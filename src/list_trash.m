function rows = list_trash(cfg)
%LIST_TRASH  Summarise everything currently in data/.trash.
%
%   rows = list_trash(cfg) returns a struct array, one entry per item
%   directly under cfg.trashDir (see MOVE_TO_TRASH), each with:
%       name         the trashed entry's own name, e.g. "Harvard__trashed_20260805_142233"
%       path         its full path inside cfg.trashDir
%       isDir        true for a trashed dataset folder, false for a file
%       originalPath where it came from (from the ".origin.txt" sidecar
%                    MOVE_TO_TRASH writes), or "" if that sidecar is
%                    missing -- which can only happen if the trash folder
%                    was tampered with by hand, since MOVE_TO_TRASH always
%                    writes one
%       trashedOn    datetime parsed from the timestamp in the entry name
%
%   Sidecar files themselves ("*.origin.txt") are not listed as entries.
%
%   See also MOVE_TO_TRASH, RESTORE_FROM_TRASH, EMPTY_TRASH_ITEM.

fields = {'name', 'path', 'isDir', 'originalPath', 'trashedOn'};
rows = cell2struct(cell(numel(fields), 0), fields, 1);

if exist(cfg.trashDir, 'dir') ~= 7
    return
end

entries = dir(cfg.trashDir);
entries = entries(~ismember({entries.name}, {'.', '..'}) & ...
                   ~endsWith({entries.name}, '.origin.txt'));

if isempty(entries)
    return
end

rows(numel(entries)).name = '';
for k = 1:numel(entries)
    itemPath = fullfile(entries(k).folder, entries(k).name);

    originFile = [itemPath '.origin.txt'];
    originalPath = "";
    if exist(originFile, 'file') == 2
        originalPath = string(strtrim(fileread(originFile)));
    end

    tok = regexp(entries(k).name, '__trashed_(\d{8}_\d{6})$', 'tokens', 'once');
    if ~isempty(tok)
        trashedOn = datetime(tok{1}, 'InputFormat', 'yyyyMMdd_HHmmss');
    else
        trashedOn = datetime(entries(k).datenum, 'ConvertFrom', 'datenum');
    end

    rows(k).name         = entries(k).name;
    rows(k).path          = itemPath;
    rows(k).isDir         = entries(k).isdir;
    rows(k).originalPath  = originalPath;
    rows(k).trashedOn     = trashedOn;
end
end
