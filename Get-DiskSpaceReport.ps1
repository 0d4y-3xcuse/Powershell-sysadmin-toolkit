<#
.SYNOPSIS
    Checks disk space across one or multiple computers and flags low storage.

.DESCRIPTION
    Queries local or remote machines for disk space usage on all fixed drives.
    Flags any drive below the specified threshold and exports a report to CSV.
    Designed for proactive storage monitoring across servers and workstations
    before low disk space causes service failures or performance issues.

.PARAMETER ComputerName
    One or more computer names to check. Defaults to the local machine.
    Accepts an array: -ComputerName "DC01","DC02","WRK01"

.PARAMETER ThresholdGB
    Disk space threshold in GB. Drives below this value are flagged as WARNING.
    Default is 10 GB.

.PARAMETER ReportPath
    Full path where the CSV report will be saved.
    Default is C:\IT\Reports\DiskSpaceReport.csv

.EXAMPLE
    # Check local machine only
    .\Get-DiskSpaceReport.ps1

.EXAMPLE
    # Check multiple remote machines
    .\Get-DiskSpaceReport.ps1 -ComputerName "DC01","DC02","WRK01"

.EXAMPLE
    # Custom threshold and report path
    .\Get-DiskSpaceReport.ps1 -ComputerName "DC01" -ThresholdGB 20 -ReportPath "C:\Audit\disk.csv"

.NOTES
    Author: Ebrima Jallow
    Requires: WMI/CIM access to remote machines (admin rights on targets)
    Run As: Local Admin or Domain Admin for remote checks
#>

param (
    [Parameter(Mandatory = $false)]
    [string[]]$ComputerName = $env:COMPUTERNAME,

    [Parameter(Mandatory = $false)]
    [int]$ThresholdGB = 10,

    [Parameter(Mandatory = $false)]
    [string]$ReportPath = "C:\IT\Reports\DiskSpaceReport.csv"
)

# --- Setup ---
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$report    = @()
$warnings  = 0

Write-Host "`n[INFO] Starting disk space check..." -ForegroundColor Cyan
Write-Host "[INFO] Threshold: $ThresholdGB GB | Checking $($ComputerName.Count) machine(s)`n" -ForegroundColor Cyan

# --- Check Each Machine ---
foreach ($computer in $ComputerName) {

    Write-Host "  [CHECKING] $computer..." -ForegroundColor White

    try {
        # Get all fixed drives (DriveType 3 = fixed local disk)
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk `
            -ComputerName $computer `
            -Filter "DriveType=3" `
            -ErrorAction Stop

        foreach ($disk in $disks) {

            $totalGB = [math]::Round($disk.Size / 1GB, 2)
            $freeGB  = [math]::Round($disk.FreeSpace / 1GB, 2)
            $usedGB  = [math]::Round($totalGB - $freeGB, 2)
            $freePct = [math]::Round(($freeGB / $totalGB) * 100, 1)
            $status  = if ($freeGB -lt $ThresholdGB) { "WARNING" } else { "OK" }

            if ($status -eq "WARNING") {
                Write-Host "    ⚠️  Drive $($disk.DeviceID) — $freeGB GB free of $totalGB GB ($freePct%) — BELOW THRESHOLD" -ForegroundColor Red
                $warnings++
            } else {
                Write-Host "    ✅  Drive $($disk.DeviceID) — $freeGB GB free of $totalGB GB ($freePct%)" -ForegroundColor Green
            }

            # Build report entry
            $report += [PSCustomObject]@{
                ComputerName  = $computer
                Drive         = $disk.DeviceID
                TotalGB       = $totalGB
                UsedGB        = $usedGB
                FreeGB        = $freeGB
                FreePercent   = "$freePct%"
                Status        = $status
                Threshold     = "$ThresholdGB GB"
                CheckedAt     = $timestamp
            }
        }

    } catch {
        Write-Host "    [ERROR] Could not reach $computer — $($_.Exception.Message)" -ForegroundColor Red

        # Still log the failure in the report
        $report += [PSCustomObject]@{
            ComputerName  = $computer
            Drive         = "N/A"
            TotalGB       = "N/A"
            UsedGB        = "N/A"
            FreeGB        = "N/A"
            FreePercent   = "N/A"
            Status        = "UNREACHABLE"
            Threshold     = "$ThresholdGB GB"
            CheckedAt     = $timestamp
        }
    }

    Write-Host ""
}

# --- Export Report ---
$reportDir = Split-Path $ReportPath
if (-not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}

$report | Export-Csv -Path $ReportPath -NoTypeInformation
Write-Host "[REPORT] Saved to: $ReportPath" -ForegroundColor Cyan

# --- Summary ---
Write-Host "`n--- SUMMARY ---" -ForegroundColor White
Write-Host "Machines checked:    $($ComputerName.Count)" -ForegroundColor White
Write-Host "Drives checked:      $(($report | Where-Object Drive -ne 'N/A').Count)" -ForegroundColor White
Write-Host "Drives OK:           $(($report | Where-Object Status -eq 'OK').Count)" -ForegroundColor Green
Write-Host "Drives WARNING:      $warnings" -ForegroundColor $(if ($warnings -gt 0) { "Red" } else { "Green" })
Write-Host "Unreachable:         $(($report | Where-Object Status -eq 'UNREACHABLE').Count)" -ForegroundColor Yellow
Write-Host "Report location:     $ReportPath`n" -ForegroundColor Cyan
