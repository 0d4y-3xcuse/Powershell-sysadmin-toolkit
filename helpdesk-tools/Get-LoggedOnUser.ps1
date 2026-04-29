<#
.SYNOPSIS
    Finds who is currently logged into one or more remote machines.

.DESCRIPTION
    Queries one or more computers to identify all currently logged-on users
    including their session type, logon time, and session state.
    Essential for helpdesk workflows before performing remote actions
    such as reboots, software pushes, or remote assistance sessions.

.PARAMETER ComputerName
    One or more computer names to query.
    Defaults to the local machine.

.PARAMETER ExportReport
    Switch parameter. If included, exports results to a CSV report.

.PARAMETER ReportPath
    Path for the CSV report if ExportReport is used.
    Default is C:\IT\Reports\LoggedOnUsers.csv

.EXAMPLE
    # Check who is logged into a single machine
    .\Get-LoggedOnUser.ps1 -ComputerName "WRK01"

.EXAMPLE
    # Check multiple machines at once
    .\Get-LoggedOnUser.ps1 -ComputerName "WRK01","WRK02","DC01"

.EXAMPLE
    # Check and export to CSV
    .\Get-LoggedOnUser.ps1 -ComputerName "WRK01","WRK02" -ExportReport

.NOTES
    Author: Ebrima Jallow
    Requires: Admin rights on target machines
    Run As: Domain Admin or Local Admin on target machines
#>

param (
    [Parameter(Mandatory = $false)]
    [string[]]$ComputerName = $env:COMPUTERNAME,

    [Parameter(Mandatory = $false)]
    [switch]$ExportReport,

    [Parameter(Mandatory = $false)]
    [string]$ReportPath = "C:\IT\Reports\LoggedOnUsers.csv"
)

# --- Setup ---
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$report    = @()

Write-Host "`n[INFO] Checking logged-on users on $($ComputerName.Count) machine(s)...`n" -ForegroundColor Cyan

# --- Check Each Machine ---
foreach ($computer in $ComputerName) {

    Write-Host "  [$computer]" -ForegroundColor White
    Write-Host "  $('-' * 40)" -ForegroundColor Gray

    try {
        # Method 1 — CIM for detailed session info
        $sessions = Get-CimInstance -ClassName Win32_LogonSession `
            -ComputerName $computer `
            -ErrorAction Stop |
            Where-Object { $_.LogonType -in @(2, 10, 11) }
            # LogonType 2  = Interactive (local login)
            # LogonType 10 = RemoteInteractive (RDP)
            # LogonType 11 = CachedInteractive (cached credentials)

        if (-not $sessions) {
            Write-Host "    [INFO] No interactive users currently logged on.`n" -ForegroundColor Gray
            continue
        }

        foreach ($session in $sessions) {

            # Get the user associated with this session
            $logonUser = Get-CimAssociatedInstance `
                -InputObject $session `
                -ResultClassName Win32_UserAccount `
                -ErrorAction SilentlyContinue

            $logonType = switch ($session.LogonType) {
                2  { "Local (Console)" }
                10 { "Remote (RDP)"    }
                11 { "Cached"          }
                default { "Unknown"    }
            }

            $logonTime = if ($session.StartTime) {
                $session.StartTime.ToString("yyyy-MM-dd HH:mm:ss")
            } else { "Unknown" }

            $username = if ($logonUser) { $logonUser.Name } else { "Unknown" }
            $domain   = if ($logonUser) { $logonUser.Domain } else { "Unknown" }

            Write-Host "    👤  User:       $domain\$username" -ForegroundColor Green
            Write-Host "        Logon Type: $logonType" -ForegroundColor Gray
            Write-Host "        Logon Time: $logonTime" -ForegroundColor Gray
            Write-Host ""

            $report += [PSCustomObject]@{
                ComputerName = $computer
                Domain       = $domain
                Username     = $username
                LogonType    = $logonType
                LogonTime    = $logonTime
                CheckedAt    = $timestamp
            }
        }

    } catch {
        # Fallback — use quser if CIM fails
        Write-Host "    [INFO] CIM query failed, trying quser..." -ForegroundColor Yellow

        try {
            $quser = quser /server:$computer 2>&1

            if ($quser -match "No User exists") {
                Write-Host "    [INFO] No users logged on.`n" -ForegroundColor Gray
            } else {
                $quser | Select-Object -Skip 1 | ForEach-Object {
                    $line = $_ -replace '\s+', ' '
                    Write-Host "    👤  $line" -ForegroundColor Green

                    $report += [PSCustomObject]@{
                        ComputerName = $computer
                        Domain       = "N/A"
                        Username     = $line.Trim()
                        LogonType    = "quser fallback"
                        LogonTime    = "N/A"
                        CheckedAt    = $timestamp
                    }
                }
                Write-Host ""
            }
        } catch {
            Write-Host "    [ERROR] Could not query $computer — $($_.Exception.Message)`n" -ForegroundColor Red
        }
    }
}

# --- Export if requested ---
if ($ExportReport) {
    $reportDir = Split-Path $ReportPath
    if (-not (Test-Path $reportDir)) {
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    }
    $report | Export-Csv -Path $ReportPath -NoTypeInformation
    Write-Host "[REPORT] Saved to: $ReportPath" -ForegroundColor Cyan
}

# --- Summary ---
Write-Host "--- SUMMARY ---" -ForegroundColor White
Write-Host "Machines checked:    $($ComputerName.Count)" -ForegroundColor White
Write-Host "Active sessions:     $($report.Count)" -ForegroundColor $(if ($report.Count -gt 0) {"Yellow"} else {"Green"})
Write-Host "RDP sessions:        $(($report | Where-Object LogonType -eq 'Remote (RDP)').Count)" -ForegroundColor White
Write-Host "Local sessions:      $(($report | Where-Object LogonType -eq 'Local (Console)').Count)" -ForegroundColor White
