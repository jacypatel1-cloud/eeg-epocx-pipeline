# EEG Preprocessing Pipeline — Emotiv EPOC X

Project rules for any AI agent writing code in this repo. Read this before editing anything.

## Hard constraints

- **MATLAB only.** No Python, no MNE, no shell pipelines for the deliverable. EEGLAB is the
  preferred framework. Helper scripts in other languages are not acceptable output.
- **Local only.** No cloud services, no uploads, no network calls at runtime. This is clinical
  data. Everything reads from and writes to folders inside this project.
- **Device is fixed:** Emotiv EPOC X, 14 channels, in this order —
  `AF3 F7 F3 FC5 T7 P7 O1 O2 P8 T8 FC6 F4 F8 AF4`. Sampling rate is 128 Hz (or 256 Hz in
  the higher-rate mode) — read it from the file header, never hardcode it.
- **Input format:** EDF or BDF. Import with `pop_biosig`. CSV exports from Emotiv are a
  secondary path only.

## Waiting-room intake exception (explicitly authorized, narrowly scoped)

The two hard constraints above ("MATLAB only", "no network calls at runtime") have exactly
**one** documented exception, authorized explicitly by the project owner (not inferred) to
let a patient fill out questionnaires on an iPad in the waiting room, since a tablet cannot
run a MATLAB App Designer app:

- **Lives entirely in `webintake/`**, never `src/`. `webintake/server.py` (Python 3,
  standard library only, no dependencies) is the one non-MATLAB file in this deliverable —
  mirroring how `Tools/` already holds the non-MATLAB MCP server helper alongside the
  MATLAB-only pipeline.
- **LAN only, never the internet.** The server binds to the machine's own private LAN IPv4
  address (see `get_lan_ip()` in `webintake/server.py`) — never `0.0.0.0`, never a public
  interface, no port forwarding, no cloud anything. It only runs while a clinician has
  deliberately clicked "Start Waiting Room Intake" in the app.
- **One job, nothing else.** It serves a questionnaire form and writes submitted answers to
  a plain JSON file under that patient's own visit folder
  (`data/patients/<id>/visits/<date>/questionnaire_intake/`). It does not score anything,
  does not touch `qc_summary.csv` or any pipeline output, and never runs the EEG pipeline.
  `import_pending_intake_responses.m` (MATLAB) picks the raw file up, scores it with the
  same `score_questionnaire.m` engine used everywhere else, and deletes it once processed.
- **Item wording is exported from MATLAB, never hand-copied into Python** —
  `export_questionnaire_definitions_json.m` writes `webintake/questionnaire_definitions.json`
  from `questionnaire_definitions.m`, so the iPad form and the app can never show different
  text for the same instrument.

Do not extend this exception to anything else. Any other future network or non-MATLAB need
requires the same explicit, in-writing authorization from the project owner this one got —
never assume it by analogy.

## Required pipeline order

1. Import EDF/BDF, apply channel locations from `data/emotivX_channels_location.ced`
2. Inspect and reject bad segments
3. High-pass filter (0.5–1 Hz)
4. Low-pass filter (40–45 Hz)
5. Optional notch (50/60 Hz — configurable, Hawaii is 60 Hz)
6. Re-reference to common average
7. Artifact removal: ASR (`clean_artifacts`) and/or ICA + ICLabel
8. Bad channel interpolation
9. Epoch rejection

Every stage must be toggleable and parameterised from a single config struct, not by editing
the pipeline body.

## Required output

- Power spectral density plots of cleaned data, computed via FFT (Welch is acceptable —
  state the method in the axis label).
- 0–20 Hz band, per channel.
- Comparison view showing **three recordings at once**: first, second-to-last, and last.
- Save figures to `figures/`, numeric results to `results/`.

## Folder layout

```
data/raw/         EDF/BDF files as recorded — never modified
data/processed/   cleaned .set/.fdt files, one per recording
data/patients/    patient profiles + visit history (see CREATE_PATIENT_PROFILE.m)
figures/          PSD plots
results/          exported spectra, QC tables, questionnaire scores
src/              all MATLAB code
toolboxes/        EEGLAB lives here (git-ignored)
webintake/        the ONE non-MATLAB exception -- see "Waiting-room intake exception" above
```

## Code style

- Every script starts by calling `cfg = setup_paths();` — never hardcode absolute paths.
- Use `fullfile()` for all paths. The user is on Windows; the cousin may be on macOS.
- Functions over scripts. One responsibility per file. Header comment block on every function.
- Comment the *why*, especially for filter choices and rejection thresholds — a physician,
  not a programmer, has to defend these numbers.
- Log every processing decision (channels interpolated, epochs rejected, ICs removed) into a
  per-recording QC struct saved alongside the cleaned data. Reproducibility matters more
  than speed here.
- Fail loudly. If a file has the wrong channel count or sampling rate, error out with a clear
  message rather than silently continuing.

## Verification

Before claiming a stage works, run it on a real sample file in `data/raw/` and show the
before/after PSD. Do not report success from code that has only been read, not executed.

## Git workflow — commit and push after every change

The MATLAB working folder and the git repository are the same folder, so any edit is
immediately live in MATLAB. Keeping GitHub in step is therefore just a matter of
committing promptly. Do this without being asked:

1. Make the change.
2. **Run it.** Execute the affected function in MATLAB and confirm it works.
3. `git add` the changed files, commit with a message explaining *why*, and `git push`.

**Commit after every verified change, not at the end of a session.** The point of the
history is that the user can review individual changes from his phone; one large commit
at the end destroys that.

**Never push code that has not been executed.** A broken push is worse than a slow one.
If a change cannot be verified — no sample data, MATLAB unavailable — say so and ask
before pushing.

Commit messages: one short subject line saying what changed, then a body explaining why.
Reference the threshold or behaviour affected. "Fix bug" is not a commit message.

Never commit anything under `data/`, `figures/`, `results/` or `toolboxes/`. `.gitignore`
covers these; do not add exceptions. Patient recordings committed to a public repository
are permanently public, because git keeps history.

After changing `src/import_recording.m`, run `test_edf_roundtrip(cfg)` before pushing.
