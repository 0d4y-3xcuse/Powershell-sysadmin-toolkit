<#
.SYNOPSIS
    Triggers Windows Update installation on one or more remote machines.

.DESCRIPTION
    Connects to one or more machines and initiates Windows Update installation
    remotely. Can target all available updates or only specific categories
    such as security updates. Logs all activity and optionally reboots
    machines automatically after updates are installed.
    Designed for Tier 1/2 patch deployment workflows outside of WSUS.

.PARAMETER ComputerName
    One or more computer names to update.
    Defaults to the local machine.

.PARAMETER CategoryFilter
    Filter updates by category. Options: All, Security, Critical.
    Default is Security — installs security updates only.

.PARAMETER AutoReboot
    Switch parameter. If included, reboots machines automatically
    after updates install if a reboot is required.
    If omitted, updates install but no reboot is triggered.

.PARAMETER LogPath
    Path to the audit log file.
    Default is C:\IT\Logs\WindowsUpdate.log

.EXAMPLE
    # Install security updates on local machine — no auto reboot
    .\Invoke-WindowsUpdate.ps1

.EXAMPLE
    # Install all updates on remote machines with auto reboot
    .\Invoke-WindowsUpdate.ps1 -ComputerName "WRK01","WRK02" -CategoryFilter All -AutoReboot

.EXAMPLE
    # Install critical updates only on a single machine
    .\Invoke-WindowsUpdate.ps1 -ComputerName "DC01" -CategoryFilter Critical

.NOTES
    Author: Ebrima Jallow
    Requires: WinRM enabled on target machines, Admin rights on targets
    Run As: Domain Admin or Local Admin
    WARNING: Always run Get-PatchStatus.ps1 first to review pending updates
             before triggering installation. Never run -AutoReboot on DCs
             without scheduling a maintenance window first.
#>

param (
    [Parameter(Mandatory = $false)]
    [string[]]$ComputerName = $env:COMPUTERNAME,

    [Parameter(Mandatory = $false)]
    [ValidateSet("All", "Security", "Critical")]
    [string]$CategoryFilter = "Security",

    [Parameter(Mandatory = $false)]
    [switch]$AutoReboot,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\IT\Logs\WindowsUpdate.log"
)

$timestamp   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$totalInstalled = 0

Write-Host "`n[INFO] Starting Windows Update deployment..." -ForegroundColor Cyan
Write-Host "[INFO] Category: $CategoryFilter | Auto-reboot: $($AutoReboot.IsPresent)" -ForegroundColor Cyan
Write-Host "[WARNING] Never run AutoReboot on domain controllers without a maintenance window.`n" -ForegroundColor Yellow

# --- Setup log ---
$logDir = Split-Path $LogPath
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

foreach ($computer in $ComputerName) {

    Write-Host "  [$computer] Starting update process..." -ForegroundColor White

    try {
        $updateResult = Invoke-Command -ComputerName $computer -ErrorAction Stop -ArgumentList $CategoryFilter -ScriptBlock {

            param($CategoryFilter)

            $updateSession  = New-Object -ComObject Microsoft.Update.Session
            $updateSearcher = $updateSession.CreateUpdateSearcher()
            $updateDownloader = $updateSession.CreateUpdateDownloader()
            $updateInstaller  = $updateSession.CreateUpdateInstaller()

            # Build search query based on category
            $searchQuery = switch ($CategoryFilter) {
                "Security" { "IsInstalled=0 and IsHidden=0 and CategoryIDs contains '0FA1201D-4330-4FA8-8AE9-B877473B6441'" }
                "Critical" { "IsInstalled=0 and IsHidden=0 and BrowseOnly=0 and AutoSelectOnWebSites=1" }
                default    { "IsInstalled=0 and IsHidden=0" }
            }

            Write-Output "[SEARCH] Searching for $CategoryFilter updates..."
            $searchResult = $updateSearcher.Search($searchQuery)

            if ($searchResult.Updates.Count -eq 0) {
                Write-Output "[INFO] No $CategoryFilter updates found. Machine is current."
                return [PSCustomObject]@{
                    UpdatesFound     = 0
                    UpdatesInstalled = 0
                    RebootRequired   = $false
                    UpdateTitles     = @()
                    Status           = "UP TO DATE"
                }
            }

            Write-Output "[INFO] Found $($searchResult.Updates.Count) update(s). Downloading..."

            # Download updates
            $updateDownloader.Updates = $searchResult.Updates
            $downloadResult = $updateDownloader.Download()

            # Install updates
            Write-Output "[INFO] Download complete. Installing..."
            $updateInstaller.Updates = $searchResult.Updates
            $installResult = $updateInstaller.Install()

            $titles = @($searchResult.Updates | ForEach-Object { $_.Title })

            return [PSCustomObject]@{
                UpdatesFound     = $searchResult.Updates.Count
                UpdatesInstalled = $installResult.ResultCode
                RebootRequired   = $installResult.RebootRequired
                UpdateTitles     = $titles
                Status           = if ($installResult.ResultCode -eq 2) { "SUCCESS" } else { "PARTIAL" }
            }
        }

        # Display results
        Write-Host "    Updates found:     $($updateResult.UpdatesFound)" -ForegroundColor White
        Write-Host "    Status:            $($updateResult.Status)" -ForegroundColor $(if ($updateResult.Status -eq "SUCCESS") { "Green" } else { "Yellow" })
        Write-Host "    Reboot required:   $($updateResult.RebootRequired)" -ForegroundColor $(if ($updateResult.RebootRequired) { "Red" } else { "Gray" })

        # List installed updates
        if ($updateResult.UpdateTitles.Count -gt 0) {
            Write-Host "    Installed updates:" -ForegroundColor Gray
            foreach ($title in $updateResult.UpdateTitles) {
                Write-Host "      - $title" -ForegroundColor Gray
            }
        }

        $totalInstalled += $updateResult.UpdatesFound

        # Auto reboot if needed and switch was passed
        if ($AutoReboot -and $updateResult.RebootRequired) {
            Write-Host "    [REBOOT] Scheduling reboot in 60 seconds..." -ForegroundColor Yellow
            Invoke-Command -ComputerName $computer -ScriptBlock {
                shutdown /r /t 60 /c "Scheduled reboot after Windows Update by IT"
            }
        }

        # Write audit log
        $logEntry = "$timestamp | UPDATE | Computer: $computer | Category: $CategoryFilter | Found: $($updateResult.UpdatesFound) | Status: $($updateResult.Status) | RebootRequired: $($updateResult.RebootRequired) | RunBy: $env:USERNAME"
        Add-Content -Path $LogPath -Value $logEntry

    } catch {
        Write-Host "    [ERROR] Could not connect to $computer — $($_.Exception.Message)" -ForegroundColor Red
        $logEntry = "$timestamp | ERROR | Computer: $computer | $($_.Exception.Message) | RunBy: $env:USERNAME"
        Add-Content -Path $LogPath -Value $logEntry
    }

    Write-Host ""
}

# Summary
Write-Host "--- SUMMARY ---" -ForegroundColor White
Write-Host "Machines targeted:     $($ComputerName.Count)" -ForegroundColor White
Write-Host "Total updates pushed:  $totalInstalled" -ForegroundColor $(if ($totalInstalled -gt 0) { "Green" } else { "White" })
Write-Host "Audit log:             $LogPath`n" -ForegroundColor Cyan
