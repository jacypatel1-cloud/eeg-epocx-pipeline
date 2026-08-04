# Where everything is

A map of this folder. Nothing here is technical.

---

## To start work

**Double-click `1 - START HERE.bat`**

MATLAB opens, loads the project, checks everything is installed, and prints a
menu. That is the whole start-up procedure.

Then, if you want Claude Code as well, double-click **`2 - Claude Code.bat`**.

**Always in that order.** Claude Code checks its MATLAB connection once when it
starts, so MATLAB has to be running first.

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
│   ├── raw/               ← PUT NEW RECORDINGS HERE (.edf, .bdf or .csv)
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
├── START_HERE.m           ← what launcher 1 runs
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
| Add new recordings | `data/raw/` |

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
| 4 | `parse_recording_name.m` | Works out who, what and when from the filename |
| 5 | `import_recording.m` | Loads the file, sending EDF/BDF and CSV to the right reader |
| 6 | `import_emotiv_csv.m` | Reads Emotiv CSV exports |
| 7 | `preprocess_recording.m` | The 8 cleaning stages |
| 8 | `compute_psd.m` | Works out the power spectrum |
| 9 | `draw_psd_strips.m` | Draws the coloured bands |
| 10 | `plot_psd_stack.m` | One recording, one page |
| 11 | `pick_three.m` | Chooses first / second-to-last / last |
| 12 | `compare_recordings.m` | Three recordings side by side |
| 13 | `run_pipeline.m` | **Runs all of the above over every file** |

Four extras, not part of the main run:

| File | What it does |
|---|---|
| `qc_report.m` | Detailed per-channel statistics for one recording |
| `make_test_fixture.m` | Makes fake data with a known answer, to check the maths |
| `test_edf_roundtrip.m` | Checks the EDF reader puts the right signal under the right channel name |
| `get_sample_data.m` | Where to download public sample recordings |
| `sync_to_github.m` | Saves your changes to GitHub in one line |

---

## If you break something

Nothing in `data/raw/` is ever modified — the pipeline only reads it. Everything
in `figures/`, `results/` and `data/processed/` is rebuilt from scratch each
time you run `run_pipeline()`.

So if the outputs ever look wrong, you can safely delete everything in those
three folders and run it again.
