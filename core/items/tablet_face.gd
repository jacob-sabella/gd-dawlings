class_name TabletFace
extends Node3D

## What the tablet shows the person holding it: their personal mix (PersonalMix), as a cue
## mixer's face. Four receivers, A to D, a row each: what it is patched to, a level, and a meter
## of what is coming through. Above the screen, in the tablet's tray, a wireless plug for each:
## drag one onto a SEND socket in the room and its receiver hears that socket; click one that is
## out, and it comes back.
##
## Only ever built on the machine of the hand that holds it, which is what "only you see it"
## comes to: everybody else's copy of the tablet has a dark screen. Laid out in its own frame: X
## along the screen, Y up it (toward the tray), Z out of the glass.

## A plug was dropped on `socket` (or brought back, for none): for the studio to ask the room.
signal patch_asked(receiver: int, socket: StringName)
## The ON AIR switch flipped: for the studio to ask the room.
signal on_air_asked(on: bool)

## The glass, and the tray above it, in this frame (tools/blender/tablet.py).
const SCREEN := Vector2(0.238, 0.142)
const TRAY_AT := Vector3(0.0, 0.085, -0.0043)
const TRAY_WIDTH := 0.236
const ROW_TOP := 0.029
const ROW_STEP := 0.026
## A level slider's travel along the row, and the meter under it.
const TRACK_FROM := -0.024
const TRACK_TO := 0.068
## The meter's range: below METER_FLOOR is nothing; the top is a little over unity.
const METER_FLOOR := -48.0
const METER_TOP := 6.0
## Lettering a screen's size: the console's scale (MasterSection._label), a touch smaller.
const PIXEL := 0.00016
const INK := Color(0.86, 0.88, 0.9)
const DIM := Color(0.45, 0.48, 0.52)
## The display's own colour, under everything on it.
const BACKLIGHT := Color(0.022, 0.03, 0.045)
## How far a dragged plug can be carried from its place in the tray before it stops following,
## so a drag across the room does not fling it off out of sight.
const DRAG_REACH := 0.3

var mix: PersonalMix
## The holder's colour: the plugs' light, and the chips.
var colour := Color(0.95, 0.62, 0.22)
## Whether headphones are on this person's head, for the header.
var listening := false:
	set(v):
		listening = v
		_refresh()

## Whether this person is ON AIR: anyone may plug into their monitor (TheirMonitor).
var on_air := false:
	set(v):
		on_air = v
		_refresh()

var _rows: Array[Dictionary] = []
var _senders: Array[Sender] = []
var _status: Label3D
var _air: OnAirSwitch


func _ready() -> void:
	# The display itself: lit from behind, so the room's lamps do not grey it.
	var back := _bar(Vector3(0, 0, -0.0002), SCREEN, BACKLIGHT)
	back.name = "Backlight"
	var header := _text(11, Vector3(-SCREEN.x * 0.5 + 0.01, SCREEN.y * 0.5 - 0.013, 0), HORIZONTAL_ALIGNMENT_LEFT)
	header.text = "PERSONAL MIX"
	_status = _text(9, Vector3(SCREEN.x * 0.5 - 0.01, SCREEN.y * 0.5 - 0.013, 0), HORIZONTAL_ALIGNMENT_RIGHT)
	_air = OnAirSwitch.new()
	_air.face = self
	_air.position = Vector3(0.012, SCREEN.y * 0.5 - 0.0125, 0.0004)
	add_child(_air)
	# A rule under the header, as a screen draws one.
	_bar(Vector3(0, SCREEN.y * 0.5 - 0.022, 0), Vector2(SCREEN.x - 0.02, 0.0007), DIM)
	for i in PersonalMix.RECEIVERS:
		var y := ROW_TOP - i * ROW_STEP
		var row := {}
		var chip := _bar(Vector3(-SCREEN.x * 0.5 + 0.017, y, 0), Vector2(0.013, 0.013), colour * 0.55)
		row["chip"] = chip
		var letter := _text(10, Vector3(-SCREEN.x * 0.5 + 0.017, y - 0.0005, 0.0003), HORIZONTAL_ALIGNMENT_CENTER)
		letter.text = PersonalMix.LETTERS[i]
		letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row["source"] = _text(10, Vector3(-SCREEN.x * 0.5 + 0.03, y, 0), HORIZONTAL_ALIGNMENT_LEFT)
		row["source"].vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_bar(Vector3((TRACK_FROM + TRACK_TO) * 0.5, y + 0.003, 0), Vector2(TRACK_TO - TRACK_FROM, 0.0012), DIM * 0.7)
		var meter_back := _bar(Vector3((TRACK_FROM + TRACK_TO) * 0.5, y - 0.0055, 0),
				Vector2(TRACK_TO - TRACK_FROM, 0.0022), Color(0.07, 0.085, 0.11))
		meter_back.position.z = -0.0001
		var meter := _bar(Vector3(TRACK_FROM, y - 0.0055, 0.0001), Vector2(1.0, 0.0022), Color(0.35, 0.85, 0.45))
		row["meter"] = meter
		var slider := LevelSlider.new()
		slider.face = self
		slider.receiver = i
		slider.position = Vector3(0, y + 0.003, 0.0004)
		add_child(slider)
		row["slider"] = slider
		row["db"] = _text(9, Vector3(SCREEN.x * 0.5 - 0.01, y, 0), HORIZONTAL_ALIGNMENT_RIGHT)
		row["db"].vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_rows.append(row)
		var sender := Sender.new()
		sender.face = self
		sender.receiver = i
		sender.position = cradle(i)
		add_child(sender)
		_senders.append(sender)
		# The receiver's letter on the tray's floor, beside its plug.
		var tray_letter := _text(8, cradle(i) + Vector3(-0.026, 0, -0.0035), HORIZONTAL_ALIGNMENT_CENTER)
		tray_letter.text = PersonalMix.LETTERS[i]
		tray_letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var footer := _text(8, Vector3(0, -SCREEN.y * 0.5 + 0.009, 0), HORIZONTAL_ALIGNMENT_CENTER)
	footer.text = "drag a plug onto a SEND socket   ·   click one that is out to bring it back"
	footer.modulate = DIM
	if mix != null:
		mix.changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if mix != null and mix.changed.is_connected(_refresh):
		mix.changed.disconnect(_refresh)


## Where receiver `i`'s plug lies in the tray, in this frame: its middle over its cell.
func cradle(i: int) -> Vector3:
	return TRAY_AT + Vector3((i - (PersonalMix.RECEIVERS - 1) * 0.5) * TRAY_WIDTH / PersonalMix.RECEIVERS + 0.006, 0, 0.0082)


## A level's place along its slider, 0 to 1, from its dB, and back: even in dB, the top a
## little over unity.
static func level_to_x(db: float) -> float:
	return clampf((db - PersonalMix.FLOOR_DB) / (PersonalMix.TOP_DB - PersonalMix.FLOOR_DB), 0.0, 1.0)


static func x_to_level(x: float) -> float:
	return lerpf(PersonalMix.FLOOR_DB, PersonalMix.TOP_DB, clampf(x, 0.0, 1.0))


func _process(_delta: float) -> void:
	if mix == null:
		return
	for i in _rows.size():
		var bus := mix.bus_of(i)
		var db := METER_FLOOR
		var at := AudioServer.get_bus_index(bus) if bus != &"" else -1
		var gain := Ears.gain_db(bus)
		var track := PersonalMix.track_of(mix.sockets[i])
		if at < 0 and bus != &"" and track > 0:
			# A track's cue plays only while headphones are on; until then, the track's own bus
			# says what it would carry.
			at = AudioServer.get_bus_index(GodotBackend.BUS_PREFIX + str(track))
			gain = 0.0
		if at >= 0:
			var peak := maxf(AudioServer.get_bus_peak_volume_left_db(at, 0), AudioServer.get_bus_peak_volume_right_db(at, 0))
			# The bus's peak is after the headphones' gain on it (Ears); this receiver's share is
			# the source as it comes, at this receiver's level.
			db = peak - gain + mix.levels_db[i]
		var meter: MeshInstance3D = _rows[i]["meter"]
		var f := clampf((db - METER_FLOOR) / (METER_TOP - METER_FLOOR), 0.0, 1.0)
		var length := (TRACK_TO - TRACK_FROM) * f
		meter.visible = length > 0.0005
		meter.scale.x = maxf(length, 0.0001)
		meter.position.x = TRACK_FROM + length * 0.5


func _refresh() -> void:
	if _status == null or mix == null:
		return
	_status.text = "HEADPHONES ON" if listening else "HEADPHONES OFF"
	_status.modulate = Color(0.55, 0.85, 0.6) if listening else INK * 0.75
	if _air != null:
		_air.show_on(on_air)
	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var socket := mix.sockets[i]
		var source: Label3D = row["source"]
		if socket == &"":
			source.text = "plug %s in the tray" % PersonalMix.LETTERS[i]
			source.modulate = DIM
		else:
			source.text = PersonalMix.title_of(socket)
			source.modulate = DIM if mix.unheard(i) else INK
		(row["chip"] as MeshInstance3D).material_override = _flat(colour if socket != &"" else colour * 0.35)
		var db: float = mix.levels_db[i]
		(row["db"] as Label3D).text = "not here" if mix.unheard(i) \
				else "off" if db <= PersonalMix.FLOOR_DB else "%+.0f dB" % db
		(row["db"] as Label3D).modulate = INK if socket != &"" and not mix.unheard(i) else DIM
		(row["slider"] as LevelSlider).show_level(db)
		_senders[i].show_out(socket != &"")


func _text(size: int, pos: Vector3, align: HorizontalAlignment) -> Label3D:
	var l := Label3D.new()
	l.font_size = size * 4
	l.pixel_size = PIXEL
	l.position = pos
	l.modulate = INK
	l.horizontal_alignment = align
	Lettering.range_to_legibility(l)
	add_child(l)
	return l


func _bar(pos: Vector3, size: Vector2, tint: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	m.mesh = quad
	m.position = pos
	m.material_override = _flat(tint)
	add_child(m)
	return m


## A colour drawn as a screen draws it: lit by itself, not by the room.
static func _flat(tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = tint
	return m


## ON AIR: a lit key in the header. On, anyone may plug into this person's monitor and hear
## their keys in time with the backing they play to; everyone sees the sign on their pack.
class OnAirSwitch extends ControlAffordance:
	const SIZE := Vector2(0.042, 0.011)
	var face: TabletFace
	var _key: MeshInstance3D
	var _word: Label3D

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(SIZE.x + 0.004, SIZE.y + 0.004, 0.006)
		shape.shape = box
		add_child(shape)
		_key = MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = SIZE
		_key.mesh = quad
		add_child(_key)
		_word = face._text(9, Vector3(0, 0, 0.0002), HORIZONTAL_ALIGNMENT_CENTER)
		_word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_word.text = "ON AIR"
		face.remove_child(_word)
		add_child(_word)
		show_on(face.on_air)

	func show_on(on: bool) -> void:
		if _key == null:
			return
		_key.material_override = TabletFace._flat(Color(0.85, 0.12, 0.1) if on else Color(0.09, 0.1, 0.12))
		_word.modulate = Color(1.0, 0.94, 0.92) if on else DIM

	func personal() -> bool:
		return true

	func title() -> String:
		return "ON AIR"

	func readout() -> String:
		return "on: anyone can plug into your monitor" if face.on_air else "off"

	func hint() -> String:
		return "click: let the room hear you in time with the backing you play to"

	func _on_grab_begin(_at: Vector3) -> void:
		face.on_air_asked.emit(not face.on_air)

	func _foley_contact() -> AudioStream:
		return Foley.plug_seat()


## A receiver's level: drag along the row, or scroll over it.
class LevelSlider extends ControlAffordance:
	const STEP_DB := 1.0
	const FINE_DB := 0.25
	var face: TabletFace
	var receiver := 0
	var _cap: MeshInstance3D

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(TRACK_TO - TRACK_FROM + 0.01, 0.014, 0.006)
		shape.shape = box
		shape.position.x = (TRACK_FROM + TRACK_TO) * 0.5
		add_child(shape)
		_cap = MeshInstance3D.new()
		var cap := BoxMesh.new()
		cap.size = Vector3(0.0045, 0.009, 0.002)
		_cap.mesh = cap
		_cap.material_override = TabletFace._flat(Color(0.82, 0.84, 0.86))
		add_child(_cap)

	func show_level(db: float) -> void:
		if _cap != null:
			_cap.position.x = lerpf(TRACK_FROM, TRACK_TO, TabletFace.level_to_x(db))

	func personal() -> bool:
		return true

	func title() -> String:
		return "RECEIVER %s  LEVEL" % PersonalMix.LETTERS[receiver]

	func readout() -> String:
		var db: float = face.mix.levels_db[receiver]
		return "off" if db <= PersonalMix.FLOOR_DB else "%+.1f dB" % db

	func hint() -> String:
		return "drag or scroll: how loud it is in your headphones"

	func _on_grab_begin(at: Vector3) -> void:
		_set_from(at)

	func _on_grab_move(at: Vector3) -> void:
		_set_from(at)

	func _on_nudge(notches: int, fine: bool) -> bool:
		face.mix.set_level(receiver, face.mix.levels_db[receiver] + notches * (FINE_DB if fine else STEP_DB))
		return true

	func _set_from(at: Vector3) -> void:
		var x := to_local(at).x
		face.mix.set_level(receiver, TabletFace.x_to_level((x - TRACK_FROM) / (TRACK_TO - TRACK_FROM)))

	func _foley_contact() -> AudioStream:
		return null


## A receiver's wireless plug, lying in the tray: drag it onto a SEND socket to patch it, and
## click it once it is out to bring it back.
class Sender extends ControlAffordance:
	var face: TabletFace
	var receiver := 0
	var _plug: Node3D
	var _out := false
	var _moved := false
	var _from := Vector3.ZERO

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.06, 0.02, 0.02)
		shape.shape = box
		add_child(shape)
		_plug = SendSocket.make_plug(face.colour)
		# Lying along the tray, tip toward +X, its middle over the cell.
		_plug.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5) * Basis(Vector3.FORWARD, 0.0), Vector3(-0.0035, 0, 0))
		add_child(_plug)

	## Out in a socket: its place in the tray is empty.
	func show_out(out: bool) -> void:
		_out = out
		if _plug != null and held_by == null:
			_plug.visible = not out
			_plug.position = Vector3(-0.0035, 0, 0)

	func personal() -> bool:
		return true

	func title() -> String:
		return "PLUG %s" % PersonalMix.LETTERS[receiver]

	func readout() -> String:
		var socket: StringName = face.mix.sockets[receiver]
		if socket == &"":
			return "in the tray"
		return "in SEND " + PersonalMix.title_of(socket) + (": not heard on this machine" if face.mix.unheard(receiver) else "")

	func hint() -> String:
		return "click to bring it back" if _out else "drag onto a SEND socket"

	func _on_grab_begin(at: Vector3) -> void:
		_moved = false
		_from = at
		_plug.visible = true

	func _on_grab_move(at: Vector3) -> void:
		if at.distance_to(_from) > 0.01:
			_moved = true
		var local := to_local(at)
		_plug.position = local.limit_length(DRAG_REACH) + Vector3(0, 0, 0.012)

	func _on_grab_end() -> void:
		var under: ControlAffordance = (held_by as Interactor).hovered if held_by is Interactor else null
		if under is SendSocket:
			face.patch_asked.emit(receiver, (under as SendSocket).source)
		elif _out and not _moved:
			face.patch_asked.emit(receiver, &"")
		_plug.position = Vector3(-0.0035, 0, 0)
		_plug.visible = not _out

	func _foley_contact() -> AudioStream:
		return Foley.plug_seat()
