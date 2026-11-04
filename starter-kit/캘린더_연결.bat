@echo off
rem ============================================================
rem  Agent-Team Course - connect Naver Calendar (Appendix, optional)
rem  Double-click this file. It runs naver-calendar\connect.ps1.
rem  (ASCII only on purpose: cmd.exe reads .bat files in CP949.)
rem ============================================================
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0naver-calendar\connect.ps1" %*
