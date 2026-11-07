#!/usr/bin/env python3
"""Generates the built-in mod manifests under mods/builtin/ from the tables the game used before the
mod registry (docs/mods.md section 9, step 4).

Inputs, all read, none retyped:
  tests/fixtures/rack_legacy_tables.json   RackSkin.SKINS, RackWall.PAD_KNOBS, RackCatalogue.GROUPS and
                                           the RackPatch presets as they stood at 26b79fc. It was dumped
                                           from the live GDScript tables by a throw-away script before
                                           they were deleted; this file is their frozen form.
  core/music/rack/modules.json             the engine snapshot: type, title, group and blurb of each module.
  native/rack/modules_core.cc              which modules are built on DaisySP (a module whose class uses a
  native/rack/modules_mutable.cc           `daisysp::` name) and which on Mutable Instruments.

Outputs (rewritten in full, so the script is idempotent):
  mods/builtin/core/mod.json       the palette groups and the modules that use no third-party DSP
  mods/builtin/daisysp/mod.json    the modules built on vendor/daisysp
  mods/builtin/mutable/mod.json    the modules built on vendor/mutable-eurorack
  mods/builtin/presets/mod.json    the presets, with one patch file each under patches/

A module's type stays its bare engine name (`plaits`); the rename to `builtin.<name>` is a later,
separate slice. Usage: python3 tools/mods_from_legacy.py [--check]   (--check writes nothing and exits 1
when a file on disk differs from what would be written).
"""
import json
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LEGACY = ROOT / "tests/fixtures/rack_legacy_tables.json"
SNAPSHOT = ROOT / "core/music/rack/modules.json"
OUT = ROOT / "mods/builtin"

COMMON = {"format": "dawlings.mod", "api_version": 1, "version": "1.0.0"}

# Group titles are the ids; the order is the palette's (RackCatalogue.GROUPS).
MODS = {
    "core": {
        "id": "builtin.core", "name": "Core rack modules",
        "author": "dawlings",
        "description": "The palette groups and the rack modules that need no third-party DSP.",
        "licence": {"spdx": "MIT", "copyright": "Copyright (c) 2026 Jacob Sabella"},
        "source": {"kind": "in_tree", "path": "native/rack"},
    },
    "daisysp": {
        "id": "builtin.daisysp", "name": "DaisySP modules",
        "author": "Electrosmith (DaisySP); wrapper by dawlings",
        "description": "Rack modules built on the DaisySP DSP library.",
        "licence": {"spdx": "MIT", "copyright": "Copyright (c) 2020 Electrosmith, Corp."},
        "source": {"kind": "submodule", "path": "vendor/daisysp", "commit": "2c72eaf",
                   "upstream": "https://github.com/electro-smith/DaisySP"},
    },
    "mutable": {
        "id": "builtin.mutable", "name": "Mutable Instruments modules",
        "author": "Emilie Gillet (Mutable Instruments); wrapper by dawlings",
        "licence": {"spdx": "MIT", "copyright": "Copyright Emilie Gillet"},
        "source": {"kind": "submodule", "path": "vendor/mutable-eurorack", "commit": "f4cfa76",
                   "upstream": "https://github.com/pichenettes/eurorack"},
    },
    "presets": {
        "id": "builtin.presets", "name": "Rack presets",
        "author": "dawlings",
        "description": "The ready-made patches of the rack's PRESETS group.",
        "licence": {"spdx": "MIT", "copyright": "Copyright (c) 2026 Jacob Sabella"},
        "source": {"kind": "data"},
        "requires": [{"mod": "builtin.core", "min": "1.0.0"}, {"mod": "builtin.daisysp", "min": "1.0.0"},
                     {"mod": "builtin.mutable", "min": "1.0.0"}],
    },
}


def f32(x):
    """x rounded to a 32-bit float, as Godot's Color holds it."""
    return struct.unpack("f", struct.pack("f", x))[0]


def hexcolour(c):
    """A float [r, g, b] as #RRGGBB, exactly as Godot's Color.to_html writes it: the product with 255 is
    taken in 32-bit floats and rounded half away from zero, so 0.9 is E6 there and not E5."""
    return "#" + "".join("%02X" % int(f32(f32(c_) * 255.0) + 0.5) for c_ in c)


def registrations(path):
    """{type: True if its code uses `daisysp::`} for each `static Registrar r_<type>` in a C++ file."""
    uses, out = False, {}
    for line in path.read_text().splitlines():
        m = re.match(r"static Registrar r_(\w+)\(", line)
        if m:
            out[m.group(1)] = uses or "daisysp::" in line
            uses = False
        elif "daisysp::" in line:
            uses = True
    return out


def owner_of(module_type, core, mutable):
    if module_type in mutable:
        return "mutable"
    if module_type in core:
        return "daisysp" if core[module_type] else "core"
    sys.exit("no C++ registration for module %s" % module_type)


def one_line(v):
    return json.dumps(v, ensure_ascii=False)


def manifest_text(head, groups, entries):
    """mod.json text: the head fields indented, one entry per line."""
    lines = ["{"]
    for k, v in head.items():
        lines.append('  %s: %s,' % (one_line(k), one_line(v)))
    if groups:
        lines.append('  "groups": [')
        lines.append(",\n".join("    " + one_line(g) for g in groups))
        lines.append("  ],")
    lines.append('  "provides": [')
    lines.append(",\n".join("    " + one_line(e) for e in entries))
    lines.append("  ]")
    lines.append("}")
    return "\n".join(lines) + "\n"


def patch_text(patch):
    """A preset patch, one module and one cable per line."""
    mods = ",\n".join("    %s: %s" % (one_line(i), one_line(patch["modules"][i])) for i in sorted(patch["modules"]))
    cables = ",\n".join("    " + one_line(c) for c in patch["cables"])
    return '{\n  "modules": {\n%s\n  },\n  "cables": [\n%s\n  ]\n}\n' % (mods, cables)


def build():
    legacy = json.loads(LEGACY.read_text())
    snapshot = json.loads(SNAPSHOT.read_text())["modules"]
    core = registrations(ROOT / "native/rack/modules_core.cc")
    mutable = registrations(ROOT / "native/rack/modules_mutable.cc")
    files = {}
    entries = {k: [] for k in MODS}
    for m in snapshot:
        t = m["type"]
        s = legacy["skins"][t]
        e = {"kind": "rack_module", "type": t, "title": m["title"], "group": m["group"], "blurb": m["blurb"],
             "sound": {"kind": "engine", "type": t},
             "skin": {"face": hexcolour(s[0]), "accent": hexcolour(s[1]), "pattern": s[2], "tagline": s[3]}}
        if t in legacy["pad_knobs"]:
            e["pad_knobs"] = legacy["pad_knobs"][t]
        entries[owner_of(t, core, mutable)].append(e)
    stray = set(legacy["skins"]) - {m["type"] for m in snapshot}
    if stray or set(legacy["pad_knobs"]) - {m["type"] for m in snapshot}:
        sys.exit("the legacy tables name modules the engine does not have: %s" % sorted(stray))
    groups = [{"id": g, "title": g, "order": i + 1} for i, g in enumerate(legacy["groups"])]
    for key, mod in MODS.items():
        head = {**COMMON, **{k: v for k, v in mod.items()}}
        # Field order of the existing file: format, api_version, id, name, version, author, ...
        ordered = {k: head[k] for k in ["format", "api_version", "id", "name", "version", "author", "description",
                                         "licence", "source", "requires"] if k in head}
        if key == "presets":
            pres = []
            for p in legacy["presets"]:
                rel = "patches/%s.patch.json" % p["name"]
                files[OUT / key / rel] = patch_text(p["patch"])
                pres.append({"kind": "rack_preset", "name": p["name"], "title": p["title"], "patch": {"file": rel}})
            files[OUT / key / "mod.json"] = manifest_text(ordered, [], pres)
        else:
            files[OUT / key / "mod.json"] = manifest_text(ordered, groups if key == "core" else [], entries[key])
    return files


def main():
    files = build()
    stale = [p for p, text in files.items() if not p.exists() or p.read_text() != text]
    if "--check" in sys.argv:
        for p in stale:
            print("differs:", p.relative_to(ROOT))
        sys.exit(1 if stale else 0)
    for p, text in files.items():
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
    print("wrote %d files (%d changed)" % (len(files), len(stale)))


if __name__ == "__main__":
    main()
