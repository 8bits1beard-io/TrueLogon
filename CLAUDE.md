# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

True Logon is a Windows profile management system that tracks user logon activity and automatically removes stale profiles from shared workstations. It solves the problem of profile accumulation in Windows environments where file timestamps are unreliable due to security tools and background processes modifying profile folders.

## Architecture

True Logon operates in three phases:

1. **Installation (Win32 App)**: Deploy via Intune, installs tracking infrastructure
2. **Tracking**: Scheduled task runs at every user logon, records logon data to registry
3. **Cleanup (Proactive Remediation)**: Identifies and removes stale profiles

### Key Components

```
W32App/
├── Install.ps1          # Main installation script - sets up registry, tracking script, scheduled task
├── Detection.ps1        # Intune detection - validates 5 components for compliance
└── IntuneWinAppUtil.exe # Packaging utility for .intunewin creation

ProactiveRemediationScripts/
├── Detection.ps1        # Counts profiles, triggers remediation if > threshold
└── Remediation.ps1      # Removes stale profiles based on DaysThreshold
```

### Data Flow

- **Registry**: `HKLM:\Software\TrueLogon` stores per-user SIDs with Username, LastLogon (ISO 8601), ProfilePath
- **Tracking Script**: `C:\ProgramData\TrueLogon\TrueLogon.ps1` runs at logon via scheduled task "TrueLogon"
- **Logs**: `C:\ProgramData\TrueLogon\Logs\` (CMTrace format, 5MB rotation per file)
  - `TrueLogon-Install.log` - Installation/uninstallation
  - `TrueLogon-Detection.log` - Win32 app detection checks
  - `TrueLogon-Tracking.log` - Logon tracking errors
  - `TrueLogon-Remediation.log` - Profile cleanup operations

## Common Commands

### Packaging for Intune
```powershell
.\W32App\IntuneWinAppUtil.exe -c .\W32App -s Install.ps1 -o .\W32App
```

### Local Testing
```powershell
# Install (dry run)
.\W32App\Install.ps1 -WhatIf

# Install
.\W32App\Install.ps1

# Uninstall
.\W32App\Install.ps1 -Uninstall

# Preview profile cleanup
.\ProactiveRemediationScripts\Remediation.ps1 -WhatIf

# Test with custom threshold
.\ProactiveRemediationScripts\Remediation.ps1 -DaysThreshold 30 -WhatIf
```

### Verification
```powershell
# Check registry
reg query "HKLM\Software\TrueLogon"

# Check scheduled task
Get-ScheduledTask -TaskName TrueLogon

# Check logs (or open with CMTrace.exe for color-coded viewing)
Get-Content "C:\ProgramData\TrueLogon\Logs\TrueLogon-Install.log" -Tail 20
Get-Content "C:\ProgramData\TrueLogon\Logs\TrueLogon-Remediation.log" -Tail 20
```

## Script Parameters

| Script | Parameter | Default | Purpose |
|--------|-----------|---------|---------|
| Install.ps1 | -Uninstall | false | Remove True Logon |
| Install.ps1 | -WhatIf | false | Dry run |
| Detection.ps1 (Proactive) | -ProfileThreshold | 30 | Max profiles before remediation |
| Remediation.ps1 | -DaysThreshold | 90 | Days since logon to consider stale |
| Remediation.ps1 | -ExcludeUsers | @() | Additional usernames to protect |
| Remediation.ps1 | -WhatIf | false | Dry run |

## Deployment Constraints

- **Win32 App scripts** (W32App/): Packaged together, can reference each other
- **Proactive Remediation scripts**: Sent directly by Intune at runtime, must be 100% standalone (no shared modules possible)
- **TrueLogon.ps1**: Embedded in Install.ps1 as a here-string, written to disk during install

## Version Management

- Version is set in `Install.ps1` (`$Script:Version`)
- W32App/Detection.ps1 validates that a version value exists (not a specific version)
- Only Install.ps1 needs updating when bumping versions

## Legacy Cleanup

Install.ps1 automatically removes previous versions:
- Scheduled tasks: "User Logon Registry Stamp", "UserLogonTracking"
- Registry paths:
  - `HKLM:\SOFTWARE\Walmart Applications\WindowsEngineeringOS\UserLogonTracking`
  - `HKLM:\SOFTWARE\Walmart Applications\WindowsEngineering\UserLogonRegistryStamp`

## Code Patterns

All scripts follow these conventions:
- `#Requires -Version 5.1` and `#Requires -RunAsAdministrator`
- `Set-StrictMode -Version 3.0`
- `[CmdletBinding()]` for advanced parameter support
- CMTrace format logging (viewable with CMTrace.exe/OneTrace)
- Exit codes: 0 (success/compliant), 1 (failure/non-compliant), 2 (error)

## Protected Accounts

These profiles are never removed:
- System accounts (S-1-5-18, S-1-5-19, S-1-5-20)
- Default, Default User, Public, All Users
- Administrator, Moonpie
- Currently logged-in users

## Technology Stack

- PowerShell 5.1+ (no external modules required)
- Windows Registry for tracking data
- CIM/WMI classes (Win32_UserProfile, Win32_ComputerSystem)
- Microsoft Intune for deployment
