@echo off
title Setup Windows - clawdbotfmm-spec
setlocal enabledelayedexpansion

:: 1. Auto-elevar a administrador (Ruta dinámica)
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Solicitando permisos de administrador...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo =====================================
echo    Setup Windows - clawdbotfmm-spec
echo =====================================
echo.
echo Iniciando configuracion...
chcp 65001 >nul
echo.

:: 2. Definir rutas
set "PS_URL=https://raw.githubusercontent.com/clawdbotfmm-spec/winsetup/main/menu_v2.ps1"
set "LOCAL_PS1=%temp%\menu_v2_temp.ps1"

:: 3. Descargar y ejecutar (Esto soluciona el error de $PSScriptRoot)
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "Start-Transcript -Path $env:TEMP\winsetup_boot_log.txt -Force; " ^
    "Invoke-WebRequest -Uri '%PS_URL%' -OutFile '%LOCAL_PS1%'; " ^
    "& '%LOCAL_PS1%'; " ^
    "Stop-Transcript; " ^
    "Remove-Item '%LOCAL_PS1%' -ErrorAction SilentlyContinue"

echo.
echo Proceso finalizado.
pause