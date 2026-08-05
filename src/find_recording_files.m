function listing = find_recording_files(datasetDir)
%FIND_RECORDING_FILES  List the real recording files inside a dataset folder.
%
%   listing = find_recording_files(datasetDir) returns a dir()-style struct
%   array covering every .edf, .bdf, .csv and .dat file found recursively
%   under datasetDir, with the non-recording files this project's sample
%   datasets are known to ship alongside filtered out.
%
%   WHY THIS EXISTS AS ITS OWN FUNCTION
%   RUN_PIPELINE and the dataset manager UI (LIST_DATASETS, and the app's
%   dataset table / recording counts) both need to answer "how many
%   recordings are actually in this folder" -- and both need the same
%   answer. Keeping the filtering rules in one place means a dataset never
%   shows a different recording count in the UI than it processes.
%
%   WHAT IS FILTERED OUT, AND WHY
%   - "*_intervalMarker.csv"  -- the Harvard dataset's event-marker files.
%     Same extension as a real recording, no EEG in them.
%   - "__MACOSX" folders / "._*" files -- AppleDouble resource-fork shadow
%     files left behind when a zip made on macOS is extracted on Windows.
%     Importing one would fail deep inside the reader with a confusing
%     error, so it is filtered here where the reason is obvious instead.
%
%   The search is recursive ('**') because datasets in this project ship
%   both flat (Harvard) and nested one subfolder per subject (Zenodo).
%
%   See also RUN_PIPELINE, LIST_DATASETS.

listing = [dir(fullfile(datasetDir, '**', '*.edf'));
           dir(fullfile(datasetDir, '**', '*.bdf'));
           dir(fullfile(datasetDir, '**', '*.csv'));
           dir(fullfile(datasetDir, '**', '*.dat'))];
listing = listing(~[listing.isdir]);

isMarker = contains({listing.name}, '_intervalMarker', 'IgnoreCase', true);
listing  = listing(~isMarker);

isAppleJunk = contains({listing.folder}, '__MACOSX', 'IgnoreCase', true) | ...
              startsWith({listing.name}, '._');
listing = listing(~isAppleJunk);
end
