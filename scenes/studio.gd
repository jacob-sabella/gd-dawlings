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

## The walls, which are a room rather than the floor's extent. Floor stays large because its far
## edge is never in shot from a working position and a small one shows its own border.
const ROOM_WIDTH := 6.4
const ROOM_DEPTH := 5.0
const WALL_HEIGHT := 2.8
## The stand that carries the timeline. Its top sits just under the panel's lower edge, which
## is why it is a constant rather than a number in two places: move the timeline and this has
## to follow or the panel floats again, one centimetre higher.
const TIMELINE_Y := 1.62
const TIMELINE_Z := -1.02
const TIMELINE_STAND_TOP := 1.46
const TIMELINE_STAND_Z := TIMELINE_Z - 0.04

## Set by whoever builds the studio, BEFORE adding it to the tree. The medium is not a rendering
## detail: it decides whether this participant gets a floor and furniture at all, and a studio
## that learned it a frame late would build a virtual room and then delete it in front of someone
## already wearing the headset.
var medium: int = Presentation.Medium.SCREEN
var xr_bootstrap: XRBootstrap = null

var camera: Camera3D
var rig: XRRig
var screen_stage: Node3D
var room_anchor: RoomAnchor
var studio_set: Node3D
var mount: SurfaceMount

var console: ConsoleSurface
var rack: RackSurface
var deck: TapeDeck
var patchbay: PatchbaySurface
var timeline: TimelineSurface

var _orbit_yaw := 0.0
var _orbit_pitch := -0.18
var _orbit_distance := 2.05
var _orbit_target := Vector3(0, 0.92, 0)


func _ready() -> void:
	_build_environment()
	# In AR the room is already there -- it is the one the participant is standing in. Drawing a
	# virtual floor over a real one is not a smaller version of the VR experience, it is a worse
	# one: it hides the actual floor and it disagrees with it by however much calibration is off.
	if medium != Presentation.Medium.AR:
		_build_room()
	_build_anchors()
	if medium != Presentation.Medium.AR:
		_build_furniture()
	_build_surfaces()
	if camera != null:
		_update_camera()
	if medium == Presentation.Medium.AR and xr_bootstrap != null:
		# Now, and not in XRBootstrap.start(): the environment it has to clear is the one built
		# four lines up.
		xr_bootstrap.apply_passthrough()


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

	# Three walls and no ceiling, which is a corner you are standing in rather than a backdrop
	# the gear is parked in front of.
	#
	# This used to be the back wall alone, on the stated grounds that enclosing the room would
	# bounce every light into the lens and make the desk harder to read. That is true of a
	# renderer with global illumination and false of this one: the environment is
	# AMBIENT_SOURCE_COLOR with no SDFGI, no VoxelGI and no SSIL, so ambient is a flat constant
	# applied the same whether a wall is there or not. Adding walls adds exactly zero bounced
	# light. What it adds is the thing a wide shot was missing -- an edge for the room to stop
	# at, instead of a floor fading into black on both sides.
	#
	# The ceiling stays off, and that reason does survive: the key light is a DirectionalLight3D
	# with shadows on, so a ceiling does not soften the room, it switches the key off.
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.072, 0.076, 0.085)
	wall_mat.roughness = 0.9

	# Narrower than the floor. A control room is a room, not a hangar, and the walls have to be
	# close enough to read as walls from the working position -- at nine metres apart they are
	# two more grey rectangles in the distance.
	for spec in [[Vector3(0, WALL_HEIGHT * 0.5, -2.2), Vector3(ROOM_WIDTH, WALL_HEIGHT, 0.1)],
			[Vector3(-ROOM_WIDTH * 0.5, WALL_HEIGHT * 0.5, 0.3),
					Vector3(0.1, WALL_HEIGHT, ROOM_DEPTH)],
			[Vector3(ROOM_WIDTH * 0.5, WALL_HEIGHT * 0.5, 0.3),
					Vector3(0.1, WALL_HEIGHT, ROOM_DEPTH)]]:
		var wall := MeshInstance3D.new()
		var wall_mesh := BoxMesh.new()
		wall_mesh.size = spec[1]
		wall.mesh = wall_mesh
		wall.position = spec[0]
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

	# A stand under the timeline, which until now hung in the air.
	#
	# It is the only thing in the room that did. The rack has a plinth, the deck a trolley, the
	# bay a bridge, the console its own carcass -- and then a metre of lit panel floating at
	# head height with nothing holding it. In a close-up that reads as a screen. In a wide shot
	# of the room it reads as the one object that is software, which is the single thing this
	# project is trying not to be.
	#
	# Two legs and a crossbar, deliberately the same vocabulary as the patchbay bridge rather
	# than a new idea: a room furnished out of three kinds of part looks like a room, and one
	# furnished out of six looks like a kit.
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.035, TIMELINE_STAND_TOP, 0.05)
		leg.mesh = leg_mesh
		leg.position = Vector3(side * 0.36, TIMELINE_STAND_TOP * 0.5, TIMELINE_STAND_Z)
		leg.material_override = Materials.chassis()
		studio_set.add_child(leg)

		# A foot, because a 35mm post standing on a floor is a post that fell over a moment ago.
		var foot := MeshInstance3D.new()
		var foot_mesh := BoxMesh.new()
		foot_mesh.size = Vector3(0.10, 0.022, 0.22)
		foot.mesh = foot_mesh
		foot.position = Vector3(side * 0.36, 0.011, TIMELINE_STAND_Z)
		foot.material_override = Materials.chassis()
		studio_set.add_child(foot)

	var crossbar := MeshInstance3D.new()
	var crossbar_mesh := BoxMesh.new()
	crossbar_mesh.size = Vector3(0.79, 0.028, 0.09)
	crossbar.mesh = crossbar_mesh
	crossbar.position = Vector3(0, TIMELINE_STAND_TOP + 0.014, TIMELINE_STAND_Z)
	crossbar.material_override = Materials.brushed_metal()
	studio_set.add_child(crossbar)


func _build_anchors() -> void:
	# The head and the hands differ by medium; everything downstream of them does not. That is
	# the point of putting screen_stage on whichever camera exists rather than on the desktop
	# one: a surface in SCREEN mode is a panel in front of your face whether your face is behind
	# a monitor or inside a headset.
	var head: Node3D
	if medium == Presentation.Medium.SCREEN:
		camera = Camera3D.new()
		camera.fov = 58.0
		camera.near = 0.02
		add_child(camera)
		head = camera

		var mouse := MouseInteractor.new()
		mouse.camera = camera
		mouse.name = "MouseHand"
		add_child(mouse)
	else:
		rig = XRRig.new()
		rig.name = "XRRig"
		add_child(rig)
		head = rig.head

	screen_stage = Node3D.new()
	screen_stage.name = "ScreenStage"
	screen_stage.position = Vector3(0, 0, -0.75)
	head.add_child(screen_stage)

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

	if rig != null:
		rig.room_anchor = room_anchor

	# A participant with no physical room to mark adopts the session frame outright and stands in
	# the same layout as everyone else. 1.2m is the span the default layout assumes between the
	# two floor marks. An AR participant does NOT get this: they have a real room, and handing
	# them a guessed frame would put the console somewhere plausible and wrong, which is harder
	# to notice than no console at all.
	if medium != Presentation.Medium.AR:
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

	# Hung on the back wall in the virtual set, which is where it goes for anyone who has
	# chosen to see it as an object. Its default mode is SCREEN in every medium -- a
	# forty-minute song is not furniture -- so most of the time this placement is unused, and
	# it is written anyway so that choosing ROOM does not drop it at the origin.
	timeline = TimelineSurface.new()
	timeline.name = "Timeline"
	timeline.position = Vector3(0, TIMELINE_Y, TIMELINE_Z)
	studio_set.add_child(timeline)
	mount.register(timeline)

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
	if camera == null:
		return
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
	if camera == null:
		return
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move.z -= 1.0
	if Input.is_key_pressed(KEY_S): move.z += 1.0
	if Input.is_key_pressed(KEY_A): move.x -= 1.0
	if Input.is_key_pressed(KEY_D): move.x += 1.0
	if move != Vector3.ZERO:
		var yaw := Basis(Vector3.UP, _orbit_yaw)
		_orbit_target += yaw * move.normalized() * delta * 1.4
		_update_camera()


## No-op in a headset, where the camera is a head. Kept callable either way so the screenshot
## harness does not have to know which medium it is pointing at.
func frame(target: Vector3, distance: float, yaw: float, pitch: float) -> void:
	if camera == null:
		return
	_orbit_target = target
	_orbit_distance = distance
	_orbit_yaw = yaw
	_orbit_pitch = pitch
	_update_camera()


func _update_camera() -> void:
	var offset := Basis(Vector3.UP, _orbit_yaw) * (Basis(Vector3.RIGHT, _orbit_pitch) * Vector3(0, 0, _orbit_distance))
	camera.position = _orbit_target + offset
	camera.look_at(_orbit_target, Vector3.UP)
