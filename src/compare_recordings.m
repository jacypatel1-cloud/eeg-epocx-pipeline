function figHandle = compare_recordings(specs, cfg, varargin)
%COMPARE_RECORDINGS  Show several recordings' spectra side by side.
%
%   figHandle = compare_recordings(specs, cfg) draws one column per
%   recording in the reference layout, on a shared vertical scale so the
%   columns can honestly be read against one another.
%
%   specs is an array of structs from COMPUTE_PSD. The deliverable asks for
%   three: the first recording, the second-to-last, and the last. PICK_THREE
%   selects those from a list sorted by recording time.
%
%   Options:
%       'Titles'     cellstr, one heading per column. Default: setnames
%       'Save'       write PNG and FIG to figures/.    Default false
%       'Tag'        filename suffix.                  Default 'comparison'
%       'Scale'      'db' | 'linear'.                  Default 'db'
%       'ShowMethod' method footnote.                  Default true
%
%   WHY A SHARED VERTICAL SCALE MATTERS
%   If each column were scaled to its own maximum, a recording with half the
%   power would look identical to one with twice it -- the very change this
%   figure exists to reveal. Every column therefore uses one scale, computed
%   across all recordings shown. The cost is that a genuinely quiet
%   recording looks flat, which is the honest result.
%
%   Channel names appear only on the left-hand column. The rows line up
%   across columns by construction, so repeating them would be clutter.
%
%   See also COMPUTE_PSD, DRAW_PSD_STRIPS, PICK_THREE.

p = inputParser;
p.addRequired('specs', @(x) isstruct(x) && numel(x) >= 1);
p.addRequired('cfg',   @isstruct);
p.addParameter('Titles',     {},           @iscell);
p.addParameter('Save',       false,        @islogical);
p.addParameter('Tag',        'comparison', @(x) ischar(x) || isstring(x));
p.addParameter('Scale',      'db',         @(x) any(strcmpi(x, {'db','linear'})));
p.addParameter('ShowMethod', true,         @islogical);
p.parse(specs, cfg, varargin{:});
opt = p.Results;

nRec = numel(specs);

% -------------------------------------------------------------------------
% Refuse to compare things that are not comparable
% -------------------------------------------------------------------------
for i = 2:nRec
    if ~isequal(specs(i).labels, specs(1).labels)
        error('compare_recordings:channelMismatch', ...
            ['Recording %d has different channels from recording 1. ' ...
             'These cannot be compared directly.'], i);
    end
    if ~strcmp(specs(i).method, specs(1).method)
        warning('compare_recordings:methodMismatch', ...
            ['Recording %d used a different analysis method:\n  %s\n' ...
             'vs recording 1:\n  %s\nThe comparison may mislead.'], ...
             i, specs(i).method, specs(1).method);
    end
end

% -------------------------------------------------------------------------
% Shared scale across every recording shown
% -------------------------------------------------------------------------
allY = [];
for i = 1:nRec
    if strcmpi(opt.Scale, 'db'); Yi = specs(i).psdDb; else; Yi = specs(i).psd; end
    allY = [allY; Yi(:)]; %#ok<AGROW>
end

yFloor = min(allY);
yRange = max(allY) - yFloor;
if yRange <= 0; yRange = 1; end
% spacing must exceed yRange (not be a fraction of it) or the tallest strip
% is guaranteed to collide with the strip above it -- see PLOT_PSD_STACK for
% the full explanation. 1.25x leaves a clear 25% gap between strips.
spacing = yRange * 1.25;

nCh  = numel(specs(1).labels);
cmap = jet(nCh);

if strcmpi(opt.Scale, 'db')
    yTickFormat = '%.0f';
else
    yTickFormat = '%.2g';
end

% -------------------------------------------------------------------------
% Draw one column per recording
% -------------------------------------------------------------------------
figHandle = figure('Color', 'w', ...
                   'Position', fit_figure_to_screen(min(1750, 560*nRec), 1000), ...
                   'Name', 'PSD comparison');

leftMargin  = 0.075;
rightMargin = 0.015;
gap         = 0.025;
colWidth    = (1 - leftMargin - rightMargin - gap*(nRec-1)) / nRec;

for r = 1:nRec
    S  = specs(r);
    ax = axes(figHandle, 'Position', ...
        [leftMargin + (r-1)*(colWidth+gap), 0.075, colWidth, 0.855]); %#ok<LAXES>

    style = struct('yFloor', yFloor, 'yRange', yRange, 'spacing', spacing, ...
                   'cmap', cmap, 'showLabels', r == 1, 'labelSize', 11, ...
                   'scale', opt.Scale, 'showYScale', true, ...
                   'yTickFormat', yTickFormat);

    draw_psd_strips(ax, S, style);

    fSpan = [S.f(1) S.f(end)];
    xlim(ax, [fSpan(1) - 0.06*diff(fSpan), fSpan(2) + 0.16*diff(fSpan)]);
    ylim(ax, [-spacing*0.40, (nCh-1)*spacing + yRange*1.02]);
    axis(ax, 'off');

    % Frequency scale under each column
    yAxisLine = -spacing * 0.30;
    hold(ax, 'on');
    plot(ax, fSpan, [yAxisLine yAxisLine], 'Color', [0.15 0.15 0.15], ...
         'LineWidth', 1.3);
    for tx = fSpan(1):10:fSpan(2)
        plot(ax, [tx tx], [yAxisLine, yAxisLine - spacing*0.06], ...
             'Color', [0.15 0.15 0.15], 'LineWidth', 1.3);
        text(ax, tx, yAxisLine - spacing*0.13, sprintf('%g Hz', tx), ...
             'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
             'FontWeight', 'bold', 'FontSize', 11, 'Color', [0.15 0.15 0.15]);
    end
    hold(ax, 'off');

    % Column heading
    if isempty(opt.Titles)
        colTitle = char(S.setname);
    else
        colTitle = char(opt.Titles{r});
    end
    text(ax, mean(fSpan), (nCh-1)*spacing + yRange*1.02, ...
         strrep(colTitle, '_', '\_'), ...
         'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
         'FontWeight', 'bold', 'FontSize', 10, 'Interpreter', 'tex');
end

if opt.ShowMethod
    if strcmpi(opt.Scale, 'db')
        unitText = 'dB (10log_{10} \muV^2/Hz)';
    else
        unitText = '\muV^2/Hz';
    end
    annotation(figHandle, 'textbox', [0.02 0.004 0.96 0.032], ...
        'String', sprintf('%s  |  %s  |  shared vertical scale across all columns', ...
                          specs(1).method, unitText), ...
        'EdgeColor', 'none', 'FontSize', 8, 'Color', [0.45 0.45 0.45], ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
end

% -------------------------------------------------------------------------
% Save
% -------------------------------------------------------------------------
if opt.Save
    if ~exist(cfg.figDir, 'dir'); mkdir(cfg.figDir); end
    base = fullfile(cfg.figDir, char(opt.Tag));
    exportgraphics(figHandle, [base '.png'], 'Resolution', 150);
    savefig(figHandle, [base '.fig']);
    fprintf('Saved %s.png\n', base);
end
end
