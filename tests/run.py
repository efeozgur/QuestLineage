"""Runs every tests/*.lua under Lua 5.1 (no WoW client). Needs Python 3 and `pip install lupa`.
Usage: python tests/run.py [name ...]   e.g. python tests/run.py chain"""
import glob
import os
import sys

from lupa.lua51 import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
wanted = set(sys.argv[1:])
ok = bad = 0
for path in sorted(glob.glob(os.path.join("tests", "*.lua"))):
    name = os.path.splitext(os.path.basename(path))[0]
    if name == "stubs" or (wanted and name not in wanted):
        continue
    lua = LuaRuntime(unpack_returned_tuples=True)
    try:
        lua.execute(open(path, encoding="utf-8").read())
        ok += 1
        print("OK  ", path)
    except Exception as e:
        bad += 1
        print("FAIL", path, "->", str(e)[:400].replace("\n", " | "))
print("\n%d passed, %d failed" % (ok, bad))
sys.exit(1 if bad else 0)
