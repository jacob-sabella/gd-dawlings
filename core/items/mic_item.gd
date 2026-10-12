class_name MicItem
extends Item

## A handheld mic. Picking it up is putting your voice on a track: in your hand it is live
## (`live_changed`), and the studio arms a track for you (MicArm); put down, thrown, handed on or
## taken, it is not, and the track goes back to how it was. It lives in the clip of the booth's
## mic stand, where a singer would reach for it.
##
## In anybody's hand its band glows, so everyone in the room can see who is singing.

const MODEL := "res://assets/models/mic.glb"
const BODY := Color(0.11, 0.115, 0.12)
const GRILLE := Color(0.72, 0.73, 0.75)
const FOAM := Color(0.035, 0.035, 0.04)
## The band at the grille's neck, lit while the mic is in a hand: an on-air red, dim enough to
## sit inside the room's light budget.
const HOT := Color(0.95, 0.12, 0.08)
const HOT_ENERGY := 1.6
## How high its axis is over its origin, lying down: about the body's radius at its middle.
const AXIS_HEIGHT := 0.022

## In a hand here or not: the studio arms and disarms on this.
signal live_changed(live: bool)

var live := false
var _band: StandardMaterial3D


func _init() -> void:
	id = &"mic"
	super()
	state_changed.connect(_on_state)


func item_title() -> String:
	return "MIC"


func hint() -> String:
	return _hint("click to take your own, and sing: it arms a track for you")


func _build_body() -> Node3D:
	var root := Node3D.new()
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	root.add_child(model)
	var body := StandardMaterial3D.new()
	body.albedo_color = BODY
	body.metallic = 0.6
	body.roughness = 0.45
	var grille := StandardMaterial3D.new()
	grille.albedo_color = GRILLE
	grille.metallic = 0.9
	grille.roughness = 0.3
	var foam := StandardMaterial3D.new()
	foam.albedo_color = FOAM
	foam.roughness = 0.95
	_band = StandardMaterial3D.new()
	_band.albedo_color = GRILLE * 0.8
	_band.metallic = 0.85
	_band.roughness = 0.3
	_band.emission_enabled = true
	_band.emission = HOT
	# Dark until it is in a hand. The energy, not the switch: switching emission on and off
	# compiles a new shader.
	_band.emission_energy_multiplier = 0.0
	var swap := {"body": body, "grille": grille, "foam": foam, "band": _band}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
	return root


func _grip_shape() -> Shape3D:
	var s := BoxShape3D.new()
	s.size = Vector3(0.07, 0.07, 0.24)
	return s


func centre_height() -> float:
	return AXIS_HEIGHT


## Grille up and toward you, the handle in the palm, as you hold a mic to sing into.
func held_pose() -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, 1.15) * Basis(Vector3.UP, 0.35), Vector3(0, 0.05, 0))


## Heavy for its size, and it does not bounce: it clunks, and rolls a little on its round body.
func flies() -> Dictionary:
	return {"bounce": 0.18, "roll": 3.5, "drag": 0.04}


## A tap on the grille: the thump everyone does to a mic before they trust it.
func use(down: bool) -> void:
	if down:
		poke(-0.08)
		Foley.play(self, Foley.rubber_tap(), -4.0, 0.45)


func on_bounce(speed: float) -> void:
	Foley.play(self, Foley.gear_bump(), clampf(linear_to_db(speed / 4.0), -24.0, -3.0), 1.4)


func _foley_contact() -> AudioStream:
	return Foley.plug_seat()


func _on_state(now: State) -> void:
	_band.emission_energy_multiplier = HOT_ENERGY if now == State.HELD else 0.0
	var here := now == State.HELD and carried_by != null
	if here != live:
		live = here
		live_changed.emit(live)
