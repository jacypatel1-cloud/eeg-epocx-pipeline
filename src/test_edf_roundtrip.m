function pass = test_edf_roundtrip(cfg)
%TEST_EDF_ROUNDTRIP  Prove the EDF import path is correct, then clean up.
%
%   pass = test_edf_roundtrip(cfg) writes a temporary EDF file with its
%   channels DELIBERATELY SHUFFLED, reads it back through IMPORT_RECORDING,
%   and checks that the channels come back in the correct EPOC X order with
%   the correct data attached to each name. The temporary file is deleted
%   afterwards whether the test passes or fails.
%
%   WHY THIS TEST EXISTS
%   The first version of the EDF importer used pop_select to reorder
%   channels. pop_select silently SORTS its channel list into ascending
%   order, so it cannot reorder at all: the data came back in file order
%   while canonical labels were attached on top of it. The result was a
%   completely scrambled montage -- AF4's signal labelled AF3 -- with no
%   error, no warning, and figures that looked entirely plausible.
%
%   Nothing but an end-to-end check with known data catches that class of
%   bug. Run this after any change to import_recording.m.
%
%   Usage:
%       cfg = setup_paths();
%       test_edf_roundtrip(cfg);
%
%   See also IMPORT_RECORDING, IMPORT_EMOTIV_CSV.

narginchk(1, 1);
pass = false;

% -------------------------------------------------------------------------
% Find any CSV recording to use as the source of truth
% -------------------------------------------------------------------------
src = dir(fullfile(cfg.rawDir, '*.csv'));
src = src(~contains({src.name}, '_intervalMarker', 'IgnoreCase', true));
if isempty(src)
    error('test_edf_roundtrip:noSource', ...
        'Need at least one CSV recording in data/raw to build the test file.');
end

srcFile = fullfile(src(1).folder, src(1).name);
fprintf('EDF round-trip test\n  source: %s\n', src(1).name);

evalc('EEGsrc = import_emotiv_csv(srcFile, cfg);');
truth = double(EEGsrc.data);

% -------------------------------------------------------------------------
% Build a shuffled copy. Indexing the data and chanlocs directly, NOT via
% pop_select, because pop_select would sort them back again.
% -------------------------------------------------------------------------
perm = [14 3 9 1 12 5 7 2 11 6 13 4 10 8];

E          = EEGsrc;
E.data     = EEGsrc.data(perm, :);
E.chanlocs = EEGsrc.chanlocs(perm);

% Prefix the labels too, mimicking recorders that write "EEG AF3".
for k = 1:numel(E.chanlocs)
    E.chanlocs(k).labels = ['EEG ' E.chanlocs(k).labels];
end
evalc('E = eeg_checkset(E);');

tmpFile = fullfile(tempdir, 'TEST_EPOCX_roundtrip.edf');
cleanup = onCleanup(@() delete_if_present(tmpFile));

evalc('pop_writeeeg(E, tmpFile, ''TYPE'', ''EDF'');');

% -------------------------------------------------------------------------
% Read it back through the real importer
% -------------------------------------------------------------------------
evalc('EEGedf = import_recording(tmpFile, cfg);');

% --- check 1: channel order --------------------------------------------
orderOk = isequal({EEGedf.chanlocs.labels}, cfg.channels);

% --- check 2: the right data is attached to each name -------------------
% EDF pads to whole seconds, so compare only the original sample count.
n = min(size(truth, 2), EEGedf.pnts);
r = zeros(numel(cfg.channels), 1);
d = zeros(numel(cfg.channels), 1);
for k = 1:numel(cfg.channels)
    a    = double(EEGedf.data(k, 1:n));
    b    = truth(k, 1:n);
    cc   = corrcoef(a, b);
    r(k) = cc(1, 2);
    d(k) = max(abs(a - b));
end

% EDF stores 16-bit integers, so a small quantisation error is expected and
% correct. Anything beyond this means real corruption, not rounding.
dataOk = min(r) > 0.9999 && max(d) < 1.0;

% --- check 3: sampling rate --------------------------------------------
rateOk = abs(EEGedf.srate - EEGsrc.srate) < 1e-6;

% --- check 4: locations -------------------------------------------------
locOk = sum(~cellfun(@isempty, {EEGedf.chanlocs.X})) == numel(cfg.channels);

% -------------------------------------------------------------------------
% Report
% -------------------------------------------------------------------------
fprintf('  channel order      : %s\n', tick(orderOk));
fprintf('  data alignment     : %s  (min r = %.6f, max diff = %.3f uV)\n', ...
        tick(dataOk), min(r), max(d));
fprintf('  sampling rate      : %s  (%g Hz)\n', tick(rateOk), EEGedf.srate);
fprintf('  channel locations  : %s\n', tick(locOk));

pass = orderOk && dataOk && rateOk && locOk;
fprintf('  RESULT             : %s\n', tick(pass));

if ~pass
    warning('test_edf_roundtrip:failed', ...
        'EDF round-trip test FAILED. Do not trust EDF imports until fixed.');
end
end


% =========================================================================
function s = tick(ok)
if ok; s = 'PASS'; else; s = 'FAIL'; end
end

function delete_if_present(f)
if exist(f, 'file') == 2
    delete(f);
end
end
