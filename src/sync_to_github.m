function sync_to_github(message, varargin)
%SYNC_TO_GITHUB  Commit and push the current state, from inside MATLAB.
%
%   sync_to_github('why you changed something') stages every tracked change,
%   commits it with that message, and pushes to GitHub.
%
%   sync_to_github(msg, 'DryRun', true) shows what would happen without
%   changing anything. Worth using the first few times.
%
%   WHEN TO USE IT
%   After you have made a change AND RUN IT. Pushing code you have not
%   executed is how a repository ends up broken for everyone who cloned it.
%   If you are working through Claude Code, it does this for you as part of
%   each change; this function is for when you edit something by hand in the
%   MATLAB editor.
%
%   WHAT IT WILL NOT DO
%   It refuses to stage anything under data/, figures/, results/ or
%   toolboxes/. Those are excluded in .gitignore, and this is a second,
%   independent check in case that file is ever lost or edited: a patient
%   recording pushed to a public repository stays public forever, because
%   git keeps history even after a file is deleted.
%
%   Example:
%       sync_to_github('Raise epoch rejection to 200 uV; 150 was dropping usable data');
%
%   See also RUN_PIPELINE, PIPELINE_CONFIG.

p = inputParser;
p.addRequired('message', @(x) (ischar(x) || isstring(x)) && strlength(string(x)) > 0);
p.addParameter('DryRun', false, @islogical);
p.parse(message, varargin{:});
opt = p.Results;

cfg  = setup_paths();
root = cfg.root;

% -------------------------------------------------------------------------
% Is git even installed? Checked separately from "is this a repository",
% because the two problems have completely different fixes and git's own
% error message does not distinguish them.
% -------------------------------------------------------------------------
[stGit, outGit] = system('git --version');
if stGit ~= 0
    error('sync_to_github:gitNotInstalled', ...
        ['Git is not installed, or is not on the Windows PATH.\n\n' ...
         'Install it by running this in PowerShell:\n' ...
         '    winget install Git.Git\n\n' ...
         'then RESTART MATLAB so it picks up the new PATH.\n\n' ...
         'What MATLAB got when it asked for the version:\n%s'], strtrim(outGit));
end

% -------------------------------------------------------------------------
% Is this a git repository?
% -------------------------------------------------------------------------
[st, ~] = run_git(root, 'rev-parse --is-inside-work-tree');
if st ~= 0
    error('sync_to_github:notARepo', ...
        ['%s is not a git repository.\n\nIf it used to be one, the .git ' ...
         'folder has been lost -- see GITHUB_AND_CLAUDE_CODE.md, which ' ...
         'explains why OneDrive is a hazardous place to keep one.'], root);
end

% -------------------------------------------------------------------------
% Is .gitignore still present? Without it, a single "git add -A" would stage
% every recording in data/raw. Checked every time, because it has gone
% missing once already.
% -------------------------------------------------------------------------
if exist(fullfile(root, '.gitignore'), 'file') ~= 2
    error('sync_to_github:noGitignore', ...
        ['.gitignore is missing from %s.\n\nRefusing to commit: without it, ' ...
         'every recording in data/raw would be staged. Restore it before ' ...
         'committing anything.'], root);
end

% -------------------------------------------------------------------------
% What has changed?
% -------------------------------------------------------------------------
[~, statusOut] = run_git(root, 'status --porcelain');

if isempty(strtrim(statusOut))
    fprintf('Nothing has changed. Working tree is clean.\n');
    return
end

fprintf('\nChanged files:\n');
lines = strsplit(strtrim(statusOut), newline);
for i = 1:numel(lines)
    fprintf('  %s\n', strtrim(lines{i}));
end
fprintf('\n');

% -------------------------------------------------------------------------
% Safety net: refuse if anything protected is about to be staged
% -------------------------------------------------------------------------
protectedDirs = {'data/', 'figures/', 'results/', 'toolboxes/'};
offenders = {};
for i = 1:numel(lines)
    fileOnly = strtrim(regexprep(lines{i}, '^\s*\S+\s+', ''));
    fileOnly = strrep(fileOnly, '\', '/');
    fileOnly = strrep(fileOnly, '"', '');
    for d = 1:numel(protectedDirs)
        if startsWith(fileOnly, protectedDirs{d}) && ...
           ~endsWith(fileOnly, '.gitkeep') && ~endsWith(fileOnly, '.ced')
            offenders{end+1} = fileOnly; %#ok<AGROW>
        end
    end
end

if ~isempty(offenders)
    error('sync_to_github:protectedPath', ...
        ['Refusing to commit. These files are inside a protected folder:\n' ...
         '  %s\n\nRecordings and generated output must never be committed. ' ...
         'Check .gitignore has not been changed.'], ...
         strjoin(unique(offenders), sprintf('\n  ')));
end

% -------------------------------------------------------------------------
% Commit and push
% -------------------------------------------------------------------------
msg = char(opt.message);

if opt.DryRun
    fprintf('DRY RUN -- nothing was changed.\n');
    fprintf('Would commit with message:\n  %s\n', msg);
    return
end

[st, out] = run_git(root, 'add -A');
if st ~= 0
    error('sync_to_github:addFailed', 'git add failed:\n%s', out);
end

safeMsg = strrep(msg, '"', '\"');
[st, out] = run_git(root, sprintf('commit -m "%s"', safeMsg));
if st ~= 0
    error('sync_to_github:commitFailed', 'git commit failed:\n%s', out);
end
fprintf('Committed.\n');

[st, out] = run_git(root, 'push');
if st ~= 0
    fprintf(2, ['\nCommitted locally, but the push failed:\n%s\n\n' ...
                'The change IS saved on this computer. Common causes: no ' ...
                'internet, no remote configured yet, or not signed in to ' ...
                'GitHub. Run "git push" in a terminal to see the full ' ...
                'error.\n'], out);
    return
end

fprintf('Pushed to GitHub.\n');

[~, url] = run_git(root, 'remote get-url origin');
if ~isempty(strtrim(url))
    fprintf('  %s\n', strtrim(url));
end
end


% =========================================================================
function [status, output] = run_git(root, args)
%RUN_GIT  Run a git command in the project folder.
cmd = sprintf('git -C "%s" %s', root, args);
[status, output] = system(cmd);
end
