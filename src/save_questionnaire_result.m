function save_questionnaire_result(cfg, recordingName, result)
%SAVE_QUESTIONNAIRE_RESULT  Persist one scored questionnaire against a scan.
%
%   save_questionnaire_result(cfg, recordingName, result) stores RESULT
%   (from SCORE_QUESTIONNAIRE) into
%   results/questionnaires/<safe recordingName>.mat, alongside whichever
%   other instruments have already been completed for that same recording
%   -- one file per SCAN holding every questionnaire filled out for it, not
%   one file per questionnaire, since "with each scan" is the unit that
%   matters here.
%
%   Also rewrites results/questionnaire_summary.csv, one row per recording
%   that has any questionnaire data, mirroring how RUN_PIPELINE already
%   rolls QC up into qc_summary.csv.
%
%   See also SCORE_QUESTIONNAIRE, LOAD_QUESTIONNAIRE_RESULTS, QUESTIONNAIRE_DEFINITIONS.

p = inputParser;
p.addRequired('cfg',           @isstruct);
p.addRequired('recordingName', @(x) ischar(x) || isstring(x));
p.addRequired('result',        @isstruct);
p.parse(cfg, recordingName, result);

qDir = fullfile(cfg.resultDir, 'questionnaires');
if ~exist(qDir, 'dir'); mkdir(qDir); end

safeName = matlab.lang.makeValidName(char(recordingName));
matPath  = fullfile(qDir, [safeName '.mat']);

if exist(matPath, 'file') == 2
    loaded = load(matPath, 'byInstrument');
    byInstrument = loaded.byInstrument;
else
    byInstrument = struct();
end
byInstrument.(result.id) = result;

save(matPath, 'byInstrument');
fprintf('Saved %s questionnaire for "%s"\n', result.id, recordingName);

rewrite_summary(cfg, qDir);
end


% =========================================================================
function rewrite_summary(cfg, qDir)
%REWRITE_SUMMARY  One row per recording with any saved questionnaire data.
d = dir(fullfile(qDir, '*.mat'));
if isempty(d)
    return
end

ids = {'PHQ9', 'GAD7', 'ISI', 'MMQ9', 'CBS'};

n = numel(d);
S = struct('recording', strings(n,1));
for k = 1:numel(ids)
    S.(sprintf('%s_score', ids{k})) = nan(n,1);
    S.(sprintf('%s_band',  ids{k})) = strings(n,1);
end
S.selfHarmFlag = false(n,1);

for i = 1:n
    loaded = load(fullfile(d(i).folder, d(i).name), 'byInstrument');
    byInstrument = loaded.byInstrument;
    [~, S.recording(i)] = fileparts(d(i).name);

    for k = 1:numel(ids)
        id = ids{k};
        if isfield(byInstrument, id)
            S.(sprintf('%s_score', id))(i) = byInstrument.(id).total;
            S.(sprintf('%s_band',  id))(i) = string(byInstrument.(id).band);
            if strcmp(id, 'PHQ9') && byInstrument.(id).flagged
                S.selfHarmFlag(i) = true;
            end
        end
    end
end

rows = struct2table(S);
out  = fullfile(cfg.resultDir, 'questionnaire_summary.csv');
writetable(rows, out);
end
