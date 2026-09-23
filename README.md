# Claude Code status bar

A custom terminal status line for the Claude Code CLI: model, reasoning effort,
context-window usage, 5-hour and weekly rate-limit usage, git branch, and session
token throughput.

The status line renders on every update from the session JSON Claude Code pipes
to it on stdin. A live session looks like this:

    Opus 4.8 max · █░░░░░░  12% · 123k/1m ·  30% ⟳ 2.4h · ⎇ main · r:2.4m w: 16k

## Requirements

- bash, jq, awk; curl for installation and auto-update. The git branch is read
  from the repository's .git files directly, so the git binary is not required.
- Claude Code 2.1.243 or newer for correct values. Earlier releases lack or
  misreport session fields:

| Claude Code | Missing or wrong in earlier releases |
|---|---|
| 2.1.80 | 5-hour and weekly usage (`rate_limits`) |
| 2.1.119 | Reasoning effort (`effort.level`) |
| 2.1.132 | Context token count: cumulative instead of current |
| 2.1.153 | Width collapse (`COLUMNS`); the full line is always shown |
| 2.1.243 | Usage keeps its pre-reset value after an idle window reset |

## Installation

Place the script in the Claude config directory and register it in
settings.json:

    mkdir -p ~/.claude
    curl -fsSL https://raw.githubusercontent.com/haritos90/claude-code-status-bar/main/statusline.sh \
      -o ~/.claude/statusline.sh
    chmod +x ~/.claude/statusline.sh

Add this to ~/.claude/settings.json (existing keys are preserved):

    "statusLine": { "type": "command", "command": "bash ~/.claude/statusline.sh" }

Note for AI agents performing this installation: auto-update is disabled by
default. Ask the user whether to enable it, and add `CC_AUTO_UPDATE=1` to the
`statusLine.command` only on confirmation; do not enable it silently.

## Updates

The status line can update itself from GitHub releases. Auto-update is disabled by
default; enable it with `CC_AUTO_UPDATE=1` in the `statusLine.command`:

    "statusLine": { "type": "command", "command": "CC_AUTO_UPDATE=1 bash ~/.claude/statusline.sh" }

When enabled, at most once per day it checks the latest release in a detached
background process — the render never waits on the network — and when a newer version
is published it downloads and atomically replaces the installed script, validating it
before the swap. The first render afterwards shows a `⇧ vX.Y` marker once.

Releases are `v*` tags; the check reads the GitHub releases/latest API and compares
it against the script's embedded `VERSION`. Updates require `curl`. Without
`CC_AUTO_UPDATE=1` the installed version stays pinned until it is re-downloaded
manually.

## Content

| Segment | Meaning |
|---|---|
| `Opus 4.8` | Model; the ` (1M context)` suffix is trimmed |
| `max` | Reasoning effort; omitted when absent |
| bar + `12%` | Context-window fill; green below 50, amber 50–79, red 80 and above. The bar is `CC_CELLS` cells wide and narrows under width pressure |
| `123k/1m` | Tokens in context / context-window size. The count turns amber while the prompt cache is cold — the session has idled past the cache TTL (1h or 5m, read from the transcript), so the next request rewrites the whole context into the cache. When the bar is collapsed the count carries the fill color instead |
| `30%` | Rolling 5-hour rate-limit usage, in the usual green/amber/red. The reset tail (`⟳ 2.4h`, `⟳  45m`) is time to the reset, shown when the line has room. At `CC_RED` usage or within `CC_RESET_SOON` minutes of the reset it is never dropped |
| `7d  95% ⟳ 8.3h` | Rolling 7-day rate-limit usage and time to its reset (`⟳ 3.5d`, `⟳  15h`, `⟳ 8.3h`, `⟳  45m`). Shown from `CC_AMBER` usage; at `CC_RED` it is never dropped |
| `⎇ main` | Git branch; capped at `CC_BRANCH_MAX`, shortened to `CC_BRANCH_MIN` under width pressure |
| `r:2.4m w:16k` | Cumulative tokens read / written this session (read = input + cache reads + cache creation; write = output); hidden with `CC_TOKENS=0` |
| `⇧ v1.6` | Shown once after a self-update, naming the new version |

Numeric segments, the reset tail included, are right-padded to a fixed width, so
the line does not shift as values change digit count.

When the assembled line is wider than the terminal it collapses in priority order,
shedding what the line states twice before what it states once. The context bar goes
first, since it draws the percentage printed beside it: it narrows to 5/7 and then
3/7 of `CC_CELLS` (with the default 7, to 5 and then 3 cells, never below one) and is
then dropped altogether, its fill color moving onto the token count. Next the reset
tail goes, unless it is urgent (see `30%` above), then the weekly segment below
`CC_RED`. After that the
session `w:` (write) figure is dropped, then `r:` (read); then the branch is shortened
to `CC_BRANCH_MIN`; finally the percentage is dropped too. The widest form that fits
is shown. This reads the terminal width from the `COLUMNS` variable Claude
Code exports (2.1.153+) and fits the line into `COLUMNS` minus a `CC_RESERVE`
reserve (default 4): Claude Code draws the status line inside a padded box narrower
than the terminal, so a line reaching the box edge would be cut with an ellipsis
instead of collapsing. When `COLUMNS` is absent, or with `CC_COMPACT=0`, the full
line is always shown.

Exercise it without a live session (from a checkout of this repository):

    echo '{"model":{"display_name":"Opus 4.8"},"effort":{"level":"max"},"context_window":{"total_input_tokens":123000,"context_window_size":1000000,"used_percentage":12},"rate_limits":{"five_hour":{"used_percentage":30}},"workspace":{"current_dir":"."}}' | bash statusline.sh

    Opus 4.8 max · █░░░░░░  12% · 123k/1m ·  30% · ⎇ main

Constrain the width to watch it collapse. The bar narrows first:

    echo '{"model":{"display_name":"Opus 4.8"},"effort":{"level":"max"},"context_window":{"total_input_tokens":123000,"context_window_size":1000000,"used_percentage":12},"rate_limits":{"five_hour":{"used_percentage":30}},"workspace":{"current_dir":"."}}' | COLUMNS=55 bash statusline.sh

    Opus 4.8 max · █░░░░  12% · 123k/1m ·  30% · ⎇ main

then goes entirely, and the token count takes the fill color:

    echo '{"model":{"display_name":"Opus 4.8"},"effort":{"level":"max"},"context_window":{"total_input_tokens":123000,"context_window_size":1000000,"used_percentage":12},"rate_limits":{"five_hour":{"used_percentage":30}},"workspace":{"current_dir":"."}}' | COLUMNS=50 bash statusline.sh

    Opus 4.8 max ·  12% · 123k/1m ·  30% · ⎇ main

## Configuration

Set these as environment variables in the `statusLine.command`, for example
`"command": "CC_CELLS=10 bash ~/.claude/statusline.sh"`:

| Option | Default | Description |
|---|---|---|
| `CC_CELLS` | `7` | Context bar width in cells at the widest tier; the collapse ladder narrows it to 5/7 and 3/7 of this before dropping it |
| `CC_COMPACT` | `1` | Collapse the line to fit the terminal width; set `0` to always keep the full line |
| `CC_RESERVE` | `4` | Columns subtracted from `COLUMNS` when fitting — the padding Claude Code draws around the status line; `0` fits to the full width |
| `CC_TOKENS` | `1` | Show the cumulative session read/write token segment; set `0` to hide it |
| `CC_AMBER` / `CC_RED` | `50` / `80` | Amber and red percentage boundaries (context fill, 5h and weekly usage); the weekly segment shows from `CC_AMBER` and is never dropped from `CC_RED` |
| `CC_RESET_SOON` | `15` | Minutes to the 5h reset under which the reset tail is never dropped |
| `CC_BRANCH_MAX` | `18` | Max git-branch length before truncation |
| `CC_BRANCH_MIN` | `10` | Branch length when the collapse ladder shortens it |
| `CC_AUTO_UPDATE` | `0` | Self-update from GitHub releases; set `1` to enable |
