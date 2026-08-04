function info = parse_recording_name(filename)
%PARSE_RECORDING_NAME  Pull movement, subject and time out of a filename.
%
%   info = parse_recording_name(filename) returns a struct describing one
%   recording, derived entirely from its name.
%
%   THE NAMES LOOK LIKE THIS
%       DOWN_EPOCX_126518_2021.03.24T14.43.47+05.30.md.mc.pm.fe.bp.csv
%       TWO BLINK_EPOCX_126518_2021.03.23T15.10.35+05.30.md.mc.pm.fe.bp.csv
%       |________| |___| |____| |_________________________| |____________|
%        movement  device subject      timestamp             stream suffix
%
%   The trailing ".md.mc.pm.fe.bp" lists the data streams EmotivPRO exported
%   into the file: motion, mental commands, performance metrics, facial
%   expressions and band power, alongside the EEG.
%
%   TWO THINGS THIS HAS TO COPE WITH
%   1. Spaces. "TWO BLINK" contains a space, so the movement label cannot be
%      found by splitting on underscores alone -- we anchor on "_EPOCX_".
%   2. Inconsistent labelling. The dataset contains both "TWO BLINK" and
%      "TWO BLINKS" for the same condition. These are normalised to a single
%      label so the two spellings do not appear as separate conditions.
%
%   RETURNED FIELDS
%       file        full path as given
%       name        filename without the stream suffix or extension
%       movement    normalised condition label, e.g. "TWO_BLINK"
%       subject     subject/session ID as a string, e.g. "126518"
%       timestamp   datetime of the recording, or NaT if nothing worked
%       timeSource  where the timestamp came from (see below)
%       valid       true if movement, subject and timestamp were all found
%
%   Sorting a list of these by .timestamp is what defines "first",
%   "second-to-last" and "last" for the comparison figure.
%
%   FINDING THE RECORDING TIME WHEN THE FILENAME DOES NOT COOPERATE
%   Files that came from EmotivPRO carry the time in their name. Files that
%   were renamed, or came from anywhere else, do not -- and without a time
%   the comparison figure would silently pick three arbitrary recordings.
%   So there is a fallback chain, and whichever step succeeded is reported
%   in .timeSource so it is never a mystery:
%
%       1. 'filename'   the timestamp in the name (most reliable)
%       2. 'file header' the "start timestamp" inside the CSV metadata line,
%                        which EmotivPRO writes as a Unix time
%       3. 'file date'  the file's own modification date (weakest -- copying
%                        or syncing a file can change this)
%       4. NaT          nothing worked; the recording sorts last and says so
%
%   See also RUN_PIPELINE, COMPARE_RECORDINGS.

[folder, base, ext] = fileparts(char(filename));

% Strip the EmotivPRO stream suffix chain (".md.mc.pm.fe.bp") so the name we
% report is readable. regexprep only removes it if it is actually there.
nameOnly = regexprep(base, '\.(md|mc|pm|fe|bp)+$', '');
nameOnly = regexprep(nameOnly, '(\.(md|mc|pm|fe|bp))+$', '');

info = struct( ...
    'file',      char(filename), ...
    'folder',    folder, ...
    'ext',       ext, ...
    'name',      nameOnly, ...
    'movement',  "", ...
    'subject',   "", ...
    'timestamp', NaT, ...
    'timeSource', "none", ...
    'valid',     false);

% ---------------------------------------------------------------------
% Split on the device marker. Everything before it is the movement label
% (which may contain spaces); everything after is subject + timestamp.
% ---------------------------------------------------------------------
tok = regexp(nameOnly, '^(.*?)_EPOCX_(\d+)_(.*)$', 'tokens', 'once');

if isempty(tok)
    % Not an EmotivPRO-style name. This is normal for recordings made
    % elsewhere or renamed by hand, so it is not an error -- but we still
    % need a recording time for the comparison figure to be meaningful.
    [info.timestamp, info.timeSource] = fallback_time(info.file);
    info.movement = "UNLABELLED";
    info.subject  = "UNKNOWN";
    info.valid    = ~isnat(info.timestamp);
    return
end

movementRaw = strtrim(tok{1});
info.subject = string(tok{2});
tsRaw        = tok{3};

% ---------------------------------------------------------------------
% Normalise the movement label: upper case, spaces to underscores, and
% collapse the BLINK/BLINKS plural so both spellings become one condition.
% ---------------------------------------------------------------------
mv = upper(strtrim(movementRaw));
mv = regexprep(mv, '\s+', '_');
mv = regexprep(mv, 'BLINKS$', 'BLINK');
info.movement = string(mv);

% ---------------------------------------------------------------------
% Timestamp: 2021.03.24T14.43.47+05.30
% Dots are used as separators in both the date and the time, and the UTC
% offset uses a dot too. We parse the local wall-clock part and keep the
% offset separately -- all recordings in this dataset share one offset, and
% ordering within a session is what matters.
% ---------------------------------------------------------------------
tsTok = regexp(tsRaw, ...
    '^(\d{4})\.(\d{2})\.(\d{2})T(\d{2})\.(\d{2})\.(\d{2})', 'tokens', 'once');

if ~isempty(tsTok)
    v = str2double(tsTok);
    try
        info.timestamp  = datetime(v(1), v(2), v(3), v(4), v(5), v(6));
        info.timeSource = "filename";
    catch
        info.timestamp = NaT;
    end
end

if isnat(info.timestamp)
    [info.timestamp, info.timeSource] = fallback_time(info.file);
end

info.valid = strlength(info.movement) > 0 && ...
             strlength(info.subject)  > 0 && ...
             ~isnat(info.timestamp);
end


% =========================================================================
function [ts, src] = fallback_time(file)
%FALLBACK_TIME  Recover a recording time when the filename has none.
%
%   Tries the file's own contents first, then the filesystem. Returns NaT
%   and "none" if neither works, rather than inventing a time -- an invented
%   ordering would be worse than an admitted absence.

ts  = NaT;
src = "none";

if exist(file, 'file') ~= 2
    return
end

% --- 1. The "start timestamp" EmotivPRO writes into the CSV metadata line.
% It is a Unix time (seconds since 1970-01-01 UTC) and is the most
% trustworthy source available once the filename is gone, because it comes
% from the recording software itself.
[~, ~, ext] = fileparts(file);
if strcmpi(ext, '.csv')
    try
        fid = fopen(file, 'r');
        if fid >= 0
            line1 = fgetl(fid);
            fclose(fid);
            if ischar(line1)
                tok = regexp(line1, 'start\s*timestamp\s*[:=]\s*([\d.]+)', ...
                             'tokens', 'once', 'ignorecase');
                if ~isempty(tok)
                    unixT = str2double(tok{1});
                    if isfinite(unixT) && unixT > 0
                        ts  = datetime(unixT, 'ConvertFrom', 'posixtime', ...
                                       'TimeZone', '');
                        src = "file header";
                        return
                    end
                end
            end
        end
    catch
        % fall through to the next option
    end
end

% --- 2. The filesystem's modification date. Weakest option: copying,
% syncing or restoring a file can rewrite it, so the ordering it gives may
% not be the order things were actually recorded. Reported as such.
d = dir(file);
if ~isempty(d)
    ts  = datetime(d.datenum, 'ConvertFrom', 'datenum');
    src = "file date";
end
end
