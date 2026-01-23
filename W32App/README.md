# W32App (True Logon Installer)

This folder contains the Win32 app scripts used to install and detect the True Logon system.

## Contents

- `Install.ps1` installs or uninstalls True Logon.
- `Detection.ps1` validates the install for Win32 app detection.
- `IntuneWinAppUtil.exe` packages the scripts into an .intunewin file.

## Package the app

From the repository root, run:

```powershell
.\W32App\IntuneWinAppUtil.exe -c .\W32App -s Install.ps1 -o .\W32App
```

Change `-o .\W32App` to specify a different output path if needed.

## Create the app in Intune

When creating the Win32 app in Intune, use these values:

| Field | Value |
|-------|-------|
| Name | True Logon |
| Description | Tracks user logon activity and enables automated cleanup of stale profiles |
| Publisher | Windows Engineering OS |
| App Version | 1.0.0 |
| Developer | Joshua Walderbach |
| Owner | Windows Engineering OS |
| Information URL | https://gecgithub01.walmart.com/WinEngOS/TrueLogon |
| Category | Computer Management |

## Install and uninstall commands

Install:
```powershell
PowerShell.exe -ExecutionPolicy Bypass -File .\W32App\Install.ps1
```

Uninstall:
```powershell
PowerShell.exe -ExecutionPolicy Bypass -File .\W32App\Install.ps1 -Uninstall
```

## Detection rule

Recommended scripted detection:
- Script: `W32App/Detection.ps1`

Alternative rule-based detection:
- Registry value: `HKLM:\Software\TrueLogon\Version` equals `1.0.0`
- Scheduled task `TrueLogon` exists
- Script file exists at `C:\ProgramData\TrueLogon\TrueLogon.ps1`

## Troubleshooting

Logs are written in CMTrace format to `C:\ProgramData\TrueLogon\Logs\`. Open with CMTrace.exe or OneTrace for color-coded viewing.

- `TrueLogon-Install.log` - Installation and uninstallation
- `TrueLogon-Detection.log` - Win32 app detection checks

## Upgrades

1. Bump the version in `Install.ps1` and `Detection.ps1`.
2. Rebuild the .intunewin package.
3. Supersede or replace the existing Win32 app in Intune.

### Migrating from legacy versions

The installer automatically cleans up previous versions of this tool:
- Removes scheduled tasks: "User Logon Registry Stamp", "UserLogonTracking"
- Removes registry paths:
  - `HKLM:\SOFTWARE\Walmart Applications\WindowsEngineeringOS\UserLogonTracking`
  - `HKLM:\SOFTWARE\Walmart Applications\WindowsEngineering\UserLogonRegistryStamp`

No manual cleanup is required when upgrading.
