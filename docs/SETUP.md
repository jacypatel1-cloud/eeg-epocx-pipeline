# Setup — MATLAB + EEGLAB + Claude

Windows instructions. Do these in order; the whole thing takes about 30 minutes, most of it
download time.

---

## 1. Confirm MATLAB and its toolboxes

EEGLAB needs **R2016b or later** (the MATLAB MCP server needs **R2021a or later**, so target
that). It also needs two toolboxes:

- Signal Processing Toolbox
- Statistics and Machine Learning Toolbox

In the MATLAB Command Window:

```matlab
ver
```

If either toolbox is missing, install it via **Home > Add-Ons > Get Add-Ons**. On a student or
academic licence they are usually already included.

---

## 2. Install EEGLAB

**Do not** download the ZIP from the EEGLAB GitHub repo — it is missing bundled plugins.

1. Go to <https://eeglab.org/others/How_to_download_EEGLAB.html> and download the latest
   release ZIP.
2. Extract it into `toolboxes\` in this project, so you end up with something like
   `toolboxes\eeglab2025.0\`. Avoid spaces and special characters anywhere in the path.
3. In MATLAB, `cd` to this project folder and run:

```matlab
addpath('src');
cfg = setup_paths();   % finds EEGLAB in toolboxes\, starts it headless
check_env();           % reports missing toolboxes and plugins
```

`setup_paths` deliberately adds only the top-level EEGLAB folder and then calls
`eeglab nogui`, which lets EEGLAB manage its own subpaths. Adding EEGLAB with
`addpath(genpath(...))` is a common mistake and causes function shadowing.

### Required EEGLAB plugins

`check_env` will flag any that are missing. Install from the EEGLAB GUI via
**File > Manage EEGLAB extensions**:

| Plugin | Why |
|---|---|
| **BIOSIG** | reads EDF/BDF files (`pop_biosig`) |
| **firfilt** | the FIR filters (`pop_eegfiltnew`) — usually bundled |
| **clean_rawdata** | ASR artifact correction + bad channel detection |
| **ICLabel** | automatic classification of ICA components (eye, muscle, line noise) |

ICLabel plus ASR is the combination that does the heavy lifting on the noise your cousin is
seeing — ASR for large transient artifacts, ICA/ICLabel for stereotyped ones like blinks and
jaw clench.

### Channel locations

Download the EPOC X `.ced` file into `data\`:

<https://raw.githubusercontent.com/huytungst/EEGEmotions-27/main/emotivX_channels_location.ced>

Save it as `data\emotivX_channels_location.ced`. Without channel locations, ICA topographies
and interpolation will not work.

---

## 3. Set up a MATLAB "project" (optional but useful)

Two ways to do this:

**Lightweight (what this repo assumes):** the folder structure plus `setup_paths.m`. Run
`setup_paths()` at the start of each session. Portable, git-friendly, no MATLAB-specific
metadata files.

**MATLAB Project (`.prj`):** in MATLAB, **Home > New > Project > From Folder**, point it at
this folder. Then in **Project Settings** set `src` as a path folder and `setup_paths.m` as a
startup file, so paths load automatically when you open the project. This adds dependency
analysis and a file-change view. It also adds binary metadata that plays badly with git.

Start with the lightweight version. Add the `.prj` later if the dependency graph becomes
useful.

---

## 4. Connect Claude to MATLAB

MathWorks publishes an official MCP server that lets Claude write MATLAB code, run it on your
machine, and read back the actual output — including errors. That feedback loop is the whole
point: without it Claude is guessing.

Repo: <https://github.com/matlab/matlab-mcp-server>

Tools it exposes: `detect_matlab_toolboxes`, `check_matlab_code`, `evaluate_matlab_code`,
`run_matlab_file`, `run_matlab_test_file`.

### Prerequisite

MATLAB must be on your system PATH. Check in PowerShell:

```powershell
matlab -help
```

If that fails, add `C:\Program Files\MATLAB\R20XXx\bin` to your PATH (Windows Settings >
search "environment variables" > Edit the system environment variables > Environment
Variables > Path > New), then restart your terminal.

### Option A — Claude Desktop (easiest, works with this app)

1. In Claude Desktop: **Settings > Extensions > Browse extensions**, install the
   **Filesystem** extension by Anthropic, and grant it access to this project folder.
2. Download `matlab-mcp-server.mcpb` from
   <https://github.com/matlab/matlab-mcp-server/releases/latest>.
3. Double-click the `.mcpb` file and click **Install** in Claude Desktop. (Or
   **Settings > Extensions > Advanced Settings > Install Extension**.)
4. **Settings > Extensions > Configure** to set arguments — set
   `initial-working-folder` to this project folder.

### Option B — Claude Code CLI

1. Download `matlab-mcp-server-windows-x64.exe` from
   <https://github.com/matlab/matlab-mcp-server/releases/latest>. Put it somewhere stable,
   e.g. `C:\Users\jacyp\Projects\EEG\Tools\matlab-mcp-server-windows-x64.exe`.
2. In a terminal, from this project folder:

```powershell
claude mcp add --transport stdio matlab -- C:\Users\jacyp\Projects\EEG\Tools\matlab-mcp-server-windows-x64.exe --matlab-session-mode=existing
```

3. Start `claude` **from this folder** — the server is registered to this project, so
   started anywhere else it will not appear in `/mcp` at all. It picks up `CLAUDE.md`
   automatically as project rules.
4. Verify with `/mcp` — you should see the `matlab` server connected and its five tools.

To remove later: `claude mcp remove matlab`.

### Useful arguments

| Argument | Use |
|---|---|
| `--matlab-root=C:\\Program Files\\MATLAB\\R2025b` | pick a specific MATLAB if you have several |
| `--initial-working-folder=<project>` | MATLAB starts here. **Only valid in `new`/`auto` mode** |
| `--matlab-display-mode=nodesktop` | run headless, no MATLAB window |
| `--matlab-session-mode=existing` | attach to a MATLAB you already have open |
| `--disable-telemetry=true` | opt out of MathWorks usage data |

> **`--initial-working-folder` and `--matlab-session-mode=existing` cannot be
> combined.** The server refuses to start with
> `option "initial-working-folder" is not compatible with MATLAB session mode set
> to "existing"`, and `/mcp` shows only "failed" with no reason given. Attaching
> to a running MATLAB means you do not get to choose where it started.
>
> When an MCP server fails, `claude --debug` prints the real cause.

### Attaching to an already-open MATLAB

Handy when you want to inspect variables yourself between agent runs. One-time setup:

```powershell
C:\Users\jacyp\Projects\EEG\Tools\matlab-mcp-server-windows-x64.exe --setup-matlab
```

This installs the *MATLAB MCP Server Toolbox* add-on. Then in your running MATLAB session:

```matlab
shareMATLABSession()
```

Add that line to your MATLAB `startup.m` to make it automatic. Then run the server with
`--matlab-session-mode=existing`.

---

## 5. Sanity check

Ask Claude to run this. If it comes back with a report rather than an apology, the link works:

```matlab
cd('C:\Users\jacyp\Projects\EEG');
addpath('src');
cfg = setup_paths();
check_env();
```

---

## Security note

The MCP server runs whatever MATLAB code the agent writes, on your machine, with your
permissions. Review tool calls before approving them — particularly anything that deletes or
overwrites files in `data\raw\`. Raw recordings should be treated as write-once.

## Sources

- [Download EEGLAB — EEGLAB Wiki](https://eeglab.org/others/How_to_download_EEGLAB.html)
- [Installing EEGLAB — EEGLAB Wiki](https://eeglab.org/tutorials/01_Install/Install.html)
- [EEGLAB System Requirements](https://sccn.ucsd.edu/eeglab/ressources.php)
- [matlab/matlab-mcp-server (GitHub)](https://github.com/matlab/matlab-mcp-server)
- [Run MATLAB with AI Agentic and AI Assistant Applications — MathWorks](https://www.mathworks.com/help/cloudcenter/ug/run-matlab-with-ai-agentic-and-ai-assistant-applications.html)
