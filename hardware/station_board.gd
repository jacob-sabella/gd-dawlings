class_name StationBoard
extends Node3D

## Every instrument that stands here, as a row to press to go to it (docs/spatial_loop.md part
## two, slice 11): how a headset player, whose play space is two metres square, reaches stations
## several metres behind the desk. A press travels there (XRRig.travel, a cut behind a blink);
## on a desktop the same press walks there (Studio.go_to_station), so the board is one more way in
## beside I and the help card's PLAY lines, not a headset's alone.
##
## Two of them. The board on its stand by the desk, at the mix position, with its title and the
## line that says how it works; and the same rows beside a station's plaque, put up by the
## plaque's INSTRUMENTS key (`compact`, no stand) until a row or INSTRUMENTS is pressed again.
##
## Its rows are the PLAY pages' stations (`rows_for`): Stations.by_area, an area at a time in the
## card's order, each area under its name. A row is a key a fingertip pokes, a pinch's ray or a
## trigger presses, a cursor clicks or a gaze dwells on, and its hover card says what it is.
##
## Where travel is refused (a co-located room, Studio.travel_refusal), the board says so on its
## face: `refuse(reason)` letters CAN'T GO and the reason on the line under the rows, so the
## press that did nothing is answered where it was made, in words and not by a colour.

## A row was pressed: station `id` (a Stations id).
signal chosen(id: StringName)

## The face's width, and a row's size on it: wide enough for the longest title at ROW_CAP, and
## tall enough that from the desk's seat (about a metre off, and the plaques' several) it is a
## target a cursor can rest on (the seat audit's 7 px).
const WIDTH := 0.36
const ROW := Vector2(0.32, 0.062)
const ROW_GAP := 0.012
## The most a column of rows runs down the face (m). Past it the rows go on in a column beside,
## so a venue with many stations makes the board wider rather than long enough to lean into the
## floor; an area is split across columns only when it alone is taller than this.
const COLUMN_TALL := 0.78
## Letter heights (m): the title, the rows, the areas' names and the small print (the line that
## says how it works, and a refusal), each legible from where it is read (Lettering).
const TITLE_CAP := 0.028
const ROW_CAP := 0.024
const AREA_CAP := 0.015
const SMALL_CAP := 0.014
const PIXEL := 0.00025
const PAD := 0.02
## What the board says on its face, under its title.
const FACE_LINE := "press a row to go there · BACK on any plaque comes home"
## What a refusal starts with: the words, not only the warm colour of the line.
const REFUSED := "CAN'T GO"
## How long a refusal stays on the face.
const REFUSAL_SECONDS := 8.0
## The stand's face: how far it leans back from upright (35 degrees), and how high its top edge is.
const TILT := 0.61
const FACE_TOP := 1.2
## The stand's foot on the floor, half its size: what the walker and the trolleys stand clear of.
const FOOT := Vector2(0.17, 0.14)

const INK := Color(0.04, 0.037, 0.035)
const LETTER := Color(0.95, 0.9, 0.78)
const SMALL := Color(0.82, 0.8, 0.76)
const WARN := Color(1.0, 0.72, 0.42)

## Rows only, no stand, title or line: the rows beside a plaque.
var compact := false
## The venue whose stations are the rows (Stations.by_area); none lists every station.
var venue: Venue = null
## Why travel was last refused, while the face says so; empty otherwise.
var refusal := ""

var _face: Node3D
var _stand: Node3D
var _rows: Dictionary = {}
var _why: Label3D
var _refused_at := 0
var _height := 0.0
var _width := WIDTH


func _ready() -> void:
	_build_face()


## Show `v`'s stations.
func set_venue(v: Venue) -> void:
	venue = v
	if is_inside_tree():
		_build_face()


## The stations a board lists in `venue`, in the order it lists them: the PLAY pages' stations,
## an area at a time in the card's order (Stations.AREAS).
static func rows_for(v: Venue) -> Array[StringName]:
	var out: Array[StringName] = []
	var here := Stations.by_area(v)
	for area in Stations.AREAS:
		for r: Dictionary in here[area]:
			out.append(r["id"])
	return out


## The stations this board shows, in order.
func rows() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _rows:
		out.append(id)
	return out


## Station `id`'s row, or null.
func row(id: StringName) -> Row:
	return _rows.get(id) as Row


## The face's height (m), title to its last line.
func face_height() -> float:
	return _height


## The face's width (m): WIDTH a column of rows. Known before the face is built, so the rows
## beside a plaque can be stood clear of it as they are put up.
func face_width() -> float:
	return _width if _face != null else WIDTH * _columns(Stations.by_area(venue)).size()


## Say on the face that travel was refused, and why, for REFUSAL_SECONDS.
func refuse(reason: String) -> void:
	refusal = reason
	_refused_at = Time.get_ticks_msec()
	if _why != null:
		_why.text = "%s · %s" % [REFUSED, reason]
		_why.visible = true


## Take a refusal off the face.
func clear_refusal() -> void:
	refusal = ""
	if _why != null:
		_why.text = ""
		_why.visible = false


func _process(_delta: float) -> void:
	if refusal != "" and Time.get_ticks_msec() - _refused_at > int(REFUSAL_SECONDS * 1000.0):
		clear_refusal()


## The face, rebuilt from the venue's stations: its top edge at the node's origin (or the stand's
## top), lettering out along +Z.
func _build_face() -> void:
	if _face != null:
		remove_child(_face)
		_face.queue_free()
	_rows.clear()
	_face = Node3D.new()
	_face.name = "Face"
	if not compact:
		_face.transform = Transform3D(Basis(Vector3.RIGHT, -TILT), Vector3(0, FACE_TOP, 0))
	add_child(_face)
	var here := Stations.by_area(venue)
	var columns := _columns(here)
	_width = WIDTH * columns.size()
	var inner := _width - PAD * 2.0
	var y := -PAD
	if not compact:
		var title := _letter("INSTRUMENTS", TITLE_CAP, LETTER, y)
		title.name = "Title"
		y -= TITLE_CAP * 1.6
		var line := _letter(FACE_LINE, SMALL_CAP, SMALL, y, inner)
		line.name = "Says"
		y -= _lines(FACE_LINE, inner, SMALL_CAP) * SMALL_CAP * 1.45 + 0.012
	var top := y
	var lowest := y
	for c in columns.size():
		var x := (c - (columns.size() - 1) * 0.5) * WIDTH
		y = top
		for block: Dictionary in columns[c]:
			var area: StringName = block["area"]
			var heading := _letter(Stations.AREA_TITLES[area], AREA_CAP, SMALL, y)
			heading.name = "Area_%s_%d" % [area, c] if block["more"] else "Area_%s" % area
			heading.position.x = x
			y -= AREA_CAP * 1.6
			for r: Dictionary in block["rows"]:
				var key := Row.new()
				key.name = "Row_%s" % r["id"]
				key.board = self
				key.station = r["id"]
				key.legend = r["title"]
				key.area_title = Stations.AREA_TITLES[area]
				key.position = Vector3(x, y - ROW.y * 0.5, 0)
				_face.add_child(key)
				_rows[r["id"]] = key
				y -= ROW.y + ROW_GAP
		lowest = minf(lowest, y)
	y = lowest
	# Room for two lines of refusal, kept whether one is showing or not, so the face does not
	# change size under a hand.
	_why = _letter(("%s · %s" % [REFUSED, refusal]) if refusal != "" else "", SMALL_CAP, WARN, y - 0.004, inner)
	_why.name = "Why"
	_why.visible = refusal != ""
	y -= SMALL_CAP * 1.45 * 2.0 + PAD
	_height = -y
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	var box := BoxMesh.new()
	box.size = Vector3(_width, _height, 0.01)
	plate.mesh = box
	plate.position = Vector3(0, -_height * 0.5, -0.005)
	var ink := StandardMaterial3D.new()
	ink.albedo_color = INK
	ink.roughness = 0.9
	plate.material_override = ink
	_face.add_child(plate)
	if not compact:
		_build_stand()


## The rows laid out in columns of at most COLUMN_TALL: a list per column of blocks, each an
## area's name and its rows (`more` on an area carried on from the column before). Areas are
## kept whole where they fit, in the card's order.
static func _columns(here: Dictionary) -> Array:
	var head := AREA_CAP * 1.6
	var step := ROW.y + ROW_GAP
	var columns: Array = [[]]
	var used := 0.0
	for area in Stations.AREAS:
		var listed: Array = here[area]
		if listed.is_empty():
			continue
		var whole := head + step * listed.size()
		if used > 0.0 and used + whole > COLUMN_TALL and whole <= COLUMN_TALL:
			columns.append([])
			used = 0.0
		var block := {"area": area, "rows": [], "more": false}
		columns[-1].append(block)
		used += head
		for r in listed:
			if used + step > COLUMN_TALL and not (block["rows"] as Array).is_empty():
				columns.append([])
				block = {"area": area, "rows": [], "more": true}
				columns[-1].append(block)
				used = head
			(block["rows"] as Array).append(r)
			used += step
	return columns


## How far forward of the node the face's middle is over the floor (m): the leant face's bottom
## edge comes out toward whoever reads it.
func _middle_z() -> float:
	return _height * 0.5 * sin(TILT)


## Where the stand stands, as a FloorPlan footprint in the parent's frame: what the walker and
## the trolleys keep clear of. Empty for the rows beside a plaque, which stand on nothing.
func footprint() -> Dictionary:
	if compact:
		return {}
	var middle := transform * Vector3(0, 0, _middle_z())
	return FloorPlan.footprint(Vector2(middle.x, middle.z), FOOT, rotation.y)


## A post on a foot, as a music stand's, up under the face's middle, behind it.
func _build_stand() -> void:
	if _stand != null:
		remove_child(_stand)
		_stand.queue_free()
	_stand = Node3D.new()
	_stand.name = "Stand"
	add_child(_stand)
	var z := _middle_z()
	var foot := MeshInstance3D.new()
	foot.name = "Foot"
	var foot_mesh := BoxMesh.new()
	foot_mesh.size = Vector3(FOOT.x * 2.0, 0.02, FOOT.y * 2.0)
	foot.mesh = foot_mesh
	foot.position = Vector3(0, 0.01, z)
	foot.material_override = Materials.furniture()
	_stand.add_child(foot)
	# Up to just behind the face's middle, where a bracket would hold it.
	var top := FACE_TOP - _height * 0.5 * cos(TILT)
	var post := MeshInstance3D.new()
	post.name = "Post"
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.035, top - 0.02, 0.035)
	post.mesh = post_mesh
	post.position = Vector3(0, 0.02 + (top - 0.02) * 0.5, z - 0.03)
	post.material_override = Materials.brushed_metal()
	_stand.add_child(post)


func _letter(text: String, cap: float, colour: Color, y: float, wrap := 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = PIXEL
	l.font_size = roundi(cap / PIXEL)
	l.modulate = colour
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.double_sided = false
	if wrap > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.width = wrap / PIXEL
	l.position = Vector3(0, y, 0.001)
	Lettering.range_to_legibility(l)
	_face.add_child(l)
	return l


## How many lines `text` takes at `cap`, wrapped to `width` metres.
static func _lines(text: String, width: float, cap: float) -> int:
	var f: Font = Lettering.face()
	if f == null:
		f = ThemeDB.fallback_font
	var size := roundi(cap / PIXEL)
	var per := width / PIXEL
	var lines := 1
	var run := 0.0
	var space := f.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	for word in text.split(" ", false):
		var w := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if run > 0.0 and run + space + w > per:
			lines += 1
			run = w
		else:
			run += (space if run > 0.0 else 0.0) + w
	return lines


## A board's row: a station's title on a key. Pressed, the board says which (`chosen`).
class Row extends ControlAffordance:
	var board: StationBoard
	var station := &""
	var legend := ""
	var area_title := ""

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		StationBoard.dress_key(self, StationBoard.ROW, legend, StationBoard.ROW_CAP)

	func _default_title() -> String:
		return "INSTRUMENTS  %s" % legend

	func _default_readout() -> String:
		return "in the %s" % area_title.to_lower()

	func hint() -> String:
		return "press to go there · BACK on its plaque comes home"

	func dwell_activates() -> bool:
		return true

	## Where this player goes is theirs: nobody else is told the row is held.
	func personal() -> bool:
		return true

	func _on_grab_begin(_at: Vector3) -> void:
		if board != null:
			board.chosen.emit(station)


## A key on a station's plaque (Stations.plaque): INSTRUMENTS, the board's rows beside the plaque,
## or BACK, home to the desk. Pressed, it asks whoever keeps the stations (an ancestor with
## `plaque_key`, the studio), so a plaque on a station stood anywhere else is a plaque and no more.
class PlaqueKey extends ControlAffordance:
	const INSTRUMENTS := &"instruments"
	const BACK := &"back"
	var station := &""
	var kind := INSTRUMENTS
	var size := Vector2(0.2, 0.07)

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		StationBoard.dress_key(self, size, "INSTRUMENTS" if kind == INSTRUMENTS else "BACK", 0.024)

	func _default_title() -> String:
		return "%s  %s" % [Stations.row(station).get("title", String(station)), "INSTRUMENTS" if kind == INSTRUMENTS else "BACK"]

	func hint() -> String:
		if kind == INSTRUMENTS:
			return "press for every instrument's row beside this plaque, again to put them away"
		return "press to go back to the desk"

	func dwell_activates() -> bool:
		return true

	func personal() -> bool:
		return true

	func _on_grab_begin(_at: Vector3) -> void:
		var keeper := get_parent()
		while keeper != null and not keeper.has_method("plaque_key"):
			keeper = keeper.get_parent()
		if keeper != null:
			keeper.plaque_key(station, kind, self)


## A plaque's title row, as a key: a press opens the how-to-play lines under it, or folds them
## away again (Stations.fold_plaque). Each player's own: it changes nothing anyone else sees.
class PlaqueFold extends ControlAffordance:
	var station := &""
	var size := Vector2(0.3, 0.06)

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(size.x, size.y, 0.02)
		shape.shape = box
		shape.position = Vector3(0, 0, 0.01)
		add_child(shape)

	func _default_title() -> String:
		return "%s  HOW TO PLAY" % Stations.row(station).get("title", String(station))

	func hint() -> String:
		var holder := get_parent() as Node3D
		if holder != null and Stations.plaque_open(holder):
			return "press to fold the how-to-play lines away"
		return "press for how to play it"

	func dwell_activates() -> bool:
		return true

	func personal() -> bool:
		return true

	func _on_grab_begin(_at: Vector3) -> void:
		var holder := get_parent() as Node3D
		if holder != null:
			Stations.fold_plaque(holder, not Stations.plaque_open(holder))


## A key's body: its collision box, a dark cap a little proud of what it is on, and its legend in
## light lettering (unshaded, so it reads however the corner is lit), as the harp's crown buttons.
static func dress_key(key: ControlAffordance, size: Vector2, legend: String, cap: float) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y, 0.02)
	shape.shape = box
	shape.position = Vector3(0, 0, 0.01)
	key.add_child(shape)
	var top := MeshInstance3D.new()
	top.name = "Cap"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x - 0.006, size.y - 0.006, 0.012)
	top.mesh = mesh
	top.position = Vector3(0, 0, 0.006)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.13, 0.1, 0.07)
	paint.roughness = 0.8
	top.material_override = paint
	key.add_child(top)
	var l := Label3D.new()
	l.name = "Legend"
	l.text = legend
	l.pixel_size = PIXEL
	l.font_size = roundi(cap / PIXEL)
	l.position = Vector3(0, 0, 0.0125)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.modulate = LETTER
	l.double_sided = false
	Lettering.range_to_legibility(l)
	key.add_child(l)
