# EEG Preprocessing Pipeline — Emotiv EPOC X

Local-only MATLAB/EEGLAB pipeline that cleans Emotiv EPOC X (14-channel)
recordings and plots their power spectra. Nothing leaves your computer at any
point — there are no network calls at runtime.

![Three-recording comparison](docs/examples/example-comparison-three-recordings.png)

---

## If you just cloned this repository

**No recordings are included.** `data/` is deliberately excluded from git so that
real patient recordings can never be committed by accident. To get sample data:

```matlab
cfg = setup_paths();
get_sample_data(cfg)     % prints download links and where to put the files
```

The dataset this was built against is [Harvard Dataverse
`10.7910/DVN/JMH4PD`](https://doi.org/10.7910/DVN/JMH4PD) — 54 Emotiv EPOC X
recordings, CC0 public domain.

You also need EEGLAB, which is not bundled. See **`docs/SETUP.md`**, then run
`check_env()` — it names anything missing.

---

## Quick start

**Double-click `1 - START HERE.bat`.**

MATLAB opens already pointed at this folder, gets EEGLAB ready, and opens the
**EEG Dataset Manager** — an interactive window where you can:

- **Add Dataset(s)...** — pick one or more `.zip` files; each is extracted into
  its own `data/raw/<name>/` folder automatically.
- Browse the dataset list, rename or delete a dataset, and inspect/add/rename/
  delete individual files inside one, from the **Files** tab.
- Click a dataset, then **Run Pipeline on Selected Dataset** (in the **Run
  Pipeline** tab) — imports, cleans, computes spectra, and builds the
  comparison figure, with the full log shown in the window.
- The **Results** tab shows the first/second-to-last/last PSD comparison as
  soon as a run finishes, plus buttons to open the cleaned-data, figures and
  QC-summary folders directly in Explorer.

Everything the window does calls the same functions described below
(`run_pipeline`, `import_dataset_zip`, etc.) — nothing about the pipeline
itself changes, this just gives it a front end.

**Troubleshooting, or prefer the console?** Open `START_HERE.m` in MATLAB and
press the green **Run** button — it does the same setup, then prints a menu of
console commands (including everything below) instead of opening the window.

New to the folder? Read `WHERE_EVERYTHING_IS.md` first — it is a one-page map
with no technical detail in it.

---

## Console workflow

Everything above is also available as plain MATLAB commands, after running
`START_HERE.m` (or `cfg = setup_paths();` by hand):

```matlab
results = run_pipeline();
```

That is the whole thing. It imports every recording, cleans it, saves the cleaned
version, computes the spectra, and writes a comparison figure.

**Multiple datasets?** Each one gets its own subfolder under `data/raw/` (e.g.
`data/raw/Harvard/`, `data/raw/Zenodo/`) — see [Working with multiple
datasets](#working-with-multiple-datasets) below. `run_pipeline()` with no
arguments always processes whichever subfolder was extracted most recently.

---

## Common variations

```matlab
% Just one participant
results = run_pipeline('Subject', "126518");

% Just one condition
results = run_pipeline('Movement', "DOWN");

% Quick look at 3 files, saving a spectrum plot for each
results = run_pipeline('Limit', 3, 'PlotEach', true);

% Use a 50 Hz notch instead of the 60 Hz default
% (also needs the low-pass raised above 50 Hz, or it is skipped as redundant
% -- see "Things worth knowing about this dataset" for why)
P = pipeline_config('doNotch', true, 'notchFreq', 50);
results = run_pipeline('Config', P);

% A specific dataset subfolder, instead of the most recently extracted one
results = run_pipeline('Dataset', 'Harvard');
```

---

## Where things go

| Folder | Contents |
|---|---|
| `data/raw/<dataset>/` | Your recordings (`.edf`, `.bdf`, `.csv` or `.dat`), one subfolder per dataset, exactly as exported. **Never modified.** |
| `data/processed/` | Cleaned data, one `.set` file per recording |
| `figures/` | Spectrum plots and the comparison figure |
| `results/` | `qc_summary.csv` plus the numeric spectra |
| `src/` | All the code |
| `toolboxes/` | EEGLAB |

**Start with `results/qc_summary.csv`.** One row per recording, listing every
decision the pipeline made: which channels were repaired, how many epochs were
thrown away, whether ICA ran, and any warnings. The `usable` column is the one to
check first — `0` means the recording was too noisy to trust.

---

## What the code does

Read in this order if you want to follow it through:

| File | Role |
|---|---|
| `setup_paths.m` | Finds EEGLAB, creates folders, returns all paths. Run first. |
| `check_env.m` | Confirms required toolboxes and plugins are installed |
| `pipeline_config.m` | **Every setting lives here.** All thresholds, all on/off switches |
| `select_dataset.m` | Picks which `data/raw/<name>/` subfolder to process — latest by default |
| `import_dataset_zip.m` | Extracts a downloaded dataset zip into its own `data/raw/` subfolder |
| `parse_recording_name.m` | Reads participant, condition and time out of a filename |
| `import_recording.m` | **Entry point for loading.** Routes EDF/BDF to `pop_biosig`, CSV to the Emotiv reader, DAT to the headerless-matrix reader |
| `import_emotiv_csv.m` | Emotiv CSV → EEGLAB dataset, refusing to guess anything |
| `import_matrix_dat.m` | Headerless numeric-matrix files → EEGLAB dataset. Sample rate and channel order must be supplied explicitly, since this format cannot self-report either |
| `test_edf_roundtrip.m` | Proves the EDF path attaches the right data to the right channel name |
| `preprocess_recording.m` | The 8 cleaning stages |
| `compute_psd.m` | Turns cleaned data into a power spectrum |
| `draw_psd_strips.m` | Draws one recording's stacked strips — shared by the two functions below so they can never visually drift apart |
| `plot_psd_stack.m` | Draws one recording |
| `compare_recordings.m` | Draws several side by side |
| `fit_figure_to_screen.m` | Sizes and centers a figure so its title bar always stays reachable, on whatever screen it opens on |
| `pick_three.m` | Chooses first / second-to-last / last |
| `run_pipeline.m` | Runs all of the above over every file |
| `make_test_fixture.m` | Builds fake data with a known answer, for testing — including deliberately hostile data (see [Testing without real data](#testing-without-real-data)) |

### The 8 cleaning stages

1. **Reject bad segments** — cut out stretches where the signal has clearly broken down
2. **High-pass filter (1 Hz)** — remove slow drift. Raw Emotiv values sit near +4300 µV; this is what removes that offset
3. **Low-pass filter (45 Hz)** — remove muscle activity and high-frequency noise
4. **Notch filter (optional)** — remove mains hum. Off by default; see below
5. **Re-reference** — express each channel against the average of all channels
6. **Artifact removal** — ASR for large sudden events, ICA + ICLabel for blinks and muscle
7. **Interpolate bad channels** — rebuild a broken electrode from its neighbours
8. **Epoch and reject** — cut into 2-second pieces, drop any still containing extremes

Every stage can be switched off in `pipeline_config.m`. Nothing is hard-coded into
the pipeline body.

### Thresholds are adaptive, not fixed

`badSegAbsUV`, `badChanCorr` and `epochRejUV` default to `[]`, which means each is
recomputed **per recording**, from that recording's own robust statistics (median +
K robust-sigmas, clamped to a floor/ceiling), rather than one fixed number applied to
every file. This matters because a fixed threshold tuned on one dataset does not
travel: it was tuned on one 6-recording sample from the original client dataset, and
running it against a second, independent dataset (Zenodo's 14-channel EPOC set)
showed the correlation threshold pinned at its ceiling for 63% of recordings — i.e.
"adaptive" had quietly become a fixed number again. The floor/ceiling guardrails
have since been re-measured across both datasets combined (115 recordings). Full
reasoning and the actual numbers are in the comments above each threshold in
`pipeline_config.m`.

Set any of the three to a specific number instead of `[]` to force the old
fixed-threshold behaviour, e.g. for a validated clinical protocol that mandates one
exact cutoff.

---

## Reading the spectrum plots

Channels are stacked vertically, front of the head at the top. Left to right is
frequency, 0–20 Hz. The height of each coloured band is how much power that channel
carries at that frequency. Every strip has its own small amplitude scale on the
right (three ticks: floor, mid, peak of the shared dB scale) and a spacing wide
enough that a strip's tallest possible peak can never overlap the strip above it —
this is not cosmetic, an earlier version's spacing formula let strips overlap by up
to 2x on real data.

A bump around 8–12 Hz at the back of the head (O1, O2, P7, P8) is **alpha rhythm** —
normal, and stronger with eyes closed.

The comparison figure puts three recordings side by side on **one shared scale**, so
a column that looks lower really does have less power. If each were scaled to its
own maximum, that difference would vanish.

---

## Working with multiple datasets

Each dataset lives in its own subfolder under `data/raw/`, e.g.:

```
data/raw/Harvard/...
data/raw/Zenodo/...
```

This matters because `run_pipeline()` sorts every recording it finds by timestamp
and treats "first" and "last" as meaningful for the comparison figure — two
unrelated datasets dropped loose into one folder would get compared against each
other by coincidence of file timestamp, which answers no real question.

- **`run_pipeline()`** with no `'Dataset'` argument processes whichever subfolder
  was extracted **most recently** — no need to tell it which one.
- **`run_pipeline('Dataset', 'Harvard')`** processes a specific one by name.
- **`import_dataset_zip('C:\path\to\download.zip')`** extracts a downloaded zip into
  its own correctly-named `data/raw/` subfolder in one step — the only manual part
  of an otherwise hands-off workflow. It refuses to overwrite an existing dataset
  folder rather than risk mixing an old extraction with a new one.

Nothing here runs automatically or watches the filesystem — every step happens
because you called it.

---

## Things worth knowing about this dataset

Findings from the 54 Harvard Dataverse recordings, which affect what the pipeline
can honestly do:

- **The recordings are short.** Median 9 seconds, shortest 6, longest 74.
- **ICA is skipped on almost all of them.** ICA needs roughly 4,000 samples for 14
  channels; a 9-second recording has about 1,150. The pipeline checks this and
  skips with an explanation rather than producing a decomposition that would look
  convincing and mean nothing. Only the 74-second recording qualified.
- **ASR is skipped for the same reason** — it needs a clean reference section
  within the recording, and there isn't one in 9 seconds.
- **The notch filter is off by default, and enabling it alone is not enough.**
  Under the default 45 Hz low-pass, a 60 Hz notch always gets skipped as redundant
  (the low-pass has already removed it) even with `doNotch` set to `true` — you
  also need to raise `lowpassHz` above the notch frequency, or run at 256 Hz. The
  filter itself is correct where reachable: confirmed by an isolated test showing
  >99.99% reduction in 60 Hz power once the redundant-skip no longer applies.
- **2 of 54 recordings are flagged unusable** — too noisy to survive epoch
  rejection. They are reported, not silently dropped.

None of the above is a fault in the code. It is what short recordings allow. Longer
recordings — 60 seconds or more — would let ICA and ASR run, and those are the two
stages that do the heavy lifting on blink and muscle artifacts. Confirmed directly:
a 60-second synthetic recording built specifically to be long enough triggered ICA +
ICLabel successfully, the first time either had run end-to-end in this project.

**Cross-checked against a second, independent dataset** (Zenodo's 14-channel EPOC
set, 64 recordings, different subjects, different noise profile, different file
format entirely) — see the "Working with multiple datasets" section above for how
that's kept separate from Harvard. All 64 processed successfully. The exercise is
also what caught the adaptive-threshold ceiling problem described above: numbers
tuned on one dataset do not automatically generalise, and the only way to find that
out is to run a second, genuinely different dataset through and look at what the
thresholds actually compute.

---

## Input formats

Drop `.edf`, `.bdf`, `.csv` or `.dat` files into a dataset subfolder under
`data/raw/` — `run_pipeline()` picks up all four and routes each to the right
reader. EDF/BDF go through `pop_biosig`; CSV goes through the EmotivPRO reader; DAT
(a headerless numeric matrix, no metadata at all) goes through a reader that
requires the sample rate and channel order to be supplied explicitly, since the
format cannot report either itself.

**Channels are matched by name, never by position**, wherever the format allows it.
An EDF that stores its channels in a different order, or labels them `EEG AF3`
instead of `AF3`, is reordered into the correct EPOC X montage on import. This is
not cosmetic: taking channels 1–14 positionally would produce a scrambled montage
that runs without error and makes every figure wrong. To verify it on your machine:

```matlab
test_edf_roundtrip(cfg);
```

That writes an EDF with deliberately shuffled channels, reads it back, and checks
the right signal ends up under the right name.

**DAT files are the exception, and it is a real limitation, not a technicality.**
A bare grid of numbers cannot say which column is which electrode. Passing the
wrong `ChannelOrder` would silently repeat exactly the mislabelling bug the EDF path
above was rewritten to prevent — so `import_matrix_dat.m` refuses to guess and
requires it explicitly, and stamps whatever was passed into `meta.channelOrderSource`
verbatim (e.g. `"ASSUMED: canonical EPOC X order, not documented by source dataset"`)
rather than presenting it as fact. If you don't have documented channel order for a
`.dat` source, treat any per-channel finding from it as provisional.

---

## Testing without real data

`make_test_fixture.m` writes a synthetic file with a known answer: a 10 Hz peak at
the back of the head, blinks at the front, mains hum, drift, and one dead channel.

```matlab
fixture = make_test_fixture(cfg);
EEG = import_emotiv_csv(fixture, cfg);
S   = compute_psd(EEG, pipeline_config());
plot_psd_stack(S, cfg);
```

If the peak does not land at 10 Hz, something is wrong with the analysis rather
than with the data. Delete the file from `data/raw/` afterwards — it is not a
recording.

### Adversarial stress-testing

The same generator can build deliberately hostile recordings, for testing the
pipeline's failure paths rather than its happy path:

```matlab
% Several simultaneously dead channels -- tests the "refuse to interpolate,
% too many channels missing" guardrail
make_test_fixture(cfg, 'BadChannel', [2 5 8 11]);

% Severe broadband artifact bursts on every channel, not just the usual
% frontal blinks -- tests ASR/bad-segment behaviour under real duress
make_test_fixture(cfg, 'ExtremeNoiseAmp', 500);

% Corrupted (NaN) samples -- tests the importer's non-finite handling
make_test_fixture(cfg, 'InjectNaNFrac', 0.02);

% Long and clean enough to actually trigger ICA (most real recordings in
% this project are too short for ICA to ever run)
make_test_fixture(cfg, 'DurationSec', 60, 'BadChannel', 0);
```

Put a batch of these in their own `data/raw/<name>/` subfolder (see [Working with
multiple datasets](#working-with-multiple-datasets)) to run a full adversarial
sweep through `run_pipeline()`. As with the basic fixture, these are synthetic —
delete the subfolder afterwards rather than leaving it alongside real recordings.
`Tag` keeps multiple fixtures in one folder from colliding on filename.

---

## If something goes wrong

**"EEGLAB not found"** — EEGLAB isn't in `toolboxes/`. See `docs/SETUP.md`.

**"Channel location file not found"** — `data/emotivX_channels_location.ced` is
missing. Download link is in `docs/SETUP.md`.

**"Could not determine the sampling rate"** — the file has no readable header. Pass
it explicitly, but only if you know it for certain:
`import_emotiv_csv(file, cfg, 'SampleRate', 128)`.

**"No dataset subfolders found in data/raw"** — recordings need to sit inside a
named subfolder, e.g. `data/raw/Harvard/...`, not loose in `data/raw/` directly.
See [Working with multiple datasets](#working-with-multiple-datasets).

**"This file format carries no sample rate/channel names of its own"** — a `.dat`
file needs both passed explicitly via `'ImportOptions'` on `run_pipeline()` (or
directly to `import_matrix_dat.m`), since the format has no header at all.

**A recording fails** — the batch continues and reports which one and why at the
end. One bad file never stops the run.

---

## Requirements

- MATLAB R2021a or later, with Signal Processing and Statistics toolboxes
- EEGLAB, with the BIOSIG, firfilt, clean_rawdata and ICLabel plugins

`check_env()` confirms all of this and names anything missing.

---

## What is and is not tracked in git

| Tracked | Not tracked |
|---|---|
| All code in `src/` | `data/raw/` and `data/processed/` |
| Documentation and the client brief | `figures/` and `results/` |
| Two example figures in `docs/examples/` | `toolboxes/` (EEGLAB, ~150 MB) |

**`data/` is excluded on purpose, and that exclusion should not be relaxed.**
The moment a real patient recording is committed to a public repository it is
permanently public, even if deleted afterwards — git keeps history. Keeping the
whole folder out, with no exceptions, is what makes that mistake impossible
rather than merely unlikely.

Everything in `figures/`, `results/` and `data/processed/` is regenerated by
`run_pipeline()`, so nothing is lost by not tracking it.

---

## Licence

MIT — see `LICENSE`. This is a research and signal-processing tool, not a
medical device, and must not be used as the basis for clinical decisions.
