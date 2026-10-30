class_name PinMatrix
extends Node3D

## A pin matrix: every source down the left, every destination across the top, and a pin at each
## crossing. The routing bay's track sends (PatchbaySurface) and the audio devices' ports
## (PatchWallSurface) are both one of these, so they are worked the same way.
##
## WHY A MATRIX. A bay of cables reads a dozen patches well and fifty not at all, and the one with
## the most to say -- a return fed by everything -- is the one whose jacks run out first. A matrix
## has a place for every patch there could be: whether KICK goes to BASS DI is the one crossing at
## KICK's row and BASS DI's column, seated or empty, and nothing has to be followed across the
## panel to find out. The EMS Synthi and the old broadcast desks route this way for that reason.
##
## WHAT IS ON IT. Each header is a colour chip and the name, in text (a colour is never the only
## way a line is told apart). An empty crossing is a socket; a patched one has a pin seated in it,
## its head in the source's colour, and where the patch has a level (a send) a bar beside it as
## tall as the level is high. A crossing that cannot be patched (a track into itself, a send that
## would loop) has no socket at all, only a dash. A pin carrying signal pulses with it: brighter
## the louder what goes through it is (SignalBeads's level, so the light and the beads on every
## other cable in the room agree).
##
## WHAT YOU DO, with a mouse and a hand alike, through the one press-drag-release every control
## has (ControlAffordance):
##   - press and let go on a crossing: the pin goes in, or comes out
##   - drag a seated pin up or down: its level
##   - wheel a seated pin, or a controller's stick on it: its level
##   - drag anywhere else on the grid, or a header, or a scroll bar: the grid scrolls
##   - wheel a header, an empty socket or a bar: the grid scrolls; Shift-wheel goes sideways
## Pointing at a crossing lights its row and its column and dims everything else, so one track's
## routing reads out of a full grid; pointing at a header lights that one line.
##
## NO PAGES. However many lines there are, the grid shows as many as fit at a readable size and
## scrolls through the rest -- rows and columns each on their own, the headers pinned -- so a send
## from row 60 to column 3 is one drag and a press, not three page turns. The foot says where the
## window is ("ROWS 25-48 OF 64").
##
## GROUPS. A line can head a group (a PipeWire node over its ports): pressing its header folds the
## group away to one line that says how many it holds, and opens it again. A crossing with a group
## line counts the patches inside it, and pressing it opens the group.
##
## LEVELS, always (docs/spatial_loop.md part three, D). Where the owner says how loud a line is
## (`row_meter`, `col_meter`), each header carries a thin meter: the RMS as a fill, the peak as a
## tick that holds for HOLD_MSEC, and a light at its end -- a small amber square from
## SignalGraph.HOT_DB, a tall red bar past 0 dBFS, held CLIP_MSEC -- and its card says the figures
## and the clip in words. A column's meter is what arrives there, the sends into it added (worst
## case, peaks together), so a return fed by four quiet sends that would pass 0 dBFS together goes
## red although no one send is hot. A seated pin's head pulses with what its patch carries
## (`pin_meter`), dull while it carries nothing; an empty socket in a row over HOT_DB glows faintly,
## a place a loud line could go somewhere quieter. Read at METER_HZ, only for what the window shows,
## into lines and slots kept from the build: nothing is made while it runs.
##
## THE SKYLINE (part three, E). With `skyline` on (the owner's: the signal glasses), every seated
## pin with a level stands up out of the board as a column of light as tall as what it carries
## (SignalGraph.thickness, FLOOR_DB at the board to TOP_DB at `tower_max`), and each column's
## arrival as a tower on its header. Tops go amber from HOT_DB and red past 0 dBFS, each with its
## figure on a tag on the board at its foot ("+1.8 dB" past 0). Pointing lights a row and a column as ever. A tower's top is
## a control (`Tower`): drag it up or down, or pull it out of the board or push it in, for the send's
## level (`level_db` and `set_level_db`); the wheel steps it as a pin's does. One undo step a
## drag (`edits_as_one`); a guest's is an intent its host carries out, as every DAW write is. At
## Ergonomics.motion_scale 0 the towers stand still between readings and only move once a second.
##
## The matrix knows nothing of tracks or ports. Its owner gives it the lines (`set_lines`) and answers
## for each crossing through the callables below; whatever the owner says goes, so the DAW's
## routing rules and PipeWire's are each in one place.

## Words the owner wants said: a refusal, what a patch did. Also shown in the foot for a while.
signal said(words: String)
## The window moved.
signal scrolled()

## The strip of names left of the grid, and the strip above it (m).
var row_head := 0.24
var col_head := 0.16
## How tall a row and how wide a column may be, smallest and largest (m): as big as the panel
## allows, never smaller than can be read and hit from where it is used.
var row_pitch := Vector2(0.032, 0.05)
var col_pitch := Vector2(0.034, 0.06)
## The most the whole matrix may take, headers, bars and foot included (m).
var area := Vector2(1.0, 1.0)
## A scroll bar's thickness, and its arrow keys' size.
var bar := 0.026
var gap := 0.008
## The strip under it all that says where the window is, and what the last press did.
var foot := 0.045
## Label3D pixel size for the lettering, and the tallest a name's capitals may be (m).
var px := 0.0003
var name_cap := 0.02
## The colour chip beside a name: at most this big, and never more than most of its line.
var chip := 0.018
## What the two axes are, for the corner and the hover cards: "FROM" and "TO".
var row_word := "FROM"
var col_word := "TO"
var ink := Color(0.93, 0.92, 0.88)
var dim_ink := Color(0.58, 0.6, 0.64)
## The bands behind the lines at rest, and every other one a shade lighter, as a painted panel's
## colour (sRGB): the bands are self-lit, so they are taken to light's terms before they are drawn.
var ground := Color(0.10, 0.103, 0.115)
var ground_banded := Color(0.135, 0.138, 0.152)

## (row key, column key) -> Dictionary: "on" (a pin is seated), "level" (0..1 bar height, or -1
## for a patch with no level), "blocked" (cannot be patched), "pending" (asked for, not yet
## answered), "links" (for a crossing with a group: patches inside it), "tint" (the head's colour).
var pin_at: Callable = Callable()
## (row key, column key) -> String: put the pin in or take it out; what to say back, or "".
var toggle: Callable = Callable()
## (row key, column key, notches, fine) -> bool: a seated pin's level moved by `notches` steps.
var level: Callable = Callable()
## (row key, column key) -> PackedStringArray [title, readout, hint], for the hover card.
var describe: Callable = Callable()
## (line, is_row) -> PackedStringArray [title, readout, hint], for a header's hover card.
var describe_line: Callable = Callable()
## (row key, column key) -> float: how loud what goes through the pin is now, 0..1 on the fader
## law, for its pulse. Unset, pins do not pulse.
var signal_of: Callable = Callable()

## (row key) -> Vector3(peak dBFS, RMS dBFS or NAN, SignalGraph.MEASURED / ESTIMATED / UNKNOWN):
## how loud the row's line is now, for its header meter. Unset, rows have none.
var row_meter: Callable = Callable()
## (column key) -> Vector3(peak dBFS, how many feed it, how): what arrives at the column. Unset,
## columns have none.
var col_meter: Callable = Callable()
## (row key, column key) -> Vector3(peak dBFS, 0, how): what a seated pin carries. Set, the pins
## pulse with it rather than `signal_of`, dull while it is silent, and the skyline is as tall.
var pin_meter: Callable = Callable()
## (row key, column key) -> float: a seated pin's level setting (dB), and (row key, column key,
## dB) -> bool to set it: a tower's drag.
var level_db: Callable = Callable()
var set_level_db: Callable = Callable()
## The skyline: seated pins and column arrivals stand up out of the board. Set by the owner.
var skyline := false
## How tall a tower at SignalGraph.TOP_DB stands out of the board (m).
var tower_max := 0.24
## How tall a tag's capitals are on a tower top (m); 0 for the cell's own size.
var tag_cap := 0.0

## Group keys folded away.
var collapsed := {}

## A wheel notch scrolls this many lines.
const WHEEL_LINES := 3
## After a scroll, a wheel goes on scrolling for this long whatever it lands on, so a seated pin
## coming under a still pointer mid-scroll is not turned up by the next notch.
const WHEEL_LATCH_MSEC := 450
## How far a press has to move, as a share of a cell, before it is a drag and not a press.
const DRAG_FROM := 0.45
## A level drag: one step per this share of a row's height.
const LEVEL_STEP := 0.3
## How fast the window eases to where it was sent, per second.
const EASE := 18.0
## A pin's pulse: fast up, slow down, as the beads follow a meter.
const ATTACK := 30.0
const RELEASE := 4.0
## Words in the foot stay this long.
const SAY_MSEC := 4000
## How often the meters, the pulses and the towers are read (Hz), and at motion 0 the towers.
const METER_HZ := 30.0
const CALM_HZ := 1.0
## A header's peak tick holds this long, and its clip light this long after the last clip (ms).
const HOLD_MSEC := 1500
const CLIP_MSEC := 2000
## A header meter falls this fast (dB a second) after its peak, as a desk's does.
const FALL_DB := 24.0
## How many tower tops carry a figure at once.
const TAGS := 24
const AMBER := Color(1.0, 0.64, 0.16)
const RED := Color(1.0, 0.16, 0.1)

var _rows_all: Array = []
var _cols_all: Array = []
## The lines shown, after groups are folded.
var _rows: Array = []
var _cols: Array = []
## Cell pitches, how many cells the window shows each way, and the grid's size.
var _rp := 0.05
var _cp := 0.05
var _vr := 0
var _vc := 0
var _grid := Vector2.ZERO
var _vbar := false
var _hbar := false
## Where the window is (in lines, eased) and where it is going.
var _top := 0.0
var _left := 0.0
var _want_top := 0.0
var _want_left := 0.0
var _pins: Array[Pin] = []
var _row_lines: Array[Line] = []
var _col_lines: Array[Line] = []
var _row_text: Array[Label3D] = []
var _col_text: Array[Label3D] = []
var _bars: Array[Bar] = []
var _keys: Array[Arrow] = []
## What each crossing shown is, asked once until `refresh`: Vector2i(row, col) -> Dictionary.
var _cells := {}
## The pulse each crossing is showing: Vector2i(row, col) -> level.
var _glow := {}
var _lit_row := -1
var _lit_col := -1
var _lit_by: Object = null
var _wheel_until := 0
var _drag := {}
var _said_until := 0
var _built_shape := Vector2i(-1, -1)
var _sockets: MeshBank
var _heads: MeshBank
var _fills: MeshBank
var _bands: MeshBank
var _where: Label3D
var _status: Label3D
var _corner: Array[Label3D] = []
## The header meters, four slots a pooled line (track, fill, tick, light), rows first.
var _meters: MeshBank
## A line's meter as shown, by key: [shown dB, held peak dB, held until, clipped until, last peak,
## last RMS, how], for rows and columns apart.
var _row_level := {}
var _col_level := {}
## Rows whose line is over HOT_DB now, by shown index, so their empty sockets glow.
var _hot_rows := {}
var _meter_clock := 0.0
var _calm_clock := 0.0
## The skyline's towers, two slots a pin (body, top) then two a pooled column; the tops' controls
## (one a pin); the figures on them; what each shows (Vector2i(row, col) -> dB, a column's by
## Vector2i(-1, col)).
var _towers: MeshBank
var _tower_keys: Array[Tower] = []
var _tags: Array[Label3D] = []
var _tower_db := {}
var _tags_clock := 0.0
## For the suite: the figures the tags show now.
var tags_shown: Array[String] = []


# --- what is on it ----------------------------------------------------------------------------

## The lines, rows and columns: Arrays of Dictionaries with "key", "name", "colour", and for a
## group "group" true and "count" (the lines in it), or for a line in one "of" (its group's key).
## Where the window is, and which groups are folded, survive new lines.
func set_lines(rows: Array, cols: Array) -> void:
	_rows_all = rows
	_cols_all = cols
	_relayout()


## Asks the owner about every crossing again: something it answers for changed (a level).
func refresh() -> void:
	_cells.clear()
	_paint()


func _relayout() -> void:
	_rows = _shown(_rows_all)
	_cols = _shown(_cols_all)
	_cells.clear()
	_measure()
	var shape := Vector2i(_vr, _vc)
	if shape != _built_shape:
		_build(shape)
	_want_top = clampf(_want_top, 0.0, _most_top())
	_want_left = clampf(_want_left, 0.0, _most_left())
	_top = clampf(_top, 0.0, _most_top())
	_left = clampf(_left, 0.0, _most_left())
	_place()


## The lines a group folded away leaves out.
func _shown(lines: Array) -> Array:
	var out: Array = []
	for it: Dictionary in lines:
		if it.has("of") and collapsed.has(it["of"]):
			continue
		out.append(it)
	return out


## How big a cell is and how many show: as big as the area allows down to the smallest that can
## be read, and past that, the window scrolls.
func _measure() -> void:
	var nr := _rows.size()
	var nc := _cols.size()
	var room_h := area.y - col_head - foot
	var room_w := area.x - row_head
	_hbar = false
	_vbar = false
	for _pass in 2:
		var h := room_h - (gap + bar if _hbar else 0.0)
		var w := room_w - (gap + bar if _vbar else 0.0)
		_vbar = nr > 0 and nr * row_pitch.x > h + 0.0001
		_hbar = nc > 0 and nc * col_pitch.x > w + 0.0001
	var h := room_h - (gap + bar if _hbar else 0.0)
	var w := room_w - (gap + bar if _vbar else 0.0)
	_rp = clampf(h / maxf(nr, 1), row_pitch.x, row_pitch.y)
	_cp = clampf(w / maxf(nc, 1), col_pitch.x, col_pitch.y)
	_vr = mini(nr, floori(h / _rp + 0.0001))
	_vc = mini(nc, floori(w / _cp + 0.0001))
	_grid = Vector2(_vc * _cp, _vr * _rp)


func _most_top() -> float:
	return maxf(_rows.size() - _vr, 0)


func _most_left() -> float:
	return maxf(_cols.size() - _vc, 0)


## The whole matrix's size (m): what it took of `area`.
func size() -> Vector2:
	return Vector2(row_head + _grid.x + (gap + bar if _vbar else 0.0),
			col_head + _grid.y + (gap + bar if _hbar else 0.0) + foot)


## The grid's top-left corner, in this node's space: the matrix's origin is its own top-left.
func _origin() -> Vector2:
	return Vector2(row_head, -col_head)


func row_count() -> int:
	return _rows.size()


func col_count() -> int:
	return _cols.size()


## The first line the window shows each way, and how many it shows.
func first_row() -> int:
	return roundi(_want_top)


func first_col() -> int:
	return roundi(_want_left)


func shown_rows() -> int:
	return _vr


func shown_cols() -> int:
	return _vc


func cell_size() -> Vector2:
	return Vector2(_cp, _rp)


# --- building -----------------------------------------------------------------------------------

## A pool of pins as big as the window plus one each way (a window between two lines shows part
## of both), and its headers, bars and keys. Built again only when the window changes size:
## scrolling re-points the pool rather than making anything.
func _build(shape: Vector2i) -> void:
	_built_shape = shape
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_pins.clear()
	_row_lines.clear()
	_col_lines.clear()
	_row_text.clear()
	_col_text.clear()
	_bars.clear()
	_keys.clear()
	_corner.clear()
	_glow.clear()
	_tower_keys.clear()
	_tags.clear()
	_tower_db.clear()
	_hot_rows.clear()
	var pr := shape.x + 1 if shape.x > 0 else 0
	var pc := shape.y + 1 if shape.y > 0 else 0

	_meters = MeshBank.strips()
	_meters.name = "Meters"
	for i in (pr + pc) * 4:
		_meters.claim(_hidden(), Color.BLACK)
	add_child(_meters)
	_meters.commit()
	_towers = MeshBank.strips()
	_towers.name = "Towers"
	for i in (pr * pc + pc) * 2:
		_towers.claim(_hidden(), Color.BLACK)
	add_child(_towers)
	_towers.commit()

	_bands = MeshBank.strips()
	_bands.name = "Bands"
	_bands.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A row band for each pooled row, a column band for each pooled column (the header strip's,
	# and over the grid while it is lit), and each line's chip.
	for i in pr * 2 + pc * 2 + 2:
		_bands.claim(_hidden(), Color.BLACK)
	add_child(_bands)
	_bands.commit()

	_sockets = MeshBank.meshed(_disc(_socket_material()))
	_sockets.name = "Sockets"
	_heads = MeshBank.meshed(_disc(null))
	_heads.name = "Heads"
	_heads.material_override = MeshBank._lamp_material()
	_fills = MeshBank.strips()
	_fills.name = "Fills"
	for bank: MeshBank in [_sockets, _heads, _fills]:
		bank.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for k in pr * pc:
			bank.claim(_hidden(), Color.BLACK)
		add_child(bank)
		bank.commit()

	for a in pr:
		for b in pc:
			var pin := Pin.new()
			pin.matrix = self
			pin.slot = a * pc + b
			pin.name = "Pin_%d_%d" % [a, b]
			add_child(pin)
			_pins.append(pin)
			var top := Tower.new()
			top.matrix = self
			top.pin = pin
			top.name = "Tower_%d_%d" % [a, b]
			add_child(top)
			_tower_keys.append(top)
	for i in TAGS:
		var tag := Label3D.new()
		tag.name = "Tag%d" % i
		tag.pixel_size = px
		tag.font_size = 40
		tag.outline_size = 8
		tag.outline_modulate = Color(0.02, 0.02, 0.03, 0.9)
		# Flat on the board, as the rest of its lettering is: a tag turned to the eye and drawn over
		# everything stood in the air in front of the matrix and was too much of it.
		tag.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		tag.double_sided = false
		tag.render_priority = 3
		tag.outline_render_priority = 2
		tag.visible = false
		Lettering.range_to_legibility(tag)
		add_child(tag)
		_tags.append(tag)
	for a in pr:
		var line := Line.new()
		line.matrix = self
		line.is_row = true
		line.name = "Row_%d" % a
		add_child(line)
		_row_lines.append(line)
		_row_text.append(_label(HORIZONTAL_ALIGNMENT_LEFT))
	for b in pc:
		var line := Line.new()
		line.matrix = self
		line.is_row = false
		line.name = "Col_%d" % b
		add_child(line)
		_col_lines.append(line)
		var text := _label(HORIZONTAL_ALIGNMENT_LEFT)
		# Up the column, read from bottom to top, starting just over the grid.
		text.rotation.z = PI * 0.5
		_col_text.append(text)

	_where = _label(HORIZONTAL_ALIGNMENT_LEFT)
	_where.modulate = dim_ink
	_status = _label(HORIZONTAL_ALIGNMENT_RIGHT)
	_status.modulate = Color(0.95, 0.78, 0.45)
	for word in [row_word, col_word]:
		var corner := _label(HORIZONTAL_ALIGNMENT_LEFT)
		corner.text = word
		corner.modulate = Color(0.75, 0.70, 0.55)
		_corner.append(corner)

	for vertical in [true, false]:
		var b := Bar.new()
		b.matrix = self
		b.vertical = vertical
		b.name = "VBar" if vertical else "HBar"
		add_child(b)
		_bars.append(b)
		for step in [-1, 1]:
			var key := Arrow.new()
			key.matrix = self
			key.vertical = vertical
			key.step = step
			key.name = "%s%s" % ["Up" if vertical and step < 0 else "Down" if vertical else "Left" if step < 0 else "Right", "Arrow"]
			add_child(key)
			_keys.append(key)


func _label(align: int) -> Label3D:
	var l := Label3D.new()
	l.pixel_size = px
	l.font_size = 40
	l.horizontal_alignment = align
	l.modulate = ink
	l.double_sided = false
	Lettering.range_to_legibility(l)
	add_child(l)
	return l


static func _hidden() -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)


## A unit disc facing out of the panel (+Z): a cylinder 1 across and 1 deep, turned.
static func _disc(material: Material) -> Mesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.5
	c.bottom_radius = 0.5
	c.height = 1.0
	c.radial_segments = 20
	c.rings = 1
	if material != null:
		c.material = material
	return c


static func _socket_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color.WHITE
	m.metallic = 0.55
	m.roughness = 0.4
	return m


# --- laying the window out --------------------------------------------------------------------

## Points the pool at the lines the window is over and puts every piece where it goes.
func _place() -> void:
	if _pins.is_empty() and _row_lines.is_empty() and _col_lines.is_empty():
		_lay_chrome()
		return
	var o := _origin()
	var pr := _row_lines.size()
	var pc := _col_lines.size()
	var r0 := floori(_top)
	var c0 := floori(_left)
	for a in pr:
		var i := r0 + a
		var y := o.y - (i - _top + 0.5) * _rp
		var shown := i < _rows.size() and y <= o.y + 0.0001 and y >= o.y - _grid.y - 0.0001
		_point_line(_row_lines[a], _row_text[a], i if shown else -1, Vector3(row_head * 0.5, y, 0))
		for b in pc:
			var j := c0 + b
			var x := o.x + (j - _left + 0.5) * _cp
			var pin := _pins[a * pc + b]
			var on := shown and j < _cols.size() and x >= o.x - 0.0001 and x <= o.x + _grid.x + 0.0001
			pin.point(i if on else -1, j if on else -1, Vector3(x, y, 0), Vector2(_cp, _rp))
	for b in pc:
		var j := c0 + b
		var x := o.x + (j - _left + 0.5) * _cp
		var shown := j < _cols.size() and x >= o.x - 0.0001 and x <= o.x + _grid.x + 0.0001
		_point_line(_col_lines[b], _col_text[b], j if shown else -1, Vector3(x, -col_head * 0.5, 0))
	# What is lit follows what is under the pointer, which the window just moved.
	if _lit_by is Pin and is_instance_valid(_lit_by):
		_lit_row = (_lit_by as Pin).r
		_lit_col = (_lit_by as Pin).c
	elif _lit_by is Tower and is_instance_valid(_lit_by):
		_lit_row = (_lit_by as Tower).pin.r
		_lit_col = (_lit_by as Tower).pin.c
	elif _lit_by is Line and is_instance_valid(_lit_by):
		var held := _lit_by as Line
		_lit_row = held.index if held.is_row else -1
		_lit_col = -1 if held.is_row else held.index
	_lay_chrome()
	_paint()
	# The window moved under the towers: they stand again at the next reading, even at motion 0.
	_calm_clock = 1000.0
	_meter_clock = 1000.0


func _point_line(line: Line, text: Label3D, index: int, at: Vector3) -> void:
	var lines := _rows if line.is_row else _cols
	line.point(index, at, Vector2(row_head, _rp) if line.is_row else Vector2(_cp, col_head))
	text.visible = index >= 0
	if index < 0:
		return
	var it: Dictionary = lines[index]
	var words := _line_words(it)
	# A group's own lines sit in from its header, so which node a port is on reads at a glance.
	var indent := _indent(it)
	if line.is_row:
		var side := minf(_rp * 0.62, chip)
		text.position = Vector3(gap + side * 1.6 + indent, at.y, 0.0016)
		_set_text(text, words, row_head - gap * 2.0 - side * 1.6 - indent, _rp * 0.52)
	else:
		var side := minf(_cp * 0.62, chip)
		# The label's left end is its anchor; turned, that end is at the bottom of the strip.
		text.position = Vector3(at.x, -col_head + gap + side * 1.8 + indent, 0.0016)
		_set_text(text, words, col_head - gap * 2.0 - side * 1.8 - indent, _cp * 0.52)


func _indent(it: Dictionary) -> float:
	return 0.0 if it.get("group", false) or not it.has("of") else chip * 0.9


## What a header says: the name, and on a group the count and whether it is open.
func _line_words(it: Dictionary) -> String:
	var n := str(it.get("name", "")).to_upper()
	if it.get("group", false):
		var count := int(it.get("count", 0))
		if collapsed.has(it["key"]):
			return "+ %s  (%d)" % [n, count]
		return "– %s" % n
	return n


func _set_text(label: Label3D, words: String, width: float, tallest: float) -> void:
	var largest := clampi(int(minf(tallest, name_cap) / px), 16, 96)
	if label.text == words and label.get_meta(&"fit", Vector2.ZERO) == Vector2(width, largest):
		return
	label.text = words
	label.set_meta(&"fit", Vector2(width, largest))
	Lettering.fit(label, width, largest)
	Lettering.range_to_legibility(label)


## The bars, keys, corner and foot: where they go for this window, and whether they show at all.
func _lay_chrome() -> void:
	var o := _origin()
	var vx := o.x + _grid.x + gap + bar * 0.5
	var hy := o.y - _grid.y - gap - bar * 0.5
	for b in _bars:
		var on := _vbar if b.vertical else _hbar
		if b.vertical:
			b.lay(on, Vector3(vx, o.y - _grid.y * 0.5, 0), Vector2(bar, maxf(_grid.y - 2.0 * (bar + gap), bar)))
		else:
			b.lay(on, Vector3(o.x + _grid.x * 0.5, hy, 0), Vector2(maxf(_grid.x - 2.0 * (bar + gap), bar), bar))
	for k in _keys:
		var on := _vbar if k.vertical else _hbar
		var at := Vector3(vx, o.y - bar * 0.5 if k.step < 0 else o.y - _grid.y + bar * 0.5, 0) if k.vertical \
				else Vector3(o.x + bar * 0.5 if k.step < 0 else o.x + _grid.x - bar * 0.5, hy, 0)
		k.lay(on, at, bar)
	if _corner.size() == 2:
		_set_text(_corner[0], row_word + "  ↓", row_head - gap * 2.0, col_head * 0.2)
		_corner[0].position = Vector3(gap, -col_head + col_head * 0.15, 0.0016)
		_set_text(_corner[1], col_word + "  →", row_head - gap * 2.0, col_head * 0.2)
		_corner[1].position = Vector3(gap, -col_head * 0.45, 0.0016)
	if _where != null:
		var foot_y := -size().y + foot * 0.5
		_where.position = Vector3(gap, foot_y, 0.0016)
		_set_text(_where, position_words(), size().x * 0.55, foot * 0.55)
		_status.position = Vector3(size().x - gap, foot_y, 0.0016)
		_status.visible = Time.get_ticks_msec() < _said_until
	# The bands' head-strip and chips are part of the paint.


## "ROWS 25-48 OF 64 · COLUMNS 1-22 OF 64", or the counts when everything fits.
func position_words() -> String:
	var parts := PackedStringArray()
	var top := first_row()
	var left := first_col()
	if _rows.size() > _vr:
		parts.append("ROWS %d-%d OF %d" % [top + 1, top + _vr, _rows.size()])
	if _cols.size() > _vc:
		parts.append("COLUMNS %d-%d OF %d" % [left + 1, left + _vc, _cols.size()])
	if parts.is_empty():
		return "%d %s  ×  %d %s" % [_rows.size(), row_word, _cols.size(), col_word]
	return "  ·  ".join(parts)


# --- painting ---------------------------------------------------------------------------------

## What crossing (row, col) is, asked of the owner once until `refresh`.
func cell(i: int, j: int) -> Dictionary:
	var at := Vector2i(i, j)
	if _cells.has(at):
		return _cells[at]
	var out := {}
	if i >= 0 and j >= 0 and i < _rows.size() and j < _cols.size():
		var r: Dictionary = _rows[i]
		var c: Dictionary = _cols[j]
		if pin_at.is_valid():
			out = pin_at.call(r["key"], c["key"])
	_cells[at] = out
	return out


func _on_lit_line(i: int, j: int) -> bool:
	return (_lit_row >= 0 and i == _lit_row) or (_lit_col >= 0 and j == _lit_col)


## Every piece's look: the bands, the chips, the sockets and pins, and the lettering's light.
func _paint() -> void:
	if _bands == null:
		return
	var o := _origin()
	var pr := _row_lines.size()
	var pc := _col_lines.size()
	var lit := _lit_row >= 0 or _lit_col >= 0
	var slot := 0
	for a in pr:
		var line := _row_lines[a]
		var i := line.index
		if i < 0:
			_bands.move_slot(slot, _hidden())
			_bands.move_slot(slot + 1, _hidden())
		else:
			var it: Dictionary = _rows[i]
			var tint: Color = it.get("colour", Color.GRAY)
			var rest := ground_banded if i % 2 == 1 else ground
			if it.get("group", false):
				rest = rest.lerp(tint, 0.16)
			var colour := rest.lerp(tint, 0.24) if i == _lit_row else rest
			var wide := row_head + _grid.x
			_bands.move_slot(slot, Transform3D(Basis.from_scale(Vector3(wide, _rp * 0.94, 0.0005)),
					Vector3(wide * 0.5, line.position.y, 0.0004)))
			_bands.set_colour(slot, colour.srgb_to_linear())
			var side := minf(_rp * 0.62, chip)
			var big := side * (1.0 if not it.has("of") else 0.6)
			_bands.move_slot(slot + 1, Transform3D(Basis.from_scale(Vector3(big * 0.55, big, 0.0005)),
					Vector3(gap + side * 0.5 + _indent(it), line.position.y, 0.0012)))
			_bands.set_colour(slot + 1, Materials.chip_colour(tint))
			_row_text[a].modulate = ink if not lit or i == _lit_row else dim_ink.darkened(0.25)
		slot += 2
	for b in pc:
		var line := _col_lines[b]
		var j := line.index
		if j < 0:
			_bands.move_slot(slot, _hidden())
			_bands.move_slot(slot + 1, _hidden())
		else:
			var it: Dictionary = _cols[j]
			var tint: Color = it.get("colour", Color.GRAY)
			var rest := ground_banded if j % 2 == 1 else ground
			if it.get("group", false):
				rest = rest.lerp(tint, 0.16)
			if j == _lit_col:
				# Down through the grid too, over the row bands, so the column reads as a line.
				var tall := col_head + _grid.y
				_bands.move_slot(slot, Transform3D(Basis.from_scale(Vector3(_cp * 0.94, tall, 0.0005)),
						Vector3(line.position.x, -tall * 0.5, 0.0007)))
				_bands.set_colour(slot, rest.lerp(tint, 0.24).srgb_to_linear())
			else:
				_bands.move_slot(slot, Transform3D(Basis.from_scale(Vector3(_cp * 0.94, col_head, 0.0005)),
						Vector3(line.position.x, -col_head * 0.5, 0.0004)))
				_bands.set_colour(slot, rest.srgb_to_linear())
			var side := minf(_cp * 0.62, chip)
			var big := side * (1.0 if not it.has("of") else 0.6)
			_bands.move_slot(slot + 1, Transform3D(Basis.from_scale(Vector3(big, big * 0.55, 0.0005)),
					Vector3(line.position.x, -col_head + gap + side * 0.5 + _indent(it), 0.0012)))
			_bands.set_colour(slot + 1, Materials.chip_colour(tint))
			_col_text[b].modulate = ink if not lit or j == _lit_col else dim_ink.darkened(0.25)
		slot += 2
	for pin in _pins:
		_paint_pin(pin)


func _paint_pin(pin: Pin) -> void:
	var k := pin.slot
	if pin.r < 0 or pin.c < 0:
		_sockets.move_slot(k, _hidden())
		_heads.move_slot(k, _hidden())
		_fills.move_slot(k, _hidden())
		return
	var st := cell(pin.r, pin.c)
	var at := pin.position
	var small := minf(_cp, _rp)
	var dim := (_lit_row >= 0 or _lit_col >= 0) and not _on_lit_line(pin.r, pin.c)
	var crossing := _on_lit_line(pin.r, pin.c) and (_lit_row >= 0 or _lit_col >= 0)
	var tint: Color = st.get("tint", Color.GRAY)
	var group: bool = (_rows[pin.r] as Dictionary).get("group", false) or (_cols[pin.c] as Dictionary).get("group", false)
	var turned := Basis(Vector3.RIGHT, PI * 0.5)

	if st.get("blocked", false):
		# No socket at all: a short dash, so it reads as "not here" and not as "empty".
		_sockets.move_slot(k, _hidden())
		_heads.move_slot(k, _hidden())
		_fills.move_slot(k, Transform3D(Basis.from_scale(Vector3(small * 0.42, small * 0.07, 0.0006)),
				at + Vector3(0, 0, 0.0012)))
		_fills.set_colour(k, Color(0.3, 0.3, 0.32).srgb_to_linear() * (0.6 if dim else 1.0))
		return
	if group:
		var links := int(st.get("links", 0))
		_heads.move_slot(k, _hidden())
		if links > 0:
			_sockets.move_slot(k, _hidden())
			var side := small * clampf(0.22 + 0.06 * links, 0.22, 0.5)
			_fills.move_slot(k, Transform3D(Basis.from_scale(Vector3(side, side, 0.0008)), at + Vector3(0, 0, 0.0014)))
			_fills.set_colour(k, Materials.chip_colour(tint) * (0.25 if dim else 0.9))
		else:
			_fills.move_slot(k, _hidden())
			_sockets.move_slot(k, Transform3D(turned * Basis.from_scale(Vector3(small * 0.16, 0.002, small * 0.16)),
					at + Vector3(0, 0, 0.001)))
			_sockets.set_colour(k, Color(0.2, 0.21, 0.23))
		return

	var seated: bool = st.get("on", false)
	var pending: bool = st.get("pending", false)
	_sockets.move_slot(k, Transform3D(turned * Basis.from_scale(Vector3(small * 0.34, small * 0.06, small * 0.34)),
			at + Vector3(0, 0, small * 0.03)))
	var bore := Color(0.26, 0.27, 0.3)
	if crossing:
		bore = Color(0.48, 0.5, 0.55)
	elif dim:
		bore = Color(0.14, 0.145, 0.16)
	if not seated and not pending and _hot_rows.has(pin.r):
		# An empty socket in a hot row glows, faintly: somewhere that loud line could go instead.
		bore = bore.lerp(Color(0.95, 0.62, 0.22), 0.45 if not dim else 0.2)
	_sockets.set_colour(k, bore)
	if seated or pending:
		var head := small * (0.54 if seated else 0.36)
		_heads.move_slot(k, Transform3D(turned * Basis.from_scale(Vector3(head, small * 0.16, head)),
				at + Vector3(0, 0, small * 0.1)))
		_heads.set_colour(k, _head_colour(pin, tint, seated, dim))
	else:
		_heads.move_slot(k, _hidden())
	var lvl: float = st.get("level", -1.0)
	if seated and lvl >= 0.0:
		# The level as a bar up the cell's right edge, from its foot.
		var tall := maxf(lvl, 0.02) * _rp * 0.84
		_fills.move_slot(k, Transform3D(Basis.from_scale(Vector3(_cp * 0.09, tall, 0.0006)),
				at + Vector3(_cp * 0.4, -_rp * 0.42 + tall * 0.5, 0.0012)))
		_fills.set_colour(k, Materials.chip_colour(tint) * (0.22 if dim else 0.75))
	else:
		_fills.move_slot(k, _hidden())


## A head is its source's colour, brighter the louder what goes through it is: above 1 is what
## the glow picks up, as SignalBeads.glow.
func _head_colour(pin: Pin, tint: Color, seated: bool, dim: bool) -> Color:
	# Saturated as a lit cable's jacket is (Materials.cable_lit): a pastel track colour on a head
	# this small reads as white.
	var dyed := tint
	dyed.s = maxf(dyed.s, 0.55)
	var lit := Materials.chip_colour(dyed)
	if not seated:
		return lit * 0.4
	if dim:
		return lit * 0.22
	var loud := clampf((float(_glow.get(Vector2i(pin.r, pin.c), 0.0)) - SignalBeads.FLOOR) / (0.716 - SignalBeads.FLOOR), 0.0, 1.0)
	if pin_meter.is_valid() and loud <= 0.0:
		# Patched, carrying nothing: dull, so a pin in that is not sounding reads apart from one that is.
		return lit * 0.32
	return lit * lerpf(0.8, 2.0, loud)


## How bright pin (row, col)'s head is now, 0..1 of its pulse: for the suite.
func pulse_of(i: int, j: int) -> float:
	return float(_glow.get(Vector2i(i, j), 0.0))


func _process(delta: float) -> void:
	var motion := Ergonomics.current.motion_scale if Ergonomics.current != null else 1.0
	var moved := false
	if absf(_want_top - _top) > 0.0005 or absf(_want_left - _left) > 0.0005:
		var k := 1.0 if motion <= 0.0 or delta <= 0.0 else clampf(1.0 - exp(-EASE * delta), 0.0, 1.0)
		_top = lerpf(_top, _want_top, k)
		_left = lerpf(_left, _want_left, k)
		if absf(_want_top - _top) < 0.002:
			_top = _want_top
		if absf(_want_left - _left) < 0.002:
			_left = _want_left
		moved = true
	if moved:
		_place()
		scrolled.emit()
	if pin_meter.is_valid() or row_meter.is_valid() or col_meter.is_valid():
		_meter_clock += delta
		if _meter_clock >= 1.0 / METER_HZ:
			var step := minf(_meter_clock, 0.1)
			_meter_clock = 0.0
			_pulse(step)
			_read_meters(step, motion)
	else:
		_pulse(delta)
	if _status != null and _status.visible and Time.get_ticks_msec() >= _said_until:
		_status.visible = false


## Every seated pin in the window followed to the level through it, as a meter's ballistics.
func _pulse(delta: float) -> void:
	if not (signal_of.is_valid() or pin_meter.is_valid()) or _heads == null:
		return
	for pin in _pins:
		if pin.r < 0:
			continue
		var st := cell(pin.r, pin.c)
		if not st.get("on", false):
			continue
		var at := Vector2i(pin.r, pin.c)
		var want := 0.0
		if pin_meter.is_valid():
			var m: Vector3 = pin_meter.call(_rows[pin.r]["key"], _cols[pin.c]["key"])
			want = FaderLaw.to_taper(m.x) if m.z != SignalGraph.UNKNOWN and is_finite(m.x) and m.x > SignalGraph.FLOOR_DB else 0.0
		else:
			want = clampf(float(signal_of.call(_rows[pin.r]["key"], _cols[pin.c]["key"])), 0.0, 1.0)
		var was := float(_glow.get(at, 0.0))
		var follow := ATTACK if want > was else RELEASE
		var now := lerpf(was, want, clampf(follow * delta, 0.0, 1.0)) if delta > 0.0 else want
		if want <= 0.0 and now < 0.01:
			now = 0.0
		if absf(now - was) < 0.0005 and _glow.has(at):
			continue
		_glow[at] = now
		var dim := (_lit_row >= 0 or _lit_col >= 0) and not _on_lit_line(pin.r, pin.c)
		_heads.set_colour(pin.slot, _head_colour(pin, st.get("tint", Color.GRAY), true, dim))


# --- levels: the header meters and the skyline --------------------------------------------------

## A level's share of a meter or a tower: SignalGraph.FLOOR_DB at nothing to SignalGraph.TOP_DB at
## all of it, even in decibels, as a pipe's thickness is.
static func level_share(db: float) -> float:
	return SignalGraph.thickness(db) if is_finite(db) else 0.0


static func _known(m: Vector3) -> bool:
	return m.z != SignalGraph.UNKNOWN


## The header meters, the hot rows' sockets and the towers, read for what the window shows.
func _read_meters(delta: float, motion: float) -> void:
	if _meters == null or not is_visible_in_tree():
		return
	var now := Time.get_ticks_msec()
	var lit := _lit_row >= 0 or _lit_col >= 0
	for a in _row_lines.size():
		var line := _row_lines[a]
		var slot := a * 4
		if line.index < 0 or not row_meter.is_valid():
			_hide_meter(slot)
			continue
		var it: Dictionary = _rows[line.index]
		var m: Vector3 = row_meter.call(it["key"])
		var st := _level_state(_row_level, it["key"])
		_follow_level(st, m, delta, now)
		_draw_meter(slot, true, line, it, st, now, motion, lit and line.index != _lit_row)
		var hot := _known(m) and is_finite(m.x) and m.x >= SignalGraph.HOT_DB
		if hot != _hot_rows.has(line.index):
			if hot:
				_hot_rows[line.index] = true
			else:
				_hot_rows.erase(line.index)
			for pin in _pins:
				if pin.r == line.index:
					_paint_pin(pin)
	var base := _row_lines.size() * 4
	for b in _col_lines.size():
		var line := _col_lines[b]
		var slot := base + b * 4
		if line.index < 0 or not col_meter.is_valid():
			_hide_meter(slot)
			continue
		var it: Dictionary = _cols[line.index]
		var m: Vector3 = col_meter.call(it["key"])
		var st := _level_state(_col_level, it["key"])
		_follow_level(st, m, delta, now)
		_draw_meter(slot, false, line, it, st, now, motion, lit and line.index != _lit_col)
	_draw_towers(delta, motion, now)


## A line's meter state, kept by its key from the first time it is shown.
static func _level_state(states: Dictionary, key: Variant) -> Array:
	var st: Array = states.get(key, [])
	if st.is_empty():
		st = [-INF, -INF, 0, 0, -INF, NAN, SignalGraph.UNKNOWN, -INF]
		states[key] = st
	return st


## One reading into a line's state: the shown level falls at FALL_DB a second after a peak, the
## held peak stands HOLD_MSEC, a clip is remembered CLIP_MSEC with the most it went over by.
func _follow_level(st: Array, m: Vector3, delta: float, now: int) -> void:
	var peak := m.x if _known(m) and is_finite(m.x) else -INF
	st[4] = peak
	st[5] = m.y
	st[6] = m.z
	var shown: float = st[0]
	shown = peak if peak >= shown or not is_finite(shown) else maxf(peak, shown - FALL_DB * delta)
	st[0] = shown
	if peak >= float(st[1]) or now > int(st[2]):
		st[1] = peak
		st[2] = now + HOLD_MSEC
	if peak > SignalGraph.CLIP_DB:
		if now > int(st[3]):
			st[7] = peak
		st[7] = maxf(float(st[7]), peak)
		st[3] = now + CLIP_MSEC


func _hide_meter(slot: int) -> void:
	for i in 4:
		_meters.move_slot(slot + i, _hidden())


## A header's meter: a dark track, the RMS (or the level, where there is no RMS) as a fill in the
## line's colour -- amber from HOT_DB, red past 0 dBFS -- the held peak as a tick, and the light.
func _draw_meter(slot: int, is_row: bool, line: Line, it: Dictionary, st: Array, now: int, motion: float, dim: bool) -> void:
	if int(st[6]) == int(SignalGraph.UNKNOWN):
		_hide_meter(slot)
		return
	var at := line.position
	var tint: Color = it.get("colour", Color.GRAY)
	var shown: float = st[0]
	var rms: float = st[5]
	var fill_db := rms if is_finite(rms) else shown
	var light := 0
	if now <= int(st[3]):
		light = 2
	elif is_finite(float(st[1])) and float(st[1]) >= SignalGraph.HOT_DB and now <= int(st[2]):
		light = 1
	var lane := 0.0
	var thick := 0.0
	var from := 0.0
	var to := 0.0
	if is_row:
		var side := minf(_rp * 0.62, chip)
		thick = _rp * 0.11
		lane = at.y - _rp * 0.36
		from = gap + side * 1.6 + _indent(it)
		to = row_head - gap * 1.5 - _rp * 0.3
	else:
		var side := minf(_cp * 0.62, chip)
		thick = _cp * 0.11
		lane = at.x + _cp * 0.36
		from = -col_head + gap + side * 1.8 + _indent(it)
		to = -gap * 1.5 - _cp * 0.3
	var run := maxf(to - from, 0.001)
	var health := SignalGraph.health(shown)
	var ink := Materials.chip_colour(tint)
	if health == &"clip":
		ink = RED * 1.4
	elif health == &"hot":
		ink = AMBER * 1.3
	var fade := 0.35 if dim else 1.0
	var fill := run * level_share(fill_db)
	var tick := run * level_share(float(st[1]))
	_meters.move_slot(slot, _meter_box(is_row, lane, from + run * 0.5, run, thick, 0.0013))
	_meters.set_colour(slot, Color(0.03, 0.032, 0.036))
	if fill > 0.0005:
		_meters.move_slot(slot + 1, _meter_box(is_row, lane, from + fill * 0.5, fill, thick * 0.8, 0.0016))
		_meters.set_colour(slot + 1, ink * 0.9 * fade)
	else:
		_meters.move_slot(slot + 1, _hidden())
	if tick > 0.0005:
		_meters.move_slot(slot + 2, _meter_box(is_row, lane, from + tick, maxf(run * 0.012, 0.0012), thick * 1.2, 0.0018))
		_meters.set_colour(slot + 2, (RED * 1.8 if float(st[1]) > SignalGraph.CLIP_DB else Color(1.0, 0.97, 0.9) * 1.5) * fade)
	else:
		_meters.move_slot(slot + 2, _hidden())
	if light == 0:
		_meters.move_slot(slot + 3, _hidden())
	else:
		# Amber a small square, red a bar half as tall again as the line's meter is thick: told
		# apart by their shapes, and said in words on the card.
		var size := (_rp if is_row else _cp) * 0.2
		var tall := size * (2.2 if light == 2 else 1.0)
		var end := to + (_rp if is_row else _cp) * 0.17
		var basis := Basis.from_scale(Vector3(size, tall, 0.001)) if is_row else Basis.from_scale(Vector3(tall, size, 0.001))
		var where := Vector3(end, lane + (tall - size) * 0.5, 0.0018) if is_row else Vector3(lane - (tall - size) * 0.5, end, 0.0018)
		_meters.move_slot(slot + 3, Transform3D(basis, where))
		var pulse := 1.0 if motion <= 0.0 or light != 2 else 0.75 + 0.25 * sin(now * 0.001 * TAU * 2.0)
		_meters.set_colour(slot + 3, (RED * 2.0 * pulse if light == 2 else AMBER * 1.6) * fade)


static func _meter_box(is_row: bool, lane: float, along: float, length: float, thick: float, z: float) -> Transform3D:
	if is_row:
		return Transform3D(Basis.from_scale(Vector3(length, thick, 0.0006)), Vector3(along, lane, z))
	return Transform3D(Basis.from_scale(Vector3(thick, length, 0.0006)), Vector3(lane, along, z))


## A header's level in words, for its card: "peak −6.0 dBFS · RMS −14.2 dBFS", the held clip
## ("CLIPPED +1.2 dB, 1 s ago") or the heat, and for a column how many feed it. "" with no meter.
func line_level_words(key: Variant, is_row: bool) -> String:
	var st: Array = (_row_level if is_row else _col_level).get(key, [])
	if st.is_empty():
		var m: Vector3 = (row_meter.call(key) if is_row else col_meter.call(key)) if (row_meter if is_row else col_meter).is_valid() else Vector3(-INF, NAN, SignalGraph.UNKNOWN)
		st = [m.x, m.x, 0, 0, m.x, m.y, m.z, -INF]
	var how: float = st[6]
	if how == SignalGraph.UNKNOWN:
		return "level not measured"
	var parts := PackedStringArray()
	parts.append(("arriving, peaks added, %s" if not is_row else "peak %s") % SignalGraph.db_words(float(st[4]), how))
	if is_row and is_finite(float(st[5])):
		parts.append("RMS %s" % SignalGraph.db_words(float(st[5])))
	var now := Time.get_ticks_msec()
	if now <= int(st[3]):
		parts.append("CLIPPED +%.1f dB, %d s ago" % [float(st[7]), int((CLIP_MSEC - (int(st[3]) - now)) / 1000.0)])
	elif float(st[4]) >= SignalGraph.HOT_DB:
		parts.append("HOT: within 3 dB of 0 dBFS")
	return " · ".join(parts)


## Whether the line is showing its clip light now: for the suite.
func clip_lit(key: Variant, is_row: bool) -> bool:
	var st: Array = (_row_level if is_row else _col_level).get(key, [])
	return not st.is_empty() and Time.get_ticks_msec() <= int(st[3])


## Whether row `i` (shown index) is hot, its empty sockets glowing: for the suite.
func row_hot(i: int) -> bool:
	return _hot_rows.has(i)


## The skyline: a tower a seated pin with a level, as tall as what it carries, and one a column's
## arrival on its header; amber and red tops carry their figures. Hidden when `skyline` is off.
func _draw_towers(delta: float, motion: float, now: int) -> void:
	if _towers == null:
		return
	var up := skyline and pin_meter.is_valid() and is_visible_in_tree()
	if not up:
		if not _tower_db.is_empty():
			_tower_db.clear()
			for i in _towers.count():
				_towers.move_slot(i, _hidden())
			for t in _tower_keys:
				t.lay(false, Vector3.ZERO, 0.0, 0.0)
			for tag in _tags:
				tag.visible = false
			tags_shown.clear()
		return
	var calm := motion <= 0.0
	if calm:
		_calm_clock += delta
		if _calm_clock < 1.0 / CALM_HZ and not _tower_db.is_empty():
			return
		_calm_clock = 0.0
	var small := minf(_cp, _rp)
	var lit := _lit_row >= 0 or _lit_col >= 0
	var tags := 0
	var pc := _col_lines.size()
	for pin in _pins:
		var k := pin.slot * 2
		var tower := _tower_keys[pin.slot]
		var st := cell(pin.r, pin.c) if pin.r >= 0 and pin.c >= 0 else {}
		var group: bool = pin.r >= 0 and pin.c >= 0 and ((_rows[pin.r] as Dictionary).get("group", false) or (_cols[pin.c] as Dictionary).get("group", false))
		if not st.get("on", false) or group:
			_towers.move_slot(k, _hidden())
			_towers.move_slot(k + 1, _hidden())
			tower.lay(false, Vector3.ZERO, 0.0, 0.0)
			continue
		var at := Vector2i(pin.r, pin.c)
		var m: Vector3 = pin_meter.call(_rows[pin.r]["key"], _cols[pin.c]["key"])
		var target := m.x if _known(m) and is_finite(m.x) else SignalGraph.FLOOR_DB
		if not is_nan(tower.held_db):
			target = tower.held_db
		var db := _ease_tower(at, target, delta, calm or not is_nan(tower.held_db))
		var dim := lit and not _on_lit_line(pin.r, pin.c)
		tags = _stand_tower(k, pin.position, small, db, st.get("tint", Color.GRAY), dim, motion, now, tags, _known(m) and m.z == SignalGraph.ESTIMATED)
		tower.lay(st.get("level", -1.0) >= 0.0, pin.position, small, _tower_tall(db, small))
	for b in pc:
		var k := (_pins.size() + b) * 2
		var line := _col_lines[b]
		var st: Array = _col_level.get(_cols[line.index]["key"], []) if line.index >= 0 else []
		if st.is_empty() or int(st[6]) == int(SignalGraph.UNKNOWN):
			_towers.move_slot(k, _hidden())
			_towers.move_slot(k + 1, _hidden())
			continue
		var db := _ease_tower(Vector2i(-1, line.index), float(st[4]) if is_finite(float(st[4])) else SignalGraph.FLOOR_DB, delta, calm)
		var foot := Vector3(line.position.x, -col_head * 0.5, 0.0)
		var dim := lit and line.index != _lit_col
		tags = _stand_tower(k, foot, minf(_cp, col_head) * 0.8, db, Color(0.9, 0.9, 0.95), dim, motion, now, tags, int(st[6]) == int(SignalGraph.ESTIMATED))
	for i in range(tags, _tags.size()):
		if _tags[i].visible:
			_tags[i].visible = false
			_tags_changed()


func _ease_tower(at: Vector2i, target: float, delta: float, now_: bool) -> float:
	var was := float(_tower_db.get(at, target))
	if not is_finite(was):
		was = SignalGraph.FLOOR_DB
	var db := target if now_ or delta <= 0.0 else lerpf(was, target, clampf((ATTACK if target > was else RELEASE) * delta, 0.0, 1.0))
	_tower_db[at] = db
	return db


func _tower_tall(db: float, small: float) -> float:
	return maxf(level_share(db) * tower_max, small * 0.25)


## One tower at `at` on the board, a cell `small` across: its body, glowing in its colour, and its
## top; amber and red tops get a tag, flat on the board at the top of the tower's cell. Answers how
## many tags are in use after it.
func _stand_tower(k: int, at: Vector3, small: float, db: float, tint: Color, dim: bool, motion: float, now: int, tags: int, estimated: bool) -> int:
	var tall := _tower_tall(db, small)
	var wide := small * 0.34
	var cap := minf(tall * 0.12, small * 0.2)
	var base := small * 0.1
	var dyed := tint
	dyed.s = maxf(dyed.s, 0.5)
	var glow := Materials.chip_colour(dyed) * lerpf(0.7, 1.8, level_share(db))
	_towers.move_slot(k, Transform3D(Basis.from_scale(Vector3(wide, wide, tall - cap)), at + Vector3(0, 0, base + (tall - cap) * 0.5)))
	_towers.set_colour(k, glow * (0.22 if dim else 1.0))
	var top := Materials.chip_colour(dyed) * 2.0
	var health := SignalGraph.health(db)
	if health == &"clip":
		var pulse := 1.0 if motion <= 0.0 else 0.7 + 0.3 * sin(now * 0.001 * TAU * 2.0)
		top = RED * 2.2 * pulse
	elif health == &"hot":
		top = AMBER * 1.9
	_towers.move_slot(k + 1, Transform3D(Basis.from_scale(Vector3(wide * 1.25, wide * 1.25, cap)), at + Vector3(0, 0, base + tall - cap * 0.5)))
	_towers.set_colour(k + 1, top * (0.3 if dim else 1.0))
	if (health == &"clip" or health == &"hot") and tags < _tags.size():
		var tag := _tags[tags]
		var words := ("+%.1f dB" % db) if health == &"clip" else "%s%.1f dBFS" % ["−" if db < 0.0 else "", absf(db)]
		if estimated:
			words = "≈ " + words
		if tag.text != words or not tag.visible:
			tag.text = words
			tag.visible = true
			_tags_changed()
		var size := tag_cap if tag_cap > 0.0 else clampf(small * 0.45, 0.012, 0.08)
		tag.font_size = 40
		tag.pixel_size = size / 40.0 * 1.4
		tag.modulate = RED.lightened(0.3) if health == &"clip" else AMBER.lightened(0.2)
		tag.position = at + Vector3(0, small * 0.4, small * 0.05)
		tags += 1
	return tags


func _tags_changed() -> void:
	tags_shown.clear()
	for tag in _tags:
		if tag.visible:
			tags_shown.append(tag.text)


## How tall pin (row, col)'s tower stands now (m), 0 with none: for the suite.
func tower_height(i: int, j: int) -> float:
	for pin in _pins:
		if pin.r == i and pin.c == j:
			var t := _tower_keys[pin.slot]
			return t.tall if t.up else 0.0
	return 0.0


## The tower top on pin (row, col), when the window shows it and it stands: for the suite.
func tower_for(row_key: Variant, col_key: Variant) -> Tower:
	var pin := pin_for(row_key, col_key)
	return _tower_keys[pin.slot] if pin != null and _tower_keys[pin.slot].up else null


func _tower_begin(tower: Tower, at: Vector3) -> void:
	var pin := tower.pin
	tower._start = to_local(at)
	tower._moved = false
	tower._notched = 0.0
	var from := float(level_db.call(_rows[pin.r]["key"], _cols[pin.c]["key"])) if level_db.is_valid() else -INF
	tower._from_db = from if is_finite(from) else -61.0
	tower._peak_from = float(_tower_db.get(Vector2i(pin.r, pin.c), SignalGraph.FLOOR_DB))


func _tower_move(tower: Tower, at: Vector3) -> void:
	var pin := tower.pin
	if pin.r < 0 or pin.c < 0 or not set_level_db.is_valid():
		return
	var d := to_local(at) - tower._start
	if not tower._moved and Vector2(d.y, d.z).length() < DRAG_FROM * minf(_cp, _rp):
		return
	tower._moved = true
	# Up the board, as a pin's drag; or out of it, the top following the hand.
	var by := d.y / (LEVEL_STEP * _rp) + d.z / maxf(tower_max, 0.01) * (SignalGraph.TOP_DB - SignalGraph.FLOOR_DB)
	var hand := tower.held_by as Interactor
	if hand != null and hand.fine():
		by *= 0.1
	var want := clampf(snappedf(tower._from_db + by, 0.1), -61.0, 12.0)
	if is_equal_approx(want, tower._notched):
		return
	tower._notched = want
	set_level_db.call(_rows[pin.r]["key"], _cols[pin.c]["key"], want)
	tower.held_db = tower._peak_from + (maxf(want, -60.0) - maxf(tower._from_db, -60.0))
	refresh()


func _tower_end(tower: Tower) -> void:
	var pin := tower.pin
	var moved := tower._moved
	tower.held_db = NAN
	tower._moved = false
	if not moved and pin.r >= 0 and pin.c >= 0:
		press(pin.r, pin.c)


# --- moving the window ------------------------------------------------------------------------

## Sends the window by `rows` and `cols` lines; whether it moved at all.
func scroll_by(rows: float, cols: float) -> bool:
	var top := clampf(roundf(_want_top + rows), 0.0, _most_top())
	var left := clampf(roundf(_want_left + cols), 0.0, _most_left())
	if is_equal_approx(top, _want_top) and is_equal_approx(left, _want_left):
		return false
	_want_top = top
	_want_left = left
	return true


## Puts the window with `row` and `col` at its top-left (as near as the ends allow), there at
## once rather than eased when `instant`.
func scroll_to(row: int, col: int, instant := true) -> void:
	_want_top = clampf(row, 0.0, _most_top())
	_want_left = clampf(col, 0.0, _most_left())
	if instant:
		_top = _want_top
		_left = _want_left
		_place()
		scrolled.emit()


## Brings line `key` into the window, as a row or a column.
func show_line(key: Variant, is_row: bool) -> void:
	var lines := _rows if is_row else _cols
	for n in lines.size():
		if (lines[n] as Dictionary)["key"] == key:
			var span := _vr if is_row else _vc
			var first := first_row() if is_row else first_col()
			if n < first or n >= first + span:
				first = n - span / 2
			if is_row:
				scroll_to(first, first_col())
			else:
				scroll_to(first_row(), first)
			return


func _wheel(rows: int, cols: int) -> bool:
	var moved := scroll_by(rows, cols)
	if moved:
		_wheel_until = Time.get_ticks_msec() + WHEEL_LATCH_MSEC
	return moved


# --- folding groups -----------------------------------------------------------------------------

func set_collapsed(key: Variant, folded: bool) -> void:
	if folded:
		collapsed[key] = true
	else:
		collapsed.erase(key)
	_relayout()


func is_collapsed(key: Variant) -> bool:
	return collapsed.has(key)


# --- what the pieces report ---------------------------------------------------------------------

## The pin in the window at row `row_key`, column `col_key`; null when the window is elsewhere.
func pin_for(row_key: Variant, col_key: Variant) -> Pin:
	for pin in _pins:
		if pin.r >= 0 and pin.c >= 0 and (_rows[pin.r] as Dictionary)["key"] == row_key \
				and (_cols[pin.c] as Dictionary)["key"] == col_key:
			return pin
	return null


## The header in the window for line `key`, as a row or a column; null when it is out of it.
func line_for(key: Variant, is_row: bool) -> Line:
	for line in (_row_lines if is_row else _col_lines):
		var lines := _rows if is_row else _cols
		if line.index >= 0 and (lines[line.index] as Dictionary)["key"] == key:
			return line
	return null


func row_line(i: int) -> Dictionary:
	return _rows[i] if i >= 0 and i < _rows.size() else {}


func col_line(j: int) -> Dictionary:
	return _cols[j] if j >= 0 and j < _cols.size() else {}


## The row and column lit now (shown indices), -1 for none.
func lit() -> Vector2i:
	return Vector2i(_lit_row, _lit_col)


func pins() -> Array[Pin]:
	return _pins


func bars() -> Array[Bar]:
	return _bars


func arrows() -> Array[Arrow]:
	return _keys


## Says `words` in the foot for a while, and to whoever listens.
func say(words: String) -> void:
	if words.is_empty():
		return
	if _status != null:
		_set_text(_status, words, size().x * 0.42, foot * 0.55)
		_status.visible = true
	_said_until = Time.get_ticks_msec() + SAY_MSEC
	said.emit(words)


func status_words() -> String:
	return _status.text if _status != null and _status.visible else ""


func _light(row: int, col: int, by: Object) -> void:
	_lit_row = row
	_lit_col = col
	_lit_by = by
	_paint()


func _unlight(by: Object) -> void:
	if _lit_by != by:
		return
	_light(-1, -1, null)


# --- the gestures -------------------------------------------------------------------------------

func _begin(node: ControlAffordance, at: Vector3) -> void:
	_drag = {"node": node, "start": to_local(at), "top": _want_top, "left": _want_left, "mode": &"press",
			"notches": 0}


func _move(node: ControlAffordance, at: Vector3) -> void:
	if _drag.is_empty() or _drag["node"] != node:
		return
	var d: Vector3 = to_local(at) - (_drag["start"] as Vector3)
	if _drag["mode"] == &"press":
		if Vector2(d.x, d.y).length() < DRAG_FROM * minf(_cp, _rp):
			return
		var pin := node as Pin
		var st := cell(pin.r, pin.c) if pin != null else {}
		if pin != null and st.get("on", false) and float(st.get("level", -1.0)) >= 0.0 and level.is_valid() \
				and absf(d.y) > absf(d.x):
			_drag["mode"] = &"level"
			_drag["keys"] = [_rows[pin.r]["key"], _cols[pin.c]["key"]]
			_drag["start"] = to_local(at)
			d = Vector3.ZERO
		else:
			_drag["mode"] = &"scroll"
	match _drag["mode"]:
		&"level":
			var n := int(d.y / (LEVEL_STEP * _rp))
			if n != int(_drag["notches"]):
				var keys: Array = _drag["keys"]
				var hand := node.held_by as Interactor
				level.call(keys[0], keys[1], n - int(_drag["notches"]), hand != null and hand.fine())
				_drag["notches"] = n
				refresh()
		&"scroll":
			var line := node as Line
			var rows := d.y / _rp if line == null or line.is_row else 0.0
			var cols := -d.x / _cp if line == null or not line.is_row else 0.0
			_want_top = clampf(float(_drag["top"]) + rows, 0.0, _most_top())
			_want_left = clampf(float(_drag["left"]) + cols, 0.0, _most_left())
			# Held, the grid is the hand's: it goes where the hand does, not after it.
			_top = _want_top
			_left = _want_left
			_place()
			scrolled.emit()


func _end(node: ControlAffordance) -> void:
	if _drag.is_empty() or _drag["node"] != node:
		return
	var mode: StringName = _drag["mode"]
	_drag.clear()
	if mode == &"scroll":
		# Let go between two lines, the window settles on the nearer.
		_want_top = clampf(roundf(_want_top), 0.0, _most_top())
		_want_left = clampf(roundf(_want_left), 0.0, _most_left())
		return
	if mode != &"press":
		return
	if node is Pin:
		press(node.r, node.c)
	elif node is Line:
		var line := node as Line
		var it: Dictionary = (_rows if line.is_row else _cols)[line.index] if line.index >= 0 else {}
		if it.get("group", false):
			set_collapsed(it["key"], not is_collapsed(it["key"]))


## A press on crossing (row, col), shown indices: the owner's toggle, or a group opened.
func press(i: int, j: int) -> void:
	if i < 0 or j < 0 or i >= _rows.size() or j >= _cols.size():
		return
	var r: Dictionary = _rows[i]
	var c: Dictionary = _cols[j]
	var opened := false
	for it: Dictionary in [r, c]:
		if it.get("group", false) and is_collapsed(it["key"]):
			collapsed.erase(it["key"])
			opened = true
	if opened:
		_relayout()
		return
	if r.get("group", false) or c.get("group", false):
		say("open a group's ports to patch them")
		return
	if not toggle.is_valid():
		return
	var words: String = toggle.call(r["key"], c["key"])
	refresh()
	if not words.is_empty():
		say(words)


func _nudge_pin(pin: Pin, notches: int, fine: bool) -> bool:
	if pin.r < 0:
		return false
	if fine:
		return _wheel(0, -notches * WHEEL_LINES)
	var st := cell(pin.r, pin.c)
	var latched := Time.get_ticks_msec() < _wheel_until
	if not latched and st.get("on", false) and float(st.get("level", -1.0)) >= 0.0 and level.is_valid():
		var took: bool = level.call(_rows[pin.r]["key"], _cols[pin.c]["key"], notches, false)
		refresh()
		return took
	return _wheel(-notches * WHEEL_LINES, 0)


func _describe_pin(pin: Pin) -> PackedStringArray:
	if pin.r < 0 or pin.c < 0:
		return PackedStringArray(["SPARE PIN", "", ""])
	var r: Dictionary = _rows[pin.r]
	var c: Dictionary = _cols[pin.c]
	if describe.is_valid():
		return describe.call(r["key"], c["key"])
	return PackedStringArray(["%s  →  %s" % [str(r["name"]).to_upper(), str(c["name"]).to_upper()], "", ""])


func _describe_line(line: Line) -> PackedStringArray:
	if line.index < 0:
		return PackedStringArray(["SPARE %s HEADER" % ("ROW" if line.is_row else "COLUMN"), "", ""])
	var it: Dictionary = (_rows if line.is_row else _cols)[line.index]
	var out := PackedStringArray(["%s  %s" % [str(it["name"]).to_upper(), row_word if line.is_row else col_word], "", ""])
	if describe_line.is_valid():
		out = describe_line.call(it, line.is_row)
	if (row_meter if line.is_row else col_meter).is_valid():
		var level := line_level_words(it["key"], line.is_row)
		out[1] = level if out[1].is_empty() else "%s · %s" % [out[1], level]
	return out


## One crossing's place to press: no mesh of its own (the matrix's banks draw every pin in a
## handful of calls), only the box a ray or a fingertip lands on, as big as the cell.
class Pin extends ControlAffordance:
	var matrix: PinMatrix
	## Its slot in the matrix's pool and its banks.
	var slot := 0
	## The row and column it is over now (shown indices), -1 when the window has no line here.
	var r := -1
	var c := -1
	var _shape := CollisionShape3D.new()
	var _box := BoxShape3D.new()

	func _init() -> void:
		collision_mask = 0
		_shape.shape = _box
		_shape.position.z = 0.008
		add_child(_shape)
		hover_changed.connect(_on_hover)
		_apply()

	## Over crossing (row, col) at `at`, a cell `cell` big; (-1, -1) for nowhere, which hides it.
	func point(row: int, col: int, at: Vector3, cell: Vector2) -> void:
		if row != r or col != c:
			# Re-pointed: whoever held the crossing it was over does not hold this one.
			claimed_by = null
		r = row
		c = col
		position = at
		_box.size = Vector3(cell.x * 0.96, cell.y * 0.96, 0.016)
		_apply()

	func _apply() -> void:
		var on := r >= 0 and c >= 0
		visible = on
		collision_layer = 2 if on else 0
		_shape.disabled = not on

	func _on_hover(on: bool) -> void:
		if on:
			matrix._light(r, c, self)
		else:
			matrix._unlight(self)

	func cell() -> Dictionary:
		return matrix.cell(r, c)

	func _on_grab_begin(at: Vector3) -> void:
		matrix._begin(self, at)

	func _on_grab_move(at: Vector3) -> void:
		matrix._move(self, at)

	func _on_grab_end() -> void:
		matrix._end(self)

	func _on_nudge(notches: int, fine: bool) -> bool:
		return matrix._nudge_pin(self, notches, fine)

	func dwell_activates() -> bool:
		return false

	func _default_title() -> String:
		return matrix._describe_pin(self)[0]

	func _default_readout() -> String:
		return matrix._describe_pin(self)[1]

	func hint() -> String:
		return matrix._describe_pin(self)[2]


## A row's or a column's header: hovering it lights its line, dragging or wheeling it scrolls its
## way, and a group's header folds the group away and opens it again.
class Line extends ControlAffordance:
	var matrix: PinMatrix
	var is_row := true
	var index := -1
	var _shape := CollisionShape3D.new()
	var _box := BoxShape3D.new()

	func _init() -> void:
		collision_mask = 0
		_shape.shape = _box
		_shape.position.z = 0.006
		add_child(_shape)
		hover_changed.connect(func(on: bool):
			if on:
				matrix._light(index if is_row else -1, -1 if is_row else index, self)
			else:
				matrix._unlight(self))
		_apply()

	func point(at_index: int, at: Vector3, cell: Vector2) -> void:
		index = at_index
		position = at
		_box.size = Vector3(cell.x * 0.98, cell.y * 0.96, 0.012)
		_apply()

	func _apply() -> void:
		var on := index >= 0
		visible = on
		collision_layer = 2 if on else 0
		_shape.disabled = not on

	func line() -> Dictionary:
		return matrix.row_line(index) if is_row else matrix.col_line(index)

	func _on_grab_begin(at: Vector3) -> void:
		matrix._begin(self, at)

	func _on_grab_move(at: Vector3) -> void:
		matrix._move(self, at)

	func _on_grab_end() -> void:
		matrix._end(self)

	func _on_nudge(notches: int, fine: bool) -> bool:
		if is_row and not fine:
			return matrix._wheel(-notches * WHEEL_LINES, 0)
		return matrix._wheel(0, -notches * WHEEL_LINES)

	func _default_title() -> String:
		return matrix._describe_line(self)[0]

	func _default_readout() -> String:
		return matrix._describe_line(self)[1]

	func hint() -> String:
		return matrix._describe_line(self)[2]


## A scroll bar: a track the window's share long, and a thumb that is the window. Drag it, or
## wheel over it.
class Bar extends ControlAffordance:
	var matrix: PinMatrix
	var vertical := true
	var length := 0.1
	var _shape := CollisionShape3D.new()
	var _box := BoxShape3D.new()
	var _track: MeshInstance3D
	var _thumb: MeshInstance3D
	var _from := 0.0
	var _grabbed_at := Vector3.ZERO

	func _init() -> void:
		collision_mask = 0
		_shape.shape = _box
		_shape.position.z = 0.006
		add_child(_shape)
		_track = _quad(Color(0.13, 0.135, 0.15))
		_thumb = _quad(Color(0.45, 0.6, 0.82))
		_thumb.position.z = 0.0012

	func _ready() -> void:
		matrix.scrolled.connect(_lay_thumb)

	func _quad(colour: Color) -> MeshInstance3D:
		var q := MeshInstance3D.new()
		q.mesh = QuadMesh.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = colour
		q.material_override = m
		q.position.z = 0.0008
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(q)
		return q

	func lay(on: bool, at: Vector3, size: Vector2) -> void:
		visible = on
		collision_layer = 2 if on else 0
		_shape.disabled = not on
		position = at
		length = size.y if vertical else size.x
		_box.size = Vector3(size.x * 1.2 if vertical else size.x, size.y if vertical else size.y * 1.2, 0.012)
		(_track.mesh as QuadMesh).size = size
		_lay_thumb()

	## The thumb's span: the window's share of the lines, where the window is.
	func _lay_thumb() -> void:
		if _thumb == null:
			return
		var total := float(matrix.row_count() if vertical else matrix.col_count())
		var shown := float(matrix.shown_rows() if vertical else matrix.shown_cols())
		var first := matrix._top if vertical else matrix._left
		var share := clampf(shown / maxf(total, 1.0), 0.08, 1.0)
		var span := length * share
		var at := (first / maxf(total - shown, 1.0)) * (length - span) if total > shown else 0.0
		var across := matrix.bar * 0.7
		(_thumb.mesh as QuadMesh).size = Vector2(across, span) if vertical else Vector2(span, across)
		if vertical:
			_thumb.position = Vector3(0, length * 0.5 - span * 0.5 - at, 0.0012)
		else:
			_thumb.position = Vector3(-length * 0.5 + span * 0.5 + at, 0, 0.0012)

	func _on_grab_begin(at: Vector3) -> void:
		_grabbed_at = matrix.to_local(at)
		_from = matrix._want_top if vertical else matrix._want_left
		# A press on the track off the thumb sends the window there first.
		var local := to_local(at)
		var total := float(matrix.row_count() if vertical else matrix.col_count())
		var shown := float(matrix.shown_rows() if vertical else matrix.shown_cols())
		var along := (0.5 - local.y / length) if vertical else (0.5 + local.x / length)
		var want := clampf(along * total - shown * 0.5, 0.0, maxf(total - shown, 0.0))
		var first := matrix._want_top if vertical else matrix._want_left
		if want < first - 0.5 or want > first + 0.5:
			_from = roundf(want)
			if vertical:
				matrix.scroll_to(int(_from), matrix.first_col(), false)
			else:
				matrix.scroll_to(matrix.first_row(), int(_from), false)

	func _on_grab_move(at: Vector3) -> void:
		var d := matrix.to_local(at) - _grabbed_at
		var total := float(matrix.row_count() if vertical else matrix.col_count())
		var lines_per_m := total / maxf(length, 0.001)
		var to := _from + (-d.y if vertical else d.x) * lines_per_m
		if vertical:
			matrix._want_top = clampf(to, 0.0, matrix._most_top())
		else:
			matrix._want_left = clampf(to, 0.0, matrix._most_left())

	func _on_grab_end() -> void:
		matrix._want_top = clampf(roundf(matrix._want_top), 0.0, matrix._most_top())
		matrix._want_left = clampf(roundf(matrix._want_left), 0.0, matrix._most_left())

	func _on_nudge(notches: int, _fine: bool) -> bool:
		return matrix._wheel(-notches * WHEEL_LINES, 0) if vertical else matrix._wheel(0, -notches * WHEEL_LINES)

	func _default_title() -> String:
		return "%s SCROLL BAR" % ("ROWS" if vertical else "COLUMNS")

	func _default_readout() -> String:
		var first := matrix.first_row() if vertical else matrix.first_col()
		var shown := matrix.shown_rows() if vertical else matrix.shown_cols()
		return "%d-%d of %d" % [first + 1, first + shown, matrix.row_count() if vertical else matrix.col_count()]

	func hint() -> String:
		return "drag it, or wheel over it, to scroll the %s" % ("rows" if vertical else "columns")


## An arrow at a scroll bar's end: a press moves the window most of a window's worth that way.
class Arrow extends ControlAffordance:
	var matrix: PinMatrix
	var vertical := true
	var step := 1
	var _shape := CollisionShape3D.new()
	var _box := BoxShape3D.new()
	var _face: MeshInstance3D
	var _arrow: MeshInstance3D

	func _init() -> void:
		collision_mask = 0
		_shape.shape = _box
		_shape.position.z = 0.006
		add_child(_shape)
		_face = MeshInstance3D.new()
		_face.mesh = QuadMesh.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.17, 0.18, 0.2)
		_face.material_override = m
		_face.position.z = 0.0008
		add_child(_face)
		_arrow = MeshInstance3D.new()
		_arrow.mesh = _triangle()
		var a := StandardMaterial3D.new()
		a.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		a.albedo_color = Color(0.86, 0.88, 0.92)
		a.cull_mode = BaseMaterial3D.CULL_DISABLED
		_arrow.material_override = a
		_arrow.position.z = 0.0014
		add_child(_arrow)

	static func _triangle() -> ArrayMesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_normal(Vector3.BACK)
		for v in [Vector3(0, 0.32, 0), Vector3(-0.34, -0.24, 0), Vector3(0.34, -0.24, 0)]:
			st.add_vertex(v)
		return st.commit()

	func lay(on: bool, at: Vector3, size: float) -> void:
		visible = on
		collision_layer = 2 if on else 0
		_shape.disabled = not on
		position = at
		_box.size = Vector3(size, size, 0.012)
		(_face.mesh as QuadMesh).size = Vector2(size, size) * 0.92
		_arrow.scale = Vector3.ONE * size
		# Drawn pointing up; turned to point the way it goes.
		_arrow.rotation.z = (0.0 if step < 0 else PI) if vertical else (PI * 0.5 if step < 0 else -PI * 0.5)

	func _on_grab_begin(_at: Vector3) -> void:
		var by := maxi((matrix.shown_rows() if vertical else matrix.shown_cols()) - 1, 1) * step
		if vertical:
			matrix.scroll_by(by, 0)
		else:
			matrix.scroll_by(0, by)

	func _on_nudge(notches: int, _fine: bool) -> bool:
		return matrix._wheel(-notches * WHEEL_LINES, 0) if vertical else matrix._wheel(0, -notches * WHEEL_LINES)

	func dwell_activates() -> bool:
		return true

	func _default_title() -> String:
		if vertical:
			return "%s ROWS  %s" % [matrix.row_word, "UP" if step < 0 else "DOWN"]
		return "%s COLUMNS  %s" % [matrix.col_word, "LEFT" if step < 0 else "RIGHT"]

	func _default_readout() -> String:
		return matrix.position_words()

	func hint() -> String:
		return "press to scroll a window's worth that way"


## A tower's top, in the skyline (PinMatrix.skyline): the control that sets the send its pin is.
## Drag it up or down the board, or pull it out and push it in, and the send follows (one undo
## step a drag); wheel it as a pin; press and let go without moving and the pin comes out, as a
## press on its crossing does. No mesh of its own: the matrix's bank draws the tower.
class Tower extends ControlAffordance:
	var matrix: PinMatrix
	var pin: Pin
	## Whether it stands now, and how tall (m).
	var up := false
	var tall := 0.0
	## The level the tower shows while a hand has it (dBFS), NAN when it follows what it carries.
	var held_db := NAN
	var _start := Vector3.ZERO
	var _moved := false
	var _from_db := 0.0
	var _peak_from := 0.0
	var _notched := 0.0
	var _shape := CollisionShape3D.new()
	var _box := BoxShape3D.new()

	func _init() -> void:
		collision_mask = 0
		_shape.shape = _box
		add_child(_shape)
		edits_as_one = true
		describe_edit = func() -> String: return "%s: send level" % matrix._describe_pin(pin)[0]
		hover_changed.connect(func(on: bool) -> void:
			if on:
				matrix._light(pin.r, pin.c, self)
			else:
				matrix._unlight(self))
		lay(false, Vector3.ZERO, 0.0, 0.0)

	## Standing over a pin at `at`, a cell `small` across, `height` tall; or not at all.
	func lay(on: bool, at: Vector3, small: float, height: float) -> void:
		if not on and not up and not visible:
			return
		up = on
		tall = height
		visible = on
		collision_layer = 2 if on else 0
		_shape.disabled = not on
		if not on:
			if held_by == null:
				claimed_by = null
			return
		position = at + Vector3(0, 0, small * 0.1 + height)
		_box.size = Vector3(small * 0.8, small * 0.8, maxf(small * 0.5, 0.012))

	func _on_grab_begin(at: Vector3) -> void:
		matrix._tower_begin(self, at)

	func _on_grab_move(at: Vector3) -> void:
		matrix._tower_move(self, at)

	func _on_grab_end() -> void:
		matrix._tower_end(self)

	func _on_nudge(notches: int, fine: bool) -> bool:
		return matrix._nudge_pin(pin, notches, fine)

	func dwell_activates() -> bool:
		return false

	func _default_title() -> String:
		return matrix._describe_pin(pin)[0]

	func _default_readout() -> String:
		return matrix._describe_pin(pin)[1]

	func hint() -> String:
		return "drag the top up or down, or pull it out of the board, for the send's level, one undo step · wheel 1 dB, Shift 0.1 · a click pulls the pin out"
