function patientId = create_patient_profile(cfg, lastName, firstName, dob, unitNumber)
%CREATE_PATIENT_PROFILE  Start a new patient record under data/patients.
%
%   patientId = create_patient_profile(cfg, lastName, firstName, dob, unitNumber)
%   creates data/patients/<patientId>/ with a profile.json (identity) and
%   an empty visits/ subfolder, and returns the generated patientId.
%
%   dob is stored as given but expected in 'yyyy-MM-dd' (unambiguous,
%   sorts correctly, no locale confusion between mm/dd and dd/mm) --
%   convert at the UI boundary, not here.
%
%   patientId IS DERIVED, NOT CHOSEN. It is "<sanitized last>_<sanitized
%   first>", with a numeric suffix appended if that name is already taken
%   (e.g. two different patients named Smith, John) -- the profile.json
%   fields, not the id, are the source of truth for display, so the id
%   just needs to be a stable, unique folder name.
%
%   See also LIST_PATIENTS, ADD_VISIT_TO_PATIENT, LIST_PATIENT_VISITS.

p = inputParser;
p.addRequired('cfg',        @isstruct);
p.addRequired('lastName',   @(x) ischar(x) || isstring(x));
p.addRequired('firstName',  @(x) ischar(x) || isstring(x));
p.addRequired('dob',        @(x) ischar(x) || isstring(x));
p.addRequired('unitNumber', @(x) ischar(x) || isstring(x) || isnumeric(x));
p.parse(cfg, lastName, firstName, dob, unitNumber);

lastName  = strtrim(char(lastName));
firstName = strtrim(char(firstName));
if isempty(lastName) || isempty(firstName)
    error('create_patient_profile:missingName', 'Both last name and first name are required.');
end

sanitize = @(s) regexprep(strtrim(s), '[<>:"/\\|?*]', '_');
base = sprintf('%s_%s', sanitize(lastName), sanitize(firstName));

if ~exist(cfg.patientsDir, 'dir'); mkdir(cfg.patientsDir); end

patientId = base;
suffix = 2;
while exist(fullfile(cfg.patientsDir, patientId), 'dir') == 7
    patientId = sprintf('%s_%d', base, suffix);
    suffix = suffix + 1;
end

patientDir = fullfile(cfg.patientsDir, patientId);
mkdir(patientDir);
mkdir(fullfile(patientDir, 'visits'));

profile = struct( ...
    'patientId',   patientId, ...
    'lastName',    lastName, ...
    'firstName',   firstName, ...
    'dob',         char(dob), ...
    'unitNumber',  char(string(unitNumber)), ...
    'createdOn',   char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss')));

fid = fopen(fullfile(patientDir, 'profile.json'), 'w');
if fid < 0
    rmdir(patientDir, 's');
    error('create_patient_profile:cannotWrite', 'Could not write profile.json in:\n  %s', patientDir);
end
fprintf(fid, '%s', jsonencode(profile, 'PrettyPrint', true));
fclose(fid);

fprintf('Created patient profile "%s" (%s, %s)\n', patientId, lastName, firstName);
end
