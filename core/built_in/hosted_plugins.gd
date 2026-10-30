class_name HostedPlugins
extends RefCounted

## The third-party plugins the built-in engine has loaded (dawkit's DawKitPlugin), by a key of
## their own that their chain slot carries (FXState.host_key).
##
## A slot is laid down again whenever its chain changes -- a move, an add, an undo -- and a
## plugin is far too heavy, and holds too much (its state, its open window), to be made again
## each time, so the slot names its plugin by key and the plugin stays here. One taken out of a
## chain is kept until the project closes, so an undo puts the same one back.
##
## Only the host loads plugins: a guest's chain shows their names and parameters, as the wire
## brings them, and its intents reach these through the host's DAW.
##
## Loading one is dawkit's work on a thread of its own (DawKitPlugin.begin_load), one at a time:
## a Wine plugin through yabridge starts a whole Windows process, five seconds and more, and the
## game stood still for all of it ("loading in certain heavy plugins causes the game to freeze. I
## would rather that work happen on a background thread and the main ui waits for it to
## complete", 2026-10-30). `host` answers at once with the plugin's key, and its slot is in the
## chain straight away, named, with nothing on the bus and no parameters yet (`is_loading`); `poll`,
## once a frame, says which have finished, and the engine then fills their slots in -- or takes
## out the slots of one that would not load. Until then the plugin is not pumped, run, or shown,
## and `info`, `is_instrument` and the state it is being given answer for it.

## The largest block a plugin is given at once; the mixer's are cut to it.
const MAX_BLOCK := 1024
## The most parameters a slot puts on the wire. A VST3 lists two thousand MIDI controller slots
## after its real controls; those are left out (not automatable), and past this many the rest.
const MAX_SHOWN := 512

## key -> {"plugin": DawKitPlugin, "effect": DawKitPluginEffect, "info": Dictionary,
## "shown": Array[int], "loading": bool}
var _all := {}
## Whether `host` loads on dawkit's thread and answers at once (the game), or waits for the plugin
## and answers "" for one that would not load (checks that want the slot whole the moment it is
## added).
var threaded := true
var _next := 1
## The song's clock, which tells a plugin's buses one block from the next and where the song is.
var transport: Object = null


static func available() -> bool:
	return PluginCatalogue.available()


## Why the last `host` came to nothing.
var last_error := ""


## Loads `info` (as PluginCatalogue lists it), with `state` if given, active at the mixer's rate.
## Its key, or "" with `last_error` saying why. Threaded, the key comes back at once and the
## plugin loads behind it (`is_loading`, `poll`); a load that fails then is told by `poll`.
func host(info: Dictionary, state := PackedByteArray()) -> String:
	last_error = ""
	if not available():
		last_error = "plugins are not hosted on this system"
		return ""
	if info.is_empty():
		last_error = "no such plugin here"
		return ""
	var p = ClassDB.instantiate(&"DawKitPlugin")
	if not p.begin_load(info, state, AudioServer.get_mix_rate(), MAX_BLOCK):
		last_error = "it could not start loading"
		return ""
	var key := "p%d" % _next
	_next += 1
	_all[key] = {"plugin": p, "info": info.duplicate(), "effect": null, "shown": [], "loading": true,
			"state": state}
	if not threaded:
		p.wait_loaded()
		var done := _finish(key)
		if not done["ok"]:
			last_error = done["error"]
			return ""
	return key


## The plugins that finished loading since last asked, each as {key, name, ok, error, info, state}
## (what it was asked to load): once a frame, on the main thread. One that did not load is gone
## (`has` is false) by the time it is said.
func poll() -> Array:
	var out := []
	for key in _all.keys():
		if _all[key]["loading"] and not _all[key]["plugin"].is_loading():
			out.append(_finish(key))
	return out


## Whether the plugin is still loading: named, but not yet on the bus or with parameters to show.
func is_loading(key: String) -> bool:
	return _all.has(key) and _all[key]["loading"]


## The keys of the plugins still loading.
func loading_keys() -> Array:
	return _all.keys().filter(func(k): return _all[k]["loading"])


## Waits for every plugin loading to finish, on the main thread. What `poll` would have said.
func finish_loads() -> Array:
	var out := []
	for key in _all.keys():
		if _all[key]["loading"]:
			_all[key]["plugin"].wait_loaded()
			out.append(_finish(key))
	return out


## A plugin dawkit has finished with, taken in: its parameters and its effect, or, one that would
## not load, let go of.
func _finish(key: String) -> Dictionary:
	var entry: Dictionary = _all[key]
	var p = entry["plugin"]
	var name: String = entry["info"].get("name", "?")
	var asked := {"key": key, "name": name, "info": entry["info"], "state": entry["state"]}
	entry.erase("state")
	if not p.is_loaded():
		_all.erase(key)
		return asked.merged({"ok": false, "error": p.get_error()})
	if p.get_warning() != "":
		push_warning("%s did not take its saved state: %s" % [name, p.get_warning()])
	entry["loading"] = false
	entry["info"] = p.info()
	entry["shown"] = Array(p.shown_params(MAX_SHOWN))
	if not p.is_instrument():
		var e = ClassDB.instantiate(&"DawKitPluginEffect")
		e.set_plugin(p)
		if transport != null:
			e.set_transport(transport)
		entry["effect"] = e
	return asked.merged({"ok": true, "error": ""})


## Another of the same plugin, set as `key`'s is now (as it is being set, while it loads).
func clone(key: String) -> String:
	if not _all.has(key):
		return ""
	return host(_all[key]["info"], plugin(key).get_state())


func has(key: String) -> bool:
	return _all.has(key)


func plugin(key: String) -> Object:
	return _all[key]["plugin"] if _all.has(key) else null


func effect(key: String) -> Object:
	return _all[key]["effect"] if _all.has(key) else null


func info(key: String) -> Dictionary:
	return _all[key]["info"] if _all.has(key) else {}


func is_instrument(key: String) -> bool:
	return _all.has(key) and plugin(key).is_instrument()


## The parameters worth showing, in the plugin's order.
func shown(key: String) -> Array:
	return _all[key]["shown"] if _all.has(key) else []


func set_transport(t: Object) -> void:
	transport = t
	for key in _all:
		if _all[key]["effect"] != null:
			_all[key]["effect"].set_transport(t)


## The chain slot for a plugin: its name as the wire says one ("VST3: Mantra"), its parameters'
## names and values, and its key.
func row(key: String) -> Dictionary:
	var p = plugin(key)
	var i := info(key)
	var type: String = i["format"] + ("i" if p.is_instrument() else "")
	var out := {"name": "%s: %s" % [type, i["name"]], "enabled": true, "wet": 1.0, "preset": "",
			"params": {}, "param_names": {}, "key": key, "param_list": shown(key)}
	for pi in shown(key):
		out["params"][pi] = p.get_param(pi)
		out["param_names"][pi] = p.param_info(pi)["name"]
	return out


## Once a frame, on the main thread: plugins' timers and windows, and what they asked for.
static func pump() -> void:
	if available():
		ClassDB.class_call_static(&"DawKitPlugin", &"pump")


## The titles of windows plugins put on the desktop and that were left there, to be answered
## there (an activation, a licence, a file to open), since last asked. dawkit keeps everything
## else a plugin puts up off the desktop.
static func take_desktop_windows() -> PackedStringArray:
	if not available():
		return PackedStringArray()
	return ClassDB.class_call_static(&"DawKitPlugin", &"take_desktop_windows")


## Every plugin closed and let go. One still loading is waited for (a few seconds at most, and
## only the one whose turn it is: the rest are called off).
func clear() -> void:
	for key in _all:
		var p = _all[key]["plugin"]
		p.editor_close()
		p.deactivate()
	_all.clear()
