function byInstrument = load_questionnaire_results(cfg, recordingName)
%LOAD_QUESTIONNAIRE_RESULTS  Read back whichever questionnaires a scan has.
%
%   byInstrument = load_questionnaire_results(cfg, recordingName) returns a
%   struct with one field per completed instrument id (e.g. .PHQ9, .GAD7),
%   each the SCORE_QUESTIONNAIRE result saved for that recording. Returns
%   an empty struct (no fields) if nothing has been saved for it yet --
%   not an error, since "no questionnaires filled out yet" is the normal
%   state for a scan that just finished processing.
%
%   See also SAVE_QUESTIONNAIRE_RESULT, SCORE_QUESTIONNAIRE.

p = inputParser;
p.addRequired('cfg',           @isstruct);
p.addRequired('recordingName', @(x) ischar(x) || isstring(x));
p.parse(cfg, recordingName);

byInstrument = struct();

matPath = fullfile(cfg.resultDir, 'questionnaires', ...
    [matlab.lang.makeValidName(char(recordingName)) '.mat']);
if exist(matPath, 'file') ~= 2
    return
end

loaded = load(matPath, 'byInstrument');
byInstrument = loaded.byInstrument;
end
