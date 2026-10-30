class_name Neighbourhoods
extends RefCounted

## The room in named neighbourhoods: each a cluster of stations round a middle of its own, with
## walkways between them and a banner over the middle saying what it is.
##
## The room grew twenty stations one at a time, each put in whatever gap was left, until they
## stood nose to tail along one strip of the live room's back wall and a person could not walk to
## half of them (2026-10-28: "now EVERYTHING is way too cramped. All environments need an increase
## in size and better organization"). So the room is organised the way a real one is, by what you
## do in each part of it, and says so in words: a desktop player turned round from the desk reads
## RHYTHM and HARMONY & STRINGS over the floor rather than working out from the furniture where
## things are. Where each station stands is still the venue's (Venue's `default_*_spot`, from its
## zones); this is only which belong together, where their middle is, and the banner.
##
## The mixing neighbourhood is the control room's ring round the seat. The venue's own instrument
## and weather belong to no neighbourhood: they are the venue's, wherever it puts them.

## In the order a person meets them coming out of the control room. `stations` are the Stations
## ids that make up the neighbourhood (those of them that stand in a venue); `pieces`, what else of
## the room's furniture belongs there (Venue.WHEELED ids), which helps place the middle; `lift` (m),
## how much higher than SIGN_HEIGHT its own banner hangs: from the desk the harmony and synth banners
## stand one behind the other along the right of the room, and their long titles at one height ran
## into each other, so the near one hangs lower and the far one higher.
const ALL := [
	{"id": &"mixing", "title": "MIXING", "colour": Color(0.95, 0.86, 0.62),
			"stations": [&"stage_table", &"platter", &"eq_wall", &"levels"], "pieces": []},
	{"id": &"rhythm", "title": "RHYTHM", "colour": Color(1.0, 0.62, 0.42),
			"stations": [&"drums", &"looper", &"marbles"], "pieces": []},
	{"id": &"harmony", "title": "HARMONY & STRINGS", "colour": Color(0.62, 0.86, 1.0),
			"stations": [&"harp", &"bells", &"wheel", &"sections", &"ledge", &"strings", &"music_box"], "pieces": [],
			"lift": -0.4},
	{"id": &"synth", "title": "SYNTH & SOUND DESIGN", "colour": Color(0.78, 0.66, 1.0),
			"stations": [&"modular", &"theremin", &"grains", &"sampler"], "pieces": [], "lift": 0.25},
	{"id": &"vocals", "title": "VOCALS", "colour": Color(1.0, 0.7, 0.82),
			"stations": [&"lyrics"], "pieces": []},
	{"id": &"tape", "title": "TAPE & TOYS", "colour": Color(0.7, 1.0, 0.72),
			"stations": [&"cassette_rack"], "pieces": [&"prop_shelf", &"tour_case", &"hoop"]},
]
## How high a banner hangs over its middle, by default (Venue.sign_height): over the lattice's
## shoulders and the booth's lid, under any ceiling a live room has.
const SIGN_HEIGHT := 2.9
## How far a station may stand from its neighbourhood's middle (m) and still be part of it: a
## cluster you can take in from its middle with a turn.
const RADIUS := 3.4
## How tall a banner's capitals are (m): read from across the live room, which the plaques are not.
const LETTER := 0.3


static func row(id: StringName) -> Dictionary:
	for r: Dictionary in ALL:
		if r["id"] == id:
			return r
	return {}


## Which neighbourhood station `station` belongs to, or empty for none (the venue's own).
static func of(station: StringName) -> StringName:
	for r: Dictionary in ALL:
		if (r["stations"] as Array).has(station):
			return r["id"]
	return &""


## The stations of neighbourhood `id` that stand in `venue`.
static func stations_in(venue: Venue, id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for s: StringName in row(id).get("stations", []):
		if Stations.spot(venue, s) != null:
			out.append(s)
	return out


## Neighbourhood `id`'s middle in `venue`, on the floor in studio space: the mixing one at the seat,
## every other the middle of the box round its stations and pieces where they stand now. Null where
## none of it stands (the Rig Roulette room's synth and vocals).
static func middle(venue: Venue, id: StringName) -> Variant:
	if id == &"mixing":
		return Vector3(0, 0, Studio.MIX_POSITION_Z)
	var points: Array[Vector2] = []
	for s in stations_in(venue, id):
		var at := (Stations.spot(venue, s) as Transform3D).origin
		points.append(Vector2(at.x, at.z))
	if points.is_empty():
		return null
	for p: StringName in row(id).get("pieces", []):
		var at: Variant = venue._spot_of(p)
		if at is Transform3D:
			points.append(Vector2((at as Transform3D).origin.x, (at as Transform3D).origin.z))
	var box := Rect2(points[0], Vector2.ZERO)
	for p in points:
		box = box.expand(p)
	var c := box.get_center()
	return Vector3(c.x, 0, c.y)


## How far over the control room's ceiling, and out from its open rear into the live room, the
## MIXING banner hangs.
const MIXING_ABOVE := 0.45
const MIXING_OUT := 0.12


## Where neighbourhood `id`'s banner hangs in `venue` (studio space): over its middle at the
## venue's sign height; the mixing one over the control room's open rear, facing the live room, where
## anyone coming back from it looks for the desk. Null where the neighbourhood does not stand.
static func sign_spot(venue: Venue, id: StringName) -> Variant:
	var m: Variant = middle(venue, id)
	if m == null:
		return null
	var at: Vector3 = m
	if id == &"mixing":
		# On the live room's side of the header over the opening, read from the live room only: from
		# the seat a banner overhead was the biggest thing in the view of the room behind.
		return Vector3(0, Studio.WALL_HEIGHT + MIXING_ABOVE, Studio.ROOM_BACK + MIXING_OUT)
	return Vector3(at.x, venue.sign_height() + float(row(id).get("lift", 0.0)), at.z)


## A banner: the neighbourhood's name in capitals, turned to whoever looks at it (so it reads from
## the seat, from the far wall and from the next neighbourhood alike), lit, and outlined dark so it
## reads against a lit wall or a night sky. Named "Sign_<id>"; its text is the title.
static func make_sign(id: StringName) -> Label3D:
	var r := row(id)
	var label := Label3D.new()
	label.name = "Sign_%s" % id
	label.text = String(r.get("title", id))
	label.font_size = 128
	label.outline_size = 24
	label.pixel_size = LETTER / 128.0 * 1.35
	label.modulate = r.get("colour", Color.WHITE)
	label.outline_modulate = Color(0.02, 0.02, 0.025, 0.85)
	# The mixing one faces the live room (+Z) from over the opening and is not seen from the seat;
	# every other turns to whoever looks.
	var facing_out := id == &"mixing"
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED if facing_out else BaseMaterial3D.BILLBOARD_FIXED_Y
	label.shaded = false
	label.double_sided = not facing_out
	label.no_depth_test = false
	label.fixed_size = false
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.set_meta(&"neighbourhood", id)
	return label
