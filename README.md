# Hunkwise (patched build)
Review Claude Code's edits hunk by hunk, like you would with Copilot ✅❌

Claude Code (unlike Copilot or Cursor) doesn't come with a way to accept or discard its changes per hunk inside VS Code. [hunkwise](https://github.com/molon/hunkwise) fills that gap, but out of the box it flags *every* change it didn't see you make in the editor. That includes things like Discard Changes in Source Control, a formatter like Black running on save, or a file that another extension happens to keep open in the background. In practice this meant hunkwise regularly showed hunks for changes that had nothing to do with Claude, or missed Claude's changes entirely.

This build flips that around, so hunkwise only shows the changes it knows Claude made. Claude Code tells it exactly which file it is about to edit and what the file looked like before and after (through Claude Code hooks), and everything else is accepted silently. On top of that, this build turns itself on in every folder you open, keeps its data in VS Code's own storage (so no `.vscode/hunkwise` folders show up in your projects), and also tracks files in subfolders on Windows (which the original version didn't).

It also makes Claude Code's chats a bit nicer to juggle: text you typed but didn't send stays with its chat when you switch to another one, and you get a notification when a chat waits for you (see [Claude Code chats](#claude-code-chats)).

## Installation
To update an earlier install, pull this repo and run the install script again: newer versions can need new Claude Code hooks.


### Windows
1. Clone this repo anywhere.
2. Open a PowerShell terminal in the cloned folder and run `./install.ps1`.
3. Fully quit VS Code (all windows, not just the one you're in) and reopen it.

If PowerShell says that running scripts is disabled on this system, Windows PowerShell's default execution policy is blocking the script. Run it like this instead:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

### Linux and macOS
1. Clone this repo anywhere.
2. Run `bash install.sh` from it (it needs `python3` to edit the JSON config files).
3. Fully quit VS Code (all windows, not just the one you're in) and reopen it.

### Dev containers
In a dev container, both hunkwise and Claude Code run inside the container, so that's also where the extension and the Claude Code hooks need to be. The one exception is `argv.json` (which turns on the API hunkwise needs): that one belongs to the VS Code on your host. So install hunkwise on your host first, using the steps above.

After that, your container may already have everything. VS Code can be set up to copy your local extensions into every new container (it then copies this patched build, not the original from the Marketplace), and the hooks can come along with a synced `~/.claude/settings.json` (e.g. through a dotfiles repo). If one of the two is missing, copy this folder into the container, run `bash install.sh` there, and run **Developer: Reload Window** afterwards. Inside a container, the script installs the extension into the container's VS Code server and leaves `argv.json` alone.

## What shows up as a hunk
Only changes Claude makes with its file tools: `Edit`, `Write` (including new files) and `NotebookEdit`.

Everything else, like your own typing, a Black formatting run, or a Git discard, is accepted without a hunk. The one exception is when you edit lines inside a Claude hunk: your edit then becomes part of that hunk (as if Claude wrote it), and the hunk stays until you accept or discard it.

## Reviewing
- Removed lines are shown in red above the hunk, and wrap just like the rest of the editor does. Within a hunk, the exact words that changed get a darker highlight, in the same colors as VS Code's own diffs. Scrolling with the mouse wheel works over them too, just like over the rest of the editor.
- Every hunk has its **Accept** and **Discard** buttons hovering over the top right of its removed lines. After you click one, the editor scrolls to the next hunk and puts its buttons in exactly the same spot, so you can click through a file without moving your mouse. A hunk that only adds lines has nothing to hover over, so its buttons get a line of their own above it, since VS Code doesn't let extensions draw over the editor's text.
- To accept or discard all changes in a file (or all files) at once, use the hunkwise panel. The editor title bar also has buttons for the file you're looking at, plus arrows to jump to the previous or next hunk.
- Files with hunks to review get a purple ✦ badge in the Explorer, and so do the folders they're in, so you can see what Claude changed without opening the hunkwise panel.

## Claude Code chats
### Unsent text stays with its chat
Claude Code empties the message box whenever you switch to another chat (in the side bar or in a tab), so a half-written message is gone when you come back. With hunkwise, the text you typed stays with the chat you typed it in, and comes back when you switch back to that chat, also after VS Code reloads or restarts.

VS Code doesn't let one extension reach into another extension's UI, so hunkwise patches Claude Code's chat UI (`webview/index.js` in Claude Code's extension folder) to do this. It patches every Claude Code version it finds, and also new versions as soon as Claude Code updates itself, before VS Code loads them. The first time, hunkwise asks you to reload VS Code, since the chat UI that's already open doesn't have the patch yet. If an update changes Claude Code's code so much that hunkwise no longer recognizes the message box, hunkwise leaves that version alone: Claude Code then works as usual, just without keeping your text, and the hunkwise log (Output panel > Hunkwise) says so.

### Notifications when a chat waits for you
When a chat asks you a question, has a plan for you to approve, or asks permission to use a tool, hunkwise makes sure you notice:
- On Windows, a Windows notification with a sound and the chat's title, which stays on screen until you click it. **Open Chat** brings VS Code to the front with that chat open. The first time, VS Code asks whether hunkwise may open the link; tick the box so it doesn't ask again.
- On Windows, when VS Code isn't the app in front, its taskbar button also gets a red background (like a chat app with an unread message) until you switch to VS Code.
- On Linux and macOS, which don't get these, a notification in the VS Code window of that chat instead, with an **Open Chat** button. It stays until you click **Open Chat** or **Dismiss** (VS Code only keeps error notifications open, so it has the red error icon).

Chats that run in a terminal (the `claude` CLI) are announced too, but without a way to open them.

## Known limitations
- Files Claude changes through Bash (`sed`, scripts, git) are not shown, including deleted files. Claude Code has no delete tool, and I couldn't find a way to attribute Bash changes to Claude without also catching things you did yourself at the same moment. I'd rather miss those than show false positives.
- Changes Claude makes while no VS Code window is open are not shown, since there's nothing listening at that point.
- In a dev container that works on a folder from your Windows drive (the default when you open a local folder in a container), Linux never gets notified when a file changes. VS Code itself has the same problem, so a file that's already open can keep showing its old content until you click it. hunkwise makes up for it by comparing the files it's reviewing with the disk every 2 seconds, and its panel always reads from disk, so Claude's changes still show up there right away. If you want to get rid of the problem entirely, keep the repo inside WSL or in a container volume (**Dev Containers: Clone Repository in Container Volume**), which also makes the container a lot faster.
- Only files inside the folder you have open in VS Code are tracked. If Claude edits a file somewhere else on your PC (e.g. a config file in your home folder), hunkwise ignores it. This is baked into how hunkwise works: it stores its baselines in a small git repo tied to your workspace folder (and git can't track files outside it), and it only watches that folder for changes. Fixing this would mean a separate storage and file watcher for outside files, plus deciding which VS Code window should show them when you have several open, so I left it out for now.
- A change of more than about 500 lines (for example when Claude rewrites most of a large file, or changes all of its line endings) shows up as one hunk, from its first to its last changed line. Finding the smaller hunks in there can take seconds, and VS Code (Claude Code included) would freeze in the meantime, see below. For the same reason, if you change more than about 1250 lines yourself in a file that's under review (for example by reformatting it), its review ends: Claude's changes stay in the file, but they're no longer shown as hunks, since hunkwise can't tell them apart from yours anymore.
- Only the text of an unsent message is kept: files and images you attached to it are still dropped when you switch chats. Text survives a reload because VS Code saves it with the chat panel's state when it shuts down; if VS Code crashes, the last minute of typing can be lost. Each Claude Code panel (the side bar, or a tab) keeps its own drafts, for the 50 chats you typed in last.
- A chat that waits for you is announced even when you're already looking at it, since hunkwise can't see which chat Claude Code shows. Permission prompts of subagents are not announced: most subagents run in the background, where Claude Code can't ask you anyway.
- The notifications only come from the VS Code window whose folder the chat runs in, and the Windows notification and taskbar highlight only exist on Windows (not on Linux, macOS or in a dev container).

## How it works (for nerds)
To know what Claude edits, hunkwise runs a tiny local server on `127.0.0.1:47821` and Claude Code calls it right before and after every Edit/Write/NotebookEdit. Claude Code also calls it right before every AskUserQuestion (a question for you) and ExitPlanMode (a plan for you), and for every permission prompt, which is how hunkwise knows a chat waits for you. The install script registers these hooks in `~/.claude/settings.json`, and your other settings and hooks stay untouched. The hooks send the `CLAUDE_CODE_ENTRYPOINT` of the chat along, so hunkwise can tell a chat in VS Code from one in a terminal. If VS Code isn't running, the hooks just find nothing listening and Claude Code carries on normally.

The original hunkwise copies every file in your workspace into a private git repo when you turn it on, so it has something to compare against when any file changes. This build doesn't need that, since the hooks tell it what a file looked like right before Claude changed it. So it only stores the files that are under review, and drops each one again once you've accepted or discarded all its hunks. Turning it on in a big repo costs nothing, and a leftover copy from an older version is cleaned up the next time VS Code starts.

VS Code runs all extensions in one extension host process, so whenever hunkwise keeps it busy, Claude Code's chat stops responding too. hunkwise is careful about that: it reads all its stored files through a single git process (starting a process takes 10-20 ms of the extension host's time on Windows, so starting one per file froze VS Code for minutes when thousands of files were left over from an older version), it loads the `.gitignore` rules in the background, it ignores changes to files that aren't under review, and it gives up on diffs that would take too long.

## Turning it off
To turn it off for one folder, go to the hunkwise panel > gear icon > **Disable**. It stays off in that folder until you click **Enable** again.

## Files
| File | Purpose |
| --- | --- |
| `hunkwise-0.0.29.vsix` | The pre-built extension, based on molon/hunkwise commit `d609507`. |
| `install.ps1` | Does the actual work on Windows: installs the `.vsix` into every VS Code build it finds, adds `"enable-proposed-api": ["molon.hunkwise"]` to `argv.json` (hunkwise needs an API that VS Code only enables this way), and registers the Claude Code hooks. Running it again is safe, since it never adds anything twice. |
| `install.sh` | The same as `install.ps1`, but for Linux, macOS and dev containers (inside a container, it leaves `argv.json` alone). |
| `hunkwise-auto-enable.patch` | All source changes compared to upstream hunkwise. You only need this if you want to rebuild a newer hunkwise version with the same changes. |
