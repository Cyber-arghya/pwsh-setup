@echo off
title PowerShell Script Manager Installer
color 0A

echo [*] Initializing smart automated setup...
set "SCRIPT_URL=https://raw.githubusercontent.com/Cyber-arghya/pwsh-setup/refs/heads/main/setup.ps1"
set "DEV_SCRIPT_URL=https://raw.githubusercontent.com/Cyber-arghya/pwsh-setup/refs/heads/main/dev-setup.ps1"

:: 1. Install setup.ps1 and dev-setup.ps1 into Windows PowerShell 5.1
echo [*] Injecting setup.ps1 into Windows PowerShell 5.1...
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm %SCRIPT_URL% | iex"

echo [*] Injecting dev-setup.ps1 into Windows PowerShell 5.1...
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm %DEV_SCRIPT_URL% | iex"

:: 2. Check for modern PowerShell 7+ (pwsh) and inject both scripts if detected
where pwsh >nul 2>nul
if %errorlevel% equ 0 (
    echo.
    echo [*] PowerShell 7 detected! Injecting setup.ps1 into PS7...
    pwsh -NoProfile -ExecutionPolicy Bypass -Command "irm %SCRIPT_URL% | iex"

    echo [*] Injecting dev-setup.ps1 into PS7...
    pwsh -NoProfile -ExecutionPolicy Bypass -Command "irm %DEV_SCRIPT_URL% | iex"
) else (
    echo.
    echo [*] PowerShell 7 not found. Skipping PS7 injection.
)

echo.
echo [*] Smart Installation finished successfully!
echo [*] Please close this window and open a NEW PowerShell terminal.
pause