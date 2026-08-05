function trashPath = delete_dataset(cfg, name)
%DELETE_DATASET  Move a data/raw/<name> dataset folder to the trash.
%
%   trashPath = delete_dataset(cfg, name) moves data/raw/<name> (and
%   everything in it) into cfg.trashDir via MOVE_TO_TRASH, and returns
%   where it landed so the caller can offer to restore it later. This does
%   not touch data/processed, figures, or results -- any output already
%   produced from this dataset stays put; only the raw source folder moves.
%
%   THE ONE SAFETY CHECK THIS FUNCTION EXISTS TO ENFORCE
%   The path being moved must resolve to a direct child of cfg.rawDir. That
%   guards against ever touching something else -- a coding mistake that
%   passed a full path instead of a bare name, or a name containing ".." --
%   turning into a move somewhere it was never meant to reach. Moving to
%   trash is recoverable, but the check still happens before the move, not
%   after: it costs nothing to keep and there is no reason to rely on the
%   trash bin to catch a bug that should never have run at all.
%
%   Callers driving this from a UI are expected to confirm with the user
%   first; this function does not prompt.
%
%   See also LIST_DATASETS, RENAME_DATASET, IMPORT_DATASET_ZIP, MOVE_TO_TRASH.

p = inputParser;
p.addRequired('cfg',  @isstruct);
p.addRequired('name', @(x) ischar(x) || isstring(x));
p.parse(cfg, name);

name = char(name);
if isempty(name) || any(name == '.' | name == '/' | name == '\')
    error('delete_dataset:badName', ...
        'Not a valid dataset name: "%s"', name);
end

targetPath = fullfile(cfg.rawDir, name);

% Resolve both to absolute, canonical paths before comparing parents --
% fullfile() alone does not collapse "..", so this is the check that
% actually enforces "direct child of rawDir", not just string-prefix luck.
if exist(targetPath, 'dir') ~= 7
    error('delete_dataset:noSuchDataset', ...
        'No dataset folder named "%s" in:\n  %s', name, cfg.rawDir);
end

[parentOfTarget, ~, ~] = fileparts(targetPath);
if ~strcmpi(char(java.io.File(parentOfTarget).getCanonicalPath()), ...
            char(java.io.File(cfg.rawDir).getCanonicalPath()))
    error('delete_dataset:notADirectChild', ...
        ['Refusing to delete "%s": it does not resolve to a direct child ' ...
         'of\n  %s\nNothing was deleted.'], targetPath, cfg.rawDir);
end

trashPath = move_to_trash(cfg, targetPath);
fprintf('Dataset "%s" moved to trash.\n', name);
end
