function cfg = setup_paths()
%SETUP_PATHS  Initialise the EEG project: paths, EEGLAB, folder structure.
%
%   cfg = setup_paths() adds the project source folder and EEGLAB to the
%   MATLAB path, creates any missing data folders, and returns a struct of
%   absolute paths used by the rest of the pipeline.
%
%   Run this once at the start of every session:
%       cd('<project root>'); addpath('src'); cfg = setup_paths();
%
%   Everything stays local. No network calls are made by this function.

% --- Project root = parent of the folder containing this file -----------
thisFile   = mfilename('fullpath');
srcDir     = fileparts(thisFile);
cfg.root   = fileparts(srcDir);

% --- Standard folders ---------------------------------------------------
cfg.src       = srcDir;
cfg.rawDir    = fullfile(cfg.root, 'data', 'raw');
cfg.procDir   = fullfile(cfg.root, 'data', 'processed');
cfg.figDir    = fullfile(cfg.root, 'figures');
cfg.resultDir = fullfile(cfg.root, 'results');
cfg.toolboxes = fullfile(cfg.root, 'toolboxes');

folders = {cfg.rawDir, cfg.procDir, cfg.figDir, cfg.resultDir, cfg.toolboxes};
for k = 1:numel(folders)
    if ~exist(folders{k}, 'dir')
        mkdir(folders{k});
        fprintf('Created %s\n', folders{k});
    end
end

addpath(genpath(cfg.src));

% --- Emotiv EPOC X constants -------------------------------------------
cfg.channels = {'AF3','F7','F3','FC5','T7','P7','O1', ...
                'O2','P8','T8','FC6','F4','F8','AF4'};
cfg.nChannels = 14;
cfg.chanlocsFile = fullfile(cfg.root, 'data', 'emotivX_channels_location.ced');

% --- Locate and start EEGLAB -------------------------------------------
if exist('eeglab', 'file') ~= 2
    hits = dir(fullfile(cfg.toolboxes, 'eeglab*'));
    hits = hits([hits.isdir]);
    if isempty(hits)
        error('setup_paths:noEEGLAB', ...
            ['EEGLAB not found. Download it from https://eeglab.org and ' ...
             'unzip it into:\n  %s'], cfg.toolboxes);
    end
    eeglabPath = fullfile(cfg.toolboxes, hits(end).name);
    addpath(eeglabPath);
    fprintf('Added EEGLAB from %s\n', eeglabPath);
end

% Start EEGLAB without the GUI; this puts all EEGLAB subfolders on the path.
eeglab nogui;

cfg.eeglabPath = fileparts(which('eeglab'));
fprintf('\nProject root : %s\nEEGLAB       : %s\n', cfg.root, cfg.eeglabPath);
end
