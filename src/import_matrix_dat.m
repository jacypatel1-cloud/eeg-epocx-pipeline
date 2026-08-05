function [EEG, meta] = import_matrix_dat(file, cfg, varargin)
%IMPORT_MATRIX_DAT  Import a headerless numeric matrix (.dat) recording.
%
%   [EEG, meta] = import_matrix_dat(file, cfg, 'SampleRate', hz, ...
%                                    'ChannelOrder', names) reads a plain
%   text file of tab- or space-delimited numbers, one sample per row and one
%   channel per column, with NO header row and NO metadata of any kind.
%
%   'SampleRate' and 'ChannelOrder' are REQUIRED, not optional. Every other
%   importer in this project (EDF/BDF via pop_biosig, EmotivPRO CSV) reads
%   the sample rate and channel identity out of the file itself. This format
%   carries neither -- a bare grid of numbers cannot say what its own rows
%   or columns mean. Guessing here would repeat exactly the mistake
%   IMPORT_RECORDING's EDF path was rewritten to prevent (a channel silently
%   mislabelled, with no error and a plausible-looking result). So this
%   importer refuses to run without both being stated explicitly by the
%   caller, and it stamps the result with WHERE that information came from
%   (see meta.channelOrderSource) so nobody downstream mistakes an assumed
%   value for a documented one.
%
%   Options:
%       'SampleRate'    Hz. Required, no default.
%       'ChannelOrder'  cellstr/string, one name per column, in file order.
%                       Required, no default. Length must equal the file's
%                       column count.
%       'ChannelOrderSource'  free text recorded in meta, e.g. 'documented
%                       by data provider' or 'ASSUMED: canonical EPOC X
%                       order, not documented by source dataset'. Default:
%                       'not stated by caller'.
%
%   See also IMPORT_RECORDING, IMPORT_EMOTIV_CSV, IMPORT_BIOSIG.

p = inputParser;
p.addRequired('file', @(x) ischar(x) || isstring(x));
p.addRequired('cfg',  @isstruct);
p.addParameter('SampleRate',   [], @(x) isscalar(x) && x > 0);
p.addParameter('ChannelOrder', {}, @(x) iscellstr(x) || isstring(x));
p.addParameter('ChannelOrderSource', 'not stated by caller', ...
                @(x) ischar(x) || isstring(x));
p.parse(file, cfg, varargin{:});
opt = p.Results;

file = char(file);
if exist(file, 'file') ~= 2
    error('import_matrix_dat:fileNotFound', 'File not found:\n  %s', file);
end
if isempty(opt.SampleRate)
    error('import_matrix_dat:noSampleRate', ...
        ['This file format carries no sample rate of its own. Pass it ' ...
         'explicitly, e.g.:\n  import_matrix_dat(file, cfg, ''SampleRate'', 128, ...)\n' ...
         'File: %s'], file);
end
if isempty(opt.ChannelOrder)
    error('import_matrix_dat:noChannelOrder', ...
        ['This file format carries no channel names of its own. Pass the ' ...
         'column order explicitly, e.g.:\n  import_matrix_dat(file, cfg, ' ...
         '''ChannelOrder'', cfg.channels, ...)\nFile: %s'], file);
end

chanOrder = cellstr(opt.ChannelOrder(:));

% -------------------------------------------------------------------------
% Read the numeric body. No header line to skip; delimiter is whitespace
% (covers both tab- and space-separated variants without needing to know
% which one a given export used).
% -------------------------------------------------------------------------
M = readmatrix(file, 'FileType', 'text', 'Delimiter', '\t', ...
               'ConsecutiveDelimitersRule', 'join', 'OutputType', 'double');

if isempty(M)
    error('import_matrix_dat:noSamples', 'File parsed to zero rows:\n  %s', file);
end

if size(M, 2) ~= numel(chanOrder)
    error('import_matrix_dat:columnMismatch', ...
        ['File has %d column(s), but ChannelOrder lists %d name(s). This ' ...
         'file does not match the montage it is being imported as -- refusing ' ...
         'to guess which columns to drop or duplicate.\nFile: %s'], ...
        size(M, 2), numel(chanOrder), file);
end

if any(~isfinite(M(:)))
    nBad = sum(~isfinite(M(:)));
    warning('import_matrix_dat:nonFinite', ...
        '%d non-finite value(s) found and replaced by linear interpolation.', nBad);
    M = fill_nonfinite(M);
end

data = M';   % samples x channels -> channels x samples, as EEGLAB expects

% -------------------------------------------------------------------------
% Build the EEGLAB struct
% -------------------------------------------------------------------------
[~, baseName] = fileparts(file);

EEG = eeg_emptyset();
EEG.setname  = baseName;
EEG.filename = [baseName '.dat'];
EEG.filepath = fileparts(file);
EEG.nbchan   = size(data, 1);
EEG.trials   = 1;
EEG.pnts     = size(data, 2);
EEG.srate    = opt.SampleRate;
EEG.xmin     = 0;
EEG.xmax     = (EEG.pnts - 1) / EEG.srate;
EEG.data     = single(data);
EEG.ref      = 'unknown';

for k = 1:EEG.nbchan
    EEG.chanlocs(k).labels = char(chanOrder{k});
end

if exist(cfg.chanlocsFile, 'file') == 2
    EEG = pop_chanedit(EEG, 'lookup', cfg.chanlocsFile, ...
                            'load', {cfg.chanlocsFile, 'filetype', 'autodetect'});
    EEG.chaninfo.filename = cfg.chanlocsFile;
else
    error('import_matrix_dat:noChanlocs', ...
        'Channel location file not found:\n  %s', cfg.chanlocsFile);
end

EEG = eeg_checkset(EEG);

% -------------------------------------------------------------------------
% Provenance -- loud about the one thing this format cannot prove itself
% -------------------------------------------------------------------------
meta = struct();
meta.sourceFile         = file;
meta.sourceFormat       = 'DAT (headerless matrix)';
meta.importedOn         = datetime('now');
meta.srate               = opt.SampleRate;
meta.srateSource         = 'caller-supplied (file has no header)';
meta.nChannels           = EEG.nbchan;
meta.channelOrder        = chanOrder(:)';
meta.channelOrderSource  = char(opt.ChannelOrderSource);
meta.nSamples            = EEG.pnts;
meta.durationSec         = EEG.pnts / opt.SampleRate;

fprintf('Imported %s (DAT)\n', baseName);
fprintf('  %d channels x %d samples (%.1f s) at %.4g Hz [caller-supplied]\n', ...
        EEG.nbchan, EEG.pnts, meta.durationSec, opt.SampleRate);
if contains(lower(meta.channelOrderSource), 'assumed')
    fprintf('  WARNING: channel order is ASSUMED, not documented by the source file -- %s\n', ...
            meta.channelOrderSource);
end
end


% =========================================================================
function data = fill_nonfinite(data)
%FILL_NONFINITE  Linearly interpolate over NaN/Inf, per column (channel).
for c = 1:size(data, 2)
    x   = data(:, c);
    bad = ~isfinite(x);
    if ~any(bad) || all(bad)
        continue
    end
    idx    = (1:numel(x))';
    x(bad) = interp1(idx(~bad), x(~bad), idx(bad), 'linear', 'extrap');
    data(:, c) = x;
end
end
