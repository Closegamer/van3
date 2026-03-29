# Синхронизация Docker-стека на удалённый хост и запуск compose.
# Нужны: ssh, scp; на сервере — Docker + Compose v2.
#
# Пример:
#   .\scripts\deploy_remote.ps1 -Target user@YOUR_SERVER_IP -RemotePath /opt/van3
#   .\scripts\deploy_remote.ps1 -Target user@host -KeyFile C:\path\to\id_ed25519

param(
    [Parameter(Mandatory = $true)]
    [string]$Target,
    [string]$RemotePath = "/opt/van3",
    [string]$KeyFile = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

if (-not (Test-Path -LiteralPath ".env.docker")) {
    Write-Host "Создайте .env.docker из .env.docker.example и задайте POSTGRES_PASSWORD." -ForegroundColor Red
    exit 1
}

function Invoke-RemoteSsh {
    param([string[]]$Args)
    if ($KeyFile) {
        & ssh -i $KeyFile @Args
    } else {
        & ssh @Args
    }
}

function Invoke-RemoteScp {
    param([string]$LocalPath, [string]$RemoteSpec)
    if ($KeyFile) {
        & scp -i $KeyFile $LocalPath $RemoteSpec
    } else {
        & scp $LocalPath $RemoteSpec
    }
}

Write-Host "Каталог на сервере: $RemotePath" -ForegroundColor Cyan
Invoke-RemoteSsh @($Target, "mkdir -p $RemotePath/docker/initdb")

Invoke-RemoteScp (Join-Path $root "docker-compose.yml") "${Target}:$RemotePath/"
Invoke-RemoteScp (Join-Path $root ".env.docker") "${Target}:$RemotePath/"
Invoke-RemoteScp (Join-Path $root "docker/initdb/010_vanity_ranges.sql") "${Target}:$RemotePath/docker/initdb/"

$cmd = "cd $RemotePath && docker compose --env-file .env.docker pull 2>/dev/null; docker compose --env-file .env.docker up -d && docker compose --env-file .env.docker ps"
Write-Host "docker compose up -d ..." -ForegroundColor Cyan
Invoke-RemoteSsh @($Target, $cmd)

Write-Host "Готово. Проверка: ssh $Target `"docker compose -f $RemotePath/docker-compose.yml --env-file $RemotePath/.env.docker ps`"" -ForegroundColor Green
