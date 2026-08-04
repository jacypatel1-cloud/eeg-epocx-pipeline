@echo off
REM ============================================================
REM  Start Claude Code in the EEG project.
REM
REM  Double-click this rather than typing "claude" yourself.
REM
REM  WHY THIS FILE EXISTS
REM  The MATLAB connection is registered to THIS PROJECT FOLDER
REM  only. If Claude Code is started from anywhere else, the
REM  matlab server does not appear in /mcp at all -- it is not
REM  broken, it simply is not loaded. Starting from the right
REM  folder is the whole fix, and this guarantees it.
REM
REM  BEFORE RUNNING THIS: open MATLAB and run START_HERE.m.
REM  Claude Code attaches to a MATLAB session that is already
REM  shared; if MATLAB is not running and shared first, the
REM  connection fails.
REM ============================================================

cd /d "%~dp0"

echo.
echo  EEG project - starting Claude Code
echo  Folder: %CD%
echo.
echo  Reminder: MATLAB should already be open with START_HERE.m run.
echo.

claude

REM If the window closes instantly, claude is not on PATH.
REM Run this instead:
REM   "%USERPROFILE%\.local\bin\claude.exe"
