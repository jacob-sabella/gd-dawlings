#!/usr/bin/env python3
"""Reads Airwindopedia.txt (Chris Johnson's own descriptions, MIT, in vendor/airwindows) into
core/music/rack/airwindows_help.json: each effect's one-line summary, its text and its categories.

    tools/airwindows_help.py            # writes the file
    tools/airwindows_help.py --check    # exits 1 if the committed file is not what the pinned source gives

An entry in the source starts with a line `############ Name is ...`; its text runs to the next one. The
categories are the `Category: A, B, C,` lines near the top. Long entries (several blog posts joined) are cut
at a paragraph, with a note, to keep the committed file small; the full text is in the submodule.
"""
import json
import os
import re
import subprocess
import sys

root = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sub = os.path.join(root, "vendor", "airwindows")
OUT = os.path.join(root, "core", "music", "rack", "airwindows_help.json")
CAP = 1500

lines = open(os.path.join(sub, "Airwindopedia.txt"), encoding="utf-8", errors="replace").read().split("\n")

cats = {}
i = next(n for n, l in enumerate(lines) if l.strip() == "# Categories") + 1
while i < len(lines) and not lines[i].startswith("############"):
    m = re.match(r"^([A-Za-z][A-Za-z -]*): (.+)$", lines[i])
    if m:
        cats[m.group(1)] = [w.strip() for w in m.group(2).split(",") if w.strip()]
    elif lines[i].startswith("# "):
        break
    i += 1

effects = {}
cur = None
for l in lines[i:]:
    m = re.match(r"^############\s+(\S+)\s*(.*)$", l)
    if m:
        cur = m.group(1)
        rest = m.group(2)
        effects[cur] = {"summary": (cur + " " + rest).strip(), "body": []}
    elif cur is not None:
        effects[cur]["body"].append(l)

out = {}
for name, e in effects.items():
    paras = [p.strip() for p in re.split(r"\n\s*\n", "\n".join(e["body"])) if p.strip()]
    text, cut = [], False
    n = 0
    for p in paras:
        if n + len(p) > CAP and text:
            cut = True
            break
        text.append(p)
        n += len(p)
    out[name] = {"summary": e["summary"], "text": text, "more": cut,
                 "categories": sorted(c for c, ids in cats.items() if name in ids)}
commit = subprocess.run(["git", "-C", sub, "rev-parse", "--short=7", "HEAD"], capture_output=True, text=True).stdout.strip()
doc = {"source": "airwindows/airwindows Airwindopedia.txt (MIT, Chris Johnson) at " + commit,
       "categories": {c: [x for x in ids if x in out] for c, ids in sorted(cats.items())}, "effects": dict(sorted(out.items()))}
text = json.dumps(doc, indent=1, ensure_ascii=False) + "\n"
if "--check" in sys.argv:
    sys.exit(0 if open(OUT, encoding="utf-8").read() == text else 1)
open(OUT, "w", encoding="utf-8").write(text)
print(len(out), "entries,", len(cats), "categories,", len(text) // 1024, "KB", file=sys.stderr)
