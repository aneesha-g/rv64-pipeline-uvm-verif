#!/usr/bin/env bash
# usage: scripts/cpi.sh [tests]   cycles / CPI / redirects with and without the predictor
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ON=$ROOT/build/obj_core/sim_core
OFF=$ROOT/build/obj_core_nobp/sim_core_nobp
OUT=$ROOT/build/cpi
mkdir -p "$OUT"

tests=("$@")
if [ ${#tests[@]} -eq 0 ]; then
  for f in "$ROOT"/build/sw/*.bin; do tests+=("$(basename "$f" .bin)"); done
fi

printf "%-10s %6s %9s %7s %9s %7s %10s %8s\n" test insns cyc_nobp cpi_nobp cyc_bp cpi_bp redir_nobp redir_bp
for t in "${tests[@]}"; do
  python3 "$ROOT/scripts/bin2hex.py" "$ROOT/build/sw/$t.bin" "$OUT/$t.hex"
  "$OFF" +prog="$OUT/$t.hex" +trace="$OUT/$t.off.txt" > "$OUT/$t.off.log" 2>&1
  "$ON"  +prog="$OUT/$t.hex" +trace="$OUT/$t.on.txt"  > "$OUT/$t.on.log"  2>&1
  n=$(wc -l < "$OUT/$t.on.txt")
  co=$(sed -n 's/^cycles=//p' "$OUT/$t.off.log")
  cb=$(sed -n 's/^cycles=//p' "$OUT/$t.on.log")
  ro=$(sed -n 's/.*redirects=//p' "$OUT/$t.off.log")
  rb=$(sed -n 's/.*redirects=//p' "$OUT/$t.on.log")
  awk -v t="$t" -v n="$n" -v co="$co" -v cb="$cb" -v ro="$ro" -v rb="$rb" \
    'BEGIN{printf "%-10s %6d %9d %7.2f %9d %7.2f %10d %8d\n", t, n, co, co/n, cb, cb/n, ro, rb}'
done
