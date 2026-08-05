function result = score_questionnaire(Q, responses)
%SCORE_QUESTIONNAIRE  Total score, severity band, and any special flag.
%
%   result = score_questionnaire(Q, responses) takes one entry from
%   QUESTIONNAIRE_DEFINITIONS and a response vector (one value per item,
%   already mapped through that item's own responseValues -- what a
%   uidropdown's Value already is when its ItemsData is set to
%   responseValues), and returns a struct:
%       id           Q.id, copied through for convenience
%       total        sum of responses
%       band         label of the matching entry in Q.scoreBands
%       flagged      true if Q.specialFlagItem is set and that response > 0
%                    (PHQ-9's self-harm item -- a flag for the clinician to
%                    see, never an automated action)
%       responses    the responses as given, for persistence
%       completedOn  datetime('now')
%
%   REFUSES AN INCOMPLETE OR INVALID RESPONSE SET. responses must have
%   exactly numel(Q.items) values, and every value must be one of that
%   item's own responseValues -- a self-report score means nothing if an
%   item was skipped or a value outside its defined scale slipped in, and
%   silently scoring it anyway would produce a confident-looking number
%   that is not actually valid.
%
%   See also QUESTIONNAIRE_DEFINITIONS.

p = inputParser;
p.addRequired('Q',         @isstruct);
p.addRequired('responses', @isnumeric);
p.parse(Q, responses);

responses = responses(:)';
nItems = numel(Q.items);

if numel(responses) ~= nItems
    error('score_questionnaire:wrongLength', ...
        '%s has %d item(s) but %d response(s) were given.', Q.id, nItems, numel(responses));
end

for i = 1:nItems
    if ~any(responses(i) == Q.items(i).responseValues)
        error('score_questionnaire:invalidResponse', ...
            'Item %d of %s: %g is not one of that item''s allowed values (%s).', ...
            i, Q.id, responses(i), mat2str(Q.items(i).responseValues));
    end
end

total = sum(responses);

band = '';
for b = 1:numel(Q.scoreBands)
    if total >= Q.scoreBands(b).min && total <= Q.scoreBands(b).max
        band = Q.scoreBands(b).label;
        break
    end
end
if isempty(band)
    error('score_questionnaire:noBand', ...
        '%s: total score %g falls outside every defined severity band.', Q.id, total);
end

flagged = false;
if isfield(Q, 'specialFlagItem') && ~isempty(Q.specialFlagItem)
    flagged = responses(Q.specialFlagItem) > 0;
end

result = struct( ...
    'id',          Q.id, ...
    'total',       total, ...
    'band',        band, ...
    'flagged',     flagged, ...
    'responses',   responses, ...
    'completedOn', datetime('now'));
end
