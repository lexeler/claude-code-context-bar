#!/usr/bin/env bash
#
# context-bar — a minimalistic status line for Claude Code.
#
# Left  : context-window usage — blue->red gradient bar + used %.
# Right : 5-hour rate-limit usage — a low-key muted grey gradient bar, with
#         "H:MM" time-to-reset on its left and used % on its right, right-aligned
#         to the terminal width (COLUMNS) when available.
#
# Each bar cell is a space painted with a *background* colour, so the terminal
# fills the whole cell edge-to-edge — clean and full-height, with no glyphs
# (hence no half-block notch and no sub-pixel flicker at the fill boundary).
#
# Pure Bash; the only external call is one tiny `date` for the reset clock
# (fork-free on Bash 4.2+).
#
# Env: CCTX_THEME (context gradient: blue-red|green-red|cyan-magenta|blue-black|
#      teal-orange, default blue-red), CCTX_WIDTH (context cells, default 16),
#      CCTX_LIMIT (0 = hide 5h tracker), CCTX_LIMIT_WIDTH (5h cells, default 10),
#      CCTX_RMARGIN (right margin, 6).
#
# https://github.com/lexeler/claude-code-context-bar   (MIT)

IFS= read -r -d '' json || true

esc=$'\033'
reset="${esc}[0m"

# --- extract a percentage from a JSON scope into global PCT -----------------
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

# --- build a bar into global BAR by painting cell backgrounds (no glyphs) ----
# $1=num(0..100) $2=cells $3=mode(0 blue->red gradient, 1 muted grey gradient).
# Mode 1 is a muted grey gradient (grayscale, low-key).
build_bar() {
  local n=$1 cells=$2 mode=$3
  local filled=$(( n * cells / 100 ))
  local i t g col out=""
  for (( i = 0; i < cells; i++ )); do
    if (( i < filled )); then
      if (( cells > 1 )); then t=$(( i * 100 / (cells - 1) )); else t=0; fi
      if (( mode == 0 )); then
        col="$(( SR + (ER-SR)*t/100 ));$(( SG + (EG-SG)*t/100 ));$(( SB + (EB-SB)*t/100 ))"
      else
        g=$(( 72 + 48*t/100 ))           # muted grey ramp dark->light (no colour, low-key)
        col="${g};${g};$(( g + 6 ))"
      fi
    else
      (( mode == 0 )) && col="95;100;115" || col="46;48;54"
    fi
    out+="${esc}[48;2;${col}m "
  done
  BAR="${out}${reset}"
}

# COL = "r;g;b" for the context ramp at $1(0..100), using the chosen theme
ctx_rgb() { COL="$(( SR + (ER-SR)*$1/100 ));$(( SG + (EG-SG)*$1/100 ));$(( SB + (EB-SB)*$1/100 ))"; }

# ---- LEFT: context window --------------------------------------------------
# Gradient theme — start RGB (SR,SG,SB) fades to end RGB (ER,EG,EB) as it fills.
case "${CCTX_THEME:-blue-red}" in
  green-red)    SR=46;  SG=204; SB=113; ER=200; EG=20;  EB=20  ;;
  cyan-magenta) SR=0;   SG=200; SB=220; ER=220; EG=0;   EB=140 ;;
  blue-black)   SR=60;  SG=140; SB=255; ER=20;  EG=20;  EB=35  ;;
  teal-orange)  SR=20;  SG=180; SB=170; ER=255; EG=120; EB=0   ;;
  *)            SR=40;  SG=170; SB=255; ER=150; EG=0;   EB=20  ;;  # blue-red (default)
esac

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

    lim_cells=${CCTX_LIMIT_WIDTH:-10}
    [[ $lim_cells =~ ^[0-9]+$ ]] || lim_cells=10
    (( lim_cells < 1 )) && lim_cells=1

    build_bar "$u5" "$lim_cells" 1
    lim_bar="$BAR"

    # time until reset -> "H:MM" (fork-free builtin on Bash 4.2+, else `date`)
    if ! printf -v now '%(%s)T' -1 2>/dev/null || [[ ! $now =~ ^[0-9]+$ ]]; then
      now=$(date +%s 2>/dev/null); [[ $now =~ ^[0-9]+$ ]] || now=0
    fi
    secs=$(( r5 - now )); (( secs < 0 )) && secs=0
    hh=$(( secs / 3600 )); mm=$(( (secs % 3600) / 60 ))
    printf -v tstr '%d:%02d' "$hh" "$mm"

    tcol="112;115;125"           # muted grey labels, low-key like the bar
    lcol="130;133;142"
    u5_label="${u5}%"
    right="${esc}[38;2;${tcol}m${tstr}${reset} ${lim_bar} ${esc}[38;2;${lcol}m${u5_label}${reset}"
    rvis=$(( ${#tstr} + 1 + lim_cells + 1 + ${#u5_label} ))
  fi
fi

# ---- assemble --------------------------------------------------------------
if (( has5h )); then
  cols=${COLUMNS:-0}
  [[ $cols =~ ^[0-9]+$ ]] || cols=0
  rmargin=${CCTX_RMARGIN:-6}
  gap=$(( cols - lvis - rvis - rmargin ))
  if (( cols > 0 && gap >= 1 )); then
    printf '%s%*s%s' "$left" "$gap" '' "$right"
  else
    printf '%s   %s' "$left" "$right"
  fi
else
  printf '%s' "$left"
fi
