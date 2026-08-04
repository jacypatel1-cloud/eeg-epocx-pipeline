function qc = qc_report(EEG, cfg, varargin)
%QC_REPORT  Per-channel quality checks on a raw or cleaned EEG recording.
%
%   qc = qc_report(EEG, cfg) computes per-channel diagnostics and prints a
%   readable table. Nothing is modified or rejected here -- this stage only
%   describes the data, so that any later rejection can be justified against
%   numbers that were recorded before the rejection happened.
%
%   qc = qc_report(..., 'Save', true) also writes results/<setname>_qc.csv
%   and results/<setname>_qc.mat.
%
%   FIELDS RETURNED (one row per channel)
%       label        electrode name
%       meanuV       mean amplitude -- large values indicate DC offset
%       sduV         standard deviation -- the main dispersion measure
%       minuV/maxuV  extremes, for spotting rail hits
%       ptpuV        peak-to-peak range
%       pctSaturated fraction of samples at or beyond +/- SaturationLimit
%       pctFlat      fraction of samples in a run of near-zero difference
%       kurt         kurtosis -- high values flag spiky, artifact-heavy channels
%       lineRatio    power at LineFreq relative to neighbouring bins
%       corrWithMean correlation with the mean of all other channels; a
%                    channel near zero here is probably disconnected
%
%   WHY THESE THRESHOLDS
%   The defaults below are screening aids, not clinical criteria. They are
%   deliberately loose: this function flags channels for a human to look at,
%   it does not decide anything. Every threshold is a named parameter so the
%   value used can be reported alongside the result.
%
%   See also IMPORT_EMOTIV_CSV, PLOT_PSD.

p = inputParser;
p.addRequired('EEG',  @isstruct);
p.addRequired('cfg',  @isstruct);
p.addParameter('SaturationLimit', 500,  @isscalar);   % uV, EPOC X rails well inside this
p.addParameter('FlatTol',         0.5,  @isscalar);   % uV, sample-to-sample change below this counts as flat
p.addParameter('LineFreq',        60,   @isscalar);   % Hawaii is 60 Hz
p.addParameter('Save',            false, @islogical);
p.parse(EEG, cfg, varargin{:});
opt = p.Results;

data = double(EEG.data);
n    = EEG.nbchan;

labels = strings(n, 1);
for k = 1:n
    labels(k) = string(EEG.chanlocs(k).labels);
end

meanuV = mean(data, 2);
sduV   = std(data, 0, 2);
minuV  = min(data, [], 2);
maxuV  = max(data, [], 2);
ptpuV  = maxuV - minuV;
kurt   = kurtosis(data, 1, 2);

pctSaturated = mean(abs(data) >= opt.SaturationLimit, 2) * 100;
pctFlat      = mean([false(n,1), abs(diff(data, 1, 2)) < opt.FlatTol], 2) * 100;

% Line noise: power in a narrow band at LineFreq against the surrounding
% background. Only meaningful if the sample rate reaches that high.
lineRatio = nan(n, 1);
if EEG.srate > 2 * opt.LineFreq
    nfft = 2 ^ nextpow2(min(EEG.pnts, round(EEG.srate * 4)));
    [pxx, f] = pwelch(data', hann(nfft), nfft/2, nfft, EEG.srate);
    inBand   = abs(f - opt.LineFreq) <= 1;
    nearBand = (abs(f - opt.LineFreq) > 2) & (abs(f - opt.LineFreq) <= 6);
    if any(inBand) && any(nearBand)
        lineRatio = (mean(pxx(inBand, :), 1) ./ mean(pxx(nearBand, :), 1))';
    end
end

% Correlation against the other channels. A well-connected electrode shares
% a good deal of variance with its neighbours; a floating one does not.
corrWithMean = nan(n, 1);
if n > 1
    for k = 1:n
        others = mean(data(setdiff(1:n, k), :), 1);
        c = corrcoef(data(k, :), others);
        corrWithMean(k) = c(1, 2);
    end
end

qc = table(labels, meanuV, sduV, minuV, maxuV, ptpuV, ...
           pctSaturated, pctFlat, kurt, lineRatio, corrWithMean, ...
           'VariableNames', {'label','meanuV','sduV','minuV','maxuV','ptpuV', ...
                             'pctSaturated','pctFlat','kurt','lineRatio','corrWithMean'});

% -------------------------------------------------------------------------
% Report
% -------------------------------------------------------------------------
fprintf('\n=== QC: %s ===\n', EEG.setname);
fprintf('%d channels, %d samples, %.1f s at %g Hz\n', ...
        EEG.nbchan, EEG.pnts, EEG.pnts / EEG.srate, EEG.srate);
fprintf('Thresholds: saturation >= %g uV, flat < %g uV/sample, line %g Hz\n\n', ...
        opt.SaturationLimit, opt.FlatTol, opt.LineFreq);
disp(qc);

suspect = strings(0,1);
for k = 1:n
    reasons = strings(0,1);
    if pctFlat(k)      > 20,  reasons(end+1) = sprintf('flat %.0f%%', pctFlat(k));      end %#ok<AGROW>
    if pctSaturated(k) > 1,   reasons(end+1) = sprintf('saturated %.1f%%', pctSaturated(k)); end %#ok<AGROW>
    if sduV(k)         < 1,   reasons(end+1) = sprintf('sd %.2f uV', sduV(k));          end %#ok<AGROW>
    if ~isnan(corrWithMean(k)) && abs(corrWithMean(k)) < 0.1
        reasons(end+1) = sprintf('corr %.2f', corrWithMean(k));                          %#ok<AGROW>
    end
    if ~isnan(lineRatio(k)) && lineRatio(k) > 10
        reasons(end+1) = sprintf('line x%.0f', lineRatio(k));                            %#ok<AGROW>
    end
    if ~isempty(reasons)
        suspect(end+1) = sprintf('  %-5s  %s', labels(k), strjoin(reasons, ', ')); %#ok<AGROW>
    end
end

if isempty(suspect)
    fprintf('No channels flagged.\n');
else
    fprintf('Flagged for inspection (not rejected):\n%s\n', strjoin(suspect, newline));
end

% -------------------------------------------------------------------------
% Save
% -------------------------------------------------------------------------
if opt.Save
    if ~exist(cfg.resultDir, 'dir'); mkdir(cfg.resultDir); end
    csvOut = fullfile(cfg.resultDir, [EEG.setname '_qc.csv']);
    matOut = fullfile(cfg.resultDir, [EEG.setname '_qc.mat']);
    writetable(qc, csvOut);
    thresholds = rmfield(opt, {'EEG','cfg'}); %#ok<NASGU>
    save(matOut, 'qc', 'thresholds');
    fprintf('\nSaved %s\n      %s\n', csvOut, matOut);
end
end
