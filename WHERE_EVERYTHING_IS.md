# Where everything is

A map of this folder. Nothing here is technical.

> **The project moved on 4 August 2026.** It now lives at
> `C:\Users\jacyp\Projects\EEG`, not in OneDrive. OneDrive was deleting files,
> including the git repository. See `GITHUB_AND_CLAUDE_CODE.md` for the full
> explanation. The old OneDrive copy can be deleted once you are happy this one
> works.

---

## To start work

**Double-click `Launch EEG Project.bat`**

MATLAB opens, loads the project, and prints a menu. That is the whole
start-up procedure.

If you prefer to open MATLAB yourself: open `START_HERE.m` and press the green
**Run** button.

---

## The folders

```
EEG/
│
├── Launch EEG Project.bat   ← 1. DOUBLE-CLICK THIS FIRST (opens MATLAB)
├── Launch Claude Code.bat   ← 2. then this, if you want Claude Code
├── START_HERE.m             ← what the first launcher runs
│
├── README.md                ← full instructions
├── WHERE_EVERYTHING_IS.md   ← this file
├── SETUP.md                 ← MATLAB/EEGLAB install steps (already done)
├── GITHUB_AND_CLAUDE_CODE.md ← what to install for GitHub (NOT done yet)
├── CLAUDE.md                ← rules for AI assistants working on this code
├── LICENSE                  ← MIT
│
├── data/
│   ├── raw/                 ← PUT NEW RECORDINGS HERE (.csv, .edf, .bdf)
│   └── processed/           ← cleaned recordings appear here automatically
│
├── figures/                 ← all the plots appear here
├── results/                 ← qc_summary.csv and the numeric spectra
│
├── docs/                    ← the client's brief and reference material
├── src/                     ← the code
├── Tools/                   ← MATLAB MCP server (lets Claude talk to MATLAB)
└── toolboxes/               ← EEGLAB (do not touch)
```

---

## The three things you will actually open

| I want to... | Open this |
|---|---|
| See the plots | `figures/` |
| See what the pipeline decided for each recording | `results/qc_summary.csv` |
| Add new recordings | `data/raw/` |

---

## The one file that matters most

**`results/qc_summary.csv`** — one row per recording. Open it in Excel.

The column to look at first is **`usable`**:

- **1** = the recording is fine
- **0** = too noisy to trust, do not use its results

Other useful columns: `badChannels` (electrodes that were faulty),
`interpolated` (electrodes that were repaired), `nEpochs` (how much clean data
survived), and `warnings` (plain-English notes about anything unusual).

---

## The code files, in the order they run

You do not need to read these. This is only so you can find one if you want to.

| Order | File | What it does |
|---|---|---|
| 1 | `setup_paths.m` | Finds EEGLAB, creates folders |
| 2 | `check_env.m` | Confirms everything is installed |
| 3 | `pipeline_config.m` | **Every setting and threshold lives here** |
| 4 | `parse_recording_name.m` | Works out who, what and when from the filename |
| 5 | `import_recording.m` | Loads the file (sends EDF/BDF and CSV to the right reader) |
| 6 | `import_emotiv_csv.m` | Reads Emotiv CSV exports |
| 7 | `preprocess_recording.m` | The 8 cleaning stages |
| 8 | `compute_psd.m` | Works out the power spectrum |
| 9 | `draw_psd_strips.m` | Draws the coloured bands |
| 10 | `plot_psd_stack.m` | One recording, one page |
| 11 | `pick_three.m` | Chooses first / second-to-last / last |
| 12 | `compare_recordings.m` | Three recordings side by side |
| 13 | `run_pipeline.m` | **Runs all of the above over every file** |

Two extras, not part of the main run:

| File | What it does |
|---|---|
| `qc_report.m` | Detailed per-channel statistics for one recording, if you want a closer look |
| `make_test_fixture.m` | Makes fake data with a known answer, to check the maths |
| `test_edf_roundtrip.m` | Checks the EDF reader puts the right signal under the right channel name |

---

## If you break something

Nothing in `data/raw/` is ever modified — the pipeline only reads it. Everything
in `figures/`, `results/` and `data/processed/` is regenerated from scratch each
time you run `run_pipeline()`.

So if the outputs ever look wrong, you can safely delete everything in those
three folders and run it again.
