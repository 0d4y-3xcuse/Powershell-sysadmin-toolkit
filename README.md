# PowerShell Sysadmin Toolkit

A collection of PowerShell scripts for Active Directory administration, user lifecycle management, and IT operations — built for Tier 1/2 Sysadmin workflows.

## Structure

| Folder | Description |
|---|---|
| `active-directory/` | AD user lifecycle, auditing, and account management |
| `system-admin/` | Disk space, service monitoring, and system health |
| `helpdesk-tools/` | Day-to-day Tier 1 helpdesk automation |

## Scripts

### Active Directory
| Script | Description |
|---|---|
| `New-BulkADUsers.ps1` | Creates AD users in bulk from a CSV file |
| `Get-StaleAccounts.ps1` | Finds and disables inactive accounts (90+ days) |
| `Reset-UserPassword.ps1` | Resets password, unlocks account, writes audit log |
| `Export-ADUserReport.ps1` | Exports full AD user report to CSV and JSON |
| `Get-LockedAccounts.ps1` | Finds all locked accounts and unlocks them |

### System Administration
| Script | Description |
|---|---|
| `Get-DiskSpaceReport.ps1` | Checks disk space across machines, flags low storage |
| `Get-ServiceStatus.ps1` | Monitors critical services, restarts if down |

### Helpdesk Tools
| Script | Description |
|---|---|
| `Get-LoggedOnUser.ps1` | Finds who is logged into a remote machine |
| `Clear-TempFiles.ps1` | Cleans temp files to free disk space and fix performance |

## Requirements
- PowerShell 5.1 or later
- RSAT (Remote Server Administration Tools) for AD scripts
- Run as Domain Admin or account with appropriate rights

## Author
**Ebrima Jallow** — IT Support & Sysadmin | Worcester, MA
- [LinkedIn](https://linkedin.com/in/ebrima-jallow1)
- [Active Directory Home Lab](https://github.com/pischek/active-directory-home-lab)
