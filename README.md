# Claude Code status bar

A custom terminal status line for the Claude Code CLI: model, reasoning effort,
context-window usage, 5-hour rate-limit usage, and git branch.

The status line renders on every update from the session JSON Claude Code pipes
to it on stdin:

    Opus 4.8 max · █░░░░░░  12% · 123k/1m · 5h  30% · ⎇ main


## Requirements

- bash, jq, awk, git; curl for installation and auto-update
- Claude Code 2.1 or newer (2.1.153+ to collapse the line into narrow terminals; on
  older versions the full bar is always shown)

## Installation

Place the script in the Claude config directory and register it in
settings.json:

    mkdir -p ~/.claude
    curl -fsSL https://raw.githubusercontent.com/haritos90/claude-code-status-bar/main/statusline.sh \
      -o ~/.claude/statusline.sh
    chmod +x ~/.claude/statusline.sh

Add this to ~/.claude/settings.json (existing keys are preserved):

    "statusLine": { "type": "command", "command": "bash ~/.claude/statusline.sh" }

## Updates

The status line updates itself from GitHub releases. At most once per day it checks
the latest release in a detached background process — the render never waits on the
network — and when a newer version is published it downloads and atomically replaces
the installed script, validating it before the swap. The first render afterwards
shows a `⇧ vX.Y` marker once.

Disable it with `CC_AUTO_UPDATE=0` in the `statusLine.command`:

    "statusLine": { "type": "command", "command": "CC_AUTO_UPDATE=0 bash ~/.claude/statusline.sh" }

Releases are `v*` tags; the check reads the GitHub releases/latest API and compares
it against the script's embedded `VERSION`. Updates require `curl`.

## Content

| Segment | Meaning |
|---|---|
| `Opus 4.8` | Model; the ` (1M context)` suffix is trimmed |
| `max` | Reasoning effort; omitted when absent |
| bar + `12%` | Context-window fill; green below 50, amber 50–79, red 80 and above |
| `123k/1m` | Tokens in context / context-window size; the count takes the fill color when the bar is collapsed |
| `5h 30%` | Rolling 5-hour rate-limit usage |
| `⎇ main` | Git branch; long names truncated (`CC_BRANCH_MAX`) |
| `⇧ v1.2` | Shown once after a self-update, naming the new version |

Numeric segments are right-padded to a fixed width, so the line does not shift
as values change digit count.

When the assembled line is wider than the terminal, the context bar is dropped and
its fill color moves onto the token count; if it still does not fit, the percentage is
dropped too, leaving only the colored token count. The widest form that fits is shown.
This reads the terminal width from the `COLUMNS` variable Claude Code exports
(2.1.153+); when it is absent, or with `CC_COMPACT=0`, the full bar is always shown.

Exercise it without a live session:

    echo '{"model":{"display_name":"Opus 4.8"},"effort":{"level":"max"},"context_window":{"total_input_tokens":123000,"context_window_size":1000000,"used_percentage":12},"rate_limits":{"five_hour":{"used_percentage":30}},"workspace":{"current_dir":"."}}' | bash statusline.sh

Constrain the width to watch it collapse — the bar drops and the token count takes the
fill color:

    echo '{"model":{"display_name":"Opus 4.8"},"effort":{"level":"max"},"context_window":{"total_input_tokens":123000,"context_window_size":1000000,"used_percentage":12},"rate_limits":{"five_hour":{"used_percentage":30}},"workspace":{"current_dir":"."}}' | COLUMNS=50 bash statusline.sh

## Configuration

Set these as environment variables in the `statusLine.command`, for example
`"command": "CC_CELLS=10 bash ~/.claude/statusline.sh"`:

| Option | Default | Description |
|---|---|---|
| `CC_CELLS` | `7` | Context bar width in cells |
| `CC_COMPACT` | `1` | Collapse the bar to fit the terminal width; set `0` to always keep the full bar |
| `CC_AMBER` / `CC_RED` | `50` / `80` | Amber and red context-fill percentage boundaries |
| `CC_BRANCH_MAX` | `18` | Max git-branch length before truncation |
| `CC_AUTO_UPDATE` | `1` | Self-update from GitHub releases; set `0` to disable |

