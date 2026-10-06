# Installs the patched hunkwise extension (auto-enable, no per-folder files, Windows subfolder fix,
# only Claude Code's own edits become hunks) into every VS Code build found on this PC, enables the
# proposed API it needs, and registers the Claude Code hooks that tell hunkwise what Claude edits.
# Run: ./install.ps1 from a PowerShell terminal in this folder.

param(
    [string]$TestArgv,           # Only used for testing the argv.json update on a copy.
    [string]$TestClaudeSettings  # Only used for testing the Claude Code settings update on a copy.
)

$ErrorActionPreference = 'Stop'

# Must match HOOK_PORT and HOOK_PATH in the extension (src/claudeHooks.ts).
$HookUrl = 'http://127.0.0.1:47821/hunkwise/claude-hook'
$HookEvents = @('PreToolUse', 'PostToolUse', 'PostToolUseFailure', 'PermissionDenied')
$HookMatcher = 'Edit|Write|MultiEdit|NotebookEdit'

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
}

# Serialize to JSON with 2-space indentation (Windows PowerShell's ConvertTo-Json output is hard to read).
function ConvertTo-PrettyJson($Value, [string]$Indent = '') {
    $inner = $Indent + '  '
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [string]) {
        $escaped = $Value.Replace('\', '\\').Replace('"', '\"').Replace("`n", '\n').Replace("`r", '\r').Replace("`t", '\t')
        $escaped = [regex]::Replace($escaped, '[\x00-\x1f]', { param($m) '\u{0:x4}' -f [int][char]$m.Value })
        return '"' + $escaped + '"'
    }
    if ($Value -is [System.ValueType]) { return [System.Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture) }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $props = @($Value.PSObject.Properties)
        if ($props.Count -eq 0) { return '{}' }
        $parts = $props | ForEach-Object { $inner + (ConvertTo-PrettyJson $_.Name) + ': ' + (ConvertTo-PrettyJson $_.Value $inner) }
        return "{`n" + ($parts -join ",`n") + "`n$Indent}"
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $items = @($Value)
        if ($items.Count -eq 0) { return '[]' }
        $parts = $items | ForEach-Object { $inner + (ConvertTo-PrettyJson $_ $inner) }
        return "[`n" + ($parts -join ",`n") + "`n$Indent]"
    }
    throw "Cannot write a value of type $($Value.GetType().FullName) as JSON."
}

# Register hunkwise's hooks in Claude Code's user settings, leaving all other settings and hooks as they are.
function Update-ClaudeSettings([string]$Path) {
    $original = $null
    $settings = [pscustomobject]@{}
    if (Test-Path $Path) {
        $original = [System.IO.File]::ReadAllText($Path)
        if ($original.Trim()) {
            try { $settings = $original | ConvertFrom-Json }
            catch { throw "Could not read $Path as JSON, so it was left alone: $($_.Exception.Message)" }
        }
    }

    if (-not $settings.PSObject.Properties['hooks']) {
        $settings | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{})
    }
    $hooks = $settings.hooks

    # Drop hunkwise entries from an earlier install, so running this again never duplicates them.
    foreach ($prop in @($hooks.PSObject.Properties)) {
        $groups = @()
        foreach ($group in @($prop.Value)) {
            if ($null -eq $group -or -not $group.PSObject.Properties['hooks']) { $groups += , $group; continue }
            $kept = @(@($group.hooks) | Where-Object { -not ($_.PSObject.Properties['url'] -and $_.url -like '*/hunkwise/claude-hook') })
            if ($kept.Count -gt 0) { $group.hooks = $kept; $groups += , $group }
        }
        if ($groups.Count -gt 0) { $hooks.($prop.Name) = $groups } else { $hooks.PSObject.Properties.Remove($prop.Name) }
    }

    foreach ($hookEvent in $HookEvents) {
        $entry = [pscustomobject][ordered]@{ type = 'http'; url = $HookUrl; timeout = 5 }
        $group = [pscustomobject][ordered]@{ matcher = $HookMatcher; hooks = @($entry) }
        if ($hooks.PSObject.Properties[$hookEvent]) {
            $hooks.$hookEvent = @(@($hooks.$hookEvent) + $group)
        } else {
            $hooks | Add-Member -NotePropertyName $hookEvent -NotePropertyValue @($group)
        }
    }

    $text = (ConvertTo-PrettyJson $settings) + "`n"
    if ($null -ne $original -and $text -eq $original) {
        Write-Host "  $Path already has the hunkwise hooks"
        return
    }
    New-Item -ItemType Directory -Force (Split-Path $Path) | Out-Null
    Write-Utf8NoBom $Path $text
    Write-Host "  Registered the hunkwise hooks in $Path"
}

# Add "enable-proposed-api": ["molon.hunkwise"] to argv.json without touching other settings.
function Update-Argv([string]$Path) {
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Force (Split-Path $Path) | Out-Null
        Write-Utf8NoBom $Path "{`n`t`"enable-proposed-api`": [`"molon.hunkwise`"]`n}`n"
        Write-Host "  Created $Path"
        return
    }
    $text = [System.IO.File]::ReadAllText($Path)
    if ($text -match 'molon\.hunkwise') {
        Write-Host "  $Path already enables hunkwise"
        return
    }
    if ($text -match '"enable-proposed-api"\s*:\s*\[\s*\]') {
        $text = [regex]::Replace($text, '("enable-proposed-api"\s*:\s*\[)\s*\]', '$1"molon.hunkwise"]', 1)
    } elseif ($text -match '"enable-proposed-api"\s*:\s*\[') {
        $text = [regex]::Replace($text, '("enable-proposed-api"\s*:\s*\[)\s*', '$1"molon.hunkwise", ', 1)
    } else {
        # Insert as the first property; add a comma only if other properties follow.
        $brace = $text.IndexOf('{')
        $rest = $text.Substring($brace + 1)
        $comma = if ($rest -match '(?m)^\s*"') { ',' } else { '' }
        $text = $text.Substring(0, $brace + 1) + "`n`t`"enable-proposed-api`": [`"molon.hunkwise`"]$comma`n" + $rest
    }
    Write-Utf8NoBom $Path $text
    Write-Host "  Updated $Path"
}

if ($TestArgv) { Update-Argv $TestArgv; return }
if ($TestClaudeSettings) { Update-ClaudeSettings $TestClaudeSettings; return }

$vsix = Get-ChildItem -Path $PSScriptRoot -Filter 'hunkwise-*.vsix' | Select-Object -First 1
if (-not $vsix) { throw "No hunkwise .vsix found next to this script." }

$builds = @(
    @{ Name = 'VS Code';          Cli = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd";                   Argv = "$env:USERPROFILE\.vscode\argv.json" },
    @{ Name = 'VS Code (system)'; Cli = "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd";                            Argv = "$env:USERPROFILE\.vscode\argv.json" },
    @{ Name = 'VS Code Insiders'; Cli = "$env:LOCALAPPDATA\Programs\Microsoft VS Code Insiders\bin\code-insiders.cmd"; Argv = "$env:USERPROFILE\.vscode-insiders\argv.json" }
)

$installed = 0
$argvDone = @{}
foreach ($b in $builds) {
    if (-not (Test-Path $b.Cli)) { continue }
    Write-Host "Installing into $($b.Name)..."
    # VS Code's own CLI prints a Node.js deprecation warning (url.parse()) that has nothing to do with hunkwise.
    $nodeOptions = $env:NODE_OPTIONS
    $env:NODE_OPTIONS = "$nodeOptions --no-deprecation".Trim()
    try { & $b.Cli --install-extension $vsix.FullName --force }
    finally { $env:NODE_OPTIONS = $nodeOptions }
    $installed++
    if (-not $argvDone[$b.Argv]) {
        Update-Argv $b.Argv
        $argvDone[$b.Argv] = $true
    }
}

if ($installed -eq 0) { throw "No VS Code installation found." }

Write-Host "Registering Claude Code hooks..."
Update-ClaudeSettings "$env:USERPROFILE\.claude\settings.json"

Write-Host "`nDone. Fully quit VS Code (all windows) and reopen it."
