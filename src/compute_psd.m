function S = compute_psd(EEG, P)
%COMPUTE_PSD  Power spectral density per channel, over the requested band.
%
%   S = compute_psd(EEG, P) returns a struct describing the spectrum of
%   every channel in EEG, using the settings in P (see PIPELINE_CONFIG).
%
%   RETURNED FIELDS
%       f          frequency axis, Hz, cropped to P.psdBand
%       psd        nFreq x nChannels, power density in uV^2/Hz
%       psdDb      the same in decibels, 10*log10(psd)
%       labels     channel names, in data order
%       method     human-readable description of how it was computed
%       srate      sampling rate the estimate was made at
%       nWindows   how many windows were averaged (1 for the plain FFT)
%
%   WHY THIS IS A SEPARATE FILE
%   Both the single-recording viewer and the three-recording comparison call
%   it. If the two computed their spectra independently they could drift
%   apart, and a comparison figure would then be comparing two different
%   analyses rather than two different recordings.
%
%   WELCH VERSUS A SINGLE FFT
%   Both are Fourier transforms, which is what the brief asks for. The
%   difference is only in how the result is averaged:
%
%     single FFT  one transform over the whole recording. Every frequency
%                 bin ends up with just 2 degrees of freedom no matter how
%                 long the recording is, so the spectrum looks spiky and
%                 two recordings of identical data can look quite different.
%
%     Welch       the recording is cut into overlapping windows, each is
%                 transformed, and the results are averaged. Frequency
%                 resolution is coarser, but the estimate is stable, which
%                 is what makes recordings comparable.
%
%   Welch is the default for that reason. The method used is returned in
%   S.method and printed on every figure, so it is never ambiguous.
%
%   HANDLING EPOCHED DATA
%   After stage 8 the data is 3-D (channels x samples x epochs). Each epoch
%   is transformed separately and the results averaged across epochs, which
%   is the correct thing to do -- epochs are not contiguous in time, so
%   joining them end to end would create artificial jumps.
%
%   See also PIPELINE_CONFIG, PLOT_PSD_STACK, COMPARE_RECORDINGS.

narginchk(2, 2);

srate = EEG.srate;
data  = double(EEG.data);          % channels x samples [x epochs]
nCh   = size(data, 1);
nPts  = size(data, 2);
nEp   = size(data, 3);

% -------------------------------------------------------------------------
% Choose a window length that actually fits.
% P.psdWindowSec is the preference; if an epoch is shorter than that, we use
% the whole epoch instead and say so, rather than erroring or silently
% producing something misleading.
% -------------------------------------------------------------------------
wantPts = round(P.psdWindowSec * srate);
winPts  = min(wantPts, nPts);
winPts  = 2 ^ floor(log2(winPts));          % power of two, for a clean FFT
winPts  = max(winPts, 16);                  % refuse to go absurdly small
adapted = winPts < wantPts;

nfft    = max(256, 2 ^ nextpow2(winPts));   % zero-pad so the curve is smooth
                                            % (this does NOT add resolution,
                                            % it only interpolates the plot)

switch lower(P.psdMethod)
    case 'welch'
        nOv = floor(winPts * P.psdOverlap);
        acc = [];
        for e = 1:nEp
            [pxx, f] = pwelch(data(:, :, e)', hann(winPts), nOv, nfft, srate);
            if isempty(acc); acc = zeros(size(pxx)); end
            acc = acc + pxx;
        end
        psd = acc / nEp;

        nWinPerEpoch = max(1, floor((nPts - nOv) / (winPts - nOv)));
        nWindows     = nWinPerEpoch * nEp;
        method = sprintf('Welch, %.2f s Hann windows, %.0f%% overlap, %d window(s) averaged', ...
                         winPts / srate, P.psdOverlap * 100, nWindows);

    case 'fft'
        % One transform per epoch across the full epoch length, averaged
        % over epochs. Scaled to a true density in uV^2/Hz.
        acc = [];
        w   = hann(nPts);
        for e = 1:nEp
            X = fft(data(:, :, e)' .* w, nfft, 1);
            nUnique = floor(nfft / 2) + 1;
            pxx = abs(X(1:nUnique, :)).^2 / (srate * sum(w.^2));
            pxx(2:end-1, :) = pxx(2:end-1, :) * 2;   % one-sided correction
            if isempty(acc); acc = zeros(size(pxx)); end
            acc = acc + pxx;
        end
        psd = acc / nEp;
        f   = (0:size(psd,1)-1)' * srate / nfft;
        nWindows = nEp;
        method   = sprintf('single FFT per epoch, %d-point, Hann window, %d epoch(s) averaged', ...
                           nfft, nEp);

    otherwise
        error('compute_psd:badMethod', ...
            'P.psdMethod must be ''welch'' or ''fft'', got ''%s''.', P.psdMethod);
end

% -------------------------------------------------------------------------
% Crop to the band of interest
% -------------------------------------------------------------------------
keep = f >= P.psdBand(1) & f <= P.psdBand(2);
if ~any(keep)
    error('compute_psd:emptyBand', ...
        'No frequency bins fall inside the requested band [%g %g] Hz.', ...
        P.psdBand(1), P.psdBand(2));
end

S = struct();
S.f        = f(keep);
S.psd      = psd(keep, :);
S.psdDb    = 10 * log10(max(S.psd, realmin));   % realmin guards log10(0)
% Forced to a COLUMN. chanlocs is a row struct array, so arrayfun returns a
% row, and flipud() on a row vector silently does nothing -- which reversed
% the channel labels on the comparison figure without any error.
S.labels   = arrayfun(@(c) string(c.labels), EEG.chanlocs(1:nCh))';
S.method   = method;
S.srate    = srate;
S.band     = P.psdBand;
S.nWindows = nWindows;
S.nEpochs  = nEp;
S.setname  = EEG.setname;
S.adapted  = adapted;

if adapted
    S.method = sprintf('%s [window shortened from %.1f s to fit the recording]', ...
                       S.method, P.psdWindowSec);
end
end
