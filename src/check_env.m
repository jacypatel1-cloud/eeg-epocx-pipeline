function ok = check_env()
%CHECK_ENV  Verify MATLAB toolboxes and EEGLAB plugins needed by the pipeline.
%
%   ok = check_env() prints a report and returns true if every hard
%   requirement is present. Run this after setup_paths().

ok = true;
fprintf('\n=== Environment check ===\n');
fprintf('MATLAB       : %s (%s)\n', version, computer);

% --- MATLAB toolboxes ---------------------------------------------------
required = { ...
    'Signal Processing Toolbox',            'signal'; ...
    'Statistics and Machine Learning Toolbox', 'stats'};
optional = { ...
    'Image Processing Toolbox',             'images'; ...
    'Parallel Computing Toolbox',           'distcomp'};

v = ver;
installed = {v.Name};

fprintf('\n-- Required toolboxes --\n');
for k = 1:size(required, 1)
    present = any(strcmp(installed, required{k,1})) || ...
              license('test', required{k,2});
    fprintf('  [%s] %s\n', tick(present), required{k,1});
    ok = ok && present;
end

fprintf('\n-- Optional toolboxes --\n');
for k = 1:size(optional, 1)
    present = any(strcmp(installed, optional{k,1}));
    fprintf('  [%s] %s\n', tick(present), optional{k,1});
end

% --- EEGLAB and plugins -------------------------------------------------
fprintf('\n-- EEGLAB --\n');
hasEEGLAB = exist('eeglab', 'file') == 2;
fprintf('  [%s] eeglab\n', tick(hasEEGLAB));
ok = ok && hasEEGLAB;

plugins = { ...
    'ICLabel  (IC classification)', 'iclabel'; ...
    'clean_rawdata / ASR',          'clean_artifacts'; ...
    'BIOSIG (EDF/BDF import)',      'pop_biosig'; ...
    'firfilt (FIR filtering)',      'pop_eegfiltnew'};

for k = 1:size(plugins, 1)
    present = exist(plugins{k,2}, 'file') > 0;
    fprintf('  [%s] %s\n', tick(present), plugins{k,1});
    ok = ok && present;
end

fprintf('\n%s\n\n', ternary(ok, 'All hard requirements met.', ...
    'MISSING requirements above - install before running the pipeline.'));
end

function s = tick(b)
if b, s = 'x'; else, s = ' '; end
end

function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end
