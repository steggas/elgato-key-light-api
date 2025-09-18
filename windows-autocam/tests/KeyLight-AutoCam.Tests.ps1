$scriptPath = Join-Path $PSScriptRoot '..' 'KeyLight-AutoCam.ps1'
. $scriptPath

Describe 'ConvertTo-Mired' {
  It 'rounds Kelvin to the nearest supported mired value' {
    ConvertTo-Mired -Kelvin 7000 | Should -Be 143
  }

  It 'clamps the calculated value to the supported range' {
    ConvertTo-Mired -Kelvin 8000 | Should -Be 143
    ConvertTo-Mired -Kelvin 2000 | Should -Be 344
  }
}

Describe 'Set-KeyLights' {
  BeforeEach {
    $script:LightIPs = @('10.0.0.5')
    $script:Brightness = 25
    $script:Kelvin = 7000
    $script:Mired = ConvertTo-Mired -Kelvin $script:Kelvin
    $script:DebugPrint = $false
  }

  It 'sends a payload with the expected state and configuration' {
    $captured = @()
    Mock -CommandName Invoke-RestMethod -MockWith {
      param(
        [Parameter(Mandatory=$true)]$Method,
        [Parameter(Mandatory=$true)]$Uri,
        [Parameter(Mandatory=$true)]$ContentType,
        [Parameter(Mandatory=$true)]$Body
      )

      $script:captured += [pscustomobject]@{
        Method      = $Method
        Uri         = $Uri
        ContentType = $ContentType
        Body        = $Body
      }
    }

    Set-KeyLights -On $true

    $captured.Count | Should -Be 1
    $captured[0].Method | Should -Be 'Put'
    $captured[0].Uri | Should -Be 'http://10.0.0.5:9123/elgato/lights'
    $captured[0].ContentType | Should -Be 'application/json'

    $payload = $captured[0].Body | ConvertFrom-Json
    $payload.numberOfLights | Should -Be 1
    $payload.lights | Should -HaveCount 1
    $payload.lights[0].on | Should -Be 1
    $payload.lights[0].brightness | Should -Be 25
    $payload.lights[0].temperature | Should -Be 143
  }

  It 'turns the light off when requested' {
    $offPayload = $null
    Mock -CommandName Invoke-RestMethod -MockWith {
      param(
        [Parameter(Mandatory=$true)]$Method,
        [Parameter(Mandatory=$true)]$Uri,
        [Parameter(Mandatory=$true)]$ContentType,
        [Parameter(Mandatory=$true)]$Body
      )

      $script:offPayload = $Body | ConvertFrom-Json
    }

    Set-KeyLights -On $false

    $offPayload.lights[0].on | Should -Be 0
  }
}
