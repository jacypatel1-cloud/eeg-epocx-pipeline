function yBase = draw_psd_strips(ax, S, style)
%DRAW_PSD_STRIPS  Draw one recording as stacked filled strips.
%
%   yBase = draw_psd_strips(ax, S, style) draws the spectrum S into the axes
%   ax in the client's reference layout, and returns the baseline y position
%   of each channel.
%
%   style is a struct with fields:
%       yFloor      value mapped to a strip's baseline
%       yRange      full value range (sets strip height)
%       spacing     vertical distance between baselines
%       cmap        nCh x 3 colours, row 1 = top channel
%       showLabels  draw channel names at the left
%       labelSize   font size for those names
%       scale       'db' | 'linear'
%
%   WHY THIS IS ITS OWN FILE
%   Both the single-recording viewer and the multi-recording comparison draw
%   exactly the same thing. Keeping one copy means the two can never drift
%   apart visually -- if they did, a comparison figure would be showing two
%   differently-drawn pictures and inviting a false conclusion.
%
%   THE LAYOUT, AND WHY EACH PART IS THERE
%   Channels are stacked with channel 1 at the top. Every channel uses the
%   SAME vertical scale and is simply shifted upwards, so a tall strip really
%   does mean more power. Each strip gets its own baseline rule with small
%   tick marks, which is what lets the eye follow a single frequency down
%   the page across all 14 channels.
%
%   See also PLOT_PSD_STACK, COMPARE_RECORDINGS, COMPUTE_PSD.

if strcmpi(style.scale, 'db')
    Y = S.psdDb;
else
    Y = S.psd;
end

f   = S.f(:);
nCh = size(Y, 2);

yBase = zeros(nCh, 1);

hold(ax, 'on');

for k = 1:nCh
    % Channel 1 sits at the top, so the offset counts downwards.
    base   = (nCh - k) * style.spacing;
    yCurve = Y(:, k) - style.yFloor + base;

    % Filled area under the curve.
    fill(ax, [f(1); f; f(end)], [base; yCurve; base], style.cmap(k, :), ...
         'EdgeColor', 'none', 'FaceAlpha', 1);

    % Outline, in a darker shade of the same colour, so that where two
    % strips overlap the boundary between them stays readable.
    plot(ax, f, yCurve, 'Color', style.cmap(k, :) * 0.5, 'LineWidth', 0.6);

    % Baseline rule for this channel.
    plot(ax, [f(1) f(end)], [base base], 'Color', [0.35 0.35 0.35], ...
         'LineWidth', 0.9);

    % Small downward ticks along the baseline, every 2 Hz, matching the
    % reference figure. They give the eye a frequency ruler on every strip
    % rather than only at the bottom of the page.
    tickX = ceil(f(1)/2)*2 : 2 : floor(f(end));
    tickH = style.spacing * 0.10;
    for tx = tickX
        plot(ax, [tx tx], [base, base - tickH], ...
             'Color', [0.35 0.35 0.35], 'LineWidth', 0.7);
    end

    % Channel name, to the left of the axis, vertically centred on the strip.
    if style.showLabels
        text(ax, f(1) - 0.035*(f(end)-f(1)), base + style.spacing*0.15, ...
             char(S.labels(k)), ...
             'HorizontalAlignment', 'right', ...
             'VerticalAlignment',   'middle', ...
             'FontWeight', 'bold', ...
             'FontSize',   style.labelSize, ...
             'Color',      [0.15 0.15 0.15]);
    end

    yBase(k) = base;
end

hold(ax, 'off');
end
