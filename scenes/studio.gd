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

## The walls of the control room: the working footprint. Each venue builds the rest of its
## world -- and the activity zones behind the mix position -- around this (see Venue.ZONES).
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
## The lamps in the room: where the light comes from, what colour, and how hard.
##
## One table, read twice -- once by the environment to make the lights and once by the furniture
## to make the stands under them. They were two floating OmniLights with nothing to come out of,
## which is the lighting version of the patchbay wired to nothing: a room lit by sources you
## cannot see. The third is new, and it is there because the measurement said so -- the rack's
## faceplate read 13.8 against the console's 22.1, and the floor at its foot 9.1 against 29.5.
const PRACTICALS: Array = [
	[Vector3(-2.05, 1.76, 1.25), Color(1.0, 0.78, 0.52), 6.0],
	# Clear of the deck trolley from the seat: behind it, it was a lamp you could not take hold of.
	# Forward on the right since the patch stand took that side of the room: anywhere behind it
	# the stand was in the way from the seat.
	[Vector3(2.30, 1.70, 0.95), Color(0.6, 0.78, 1.0), 5.5],
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
## The patch stand: the bay's own cabinet, out to the right of the desk past the deck, turned to
## face the mix position. Its own station rather than a strip on a meter bridge between the timeline and
## the console, where it was a hand's width tall and read as part of both. Where on the stand the
## bay's top edge is, and how far the cabinet under it reaches back.
const PATCH_STAND_AT := Vector3(SessionLayout.PATCH_AT.x, 0, SessionLayout.PATCH_AT.y)
const PATCH_STAND_HEADING := SessionLayout.PATCH_HEADING
const PATCH_BAY_TOP := 1.78
const PATCH_BAY_FRONT := 0.03
const PATCH_CABINET_DEPTH := 0.12

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
var presence: Presence
## This participant's body. Everything placed for a person is placed from it, and it is one
## object rather than a scattering of constants precisely so there is somewhere to change it.
var ergonomics := Ergonomics.new()
## Where a height chosen in the room is remembered. Tests point it somewhere of their own.
var body_path := Ergonomics.HEIGHT_PATH

var console: ConsoleSurface
var rack: RackSurface
## The things people pick up and carry. Null in AR, which has a real room's things in it.
var items: ItemRoom
## What the mic in a hand here has done to a track, to be undone when it leaves the hand.
var mic_arm := MicArm.new()
## Whether the headphones are on a head here, as Ears was last told.
var _heard_phones := false
## The personal mix of whoever is at this machine: the tablet's receivers (docs/items_loop.md).
var personal := PersonalMix.new()
## Other players' keys, played here for the personal mix's plugs in them.
var their_keys: TheirKeys
## Other players' monitors, rebuilt here in time for the personal mix's plugs in them.
var their_monitor: TheirMonitor
## The hand percussion played here, taken down onto the armed track while recording.
var hit_recorder: HitRecorder
## The computer keyboard as the keytar's keys, while it is in this player's hands (KeytarItem).
var keytar_keys: KeyCatcher
## Whether the keytar is in this player's hands, as last seen: for GuestMidi to play it.
var _keytar_mine := false
## Who is ON AIR, by peer id: whose monitor anyone may plug into. The room's, like `patches`.
var on_air: Array = []
## Who has a plug in which SEND socket: {peer id: [socket name per receiver, "" in the tray]}.
## The room's, so the host's: everyone sees everyone's plugs. Whoever is at this machine hears
## their own row (`personal`).
var patches: Dictionary = {}
## Plugins torn off the rack, each on its own stand: {stand id: [Trolley, PluginTablet]}.
var tablets: Dictionary = {}
## While the host's room is being put up here: a stand set down by it is not news to send back.
var _applying_room := false
var _room_publish_due := false
## Whether what stands here is the host's room rather than this participant's own.
var _showing_hosts_room := false
## A guest's asks the host has not answered yet: {seq, verb, args, id}. See apply_room.
var _predictions: Array = []
var _motion_sent_msec := 0
## Guest: how many stands it has put out on its own say-so, for naming them until the host does.
var _predicted_tablets := 0
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
## stood under the bay once, when the bay rode a meter bridge over it; now the bay has its own
## stand, every run takes the floor behind the desk.
const LOOM_RUNS: Array = [
	["console", Vector3(0, 0.02, -0.19), Vector3(0, 0.6, -1.0), 0.0,
			Vector3(0.30, 0, -0.72), true],
	["rack", Vector3(0, 0.07, -0.29), Vector3(0, -0.18, -1.0), -0.74,
			Vector3(-0.70, 0, -0.72), true],
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
var patch_stand: Trolley
## Surface id -> [the trolley it stands on, where on that trolley].
var _seated_on := {}
var _lamps: Array[OmniLight3D] = []
## {piece_id: Transform3D} -- where the authored layout stood each piece, for the things that
## were written against it: the floor points the looms run through.
var _authored_floor: Dictionary = {}
## How wide the room is right now. Starts at the authored width and grows with the desk; see
## SessionLayout.
var room_width := ROOM_WIDTH
## True while the room is moving furniture to fit the session, so those moves are not saved as
## if this participant had pushed everything.
var _fitting := false
var _patch_cabinet: MeshInstance3D
var _patch_cheeks: Array[MeshInstance3D] = []

## Where a person stands to work, on a monitor. Far enough forward of the console's home at
## z = 0.1 that gear summoned to arm's length lands on the desk rather than through it.
const MIX_POSITION_Z := 0.66
## Where the opening view looks: (metres ahead of the mix position, height). Where a standing
## eye's half-radian glance lands on the console, kept for every other eye height.
const DESK_GAZE := Vector2(0.96, 1.096)

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

## You, on foot. The default way to be in the room on a monitor; see walker.gd.
var walker: Walker
## The orbit camera instead of the walker: floats, flies, passes through things. For arranging a
## room and for photographing it. N toggles it.
var god_mode := false
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
		if Session.layout != null:
			set_venue(Session.layout.venue, false, Session.layout.venue_variant)
		else:
			set_venue(Venue.IDS[0], false)
	_build_anchors()
	if medium != Presentation.Medium.AR:
		_build_furniture()
	_build_surfaces()
	if camera != null:
		_build_walker()
		_update_camera()
	if medium != Presentation.Medium.AR:
		_build_items()
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
## What rides in front of your face in screen mode is seen, never reflected: in a mirror it
## would be the backs of the panels, over your own face. Whatever moves back into the room is
## reflected again. See core/venues/mirror.gd.
func _keep_out_of_mirrors(node: Node) -> void:
	var drawn := node as VisualInstance3D
	if drawn == null or screen_stage == null or not is_instance_valid(screen_stage):
		return
	if screen_stage.is_ancestor_of(drawn):
		if drawn.layers == 1:
			drawn.layers = Mirror.NOT_REFLECTED
			drawn.set_meta(&"kept_out_of_mirrors", true)
	elif drawn.has_meta(&"kept_out_of_mirrors"):
		drawn.layers = 1
		drawn.remove_meta(&"kept_out_of_mirrors")


func _exit_tree() -> void:
	mic_arm.let_go()
	Ears.listen(false)
	if DAW.backend is GodotBackend:
		(DAW.backend as GodotBackend).set_cues([])
	if get_tree().node_added.is_connected(_keep_out_of_mirrors):
		get_tree().node_added.disconnect(_keep_out_of_mirrors)


func set_venue(id: StringName, persist := true, variant := 0) -> void:
	if medium == Presentation.Medium.AR:
		return
	if not Venue.is_known(id):
		id = Venue.IDS[0]
	if venue != null:
		remove_child(venue)
		venue.queue_free()
	venue = Venue.make(id, variant)
	venue.name = "Venue"
	venue.rich = rich_rendering()
	venue.room_width = room_width
	var env := _house_environment()
	_house_key(key_light)
	venue.dress(env, key_light)
	world_env.environment = env
	add_child(venue)
	var mirror := venue.make_mirror(env)
	venue.add_child(mirror)
	mirror.wardrobe.look = Session.local_look
	mirror.wardrobe.look_changed.connect(Session.set_look)
	for i in _lamps.size():
		if i < PRACTICALS.size():
			_lamps[i].light_color = venue.lamp_colour(i, PRACTICALS[i][1])
			_lamps[i].light_energy = venue.lamp_energy(i, PRACTICALS[i][2])
	if persist and Session.layout != null and Session.is_authority():
		Session.layout.venue = id
		Session.layout.venue_variant = venue.variant
		Session.layout.save()
	_walk_where_the_venue_lets()
	venue_changed.emit(id)
	_publish_room()


## On foot you can go where the room goes: the working footprint and, behind it, the venue's
## live room with its zones. The furniture's floor plan is still the footprint alone.
func _walkable() -> Array[Rect2]:
	var out: Array[Rect2] = [_room_bounds()]
	if venue != null:
		out.append_array(venue.rooms())
	return out


func _walk_where_the_venue_lets() -> void:
	if walker != null:
		walker.walkable = _walkable()
		walker.fixed = venue.solids() if venue != null else []
		walker.rebuild_walls()
		walker.unstick()
	if items != null and venue != null:
		items.set_spots(venue.item_spots(), _item_homes())


## Somewhere else to stand, if this is somebody's to say: the room is the host's, so a guest
## asking is told so rather than taken somewhere nobody else is.
## How tall you are, changed in the room: the eye goes there at once and the height is kept
## for next time. The gear stays where it is -- it is the room's, and you are the one who grew.
func set_body_height(height: float) -> void:
	ergonomics.set_height(height)
	Ergonomics.save_height(ergonomics.height, body_path)
	if walker != null:
		walker.standing_eye = ergonomics.eye_height
		walker.eye_height = ergonomics.eye_height
		walker._place_camera()
	if body != null and medium == Presentation.Medium.SCREEN:
		body.position.y = ergonomics.eye_height


func choose_venue(id: StringName, variant := 0) -> bool:
	if not Session.is_authority():
		Session.notice.emit("Only %s can change the venue." % Session.name_of(1))
		return false
	set_venue(id, true, variant)
	return true


## The same venue, arranged another way. The host's to choose, like the venue.
func choose_variant(variant: int) -> bool:
	return choose_venue(venue.venue_id() if venue != null else Venue.IDS[0], variant)


func cycle_venue() -> void:
	choose_venue(Venue.next_after(venue.venue_id() if venue != null else Venue.IDS[0]))


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
	floor_plan.bounds = _room_bounds()
	floor_plan.fixtures.append(_desk_footprint)
	add_child(floor_plan)

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
	# Two legs and a crossbar, deliberately the same vocabulary as the patch stand rather than
	# a new idea: a room furnished out of three kinds of part looks like a room, and one
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

	_build_patch_stand()


## The bay's own cabinet: a plinth on casters, a carcass under the panel and a cheek either side
## running up past its top, so the bay stands in a frame rather than on a post. The carcass and
## cheeks are sized to the bay once it knows how many rows it has (`_fit_stand_to_bay`).
func _build_patch_stand() -> void:
	patch_stand = _trolley("PatchStand", &"patch_stand", PATCH_STAND_AT, PATCH_STAND_HEADING)
	patch_stand.footprint_centre = Vector2(0, -0.03)
	patch_stand.footprint_half = Vector2(0.62, 0.15)
	patch_stand.follow = 9.0
	var plinth := MeshInstance3D.new()
	var plinth_mesh := BoxMesh.new()
	plinth_mesh.size = Vector3(1.20, 0.03, 0.28)
	plinth.mesh = plinth_mesh
	plinth.position = Vector3(0, Caster.HEIGHT + 0.015, -0.03)
	plinth.material_override = Materials.chassis()
	patch_stand.add_part(plinth)
	_patch_cabinet = MeshInstance3D.new()
	_patch_cabinet.name = "Cabinet"
	_patch_cabinet.mesh = BoxMesh.new()
	_patch_cabinet.material_override = Materials.chassis()
	patch_stand.add_part(_patch_cabinet)
	for side in [-1.0, 1.0]:
		var cheek := MeshInstance3D.new()
		cheek.name = "Cheek"
		cheek.mesh = BoxMesh.new()
		cheek.material_override = Materials.end_cheek()
		patch_stand.add_part(cheek)
		_patch_cheeks.append(cheek)
	patch_stand.add_corner_casters(0.06)
	_fit_stand_to_bay()


# --- plugin tablets -------------------------------------------------------------------------
#
# A plugin pulled off the rack stands on its own music stand: a weighted round foot, a pole, and
# a cradle holding the tablet tilted back at a standing reader's hands. On the floor rather than
# on the desk because the desk is the console, and a tablet propped on the faders is in the way
# of the faders; a stand can be wheeled up beside the chair, or across to the rack, or anywhere.

## The top edge of the tablet on its stand, and how far it leans back. Desk height plus a little:
## read standing, or pulled up beside the chair.
const TABLET_TOP := 1.16
const TABLET_LEAN := 28.0
const TABLET_FOOT := 0.19
## How far in front of the rack's face a pulled tablet lands, when it was not pulled anywhere
## in particular.
const TABLET_PULL := 0.6


func _on_tear_requested(track: int, fx: int, at: Vector3) -> void:
	var f := DAW.state.fx(track, fx, false)
	if f == null or f.name == "":
		return
	# Out from the rack along its facing, so a tablet pulled straight off lands in front of it
	# rather than inside it.
	var out := rack.global_basis.z.normalized()
	var landing := at + Vector3(out.x, 0, out.z).normalized() * TABLET_PULL
	var id: StringName
	if Session.is_authority():
		id = open_tablet(track, fx, f.name, Vector2(landing.x, landing.z))
	else:
		# Out at once, under a name of this guest's own, and asked for: the host's room renames
		# it when it answers, or takes it back if the host would not.
		id = _predicted_tablet(track, fx, f.name, Vector2(landing.x, landing.z))
		if id == StringName():
			return
	# On a monitor, pulling it off is asking to use it: walk up to it. In a headset you are
	# already standing where you pulled it.
	if focus != null and focus.visits:
		focus.focus(id)
		_sit_down()


## Put a plugin on a stand at `where` on the floor, facing the mix position. One stand per
## plugin: asking again for one that is already out wheels that stand over instead.
func open_tablet(track: int, fx: int, plugin_name: String, where: Vector2) -> StringName:
	for id in tablets:
		var tablet: PluginTablet = tablets[id][1]
		if tablet.track_index == track and tablet.fx_index == fx:
			(tablets[id][0] as Trolley).place(where, _facing_mix(where))
			return id
	var n := 1
	while tablets.has(StringName("tablet_%d" % n)) or (Session.layout != null \
			and Session.layout.tablets.has(StringName("tablet_%d" % n))):
		n += 1
	var id := StringName("tablet_%d" % n)
	_build_tablet(id, track, fx, plugin_name)
	(tablets[id][0] as Trolley).place(where, _facing_mix(where))
	_remember_tablets()
	_publish_room()
	return id


func _facing_mix(from: Vector2) -> float:
	var to := Vector2(0, MIX_POSITION_Z) - from
	return atan2(to.x, to.y)


func _build_tablet(id: StringName, track: int, fx: int, plugin_name: String) -> void:
	var stand := _trolley("PluginStand_%s" % id, id, Vector3(0, 0, 0.6), 0.0)
	stand.rolls = false
	stand.follow = 14.0
	stand.footprint_half = Vector2(TABLET_FOOT, TABLET_FOOT)
	var foot := MeshInstance3D.new()
	foot.name = "Foot"
	var disc := CylinderMesh.new()
	disc.top_radius = TABLET_FOOT * 0.92
	disc.bottom_radius = TABLET_FOOT
	disc.height = 0.025
	disc.radial_segments = 40
	foot.mesh = disc
	foot.position.y = 0.0125
	foot.material_override = Materials.chassis()
	stand.add_part(foot)
	var pole := MeshInstance3D.new()
	pole.name = "Pole"
	var tube := CylinderMesh.new()
	tube.top_radius = 0.012
	tube.bottom_radius = 0.016
	var pole_top := TABLET_TOP - PluginTablet.HEIGHT * cos(deg_to_rad(TABLET_LEAN)) * 0.5
	tube.height = pole_top
	tube.radial_segments = 16
	pole.mesh = tube
	pole.position = Vector3(0, pole_top * 0.5, -0.02)
	pole.material_override = Materials.brushed_metal()
	stand.add_part(pole)

	var tablet := PluginTablet.create(track, fx, plugin_name)
	tablet.surface_id = id
	# Hung from its top edge's middle, leaning back: the cradle's lip is under its bottom edge.
	var lean := Basis(Vector3.RIGHT, -deg_to_rad(TABLET_LEAN))
	tablet.transform = Transform3D(lean, Vector3(0, TABLET_TOP, 0.0)) \
			* Transform3D(Basis.IDENTITY, Vector3(0, -PluginTablet.HEIGHT * 0.5, 0))
	var lip := MeshInstance3D.new()
	lip.name = "Cradle"
	var ledge := BoxMesh.new()
	ledge.size = Vector3(PluginTablet.WIDTH * 0.8, 0.012, 0.03)
	lip.mesh = ledge
	lip.transform = tablet.transform * Transform3D(Basis.IDENTITY,
			Vector3(0, -PluginTablet.HEIGHT * 0.5 - 0.006, -0.002))
	lip.material_override = Materials.brushed_metal()
	stand.add_part(lip, false)
	stand.add_child(tablet)
	tablet.dock_requested.connect(_dock_tablet.bind(id))
	# Gear like the rest: F walks to it, and it comes up close to be worked.
	if focus != null:
		focus.surfaces.append(tablet)
		tablet.rebuilt.connect(focus._on_surface_rebuilt.bind(tablet))
	tablets[id] = [stand, tablet]


func close_tablet(id: StringName) -> void:
	if not tablets.has(id):
		return
	_take_down_tablet(id)
	if Session.layout != null and Session.is_authority():
		Session.layout.clear_transform(StringName("floor/%s" % id), Presentation.Mode.STUDIO)
	_remember_tablets()
	_publish_room()


## The stand gone from this room, and nothing remembered or told about it.
func _take_down_tablet(id: StringName) -> void:
	var stand: Trolley = tablets[id][0]
	var tablet: PluginTablet = tablets[id][1]
	if focus != null:
		if focus.focused_id == id:
			focus.release()
			_sit_down()
		focus.surfaces.erase(tablet)
	tablets.erase(id)
	floor_plan.pieces.erase(stand)
	stand.queue_free()


## Put back on the rack: here if the room is ours; if it is the host's, here at once and asked.
func _dock_tablet(id: StringName) -> void:
	if Session.is_authority():
		close_tablet(id)
	elif tablets.has(id) and _predict(&"close_tablet", [id]) > 0:
		_take_down_tablet(id)


func _predicted_tablet(track: int, fx: int, plugin_name: String, where: Vector2) -> StringName:
	for id in tablets:
		var t: PluginTablet = tablets[id][1]
		if t.track_index == track and t.fx_index == fx:
			(tablets[id][0] as Trolley).place(where, _facing_mix(where))
			return id
	_predicted_tablets += 1
	var id := StringName("mine_%d" % _predicted_tablets)
	if _predict(&"open_tablet", [track, fx, plugin_name, where.x, where.y], id) == 0:
		return StringName()
	_build_tablet(id, track, fx, plugin_name)
	_applying_room = true
	(tablets[id][0] as Trolley).place(where, _facing_mix(where))
	_applying_room = false
	return id


## The list of what is out, saved whenever a tablet is opened or closed. Not when a tablet finds
## its plugin somewhere new: the name finds it again next time anyway, and a profile rewritten
## because a different session happened to be open would be a file changed by looking at it.
func _remember_tablets() -> void:
	# A guest's tablets are the host's room, not its own: its own wait for it in the profile.
	if Session.layout == null or not Session.is_authority():
		return
	var out := {}
	for id in tablets:
		var t: PluginTablet = tablets[id][1]
		out[id] = [t.track_index, t.fx_index, t.fx_name]
	if out == Session.layout.tablets:
		return
	Session.layout.tablets = out
	Session.layout.save()


func _restore_tablets() -> void:
	if Session.layout == null or not Session.is_authority():
		return
	for id in Session.layout.tablets:
		var entry: Array = Session.layout.tablets[id]
		_build_tablet(id, int(entry[0]), int(entry[1]), str(entry[2]))


# --- the shared room -----------------------------------------------------------------------
#
# The venue and the plugins out on stands are facts about the room, like where the desk is, so
# in a session they are the host's: one room, everyone in it. A guest asks and is shown; its own
# venue and tablets wait in its profile for when it is on its own again.

## The room as it stands here, in the shape Session.room carries.
func room_state() -> Dictionary:
	var out := {}
	for id in tablets:
		var stand: Trolley = tablets[id][0]
		var t: PluginTablet = tablets[id][1]
		out[id] = [t.track_index, t.fx_index, t.fx_name, stand.position.x, stand.position.z,
				stand.rotation.y]
	var floor := {}
	if floor_plan != null:
		for piece in floor_plan.pieces:
			var t := piece as Trolley
			if t != null and is_instance_valid(t) and not tablets.has(t.piece_id):
				floor[t.piece_id] = [t.position.x, t.position.z, t.rotation.y]
	var placed := {}
	if mount != null:
		for surface_id in mount.mounted_ids():
			if not mount.seats.has(surface_id):
				placed[surface_id] = mount.studio_home(surface_id)
	return {"venue": venue.venue_id() if venue != null else Venue.IDS[0],
			"variant": venue.variant if venue != null else 0, "tablets": out,
			"floor": floor, "placed": placed, "items": items.state() if items != null else {},
			"patches": patches.duplicate(true), "on_air": on_air.duplicate()}


func _publish_room() -> void:
	if Session.role == Session.Role.HOST and not _applying_room:
		Session.publish_room(room_state())


func _on_room_changed() -> void:
	if not Session.is_authority():
		apply_room(Session.room, true)


## Make this room the one `state` describes -- its venue, the same stands in the same places, the
## desk where it stands -- and then put this guest's own unanswered moves back on top.
##
## That last part is the prediction. A guest does what it asked for at once, on its own screen,
## and keeps a note of it until the host's room says the ask was answered: until then the note
## wins over the room, so a stand does not flick back to where it was because a room published a
## moment before the ask arrived crossed it on the wire. Once answered, the room is the truth --
## and if the host would not do it, the stand goes back. That is the rollback.
##
## `glide` rolls things to where the room has them, as if pushed, instead of putting them there.
func apply_room(state: Dictionary, glide := false) -> void:
	_applying_room = true
	_showing_hosts_room = true
	var answered := int((state.get("acks", {}) as Dictionary).get(Session.local_peer_id, 0))
	_predictions = _predictions.filter(func(p: Dictionary) -> bool: return int(p["seq"]) > answered)
	var pending_open := {}
	var pending_close := {}
	var pending_move := {}
	var pending_place := {}
	var pending_items := {}
	for p in _predictions:
		match p["verb"]:
			&"put_item", &"home_item", &"throw_item", &"wear_item": pending_items[p["args"][0]] = true
			&"patch", &"on_air": pass
			&"open_tablet": pending_open[p["id"]] = true
			&"close_tablet": pending_close[p["args"][0]] = true
			&"move_tablet", &"move_piece": pending_move[p["args"][0]] = true
			&"place_surface": pending_place[p["args"][0]] = p["args"][1]

	var id_wanted := StringName(state.get("venue", &""))
	var variant_wanted := Venue.known_variant(id_wanted, int(state.get("variant", 0)))
	if venue != null and Venue.is_known(id_wanted) \
			and (venue.venue_id() != id_wanted or venue.variant != variant_wanted):
		set_venue(id_wanted, false, variant_wanted)

	var wanted: Dictionary = state.get("tablets", {})
	for id in tablets.keys():
		var t: PluginTablet = tablets[id][1]
		var entry: Variant = wanted.get(id)
		if entry != null and int(entry[0]) == t.track_index and int(entry[1]) == t.fx_index:
			continue
		if pending_open.has(id):
			continue
		# The host's answer to this guest's pull: the same stand, under the name the host gave
		# it, rather than this one taken away and that one put up in its place.
		var named := _hosts_name_for(wanted, t.track_index, t.fx_index)
		if named != StringName() and not tablets.has(named):
			_rename_tablet(id, named)
			continue
		_take_down_tablet(id)

	if floor_plan != null:
		for id in wanted:
			if pending_close.has(id):
				continue
			var entry: Array = wanted[id]
			if not tablets.has(id):
				_build_tablet(id, int(entry[0]), int(entry[1]), str(entry[2]))
				(tablets[id][0] as Trolley).place(Vector2(float(entry[3]), float(entry[4])), float(entry[5]))
			elif not pending_move.has(id):
				_follow_room(tablets[id][0], float(entry[3]), float(entry[4]), float(entry[5]), glide)
		var floor: Dictionary = state.get("floor", {})
		for piece in floor_plan.pieces:
			var t := piece as Trolley
			if t == null or not is_instance_valid(t) or not floor.has(t.piece_id) or pending_move.has(t.piece_id):
				continue
			var spot: Array = floor[t.piece_id]
			_follow_room(t, float(spot[0]), float(spot[1]), float(spot[2]), glide)

	if mount != null:
		var placed: Dictionary = (state.get("placed", {}) as Dictionary).duplicate()
		placed.merge(pending_place, true)
		mount.share_studio(placed, GLIDE_SECONDS if glide else 0.0)
	if items != null and state.has("items"):
		items.apply(state["items"], pending_items)
	if state.has("on_air"):
		on_air = (state["on_air"] as Array).duplicate()
		for p in _predictions:
			if p["verb"] == &"on_air":
				_set_on_air(Session.local_peer_id, p["args"][0], false)
	if state.has("patches"):
		patches = (state["patches"] as Dictionary).duplicate(true)
		# This guest's plugs it has moved and not heard back about, on top.
		for p in _predictions:
			if p["verb"] == &"patch":
				_set_patch(Session.local_peer_id, p["args"][0], p["args"][1], false)
		_show_patches()
	_applying_room = false
	_looms_dirty = true


## The time a desk put down across the room takes to get there on this screen.
const GLIDE_SECONDS := 0.25


## A piece to where the room has it -- unless a hand here has hold of it, which wins.
func _follow_room(t: Trolley, x: float, z: float, heading: float, glide: bool) -> void:
	if t.held_by != null:
		return
	var at := Vector2(x, z)
	if at.is_equal_approx(Vector2(t.position.x, t.position.z)) and is_equal_approx(t.rotation.y, heading):
		return
	if glide:
		t.roll_to(at, heading)
	else:
		t.steered = true
		t.place(at, heading)


func _hosts_name_for(wanted: Dictionary, track: int, fx: int) -> StringName:
	for id in wanted:
		if int(wanted[id][0]) == track and int(wanted[id][1]) == fx:
			return id
	return StringName()


## The same stand, known by another name: the one the host gave the stand this guest put out.
func _rename_tablet(from: StringName, to: StringName) -> void:
	var stand: Trolley = tablets[from][0]
	var tablet: PluginTablet = tablets[from][1]
	tablets.erase(from)
	tablets[to] = [stand, tablet]
	stand.piece_id = to
	tablet.surface_id = to
	_authored_floor[to] = _authored_floor.get(from, stand.transform)
	_authored_floor.erase(from)
	if focus != null and focus.focused_id == from:
		focus.focused_id = to
	for p in _predictions:
		if p["verb"] != &"open_tablet" and p["args"].size() > 0 and p["args"][0] == from:
			p["args"][0] = to


## A guest's ask, sent, and done here at once. See apply_room.
func _predict(verb: StringName, args: Array, id := StringName()) -> int:
	var seq := Session.ask_room(verb, args)
	if seq > 0:
		_predictions.append({"seq": seq, "verb": verb, "args": args, "id": id})
	return seq


## A stand being pushed by a hand here, told to everyone else a few dozen times a second so
## theirs rolls after it. The settled place is sent as an ask when it comes to rest.
func _on_trolley_moved(piece: Trolley) -> void:
	_looms_dirty = true
	if piece.held_by == null or not Session.is_networked():
		return
	var now := Time.get_ticks_msec()
	if now - _motion_sent_msec < MOTION_MSEC:
		return
	_motion_sent_msec = now
	Session.send_motion(piece.piece_id, piece.position.x, piece.position.z, piece.rotation.y)


const MOTION_MSEC := 50


## Someone else's hand on a stand: roll ours after it. Not one this guest is pushing, nor one it
## has let go of and not yet heard the host answer for.
func _on_room_motion(id: StringName, x: float, z: float, heading: float, _from: int) -> void:
	var t := _floor_piece(id)
	if t == null or t.held_by != null:
		return
	for p in _predictions:
		if (p["verb"] == &"move_piece" or p["verb"] == &"move_tablet") and p["args"][0] == id:
			return
	t.roll_to(Vector2(x, z), heading)


## The host, answering someone's ask. The same calls the host's own hands make, so the room is
## then published the way any change to it is.
func _on_room_asked(verb: StringName, args: Array, from: int) -> void:
	match verb:
		&"patch":
			# A monitor only while its performer is on air: off air, there is no socket to plug into.
			var into := PersonalMix.monitor_of(args[1])
			if PersonalMix.valid_socket(args[1]) and (into == 0 or into in on_air):
				_set_patch(from, args[0], args[1])
				_publish_room_soon()
		&"on_air":
			_set_on_air(from, args[0])
			_publish_room_soon()
		&"open_tablet":
			if floor_plan != null and DAW.state.fx(args[0], args[1], false) != null:
				open_tablet(args[0], args[1], args[2], Vector2(args[3], args[4]))
		&"close_tablet":
			close_tablet(args[0])
		&"move_tablet", &"move_piece":
			var piece := _floor_piece(args[0])
			if piece != null:
				piece.place(Vector2(args[1], args[2]), args[3])
		&"place_surface":
			if mount != null and mount.mounted_ids().has(args[0]) and not mount.seats.has(args[0]):
				_place_in_studio(args[0], args[1])
		&"put_item", &"home_item", &"throw_item", &"wear_item":
			var item: Item = items.items.get(args[0]) if items != null else null
			if item == null or not _may_put(item, from):
				return
			match verb:
				&"wear_item":
					# Only something in their hand goes on their head.
					if item.state == Item.State.HELD:
						item.set_worn(args[1])
				&"put_item": items.lay(item, Vector2(args[1], args[2]), args[3])
				&"home_item": item.go_home()
				&"throw_item": items.fly(item, args[1], args[2], args[3])


## Only whoever has an item may put it down: the hand the host's table says has it, or anyone
## when nobody does. Not the guest whose pick-up lost a race, still putting down what it thought
## it had.
func _may_put(item: Item, from: int) -> bool:
	var holder := Session.holder_of(item.network_key())
	return holder == 0 or holder == from


func _floor_piece(id: StringName) -> Trolley:
	if floor_plan == null:
		return null
	for piece in floor_plan.pieces:
		var t := piece as Trolley
		if t != null and is_instance_valid(t) and t.piece_id == id:
			return t
	return null


## Gear that stands on nothing, put somewhere in the studio for the room: remembered as the
## host's own placement, stood there if it is standing in the studio now, and the room told.
func _place_in_studio(surface_id: StringName, where: Transform3D) -> void:
	Session.layout.set_transform(surface_id, Presentation.Mode.STUDIO, where)
	Session.layout.save()
	mount.share_studio({})
	if surface_id == &"console":
		_fit_room_to_session()
	_publish_room()


## The mount's question when the desk is put down in the studio: a guest sends it to the host
## and keeps nothing; the host saves it as ever and tells the room once it has.
func _on_studio_placed(surface_id: StringName, where: Transform3D) -> bool:
	if Session.is_authority():
		_publish_room.call_deferred()
		return false
	if _predict(&"place_surface", [surface_id, where]) > 0:
		var placed := mount.shared_studio.duplicate()
		placed[surface_id] = where
		mount.shared_studio = placed
	return true


## Joined someone: their room arrives on its own. Back on our own, or hosting: our own room, and
## as host, everyone is told what it is.
func _on_role_changed() -> void:
	if Session.role == Session.Role.GUEST:
		return
	if _showing_hosts_room:
		_put_back_own_room()
	_publish_room()


func _put_back_own_room() -> void:
	_showing_hosts_room = false
	_predictions.clear()
	if Session.layout == null:
		return
	for id in tablets.keys():
		_take_down_tablet(id)
	if mount != null:
		mount.share_studio({})
	if floor_plan != null:
		_applying_room = true
		for piece in floor_plan.pieces:
			var t := piece as Trolley
			if t == null or not is_instance_valid(t) or not _authored_floor.has(t.piece_id):
				continue
			var own: Transform3D = Session.layout.transform_for(StringName("floor/%s" % t.piece_id),
					Presentation.Mode.STUDIO, _authored_floor[t.piece_id])
			t.place(Vector2(own.origin.x, own.origin.z), own.basis.get_euler().y)
		_applying_room = false
		_fit_room_to_session()
	var own := Session.layout.venue if Venue.is_known(Session.layout.venue) else Venue.IDS[0]
	var own_variant := Venue.known_variant(own, Session.layout.venue_variant)
	if medium != Presentation.Medium.AR and venue != null \
			and (venue.venue_id() != own or venue.variant != own_variant):
		set_venue(own, false, own_variant)
	if floor_plan != null:
		_restore_tablets()


## The carcass fills from the plinth up to the bay's lower edge and the cheeks run past its top,
## whatever height the session has made the bay.
func _fit_stand_to_bay() -> void:
	if _patch_cabinet == null:
		return
	var height := patchbay.panel_height() if patchbay != null else 0.0
	if height <= 0.0:
		height = 0.8
	var floor_top := Caster.HEIGHT + 0.03
	var under := maxf(PATCH_BAY_TOP - height - 0.004, floor_top + 0.01)
	(_patch_cabinet.mesh as BoxMesh).size = Vector3(PatchbaySurface.PANEL_WIDTH,
			under - floor_top, PATCH_CABINET_DEPTH)
	_patch_cabinet.position = Vector3(0, (under + floor_top) * 0.5,
			PATCH_BAY_FRONT - PatchbaySurface.PANEL_DEPTH - PATCH_CABINET_DEPTH * 0.5 + 0.01)
	var top := PATCH_BAY_TOP + 0.03
	for i in _patch_cheeks.size():
		var side := -1.0 if i == 0 else 1.0
		(_patch_cheeks[i].mesh as BoxMesh).size = Vector3(0.035, top - floor_top, 0.16)
		_patch_cheeks[i].position = Vector3(side * (PatchbaySurface.PANEL_WIDTH * 0.5 + 0.0175),
				(top + floor_top) * 0.5, PATCH_BAY_FRONT - 0.06)


func _room_bounds() -> Rect2:
	return Rect2(-room_width * 0.5 + 0.05, -2.15, room_width - 0.10, ROOM_DEPTH - 0.05)


## Move the room round the desk. See SessionLayout for the rule.
##
## A piece this participant has put somewhere themselves stays there unless the desk has grown
## into it, and then it is pushed just clear, the way a person would shove it -- not sent back to
## a default they had already rejected. A piece still where the room put it goes where the room
## would put it now.
func _fit_room_to_session() -> void:
	if floor_plan == null or console == null:
		return
	var desk := _desk_footprint()
	if desk.is_empty():
		return
	var fit := SessionLayout.fit((desk[0]["h"] as Vector2).x)
	var width: float = fit["room_width"]
	if not is_equal_approx(width, room_width):
		room_width = width
		floor_plan.bounds = _room_bounds()
		if venue != null:
			set_venue(venue.venue_id(), false, venue.variant)
		_walk_where_the_venue_lets()
	# A guest's room is fitted by the host, who says where everything went.
	if _showing_hosts_room:
		apply_room(Session.room)
		return
	_fitting = true
	for piece in floor_plan.pieces:
		var t := piece as Trolley
		if t == null or not is_instance_valid(t):
			continue
		var id := String(t.piece_id)
		var want: Variant = null
		if fit.has(id):
			want = [fit[id][0], deg_to_rad(fit[id][1])]
		elif id.begins_with("lamp_") and _authored_floor.has(t.piece_id):
			var home: Transform3D = _authored_floor[t.piece_id]
			want = [SessionLayout.widen(Vector2(home.origin.x, home.origin.z), room_width),
					home.basis.get_euler().y]
		var saved := Session.layout != null and Session.layout.has_transform(
				StringName("floor/%s" % id), Presentation.Mode.STUDIO)
		var here := Vector2(t.position.x, t.position.z)
		if want != null and not saved:
			if not (want[0] as Vector2).is_equal_approx(here) or not floor_plan.is_clear(t, here, t.rotation.y):
				t.place(want[0], want[1])
		elif not floor_plan.is_clear(t, here, t.rotation.y):
			t.place(here, t.rotation.y)
	_fitting = false
	_looms_dirty = true
	_publish_room()


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
	piece.moved.connect(_on_trolley_moved.bind(piece))
	studio_set.add_child(piece)
	floor_plan.add_piece(piece)
	return piece


func _on_trolley_settled(piece: Trolley) -> void:
	var steered := piece.steered
	piece.steered = false
	if not _fitting and not _applying_room and not (steered and not Session.is_authority()):
		if not Session.is_authority():
			# Wheeled here: it stays here, and the host is told; see apply_room.
			var verb := &"move_tablet" if tablets.has(piece.piece_id) else &"move_piece"
			_predict(verb, [piece.piece_id, piece.position.x, piece.position.z, piece.rotation.y])
			_looms_dirty = true
			return
		_publish_room()
	# Where the host's room has things is not where this guest keeps its own.
	if Session.layout == null or _fitting or _showing_hosts_room:
		_looms_dirty = true
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
		# Everything but your own ghost, which only mirrors draw. See core/venues/mirror.gd.
		camera.cull_mask = Mirror.MAIN_VIEW_MASK

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
	if not get_tree().node_added.is_connected(_keep_out_of_mirrors):
		get_tree().node_added.connect(_keep_out_of_mirrors)

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
	# the lamp on a real desk goes and for the same reason. A little ahead of the head rather
	# than over the shoulder, as a desk lamp is: the light is for what is in front, and the
	# full-height rack, framed whole, stands nearly two metres off.
	var work_light := OmniLight3D.new()
	work_light.name = "WorkLight"
	work_light.position = Vector3(0.42 * signf(ergonomics.handedness), 0.30, -0.08)
	work_light.light_color = Color(1.0, 0.95, 0.88)
	work_light.light_energy = 1.0
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

	# Everyone else. Built for a solo run too, empty: a session can be hosted from the panel at
	# any moment, and the people who then walk in need somewhere to stand.
	presence = Presence.new()
	presence.name = "Presence"
	presence.head_node = head
	presence.frame = room_anchor
	add_child(presence)


func _build_surfaces() -> void:
	# These transforms are the DEFAULT LAYOUT, used until a participant moves something and their
	# LayoutProfile starts overriding them. Heights are real: the desk surface at 0.74m, the
	# patchbay at eye level over it, the rack within arm's reach to the left.
	console = ConsoleSurface.new()
	console.name = "Console"
	console.position = Vector3(0, 0.74, 0.1)
	studio_set.add_child(console)
	mount.register(console)

	# On its stand, as authored: the stand's own placement times where the bay sits on it. The
	# stand may since have been wheeled somewhere else; riding it (below) takes care of that.
	patchbay = PatchbaySurface.new()
	patchbay.name = "Patchbay"
	patchbay.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(PATCH_STAND_HEADING)),
			PATCH_STAND_AT) * Transform3D(Basis.IDENTITY, Vector3(0, PATCH_BAY_TOP, PATCH_BAY_FRONT))
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
		mount.studio_placed = _on_studio_placed
		_ride(rack_trolley, rack)
		_ride(deck_trolley, deck)
		_ride(timeline_stand, timeline)
		_ride(patch_stand, patchbay)

	# After the gear, because a loom is measured off the transforms of the two things it joins.
	# Rebuilt with the bay, because the bay's width is the track count and the glands are spaced
	# across it: a session that gains tracks moves where its own looms land.
	patchbay.rebuilt.connect(refresh_looms)
	refresh_looms()

	# The room is fitted to the desk every time the desk changes shape: a live session's tracks
	# arrive after the room is built, and a project that gains a bank gains a metre of console.
	console.rebuilt.connect(_fit_room_to_session)
	patchbay.rebuilt.connect(_fit_stand_to_bay)
	_fit_room_to_session()

	if floor_plan != null:
		rack.tear_requested.connect(_on_tear_requested)
		_restore_tablets()
	Session.room_changed.connect(_on_room_changed)
	Session.room_asked.connect(_on_room_asked)
	Session.role_changed.connect(_on_role_changed)
	Session.room_motion.connect(_on_room_motion)
	_publish_room()


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
		# A bay standing in its cabinet takes its looms in low, through the cheek on the end
		# that faces the desk, the way a floor-standing bay is wired: from there they go
		# straight to the floor and away behind the desk instead of round the carcass.
		if _stands_in_cabinet():
			var side := -(PatchbaySurface.PANEL_WIDTH * 0.5 + 0.035)
			var fraction: float = run[3]
			to_at = patch_stand.transform * Vector3(side, Caster.HEIGHT + 0.14 + (fraction + 1.0) * 0.045,
					PATCH_BAY_FRONT - 0.06 + fraction * 0.035)
			to_dir = (patch_stand.transform.basis * Vector3.LEFT).normalized()
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


func _stands_in_cabinet() -> bool:
	return patch_stand != null and _patch_cabinet != null and _seated_on.has(patchbay.surface_id) \
			and (_patch_cabinet.mesh as BoxMesh).size.y > 0.2


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

## The items' homes off the shelf: the headphones on their hook under it, and the mic in the
## booth's stand, where the venue has one.
func _item_homes() -> Dictionary:
	if venue == null:
		return {}
	var out := {&"headphones": venue.headphones_spot(), &"tablet": venue.tablet_spot(),
			&"shaker": venue.shaker_spot(), &"tambourine": venue.tambourine_spot(),
			&"keytar": venue.keytar_spot(), &"chips": venue.chips_spot(), &"cards": venue.cards_spot()}
	var mic_at: Variant = venue.mic_spot()
	if mic_at != null:
		out[&"mic"] = mic_at
	return out


## The things people pick up (docs/items_loop.md), in the set's frame, the floor plan's. They
## lie only where the walker could stand to pick them up again.
func _build_items() -> void:
	items = ItemRoom.new()
	items.name = "Items"
	if walker != null:
		items.fits = walker.reachable
		items.ground_at = walker.ground_at
		items.floor_rects = func() -> Array: return walker.walkable
		items.solids = func() -> Array: return walker.fixed
		items.gear = walker.footprints
	Session.takeable = func(key: String) -> bool:
		return is_instance_valid(items) and items.items.values().any(
				func(item: Item) -> bool: return item.network_key() == key)
	studio_set.add_child(items)
	items.set_spots(venue.item_spots(), _item_homes())
	var mic := items.items.get(&"mic") as MicItem
	if mic != null:
		mic.live_changed.connect(func(live: bool) -> void:
			if live:
				mic_arm.take()
			else:
				mic_arm.let_go())
	var phones := items.items.get(&"headphones") as HeadphonesItem
	if phones != null:
		phones.worn_changed.connect(_on_phones_changed)
		phones.state_changed.connect(func(_s: Item.State) -> void: _on_phones_changed())
	var tablet := items.items.get(&"tablet") as TabletItem
	if tablet != null:
		tablet.mix = personal
		tablet.colour = _colour_of(Session.local_peer_id)
		tablet.patch_asked.connect(_on_patch_asked)
		tablet.on_air_asked.connect(_on_air_asked)
	personal.changed.connect(_on_personal_changed)
	their_keys = TheirKeys.new()
	their_keys.name = "TheirKeys"
	add_child(their_keys)
	Session.note_played.connect(their_keys.play)
	their_monitor = TheirMonitor.new()
	their_monitor.name = "TheirMonitor"
	add_child(their_monitor)
	Session.note_played.connect(their_monitor.play)
	console.rebuilt.connect(_show_patches)
	Session.roster_changed.connect(_on_roster_for_patches)
	_show_patches()
	items.asked.connect(_on_items_asked)
	items.used.connect(func(item: Item, down: bool) -> void: Session.send_item_use(item.id, down))
	hit_recorder = HitRecorder.new()
	hit_recorder.name = "HitRecorder"
	add_child(hit_recorder)
	hit_recorder.unarmed.connect(func() -> void:
		Session.notice.emit("Arm a track to record the percussion: hits are only heard until one is."))
	items.played.connect(_on_item_played)
	keytar_keys = KeyCatcher.new()
	keytar_keys.name = "KeytarKeys"
	add_child(keytar_keys)
	keytar_keys.note_on.connect(func(pitch: int, velocity: int) -> void:
		if Session.guest_midi != null:
			Session.guest_midi.note_on(pitch, velocity))
	keytar_keys.note_off.connect(func(pitch: int) -> void:
		if Session.guest_midi != null:
			Session.guest_midi.note_off(pitch))
	var keytar := items.items.get(&"keytar") as KeytarItem
	if keytar != null:
		keytar.wants_keys.connect(func() -> void: _keytar_play(true))
	if Session.guest_midi != null:
		Session.guest_midi.key.connect(_on_key_played)
	items.moved.connect(func(_item: Item) -> void: _publish_room_soon())
	if presence != null:
		presence.items = items


## What the headphones on this person's head let through (Ears), and what this person is told
## about it when they go on.
func _on_phones_changed() -> void:
	var phones := items.items.get(&"headphones") as HeadphonesItem if items != null else null
	if phones == null:
		return
	var now := phones.carried_by != null and phones.on_head
	if now == _heard_phones:
		return
	_heard_phones = now
	_listen()
	var tablet := items.items.get(&"tablet") as TabletItem
	if tablet != null:
		tablet.listening = now
	if not now:
		return
	if not Ears.reaches_mix(Session.role == Session.Role.GUEST, DAW.backend is ReaperBackend):
		Session.notice.emit("Headphones on: the room shut out. You hear Reaper itself, through the system.")
	elif personal.is_patched():
		Session.notice.emit("Headphones on: your personal mix, the room shut out. H takes them off.")
	else:
		Session.notice.emit("Headphones on: the mix and your keys, the room shut out. The tablet patches what is in them.")


## The personal mix changed -- a plug moved, a level -- and the headphones, if they are on,
## play it at once.
func _on_personal_changed() -> void:
	_listen()


## What this machine plays, with or without headphones: the cues of the tracks patched while they
## are on, and the personal mix's levels on the buses.
func _listen() -> void:
	if DAW.backend is GodotBackend:
		(DAW.backend as GodotBackend).set_cues(personal.tracks() if _heard_phones and personal.hears_tracks else [])
	if their_keys != null:
		their_keys.set_players(personal.players() if _heard_phones else [])
	if their_monitor != null:
		their_monitor.set_performers(personal.performers() if _heard_phones else [])
	Ears.listen(_heard_phones, personal.ears_levels())


## Whether a strip's socket can be heard here: the tracks are played one by one on this machine.
func _hears_tracks() -> bool:
	return DAW.backend is GodotBackend and Session.role != Session.Role.GUEST


## A plug dropped on a socket by a hand here, or brought back to the tray: done here at once,
## and asked of the host, whose table it is.
func _on_patch_asked(receiver: int, socket: StringName) -> void:
	if not PersonalMix.valid_socket(socket) or receiver < 0 or receiver >= PersonalMix.RECEIVERS:
		return
	var letter: String = PersonalMix.LETTERS[receiver]
	_set_patch(Session.local_peer_id, receiver, socket)
	if Session.is_authority():
		_publish_room_soon()
	else:
		_predict(&"patch", [receiver, socket])
	if socket == &"":
		Session.notice.emit("Plug %s is back in the tray." % letter)
	elif personal.unheard(receiver):
		Session.notice.emit("Plug %s in SEND %s. One track by itself is not heard here: %s" % [letter,
				PersonalMix.title_of(socket), _why_no_tracks()])
	else:
		var late := ""
		var player := PersonalMix.player_of(socket)
		if player > 0 and Session.note_delay_ms(player) >= 0.0:
			late = " Their notes are played here, about %d ms after they play them." \
					% roundi(Session.note_delay_ms(player))
		if PersonalMix.monitor_of(socket) > 0:
			late = " In time with the backing they hear: your mix waits for their notes."
			if not Ears.reaches_mix(Session.role == Session.Role.GUEST, DAW.backend is ReaperBackend):
				late += " Reaper's mix is not the game's to copy, so only their notes are heard."
		Session.notice.emit("Plug %s in SEND %s: in your headphones%s.%s" % [letter,
				PersonalMix.title_of(socket), "" if _heard_phones else " when you put them on", late])


## Whether the keytar is in this player's hands now, and if that has changed, its keys given or
## taken back: GuestMidi plays it, and on a desktop the computer keyboard is its piano.
func _follow_keytar() -> void:
	var keytar := items.items.get(&"keytar") as KeytarItem if items != null else null
	var mine := keytar != null and keytar.state == Item.State.HELD and keytar.carried_by != null \
			and not keytar.is_held_elsewhere()
	if mine == _keytar_mine:
		return
	_keytar_mine = mine
	if Session.guest_midi != null:
		Session.guest_midi.keytar = mine
	if keytar != null and not mine:
		keytar.release_all()
	_keytar_play(mine and medium == Presentation.Medium.SCREEN)


## The computer keyboard as the keytar's piano, on or off, and said so the first time.
func _keytar_play(on: bool) -> void:
	if keytar_keys == null or on == keytar_keys.is_active():
		return
	keytar_keys.set_active(on)
	if on:
		Session.notice.emit("Keytar: A to ' play from %s, Z and X move the octave, the arrows walk. Esc gives the keys back; click the keytar to take them again."
				% keytar_keys.octave_name())


## A key played on this player's keys: shown on the keytar, while it is theirs.
func _on_key_played(pitch: int, down: bool) -> void:
	var keytar := items.items.get(&"keytar") as KeytarItem if items != null else null
	if keytar != null and _keytar_mine:
		keytar.press(pitch, down)


## An instrument played by a hand here: into the take, and, shaken, out to everyone else. A
## click is out already, as a use.
func _on_item_played(item: InstrumentItem, velocity: int, struck: bool) -> void:
	hit_recorder.hit(item, velocity)
	if not struck:
		Session.send_item_hit(item.id, velocity)


## Why a single track is not heard on this machine (`_hears_tracks`).
func _why_no_tracks() -> String:
	if Session.role == Session.Role.GUEST:
		return "a guest hears the host's mix as one stream."
	if DAW.backend is ReaperBackend:
		return "Reaper plays the tracks, not the game."
	return "the stand-in DAW makes no sound."


## Put `peer`'s receiver `receiver`'s plug in `socket`, or back in its tray (empty).
func _set_patch(peer: int, receiver: int, socket: StringName, show := true) -> void:
	if receiver < 0 or receiver >= PersonalMix.RECEIVERS:
		return
	var row: Array = []
	for i in PersonalMix.RECEIVERS:
		var had: Array = patches.get(peer, [])
		row.append(String(had[i]) if i < had.size() else "")
	row[receiver] = String(socket)
	if row.all(func(s: String) -> bool: return s == ""):
		patches.erase(peer)
	else:
		patches[peer] = row
	if show:
		_show_patches()


## Everyone's plugs in the sockets, in their colours, and this person's own in their ears.
func _show_patches() -> void:
	personal.hears_tracks = _hears_tracks()
	personal.set_sockets(patches.get(Session.local_peer_id, []))
	if console == null or console.master == null:
		return
	var peers := patches.keys()
	peers.sort()
	var sockets: Array[SendSocket] = console.master.sends.duplicate()
	for strip in console.strips:
		sockets.append(strip.send)
	if presence != null:
		for peer in Session.participants:
			var avatar := presence.avatar_of(peer)
			if avatar != null:
				avatar.set_on_air(peer in on_air, peer)
		for avatar: Presence.Avatar in presence.avatars():
			if avatar.send != null:
				sockets.append(avatar.send)
			if avatar.monitor_send != null:
				sockets.append(avatar.monitor_send)
	var tablet := items.items.get(&"tablet") as TabletItem if items != null else null
	if tablet != null:
		tablet.on_air = Session.local_peer_id in on_air
	for socket in sockets:
		if not socket.pressed.is_connected(_on_send_pressed):
			socket.pressed.connect(_on_send_pressed.bind(socket.source))
		var colours: Array[Color] = []
		for peer in peers:
			for s: String in patches[peer]:
				if StringName(s) == socket.source:
					colours.append(_colour_of(peer))
		socket.set_plugs(colours)


## A SEND socket clicked: this person's plugs in it come back to their tray. With none in it,
## where the plugs are.
func _on_send_pressed(source: StringName) -> void:
	var mine: Array = patches.get(Session.local_peer_id, [])
	var any := false
	for i in mine.size():
		if StringName(mine[i]) == source:
			_on_patch_asked(i, &"")
			any = true
	if not any:
		Session.notice.emit("Drag a plug onto SEND %s from your tablet: it lies on the prop shelf's lower tier."
				% PersonalMix.title_of(source))


## Who is here changed: colours may have, and a guest who left takes their plugs with them.
func _on_roster_for_patches() -> void:
	var tablet := items.items.get(&"tablet") as TabletItem if items != null else null
	if tablet != null:
		tablet.colour = _colour_of(Session.local_peer_id)
	if Session.role == Session.Role.HOST:
		for peer in patches.keys():
			if not Session.participants.has(peer):
				patches.erase(peer)
				_publish_room_soon()
		for peer in on_air.duplicate():
			if not Session.participants.has(peer):
				_set_on_air(peer, false, false)
				_publish_room_soon()
		# And the plugs in the keys of whoever left come back to their trays.
		for peer in patches.keys():
			var row: Array = patches[peer]
			for i in row.size():
				var into := PersonalMix.player_of(StringName(row[i]))
				if into > 0 and not Session.participants.has(into):
					_set_patch(peer, i, &"", false)
					_publish_room_soon()
	# After the ghosts: a new one's pack is made on the same news.
	_show_patches.call_deferred()


## The ON AIR switch on the tablet in a hand here: done here at once, and asked of the host.
func _on_air_asked(on: bool) -> void:
	_set_on_air(Session.local_peer_id, on)
	if Session.is_authority():
		_publish_room_soon()
	else:
		_predict(&"on_air", [on])
	if on:
		Session.notice.emit("On air: anyone can plug into the MONITOR on your pack and hear your keys in time with the backing you play to.")
	else:
		Session.notice.emit("Off air: the plugs in your monitor went back to their trays.")


## `peer` ON AIR or off. Off, the plugs in their monitor come back to their owners' trays: the
## host's to do, as it keeps the table; a guest predicting its own leaves the others to it.
func _set_on_air(peer: int, on: bool, show := true) -> void:
	if on and peer not in on_air:
		on_air.append(peer)
		on_air.sort()
	elif not on:
		on_air.erase(peer)
		if Session.is_authority():
			for listener in patches.keys():
				var row: Array = patches[listener]
				for i in row.size():
					if PersonalMix.monitor_of(StringName(row[i])) == peer:
						_set_patch(listener, i, &"", false)
	if show:
		_show_patches()


func _colour_of(peer: int) -> Color:
	var p: Session.Participant = Session.participants.get(peer)
	return p.colour if p != null else SendSocket.LAMP


## A hand here put an item down, or sent it home: a guest asks the host, having done it already.
## A host's room is told by the item moving (`_publish_room_soon`).
func _on_items_asked(verb: StringName, args: Array) -> void:
	if not Session.is_authority():
		_predict(verb, args)


## The room told once at the end of the frame, however many things in it moved during it.
func _publish_room_soon() -> void:
	if Session.role != Session.Role.HOST or _applying_room or _room_publish_due:
		return
	_room_publish_due = true
	(func() -> void:
		_room_publish_due = false
		_publish_room()).call_deferred()



## Off your head into the mouse's hand, or on from it.
func _toggle_headphones() -> void:
	var hand := get_node_or_null("MouseHand") as Interactor
	if hand == null:
		return
	if hand.worn != null:
		if not hand.take_off():
			Session.notice.emit("Your hand is full: put down what is in it first (Q).")
	elif hand.carrying != null and hand.carrying.wearable():
		hand.wear()


## Put down whatever any hand here is carrying, where it is aiming.
func put_down_items() -> void:
	for hand in get_tree().get_nodes_in_group(Interactor.GROUP):
		var interactor := hand as Interactor
		if interactor != null and interactor.carrying != null:
			interactor.put_down()


func _build_walker() -> void:
	walker = Walker.new()
	walker.name = "Walker"
	walker.camera = camera
	walker.floor_plan = floor_plan
	walker.walkable = _walkable()
	walker.fixed = venue.solids() if venue != null else []
	walker.solids_parent = studio_set
	walker.standing_eye = ergonomics.eye_height
	walker.eye_height = ergonomics.eye_height
	add_child(walker)
	# At the mix position, looking down at the desk. Aimed at a POINT on it rather than set to
	# an angle, because the desk does not move when the eye does: -0.5 rad was right from a
	# standing 1.62 m and, from a seated 1.21 m, put the faders' tops up under the timeline.
	walker.global_position = Vector3(0, 0, MIX_POSITION_Z)
	walker.pitch = -atan2(ergonomics.eye_height - DESK_GAZE.y, DESK_GAZE.x)
	walker.active = not god_mode
	walker._place_camera()


## Swap between walking and flying. The handover keeps the view: going up, the orbit takes the
## walker's eye and a point in front of it; coming down, the walker lands under wherever the
## camera was, inside the room, facing the same way.
func set_god_mode(on: bool) -> void:
	god_mode = on
	if walker == null:
		return
	walker.active = not on
	if on:
		var forward := -walker.look_basis().z
		var at := walker.eye() + forward * 1.6
		frame(at, 1.6, walker.yaw, walker.pitch)
	else:
		var from := camera.global_position
		var b := floor_plan.bounds if floor_plan != null else Rect2(-3, -2, 6, 4.8)
		walker.global_position = Vector3(clampf(from.x, b.position.x + 0.3, b.end.x - 0.3), 0.0,
				clampf(from.z, b.position.y + 0.3, b.end.y - 0.3))
		walker.velocity = Vector3.ZERO
		walker.yaw = _orbit_yaw
		walker.pitch = clampf(_orbit_pitch, -1.2, 0.6)
		walker.eye_height = walker.standing_eye
		walker._place_camera()


## Orbit on right-drag, zoom on wheel, WASD to walk. Not a replacement for standing in the room;
## it is how the screen half of a hybrid session gets around, and how every screenshot of this
## project is framed.
func _unhandled_input(event: InputEvent) -> void:
	if camera == null:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) \
			and not god_mode and walker != null:
		walker.look(event.relative)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_orbit_yaw -= event.relative.x * 0.005
		_orbit_pitch = clampf(_orbit_pitch - event.relative.y * 0.005, -1.4, 1.2)
		_update_camera()
	elif event is InputEventKey and event.keycode == KEY_R and not event.echo:
		# Hold to wind up a throw of what you carry, let go to throw it where the cursor is.
		# R: beside Q, which puts it down, under the same hand.
		var hand := get_node_or_null("MouseHand") as MouseInteractor
		if hand != null:
			if event.pressed:
				hand.begin_throw()
			else:
				hand.release_throw()
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
			# The history, from anywhere in the room. The deck has keys for it too.
			KEY_Z when event.ctrl_pressed:
				DAW.redo() if event.shift_pressed else DAW.undo()
			KEY_Y when event.ctrl_pressed:
				DAW.redo()
			# Split the selected items at the playhead. B for blade: S is walking backwards.
			KEY_B:
				DAW.split_selected(DAW.state.position_seconds)
			# Put down what you are carrying, where you are looking. Q: the key under the hand
			# that is on WASD, and the one games drop things with.
			KEY_Q:
				put_down_items()
			# Headphones on, or off into your hand. H: beside the hand's other item keys.
			KEY_H:
				_toggle_headphones()
			# Leave your body and fly, or come back down into it.
			KEY_N:
				set_god_mode(not god_mode)
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
		if not god_mode and walker != null:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				camera.fov = maxf(30.0, camera.fov - 3.0)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				camera.fov = minf(ROOM_FOV, camera.fov + 3.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_distance = maxf(0.4, _orbit_distance - 0.12)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_distance = minf(6.0, _orbit_distance + 0.12)
			_update_camera()


func _process(delta: float) -> void:
	_refresh_looms_if_moved(delta)
	_follow_keytar()
	if venue != null and DAW.state != null:
		venue.pulse(maxf(DAW.state.master.vu_l, DAW.state.master.vu_r))
	if camera == null or not god_mode:
		return
	# Not while typing a name into the session panel, or every "s" in it flies backwards.
	if get_viewport().gui_get_focus_owner() != null:
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
	# Anywhere in the set: a tablet stands on its own stand, a level further down.
	if target != null and studio_set.is_ancestor_of(target):
		var box := target.content_aabb()
		if box.size.y > 0.01:
			seat = focus.seat_for(target)
			# Inside the room and at a height a person's eyes can be at. A rack's bottom unit
			# asks for a seat on the floor; nobody mixes lying down.
			var bounds := floor_plan.bounds if floor_plan != null \
					else _room_bounds()
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
	if walker != null and not god_mode:
		_orbit_target = to[0]
		walker.travel_to(seat.origin, look_at, seconds)
		if _walk != null and _walk.is_valid():
			_walk.kill()
		_walk = create_tween()
		_walk.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_walk.tween_property(body, "transform", seat, seconds)
		return
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
	if walker != null and not god_mode:
		var eye := target + Basis(Vector3.UP, yaw) * (Basis(Vector3.RIGHT, pitch) * Vector3(0, 0, distance))
		walker.travel_to(eye, target, 0.0)
		return
	_update_camera()


func _update_camera() -> void:
	if walker != null and not god_mode:
		walker._place_camera()
		return
	var offset := Basis(Vector3.UP, _orbit_yaw) * (Basis(Vector3.RIGHT, _orbit_pitch) * Vector3(0, 0, _orbit_distance))
	camera.position = _orbit_target + offset
	camera.look_at(_orbit_target, Vector3.UP)
