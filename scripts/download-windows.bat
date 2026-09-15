@echo off
REM Download the latest Lagestroemia Windows build from GitHub Releases.
REM
REM Usage: scripts\download-windows.bat
REM
REM Downloads lagestroemia-windows-x64.zip, extracts it to .\lagestroemia\,
REM and prints the path to the exe.

powershell -ExecutionPolicy Bypass -File "%~dp0download-windows.ps1" %*
