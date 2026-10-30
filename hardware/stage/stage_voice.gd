class_name StageVoice
extends ControlAffordance

## One track on the stage table (StageTable; docs/spatial_loop.md slice 18, idea #1): a lit
## sphere, the track's number on the table at its foot, standing where the track sits in the mix. Across the
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
## Tracks at one pan and level stand in one place, and only the top ball of a pile can be taken.
## So each track can also be taken by the name on its tag (StageTable.NameGrip), which steers its
## voice from there (`steered`): drag, wheel, double press, all as on the ball. While its name is
## hovered or held, the voice stands raised over the rest (`pick`), so which ball it is is seen.
##
## Muted, it is dimmed and struck through; soloed, it wears a halo over it. Neither is told by
## colour: the sphere keeps the track's own colour either way, and the tag says MUTE or SOLO.
##
## A cassette pressed on the ball or its name pastes onto its track at the playhead (`pastes_onto`,
## docs/spatial_loop.md part two, slice 24).
##
## It stands on a stalk (`Stalk`, docs/spatial_loop.md slice 19), a handle of its own: lifted off
## the table, up to STALK_MOST, the voice sends that much to the room (StageTable.room_track), and
## a mist round the ball shows how much. Standing on the table, it sends nothing, however quiet it
## is: depth is never a side effect of level.
##
## Under the ball, on its stalk, is a knot (`Knot`, docs/spatial_loop.md slice 20): dragged from to
## another voice, it ties a rope (StageTable.Rope), a sidechain from this track to that one. While
## this voice has a rope out, an X beside its knot (`cut_key`) cuts them.

## How far above the table top the sphere's middle is when its stalk stands on the table, and how
## big it is (m). Its size is not its width: the ring is. High enough that the stalk under it, a
## handle of its own, shows between the ball and the ring.
const LIFT := 0.06
const RADIUS := 0.016
## Where the track's number lies on the table: this far toward the front edge from the stalk's
## foot, clear of it, and this far over the table top, so it is on it and not in it (m).
const NUMBER_OUT := 0.016
const NUMBER_OVER := 0.0015
## How far the stalk lifts it off the table, at most (m): the room send's top (StageTable.ROOM_TOP_DB).
const STALK_MOST := 0.3
## How far a stalk's rod stands off the table at its foot (m), so it lies in no plane of the top.
const ROD_CLEAR := 0.0003
## How far the hand must go before a press is a drag (m): less is a press, and moves nothing.
const DRAG_START := 0.005
## How far over a pile a voice stands while its tag's name is hovered or held (m).
const RAISE := 0.045
## How far under the ball's middle its knot is, how big it is drawn, and how far round it a hand
## takes it (m). Clear of the ball's own reach (BALL_REACH), and the stalk below it is the stalk.
const KNOT_DROP := 0.03
const KNOT_RADIUS := 0.005
const KNOT_REACH := 0.009
## How far round the ball's middle a hand takes the ball (m): a little bigger than it is drawn, as
## a 3 cm ball across a table is a small thing to hit, short of the knot under it.
const BALL_REACH := RADIUS * 1.3

var table: StageTable
## The track, as the cache numbers it (bank-relative, 1 first).
var track := 0
## The ring round its foot: its width, a control of its own. Null where the DAW cannot set a
## width (Capability.WIDTH), which the card says.
var ring: Ring = null
## Being placed from its tag's name (StageTable.NameGrip) rather than by a hand on it: it stands
## where that hand put it, as when held.
var steered := false
## Raised over the rest: its tag's name is hovered or held.
var picked := false
## The stalk under it: its send to the room.
var stalk: Stalk = null
## The knot under the ball, where its ropes are tied, and the X beside it while it has a rope out
## (null while it has none).
var knot: Knot = null
var cut_key: StageTable.TableKey = null

var _sphere: MeshInstance3D
var _paint: StandardMaterial3D
var _number: Label3D
var _slash: MeshInstance3D
var _halo: MeshInstance3D
var _mist: MeshInstance3D
var _mist_paint: StandardMaterial3D
## Where the stalk's hand has it while it is held (m off the table), or -1 for where its send has it.
var _lift_held := -1.0
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
	# A cassette pressed on the ball pastes on its track at the playhead (docs/spatial_loop.md part
	# two, slice 24): a click, a trigger, or the cassette pushed into it.
	pastes_onto = func() -> int: return track


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	# Its +Z the table's up: see the class comment.
	basis = Basis(Vector3.RIGHT, -PI * 0.5)
	var shape := CollisionShape3D.new()
	var ball := SphereShape3D.new()
	ball.radius = BALL_REACH
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
	# Flat on the table at the stalk's foot, read from the front edge: as this frame's +Z is the
	# table's up and its -Y toward the player, a label left unturned lies face up and the right way
	# round for them. Turned to the eye over the ball, it was one more word in the air.
	_number.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_number.double_sided = false
	_number.pixel_size = 0.0002
	_number.font_size = 110
	_number.modulate = Color(0.97, 0.95, 0.9)
	_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Just in front of the stalk's foot, toward the player; how far down the table is, `_stand`.
	_number.position = Vector3(0, -NUMBER_OUT, -LIFT + NUMBER_OVER)
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
	# The room's mist round it, as much as it sends: a shape, not a colour, so it reads in grey.
	_mist = MeshInstance3D.new()
	_mist.name = "Mist"
	var cloud := SphereMesh.new()
	cloud.radius = RADIUS
	cloud.height = RADIUS * 2.0
	cloud.radial_segments = 16
	cloud.rings = 8
	_mist.mesh = cloud
	_mist_paint = StandardMaterial3D.new()
	_mist_paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mist_paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mist_paint.albedo_color = Color(0.78, 0.84, 0.95, 0.2)
	_mist_paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mist.material_override = _mist_paint
	_mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mist.visible = false
	add_child(_mist)
	stalk = Stalk.new()
	stalk.name = "Stalk"
	stalk.voice = self
	add_child(stalk)
	knot = Knot.new()
	knot.name = "Knot"
	knot.voice = self
	knot.position = Vector3(0, 0, -KNOT_DROP)
	add_child(knot)
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
	if not is_held() and not steered:
		position = StageTable.spot_of(t.pan, StageTable.db_of_volume(t.volume))
		table.lead(self)
	_stand()
	_number.text = str(StageTable.number_of(track))
	_slash.visible = t.mute
	_halo.visible = t.solo
	var colour := t.shown_colour()
	_paint.albedo_color = colour.darkened(0.55) if t.mute else colour
	_paint.emission = colour
	if ring != null:
		ring.show_width(t.width)
	_show_cut()
	glow(0.0)


## The X beside the knot while this track has a rope out, and none while it has none: a key that
## is not there is not under a hand either.
func _show_cut() -> void:
	var out := table != null and not table.ropes_from(track).is_empty()
	if out == (cut_key != null):
		return
	if not out:
		cut_key.queue_free()
		cut_key = null
		return
	cut_key = StageTable.TableKey.new()
	cut_key.name = "Cut"
	cut_key.glyph = "X"
	# Beside the knot, its face up and toward the player (this frame's +Z is up, -Y toward them).
	cut_key.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.25), Vector3(0.026, 0, -KNOT_DROP))
	cut_key.describe_title = func() -> String: return "%s  CUT ROPE" % table.title_of(track)
	cut_key.describe_value = func(_v: float) -> String: return table.ropes_words(track)
	cut_key.says = "cuts this track's rope: its key send, and the compressor if the rope added it (one undo step)"
	cut_key.dwells = false
	cut_key.pressed.connect(func() -> void: table.cut_from(track))
	cut_key.set_meta(&"stage_track", track)
	add_child(cut_key)


## Raised over the rest, or set down again: its tag's name is hovered or held. The ring and the
## stalk's foot stay on the table.
func pick(on: bool) -> void:
	if picked == on:
		return
	picked = on
	_stand()


## How far its stalk lifts it off the table (m): where a hand holding the stalk has it, or else
## where its send to the room has it (StageTable.lift_of_send_db).
func lift() -> float:
	if _lift_held >= 0.0:
		return _lift_held
	return StageTable.lift_of_send_db(StageTable.room_send_db(track)) if table != null else 0.0


## The stalk's hand has it `at` (m off the table), or -1 for its send's again.
func hold_lift(at: float) -> void:
	_lift_held = clampf(at, 0.0, STALK_MOST) if at >= 0.0 else -1.0
	_stand()


func _height() -> float:
	return LIFT + lift() + (RAISE if picked else 0.0)


## Stood at its height: the ball over its stalk, the ring, the stalk's foot and the number on the
## table, and the mist as much as it sends.
func _stand() -> void:
	if _sphere == null:
		return
	var h := _height()
	position.y = h
	if ring != null:
		ring.position.z = -h
	_number.position.z = -h + NUMBER_OVER
	stalk.stand(h)
	var db := StageTable.send_db_of_lift(lift()) if _lift_held >= 0.0 else StageTable.room_send_db(track)
	_mist.visible = db != -INF
	if _mist.visible:
		var f := clampf((db - StageTable.ROOM_LOW_DB) / (StageTable.ROOM_TOP_DB - StageTable.ROOM_LOW_DB), 0.0, 1.0)
		_mist.scale = Vector3.ONE * (1.5 + 2.5 * f)
		_mist_paint.albedo_color.a = 0.08 + 0.2 * f


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
## stays there while it is held, whatever comes back from the mix meanwhile. `fine` is the hand's
## own unless a tag's name, steering it, says.
func drag_to(at: Vector2, fine: Variant = null) -> void:
	var want := at + _offset
	if not _dragged and want.distance_to(_from) < DRAG_START:
		return
	_dragged = true
	var landed := table.place(track, want, _fine() if fine == null else bool(fine))
	position = Vector3(landed.x, _height(), landed.y)
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
	return table.nudge_voice(track, is_held(), notches, fine)


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


## The stalk a voice stands on: its send to the room, and a handle of its own (docs/spatial_loop.md
## slice 19). Dragged up, the voice is lifted off the table and sends more; down onto the table,
## nothing. The wheel too, a decibel a notch (StageTable.ROOM_STEP), a tenth fine. Its frame is the
## table's own, turned back from the voice's, its foot on the table under the ball: so its +Z faces
## the player, and a held ray moves in the upright plane through it (Interactor._plane_point), up
## and down as the hand goes. One edit a drag, so a first lift that makes the send is one undo step
## with its level.
class Stalk extends ControlAffordance:
	var voice: StageVoice
	var _rod: MeshInstance3D
	var _cylinder: CylinderMesh
	var _shape: CollisionShape3D
	var _box: BoxShape3D
	## How far below the stalk's top the hand took hold, kept, so taking hold does not jump it.
	var _grip := 0.0
	var _room := 0

	func _init() -> void:
		edits_as_one = true
		describe_edit = func() -> String:
			var t := voice._state() if voice != null else null
			return "%s: room" % (t.display_name() if t != null else "Track")

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		# The voice's +Z is the table's up; this is the table's frame again, +Y up, +Z to the player.
		basis = Basis(Vector3.RIGHT, PI * 0.5)
		_rod = MeshInstance3D.new()
		_rod.name = "Rod"
		_cylinder = CylinderMesh.new()
		_cylinder.top_radius = 0.0025
		_cylinder.bottom_radius = 0.0035
		_cylinder.radial_segments = 8
		_cylinder.rings = 1
		_rod.mesh = _cylinder
		_rod.material_override = Materials.legend()
		_rod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_rod)
		_shape = CollisionShape3D.new()
		_box = BoxShape3D.new()
		_shape.shape = _box
		add_child(_shape)
		set_meta(&"stage_track", voice.track)

	## The voice's middle stands `height` over the table: the rod from the table up to the ball,
	## and taken hold of anywhere along it clear of the ring at its foot and the ball on its top.
	func stand(height: float) -> void:
		position = Vector3(0, 0, -height)
		if _cylinder == null:
			return
		var top := height - StageVoice.RADIUS * 0.5
		# Its foot a hair off the table, so it does not lie in the top's plane.
		_cylinder.height = top - ROD_CLEAR
		_rod.position = Vector3(0, (top + ROD_CLEAR) * 0.5, 0)
		var low := 0.009
		# Up to the knot under the ball, which is a handle of its own.
		var high := maxf(height - StageVoice.KNOT_DROP - StageVoice.KNOT_REACH, low + 0.004)
		_box.size = Vector3(0.016, high - low, 0.016)
		_shape.position = Vector3(0, (low + high) * 0.5, 0)

	func _up(at: Vector3) -> float:
		return voice.table.to_local(at).y - StageVoice.LIFT

	func _on_grab_begin(at: Vector3) -> void:
		_room = StageTable.room_track()
		if _room == 0:
			voice.table.told.emit(voice.table.no_room_words())
			return
		voice.table.forget_asked(voice.track)
		var now := voice.lift()
		_grip = now - _up(at)
		voice.hold_lift(now)

	func _on_grab_move(at: Vector3) -> void:
		if _room == 0 or _room == voice.track:
			return
		var lift := clampf(_up(at) + _grip, 0.0, StageVoice.STALK_MOST)
		voice.hold_lift(lift)
		voice.table.send_to_room(voice.track, StageTable.send_db_of_lift(lift))

	func _on_grab_end() -> void:
		voice.hold_lift(-1.0)

	func _on_nudge(notches: int, fine: bool) -> bool:
		var done := voice.table.nudge_room(voice.track, notches, fine)
		voice.refresh()
		return done

	func _default_title() -> String:
		return "%s  ROOM SEND" % voice.table.title_of(voice.track)

	func _default_readout() -> String:
		var db := StageTable.room_send_db(voice.track)
		if StageTable.room_track() == 0:
			return "no room yet"
		return "none: standing on the table" if db == -INF else "room %.1f dB" % db

	func hint() -> String:
		return voice.table.stalk_hint(voice.track)

	func dwell_activates() -> bool:
		return false


## The knot under a voice's ball (docs/spatial_loop.md slice 20): dragged from, a rope runs from it
## to the hand, and let go over another voice it is tied there (StageTable.tie), a sidechain from
## this track to that one: a key send and a compressor listening to it, one undo step. Its frame is
## the voice's (+Z the table's up), so a held ray moves in the level plane through it, as a ball's
## does. A press with no drag says how it is used.
class Knot extends ControlAffordance:
	var voice: StageVoice
	var _bead: MeshInstance3D
	var _dragged := false
	var _from := Vector2.ZERO

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var ball := SphereShape3D.new()
		ball.radius = StageVoice.KNOT_REACH
		shape.shape = ball
		add_child(shape)
		_bead = MeshInstance3D.new()
		_bead.name = "Bead"
		# A knot is a lump wider than it is tall, round the stalk: a squashed ring, so it reads as
		# tied on and not as another ball.
		var lump := TorusMesh.new()
		lump.inner_radius = StageVoice.KNOT_RADIUS * 0.35
		lump.outer_radius = StageVoice.KNOT_RADIUS
		lump.rings = 16
		lump.ring_segments = 8
		_bead.mesh = lump
		_bead.rotation = Vector3(PI * 0.5, 0, 0)
		_bead.scale = Vector3(1, 1.6, 1)
		_bead.material_override = StageTable.rope_paint()
		_bead.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_bead)
		set_meta(&"stage_track", voice.track)

	func _at(at: Vector3) -> Vector2:
		var p := voice.table.to_local(at)
		return Vector2(p.x, p.z)

	func _on_grab_begin(at: Vector3) -> void:
		_dragged = false
		_from = _at(at)

	func _on_grab_move(at: Vector3) -> void:
		var p := _at(at)
		if not _dragged and p.distance_to(_from) < StageVoice.DRAG_START:
			return
		_dragged = true
		voice.table.draw_loose(voice.track, p)

	func _on_grab_end() -> void:
		if _dragged:
			voice.table.let_go_rope(voice.track)
		else:
			voice.table.told.emit("%s: drag from its knot to another voice to tie a rope: that track ducks under this one."
					% voice.table.title_of(voice.track))
		_dragged = false

	func _default_title() -> String:
		return "%s  KNOT" % voice.table.title_of(voice.track)

	func _default_readout() -> String:
		return voice.table.ropes_words(voice.track)

	func hint() -> String:
		return voice.table.knot_hint(voice.track)

	func dwell_activates() -> bool:
		return false
