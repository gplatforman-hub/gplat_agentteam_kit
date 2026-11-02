@echo off
rem ============================================================
rem  Start Claude Code in the starter-kit folder.
rem  The cd below is the whole point: agents (.claude\agents),
rem  skills (.claude\skills) and the autosave/guard hooks are all
rem  resolved from the current folder. Opening a window anywhere
rem  else and typing 'claude' gives you zero agents.
rem  ASCII body on purpose: a .bat with non-ASCII text breaks when
rem  the file arrives with LF line endings (GitHub archive does).
rem ============================================================
chcp 65001 >nul
cd /d "%~dp0"
where claude >nul 2>nul
if errorlevel 1 goto nocli
echo [GP] starter-kit folder: %CD%
echo [GP] Starting Claude Code. Agents, skills and hooks load from here.
echo.
call claude
if errorlevel 1 pause
exit /b 0
:nocli
echo [GP] Claude Code not found. Run the environment check (the .bat next to this file) first.
pause
exit /b 1
