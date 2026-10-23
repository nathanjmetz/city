#!/usr/bin/env python3
"""Stamps the build for CI: writes scripts/build_info.gd with
BUILD and BUILT_AT (shown in the game's corner, in local time), COMMIT,
BUILT (the commit's Unix time) and
SETTINGS (a fingerprint of project.godot without its shader globals).
The desktop updater compares these with latest.json to decide whether a new
game data pack fits the installed app (scripts/shell/updater.gd).

Run: python3 tools/stamp_build.py [--globals out.json]
--globals also writes the shader globals, which an update can add at runtime.
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import time

sha = os.environ.get("GITHUB_SHA") or subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
built = int(subprocess.check_output(["git", "log", "-1", "--format=%ct"], text=True).strip())
text = open("project.godot", encoding="utf-8").read()

# Split into sections; the shader globals are left out of the fingerprint.
sections = re.split(r"(?m)^(?=\[)", text)
kept, globals_text = [], ""
for s in sections:
    if s.startswith("[shader_globals]"):
        globals_text = s
    else:
        kept.append(s)
settings = hashlib.sha256("".join(kept).strip().encode()).hexdigest()[:16]

with open("scripts/build_info.gd", "w", encoding="utf-8") as f:
    f.write('const BUILD := "%s"\n' % sha[:7])
    f.write("const BUILT_AT := %d\n" % int(time.time()))
    f.write('const COMMIT := "%s"\n' % sha)
    f.write("const BUILT := %d\n" % built)
    f.write('const SETTINGS := "%s"\n' % settings)

if "--globals" in sys.argv:
    out = {}
    # name={ "type": "float", "value": 0.0 }, possibly over several lines.
    for m in re.finditer(r'(?ms)^(\w+)=\{\s*"type":\s*"(\w+)",\s*"value":\s*(.*?)\s*\}\s*$', globals_text):
        out[m.group(1)] = {"type": m.group(2), "value": m.group(3)}
    meta = {"commit": sha, "built": built, "settings": settings, "globals": out}
    with open(sys.argv[sys.argv.index("--globals") + 1], "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)
print(open("scripts/build_info.gd").read())
