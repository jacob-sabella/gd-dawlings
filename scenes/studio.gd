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
## The meter bridge's crossbar. Constants rather than numbers in the builder because the console
## loom has to be routed BEHIND it: the first version of that loom took the short way down and
## went straight through the bar, which is the sort of thing no amount of reading the code finds
## and one photograph finds immediately.
## The lamps in the room: where the light comes from, what colour, and how hard.
##
## One table, read twice -- once by the environment to make the lights and once by the furniture
## to make the stands under them. They were two floating OmniLights with nothing to come out of,
## which is the lighting version of the patchbay wired to nothing: a room lit by sources you
## cannot see. The third is new, and it is there because the measurement said so -- the rack's
## faceplate read 13.8 against the console's 22.1, and the floor at its foot 9.1 against 29.5.
const PRACTICALS: Array = [
	[Vector3(-2.05, 1.76, 1.25), Color(1.0, 0.78, 0.52), 6.0],
	[Vector3(1.62, 1.70, -1.15), Color(0.6, 0.78, 1.0), 5.5],
	# Moved back and out, and turned down, once the desk started being summoned to the mix
	# position. At (-0.80, 1.72, 0.34) this lamp stood 0.71m from the left end of a summoned
	# desk and 1.55m from the right; inverse square makes that a five-to-one gradient across
	# one console, and the left end blew to white -- the BANK module read as a hole in the
	# panel and its indicator bar lost its colour entirely. It also stood 80cm to the left of
	# the mix position and 30cm in front of it, which is somewhere you would kick it.
	#
	# From here, against the body's own work light, inverse-square irradiance at the two ends
	# comes out within a couple of percent. Summoned gear is lit by the work light; the room's
	# lamps light the ROOM. `_test_the_desk_is_lit_evenly_end_to_end` holds the balance.
	[Vector3(-1.50, 1.72, 0.95), Color(1.0, 0.82, 0.60), 4.5],
]
## How far a practical reaches. Short on purpose: at 6.5m each lamp lit all three walls, and
## three of them made the empty half of the room as bright as the gear (37.0 against 38.7 on
## the console's face). A floor lamp is a pool, not a sun.
const LAMP_RANGE := 3.6
## The lamp head. Wide and low rather than tall and thin: the first pass put a 105mm shade on a
## two-metre pole, which from across the room is a street light. A floor lamp is shorter than
## the people using it and its head is the part you notice.
const LAMP_SHADE_RADIUS := 0.165
const LAMP_SHADE_HEIGHT := 0.150
const BRIDGE_POS := Vector3(0, 1.20, -0.35)
const BRIDGE_SIZE := Vector3(0.70, 0.03, 0.09)

## Set by whoever builds the studio, BEFORE adding it to the tree. The medium is not a rendering
## detail: it decides whether this participant gets a floor and furniture at all, and a studio
## that learned it a frame late would build a virtual room and then delete it in front of someone
## already wearing the headset.
var medium: int = Presentation.Medium.SCREEN
var xr_bootstrap: XRBootstrap = null

signal venue_changed(id: StringName)

## The world the studio stands in. See core/venues/venue.gd.
var venue: Venue
var world_env: WorldEnvironment
var key_light: DirectionalLight3D

var camera: Camera3D
var rig: XRRig
var screen_stage: Node3D
var room_anchor: RoomAnchor
var studio_set: Node3D
var mount: SurfaceMount
var body: BodyFrame
var focus: FocusRig
## This participant's body. Everything placed for a person is placed from it, and it is one
## object rather than a scattering of constants precisely so there is somewhere to change it.
var ergonomics := Ergonomics.new()

var console: ConsoleSurface
var rack: RackSurface
var deck: TapeDeck
var patchbay: PatchbaySurface
var timeline: TimelineSurface

## Where each machine's loom leaves it, in that machine's own space, and where it lands across
## the back of the bay. One entry per run: machine, exit point, exit direction, the fraction
## across the bay's back it arrives at, and the point on the floor its run passes through.
##
## The floor points all sit behind the desk rather than in front of it, which is both where real
## trunking goes and the only place in this room where two metres of cable is not underfoot.
## Where each machine's loom leaves it, in that machine's own space; where it lands across the
## back of the bay; and, for the two that take the floor, the point on the floor their run passes
## through -- and a flag saying which kind it is. The console's does not take the floor: it
## stands directly under the bay, so its loom is a hanging drop rather than a metre and a half
## of trunk going the long way round to a destination half a metre above where it started. Its
## via is the clearance point behind the meter bridge instead.
const LOOM_RUNS: Array = [
	# The console's via is level with where it leaves the bay and well behind the crossbar, so
	# the run goes BACK before it goes down. Dropping first and clearing the bar afterwards is
	# the shorter cable and it does not fit: the test caught the curve sagging through the top
	# of the bar fifteen millimetres past the gland.
	["console", Vector3(0, 0.02, -0.19), Vector3(0, 0.6, -1.0), 0.0,
			Vector3(0, BRIDGE_POS.y + BRIDGE_SIZE.y * 0.5 + 0.020,
					BRIDGE_POS.z - BRIDGE_SIZE.z * 0.5 - 0.075), false],
	["rack", Vector3(0, 0.07, -0.29), Vector3(0, -0.18, -1.0), -0.74,
			Vector3(-0.92, 0, -1.02), true],
	["deck", Vector3(0, -0.02, -0.05), Vector3(0, -0.5, -1.0), 0.74,
			Vector3(0.86, 0, -0.96), true],
]

var _looms: Array[GearLoom] = []
var _looms_dirty := false
var _loom_clock := 0.0

## The floor and everything on wheels. Null in AR, where the floor is real and so is the
## furniture.
var floor_plan: FloorPlan
var rack_trolley: Trolley
var deck_trolley: Trolley
var timeline_stand: Trolley
## Surface id -> [the trolley it stands on, where on that trolley].
var _seated_on := {}
var _lamps: Array[OmniLight3D] = []
## {piece_id: Transform3D} -- where the authored layout stood each piece, for the things that
## were written against it: the floor points the looms run through.
var _authored_floor: Dictionary = {}

## Where a person stands to work, on a monitor. Far enough forward of the console's home at
## z = 0.1 that gear summoned to arm's length lands on the desk rather than through it.
const MIX_POSITION_Z := 0.66

## Vertical field of view, in degrees: wide enough to take in a room, long enough to work at a
## desk without the near edge of it bowing away from you.
## The lens for looking AT the room, as against being seated at one thing in it. Named rather
## than written twice, because it was written twice -- 58 where the camera is set up and 75
## where focus is released -- and releasing focus quietly widened the room by seventeen
## degrees every time.
const ROOM_FOV := 58.0
const SEATED_FOV := 54.0
## Roughly what a headset shows vertically. Not a lens anyone sets -- the runtime owns the
## projection -- but surfaces still need a number to size themselves against, and the visor's
## own field is the honest one.
const HEADSET_FOV := 95.0

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
		set_venue(Session.layout.venue if Session.layout != null else Venue.IDS[0], false)
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
	world_env = WorldEnvironment.new()
	world_env.environment = _house_environment()
	add_child(world_env)
	if rich_rendering():
		_tune_renderer()

	# Key light from above and in front, as a studio's ceiling panel would be. Shadows are what
	# seat the gear on the desk rather than leaving it floating a centimetre above it.
	key_light = DirectionalLight3D.new()
	key_light.name = "Key"
	_house_key(key_light)
	add_child(key_light)

	# The practicals, the lamps an actual control room has. They also give the metal something to
	# catch: brushed aluminium under a single light source reads as flat grey. The stands that
	# hold them up are furniture and are built there, because an AR participant has real lamps
	# in a real room and needs these to light the virtual gear without appearing in front of him.
	for spec in PRACTICALS:
		var lamp := OmniLight3D.new()
		lamp.position = spec[0]
		lamp.light_color = spec[1]
		lamp.light_energy = spec[2]
		lamp.omni_range = LAMP_RANGE
		lamp.shadow_enabled = false
		if rich_rendering():
			# Soft, contact-hardening shadows from a bulb the size of a bulb. A lamp that lights
			# gear without shadowing it is what made everything look pasted onto the room.
			lamp.shadow_enabled = true
			lamp.light_size = 0.06
			lamp.shadow_bias = 0.04
			lamp.shadow_normal_bias = 1.0
			lamp.light_volumetric_fog_energy = 0.6
		add_child(lamp)
		_lamps.append(lamp)


## The environment every venue starts from, and the one an AR participant keeps.
func _house_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.021, 0.024, 0.030)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.20, 0.23, 0.30)
	# Dropped from 0.58 when the third practical went in. Ambient is what fills the room rather
	# than the work, so it is the first thing to come down when more lamps are added: the
	# alternative is a room where the empty floor reads as brightly as the console.
	env.ambient_light_energy = 0.46

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
	return env


func _house_key(key: DirectionalLight3D) -> void:
	key.light_energy = 1.05
	key.light_specular = 1.0
	key.light_color = Color(0.92, 0.94, 1.0)
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-62, 18, 0)
	# Fitted to the room, not to the default hundred metres. A directional shadow map is spread
	# over its whole distance, so at 100m every texel was several centimetres across -- coarser
	# than a fader cap -- and the shadows of everything small on the desk shimmered as the
	# camera moved. It reads as z-fighting and it is not; it is a shadow map looking at a
	# console from the far side of a football pitch.
	key.directional_shadow_max_distance = 9.0
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	key.directional_shadow_blend_splits = true
	key.shadow_normal_bias = 1.2
	key.shadow_bias = 0.03
	key.light_angular_distance = 1.2
	key.shadow_blur = 1.0
	key.light_color = Color(0.92, 0.94, 1.0)
	key.rotation_degrees = Vector3(-62, 18, 0)
	key.shadow_enabled = true


## Renderer-wide settings for the desktop: shadow resolution and filtering, antialiasing. Not
## per venue -- these are about the machine, not the scenery.
func _tune_renderer() -> void:
	RenderingServer.directional_shadow_atlas_set_size(8192, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
			RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	RenderingServer.positional_soft_shadow_filter_set_quality(
			RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	var view := get_viewport()
	if view != null:
		view.positional_shadow_atlas_size = 8192
		view.msaa_3d = Viewport.MSAA_4X
		view.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
		view.use_debanding = true


## Stand the studio somewhere else. The gear, the furniture, where it has all been pushed and
## what is focused are untouched; the floor, the sky, the air and the light change.
##
## `persist` false for a venue asked for on the command line, which is a look for one run and
## not a change of mind.
func set_venue(id: StringName, persist := true) -> void:
	if medium == Presentation.Medium.AR:
		return
	if not Venue.is_known(id):
		id = Venue.IDS[0]
	if venue != null:
		remove_child(venue)
		venue.queue_free()
	venue = Venue.make(id)
	venue.name = "Venue"
	venue.rich = rich_rendering()
	var env := _house_environment()
	_house_key(key_light)
	venue.dress(env, key_light)
	world_env.environment = env
	add_child(venue)
	for i in _lamps.size():
		if i < PRACTICALS.size():
			_lamps[i].light_color = venue.lamp_colour(i, PRACTICALS[i][1])
			_lamps[i].light_energy = venue.lamp_energy(i, PRACTICALS[i][2])
	if persist and Session.layout != null:
		Session.layout.venue = id
		Session.layout.save()
	venue_changed.emit(id)


func cycle_venue() -> void:
	set_venue(Venue.next_after(venue.venue_id() if venue != null else Venue.IDS[0]))


## Whether this participant gets the whole renderer: global illumination, screen-space
## reflections, volumetric light, soft shadows. A desktop does; a standalone headset runs the
## mobile renderer, which has none of it and must not be asked. Decided by what is actually
## running rather than by medium alone -- a desktop forced onto the compatibility renderer
## must fall back too.
func rich_rendering() -> bool:
	return medium == Presentation.Medium.SCREEN \
			and RenderingServer.get_current_rendering_method() == "forward_plus"


## Furniture: the things that hold the gear up.
##
## Separate from the surfaces on purpose, and the line matters. A surface is DRIVEN BY REAPER --
## it exists because the project has tracks or plugins, and its size follows them. A stand is
## not; it is set dressing, it means nothing, and in ROOM mode it is not drawn at all because the
## participant already has real furniture. Mixing the two would mean a rack that cannot be put
## on the floor without inventing a plugin to justify its legs.
## One piece of furniture, as one node.
##
## The furniture used to be a flat heap of boxes under the set: four posts, a shelf, two legs,
## a crossbar, all siblings. That is fine to LOOK at and useless to move, and moving it is now
## required -- a surface summoned to the mix position lands exactly where the stand that used
## to hold it is still standing, and a trolley through the master section is the kind of thing
## no amount of lighting rescues. A rig can hide an assembly. It cannot hide half a trolley
## and leave the other two legs up.
func _assembly(of_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = of_name
	node.add_to_group(&"room_furniture")
	studio_set.add_child(node)
	return node


func _build_furniture() -> void:
	floor_plan = FloorPlan.new()
	floor_plan.name = "FloorPlan"
	floor_plan.bounds = Rect2(-ROOM_WIDTH * 0.5 + 0.05, -2.15, ROOM_WIDTH - 0.10, ROOM_DEPTH - 0.05)
	floor_plan.fixtures.append(_desk_footprint)
	add_child(floor_plan)

	# Meter bridge: the arm that carries the patchbay up off the back of the desk. Every console
	# with anything mounted above it has one, and without it the bay hangs in the air.
	var bridge_frame := _assembly("MeterBridge")
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.035, 0.46, 0.05)
		leg.mesh = leg_mesh
		# Centred under the bar rather than flush with its face: flush, the leg's front and the
		# bar's front were one plane and the joint shimmered.
		leg.position = Vector3(side * 0.30, 1.03, BRIDGE_POS.z)
		leg.material_override = Materials.chassis()
		bridge_frame.add_child(leg)

	var bridge := MeshInstance3D.new()
	var bridge_mesh := BoxMesh.new()
	bridge_mesh.size = BRIDGE_SIZE
	bridge.mesh = bridge_mesh
	bridge.position = BRIDGE_POS
	bridge.material_override = Materials.brushed_metal()
	bridge_frame.add_child(bridge)

	_build_lamp_stands()

	# A trolley for the deck. Two uprights and a shelf on a caster base; a tape machine on a
	# cart is what the right-hand side of a control room looks like, and it is the thing in
	# the room most often wheeled somewhere else.
	deck_trolley = _trolley("DeckTrolley", &"deck_trolley", Vector3(0.80, 0, -0.22), -32.0)
	deck_trolley.footprint_half = Vector2(0.28, 0.21)
	deck_trolley.follow = 10.0
	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(0.56, 0.025, 0.42)
	base.mesh = base_mesh
	base.position = Vector3(0, Caster.HEIGHT + 0.0125, 0)
	base.material_override = Materials.chassis()
	deck_trolley.add_part(base)
	var shelf := MeshInstance3D.new()
	var shelf_mesh := BoxMesh.new()
	shelf_mesh.size = Vector3(0.56, 0.04, 0.42)
	shelf.mesh = shelf_mesh
	shelf.position = Vector3(0, 0.86, 0)
	shelf.material_override = Materials.chassis()
	deck_trolley.add_part(shelf)
	var post_bottom := Caster.HEIGHT + 0.025
	for dx in [-0.22, 0.22]:
		for dz in [-0.16, 0.16]:
			var post := MeshInstance3D.new()
			var post_mesh := BoxMesh.new()
			post_mesh.size = Vector3(0.03, 0.84 - post_bottom, 0.03)
			post.mesh = post_mesh
			post.position = Vector3(dx, (0.84 + post_bottom) * 0.5, dz)
			post.material_override = Materials.brushed_metal()
			deck_trolley.add_part(post)
	deck_trolley.add_corner_casters()

	# A plinth under the rack. A floor-standing rack puts its lowest unit at ankle height; every
	# control room that has one has it up on something -- and here the something has wheels,
	# because a rack of outboard is the piece of a studio people actually push about.
	rack_trolley = _trolley("RackTrolley", &"rack", Vector3(-1.18, 0, -0.42), 38.0)
	rack_trolley.footprint_centre = Vector2(0, -0.15)
	rack_trolley.footprint_half = Vector2(0.30, 0.17)
	# Heavier than anything else on the floor. It is a cabinet full of steel.
	rack_trolley.follow = 7.5
	var plinth := MeshInstance3D.new()
	var plinth_mesh := BoxMesh.new()
	plinth_mesh.size = Vector3(0.60, 0.30 - Caster.HEIGHT, 0.34)
	plinth.mesh = plinth_mesh
	plinth.position = Vector3(0, (0.30 + Caster.HEIGHT) * 0.5, -0.15)
	plinth.material_override = Materials.chassis()
	rack_trolley.add_part(plinth)
	rack_trolley.add_corner_casters(0.05)

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
	# furnished out of six looks like a kit. The feet are on casters, like a whiteboard's.
	timeline_stand = _trolley("TimelineStand", &"timeline_stand",
			Vector3(0, 0, TIMELINE_STAND_Z), 0.0)
	timeline_stand.footprint_half = Vector2(0.41, 0.11)
	var foot_top := Caster.HEIGHT + 0.022
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.035, TIMELINE_STAND_TOP - foot_top, 0.05)
		leg.mesh = leg_mesh
		leg.position = Vector3(side * 0.36, (TIMELINE_STAND_TOP + foot_top) * 0.5, 0)
		leg.material_override = Materials.chassis()
		timeline_stand.add_part(leg)

		# A foot, because a 35mm post standing on a floor is a post that fell over a moment ago.
		var foot := MeshInstance3D.new()
		var foot_mesh := BoxMesh.new()
		foot_mesh.size = Vector3(0.10, 0.022, 0.22)
		foot.mesh = foot_mesh
		foot.position = Vector3(side * 0.36, Caster.HEIGHT + 0.011, 0)
		foot.material_override = Materials.chassis()
		timeline_stand.add_part(foot)
		for end in [-0.075, 0.075]:
			timeline_stand.add_caster(Vector2(side * 0.36, end))

	var crossbar := MeshInstance3D.new()
	var crossbar_mesh := BoxMesh.new()
	crossbar_mesh.size = Vector3(0.79, 0.028, 0.09)
	crossbar.mesh = crossbar_mesh
	# Two millimetres under the timeline's scrub rail, which otherwise sat a fifth of a
	# millimetre off the bar's top face -- near enough to share its depth.
	crossbar.position = Vector3(0, TIMELINE_STAND_TOP + 0.012, 0)
	crossbar.material_override = Materials.brushed_metal()
	timeline_stand.add_part(crossbar)


## The console does not roll. It is the desk the room is arranged around and the one thing in
## it the mix position is measured from, so it is a fixture: solid, and in the way.
##
## Measured from its home, not its node, because a summoned desk is at the mix position and
## the place it will come back to still has to be kept clear.
func _desk_footprint() -> Array:
	if console == null or mount == null or mount.mode_of(&"console") != Presentation.Mode.STUDIO:
		return []
	var home := focus.home_of(&"console") if focus != null and focus.holds(&"console") \
			else console.transform
	var box := console.content_aabb()
	if box.size.x <= 0.0:
		return []
	var flat := home * box
	# Down to the floor and out to the toe of the carcass: the panel is what is measured, and
	# the desk under it is what a trolley actually runs into.
	flat = flat.merge(AABB(Vector3(flat.position.x, 0.0, flat.position.z), Vector3(flat.size.x, 0.01, 0.0)))
	return [FloorPlan.footprint_of_box(flat)]


## A piece of furniture that can be pushed around the floor, standing where the layout puts it
## -- or where this participant last left it.
func _trolley(of_name: String, id: StringName, at: Vector3, heading_degrees: float) -> Trolley:
	var piece := Trolley.new()
	piece.name = of_name
	piece.piece_id = id
	piece.floor_plan = floor_plan
	piece.position = at
	piece.rotation_degrees = Vector3(0, heading_degrees, 0)
	_authored_floor[id] = piece.transform
	var key := StringName("floor/%s" % id)
	if Session.layout != null and Session.layout.has_transform(key, Presentation.Mode.STUDIO):
		piece.transform = Session.layout.transform_for(key, Presentation.Mode.STUDIO, piece.transform)
	piece.settled.connect(_on_trolley_settled.bind(piece))
	piece.moved.connect(func() -> void: _looms_dirty = true)
	studio_set.add_child(piece)
	floor_plan.add_piece(piece)
	return piece


func _on_trolley_settled(piece: Trolley) -> void:
	if Session.layout == null:
		return
	Session.layout.set_transform(StringName("floor/%s" % piece.piece_id),
			Presentation.Mode.STUDIO, piece.transform)
	Session.layout.save()
	_looms_dirty = true


## The trolley a surface rides on, told how to move that surface's HOME.
##
## Not simply "move the node". A surface on a trolley may be somewhere else entirely when its
## stand is pushed: summoned to the mix position by focus, or sitting on a monitor in SCREEN
## mode. In both cases the stand still moves, and the surface must come back to where the stand
## now is -- so what rides is the surface's studio placement, and the node only moves with it
## when the node is actually standing on the trolley.
func _ride(piece: Trolley, surface: Surface) -> void:
	var id := surface.surface_id
	var standing := func() -> bool:
		return mount.mode_of(id) == Presentation.Mode.STUDIO and surface.get_parent() == studio_set
	piece.riders.append({
		"get": func() -> Transform3D:
			if focus != null and focus.holds(id):
				return focus.home_of(id)
			if standing.call():
				return surface.transform
			return mount.studio_home(id),
		"set": func(xform: Transform3D, settled_now: bool) -> void:
			if focus != null and focus.holds(id):
				focus.rehome(id, xform)
			elif standing.call():
				surface.transform = xform
			# Nothing saved: a seated surface's place is its stand's, and the stand saves
			# itself. See SurfaceMount.seats.
			pass,
	})
	var offset: Transform3D = _authored_floor[piece.piece_id].affine_inverse() * mount.authored_of(id)
	_seated_on[id] = [piece, offset]
	mount.seat(id, func() -> Transform3D: return piece.transform * offset)


## A seated surface put down by its own handle: roll its stand to where that puts it.
func _reseat(id: StringName, put: Transform3D) -> void:
	if not _seated_on.has(id):
		return
	var piece: Trolley = _seated_on[id][0]
	var under: Transform3D = put * (_seated_on[id][1] as Transform3D).affine_inverse()
	var ahead := under.basis.z
	piece.place(Vector2(under.origin.x, under.origin.z), atan2(ahead.x, ahead.z))


func _build_anchors() -> void:
	# The head and the hands differ by medium; everything downstream of them does not. That is
	# the point of putting screen_stage on whichever camera exists rather than on the desktop
	# one: a surface in SCREEN mode is a panel in front of your face whether your face is behind
	# a monitor or inside a headset.
	var head: Node3D
	if medium == Presentation.Medium.SCREEN:
		camera = Camera3D.new()
		camera.fov = ROOM_FOV

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

	# The frame a person's own gear sits in, as distinct from the room's. Parented to the studio
	# rather than the head: it follows the head itself, with a deadzone, which is the whole
	# reason it exists. See body_frame.gd.
	body = BodyFrame.new()
	body.name = "BodyFrame"
	add_child(body)
	if medium == Presentation.Medium.SCREEN:
		# On a monitor the camera is NOT a head, and pretending it is makes people ill. The
		# orbit camera swings on a two-metre boom; letting the body take its position meant a
		# mouse drag carried the console bodily around the room on the end of that boom,
		# through the furniture, while the mixer stood still. A drag on a screen is a LOOK.
		#
		# So the body is a mix position instead: a fixed standing spot in the room at eye
		# height, facing the way the room faces. Summoned gear lands in front of it and stays
		# there, and the camera is free to fly around and look at it from anywhere. The gear
		# is still placed from a body -- it is just not a body that chases the lens.
		# In FRONT of the desk, not on top of it. The first version stood the mixer at the room
		# origin, which is where the console's own carcass is, so every summoned surface landed
		# inside the furniture and the render came back with a table sawn through the middle of
		# a mixing desk. A mix position is a place you could actually stand.
		body.position = Vector3(0, ergonomics.eye_height, MIX_POSITION_Z)
	else:
		# In AR and VR it really is a head, and following it is the whole point. See
		# body_frame.gd for the deadzone that keeps a glance from dragging the room.
		body.head = head

	# What a surface may assume it will be seen through. On a monitor that is the seated lens;
	# in a headset it is the visor, which is far wider, and sizing gear to a 54-degree crop
	# there would stack a patchbay into four units that would have fitted in one.
	ergonomics.seated_fov = SEATED_FOV if medium == Presentation.Medium.SCREEN else HEADSET_FOV
	_follow_viewport_shape()
	var view := get_viewport()
	if view != null and not view.size_changed.is_connected(_follow_viewport_shape):
		view.size_changed.connect(_follow_viewport_shape)

	# A light that travels with the person. Summoned gear leaves the room's lamps behind -- the
	# first rack pulled to arm's length arrived in total darkness, which is both useless and a
	# fair description of what body-relative content is: not in the room any more. A headlamp
	# would flatten everything it hit, so this sits up and to the working side, which is where
	# the lamp on a real desk goes and for the same reason.
	var work_light := OmniLight3D.new()
	work_light.name = "WorkLight"
	work_light.position = Vector3(0.42 * signf(ergonomics.handedness), 0.30, 0.10)
	work_light.light_color = Color(1.0, 0.95, 0.88)
	work_light.light_energy = 3.2
	work_light.omni_range = 2.4
	work_light.shadow_enabled = false
	body.add_child(work_light)

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

	focus = FocusRig.new()
	focus.name = "FocusRig"
	focus.body = body
	focus.ergonomics = ergonomics
	focus.surfaces = [console, patchbay, rack, deck, timeline]
	focus.show_halo = medium != Presentation.Medium.SCREEN
	focus.visits = medium == Presentation.Medium.SCREEN
	# Re-seat once the focused surface has been PLACED, which is when it finally knows both its
	# own size and where it ended up. Without this the camera is always aimed using the layout
	# the desk had before it was summoned, and a paged single-tier console is a very different
	# object from the flat 48-track plank it was a frame earlier.
	#
	# Placement, not rebuilding. Both this and the rig itself used to listen to `rebuilt`, and
	# which of them ran first was decided by connection order; this one won, so the camera sat
	# down facing where the gear had been a moment before the rig moved it, and nothing fired
	# again to correct it. `--focus rack` came back as a photograph of the floor.
	focus.placed.connect(_sit_down)
	# Release too, whoever releases: a key, a hand, a remote participant handing focus back.
	# Only the keyboard path used to re-seat, so anything else left you standing at the rack.
	focus.focus_changed.connect(func(id: StringName) -> void:
		if id == &"" and focus.visits:
			_sit_down())
	focus.room = studio_set
	focus.move = _glide
	add_child(focus)
	if mount != null:
		mount.held = focus.holds

	# What rides on what. After the rig, because a surface that is summoned rides by its home,
	# and the rig is what holds that.
	if floor_plan != null:
		mount.reseat = _reseat
		_ride(rack_trolley, rack)
		_ride(deck_trolley, deck)
		_ride(timeline_stand, timeline)

	# After the gear, because a loom is measured off the transforms of the two things it joins.
	# Rebuilt with the bay, because the bay's width is the track count and the glands are spaced
	# across it: a session that gains tracks moves where its own looms land.
	patchbay.rebuilt.connect(refresh_looms)
	refresh_looms()


## A stand under every practical.
##
## A tripod floor lamp rather than a pendant, and that is forced rather than chosen: this room
## has three walls and no ceiling, so there is nothing for a hanging fixture to hang from, and a
## stem disappearing into open sky above the wall line would be worse than no fixture at all.
##
## The shade is a cone open at the bottom with an emissive disc inside it, so the lamp reads as
## ON. Nothing about the geometry emits light -- the OmniLight does that, from the middle of the
## shade -- and that division is why the head sits where the light is rather than the other way
## round. Move a practical in the table and its stand follows; there is a test on the pairing,
## because the failure mode is an invisible light source, which is the thing this fixes.
func _build_lamp_stands() -> void:
	for spec in PRACTICALS:
		var at: Vector3 = spec[0]
		var tint: Color = spec[1]
		var number := PRACTICALS.find(spec) + 1
		var stand := _trolley("LampStand", StringName("lamp_%d" % number),
				Vector3(at.x, 0.0, at.z), 0.0)
		stand.add_to_group(&"lamp_stand")
		stand.rolls = false
		stand.follow = 15.0
		stand.footprint_half = Vector2(0.15, 0.15)
		# The light goes with its lamp. Reparented rather than built here, because an AR
		# participant gets the lights with no stands at all -- see _build_environment.
		if number - 1 < _lamps.size():
			_lamps[number - 1].reparent(stand, true)

		var base := MeshInstance3D.new()
		var base_mesh := CylinderMesh.new()
		base_mesh.top_radius = 0.085
		base_mesh.bottom_radius = 0.150
		base_mesh.height = 0.032
		base_mesh.radial_segments = 16
		base.mesh = base_mesh
		base.position = Vector3(0, 0.016, 0)
		base.material_override = Materials.chassis()
		stand.add_part(base)

		# Up to the middle of the shade, so the pole is hidden by the head rather than stopping
		# just short of it and leaving a gap you can see the wall through.
		var pole := MeshInstance3D.new()
		var pole_mesh := CylinderMesh.new()
		pole_mesh.top_radius = 0.0145
		pole_mesh.bottom_radius = 0.0205
		# Rising out of the base rather than standing on the floor inside it, where its foot and
		# the base's underside were one plane.
		pole_mesh.height = at.y - 0.02
		pole_mesh.radial_segments = 10
		pole.mesh = pole_mesh
		pole.position = Vector3(0, (at.y + 0.02) * 0.5, 0)
		pole.material_override = Materials.brushed_metal()
		stand.add_part(pole)

		var shade := MeshInstance3D.new()
		shade.name = "Shade"
		var shade_mesh := CylinderMesh.new()
		shade_mesh.top_radius = LAMP_SHADE_RADIUS * 0.42
		shade_mesh.bottom_radius = LAMP_SHADE_RADIUS
		shade_mesh.height = LAMP_SHADE_HEIGHT
		shade_mesh.radial_segments = 20
		shade_mesh.cap_bottom = false
		shade.mesh = shade_mesh
		shade.position = Vector3(0, at.y, 0)
		shade.material_override = Materials.cap_plastic(Color(0.17, 0.165, 0.155))
		stand.add_part(shade)

		# The glowing bit. Above the shade's lower rim so the cone shields it from straight on,
		# which is what stops a lamp pointing down reading as a bare bulb from across the room.
		var glow := MeshInstance3D.new()
		var glow_mesh := CylinderMesh.new()
		glow_mesh.top_radius = LAMP_SHADE_RADIUS * 0.80
		glow_mesh.bottom_radius = LAMP_SHADE_RADIUS * 0.80
		glow_mesh.height = 0.004
		glow_mesh.radial_segments = 20
		glow.mesh = glow_mesh
		glow.position = Vector3(0, at.y - LAMP_SHADE_HEIGHT * 0.28, 0)
		glow.material_override = Materials.led(tint, true)
		stand.add_part(glow, false)


# --- looms --------------------------------------------------------------------------------

## The permanent runs from each machine to the back of the patchbay. See hardware/gear_loom.gd
## for what they are claiming.
##
## Skipped for any machine not standing in the virtual set. A surface in SCREEN mode is a panel
## riding in front of someone's face, and a two-metre cable from a panel in the viewer's head
## down to the floor of a room they may not even be rendering is worse than no cable: it moves
## with them, so it reads as the room being dragged around rather than as a loose cable.
func refresh_looms() -> void:
	for loom in _looms:
		if is_instance_valid(loom):
			loom.queue_free()
	_looms.clear()
	if medium == Presentation.Medium.AR or studio_set == null or patchbay == null:
		return
	if patchbay.get_parent() != studio_set:
		return
	# A bay with no jacks has no width, so every landing fraction resolves to the same point and
	# the three looms would stack into one. An empty session gets no looms.
	if patchbay.loom_entry(-1.0).is_equal_approx(patchbay.loom_entry(1.0)):
		return

	for run in LOOM_RUNS:
		var machine: Node3D = get(run[0])
		if machine == null or machine.get_parent() != studio_set:
			continue
		var from_at: Vector3 = machine.transform * (run[1] as Vector3)
		var from_dir: Vector3 = (machine.transform.basis * (run[2] as Vector3)).normalized()
		var entry: Vector3 = patchbay.loom_entry(run[3])
		var to_at: Vector3 = patchbay.transform * entry
		# Into the panel, which is the bay's own -Z however the bay is tilted. Negated because a
		# loom's axis is the direction it RUNS AWAY along, not the direction it points in.
		var to_dir: Vector3 = (patchbay.transform.basis * Vector3.BACK).normalized()
		var via: Vector3 = run[4]
		# The floor point was written against where the authored layout stood the machine. A
		# machine that has been wheeled somewhere else takes its run of trunking with it.
		var stand := _stand_of(String(run[0]))
		if stand != null and _authored_floor.has(stand.piece_id):
			via = stand.transform * (_authored_floor[stand.piece_id] as Transform3D).affine_inverse() * via
		var loom := GearLoom.create(from_at, from_dir, to_at, to_dir, via, hash(run[0]))
		loom.on_floor = run[5]
		loom.name = "Loom_%s" % run[0]
		studio_set.add_child(loom)
		_looms.append(loom)


func _stand_of(machine: String) -> Trolley:
	match machine:
		"rack": return rack_trolley
		"deck": return deck_trolley
	return null


## Looms follow furniture that is being pushed, but not every physics frame: a loom is a swept
## mesh, and rebuilding three of them sixty times a second for a rack moving two centimetres is
## the furniture costing more than the console.
func _refresh_looms_if_moved(delta: float) -> void:
	_loom_clock += delta
	if _looms_dirty and _loom_clock >= 0.05:
		_looms_dirty = false
		_loom_clock = 0.0
		refresh_looms()


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
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			# Walk the gear past you one piece at a time, and off either end to put it back.
			# Shift goes the other way. One key, no modifier needed to start, and the exit is
			# where you would find it by accident.
			KEY_F:
				focus.cycle(-1 if event.shift_pressed else 1)
				_sit_down()
			# The other half of the desk. A console pages by default, because twelve strips
			# you can face beats forty-eight you have to turn your head through -- but a
			# mix is sometimes a thing you want to see all of at once, and then the tiers
			# are worth the neck. One key, and it is the one the desk is named after.
			KEY_E:
				_toggle_expanded()
			KEY_G:
				_toggle_summoning()
			# Somewhere else to stand. The setup comes along; only the world changes.
			KEY_V:
				cycle_venue()
			KEY_ESCAPE:
				focus.release()
				_sit_down()
			# Comfort and eyesight, live, because the only way anyone finds the right value is
			# by changing it while looking at the thing.
			KEY_EQUAL, KEY_KP_ADD:
				_set_text_scale(ergonomics.text_scale * 1.15)
			KEY_MINUS, KEY_KP_SUBTRACT:
				_set_text_scale(ergonomics.text_scale / 1.15)
			KEY_0:
				_set_text_scale(1.0)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_distance = maxf(0.4, _orbit_distance - 0.12)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_distance = minf(6.0, _orbit_distance + 0.12)
			_update_camera()


func _process(delta: float) -> void:
	_refresh_looms_if_moved(delta)
	if venue != null and DAW.state != null:
		venue.pulse(maxf(DAW.state.master.vu_l, DAW.state.master.vu_r))
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


## Move a surface to where the focus rig wants it, over time rather than instantly.
##
## The glide is not decoration. Something large arriving next to your face with no transit is
## disorienting and leaves you unsure what you are now looking at; watching it travel tells you
## which thing came and where it came from. It is also the first thing someone prone to motion
## sickness needs to turn off, which is why the duration is a property of the person.
func _glide(surface: Surface, parent: Node3D, local: Transform3D) -> void:
	# Reparented first, keeping the world pose, so the travel is computed inside the frame it is
	# travelling to. Reparenting at the END would teleport the surface on arrival; reparenting
	# without keeping the pose teleports it on departure.
	if parent != null and surface.get_parent() != parent:
		surface.reparent(parent, true)
	var seconds := 0.42 * clampf(ergonomics.motion_scale, 0.0, 2.0)
	if seconds <= 0.01:
		surface.transform = local
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(surface, "transform", local, seconds)


## Lettering is sized once, when a label is built, and then enforced by the rendering server.
## So changing whose eyes it is for means rebuilding the labels -- which is cheap, and is the
## honest consequence of the visibility range being server-side rather than per-frame script.
func _set_text_scale(to: float) -> void:
	ergonomics.text_scale = clampf(to, 0.4, 4.0)
	Ergonomics.current = ergonomics
	for node in find_children("*", "Node3D", true, false):
		if node is Surface:
			(node as Surface).mark_dirty()
	if focus != null and focus.is_focused():
		focus.focus(focus.focused_id)


## Put the screen camera where the mixer is standing, looking at whatever they just summoned.
##
## Focusing moves the gear to the body. On a monitor that is only half the gesture: the body is
## a fixed mix position, so without this you summon a console to a spot in the room and then go
## on watching it from wherever you happened to be orbiting -- usually behind and above it,
## where a wrapped desk reads as four tiers of scaffolding rather than as a desk. The whole
## point of an arc is that it is right from ONE place.
##
## A no-op in AR and VR, where the camera is a head and moving it is not ours to do.
## Swap the focused desk between its paged bank and its full width.
##
## Only the console has two sizes, so this does nothing anywhere else rather than inventing a
## meaning for "expanded" on a tape deck. The re-seat comes free: the desk emits `rebuilt`, and
## the camera is already listening for that.
func _toggle_expanded() -> void:
	if focus == null or not focus.is_focused():
		return
	for surface in focus.surfaces:
		if surface.surface_id != focus.focused_id:
			continue
		var console := surface as ConsoleSurface
		if console != null:
			console.expanded = not console.expanded
		return


## Keep the rig's idea of the frame in step with the actual window.
##
## Resizing changes how much gear fits in view, and gear placed for the old shape is cropped by
## the new one. Cheap enough to redo on every resize: it sets one number and marks the surfaces,
## and a person dragging a window edge is not in the middle of anything precise.
func _follow_viewport_shape() -> void:
	var view := get_viewport()
	if view == null:
		return
	var size := view.get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var aspect := size.x / size.y
	if is_equal_approx(aspect, ergonomics.view_aspect):
		return
	ergonomics.view_aspect = aspect
	if focus != null:
		for surface in focus.surfaces:
			surface.mark_dirty()


func _sit_down() -> void:
	if camera == null or body == null or medium != Presentation.Medium.SCREEN:
		return
	if focus != null and focus.visits:
		_walk_to_seat()
		return
	# Aimed at where focused gear GOES, not at where the focused surface currently is. Asking
	# the surface was the first version, and it reads its bounds a frame too early -- focus
	# moves the surface immediately but the rebuild that gives it its shape happens on the next
	# _process, so the camera was aimed using the previous layout's box and ended up on the
	# floor looking at a lamp. This point is a property of the body, which is already final.
	var eye := body.global_position
	var drop := deg_to_rad(ergonomics.gaze_down)
	var ahead := Vector3(0, -sin(drop), -cos(drop)) * ergonomics.working_distance()
	var at: Vector3 = eye + body.global_transform.basis * ahead
	# Aimed at the focused surface's own middle once it HAS one. Reading its bounds is only
	# safe after the rebuild -- focus moves a surface immediately but the rebuild that gives it
	# its shape happens on the next _process -- so this takes the measurement when it is real
	# and falls back to the body's working point when it is not.
	if focus != null and focus.is_focused():
		for surface in focus.surfaces:
			if surface.surface_id == focus.focused_id:
				var box := surface.content_aabb()
				if box.size.y > 0.01:
					# Aimed at where the surface is GOING, not where it currently is. Gear
					# glides to the mix position over a few hundred milliseconds, and the
					# camera is seated the instant placement is decided -- reading the live
					# transform aims it at a console still halfway across the room, and
					# nothing fires afterwards to correct it once the tween lands. This is
					# why `--focus rack` kept coming back as a photograph of the floor even
					# after the signal race behind it was fixed: two separate bugs with one
					# symptom, and fixing the first changed the render not at all.
					#
					# Dead centre of the box, not a quarter up it. The lift was there to
					# stop the camera staring into the desk's underside, and the underside
					# was really the carcass being counted as content, which it no longer is.
					var target := body.global_transform * focus.placement(surface, 0)
					at = target * box.get_center()
	var back := eye - at
	# Through frame() rather than by assigning the four orbit fields, which is what the version
	# before that did: those values are only read when something applies them, so setting them
	# and stopping leaves the camera exactly where it was. The render came back identical twice
	# and both times read as a placement bug rather than a call that never reached the camera.
	#
	# Negative pitch, because the offset is built with Basis(RIGHT, pitch), which sends +pitch
	# DOWN -- the eye is above the desk, so it wants the sign that lifts it.
	# A longer lens while you are working at something. The default 75-degree field is right
	# for walking around a room and wrong for standing over a desk: at half a metre it bows the
	# arc outward at the edges and spends most of the frame on everything that is not the desk.
	# Nobody photographs a console on a wide angle either, and for the same reason.
	camera.fov = SEATED_FOV if focus.is_focused() else ROOM_FOV
	frame(at, back.length(), atan2(back.x, back.z),
			-atan2(back.y, Vector2(back.x, back.z).length()))


## Where the mix position stands when nothing is being visited.
func _home_seat() -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(0, ergonomics.eye_height, MIX_POSITION_Z))


## Visiting: walk the mix position over to the focused gear and look at it from there.
##
## The body goes, not just the lens, because the body is what carries the work light -- and
## because "where I am standing" is what release has to undo. A surface that is not standing in
## the room (a timeline on the monitor) has no seat; focusing it leaves you where you are.
func _walk_to_seat() -> void:
	var seat := _home_seat()
	var look_at := Vector3.ZERO
	var target: Surface = null
	if focus.is_focused():
		for surface in focus.surfaces:
			if surface.surface_id == focus.focused_id:
				target = surface
	if target != null and target.get_parent() == studio_set:
		var box := target.content_aabb()
		if box.size.y > 0.01:
			seat = focus.seat_for(target)
			# Inside the room and at a height a person's eyes can be at. A rack's bottom unit
			# asks for a seat on the floor; nobody mixes lying down.
			var bounds := floor_plan.bounds if floor_plan != null \
					else Rect2(-ROOM_WIDTH * 0.5, -2.15, ROOM_WIDTH, ROOM_DEPTH)
			seat.origin = Vector3(
					clampf(seat.origin.x, bounds.position.x + 0.2, bounds.end.x - 0.2),
					clampf(seat.origin.y, 0.95, 1.95),
					clampf(seat.origin.z, bounds.position.y + 0.2, bounds.end.y + 0.6))
			look_at = target.global_transform * box.get_center()
	elif target != null:
		return
	_stand_down_screen(target != null)
	if look_at == Vector3.ZERO:
		var drop := deg_to_rad(ergonomics.gaze_down)
		look_at = seat * (Vector3(0, -sin(drop), -cos(drop)) * ergonomics.working_distance())
	camera.fov = SEATED_FOV if target != null else ROOM_FOV
	var back := seat.origin - look_at
	var to := [look_at, back.length(), atan2(back.x, back.z),
			-atan2(back.y, Vector2(back.x, back.z).length())]
	var seconds := 0.55 * clampf(ergonomics.motion_scale, 0.0, 2.0)
	if seconds <= 0.01 or not is_inside_tree():
		body.transform = seat
		frame(to[0], to[1], to[2], to[3])
		return
	# Both at once, on one curve. A body that arrived before its camera would leave the work
	# light lighting the gear from an empty spot for half a second; a camera that arrived first
	# would see the light swing in after it.
	var body_from := body.transform
	var cam_from := camera.global_transform
	frame(to[0], to[1], to[2], to[3])
	var cam_to := camera.global_transform
	camera.global_transform = cam_from
	if _walk != null and _walk.is_valid():
		_walk.kill()
	_walk = create_tween()
	_walk.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_walk.tween_method(func(t: float) -> void:
		body.transform = body_from.interpolate_with(seat, t)
		camera.global_transform = cam_from.interpolate_with(cam_to, t), 0.0, 1.0, seconds)


var _walk: Tween


## The monitor's own panels step aside while you are over at a piece of gear.
##
## A surface on the screen stage hangs off the lens, so walking to the console carries the
## timeline with you and holds it a hand's width in front of the desk you walked over to see --
## the first honest visit render was a timeline with a console somewhere behind it. Summoning
## never showed this because it pulled the timeline into the arc with everything else.
##
## Disabled as well as hidden: a hidden ControlAffordance is still in the physics space, and
## a click aimed at a fader would land on the invisible clip lane in front of it.
func _stand_down_screen(away: bool) -> void:
	if screen_stage == null:
		return
	screen_stage.visible = not away
	screen_stage.process_mode = Node.PROCESS_MODE_DISABLED if away \
			else Node.PROCESS_MODE_INHERIT


## Visit the gear, or have it brought. Visiting is the monitor's default; bringing is still
## the right answer for some work -- a patchbay you want flat in front of you -- and is how a
## headset works, so it is one key away rather than gone.
func _toggle_summoning() -> void:
	var was := focus.focused_id
	focus.release()
	focus.visits = not focus.visits
	if not focus.visits:
		# Summoned gear lands in front of the mix position, so the mix position has to be back
		# where it stands before anything is summoned to it.
		_stand_down_screen(false)
		body.transform = _home_seat()
	if was != &"":
		focus.focus(was)
	_sit_down()


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
