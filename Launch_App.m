%% LAUNCH THE EEG DATASET MANAGER
%
%  This is what double-clicking "1 - START HERE.bat" runs. It gets MATLAB
%  ready (paths, EEGLAB, environment check, Claude Code sharing) the same
%  way START_HERE.m always has, then opens the interactive dataset manager
%  directly -- add dataset zips, browse/run/delete datasets and see results,
%  all from the window, with no commands to type.
%
%  TROUBLESHOOTING
%  If the app window does not appear, or something needs diagnosing at the
%  console instead, run START_HERE.m directly -- it does the same setup and
%  prints a full menu of console commands instead of opening the app.
%
% -------------------------------------------------------------------------

clc;

fprintf('\n');
fprintf('==============================================================\n');
fprintf('  EEG PIPELINE  --  Emotiv EPOC X                             \n');
fprintf('  Starting up...                                              \n');
fprintf('==============================================================\n\n');

% --- Project root, same trick START_HERE.m uses --------------------------
thisFile    = mfilename('fullpath');
projectRoot = fileparts(thisFile);
cd(projectRoot);
addpath(fullfile(projectRoot, 'src'));

% --- Paths + EEGLAB, output suppressed so this stays quick and quiet -----
fprintf('Setting up (this takes a few seconds)...\n');
setupLog = evalc('cfg = setup_paths();');

% --- Environment check, but only speak up if something is actually wrong.
% check_env() prints a full report unconditionally; that report is exactly
% what START_HERE.m is for. Here we just need its pass/fail return value.
evalc('envOk = check_env();');
if ~envOk
    fprintf(2, '\nSomething in the environment check did not pass.\n');
    fprintf(2, 'Run START_HERE.m for the full report before relying on results.\n\n');
end

% --- Share the session so Claude Code can still connect, same as before --
if exist('shareMATLABSession', 'file') == 0
    addonGuess = fullfile(getenv('APPDATA'), 'MathWorks', 'MATLAB Add-Ons', ...
                          'Toolboxes', 'MATLAB MCP Server Toolbox');
    if exist(addonGuess, 'dir')
        addpath(addonGuess);
    end
end
if exist('shareMATLABSession', 'file') ~= 0
    try
        shareMATLABSession();
    catch
        % Non-fatal -- the app works fine without Claude Code attached.
    end
end

% --- Open the app ---------------------------------------------------------
fprintf('Opening the EEG Dataset Manager...\n\n');
app = EEGDatasetManagerApp(cfg); %#ok<NASGU>

fprintf('==============================================================\n');
fprintf('  READY. The Dataset Manager window is open.\n');
fprintf('  For the console workflow or troubleshooting, run START_HERE.m\n');
fprintf('==============================================================\n\n');
