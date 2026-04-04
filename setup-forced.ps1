# fnwsl unattended setup — runs setup.ps1 with -Force (all defaults, no prompts)
# From elevated PowerShell:
#   .\setup-forced.ps1
#   irm https://github.com/fnrhombus/fnwsl/releases/latest/download/setup-forced.ps1 | iex

$setupUrl = "https://github.com/fnrhombus/fnwsl/releases/latest/download/setup.ps1"
$setupPath = Join-Path $env:TEMP "fnwsl-setup.ps1"
Invoke-WebRequest -Uri $setupUrl -OutFile $setupPath
& $setupPath -Force @args
