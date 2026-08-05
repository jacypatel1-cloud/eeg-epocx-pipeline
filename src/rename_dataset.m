function newPath = rename_dataset(cfg, oldName, newName)
%RENAME_DATASET  Rename a data/raw/<name> dataset folder in place.
%
%   newPath = rename_dataset(cfg, oldName, newName) renames
%   data/raw/<oldName> to data/raw/<newName> and returns the new full path.
%
%   newName is sanitized the same way IMPORT_DATASET_ZIP sanitizes a zip's
%   filename: characters Windows folder names cannot contain are stripped,
%   so a name typed in the UI can't produce an invalid path.
%
%   Refuses (errors, does not silently pick a different name) if:
%     - data/raw/<oldName> does not exist
%     - the sanitized newName is empty
%     - data/raw/<newName> already exists (same reasoning as
%       IMPORT_DATASET_ZIP's overwrite refusal: a collision almost always
%       means something else is already using that name, and silently
%       merging two dataset folders is exactly what SELECT_DATASET's
%       one-folder-per-dataset rule exists to prevent)
%
%   See also LIST_DATASETS, DELETE_DATASET, IMPORT_DATASET_ZIP.

p = inputParser;
p.addRequired('cfg',     @isstruct);
p.addRequired('oldName', @(x) ischar(x) || isstring(x));
p.addRequired('newName', @(x) ischar(x) || isstring(x));
p.parse(cfg, oldName, newName);

oldName = char(oldName);
oldPath = fullfile(cfg.rawDir, oldName);
if exist(oldPath, 'dir') ~= 7
    error('rename_dataset:noSuchDataset', ...
        'No dataset folder named "%s" in:\n  %s', oldName, cfg.rawDir);
end

sanitized = regexprep(char(newName), '[<>:"/\\|?*]', '_');
sanitized = strtrim(sanitized);
if isempty(sanitized)
    error('rename_dataset:emptyName', ...
        'New name is empty (or contains only characters not allowed in a folder name).');
end

newPath = fullfile(cfg.rawDir, sanitized);

if strcmpi(oldPath, newPath)
    % Same name after sanitizing -- nothing to do, not an error.
    return
end

if exist(newPath, 'dir') == 7
    error('rename_dataset:alreadyExists', ...
        ['Dataset folder already exists:\n  %s\n' ...
         'Choose a different name, or delete that folder first if this is ' ...
         'meant to replace it.'], newPath);
end

movefile(oldPath, newPath);
fprintf('Renamed dataset "%s" -> "%s"\n', oldName, sanitized);
end
