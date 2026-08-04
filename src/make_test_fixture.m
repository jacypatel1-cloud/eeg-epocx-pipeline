function outFile = make_test_fixture(cfg, varargin)
%MAKE_TEST_FIXTURE  Write a synthetic EmotivPRO-format CSV with known content.
%
%   outFile = make_test_fixture(cfg) writes a CSV to data/raw/ that mimics an
%   EmotivPRO EPOC X export, containing a signal whose spectrum is known
%   exactly in advance.
%
%   THIS IS A TEST FIXTURE, NOT DATA. It exists so the importer, QC and PSD
%   code can be checked against ground truth before any real recording is
%   available: if the pipeline reports a 10 Hz peak on a file built to have a
%   10 Hz peak, the frequency axis and scaling are right. Never analyse it as
%   though it were a recording, and never leave it in data/raw/ alongside
%   real files without the SYNTHETIC prefix it is given here.
%
%   Options:
%       'AlphaFreq'   peak frequency to inject, Hz.     Default 10
%       'AlphaAmp'    amplitude of that peak, uV.       Default 15
%       'DurationSec' recording length.                 Default 120
%       'SampleRate'  128 or 256.                       Default 128
%       'LineFreq'    mains frequency to inject, Hz.    Default 60
%       'BadChannel'  index forced flat, 0 for none.    Default 5 (T7)
%
%   The file includes, deliberately:
%     - 1/f background, so the spectrum looks broadly physiological
%     - an alpha peak on posterior channels only (O1 O2 P7 P8)
%     - blink transients on frontal channels (AF3 AF4 F7 F8)
%     - mains hum, to give the notch stage something to remove
%     - slow drift, to give the high-pass something to remove
%     - one flat channel, to give QC something to flag
%
%   See also IMPORT_EMOTIV_CSV, QC_REPORT, PLOT_PSD.

p = inputParser;
p.addRequired('cfg', @isstruct);
p.addParameter('AlphaFreq',   10,  @isscalar);
p.addParameter('AlphaAmp',    15,  @isscalar);
p.addParameter('DurationSec', 120, @isscalar);
p.addParameter('SampleRate',  128, @(x) any(x == [128 256]));
p.addParameter('LineFreq',    60,  @isscalar);
% T7 by default: deliberately NOT one of the posterior alpha channels, so a
% flat channel and a missing alpha peak stay independent failure signals.
p.addParameter('BadChannel',  5,   @isscalar);
p.parse(cfg, varargin{:});
opt = p.Results;

rng(42);   % fixed seed: the fixture must be identical on every machine

srate = opt.SampleRate;
n     = round(opt.DurationSec * srate);
t     = (0:n-1)' / srate;
nCh   = cfg.nChannels;
chans = cfg.channels;

data = zeros(n, nCh);

posterior = find(ismember(chans, {'O1','O2','P7','P8'}));
frontal   = find(ismember(chans, {'AF3','AF4','F7','F8'}));

for c = 1:nCh
    % 1/f background via filtered noise
    x = pinknoise_local(n) * 8;

    % Slow drift (electrode settling) -- target of the high-pass stage
    x = x + 20 * sin(2*pi*0.05*t + rand*2*pi) + 15 * sin(2*pi*0.11*t + rand*2*pi);

    % Mains hum -- target of the notch stage
    x = x + 3 * sin(2*pi*opt.LineFreq*t + rand*2*pi);

    % Alpha, posterior only. Narrowband rather than a pure tone so the peak
    % has realistic width.
    if ismember(c, posterior)
        alpha = filter_narrowband(randn(n,1), srate, opt.AlphaFreq - 1, opt.AlphaFreq + 1);
        alpha = alpha / std(alpha) * opt.AlphaAmp;
        x = x + alpha;
    end

    % Blinks, frontal only -- target of ICA/ICLabel
    if ismember(c, frontal)
        x = x + blink_train(n, srate, 0.3, 80);
    end

    data(:, c) = x;
end

% One dead channel for QC to catch
if opt.BadChannel >= 1 && opt.BadChannel <= nCh
    data(:, opt.BadChannel) = 0.01 * randn(n, 1);
end

% -------------------------------------------------------------------------
% Write in EmotivPRO layout: metadata line, then column header, then data
% -------------------------------------------------------------------------
if ~exist(cfg.rawDir, 'dir'); mkdir(cfg.rawDir); end
outFile = fullfile(cfg.rawDir, sprintf('SYNTHETIC_EPOCX_%dHz_alpha%d.csv', ...
                                       srate, round(opt.AlphaFreq)));

fid = fopen(outFile, 'w');
if fid < 0
    error('make_test_fixture:cannotWrite', 'Could not write:\n  %s', outFile);
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, 'title:SYNTHETIC TEST FIXTURE NOT A RECORDING,recordId:synthetic-0001,start timestamp:0,sampling rate:%d,channels:%d,headset:EPOCX\n', ...
        srate, nCh);

hdr = ['Timestamp,EEG.Counter,' ...
       strjoin(cellfun(@(c) ['EEG.' c], chans, 'UniformOutput', false), ',') ...
       ',' strjoin(cellfun(@(c) ['CQ.' c], chans, 'UniformOutput', false), ',')];
fprintf(fid, '%s\n', hdr);

counter = mod(0:n-1, 128);
cq      = repmat(4, 1, nCh);   % contact quality: 4 = good

fmt = ['%.6f,%d' repmat(',%.4f', 1, nCh) repmat(',%d', 1, nCh) '\n'];
for i = 1:n
    fprintf(fid, fmt, t(i), counter(i), data(i, :), cq);
end

clear cleanup;

fprintf('Wrote fixture: %s\n', outFile);
fprintf('  %d ch x %d samples (%.0f s) at %d Hz\n', nCh, n, opt.DurationSec, srate);
fprintf('  Ground truth: %.1f Hz alpha (%.0f uV) on %s; flat channel %s; %d Hz line\n', ...
        opt.AlphaFreq, opt.AlphaAmp, strjoin(chans(posterior), ' '), ...
        chans{opt.BadChannel}, opt.LineFreq);
end


% =========================================================================
function x = pinknoise_local(n)
%PINKNOISE_LOCAL  1/f noise by spectral shaping of white noise.
nfft = 2 ^ nextpow2(n);
X    = fft(randn(nfft, 1));
f    = (0:nfft-1)';
f(1) = 1;
f(f > nfft/2) = nfft - f(f > nfft/2);
f(f == 0) = 1;
X    = X ./ sqrt(f);
x    = real(ifft(X));
x    = x(1:n);
x    = x / std(x);
end

% =========================================================================
function y = filter_narrowband(x, srate, lo, hi)
%FILTER_NARROWBAND  Zero-phase band-pass, for building the alpha component.
[b, a] = butter(4, [lo hi] / (srate/2), 'bandpass');
y = filtfilt(b, a, x);
end

% =========================================================================
function y = blink_train(n, srate, ratePerSec, amp)
%BLINK_TRAIN  Sparse blink-shaped transients.
y = zeros(n, 1);
nBlinks = round(n / srate * ratePerSec);
w = round(0.3 * srate);
shape = amp * exp(-((1:w)' - w/2).^2 / (2 * (w/6)^2));
for k = 1:nBlinks
    i0 = randi([1, max(1, n - w)]);
    y(i0:i0+w-1) = y(i0:i0+w-1) + shape * (0.7 + 0.6*rand);
end
end
