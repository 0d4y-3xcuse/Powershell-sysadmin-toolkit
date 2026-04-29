<#
.SYNOPSIS
    Bulk provisions Active Directory users from a CSV file.

.DESCRIPTION
    Reads a CSV file containing user information and creates AD user accounts
    with proper OU placement, group membership, and account settings.
    Designed for Tier 1/2 Sysadmin workflows in enterprise environments.

.PARAMETER CSVPath
    Full path to the CSV file containing user data.

.PARAMETER DefaultPassword
    The initial password assigned to all new accounts. Users are forced to
    change it on first login.

.EXAMPLE
    .\New-BulkADUsers.ps1 -CSVPath "C:\IT\new-users.csv" -DefaultPassword "Welcome@2025!"

.NOTES
    Author: Ebrima Jallow
    Requires: ActiveDirectory PowerShell module (RSAT)
    Run As: Domain Admin or account with User creation rights
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$CSVPath,

    [Parameter(Mandatory = $false)]
    [string]$DefaultPassword = "Welcome@2025!"
)

# --- Import & Validate CSV ---
if (-not (Test-Path $CSVPath)) {
    Write-Host "[ERROR] CSV file not found at: $CSVPath" -ForegroundColor Red
    exit 1
}

$users = Import-Csv -Path $CSVPath
Write-Host "[INFO] Found $($users.Count) users to provision." -ForegroundColor Cyan

# --- Loop Through Each User ---
foreach ($user in $users) {

    $fullName    = "$($user.FirstName) $($user.LastName)"
    $username    = ($user.FirstName[0] + $user.LastName).ToLower()  # e.g. jsmith
    $ouPath      = "OU=$($user.OU),OU=_Users,DC=corp,DC=jallow,DC=local"
    $securePass  = ConvertTo-SecureString $DefaultPassword -AsPlainText -Force

    # Check if user already exists
    if (Get-ADUser -Filter {SamAccountName -eq $username} -ErrorAction SilentlyContinue) {
        Write-Host "[SKIP] $username already exists. Skipping." -ForegroundColor Yellow
        continue
    }

    try {
        New-ADUser `
            -SamAccountName       $username `
            -UserPrincipalName    "$username@corp.jallow.local" `
            -Name                 $fullName `
            -GivenName            $user.FirstName `
            -Surname              $user.LastName `
            -DisplayName          $fullName `
            -Title                $user.JobTitle `
            -Department           $user.Department `
            -Path                 $ouPath `
            -AccountPassword      $securePass `
            -ChangePasswordAtLogon $true `
            -Enabled              $true

        Write-Host "[SUCCESS] Created user: $username ($fullName)" -ForegroundColor Green

    } catch {
        Write-Host "[ERROR] Failed to create $username - $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n[DONE] User provisioning complete." -ForegroundColor Cyan
