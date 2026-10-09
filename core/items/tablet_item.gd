class_name TabletItem
extends Item

## The tablet: your personal mixer (docs/items_loop.md). In a hand here its screen lights with
## your personal mix (TabletFace), which only you see; anywhere else -- on its shelf, on the
## floor, in somebody else's hand -- the screen is dark glass. Its wireless plugs lie in a tray
## along the top: the face is where they are dragged out from and brought back to.
##
## What it patches is not the tablet's. The plugs are the room's (the studio keeps who has
## which where) and the levels are this person's PersonalMix, so they stay as they are when the
## tablet goes back on its shelf, and a pair of headphones keeps playing them.

const MODEL := "res://assets/models/tablet.glb"
const CASE := Color(0.09, 0.095, 0.105)
## A warm rubber bumper, so it is found on a shelf of black things.
const BUMPER := Color(0.42, 0.25, 0.12)
const GLASS := Color(0.015, 0.018, 0.024)
## The screen lit: a faint blue-black glow behind the face, within the room's light budget.
const LIT := Color(0.05, 0.075, 0.11)
const LIT_ENERGY := 0.6
## Where a desktop's hand holds it, in the eye's frame: low and a little left, its left edge in the
## hand (which would cover the rows were it any further over), clear of the middle of the
## view, near enough to read.
const VIEW_AT := Vector3(-0.04, -0.13, -0.5)

## A plug was dropped on a socket, or brought back (`socket` empty), in a hand here.
signal patch_asked(receiver: int, socket: StringName)

## The personal mix the face shows: the studio's.
var mix: PersonalMix
## The holder's colour, for the face's plugs and chips.
var colour := Color(0.95, 0.62, 0.22)
## Whether headphones are on this person's head, for the face to say.
var listening := false:
	set(v):
		listening = v
		if face != null:
			face.listening = v

var face: TabletFace = null
var _screen: MeshInstance3D
var _glass: StandardMaterial3D


func _init() -> void:
	id = &"tablet"
	super()
	state_changed.connect(func(_s: State) -> void: _show_face())


func item_title() -> String:
	return "TABLET"


func hint() -> String:
	return _hint("click to pick up: your personal mix, for your headphones")


func _build_body() -> Node3D:
	var root := Node3D.new()
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	root.add_child(model)
	var case := StandardMaterial3D.new()
	case.albedo_color = CASE
	case.roughness = 0.55
	var bumper := StandardMaterial3D.new()
	bumper.albedo_color = BUMPER
	bumper.roughness = 0.8
	var tray := StandardMaterial3D.new()
	tray.albedo_color = Color(0.03, 0.03, 0.035)
	tray.roughness = 0.9
	_glass = StandardMaterial3D.new()
	_glass.albedo_color = GLASS
	# Matte, as a screen with an anti-glare film is: a gloss would put the room's lamps across
	# the face.
	_glass.roughness = 0.5
	_glass.emission_enabled = true
	_glass.emission = LIT
	# Dark until it is in a hand here. The energy, not the switch: switching emission on and off
	# compiles a new shader.
	_glass.emission_energy_multiplier = 0.0
	var swap := {"case": case, "bumper": bumper, "tray": tray, "screen": _glass}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
	_screen = model.find_child("Screen", true, false) as MeshInstance3D
	return root


## Taller than the slate is thick: lying flat on the lower tier it is seen nearly edge-on from the
## seat, and a click has to find it there.
func _grip_shape() -> Shape3D:
	var s := BoxShape3D.new()
	s.size = Vector3(0.27, 0.07, 0.2)
	return s


func centre_height() -> float:
	return 0.0065


## Up on its edge in front of you, the tray along the top, its glass square to your eyes: held
## as a tablet is read. In a headset, as the hand holds it; on a desktop, where the eye can read
## it without turning, down and to the left of the middle of the view (VIEW_AT).
func held_pose() -> Transform3D:
	if carried_by is MouseInteractor:
		var carry := Transform3D(Basis(Vector3.RIGHT, MouseInteractor.CARRY_TIP), MouseInteractor.CARRY_AT)
		return carry.affine_inverse() * facing_eye(VIEW_AT)
	return Transform3D(Basis(Vector3.UP, 0.42) * Basis(Vector3.RIGHT, 1.02), Vector3(0.15, 0.07, 0.06))


## A pose at `at` in the eye's frame whose glass faces the eye, tray up.
static func facing_eye(at: Vector3) -> Transform3D:
	var normal := -at.normalized()
	var up := (Vector3.UP - normal * Vector3.UP.dot(normal)).normalized()
	# The glass is the model's +Y, and the tray its -Z.
	return Transform3D(Basis(normal.cross(-up), normal, -up), at)


## Flat and hard: it lands with a clack and slides.
func flies() -> Dictionary:
	return {"bounce": 0.15, "roll": 1.5, "drag": 0.06}


func on_bounce(speed: float) -> void:
	Foley.play(self, Foley.gear_bump(), clampf(linear_to_db(speed / 4.0), -24.0, -4.0), 1.1)


func _foley_contact() -> AudioStream:
	return Foley.gear_bump()


## The face on the glass while a hand here has it, and only then.
func _show_face() -> void:
	var mine := state == State.HELD and carried_by != null and mix != null
	_glass.emission_energy_multiplier = LIT_ENERGY if mine else 0.0
	if mine == (face != null):
		return
	if not mine:
		face.queue_free()
		face = null
		return
	face = TabletFace.new()
	face.name = "Face"
	face.mix = mix
	face.colour = colour
	face.listening = listening
	# On the glass: X along it, Y up it toward the tray, Z out of it.
	face.transform = _screen.transform * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.0004, 0))
	face.patch_asked.connect(func(receiver: int, socket: StringName) -> void: patch_asked.emit(receiver, socket))
	_screen.get_parent().add_child(face)
