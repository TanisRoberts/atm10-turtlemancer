#!/usr/bin/env python3
"""Compile-check every .lua file, then run the simulator scenarios.

    python3 tests/run.py                 # compile check + every scenario
    python3 tests/run.py storage         # compile check + scenarios/storage*.lua
    python3 tests/run.py --check         # compile check only
    python3 tests/run.py --no-check smelter

Needs lupa (Lua 5.2, same as CraftOS): pip install --break-system-packages -q lupa
"""
import sys
from pathlib import Path

try:
    from lupa.lua52 import LuaRuntime
except ImportError:
    sys.exit("lupa is missing: pip install --break-system-packages -q lupa")

ROOT = Path(__file__).resolve().parent.parent
SKIP_DIRS = {".git", "node_modules"}


def lua_files():
    for p in sorted(ROOT.rglob("*.lua")):
        if not SKIP_DIRS.intersection(p.relative_to(ROOT).parts):
            yield p


def compile_check():
    lua = LuaRuntime()
    compile_ = lua.eval("function(src, name) local f, err = load(src, name, 't', {}); return err end")
    bad = 0
    n = 0
    for p in lua_files():
        n += 1
        err = compile_(p.read_bytes(), "@" + str(p.relative_to(ROOT)))
        if err:
            bad += 1
            print("  FAIL  compile " + (err.decode() if isinstance(err, bytes) else str(err)))
    print(f"compile check: {n - bad}/{n} files OK")
    return bad == 0


def run_scenarios(names):
    scen = ROOT / "tests" / "scenarios"
    files = sorted(scen.glob("*.lua"))
    if names:
        files = [f for f in files if any(f.stem == n or f.stem.startswith(n + "_") for n in names)]
        if not files:
            sys.exit("no scenarios match: " + ", ".join(names))
    lua = LuaRuntime(register_eval=False)
    lua.execute(
        'ROOT = ...; package.path = ROOT .. "/tests/?.lua;" .. package.path; '
        'require("sim.cc").ROOT = ROOT',
        str(ROOT),
    )
    T = lua.eval('require("sim.test")')
    load_scenario = lua.eval("function(path) local f = assert(loadfile(path)); return f() end")
    passed = failed = 0
    for f in files:
        print(f"{f.stem}:")
        try:
            load_scenario(str(f))
        except Exception as e:  # a scenario file that doesn't even load
            print(f"  FAIL  {f.name} did not load: {e}")
            failed += 1
            continue
        p, q = T.runAll("")
        passed += int(p)
        failed += int(q)
    print(f"scenarios: {passed} passed, {failed} failed")
    return failed == 0


def main(argv):
    args = [a for a in argv if not a.startswith("-")]
    ok = True
    if "--no-check" not in argv:
        ok = compile_check()
    if "--check" not in argv:
        ok = run_scenarios(args) and ok
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main(sys.argv[1:])
