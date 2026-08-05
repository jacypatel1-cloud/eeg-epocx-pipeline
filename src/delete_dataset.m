function delete_dataset(cfg, name)
%DELETE_DATASET  Permanently remove a data/raw/<name> dataset folder.
%
%   delete_dataset(cfg, name) deletes data/raw/<name> and everything in it.
%   This does not touch data/processed, figures, or results -- any output
%   already produced from this dataset stays put; only the raw source
%   folder is removed.
%
%   THE ONE SAFETY CHECK THIS FUNCTION EXISTS TO ENFORCE
%   The path being deleted must resolve to a direct child of cfg.rawDir.
%   That guards against ever deleting something else -- a coding mistake
%   that passed a full path instead of a bare name, or a name containing
%   ".." -- turning into an rmdir() call somewhere it was never meant to
%   reach. This is a one-way, unrecoverable operation on (potentially)
%   irreplaceable recordings, so the check happens before rmdir runs, not
%   after.
%
%   Callers driving this from a UI are expected to confirm with the user
%   first; this function does not prompt.
%
%   See also LIST_DATASETS, RENAME_DATASET, IMPORT_DATASET_ZIP.

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

rmdir(targetPath, 's');
fprintf('Deleted dataset "%s"\n  %s\n', name, targetPath);
end
