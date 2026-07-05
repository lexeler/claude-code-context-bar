#!/usr/bin/env bash
# Test suite for context-bar.sh (half-block, 2 colour sub-cells per char).
# Fill is encoded in colour, so we verify: printed % + count of filled sub-cells.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
BAR="$DIR/context-bar.sh"
pass=0; fail=0
DIMC='95;100;115'

# check <label> <json> <expected_num> [env] [width]
check() {
  local label="$1" json="$2" num="$3" env="${4:-}" w="${5:-16}"
  local sub=$(( w * 2 )) raw pct dim filled expf
  if [[ -n $env ]]; then raw=$(printf '%s' "$json" | env $env "$BAR"); else raw=$(printf '%s' "$json" | "$BAR"); fi
  pct=$(grep -oE '[0-9]+%' <<<"$raw" | tr -d '%' | tail -1); pct=${pct:-none}
  dim=$(grep -o "$DIMC" <<<"$raw" | wc -l | tr -d ' ')
  filled=$(( sub - dim ))
  expf=$(( num * sub / 100 ))
  if [[ "$pct" == "$num" && "$filled" -eq "$expf" ]]; then
    pass=$((pass+1)); printf '  ok   %-32s (%d%%, %d/%d filled)\n' "$label" "$num" "$filled" "$sub"
  else
    fail=$((fail+1)); printf '  FAIL %-32s  want %%=%s filled=%d/%d, got %%=%s filled=%d\n' "$label" "$num" "$expf" "$sub" "$pct" "$filled"
  fi
}

echo "── correctness ──"
check "used 0%"            '{"context_window":{"used_percentage":0}}'   0
check "used 25%"           '{"context_window":{"used_percentage":25}}'  25
check "used 50%"           '{"context_window":{"used_percentage":50}}'  50
check "used 100%"          '{"context_window":{"used_percentage":100}}' 100
check "whitespace ': 40'"  '{"used_percentage": 40}'                    40
check "float 22.7 -> 22"   '{"used_percentage":22.7}'                   22
check "remaining 76 ->24"  '{"context_window":{"remaining_percentage":76}}' 24
check "remaining 100 ->0"  '{"remaining_percentage":100}'               0

echo "── robustness ──"
check "empty object"       '{}'                                        0
check "empty input"        ''                                          0
check "malformed json"     '{ broken :: '                              0
check "garbage text"       'hello not json'                            0
check "clamp rem 120 ->0"  '{"remaining_percentage":120}'              0
check "clamp used 150"     '{"used_percentage":150}'                   100
check "no false-match key" '{"foo_used_percentage":99,"context_window":{"used_percentage":10}}' 10

echo "── real payload (multiple used_percentage) ──"
REAL='{"context_window":{"current_usage":{"input_tokens":2},"context_window_size":1000000,"used_percentage":31,"remaining_percentage":69},"rate_limits":{"five_hour":{"used_percentage":10},"seven_day":{"used_percentage":19}}}'
check "picks context_window (31)" "$REAL" 31

echo "── config (CCTX_WIDTH) ──"
check "width=8 @50%"       '{"used_percentage":50}'   50  "CCTX_WIDTH=8"  8
check "width=invalid ->16" '{"used_percentage":50}'   50  "CCTX_WIDTH=xx" 16
check "width=0 ->1 cell"   '{"used_percentage":100}'  100 "CCTX_WIDTH=0"  1
check "width=32 @50%"      '{"used_percentage":50}'   50  "CCTX_WIDTH=32" 32

echo "── hygiene ──"
err=$(printf '%s' '{"used_percentage":50}' | "$BAR" 2>&1 1>/dev/null)
[[ -z $err ]] && { pass=$((pass+1)); echo "  ok   no stderr output"; } || { fail=$((fail+1)); echo "  FAIL stderr: $err"; }
printf '%s' '{"used_percentage":50}' | "$BAR" >/dev/null 2>&1
[[ $? -eq 0 ]] && { pass=$((pass+1)); echo "  ok   exit code 0"; } || { fail=$((fail+1)); echo "  FAIL nonzero exit"; }

echo
echo "RESULT: $pass passed, $fail failed"
exit $(( fail > 0 ))
