class_name PatchPlug
extends ControlAffordance

## One end of a patch cable, seated in a jack: the thing you take hold of to change a send that
## already exists.
##
## Pull it out and drop it on another row of the same column to move that end -- the TO end of a
## send to the drums bus taken across to the reverb is now a send to the reverb -- or drop it
## anywhere else to unplug it, which removes the send. Let go of it where it was and nothing
## happens: that is a plug you wiggled. Scrolling over it sets the send's level, because the
## cable is the send and there is nowhere else on a bay a level could live.
##
## The plug itself is drawn by the cable (PatchCable); this is the handle on it.

signal drag_began(from: ControlAffordance, at: Vector3)
signal drag_moved(from: ControlAffordance, at: Vector3, over: ControlAffordance)
signal drag_finished(from: ControlAffordance, over: ControlAffordance)

## Wide enough to catch at a glance, and short of the next jack along.
const RADIUS := 0.0125
## dB per wheel notch, and with the fine modifier.
const STEP_DB := 1.0
const FINE_DB := 0.1

var source: int = 0
## The send's place in the source's list of sends, from one, as on the wire.
var send_index: int = 1
var dest: int = 0
## Which end this is: PatchPoint.Kind.OUTPUT for the end in the FROM column.
var end: int = PatchPoint.Kind.OUTPUT
## The row this end is plugged into.
var row: PatchPoint


static func create(src: int, index: int, dst: int, which_end: int) -> PatchPlug:
	var p := PatchPlug.new()
	p.source = src
	p.send_index = index
	p.dest = dst
	p.end = which_end
	p.name = "Plug_%d_%d_%s" % [src, index, "out" if which_end == PatchPoint.Kind.OUTPUT else "in"]
	return p


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var ball := SphereShape3D.new()
	ball.radius = RADIUS
	shape.shape = ball
	# Out over the boot, which is the part of a plug that stands proud of the panel, so the ray
	# finds the plug before the row behind it.
	shape.position.z = 0.016
	add_child(shape)


func send() -> MixState.SendState:
	return DAW.state.send(source, send_index, false)


func _on_grab_begin(at: Vector3) -> void:
	drag_began.emit(self, at)


func _on_grab_move(at: Vector3) -> void:
	drag_moved.emit(self, at, _under_hand())


func _on_grab_end() -> void:
	drag_finished.emit(self, _under_hand())


func _under_hand() -> ControlAffordance:
	if held_by is Interactor:
		return (held_by as Interactor).hovered
	return null


func _on_nudge(notches: int, fine: bool) -> bool:
	var s := send()
	if s == null:
		return false
	# From the bottom of the table when it is off, or a send at -inf could never be turned up.
	var db := maxf(FaderLaw.to_db(s.volume), -61.0) + notches * (FINE_DB if fine else STEP_DB)
	DAW.set_send_volume(source, send_index, 0.0 if db < -60.0 else FaderLaw.to_taper(db))
	return true


func _foley_contact() -> AudioStream:
	return Foley.plug_seat()


func _default_title() -> String:
	return "%s  →  %s" % [_name_of(source), _name_of(dest)]


func _default_readout() -> String:
	var s := send()
	if s == null:
		return ""
	var db := FaderLaw.to_db(s.volume)
	return "-inf dB" if db < -60.0 else "%+.1f dB" % db


func hint() -> String:
	return "drag to another row to re-patch · pull it off to unplug · scroll for level"


static func _name_of(index: int) -> String:
	if not DAW.state.tracks.has(index):
		return "?"
	return DAW.state.track(index).display_name().to_upper()
