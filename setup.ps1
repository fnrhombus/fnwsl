# fnwsl Windows-side setup
# Run from elevated PowerShell (interactive - prompts for missing args):
#   .\setup.ps1
#
# Or fully non-interactive:
#   .\setup.ps1 -WslUsername tom -Passphrase "mypassphrase"
#
# With custom WSL name (defaults to {hostname}-wsl):
#   .\setup.ps1 -WslUsername tom -Passphrase "mypassphrase" -WslName "dev-wsl"
#
# Let Powerlevel10k wizard run instead of using default config:
#   .\setup.ps1 -P10kWizard
#
# Forward specific Windows env vars to WSL (non-interactive):
#   .\setup.ps1 -WslUsername tom -Passphrase "mypassphrase" -WslEnv GH_TOKEN,GOPATH
#
# Control default WSL distro:
#   .\setup.ps1 -WslUsername tom -Passphrase "mypassphrase" -SetDefault $true
#
# Or one-liner (from elevated PowerShell):
#   irm https://github.com/fnrhombus/fnwsl/releases/latest/download/setup.ps1 | iex

param(
    [string]$WslUsername,
    [string]$Passphrase,
    [string]$WslName,
    [switch]$P10kWizard,
    [string[]]$WslEnv,
    [Nullable[bool]]$SetDefault
)

$ErrorActionPreference = "Stop"

function Assert-ExitCode {
    param([string]$Message)
    if ($LASTEXITCODE -ne 0) {
        throw "ERROR: $Message (exit code $LASTEXITCODE)"
    }
}

function Show-CheckboxList {
    param(
        [Parameter(Mandatory)][array]$Items,
        [string]$Title = "Select items"
    )
    if ($Items.Count -eq 0) { return }

    $cursor = 0
    $offset = 0
    $pageSize = [Math]::Min($Items.Count, [Console]::WindowHeight - 8)
    [Console]::CursorVisible = $false
    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan
    Write-Host "  [Space] toggle  [A] all  [N] none  [Enter] confirm  [Esc] skip" -ForegroundColor DarkGray
    Write-Host ""
    $listTop = [Console]::CursorTop

    try {
        while ($true) {
            [Console]::SetCursorPosition(0, $listTop)
            $end = [Math]::Min($offset + $pageSize, $Items.Count)
            for ($i = $offset; $i -lt $end; $i++) {
                $item = $Items[$i]
                $check = if ($item.Checked) { "x" } else { " " }
                $arrow = if ($i -eq $cursor) { ">" } else { " " }
                $val = $item.Value
                if ($val.Length -gt 40) { $val = $val.Substring(0, 37) + "..." }
                $line = " $arrow [$check] $($item.Name) = $val"
                $line = $line.PadRight([Console]::WindowWidth - 1)
                if ($i -eq $cursor) {
                    Write-Host $line -ForegroundColor Yellow
                } else {
                    Write-Host $line
                }
            }
            if ($Items.Count -gt $pageSize) {
                $scrollHint = "  ($($offset + 1)-$end of $($Items.Count))"
                Write-Host $scrollHint.PadRight([Console]::WindowWidth - 1) -ForegroundColor DarkGray
            }

            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow'   { if ($cursor -gt 0) { $cursor--; if ($cursor -lt $offset) { $offset = $cursor } } }
                'DownArrow' { if ($cursor -lt $Items.Count - 1) { $cursor++; if ($cursor -ge $offset + $pageSize) { $offset++ } } }
                'Spacebar'  { $Items[$cursor].Checked = -not $Items[$cursor].Checked }
                'A'         { $Items | ForEach-Object { $_.Checked = $true } }
                'N'         { $Items | ForEach-Object { $_.Checked = $false } }
                'Escape'    { return $false }
                'Enter'     { return $true }
            }
        }
    } finally {
        [Console]::CursorVisible = $true
    }
}

# --- Ensure running as admin ---
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: Run this script from an elevated PowerShell." -ForegroundColor Red
    return
}

Write-Host "=== fnwsl Windows setup ===" -ForegroundColor Cyan

# --- Prompt for missing arguments ---
$defaultWslName = "$($env:COMPUTERNAME.ToLower())-wsl"
if (-not $WslName) {
    $WslName = Read-Host "WSL name (default: $defaultWslName)"
    if (-not $WslName) { $WslName = $defaultWslName }
}

# --- Validate WslName is not already in use ---
if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
    $existingDistros = @((wsl -l -q 2>$null) -join "`n" -replace "`0","" -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($WslName -in $existingDistros) {
        Write-Host "ERROR: A WSL distro named '$WslName' already exists." -ForegroundColor Red
        return
    }
}
if (Test-Path "$env:USERPROFILE\.fnwsl") {
    $existing = Get-Content "$env:USERPROFILE\.fnwsl" -Raw | ConvertFrom-Json
    if ($existing.instances -and ($existing.instances.PSObject.Properties.Name -contains $WslName)) {
        Write-Host "ERROR: '$WslName' already exists in the fnwsl tracker." -ForegroundColor Red
        return
    }
}

if (-not $WslUsername) {
    $defaultUsername = ($env:USERNAME ?? $env:USER).ToLower()
    $WslUsername = Read-Host "WSL username (default: $defaultUsername)"
    if (-not $WslUsername) { $WslUsername = $defaultUsername }
}
if (-not $PSBoundParameters.ContainsKey('Passphrase')) {
    $securePass = Read-Host "Passphrase for WSL password and SSH key (blank for none)" -AsSecureString
    $Passphrase = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass))
}
if ($null -eq $SetDefault) {
    $currentDefault = ((wsl -l 2>$null) -join "`n" -replace "`0","" -split "`n" | Where-Object { $_ -match '\(Default\)' }) -replace '\s*\(Default\)','' | ForEach-Object { $_.Trim() }
    if ($currentDefault -and $currentDefault -ne $WslName) {
        $answer = Read-Host "Set '$WslName' as default WSL distro? Current default: '$currentDefault' (Y/n)"
        $SetDefault = -not ($answer -match '^[Nn]')
    } else {
        $SetDefault = $true
    }
}
Write-Host ""
Write-Host "  WSL name:   $WslName" -ForegroundColor DarkGray
Write-Host "  Username:   $WslUsername" -ForegroundColor DarkGray
Write-Host "  Passphrase: $(if ($Passphrase) { '****' } else { '(none)' })" -ForegroundColor DarkGray
Write-Host "  Default:    $SetDefault" -ForegroundColor DarkGray

# --- Forward Windows environment variables to WSL (WSLENV) ---
$skipVars = @(
    'ALLUSERSPROFILE','APPDATA','CLIENTNAME','COMMONPROGRAMFILES','COMMONPROGRAMFILES(X86)',
    'COMPUTERNAME','COMSPEC','DRIVERDATA','HOMEDRIVE','HOMEPATH','LOCALAPPDATA',
    'LOGONSERVER','NUMBER_OF_PROCESSORS','OS','PATHEXT','PATH','PROCESSOR_ARCHITECTURE',
    'PROCESSOR_IDENTIFIER','PROCESSOR_LEVEL','PROCESSOR_REVISION','PROGRAMDATA',
    'PROGRAMFILES','PROGRAMFILES(X86)','PSMODULEPATH','PUBLIC','SESSIONNAME',
    'SYSTEMDRIVE','SYSTEMROOT','TEMP','TMP','USERDOMAIN','USERDOMAIN_ROAMINGPROFILE',
    'USERNAME','USERPROFILE','WINDIR','WSLENV','TERM_PROGRAM','TERM_PROGRAM_VERSION',
    'PROMPT','PSEXECUTIONPOLICYPREFERENCE','__COMPAT_LAYER'
)

# Parse existing WSLENV (preserve flags like /p, /u, /l)
$currentWslenv = [Environment]::GetEnvironmentVariable('WSLENV', 'User')
$existingFlags = @{}
$existingVars = @()
if ($currentWslenv) {
    foreach ($entry in $currentWslenv -split ':') {
        if (-not $entry) { continue }
        $parts = $entry -split '/', 2
        $existingVars += $parts[0]
        $existingFlags[$parts[0]] = if ($parts.Count -gt 1) { "/$($parts[1])" } else { "" }
    }
}

if ($WslEnv) {
    # Non-interactive: use provided list, merge with existing
    foreach ($var in $WslEnv) {
        if ($var -notin $existingVars) { $existingVars += $var }
    }
    $wslenvEntries = @()
    foreach ($var in $existingVars) {
        $flags = if ($existingFlags.ContainsKey($var)) { $existingFlags[$var] } else { "" }
        $wslenvEntries += "$var$flags"
    }
    $newWslenv = $wslenvEntries -join ':'
    [Environment]::SetEnvironmentVariable('WSLENV', $newWslenv, 'User')
    $env:WSLENV = $newWslenv
    Write-Host "  WSLENV:     $($existingVars.Count) var(s) forwarded" -ForegroundColor DarkGray
    if ('GH_TOKEN' -in $existingVars -and $env:GH_TOKEN -match '^github_pat_') {
        Write-Host "  WARNING: GH_TOKEN is a fine-grained PAT — cross-repo PRs will not work from CLI." -ForegroundColor Yellow
    }
} else {
    # Interactive: show checkbox list
    $envItems = @()
    [Environment]::GetEnvironmentVariables('Process').GetEnumerator() |
        Where-Object { $_.Key -notin $skipVars } |
        Sort-Object Key |
        ForEach-Object {
            $envItems += @{ Name = $_.Key; Value = $_.Value; Checked = $_.Key -in $existingVars }
        }
    # Include any WSLENV vars no longer in the environment
    foreach ($var in $existingVars) {
        if (-not ($envItems | Where-Object { $_.Name -eq $var })) {
            $envItems += @{ Name = $var; Value = "(not set)"; Checked = $true }
        }
    }

    if ($envItems.Count -gt 0) {
        $confirmed = Show-CheckboxList -Items $envItems -Title "Forward Windows env vars to WSL via WSLENV: (PATH handled separately via wsl.conf)"
        if ($confirmed -ne $false) {
            $selected = $envItems | Where-Object { $_.Checked }
            $wslenvEntries = @()
            foreach ($item in $selected) {
                $flags = if ($existingFlags.ContainsKey($item.Name)) { $existingFlags[$item.Name] } else { "" }
                $wslenvEntries += "$($item.Name)$flags"
            }
            $newWslenv = $wslenvEntries -join ':'
            if ($newWslenv) {
                [Environment]::SetEnvironmentVariable('WSLENV', $newWslenv, 'User')
                $env:WSLENV = $newWslenv
                Write-Host "  WSLENV set: $($selected.Count) var(s)" -ForegroundColor Green
                # Warn if forwarding a fine-grained PAT as GH_TOKEN
                $ghItem = $selected | Where-Object { $_.Name -eq 'GH_TOKEN' }
                if ($ghItem -and $ghItem.Value -match '^github_pat_') {
                    Write-Host ""
                    Write-Host "  WARNING: GH_TOKEN is a fine-grained PAT." -ForegroundColor Yellow
                    Write-Host "  Fine-grained PATs are scoped to your own repos. Forwarding this" -ForegroundColor DarkGray
                    Write-Host "  token will make it impossible to create PRs on other people's repos" -ForegroundColor DarkGray
                    Write-Host "  from the CLI, even after running 'gh auth login' (the env var always" -ForegroundColor DarkGray
                    Write-Host "  takes precedence over stored OAuth credentials)." -ForegroundColor DarkGray
                    Write-Host "  Consider: uncheck GH_TOKEN and use 'gh auth login' inside WSL instead." -ForegroundColor DarkGray
                }
            } elseif ($currentWslenv) {
                [Environment]::SetEnvironmentVariable('WSLENV', $null, 'User')
                $env:WSLENV = $null
                Write-Host "  WSLENV cleared" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "  WSLENV: skipped (unchanged)" -ForegroundColor DarkGray
        }
    }
}

# --- Check .wslconfig for conflicts ---
$wslconfigPath = "$env:USERPROFILE\.wslconfig"
$requiredSettings = [ordered]@{
    "networkingMode" = @{
        value = "mirrored"
        reason = "Mirrored networking shares your Windows IP with WSL. This means WSL services (SSH, web servers) are reachable from other devices on your LAN, IPv6 works natively, and localhost is shared between Windows and WSL."
        impacts = @{
            "nat"         = "NAT puts WSL behind a virtual subnet. Other machines on your network cannot reach WSL services directly. IPv6 will not work. You'll need manual port forwarding (netsh) for any WSL service you want to expose."
            "virtioproxy" = "VirtioProxy is experimental and uses a different networking stack. It may work for basic scenarios but has limited community support and may not handle all protocols correctly. IPv6 and inbound connections may behave differently than expected."
        }
        defaultImpact = "fnwsl expects mirrored networking for SSH access, IPv6, and LAN visibility. Your current value may not support these features."
    }
    "dnsTunneling" = @{
        value = "true"
        reason = "DNS tunneling routes WSL's DNS requests through the Windows DNS stack. This is required for mirrored networking to resolve hostnames correctly, and ensures WSL respects your VPN, corporate DNS, and split-tunnel configurations."
        impact = "WSL will attempt to resolve DNS independently, which often fails under mirrored networking. You may see intermittent DNS failures, especially on VPN or corporate networks where DNS is managed by Windows."
    }
    "firewall" = @{
        value = "true"
        reason = "Applies Windows Defender Firewall rules to WSL traffic. With mirrored networking, WSL shares your real IP, so firewall protection ensures WSL services aren't silently exposed to the network without your firewall rules."
        impact = "WSL traffic will bypass Windows Defender Firewall entirely. Any service running in WSL will be directly accessible from the network with no firewall filtering, which is a security risk on shared or public networks."
    }
}
$wslconfigOverrides = @{}
if (Test-Path $wslconfigPath) {
    $existingLines = Get-Content $wslconfigPath
    $inWsl2 = $false
    foreach ($line in $existingLines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\[') {
            $inWsl2 = $trimmed -eq '[wsl2]'
        } elseif ($inWsl2 -and $trimmed -match '^(\w+)\s*=\s*(.+)$') {
            $key = $Matches[1]
            $val = $Matches[2].Trim()
            if ($requiredSettings.Contains($key) -and $val -ne $requiredSettings[$key].value) {
                $setting = $requiredSettings[$key]
                $impactMsg = if ($setting.impacts -and $setting.impacts.ContainsKey($val)) {
                    $setting.impacts[$val]
                } elseif ($setting.defaultImpact) {
                    $setting.defaultImpact
                } else {
                    $setting.impact
                }
                Write-Host ""
                Write-Host "  .wslconfig conflict: $key=$val (current) vs $($setting.value) (required)" -ForegroundColor Yellow
                Write-Host "    Why: $($setting.reason)" -ForegroundColor DarkGray
                Write-Host "    If kept ($val): $impactMsg" -ForegroundColor DarkGray
                $answer = Read-Host "    Change $key to $($setting.value)? (Y/n)"
                if ($answer -match '^[Nn]') {
                    $wslconfigOverrides[$key] = $val
                }
            }
        }
    }
}

Write-Host ""
Write-Host "The rest of the install is non-interactive. Feel free to grab a coffee." -ForegroundColor Green

# --- Install WSL if not present ---
$wslInstalled = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wslInstalled) {
    Write-Host ""
    Write-Host "Installing WSL..." -ForegroundColor Yellow
    wsl --install --distribution Ubuntu --no-launch
    Assert-ExitCode "WSL installation failed."
    Write-Host ""
    Write-Host "WSL installed. A REBOOT is required before continuing." -ForegroundColor Red
    Write-Host "After reboot, run this script again." -ForegroundColor Red
    return
}

# --- Ensure Ubuntu is installed ---
$distroOutput = (wsl -l -q 2>$null) -join "`n" -replace "`0",""
if ($distroOutput -match "Ubuntu") {
    Write-Host ""
    Write-Host "Found existing Ubuntu instance. Will configure and rename to '$WslName'." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "Installing fresh Ubuntu instance..." -ForegroundColor Yellow
    wsl --install --distribution Ubuntu --no-launch
    Assert-ExitCode "Ubuntu installation failed. Check your network connection and try again."

    # --- Create WSL user (non-interactive) ---
    Write-Host "Creating WSL user '$WslUsername'..." -ForegroundColor Yellow
    wsl -d Ubuntu -- bash -c "useradd -m -s /bin/bash -G sudo '$WslUsername' && echo '${WslUsername}:${Passphrase}' | chpasswd && echo '${WslUsername} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/${WslUsername} && chmod 440 /etc/sudoers.d/${WslUsername} && echo -e '[user]\ndefault=${WslUsername}' >> /etc/wsl.conf"
    Assert-ExitCode "WSL user creation failed."
    wsl --shutdown
    Start-Sleep -Seconds 2
    Write-Host "  User '$WslUsername' created and set as default." -ForegroundColor Green
}

# --- Rename distro: export Ubuntu, import as $WslName ---
Write-Host ""
Write-Host "Renaming Ubuntu distro to '$WslName'..." -ForegroundColor Yellow
$exportPath = "$env:TEMP\fnwsl-export.tar"
wsl --export Ubuntu "$exportPath"
Assert-ExitCode "WSL export failed."
wsl --unregister Ubuntu
Assert-ExitCode "WSL unregister failed."
wsl --shutdown
Start-Sleep -Seconds 2
$installPath = "$env:LOCALAPPDATA\fnwsl\$WslName"
New-Item -ItemType Directory -Path (Split-Path $installPath) -Force | Out-Null
wsl --import "$WslName" "$installPath" "$exportPath"
Assert-ExitCode "WSL import failed."
Remove-Item "$exportPath"
Write-Host "  Distro is now '$WslName'." -ForegroundColor Green

# --- Set as default WSL distro ---
$previousDefault = $null
if ($SetDefault) {
    $previousDefault = (wsl -l 2>$null) -join "`n" -replace "`0","" -split "`n" |
        Where-Object { $_ -match '\(Default\)' } |
        ForEach-Object { ($_ -replace '\s*\(Default\)','').Trim() }
    wsl --set-default "$WslName"
    Write-Host "  Set '$WslName' as default WSL distro." -ForegroundColor Green
}

# --- Configure .wslconfig (mirrored networking, IPv6) ---
$wslconfigPath = "$env:USERPROFILE\.wslconfig"
$fnwslTracker = "$env:USERPROFILE\.fnwsl"
$wslconfigExisted = Test-Path $wslconfigPath

# Determine final values, respecting user overrides from interview
$mergeSettings = @{}
foreach ($key in $requiredSettings.Keys) {
    if ($wslconfigOverrides.ContainsKey($key)) {
        $mergeSettings[$key] = $wslconfigOverrides[$key]
    } else {
        $mergeSettings[$key] = $requiredSettings[$key].value
    }
}

# Snapshot current values before we change anything
$currentValues = @{}
if ($wslconfigExisted) {
    $existingLines = Get-Content $wslconfigPath
    $inWsl2 = $false
    foreach ($line in $existingLines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\[') { $inWsl2 = $trimmed -eq '[wsl2]' }
        elseif ($inWsl2 -and $trimmed -match '^(\w+)\s*=\s*(.+)$') {
            if ($mergeSettings.ContainsKey($Matches[1])) {
                $currentValues[$Matches[1]] = $Matches[2].Trim()
            }
        }
    }
}

# Build per-setting change record
$wslconfigChanges = @{}
foreach ($key in $mergeSettings.Keys) {
    $fromVal = if ($currentValues.ContainsKey($key)) { $currentValues[$key] } else { $null }
    $wslconfigChanges[$key] = @{ from = $fromVal; to = $mergeSettings[$key] }
}

# Load or create tracker
$tracker = [PSCustomObject]@{ wslconfigExisted = $wslconfigExisted; instances = [PSCustomObject]@{} }
if (Test-Path $fnwslTracker) {
    $tracker = Get-Content $fnwslTracker -Raw | ConvertFrom-Json
    # Preserve wslconfigExisted from first run
}
if (-not $tracker.instances) {
    $tracker.instances = [PSCustomObject]@{}
}
# Record pre-fnwsl WSLENV on first install only
if (-not ($tracker.PSObject.Properties.Name -contains 'previousWslenv')) {
    $tracker | Add-Member -NotePropertyName 'previousWslenv' -NotePropertyValue $currentWslenv -Force
}

# Record this instance
$instanceRecord = @{
    setupTime = (Get-Date -Format "o")
    wslconfig = if ($wslconfigExisted) { $wslconfigChanges } else { $null }
    previousDefault = $previousDefault
}
$tracker.instances | Add-Member -NotePropertyName $WslName -NotePropertyValue $instanceRecord -Force
$tracker | ConvertTo-Json -Depth 10 | Set-Content $fnwslTracker -Encoding UTF8

# Merge settings into .wslconfig
Write-Host ""
Write-Host "Configuring .wslconfig..." -ForegroundColor Yellow
$lines = @()
$inWsl2 = $false
$wsl2Found = $false
$setKeys = @{}
if ($wslconfigExisted) {
    $lines = @(Get-Content $wslconfigPath)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].Trim()
        if ($line -match '^\[') {
            $inWsl2 = $line -eq '[wsl2]'
            if ($inWsl2) { $wsl2Found = $true }
        } elseif ($inWsl2 -and $line -match '^(\w+)\s*=') {
            $key = $Matches[1]
            if ($mergeSettings.ContainsKey($key)) {
                $lines[$i] = "$key=$($mergeSettings[$key])"
                $setKeys[$key] = $true
            }
        }
    }
}
if (-not $wsl2Found) {
    if ($lines.Count -gt 0) { $lines += "" }
    $lines += "[wsl2]"
}
$missingKeys = $mergeSettings.Keys | Where-Object { -not $setKeys.ContainsKey($_) }
foreach ($key in $missingKeys) {
    $lines += "$key=$($mergeSettings[$key])"
}
$lines | Set-Content -Path $wslconfigPath -Encoding UTF8

# --- Restart WSL to pick up new config ---
Write-Host ""
Write-Host "Restarting WSL..." -ForegroundColor Yellow
wsl --shutdown
Start-Sleep -Seconds 2

# --- Run fnwsl bootstrap inside WSL ---
Write-Host ""
Write-Host "Running fnwsl setup inside WSL..." -ForegroundColor Yellow
$p10kArg = if ($P10kWizard) { "1" } else { "" }
wsl -d $WslName -- bash -c "curl -fsSL 'https://raw.githubusercontent.com/fnrhombus/fnwsl/main/bootstrap.sh' | bash -s -- '$Passphrase' '$WslName' '$p10kArg'"
Assert-ExitCode "WSL-side setup failed."

# --- Hyper-V firewall: allow inbound to WSL ---
Write-Host ""
Write-Host "Configuring Hyper-V firewall (allow inbound to WSL)..." -ForegroundColor Yellow
try {
    Set-NetFirewallHyperVVMSetting -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -DefaultInboundAction Allow
} catch {
    Write-Host "  WARNING: Could not set Hyper-V firewall rule. You may need to do this manually." -ForegroundColor DarkYellow
}

# --- Install usbipd-win ---
$usbipd = Get-Command usbipd -ErrorAction SilentlyContinue
if (-not $usbipd) {
    Write-Host ""
    Write-Host "Installing usbipd-win (USB passthrough for ESP32/Pico)..." -ForegroundColor Yellow
    winget install --exact dorssel.usbipd-win --accept-package-agreements --accept-source-agreements
} else {
    Write-Host ""
    Write-Host "usbipd-win already installed." -ForegroundColor DarkGray
}

# --- Configure Windows Terminal (Nerd Font + rename WSL profile) ---
$wtSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
if (Test-Path $wtSettingsPath) {
    $settings = Get-Content $wtSettingsPath -Raw | ConvertFrom-Json
    $needsSave = $false
    $wslHostname = $WslName

    # Set font on defaults if not already set
    if (-not $settings.profiles.defaults.font) {
        $settings.profiles.defaults | Add-Member -NotePropertyName "font" -NotePropertyValue @{ face = "CaskaydiaCove Nerd Font" } -Force
        $needsSave = $true
    } elseif (-not $settings.profiles.defaults.font.face) {
        $settings.profiles.defaults.font | Add-Member -NotePropertyName "face" -NotePropertyValue "CaskaydiaCove Nerd Font" -Force
        $needsSave = $true
    }

    # Hide auto-detected WSL/Ubuntu profiles (we create our own explicit one)
    foreach ($profile in $settings.profiles.list) {
        if ($profile.source -match "Microsoft\.WSL|Windows\.Terminal\.Wsl" -or $profile.name -match "Ubuntu") {
            if (-not $profile.hidden) {
                $profile.hidden = $true
                $needsSave = $true
            }
        }
    }

    # Ensure our explicit profile exists
    $ourProfile = $settings.profiles.list | Where-Object { $_.name -eq $wslHostname -and -not $_.source } | Select-Object -First 1
    if (-not $ourProfile) {
        $newProfile = [PSCustomObject]@{
            guid        = "{$([guid]::NewGuid().ToString())}"
            name        = $wslHostname
            commandline = "wsl.exe -d $wslHostname"
            hidden      = $false
        }
        $settings.profiles.list = @($settings.profiles.list) + @($newProfile)
        $needsSave = $true
    }

    if ($needsSave) {
        Write-Host ""
        Write-Host "Configuring Windows Terminal (font + WSL profile '$wslHostname')..." -ForegroundColor Yellow
        $settings | ConvertTo-Json -Depth 10 | Set-Content $wtSettingsPath -Encoding UTF8
    } else {
        Write-Host ""
        Write-Host "Windows Terminal already configured." -ForegroundColor DarkGray
    }
} else {
    Write-Host ""
    Write-Host "Windows Terminal settings not found - configure manually." -ForegroundColor DarkYellow
}

# --- Verify Windows-side setup ---
Write-Host ""
Write-Host "Verifying setup..." -ForegroundColor Yellow
$verifyFailures = @()

function Verify($label, $check) {
    if (& $check) {
        Write-Host "  OK    $label" -ForegroundColor Green
    } else {
        Write-Host "  FAIL  $label" -ForegroundColor Red
        $script:verifyFailures += $label
    }
}

# WSL distro exists and responds
Verify "WSL distro '$WslName'" {
    $distros = @((wsl -l -q 2>$null) -join "`n" -replace "`0","" -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $WslName -in $distros
}
Verify "Default user is '$WslUsername'" {
    $user = (wsl -d $WslName -- whoami 2>$null) -replace "`0","" | ForEach-Object { $_.Trim() }
    $user -eq $WslUsername
}
if ($SetDefault) {
    Verify "Default WSL distro is '$WslName'" {
        $default = (wsl -l 2>$null) -join "`n" -replace "`0","" -split "`n" | Where-Object { $_ -match '\(Default\)' } | ForEach-Object { ($_ -replace '\s*\(Default\)','').Trim() }
        $default -eq $WslName
    }
}

# Tracker
Verify "Tracker has '$WslName'" {
    if (Test-Path $fnwslTracker) {
        $t = Get-Content $fnwslTracker -Raw | ConvertFrom-Json
        $t.instances.PSObject.Properties.Name -contains $WslName
    } else { $false }
}

# .wslconfig
Verify ".wslconfig exists" { Test-Path "$env:USERPROFILE\.wslconfig" }

# WSLENV
Verify "WSLENV configured" { [bool][Environment]::GetEnvironmentVariable('WSLENV', 'User') }

# Windows Terminal font
Verify "Terminal font configured" {
    if (Test-Path $wtSettingsPath) {
        $s = Get-Content $wtSettingsPath -Raw | ConvertFrom-Json
        [bool]$s.profiles.defaults.font.face
    } else { $false }
}

# usbipd
Verify "usbipd-win installed" { [bool](Get-Command usbipd -ErrorAction SilentlyContinue) }

if ($verifyFailures.Count -gt 0) {
    Write-Host ""
    Write-Host "WARNING: $($verifyFailures.Count) check(s) failed:" -ForegroundColor Red
    foreach ($f in $verifyFailures) {
        Write-Host "  - $f" -ForegroundColor Red
    }
}

# --- Done ---
Write-Host ""
Write-Host "=== Setup complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Open a new WSL terminal tab"
Write-Host "  2. Run 'gh auth login' to authenticate with GitHub"
Write-Host "  3. Verify git signing: git log --show-signature"
Write-Host "  4. To reconfigure p10k prompt: p10k configure"
if (Get-Process "Docker Desktop" -ErrorAction SilentlyContinue) {
    Write-Host ""
    Write-Host "Docker:" -ForegroundColor White
    Write-Host "  Enable WSL integration for '$WslName' in Docker Desktop:"
    Write-Host "  Settings > Resources > WSL Integration > enable '$WslName'"
}
Write-Host ""
Write-Host "USB passthrough (when needed):" -ForegroundColor White
Write-Host "  usbipd list                                         # find your device"
Write-Host "  usbipd bind --busid X-X                             # share it (once, admin)"
Write-Host "  usbipd attach --wsl --busid X-X --auto-attach       # attach to WSL"
