#!/usr/bin/env python3
"""Writes mods/builtin/airwindows/mod.json: one rack module per Airwindows effect.

Each effect is a *composite* (docs/mods.md 3.5): the one engine module `builtin.airwindows` with its EFFECT knob
set to that effect, its own knobs named for the effect's parameters (`airwindows.json`, from the engine) and
started at their own default values. So a patch holds `builtin.aw.galactic`, not "an AIRWINDOWS set to Galactic",
and the palette finds one by name or kind (RackFinderScreen). The text and kinds come from
`airwindows_help.json` (tools/airwindows_help.py). Run after either of those files changes; a test holds this
file to them.

    python3 tools/airwindows_mods.py
"""
import colorsys
import json
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
RACK = os.path.join(ROOT, "core", "music", "rack")
OUT = os.path.join(ROOT, "mods", "builtin", "airwindows", "mod.json")
PREFIX = "builtin.aw."
PATTERNS = ["stripes", "bars", "wave", "zigzag", "checker", "dots"]
LETTERS = "abcdefghijkl"


def type_of(effect_id):
    return PREFIX + re.sub(r"[^a-z0-9]", "_", effect_id.lower())


def hexcolour(h, s, v):
    r, g, b = colorsys.hsv_to_rgb(h, s, v)
    return "#%02X%02X%02X" % (round(r * 255), round(g * 255), round(b * 255))


def blurb_of(summary):
    text = " ".join((summary or "").split())
    return text if text else "An Airwindows effect."


def main():
    params = {e["id"]: e for e in json.load(open(os.path.join(RACK, "airwindows.json")))["effects"]}
    ids = list(params)
    help_ = json.load(open(os.path.join(RACK, "airwindows_help.json")))
    kinds = list(help_["categories"])
    entries = [{
        "kind": "rack_module", "type": "builtin.airwindows", "title": "AIRWINDOWS", "group": "Internal",
        "blurb": "The engine module every Airwindows effect is built on; use the effects themselves.",
        "sound": {"kind": "engine", "type": "airwindows"},
        "skin": {"face": "#262626", "accent": "#F2F2F2", "pattern": "stripes", "tagline": "ALL OF THEM"},
        "pad_knobs": ["a", "b"],
    }]
    taken = {("#262626", "#F2F2F2")}
    for eid in ids:
        e = params[eid]
        info = help_["effects"].get(eid, {})
        mine = [k for k in kinds if eid in help_["categories"][k]] or ["Effects"]
        k0 = kinds.index(mine[0]) if mine[0] in kinds else 0
        rank = help_["categories"][mine[0]].index(eid) if eid in help_["categories"][mine[0]] else ids.index(eid) % 20
        size = max(1, len(help_["categories"].get(mine[0], [1])))
        # A hue band for each kind, and each effect a place in its kind's band: no two skins are alike.
        hue = (k0 + 0.05 + 0.9 * rank / size) / len(kinds)
        n = min(len(e["params"]), len(LETTERS))
        knobs = {LETTERS[i]: {"to": "fx." + LETTERS[i], "label": e["params"][i]["name"].upper()} for i in range(n)}
        set_ = {"effect": round((ids.index(eid) + 0.5) / len(ids), 9)}
        for i in range(n):
            set_[LETTERS[i]] = e["params"][i]["default"]
        pads = [LETTERS[0], LETTERS[1] if n > 1 else LETTERS[0]]
        face = accent = ""
        while True:
            face = hexcolour(hue, 0.5 + 0.15 * (rank % 3) / 2, 0.19 + 0.05 * (rank % 4) / 3)
            accent = hexcolour(hue, 0.45, 1.0)
            if (face, accent) not in taken:
                break
            hue += 0.0007  # a skin of its own: nudged along until no other effect has this one
        taken.add((face, accent))
        entries.append({
            "kind": "rack_module", "type": type_of(eid), "title": e["title"].upper(), "group": "Airwindows",
            "kinds": mine,
            "blurb": blurb_of(info.get("summary")),
            "sound": {
                "kind": "composite",
                "modules": {"fx": {"type": "builtin.airwindows", "knobs": set_}},
                "cables": [],
                "ins": {"l": ["fx.l"], "r": ["fx.r"]},
                "outs": {"l": "fx.l", "r": "fx.r"},
                "knobs": knobs,
                "meter_from": "fx",
            },
            "skin": {"face": face, "accent": accent,
                     "pattern": PATTERNS[k0 % len(PATTERNS)], "tagline": mine[0].upper()},
        })
        if n > 0:
            entries[-1]["pad_knobs"] = pads
    mod = {
        "format": "dawlings.mod", "api_version": 1, "id": "builtin.airwindows", "name": "Airwindows effects",
        "version": "2.0.0", "author": "Chris Johnson (Airwindows); wrapper by dawlings",
        "description": "Every Airwindows effect as a rack module of its own, found by name or kind in the module finder.",
        "licence": {"spdx": "MIT", "copyright": "Copyright (c) 2018 Chris Johnson"},
        "source": {"kind": "submodule", "path": "vendor/airwindows", "commit": "94cb679",
                   "upstream": "https://github.com/airwindows/airwindows"},
        "groups": [{"id": "Airwindows", "title": "Airwindows", "order": 8}, {"id": "Internal", "title": "Internal", "order": 99}],
        "provides": entries,
    }
    text = json.dumps(mod, indent=1) + "\n"
    if "--check" in sys.argv:
        sys.exit(0 if os.path.exists(OUT) and open(OUT).read() == text else 1)
    with open(OUT, "w") as f:
        f.write(text)
    print("wrote %d entries to %s" % (len(entries), OUT))


if __name__ == "__main__":
    main()
