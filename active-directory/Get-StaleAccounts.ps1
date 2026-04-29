<#
.SYNOPSIS
    Detects and disables stale Active Directory user accounts.

.DESCRIPTION
    Searches Active Directory for user accounts that have not logged in
    within a specified number of days. Exports a report of stale accounts
    to CSV, then disables them with a descriptive note in the account.
    Designed for periodic security hygiene and compliance workflows.

.PARAMETER InactiveDays
    Number of days since last logon to consider an account stale.
    Default is 90 days.

.PARAMETER ReportPath
    Full path where the CSV report will be saved.
    Default is C:\IT\Reports\StaleAccounts.csv

.PARAMETER DisableAccounts
    Switch parameter. If included, stale accounts will be disabled
    after the report is generated. If omitted, runs in report-only mode.

.EXAMPLE
    # Report only — no changes made
    .\Get-StaleAccounts.ps1

.EXAMPLE
    # Report AND disable stale accounts
    .\Get-StaleAccounts.ps1 -DisableAccounts

.EXAMPLE
    # Custom threshold and report path
    .\Get-StaleAccounts.ps1 -InactiveDays 60 -ReportPath "C:\Audit\stale.csv" -DisableAccounts

.NOTES
    Author: Ebrima Jallow
    Requires: ActiveDirectory PowerShell module (RSAT)
    Run As: Domain Admin or account with write access to user objects
#>

param (
    [Parameter(Mandatory = $false)]
    [int]$InactiveDays = 90,

    [Parameter(Mandatory = $false)]
    [string]$ReportPath = "C:\IT\Reports\StaleAccounts.csv",

    [Parameter(Mandatory = $false)]
    [switch]$DisableAccounts
)

# --- Setup ---
$cutoffDate = (Get-Date).AddDays(-$InactiveDays)
$timestamp  = Get-Date -Format "yyyy-MM-dd HH:mm"
$results    = @()

Write-Host "`n[INFO] Searching for accounts inactive since: $($cutoffDate.ToShortDateString())" -ForegroundColor Cyan

# --- Find Stale Accounts ---
$staleUsers = Search-ADAccount -AccountInactive -TimeSpan (New-TimeSpan -Days $InactiveDays) `
    -UsersOnly | Get-ADUser -Properties LastLogonDate, Department, Title, Manager, Description

if (-not $staleUsers) {
    Write-Host "[INFO] No stale accounts found. Exiting." -ForegroundColor Green
    exit 0
}

Write-Host "[INFO] Found $($staleUsers.Count) stale account(s).`n" -ForegroundColor Yellow

# --- Process Each Account ---
foreach ($user in $staleUsers) {

    $lastLogon = if ($user.LastLogonDate) { $user.LastLogonDate } else { "Never" }

    Write-Host "  [STALE] $($user.SamAccountName) | Last Logon: $lastLogon" -ForegroundColor Yellow

    # Build report entry
    $results += [PSCustomObject]@{
        Username      = $user.SamAccountName
        FullName      = $user.Name
        Department    = $user.Department
        JobTitle      = $user.Title
        LastLogonDate = $lastLogon
        Enabled       = $user.Enabled
        Action        = if ($DisableAccounts) { "Disabled" } else { "Reported Only" }
        RunDate       = $timestamp
    }

    # Disable if switch was passed
    if ($DisableAccounts) {
        try {
            Set-ADUser -Identity $user.SamAccountName `
                -Description "DISABLED by IT - Inactive $InactiveDays+ days as of $timestamp"

            Disable-ADAccount -Identity $user.SamAccountName

            Write-Host "  [DISABLED] $($user.SamAccountName)" -ForegroundColor Red

        } catch {
            Write-Host "  [ERROR] Could not disable $($user.SamAccountName): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# --- Export Report ---
$reportDir = Split-Path $ReportPath
if (-not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}

$results | Export-Csv -Path $ReportPath -NoTypeInformation
Write-Host "`n[REPORT] Saved to: $ReportPath" -ForegroundColor Cyan

# --- Summary ---
Write-Host "`n--- SUMMARY ---" -ForegroundColor White
Write-Host "Stale accounts found:    $($results.Count)" -ForegroundColor Yellow
Write-Host "Accounts disabled:       $(($results | Where-Object Action -eq 'Disabled').Count)" -ForegroundColor Red
Write-Host "Report-only (no change): $(($results | Where-Object Action -eq 'Reported Only').Count)" -ForegroundColor Green
Write-Host "Report location:         $ReportPath`n" -ForegroundColor Cyan
