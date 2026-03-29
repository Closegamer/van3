@echo off
cd /d "%~dp0"

REM Настройки БД и пароли — в .env рядом со скриптом (см. .env.example).
REM Run PowerShell script that manages combinations via started.txt and completed.txt
powershell -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0run_vanity.ps1"

pause



