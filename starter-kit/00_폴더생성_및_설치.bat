@echo off
rem ============================================================
rem  WD Agent Team starter-kit installer launcher
rem  Extract the ZIP first, then double-click this file.
rem  ASCII body is intentional for legacy cmd.exe compatibility.
rem ============================================================
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_starterkit.ps1"
if errorlevel 1 pause

