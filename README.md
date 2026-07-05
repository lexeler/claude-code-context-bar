# context-bar

A minimalistic **context-usage gauge** for the [Claude Code](https://claude.com/claude-code) status line.

It renders a single-line gradient bar that fills up — cool **blue** when the
context window is nearly empty, shifting smoothly to **blood-red** as it fills:

```
░░░░░░░░░░░░░░░░  0%      just started
███░░░░░░░░░░░░░  22%     plenty of room
█████████░░░░░░░  60%     getting fuller
███████████████░  95%     almost out
```

The filled portion is a blue→red gradient; the number is the percent of the
context window **used**. One glance tells you how much room is left.

## Why

- **Smooth in a tiny footprint** — each character cell is split into two colour
  sub-cells with a half-block glyph (`▌`: foreground paints the left half,
  background the right), so the default 16-char bar carries **32 gradient steps**
  and fills at half-cell precision — a fluid ramp that still fits one short line.
- **Featherweight** — pure Bash, **zero** external processes (no `jq`, `python`,
  `node`, no forks), no network, no background daemon. Runs in a few ms and exits.
- **Accurate** — reads the percentage straight from Claude Code's own
  `context_window.used_percentage`, scoped so it never picks up the unrelated
  rate-limit percentages in the same payload.
- **Robust** — tolerant of whitespace, floats, missing fields and malformed
  input; clamps to 0–100; 22 tests cover the edge cases.
- **Portable** — works on the stock macOS Bash 3.2 and modern Bash alike.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/lexeler/claude-code-context-bar/main/install.sh | bash
```

Then **restart Claude Code**. That's it.

The installer drops `context-bar.sh` into your Claude config dir
(`~/.claude`, or `$CLAUDE_CONFIG_DIR`) and adds a `statusLine` entry to
`settings.json`, backing up any existing file first and preserving your other
settings.

**Already have a status line?** Claude Code supports only one, so context-bar
replaces it — but it prints which one it replaced and your timestamped backup
keeps the old configuration, so you can revert any time.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `CCTX_WIDTH` | `16` | Character cells in the bar. Each cell = 2 colour sub-cells, so the default is 32 gradient steps; `24` gives 48, and so on. |

Set it in the `statusLine` command, e.g. `CCTX_WIDTH=24 ~/.claude/context-bar.sh`.

## Manual install

1. Copy `context-bar.sh` anywhere (e.g. `~/.claude/context-bar.sh`) and
   `chmod +x` it.
2. Add to `~/.claude/settings.json`:

   ```json
   {
     "statusLine": { "type": "command", "command": "~/.claude/context-bar.sh", "padding": 0 }
   }
   ```
3. Restart Claude Code.

## Safety

The installer is careful with the one thing it changes — your `settings.json`:

- It **verifies the download** (non-empty, correct shebang, valid Bash syntax)
  *before* installing, so a broken or truncated file never replaces a working one.
- The whole script is wrapped in a function invoked only at the end, so a
  half-downloaded `curl | bash` runs nothing.
- Your existing `settings.json` is **backed up with a timestamp**, written
  **atomically**, and **all your other keys are preserved** — only `statusLine`
  is added.
- If `settings.json` isn't valid JSON it's moved aside to `.broken`; if it's
  valid JSON but not an object, it's **left untouched** and you're told what to add.
- Nothing outside your Claude config dir is touched, and **no `sudo`** is used.
- Uninstall removes the `statusLine` entry **only if it's context-bar's** — a
  status line you set for something else is left alone.

All of the above is covered by the scenario tests.

## How it works

Claude Code pipes a JSON blob describing the session to the status-line command
on every refresh. `context-bar.sh` reads it with a Bash builtin, pulls
`context_window.used_percentage`, and prints a colored bar with `printf` — each
character a `▌` half-block whose foreground and background encode two adjacent
gradient colours. No subprocess is ever spawned.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/lexeler/claude-code-context-bar/main/uninstall.sh | bash
```

or just remove the `statusLine` block from `settings.json` and delete the script.

## Tests

```bash
./test.sh
```

## License

MIT — see [LICENSE](LICENSE).
