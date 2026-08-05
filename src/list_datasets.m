function rows = list_datasets(cfg)
%LIST_DATASETS  Summarise every dataset folder under data/raw.
%
%   rows = list_datasets(cfg) returns a struct array, one entry per
%   subfolder directly under cfg.rawDir (see SETUP_PATHS), each with:
%       name        the subfolder name, e.g. "Harvard"
%       path        its full path
%       nRecordings how many real recording files FIND_RECORDING_FILES
%                   finds inside it -- the same count RUN_PIPELINE would
%                   process, not a raw file count
%       nBytes      total size on disk of every file inside it (recursive)
%       modified    datetime the folder was last modified
%
%   Returns a 0x0 struct with those fields if data/raw has no subfolders yet
%   (a fresh checkout, or everything deleted) -- not an error, since "no
%   datasets yet" is the normal starting state for the dataset manager UI.
%
%   WHY RECORDING COUNT, NOT RAW FILE COUNT
%   A dataset folder can contain interval-marker CSVs, JSON metadata, or
%   AppleDouble junk from a macOS zip alongside the real recordings (see
%   FIND_RECORDING_FILES). Showing the raw file count in the UI would
%   overstate how much data is actually there and never match what
%   RUN_PIPELINE reports processing.
%
%   See also FIND_RECORDING_FILES, RUN_PIPELINE, RENAME_DATASET, DELETE_DATASET.

fields = {'name', 'path', 'nRecordings', 'nBytes', 'modified'};
rows = cell2struct(cell(numel(fields), 0), fields, 1);

entries = dir(cfg.rawDir);
entries = entries([entries.isdir] & ~ismember({entries.name}, {'.', '..'}));

if isempty(entries)
    return
end

rows(numel(entries)).name = '';   % preallocate
for k = 1:numel(entries)
    dsPath = fullfile(entries(k).folder, entries(k).name);

    recFiles = find_recording_files(dsPath);

    allFiles = dir(fullfile(dsPath, '**', '*'));
    allFiles = allFiles(~[allFiles.isdir]);
    nBytes   = sum([allFiles.bytes]);

    rows(k).name        = entries(k).name;
    rows(k).path        = dsPath;
    rows(k).nRecordings = numel(recFiles);
    rows(k).nBytes      = nBytes;
    rows(k).modified    = datetime(entries(k).datenum, 'ConvertFrom', 'datenum');
end
end
