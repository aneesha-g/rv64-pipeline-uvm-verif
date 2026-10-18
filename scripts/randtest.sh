#!/usr/bin/env bash
# usage: [GENARGS="--spread"] [SIMARGS="+imem_lat=5"] scripts/randtest.sh [num_seeds=20] [first_seed=1]
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
N=${1:-20}; FIRST=${2:-1}; GENARGS=${GENARGS:-}
D=$ROOT/build/rand
mkdir -p "$D"

names=()
for ((s = FIRST; s < FIRST + N; s++)); do
  t=r_$s
  python3 "$ROOT/gen/gen.py" --seed "$s" $GENARGS --out "$D/$t.S" || exit 1
  riscv64-elf-gcc -march=rv32i -mabi=ilp32 -mno-relax -nostdlib -nostartfiles -static \
      -T "$ROOT/sw/link.ld" "$D/$t.S" -o "$D/$t.elf" || { echo "assemble failed: $D/$t.S"; exit 1; }
  riscv64-elf-objcopy -O binary "$D/$t.elf" "$D/$t.bin"
  names+=("$t")
done

BINDIR=$D OUT=$D/lockstep "$ROOT/scripts/lockstep.sh" "${names[@]}" | grep -v '^PASS'
exit "${PIPESTATUS[0]}"
