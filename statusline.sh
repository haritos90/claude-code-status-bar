#!/usr/bin/env bash
# Claude Code status line — model · effort · context bar · 5h limit · git · cost.
# All values come from the JSON on stdin. Numeric segments are right-padded to a
# fixed width so the line does not shift as values change digit count.
input=$(cat)
j() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }

model=$(j '.model.display_name // .model.id // "?"'); model=${model% (1M context)}
effort=$(j '.effort.level // empty')
used=$(j '.context_window.total_input_tokens // 0')
total=$(j '.context_window.context_window_size // 200000')
pct=$(j '.context_window.used_percentage // 0'); pct=${pct%.*}
lim5=$(j '.rate_limits.five_hour.used_percentage // empty'); lim5=${lim5%.*}
cwd=$(j '.workspace.current_dir // .cwd // ""')
cost=$(j '.cost.total_cost_usd // 0')
modelid=$(j '.model.id // ""')
tpath=$(j '.transcript_path // ""')

R=$'\033[0m'; DIM=$'\033[38;2;120;120;120m'; BOLD=$'\033[1m'
col() { # pct -> ANSI color (green / amber / red)
  if   [ "${1:-0}" -ge 80 ]; then printf '\033[38;2;225;95;75m'
  elif [ "${1:-0}" -ge 50 ]; then printf '\033[38;2;240;190;70m'
  else                            printf '\033[38;2;120;190;120m'
  fi
}
pad() { printf "%${1}s" "$2"; }   # right-align $2 to width $1 (fixed-width segments)
C=$(col "$pct")
sep=" ${DIM}·${R} "

# --- context bar ---
# task-9: superseded — CELLS=10
# task-14: superseded — CELLS=8
CELLS=7
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

# --- assemble (fixed widths: pct 4, tokens 4, 5h 4, cost 7) ---
out="${BOLD}${model}${R}${fbmark}"
[ -n "$effort" ] && out="${out} ${DIM}${effort}${R}"
out="${out}${sep}${bar} ${C}$(pad 4 "${pct}%")${R}${sep}${DIM}$(pad 4 "$(fmt "$used")")/$(fmt "$total")${R}"

# 5-hour rate-limit usage
if [ -n "$lim5" ]; then
  LC=$(col "$lim5")
  out="${out}${sep}${DIM}5h ${R}${LC}$(pad 4 "${lim5}%")${R}"
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
    out="${out}${sep}${DIM}⎇ ${br}${R}"
  fi
fi

# cost — task-11: LC_ALL=C so the dotted JSON value is parsed and formatted with a
# period. A comma-locale printf fails on '1.23' with 'invalid number', and the awk
# guard would misparse a sub-dollar cost to 0 and hide the segment.
if LC_ALL=C awk -v c="$cost" 'BEGIN{exit !(c+0 > 0.0001)}'; then
  out="${out}${sep}${DIM}$(pad 7 "$(LC_ALL=C printf '$%.2f' "$cost")")${R}"
fi

# cache warmth — time until the prompt cache likely expires. The TTL is DETECTED
# from the transcript: which bucket cache writes went to (ephemeral_1h vs
# ephemeral_5m), newest write wins; falls back to CC_TTL (default 1h — the TTL
# subscription sessions always get) before any write. "⧗ Nm" (green) = warm,
# reuse soon; "⧗ —" (dim) = expired, the next request rewrites the history.
# Reflects the last render, not a live idle tick. tpath is read once near the top.
if [ -n "$tpath" ] && [ -f "$tpath" ]; then
  mt=$(stat -c %Y "$tpath" 2>/dev/null || stat -f %m "$tpath" 2>/dev/null)
  case "$mt" in ''|*[!0-9]*) mt="" ;; esac
  ttl=$(tail -n 2000 "$tpath" 2>/dev/null | tail -n +2 \
        | jq -c 'select(.type=="assistant" and ((.message.usage.cache_creation_input_tokens // 0) > 0))
                 | .message.usage.cache_creation
                 | if (.ephemeral_1h_input_tokens // 0) > 0 then 3600
                   elif (.ephemeral_5m_input_tokens // 0) > 0 then 300
                   else empty end' 2>/dev/null | tail -1)
  # task-8: superseded — [ -n "$ttl" ] || ttl=${CC_TTL:-300}
  [ -n "$ttl" ] || ttl=${CC_TTL:-3600}
  if [ -n "$mt" ]; then
    idle=$(( $(date +%s) - mt ))
    if [ "$idle" -lt "$ttl" ]; then
      out="${out}${sep}$(col 0)⧗ $(pad 3 "$(( (ttl - idle + 59) / 60 ))m")${R}"
    else
      # task-8: superseded — out="${out}${sep}${DIM}⧗ $(pad 3 "∞")${R}"
      out="${out}${sep}${DIM}⧗ $(pad 3 "—")${R}"
    fi
  fi
fi

printf '%s' "$out"
