# Claude Code status bar

A custom terminal status line for the Claude Code CLI: model, reasoning effort,
context-window usage, 5-hour rate-limit usage, git branch, and session cost.

The status line renders on every update from the session JSON Claude Code pipes
to it on stdin:

    Opus 4.8 max · █░░░░░░  12% · 123k/1m · 5h  30% · ⎇ main ·   $4.04


## Requirements

- bash, jq, awk, git
- Claude Code 2.1 or newer

## Installation

Place the script in the Claude config directory and register it in
settings.json:

    mkdir -p ~/.claude
    curl -fsSL https://raw.githubusercontent.com/haritos90/claude-code-status-bar/main/statusline.sh \
      -o ~/.claude/statusline.sh
    chmod +x ~/.claude/statusline.sh

Add this to ~/.claude/settings.json (existing keys are preserved):

    "statusLine": { "type": "command", "command": "bash ~/.claude/statusline.sh" }

## Content

| Segment | Meaning |
|---|---|
| `Opus 4.8` | Model; the ` (1M context)` suffix is trimmed |
| `max` | Reasoning effort; omitted when absent |
| bar + `12%` | Context-window fill; green below 50, amber 50–79, red 80 and above |
| `123k/1m` | Tokens in context / context-window size |
| `5h 30%` | Rolling 5-hour rate-limit usage |
| `⎇ main` | Git branch; long names truncated (`CC_BRANCH_MAX`) |
| `$4.04` | Session cost at API rates; omitted when zero |

Numeric segments are right-padded to a fixed width, so the line does not shift
as values change digit count.

Exercise it without a live session:

    echo '{"model":{"display_name":"Opus 4.8"},"effort":{"level":"max"},"context_window":{"total_input_tokens":123000,"context_window_size":1000000,"used_percentage":12},"rate_limits":{"five_hour":{"used_percentage":30}},"workspace":{"current_dir":"."},"cost":{"total_cost_usd":4.04}}' | bash statusline.sh

## Configuration

Set these as environment variables in the `statusLine.command`, for example
`"command": "CC_CELLS=10 bash ~/.claude/statusline.sh"`:

| Option | Default | Description |
|---|---|---|
| `CC_CELLS` | `7` | Context bar width in cells |
| `CC_AMBER` / `CC_RED` | `50` / `80` | Amber and red context-fill percentage boundaries |
| `CC_BRANCH_MAX` | `18` | Max git-branch length before truncation |

`cost.total_cost_usd` is the API-rate value of the session's tokens, not a
subscription charge.

