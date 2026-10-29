class_name ReelCrank
extends ControlAffordance

## The history, on the tape deck's supply reel (docs/spatial_loop.md part two, slice 28, idea #11):
## a crank on the reel's hub, turned to go back and forth through the history list.
##
## A NOTCH IS A STEP. Turned back (anticlockwise, winding the tape back onto the supply reel) a
## notch, NOTCH (30 degrees), is one step of history back; turned on, clockwise, one on. Each notch
## clicks (Foley.reel_click), and the crank stands at the step it has been turned to, its arm at
## that many notches round. Nothing is undone while it turns: once it has stood still for SETTLE,
## the history goes there in one jump (DAW.undo_to, as the history rail on the timeline does), not a
## step a frame, so twelve notches back is one undo_to, and turning back and on again to where it
## was is nothing at all. Turned past either end of the history, it stops there with a dull knock
## (Foley.reel_knock), and the hand's angle past the end is not kept: turned back, it comes off the
## end at once.
##
## IT PLAYS THE SONG AS IT WAS THERE. With the song stopped, each settled step plays PREVIEW_BARS
## bars from the playhead and stops, and the playhead goes back to where it was, so a turn back is
## heard as well as seen. A step settled while that is still playing starts it again from there.
## With the song playing, it just keeps playing.
##
## Turned by going round the reel's middle (a mouse, a fingertip) however many times round, or by a
## controller's twist; the wheel or the thumbstick is a step a notch. Its readout (`readout_text`,
## on the deck beside the reel) is `12 / 15 · 3 BASS: volume`: the step it stands at, of how many,
## and what that step was called (MixState.undo_names, where an edit group is its name), so the
## history is read in words, not by the arm's angle. Ctrl-Z is not changed by any of this.
##
## A guest's crank asks undo_to of the host, as everything a guest does to the mix asks, and then
## stands where it asked (ASK_WAIT at most) until the host's history comes back there. Where the
## DAW does not say how deep its history is (Reaper with no bridge: MixState.undo_depth -1), the
## crank cannot know where the ends are: a settle is that many undos or redos, one at a time, and
## its readout says only how far it has been turned.
##
## Hardware: it knows the DAW and nothing of the session; DAW routes a guest's ask.

## A step of history a notch, and a notch is this far round.
const NOTCH := PI / 6.0
## How long the crank stands still before the history goes to where it was turned.
const SETTLE := 0.25
## How much of the song a settled step plays, with the song stopped, from the playhead.
const PREVIEW_BARS := 2.0
## How long a guest's crank stands where it asked before giving way to the host's history.
const ASK_WAIT := 1.0
## The reel's radius, which the crank is turned over: anywhere on the reel's face.
const RADIUS := 0.085
## The arm, from the hub to the handle, and the handle standing out of the reel towards the hand.
const ARM := 0.058
const HANDLE_RADIUS := 0.0075
const HANDLE_LENGTH := 0.024
const CLICK_DB := -12.0
const KNOCK_DB := -6.0
## The most of a step's name the readout shows; longer ones end in an ellipsis.
const NAME_MOST := 24

## Whether a settled step with the song stopped plays PREVIEW_BARS of it. The probe's crank does
## not, so the host's transport is left as its later checks need it.
var plays_back := true

## What it has done, for the suite and the probe: notches clicked, knocks at an end, settles (each
## one undo_to, or a run of undos where the depth is unknown) and previews started.
var clicks := 0
var knocks := 0
var settles := 0
var previews := 0
var previewing := false

## The drawn crank, turned to the step it stands at.
var arm: Node3D

## Notches turned since the last settle, on from `_base`, the step it was turned from.
var _pending := 0
var _base := -1
var _since_notch := 0.0
## -1 or 1 while turned hard against the start or the end, so the knock is once a time it is met.
var _at_end := 0
var _grab_twist := NAN
var _grab_angle := 0.0
var _turned := 0.0
## The notches pending when the hand closed, so the hand's turn counts on from them.
var _grab_pending := 0
## A guest's ask, the step it asked for, until the host's history is there or ASK_WAIT is out.
var _asked := -1
var _asked_for := 0.0
var _preview_left := 0.0
var _preview_from := 0.0
var _preview_heard := false


func _init() -> void:
	collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = RADIUS + 0.004
	cylinder.height = 0.014
	shape.shape = cylinder
	# The cylinder's axis is its Y; the crank's is its Z, out of the reel towards the hand.
	shape.rotation.x = PI * 0.5
	add_child(shape)
	_build_arm()


## A bar from the hub to a handle standing out of the reel, on a boss over the hub. Turned whole
## about the reel's axis; it does not turn with the reel, which goes round with the song.
func _build_arm() -> void:
	arm = Node3D.new()
	arm.name = "Arm"
	add_child(arm)
	var metal := Materials.brushed_metal()
	var boss := MeshInstance3D.new()
	var boss_mesh := CylinderMesh.new()
	boss_mesh.top_radius = 0.011
	boss_mesh.bottom_radius = 0.012
	boss_mesh.height = 0.010
	boss_mesh.radial_segments = 20
	boss.mesh = boss_mesh
	boss.rotation.x = PI * 0.5
	boss.material_override = metal
	arm.add_child(boss)
	var bar := MeshInstance3D.new()
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(0.010, ARM, 0.004)
	bar.mesh = bar_mesh
	# Up from the hub at rest: the start of the history, the arm at twelve o'clock.
	bar.position = Vector3(0, ARM * 0.5, 0.004)
	bar.material_override = metal
	arm.add_child(bar)
	var handle := MeshInstance3D.new()
	handle.name = "Handle"
	var handle_mesh := CylinderMesh.new()
	handle_mesh.top_radius = HANDLE_RADIUS * 0.85
	handle_mesh.bottom_radius = HANDLE_RADIUS
	handle_mesh.height = HANDLE_LENGTH
	handle_mesh.radial_segments = 16
	handle.mesh = handle_mesh
	handle.rotation.x = PI * 0.5
	handle.position = Vector3(0, ARM, 0.006 + HANDLE_LENGTH * 0.5)
	handle.material_override = Materials.cap_plastic(Color(0.92, 0.72, 0.38))
	arm.add_child(handle)


## Whether the DAW says how deep its history is, so the crank knows its ends.
static func known() -> bool:
	return DAW.state != null and DAW.state.undo_depth >= 0


## How many steps of history there are, done and to redo.
static func total() -> int:
	if DAW.state == null:
		return 0
	return maxi(DAW.state.undo_depth, 0) + maxi(DAW.state.redo_depth, 0)


## The step the history is at: the DAW's, or a guest's own ask while it waits for the host.
func depth() -> int:
	if _asked >= 0:
		return _asked
	return maxi(DAW.state.undo_depth, 0) if DAW.state != null else 0


## The step the crank stands at: where it has been turned to, or where the history is.
func standing() -> int:
	if _base >= 0:
		return _base + _pending
	return depth()


## Notches turned and not yet settled, back negative: what a settle will do.
func pending() -> int:
	return _pending


## Turn the crank to `notches` on from where it was before this turn (`_base`), one click a notch
## passed, and stop at the history's ends with a knock. Returns where it stands now.
func turn_to(notches: int) -> int:
	if _base < 0:
		_base = depth()
		_since_notch = 0.0
	var want := notches
	var stopped := 0
	var lowest := -_base
	var highest := total() - _base
	if known():
		if want < lowest:
			want = lowest
			stopped = -1
		elif want > highest:
			want = highest
			stopped = 1
	if stopped != 0 and _at_end != stopped:
		knocks += 1
		Foley.play(self, Foley.reel_knock(), KNOCK_DB)
		_at_end = stopped
	elif stopped == 0 and ((_at_end > 0 and want < highest) or (_at_end < 0 and want > lowest)):
		# Off the end it was against, by a notch at least: meeting it again is another knock.
		_at_end = 0
	var passed := absi(want - _pending)
	if passed > 0:
		clicks += passed
		# One click for a turn's notches all in one frame: a flick of the wheel is heard as one
		# tick, not as a stack of them on top of each other. The count is every notch.
		Foley.play(self, Foley.reel_click(), CLICK_DB + minf(4.0, float(passed - 1)))
		_pending = want
		_since_notch = 0.0
	_show()
	return want


## A step a notch, on (positive) or back: the wheel's and the thumbstick's.
func step_by(notches: int) -> void:
	turn_to(_pending + notches)


func _process(delta: float) -> void:
	step(delta)


## A frame: the settle once the crank has stood still SETTLE, the preview's two bars, and a
## guest's ask given up when the host's history is there or ASK_WAIT has gone by. The two bars
## count from the frame after they start, and not while the transport counts in: the click
## before the song is not the song there.
func step(delta: float) -> void:
	var previews_were := previews
	if _base >= 0:
		_since_notch += delta
		if _since_notch >= SETTLE:
			_settle()
	if _asked >= 0:
		_asked_for += delta
		if DAW.state == null or DAW.state.undo_depth == _asked or _asked_for >= ASK_WAIT:
			_asked = -1
	if previewing:
		if previews == previews_were and not DAW.state.counting_in():
			_preview_left -= delta
		if DAW.state.playing:
			_preview_heard = true
		elif _preview_heard:
			# Stopped by somebody, not by the preview: theirs to say where the playhead stands.
			previewing = false
		if previewing and _preview_left <= 0.0:
			_end_preview()
	_show()


## The history goes to where the crank stands, in one jump; with the song stopped, two bars of it.
func _settle() -> void:
	var to := _base + _pending
	var notches := _pending
	_base = -1
	_pending = 0
	# A hand still pressing against an end has met it once: it knocks again when it comes off
	# and back, or is taken hold of afresh, not every SETTLE it stays there.
	if held_by == null:
		_at_end = 0
	else:
		# Still held: the turn so far is done, so the hand where it is now is no notches on. Else
		# its next move would be the whole turn since the grab again, from the settled step.
		_grab_pending = -roundi(_turned / NOTCH)
	if notches == 0:
		return
	settles += 1
	var playing := DAW.state.playing and not previewing
	if known():
		DAW.undo_to(to)
		_asked = to
		_asked_for = 0.0
	else:
		for _i in absi(notches):
			if notches < 0:
				DAW.undo()
			else:
				DAW.redo()
	if plays_back and not playing:
		_preview()


## Play PREVIEW_BARS from the playhead, or from where the last preview started if one is playing.
func _preview() -> void:
	var s := DAW.state
	if previewing:
		DAW.seek(_preview_from)
	else:
		_preview_from = s.position_seconds
	var bar := s.bar_at(_preview_from)
	_preview_left = maxf(s.bar_to_seconds(bar + PREVIEW_BARS + 1.0) - _preview_from, 0.1)
	previews += 1
	_preview_heard = previewing and s.playing
	previewing = true
	if not s.playing:
		DAW.transport_play()


func _end_preview() -> void:
	previewing = false
	DAW.transport_stop()
	DAW.seek(_preview_from)


## What the deck's readout says: the step it stands at, of how many, and that step's name.
func readout_text() -> String:
	if DAW.state == null:
		return ""
	if not known():
		if _pending == 0:
			return "HISTORY · IN THE DAW'S OWN LIST"
		return "HISTORY · %d %s" % [absi(_pending), "BACK" if _pending < 0 else "ON"]
	var n := standing()
	var all := total()
	if all == 0:
		return "0 / 0 · NOTHING DONE YET"
	return "%d / %d · %s" % [n, all, step_name(DAW.state.undo_names, n)]


## What history step `n` is called (the step done last, standing there): "the start" for 0.
static func step_name(names: Array, n: int) -> String:
	if n <= 0:
		return "the start"
	var said := str(names[n - 1]) if n <= names.size() else "step %d" % n
	return said if said.length() <= NAME_MOST else said.left(NAME_MOST - 1) + "…"


func _show() -> void:
	if arm != null:
		# Clockwise, as the person at the deck sees it, is on.
		arm.rotation.z = -float(standing() if known() else _pending) * NOTCH


func network_key() -> String:
	return "TRANSPORT  HISTORY REEL"


func _default_title() -> String:
	return "EDIT  HISTORY REEL"


func _default_readout() -> String:
	var said := readout_text()
	if previewing:
		said += " · playing %d bars there" % int(PREVIEW_BARS)
	elif _base >= 0:
		said += " · settles when it stands still"
	return said


func hint() -> String:
	return "drag round the reel: back a notch (30°) is a step undone, on a notch a step redone · it goes there when you stop · stopped, it plays two bars there · wheel: a step · Ctrl-Z still undoes"


func _on_grab_begin(at: Vector3) -> void:
	_turned = 0.0
	_at_end = 0
	_grab_pending = _pending
	_grab_twist = NAN
	_grab_angle = _angle_at(at)
	if held_by is Interactor and not (held_by as Interactor).touches_directly():
		_grab_twist = (held_by as Interactor).twist()


## Turned by turning the hand, or by going round the middle, however many times round.
func _on_grab_move(at: Vector3) -> void:
	if not is_nan(_grab_twist):
		_turned = (held_by as Interactor).twist() - _grab_twist
	else:
		var angle := _angle_at(at)
		_turned += wrapf(angle - _grab_angle, -PI, PI)
		_grab_angle = angle
	var want := _grab_pending + roundi(_turned / NOTCH)
	var got := turn_to(want)
	if got != want:
		# Against an end: the hand's turn past it is not kept, so a turn back comes off it at once.
		_grab_pending = got - roundi(_turned / NOTCH)


## Where `at` is round the middle, clockwise from twelve o'clock, as the person at the deck sees it.
func _angle_at(at: Vector3) -> float:
	var p := to_local(at)
	return atan2(p.x, p.y)


func _on_nudge(notches: int, _fine: bool) -> bool:
	if notches == 0:
		return false
	step_by(notches)
	return true
