# Proactive Remediation Scripts

This folder contains the Intune Proactive Remediation scripts used to detect and remove stale profiles.

## Contents

- `Detection.ps1` detects machines with excessive user profiles.
- `Remediation.ps1` removes stale profiles using True Logon registry data.

## Intune script package

- **Detection script:** `ProactiveRemediationScripts/Detection.ps1`
- **Remediation script:** `ProactiveRemediationScripts/Remediation.ps1`
- Run as 64-bit PowerShell using SYSTEM

## Troubleshooting

Remediation logs are written in CMTrace format to `C:\ProgramData\TrueLogon\Logs\TrueLogon-Remediation.log`. Open with CMTrace.exe or OneTrace for color-coded viewing.

Detection scripts output to stdout which is captured by Intune. Check the Intune portal for detection output.

## Common parameters

- `Detection.ps1`: `-ProfileThreshold 30`
- `Remediation.ps1`: `-DaysThreshold 90`, `-WhatIf`, `-ExcludeUsers @("user1", "user2")`
