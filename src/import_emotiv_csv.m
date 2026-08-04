function [EEG, meta] = import_emotiv_csv(csvFile, cfg, varargin)
%IMPORT_EMOTIV_CSV  Import an EmotivPRO CSV export into an EEGLAB EEG struct.
%
%   [EEG, meta] = import_emotiv_csv(csvFile, cfg) reads an Emotiv EPOC X CSV
%   export and returns an EEGLAB-compatible EEG structure with channel
%   locations attached.
%
%   [EEG, meta] = import_emotiv_csv(..., 'Name', Value) accepts:
%       'SampleRate'  - override the sample rate (Hz). Only use this when the
%                       file genuinely carries no rate information; the
%                       default is to read it from the file and error if it
%                       cannot be found. Default: [] (read from file).
%       'Strict'      - if true (default), error when the channel count is
%                       not exactly cfg.nChannels. If false, warn instead.
%
%   WHY A CSV PATH EXISTS AT ALL
%   The project standard is EDF/BDF via pop_biosig, because those formats
%   carry the sample rate and channel metadata in a documented header. The
%   public EPOC X datasets are distributed as EmotivPRO CSV exports, so this
%   importer exists to consume them. It is deliberately defensive: anything
%   it cannot determine from the file, it refuses to guess.
%
%   EMOTIVPRO CSV LAYOUT
%   EmotivPRO v2+ writes a metadata line before the column header, e.g.
%       title:...,recordId:...,sampling rate:128,channels:...
%       Timestamp,EEG.Counter,EEG.AF3,EEG.F7,...,CQ.AF3,...
%   Older exports omit the metadata line and start at the column header.
%   Both are handled. Columns are matched by NAME, never by position, so a
%   change in export settings cannot silently misalign the montage.
%
%   Everything is local. No network calls.
%
%   See also SETUP_PATHS, POP_BIOSIG, QC_REPORT.

% -------------------------------------------------------------------------
% Arguments
% -------------------------------------------------------------------------
p = inputParser;
p.addRequired('csvFile',  @(x) ischar(x) || isstring(x));
p.addRequired('cfg',      @isstruct);
p.addParameter('SampleRate', [], @(x) isempty(x) || (isscalar(x) && x > 0));
p.addParameter('Strict',   true, @(x) islogical(x) && isscalar(x));
p.parse(csvFile, cfg, varargin{:});
opt = p.Results;

csvFile = char(csvFile);
if exist(csvFile, 'file') ~= 2
    error('import_emotiv_csv:fileNotFound', 'File not found:\n  %s', csvFile);
end

% -------------------------------------------------------------------------
% Read the first two lines to work out the file's shape
% -------------------------------------------------------------------------
fid = fopen(csvFile, 'r');
if fid < 0
    error('import_emotiv_csv:cannotOpen', 'Could not open:\n  %s', csvFile);
end
cleanup = onCleanup(@() fclose(fid));
line1 = fgetl(fid);
line2 = fgetl(fid);
clear cleanup;   %#ok<CLEAR>  % closes the file

if ~ischar(line1)
    error('import_emotiv_csv:emptyFile', 'File is empty:\n  %s', csvFile);
end

% Distinguish the metadata line from the column header by looking for actual
% channel columns, not by searching for the word "timestamp" -- EmotivPRO's
% metadata line contains "start timestamp:0", which makes that test fail.
hasMetaLine = ~is_header_line(line1, cfg.channels);

if hasMetaLine
    headerLine  = line2;
    headerRow   = 2;
    metaRawLine = line1;
else
    headerLine  = line1;
    headerRow   = 1;
    metaRawLine = '';
end

if ~ischar(headerLine)
    error('import_emotiv_csv:noHeader', ...
        'Could not find a column header row in:\n  %s', csvFile);
end

% -------------------------------------------------------------------------
% Sample rate. Order of preference: explicit override, then file metadata,
% then derived from the Timestamp column. Never a hardcoded constant --
% EPOC X runs at 128 Hz or 256 Hz depending on mode, and getting this wrong
% silently rescales every frequency in the output.
% -------------------------------------------------------------------------
srate       = [];
srateSource = '';

if ~isempty(opt.SampleRate)
    srate       = opt.SampleRate;
    srateSource = 'caller override';
elseif ~isempty(metaRawLine)
    % Real EmotivPRO files list a rate PER STREAM, e.g.
    %   sampling rate:eeg_128;mot_32;mc_8;pm_0.1;fe_32;pow_8
    % We want the EEG stream only. Motion (mot) and band power (pow) run at
    % different rates, and picking the wrong one would rescale the entire
    % frequency axis. Try the eeg_ form first, then the plain-number form
    % used by older exports and by our test fixture.
    tok = regexp(metaRawLine, 'eeg[_:=]\s*([\d.]+)', ...
                 'tokens', 'once', 'ignorecase');
    if ~isempty(tok)
        srate       = str2double(tok{1});
        srateSource = 'file metadata (eeg stream)';
    else
        tok = regexp(metaRawLine, 'sampling\s*rate\s*[:=]\s*([\d.]+)', ...
                     'tokens', 'once', 'ignorecase');
        if ~isempty(tok)
            srate       = str2double(tok{1});
            srateSource = 'file metadata (single rate)';
        end
    end
end

% -------------------------------------------------------------------------
% Read the numeric body
% -------------------------------------------------------------------------
% Split the header ourselves rather than relying on detectImportOptions.
% Two reasons: it treats the EmotivPRO metadata line as the header (making
% every channel come back as "VarN"), and assigning VariableNamesLine after
% detection does not re-read the names from the file. Doing it by hand is
% both shorter and stable across MATLAB releases.
varNames = strtrim(string(strsplit(headerLine, ',')));

M = readmatrix(csvFile, ...
    'NumHeaderLines', headerRow, ...
    'Delimiter', ',', ...
    'OutputType', 'double');

if isempty(M)
    error('import_emotiv_csv:noSamples', ...
        'Header parsed but no data rows found in:\n  %s', csvFile);
end

% Non-numeric columns (e.g. MarkerType in real exports) come back as NaN but
% keep their position, so name-to-column alignment still holds.
if size(M, 2) ~= numel(varNames)
    error('import_emotiv_csv:shapeMismatch', ...
        ['Header lists %d columns but the data rows have %d. The file is ' ...
         'malformed or uses a different delimiter.\nFile: %s'], ...
        numel(varNames), size(M, 2), csvFile);
end

% -------------------------------------------------------------------------
% Match EEG channels by name. Emotiv prefixes them "EEG.AF3"; some exports
% and third-party conversions drop the prefix. Accept either, but require
% an exact match on the electrode name itself so that, for example, "F7"
% can never be satisfied by "CQ.F7" (contact quality, not signal).
% -------------------------------------------------------------------------
wanted  = string(cfg.channels(:));
colIdx  = nan(numel(wanted), 1);

normalised = regexprep(varNames, '^EEG\.', '');
normalised = strtrim(normalised);

for k = 1:numel(wanted)
    hit = find(strcmpi(normalised, wanted(k)) & ...
               ~startsWith(varNames, "CQ.", 'IgnoreCase', true) & ...
               ~startsWith(varNames, "MOT.", 'IgnoreCase', true) & ...
               ~startsWith(varNames, "POW.", 'IgnoreCase', true), 1);
    if ~isempty(hit)
        colIdx(k) = hit;
    end
end

missing = wanted(isnan(colIdx));
if ~isempty(missing)
    error('import_emotiv_csv:missingChannels', ...
        ['Expected %d EPOC X channels, could not find %d of them: %s\n' ...
         'File: %s\nColumns present: %s'], ...
        numel(wanted), numel(missing), strjoin(missing, ', '), ...
        csvFile, strjoin(varNames, ', '));
end

if numel(colIdx) ~= cfg.nChannels
    msg = sprintf(['Channel count mismatch: matched %d, expected %d. ' ...
                   'This does not look like an EPOC X recording.'], ...
                   numel(colIdx), cfg.nChannels);
    if opt.Strict
        error('import_emotiv_csv:channelCount', '%s', msg);
    else
        warning('import_emotiv_csv:channelCount', '%s', msg);
    end
end

data = double(M(:, colIdx))';   % channels x samples, as EEGLAB expects

if any(~isfinite(data(:)))
    nBad = sum(~isfinite(data(:)));
    warning('import_emotiv_csv:nonFinite', ...
        ['%d non-finite sample(s) found and replaced by linear ' ...
         'interpolation. Check the source file.'], nBad);
    data = fill_nonfinite(data);
end

% -------------------------------------------------------------------------
% Fall back to deriving the sample rate from timestamps
% -------------------------------------------------------------------------
if isempty(srate)
    tsCol = find(strcmpi(varNames, 'Timestamp') | ...
                 strcmpi(varNames, 'EEG.Timestamp'), 1);
    if ~isempty(tsCol)
        ts = double(M(:, tsCol));
        dt = median(diff(ts), 'omitnan');
        if isfinite(dt) && dt > 0
            srate       = 1 / dt;
            srateSource = 'derived from Timestamp column';
        end
    end
end

if isempty(srate) || ~isfinite(srate) || srate <= 0
    error('import_emotiv_csv:noSampleRate', ...
        ['Could not determine the sampling rate from:\n  %s\n' ...
         'No metadata line and no usable Timestamp column. Pass it ' ...
         'explicitly with ''SampleRate'' only if you know it for certain -- ' ...
         'guessing here corrupts every frequency in the output.'], csvFile);
end

% EPOC X only runs at 128 or 256 Hz. Anything else means the file is not
% what it claims to be, or the timestamps are in the wrong units.
if ~any(abs(srate - [128 256]) < 1)
    warning('import_emotiv_csv:unexpectedRate', ...
        ['Sampling rate resolved to %.3f Hz (%s), which is neither 128 ' ...
         'nor 256 Hz. Verify the source before trusting any spectra.'], ...
        srate, srateSource);
end

% -------------------------------------------------------------------------
% Build the EEGLAB struct
% -------------------------------------------------------------------------
[~, baseName] = fileparts(csvFile);

EEG = eeg_emptyset();
EEG.setname  = baseName;
EEG.filename = [baseName '.csv'];
EEG.filepath = fileparts(csvFile);
EEG.nbchan   = size(data, 1);
EEG.trials   = 1;
EEG.pnts     = size(data, 2);
EEG.srate    = srate;
EEG.xmin     = 0;
EEG.xmax     = (EEG.pnts - 1) / EEG.srate;
EEG.data     = single(data);
EEG.ref      = 'unknown';   % Emotiv exports are referenced to CMS/DRL

for k = 1:EEG.nbchan
    EEG.chanlocs(k).labels = char(wanted(k));
end

% Channel locations. Without these, ICA topographies and interpolation
% cannot work, so a missing .ced is a hard failure rather than a warning.
if exist(cfg.chanlocsFile, 'file') == 2
    EEG = pop_chanedit(EEG, 'lookup', cfg.chanlocsFile, ...
                            'load', {cfg.chanlocsFile, 'filetype', 'autodetect'});
    EEG.chaninfo.filename = cfg.chanlocsFile;
else
    error('import_emotiv_csv:noChanlocs', ...
        ['Channel location file not found:\n  %s\n' ...
         'See docs/SETUP.md section 2 for the download link.'], cfg.chanlocsFile);
end

EEG = eeg_checkset(EEG);

% -------------------------------------------------------------------------
% Provenance. Logged so a clinician can defend where every number came from.
% -------------------------------------------------------------------------
meta = struct();
meta.sourceFile     = csvFile;
meta.importedOn     = datetime('now');
meta.srate          = srate;
meta.srateSource    = srateSource;
meta.nChannels      = EEG.nbchan;
meta.channelOrder   = cellstr(wanted)';
meta.nSamples       = EEG.pnts;
meta.durationSec    = EEG.pnts / srate;
meta.hasMetaLine    = hasMetaLine;
meta.rawMetaLine    = metaRawLine;
meta.columnsInFile  = cellstr(varNames);

fprintf('Imported %s\n', baseName);
fprintf('  %d channels x %d samples (%.1f s) at %.4g Hz [%s]\n', ...
        EEG.nbchan, EEG.pnts, meta.durationSec, srate, srateSource);
end


% =========================================================================
function tf = is_header_line(line, channels)
%IS_HEADER_LINE  True if this CSV line names EEG channel columns.
%   A column header contains fields that are either "EEG.<chan>" or a bare
%   electrode name. A metadata line contains neither.
if ~ischar(line) && ~isstring(line)
    tf = false;
    return
end
fields = strtrim(string(strsplit(char(line), ',')));
bare   = regexprep(fields, '^EEG\.', '');
tf = any(ismember(lower(bare), lower(string(channels(:)))));
end

% =========================================================================
function data = fill_nonfinite(data)
%FILL_NONFINITE  Linearly interpolate over NaN/Inf, per channel.
for c = 1:size(data, 1)
    x   = data(c, :);
    bad = ~isfinite(x);
    if ~any(bad) || all(bad)
        continue
    end
    idx     = 1:numel(x);
    x(bad)  = interp1(idx(~bad), x(~bad), idx(bad), 'linear', 'extrap');
    data(c, :) = x;
end
end
