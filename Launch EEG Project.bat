@echo off
REM ============================================================
REM  Launch the EEG project.
REM
REM  Double-click this file. It opens MATLAB already pointed at
REM  this folder and runs START_HERE.m automatically, so the
REM  project is ready to use with no typing.
REM
REM  If nothing happens, MATLAB is probably not on your system
REM  PATH. See SETUP.md, section 4, "Prerequisite".
REM ============================================================

cd /d "%~dp0"

echo Starting MATLAB and loading the EEG project...
echo This takes about 20-30 seconds.

start "" matlab -sd "%~dp0" -r "run('START_HERE.m')"

exit
