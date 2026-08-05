function trashPath = move_to_trash(cfg, targetPath)
%MOVE_TO_TRASH  Move a dataset folder or a single file into data/.trash.
%
%   trashPath = move_to_trash(cfg, targetPath) moves targetPath (a folder
%   or a file, given as a full path) into cfg.trashDir and returns where it
%   landed.
%
%   WHY A TRASH BIN INSTEAD OF DELETING OUTRIGHT
%   The client asked for delete to be "highly regulated -- multiple prompts
%   to prevent error, or a trash bin to allow later emptying." A trash bin
%   is the safer of the two: a recording accidentally deleted a week ago is
%   still one Restore away, where a confirmation dialog only ever protects
%   against the click that just happened.
%
%   NAMING IN THE TRASH
%   Entries are stored as "<original name>__trashed_<timestamp>", so:
%     - deleting the same-named thing twice never collides
%     - the original name is still readable at a glance for RESTORE
%     - the timestamp says exactly when it was deleted, for EMPTY TRASH
%
%   RESTORING LATER
%   Alongside the moved item, a small sidecar file "<trash name>.origin.txt"
%   is written containing the item's original full path -- otherwise, once
%   something is inside the flat cfg.trashDir, there would be no way to
%   know where "back" even means. RESTORE_FROM_TRASH reads this sidecar.
%
%   WHAT THIS DOES NOT DO
%   It does not ask for confirmation -- callers (the UI) are responsible
%   for confirming with the user first.
%
%   See also DELETE_DATASET, RESTORE_FROM_TRASH, SETUP_PATHS.

p = inputParser;
p.addRequired('cfg',        @isstruct);
p.addRequired('targetPath', @(x) ischar(x) || isstring(x));
p.parse(cfg, targetPath);

targetPath = char(targetPath);
isDir  = exist(targetPath, 'dir') == 7;
isFile = exist(targetPath, 'file') == 2;

if ~isDir && ~isFile
    error('move_to_trash:notFound', 'Nothing exists at:\n  %s', targetPath);
end

if ~exist(cfg.trashDir, 'dir'); mkdir(cfg.trashDir); end

[~, baseName, ext] = fileparts(targetPath);
if isDir
    ext = ''; % fileparts would otherwise treat a dotted folder name as having an extension
end
stamp     = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
trashName = sprintf('%s%s__trashed_%s', baseName, ext, stamp);
trashPath = fullfile(cfg.trashDir, trashName);

% Recorded BEFORE the move -- once targetPath is gone, this is the only
% place its original location is written down.
originFile = [trashPath '.origin.txt'];
fid = fopen(originFile, 'w');
if fid < 0
    error('move_to_trash:cannotWriteOrigin', ...
        'Could not write origin record:\n  %s', originFile);
end
fprintf(fid, '%s', targetPath);
fclose(fid);

try
    movefile(targetPath, trashPath);
catch ME
    delete(originFile);   % don't leave an origin record for a move that didn't happen
    rethrow(ME);
end

fprintf('Moved to trash: %s\n  -> %s\n', targetPath, trashPath);
end
