class_name Stations
extends RefCounted

## Every instrument that stands somewhere, as one list (docs/spatial_loop.md part two, slice 10):
## the help card's PLAY pages, the desktop's go-to (I and Shift-I, a click on a PLAY line), the
## headset's station board (slice 11) and the suite's clearance loop are all made from it, so a
## later slice that appends its row cannot forget any of them.
##
## A row (`ALL`) is a station: `id`; `title`, as its plaque and the card letter it; `area`, the
## part of the world it is in (CONTROL, LIVE or VENUE, one PLAY page each); `zone`, the
## Venue.ZONES zone it is mounted in, or empty for one that stands on the floor by itself; `air`,
## the free radius it needs round where it is played (m); `spot`, the Venue method that places it
## (a Transform3D, or null where the venue has no room for it); `at`, the point in that frame a
## player looks at while playing it; and two lines of help, `desk` (mouse and keys) and `hands`
## (hands and buttons); and `frame`, what of it a player should see from where they stand, its
## top and its foot (two points in its frame, its controls' top first: the harp's crown with its
## 8va buttons, the bells' handles, the wheel board's top edge; then its plaque's bottom, under
## its keys, Stations.plaque_bottom). Every station's front is its frame's +Z: whoever plays it
## stands there, facing back along -Z.
##
## A free-standing row also says its footprint (`foot`, half its size on the floor, and `foot_z`,
## how far along Z its middle is) and how tall it stands (`top`), which is the walker solid the
## venue gives it, so the clearance loop and the venue cannot disagree about where it is.
##
## A row that is a surface rather than an instrument (the stage table, slice 18) says so
## (`surface`, its surface id), stands on a trolley rather than a venue solid (no `foot`), and
## may say its own `seat`, how far in front of it a player stands (m), where SEAT would leave its
## back edge out of reach.
##
## Things carried, not stood anywhere (the keytar, the shaker, the tambourine, the bells in a
## hand, the fingertips, the jacks), and what the hands do anywhere (clapping to mute, leaning in),
## are `HELD`: help lines only, on PLAY · HELD.

const CONTROL := &"control"
const LIVE := &"live"
const VENUE := &"venue"
const HELD_AREA := &"held"
## The areas in the order the card pages them.
const AREAS: Array[StringName] = [CONTROL, LIVE, VENUE]
const AREA_TITLES := {&"held": "HELD", &"control": "CONTROL ROOM", &"live": "LIVE ROOM", &"venue": "THIS VENUE"}
## How far in front of a station its seat is (m), and the nearest it comes in when something
## stands on the floor there: the far side of a table, a wall.
const SEAT := 1.1
const NEAREST := 0.45
## The plaque's lettering: 30 mm letters, readable at 1.5 m and well beyond (Lettering), and how
## wide its hands line runs before it wraps.
const PLAQUE_CAP := 0.03
const PLAQUE_WIDTH := 0.66
## The plaque's keys (INSTRUMENTS and BACK): each this tall, at most PLAQUE_KEY_WIDE, in a row
## this far under the lettering. 7 cm is what the seat audit's 7 px asks of a key the far side of
## the live room from the desk.
const PLAQUE_KEY := 0.07
const PLAQUE_KEY_WIDE := 0.24
const PLAQUE_KEYS_ROW := PLAQUE_KEY + 0.02

const ALL := [
	{
		"id": &"harp", "title": "CHORD HARP", "area": LIVE, "zone": &"", "air": 0.5,
		"spot": &"harp_spot", "at": Vector3(0, 1.05, 0),
		"frame": [Vector3(0, 1.73, 0), Vector3(0, 0.16, 0.26)],
		"foot": Vector2(0.35, 0.2), "foot_z": -0.06, "top": 1.73,
		"desk": "click a string to pluck · drag across to strum · wheel or 8va for the octave · wiggle over a ringing string to wobble · Alt + mouse up or down bends",
		"hands": "brush the strings with a fingertip, or pinch and sweep · 8va on the crown · tilt to bend · shake to wobble",
	},
	{
		"id": &"bells", "title": "HANDBELLS", "area": LIVE, "zone": &"", "air": 0.5,
		"spot": &"bell_stand_spot", "at": Vector3(0, 0.85, 0),
		"frame": [Vector3(0, 1.0, 0), Vector3(0, 0.41, 0.13)],
		"foot": Vector2(0.27, 0.12), "foot_z": 0.0, "top": 0.8,
		"desk": "click a bell to pick it up · swing the mouse or click to ring its chord tone",
		"hands": "pick a bell up and swing it · bells 1 to 4 ring the chord's root, third, fifth, top",
	},
	{
		"id": &"wheel", "title": "FIFTHS WHEEL", "area": LIVE, "zone": &"bricks", "air": 0.5,
		"spot": &"wheel_spot", "at": Vector3(0, 0.45, -0.2),
		"frame": [Vector3(0, 0.77, -0.35), Vector3(0, -0.29, 0.06)],
		"desk": "click a chord to hear it · drag round the hub or wheel for the key · SET writes it",
		"hands": "press a chord · twist the hub for the key · SET writes them into the song",
	},
	{
		"id": &"stage_table", "title": "STAGE TABLE", "area": CONTROL, "zone": &"", "air": 0.5,
		"spot": &"stage_table_spot", "at": Vector3(0, 0.74, 0.05),
		"frame": [Vector3(0, 0.80, -0.47), Vector3(0, 0.30, 0.585)],
		"seat": 0.95, "surface": &"stage_table",
		"desk": "drag a track's ball, or its tag's name: across is pan, back is quieter · wheel 0.5 dB, Shift 0.1 · its ring, or the wheel while held, is width · drag the stalk under it up for more of the room (ROOM makes one) · drag from the knot under a ball to another: a sidechain rope, pull its middle to duck harder, X cuts · double-click or Backspace resets · < > banks, SHOW · L held leans in",
		"hands": "take a track's ball, or its tag's name, and stand it where it should sound: across is pan, back is quieter · its ring is width, its stalk the room · pull a rope from the knot under it to another to duck that one, harder the more you pull, the X by the knot cuts it · press it twice to reset · lean in to hear it",
	},
	{
		"id": &"cassette_rack", "title": "CASSETTE RACK", "area": LIVE, "zone": &"", "air": 0.5,
		"spot": &"cassette_rack_spot", "at": Vector3(0, 1.15, 0),
		"frame": [Vector3(0, 1.5, 0), Vector3(0, 0.05, 0.1)],
		"foot": CassetteRack.FOOT, "foot_z": 0.0, "top": CassetteRack.TOP,
		"desk": "drag a clip off the timeline's edge: a cassette of it in your hand · carried, hold L to hear it, click a slot to shelve it, the BIN to bin it, a bandmate to hand it over · click a racked one to take it",
		"hands": "pull a clip out of the timeline toward you · hold it to your ear to hear it · let it go by a slot to shelve it, in the BIN to bin it · hold it by a bandmate's glove to hand it over",
	},
	{
		"id": &"sampler", "title": "SAMPLER", "area": LIVE, "zone": &"", "air": 0.5,
		"spot": &"sampler_spot", "at": Vector3(0, 1.0, 0),
		"frame": [Vector3(0, 1.33, 0), Vector3(0, 0.3, 0.13)],
		"foot": Sampler.FOOT, "foot_z": 0.0, "top": Sampler.TOP,
		"desk": "click REC, then squeeze, click or shake something you carry, or anything used within 1.5 m of its mic: one sample, a WAV and a cassette on the rack · click REC again to stop",
		"hands": "press REC, then squeeze, hit or shake something in your hand, or near the mic · that one sound is a cassette on the rack · press REC again to stop",
	},
]

const HELD := [
	{
		"id": &"keytar", "title": "KEYTAR", "area": HELD_AREA,
		"desk": "click it on the shelf to take it · A to ' play · Z X octave · arrows walk · wiggle the mouse to wobble · Alt + mouse up or down bends",
		"hands": "take it by the neck · play it from a MIDI keyboard or the computer's keys · tilt the neck hand to bend · shake to wobble",
	},
	{
		"id": &"shaker", "title": "SHAKER", "area": HELD_AREA,
		"desk": "click it on the shelf to pick it up · shake it with the mouse · click strikes · P jack · hits snap gently to the beat (session panel)",
		"hands": "close your hand round it and shake · each stroke that stops is a hit · a pinch carries it too · controllers are steadier for fast parts",
	},
	{
		"id": &"tambourine", "title": "TAMBOURINE", "area": HELD_AREA,
		"desk": "click it on the shelf to pick it up · shake it with the mouse · click strikes · P jack · hits snap gently to the beat (session panel)",
		"hands": "close your hand round the bare hoop and shake · the trigger strikes it · controllers are steadier for fast parts",
	},
	{
		"id": &"bells_held", "title": "A HANDBELL", "area": HELD_AREA,
		"desk": "carried: swing the mouse or click to ring · 1 to 3 pocket it · Q puts it down",
		"hands": "carried: swing it down to ring · its tab says the note it rings now",
	},
	{
		"id": &"fingertips", "title": "FINGERTIPS", "area": HELD_AREA,
		"desk": "T, then J K L ; play the chord's root, third, fifth and top · T or Esc gives them back · wiggle the mouse to wobble · Alt + mouse up or down bends",
		"hands": "hold an empty hand open, palm up, to turn them on · thumb to each fingertip plays · tilt to bend · shake to wobble",
	},
	{
		"id": &"clap", "title": "CLAP TO MUTE", "area": HELD_AREA,
		"desk": "K held over a track (a stage voice, a strip, a lane, a rack) mutes it while held · a tap latches it, another unlatches",
		"hands": "palms pressed together, pointing at a track, mute it until they part · a quick clap latches it · controllers: grips together",
	},
	{
		"id": &"lean", "title": "LEAN IN", "area": HELD_AREA,
		"desk": "L held over a stage voice: that track 6 dB up in your ears alone, the mix 6 dB down · a host on the built-in engine",
		"hands": "lean your head within 25 cm of a stage voice to hear it up close · a host on the built-in engine",
	},
	{
		"id": &"cassette", "title": "A CASSETTE", "area": HELD_AREA,
		"desk": "drag a clip off the timeline's edge for one · hold L to hear it · click a timeline lane, a strip or a stage voice to paste it · click a bandmate to hand it over · click a rack slot to shelve it · Q puts it down · 1 to 3 pocket it",
		"hands": "pull a clip out of the timeline toward you · hold it to your ear to hear it · push it into a timeline lane, a strip or a stage voice to paste it · hold it by a bandmate's glove for half a second to hand it over · throw it to them · let it go by a rack slot to shelve it",
	},
	{
		"id": &"jacks", "title": "JACKS", "area": HELD_AREA,
		"desk": "P steps what you carry into a track or a bandmate · Shift-P unplugs",
		"hands": "with the other hand, press the jack on what you carry · press again to step",
	},
]


## The row with this id, from ALL or HELD; empty if there is none.
static func row(id: StringName) -> Dictionary:
	for r: Dictionary in ALL + HELD:
		if r["id"] == id:
			return r
	return {}


## Where station `id` stands in `venue`, in the venue's frame, its front toward +Z; null where
## the venue has no room for it (the Rig Roulette room has no bricks table) or there is no venue.
static func spot(venue: Venue, id: StringName) -> Variant:
	var r := row(id)
	if venue == null or r.is_empty() or not r.has("spot") or not venue.has_method(r["spot"]):
		return null
	var at: Variant = venue.call(r["spot"])
	return at if at is Transform3D else null


## What a player at station `id` looks at, in the venue's frame; null where it does not stand.
static func look_point(venue: Venue, id: StringName) -> Variant:
	var at: Variant = spot(venue, id)
	if at == null:
		return null
	return (at as Transform3D) * (row(id)["at"] as Vector3)


## How far inside the edge of the view a station's frame is held (degrees): its foot just inside
## the bottom, its top further in from the top, clear of the HUD's line and the toast under it
## (about 6 degrees of a 58-degree lens), which says how to play what you have just walked to.
const FRAME_MARGIN := 3.0
const FRAME_TOP := 8.0


## Where a player whose eye is at `eye` (the venue's frame) looks to play station `id`, with a
## view `fov` degrees tall: toward its look point, tipped up or down only as far as it takes to
## hold its `frame`'s top and foot inside the view (FRAME_TOP and FRAME_MARGIN in from its edges). Where both do not fit (a seat the room has
## brought in close: the harp's, with the bricks table in front of it) the top wins, because that
## is where its controls are: the harp's chord readout and its 8va buttons are on its crown, and
## its plaque is for a headset, which reads it close up. The point is as far off, along the
## floor, as the look point. Null where the station does not stand.
static func look_from(venue: Venue, id: StringName, eye: Vector3, fov: float) -> Variant:
	var at: Variant = look_point(venue, id)
	if at == null:
		return null
	var look := at as Vector3
	var ahead := Vector3(look.x - eye.x, 0.0, look.z - eye.z)
	var along := ahead.length()
	if along < 0.001:
		return look
	ahead /= along
	var pitch := atan2(look.y - eye.y, along)
	var points: Array = row(id).get("frame", [])
	if points.size() == 2:
		var frame := spot(venue, id) as Transform3D
		var tip := func(p: Vector3) -> float:
			var q := frame * p
			return atan2(q.y - eye.y, maxf(0.05, (q - eye).dot(ahead)))
		var lowest: float = tip.call(points[0]) - deg_to_rad(fov * 0.5 - FRAME_TOP)
		var highest: float = tip.call(points[1]) + deg_to_rad(fov * 0.5 - FRAME_MARGIN)
		pitch = clampf(pitch, lowest, highest) if lowest <= highest else lowest
	return eye + ahead * along + Vector3.UP * along * tan(clampf(pitch, -1.4, 1.4))


## Where a player stands to play station `id`, in the venue's frame: on the floor SEAT in front
## of it (or its row's own `seat`), facing it (the transform's -Z toward its look point), and level. `fits` (a Vector2 on
## the floor -> bool, the walker's own) says where a person may stand; given, the seat comes in
## along the station's front toward NEAREST until it fits, then tries either side, and is the
## plain SEAT in front only when nothing fits. Null where the station does not stand.
static func seat(venue: Venue, id: StringName, fits := Callable()) -> Variant:
	var at: Variant = spot(venue, id)
	if at == null:
		return null
	var frame := at as Transform3D
	var look: Vector3 = look_point(venue, id)
	var far: float = row(id).get("seat", SEAT)
	var chosen := frame * Vector3(0, 0, far)
	if fits.is_valid():
		var found := false
		for side in [0.0, 0.15, -0.15, 0.3, -0.3, 0.45, -0.45]:
			var d := far
			while d >= NEAREST - 0.001 and not found:
				var p := frame * Vector3(side, 0, d)
				if fits.call(Vector2(p.x, p.z)):
					chosen = p
					found = true
				d -= 0.05
			if found:
				break
	chosen.y = 0.0
	var toward := Vector3(look.x - chosen.x, 0.0, look.z - chosen.z)
	if toward.length() < 0.001:
		toward = -frame.basis.z
	return Transform3D(Basis.looking_at(toward.normalized(), Vector3.UP), chosen)


## The ids of the stations that stand in `venue`, in list order.
static func ids(venue: Venue) -> Array[StringName]:
	var out: Array[StringName] = []
	for r: Dictionary in ALL:
		if spot(venue, r["id"]) != null:
			out.append(r["id"])
	return out


## {area: [row, ...]} of the stations that stand in `venue`, every area in AREAS present (an
## area with none has an empty list). With no venue, every row, as a card with no studio shows.
static func by_area(venue: Venue) -> Dictionary:
	var out := {}
	for area in AREAS:
		out[area] = []
	var here: Array[StringName] = ids(venue)
	for r: Dictionary in ALL:
		if venue != null and not here.has(r["id"]):
			continue
		(out[r["area"]] as Array).append(r)
	return out


## Whether station `id` is mounted in a zone (checked inside it) rather than free-standing.
static func zoned(id: StringName) -> bool:
	return row(id).get("zone", &"") != &""


## A free-standing station's walker solid at `venue`'s spot for it ({c, h, a, top}); empty for a
## zone-mounted one, which the zone's own solids carry, or one that does not stand there.
static func solid(venue: Venue, id: StringName) -> Dictionary:
	var r := row(id)
	var at: Variant = spot(venue, id)
	if at == null or not r.has("foot"):
		return {}
	var frame := at as Transform3D
	var middle := frame * Vector3(0, 0, r["foot_z"])
	return {"c": Vector2(middle.x, middle.z), "h": r["foot"], "a": frame.basis.get_euler().y, "top": r["top"]}


## A station's plaque: its title and its hands line, lettered at PLAQUE_CAP on a dark plate
## `width` wide, facing +Z (out of the station's front), for a headset player to read what it is
## and how hands play it; and under them its two keys (StationBoard.PlaqueKey, slice 11),
## INSTRUMENTS, the station board's rows beside the plaque, and BACK, home to the desk, so a
## player who has travelled here has the way on and the way back where they are looking. The
## lettering's middle is the node's origin; the keys' row hangs PLAQUE_KEYS_ROW below it. Named
## "Plaque", its keys "Instruments" and "Back".
static func plaque(id: StringName, width := PLAQUE_WIDTH) -> Node3D:
	var r := row(id)
	var holder := Node3D.new()
	holder.name = "Plaque"
	var lines := _plaque_lines(r.get("hands", ""), width - 0.04)
	var tall := PLAQUE_CAP * 1.6 + lines * PLAQUE_CAP * 1.45 + 0.03
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	var box := BoxMesh.new()
	box.size = Vector3(width, tall + PLAQUE_KEYS_ROW, 0.008)
	plate.mesh = box
	plate.position = Vector3(0, -PLAQUE_KEYS_ROW * 0.5, -0.004)
	var ink := StandardMaterial3D.new()
	ink.albedo_color = Color(0.07, 0.065, 0.06)
	ink.roughness = 0.6
	plate.material_override = ink
	holder.add_child(plate)
	var top := tall * 0.5 - 0.015
	var title := _plaque_label(r.get("title", String(id)), Color(0.95, 0.9, 0.78))
	title.name = "Title"
	title.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	title.position = Vector3(0, top, 0.001)
	holder.add_child(title)
	var hands := _plaque_label(r.get("hands", ""), Color(0.86, 0.84, 0.8))
	hands.name = "Hands"
	hands.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	hands.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hands.width = (width - 0.04) / hands.pixel_size
	hands.position = Vector3(0, top - PLAQUE_CAP * 1.6, 0.001)
	holder.add_child(hands)
	var wide := minf(PLAQUE_KEY_WIDE, (width - 0.06) * 0.5)
	for kind in [StationBoard.PlaqueKey.INSTRUMENTS, StationBoard.PlaqueKey.BACK]:
		var key := StationBoard.PlaqueKey.new()
		key.name = "Instruments" if kind == StationBoard.PlaqueKey.INSTRUMENTS else "Back"
		key.station = id
		key.kind = kind
		key.size = Vector2(wide, PLAQUE_KEY)
		var side := -1.0 if kind == StationBoard.PlaqueKey.INSTRUMENTS else 1.0
		key.position = Vector3(side * (wide * 0.5 + 0.01), -tall * 0.5 - PLAQUE_KEYS_ROW * 0.5 + 0.005, 0.0)
		holder.add_child(key)
	return holder


## How far below a plaque's origin its plate's bottom edge is, for `id`'s hands line at `width`:
## the foot of the station's `frame`, where the plaque is its lowest part.
static func plaque_bottom(id: StringName, width := PLAQUE_WIDTH) -> float:
	var lines := _plaque_lines(row(id).get("hands", ""), width - 0.04)
	return (PLAQUE_CAP * 1.6 + lines * PLAQUE_CAP * 1.45 + 0.03) * 0.5 + PLAQUE_KEYS_ROW


static func _plaque_label(text: String, colour: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = 0.00025
	l.font_size = roundi(PLAQUE_CAP / l.pixel_size)
	l.modulate = colour
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.double_sided = false
	Lettering.range_to_legibility(l)
	return l


## How many lines `text` takes at PLAQUE_CAP, wrapped to `width` metres, so the plate fits it.
static func _plaque_lines(text: String, width: float) -> int:
	var f: Font = Lettering.face()
	if f == null:
		f = ThemeDB.fallback_font
	var size := roundi(PLAQUE_CAP / 0.00025)
	var per := width / 0.00025
	var lines := 1
	var run := 0.0
	var space := f.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	for word in text.split(" ", false):
		var w := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if run > 0.0 and run + space + w > per:
			lines += 1
			run = w
		else:
			run += (space if run > 0.0 else 0.0) + w
	return lines
