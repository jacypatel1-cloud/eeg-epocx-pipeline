function stop_intake_server()
%STOP_INTAKE_SERVER  Close the waiting-room questionnaire intake server.
%
%   stop_intake_server() closes the "EEG Intake Server" console window
%   START_INTAKE_SERVER opened, by window title (Windows' TASKKILL, /FI
%   WINDOWTITLE) rather than tracking a PID -- simpler, and just as
%   reliable since that title is unique to this one purpose. Safe to call
%   even if the server isn't running (taskkill's "not found" is not
%   treated as an error here).
%
%   See also START_INTAKE_SERVER.

[st, out] = system('taskkill /FI "WINDOWTITLE eq EEG Intake Server*" /T /F');
if st ~= 0 && ~contains(out, 'not found', 'IgnoreCase', true)
    warning('stop_intake_server:taskkillFailed', 'Could not confirm the server stopped:\n%s', out);
else
    fprintf('Waiting-room intake server stopped.\n');
end
end
