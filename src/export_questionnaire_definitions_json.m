function jsonPath = export_questionnaire_definitions_json(cfg)
%EXPORT_QUESTIONNAIRE_DEFINITIONS_JSON  Write questionnaire item text for the intake server.
%
%   jsonPath = export_questionnaire_definitions_json(cfg) writes
%   webintake/questionnaire_definitions.json from QUESTIONNAIRE_DEFINITIONS.
%
%   WHY THIS EXISTS
%   The waiting-room intake server (webintake/server.py) is a separate
%   Python process -- it cannot call QUESTIONNAIRE_DEFINITIONS.m directly.
%   Exporting the SAME struct this app uses, rather than hand-copying item
%   text into the Python side, is what guarantees the iPad form and the
%   MATLAB app can never show different wording for the same instrument.
%   Call this before starting the intake server (START_INTAKE_SERVER does).
%
%   See also QUESTIONNAIRE_DEFINITIONS, START_INTAKE_SERVER.

p = inputParser;
p.addRequired('cfg', @isstruct);
p.parse(cfg);

Q = questionnaire_definitions();

webintakeDir = fullfile(cfg.root, 'webintake');
if ~exist(webintakeDir, 'dir'); mkdir(webintakeDir); end
jsonPath = fullfile(webintakeDir, 'questionnaire_definitions.json');

fid = fopen(jsonPath, 'w');
if fid < 0
    error('export_questionnaire_definitions_json:cannotWrite', 'Could not write:\n  %s', jsonPath);
end
fprintf(fid, '%s', jsonencode(Q, 'PrettyPrint', true));
fclose(fid);

fprintf('Exported questionnaire definitions -> %s\n', jsonPath);
end
