function yBase = draw_psd_strips(ax, S, style)
%DRAW_PSD_STRIPS  Draw one recording as stacked filled strips.
%
%   yBase = draw_psd_strips(ax, S, style) draws the spectrum S into the axes
%   ax in the client's reference layout, and returns the baseline y position
%   of each channel.
%
%   style is a struct with fields:
%       yFloor       value mapped to a strip's baseline
%       yRange       full value range (sets strip height)
%       spacing      vertical distance between baselines
%       cmap         nCh x 3 colours, row 1 = top channel
%       showLabels   draw channel names at the left
%       labelSize    font size for those names
%       scale        'db' | 'linear'
%       showYScale   draw an amplitude tick ruler on the right of each strip
%       yTickFormat  sprintf format for the tick numbers, e.g. '%.0f'
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
%   WHY spacing MUST BE AT LEAST yRange
%   A strip's curve height above its baseline is (value - yFloor), which by
%   construction can reach the full yRange (that is what yRange means: the
%   spread from the quietest to the loudest point across everything being
%   drawn). If the caller sets spacing smaller than yRange, the tallest strip
%   is geometrically guaranteed to rise into the strip above it -- that is
%   not a rare edge case, it is the routine appearance of a normal PSD peak.
%   Callers must pass spacing >= yRange, with headroom on top for a visible
%   gap between strips. This function does not defend against a caller
%   passing too little; PLOT_PSD_STACK and COMPARE_RECORDINGS are
%   responsible for choosing spacing correctly.
%
%   PER-STRIP Y-AXIS
%   Because every strip shares one scale, the same three tick values (floor,
%   mid, peak) are correct on every row -- but readers should not have to
%   hold "the scale" in their head while scanning fourteen rows. A small
%   tick ruler is drawn at the right edge of each strip for that reason.
%
%   See also PLOT_PSD_STACK, COMPARE_RECORDINGS, COMPUTE_PSD.

if strcmpi(style.scale, 'db')
    Y = S.psdDb;
else
    Y = S.psd;
end

f   = S.f(:);
nCh = size(Y, 2);

if ~isfield(style, 'showYScale');  style.showYScale  = true;   end
if ~isfield(style, 'yTickFormat'); style.yTickFormat  = '%.0f'; end

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

    % Amplitude tick ruler at the right edge of the strip. Three ticks --
    % floor, mid, peak of the SHARED scale (not this channel's own min/max,
    % which would misrepresent a shared-scale figure as normalised). Every
    % row shows the same three numbers on purpose: a reader looking at any
    % single row, without having to scroll back to a legend, can read off
    % what a given curve height means.
    if style.showYScale
        tickLen = 0.012 * (f(end) - f(1));
        for tf = [0 0.5 1]
            ty  = base + tf * style.yRange;
            val = style.yFloor + tf * style.yRange;
            plot(ax, [f(end), f(end) + tickLen], [ty ty], ...
                 'Color', [0.35 0.35 0.35], 'LineWidth', 0.7);
            text(ax, f(end) + tickLen * 1.6, ty, sprintf(style.yTickFormat, val), ...
                 'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', ...
                 'FontSize', max(6, style.labelSize * 0.55), ...
                 'Color', [0.4 0.4 0.4]);
        end
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
