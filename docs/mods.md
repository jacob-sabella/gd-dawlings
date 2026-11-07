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

`plugin`: `plugin.format` R (`clap`|`vst3`|`lv2`, or `godot` for the audio effects the built-in engine
ships), `plugin.id` R, `display` O (`title`; later skin, model, `first_params`, labels). Overlay on a
plugin the user has (4.3). A plugin id is namespaced by its format, so it is not renamed `builtin.*`: the
effect `compressor` is `godot:compressor`.

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
| Presets naming `plaits` (`rack_patch.gd:52,154,224,306`) | stay presets, in `builtin.presets`, which `requires` `builtin.core`, `builtin.daisysp` and `builtin.mutable` (step 4) |
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
    {"kind": "rack_module", "type": "builtin.plaits", "title": "PLAITS", "group": "Voice", "blurb": "Mutable Instruments' macro oscillator: 24 engines from virtual analogue to modal, granular, drums and speech.", "sound": {"kind": "engine", "type": "plaits"}, "skin": {"face": "#421F47", "accent": "#FF8CFF", "pattern": "checker", "tagline": "ONE OF 16"}, "pad_knobs": ["harm", "timbre"]}
  ]
}
```

The real file lists `rings`, `reverb` and `clouds` the same way (`modules_mutable.cc:119,146,198`).

### 3.4 Worked example: a DAW plugin entry (CLAP via dawkit)

The engine's own effects are `plugin` entries too (format `godot`, 4.3): see
`res://mods/builtin/effects/mod.json`. What follows is the user-installed kind.

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

`dawlings.sample.pluck` is a composite module built from three existing modules (`builtin.plaits`, `builtin.env`,
`builtin.vca`, ports and knobs as in `modules.json`), plus a skin and a preset. No engine change, no code. It
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
    {"kind": "rack_module", "type": "dawlings.sample.pluck", "title": "PLUCK", "group": "Voice", "blurb": "One note in, one pluck out: Plaits through a short envelope.", "sound": {"kind": "composite", "modules": {"osc": {"type": "builtin.plaits", "knobs": {"engine": 0.35, "harm": 0.4}}, "env": {"type": "builtin.env", "knobs": {"a": 0.0, "d": 0.25, "s": 0.0, "r": 0.2}}, "amp": {"type": "builtin.vca"}}, "cables": [["env.out", "amp.cv"], ["osc.out", "amp.in"]], "ins": {"pitch": ["osc.pitch"], "gate": ["env.gate", "osc.trig"]}, "outs": {"out": "amp.out"}, "knobs": {"timbre": {"to": "osc.timbre", "label": "TIMBRE"}, "decay": {"to": "env.d", "label": "DECAY"}}, "meter_from": "amp"}, "skin": {"face": "#1E2A1A", "accent": "#E6FF6A", "pattern": "dots", "tagline": "PLUCK IT"}, "pad_knobs": ["timbre", "decay"]},
    {"kind": "rack_preset", "name": "pluck_demo", "title": "Pluck demo", "patch": {"modules": {"keys": {"type": "builtin.keys", "at": [0, 0], "knobs": {}}, "pl": {"type": "dawlings.sample.pluck", "at": [1, 0], "knobs": {"decay": 0.4}}, "out": {"type": "builtin.out", "at": [3, 0], "knobs": {}}}, "cables": [["keys.pitch", "pl.pitch"], ["keys.gate", "pl.gate"], ["pl.out", "out.l"], ["pl.out", "out.r"]]}}
  ]
}
```

Expansion (pure GDScript, `RackExpansion`, called by `RackPatch.lines`; see section 9 step 7): an instance `pl` becomes engine modules `pl~osc`,
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

**Built (2026-11-07, step 8, plugin part).** `res://mods/builtin/effects/mod.json` (`builtin.effects`) holds a
`plugin` entry, format `godot`, for each of the ten effects of `FXCatalogue` (eq, eq21, compressor, reverb,
delay, chorus, filter, distortion, phaser, limiter), with `display.title` the name the chain and ADD
PLUGIN already used (EQ6, EQ21, Compressor, Reverb, Delay, Chorus, Low-pass, Drive, Phaser, Limiter).
`FXCatalogue.kinds()[kind]["name"]` is read from `ModRegistry.plugin_title("godot", kind)`; the
`AudioEffect` class and the parameter ranges stay in `fx_catalogue.gd` as the binding (they are code, not
data, and the sound would not change by moving them). `ModRegistry.plugin_display/plugin_title/plugin_ids`
serve the entries, and `PluginCatalogue.display_name(info)` gives a scanned plugin the title a mod
gives it, else its own: used for its ADD PLUGIN label (`GodotBackend.fx_choices`) and its chain row name
(`HostedPlugins.row`). No third-party plugin has a shipped entry, so nothing changes for them until a mod
adds one. Not done: `display.skin`, `first_params` and `param_key` are accepted and ignored (the
`RackUnit` and `PluginTablet` still look the same for every plugin); the unavailable slot for a plugin
the machine lacks; the Reaper backend's own list (`ReaperBackend.fx_choices`, Reaper's stock FX); the
`plugin_not_found` problem.

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
    "keys": {"type": "builtin.keys", "at": [0, 0], "w": 3, "knobs": {}},
    "pl": {"type": "dawlings.sample.pluck", "at": [1, 0], "w": 4, "knobs": {"decay": 0.4}},
    "out": {"type": "builtin.out", "at": [3, 0], "w": 2, "knobs": {}}
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
  func plugin_display(format: String, id: String) -> Dictionary   # the entry's `display`, {} if none (built)
  func plugin_title(format: String, id: String, fallback := "") -> String   # built
  func plugin_ids(format: String) -> Array[String]                 # built
  func rack_engine_type(type: String) -> String                    # builtin.plaits -> plaits (built)
  func rack_type_of_engine(engine_type: String) -> String          # plaits -> builtin.plaits (built)
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
   * The entry's `type` was still `plaits` at this step (renamed to `builtin.plaits` in step 4b). Decision 2 (no alias table) means a
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
4. **The rest of the rack.** Part (a), built (2026-11-07): all 29 rack modules and the 17 presets are on
   the registry and the old tables are deleted. Part (b), built (2026-11-07): the `builtin.<name>` rename
   and the DAW plugins' catalogue (4.3). What differs from the sketch:
   * **The rename (part b).** Every rack module type, in the manifests, the preset patch files and the
     tests, is `builtin.<name>`; there is no alias table, so a patch that still says `vco` is not carried
     (`RackPatch.sanitize` drops it as an unknown module). The engine keeps its own names: `modules.json`,
     the C++ `Registrar`s and each entry's `sound.type` are unchanged, and the registry maps a type to the
     engine's name (`ModRegistry.rack_engine_type`, `RackCatalogue.engine_type`) where the engine is
     spoken to (`RackPatch.lines`, `RackVoice._sync_patch`). The catalogue is keyed by type and each spec
     has `type` (the mod's) and `engine`. An engine module no mod claims keeps its bare engine name as its
     type. A module's id in a patch stays the short name (`vco`, `vco2`): an id is the first part of a jack
     path `id.port`, so it cannot hold the dot (`RackCatalogue.short_name`). The special modules are named
     once, `RackPatch.OUT_MODULE` and `WORLD_MODULE`; `rack_layout.gd` (SCOPE width), `rack_curves.gd`,
     `rack_wall.gd` (the `seq` bars, the `scope` screen) name `builtin.scope`, `builtin.seq`, `builtin.env`,
     `builtin.svf`, `builtin.ladder`. `studio.gd` changed in three comparisons with `"world"` only.
   * **`tools/mods_from_legacy.py` is retired** (deleted in the same commit). It wrote the manifests once,
     from tables that no longer exist; the manifests are now the source of truth and are edited by hand, and
     a second generator that rewrites them in full would overwrite those edits. Its input stays as
     `tests/fixtures/rack_legacy_tables.json` (bare names, the 26b79fc tables), which
     `_test_the_manifests_equal_the_old_tables` holds the manifests to, adding the prefix.
   * (Part a, as built:) the script `tools/mods_from_legacy.py` generated the manifests. Its input was
     `tests/fixtures/rack_legacy_tables.json`, the old `RackSkin.SKINS`, `RackWall.PAD_KNOBS`,
     `RackCatalogue.GROUPS` and `RackPatch` presets dumped from the live GDScript at `26b79fc` by a
     throw-away script, plus `modules.json` (title, group, blurb) and the C++ sources (which module uses
     `daisysp::`). `--check` says whether the files on disk are what it would write.
   * Four mods, not three: `builtin.core` (the seven groups and the 14 modules with no third-party DSP,
     source `in_tree`), `builtin.daisysp` (11 modules, pinned to `vendor/daisysp` @ `2c72eaf`; OUT is here
     because it uses `DcBlock`), `builtin.mutable` (plaits, rings, reverb, clouds) and **`builtin.presets`**
     (the 17 presets), not "presets in `builtin.core`" as 3.3 sketches. A preset names modules of all three
     others, so `builtin.core` would have to `requires` the other two, and a missing `builtin.mutable` would
     then take KEYS and CLOCK down with it. `builtin.presets` requires the three; losing one loses presets
     only. Palette groups are global across available mods, so the module mods do not `requires` core for
     them. `builtin.mutable` no longer declares `Voice`.
   * Each preset's patch is a file, `mods/builtin/presets/patches/<name>.patch.json` (`{modules, cables}`,
     one module and one cable per line), named by `patch.file`. `ModRegistry.rack_preset_names/title/patch`
     serve them; the patch is read on first ask, kept, and handed out as a deep copy with `at` as ints (JSON
     has one number type). An unreadable file is an empty patch (`RackPatch.preset` returns `empty()`) and
     a `missing_file` warning; the preset stays listed. Knobs are stored in full (the engine defaults the
     old code filled in at run time), so a preset no longer follows a later change of a knob's default.
   * Gone: `RackSkin.SKINS`, `RackWall.PAD_KNOBS`, `RackCatalogue.GROUPS` (now `RackCatalogue.groups()`, the
     registry's) and the preset bodies and helpers in `rack_patch.gd`. `RackSkin.DEFAULT` stays for a module no
     mod skins. `RackCatalogue` keeps `modules.json` for jacks and knobs and, for an engine module no mod
     claims, its title/group/blurb (doc 8: it appears, with the default skin). Nothing else falls back.
   * Skin colours are rounded to hex exactly as Godot's `Color.to_html` rounds the 32-bit floats (`0.9` is
     `E6`), so `tests/rack_mod_tests.gd` can compare them to the old floats to the 8-bit step.
   * The `face` (`out`, `scope`, `seq`) and `mood` keys are not emitted: nothing reads them yet.
   * Tests: `_test_the_manifests_equal_the_old_tables` (in `tests/rack_mod_tests.gd`, against the frozen
     fixture) and `_test_a_preset_with_a_bad_file_is_empty_and_never_a_crash`; the catalogue and skin tests
     now enumerate the registry.
5. **Patch file and keep-unknown.** Built (2026-11-07). `RackPatch.to_dict/from_dict/problem`, `w`, `uses`,
   the keep-unknown `sanitize`, autosave/load in `user://patches/`. Tests of 6.1 and 6.2
   (`tests/rack_patch_file_tests.gd`). The unavailable plate is a plain label for now. As built:
   * `RackPatch.problem(raw)` says why a dictionary cannot be read ("" if it can): not a dictionary, a
     `format` other than `dawlings.rack-patch`, a `version` that is not a number, below 1 or above `VERSION`
     (2), or no `modules`. No `format` means version 1, which loads. `from_dict` is `problem` then `sanitize`
     (an empty patch on a problem); `sanitize` itself never looks at `format` or `version`, so a room row,
     which has neither, still works.
   * **Keep-unknown.** `sanitize` keeps a module whose type the catalogue lacks, as
     `{type, at, w, knobs, missing: true}` (`w` clamped to 1..COLS, knobs only numbers under plain names, at
     most 64, not clamped; type 1..80 characters). `missing` is in memory only (`to_dict` does not write it).
     Known modules gain no new field in memory: `w` exists for them only in the file. `uses` entries for a
     missing type are carried in the patch (`p["uses"]`, only for missing types) so `to_dict` can write them
     again. A cable is kept when one end is a missing module and the other end is a real jack of a known
     module or a missing module (only the form `id.port` is checked). `RackLayout.width_in(p, id)` is the
     width everywhere a patch's module is measured (fits, tidy, flow, the wall); `fits`/`free_slot` take
     an optional `wide`. `RackPatch.playable(p)` is the patch without missing modules and their cables;
     `lines` and `RackVoice.set_patch` use it, so the engine never hears them.
   * `RackWall._build_module` draws a missing module as a plain plate titled `<type> not installed`, in its
     place and at its width, with the take-out key and the grip; no knobs, no jacks, so its cables are
     not drawn until step 6.
   * `RackPatchFile` (`core/music/rack/rack_patch_file.gd`): `read(path)` -> `{ok, patch, title, track,
     error}` (falls back to the `.bak`; size cap 256 kB), `text_of(dict)` (sorted keys, tab-indented, final
     newline: the same patch is always the same bytes), `write_text(path, text)` (temp file, the old file
     renamed to `.bak`, temp renamed over). `RackAutosave` (a Node, `core/music/rack/rack_autosave.gd`)
     restores `user://patches/_current.patch.json` into the studio's `rack_row` when the wall is built, and
     `note(row)` after each change starts a 1.5 s timer (restarted by every change); when it fires the dictionary is
     built on the main thread and the text and the file write run on a `WorkerThreadPool` task, only if the
     patch hash changed since the last save; leaving the tree flushes. Only `Session.is_authority()` writes.
     `RackAutosave.disabled` (the test runner sets it) keeps a studio under test off the player's file.
     `studio.gd` holds one `RackAutosave` and calls `restore` once and `note` twice.
   * **Not done here:** named saves (`<slug>.patch.json`) have no caller yet; (both done in step 6)
   * Cost (headless, `big_rig`, 35 modules, 11 kB): `to_dict` 105 us on the main thread, text 180 us and
     the file write 130 us on the worker; `note()` 1.3 us per call. A knob sweep costs the note and nothing else.
6. **Unavailable plate and guests.** Built (2026-11-07). As built:
   * `RackGaps` (`core/music/rack/rack_gaps.gd`, static): `plate_title` ("PLUCK not installed", else
     "<type> not installed"), `plate_note` ("dawlings.sample.pluck 0.1.0"), `plate_text` (the sentence of 6.3),
     `end_of`/`keep_cable`/`dangling`, `problems(p)` (the list: each missing mod once, each dangling cable) and
     `published(row)`. `RackWall._build_module` prints the title and puts the note in the tagline place.
   * **Dangling cables (deviation from step 5, as noted there).** `sanitize` now keeps a cable one of whose ends
     is a port a *known* module no longer has, provided the other end is a real jack, an absent module or
     another gone port. A port that exists in the other direction, a loop, a repeat, a module that is not in the
     patch and a path of the wrong form are still dropped. `RackPatch.playable` (so `lines` and the voice) leaves
     dangling cables out, as it does cables on absent modules. The file and `to_dict` keep them.
   * `RackStubs` (`hardware/rack/rack_stubs.gd`, a child of the wall): a cable with only one plug on the wall is a
     short stub out of that plug, red for a dangling cable, grey for one to an absent module, each with a small
     key that asks `pull_one` (the usual verb, so the host validates). `RackWall._lay_cables` calls it last.
   * **`uses` on the room row.** `Studio.room_state` publishes `RackGaps.published(rack_row)`: the row with the
     patch's `uses` filled for every type from the registry (`RackPatch.to_dict`). The host's own `rack_row` does
     not carry them for known types (they are not stored); for an absent type they are carried from what the
     file or row said, so a host who lacks a mod still passes the name on. A guest's `sanitize` keeps `uses`
     only for the types it lacks.
   * **Guests.** The host runs the engine from `RackPatch.playable`, so the sound with the stranger in the case is
     the sound the guest is sent; a guest builds no engine (`rack_voice` only holds the patch). Nothing about the
     replication path changed: the row already travelled whole. Tested in `tests/rack_gaps_tests.gd`.
   * Not done: the unavailable DAW plugin slot (needs the chain/`PluginTablet` work of step 8); the problem list is
     a function (`RackGaps.problems`) that nothing shows yet; the plate is not restyled beyond title and note.
7. **Composite.** Expansion in `RackPatch.lines`; `interface` handling in `RackModuleDef`; meters.
   **Built (2026-11-07).**
   * `RackModuleDef` (`core/music/rack/rack_module_def.gd`) is the scan-time half and reads no registry, patch or
     catalogue (a cycle between those classes does not compile): `resolve(entries)` checks every composite and
     gives each its interface `{ins, outs, knobs}`, `depth` and `cost`. It also reads the engine snapshot
     (`engine_modules`, `engine_spec`; `RackCatalogue.PATH` is `RackModuleDef.PATH`). The registry calls it at the
     end of `_index_rack_modules` (`_check_composites`): a bad composite is taken out of the rack modules, recorded
     as `composite_invalid` (error, entry `rack_module:<type>`, the reason in the message; the mod's other entries
     stay), and kept in `invalid_composite_entry` / `composite_problem` for the plate. Good ones are
     `is_composite`, `composite_info` (`depth`, `cost`, `spec`), `composite_sound`, `composite_types`.
   * Rules of `resolve`: inner ids are identifiers up to 20 characters (no `~`, no dot); inner types must be
     available rack modules (engine or composite) and not `builtin.out` / `builtin.world`; inner `knobs` name real
     knobs and hold numbers; each cable goes from an inner output to an inner input; each `ins` name has one or more
     inner inputs, each `outs` name one inner output, each plate knob a `to` that is an inner knob; `meter_from`
     is an inner id; a cycle, nesting past 3 (`RackModuleDef.MAX_DEPTH`; a composite of engine modules is depth 1),
     more than 64 expanded modules or 160 cables, and a plate with no jacks are refused.
   * The catalogue (`RackCatalogue._load`) lists the good composites after the engine's own, in registry order, with
     `engine: ""` and `composite: true`. A plate knob has the inner knob's range, curve, units and label (or the
     label given); where the composite sets the inner module's knob (`"knobs": {"d": 0.25}` on the inner module), that
     position is the plate knob's default. The width comes from the counts as for any module.
   * `RackExpansion` (`core/music/rack/rack_expansion.gd`) is the play-time half: `expand(p)` (returns `p` itself when
     it holds no composite, so a plain patch is untouched), `cost(type)`, `has_composite`, `meter_map`. Ids are
     `<instance>~<inner>`, nested `<instance>~<a>~<b>`. Order: every module of the patch by id, with each
     composite's inner modules and cables written as it is met; inner cables come before the patch's own; a patch
     cable on a plate jack fans out to every inner jack (a cable on a jack the plate lacks is dropped, as a
     dangling one is). A module's knobs are the composite's values for it, then the instance's values routed to it
     (0..1, clamped); a plate knob the instance does not hold leaves the inner value alone.
   * **Cap.** `RackPatch.cost(p)` is the sum of `RackExpansion.cost` (1 for an engine module and for a type nobody
     provides, the expanded count for a composite); `add`, the `add` verb and `sanitize` hold it to
     `MAX_MODULES` (64; the constant now lives in `RackModuleDef` and `RackPatch` aliases it). A patch with more
     is cut at the cap on load, in module order.
   * **Voice.** `RackVoice._sync_patch` diffs the *expanded* patch against what the engine has, so a live edit sends
     only inner changes; `knob()` on a composite plate re-syncs instead of sending one line; `meters` folds each
     composite plate's lamp from `meter_map` (`meter_from`, else the module its first output comes from; nested:
     through the inner composite's own). Scopes and sequencer steps inside a composite are not forwarded.
   * **Unavailable.** A composite that is `composite_invalid` is not in the catalogue, so a patch that uses it keeps
     it as the existing stranger plate (step 5); `RackGaps.plate_text` adds "unavailable, <reason>", and
     `to_dict` takes the plate's title from the dropped entry. No crash path: `resolve` returns a reason for any
     junk (tested with malformed `sound` objects).
   * Not done: `ModEntryCheck` still checks only the shape (`modules`, `ins`, `outs`); the details are
     `composite_invalid`, not `bad_schema`. The reason is not shown anywhere but the plate sentence and the
     problem list (the MODS screen is step 8). Fixtures: `tests/fixtures/mods/composite/` (`test_comp`: pluck, pair,
     stack; `test_bad`: one broken composite per rule, one fine). The sample mod itself is step 9.
8. **Plugin overlays, MODS screen, notices tool.** Plugin part, catalogue built (4.3; the tablet/unit look,
   the unavailable slot and `display.skin` remain); `plugin_display` in the tablet/unit; the MODS plate;
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
| `_test_a_composite_expands_exactly`, `_test_a_composite_has_its_own_interface`, `_test_composite_knobs_are_routed_to_the_inner_modules`, `_test_composites_nest_three_deep`, `_test_a_bad_composite_is_an_unavailable_plate_and_never_a_crash`, `_test_the_module_cap_is_counted_on_the_expansion`, `_test_a_composite_plate_meters_its_inner_module`, `_test_a_patch_without_composites_is_unchanged`, `_test_composite_fixtures_load`, `_test_a_composite_plays` (built, `tests/rack_composite_tests.gd`) | 3.5: exact lines, interface, knob routing, nesting, depth/cycle limits, cap, meters; render equals the same modules patched by hand. The sample mod's own render is the proof test |
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
