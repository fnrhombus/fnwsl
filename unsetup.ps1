# fnwsl teardown - reverses everything setup.ps1 did
# Run from elevated PowerShell:
#   .\unsetup.ps1
#   .\unsetup.ps1 -WslName "metis-wsl"
#   .\unsetup.ps1 -RemoveWslConfig    # force roll back .wslconfig even if other instances exist
#   .\unsetup.ps1 -KeepWslConfig      # always keep .wslconfig unchanged
#
# Fully non-interactive:
#   .\unsetup.ps1 -WslName "metis-wsl" -Force

[CmdletBinding(DefaultParameterSetName = "Auto")]
param(
    [string]$WslName,
    [Parameter(ParameterSetName = "KeepConfig")]
    [switch]$KeepWslConfig,
    [Parameter(ParameterSetName = "RemoveConfig")]
    [switch]$RemoveWslConfig,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Show-CheckboxMenu {
    param(
        [string]$Title,
        [string[]]$Items
    )

    $selected = [bool[]]::new($Items.Count)
    $cursor = 0

    [Console]::CursorVisible = $false
    try {
        Write-Host ""
        Write-Host $Title -ForegroundColor Yellow
        $startTop = [Console]::CursorTop
        for ($i = 0; $i -lt $Items.Count + 2; $i++) { Write-Host "" }

        while ($true) {
            [Console]::SetCursorPosition(0, $startTop)
            for ($i = 0; $i -lt $Items.Count; $i++) {
                $check = if ($selected[$i]) { "x" } else { " " }
                $prefix = if ($i -eq $cursor) { ">" } else { " " }
                $color = if ($i -eq $cursor) { "Cyan" } else { "Gray" }
                Write-Host ("$prefix [$check] $($Items[$i])".PadRight([Console]::WindowWidth - 1)) -ForegroundColor $color
            }
            Write-Host ""
            Write-Host "  Up/Down = navigate, Space = toggle, Enter = confirm" -ForegroundColor DarkGray

            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                "UpArrow"   { if ($cursor -gt 0) { $cursor-- } }
                "DownArrow" { if ($cursor -lt $Items.Count - 1) { $cursor++ } }
                "Spacebar"  { $selected[$cursor] = -not $selected[$cursor] }
                "Enter"     {
                    Write-Host ""
                    $result = @()
                    for ($i = 0; $i -lt $Items.Count; $i++) {
                        if ($selected[$i]) { $result += $Items[$i] }
                    }
                    return $result
                }
            }
        }
    } finally {
        [Console]::CursorVisible = $true
    }
}

# --- Ensure running as admin ---
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: Run this script from an elevated PowerShell." -ForegroundColor Red
    exit 1
}

Write-Host "=== fnwsl teardown ===" -ForegroundColor Cyan

# --- Load tracker for instance picker ---
$fnwslTracker = "$env:USERPROFILE\.fnwsl"
$wslconfigPath = "$env:USERPROFILE\.wslconfig"

$trackerData = $null
if (Test-Path $fnwslTracker) {
    $trackerData = Get-Content $fnwslTracker -Raw | ConvertFrom-Json
}

# --- Select instances to remove ---
$selectedNames = @()
if ($WslName) {
    $selectedNames = @($WslName)
} else {
    # Gather known names from tracker and installed WSL distros
    $knownNames = [System.Collections.Generic.List[string]]::new()
    if ($trackerData -and $trackerData.instances) {
        foreach ($name in $trackerData.instances.PSObject.Properties.Name) {
            $knownNames.Add($name)
        }
    }
    $distroOutput = (wsl -l -q 2>$null) -join "`n" -replace "`0",""
    foreach ($line in $distroOutput -split "`n") {
        $distro = $line.Trim()
        if ($distro -and $distro -ne "docker-desktop" -and $distro -ne "docker-desktop-data" -and -not $knownNames.Contains($distro)) {
            $knownNames.Add($distro)
        }
    }

    if ($knownNames.Count -eq 0) {
        Write-Host ""
        Write-Host "No fnwsl instances found." -ForegroundColor DarkGray
        exit 0
    } elseif ($knownNames.Count -eq 1) {
        $selectedNames = @($knownNames[0])
        Write-Host ""
        Write-Host "Found instance: $($knownNames[0])" -ForegroundColor Yellow
    } elseif ($Force) {
        Write-Host "ERROR: -Force requires -WslName when multiple instances exist." -ForegroundColor Red
        exit 1
    } else {
        $selectedNames = @(Show-CheckboxMenu -Title "Select instances to remove:" -Items $knownNames.ToArray())
        if ($selectedNames.Count -eq 0) {
            Write-Host "No instances selected." -ForegroundColor DarkGray
            exit 0
        }
    }
}

# --- Process each selected instance ---
foreach ($WslName in $selectedNames) {
    if ($selectedNames.Count -gt 1) {
        Write-Host ""
        Write-Host "--- $WslName ---" -ForegroundColor Cyan
    }

    # Reload tracker (may have been modified by previous iteration)
    $tracker = $null
    $instanceData = $null
    if (Test-Path $fnwslTracker) {
        $tracker = Get-Content $fnwslTracker -Raw | ConvertFrom-Json
        if ($tracker.instances -and ($tracker.instances.PSObject.Properties.Name -contains $WslName)) {
            $instanceData = $tracker.instances.$WslName
        }
    }

    if (-not $instanceData) {
        Write-Host ""
        Write-Host "WARNING: No tracker record found for '$WslName'." -ForegroundColor DarkYellow
        Write-Host "  .wslconfig settings will not be rolled back." -ForegroundColor DarkGray
    }

    # Determine remaining instances
    $remainingInstances = @()
    if ($tracker -and $tracker.instances) {
        $remainingInstances = @($tracker.instances.PSObject.Properties.Name | Where-Object { $_ -ne $WslName })
    }
    $isLastInstance = $remainingInstances.Count -eq 0

    # --- Interview phase: .wslconfig rollback decisions ---
    $rollbackDecisions = @{}
    $hasTrackedSettings = ($null -ne $instanceData) -and ($null -ne $instanceData.wslconfig)
    $willDeleteFile = (-not $KeepWslConfig) -and $isLastInstance -and $tracker -and (-not $tracker.wslconfigExisted)

    if (-not $KeepWslConfig -and -not $RemoveWslConfig -and -not $willDeleteFile -and $hasTrackedSettings) {
        $currentValues = @{}
        if (Test-Path $wslconfigPath) {
            $existingLines = Get-Content $wslconfigPath
            $inWsl2 = $false
            foreach ($line in $existingLines) {
                $trimmed = $line.Trim()
                if ($trimmed -match '^\[') { $inWsl2 = $trimmed -eq '[wsl2]' }
                elseif ($inWsl2 -and $trimmed -match '^(\w+)\s*=\s*(.+)$') {
                    $currentValues[$Matches[1]] = $Matches[2].Trim()
                }
            }
        }

        foreach ($key in $instanceData.wslconfig.PSObject.Properties.Name) {
            $change = $instanceData.wslconfig.$key
            $fromVal = $change.from
            $toVal = $change.to
            $currentVal = if ($currentValues.ContainsKey($key)) { $currentValues[$key] } else { $null }

            $neededByOther = $false
            foreach ($otherName in $remainingInstances) {
                $otherData = $tracker.instances.$otherName
                if ($otherData.wslconfig -and ($otherData.wslconfig.PSObject.Properties.Name -contains $key)) {
                    $neededByOther = $true
                    break
                }
            }

            if ($neededByOther) {
                $rollbackDecisions[$key] = "propagate"
            } elseif ($currentVal -eq $toVal) {
                $rollbackDecisions[$key] = "rollback"
            } elseif ($Force) {
                $rollbackDecisions[$key] = "rollback"
            } else {
                $fromDisplay = if ($null -ne $fromVal) { $fromVal } else { "(not set)" }
                $currentDisplay = if ($null -ne $currentVal) { $currentVal } else { "(not set)" }
                Write-Host ""
                Write-Host "  .wslconfig: $key has an unexpected value" -ForegroundColor Yellow
                Write-Host "    fnwsl set it from $fromDisplay to $toVal during setup" -ForegroundColor DarkGray
                Write-Host "    It is currently: $currentDisplay" -ForegroundColor DarkGray
                Write-Host ""
                if ($null -ne $fromVal) {
                    Write-Host "    [R] Roll back to $fromVal (pre-fnwsl value)" -ForegroundColor DarkGray
                } else {
                    Write-Host "    [R] Remove setting (was not set before fnwsl)" -ForegroundColor DarkGray
                }
                Write-Host "    [K] Keep current value ($currentDisplay)" -ForegroundColor DarkGray
                $answer = Read-Host "    Choice (R/k)"
                if ($answer -match '^[Kk]') {
                    $rollbackDecisions[$key] = "keep"
                } else {
                    $rollbackDecisions[$key] = "rollback"
                }
            }
        }
    }

    # --- Confirmation ---
    Write-Host ""
    Write-Host "This will:" -ForegroundColor Yellow
    Write-Host "  - Unregister '$WslName' WSL distro (deletes all data inside it)"
    Write-Host "  - Remove WSL/Ubuntu profiles from Windows Terminal"

    if ($KeepWslConfig) {
        Write-Host "  - .wslconfig: keep unchanged (-KeepWslConfig)" -ForegroundColor DarkGray
    } elseif ($willDeleteFile) {
        Write-Host "  - .wslconfig: delete (did not exist before fnwsl)"
    } elseif ($RemoveWslConfig -and $hasTrackedSettings) {
        foreach ($key in $instanceData.wslconfig.PSObject.Properties.Name) {
            $fromVal = $instanceData.wslconfig.$key.from
            $fromDisplay = if ($null -ne $fromVal) { "restore to $fromVal" } else { "remove" }
            Write-Host "  - .wslconfig ${key}: $fromDisplay (forced)"
        }
    } elseif ($rollbackDecisions.Count -gt 0) {
        foreach ($key in $rollbackDecisions.Keys) {
            $decision = $rollbackDecisions[$key]
            if ($decision -eq "rollback") {
                $fromVal = $instanceData.wslconfig.$key.from
                $fromDisplay = if ($null -ne $fromVal) { "restore to $fromVal" } else { "remove" }
                Write-Host "  - .wslconfig ${key}: $fromDisplay"
            } elseif ($decision -eq "keep") {
                Write-Host "  - .wslconfig ${key}: keep current value" -ForegroundColor DarkGray
            } elseif ($decision -eq "propagate") {
                Write-Host "  - .wslconfig ${key}: keep (needed by other fnwsl instance)" -ForegroundColor DarkGray
            }
        }
    } else {
        Write-Host "  - .wslconfig: no changes" -ForegroundColor DarkGray
    }

    if (-not $Force) {
        Write-Host ""
        $confirm = Read-Host "Continue? (Y/n)"
        if ($confirm -match '^[Nn]') {
            Write-Host "Aborted." -ForegroundColor DarkGray
            if ($selectedNames.Count -gt 1) { continue } else { exit 0 }
        }
        Write-Host ""
        Write-Host "The rest of the teardown is non-interactive." -ForegroundColor Green
    }

    # --- Unregister WSL distro ---
    $distroList = @((wsl -l -q 2>$null) -join "`n" -replace "`0","" -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($WslName -in $distroList) {
        Write-Host ""
        Write-Host "Unregistering '$WslName' WSL distro..." -ForegroundColor Yellow
        wsl --unregister "$WslName"
        Write-Host "  Done." -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "No '$WslName' distro found, skipping." -ForegroundColor DarkGray
    }

    # --- Handle .wslconfig ---
    $settingsToRollback = @{}

    if (-not $KeepWslConfig -and $hasTrackedSettings) {
        if ($willDeleteFile) {
            # Handled below - delete entire file
        } elseif ($RemoveWslConfig) {
            foreach ($key in $instanceData.wslconfig.PSObject.Properties.Name) {
                $settingsToRollback[$key] = $instanceData.wslconfig.$key.from
            }
        } else {
            foreach ($key in $rollbackDecisions.Keys) {
                if ($rollbackDecisions[$key] -eq "rollback") {
                    $settingsToRollback[$key] = $instanceData.wslconfig.$key.from
                }
            }
        }
    }

    if ($willDeleteFile) {
        if (Test-Path $wslconfigPath) {
            Write-Host ""
            Write-Host "Removing .wslconfig (did not exist before fnwsl)..." -ForegroundColor Yellow
            Remove-Item $wslconfigPath
            Write-Host "  Done." -ForegroundColor Green
        }
    } elseif ($settingsToRollback.Count -gt 0 -and (Test-Path $wslconfigPath)) {
        Write-Host ""
        Write-Host "Rolling back .wslconfig settings..." -ForegroundColor Yellow
        $lines = [System.Collections.ArrayList]@(Get-Content $wslconfigPath)
        $inWsl2 = $false
        $removeIndices = @()

        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i].Trim()
            if ($line -match '^\[') {
                $inWsl2 = $line -eq '[wsl2]'
            } elseif ($inWsl2 -and $line -match '^(\w+)\s*=') {
                $key = $Matches[1]
                if ($settingsToRollback.ContainsKey($key)) {
                    $fromVal = $settingsToRollback[$key]
                    if ($null -ne $fromVal) {
                        $lines[$i] = "$key=$fromVal"
                        Write-Host "  Restored $key=$fromVal" -ForegroundColor Green
                    } else {
                        $removeIndices += $i
                        Write-Host "  Removed $key (was not set before fnwsl)" -ForegroundColor Green
                    }
                }
            }
        }

        $removeIndices | Sort-Object -Descending | ForEach-Object { $lines.RemoveAt($_) }

        $wsl2Empty = $true
        $wsl2HeaderIndex = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i].Trim()
            if ($line -eq '[wsl2]') {
                $wsl2HeaderIndex = $i
            } elseif ($wsl2HeaderIndex -ge 0 -and $line -match '^\[') {
                break
            } elseif ($wsl2HeaderIndex -ge 0 -and $line -match '^\w+\s*=') {
                $wsl2Empty = $false
                break
            }
        }
        if ($wsl2Empty -and $wsl2HeaderIndex -ge 0) {
            $lines.RemoveAt($wsl2HeaderIndex)
        }

        $hasContent = $false
        foreach ($l in $lines) {
            if ($l.Trim() -ne "") { $hasContent = $true; break }
        }
        if (-not $hasContent) {
            Remove-Item $wslconfigPath
            Write-Host "  .wslconfig was empty, removed." -ForegroundColor Green
        } else {
            $lines | Set-Content -Path $wslconfigPath -Encoding UTF8
        }
    }

    # --- Propagate "from" values to remaining instances ---
    if (-not $RemoveWslConfig -and $hasTrackedSettings -and $remainingInstances.Count -gt 0) {
        foreach ($key in $rollbackDecisions.Keys) {
            if ($rollbackDecisions[$key] -eq "propagate") {
                $myFrom = $instanceData.wslconfig.$key.from
                $myTo = $instanceData.wslconfig.$key.to
                foreach ($otherName in $remainingInstances) {
                    $otherData = $tracker.instances.$otherName
                    if ($otherData.wslconfig -and ($otherData.wslconfig.PSObject.Properties.Name -contains $key)) {
                        if ($otherData.wslconfig.$key.from -eq $myTo) {
                            $otherData.wslconfig.$key.from = $myFrom
                        }
                    }
                }
            }
        }
    }

    # --- Update tracker ---
    if ($tracker -and $tracker.instances) {
        $tracker.instances.PSObject.Properties.Remove($WslName)
        if ($isLastInstance) {
            Remove-Item $fnwslTracker -ErrorAction SilentlyContinue
        } else {
            $tracker | ConvertTo-Json -Depth 10 | Set-Content $fnwslTracker -Encoding UTF8
        }
    }

    # --- Remove WSL profiles from Windows Terminal ---
    $wtSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    if (Test-Path $wtSettingsPath) {
        $settings = Get-Content $wtSettingsPath -Raw | ConvertFrom-Json
        $before = $settings.profiles.list.Count
        $distroList = @((wsl -l -q 2>$null) -join "`n" -replace "`0","" -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $settings.profiles.list = @($settings.profiles.list | Where-Object {
            if ($_.name -eq $WslName) { return $false }
            # Remove orphaned WSL profiles (distro no longer exists)
            if ($_.source -match "Microsoft\.WSL|Windows\.Terminal\.Wsl" -and $_.name -notin $distroList) { return $false }
            return $true
        })
        $removed = $before - $settings.profiles.list.Count
        if ($removed -gt 0) {
            Write-Host ""
            Write-Host "Removing $removed WSL profile(s) from Windows Terminal..." -ForegroundColor Yellow
            $settings | ConvertTo-Json -Depth 10 | Set-Content $wtSettingsPath -Encoding UTF8
            Write-Host "  Done." -ForegroundColor Green
        } else {
            Write-Host ""
            Write-Host "No WSL profiles found in Windows Terminal, skipping." -ForegroundColor DarkGray
        }
    } else {
        Write-Host ""
        Write-Host "Windows Terminal settings not found, skipping." -ForegroundColor DarkGray
    }
}

# --- Done ---
Write-Host ""
Write-Host "=== Teardown complete ===" -ForegroundColor Cyan
Write-Host ""
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Write-Host "To reinstall: gsudo pwsh $scriptDir\setup.ps1" -ForegroundColor White
