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

## The largest block a plugin is given at once; the mixer's are cut to it.
const MAX_BLOCK := 1024
## The most parameters a slot puts on the wire. A VST3 lists two thousand MIDI controller slots
## after its real controls; those are left out (not automatable), and past this many the rest.
const MAX_SHOWN := 512

## key -> {"plugin": DawKitPlugin, "effect": DawKitPluginEffect, "info": Dictionary,
## "shown": Array[int]}
var _all := {}
var _next := 1
## The song's clock, which tells a plugin's buses one block from the next and where the song is.
var transport: Object = null


static func available() -> bool:
	return PluginCatalogue.available()


## Why the last `host` came to nothing.
var last_error := ""


## Loads `info` (as PluginCatalogue lists it), with `state` if given, active at the mixer's rate.
## Its key, or "" with `last_error` saying why.
func host(info: Dictionary, state := PackedByteArray()) -> String:
	last_error = ""
	if not available():
		last_error = "plugins are not hosted on this system"
		return ""
	var p = ClassDB.instantiate(&"DawKitPlugin")
	if not p.load(info):
		last_error = p.get_error()
		return ""
	if not state.is_empty() and not p.set_state(state):
		push_warning("%s did not take its saved state: %s" % [info.get("name", "?"), p.get_error()])
	if not p.activate(AudioServer.get_mix_rate(), MAX_BLOCK):
		last_error = p.get_error()
		return ""
	var key := "p%d" % _next
	_next += 1
	var entry := {"plugin": p, "info": p.info(), "effect": null, "shown": _shown(p)}
	if not p.is_instrument():
		var e = ClassDB.instantiate(&"DawKitPluginEffect")
		e.set_plugin(p)
		if transport != null:
			e.set_transport(transport)
		entry["effect"] = e
	_all[key] = entry
	return key


## Another of the same plugin, set as `key`'s is now.
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


## Every plugin closed and let go.
func clear() -> void:
	for key in _all:
		var p = _all[key]["plugin"]
		p.editor_close()
		p.deactivate()
	_all.clear()


static func _shown(p: Object) -> Array:
	var out := []
	for i in p.param_count():
		var d: Dictionary = p.param_info(i)
		if d["hidden"] or not d["automatable"] or d["read_only"]:
			continue
		out.append(i)
		if out.size() >= MAX_SHOWN:
			break
	# A plugin that marks nothing automatable (some LV2s) shows everything it does not hide.
	if out.is_empty():
		for i in mini(p.param_count(), MAX_SHOWN):
			if not p.param_info(i)["hidden"]:
				out.append(i)
	return out
