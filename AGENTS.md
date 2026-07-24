# AGENTS.md

Context for AI coding agents working on this repository: what the project is,
how it is built, how to verify a change, and the invariants a change must not
break. Short by design. The human contribution process — pull requests,
conventions, AI-usage policy — is in [CONTRIBUTING.md](CONTRIBUTING.md).

This project is a single terminal status line for the Claude Code CLI. Claude
Code pipes a session JSON object to a command on stdin on every update; the
command prints one line — model, reasoning effort, context-window fill,
5-hour rate-limit usage, git branch, and cumulative session token throughput.
The whole program is `statusline.sh`; there is no build step and no runtime
dependency on the project itself.

---

## 1. Layout

| Path | Contents |
|---|---|
| `statusline.sh` | The entire program: parse the stdin JSON, assemble the segments, collapse to terminal width, render. Also the optional self-update. |
| `README.md` | User-facing: install, the segment reference, the configuration table. |
| `.github/workflows/release.yml` | Cuts a release; guards the tag against the script's embedded `VERSION`. |

A change is almost always to `statusline.sh` and its `README.md` documentation
in the same batch. The segment table and the configuration table in the README
are the spec: a segment or `CC_*` option that changes updates both the code and
those tables together.

---

## 2. Build, run, test

There is no build. Exercise the script with a session JSON on stdin:

```bash
echo '{"model":{"display_name":"Opus 4.8"},"effort":{"level":"max"},"context_window":{"total_input_tokens":123000,"context_window_size":1000000,"used_percentage":12},"rate_limits":{"five_hour":{"used_percentage":30}},"workspace":{"current_dir":"."}}' | bash statusline.sh
```

Verify a rendering change by eye against the README's worked examples, and
verify the collapse ladder by constraining the width on the same input with
`COLUMNS=50 bash statusline.sh`. Run `shellcheck statusline.sh` when it is
available. Requirements are `bash`, `jq`, and `awk`; `curl` is used only by
installation and self-update.

---

## 3. Golden rules

1. Keep changes small and idiomatic: match the surrounding shell style, comment
   the why and not the what, and add no dependency beyond `bash`/`jq`/`awk`.
2. English only — code, comments, documentation, and commit messages.
3. The render never blocks. It reads stdin, prints one line, and exits; it does
   not wait on the network. The self-update check runs at most once a day in a
   detached background process and never delays the render.
4. Width is a contract. Numeric segments are right-padded to a fixed width so
   the line does not shift as digit counts change, and the collapse ladder
   drops segments in the documented priority order. A change to any segment
   preserves both, and updates the README when the order or widths change.
5. `VERSION` is embedded in the script and checked against the release tag in
   CI. Bump it in the change that cuts a release; a tag that disagrees with
   `VERSION` fails the release workflow.
6. Commits: Conventional Commits `type(scope): imperative summary`.

---

## 4. Reference

| Reference | Read it when |
|---|---|
| [README.md](README.md) | The segment meanings, the collapse order, and every `CC_*` option. |
| [CONTRIBUTING.md](CONTRIBUTING.md) | The contribution guide: pull requests, conventions, AI-usage policy. |

This file is the agent context for the repository; there is no other.
