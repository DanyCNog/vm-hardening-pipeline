<#
  Applies the tailored CIS Windows Server 2025 finding list with HardeningKitty (HailMary mode).
  Takes a backup of the current values first, so the change can be rolled back.
#>
param(
    [string]$FindingList = 'C:\Tools\cis_ws2025_tailored.csv'
)
$ErrorActionPreference = 'Stop'

New-Item -ItemType Directory -Force -Path C:\scan | Out-Null
Import-Module C:\Tools\HardeningKitty\HardeningKitty.psm1 -Force
$available = (Get-Command Invoke-HardeningKitty).Parameters

# The tailored list is not in the signed manifest, so it needs AllowCustomList (v0.9.4+)
$common = @{ FileFindingList = $FindingList }
if ($available.ContainsKey('AllowCustomList')) { $common.AllowCustomList = $true }

Write-Output '[harden] Backup of current values'
Invoke-HardeningKitty -Mode Config -Backup -BackupFile C:\scan\backup-before-hardening.csv @common | Out-Null

$hailmary = $common.Clone()
if ($available.ContainsKey('SkipRestorePoint')) { $hailmary.SkipRestorePoint = $true }

Write-Output "[harden] Applying $(Split-Path $FindingList -Leaf) (HailMary)"
Invoke-HardeningKitty -Mode HailMary -Log -LogFile C:\scan\hailmary.log @hailmary | Out-Null
Write-Output '[harden] Done. A reboot is required.'
