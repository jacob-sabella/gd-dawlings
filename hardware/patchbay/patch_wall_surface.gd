class_name PatchWallSurface
extends Surface

## The audio devices' patchbay, as a wall: every node PipeWire has -- the interface, the apps, the
## dawlings streams -- as a box of ports, the ones that make sound down the left and the ones that
## take it down the right, a cable for each link between them (PipeGraph). The Carla / qpwgraph
## picture, big enough to stand in front of. It reads the machine's own graph and follows it.
##
## Patching is by hand: press on a port and drag a cable to a port of the other kind to patch the
## two, or onto one it is already patched to, to cut that cable (PatchJack). It is the machine's
## own graph and the player's own hands, so nothing about it is shared with the session.

const WIDTH := 5.2
const BOX_WIDTH := 1.7
const ROW := 0.13
const HEAD := 0.17
const GAP := 0.11
## The most port rows in a column; the rest are counted at its foot rather than drawn off the wall.
const MAX_ROWS := 12
const REFRESH_SECONDS := 2.0
const CABLE_LIMIT := 150
const RIBBON := 0.022
const RIBBON_STEPS := 28

const INK := Color(0.92, 0.94, 0.98)
const DIM := Color(0.72, 0.75, 0.82)
## How wide the frame round the screen is.
const FRAME := 0.10

## The graph on the wall. Set it to show one; otherwise the machine's own is fetched.
var graph: PipeGraph
## What is asked for the graph (PipeGraph.fetch), a stand-in for the suite.
var tool := "pw-link"
## Whether the machine is asked again every few seconds. Off for the suite.
var follow := true
var cables := 0
var height := 0.0

## What the last patch or cut did, said in the footer.
var status := ""
var _shown := ""
## {port: PatchJack} and where each port's jack is, in this surface's space.
var _jacks := {}
var _jack_at := {}
var _drag := {}
## What the screen was dressed in (the venue's palette and gear), so a venue change redraws it.
var _dressed := ""
var _thread: Thread
var _next_ask := 0.0
var _hidden := {"outputs": 0, "inputs": 0}
## Which page each column is showing, and how many it has.
var _page := {"outputs": 0, "inputs": 0}
var _page_count := {"outputs": 1, "inputs": 1}


func _ready() -> void:
	surface_id = &"patch_wall"
	surface_kind = &"patchwall"
	super()


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
	_jacks.clear()
	_jack_at.clear()
	_drag.clear()
	_dressed = _dress_key()
	if graph == null:
		_shown = ""
		_note("listening to the audio graph...", -0.1, 48)
		height = 0.3
		return
	_shown = graph.signature()
	if not graph.error.is_empty():
		_note(graph.error, -0.1, 48)
		height = 0.3
		return
	var linked := {}
	for link in graph.links:
		linked[link[0]] = true
		linked[link[1]] = true
	var jacks := {}
	var top := 0.45
	var left := _column(true, -WIDTH * 0.5, top, jacks, linked)
	var right := _column(false, WIDTH * 0.5 - BOX_WIDTH, top, jacks, linked)
	height = maxf(left, right) + 0.3
	_quad(Vector2(WIDTH + 0.16, height), Vector3(0, -height * 0.5 + 0.08, -0.006), _panel(), 0.0)
	_frame(Vector2(WIDTH + 0.16, height), Vector3(0, -height * 0.5 + 0.08, 0.0))
	_casing(Vector2(WIDTH + 0.16, height), Vector3(0, -height * 0.5 + 0.08, 0.0))
	_note("AUDIO DEVICES", -0.05, 56, _brass())
	for link in graph.links:
		for end in link:
			if _jacks.has(end):
				(_jacks[end] as PatchJack).patches += 1
	var counts := "%d nodes · %d links" % [graph.nodes.size(), graph.links.size()]
	_note(counts if status.is_empty() else "%s · %s" % [counts, status], -height + 0.1, 34)
	var ribbons := ImmediateMesh.new()
	for link in graph.links:
		if cables >= CABLE_LIMIT:
			break
		if not jacks.has(link[0]) or not jacks.has(link[1]):
			continue
		_ribbon(ribbons, jacks[link[0]], jacks[link[1]], _tint(PipeGraph.node_of(link[0])))
		cables += 1
	var mesh := MeshInstance3D.new()
	mesh.mesh = ribbons
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = m
	_adopt(mesh)


## A cable as a ribbon along a curve that leaves one port going sideways and arrives going
## sideways, as a patchbay program draws it; one strip into `into`, joined to the last by a
## degenerate pair.
func _ribbon(into: ImmediateMesh, from: Vector3, to: Vector3, tint: Color) -> void:
	var run := maxf(absf(to.x - from.x) * 0.5, 0.15)
	var c1 := from + Vector3(run, 0, 0)
	var c2 := to - Vector3(run, 0, 0)
	into.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in RIBBON_STEPS + 1:
		var t := float(i) / RIBBON_STEPS
		var u := 1.0 - t
		var at := from * (u * u * u) + c1 * (3.0 * u * u * t) + c2 * (3.0 * u * t * t) + to * (t * t * t)
		var ahead := (c1 - from) * (3.0 * u * u) + (c2 - c1) * (6.0 * u * t) + (to - c2) * (3.0 * t * t)
		var side := Vector3(-ahead.y, ahead.x, 0.0).normalized() * RIBBON * 0.5
		into.surface_set_color(tint)
		into.surface_add_vertex(at + side)
		into.surface_set_color(tint)
		into.surface_add_vertex(at - side)
	into.surface_end()


## The boxes of one column, packed into pages of at most MAX_ROWS port rows: [{node, from, to}] a
## page, the ports `from` to `to` of that node. A node with more ports than a page holds is cut
## across pages, so every port is somewhere a hand can reach however large the graph.
func _pages(outputs: bool) -> Array:
	var key := "outputs" if outputs else "inputs"
	var pages: Array = []
	var page: Array = []
	var rows := 0
	for node in graph.nodes_by_use():
		var count: int = (graph.nodes[node][key] as Array).size()
		var at := 0
		while at < count:
			if rows >= MAX_ROWS:
				pages.append(page)
				page = []
				rows = 0
			var take := mini(count - at, MAX_ROWS - rows)
			page.append({"node": node, "from": at, "to": at + take})
			rows += take
			at += take
	if not page.is_empty():
		pages.append(page)
	return pages


## One column of node boxes, top down; fills `jacks` with where each port's jack is. Returns how
## far down it went. Shows the column's current page, with its pager at the foot when there is
## more than one.
func _column(outputs: bool, x: float, top: float, jacks: Dictionary, linked: Dictionary) -> float:
	var key := "outputs" if outputs else "inputs"
	var y := -top
	var pages := _pages(outputs)
	_page_count[key] = pages.size()
	_page[key] = clampi(int(_page.get(key, 0)), 0, maxi(pages.size() - 1, 0))
	var shown: Array = pages[_page[key]] if not pages.is_empty() else []
	var total := 0
	for pg in pages:
		for part in pg:
			total += int(part["to"]) - int(part["from"])
	for part in shown:
		var node: String = part["node"]
		var ports: Array = (graph.nodes[node][key] as Array).slice(part["from"], part["to"])
		var tint := _tint(node)
		var tall := HEAD + ports.size() * ROW + 0.02
		_quad(Vector2(BOX_WIDTH + 0.012, tall + 0.012), Vector3(x + BOX_WIDTH * 0.5, y - tall * 0.5, -0.003), tint.darkened(0.45), 0.0)
		_quad(Vector2(BOX_WIDTH, tall), Vector3(x + BOX_WIDTH * 0.5, y - tall * 0.5, -0.001), _panel().lightened(0.10), 0.0)
		_quad(Vector2(BOX_WIDTH, HEAD), Vector3(x + BOX_WIDTH * 0.5, y - HEAD * 0.5, 0.0), tint.darkened(0.15), 0.0)
		var cut := " (%d-%d)" % [int(part["from"]) + 1, part["to"]] \
				if ports.size() < (graph.nodes[node][key] as Array).size() else ""
		var title := _text(PipeGraph.short_name(node, 24) + cut, Vector3(x + 0.1, y - HEAD * 0.5, 0.003), Color(0.04, 0.05, 0.07), 50)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		for i in ports.size():
			var port: String = ports[i]
			var py := y - HEAD - (i + 0.5) * ROW - 0.01
			var used: bool = linked.has(port)
			var side := x + BOX_WIDTH if outputs else x
			var jack := MeshInstance3D.new()
			var disc := CylinderMesh.new()
			disc.top_radius = 0.04
			disc.bottom_radius = 0.04
			disc.height = 0.012
			jack.mesh = disc
			jack.rotation_degrees = Vector3(90, 0, 0)
			jack.position = Vector3(side, py, 0.003)
			jack.material_override = _paint(tint if used else tint.darkened(0.6))
			_adopt(jack)
			jacks[port] = Vector3(side, py, 0.014)
			var grab := PatchJack.create(port, outputs, tint, Vector2(BOX_WIDTH, ROW * 0.96))
			grab.position = Vector3(x + BOX_WIDTH * 0.5, py, 0.004)
			grab.drag_began.connect(_on_drag_began)
			grab.drag_moved.connect(_on_drag_moved)
			grab.drag_finished.connect(_on_drag_finished)
			_adopt(grab)
			_jacks[port] = grab
			_jack_at[port] = Vector3(side, py, 0.014)
			var label := _text(PipeGraph.short_name(PipeGraph.label_of(port), 30), Vector3(x + BOX_WIDTH - 0.1 if outputs else x + 0.1, py, 0.003),
					INK if used else DIM, 46)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if outputs else HORIZONTAL_ALIGNMENT_LEFT
		y -= tall + GAP
	_hidden[key] = total - _shown_ports(shown)
	if pages.size() > 1:
		_pager(key, x, y - 0.02, pages.size(), total)
		y -= 0.16
	return -y


func _shown_ports(shown: Array) -> int:
	var n := 0
	for part in shown:
		n += int(part["to"]) - int(part["from"])
	return n


## The foot of a paged column: back, the page it is on, forward. Pressed buttons turn the page
## and the wall redraws.
func _pager(key: String, x: float, y: float, count: int, total: int) -> void:
	var cx := x + BOX_WIDTH * 0.5
	_text("PAGE %d / %d  ·  %d PORTS" % [int(_page[key]) + 1, count, total], Vector3(cx, y - 0.05, 0.003), DIM, 34)
	for step in [-1, 1]:
		var button := PanelButton.new()
		button.scale = Vector3.ONE * 6.0
		button.hit_pad = Vector2(1.6, 2.6)
		button.led_colour = Color(0.45, 0.68, 0.95)
		button.position = Vector3(cx + step * (BOX_WIDTH * 0.5 - 0.1), y - 0.05, 0.006)
		button.pressed.connect(_turn_page.bind(key, step, count))
		_adopt(button)
		var glyph := _text("<" if step < 0 else ">", Vector3(cx + step * (BOX_WIDTH * 0.5 - 0.1), y - 0.05, 0.032), INK, 40)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _turn_page(key: String, step: int, count: int) -> void:
	_page[key] = posmod(int(_page[key]) + step, count)
	mark_dirty()


# --- carrying a cable ---------------------------------------------------------------------

func _on_drag_began(from: ControlAffordance, at: Vector3) -> void:
	var jack := from as PatchJack
	if jack == null:
		return
	var carried := MeshInstance3D.new()
	carried.name = "CarriedCable"
	carried.mesh = ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	carried.material_override = m
	_adopt(carried)
	_drag = {"from": jack, "cable": carried, "target": null}
	for other in _candidates(jack):
		other.set_light(PatchJack.Light.CUT if graph.is_linked(_pair(jack, other)[0], _pair(jack, other)[1]) else PatchJack.Light.CANDIDATE)
	_draw_carried(to_local(at))


func _on_drag_moved(from: ControlAffordance, at: Vector3, over: ControlAffordance) -> void:
	if _drag.is_empty() or _drag["from"] != from:
		return
	var target := _target_for(from as PatchJack, over)
	_drag["target"] = target
	var end := to_local(at)
	if target != null:
		end = _jack_at[target.port]
	_draw_carried(end)


func _on_drag_finished(from: ControlAffordance, over: ControlAffordance) -> void:
	if _drag.is_empty() or _drag["from"] != from:
		return
	var jack := from as PatchJack
	var target := _target_for(jack, over)
	var carried: MeshInstance3D = _drag["cable"]
	if is_instance_valid(carried):
		carried.queue_free()
	_drag.clear()
	for other in _jacks.values():
		(other as PatchJack).set_light(PatchJack.Light.PLAIN)
	if target != null:
		patch(jack.port, target.port)


## Patches two ports, or cuts the patch between them if they are already patched: the output
## first, whichever the hand started from. Then reads the graph again, so the wall shows it.
func patch(a: String, b: String) -> bool:
	var out_port := a if (_jacks.has(a) and (_jacks[a] as PatchJack).is_output) else b
	var in_port := b if out_port == a else a
	var cut := graph != null and graph.is_linked(out_port, in_port)
	var done := PipeGraph.unlink(out_port, in_port, tool) if cut else PipeGraph.link(out_port, in_port, tool)
	status = "%s %s to %s" % [("cut" if cut else "patched") if done else ("could not cut" if cut else "could not patch"),
			PipeGraph.short_name(PipeGraph.label_of(out_port), 14), PipeGraph.short_name(PipeGraph.label_of(in_port), 14)]
	show_graph(PipeGraph.fetch(tool))
	mark_dirty()
	return done


## The ports a cable carried from `from` could be let go on: the other kind, on any node.
func _candidates(from: PatchJack) -> Array[PatchJack]:
	var out: Array[PatchJack] = []
	for jack in _jacks.values():
		if (jack as PatchJack).is_output != from.is_output:
			out.append(jack)
	return out


func _target_for(from: PatchJack, over: ControlAffordance) -> PatchJack:
	if from == null or not (over is PatchJack):
		return null
	return over if over in _candidates(from) else null


func _pair(a: PatchJack, b: PatchJack) -> Array:
	return [a.port, b.port] if a.is_output else [b.port, a.port]


func _draw_carried(end: Vector3) -> void:
	if _drag.is_empty():
		return
	var from: PatchJack = _drag["from"]
	var mesh := (_drag["cable"] as MeshInstance3D).mesh as ImmediateMesh
	mesh.clear_surfaces()
	var start: Vector3 = _jack_at[from.port]
	if from.is_output:
		_ribbon(mesh, start, end, from.tint)
	else:
		_ribbon(mesh, end, start, from.tint)


func _quad(size: Vector2, at: Vector3, colour: Color, glow: float) -> void:
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
