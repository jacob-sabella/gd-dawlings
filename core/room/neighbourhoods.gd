class_name Neighbourhoods
extends RefCounted

## The room in named neighbourhoods: each a cluster of stations round a middle of its own, with
## walkways between them and a banner on the wall behind it saying what it is.
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
## how much higher than SIGN_HEIGHT its own banner hangs: the harmony and synth banners can both be
## on the right-hand wall, one along from the other, and their long titles at one height ran into
## each other, so the near one hangs lower and the far one higher.
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
## How high a banner hangs on its wall, by default (Venue.sign_height): over the lattice's
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


## How far in from a wall's face a banner is (m): proud of what is on the wall, as the studio's
## back-wall slats are (12 cm), so they do not cut through its letters.
const OFF_WALL := 0.15
## How far a banner's ends keep from the corners of its wall (m).
const CORNER_CLEAR := 0.3


## Where neighbourhood `id`'s banner hangs in `venue` (studio space), as a frame whose +Z is the way
## its face looks: flat on the wall nearest its middle, at the venue's sign height, as far along it
## as the middle is, and facing back into the room; the mixing one on the live room's side of the
## header over the control room's open rear, where anyone coming back from it looks for the desk.
## Null where the neighbourhood does not stand.
##
## Words in the air were too much (2026-10-29: "i don't like the floating text. its too present.
## put it on walls when you can"): a banner that turned to whoever looked hung in the middle of
## every view of the room. On a wall it is where a room's signs are, and the wall hides it from
## the other side. The walls are the edges of the floor (Walker.outline of the footprint and the
## venue's rooms), so a doorway is not one. A venue without walls (Venue.has_walls) has no banners:
## standing at the edge of an open floor they were words in the air again.
static func sign_spot(venue: Venue, id: StringName) -> Variant:
	if not venue.has_walls():
		return null
	var m: Variant = middle(venue, id)
	if m == null:
		return null
	var at: Vector3 = m
	if id == &"mixing":
		# On the live room's side of the header over the opening, read from the live room only: from
		# the seat a banner overhead was the biggest thing in the view of the room behind.
		return Transform3D(Basis.IDENTITY, Vector3(0, Studio.WALL_HEIGHT + MIXING_ABOVE, Studio.ROOM_BACK + MIXING_OUT))
	var high := venue.sign_height() + float(row(id).get("lift", 0.0))
	var mid := Vector2(at.x, at.z)
	var wall := _nearest_wall(venue, mid, sign_width(id))
	if wall.is_empty():
		return Transform3D(Basis.IDENTITY, Vector3(at.x, high, at.z))
	var normal: Vector2 = wall["normal"]
	var on: Vector2 = wall["at"] - normal * OFF_WALL
	# Its face looks back into the room, against the wall's outward normal.
	return Transform3D(Basis(Vector3.UP, atan2(-normal.x, -normal.y)), Vector3(on.x, high, on.y))


## How wide neighbourhood `id`'s banner is (m), as make_sign letters it.
static func sign_width(id: StringName) -> float:
	var font := ThemeDB.fallback_font
	var words := String(row(id).get("title", id))
	if font == null:
		return words.length() * LETTER
	return font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, 128).x * LETTER / 128.0 * 1.35


## The wall of the room `mid` is in (or the nearest room to it) that is nearest `mid`, as {"at": the
## point on it a banner `wide` across is centred on, "normal": its outward normal}; empty where the
## venue has no rooms past the footprint. A banner is slid along its wall to clear the corners, if
## the wall is long enough to.
static func _nearest_wall(venue: Venue, mid: Vector2, wide: float) -> Dictionary:
	var rooms := venue.rooms()
	if rooms.is_empty():
		return {}
	var home: Rect2 = rooms[0]
	var best_gap := INF
	for r in rooms:
		var gap := 0.0 if r.has_point(mid) else r.get_center().distance_to(mid) - r.size.length() * 0.5
		if gap < best_gap:
			best_gap = gap
			home = r
	var cr := venue.room_width * 0.5
	var floor_rects: Array[Rect2] = [Rect2(-cr + 0.05, Studio.ROOM_FRONT + 0.05, venue.room_width - 0.10, Studio.ROOM_DEPTH - 0.05)]
	floor_rects.append_array(rooms)
	var out := {}
	var nearest := INF
	var grown := home.grow(0.02)
	for e: Array in Walker.outline(floor_rects):
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		# Only the walls of its own room.
		if not grown.has_point(a) or not grown.has_point(b):
			continue
		var length := a.distance_to(b)
		if length < 0.01:
			continue
		var along := (b - a) / length
		var t := clampf((mid - a).dot(along), 0.0, length)
		var gap := mid.distance_to(a + along * t)
		if gap >= nearest:
			continue
		var half := wide * 0.5 + CORNER_CLEAR
		t = clampf(t, half, length - half) if length > half * 2.0 else length * 0.5
		nearest = gap
		out = {"at": a + along * t, "normal": e[2]}
	return out


## A banner: the neighbourhood's name in capitals, flat on its wall (sign_spot), lit, and outlined
## dark so it reads against a lit wall or a night sky. Named "Sign_<id>"; its text is the title.
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
	# Flat on its wall, read from the room's side only, and hidden by whatever stands between.
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.shaded = false
	label.double_sided = false
	label.no_depth_test = false
	label.fixed_size = false
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.set_meta(&"neighbourhood", id)
	return label
