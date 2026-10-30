class_name PatchWallSurface
extends Surface

## The audio devices' patchbay, as a wall: every node PipeWire has -- the interface, the apps, the
## dawlings streams -- as a pin matrix (PinMatrix), the ports that make sound down the left, each
## under its node's name, and the ports that take it across the top, each under its node's. A pin
## at a crossing is a link between the two ports (PipeGraph). The Carla / qpwgraph picture, big
## enough to stand in front of, and read as a grid so a busy machine stays readable. It reads the
## machine's own graph and follows it.
##
## Patching is a press: press a crossing to patch the two ports, or press a seated pin to cut that
## link. Press a node's name to fold its ports away to one line that says how many it has, and
## again to open it; a crossing with a folded node counts the links inside it, and pressing it
## opens the node. However many ports the machine has, the grid scrolls to every one of them --
## drag it, wheel its names, or use its bars -- so nothing is ever counted at the foot and left
## out of reach. The foot says what the last press did.
##
## LEVELS, where they can be had cheaply (docs/spatial_loop.md part three, D and E). PipeWire keeps
## no per-port level anyone can read: `pw-top` reports each node's timing, `pw-dump` and `pw-cli`
## its volume (a gain, not a level), and a meter would need a capture stream of its own on every
## port, as pavucontrol opens one a stream (PEAK_DETECT) -- a process or a stream a port, all the
## time, for a wall. So only the streams whose level this process already knows are metered
## (`port_level`): dawlings's own outputs (the Mix, Monitor and Gear streams, AudioPorts, and the
## app's own output) by their AudioServer buses' peaks, and on Reaper the DAW's outputs and the
## `dawlings_tap` they feed (MixTap) by Reaper's master meter. Every other port's card says it is
## not measured, and why. The skyline stands a tower on every link out of a metered port.
##
## It is the machine's own graph and the player's own hands, so nothing about it is shared with
## the session: a guest's sound card is the guest's.

const WIDTH := 5.2
## The screen's height, fixed: a big graph scrolls rather than growing the wall down the room.
const HEIGHT := 3.4
## The title strip over the matrix, and the counts under it.
const HEAD := 0.26
const FOOT := 0.2
const REFRESH_SECONDS := 2.0

const INK := Color(0.92, 0.94, 0.98)
const DIM := Color(0.72, 0.75, 0.82)
## How wide the frame round the screen is.
const FRAME := 0.10
## A node's own lines are keyed by its name behind this, so a node and a port never share a key.
const GROUP := "@"

## The graph on the wall. Set it to show one; otherwise the machine's own is fetched.
var graph: PipeGraph
## What is asked for the graph (PipeGraph.fetch), a stand-in for the suite.
var tool := "pw-link"
## Whether the machine is asked again every few seconds. Off for the suite.
var follow := true
## How many links the wall shows seated.
var cables := 0
var height := HEIGHT

## What the last patch or cut did, said in the footer.
var status := ""
var matrix: PinMatrix
var _shown := ""
## What the screen was dressed in (the venue's palette and gear), so a venue change redraws it.
var _dressed := ""
var _thread: Thread
var _next_ask := 0.0
## How many links each crossing holds, a node's crossings counting all of its ports':
## "row key|column key" -> count.
var _links := {}
var _outputs := {}


func _ready() -> void:
	surface_id = &"patch_wall"
	surface_kind = &"patchwall"
	super()
	matrix = PinMatrix.new()
	matrix.name = "Matrix"
	matrix.row_head = 1.3
	matrix.col_head = 0.9
	matrix.row_pitch = Vector2(0.1, 0.14)
	matrix.col_pitch = Vector2(0.11, 0.16)
	matrix.area = Vector2(WIDTH - 0.1, HEIGHT - HEAD - FOOT)
	matrix.bar = 0.1
	matrix.gap = 0.025
	matrix.foot = 0.14
	matrix.px = 0.0017
	matrix.name_cap = 0.06
	matrix.chip = 0.07
	matrix.row_word = "OUTPUTS"
	matrix.col_word = "INPUTS"
	matrix.pin_at = _pin_at
	matrix.toggle = _toggle
	matrix.describe = _describe
	matrix.describe_line = _describe_line
	matrix.row_meter = port_level
	matrix.col_meter = port_level
	matrix.pin_meter = func(out_key: String, _in_key: String) -> Vector3: return port_level(out_key)
	matrix.tower_max = 0.9
	matrix.position = Vector3(-(WIDTH - 0.1) * 0.5, -HEAD, 0.004)
	matrix.visible = false
	add_child(matrix)


func _exit_tree() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null


func _process(delta: float) -> void:
	super(delta)
	if _thread != null and not _thread.is_alive():
		show_graph(_thread.wait_to_finish())
		_thread = null
	if _dressed != _dress_key():
		mark_dirty()
	if follow and _thread == null and is_visible_in_tree():
		_next_ask -= delta
		if _next_ask <= 0.0:
			# Slower when there is no graph to read (no PipeWire): nothing is going to change.
			_next_ask = REFRESH_SECONDS if graph == null or graph.error.is_empty() else REFRESH_SECONDS * 5.0
			_thread = Thread.new()
			_thread.start(PipeGraph.fetch.bind(tool))


## Shows a graph, rebuilding only when it differs from the one shown.
func show_graph(g: PipeGraph) -> void:
	graph = g
	if g.signature() != _shown:
		mark_dirty()


func _rebuild() -> void:
	_clear_built()
	cables = 0
	_dressed = _dress_key()
	_quad(Vector2(WIDTH + 0.16, HEIGHT), Vector3(0, -HEIGHT * 0.5 + 0.08, -0.006), _panel())
	_frame(Vector2(WIDTH + 0.16, HEIGHT), Vector3(0, -HEIGHT * 0.5 + 0.08, 0.0))
	_casing(Vector2(WIDTH + 0.16, HEIGHT), Vector3(0, -HEIGHT * 0.5 + 0.08, 0.0))
	_note("AUDIO DEVICES", -0.12, 56, _brass())
	if graph == null or not graph.error.is_empty():
		_shown = "" if graph == null else graph.signature()
		matrix.visible = false
		matrix.set_lines([], [])
		_note("listening to the audio graph..." if graph == null else graph.error, -HEIGHT * 0.4, 48)
		return
	_shown = graph.signature()
	matrix.ground = _panel().lightened(0.05)
	matrix.ground_banded = _panel().lightened(0.10)
	matrix.ink = INK
	matrix.dim_ink = DIM
	_outputs.clear()
	_links.clear()
	var rows: Array = []
	var cols: Array = []
	for node in graph.nodes_by_use():
		var tint := _tint(node)
		for side in ["outputs", "inputs"]:
			var ports: Array = graph.nodes[node][side]
			if ports.is_empty():
				continue
			var lines: Array = rows if side == "outputs" else cols
			lines.append({"key": GROUP + node, "name": PipeGraph.short_name(node, 28), "colour": tint,
					"group": true, "count": ports.size()})
			for port: String in ports:
				lines.append({"key": port, "name": PipeGraph.label_of(port), "colour": tint, "of": GROUP + node})
				if side == "outputs":
					_outputs[port] = true
	for link in graph.links:
		var o: String = link[0]
		var i: String = link[1]
		for a in [o, GROUP + PipeGraph.node_of(o)]:
			for b in [i, GROUP + PipeGraph.node_of(i)]:
				_links[a + "|" + b] = int(_links.get(a + "|" + b, 0)) + 1
		cables += 1
	matrix.visible = true
	matrix.set_lines(rows, cols)
	var counts := "%d nodes · %d links" % [graph.nodes.size(), graph.links.size()]
	_note(counts if status.is_empty() else "%s · %s" % [counts, status], -HEIGHT + 0.08 + FOOT * 0.5, 34)


# --- the crossings ----------------------------------------------------------------------------

func _pin_at(out_key: String, in_key: String) -> Dictionary:
	var node := out_key.trim_prefix(GROUP) if out_key.begins_with(GROUP) else PipeGraph.node_of(out_key)
	var n := int(_links.get(out_key + "|" + in_key, 0))
	if out_key.begins_with(GROUP) or in_key.begins_with(GROUP):
		return {"links": n, "tint": _tint(node)}
	return {"on": n > 0, "level": -1.0, "tint": _tint(node)}


func _toggle(out_key: String, in_key: String) -> String:
	patch(out_key, in_key)
	return status


## Patches two ports, or cuts the patch between them if they are already patched: the output
## first, whichever was named first. Then reads the graph again, so the wall shows it.
func patch(a: String, b: String) -> bool:
	var out_port := a if _is_output(a) else b
	var in_port := b if out_port == a else a
	var cut := graph != null and graph.is_linked(out_port, in_port)
	var done := PipeGraph.unlink(out_port, in_port, tool) if cut else PipeGraph.link(out_port, in_port, tool)
	status = "%s %s to %s" % [("cut" if cut else "patched") if done else ("could not cut" if cut else "could not patch"),
			PipeGraph.short_name(PipeGraph.label_of(out_port), 14), PipeGraph.short_name(PipeGraph.label_of(in_port), 14)]
	show_graph(PipeGraph.fetch(tool))
	mark_dirty()
	return done


func _is_output(port: String) -> bool:
	if _outputs.has(port):
		return true
	if graph == null:
		return false
	var node := PipeGraph.node_of(port)
	return graph.nodes.has(node) and port in (graph.nodes[node]["outputs"] as Array)


static func _port_words(port: String) -> String:
	return "%s %s" % [PipeGraph.short_name(PipeGraph.node_of(port), 16).to_upper(),
			PipeGraph.short_name(PipeGraph.label_of(port), 18).to_upper()]


func _describe(out_key: String, in_key: String) -> PackedStringArray:
	var n := int(_links.get(out_key + "|" + in_key, 0))
	if out_key.begins_with(GROUP) or in_key.begins_with(GROUP):
		var a := PipeGraph.short_name(out_key.trim_prefix(GROUP), 18).to_upper() if out_key.begins_with(GROUP) else _port_words(out_key)
		var b := PipeGraph.short_name(in_key.trim_prefix(GROUP), 18).to_upper() if in_key.begins_with(GROUP) else _port_words(in_key)
		var folded := matrix.is_collapsed(out_key) or matrix.is_collapsed(in_key)
		return PackedStringArray(["%s  →  %s" % [a, b], "%d link%s" % [n, "" if n == 1 else "s"],
				"click to open the folded node" if folded else "patch its ports, below and to the right"])
	var said := "patched" if n > 0 else "not patched"
	if n > 0 and metered(out_key):
		var m := port_level(out_key)
		said = "patched · %s" % ("carrying %s" % SignalGraph.db_words(m.x) if is_finite(m.x) and m.x > SignalGraph.FLOOR_DB else "no signal just now")
	elif n > 0:
		said = "patched · level not measured: PipeWire reports none for this port"
	return PackedStringArray(["%s  →  %s" % [_port_words(out_key), _port_words(in_key)], said,
			"click to cut this link" if n > 0 else "click to patch these two ports"])


func _describe_line(line: Dictionary, is_row: bool) -> PackedStringArray:
	var key: String = line["key"]
	var links := 0
	for k in _links:
		var parts := (k as String).split("|")
		if parts[0 if is_row else 1] == key and not parts[1 if is_row else 0].begins_with(GROUP):
			links += int(_links[k])
	if line.get("group", false):
		var folded := matrix.is_collapsed(key)
		return PackedStringArray(["%s  %s" % [PipeGraph.short_name(key.trim_prefix(GROUP), 28).to_upper(),
				"OUTPUTS" if is_row else "INPUTS"], "%d ports · %d links" % [int(line.get("count", 0)), links],
				"click to open its ports" if folded else "click to fold its ports away"])
	var hint := "its %s lights · drag or wheel here to scroll" % ("row" if is_row else "column")
	if not metered(key):
		hint += " · no meter: PipeWire gives no port levels, so only dawlings's own streams are metered"
	return PackedStringArray(["%s  %s" % [_port_words(key), "OUT" if is_row else "IN"],
			"not patched" if links == 0 else "patched to %d" % links, hint])


# --- levels ------------------------------------------------------------------------------------

## The node names whose ports this process can meter, and how: a dawlings stream by its bus.
const OWN_STREAMS := {"dawlings_mix": AudioPorts.MIX, "dawlings_monitor": AudioPorts.MONITOR,
		"dawlings_gear": AudioPorts.GEAR}


## How loud port (or a node's group line) `key` is: Vector3(peak dBFS, NAN, SignalGraph.MEASURED)
## for one of dawlings's own streams or, on Reaper, the DAW's outputs and the tap they feed;
## SignalGraph.UNKNOWN for anything else (PipeWire reports no levels: see the class note).
func port_level(key: String) -> Vector3:
	var unknown := Vector3(-INF, NAN, SignalGraph.UNKNOWN)
	var group := key.begins_with(GROUP)
	var node := key.trim_prefix(GROUP) if group else PipeGraph.node_of(key)
	var side := 0 if group else _side_of(PipeGraph.label_of(key))
	if OWN_STREAMS.has(node) or node == "dawlings" or node == "Godot Engine":
		var bus := AudioServer.get_bus_index(AudioPorts.bus(OWN_STREAMS[node])) if OWN_STREAMS.has(node) else 0
		if bus < 0:
			return unknown
		var l := AudioServer.get_bus_peak_volume_left_db(bus, 0)
		var r := AudioServer.get_bus_peak_volume_right_db(bus, 0)
		var db := l if side < 0 else (r if side > 0 else maxf(l, r))
		return Vector3(db if db > -150.0 else -INF, NAN, SignalGraph.MEASURED)
	if DAW.backend is ReaperBackend and DAW.state != null and (node == MixTap.TAP or _daw_node().search(node) != null):
		var vu := DAW.state.master.vu_l if side < 0 else (DAW.state.master.vu_r if side > 0 else maxf(DAW.state.master.vu_l, DAW.state.master.vu_r))
		return Vector3(FaderLaw.to_db(vu), NAN, SignalGraph.MEASURED)
	return unknown


static var _daw_re: RegEx = null


static func _daw_node() -> RegEx:
	if _daw_re == null:
		_daw_re = RegEx.create_from_string(MixTap.DAW_NODE)
	return _daw_re


## Which side a port's name says it carries: -1 left, 1 right, 0 either or both.
static func _side_of(label: String) -> int:
	var l := label.to_upper()
	if l.ends_with("FL") or l.ends_with("_L") or l.ends_with("LEFT") or l.ends_with("_1"):
		return -1
	if l.ends_with("FR") or l.ends_with("_R") or l.ends_with("RIGHT") or l.ends_with("_2"):
		return 1
	return 0


## Whether `key`'s level is known here: for the cards.
func metered(key: String) -> bool:
	return port_level(key).z != SignalGraph.UNKNOWN


# --- the screen ---------------------------------------------------------------------------------

func _quad(size: Vector2, at: Vector3, colour: Color) -> void:
	var box := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	box.mesh = quad
	box.position = at
	box.material_override = _paint(colour)
	_adopt(box)


func _text(text: String, at: Vector3, tint: Color, size := 36) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.pixel_size = 0.0017
	label.font_size = size
	label.modulate = tint
	label.position = at
	label.outline_size = 0
	label.double_sided = false
	Lettering.range_to_legibility(label)
	_adopt(label)
	return label


func _note(text: String, y: float, size := 36, tint := DIM) -> void:
	var label := _text(text, Vector3(0, y, 0.003), tint, size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## A surface that lights itself: the room it hangs in is dim.
static func _paint(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## A node's colour, from its name, so a device's jacks, header and cables read as one family.
## from the venue's own palette (the one the console's tracks wear), never its neutral.
static func _tint(node: String) -> Color:
	var colours := TrackColours.palette()
	return colours[hash(node) % (colours.size() - 1)]


## The screen's ground: the venue's gear, much darkened.
static func _panel() -> Color:
	return Materials.chassis().albedo_color.darkened(0.55)


## The venue's trim colour, for the title and the frame.
static func _brass() -> Color:
	return Materials.trim().albedo_color.lightened(0.25)


func _dress_key() -> String:
	return "%s|%s|%s" % [TrackColours.palette()[0].to_html(), _panel().to_html(), _brass().to_html()]


## A frame of the venue's trim round the screen, a lit solid so it catches the room's light.
func _frame(size: Vector2, at: Vector3) -> void:
	var bars := [
		[Vector3(size.x + FRAME * 2.0, FRAME, 0.04), Vector3(0, size.y * 0.5 + FRAME * 0.5, 0)],
		[Vector3(size.x + FRAME * 2.0, FRAME, 0.04), Vector3(0, -size.y * 0.5 - FRAME * 0.5, 0)],
		[Vector3(FRAME, size.y, 0.04), Vector3(-size.x * 0.5 - FRAME * 0.5, 0, 0)],
		[Vector3(FRAME, size.y, 0.04), Vector3(size.x * 0.5 + FRAME * 0.5, 0, 0)],
	]
	for bar in bars:
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = bar[0]
		m.mesh = box
		m.position = at + bar[1] + Vector3(0, 0, -0.012)
		m.material_override = Materials.trim()
		_adopt(m)


## The back of the wall: a solid case behind the frame, so from behind it is a piece of hardware
## with a nameplate and not a see-through screen with jacks and cables floating in front of it
## (the panel and boxes are one-sided quads). Flush with the frame's outside edge.
func _casing(size: Vector2, at: Vector3) -> void:
	var case := MeshInstance3D.new()
	case.name = "Casing"
	var box := BoxMesh.new()
	box.size = Vector3(size.x + FRAME * 2.0, size.y + FRAME * 2.0, 0.05)
	case.mesh = box
	case.position = at + Vector3(0, 0, -0.012 - 0.02 - 0.025)
	case.material_override = Materials.chassis()
	_adopt(case)
	# A rim in the venue's trim round the back, and ribs across it, so it reads as a built case.
	var back_z := at.z - 0.012 - 0.02 - 0.05
	var full := Vector2(size.x + FRAME * 2.0, size.y + FRAME * 2.0)
	var ribs: Array = [
		[Vector3(full.x, 0.04, 0.03), Vector3(0, full.y * 0.5 - 0.02, 0)],
		[Vector3(full.x, 0.04, 0.03), Vector3(0, -full.y * 0.5 + 0.02, 0)],
		[Vector3(0.04, full.y, 0.03), Vector3(-full.x * 0.5 + 0.02, 0, 0)],
		[Vector3(0.04, full.y, 0.03), Vector3(full.x * 0.5 - 0.02, 0, 0)],
	]
	for k in range(1, 4):
		ribs.append([Vector3(full.x, 0.03, 0.02), Vector3(0, full.y * (0.5 - k * 0.25), 0)])
	for rib in ribs:
		var bar := MeshInstance3D.new()
		var bar_mesh := BoxMesh.new()
		bar_mesh.size = rib[0]
		bar.mesh = bar_mesh
		bar.position = Vector3(at.x, at.y, back_z - 0.012) + rib[1]
		bar.material_override = Materials.trim()
		_adopt(bar)
	# Turned to face whoever is behind it, on the case's back face.
	var plate := Label3D.new()
	plate.text = "AUDIO DEVICES  ·  PATCH WALL"
	plate.pixel_size = 0.0017
	plate.font_size = 56
	plate.modulate = _brass()
	plate.outline_size = 0
	plate.double_sided = false
	plate.rotation.y = PI
	plate.position = at + Vector3(0, size.y * 0.5 - 0.06, -0.012 - 0.02 - 0.05 - 0.03)
	_adopt(plate)
