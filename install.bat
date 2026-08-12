:: ==========================================
:: File: install.bat
:: Description: 1-Click bypass installer for GitHub
:: ==========================================
@echo off
title PowerShell Script Manager Installer
color 0A

echo [*] Initializing automated setup...
echo [*] Downloading and executing core scripts from GitHub...

:: Bypasses Execution Policy to cleanly run the remote setup script
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/Cyber-arghya/pwsh-setup/refs/heads/main/install.bat | iex"

echo.
echo [*] Installation finished successfully! 
echo [*] Please close this window and open a NEW PowerShell terminal.
echo [*] Type 'ip' to test your connection, or 'inps' to add new scripts.
pause