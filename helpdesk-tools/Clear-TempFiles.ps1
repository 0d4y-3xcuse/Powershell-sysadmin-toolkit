<#
.SYNOPSIS
    Clears temporary files on a local or remote machine to free disk space.

.DESCRIPTION
    Removes temp files from Windows Temp, User Temp, browser caches,
    and the Recycle Bin. Calculates and reports how much space was freed.
    Logs all cleanup actions with a before/after disk space comparison.
    Designed for Tier 1 performance troubleshooting and routine maintenance.

.PARAMETER ComputerName
    Target machine to clean. Defaults to local machine.

.PARAMETER LogPath
    Path to the audit log file.
    Default is C:\IT\Logs\TempFileCleanup.log

.PARAMETER WhatIf
    Switch parameter. If included, shows what WOULD be deleted without
    actually deleting anything. Always run this first on unfamiliar machines.

.EXAMPLE
    # Preview what would be deleted — no changes made
    .\Clear-TempFiles.ps1 -WhatIf

.EXAMPLE
    # Clean local machine
    .\Clear-TempFiles.ps1

.EXAMPLE
    # Clean a remote machine
    .\Clear-TempFiles.ps1 -ComputerName "WRK01"

.NOTES
    Author: Ebrima Jallow
    Requires: Admin rights on target machine
    Run As: Local Admin or Domain Admin
    WARNING: Always run with -WhatIf first on unfamiliar machines
#>

param (
    [Parameter(Mandatory = $false)]
    [string]$ComputerName = $env:COMPUTERNAME,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\IT\Logs\TempFileCleanup.log",

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

# --- Setup ---
$timestamp   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$totalFreed  = 0
$isLocal     = ($ComputerName -eq $env:COMPUTERNAME)

Write-Host "`n[INFO] Temp file cleanup — Target: $ComputerName" -ForegroundColor Cyan
Write-Host "[INFO] WhatIf mode: $($WhatIf.IsPresent) (no changes will be made)`n" -ForegroundColor $(if ($WhatIf) {"Yellow"} else {"Cyan"})

# --- Define Cleanup Targets ---
# For local machine use direct paths
# For remote machines use UNC paths (requires admin share access)
$cleanupPaths = if ($isLocal) {
    @(
        "$env:SystemRoot\Temp",                          # Windows system temp
        "$env:TEMP",                                     # Current user temp
        "$env:LOCALAPPDATA\Temp",                        # Local app data temp
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCache", # IE/Edge cache
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache", # Chrome cache
        "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"     # Firefox cache
    )
} else {
    @(
        "\\$ComputerName\C$\Windows\Temp",
        "\\$ComputerName\C$\Users\*\AppData\Local\Temp"
    )
}

# --- Get Disk Space Before ---
$driveBefore = Get-PSDrive -Name C -ErrorAction SilentlyContinue
$freeGBBefore = if ($driveBefore) { [math]::Round($driveBefore.Free / 1GB, 2) } else { "N/A" }

Write-Host "[INFO] Disk space before cleanup: $freeGBBefore GB free`n" -ForegroundColor White

# --- Clean Each Path ---
foreach ($path in $cleanupPaths) {

    # Expand wildcards for paths like C:\Users\*\AppData\Local\Temp
    $expandedPaths = Get-Item -Path $path -ErrorAction SilentlyContinue

    foreach ($expandedPath in $expandedPaths) {

        if (-not (Test-Path $expandedPath)) {
            Write-Host "  [SKIP] Path not found: $expandedPath" -ForegroundColor Gray
            continue
        }

        # Calculate size before deletion
        $files = Get-ChildItem -Path $expandedPath -Recurse -Force -ErrorAction SilentlyContinue
        $pathSizeBytes = ($files | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        $pathSizeMB = [math]::Round($pathSizeBytes / 1MB, 2)

        Write-Host "  [CLEANING] $expandedPath" -ForegroundColor White
        Write-Host "             Size: $pathSizeMB MB | Files: $($files.Count)" -ForegroundColor Gray

        if ($WhatIf) {
            Write-Host "             [WHATIF] Would delete $($files.Count) files ($pathSizeMB MB)" -ForegroundColor Yellow
            $totalFreed += $pathSizeBytes

        } else {
            # Delete files — skip locked files silently
            $deleted = 0
            $skipped = 0

            foreach ($file in $files) {
                try {
                    if (-not $file.PSIsContainer) {
                        Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                        $deleted++
                        $totalFreed += $file.Length
                    }
                } catch {
                    $skipped++  # File is locked/in use — skip silently
                }
            }

            # Remove empty folders
            Get-ChildItem -Path $expandedPath -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.PSIsContainer } |
                Sort-Object FullName -Descending |
                ForEach-Object {
                    Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                }

            Write-Host "             Deleted: $deleted files | Skipped (in use): $skipped" -ForegroundColor Green
        }

        Write-Host ""
    }
}

# --- Empty Recycle Bin (local only) ---
if ($isLocal -and -not $WhatIf) {
    try {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Write-Host "  [CLEANED] Recycle Bin emptied`n" -ForegroundColor Green
    } catch {
        Write-Host "  [SKIP] Could not empty Recycle Bin`n" -ForegroundColor Gray
    }
}

# --- Get Disk Space After ---
$driveAfter   = Get-PSDrive -Name C -ErrorAction SilentlyContinue
$freeGBAfter  = if ($driveAfter) { [math]::Round($driveAfter.Free / 1GB, 2) } else { "N/A" }
$totalFreedMB = [math]::Round($totalFreed / 1MB, 2)
$totalFreedGB = [math]::Round($totalFreed / 1GB, 2)

# --- Write Audit Log ---
if (-not $WhatIf) {
    $logDir = Split-Path $LogPath
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $logEntry = "$timestamp | CLEANUP | Computer: $ComputerName | FreedMB: $totalFreedMB | Before: $freeGBBefore GB | After: $freeGBAfter GB | RunBy: $env:USERNAME"
    Add-Content -Path $LogPath -Value $logEntry
}

# --- Summary ---
Write-Host "--- SUMMARY ---" -ForegroundColor White
Write-Host "Target machine:      $ComputerName" -ForegroundColor White
Write-Host "Disk space bef
