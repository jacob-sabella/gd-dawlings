extends RefCounted

## The rack modules and presets on the mod registry (docs/mods.md section 9 step 4, section 10), called
## from tests/run_tests.gd's `_test_*` wrappers. The old tables (RackSkin.SKINS, RackWall.PAD_KNOBS,
## RackCatalogue.GROUPS, the RackPatch presets) are gone; tests/fixtures/rack_legacy_tables.json is
## what they held when they were deleted, and the manifests under res://mods/builtin/ are held to it.

const LEGACY := "res://tests/fixtures/rack_legacy_tables.json"
const TMP := "user://mods_rack_test/"

var t: Node


func _init(runner: Node) -> void:
	t = runner


func check(label: String, ok: bool) -> void:
	t.check(label, ok)


## Makes `reg` the registry the game's tables ask, and has them read it afresh.
func _use(reg: ModRegistry) -> void:
	ModRegistry.current = reg
	RackCatalogue._forget()
	RackSkin._forget()


## Every rack module and preset the shipped manifests give equals what the old tables said, and the
## game's own entry points (RackCatalogue, RackSkin.of, RackWall.pad_knobs, RackPatch.preset) answer
## from the registry alone.
func manifests_equal_the_old_tables() -> void:
	var kept := ModRegistry.current
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LEGACY))
	var snapshot: Array = JSON.parse_string(FileAccess.get_file_as_string(RackCatalogue.PATH))["modules"]
	var reg := ModRegistry.new()
	reg.scan([ModRegistry.SHIPPED_ROOT])
	_use(reg)
	var ids: Array = reg.mods().map(func(m: ModManifest) -> String: return m.id)
	ids.sort()
	check("the shipped mods are airwindows, core, daisysp, effects, mutable and presets, all available, with no problem",
			ids == ["builtin.airwindows", "builtin.core", "builtin.daisysp", "builtin.effects", "builtin.mutable", "builtin.presets"]
			and ids.all(func(i: String) -> bool: return reg.is_available(i)) and reg.problems().is_empty())
	check("the vendor pins are the submodules' (THIRD_PARTY_NOTICES.md)",
			reg.mod("builtin.daisysp").source["path"] == "vendor/daisysp" and reg.mod("builtin.daisysp").source["commit"] == "2c72eaf"
			and reg.mod("builtin.mutable").source["path"] == "vendor/mutable-eurorack" and reg.mod("builtin.mutable").source["commit"] == "f4cfa76")
	# Modules: one entry for each the engine describes, nothing else.
	var engine_types: Array = snapshot.map(func(m: Dictionary) -> String: return m["type"])
	var types: Array = engine_types.map(func(x: String) -> String: return "builtin." + x)
	var entry_types: Array = []
	for m in reg.mods():
		for e in m.entries:
			# (The Airwindows mod's 532 composites are `builtin.aw.<effect>`; they are built on the engine's AIRWINDOWS.)
			if e["kind"] == "rack_module" and not String(e["type"]).begins_with("builtin.aw."):
				entry_types.append(e["type"])
	check("the manifests give one rack module for each module the engine describes (%d)" % types.size(),
			entry_types.size() == types.size() and entry_types.all(func(x: String) -> bool: return x in types)
			and types.all(func(x: String) -> bool: return reg.has_rack_module(x) and reg.entry_owner("rack_module:" + x) != ""))
	check("a module belongs to the mod whose DSP it uses",
			reg.entry_owner("rack_module:builtin.plaits") == "builtin.mutable" and reg.entry_owner("rack_module:builtin.reverb") == "builtin.mutable"
			and reg.entry_owner("rack_module:builtin.vco") == "builtin.daisysp" and reg.entry_owner("rack_module:builtin.keys") == "builtin.core")
	var same_text := true
	var same_sound := true
	var same_skin := true
	var close_skin := true
	var same_pads := true
	var legacy_skins: Dictionary = legacy["skins"]
	for m in snapshot:
		var engine: String = m["type"]
		var ty := "builtin." + engine
		var e := reg.rack_module_entry(ty)
		same_text = same_text and e["title"] == m["title"] and e["group"] == m["group"] and e["blurb"] == m["blurb"]
		var spec := RackCatalogue.spec(ty)
		var plain: Dictionary = m.duplicate()
		plain["engine"] = engine
		plain["type"] = ty
		same_text = same_text and str(spec) == str(plain)
		same_sound = same_sound and e["sound"] == {"kind": "engine", "type": engine}
		var old: Array = legacy_skins[engine]
		var face := Color(old[0][0], old[0][1], old[0][2])
		var accent := Color(old[1][0], old[1][1], old[1][2])
		var got := RackSkin.of(ty)
		# Skins are stored as hex, so the old floats come back to the nearest 8-bit step.
		same_skin = same_skin and got[0].to_html(false) == face.to_html(false) and got[1].to_html(false) == accent.to_html(false) \
				and got[2] == StringName(old[2]) and got[3] == old[3]
		close_skin = close_skin and _within(got[0], face, 0.003) and _within(got[1], accent, 0.003)
		same_pads = same_pads and RackWall.pad_knobs(ty) == legacy["pad_knobs"].get(engine, [])
	check("title, group and blurb equal modules.json for every module, and the catalogue serves them with the engine's jacks", same_text)
	check("every module's sound is the engine module of its own name, and its type is builtin.<name>", same_sound)
	check("every skin equals the old table to the 8-bit step, pattern and tagline exactly", same_skin)
	check("and is within 0.003 of the old floats", close_skin)
	check("every orb pad has the old table's two knobs, and a module without one has none", same_pads)
	check("every old pad belongs to a module the engine has", legacy["pad_knobs"].keys().all(func(k: String) -> bool: return k in engine_types))
	check("the palette groups are the old ones in the old order, and every module is in one",
			str(RackCatalogue.groups()) == str(legacy["groups"])
			and types.all(func(x: String) -> bool: return RackCatalogue.spec(x)["group"] in RackCatalogue.groups()))
	check("a module no mod gives a skin has the plain one, and no pad", RackSkin.of("nope") == RackSkin.DEFAULT and RackWall.pad_knobs("nope").is_empty())
	# Presets.
	var old_names: Array = legacy["presets"].map(func(p: Dictionary) -> String: return p["name"])
	check("the presets are the old ones in the old order (%d)" % old_names.size(),
			RackPatch.presets().map(func(n: StringName) -> String: return String(n)) == old_names)
	var titles := true
	var patches := true
	for p in legacy["presets"]:
		var n := StringName(p["name"])
		titles = titles and RackPatch.preset_title(n) == p["title"]
		patches = patches and RackPatch.preset(n) == _with_cells(p["patch"])
	check("every preset has its old title", titles)
	check("and its old patch, module for module, knob for knob and cable for cable", patches)
	var again := RackPatch.preset(&"keys_voice")
	again["modules"]["keys"]["at"][0] = 99
	again["cables"].clear()
	check("a preset is a fresh copy each time", RackPatch.preset(&"keys_voice") == _with_cells(legacy["presets"][0]["patch"]))
	check("a preset's cells are ints", RackPatch.preset(&"acid_line")["modules"]["vco"]["at"][0] is int)
	check("the default patch is the keys voice", RackPatch.default_patch() == RackPatch.preset(&"keys_voice"))
	check("a name no mod gives is an empty patch with no title", RackPatch.preset(&"nope") == RackPatch.empty() and RackPatch.preset_title(&"nope") == "")
	# No mods at all: plain skins, no pads, no palette groups, no presets; the engine's own text stays.
	var none := ModRegistry.new()
	none.scan([])
	_use(none)
	check("with no mods the skin is the plain one", RackSkin.of("builtin.plaits") == RackSkin.DEFAULT)
	check("with no mods there are no pads, no groups and no presets",
			RackWall.pad_knobs("builtin.svf").is_empty() and RackCatalogue.groups().is_empty() and RackPatch.presets().is_empty())
	check("with no mods the default patch is empty", RackPatch.default_patch() == RackPatch.empty())
	check("with no mods the catalogue is still the engine's own description, under the engine's own names", RackCatalogue.engine_type("svf") == "svf" and RackCatalogue.spec("svf")["title"] == snapshot[engine_types.find("svf")]["title"])
	_use(kept)
	if kept == null:
		ModRegistry.current = null


## A preset whose patch file is missing or broken is listed but empty and never crashes; an inline
## patch works too, with its cells read back as ints.
func a_preset_with_a_bad_file_is_empty_and_never_a_crash() -> void:
	var kept := ModRegistry.current
	DirAccess.make_dir_recursive_absolute(TMP + "bad")
	var manifest := {"format": "dawlings.mod", "api_version": 1, "id": "test.presets", "name": "Test presets",
			"version": "1.0.0", "licence": {"spdx": "MIT"}, "source": {"kind": "data"}, "provides": [
				{"kind": "rack_preset", "name": "inline", "title": "Inline", "patch": {"modules": {"o": {"type": "builtin.out", "at": [3.0, 1.0], "knobs": {}}}, "cables": []}},
				{"kind": "rack_preset", "name": "gone", "title": "Gone", "patch": {"file": "patches/gone.patch.json"}},
				{"kind": "rack_preset", "name": "broken", "title": "Broken", "patch": {"file": "broken.json"}}]}
	var f := FileAccess.open(TMP + "bad/mod.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest))
	f.close()
	f = FileAccess.open(TMP + "bad/broken.json", FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	var reg := ModRegistry.new()
	reg.scan([TMP])
	_use(reg)
	check("the three presets are listed, in order", RackPatch.presets() == [&"inline", &"gone", &"broken"])
	var inline := RackPatch.preset(&"inline")
	check("an inline patch is read, its cells as ints", inline["modules"]["o"]["at"] == [3, 1] and inline["modules"]["o"]["at"][0] is int)
	check("a missing patch file is an empty patch, and a warning", RackPatch.preset(&"gone") == RackPatch.empty()
			and reg.problems_with(&"missing_file").size() == 1)
	check("an unreadable patch file is an empty patch", RackPatch.preset(&"broken") == RackPatch.empty())
	check("the titles are still there", RackPatch.preset_title(&"gone") == "Gone")
	_mod_rmdir(TMP.trim_suffix("/"))
	_use(kept)
	if kept == null:
		ModRegistry.current = null


## The built-in types are `builtin.<name>` with no alias: the registry maps a type to the engine's
## name, a patch speaks types, the lines sent to the engine speak engine names, ids stay short, and
## a patch that still says a bare name is not carried.
func builtin_types_are_prefixed_and_the_engine_keeps_its_names() -> void:
	var reg := ModRegistry.ensure_current()
	check("the registry maps a type to the engine's name and back",
			reg.rack_engine_type("builtin.plaits") == "plaits" and reg.rack_type_of_engine("plaits") == "builtin.plaits"
			and reg.rack_engine_type("plaits") == "" and reg.rack_type_of_engine("nope") == "")
	check("the catalogue knows the prefixed types and not the bare ones",
			RackCatalogue.has("builtin.vco") and not RackCatalogue.has("vco")
			and RackCatalogue.types().all(func(x: String) -> bool: return x.begins_with("builtin.")))
	check("and says the engine's name of each", RackCatalogue.engine_type("builtin.ladder") == "ladder"
			and RackCatalogue.spec("builtin.ladder")["type"] == "builtin.ladder" and RackCatalogue.engine_type("nope") == "")
	check("a short name drops the mod's prefix", RackCatalogue.short_name("builtin.vco") == "vco"
			and RackCatalogue.short_name("dawlings.sample.pluck") == "pluck" and RackCatalogue.short_name("vco") == "vco")
	var p := RackPatch.empty()
	var a := RackPatch.add(p, "builtin.vco")
	var b := RackPatch.add(p, "builtin.vco")
	check("ids are the short name, so a jack path has one dot", a == "vco" and b == "vco2" and RackPatch.type_of(p, "vco2") == "builtin.vco")
	RackPatch.add(p, "builtin.plaits")
	var lines := RackPatch.lines(p)
	check("the engine is told its own names", "add vco vco" in lines and "add vco2 vco" in lines and "add plaits plaits" in lines
			and not "\n".join(lines).contains("builtin"))
	var old := {"modules": {"vco": {"type": "vco", "at": [0, 0], "knobs": {}}}, "cables": []}
	var kept := RackPatch.sanitize(old)
	check("a bare name is no alias for the prefixed one (no alias table): it is a kept missing module, never played",
			kept["modules"].has("vco") and RackPatch.is_missing(kept, "vco") and RackPatch.playable(kept)["modules"].is_empty())
	var every := true
	for name in RackPatch.presets():
		var preset := RackPatch.preset(name)
		for id in preset["modules"]:
			every = every and RackCatalogue.has(preset["modules"][id]["type"])
	check("every preset module is a prefixed type the catalogue has", every)


## The built-in engine's effects are `plugin` entries of `builtin.effects` (format `godot`), the names
## FXCatalogue and the ADD PLUGIN list show come from them, and a mod's `display.title` renames a scanned
## plugin in the same two places (PluginCatalogue.display_name).
func plugins_are_described_by_the_registry() -> void:
	var kept := ModRegistry.current
	var reg := ModRegistry.new()
	reg.scan([ModRegistry.SHIPPED_ROOT])
	var kinds: Array = FXCatalogue.kinds().keys().map(func(k: StringName) -> String: return String(k))
	check("every built-in effect kind has a godot plugin entry, in the table's order, and no other does",
			reg.plugin_ids("godot") == kinds and kinds.size() == 10 and reg.entry_owner("plugin:godot:eq21") == "builtin.effects")
	var names := {"eq": "EQ6", "eq21": "EQ21", "compressor": "Compressor", "reverb": "Reverb", "delay": "Delay", "chorus": "Chorus",
			"filter": "Low-pass", "distortion": "Drive", "phaser": "Phaser", "limiter": "Limiter"}
	var same := true
	for k in names:
		same = same and reg.plugin_title("godot", k) == names[k] and FXCatalogue.kinds()[StringName(k)]["name"] == names[k]
	check("each is called what the old table called it (the names songs and the wire already hold)", same)
	check("a plugin no mod describes has no display and the fallback title",
			reg.plugin_display("clap", "nope").is_empty() and reg.plugin_title("clap", "nope", "Own") == "Own" and reg.plugin_ids("clap").is_empty())
	var info := {"format": "clap", "id": "org.example.synth", "name": "Example Synth"}
	ModRegistry.current = reg
	check("a scanned plugin with no entry keeps the name it reports", PluginCatalogue.display_name(info) == "Example Synth")
	DirAccess.make_dir_recursive_absolute(TMP + "look")
	var manifest := {"format": "dawlings.mod", "api_version": 1, "id": "test.look", "name": "Test look", "version": "1.0.0",
			"licence": {"spdx": "MIT"}, "source": {"kind": "user_installed"}, "provides": [
				{"kind": "plugin", "plugin": {"format": "clap", "id": "org.example.synth"}, "display": {"title": "EXAMPLE"}}]}
	var f := FileAccess.open(TMP + "look/mod.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest))
	f.close()
	var user := ModRegistry.new()
	user.scan([ModRegistry.SHIPPED_ROOT, TMP])
	ModRegistry.current = user
	check("a mod's entry titles a scanned plugin", user.problems().is_empty() and PluginCatalogue.display_name(info) == "EXAMPLE"
			and user.plugin_ids("clap") == ["org.example.synth"])
	check("and the other scanned plugins are untouched", PluginCatalogue.display_name({"format": "vst3", "id": "x", "name": "Other"}) == "Other")
	_mod_rmdir(TMP.trim_suffix("/"))
	_use(kept)
	if kept == null:
		ModRegistry.current = null


func _within(a: Color, b: Color, tol: float) -> bool:
	return absf(a.r - b.r) <= tol and absf(a.g - b.g) <= tol and absf(a.b - b.b) <= tol


## A legacy patch (JSON numbers are floats, types bare) with its cells as ints and its types
## `builtin.<name>`, as the rack holds them.
func _with_cells(patch: Dictionary) -> Dictionary:
	var out := patch.duplicate(true)
	for id in out["modules"]:
		var at: Array = out["modules"][id]["at"]
		out["modules"][id]["at"] = [int(at[0]), int(at[1])]
		out["modules"][id]["type"] = "builtin." + String(out["modules"][id]["type"])
	return out


func _mod_rmdir(path: String) -> void:
	for d in DirAccess.get_directories_at(path):
		_mod_rmdir(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)
