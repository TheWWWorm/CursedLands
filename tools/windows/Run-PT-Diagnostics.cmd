@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Prepare-PT-Diagnostics.ps1"
exit /b %errorlevel%
