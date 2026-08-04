# Moving to Claude Code + GitHub

Everything on the code side is ready. This is what is left for you to do, in
order. Budget about 20 minutes, most of it downloading.

---

## Read this first: the project has moved

The project now lives at:

```
C:\Users\jacyp\Projects\EEG
```

It used to be in `C:\Users\jacyp\OneDrive\EEG`. It was moved because **OneDrive
deleted a git repository**, along with `.gitignore` and two other files, within
minutes of them being created.

This is a known and well-documented conflict, not bad luck. A `.git` folder is
thousands of tiny files that git rewrites constantly, often several times per
second. OneDrive tries to sync each one mid-write, and the two fight. The usual
results are corruption or silent deletion. Dropbox and Google Drive behave the
same way.

**Do not move the project back into OneDrive.** You lose nothing by keeping it
out: GitHub is version control and off-site backup, and it is far better at both
than OneDrive is. Every version of every file will be recoverable from GitHub
once step 3 is done.

The old copy is still at `C:\Users\jacyp\OneDrive\EEG`. Leave it until you are
happy everything works, then delete it so you cannot open the wrong one by
mistake.

---

## Where things stand

| | |
|---|---|
| Project moved out of OneDrive | ✅ Done — verified running from the new path |
| `.gitignore` protecting patient data | ✅ Recreated and verified |
| Licence, README, examples | ✅ Done |
| Git installed on Windows | ❌ **Not installed — do this first** |
| GitHub CLI installed | ❌ Not installed |
| Claude Code installed | ❌ Not installed |
| Repository created and pushed | ❌ Waiting on the above |

**Node.js is not needed.** Claude Code ships as a self-contained program now.

---

## Before you start: open PowerShell

Press the **Windows key**, type `powershell`, press **Enter**. You do not need
to run it as Administrator.

You can tell it is PowerShell because the prompt starts with `PS`, like
`PS C:\Users\jacyp>`.

---

## Step 1 — Install Git, GitHub CLI and Claude Code

Your machine already has `winget`, Windows' built-in installer, so these go in
from the command line with no setup screens to click through.

Paste one at a time, pressing Enter and waiting for each to finish:

```powershell
winget install Git.Git
```

```powershell
winget install GitHub.cli
```

```powershell
irm https://claude.ai/install.ps1 | iex
```

That last one is Anthropic's own installer rather than winget, because it keeps
Claude Code updated automatically. The winget version does not.

**Now close PowerShell and open a new one**, and **close and reopen MATLAB**.
Newly installed programs are only visible to windows opened afterwards.

Check all three:

```powershell
git --version
gh --version
claude --version
```

Three version numbers means you are ready.

### Two settings to fix

winget installs Git with its defaults, which leaves two things worth changing:

```powershell
git config --global core.editor notepad
git config --global init.defaultBranch main
```

The first stops Git dropping you into the Vim text editor, which is notoriously
hard to exit. The second makes new repositories use `main` as the branch name.

---

## Step 2 — Sign in to GitHub

```powershell
gh auth login
```

Answer with the arrow keys and Enter:

| Question | Answer |
|---|---|
| What account do you want to log into? | **GitHub.com** |
| What is your preferred protocol? | **HTTPS** |
| Authenticate Git with your GitHub credentials? | **Yes** |
| How would you like to authenticate? | **Login with a web browser** |

It shows an eight-character code and opens your browser. Paste the code and
approve.

---

## Step 3 — Create the repository and push

Paste this whole block. It creates the repository, makes the first commit, and
uploads it.

```powershell
cd C:\Users\jacyp\Projects\EEG
git init -b main
git add -A
git status --short
```

**Stop and look at that list before continuing.** It should be about 33 files —
code, documentation and two example images. If you see anything from `data/`,
`figures/`, `results/` or `toolboxes/`, something is wrong with `.gitignore`;
do not continue, and ask before pushing.

If the list looks right:

```powershell
git commit -m "Emotiv EPOC X preprocessing pipeline: local MATLAB/EEGLAB cleaning and 0-20 Hz power spectrum viewer"
gh repo create eeg-epocx-pipeline --public --source=. --remote=origin --push
```

It will then be live at `https://github.com/<your-username>/eeg-epocx-pipeline`.

`eeg-epocx-pipeline` is only a suggestion — change the name if you prefer.

---

## Step 4 — Connect Claude Code to MATLAB

The MATLAB MCP server is already on your machine at
`C:\Users\jacyp\Projects\EEG\Tools\matlab-mcp-server-windows-x64.exe`, so this is one command:

```powershell
cd C:\Users\jacyp\Projects\EEG
claude mcp add --transport stdio matlab -- C:\Users\jacyp\Projects\EEG\Tools\matlab-mcp-server-windows-x64.exe --matlab-session-mode=existing
```

`--matlab-session-mode=existing` is the important part: it attaches to the
MATLAB window you already have open rather than starting a hidden one, so you
can watch what happens.

**Do NOT add `--initial-working-folder` to that command.** The two options are
mutually exclusive, and the server refuses to start:

```
Error with supplied arguments: option "initial-working-folder" is not
compatible with MATLAB session mode set to "existing".
```

It makes sense once stated: if you are attaching to a MATLAB that is already
running, you do not get to choose where it started. The option only applies in
`new` or `auto` mode, where the server launches MATLAB itself.

Nothing is lost by leaving it out — `START_HERE.m` already changes to the
project folder, so MATLAB is in the right place before Claude Code attaches.

This failure is easy to misread, because `/mcp` reports only "failed" with no
reason. If a server ever fails, `claude --debug` prints the actual cause.

Then start it:

```powershell
claude
```

Claude Code needs a Claude Pro, Max, Team or Enterprise account — the free plan
does not include it. The first run opens a browser to sign in.

Once inside, type `/mcp` to confirm the `matlab` server is connected.

### Two things that will otherwise catch you out

**Start Claude Code from the project folder, every time.** The MATLAB server is
registered to this project only. Started from anywhere else — your home folder,
`C:\Windows\System32` — it does not appear in `/mcp` at all. It is not broken; it
simply is not loaded. `2 - Claude Code.bat` handles this, so use that rather
than typing `claude` wherever you happen to be.

**Share MATLAB before starting Claude Code, not after.** Claude Code checks the
connection once at startup. If MATLAB was not open and shared at that moment,
`/mcp` shows a failure and will not retry on its own. The order is: run
`START_HERE.m` in MATLAB, wait for `Shared and verified`, then start Claude Code.
If you get it the wrong way round, `/exit` and start it again.

It reads `CLAUDE.md` automatically, which contains the rule to run every change
in MATLAB and then commit and push it.

---

## How the "update both at once" workflow works

The MATLAB working folder and the git repository **are the same folder**. There
is no copying and no syncing — editing a file in MATLAB changes the repository's
working tree instantly. Keeping GitHub in step is only a matter of committing.

`CLAUDE.md` instructs Claude Code to, for every change:

1. Make the edit
2. **Run it in MATLAB** to confirm it works
3. Commit with an explanatory message and push

So asking Claude Code from your phone for a change produces a tested change,
live in MATLAB, and a pushed commit you can review in the GitHub app.

### One deliberate exception

Commits happen after a change is **verified**, not on every file save. Pushing
on save would publish half-finished, broken code to a public repository many
times a minute. If a change cannot be tested — MATLAB closed, no sample data —
Claude Code is told to say so and ask before pushing.

### Doing it by hand

If you edit something yourself in the MATLAB editor:

```matlab
sync_to_github('Raised epoch rejection to 200 uV because 150 was dropping usable data')
```

That stages, commits and pushes in one line. It refuses to run if `.gitignore`
is missing, and refuses to stage anything from `data/`, `figures/`, `results/`
or `toolboxes/` even if `.gitignore` is ever changed.

---

## Working from your phone

Once it is pushed:

- **Read code and history** — the GitHub mobile app, or github.com in a browser
- **Review a change** — open the commit; GitHub shows exactly which lines moved
- **Ask for changes** — this needs Claude Code running on the laptop, because it
  needs MATLAB to verify anything before pushing

Review from anywhere; editing needs the laptop awake.

---

## If something goes wrong

**"git is not recognized"** — Step 1 was skipped, or the window was not reopened
afterwards.

**`gh repo create` says the name is taken** — pick a different name.

**Push rejected** — run `git pull --rebase`, then push again.

**Claude Code cannot see MATLAB** — make sure MATLAB is open and `START_HERE.m`
has been run. It calls `shareMATLABSession()`, which is what makes the session
visible.

**Git says "index.lock exists" or similar** — a previous git command was
interrupted. Delete the named `.lock` file inside `.git` and try again.
