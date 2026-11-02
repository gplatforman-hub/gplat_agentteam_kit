@echo off
rem ============================================================
rem  Agent-Team Course - connect personal mail (Appendix B-2, optional)
rem  Double-click this file. It runs env_check.ps1 -MailOnly.
rem  (ASCII only on purpose: cmd.exe reads .bat files in CP949.)
rem ============================================================
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0env_check.ps1" -MailOnly %*
