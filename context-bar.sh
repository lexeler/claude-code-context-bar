#!/usr/bin/env bash
#
# context-bar — a minimalistic status line for Claude Code.
#
# Left  : context-window usage — blue->red gradient bar + used %.
# Right : 5-hour rate-limit usage — grey gradient bar that reddens near the limit,
#         with "H:MM" time-until-reset on its left and used % on its right,
#         right-aligned to the terminal width (COLUMNS) when available.
#
# Pure Bash (one tiny `date` call for the reset clock). Two colour sub-cells per
# character via the half-block glyph for a smooth ramp in a short width.
#
# Env: CCTX_WIDTH (context cells, default 16), CCTX_LIMIT (0 = hide 5h tracker).
#
# https://github.com/lexeler/claude-code-context-bar   (MIT)

IFS= read -r -d '' json || true

esc=$'\033'
reset="${esc}[0m"

# --- extract a percentage from a JSON scope into global PCT -----------------
# $1 = text to search (used_percentage, or 100-remaining). No subshell.
pct_in() {
  local s=$1 n=""
  if [[ $s =~ \"used_percentage\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
    n=${BASH_REMATCH[1]}
  elif [[ $s =~ \"remaining_percentage\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
    n=$(( 100 - ${BASH_REMATCH[1]} ))
  fi
  [[ -z $n ]] && n=0
  (( n < 0 )) && n=0
  (( n > 100 )) && n=100
  PCT=$n
}

# --- build a half-block bar into global BAR ---------------------------------
# $1=num(0..100) $2=cells $3=mode(0 context,1 limit) $4=warn(0..100, limit only)
build_bar() {
  local n=$1 cells=$2 mode=$3 warn=${4:-0}
  local sub=$(( cells * 2 )) last=$(( cells * 2 - 1 ))
  (( last < 1 )) && last=1
  local filled=$(( n * sub / 100 ))
  local i half k t col out=""
  for (( i = 0; i < cells; i++ )); do
    for half in 0 1; do
      k=$(( 2 * i + half ))
      if (( k < filled )); then
        t=$(( k * 100 / last ))
        if (( mode == 0 )); then
          col="$(( 40 + 110*t/100 ));$(( 170 - 170*t/100 ));$(( 255 - 235*t/100 ))"
        else
          # solid, even grey (no ramp -> no bright edge stripe), reddening near the limit
          col="$(( 135 + (215-135)*warn/100 ));$(( 135 + (60-135)*warn/100 ));$(( 145 + (50-145)*warn/100 ))"
        fi
      else
        (( mode == 0 )) && col="95;100;115" || col="46;48;54"
      fi
      (( half == 0 )) && out+="${esc}[38;2;${col}m" || out+="${esc}[48;2;${col}m▌"
    done
  done
  BAR="${out}${reset}"
}

# color helper: sets COL to "r;g;b" for the context ramp at $1(0..100)
ctx_rgb() { COL="$(( 40 + 110*$1/100 ));$(( 170 - 170*$1/100 ));$(( 255 - 235*$1/100 ))"; }

# ---- LEFT: context window --------------------------------------------------
cw=$json
[[ $json == *'"context_window"'* ]] && cw=${json#*\"context_window\"}
pct_in "$cw"; num=$PCT

cw_cells=${CCTX_WIDTH:-16}
[[ $cw_cells =~ ^[0-9]+$ ]] || cw_cells=16
(( cw_cells < 1 )) && cw_cells=1

build_bar "$num" "$cw_cells" 0
ctx_rgb "$num"
ctx_label="${num}%"
left="${BAR} ${esc}[38;2;${COL}m${ctx_label}${reset}"
lvis=$(( cw_cells + 1 + ${#ctx_label} ))

# ---- RIGHT: 5-hour rate limit ----------------------------------------------
has5h=0
if [[ ${CCTX_LIMIT:-1} != 0 && $json == *'"five_hour"'* ]]; then
  fh=${json#*\"five_hour\"}
  if [[ $fh =~ \"used_percentage\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
    has5h=1
    u5=${BASH_REMATCH[1]}
    (( u5 < 0 )) && u5=0; (( u5 > 100 )) && u5=100

    r5=0
    [[ $fh =~ \"resets_at\"[[:space:]]*:[[:space:]]*([0-9]+) ]] && r5=${BASH_REMATCH[1]}

    warn=$(( (u5 - 70) * 100 / 30 ))
    (( warn < 0 )) && warn=0; (( warn > 100 )) && warn=100

    lim_cells=${CCTX_LIMIT_WIDTH:-10}
    [[ $lim_cells =~ ^[0-9]+$ ]] || lim_cells=10
    (( lim_cells < 1 )) && lim_cells=1

    build_bar "$u5" "$lim_cells" 1 "$warn"
    lim_bar="$BAR"

    # time until reset -> "H:MM". Prefer the fork-free builtin (bash 4.2+),
    # fall back to `date` on the stock macOS Bash 3.2.
    if ! printf -v now '%(%s)T' -1 2>/dev/null || [[ ! $now =~ ^[0-9]+$ ]]; then
      now=$(date +%s 2>/dev/null); [[ $now =~ ^[0-9]+$ ]] || now=0
    fi
    secs=$(( r5 - now )); (( secs < 0 )) && secs=0
    hh=$(( secs / 3600 )); mm=$(( (secs % 3600) / 60 ))
    printf -v tstr '%d:%02d' "$hh" "$mm"

    # muted colours for the labels (reddening with warn)
    tcol="120;124;134"
    lr=$(( 150 + (215-150)*warn/100 )); lg=$(( 152 + (60-152)*warn/100 )); lb=$(( 162 + (50-162)*warn/100 ))
    u5_label="${u5}%"
    right="${esc}[38;2;${tcol}m${tstr}${reset} ${lim_bar} ${esc}[38;2;${lr};${lg};${lb}m${u5_label}${reset}"
    rvis=$(( ${#tstr} + 1 + lim_cells + 1 + ${#u5_label} ))
  fi
fi

# ---- assemble --------------------------------------------------------------
if (( has5h )); then
  cols=${COLUMNS:-0}
  [[ $cols =~ ^[0-9]+$ ]] || cols=0
  # COLUMNS is the full terminal width; the status line sits inside a padded box,
  # so leave a right margin (tunable) to avoid Claude Code truncating the tail.
  rmargin=${CCTX_RMARGIN:-6}
  gap=$(( cols - lvis - rvis - rmargin ))
  if (( cols > 0 && gap >= 1 )); then
    printf '%s%*s%s' "$left" "$gap" '' "$right"
  else
    printf '%s   %s' "$left" "$right"   # not enough width -> sit next to it
  fi
else
  printf '%s' "$left"
fi
