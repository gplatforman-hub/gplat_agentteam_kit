@echo off
rem Learner backup launcher. Secrets and login state are never included.
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0backup_my_company.ps1"
if errorlevel 1 pause
