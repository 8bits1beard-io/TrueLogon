#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Detection script for Intune Proactive Remediation to identify machines with excessive user profiles.

.DESCRIPTION
    Counts user profiles on the Windows workstation and triggers remediation if the total exceeds the threshold.
    Uses the registry ProfileList to enumerate all registered user profiles.

.PARAMETER ProfileThreshold
    Maximum number of user profiles allowed before triggering remediation. Default is 30.

.EXAMPLE
    .\Detection.ps1
    Runs detection with default threshold of 30 profiles.

.EXAMPLE
    .\Detection.ps1 -ProfileThreshold 50
    Runs detection with custom threshold of 50 profiles.

.NOTES
    Author:  Joshua Walderbach
    Version: 1.0.0
    Created: 2025-11-18
    Exit 0:  Compliant (at or below threshold)
    Exit 1:  Non-compliant (exceeds threshold, triggers remediation)
    Exit 2:  Critical error during detection
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 999)]
    [int]$ProfileThreshold = 30
)

$ErrorActionPreference = 'Stop'

# Configuration
$Script:Config = @{
    ProfileThreshold = $ProfileThreshold
    ProfileListPath  = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
}

# System SIDs to exclude from counting (well-known system accounts)
$Script:ExcludedSIDs = @(
    'S-1-5-18',  # Local System
    'S-1-5-19',  # Local Service
    'S-1-5-20'   # Network Service
)

try {
    # Get all profile subkeys from registry
    if (-not (Test-Path $Script:Config.ProfileListPath)) {
        Write-Output "ERROR: ProfileList registry path not found"
        exit 2
    }

    $allProfiles = Get-ChildItem -Path $Script:Config.ProfileListPath -ErrorAction Stop

    # Filter to user profiles only
    $userProfiles = $allProfiles | Where-Object {
        $sid = $_.PSChildName

        # Exclude system SIDs
        if ($Script:ExcludedSIDs -contains $sid) {
            return $false
        }

        # Exclude well-known SIDs (anything ending in specific patterns)
        # S-1-5-21-... are domain/local user accounts (what we want to count)
        if ($sid -match '^S-1-5-21-') {
            return $true
        }

        return $false
    }

    $profileCount = $userProfiles.Count

    # Check against threshold
    if ($profileCount -gt $Script:Config.ProfileThreshold) {
        Write-Output "Total profile count exceeds $($Script:Config.ProfileThreshold), found $profileCount"
        exit 1  # Non-compliant, trigger remediation
    }
    else {
        Write-Output "Compliant: Found $profileCount user profiles (threshold: $($Script:Config.ProfileThreshold))"
        exit 0  # Compliant
    }
}
catch {
    Write-Output "ERROR: Failed to enumerate user profiles - $($_.Exception.Message)"
    exit 2  # Critical error
}
