function [EEG, meta] = import_recording(file, cfg, varargin)
%IMPORT_RECORDING  Load an EEG recording, whatever format it arrives in.
%
%   [EEG, meta] = import_recording(file, cfg) inspects the file extension and
%   routes to the right importer:
%
%       .edf, .bdf   -> pop_biosig       (the project's primary format)
%       .csv         -> import_emotiv_csv
%       .dat         -> import_matrix_dat (headerless matrix; needs
%                        'SampleRate' and 'ChannelOrder' -- see that file)
%
%   This is the function the pipeline calls. Everything else goes through it,
%   so adding a new format later means changing one file.
%
%   WHY BOTH PATHS EXIST
%   EDF and BDF are the formats the brief specifies, and they are the right
%   choice: the header carries the sampling rate, channel labels and units in
%   a documented standard, so nothing has to be inferred. The public Emotiv
%   datasets, however, are distributed as EmotivPRO CSV exports, and the
%   headset's own software exports CSV by default. Supporting only one would
%   mean either being unable to run on real sample data, or being unable to
%   accept the format the brief asks for.
%
%   WHATEVER THE SOURCE, THE OUTPUT IS IDENTICAL: a 14-channel EEGLAB dataset
%   in EPOC X channel order with locations attached, and a meta struct
%   recording where every value came from.
%
%   See also IMPORT_EMOTIV_CSV, POP_BIOSIG, RUN_PIPELINE.

narginchk(2, Inf);

file = char(file);
if exist(file, 'file') ~= 2
    error('import_recording:fileNotFound', 'File not found:\n  %s', file);
end

[~, base, ext] = fileparts(file);

switch lower(ext)

    case {'.edf', '.bdf'}
        [EEG, meta] = import_biosig(file, cfg, base, ext);

    case '.csv'
        [EEG, meta] = import_emotiv_csv(file, cfg, varargin{:});

    case '.dat'
        [EEG, meta] = import_matrix_dat(file, cfg, varargin{:});

    otherwise
        error('import_recording:unsupportedFormat', ...
            ['Cannot import "%s" files. Supported: .edf, .bdf ' ...
             '(via pop_biosig), .csv (EmotivPRO export), .dat (headerless ' ...
             'matrix, needs SampleRate/ChannelOrder).\nFile: %s'], ...
             ext, file);
end
end


% =========================================================================
function [EEG, meta] = import_biosig(file, cfg, base, ext)
%IMPORT_BIOSIG  Read an EDF/BDF file and force it into EPOC X shape.

EEG = pop_biosig(file);

% ---------------------------------------------------------------------
% Select and ORDER the 14 EPOC X channels by name.
%
% This matters more than it looks. EDF files store channels in whatever
% order the recording software wrote them, and channel labels often carry
% prefixes ("EEG AF3", "EEG.AF3"). Taking channels 1-14 positionally would
% quietly produce a scrambled montage: every downstream step would run
% without error and every figure would be wrong.
% ---------------------------------------------------------------------
wanted = string(cfg.channels(:));
have   = arrayfun(@(c) string(c.labels), EEG.chanlocs(:));

% Strip common prefixes and whitespace before matching.
haveNorm = strtrim(regexprep(have, '^(EEG[\s\.\-_]*)', '', 'ignorecase'));

idx = nan(numel(wanted), 1);
for k = 1:numel(wanted)
    hit = find(strcmpi(haveNorm, wanted(k)), 1);
    if ~isempty(hit); idx(k) = hit; end
end

missing = wanted(isnan(idx));
if ~isempty(missing)
    error('import_recording:missingChannels', ...
        ['This %s file is missing %d of the 14 EPOC X channels: %s\n' ...
         'File: %s\nChannels present: %s'], ...
        upper(ext(2:end)), numel(missing), strjoin(missing, ', '), ...
        file, strjoin(have, ', '));
end

if numel(idx) ~= cfg.nChannels
    error('import_recording:channelCount', ...
        'Matched %d channels, expected %d. This is not an EPOC X recording.', ...
        numel(idx), cfg.nChannels);
end

% DO NOT use pop_select here. pop_select sorts its channel list into
% ascending order, so it cannot reorder -- it would return the channels in
% FILE order while we then attached canonical labels to them, producing a
% scrambled montage with no error and no warning. Verified: a deliberately
% shuffled EDF came back with AF4's data labelled AF3. Index directly.
EEG.data     = EEG.data(idx(:), :);
EEG.chanlocs = EEG.chanlocs(idx(:));
EEG.nbchan   = numel(idx);

% Re-label to the canonical names, so a file using "EEG AF3" and one using
% "AF3" produce datasets that are identical from here on.
for k = 1:numel(wanted)
    EEG.chanlocs(k).labels = char(wanted(k));
end

% ---------------------------------------------------------------------
% Sanity-check the sampling rate that came out of the header. Unlike CSV,
% EDF always carries one -- but it can still be wrong if the file was
% written badly, and a wrong rate rescales every frequency in the output.
% ---------------------------------------------------------------------
if ~any(abs(EEG.srate - [128 256]) < 1)
    warning('import_recording:unexpectedRate', ...
        ['Header reports %.4g Hz, which is neither 128 nor 256 Hz. The ' ...
         'EPOC X runs at one of those two. Verify before trusting any ' ...
         'spectra from this file.'], EEG.srate);
end

% ---------------------------------------------------------------------
% Channel locations
% ---------------------------------------------------------------------
if exist(cfg.chanlocsFile, 'file') ~= 2
    error('import_recording:noChanlocs', ...
        ['Channel location file not found:\n  %s\nSee docs/SETUP.md section 2.'], ...
        cfg.chanlocsFile);
end
EEG = pop_chanedit(EEG, 'lookup', cfg.chanlocsFile, ...
                        'load', {cfg.chanlocsFile, 'filetype', 'autodetect'});
EEG.chaninfo.filename = cfg.chanlocsFile;

EEG.setname = base;
EEG = eeg_checkset(EEG);

% ---------------------------------------------------------------------
% Provenance
% ---------------------------------------------------------------------
meta = struct();
meta.sourceFile   = file;
meta.sourceFormat = upper(ext(2:end));
meta.importedOn   = datetime('now');
meta.srate        = EEG.srate;
meta.srateSource  = sprintf('%s header', upper(ext(2:end)));
meta.nChannels    = EEG.nbchan;
meta.channelOrder = cellstr(wanted)';
meta.nSamples     = EEG.pnts;
meta.durationSec  = EEG.pnts / EEG.srate;
meta.reorderedFrom = cellstr(have)';

fprintf('Imported %s (%s)\n', base, meta.sourceFormat);
fprintf('  %d channels x %d samples (%.1f s) at %.4g Hz [%s]\n', ...
        EEG.nbchan, EEG.pnts, meta.durationSec, EEG.srate, meta.srateSource);
end
