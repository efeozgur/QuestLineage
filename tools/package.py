"""Builds the release zip for CurseForge: dist/QuestLineage-<version>.zip with one folder
"QuestLineage" holding only what the game loads (toc, Lua files listed in it, Media) plus LICENSE
and README. Refuses when a file the toc lists is missing or the tests fail.
Usage: python tools/package.py [--skip-tests]"""
import os
import re
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = "QuestLineage"
os.chdir(ROOT)

toc = open(NAME + ".toc", encoding="utf-8").read()
version = (re.search(r"^## Version:\s*(\S+)", toc, re.M) or [None, "dev"])[1]
lua = [l.strip() for l in toc.splitlines() if l.strip() and not l.startswith("#")]
missing = [f for f in lua if not os.path.isfile(f)]
if missing:
    sys.exit("missing files listed in the toc: " + ", ".join(missing))
stray = sorted(set(f for f in os.listdir(".") if f.endswith(".lua")) - set(lua))
if stray:
    sys.exit("Lua files not in the toc: " + ", ".join(stray))

if "--skip-tests" not in sys.argv:
    if subprocess.call([sys.executable, os.path.join("tests", "run.py")]) != 0:
        sys.exit("tests failed: no package")

files = [NAME + ".toc", "Bindings.xml", "LICENSE", "README.md", "CHANGELOG.md"] + lua
for base, dirs, names in os.walk("Media"):
    dirs[:] = [d for d in dirs if not d.startswith((".", "__"))]
    for n in names:
        if not n.startswith("."):
            files.append(os.path.join(base, n))

os.makedirs("dist", exist_ok=True)
out = os.path.join("dist", "%s-%s.zip" % (NAME, version))
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        z.write(f, NAME + "/" + f.replace(os.sep, "/"))
print("%s: %d files, %.0f KB" % (out, len(files), os.path.getsize(out) / 1024))
