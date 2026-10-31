@echo off
rem Double-click launcher: starts Install-Win7Look.ps1 (it self-elevates).
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Win7Look.ps1" %*
