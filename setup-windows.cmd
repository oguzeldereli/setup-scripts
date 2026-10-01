@echo off
rem Double-click this file to run setup-windows.ps1 without changing PowerShell's execution policy.
rem Extra switches are passed through, e.g.  setup-windows.cmd -All
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-windows.ps1" %*
echo.
pause
