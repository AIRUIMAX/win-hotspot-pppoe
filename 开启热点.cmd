@echo off
chcp 65001 >nul
setlocal
set "PS1=%~dp0start-hotspot.ps1"

if not exist "%PS1%" (
    echo [x] start-hotspot.ps1 not found in the same folder.
    pause
    exit /b 1
)

net session >nul 2>&1
if %errorlevel% equ 0 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
) else (
    echo Requesting administrator privileges...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%PS1%\"'"
)
