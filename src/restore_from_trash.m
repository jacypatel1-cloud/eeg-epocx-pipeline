function originalPath = restore_from_trash(cfg, trashEntryName)
%RESTORE_FROM_TRASH  Move a trashed dataset or file back to where it came from.
%
%   originalPath = restore_from_trash(cfg, trashEntryName) reads the
%   ".origin.txt" sidecar MOVE_TO_TRASH wrote alongside the entry, moves the
%   item back there, and removes the sidecar. Returns the restored path.
%
%   REFUSES RATHER THAN OVERWRITE. If something already exists at the
%   original location (e.g. a new dataset was imported under the same name
%   after this one was trashed), this errors instead of silently replacing
%   it -- the same reasoning IMPORT_DATASET_ZIP and RENAME_DATASET already
%   use for name collisions.
%
%   See also MOVE_TO_TRASH, LIST_TRASH, EMPTY_TRASH_ITEM.

p = inputParser;
p.addRequired('cfg',            @isstruct);
p.addRequired('trashEntryName', @(x) ischar(x) || isstring(x));
p.parse(cfg, trashEntryName);

trashEntryName = char(trashEntryName);
itemPath   = fullfile(cfg.trashDir, trashEntryName);
originFile = [itemPath '.origin.txt'];

if exist(itemPath, 'file') ~= 2 && exist(itemPath, 'dir') ~= 7
    error('restore_from_trash:noSuchItem', ...
        'Nothing named "%s" in the trash.', trashEntryName);
end
if exist(originFile, 'file') ~= 2
    error('restore_from_trash:noOriginRecord', ...
        ['No origin record for "%s" -- do not know where to restore it to.\n' ...
         'This should never happen through normal use; the trash folder may ' ...
         'have been edited by hand.'], trashEntryName);
end

originalPath = strtrim(fileread(originFile));

if exist(originalPath, 'file') == 2 || exist(originalPath, 'dir') == 7
    error('restore_from_trash:destinationExists', ...
        ['Cannot restore "%s": something already exists at its original ' ...
         'location:\n  %s\nMove or rename that first.'], trashEntryName, originalPath);
end

destParent = fileparts(originalPath);
if ~exist(destParent, 'dir'); mkdir(destParent); end

movefile(itemPath, originalPath);
delete(originFile);

fprintf('Restored "%s"\n  -> %s\n', trashEntryName, originalPath);
end
