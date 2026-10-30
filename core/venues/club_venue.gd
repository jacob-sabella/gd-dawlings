class_name ClubVenue
extends Venue

## A jazz club after hours, the last set long over. A basement of old brick over a walnut
## wainscot, a pressed-tin ceiling gone dark with smoke, a herringbone floor worn pale where the
## dancing was. The stage is the drum riser, a red velvet curtain behind it, and one spot still
## burning on it from the ceiling, its beam hanging in the haze. Along the left wall, leather
## booths with a marble table in each and a candle guttering; along the right, the bar: a walnut
## counter on a brass foot rail, its stools turned up on top of it, the back bar's bottles lit
## from under their shelves against a mirror. "after hours" in pink neon over the door you came
## in by. No windows: the street is upstairs.
##
## Three arrangements (Venue.VARIANTS): AFTER_HOURS, as above; SHOWTIME, the same room open
## and set for the show (the stools down, bistro tables and bentwood chairs set out in the
## corners with a candle lit on every table, the piano's lid up with a score on its desk and the
## bass stood ready beside it, the curtain washed in colour from a rig of cans, footlights along
## the stage, a marquee board, "LIVE tonight" in neon ringed with chasing bulbs, where the
## after-hours sign was, and the back bar turned up); and SPEAKEASY, the basement in 1920: its
## front a wall of bookcases, one of them swung open on the stair to the street, oak barrels
## racked against the wall and crates of "maple syrup", dark panelling to above the head with
## brass deco strips, bare joists overhead and Edison bulbs on long cords, a sunburst mirror over
## the desk and another crowning the back bar, a card table under a green shade where the piano
## was, a gramophone, and the smoke hanging in layers under the joists.

const AFTER_HOURS := 0
const SHOWTIME := 1
const SPEAKEASY := 2

## As tall as the live room is now (Venue.LIVE_ROOM_HEIGHT): the pressed tin over the lattice, the
## banners and a hand raised over both.
const HEIGHT := LIVE_ROOM_HEIGHT
const WALL := 0.3
## The front wall, in front of the desk: the footprint's front edge.
const FRONT := Studio.ROOM_FRONT
## The wainscot's height, and how proud of the brick it stands.
const WAINSCOT := 1.1
## The bar: how far its counter's front face stands in from the right-hand wall, its ends (z), its
## height. Measured from the wall, so it stays in the strip beside the control room however wide the
## room is drawn (it was a number for the old 8 m footprint, and stood inside the new one).
const BAR_IN := 2.2
const BAR_FROM := -2.0
const BAR_TO := 2.6
const BAR_TOP := 1.08
const COUNTER_DEPTH := 0.6
## The booths along the left wall: each one's centre (z). A booth is two benches facing each
## other across a table, its benches BENCH long out from the wall.
const BOOTHS := [-1.0, 1.4]
const BENCH := 1.3
## How far each bench's seat front is from the booth's centre.
const BENCH_GAP := 0.3
## The spot: where it hangs, and the stage it is on.
const SPOT_AT := Vector3(-2.1, HEIGHT - 0.3, 3.0)
## The upright piano pushed back against the ends of the two booths' back-to-back benches,
## between their openings, its keys to the room; the double bass laid on the floor past the far
## booth, its scroll to the wall, clear of the keys' middle octave, where a person stands to play it
## (`instrument`), and of the way from the strip into the back of house. Both in the side strip:
## the back of house is kept clear for people.
const PIANO_Z := 0.1
const PIANO_DEPTH := 0.6
const PIANO_WIDTH := 1.5
## The piano's keys in its case's frame (club.glb's Piano, its keys toward +Z): their middle this far
## in front of the case's middle, and the middle of the octave that is the club's instrument (club.py's
## GAP, key 26 of the keyboard's 52 to key 33, A to A) this far along it.
const PIANO_KEYS_OUT := PIANO_DEPTH * 0.5 + 0.2
const PIANO_OCTAVE := -0.68 + 1.36 * 30.0 / 52.0
## How far the case stands off the back wall in the speakeasy, where the piano stands by the stage.
const PIANO_OFF_WALL := 0.04
## The bass's foot: in from the strip's control-room edge, and along (z) past the far booth.
const BASS_AT := Vector2(1.05, 3.3)
const BASS_YAW := PI - 0.1
const BASS_LENGTH := 1.95
const MOTES := 180
## Where the after-hours sconces hang along each side wall (z), and how high.
const SCONCES := [5.0, 8.0]
## The cans on the tin over each neighbourhood of the back of house, aimed down at its middle: each
## (x, z) from the zones they light, so a moved zone carries its light.
const HOUSE_CAN_DROP := 0.35
const MODELS := "res://assets/models/"

## Showtime: the bistro tables set out in the strips' free corners, each as (x from the side
## wall it is nearer, z) in the strip -- x measured in from the footprint's edge, so a wider
## room keeps them clear of the gear -- and which way round each of its two chairs stands
## (radians about the table, 0 toward +X, PI/2 toward +Z).
const SHOW_TABLES := [
	[-1, 0.75, -3.0, [PI, PI * 0.5]],
	[-1, 0.75, 3.15, [PI, -PI * 0.5]],
	[1, 1.1, -3.25, [PI * 0.5, PI]],
	[1, 2.4, -3.25, [PI * 0.5, 0.0]],
]
## How far a chair's seat stands from its table's middle.
const CHAIR_OUT := 0.5
## Showtime: the bench before the keys, slid along toward their bass end (BENCH_ALONG) so the middle
## octave, the club's instrument, has room to stand at; and the bass in its stand beside them.
const BENCH_OUT := 0.36
const BENCH_ALONG := 0.75
const BASS_STAND := Vector2(0.5, -1.2)
## Showtime: a second bar of cans in front of the spot's, washing the stage and curtain.
const RIG_Z := 4.0
const CAN_COLOURS := [Color(1.0, 0.25, 0.55), Color(1.0, 0.6, 0.2), Color(0.3, 0.45, 1.0), Color(1.0, 0.6, 0.2),
		Color(1.0, 0.25, 0.55)]
## How long each set of the marquee's bulbs stays lit before the other set takes over.
const CHASE := 0.32
## The marquee's bulbs' colour, and its neon's: LIVE in red, tonight in blue (unshaded, so
## these are how bright they burn).
const BULB := Color(1.0, 0.78, 0.5)
const NEON := [Color(3.4, 0.35, 0.25), Color(0.5, 1.1, 3.4)]

## Speakeasy: a bookcase bay (club_speakeasy.glb's Bookcase), and the bays along the left strip's
## front wall: the middle one is the door to the stair, swung open DOOR_OPEN about its front
## corner on the left, so the way through shows to the room.
const BAY := Vector3(1.0, 2.5, 0.34)
const BAYS := 3
const DOOR_BAY := 1
const DOOR_OPEN := 1.35
## The stair behind it, up to the street: how deep the passage runs, each step's rise and tread.
const STAIR_DEPTH := 2.6
const RISE := 0.19
const TREAD := 0.28
## The panelling's height, all round.
const PANEL := 2.25
## The barrels racked on their sides against the right strip's front wall, heads to the room.
const BARREL_R := 0.305
const BARREL_LONG := 0.86
const CRADLE := 0.07
## The card table where the piano was, and its chairs round three sides (the fourth to the
## booths' bench ends).
## Its width across the rail: club_speakeasy.glb's table drawn smaller (CARD_SCALE) to sit in
## the strip, its height kept.
const CARD_SCALE := 0.75
const CARD_TABLE := 0.98
const CARD_CHAIRS := [0.0, 1.35, -1.35]
const CARD_CHAIR_OUT := 0.78
## The gramophone's spot in the left strip's front corner (in from the footprint, out from the
## front wall) and the barrel table's in the strip's back corner.
const GRAMOPHONE_AT := Vector2(0.5, 1.05)
const BARREL_TABLE_AT := Vector2(0.85, 3.0)
const SMOKE := 80
## Showtime: the points of light in the show cloth.
const STARS := 260
const CURTAIN_FOLDS := 2.2
const CURTAIN_DEPTH := 0.09

var spot: SpotLight3D
## The booths' candles, for their flicker.
var candles: Array[OmniLight3D] = []
## Where every bottle on the back bar stands (a MultiMesh's own transforms are not kept headless).
var bottle_spots: Array[Transform3D] = []
## The heights the bottles stand at: the shelves', and the back bar's top.
var bottle_levels: Array[float] = []
## Where each glass was left, on the booth tables and the bar.
var glass_spots: Array[Vector3] = []
## Where each mote of dust in the spot's beam is put (it wanders a little round it).
var motes: Array[Vector3] = []
var _t := 0.0
## Showtime: the curtain's washes and the rig's cans (their energies as built, for pulse()),
## the marquee's two sets of bulbs and its neon.
var washes: Array[SpotLight3D] = []
var _wash_energy: Array[float] = []
var _bulbs: Array[StandardMaterial3D] = []
var _neon: Array[StandardMaterial3D] = []
var _level := 0.0
var _stars: ShaderMaterial
## Speakeasy: the bulbs' lights, which waver a little on the old wiring.
var bulb_lights: Array[Light3D] = []
var _bulb_energy: Array[float] = []


func venue_id() -> StringName:
	return &"club"


## Road cases: black tolex over ply, chrome corners and an amber stage light along every edge,
## the way a band's own gear stands on a club's stage.
func gear_style() -> GearStyle:
	var tolex := GearStyle.paint(Color(0.05, 0.05, 0.055), 0.85, 0.0)
	tolex.normal_texture = Materials.grain("tolex", 1.6, 2.4)
	tolex.normal_scale = 0.9
	return GearStyle.new() \
			.with("furniture", tolex) \
			.with("chassis", GearStyle.paint(Color(0.08, 0.07, 0.068), 0.7, 0.25)) \
			.with("brushed", GearStyle.metal(Color(0.78, 0.78, 0.8), 0.18)) \
			.with("trim", GearStyle.glow(Color(1.0, 0.45, 0.12), 1.6)) \
			.with("end_cheek", GearStyle.scan("black_walnut_veneer_01", 0.6, Color(0.36, 0.26, 0.2))) \
			.with("lamp_shade", GearStyle.metal(Color(0.75, 0.55, 0.25), 0.35)) \
			.with("loom_band", GearStyle.glow(Color(1.0, 0.45, 0.12), 1.2)) \
			.with("knob_cap", GearStyle.paint(Color(0.22, 0.05, 0.04), 0.35, 0.0))


## Black tolex like the road cases, cream lettering, amber arrows.
func _dress_wardrobe(board: Wardrobe) -> void:
	board.board_material = GearStyle.paint(Color(0.05, 0.05, 0.055), 0.85, 0.0)
	board.ink = Color(0.95, 0.9, 0.8)
	board.accent = Color(1.0, 0.55, 0.2)
	board.board_ink_fade = Color(0.4, 0.38, 0.36)


func dress(env: Environment, key: DirectionalLight3D) -> void:
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.42, 0.3)
	# A touch more than a basement's: the room is twice the floor it was, and its far corners are
	# metres further from any lamp.
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	# The haze the last set left behind, enough to soften the room's far corners.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.05, 0.035, 0.03)
	env.fog_depth_begin = 3.0
	env.fog_depth_end = 30.0
	if rich:
		env.ssao_enabled = true
		env.ssao_intensity = 1.4
	# No sun down here: the key is the room's general light, all but off.
	key.light_color = Color(1.0, 0.8, 0.6)
	key.light_energy = 0.04
	key.shadow_enabled = false
	key.basis = Basis.looking_at(Vector3(0.3, -1.0, 0.4), Vector3.FORWARD)
	match variant:
		SHOWTIME:
			# The house lights up for the show, warm, and the air clearer: no set has played yet.
			env.ambient_light_color = Color(0.72, 0.46, 0.3)
			env.ambient_light_energy = 0.6
			env.fog_light_color = Color(0.06, 0.035, 0.03)
			env.fog_depth_begin = 5.0
			env.glow_intensity = 0.8
		SPEAKEASY:
			# Darker, browner, and thick with smoke: the far end of the room goes soft.
			env.ambient_light_color = Color(0.5, 0.36, 0.24)
			env.ambient_light_energy = 0.38
			env.fog_light_color = Color(0.075, 0.058, 0.042)
			env.fog_depth_begin = 0.5
			env.fog_depth_end = 15.0
			key.light_energy = 0.02


func lamp_colour(_index: int, authored: Color) -> Color:
	# Tungsten, warmer than the authored lamps: the club's bulbs are old.
	return authored.lerp(Color(1.0, 0.72, 0.45), 0.3)


func lamp_energy(_index: int, authored: float) -> float:
	return authored * (0.7 if variant == SPEAKEASY else 0.85)


## One open floor: the strips either side of the footprint, wall to wall and from the front wall to
## the back of house, overlapping the footprint's edge so they join the control room beside them
## and meeting the back of house behind. They were drawn 5 cm off the footprint and 30 cm short of
## the back of house, so each was a walled island no one could walk into.
func rooms() -> Array[Rect2]:
	var half := live_room_half()
	var cr := room_width * 0.5
	var depth := Studio.ROOM_BACK - FRONT
	return [back_of_house(),
			Rect2(-half, FRONT, half - cr + 0.05, depth),
			Rect2(cr - 0.05, FRONT, half - cr + 0.05, depth)]


func zone_solids() -> Array:
	var out := ZoneKit.solids(zones(), true)
	var half := live_room_half()
	# The bar's counter, and the back bar behind it.
	out.append({"c": Vector2(bar_front() + COUNTER_DEPTH * 0.5, (BAR_FROM + BAR_TO) * 0.5),
			"h": Vector2(COUNTER_DEPTH * 0.5, (BAR_TO - BAR_FROM) * 0.5), "a": 0.0, "top": BAR_TOP})
	out.append({"c": Vector2(half - 0.25, (BAR_FROM + BAR_TO) * 0.5),
			"h": Vector2(0.25, (BAR_TO - BAR_FROM) * 0.5), "a": 0.0, "top": 0.95})
	for z: float in BOOTHS:
		for side in [-1.0, 1.0]:
			out.append({"c": Vector2(-half + BENCH * 0.5, z + side * (BENCH_GAP + 0.3)), "h": Vector2(BENCH * 0.5, 0.3),
					"a": 0.0, "top": 1.15})
		out.append({"c": Vector2(-half + BENCH * 0.5, z), "h": Vector2(0.33, BENCH_GAP - 0.01), "a": 0.0, "top": 0.74})
	for at in stool_spots():
		out.append({"c": at, "h": Vector2(0.2, 0.2), "a": 0.0, "top": 0.79})
	if variant == SPEAKEASY:
		out.append_array(_speakeasy_solids())
		return out
	# The case and the keybed's back, to the keys: they are the instrument's own solid
	# (Venue.instrument_solids).
	out.append({"c": Vector2(piano_x() + 0.05, PIANO_Z), "h": Vector2(PIANO_DEPTH * 0.5 + 0.05, PIANO_WIDTH * 0.5), "a": 0.0,
			"top": 1.25})
	if variant == SHOWTIME:
		out.append_array(_showtime_solids())
		return out
	var bass_dir := Vector2(cos(BASS_YAW), -sin(BASS_YAW))
	out.append({"c": Vector2(bass_at().x, bass_at().z) + bass_dir * BASS_LENGTH * 0.5, "h": Vector2(BASS_LENGTH * 0.5, 0.2),
			"a": -BASS_YAW, "top": 0.72})
	return out


## Showtime: the bench and the bass by the piano, the tables and their chairs, the coat stand.
func _showtime_solids() -> Array:
	var out := []
	out.append({"c": piano_bench_at(), "h": Vector2(0.18, 0.43), "a": 0.0, "top": 0.54})
	out.append({"c": bass_stand_at(), "h": Vector2(0.3, 0.38), "a": 0.0, "top": 1.9})
	for t in SHOW_TABLES.size():
		var at := show_table_at(t)
		out.append({"c": at, "h": Vector2(0.24, 0.24), "a": 0.0, "top": 0.74})
		for chair in chair_spots(t):
			out.append({"c": chair, "h": Vector2(0.2, 0.2), "a": 0.0, "top": 0.86})
	out.append({"c": coat_stand_at(), "h": Vector2(0.25, 0.25), "a": 0.0, "top": 1.83})
	out.append({"c": bucket_at(), "h": Vector2(0.17, 0.17), "a": 0.0, "top": 0.81})
	return out


## Speakeasy: the bookcases (the door bay turned on its hinge), the barrels and crates, the card
## table and its chairs, the gramophone, the barrel table and its stools.
func _speakeasy_solids() -> Array:
	var out := []
	for i in BAYS:
		var bay := bay_transform(i)
		var mid := bay * Vector3(0, 0, BAY.z * 0.5)
		out.append({"c": Vector2(mid.x, mid.z), "h": Vector2(BAY.x * 0.5, BAY.z * 0.5), "a": -bay.basis.get_euler().y,
				"top": BAY.y})
	var rack := barrel_rack()
	out.append({"c": rack.get_center(), "h": rack.size * 0.5, "a": 0.0, "top": 1.2})
	var case := piano_case()
	var middle := case * Vector3(0, 0, 0.05)
	out.append({"c": Vector2(middle.x, middle.z), "h": Vector2(PIANO_WIDTH * 0.5, PIANO_DEPTH * 0.5 + 0.05),
			"a": case.basis.get_euler().y, "top": 1.25})
	var crates := crate_stack()
	out.append({"c": crates.get_center(), "h": crates.size * 0.5, "a": 0.0, "top": 0.72})
	out.append({"c": card_table_at(), "h": Vector2.ONE * CARD_TABLE * 0.5, "a": 0.0, "top": 0.8})
	for chair in card_chair_spots():
		out.append({"c": chair, "h": Vector2(0.2, 0.2), "a": 0.0, "top": 0.86})
	out.append({"c": gramophone_at(), "h": Vector2(0.27, 0.27), "a": 0.0, "top": 1.45})
	out.append({"c": barrel_table_at(), "h": Vector2(0.3, 0.3), "a": 0.0, "top": 0.92})
	for stool in barrel_stools():
		out.append({"c": stool, "h": Vector2(0.2, 0.2), "a": 0.0, "top": 0.79})
	return out


# --- where things stand in the other arrangements --------------------------------------------

## The strip's edge on a side: the footprint's half width.
func _strip_edge() -> float:
	return room_width * 0.5


## Showtime: a bistro table's middle (x, z).
func show_table_at(t: int) -> Vector2:
	var spec: Array = SHOW_TABLES[t]
	return Vector2(float(spec[0]) * (_strip_edge() + float(spec[1])), spec[2])


## Showtime: where the chairs at table `t` stand.
func chair_spots(t: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for a: float in SHOW_TABLES[t][3]:
		out.append(show_table_at(t) + Vector2(cos(a), sin(a)) * CHAIR_OUT)
	return out


func piano_bench_at() -> Vector2:
	return Vector2(piano_x() + PIANO_DEPTH * 0.5 + 0.35 + BENCH_OUT, PIANO_Z + BENCH_ALONG)


func bass_stand_at() -> Vector2:
	return Vector2(-_strip_edge() - BASS_STAND.x, BASS_STAND.y)


## Showtime: the coat stand by the door, between it and the corner.
func coat_stand_at() -> Vector2:
	return Vector2(-live_room_half() + 0.3, FRONT + 0.5)


## Showtime: the champagne bucket by the right-hand table nearest the desk.
func bucket_at() -> Vector2:
	return show_table_at(2) + Vector2(0.5, -0.5)


## Speakeasy: bay `i` of the bookcases along the left strip's front wall, as the transform of its
## foot (its back on the wall, its books facing +Z); the door bay swung open on its front left
## corner.
func bay_transform(i: int) -> Transform3D:
	var x := -live_room_half() + 0.05 + BAY.x * (i + 0.5)
	var at := Transform3D(Basis.IDENTITY, Vector3(x, 0, FRONT + 0.005))
	if i != DOOR_BAY:
		return at
	var hinge := Vector3(x - BAY.x * 0.5, 0, FRONT + 0.005 + BAY.z)
	return Transform3D(Basis(Vector3.UP, -DOOR_OPEN), hinge) * Transform3D(Basis.IDENTITY, at.origin - hinge)


## Speakeasy: the doorway behind the door bay, (x0, x1).
func stair_door() -> Vector2:
	var x0 := -live_room_half() + 0.05 + BAY.x * DOOR_BAY
	return Vector2(x0 + 0.06, x0 + BAY.x - 0.06)


## Speakeasy: the floor the barrel rack stands on, against the right strip's front wall.
func barrel_rack() -> Rect2:
	var x0 := _strip_edge() + 0.25
	var x1 := live_room_half() - 0.1
	return Rect2(x0, FRONT + 0.02, x1 - x0, BARREL_LONG + 0.1)


## The barrels' middles, lying along Z: a bottom row on the cradle and a row nested on top.
func barrel_spots() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var rack := barrel_rack()
	var count := int(rack.size.x / (BARREL_R * 2.0 + 0.02))
	var pitch := rack.size.x / count
	var z := rack.position.y + 0.05 + BARREL_LONG * 0.5
	for i in count:
		out.append(Vector3(rack.position.x + pitch * (i + 0.5), CRADLE + BARREL_R, z))
	var lift := sqrt(4.0 * BARREL_R * BARREL_R - pitch * pitch * 0.25)
	for i in count - 1:
		out.append(Vector3(rack.position.x + pitch * (i + 1.0), CRADLE + BARREL_R + lift, z - 0.03))
	return out


## Speakeasy: the crates, two stacked against the right wall between the barrels and the bar.
func crate_stack() -> Rect2:
	var x1 := live_room_half() - 0.05
	return Rect2(x1 - 0.62, barrel_rack().end.y + 0.04, 0.62, 0.42)


func card_table_at() -> Vector2:
	return Vector2(-live_room_half() + BENCH + 0.05 + CARD_TABLE * 0.5 + 0.05, PIANO_Z + 0.1)


func card_chair_spots() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for a: float in CARD_CHAIRS:
		out.append(card_table_at() + Vector2(cos(a), sin(a)) * CARD_CHAIR_OUT)
	return out


func gramophone_at() -> Vector2:
	return Vector2(-_strip_edge() - GRAMOPHONE_AT.x, FRONT + BAY.z + GRAMOPHONE_AT.y - 0.4)


func barrel_table_at() -> Vector2:
	return Vector2(-_strip_edge() - BARREL_TABLE_AT.x, BARREL_TABLE_AT.y)


func barrel_stools() -> Array[Vector2]:
	return [barrel_table_at() + Vector2(-0.52, 0.1), barrel_table_at() + Vector2(0.1, 0.52)]


## The bar's counter's front face (x), BAR_IN in from the right-hand wall.
func bar_front() -> float:
	return live_room_half() - BAR_IN


## The bass's foot, in the left strip past the far booth, from the strip's edge by the control room.
func bass_at() -> Vector3:
	return Vector3(-_strip_edge() - BASS_AT.x, 0, BASS_AT.y)


## The middle of the piano's case, its back to the booths' bench ends.

func piano_x() -> float:
	return -live_room_half() + BENCH + 0.05 + PIANO_DEPTH * 0.5


## The piano's case's frame, on the floor under its middle, its keys toward +Z: against the booths'
## bench ends, its keys to the room; in the speakeasy, where the card table has its place, against
## the back wall between the kit and the lattice, its keys toward the desk.
func piano_case() -> Transform3D:
	if variant == SPEAKEASY:
		# Where every venue's back-wall instrument stands (Venue.back_wall_instrument): behind the
		# riser, the rhythm neighbourhood's back wall.
		var x := back_wall_instrument(0.0).origin.x
		return Transform3D(Basis(Vector3.UP, PI), Vector3(x, 0, LIVE_ROOM_BACK - 0.05 - PIANO_OFF_WALL - PIANO_DEPTH * 0.5))
	return Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(piano_x(), 0, PIANO_Z))


## Its instrument (VenueInstrument, docs/spatial_loop.md part two, slice 43): the upright piano's own
## keys, the octave from A in the middle of its keyboard. club.glb leaves that octave out
## (tools/blender/club.py's GAP) for the set's eight keys and its sunk black keys, wherever the piano
## stands (`piano_case`).
func instrument() -> Dictionary:
	return {"kind": &"piano", "spot": piano_case() * Transform3D(Basis.IDENTITY, Vector3(PIANO_OCTAVE, 0, PIANO_KEYS_OUT))}


## Speakeasy: the upright moved out of the strip for the card table, against the back wall by the
## band, its lid down; its octave is the club's instrument there too.
func _move_the_piano_by_the_stage() -> void:
	var piano := _piece(load(MODELS + "club.glb") as PackedScene, "Piano")
	piano.name = "Piano"
	piano.transform = piano_case()


## Where each bar stool stands, in front of the counter.
func stool_spots() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var z := BAR_FROM + 0.45
	while z < BAR_TO - 0.3:
		out.append(Vector2(bar_front() - 0.36, z))
		z += 0.75
	return out


## Where the spot is aimed: the middle of the drum riser's top.
func stage_centre() -> Vector3:
	var stage: AABB = zones()[&"drums"]
	return Vector3(stage.get_center().x, ZoneKit.RISER_HEIGHT, stage.get_center().z)


func _ready() -> void:
	_lay_the_floor()
	_build_walls()
	_build_ceiling()
	_build_the_bar()
	_build_the_booths()
	_hang_the_curtain()
	match variant:
		SHOWTIME:
			_hang_the_spot()
			_rig_the_show()
			_light_the_marquee()
			_set_the_stage_for_the_band()
			_set_out_the_tables()
		SPEAKEASY:
			_open_the_bookcase()
			_rack_the_barrels()
			_hang_the_sunbursts()
			_deal_the_cards()
			_move_the_piano_by_the_stage()
			_wind_the_gramophone()
			_light_the_band_low()
			_light_the_house()
			_string_the_bulbs()
			_blow_the_smoke()
		_:
			_hang_the_spot()
			_light_the_sign()
			_leave_the_instruments()
			_leave_the_glasses()
	if variant != SPEAKEASY:
		_light_the_house()
	_dress_zones()


func _process(delta: float) -> void:
	_t += delta
	for i in candles.size():
		var c := candles[i]
		c.light_energy = 0.35 + 0.08 * sin(_t * 7.3 + i * 2.1) * sin(_t * 3.1 + i) + 0.04 * sin(_t * 17.0 + i * 5.0)
	if not _bulbs.is_empty():
		# The marquee's chase: one set lit, then the other, a little quicker on a loud bar.
		var lit := int(_t / (CHASE * (1.0 - 0.35 * _level))) % 2
		for i in _bulbs.size():
			_bulbs[i].albedo_color = BULB * (2.6 if i == lit else 0.3) * (1.0 + _level * 0.6)
	for i in bulb_lights.size():
		# Old wiring: each bulb's light dips now and then, not together.
		var dip := maxf(0.0, sin(_t * 1.7 + i * 2.3) * sin(_t * 5.3 + i * 1.1) - 0.7) * 0.6
		bulb_lights[i].light_energy = _bulb_energy[i] * (1.0 - dip)


## Showtime: the curtain's washes and the cans breathe with the band, and the neon brightens.
func pulse(level: float) -> void:
	_level = lerpf(_level, level, 0.25)
	for i in washes.size():
		washes[i].light_energy = _wash_energy[i] * (0.8 + 0.5 * _level)
	for i in _neon.size():
		_neon[i].albedo_color = NEON[i] * (1.0 + 0.6 * _level)
	if _stars != null:
		_stars.set_shader_parameter("pulse", _level)


# --- materials -------------------------------------------------------------------------------

func _brick() -> StandardMaterial3D:
	return Materials.cached_scanned("club_brick", "red_brick_03", "2k", 1.3, Color(0.42, 0.3, 0.26))


func _walnut() -> StandardMaterial3D:
	return Materials.cached_scanned("club_walnut", "black_walnut_veneer_01", "2k", 1.0, Color(0.3, 0.22, 0.16))


func _brass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.78, 0.6, 0.32)
	m.metallic = 1.0
	m.roughness = 0.32
	return m


func _black() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.03, 0.03, 0.03)
	m.roughness = 0.5
	m.metallic = 0.4
	return m


func _leather() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.06, 0.05)
	m.roughness = 0.42
	m.metallic_specular = 0.45
	m.normal_enabled = true
	m.normal_texture = Materials.grain("leather", 0.3, 0.7)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 3.0
	return m


func _bottle_glass(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = colour
	m.roughness = 0.08
	m.metallic_specular = 0.7
	m.rim_enabled = true
	m.rim = 0.4
	return m


func _swaps() -> Dictionary:
	var marble := StandardMaterial3D.new()
	marble.albedo_color = Color(0.82, 0.8, 0.76)
	marble.roughness = 0.18
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.82, 0.74, 0.58)
	paper.roughness = 0.8
	return {"marble": marble, "iron": _black(), "wood": _walnut(), "leather": _leather(), "brass": _brass(),
			"glass_green": _bottle_glass(Color(0.1, 0.3, 0.12, 0.75)),
			"glass_amber": _bottle_glass(Color(0.55, 0.28, 0.06, 0.7)),
			"glass_clear": _bottle_glass(Color(0.75, 0.8, 0.8, 0.35)), "label": paper,
			"lacquer": _lacquer(), "ivory": _plain(Color(0.86, 0.82, 0.72), 0.35), "ebony": _plain(Color(0.025, 0.02, 0.02), 0.3),
			"varnish": _varnish(), "string": _brass(), "whisky": _bottle_glass(Color(0.62, 0.3, 0.05, 0.8)),
			"wine": _bottle_glass(Color(0.35, 0.02, 0.05, 0.9)), "wool": _cloth(Color(0.42, 0.33, 0.22)),
			"felt": _cloth(Color(0.12, 0.11, 0.1)), "ribbon": _plain(Color(0.03, 0.03, 0.03), 0.4)}


func _plain(colour: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = rough
	return m


## The piano's black lacquer: deep, and glossy enough to carry the spot and the candles.
func _lacquer() -> StandardMaterial3D:
	var m := _plain(Color(0.02, 0.018, 0.018), 0.12)
	m.metallic_specular = 0.8
	m.clearcoat_enabled = true
	m.clearcoat = 0.8
	m.clearcoat_roughness = 0.1
	return m


## The bass's varnish over maple: a warm red-brown with a shine.
func _varnish() -> StandardMaterial3D:
	var m := _plain(Color(0.36, 0.13, 0.04), 0.25)
	m.clearcoat_enabled = true
	m.clearcoat = 0.6
	m.normal_enabled = true
	m.normal_texture = Materials.grain("club_varnish", 0.15, 0.4, 4.0)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 2.0
	return m


func _cloth(colour: Color) -> StandardMaterial3D:
	var m := _plain(colour, 0.9)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.rim_enabled = true
	m.rim = 0.3
	m.rim_tint = 0.6
	m.normal_enabled = true
	m.normal_texture = Materials.grain("club_wool", 0.25, 0.6)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 6.0
	return m


# --- the room --------------------------------------------------------------------------------

func _lay_the_floor() -> void:
	var half := live_room_half()
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(half * 2.0 + WALL, LIVE_ROOM_BACK - FRONT + WALL)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(0, 0, (FRONT + LIVE_ROOM_BACK) * 0.5)
	floor_mesh.material_override = Materials.cached_scanned("club_floor", "herringbone_parquet", "2k", 2.0,
			Color(0.45, 0.36, 0.28))
	if variant == SPEAKEASY:
		# A cellar's boards, scuffed dark: no parquet down here yet.
		floor_mesh.material_override = Materials.cached_scanned("club_boards", "weathered_brown_planks", "2k", 2.6,
				Color(0.42, 0.32, 0.25))
	add_child(floor_mesh)


## Brick from the floor to the ceiling, the wainscot over its lower part, a cap rail along the
## wainscot's top, and the door in the front wall with its exit sign.
func _build_walls() -> void:
	if variant == SPEAKEASY:
		_panel_the_walls()
		return
	var half := live_room_half()
	var brick := _brick()
	var walnut := _walnut()
	var z0 := FRONT
	var z1 := LIVE_ROOM_BACK
	var length := z1 - z0
	var mid := (z0 + z1) * 0.5
	for side in [-1.0, 1.0]:
		ZoneKit.block(self, Vector3(WALL, HEIGHT, length + WALL * 2.0), Vector3(side * (half + WALL * 0.5), HEIGHT * 0.5, mid),
				brick, "SideWall")
		ZoneKit.block(self, Vector3(0.04, WAINSCOT, length - 0.004), Vector3(side * (half - 0.02), WAINSCOT * 0.5, mid),
				walnut, "Wainscot")
		ZoneKit.block(self, Vector3(0.07, 0.05, length - 0.01), Vector3(side * (half - 0.037), WAINSCOT + 0.02, mid),
				walnut, "CapRail")
	for spec in [[z0 - WALL * 0.5, 1.0], [z1 + WALL * 0.5, -1.0]]:
		var z: float = spec[0]
		var inward: float = spec[1]
		ZoneKit.block(self, Vector3(half * 2.0, HEIGHT, WALL), Vector3(0, HEIGHT * 0.5, z), brick, "EndWall")
		ZoneKit.block(self, Vector3(half * 2.0 - 0.1, WAINSCOT, 0.04), Vector3(0, WAINSCOT * 0.5, z + inward * (WALL * 0.5 + 0.02)),
				walnut, "Wainscot")
		ZoneKit.block(self, Vector3(half * 2.0 - 0.144, 0.05, 0.07), Vector3(0, WAINSCOT + 0.02, z + inward * (WALL * 0.5 + 0.037)),
				walnut, "CapRail")
	# The door: on the front wall right of the desk, short of the Rig Roulette door, a walnut slab
	# in a black frame, a brass push plate, the exit sign over it. Not in the left corner, where it
	# was: that is LEVELS' niche (Venue.levels_niche_spot).
	var door_x := rig_roulette_door().origin.x - RouletteDoor.HALF.x - 1.0
	# (all of it standing proud of the wainscot)
	var face := FRONT + 0.045
	ZoneKit.block(self, Vector3(1.0, 2.16, 0.06), Vector3(door_x, 1.08, face + 0.03), walnut, "Door")
	for spec in [[Vector3(0.06, 2.3, 0.08), Vector3(door_x - 0.53, 1.15, face + 0.04)],
			[Vector3(0.06, 2.3, 0.08), Vector3(door_x + 0.53, 1.15, face + 0.04)],
			[Vector3(1.0, 0.06, 0.07), Vector3(door_x, 2.2, face + 0.035)]]:
		ZoneKit.block(self, spec[0], spec[1], _black(), "DoorFrame")
	ZoneKit.block(self, Vector3(0.1, 0.3, 0.01), Vector3(door_x + 0.32, 1.15, face + 0.065), _brass(), "PushPlate")
	ZoneKit.block(self, Vector3(0.36, 0.14, 0.05), Vector3(door_x, 2.55, face + 0.03), _black(), "ExitBox")
	var exit := Label3D.new()
	exit.name = "Exit"
	exit.text = "EXIT"
	exit.font_size = 64
	exit.pixel_size = 0.0014
	exit.modulate = Color(2.4, 0.25, 0.2)
	exit.shaded = false
	exit.double_sided = false
	exit.position = Vector3(door_x, 2.55, face + 0.056)
	add_child(exit)
	var red := OmniLight3D.new()
	red.name = "ExitGlow"
	red.light_color = Color(1.0, 0.2, 0.15)
	red.light_energy = 0.25
	red.omni_range = 1.6
	red.position = Vector3(door_x, 2.4, face + 0.3)
	add_child(red)
	# Sconces on the brick, a warm pool each, high on the side walls of the back of house: over the
	# prop shelf and the cassette rack on the left, the bricks table and the bells on the right,
	# clear of the booth and the modular wall at the back.
	for side in [-1.0, 1.0]:
		for z in SCONCES:
			var at := Vector3(side * (half - 0.08), 2.3, z)
			ZoneKit.block(self, Vector3(0.12, 0.2, 0.12), at, _brass(), "Sconce")
			ZoneKit.block(self, Vector3(0.1, 0.06, 0.1), at + Vector3(0, 0.13, 0), ZoneKit.glow(Color(1.0, 0.7, 0.4), 1.6),
					"SconceBulb")
			var lamp := OmniLight3D.new()
			lamp.name = "SconceLight"
			lamp.light_color = Color(1.0, 0.68, 0.4)
			lamp.light_energy = 1.3
			lamp.omni_range = 4.2
			lamp.position = at + Vector3(-side * 0.15, 0.25, 0)
			add_child(lamp)


## Pressed tin, gone dark: the station's panel grid in small squares, in an old brass colour.
func _build_ceiling() -> void:
	if variant == SPEAKEASY:
		_bare_the_joists()
		return
	var half := live_room_half()
	var tin := ShaderMaterial.new()
	tin.shader = preload("res://core/venues/shaders/station_panel.gdshader")
	tin.set_shader_parameter("base", Color(0.16, 0.12, 0.08))
	tin.set_shader_parameter("seam", Color(0.03, 0.025, 0.02))
	tin.set_shader_parameter("panel", Vector2(0.6, 0.6))
	tin.set_shader_parameter("seam_width", 0.02)
	tin.set_shader_parameter("metal", 0.7)
	tin.set_shader_parameter("roughness_base", 0.45)
	tin.set_shader_parameter("mottle", 0.15)
	ZoneKit.block(self, Vector3(half * 2.0, 0.1, LIVE_ROOM_BACK - FRONT), Vector3(0, HEIGHT + 0.05,
			(FRONT + LIVE_ROOM_BACK) * 0.5), tin, "Ceiling")


# --- the bar ---------------------------------------------------------------------------------

## The counter, its top, its brass foot rail; the back bar against the wall, its shelves of
## bottles lit from under, a mirror behind them; the stools, some turned up on the counter.
func _build_the_bar() -> void:
	var half := live_room_half()
	var walnut := _walnut()
	var length := BAR_TO - BAR_FROM
	var mid := (BAR_FROM + BAR_TO) * 0.5
	var cx := bar_front() + COUNTER_DEPTH * 0.5
	ZoneKit.block(self, Vector3(COUNTER_DEPTH, BAR_TOP - 0.06, length), Vector3(cx, (BAR_TOP - 0.06) * 0.5, mid), walnut,
			"Counter")
	ZoneKit.block(self, Vector3(COUNTER_DEPTH + 0.12, 0.06, length + 0.12), Vector3(cx - 0.04, BAR_TOP - 0.03, mid),
			Materials.cached_scanned("club_top", "black_walnut_veneer_01", "2k", 1.0, Color(0.16, 0.11, 0.08)), "BarTop")
	var rail := MeshInstance3D.new()
	rail.name = "FootRail"
	var tube := CylinderMesh.new()
	tube.top_radius = 0.025
	tube.bottom_radius = 0.025
	tube.height = length - 0.1
	tube.radial_segments = 12
	rail.mesh = tube
	rail.material_override = _brass()
	rail.rotation.x = PI * 0.5
	rail.position = Vector3(bar_front() - 0.14, 0.2, mid)
	add_child(rail)
	for z in [BAR_FROM + 0.2, mid, BAR_TO - 0.2]:
		ZoneKit.block(self, Vector3(0.14, 0.03, 0.03), Vector3(bar_front() - 0.07, 0.2, z), _brass(), "RailBracket")

	# The back bar: a low cabinet, three shelves over it, a mirror behind.
	ZoneKit.block(self, Vector3(0.44, 0.95, length), Vector3(half - 0.26, 0.475, mid), walnut, "BackBar")
	var mirror := StandardMaterial3D.new()
	mirror.albedo_color = Color(0.25, 0.22, 0.2)
	mirror.metallic = 1.0
	mirror.roughness = 0.12
	ZoneKit.block(self, Vector3(0.02, 1.3, length - 0.1), Vector3(half - 0.05, 1.85, mid), mirror, "BarMirror")
	# Set for the show the back bar is turned right up; in the speakeasy it is kept low.
	var turned := {SHOWTIME: 1.6, SPEAKEASY: 0.8}.get(variant, 1.0) as float
	var strip := ZoneKit.glow(Color(1.0, 0.68, 0.36), 1.8 * turned)
	var shelves := [1.3, 1.72, 2.14]
	for y: float in shelves:
		ZoneKit.block(self, Vector3(0.24, 0.03, length - 0.1), Vector3(half - 0.18, y, mid), walnut, "Shelf")
		var led := ZoneKit.block(self, Vector3(0.02, 0.012, length - 0.2), Vector3(half - 0.08, y - 0.021, mid), strip,
				"ShelfLight")
		led.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for z in [BAR_FROM + 0.8, BAR_TO - 0.8]:
		var glow := OmniLight3D.new()
		glow.name = "BackBarLight"
		glow.light_color = Color(1.0, 0.66, 0.36)
		glow.light_energy = 0.9 * turned
		glow.omni_range = 2.2
		glow.position = Vector3(half - 0.3, 1.9, z)
		add_child(glow)
	_line_the_bottles(shelves + [0.95], half - 0.18, length - 0.3, mid)

	# The stools: the first two standing, the rest turned up on the counter.
	var club := load(MODELS + "club.glb") as PackedScene
	var spots := stool_spots()
	for i in spots.size():
		var stool := _piece(club, "Stool")
		if i < 2 or variant != AFTER_HOURS:
			stool.position = Vector3(spots[i].x, 0, spots[i].y)
			stool.rotation.y = i * 0.7 + (0.0 if variant == AFTER_HOURS else 0.3 * sin(i * 2.3))
		else:
			stool.basis = Basis(Vector3.RIGHT, PI)
			stool.position = Vector3(cx - 0.05, BAR_TOP + 0.79, spots[i].y)
		stool.name = "Stool%d" % i
	# A glass left on the bar, and the bar's last candle.
	_candle(Vector3(cx - 0.1, BAR_TOP, BAR_FROM + 0.25))
	if variant == SHOWTIME:
		# Set for the show: a candle at the other end of the counter too.
		_candle(Vector3(cx - 0.1, BAR_TOP, BAR_TO - 0.25))
	elif variant == SPEAKEASY:
		_deco_the_counter(cx, length, mid)


## The bottles: rows of the four kinds on every shelf, each row a MultiMesh, spaced unevenly.
func _line_the_bottles(levels: Array, x: float, length: float, mid: float) -> void:
	var club := (load(MODELS + "club.glb") as PackedScene).instantiate()
	var swaps := _swaps()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var per_kind: Array = [[], [], [], []]
	for y: float in levels:
		bottle_levels.append(y + 0.015)
		var z := mid - length * 0.5
		while z < mid + length * 0.5:
			var kind := rng.randi() % 4
			var spot := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(x + rng.randf_range(-0.04, 0.04),
					y + 0.015, z))
			per_kind[kind].append(spot)
			bottle_spots.append(spot)
			z += rng.randf_range(0.09, 0.16)
	for kind in 4:
		var source := club.find_child("Bottle%d" % kind, true, false) as MeshInstance3D
		var mesh := source.mesh.duplicate() as ArrayMesh
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			if m != null and swaps.has(m.resource_name):
				mesh.surface_set_material(s, swaps[m.resource_name])
		var rows := MultiMesh.new()
		rows.transform_format = MultiMesh.TRANSFORM_3D
		rows.mesh = mesh
		rows.instance_count = per_kind[kind].size()
		for i in per_kind[kind].size():
			rows.set_instance_transform(i, per_kind[kind][i])
		var node := MultiMeshInstance3D.new()
		node.name = "Bottles%d" % kind
		node.multimesh = rows
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	club.free()


# --- the booths ------------------------------------------------------------------------------

## Each booth: two benches facing across a marble table against the wall, a candle on it.
func _build_the_booths() -> void:
	var half := live_room_half()
	var club := load(MODELS + "club.glb") as PackedScene
	var x := -half + BENCH * 0.5
	for i in BOOTHS.size():
		var z: float = BOOTHS[i]
		for side in [-1.0, 1.0]:
			var bench := _piece(club, "Banquette")
			bench.name = "Bench%d%s" % [i, "a" if side < 0.0 else "b"]
			# The model's seat faces +Z and its back is 0.34 behind the seat front... at -Z.
			bench.position = Vector3(x, 0, z + side * (BENCH_GAP + 0.25))
			bench.rotation.y = 0.0 if side < 0.0 else PI
		var table := _piece(club, "Table")
		table.name = "BoothTable%d" % i
		table.position = Vector3(x, 0, z)
		_candle(Vector3(x + 0.12, 0.74, z + 0.05))
		if variant == SPEAKEASY:
			# Three bare bulbs on long cords over each booth instead of the brass shade.
			for k in 3:
				_hang_bulb(Vector3(x - 0.16 + 0.16 * k, 1.62 + 0.14 * ((k + i) % 2) + 0.07 * k, z + 0.08 * (k - 1)))
			var low := SpotLight3D.new()
			low.name = "BoothLight"
			low.light_color = Color(1.0, 0.62, 0.32)
			low.light_energy = 1.1
			low.spot_range = 2.4
			low.spot_angle = 65.0
			low.position = Vector3(x, 1.55, z)
			low.rotation.x = -PI * 0.5
			add_child(low)
			_flickers(low)
			continue
		# A low pendant over each booth, its shade a dark cone, its bulb warm.
		var shade := MeshInstance3D.new()
		shade.name = "BoothShade"
		var cone := CylinderMesh.new()
		cone.top_radius = 0.05
		cone.bottom_radius = 0.2
		cone.height = 0.18
		cone.radial_segments = 20
		shade.mesh = cone
		shade.material_override = _brass()
		shade.position = Vector3(x, 1.75, z)
		add_child(shade)
		ZoneKit.block(self, Vector3(0.008, HEIGHT - 1.84, 0.008), Vector3(x, (HEIGHT + 1.84) * 0.5, z), _black(), "Cord")
		var pool := SpotLight3D.new()
		pool.name = "BoothLight"
		pool.light_color = Color(1.0, 0.7, 0.42)
		pool.light_energy = 1.4
		pool.spot_range = 2.4
		pool.spot_angle = 55.0
		pool.position = Vector3(x, 1.68, z)
		pool.rotation.x = -PI * 0.5
		add_child(pool)


## A candle in a short amber glass, and the small light it gives, which flickers (_process).
func _candle(at: Vector3) -> void:
	var glass := MeshInstance3D.new()
	glass.name = "Candle"
	var cup := CylinderMesh.new()
	cup.top_radius = 0.035
	cup.bottom_radius = 0.032
	cup.height = 0.08
	cup.radial_segments = 14
	glass.mesh = cup
	glass.material_override = _bottle_glass(Color(0.75, 0.38, 0.1, 0.6))
	glass.position = at + Vector3(0, 0.04, 0)
	add_child(glass)
	var flame := ZoneKit.block(self, Vector3(0.012, 0.025, 0.012), at + Vector3(0, 0.07, 0), ZoneKit.glow(Color(1.0, 0.7, 0.3), 3.0),
			"Flame")
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.name = "CandleLight"
	light.light_color = Color(1.0, 0.62, 0.3)
	light.light_energy = 0.35
	light.omni_range = 1.4
	light.position = at + Vector3(0, 0.15, 0)
	add_child(light)
	candles.append(light)


# --- the stage -------------------------------------------------------------------------------

## The velvet behind the stage, drawn the whole width of the back wall.
func _hang_the_curtain() -> void:
	var half := live_room_half()
	var stage: AABB = zones()[&"drums"]
	var x0 := -half + 0.05
	var x1 := half - 0.05
	var curtain := MeshInstance3D.new()
	curtain.name = "Curtain"
	var plane := PlaneMesh.new()
	plane.orientation = PlaneMesh.FACE_Z
	plane.size = Vector2(x1 - x0, HEIGHT - 0.12)
	plane.subdivide_width = int((x1 - x0) * 24.0)
	curtain.mesh = plane
	var velvet := ShaderMaterial.new()
	velvet.shader = preload("res://core/venues/shaders/curtain.gdshader")
	if variant == SPEAKEASY:
		# Old-gold brocade: the deco colour, not the red of a jazz bar, and it takes the bulbs'
		# amber where green velvet would drink it.
		velvet.set_shader_parameter("colour", Color(0.3, 0.19, 0.06))
		velvet.set_shader_parameter("sheen", Color(1.0, 0.78, 0.4))
	elif variant == SHOWTIME:
		# The show cloth: pale silver satin, so the washes paint it in their own colours.
		velvet.set_shader_parameter("colour", Color(0.36, 0.34, 0.36))
		velvet.set_shader_parameter("sheen", Color(0.9, 0.88, 0.95))
	curtain.material_override = velvet
	curtain.position = Vector3((x0 + x1) * 0.5, (HEIGHT - 0.12) * 0.5 + 0.02, LIVE_ROOM_BACK - 0.1)
	# The plane faces +Z; turned round to face the room.
	curtain.rotation.y = PI
	add_child(curtain)
	# Up-lights at its foot, behind the riser: the velvet glowing from below in long folds.
	for i in 5:
		var wash := SpotLight3D.new()
		wash.name = "CurtainWash"
		wash.light_color = Color(1.0, 0.45, 0.3)
		wash.light_energy = 2.2
		if variant == SHOWTIME:
			# Washed in the show's colours, and breathing with the band (pulse()).
			wash.light_color = CAN_COLOURS[i]
			wash.light_energy = 1.8
			washes.append(wash)
			_wash_energy.append(wash.light_energy)
		elif variant == SPEAKEASY:
			wash.light_color = Color(1.0, 0.62, 0.3)
			wash.light_energy = 2.6
		wash.spot_range = 4.6
		wash.spot_angle = 38.0
		wash.position = Vector3(x0 + (x1 - x0) * (i + 0.5) / 5.0, 0.08, LIVE_ROOM_BACK - 0.75)
		wash.basis = Basis.looking_at(Vector3(0, 1.0, 0.18), Vector3.FORWARD)
		add_child(wash)
	if variant == SHOWTIME:
		_sew_the_stars(x0, x1, curtain.position.z)
	# The track it hangs from.
	ZoneKit.block(self, Vector3(x1 - x0 + 0.1, 0.05, 0.08), Vector3((x0 + x1) * 0.5, HEIGHT - 0.06, LIVE_ROOM_BACK - 0.1),
			_black(), "CurtainTrack")


## The one spot: a black can on a bar from the ceiling, aimed at the middle of the stage, its
## beam drawn in the haze.
func _hang_the_spot() -> void:
	var target := stage_centre()
	ZoneKit.block(self, Vector3(1.2, 0.05, 0.05), Vector3(SPOT_AT.x, HEIGHT - 0.12, SPOT_AT.z), _black(), "LightingBar")
	ZoneKit.block(self, Vector3(0.03, 0.14, 0.03), Vector3(SPOT_AT.x, HEIGHT - 0.2, SPOT_AT.z), _black(), "Yoke")
	var aim := Basis.looking_at(target - SPOT_AT, Vector3.UP)
	var can := MeshInstance3D.new()
	can.name = "SpotCan"
	var body := CylinderMesh.new()
	body.top_radius = 0.1
	body.bottom_radius = 0.12
	body.height = 0.36
	body.radial_segments = 20
	can.mesh = body
	can.material_override = _black()
	# The cylinder's axis is its Y; turn it to lie along the aim (-Z of `aim`).
	can.basis = aim * Basis(Vector3.RIGHT, -PI * 0.5)
	can.position = SPOT_AT
	add_child(can)
	spot = SpotLight3D.new()
	spot.name = "Spot"
	spot.light_color = Color(1.0, 0.86, 0.66)
	spot.light_energy = 14.0
	spot.spot_range = 9.0
	spot.spot_angle = 14.0
	spot.spot_angle_attenuation = 0.4
	spot.shadow_enabled = true
	spot.basis = aim
	spot.position = SPOT_AT + aim * Vector3(0, 0, -0.2)
	add_child(spot)
	# The beam: an open cone from the lens to the stage.
	var length := SPOT_AT.distance_to(target)
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.1
	cone.bottom_radius = length * tan(deg_to_rad(spot.spot_angle)) * 0.85
	cone.height = 1.0
	cone.cap_top = false
	cone.cap_bottom = false
	cone.radial_segments = 32
	beam.mesh = cone
	var haze := ShaderMaterial.new()
	haze.shader = preload("res://core/venues/shaders/spot_beam.gdshader")
	beam.material_override = haze
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Narrow end (the cylinder's top, +Y) at the lamp, the wide end on the stage.
	beam.basis = aim * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(1, length, 1))
	beam.position = SPOT_AT + (target - SPOT_AT) * 0.5
	add_child(beam)
	_raise_the_dust(target, cone.bottom_radius)


## Motes in the beam: put at random through the cone, each wandering round its own place in
## dust.gdshader, lit only while they are in the light.
func _raise_the_dust(target: Vector3, far_radius: float) -> void:
	var aim := (target - SPOT_AT).normalized()
	var reach := SPOT_AT.distance_to(target)
	var spread := (far_radius - 0.1) / reach
	var side := aim.cross(Vector3.UP).normalized()
	var up := side.cross(aim)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.014, 0.014)
	mm.mesh = quad
	mm.instance_count = MOTES
	for i in MOTES:
		var along := rng.randf_range(0.5, reach - 0.4)
		var r := (0.1 + along * spread) * 0.8 * sqrt(rng.randf())
		var a := rng.randf() * TAU
		var at := SPOT_AT + aim * along + (side * cos(a) + up * sin(a)) * r
		motes.append(at)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, at))
		mm.set_instance_custom_data(i, Color(rng.randf(), 0, 0, 0))
	var dust := MultiMeshInstance3D.new()
	dust.name = "Dust"
	dust.multimesh = mm
	var shine := ShaderMaterial.new()
	shine.shader = preload("res://core/venues/shaders/dust.gdshader")
	shine.set_shader_parameter("lamp", SPOT_AT)
	shine.set_shader_parameter("aim", aim)
	shine.set_shader_parameter("spread", spread)
	shine.set_shader_parameter("reach", reach)
	dust.material_override = shine
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bounds := AABB(motes[0], Vector3.ZERO)
	for at in motes:
		bounds = bounds.expand(at)
	dust.custom_aabb = bounds.grow(0.3)
	add_child(dust)


## "after hours" in pink neon on the front wall, over the view from the desk, and the glow it
## throws on the brick.
func _light_the_sign() -> void:
	var tube := StandardMaterial3D.new()
	tube.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tube.albedo_color = Color(3.2, 0.7, 1.8)
	var sign := _model("neon.glb", Vector3(0.6, 2.95, FRONT + 0.08), 0.0, {"tube": tube, "rail": _black()})
	sign.name = "Neon"
	var glow := OmniLight3D.new()
	glow.name = "NeonGlow"
	glow.light_color = Color(1.0, 0.3, 0.6)
	glow.light_energy = 0.8
	glow.omni_range = 2.4
	glow.position = Vector3(0.6, 3.0, FRONT + 0.5)
	add_child(glow)


# --- what was left behind -------------------------------------------------------------------

## The band's gone home: the upright against the booths, the double bass laid down by it,
## a coat thrown over a booth's bench and a hat left on the other one.
func _leave_the_instruments() -> void:
	var club := load(MODELS + "club.glb") as PackedScene
	var piano := _piece(club, "Piano")
	piano.name = "Piano"
	# The model's keys face +Z; turned to face the room (+X).
	piano.transform = piano_case()
	# A brass lamp on the piano's lid, left on, bent over the keys.
	var lamp_at := Vector3(piano_x() + 0.12, 1.25, PIANO_Z - 0.45)
	ZoneKit.block(self, Vector3(0.12, 0.015, 0.12), lamp_at + Vector3(0, 0.008, 0), _brass(), "PianoLampBase")
	ZoneKit.block(self, Vector3(0.012, 0.3, 0.012), lamp_at + Vector3(0, 0.16, 0), _brass(), "PianoLampStem")
	var shade := MeshInstance3D.new()
	shade.name = "PianoLampShade"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.035
	cone.bottom_radius = 0.09
	cone.height = 0.11
	cone.radial_segments = 18
	shade.mesh = cone
	shade.material_override = _brass()
	shade.position = lamp_at + Vector3(0.08, 0.31, 0)
	shade.rotation.z = -0.6
	add_child(shade)
	var lamp := SpotLight3D.new()
	lamp.name = "PianoLamp"
	lamp.light_color = Color(1.0, 0.72, 0.45)
	lamp.light_energy = 1.6
	lamp.spot_range = 3.0
	lamp.spot_angle = 60.0
	lamp.position = shade.position + Vector3(0.03, -0.04, 0)
	lamp.basis = Basis.looking_at(Vector3(0.75, -1.0, 0.25), Vector3.UP)
	add_child(lamp)
	var bass := _piece(club, "Bass")
	bass.name = "Bass"
	# Its scroll is the model's +X end: laid along the piano's front toward the door, belly to the room.
	bass.rotation.y = BASS_YAW
	bass.position = bass_at()
	var bench := find_child("Bench1a", false, false) as Node3D
	var coat := _piece(club, "Coat")
	coat.name = "Coat"
	coat.transform = bench.transform
	var hat := _piece(club, "Hat")
	hat.name = "Hat"
	hat.transform = bench.transform * Transform3D(Basis(Vector3.UP, 0.7), Vector3(-0.38, 0.34, 0.04))


## Glasses no one cleared: two on each booth table, a couple on the bar.
func _leave_the_glasses() -> void:
	var club := load(MODELS + "club.glb") as PackedScene
	var x := -live_room_half() + BENCH * 0.5
	var cx := bar_front() + COUNTER_DEPTH * 0.5
	var left := [[0, Vector3(x - 0.12, 0.74, BOOTHS[0] - 0.14)], [1, Vector3(x + 0.16, 0.74, BOOTHS[0] + 0.12)],
			[2, Vector3(x - 0.08, 0.74, BOOTHS[1] + 0.15)], [0, Vector3(x + 0.1, 0.74, BOOTHS[1] - 0.16)],
			[0, Vector3(cx - 0.12, BAR_TOP, BAR_FROM + 0.6)], [2, Vector3(cx - 0.15, BAR_TOP, 0.4)]]
	for spec in left:
		var glass := _piece(club, "Glass%d" % spec[0])
		glass.name = "LeftGlass%d" % glass_spots.size()
		glass.position = spec[1]
		glass.rotation.y = glass_spots.size() * 1.3
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glass_spots.append(spec[1])


# --- showtime --------------------------------------------------------------------------------

const SHOW_MODELS := "club_showtime.glb"
const SPEAK_MODELS := "club_speakeasy.glb"
var _show_swaps_made := {}
var _speak_swaps_made := {}


## club_showtime.glb's materials, the club's own where it has them.
func _show_swaps() -> Dictionary:
	if _show_swaps_made.is_empty():
		var gold := _plain(Color(0.8, 0.6, 0.28), 0.28)
		gold.metallic = 1.0
		var silver := _plain(Color(0.82, 0.82, 0.84), 0.18)
		silver.metallic = 1.0
		_show_swaps_made = {"lacquer": _lacquer(), "ivory": _plain(Color(0.86, 0.82, 0.72), 0.35),
				"ebony": _plain(Color(0.025, 0.02, 0.02), 0.3), "brass": _brass(), "gold": gold,
				"paper": _plain(Color(0.88, 0.84, 0.74), 0.85), "ink": _plain(Color(0.04, 0.04, 0.05), 0.6),
				"varnish": _varnish(), "string": _brass(), "iron": _black(), "wood": _walnut(),
				"felt": _cloth(Color(0.12, 0.11, 0.1)), "felt_red": _cloth(Color(0.42, 0.05, 0.07)),
				"scarf": _cloth(Color(0.72, 0.64, 0.5)), "leather": _leather(), "silver": silver,
				"glass_green": _bottle_glass(Color(0.1, 0.3, 0.12, 0.8)),
				"ice": _bottle_glass(Color(0.85, 0.92, 0.95, 0.55)), "foil": gold,
				"lens": ZoneKit.glow(Color(1.0, 0.72, 0.42), 2.2)}
	return _show_swaps_made


## One named piece from one of the club's model files, its materials swapped for `swaps`.
func _set_piece(file: String, piece: String, swaps: Dictionary) -> MeshInstance3D:
	var all := (load(MODELS + file) as PackedScene).instantiate()
	var node := all.find_child(piece, true, false) as MeshInstance3D
	node.get_parent().remove_child(node)
	all.free()
	node.transform = Transform3D.IDENTITY
	for s in node.mesh.get_surface_count():
		var m := node.mesh.surface_get_material(s)
		if m != null and swaps.has(m.resource_name):
			node.set_surface_override_material(s, swaps[m.resource_name])
	add_child(node)
	return node


## A piece's mesh with its materials swapped, for a MultiMesh.
func _mesh_of(file: String, piece: String, swaps: Dictionary) -> ArrayMesh:
	var all := (load(MODELS + file) as PackedScene).instantiate()
	var mesh := (all.find_child(piece, true, false) as MeshInstance3D).mesh.duplicate() as ArrayMesh
	all.free()
	for s in mesh.get_surface_count():
		var m := mesh.surface_get_material(s)
		if m != null and swaps.has(m.resource_name):
			mesh.surface_set_material(s, swaps[m.resource_name])
	return mesh


## Many of one mesh, one draw.
func _scatter(mesh: Mesh, spots: Array, label: String, shadows := true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = spots.size()
	for i in spots.size():
		mm.set_instance_transform(i, spots[i])
	var node := MultiMeshInstance3D.new()
	node.name = label
	node.multimesh = mm
	if not shadows:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


## A can on a yoke at `at`, aimed at `target`, and the light it throws.
func _can(at: Vector3, target: Vector3, colour: Color, energy: float, angle: float) -> SpotLight3D:
	var aim := Basis.looking_at(target - at, Vector3.UP)
	var can := MeshInstance3D.new()
	can.name = "Can"
	var body := CylinderMesh.new()
	body.top_radius = 0.075
	body.bottom_radius = 0.09
	body.height = 0.26
	body.radial_segments = 16
	can.mesh = body
	can.material_override = _black()
	can.basis = aim * Basis(Vector3.RIGHT, -PI * 0.5)
	can.position = at
	add_child(can)
	ZoneKit.block(self, Vector3(0.025, 0.16, 0.025), at + Vector3(0, 0.1, 0), _black(), "CanYoke")
	var lens := MeshInstance3D.new()
	lens.name = "CanLens"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.085
	disc.bottom_radius = 0.085
	disc.height = 0.004
	disc.radial_segments = 16
	lens.mesh = disc
	lens.material_override = ZoneKit.glow(colour, 1.4)
	lens.basis = can.basis
	lens.position = at + aim * Vector3(0, 0, -0.132)
	add_child(lens)
	var light := SpotLight3D.new()
	light.name = "CanLight"
	light.light_color = colour
	light.light_energy = energy
	light.spot_range = at.distance_to(target) + 2.0
	light.spot_angle = angle
	light.spot_angle_attenuation = 0.6
	light.basis = aim
	light.position = at + aim * Vector3(0, 0, -0.16)
	add_child(light)
	return light


## Showtime: a star cloth -- points of light sewn over the curtain, each on the face of its fold
## (curtain.gdshader's wave, read back here), twinkling in club_starcloth.gdshader.
func _sew_the_stars(x0: float, x1: float, z: float) -> void:
	# curtain.gdshader's own `folds` and `depth`, which this curtain keeps (a shader's defaults
	# cannot be read back without a renderer, and the tests run without one).
	var folds := CURTAIN_FOLDS
	var depth := CURTAIN_DEPTH
	var cx := (x0 + x1) * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	mm.instance_count = STARS
	for i in STARS:
		var x := rng.randf_range(x0 + 0.1, x1 - 0.1)
		# The curtain is turned to face the room, so its own x runs the other way.
		var u := cx - x
		var wave := sin(u * folds * TAU) + 0.35 * sin(u * folds * 2.7 * TAU + 1.3)
		var at := Vector3(x, rng.randf_range(0.5, HEIGHT - 0.35), z - wave * depth - 0.02)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * rng.randf_range(0.03, 0.055)), at))
		mm.set_instance_custom_data(i, Color(rng.randf(), 0, 0, 0))
	var stars := MultiMeshInstance3D.new()
	stars.name = "StarCloth"
	stars.multimesh = mm
	var twinkle := ShaderMaterial.new()
	twinkle.shader = preload("res://core/venues/shaders/club_starcloth.gdshader")
	stars.material_override = twinkle
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stars.custom_aabb = AABB(Vector3(x0, 0, z - 0.4), Vector3(x1 - x0, HEIGHT, 0.6))
	add_child(stars)
	_stars = twinkle


## Showtime: a second bar of cans in front of the spot's, two on the stage in magenta and amber,
## two on the curtain in blue and amber, all breathing with the band.
func _rig_the_show() -> void:
	var stage := stage_centre()
	var x0 := stage.x - 1.6
	var x1 := stage.x + 1.6
	ZoneKit.block(self, Vector3(x1 - x0 + 0.3, 0.05, 0.05), Vector3((x0 + x1) * 0.5, HEIGHT - 0.42, RIG_Z), _black(), "Rig")
	for x: float in [x0 + 0.1, x1 - 0.1]:
		ZoneKit.block(self, Vector3(0.02, 0.37, 0.02), Vector3(x, HEIGHT - 0.21, RIG_Z), _black(), "RigDrop")
	var aims := [Vector3(stage.x - 2.4, 1.6, LIVE_ROOM_BACK - 0.3), Vector3(stage.x - 0.5, ZoneKit.RISER_HEIGHT, stage.z),
			Vector3(stage.x + 0.5, ZoneKit.RISER_HEIGHT, stage.z + 0.2), Vector3(stage.x + 2.4, 1.6, LIVE_ROOM_BACK - 0.3)]
	var colours := [Color(0.3, 0.45, 1.0), Color(1.0, 0.25, 0.55), Color(1.0, 0.6, 0.2), Color(0.3, 0.45, 1.0)]
	for i in 4:
		var at := Vector3(lerpf(x0, x1, i / 3.0), HEIGHT - 0.6, RIG_Z)
		var light := _can(at, aims[i], colours[i], 2.4 if i in [1, 2] else 3.0, 20.0 if i in [1, 2] else 28.0)
		washes.append(light)
		_wash_energy.append(light.light_energy)


## Showtime: the marquee on the front wall where the after-hours sign hangs, its two sets of
## bulbs chasing (_process) and its neon brightening with the band (pulse()).
func _light_the_marquee() -> void:
	var swaps := _show_swaps().duplicate()
	var panel := _plain(Color(0.16, 0.02, 0.03), 0.25)
	panel.clearcoat_enabled = true
	panel.clearcoat = 0.7
	swaps["panel"] = panel
	for key in ["bulb_a", "bulb_b"]:
		var bulb := ZoneKit.glow(BULB, 1.0)
		swaps[key] = bulb
		_bulbs.append(bulb)
	for i in 2:
		var tube := ZoneKit.glow(NEON[i], 1.0)
		swaps[["tube_red", "tube_blue"][i]] = tube
		_neon.append(tube)
	var sign := _set_piece(SHOW_MODELS, "Marquee", swaps)
	sign.name = "Marquee"
	sign.position = Vector3(0.6, 2.95, FRONT + 0.012)
	for spec in [[Vector3(0.25, 3.15, FRONT + 0.6), Color(1.0, 0.18, 0.12), 0.7],
			[Vector3(0.95, 2.65, FRONT + 0.6), Color(0.3, 0.45, 1.0), 0.5],
			[Vector3(0.6, 2.95, FRONT + 0.9), Color(1.0, 0.75, 0.45), 0.5]]:
		var glow := OmniLight3D.new()
		glow.name = "MarqueeGlow"
		glow.position = spec[0]
		glow.light_color = spec[1]
		glow.light_energy = spec[2]
		glow.omni_range = 2.8
		add_child(glow)


## Showtime: the band's things set ready -- the piano's lid up and a score on its desk, its bench
## before it, the bass stood in its stand beside it -- and a lamp over them.
func _set_the_stage_for_the_band() -> void:
	var swaps := _show_swaps()
	var piano := _set_piece(SHOW_MODELS, "PianoOpen", swaps)
	piano.name = "Piano"
	piano.transform = piano_case()
	var bench := _set_piece(SHOW_MODELS, "PianoBench", swaps)
	bench.name = "PianoBench"
	bench.rotation.y = PI * 0.5
	bench.position = Vector3(piano_bench_at().x, 0, piano_bench_at().y)
	var bass := _set_piece(SHOW_MODELS, "BassUpright", swaps)
	bass.name = "Bass"
	# Belly to the room (+X), its stand behind it.
	bass.rotation.y = PI * 0.5
	bass.position = Vector3(bass_stand_at().x, 0, bass_stand_at().y)
	var over := SpotLight3D.new()
	over.name = "PianoLight"
	over.light_color = Color(1.0, 0.74, 0.48)
	over.light_energy = 1.6
	over.spot_range = 4.6
	over.spot_angle = 30.0
	over.position = Vector3(piano_x() + 1.2, HEIGHT - 0.2, PIANO_Z - 0.3)
	over.basis = Basis.looking_at(Vector3(piano_x() + 0.3, 1.0, PIANO_Z - 0.3) - over.position, Vector3.UP)
	add_child(over)


## Showtime: bistro tables and bentwood chairs set out in the strips' corners, a candle and two
## glasses on each; a coat stand by the door with the first hats on it, and champagne on ice.
func _set_out_the_tables() -> void:
	var club := load(MODELS + "club.glb") as PackedScene
	for t in SHOW_TABLES.size():
		var at := show_table_at(t)
		var table := _piece(club, "Table")
		table.name = "ShowTable%d" % t
		table.position = Vector3(at.x, 0, at.y)
		_candle(Vector3(at.x + 0.06, 0.74, at.y - 0.05))
		for spot in chair_spots(t):
			var chair := _piece(club, "Chair")
			chair.name = "Chair"
			var to := at - spot
			# The chair's seat opens to its +Z: turned to face its table.
			chair.rotation.y = atan2(to.x, to.y)
			chair.position = Vector3(spot.x, 0, spot.y)
			var glass := _piece(club, "Glass2")
			glass.name = "SetGlass"
			glass.position = Vector3(at.x, 0.74, at.y) + Vector3(-to.x, 0, -to.y).normalized() * 0.2
			glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Two more on each booth table, and a bottle of wine open on the first.
	var x := -live_room_half() + BENCH * 0.5
	for z: float in BOOTHS:
		for dz: float in [-0.16, 0.16]:
			var glass := _piece(club, "Glass1")
			glass.name = "SetGlass"
			glass.position = Vector3(x - 0.1, 0.74, z + dz)
			glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var wine := _piece(club, "Bottle0")
	wine.name = "Wine"
	wine.position = Vector3(x - 0.16, 0.74, BOOTHS[0])
	var swaps := _show_swaps()
	var stand := _set_piece(SHOW_MODELS, "CoatStand", swaps)
	stand.name = "CoatStand"
	stand.position = Vector3(coat_stand_at().x, 0, coat_stand_at().y)
	stand.rotation.y = 0.6
	var bucket := _set_piece(SHOW_MODELS, "Bucket", swaps)
	bucket.name = "Bucket"
	bucket.position = Vector3(bucket_at().x, 0, bucket_at().y)


## Showtime: footlights along the front edge of the stage, hoods toward the band.
func _footlights(drums: Node3D, riser: Vector2) -> void:
	var swaps := _show_swaps()
	var spots: Array = []
	var count := 6
	for i in count:
		var x := (i + 0.5) / count * (riser.x - 0.4) - (riser.x - 0.4) * 0.5
		spots.append(Transform3D(Basis.IDENTITY, Vector3(x, ZoneKit.RISER_HEIGHT + 0.001, -riser.y * 0.5 + 0.07)))
	var lights := _scatter(_mesh_of(SHOW_MODELS, "Footlight", swaps), spots, "Footlights", false)
	remove_child(lights)
	drums.add_child(lights)
	var glow := OmniLight3D.new()
	glow.name = "FootlightGlow"
	glow.light_color = Color(1.0, 0.7, 0.42)
	glow.light_energy = 0.6
	glow.omni_range = 2.2
	glow.position = Vector3(0, ZoneKit.RISER_HEIGHT + 0.25, -riser.y * 0.5 + 0.3)
	drums.add_child(glow)


# --- speakeasy -------------------------------------------------------------------------------

## Where every Edison bulb hangs (its socket's top), gathered as the room is built and strung in
## one MultiMesh (_string_the_bulbs).
var _bulb_spots: Array[Vector3] = []


## club_speakeasy.glb's materials.
func _speak_swaps() -> Dictionary:
	if _speak_swaps_made.is_empty():
		var gilt := _plain(Color(0.78, 0.58, 0.26), 0.3)
		gilt.metallic = 1.0
		var bulb := _bottle_glass(Color(1.0, 0.78, 0.5, 0.3))
		bulb.emission_enabled = true
		bulb.emission = Color(1.0, 0.55, 0.22)
		bulb.emission_energy_multiplier = 0.5
		var frost := _plain(Color(0.95, 0.86, 0.7), 0.5)
		frost.emission_enabled = true
		frost.emission = Color(1.0, 0.72, 0.42)
		frost.emission_energy_multiplier = 1.3
		var shade := _plain(Color(0.03, 0.22, 0.09), 0.12)
		shade.metallic_specular = 0.9
		shade.emission_enabled = true
		shade.emission = Color(0.06, 0.4, 0.14)
		shade.emission_energy_multiplier = 0.6
		shade.cull_mode = BaseMaterial3D.CULL_DISABLED
		var horn := _brass()
		horn.cull_mode = BaseMaterial3D.CULL_DISABLED
		# Smoked glass rather than silver: with no reflections down here a true mirror is black.
		var mirror := _plain(Color(0.2, 0.18, 0.16), 0.15)
		mirror.metallic = 0.5
		mirror.metallic_specular = 0.9
		var iron := _plain(Color(0.06, 0.055, 0.05), 0.55)
		iron.metallic = 0.7
		_speak_swaps_made = {"oak": Materials.cached_scanned("club_oak", "weathered_brown_planks", "2k", 1.0,
					Color(0.7, 0.5, 0.34)),
				"hoop": iron, "head": _plain(Color(0.2, 0.13, 0.08), 0.85), "brass": horn, "walnut": _walnut(),
				"book_red": _plain(Color(0.34, 0.05, 0.04), 0.7), "book_green": _plain(Color(0.05, 0.19, 0.1), 0.7),
				"book_brown": _plain(Color(0.3, 0.17, 0.08), 0.75), "book_navy": _plain(Color(0.06, 0.08, 0.2), 0.7),
				"book_black": _plain(Color(0.05, 0.045, 0.04), 0.6), "gilt": gilt,
				"crate": Materials.cached_scanned("club_crate", "weathered_brown_planks", "2k", 0.7, Color(0.8, 0.64, 0.46)),
				"stencil": _plain(Color(0.06, 0.05, 0.04), 0.9), "socket": _brass(), "bulb": bulb,
				"filament": ZoneKit.glow(Color(1.0, 0.52, 0.18), 7.0), "mirror": mirror,
				"black": _plain(Color(0.02, 0.02, 0.02), 0.4), "frost": frost, "baize": _cloth(Color(0.03, 0.2, 0.09)),
				"leather": _leather(), "chip_red": _plain(Color(0.55, 0.06, 0.05), 0.4),
				"chip_white": _plain(Color(0.85, 0.82, 0.76), 0.4), "chip_black": _plain(Color(0.04, 0.04, 0.04), 0.4),
				"card": _plain(Color(0.92, 0.9, 0.85), 0.6), "card_back": _plain(Color(0.45, 0.06, 0.08), 0.6),
				"ash": _plain(Color(0.5, 0.5, 0.48), 0.95), "cigar": _plain(Color(0.28, 0.16, 0.08), 0.8),
				"glass_clear": _bottle_glass(Color(0.75, 0.8, 0.8, 0.35)), "shellac": _plain(Color(0.02, 0.02, 0.02), 0.15),
				"label": _plain(Color(0.55, 0.1, 0.08), 0.6), "shade": shade}
	return _speak_swaps_made


## The panelling's walnut, darker than the bar's.
func _panelling() -> StandardMaterial3D:
	return Materials.cached_scanned("club_panel", "black_walnut_veneer_01", "2k", 0.9, Color(0.2, 0.14, 0.1))


## A bulb to hang from the joists (strung by _string_the_bulbs).
func _hang_bulb(at: Vector3) -> void:
	_bulb_spots.append(at)


## A light that wavers with the bulbs (_process).
func _flickers(light: Light3D) -> void:
	bulb_lights.append(light)
	_bulb_energy.append(light.light_energy)


## Speakeasy: brick over dark panelling all round, ribbed in brass and capped; the front wall
## with a doorway behind the bookcase door; deco sconces on the panelling.
func _panel_the_walls() -> void:
	var half := live_room_half()
	var brick := _brick()
	var panel := _panelling()
	var brass := _brass()
	var z0 := FRONT
	var z1 := LIVE_ROOM_BACK
	var length := z1 - z0
	var mid := (z0 + z1) * 0.5
	var ribs: Array[Transform3D] = []
	for side: float in [-1.0, 1.0]:
		ZoneKit.block(self, Vector3(WALL, HEIGHT, length + WALL * 2.0), Vector3(side * (half + WALL * 0.5), HEIGHT * 0.5, mid),
				brick, "SideWall")
		ZoneKit.block(self, Vector3(0.04, PANEL, length - 0.004), Vector3(side * (half - 0.02), PANEL * 0.5, mid), panel, "Panelling")
		ZoneKit.block(self, Vector3(0.07, 0.05, length - 0.01), Vector3(side * (half - 0.037), PANEL + 0.02, mid), panel, "CapRail")
		# A millimetre off the panelling, clear of the back bar's mirror where it passes behind it.
		ZoneKit.block(self, Vector3(0.008, 0.02, length - 0.02), Vector3(side * (half - 0.045), PANEL - 0.05, mid), brass, "BrassBand")
		var z := z0 + 0.6
		while z < z1 - 0.3:
			ribs.append(Transform3D(Basis.IDENTITY, Vector3(side * (half - 0.046), PANEL * 0.5 - 0.1, z)))
			z += 1.2
	# The back wall: brick and panelling, the curtain over it.
	ZoneKit.block(self, Vector3(half * 2.0, HEIGHT, WALL), Vector3(0, HEIGHT * 0.5, z1 + WALL * 0.5), brick, "EndWall")
	ZoneKit.block(self, Vector3(half * 2.0 - 0.1, PANEL, 0.04), Vector3(0, PANEL * 0.5, z1 - 0.02), panel, "Panelling")
	# The front wall, in three pieces round the doorway to the stair.
	var door := stair_door()
	var zf := z0 - WALL * 0.5
	ZoneKit.block(self, Vector3(door.x + half, HEIGHT, WALL), Vector3((door.x - half) * 0.5, HEIGHT * 0.5, zf), brick, "EndWall")
	ZoneKit.block(self, Vector3(half - door.y, HEIGHT, WALL), Vector3((door.y + half) * 0.5, HEIGHT * 0.5, zf), brick, "EndWall")
	ZoneKit.block(self, Vector3(door.y - door.x, HEIGHT - 2.3, WALL), Vector3((door.x + door.y) * 0.5, (HEIGHT + 2.3) * 0.5, zf),
			brick, "Lintel")
	# Panelling along the front past the bookcases, ribbed but kept clear of the Rig Roulette
	# panel that hangs on this wall and of the sconces.
	var from := -half + 0.05 + BAY.x * BAYS + 0.02
	ZoneKit.block(self, Vector3(half - 0.05 - from, PANEL, 0.04), Vector3((from + half - 0.05) * 0.5, PANEL * 0.5, z0 + 0.02), panel,
			"Panelling")
	# (stopping short of the side walls' own rails and bands, as the after-hours wainscot does)
	ZoneKit.block(self, Vector3(half - 0.075 - from, 0.05, 0.07), Vector3((from + half - 0.075) * 0.5, PANEL + 0.02, z0 + 0.037),
			panel, "CapRail")
	# The band stops at the Rig Roulette door's frame either side, rather than running across it.
	var door_x := rig_roulette_door().origin.x
	var band_ends := [[from, door_x - RouletteDoor.HALF.x - 0.01], [door_x + RouletteDoor.HALF.x + 0.01, half - 0.075]]
	for ends: Array in band_ends:
		if ends[1] - ends[0] > 0.05:
			ZoneKit.block(self, Vector3(ends[1] - ends[0], 0.02, 0.008), Vector3((ends[0] + ends[1]) * 0.5, PANEL - 0.05, z0 + 0.044),
					brass, "BrassBand")
	var roulette := rig_roulette_spot().origin.x
	var sconce_x := [0.6 - 1.75, 0.6 + 1.75]
	var x := from + 0.6
	while x < half - 0.3:
		if absf(x - roulette) > 0.6 and sconce_x.all(func(s: float): return absf(x - s) > 0.3):
			ribs.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x, PANEL * 0.5 - 0.1, z0 + 0.046)))
		x += 1.2
	var rib := BoxMesh.new()
	rib.size = Vector3(0.012, PANEL - 0.35, 0.03)
	rib.material = brass
	_scatter(rib, ribs, "BrassRibs", false)
	# Deco sconces: three on each side wall between the ribs (over the booths and the crates, past
	# the bar and the far booth, and in the back of house clear of the booth and the synth), two on
	# the front wall either side of the sunburst.
	var lamps: Array[Transform3D] = []
	for side: float in [-1.0, 1.0]:
		for k: float in ([1.0, 6.0, 10.0] if side < 0.0 else [1.0, 6.0, 11.0]):
			var z := z0 + 1.2 * k
			lamps.append(Transform3D(Basis(Vector3.UP, -side * PI * 0.5), Vector3(side * (half - 0.041), 1.8, z)))
	for sx: float in sconce_x:
		lamps.append(Transform3D(Basis.IDENTITY, Vector3(sx, 1.75, z0 + 0.041)))
	var swaps := _speak_swaps()
	for at in lamps:
		var sconce := _set_piece(SPEAK_MODELS, "DecoSconce", swaps)
		sconce.name = "DecoSconce"
		sconce.transform = at.scaled_local(Vector3.ONE * 1.35)
		var lamp := OmniLight3D.new()
		lamp.name = "SconceLight"
		lamp.light_color = Color(1.0, 0.66, 0.36)
		lamp.light_energy = 0.75
		lamp.omni_range = 2.8
		lamp.position = at * Vector3(0, 0.25, 0.3)
		add_child(lamp)
		_flickers(lamp)


## Speakeasy: bare joists under dark boards, and two old pipes running the length of the room.
func _bare_the_joists() -> void:
	var half := live_room_half()
	ZoneKit.block(self, Vector3(half * 2.0, 0.1, LIVE_ROOM_BACK - FRONT), Vector3(0, HEIGHT + 0.05, (FRONT + LIVE_ROOM_BACK) * 0.5),
			Materials.cached_scanned("club_deck", "weathered_brown_planks", "2k", 2.0, Color(0.22, 0.17, 0.13)), "Ceiling")
	var joist := BoxMesh.new()
	joist.size = Vector3(half * 2.0 - 0.01, 0.22, 0.12)
	joist.material = Materials.cached_scanned("club_joist", "weathered_brown_planks", "2k", 1.4, Color(0.3, 0.22, 0.16))
	var spots: Array[Transform3D] = []
	var z := FRONT + 0.45
	while z < LIVE_ROOM_BACK - 0.4:
		spots.append(Transform3D(Basis.IDENTITY, Vector3(0, HEIGHT - 0.11, z)))
		z += 0.9
	_scatter(joist, spots, "Joists")
	var pipe := MeshInstance3D.new()
	for spec in [[half - 0.5, HEIGHT - 0.3, 0.05], [half - 0.75, HEIGHT - 0.32, 0.035]]:
		var run := CylinderMesh.new()
		run.top_radius = spec[2]
		run.bottom_radius = spec[2]
		run.height = LIVE_ROOM_BACK - FRONT - 0.02
		run.radial_segments = 12
		pipe = MeshInstance3D.new()
		pipe.name = "Pipe"
		pipe.mesh = run
		pipe.material_override = _plain(Color(0.2, 0.12, 0.08), 0.5)
		(pipe.material_override as StandardMaterial3D).metallic = 0.8
		pipe.rotation.x = PI * 0.5
		pipe.position = Vector3(spec[0], spec[1], (FRONT + LIVE_ROOM_BACK) * 0.5)
		add_child(pipe)


## Speakeasy: the front of the left strip is shelves of books, and the middle bay is the door: it
## stands open on the stair up to the street, a bulb burning at its foot and the street's own
## light at the top, and its light spills out across the boards through the gap.
func _open_the_bookcase() -> void:
	var swaps := _speak_swaps()
	for i in BAYS:
		var bay := _set_piece(SPEAK_MODELS, "Bookcase", swaps)
		bay.name = "SecretDoor" if i == DOOR_BAY else "Bookcase%d" % i
		bay.transform = bay_transform(i)
	# Two bulbs hung in front of the shelves, enough to read the spines by.
	for i in [0, 2]:
		var front := bay_transform(i) * Vector3(0, 0, BAY.z + 0.55)
		_hang_bulb(Vector3(front.x, 2.55, front.z))
		var shelf_light := OmniLight3D.new()
		shelf_light.name = "ShelfBulb"
		shelf_light.light_color = Color(1.0, 0.62, 0.32)
		shelf_light.light_energy = 0.9
		shelf_light.omni_range = 2.6
		shelf_light.position = Vector3(front.x, 2.3, front.z)
		add_child(shelf_light)
		_flickers(shelf_light)
	var door := stair_door()
	var w := door.y - door.x
	var cx := (door.x + door.y) * 0.5
	var back := FRONT - WALL
	var brick := _brick()
	# The passage's floor, from under the wall back to the foot of the stair.
	var floor_from := FRONT - WALL * 0.5 - 0.002
	var floor_to := back - STAIR_DEPTH
	ZoneKit.block(self, Vector3(w + 0.1, 0.1, floor_from - floor_to), Vector3(cx, -0.05, (floor_from + floor_to) * 0.5),
			Materials.cached_scanned("club_boards", "weathered_brown_planks", "2k", 2.6, Color(0.42, 0.32, 0.25)), "PassageFloor")
	for sx: float in [-1.0, 1.0]:
		var x := cx + sx * (w * 0.5 + 0.01 + WALL * 0.5)
		ZoneKit.block(self, Vector3(WALL, 3.4, STAIR_DEPTH), Vector3(x, 1.7, back - STAIR_DEPTH * 0.5), brick, "PassageWall")
	ZoneKit.block(self, Vector3(w + 0.02, WALL, STAIR_DEPTH), Vector3(cx, 3.4 - WALL * 0.5 + 0.01, back - STAIR_DEPTH * 0.5), brick,
			"PassageCeiling")
	ZoneKit.block(self, Vector3(w + 0.1, 3.4, WALL), Vector3(cx, 1.7, back - STAIR_DEPTH - WALL * 0.5), brick, "PassageEnd")
	var steps := int((STAIR_DEPTH - 0.5) / TREAD)
	var oak: Material = swaps["oak"]
	for k in steps:
		var tall := RISE * (k + 1)
		ZoneKit.block(self, Vector3(w, tall, TREAD), Vector3(cx, tall * 0.5, back - 0.5 - TREAD * (k + 0.5)), oak, "Step")
	_hang_bulb(Vector3(cx, 2.45, back - 0.35))
	var foot := OmniLight3D.new()
	foot.name = "StairBulb"
	foot.light_color = Color(1.0, 0.6, 0.3)
	foot.light_energy = 1.6
	foot.omni_range = 3.0
	foot.position = Vector3(cx, 2.1, back - 0.35)
	add_child(foot)
	_flickers(foot)
	var street := OmniLight3D.new()
	street.name = "StreetLight"
	street.light_color = Color(0.5, 0.6, 1.0)
	street.light_energy = 0.7
	street.omni_range = 2.4
	street.position = Vector3(cx, 2.9, back - STAIR_DEPTH + 0.3)
	add_child(street)
	# What comes out through the gap: a wedge of warm light across the floor, cut by the door.
	var spill := SpotLight3D.new()
	spill.name = "DoorSpill"
	spill.light_color = Color(1.0, 0.62, 0.32)
	spill.light_energy = 3.5
	spill.spot_range = 6.0
	spill.spot_angle = 38.0
	spill.shadow_enabled = true
	spill.position = Vector3(cx - 0.2, 2.0, back - 0.3)
	spill.basis = Basis.looking_at(Vector3(cx + 0.7, 0.0, FRONT + 2.4) - spill.position, Vector3.UP)
	add_child(spill)


## Speakeasy: the barrels racked on their sides along the right strip's front wall, heads to the
## room, taps in the bottom row and what is in each chalked on its head; the crates beside them.
func _rack_the_barrels() -> void:
	var swaps := _speak_swaps()
	var rack := barrel_rack()
	var oak: Material = swaps["oak"]
	for dz: float in [0.16, BARREL_LONG - 0.16]:
		ZoneKit.block(self, Vector3(rack.size.x, CRADLE + 0.03, 0.09), Vector3(rack.get_center().x, (CRADLE + 0.03) * 0.5,
				rack.position.y + 0.05 + dz), oak, "Cradle")
	var spots := barrel_spots()
	var placed: Array = []
	var bottom := int((spots.size() + 1) / 2.0)
	var marks := ["RYE", "GIN", "XXX", "RUM", "1919", "No. 7"]
	for i in spots.size():
		var c := spots[i]
		var roll := Basis(Vector3.BACK, 0.7 * i + 0.3)
		placed.append(Transform3D(roll * Basis(Vector3.RIGHT, PI * 0.5), c - Vector3(0, 0, BARREL_LONG * 0.5)))
		var head := c.z + BARREL_LONG * 0.5 - 0.035
		var chalk := Label3D.new()
		chalk.name = "Chalk"
		chalk.text = marks[i % marks.size()]
		chalk.font_size = 48
		chalk.pixel_size = 0.0018
		chalk.modulate = Color(0.75, 0.72, 0.65, 0.8)
		chalk.double_sided = false
		chalk.position = Vector3(c.x, c.y + 0.08, head + 0.003)
		add_child(chalk)
		if i < bottom:
			var tap := _set_piece(SPEAK_MODELS, "Tap", swaps)
			tap.name = "Tap"
			# Out of the head along +Z, its spout down.
			tap.basis = Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN)
			tap.position = Vector3(c.x, c.y - 0.13, head)
	_scatter(_mesh_of(SPEAK_MODELS, "Barrel", swaps), placed, "Barrels")
	# A bulb hung over the rack, so the chalk can be read.
	_hang_bulb(Vector3(rack.get_center().x, 2.3, rack.end.y + 0.25))
	var over := OmniLight3D.new()
	over.name = "RackBulb"
	over.light_color = Color(1.0, 0.6, 0.3)
	over.light_energy = 1.0
	over.omni_range = 2.8
	over.position = Vector3(rack.get_center().x, 2.1, rack.end.y + 0.3)
	add_child(over)
	_flickers(over)
	var crates := crate_stack()
	var crate_mesh := _mesh_of(SPEAK_MODELS, "Crate", swaps)
	var cc := Vector3(crates.get_center().x, 0, crates.get_center().y)
	_scatter(crate_mesh, [Transform3D(Basis.IDENTITY, cc),
			Transform3D(Basis(Vector3.UP, 0.1), cc + Vector3(-0.02, 0.381, 0.01)),
			Transform3D(Basis(Vector3.UP, PI * 0.5 + 0.2), Vector3(stair_door().x + 0.4, 0, FRONT - WALL - 0.25))], "Crates")


## Speakeasy: a sunburst of mirror and brass over the desk on the front wall, and another
## crowning the back bar; brass bands and flutes on the bar's counter; bulbs over it.
func _hang_the_sunbursts() -> void:
	var swaps := _speak_swaps()
	var big := _set_piece(SPEAK_MODELS, "DecoMirror", swaps)
	big.name = "Sunburst"
	big.scale = Vector3.ONE * 1.15
	big.position = Vector3(0.6, PANEL + 0.13, FRONT + 0.012)
	var crest := _set_piece(SPEAK_MODELS, "DecoMirror", swaps)
	crest.name = "BarSunburst"
	crest.basis = Basis(Vector3.UP, -PI * 0.5).scaled(Vector3.ONE * 0.9)
	crest.position = Vector3(live_room_half() - 0.035, 2.62, (BAR_FROM + BAR_TO) * 0.5)


func _deco_the_counter(cx: float, length: float, mid: float) -> void:
	var brass := _brass()
	for y: float in [0.32, 0.95]:
		ZoneKit.block(self, Vector3(0.012, 0.03, length - 0.04), Vector3(bar_front() - 0.006, y, mid), brass, "CounterBand")
	var flutes: Array[Transform3D] = []
	var z := BAR_FROM + 0.3
	while z < BAR_TO - 0.2:
		flutes.append(Transform3D(Basis.IDENTITY, Vector3(bar_front() - 0.009, 0.635, z)))
		z += 0.5
	var flute := CylinderMesh.new()
	flute.top_radius = 0.012
	flute.bottom_radius = 0.012
	flute.height = 0.54
	flute.radial_segments = 8
	flute.material = brass
	_scatter(flute, flutes, "Flutes", false)
	# A row of bulbs over the counter at uneven drops, and the light they make.
	z = BAR_FROM + 0.25
	var k := 0
	while z < BAR_TO:
		_hang_bulb(Vector3(cx - 0.05, 2.35 + 0.18 * ((k * 3) % 4) / 3.0, z))
		z += 0.55
		k += 1
	for zz: float in [BAR_FROM + 0.9, BAR_TO - 0.9]:
		var over := OmniLight3D.new()
		over.name = "BarBulbs"
		over.light_color = Color(1.0, 0.6, 0.3)
		over.light_energy = 0.8
		over.omni_range = 2.6
		over.position = Vector3(cx - 0.05, 2.25, zz)
		add_child(over)
		_flickers(over)


## Speakeasy: the card table where the piano stood, three chairs drawn up, a hand dealt and the
## pot in the middle, under a green glass shade; and a standing barrel for a table in the strip's
## back corner with two stools.
func _deal_the_cards() -> void:
	var swaps := _speak_swaps()
	var at := card_table_at()
	var table := _set_piece(SPEAK_MODELS, "PokerTable", swaps)
	table.name = "CardTable"
	table.basis = Basis(Vector3.UP, PI * 0.125).scaled(Vector3(CARD_SCALE, 1.0, CARD_SCALE))
	table.position = Vector3(at.x, 0, at.y)
	var club := load(MODELS + "club.glb") as PackedScene
	for spot in card_chair_spots():
		var chair := _piece(club, "Chair")
		chair.name = "Chair"
		var to := at - spot
		chair.rotation.y = atan2(to.x, to.y) + 0.15
		chair.position = Vector3(spot.x, 0, spot.y)
	var shade := _set_piece(SPEAK_MODELS, "Shade", swaps)
	shade.name = "CardShade"
	shade.rotation.y = PI * 0.5
	shade.position = Vector3(at.x, 1.78, at.y)
	for dz: float in [-0.26, 0.26]:
		ZoneKit.block(self, Vector3(0.006, HEIGHT - 1.79, 0.006), Vector3(at.x, (HEIGHT + 1.77) * 0.5, at.y + dz), _black(), "Chain")
	# The bulbs inside the shade, seen from under it.
	var lit := ZoneKit.block(self, Vector3(0.4, 0.03, 0.05), Vector3(at.x, 1.69, at.y), ZoneKit.glow(Color(1.0, 0.8, 0.55), 3.0),
			"ShadeBulbs")
	lit.rotation.y = PI * 0.5
	lit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pool := SpotLight3D.new()
	pool.name = "CardLight"
	pool.light_color = Color(1.0, 0.82, 0.55)
	pool.light_energy = 3.0
	pool.spot_range = 2.6
	pool.spot_angle = 50.0
	pool.shadow_enabled = true
	pool.position = Vector3(at.x, 1.66, at.y)
	pool.rotation.x = -PI * 0.5
	add_child(pool)
	# The barrel table.
	var bt := barrel_table_at()
	var barrel := _set_piece(SPEAK_MODELS, "Barrel", swaps)
	barrel.name = "BarrelTable"
	barrel.position = Vector3(bt.x, 0, bt.y)
	var top := _set_piece(SPEAK_MODELS, "BarrelTop", swaps)
	top.name = "BarrelTop"
	top.position = Vector3(bt.x, BARREL_LONG + 0.001, bt.y)
	_candle(Vector3(bt.x + 0.05, BARREL_LONG + 0.046, bt.y - 0.05))
	var glass := _piece(club, "Glass0")
	glass.name = "LeftGlass"
	glass.position = Vector3(bt.x - 0.15, BARREL_LONG + 0.046, bt.y + 0.08)
	for stool_at in barrel_stools():
		var stool := _piece(club, "Stool")
		stool.name = "BarrelStool"
		stool.position = Vector3(stool_at.x, 0, stool_at.y)
		stool.rotation.y = stool_at.x


## Speakeasy: the gramophone in the strip's front corner, its horn to the room.
func _wind_the_gramophone() -> void:
	var g := _set_piece(SPEAK_MODELS, "Gramophone", _speak_swaps())
	g.name = "Gramophone"
	g.rotation.y = PI * 0.3
	g.position = Vector3(gramophone_at().x, 0, gramophone_at().y)


## Speakeasy: no spot on the stage, only a line of bare bulbs hung low over its front and two
## warm lamps on it from the joists.
func _light_the_band_low() -> void:
	var stage: AABB = zones()[&"drums"]
	var n := 7
	for i in n:
		var u := i / float(n - 1)
		_hang_bulb(Vector3(lerpf(stage.position.x + 0.1, stage.end.x - 0.1, u), 3.05 - 0.15 * sin(u * PI),
				stage.position.z + 0.2))
	var centre := stage_centre()
	for sx: float in [-0.7, 0.7]:
		var lamp := SpotLight3D.new()
		lamp.name = "StageLamp"
		lamp.light_color = Color(1.0, 0.66, 0.38)
		lamp.light_energy = 7.0
		lamp.spot_range = 9.0
		lamp.spot_angle = 24.0
		lamp.position = Vector3(centre.x + sx, HEIGHT - 0.25, stage.position.z - 0.6)
		lamp.basis = Basis.looking_at(centre + Vector3(sx * 0.4, 0, 0.2) - lamp.position, Vector3.UP)
		add_child(lamp)
	var glow := OmniLight3D.new()
	glow.name = "StageBulbs"
	glow.light_color = Color(1.0, 0.58, 0.28)
	glow.light_energy = 0.9
	glow.omni_range = 3.0
	glow.position = Vector3(centre.x, 2.8, stage.position.z + 0.3)
	add_child(glow)
	_flickers(glow)


## Where the house lights fall in the back of house: the middle of each neighbourhood round the
## zones (harmony off the bricks table's long side, synth off its stand, the lattice, tape and toys
## off the prop shelf), and the walk down the middle between them.
func house_light_spots() -> Array[Vector3]:
	var z := zones()
	var out: Array[Vector3] = []
	if z.has(&"bricks"):
		var c := (z[&"bricks"] as AABB).get_center()
		out.append(Vector3(c.x - HARMONY_AISLE, 0, c.z + 0.6))
	if z.has(&"synth"):
		var c := (z[&"synth"] as AABB).get_center()
		out.append(Vector3(c.x - SYNTH_MIDDLE, 0, c.z))
	if z.has(&"matrix"):
		var c := (z[&"matrix"] as AABB).get_center()
		out.append(Vector3(c.x, (z[&"matrix"] as AABB).end.y, c.z))
	var shelf := prop_shelf_spot().origin
	out.append(Vector3(shelf.x + signf(-shelf.x) * TOYS_ACROSS * 0.5, 0, shelf.z + 1.0))
	out.append(Vector3(2.6, 0, (Studio.ROOM_BACK + LIVE_ROOM_BACK) * 0.5 - 1.0))
	return out


## The back of house is twice the floor it was: a warm can on the tin over each neighbourhood, a
## pool of light to work in, the way the spot is the stage's. In the speakeasy, bare bulbs dropped
## from the joists instead, a cluster over each.
func _light_the_house() -> void:
	for at in house_light_spots():
		var top := Vector3(at.x, HEIGHT - HOUSE_CAN_DROP, at.z - 0.6)
		if variant == SPEAKEASY:
			for k in 3:
				_hang_bulb(Vector3(at.x - 0.25 + 0.25 * k, 3.6 + 0.15 * ((k + 1) % 2), at.z - 0.6 + 0.1 * (k - 1)))
			var bulbs := OmniLight3D.new()
			bulbs.name = "HouseBulbs"
			bulbs.light_color = Color(1.0, 0.6, 0.3)
			bulbs.light_energy = 2.2
			bulbs.omni_range = 5.5
			bulbs.position = Vector3(at.x, 3.4, at.z - 0.6)
			add_child(bulbs)
			_flickers(bulbs)
			continue
		ZoneKit.block(self, Vector3(0.03, HOUSE_CAN_DROP - 0.1, 0.03), Vector3(top.x, HEIGHT - (HOUSE_CAN_DROP - 0.1) * 0.5, top.z),
				_black(), "HouseCanDrop")
		# Under the stage spot's 14: that one is the room's only hard light.
		var light := _can(top, at, Color(1.0, 0.74, 0.46), 4.6 if variant == SHOWTIME else 4.0, 44.0)
		light.name = "HouseLight"
		light.spot_range += 1.5


## Speakeasy: every bulb gathered above strung at once, each on its own cord up to the boards.
func _string_the_bulbs() -> void:
	var swaps := _speak_swaps()
	var bulbs: Array = []
	var cords: Array = []
	for at in _bulb_spots:
		bulbs.append(Transform3D(Basis(Vector3.UP, at.x * 3.0 + at.z), at))
		var drop := HEIGHT - at.y
		cords.append(Transform3D(Basis.from_scale(Vector3(1, drop, 1)), at + Vector3(0, drop * 0.5, 0)))
	_scatter(_mesh_of(SPEAK_MODELS, "Edison", swaps), bulbs, "Bulbs", false)
	var cord := BoxMesh.new()
	cord.size = Vector3(0.007, 1.0, 0.007)
	cord.material = _black()
	_scatter(cord, cords, "Cords", false)


## Speakeasy: smoke hanging in layers under the joists, thickest over the card table and the
## stage, warmed where it hangs near a bulb (club_smoke.gdshader).
func _blow_the_smoke() -> void:
	var half := live_room_half()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1920
	var lamps: Array[Vector3] = _bulb_spots.duplicate()
	var card := card_table_at()
	lamps.append(Vector3(card.x, 1.7, card.y))
	var where: Array[Vector3] = []
	for i in SMOKE:
		where.append(Vector3(rng.randf_range(-half + 1.0, half - 1.0), rng.randf_range(HEIGHT - 2.7, HEIGHT - 0.6),
				rng.randf_range(FRONT + 1.0, LIVE_ROOM_BACK - 1.0)))
	for i in 8:
		where.append(Vector3(card.x + rng.randf_range(-0.5, 0.5), rng.randf_range(1.5, 2.2), card.y + rng.randf_range(-0.6, 0.6)))
	var stage := stage_centre()
	for i in 6:
		where.append(Vector3(stage.x + rng.randf_range(-1.2, 1.2), rng.randf_range(1.8, 3.0), stage.z + rng.randf_range(-0.8, 0.8)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mm.mesh = quad
	mm.instance_count = where.size()
	for i in where.size():
		var at := where[i]
		var warm := 0.0
		for l in lamps:
			warm += exp(-at.distance_squared_to(l) / 1.2)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * rng.randf_range(1.4, 2.8)), at))
		mm.set_instance_custom_data(i, Color(rng.randf(), clampf(warm, 0.0, 1.0), 0, 0))
	var smoke := MultiMeshInstance3D.new()
	smoke.name = "Smoke"
	smoke.multimesh = mm
	var haze := ShaderMaterial.new()
	haze.shader = preload("res://core/venues/shaders/club_smoke.gdshader")
	smoke.material_override = haze
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.custom_aabb = AABB(Vector3(-half, 1.0, FRONT), Vector3(half * 2.0, HEIGHT - 1.0, LIVE_ROOM_BACK - FRONT))
	add_child(smoke)


# --- the zones -------------------------------------------------------------------------------

## The zones: the stage is the drum riser, walnut on black; the booth framed in black; a brass
## square on the floor for the lattice; a walnut table; the keys.
func _dress_zones() -> void:
	var z := zones()
	var walnut := _walnut()
	var black := _black()

	var drums := ZoneKit.holder(self, &"drums", z[&"drums"])
	var drum_box: AABB = z[&"drums"]
	var riser := Vector2(drum_box.size.x, drum_box.size.z) - Vector2.ONE * ZoneKit.RISER_INSET
	ZoneKit.riser(drums, riser, ZoneKit.RISER_HEIGHT, walnut, black)
	if variant == SHOWTIME:
		_footlights(drums, riser)

	var vocals := ZoneKit.holder(self, &"vocals", z[&"vocals"])
	var booth_box: AABB = z[&"vocals"]
	var glass := _bottle_glass(Color(0.4, 0.4, 0.4, 0.08))
	ZoneKit.booth(vocals, booth_box.size, ZoneKit.BOOTH_DOOR_SIDE, black, glass)
	ZoneKit.mic_stand(vocals, ZoneKit.MIC_AT + Vector3(0, 0.001, 0), Materials.brushed_metal(), ZoneKit.MIC_YAW)
	ZoneKit.spot_down(vocals, Vector3(0, booth_box.size.y - 0.08 - 0.046, 0.1), Color(1.0, 0.75, 0.5),
			1.1, 60.0, 3.2, black)

	var matrix := ZoneKit.holder(self, &"matrix", z[&"matrix"])
	ZoneKit.floor_frame(matrix, Vector2(3.08, 3.08), Vector3(0, 0.001, 0), 0.03, _brass())

	var bricks := ZoneKit.holder(self, &"bricks", z[&"bricks"])
	ZoneKit.table(bricks, ZoneKit.TABLE_TOP, ZoneKit.TABLE_HEIGHT, 0.06, walnut, black)
	_dress_prop_shelf(walnut, black)

	var synth := ZoneKit.holder(self, &"synth", z[&"synth"])
	ZoneKit.keyboard_stand(synth, ZoneKit.STAND_WIDTH, Materials.brushed_metal(), black)


## One named piece from club.glb, its materials swapped for the club's own.
func _piece(scene: PackedScene, piece: String) -> Node3D:
	var all := scene.instantiate()
	var node := all.find_child(piece, true, false) as MeshInstance3D
	node.get_parent().remove_child(node)
	all.free()
	node.transform = Transform3D.IDENTITY
	var swaps := _swaps()
	for s in node.mesh.get_surface_count():
		var m := node.mesh.surface_get_material(s)
		if m != null and swaps.has(m.resource_name):
			node.set_surface_override_material(s, swaps[m.resource_name])
	add_child(node)
	return node


func _model(file: String, at: Vector3, yaw: float, swap: Dictionary) -> Node3D:
	var node := (load(MODELS + file) as PackedScene).instantiate() as Node3D
	node.position = at
	node.rotation.y = yaw
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
	add_child(node)
	return node


func _frame_mirror(mirror: Mirror) -> void:
	Venue.frame_bars(mirror, 0.05, 0.035, 0.012, _walnut())


## The tracks' colours here (TrackColours), in its STANDARD order.
## After hours: oxblood, amber and neon, saturated and a little dark, warm leaning.
func track_palette() -> Array:
	return [
		Color(0.88, 0.16, 0.23), Color(0.94, 0.44, 0.16), Color(0.96, 0.72, 0.18), Color(0.72, 0.84, 0.23),
		Color(0.25, 0.81, 0.42), Color(0.14, 0.76, 0.66), Color(0.18, 0.71, 0.94), Color(0.29, 0.42, 1.00),
		Color(0.61, 0.30, 1.00), Color(0.88, 0.23, 0.84), Color(1.00, 0.31, 0.58), Color(0.66, 0.60, 0.57),
	]
