#!/usr/bin/env bash
# usage: [IMEM_LAT=3] scripts/cpi.sh [tests]
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ON=$ROOT/build/obj_core/sim_core
OFF=$ROOT/build/obj_core_nobp/sim_core_nobp
OUT=$ROOT/build/cpi
LAT=${IMEM_LAT:-3}
mkdir -p "$OUT"

tests=("$@")
if [ ${#tests[@]} -eq 0 ]; then
  for f in "$ROOT"/build/sw/*.bin; do tests+=("$(basename "$f" .bin)"); done
fi

echo "imem_lat=$LAT"
printf "%-10s %6s %9s %7s %9s %7s %8s %9s %9s\n" test insns cyc_nobp cpi_nobp cyc_bp cpi_bp redir_bp ic_fills ic_stalls
for t in "${tests[@]}"; do
  python3 "$ROOT/scripts/bin2hex.py" "$ROOT/build/sw/$t.bin" "$OUT/$t.hex"
  "$OFF" +prog="$OUT/$t.hex" +trace="$OUT/$t.off.txt" +imem_lat=$LAT > "$OUT/$t.off.log" 2>&1
  "$ON"  +prog="$OUT/$t.hex" +trace="$OUT/$t.on.txt"  +imem_lat=$LAT > "$OUT/$t.on.log"  2>&1
  n=$(wc -l < "$OUT/$t.on.txt")
  co=$(sed -n 's/^cycles=//p' "$OUT/$t.off.log")
  cb=$(sed -n 's/^cycles=//p' "$OUT/$t.on.log")
  rb=$(sed -n 's/.*redirects=//p' "$OUT/$t.on.log")
  fi=$(sed -n 's/^ic_fills=\([0-9]*\) .*/\1/p' "$OUT/$t.on.log")
  st=$(sed -n 's/.*ic_stalls=//p' "$OUT/$t.on.log")
  awk -v t="$t" -v n="$n" -v co="$co" -v cb="$cb" -v rb="$rb" -v fi="$fi" -v st="$st" \
    'BEGIN{printf "%-10s %6d %9d %7.2f %9d %7.2f %8d %9d %9d\n", t, n, co, co/n, cb, cb/n, rb, fi, st}'
done
