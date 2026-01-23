#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Installs or uninstalls the True Logon system for monitoring user logon activity.

.DESCRIPTION
    Install.ps1 sets up or removes a comprehensive user logon tracking system for Windows environments.
    The script creates a scheduled task that executes at user logon to record username and timestamp data in both
    registry and log files. It supports complete uninstallation to remove all associated artifacts.
    
    Key features include:
    - Automated scheduled task creation for logon tracking
    - Registry-based user activity storage with fallback logging
    - Comprehensive uninstall capability for complete system cleanup
    - Enterprise-grade logging with JSON format and rotation
    - Security validation and privilege checking
    - Robust error handling with detailed audit trails

.AUTHOR
    Joshua Walderbach

.VERSION
    1.0.0

.CREATED
    2025-06-09

.LASTUPDATED
    2026-01-23

.PARAMETER Uninstall
    Switch parameter to remove the scheduled task, registry keys, and script files created by this system.
    When specified, performs complete cleanup of all True Logon components.

.PARAMETER WhatIf
    Switch parameter to run the script in simulation mode without actually making changes.
    Shows what would be installed or uninstalled without modifying the system.

.EXAMPLE
    # Basic Usage - Initialize Tracking System
    PS> .\Install.ps1
    Initializes the complete user logon tracking system including scheduled task and registry setup.

.EXAMPLE
    # Uninstall Mode - Remove All Components
    PS> .\Install.ps1 -Uninstall
    Removes the logon tracking system and all associated components including tasks, registry keys, and files.

.NOTES
    - Requires PowerShell 5.1 or later
    - Requires Administrator privileges for registry and scheduled task operations
    - No additional modules required - uses built-in Windows cmdlets
    - Script follows Microsoft PowerShell Best Practices and POSH Style Guide
    - Creates scheduled task running as SYSTEM account for security
    - All operations are logged with enterprise-grade audit trails
    - For support contact: joshua.walderbach@walmart.com
    - Use Get-Help Install.ps1 -Full for complete documentation

.CHANGELOG
    - 2026-01-23: v1.0.0 - Initial Win32 app installer version
#>

[CmdletBinding()]
param (
    [Parameter(HelpMessage = "Remove the True Logon system and all associated components")]
    [switch]$Uninstall,

    [Parameter(HelpMessage = "Run in simulation mode without making changes")]
    [switch]$WhatIf
)

$Script:Version = "1.0.0"
$Script:RegistryPath = "HKLM:\Software\TrueLogon"

function Write-LogMessage {
    <#
    .SYNOPSIS
        Writes log messages in CMTrace format with automatic log rotation.

    .DESCRIPTION
        Logs messages to a specified file in CMTrace format, compatible with CMTrace.exe and OneTrace.
        Supports automatic log file rotation when size threshold is exceeded.

    .PARAMETER Message
        The message to be logged.

    .PARAMETER Level
        The severity level: Verbose, Warning, Error, Information, Debug.
        Default: Information

    .PARAMETER Component
        The component or script name generating the log entry.
        Default: 'Install'

    .PARAMETER LogPath
        The directory where the log file will be stored.
        Default: C:\ProgramData\TrueLogon\Logs

    .PARAMETER LogFileName
        The name of the log file.
        Default: TrueLogon.log

    .PARAMETER MaxFileSizeMB
        Maximum log file size in MB before rotation. Default: 5 MB

    .EXAMPLE
        Write-LogMessage -Message "Script started" -Level Information

    .NOTES
        CMTrace format enables viewing with CMTrace.exe/OneTrace with color-coded severity.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory = $false, Position = 1)]
        [ValidateSet('Verbose', 'Warning', 'Error', 'Information', 'Debug')]
        [string]$Level = 'Information',

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$Component = 'Install',

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$LogPath = "C:\ProgramData\TrueLogon\Logs",

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$LogFileName = "TrueLogon-Install.log",

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 100)]
        [int]$MaxFileSizeMB = 5
    )

    begin {
        $LogFile = Join-Path -Path $LogPath -ChildPath $LogFileName

        # Ensure the directory exists
        if (-not (Test-Path -Path $LogPath)) {
            try {
                New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
            }
            catch {
                Write-Warning "Failed to create log directory at '$LogPath': $($_.Exception.Message)"
                return
            }
        }

        # Check if the log file exists and its size - rotate if needed
        if (Test-Path -Path $LogFile) {
            $FileSizeMB = (Get-Item -Path $LogFile).Length / 1MB
            if ($FileSizeMB -ge $MaxFileSizeMB) {
                $Timestamp = Get-Date -Format "yyyyMMddHHmmss"
                $ArchivedLog = "$LogFile.$Timestamp.bak"
                try {
                    Rename-Item -Path $LogFile -NewName $ArchivedLog -ErrorAction Stop
                }
                catch {
                    Write-Warning "Log rotation failed for '$LogFile'. Continuing with existing file."
                }
            }
        }
    }

    process {
        try {
            # Map level to CMTrace type: 1=Info, 2=Warning, 3=Error
            $Type = switch ($Level) {
                'Error'   { 3 }
                'Warning' { 2 }
                default   { 1 }
            }

            # Build CMTrace format timestamp
            $Now = Get-Date
            $Time = $Now.ToString("HH:mm:ss.fff")
            $Date = $Now.ToString("MM-dd-yyyy")

            # Get timezone offset
            $UtcOffset = [System.TimeZoneInfo]::Local.GetUtcOffset($Now).TotalMinutes

            # Build CMTrace log entry
            $LogEntry = "<![LOG[$Message]LOG]!><time=`"$Time+$UtcOffset`" date=`"$Date`" component=`"$Component`" context=`"$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)`" type=`"$Type`" thread=`"$PID`" file=`"$($MyInvocation.ScriptName | Split-Path -Leaf)`">"

            # Write the log entry
            Add-Content -Path $LogFile -Value $LogEntry -Encoding UTF8 -ErrorAction Stop

            # Output to console based on log level
            switch ($Level) {
                'Verbose'     { if ($VerbosePreference -ne 'SilentlyContinue') { Write-Verbose -Message $Message } }
                'Warning'     { Write-Warning -Message $Message }
                'Error'       { Write-Error -Message $Message }
                'Information' { Write-Information -MessageData $Message -InformationAction Continue }
                'Debug'       { if ($DebugPreference -ne 'SilentlyContinue') { Write-Debug -Message $Message } }
            }
        }
        catch {
            Write-Warning "Failed to write log entry: $($_.Exception.Message)"
        }
    }
}

# Initialize logging
$whatIfText = if ($WhatIf) { " [WHATIF MODE]" } else { "" }
Write-LogMessage -Message "Install v$Script:Version started$whatIfText - Uninstall: $Uninstall" -Level Information

# Clean up legacy scheduled tasks from previous versions of this tool
$LegacyTaskNames = @("User Logon Registry Stamp", "UserLogonTracking")
foreach ($LegacyTask in $LegacyTaskNames) {
    schtasks.exe /Query /TN $LegacyTask /FO LIST /V > $null 2>&1
    if ($LASTEXITCODE -eq 0) {
        try {
            if ($WhatIf) {
                Write-LogMessage -Message "[WHATIF] Would remove legacy scheduled task '$LegacyTask'" -Level Information
                Write-Host "[WHATIF] Would remove legacy scheduled task '$LegacyTask'" -ForegroundColor Magenta
            }
            else {
                schtasks.exe /Delete /TN $LegacyTask /F > $null 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-LogMessage -Message "Legacy scheduled task '$LegacyTask' removed successfully" -Level Information
                    Write-Host "Removed legacy scheduled task: $LegacyTask" -ForegroundColor Cyan
                }
                else {
                    Write-LogMessage -Message "Failed to remove legacy scheduled task '$LegacyTask'. Exit code: $LASTEXITCODE" -Level Warning
                }
            }
        }
        catch {
            Write-LogMessage -Message "Exception while removing legacy task '$LegacyTask': $($_.Exception.Message)" -Level Warning
        }
    }
}

# Clean up legacy registry paths from previous versions of this tool
$LegacyRegistryPaths = @(
    "HKLM:\SOFTWARE\Walmart Applications\WindowsEngineeringOS\UserLogonTracking",
    "HKLM:\SOFTWARE\Walmart Applications\WindowsEngineering\UserLogonRegistryStamp"
)
foreach ($LegacyRegPath in $LegacyRegistryPaths) {
    if (Test-Path $LegacyRegPath) {
        try {
            if ($WhatIf) {
                Write-LogMessage -Message "[WHATIF] Would remove legacy registry path '$LegacyRegPath'" -Level Information
                Write-Host "[WHATIF] Would remove legacy registry path '$LegacyRegPath'" -ForegroundColor Magenta
            }
            else {
                Remove-Item -Path $LegacyRegPath -Recurse -Force -ErrorAction Stop
                Write-LogMessage -Message "Legacy registry path '$LegacyRegPath' removed successfully" -Level Information
                Write-Host "Removed legacy registry path: $LegacyRegPath" -ForegroundColor Cyan
            }
        }
        catch {
            Write-LogMessage -Message "Failed to remove legacy registry path '$LegacyRegPath': $($_.Exception.Message)" -Level Warning
        }
    }
}

# Handle uninstall mode
if ($Uninstall) {
    Write-LogMessage -Message "Uninstall mode activated$whatIfText" -Level Information
    Write-Host "Uninstall mode activated. Reversing initialization..." -ForegroundColor Magenta
    
    # Remove scheduled task using schtasks.exe
    $TaskName = "TrueLogon"
    schtasks.exe /Query /TN $TaskName /FO LIST /V > $null 2>&1

    if ($LASTEXITCODE -eq 0) {
        try {
            if ($WhatIf) {
                Write-LogMessage -Message "[WHATIF] Would remove scheduled task '$TaskName'" -Level Information
                Write-Host "[WHATIF] Would remove scheduled task '$TaskName'" -ForegroundColor Magenta
            }
            else {
                schtasks.exe /Delete /TN $TaskName /F
                if ($LASTEXITCODE -eq 0) {
                    Write-LogMessage -Message "Scheduled task '$TaskName' removed successfully" -Level Information
                    Write-Host "Scheduled task '$TaskName' removed." -ForegroundColor Cyan
                } else {
                    Write-LogMessage -Message "schtasks.exe returned exit code $LASTEXITCODE when attempting to delete task '$TaskName'" -Level Error
                    Write-Warning "Failed to remove scheduled task '$TaskName'. Exit code: $LASTEXITCODE"
                }
            }
        }
        catch {
            Write-LogMessage -Message "Exception occurred while removing scheduled task '$TaskName': $($_.Exception.Message)" -Level Error
            Write-Warning "Failed to remove scheduled task '$TaskName': $($_.Exception.Message)"
        }
    }
    else {
        Write-Host "Scheduled task '$TaskName' not found." -ForegroundColor Yellow
    }

    # Remove script file
    $ScriptPath = 'C:\ProgramData\TrueLogon\TrueLogon.ps1'
    if (Test-Path $ScriptPath) {
        try {
            if ($WhatIf) {
                Write-LogMessage -Message "[WHATIF] Would remove script file: $ScriptPath" -Level Information
                Write-Host "[WHATIF] Would remove script file: $ScriptPath" -ForegroundColor Magenta
            }
            else {
                Remove-Item -Path $ScriptPath -Force -ErrorAction Stop
                Write-LogMessage -Message "Script file removed: $ScriptPath" -Level Information
                Write-Host "Script file removed: $ScriptPath" -ForegroundColor Cyan
            }
        }
        catch {
            Write-LogMessage -Message "Failed to remove script file '$ScriptPath': $($_.Exception.Message)" -Level Error
            Write-Warning "Failed to remove script file: $($_.Exception.Message)"
        }
    }
    else {
        Write-Host "$ScriptPath not found." -ForegroundColor Yellow
    }

    # Remove registry key
    $RegistryPath = $Script:RegistryPath
    if (Test-Path $RegistryPath) {
        try {
            if ($WhatIf) {
                Write-LogMessage -Message "[WHATIF] Would remove registry key: $RegistryPath" -Level Information
                Write-Host "[WHATIF] Would remove registry key: $RegistryPath" -ForegroundColor Magenta
            }
            else {
                Remove-Item -Path $RegistryPath -Recurse -Force -ErrorAction Stop
                Write-LogMessage -Message "Registry key removed: $RegistryPath" -Level Information
                Write-Host "Registry key removed: $RegistryPath" -ForegroundColor Cyan
            }
        }
        catch {
            Write-LogMessage -Message "Failed to remove registry key '$RegistryPath': $($_.Exception.Message)" -Level Error
            Write-Warning "Failed to remove registry key: $($_.Exception.Message)"
        }
    }
    else {
        Write-Host "$RegistryPath not found." -ForegroundColor Yellow
    }

    # Remove folder only if empty (logs are intentionally preserved for troubleshooting)
    $ScriptFolder = Split-Path -Path $ScriptPath -Parent
    if ((Test-Path $ScriptFolder) -and (-not (Get-ChildItem -Path $ScriptFolder -Force))) {
        try {
            if ($WhatIf) {
                Write-LogMessage -Message "[WHATIF] Would remove empty folder: $ScriptFolder" -Level Information
                Write-Host "[WHATIF] Would remove empty folder: $ScriptFolder" -ForegroundColor Magenta
            }
            else {
                Remove-Item -Path $ScriptFolder -Force -ErrorAction Stop
                Write-LogMessage -Message "Empty folder removed: $ScriptFolder" -Level Information
                Write-Host "Removed empty folder: $ScriptFolder" -ForegroundColor Cyan
            }
        }
        catch {
            Write-LogMessage -Message "Failed to remove folder '$ScriptFolder': $($_.Exception.Message)" -Level Error
            Write-Warning "Failed to remove folder '$ScriptFolder': $($_.Exception.Message)"
        }
    }
    elseif (Test-Path $ScriptFolder) {
        Write-LogMessage -Message "Folder preserved (contains logs): $ScriptFolder" -Level Information
        Write-Host "Logs preserved at: $ScriptFolder\Logs\" -ForegroundColor Cyan
    }

    Write-LogMessage -Message "Uninstall process completed$whatIfText" -Level Information
    exit 0
}

function Initialize-UserLogonRegistry {
    [CmdletBinding()]
    param (
        [string]$RegistryPath = $Script:RegistryPath,
        [string[]]$ExcludeUsers = @("Default", "Default User", "Public", "All Users", "Administrator", "Moonpie"),
        [switch]$WhatIf
    )

    Set-StrictMode -Version 3.0

    $whatIfText = if ($WhatIf) { " [WHATIF]" } else { "" }
    Write-LogMessage -Message "Initialize-UserLogonRegistry started$whatIfText" -Level Information
    
    # Use the last modified date of each user profile folder as the last logon date to record in the registry.
    $AddedCount = 0
    try {
        if (-not (Test-Path $RegistryPath)) {
            if ($WhatIf) {
                Write-LogMessage -Message "[WHATIF] Would create registry path: $RegistryPath" -Level Information
            }
            else {
                New-Item -Path $RegistryPath -Force -ErrorAction Stop | Out-Null
                Write-LogMessage -Message "Registry path created: $RegistryPath" -Level Information
            }
        }

        $UserProfiles = Get-CimInstance -ClassName Win32_UserProfile | Where-Object { -not $_.Special }
        Write-LogMessage -Message "Found $($UserProfiles.Count) user profiles" -Level Information

        $UserProfiles | ForEach-Object {
            $ProfilePath = $_.LocalPath
            $ProfileName = Split-Path -Path $ProfilePath -Leaf
            $ProfileSid = $_.SID

            if ($ExcludeUsers -contains $ProfileName) {
                return
            }

            $LastModified = if ($ProfilePath -and (Test-Path -Path $ProfilePath)) {
                (Get-Item -Path $ProfilePath).LastWriteTime.ToString("yyyy-MM-ddTHH:mm:ss")
            }
            else {
                (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            }

            $SidRegistryPath = Join-Path -Path $RegistryPath -ChildPath $ProfileSid

            try {
                if ($WhatIf) {
                    $AddedCount++
                    Write-LogMessage -Message "[WHATIF] Would add SID '$ProfileSid' (user '$ProfileName') to registry with timestamp: $LastModified" -Level Information
                }
                else {
                    New-Item -Path $SidRegistryPath -Force | Out-Null
                    New-ItemProperty -Path $SidRegistryPath -Name "Username" -Value $ProfileName -PropertyType String -Force | Out-Null
                    New-ItemProperty -Path $SidRegistryPath -Name "LastLogon" -Value $LastModified -PropertyType String -Force | Out-Null
                    New-ItemProperty -Path $SidRegistryPath -Name "ProfilePath" -Value $ProfilePath -PropertyType String -Force | Out-Null
                    $AddedCount++
                    Write-LogMessage -Message "Added SID '$ProfileSid' (user '$ProfileName') to registry with timestamp: $LastModified" -Level Information
                }
            }
            catch {
                Write-LogMessage -Message "Failed to write profile SID '$ProfileSid' to registry: $($_.Exception.Message)" -Level Error
                Write-Warning "An error occurred while writing $ProfileSid to registry: $_"
            }
        }

        Write-LogMessage -Message "User profile processing completed$whatIfText. Total profiles added to registry: $AddedCount" -Level Information
        Write-Host "Total user profiles added to registry: $AddedCount"
    }
    catch {
        Write-LogMessage -Message "Critical error occurred during registry initialization: $($_.Exception.Message)" -Level Error
        Write-Warning "An error occurred during initialization: $_"
    }
}

# Run the initialization
Initialize-UserLogonRegistry -WhatIf:$WhatIf

# Define the logon tracking script content
$TrueLogon_Script = @'
function Enable-TrueLogon {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$RegistryPath = "HKLM:\Software\TrueLogon",

        [Parameter()]
        [string]$LogPath = "C:\ProgramData\TrueLogon\Logs\TrueLogon-Tracking.log"
    )

    Set-StrictMode -Version 3.0

    $Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
    $SafeUsername = "UnknownUser"
    $UserSid = $null

    # Get the current logged-in user
    $Session = (Get-CimInstance -ClassName Win32_ComputerSystem).UserName
    if ($Session) {
        $Domain, $Username = $Session -split '\\'
        $SafeUsername = $Username -replace '[\\/:*?"<>|]', '_'
    }

    try {
        $UserSid = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
    }
    catch {
        $UserSid = $null
    }

    try {
        # Create registry path if it doesn't exist
        if (-not (Test-Path $RegistryPath)) {
            New-Item -Path $RegistryPath -Force | Out-Null
        }

        if (-not $UserSid) {
            return $false
        }

        $SidRegistryPath = Join-Path -Path $RegistryPath -ChildPath $UserSid
        if (-not (Test-Path $SidRegistryPath)) {
            New-Item -Path $SidRegistryPath -Force | Out-Null
        }

        # Log the user logon to registry
        New-ItemProperty -Path $SidRegistryPath -Name "LastLogon" -Value $Timestamp -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $SidRegistryPath -Name "Username" -Value $SafeUsername -PropertyType String -Force | Out-Null
        if ($env:USERPROFILE) {
            New-ItemProperty -Path $SidRegistryPath -Name "ProfilePath" -Value $env:USERPROFILE -PropertyType String -Force | Out-Null
        }
        return $true
    } catch {
        # Log failure in CMTrace format
        try {
            $LogDir = Split-Path -Path $LogPath -Parent
            if (-not (Test-Path $LogDir)) {
                New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
            }

            $Now = Get-Date
            $Time = $Now.ToString("HH:mm:ss.fff")
            $Date = $Now.ToString("MM-dd-yyyy")
            $UtcOffset = [System.TimeZoneInfo]::Local.GetUtcOffset($Now).TotalMinutes
            $ErrorMsg = "Failed to record logon for user '$SafeUsername': $($_.Exception.Message)"
            $LogEntry = "<![LOG[$ErrorMsg]LOG]!><time=`"$Time+$UtcOffset`" date=`"$Date`" component=`"Tracking`" context=`"$SafeUsername`" type=`"3`" thread=`"$PID`" file=`"TrueLogon.ps1`">"
            Add-Content -Path $LogPath -Value $LogEntry -ErrorAction SilentlyContinue
        } catch {
            # If logging fails, continue silently - don't block logon
        }
        return $false
    }
}

Enable-TrueLogon
'@

# Save the script to disk
try {
    $ScriptPath = 'C:\ProgramData\TrueLogon\TrueLogon.ps1'
    $ScriptDirectory = Split-Path -Path $ScriptPath -Parent

    if (-not (Test-Path $ScriptDirectory)) {
        if ($WhatIf) {
            Write-LogMessage -Message "[WHATIF] Would create script directory: $ScriptDirectory" -Level Information
        }
        else {
            New-Item -ItemType Directory -Path $ScriptDirectory -Force | Out-Null
            Write-LogMessage -Message "Script directory created: $ScriptDirectory" -Level Information
        }
    }

    if ($WhatIf) {
        Write-LogMessage -Message "[WHATIF] Would create True Logon script file: $ScriptPath" -Level Information
    }
    else {
        Set-Content -Path $ScriptPath -Value $TrueLogon_Script -Force
        Write-LogMessage -Message "True Logon script file created: $ScriptPath" -Level Information
    }
}
catch {
    Write-LogMessage -Message "Failed to create True Logon script file '$ScriptPath': $($_.Exception.Message)" -Level Error
    Write-Warning "Failed to write tracking script: $_"
}

# Register the scheduled task
try {
    $TaskName = "TrueLogon"
    $ScriptPath = "C:\ProgramData\TrueLogon\TrueLogon.ps1"

    if ($WhatIf) {
        Write-LogMessage -Message "[WHATIF] Would register scheduled task '$TaskName' to run at logon as SYSTEM (Script: $ScriptPath)" -Level Information
    }
    else {
        $Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$ScriptPath`""

        $Trigger = New-ScheduledTaskTrigger -AtLogOn

        $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest -LogonType ServiceAccount

        $Task = New-ScheduledTask -Action $Action -Trigger $Trigger -Principal $Principal -Description "Tracks user logons and updates registry with timestamp"

        Register-ScheduledTask -TaskName $TaskName -InputObject $Task -Force
        Write-LogMessage -Message "Scheduled task '$TaskName' registered successfully" -Level Information
    }
}
catch {
    Write-LogMessage -Message "Failed to register scheduled task '$TaskName': $($_.Exception.Message)" -Level Error
    Write-Warning "Scheduled task registration failed: $_"
}

# Write version marker for Win32 app detection
try {
    if (-not (Test-Path -Path $Script:RegistryPath)) {
        New-Item -Path $Script:RegistryPath -Force | Out-Null
    }

    if ($WhatIf) {
        Write-LogMessage -Message "[WHATIF] Would write version $Script:Version to registry" -Level Information
    }
    else {
        New-ItemProperty -Path $Script:RegistryPath -Name "Version" -Value $Script:Version -PropertyType String -Force | Out-Null
        Write-LogMessage -Message "Registry version set to $Script:Version" -Level Information
    }
}
catch {
    Write-LogMessage -Message "Failed to write registry version: $($_.Exception.Message)" -Level Error
    Write-Warning "Failed to write registry version: $($_.Exception.Message)"
}

# Script execution completed
Write-LogMessage -Message "True Logon system installation completed successfully$whatIfText" -Level Information
exit 0
