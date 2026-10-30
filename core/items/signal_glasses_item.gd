class_name SignalGlassesItem
extends Item

## A pair of signal glasses (docs/spatial_loop.md part three): on your head, the room shows you the
## audio path as glowing pipes (SignalView), thick as loud, amber near 0 dBFS, red over, a sign where
## the sound stops and why. Picked up, a click puts them on (`Interactor.wear`), as the headphones go
## on; bandmates see them on your ghost, and nothing changes in their room: the view is this
## player's alone (`Studio.signal_view_on`), never room state. A personal kind (ItemRoom.PERSONAL_KINDS):
## the shelf's pair is a dispenser, and a hand takes a pair of its own.
##
## They share the head with the headphones (Interactor.worn is one slot): putting one on sends the
## other home. At a desk X shows the signal with or without them.

const FRAME := Color(0.08, 0.08, 0.09)
## The lenses' tint: a faint amber, lit, so a pair on a shelf or a ghost reads as switched on.
const LENS := Color(1.0, 0.62, 0.22)
const RIM_RADIUS := 0.026
const APART := 0.064
const ARM := 0.13


func _init() -> void:
	id = &"glasses"
	super()


func item_title() -> String:
	return "SIGNAL GLASSES"


func hint() -> String:
	if in_hand():
		return "click to put them on and see the signal: pipes from every source to the speakers (X at a desk)"
	return _hint("click to take your own: they show where the sound goes, and where it stops")


func wearable() -> bool:
	return true


func _build_body() -> Node3D:
	var root := Node3D.new()
	var frame := StandardMaterial3D.new()
	frame.albedo_color = FRAME
	frame.roughness = 0.4
	frame.metallic = 0.3
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color(LENS, 0.55)
	lens.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lens.emission_enabled = true
	lens.emission = LENS
	lens.emission_energy_multiplier = 0.9
	lens.roughness = 0.1
	for side in [-1.0, 1.0]:
		var rim := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = RIM_RADIUS - 0.004
		torus.outer_radius = RIM_RADIUS
		torus.rings = 24
		torus.ring_segments = 6
		rim.mesh = torus
		rim.material_override = frame
		# A torus lies in XZ: stood up to face -Z, as an item faces.
		rim.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(side * APART * 0.5, 0, 0))
		root.add_child(rim)
		var glass := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = RIM_RADIUS - 0.003
		disc.bottom_radius = RIM_RADIUS - 0.003
		disc.height = 0.002
		disc.radial_segments = 20
		glass.mesh = disc
		glass.material_override = lens
		glass.transform = rim.transform
		root.add_child(glass)
		var arm := MeshInstance3D.new()
		var rod := BoxMesh.new()
		rod.size = Vector3(0.004, 0.006, ARM)
		arm.mesh = rod
		arm.material_override = frame
		arm.position = Vector3(side * (APART * 0.5 + RIM_RADIUS - 0.002), 0.004, ARM * 0.5)
		root.add_child(arm)
	var bridge := MeshInstance3D.new()
	var bar := BoxMesh.new()
	bar.size = Vector3(APART - RIM_RADIUS * 2.0 + 0.006, 0.005, 0.005)
	bridge.mesh = bar
	bridge.material_override = frame
	bridge.position = Vector3(0, 0.008, 0)
	root.add_child(bridge)
	return root


func _grip_shape() -> Shape3D:
	var s := BoxShape3D.new()
	s.size = Vector3(0.15, 0.06, 0.14)
	return s


func centre_height() -> float:
	return RIM_RADIUS


func on_bounce(speed: float) -> void:
	Foley.play(self, Foley.gear_bump(), clampf(linear_to_db(speed / 4.0), -30.0, -10.0), 1.4)


func _foley_contact() -> AudioStream:
	return Foley.gear_bump()


## A click with them in your hand: on they go.
func use(down: bool) -> void:
	if down and in_hand():
		carried_by.wear()
