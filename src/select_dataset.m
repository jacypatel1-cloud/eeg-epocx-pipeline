function datasetDir = select_dataset(cfg, varargin)
%SELECT_DATASET  Choose which data/raw/<name> subfolder to process.
%
%   datasetDir = select_dataset(cfg) returns the most recently modified
%   subfolder directly under cfg.rawDir -- i.e. "whatever was extracted most
%   recently."
%
%   datasetDir = select_dataset(cfg, 'Dataset', name) returns
%   fullfile(cfg.rawDir, name) instead, after checking it actually exists.
%
%   WHY DATASETS LIVE IN THEIR OWN SUBFOLDERS
%   RUN_PIPELINE sorts every recording it finds by timestamp and treats
%   "first" and "last" as meaningful (the comparison figure). Two unrelated
%   datasets dropped loose into the same folder would get sorted and
%   compared against each other by coincidence of clock time, which answers
%   no real question. One dataset per subfolder keeps every run scoped to
%   data that is actually comparable to itself.
%
%   WHY "MOST RECENTLY MODIFIED", NOT "MOST RECENTLY CREATED"
%   Windows does not reliably preserve a folder's original creation time
%   through a zip extraction (it can inherit the archive's creation time
%   instead of the extraction time). Modification time is what actually
%   changes at the moment the files land, so it is the reliable signal for
%   "what did I just add."
%
%   See also RUN_PIPELINE, SETUP_PATHS.

p = inputParser;
p.addRequired('cfg', @isstruct);
p.addParameter('Dataset', '', @(x) ischar(x) || isstring(x));
p.parse(cfg, varargin{:});
opt = p.Results;

entries = dir(cfg.rawDir);
entries = entries([entries.isdir] & ~ismember({entries.name}, {'.', '..'}));

if isempty(entries)
    error('select_dataset:noDatasets', ...
        ['No dataset subfolders found in:\n  %s\n' ...
         'Extract each dataset into its own subfolder first, e.g.\n' ...
         '  data/raw/Harvard/...\n  data/raw/Zenodo/...'], cfg.rawDir);
end

if strlength(string(opt.Dataset)) > 0
    hit = strcmpi({entries.name}, opt.Dataset);
    if ~any(hit)
        error('select_dataset:noSuchDataset', ...
            'No dataset folder named "%s" in:\n  %s\nAvailable: %s', ...
            char(opt.Dataset), cfg.rawDir, strjoin({entries.name}, ', '));
    end
    chosen = entries(hit);
    chosenBy = 'requested by name';
else
    [~, idx] = max([entries.datenum]);
    chosen = entries(idx);
    chosenBy = 'most recently modified';
end

datasetDir = fullfile(chosen.folder, chosen.name);
fprintf('Dataset: %s (%s)\n', chosen.name, chosenBy);
if numel(entries) > 1 && strlength(string(opt.Dataset)) == 0
    others = setdiff({entries.name}, chosen.name);
    fprintf('  (%d other dataset(s) available: %s -- pass ''Dataset'', ''name'' to use one)\n', ...
            numel(others), strjoin(others, ', '));
end
end
