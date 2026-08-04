function get_sample_data(cfg)
%GET_SAMPLE_DATA  Instructions for obtaining the public sample recordings.
%
%   get_sample_data(cfg) prints where to download the Emotiv EPOC X sample
%   dataset and where to put it. It does NOT download anything itself.
%
%   WHY THIS DOES NOT DOWNLOAD AUTOMATICALLY
%   The project rule is that nothing here makes network calls at runtime.
%   That rule exists because this pipeline is intended to run on clinical
%   recordings, and code that reaches the internet while handling patient
%   data is a liability regardless of what it actually sends. Downloading is
%   a one-off setup step done by a human, not something the software does.
%
%   WHY THE DATA IS NOT IN THE GIT REPOSITORY
%   Two reasons. It is large, and more importantly `data/` is deliberately
%   excluded in .gitignore so that real patient recordings can never be
%   committed by accident. That protection only works if it applies to the
%   whole folder, with no exceptions carved out for sample files.
%
%   See also SETUP_PATHS, RUN_PIPELINE.

if nargin < 1
    cfg = setup_paths();
end

fprintf('\n');
fprintf('==============================================================\n');
fprintf('  GETTING THE SAMPLE DATA\n');
fprintf('==============================================================\n\n');

fprintf('This project ships without recordings. To try it out, download a\n');
fprintf('public Emotiv EPOC X dataset and unzip it into:\n\n');
fprintf('    %s\n\n', cfg.rawDir);

fprintf('OPTION 1 -- Harvard Dataverse (the one this was built against)\n');
fprintf('    https://doi.org/10.7910/DVN/JMH4PD\n');
fprintf('    54 recordings, 11 participants, 5 eye-movement conditions.\n');
fprintf('    Licence: CC0 (public domain). Files are EmotivPRO CSV exports.\n');
fprintf('    Download the whole dataset, unzip, and copy the *.csv files in.\n');
fprintf('    The "_intervalMarker.csv" and ".json" files are ignored by the\n');
fprintf('    pipeline, so it does no harm to copy everything.\n\n');

fprintf('OPTION 2 -- Zenodo, 14-channel Emotiv EPOC\n');
fprintf('    https://zenodo.org/records/1183360\n');
fprintf('    Small (~3 MB) resting-state and SSVEP recordings.\n\n');

fprintf('OPTION 3 -- your own recordings\n');
fprintf('    Export from EmotivPRO as CSV, or record to EDF/BDF.\n');
fprintf('    Both are read automatically. Just drop them in the folder above.\n\n');

fprintf('--------------------------------------------------------------\n');
fprintf('NO SAMPLE DATA NEEDED FOR A QUICK CHECK\n');
fprintf('You can verify the whole analysis chain without any recordings,\n');
fprintf('using synthetic data with a known answer:\n\n');
fprintf('    fixture = make_test_fixture(cfg);\n');
fprintf('    EEG     = import_emotiv_csv(fixture, cfg);\n');
fprintf('    S       = compute_psd(EEG, pipeline_config());\n');
fprintf('    plot_psd_stack(S, cfg);\n\n');
fprintf('That builds a file with a 10 Hz peak at the back of the head. If\n');
fprintf('the plot shows the peak at 10 Hz, the analysis is working.\n');
fprintf('Delete the fixture from data\\raw afterwards.\n');
fprintf('--------------------------------------------------------------\n\n');

nFound = numel(dir(fullfile(cfg.rawDir, '*.csv'))) ...
       + numel(dir(fullfile(cfg.rawDir, '*.edf'))) ...
       + numel(dir(fullfile(cfg.rawDir, '*.bdf')));

if nFound > 0
    fprintf('You already have %d file(s) in data\\raw.\n\n', nFound);
else
    fprintf('data\\raw is currently empty.\n\n');
end
end
