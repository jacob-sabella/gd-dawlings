class_name PluginCatalogue
extends RefCounted

## The third-party plugins (CLAP, VST3, LV2) installed on this machine, for the built-in engine.
##
## Found by dawkit's scanner, a program of its own beside the engine, one plugin file at a time:
## a plugin that crashes as it starts costs its own entry, not the game. What it found is kept in
## user://, by file and the time the file last changed, so only new and changed files are looked
## at again, on a thread of their own. Each plugin is a dictionary as dawkit describes one:
## {format, id, name, vendor, version, path, category, instrument, has_editor}.

signal changed

const CACHE := "user://plugin_scan.json"
const VERSION := 1

static var _shared: PluginCatalogue

var _plugins: Array = []
var _cache := {}
var _thread: Thread
var _scanning := false


## The one catalogue, scanned the first time it is asked for.
static func shared() -> PluginCatalogue:
	if _shared == null:
		_shared = PluginCatalogue.new()
		_shared._load_cache()
		_shared.rescan()
	return _shared


## The catalogue as exactly `plugins`, never scanned: for checks, which should not depend on what
## a machine has installed nor wait for it to be looked at.
static func use_only(plugins: Array) -> void:
	_shared = PluginCatalogue.new()
	_shared._plugins = plugins.duplicate(true)


## Whether plugins can be hosted here at all: the engine's native core is in, and hosts on this
## system (Linux, for now).
static func available() -> bool:
	return ClassDB.class_exists(&"DawKitPlugin") and ClassDB.class_call_static(&"DawKitPlugin", &"hosting_available")


## Every plugin found so far, effects and instruments, sorted by name.
func plugins() -> Array:
	return _plugins


func effects() -> Array:
	return _plugins.filter(func(p: Dictionary) -> bool: return not p["instrument"])


func instruments() -> Array:
	return _plugins.filter(func(p: Dictionary) -> bool: return p["instrument"])


## The plugin `format` calls `id`, or {} when it is not installed.
func find(format: String, id: String) -> Dictionary:
	for p in _plugins:
		if p["format"] == format and p["id"] == id:
			return p
	return {}


func is_scanning() -> bool:
	return _scanning


## Looks for new, changed and removed plugin files, in the background; `changed` when done.
func rescan() -> void:
	if _scanning or not available():
		return
	_scanning = true
	_thread = Thread.new()
	_thread.start(_scan.bind(_cache.duplicate(true)))


## The scanner beside the engine: in the project's addon while developing, beside the game's
## executable once exported (where res:// is inside a pack no program can run from).
static func scanner() -> String:
	var name := "dawkit_scan.linux.x86_64"
	for path in [ProjectSettings.globalize_path("res://addons/dawkit/bin/").path_join(name),
			OS.get_executable_path().get_base_dir().path_join(name)]:
		if FileAccess.file_exists(path):
			return path
	return ""


## Waits for a scan under way to finish (tests, and a game quitting).
func wait() -> void:
	_done()


## On the main thread, when the scan's thread has finished (or to wait for it).
func _done() -> void:
	if _thread != null and _thread.is_started():
		_finish(_thread.wait_to_finish())


func _scan(cache: Dictionary) -> Dictionary:
	var files: Dictionary = cache.get("files", {})
	var kept := {}
	var exe := scanner()
	for format in ["CLAP", "VST3"]:
		var dirs: PackedStringArray = ClassDB.class_call_static(&"DawKitPlugin", &"default_paths", format)
		var found: PackedStringArray = ClassDB.class_call_static(&"DawKitPlugin", &"find_files", format, dirs)
		for path in found:
			var stamp := _stamp(path)
			var had: Dictionary = files.get(path, {})
			if had.get("stamp", -1) == stamp:
				kept[path] = had
				continue
			kept[path] = {"stamp": stamp, "plugins": _run(exe, [format, path])}
	var lv2 := {}
	var lv2_stamp := 0
	for dir in ClassDB.class_call_static(&"DawKitPlugin", &"default_paths", "LV2"):
		lv2_stamp += _stamp(dir)
	var had_lv2: Dictionary = cache.get("lv2", {})
	if had_lv2.get("stamp", -1) == lv2_stamp:
		lv2 = had_lv2
	else:
		lv2 = {"stamp": lv2_stamp, "plugins": _run(exe, ["LV2"])}
	_done.call_deferred()
	return {"version": VERSION, "files": kept, "lv2": lv2}


## A file's (or a folder's) last change, as a number to compare; a bundle's is the newest of what
## is directly in it, so a plugin updated in place is looked at again.
static func _stamp(path: String) -> int:
	var t := FileAccess.get_modified_time(path)
	if DirAccess.dir_exists_absolute(path):
		for f in DirAccess.get_files_at(path):
			t = maxi(t, FileAccess.get_modified_time(path.path_join(f)))
		for d in DirAccess.get_directories_at(path):
			t = maxi(t, FileAccess.get_modified_time(path.path_join(d)))
	return t


func _run(exe: String, args: Array) -> Array:
	if exe == "":
		# No scanner: in this process, which a crashing plugin takes down with it.
		return ClassDB.class_call_static(&"DawKitPlugin", &"scan_file", args[0], args[1] if args.size() > 1 else "")
	var out := []
	# A plugin that hangs as it starts is given up on.
	var rc := OS.execute("timeout", ["60", exe] + args, out)
	if rc != 0 or out.is_empty():
		return []
	var parsed = JSON.parse_string(out[0])
	return parsed if parsed is Array else []


func _finish(result: Dictionary) -> void:
	_thread = null
	_scanning = false
	_cache = result
	_plugins = _list(result)
	var f := FileAccess.open(CACHE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(result))
	changed.emit()


func _load_cache() -> void:
	if not FileAccess.file_exists(CACHE):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CACHE))
	if parsed is Dictionary and parsed.get("version", 0) == VERSION:
		_cache = parsed
		_plugins = _list(parsed)


static func _list(cache: Dictionary) -> Array:
	var out := []
	for entry in cache.get("files", {}).values():
		out.append_array(entry.get("plugins", []))
	out.append_array(cache.get("lv2", {}).get("plugins", []))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["name"].naturalnocasecmp_to(b["name"]) < 0)
	return out
