<#
.SYNOPSIS
    Exports a full Active Directory user report to CSV and JSON.

.DESCRIPTION
    Pulls all AD user accounts with key attributes including last logon,
    account status, department, group memberships, and password info.
    Exports to both CSV (for Excel/reporting) and JSON (for SIEM tools
    or compliance platforms). Designed for audit, offboarding review,
    and access control verification workflows.

.PARAMETER OutputFolder
    Folder where CSV and JSON reports will be saved.
    Default is C:\IT\Reports\

.PARAMETER IncludeDisabled
    Switch parameter. If included, disabled accounts are included
    in the report. Default is active accounts only.

.EXAMPLE
    # Active users only
    .\Export-ADUserReport.ps1

.EXAMPLE
    # All users including disabled
    .\Export-ADUserReport.ps1 -IncludeDisabled

.EXAMPLE
    # Custom output folder
    .\Export-ADUserReport.ps1 -OutputFolder "C:\Audit\$(Get-Date -Format 'yyyy-MM')"

.NOTES
    Author: Ebrima Jallow
    Requires: ActiveDirectory PowerShell module (RSAT)
    Run As: Domain Admin or account with read access to AD user objects
#>

param (
    [Parameter(Mandatory = $false)]
    [string]$OutputFolder = "C:\IT\Reports",

    [Parameter(Mandatory = $false)]
    [switch]$IncludeDisabled
)

# --- Setup ---
$timestamp   = Get-Date -Format "yyyy-MM-dd"
$csvPath     = Join-Path $OutputFolder "ADUserReport_$timestamp.csv"
$jsonPath    = Join-Path $OutputFolder "ADUserReport_$timestamp.json"

Write-Host "`n[INFO] Starting AD User Report Export..." -ForegroundColor Cyan
Write-Host "[INFO] Include disabled accounts: $($IncludeDisabled.IsPresent)" -ForegroundColor Cyan

# --- Create Output Folder if Missing ---
if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    Write-Host "[INFO] Created output folder: $OutputFolder" -ForegroundColor Yellow
}

# --- Pull All AD Users ---
$filter = if ($IncludeDisabled) { '*' } else { 'Enabled -eq $true' }

$users = Get-ADUser -Filter $filter -Properties `
    DisplayName,
    Department,
    Title,
    Manager,
    EmailAddress,
    LastLogonDate,
    PasswordLastSet,
    PasswordNeverExpires,
    PasswordExpired,
    LockedOut,
    Enabled,
    Created,
    MemberOf

Write-Host "[INFO] Retrieved $($users.Count) user account(s) from AD.`n" -ForegroundColor White

# --- Build Report ---
$report = foreach ($user in $users) {

    # Get group names cleanly (strip the full DN down to just the name)
    $groups = ($user.MemberOf | ForEach-Object {
        ($_ -split ',')[0] -replace 'CN=', ''
    }) -join ' | '

    # Get manager name cleanly
    $managerName = if ($user.Manager) {
        (Get-ADUser -Identity $user.Manager).Name
    } else { "N/A" }

    [PSCustomObject]@{
        Username             = $user.SamAccountName
        FullName             = $user.DisplayName
        Department           = $user.Department
        JobTitle             = $user.Title
        Email                = $user.EmailAddress
        Manager              = $managerName
        Enabled              = $user.Enabled
        LockedOut            = $user.LockedOut
        LastLogonDate        = if ($user.LastLogonDate) { $user.LastLogonDate } else { "Never" }
        PasswordLastSet      = $user.PasswordLastSet
        PasswordNeverExpires = $user.PasswordNeverExpires
        PasswordExpired      = $user.PasswordExpired
        AccountCreated       = $user.Created
        GroupMemberships     = $groups
    }
}

# --- Export CSV ---
$report | Export-Csv -Path $csvPath -NoTypeInformation
Write-Host "[CSV] Report saved to: $csvPath" -ForegroundColor Green

# --- Export JSON ---
$report | ConvertTo-Json -Depth 3 | Out-File -FilePath $jsonPath -Encoding UTF8
Write-Host "[JSON] Report saved to: $jsonPath" -ForegroundColor Green

# --- Summary ---
Write-Host "`n--- SUMMARY ---" -ForegroundColor White
Write-Host "Total users exported:    $($report.Count)" -ForegroundColor White
Write-Host "Enabled accounts:        $(($report | Where-Object Enabled -eq $true).Count)" -ForegroundColor Green
Write-Host "Disabled accounts:       $(($report | Where-Object Enabled -eq $false).Count)" -ForegroundColor Yellow
Write-Host "Locked out accounts:     $(($report | Where-Object LockedOut -eq $true).Count)" -ForegroundColor Red
Write-Host "Never logged in:         $(($report | Where-Object LastLogonDate -eq 'Never').Count)" -ForegroundColor Yellow
Write-Host "Password never expires:  $(($report | Where-Object PasswordNeverExpires -eq $true).Count)" -ForegroundColor Red
Write-Host "`nReports saved to: $OutputFolder`n" -ForegroundColor Cyan
