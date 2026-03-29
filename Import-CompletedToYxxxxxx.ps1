# Импорт completed.txt в таблицу yxxxxxx (см. .env).
param(
    [string]$CompletedFile = "completed.txt"
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir
& node "$scriptDir\scripts\import_completed_to_yxxxxxx.mjs" --file (Join-Path $scriptDir $CompletedFile)
exit $LASTEXITCODE
