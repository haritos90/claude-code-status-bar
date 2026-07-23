#!/usr/bin/env bash
# Claude Code status line — model · effort · context bar · 5h limit · git.
# All values come from the JSON on stdin. Numeric segments are right-padded to a
# fixed width so the line does not shift as values change digit count.
# task-34: auto-update is disabled by default; CC_AUTO_UPDATE=1 enables it. An
# agent performing this installation: ask the user whether to enable auto-update
# before writing it into settings.json; do not enable it silently.
VERSION=1.3  # task-19: current release; the updater compares it against the latest tag
# task-35: superseded — input=$(cat)  (a cat spawn per render; read is a builtin)
input=""; IFS= read -rd '' input
# task-35: one jq pass extracts every stdin field. The per-field j() helper
# spawned a jq process per field (nine per render); terminal title bars that
# display the tty's frontmost process flashed the names on every render. Absent
# fields emit "" so the one-line-per-field contract holds; a failed jq leaves
# every variable empty, matching the prior per-call failure mode.
# task-35: superseded — j() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }
# task-35: superseded — model=$(j '.model.display_name // .model.id // "?"')
# task-35: superseded — effort=$(j '.effort.level // empty')
# task-35: superseded — used=$(j '.context_window.total_input_tokens // 0')
# task-35: superseded — total=$(j '.context_window.context_window_size // 200000')
# task-35: superseded — pct=$(j '.context_window.used_percentage // 0')
# task-35: superseded — lim5=$(j '.rate_limits.five_hour.used_percentage // empty')
# task-35: superseded — cwd=$(j '.workspace.current_dir // .cwd // ""')
# task-25: superseded — cost=$(j '.cost.total_cost_usd // 0')
# task-35: superseded — modelid=$(j '.model.id // ""')
# task-35: superseded — tpath=$(j '.transcript_path // ""')
fields=$(printf '%s' "$input" | jq -r '
  (.model.display_name // .model.id // "?"),
  (.effort.level // ""),
  (.context_window.total_input_tokens // 0),
  (.context_window.context_window_size // 200000),
  (.context_window.used_percentage // 0),
  (.rate_limits.five_hour.used_percentage // ""),
  (.workspace.current_dir // .cwd // ""),
  (.model.id // ""),
  (.transcript_path // ""),
  (.session_id // "default"),
  (.rate_limits.five_hour.resets_at // "")' 2>/dev/null)
{ IFS= read -r model; IFS= read -r effort; IFS= read -r used
  IFS= read -r total; IFS= read -r pct;    IFS= read -r lim5
  IFS= read -r cwd;   IFS= read -r modelid; IFS= read -r tpath
  IFS= read -r sid;   IFS= read -r reset5; } <<< "$fields"
model=${model% (1M context)}
pct=${pct%.*}
lim5=${lim5%.*}

R=$'\033[0m'; DIM=$'\033[38;2;120;120;120m'; BOLD=$'\033[1m'
col() { # pct -> ANSI color; task-17: amber/red boundaries via CC_AMBER/CC_RED
  if   [ "${1:-0}" -ge "${CC_RED:-80}" ]; then printf '\033[38;2;225;95;75m'
  elif [ "${1:-0}" -ge "${CC_AMBER:-50}" ]; then printf '\033[38;2;240;190;70m'
  else printf '\033[38;2;120;190;120m'
  fi
}
pad() { printf "%${1}s" "$2"; }   # right-align $2 to width $1 (fixed-width segments)
C=$(col "$pct")
sep=" ${DIM}·${R} "

# --- context bar ---
# task-9: superseded — CELLS=10
# task-14: superseded — CELLS=8
# task-17: CC_CELLS overrides the width so an auto-update does not clobber a chosen
# value; the default reproduces the prior fixed CELLS=7.
CELLS=${CC_CELLS:-7}
filled=$(( (${pct:-0} * CELLS + 50) / 100 ))
[ "$filled" -gt "$CELLS" ] && filled=$CELLS
[ "$filled" -lt 0 ] && filled=0
fstr=""; estr=""; i=0
while [ "$i" -lt "$filled" ]; do fstr="${fstr}█"; i=$((i+1)); done
i=0; while [ "$i" -lt $((CELLS - filled)) ]; do estr="${estr}░"; i=$((i+1)); done
bar="${C}${fstr}${DIM}${estr}${R}"

# task-35: integer arithmetic replaces the two awk spawns per call. The task-11
# radix concern is gone with awk: the tenth digit is computed and printed as an
# integer, so no locale can reintroduce a comma. Rounding is decimal-correct;
# awk's %.1f differed only where the binary double of an exact half rounds down.
# task-35: superseded — if [ "$n" -ge 1000000 ]; then LC_ALL=C awk -v n="$n" 'BEGIN{v=n/1000000; if(v==int(v))printf"%dm",v;else printf"%.1fm",v}'
# task-35: superseded — elif [ "$n" -ge 1000 ]; then awk -v n="$n" 'BEGIN{printf"%dk",int(n/1000+0.5)}'
fmt() {
  local n=$1 t
  if [ "$n" -ge 1000000 ]; then
    if [ $(( n % 1000000 )) -eq 0 ]; then printf '%dm' $(( n / 1000000 ))
    else t=$(( (n + 50000) / 100000 )); printf '%d.%dm' $(( t / 10 )) $(( t % 10 ))
    fi
  elif [ "$n" -ge 1000 ]; then printf '%dk' $(( (n + 500) / 1000 ))
  else printf '%d' "$n"
  fi
}

# --- self-update (task-20, decision-1; opt-in per task-33, decision-3) ------
# Disabled unless CC_AUTO_UPDATE=1. When enabled, at most once per day a detached
# background process checks the latest GitHub release and, when it is newer than
# VERSION, atomically replaces this script with the tagged statusline.sh. It never
# blocks the render; all failures are silent. State lives under CACHE_DIR. The
# trigger at the end of the script decides whether to spawn self_update.
CC_REPO="haritos90/claude-code-status-bar"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-code-status-bar"

# task-38: current epoch seconds, spawn-free where printf %(fmt)T exists (bash
# 4.2+); /bin/bash 3.2 falls back to one date spawn. Used by the 5h reset tail
# and the self-update trigger.
now=$(printf '%(%s)T' -1 2>/dev/null)
case "$now" in ''|*[!0-9]*) now=$(date +%s) ;; esac

vgt() { # exit 0 iff $1 is strictly newer than $2 (dotted numeric versions)
  awk -v a="$1" -v b="$2" 'BEGIN{
    na=split(a,A,"."); nb=split(b,B,".");
    n=(na>nb?na:nb);
    for(i=1;i<=n;i++){x=(i<=na?A[i]+0:0);y=(i<=nb?B[i]+0:0);
      if(x>y)exit 0; if(x<y)exit 1}
    exit 1}'
}

self_update() { # detached background; silent; never surfaces failures
  local tag latest self dir tmp
  tag=$(curl -fsSL --max-time 10 "https://api.github.com/repos/$CC_REPO/releases/latest" 2>/dev/null \
        | jq -r '.tag_name // empty' 2>/dev/null)
  [ -n "$tag" ] || return 0
  latest=${tag#v}
  vgt "$latest" "$VERSION" || return 0             # only ever move forward
  self="${SELF:-$0}"; [ -f "$self" ] || return 0   # SELF overridable for tests
  dir=$(dirname "$self")
  tmp=$(mktemp "$dir/.statusline.XXXXXX" 2>/dev/null) || return 0
  if curl -fsSL --max-time 20 "https://raw.githubusercontent.com/$CC_REPO/$tag/statusline.sh" -o "$tmp" 2>/dev/null \
     && [ -s "$tmp" ] && bash -n "$tmp" 2>/dev/null; then
    chmod +x "$tmp" 2>/dev/null
    mv -f "$tmp" "$self" 2>/dev/null && printf '%s' "$latest" > "$CACHE_DIR/applied-version" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
  fi
}

# fallback marker — Claude Code records an automatic model switch as an assistant
# "fallback" content block {from,to} (e.g. the selected model is unavailable). The
# stdin .model reflects the effective model, so it silently disagrees with the
# startup banner. When the active model equals the newest fallback target, flag it
# with an amber arrow; a later manual switch away makes .model.id stop matching and
# the marker drops.
# task-35: the per-render tail+jq scan moved into the memoized transcript pass
# below; the newest fallback target rides in the same cache file as the token
# totals and the mark is recomputed from it on every render.
# task-35: superseded — fbto=$(tail -n 4000 "$tpath" 2>/dev/null \
# task-35: superseded —       | jq -r 'select(.type=="assistant") | .message.content[]?
# task-35: superseded —                | select(.type=="fallback") | .to.model' 2>/dev/null | tail -1)
# task-35: superseded — [ "$fbto" = "$modelid" ] && fbmark=" $(col 50)⤵${R}"

# task-27 (decision-2): superseded — the activity dot is removed. Its signals
# (cost.total_api_duration_ms and the transcript mtime) advance only at message and
# tool boundaries, and the statusLine renders only at message completion plus the
# refreshInterval timer with no real-time busy field, so across a long generation span
# the dot decayed to green while the model was still working. A reliable indicator
# needs out-of-band lifecycle hooks (see decision-2). Kept commented for a restore.
# dot=""
# if [ "${CC_DOT:-0}" = "1" ]; then
#   sid=$(j '.session_id // "default"')
#   api=$(j '.cost.total_api_duration_ms // 0'); case "$api" in ''|*[!0-9]*) api=0 ;; esac
#   amt=0; [ -n "$tpath" ] && amt=$(stat -c %Y "$tpath" 2>/dev/null || stat -f %m "$tpath" 2>/dev/null || printf 0)
#   case "$amt" in ''|*[!0-9]*) amt=0 ;; esac
#   win=${CC_BUSY_WINDOW:-10}; anow=$(date +%s); af="$CACHE_DIR/activity-$sid"
#   pa=$api pm=$amt la=$((anow - win - 1))                 # first render defaults to idle
#   [ -f "$af" ] && IFS=' ' read -r pa pm la < "$af" 2>/dev/null
#   case "$pa" in ''|*[!0-9]*) pa=$api ;; esac
#   case "$pm" in ''|*[!0-9]*) pm=$amt ;; esac
#   case "$la" in ''|*[!0-9]*) la=$anow ;; esac
#   { [ "$api" -gt "$pa" ] || [ "$amt" -gt "$pm" ]; } && la=$anow   # advanced since last render -> active
#   mkdir -p "$CACHE_DIR" 2>/dev/null && printf '%s %s %s\n' "$api" "$amt" "$la" > "$af" 2>/dev/null
#   if [ "$((anow - la))" -le "$win" ]; then
#     lvl=$(( anow % 6 )); [ "$lvl" -gt 3 ] && lvl=$(( 6 - lvl ))   # 0,1,2,3,2,1 triangle over 6s
#     dot="$(printf '\033[38;2;235;%s;55m' "$(( 120 + lvl * 18 ))")●${R} "   # breathing orange = active
#   else
#     dot="$(printf '\033[38;2;110;150;110m')●${R} "                         # calm dim green = idle
#   fi
# fi

# --- transcript pass: token throughput (task-32) + fallback target ----------
# Cumulative read/write across the transcript: read = Σ(input + cache_read +
# cache_creation), write = Σ output. Shown by default; CC_TOKENS=0 opts out.
# task-35: one memoized pass serves both features. The totals and the newest
# fallback target are keyed on the transcript's size+mtime in
# CACHE_DIR/tokens-<sid> (fields: sz mt rd wr fbto), so idle re-renders spawn no
# jq and one stat; the full rescan runs only when the transcript changed (once
# per turn). jq streams with -n 'reduce(inputs)' (no slurp). Compaction that
# prunes the transcript lowers the total. Pre-task-35 cache files carry four
# fields; fbto reads empty and heals on the next transcript change. tok0/tok1
# are the width tiers (full / read-only); tok2 is empty (segment dropped).
# Hidden until a turn records usage.
tok0=""; tok1=""; tok2=""; fbmark=""
if [ -n "$tpath" ] && [ -f "$tpath" ]; then
  # task-35: superseded — sid=$(j '.session_id // "default"')  (single jq pass, top)
  # task-35: superseded — sz=$(stat -c %s "$tpath" 2>/dev/null || stat -f %z "$tpath" 2>/dev/null || printf 0)
  # task-35: superseded — mt=$(stat -c %Y "$tpath" 2>/dev/null || stat -f %m "$tpath" 2>/dev/null || printf 0)
  case "$OSTYPE" in                      # one stat; the GNU->BSD retry chain spawned four
    darwin*|*bsd*) szmt=$(stat -f '%z %m' "$tpath" 2>/dev/null) ;;
    *)             szmt=$(stat -c '%s %Y' "$tpath" 2>/dev/null) ;;
  esac
  [ -n "$szmt" ] || szmt="0 0"
  sz=${szmt% *}; mt=${szmt#* }
  # task-43: the pass also carries the newest cache TTL (field order: sz mt rd wr
  # ttl fbto — ttl is always numeric and sits before the possibly-empty fallback
  # target so a blank target cannot shift fields; 0 = unknown). Pre-task-43 files
  # put the target in the ttl slot; the numeric guard discards it and both fields
  # heal on the next transcript change.
  # task-43: superseded — [ -f "$tf" ] && IFS=' ' read -r psz pmt rd wr fbto < "$tf" 2>/dev/null
  tf="$CACHE_DIR/tokens-$sid"; rd=0; wr=0; ttl=0; psz=""; pmt=""; fbto=""
  [ -f "$tf" ] && IFS=' ' read -r psz pmt rd wr ttl fbto < "$tf" 2>/dev/null
  case "$rd" in ''|*[!0-9]*) rd=0 ;; esac; case "$wr" in ''|*[!0-9]*) wr=0 ;; esac
  case "$ttl" in ''|*[!0-9]*) ttl=0 ;; esac
  if [ "$psz" != "$sz" ] || [ "$pmt" != "$mt" ]; then         # rescan only on change
    IFS=$'\t' read -r rd wr ttl fbto < <(jq -n -r '
      reduce (inputs | select(.type=="assistant")) as $a
        ({r:0, w:0, t:0, f:""};
           ($a.message.usage? // {}) as $u
         | .r += (($u.input_tokens//0)+($u.cache_read_input_tokens//0)+($u.cache_creation_input_tokens//0))
         | .w += ($u.output_tokens//0)
         | .t = (if ($u.cache_creation_input_tokens // 0) > 0
                 then (if ($u.cache_creation.ephemeral_1h_input_tokens // 0) > 0 then 3600
                       elif ($u.cache_creation.ephemeral_5m_input_tokens // 0) > 0 then 300
                       else .t end)
                 else .t end)
         | .f = (([$a.message.content[]? | select(.type=="fallback") | .to.model] | last) // .f))
      | "\(.r)\t\(.w)\t\(.t)\t\(.f)"' "$tpath" 2>/dev/null)
    case "$rd" in ''|*[!0-9]*) rd=0 ;; esac; case "$wr" in ''|*[!0-9]*) wr=0 ;; esac
    case "$ttl" in ''|*[!0-9]*) ttl=0 ;; esac
    # task-43: superseded — printf '%s %s %s %s %s\n' "$sz" "$mt" "$rd" "$wr" "$fbto" > "$tf"
    mkdir -p "$CACHE_DIR" 2>/dev/null && printf '%s %s %s %s %s %s\n' "$sz" "$mt" "$rd" "$wr" "$ttl" "$fbto" > "$tf" 2>/dev/null
  fi
  [ -n "$fbto" ] && [ "$fbto" = "$modelid" ] && fbmark=" $(col 50)⤵${R}"
  if [ "${CC_TOKENS:-1}" != "0" ] && { [ "$rd" -gt 0 ] || [ "$wr" -gt 0 ]; }; then
    tok0="${sep}${DIM}r:${R}$(pad 4 "$(fmt "$rd")") ${DIM}w:${R}$(pad 4 "$(fmt "$wr")")"
    tok1="${sep}${DIM}r:${R}$(pad 4 "$(fmt "$rd")")"
  fi
fi

# --- assemble (fixed widths: pct 4, tokens 4, r/w 4, 5h 4) ---
# task-27 (decision-2): superseded — head="${dot}${BOLD}${model}${R}${fbmark}"
head="${BOLD}${model}${R}${fbmark}"
[ -n "$effort" ] && head="${head} ${DIM}${effort}${R}"

# task-26: three width tiers for the context segment (each carries its leading sep).
# ctx0 (full) is the bar + colored pct + dim tokens, as before. Under width pressure
# the bar is dropped (ctx1: colored pct + colored token count), then the pct too
# (ctx2: colored token count only). The used figure takes the fill color the bar
# otherwise carried; the denominator stays dim. The widest tier that fits is chosen
# after the whole line is assembled (see the COLUMNS check below).
# task-43: while the prompt cache is cold — the session idled past the cache TTL
# from the transcript pass (0 = unknown, defaults to 3600 s) — the used count
# renders amber in every tier: those tokens will be rewritten into the cache by
# the next request. Width and characters are unchanged; only the color shifts.
UC=$DIM; UC1=$C
if [ "${mt:-0}" -gt 0 ] 2>/dev/null; then
  cttl=$ttl; [ "$cttl" -gt 0 ] 2>/dev/null || cttl=3600
  if [ $(( now - mt )) -gt "$cttl" ]; then
    UC=$'\033[38;2;240;190;70m'; UC1=$UC
  fi
fi
# task-43: superseded — ctx0="${sep}${bar} ${C}$(pad 4 "${pct}%")${R}${sep}${DIM}$(pad 4 "$(fmt "$used")")/$(fmt "$total")${R}"
# task-43: superseded — ctx1="${sep}${C}$(pad 4 "${pct}%")${R}${sep}${C}$(pad 4 "$(fmt "$used")")${R}${DIM}/$(fmt "$total")${R}"
# task-43: superseded — ctx2="${sep}${C}$(pad 4 "$(fmt "$used")")${R}${DIM}/$(fmt "$total")${R}"
ctx0="${sep}${bar} ${C}$(pad 4 "${pct}%")${R}${sep}${UC}$(pad 4 "$(fmt "$used")")${R}${DIM}/$(fmt "$total")${R}"
ctx1="${sep}${C}$(pad 4 "${pct}%")${R}${sep}${UC1}$(pad 4 "$(fmt "$used")")${R}${DIM}/$(fmt "$total")${R}"
ctx2="${sep}${UC1}$(pad 4 "$(fmt "$used")")${R}${DIM}/$(fmt "$total")${R}"

# rest — everything after the context segment; independent of the chosen tier.
rest=""
# 5-hour rate-limit usage — task-38: bare colored percent, the dim "5h" label is
# dropped. A reset tail (⟳2.4h / ⟳45m, in the percent's color) appears only when
# the figure is actionable: usage at or above CC_RED, or the reset within
# CC_RESET_SOON minutes (default 15). resets_at is epoch seconds; a missing or
# non-numeric value, or a reset not in the future, yields no tail. Remaining time
# formats as tenth-hours at or above 90 minutes, whole minutes below.
# task-38: superseded — rest="${rest}${sep}${DIM}5h ${R}${LC}$(pad 4 "${lim5}%")${R}"
if [ -n "$lim5" ]; then
  LC=$(col "$lim5")
  seg5="${LC}$(pad 4 "${lim5}%")${R}"
  case "$reset5" in *[!0-9]*) reset5="" ;; esac
  if [ -n "$reset5" ] && [ "$reset5" -gt "$now" ]; then
    rem=$(( reset5 - now ))
    if [ "$lim5" -ge "${CC_RED:-80}" ] || [ "$rem" -le $(( ${CC_RESET_SOON:-15} * 60 )) ]; then
      if [ "$rem" -ge 5400 ]; then
        t=$(( (rem + 180) / 360 ))
        seg5="${seg5} ${LC}⟳$(( t / 10 )).$(( t % 10 ))h${R}"
      else
        seg5="${seg5} ${LC}⟳$(( (rem + 30) / 60 ))m${R}"
      fi
    fi
  fi
  rest="${rest}${sep}${seg5}"
fi

# git branch — task-35: parsed from the repository's HEAD file; spawning git put
# its name into terminal title bars on every render. Walk up from cwd to .git,
# follow a "gitdir:" pointer file (worktree, submodule), then read HEAD: a
# "ref: refs/heads/..." line is the branch — present even on an unborn branch,
# which symbolic-ref also showed — and a bare hash is a detached HEAD, shown as
# its first seven digits.
# task-35: superseded — br=$(git -C "$cwd" symbolic-ref --quiet --short HEAD 2>/dev/null)
# task-35: superseded — sha=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
# task-35: superseded — [ -n "$sha" ] && br="(${sha})"
br0=""; br1=""
if [ -n "$cwd" ]; then
  br=""; gd=""; d=$cwd
  while :; do
    [ -e "$d/.git" ] && { gd="$d/.git"; break; }
    [ "$d" = "/" ] && break
    case "$d" in */*) d=${d%/*}; [ -n "$d" ] || d="/" ;; *) break ;; esac
  done
  if [ -n "$gd" ] && [ -f "$gd" ]; then                 # worktree/submodule pointer
    gl=""; IFS= read -r gl < "$gd" 2>/dev/null
    gl=${gl#gitdir: }
    case "$gl" in /*) gd=$gl ;; *) gd="$d/$gl" ;; esac
  fi
  if [ -n "$gd" ] && [ -f "$gd/HEAD" ]; then
    hd=""; IFS= read -r hd < "$gd/HEAD" 2>/dev/null
    case "$hd" in
      "ref: refs/heads/"*) br=${hd#ref: refs/heads/} ;;
      "ref: "*)            br=${hd#ref: } ;;           # symbolic ref outside heads
      ?*)                  br="(${hd:0:7})" ;;         # detached
    esac
  fi
  # task-39: two width tiers. br0 caps at CC_BRANCH_MAX as before; br1 caps at
  # CC_BRANCH_MIN and is chosen by the collapse ladder after the token tiers are
  # exhausted, before the context tiers collapse. Both carry their leading sep.
  # task-39: superseded — [ "${#br}" -gt "$BRMAX" ] && br="${br:0:$((BRMAX-1))}…"
  # task-39: superseded — rest="${rest}${sep}${DIM}⎇ ${br}${R}"
  if [ -n "$br" ]; then
    BRMAX=${CC_BRANCH_MAX:-18}
    BRMIN=${CC_BRANCH_MIN:-10}
    b=$br
    [ "${#b}" -gt "$BRMAX" ] && b="${b:0:$((BRMAX-1))}…"
    br0="${sep}${DIM}⎇ ${b}${R}"
    b=$br
    [ "${#b}" -gt "$BRMIN" ] && b="${b:0:$((BRMIN-1))}…"
    br1="${sep}${DIM}⎇ ${b}${R}"
  fi
fi

# task-25: superseded — the cost segment (the API-rate value of the session's tokens,
# not a subscription charge) is removed to save fixed width. Kept commented for a
# possible restore.
# cost — task-11: LC_ALL=C so the dotted JSON value is parsed and formatted with a
# period. A comma-locale printf fails on '1.23' with 'invalid number', and the awk
# guard would misparse a sub-dollar cost to 0 and hide the segment.
# if LC_ALL=C awk -v c="$cost" 'BEGIN{exit !(c+0 > 0.0001)}'; then
#   out="${out}${sep}${DIM}$(pad 7 "$(LC_ALL=C printf '$%.2f' "$cost")")${R}"
# fi

# task-16: superseded — cache-warmth (⧗) segment removed to save status-line width.
# Analysis shows Claude Code sessions cache with a 1h TTL essentially always, so a
# constantly-shown countdown adds little actionable value. The block is kept
# commented for a possible restore; CC_TTL no longer affects the output.
# if [ -n "$tpath" ] && [ -f "$tpath" ]; then
#   mt=$(stat -c %Y "$tpath" 2>/dev/null || stat -f %m "$tpath" 2>/dev/null)
#   case "$mt" in ''|*[!0-9]*) mt="" ;; esac
#   ttl=$(tail -n 2000 "$tpath" 2>/dev/null | tail -n +2 \
#         | jq -c 'select(.type=="assistant" and ((.message.usage.cache_creation_input_tokens // 0) > 0))
#                  | .message.usage.cache_creation
#                  | if (.ephemeral_1h_input_tokens // 0) > 0 then 3600
#                    elif (.ephemeral_5m_input_tokens // 0) > 0 then 300
#                    else empty end' 2>/dev/null | tail -1)
#   # task-8: superseded — [ -n "$ttl" ] || ttl=${CC_TTL:-300}
#   [ -n "$ttl" ] || ttl=${CC_TTL:-3600}
#   if [ -n "$mt" ]; then
#     idle=$(( $(date +%s) - mt ))
#     if [ "$idle" -lt "$ttl" ]; then
#       out="${out}${sep}$(col 0)⧗ $(pad 3 "$(( (ttl - idle + 59) / 60 ))m")${R}"
#     else
#       # task-8: superseded — out="${out}${sep}${DIM}⧗ $(pad 3 "∞")${R}"
#       out="${out}${sep}${DIM}⧗ $(pad 3 "—")${R}"
#     fi
#   fi
# fi

# task-21: announce a just-applied self-update once. task-20's background writes the
# new version to CACHE_DIR/applied-version after an atomic replace; show a ⇧ vX.Y
# marker on the next render and record it in announced-version so it shows only once.
# Reads state from the previous run; no network, outside the fixed-width segments.
# task-37: the marker gets its own tail variable so the token segment can render
# after the branch; the marker stays the last element of the line.
tailseg=""
if [ -f "$CACHE_DIR/applied-version" ]; then
  # task-35: superseded — av=$(cat "$CACHE_DIR/applied-version" 2>/dev/null)
  # task-35: superseded — ann=$(cat "$CACHE_DIR/announced-version" 2>/dev/null)
  av=""; ann=""
  IFS= read -r av < "$CACHE_DIR/applied-version" 2>/dev/null
  [ -f "$CACHE_DIR/announced-version" ] && IFS= read -r ann < "$CACHE_DIR/announced-version" 2>/dev/null
  if [ -n "$av" ] && [ "$av" != "$ann" ]; then
    # task-37: superseded — rest="${rest}${sep}$(col 0)⇧ v${av}${R}"
    tailseg="${sep}$(col 0)⇧ v${av}${R}"
    printf '%s' "$av" > "$CACHE_DIR/announced-version" 2>/dev/null
  fi
fi

# task-26: choose the widest context+tokens combination whose whole line fits $COLUMNS
# (Claude Code exports it, >= 2.1.153). cols=0 (unset, older Claude Code) or CC_COMPACT=0
# keeps the full bar, matching the prior output. Visible width strips ANSI SGR and UTF-8
# continuation bytes so each multi-byte cell (█ ░ · ⎇) counts as one column, and is
# measured against the fully assembled line including tokens, 5h, branch, and markers.
# task-32: the ladder now also collapses the token-throughput segment (tok0->tok1->tok2)
# ahead of the context bar; see the pair list below.
cols=${COLUMNS:-0}
ctx="$ctx0"; tok="$tok0"; brseg="$br0"
if [ "${CC_COMPACT:-1}" != "0" ] && [ "$cols" -gt 0 ]; then
  # task-32: superseded — the collapse iterated context tiers only:
  #   for cand in "$ctx0" "$ctx1" "$ctx2"; do ctx="$cand"; measure "${head}${ctx}${rest}"; done
  # task-39: the walk now covers (ctx,tok,branch) trios: drop write, then read,
  # then shorten the branch to CC_BRANCH_MIN, then the bar, then the pct. With
  # CC_TOKENS=0 the tok tiers are empty and the walk degenerates accordingly.
  # Indirect ${!name} expands the tier variables named in each trio.
  # task-39: superseded — for pair in "ctx0 tok0" "ctx0 tok1" "ctx0 tok2" "ctx1 tok2" "ctx2 tok2"; do
  # task-39: superseded —   cn=${pair% *}; tn=${pair#* }; ctx=${!cn}; tok=${!tn}
  for trio in "ctx0 tok0 br0" "ctx0 tok1 br0" "ctx0 tok2 br0" "ctx0 tok2 br1" "ctx1 tok2 br1" "ctx2 tok2 br1"; do
    read -r cn tn bn <<< "$trio"
    ctx=${!cn}; tok=${!tn}; brseg=${!bn}
    # task-37: superseded — vis=$(printf '%s' "${head}${ctx}${tok}${rest}" | LC_ALL=C awk '{s=$0; gsub(/\033\[[0-9;]*m/,"",s); gsub(/[\200-\277]/,"",s); print length(s)}')
    vis=$(printf '%s' "${head}${ctx}${rest}${brseg}${tok}${tailseg}" | LC_ALL=C awk '{s=$0; gsub(/\033\[[0-9;]*m/,"",s); gsub(/[\200-\277]/,"",s); print length(s)}')
    [ "$vis" -le "$cols" ] && break
  done
fi
# task-37: the token tiers render after rest (5h) and the branch instead of
# between the context segment and rest; the collapse ladder still drops them first.
# task-37: superseded — out="${head}${ctx}${tok}${rest}"
# task-39: superseded — out="${head}${ctx}${rest}${tok}${tailseg}"
out="${head}${ctx}${rest}${brseg}${tok}${tailseg}"

printf '%s' "$out"

# task-20: spawn the once-a-day self-update, fully detached so it never delays this
# render (the network runs in the background; the foreground work here is only a
# stat and a touch). The stamp is written now so a failed or slow check still waits
# a day before retrying. Guarded by CC_AUTO_UPDATE (opt-in, decision-3) and curl's
# presence.
# task-35: RANDOM samples the age gate at ~1/20 of renders so its date+stat pair
# does not spawn on every render; the daily stamp still bounds real checks to one
# per day, and the sampling only delays the day rollover by a few renders.
# task-33: superseded — if [ "${CC_AUTO_UPDATE:-1}" != "0" ] && command -v curl >/dev/null 2>&1; then
# task-35: superseded — if [ "${CC_AUTO_UPDATE:-0}" = "1" ] && command -v curl >/dev/null 2>&1; then
if [ "${CC_AUTO_UPDATE:-0}" = "1" ] && [ $(( RANDOM % 20 )) -eq 0 ] && command -v curl >/dev/null 2>&1; then
  # task-38: superseded — stamp="$CACHE_DIR/last-check"; now=$(date +%s); last=0
  stamp="$CACHE_DIR/last-check"; last=0    # now comes from the top-of-script clock
  # task-35: superseded — last=$(stat -c %Y "$stamp" 2>/dev/null || stat -f %m "$stamp" 2>/dev/null || printf 0)
  if [ -f "$stamp" ]; then
    case "$OSTYPE" in
      darwin*|*bsd*) last=$(stat -f %m "$stamp" 2>/dev/null) ;;
      *)             last=$(stat -c %Y "$stamp" 2>/dev/null) ;;
    esac
  fi
  case "$last" in ''|*[!0-9]*) last=0 ;; esac
  if [ "$(( now - last ))" -ge 86400 ]; then
    mkdir -p "$CACHE_DIR" 2>/dev/null && : > "$stamp" 2>/dev/null
    ( self_update & ) </dev/null >/dev/null 2>&1
  fi
fi
