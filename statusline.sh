#!/usr/bin/env bash
# Claude Code status line; session JSON on stdin.
input=""; IFS= read -rd '' input
# One jq pass; spawns flash in terminal title bars.
# Last three fields: the model-scoped limit, matched by alias.
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
  (.rate_limits.five_hour.resets_at // ""),
  (.rate_limits.seven_day.used_percentage // ""),
  (.rate_limits.seven_day.resets_at // ""),
  ((((.model.id // "") + " " + (.model.display_name // "")) | ascii_downcase) as $m
   | ((.rate_limits // {}) | to_entries
      | map((.key | sub("^[a-z]+_(hour|day|week|month)_"; "")) as $a
          | select($a != .key and ($m | test("\\b" + ($a | gsub("_"; "[-_ ]")) + "\\b")))
          | {a: $a, v: .value})
      | first // {a: "", v: {}})
   | (.a), (.v.used_percentage // ""), (.v.resets_at // ""))' 2>/dev/null)
{ IFS= read -r model; IFS= read -r effort; IFS= read -r used
  IFS= read -r total; IFS= read -r pct;    IFS= read -r lim5
  IFS= read -r cwd;   IFS= read -r modelid; IFS= read -r tpath
  IFS= read -r sid;   IFS= read -r reset5
  IFS= read -r lim7;  IFS= read -r reset7
  IFS= read -r aliasM; IFS= read -r limM; IFS= read -r resetM; } <<< "$fields"
model=${model% (1M context)}
pct=${pct%.*}
lim5=${lim5%.*}
lim7=${lim7%.*}
limM=${limM%.*}

R=$'\033[0m'; DIM=$'\033[38;2;120;120;120m'; BOLD=$'\033[1m'
AMB=$'\033[38;2;240;190;70m'; GRN=$'\033[38;2;120;190;120m'   # fixed marker colors
col() { # pct [tone: ctx 5h 7d md] -> ANSI color
  local p=${1:-0} a=${CC_AMBER:-50} r=${CC_RED:-80} i=1 p0 p1 k s
  [ "$p" -lt 0 ] && p=0; [ "$p" -gt 100 ] && p=100
  [ "$r" -lt "$a" ] && r=$a
  local P=(0 "$a" $(( a + (r - a) * 2 / 3 )) $(( r + (100 - r) / 4 )) 100)
  # Anchors stay distinct under the tmux 256-color clamp.
  case "${2:-ctx}" in
    5h) local RR=(70 90 160 235 230) GG=(118 150 150 140 85) BB=(172 210 250 190 70) ;;    # blue
    7d) local RR=(60 65 220 240 230) GG=(150 182 205 170 85) BB=(150 175 110 70 70) ;;     # teal
    md) local RR=(145 165 210 235 230) GG=(110 120 110 90 85) BB=(175 205 190 125 70) ;;   # violet
    *)  local RR=(110 135 200 230 230) GG=(140 165 175 140 85) BB=(110 110 95 80 70) ;;    # green
  esac
  while [ "$i" -lt 4 ] && [ "$p" -gt "${P[$i]}" ]; do i=$((i+1)); done
  p0=${P[$((i-1))]}; p1=${P[$i]}; s=$(( p1 - p0 )); [ "$s" -le 0 ] && s=1; k=$(( p - p0 ))
  printf '\033[38;2;%d;%d;%dm' \
    $(( RR[i-1] + (RR[i] - RR[i-1]) * k / s )) \
    $(( GG[i-1] + (GG[i] - GG[i-1]) * k / s )) \
    $(( BB[i-1] + (BB[i] - BB[i-1]) * k / s ))
}
pad() { printf "%${1}s" "$2"; }   # right-align $2 to width $1
C=$(col "$pct")
sep=" ${DIM}·${R} "

# --- context bar ---
CELLS=${CC_CELLS:-7}
mkbar() {                                  # $1 = cells; sets BAR
  local cells=$1 filled fstr="" estr="" i=0
  filled=$(( (${pct:-0} * cells + 50) / 100 ))
  [ "$filled" -gt "$cells" ] && filled=$cells
  [ "$filled" -lt 0 ] && filled=0
  while [ "$i" -lt "$filled" ]; do fstr="${fstr}█"; i=$((i+1)); done
  i=0; while [ "$i" -lt $((cells - filled)) ]; do estr="${estr}░"; i=$((i+1)); done
  BAR="${C}${fstr}${DIM}${estr}${R}"
}
# A zero-cell bar stays zero.
CELLS1=$(( (CELLS * 5 + 3) / 7 )); [ "$CELLS1" -lt 1 ] && [ "$CELLS" -ge 1 ] && CELLS1=1
CELLS2=$(( (CELLS * 3 + 3) / 7 )); [ "$CELLS2" -lt 1 ] && [ "$CELLS" -ge 1 ] && CELLS2=1
mkbar "$CELLS";  bar=$BAR
mkbar "$CELLS1"; bar1=$BAR
mkbar "$CELLS2"; bar2=$BAR

# 1234 -> 1k, 1234567 -> 1.2m
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

# --- self-update: opt-in, detached, silent ---
CC_REPO="haritos90/claude-code-status-bar"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-code-status-bar"

# Spawn-free clock on bash 4.2+.
now=$(printf '%(%s)T' -1 2>/dev/null)
case "$now" in ''|*[!0-9]*) now=$(date +%s) ;; esac

# A release published after the install replaces it.
self_update() { # detached; failures are silent
  local tag pub self mt dir tmp
  IFS=' ' read -r tag pub < <(curl -fsSL --max-time 10 "https://api.github.com/repos/$CC_REPO/releases/latest" 2>/dev/null \
        | jq -r '"\(.tag_name // "") \(.published_at // "" | try fromdateiso8601 catch 0)"' 2>/dev/null)
  [ -n "$tag" ] || return 0
  case "$pub" in ''|*[!0-9]*) return 0 ;; esac
  self="${SELF:-$0}"; [ -f "$self" ] || return 0   # SELF: test override
  case "$OSTYPE" in
    darwin*|*bsd*) mt=$(stat -f %m "$self" 2>/dev/null) ;;
    *)             mt=$(stat -c %Y "$self" 2>/dev/null) ;;
  esac
  case "$mt" in ''|*[!0-9]*) mt=0 ;; esac
  [ "$pub" -gt "$mt" ] || return 0                 # never downgrade
  dir=$(dirname "$self")
  tmp=$(mktemp "$dir/.statusline.XXXXXX" 2>/dev/null) || return 0
  if curl -fsSL --max-time 20 "https://raw.githubusercontent.com/$CC_REPO/$tag/statusline.sh" -o "$tmp" 2>/dev/null \
     && [ -s "$tmp" ] && bash -n "$tmp" 2>/dev/null; then
    if cmp -s "$tmp" "$self"; then
      rm -f "$tmp" 2>/dev/null; touch "$self" 2>/dev/null   # same content; mark it current
    else
      chmod +x "$tmp" 2>/dev/null
      mv -f "$tmp" "$self" 2>/dev/null && printf '%s' "${tag#v}" > "$CACHE_DIR/applied-version" 2>/dev/null
    fi
  else
    rm -f "$tmp" 2>/dev/null
  fi
}

# --- transcript pass: tokens, cache TTL, fallback target ---
tok0=""; tok1=""; tok2=""; fbmark=""
if [ -n "$tpath" ] && [ -f "$tpath" ]; then
  case "$OSTYPE" in
    darwin*|*bsd*) szmt=$(stat -f '%z %m' "$tpath" 2>/dev/null) ;;
    *)             szmt=$(stat -c '%s %Y' "$tpath" 2>/dev/null) ;;
  esac
  [ -n "$szmt" ] || szmt="0 0"
  sz=${szmt% *}; mt=${szmt#* }
  # Memoized in CACHE_DIR/tokens-<sid>: sz mt rd wr ttl fbto.
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
    mkdir -p "$CACHE_DIR" 2>/dev/null && printf '%s %s %s %s %s %s\n' "$sz" "$mt" "$rd" "$wr" "$ttl" "$fbto" > "$tf" 2>/dev/null
  fi
  # ⤵: the active model is a fallback.
  [ -n "$fbto" ] && [ "$fbto" = "$modelid" ] && fbmark=" ${AMB}⤵${R}"
  if [ "${CC_TOKENS:-0}" = "1" ] && { [ "$rd" -gt 0 ] || [ "$wr" -gt 0 ]; }; then
    tok0="${sep}${DIM}r:${R}$(pad 4 "$(fmt "$rd")") ${DIM}w:${R}$(pad 4 "$(fmt "$wr")")"
    tok1="${sep}${DIM}r:${R}$(pad 4 "$(fmt "$rd")")"
  fi
fi

# --- assemble ---
head="${BOLD}${model}${R}${fbmark}"
# hd1: two-letter effort (xhigh -> xh)
hd1=$head
if [ -n "$effort" ]; then
  hd1="${head} ${DIM}${effort:0:2}${R}"
  head="${head} ${DIM}${effort}${R}"
fi
hd0=$head

# Amber count while the prompt cache is cold.
UC=$DIM; UC1=$C
if [ "${mt:-0}" -gt 0 ] 2>/dev/null; then
  cttl=$ttl; [ "$cttl" -gt 0 ] 2>/dev/null || cttl=3600
  if [ $(( now - mt )) -gt "$cttl" ]; then
    UC=$'\033[38;2;240;190;70m'; UC1=$UC
  fi
fi
# Context tiers: three bar widths, bar-less, bare percent.
pctf=$(pad 4 "${pct}%"); usedf=$(pad 4 "$(fmt "$used")"); totalf=$(fmt "$total")
pctseg="${C}${pctf}${R}"
cntdim="${UC}${usedf}${R}${DIM}/${totalf}${R}"      # bar present: the count stays dim
cntlit="${UC1}${usedf}${R}${DIM}/${totalf}${R}"     # bar gone: the count takes the fill
ctx0="${sep}${bar} ${pctseg}${sep}${cntdim}"
ctx1="${sep}${bar1} ${pctseg}${sep}${cntdim}"
ctx2="${sep}${bar2} ${pctseg}${sep}${cntdim}"
ctx3="${sep}${pctseg}${sep}${cntlit}"
ctx4="${sep}${pctseg}"                     # the bare percent

# 5h tiers: tail, tail when urgent, none.
rest=""; rs0=""; rs1=""; rs2=""
if [ -n "$lim5" ]; then
  LC=$(col "$lim5" 5h)
  seg5="${LC}$(pad 4 "${lim5}%")${R}"
  tail5=""; pin5=0
  case "$reset5" in *[!0-9]*) reset5="" ;; esac
  if [ -n "$reset5" ] && [ "$reset5" -gt "$now" ]; then
    rem=$(( reset5 - now ))
    if [ "$rem" -ge 5400 ]; then
      t=$(( (rem + 180) / 360 )); tv="$(( t / 10 )).$(( t % 10 ))h"
    else
      tv="$(( (rem + 30) / 60 ))m"
    fi
    # Fallback glyphs cover the next cell.
    tail5=" ${LC}⟳ $(pad 4 "$tv")${R}"
    if [ "$lim5" -ge "${CC_RED:-80}" ] || [ "$rem" -le $(( ${CC_RESET_SOON:-15} * 60 )) ]; then
      pin5=1
    fi
  fi
  rs0="${sep}${seg5}${tail5}"
  rs1="${sep}${seg5}"; [ "$pin5" = 1 ] && rs1=$rs0
  rs2="${sep}${seg5}"
fi
rest=$rs0

mktail() {                                 # $1 = resets_at, $2 = color; sets TAIL
  local rs=$1 c=$2 rem t tv
  TAIL=""
  case "$rs" in ''|*[!0-9]*) return 0 ;; esac
  [ "$rs" -gt "$now" ] || return 0
  rem=$(( rs - now ))
  if [ "$rem" -ge 86400 ]; then                      # tenths of a day
    t=$(( (rem + 4320) / 8640 )); tv="$(( t / 10 )).$(( t % 10 ))d"
  elif [ "$rem" -ge 5400 ]; then
    t=$(( (rem + 180) / 360 ))
    if [ "$t" -ge 100 ]; then tv="$(( (rem + 1800) / 3600 ))h"   # keeps four chars
    else tv="$(( t / 10 )).$(( t % 10 ))h"; fi
  else
    tv="$(( (rem + 30) / 60 ))m"
  fi
  # Fallback glyphs cover the next cell.
  TAIL=" ${c}⟳ $(pad 4 "$tv")${R}"
}

# Weekly tiers drop tail, then figure; odd ones pin urgent.
wk=""; wk0=""; wk1=""; wk2=""; wk3=""; wk4=""
if [ -n "$lim7" ]; then
  WC=$(col "$lim7" 7d)
  mktail "$reset7" "$WC"
  seg7="${DIM}7d ${R}${WC}$(pad 4 "${lim7}%")${R}"
  wk0="${sep}${seg7}${TAIL}"; wk1="${sep}${seg7}"; wk2=$wk1
  [ "$lim7" -ge "${CC_RED:-80}" ] && { wk1=$wk0; wk3=$wk2; }
fi
wk=$wk0

# Model-scoped limit; tiers as the weekly one.
md=""; md0=""; md1=""; md2=""; md3=""; md4=""
if [ -n "$limM" ] && [ -n "$aliasM" ]; then
  MC=$(col "$limM" md)
  mktail "$resetM" "$MC"
  segm="${DIM}${aliasM} ${R}${MC}$(pad 4 "${limM}%")${R}"
  md0="${sep}${segm}${TAIL}"; md1="${sep}${segm}"; md2=$md1
  [ "$limM" -ge "${CC_RED:-80}" ] && { md1=$md0; md3=$md2; }
fi
md=$md0

# Read .git/HEAD directly; no git spawn.
# brf: the branch takes the room left, down to brfloor.
br0=""; br1=""; br2=""; brf=""; brfloor=0
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
  if [ -n "$br" ]; then
    BRMAX=${CC_BRANCH_MAX:-18}
    BRMIN=${CC_BRANCH_MIN:-1}                 # fewest letters kept
    case "$BRMIN" in ''|*[!0-9]*|0) BRMIN=1 ;; esac
    b=$br
    [ "${#b}" -gt "$BRMAX" ] && b="${b:0:$((BRMAX-1))}…"
    br0="${sep}${DIM}⎇ ${b}${R}"
    brfloor=$(( BRMIN + 1 )); [ "${#br}" -le "$BRMIN" ] && brfloor=${#br}
  fi
fi

# ⇧ vX.Y.Z once after a self-update.
tailseg=""
if [ -f "$CACHE_DIR/applied-version" ]; then
  av=""; ann=""
  IFS= read -r av < "$CACHE_DIR/applied-version" 2>/dev/null
  [ -f "$CACHE_DIR/announced-version" ] && IFS= read -r ann < "$CACHE_DIR/announced-version" 2>/dev/null
  if [ -n "$av" ] && [ "$av" != "$ann" ]; then
    tailseg="${sep}${GRN}⇧ v${av}${R}"
    printf '%s' "$av" > "$CACHE_DIR/announced-version" 2>/dev/null
  fi
fi

# rc while Remote Control is attached.
rcseg=""
if [ -n "${CLAUDE_CODE_BRIDGE_SESSION_ID:-}" ]; then
  # The CLI's green; 256-color inside tmux.
  if [ -n "${TMUX:-}" ] && [ -z "${CLAUDE_CODE_TMUX_TRUECOLOR:-}" ]; then
    RCC=$'\033[38;5;114m'
  else
    RCC=$'\033[38;2;78;186;101m'
  fi
  rcseg="${sep}${RCC}rc${R}"
fi

# --- collapse: the widest tier that fits ---
cols=${COLUMNS:-0}
ctx="$ctx0"; tok="$tok0"; brseg="$br0"
if [ "${CC_COMPACT:-1}" != "0" ] && [ "$cols" -gt 0 ]; then
  budget=$(( cols - ${CC_RESERVE:-4} ))      # minus the renderer's padding
  # Drop order: bar, effort, tails, tokens, count, branch, figures.
  tiers=("ctx0 tok0 br0 rs0 wk0 md0 hd0" "ctx1 tok0 br0 rs0 wk0 md0 hd0" "ctx2 tok0 br0 rs0 wk0 md0 hd0" \
         "ctx3 tok0 br0 rs0 wk0 md0 hd0" "ctx3 tok0 br0 rs0 wk0 md0 hd1" "ctx3 tok0 br0 rs1 wk0 md0 hd1" \
         "ctx3 tok0 br0 rs1 wk0 md1 hd1" "ctx3 tok0 br0 rs1 wk1 md1 hd1" "ctx3 tok1 br0 rs1 wk1 md1 hd1" \
         "ctx3 tok2 br0 rs1 wk1 md1 hd1" "ctx4 tok2 brf rs1 wk1 md1 hd1" \
         "ctx4 tok2 br2 rs1 wk1 md1 hd1" "ctx4 tok2 br2 rs2 wk1 md1 hd1" "ctx4 tok2 br2 rs2 wk1 md2 hd1" \
         "ctx4 tok2 br2 rs2 wk2 md2 hd1" "ctx4 tok2 br2 rs2 wk2 md3 hd1" "ctx4 tok2 br2 rs2 wk3 md3 hd1" \
         "ctx4 tok2 br2 rs2 wk3 md4 hd1" "ctx4 tok2 br2 rs2 wk4 md4 hd1")
  cands=()
  for trio in "${tiers[@]}"; do
    read -r cn tn bn rn kn mn hn <<< "$trio"
    cands+=("${!hn}${!cn}${!rn}${!kn}${!mn}${!bn}${!tn}${rcseg}${tailseg}")
  done
  sel=$(( ${#tiers[@]} - 1 ))               # none fits: the narrowest
  i=0; brroom=0
  while IFS= read -r vis; do
    case " ${tiers[$i]} " in
      *" brf "*)                              # " · ⎇ " takes 5 columns
        brroom=$(( budget - vis - 5 ))
        if [ -n "$br" ]; then [ "$brroom" -ge "$brfloor" ] && { sel=$i; break; }
        else [ "$vis" -le "$budget" ] && { sel=$i; break; }; fi ;;
      *) [ "$vis" -le "$budget" ] && { sel=$i; break; } ;;
    esac
    i=$((i+1))
  done < <(printf '%s\n' "${cands[@]}" | LC_ALL=C awk '{s=$0; gsub(/\033\[[0-9;]*m/,"",s); gsub(/[\200-\277]/,"",s); print length(s)}')
  read -r cn tn bn rn kn mn hn <<< "${tiers[$sel]}"
  ctx=${!cn}; tok=${!tn}; brseg=${!bn}; rest=${!rn}; wk=${!kn}; md=${!mn}; head=${!hn}
  if [ "$bn" = brf ] && [ -n "$br" ]; then  # one letter at a time
    b=$br; n=$brroom; [ "$n" -gt "$BRMAX" ] && n=$BRMAX
    [ "${#b}" -gt "$n" ] && b="${b:0:$((n-1))}…"
    brseg="${sep}${DIM}⎇ ${b}${R}"
  fi
fi
out="${head}${ctx}${rest}${wk}${md}${brseg}${tok}${rcseg}${tailseg}"

printf '%s' "$out"

# Daily check; RANDOM thins the stat to 1/20 of renders.
if [ "${CC_AUTO_UPDATE:-0}" = "1" ] && [ $(( RANDOM % 20 )) -eq 0 ] && command -v curl >/dev/null 2>&1; then
  stamp="$CACHE_DIR/last-check"; last=0
  if [ -f "$stamp" ]; then
    case "$OSTYPE" in
      darwin*|*bsd*) last=$(stat -f %m "$stamp" 2>/dev/null) ;;
      *)             last=$(stat -c %Y "$stamp" 2>/dev/null) ;;
    esac
  fi
  case "$last" in ''|*[!0-9]*) last=0 ;; esac
  if [ "$(( now - last ))" -ge 86400 ]; then
    mkdir -p "$CACHE_DIR" 2>/dev/null && : > "$stamp" 2>/dev/null   # a failure waits a day
    ( self_update & ) </dev/null >/dev/null 2>&1
  fi
fi
