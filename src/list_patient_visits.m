function visits = list_patient_visits(cfg, patientId)
%LIST_PATIENT_VISITS  Every visit on file for one patient, oldest first.
%
%   visits = list_patient_visits(cfg, patientId) returns a struct array,
%   one entry per data/patients/<patientId>/visits/<date>/ subfolder:
%       date          datetime parsed from the folder name ('yyyy-MM-dd')
%       path          full path to that visit's folder
%       nRecordings   how many real recording files FIND_RECORDING_FILES
%                     finds inside it
%
%   Sorted oldest to newest, so "first visit" / "most recent visit" are
%   just rows(1) / rows(end) -- the same convention PICK_THREE uses for a
%   research dataset's recordings.
%
%   Returns a 0x0 struct with those fields if the patient has no visits yet.
%
%   See also CREATE_PATIENT_PROFILE, ADD_VISIT_TO_PATIENT, LIST_PATIENTS.

fields = {'date', 'path', 'nRecordings'};
visits = cell2struct(cell(numel(fields), 0), fields, 1);

visitsDir = fullfile(cfg.patientsDir, patientId, 'visits');
if exist(visitsDir, 'dir') ~= 7
    return
end

entries = dir(visitsDir);
entries = entries([entries.isdir] & ~ismember({entries.name}, {'.', '..'}));
if isempty(entries)
    return
end

visits(numel(entries)).date = NaT;
for k = 1:numel(entries)
    visitPath = fullfile(entries(k).folder, entries(k).name);
    try
        d = datetime(entries(k).name, 'InputFormat', 'yyyy-MM-dd');
    catch
        d = datetime(entries(k).datenum, 'ConvertFrom', 'datenum');
    end
    try
        nRec = numel(find_recording_files(visitPath));
    catch
        nRec = 0;
    end
    visits(k).date        = d;
    visits(k).path         = visitPath;
    visits(k).nRecordings  = nRec;
end

[~, order] = sort([visits.date]);
visits = visits(order);
end
