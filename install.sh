#!/usr/bin/env bash
# Installs the patched hunkwise extension (auto-enable, no per-folder files, only Claude Code's own
# edits become hunks) on Linux and macOS, including inside dev containers. It installs the .vsix
# into every VS Code build it finds, enables the proposed API it needs, and registers the Claude
# Code hooks that tell hunkwise what Claude edits.
# Run: bash install.sh (install.ps1 is the Windows version of this script).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Must match HOOK_PORT and HOOK_PATH in the extension (src/claudeHooks.ts).
HOOK_URL='http://127.0.0.1:47821/hunkwise/claude-hook'
HOOK_EVENTS='PreToolUse PostToolUse PostToolUseFailure PermissionDenied'
HOOK_MATCHER='Edit|Write|MultiEdit|NotebookEdit'

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is needed to update the JSON config files, but it isn't installed." >&2
  exit 1
fi

# Add "enable-proposed-api": ["molon.hunkwise"] to argv.json without touching other settings.
# argv.json allows comments, so it is edited as text instead of being parsed as JSON.
update_argv() {
  python3 - "$1" <<'PY'
import re, sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists():
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('{\n\t"enable-proposed-api": ["molon.hunkwise"]\n}\n', encoding="utf-8")
    print(f"  Created {path}")
    sys.exit()
text = path.read_text(encoding="utf-8")
if "molon.hunkwise" in text:
    print(f"  {path} already enables hunkwise")
    sys.exit()
if re.search(r'"enable-proposed-api"\s*:\s*\[\s*\]', text):
    text = re.sub(r'("enable-proposed-api"\s*:\s*\[)\s*\]', r'\1"molon.hunkwise"]', text, count=1)
elif re.search(r'"enable-proposed-api"\s*:\s*\[', text):
    text = re.sub(r'("enable-proposed-api"\s*:\s*\[)\s*', r'\1"molon.hunkwise", ', text, count=1)
else:
    # Insert as the first property; add a comma only if other properties follow.
    brace = text.index("{")
    rest = text[brace + 1 :].lstrip("\r\n")
    comma = "," if re.search(r'^\s*"', rest, re.MULTILINE) else ""
    text = text[: brace + 1] + f'\n\t"enable-proposed-api": ["molon.hunkwise"]{comma}\n' + rest
path.write_text(text, encoding="utf-8")
print(f"  Updated {path}")
PY
}

# Register hunkwise's hooks in Claude Code's user settings, leaving all other settings and hooks as they are.
update_claude_settings() {
  python3 - "$1" "$HOOK_URL" "$HOOK_MATCHER" $HOOK_EVENTS <<'PY'
import json, sys
from pathlib import Path

path, url, matcher, events = Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4:]
original = path.read_text(encoding="utf-8") if path.exists() else None
try:
    settings = json.loads(original) if original and original.strip() else {}
except json.JSONDecodeError as err:
    sys.exit(f"Could not read {path} as JSON, so it was left alone: {err}")

hooks = settings.setdefault("hooks", {})
# Drop hunkwise entries from an earlier install, so running this again never duplicates them.
for event in list(hooks):
    groups = []
    for group in hooks[event]:
        if isinstance(group, dict) and "hooks" in group:
            group["hooks"] = [h for h in group["hooks"] if not str(h.get("url", "")).endswith("/hunkwise/claude-hook")]
            if not group["hooks"]:
                continue
        groups.append(group)
    if groups:
        hooks[event] = groups
    else:
        del hooks[event]

for event in events:
    hooks.setdefault(event, []).append({"matcher": matcher, "hooks": [{"type": "http", "url": url, "timeout": 5}]})

text = json.dumps(settings, indent=2, ensure_ascii=False) + "\n"
if text == original:
    print(f"  {path} already has the hunkwise hooks")
    sys.exit()
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(text, encoding="utf-8")
print(f"  Registered the hunkwise hooks in {path}")
PY
}

# Only used for testing the argv.json and Claude Code settings updates on a copy.
case "${1:-}" in
  --test-argv) update_argv "$2"; exit ;;
  --test-claude-settings) update_claude_settings "$2"; exit ;;
esac

vsix="$(ls "$HERE"/hunkwise-*.vsix 2>/dev/null | head -n 1 || true)"
if [ -z "$vsix" ]; then
  echo "No hunkwise .vsix found next to this script." >&2
  exit 1
fi

# Each entry is "name|cli|argv.json". Inside a dev container (or over Remote SSH/WSL), the
# extension goes into the VS Code server, and argv.json is left alone: it belongs to the VS Code
# that runs on the host, so install hunkwise there as well.
builds=()
for server in "$HOME/.vscode-server" "$HOME/.vscode-server-insiders" "$HOME/.vscode-remote"; do
  cli="$(ls -t "$server"/bin/*/bin/code-server* 2>/dev/null | head -n 1 || true)"
  if [ -n "$cli" ]; then builds+=("VS Code server ($server)|$cli|"); fi
done
if [ ${#builds[@]} -eq 0 ]; then
  for cmd in code code-insiders; do
    cli="$(command -v "$cmd" || true)"
    if [ -z "$cli" ]; then
      case "$cmd" in
        code) cli='/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code' ;;
        code-insiders) cli='/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/bin/code' ;;
      esac
    fi
    [ -x "$cli" ] || continue
    if [ "$cmd" = code ]; then argv="$HOME/.vscode/argv.json"; else argv="$HOME/.vscode-insiders/argv.json"; fi
    builds+=("$cmd|$cli|$argv")
  done
fi

if [ ${#builds[@]} -eq 0 ]; then
  echo "No VS Code installation found." >&2
  exit 1
fi

for build in "${builds[@]}"; do
  IFS='|' read -r name cli argv <<<"$build"
  echo "Installing into $name..."
  "$cli" --install-extension "$vsix" --force
  if [ -n "$argv" ]; then update_argv "$argv"; fi
done

echo "Registering Claude Code hooks..."
update_claude_settings "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

echo
echo "Done. Fully quit VS Code (all windows) and reopen it. In a dev container, run \"Developer: Reload Window\" instead."
