<#
  HardeningKitty audit against the CIS Windows Server 2025 finding list.
  Usage (as administrator): scan.ps1 -Phase baseline|final
#>
param(
    [Parameter(Mandatory)][ValidateSet('baseline', 'final')][string]$Phase,
    [string]$FindingList = 'C:\Tools\HardeningKitty\lists\finding_list_cis_microsoft_windows_server_2025_24h2_1.0.0_machine.csv'
)
$ErrorActionPreference = 'Stop'

$out = "C:\scan\$Phase"
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Force -Path $out | Out-Null

Import-Module C:\Tools\HardeningKitty\HardeningKitty.psm1 -Force
Write-Output "[scan:$Phase] HardeningKitty $((Get-Module HardeningKitty).Version)"
Write-Output "[scan:$Phase] list: $(Split-Path $FindingList -Leaf)"

Invoke-HardeningKitty -Mode Audit -FileFindingList $FindingList `
    -Report -ReportFile "$out\hk-report.csv" `
    -Log -LogFile "$out\hk.log" -SkipMachineInformation | Out-Null

# Summary: find the result column (values Passed/Low/Medium/High)
$rows   = @(Import-Csv "$out\hk-report.csv")
$levels = 'Passed', 'Low', 'Medium', 'High'
$col = $rows[0].PSObject.Properties.Name | Where-Object {
    $c = $_
    (@($rows | Where-Object { $_.$c -eq 'Passed' }).Count -gt 0) -and
    -not ($rows | Where-Object { $_.$c -notin $levels })
} | Select-Object -First 1
$passed = @($rows | Where-Object { $_.$col -eq 'Passed' }).Count
Write-Output "[scan:$Phase] checks: $($rows.Count)  passed: $passed  failed: $($rows.Count - $passed)"

Compress-Archive -Path $out -DestinationPath "C:\scan\$Phase.zip" -Force
Write-Output "[scan:$Phase] done: C:\scan\$Phase.zip"
