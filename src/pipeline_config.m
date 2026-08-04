function P = pipeline_config(varargin)
%PIPELINE_CONFIG  Every setting for the preprocessing pipeline, in one place.
%
%   P = pipeline_config() returns the default settings.
%   P = pipeline_config('Name', Value, ...) overrides individual settings.
%
%   THE POINT OF THIS FILE
%   Nothing in the pipeline is ever changed by editing the pipeline itself.
%   You change behaviour here, or by passing an override at the call site.
%   That means the settings used for any result can be saved next to it, and
%   a result can always be reproduced exactly.
%
%   Example -- run with a 50 Hz notch instead of 60 Hz:
%       P = pipeline_config('notchFreq', 50);
%
%   Example -- skip ICA entirely and rely on ASR:
%       P = pipeline_config('doICA', false);
%
%   EVERY STAGE CAN BE SWITCHED OFF with its do* flag. The stages run in the
%   order laid out in the project brief; that order is not arbitrary and
%   should not be rearranged. Filtering before ICA, for instance, matters a
%   great deal -- ICA is badly behaved on data still containing slow drift.
%
%   See also PREPROCESS_RECORDING, RUN_PIPELINE.

% =========================================================================
% STAGE 1 -- Bad segment rejection
% =========================================================================
% Flags stretches where the signal is obviously not brain activity: the
% amplifier has railed, or an electrode has come loose. Done BEFORE
% filtering, because a filter smears one bad sample across its whole
% window, turning a short glitch into a long one.
P.doBadSegments   = true;
P.badSegAbsUV     = 300;   % |signal| above this (after removing the DC
                           % offset) is not EEG. Emotiv EPOC X sits around
                           % +/-100 uV in normal use; blinks reach ~200 uV.
P.badSegPadSec    = 0.1;   % also drop this much either side of a bad patch,
                           % because filter ringing spreads the damage

% =========================================================================
% STAGE 2 -- High-pass filter
% =========================================================================
% Removes slow drift: electrodes settling, sweat, gel drying, head movement.
% Raw Emotiv CSV values sit near +4300 uV -- that is a DC offset, not
% signal, and this stage is what removes it.
%
% WHY 1 Hz AND NOT 0.5 Hz
% The brief allows 0.5-1 Hz. We default to 1 Hz for two reasons. First, an
% FIR filter's length grows as the cutoff falls: at 128 Hz sampling, a 0.5 Hz
% cutoff needs roughly 845 filter coefficients, and many recordings in this
% dataset are only ~1200 samples long -- the filter would be comparable to
% the data. Second, ICA is well documented to separate components far more
% cleanly on 1 Hz high-passed data. If you need slow activity below 1 Hz,
% lower this and expect fewer usable recordings.
P.doHighpass      = true;
P.highpassHz      = 1.0;

% =========================================================================
% STAGE 3 -- Low-pass filter
% =========================================================================
% Removes high-frequency muscle activity and electrical noise above the band
% of interest. The brief asks for 40-45 Hz. 45 Hz keeps a little margin
% above the classic gamma edge while still sitting below 50/60 Hz mains.
P.doLowpass       = true;
P.lowpassHz       = 45;

% =========================================================================
% STAGE 4 -- Notch filter (optional)
% =========================================================================
% Removes mains hum. Hawaii and the rest of the USA run at 60 Hz; most of
% Europe, Asia and Africa run at 50 Hz.
%
% NOTE: at a 128 Hz sampling rate the highest measurable frequency (Nyquist)
% is 64 Hz. A 60 Hz notch is therefore right at the edge of what can be
% measured, and the 45 Hz low-pass above has already removed everything up
% there. The notch is left OFF by default for that reason, and only becomes
% genuinely useful if the headset is run in its 256 Hz mode.
P.doNotch         = false;
P.notchFreq       = 60;
P.notchWidth      = 2;     % Hz either side

% =========================================================================
% STAGE 5 -- Re-reference
% =========================================================================
% Every EEG voltage is a difference between two points. Emotiv references
% everything to its CMS/DRL electrodes behind the ear. Common average
% referencing re-expresses each channel relative to the average of all
% channels, which removes noise shared across the whole head.
%
% CAVEAT WORTH KNOWING: with only 14 electrodes covering the head unevenly,
% the "average" is a rough approximation of a true reference. It is standard
% practice for this headset, but it is an approximation.
P.doReref         = true;
P.rerefMethod     = 'average';

% =========================================================================
% STAGE 6 -- Artifact removal
% =========================================================================
% Two complementary tools:
%   ASR  removes large, brief, unusual events (movement, electrode pops) by
%        comparing against a clean reference section of the same recording.
%   ICA  splits the recording into independent sources, and ICLabel then
%        classifies each as brain, eye, muscle, heart, line noise or channel
%        noise. Sources classified as non-brain are subtracted.
%
% ICA HAS A HARD DATA REQUIREMENT. It estimates roughly nbchan^2 parameters,
% so it needs many times that many samples. The usual rule of thumb is
% k * nbchan^2 samples, with k of about 20-30. For 14 channels that is
% ~4,000-6,000 samples, i.e. 30-45 seconds at 128 Hz. Most recordings in the
% Harvard dataset are around 9 seconds. The pipeline therefore CHECKS this
% and skips ICA with a clear message rather than producing a confident,
% meaningless decomposition.
P.doASR           = true;
P.asrCutoff       = 20;    % std devs; lower = more aggressive. 20 is the
                           % EEGLAB default and is deliberately gentle.
P.asrMinSec       = 15;    % skip ASR below this duration -- it needs a clean
                           % reference section it cannot find in a few seconds

P.doICA           = true;
P.icaMinSamplesK  = 20;    % the k in k*nbchan^2; raise for stricter gating
P.icaExtended     = 1;     % extended infomax, handles sub-Gaussian sources
P.doICLabel       = true;
P.icLabelReject   = struct( ...   % probability above which a component is
    'Eye',        0.80, ...       % removed. Eye and muscle are set lower
    'Muscle',     0.80, ...       % than the rest because they are the
    'Heart',      0.90, ...       % artifacts this headset actually suffers
    'LineNoise',  0.90, ...       % from and ICLabel identifies them well.
    'ChannelNoise', 0.90);

% =========================================================================
% STAGE 7 -- Bad channel detection and interpolation
% =========================================================================
% A channel that is flat, wildly noisy, or uncorrelated with its neighbours
% is reconstructed from the surrounding electrodes using the channel
% locations. With only 14 widely spaced electrodes this is a real
% approximation, so the limit below is deliberately low: if more than this
% fraction of channels is bad, the recording is flagged rather than patched.
P.doInterp        = true;
P.badChanFlatSec  = 5;     % flat for this many seconds = dead

% MEASURED, NOT GUESSED. Across 6 recordings from this dataset (84 channel
% observations), after 1-45 Hz filtering, each channel's correlation with the
% average of the others was:
%     min 0.07 | 5th pct 0.28 | median 0.70 | 95th pct 0.93 | max 0.95
% A threshold of 0.60 would have condemned 35% of all channels, which is
% obviously wrong. 0.25 flags roughly the bottom 5%, a believable bad-channel
% rate. Note also that the temporal electrodes T7 and T8 sit lowest by nature
% (medians 0.49 and 0.51) because they are physically farthest from the rest
% of the montage -- a high threshold would punish them for their position
% rather than for any fault.
P.badChanCorr     = 0.25;
P.badChanMaxFrac  = 0.25;  % refuse to interpolate more than this fraction

% =========================================================================
% STAGE 8 -- Epoching and epoch rejection
% =========================================================================
% The continuous recording is cut into fixed-length pieces, and pieces still
% containing extreme values after all the above are dropped. Epoching also
% makes the spectral estimate better behaved.
P.doEpoch         = true;
P.epochSec        = 2;     % 2 s gives 0.5 Hz frequency resolution, and
                           % yields a usable number of epochs even from the
                           % ~9 s recordings in this dataset
P.epochOverlap    = 0.5;   % fraction
P.epochRejUV      = 150;   % drop epochs exceeding this after cleaning
P.epochMinKeep    = 3;     % fewer surviving epochs than this = unusable

% =========================================================================
% SPECTRAL ANALYSIS
% =========================================================================
% The brief asks for power spectra via Fourier transform, over 0-20 Hz, per
% channel. Welch's method is used by default: it is a Fourier transform
% applied to overlapping windows which are then averaged. A single FFT over
% a whole recording gives every frequency bin only 2 degrees of freedom no
% matter how long the recording is, so the spectrum stays visibly noisy;
% averaging windows fixes that. The method actually used is printed on every
% figure, so no reader has to guess.
P.psdMethod       = 'welch';   % 'welch' | 'fft'
P.psdBand         = [0 20];    % Hz, as specified in the brief
P.psdWindowSec    = 2;         % shortened from the usual 4 s because these
                               % recordings are short; see compute_psd.m,
                               % which adapts further if even this will not fit
P.psdOverlap      = 0.5;
P.psdScale        = 'db';      % 'db' (10*log10) | 'linear'

% =========================================================================
% OUTPUT
% =========================================================================
P.saveCleaned     = true;      % write .set/.fdt to data/processed
P.saveFigures     = true;      % write PNG + FIG to figures
P.saveResults     = true;      % write QC tables and spectra to results
P.figureFormat    = 'png';
P.figureDPI       = 150;
P.verbose         = true;

% =========================================================================
% Apply any overrides
% =========================================================================
if mod(numel(varargin), 2) ~= 0
    error('pipeline_config:badArgs', ...
          'Overrides must be Name/Value pairs.');
end
for i = 1:2:numel(varargin)
    name = varargin{i};
    if ~isfield(P, name)
        error('pipeline_config:unknownOption', ...
            ['"%s" is not a pipeline setting. Open pipeline_config.m to ' ...
             'see the full list.'], name);
    end
    P.(name) = varargin{i+1};
end

% =========================================================================
% Sanity checks -- fail here, loudly, rather than deep inside a stage
% =========================================================================
if P.doHighpass && P.doLowpass && P.highpassHz >= P.lowpassHz
    error('pipeline_config:badBand', ...
        'High-pass (%.2f Hz) must be below low-pass (%.2f Hz).', ...
        P.highpassHz, P.lowpassHz);
end
if P.highpassHz < 0.5 || P.highpassHz > 1
    warning('pipeline_config:highpassOutOfBrief', ...
        ['High-pass is %.2f Hz; the brief specifies 0.5-1 Hz. This is ' ...
         'allowed but should be justified in the write-up.'], P.highpassHz);
end
if P.lowpassHz < 40 || P.lowpassHz > 45
    warning('pipeline_config:lowpassOutOfBrief', ...
        ['Low-pass is %.2f Hz; the brief specifies 40-45 Hz.'], P.lowpassHz);
end
end
