#!/usr/bin/env python3
"""Compile-check every .lua file, then run the simulator scenarios.

    python3 tests/run.py                 # compile check + every scenario
    python3 tests/run.py storage         # compile check + scenarios/storage*.lua
    python3 tests/run.py --check         # compile check only
    python3 tests/run.py --no-check smelter

Needs lupa (Lua 5.2, same as CraftOS): pip install --break-system-packages -q lupa
"""
import re
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


# CraftOS runs a dofile()d file in _G, where `require` and `shell` don't exist: they live in each program's own
# environment (the shell's createShellEnv). A file that uses them has to be loaded with require(), which runs it in
# the program's environment. This catches it statically; the simulator (tests/sim/env.lua) does too at run time.
DOFILE_RE = re.compile(r"""\bdofile\s*\(?\s*["']([^"']+)["']""")
NEEDS_PROGRAM_ENV_RE = re.compile(r"(?<![\w.:])(require\s*[(\"']|shell\s*\.)")


STRING_RE = re.compile(r""""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'""")


def code_lines(p):
    """(line number, code, code with string contents blanked), comments left out of both."""
    for i, line in enumerate(p.read_text(errors="replace").splitlines(), 1):
        blank = STRING_RE.sub(lambda m: m.group(0)[0] + " " * (len(m.group(0)) - 2) + m.group(0)[0], line)
        cut = blank.find("--")
        if cut >= 0:
            line, blank = line[:cut], blank[:cut]
        yield i, line, blank


def dofile_check():
    files = [p for p in lua_files() if "tests" not in p.relative_to(ROOT).parts]
    by_name = {}
    for p in files:
        by_name.setdefault(p.name, []).append(p)
    loaded = {}
    for p in files:
        for i, line, _ in code_lines(p):
            for m in DOFILE_RE.finditer(line):
                name = m.group(1).split("/")[-1]
                loaded.setdefault(name, f"{p.relative_to(ROOT)}:{i}")
    bad = 0
    for name, where in sorted(loaded.items()):
        for p in by_name.get(name, []):
            for i, _, blank in code_lines(p):
                if NEEDS_PROGRAM_ENV_RE.search(blank):
                    bad += 1
                    print(f"  FAIL  dofile {p.relative_to(ROOT)}:{i} uses require/shell, but {where} loads it with "
                          f"dofile (no require or shell there in CraftOS): load it with require() instead")
                    break
    print(f"dofile check: {len(loaded)} dofile()d files, {bad} need require() instead")
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
        ok = dofile_check() and ok
    if "--check" not in argv:
        ok = run_scenarios(args) and ok
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main(sys.argv[1:])
