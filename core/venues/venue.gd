class_name Venue
extends Node3D

## The world the studio stands in.
##
## Everything a person WORKS with -- the gear, the stands it rides on, the lamps, the looms, where
## each of them has been pushed -- belongs to the studio and is the same in every venue. A venue
## is everything else: the floor, what is past the edge of the floor, the sky if there is one,
## the air, and how all of it is lit. Swapping one is a change of scenery, never of setup, which
## is why it is safe to do mid-session and why it is one key.
##
## Saved in the layout on your own; in a session, the HOST'S, like everything else about the room
## (see Session.room). A guest is shown the host's venue and keeps its own for later.
##
## Every venue keeps the same working footprint (room_width x Studio.ROOM_DEPTH) because the
## furniture's floor plan is that rectangle. A venue with no walls marks it instead -- a lit
## border on the grid, a chalk outline in the chalk zone -- so the edge you will bump a rack
## into is never invisible.

## Registry, in cycling order. The first is the default.
const IDS: Array[StringName] = [&"studio", &"grid", &"chalk", &"loft", &"cabin", &"rooftop", &"station", &"dome",
		&"club", &"cave", &"greenhouse", &"stage", &"garden", &"desert"]

## The Rig Roulette room's id. A place the band is taken to, not one of the venues (`IDS`).
const ROULETTE_ID := &"roulette"

## A venue can come in more than one arrangement -- the same place with its structure moved
## about: walls or none, a city close in or far off. A variant keeps the venue's footprint and
## its zones' contract; only what stands round them changes. Variant 0 is the venue as first
## built. Chosen by whoever's room it is, and carried with the venue (see Session.room).
const VARIANTS := {
	&"studio": ["Live room behind", "Live room beside", "Through the glass"],
	&"grid": ["Highway", "Downtown", "Neon sea"],
	&"chalk": ["Open sky", "Sketched room", "Classroom"],
	&"loft": ["City night", "Sunday morning", "Thunderstorm"],
	&"cabin": ["Snowy night", "Summer dusk", "Northern lights"],
	&"rooftop": ["Dusk", "Golden hour", "Night"],
	&"station": ["Night side", "Day side", "Orbital sunrise"],
	&"dome": ["Twenty metres", "The deep", "Shipwreck"],
	&"club": ["After hours", "Showtime", "Speakeasy"],
	&"cave": ["Crystal grotto", "Glowworm lake", "Lava tube"],
	&"greenhouse": ["Morning", "Rain", "Night bloom"],
	&"stage": ["Headline night", "Soundcheck", "Arena"],
	&"garden": ["Spring", "Autumn", "Winter"],
	&"desert": ["Starlit canyon", "Dawn dunes", "Oasis"],
}

## What people will do here besides mix, each with room of its own. Built later; every venue
## leaves the space for all of them now, so an activity made for one lands in every one.
const ZONE_IDS: Array[StringName] = [&"bricks", &"matrix", &"drums", &"vocals", &"synth"]

## Where they go, at the base room width: back of house, behind the mix position, so the gear's
## floor plan never moves for them. Turn round from the desk and they are all in front of you,
## booth and kit to the left, the lattice in the middle, the table and the keys to the right.
## Each box is the activity's whole space -- clearance to walk round it included -- from the
## floor up to the height it needs.
const ZONES := {
	# A booth 2.2 m square: one singer, a stand, and the door.
	&"vocals": AABB(Vector3(-6.0, 0.0, 4.9), Vector3(2.2, 2.4, 2.2)),
	# A riser for a full kit and the drummer's stool, 2.6 m square.
	&"drums": AABB(Vector3(-3.5, 0.0, 4.5), Vector3(2.6, 2.8, 2.6)),
	# The lattice, 3.4 m on every side: a 3 m cube of cells and room to reach in from any face.
	&"matrix": AABB(Vector3(-0.5, 0.0, 3.7), Vector3(3.4, 3.4, 3.4)),
	# A 1 x 2 m table at waist height, long way back, with walking room all round.
	&"bricks": AABB(Vector3(3.2, 0.0, 3.4), Vector3(1.9, 1.3, 2.9)),
	# A keyboard stand 1.5 m wide against the right-hand wall, modules racked above it.
	&"synth": AABB(Vector3(5.35, 0.0, 4.4), Vector3(0.8, 2.0, 2.0)),
}
## The back-of-house space the zones stand in: from the control room's open rear (the
## footprint's far edge) back to here, and this far either side of centre at the base width.
const LIVE_ROOM_BACK := 7.3
const LIVE_ROOM_HALF := 6.3
## Tall enough for the lattice and a hand raised above it.
const LIVE_ROOM_HEIGHT := 4.0

## How wide the working footprint is. Set by the studio before the venue enters the tree; the
## room grows with the desk (see SessionLayout), and a venue drawn for the old width would put
## its walls through the rack.
var room_width := Studio.ROOM_WIDTH

## Which arrangement of this venue to build (VARIANTS). Set by make(), before the venue enters
## the tree.
var variant := 0

## Set by the studio before the venue enters the tree: whether the full desktop renderer is
## running. A venue must look right without it -- a headset runs the mobile renderer.
var rich := false


static func make(id: StringName, which := 0) -> Venue:
	var out: Venue
	match id:
		&"grid":
			out = GridVenue.new()
		&"chalk":
			out = ChalkVenue.new()
		&"loft":
			out = LoftVenue.new()
		&"cabin":
			out = CabinVenue.new()
		&"rooftop":
			out = RooftopVenue.new()
		&"station":
			out = StationVenue.new()
		&"dome":
			out = DomeVenue.new()
		&"club":
			out = ClubVenue.new()
		&"cave":
			out = CaveVenue.new()
		&"greenhouse":
			out = GreenhouseVenue.new()
		&"stage":
			out = StageVenue.new()
		&"garden":
			out = GardenVenue.new()
		&"desert":
			out = DesertVenue.new()
		ROULETTE_ID:
			out = RouletteRoom.new()
		_:
			out = StudioVenue.new()
	out.variant = known_variant(id, which)
	return out


## The names of a venue's arrangements, in order, without building it. A venue with one has
## nothing to choose between, and the stage manager shows no picker for it.
static func variant_titles(id: StringName) -> PackedStringArray:
	return PackedStringArray(VARIANTS.get(id, [make_title(id)]))


## `which` if the venue has that arrangement, else its first.
static func known_variant(id: StringName, which: int) -> int:
	return which if which >= 0 and which < variant_titles(id).size() else 0


## A venue's name without building one: building the chalk zone to read its title would draw
## sixty-four doodles for a button caption.
static func make_title(id: StringName) -> String:
	match id:
		&"grid":
			return "Grid"
		&"chalk":
			return "Chalk Zone"
		&"loft":
			return "Loft"
		&"cabin":
			return "Cabin"
		&"rooftop":
			return "Rooftop"
		&"station":
			return "Station"
		&"dome":
			return "Underwater dome"
		&"club":
			return "Jazz club"
		&"cave":
			return "Crystal cave"
		&"greenhouse":
			return "Glasshouse"
		&"stage":
			return "Festival stage"
		&"garden":
			return "Temple garden"
		&"desert":
			return "Desert"
		ROULETTE_ID:
			return "Rig Roulette room"
		_:
			return "Studio"


static func next_after(id: StringName) -> StringName:
	var at := IDS.find(id)
	return IDS[(at + 1) % IDS.size()]


static func is_known(id: StringName) -> bool:
	return IDS.has(id) or id == ROULETTE_ID


func venue_id() -> StringName:
	return &"studio"


## What a person is told when they arrive.
func title() -> String:
	if variant_titles(venue_id()).size() < 2:
		return make_title(venue_id())
	return "%s, %s" % [make_title(venue_id()), variant_titles(venue_id())[variant]]


## Set up the sky, the air, the exposure and the key light. `env` arrives fresh, with the
## studio's house defaults (glow on, SSAO on) already in it, so a venue only states what is
## different about it.
func dress(_env: Environment, _key: DirectionalLight3D) -> void:
	pass


## The lamps are furniture and go wherever the venue goes, but what they shine is the venue's
## call: a warm tungsten floor lamp on a neon grid is a lamp from another room.
func lamp_colour(_index: int, authored: Color) -> Color:
	return authored


func lamp_energy(_index: int, authored: float) -> float:
	return authored


## The house lights go, for a venue with fittings of its own to kill -- `power_flicker`'s strike,
## the one bar a chaos event takes the room dark. Nothing by default: a venue with no fittings
## of its own (anything but the studio today) has nothing here to turn off; its own practicals
## (scenes/studio.gd's `_lamps`) still dip and die, which is the whole room going dark anywhere.
func blackout(_on: bool) -> void:
	pass


## How loud the mix is right now, 0..1, every frame. For venues that move to the music.
func pulse(_level: float) -> void:
	pass


## Whether the room moves to the music. Off, `hear` takes everything for silence and a venue sits
## at its authored look: for anyone who would rather the room held still.
var reactive := true
## The mix's level through a meter's ballistics (fast up, slow down), 0..1.
var heard := 0.0
## A flash on each rise in the level -- a kick or a snare -- that dies away in a few frames, 0..1.
var heard_hit := 0.0
var _heard_slow := 0.0


## What a venue's `pulse` calls first: smooths `level` into `heard` and finds the hits in it into
## `heard_hit`. Nothing here allocates, and a mix at rest (or `reactive` off) settles both at 0.
func hear(level: float) -> void:
	var l := clampf(level, 0.0, 1.0) if reactive else 0.0
	heard = lerpf(heard, l, 0.45 if l > heard else 0.08)
	# A hit is the level jumping above where it has been lately.
	_heard_slow = lerpf(_heard_slow, l, 0.05)
	heard_hit = maxf(heard_hit * 0.82, clampf((l - _heard_slow) * 3.0, 0.0, 1.0))
	if heard < 0.002:
		heard = 0.0
	if heard_hit < 0.002:
		heard_hit = 0.0


## A box of soft additive sparks, off until `drive_sparks` turns them on. `colours` is picked per
## spark from its left to its right; `rise` sends them up instead of down.
func make_sparks(label: String, at: Vector3, extents: Vector3, seen: AABB, colours: Gradient,
		amount: int, rise := false) -> GPUParticles3D:
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	soft.gradient = g
	soft.width = 32
	soft.height = 32
	var dot := StandardMaterial3D.new()
	dot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dot.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dot.vertex_color_use_as_albedo = true
	dot.albedo_texture = soft
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	quad.material = dot
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = extents
	m.direction = Vector3(0, 1 if rise else -1, 0)
	m.spread = 25.0
	m.initial_velocity_min = 0.1
	m.initial_velocity_max = 0.5
	m.gravity = Vector3(0, 0.12 if rise else -0.25, 0)
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 0.35
	m.turbulence_noise_scale = 2.0
	m.scale_min = 0.5
	m.scale_max = 1.6
	var pick := GradientTexture1D.new()
	pick.gradient = colours
	m.color_initial_ramp = pick
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	m.color_ramp = ramp
	var p := GPUParticles3D.new()
	p.name = label
	p.position = at
	p.amount = amount
	p.lifetime = 3.0
	p.local_coords = false
	p.emitting = false
	p.draw_pass_1 = quad
	p.process_material = m
	p.visibility_aabb = seen
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


## How many of `p`'s sparks are out, from what the mix is doing: none at rest.
func drive_sparks(p: GPUParticles3D, gain := 1.0) -> void:
	if p == null:
		return
	var rate := clampf((heard * 1.4 + heard_hit) * gain, 0.0, 1.0)
	p.amount_ratio = maxf(rate, 0.01)
	p.emitting = rate > 0.04


## The activity zones, id -> AABB in studio space. The room widens with the desk, and the zones
## step out with it on their own side, so they never close in on the footprint or on each other.
func zones() -> Dictionary:
	var out := {}
	for id in ZONE_IDS:
		var box: AABB = ZONES[id]
		var shift := _grow() * signf(box.get_center().x)
		out[id] = AABB(box.position + Vector3(shift, 0, 0), box.size)
	return out


## What in the zones stops a person walking, as walker footprints ({c, h, a, top}) in studio
## space. Nothing by default: a zone that is only drawn (the chalk zone's sketches) is walked
## through, the way everything drawn in the air there is.
func zone_solids() -> Array:
	return []


## Where the prop shelf stands, in studio space: its floor centre, turned so its front faces
## into the room. Against the left wall at the front of the back of house, the side the mirror and
## the wardrobe are on: turn round from the desk and it is on your right as you come out of the
## control room, short of the booth and the riser.
func prop_shelf_spot() -> Transform3D:
	var x := -live_room_half() + 0.08 + ZoneKit.SHELF.z * 0.5
	var z := Studio.ROOM_BACK + 0.3 + ZoneKit.SHELF.x * 0.5
	return Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x, 0, z))


## Where the items live, in studio space, one per item (ItemRoom.KINDS) and a few spare: in a
## row along the shelf's top, facing out into the room.
func item_spots() -> Array[Transform3D]:
	var shelf := prop_shelf_spot()
	var out: Array[Transform3D] = []
	# From the middle out, so one item is not left at the end of an empty shelf; the lamp is at
	# the +X end, so that side fills last.
	for i in [1, 0, 2, 3].slice(0, ZoneKit.SHELF_SPOTS):
		var along := (float(i) - (ZoneKit.SHELF_SPOTS - 1) * 0.5) * ZoneKit.SHELF.x / ZoneKit.SHELF_SPOTS
		var at := shelf * Vector3(along, ZoneKit.SHELF.y, 0.04)
		# Facing out of the shelf's front, as an item faces -Z.
		out.append(Transform3D(shelf.basis * Basis(Vector3.UP, PI), at))
	return out


## Where the headphones hang, in studio space: on the hook under the front of the prop shelf
## (ZoneKit.HEADPHONE_HOOK), band over the peg, facing out.
func headphones_spot() -> Transform3D:
	var hang := ZoneKit.HEADPHONE_HOOK + Vector3(0, -HeadphonesItem.HANG, ZoneKit.HOOK_REACH * 0.55)
	return prop_shelf_spot() * Transform3D(Basis(Vector3.UP, PI), hang)


## Where the tablet lies, in studio space: face up on the prop shelf's lower tier, toward the
## lamp's end and out of the headphones' way, its tray toward the back.
func tablet_spot() -> Transform3D:
	return prop_shelf_spot() * Transform3D(Basis.IDENTITY, Vector3(0.17, ZoneKit.SHELF_LOWER_TOP, 0.03))


## Where the keytar stands, in studio space: on its edge on the rack at the back of the prop
## shelf (ZoneKit.KEYTAR_PEGS), keys out to the room, its body's edge on the low peg.
func keytar_spot() -> Transform3D:
	return prop_shelf_spot() * Transform3D(Basis(Vector3.RIGHT, PI * 0.5),
			Vector3(0, ZoneKit.KEYTAR_REST + KeytarItem.FRONT_EDGE, ZoneKit.KEYTAR_BACK_Z))


## Where the hand percussion lies, in studio space: on the prop shelf's lower tier, at the far end
## from the tablet: the tambourine flat, head up, and the shaker beside it, along the shelf's depth.
func tambourine_spot() -> Transform3D:
	return prop_shelf_spot() * Transform3D(Basis.IDENTITY, Vector3(-0.23, ZoneKit.SHELF_LOWER_TOP, 0.01))


func shaker_spot() -> Transform3D:
	return prop_shelf_spot() * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-0.04, ZoneKit.SHELF_LOWER_TOP, 0.02))


## Where the chips and the cards lie, in studio space: along the front edge of the prop shelf's
## top, at its two ends, as they would be left on a table: the stack at the ball's end, the deck a
## little askew at the lamp's. Not in front of a toy: from the seat a toy behind one would be a
## click on the chips.
func chips_spot() -> Transform3D:
	return prop_shelf_spot() * Transform3D(Basis(Vector3.UP, PI), Vector3(-0.4, ZoneKit.SHELF.y, 0.15))


func cards_spot() -> Transform3D:
	return prop_shelf_spot() * Transform3D(Basis(Vector3.UP, PI - 0.25), Vector3(0.38, ZoneKit.SHELF.y, 0.13))


## Where the Newton's cradle stands, in studio space: at the back of the prop shelf's top, in the
## middle, its row of balls along the shelf -- behind the duck and the plane and taller than them,
## under the shelf lamp, not hidden behind the ball in the dark corner.
func cradle_spot() -> Transform3D:
	return prop_shelf_spot() * Transform3D(Basis(Vector3.UP, PI), Vector3(-0.04, ZoneKit.SHELF.y, -0.135))


## Where the yo-yo lies, in studio space: on its side at the front of the prop shelf's top,
## between the plane and the cards.
func yoyo_spot() -> Transform3D:
	return prop_shelf_spot() * Transform3D(Basis(Vector3.UP, PI), Vector3(0.2, ZoneKit.SHELF.y, 0.15))


## Where the dartboard's face is, in studio space: its middle, facing out into the room (+Z).
func dartboard_spot() -> Transform3D:
	return prop_shelf_spot() * Transform3D(Basis.IDENTITY, Vector3(0, ZoneKit.DARTBOARD_Y, ZoneKit.DARTBOARD_FACE_Z))


## What a dart sticks in, in studio space (Flight.fly's `boards`): the board, and the cork panel
## round it.
func dart_boards() -> Array:
	var panel := prop_shelf_spot() * Transform3D(Basis.IDENTITY, Vector3(0, ZoneKit.DARTBOARD_Y,
			ZoneKit.DART_PANEL_BACK + ZoneKit.DART_PANEL_THICK))
	return [{"at": dartboard_spot(), "radius": ZoneKit.DARTBOARD_RADIUS},
			{"at": panel, "half": ZoneKit.DART_PANEL * 0.5}]


## Where dart `n` lives, in studio space: left in the board, along the top of it, point in and
## its tail a little down, as darts hang in a board between games.
const DART_HOMES := [Vector2(-0.11, 0.1), Vector2(0.0, 0.135), Vector2(0.11, 0.1)]


func dart_spot(n: int) -> Transform3D:
	var on: Vector2 = DART_HOMES[n % DART_HOMES.size()]
	return dartboard_spot() * Transform3D(Basis(Vector3.RIGHT, 0.15), Vector3(on.x, on.y, -DartItem.POINT_IN))


## Where the mini hoop stands, in studio space: its foot, its board facing into the room. On
## the right-hand wall at the front of the live room, the opposite side from the shelf the ball
## lives on: in front of the bricks table and the synth stand, clear of both, a throw across the
## room from the shelf.
func hoop_spot() -> Transform3D:
	var x := live_room_half() - 0.12 + Hoop.POLE_Z
	var z := Studio.ROOM_BACK + 0.32
	return Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(x, 0, z))


## Where the venue's own toy (ToyItem) lies, in studio space: on the floor a little in front of
## the hoop and to its right, where you would leave a ball after shooting -- room enough round it
## for the rooftop's beach ball, clear of the hoop's base.
func toy_spot() -> Transform3D:
	return hoop_spot() * Transform3D(Basis(Vector3.UP, 0.6), Vector3(0.42, 0, 0.5))


## Where the radio plane (RcPlaneItem) waits, in studio space: on the floor further out from the
## hoop than the toy, its nose toward the middle of the room, so a take-off runs into the open.
func rcplane_spot() -> Transform3D:
	return hoop_spot() * Transform3D(Basis(Vector3.UP, PI), Vector3(0.55, 0, 1.25))


## Where the Tour case stands, in studio space: chained in the back of house, against the back
## wall on the opposite side from the hoop, its stencilled front facing into the room -- clear
## of the mirror and the wardrobe, a throw from the middle of the floor.
func tour_case_spot() -> Transform3D:
	var x := -live_room_half() + 0.65
	var z := LIVE_ROOM_BACK - 0.5
	# Turned a half-circle from identity: the case's front (+Z, tools/blender/tour_case.py) then
	# faces -Z, back toward the control room, the way anyone walking into the back of house
	# meets it.
	return Transform3D(Basis(Vector3.UP, PI), Vector3(x, 0, z))


## Where the chord harp stands (ChordHarp), in studio space: its feet on the floor under its
## strings, turned so whoever plays it faces the back wall. Against the live room's back wall,
## behind the bricks table: the side away from the prop shelf, the mirror and the wardrobe, the
## roulette door and the Tour case, out of the zones and of the way to the keyboard stand. Walk
## round the table and it is in front of you.
func harp_spot() -> Transform3D:
	var at := zones()
	var x := live_room_half() - (LIVE_ROOM_HALF - (ZONES[&"bricks"] as AABB).get_center().x)
	if at.has(&"bricks"):
		x = (at[&"bricks"] as AABB).get_center().x
	# Its plinth's back a hand's width off the wall.
	var z := LIVE_ROOM_BACK - 0.05 - 0.08 - (ChordHarp.FOOT.y - ChordHarp.FOOT_Z)
	return Transform3D(Basis(Vector3.UP, PI), Vector3(x, 0, z))


## Where the handbells' stand stands (HandbellItem.stand), in studio space: beside the chord harp,
## its back in line with the harp's plinth, facing the same way, so whoever walks round the
## bricks table to the harp finds the bells at their elbow. On the harp's high side, `BELL_SIDE`,
## a hand's width clear of its plinth.
const BELL_SIDE := 1.0
const BELL_GAP := 0.12


func bell_stand_spot() -> Transform3D:
	var along := ChordHarp.FOOT.x + BELL_GAP + HandbellItem.STAND.x * 0.5
	var back := ChordHarp.FOOT_Z - ChordHarp.FOOT.y + HandbellItem.STAND.y * 0.5
	return harp_spot() * Transform3D(Basis.IDENTITY, Vector3(BELL_SIDE * along, 0, back))


## Where handbell `n` (1 to 4) lives, in studio space: on its seat on the stand, mouth down, its
## tab toward the room (HandbellItem.seat).
func bell_spot(n: int) -> Transform3D:
	return bell_stand_spot() * HandbellItem.seat(n)


## Where the fifths wheel stands (FifthsWheel.on_stand), in studio space: on the bricks table,
## the bottom edge of its board WHEEL_IN in from the table's end nearest the control room, facing
## back toward it. So whoever walks back from the desk meets it at the end of the table, where
## both hands reach it and the table's length is behind it. Null where there is no bricks table
## (the Rig Roulette room has no zones).
const WHEEL_IN := 0.06


func wheel_spot() -> Variant:
	var at := zones()
	if not at.has(&"bricks"):
		return null
	var c := (at[&"bricks"] as AABB).get_center()
	return Transform3D(Basis(Vector3.UP, PI),
			Vector3(c.x, ZoneKit.TABLE_HEIGHT, c.z - ZoneKit.TABLE_TOP.z * 0.5 + WHEEL_IN))


## Where the Rig Roulette station hangs, in studio space: on the control room's own back wall,
## within reach of the console rather than tucked away in the back of house like the Tour case --
## this is a thing the whole band gathers around between takes, not a run's own opening move.
## Mounted at console-knob height, facing into the room.
##
## The back wall, not a side wall: both side walls sit behind furniture that grows with every
## track's own FX -- the mixing rack (`Studio.rack`, leant out at 38 degrees off the left wall)
## and the patchbay (leant off the right) both lengthen as tracks are added, and a long enough
## one stands squarely between the seat and anything mounted on the wall behind it
## (`tests/run_tests.gd`'s own seat-click audit, run at 40 tracks, catches exactly this). The
## back wall carries nothing of the kind -- only the fixed first-reflection panels this clears
## by mounting past their x -1.95..1.95 spread, toward the corner.
func rig_roulette_spot() -> Transform3D:
	var x := -room_width * 0.5 + 1.0
	# The wall is a box 0.1 thick centred on ROOM_FRONT, its face 5cm out; the plate stands 1cm
	# deep behind the origin, so a spot any nearer than this buries the panel in the plaster.
	var z := Studio.ROOM_FRONT + 0.07
	return Transform3D(Basis.IDENTITY, Vector3(x, 1.05, z))


## Where the door to the Rig Roulette room stands, in studio space (its origin the floor in the
## middle of the opening, facing into the room, 7cm off the wall): at the right-hand end of the
## front wall, in the corner -- clear of the roulette panel's end, the first-reflection panels, the
## roll board and the acoustic treatment. Where the room has no wall it is a gate on its own legs.
## Every venue has one; a venue whose front wall is taken says where else.
func rig_roulette_door() -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(room_width * 0.5 - 1.0, 0.0, Studio.ROOM_FRONT + 0.07))


## The door as the walker's footprint: solid to its lintel.
func door_solid() -> Dictionary:
	var at := rig_roulette_door()
	return {"c": Vector2(at.origin.x, at.origin.z), "h": RouletteDoor.HALF, "a": at.basis.get_euler().y,
			"top": RouletteDoor.OPENING.y + RouletteDoor.LINTEL}


## Where the board that writes up a Rig Roulette roll hangs, in studio space (its origin the
## middle of its bottom edge): high on the right-hand wall, facing in, its lower edge just above
## the acoustic panels (which stand to 2.1m) and its top just under the ceiling, so the whole
## room can read it with a turn of the head. Not on the front wall, where it was: there it hung
## straight behind the timeline and was the backdrop to the whole set ("the big screen for rig
## randomizer needs to move somewhere else that isnt the backdrop for the main set"). Not the
## left wall either, which has the mirror and, in the studio, a window into the live room.
##
## Where there is no wall and the board stands on its own legs, it stands in from the edge: the
## edge is where a venue puts its own uprights (the rooftop's light poles went through it).
func roll_board_spot() -> Transform3D:
	# The wall is a box 0.1 thick centred on the room's edge, its face 5cm in.
	var inset := 0.45 if back_wall_gear_stands() else 0.11
	return Transform3D(Basis(Vector3.UP, -PI * 0.5),
			Vector3(room_width * 0.5 - inset, 2.14, Studio.ROOM_MID))


## What the gear is made of here (see GearStyle). The studio's own: no change from the
## defaults but a steel edge.
## The twelve colours tracks are shown in here, in TrackColours.STANDARD's order (red, orange,
## yellow, lime, green, teal, sky, blue, violet, magenta, pink, neutral); empty for STANDARD's
## own, which is the studio's.
func track_palette() -> Array:
	return []


func gear_style() -> GearStyle:
	return GearStyle.new()


## Whether what hangs on the control room's back wall elsewhere (the roll board, the Rig Roulette
## panel) stands on posts of its own here, for a venue with no wall to hang it on.
func back_wall_gear_stands() -> bool:
	return false


## Whether the board is drawn as chalk on a slate rather than as a lit screen.
func roll_board_chalky() -> bool:
	return false


## The baskets a ball meets in flight, in studio space (Flight.fly's `hoops`), each with the Hoop
## that sounds it as its "node" when the venue has stood one.
func hoops() -> Array:
	var shape := Hoop.shape(hoop_spot())
	shape["node"] = get_node_or_null("Hoop")
	return [shape]


## Where the mic lives, in studio space: in the clip at the end of the booth's mic stand's boom,
## along it, grille out. Null where there is no stand (the chalk zone only draws one), and the
## mic takes a place on the shelf instead.
func mic_spot() -> Variant:
	var stand := find_child("MicStand", true, false) as Node3D
	if stand == null:
		return null
	var at := stand.transform
	var up := stand.get_parent()
	while up != null and up != self:
		if up is Node3D:
			at = (up as Node3D).transform * at
		up = up.get_parent()
	# Along the boom: out along the stand's -Z and up by its tilt, and the mic's axis (which is
	# its own centre height above its origin) through the clip.
	var along := Basis(Vector3.RIGHT, ZoneKit.MIC_TILT)
	return at * Transform3D(along, ZoneKit.mic_clip() - along * Vector3(0, MicItem.AXIS_HEIGHT, 0))


## Everything the venue puts on the floor that stops a person: the zones' dressing, the prop
## shelf and what stands about the room with it (the door, the hoop, the Tour case, the harp and
## the bells' stand).
## What the walker is given.
func solids() -> Array:
	var out := zone_solids()
	if prop_shelf_solid():
		# The door is as solid as the shelf: a venue that only draws its furniture (the chalk
		# zone) is walked through, door and all.
		out.append(door_solid())
		var spot := prop_shelf_spot()
		out.append({"c": Vector2(spot.origin.x, spot.origin.z),
				"h": Vector2(ZoneKit.SHELF.x, ZoneKit.SHELF.z) * 0.5,
				"a": spot.basis.get_euler().y, "top": ZoneKit.SHELF.y})
		out.append_array(Hoop.solids(hoop_spot()))
		out.append_array(TourCase.solids(tour_case_spot()))
		out.append(ChordHarp.solid(harp_spot()))
		out.append(HandbellItem.stand_solid(bell_stand_spot()))
	return out


## Whether the shelf is a thing you bump into. A venue that only draws it (the chalk zone) says
## no, the way its sketched zones are walked through.
func prop_shelf_solid() -> bool:
	return true


## Build the prop shelf at its spot in the venue's own materials: called by each venue as it
## dresses its zones, with the bricks table's top and legs so the two read as one set, and a lamp
## the colour of the venue's own light.
func _dress_prop_shelf(top: Material, frame: Material, lamp := Color(1.0, 0.76, 0.48)) -> Node3D:
	var holder := Node3D.new()
	holder.name = "PropShelf"
	holder.transform = prop_shelf_spot()
	add_child(holder)
	ZoneKit.prop_shelf(holder, top, frame, lamp)
	# The hoop across the room is the shelf's: its stand in the shelf's frame.
	var hoop := Hoop.new(frame, null, false, lamp)
	hoop.transform = hoop_spot()
	add_child(hoop)
	return holder


## The floor behind the working footprint that a person can walk on to reach the zones: the
## footprint's far edge back to the live room's back, wall to wall. Furniture stays out of it;
## it is for people. In the studio it is the live room; in an open venue, where nothing else
## would stop you, it is where the floor ends being somewhere.
func back_of_house() -> Rect2:
	var front := Studio.ROOM_BACK
	var half := live_room_half() - 0.05
	return Rect2(-half, front, half * 2.0, LIVE_ROOM_BACK - 0.05 - front)


## Every room past the working footprint that a person can walk in, in studio space, each
## meeting the footprint or another along a shared line (see Walker.outline). By default the
## one back_of_house; an arrangement with a room off to the side has more.
func rooms() -> Array[Rect2]:
	return [back_of_house()]


## The floor either side of the working footprint, out to the live room's width, from the
## footprint's front edge to where the back of house begins: for a venue with nothing beside the
## desk but more of itself (a deck, a roof, a plaza), so you can walk round the gear rather
## than only between it.
func beside_the_desk() -> Array[Rect2]:
	var half := live_room_half()
	var cr := room_width * 0.5
	var z := Studio.ROOM_FRONT + 0.05
	var depth := Studio.ROOM_DEPTH - 0.05
	return [Rect2(-half + 0.05, z, half - cr, depth), Rect2(cr - 0.05, z, half - cr, depth)]


## One floor round everything -- the desk, the zones, the live room -- `margin` past them on
## every side: for a venue with nothing round the room but more open ground, so the zones can be
## walked round and the desk approached from in front. It overlaps the footprint rather than
## meeting it, which Walker.outline takes as floor on both sides.
func open_floor(margin: float) -> Rect2:
	var half := live_room_half() + margin
	var front := Studio.ROOM_FRONT + 0.05 - margin
	return Rect2(-half, front, half * 2.0, LIVE_ROOM_BACK + margin - front)


## Half the live room's width, grown with the desk the way the zones are.
func live_room_half() -> float:
	return LIVE_ROOM_HALF + _grow()


## How much each side of the room has grown past the width every venue was drawn round, so the
## back of house and the strips beside the control room keep their room as it widens.
const DRAWN_WIDTH := 6.4


func _grow() -> float:
	return (room_width - DRAWN_WIDTH) * 0.5


## A lit or drawn outline of the working footprint, at floor level, as a set of corners.
func footprint_corners() -> PackedVector2Array:
	var hw := room_width * 0.5 - 0.05
	var front := Studio.ROOM_BACK - 0.05
	var back := Studio.ROOM_FRONT + 0.05
	return PackedVector2Array([Vector2(-hw, back), Vector2(hw, back), Vector2(hw, front),
			Vector2(-hw, front)])


## A mirror in this venue's style, where this venue keeps it. See core/venues/mirror.gd.
func make_mirror(env: Environment) -> Mirror:
	var m := Mirror.new()
	m.name = "Mirror"
	m.rich = rich
	m.environment_from = env
	m.transform = mirror_spot(m.glass_size)
	_frame_mirror(m)
	var board := Wardrobe.new()
	board.name = "Wardrobe"
	_dress_wardrobe(board)
	board.transform = wardrobe_spot(m)
	m.add_child(board)
	m.wardrobe = board
	return m


## Where the wardrobe board hangs, in the mirror's frame: beside the glass on its +X side, at
## hand height, turned a little toward whoever is standing in front of the glass.
func wardrobe_spot(mirror: Mirror) -> Transform3D:
	var beside := mirror.glass_size.x * 0.5 + 0.34
	var hand := 1.25 - mirror.position.y
	return Transform3D(Basis(Vector3.UP, -0.4), Vector3(beside, hand, 0.06))


## The board's materials and ink, in the venue's own style. Left plain by default.
func _dress_wardrobe(_board: Wardrobe) -> void:
	pass


## Where the glass's centre stands, facing into the room. By default on the left wall behind
## the treatment, facing across the room: a step back and a turn left from the mix position,
## clear of every piece of gear in the floor plan.
func mirror_spot(glass: Vector2) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, PI * 0.5),
			Vector3(-room_width * 0.5 + 0.16, 0.14 + glass.y * 0.5, 2.2))


## Build the frame round `mirror`'s glass, as its children. The glass faces +Z and is centred
## on the mirror; a frame stands proud of it, never in front of the glass's face.
func _frame_mirror(_mirror: Mirror) -> void:
	pass


## Four bars round the glass, `bar` wide and `depth` deep, set back so their faces sit `proud`
## in front of the glass, and `inset` over its edge. Shared by the venues whose frames are solid.
static func frame_bars(mirror: Mirror, bar: float, depth: float, proud: float,
		material: Material, inset := 0.0) -> void:
	var w := mirror.glass_size.x - inset * 2.0
	var h := mirror.glass_size.y - inset * 2.0
	for spec in [[Vector3(0, (h + bar) * 0.5, 0), Vector3(w + bar * 2.0, bar, depth)],
			[Vector3(0, -(h + bar) * 0.5, 0), Vector3(w + bar * 2.0, bar, depth)],
			[Vector3((w + bar) * 0.5, 0, 0), Vector3(bar, h, depth)],
			[Vector3(-(w + bar) * 0.5, 0, 0), Vector3(bar, h, depth)]]:
		var piece := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = spec[1]
		piece.mesh = box
		piece.material_override = material
		piece.position = spec[0] + Vector3(0, 0, proud - depth * 0.5)
		mirror.add_child(piece)
