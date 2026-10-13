class_name Fader
extends ControlAffordance

## A 100mm channel fader.
##
## The affordance covers the WHOLE TRAVEL, not just the cap, and that is deliberate on both
## input paths. With a mouse it gives you click-in-the-trough-to-jump, which is how every desk
## and every DAW already behaves. With a hand it means the grab does not lapse the instant the
## cap slides out from under your fingertip, which at 100mm of throw is immediately.
##
## Travel is along local +Y. The panel normal is local +Z, which is the plane the Interactor
## projects a wandering ray onto -- so a fader laid onto a tilted console works without the
## interactor knowing anything about consoles.

const TRAVEL := 0.10
const WIDTH := 0.014
const CAP_HEIGHT := 0.022
const MESH_PATH := "res://assets/hardware/fader_cap.glb"

## Reaper's normalised taper value. Kept separate from `value` only in name: they are the same
## number, and that is the point -- no conversion happens on the way to the DAW.
var track_index: int = 0
## Where a new position goes. Defaults to the track named by `track_index`; the master section
## points it at the master bus. One fader class, because the FEEL of a fader -- 100mm of travel,
## grab-the-trough-to-jump, a cap that keeps its offset under the finger -- is the whole of what
## a fader is, and none of it depends on which number it writes.
var write_value: Callable = Callable()

## The recessed slot the cap travels in, if whoever built this fader has somewhere to put it.
## One per strip, identical on every strip, and never recoloured -- which is the easiest kind of
## thing to bank. See hardware/mesh_bank.gd.
var slot_bank: MeshBank
## And where the moulded CAP gets drawn. Same argument as the slot, with the one difference
## that a cap moves -- so this one is kept and rewritten on every value change rather than
## claimed once and forgotten. See MeshBank.move_slot.
var cap_bank: MeshBank

## Slot geometry, out here because the bank has to size its box before any fader exists.
const SLOT_SIZE := Vector3(WIDTH * 0.45, TRAVEL + 0.012, 0.004)
const SLOT_OFFSET := Vector3(0, TRAVEL * 0.5, 0.002)

var _cap: Node3D
var _cap_slot := -1
var _grab_offset := 0.0
var _slide: AudioStreamPlayer3D
## Travel per second, smoothed. The slide is the only sound here that is CONTINUOUS, so unlike a
## click it needs a current loudness rather than a moment to fire at.
var _speed := 0.0
var _last_value := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0

	if slot_bank != null:
		var at := Node3D.new()
		add_child(at)
		at.position = SLOT_OFFSET
		slot_bank.place(at, Color.WHITE)
		at.queue_free()
	else:
		var slot := MeshInstance3D.new()
		var slot_mesh := BoxMesh.new()
		slot_mesh.size = SLOT_SIZE
		slot.mesh = slot_mesh
		slot.material_override = Materials.recess()
		slot.position = SLOT_OFFSET
		add_child(slot)

	# The moulded cap: scooped waist, a lip at each end, the pointer line down in the scoop
	# where a finger bridges over it (tools/blender/fader_cap.py). Modelled in the orientation
	# it is used in, so unlike the knob it needs no correcting rotation.
	# Banked, the cap is an empty node that the bank slot shadows. It still has to BE a node:
	# the slide emitter parents to it so the sound comes from where the cap is, and a bank slot
	# is a row in a buffer with nowhere to hang a speaker.
	if cap_bank != null:
		_cap = Node3D.new()
		add_child(_cap)
		_cap_slot = cap_bank.place(_cap, Color.WHITE)
	else:
		_cap = Part.build(
			MESH_PATH,
			Materials.fader_cap(),
			{"indicator": Materials.legend()},
		)
		if _cap == null:
			_cap = _stand_in()
		add_child(_cap)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH * 2.2, TRAVEL + CAP_HEIGHT, 0.02)
	shape.shape = box
	shape.position = Vector3(0, TRAVEL * 0.5, 0.008)
	add_child(shape)

	_on_value_changed()
	# Off until a hand arrives; see _process.
	set_process(false)


## The pre-Blender cap, kept as the fallback so a missing asset is a plainer desk rather than a
## desk whose faders you cannot see the position of.
func _stand_in() -> Node3D:
	var holder := MeshInstance3D.new()
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(WIDTH, CAP_HEIGHT, 0.016)
	holder.mesh = cap_mesh
	holder.material_override = Materials.fader_cap()

	var line := MeshInstance3D.new()
	var line_mesh := BoxMesh.new()
	line_mesh.size = Vector3(WIDTH * 1.05, 0.0015, 0.0165)
	line.mesh = line_mesh
	line.material_override = Materials.legend()
	holder.add_child(line)
	return holder


## Loudest the slide ever gets, at the top of SPEED_FOR_FULL. A cap dragged the length of its
## travel is a quiet sound in life -- felt more than heard -- and it is competing with a mix.
const SLIDE_DB := -11.0
## Travel-per-second that counts as flat out. One full throw in a third of a second.
const SPEED_FOR_FULL := 3.0


## How loud the slide should be for a given speed, 0 meaning do not play it at all.
##
## Square-rooted rather than linear: a cap creeping along still makes a sound, and a linear law
## leaves the slow two-thirds of every move silent, which is exactly the part of a move where the
## confirmation is worth most.
static func slide_gain(speed: float) -> float:
	if speed <= 0.02:
		return 0.0
	return sqrt(clampf(speed / SPEED_FOR_FULL, 0.0, 1.0))


func _on_grab_begin(at: Vector3) -> void:
	_last_value = value
	_speed = 0.0
	if _slide == null:
		_slide = Foley.emitter(Foley.fader_slide(), -80.0)
		add_child(_slide)
	# Parented to the cap so it comes from where the cap is. A slide emitted from the strip's
	# origin would sit at the bottom of the throw no matter where the hand was, which on a desk
	# three faders wide is audibly the wrong fader.
	if _cap != null and _slide.get_parent() != _cap:
		_slide.get_parent().remove_child(_slide)
		_cap.add_child(_slide)
	_slide.volume_db = -80.0
	_slide.play()
	set_process(true)
	# Grabbing the cap must not jump the value; grabbing the trough should. The offset is kept
	# only when the contact was already on the cap, which is what distinguishes the two without
	# needing two colliders.
	var local_y := to_local(at).y
	var cap_y := value * TRAVEL
	var on_cap := absf(local_y - cap_y) < CAP_HEIGHT
	_grab_offset = (cap_y - local_y) if on_cap else 0.0
	# With notches on, a tap on the trough is a NUDGE rather than a jump, and that single
	# change is what makes the fader usable without a drag at all: tap above the cap to go up,
	# below it to go down, one notch a time, with no precision required anywhere. Jumping to the
	# tap would demand exactly the accuracy stepping exists to remove.
	if not on_cap and Ergonomics.current.step > 0.0:
		_grab_offset = 0.0
		_set_value(Ergonomics.current.nudge(value, 1 if local_y > cap_y else -1))
		return
	_apply_from_local_y(local_y)


func _on_grab_move(at: Vector3) -> void:
	_apply_from_local_y(to_local(at).y)


func _on_grab_end() -> void:
	if _slide != null:
		_slide.stop()
	_speed = 0.0
	set_process(false)


## Runs only while held, so a desk of ninety strips costs nothing when nobody is touching it.
func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	var moved := absf(value - _last_value) * TRAVEL / delta
	_last_value = value
	# Decays toward the measured speed rather than taking it. A hand's velocity measured over one
	# frame is extremely noisy -- a still hand reads as several cm/s on a tracked controller --
	# and an un-smoothed gain turns a steady pull into a sound that flutters.
	_speed = lerpf(_speed, moved, clampf(delta * 14.0, 0.0, 1.0))
	if _slide != null:
		var gain := slide_gain(_speed)
		_slide.volume_db = -80.0 if gain <= 0.0 else SLIDE_DB + linear_to_db(gain)


func _apply_from_local_y(local_y: float) -> void:
	_set_value(clampf((local_y + _grab_offset) / TRAVEL, 0.0, 1.0))


func _set_value(to: float) -> void:
	value = Ergonomics.current.quantise(to)
	_on_value_changed()
	if write_value.is_valid():
		write_value.call(value)
	else:
		DAW.set_track_volume(track_index, value)


func _on_value_changed() -> void:
	if _cap == null:
		return
	_cap.position = Vector3(0, value * TRAVEL, 0.009)
	if _cap_slot >= 0:
		cap_bank.move_slot(_cap_slot, cap_bank.global_transform.affine_inverse() * _cap.global_transform)


func _default_title() -> String:
	return "LEVEL"


## In dB through the DAW's own law, because that is the unit a mix is argued about in. A
## position -- "71%" -- is true and useless.
func _default_readout() -> String:
	var db := DAW.taper_to_db(value)
	return "-inf dB" if db < -150.0 else "%+.1f dB" % db


func hint() -> String:
	return "drag or scroll  ·  shift for fine  ·  click the slot to jump"


## In dB, because that is how a level is nudged on every desk: a dB a notch, a tenth fine. Out
## of -inf the first notch up lands on -60 rather than on a dB above minus infinity.
func _on_nudge(notches: int, fine: bool) -> bool:
	var erg := Ergonomics.current
	if erg.step > 0.0:
		_set_value(erg.nudge(value, notches))
		return true
	var db := DAW.taper_to_db(value)
	if db < -150.0:
		if notches < 0:
			return true
		db = -60.0
	else:
		db += float(notches) * (0.1 if fine else 1.0)
	_set_value(clampf(DAW.db_to_taper(db), 0.0, 1.0))
	return true
