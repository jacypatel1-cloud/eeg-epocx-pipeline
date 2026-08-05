function permanently_delete_trash_item(cfg, trashEntryName)
%PERMANENTLY_DELETE_TRASH_ITEM  Irreversibly remove one item from the trash.
%
%   permanently_delete_trash_item(cfg, trashEntryName) deletes a dataset
%   folder or file already sitting in cfg.trashDir, along with its
%   ".origin.txt" sidecar. Unlike MOVE_TO_TRASH, this has no way back --
%   callers (the UI) are expected to have already confirmed this
%   specifically with the user, separately from the original "move to
%   trash" confirmation.
%
%   Only operates on items that resolve to a direct child of cfg.trashDir,
%   for the same reason DELETE_DATASET checks its own target -- so that a
%   coding mistake can never reach outside the trash folder.
%
%   See also LIST_TRASH, RESTORE_FROM_TRASH.

p = inputParser;
p.addRequired('cfg',            @isstruct);
p.addRequired('trashEntryName', @(x) ischar(x) || isstring(x));
p.parse(cfg, trashEntryName);

trashEntryName = char(trashEntryName);
if isempty(trashEntryName) || any(trashEntryName == '/' | trashEntryName == '\')
    error('permanently_delete_trash_item:badName', ...
        'Not a valid trash entry name: "%s"', trashEntryName);
end

itemPath = fullfile(cfg.trashDir, trashEntryName);
isDir  = exist(itemPath, 'dir') == 7;
isFile = exist(itemPath, 'file') == 2;
if ~isDir && ~isFile
    error('permanently_delete_trash_item:noSuchItem', ...
        'Nothing named "%s" in the trash.', trashEntryName);
end

[parentOfItem, ~, ~] = fileparts(itemPath);
if ~strcmpi(char(java.io.File(parentOfItem).getCanonicalPath()), ...
            char(java.io.File(cfg.trashDir).getCanonicalPath()))
    error('permanently_delete_trash_item:notADirectChild', ...
        'Refusing to delete "%s": not a direct child of the trash folder.', itemPath);
end

if isDir
    rmdir(itemPath, 's');
else
    delete(itemPath);
end

originFile = [itemPath '.origin.txt'];
if exist(originFile, 'file') == 2
    delete(originFile);
end

fprintf('Permanently deleted from trash: %s\n', trashEntryName);
end
