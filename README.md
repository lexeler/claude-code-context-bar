# context-bar

A minimalistic **status line for [Claude Code](https://claude.com/claude-code)**:
context-window usage on the left, and — optionally — your **5-hour rate-limit**
usage pinned to the right edge of the line.

```
████░░░░░░░░░░░░ 37%                          2:45 ▌▌▌▌▌░░░░░ 40%
└ context: blue→red bar + used %              └ 5-hour limit: time-to-reset · grey bar · used %
```

- **Left — context window.** A blue→red gradient bar that fills as the context
  window fills; the number is the percent **used**. One glance tells you how much
  room is left.
- **Right — 5-hour limit.** `H:MM` until the limit resets, a calm grey bar that
  **reddens as you approach the cap**, and the used percentage — right-aligned so
  it stays out of the way until you need it.

## Why

- **Two gauges, one line, tiny footprint.** Each character cell holds two colour
  sub-cells via a half-block glyph (`▌`), so a 16-char bar carries 32 steps and
  fills at half-cell precision — smooth, yet short.
- **Featherweight.** Pure Bash, no network, no daemon; the only external call is
  one tiny `date` for the reset clock (and even that is fork-free on Bash 4.2+).
  A few milliseconds per render, then it exits.
- **Accurate.** Reads `context_window.used_percentage` and
  `rate_limits.five_hour` straight from Claude Code's own payload, each scoped so
  it never grabs the wrong percentage.
- **Robust.** Tolerant of whitespace, floats, missing fields and malformed input;
  clamps to 0–100; **27 tests** cover the edge cases.
- **Portable.** Works on the stock macOS Bash 3.2 and modern Bash alike.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/lexeler/claude-code-context-bar/main/install.sh | bash
```

Context bar only (hide the 5-hour tracker):

```bash
curl -fsSL https://raw.githubusercontent.com/lexeler/claude-code-context-bar/main/install.sh | bash -s -- --no-limit
```

Then **restart Claude Code**. The installer drops `context-bar.sh` into your
Claude config dir (`~/.claude`, or `$CLAUDE_CONFIG_DIR`) and adds a `statusLine`
entry to `settings.json`, backing up any existing file first and preserving your
other settings.

> The 5-hour tracker only appears when Claude Code includes `rate_limits` in its
> payload (subscription plans). Without it, you simply get the context bar.

**Already have a status line?** Claude Code supports only one, so context-bar
replaces it — it prints which one it replaced, and your timestamped backup keeps
the old configuration so you can revert any time.

## Configuration

Set these as env vars at install time (baked into the status line command), e.g.
`... | CCTX_WIDTH=24 bash`, or edit the command in `settings.json`.

| Variable | Default | Description |
|----------|---------|-------------|
| `CCTX_LIMIT` | on | Set to `0` to hide the 5-hour rate-limit tracker (same as `--no-limit`). |
| `CCTX_WIDTH` | `16` | Context bar cells (each = 2 colour sub-cells → 32 steps at the default). |
| `CCTX_LIMIT_WIDTH` | `10` | 5-hour bar cells. |
| `CCTX_RMARGIN` | `6` | Right-edge margin (columns) so the tracker isn't truncated. Increase if the tail is cut off; decrease to sit tighter to the edge. |

## Manual install

1. Copy `context-bar.sh` anywhere (e.g. `~/.claude/context-bar.sh`) and `chmod +x` it.
2. Add to `~/.claude/settings.json`:

   ```json
   {
     "statusLine": { "type": "command", "command": "~/.claude/context-bar.sh", "padding": 0 }
   }
   ```
3. Restart Claude Code.

## How it works

Claude Code pipes a JSON blob describing the session to the status-line command
on every refresh. `context-bar.sh` reads it with a Bash builtin, pulls
`context_window.used_percentage` (and, for the right side,
`rate_limits.five_hour`'s used percentage and reset time), and prints both bars
with `printf` — each character a `▌` half-block whose foreground and background
encode two adjacent colours. The 5-hour tracker is right-aligned using the
terminal width Claude Code passes via `COLUMNS`.

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
