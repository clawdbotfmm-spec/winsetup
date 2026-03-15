@echo off
title Setup Windows - clawdbotfmm-spec
setlocal enabledelayedexpansion

:: 1. Auto-elevar a administrador
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Solicitando permisos de administrador...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:MENU
cls
echo =====================================
echo    Setup Windows - clawdbotfmm-spec
echo =====================================
echo.
echo  1 - Menu principal Windows
echo  2 - Instalar OpenClaw
echo  3 - Salir
echo.
set /p choice="Selecciona una opcion (1, 2 o 3): "

if "%choice%"=="1" goto MENU_PRINCIPAL
if "%choice%"=="2" goto OPENCLAW
if "%choice%"=="3" goto SALIR
echo Opcion invalida. Intenta de nuevo.
timeout /t 2 >nul
goto MENU

:MENU_PRINCIPAL
echo.
echo Iniciando Menu principal...
echo.
chcp 65001 >nul
set "PS_URL=https://raw.githubusercontent.com/clawdbotfmm-spec/winsetup/main/menu_v2.ps1"
set "LOCAL_PS1=%temp%\menu_v2_temp.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; " ^
    "$OutputEncoding = [System.Text.Encoding]::UTF8; " ^
    "Start-Transcript -Path $env:TEMP\winsetup_boot_log.txt -Force; " ^
    "$content = (Invoke-WebRequest -Uri '%PS_URL%' -UseBasicParsing).Content; " ^
    "[System.IO.File]::WriteAllText('%LOCAL_PS1%', $content, [System.Text.Encoding]::UTF8); " ^
    "& '%LOCAL_PS1%'; " ^
    "Stop-Transcript; " ^
    "Remove-Item '%LOCAL_PS1%' -ErrorAction SilentlyContinue"
goto MENU

:OPENCLAW
echo.
echo Iniciando instalacion de OpenClaw...
echo.
chcp 65001 >nul
set "PS_URL=https://raw.githubusercontent.com/clawdbotfmm-spec/openclaw/main/openclaw.ps1"
set "LOCAL_PS1=%temp%\openclaw_temp.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; " ^
    "$OutputEncoding = [System.Text.Encoding]::UTF8; " ^
    "$content = (Invoke-WebRequest -Uri '%PS_URL%' -UseBasicParsing).Content; " ^
    "[System.IO.File]::WriteAllText('%LOCAL_PS1%', $content, [System.Text.Encoding]::UTF8); " ^
    "& '%LOCAL_PS1%'; " ^
    "Remove-Item '%LOCAL_PS1%' -ErrorAction SilentlyContinue"
goto MENU

:SALIR
echo.
echo Hasta luego.
timeout /t 2 >nul
exit
