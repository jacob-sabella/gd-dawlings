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
## floor plan never moves for them. The live room is laid out in neighbourhoods (Neighbourhoods,
## docs/architecture.md "Room layout"), three columns either side of two walkways, each a cluster
## round a middle of its own: turn round from the desk and the rhythm section is straight ahead
## (the riser on the left of the middle, the lattice behind on the right, the venue's own
## instrument on the back wall between), tape and toys on the left with the vocal booth behind
## them, harmony and strings round the bricks table on the right with synth and sound design
## behind. Each box is the activity's whole space -- clearance to walk round it included -- from
## the floor up to the height it needs.
##
## Spread out on 2026-10-28 ("EVERYTHING is way too cramped"): the room's pieces stood nose to
## tail along the back wall, 3 to 12 cm apart, and the harp, the music box, the modular and the
## lyric board could not be reached down a 0.9 m walkway.
const ZONES := {
	# A booth 3.4 x 3.1 m: a singer, a stand, the lyric board, room for a talk box, and a door
	# wide enough to walk through without turning sideways.
	&"vocals": AABB(Vector3(-8.7, 0.0, 9.2), Vector3(3.4, 2.6, 3.1)),
	# A riser for a full kit and the drummer's stool, 2.6 m square, at the front of the middle.
	&"drums": AABB(Vector3(-3.4, 0.0, 4.8), Vector3(2.6, 2.8, 2.6)),
	# The lattice, 3.4 m on every side: a 3 m cube of cells and room to reach in from any face.
	&"matrix": AABB(Vector3(0.0, 0.0, 8.6), Vector3(3.4, 3.4, 3.4)),
	# A 1 x 2 m table at waist height, long way back, with walking room all round.
	&"bricks": AABB(Vector3(6.8, 0.0, 4.6), Vector3(1.9, 1.3, 2.9)),
	# A keyboard stand 1.5 m wide against the right-hand wall, modules racked above it.
	&"synth": AABB(Vector3(7.9, 0.0, 10.0), Vector3(0.8, 2.0, 2.0)),
}
## The back-of-house space the zones stand in: from the control room's open rear (the
## footprint's far edge) back to here, and this far either side of centre at the base width.
## 8.4 x 17.6 m: a little over twice the floor it had (4.5 x 14.2).
const LIVE_ROOM_BACK := 12.4
const LIVE_ROOM_HALF := 8.8
## Tall enough for the lattice, a hand raised above it, and the neighbourhoods' banners over that.
const LIVE_ROOM_HEIGHT := 5.0
## The live room as every venue's dressing was first drawn round it, before the spread (half its
## width at the old base room, and its back wall). A venue whose scenery is placed by number scales
## it by the room's size over these, so it fills the bigger room rather than huddling in the old one.
const DRAWN_HALF := 7.1
const DRAWN_BACK := 7.3

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


## The room hears a clip (docs/spatial_loop.md part two, slice 21, idea #5): the master or any
## track over 0 dBFS lifts the practicals by LIFT, falling to nothing over LIFT_SECONDS -- the shape
## of `heard_hit`, a jump and a fall -- and at most once every FLASH_GAP however often it clips. A
## mix clipping on every beat is told once in two seconds, not strobed at.
const LIFT := 0.3
const LIFT_SECONDS := 0.15
const FLASH_GAP := 2.0
## Whether a clip lifts the room at all (COMFORT's "Lift on clip"). Only while `reactive` too.
var lift_on_clip := true
## How far the practicals are lifted now, 0..LIFT, as a share of their own energy.
var lift := 0.0
## How many lifts there have been, for the suite and a shot's log.
var lifts := 0
var _lift_left := 0.0
var _since_lift := INF


## One frame of the room hearing whether anything is over (`over`), `delta` seconds on: a clip
## after FLASH_GAP of none starts a lift; the lift falls away over LIFT_SECONDS.
func hear_clip(over: bool, delta: float) -> void:
	_since_lift += delta
	_lift_left = maxf(_lift_left - delta, 0.0)
	if over and reactive and lift_on_clip and _since_lift >= FLASH_GAP:
		_since_lift = 0.0
		_lift_left = LIFT_SECONDS
		lifts += 1
	if not reactive or not lift_on_clip:
		_lift_left = 0.0
	lift = LIFT * _lift_left / LIFT_SECONDS


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
## into the room. On its trolley (WHEELED), wherever that has been pushed; else where the venue
## stands it.
func prop_shelf_spot() -> Transform3D:
	return _spot_of(&"prop_shelf")


## Where the venue stands the prop shelf until it is pushed somewhere else: the tape and toys
## neighbourhood (Neighbourhoods), against the left wall at the front of the live room, TOYS_IN back
## from the control room's open rear, facing across the neighbourhood's middle to the hoop and the
## Tour case. Turn round from the desk and it is on your right as you come out, short of the booth.
const TOYS_IN := 1.0
## How far across the neighbourhood from the left wall the hoop and the Tour case stand, facing back
## at the shelf and the cassette rack: a throw across the middle.
const TOYS_ACROSS := 3.5


func default_prop_shelf_spot() -> Transform3D:
	var x := -live_room_half() + 0.08 + ZoneKit.SHELF.z * 0.5
	var z := Studio.ROOM_BACK + TOYS_IN
	return Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x, 0, z))


## The wall the shelf at `shelf` (facing +X) has its back to, along x.
static func _toys_wall(shelf: Transform3D) -> float:
	return shelf.origin.x - 0.08 - ZoneKit.SHELF.z * 0.5


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


## Where the mini hoop stands, in studio space: its foot, its board facing into the room. On its
## trolley (WHEELED), wherever that has been pushed; else where the venue stands it.
func hoop_spot() -> Transform3D:
	return _spot_of(&"hoop")


## Where the venue stands the hoop until it is pushed somewhere else: across the tape and toys
## neighbourhood from the shelf the ball lives on, its board facing back at it, level with the
## shelf's far end: a throw across the middle, the toy and the plane on the floor between.
const HOOP_ALONG := 0.4


func default_hoop_spot() -> Transform3D:
	var shelf := default_prop_shelf_spot()
	var x := _toys_wall(shelf) + TOYS_ACROSS + 0.1
	return Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(x, 0, shelf.origin.z + HOOP_ALONG))


## Where the venue's own toy (ToyItem) lies, in studio space: on the floor a little in front of
## the hoop and to its right, where you would leave a ball after shooting -- room enough round it
## for the rooftop's beach ball, clear of the hoop's base.
func toy_spot() -> Transform3D:
	return hoop_spot() * Transform3D(Basis(Vector3.UP, 0.6), Vector3(0.42, 0, 0.5))


## Where the radio plane (RcPlaneItem) waits, in studio space: on the floor further out from the
## hoop than the toy, in the tape and toys neighbourhood's middle, its nose (-Z) pointed back along
## it away from the control room, so a take-off runs down the open floor between the shelf's wall
## and the hoop's side, not into either.
func rcplane_spot() -> Transform3D:
	var at := hoop_spot() * Vector3(0.55, 0, 1.25)
	return Transform3D(Basis(Vector3.UP, PI if _away(at) > 0.0 else 0.0), at)


## Where the Tour case stands, in studio space. On its trolley (WHEELED), wherever that has been
## pushed; else where the venue stands it.
func tour_case_spot() -> Transform3D:
	return _spot_of(&"tour_case")


## Where the venue stands the Tour case until it is pushed somewhere else: in the tape and toys
## neighbourhood beside the hoop, across the middle from the cassette rack, its stencilled front
## facing back at the shelf and the rack -- the run's opening move, where everyone walks past.
const TOUR_CASE_ALONG := 2.0


func default_tour_case_spot() -> Transform3D:
	var shelf := default_prop_shelf_spot()
	var x := _toys_wall(shelf) + TOYS_ACROSS
	# Turned a quarter from identity: the case's front (+Z, tools/blender/tour_case.py) then faces
	# -X, back across the middle at the shelf.
	return Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(x, 0, shelf.origin.z + TOUR_CASE_ALONG))


## Where the chord harp stands (ChordHarp), in studio space. On its trolley (WHEELED), wherever that
## has been pushed; else where the venue stands it.
func harp_spot() -> Transform3D:
	return _spot_of(&"harp")


## The harmony and strings neighbourhood (Neighbourhoods) round the bricks table: the chord harp,
## the music box and the string spool in a row along the table's long side toward the middle of the
## room, HARMONY_AISLE out from its edge, each facing the table across the aisle their players stand
## in; the handbells' stand across the table's far end, facing back along it. So the table is the
## middle, and whoever stands at any of them has the rest round them. The row's pieces stand
## HARMONY_GAP apart, the harp in the middle, the music box toward the control room and the spool
## away from it.
const HARMONY_AISLE := 1.75
const HARMONY_GAP := 0.65
## How far past the table's far end the bells' stand's middle is.
const BELL_BEYOND := 1.25


## Where the venue stands the chord harp until it is pushed somewhere else: its feet on the floor
## under its strings, in the middle of the harmony row, facing the bricks table. In a room with no
## table (the Rig Roulette room), against the back wall on the right, facing it.
func default_harp_spot() -> Transform3D:
	var at := zones()
	if not at.has(&"bricks"):
		var x := live_room_half() - 2.5
		var z := LIVE_ROOM_BACK - 0.05 - 0.08 - (ChordHarp.FOOT.y - ChordHarp.FOOT_Z)
		return Transform3D(Basis(Vector3.UP, PI), Vector3(x, 0, z))
	var c := (at[&"bricks"] as AABB).get_center()
	var side := _table_side(c)
	var x := c.x - side * (ZoneKit.TABLE_TOP.x * 0.5 + HARMONY_AISLE)
	return Transform3D(Basis(Vector3.UP, side * PI * 0.5), Vector3(x, 0, c.z))


## Which way across the room the bricks table at `c` stands from its middle: +1 on the right.
func _table_side(c: Vector3) -> float:
	return 1.0 if c.x >= 0.0 else -1.0


## Which way along the table is away from the control room: +1 back (+Z).
static func _away(c: Vector3) -> float:
	return 1.0 if c.z >= Studio.MIX_POSITION_Z else -1.0


## A spot in the harmony row `along` metres from the harp's middle, away from the control room
## (+) or toward it (-), facing the table as the harp does.
func _harmony_row(along: float) -> Transform3D:
	var harp := default_harp_spot()
	var c := (zones()[&"bricks"] as AABB).get_center()
	return Transform3D(harp.basis, harp.origin + Vector3(0, 0, _away(c) * along))


## Where the handbells' stand stands (HandbellItem.stand), in studio space: on its trolley (WHEELED)
## wherever that has been pushed, else across the bricks table's far end from the control room,
## facing back along it, so the bells are in reach of whoever is at the table and the harp.
const BELL_SIDE := 1.0
const BELL_GAP := 0.65


func bell_stand_spot() -> Transform3D:
	return _spot_of(&"bells")


## Where the venue stands the bells' stand until it is pushed somewhere else. Beside the harp where
## there is no table (the Rig Roulette room), BELL_GAP clear of its plinth.
func default_bell_stand_spot() -> Transform3D:
	var at := zones()
	if not at.has(&"bricks"):
		var along := ChordHarp.FOOT.x + BELL_GAP + HandbellItem.STAND.x * 0.5
		var back := ChordHarp.FOOT_Z - ChordHarp.FOOT.y + HandbellItem.STAND.y * 0.5
		return default_harp_spot() * Transform3D(Basis.IDENTITY, Vector3(BELL_SIDE * along, 0, back))
	var c := (at[&"bricks"] as AABB).get_center()
	var away := _away(c)
	return Transform3D(Basis(Vector3.UP, PI if away > 0.0 else 0.0),
			Vector3(c.x, 0, c.z + away * (ZoneKit.TABLE_TOP.z * 0.5 + BELL_BEYOND)))


## Where handbell `n` (1 to 4) lives, in studio space: on its seat on the stand, mouth down, its
## tab toward the room (HandbellItem.seat).
func bell_spot(n: int) -> Transform3D:
	return bell_stand_spot() * HandbellItem.seat(n)


## Where the music box stands (MusicBox, docs/spatial_loop.md part two, slice 47), in studio space: on
## its trolley (WHEELED) wherever that has been pushed, else in the harmony row on the harp's side
## toward the control room, HARMONY_GAP clear of it, facing the bricks table as the harp does. Null
## where there are no zones to stand it by (the Rig Roulette room).
func music_box_spot() -> Variant:
	return _spot_of(&"music_box")


## Where the venue stands the music box until it is pushed somewhere else; null where it has no table.
func default_music_box_spot() -> Variant:
	if not zones().has(&"bricks"):
		return null
	return _harmony_row(-(ChordHarp.FOOT.x + HARMONY_GAP + MusicBox.FOOT.x))


## Where the string spool stands (RoomString.Spool, docs/spatial_loop.md part two, slice 48), in studio
## space: on its trolley (WHEELED) wherever that has been pushed, else in the harmony row on the harp's
## side away from the control room, HARMONY_GAP clear of it, facing the table: the whole of the middle
## of the live room in front of it to stretch a string across. Null where there are no zones (the Rig
## Roulette room).
func string_spool_spot() -> Variant:
	return _spot_of(RoomString.STATION)


## Where the venue stands the spool until it is pushed somewhere else; null where it has no table.
func default_string_spool_spot() -> Variant:
	if not zones().has(&"bricks"):
		return null
	return _harmony_row(ChordHarp.FOOT.x + HARMONY_GAP + RoomString.SPOOL_FOOT.x)


## The synth and sound design neighbourhood (Neighbourhoods) round the synth zone's keyboard stand
## and the modular wall over it: its middle SYNTH_MIDDLE out from the zone's middle into the room;
## the theremin SYNTH_RING further out, facing the stand across the middle (its player's back to the
## modular, a metre of air round both hands); the grain cloud on the middle's side toward the control
## room and the sampler on the side away from it, each SYNTH_RING from the middle, facing it.
const SYNTH_MIDDLE := 1.7
const SYNTH_RING := 1.3
const SAMPLER_RING := 1.1


## The synth neighbourhood's middle, on the floor, and which way across the room the stand is from
## it (+1 the stand on the right); null where there is no synth zone.
func synth_middle() -> Variant:
	var at := zones()
	if not at.has(&"synth"):
		return null
	var c := (at[&"synth"] as AABB).get_center()
	var side := 1.0 if c.x >= 0.0 else -1.0
	return [Vector3(c.x - side * SYNTH_MIDDLE, 0, c.z), side]


## Where the theremin stands (Theremin, docs/spatial_loop.md part two, slice 50), in studio space: on
## its trolley (WHEELED) wherever that has been pushed, else in the synth neighbourhood, SYNTH_RING out
## from its middle on the side away from the stand, facing it. Its player stands in the middle between
## it and the stand, with a metre of free air round both hands. Null where there is no synth zone (the
## Rig Roulette room).
func theremin_spot() -> Variant:
	return _spot_of(Theremin.STATION)


## Where the venue stands the theremin until it is pushed somewhere else; null where it has no synth zone.
func default_theremin_spot() -> Variant:
	var m: Variant = synth_middle()
	if m == null:
		return null
	var side: float = m[1]
	return Transform3D(Basis(Vector3.UP, side * PI * 0.5), (m[0] as Vector3) - Vector3(side * SYNTH_RING, 0, 0))


## Where the grain cloud stands (GrainCloud, docs/spatial_loop.md part two, slice 54), in studio
## space: on its trolley (WHEELED) wherever that has been pushed, else in the synth neighbourhood on
## its middle's side toward the control room, facing the middle. Null where there is no synth zone
## (the Rig Roulette room).
func grains_spot() -> Variant:
	return _spot_of(GrainCloud.STATION)


## Where the venue stands the grain cloud until it is pushed somewhere else; null where it has no
## synth zone.
func default_grains_spot() -> Variant:
	var m: Variant = synth_middle()
	if m == null:
		return null
	var mid: Vector3 = m[0]
	var away := _away(mid)
	return Transform3D(Basis(Vector3.UP, 0.0 if away > 0.0 else PI), mid - Vector3(0, 0, away * SYNTH_RING))


## Where the modular wall hangs (ModularWall, docs/spatial_loop.md part two, slice 51), in studio
## space: the synth zone's module rack over the keyboard stand (ZoneKit.keyboard_stand), its panel's
## face MODULAR_BACK in from the zone's middle toward the wall behind the stand and its foot
## MODULAR_BOTTOM up, over the stand's upper deck, its front (+Z) out over the decks toward whoever
## plays, so its touch keys lie on the upper deck under it; along the stand by ModularWall.OFF_MIDDLE,
## so the panel and the plaque beside it stand over the stand together. Mounted in the zone, not a
## trolley: the stand is the venue's, and the rack's own dressing gives way to it (ZoneKit.yield_rack).
## Null where there is no synth zone (the Rig Roulette room).
const MODULAR_BACK := 0.27
const MODULAR_BOTTOM := 1.26


func modular_spot() -> Variant:
	var at := zones()
	if not at.has(&"synth"):
		return null
	var c := (at[&"synth"] as AABB).get_center()
	return Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(c.x + MODULAR_BACK, MODULAR_BOTTOM,
			c.z - ModularWall.OFF_MIDDLE))


## Where the lyric board stands (LyricBoard, docs/spatial_loop.md part two, slice 56), in studio space:
## in the vocal booth, LyricBoard.IN_BOOTH from its floor's middle, across the mic stand's foot from
## where the singer stands and in line with it, its face (+Z) back toward the singer. Mounted in the
## zone, not a trolley: the booth is the venue's. Null where there is no booth (the Rig Roulette room).
## It stands on what the mic stand stands on (the studio's felt, a millimetre over the floor
## elsewhere), so its foot is not in the floor's plane.
func lyrics_spot() -> Variant:
	var at := zones()
	if not at.has(&"vocals"):
		return null
	var c := (at[&"vocals"] as AABB).get_center()
	var floor_y := 0.001
	var stand := find_child("MicStand", true, false) as Node3D
	if stand != null:
		var y := stand.position.y
		var up := stand.get_parent()
		while up != null and up != self:
			if up is Node3D:
				y += (up as Node3D).position.y
			up = up.get_parent()
		floor_y = y
	return Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(c.x, floor_y, c.z) + LyricBoard.IN_BOOTH)


## Where the marble run stands (MarbleRun, docs/spatial_loop.md part two, slice 49), in studio space:
## the lattice zone's cube of cells, on the floor at its tray (MarbleRun.spot_in), which stands at the
## cube's face toward the control room off to one side of its middle, +Z out of that face toward the
## desk and the cells behind it; so whoever comes back from the desk meets it with the whole lattice
## behind it and the rooms beyond still seen past it. Its seat is in front, between the lattice and
## the control room (in front of the glass in studio:2, which brings it in close). Mounted in the
## zone, not a trolley: the lattice is the venue's. Null where there is no lattice (the Rig Roulette
## room).
func marbles_spot() -> Variant:
	var at := zones()
	if not at.has(&"matrix"):
		return null
	return MarbleRun.spot_in(at[&"matrix"])


## Where the cassette rack stands (CassetteRack, docs/spatial_loop.md part two, slice 23), in
## studio space: on its trolley (WHEELED) wherever that has been pushed, else on the floor beside the
## prop shelf, RACK_GAP clear of it on the side away from the control room, its back in line with the
## shelf's against the same wall and facing into the room the same way. So the clips the band pulls
## out of the timeline stand beside the toys, where everyone walks past.
const RACK_GAP := 0.65


func cassette_rack_spot() -> Transform3D:
	return _spot_of(&"cassette_rack")


## Where the venue stands the cassette rack until it is pushed somewhere else: beside where it
## stands the prop shelf.
func default_cassette_rack_spot() -> Transform3D:
	var along := ZoneKit.SHELF.x * 0.5 + RACK_GAP + CassetteRack.FOOT.x
	return default_prop_shelf_spot() * Transform3D(Basis.IDENTITY,
			Vector3(-along, 0, -ZoneKit.SHELF.z * 0.5 + CassetteRack.FOOT.y))


## Where the sampler stands (Sampler, docs/spatial_loop.md part two, slice 26), in studio space: on
## its trolley (WHEELED) wherever that has been pushed, else in the synth neighbourhood on its
## middle's side away from the control room, SAMPLER_RING out, facing the middle: the pads, the
## grain cloud and the modular one turn apart. Null where there is no synth zone (the Rig Roulette
## room has no zones).
func sampler_spot() -> Variant:
	return _spot_of(&"sampler")


## Where the venue stands the sampler until it is pushed somewhere else; null where it has no synth
## zone.
func default_sampler_spot() -> Variant:
	var m: Variant = synth_middle()
	if m == null:
		return null
	var mid: Vector3 = m[0]
	var away := _away(mid)
	return Transform3D(Basis(Vector3.UP, PI if away > 0.0 else 0.0), mid + Vector3(0, 0, away * SAMPLER_RING))


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


## The bricks table in three bands (docs/spatial_loop.md part two, slice 30), each a rectangle on
## its top that one zone-mounted station has to itself, in the table's own frame (`bricks_table`):
## x across it, + toward the long edge far from the middle of the room, and z along it, + away
## from the control room. The fifths wheel's board and its strut at the end nearest the control
## room (where `wheel_spot` stands it, WHEEL_IN in from that end); the section blocks along the
## far long edge, past the wheel; and the ledge for chord bricks (slice 31) along the near long
## edge, beside them, where a player at the blocks has it under their hands. Seen from there, the
## wheel is at the near left end. Clear of each other by BAND_GAP or more.
const TABLE_BANDS := {
	&"wheel": Rect2(-0.47, -1.0, 0.94, 0.56),
	&"sections": Rect2(0.12, -0.4, 0.36, 1.38),
	&"ledge": Rect2(-0.48, -0.4, 0.3, 1.38),
}
const BAND_GAP := 0.04


## The bricks table's top, in studio space: the middle of its top, square to the room (x across
## it, z along it, as TABLE_BANDS has them). Null where there is no bricks table.
func bricks_table() -> Variant:
	var at := zones()
	if not at.has(&"bricks"):
		return null
	var c := (at[&"bricks"] as AABB).get_center()
	return Transform3D(Basis.IDENTITY, Vector3(c.x, ZoneKit.TABLE_HEIGHT, c.z))


## Where band `id` (TABLE_BANDS) is on the bricks table, in studio space: on its top at the band's
## middle, its front (+Z) toward the near long edge, where a player stands to use it, so its +X runs
## along the table away from the wheel, left to right for them. Null where there is no table.
func band_spot(id: StringName) -> Variant:
	var table: Variant = bricks_table()
	if table == null or not TABLE_BANDS.has(id):
		return null
	var band: Rect2 = TABLE_BANDS[id]
	var middle := band.get_center()
	return (table as Transform3D) * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(middle.x, 0, middle.y))


## Where the section blocks stand (SectionBlocks, slice 30): their band's middle on the bricks
## table, along its far long edge. Null where there is no bricks table.
func sections_spot() -> Variant:
	return band_spot(&"sections")


## Where the ledge for chord bricks stands (ChordLedge, slice 31): its band's middle on the bricks
## table, along its near long edge. Null where there is no bricks table.
func ledge_spot() -> Variant:
	return band_spot(&"ledge")


## The circle of hand drums on the drum riser (HandDrum, docs/spatial_loop.md part two, slice 40):
## how far each drum's middle is from the ring's, and the most a drum stands out from its own middle
## on the floor (the low conga's belly, the cajón's corners on their stand), for the walker's solids.
const DRUM_RING := 0.72
const DRUM_FOOT := 0.19


## Where the ring of hand drums stands in a drums zone `box` (studio space): `n` -1 is the ring's
## middle `floor` up (the riser's top, or the floor where the riser is only drawn: `drum_floor`), its
## front (+Z) toward the mix position (square to the room, the nearest of the four ways), where the
## station's seat is; `n` 0 to 3 is HandDrum.KINDS[n]'s place round it, each DRUM_RING out on a
## diagonal, the djembe and the cajón in front, the two congas, the tallest, behind, every drum's
## front (an item's -Z) toward the ring's front, so its jack and the cajón's face are seen from the
## seat.
static func drum_ring(box: AABB, n := -1, floor := ZoneKit.RISER_HEIGHT) -> Transform3D:
	var c := box.get_center()
	var toward := Vector2(0.0, Studio.MIX_POSITION_Z) - Vector2(c.x, c.z)
	var yaw := snappedf(atan2(toward.x, toward.y), PI * 0.5)
	var middle := Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, floor, c.z))
	if n < 0 or n >= 4:
		return middle
	var corner: Vector2 = [Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1)][n]
	var along := corner.normalized() * DRUM_RING
	return middle * Transform3D(Basis(Vector3.UP, PI), Vector3(along.x, 0, along.y))


## Where the ring of hand drums stands here (`drum_ring`), in studio space: its middle (`n` -1, the
## station `drums`) or drum `n`'s place. Null where the venue has no drum riser (the Rig Roulette room
## has no zones).
func drum_circle_spot(n := -1) -> Variant:
	var at := zones()
	if not at.has(&"drums"):
		return null
	return drum_ring(at[&"drums"], n, drum_floor())


## How high the ring of hand drums stands: the riser's top where the riser is a step the walker
## climbs (`zone_solids`), and the floor where it is only drawn (the chalk zone), so a drum stands
## on what a person stands on beside it. 0 where there is no drums zone.
func drum_floor() -> float:
	var at := zones()
	if not at.has(&"drums"):
		return 0.0
	var c: Vector3 = (at[&"drums"] as AABB).get_center()
	return Walker.ground_of(zone_solids(), Vector2(c.x, c.z))


## The looper (Looper, docs/spatial_loop.md part two, slice 45) on its stand at the drum riser's front
## corner: how far out along both of the ring's axes its feet's middle is, inside the riser's edge.
const LOOPER_CORNER := 0.98


## Where the looper stands in a drums zone `box` (studio space), on `floor` (`drum_ring`'s): at the
## riser's front corner on the ring's left as you face its front, toward the room's middle in the
## studio, its front (+Z) the ring's, so it is played from the floor in front of the riser.
static func looper_at(box: AABB, floor := ZoneKit.RISER_HEIGHT) -> Transform3D:
	return drum_ring(box, -1, floor) * Transform3D(Basis.IDENTITY, Vector3(-LOOPER_CORNER, 0, LOOPER_CORNER))


## Where the looper stands here (`looper_at`), in studio space: the station `looper`. Null where the
## venue has no drum riser.
func looper_spot() -> Variant:
	var at := zones()
	if not at.has(&"drums"):
		return null
	return looper_at(at[&"drums"], drum_floor())


## The venue's own instrument (VenueInstrument, docs/spatial_loop.md part two, slices 42 and 43, idea
## #19): {"kind" (one of VenueInstrument.KINDS), "spot" (the set's frame in studio space, its front,
## +Z, toward whoever plays it, on the floor under the row's middle), and optionally "count" (bars,
## up to VenueInstrument.MOST), "low" (the note its first bar's tonic is nearest), "title" and
## whatever of its kind it changes (how high it hangs, `at`)}. Every venue of Venue.IDS has one; empty
## for none, the Rig Roulette room, which says nothing of one.
func instrument() -> Dictionary:
	return {}


## Where the venue's instrument stands (the station `venue`), in studio space: its `spot`, or null
## where it has none.
func instrument_spot() -> Variant:
	var spec := instrument()
	return spec["spot"] if spec.get("spot") is Transform3D else null


## How far the instruments set against a wall stand off it, bars to its face (m).
const INSTRUMENT_OFF_WALL := 0.12
## How far the back wall's instrument stands to the kit's side of the lattice (m), where a venue
## measures it from the lattice: behind the riser, the rhythm neighbourhood's back wall.
const INSTRUMENT_BESIDE_LATTICE := 2.1


## A spot for an instrument against the live room's back wall, behind the drum riser beside the
## lattice (the rhythm neighbourhood's back wall), its front toward the desk, its bars `depth` deep: where the studio's tubular bells, the
## cave's crystals, the grid's neon bars, the chalk zone's xylophone, the station's hull panels, the
## greenhouse's pots, the stage's cymbals and gong and the desert's ringing stones stand (the
## speakeasy's piano stands in the same place, by ClubVenue.piano_case's own reckoning). Clear of
## both zones' boxes, of the harp and the bells' stand on the far side of the lattice, and of the
## walk between.
func back_wall_instrument(depth: float) -> Transform3D:
	var at := zones()
	var x := (ZONES[&"drums"] as AABB).get_center().x
	if at.has(&"drums"):
		x = (at[&"drums"] as AABB).get_center().x
	return Transform3D(Basis(Vector3.UP, PI), Vector3(x, 0, LIVE_ROOM_BACK - 0.05 - INSTRUMENT_OFF_WALL - depth))


## A spot for an instrument against a side wall of the floor beside the desk (`side` -1 the left, 1
## the right), `along` its middle's z, its bars `depth` deep, its front into the room: where the
## garden's chimes, the cabin's icicles and the loft's steam pipes hang and the dome's glass stands.
func side_wall_instrument(side: float, along: float, depth: float) -> Transform3D:
	var x := signf(side) * (live_room_half() - 0.05 - INSTRUMENT_OFF_WALL - depth)
	return Transform3D(Basis(Vector3.UP, -signf(side) * PI * 0.5), Vector3(x, 0, along))


## The venue's instrument as a walker solid, where it is solid (`prop_shelf_solid`): a person walks up
## to it rather than through it, and a throw bounces off it.
func instrument_solids() -> Array:
	var spec := VenueInstrument.spec_of(self)
	if spec.is_empty() or not prop_shelf_solid():
		return []
	return [VenueInstrument.solid(spec)]


## The venue's weather (Weather, docs/spatial_loop.md part two, slice 44, idea #20), in an arrangement
## that has some: {"kind" (one of Weather.KINDS), "spot" (the switch's frame in studio space, on the
## floor under it, its front +Z into the room), "sill" (the switch's height), "glass" (the pane the
## drops land on, a frame at its middle, X across, Y up, +Z into the room) and "size" (the pane's
## width and height), or "pools" (points on the water the cave's drips fall into), and optionally
## "post" (it stands on a post of its own, at the floor's edge), "switch_z" and "plaque_z" (how far
## out of the spot's front the switch and the plaque are) and "low" (the note its lowest drop's tonic
## is nearest)}. Empty for none: every arrangement but the loft's Thunderstorm, the greenhouse's Rain,
## the cabin's Snowy night and the cave's grotto and glowworm lake.
func weather() -> Dictionary:
	return {}


## Where the venue's weather's switch stands (the station `weather`), in studio space: its `spot`, or
## null where it has none.
func weather_spot() -> Variant:
	var spec := weather()
	return spec["spot"] if spec.get("spot") is Transform3D else null


## The weather's switch's post as a walker solid, where it stands on one and the room is solid.
func weather_solids() -> Array:
	var post := Weather.solid(Weather.spec_of(self))
	if post.is_empty() or not prop_shelf_solid():
		return []
	return [post]


## The floor's height at `p` (studio space): the top of whatever the venue stands there that a person
## steps up onto (the drum riser), or 0, as the walker finds it (Walker.ground_of, `solids`). Where a
## station's seat is put down (Stations.seat), and so a headset's play space on a travel there.
func floor_at(p: Vector2) -> float:
	return Walker.ground_of(solids(), p)


## The stations and the furniture of the back of house that stand on the floor by themselves, and
## so are pushed about it like the gear in the control room: each is a trolley of the studio's
## (Studio.live_pieces), and its `*_spot` is wherever that trolley has been wheeled. The venue says
## only where each stands until somebody moves it (`default_spot`), and null where it has no room
## for it at all. The fifths wheel is not here: it is mounted on the bricks table, which is the
## venue's and does not move.
const WHEELED: Array[StringName] = [&"harp", &"bells", &"cassette_rack", &"sampler", &"tour_case",
		&"prop_shelf", &"hoop", &"music_box", &"strings", &"theremin", &"grains"]


## Where the venue stands wheeled piece `id` (WHEELED) until it is pushed somewhere else, in
## studio space; null where the venue has no room for it.
func default_spot(id: StringName) -> Variant:
	match id:
		&"harp":
			return default_harp_spot()
		&"bells":
			return default_bell_stand_spot()
		&"cassette_rack":
			return default_cassette_rack_spot()
		&"sampler":
			return default_sampler_spot()
		&"tour_case":
			return default_tour_case_spot()
		&"prop_shelf":
			return default_prop_shelf_spot()
		&"hoop":
			return default_hoop_spot()
		&"music_box":
			return default_music_box_spot()
		&"strings":
			return default_string_spool_spot()
		&"theremin":
			return default_theremin_spot()
		&"grains":
			return default_grains_spot()
	return null


## The trolley that wheeled piece `id` stands on, in the studio this venue stands in; null in no
## studio (a venue made to be measured) or one that has not built it (AR).
func _trolley_of(id: StringName) -> Trolley:
	var studio := get_parent() as Studio
	if studio == null or studio.studio_set == null:
		return null
	var t: Trolley = studio.live_pieces.get(id)
	return t if t != null and is_instance_valid(t) else null


## Where wheeled piece `id` stands, in studio space: where its trolley has been wheeled while it
## is out in this venue, else the venue's own `default_spot` for it.
func _spot_of(id: StringName) -> Variant:
	var t := _trolley_of(id)
	if t != null and t.visible:
		return transform.affine_inverse() * get_parent().studio_set.transform * t.transform
	return default_spot(id)


## Where the stage table stands (StageTable, docs/spatial_loop.md slice 18), in studio space: on
## its trolley in the control room, which is the studio's furniture and not the venue's, so read
## from the studio this venue stands in, wherever the trolley has since been wheeled. Its front
## (+Z) faces the mix position. Null for a venue in no studio, or one with no table (AR).
func stage_table_spot() -> Variant:
	var studio := get_parent() as Studio
	if studio == null or studio.stage_trolley == null or not is_instance_valid(studio.stage_trolley):
		return null
	return transform.affine_inverse() * studio.studio_set.transform * studio.stage_trolley.transform


## Where the EQ wall stands (EqWall, docs/spatial_loop.md part two, slice 36), in studio space: on
## its trolley at the control room's side wall, which is the studio's furniture and not the venue's,
## so read from the studio this venue stands in, wherever the trolley has since been wheeled. Its
## front (+Z) faces into the room. Null for a venue in no studio, or one with no wall (AR).
func eq_wall_spot() -> Variant:
	var studio := get_parent() as Studio
	if studio == null or studio.eq_wall_trolley == null or not is_instance_valid(studio.eq_wall_trolley):
		return null
	return transform.affine_inverse() * studio.studio_set.transform * studio.eq_wall_trolley.transform


## Where the DJ platter stands (Platter, docs/spatial_loop.md part two, slice 27), in studio space:
## on the leaf of the tape deck's cart, beside the deck, which is the studio's furniture and not the
## venue's, so read from the studio this venue stands in, wherever the cart has since been wheeled.
## Its front (+Z) is the cart's. Null for a venue in no studio, or one with no cart (AR).
func platter_spot() -> Variant:
	var studio := get_parent() as Studio
	if studio == null or studio.platter == null or not is_instance_valid(studio.platter) \
			or studio.deck_trolley == null or not is_instance_valid(studio.deck_trolley):
		return null
	return transform.affine_inverse() * studio.studio_set.transform * studio.deck_trolley.transform * Platter.ON_CART


## Where the session in miniature lies at home (MiniatureItem, docs/spatial_loop.md part two, slice
## 34), in studio space: on the desk's left wing (Studio.desk_wing), the little table bolted to the
## console's left end, which is the studio's furniture and not the venue's, so read from the studio
## this venue stands in, wherever the desk has grown to. Its reader's edge (an item's -Z) toward the
## mix position. Null for a venue in no studio, or one with no wing (AR).
func miniature_spot() -> Variant:
	var studio := get_parent() as Studio
	if studio == null or studio.desk_wing == null or not is_instance_valid(studio.desk_wing):
		return null
	return transform.affine_inverse() * studio.studio_set.transform * studio.desk_wing.transform \
			* Transform3D(Basis(Vector3.UP, PI), Vector3(0, Studio.WING_TOP, 0))


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
	# Its frame stands in the wall's face; what a person walks into is the part on the floor.
	var c := Vector2(at.origin.x, at.origin.z)
	if absf(at.basis.get_euler().y) < 0.01:
		c.y = maxf(c.y, Studio.ROOM_FRONT + 0.05 + RouletteDoor.HALF.y + 0.005)
	return {"c": c, "h": RouletteDoor.HALF, "a": at.basis.get_euler().y,
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
## shelf and what stands about the room with it (the door, the hoop, the Tour case, the harp, the
## bells' stand and the cassette rack).
## What the walker is given.
##
## In a studio the free-standing ones (WHEELED) are left out: they stand on trolleys there, and the
## walker already stops at every trolley in the floor plan, wherever it has been pushed.
func solids() -> Array:
	var out := zone_solids()
	out.append_array(instrument_solids())
	out.append_array(weather_solids())
	if prop_shelf_solid():
		# The door is as solid as the shelf: a venue that only draws its furniture (the chalk
		# zone) is walked through, door and all.
		out.append(door_solid())
		if _trolley_of(&"prop_shelf") == null:
			out.append_array(wheeled_solids())
	return out


## The free-standing pieces (WHEELED) where they stand now, as walker footprints with how tall each
## is: what a thrown thing lands on top of or bounces off the side of (Flight.fly), which a
## trolley's footprint alone does not say. None where they are only drawn (`prop_shelf_solid`).
func wheeled_solids() -> Array:
	var out: Array = []
	if not prop_shelf_solid():
		return out
	var spot := prop_shelf_spot()
	out.append({"c": Vector2(spot.origin.x, spot.origin.z),
			"h": Vector2(ZoneKit.SHELF.x, ZoneKit.SHELF.z) * 0.5,
			"a": spot.basis.get_euler().y, "top": ZoneKit.SHELF.y})
	out.append_array(Hoop.solids(hoop_spot()))
	out.append_array(TourCase.solids(tour_case_spot()))
	out.append(ChordHarp.solid(harp_spot()))
	out.append(HandbellItem.stand_solid(bell_stand_spot()))
	out.append(CassetteRack.solid(cassette_rack_spot()))
	var sampler_at: Variant = sampler_spot()
	if sampler_at != null:
		out.append(Sampler.solid(sampler_at))
	var box_at: Variant = music_box_spot()
	if box_at != null:
		out.append(MusicBox.solid(box_at))
	var spool_at: Variant = string_spool_spot()
	if spool_at != null:
		out.append(RoomString.spool_solid(spool_at))
	var theremin_at: Variant = theremin_spot()
	if theremin_at != null:
		out.append(Theremin.solid(theremin_at))
	var grains_at: Variant = grains_spot()
	if grains_at != null:
		out.append(GrainCloud.solid(grains_at))
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


## How much each side of the room has grown past its base width, so the back of house and the
## strips beside the control room keep their room as it widens with the desk.
const DRAWN_WIDTH := Studio.ROOM_WIDTH


func _grow() -> float:
	return (room_width - DRAWN_WIDTH) * 0.5


## How high the neighbourhoods' banners hang here (Neighbourhoods.sign_spot): under whatever is
## overhead. A venue with something lower over the live room (a gallery, eaves) says so.
func sign_height() -> float:
	return Neighbourhoods.SIGN_HEIGHT


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
