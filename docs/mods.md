# Mods: manifest, registry and save format

Status: **built** (sections 7 and 9 say how far; the rest is the design it was built from). Companion: `docs/layouts.md`
(rooms and pieces), `docs/rack.md` (the rack that uses the mods), `docs/README.md` (the index). "Today" claims in the
design text cite `docs/refactor_state_map.md` (SM), which describes the code before the refactor.

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
| **Skin** | How a module looks on the rack: face and accent colour, pattern, tagline (today `RackSkin.SKINS`, `rack_skin.gd`), optionally a decorative model. |
| **Unavailable plate** | What a module, plugin or piece looks like when its mod is missing or broken: a plain labelled plate that keeps its place and its connections. Never a crash, never a silent deletion. |

Rules fixed by the owner (2026-11-07, `docs/refactor_loop.md` "Decisions"):

1. **Data-only plus pinned vendor DSP.** A user mod is a manifest, skin/model and a patch that uses
   DSP already compiled into the game. New native DSP comes only from pinned submodules or versioned
   binaries shipped with the game. No user-supplied native code (a reserved, undesigned extension
   point is marked in 4.2).
2. **A patch is a file.** It is saved and loaded; a missing mod shows an unavailable plate and keeps
   its place and cables.
3. **A guest without the host's mod** sees an unavailable plate naming the mod and still hears the
   host's sound, unless the host SHARES the mod and the guest accepts it (section 13). This replaces
   "no transfer" (owner, 2026-11-08, "Send all mods").
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
`rack_catalogue.gd`).

`rack_module`:

| Field | R/O | Meaning |
|---|---|---|
| `type` | R | The id patches use. Builtin mods are named `builtin.<name>` (`builtin.plaits`); every other mod is namespaced `<mod id>.<name>`. |
| `title`, `group`, `blurb` | R | Plate title, palette group, tooltip. For `engine` modules `title`/`group`/`blurb` default to the engine's `--describe` values. |
| `sound` | R | `{"kind":"engine","type":"plaits"}` or `{"kind":"composite", ...}` (4.1). Any other kind is rejected (4.2). |
| `interface` | (none) | The interface lives in `sound`: for `composite`, `sound.ins`, `sound.outs` and `sound.knobs` (3.5); for `engine` modules it is **not** repeated and `sound.ins/outs/knobs` are rejected (`bad_schema`): it comes from the engine (8). The parser has no separate `interface` key. |
| `skin` | R | `face`, `accent` (`#RRGGBB`), `pattern`, `tagline`. Today's four-tuple. |
| `pad_knobs` | O | The two knob ids of the orb pad (`rack_wall.gd`). |
| `face` | O | `{"kind":"standard"}` (default) or a builtin custom face: `out`, `scope`, `seq` (today's `rack_wall.gd`). User mods may only use `standard`. May add `model`. |
| `model` | O | `{"glb":"models/x.glb","slot":"front"}`: a decorative mesh mounted on the plate. Jacks and knobs are always generated from the interface, so a model cannot break interaction. |
| `mood` | O | `{"accent":"#RRGGBB","reacts_to":"level"|"hit"|"none"}`: how the modular room's lights treat this module (today `ModularAnnex.show_levels`, all modules alike). |
| `port_signals` | O | `{"portname":"gate"|"audio"|"cv"}` overrides of the cable colour lists (`rack_skin.gd`), which today silently default new names to CV. |

`rack_preset`: `name` R (unique), `title` R, `patch` R (an inline patch in the file format of 6.1, or
`{"file":"presets/x.patch.json"}`). Replaces `RackPatch.preset()` (30 hand-coded presets,
`rack_patch.gd`).

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
| C++ module `r_plaits` (`native/rack/modules_mutable.cc`) | `sound.type: "plaits"`; the C++ stays |
| Build globs for `plaits/dsp`, `stmlib` (`tools/rack_build.sh`) | `source` of the mod: submodule `vendor/mutable-eurorack` @ `f4cfa76` |
| `RackSkin.SKINS["plaits"]` = `[Color(0.26,0.12,0.28), Color(1,0.55,1), &"checker", "ONE OF 16"]` (`rack_skin.gd`) | `skin` (hex: 0.26,0.12,0.28 -> `#421F47`; 1,0.55,1 -> `#FF8CFF`) |
| `PAD_KNOBS["plaits"] = ["harm","timbre"]` (`rack_wall.gd`) | `pad_knobs` |
| Presets naming `plaits` (`rack_patch.gd`) | stay presets, in `builtin.presets`, which `requires` `builtin.core`, `builtin.daisysp` and `builtin.mutable` (step 4) |
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

The real file lists `rings`, `reverb` and `clouds` the same way (`modules_mutable.cc`).

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
| Skin | `skin` on the plate (`RackWall._build_module`, `rack_wall.gd`) | `display.skin` on the `RackUnit` and tablet | `skin` entry replaces a module's |
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
adds one.

Built (the MODS-screen branch): `display.skin` (validated like a module's skin; `{face, accent, pattern, tagline}`) dresses
the plugin's `RackUnit`: the face is tinted, and an accent band, the printed pattern and the tagline are added
(`RackSkin.of_plugin`, `RackUnitDress`). A slot whose plugin this machine lacks (the project kept it as it came, FXState meta
`unhosted`) shows the **unavailable plate** in its place: dark red, `UNAVAILABLE` and `CLAP <TITLE> is not installed here` (the title
a mod gives it, else the slot's name), keeping its power and remove keys so the project still saves it. `PluginRef.of(fx, backend)`
names the plugin a slot holds (`{format, id, name, missing}`, formats lower case). `plugin_not_found` is a listing status, not a stored
problem: `ModPluginListing.rows` marks each plugin entry `installed` or `missing` (with the reason) in the MODS screen and
`tools/rack_describe.sh`. A user mod cannot skin the ten built-in effects: `builtin.effects` owns every `godot:*` id and the first mod wins.
`--lose-plugin t:fx:format:id` in `tools/shot.sh` shows the plate offline.

Not done, and why: `first_params` and `param_key` are still accepted and ignored. `PluginTablet` is not skinned
(`plugin_tablet.gd` is already past the 800-line limit, so a skin there needs that file split first; the unit is the rack's
face, the tablet a second view), and the unavailable plate is a `RackUnit` only. The Reaper backend's own list
(`ReaperBackend.fx_choices` is Reaper's stock FX and an unavailable slot under Reaper is Reaper's business, open question 6)
is untouched, and so are the rack marbles outputs. The `unhosted` meta is still not on the wire, but the host sends a **plugin
marker** instead (section 13.4): `/track/N/fx/M/plugin` = `[format, id, name]`, which a guest stores as slot meta `plugin_ref`;
`PluginRef.of` then says `missing` when the guest's own plugin scan lacks it, and the rack shows the same unavailable plate.

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
| `binary_missing` | `source.kind` binary and `source.file` is not in the mod's folder (built) | mod unavailable, the reason is listed; mods that need it are unavailable too |
| `binary_hash_mismatch`, `unsupported_platform` | pinned binary altered or not for this OS | entry unavailable |
| `composite_invalid` | unknown inner type, cycle, depth > 3, bad jack | entry unavailable, reason shown |
| `unsupported_sound_kind` | reserved or unknown `sound.kind` | entry unavailable |
| `licence_missing` | no `licence.spdx` | `bad_schema` |
| `plugin_not_found` | `plugin` entry whose plugin is not scanned | listed as `missing` in the MODS screen and `rack_describe` (`ModPluginListing`, never stored); no effect on the game |
| `unknown_group` | module group not declared | placed in "Other"; warning |
| `unknown_key` | top-level key the format does not define | ignored; warning (3.1: forward compatibility) |

On start the game shows one toast ("2 mods could not be loaded: see MODS") if any `error` problem
exists, and writes all problems to the log. The MODS screen (built: F5, `ModsScreen`, section 11)
lists every mod folder with its version, licence, source pin, what it provides and, when unavailable, why. A mod removed after a patch used it is not a
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
  `_current` at start in place of the hard-coded `keys_voice` (`studio.gd`); in a joined session the room
  row wins and a guest never writes the host's file. Writes are atomic (temp + rename) and keep one
  `.bak`.
* Caps stay: `MAX_MODULES` 64, `MAX_CABLES` 160, file 256 kB.

### 6.2 Sanitise keeps what it cannot show

Today `RackPatch.sanitize` drops a module whose type the catalogue lacks (`rack_patch.gd`,
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

The `rack` row stays `{patch, track}` (`studio.gd`, `Session.ask_room` validation
`session.gd`); the patch inside gains `uses`. The host fills `uses` from its registry when it
publishes. A guest's registry resolves `type` locally; if absent, the plate reads
"PLUCK (dawlings.sample.pluck 0.1.0): not installed" from `uses`. The guest hears the host's sound
exactly as today (the host runs the engine and feeds the track, SM 1.6). A mod the host shares may be
offered and installed (section 13), after which the plate becomes the module. A guest
cannot turn knobs on a missing module (nothing to drag) but may move or remove it by the usual
`ask_rack` verbs, which the host validates. The guest's own prediction path (`_rack_apply`) uses the
same `sanitize`, so predictions do not drop modules the host kept.

## 7. The registry API (GDScript)

All in `core/mods/`: `ModProblem`, `ModManifest` (parse and validate one `mod.json`), `ModEntryCheck` (the
per-kind rules of `provides[]`), `ModFiles` (the files a manifest names, the model limits) and `ModRegistry`.
`ModRegistry` is instance-based with one shared instance (`ModRegistry.ensure_current()` scans the default roots
on first use; tests build their own and set `current`). Public surface, as it is:

```
static func ensure_current() -> ModRegistry
static func default_roots(env := ...) -> Array[String]     # shipped, user://mods, then $DAWLINGS_MODS
func scan(roots)  /  reload()  /  roots()                  # idempotent, never throws
func mods() / mod(id) / is_available(id) / entry_owner(key)
func problems() / problems_with(code)                      # ModProblem: code, mod, entry, message, severity
func groups() -> Array[Dictionary]                         # rack palette groups, ordered
func rack_module_entry(type) / has_rack_module(type)       # the manifest entry for a rack module
func rack_preset_names() / rack_preset_title(n) / rack_preset_patch(n)
func is_composite(type) / composite_types() / composite_info / composite_sound / composite_problem
func rack_engine_type(type) / rack_type_of_engine(engine_type)    # builtin.plaits <-> plaits
func plugin_display(format, id) / plugin_title(format, id, fallback) / plugin_ids(format)
```

The rack reads it through `RackCatalogue` (types, specs, groups, knobs: a cache built from the registry and the
engine snapshot, `RackCatalogue.types()/spec()/in_group()/knob()`), `RackSkin` (face colour, pattern, tagline),
`RackModuleDef` (a composite's resolved interface) and `RackExpansion` (play-time expansion). Plugins read
`plugin_title` and `plugin_display` through `PluginCatalogue.display_name`.
`RackMood.MOODS` is gone: each venue's mood is in its layout file (`docs/layouts.md` 5.3).

**Interface for engine modules.** A rack entry whose `sound.kind` is `engine` takes `ins/outs/knobs` from the
engine snapshot (section 8), so the interface exists in exactly one place.

## 8. The native engine and the registry

New native DSP is not user-supplied, so the C++ side stays one executable built from pinned
submodules; the registry never loads DSP.

* **What the engine exposes** (already true): `rack --describe` prints every `Registrar` module with
  type, title, group, blurb, ins, outs and knobs (`main.cc`). New: a header object
  `{"engine_api": 1, "modules": [...]}` so the registry can refuse a snapshot from an engine it does
  not understand.
* **Snapshot.** `core/music/rack/modules.json` remains committed, as the **engine snapshot** (the
  engine's own description, so the room can be drawn with no compiler, on Windows and Quest). Nobody
  hand-edits it; it is regenerated from `native/rack --describe` (the snapshot is not what `tools/rack_describe.sh` prints, section 12).
* **Reconciling.** At scan: (a) every `sound.kind == "engine"` entry must name a snapshot type, else
  `engine_type_missing`; (b) every snapshot type should have an entry, else warning `engine_type_unclaimed`
  (the module exists in the engine but has no look: it appears with the default skin, not hidden); (c)
  when `RackEngine.available()`, the live `--describe` is compared with the snapshot and wins on
  difference (`snapshot_stale`).
* **Adding native DSP** then means: C++ in `native/rack/`, the upstream as a submodule or versioned
  binary, a notice row (generated), the snapshot, and one manifest entry. No `studio.gd`, no
  `RackSkin`, no test edit.
* **The existing test** `_test_a_rack_catalogue_is_the_engines_own_description` (`run_tests.gd`;
  compares `modules.json` with `--describe`, skipped without an engine) is kept unchanged as the
  "snapshot is current" check. Two tests are new or rewritten (section 10): the manifest/snapshot
  reconcile test (runs everywhere), and the skin test, which iterates the registry
  (`run_tests.gd`).

## 9. Current state

Built and held by tests (the steps of the old migration plan are in `docs/refactor_loop.md`, "Log"):

| Part | State |
|---|---|
| Parser, validator, registry, `DataHome.dir`, `mods/mod.schema.json`, fixtures in `tests/fixtures/mods/` | Built. Codes raised: `ModProblem.CODES`. Unreachable until the thing they check exists: `ModProblem.LATER_CODES` (`engine_*`, `snapshot_stale`, `binary_hash_mismatch`, `unsupported_platform`). |
| Rack modules and presets on the registry | Built. `res://mods/builtin/{core,daisysp,mutable}` hold the 29 modules, `presets` the 17 preset patches, all named `builtin.<name>` with no alias table (decision 2). The old tables (`RackSkin.SKINS`, `PAD_KNOBS`, `RackCatalogue.GROUPS`, preset bodies) are deleted. |
| Patch file, keep-unknown, unavailable plate, guests | Built. `RackPatch` v2 (`format`, `version`, `uses`, `w`), `RackPatchFile` (atomic write, `.bak`, `.bad` set aside), `RackAutosave` (`user://patches/_current.patch.json`), `RackGaps`, `RackStubs`; the host row carries `uses`, a guest without the mod gets a named plate and no engine. |
| Composites | Built. `RackModuleDef.resolve` at scan, `RackExpansion.expand` at play time; depth 3, cost counted on the expansion against `MAX_MODULES` (64). |
| Plugin overlays | Partly. `res://mods/builtin/effects` gives the ten built-in effects their titles; `plugin_title`/`plugin_display` serve scanned plugins. Built: `display.skin` on the `RackUnit`, the unavailable plugin slot, `plugin_not_found` as a listing status (4.3). Not done: `first_params`, `param_key`, the tablet skin, Reaper's own list, the rack marbles outputs. |
| The proof | Built. `mods_examples/dawlings.sample.pluck/` (folder only, excluded from exports) and `tests/sample_mod_proof_tests.gd`: appears, plays, saves, reloads, replicates to a guest. |
| Mod sharing | Built (section 13). `ModShare` (checks, hash, install), `ModSend` (offer, chunked transfer), `ModOfferPrompt` (session panel), the plugin marker. |
| MODS screen | Built. `ModListing` (rows), `ModsScreen` (F5, read-only, host and guest), section 11. |
| `tools/rack_describe.sh` | Built (section 12): the registry's rows headless. |
| Not built | `tools/mods_notices.py` and the notice/pin tests (3.6); the snapshot regeneration script (the snapshot `core/music/rack/modules.json` is regenerated from `native/rack --describe` by hand, and `_test_a_rack_catalogue_is_the_engines_own_description` compares them when an engine exists). |

### How to add a mod (steps)

1. Make a folder with `mod.json` (section 3; copy `mods_examples/dawlings.sample.pluck/mod.json`). A user mod's rack
   type must be its id or start with `<id>.`.
2. A new sound from existing modules is a `composite` entry. A new sound from native DSP needs C++ in `native/rack/`
   from a pinned submodule or versioned binary (decision 1) plus an `engine` entry, a snapshot update and a row in
   `THIRD_PARTY_NOTICES.md`.
3. Put the folder in `user://mods/` (or a root of `$DAWLINGS_MODS`); a built-in one goes in `res://mods/builtin/<name>/`
   with an id `builtin.*`.
4. Run the rack and registry tests: `_test_the_registry_says_what_the_old_tables_say_for_plaits`,
   `tests/rack_mod_tests.gd`, `tests/rack_composite_tests.gd`, and the proof. Nothing in `studio.gd`, `RackWall`
   or the tests needs an edit.

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

| `_test_a_mod_is_offered_accepted_and_installed_and_its_plate_becomes_the_module`, `_test_declining_a_mod_or_having_it_already_changes_nothing`, `_test_a_shared_mod_with_a_bad_hash_path_kind_or_size_is_refused_whole`, `_test_the_plugin_marker_reaches_a_guest_and_lacking_it_is_the_unavailable_plate` (`tests/mod_share_tests.gd`) | 13: round trip, decline, hash, traversal, extension, program bytes, caps, binary source, builtin id, the plate becoming the module, the marker, solo |

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

## 11. The MODS screen

`F5` opens and closes it (`ModsScreen`, `core/mods/mods_screen.gd`), in the host's game and in a guest's: it only reads. One line per mod
folder the registry read, in registry order and then the folders it refused: status (`OK` / `UNAVAILABLE`), id, version, licence (SPDX),
source pin (`submodule vendor/daisysp @ 2c72eaf`, `in_tree core/built_in`, `binary file version sha 01234567`, `data`) and what
it provides (`rack_module x14, rack_preset x1`). An unavailable mod has its reason in red under it (`code: sentence`); the
warnings of an ok one (`unknown_key`, `missing_file`) and its dropped entries are in grey. The head says how many mods and how
many are unavailable. Under the mods, a PLUGINS block lists each `plugin` entry of an available mod (`OK` / `NOT HERE`, title,
format, mod, plugin id, `skin`) with the reason in red for one this machine lacks (`ModPluginListing`, `core/mods/mod_plugin_listing.gd`).

The rows are `ModListing.rows(registry)` (`core/mods/mod_listing.gd`), a pure function of a `ModRegistry`, so a script can print the same
thing (`tools/rack_describe.sh`, section 12). Listed, never a crash:

* a manifest that is not JSON, fails the schema, or is for another format or api: `ModRegistry.rejected()` keeps what was read, the row
  is named for its id (or the folder) and says the parser's sentence;
* a folder with no `mod.json`: a row naming the folder, `no_manifest`;
* a mod that parsed but cannot run (a missing dependency, a cycle, a pinned binary that is not there): unavailable, the problem
  recorded for it is the reason, and its entries are not in the game;
* a valid manifest refused for a reserved or repeated id: a row for the refused folder, `reserved_id` / `id_collision`.

Tests: `tests/plugin_dress_tests.gd` (skin validation, `RackSkin.of_plugin`, `PluginRef`, a unit's band and tagline, the unavailable plate, plugin rows) and `tests/mods_screen_tests.gd` (a temporary root with a good mod, bad JSON, a schema failure, no manifest, a missing binary, a
mod that needs it, and a present binary). Screenshot: `--panel mods` in `tools/shot.sh` with `--mod` folders.

## 12. `tools/rack_describe.sh`

Prints the registry headless, for scripts and CI: the rows of section 11, one per mod folder, tab separated (`status id version licence
source provides reason`, a `#` header and a `# N mods, M unavailable` footer), then the plugin rows, each starting `plugin` (`plugin status mod
format id title skin reason`), or `--json` (`{roots, mods: [row...], plugins: [row...]}`). It reads the
shipped folder and `$DAWLINGS_MODS` (colon-separated), and the player's `user://mods/` only with `--user`, so a CI run never reads or
creates anything in a player's data. `--strict` exits 1 when any mod is unavailable; exit 2 means godot printed no listing (a script
error). It runs `tools/rack_describe.gd` (a `SceneTree` script) over `ModListing.rows`, so the screen and the script cannot disagree.
Test: `_test_rack_describe_prints_the_registry_headless` (runs the script on a root with a bad manifest and a missing binary).
It does not print the engine snapshot; `core/music/rack/modules.json` is still regenerated from `native/rack --describe`.


## 13. Sharing mods with guests

Owner, 2026-11-08 ("Send all mods"), superseding "no transfer" in rule 3 of section 1. Rule 1 stands: a mod never carries
native code.

### 13.1 What is offered

The host offers its **user** mods (folders under `user://mods`, status ok) to a guest when the guest joins, and again when the
host's rack patch uses a mod the guest has not been asked about (`RackHost._offer_the_mods_in_use`; the mods the room uses go first).
Builtin mods (`builtin.*`, `res://`) are never offered, nor are VST/CLAP plugin files, their state or licences. A mod the guest
already has is not offered. A mod the guest declined is not asked again this session. At most 8 offers wait per guest, and one
offer is made per frame.

### 13.2 The guest's prompt

The session panel gains a block (`ModOfferPrompt`, `scenes/mod_offer_prompt.gd`): a card per offer naming the host, the mod, its
version, licence, size and file count, with ACCEPT and DECLINE; a progress bar while receiving; "Installed" or "Not installed: why"
after. The panel opens itself when an offer arrives. Declining or ignoring keeps today's behaviour: the unavailable plate and the
host's sound.

### 13.3 The transfer and its safeguards

`ModSend` (`core/session/mod_send.gd`, a child of the Session autoload, channel 6 like `FileSend`) follows the `FileSend` pattern:
reliable, chunked (32 KB slices, two per frame in all, so it never blocks audio or the frame loop), host-authoritative (the host
sends only what a guest accepted, one mod at a time per guest). The offer carries `{id, name, version, licence, size, count, hash}`;
`hash` is a SHA-256 over the sorted file set (`ModShare.digest`). The guest keeps the files in memory and writes nothing until
the whole set has passed, then installs atomically (a hidden staging folder renamed into `user://mods/<id>`), then the registry
rescans and the plates become the live module (`RackHost` shows the rack again on the registry's `changed`; the wall rebuilds a module whose
`missing` flag flipped).

`ModShare.check` runs on **both ends** (the host will not offer a set that fails it) and rejects the WHOLE mod for any of:

| Rule | Limit |
|---|---|
| Extensions | only `json png jpg ogg wav glb txt md` |
| Paths | relative and plain: no `..`, leading or doubled slash, backslash, drive colon, hidden segment or control character; at most 96 characters and 4 deep |
| Program bytes | a file starting like ELF, PE, Mach-O or `#!` is refused whatever it is called |
| Size | 4 MB a file, 8 MB in all, 64 files |
| Manifest | must parse and be ok; its id must equal the offered id; not `builtin.*`; no `binary` source |
| Hash | the received set must hash to the offer's `hash` |
| Links, hidden files | the host does not read them; the mod is not offered |

### 13.4 The plugin marker

A hosted or kept third-party plugin in a chain slot is sent as `/track/N/fx/M/plugin` = `[format, id, name]` (in the snapshot and on
every slot write; `MixWire.plugin_marker`, written in `OfflineBackend._write_fx`). Never a binary, a state blob or a licence. A
guest stores it as slot meta `plugin_ref`; `PluginRef.of` sets `missing` from the guest's own plugin scan (`PluginRef.installed`), so a
guest lacking the plugin sees the unavailable plate (4.3) and one that has it sees none. A rename of the slot forgets the marker.

### 13.5 Proof

`tests/mod_share_tests.gd` (section 10) and, with two real windows, a host with `dawlings.sample.pluck` and a guest with an empty
`user://mods`: the guest's prompt, then the live module and its MODS row after ACCEPT, and the plate after DECLINE.
