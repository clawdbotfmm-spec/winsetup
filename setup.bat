@echo off
title Setup Windows - clawdbotfmm-spec

:: Auto-elevar a administrador
net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit
)

echo Iniciando configuracion del sistema...
echo.
PowerShell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/clawdbotfmm-spec/winsetup/main/menu_v2.ps1 | iex"

pause
