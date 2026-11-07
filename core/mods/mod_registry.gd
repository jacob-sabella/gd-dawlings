class_name ModRegistry
extends RefCounted

## Finds the mods on disk, validates them and holds the result (docs/mods.md sections 5 and 7).
## `scan` takes roots, reads every folder in each as a mod, orders mods after the mods they
## `requires`, settles id and entry collisions (first wins) and records every failure as a
## ModProblem. It never throws: a bad mod is a recorded problem and the rest still load.
##
## One shared instance lives in `current`; tests build their own. Not used by the game yet.

const API_MIN := ModManifest.API_MIN
const API_MAX := ModManifest.API_MAX
## Extra roots for tests and development, separated by ":" (";" on Windows).
const ENV := "DAWLINGS_MODS"
## The in-tree root; only mods found under a shipped root may use `builtin.*` ids.
const SHIPPED_ROOT := "res://mods/"

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
var _owner: Dictionary = {}


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
	_owner.clear()
	var found: Array[ModManifest] = []
	for root in roots:
		_discover(root, found)
	_order_and_check(found)
	_claim_entries()
	_check_groups()
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
			continue
		if not shipped and (m.id == "builtin" or m.id.begins_with("builtin.")):
			_record(&"reserved_id", m.id, "'builtin' ids belong to the shipped mods")
			continue
		if _by_id.has(m.id):
			_record(&"id_collision", m.id, "%s already used by %s" % [m.id, (_by_id[m.id] as ModManifest).folder])
			continue
		if not shipped:
			_drop_unnamespaced(m)
		_by_id[m.id] = m
		found.append(m)


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
