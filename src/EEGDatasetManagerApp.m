classdef EEGDatasetManagerApp < matlab.apps.AppBase
    %EEGDATASETMANAGERAPP  Interactive front end for the EEG pipeline.
    %
    %   app = EEGDatasetManagerApp() opens the dataset manager: add dataset
    %   zips, browse/rename/delete datasets and the files inside them, run
    %   the pipeline on a selected dataset, and view the first/second-to-
    %   last/last PSD comparison it produces.
    %
    %   app = EEGDatasetManagerApp(cfg) reuses an already-initialized paths
    %   struct from SETUP_PATHS (this is how LAUNCH_APP.m opens it, since it
    %   has already started EEGLAB). With no argument the app calls
    %   SETUP_PATHS itself on first display.
    %
    %   WHY THIS IS A HAND-WRITTEN CLASSDEF, NOT AN .mlapp FILE
    %   An .mlapp is a zipped binary container -- git can version it, but
    %   cannot usefully diff or merge it, and CLAUDE.md's git workflow
    %   depends on reviewable per-change history. A plain classdef App
    %   Designer app is ordinary text (this file can still be opened in App
    %   Designer directly, via `appdesigner('EEGDatasetManagerApp.m')`, if
    %   ever wanted) while staying fully diffable.
    %
    %   THIS APP CALLS EXISTING PIPELINE FUNCTIONS; IT DOES NOT REIMPLEMENT
    %   THEM. Adding a dataset calls IMPORT_DATASET_ZIP. Running the
    %   pipeline calls RUN_PIPELINE, unmodified, and just displays the PNG
    %   it already saves. Renaming/deleting call RENAME_DATASET /
    %   DELETE_DATASET. The point of this file is the UI, not the pipeline.
    %
    %   See also LAUNCH_APP, SETUP_PATHS, RUN_PIPELINE, LIST_DATASETS.

    % =====================================================================
    % Public component properties
    % =====================================================================
    properties (Access = public)
        UIFigure            matlab.ui.Figure
    end

    properties (Access = private)
        MainGrid            matlab.ui.container.GridLayout
        HeaderGrid          matlab.ui.container.GridLayout
        TitleLabel          matlab.ui.control.Label
        AddDatasetButton    matlab.ui.control.Button
        RefreshDatasetButton matlab.ui.control.Button

        BodyGrid            matlab.ui.container.GridLayout
        LeftPanel           matlab.ui.container.Panel
        LeftGrid            matlab.ui.container.GridLayout
        DatasetTable        matlab.ui.control.Table
        DatasetButtonGrid   matlab.ui.container.GridLayout
        RenameDatasetButton matlab.ui.control.Button
        DeleteDatasetButton matlab.ui.control.Button

        RightGrid           matlab.ui.container.GridLayout
        SelectedDatasetLabel matlab.ui.control.Label
        RightTabGroup       matlab.ui.container.TabGroup

        FilesTab            matlab.ui.container.Tab
        FileGrid            matlab.ui.container.GridLayout
        FileTable           matlab.ui.control.Table
        FileButtonGrid      matlab.ui.container.GridLayout
        AddFileButton       matlab.ui.control.Button
        RenameFileButton    matlab.ui.control.Button
        DeleteFileButton    matlab.ui.control.Button

        RunTab              matlab.ui.container.Tab
        RunGrid             matlab.ui.container.GridLayout
        RunButton           matlab.ui.control.Button
        RunStatusLabel      matlab.ui.control.Label
        LogTextArea         matlab.ui.control.TextArea

        ResultsTab          matlab.ui.container.Tab
        ResultsGrid         matlab.ui.container.GridLayout
        ResultsPlotGrid     matlab.ui.container.GridLayout
        ResultsAxes         matlab.ui.control.UIAxes  % 1x3: First / Second-to-last / Last
        FrequencyReadoutLabel matlab.ui.control.Label
        NoResultsLabel      matlab.ui.control.Label
        ResultsButtonGrid   matlab.ui.container.GridLayout
        OpenCleanedFolderButton matlab.ui.control.Button
        OpenFiguresFolderButton matlab.ui.control.Button
        OpenQCButton        matlab.ui.control.Button
        SaveGraphButton     matlab.ui.control.Button

        PrintTab            matlab.ui.container.Tab
        PrintGrid           matlab.ui.container.GridLayout
        PrintTable          matlab.ui.control.Table
        PrintSelectedButton matlab.ui.control.Button

        TrashTab            matlab.ui.container.Tab
        TrashGrid           matlab.ui.container.GridLayout
        TrashTable          matlab.ui.control.Table
        TrashButtonGrid     matlab.ui.container.GridLayout
        RestoreButton       matlab.ui.control.Button
        DeleteForeverButton matlab.ui.control.Button
        EmptyTrashButton    matlab.ui.control.Button
    end

    % =====================================================================
    % Data (not UI)
    % =====================================================================
    properties (Access = private)
        cfg                 = []    % struct from setup_paths()
        DatasetRows         = []    % struct array from list_datasets()
        SelectedDatasetName = ''    % char, name of the selected dataset row
        FileRows            = []    % dir()-style struct array, current dataset's files
        PrintRows           = []    % parse_recording_name() struct array, current dataset's recordings
        TrashRows           = []    % struct array from list_trash()
    end

    % =====================================================================
    % Colours -- one place, so the look stays consistent
    % =====================================================================
    properties (Access = private, Constant)
        ColorHeader = [0.13 0.20 0.33]
        ColorHeaderText = [1 1 1]
        ColorAccent = [0.16 0.45 0.75]
        ColorBg     = [0.95 0.96 0.97]
        ColorPanel  = [1 1 1]
        ColorDanger = [0.72 0.19 0.19]
    end

    % =====================================================================
    % Startup
    % =====================================================================
    methods (Access = private)

        function startupFcn(app)
            if isempty(app.cfg)
                app.RunStatusLabel.Text = 'Initializing EEGLAB (first run can take a moment)...';
                drawnow;
                evalc('cfgLocal = setup_paths();');
                app.cfg = cfgLocal;
            end
            app.refreshDatasetTable();
            app.refreshResultsTab();
            app.refreshTrashTable();
            app.RunStatusLabel.Text = 'Idle.';
        end

    end

    % =====================================================================
    % Dataset list (left panel)
    % =====================================================================
    methods (Access = private)

        function refreshDatasetTable(app)
            app.DatasetRows = list_datasets(app.cfg);

            if isempty(app.DatasetRows)
                app.DatasetTable.Data = cell(0, 4);
            else
                n = numel(app.DatasetRows);
                data = cell(n, 4);
                for i = 1:n
                    r = app.DatasetRows(i);
                    data{i,1} = r.name;
                    data{i,2} = r.nRecordings;
                    data{i,3} = app.formatBytes(r.nBytes);
                    data{i,4} = char(r.modified, 'dd-MMM-uuuu HH:mm');
                end
                app.DatasetTable.Data = data;
            end

            % Keep the current selection if it still exists; otherwise clear it.
            if ~isempty(app.SelectedDatasetName) && ...
               any(strcmp({app.DatasetRows.name}, app.SelectedDatasetName))
                app.selectDatasetByName(app.SelectedDatasetName);
            else
                app.SelectedDatasetName = '';
                app.SelectedDatasetLabel.Text = 'No dataset selected';
                app.FileRows = [];
                app.FileTable.Data = cell(0, 3);
                app.PrintRows = [];
                app.PrintTable.Data = cell(0, 3);
            end
        end

        function selectDatasetByName(app, name)
            app.SelectedDatasetName = name;
            app.SelectedDatasetLabel.Text = sprintf('Selected dataset: %s', name);

            idx = find(strcmp({app.DatasetRows.name}, name), 1);
            if ~isempty(idx)
                app.DatasetTable.Selection = idx;
            end

            app.refreshFileTable();
            app.refreshResultsTab();
            app.refreshPrintTable();
            app.RunStatusLabel.Text = 'Idle.';
            app.LogTextArea.Value = {''};
        end

        function DatasetTableCellSelection(app, event)
            if isempty(event.Indices)
                return
            end
            row = event.Indices(1, 1);
            if row >= 1 && row <= numel(app.DatasetRows)
                app.selectDatasetByName(app.DatasetRows(row).name);
            end
        end

        function AddDatasetButtonPushed(app, ~)
            [files, folder] = uigetfile({'*.zip', 'Zip files (*.zip)'}, ...
                'Select one or more dataset zip files', 'MultiSelect', 'on');
            if isequal(files, 0)
                return
            end
            if ischar(files)
                files = {files};
            end

            okNames  = {};
            failures = {};
            for i = 1:numel(files)
                zipPath = fullfile(folder, files{i});
                try
                    datasetDir = import_dataset_zip(zipPath);
                    [~, nm] = fileparts(datasetDir);
                    okNames{end+1} = nm; %#ok<AGROW>
                catch ME
                    failures{end+1} = sprintf('%s: %s', files{i}, ME.message); %#ok<AGROW>
                end
            end

            app.refreshDatasetTable();
            if ~isempty(okNames)
                app.selectDatasetByName(okNames{end});
            end

            if ~isempty(failures)
                uialert(app.UIFigure, strjoin(failures, newline), ...
                    'Some zip files could not be imported', 'Icon', 'warning');
            end
        end

        function RefreshDatasetButtonPushed(app, ~)
            app.refreshDatasetTable();
        end

        function RenameDatasetButtonPushed(app, ~)
            if isempty(app.SelectedDatasetName)
                uialert(app.UIFigure, 'Select a dataset first.', 'No dataset selected');
                return
            end
            answer = inputdlg('New name:', 'Rename Dataset', 1, {app.SelectedDatasetName});
            if isempty(answer) || isempty(strtrim(answer{1}))
                return
            end
            try
                newPath = rename_dataset(app.cfg, app.SelectedDatasetName, answer{1});
                [~, newName] = fileparts(newPath);
                app.refreshDatasetTable();
                app.selectDatasetByName(newName);
            catch ME
                uialert(app.UIFigure, ME.message, 'Rename failed', 'Icon', 'error');
            end
        end

        function DeleteDatasetButtonPushed(app, ~)
            if isempty(app.SelectedDatasetName)
                uialert(app.UIFigure, 'Select a dataset first.', 'No dataset selected');
                return
            end
            name = app.SelectedDatasetName;
            choice = uiconfirm(app.UIFigure, ...
                sprintf(['Move dataset "%s" and every file inside it to the trash?\n\n' ...
                         'It can be restored later from the Trash tab. Anything already ' ...
                         'processed from it in data/processed, figures/ or results/ is ' ...
                         'NOT affected.'], name), ...
                'Delete Dataset', 'Options', {'Move to Trash', 'Cancel'}, ...
                'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
            if ~strcmp(choice, 'Move to Trash')
                return
            end
            try
                delete_dataset(app.cfg, name);
                app.SelectedDatasetName = '';
                app.refreshDatasetTable();
                app.refreshTrashTable();
            catch ME
                uialert(app.UIFigure, ME.message, 'Delete failed', 'Icon', 'error');
            end
        end

    end

    % =====================================================================
    % Files tab (right panel)
    % =====================================================================
    methods (Access = private)

        function refreshFileTable(app)
            if isempty(app.SelectedDatasetName)
                app.FileRows = [];
                app.FileTable.Data = cell(0, 3);
                return
            end

            dsPath = fullfile(app.cfg.rawDir, app.SelectedDatasetName);
            listing = dir(fullfile(dsPath, '**', '*'));
            listing = listing(~[listing.isdir]);
            app.FileRows = listing;

            n = numel(listing);
            data = cell(n, 3);
            for i = 1:n
                relFolder = erase(listing(i).folder, dsPath);
                relFolder = strrep(relFolder, filesep, '/');
                relFolder = regexprep(relFolder, '^/', '');
                if isempty(relFolder)
                    data{i,1} = listing(i).name;
                else
                    data{i,1} = [relFolder '/' listing(i).name];
                end
                [~, ~, ext] = fileparts(listing(i).name);
                data{i,2} = ext;
                data{i,3} = app.formatBytes(listing(i).bytes);
            end
            app.FileTable.Data = data;
        end

        function AddFileButtonPushed(app, ~)
            if isempty(app.SelectedDatasetName)
                uialert(app.UIFigure, 'Select a dataset first.', 'No dataset selected');
                return
            end
            [files, folder] = uigetfile('*.*', 'Select file(s) to add to this dataset', ...
                'MultiSelect', 'on');
            if isequal(files, 0)
                return
            end
            if ischar(files)
                files = {files};
            end

            dsPath = fullfile(app.cfg.rawDir, app.SelectedDatasetName);
            failures = {};
            for i = 1:numel(files)
                src = fullfile(folder, files{i});
                dst = fullfile(dsPath, files{i});
                if exist(dst, 'file') == 2
                    failures{end+1} = sprintf('%s: already exists in this dataset', files{i}); %#ok<AGROW>
                    continue
                end
                try
                    copyfile(src, dst);
                catch ME
                    failures{end+1} = sprintf('%s: %s', files{i}, ME.message); %#ok<AGROW>
                end
            end

            app.refreshFileTable();
            app.refreshDatasetTable();
            if ~isempty(failures)
                uialert(app.UIFigure, strjoin(failures, newline), ...
                    'Some files could not be added', 'Icon', 'warning');
            end
        end

        function DeleteFileButtonPushed(app, ~)
            row = app.selectedFileRow();
            if isempty(row)
                uialert(app.UIFigure, 'Select a file first.', 'No file selected');
                return
            end
            f = app.FileRows(row);
            fullPath = fullfile(f.folder, f.name);
            choice = uiconfirm(app.UIFigure, sprintf('Move "%s" to trash?', f.name), ...
                'Delete File', 'Options', {'Move to Trash', 'Cancel'}, ...
                'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
            if ~strcmp(choice, 'Move to Trash')
                return
            end
            try
                move_to_trash(app.cfg, fullPath);
            catch ME
                uialert(app.UIFigure, ME.message, 'Delete failed', 'Icon', 'error');
            end
            app.refreshFileTable();
            app.refreshDatasetTable();
            app.refreshTrashTable();
        end

        function RenameFileButtonPushed(app, ~)
            row = app.selectedFileRow();
            if isempty(row)
                uialert(app.UIFigure, 'Select a file first.', 'No file selected');
                return
            end
            f = app.FileRows(row);
            answer = inputdlg('New file name:', 'Rename File', 1, {f.name});
            if isempty(answer) || isempty(strtrim(answer{1}))
                return
            end
            newName = regexprep(strtrim(answer{1}), '[<>:"/\\|?*]', '_');
            newPath = fullfile(f.folder, newName);
            if exist(newPath, 'file') == 2
                uialert(app.UIFigure, sprintf('"%s" already exists.', newName), 'Rename failed');
                return
            end
            try
                movefile(fullfile(f.folder, f.name), newPath);
            catch ME
                uialert(app.UIFigure, ME.message, 'Rename failed', 'Icon', 'error');
            end
            app.refreshFileTable();
        end

        function row = selectedFileRow(app)
            row = [];
            sel = app.FileTable.Selection;
            if isempty(sel)
                return
            end
            row = sel(1, 1);
            if row < 1 || row > numel(app.FileRows)
                row = [];
            end
        end

    end

    % =====================================================================
    % Print tab
    % =====================================================================
    methods (Access = private)

        function refreshPrintTable(app)
            if isempty(app.SelectedDatasetName)
                app.PrintRows = [];
                app.PrintTable.Data = cell(0, 3);
                return
            end

            dsPath = fullfile(app.cfg.rawDir, app.SelectedDatasetName);
            try
                listing = find_recording_files(dsPath);
            catch
                listing = [];
            end

            if isempty(listing)
                app.PrintRows = [];
                app.PrintTable.Data = cell(0, 3);
                return
            end

            infos = arrayfun(@(d) parse_recording_name(fullfile(d.folder, d.name)), listing);
            app.PrintRows = infos;

            n = numel(infos);
            data = cell(n, 3);
            for i = 1:n
                pngPath = app.psdPngPathFor(infos(i).name);
                data{i,1} = false;
                data{i,2} = infos(i).name;
                if exist(pngPath, 'file') == 2
                    data{i,3} = 'Ready to print';
                else
                    data{i,3} = 'Not yet run';
                end
            end
            app.PrintTable.Data = data;
        end

        function PrintSelectedButtonPushed(app, ~)
            if isempty(app.PrintRows)
                uialert(app.UIFigure, 'Select a dataset first.', 'Nothing to print');
                return
            end

            checkedCol = app.PrintTable.Data(:,1);
            checked = find(cellfun(@(v) islogical(v) && v, checkedCol));
            if isempty(checked)
                uialert(app.UIFigure, 'Check one or more recordings first.', 'Nothing selected');
                return
            end

            notReady = {};
            for idx = checked(:)'
                name    = app.PrintRows(idx).name;
                pngPath = app.psdPngPathFor(name);
                if exist(pngPath, 'file') == 2
                    winopen(pngPath);
                else
                    notReady{end+1} = name; %#ok<AGROW>
                end
            end

            if ~isempty(notReady)
                uialert(app.UIFigure, sprintf(['These recordings have not been run yet, so there is ' ...
                    'no PSD image to print -- run the pipeline first:\n\n%s'], strjoin(notReady, newline)), ...
                    'Some Recordings Not Ready', 'Icon', 'warning');
            end
        end

        function pngPath = psdPngPathFor(app, recordingName)
            %PSDPNGPATHFOR  Where RUN_PIPELINE('PlotEach',true) saves a
            %   recording's individual PSD image -- must match
            %   PLOT_PSD_STACK's own naming (safe-name + '_psdstack.png',
            %   no tag) exactly, or the Print tab would never find it.
            pngPath = fullfile(app.cfg.figDir, [matlab.lang.makeValidName(recordingName) '_psdstack.png']);
        end

    end

    % =====================================================================
    % Trash tab -- global (not scoped to the selected dataset)
    % =====================================================================
    methods (Access = private)

        function refreshTrashTable(app)
            rows = list_trash(app.cfg);
            app.TrashRows = rows;

            n = numel(rows);
            data = cell(n, 4);
            for i = 1:n
                displayName = regexprep(rows(i).name, '__trashed_\d{8}_\d{6}$', '');
                data{i,1} = displayName;
                if rows(i).isDir
                    data{i,2} = 'Dataset';
                else
                    data{i,2} = 'File';
                end
                data{i,3} = char(rows(i).trashedOn, 'dd-MMM-uuuu HH:mm');
                data{i,4} = char(rows(i).originalPath);
            end
            app.TrashTable.Data = data;
        end

        function row = selectedTrashRow(app)
            row = [];
            sel = app.TrashTable.Selection;
            if isempty(sel)
                return
            end
            row = sel(1, 1);
            if row < 1 || row > numel(app.TrashRows)
                row = [];
            end
        end

        function RestoreButtonPushed(app, ~)
            row = app.selectedTrashRow();
            if isempty(row)
                uialert(app.UIFigure, 'Select a trashed item first.', 'Nothing selected');
                return
            end
            entryName = app.TrashRows(row).name;
            try
                restore_from_trash(app.cfg, entryName);
            catch ME
                uialert(app.UIFigure, ME.message, 'Restore failed', 'Icon', 'error');
            end
            app.refreshTrashTable();
            app.refreshDatasetTable();
        end

        function DeleteForeverButtonPushed(app, ~)
            row = app.selectedTrashRow();
            if isempty(row)
                uialert(app.UIFigure, 'Select a trashed item first.', 'Nothing selected');
                return
            end
            entryName = app.TrashRows(row).name;
            choice = uiconfirm(app.UIFigure, ...
                sprintf('Permanently delete "%s"?\n\nThis cannot be undone -- there is no trash for the trash.', ...
                        regexprep(entryName, '__trashed_\d{8}_\d{6}$', '')), ...
                'Delete Forever', 'Options', {'Delete Forever', 'Cancel'}, ...
                'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
            if ~strcmp(choice, 'Delete Forever')
                return
            end
            try
                permanently_delete_trash_item(app.cfg, entryName);
            catch ME
                uialert(app.UIFigure, ME.message, 'Delete failed', 'Icon', 'error');
            end
            app.refreshTrashTable();
        end

        function EmptyTrashButtonPushed(app, ~)
            if isempty(app.TrashRows)
                uialert(app.UIFigure, 'Trash is already empty.', 'Nothing to empty');
                return
            end
            n = numel(app.TrashRows);
            choice = uiconfirm(app.UIFigure, ...
                sprintf(['Permanently delete all %d item(s) in the trash?\n\n' ...
                         'This cannot be undone.'], n), ...
                'Empty Trash', 'Options', {'Empty Trash', 'Cancel'}, ...
                'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
            if ~strcmp(choice, 'Empty Trash')
                return
            end
            failures = {};
            for i = 1:n
                try
                    permanently_delete_trash_item(app.cfg, app.TrashRows(i).name);
                catch ME
                    failures{end+1} = sprintf('%s: %s', app.TrashRows(i).name, ME.message); %#ok<AGROW>
                end
            end
            app.refreshTrashTable();
            if ~isempty(failures)
                uialert(app.UIFigure, strjoin(failures, newline), 'Some items could not be deleted', ...
                    'Icon', 'warning');
            end
        end

    end

    % =====================================================================
    % Run Pipeline tab
    % =====================================================================
    methods (Access = private)

        function RunPipelineButtonPushed(app, ~)
            if isempty(app.SelectedDatasetName)
                uialert(app.UIFigure, 'Select a dataset first.', 'No dataset selected');
                return
            end

            name   = app.SelectedDatasetName;
            dsPath = fullfile(app.cfg.rawDir, name);

            % .dat is a headerless numeric matrix -- IMPORT_MATRIX_DAT
            % deliberately refuses to guess its sample rate or channel
            % order (see that file), so RUN_PIPELINE cannot import one
            % without ImportOptions supplied. Ask here, once, rather than
            % having every such dataset just fail with no way to proceed.
            importOptions = {};
            if ~isempty(dir(fullfile(dsPath, '**', '*.dat')))
                choice = uiconfirm(app.UIFigure, ...
                    sprintf(['"%s" contains .dat recordings, which carry no sample ' ...
                             'rate or channel order of their own.\n\n' ...
                             'What sample rate were these recorded at?'], name), ...
                    'Sample Rate Needed', ...
                    'Options', {'128 Hz (standard)', '256 Hz (high-rate mode)', 'Cancel'}, ...
                    'DefaultOption', 1, 'CancelOption', 3);
                switch choice
                    case '128 Hz (standard)'
                        rateHz = 128;
                    case '256 Hz (high-rate mode)'
                        rateHz = 256;
                    otherwise
                        return
                end
                % Channel order is assumed to be this project's fixed EPOC X
                % montage (cfg.channels) since the file itself cannot say --
                % ChannelOrderSource records that assumption rather than
                % hiding it, per IMPORT_MATRIX_DAT's provenance contract.
                importOptions = {'SampleRate', rateHz, 'ChannelOrder', app.cfg.channels, ...
                    'ChannelOrderSource', ['ASSUMED: canonical EPOC X order (fixed 14-' ...
                    'channel montage), confirmed via Dataset Manager sample-rate prompt, ' ...
                    'not documented by the source file']};
            end

            app.RunStatusLabel.Text = sprintf('Running pipeline on "%s"...', name);
            app.LogTextArea.Value = {''};
            drawnow;

            d = uiprogressdlg(app.UIFigure, 'Title', 'Running Pipeline', ...
                'Message', sprintf('Processing "%s" -- this can take a while for a large dataset.', name), ...
                'Indeterminate', 'on');
            cleanupObj = onCleanup(@() close(d));

            try
                % Visible=false: run_pipeline's own comparison/per-recording
                % figures are suppressed on screen -- this Results tab already
                % shows the saved PNG, so a second pop-up window would just be
                % a redundant copy of the same figure, not additional information.
                % PlotEach=true: also save one PSD PNG per recording (not just
                % the three-way comparison), so the Print tab has something to
                % open for any recording the user selects there.
                cmd = sprintf(['resultsLocal = run_pipeline(''Dataset'', %s, ' ...
                    '''ImportOptions'', importOptionsLocal, ''Visible'', false, ' ...
                    '''PlotEach'', true);'], mat2str(name));
                importOptionsLocal = importOptions; %#ok<NASGU> % read by evalc below
                captured = evalc(cmd);

                nTotal = numel(resultsLocal); %#ok<NODEF>
                okMask = [resultsLocal.ok];
                nOk    = sum(okMask);
                nFail  = nTotal - nOk;

                % "Unusable" is QC's usable==false on a recording that DID
                % import and process -- distinct from nFail (didn't even get
                % that far). Both mean "can't use this recording's result",
                % so both count toward the percentage shown to the user.
                nUnusableOk = 0;
                okIdx = find(okMask);
                for k = okIdx
                    if ~isempty(resultsLocal(k).qc) && isfield(resultsLocal(k).qc, 'usable') ...
                            && ~resultsLocal(k).qc.usable
                        nUnusableOk = nUnusableOk + 1;
                    end
                end
                nBad    = nFail + nUnusableOk;
                pctBad  = 100 * nBad / max(nTotal, 1);

                app.LogTextArea.Value = strsplit(captured, newline);
                app.refreshPrintTable();   % PlotEach just saved a PNG per recording

                proceed = true;
                if nBad > 0
                    detailLines = {};
                    if nFail > 0
                        detailLines{end+1} = sprintf('%d failed to process entirely.', nFail); %#ok<AGROW>
                    end
                    if nUnusableOk > 0
                        detailLines{end+1} = sprintf(['%d processed but were flagged unusable by ' ...
                            'quality control (too noisy, too few clean epochs, or too many bad ' ...
                            'channels -- see results/qc_summary.csv for exactly why each one).'], ...
                            nUnusableOk); %#ok<AGROW>
                    end
                    choice = uiconfirm(app.UIFigure, ...
                        sprintf(['%.0f%% of this dataset (%d of %d recordings) is unusable:\n\n%s\n\n' ...
                                 'View the results anyway?'], ...
                                pctBad, nBad, nTotal, strjoin(detailLines, '\n')), ...
                        'Some Data Is Unusable', ...
                        'Options', {'Yes', 'No'}, 'DefaultOption', 1, 'CancelOption', 2, ...
                        'Icon', 'warning');
                    proceed = strcmp(choice, 'Yes');
                end

                if proceed
                    app.RunStatusLabel.Text = sprintf('Done: %d succeeded, %d failed.', nOk, nFail);
                    app.refreshResultsTab();
                else
                    app.RunStatusLabel.Text = sprintf(['Done: %d succeeded, %d failed -- results not ' ...
                        'shown (declined).'], nOk, nFail);
                end
            catch ME
                app.RunStatusLabel.Text = 'Pipeline failed -- see log.';
                app.LogTextArea.Value = strsplit(sprintf('ERROR: %s', ME.message), newline);
                uialert(app.UIFigure, ME.message, 'Pipeline Error', 'Icon', 'error');
            end
        end

    end

    % =====================================================================
    % Results tab
    % =====================================================================
    methods (Access = private)

        function refreshResultsTab(app)
            % Live, interactive redraw (not the saved PNG) -- specs are
            % reloaded from results/psd_<name>.mat rather than only kept in
            % memory from the last run, so reselecting a dataset processed in
            % an earlier session still shows an interactive comparison, not
            % just whatever the last run in THIS session happened to be.
            [specs, labels, ok] = app.loadComparisonSpecsForDataset(app.SelectedDatasetName);

            if ok
                try
                    compare_recordings(specs, app.cfg, 'Titles', labels, ...
                        'TargetAxes', app.ResultsAxes, 'Save', false);
                    app.ResultsPlotGrid.Visible = 'on';
                    app.NoResultsLabel.Visible = 'off';
                catch ME
                    ok = false;
                    uialert(app.UIFigure, ME.message, 'Could not draw comparison', 'Icon', 'error');
                end
            end

            if ~ok
                app.ResultsPlotGrid.Visible = 'off';
                app.NoResultsLabel.Visible = 'on';
                app.FrequencyReadoutLabel.Text = 'Frequency: --';
            end
        end

        function OpenCleanedFolderButtonPushed(app, ~)
            if exist(app.cfg.procDir, 'dir') == 7
                winopen(app.cfg.procDir);
            else
                uialert(app.UIFigure, 'No cleaned data yet -- run the pipeline first.', 'Nothing to open');
            end
        end

        function OpenFiguresFolderButtonPushed(app, ~)
            if exist(app.cfg.figDir, 'dir') == 7
                winopen(app.cfg.figDir);
            else
                uialert(app.UIFigure, 'No figures yet -- run the pipeline first.', 'Nothing to open');
            end
        end

        function OpenQCButtonPushed(app, ~)
            qcPath = fullfile(app.cfg.resultDir, 'qc_summary.csv');
            if exist(qcPath, 'file') == 2
                winopen(qcPath);
            else
                uialert(app.UIFigure, 'No QC summary yet -- run the pipeline first.', 'Nothing to open');
            end
        end

        function SaveGraphButtonPushed(app, ~)
            pngPath = fullfile(app.cfg.figDir, 'comparison_first_secondlast_last.png');
            if exist(pngPath, 'file') ~= 2
                uialert(app.UIFigure, 'No comparison figure yet -- run the pipeline first.', 'Nothing to save');
                return
            end
            [file, folder] = uiputfile('*.png', 'Save comparison figure as', ...
                'comparison_first_secondlast_last.png');
            if isequal(file, 0)
                return
            end
            try
                copyfile(pngPath, fullfile(folder, file));
            catch ME
                uialert(app.UIFigure, ME.message, 'Save failed', 'Icon', 'error');
            end
        end

        function [specs, labels, ok] = loadComparisonSpecsForDataset(app, name)
            %LOADCOMPARISONSPECSFORDATASET  Reload the first/second-to-last/
            %   last spectra for NAME from results/psd_*.mat, the same
            %   selection RUN_PIPELINE's own comparison figure uses. Reading
            %   from disk (rather than only trusting whatever is left over in
            %   memory from the last run) means this also works right after
            %   reselecting a dataset that was processed in an earlier session.
            specs = []; labels = {}; ok = false;
            if isempty(name)
                return
            end

            dsPath = fullfile(app.cfg.rawDir, name);
            try
                listing = find_recording_files(dsPath);
            catch
                return
            end
            if isempty(listing)
                return
            end
            infos = arrayfun(@(d) parse_recording_name(fullfile(d.folder, d.name)), listing);

            hasSpec = false(size(infos));
            for i = 1:numel(infos)
                hasSpec(i) = exist(app.psdMatPathFor(infos(i).name), 'file') == 2;
            end
            infos = infos(hasSpec);
            if isempty(infos)
                return
            end

            try
                [sel, labelsOut] = pick_three(infos);
            catch
                return
            end

            specsOut = [];
            for k = 1:numel(sel)
                loaded = load(app.psdMatPathFor(infos(sel(k)).name), 'S');
                if isempty(specsOut)
                    specsOut = loaded.S;
                else
                    specsOut(end+1) = loaded.S; %#ok<AGROW>
                end
            end

            specs = specsOut;
            labels = labelsOut;
            ok = true;
        end

        function matPath = psdMatPathFor(app, recordingName)
            %PSDMATPATHFOR  Where RUN_PIPELINE saves a recording's spectrum
            %   -- must match its own naming exactly (results/psd_<safe
            %   name>.mat) or specs would never be found on reselect.
            matPath = fullfile(app.cfg.resultDir, ['psd_' matlab.lang.makeValidName(recordingName) '.mat']);
        end

        function ResultsMouseMoved(app, ~)
            %RESULTSMOUSEMOVED  Show the exact Hz under the cursor.
            %
            %   Wired to the whole figure's WindowButtonMotionFcn (uiaxes has
            %   no per-axes hover event of its own in App Designer). For each
            %   of the three comparison axes, MATLAB continuously updates
            %   CurrentPoint to where the pointer would land in THAT axes'
            %   data coordinates, even when the pointer isn't actually over
            %   it -- so "is the pointer really over this axes" is decided by
            %   checking the projected point against the axes' own current
            %   XLim/YLim, not by pixel geometry.
            if isempty(app.SelectedDatasetName) || strcmp(app.ResultsPlotGrid.Visible, 'off')
                return
            end

            hz = NaN;
            for i = 1:numel(app.ResultsAxes)
                ax = app.ResultsAxes(i);
                if ~isvalid(ax)
                    continue
                end
                cp = ax.CurrentPoint;
                x  = cp(1,1); y = cp(1,2);
                xl = ax.XLim; yl = ax.YLim;
                if x >= xl(1) && x <= xl(2) && y >= yl(1) && y <= yl(2)
                    hz = x;
                    break
                end
            end

            if isnan(hz)
                app.FrequencyReadoutLabel.Text = 'Frequency: --';
            else
                app.FrequencyReadoutLabel.Text = sprintf('Frequency: %.2f Hz', max(0, min(20, hz)));
            end
        end

    end

    % =====================================================================
    % Small formatting helper
    % =====================================================================
    methods (Static, Access = private)

        function s = formatBytes(n)
            if n >= 1e9
                s = sprintf('%.2f GB', n / 1e9);
            elseif n >= 1e6
                s = sprintf('%.1f MB', n / 1e6);
            elseif n >= 1e3
                s = sprintf('%.0f KB', n / 1e3);
            else
                s = sprintf('%d B', n);
            end
        end

    end

    % =====================================================================
    % Component creation
    % =====================================================================
    methods (Access = private)

        function createComponents(app)
            screen = get(0, 'ScreenSize');
            w = 1200; h = 780;
            x = max(50, (screen(3) - w) / 2);
            y = max(50, (screen(4) - h) / 2);

            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [x y w h];
            app.UIFigure.Name = 'EEG Dataset Manager';
            app.UIFigure.Color = app.ColorBg;

            app.MainGrid = uigridlayout(app.UIFigure, [2 1]);
            app.MainGrid.RowHeight = {64, '1x'};
            app.MainGrid.ColumnWidth = {'1x'};
            app.MainGrid.Padding = [12 12 12 12];
            app.MainGrid.RowSpacing = 10;
            app.MainGrid.BackgroundColor = app.ColorBg;

            % --- Header -------------------------------------------------
            app.HeaderGrid = uigridlayout(app.MainGrid, [1 3]);
            app.HeaderGrid.Layout.Row = 1;
            app.HeaderGrid.Layout.Column = 1;
            app.HeaderGrid.ColumnWidth = {'1x', 200, 110};
            app.HeaderGrid.RowHeight = {'1x'};
            app.HeaderGrid.Padding = [16 4 16 4];
            app.HeaderGrid.BackgroundColor = app.ColorHeader;

            app.TitleLabel = uilabel(app.HeaderGrid);
            app.TitleLabel.Text = 'EEG Dataset Manager';
            app.TitleLabel.FontSize = 20;
            app.TitleLabel.FontWeight = 'bold';
            app.TitleLabel.FontColor = app.ColorHeaderText;
            app.TitleLabel.Layout.Row = 1;
            app.TitleLabel.Layout.Column = 1;

            app.AddDatasetButton = uibutton(app.HeaderGrid, 'push');
            app.AddDatasetButton.Text = '+ Add Dataset(s)...';
            app.AddDatasetButton.FontWeight = 'bold';
            app.AddDatasetButton.BackgroundColor = app.ColorAccent;
            app.AddDatasetButton.FontColor = [1 1 1];
            app.AddDatasetButton.Layout.Row = 1;
            app.AddDatasetButton.Layout.Column = 2;
            app.AddDatasetButton.ButtonPushedFcn = @(src, event) app.AddDatasetButtonPushed(event);

            app.RefreshDatasetButton = uibutton(app.HeaderGrid, 'push');
            app.RefreshDatasetButton.Text = 'Refresh';
            app.RefreshDatasetButton.Layout.Row = 1;
            app.RefreshDatasetButton.Layout.Column = 3;
            app.RefreshDatasetButton.ButtonPushedFcn = @(src, event) app.RefreshDatasetButtonPushed(event);

            % --- Body: left dataset list, right tabs ---------------------
            app.BodyGrid = uigridlayout(app.MainGrid, [1 2]);
            app.BodyGrid.Layout.Row = 2;
            app.BodyGrid.Layout.Column = 1;
            app.BodyGrid.ColumnWidth = {400, '1x'};
            app.BodyGrid.RowHeight = {'1x'};
            app.BodyGrid.ColumnSpacing = 10;
            app.BodyGrid.Padding = [0 0 0 0];
            app.BodyGrid.BackgroundColor = app.ColorBg;

            % Left panel: dataset table + actions
            app.LeftPanel = uipanel(app.BodyGrid);
            app.LeftPanel.Layout.Row = 1;
            app.LeftPanel.Layout.Column = 1;
            app.LeftPanel.Title = 'Datasets (data/raw)';
            app.LeftPanel.BackgroundColor = app.ColorPanel;

            app.LeftGrid = uigridlayout(app.LeftPanel, [2 1]);
            app.LeftGrid.RowHeight = {'1x', 40};
            app.LeftGrid.ColumnWidth = {'1x'};

            app.DatasetTable = uitable(app.LeftGrid);
            app.DatasetTable.Layout.Row = 1;
            app.DatasetTable.Layout.Column = 1;
            app.DatasetTable.ColumnName = {'Name', 'Recordings', 'Size', 'Modified'};
            app.DatasetTable.ColumnWidth = {130, 80, 70, 130};
            app.DatasetTable.Data = cell(0, 4);
            app.DatasetTable.SelectionType = 'row';
            app.DatasetTable.CellSelectionCallback = @(src, event) app.DatasetTableCellSelection(event);

            app.DatasetButtonGrid = uigridlayout(app.LeftGrid, [1 2]);
            app.DatasetButtonGrid.Layout.Row = 2;
            app.DatasetButtonGrid.Layout.Column = 1;
            app.DatasetButtonGrid.ColumnWidth = {'1x', '1x'};
            app.DatasetButtonGrid.Padding = [0 0 0 0];

            app.RenameDatasetButton = uibutton(app.DatasetButtonGrid, 'push');
            app.RenameDatasetButton.Text = 'Rename';
            app.RenameDatasetButton.Layout.Row = 1;
            app.RenameDatasetButton.Layout.Column = 1;
            app.RenameDatasetButton.ButtonPushedFcn = @(src, event) app.RenameDatasetButtonPushed(event);

            app.DeleteDatasetButton = uibutton(app.DatasetButtonGrid, 'push');
            app.DeleteDatasetButton.Text = 'Delete';
            app.DeleteDatasetButton.BackgroundColor = app.ColorDanger;
            app.DeleteDatasetButton.FontColor = [1 1 1];
            app.DeleteDatasetButton.Layout.Row = 1;
            app.DeleteDatasetButton.Layout.Column = 2;
            app.DeleteDatasetButton.ButtonPushedFcn = @(src, event) app.DeleteDatasetButtonPushed(event);

            % Right side: selected-dataset label + tab group
            app.RightGrid = uigridlayout(app.BodyGrid, [2 1]);
            app.RightGrid.Layout.Row = 1;
            app.RightGrid.Layout.Column = 2;
            app.RightGrid.RowHeight = {26, '1x'};
            app.RightGrid.Padding = [0 0 0 0];
            app.RightGrid.RowSpacing = 6;
            app.RightGrid.BackgroundColor = app.ColorBg;

            app.SelectedDatasetLabel = uilabel(app.RightGrid);
            app.SelectedDatasetLabel.Text = 'No dataset selected';
            app.SelectedDatasetLabel.FontWeight = 'bold';
            app.SelectedDatasetLabel.FontSize = 13;
            app.SelectedDatasetLabel.Layout.Row = 1;
            app.SelectedDatasetLabel.Layout.Column = 1;

            app.RightTabGroup = uitabgroup(app.RightGrid);
            app.RightTabGroup.Layout.Row = 2;
            app.RightTabGroup.Layout.Column = 1;

            % --- Files tab ------------------------------------------------
            app.FilesTab = uitab(app.RightTabGroup, 'Title', 'Files');

            app.FileGrid = uigridlayout(app.FilesTab, [2 1]);
            app.FileGrid.RowHeight = {'1x', 40};
            app.FileGrid.ColumnWidth = {'1x'};

            app.FileTable = uitable(app.FileGrid);
            app.FileTable.Layout.Row = 1;
            app.FileTable.Layout.Column = 1;
            app.FileTable.ColumnName = {'File', 'Type', 'Size'};
            app.FileTable.ColumnWidth = {'1x', 80, 80};
            app.FileTable.Data = cell(0, 3);
            app.FileTable.SelectionType = 'row';

            app.FileButtonGrid = uigridlayout(app.FileGrid, [1 3]);
            app.FileButtonGrid.Layout.Row = 2;
            app.FileButtonGrid.Layout.Column = 1;
            app.FileButtonGrid.ColumnWidth = {'1x', '1x', '1x'};
            app.FileButtonGrid.Padding = [0 0 0 0];

            app.AddFileButton = uibutton(app.FileButtonGrid, 'push');
            app.AddFileButton.Text = 'Add File(s)...';
            app.AddFileButton.Layout.Row = 1;
            app.AddFileButton.Layout.Column = 1;
            app.AddFileButton.ButtonPushedFcn = @(src, event) app.AddFileButtonPushed(event);

            app.RenameFileButton = uibutton(app.FileButtonGrid, 'push');
            app.RenameFileButton.Text = 'Rename';
            app.RenameFileButton.Layout.Row = 1;
            app.RenameFileButton.Layout.Column = 2;
            app.RenameFileButton.ButtonPushedFcn = @(src, event) app.RenameFileButtonPushed(event);

            app.DeleteFileButton = uibutton(app.FileButtonGrid, 'push');
            app.DeleteFileButton.Text = 'Delete';
            app.DeleteFileButton.BackgroundColor = app.ColorDanger;
            app.DeleteFileButton.FontColor = [1 1 1];
            app.DeleteFileButton.Layout.Row = 1;
            app.DeleteFileButton.Layout.Column = 3;
            app.DeleteFileButton.ButtonPushedFcn = @(src, event) app.DeleteFileButtonPushed(event);

            % --- Run Pipeline tab ------------------------------------------
            app.RunTab = uitab(app.RightTabGroup, 'Title', 'Run Pipeline');

            app.RunGrid = uigridlayout(app.RunTab, [3 1]);
            app.RunGrid.RowHeight = {40, 24, '1x'};
            app.RunGrid.ColumnWidth = {'1x'};

            app.RunButton = uibutton(app.RunGrid, 'push');
            app.RunButton.Text = 'Run Pipeline on Selected Dataset';
            app.RunButton.FontWeight = 'bold';
            app.RunButton.BackgroundColor = app.ColorAccent;
            app.RunButton.FontColor = [1 1 1];
            app.RunButton.Layout.Row = 1;
            app.RunButton.Layout.Column = 1;
            app.RunButton.ButtonPushedFcn = @(src, event) app.RunPipelineButtonPushed(event);

            app.RunStatusLabel = uilabel(app.RunGrid);
            app.RunStatusLabel.Text = 'Idle.';
            app.RunStatusLabel.Layout.Row = 2;
            app.RunStatusLabel.Layout.Column = 1;

            app.LogTextArea = uitextarea(app.RunGrid);
            app.LogTextArea.Layout.Row = 3;
            app.LogTextArea.Layout.Column = 1;
            app.LogTextArea.Editable = 'off';
            app.LogTextArea.FontName = 'Consolas';
            app.LogTextArea.Value = {''};

            % --- Results tab ------------------------------------------------
            app.ResultsTab = uitab(app.RightTabGroup, 'Title', 'Results');

            app.ResultsGrid = uigridlayout(app.ResultsTab, [3 1]);
            app.ResultsGrid.RowHeight = {22, '1x', 40};
            app.ResultsGrid.ColumnWidth = {'1x'};

            app.FrequencyReadoutLabel = uilabel(app.ResultsGrid);
            app.FrequencyReadoutLabel.Layout.Row = 1;
            app.FrequencyReadoutLabel.Layout.Column = 1;
            app.FrequencyReadoutLabel.Text = 'Frequency: --';
            app.FrequencyReadoutLabel.FontWeight = 'bold';
            app.FrequencyReadoutLabel.HorizontalAlignment = 'center';

            % Live, interactive comparison -- real uiaxes (not a flattened
            % image) so the cursor readout above can report an exact Hz value
            % straight from each axes' own data coordinates. See
            % REFRESHRESULTSTAB and RESULTSMOUSEMOVED.
            app.ResultsPlotGrid = uigridlayout(app.ResultsGrid, [1 3]);
            app.ResultsPlotGrid.Layout.Row = 2;
            app.ResultsPlotGrid.Layout.Column = 1;
            app.ResultsPlotGrid.ColumnWidth = {'1x', '1x', '1x'};
            app.ResultsPlotGrid.Padding = [0 0 0 0];
            app.ResultsPlotGrid.Visible = 'off';

            app.ResultsAxes = [uiaxes(app.ResultsPlotGrid), uiaxes(app.ResultsPlotGrid), ...
                                uiaxes(app.ResultsPlotGrid)];
            for i = 1:3
                app.ResultsAxes(i).Layout.Row = 1;
                app.ResultsAxes(i).Layout.Column = i;
                app.ResultsAxes(i).Toolbar.Visible = 'off';
                disableDefaultInteractivity(app.ResultsAxes(i));
            end

            app.NoResultsLabel = uilabel(app.ResultsGrid);
            app.NoResultsLabel.Layout.Row = 2;
            app.NoResultsLabel.Layout.Column = 1;
            app.NoResultsLabel.Text = sprintf(['No comparison figure yet.\n' ...
                'Select a dataset and run the pipeline from the "Run Pipeline" tab.']);
            app.NoResultsLabel.HorizontalAlignment = 'center';
            app.NoResultsLabel.VerticalAlignment = 'center';
            app.NoResultsLabel.FontColor = [0.5 0.5 0.5];

            app.UIFigure.WindowButtonMotionFcn = @(src, event) app.ResultsMouseMoved(event);

            app.ResultsButtonGrid = uigridlayout(app.ResultsGrid, [1 4]);
            app.ResultsButtonGrid.Layout.Row = 3;
            app.ResultsButtonGrid.Layout.Column = 1;
            app.ResultsButtonGrid.ColumnWidth = {'1x', '1x', '1x', '1x'};
            app.ResultsButtonGrid.Padding = [0 0 0 0];

            app.OpenCleanedFolderButton = uibutton(app.ResultsButtonGrid, 'push');
            app.OpenCleanedFolderButton.Text = 'Open Cleaned Data Folder';
            app.OpenCleanedFolderButton.Layout.Row = 1;
            app.OpenCleanedFolderButton.Layout.Column = 1;
            app.OpenCleanedFolderButton.ButtonPushedFcn = @(src, event) app.OpenCleanedFolderButtonPushed(event);

            app.OpenFiguresFolderButton = uibutton(app.ResultsButtonGrid, 'push');
            app.OpenFiguresFolderButton.Text = 'Open Figures Folder';
            app.OpenFiguresFolderButton.Layout.Row = 1;
            app.OpenFiguresFolderButton.Layout.Column = 2;
            app.OpenFiguresFolderButton.ButtonPushedFcn = @(src, event) app.OpenFiguresFolderButtonPushed(event);

            app.OpenQCButton = uibutton(app.ResultsButtonGrid, 'push');
            app.OpenQCButton.Text = 'Open QC Summary (CSV)';
            app.OpenQCButton.Layout.Row = 1;
            app.OpenQCButton.Layout.Column = 3;
            app.OpenQCButton.ButtonPushedFcn = @(src, event) app.OpenQCButtonPushed(event);

            app.SaveGraphButton = uibutton(app.ResultsButtonGrid, 'push');
            app.SaveGraphButton.Text = 'Save Graph As...';
            app.SaveGraphButton.FontWeight = 'bold';
            app.SaveGraphButton.BackgroundColor = app.ColorAccent;
            app.SaveGraphButton.FontColor = [1 1 1];
            app.SaveGraphButton.Layout.Row = 1;
            app.SaveGraphButton.Layout.Column = 4;
            app.SaveGraphButton.ButtonPushedFcn = @(src, event) app.SaveGraphButtonPushed(event);

            % --- Print tab ------------------------------------------------
            app.PrintTab = uitab(app.RightTabGroup, 'Title', 'Print');

            app.PrintGrid = uigridlayout(app.PrintTab, [2 1]);
            app.PrintGrid.RowHeight = {'1x', 40};
            app.PrintGrid.ColumnWidth = {'1x'};

            app.PrintTable = uitable(app.PrintGrid);
            app.PrintTable.Layout.Row = 1;
            app.PrintTable.Layout.Column = 1;
            app.PrintTable.ColumnName = {'Print', 'Recording', 'Status'};
            app.PrintTable.ColumnFormat = {'logical', 'char', 'char'};
            app.PrintTable.ColumnEditable = [true false false];
            app.PrintTable.ColumnWidth = {50, '1x', 120};
            app.PrintTable.Data = cell(0, 3);

            app.PrintSelectedButton = uibutton(app.PrintGrid, 'push');
            app.PrintSelectedButton.Text = 'Print Selected';
            app.PrintSelectedButton.FontWeight = 'bold';
            app.PrintSelectedButton.BackgroundColor = app.ColorAccent;
            app.PrintSelectedButton.FontColor = [1 1 1];
            app.PrintSelectedButton.Layout.Row = 2;
            app.PrintSelectedButton.Layout.Column = 1;
            app.PrintSelectedButton.ButtonPushedFcn = @(src, event) app.PrintSelectedButtonPushed(event);

            % --- Trash tab (global -- not scoped to the selected dataset) ---
            app.TrashTab = uitab(app.RightTabGroup, 'Title', 'Trash');

            app.TrashGrid = uigridlayout(app.TrashTab, [2 1]);
            app.TrashGrid.RowHeight = {'1x', 40};
            app.TrashGrid.ColumnWidth = {'1x'};

            app.TrashTable = uitable(app.TrashGrid);
            app.TrashTable.Layout.Row = 1;
            app.TrashTable.Layout.Column = 1;
            app.TrashTable.ColumnName = {'Name', 'Type', 'Trashed On', 'Original Location'};
            app.TrashTable.ColumnWidth = {150, 70, 130, '1x'};
            app.TrashTable.Data = cell(0, 4);
            app.TrashTable.SelectionType = 'row';

            app.TrashButtonGrid = uigridlayout(app.TrashGrid, [1 3]);
            app.TrashButtonGrid.Layout.Row = 2;
            app.TrashButtonGrid.Layout.Column = 1;
            app.TrashButtonGrid.ColumnWidth = {'1x', '1x', '1x'};
            app.TrashButtonGrid.Padding = [0 0 0 0];

            app.RestoreButton = uibutton(app.TrashButtonGrid, 'push');
            app.RestoreButton.Text = 'Restore';
            app.RestoreButton.Layout.Row = 1;
            app.RestoreButton.Layout.Column = 1;
            app.RestoreButton.ButtonPushedFcn = @(src, event) app.RestoreButtonPushed(event);

            app.DeleteForeverButton = uibutton(app.TrashButtonGrid, 'push');
            app.DeleteForeverButton.Text = 'Delete Forever';
            app.DeleteForeverButton.BackgroundColor = app.ColorDanger;
            app.DeleteForeverButton.FontColor = [1 1 1];
            app.DeleteForeverButton.Layout.Row = 1;
            app.DeleteForeverButton.Layout.Column = 2;
            app.DeleteForeverButton.ButtonPushedFcn = @(src, event) app.DeleteForeverButtonPushed(event);

            app.EmptyTrashButton = uibutton(app.TrashButtonGrid, 'push');
            app.EmptyTrashButton.Text = 'Empty Trash';
            app.EmptyTrashButton.BackgroundColor = app.ColorDanger;
            app.EmptyTrashButton.FontColor = [1 1 1];
            app.EmptyTrashButton.Layout.Row = 1;
            app.EmptyTrashButton.Layout.Column = 3;
            app.EmptyTrashButton.ButtonPushedFcn = @(src, event) app.EmptyTrashButtonPushed(event);

            app.UIFigure.Visible = 'on';
        end

    end

    % =====================================================================
    % App creation and deletion
    % =====================================================================
    methods (Access = public)

        function app = EEGDatasetManagerApp(varargin)
            if ~isempty(varargin) && isstruct(varargin{1})
                app.cfg = varargin{1};
            end

            createComponents(app)
            registerApp(app, app.UIFigure)
            runStartupFcn(app, @startupFcn)

            if nargout == 0
                clear app
            end
        end

        function delete(app)
            delete(app.UIFigure)
        end

    end
end
