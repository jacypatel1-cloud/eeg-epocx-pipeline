function visitPath = add_visit_to_patient(cfg, patientId, sourceFile, visitDate)
%ADD_VISIT_TO_PATIENT  Import one scan into a patient's visit history.
%
%   visitPath = add_visit_to_patient(cfg, patientId, sourceFile, visitDate)
%   creates data/patients/<patientId>/visits/<visitDate>/ and puts
%   sourceFile's contents there -- a zip is extracted (same idea as
%   IMPORT_DATASET_ZIP), anything else is copied in as-is.
%
%   visitDate is a datetime (or anything DATETIME accepts); the folder is
%   named 'yyyy-MM-dd' so visits sort correctly regardless of the display
%   format used elsewhere in the UI.
%
%   REFUSES A DUPLICATE VISIT DATE. Two visits landing on the same
%   calendar day for the same patient is almost always a mistake (the
%   wrong patient selected, or adding the same scan twice) -- pick a
%   different date, or remove the existing visit first if this is meant
%   to replace it. Same reasoning IMPORT_DATASET_ZIP already uses for a
%   name collision.
%
%   See also CREATE_PATIENT_PROFILE, LIST_PATIENT_VISITS.

p = inputParser;
p.addRequired('cfg',        @isstruct);
p.addRequired('patientId',  @(x) ischar(x) || isstring(x));
p.addRequired('sourceFile', @(x) ischar(x) || isstring(x));
p.addRequired('visitDate');
p.parse(cfg, patientId, sourceFile, visitDate);

patientId  = char(patientId);
sourceFile = char(sourceFile);

patientDir = fullfile(cfg.patientsDir, patientId);
if exist(patientDir, 'dir') ~= 7
    error('add_visit_to_patient:noSuchPatient', 'No patient folder:\n  %s', patientDir);
end
if exist(sourceFile, 'file') ~= 2
    error('add_visit_to_patient:fileNotFound', 'File not found:\n  %s', sourceFile);
end

dateStr = char(datetime(visitDate, 'Format', 'yyyy-MM-dd'));
visitPath = fullfile(patientDir, 'visits', dateStr);

if exist(visitPath, 'dir') == 7
    error('add_visit_to_patient:visitAlreadyExists', ...
        ['A visit dated %s already exists for this patient:\n  %s\n' ...
         'Choose a different date, or remove that visit first if this is meant to replace it.'], ...
        dateStr, visitPath);
end

mkdir(visitPath);
try
    [~, ~, ext] = fileparts(sourceFile);
    if strcmpi(ext, '.zip')
        unzip(sourceFile, visitPath);
    else
        copyfile(sourceFile, visitPath);
    end
catch ME
    rmdir(visitPath, 's');
    rethrow(ME);
end

fprintf('Added visit %s for patient "%s"\n  -> %s\n', dateStr, patientId, visitPath);
end
