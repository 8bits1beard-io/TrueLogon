#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Detection script for Intune Win32 app detection or manual validation of True Logon installation.

.DESCRIPTION
    Validates that the True Logon system is properly installed and functional by checking
    five required components: scheduled task, script file, registry path, registry entries, and version marker.

    This script is designed for Intune Win32 app detection or manual validation. When components
    are missing or non-functional, it returns exit code 1.

.NOTES
    Author:  Joshua Walderbach
    Version: 1.0.0
    Created: 2025-11-18

    Exit Codes:
    - 0: Fully compliant (all 5 components present and functional)
    - 1: Non-compliant
    - 2: Critical error during detection

    Components Validated:
    1. Scheduled Task - Exists, enabled, and in valid state (Ready/Running)
    2. Script File - Exists at expected path
    3. Registry Path - Base registry key exists
    4. Registry Entries - User logon data is present
    5. Version Marker - Registry version value exists and is not empty

.EXAMPLE
    .\Detection.ps1
    Runs detection and outputs compliance status to console (captured by Intune).
#>

[CmdletBinding()]
param()

# Set strict mode for better error handling
Set-StrictMode -Version Latest

#region Logging Function
function Write-LogMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,
        [Parameter(Mandatory = $false, Position = 1)]
        [ValidateSet('Verbose', 'Warning', 'Error', 'Information', 'Debug')]
        [string]$Level = 'Information',
        [Parameter(Mandatory = $false)]
        [string]$Component = 'Detection'
    )

    $LogPath = "C:\ProgramData\TrueLogon\Logs"
    $LogFile = Join-Path -Path $LogPath -ChildPath "TrueLogon-Detection.log"

    # Ensure directory exists
    if (-not (Test-Path -Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }

    # Map level to CMTrace type: 1=Info, 2=Warning, 3=Error
    $Type = switch ($Level) {
        'Error'   { 3 }
        'Warning' { 2 }
        default   { 1 }
    }

    $Now = Get-Date
    $Time = $Now.ToString("HH:mm:ss.fff")
    $Date = $Now.ToString("MM-dd-yyyy")
    $UtcOffset = [System.TimeZoneInfo]::Local.GetUtcOffset($Now).TotalMinutes

    $LogEntry = "<![LOG[$Message]LOG]!><time=`"$Time+$UtcOffset`" date=`"$Date`" component=`"$Component`" context=`"$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)`" type=`"$Type`" thread=`"$PID`" file=`"Detection.ps1`">"

    Add-Content -Path $LogFile -Value $LogEntry -Encoding UTF8 -ErrorAction SilentlyContinue
}
#endregion Logging Function

# Configuration variables - centralized for easy maintenance
$Script:Config = @{
    TaskName = "TrueLogon"
    ScriptPath = 'C:\ProgramData\TrueLogon\TrueLogon.ps1'
    RegistryPath = "HKLM:\Software\TrueLogon"
    RequiredComponents = 5    # Total number of components to validate
    VersionValueName = "Version"
}

# Initialize detection results
$DetectionResults = @{
    ScheduledTask = $false
    ScriptFile = $false
    RegistryPath = $false
    RegistryEntries = $false
    Version = $false
}

$ErrorMessages = @()

Write-LogMessage -Message "Starting True Logon detection script" -Level 'Information'

try {
    # Test 1: Check for scheduled task (existence and state)
    try {
        # Use registry method directly for better performance and reliability
        $TaskRegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\$($Script:Config.TaskName)"
        if (Test-Path $TaskRegistryPath -ErrorAction SilentlyContinue) {
            # Task exists, now verify it's enabled and functional
            try {
                $TaskInfo = Get-ScheduledTask -TaskName $Script:Config.TaskName -ErrorAction Stop

                # Check if task is disabled
                if ($TaskInfo.State -eq 'Disabled') {
                    $ErrorMessages += "Scheduled task '$($Script:Config.TaskName)' exists but is disabled"
                    $DetectionResults.ScheduledTask = $false
                    Write-LogMessage -Message "Scheduled Task check: FAILED - Task is disabled" -Level 'Warning'
                }
                # Check if task is in a valid state (Ready or Running are good)
                elseif ($TaskInfo.State -notin @('Ready', 'Running')) {
                    $ErrorMessages += "Scheduled task '$($Script:Config.TaskName)' is in unexpected state: $($TaskInfo.State)"
                    $DetectionResults.ScheduledTask = $false
                    Write-LogMessage -Message "Scheduled Task check: FAILED - Task in unexpected state: $($TaskInfo.State)" -Level 'Warning'
                }
                else {
                    $DetectionResults.ScheduledTask = $true
                    Write-LogMessage -Message "Scheduled Task check: PASSED - Task exists and is in state: $($TaskInfo.State)" -Level 'Information'
                }
            } catch {
                # Fall back to existence check if Get-ScheduledTask fails
                $ErrorMessages += "Warning: Could not verify task state: $($_.Exception.Message)"
                $DetectionResults.ScheduledTask = $true  # Task exists, assume functional
                Write-LogMessage -Message "Scheduled Task check: PASSED (with warning) - Task exists but state verification failed" -Level 'Warning'
            }
        } else {
            $ErrorMessages += "Scheduled task '$($Script:Config.TaskName)' not found in registry"
            Write-LogMessage -Message "Scheduled Task check: FAILED - Task not found in registry" -Level 'Error'
        }
    } catch {
        $ErrorMessages += "Error checking scheduled task: $($_.Exception.Message)"
        Write-LogMessage -Message "Scheduled Task check: FAILED - Error: $($_.Exception.Message)" -Level 'Error'
    }

    # Test 2: Check for tracking script file
    try {
        if (Test-Path $Script:Config.ScriptPath) {
            $DetectionResults.ScriptFile = $true
            Write-LogMessage -Message "Script File check: PASSED - File exists at $($Script:Config.ScriptPath)" -Level 'Information'
        } else {
            $ErrorMessages += "Script file not found: $($Script:Config.ScriptPath)"
            Write-LogMessage -Message "Script File check: FAILED - File not found at $($Script:Config.ScriptPath)" -Level 'Error'
        }
    } catch {
        $ErrorMessages += "Error checking script file: $($_.Exception.Message)"
        Write-LogMessage -Message "Script File check: FAILED - Error: $($_.Exception.Message)" -Level 'Error'
    }

    # Test 3: Check for registry path
    try {
        if (Test-Path $Script:Config.RegistryPath) {
            $DetectionResults.RegistryPath = $true
            Write-LogMessage -Message "Registry Path check: PASSED - Path exists at $($Script:Config.RegistryPath)" -Level 'Information'
        } else {
            $ErrorMessages += "Registry path not found: $($Script:Config.RegistryPath)"
            Write-LogMessage -Message "Registry Path check: FAILED - Path not found at $($Script:Config.RegistryPath)" -Level 'Error'
        }
    } catch {
        $ErrorMessages += "Error checking registry path: $($_.Exception.Message)"
        Write-LogMessage -Message "Registry Path check: FAILED - Error: $($_.Exception.Message)" -Level 'Error'
    }

    # Test 4: Check for registry entries (user profiles)
    try {
        if ($DetectionResults.RegistryPath) {
            $RegistryEntries = Get-ChildItem -Path $Script:Config.RegistryPath -ErrorAction SilentlyContinue |
                Where-Object { $_.PSChildName -match '^S-1-5-21-' } |
                Measure-Object

            if ($RegistryEntries.Count -gt 0) {
                $DetectionResults.RegistryEntries = $true
                Write-LogMessage -Message "Registry Entries check: PASSED - Found $($RegistryEntries.Count) user profile entries" -Level 'Information'
            } else {
                $ErrorMessages += "No user profile entries found in registry"
                Write-LogMessage -Message "Registry Entries check: FAILED - No user profile entries found" -Level 'Warning'
            }
        } else {
            $ErrorMessages += "Cannot check registry entries - registry path does not exist"
            Write-LogMessage -Message "Registry Entries check: SKIPPED - Registry path does not exist" -Level 'Warning'
        }
    } catch {
        $ErrorMessages += "Error checking registry entries: $($_.Exception.Message)"
        Write-LogMessage -Message "Registry Entries check: FAILED - Error: $($_.Exception.Message)" -Level 'Error'
    }

    # Test 5: Check for registry version marker (exists and is not empty)
    try {
        if ($DetectionResults.RegistryPath) {
            $VersionValue = (Get-ItemProperty -Path $Script:Config.RegistryPath -ErrorAction SilentlyContinue).$($Script:Config.VersionValueName)
            if (-not [string]::IsNullOrWhiteSpace($VersionValue)) {
                $DetectionResults.Version = $true
                Write-LogMessage -Message "Version check: PASSED - Version value is '$VersionValue'" -Level 'Information'
            } else {
                $ErrorMessages += "Registry version value is missing or empty"
                Write-LogMessage -Message "Version check: FAILED - Version value is missing or empty" -Level 'Error'
            }
        } else {
            $ErrorMessages += "Cannot check registry version - registry path does not exist"
            Write-LogMessage -Message "Version check: SKIPPED - Registry path does not exist" -Level 'Warning'
        }
    } catch {
        $ErrorMessages += "Error checking registry version: $($_.Exception.Message)"
        Write-LogMessage -Message "Version check: FAILED - Error: $($_.Exception.Message)" -Level 'Error'
    }

    # Determine overall success
    $SuccessfulComponents = $DetectionResults.Values | Where-Object { $_ -eq $true } | Measure-Object
    $FailedComponents = @()

    # Check each component and build list of failures
    if (-not $DetectionResults.ScheduledTask) {
        $FailedComponents += "Scheduled Task"
    }
    if (-not $DetectionResults.ScriptFile) {
        $FailedComponents += "Script File"
    }
    if (-not $DetectionResults.RegistryPath) {
        $FailedComponents += "Registry Path"
    }
    if (-not $DetectionResults.RegistryEntries) {
        $FailedComponents += "Registry Entries"
    }
    if (-not $DetectionResults.Version) {
        $FailedComponents += "Version"
    }

    # Determine installation status and exit code
    if ($SuccessfulComponents.Count -eq $Script:Config.RequiredComponents) {
        Write-LogMessage -Message "Detection complete: COMPLIANT - All $($Script:Config.RequiredComponents) components present and functional" -Level 'Information'
        Write-Output "True Logon system is fully compliant - all components present"
        exit 0  # Compliant
    } else {
        Write-LogMessage -Message "Detection complete: NON-COMPLIANT - $($SuccessfulComponents.Count)/$($Script:Config.RequiredComponents) components passed. Failed: $($FailedComponents -join ', ')" -Level 'Warning'
        Write-Output "True Logon system is not compliant"
        Write-Output "Failed components: $($FailedComponents -join ', ')"
        if ($ErrorMessages.Count -gt 0) {
            Write-Output "Detailed errors: $($ErrorMessages -join '; ')"
        }
        exit 1  # Non-compliant (will trigger remediation)
    }

} catch {
    Write-LogMessage -Message "Detection complete: CRITICAL ERROR - $($_.Exception.Message)" -Level 'Error'
    Write-Error "Critical error during detection: $($_.Exception.Message)"
    exit 2  # Error
}
