class_name StageVoice
extends ControlAffordance

## One track on the stage table (StageTable; docs/spatial_loop.md slice 18, idea #1): a lit
## sphere lettered with the track's number, standing where the track sits in the mix. Across the
## table is its pan, its distance back from the front edge its level, and the ring round its foot
## its width.
##
## Taken hold of, it is placed: by a mouse on the table's plane, by a hand, or by a controller.
## Its frame is turned so its own +Z is the table's up, so a held ray stays in the plane through
## its middle (Interactor._plane_point) and a fingertip's point is read straight down onto the
## table. A press is not a write: it moves nothing until the hand has gone DRAG_START, and two
## presses without a drag within StageTable.DOUBLE_PRESS put the track back (StageTable.reset).
## The whole of a placing is one edit (edits_as_one), so pan and volume are one undo step.
##
## Muted, it is dimmed and struck through; soloed, it wears a halo over it. Neither is told by
## colour: the sphere keeps the track's own colour either way, and the tag says MUTE or SOLO.

## How far above the table top the sphere's middle is, and how big it is (m). Its size is not
## its width: the ring is.
const LIFT := 0.035
const RADIUS := 0.016
## How far the hand must go before a press is a drag (m): less is a press, and moves nothing.
const DRAG_START := 0.005

var table: StageTable
## The track, as the cache numbers it (bank-relative, 1 first).
var track := 0
## The ring round its foot: its width, a control of its own. Null where the DAW cannot set a
## width (Capability.WIDTH), which the card says.
var ring: Ring = null

var _sphere: MeshInstance3D
var _paint: StandardMaterial3D
var _number: Label3D
var _slash: MeshInstance3D
var _halo: MeshInstance3D
var _dragged := false
var _from := Vector2.ZERO
var _offset := Vector2.ZERO


func _init() -> void:
	edits_as_one = true
	describe_edit = func() -> String:
		var t := _state()
		var who := t.display_name() if t != null else "Track %d" % track
		# A wheel turn is the level alone; a grab is a placing.
		return "%s: %s" % [who, "place" if held_by != null else "level"]


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	# Its +Z the table's up: see the class comment.
	basis = Basis(Vector3.RIGHT, -PI * 0.5)
	var shape := CollisionShape3D.new()
	var ball := SphereShape3D.new()
	# A little bigger than it is drawn: a 3 cm ball across a table is a small thing to hit.
	ball.radius = RADIUS * 1.6
	shape.shape = ball
	add_child(shape)
	_sphere = MeshInstance3D.new()
	_sphere.name = "Sphere"
	var mesh := SphereMesh.new()
	mesh.radius = RADIUS
	mesh.height = RADIUS * 2.0
	mesh.radial_segments = 20
	mesh.rings = 10
	_sphere.mesh = mesh
	_paint = StandardMaterial3D.new()
	_paint.roughness = 0.35
	_paint.emission_enabled = true
	_sphere.material_override = _paint
	add_child(_sphere)
	_number = Label3D.new()
	_number.name = "Number"
	_number.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_number.pixel_size = 0.0002
	_number.font_size = 110
	_number.modulate = Color(0.97, 0.95, 0.9)
	_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Over the ball, up the table's up (this frame's +Z).
	_number.position = Vector3(0, 0, RADIUS + 0.018)
	Lettering.range_to_legibility(_number)
	add_child(_number)
	# Struck through when muted: a bar across the ball as the player sees it (this frame's X and Z).
	_slash = MeshInstance3D.new()
	_slash.name = "Slash"
	var bar := BoxMesh.new()
	bar.size = Vector3(RADIUS * 3.4, 0.005, 0.005)
	_slash.mesh = bar
	_slash.rotation = Vector3(0, PI * 0.25, 0)
	_slash.material_override = Materials.legend()
	add_child(_slash)
	# A halo over it when soloed, lying level above the ball.
	_halo = MeshInstance3D.new()
	_halo.name = "Halo"
	var torus := TorusMesh.new()
	torus.inner_radius = RADIUS * 0.8
	torus.outer_radius = RADIUS * 1.05
	torus.rings = 24
	torus.ring_segments = 8
	_halo.mesh = torus
	_halo.rotation = Vector3(PI * 0.5, 0, 0)
	_halo.position = Vector3(0, 0, RADIUS + 0.006)
	_halo.material_override = Materials.led(Color(0.98, 0.84, 0.4), true)
	add_child(_halo)
	if DAW.can(DAWBackend.Capability.WIDTH):
		ring = Ring.new()
		ring.name = "Ring"
		ring.voice = self
		ring.position = Vector3(0, 0, -LIFT)
		add_child(ring)
	refresh()


func _state() -> MixState.TrackState:
	return DAW.state.track(track, false) if DAW.state != null else null


## Stand where the mix has this track, letter it and light it as its state says: unless a hand
## has it, when it stands where the hand put it.
func refresh() -> void:
	var t := _state()
	if t == null or _sphere == null:
		return
	if not is_held():
		position = StageTable.spot_of(t.pan, StageTable.db_of_volume(t.volume))
		table.lead(self)
	_number.text = str(StageTable.number_of(track))
	_slash.visible = t.mute
	_halo.visible = t.solo
	var colour := t.shown_colour()
	_paint.albedo_color = colour.darkened(0.55) if t.mute else colour
	_paint.emission = colour
	if ring != null:
		ring.show_width(t.width)
	glow(0.0)


## How lit it is: a muted track barely, any other by its meter, so a voice that sounds is seen to.
func glow(level: float) -> void:
	var t := _state()
	if t == null or _paint == null:
		return
	_paint.emission_energy_multiplier = 0.15 if t.mute else 0.55 + 1.6 * clampf(level, 0.0, 1.0)


# --- placing --------------------------------------------------------------------------------

func _on_grab_begin(at: Vector3) -> void:
	var p := table.to_local(at)
	begin_drag(Vector2(p.x, p.z))


func _on_grab_move(at: Vector3) -> void:
	var p := table.to_local(at)
	drag_to(Vector2(p.x, p.z))


func _on_grab_end() -> void:
	end_drag()


## Where on the table the hand took hold (table frame, x across and z toward the front): kept as
## an offset from the voice, so it does not jump to put its middle under the hand.
func begin_drag(at: Vector2) -> void:
	_dragged = false
	_from = Vector2(position.x, position.z)
	_offset = _from - at


## The hand is at `at` (table frame): once it has gone DRAG_START, the voice is placed there and
## stays there while it is held, whatever comes back from the mix meanwhile.
func drag_to(at: Vector2) -> void:
	var want := at + _offset
	if not _dragged and want.distance_to(_from) < DRAG_START:
		return
	_dragged = true
	var landed := table.place(track, want, _fine())
	position = Vector3(landed.x, LIFT, landed.y)
	table.lead(self)


## Let go: a press with no drag is counted toward a double press, a drag ends any.
func end_drag() -> void:
	if _dragged:
		table.forget_press(track)
	else:
		table.pressed(track)
	_dragged = false
	# After the let-go, when it is no longer held and stands where the mix has it.
	refresh.call_deferred()


func _fine() -> bool:
	return held_by is Interactor and (held_by as Interactor).fine()


## The wheel or a thumbstick: half a decibel a notch, a tenth with the fine modifier. While the
## voice is held the level is where the hand has it, so the wheel is its width instead, and goes
## into the same edit as the placing (ControlAffordance.nudge): pan, level and width, one step.
func _on_nudge(notches: int, fine: bool) -> bool:
	if is_held() and ring != null:
		return table.nudge_width(track, notches, fine)
	return table.nudge_volume(track, notches, fine)


func _on_value_changed() -> void:
	refresh()


# --- saying what it is ----------------------------------------------------------------------

func _default_title() -> String:
	return table.title_of(track) if table != null else "STAGE"


func _default_readout() -> String:
	return table.readout_of(track) if table != null else ""


func hint() -> String:
	return table.hint_of(track) if table != null else ""


## Not dwellable: dwelt on, a voice would take the mix somewhere nobody asked.
func dwell_activates() -> bool:
	return false


## The ring round a voice's foot: its width, from 2 cm across for mono to 8 cm for full width
## (StageTable.ring_of). Dragged out, wider; in, narrower; the wheel too, five percent a notch.
## Lying on the table, its own +Z the table's up as the voice's is, so a held ray stays in the
## table's plane. One edit a drag, so on Reaper a drag is one call and one undo point.
class Ring extends ControlAffordance:
	var voice: StageVoice
	var _band: MeshInstance3D
	var _torus: TorusMesh
	var _hit: CylinderShape3D
	var _shown := -1.0
	## How far out from the ring the hand took hold, kept, so taking hold does not jump it.
	var _grip := 0.0

	func _init() -> void:
		edits_as_one = true
		describe_edit = func() -> String:
			var t := voice._state() if voice != null else null
			return "%s: width" % (t.display_name() if t != null else "Track")

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		var shape := CollisionShape3D.new()
		_hit = CylinderShape3D.new()
		_hit.height = 0.008
		shape.shape = _hit
		shape.rotation = Vector3(PI * 0.5, 0, 0)
		shape.position = Vector3(0, 0, 0.004)
		add_child(shape)
		_band = MeshInstance3D.new()
		_band.name = "Band"
		_torus = TorusMesh.new()
		_torus.rings = 40
		_torus.ring_segments = 6
		_band.mesh = _torus
		_band.rotation = Vector3(PI * 0.5, 0, 0)
		_band.position = Vector3(0, 0, 0.003)
		_band.material_override = Materials.legend()
		add_child(_band)
		show_width(_shown if _shown >= 0.0 else 1.0)
		set_meta(&"stage_track", voice.track)

	## Drawn at `width`'s radius, and taken hold of a little beyond it.
	func show_width(width: float) -> void:
		_shown = width
		if _torus == null:
			return
		var r := StageTable.ring_of(width)
		_torus.inner_radius = r - 0.0025
		_torus.outer_radius = r + 0.0025
		_hit.radius = r + 0.012

	func _reach(at: Vector3) -> float:
		var p := voice.table.to_local(at)
		return Vector2(p.x, p.z).distance_to(Vector2(voice.position.x, voice.position.z))

	func _on_grab_begin(at: Vector3) -> void:
		_grip = StageTable.ring_of(_shown if _shown >= 0.0 else 1.0) - _reach(at)

	func _on_grab_move(at: Vector3) -> void:
		var w := StageTable.width_of(_reach(at) + _grip)
		show_width(w)
		var t := voice._state()
		if t != null and absf(t.width - w) > 0.0005:
			DAW.set_track_width(voice.track, w)

	func _on_grab_end() -> void:
		var t := voice._state()
		if t != null:
			show_width(t.width)

	func _on_nudge(notches: int, fine: bool) -> bool:
		var t := voice._state()
		if t == null:
			return false
		voice.table.nudge_width(voice.track, notches, fine)
		show_width(t.width)
		return true

	func _default_title() -> String:
		return "%s  WIDTH" % voice.table.title_of(voice.track)

	func dwell_activates() -> bool:
		return false

	func _default_readout() -> String:
		var t := voice._state()
		return "width %d%%" % roundi(t.width * 100.0) if t != null else ""

	func hint() -> String:
		return "drag out for wider, in toward the ball for narrower, down to mono  ·  wheel 5% a notch, Shift 1%"
