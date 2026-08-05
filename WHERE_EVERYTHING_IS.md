# Where everything is

A map of this folder. Nothing here is technical.

---

## To start work

**Double-click `1 - START HERE.bat`**

MATLAB opens, gets everything ready, and opens the **EEG Dataset Manager**
window — add dataset zips, browse/rename/delete datasets and the files inside
them, run the pipeline on a selected dataset, and see the results, all without
typing a command. That is the whole start-up procedure.

Then, if you want Claude Code as well, double-click **`2 - Claude Code.bat`**.

**Always in that order.** Claude Code checks its MATLAB connection once when it
starts, so MATLAB has to be running first.

**Troubleshooting, or want the console instead?** Run `START_HERE.m` directly
inside MATLAB. It does the same setup and prints a full menu of console
commands and an environment report, instead of opening the window.

---

## The folders

```
EEG/
│
├── 0 - SETUP GUIDE.pdf    ← one page: how to set this up from scratch
├── 1 - START HERE.bat     ← DOUBLE-CLICK THIS FIRST (opens MATLAB)
├── 2 - Claude Code.bat    ← then this, if you want Claude Code
│
├── data/
│   ├── raw/               ← PUT NEW RECORDINGS HERE, one subfolder per dataset
│   │   ├── Harvard/       ←   e.g. data/raw/Harvard/... (.edf, .bdf, .csv or .dat)
│   │   └── Zenodo/        ←   a second dataset never mixes with the first
│   └── processed/         ← cleaned recordings appear here automatically
│
├── figures/               ← all the plots appear here
├── results/               ← qc_summary.csv and the numeric spectra
│
├── README.md              ← full instructions
├── WHERE_EVERYTHING_IS.md ← this file
├── LICENSE                ← MIT
│
├── src/                   ← the code
├── docs/                  ← install guides and the client's brief
├── Tools/                 ← MATLAB MCP server (lets Claude talk to MATLAB)
├── toolboxes/             ← EEGLAB (do not touch)
│
├── Launch_App.m           ← what launcher 1 actually runs (opens the app)
├── START_HERE.m           ← the console workflow, for troubleshooting
└── CLAUDE.md              ← rules for AI assistants working on this code
```

The numbered files at the top are the only ones you need day to day. Everything
else can be ignored until you want it.

---

## The three things you will actually open

| I want to... | Open this |
|---|---|
| See the plots | `figures/` |
| See what the pipeline decided for each recording | `results/qc_summary.csv` |
| Add new recordings | `data/raw/<a folder named for the dataset>/` |

---

## The one file that matters most

**`results/qc_summary.csv`** — one row per recording. Open it in Excel.

The column to check first is **`usable`**:

- **1** = the recording is fine
- **0** = too noisy to trust, do not use its results

Other useful columns: `badChannels` (electrodes that were faulty),
`interpolated` (electrodes that were repaired), `nEpochs` (how much clean data
survived), and `warnings` (plain-English notes on anything unusual).

---

## Inside `docs/`

| File | What it is |
|---|---|
| `SETUP.md` | Full MATLAB and EEGLAB install instructions |
| `GITHUB_AND_CLAUDE_CODE.md` | Installing Git, GitHub CLI and Claude Code |
| `Client Brief (original).pdf` | What was originally asked for |
| `Project Breakdown (simplified).pdf` | The same, in plainer language |
| `examples/` | Two sample output figures |

---

## Inside `src/` — the code, in the order it runs

You do not need to read any of this. It is here so you can find a file if you
ever want to.

| Order | File | What it does |
|---|---|---|
| 1 | `setup_paths.m` | Finds EEGLAB, creates folders |
| 2 | `check_env.m` | Confirms everything is installed |
| 3 | `pipeline_config.m` | **Every setting and threshold lives here** |
| 4 | `select_dataset.m` | Picks which dataset subfolder to process — latest one by default |
| 5 | `find_recording_files.m` | Finds the real recording files in a dataset folder, filtering out junk |
| 6 | `parse_recording_name.m` | Works out who, what and when from the filename |
| 7 | `import_recording.m` | Loads the file, sending EDF/BDF, CSV and DAT to the right reader |
| 8 | `import_emotiv_csv.m` | Reads Emotiv CSV exports |
| 9 | `import_matrix_dat.m` | Reads headerless numeric-matrix files (needs sample rate + channel order given explicitly) |
| 10 | `preprocess_recording.m` | The 8 cleaning stages |
| 11 | `compute_psd.m` | Works out the power spectrum |
| 12 | `draw_psd_strips.m` | Draws the coloured bands |
| 13 | `plot_psd_stack.m` | One recording, one page |
| 14 | `fit_figure_to_screen.m` | Keeps the plot window's title bar on-screen, whatever monitor it opens on |
| 15 | `pick_three.m` | Chooses first / second-to-last / last |
| 16 | `compare_recordings.m` | Three recordings side by side |
| 17 | `run_pipeline.m` | **Runs all of the above over every file** |

Six extras, not part of the main run:

| File | What it does |
|---|---|
| `qc_report.m` | Detailed per-channel statistics for one recording |
| `make_test_fixture.m` | Makes fake data with a known answer, to check the maths — including deliberately hostile data for stress-testing |
| `import_dataset_zip.m` | Extracts a downloaded dataset zip into its own `data/raw/` subfolder in one step |
| `test_edf_roundtrip.m` | Checks the EDF reader puts the right signal under the right channel name |
| `get_sample_data.m` | Where to download public sample recordings |
| `sync_to_github.m` | Saves your changes to GitHub in one line |

The interactive window (what `Launch_App.m` opens):

| File | What it does |
|---|---|
| `EEGDatasetManagerApp.m` | The Dataset Manager window itself — add/rename/delete datasets and their files, run the pipeline, view results |
| `list_datasets.m` | Lists every `data/raw/` dataset with its recording count, size and modified date, for the app's dataset table |
| `rename_dataset.m` | Renames a dataset folder |
| `delete_dataset.m` | Deletes a dataset folder |

---

## If you break something

Nothing in `data/raw/` is ever modified — the pipeline only reads it. Everything
in `figures/`, `results/` and `data/processed/` is rebuilt from scratch each
time you run `run_pipeline()`.

So if the outputs ever look wrong, you can safely delete everything in those
three folders and run it again.
