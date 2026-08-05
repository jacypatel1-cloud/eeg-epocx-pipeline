function Sout = reorder_channels_for_display(S)
%REORDER_CHANNELS_FOR_DISPLAY  Permute a spectrum to the client's display order.
%
%   Sout = reorder_channels_for_display(S) returns a copy of the spectrum
%   struct from COMPUTE_PSD with .labels, .psd and .psdDb reordered to:
%
%       AF3 AF4  F7 F8  F3 F4  FC5 FC6  T7 T8  P7 P8  O1 O2
%
%   top to bottom, per the client's requested reading order (frontmost
%   pairs first, working back to occipital).
%
%   THIS IS A DISPLAY ORDER, NOT THE DEVICE ORDER. Import, re-referencing,
%   interpolation and ICA all use the fixed EPOC X physical channel order
%   (AF3 F7 F3 FC5 T7 P7 O1 O2 P8 T8 FC6 F4 F8 AF4, see SETUP_PATHS) --
%   that order describes the hardware and must not change. This function
%   only reorders how a spectrum already computed in that order gets drawn.
%   Nothing upstream of plotting (QC columns, results/psd_*.mat, the
%   cleaned .set files) is touched by it.
%
%   Errors if a channel in the display order is missing from S.labels,
%   rather than silently dropping a row -- a spectrum missing an expected
%   channel means something upstream already went wrong, and reordering
%   around the gap would hide that.
%
%   See also DRAW_PSD_STRIPS, COMPUTE_PSD, PLOT_PSD_STACK, COMPARE_RECORDINGS.

displayOrder = {'AF3','AF4','F7','F8','F3','F4','FC5','FC6','T7','T8','P7','P8','O1','O2'};

have = cellstr(S.labels(:));

idx = nan(numel(displayOrder), 1);
for k = 1:numel(displayOrder)
    hit = find(strcmpi(have, displayOrder{k}), 1);
    if ~isempty(hit); idx(k) = hit; end
end

missing = displayOrder(isnan(idx));
if ~isempty(missing)
    error('reorder_channels_for_display:missingChannels', ...
        ['Cannot apply the display order -- %d channel(s) missing from this ' ...
         'spectrum: %s\nChannels present: %s'], ...
        numel(missing), strjoin(missing, ', '), strjoin(have, ', '));
end

Sout          = S;
Sout.labels   = S.labels(idx);
Sout.psd      = S.psd(:, idx);
Sout.psdDb    = S.psdDb(:, idx);
end
