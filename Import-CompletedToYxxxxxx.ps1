# Импорт completed.txt: yxxxxxx; с -VanRanges ещё van_ranges (completed) для run_van.ps1 + БД.
param(
    [string]$CompletedFile = "completed.txt",
    [switch]$VanRanges
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir
$nodeArgs = @(
    "$scriptDir\scripts\import_completed_to_yxxxxxx.mjs",
    "--file",
    (Join-Path $scriptDir $CompletedFile)
)
if ($VanRanges) {
    $nodeArgs += "--van-ranges"
}
& node @nodeArgs
exit $LASTEXITCODE
