:: ==========================================
:: File: uninstall.bat
:: Description: 1-Click uninstaller for PS5.1 & PS7
:: ==========================================
@echo off
title PowerShell Script Manager Uninstaller
color 0C

echo [*] Initializing complete cleanup...
echo [*] Removing scripts and profile configurations for both PS5.1 and PS7...

:: Inline PowerShell script to clean both profile directories safely
set "CLEAN_CMD=$dirs = @('WindowsPowerShell', 'PowerShell'); foreach ($d in $dirs) { $base = Join-Path ([Environment]::GetFolderPath('MyDocuments')) $d; $cs = Join-Path $base 'CustomScripts'; if (Test-Path $cs) { Remove-Item -LiteralPath $cs -Recurse -Force }; $prof = Join-Path $base 'Microsoft.PowerShell_profile.ps1'; if (Test-Path $prof) { $c = Get-Content -LiteralPath $prof -Raw -ErrorAction Ignore; $c = $c -replace '(?s)# AUTO-LOADER FOR MODULAR SCRIPTS.*', ''; if ([string]::IsNullOrWhiteSpace($c)) { Remove-Item -LiteralPath $prof -Force } else { Set-Content -LiteralPath $prof -Value $c.Trim() -Encoding UTF8 -Force } } }"

:: Execute the cleanup command using the default Windows PowerShell
powershell -NoProfile -ExecutionPolicy Bypass -Command "%CLEAN_CMD%"

echo.
echo [*] Uninstallation finished successfully! 
echo [*] All aliases and CustomScripts have been removed from your system.
pause