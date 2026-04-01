# fnwsl Windows-side setup
# Run from elevated PowerShell:
#   .\install-windows.ps1 "mypassphrase"
#
# Or one-liner (download and run):
#   iwr -Uri https://raw.githubusercontent.com/fnrhombus/fnwsl/main/install-windows.ps1 -OutFile $env:TEMP\fnwsl.ps1; & $env:TEMP\fnwsl.ps1 "mypassphrase"

param(
    [string]$SshPassphrase
)

$ErrorActionPreference = "Stop"

Write-Host "=== fnwsl Windows setup ===" -ForegroundColor Cyan

# --- Ensure running as admin ---
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: Run this script from an elevated PowerShell." -ForegroundColor Red
    exit 1
}

# --- Install WSL if not present ---
$wslInstalled = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wslInstalled) {
    Write-Host ""
    Write-Host "Installing WSL..." -ForegroundColor Yellow
    wsl --install --distribution Ubuntu --no-launch
    Write-Host ""
    Write-Host "WSL installed. A REBOOT is required before continuing." -ForegroundColor Red
    Write-Host "After reboot, run this script again." -ForegroundColor Red
    exit 0
}

# --- Ensure Ubuntu is installed ---
$distros = wsl -l -q 2>$null | Where-Object { $_ -match "Ubuntu" }
if (-not $distros) {
    Write-Host ""
    Write-Host "Installing Ubuntu..." -ForegroundColor Yellow
    wsl --install --distribution Ubuntu --no-launch
    Write-Host "Ubuntu installed. Launch it once to create your user, then run this script again." -ForegroundColor Yellow
    exit 0
}

# --- Create .wslconfig (mirrored networking, IPv6) ---
$wslconfigPath = "$env:USERPROFILE\.wslconfig"
if (-not (Test-Path $wslconfigPath)) {
    Write-Host ""
    Write-Host "Creating .wslconfig (mirrored networking)..." -ForegroundColor Yellow
    @"
[wsl2]
networkingMode=mirrored
dnsTunneling=true
firewall=true
"@ | Set-Content -Path $wslconfigPath -Encoding UTF8
} else {
    Write-Host ""
    Write-Host ".wslconfig already exists, skipping." -ForegroundColor DarkGray
}

# --- Restart WSL to pick up new config ---
Write-Host ""
Write-Host "Restarting WSL..." -ForegroundColor Yellow
wsl --shutdown
Start-Sleep -Seconds 2

# --- Run fnwsl bootstrap inside WSL ---
Write-Host ""
Write-Host "Running fnwsl setup inside WSL..." -ForegroundColor Yellow
if ($SshPassphrase) {
    wsl -d Ubuntu -- bash -c "curl -fsSL 'https://raw.githubusercontent.com/fnrhombus/fnwsl/main/bootstrap.sh' | bash -s -- '$SshPassphrase'"
} else {
    wsl -d Ubuntu -- bash -c "curl -fsSL https://raw.githubusercontent.com/fnrhombus/fnwsl/main/bootstrap.sh | bash"
}

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
    $wslHostname = "$($env:COMPUTERNAME.ToLower())-wsl"

    # Set font on defaults if not already set
    if (-not $settings.profiles.defaults.font) {
        $settings.profiles.defaults | Add-Member -NotePropertyName "font" -NotePropertyValue @{ face = "CaskaydiaCove Nerd Font" } -Force
        $needsSave = $true
    } elseif (-not $settings.profiles.defaults.font.face) {
        $settings.profiles.defaults.font | Add-Member -NotePropertyName "face" -NotePropertyValue "CaskaydiaCove Nerd Font" -Force
        $needsSave = $true
    }

    # Rename Ubuntu WSL profiles to match the WSL hostname
    foreach ($profile in $settings.profiles.list) {
        if ($profile.source -match "Ubuntu|Microsoft\.WSL" -or $profile.name -match "Ubuntu") {
            if ($profile.name -ne $wslHostname) {
                $profile.name = $wslHostname
                $needsSave = $true
            }
        }
    }

    if ($needsSave) {
        Write-Host ""
        Write-Host "Configuring Windows Terminal (font + renaming WSL profile to '$wslHostname')..." -ForegroundColor Yellow
        $settings | ConvertTo-Json -Depth 10 | Set-Content $wtSettingsPath -Encoding UTF8
    } else {
        Write-Host ""
        Write-Host "Windows Terminal already configured." -ForegroundColor DarkGray
    }
} else {
    Write-Host ""
    Write-Host "Windows Terminal settings not found — configure manually." -ForegroundColor DarkYellow
}

# --- Done ---
Write-Host ""
Write-Host "=== Setup complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Open a new WSL terminal tab"
Write-Host "  2. Powerlevel10k will prompt you to configure your prompt"
Write-Host "  3. Run 'gh auth login' to authenticate with GitHub"
Write-Host "  4. Verify git signing: git log --show-signature"
Write-Host ""
Write-Host "USB passthrough (when needed):" -ForegroundColor White
Write-Host "  usbipd list                                         # find your device"
Write-Host "  usbipd bind --busid X-X                             # share it (once, admin)"
Write-Host "  usbipd attach --wsl --busid X-X --auto-attach       # attach to WSL"
