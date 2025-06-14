Gophish USB Windows Agent
=======
This repository contains the Windows target agent for [GophishUSB](https://github.com/niklasent/gophishusb).

### How it works
The agent runs as a Windows service and periodically scans each mounted USB device for USB phishing flags defined by the [GophishUSB Preparation Tool](https://github.com/niklasent/gophishusb-prep).  
If such a flag is detected, a corresponding phishing event is posted to the GophishUSB instance. The target authenticates itself to the instance by using an API key, which is generated in the registration process. 

### Installation
Run the PowerShell script `setup.ps1` in order to install the GophishUSB agent locally:
```
.\setup.ps1 -AdminUrl <YOUR-GOPHISHUSB-ADMIN-URL> -PhishUrl <YOUR-GOPHISHUSB-PHISH-URL> -ApiKey <YOUR-GOPHISHUSB-API-KEY>
```
The script then guides you through the agent installation process. Doing so, the computer machine will be registered as a target machine in your GophishUSB instance.  
To uninstall the agent, run the setup script using the `-Uninstall` parameter. This will also remove the target from the GophishUSB instance.  
If you want to specify an installation path other then `C:\gophishusb-agent\`, use the parameter `-InstallPath <LOCAL-INSTALL-PATH>`.