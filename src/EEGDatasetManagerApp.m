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
        ResultsImage        matlab.ui.control.Image
        NoResultsLabel      matlab.ui.control.Label
        ResultsButtonGrid   matlab.ui.container.GridLayout
        OpenCleanedFolderButton matlab.ui.control.Button
        OpenFiguresFolderButton matlab.ui.control.Button
        OpenQCButton        matlab.ui.control.Button
        SaveGraphButton     matlab.ui.control.Button
    end

    % =====================================================================
    % Data (not UI)
    % =====================================================================
    properties (Access = private)
        cfg                 = []    % struct from setup_paths()
        DatasetRows         = []    % struct array from list_datasets()
        SelectedDatasetName = ''    % char, name of the selected dataset row
        FileRows            = []    % dir()-style struct array, current dataset's files
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
                sprintf(['Delete dataset "%s" and every file inside it?\n\n' ...
                         'This cannot be undone. Anything already processed from it ' ...
                         'in data/processed, figures/ or results/ is NOT affected.'], name), ...
                'Delete Dataset', 'Options', {'Delete', 'Cancel'}, ...
                'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
            if ~strcmp(choice, 'Delete')
                return
            end
            try
                delete_dataset(app.cfg, name);
                app.SelectedDatasetName = '';
                app.refreshDatasetTable();
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
            choice = uiconfirm(app.UIFigure, sprintf('Delete "%s"?', f.name), ...
                'Delete File', 'Options', {'Delete', 'Cancel'}, ...
                'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
            if ~strcmp(choice, 'Delete')
                return
            end
            try
                delete(fullPath);
            catch ME
                uialert(app.UIFigure, ME.message, 'Delete failed', 'Icon', 'error');
            end
            app.refreshFileTable();
            app.refreshDatasetTable();
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
                cmd = sprintf(['resultsLocal = run_pipeline(''Dataset'', %s, ' ...
                    '''ImportOptions'', importOptionsLocal, ''Visible'', false);'], ...
                    mat2str(name));
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
            pngPath = fullfile(app.cfg.figDir, 'comparison_first_secondlast_last.png');
            if exist(pngPath, 'file') == 2
                % Read the pixels rather than pointing ImageSource at the path.
                % The comparison figure is always saved under this same
                % filename, so setting ImageSource to the same path string
                % after a new run does not reliably force uiimage to reload
                % the (changed) file on disk -- passing the decoded image
                % data instead guarantees the tab actually shows the latest run.
                try
                    app.ResultsImage.ImageSource = imread(pngPath);
                catch
                    app.ResultsImage.ImageSource = pngPath;
                end
                app.ResultsImage.Visible = 'on';
                app.NoResultsLabel.Visible = 'off';
            else
                app.ResultsImage.Visible = 'off';
                app.NoResultsLabel.Visible = 'on';
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

            app.ResultsGrid = uigridlayout(app.ResultsTab, [2 1]);
            app.ResultsGrid.RowHeight = {'1x', 40};
            app.ResultsGrid.ColumnWidth = {'1x'};

            app.ResultsImage = uiimage(app.ResultsGrid);
            app.ResultsImage.Layout.Row = 1;
            app.ResultsImage.Layout.Column = 1;
            app.ResultsImage.ScaleMethod = 'fit';
            app.ResultsImage.Visible = 'off';

            app.NoResultsLabel = uilabel(app.ResultsGrid);
            app.NoResultsLabel.Layout.Row = 1;
            app.NoResultsLabel.Layout.Column = 1;
            app.NoResultsLabel.Text = sprintf(['No comparison figure yet.\n' ...
                'Select a dataset and run the pipeline from the "Run Pipeline" tab.']);
            app.NoResultsLabel.HorizontalAlignment = 'center';
            app.NoResultsLabel.VerticalAlignment = 'center';
            app.NoResultsLabel.FontColor = [0.5 0.5 0.5];

            app.ResultsButtonGrid = uigridlayout(app.ResultsGrid, [1 4]);
            app.ResultsButtonGrid.Layout.Row = 2;
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
