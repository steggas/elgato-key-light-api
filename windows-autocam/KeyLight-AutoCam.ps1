<#
  KeyLight-AutoCam.ps1 — Windows PowerShell 5.1
  Auto-toggle Elgato Key Light(s) when webcam/microphone are in use.

  Uses the device’s local HTTP API (port 9123, base /elgato) documented here:
  https://github.com/adamesch/elgato-key-light-api
  SPDX-License-Identifier: MIT
  Copyright (c) 2025 Callum Stegmann
#>

# --- SETTINGS ---
$LightIPs          = @("192.168.1.61")  # <--- your light(s) IPs
$Brightness        = 40                 # 0..100 (values below ~3 may have no visible effect)
$Kelvin            = 4000               # ~2900..7000
$PollSeconds       = 2
$UseMicAsFallback        = $false       # $true => audio-only calls also turn light on
$ActivationWindowSeconds = 9000         # treat Start as "newly active" within last N seconds
$DebugPrint              = $true        # set $false once you're happy
$ExcludeExeNames         = @()          # e.g. @("zoom") to ignore Zoom entirely if needed

function ConvertTo-Mired([double]$Kelvin){
  if($Kelvin -le 0){ throw "Kelvin must be greater than zero." }
  $raw = [Math]::Round(1000000 / $Kelvin)
  return [int]([Math]::Min([Math]::Max($raw, 143), 344))
}

# --- INIT ---
$Mired = ConvertTo-Mired -Kelvin $Kelvin
$ActiveNonPackaged = New-Object 'System.Collections.Generic.HashSet[string]'

function Set-KeyLights([bool]$On) {
  $onValue = if ($On) { 1 } else { 0 }
  $payload = @{
    numberOfLights = 1
    lights = @(@{ on=$onValue; brightness=$Brightness; temperature=$Mired })
  } | ConvertTo-Json -Depth 4

  foreach ($ip in $LightIPs) {
    $url = "http://{0}:9123/elgato/lights" -f $ip
    try {
      Invoke-RestMethod -Method Put -Uri $url -ContentType "application/json" -Body $payload | Out-Null
      if ($DebugPrint) { Write-Host "Sent to $ip → on=$onValue, b=$Brightness, t=$Mired" }
    } catch {
      if ($DebugPrint) { Write-Host "Failed to reach $ip : $_" }
    }
  }
}

function To-DateTime([UInt64]$ft){
  if($ft -eq 0){ return $null }
  try { return [DateTime]::FromFileTimeUtc([Int64]$ft) } catch { return $null }
}

function Process-Exists([string]$exePath){
  $name = [IO.Path]::GetFileNameWithoutExtension($exePath)
  if([string]::IsNullOrEmpty($name)){ return $false }
  if($ExcludeExeNames -contains $name.ToLowerInvariant()){ return $false }
  try { return $null -ne (Get-Process -Name $name -ErrorAction SilentlyContinue) } catch { return $false }
}

function Test-CapabilityInUse([string]$capability){
  $now = [DateTime]::UtcNow
  $anyActive = $false

  # ---- NonPackaged (classic desktop apps) ----
  $baseNP = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\$capability\NonPackaged"
  if(Test-Path $baseNP){
    foreach($k in (Get-ChildItem -Path $baseNP -ErrorAction SilentlyContinue)){
      $p = $null; try { $p = Get-ItemProperty -Path $k.PSPath -ErrorAction SilentlyContinue } catch {}
      if(-not $p){ continue }

      $start = To-DateTime([UInt64]($p.LastUsedTimeStart)); $stop = To-DateTime([UInt64]($p.LastUsedTimeStop))
      $exePath = ($k.PSChildName -replace '#','\')
      $exeName = ([IO.Path]::GetFileNameWithoutExtension($exePath)).ToLowerInvariant()
      $procRunning = Process-Exists $exePath

      if(-not $procRunning){ [void]$ActiveNonPackaged.Remove($exeName) }

      $isCandidate = $procRunning -and $start -and ( ($stop -eq $null) -or ($start -gt $stop) )
      if($isCandidate){
        if($ActiveNonPackaged.Contains($exeName) -or ($now - $start).TotalSeconds -le $ActivationWindowSeconds){
          [void]$ActiveNonPackaged.Add($exeName)
          $anyActive = $true
        }
      }
    }
  }

  # ---- Packaged apps (UWP) – conservative new-activation check ----
  $basePKG = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\$capability"
  if(Test-Path $basePKG){
    foreach($k in (Get-ChildItem -Path $basePKG -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "*\NonPackaged\*" })){
      $p = $null; try { $p = Get-ItemProperty -Path $k.PSPath -ErrorAction SilentlyContinue } catch {}
      if(-not $p){ continue }
      $start = To-DateTime([UInt64]($p.LastUsedTimeStart)); $stop = To-DateTime([UInt64]($p.LastUsedTimeStop))
      if($start -and (($stop -eq $null) -or ($start -gt $stop))){
        if(($now - $start).TotalSeconds -le $ActivationWindowSeconds){
          $anyActive = $true
        }
      }
    }
  }

  return $anyActive
}

function CameraOrMicInUse {
  if(Test-CapabilityInUse 'webcam'){ return $true }
  if($UseMicAsFallback -and (Test-CapabilityInUse 'microphone')){ return $true }
  return $false
}

# --- MAIN LOOP ---
function Start-KeyLightAutoCam {
  $last = $false
  while($true){
    $active = CameraOrMicInUse
    if($active -ne $last){
      if($DebugPrint){ Write-Host ("State changed: {0} @ {1}" -f $active,(Get-Date)) }
      Set-KeyLights $active
      $last = $active
    }
    Start-Sleep -Seconds $PollSeconds
  }
}

if($MyInvocation.InvocationName -ne '.'){
  Start-KeyLightAutoCam
}
