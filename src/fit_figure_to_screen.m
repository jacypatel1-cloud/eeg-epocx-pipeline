function pos = fit_figure_to_screen(desiredW, desiredH, varargin)
%FIT_FIGURE_TO_SCREEN  A figure Position that always keeps the title bar
%   (and with it Close/Minimize) on-screen, on whatever monitor this runs.
%
%   pos = fit_figure_to_screen(desiredW, desiredH) returns a
%   [left bottom width height] vector: desiredW x desiredH if the screen is
%   big enough, shrunk to fit if it is not, and centered either way.
%
%   WHY THIS EXISTS
%   Every figure this project draws used to hardcode a fixed pixel Position
%   (e.g. bottom=30, height=1000), sized for whatever screen it was written
%   on. MATLAB's figure Position is measured from the BOTTOM-left of the
%   primary monitor, so a figure that is taller than (screen height - the
%   window's own bottom margin) has its top edge -- where Windows puts the
%   title bar -- pushed above the top of the screen entirely. The window is
%   still open, just permanently unreachable: no title bar means no Close,
%   no Minimize, no dragging it back into view. This happened on a real
%   1536x864 screen with a figure hardcoded to reach 1040px tall.
%
%   Options:
%       'MarginFrac'      fraction of screen kept clear on each side.
%                         Default 0.05
%       'ChromeReserveY'  extra pixels reserved vertically for the title bar
%                         and Windows taskbar, on top of MarginFrac.
%                         Default 90
%
%   See also PLOT_PSD_STACK, COMPARE_RECORDINGS.

p = inputParser;
p.addRequired('desiredW', @isscalar);
p.addRequired('desiredH', @isscalar);
p.addParameter('MarginFrac',     0.05, @isscalar);
p.addParameter('ChromeReserveY', 90,   @isscalar);
p.parse(desiredW, desiredH, varargin{:});
opt = p.Results;

screenSize = get(0, 'ScreenSize');   % [1 1 width height] of the primary monitor
screenW = screenSize(3);
screenH = screenSize(4);

maxW = screenW * (1 - 2*opt.MarginFrac);
maxH = screenH * (1 - 2*opt.MarginFrac) - opt.ChromeReserveY;

w = min(desiredW, maxW);
h = min(desiredH, maxH);

left   = max(1, (screenW - w) / 2);
bottom = max(1, (screenH - h) / 2 - opt.ChromeReserveY / 2);

pos = [left, bottom, w, h];
end
