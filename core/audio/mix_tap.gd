class_name MixTap
extends RefCounted

## Getting the DAW's sound into this process, so a host can pass it on to guests.
##
## The DAW plays to the studio's speakers through the OS, not through us, and that stays true:
## this only ADDS a listener. On PipeWire that is cheap and exact. A virtual source named
## `reaper3d_tap` is made once, the DAW's output ports are linked into it alongside whatever
## they already feed, and Godot captures the tap like a microphone. Nothing the DAW was
## connected to is disconnected, so the engineer at the desk hears exactly what they heard
## before.
##
## Why not the monitor of the default sink, which needs no plumbing at all: it is everything
## the machine plays, which includes this app's own fader clicks, a browser tab, and the
## notification chime -- all sent to everyone, a few dozen milliseconds late. The tap is the
## DAW and nothing else.
##
## Linux with PipeWire only, stated rather than discovered. Windows would need WASAPI loopback
## and macOS a virtual device, neither of which Godot can open; there, `open` says so and the
## session carries on without sound.

const TAP := "reaper3d_tap"
## The DAW's node, by name. Reaper registers with JACK -- or with PulseAudio when set to it --
## as REAPER, and a second instance as REAPER-01. This app's own node is "reaper-3d" and must
## never match: that would feed the host's fader clicks to the guests.
const DAW_NODE := "^REAPER(-\\d+)?$"

## Why the last `open` gave no source, for the session panel. Empty when it worked.
static var why_not := ""
static var _module_id := -1


## A MixSource carrying the DAW's sound, or a silent one with `why_not` set.
static func open(node_name := "") -> MixSource:
	why_not = ""
	if OS.get_name() != "Linux":
		why_not = "Sharing the mix's audio needs PipeWire (Linux) on the host."
		return MixSource.new()
	if not _has("pw-link") or not _has("pactl") or not _has("pw-dump"):
		why_not = "Sharing the mix's audio needs PipeWire's tools (pw-link, pw-dump, pactl)."
		return MixSource.new()
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		why_not = "Audio input is disabled in the project settings."
		return MixSource.new()
	if not _ensure_tap():
		why_not = "Could not make the audio tap (pactl load-module failed)."
		return MixSource.new()
	var linked := link(node_name)
	if linked == 0:
		why_not = "Reaper's audio outputs were not found. Is Reaper running and playing to PipeWire?"
		return MixSource.new()
	return MixSource.Captured.new(TAP, "Guests hear Reaper's output, tapped from PipeWire.")


## Link the DAW's first two output ports into the tap. Returns how many links now exist.
## Idempotent: links already there are left alone, and asked for again cost one failed call.
static func link(node_name := "") -> int:
	var objects = JSON.parse_string(_run("pw-dump", []))
	if typeof(objects) != TYPE_ARRAY:
		return 0
	var pattern := RegEx.create_from_string(DAW_NODE)
	var daw_nodes := {}
	var tap_node := -1
	for o in objects:
		if o.get("type") != "PipeWire:Interface:Node":
			continue
		var named: String = o.get("info", {}).get("props", {}).get("node.name", "")
		if named == TAP:
			tap_node = int(o["id"])
		elif (node_name.is_empty() and pattern.search(named) != null) or named == node_name:
			daw_nodes[int(o["id"])] = named
	if daw_nodes.is_empty() or tap_node < 0:
		return 0
	# One DAW. Two Reapers open at once is a rig beside a real session, and the tap should
	# carry the real one -- the first registered, which is the lowest id.
	var daw_id: int = daw_nodes.keys().min()
	var outs: Array = []
	var ins: Array = []
	for o in objects:
		if o.get("type") != "PipeWire:Interface:Port":
			continue
		var props: Dictionary = o["info"]["props"]
		var node := int(props.get("node.id", -1))
		if node == daw_id and o["info"]["direction"] == "output":
			outs.append(o)
		elif node == tap_node and o["info"]["direction"] == "input":
			ins.append(o)
	var by_port := func(a, b): return int(a["info"]["props"].get("port.id", 0)) < int(b["info"]["props"].get("port.id", 0))
	outs.sort_custom(by_port)
	ins.sort_custom(by_port)
	var made := 0
	for i in mini(2, mini(outs.size(), ins.size())):
		_run("pw-link", [str(outs[i]["id"]), str(ins[i]["id"])])
		made += 1
	# A mono DAW output still reaches both ears.
	if outs.size() == 1 and ins.size() >= 2:
		_run("pw-link", [str(outs[0]["id"]), str(ins[1]["id"])])
	return made


## The tap is left in place when the session ends, on purpose: it costs nothing idle, and taking
## it down while a guest is reconnecting would drop links the next host would only remake. It
## goes when this process quits, if this process made it.
static func close() -> void:
	if _module_id >= 0:
		_run("pactl", ["unload-module", str(_module_id)])
		_module_id = -1


static func _ensure_tap() -> bool:
	if TAP in AudioServer.get_input_device_list():
		return true
	var out := _run("pactl", ["load-module", "module-null-sink", "media.class=Audio/Source/Virtual",
			"sink_name=" + TAP, "channel_map=front-left,front-right",
			"sink_properties=device.description=reaper-3d-mix-tap"]).strip_edges()
	if not out.is_valid_int():
		return false
	_module_id = int(out)
	# The driver learns of new devices on its own schedule; the list is what Godot will open.
	for i in 20:
		if TAP in AudioServer.get_input_device_list():
			return true
		OS.delay_msec(25)
	return TAP in AudioServer.get_input_device_list()


static func _has(tool: String) -> bool:
	return OS.execute("sh", ["-c", "command -v " + tool], [], false) == 0


static func _run(tool: String, args: Array) -> String:
	var out: Array = []
	OS.execute(tool, PackedStringArray(args), out, true)
	return "".join(out)
