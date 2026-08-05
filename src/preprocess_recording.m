function [EEG, QC] = preprocess_recording(EEG, P, cfg)
%PREPROCESS_RECORDING  Run the 8-stage cleaning pipeline on one recording.
%
%   [EEG, QC] = preprocess_recording(EEG, P, cfg) takes an imported EEGLAB
%   dataset, applies every enabled stage in P, and returns the cleaned data
%   together with a QC struct recording what was done.
%
%   STAGE ORDER (fixed by the project brief -- do not rearrange)
%       1  Inspect and reject bad segments
%       2  High-pass filter
%       3  Low-pass filter
%       4  Notch filter (optional)
%       5  Re-reference to common average
%       6  Artifact removal: ASR and/or ICA + ICLabel
%       7  Bad channel interpolation
%       8  Epoching and epoch rejection
%
%   The order matters. Bad segments go first because a filter smears a
%   single bad sample across its whole window. Filtering precedes ICA
%   because ICA separates poorly when slow drift is still present.
%
%   ONE DEPARTURE, DELIBERATE AND LOGGED
%   Bad channels are DETECTED before the common average reference (stage 5)
%   but INTERPOLATED at stage 7, where the brief places them. The reason is
%   that a dead channel dragged into the average contaminates every other
%   channel through the reference. Detecting early lets us leave bad
%   channels out of the average; interpolating late keeps the brief's order.
%   Both the detection point and the interpolation point are recorded in QC.
%
%   NOTHING IS SILENT. Every rejection, removal and skip is written into QC
%   with the reason and the threshold responsible, so any number in a figure
%   can be traced back to the decision that produced it.
%
%   See also PIPELINE_CONFIG, IMPORT_EMOTIV_CSV, RUN_PIPELINE.

narginchk(3, 3);

QC              = struct();
QC.setname      = EEG.setname;
QC.srate        = EEG.srate;
QC.nbchanIn     = EEG.nbchan;
QC.pntsIn       = EEG.pnts;
QC.durationIn   = EEG.pnts / EEG.srate;
QC.stages       = {};        % human-readable log, one line per action
QC.warnings     = {};
QC.settings     = P;         % the exact config that produced this result

log_stage(P.verbose, '--- %s (%.1f s, %d ch) ---', ...
          EEG.setname, QC.durationIn, EEG.nbchan);

% =========================================================================
% STAGE 1 -- Bad segment rejection
% =========================================================================
QC.badSegments      = 0;
QC.badSegmentsSec   = 0;

if P.doBadSegments
    % Work on a DC-removed copy purely for DETECTION. The raw Emotiv values
    % sit around +4300 uV, which is an offset rather than signal, and every
    % sample would exceed the threshold if we tested the raw values.
    probe = double(EEG.data) - mean(double(EEG.data), 2);

    if isempty(P.badSegAbsUV)
        badSegThr = robust_bound(abs(probe(:)), P.badSegAdaptK, ...
                                  P.badSegFloorUV, P.badSegCeilUV, 'upper');
        QC.badSegThreshold       = badSegThr;
        QC.badSegThresholdSource = sprintf( ...
            'adaptive: median + %.1fx robust-sigma of this recording, clamped to [%g %g] uV', ...
            P.badSegAdaptK, P.badSegFloorUV, P.badSegCeilUV);
    else
        badSegThr = P.badSegAbsUV;
        QC.badSegThreshold       = badSegThr;
        QC.badSegThresholdSource = 'fixed (config override)';
    end

    isBad = any(abs(probe) > badSegThr, 1);   % bad if ANY channel is bad

    if any(isBad)
        % Grow each bad patch outwards, because filter ringing spreads the
        % contamination beyond the samples that actually exceeded the limit.
        pad   = round(P.badSegPadSec * EEG.srate);
        isBad = movmax(double(isBad), 2*pad + 1) > 0;

        regions = mask_to_regions(isBad);

        % Refuse to proceed if there would be too little left to analyse.
        keptFrac = 1 - sum(isBad) / numel(isBad);
        if keptFrac < 0.5
            QC.warnings{end+1} = sprintf( ...
                ['Bad-segment rejection would remove %.0f%% of the ' ...
                 'recording; skipped. Inspect this file by hand.'], ...
                 (1 - keptFrac) * 100);
            log_stage(P.verbose, '  [1] bad segments: SKIPPED (%.0f%% would be lost)', ...
                      (1 - keptFrac) * 100);
        else
            EEG = pop_select(EEG, 'nopoint', regions);
            QC.badSegments    = size(regions, 1);
            QC.badSegmentsSec = sum(isBad) / QC.srate;
            log_stage(P.verbose, '  [1] bad segments: removed %d region(s), %.2f s (threshold %.1f uV, %s)', ...
                      QC.badSegments, QC.badSegmentsSec, badSegThr, QC.badSegThresholdSource);
        end
    else
        log_stage(P.verbose, '  [1] bad segments: none above %.1f uV (%s)', ...
                  badSegThr, QC.badSegThresholdSource);
    end
else
    log_stage(P.verbose, '  [1] bad segments: disabled');
end

% =========================================================================
% STAGE 2 -- High-pass filter
% =========================================================================
QC.highpassHz = NaN;

if P.doHighpass
    % An FIR filter needs enough samples to work with. pop_eegfiltnew picks
    % its own order from the cutoff; we check the recording can support it
    % rather than letting EEGLAB produce edge artifacts silently.
    minPnts = estimate_fir_length(P.highpassHz, EEG.srate);
    if EEG.pnts < 3 * minPnts
        QC.warnings{end+1} = sprintf( ...
            ['Recording is %d samples; a %.2f Hz high-pass needs roughly ' ...
             '%d for a clean result. Edges may be distorted.'], ...
             EEG.pnts, P.highpassHz, 3 * minPnts);
    end
    EEG = pop_eegfiltnew(EEG, 'locutoff', P.highpassHz);
    QC.highpassHz = P.highpassHz;
    log_stage(P.verbose, '  [2] high-pass: %.2f Hz', P.highpassHz);
else
    log_stage(P.verbose, '  [2] high-pass: disabled');
end

% =========================================================================
% STAGE 3 -- Low-pass filter
% =========================================================================
QC.lowpassHz = NaN;

if P.doLowpass
    if P.lowpassHz >= EEG.srate / 2
        error('preprocess_recording:lowpassAboveNyquist', ...
            ['Low-pass %.1f Hz is at or above Nyquist (%.1f Hz) for a ' ...
             '%g Hz recording. Nothing above Nyquist exists to remove.'], ...
             P.lowpassHz, EEG.srate/2, EEG.srate);
    end
    EEG = pop_eegfiltnew(EEG, 'hicutoff', P.lowpassHz);
    QC.lowpassHz = P.lowpassHz;
    log_stage(P.verbose, '  [3] low-pass: %.1f Hz', P.lowpassHz);
else
    log_stage(P.verbose, '  [3] low-pass: disabled');
end

% =========================================================================
% STAGE 4 -- Notch filter (optional)
% =========================================================================
QC.notchHz = NaN;

if P.doNotch
    if P.notchFreq >= EEG.srate / 2
        QC.warnings{end+1} = sprintf( ...
            ['Notch at %g Hz is above Nyquist (%.1f Hz); skipped. ' ...
             'Nothing at that frequency is present in the data.'], ...
             P.notchFreq, EEG.srate/2);
        log_stage(P.verbose, '  [4] notch: SKIPPED (above Nyquist)');
    elseif P.doLowpass && P.notchFreq > P.lowpassHz
        QC.warnings{end+1} = sprintf( ...
            ['Notch at %g Hz sits above the %g Hz low-pass, which has ' ...
             'already removed it; skipped as redundant.'], ...
             P.notchFreq, P.lowpassHz);
        log_stage(P.verbose, '  [4] notch: SKIPPED (already removed by low-pass)');
    else
        % revfilt = 1 turns the band-pass into a band-stop
        EEG = pop_eegfiltnew(EEG, ...
            'locutoff',  P.notchFreq - P.notchWidth, ...
            'hicutoff',  P.notchFreq + P.notchWidth, ...
            'revfilt',   1);
        QC.notchHz = P.notchFreq;
        log_stage(P.verbose, '  [4] notch: %g Hz +/- %g', P.notchFreq, P.notchWidth);
    end
else
    log_stage(P.verbose, '  [4] notch: disabled');
end

% =========================================================================
% Bad-channel DETECTION (interpolation happens at stage 7)
% =========================================================================
% Placed here, AFTER filtering and BEFORE the common average reference, for
% two reasons that both matter:
%
%   After filtering, because on unfiltered data the slow drift and the
%   +4300 uV DC offset dominate every statistic. A correlation computed on
%   raw Emotiv values mostly measures how similarly two electrodes drift,
%   not whether either is working.
%
%   Before re-referencing, because the common average is the average of all
%   channels. Include a dead channel in it and its badness is subtracted
%   into every other channel, which both corrupts the good data and hides
%   the bad channel by making everything look equally odd.
[badChans, badChanReasons, corrThr, corrThrSource] = detect_bad_channels(EEG, P);
QC.badChannels          = {EEG.chanlocs(badChans).labels};
QC.badChannelReasons    = badChanReasons;
QC.badChanCorrThreshold = corrThr;
QC.badChanCorrSource    = corrThrSource;

if ~isempty(badChans)
    log_stage(P.verbose, '  [*] bad channels detected: %s', ...
              strjoin(QC.badChannels, ', '));
else
    log_stage(P.verbose, '  [*] bad channels: none');
end

% =========================================================================
% STAGE 5 -- Re-reference to common average
% =========================================================================
QC.reref = 'none';

if P.doReref
    goodChans = setdiff(1:EEG.nbchan, badChans);
    if numel(goodChans) < 2
        QC.warnings{end+1} = 'Too few good channels to re-reference; skipped.';
        log_stage(P.verbose, '  [5] re-reference: SKIPPED (too few good channels)');
    else
        % 'exclude' keeps bad channels in the dataset but leaves them out of
        % the average, so one dead electrode cannot leak into all the others.
        EEG = pop_reref(EEG, [], 'exclude', badChans);
        QC.reref = sprintf('common average (excluding %d bad channel(s))', ...
                           numel(badChans));
        log_stage(P.verbose, '  [5] re-reference: %s', QC.reref);
    end
else
    log_stage(P.verbose, '  [5] re-reference: disabled');
end

% =========================================================================
% STAGE 6a -- ASR
% =========================================================================
QC.asrApplied   = false;
QC.asrCutoff    = NaN;
QC.asrPctChanged = NaN;

if P.doASR
    durSec = EEG.pnts / EEG.srate;
    if durSec < P.asrMinSec
        QC.warnings{end+1} = sprintf( ...
            ['ASR skipped: recording is %.1f s but ASR needs at least ' ...
             '%.0f s to find a clean reference section within it.'], ...
             durSec, P.asrMinSec);
        log_stage(P.verbose, '  [6a] ASR: SKIPPED (%.1f s < %.0f s minimum)', ...
                  durSec, P.asrMinSec);
    else
        try
            before = double(EEG.data);
            EEG    = clean_asr(EEG, P.asrCutoff);
            after  = double(EEG.data);
            QC.asrApplied    = true;
            QC.asrCutoff     = P.asrCutoff;
            % How much of the signal ASR actually altered -- a useful sanity
            % number. Near 0% means it did nothing; very high means it may
            % have been too aggressive.
            QC.asrPctChanged = mean(abs(after(:) - before(:)) > ...
                                    0.01 * std(before(:))) * 100;
            log_stage(P.verbose, '  [6a] ASR: cutoff %g, %.1f%% of samples altered', ...
                      P.asrCutoff, QC.asrPctChanged);
        catch ME
            QC.warnings{end+1} = sprintf('ASR failed: %s', ME.message);
            log_stage(P.verbose, '  [6a] ASR: FAILED (%s)', ME.message);
        end
    end
else
    log_stage(P.verbose, '  [6a] ASR: disabled');
end

% =========================================================================
% STAGE 6b -- ICA + ICLabel
% =========================================================================
QC.icaApplied     = false;
QC.icaSamples     = EEG.pnts;
QC.icaRequired    = P.icaMinSamplesK * EEG.nbchan^2;
QC.icRemoved      = [];
QC.icRemovedTypes = {};

if P.doICA
    % The data requirement, checked explicitly. ICA estimates an nbchan x
    % nbchan unmixing matrix; with too few samples the result is arbitrary
    % but looks perfectly convincing, which is the dangerous part.
    if EEG.pnts < QC.icaRequired
        QC.warnings{end+1} = sprintf( ...
            ['ICA skipped: %d samples available, ~%d needed for %d ' ...
             'channels (%dx nbchan^2). A decomposition from this little ' ...
             'data would not be trustworthy.'], ...
             EEG.pnts, QC.icaRequired, EEG.nbchan, P.icaMinSamplesK);
        log_stage(P.verbose, ...
            '  [6b] ICA: SKIPPED (%d samples, need ~%d)', ...
            EEG.pnts, QC.icaRequired);
    else
        try
            goodChans = setdiff(1:EEG.nbchan, badChans);
            EEG = pop_runica(EEG, 'icatype', 'runica', ...
                                  'extended', P.icaExtended, ...
                                  'chanind',  goodChans, ...
                                  'verbose',  'off');
            QC.icaApplied = true;

            if P.doICLabel
                EEG = iclabel(EEG);
                cls = EEG.etc.ic_classification.ICLabel.classifications;
                names = EEG.etc.ic_classification.ICLabel.classes;

                reject = false(size(cls, 1), 1);
                types  = repmat("", size(cls, 1), 1);

                fn = fieldnames(P.icLabelReject);
                for c = 1:numel(fn)
                    col = find(strcmpi(names, fn{c}), 1);
                    if isempty(col); continue; end
                    hit = cls(:, col) >= P.icLabelReject.(fn{c});
                    types(hit & ~reject) = string(fn{c});
                    reject = reject | hit;
                end

                if any(reject)
                    EEG = pop_subcomp(EEG, find(reject), 0);
                    QC.icRemoved      = find(reject)';
                    QC.icRemovedTypes = cellstr(types(reject));
                    log_stage(P.verbose, '  [6b] ICA: removed %d component(s): %s', ...
                              numel(QC.icRemoved), strjoin(QC.icRemovedTypes, ', '));
                else
                    log_stage(P.verbose, '  [6b] ICA: no components exceeded rejection thresholds');
                end
            else
                log_stage(P.verbose, '  [6b] ICA: decomposed, ICLabel disabled');
            end
        catch ME
            QC.warnings{end+1} = sprintf('ICA failed: %s', ME.message);
            log_stage(P.verbose, '  [6b] ICA: FAILED (%s)', ME.message);
        end
    end
else
    log_stage(P.verbose, '  [6b] ICA: disabled');
end

% =========================================================================
% STAGE 7 -- Bad channel interpolation
% =========================================================================
QC.interpolated = {};

if P.doInterp && ~isempty(badChans)
    fracBad = numel(badChans) / EEG.nbchan;
    if fracBad > P.badChanMaxFrac
        QC.warnings{end+1} = sprintf( ...
            ['%d of %d channels (%.0f%%) are bad, above the %.0f%% limit. ' ...
             'Not interpolated -- with this many electrodes missing there ' ...
             'is not enough surrounding signal to reconstruct from. Treat ' ...
             'this recording as unusable.'], ...
             numel(badChans), EEG.nbchan, fracBad*100, P.badChanMaxFrac*100);
        log_stage(P.verbose, '  [7] interpolation: REFUSED (%.0f%% of channels bad)', ...
                  fracBad * 100);
    else
        QC.interpolated = {EEG.chanlocs(badChans).labels};
        EEG = pop_interp(EEG, badChans, 'spherical');
        log_stage(P.verbose, '  [7] interpolation: %s', ...
                  strjoin(QC.interpolated, ', '));
    end
elseif P.doInterp
    log_stage(P.verbose, '  [7] interpolation: no bad channels');
else
    log_stage(P.verbose, '  [7] interpolation: disabled');
end

% =========================================================================
% STAGE 8 -- Epoching and epoch rejection
% =========================================================================
QC.nEpochs        = 0;
QC.nEpochsRejected = 0;
QC.usable         = true;

if P.doEpoch
    step = P.epochSec * (1 - P.epochOverlap);
    if EEG.pnts < P.epochSec * EEG.srate
        QC.warnings{end+1} = sprintf( ...
            'Recording (%.1f s) is shorter than one %.1f s epoch; not epoched.', ...
            EEG.pnts / EEG.srate, P.epochSec);
        QC.usable = false;
        log_stage(P.verbose, '  [8] epochs: SKIPPED (recording shorter than one epoch)');
    else
        % eeg_regepochs (via pop_epoch/pop_select) can throw on a recording
        % that stage 1 has fragmented into many short, discontinuous pieces
        % -- more likely now that bad-segment detection is adaptive and
        % catches genuine artifacts a loose fixed threshold used to miss.
        % That is stage 1 doing its job correctly; it is EEGLAB's fixed-
        % length re-epoching that has no graceful path for "too fragmented
        % to epoch," and errors instead of returning zero epochs. Caught
        % here, the same way ASR and ICA above are: the recording is marked
        % unusable with a clear reason, not lost to a cryptic internal
        % EEGLAB error that would also abort the whole batch.
        try
            EEG = eeg_regepochs(EEG, 'recurrence', step, ...
                                     'limits', [0 P.epochSec], ...
                                     'rmbase', NaN);
        catch ME
            QC.usable = false;
            QC.warnings{end+1} = sprintf( ...
                ['Epoching failed (%s). This usually means bad-segment removal ' ...
                 '(stage 1) left the recording too fragmented to cut into fixed ' ...
                 '%.1f s pieces. The cleaned continuous data was kept; no epochs ' ...
                 'or spectrum could be produced.'], ME.message, P.epochSec);
            log_stage(P.verbose, '  [8] epochs: FAILED (%s) -- recording marked unusable', ...
                      ME.message);
            EEG = eeg_checkset(EEG);
            QC.nbchanOut   = EEG.nbchan;
            QC.pntsOut     = EEG.pnts;
            QC.trialsOut   = EEG.trials;
            QC.durationOut = EEG.pnts * max(EEG.trials, 1) / EEG.srate;
            QC.completedOn = datetime('now');
            return
        end
        nBefore = EEG.trials;

        % Drop epochs still holding extreme values after all the cleaning.
        if isempty(P.epochRejUV)
            epochRejThr = robust_bound(abs(double(EEG.data(:))), P.epochRejK, ...
                                        P.epochRejFloorUV, P.epochRejCeilUV, 'upper');
            QC.epochRejThreshold       = epochRejThr;
            QC.epochRejThresholdSource = sprintf( ...
                'adaptive: median + %.1fx robust-sigma of this recording, clamped to [%g %g] uV', ...
                P.epochRejK, P.epochRejFloorUV, P.epochRejCeilUV);
        else
            epochRejThr = P.epochRejUV;
            QC.epochRejThreshold       = epochRejThr;
            QC.epochRejThresholdSource = 'fixed (config override)';
        end

        EEG = pop_eegthresh(EEG, 1, 1:EEG.nbchan, ...
                            -epochRejThr, epochRejThr, ...
                            EEG.xmin, EEG.xmax, 0, 0);
        rejIdx = find(EEG.reject.rejthresh);

        if numel(rejIdx) == nBefore
            % EVERY epoch failed. Rejecting them all would leave an empty
            % dataset, which downstream code cannot work with and which
            % crashes the batch. The recording is genuinely unusable, so we
            % say so and keep the epochs in place -- flagged, not deleted --
            % so a human can look at what went wrong.
            QC.usable = false;
            QC.warnings{end+1} = sprintf( ...
                ['All %d epochs exceeded +/-%.1f uV (%s). The recording is ' ...
                 'too noisy to use. Epochs were NOT removed, so the data can ' ...
                 'still be inspected, but no result from it should be ' ...
                 'trusted.'], nBefore, epochRejThr, QC.epochRejThresholdSource);
            log_stage(P.verbose, ...
                '  [8] epochs: ALL %d exceeded %.1f uV -- recording marked unusable', ...
                nBefore, epochRejThr);
        elseif ~isempty(rejIdx)
            EEG = pop_rejepoch(EEG, rejIdx, 0);
        end

        QC.nEpochs         = EEG.trials;
        QC.nEpochsRejected = nBefore - EEG.trials;

        if EEG.trials < P.epochMinKeep
            QC.usable = false;
            QC.warnings{end+1} = sprintf( ...
                ['Only %d epoch(s) survived (minimum %d). Not enough data ' ...
                 'for a stable spectrum.'], EEG.trials, P.epochMinKeep);
        end

        log_stage(P.verbose, '  [8] epochs: %d kept, %d rejected above %.1f uV (%s)', ...
                  QC.nEpochs, QC.nEpochsRejected, epochRejThr, QC.epochRejThresholdSource);
    end
else
    log_stage(P.verbose, '  [8] epochs: disabled (data left continuous)');
end

% =========================================================================
% Wrap up
% =========================================================================
EEG = eeg_checkset(EEG);

QC.nbchanOut   = EEG.nbchan;
QC.pntsOut     = EEG.pnts;
QC.trialsOut   = EEG.trials;
QC.durationOut = EEG.pnts * max(EEG.trials, 1) / EEG.srate;
QC.completedOn = datetime('now');

if ~isempty(QC.warnings)
    log_stage(P.verbose, '  %d warning(s) logged', numel(QC.warnings));
end
end


% =========================================================================
% Helpers
% =========================================================================
function log_stage(verbose, fmt, varargin)
%LOG_STAGE  Print progress only when the config asks for it.
if verbose
    fprintf([fmt '\n'], varargin{:});
end
end


function regions = mask_to_regions(mask)
%MASK_TO_REGIONS  Turn a logical mask into [start stop] sample pairs.
d      = diff([false, mask(:)', false]);
starts = find(d == 1);
stops  = find(d == -1) - 1;
regions = [starts(:), stops(:)];
end


function n = estimate_fir_length(cutoffHz, srate)
%ESTIMATE_FIR_LENGTH  Approximate pop_eegfiltnew's filter length.
%   EEGLAB picks a transition band of min(max(cutoff*0.25, 2), cutoff) Hz and
%   a Hamming-window FIR of order 3.3 / (transition / srate). We reproduce
%   that here only to warn when a recording is too short to support it.
tb = min(max(cutoffHz * 0.25, 2), cutoffHz);
n  = ceil(3.3 / (tb / srate));
end


function [badIdx, reasons, corrThr, corrThrSource] = detect_bad_channels(EEG, P)
%DETECT_BAD_CHANNELS  Flag flat, dead or uncorrelated electrodes.
%
%   Two independent tests, because they catch different failures:
%     flat  -- the electrode is not reporting at all
%     corr  -- the electrode reports, but shares no variance with the rest
%              of the head, meaning it is picking up something local (a
%              loose contact) rather than brain activity
%
%   Detection only. Nothing is changed here.
%
%   THE CORRELATION TEST IS TWO-PASS ON PURPOSE. Every channel's correlation
%   with the rest of the head is computed first; only once all of them are
%   known can an ADAPTIVE threshold be set relative to this recording's own
%   median (see PIPELINE_CONFIG). A single-pass version could not do that --
%   it would need the answer before it had finished computing the inputs.

data = double(EEG.data);
data = data - mean(data, 2);          % remove DC before judging amplitude
n    = EEG.nbchan;

flatSamples = round(P.badChanFlatSec * EEG.srate);

isFlatCh = false(n, 1);
flatSec  = zeros(n, 1);
corrs    = nan(n, 1);

for k = 1:n
    % --- flat test: longest run of near-zero change ---
    d       = abs(diff(data(k, :)));
    isFlat  = d < 1e-6;
    longest = longest_true_run(isFlat);
    isFlatCh(k) = longest >= flatSamples;
    flatSec(k)  = longest / EEG.srate;

    % --- correlation with the rest of the head ---
    if n > 2
        others   = mean(data(setdiff(1:n, k), :), 1);
        c        = corrcoef(data(k, :), others);
        corrs(k) = c(1, 2);
    end
end

if isempty(P.badChanCorr)
    corrThr = robust_bound(abs(corrs(~isnan(corrs))), P.badChanCorrK, ...
                            P.badChanCorrFloor, P.badChanCorrCeil, 'lower');
    corrThrSource = sprintf( ...
        'adaptive: median - %.1fx robust-sigma of this recording, clamped to [%.2f %.2f]', ...
        P.badChanCorrK, P.badChanCorrFloor, P.badChanCorrCeil);
else
    corrThr = P.badChanCorr;
    corrThrSource = 'fixed (config override)';
end

badIdx  = [];
reasons = {};

for k = 1:n
    why = {};

    if isFlatCh(k)
        why{end+1} = sprintf('flat for %.1f s', flatSec(k)); %#ok<AGROW>
    end
    if ~isnan(corrs(k)) && abs(corrs(k)) < corrThr
        why{end+1} = sprintf('corr %.2f below threshold %.2f (%s)', ...
                              corrs(k), corrThr, corrThrSource); %#ok<AGROW>
    end

    if ~isempty(why)
        badIdx(end+1)  = k;                          %#ok<AGROW>
        reasons{end+1} = strjoin(why, '; ');         %#ok<AGROW>
    end
end
end


function n = longest_true_run(v)
%LONGEST_TRUE_RUN  Length of the longest consecutive run of true.
if ~any(v); n = 0; return; end
d      = diff([false, v(:)', false]);
starts = find(d == 1);
stops  = find(d == -1);
n      = max(stops - starts);
end


function thr = robust_bound(x, k, floorVal, ceilVal, direction)
%ROBUST_BOUND  median +/- k robust-sigmas of THIS recording, clamped to a
%   physiologically sane range.
%
%   Every adaptive threshold in this file (bad segments, bad channels,
%   epoch rejection) goes through here. MEDIAN and MAD are used instead of
%   MEAN and SD deliberately: the values being screened for are exactly the
%   artifacts this function exists to flag, and a mean/SD computed on data
%   that still contains them gets dragged toward the artifacts themselves,
%   raising (or lowering) the bar precisely where it should not move. MAD
%   is scaled by 1.4826 so that k means the same thing a familiar "k-sigma"
%   cutoff would mean on artifact-free, normally distributed data.
%
%   floorVal/ceilVal are not part of the statistic -- they are a guardrail
%   so a session that happens to be unusually uniform (which would shrink
%   the robust sigma toward zero and make the threshold absurdly tight) or
%   unusually chaotic (which would inflate it past anything physiologically
%   plausible) cannot produce a threshold that no longer means anything.
%
%   direction: 'upper' for "flag above" (bad segments, epoch rejection),
%              'lower' for "flag below" (channel correlation).

x = x(:);
med = median(x, 'omitnan');
s   = 1.4826 * mad(x, 1);       % robust sigma; mad(...,1) = about the median
if s <= 0
    s = eps(max(abs(med), 1));  % degenerate (perfectly uniform) data
end

if strcmpi(direction, 'upper')
    thr = med + k * s;
else
    thr = med - k * s;
end

thr = min(max(thr, floorVal), ceilVal);
end
