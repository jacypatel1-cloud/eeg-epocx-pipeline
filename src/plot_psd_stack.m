function figHandle = plot_psd_stack(S, cfg, varargin)
%PLOT_PSD_STACK  Stacked power-spectrum display, one filled strip per channel.
%
%   figHandle = plot_psd_stack(S, cfg) draws the spectrum struct from
%   COMPUTE_PSD in the layout of the client's reference figure: channels
%   stacked vertically, each a filled area, coloured blue at the top through
%   to red at the bottom, with channel names down the left and a single
%   frequency scale along the bottom.
%
%   Options:
%       'Save'       write PNG and FIG to figures/.        Default false
%       'Tag'        suffix for the saved filename.        Default ''
%       'Scale'      'db' | 'linear'.                      Default 'db'
%       'Title'      heading text; '' for none.            Default '' (none)
%       'ShowMethod' small footnote naming the method.     Default true
%       'Colormap'   any Nx3 colormap.                     Default jet
%       'Visible'    show the figure window on screen.     Default true
%
%   ON THE DEFAULTS
%   Title is OFF and there is no y-axis, because the reference figure has
%   neither. ShowMethod is ON: it prints the analysis method in small grey
%   type beneath the frequency axis. That is required by the project rules
%   (the method behind a spectrum must never be ambiguous) and it is small
%   enough not to alter the look of the plot. Pass 'ShowMethod', false for a
%   pixel-clean match to the reference.
%
%   READING THE FIGURE
%   Left to right is frequency, 0-20 Hz. The height of each coloured band is
%   power at that frequency for that channel. Channels run front-of-head at
%   the top to back and round at the bottom, in EPOC X order. A bump around
%   8-12 Hz on the lower (posterior) channels is alpha rhythm.
%
%   See also COMPUTE_PSD, DRAW_PSD_STRIPS, COMPARE_RECORDINGS.

p = inputParser;
p.addRequired('S',   @isstruct);
p.addRequired('cfg', @isstruct);
p.addParameter('Save',       false, @islogical);
p.addParameter('Tag',        '',    @(x) ischar(x) || isstring(x));
p.addParameter('Scale',      'db',  @(x) any(strcmpi(x, {'db','linear'})));
p.addParameter('Title',      '',    @(x) ischar(x) || isstring(x));
p.addParameter('ShowMethod', true,  @islogical);
p.addParameter('Colormap',   [],    @(x) isempty(x) || size(x,2) == 3);
p.addParameter('Visible',    true,  @islogical);
p.parse(S, cfg, varargin{:});
opt = p.Results;

if strcmpi(opt.Scale, 'db')
    Y = S.psdDb;
else
    Y = S.psd;
end

nCh = size(Y, 2);

% -------------------------------------------------------------------------
% One common vertical scale for every channel. If each strip were normalised
% to its own maximum, a quiet channel would look identical to a loud one.
%
% SPACING MUST EXCEED yRange, NOT BE A FRACTION OF IT. A strip's curve rises
% (value - yFloor) above its baseline, which can reach the full yRange -- so
% spacing < yRange guarantees strips collide with the one above them (this
% was the cause of the overlapping-graphs bug). 1.25x leaves a clear 25% gap
% of blank space between the tallest possible strip and the baseline above
% it, which is also where the per-strip amplitude ticks live.
% -------------------------------------------------------------------------
yFloor = min(Y(:));
yRange = max(Y(:)) - yFloor;
if yRange <= 0; yRange = 1; end
spacing = yRange * 1.25;

if isempty(opt.Colormap)
    cmap = jet(nCh);
else
    cmap = opt.Colormap;
    if size(cmap, 1) ~= nCh
        cmap = interp1(linspace(0,1,size(cmap,1)), cmap, linspace(0,1,nCh));
    end
end

% -------------------------------------------------------------------------
% Draw
% -------------------------------------------------------------------------
visStr = 'on';
if ~opt.Visible; visStr = 'off'; end
figHandle = figure('Color', 'w', 'Position', fit_figure_to_screen(780, 1000), ...
                   'Name', sprintf('PSD - %s', S.setname), 'Visible', visStr);

ax = axes(figHandle, 'Position', [0.14 0.07 0.82 0.88]);

if strcmpi(opt.Scale, 'db')
    yTickFormat = '%.0f';
else
    yTickFormat = '%.2g';
end

style = struct('yFloor', yFloor, 'yRange', yRange, 'spacing', spacing, ...
               'cmap', cmap, 'showLabels', true, 'labelSize', 13, ...
               'scale', opt.Scale, 'showYScale', true, ...
               'yTickFormat', yTickFormat);

draw_psd_strips(ax, S, style);

% -------------------------------------------------------------------------
% Axes: the reference figure has no frame and no gridlines. A hand-drawn
% frequency scale runs along the bottom; the per-strip amplitude ticks drawn
% by DRAW_PSD_STRIPS sit just past the right edge, so xlim needs headroom on
% both sides to avoid clipping either one.
% -------------------------------------------------------------------------
fSpan = [S.f(1) S.f(end)];
xlim(ax, [fSpan(1) - 0.05*diff(fSpan), fSpan(2) + 0.14*diff(fSpan)]);
ylim(ax, [-spacing*0.35, (nCh-1)*spacing + yRange*1.02]);

axis(ax, 'off');   % remove everything, then draw only what we want back

% Frequency scale, drawn by hand beneath the lowest strip.
yAxisLine = -spacing * 0.30;
hold(ax, 'on');
plot(ax, fSpan, [yAxisLine yAxisLine], 'Color', [0.15 0.15 0.15], ...
     'LineWidth', 1.4);

for tx = fSpan(1):10:fSpan(2)
    plot(ax, [tx tx], [yAxisLine, yAxisLine - spacing*0.06], ...
         'Color', [0.15 0.15 0.15], 'LineWidth', 1.4);
    text(ax, tx, yAxisLine - spacing*0.12, sprintf('%g Hz', tx), ...
         'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
         'FontWeight', 'bold', 'FontSize', 13, 'Color', [0.15 0.15 0.15]);
end
hold(ax, 'off');

if ~isempty(char(opt.Title))
    title(ax, strrep(char(opt.Title), '_', '\_'), ...
          'FontWeight', 'bold', 'FontSize', 12, 'Visible', 'on');
end

% Method footnote. Small and grey: present for the record, but not part of
% the visual design.
if opt.ShowMethod
    if strcmpi(opt.Scale, 'db')
        unitText = 'dB (10log_{10} \muV^2/Hz)';
    else
        unitText = '\muV^2/Hz';
    end
    annotation(figHandle, 'textbox', [0.02 0.005 0.96 0.035], ...
        'String', sprintf('%s  |  %s', S.method, unitText), ...
        'EdgeColor', 'none', 'FontSize', 7.5, 'Color', [0.45 0.45 0.45], ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
end

% -------------------------------------------------------------------------
% Save
% -------------------------------------------------------------------------
if opt.Save
    if ~exist(cfg.figDir, 'dir'); mkdir(cfg.figDir); end
    tag = char(opt.Tag);
    if ~isempty(tag); tag = ['_' tag]; end
    safeName = matlab.lang.makeValidName(char(S.setname));
    base = fullfile(cfg.figDir, sprintf('%s_psdstack%s', safeName, tag));
    exportgraphics(figHandle, [base '.png'], 'Resolution', 150);
    savefig(figHandle, [base '.fig']);
    fprintf('  saved %s.png\n', base);
end
end
