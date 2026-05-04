<#
.SYNOPSIS
    Checks Windows Update status across one or more machines.

.DESCRIPTION
    Queries local or remote machines for installed and pending Windows Updates.
    Reports last update time, pending update count, and reboot status.
    Exports results to CSV for compliance tracking and audit purposes.
    Designed for Tier 1/2 sysadmin patch compliance checks.

.PARAMETER ComputerName
    One or more computer names to check.
    Defaults to the local machine.

.PARAMETER ReportPath
    Path where the CSV report will be saved.
    Default is C:\IT\Reports\PatchStatus.csv

.EXAMPLE
    # Check local machine
    .\Get-PatchStatus.ps1

.EXAMPLE
    # Check multiple machines
    .\Get-PatchStatus.ps1 -ComputerName "WRK01","WRK02","DC01"

.EXAMPLE
    # Custom report path
    .\Get-PatchStatus.ps1 -ComputerName "WRK01" -ReportPath "C:\Audit\patches.csv"

.NOTES
    Author: Ebrima Jallow
    Requires: Admin rights on target machines, WinRM enabled for remote checks
    Run As: Domain Admin or Local Admin
#>

param (
    [Parameter(Mandatory = $false)]
    [string[]]$ComputerName = $env:COMPUTERNAME,

    [Parameter(Mandatory = $false)]
    [string]$ReportPath = "C:\IT\Reports\PatchStatus.csv"
)

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$report    = @()

Write-Host "`n[INFO] Checking patch status on $($ComputerName.Count) machine(s)...`n" -ForegroundColor Cyan

foreach ($computer in $ComputerName) {

    Write-Host "  [$computer]" -ForegroundColor White

    try {
        $result = Invoke-Command -ComputerName $computer -ErrorAction Stop -ScriptBlock {

            # Get Windows Update session
            $updateSession   = New-Object -ComObject Microsoft.Update.Session
            $updateSearcher  = $updateSession.CreateUpdateSearcher()

            # Search for pending updates (not yet installed)
            $pendingUpdates  = $updateSearcher.Search("IsInstalled=0 and IsHidden=0")

            # Get last successful update install time from event log
            $lastUpdate = Get-HotFix | Sort-Object InstalledOn -Descending |
                Select-Object -First 1

            # Check if reboot is pending
            $rebootPending = $false
            $rebootKeys = @(
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
                "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
            )
            foreach ($key in $rebootKeys) {
                if (Test-Path $key) { $rebootPending = $true }
            }

            [PSCustomObject]@{
                PendingUpdateCount = $pendingUpdates.Updates.Count
                LastInstalledPatch = if ($lastUpdate) { $lastUpdate.HotFixID } else { "Unknown" }
                LastInstallDate    = if ($lastUpdate.InstalledOn) { $lastUpdate.InstalledOn.ToString("yyyy-MM-dd") } else { "Unknown" }
                RebootPending      = $rebootPending
                OSVersion          = (Get-WmiObject Win32_OperatingSystem).Caption
            }
        }

        $status = if ($result.PendingUpdateCount -eq 0) { "UP TO DATE" } else { "UPDATES PENDING" }
        $color  = if ($result.PendingUpdateCount -eq 0) { "Green" } else { "Yellow" }

        Write-Host "    Status:          $status" -ForegroundColor $color
        Write-Host "    Pending updates: $($result.PendingUpdateCount)" -ForegroundColor $color
        Write-Host "    Last patch:      $($result.LastInstalledPatch) on $($result.LastInstallDate)" -ForegroundColor Gray
        Write-Host "    Reboot pending:  $($result.RebootPending)" -ForegroundColor $(if ($result.RebootPending) { "Red" } else { "Gray" })
        Write-Host ""

        $report += [PSCustomObject]@{
            ComputerName       = $computer
            OSVersion          = $result.OSVersion
            PendingUpdateCount = $result.PendingUpdateCount
            LastInstalledPatch = $result.LastInstalledPatch
            LastInstallDate    = $result.LastInstallDate
            RebootPending      = $result.RebootPending
            Status             = $status
            CheckedAt          = $timestamp
        }

    } catch {
        Write-Host "    [ERROR] Could not reach $computer — $($_.Exception.Message)`n" -ForegroundColor Red

        $report += [PSCustomObject]@{
            ComputerName       = $computer
            OSVersion          = "N/A"
            PendingUpdateCount = "N/A"
            LastInstalledPatch = "N/A"
            LastInstallDate    = "N/A"
            RebootPending      = "N/A"
            Status             = "UNREACHABLE"
            CheckedAt          = $timestamp
        }
    }
}

# Export report
$reportDir = Split-Path $ReportPath
if (-not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}
$report | Export-Csv -Path $ReportPath -NoTypeInformation

# Summary
Write-Host "--- SUMMARY ---" -ForegroundColor White
Write-Host "Machines checked:      $($ComputerName.Count)" -ForegroundColor White
Write-Host "Up to date:            $(($report | Where-Object Status -eq 'UP TO DATE').Count)" -ForegroundColor Green
Write-Host "Updates pending:       $(($report | Where-Object Status -eq 'UPDATES PENDING').Count)" -ForegroundColor Yellow
Write-Host "Reboots pending:       $(($report | Where-Object RebootPending -eq $true).Count)" -ForegroundColor Red
Write-Host "Unreachable:           $(($report | Where-Object Status -eq 'UNREACHABLE').Count)" -ForegroundColor Gray
Write-Host "Report saved to:       $ReportPath`n" -ForegroundColor Cyan
