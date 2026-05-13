param(
    [string]$ConfigPath = ".\config.local.json"
)

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    Write-Host "Config file not found: $ConfigPath"
    Write-Host "Copy config.example.json to config.local.json, then edit vaultPath and repoRoots for this machine."
    return
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$writeDynoSheetScript = Join-Path -Path $scriptDir -ChildPath "Write-LjOsDynoSheet.ps1"

$outputPath = & $writeDynoSheetScript -ConfigPath $ConfigPath
Write-Host "Wrote LJ OS dyno sheet: $outputPath"
