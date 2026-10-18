#!/usr/bin/env bash
# usage: [SIM=path] [SIMARGS="+imem_lat=5"] scripts/lockstep.sh [test names]
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SIM=${SIM:-$ROOT/build/obj_core/sim_core}
SIMARGS=${SIMARGS:-}
ISS=$ROOT/build/iss_rv32
OUT=$ROOT/build/lockstep
mkdir -p "$OUT"

tests=("$@")
if [ ${#tests[@]} -eq 0 ]; then
  for f in "$ROOT"/build/sw/*.bin; do tests+=("$(basename "$f" .bin)"); done
fi

pass=0; fail=0
for t in "${tests[@]}"; do
  bin=$ROOT/build/sw/$t.bin
  python3 "$ROOT/scripts/bin2hex.py" "$bin" "$OUT/$t.hex"
  "$ISS" "$bin" > "$OUT/$t.iss.txt" 2> /dev/null
  "$SIM" +prog="$OUT/$t.hex" +trace="$OUT/$t.rtl.txt" +bin="$bin" $SIMARGS > "$OUT/$t.sim.log" 2>&1
  if diff -q "$OUT/$t.iss.txt" "$OUT/$t.rtl.txt" > /dev/null; then
    echo "PASS $t"; pass=$((pass+1))
  else
    echo "FAIL $t   diff $OUT/$t.iss.txt $OUT/$t.rtl.txt"; fail=$((fail+1))
  fi
done
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
