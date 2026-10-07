class_name Studio
extends Node3D

## The room, its lighting, and the three anchors a surface can hang from.
##
## Built in code rather than authored as a .tscn, and that is a considered choice rather than
## laziness. Nothing in here has a fixed shape: the console is as wide as the project has tracks,
## the rack is as tall as it has plugins, and in ROOM mode the whole layout is positioned against
## a physical room measured at run time. A .tscn would be a snapshot of one project's dimensions,
## and every launch would start by discarding it.
##
## THE THREE ANCHORS, which are the whole of the hybrid mode:
##
##   screen_stage  a child of the CAMERA. Things here follow the viewer's head and are read like
##                 a panel. Where a timeline belongs.
##   room_anchor   the shared physical frame, calibrated against two marks on the real floor.
##                 Things here stand still while you walk around them, and everyone in the room
##                 agrees where they are. See core/xr/room_anchor.gd.
##   studio_set    the virtual room. For a participant who is not in the physical one.
##
## A surface is placed in exactly one of them, per viewer, by SurfaceMount.

const FLOOR_SIZE := 9.0

var camera: Camera3D
var screen_stage: Node3D
var room_anchor: RoomAnchor
var studio_set: Node3D
var mount: SurfaceMount

var console: ConsoleSurface
var rack: RackSurface
var deck: TapeDeck
var patchbay: PatchbaySurface

var _orbit_yaw := 0.0
var _orbit_pitch := -0.18
var _orbit_distance := 2.05
var _orbit_target := Vector3(0, 0.92, 0)


func _ready() -> void:
	_build_environment()
	_build_room()
	_build_anchors()
	_build_furniture()
	_build_surfaces()
	_update_camera()


func _build_environment() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.021, 0.024, 0.030)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.20, 0.23, 0.30)
	env.ambient_light_energy = 0.58

	# Glow is load-bearing, not a filter. Every LED, meter segment and lamp in this project is an
	# emissive material above 1.0, and without a glow pass they are merely slightly brighter
	# paint -- a muted channel and an unmuted one become almost the same picture.
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 4.0
	env.ssao_enabled = true
	env.ssao_radius = 0.4
	env.ssao_intensity = 1.4
	world.environment = env
	add_child(world)

	# Key light from above and in front, as a studio's ceiling panel would be. Shadows are what
	# seat the gear on the desk rather than leaving it floating a centimetre above it.
	var key := DirectionalLight3D.new()
	key.light_energy = 1.05
	key.light_color = Color(0.92, 0.94, 1.0)
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-62, 18, 0)
	add_child(key)

	# Two warm practicals, the lamps an actual control room has. They also give the metal
	# something to catch: brushed aluminium under a single light source reads as flat grey.
	for spec in [[Vector3(-1.9, 1.95, 1.1), Color(1.0, 0.78, 0.52), 7.0],
			[Vector3(1.8, 1.85, -0.9), Color(0.6, 0.78, 1.0), 5.0]]:
		var lamp := OmniLight3D.new()
		lamp.position = spec[0]
		lamp.light_color = spec[1]
		lamp.light_energy = spec[2]
		lamp.omni_range = 6.5
		lamp.shadow_enabled = false
		add_child(lamp)


func _build_room() -> void:
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(FLOOR_SIZE, FLOOR_SIZE)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.055, 0.058, 0.065)
	floor_mat.roughness = 0.55
	floor_mat.metallic = 0.1
	floor_mesh.material_override = floor_mat
	add_child(floor_mesh)

	# Back wall only. A fully enclosed room looks better and makes the desk harder to read in a
	# screenshot, because every light then bounces into the lens. One wall gives the gear
	# something to be in front of.
	var wall := MeshInstance3D.new()
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(FLOOR_SIZE, 2.8, 0.1)
	wall.mesh = wall_mesh
	wall.position = Vector3(0, 1.4, -2.2)
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.072, 0.076, 0.085)
	wall_mat.roughness = 0.9
	wall.material_override = wall_mat
	add_child(wall)


## Furniture: the things that hold the gear up.
##
## Separate from the surfaces on purpose, and the line matters. A surface is DRIVEN BY REAPER --
## it exists because the project has tracks or plugins, and its size follows them. A stand is
## not; it is set dressing, it means nothing, and in ROOM mode it is not drawn at all because the
## participant already has real furniture. Mixing the two would mean a rack that cannot be put
## on the floor without inventing a plugin to justify its legs.
func _build_furniture() -> void:
	# Meter bridge: the arm that carries the patchbay up off the back of the desk. Every console
	# with anything mounted above it has one, and without it the bay hangs in the air.
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.035, 0.46, 0.05)
		leg.mesh = leg_mesh
		leg.position = Vector3(side * 0.30, 1.03, -0.33)
		leg.material_override = Materials.chassis()
		studio_set.add_child(leg)

	var bridge := MeshInstance3D.new()
	var bridge_mesh := BoxMesh.new()
	bridge_mesh.size = Vector3(0.70, 0.03, 0.09)
	bridge.mesh = bridge_mesh
	bridge.position = Vector3(0, 1.20, -0.35)
	bridge.material_override = Materials.brushed_metal()
	studio_set.add_child(bridge)

	# A trolley for the deck. Two uprights and a shelf; a tape machine on a stand is what the
	# right-hand side of a control room looks like.
	var shelf := MeshInstance3D.new()
	var shelf_mesh := BoxMesh.new()
	shelf_mesh.size = Vector3(0.56, 0.04, 0.42)
	shelf.mesh = shelf_mesh
	shelf.position = Vector3(0.80, 0.86, -0.22)
	shelf.rotation_degrees = Vector3(0, -32, 0)
	shelf.material_override = Materials.chassis()
	studio_set.add_child(shelf)

	# A plinth under the rack. A floor-standing rack puts its lowest unit at ankle height; every
	# control room that has one has it up on something.
	var plinth := MeshInstance3D.new()
	var plinth_mesh := BoxMesh.new()
	plinth_mesh.size = Vector3(0.60, 0.30, 0.34)
	plinth.mesh = plinth_mesh
	plinth.position = Vector3(-1.18, 0.15, -0.42) + Basis(Vector3.UP, deg_to_rad(38)) * Vector3(0, 0, -0.15)
	plinth.rotation_degrees = Vector3(0, 38, 0)
	plinth.material_override = Materials.chassis()
	studio_set.add_child(plinth)

	for dx in [-0.22, 0.22]:
		for dz in [-0.16, 0.16]:
			var post := MeshInstance3D.new()
			var post_mesh := BoxMesh.new()
			post_mesh.size = Vector3(0.03, 0.86, 0.03)
			post.mesh = post_mesh
			var offset := Basis(Vector3.UP, deg_to_rad(-32)) * Vector3(dx, 0, dz)
			post.position = Vector3(0.80, 0.43, -0.22) + offset
			post.material_override = Materials.brushed_metal()
			studio_set.add_child(post)


func _build_anchors() -> void:
	camera = Camera3D.new()
	camera.fov = 58.0
	camera.near = 0.02
	add_child(camera)

	# Parented to the camera, which is what SCREEN mode means: a panel at a fixed place in the
	# viewer's own field of view, not a thing in the room.
	screen_stage = Node3D.new()
	screen_stage.name = "ScreenStage"
	screen_stage.position = Vector3(0, 0, -0.75)
	camera.add_child(screen_stage)

	var mouse := MouseInteractor.new()
	mouse.camera = camera
	mouse.name = "MouseHand"
	add_child(mouse)

	room_anchor = RoomAnchor.new()
	room_anchor.name = "RoomAnchor"
	add_child(room_anchor)

	studio_set = Node3D.new()
	studio_set.name = "StudioSet"
	add_child(studio_set)

	mount = SurfaceMount.new()
	mount.name = "SurfaceMount"
	mount.screen_stage = screen_stage
	mount.room_anchor = room_anchor
	mount.studio_set = studio_set
	add_child(mount)

	# A screen participant has no physical room to mark, so they adopt the session frame outright
	# and stand in the same layout as everyone else. 1.2m is the span the default layout assumes
	# between the two floor marks.
	room_anchor.adopt_virtual_frame(1.2)


func _build_surfaces() -> void:
	# These transforms are the DEFAULT LAYOUT, used until a participant moves something and their
	# LayoutProfile starts overriding them. Heights are real: the desk surface at 0.74m, the
	# patchbay at eye level over it, the rack within arm's reach to the left.
	console = ConsoleSurface.new()
	console.name = "Console"
	console.position = Vector3(0, 0.74, 0.1)
	studio_set.add_child(console)
	mount.register(console)

	patchbay = PatchbaySurface.new()
	patchbay.name = "Patchbay"
	patchbay.position = Vector3(0, 1.23, -0.33)
	patchbay.rotation_degrees = Vector3(-18, 0, 0)
	studio_set.add_child(patchbay)
	mount.register(patchbay)

	rack = RackSurface.new()
	rack.name = "Rack"
	rack.position = Vector3(-1.18, 0.30, -0.42)
	rack.rotation_degrees = Vector3(0, 38, 0)
	studio_set.add_child(rack)
	mount.register(rack)

	deck = TapeDeck.new()
	deck.name = "TapeDeck"
	deck.position = Vector3(0.80, 1.02, -0.20)
	deck.rotation_degrees = Vector3(-20, -32, 0)
	studio_set.add_child(deck)
	mount.register(deck)


# --- desktop camera -----------------------------------------------------------------------

## Orbit on right-drag, zoom on wheel, WASD to walk. Not a replacement for standing in the room;
## it is how the screen half of a hybrid session gets around, and how every screenshot of this
## project is framed.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_orbit_yaw -= event.relative.x * 0.005
		_orbit_pitch = clampf(_orbit_pitch - event.relative.y * 0.005, -1.4, 1.2)
		_update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_distance = maxf(0.4, _orbit_distance - 0.12)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_distance = minf(6.0, _orbit_distance + 0.12)
			_update_camera()


func _process(delta: float) -> void:
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move.z -= 1.0
	if Input.is_key_pressed(KEY_S): move.z += 1.0
	if Input.is_key_pressed(KEY_A): move.x -= 1.0
	if Input.is_key_pressed(KEY_D): move.x += 1.0
	if move != Vector3.ZERO:
		var yaw := Basis(Vector3.UP, _orbit_yaw)
		_orbit_target += yaw * move.normalized() * delta * 1.4
		_update_camera()


func frame(target: Vector3, distance: float, yaw: float, pitch: float) -> void:
	_orbit_target = target
	_orbit_distance = distance
	_orbit_yaw = yaw
	_orbit_pitch = pitch
	_update_camera()


func _update_camera() -> void:
	var offset := Basis(Vector3.UP, _orbit_yaw) * (Basis(Vector3.RIGHT, _orbit_pitch) * Vector3(0, 0, _orbit_distance))
	camera.position = _orbit_target + offset
	camera.look_at(_orbit_target, Vector3.UP)
