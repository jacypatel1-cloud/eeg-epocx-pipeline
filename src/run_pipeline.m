function results = run_pipeline(varargin)
%RUN_PIPELINE  Process every recording in data/raw, end to end.
%
%   results = run_pipeline() imports, cleans, saves and plots every Emotiv
%   CSV in data/raw, then builds the three-recording comparison figure.
%
%   results = run_pipeline('Name', Value, ...) accepts:
%       'Config'        a struct from PIPELINE_CONFIG. Default: defaults.
%       'Dataset'       which data/raw/<name> subfolder to process. Default:
%                       '' -- the most recently modified subfolder, i.e.
%                       whatever was extracted most recently. See
%                       SELECT_DATASET. Ignored if 'DatasetPath' is given.
%       'DatasetPath'   process this exact folder instead of a data/raw/
%                       subfolder -- e.g. a patient visit folder under
%                       data/patients/<id>/visits/<date>. Bypasses
%                       SELECT_DATASET entirely. Default: '' (use 'Dataset').
%       'ImportOptions' cell array forwarded to IMPORT_RECORDING for every
%                       file, e.g. {'SampleRate', 128, 'ChannelOrder', ...}.
%                       Needed for formats that carry no metadata of their
%                       own (see IMPORT_MATRIX_DAT); ignored by formats that
%                       do (EDF/BDF, EmotivPRO CSV).
%       'Subject'       only process this subject ID, e.g. "126518".
%       'Movement'      only process this condition, e.g. "DOWN".
%       'Limit'         process at most this many recordings (quick test).
%       'Compare'       build the comparison figure.        Default true
%       'PlotEach'      save a stacked PSD per recording.   Default false
%       'Visible'       show figure windows on screen while running. Default
%                       true. The dataset manager app passes false, since it
%                       shows the saved PNGs in its own Results tab instead.
%
%   TYPICAL USE
%       cfg = setup_paths();
%       results = run_pipeline();                       % latest dataset
%       results = run_pipeline('Dataset', 'Harvard');   % a specific one
%       results = run_pipeline('Subject', "126518");    % one participant
%       results = run_pipeline('Limit', 3, 'PlotEach', true);   % quick look
%
%   WHAT IT WRITES
%       data/processed/<name>.set   cleaned data, one file per recording
%       results/qc_summary.csv      one row per recording, every decision
%       results/psd_<name>.mat      the numeric spectrum
%       figures/...                 stacked PSD plots and the comparison
%
%   ONE RECORDING FAILING DOES NOT STOP THE BATCH. Each is wrapped so that a
%   corrupt or unusable file is recorded as failed and the run continues.
%   The summary at the end says exactly which ones failed and why -- a batch
%   that silently skipped files would be worse than useless.
%
%   See also PIPELINE_CONFIG, PREPROCESS_RECORDING, COMPARE_RECORDINGS.

p = inputParser;
p.addParameter('Config',        [],    @(x) isempty(x) || isstruct(x));
p.addParameter('Dataset',       "",    @(x) ischar(x) || isstring(x));
p.addParameter('DatasetPath',   "",    @(x) ischar(x) || isstring(x));
p.addParameter('ImportOptions', {},    @iscell);
p.addParameter('Subject',       "",    @(x) ischar(x) || isstring(x));
p.addParameter('Movement',      "",    @(x) ischar(x) || isstring(x));
p.addParameter('Limit',         Inf,   @isscalar);
p.addParameter('Compare',       true,  @islogical);
p.addParameter('PlotEach',      false, @islogical);
p.addParameter('Visible',       true,  @islogical);
p.parse(varargin{:});
opt = p.Results;

cfg = setup_paths();

P = opt.Config;
if isempty(P); P = pipeline_config(); end

if strlength(string(opt.DatasetPath)) > 0
    datasetDir = char(opt.DatasetPath);
    if exist(datasetDir, 'dir') ~= 7
        error('run_pipeline:noSuchPath', 'DatasetPath does not exist:\n  %s', datasetDir);
    end
    fprintf('Dataset: %s (explicit path)\n', datasetDir);
else
    datasetDir = select_dataset(cfg, 'Dataset', opt.Dataset);
end

% =========================================================================
% Find the recordings
% =========================================================================
% EDF and BDF are the brief's primary formats; EmotivPRO CSV is what the
% public sample datasets ship as; DAT is a headerless matrix format some
% third-party datasets use (see IMPORT_MATRIX_DAT). All are accepted, and
% IMPORT_RECORDING routes each to the right reader. FIND_RECORDING_FILES
% also filters out non-recording files these sample datasets ship alongside
% (event markers, AppleDouble junk from a macOS-made zip) -- see that
% function for why. The dataset manager UI's recording counts use the same
% function, so a dataset never shows a different count there than it
% actually processes here.
listing = find_recording_files(datasetDir);

if isempty(listing)
    error('run_pipeline:noData', ...
        'No recordings found in:\n  %s\nExpected .edf, .bdf, .csv or .dat files.', ...
        datasetDir);
end

infos = arrayfun(@(d) parse_recording_name(fullfile(d.folder, d.name)), ...
                 listing);

% --- optional filters -------------------------------------------------
if strlength(string(opt.Subject)) > 0
    keep  = [infos.subject] == string(opt.Subject);
    infos = infos(keep);
    if isempty(infos)
        error('run_pipeline:noSuchSubject', ...
            'No recordings for subject "%s".', string(opt.Subject));
    end
end

if strlength(string(opt.Movement)) > 0
    want  = upper(regexprep(string(opt.Movement), '\s+', '_'));
    keep  = [infos.movement] == want;
    infos = infos(keep);
    if isempty(infos)
        error('run_pipeline:noSuchMovement', ...
            'No recordings for movement "%s".', want);
    end
end

% Sort into recording order now, so "first" and "last" are meaningful and
% the console log reads chronologically.
[~, order] = sort([infos.timestamp]);
infos      = infos(order);

% Warn if recording times came from more than one source. EmotivPRO writes
% the LOCAL time into the filename but a UTC "start timestamp" into the file
% header, so a batch mixing the two can be misordered by the timezone offset
% -- silently, and only by a few hours, which is exactly the kind of error
% that goes unnoticed. Consistent within one source; risky across two.
srcs = unique([infos.timeSource]);
if numel(srcs) > 1
    warning('run_pipeline:mixedTimeSources', ...
        ['Recording times came from %d different sources (%s). Filename ' ...
         'times are local, file-header times are UTC, so the ordering of ' ...
         '"first"/"second-to-last"/"last" may be wrong by the timezone ' ...
         'offset. Check the timeSource column in results/qc_summary.csv.'], ...
         numel(srcs), strjoin(srcs, ', '));
end

if isfinite(opt.Limit)
    infos = infos(1:min(opt.Limit, numel(infos)));
end

nRec = numel(infos);

fprintf('\n========================================\n');
fprintf('EEG pipeline: %d recording(s)\n', nRec);
fprintf('Subjects : %s\n', strjoin(unique([infos.subject]), ', '));
fprintf('Movements: %s\n', strjoin(unique([infos.movement]), ', '));
fprintf('========================================\n\n');

% =========================================================================
% Process each recording
% =========================================================================
% Note the 'meta' field: every branch below must produce a struct with the
% SAME fields, or the results(end+1) assignment fails on the first success.
results  = struct('info', {}, 'qc', {}, 'spec', {}, 'meta', {}, ...
                  'ok', {}, 'error', {});
allSpecs = struct([]);
specOf   = nan(nRec, 1);   % maps recording index -> index into allSpecs

for i = 1:nRec
    fprintf('[%d/%d] %s\n', i, nRec, infos(i).name);

    r = struct('info', infos(i), 'qc', [], 'spec', [], 'meta', [], ...
               'ok', false, 'error', '');

    try
        % --- import (dispatches on file extension) ---
        [EEG, meta] = import_recording(infos(i).file, cfg, opt.ImportOptions{:});
        EEG.setname = infos(i).name;
        r.meta = meta;

        % --- clean ---
        [EEG, QC] = preprocess_recording(EEG, P, cfg);
        QC.subject  = infos(i).subject;
        QC.movement = infos(i).movement;
        QC.timestamp = infos(i).timestamp;
        r.qc = QC;

        % --- save cleaned data ---
        if P.saveCleaned
            safe = matlab.lang.makeValidName(infos(i).name);
            pop_saveset(EEG, 'filename', [safe '.set'], ...
                             'filepath', cfg.procDir, 'savemode', 'onefile');
        end

        % --- spectrum ---
        S = compute_psd(EEG, P);
        S.setname = infos(i).name;
        r.spec = S;

        if isempty(allSpecs)
            allSpecs = S;
        else
            allSpecs(end+1) = S; %#ok<AGROW>
        end
        specOf(i) = numel(allSpecs);

        if P.saveResults
            safe = matlab.lang.makeValidName(infos(i).name);
            save(fullfile(cfg.resultDir, ['psd_' safe '.mat']), 'S', 'QC');
        end

        if opt.PlotEach
            % No title: the client's reference figure has none, and the
            % recording is already identified by the saved filename.
            h = plot_psd_stack(S, cfg, 'Save', P.saveFigures, 'Visible', opt.Visible);
            close(h);
        end

        r.ok = true;

    catch ME
        r.error = ME.message;
        fprintf('  FAILED: %s\n', ME.message);
    end

    results(end+1) = r; %#ok<AGROW>
    fprintf('\n');
end

% =========================================================================
% QC summary table
% =========================================================================
if P.saveResults
    write_qc_summary(results, cfg);
end

% =========================================================================
% Comparison figure: first, second-to-last, last
% =========================================================================
okIdx = find([results.ok]);

if opt.Compare && numel(okIdx) >= 1
    okInfos = [results(okIdx).info];
    [sel, labels] = pick_three(okInfos);

    specIdx = specOf(okIdx(sel));
    hCompare = compare_recordings(allSpecs(specIdx), cfg, ...
        'Titles', labels, 'Save', P.saveFigures, 'Visible', opt.Visible, ...
        'Tag', 'comparison_first_secondlast_last');
    if ~opt.Visible
        % Not shown on screen -- nothing left to look at it, so don't leave
        % it sitting in memory (it has already been saved to figures/ above).
        close(hCompare);
    end
elseif opt.Compare
    warning('run_pipeline:nothingToCompare', ...
        'No recordings processed successfully; no comparison figure made.');
end

% =========================================================================
% Final report
% =========================================================================
nOk   = sum([results.ok]);
nFail = nRec - nOk;

fprintf('========================================\n');
fprintf('Done: %d succeeded, %d failed\n', nOk, nFail);

if nFail > 0
    fprintf('\nFailures:\n');
    for i = find(~[results.ok])
        fprintf('  %-55s %s\n', results(i).info.name, results(i).error);
    end
end

warned = find(arrayfun(@(r) r.ok && ~isempty(r.qc) && ...
                            ~isempty(r.qc.warnings), results));
if ~isempty(warned)
    fprintf('\n%d recording(s) completed with warnings. First few:\n', numel(warned));
    for i = warned(1:min(5, numel(warned)))
        fprintf('  %s\n', results(i).info.name);
        for w = 1:numel(results(i).qc.warnings)
            fprintf('      - %s\n', results(i).qc.warnings{w});
        end
    end
    fprintf('  (full detail in results/qc_summary.csv)\n');
end

fprintf('========================================\n');
end


% =========================================================================
function write_qc_summary(results, cfg)
%WRITE_QC_SUMMARY  One row per recording, every decision the pipeline made.
ok = find([results.ok]);
if isempty(ok)
    warning('run_pipeline:noQC', 'Nothing succeeded; no QC summary written.');
    return
end

% Build each column complete, then assemble. Assigning into a table row by
% row makes MATLAB extend every other column with default values first, which
% produces a warning per row and, worse, leaves defaults behind if any field
% is ever missing.
n = numel(ok);
S = struct( ...
    'name',           strings(n,1), 'subject',        strings(n,1), ...
    'movement',       strings(n,1), 'timestamp',      NaT(n,1), ...
    'timeSource',     strings(n,1), ...
    'srate',          zeros(n,1),   'durationIn',     zeros(n,1), ...
    'durationOut',    zeros(n,1),   'badSegments',    zeros(n,1), ...
    'badChannels',    strings(n,1), 'interpolated',   strings(n,1), ...
    'reref',          strings(n,1), 'asrApplied',     false(n,1), ...
    'icaApplied',     false(n,1),   'icRemoved',      zeros(n,1), ...
    'nEpochs',        zeros(n,1),   'epochsRejected', zeros(n,1), ...
    'usable',         false(n,1),   'nWarnings',      zeros(n,1), ...
    'warnings',       strings(n,1));

for k = 1:n
    QC = results(ok(k)).qc;
    S.name(k)           = string(results(ok(k)).info.name);
    S.subject(k)        = QC.subject;
    S.movement(k)       = QC.movement;
    S.timestamp(k)      = QC.timestamp;
    S.timeSource(k)     = results(ok(k)).info.timeSource;
    S.srate(k)          = QC.srate;
    S.durationIn(k)     = QC.durationIn;
    S.durationOut(k)    = QC.durationOut;
    S.badSegments(k)    = QC.badSegments;
    S.badChannels(k)    = string(strjoin(QC.badChannels, ' '));
    S.interpolated(k)   = string(strjoin(QC.interpolated, ' '));
    S.reref(k)          = string(QC.reref);
    S.asrApplied(k)     = QC.asrApplied;
    S.icaApplied(k)     = QC.icaApplied;
    S.icRemoved(k)      = numel(QC.icRemoved);
    S.nEpochs(k)        = QC.nEpochs;
    S.epochsRejected(k) = QC.nEpochsRejected;
    S.usable(k)         = QC.usable;
    S.nWarnings(k)      = numel(QC.warnings);
    S.warnings(k)       = string(strjoin(QC.warnings, ' | '));
end

rows = struct2table(S);

if ~exist(cfg.resultDir, 'dir'); mkdir(cfg.resultDir); end
out = fullfile(cfg.resultDir, 'qc_summary.csv');
writetable(rows, out);
fprintf('Saved QC summary: %s\n\n', out);
end
