@echo off
rem MailingEditor: removes shortcuts, reminder and this app's tunnel
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\uninstall-windows.ps1"
echo.
pause
