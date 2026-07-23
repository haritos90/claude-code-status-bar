#!/usr/bin/env bash
# Claude Code status line — model · effort · context bar · 5h limit · git.
# All values come from the JSON on stdin. Numeric segments are right-padded to a
# fixed width so the line does not shift as values change digit count.
VERSION=1.3  # task-19: current release; the updater compares it against the latest tag
input=$(cat)
j() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }

model=$(j '.model.display_name // .model.id // "?"'); model=${model% (1M context)}
effort=$(j '.effort.level // empty')
used=$(j '.context_window.total_input_tokens // 0')
total=$(j '.context_window.context_window_size // 200000')
pct=$(j '.context_window.used_percentage // 0'); pct=${pct%.*}
lim5=$(j '.rate_limits.five_hour.used_percentage // empty'); lim5=${lim5%.*}
cwd=$(j '.workspace.current_dir // .cwd // ""')
# task-25: superseded — cost=$(j '.cost.total_cost_usd // 0')
modelid=$(j '.model.id // ""')
tpath=$(j '.transcript_path // ""')

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

# task-11: LC_ALL=C pins the decimal radix to a period on the %.1fm branch; under
# a comma locale awk would emit '1,2m'. The token count is a dot-formatted integer
# and the output is ASCII, so only the numeric radix is forced (LC_CTYPE untouched).
fmt() {
  local n=$1
  if   [ "$n" -ge 1000000 ]; then LC_ALL=C awk -v n="$n" 'BEGIN{v=n/1000000; if(v==int(v))printf"%dm",v;else printf"%.1fm",v}'
  elif [ "$n" -ge 1000 ];    then awk -v n="$n" 'BEGIN{printf"%dk",int(n/1000+0.5)}'
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
fbmark=""
if [ -n "$tpath" ] && [ -f "$tpath" ] && [ -n "$modelid" ]; then
  fbto=$(tail -n 4000 "$tpath" 2>/dev/null \
        | jq -r 'select(.type=="assistant") | .message.content[]?
                 | select(.type=="fallback") | .to.model' 2>/dev/null | tail -1)
  [ "$fbto" = "$modelid" ] && fbmark=" $(col 50)⤵${R}"
fi

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

# --- session token throughput (task-32) -------------------------------------
# Cumulative read/write across the transcript: read = Σ(input + cache_read +
# cache_creation), write = Σ output. Shown by default after the context segment;
# CC_TOKENS=0 opts out. Totals are memoized on the transcript's size+mtime in
# CACHE_DIR/tokens-<sid>, so idle re-renders do no jq work; a full rescan runs only when
# the transcript has grown (once per turn). jq streams with -n 'reduce(inputs)' (no
# slurp). Compaction that prunes the transcript lowers the total. tok0/tok1 are the width
# tiers (full / read-only); tok2 is empty (segment dropped). Hidden until a turn records
# usage. The assembly below places the chosen tier between ctx and rest.
tok0=""; tok1=""; tok2=""
if [ "${CC_TOKENS:-1}" != "0" ] && [ -n "$tpath" ] && [ -f "$tpath" ]; then
  sid=$(j '.session_id // "default"')
  sz=$(stat -c %s "$tpath" 2>/dev/null || stat -f %z "$tpath" 2>/dev/null || printf 0)
  mt=$(stat -c %Y "$tpath" 2>/dev/null || stat -f %m "$tpath" 2>/dev/null || printf 0)
  tf="$CACHE_DIR/tokens-$sid"; rd=0; wr=0; psz=""; pmt=""
  [ -f "$tf" ] && IFS=' ' read -r psz pmt rd wr < "$tf" 2>/dev/null
  case "$rd" in ''|*[!0-9]*) rd=0 ;; esac; case "$wr" in ''|*[!0-9]*) wr=0 ;; esac
  if [ "$psz" != "$sz" ] || [ "$pmt" != "$mt" ]; then         # rescan only when it grew
    IFS=$'\t' read -r rd wr < <(jq -n -r '
      reduce (inputs | select(.type=="assistant") | .message.usage? // empty) as $u
        ({r:0,w:0};
             .r += (($u.input_tokens//0)+($u.cache_read_input_tokens//0)+($u.cache_creation_input_tokens//0))
           | .w += ($u.output_tokens//0))
      | "\(.r)\t\(.w)"' "$tpath" 2>/dev/null)
    case "$rd" in ''|*[!0-9]*) rd=0 ;; esac; case "$wr" in ''|*[!0-9]*) wr=0 ;; esac
    mkdir -p "$CACHE_DIR" 2>/dev/null && printf '%s %s %s %s\n' "$sz" "$mt" "$rd" "$wr" > "$tf" 2>/dev/null
  fi
  if [ "$rd" -gt 0 ] || [ "$wr" -gt 0 ]; then
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
ctx0="${sep}${bar} ${C}$(pad 4 "${pct}%")${R}${sep}${DIM}$(pad 4 "$(fmt "$used")")/$(fmt "$total")${R}"
ctx1="${sep}${C}$(pad 4 "${pct}%")${R}${sep}${C}$(pad 4 "$(fmt "$used")")${R}${DIM}/$(fmt "$total")${R}"
ctx2="${sep}${C}$(pad 4 "$(fmt "$used")")${R}${DIM}/$(fmt "$total")${R}"

# rest — everything after the context segment; independent of the chosen tier.
rest=""
# 5-hour rate-limit usage
if [ -n "$lim5" ]; then
  LC=$(col "$lim5")
  rest="${rest}${sep}${DIM}5h ${R}${LC}$(pad 4 "${lim5}%")${R}"
fi

# git branch — symbolic-ref shows the real branch even on an unborn/empty branch
# (rev-parse would print literal "HEAD"); fall back to short commit when detached.
if [ -n "$cwd" ]; then
  br=$(git -C "$cwd" symbolic-ref --quiet --short HEAD 2>/dev/null)
  if [ -z "$br" ]; then
    sha=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
    [ -n "$sha" ] && br="(${sha})"
  fi
  if [ -n "$br" ]; then
    BRMAX=${CC_BRANCH_MAX:-18}
    [ "${#br}" -gt "$BRMAX" ] && br="${br:0:$((BRMAX-1))}…"
    rest="${rest}${sep}${DIM}⎇ ${br}${R}"
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
if [ -f "$CACHE_DIR/applied-version" ]; then
  av=$(cat "$CACHE_DIR/applied-version" 2>/dev/null)
  ann=$(cat "$CACHE_DIR/announced-version" 2>/dev/null)
  if [ -n "$av" ] && [ "$av" != "$ann" ]; then
    rest="${rest}${sep}$(col 0)⇧ v${av}${R}"
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
ctx="$ctx0"; tok="$tok0"
if [ "${CC_COMPACT:-1}" != "0" ] && [ "$cols" -gt 0 ]; then
  # task-32: superseded — the collapse iterated context tiers only:
  #   for cand in "$ctx0" "$ctx1" "$ctx2"; do ctx="$cand"; measure "${head}${ctx}${rest}"; done
  # Now it walks (ctx,tok) pairs, dropping write, then read, then the bar, then the pct;
  # with CC_TOKENS=0 the tok tiers are empty so it reduces to the prior ctx0/1/2 walk.
  # Indirect ${!name} expands the tier variables named in each pair.
  for pair in "ctx0 tok0" "ctx0 tok1" "ctx0 tok2" "ctx1 tok2" "ctx2 tok2"; do
    cn=${pair% *}; tn=${pair#* }; ctx=${!cn}; tok=${!tn}
    vis=$(printf '%s' "${head}${ctx}${tok}${rest}" | LC_ALL=C awk '{s=$0; gsub(/\033\[[0-9;]*m/,"",s); gsub(/[\200-\277]/,"",s); print length(s)}')
    [ "$vis" -le "$cols" ] && break
  done
fi
out="${head}${ctx}${tok}${rest}"

printf '%s' "$out"

# task-20: spawn the once-a-day self-update, fully detached so it never delays this
# render (the network runs in the background; the foreground work here is only a
# stat and a touch). The stamp is written now so a failed or slow check still waits
# a day before retrying. Guarded by CC_AUTO_UPDATE (opt-in, decision-3) and curl's
# presence.
# task-33: superseded — if [ "${CC_AUTO_UPDATE:-1}" != "0" ] && command -v curl >/dev/null 2>&1; then
if [ "${CC_AUTO_UPDATE:-0}" = "1" ] && command -v curl >/dev/null 2>&1; then
  stamp="$CACHE_DIR/last-check"; now=$(date +%s); last=0
  [ -f "$stamp" ] && last=$(stat -c %Y "$stamp" 2>/dev/null || stat -f %m "$stamp" 2>/dev/null || printf 0)
  case "$last" in ''|*[!0-9]*) last=0 ;; esac
  if [ "$(( now - last ))" -ge 86400 ]; then
    mkdir -p "$CACHE_DIR" 2>/dev/null && : > "$stamp" 2>/dev/null
    ( self_update & ) </dev/null >/dev/null 2>&1
  fi
fi
