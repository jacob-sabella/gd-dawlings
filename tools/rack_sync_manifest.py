#!/usr/bin/env python3
"""Regenerates core/music/rack/modules.json from `rack --describe` and gives every engine module that no shipped
mod dresses yet a `rack_module` entry (a skin and its two orb-pad knobs) in the mod of the pinned library its DSP
comes from. Run after adding a module to the engine: tools/rack_sync_manifest.py [build/rack/rack]."""
import colorsys, hashlib, json, subprocess, sys

REPO = __file__.rsplit("/tools/", 1)[0]
BIN = sys.argv[1] if len(sys.argv) > 1 else REPO + "/build/rack/rack"
MODS = {"daisysp": REPO + "/mods/builtin/daisysp/mod.json", "mutable": REPO + "/mods/builtin/mutable/mod.json",
        "core": REPO + "/mods/builtin/core/mod.json", "airwindows": REPO + "/mods/builtin/airwindows/mod.json",
        "chimera": REPO + "/mods/builtin/chimera/mod.json"}
# Which mod a new module goes to (anything not named here goes to daisysp).
OWNER = {"voice": "chimera", "marbles": "mutable", "frames": "mutable", "spectrum": "core", "vector": "core", "meter": "core", "plasma": "core"}
TAGLINES = {}
PATTERNS = ["stripes", "checker", "dots", "wave", "bars", "zigzag"]

desc = json.loads(subprocess.check_output([BIN, "--describe"]))
open(REPO + "/core/music/rack/modules.json", "w").write(json.dumps(desc, indent=4) + "\n")
have = set()
docs = {}
for k, p in MODS.items():
    docs[k] = json.load(open(p))
    for e in docs[k]["provides"]:
        if e.get("kind") == "rack_module":
            have.add(e["type"])
tag = json.load(open(REPO + "/tools/rack_taglines.json")) if __import__("os").path.exists(REPO + "/tools/rack_taglines.json") else {}
added = []
for m in desc["modules"]:
    t = "builtin." + m["type"]
    if t in have:
        continue
    h = int(hashlib.md5(m["type"].encode()).hexdigest(), 16)
    hue = (h % 360) / 360.0
    face = colorsys.hsv_to_rgb(hue, 0.7, 0.28)
    acc = colorsys.hsv_to_rgb(hue, 0.65, 1.0)
    hexc = lambda c: "#%02X%02X%02X" % tuple(int(round(x * 255)) for x in c)
    knobs = [k["id"] for k in m["knobs"]][:2]
    entry = {"kind": "rack_module", "type": t, "title": m["title"], "group": m["group"], "blurb": m["blurb"],
             "sound": {"kind": "engine", "type": m["type"]},
             "skin": {"face": hexc(face), "accent": hexc(acc), "pattern": PATTERNS[(h >> 8) % len(PATTERNS)],
                      "tagline": tag.get(m["type"], m["title"])},
             }
    if len(knobs) == 2:  # a module with fewer than two knobs has no orb pad
        entry["pad_knobs"] = knobs
    docs[OWNER.get(m["type"], "daisysp")]["provides"].append(entry)
    added.append(m["type"])
for k, p in MODS.items():
    if k in ("daisysp", "mutable", "core", "chimera"):
        d = docs[k]
        head = [(key, d[key]) for key in d if key != "provides"]
        lines = ["{"] + ['  %s: %s,' % (json.dumps(key), json.dumps(v, ensure_ascii=False)) for key, v in head] + ['  "provides": [']
        lines += ["    " + json.dumps(e, ensure_ascii=False) + ("," if i < len(d["provides"]) - 1 else "") for i, e in enumerate(d["provides"])]
        lines += ["  ]", "}"]
        open(p, "w").write("\n".join(lines) + "\n")
print("added", len(added), ":", " ".join(added))
