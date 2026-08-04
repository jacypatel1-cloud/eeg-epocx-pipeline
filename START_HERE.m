%% START HERE
%
%  Run this file first, every time you open MATLAB.
%
%  HOW TO RUN IT
%    Click the green "Run" button at the top of this window,
%    or press F5.
%
%  WHAT IT DOES
%    1. Points MATLAB at this project folder
%    2. Starts EEGLAB
%    3. Checks that everything needed is installed
%    4. Shares the MATLAB session so Claude can connect to it
%    5. Prints a menu of what you can do next
%
%  It changes nothing and processes nothing. It is safe to run
%  as many times as you like.
%
% -------------------------------------------------------------------------

clc;

fprintf('\n');
fprintf('==============================================================\n');
fprintf('  EEG PIPELINE  --  Emotiv EPOC X                             \n');
fprintf('  Starting up...                                              \n');
fprintf('==============================================================\n\n');

%% ---- Step 1 of 4: find the project and load the code --------------------
% Work out where this file lives, so the project can sit in any folder on
% any computer without a single path needing to be edited.
thisFile    = mfilename('fullpath');
projectRoot = fileparts(thisFile);

cd(projectRoot);
addpath(fullfile(projectRoot, 'src'));

fprintf('[1/4] Project folder\n');
fprintf('      %s\n\n', projectRoot);

%% ---- Step 2 of 4: start EEGLAB and build the folder structure ----------
fprintf('[2/4] Starting EEGLAB (this takes a few seconds)...\n');

startupLog = evalc('cfg = setup_paths();');   % hide EEGLAB's noisy banner

fprintf('      EEGLAB ready.\n\n');

%% ---- Step 3 of 4: check the environment --------------------------------
fprintf('[3/4] Checking that everything needed is installed...\n\n');
check_env();
fprintf('\n');

%% ---- Step 4 of 4: let Claude connect -----------------------------------
% shareMATLABSession makes this MATLAB session visible to the MATLAB MCP
% server, which is how Claude reads and runs code in the window you are
% looking at. Without it, Claude would start its own hidden MATLAB and you
% would not see anything happen on screen.
fprintf('[4/4] Sharing this session so Claude can connect...\n');

% The function lives in a MathWorks Add-On. Normally it is already on the
% path; if a path reset has removed it, look in the standard Add-Ons
% location before giving up.
if exist('shareMATLABSession', 'file') == 0
    addonGuess = fullfile(getenv('APPDATA'), 'MathWorks', 'MATLAB Add-Ons', ...
                          'Toolboxes', 'MATLAB MCP Server Toolbox');
    if exist(addonGuess, 'dir')
        addpath(addonGuess);
    end
end

if exist('shareMATLABSession', 'file') == 0
    fprintf(2, '      MCP Server Toolbox not found.\n');
    fprintf(2, '      Claude will not be able to see this window.\n');
    fprintf(2, '      Everything else still works normally.\n');
    fprintf(2, '      To fix: see SETUP.md, section 4.\n\n');
else
    try
        shareMATLABSession();
        fprintf('      Shared. Claude can now attach to this window.\n\n');
    catch ME
        fprintf(2, '      Could not share the session: %s\n', ME.message);
        fprintf(2, '      Everything else still works normally.\n\n');
    end
end

%% ---- Ready -------------------------------------------------------------
% Count only real recordings. The Harvard dataset also ships
% "_intervalMarker.csv" files, which are event lists rather than EEG; the
% pipeline ignores them, so counting them here would overstate the total by
% roughly double and make the number meaningless.
rawList = [dir(fullfile(cfg.rawDir, '*.csv'));
           dir(fullfile(cfg.rawDir, '*.edf'));
           dir(fullfile(cfg.rawDir, '*.bdf'))];
if isempty(rawList)
    nRaw = 0;
else
    nRaw = sum(~contains({rawList.name}, '_intervalMarker', 'IgnoreCase', true));
end

fprintf('==============================================================\n');
fprintf('  READY.  %d recording(s) waiting in data\\raw\n', nRaw);
fprintf('==============================================================\n\n');

fprintf('WHAT TO DO NEXT -- copy one of these into the box below\n');
fprintf('and press Enter:\n\n');

fprintf('  Process everything and make all the plots\n');
fprintf('      results = run_pipeline();\n\n');

fprintf('  Quick test on just 3 recordings (about 30 seconds)\n');
fprintf('      results = run_pipeline(''Limit'', 3, ''PlotEach'', true);\n\n');

fprintf('  Process one person only\n');
fprintf('      results = run_pipeline(''Subject'', "126518");\n\n');

fprintf('  Open the quality-control table in a spreadsheet\n');
fprintf('      winopen(fullfile(cfg.resultDir, ''qc_summary.csv''));\n\n');

fprintf('  Open the figures folder\n');
fprintf('      winopen(cfg.figDir);\n\n');

fprintf('  Check the EDF reader is still correct\n');
fprintf('      test_edf_roundtrip(cfg);\n\n');

fprintf('--------------------------------------------------------------\n');
fprintf('Full instructions are in README.md.\n');
fprintf('The variable "cfg" now holds every folder path you need.\n');
fprintf('--------------------------------------------------------------\n\n');
