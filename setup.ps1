#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Setup script for the Gophish USB Windows agent.

.DESCRIPTION
    This script installs the Gophish USB Windows agent.

.EXAMPLE
    setup.ps1 -InstallPath C:\gophishusb-agent\ -AdminUrl https://yourgophishusbserver.com:3333 -PhishUrl https://yourgophishusbserver.com -ApiKey <yourapikey>

.EXAMPLE
    setup.ps1 -InstallPath C:\gophishusb-agent\ -ApiKey <yourapikey> -Uninstall

.AUTHOR
    Niklas Entschladen

.LICENSE
    MIT License

    Copyright (c) 2025 Niklas Entschladen

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
#>

param (
    [Parameter(Mandatory=$true)]
    [string]$ApiKey,
    [Parameter(Mandatory=$true)]
    [string]$AdminUrl,
    [string]$PhishUrl,
    [string]$InstallPath,
    [switch]$Uninstall
)

##### Initialize global variables ans parameters #####
if (-not $PSBoundParameters.ContainsKey('Installpath')) {
    $InstallPath = "C:\gophishusb-agent\"
}
else {
    if ($InstallPath -notmatch '[\\]$') {
        $InstallPath = $InstallPath + "\"
    }
}
if ($AdminUrl -notmatch '[\/]$') {
    $AdminUrl = $AdminUrl + "/"
}
$API_URL = $AdminUrl + "api/"
$WinSrvName = "GophishUSBAgent"

$ErrorActionPreference = "Stop";
######################################################

function InvokeAPICall {
    param (
        [string]$method,
        [string]$path,
        [PSCustomObject]$body = @{}
    )

    $headers = @{
        "Authorization" = "Bearer $ApiKey"
        "Content-Type" = "application/json"
    }
    $url = $API_URL + $path
    
    try {
        if ($method -in @("POST", "PUT", "PATCH")) {
            $response = Invoke-RestMethod -Uri $url -Headers $headers -Method $method -Body $body
        }
        else {
            $response = Invoke-RestMethod -Uri $url -Headers $headers -Method $method
        }
        return $response
    }
    catch {
        Write-Error "Error in HTTP request to $($url):"
        Write-Error "Exception: $($_.Exception.Message)"
    }
    
}

function ObtainTargetGroup {
    param (
        [array]$groups
    )

    $choice = Read-Host "Please provide ID of target group (enter q to quit)"
    if ($choice.ToLower() -eq 'q') {
        exit
    }

    foreach ($group in $groups) {
        if ($group.id -eq $choice) {
            return $group
        }
    }

    Write-Warning "Group with ID $($choice) not found!"
    ObtainTargetGroup -groups $groups
}

function RegisterTarget {
    param (
        [int]$groupID
    )

    # Obtain necessary target information
    $hostname = $($env:COMPUTERNAME)
    $os = (Get-CimInstance -ClassName CIM_OperatingSystem).Caption 

    $body = @{  
        "group_id" = $groupID
        "hostname" = $hostname
        "os" = $os
    }

    # Call API to register target
    $body = $body | ConvertTo-Json
    $target = InvokeAPICall -method "POST" -path "targets/" -body $body
    Write-Verbose $target
    return $target
}

function UnregisterTarget {
    param (
        [int]$targetID
    )

    # Call API to register target
    InvokeAPICall -method "DELETE" -path "targets/$($targetID)"
    return
}

# Check uninstall option
if ($Uninstall) {
    # Check Windows service
    $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$WinSrvName'"
    if (-not $service) {
        Write-Error "Cannot find agent service '$($WinSrvName)'."
    }

    # Determine configuration file path by InstallPath or service location
    $configFilePath = ""
    if (-not $PSBoundParameters.ContainsKey('Installpath')) {
        $servicePath = [System.IO.Path]::GetDirectoryName($service.PathName)
        $exeIndex = $servicePath.IndexOf("\gophishusb-agent.exe")
        $InstallPath = $servicePath.Substring(0, $exeIndex)
    }
    $configFilePath = $InstallPath + "\config.json"
    if (-not (Test-Path $configFilePath)) {
        Write-Error "Could not find configuration file at $($configFilePath)."
    }
    $config = Get-Content -Path $configFilePath -Raw | ConvertFrom-Json

    # Unregister target from Gophish USB instance
    UnregisterTarget -targetID $config.target_info.id

    # Stop and uninstall running service
    try {
        sc.exe stop $WinSrvName
        sc.exe delete $WinSrvName
        Start-Sleep -Seconds 2  # Wait for service to be removed before deleting the executable.
    }
    catch {
        Write-Error "Error uninstalling service."
    }

    # Remove GophishUSB agent files
    try {
        Remove-Item -LiteralPath $InstallPath -Force -Recurse
    }
    catch {
        Write-Error "Error removing GophishUSB agent files."
    }
    Write-Host "Successfully uninstalled agent." -ForegroundColor Green

    exit
}

# STEP 1: Obtain and select target group
Write-Host "`nSearching for target groups..." -ForegroundColor Blue
try {
    $groups = InvokeAPICall -path "groups/" -method "GET"
}
catch {
    Write-Error "Error in HTTP request to $($url):"
    Write-Error "Exception: $($_.Exception.Message)" 
}
if ($groups.Count -eq 0) {
    Write-Error "No valid groups found! Aborting."
}
$groups | Format-Table id, name
$group = ObtainTargetGroup -groups $groups

# STEP 2: Register target to group
Write-Host "`nRegistering target $($env:COMPUTERNAME) to group '$($group.name)'..." -ForegroundColor Blue
$target = RegisterTarget -groupID $group.id

# STEP 3: Create agent configuration file
$config = @{
    "TargetID" = $target.id
    "TargetApiKey" = $target.api_key
    "PhishURL" = $PhishUrl
}

$configJSON = $config | ConvertTo-Json -Depth 2
$configJSON | Out-File -FilePath 'config.json' -Encoding ascii

if (-not $PSBoundParameters.ContainsKey('PhishUrl')) {
    Write-Warning "No phishing URL provided. Please insert phishing URL manually in configuration file for the agent to be active."
}
else {
    if ($PhishUrl -notmatch '[\/]$') {
        $PhishUrl = $PhishUrl + "/"
    }
}

# STEP 4: Complle agent source code if not present
if (Test-Path (Join-Path $PWD "bin/gophishusb-agent.exe")) {
    Write-Host "Agent executable found."
}
else {
    Write-Host "Cannot find agent executable. Building from source..." -ForegroundColor Blue
    # Check for golang installation
    try {
        $goVersion = & go version
        Write-Host "Go installation found:" -ForegroundColor Green
        Write-Host "$goVersion"
    } catch {
        Write-Host "Go installation not found. Please install Go and rerun the installation script after." -ForegroundColor Red
        Write-Host "https://go.dev/dl/"
        exit
    }
    Set-Location "$(Join-Path $PWD "src")"
    go get .
    go build -o "$(Join-Path $PWD "../bin/gophishusb-agent.exe")" "$(Join-Path $PWD "gophishusb-agent.go")"
    Set-Location "$(Join-Path $PWD "..")"
}

Write-Host "`nRegistering target $($env:COMPUTERNAME) to group '$($group.name)'..." -ForegroundColor Blue

# STEP 5: Copy files and install agent as Windows service
if (-not (Test-Path -Path $InstallPath)) {
    New-Item -ItemType Directory -Path $InstallPath
}

Copy-Item -Path "bin/gophishusb-agent.exe" -Destination $InstallPath -Force
Move-Item -Path "config.json" -Destination $InstallPath -Force

try {
    sc.exe create $WinSrvName binPath="$(Join-Path $InstallPath "gophishusb-agent.exe") -installdir='$($InstallPath)'" start=auto
    sc.exe start $WinSrvName
    Write-Host "Successfully installed agent." -ForegroundColor Green
}
catch {
    Write-Error "Error installing agent."
}
