#!/usr/bin/env python3
"""Mutation testing for the RV32 core.

For each mutant in mutants/mutant_defs.py: copy rtl/, inject ONE bug, rebuild the simulator,
run the whole suite (directed + random programs) through ISS-vs-RTL lockstep.
  KILLED         some test shows an ISS-vs-RTL mismatch
  KILLED (perf)  results correct, but cycle counts differ from the golden build
  SURVIVED       nothing noticed the bug -> the tests have a hole
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "mutants"))
from mutant_defs import MUTANTS  # noqa: E402

BUILD = ROOT / "build" / "mut"
VFLAGS = ["--binary", "--timing", "--trace", "-Wno-fatal", "-Wno-PINMISSING", "-Wno-WIDTH",
          "-Wno-TIMESCALEMOD", "--top-module", "tb_core", "--CFLAGS", "-DXLEN=32", "-j", "4"]


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def count_matches(m):
    return len(re.findall(m["pattern"], (ROOT / "rtl" / m["file"]).read_text()))


def build_suite(nseeds, fresh):
    suite = BUILD / "suite"
    if fresh and suite.exists():
        shutil.rmtree(suite)
    suite.mkdir(parents=True, exist_ok=True)
    for b in (ROOT / "build" / "sw").glob("*.bin"):
        shutil.copy(b, suite)
    specs = [(f"r_{s}", s, []) for s in range(1, nseeds + 1)]
    specs += [(f"rs_{s}", s, ["--spread"]) for s in range(100, 106)]
    specs += [(f"rl_{s}", s, ["--n", "300"]) for s in range(200, 206)]
    for name, seed, extra in specs:
        binp = suite / f"{name}.bin"
        if binp.exists():
            continue
        src, elf = suite / f"{name}.S", suite / f"{name}.elf"
        r = run([sys.executable, str(ROOT / "gen/gen.py"), "--seed", str(seed), *extra, "--out", str(src)])
        if r.returncode:
            sys.exit(r.stderr)
        r = run(["riscv64-elf-gcc", "-march=rv32i", "-mabi=ilp32", "-mno-relax", "-nostdlib",
                 "-nostartfiles", "-static", "-T", str(ROOT / "sw/link.ld"), str(src), "-o", str(elf)])
        if r.returncode:
            sys.exit(r.stderr)
        run(["riscv64-elf-objcopy", "-O", "binary", str(elf), str(binp)])
    return suite, len(list(suite.glob("*.bin")))


def build_sim(rtl_dir, out_dir):
    out_dir.mkdir(parents=True, exist_ok=True)
    rtl = sorted(str(p) for p in rtl_dir.glob("*.v"))
    cmd = ["verilator", *VFLAGS, "--Mdir", str(out_dir / "obj"), "-o", "sim", *rtl,
           str(ROOT / "tb/directed/rvfi_checker.sv"), str(ROOT / "tb/directed/tb_core.sv"),
           str(ROOT / "iss/iss.cpp"), str(ROOT / "iss/dpi.cpp")]
    r = run(cmd)
    sim = out_dir / "obj" / "sim"
    if r.returncode != 0 or not sim.exists():
        return None, (r.stdout + r.stderr)[-1500:]
    return sim, ""


def run_suite(sim, tag, suite):
    out = BUILD / tag / "lockstep"
    shutil.rmtree(out, ignore_errors=True)
    env = dict(os.environ, SIM=str(sim), BINDIR=str(suite), OUT=str(out))
    r = run([str(ROOT / "scripts/lockstep.sh")], env=env)
    fails = [l.split()[1] for l in r.stdout.splitlines() if l.startswith("FAIL ")]
    cycles = {}
    for log in out.glob("*.sim.log"):
        mt = re.search(r"^cycles=(\d+)", log.read_text(errors="ignore"), re.M)
        if mt:
            cycles[log.name[:-len(".sim.log")]] = int(mt.group(1))
    return fails, cycles


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="only check that every pattern matches exactly once")
    ap.add_argument("--only", help="comma-separated mutant names")
    ap.add_argument("--seeds", type=int, default=30, help="plain random programs in the suite")
    ap.add_argument("--fresh", action="store_true", help="regenerate the random programs")
    a = ap.parse_args()

    muts = [m for m in MUTANTS if not a.only or m["name"] in a.only.split(",")]
    bad = False
    for m in muts:
        n = count_matches(m)
        print(f"{'OK ' if n == 1 else 'ERR'} {m['name']:<24} pattern matches {n}x in rtl/{m['file']}")
        bad |= n != 1
    if bad:
        sys.exit("fix the patterns above (each must match exactly once)")
    if a.check:
        return

    if not list((ROOT / "build/sw").glob("*.bin")):
        sys.exit("no directed tests built: run  make -C sw")
    suite, ntests = build_suite(a.seeds, a.fresh)
    print(f"suite: {ntests} tests")

    print("golden build...", flush=True)
    gsim, err = build_sim(ROOT / "rtl", BUILD / "golden")
    if not gsim:
        sys.exit("golden build failed:\n" + err)
    gfails, gcycles = run_suite(gsim, "golden", suite)
    if gfails:
        sys.exit("the unmutated RTL fails its own suite, fix that first: " + " ".join(gfails[:10]))

    rows = []
    for i, m in enumerate(muts, 1):
        print(f"[{i}/{len(muts)}] {m['name']}: building...", flush=True)
        rtl = BUILD / m["name"] / "rtl"
        shutil.rmtree(rtl, ignore_errors=True)
        shutil.copytree(ROOT / "rtl", rtl)
        f = rtl / m["file"]
        f.write_text(re.sub(m["pattern"], lambda _: m["replace"], f.read_text()))
        sim, err = build_sim(rtl, BUILD / m["name"])
        if not sim:
            print(err)
            rows.append((m, "BUILD ERROR", "-", "-"))
            continue
        fails, cyc = run_suite(sim, m["name"], suite)
        if fails:
            res, by, cnt = "KILLED", fails[0], f"{len(fails)}/{ntests}"
        else:
            diff = [t for t in gcycles if cyc.get(t) != gcycles[t]]
            if diff:
                res, by, cnt = "KILLED (perf)", f"cycles differ, e.g. {diff[0]}", f"{len(diff)}/{ntests}"
            else:
                res, by, cnt = "SURVIVED", "-", f"0/{ntests}"
        rows.append((m, res, by, cnt))
        print(f"    -> {res}  {by}  ({cnt})", flush=True)

    killed = sum(r[1].startswith("KILLED") for r in rows)
    lines = ["# Mutation testing results", "",
             f"Suite: {ntests} tests (directed + random + spread + long random). Detectors: live ISS-vs-RTL "
             "lockstep (functional) and cycle count vs the unmutated build (performance).", "",
             "| # | Mutant | Bug injected | Expected | Result | First catch | Tests failing |",
             "|---|---|---|---|---|---|---|"]
    for i, (m, res, by, cnt) in enumerate(rows, 1):
        lines.append(f"| {i} | `{m['name']}` | {m['desc']} | {m['kind']} | {res} | {by} | {cnt} |")
    lines += ["", f"**Mutation score: {killed}/{len(rows)} killed.**", ""]
    (ROOT / "docs").mkdir(exist_ok=True)
    (ROOT / "docs" / "mutation.md").write_text("\n".join(lines))
    print("\n" + "\n".join(lines))
    print("wrote docs/mutation.md")
    sys.exit(0 if killed == len(rows) else 1)


if __name__ == "__main__":
    main()
