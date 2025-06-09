package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"golang.org/x/sys/windows/svc"
	"golang.org/x/sys/windows/svc/debug"
)

var installdir = ""

type myService struct{}

type Config struct {
	TargetID     int64
	TargetApiKey string
	PhishUrl     string
}

type EventDetails struct {
	Username string `json:"username"`
	USB      string `json:"usb"`
}

func pingInstance(config Config) error {
	apiURL := config.PhishUrl + "/phish/ping/"
	req, err := http.NewRequest("GET", apiURL, nil)
	if err != nil {
		return fmt.Errorf("error sending request: %v", err)
	}
	req.Header.Set("Authorization", "Bearer "+config.TargetApiKey)
	req.Header.Set("Content-Type", "application/json")
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("error sending request: %v", err)
	}
	defer resp.Body.Close()
	return nil
}

func getUSBDiskDrives() ([]string, []string, error) {
	cmd := exec.Command("wmic", "logicaldisk", "get", "DeviceID,VolumeName")
	output, err := cmd.Output()
	if err != nil {
		return nil, nil, fmt.Errorf("error reading drive info: %v", err)
	}

	lines := strings.Split(string(output), "\n")
	var usbDrives []string
	var usbNames []string

	for _, line := range lines {
		if strings.Contains(line, "USB-") {
			fields := strings.Fields(line)
			if len(fields) > 0 {
				usbDrives = append(usbDrives, fields[0])
				usbNames = append(usbNames, fields[1])
			}
		}
	}

	return usbDrives, usbNames, nil
}

func searchDrives(config Config) error {
	usbDrives, usbNames, err := getUSBDiskDrives()
	if err != nil {
		return fmt.Errorf("fehler beim Abrufen der USB-Laufwerke: %v", err)
	}

	for i, drive := range usbDrives {
		filepath.Walk(drive, func(path string, info os.FileInfo, err error) error {
			if err != nil {
				return err
			}

			if strings.HasSuffix(info.Name(), ".gusb") {
				ed := EventDetails{}
				ed.Username = "Unknown"
				ed.USB = usbNames[i]
				eventJSON, err := json.Marshal(ed)
				if err != nil {
					return fmt.Errorf("marshal Error: %v", err)
				}
				apiURL := config.PhishUrl + "/phish/mount/"
				req, err := http.NewRequest("POST", apiURL, bytes.NewBuffer(eventJSON))
				if err != nil {
					return fmt.Errorf("error creating HTTP request: %v", err)
				}

				req.Header.Set("Authorization", "Bearer "+config.TargetApiKey)
				req.Header.Set("Content-Type", "application/json")
				client := &http.Client{}
				resp, err := client.Do(req)
				if err != nil {
					return fmt.Errorf("error sending request: %v", err)
				}
				defer resp.Body.Close()
			}

			if strings.HasSuffix(info.Name(), ".mtmp") {
				ed := EventDetails{}
				ed.Username = strings.TrimSuffix(info.Name(), ".mtmp")
				ed.USB = usbNames[i]
				eventJSON, err := json.Marshal(ed)
				if err != nil {
					return fmt.Errorf("marshal Error: %v", err)
				}
				apiURL := config.PhishUrl + "/phish/macro/"
				req, err := http.NewRequest("POST", apiURL, bytes.NewBuffer(eventJSON))
				if err != nil {
					return fmt.Errorf("error creating HTTP request: %v", err)
				}

				req.Header.Set("Authorization", "Bearer "+config.TargetApiKey)
				req.Header.Set("Content-Type", "application/json")
				client := &http.Client{}
				resp, err := client.Do(req)
				if err != nil {
					return fmt.Errorf("error sending request: %v", err)
				}
				defer resp.Body.Close()
				if resp.StatusCode == http.StatusOK {
					err := os.Remove(path)
					if err != nil {
						return fmt.Errorf("error deleting flag %s: %v", path, err)
					}
				}
			}

			if strings.HasSuffix(info.Name(), ".etmp") {
				ed := EventDetails{}
				ed.Username = strings.TrimSuffix(info.Name(), ".etmp")
				ed.USB = usbNames[i]
				eventJSON, err := json.Marshal(ed)
				if err != nil {
					return fmt.Errorf("marshal Error: %v", err)
				}
				apiURL := config.PhishUrl + "/phish/exec/"
				req, err := http.NewRequest("POST", apiURL, bytes.NewBuffer(eventJSON))
				if err != nil {
					return fmt.Errorf("error creating HTTP request: %v", err)
				}

				req.Header.Set("Authorization", "Bearer "+config.TargetApiKey)
				req.Header.Set("Content-Type", "application/json")
				client := &http.Client{}
				resp, err := client.Do(req)
				if err != nil {
					return fmt.Errorf("error sending request: %v", err)
				}
				defer resp.Body.Close()
				if resp.StatusCode == http.StatusOK {
					err := os.Remove(path)
					if err != nil {
						return fmt.Errorf("error deleting flag %s: %v", path, err)
					}
				}
			}

			return nil
		})
	}
	return nil
}

func getConfig() (Config, error) {
	// Get configuration from config.json file
	config := Config{}
	content, err := os.ReadFile(filepath.Join(installdir, "config.json"))
	if err != nil {
		log.Fatal("Error when opening file: ", err)
		return config, err
	}
	err = json.Unmarshal(content, &config)
	if err != nil {
		log.Fatal("Error during Unmarshal(): ", err)
		return config, err
	}
	return config, nil
}

func (m *myService) Execute(args []string, r <-chan svc.ChangeRequest, status chan<- svc.Status) (bool, uint32) {

	const cmdsAccepted = svc.AcceptStop | svc.AcceptShutdown | svc.AcceptPauseAndContinue
	tick := time.Tick(60 * time.Second)

	status <- svc.Status{State: svc.StartPending}

	status <- svc.Status{State: svc.Running, Accepts: cmdsAccepted}

loop:
	for {
		select {
		case <-tick:
			config, err := getConfig()
			if err != nil {
				log.Printf("Error loading config: %v", err)
				continue
			}
			if err := pingInstance(config); err != nil {
				log.Printf("Ping failed: %v", err)
				continue
			}
			if err := searchDrives(config); err != nil {
				log.Printf("Failure in phishing routine: %v", err)
			}
		case c := <-r:
			switch c.Cmd {
			case svc.Interrogate:
				status <- c.CurrentStatus
			case svc.Stop, svc.Shutdown:
				log.Print("Shutting service...!")
				break loop
			case svc.Pause:
				status <- svc.Status{State: svc.Paused, Accepts: cmdsAccepted}
			case svc.Continue:
				status <- svc.Status{State: svc.Running, Accepts: cmdsAccepted}
			default:
				log.Printf("Unexpected service control request #%d", c)
			}
		}
	}

	status <- svc.Status{State: svc.StopPending}
	return false, 1
}

func runService(name string, isDebug bool) {
	if isDebug {
		err := debug.Run(name, &myService{})
		if err != nil {
			log.Fatalln("Error running service in debug mode.")
		}
	} else {
		err := svc.Run(name, &myService{})
		if err != nil {
			log.Fatalln("Error running service in Service Control mode.")
		}
	}
}

func main() {
	flag.StringVar(&installdir, "installdir", "C:\\gophishusb-agent\\", "Installation directory of agent")
	DEBUG := false
	if DEBUG {
		f, err := os.OpenFile(filepath.Join(installdir, "config.json"), os.O_RDWR|os.O_CREATE|os.O_APPEND, 0666)
		if err != nil {
			log.Fatalln(fmt.Errorf("error opening file: %v", err))
		}
		defer f.Close()

		log.SetOutput(f)
	}
	runService("myservice", DEBUG)
}
