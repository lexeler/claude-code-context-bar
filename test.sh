#!/usr/bin/env bash
# Test suite for context-bar.sh (context bar + 5h rate-limit tracker).
# Fill is colour-encoded, so we verify by counting each bar's empty-track colour,
# plus the printed numbers, the reset clock, warning tint, and right-alignment.
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
BAR="$DIR/context-bar.sh"
pass=0; fail=0
CTX_DIM='95;100;115'   # context empty-track colour
LIM_DIM='46;48;54'     # 5h empty-track colour

ok(){ pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
no(){ fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$1" "$2"; }

run(){ # $1=json $2=env-assignments -> raw output
  if [[ -n ${2:-} ]]; then printf '%s' "$1" | env $2 "$BAR"; else printf '%s' "$1" | "$BAR"; fi
}
strip(){ sed 's/\x1b\[[0-9;]*m//g'; }
vis(){ strip | tr -d '\n' | wc -m | tr -d ' '; }        # visible columns
countc(){ grep -o "$2" <<<"$1" | wc -l | tr -d ' '; }   # count colour occurrences
ctx_filled(){ echo $(( 16 - $(countc "$1" "$CTX_DIM") )); }
lim_filled(){ echo $(( 10 - $(countc "$1" "$LIM_DIM") )); }   # default 10 cells -> 20 sub
nums(){ grep -oE '[0-9]+%' <<<"$(strip <<<"$1")" | tr -d '%'; }

NOW=$(date +%s); R=$(( NOW + 3*3600 + 12*60 ))   # 3:12 from now
pay(){ # $1=ctx% $2=5h%
  echo "{\"context_window\":{\"used_percentage\":$1},\"rate_limits\":{\"five_hour\":{\"used_percentage\":$2,\"resets_at\":$R},\"seven_day\":{\"used_percentage\":19,\"resets_at\":$((R+9))}}}"
}

echo "── context bar ──"
for p in 0 25 50 100; do
  o=$(run "$(pay $p 40)" "COLUMNS=104")
  cf=$(ctx_filled "$o"); ef=$(( p*16/100 )); cn=$(nums "$o" | head -1)
  [[ $cf -eq $ef && $cn == $p ]] && ok "context $p% (filled $cf/32)" || no "context $p%" "filled=$cf want=$ef, num=$cn"
done
o=$(run '{"context_window":{"used_percentage":31},"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":'$R'}}}' "COLUMNS=104")
[[ $(nums "$o" | head -1) == 31 ]] && ok "context ignores rate_limit %" || no "context scoping" "$(nums "$o"|head -1)"

echo "── 5h tracker ──"
for p in 0 40 100; do
  o=$(run "$(pay 25 $p)" "COLUMNS=104")
  lf=$(lim_filled "$o"); ef=$(( p*10/100 )); ln=$(nums "$o" | tail -1)
  [[ $lf -eq $ef && $ln == $p ]] && ok "5h $p% (filled $lf/20)" || no "5h $p%" "filled=$lf want=$ef, num=$ln"
done
o=$(run "$(pay 25 40)" "COLUMNS=104")
[[ $(nums "$o" | tail -1) == 40 ]] && ok "5h picks five_hour (not seven_day 19)" || no "5h scoping" "$(nums "$o"|tail -1)"

echo "── reset clock H:MM ──"
mkr(){ echo "{\"context_window\":{\"used_percentage\":25},\"rate_limits\":{\"five_hour\":{\"used_percentage\":40,\"resets_at\":$1}}}"; }
t=$(run "$(mkr $((NOW+3*3600+12*60)))" "COLUMNS=104" | strip | grep -oE '[0-9]+:[0-9]{2}' | head -1)
[[ $t == 3:12 || $t == 3:11 ]] && ok "clock 3:12 (got $t)" || no "clock" "$t"
t=$(run "$(mkr $((NOW+180)))" "COLUMNS=104" | strip | grep -oE '[0-9]+:[0-9]{2}' | head -1)
[[ $t == 0:03 || $t == 0:02 ]] && ok "clock 0:03 (got $t)" || no "clock small" "$t"
t=$(run "$(mkr $((NOW-500)))" "COLUMNS=104" | strip | grep -oE '[0-9]+:[0-9]{2}' | head -1)
[[ $t == 0:00 ]] && ok "clock clamps past reset -> 0:00" || no "clock past" "$t"

echo "── 5h grey gradient (grayscale, dark->light, low-key) ──"
# the 5h bar's bg colours are the LAST 10 (context bar has 16 before it)
g5=$(run "$(pay 25 80)" "COLUMNS=104" | grep -oE '48;2;[0-9]+;[0-9]+;[0-9]+' | tail -10 | grep -v "$LIM_DIM")
first=$(head -1 <<<"$g5"); last=$(tail -1 <<<"$g5")
fr=$(cut -d';' -f3 <<<"$first"); fg=$(cut -d';' -f4 <<<"$first")
er=$(cut -d';' -f3 <<<"$last");  eg=$(cut -d';' -f4 <<<"$last")
[[ $(( fr>fg?fr-fg:fg-fr )) -le 4 && $(( er>eg?er-eg:eg-er )) -le 4 ]] && ok "5h is grayscale (R≈G, no colour)" || no "grayscale" "$first / $last"
[[ $er -gt $fr ]] && ok "5h gradient dark->light ($fr -> $er)" || no "gradient dir" "$fr -> $er"

echo "── right alignment ──"
w=$(run "$(pay 25 40)" "COLUMNS=104" | vis)
[[ $w -eq $((104-6)) ]] && ok "COLUMNS=104 -> width 98 (=cols-rmargin)" || no "right-align width" "$w"
w=$(run "$(pay 25 40)" "COLUMNS=200" | vis)
[[ $w -eq $((200-6)) ]] && ok "COLUMNS=200 -> width 194 (adapts)" || no "align adapt" "$w"
w=$(run "$(pay 25 40)" "CCTX_RMARGIN=10 COLUMNS=104" | vis)
[[ $w -eq $((104-10)) ]] && ok "CCTX_RMARGIN=10 honoured (width 94)" || no "rmargin env" "$w"

echo "── fallbacks / toggle ──"
o=$(run "$(pay 25 40)" "COLUMNS=30")
[[ $(vis <<<"$o") -lt 60 && $(nums "$o" | wc -l | tr -d ' ') -eq 2 ]] && ok "narrow COLUMNS -> adjacent, both shown" || no "narrow" "$(vis <<<"$o")"
o=$(run "$(pay 25 40)" "")
[[ $(nums "$o" | wc -l | tr -d ' ') -eq 2 ]] && ok "no COLUMNS -> adjacent" || no "no cols" "x"
o=$(run "$(pay 25 40)" "CCTX_LIMIT=0 COLUMNS=104")
[[ $(nums "$o" | wc -l | tr -d ' ') -eq 1 ]] && ok "CCTX_LIMIT=0 hides 5h tracker" || no "toggle off" "x"
o=$(run '{"context_window":{"used_percentage":25}}' "COLUMNS=104")
[[ $(nums "$o" | wc -l | tr -d ' ') -eq 1 ]] && ok "no rate_limits -> context only" || no "no limit data" "x"

echo "── robustness ──"
for j in '{}' '' '{ broken ::' 'garbage'; do
  o=$(run "$j" "COLUMNS=104")
  [[ $(nums "$o" | head -1) == 0 ]] && ok "robust: [${j:0:12}] -> 0%" || no "robust [$j]" "$(nums "$o"|head -1)"
done

echo "── hygiene ──"
err=$(printf '%s' "$(pay 25 40)" | COLUMNS=104 "$BAR" 2>&1 1>/dev/null)
[[ -z $err ]] && ok "no stderr" || no "stderr" "$err"
printf '%s' "$(pay 25 40)" | COLUMNS=104 "$BAR" >/dev/null 2>&1
[[ $? -eq 0 ]] && ok "exit 0" || no "exit" "nonzero"

echo
echo "RESULT: $pass passed, $fail failed"
exit $(( fail > 0 ))
