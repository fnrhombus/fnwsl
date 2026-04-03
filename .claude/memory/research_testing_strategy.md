# Testing Strategy for unsetup.ps1

## Problem Statement

Testing `unsetup.ps1` end-to-end requires a real WSL/Ubuntu install (via `setup.ps1`), which takes a long time and is destructive. We need a strategy to test the script's logic paths without real WSL infrastructure.

## Architecture of unsetup.ps1 (Testable Units)

The script has seven distinct functional areas:

1. **Show-CheckboxMenu** -- TUI checkbox picker using `[Console]::ReadKey`, `SetCursorPosition`, `CursorVisible`
2. **Tracker file I/O** -- Read/write/delete `~/.fnwsl` JSON
3. **.wslconfig parsing** -- Read INI-style `[wsl2]` section, extract key=value pairs
4. **Interview phase** -- Detect unexpected .wslconfig changes, prompt user for rollback/keep decisions
5. **From-propagation** -- When removing one instance, update `from` values on remaining instances' tracker records
6. **WSL distro unregistration** -- Calls `wsl --unregister Ubuntu`
7. **Windows Terminal profile cleanup** -- Read/filter/write `settings.json`

## Recommended Approach: Extract + Mock + TestDrive

### Step 1: Extract Testable Functions

Refactor `unsetup.ps1` to separate pure logic from side effects. Create a companion file (e.g., `unsetup-functions.ps1`) that the main script dot-sources. This lets Pester tests dot-source just the functions without triggering top-level script execution.

Functions to extract:

```powershell
# Already exists as a function:
Show-CheckboxMenu

# New extractions:
Read-FnwslTracker        # JSON file -> PSObject (or $null)
Write-FnwslTracker       # PSObject -> JSON file
Remove-FnwslTracker      # Delete tracker file
Read-WslConfigValues     # .wslconfig path -> hashtable of [wsl2] key=value pairs
Build-RollbackDecisions  # (instanceData, currentValues, remainingInstances, rollbackDecisions-out) -> hashtable
Apply-WslConfigRollback  # (wslconfigPath, settingsToRollback) -> modifies file
Update-TrackerFromValues # (tracker, removedInstance, rollbackDecisions) -> propagates "from" values
Remove-WslTerminalProfiles  # (settingsJsonPath, wslName) -> modifies settings.json
```

The main `unsetup.ps1` becomes an orchestrator that calls these functions + handles user I/O + calls external commands.

### Step 2: Wrapper Functions for Unmockable Dependencies

Pester **cannot mock .NET static methods** like `[Console]::ReadKey()`, `[Console]::SetCursorPosition()`, or `[Console]::CursorVisible`. The standard workaround is thin wrapper functions:

```powershell
function Read-ConsoleKey {
    [Console]::ReadKey($true)
}

function Set-ConsoleCursorPosition {
    param([int]$X, [int]$Y)
    [Console]::SetCursorPosition($X, $Y)
}

function Get-ConsoleCursorTop {
    [Console]::CursorTop
}

function Set-ConsoleCursorVisible {
    param([bool]$Visible)
    [Console]::CursorVisible = $Visible
}

function Get-ConsoleWindowWidth {
    [Console]::WindowWidth
}
```

Similarly, wrap external executables since Pester can only mock PowerShell functions/cmdlets, not native .exe calls:

```powershell
function Invoke-WslCommand {
    param([string[]]$Arguments)
    & wsl.exe @Arguments
}

function Get-WslDistros {
    (wsl -l -q 2>$null) -join "`n" -replace "`0",""
}
```

Then `Show-CheckboxMenu` calls `Read-ConsoleKey` instead of `[Console]::ReadKey($true)`, and Pester can mock `Read-ConsoleKey` to simulate keypresses.

### Step 3: Pester TestDrive for File-Based Tests

Pester's `TestDrive:\` is a temporary PSDrive that auto-cleans after each Describe/Context block. Use it for all file operations:

```powershell
Describe "Tracker file management" {
    BeforeAll {
        . $PSScriptRoot\..\unsetup-functions.ps1
    }

    Context "Single instance tracker" {
        BeforeEach {
            $tracker = @{
                wslconfigExisted = $true
                instances = @{
                    "metis-wsl" = @{
                        setupTime = "2026-04-01T10:00:00"
                        wslconfig = @{
                            networkingMode = @{ from = "nat"; to = "mirrored" }
                            dnsTunneling   = @{ from = $null; to = "true" }
                        }
                    }
                }
            }
            $tracker | ConvertTo-Json -Depth 10 | Set-Content "TestDrive:\.fnwsl"
        }

        It "Should read tracker correctly" {
            $result = Read-FnwslTracker -Path "TestDrive:\.fnwsl"
            $result.instances."metis-wsl".wslconfig.networkingMode.from | Should -Be "nat"
        }
    }
}
```

## Detailed Test Plans by Feature

### 1. Tracker File Management (Unit Tests)

**No mocking needed** -- pure file I/O against TestDrive.

Test scenarios:
- Tracker file does not exist -> returns $null
- Tracker with one instance -> reads correctly
- Tracker with multiple instances -> reads all
- Remove instance from multi-instance tracker -> JSON updated, file retained
- Remove last instance -> tracker file deleted
- Malformed JSON -> error handling (currently missing from script)
- Empty instances object -> behaves like no tracker

Sample tracker fixtures:

```powershell
# Single instance, wslconfig existed before
$singleInstance = @{
    wslconfigExisted = $true
    instances = @{
        "metis-wsl" = @{
            setupTime = "2026-04-01T10:00:00"
            wslconfig = @{
                networkingMode = @{ from = "nat"; to = "mirrored" }
                dnsTunneling   = @{ from = $null; to = "true" }
                firewall       = @{ from = $null; to = "true" }
            }
        }
    }
}

# Two instances (for propagation testing)
$twoInstances = @{
    wslconfigExisted = $true
    instances = @{
        "metis-wsl" = @{
            setupTime = "2026-04-01T10:00:00"
            wslconfig = @{
                networkingMode = @{ from = "nat"; to = "mirrored" }
            }
        }
        "dev-wsl" = @{
            setupTime = "2026-04-02T10:00:00"
            wslconfig = @{
                networkingMode = @{ from = "mirrored"; to = "mirrored" }
            }
        }
    }
}

# wslconfig did NOT exist before fnwsl (triggers file deletion)
$freshInstall = @{
    wslconfigExisted = $false
    instances = @{
        "metis-wsl" = @{
            setupTime = "2026-04-01T10:00:00"
            wslconfig = $null
        }
    }
}
```

### 2. .wslconfig Parsing and Rollback (Unit Tests)

**No mocking needed** -- pure file operations against TestDrive.

Test scenarios for parsing:
- Standard `[wsl2]` section with expected keys
- .wslconfig with multiple sections (`[wsl2]`, `[experimental]`) -- only `[wsl2]` parsed
- Keys with spaces around `=`
- Empty .wslconfig
- .wslconfig does not exist
- Comments in .wslconfig (not currently handled -- potential bug to document)

Test scenarios for rollback:
- Rollback to previous value (`networkingMode=nat` -> restore `networkingMode=nat`)
- Rollback to null (setting didn't exist before) -> line removed
- Rollback leaves `[wsl2]` empty -> `[wsl2]` header removed
- Rollback leaves entire file empty -> file deleted
- Mixed rollback/keep decisions
- .wslconfig with other sections preserved after rollback
- `-RemoveWslConfig` flag forces all tracked settings rolled back
- `-KeepWslConfig` flag skips all rollback

Sample .wslconfig fixtures:

```ini
# Standard
[wsl2]
networkingMode=mirrored
dnsTunneling=true
firewall=true

# With extra sections
[wsl2]
networkingMode=mirrored
[experimental]
autoMemoryReclaim=gradual

# Only non-fnwsl settings
[wsl2]
swap=0
localhostForwarding=true

# User has modified a value after setup
[wsl2]
networkingMode=nat
dnsTunneling=true
firewall=true
```

### 3. Interview Phase / Rollback Decision Logic (Unit Tests)

The interview logic (lines 137-197) decides per-setting whether to rollback, keep, or propagate. This is the most complex logic and benefits most from extraction.

Key decision matrix to test:

| Condition | Expected Decision |
|-----------|------------------|
| Value unchanged from what fnwsl set (`currentVal == toVal`) | Auto-rollback |
| Value changed by user/other tool (`currentVal != toVal`) | Prompt user (interview) |
| Setting needed by another fnwsl instance | Propagate (skip rollback) |
| `-RemoveWslConfig` flag | Force rollback, no interview |
| `-KeepWslConfig` flag | Skip everything |
| `willDeleteFile` is true (last instance, wslconfig didn't exist before) | Skip interview, delete file |

For the interview prompt path, mock `Read-Host` to simulate user choosing `R` (rollback) or `K` (keep):

```powershell
Context "User changed networkingMode after setup" {
    Mock Read-Host { return "R" }  # User chooses rollback

    It "Should mark setting for rollback when user presses R" {
        $decisions = Build-RollbackDecisions -InstanceData $instance -CurrentValues @{
            networkingMode = "nat"  # user changed it back
        } -RemainingInstances @()
        $decisions["networkingMode"] | Should -Be "rollback"
    }
}

Context "User wants to keep their change" {
    Mock Read-Host { return "K" }

    It "Should mark setting as keep when user presses K" {
        $decisions = Build-RollbackDecisions -InstanceData $instance -CurrentValues @{
            networkingMode = "nat"
        } -RemainingInstances @()
        $decisions["networkingMode"] | Should -Be "keep"
    }
}
```

### 4. From-Propagation for Multi-Instance (Unit Tests)

When instance A set `networkingMode` from `nat` to `mirrored`, then instance B was set up and recorded `from=mirrored` (because A already changed it). Removing A should propagate A's original `from=nat` to B's record so B's eventual teardown can restore the true original.

Test scenarios:
- Remove first instance -> second instance's `from` updated to first's `from`
- Remove second instance -> first instance's `from` unchanged
- Three instances with chain: A(nat->mirrored), B(mirrored->mirrored), C(mirrored->mirrored) -> remove A, B gets from=nat
- Setting NOT shared between instances -> no propagation
- Setting shared but values don't chain (B.from != A.to) -> no propagation (current behavior)

```powershell
Describe "From-propagation" {
    It "Should propagate original 'from' to remaining instance" {
        $tracker = <two-instance tracker where A.to == B.from>
        Update-TrackerFromValues -Tracker $tracker -RemovedInstance "metis-wsl" `
            -RollbackDecisions @{ networkingMode = "propagate" }
        $tracker.instances."dev-wsl".wslconfig.networkingMode.from | Should -Be "nat"
    }
}
```

### 5. Show-CheckboxMenu TUI (Unit Tests with Mocked Console)

After extracting console calls to wrapper functions, mock the wrappers:

```powershell
Describe "Show-CheckboxMenu" {
    BeforeAll {
        . $PSScriptRoot\..\unsetup-functions.ps1
    }

    Context "User selects one item and confirms" {
        BeforeAll {
            # Simulate: Down, Space (select item 1), Enter
            $keySequence = @(
                [PSCustomObject]@{ Key = [ConsoleKey]::DownArrow }
                [PSCustomObject]@{ Key = [ConsoleKey]::Spacebar }
                [PSCustomObject]@{ Key = [ConsoleKey]::Enter }
            )
            $script:keyIndex = 0
            Mock Read-ConsoleKey {
                $key = $keySequence[$script:keyIndex]
                $script:keyIndex++
                return $key
            }
            Mock Set-ConsoleCursorPosition {}
            Mock Set-ConsoleCursorVisible {}
            Mock Get-ConsoleCursorTop { return 5 }
            Mock Get-ConsoleWindowWidth { return 80 }
            Mock Write-Host {}
        }

        It "Should return the selected item" {
            $result = Show-CheckboxMenu -Title "Pick:" -Items @("alpha", "beta", "gamma")
            $result | Should -Be @("beta")
        }
    }

    Context "User selects nothing and confirms" {
        # ... mock Enter immediately
        It "Should return empty array" { ... }
    }

    Context "User selects all and confirms" {
        # ... mock Space, Down, Space, Down, Space, Enter
        It "Should return all items" { ... }
    }
}
```

**Limitation**: `Write-Host` output testing is tricky. Pester can mock `Write-Host` but verifying the visual output (colors, padding) is low-value. Focus on testing the return value based on key sequences.

### 6. WSL Distro Unregistration (Integration Boundary)

This calls `wsl --unregister Ubuntu` which is destructive and requires real WSL. Strategy:

- **Extract to wrapper**: `Invoke-WslUnregister` calls `wsl --unregister $Distro`
- **Extract distro check**: `Get-WslDistros` returns the distro list string
- **Unit test the decision logic only**: Given distro list contains "Ubuntu" -> unregister called. Given distro list does NOT contain "Ubuntu" -> skip.

```powershell
Context "Ubuntu distro exists" {
    Mock Get-WslDistros { return "Ubuntu`nDebian" }
    Mock Invoke-WslUnregister {}

    It "Should call unregister for Ubuntu" {
        Remove-WslDistro
        Should -Invoke Invoke-WslUnregister -Times 1 -ParameterFilter { $Distro -eq "Ubuntu" }
    }
}

Context "No Ubuntu distro" {
    Mock Get-WslDistros { return "Debian" }
    Mock Invoke-WslUnregister {}

    It "Should not call unregister" {
        Remove-WslDistro
        Should -Invoke Invoke-WslUnregister -Times 0
    }
}
```

### 7. Windows Terminal Profile Cleanup (Unit Tests)

Fully testable with TestDrive -- create a fake `settings.json`, run the cleanup, verify output.

```powershell
Describe "Windows Terminal profile cleanup" {
    BeforeEach {
        $settings = @{
            profiles = @{
                list = @(
                    @{ name = "PowerShell"; source = "Windows.Terminal.PowershellCore" }
                    @{ name = "Ubuntu"; source = "Windows.Terminal.Wsl" }
                    @{ name = "metis-wsl"; source = "Microsoft.WSL" }
                    @{ name = "Command Prompt"; source = "Windows.Terminal.CommandPrompt" }
                )
            }
        }
        $settings | ConvertTo-Json -Depth 10 | Set-Content "TestDrive:\settings.json"
    }

    It "Should remove Ubuntu and WSL profiles, keep others" {
        Remove-WslTerminalProfiles -SettingsPath "TestDrive:\settings.json" -WslName "metis-wsl"
        $result = Get-Content "TestDrive:\settings.json" -Raw | ConvertFrom-Json
        $result.profiles.list.Count | Should -Be 2
        $result.profiles.list.name | Should -Not -Contain "Ubuntu"
        $result.profiles.list.name | Should -Not -Contain "metis-wsl"
    }

    It "Should handle settings file not existing" {
        Remove-WslTerminalProfiles -SettingsPath "TestDrive:\nonexistent.json" -WslName "metis-wsl"
        # Should not throw
    }

    It "Should handle no WSL profiles present" {
        $noWsl = @{
            profiles = @{
                list = @(
                    @{ name = "PowerShell"; source = "Windows.Terminal.PowershellCore" }
                )
            }
        }
        $noWsl | ConvertTo-Json -Depth 10 | Set-Content "TestDrive:\settings.json"
        Remove-WslTerminalProfiles -SettingsPath "TestDrive:\settings.json" -WslName "metis-wsl"
        $result = Get-Content "TestDrive:\settings.json" -Raw | ConvertFrom-Json
        $result.profiles.list.Count | Should -Be 1
    }
}
```

## Integration Test Strategy (No Real WSL Needed)

For end-to-end flow testing without real WSL, create a test harness that:

1. Sets up TestDrive with fake `~/.fnwsl` tracker and `.wslconfig`
2. Sets up TestDrive with fake Windows Terminal `settings.json`
3. Mocks all external commands (`wsl.exe`, admin check)
4. Mocks all user I/O (`Read-Host`, console wrapper functions)
5. Runs the orchestrator function
6. Verifies final file states

```powershell
Describe "Full teardown flow - single instance" {
    BeforeAll {
        . $PSScriptRoot\..\unsetup-functions.ps1

        # Override path variables
        $script:fnwslTracker = "TestDrive:\.fnwsl"
        $script:wslconfigPath = "TestDrive:\.wslconfig"
        $script:wtSettingsPath = "TestDrive:\settings.json"
    }

    BeforeEach {
        # Set up fake tracker
        @{
            wslconfigExisted = $true
            instances = @{
                "metis-wsl" = @{
                    setupTime = "2026-04-01T10:00:00"
                    wslconfig = @{
                        networkingMode = @{ from = "nat"; to = "mirrored" }
                        dnsTunneling   = @{ from = $null; to = "true" }
                    }
                }
            }
        } | ConvertTo-Json -Depth 10 | Set-Content "TestDrive:\.fnwsl"

        # Set up fake .wslconfig (unchanged from what setup wrote)
        @"
[wsl2]
networkingMode=mirrored
dnsTunneling=true
"@ | Set-Content "TestDrive:\.wslconfig"

        # Set up fake Windows Terminal settings
        @{
            profiles = @{
                list = @(
                    @{ name = "PowerShell"; source = "Windows.Terminal.PowershellCore" }
                    @{ name = "Ubuntu"; source = "Windows.Terminal.Wsl" }
                )
            }
        } | ConvertTo-Json -Depth 10 | Set-Content "TestDrive:\settings.json"

        # Mock external dependencies
        Mock Get-WslDistros { return "Ubuntu" }
        Mock Invoke-WslUnregister {}
        Mock Read-Host { return "y" }  # Confirm teardown
    }

    It "Should restore .wslconfig to pre-fnwsl state" {
        Invoke-FnwslTeardown -WslName "metis-wsl"
        $config = Get-Content "TestDrive:\.wslconfig"
        $config | Should -Contain "networkingMode=nat"
        $config | Should -Not -Contain "dnsTunneling"  # was null before, so removed
    }

    It "Should delete tracker file (last instance)" {
        Invoke-FnwslTeardown -WslName "metis-wsl"
        Test-Path "TestDrive:\.fnwsl" | Should -BeFalse
    }

    It "Should remove WSL profiles from Terminal settings" {
        Invoke-FnwslTeardown -WslName "metis-wsl"
        $settings = Get-Content "TestDrive:\settings.json" -Raw | ConvertFrom-Json
        $settings.profiles.list.Count | Should -Be 1
    }

    It "Should call wsl unregister" {
        Invoke-FnwslTeardown -WslName "metis-wsl"
        Should -Invoke Invoke-WslUnregister -Times 1
    }
}
```

## Suggested Refactoring Plan

### Option A: Minimal Refactor (Companion Functions File)

Create `unsetup-functions.ps1` alongside `unsetup.ps1`:

```
fnrhombus.fnwsl/
  unsetup.ps1              # orchestrator (dot-sources functions file)
  unsetup-functions.ps1    # all extracted functions
  tests/
    unsetup.Tests.ps1      # Pester test file
```

`unsetup.ps1` starts with:
```powershell
. "$PSScriptRoot\unsetup-functions.ps1"
```

Test file starts with:
```powershell
BeforeAll {
    . $PSScriptRoot\..\unsetup-functions.ps1
}
```

**Pros**: Minimal change to existing script structure. Functions file can be tested in isolation.
**Cons**: Path variables (`$fnwslTracker`, `$wslconfigPath`, etc.) must be parameterized rather than hardcoded.

### Option B: Script Module

Convert to a `.psm1` module with exported functions. More PowerShell-idiomatic but heavier refactor.

**Recommendation**: Option A. It's the smallest change that unlocks full testability.

### Key Parameterization Needed

The current script hardcodes paths:
```powershell
$fnwslTracker = "$env:USERPROFILE\.fnwsl"
$wslconfigPath = "$env:USERPROFILE\.wslconfig"
$wtSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
```

Extracted functions should accept these as parameters so tests can pass TestDrive paths:
```powershell
function Read-WslConfigValues {
    param([string]$Path)
    # ... parse [wsl2] section
}
```

### Admin Check

The admin check at line 67 will abort the script immediately. For testing, either:
- Extract the admin check into a function (`Test-IsAdmin`) and mock it
- Or run tests as admin (not ideal)
- Or have the extracted functions not include the admin check (preferred -- the orchestrator handles it)

## Console I/O Testing Summary

| I/O Operation | Pester Mockable? | Strategy |
|---------------|-----------------|----------|
| `Read-Host` | Yes, directly | `Mock Read-Host { return "y" }` |
| `Write-Host` | Yes, directly | `Mock Write-Host {}` (suppress output) or verify calls |
| `[Console]::ReadKey()` | No (static .NET) | Wrap in `Read-ConsoleKey` function, mock that |
| `[Console]::SetCursorPosition()` | No (static .NET) | Wrap in `Set-ConsoleCursorPosition`, mock that |
| `[Console]::CursorTop` | No (static .NET) | Wrap in `Get-ConsoleCursorTop`, mock that |
| `[Console]::CursorVisible` | No (static .NET) | Wrap in `Set-ConsoleCursorVisible`, mock that |
| `[Console]::WindowWidth` | No (static .NET) | Wrap in `Get-ConsoleWindowWidth`, mock that |
| `wsl.exe` calls | No (native exe) | Wrap in `Invoke-WslCommand` / `Get-WslDistros`, mock those |

## Edge Cases Worth Testing

1. **Tracker has instance but .wslconfig is missing** -- should not crash
2. **Tracker JSON is malformed** -- currently unhandled, will throw on ConvertFrom-Json
3. **.wslconfig has BOM or encoding issues** -- UTF8 with/without BOM
4. **Instance name contains special regex characters** -- the `$([regex]::Escape($WslName))` in Windows Terminal filter handles this, but test it
5. **Windows Terminal settings.json has trailing commas** -- ConvertFrom-Json may choke
6. **Multiple iterations: removing 2 of 3 instances in one run** -- tracker reloaded each iteration (line 117), verify chaining works
7. **Concurrent modification** -- another process modifies tracker between reload and write (low priority)
8. **Empty .wslconfig after rollback** -- file should be deleted (line 329-331)
9. **[wsl2] section becomes empty but other sections remain** -- only `[wsl2]` header removed, file kept

## Getting Started

1. Install Pester 5: `Install-Module -Name Pester -MinimumVersion 5.0 -Scope CurrentUser -Force`
2. Create `tests/` directory
3. Extract functions into `unsetup-functions.ps1`
4. Write tests following patterns above
5. Run: `Invoke-Pester ./tests/unsetup.Tests.ps1 -Output Detailed`

## Sources

- [Pester documentation](https://pester.dev/)
- [Pester mocking guide](https://pester.dev/docs/usage/mocking)
- [Pester TestDrive](https://pester.dev/docs/usage/testdrive)
- [Pester setup and teardown](https://pester-docs.netlify.app/docs/usage/setup-and-teardown)
- [Importing tested functions](https://pester.dev/docs/usage/importing-tested-functions)
- [Mocking .NET static methods -- Pester issue #592](https://github.com/pester/Pester/issues/592)
- [Mocking external commands -- Pester issue #403](https://github.com/pester/Pester/issues/403)
- [Mocking .NET Objects in Pester](https://adamfortuno.com/index.php/2020/04/28/mocking-net-objects-in-pester-scripts/)
- [Testing script-level code discussion](https://forums.powershell.org/t/testing-script-level-code/9457)
- [Mock Read-Host with Pester](https://github.com/pester/Pester/issues/1044)
