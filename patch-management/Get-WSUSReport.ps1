<#
.SYNOPSIS
    Pulls a patch compliance report from a WSUS server.

.DESCRIPTION
    Connects directly to a WSUS server and generates a detailed compliance
    report showing which computers are up to date, which have pending updates,
    and which haven't checked in recently. Exports to both CSV and HTML for
    management reporting. Designed for Tier 2 patch management workflows
    where WSUS is the central update authority.

.PARAMETER WSUSServer
    Hostname or IP of the WSUS server.

.PARAMETER WSUSPort
    Port WSUS is running on. Default is 8530 (standard HTTP).
    Use 8531 for HTTPS.

.PARAMETER UseSSL
    Switch parameter. Use if WSUS is configured for HTTPS (port 8531).

.PARAMETER DaysInactive
    Flag computers that haven't checked into WSUS in this many days.
    Default is 30 days.

.PARAMETER ReportFolder
    Folder where CSV and HTML reports will be saved.
    Default is C:\IT\Reports\WSUS\

.EXAMPLE
    # Basic report from WSUS server
    .\Get-WSUSReport.ps1 -WSUSServer "WSUS01"

.EXAMPLE
    # Report with custom inactive threshold and SSL
    .\Get-WSUSReport.ps1 -WSUSServer "WSUS01" -UseSSL -WSUSPort 8531 -DaysInactive 14

.EXAMPLE
    # Save to custom folder
    .\Get-WSUSReport.ps1 -WSUSServer "WSUS01" -ReportFolder "C:\Audit\Patches"

.NOTES
    Author: Ebrima Jallow
    Requires: UpdateServices PowerShell module (installed with WSUS role)
              Must be run from the WSUS server or a machine with WSUS console installed
    Run As: WSUS Administrators group or Domain Admin
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$WSUSServer,

    [Parameter(Mandatory = $false)]
    [int]$WSUSPort = 8530,

    [Parameter(Mandatory = $false)]
    [switch]$UseSSL,

    [Parameter(Mandatory = $false)]
    [int]$DaysInactive = 30,

    [Parameter(Mandatory = $false)]
    [string]$ReportFolder = "C:\IT\Reports\WSUS"
)

$timestamp   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$dateStamp   = Get-Date -Format "yyyy-MM-dd"
$csvPath     = Join-Path $ReportFolder "WSUS-Compliance_$dateStamp.csv"
$htmlPath    = Join-Path $ReportFolder "WSUS-Compliance_$dateStamp.html"
$cutoffDate  = (Get-Date).AddDays(-$DaysInactive)

Write-Host "`n[INFO] Connecting to WSUS server: $WSUSServer`:$WSUSPort" -ForegroundColor Cyan
Write-Host "[INFO] SSL: $($UseSSL.IsPresent) | Inactive threshold: $DaysInactive days`n" -ForegroundColor Cyan

# --- Create report folder ---
if (-not (Test-Path $ReportFolder)) {
    New-Item -ItemType Directory -Path $ReportFolder -Force | Out-Null
}

# --- Load WSUS module ---
try {
    [reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
} catch {
    Write-Host "[ERROR] Could not load WSUS assembly. Is the WSUS console installed on this machine?" -ForegroundColor Red
    exit 1
}

# --- Connect to WSUS ---
try {
    $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer(
        $WSUSServer,
        $UseSSL.IsPresent,
        $WSUSPort
    )
    Write-Host "[SUCCESS] Connected to WSUS server: $($wsus.Name)" -ForegroundColor Green
    Write-Host "[INFO] WSUS version: $($wsus.Version)`n" -ForegroundColor Gray
} catch {
    Write-Host "[ERROR] Could not connect to WSUS — $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# --- Get all computers from WSUS ---
Write-Host "[INFO] Retrieving computer list from WSUS..." -ForegroundColor Cyan
$computerScope = New-Object Microsoft.UpdateServices.Administration.ComputerTargetScope
$computers     = $wsus.GetComputerTargets($computerScope)
Write-Host "[INFO] Found $($computers.Count) computers registered in WSUS.`n" -ForegroundColor White

# --- Get update scope for pending updates ---
$updateScope            = New-Object Microsoft.UpdateServices.Administration.UpdateScope
$updateScope.ApprovedStates = [Microsoft.UpdateServices.Administration.ApprovedStates]::LatestRevisionApproved

$report = @()

foreach ($computer in $computers) {

    # Get update summary for this computer
    $summary = $wsus.GetSummariesPerComputerTarget($updateScope, $computerScope) |
        Where-Object { $_.ComputerTargetId -eq $computer.Id }

    $lastCheckIn  = $computer.LastReportedStatusTime
    $lastSync     = $computer.LastSyncTime
    $isInactive   = ($lastCheckIn -lt $cutoffDate)
    $pendingCount = if ($summary) { $summary.NotInstalledCount + $summary.DownloadedCount } else { 0 }
    $failedCount  = if ($summary) { $summary.FailedCount } else { 0 }

    $complianceStatus = if ($isInactive) {
        "INACTIVE"
    } elseif ($failedCount -gt 0) {
        "FAILED UPDATES"
    } elseif ($pendingCount -eq 0) {
        "COMPLIANT"
    } else {
        "PENDING UPDATES"
    }

    $statusColor = switch ($complianceStatus) {
        "COMPLIANT"       { "Green"  }
        "PENDING UPDATES" { "Yellow" }
        "FAILED UPDATES"  { "Red"    }
        "INACTIVE"        { "Gray"   }
    }

    Write-Host "  $($computer.FullDomainName.PadRight(30)) | $complianceStatus | Pending: $pendingCount | Failed: $failedCount" -ForegroundColor $statusColor

    $report += [PSCustomObject]@{
        ComputerName      = $computer.FullDomainName
        IPAddress         = $computer.IPAddress
        OSVersion         = $computer.OSDescription
        LastCheckIn       = if ($lastCheckIn) { $lastCheckIn.ToString("yyyy-MM-dd HH:mm") } else { "Never" }
        LastSync          = if ($lastSync) { $lastSync.ToString("yyyy-MM-dd HH:mm") } else { "Never" }
        PendingUpdates    = $pendingCount
        FailedUpdates     = $failedCount
        ComplianceStatus  = $complianceStatus
        DaysInactive      = if ($lastCheckIn) { [math]::Round((Get-Date - $lastCheckIn).TotalDays, 0) } else { "N/A" }
        ReportDate        = $timestamp
    }
}

# --- Export CSV ---
$report | Export-Csv -Path $csvPath -NoTypeInformation
Write-Host "`n[CSV] Report saved to: $csvPath" -ForegroundColor Cyan

# --- Export HTML ---
$htmlHeader = @"
<style>
    body { font-family: Segoe UI, sans-serif; font-size: 13px; background: #f4f4f4; color: #333; }
    h1 { background: #0d1b2e; color: white; padding: 16px 24px; margin: 0; font-size: 18px; }
    h2 { padding: 12px 24px; margin: 0; font-size: 13px; background: #1e3a5a; color: #7ba7c9; }
    table { width: 100%; border-collapse: collapse; background: white; }
    th { background: #0d1b2e; color: white; padding: 10px 12px; text-align: left; font-size: 12px; }
    td { padding: 8px 12px; border-bottom: 1px solid #eee; font-size: 12px; }
    tr:hover td { background: #f0f4f8; }
    .COMPLIANT { color: #1a7a3c; font-weight: 500; }
    .PENDING { color: #b06a00; font-weight: 500; }
    .FAILED { color: #b00020; font-weight: 500; }
    .INACTIVE { color: #888; font-weight: 500; }
</style>
<h1>WSUS Patch Compliance Report</h1>
<h2>Generated: $timestamp &nbsp;|&nbsp; Server: $WSUSServer &nbsp;|&nbsp; Total machines: $($report.Count)</h2>
"@

$htmlRows = $report | ForEach-Object {
    $cssClass = switch ($_.ComplianceStatus) {
        "COMPLIANT"       { "COMPLIANT" }
        "PENDING UPDATES" { "PENDING"   }
        "FAILED UPDATES"  { "FAILED"    }
        "INACTIVE"        { "INACTIVE"  }
    }
    "<tr>
        <td>$($_.ComputerName)</td>
        <td>$($_.IPAddress)</td>
        <td>$($_.OSVersion)</td>
        <td>$($_.LastCheckIn)</td>
        <td>$($_.PendingUpdates)</td>
        <td>$($_.FailedUpdates)</td>
        <td class='$cssClass'>$($_.ComplianceStatus)</td>
        <td>$($_.DaysInactive)</td>
    </tr>"
}

$htmlTable = "<table><tr>
    <th>Computer</th><th>IP</th><th>OS</th><th>Last Check-In</th>
    <th>Pending</th><th>Failed</th><th>Status</th><th>Days Inactive</th>
</tr>$($htmlRows -join '')</table>"

"$htmlHeader$htmlTable" | Out-File -FilePath $htmlPath -Encoding UTF8
Write-Host "[HTML] Report saved to: $htmlPath" -ForegroundColor Cyan

# --- Summary ---
Write-Host "`n--- SUMMARY ---" -ForegroundColor White
Write-Host "Total machines:        $($report.Count)" -ForegroundColor White
Write-Host "Compliant:             $(($report | Where-Object ComplianceStatus -eq 'COMPLIANT').Count)" -ForegroundColor Green
Write-Host "Pending updates:       $(($report | Where-Object ComplianceStatus -eq 'PENDING UPDATES').Count)" -ForegroundColor Yellow
Write-Host "Failed updates:        $(($report | Where-Object ComplianceStatus -eq 'FAILED UPDATES').Count)" -ForegroundColor Red
Write-Host "Inactive ($DaysInactive+ days): $(($report | Where-Object ComplianceStatus -eq 'INACTIVE').Count)" -ForegroundColor Gray
Write-Host "Reports saved to:      $ReportFolder`n" -ForegroundColor Cyan
