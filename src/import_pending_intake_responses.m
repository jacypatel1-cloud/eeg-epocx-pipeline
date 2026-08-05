function nImported = import_pending_intake_responses(cfg, recordingName, visitPath)
%IMPORT_PENDING_INTAKE_RESPONSES  Pick up questionnaire answers submitted from the iPad.
%
%   nImported = import_pending_intake_responses(cfg, recordingName, visitPath)
%   looks in visitPath/questionnaire_intake/ for raw response files the
%   waiting-room intake server (webintake/server.py) wrote, scores each one
%   with SCORE_QUESTIONNAIRE -- the SAME engine used for a response entered
%   directly in the app -- persists it via SAVE_QUESTIONNAIRE_RESULT against
%   recordingName, and deletes the raw file once processed (so it is never
%   re-scored on a later visit). Returns how many were imported.
%
%   WHY THIS EXISTS SEPARATELY FROM THE INTAKE SERVER
%   The Python server's only job is capturing raw answers into a plain JSON
%   file -- it does not score anything or touch this project's results/
%   folder. This function is the other half: it is called from the app
%   (whenever a visit is opened) so a scan reviewed in the clinic always
%   reflects whatever the patient answered in the waiting room, without the
%   server needing to know anything about scoring, MATLAB, or this
%   project's file conventions beyond "write a JSON file here".
%
%   A malformed or unrecognized intake file is skipped with a warning, not
%   an error -- one bad file should not block picking up the other four
%   instruments' legitimate answers.
%
%   See also SCORE_QUESTIONNAIRE, SAVE_QUESTIONNAIRE_RESULT, QUESTIONNAIRE_DEFINITIONS.

p = inputParser;
p.addRequired('cfg',           @isstruct);
p.addRequired('recordingName', @(x) ischar(x) || isstring(x));
p.addRequired('visitPath',     @(x) ischar(x) || isstring(x));
p.parse(cfg, recordingName, visitPath);

nImported = 0;

intakeDir = fullfile(char(visitPath), 'questionnaire_intake');
if exist(intakeDir, 'dir') ~= 7
    return
end

d = dir(fullfile(intakeDir, '*.json'));
if isempty(d)
    return
end

Q = questionnaire_definitions();

for i = 1:numel(d)
    filePath = fullfile(d(i).folder, d(i).name);
    try
        raw = jsondecode(fileread(filePath));
        match = strcmp({Q.id}, raw.instrumentId);
        if ~any(match)
            warning('import_pending_intake_responses:unknownInstrument', ...
                'Skipping "%s": unrecognized instrument id "%s".', d(i).name, raw.instrumentId);
            continue
        end
        result = score_questionnaire(Q(match), raw.responses(:)');
        save_questionnaire_result(cfg, recordingName, result);
        delete(filePath);
        nImported = nImported + 1;
    catch ME
        warning('import_pending_intake_responses:badFile', ...
            'Skipping "%s": %s', d(i).name, ME.message);
    end
end

if nImported > 0
    fprintf('Imported %d waiting-room questionnaire response(s) for "%s"\n', nImported, recordingName);
end
end
