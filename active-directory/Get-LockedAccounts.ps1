<#
.SYNOPSIS
    Finds all locked Active Directory accounts and optionally unlocks them.

.DESCRIPTION
    Searches the domain for all currently locked user accounts and displays
    them with last logon info and lockout status. Can unlock all accounts
    at once or prompt for confirmation on each one individually.
    Logs all unlock actions to an audit file.

.PARAMETER UnlockAll
    Switch parameter. If included, unlocks all locked accounts automatically
    without prompting. If omitted, prompts for confirmation on each account.

.PARAMETER LogPath
    Path to the audit log file.
    Default is C:\IT\Logs\AccountUnlocks.log

.EXAMPLE
    # Find locked accounts — report only, no changes
    .\Get-LockedAccounts.ps1

.EXAMPLE
    # Unlock all locked accounts automatically
    .\Get-LockedAccounts.ps1 -UnlockAll

.NOTES
    Author: Ebrima Jallow
    Requires: ActiveDirectory PowerShell module (RSAT)
    Run As: Domain Admin or account with unlock rights
#>

param (
    [Parameter(Mandatory = $false)]
    [switch]$UnlockAll,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\IT\Logs\AccountUnlocks.log"
)

# --- Setup ---
$timestamp  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$unlockCount = 0

Write-Host "`n[INFO] Searching for locked accounts in the domain..." -ForegroundColor Cyan

# --- Find All Locked Accounts ---
$lockedAccounts = Search-ADAccount -LockedOut -UsersOnly |
    Get-ADUser -Properties LockedOut, LastLogonDate, Department, Title

if (-not $lockedAccounts) {
    Write-Host "[INFO] No locked accounts found. All clear." -ForegroundColor Green
    exit 0
}

Write-Host "[INFO] Found $($lockedAccounts.Count) locked account(s):`n" -ForegroundColor Yellow

# --- Display Locked Accounts ---
foreach ($account in $lockedAccounts) {
    $lastLogon = if ($account.LastLogonDate) { $account.LastLogonDate } else { "Never" }

    Write-Host "  👤 $($account.SamAccountName)" -ForegroundColor White
    Write-Host "     Name:       $($account.Name)" -ForegroundColor Gray
    Write-Host "     Department: $($account.Department)" -ForegroundColor Gray
    Write-Host "     Last Logon: $lastLogon" -ForegroundColor Gray
    Write-Host ""
}

# --- Unlock Logic ---
foreach ($account in $lockedAccounts) {

    $shouldUnlock = $false

    if ($UnlockAll) {
        # Unlock everything automatically
        $shouldUnlock = $true

    } else {
        # Prompt for each account individually
        $response = Read-Host "Unlock $($account.SamAccountName)? (Y/N)"
        if ($response -eq 'Y' -or $response -eq 'y') {
            $shouldUnlock = $true
        }
    }

    if ($shouldUnlock) {
        try {
            Unlock-ADAccount -Identity $account.SamAccountName

            Write-Host "[UNLOCKED] $($account.SamAccountName)" -ForegroundColor Green
            $unlockCount++

            # Write audit log entry
            $logDir = Split-Path $LogPath
            if (-not (Test-Path $logDir)) {
                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            }

            $logEntry = "$timestamp | UNLOCK | User: $($account.SamAccountName) | Name: $($account.Name) | UnlockedBy: $env:USERNAME"
            Add-Content -Path $LogPath -Value $logEntry

        } catch {
            Write-Host "[ERROR] Could not unlock $($account.SamAccountName): $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "[SKIPPED] $($account.SamAccountName)" -ForegroundColor Yellow
    }
}

# --- Summary ---
Write-Host "`n--- SUMMARY ---" -ForegroundColor White
Write-Host "Locked accounts found:    $($lockedAccounts.Count)" -ForegroundColor Yellow
Write-Host "Accounts unlocked:        $unlockCount" -ForegroundColor Green
Write-Host "Accounts skipped:         $($lockedAccounts.Count - $unlockCount)" -ForegroundColor Gray

if ($unlockCount -gt 0) {
    Write-Host "Audit log:                $LogPath`n" -ForegroundColor Cyan
}
