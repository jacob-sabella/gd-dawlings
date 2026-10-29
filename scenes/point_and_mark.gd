class_name PointAndMark
extends Node

## Point, mark and listen together (docs/spatial_loop.md part two, slice 35; the proving idea #7).
##
## POINTING. Z held at a desk points the mouse's hand (Interactor.pointing); in a headset a bare
## hand points by holding its index level with the other fingers curled (HandPose.pointing), and a
## controller by the non-chord hand's stick click, held (XRInteractor.points_by_stick). Presence
## then publishes what the ray meets as a song time (`ruler:<seconds>`, through `time_at`), a
## bandmate, a control or a place in the room, and every bandmate's copy of my ghost draws a ray to
## it with my name at its end. Presence is the one path: pointing is a way of filling it in.
##
## MARKS. A sticky note is a marker named `NOTE ...` (Harmony.NOTE_PREFIX), so it undoes,
## replicates, saves and is edited on the 2D ruler like any marker, and a guest's is an add_marker
## intent. O at a desk over the timeline's ruler or lanes, or the miniature, drops one at the song
## time under the cursor (anywhere else, at the playhead) and asks its words; in a headset a note
## is taken off the desk's note pad (NotePad) and stuck on the ruler, a lane or the miniature.
## Every section reader skips notes, and the 3D ruler draws each as a card over its time.
##
## LISTEN FROM MY SPOT. A note card's LISTEN key, or Enter with Z held over the ruler (a pinch of
## the pointing hand's thumb and middle in a headset; a controller's grip, its middle finger, while
## its stick click points), plays the shared song from there for everyone, and the room is told
## (Session.listen_from). Enter rather than Space, which the walker polls as a jump.

## The studio this works in: its timeline, its miniature, its hands.
var studio: Node3D
## The mouse's hand at a desk; null in a headset.
var mouse: MouseInteractor
## The headset's hands; empty at a desk.
var hands: Array[XRInteractor] = []
## Said the first time Z is held, so the keys that go with it are found.
var _told := false
## {hand: whether its thumb was on its middle finger last frame}, for a pinch's edge.
var _pinched := {}
## {hand: whether it pointed last frame}: a pinch counts only on a hand already pointing, so one
## whose thumb was on its middle before its index went out does not listen as it starts to point.
var _pointed := {}
## What asked the words of the note last dropped, until it is answered or left (for the suite).
var asking: Node = null


## The song time `control` means at `point` (global), or NAN for none: the timeline's ruler and
## lanes (TimelineSurface.is_time_control), a note's card on the ruler (its note's time,
## TimelineSurface.note_time), and the miniature's bed (a strip's or the ruler's time, not a
## track's name). What Presence publishes a point as `ruler:<seconds>` by.
func time_at(control: Object, point: Vector3) -> float:
	if control == null or not is_instance_valid(control):
		return NAN
	var timeline: TimelineSurface = studio.get("timeline")
	if timeline != null and is_instance_valid(timeline):
		if timeline.is_time_control(control):
			return maxf(timeline.seconds_at_point(point), 0.0)
		var noted := timeline.note_time(control)
		if not is_nan(noted):
			return noted
	var face := control as MiniatureItem.Face
	if face != null and face.mini != null:
		var seconds := float(face.mini.spot_at(face.mini.content_local(point))["seconds"])
		return seconds if seconds >= 0.0 else NAN
	return NAN


## The song time `hand` is on (`time_at` of what it holds or hovers), or NAN.
func time_under(hand: Interactor) -> float:
	if hand == null or not is_instance_valid(hand):
		return NAN
	var control: ControlAffordance = hand.held if hand.held != null else hand.hovered
	return time_at(control, hand.hover_point)


## Plays the song from `seconds` for everyone, and tells the room so.
func listen_from(seconds: float) -> void:
	Session.listen_from(seconds)


## Listen from where `hand` points, if that is a song time: true when it was.
func listen_pointed(hand: Interactor) -> bool:
	var seconds := time_under(hand)
	if is_nan(seconds):
		return false
	listen_from(seconds)
	return true


## A note at `seconds`: its words asked for -- on the monitor at a desk, on a typing pad over the
## note pad in a headset -- and on an answer with any, a NOTE marker there (`add_note`). The asker.
func drop_note(seconds: float) -> Node:
	var at := maxf(seconds, 0.0)
	var title := "Note at %s (%s)" % [DAW.state.bar_beat(at), Presence.clock(at)]
	if is_instance_valid(asking) and asking is TypingPad:
		asking.queue_free()
	var pad: Node3D = studio.get("note_pad")
	if mouse == null or studio.get_viewport().use_xr:
		var parent: Node3D = pad if pad != null and is_instance_valid(pad) else studio
		# Over the pad and toward whoever is at the desk, tipped up to face them, as the deck's is.
		asking = TypingPad.ask(parent, title, "", Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0, 0.16, 0.06)))
	else:
		asking = NamePrompt.ask(studio, title, "")
	asking.answered.connect(func(text: String): add_note(at, text))
	return asking


## A sticky note saying `text` at `seconds`, as one marker (Harmony.note_named), a millisecond and a
## half after any marker already there (Harmony.note_spot) so it renames none. Nothing for no words.
## On a guest, the add_marker intent. True when it was made.
static func add_note(seconds: float, text: String) -> bool:
	if text.strip_edges().is_empty() or not DAW.can(DAWBackend.Capability.MARKERS):
		return false
	DAW.add_marker(Harmony.note_spot(DAW.state.markers, seconds), Harmony.note_named(text))
	return true


## A note taken off the pad by `by` and let go on `control` at `point`: dropped at the time there,
## or, on something that is not a time, said where it goes.
func on_pad_stuck(_by: Node, control: ControlAffordance, point: Vector3) -> void:
	var seconds := time_at(control, point)
	if is_nan(seconds):
		Session.notice.emit("A note sticks on the timeline's ruler or a lane, or on the miniature.")
		return
	drop_note(seconds)


## Z held points, Enter with it listens from there, O drops a note. Not with Ctrl or Meta, which
## make Z undo; a focused catcher (the keytar's piano) takes its own keys before these are heard.
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or key.echo or mouse == null or key.ctrl_pressed or key.meta_pressed:
		return
	match key.keycode:
		KEY_Z:
			set_pointing(key.pressed)
		KEY_ENTER, KEY_KP_ENTER:
			if key.pressed and mouse.pointing:
				if not listen_pointed(mouse):
					Session.notice.emit("Point at the timeline's ruler, a lane or a note, or the miniature, to listen from there.")
				get_viewport().set_input_as_handled()
		KEY_O:
			if key.pressed:
				var seconds := time_under(mouse)
				drop_note(seconds if not is_nan(seconds) else DAW.state.position_seconds)
				get_viewport().set_input_as_handled()


## The mouse's hand pointing, or not: Z down and up. Said once, the first time.
func set_pointing(on: bool) -> void:
	if mouse == null:
		return
	mouse.pointing = on
	if on and not _told:
		_told = true
		Session.notice.emit("Pointing: bandmates see your ray, your name at its end. Enter listens from the ruler's time under it; O drops a note there.")


func _notification(what: int) -> void:
	# A window let go with Z down never hears it come up.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and mouse != null and is_instance_valid(mouse):
		mouse.pointing = false


func _physics_process(_delta: float) -> void:
	for hand in hands:
		if not is_instance_valid(hand):
			continue
		var pinch := hand.pointing and hand.finger_pinches() & HandPose.MIDDLE != 0
		if pinch and not _pinched.get(hand, false) and _pointed.get(hand, false):
			listen_pointed(hand)
		_pinched[hand] = pinch
		_pointed[hand] = hand.pointing
