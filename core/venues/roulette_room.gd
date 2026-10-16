class_name RouletteRoom
extends Venue

## The Rig Roulette room: one closed room as wide as the control room, running from its front wall
## to the back of the live room's reach -- felt-green walls, a dark wood floor, brass, and a wheel
## inlaid in the floor that spins to the music. It is a place the whole band is taken to (the host
## enters it with `Studio.enter_roulette_room`), not one of the venues the stage manager lists
## (`Venue.IDS`), so cycling venues never lands here.
##
## It is the control room's footprint with a different room round it: the desk, the racks and the
## roll board stand where they always do, so the walls are where the roll board and the roulette
## panel expect them, and `live_room_half` is the room's own half-width so everything the base
## class places against a side wall (the prop shelf, the hoop, the Tour case) stands inside it.

const HEIGHT := 3.6
## Floor position of the setup wall's post.
const STAND_AT := Vector2(-2.2, -1.5)
const WALL := 0.1
## The wheel inlaid in the floor: its centre, how far out the ring of pockets runs, how many.
const WHEEL_AT := Vector2(0.0, 4.6)
const WHEEL_RADIUS := 1.7
const POCKETS := 12
## How fast it turns at rest and at a full mix, in turns a second.
const SPIN_REST := 0.01
const SPIN_LOUD := 0.12

var _wheel: Node3D
var _spin := 0.0


func venue_id() -> StringName:
	return Venue.ROULETTE_ID


func title() -> String:
	return "Rig Roulette room"


func live_room_half() -> float:
	return room_width * 0.5


## The setup wall stands on its own in the room, between the patchbay and the console and turned
## a little toward the seat: the walls here are taken by the same gear every venue has, and
## a panel on one is hidden behind it from the seat.
func rig_roulette_spot() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, 0.5), Vector3(STAND_AT.x, 1.5, STAND_AT.y))


func solids() -> Array:
	var out := super.solids()
	out.append({"c": STAND_AT, "h": Vector2(0.55, 0.3), "a": 0.5, "top": 2.7})
	return out


func zones() -> Dictionary:
	return {}


func back_of_house() -> Rect2:
	var front := Studio.ROOM_BACK
	var half := live_room_half() - 0.05
	return Rect2(-half, front, half * 2.0, LIVE_ROOM_BACK - 0.05 - front)


func gear_style() -> GearStyle:
	return GearStyle.new() \
			.with("furniture", GearStyle.paint(Color(0.1, 0.075, 0.055), 0.55, 0.0)) \
			.with("chassis", GearStyle.paint(Color(0.07, 0.075, 0.08), 0.6, 0.2)) \
			.with("trim", GearStyle.metal(Color(0.72, 0.56, 0.24), 0.35)) \
			.with("loom_band", GearStyle.paint(Color(0.62, 0.1, 0.12), 0.8, 0.0))


func dress(env: Environment, key: DirectionalLight3D) -> void:
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.015, 0.012)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.52)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.1
	key.light_color = Color(1.0, 0.86, 0.66)
	key.light_energy = 0.0
	key.shadow_enabled = false


func track_palette() -> Array:
	return []


func _ready() -> void:
	var half := live_room_half()
	var back := LIVE_ROOM_BACK
	var front := Studio.ROOM_FRONT
	var depth := back - front
	var mid := (back + front) * 0.5

	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.13, 0.085, 0.055)
	floor_mat.roughness = 0.45
	var floor := MeshInstance3D.new()
	floor.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(half * 2.0, depth)
	floor.mesh = plane
	floor.position = Vector3(0, 0, mid)
	floor.material_override = floor_mat
	add_child(floor)

	var felt := StandardMaterial3D.new()
	felt.albedo_color = Color(0.05, 0.22, 0.15)
	felt.roughness = 0.95
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.03, 0.035, 0.034)
	dark.roughness = 0.9
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.74, 0.56, 0.24)
	brass.metallic = 0.85
	brass.roughness = 0.32

	# Four walls: the front and back full width, the sides butted between them.
	ZoneKit.block(self, Vector3(half * 2.0 + WALL, HEIGHT, WALL), Vector3(0, HEIGHT * 0.5, front), felt, "FrontWall")
	ZoneKit.block(self, Vector3(half * 2.0 + WALL, HEIGHT, WALL), Vector3(0, HEIGHT * 0.5, back), felt, "BackWall")
	for sx in [-1.0, 1.0]:
		ZoneKit.block(self, Vector3(WALL, HEIGHT, depth - WALL), Vector3(sx * half, HEIGHT * 0.5, mid), felt,
				"SideWall%s" % ("L" if sx < 0 else "R"))
	ZoneKit.block(self, Vector3(half * 2.0 + WALL, WALL, depth + WALL), Vector3(0, HEIGHT + WALL * 0.5, mid), dark,
			"Ceiling")
	# A brass rail round the room at chest height, proud of the felt, and a skirting under it.
	var rail_z := [front + WALL * 0.5 + 0.01, back - WALL * 0.5 - 0.01]
	for z: float in rail_z:
		ZoneKit.block(self, Vector3(half * 2.0 - WALL, 0.05, 0.02), Vector3(0, 1.05, z), brass, "Rail%d" % int(z * 10.0))
		ZoneKit.block(self, Vector3(half * 2.0 - WALL, 0.14, 0.03), Vector3(0, 0.07, z), dark, "Skirt%d" % int(z * 10.0))
	for sx in [-1.0, 1.0]:
		var x: float = sx * (half - WALL * 0.5 - 0.01)
		ZoneKit.block(self, Vector3(0.02, 0.05, depth - WALL * 2.0), Vector3(x, 1.05, mid), brass, "RailSide%d" % int(sx))
		ZoneKit.block(self, Vector3(0.03, 0.14, depth - WALL * 2.0), Vector3(x, 0.07, mid), dark, "SkirtSide%d" % int(sx))

	_inlay_the_wheel(brass)
	_hang_the_lamps(brass)
	_dress_prop_shelf(dark, brass, Color(1.0, 0.8, 0.5))


## A ring of red and black pockets round a brass hub, a hair above the floor: each pocket and the
## hub at a height of its own, so no two faces share a plane.
func _inlay_the_wheel(brass: Material) -> void:
	_wheel = Node3D.new()
	_wheel.name = "Wheel"
	_wheel.position = Vector3(WHEEL_AT.x, 0.0, WHEEL_AT.y)
	add_child(_wheel)
	var ring := ZoneKit.block(_wheel, Vector3(WHEEL_RADIUS * 2.0 + 0.3, 0.012, WHEEL_RADIUS * 2.0 + 0.3), Vector3(0, 0.006, 0),
			brass, "Bed")
	ring.mesh = CylinderMesh.new()
	(ring.mesh as CylinderMesh).top_radius = WHEEL_RADIUS + 0.15
	(ring.mesh as CylinderMesh).bottom_radius = WHEEL_RADIUS + 0.15
	(ring.mesh as CylinderMesh).height = 0.012
	for i in POCKETS:
		var a := TAU * float(i) / POCKETS
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.62, 0.08, 0.1) if i % 2 == 0 else Color(0.04, 0.04, 0.045)
		m.roughness = 0.5
		var pocket := ZoneKit.block(_wheel, Vector3(0.48, 0.01, 0.6), Vector3.ZERO, m, "Pocket%d" % i)
		pocket.position = Vector3(sin(a), 0.0, cos(a)) * (WHEEL_RADIUS - 0.3) + Vector3(0, 0.014 + 0.0004 * i, 0)
		pocket.rotation.y = a
	var hub := MeshInstance3D.new()
	hub.name = "Hub"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.28
	cyl.bottom_radius = 0.32
	cyl.height = 0.08
	hub.mesh = cyl
	hub.position = Vector3(0, 0.05, 0)
	hub.material_override = brass
	_wheel.add_child(hub)


## Three pendant lamps over the wheel and the walking floor: warm, no shadows, a small lit shade each.
func _hang_the_lamps(brass: Material) -> void:
	var xs := [-2.2, 0.0, 2.2]
	for i in xs.size():
		var at := Vector3(xs[i], HEIGHT - 0.5, WHEEL_AT.y)
		ZoneKit.block(self, Vector3(0.02, 0.5, 0.02), at + Vector3(0, 0.25, 0), brass, "LampCord%d" % i)
		ZoneKit.block(self, Vector3(0.34, 0.12, 0.34), at, brass, "LampShade%d" % i)
		ZoneKit.block(self, Vector3(0.24, 0.02, 0.24), at + Vector3(0, -0.07, 0), ZoneKit.glow(Color(1.0, 0.85, 0.6), 3.0),
				"LampBulb%d" % i)
		var light := OmniLight3D.new()
		light.name = "Lamp%d" % i
		light.position = at + Vector3(0, -0.3, 0)
		light.light_color = Color(1.0, 0.84, 0.62)
		light.light_energy = 2.0
		light.omni_range = 6.5
		light.shadow_enabled = false
		add_child(light)


func pulse(level: float) -> void:
	hear(level)


func _process(delta: float) -> void:
	if _wheel == null:
		return
	_spin = fposmod(_spin + lerpf(SPIN_REST, SPIN_LOUD, heard) * delta, 1.0)
	_wheel.rotation.y = _spin * TAU
