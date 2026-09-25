# Hunkwise (patched build) for Windows
Review Claude Code's edits hunk by hunk, like you would with Copilot ✅❌

Claude Code (unlike Copilot or Cursor) doesn't come with a way to accept or discard its changes per hunk inside VS Code. [hunkwise](https://github.com/molon/hunkwise) fills that gap, but out of the box it flags *every* change it didn't see you make in the editor. That includes things like Discard Changes in Source Control, a formatter like Black running on save, or a file that another extension happens to keep open in the background. In practice this meant hunkwise regularly showed hunks for changes that had nothing to do with Claude, or missed Claude's changes entirely.

This build flips that around, so hunkwise only shows the changes it knows Claude made. Claude Code tells it exactly which file it is about to edit and what the file looked like before and after (through Claude Code hooks), and everything else is accepted silently. On top of that, this build turns itself on in every folder you open, keeps its data in VS Code's own storage (so no `.vscode/hunkwise` folders show up in your projects), and also tracks files in subfolders on Windows (which the original version didn't).

## Installation
1. Unzip this folder anywhere.
2. Double-click `install.cmd`.
3. Fully quit VS Code (all windows, not just the one you're in) and reopen it.

## What shows up as a hunk
Only changes Claude makes with its file tools: `Edit`, `Write` (including new files) and `NotebookEdit`.

Everything else, like your own typing or a discard in Source Control, is accepted without a hunk. If you change a file that still has Claude hunks in it, the Claude hunks your change overlaps disappear (since you clearly already dealt with those), and the rest stay where they are.

## Known limitations
- Files Claude changes through Bash (`sed`, scripts, git) are not shown, including deleted files. Claude Code has no delete tool, and I couldn't find a way to attribute Bash changes to Claude without also catching things you did yourself at the same moment. I'd rather miss those than show false positives.
- Changes Claude makes while no VS Code window is open are not shown, since there's nothing listening at that point.
- Only files inside the folder you have open in VS Code are tracked. If Claude edits a file somewhere else on your PC (e.g. a config file in your home folder), hunkwise ignores it. This is baked into how hunkwise works: it stores its baselines in a small git repo tied to your workspace folder (and git can't track files outside it), and it only watches that folder for changes. Fixing this would mean a separate storage and file watcher for outside files, plus deciding which VS Code window should show them when you have several open, so I left it out for now.

## Claude Code hooks
To know what Claude edits, hunkwise runs a tiny local server on `127.0.0.1:47821` and Claude Code calls it right before and after every Edit/Write/NotebookEdit. `install.cmd` registers these hooks in `%USERPROFILE%\.claude\settings.json` (your other settings and hooks stay untouched). If VS Code isn't running, the hooks just find nothing listening and Claude Code carries on normally.

## Turning it off
To turn it off for one folder, go to the hunkwise panel > gear icon > **Disable**. It stays off in that folder until you click **Enable** again.

## Files
| File | Purpose |
| --- | --- |
| `hunkwise-0.0.29.vsix` | The pre-built extension, based on molon/hunkwise commit `d609507`. |
| `install.cmd` | The thing you double-click. It just starts `install.ps1` with the right PowerShell flags. |
| `install.ps1` | Does the actual work: installs the `.vsix` into every VS Code build it finds, adds `"enable-proposed-api": ["molon.hunkwise"]` to `argv.json` (hunkwise needs an API that VS Code only unlocks this way), and registers the Claude Code hooks. Running it again is safe, since it never adds anything twice. |
| `hunkwise-auto-enable.patch` | All source changes compared to upstream hunkwise. You only need this if you want to rebuild a newer hunkwise version with the same changes. |
