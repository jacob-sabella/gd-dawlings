class_name PatchWallSurface
extends Surface

## The audio devices' patchbay, as a wall: every node PipeWire has -- the interface, the apps, the
## dawlings streams -- as a box of ports, the ones that make sound down the left and the ones that
## take it down the right, a cable for each link between them (PipeGraph). The Carla / qpwgraph
## picture, big enough to stand in front of. It reads the machine's own graph and follows it.
##
## Read only so far: it shows the patching, it does not yet make or break one.

const WIDTH := 3.4
const BOX_WIDTH := 1.0
const ROW := 0.075
const HEAD := 0.10
const GAP := 0.07
## The most port rows in a column; the rest are counted at its foot rather than drawn off the wall.
const MAX_ROWS := 16
const REFRESH_SECONDS := 2.0
const CABLE_LIMIT := 150
const RIBBON := 0.011
const RIBBON_STEPS := 28

const INK := Color(0.92, 0.94, 0.98)
const DIM := Color(0.55, 0.58, 0.64)
## How wide the frame round the screen is.
const FRAME := 0.07

## The graph on the wall. Set it to show one; otherwise the machine's own is fetched.
var graph: PipeGraph
## What is asked for the graph (PipeGraph.fetch), a stand-in for the suite.
var tool := "pw-link"
## Whether the machine is asked again every few seconds. Off for the suite.
var follow := true
var cables := 0
var height := 0.0

var _shown := ""
## What the screen was dressed in (the venue's palette and gear), so a venue change redraws it.
var _dressed := ""
var _thread: Thread
var _next_ask := 0.0
var _hidden := {"outputs": 0, "inputs": 0}


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
	if follow and _thread == null:
		_next_ask -= delta
		if _next_ask <= 0.0:
			_next_ask = REFRESH_SECONDS
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
	var top := 0.22
	var left := _column(true, -WIDTH * 0.5, top, jacks, linked)
	var right := _column(false, WIDTH * 0.5 - BOX_WIDTH, top, jacks, linked)
	height = maxf(left, right) + 0.16
	_quad(Vector2(WIDTH + 0.16, height), Vector3(0, -height * 0.5 + 0.08, -0.006), _panel(), 0.0)
	_frame(Vector2(WIDTH + 0.16, height), Vector3(0, -height * 0.5 + 0.08, 0.0))
	_note("AUDIO DEVICES", -0.02, 56, _brass())
	_note("%d nodes · %d links" % [graph.nodes.size(), graph.links.size()], -height + 0.06, 34)
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


## One column of node boxes, top down; fills `jacks` with where each port's jack is. Returns how
## far down it went.
func _column(outputs: bool, x: float, top: float, jacks: Dictionary, linked: Dictionary) -> float:
	var key := "outputs" if outputs else "inputs"
	var y := -top
	var rows := 0
	var skipped := 0
	for node in graph.nodes_by_use():
		var ports: Array = graph.nodes[node][key]
		if ports.is_empty():
			continue
		if rows + ports.size() > MAX_ROWS:
			skipped += ports.size()
			continue
		var tint := _tint(node)
		var tall := HEAD + ports.size() * ROW + 0.02
		_quad(Vector2(BOX_WIDTH + 0.012, tall + 0.012), Vector3(x + BOX_WIDTH * 0.5, y - tall * 0.5, -0.003), tint.darkened(0.45), 0.0)
		_quad(Vector2(BOX_WIDTH, tall), Vector3(x + BOX_WIDTH * 0.5, y - tall * 0.5, -0.001), _panel().lightened(0.10), 0.0)
		_quad(Vector2(BOX_WIDTH, HEAD), Vector3(x + BOX_WIDTH * 0.5, y - HEAD * 0.5, 0.0), tint.darkened(0.15), 0.0)
		var title := _text(PipeGraph.short_name(node, 22), Vector3(x + 0.05, y - HEAD * 0.5, 0.003), Color(0.04, 0.05, 0.07), 40)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		for i in ports.size():
			var port: String = ports[i]
			var py := y - HEAD - (i + 0.5) * ROW - 0.01
			var used: bool = linked.has(port)
			var side := x + BOX_WIDTH if outputs else x
			var jack := MeshInstance3D.new()
			var disc := CylinderMesh.new()
			disc.top_radius = 0.021
			disc.bottom_radius = 0.021
			disc.height = 0.008
			jack.mesh = disc
			jack.rotation_degrees = Vector3(90, 0, 0)
			jack.position = Vector3(side, py, 0.003)
			jack.material_override = _paint(tint if used else tint.darkened(0.6))
			_adopt(jack)
			jacks[port] = Vector3(side, py, 0.008)
			var label := _text(PipeGraph.label_of(port), Vector3(x + BOX_WIDTH - 0.06 if outputs else x + 0.06, py, 0.003),
					INK if used else DIM, 34)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if outputs else HORIZONTAL_ALIGNMENT_LEFT
		rows += ports.size()
		y -= tall + GAP
	_hidden[key] = skipped
	if skipped > 0:
		var more := _text("+%d more ports" % skipped, Vector3(x + 0.05, y - 0.04, 0.003), DIM, 34)
		more.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		y -= 0.1
	return -y


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
	label.pixel_size = 0.0009
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
