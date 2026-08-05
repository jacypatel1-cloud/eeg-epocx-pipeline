function Q = questionnaire_definitions()
%QUESTIONNAIRE_DEFINITIONS  The five subjective questionnaires associated with a scan.
%
%   Q = questionnaire_definitions() returns a struct array, one entry per
%   instrument, each with:
%       id             short code, e.g. 'PHQ9'
%       title          full name shown in the UI
%       category       what it's a proxy for, e.g. 'Mood'
%       instructions   the stem question read before every item
%       items          1xN struct array, one per question:
%                          .text            the item wording
%                          .responseLabels  cellstr, the choices shown
%                          .responseValues  numeric value per choice, in
%                                           the same order -- SCORE_QUESTIONNAIRE
%                                           sums whichever value was picked
%       scoreBands     1xM struct array of severity cutoffs:
%                          .label  e.g. 'Moderate'
%                          .min / .max  inclusive total-score range
%       specialFlagItem  (PHQ-9 only) the item index that is a self-harm
%                        screen -- SCORE_QUESTIONNAIRE reports whether it
%                        was endorsed so the UI can flag it to the
%                        clinician. This is a flag, never an automated
%                        clinical action.
%       placeholder    true for instruments not yet populated with
%                      verified source text (see below)
%
%   PHQ-9, GAD-7 AND ISI ARE FULLY POPULATED. Item wording and scoring
%   cutoffs are the standard, widely-published versions (PHQ-9/GAD-7 are
%   public domain, developed under the MacArthur Initiative/Pfizer; ISI's
%   item content and cutoffs are Morin's published scale, reproduced here
%   as commonly used in clinical practice).
%
%   MMQ-9 AND CBS ARE DELIBERATELY PLACEHOLDERS. The short Multifactorial
%   Memory Questionnaire and the Catherine Bergego Scale self-report form
%   are more specialized instruments than PHQ-9/GAD-7/ISI, and CBS
%   specifically is a copyrighted clinical instrument (Azouvi et al.).
%   Fabricating exact item wording for either would risk an invalid score
%   presented as a real one -- this file gives both a working form shell
%   (9 generic items, a plain 0-4 scale, a simple sum-based band) so the
%   rest of the engine (form UI, persistence, per-scan association) can be
%   used and tested end to end, with every item text clearly marked
%   "[PLACEHOLDER]" so nobody mistakes it for the verified instrument.
%   Replace items/scoreBands here with the licensed source text before any
%   clinical use.
%
%   See also SCORE_QUESTIONNAIRE.

standard4pt = {'Not at all', 'Several days', 'More than half the days', 'Nearly every day'};
standard4val = [0 1 2 3];

% =========================================================================
% PHQ-9 -- Mood
% =========================================================================
phq9Items = { ...
    'Little interest or pleasure in doing things', ...
    'Feeling down, depressed, or hopeless', ...
    'Trouble falling or staying asleep, or sleeping too much', ...
    'Feeling tired or having little energy', ...
    'Poor appetite or overeating', ...
    ['Feeling bad about yourself -- or that you are a failure or have let ' ...
     'yourself or your family down'], ...
    'Trouble concentrating on things, such as reading the newspaper or watching television', ...
    ['Moving or speaking so slowly that other people could have noticed -- or the ' ...
     'opposite, being so fidgety or restless that you have been moving around a lot ' ...
     'more than usual'], ...
    'Thoughts that you would be better off dead, or of hurting yourself in some way'};

PHQ9.id           = 'PHQ9';
PHQ9.title        = 'Patient Health Questionnaire-9 (PHQ-9)';
PHQ9.category     = 'Mood';
PHQ9.instructions = 'Over the last 2 weeks, how often have you been bothered by any of the following problems?';
PHQ9.items        = make_items(phq9Items, standard4pt, standard4val);
PHQ9.scoreBands   = make_bands({'None-minimal','Mild','Moderate','Moderately severe','Severe'}, ...
                                [0 5 10 15 20], [4 9 14 19 27]);
PHQ9.specialFlagItem = 9;
PHQ9.placeholder  = false;

% =========================================================================
% GAD-7 -- Anxiety
% =========================================================================
gad7Items = { ...
    'Feeling nervous, anxious, or on edge', ...
    'Not being able to stop or control worrying', ...
    'Worrying too much about different things', ...
    'Trouble relaxing', ...
    'Being so restless that it is hard to sit still', ...
    'Becoming easily annoyed or irritable', ...
    'Feeling afraid as if something awful might happen'};

GAD7.id           = 'GAD7';
GAD7.title        = 'Generalized Anxiety Disorder-7 (GAD-7)';
GAD7.category     = 'Anxiety';
GAD7.instructions = 'Over the last 2 weeks, how often have you been bothered by the following problems?';
GAD7.items        = make_items(gad7Items, standard4pt, standard4val);
GAD7.scoreBands   = make_bands({'Minimal','Mild','Moderate','Severe'}, ...
                                [0 5 10 15], [4 9 14 21]);
GAD7.specialFlagItem = [];
GAD7.placeholder  = false;

% =========================================================================
% ISI -- Sleep
% =========================================================================
% Items 1-3 share one severity scale; items 4-7 each have their own
% differently-worded 0-4 scale (satisfaction / noticeability / worry /
% interference) -- this is why each item carries its own responseLabels
% rather than one scale for the whole instrument.
sevScale = {'None', 'Mild', 'Moderate', 'Severe', 'Very severe'};
sevVal   = [0 1 2 3 4];

isiItems(1) = struct('text', 'Difficulty falling asleep', ...
    'responseLabels', {sevScale}, 'responseValues', sevVal);
isiItems(2) = struct('text', 'Difficulty staying asleep', ...
    'responseLabels', {sevScale}, 'responseValues', sevVal);
isiItems(3) = struct('text', 'Problem waking up too early', ...
    'responseLabels', {sevScale}, 'responseValues', sevVal);
isiItems(4) = struct('text', 'How satisfied/dissatisfied are you with your current sleep pattern?', ...
    'responseLabels', {{'Very satisfied','Satisfied','Moderately satisfied','Dissatisfied','Very dissatisfied'}}, ...
    'responseValues', [0 1 2 3 4]);
isiItems(5) = struct('text', ['How noticeable to others do you think your sleep problem is in terms of ' ...
     'impairing the quality of your life?'], ...
    'responseLabels', {{'Not at all noticeable','A little','Somewhat','Much','Very much noticeable'}}, ...
    'responseValues', [0 1 2 3 4]);
isiItems(6) = struct('text', 'How worried/distressed are you about your current sleep problem?', ...
    'responseLabels', {{'Not at all worried','A little','Somewhat','Much','Very much worried'}}, ...
    'responseValues', [0 1 2 3 4]);
isiItems(7) = struct('text', ['To what extent do you consider your sleep problem to interfere with your ' ...
     'daily functioning currently (e.g. daytime fatigue, mood, concentration, memory, ' ...
     'ability to function at work or on daily chores)?'], ...
    'responseLabels', {{'Not at all interfering','A little','Somewhat','Much','Very much interfering'}}, ...
    'responseValues', [0 1 2 3 4]);

ISI.id           = 'ISI';
ISI.title        = 'Insomnia Severity Index (ISI)';
ISI.category     = 'Sleep';
ISI.instructions = 'Please rate the CURRENT (i.e. last 2 weeks) severity of your insomnia problem(s).';
ISI.items        = isiItems;
ISI.scoreBands   = make_bands({'No clinically significant insomnia','Subthreshold insomnia', ...
                                'Clinical insomnia (moderate)','Clinical insomnia (severe)'}, ...
                               [0 8 15 22], [7 14 21 28]);
ISI.specialFlagItem = [];
ISI.placeholder  = false;

% =========================================================================
% MMQ-9 -- Temporal lobe functioning proxy (subjective memory) -- PLACEHOLDER
% =========================================================================
mmq9Text = arrayfun(@(k) sprintf(['[PLACEHOLDER -- replace with verified short MMQ item %d ' ...
    'wording before clinical use]'], k), 1:9, 'UniformOutput', false);

MMQ9.id           = 'MMQ9';
MMQ9.title        = 'Short Multifactorial Memory Questionnaire (MMQ-9) -- PLACEHOLDER';
MMQ9.category     = 'Temporal lobe functioning (subjective memory proxy)';
MMQ9.instructions = ['[PLACEHOLDER instructions -- replace with the verified MMQ-9 stem question ' ...
    'before clinical use]'];
MMQ9.items        = make_items(mmq9Text, standard4pt, standard4val);
MMQ9.scoreBands   = make_bands({'Lower reported difficulty','Higher reported difficulty'}, ...
                                [0 14], [13 27]);
MMQ9.specialFlagItem = [];
MMQ9.placeholder  = true;

% =========================================================================
% CBS -- Parietal lobe functioning proxy (neglect/spatial awareness) -- PLACEHOLDER
% =========================================================================
% CBS (Catherine Bergego Scale) is a copyrighted clinical instrument
% (Azouvi et al.) -- item wording is not reproduced here without a
% verified, licensed source.
cbsText = arrayfun(@(k) sprintf(['[PLACEHOLDER -- replace with verified CBS self-report item %d ' ...
    'wording before clinical use]'], k), 1:9, 'UniformOutput', false);

CBS.id           = 'CBS';
CBS.title        = 'Catherine Bergego Scale, self-report (CBS) -- PLACEHOLDER';
CBS.category     = 'Parietal lobe functioning (neglect/spatial awareness proxy)';
CBS.instructions = ['[PLACEHOLDER instructions -- replace with the verified CBS self-report ' ...
    'instructions before clinical use]'];
CBS.items        = make_items(cbsText, standard4pt, standard4val);
CBS.scoreBands   = make_bands({'Lower reported difficulty','Higher reported difficulty'}, ...
                               [0 14], [13 27]);
CBS.specialFlagItem = [];
CBS.placeholder  = true;

Q = [PHQ9, GAD7, ISI, MMQ9, CBS];
end


% =========================================================================
function items = make_items(texts, responseLabels, responseValues)
%MAKE_ITEMS  Build an item struct array where every item shares one scale.
n = numel(texts);
items = struct('text', texts, ...
               'responseLabels', repmat({responseLabels}, 1, n), ...
               'responseValues', repmat({responseValues}, 1, n));
end

% =========================================================================
function bands = make_bands(labels, mins, maxs)
bands = struct('label', labels, 'min', num2cell(mins), 'max', num2cell(maxs));
end
