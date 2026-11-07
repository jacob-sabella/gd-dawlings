class_name ModManifest
extends RefCounted

## A parsed and validated `mod.json` (docs/mods.md section 3). `parse` never throws: whatever is
## wrong becomes a ModProblem and the manifest's `status` says whether it can be used. Pure data;
## nothing here is registered or loaded into the game (that is ModRegistry's job).

const FORMAT := "dawlings.mod"
const API_MIN := 1
const API_MAX := 1
## The game's own version, compared with `min_game_version`. There is no single constant for it
## elsewhere yet; callers (and tests) may pass another to `parse`.
const GAME_VERSION := "0.0.14"
const STATUS_OK := &"ok"
const STATUS_INVALID := &"invalid"
const STATUS_UNAVAILABLE := &"unavailable"
const SOURCE_KINDS: Array[String] = ["submodule", "binary", "in_tree", "data", "user_installed"]
const _KNOWN_KEYS: Array[String] = ["format", "api_version", "id", "name", "version",
		"min_game_version", "author", "description", "licence", "source", "requires", "groups",
		"provides", "$schema"]
const _ID_RE := "^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)*$"
const _SEMVER_RE := "^\\d+\\.\\d+\\.\\d+$"

var id := ""
var mod_name := ""
var version := ""
var min_game_version := ""
var author := ""
var description := ""
var api_version := 0
## `{spdx, copyright?, file?, redistributed?}`.
var licence: Dictionary = {}
## `{kind, ...}` as in the schema; the pin fields depend on the kind.
var source: Dictionary = {}
## `[{mod, min?, max?}]`.
var requires: Array[Dictionary] = []
## `[{id, title, order}]`: palette groups this mod declares.
var groups: Array[Dictionary] = []
## The `provides[]` entries, as given (kinds are checked, content is read by later steps).
var entries: Array[Dictionary] = []
## Entry key (ModEntryCheck.entry_key) -> the problem code that made that entry unavailable.
var unavailable_entries: Dictionary = {}
## STATUS_OK, STATUS_INVALID (the manifest could not be used) or STATUS_UNAVAILABLE (set by the
## registry: valid, but a dependency is missing or cyclic).
var status: StringName = STATUS_INVALID
## The path of the mod.json this came from, or "" when parsed from memory.
var path := ""
## The mod's folder, or "" when parsed from memory.
var folder := ""
## Every problem found while parsing this manifest, in order.
var problems: Array[ModProblem] = []


## Loads and parses `<folder>/mod.json`. A missing file is `no_manifest` and unreadable JSON is
## `bad_json`; both return an invalid manifest, never null.
static func load_folder(folder_: String, game_version: String = GAME_VERSION) -> ModManifest:
	var file := folder_.path_join("mod.json")
	var label := folder_.get_file()
	if not FileAccess.file_exists(file):
		return _failed(file, label, &"no_manifest", "no mod.json in the folder")
	var text := FileAccess.get_file_as_string(file)
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		var why := "line %d: %s" % [json.get_error_line(), json.get_error_message()] \
				if json.data == null else "the top level must be an object"
		return _failed(file, label, &"bad_json", why)
	return parse(json.data, file, game_version)


## Validates `data` (a decoded mod.json). `source` is the path it came from (used for messages
## and to check the files it names; "" skips file checks). Returns a manifest whose `status` is
## STATUS_OK unless an error problem was found.
static func parse(data: Dictionary, source_path: String = "", game_version: String = GAME_VERSION) -> ModManifest:
	var m := ModManifest.new()
	m.path = source_path
	if source_path.get_file() == "mod.json":
		m.folder = source_path.get_base_dir()
	var label: String = data["id"] if data.get("id") is String and not str(data["id"]).is_empty() \
			else (m.folder.get_file() if m.folder != "" else source_path.get_file())
	m.id = label
	var errs: Array[String] = []
	# The format gate comes first: a manifest of another format or a newer api cannot be read
	# against this schema, so nothing else is reported about it.
	if data.get("format") != FORMAT:
		m._add(&"bad_schema", label, "format must be \"%s\"" % FORMAT)
		return m
	var api: Variant = data.get("api_version")
	if not _is_int(api) or int(api) < 1:
		m._add(&"bad_schema", label, "api_version must be an integer of at least 1")
		return m
	m.api_version = int(api)
	if m.api_version < API_MIN or m.api_version > API_MAX:
		m._add(&"api_version_unsupported", label, "made for mod format %d; this game reads %d to %d" % [m.api_version, API_MIN, API_MAX])
		return m
	m._read_identity(data, errs)
	m._read_licence_source(data, errs)
	m._read_lists(data, errs)
	for e in errs:
		m._add(&"bad_schema", label, e)
	for key in data.keys():
		if not str(key) in _KNOWN_KEYS:
			m._add(&"unknown_key", label, "unknown key '%s' ignored" % key, "", ModProblem.WARNING)
	if m.min_game_version != "" and compare_versions(m.min_game_version, game_version) > 0:
		m._add(&"game_too_old", label, "needs game %s or newer; this is %s" % [m.min_game_version, game_version])
	if m.folder != "":
		m.problems.append_array(ModFiles.check(m.folder, data, m.id))
	if not m.problems.any(func(p: ModProblem) -> bool: return p.is_error() and p.entry == ""):
		m.status = STATUS_OK
	return m


## Compares two `major.minor.patch` strings: -1, 0 or 1. A malformed side counts as 0.0.0.
static func compare_versions(a: String, b: String) -> int:
	var pa := _triple(a)
	var pb := _triple(b)
	for i in 3:
		if pa[i] != pb[i]:
			return -1 if pa[i] < pb[i] else 1
	return 0


## True when this manifest's problems include a code.
func has_problem(code: StringName) -> bool:
	return problems.any(func(p: ModProblem) -> bool: return p.code == code)


## The problems of error severity.
func errors() -> Array[ModProblem]:
	var out: Array[ModProblem] = []
	for p in problems:
		if p.is_error():
			out.append(p)
	return out


func _read_identity(data: Dictionary, errs: Array[String]) -> void:
	var mid: Variant = data.get("id")
	if not mid is String or RegEx.create_from_string(_ID_RE).search(mid) == null or str(mid).length() > 64:
		errs.append("id must be dotted lower-case words, at most 64 characters")
	if not data.get("name") is String or str(data["name"]).is_empty() or str(data["name"]).length() > 40:
		errs.append("name must be a string of 1 to 40 characters")
	else:
		mod_name = data["name"]
	if not _semver(data.get("version")):
		errs.append("version must be major.minor.patch")
	else:
		version = data["version"]
	if data.has("min_game_version"):
		if _semver(data["min_game_version"]):
			min_game_version = data["min_game_version"]
		else:
			errs.append("min_game_version must be major.minor.patch")
	for f in [["author", 80], ["description", 400]]:
		if data.has(f[0]):
			if data[f[0]] is String and str(data[f[0]]).length() <= f[1]:
				set(f[0], data[f[0]])
			else:
				errs.append("%s must be a string of at most %d characters" % f)


func _read_licence_source(data: Dictionary, errs: Array[String]) -> void:
	var lic: Variant = data.get("licence")
	if not lic is Dictionary or not (lic as Dictionary).get("spdx") is String or str(lic["spdx"]).is_empty():
		errs.append("licence.spdx is required")
	else:
		licence = lic
	var src: Variant = data.get("source")
	if not src is Dictionary or not str(src.get("kind", "")) in SOURCE_KINDS:
		errs.append("source.kind must be one of %s" % ", ".join(SOURCE_KINDS))
		return
	var need: Array[String] = []
	var kind: String = src["kind"]
	match kind:
		"submodule": need = ["path", "commit", "upstream"]
		"binary": need = ["file", "version", "sha256", "upstream"]
		"in_tree": need = ["path"]
	for k in need:
		if not src.get(k) is String or str(src[k]).is_empty():
			errs.append("source.%s is required for a %s source" % [k, kind])
	if kind == "submodule" and src.get("commit") is String \
			and RegEx.create_from_string("^[0-9a-f]{7,40}$").search(src["commit"]) == null:
		errs.append("source.commit must be 7 to 40 hex digits")
	if kind == "binary" and src.get("sha256") is String \
			and RegEx.create_from_string("^[0-9a-f]{64}$").search(src["sha256"]) == null:
		errs.append("source.sha256 must be 64 hex digits")
	source = src


func _read_lists(data: Dictionary, errs: Array[String]) -> void:
	for r in _list(data, "requires", errs):
		if not r is Dictionary or not r.get("mod") is String:
			errs.append("requires[] items need a mod id")
			continue
		for bound in ["min", "max"]:
			if r.has(bound) and not _semver(r[bound]):
				errs.append("requires %s: %s must be major.minor.patch" % [r["mod"], bound])
		requires.append(r)
	for g in _list(data, "groups", errs):
		if not g is Dictionary or not g.get("id") is String or not g.get("title") is String \
				or not _is_int(g.get("order")):
			errs.append("groups[] items need id, title and an integer order")
			continue
		groups.append(g)
	var provides: Variant = data.get("provides")
	if not provides is Array or (provides as Array).is_empty():
		errs.append("provides must be a non-empty list")
		return
	for i in (provides as Array).size():
		var e: Variant = provides[i]
		if not e is Dictionary:
			errs.append("provides[%d] must be an object" % i)
			continue
		for p in ModEntryCheck.check(e, i, id):
			if p.code == &"bad_schema":
				errs.append(p.message)
			else:
				problems.append(p)
				unavailable_entries[p.entry] = p.code
		entries.append(e)


func _list(data: Dictionary, key: String, errs: Array[String]) -> Array:
	if not data.has(key):
		return []
	if not data[key] is Array:
		errs.append("%s must be a list" % key)
		return []
	return data[key]


func _add(code: StringName, label: String, msg: String, entry: String = "",
		severity: StringName = ModProblem.ERROR) -> void:
	problems.append(ModProblem.make(code, label, msg, entry, severity))


static func _failed(file: String, label: String, code: StringName, msg: String) -> ModManifest:
	var m := ModManifest.new()
	m.path = file
	m.folder = file.get_base_dir()
	m.id = label
	m.problems.append(ModProblem.make(code, label, msg))
	return m


static func _is_int(v: Variant) -> bool:
	return v is int or (v is float and v == floorf(v))


static func _semver(v: Variant) -> bool:
	return v is String and RegEx.create_from_string(_SEMVER_RE).search(v) != null


static func _triple(s: String) -> Array[int]:
	var out: Array[int] = [0, 0, 0]
	var parts := s.split(".")
	if parts.size() == 3 and _semver(s):
		for i in 3:
			out[i] = parts[i].to_int()
	return out
