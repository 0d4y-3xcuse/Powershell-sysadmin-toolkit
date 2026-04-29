<#
.SYNOPSIS
    Monitors critical Windows services and restarts any that are stopped.

.DESCRIPTION
    Checks a defined list of critical services on one or more machines.
    Reports the status of each service, attempts to restart any that are
    stopped, and logs all restart actions to an audit file.
    Designed for first-response troubleshooting and proactive monitoring.

.PARAMETER ComputerName
    One or more computer names to check.
    Defaults to the local machine.

.PARAMETER Services
    Array of service names to monitor.
    Defaults to a standard list of critical Windows services.

.PARAMETER AutoRestart
    Switch parameter. If included, automatically restarts stopped services.
    If omitted, reports status only — no changes made.

.PARAMETER LogPath
    Path to the audit log file.
    Default is C:\IT\Logs\ServiceStatus.log

.EXAMPLE
    # Check default critical services on local machine — report only
    .\Get-ServiceStatus.ps1

.EXAMPLE
    # Check and auto-restart stopped services on remote machine
    .\Get-ServiceStatus.ps1 -ComputerName "DC01" -AutoRestart

.EXAMPLE
    # Check specific services across multiple machines
    .\Get-ServiceStatus.ps1 -ComputerName "DC01","DC02" -Services "DNS","DHCP","Netlogon" -AutoRestart

.NOTES
    Author: Ebrima Jallow
    Requires: Admin rights on target machines for remote checks and restarts
    Run As: Domain Admin or Local Admin on target machines
#>

param (
    [Parameter(Mandatory = $false)]
    [string[]]$ComputerName = $env:COMPUTERNAME,

    [Parameter(Mandatory = $false)]
    [string[]]$Services = @(
        "DNS",          # DNS Server — critical for AD
        "DHCP",         # DHCP Server — IP assignment
        "Netlogon",     # Domain authentication
        "ADWS",         # AD Web Services — PowerShell AD module depends on this
        "W32tm",        # Windows Time — Kerberos requires clock sync
        "Spooler",      # Print Spooler — common helpdesk issue
        "WinRM",        # Windows Remote Management — remote admin
        "EventLog"      # Event Log — needed for auditing
    ),

    [Parameter(Mandatory = $false)]
    [switch]$AutoRestart,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\IT\Logs\ServiceStatus.log"
)

# --- Setup ---
$timestamp    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$report       = @()
$stoppedCount = 0
$restartCount = 0

Write-Host "`n[INFO] Checking $($Services.Count) services on $($ComputerName.Count) machine(s)..." -ForegroundColor Cyan
Write-Host "[INFO] Auto-restart: $($AutoRestart.IsPresent)`n" -ForegroundColor Cyan

# --- Check Each Machine ---
foreach ($computer in $ComputerName) {

    Write-Host "  [$computer]" -ForegroundColor White
    Write-Host "  $('-' * 40)" -ForegroundColor Gray

    try {
        foreach ($serviceName in $Services) {

            try {
                $service = Get-Service -Name $serviceName `
                    -ComputerName $computer `
                    -ErrorAction Stop

                $status = $service.Status

                if ($status -eq "Running") {
                    Write-Host "    ✅  $serviceName — Running" -ForegroundColor Green

                } else {
                    Write-Host "    ❌  $serviceName — $status" -ForegroundColor Red
                    $stoppedCount++

                    # Auto-restart if switch was passed
                    if ($AutoRestart) {
                        try {
                            Write-Host "    🔄  Attempting to restart $serviceName..." -ForegroundColor Yellow
                            $service.Start()
                            $service.WaitForStatus("Running", "00:00:30")  # Wait up to 30 seconds

                            Write-Host "    ✅  $serviceName restarted successfully" -ForegroundColor Green
                            $restartCount++
                            $status = "Restarted"

                            # Log the restart
                            $logDir = Split-Path $LogPath
                            if (-not (Test-Path $logDir)) {
                                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
                            }
                            $logEntry = "$timestamp | RESTART | Computer: $computer | Service: $serviceName | RestartedBy: $env:USERNAME"
                            Add-Content -Path $LogPath -Value $logEntry

                        } catch {
                            Write-Host "    [ERROR] Could not restart $serviceName — $($_.Exception.Message)" -ForegroundColor Red
                            $status = "Restart Failed"
                        }
                    }
                }

                # Add to report
                $report += [PSCustomObject]@{
                    ComputerName = $computer
                    ServiceName  = $serviceName
                    DisplayName  = $service.DisplayName
                    Status       = $status
                    AutoRestart  = $AutoRestart.IsPresent
                    CheckedAt    = $timestamp
                }

            } catch {
                # Service not found on this machine
                Write-Host "    [N/A] $serviceName — Not found on $computer" -ForegroundColor Gray

                $report += [PSCustomObject]@{
                    ComputerName = $computer
                    ServiceName  = $serviceName
                    DisplayName  = "N/A"
                    Status       = "Not Found"
                    AutoRestart  = $AutoRestart.IsPresent
                    CheckedAt    = $timestamp
                }
            }
        }

    } catch {
        Write-Host "    [ERROR] Could not connect to $computer — $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
}

# --- Summary ---
Write-Host "--- SUMMARY ---" -ForegroundColor White
Write-Host "Machines checked:     $($ComputerName.Count)" -ForegroundColor White
Write-Host "Services checked:     $($Services.Count * $ComputerName.Count)" -ForegroundColor White
Write-Host "Running:              $(($report | Where-Object Status -eq 'Running').Count)" -ForegroundColor Green
Write-Host "Stopped:              $stoppedCount" -ForegroundColor $(if ($stoppedCount -gt 0) {"Red"} else {"Green"})
Write-Host "Restarted:            $restartCount" -ForegroundColor $(if ($restartCount -gt 0) {"Yellow"} else {"Green"})
Write-Host "Not Found:            $(($report | Where-Object Status -eq 'Not Found').Count)" -ForegroundColor Gray

if ($restartCount -gt 0) {
    Write-Host "Audit log:            $LogPath`n" -ForegroundColor Cyan
}
