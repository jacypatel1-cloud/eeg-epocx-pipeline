@echo off
REM ============================================================
REM  Launch the EEG project.
REM
REM  Double-click this file. It opens MATLAB already pointed at
REM  this folder and opens the Dataset Manager window directly --
REM  add dataset zips, run the pipeline, see results, with no
REM  typing needed.
REM
REM  Troubleshooting: run START_HERE.m directly inside MATLAB for
REM  the console workflow and a full environment report.
REM
REM  If nothing happens, MATLAB is probably not on your system
REM  PATH. See docs/SETUP.md, section 4, "Prerequisite".
REM ============================================================

cd /d "%~dp0"

echo Starting MATLAB and opening the EEG Dataset Manager...
echo This takes about 20-30 seconds.

start "" matlab -sd "%~dp0" -r "run('Launch_App.m')"

exit
