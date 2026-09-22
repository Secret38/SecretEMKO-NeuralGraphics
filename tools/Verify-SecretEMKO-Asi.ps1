param([Parameter(Mandatory=$true)][string]$AsiPath)
$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $AsiPath)) { throw "File not found: $AsiPath" }
$expected = @(1604,2060,2189,2372,2545,2612,2699,2802,2944,3095,3258,3407,3570,3717,3751,3788,3889)
Get-Item -LiteralPath $AsiPath | Format-List FullName,Length,LastWriteTime
Write-Host "Expected FX_ASI_BUILD resources:"
$expected | ForEach-Object { Write-Host "  $_" }
Write-Host "FiveM itself is the authoritative runtime loader check."
