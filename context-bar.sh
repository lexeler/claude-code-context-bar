#!/usr/bin/env bash
#
# context-bar — a minimalistic context-usage gauge for the Claude Code status line.
#
# Reads Claude Code's session JSON on stdin and prints a single-line gradient bar
# plus the used-context percentage. Blue (empty) -> blood-red (full).
#
# Each character cell is split into two colour sub-cells using a half-block glyph
# (▌: foreground paints the left half, background the right), so a 16-char bar
# carries 32 gradient steps and fills at half-cell precision — smooth, yet short.
#
# Pure Bash, no external processes, no network, no state. Runs in a few ms and exits.
#
# Optional environment variables:
#   CCTX_WIDTH   number of character cells in the bar (default: 16 -> 32 sub-cells)
#
# https://github.com/lexeler/claude-code-context-bar   (MIT)

# Read all of stdin with the builtin (no `cat` fork). NUL delimiter -> read everything.
IFS= read -r -d '' json || true

# Only look INSIDE the context_window object. The payload also carries
# rate_limits.*.used_percentage, so an unscoped match could grab the wrong number.
scope=$json
[[ $json == *'"context_window"'* ]] && scope=${json#*\"context_window\"}

# Extract the used-context percentage (integer part). Tolerates whitespace and
# floats (e.g. 22.7 -> 22); falls back to 100 - remaining_percentage.
num=""
if [[ $scope =~ \"used_percentage\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
  num=${BASH_REMATCH[1]}
elif [[ $scope =~ \"remaining_percentage\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
  num=$(( 100 - ${BASH_REMATCH[1]} ))
fi

# Default and clamp to 0..100.
[[ -z $num ]] && num=0
(( num < 0 )) && num=0
(( num > 100 )) && num=100

# Bar width in characters (each = 2 colour sub-cells). Sane default, never < 1.
width=${CCTX_WIDTH:-16}
[[ $width =~ ^[0-9]+$ ]] || width=16
(( width < 1 )) && width=1

sub=$(( width * 2 ))          # total colour sub-cells
last=$(( sub - 1 )); (( last < 1 )) && last=1
filled=$(( num * sub / 100 )) # number of filled sub-cells

esc=$'\033'
reset="${esc}[0m"
dimrgb="95;100;115"           # visible empty-track grey

ramp() { # $1 = t(0..100) -> sets rgb (blue -> dark red)
  rgb="$(( 40 + 110 * $1 / 100 ));$(( 170 - 170 * $1 / 100 ));$(( 255 - 235 * $1 / 100 ))"
}

out=""
for (( i = 0; i < width; i++ )); do
  kl=$(( 2 * i )); kr=$(( kl + 1 ))
  if (( kl < filled )); then ramp $(( kl * 100 / last )); lf=$rgb; else lf=$dimrgb; fi
  if (( kr < filled )); then ramp $(( kr * 100 / last )); rf=$rgb; else rf=$dimrgb; fi
  out+="${esc}[38;2;${lf}m${esc}[48;2;${rf}m▌"
done
out+="$reset"

ramp "$num"
printf '%s %s%d%%%s' "$out" "${esc}[38;2;${rgb}m" "$num" "$reset"
