function rows = list_patients(cfg)
%LIST_PATIENTS  Summarise every patient profile under data/patients.
%
%   rows = list_patients(cfg) returns a struct array, one entry per
%   data/patients/<patientId>/profile.json found, each with:
%       patientId, lastName, firstName, dob, unitNumber   (from profile.json)
%       nVisits         how many visits/<date>/ subfolders exist
%       lastVisitDate   datetime of the most recent visit, or NaT if none yet
%
%   Returns a 0x0 struct with those fields if data/patients has no patients
%   yet -- not an error, since that is the normal starting state.
%
%   See also CREATE_PATIENT_PROFILE, LIST_PATIENT_VISITS, ADD_VISIT_TO_PATIENT.

fields = {'patientId', 'lastName', 'firstName', 'dob', 'unitNumber', 'nVisits', 'lastVisitDate'};
rows = cell2struct(cell(numel(fields), 0), fields, 1);

if exist(cfg.patientsDir, 'dir') ~= 7
    return
end

entries = dir(cfg.patientsDir);
entries = entries([entries.isdir] & ~ismember({entries.name}, {'.', '..'}));
entries = entries(arrayfun(@(e) exist(fullfile(e.folder, e.name, 'profile.json'), 'file') == 2, entries));

if isempty(entries)
    return
end

rows(numel(entries)).patientId = '';
for k = 1:numel(entries)
    patientDir = fullfile(entries(k).folder, entries(k).name);
    profile = jsondecode(fileread(fullfile(patientDir, 'profile.json')));

    visits = list_patient_visits(cfg, entries(k).name);

    rows(k).patientId  = profile.patientId;
    rows(k).lastName   = profile.lastName;
    rows(k).firstName  = profile.firstName;
    rows(k).dob        = profile.dob;
    rows(k).unitNumber = profile.unitNumber;
    rows(k).nVisits    = numel(visits);
    if isempty(visits)
        rows(k).lastVisitDate = NaT;
    else
        rows(k).lastVisitDate = visits(end).date;
    end
end
end
