<#
.SYNOPSIS
    Resets an Active Directory user password and forces change at next logon.

.DESCRIPTION
    Resets a specified user's password, unlocks the account if locked,
    and forces a password change at next logon. Logs all reset activity
    to a running audit log for compliance and tracking purposes.

.PARAMETER Username
    The SamAccountName of the user whose password will be reset.

.PARAMETER NewPassword
    The temporary password to assign. User must change it at next logon.
    Default is "TempPass@2025!"

.PARAMETER LogPath
    Path to the audit log file. Default is C:\IT\Logs\PasswordResets.log

.EXAMPLE
    .\Reset-UserPassword.ps1 -Username jsmith

.EXAMPLE
    .\Reset-UserPassword.ps1 -Username jsmith -NewPassword "Welcome@99!"

.NOTES
    Author: Ebrima Jallow
    Requires: ActiveDirectory PowerShell module (RSAT)
    Run As: Domain Admin or account with password reset rights
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$Username,

    [Parameter(Mandatory = $false)]
    [string]$NewPassword = "TempPass@2025!",

    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\IT\Logs\PasswordResets.log"
)

# --- Setup ---
$timestamp  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$securePass = ConvertTo-SecureString $NewPassword -AsPlainText -Force

# --- Verify User Exists ---
Write-Host "`n[INFO] Looking up user: $Username" -ForegroundColor Cyan

$user = Get-ADUser -Identity $Username -Properties LockedOut, PasswordExpired, LastLogonDate `
    -ErrorAction SilentlyContinue

if (-not $user) {
    Write-Host "[ERROR] User '$Username' not found in Active Directory." -ForegroundColor Red
    exit 1
}

Write-Host "[FOUND] $($user.Name) | Locked: $($user.LockedOut) | Enabled: $($user.Enabled)" -ForegroundColor White

# --- Reset Password ---
try {
    Set-ADAccountPassword -Identity $Username `
        -NewPassword $securePass `
        -Reset

    Write-Host "[SUCCESS] Password reset for $Username" -ForegroundColor Green

} catch {
    Write-Host "[ERROR] Password reset failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# --- Unlock Account if Locked ---
if ($user.LockedOut) {
    try {
        Unlock-ADAccount -Identity $Username
        Write-Host "[UNLOCKED] Account was locked — now unlocked." -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Could not unlock account: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# --- Force Password Change at Next Logon ---
try {
    Set-ADUser -Identity $Username -ChangePasswordAtLogon $true
    Write-Host "[SET] User must change password at next logon." -ForegroundColor Yellow
} catch {
    Write-Host "[ERROR] Could not set ChangePasswordAtLogon: $($_.Exception.Message)" -ForegroundColor Red
}

# --- Write to Audit Log ---
$logDir = Split-Path $LogPath
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$logEntry = "$timestamp | RESET | User: $Username | Name: $($user.Name) | WasLocked: $($user.LockedOut) | ResetBy: $env:USERNAME"
Add-Content -Path $LogPath -Value $logEntry

Write-Host "[LOG] Audit entry written to: $LogPath" -ForegroundColor Cyan

# --- Final Summary ---
Write-Host "`n--- SUMMARY ---" -ForegroundColor White
Write-Host "User:              $($user.Name) ($Username)" -ForegroundColor White
Write-Host "Password Reset:    Yes" -ForegroundColor Green
Write-Host "Account Unlocked:  $(if ($user.LockedOut) { 'Yes' } else { 'Not needed' })" -ForegroundColor Green
Write-Host "Force Pwd Change:  Yes (next logon)" -ForegroundColor Yellow
Write-Host "Audit Log:         $LogPath`n" -ForegroundColor Cyan
