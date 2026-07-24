# Contributing to claude-code-status-bar

Thanks for helping out. This file is the contribution guide: conventions,
the pre-pull-request checks, and the terms a contribution is submitted under.
Keep changes small and consistent with `statusline.sh` — match the surrounding
shell style, comment the why and not the what, and add no dependency beyond
`bash`, `jq`, and `awk`. The project context is in [AGENTS.md](AGENTS.md).

## AI-assisted contributions

Using AI coding tools is welcome. Two rules:

- You are responsible for what you submit. Review and understand every line,
  run the checks below, and be ready to answer review questions about the
  change — the model having written it is not a defense.
- Point your tool at [AGENTS.md](AGENTS.md), the agent context file with the
  project layout, the invariants, and how to exercise the script (most agent
  tools pick it up automatically). Everything in this guide applies to
  AI-written code exactly as to hand-written code.

## Language

English only: code, comments, documentation, and commit messages.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/):
`type(scope): imperative summary`. Types: `feat`, `fix`, `refactor`, `docs`,
`test`, `chore`, `perf`.

## Rights and licensing

By submitting a contribution, you agree that it is licensed under the terms in
[LICENSE](LICENSE): inbound contributions match the outbound license. No
copyright assignment and no contributor license agreement are required.

## Developer Certificate of Origin

Every commit carries a Signed-off-by line certifying the Developer Certificate
of Origin (https://developercertificate.org): the right to submit the work
under the project license. Sign off automatically with

    git commit -s

which appends

    Signed-off-by: Your Name <your@email>

from git config user.name and user.email. A pull request whose commits lack a
sign-off is not merged. The sign-off is yours: it certifies your right to
submit the work, and an assistant does not make that certification for you.

## Before you open a pull request

- Exercise the script on the worked examples in [AGENTS.md](AGENTS.md) and the
  README, and confirm the rendering still matches.
- Constrain the width (`COLUMNS=50 bash statusline.sh`) and confirm the collapse
  ladder still drops segments in the documented order.
- Run `shellcheck statusline.sh` when it is available.
- Keep the two width invariants intact: fixed-width numeric padding, and the
  documented collapse priority. If a change touches a segment or a `CC_*`
  option, update the segment and configuration tables in the README in the same
  change.
