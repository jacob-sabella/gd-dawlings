class_name ModRegistry
extends RefCounted

## Finds the mods on disk, validates them and holds the result (docs/mods.md sections 5 and 7).
## `scan` takes roots, reads every folder in each as a mod, orders mods after the mods they
## `requires`, settles id and entry collisions (first wins) and records every failure as a
## ModProblem. It never throws: a bad mod is a recorded problem and the rest still load.
##
## One shared instance lives in `current`; tests build their own. The game opens it lazily through
## `ensure_current` (the rack catalogue, skins and orb pads do, docs/mods.md section 9 step 3).

const API_MIN := ModManifest.API_MIN
const API_MAX := ModManifest.API_MAX
## Extra roots for tests and development, separated by ":" (";" on Windows).
const ENV := "DAWLINGS_MODS"
## The in-tree root; only mods found under a shipped root may use `builtin.*` ids.
const SHIPPED_ROOT := "res://mods/builtin/"

## The registry the game asks; set at startup, replaced by tests.
static var current: ModRegistry

## After `scan` or `reload`.
signal changed()
## For each problem as it is recorded during a scan.
signal problem_found(problem: ModProblem)

## What `min_game_version` is compared with.
var game_version := ModManifest.GAME_VERSION
## Roots whose mods may use reserved (`builtin.`) ids. Tests may add a root here.
var shipped_roots: Array[String] = [SHIPPED_ROOT]

var _roots: Array[String] = []
var _mods: Array[ModManifest] = []
var _by_id: Dictionary = {}
var _problems: Array[ModProblem] = []
## Folders read but not taken in, each `{manifest, code, reason}`: a bad manifest, a reserved or repeated id.
var _rejected: Array[Dictionary] = []
var _owner: Dictionary = {}
var _rack_modules: Dictionary = {}
var _plate_of_engine: Dictionary = {}
## "format:id" -> the `plugin` entry, and the ids of each format in manifest order.
var _plugins: Dictionary = {}
var _plugin_ids: Dictionary = {}
var _preset_names: Array[StringName] = []
## Composite rack modules (RackModuleDef.resolve): type -> {depth, cost, spec} for the good ones, in
## registry order, and type -> {entry, reason} for the ones dropped as `composite_invalid`.
var _composites: Dictionary = {}
var _bad_composites: Dictionary = {}
## Preset name -> {"entry": the manifest entry, "folder": the mod's folder, "patch": the patch once read}.
var _presets: Dictionary = {}


## The shared registry, scanning `default_roots()` into `current` the first time it is asked. This
## is the game's single entry point: there is no autoload and no startup call to forget.
static func ensure_current() -> ModRegistry:
	if current == null:
		var reg := ModRegistry.new()
		reg.scan(default_roots())
		current = reg
	return current


## The roots a normal run scans, in order: the shipped folder, the player's `user://mods/`, then
## each path in $DAWLINGS_MODS (passed as `env` so tests need not touch the environment).
static func default_roots(env: String = OS.get_environment(ENV)) -> Array[String]:
	var roots: Array[String] = [SHIPPED_ROOT]
	var home := DataHome.dir("mods")
	if home != "":
		roots.append(home)
	var sep := ";" if OS.get_name() == "Windows" else ":"
	for p in env.split(sep, false):
		roots.append(p.strip_edges())
	return roots


## Reads every mod folder under `roots` (in the order given; folders sorted by name within a
## root). Idempotent: whatever was scanned before is forgotten. A root that does not exist is
## skipped without a problem.
func scan(roots: Array[String]) -> void:
	_roots = roots.duplicate()
	_mods.clear()
	_by_id.clear()
	_problems.clear()
	_rejected.clear()
	_owner.clear()
	var found: Array[ModManifest] = []
	for root in roots:
		_discover(root, found)
	_order_and_check(found)
	_claim_entries()
	_check_groups()
	_index_rack_modules()
	_check_composites()
	_index_presets()
	_index_plugins()
	for p in _problems:
		problem_found.emit(p)
	changed.emit()


## Scans the same roots again (the MODS screen's reload).
func reload() -> void:
	scan(_roots)


## The roots of the last scan.
func roots() -> Array[String]:
	return _roots


## Every mod that parsed, in dependency order (a mod comes after the mods it requires; ties keep
## discovery order). Includes mods whose status is unavailable; excludes invalid ones.
func mods() -> Array[ModManifest]:
	return _mods


## The folders that were read and not taken in, in the order found, each `{manifest, code, reason}`: a
## manifest that did not parse (the `manifest` is whatever could be read of it, `id` the folder's name at
## worst), or a valid one refused for a reserved or repeated id. The MODS screen lists them beside
## `mods()`; a folder with no `mod.json` at all is here too.
func rejected() -> Array[Dictionary]:
	return _rejected


## The mod with this id, or null.
func mod(id: String) -> ModManifest:
	return _by_id.get(id)


## True when the mod exists and its status is ok.
func is_available(id: String) -> bool:
	return _by_id.has(id) and (_by_id[id] as ModManifest).status == ModManifest.STATUS_OK


## Every problem of the last scan, warnings included, in the order found.
func problems() -> Array[ModProblem]:
	return _problems


## The problems with this code.
func problems_with(code: StringName) -> Array[ModProblem]:
	return _problems.filter(func(p: ModProblem) -> bool: return p.code == code)


## The id of the mod that owns an entry key (ModEntryCheck.entry_key), or "".
func entry_owner(key: String) -> String:
	return _owner.get(key, "")


## Palette groups declared by available mods, ordered by `order` (ties by discovery). Each is
## `{id, title, order, mod}`.
func groups() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in _mods:
		if m.status == ModManifest.STATUS_OK:
			for g in m.groups:
				out.append({"id": g["id"], "title": g["title"], "order": int(g["order"]), "mod": m.id})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["order"] < b["order"])
	return out


## The `rack_module` entry for this type as the mod gave it, or an empty Dictionary when no
## available mod provides it. The caller must not modify it.
func rack_module_entry(type: String) -> Dictionary:
	return _rack_modules.get(type, {})


## True when an available mod provides a rack module of this type.
func has_rack_module(type: String) -> bool:
	return _rack_modules.has(type)


## The names of the rack presets of every available mod, in the order the mods and their entries
## give them (the PRESETS group of the palette).
func rack_preset_names() -> Array[StringName]:
	return _preset_names


## The title of a rack preset, or "" when no available mod provides it.
func rack_preset_title(name: StringName) -> String:
	return str(_presets.get(name, {}).get("entry", {}).get("title", ""))


## A fresh copy of a rack preset's patch (`{modules, cables}`, with column and row as ints), or an
## empty Dictionary when no available mod provides it or its patch file cannot be read. The file is
## read on the first ask and kept.
func rack_preset_patch(name: StringName) -> Dictionary:
	var held: Dictionary = _presets.get(name, {})
	if held.is_empty():
		return {}
	if not held.has("patch"):
		held["patch"] = _read_patch(held["entry"], held["folder"])
	return (held["patch"] as Dictionary).duplicate(true)


func _index_presets() -> void:
	_preset_names.clear()
	_presets.clear()
	for m in _mods:
		if m.status != ModManifest.STATUS_OK:
			continue
		for e in m.entries:
			if e.get("kind") == "rack_preset":
				_preset_names.append(StringName(e["name"]))
				_presets[StringName(e["name"])] = {"entry": e, "folder": m.folder}


## The patch an entry holds, inline or in the file it names; {} (and a warning) when unreadable.
func _read_patch(entry: Dictionary, folder: String) -> Dictionary:
	var src: Dictionary = entry["patch"]
	if src.get("file") is String:
		var json := JSON.new()
		var path := folder.path_join(src["file"])
		if not FileAccess.file_exists(path) or json.parse(FileAccess.get_file_as_string(path)) != OK \
				or not json.data is Dictionary:
			push_warning("ModRegistry: preset %s: %s cannot be read" % [entry["name"], path])
			return {}
		src = json.data
	if not src.get("modules") is Dictionary or not src.get("cables") is Array:
		return {}
	var out := {"modules": {}, "cables": (src["cables"] as Array).duplicate(true)}
	for id in src["modules"]:
		if not src["modules"][id] is Dictionary:
			continue
		var m: Dictionary = (src["modules"][id] as Dictionary).duplicate(true)
		# JSON has one number type; the rack's cells are ints.
		var at: Variant = m.get("at")
		m["at"] = [int(at[0]), int(at[1])] if at is Array and (at as Array).size() >= 2 else [0, 0]
		out["modules"][id] = m
	return out


## True when an available mod provides a composite rack module of this type (docs/mods.md 4.1).
func is_composite(type: String) -> bool:
	return _composites.has(type)


## The composite types, in registry order.
func composite_types() -> Array[String]:
	var out: Array[String] = []
	out.assign(_composites.keys())
	return out


## A composite's {depth, cost, spec}: `cost` is the engine modules it expands to, `spec` its {ins, outs,
## knobs} as the catalogue holds a module. {} for anything else.
func composite_info(type: String) -> Dictionary:
	return _composites.get(type, {})


## A composite's `sound` as the mod gave it ({} for anything else). The caller must not modify it.
func composite_sound(type: String) -> Dictionary:
	return _rack_modules.get(type, {}).get("sound", {}) if _composites.has(type) else {}


## Why a composite was dropped as `composite_invalid` ("" for any other type).
func composite_problem(type: String) -> String:
	return str(_bad_composites.get(type, {}).get("reason", ""))


## The manifest entry of a composite that was dropped (its title, for the plate), or {}.
func invalid_composite_entry(type: String) -> Dictionary:
	return _bad_composites.get(type, {}).get("entry", {})


## Checks every composite (RackModuleDef.resolve): a good one is kept with its description, a bad one is
## taken out of the rack modules (so its plates are unavailable) and recorded as `composite_invalid`.
## The mod's other entries stay.
func _check_composites() -> void:
	_composites.clear()
	_bad_composites.clear()
	var found := RackModuleDef.resolve(_rack_modules)
	for type in _rack_modules.keys():
		var e: Dictionary = _rack_modules[type]
		if e.get("sound", {}).get("kind") != "composite":
			continue
		var info: Dictionary = found[type]
		if info["ok"]:
			_composites[type] = {"depth": info["depth"], "cost": info["cost"], "spec": info["spec"]}
			continue
		_bad_composites[type] = {"entry": e, "reason": info["reason"]}
		_rack_modules.erase(type)
		var key := ModEntryCheck.entry_key(e)
		var owner: ModManifest = _by_id.get(_owner.get(key, ""))
		if owner != null:
			owner.unavailable_entries[key] = &"composite_invalid"
		_record(&"composite_invalid", _owner.get(key, ""), "%s: %s" % [type, info["reason"]], key)


## The native engine's name for a rack module type (`builtin.plaits` -> `plaits`): the `sound.type` of
## its entry. "" for a type no available mod provides or one whose sound is not an engine module.
func rack_engine_type(type: String) -> String:
	var s: Variant = _rack_modules.get(type, {}).get("sound")
	return str(s["type"]) if s is Dictionary and s.get("kind") == "engine" else ""


## The rack module type that sounds as this engine module, or "" when no available mod claims it.
## When two entries name the same engine module, the first in registry order.
func rack_type_of_engine(engine_type: String) -> String:
	return _plate_of_engine.get(engine_type, "")


## What the available mods say about a plugin: the `display` object of its `plugin` entry
## (`title`, and later `skin`, `first_params`, `param_key`), or an empty Dictionary when no available mod
## has an entry for `(format, id)`. `format` is `clap`, `vst3`, `lv2`, or `godot` for the engine's own
## effects. The caller must not modify it.
func plugin_display(format: String, id: String) -> Dictionary:
	var d: Variant = _plugins.get("%s:%s" % [format, id], {}).get("display")
	return d if d is Dictionary else {}


## The title a mod gives a plugin, or `fallback` when none does.
func plugin_title(format: String, id: String, fallback: String = "") -> String:
	var t: Variant = plugin_display(format, id).get("title")
	return t if t is String and not (t as String).is_empty() else fallback


## The ids of the plugins of `format` that available mods describe, in the order the mods and their
## entries give them.
func plugin_ids(format: String) -> Array[String]:
	var out: Array[String] = []
	out.assign(_plugin_ids.get(format, []))
	return out


func _index_plugins() -> void:
	_plugins.clear()
	_plugin_ids.clear()
	for m in _mods:
		if m.status != ModManifest.STATUS_OK:
			continue
		for e in m.entries:
			if e.get("kind") == "plugin":
				var p: Dictionary = e["plugin"]
				_plugins["%s:%s" % [p["format"], p["id"]]] = e
				if not _plugin_ids.has(p["format"]):
					_plugin_ids[p["format"]] = []
				_plugin_ids[p["format"]].append(str(p["id"]))


func _index_rack_modules() -> void:
	_rack_modules.clear()
	_plate_of_engine.clear()
	for m in _mods:
		if m.status != ModManifest.STATUS_OK:
			continue
		for e in m.entries:
			if e.get("kind") == "rack_module":
				_rack_modules[str(e["type"])] = e
				var snd: Variant = e.get("sound")
				if snd is Dictionary and snd.get("kind") == "engine" and not _plate_of_engine.has(str(snd["type"])):
					_plate_of_engine[str(snd["type"])] = str(e["type"])


func _discover(root: String, found: Array[ModManifest]) -> void:
	var dir := DirAccess.open(root) if not root.is_empty() else null
	if dir == null:
		return
	var shipped := _is_shipped(root)
	var names := Array(dir.get_directories())
	names.sort()
	for folder_name in names:
		if str(folder_name).begins_with("."):
			continue
		var m := ModManifest.load_folder(root.path_join(folder_name), game_version)
		_problems.append_array(m.problems)
		if m.status != ModManifest.STATUS_OK:
			var errors := m.errors()
			_rejected.append({"manifest": m, "code": errors[0].code if not errors.is_empty() else &"bad_schema",
					"reason": "; ".join(errors.map(func(p: ModProblem) -> String: return p.message))})
			continue
		if not shipped and (m.id == "builtin" or m.id.begins_with("builtin.")):
			_refuse(m, &"reserved_id", "'builtin' ids belong to the shipped mods")
			continue
		if _by_id.has(m.id):
			_refuse(m, &"id_collision", "%s already used by %s" % [m.id, (_by_id[m.id] as ModManifest).folder])
			continue
		if not shipped:
			_drop_unnamespaced(m)
		_by_id[m.id] = m
		found.append(m)


## Records a valid manifest that is not taken in, as a problem and as a rejected folder.
func _refuse(m: ModManifest, code: StringName, why: String) -> void:
	_record(code, m.id, why)
	_rejected.append({"manifest": m, "code": code, "reason": why})


## A mod whose pinned binary (`source.kind` binary, `file` beside the manifest) is not there is
## unavailable, with `binary_missing`; its entries are not indexed. A path that leaves the folder counts
## as missing. The hash is not read here (docs/mods.md 3.6: `binary_hash_mismatch` is later).
func _check_binaries() -> void:
	for m in _mods:
		if m.status != ModManifest.STATUS_OK or m.source.get("kind") != "binary":
			continue
		var rel := str(m.source.get("file", ""))
		if rel.is_absolute_path() or ".." in rel.split("/") or not FileAccess.file_exists(m.folder.path_join(rel)):
			m.status = ModManifest.STATUS_UNAVAILABLE
			_record(&"binary_missing", m.id, "its binary %s is not in the mod's folder" % rel)


func _is_shipped(root: String) -> bool:
	return shipped_roots.any(func(s: String) -> bool: return s.trim_suffix("/") == root.trim_suffix("/"))


## A user mod's rack module types must be its own id or live under it (`<id>.<name>`).
func _drop_unnamespaced(m: ModManifest) -> void:
	for e in m.entries.duplicate():
		if e.get("kind") != "rack_module":
			continue
		var t := str(e.get("type"))
		if t != m.id and not t.begins_with(m.id + "."):
			var key := ModEntryCheck.entry_key(e)
			m.entries.erase(e)
			m.unavailable_entries[key] = &"reserved_id"
			_record(&"reserved_id", m.id, "type %s is not under %s." % [t, m.id], key)


func _order_and_check(found: Array[ModManifest]) -> void:
	var state: Dictionary = {}  # id -> 1 on the path, 2 done
	var cyclic: Dictionary = {}
	var path: Array[String] = []
	for m in found:
		_visit(m, state, cyclic, path)
	_check_binaries()
	for m in _mods:
		if cyclic.has(m.id):
			m.status = ModManifest.STATUS_UNAVAILABLE
			_record(&"dependency_cycle", m.id, "%s requires itself through other mods" % m.id)
			continue
		for r in m.requires:
			var why := _why_unmet(r)
			if why != "":
				m.status = ModManifest.STATUS_UNAVAILABLE
				_record(&"missing_dependency", m.id, why)


## Depth-first, requirements first, so `_mods` ends up in dependency order.
func _visit(m: ModManifest, state: Dictionary, cyclic: Dictionary, path: Array[String]) -> void:
	if state.get(m.id, 0) == 2:
		return
	state[m.id] = 1
	path.append(m.id)
	for r in m.requires:
		var dep: ModManifest = _by_id.get(r["mod"])
		if dep == null:
			continue
		if state.get(dep.id, 0) == 1:
			for id in path.slice(path.find(dep.id)):
				cyclic[id] = true
		else:
			_visit(dep, state, cyclic, path)
	path.pop_back()
	state[m.id] = 2
	_mods.append(m)


func _why_unmet(req: Dictionary) -> String:
	var id: String = req["mod"]
	var dep: ModManifest = _by_id.get(id)
	if dep == null:
		return "needs mod %s, which is not installed" % id
	if dep.status != ModManifest.STATUS_OK:
		return "needs mod %s, which is unavailable" % id
	if req.has("min") and ModManifest.compare_versions(dep.version, req["min"]) < 0:
		return "needs %s %s or newer; found %s" % [id, req["min"], dep.version]
	if req.has("max") and ModManifest.compare_versions(dep.version, req["max"]) > 0:
		return "needs %s %s or older; found %s" % [id, req["max"], dep.version]
	return ""


## In dependency order, the first mod to name an entry owns it; a later duplicate alone is dropped.
func _claim_entries() -> void:
	for m in _mods:
		if m.status != ModManifest.STATUS_OK:
			continue
		for e in m.entries.duplicate():
			var key := ModEntryCheck.entry_key(e)
			if _owner.has(key):
				m.entries.erase(e)
				m.unavailable_entries[key] = &"type_collision"
				_record(&"type_collision", m.id, "%s is already provided by %s" % [key, _owner[key]], key)
			else:
				_owner[key] = m.id


func _check_groups() -> void:
	var known := groups().map(func(g: Dictionary) -> String: return g["id"])
	for m in _mods:
		if m.status != ModManifest.STATUS_OK:
			continue
		for e in m.entries:
			if e.get("kind") == "rack_module" and e.get("group") is String and not e["group"] in known:
				_record(&"unknown_group", m.id, "group '%s' is not declared; it goes under Other" % e["group"],
						ModEntryCheck.entry_key(e), ModProblem.WARNING)


func _record(code: StringName, mod_id: String, msg: String, entry: String = "",
		severity: StringName = ModProblem.ERROR) -> void:
	var p := ModProblem.make(code, mod_id, msg, entry, severity)
	_problems.append(p)
