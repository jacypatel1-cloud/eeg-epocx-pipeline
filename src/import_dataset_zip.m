function datasetDir = import_dataset_zip(zipPath, varargin)
%IMPORT_DATASET_ZIP  Extract a downloaded dataset zip into its own data/raw
%   subfolder, ready for RUN_PIPELINE to pick up.
%
%   datasetDir = import_dataset_zip(zipPath) extracts zipPath into
%   data/raw/<name>/, where <name> is derived from the zip's own filename,
%   and returns the folder path.
%
%   datasetDir = import_dataset_zip(zipPath, 'Name', name) uses that name
%   for the subfolder instead of deriving one from the filename.
%
%   WHY THIS EXISTS
%   RUN_PIPELINE expects each dataset in its own subfolder under data/raw/
%   (see SELECT_DATASET) so that unrelated datasets never get sorted or
%   compared against each other by coincidence of file timestamp. This
%   function is the one manual step in an otherwise hands-off workflow:
%   download a zip, run this once, then RUN_PIPELINE() picks it up
%   automatically as the newest dataset. It does not run itself -- nothing
%   in this project watches the filesystem or triggers on its own; every
%   step here happens because you called it.
%
%   WHY IT REFUSES TO OVERWRITE
%   A name collision almost always means "I already extracted this," and
%   silently re-extracting on top of it could interleave an old, possibly
%   partially-processed dataset with a new one under the same folder name --
%   exactly the kind of mixing SELECT_DATASET exists to prevent. Pick a
%   different 'Name', or remove the old folder yourself first.
%
%   See also SELECT_DATASET, RUN_PIPELINE.

p = inputParser;
p.addRequired('zipPath', @(x) ischar(x) || isstring(x));
p.addParameter('Name', '', @(x) ischar(x) || isstring(x));
p.parse(zipPath, varargin{:});
opt = p.Results;

zipPath = char(zipPath);
if exist(zipPath, 'file') ~= 2
    error('import_dataset_zip:notFound', 'Zip file not found:\n  %s', zipPath);
end
[~, ~, ext] = fileparts(zipPath);
if ~strcmpi(ext, '.zip')
    error('import_dataset_zip:notAZip', ...
        'Expected a .zip file, got "%s":\n  %s', ext, zipPath);
end

cfg = setup_paths();

if strlength(string(opt.Name)) > 0
    name = char(opt.Name);
else
    [~, name] = fileparts(zipPath);
end
% Folder names can't contain these on Windows; strip them rather than fail
% on an otherwise-reasonable zip filename.
name = regexprep(name, '[<>:"/\\|?*]', '_');

datasetDir = fullfile(cfg.rawDir, name);
if exist(datasetDir, 'dir') == 7
    error('import_dataset_zip:alreadyExists', ...
        ['Dataset folder already exists:\n  %s\n' ...
         'Pass a different ''Name'', or remove that folder yourself if this ' ...
         'is meant to replace it.'], datasetDir);
end

mkdir(datasetDir);
try
    unzip(zipPath, datasetDir);
catch ME
    rmdir(datasetDir, 's');   % don't leave a half-extracted folder behind
    rethrow(ME);
end

fprintf('Extracted %s\n  -> %s\n', zipPath, datasetDir);
fprintf('run_pipeline() will now use this as the latest dataset by default.\n');
fprintf('  (or run_pipeline(''Dataset'', ''%s'') to use it explicitly later)\n', name);
end
