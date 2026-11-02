@echo off
rem ============================================================
rem  Agent-Team Course - environment check launcher
rem  Double-click this file. It runs env_check.ps1 next to it.
rem  (ASCII only on purpose: cmd.exe reads .bat files in CP949.)
rem ============================================================
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0env_check.ps1" %*
