# Windows Auto-Toggle for Elgato Key Light (PowerShell 5.1)

This example script turns Elgato Key Light(s) **on** when your webcam (or mic, optional) is in use, and **off** when it isn’t.  
It uses the device’s local HTTP API (port **9123**, base path **/elgato**) documented in this repository. No authentication is required.  
Tested on Windows 10/11 with PowerShell 5.1.  

## Setup
1. In Elgato **Control Center**, open *Accessory settings → Advanced* and note the IP address of each light.
2. Edit `KeyLight-AutoCam.ps1`:
   - Set `$LightIPs = @("192.168.x.x", "…")`
   - Optionally change `$Brightness`, `$Kelvin` (Kelvin is converted to **mireds** internally).
3. Run once from PowerShell:
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File .\KeyLight-AutoCam.ps1
