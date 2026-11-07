# Mods: manifest, registry and save format

Status: **DESIGN, draft for owner review** (2026-11-07). Nothing here is built. It is queue item 2
of `docs/refactor_loop.md` and feeds items 3-5. "Today" claims cite `docs/refactor_state_map.md`
(SM) by section or file:line. Companion: `docs/layouts.md` (rooms and pieces).

## 1. Purpose and terms

Today a rack module is spread over twelve places (SM 1.7) and a DAW plugin is a string from
`fx_choices` (SM 1.5). The goal is: adding one means adding a folder.

| Term | Meaning |
|---|---|
| **Mod** | A folder (or later an archive) with one `mod.json` and the files it names. The unit of install, licence, version and failure. |
| **Entry** | One thing a mod provides (`provides[]`): a rack module, a plugin overlay, a preset, a skin, a piece. A mod has one or more. |
| **Manifest** | `mod.json`: the mod's identity, licence, source pin, requirements and its entries. Pure data. |
| **Registry** | `ModRegistry`: scans roots, validates manifests, holds the resulting entries and the list of problems. The only place the game asks "what modules exist". |
| **Binding** | The link from an entry to something that already exists in the game: an engine module type (`sound.engine.type`), a scanned plugin (`plugin.id`), existing modules (composite). A mod never brings code; it binds. |
| **Skin** | How a module looks on the rack: face and accent colour, pattern, tagline (today `RackSkin.SKINS`, `rack_skin.gd:19`), optionally a decorative model. |
| **Unavailable plate** | What a module, plugin or piece looks like when its mod is missing or broken: a plain labelled plate that keeps its place and its connections. Never a crash, never a silent deletion. |

Rules fixed by the owner (2026-11-07, `docs/refactor_loop.md` "Decisions"):

1. **Data-only plus pinned vendor DSP.** A user mod is a manifest, skin/model and a patch that uses
   DSP already compiled into the game. New native DSP comes only from pinned submodules or versioned
   binaries shipped with the game. No user-supplied native code (a reserved, undesigned extension
   point is marked in 4.2).
2. **A patch is a file.** It is saved and loaded; a missing mod shows an unavailable plate and keeps
   its place and cables.
3. **A guest without the host's mod** sees an unavailable plate naming the mod and still hears the
   host's sound. No transfer, no refusal.
4. The 800-line limit applies to `studio.gd`, `venue.gd` and every file the refactor touches.

## 2. Where things live

```mermaid
flowchart LR
  subgraph shipped[res://mods/builtin/ in-tree, exported]
    B1[builtin.core mod.json] --- B2[builtin.mutable mod.json]
    B3[builtin.daisysp mod.json]
  end
  subgraph user[user://mods/ per player]
    U1[dawlings.sample.pluck/mod.json]
  end
  V[vendor/ submodules: source only, never read by the game] -.pinned by.-> B2
  E[(rack engine build: --describe)] -.snapshot core/music/rack/modules.json.-> R
  shipped --> R[ModRegistry]
  user --> R
  S[dawkit plugin scan] --> R
  R --> W[RackWall, RackPatch, RackVoice, PluginTablet]
```

Manifests for pinned third-party code are **in-tree under `res://mods/builtin/`**, not inside
`vendor/`: `vendor/` is a submodule checkout we may not edit and it is `.gdignore`d, so it is not
exported (SM 1.1). The manifest points at the submodule (`source.path` + `commit`). This differs from
the brief's wording "discovers mods from `vendor/`"; open question 1.

## 3. The manifest

### 3.1 Schema (JSON Schema 2020-12, abridged to what is checked)

Strings in `provides[]` entries follow the entry kind. Unknown top-level keys are ignored with a
warning (forward compatibility); unknown keys inside an entry of a known kind are ignored too.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "dawlings mod manifest, api_version 1",
  "type": "object",
  "required": ["format", "api_version", "id", "name", "version", "licence", "source", "provides"],
  "properties": {
    "format": {"const": "dawlings.mod"},
    "api_version": {"type": "integer", "minimum": 1},
    "id": {"type": "string", "pattern": "^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)*$", "maxLength": 64},
    "name": {"type": "string", "maxLength": 40},
    "version": {"type": "string", "pattern": "^\\d+\\.\\d+\\.\\d+$"},
    "min_game_version": {"type": "string", "pattern": "^\\d+\\.\\d+\\.\\d+$"},
    "author": {"type": "string", "maxLength": 80},
    "description": {"type": "string", "maxLength": 400},
    "licence": {"type": "object", "required": ["spdx"], "properties": {"spdx": {"type": "string"}, "copyright": {"type": "string"}, "file": {"type": "string", "description": "licence text, relative to the mod folder"}, "redistributed": {"type": "boolean", "default": true}}},
    "source": {"oneOf": [{"properties": {"kind": {"const": "submodule"}, "path": {"type": "string"}, "commit": {"type": "string", "pattern": "^[0-9a-f]{7,40}$"}, "upstream": {"type": "string"}}, "required": ["kind", "path", "commit", "upstream"]}, {"properties": {"kind": {"const": "binary"}, "file": {"type": "string"}, "version": {"type": "string"}, "sha256": {"type": "string", "pattern": "^[0-9a-f]{64}$"}, "platforms": {"type": "array", "items": {"type": "string"}}, "upstream": {"type": "string"}}, "required": ["kind", "file", "version", "sha256", "upstream"]}, {"properties": {"kind": {"const": "in_tree"}, "path": {"type": "string"}}, "required": ["kind", "path"]}, {"properties": {"kind": {"const": "data"}}, "required": ["kind"]}, {"properties": {"kind": {"const": "user_installed"}}, "required": ["kind"]}]},
    "requires": {"type": "array", "items": {"type": "object", "required": ["mod"], "properties": {"mod": {"type": "string"}, "min": {"type": "string"}, "max": {"type": "string"}}}},
    "groups": {"type": "array", "items": {"type": "object", "required": ["id", "title", "order"], "properties": {"id": {"type": "string"}, "title": {"type": "string"}, "order": {"type": "integer"}}}},
    "provides": {"type": "array", "minItems": 1, "items": {"$ref": "#/$defs/entry"}}
  },
  "$defs": {
    "entry": {"type": "object", "required": ["kind"], "properties": {"kind": {"enum": ["rack_module", "rack_preset", "plugin", "skin", "piece"]}}}
  }
}
```

The per-kind field tables below are normative; `mods/mod.schema.json` (written in migration step 1)
is the machine form and the parser's test fixture.

### 3.2 Field reference

Required (**R**) or optional (**O**).

Top level: as the schema. `format`, `api_version`, `id`, `name`, `version`, `licence.spdx`, `source`,
`provides` are R. `min_game_version` is O (default: any); `requires` O; `groups` O (only
`builtin.core` declares the seven today: Source, Voice, Control, Filter, Shape, Time, Mix,
`rack_catalogue.gd:8`).

`rack_module`:

| Field | R/O | Meaning |
|---|---|---|
| `type` | R | The id patches use. Builtin mods are named `builtin.<name>` (`builtin.plaits`); every other mod is namespaced `<mod id>.<name>`. |
| `title`, `group`, `blurb` | R | Plate title, palette group, tooltip. For `engine` modules `title`/`group`/`blurb` default to the engine's `--describe` values. |
| `sound` | R | `{"kind":"engine","type":"plaits"}` or `{"kind":"composite", ...}` (4.1). Any other kind is rejected (4.2). |
| `interface` | (none) | The interface lives in `sound`: for `composite`, `sound.ins`, `sound.outs` and `sound.knobs` (3.5); for `engine` modules it is **not** repeated and `sound.ins/outs/knobs` are rejected (`bad_schema`): it comes from the engine (8). The parser has no separate `interface` key. |
| `skin` | R | `face`, `accent` (`#RRGGBB`), `pattern`, `tagline`. Today's four-tuple. |
| `pad_knobs` | O | The two knob ids of the orb pad (`rack_wall.gd:114`). |
| `face` | O | `{"kind":"standard"}` (default) or a builtin custom face: `out`, `scope`, `seq` (today's `rack_wall.gd:713,738,778`). User mods may only use `standard`. May add `model`. |
| `model` | O | `{"glb":"models/x.glb","slot":"front"}`: a decorative mesh mounted on the plate. Jacks and knobs are always generated from the interface, so a model cannot break interaction. |
| `mood` | O | `{"accent":"#RRGGBB","reacts_to":"level"|"hit"|"none"}`: how the modular room's lights treat this module (today `ModularAnnex.show_levels`, all modules alike). |
| `port_signals` | O | `{"portname":"gate"|"audio"|"cv"}` overrides of the cable colour lists (`rack_skin.gd:124-126`), which today silently default new names to CV. |

`rack_preset`: `name` R (unique), `title` R, `patch` R (an inline patch in the file format of 6.1, or
`{"file":"presets/x.patch.json"}`). Replaces `RackPatch.preset()` (30 hand-coded presets,
`rack_patch.gd:22-345`).

`plugin`: `plugin.format` R (`clap`|`vst3`|`lv2`), `plugin.id` R, `display` O (skin, model,
`first_params`, labels). Overlay on a plugin the user has (4.3).

`skin`: `for` R (a module `type`), then `skin` R. Lets a skin pack re-skin another mod's module.

`piece`: defined in `docs/layouts.md` section 4; the manifest only carries it.

### 3.3 Worked example: Plaits (an existing rack module)

How today's pieces map onto fields:

| Today | Where it goes |
|---|---|
| `modules.json` entry `type, title, group, blurb` (`core/music/rack/modules.json`) | `type`, `title`, `group`, `blurb` |
| `ins`, `outs`, `knobs[]` in the same entry | **not copied**: read from the engine snapshot by `sound.type`. The engine stays the source of truth. |
| C++ module `r_plaits` (`native/rack/modules_mutable.cc:72`) | `sound.type: "plaits"`; the C++ stays |
| Build globs for `plaits/dsp`, `stmlib` (`tools/rack_build.sh`) | `source` of the mod: submodule `vendor/mutable-eurorack` @ `f4cfa76` |
| `RackSkin.SKINS["plaits"]` = `[Color(0.26,0.12,0.28), Color(1,0.55,1), &"checker", "ONE OF 16"]` (`rack_skin.gd:45`) | `skin` (hex: 0.26,0.12,0.28 -> `#421F47`; 1,0.55,1 -> `#FF8CFF`) |
| `PAD_KNOBS["plaits"] = ["harm","timbre"]` (`rack_wall.gd:114`) | `pad_knobs` |
| Presets naming `plaits` (`rack_patch.gd:52,154,224,306`) | stay presets, in `builtin.core`'s preset entries, which `requires` `builtin.mutable` |
| `THIRD_PARTY_NOTICES.md` row | generated from `licence` + `source` (3.6) |

```json
{
  "format": "dawlings.mod",
  "api_version": 1,
  "id": "builtin.mutable",
  "name": "Mutable Instruments modules",
  "version": "1.0.0",
  "author": "Emilie Gillet (Mutable Instruments); wrapper by dawlings",
  "licence": {"spdx": "MIT", "copyright": "Copyright Emilie Gillet"},
  "source": {
    "kind": "submodule",
    "path": "vendor/mutable-eurorack",
    "commit": "f4cfa76",
    "upstream": "https://github.com/pichenettes/eurorack"
  },
  "provides": [
    {"kind": "rack_module", "type": "plaits", "title": "PLAITS", "group": "Voice", "blurb": "Mutable Instruments' macro oscillator: 24 engines from virtual analogue to modal, granular, drums and speech.", "sound": {"kind": "engine", "type": "plaits"}, "skin": {"face": "#421F47", "accent": "#FF8CFF", "pattern": "checker", "tagline": "ONE OF 16"}, "pad_knobs": ["harm", "timbre"]}
  ]
}
```

The real file lists `rings`, `reverb` and `clouds` the same way (`modules_mutable.cc:119,146,198`).

### 3.4 Worked example: a DAW plugin entry (CLAP via dawkit)

A plugin is a file on the user's disk that `PluginCatalogue` already scans (`plugin_catalogue.gd`).
The manifest does not install it; it says how the game should present it. A scanned plugin with no
manifest still appears, as a generic `RackUnit` (SM 1.5).

```json
{
  "format": "dawlings.mod",
  "api_version": 1,
  "id": "user.surge_xt_look",
  "name": "Surge XT, dressed",
  "version": "0.1.0",
  "min_game_version": "0.0.14",
  "licence": {"spdx": "CC0-1.0", "redistributed": false},
  "source": {"kind": "user_installed"},
  "provides": [
    {"kind": "plugin", "plugin": {"format": "clap", "id": "org.surge-synth-team.surge-xt"}, "display": {"title": "SURGE XT", "skin": {"face": "#1A2433", "accent": "#5BC0FF", "pattern": "bars", "tagline": "HYBRID"}, "first_params": [0, 1, 2, 3], "param_key": "index"}}
  ]
}
```

The CLAP id is the one the plugin reports; verify with the scan on install. `first_params` orders the
12-knob tablet pages (`plugin_tablet.gd`); today they are in the plugin's own order.

### 3.5 Worked example: the proof mod (pure data, composite)

`dawlings.sample.pluck` is a composite module built from three existing modules (`plaits`, `env`,
`vca`, ports and knobs as in `modules.json`), plus a skin and a preset. No engine change, no code. It
lives in the repo as `mods_examples/dawlings.sample.pluck/` (not exported) and the proof test copies
it into a temporary user mods folder (section 10).

```json
{
  "format": "dawlings.mod",
  "api_version": 1,
  "id": "dawlings.sample.pluck",
  "name": "Pluck (sample mod)",
  "version": "0.1.0",
  "min_game_version": "0.0.14",
  "author": "dawlings",
  "description": "A plucked voice: Plaits, an envelope and a VCA in one plate.",
  "licence": {"spdx": "CC0-1.0"},
  "source": {"kind": "data"},
  "requires": [{"mod": "builtin.mutable", "min": "1.0.0"}, {"mod": "builtin.core", "min": "1.0.0"}],
  "provides": [
    {"kind": "rack_module", "type": "dawlings.sample.pluck", "title": "PLUCK", "group": "Voice", "blurb": "One note in, one pluck out: Plaits through a short envelope.", "sound": {"kind": "composite", "modules": {"osc": {"type": "plaits", "knobs": {"engine": 0.35, "harm": 0.4}}, "env": {"type": "env", "knobs": {"a": 0.0, "d": 0.25, "s": 0.0, "r": 0.2}}, "amp": {"type": "vca"}}, "cables": [["env.out", "amp.cv"], ["osc.out", "amp.in"]], "ins": {"pitch": ["osc.pitch"], "gate": ["env.gate", "osc.trig"]}, "outs": {"out": "amp.out"}, "knobs": {"timbre": {"to": "osc.timbre", "label": "TIMBRE"}, "decay": {"to": "env.d", "label": "DECAY"}}, "meter_from": "amp"}, "skin": {"face": "#1E2A1A", "accent": "#E6FF6A", "pattern": "dots", "tagline": "PLUCK IT"}, "pad_knobs": ["timbre", "decay"]},
    {"kind": "rack_preset", "name": "pluck_demo", "title": "Pluck demo", "patch": {"modules": {"keys": {"type": "keys", "at": [0, 0], "knobs": {}}, "pl": {"type": "dawlings.sample.pluck", "at": [1, 0], "knobs": {"decay": 0.4}}, "out": {"type": "out", "at": [3, 0], "knobs": {}}}, "cables": [["keys.pitch", "pl.pitch"], ["keys.gate", "pl.gate"], ["pl.out", "out.l"], ["pl.out", "out.r"]]}}
  ]
}
```

Expansion (pure GDScript, in `RackPatch.lines`): an instance `pl` becomes engine modules `pl~osc`,
`pl~env`, `pl~amp` (`~` is not a valid instance-id character, so ids cannot collide) with the inner
cables, and outer cables to `pl.pitch` fan out to the inner jacks. Knob values are 0..1 positions,
as in patch files. Depth limit 3, cycles rejected, inner types must exist (else the whole entry is
unavailable). The plate's width comes from the interface counts through `RackLayout.width_of`
(`rack_layout.gd`), unchanged.

### 3.6 Versioning, compatibility, licences, pins

* `api_version` (integer) is the manifest schema major. The game supports a range
  (`ModRegistry.API_MIN..API_MAX`, 1..1 now). Outside it: `api_version_unsupported`, mod not loaded.
  Within a major, only optional fields are added.
* `min_game_version` is compared with `VERSION` (0.0.14 today). Newer than the game:
  `game_too_old`. `version` is the mod's own semver; `requires.min/max` bound dependencies.
* **Licence.** `licence.spdx` is required. Shipped (in-tree) mods must be on an allow list: MIT, BSD-2/3,
  ISC, Apache-2.0, CC0-1.0, CC-BY-4.0 (the loop rule is "MIT-style only"); `tools/mods_notices.py`
  fails otherwise. `licence.file` is copied beside the manifest when the mod's licence demands it.
  User mods may carry any licence (shown in the mods screen); `redistributed: false` marks code we do
  not ship.
* **Notices.** `tools/mods_notices.py` rewrites the table in `THIRD_PARTY_NOTICES.md` between
  `<!-- mods:begin -->` and `<!-- mods:end -->` from every in-tree manifest (id, upstream, pin, SPDX,
  copyright). `--check` fails CI when the table is stale. The prose paragraph about stmlib stays by hand.
* **Pins.** `submodule`: a test compares `commit` with `git ls-tree HEAD <path>`; a mismatch fails
  the suite, so a manifest cannot drift from `.gitmodules`. `binary`: the loader checks `sha256`
  once per file (cached by size + mtime); a mismatch is `binary_hash_mismatch` and the entry is
  unavailable. `in_tree` is our own code (`native/rack/modules_core.cc`); `data` has nothing to pin.

## 4. How mods are represented in the game

| Aspect | Rack module | Plugin | Preset / skin |
|---|---|---|---|
| Sound source | `sound`: `engine` (existing C++ type) or `composite` | the plugin itself, hosted by dawkit (`HostedPlugins`) or Reaper | none |
| Skin | `skin` on the plate (`RackWall._build_module`, `rack_wall.gd:656`) | `display.skin` on the `RackUnit` and tablet | `skin` entry replaces a module's |
| Model | optional decorative `.glb` on the plate | optional, on the unit | none |
| Mood hook | `mood`, read by `ModularAnnex` | none | none |
| Unavailable | plate with the mod name (5) | slot kept in the chain, unit shows "unavailable" | the preset button is greyed with the reason |

### 4.1 Composite

Defined in 3.5. `sound.kind: "composite"` is the only way a user mod makes a new sound.

### 4.2 Reserved extension point (later, opt-in, not designed)

`sound.kind` is an enum. The value `"native_plugin"` is **reserved**: the parser recognises it, reports
`unsupported_sound_kind` and loads nothing. No loader, ABI, sandbox or signing is designed here.
Enabling it needs a separate owner decision and design.

### 4.3 Plugins

The registry never replaces `PluginCatalogue` (the scanner, `user://plugin_scan.json`). Resolution:
scanned plugin -> optional `plugin` entry matched on `(format, id)` -> `display`. A chain slot saved
in a song whose plugin is not found is shown as unavailable and keeps its place (the chain already
keys slots by name, `LayoutProfile.tablets`). Scope: the built-in backend (`GodotBackend`). Under
Reaper the plugin is Reaper's; entries only supply a look (open question 6).

## 5. Discovery, order, collisions, failures

**Roots**, in order:

1. `res://mods/builtin/` (shipped; `builtin.*` ids only).
2. `DataHome.dir("mods")` = `user://mods/` (per player).
3. `$DAWLINGS_MODS` (colon-separated; tests and development).

`DataHome` today provides only `migrate()` for the old `reaper-3d` folder (`core/data_home.gd`); it has
no path helpers. Step 2 adds `static func dir(kind: String) -> String` (creates
`user://<kind>/` on demand) and the same helper serves layouts and patches.

**Order.** Roots in the order above; inside a root, folder names sorted. A mod is dependency-sorted
after the mods it `requires`. **Collisions.** A mod `id` seen twice: the first wins, the later is
`id_collision`. An entry `type` seen twice: the first wins, the later entry alone is dropped with
`type_collision` (the mod's other entries stay). `builtin.*` ids and un-namespaced types are reserved
to root 1; a user mod using them is `reserved_id`.

**Failure modes.** A problem is a `ModProblem {code, mod, entry, message, severity}`. The registry
never throws; every failure leaves the game running.

| Code | Cause | User sees |
|---|---|---|
| `no_manifest`, `bad_json`, `bad_schema` | missing/invalid `mod.json` | MODS screen lists the folder with the parser's message; nothing else changes |
| `api_version_unsupported`, `game_too_old` | version gates | listed "needs a newer game" / "made for a newer mod format" |
| `id_collision`, `type_collision`, `reserved_id` | duplicates | listed; the first mod works |
| `missing_dependency`, `dependency_cycle` | `requires` | mod and its entries unavailable; plates name the missing mod |
| `missing_file` | skin/model/patch file not found | entry loads without the file (model skipped, preset greyed); warning |
| `bad_model` | glb fails to import, external URIs, over size (2 MB) or triangle (20k) caps | entry loads without the model; warning |
| `engine_type_missing` | `sound.type` not in the engine snapshot | unavailable plate "needs engine module X" |
| `engine_unavailable` | no built engine (Windows, Quest, CI) | modules draw normally, the room is silent, as today (SM 1.2) |
| `snapshot_stale` | snapshot differs from the live `--describe` | warning in the log; live description wins |
| `binary_hash_mismatch`, `unsupported_platform` | pinned binary altered or not for this OS | entry unavailable |
| `composite_invalid` | unknown inner type, cycle, depth > 3, bad jack | entry unavailable, reason shown |
| `unsupported_sound_kind` | reserved or unknown `sound.kind` | entry unavailable |
| `licence_missing` | no `licence.spdx` | `bad_schema` |
| `plugin_not_found` | `plugin` entry whose plugin is not scanned | listed as "plugin not installed"; no effect on the game |
| `unknown_group` | module group not declared | placed in "Other"; warning |
| `unknown_key` | top-level key the format does not define | ignored; warning (3.1: forward compatibility) |

On start the game shows one toast ("2 mods could not be loaded: see MODS") if any `error` problem
exists, and writes all problems to the log. The MODS screen (a plate in the modular room, built in
step 8) lists mods, versions, licences and problems. A mod removed after a patch used it is not a
load error: it is handled by the patch (6).

## 6. Patch files, room row, guests

### 6.1 Patch file

A patch is the dictionary `RackPatch` already uses (SM 1.2), versioned, written to disk. Today it is
never saved (SM 1.6). New: one function pair `RackPatch.to_dict()/from_dict()` shared by the file
and the room row.

```json
{
  "format": "dawlings.rack-patch",
  "version": 2,
  "saved_with": "0.0.14",
  "title": "Pluck demo",
  "track": 0,
  "modules": {
    "keys": {"type": "keys", "at": [0, 0], "w": 3, "knobs": {}},
    "pl": {"type": "dawlings.sample.pluck", "at": [1, 0], "w": 4, "knobs": {"decay": 0.4}},
    "out": {"type": "out", "at": [3, 0], "w": 2, "knobs": {}}
  },
  "cables": [["keys.pitch", "pl.pitch"], ["keys.gate", "pl.gate"], ["pl.out", "out.l"], ["pl.out", "out.r"]],
  "uses": {"dawlings.sample.pluck": {"mod": "dawlings.sample.pluck", "version": "0.1.0", "title": "PLUCK"}}
}
```

* `w` (column width) is new: it is stored so a layout does not depend on the catalogue (today
  `RackLayout.width_of` computes it). Version 1 patches (no `format`) load; `w` is computed.
* `uses` maps each type in the patch to the mod that provided it, written by whoever saves. It is
  how a machine without the mod can still name it.
* Locations: `user://patches/_current.patch.json` (autosave by the host, debounced with the room
  publish, `_publish_room_soon`), `user://patches/<slug>.patch.json` (named saves). The host loads
  `_current` at start in place of the hard-coded `keys_voice` (`studio.gd:264`); in a joined session the room
  row wins and a guest never writes the host's file. Writes are atomic (temp + rename) and keep one
  `.bak`.
* Caps stay: `MAX_MODULES` 64, `MAX_CABLES` 160, file 256 kB.

### 6.2 Sanitise keeps what it cannot show

Today `RackPatch.sanitize` drops a module whose type the catalogue lacks (`rack_patch.gd:568-590`,
SM coupling 4), so the host erases a missing mod's modules the first time it sanitises. New contract:

* **Loaded data** (a file, a room row, a preset): a module of unknown type is kept as
  `{type, at, w, knobs}` verbatim and flagged `missing` in memory (not saved as a field). Its knob values
  are kept as raw floats. Cables touching it are kept.
* **New additions** (`ask_rack` `add`): an unknown type is refused, because nobody can see what they
  are adding. Moves and removal of a missing module are allowed.
* `RackPatch.lines()` skips missing modules and cables touching them; the engine never hears them. A
  mod that returns plays again with its knobs and cables intact.
* A cable whose port no longer exists on a returned mod (the mod changed) is kept as a **dangling**
  cable: drawn as a red stub, listed in the problem list, removed only by the player.
* Everything else `sanitize` does (ids, bounds, `out` singleton, limits) is unchanged.

### 6.3 Room row and the guest

The `rack` row stays `{patch, track}` (`studio.gd:2446`, `Session.ask_room` validation
`session.gd:1686`); the patch inside gains `uses`. The host fills `uses` from its registry when it
publishes. A guest's registry resolves `type` locally; if absent, the plate reads
"PLUCK (dawlings.sample.pluck 0.1.0): not installed" from `uses`. The guest hears the host's sound
exactly as today (the host runs the engine and feeds the track, SM 1.6); nothing is transferred. A guest
cannot turn knobs on a missing module (nothing to drag) but may move or remove it by the usual
`ask_rack` verbs, which the host validates. The guest's own prediction path (`_rack_apply`) uses the
same `sanitize`, so predictions do not drop modules the host kept.

## 7. The registry API (GDScript)

All in `core/mods/`. Instance-based with one shared instance, so tests build their own.

```
class_name ModRegistry extends RefCounted
  static var current: ModRegistry                       # set at startup; tests replace it
  const API_MIN := 1; const API_MAX := 1
  signal changed()                                      # after scan() or reload()
  signal problem_found(problem: ModProblem)
  func scan(roots: Array[String]) -> void               # idempotent; never throws
  func reload() -> void                                 # re-scan the same roots (MODS screen)
  func mods() -> Array[ModManifest]
  func mod(id: String) -> ModManifest                   # null if absent
  func problems() -> Array[ModProblem]
  func module(type: String) -> RackModuleDef            # null if unknown
  func has_module(type: String) -> bool
  func module_types() -> Array[String]                  # palette order
  func groups() -> Array[Dictionary]                    # ordered, replaces RackCatalogue.GROUPS
  func presets() -> Array[RackPresetDef]
  func plugin_display(format: String, id: String) -> PluginDisplayDef
  func uses(patch: Dictionary) -> Dictionary            # fills the `uses` map
class_name ModManifest        # parsed + validated mod.json: id, version, licence, source, entries, status
class_name ModProblem         # {code, mod, entry, message, severity}
class_name RackModuleDef      # type, title, group, blurb, ins, outs, knobs, skin, pad_knobs, face, model,
                              # mood, sound (engine type | composite), status (&"ok"|&"unavailable"), reason
class_name RackPresetDef  /  PluginDisplayDef  /  SkinDef
```

What it replaces: `RackCatalogue.types()/spec()/in_group()/knob()` become one-line forwards to
`ModRegistry.current` (so the ~40 call sites do not move in one slice) and are deleted in migration
step 11; `RackSkin.SKINS`/`of()` and `RackWall.PAD_KNOBS` are read from `RackModuleDef`;
`RackPatch.preset()` reads `RackPresetDef`; `RackMood.MOODS` (per venue) moves with layouts.

**Interface for engine modules.** A `RackModuleDef` for `sound.kind == "engine"` takes
`ins/outs/knobs` from the engine snapshot (section 8), so the interface exists in
exactly one place.

## 8. The native engine and the registry

New native DSP is not user-supplied, so the C++ side stays one executable built from pinned
submodules; the registry never loads DSP.

* **What the engine exposes** (already true): `rack --describe` prints every `Registrar` module with
  type, title, group, blurb, ins, outs and knobs (`main.cc`). New: a header object
  `{"engine_api": 1, "modules": [...]}` so the registry can refuse a snapshot from an engine it does
  not understand.
* **Snapshot.** `core/music/rack/modules.json` remains committed, as the **engine snapshot** (the
  engine's own description, so the room can be drawn with no compiler, on Windows and Quest). Nobody
  hand-edits it; `tools/rack_describe.sh` regenerates it.
* **Reconciling.** At scan: (a) every `sound.kind == "engine"` entry must name a snapshot type, else
  `engine_type_missing`; (b) every snapshot type should have an entry, else warning `engine_type_unclaimed`
  (the module exists in the engine but has no look: it appears with the default skin, not hidden); (c)
  when `RackEngine.available()`, the live `--describe` is compared with the snapshot and wins on
  difference (`snapshot_stale`).
* **Adding native DSP** then means: C++ in `native/rack/`, the upstream as a submodule or versioned
  binary, a notice row (generated), `rack_describe.sh`, and one manifest entry. No `studio.gd`, no
  `RackSkin`, no test edit.
* **The existing test** `_test_a_rack_catalogue_is_the_engines_own_description` (`run_tests.gd:44550`;
  compares `modules.json` with `--describe`, skipped without an engine) is kept unchanged as the
  "snapshot is current" check. Two tests are new or rewritten (section 10): the manifest/snapshot
  reconcile test (runs everywhere), and the skin test, which iterates the registry
  (`run_tests.gd:44881`).

## 9. Migration plan

Steps 1 and 2 are built (`core/mods/`: `ModProblem`, `ModManifest`, `ModEntryCheck`, `ModFiles`,
`ModRegistry`; `DataHome.dir`; `mods/mod.schema.json`; fixtures in `tests/fixtures/mods/`). They raise
`no_manifest`, `bad_json`, `bad_schema`, `unknown_key`, `api_version_unsupported`, `game_too_old`,
`id_collision`, `type_collision`, `reserved_id`, `missing_dependency`, `dependency_cycle`, `missing_file`,
`bad_model`, `unsupported_sound_kind`, `unknown_group`. The rest of section 5 (`engine_*`, `snapshot_stale`,
`binary_hash_mismatch`, `unsupported_platform`, `composite_invalid`, `plugin_not_found`) waits for the
step that has the thing to check (`ModProblem.LATER_CODES`). Details settled while building: `parse(data,
source_path, game_version)` reads `source_path` as the path of the `mod.json` (file checks run only then);
the game version is `ModManifest.GAME_VERSION` until the game has one constant; a non-shipped mod's rack
module `type` must equal its id or start with `<id>.`, else that entry is `reserved_id` (the sample mod's type
is its id); "shipped" roots are `ModRegistry.shipped_roots` (default `res://mods/builtin/`: each folder in it is one mod; `res://mods/` itself holds `mod.schema.json`); `$DAWLINGS_MODS`
splits on `;` on Windows; an empty or missing root is skipped; mods that fail a dependency stay in
`mods()` with status `unavailable`, invalid ones appear only in `problems()`.

Each step ends with the suite green and no behaviour change unless stated. Steps 1-4 are queue item 3,
5-8 are 4-5 (see the loop file).

1. **Parser.** `ModManifest.parse(Dictionary, source) -> ModManifest` with `ModProblem`s;
   `mods/mod.schema.json`; fixtures for each failure code in `tests/fixtures/mods/`. Not used by the
   game.
2. **Registry and `DataHome.dir`.** `ModRegistry.scan` over test roots; dependency order,
   collisions, `$DAWLINGS_MODS`. Still not used by the game.
3. **Plaits.** `res://mods/builtin/mutable/mod.json` with `plaits` only; `RackCatalogue`, `RackSkin.of`
   and `PAD_KNOBS` consult the registry first and fall back to the old tables. Test: registry result for
   `plaits` equals the old tables. **Built (2026-11-07), and what differs from the sketch above:**
   * The entry's `type` is still `plaits`, not `builtin.plaits`. Decision 2 (no alias table) means a
     renamed type must be renamed everywhere at once: `modules.json`, the engine's `add` lines, the
     presets, `PAD_KNOBS`, `SKINS` and the tests. Renaming one module now would break every patch that
     names it, so the rename of all 29 types to `builtin.<name>` happens in step 4 with the generated
     manifests, in one commit. A shipped mod may use a bare type (the `reserved_id` rule only polices
     user mods). Until then `builtin.mutable` and its `plaits` entry are the only manifest data.
   * The shipped root is `res://mods/builtin/` (each folder in it is a mod), not `res://mods/`, so
     `mods/mod.schema.json` is not scanned as a mod. `ModRegistry.SHIPPED_ROOT` changed to match.
   * `builtin.mutable` declares the `Voice` group itself, because `builtin.core` (which declares the
     seven) does not exist yet; step 4 moves it. Without it every start would log `unknown_group`.
   * The registry loads lazily: `ModRegistry.ensure_current()` scans `default_roots()` into `current`
     the first time the catalogue, `RackSkin.of` or `RackWall.pad_knobs` asks. No autoload, no startup
     call. `ModRegistry.rack_module_entry(type)` / `has_rack_module(type)` expose the entry.
   * `RackCatalogue` takes `title`, `group`, `blurb` from the entry and the jacks/knobs from the engine
     snapshot, as 3.3 says; it rebuilds its table when the registry emits `changed`.
   * Skin colours are stored as hex, so they are the 8-bit rounding of the old floats (at most 0.002
     off per channel; invisible). The test holds them to 0.003; the old table stays for fallback.
4. **The rest of the rack.** `tools/mods_from_legacy.py` generates manifests for the other 28 modules
   and the 30 presets from the old tables; an equivalence test proves registry data equals the tables;
   then the tables, `PAD_KNOBS` and `RackPatch.preset` bodies are deleted and the two enumerating tests
   rewritten (section 10). `RackCatalogue` is now a forwarder.
5. **Patch file and keep-unknown.** `RackPatch.to_dict/from_dict`, `w`, `uses`, the keep-unknown
   `sanitize`, autosave/load in `user://patches/`. Tests of 6.1 and 6.2. The unavailable plate is a
   plain label for now.
6. **Unavailable plate and guests.** `RackWall` draws missing modules and dangling cables; `uses`
   filled on publish; room-row and guest tests.
7. **Composite.** Expansion in `RackPatch.lines`; `interface` handling in `RackModuleDef`; meters.
8. **Plugin overlays, MODS screen, notices tool.** `plugin_display` in the tablet/unit; the MODS plate;
   `tools/mods_notices.py` and its `--check` in `tools/verify.sh`.
9. **The proof.** `mods_examples/dawlings.sample.pluck/` and the proof test (section 10).
10. **Source pins.** Manifests for `builtin.daisysp` and `builtin.dawkit`; the pin test.
11. **Remove old paths.** Delete forwarders, `modules.json` hand-edit paths, stale `architecture.md` rack
    section replaced by `docs/mods.md` pointers.

`studio.gd` loses its rack block (4643-5100, SM 3.1) to a `RackController` in step 6 (queue item 9).

## 10. Tests

| Test | Proves |
|---|---|
| `_test_a_manifest_parses_and_every_failure_is_named` | one fixture per code in section 5; none throws |
| `_test_the_registry_orders_mods_and_resolves_collisions` | 5, ordering |
| `_test_the_manifests_equal_the_old_tables` (steps 3-4 only) | no behaviour change |
| `_test_a_rack_catalogue_is_the_engines_own_description` (kept) | snapshot is current |
| `_test_every_engine_module_has_one_manifest_entry` (new) | reconcile, runs without an engine |
| `_test_every_module_has_a_skin_and_the_big_rig_fits_the_case` (rewritten to iterate the registry) | uniqueness holds for builtin; user mods only warn |
| `_test_submodule_pins_match_the_manifests` | 3.6 |
| `_test_the_notices_table_is_current` | 3.6 |
| `_test_a_patch_file_round_trips` | 6.1, v1 loads, atomic write |
| `_test_a_missing_mod_keeps_its_place_and_cables` | 6.2: save with the mod, load without, save again, load with: identical |
| `_test_a_guest_without_the_mod_sees_a_named_plate_and_hears_the_host` | 6.3 (host feeds the track; guest plate text from `uses`) |
| `_test_a_composite_expands_plays_and_meters` | 3.5: render 0.3 s, finite and non-silent |
| **`_test_a_sample_mod_dropped_in_a_folder_appears_plays_saves_reloads_and_replicates`** | the proof: copy `mods_examples/dawlings.sample.pluck` into a temp user root, `scan`, assert the module and preset are in the palette; load the preset, render audio from the engine; `to_dict` -> file -> `from_dict` equal; remove the folder, reload: plate unavailable, place and cables kept; host row -> guest `apply_room`: guest without the mod gets the named plate |

## 11. Decisions (owner, 2026-11-07)

1. **Manifest home.** Built-in manifests live in `res://mods/builtin/`, pointing at `vendor/` by pin.
2. **Namespacing.** Built-in types are renamed `builtin.<name>` (`builtin.plaits`). There is no alias
   table: nothing is in use yet, so old patches are not carried. Everyone else is `<mod id>.<name>`.
   Native `sound.type` names (`plaits`) are engine names and do not change.
3. **Engine builds.** Linux, macOS and Windows as shipped binaries (a `binary` source pin). Android/Quest
   native support is dropped; those platforms see rack modules as unavailable plates.
4. **Patch storage.** `user://patches/` only; the host loads it. A patch does not travel in the project
   file, and guests cannot save a copy.
5. **Model limits.** 2 MB and 20k triangles, decorative only, user textures allowed (counted in the 2 MB).
6. **Reaper.** Plugin overlays apply only to the built-in backend; an unavailable slot under Reaper is
   Reaper's business.
7. **Packaging.** Folders only until the sample-mod proof passes; `.zip`/`.pck` after.
8. **Composite cost.** A composite counts as its expanded modules against `MAX_MODULES`.
