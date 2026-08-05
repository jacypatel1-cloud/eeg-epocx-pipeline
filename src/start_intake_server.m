function url = start_intake_server(cfg)
%START_INTAKE_SERVER  Launch the waiting-room questionnaire intake server.
%
%   url = start_intake_server(cfg) exports the current questionnaire
%   definitions (see EXPORT_QUESTIONNAIRE_DEFINITIONS_JSON, so the iPad form
%   can never drift from what this app itself uses), launches
%   webintake/server.py in its own console window, and returns the LAN URL
%   it is listening on once it reports ready.
%
%   THIS IS A DELIBERATE, NARROW, EXPLICITLY-AUTHORIZED EXCEPTION to this
%   project's local-only / no-network-calls rule -- see webintake/server.py's
%   own header and CLAUDE.md's "Waiting-room intake exception" section for
%   why. Nothing else in this project makes a network call; this is the one
%   documented exception, and only while a clinician has deliberately
%   started it.
%
%   REQUIRES PYTHON 3 ON THE SYSTEM PATH. This is the one piece of this
%   project that is not MATLAB, for the same reason the exception exists:
%   an iPad cannot run a MATLAB App Designer app, so something has to serve
%   it a web page. Errors with a clear message if python is not found,
%   rather than a confusing failure from STATUS below.
%
%   See also STOP_INTAKE_SERVER, EXPORT_QUESTIONNAIRE_DEFINITIONS_JSON,
%   IMPORT_PENDING_INTAKE_RESPONSES.

p = inputParser;
p.addRequired('cfg', @isstruct);
p.parse(cfg);

[pyStatus, ~] = system('python --version');
if pyStatus ~= 0
    error('start_intake_server:noPython', ...
        ['Python 3 was not found on the system PATH. The waiting-room intake ' ...
         'server needs it (see webintake/server.py); MATLAB itself does not.']);
end

export_questionnaire_definitions_json(cfg);

statusFile = fullfile(cfg.root, 'webintake', 'server_status.json');
if exist(statusFile, 'file') == 2
    delete(statusFile);   % don't read a stale one from a previous run below
end

serverScript = fullfile(cfg.root, 'webintake', 'server.py');
cmd = sprintf('start "EEG Intake Server" python "%s" "%s"', serverScript, cfg.root);
[st, out] = system(cmd);
if st ~= 0
    error('start_intake_server:launchFailed', 'Could not launch the intake server:\n%s', out);
end

% The server writes server_status.json within about a second of starting;
% poll briefly rather than assuming a fixed delay is enough or too long.
maxWaitSec = 8;
waited = 0;
while exist(statusFile, 'file') ~= 2 && waited < maxWaitSec
    pause(0.5);
    waited = waited + 0.5;
end

if exist(statusFile, 'file') ~= 2
    error('start_intake_server:notReady', ...
        ['The intake server window opened but did not report ready within %d s. ' ...
         'Check the "EEG Intake Server" console window for an error.'], maxWaitSec);
end

status = jsondecode(fileread(statusFile));
url = status.url;
fprintf('Waiting-room intake server ready: %s\n', url);
end
