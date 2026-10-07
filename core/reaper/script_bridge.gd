class_name ScriptBridge
extends RefCounted

## The second half of the Reaper link: a file-dropbox IPC to a ReaScript running inside Reaper.
##
## WHY THIS EXISTS AT ALL, given there is already an OSC socket. OSC covers everything that
## MOVES -- faders, pan, mute, solo, rec-arm, meters, transport, FX parameters, send levels --
## and nothing that is STRUCTURAL. There is no OSC message for "how many tracks are there",
## "what plugin is in slot 2", or "create a send from Rhodes to the reverb return". The patchbay
## is therefore unbuildable on OSC alone, and so is anything that needs to know the project's
## shape rather than its current values.
##
## WHY FILES and not a socket. ReaScript's Lua has no socket API. Reaper's own MCP bridge on this
## machine (~/.config/REAPER/Scripts/mcp_bridge.lua) solved it the same way and has been in daily
## use, so this follows a proven pattern rather than inventing one. The cost is latency measured
## in deferred-script ticks, roughly 30ms, which is fine for structure and far too slow for
## meters -- exactly the division of labour above.
##
## See reaper/reaper3d_bridge.lua for the Reaper side and docs/transport.md for the contract.

const DEFAULT_DIR := "~/.config/REAPER/Scripts/reaper3d_bridge_data"

var _dir := ""
var _next_id := 1
var _open := false
## {id: {"fn": String, "t": int, "cb": Callable}}
var _pending: Dictionary = {}

const TIMEOUT_MSEC := 4000


func open(dir: String = DEFAULT_DIR) -> bool:
	_dir = dir.replace("~", OS.get_environment("HOME"))
	# Deliberately does NOT create the directory. The bridge script creates it when it starts;
	# if it is missing, Reaper is not running the companion script, and silently creating an
	# empty one would turn that into requests that are never answered.
	if not DirAccess.dir_exists_absolute(_dir):
		push_warning("ScriptBridge: %s does not exist -- load reaper/reaper3d_bridge.lua in Reaper. Structural reads and routing writes are unavailable until then." % _dir)
		_open = false
		return false
	_open = true
	return true


func close() -> void:
	_open = false
	_pending.clear()


func is_open() -> bool:
	return _open


## Queue a ReaScript call. `cb` receives the decoded result, or null on timeout.
func call_reaper(fn: String, args: Array = [], cb: Callable = Callable()) -> bool:
	if not _open:
		return false
	var id := _next_id
	_next_id += 1
	var payload := JSON.stringify({"id": id, "fn": fn, "args": args})
	var f := FileAccess.open("%s/request_%d.json" % [_dir, id], FileAccess.WRITE)
	if f == null:
		push_error("ScriptBridge: cannot write request to %s" % _dir)
		return false
	f.store_string(payload)
	f.close()
	_pending[id] = {"fn": fn, "t": Time.get_ticks_msec(), "cb": cb}
	return true


## Collect any answers that have landed. Call once a frame from whatever owns the bridge.
func poll() -> void:
	if not _open or _pending.is_empty():
		return
	var now := Time.get_ticks_msec()
	for id in _pending.keys():
		var path := "%s/response_%d.json" % [_dir, id]
		if FileAccess.file_exists(path):
			var text := FileAccess.get_file_as_string(path)
			DirAccess.remove_absolute(path)
			var entry: Dictionary = _pending[id]
			_pending.erase(id)
			var parsed = JSON.parse_string(text)
			if entry["cb"].is_valid():
				entry["cb"].call(parsed)
		elif now - int(_pending[id]["t"]) > TIMEOUT_MSEC:
			var entry: Dictionary = _pending[id]
			_pending.erase(id)
			push_warning("ScriptBridge: %s timed out after %dms" % [entry["fn"], TIMEOUT_MSEC])
			if entry["cb"].is_valid():
				entry["cb"].call(null)
