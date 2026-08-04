function [idx, labels] = pick_three(infos)
%PICK_THREE  Choose the first, second-to-last and last recording.
%
%   [idx, labels] = pick_three(infos) takes an array of structs from
%   PARSE_RECORDING_NAME, sorts them into recording order, and returns the
%   indices of the three the brief asks to compare, plus a readable label
%   for each.
%
%   WHAT "FIRST", "SECOND-TO-LAST" AND "LAST" MEAN HERE
%   Order is taken from the timestamp embedded in each filename, not from
%   alphabetical order and not from the order the operating system happens
%   to list files in. Alphabetical order would put DOWN before UP regardless
%   of when either was recorded.
%
%   EDGE CASES, HANDLED EXPLICITLY
%       0 recordings  -> error, there is nothing to plot
%       1 recording   -> returns it once, with a warning
%       2 recordings  -> returns first and last only, with a warning
%       3 or more     -> first, second-to-last, last
%   With exactly 3 recordings, "first" and "second-to-last" are the same
%   file; that is correct, and the labels say so rather than hiding it.
%
%   See also PARSE_RECORDING_NAME, COMPARE_RECORDINGS.

n = numel(infos);

if n == 0
    error('pick_three:noRecordings', ...
        'No recordings supplied. Check that data/raw contains CSV files.');
end

% Sort by timestamp. Anything without a readable timestamp goes last, and
% is reported, rather than being silently dropped or silently placed first.
ts    = [infos.timestamp];
noTs  = isnat(ts);
if any(noTs)
    warning('pick_three:missingTimestamps', ...
        ['%d recording(s) have no readable timestamp and were placed at ' ...
         'the end of the ordering.'], sum(noTs));
end
[~, order] = sort(ts);

if n == 1
    warning('pick_three:onlyOne', ...
        'Only one recording available; the comparison shows it alone.');
    idx    = order(1);
    labels = {sprintf('Only recording\n%s', infos(order(1)).name)};
    return
end

if n == 2
    warning('pick_three:onlyTwo', ...
        'Only two recordings available; showing first and last.');
    idx    = [order(1), order(end)];
    labels = { ...
        sprintf('First\n%s', infos(order(1)).name), ...
        sprintf('Last\n%s',  infos(order(end)).name)};
    return
end

iFirst  = order(1);
iSecond = order(end - 1);
iLast   = order(end);

idx = [iFirst, iSecond, iLast];

labels = { ...
    sprintf('First\n%s',          infos(iFirst).name), ...
    sprintf('Second-to-last\n%s', infos(iSecond).name), ...
    sprintf('Last\n%s',           infos(iLast).name)};

if iFirst == iSecond
    labels{1} = sprintf('First (= second-to-last)\n%s', infos(iFirst).name);
end
end
