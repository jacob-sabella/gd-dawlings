class_name WriteBead
extends ControlAffordance

## Automation by gesture (docs/spatial_loop.md part two, slice 22; docs/spatial_ideas.md #2): a
## small bead on a thread over the control a hand or a cursor is on, while the song plays. Pulled
## out -- a pinch or a grab in a headset, a drag at a desk -- it is the control: its height over
## RANGE_METRES is the control's whole range, finer than the control itself, and the control
## follows it. Meanwhile it writes that control's lane.
##
## One per hand (Interactor.bead), shown over whatever automatable control that hand is on (its
## `automation_target`), and kept while the hand goes from the control up to it (LINGER_SECONDS).
## Itself a ControlAffordance, so a mouse, a controller and a pinching hand all reach it through
## the same grab contract, and its hover card says what it does. A drag of the control itself is
## the ordinary drag it always was: the bead is somewhere else.
##
## WHILE IT IS OUT
##   - `DAW.hold_lane(track, target, true)` stops that lane following the song, so the player
##     hears the control they move rather than the lane under it, and lets it go at the let-go.
##     Not a touch pass: no automation mode is changed, and nothing times the hold out.
##   - the control's writes are its ordinary sets, inside an edit (`_open_edit`), so the control
##     goes back with the pass when it is undone.
##   - the bead keeps its own points, each at the song position this player HEARD when it was
##     made (`heard`, as everything played is stamped), a point every POINT_SECONDS even with the
##     hand still, so a guest's pass is in time with what the guest heard.
##
## A PASS is one stretch of those points. Looping, the pass records only inside the loop: it
## punches in where the playhead enters the loop (or wherever in it the bead was pulled), and at a
## wrap, or on leaving the loop, it ends. Not looping, it records from where it began and ends at
## the let-go. A pass's end writes its points over its span (`merged`) as the whole lane, with one
## DAW.set_automation, inside its edit, and closes the edit: one undo step that restores the lane
## and the control. Held on through a wrap, the next pass and its edit begin at the loop's start.

## How far the hand moves for the control's whole range, bottom to top.
const RANGE_METRES := 0.5
## How much finer the fine modifier (Shift) makes it.
const FINE := 0.1
## A point at least this often (song seconds), still or not.
const POINT_SECONDS := 0.05
## How long the bead stays once the hand has left its control, so the hand can reach it.
const LINGER_SECONDS := 0.8
## A heard position this far back is a wrap or a seek, and this far past the loop's end, the
## song has left the loop.
const WRAP_BACK := 0.1
const PAST_LOOP := 0.15
## Where the lane either side of a pass is pinned to what it was, this far outside the pass.
const EDGE := 0.001
## How often a still bead writes its value again, so its edit is never idle long enough to close
## (DAWBackend.EDIT_IDLE_MSEC) under a long held note.
const KEEP_ALIVE_MSEC := 1000
const RADIUS := 0.009
## Generous: a bead is a small thing to land a cursor on.
const HIT_RADIUS := 0.016
const THREAD_RADIUS := 0.0007
## Warm white, one hue: held it is bigger and brighter, and writing it wears a ring (no signal by
## colour alone).
const INK := Color(1.0, 0.86, 0.62)

## The bead out on this machine, if one is: one pass at a time per player, as one edit is.
static var _writing: WriteBead = null
## Every bead, so two hands on one control (a ray and a fingertip) show one bead between them.
static var _all: Array[WriteBead] = []
## (track: int, target: String) -> void: told when a bead is pulled out, with the lane it writes.
## The studio shows that lane on the 3D timeline, so each pass is seen to land there.
static var on_pull: Callable = Callable()

## The hand this bead belongs to.
var hand: Interactor = null
## The control it is over, or null.
var control: ControlAffordance = null
## () -> Dictionary: what is heard instead of this player's ears ({seconds, playing, valid}), for
## the suite and the probe. Unset: GuestMidi.heard, as every take is stamped.
var heard_source: Callable = Callable()
## How many passes this bead has written, for whoever is checking.
var passes_written := 0

## While out: the lane, the value (this control's own terms), and where the hand began.
var _lane: Array = []
var _value := 0.0
var _from_value := 0.0
var _from_height := 0.0
var _fine_was := false
var _held_at := Vector3.ZERO
## The lane's value before the bead came out, for a lane that had none (lane units).
var _before := 0.0
## The pass under way: {start, looped, points}; empty between passes.
var _pass: Dictionary = {}
var _last_heard := NAN
var _letting_go := false
var _last_write_msec := 0
var _linger := 0.0

var _body: MeshInstance3D
var _ring: MeshInstance3D
var _thread: MeshInstance3D
var _ink: StandardMaterial3D


func _init() -> void:
	name = "WriteBead"
	top_level = true
	describe_edit = func() -> String: return _edit_words()


func _enter_tree() -> void:
	super()
	if not self in _all:
		_all.append(self)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	_ink = StandardMaterial3D.new()
	_ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ink.albedo_color = INK
	_body = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	_body.mesh = sphere
	_body.material_override = _ink
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_body)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = RADIUS * 1.55
	torus.outer_radius = RADIUS * 1.85
	_ring.mesh = torus
	_ring.material_override = _ink
	# Round the bead as it faces the viewer: the torus lies in its XZ plane.
	_ring.rotation = Vector3(PI * 0.5, 0, 0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)
	_thread = MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = THREAD_RADIUS
	cylinder.bottom_radius = THREAD_RADIUS
	cylinder.height = 1.0
	cylinder.radial_segments = 6
	cylinder.rings = 1
	_thread.mesh = cylinder
	_thread.material_override = _ink
	_thread.top_level = true
	_thread.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_thread)
	var shape := CollisionShape3D.new()
	var ball := SphereShape3D.new()
	ball.radius = HIT_RADIUS
	shape.shape = ball
	add_child(shape)
	_show(false)


func _exit_tree() -> void:
	if is_held():
		_release()
	_all.erase(self)
	super()


# --- being there -----------------------------------------------------------------------------

## One physics tick of the hand: shown over `over` if it is a control a bead can write and the song
## is playing, kept while the hand goes to it, and placed. Called by the hand (Interactor).
func tend(over: ControlAffordance, delta: float) -> void:
	if is_held():
		_place()
		return
	var target: ControlAffordance = null
	if over == self:
		target = control
	elif offers(over):
		target = over
	if target != null and target != control:
		control = target
	if target != null:
		_linger = LINGER_SECONDS
	else:
		_linger -= delta
	var shown := _linger > 0.0 and control != null and is_instance_valid(control) and offers(control) \
			and DAW.state != null and DAW.state.playing
	if not shown and _linger <= 0.0:
		control = null
	_show(shown)
	if shown:
		_place()


## Whether a bead may stand over `c`: a control with a lane to write, nobody's hand on it, and no
## other bead of this machine's over it already.
func offers(c: ControlAffordance) -> bool:
	if c == null or not is_instance_valid(c) or c is WriteBead or not c.is_inside_tree() \
			or not c.is_visible_in_tree() or c.collision_layer == 0:
		return false
	if c.is_held() or c.claimed_by != null or c.automation_target().is_empty():
		return false
	for other in _all:
		if other != self and is_instance_valid(other) and other.control == c and other.visible:
			return false
	return true


## Whether it is drawn and can be reached now.
func shown() -> bool:
	return visible and collision_layer != 0


func _show(on: bool) -> void:
	visible = on
	collision_layer = (1 << (Interactor.CONTROL_LAYER - 1)) if on else 0


## Over its control, facing whoever is looking (so a cursor's drag is in the plane of the screen);
## held, where the hand has it. Its thread hangs from the control's foot.
func _place() -> void:
	if control == null or not is_instance_valid(control):
		return
	var at := control.global_transform * control.bead_anchor()
	if is_held():
		at = _held_at
	var eye := hand.aim().origin if hand != null and is_instance_valid(hand) else at + Vector3.BACK
	if not is_held():
		var facing := at - eye
		if facing.length() > 0.001:
			global_transform = Transform3D(Basis.looking_at(facing.normalized(),
					Vector3.UP if absf(facing.normalized().y) < 0.98 else Vector3.BACK), at)
		else:
			global_position = at
	else:
		global_position = at
	var writing := is_held() and not _pass.is_empty()
	_body.scale = Vector3.ONE * (1.35 if is_held() else 1.0)
	_ring.visible = writing
	_ink.albedo_color = INK * (1.25 if is_held() else 0.85)
	var foot := control.global_transform * control.bead_foot()
	var span := at - foot
	_thread.visible = span.length() > 0.002
	if _thread.visible:
		var up := span.normalized()
		var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
		_thread.global_transform = Transform3D(Basis(side, up * span.length(), side.cross(up)), foot + span * 0.5)


# --- what it says ----------------------------------------------------------------------------

func title() -> String:
	if control == null or not is_instance_valid(control):
		return "AUTOMATION"
	return "%s  AUTOMATION" % control.title()


func readout() -> String:
	if control == null or not is_instance_valid(control):
		return ""
	var reading := control.readout()
	if not is_held():
		return reading
	if not _pass.is_empty():
		return "%s  ·  writing" % reading
	return "%s  ·  waiting for the %s" % [reading, "loop" if DAW.state.looping else "song"]


func hint() -> String:
	var said := "drag the bead up or down to write automation  ·  shift for fine"
	if not DAW.can(DAWBackend.Capability.LANE_HOLD):
		said += "  ·  the lane plays over you while writing"
	return said


## The same key as its control's: holding the bead holds the control, for everyone.
func network_key() -> String:
	if control != null and is_instance_valid(control):
		return control.network_key()
	return title()


func card_hint() -> String:
	return hint()


## "Kick: level automation", the step each pass is in the history list.
func _edit_words() -> String:
	if _lane.is_empty():
		return ""
	var track: int = _lane[0]
	var who := "Master" if track == 0 else DAW.state.track(track).display_name()
	var words: String = {"volume": "level", "pan": "pan", "mute": "mute", "send": "send",
			"fx": "plugin", "enable": "plugin power"}.get(DawKitAutomation.kind_of(_lane[1]), "lane")
	return "%s: %s automation" % [who, words]


# --- out ---------------------------------------------------------------------------------------

func grab_begin(by: Node, at: Vector3) -> void:
	if control == null or not is_instance_valid(control) or control.is_held() or control.claimed_by != null:
		return
	if _writing != null and _writing != self and is_instance_valid(_writing) and _writing.is_held():
		return
	if control.automation_target().is_empty():
		return
	super(by, at)


func _on_grab_begin(at: Vector3) -> void:
	_writing = self
	_lane = control.automation_target()
	control.bead = self
	_value = now_of(_lane[0], _lane[1])
	_before = lane_value(_lane[1], _value)
	_from_value = _value
	_held_at = at
	_from_height = _height(at)
	_fine_was = _is_fine()
	_pass = {}
	_last_heard = NAN
	_letting_go = false
	_last_write_msec = Time.get_ticks_msec()
	DAW.hold_lane(_lane[0], _lane[1], true)
	if on_pull.is_valid():
		on_pull.call(_lane[0], _lane[1])
	# One undo step from here to the end of the first pass: what the bead does before the
	# playhead reaches the loop is part of it.
	_open_edit()
	follow(heard())


func _on_grab_move(at: Vector3) -> void:
	_held_at = at
	var h := _height(at)
	var fine := _is_fine()
	if fine != _fine_was:
		# From here, at the new rate: a change of rate is not a jump.
		_fine_was = fine
		_from_value = _value
		_from_height = h
	var v := clampf(_from_value + (h - _from_height) / RANGE_METRES * (FINE if fine else 1.0), 0.0, 1.0)
	if absf(v - _value) > 0.00001:
		_write(v)


func _on_grab_end() -> void:
	_letting_go = true
	follow(heard())
	if not _pass.is_empty():
		_end_pass(_last_heard if not is_nan(_last_heard) else float(_pass["start"]))
	_release()


## The lane followed again and the control the mix's, as at a let-go.
func _release() -> void:
	if not _lane.is_empty():
		DAW.hold_lane(_lane[0], _lane[1], false)
	if control != null and is_instance_valid(control) and control.bead == self:
		control.bead = null
		control._hold_against_echoes()
	if _writing == self:
		_writing = null
	_pass = {}
	_lane = []


func _physics_process(_delta: float) -> void:
	if is_held():
		follow(heard())


## Where the hand is, up and down: a hand's own height in a headset (the bead is in it), the
## drag's point at a desk, in the plane of the screen through the bead.
func _height(at: Vector3) -> float:
	var by := held_by as Interactor
	if by != null and not by.draws_own_hand():
		_held_at = by.catch_point()
		return _held_at.y
	return at.y


func _is_fine() -> bool:
	var by := held_by as Interactor
	return by != null and by.fine()


func _write(v: float, again := false) -> void:
	_value = v
	_last_write_msec = Time.get_ticks_msec()
	if control != null and is_instance_valid(control):
		control.write_from_bead(v, again)


## The song position this player hears now: {seconds, playing, valid}. On a guest the mix stream's
## stamp, as GuestMidi stamps every note; on the host its own playhead as heard.
func heard() -> Dictionary:
	if heard_source.is_valid():
		return heard_source.call()
	if Session.guest_midi != null:
		return Session.guest_midi.heard()
	return Session.host_heard()


## One moment of the song as heard, while out: a pass begun, ended or sampled.
func follow(h: Dictionary) -> void:
	if not is_held() or _lane.is_empty() or DAW.state == null:
		return
	var st := DAW.state
	var s := float(h.get("seconds", 0.0))
	var rolling := bool(h.get("valid", true)) and bool(h.get("playing", false))
	var looping := st.looping and st.loop_end - st.loop_start > POINT_SECONDS * 2.0
	var was := _last_heard
	var back := rolling and not is_nan(was) and s < was - WRAP_BACK
	if not _pass.is_empty():
		var looped: bool = _pass["looped"]
		if not rolling:
			_end_pass(was if not is_nan(was) else float(_pass["start"]))
		elif back:
			# A wrap: to the loop's end. Not looping, a seek back: to where it was.
			_end_pass(st.loop_end if looped and looping else was)
		elif looped != looping or (looped and (s >= st.loop_end + PAST_LOOP or s < st.loop_start - PAST_LOOP)):
			# Out of the loop, or the loop switched on or off under it.
			_end_pass(minf(was, st.loop_end) if looped and not is_nan(was) else (was if not is_nan(was) else s))
	if _pass.is_empty() and rolling and not _letting_go \
			and (not looping or (s >= st.loop_start - 0.0005 and s < st.loop_end)):
		var start := s
		if looping and not is_nan(was) and (back or was < st.loop_start):
			# In at the loop's start: wrapped to it, or come into it from before.
			start = st.loop_start
		start = maxf(start, 0.0)
		_pass = {"start": start, "looped": looping,
				"points": [[start, lane_value(_lane[1], _value), shape_of(_lane[1])]]}
	if not _pass.is_empty():
		_sample(s)
	_last_heard = s if rolling else NAN
	if _edit_open and Time.get_ticks_msec() - _last_write_msec > KEEP_ALIVE_MSEC:
		_write(_value, true)


## A point, if POINT_SECONDS have gone by since the last one: inside the loop, while looping.
func _sample(s: float) -> void:
	var st := DAW.state
	var points: Array = _pass["points"]
	var at := maxf(s, float(_pass["start"]))
	if _pass["looped"]:
		at = clampf(at, st.loop_start, st.loop_end)
	if points.is_empty() or at >= float(points[-1][0]) + POINT_SECONDS - 0.0001:
		points.append([at, lane_value(_lane[1], _value), shape_of(_lane[1])])


## The pass to `end`, written over its span as the whole lane, in its edit, which closes; held on,
## the next one's edit opens. A pass too short to have a stretch (a let-go at the instant of a
## wrap) writes nothing.
func _end_pass(end: float) -> void:
	var run := _pass
	_pass = {}
	var points: Array = run["points"]
	var start: float = run["start"]
	if run["looped"]:
		end = minf(end, DAW.state.loop_end)
	if not points.is_empty() and end - start >= POINT_SECONDS - 0.0001:
		if end > float(points[-1][0]) + 0.0005:
			points.append([end, lane_value(_lane[1], _value), shape_of(_lane[1])])
		var lane := merged(lane_now(_lane[0], _lane[1]), points, start, end, _before, _lane[1])
		DAW.set_automation(_lane[0], _lane[1], lane)
		passes_written += 1
	_close_edit()
	if not _letting_go and is_held():
		_open_edit()


# --- the lane ----------------------------------------------------------------------------------

## The lane as this machine has it now: [[seconds, value, shape], ...].
static func lane_now(track: int, target: String) -> Array:
	var st := DAW.state
	if track == 0:
		return (st.master.automation.get(target, []) as Array).duplicate(true)
	if not st.tracks.has(track):
		return []
	return (st.track(track).automation.get(target, []) as Array).duplicate(true)


## `recorded` over `start`..`end` of `old`, as one lane: what was outside the span kept, pinned at
## EDGE either side to what the lane was there (`before` where it had nothing), so neither side of
## the pass moves. Thinned, every other recorded point, until it fits the wire.
static func merged(old: Array, recorded: Array, start: float, end: float, before: float, target: String) -> Array:
	var shape := shape_of(target)
	var kept := recorded
	var lane: Array = []
	# Each round halves what was recorded: a dozen is more than any song's worth of points.
	for _round in 12:
		var out: Array = []
		for pt in old:
			if float(pt[0]) < start - EDGE * 0.5 or float(pt[0]) > end + EDGE * 0.5:
				out.append([float(pt[0]), float(pt[1]), int(pt[2])])
		if start > EDGE:
			out.append([start - EDGE, DawKitAutomation.value_in(old, start - EDGE, before), shape])
		for pt in kept:
			if float(pt[0]) >= start - 0.000001 and float(pt[0]) <= end + 0.000001:
				out.append([float(pt[0]), DawKitAutomation.clamp_value(target, float(pt[1])), int(pt[2])])
		out.append([end + EDGE, DawKitAutomation.value_in(old, end + EDGE, before), shape])
		out.sort_custom(func(a, b): return a[0] < b[0])
		lane = []
		for pt in out:
			if lane.is_empty() or float(pt[0]) > float(lane[-1][0]) + 0.000001:
				lane.append(pt)
			else:
				lane[-1] = pt
		if lane.size() <= MixWire.AUTOMATION_POINTS_MAX or kept.size() < 3:
			break
		var thinner: Array = []
		for i in kept.size():
			if i % 2 == 0 or i == kept.size() - 1:
				thinner.append(kept[i])
		kept = thinner
	return lane


## A switch holds from point to point; everything else goes there in a straight line.
static func shape_of(target: String) -> int:
	return DawKitAutomation.HOLD if DawKitAutomation.kind_of(target) in ["mute", "enable"] else DawKitAutomation.LINEAR


## A control's 0..1 in its lane's units: decibels for a level or a send, -1..1 for a pan, 0 or 1
## for a switch, a plugin's parameter as it is.
static func lane_value(target: String, v: float) -> float:
	match DawKitAutomation.kind_of(target):
		"volume", "send":
			return maxf(DAW.taper_to_db(clampf(v, 0.0, 1.0)), -150.0)
		"pan":
			return clampf(v, 0.0, 1.0) * 2.0 - 1.0
		"mute", "enable":
			return 1.0 if v >= 0.5 else 0.0
	return clampf(v, 0.0, 1.0)


## Where `target` of `track` is now, in the control's 0..1, from the mix.
static func now_of(track: int, target: String) -> float:
	var st := DAW.state
	if track == 0:
		return st.master.volume if target == "volume" else st.master.pan
	if not st.tracks.has(track):
		return 0.0
	var t := st.track(track)
	match DawKitAutomation.kind_of(target):
		"volume":
			return t.volume
		"pan":
			return t.pan
		"mute":
			return 1.0 if t.mute else 0.0
		"send":
			var to := int(target.substr(5))
			for slot in t.sends:
				var sd: MixState.SendState = t.sends[slot]
				if not sd.key and sd.resolve(st) == to:
					return sd.volume
		"enable":
			var fe := st.fx(track, int(target.substr(7)), false)
			return 1.0 if fe != null and fe.enabled else 0.0
		"fx":
			var parts := target.split(":")
			var f := st.fx(track, int(parts[1]), false)
			return float(f.params.get(int(parts[2]), 0.0)) if f != null else 0.0
	return 0.0
