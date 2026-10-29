class_name VenueInstrument
extends Node3D

## Every venue has something to play (docs/spatial_loop.md part two, slices 42 and 43, idea #19):
## the garden's wind chimes, the cabin's icicles, the cave's crystals, the rooftop's railing, the
## studio's tubular bells, the grid's neon bars, the chalk zone's chalk-drawn xylophone (slice 42);
## the loft's steam pipes, the station's ring of hull panels, the dome's singing glass, the club's
## upright piano, the greenhouse's terracotta pots, the stage's tuned cymbals and gong and the
## desert's ringing stones (slice 43). Tuned to the song's key, struck by a hand, a controller or a
## click, and recordable to a track.
##
## A set is up to MOST bars, each a fixed pitched InstrumentItem of the room (`Bar`, the fixed kinds
## `venue1`..`venue8` in ItemRoom.KINDS), standing where the set's own mount holds it. This node is
## the mount: what the bars hang from, stand on or lie in, with a lamp over a hanging set
## (`_build_mount`), the station's plaque (Stations.plaque, the station `venue`) and the set's one
## jack (`SOURCE`, a JackSocket on no instrument), all in the venue's frame at its spot
## (Venue.instrument_spot), so it goes with the venue. The studio stands it (Studio.venue_instrument)
## and dresses the bars for it (`dress`): a venue with no instrument (the Rig Roulette room) puts
## every bar away (ItemRoom.stand).
##
## What a set is, the venue says (Venue.instrument): its `kind` (KINDS: its look, its sound, how its
## bars stand and its help lines), its `count`, its `spot` and its `low` note. Bar n rings the n-th
## tone of the song's scale (Harmony.at's `scale`) up from the key's root nearest `low`
## (`note_at`), so the set is in the song's key wherever the song is, and retunes at a bracket: in A
## minor the chimes ring A B C D E F G A, after a `[D minor]` D E F G A Bb C D. Each bar letters the
## note it rings now, which changes with the key, so which bar is which is read, not told by
## colour. The piano's keys are the scale's notes, and between two a whole tone apart the black key
## for the note out of the key is sunk, level with them, and plays nothing (`_repattern`).
##
## Struck, a bar plays as every fixed instrument does (InstrumentItem.play): at once on the fast
## path for the striker (slice 39), pitched from its kind's sound (Foley.venue_bar) to its note; to
## the room as an item hit with its song position, so a bandmate hears it from where it hangs,
## pitched by that same position; and into the take on InstrumentItem.MELODIC_CHANNEL, where the
## built-in engine plays it back as its pitched voice (ItemVoices). The set is one jack source,
## `venue`, however many bars it has (Bar.jack_source, Jacks.hit): plugged into a track, every bar
## of the set is recorded onto it; into a bandmate, each bar's note goes down the cable.
##
## A hand strikes a bar by crossing one of its faces inward (Strike): a hanging or standing bar's
## four sides, so a brush across a row of them rings each in turn, as a hand through wind chimes
## does; a lying bar's top, as a xylophone's; a gong's face. The dome's glass rings at a touch
## (`touch`: Bar.strike_least), softly. At a desk a click strikes a bar (Shift softly), and holding
## the button down and dragging across the others brushes them (`brush`).

## The set's one jack: what it plugs into a track or a bandmate (Jacks, Jack).
const SOURCE := &"venue"
## Its station (Stations.ALL).
const STATION := &"venue"
## The most bars a set has: the room's fixed kinds venue1 to venue8.
const MOST := 8
## How the bars stand: hung from a rail, standing on a ledge or a kerb, or lying across a frame.
const HANG := &"hang"
const STAND := &"stand"
const LIE := &"lie"
## How long a strike is as a note in a take (s): a bell's, as a struck bar rings.
const RING_SECONDS := 0.8
## How often a bar's lettering is looked at again (s): a key change shows within this.
const RELETTER := 0.1
## The note letters on each bar: their height, and how far off the bar they stand.
const LETTER_CAP := 0.022
const LETTER_OUT := 0.006
## How far in front of the set's front (its bars', or its mount's where that stands further out:
## the crystals' shelf) the plaque stands, and how far the jack is from the plaque's right edge.
const PLAQUE_OUT := 0.06
const PLAQUE_WIDTH := 0.6
const JACK_SIDE := 0.06
## The can over a hanging set: its light, warm, and how bright (a kind's `lamp`: none, 0, for the
## icicles, which the moonlit window behind them lights, and on which even a faint lamp blooms clear
## ice white); how wide its cone (degrees), and how far out in front of the rail it stands on its
## arm (m), aimed back at the bars' middle, so it lights their length rather than blowing out their
## tops. Its highlight is let in a little, since
## that is what shows a tube is metal, but not so much it blooms.
const LAMP_COLOUR := Color(1.0, 0.92, 0.8)
const LAMP_ENERGY := 0.5
const LAMP_CONE := 52.0
const LAMP_OUT := 0.3
const LAMP_SPECULAR := 0.12
## How the lamp's light falls off with distance (SpotLight3D.spot_attenuation): flatter than a
## zone's, so the bars' tops, nearest it, are not much brighter than their middles.
const LAMP_FALLOFF := 0.35
## The glow among a glowing standing set's feet (the crystals'): their own colour, faint, so the
## shelf they grow out of is lit by them and not a black block under them.
const GLOW_ENERGY := 0.5
const GLOW_REACH := 1.1
## The mounts modelled in Blender (tools/blender/venue_mounts.py): the cave's rock shelf, the tubular
## bells' frame, the icicles' eave. The shelf's front, its lip, is no further out than SHELF_FRONT
## from the bars' line, and it is SHELF_WIDE across as modelled.
const MOUNTS := "res://assets/models/venue_mounts.glb"
const SHELF_FRONT := 0.15
const SHELF_WIDE := 1.0
## Slice 43's mounts, modelled in the same file: the steam pipes' header (PipeHeader, its pipe's axis
## PIPE_HEADER over where the pipes hang from, a valve on its left end, PipeValve, and a tee over each
## pipe, PipeTee), the pots' bench (PotBench, its top at 0.8 m), the cymbals' and gong's rack
## (GongRack: its top bar at GONG_BAR, the gong's cords tied to it, its lower rail's top at GONG_RAIL
## under the cymbals' pins) and the stones' sandstone ledge (StoneShelf, its two ridges' tops at
## STONE_RIDGE).
const PIPE_HEADER := 0.05
const GONG_BAR := 1.9
const GONG_RAIL := 0.975
const STONE_RIDGE := 0.78
## How many pieces a hull rib is bent in (_arc_band).
const ARC_PIECES := 8
## The bells' frame as modelled: its top rail RAIL_LONG long, the fittings at its ends where the posts
## come up into it this far either side of its middle.
const RAIL_LONG := 1.0
const RAIL_FITTING := 0.4725
## A headset's seat at a set: this far in front of its front (m), so every bar is in a hand's reach
## from where it stands (the set is played only by hand). A desk's stands back further (`seat_for`).
const REACH := 0.45
## A desk's seat at a set is the nearest, from Stations.SEAT out to SEAT_FURTHEST, from which its
## frame fits a standing player's view with this much to spare (degrees).
const SEAT_FURTHEST := 2.2
const SEAT_SPARE := 2.0
## The club's piano's white keys, one to the next (m): club.glb's keyboard, 52 keys across 1.36 m,
## which leaves the octave the set's keys are out of its own (tools/blender/club.py's GAP).
const PIANO_KEY := 1.36 / 52.0
## The piano's sunk black keys: how wide, one key's share; how long, from the tails of the keys
## (m); and how far proud of the white keys' tops their own tops stand, sunk (m), where a raised one
## stands 23 mm proud.
const SUNK_WIDE := 0.55
const SUNK_LONG := 0.09
const SUNK_PROUD := 0.002
## How slowly a hand may cross a glass that rings at a touch (`touch`) and still ring it (m/s), and
## how loud a touch slower than a strike (InstrumentItem.STROKE_MIN) rings: from the first to the
## second of these as it comes up to one.
const TOUCH_LEAST := 0.08
const TOUCH_SOFT := 18
const TOUCH_FIRM := 40

## Each kind of set: what it is called (`title`, and `one` for one of its bars), the sound each bar
## rings (Foley.VENUE_BAR_SOUNDS), how its bars stand (`shape`: HANG from a rail at `at`, STAND from
## `at` up, or LIE across at `at`, along the set's Z), how thick (`radius`, or for a lying one its
## half width and `thick`), how long its longest and its shortest are (the first bar the longest
## and lowest, the last the shortest), how far apart (`pitch`), its look (`colour`, `metal`, `rough`,
## `glow` for one that gives light), and how it is played, at a desk and with hands. A mount that
## stands out in front of the bars says how far (`front`: the crystals' shelf), so the plaque and the
## jack stand clear in front of it, and a plaque that stands lower than its kind's place says where
## (`plaque_y`). Slice 43's sets add: a flat bar (`plate`, its thickness: the hull's panels, the
## glass), bars set round an arc of a ring (`arc`, its radius, so the row curves round whoever plays
## it), bars that grow with their length (`grow`) set each its own width apart (`gap`: the pots),
## round bars (`disc`, their length a diameter: the cymbals), a gong hung behind the rest as the
## first bar (`gong`), a glass that rings at a touch (`touch`), a top struck as well as the sides
## (`top`), the piano's keys (`keys`), a letter smaller than LETTER_CAP (`letter_cap`) and letters
## that say the note without its octave (`octave` false: the piano's, a key too narrow for both at a
## size read from the desk; its hover readout and plaque still say the octave).
const KINDS := {
	&"chimes": {
		"title": "WIND CHIMES", "one": "CHIME", "sound": &"chime", "shape": HANG, "at": 1.85,
		"radius": 0.013, "long": 0.55, "short": 0.28, "pitch": 0.085,
		"colour": Color(0.78, 0.8, 0.84), "metal": 0.9, "rough": 0.22, "low": 79,
		"desk": "click a tube to strike it, Shift-click softly · hold the button and drag across the tubes to brush them · each tube a note of the song's scale, the first its key",
		"hands": "strike a tube with a fingertip or a controller · brush a hand across them to ring several · the first tube is the key's own note",
	},
	&"icicles": {
		"title": "ICICLES", "one": "ICICLE", "sound": &"icicle", "shape": HANG, "at": 1.85,
		"radius": 0.017, "long": 0.46, "short": 0.2, "pitch": 0.1, "taper": true, "lamp": 0.0,
		"colour": Color(0.78, 0.9, 0.98, 0.72), "metal": 0.0, "rough": 0.05, "low": 84,
		"desk": "click an icicle to tap it, Shift-click softly · hold the button and drag along them to run up or down · each one a note of the song's scale, the longest its key",
		"hands": "tap an icicle with a fingertip or a controller · run a hand along them to ring several · the longest is the key's own note",
	},
	&"crystals": {
		"title": "CRYSTALS", "one": "CRYSTAL", "sound": &"crystal", "shape": STAND, "at": 0.82,
		"radius": 0.03, "long": 0.42, "short": 0.18, "pitch": 0.1, "facets": true,
		"front": SHELF_FRONT, "plaque_y": 0.56,
		"colour": Color(0.62, 0.42, 0.95, 0.85), "metal": 0.0, "rough": 0.08, "glow": 0.6, "low": 79,
		"desk": "click a crystal to strike it, Shift-click softly · hold the button and drag across them to ring several · each one a note of the song's scale, the tallest its key",
		"hands": "strike a crystal's side with a fingertip or a controller · sweep a hand across them to ring several · the tallest is the key's own note",
	},
	&"railing": {
		"title": "THE RAILING", "one": "BALUSTER", "sound": &"baluster", "shape": STAND, "at": 0.27,
		"radius": 0.011, "long": 0.8, "short": 0.8, "pitch": 0.11, "plaque_y": 0.48, "letter_y": 0.09,
		"colour": Color(0.12, 0.12, 0.13), "metal": 0.75, "rough": 0.35, "collar": Color(0.78, 0.62, 0.3), "low": 72,
		"desk": "click a baluster to strike it, Shift-click softly · hold the button and drag along the railing to run it · the brass-collared ones, each a note of the song's scale, the left its key",
		"hands": "strike a baluster with a fingertip or a controller · run a hand along the railing to ring several · the left one is the key's own note",
	},
	&"tubular_bells": {
		"title": "TUBULAR BELLS", "one": "TUBULAR BELL", "sound": &"tubular", "shape": HANG, "at": 1.8,
		"radius": 0.019, "long": 0.95, "short": 0.62, "pitch": 0.1, "caps": true,
		"colour": Color(0.86, 0.84, 0.78), "metal": 0.8, "rough": 0.34, "low": 72,
		"desk": "click a bell to strike it, Shift-click softly · hold the button and drag across them to ring several · each one a note of the song's scale, the longest its key",
		"hands": "strike a bell on its cap or its side with a fingertip or a controller · sweep across them to ring several · the longest is the key's own note",
	},
	&"neon": {
		"title": "NEON BARS", "one": "NEON BAR", "sound": &"neon", "shape": LIE, "at": 0.9,
		"radius": 0.024, "thick": 0.03, "long": 0.42, "short": 0.26, "pitch": 0.072,
		"colour": Color(0.2, 0.95, 1.0), "metal": 0.0, "rough": 0.3, "glow": 2.2, "low": 72,
		"desk": "click a bar to strike it, Shift-click softly · hold the button and drag across them to run up or down · each bar a note of the song's scale, the left and longest its key",
		"hands": "strike a bar from above with a fingertip or a controller, as a vibraphone's · sweep across them for a run · the left and longest is the key's own note",
	},
	&"chalk": {
		"title": "CHALK XYLOPHONE", "one": "CHALK BAR", "sound": &"xylophone", "shape": LIE, "at": 0.9,
		"radius": 0.024, "thick": 0.025, "long": 0.4, "short": 0.24, "pitch": 0.072, "drawn": true,
		"colour": Color(0.92, 0.94, 1.0, 0.18), "metal": 0.0, "rough": 0.9, "glow": 0.4, "low": 72,
		"desk": "click a bar to strike it, Shift-click softly · hold the button and drag across them to run up or down · each bar a note of the song's scale, the left and longest its key",
		"hands": "strike a bar from above with a fingertip or a controller, as a xylophone's · sweep across them for a run · the left and longest is the key's own note",
	},
	# Slice 43's seven.
	&"pipes": {
		"title": "STEAM PIPES", "one": "PIPE", "sound": &"pipe", "shape": HANG, "at": 1.9,
		"radius": 0.024, "long": 0.82, "short": 0.44, "pitch": 0.1, "pipe": true,
		"colour": Color(0.17, 0.2, 0.18), "metal": 0.7, "rough": 0.5, "low": 60,
		"desk": "click a pipe to strike it, Shift-click softly · hold the button and drag across them to ring several · each pipe a note of the song's scale, the longest its key",
		"hands": "strike a pipe with a fingertip or a controller · sweep a hand across them to ring several · the longest is the key's own note",
	},
	&"hull_panels": {
		"title": "HULL PANELS", "one": "PANEL", "sound": &"panel", "shape": STAND, "at": 0.62,
		"radius": 0.046, "plate": 0.014, "long": 0.74, "short": 0.44, "pitch": 0.112, "arc": 0.9,
		"colour": Color(0.66, 0.7, 0.74), "metal": 0.75, "rough": 0.3, "edge": Color(0.35, 0.85, 1.0), "low": 72,
		"desk": "click a panel to strike it, Shift-click softly · hold the button and drag across them to ring several · each panel a note of the song's scale, the left and tallest its key",
		"hands": "strike a panel's face with a fingertip or a controller · sweep a hand round the ring to ring several · the left and tallest is the key's own note",
	},
	&"glass": {
		"title": "SINGING GLASS", "one": "PANE", "sound": &"glass", "shape": STAND, "at": 0.56,
		"radius": 0.05, "plate": 0.012, "long": 0.9, "short": 0.52, "pitch": 0.124, "touch": true, "front": 0.08,
		"colour": Color(0.7, 0.9, 1.0, 0.2), "metal": 0.3, "rough": 0.03, "glow": 0.05, "low": 84,
		"desk": "click a pane to ring it, Shift-click softly · hold the button and drag across them to ring several · each pane a note of the song's scale, the tallest its key",
		"hands": "touch a pane, even gently, with a fingertip or a controller: a touch rings the glass · sweep across them to ring several · the tallest is the key's own note",
	},
	&"piano": {
		"title": "THE PIANO", "one": "KEY", "sound": &"piano", "shape": LIE, "at": 0.7,
		"radius": 0.0121, "thick": 0.022, "long": 0.15, "short": 0.15, "pitch": PIANO_KEY, "keys": true,
		"front": 0.12, "letter_cap": 0.015, "octave": false,
		"colour": Color(0.95, 0.92, 0.84), "metal": 0.0, "rough": 0.35, "low": 60,
		"desk": "click a lettered key to play it, Shift-click softly · hold the button and drag along the octave to run it · its keys the song's scale, the left its key; the black keys out of the key are sunk",
		"hands": "press a lettered key with a fingertip or a controller · run along the octave to play a scale · the left key is the key's own note; the sunk black keys play nothing",
	},
	&"pots": {
		"title": "TERRACOTTA POTS", "one": "POT", "sound": &"terracotta", "shape": STAND, "at": 0.8,
		"radius": 0.07, "long": 0.16, "short": 0.09, "gap": 0.016, "grow": true, "pot": true, "top": true,
		"front": 0.14, "letter_y": 0.04,
		"colour": Color(0.74, 0.39, 0.23), "metal": 0.0, "rough": 0.88, "low": 72,
		"desk": "click a pot to tap it, Shift-click softly · hold the button and drag across them to ring several · each pot a note of the song's scale, the biggest its key",
		"hands": "tap a pot on its base or its side with a fingertip or a controller · sweep across them to ring several · the biggest is the key's own note",
	},
	&"cymbals": {
		"title": "CYMBALS AND GONG", "one": "CYMBAL", "sound": &"crotale", "shape": LIE, "at": 1.0,
		"thick": 0.004, "long": 0.17, "short": 0.11, "pitch": 0.18, "disc": true,
		"gong": {"size": 0.46, "at": 1.84, "z": -0.18, "thick": 0.014, "sound": &"gong", "one": "GONG"},
		"colour": Color(0.86, 0.68, 0.32), "metal": 0.9, "rough": 0.24, "low": 74,
		"desk": "click a cymbal or the gong to strike it, Shift-click softly · hold the button and drag across the cymbals to run them · the gong is the key's own note, the cymbals the scale up from it",
		"hands": "strike a cymbal from above, or the gong's face, with a fingertip or a controller · sweep across the cymbals for a run · the gong is the key's own note",
	},
	&"stones": {
		"title": "RINGING STONES", "one": "STONE", "sound": &"stone", "shape": LIE, "at": 0.78,
		"radius": 0.042, "thick": 0.04, "long": 0.46, "short": 0.28, "pitch": 0.1, "stone": true,
		"colour": Color(0.52, 0.48, 0.44), "metal": 0.0, "rough": 0.9, "low": 72,
		"desk": "click a stone to strike it, Shift-click softly · hold the button and drag across them to run up or down · each stone a note of the song's scale, the left and longest its key",
		"hands": "strike a stone from above with a fingertip or a controller · sweep across them for a run · the left and longest is the key's own note",
	},
}

## The set this mount holds, as `spec_of` gives it.
var spec: Dictionary = {}
## Its bars, as the studio dressed them (`dress`): what a drag across them brushes.
var bars: Array = []
## The set's jack, on the mount beside the plaque.
var jack: JackSocket = null
## Its socket on the modular's patch (slice 53, `world:venue`), beside the jack: a gate a strike and
## its velocity, patched into the modular wall from here (ModularWorld).
var modular: WorldSocket = null
## Each mouse over the set, {Interactor: [its button down, brushing, the bar it is on]}: the bar
## its button went down on or last came onto, so a drag across the others strikes each as it is
## reached, and the one it is still on is not struck again.
var _brushing := {}
## The piano's sunk black keys by slot (`_build_sunk_keys`), the slots that have one now (`pattern`),
## and when they are looked at again.
var _sunk: Array[MeshInstance3D] = []
var _pattern: Array = []
var _repattern_in := 0.0


func _init(set_spec: Dictionary = {}) -> void:
	spec = set_spec
	name = "VenueInstrument"


func _ready() -> void:
	if spec.is_empty():
		return
	_build_mount()
	var plaque := Stations.plaque(STATION, PLAQUE_WIDTH)
	plaque.transform = plaque_frame(spec)
	add_child(plaque)
	jack = JackSocket.new(null, SOURCE)
	jack.label = str(spec["title"])
	# Facing out of the mount's front, toward whoever stands at the set, beside the plaque.
	jack.transform = Transform3D(Basis(Vector3.UP, PI), jack_point(spec))
	add_child(jack)
	modular = WorldSocket.new(&"world:venue")
	modular.position = jack_point(spec) + Vector3(WorldSocket.BESIDE, 0, 0)
	add_child(modular)


# --- what a set is ----------------------------------------------------------------------------

## The set `venue` has (Venue.instrument), filled out from its kind (KINDS): `kind`, `title`, `count`
## (1 to MOST), `low`, `spot` and the kind's own fields. Empty where there is none, or no venue.
static func spec_of(venue: Venue) -> Dictionary:
	if venue == null:
		return {}
	return filled(venue.instrument())


## `given` (a venue's `instrument()`) filled out from its kind: empty for none, or a kind not known.
static func filled(given: Dictionary) -> Dictionary:
	if given.is_empty() or not KINDS.has(given.get("kind", &"")) or not (given.get("spot") is Transform3D):
		return {}
	var out: Dictionary = (KINDS[given["kind"]] as Dictionary).duplicate()
	out.merge(given, true)
	out["count"] = clampi(int(out.get("count", MOST)), 1, MOST)
	return out


## The room's id for bar `n` (0-based): `venue1` for the first.
static func bar_id(n: int) -> StringName:
	return StringName("venue%d" % (n + 1))


## Whether `id` is one of the room's venue bars.
static func is_bar(id: StringName) -> bool:
	var s := String(id)
	return s.begins_with("venue") and s.length() > 5 and s.substr(5).is_valid_int() \
			and int(s.substr(5)) >= 1 and int(s.substr(5)) <= MOST


## Bar `n`'s length (m): the first the longest, the last the shortest, evenly between. A set with a
## gong (`gong`) has it first, its size its own, and the rest evenly after it.
static func bar_length(set_spec: Dictionary, n: int) -> float:
	var count := int(set_spec.get("count", MOST))
	var first := 0
	if set_spec.has("gong"):
		if n == 0:
			return float(set_spec["gong"]["size"])
		first = 1
	var along := float(n - first) / float(maxi(count - 1 - first, 1))
	return lerpf(float(set_spec["long"]), float(set_spec["short"]), along)


## How bar `n` stands: its set's `shape`, but a gong (`gong`, the first bar) hangs behind the rest.
static func bar_shape(set_spec: Dictionary, n: int) -> StringName:
	if n == 0 and set_spec.has("gong"):
		return HANG
	return set_spec["shape"]


## Bar `n`'s half width across the row (m): its set's `radius`, a share of it by its length where the
## bars grow (`grow`: the pots), or half its length for a round one (`disc`: a cymbal, the gong).
static func bar_radius(set_spec: Dictionary, n: int) -> float:
	if set_spec.get("disc", false):
		return bar_length(set_spec, n) * 0.5
	var r := float(set_spec["radius"])
	if set_spec.get("grow", false):
		r *= bar_length(set_spec, n) / float(set_spec["long"])
	return r


## How far bar `n` stands out of its line front and back (m): a lying bar's half length (a cymbal's
## radius), a hanging gong's or a flat bar's (`plate`) half its thickness, a round bar's radius.
static func bar_depth(set_spec: Dictionary, n: int) -> float:
	if bar_shape(set_spec, n) == LIE:
		return bar_length(set_spec, n) * 0.5
	if set_spec.get("disc", false):
		return float(set_spec["gong"].get("thick", 0.02)) * 0.5
	if set_spec.has("plate"):
		return float(set_spec["plate"]) * 0.5
	return bar_radius(set_spec, n)


## Where along the row bar `n`'s middle is (m, the set's X, the first on the player's left): `pitch`
## apart, or each its own width apart with `gap` between (`gap`: the pots); a gong in the middle,
## behind the rest.
static func bar_x(set_spec: Dictionary, n: int) -> float:
	var count := int(set_spec.get("count", MOST))
	if set_spec.has("gong"):
		if n == 0:
			return 0.0
		return (float(n - 1) - float(count - 2) * 0.5) * float(set_spec["pitch"])
	if set_spec.has("gap"):
		var gap := float(set_spec["gap"])
		var total := gap * float(count - 1)
		var before := 0.0
		for k in count:
			total += bar_radius(set_spec, k) * 2.0
			if k < n:
				before += bar_radius(set_spec, k) * 2.0 + gap
		return -total * 0.5 + before + bar_radius(set_spec, n)
	return (float(n) - float(count - 1) * 0.5) * float(set_spec["pitch"])


## Where bar `n` stands in the set's frame (+Z its front, toward the player; the first bar on the
## player's left): its origin the bar's foot on its axis (a hanging bar's lower end, a standing one's
## foot, a lying one's middle underneath), its +Y up. A lying bar's length is along the frame's Z.
## Round an arc (`arc`), the row's ends come forward and each bar faces the ring's middle.
static func bar_frame(set_spec: Dictionary, n: int) -> Transform3D:
	var x := bar_x(set_spec, n)
	var y: float = set_spec["at"]
	var z := 0.0
	if n == 0 and set_spec.has("gong"):
		y = float(set_spec["gong"]["at"])
		z = float(set_spec["gong"]["z"])
	if bar_shape(set_spec, n) == HANG:
		y -= bar_length(set_spec, n)
	if set_spec.has("arc"):
		var r := float(set_spec["arc"])
		var a := x / r
		return Transform3D(Basis(Vector3.UP, -a), Vector3(r * sin(a), y, z + r * (1.0 - cos(a))))
	return Transform3D(Basis.IDENTITY, Vector3(x, y, z))


## How far the row runs either side of its middle, to its outermost bar's outer edge (m).
static func half_width(set_spec: Dictionary) -> float:
	var out := 0.0
	for n in int(set_spec.get("count", MOST)):
		var f := bar_frame(set_spec, n)
		var turn := absf(f.basis.get_euler().y)
		out = maxf(out, absf(f.origin.x) + bar_radius(set_spec, n) * cos(turn) + bar_depth(set_spec, n) * sin(turn))
	return out


## How far the bars stand out of their line toward the player (`ahead`) or behind it (m).
static func _reach_of(set_spec: Dictionary, ahead: bool) -> float:
	var out := 0.0
	for n in int(set_spec.get("count", MOST)):
		var f := bar_frame(set_spec, n)
		var turn := absf(f.basis.get_euler().y)
		var z := f.origin.z if ahead else -f.origin.z
		out = maxf(out, z + bar_radius(set_spec, n) * sin(turn) + bar_depth(set_spec, n) * cos(turn))
	return out


## How far the set stands out from its line, front and back, whichever is further (m): a vertical
## bar's radius, a lying one's half length, the ends of an arc, a gong behind.
static func half_depth(set_spec: Dictionary) -> float:
	return maxf(_reach_of(set_spec, true), _reach_of(set_spec, false))


## How far the set's front is from its line (m): its bars', or its mount's where that stands further
## out (`front`: the crystals' shelf's lip, the pots' bench, the piano's keybed). What the plaque,
## the jack and a seat stand in front of.
static func front_of(set_spec: Dictionary) -> float:
	return maxf(_reach_of(set_spec, true), float(set_spec.get("front", 0.0)))


## How far behind its line the set's bars reach (m): a gong hung behind the cymbals.
static func back_of(set_spec: Dictionary) -> float:
	return _reach_of(set_spec, false)


## Its top and its foot over what it stands on (m): the rail's, the tallest bar's top, or a lying
## set's top; and the lowest a bar comes down to, or a lying set's frame.
static func top_of(set_spec: Dictionary) -> float:
	var out := -INF
	for n in int(set_spec.get("count", MOST)):
		var y := bar_frame(set_spec, n).origin.y
		match bar_shape(set_spec, n):
			HANG:
				out = maxf(out, y + bar_length(set_spec, n) + 0.05)
			STAND:
				out = maxf(out, y + bar_length(set_spec, n))
			_:
				out = maxf(out, y + float(set_spec.get("thick", 0.03)))
	return out


static func bottom_of(set_spec: Dictionary) -> float:
	var out := INF
	for n in int(set_spec.get("count", MOST)):
		out = minf(out, bar_frame(set_spec, n).origin.y)
	return out


## Where the plaque stands in the set's frame: under a hanging set, in front of a standing one's
## foot (or where its kind says, `plaque_y`: low on the railing, under where it is struck, and on
## the crystals' shelf's face, under its lip), in front of a lying one's near edge, and always in
## front of the set's front (`front_of`: clear of a shelf's lip), leant back a little, so it reads
## from the seat.
static func plaque_frame(set_spec: Dictionary) -> Transform3D:
	var y := bottom_of(set_spec) - 0.12
	var z := front_of(set_spec) + PLAQUE_OUT
	if set_spec.has("plaque_y"):
		y = float(set_spec["plaque_y"])
	elif set_spec["shape"] == STAND:
		y = maxf(float(set_spec["at"]) - 0.1, 0.12)
	elif set_spec["shape"] == LIE:
		y = float(set_spec["at"]) - 0.1
	return Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(0, y, z))


## Where the set's jack is in its frame: off the plaque's right end, at its height.
static func jack_point(set_spec: Dictionary) -> Vector3:
	var at := plaque_frame(set_spec).origin
	return Vector3(PLAQUE_WIDTH * 0.5 + JACK_SIDE, at.y, at.z)


## What the set's station row says in this venue (Stations.row_in): its title, its help lines, where
## a player looks (`at`, the row's middle), what of it they should see (`frame`: its top, then its
## plaque's foot), where a desk stands to see all that (`seat`, `seat_for`) and where a headset
## stands to play it (`reach`: REACH in front of it, every bar in a hand's reach).
static func row_for(set_spec: Dictionary) -> Dictionary:
	if set_spec.is_empty():
		return {}
	var top := top_of(set_spec)
	return {"title": set_spec["title"], "desk": set_spec["desk"], "hands": set_spec["hands"],
			"at": Vector3(0, (top + bottom_of(set_spec)) * 0.5, 0), "frame": frame_of(set_spec),
			"seat": seat_for(set_spec), "reach": front_of(set_spec) + REACH}


## What of the set a player should see, in its frame: its top over its line, and its plaque's foot.
static func frame_of(set_spec: Dictionary) -> Array:
	var plaque := plaque_frame(set_spec).origin
	return [Vector3(0, top_of(set_spec), 0), Vector3(0, plaque.y - 0.12, plaque.z)]


## How far in front of the set a desk's seat stands (m): the nearest, from Stations.SEAT out to
## SEAT_FURTHEST, from which a standing player's view at the room's lens (Studio.ROOM_FOV, at the
## default eye height) holds its frame's top and foot inside the margins Stations.look_from keeps,
## with SEAT_SPARE to spare. A low set is seen from Stations.SEAT; the studio's tubular bells, their
## rail at 1.85 m and their plaque's foot at 0.6 m, want more.
static func seat_for(set_spec: Dictionary) -> float:
	var frame := frame_of(set_spec)
	var top: Vector3 = frame[0]
	var foot: Vector3 = frame[1]
	var eye := Ergonomics.DEFAULT_HEIGHT - Ergonomics.EYE_BELOW_CROWN
	var room := deg_to_rad(Studio.ROOM_FOV - Stations.FRAME_TOP - Stations.FRAME_MARGIN - SEAT_SPARE)
	var d := Stations.SEAT
	while d < SEAT_FURTHEST:
		if atan2(top.y - eye, d - top.z) - atan2(foot.y - eye, d - foot.z) <= room:
			break
		d += 0.05
	return d


## The set's walker solid in the venue's frame ({c, h, a, top}): the row's footprint out to its front
## (`front_of`: a shelf's lip) and as far behind (or to a gong behind, `back_of`), so a person walks
## up to it rather than through it. The piano's keys reach back only to their own tails: the case
## behind them is the club's own solid.
static func solid(set_spec: Dictionary) -> Dictionary:
	var at: Transform3D = set_spec["spot"]
	var front := front_of(set_spec)
	var back := back_of(set_spec) if set_spec.get("keys", false) else maxf(back_of(set_spec), front)
	var middle := at * Vector3(0, 0, (front - back) * 0.5)
	return {"c": Vector2(middle.x, middle.z), "h": Vector2(half_width(set_spec), (front + back) * 0.5 + 0.02),
			"a": at.basis.get_euler().y, "top": top_of(set_spec)}


## The room's bars dressed as `set_spec`'s (`Bar.dress`), the first `count`; the rest left as they
## are, for the studio to put away (its homes give them none). Answers the dressed bars.
static func dress(room: ItemRoom, set_spec: Dictionary) -> Array:
	var out: Array = []
	if room == null or set_spec.is_empty():
		return out
	for n in int(set_spec["count"]):
		var bar := room.items.get(bar_id(n)) as Bar
		if bar != null:
			bar.dress(set_spec)
			out.append(bar)
	return out


## The bars' homes in the venue's frame, {id: Transform3D}, for the first `count` (the studio's
## `_item_homes`): the set's spot times each bar's frame.
static func homes(set_spec: Dictionary) -> Dictionary:
	var out := {}
	if set_spec.is_empty():
		return out
	for n in int(set_spec["count"]):
		out[bar_id(n)] = (set_spec["spot"] as Transform3D) * bar_frame(set_spec, n)
	return out


## The tonic of `h` the set's first bar rings: the key's root nearest `low`, a fifth below it to a
## fourth above (as Harmony.voiced places a chord's root round its centre).
static func tonic(h: Harmony, low: int) -> int:
	var lowest := low - 6
	return lowest + posmod(h.root - lowest, 12)


## Bar `n`'s note in harmony `h`, the set's tonic near `low`: the n-th tone up the key's scale (its
## pitch classes, root first), each above the one before.
static func scale_tone(h: Harmony, low: int, n: int) -> int:
	var steps := h.scale.size()
	if steps == 0:
		return low
	return tonic(h, low) + posmod(h.scale[n % steps] - h.root, 12) + 12 * (n / steps)


# --- a mouse brushing across ------------------------------------------------------------------

func _process(delta: float) -> void:
	if bars.is_empty() or not is_inside_tree():
		return
	var held := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	for node in get_tree().get_nodes_in_group(Interactor.GROUP):
		if node is MouseInteractor:
			brush(node as MouseInteractor, held)
	if not _sunk.is_empty():
		_repattern_in -= delta
		if _repattern_in <= 0.0:
			_repattern_in = RELETTER
			_repattern()


## One frame of `hand` (a mouse) over the set, its button `held` or not: a click on a bar strikes it
## (Item's grab) and starts a brush; while the button stays down, each other bar of the set the
## cursor comes onto is struck in turn, Shift softly, as a hand brushed through them. Let go, the
## brush ends; a drag begun off the set brushes nothing, so a drag that orbits or walks the view
## never rings a bar it passes over.
func brush(hand: Interactor, held: bool) -> void:
	var over := hand.hovered as Bar
	if over != null and not bars.has(over):
		over = null
	# [whether its button was down, whether this is a brush, the bar it is on or last was].
	var was: Array = _brushing.get(hand, [false, false, null])
	if not held:
		_brushing[hand] = [false, false, over]
		return
	if not bool(was[0]):
		# The button has just gone down: a brush only if it went down on a bar, which its grab struck.
		_brushing[hand] = [true, over != null and was[2] == over, over]
		return
	if not bool(was[1]) or over == null or over == was[2]:
		# Between two bars it is still on the last one, so coming back onto it is no new strike.
		return
	_brushing[hand] = [true, true, over]
	over.struck_by(hand, over.global_position)


# --- the piano's sunk black keys ---------------------------------------------------------------

## Which of the slots between the piano's keys stand for a note out of the key in harmony `h`: slot k
## is between key k-1 and key k (slot 0 before the first key, slot `count` after the last), and a
## slot between two keys a whole tone or more apart has the note between them out of the key, so a
## sunk black key there. In A minor (or C major) that is a piano's own pattern: none between B and C
## or E and F.
static func pattern(set_spec: Dictionary, h: Harmony) -> Array:
	var low := int(set_spec.get("low", 72))
	var steps := h.scale.size()
	var out: Array = []
	for k in int(set_spec.get("count", MOST)) + 1:
		var below := scale_tone(h, low, k - 1) if k > 0 else scale_tone(h, low, maxi(steps - 1, 0)) - 12
		out.append(scale_tone(h, low, k) - below > 1)
	return out


## The piano's keys and its sunk black keys as the song's scale has them now (`pattern`): a sunk key
## in each slot with a note out of the key, and each key's tail notched for the sunk keys beside it,
## as a white key's is round a black one. Looked at again every RELETTER, so a bracket into a key of
## another mode shows within it.
func _repattern() -> void:
	var first := bars[0] as Bar
	if first == null:
		return
	var now := pattern(spec, first.harmony_at(InstrumentItem.now()))
	if now == _pattern:
		return
	_pattern = now
	for k in _sunk.size():
		_sunk[k].visible = bool(now[k]) if k < now.size() else false
	for bar: Bar in bars:
		bar.notch(bool(now[bar.n]), bool(now[bar.n + 1]))


## Which slots have a sunk black key now (`pattern`), as last drawn.
func sunk_pattern() -> Array:
	return _pattern.duplicate()


## The sunk black keys, one in every slot (`pattern`), hidden where the slot has none: their tops
## SUNK_PROUD over the white keys', where a raised one's would be 23 mm over, so they read as keys
## held down, out of play. Not items: nothing strikes them.
func _build_sunk_keys() -> void:
	var ebony := _look(Color(0.035, 0.03, 0.03), 0.0, 0.5)
	var pitch: float = spec["pitch"]
	var top := float(spec["at"]) + float(spec["thick"]) + SUNK_PROUD
	var tail := -float(spec["long"]) * 0.5
	for k in int(spec["count"]) + 1:
		var x := bar_x(spec, 0) + (float(k) - 0.5) * pitch
		var key := _box(Vector3(pitch * SUNK_WIDE, 0.02, SUNK_LONG), Vector3(x, top - 0.01, tail + SUNK_LONG * 0.5), ebony,
				"Sunk%d" % k)
		key.visible = false
		_sunk.append(key)


# --- the mount --------------------------------------------------------------------------------

## What the bars hang from, stand on or lie across, drawn in the kind's own way: a timber beam hung
## from above on two cords for the chimes, a snowy eave board for the icicles, a shelf of the cave's
## own rock for the crystals, the railing's own rails for its balusters (the rooftop draws the rest
## of it), a tubular steel frame for the tubular bells, a lit frame for the neon bars, chalk lines for
## the xylophone; a header pipe for the steam pipes, two ribs of the hull bent round the panels'
## ring, the vault's steel for the glass, the piano's sunk black keys, a potting bench, a gong rack, a
## sandstone ledge. The eave, the shelf, the frame, the header, the bench, the rack and the ledge
## are modelled (MOUNTS); the rest are plain.
func _build_mount() -> void:
	var half := half_width(spec) + 0.06
	var at: float = spec["at"]
	match spec["kind"]:
		&"chimes":
			var wood := _look(Color(0.36, 0.22, 0.12), 0.0, 0.7)
			_box(Vector3(half * 2.0, 0.05, 0.05), Vector3(0, at + 0.025, 0), wood, "Beam")
			var cord := _look(Color(0.7, 0.62, 0.48), 0.0, 0.9)
			for side in [-1.0, 1.0]:
				_rod(Vector3(side * (half - 0.04), at + 0.05, 0), float(spec.get("hang_to", at + 1.2)) - at - 0.05,
						0.004, cord, "Cord")
			# Each tube on its own string from the beam.
			for n in int(spec["count"]):
				var f := bar_frame(spec, n)
				_rod(Vector3(f.origin.x, f.origin.y + bar_length(spec, n), 0), at - f.origin.y - bar_length(spec, n),
						0.0012, cord, "String")
		&"icicles":
			# The board's foot is where the icicles hang from; the snow on it droops over its front.
			_piece("Eave", Transform3D(Basis.from_scale(Vector3(half * 2.0, 1, 1)), Vector3(0, at, 0)), {
				"wood": _look(Color(0.42, 0.28, 0.16), 0.0, 0.8), "snow": _look(Color(0.95, 0.97, 1.0), 0.0, 0.9)})
		&"crystals":
			# The cave's own rock (its shader: grain from where it is in the world, so the shelf and the
			# wall behind it are one stone), the crystals growing out of its top, a few small points of
			# the same crystal at its ends.
			var wide := (half * 2.0 + 0.1) / SHELF_WIDE
			_piece("CaveShelf", Transform3D(Basis.from_scale(Vector3(wide, at / 0.82, 1)), Vector3.ZERO), {
				"rock": _cave_rock(), "crystal": _look(spec["colour"], 0.0, 0.08, float(spec.get("glow", 0.0)))})
		&"railing":
			# The rooftop's own rails run through; a brass collar marks each tuned baluster, top and foot.
			pass
		&"tubular_bells":
			# Brushed steel, lighter than a black frame would be, so it shows against a dark wall: two
			# posts on rubber-capped feet, the rail across their tops.
			var steel := {"steel": _look(Color(0.42, 0.43, 0.45), 0.7, 0.42), "rubber": _look(Color(0.06, 0.06, 0.06), 0.0, 0.9)}
			var post := half + 0.02
			_piece("BellRail", Transform3D(Basis.from_scale(Vector3(post / RAIL_FITTING, 1, 1)), Vector3(0, at + 0.02, -0.03)), steel)
			for side in [-1.0, 1.0]:
				_piece("BellPost", Transform3D(Basis.IDENTITY, Vector3(side * post, 0, -0.03)), steel)
				_piece("BellFoot", Transform3D(Basis.IDENTITY, Vector3(side * post, 0, -0.03)), steel)
			var cord := _look(Color(0.6, 0.2, 0.14), 0.0, 0.8)
			for n in int(spec["count"]):
				var f := bar_frame(spec, n)
				_rod(Vector3(f.origin.x, f.origin.y + bar_length(spec, n), 0), at - f.origin.y - bar_length(spec, n),
						0.002, cord, "Cord")
		&"neon":
			var frame := _look(Color(0.05, 0.03, 0.08), 0.6, 0.4)
			var glow := _look(Color(1.0, 0.3, 0.8), 0.0, 0.5, 1.6)
			var long: float = spec["long"]
			for z in [-long * 0.32, long * 0.32]:
				_box(Vector3(half * 2.0, 0.02, 0.025), Vector3(0, at - 0.012, z), frame, "Rail")
				_box(Vector3(half * 2.0, 0.006, 0.006), Vector3(0, at - 0.025, z + 0.014), glow, "Glow")
			for side in [-1.0, 1.0]:
				_box(Vector3(0.025, at - 0.02, 0.025), Vector3(side * (half - 0.02), (at - 0.02) * 0.5, 0), frame, "Leg")
				# Its foot a hair off the floor, so its underside and the leg's are not one plane.
				_box(Vector3(0.006, at - 0.024, 0.006), Vector3(side * (half - 0.02), (at - 0.024) * 0.5 + 0.002, 0.014), glow, "LegGlow")
		&"chalk":
			# Drawn in the air, as everything is in the chalk zone: the frame, two legs and its bars' outlines.
			var long: float = spec["long"]
			var lines: Array = []
			for z in [-long * 0.32, long * 0.32]:
				lines.append(PackedVector3Array([Vector3(-half, at - 0.01, z), Vector3(half, at - 0.01, z)]))
			for side in [-1.0, 1.0]:
				lines.append(PackedVector3Array([Vector3(side * (half - 0.02), at - 0.01, 0), Vector3(side * (half - 0.08), 0.0, 0.05)]))
				lines.append(PackedVector3Array([Vector3(side * (half - 0.02), at - 0.01, 0), Vector3(side * (half - 0.08), 0.0, -0.05)]))
			add_child(Chalk.drawing(lines, Chalk.WHITE, 0.006, false, 2, 4207))
		&"pipes":
			# The header they drop from, along the brick on its brackets, a valve on its left end; a tee
			# on it over each pipe.
			var iron := {"iron": _look(spec["colour"], 0.7, 0.5), "brass": _look(Color(0.72, 0.56, 0.26), 0.9, 0.3),
					"wheel": _look(Color(0.55, 0.08, 0.06), 0.2, 0.5)}
			_piece("PipeHeader", Transform3D(Basis.from_scale(Vector3(half * 2.0, 1, 1)), Vector3(0, at, 0)), iron)
			_piece("PipeValve", Transform3D(Basis.IDENTITY, Vector3(-half, at, 0)), iron)
			for n in int(spec["count"]):
				_piece("PipeTee", Transform3D(Basis.IDENTITY, Vector3(bar_x(spec, n), at, 0)), iron)
		&"hull_panels":
			# Two ribs of the hull bent round the ring, one under the panels and one over them, their
			# ends joined by struts down to the deck, and a line of light along the lower one's face.
			# The struts stand a centimetre clear of the outermost panels round the ring (`outer`, the
			# arc length out to their outer edges), not over them.
			var dark := _look(Color(0.1, 0.11, 0.13), 0.6, 0.45)
			var led := _look(spec["edge"], 0.0, 0.4, 2.0)
			var r := float(spec["arc"])
			var over := top_of(spec) + 0.07
			var count := int(spec.get("count", MOST))
			var outer := maxf(absf(bar_x(spec, 0)), absf(bar_x(spec, count - 1))) + float(spec["radius"])
			var ends := outer + 0.06
			_arc_band(r, ends, at - 0.06, 0.06, -0.052, 0.028, dark, "Rib")
			_arc_band(r, ends, over - 0.03, 0.06, -0.052, 0.028, dark, "Rib")
			_arc_band(r, ends, at - 0.034, 0.008, 0.028, 0.032, led, "RibLight")
			for side: float in [-1.0, 1.0]:
				var a := side * (ends - 0.025) / r
				var foot := Vector3(r * sin(a), 0, r * (1.0 - cos(a))) + Basis(Vector3.UP, -a) * Vector3(0, 0, -0.012)
				var strut := _box(Vector3(0.05, over, 0.06), foot + Vector3(0, over * 0.5, 0), dark,
						"StrutLeft" if side < 0.0 else "StrutRight")
				strut.rotation.y = -a
		&"glass":
			# The vault's own steel: a sill the panes stand in, a rib up between each two and at the
			# ends, the sill on two legs to the deck.
			var steel := _look(Color(0.32, 0.36, 0.4), 0.8, 0.35)
			_box(Vector3(half * 2.0, 0.04, 0.05), Vector3(0, at - 0.02, 0), steel, "Sill")
			for side: float in [-1.0, 1.0]:
				_box(Vector3(0.04, at - 0.04, 0.04), Vector3(side * (half - 0.03), (at - 0.04) * 0.5, -0.005), steel, "Leg")
			var count := int(spec["count"])
			for k in count + 1:
				var x := bar_x(spec, 0) + (float(k) - 0.5) * float(spec["pitch"])
				var tall := bar_length(spec, clampi(k - 1, 0, count - 1))
				if k < count:
					tall = maxf(tall, bar_length(spec, k))
				_box(Vector3(0.012, tall + 0.03, 0.03), Vector3(x, at + (tall + 0.03) * 0.5, 0), steel, "Rib")
		&"piano":
			# The club's own upright is the case and the rest of the keys (ClubVenue); here are the
			# octave's sunk black keys.
			_build_sunk_keys()
		&"pots":
			# A potting bench, the pots stood upside down on its top in a row.
			_piece("PotBench", Transform3D(Basis.from_scale(Vector3(half * 2.0 + 0.06, at / 0.8, 1)), Vector3.ZERO), {
				"wood": _look(Color(0.42, 0.3, 0.19), 0.0, 0.85), "zinc": _look(Color(0.55, 0.57, 0.58), 0.7, 0.55)})
		&"cymbals":
			# A black steel rack: the gong hung from its top bar on two cords, the cymbals each on a
			# felted pin along its lower rail.
			_piece("GongRack", Transform3D(Basis.from_scale(Vector3(half * 2.0 + 0.1, 1, 1)), Vector3.ZERO), {
				"steel": _look(Color(0.07, 0.07, 0.08), 0.7, 0.4), "rubber": _look(Color(0.05, 0.05, 0.05), 0.0, 0.9)})
			var cord := _look(Color(0.55, 0.12, 0.1), 0.0, 0.8)
			var gong: Dictionary = spec["gong"]
			var size := float(gong["size"])
			for side: float in [-1.0, 1.0]:
				_rod(Vector3(side * size * 0.3, float(gong["at"]) - 0.02, float(gong["z"])), GONG_BAR - float(gong["at"]) + 0.02,
						0.003, cord, "Cord")
			var felt := _look(Color(0.5, 0.08, 0.1), 0.0, 0.95)
			var steel := _look(Color(0.5, 0.5, 0.52), 0.8, 0.3)
			for n in range(1, int(spec["count"])):
				var x := bar_x(spec, n)
				_rod(Vector3(x, GONG_RAIL, 0), at - GONG_RAIL - 0.006, 0.0035, steel, "Pin")
				_rod(Vector3(x, at - 0.006, 0), 0.006, 0.012, felt, "Felt")
		&"stones":
			# A ledge of the desert's sandstone, the stones lying across the two ridges along its top.
			_piece("StoneShelf", Transform3D(Basis.from_scale(Vector3(half * 2.0 + 0.04, at / STONE_RIDGE, 1)), Vector3.ZERO), {
				"rock": _look(Color(0.72, 0.5, 0.34), 0.0, 0.95)})
	var lit := float(spec.get("lamp", LAMP_ENERGY))
	if (spec["shape"] == HANG or spec.has("gong")) and lit > 0.0:
		# A small can on an arm out from the rail, aimed back at the bars' middle: the wall a set hangs
		# against is often the room's darkest, and a metal tube in the dark is a black line. From out
		# in front and soft it lights the bars' length; straight down from the rail it blew their tops
		# out to a white bloom.
		var rail_top: float = at + float({&"chimes": 0.05, &"pipes": PIPE_HEADER + 0.04}.get(spec["kind"], 0.045))
		if spec.has("gong"):
			# Over the rack's top bar, aimed down at the cymbals and the gong behind them.
			rail_top = GONG_BAR + 0.035
		var fitting := _look(Color(0.08, 0.08, 0.09), 0.6, 0.4)
		var arm_from := float(spec["gong"]["z"]) if spec.has("gong") else -0.02
		# A hair over the can's foot, so the arm's underside and the can's are not one plane.
		_box(Vector3(0.014, 0.014, LAMP_OUT - arm_from), Vector3(0, rail_top + 0.011, (LAMP_OUT + arm_from) * 0.5), fitting, "LampArm")
		var lamp := ZoneKit.spot_down(self, Vector3(0, rail_top, LAMP_OUT), LAMP_COLOUR, lit, LAMP_CONE, 2.6, fitting)
		lamp.position.y -= 0.03
		var drop := lamp.position.y - (at - float(spec["long"]) * 0.5)
		lamp.rotation = Vector3(-PI * 0.5 + atan2(LAMP_OUT, drop), 0, 0)
		lamp.light_specular = LAMP_SPECULAR
		lamp.spot_attenuation = LAMP_FALLOFF
	elif spec["shape"] == STAND and float(spec.get("glow", 0.0)) > 0.0:
		# A glowing set lights what it stands on: the crystals' shelf, by their own colour.
		var glow := OmniLight3D.new()
		glow.name = "Glow"
		glow.position = Vector3(0, at + 0.08, front_of(spec) + 0.05)
		var c: Color = spec["colour"]
		glow.light_color = Color(c.r, c.g, c.b)
		glow.light_energy = GLOW_ENERGY
		glow.omni_range = GLOW_REACH
		glow.light_specular = 0.1
		glow.shadow_enabled = false
		add_child(glow)


func _box(size: Vector3, at: Vector3, material: Material, label: String) -> MeshInstance3D:
	return ZoneKit.block(self, size, at, material, label)


## A band bent round the arc of radius `r` the set's ring stands on (`arc`), from `-ends` to `ends`
## along it: from `foot` up `tall`, from `back` to `front` out of the arc (toward its middle). Smooth
## pieces meeting end to end, so its faces are one surface the length of it, not boxes meeting at
## angles.
func _arc_band(r: float, ends: float, foot: float, tall: float, back: float, front: float, material: Material,
		label: String) -> void:
	var steps := 24
	var at := func(a: float, out: float, y: float) -> Vector3:
		# `out` toward the ring's middle, which is +Z at the arc's own middle.
		return Vector3((r - out) * sin(a), y, r - (r - out) * cos(a))
	var top := foot + tall
	# In ARC_PIECES pieces round the ring, so each piece's box hugs the band (a plaque in front of
	# the ring's middle is in front of the band there, not inside one box round the whole bend).
	for piece_n in ARC_PIECES:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		# Each quad as its corners go round anticlockwise seen from outside, wound clockwise for
		# Godot's front faces.
		var quad := func(p: Array) -> void:
			for i: int in [0, 2, 1, 0, 3, 2]:
				st.add_vertex(p[i])
		var first := piece_n * steps / ARC_PIECES
		for k in range(first, (piece_n + 1) * steps / ARC_PIECES):
			var a0 := lerpf(-ends, ends, float(k) / steps) / r
			var a1 := lerpf(-ends, ends, float(k + 1) / steps) / r
			quad.call([at.call(a0, front, top), at.call(a1, front, top), at.call(a1, back, top), at.call(a0, back, top)])
			quad.call([at.call(a0, back, foot), at.call(a1, back, foot), at.call(a1, front, foot), at.call(a0, front, foot)])
			quad.call([at.call(a0, front, foot), at.call(a1, front, foot), at.call(a1, front, top), at.call(a0, front, top)])
			quad.call([at.call(a1, back, foot), at.call(a0, back, foot), at.call(a0, back, top), at.call(a1, back, top)])
		var caps: Array = []
		if piece_n == 0:
			caps.append(-ends / r)
		if piece_n == ARC_PIECES - 1:
			caps.append(ends / r)
		for a: float in caps:
			var cap := [at.call(a, back, foot), at.call(a, front, foot), at.call(a, front, top), at.call(a, back, top)]
			if a > 0.0:
				cap.reverse()
			quad.call(cap)
		st.generate_normals()
		var piece := MeshInstance3D.new()
		piece.name = label
		piece.mesh = st.commit()
		piece.material_override = material
		add_child(piece, true)


## The meshes of MOUNTS by object name, loaded once.
static var _mount_meshes := {}


## The modelled mount piece `label` (an object of MOUNTS) at `at` in the set's frame, each of its
## surfaces given the material `looks` has under its Blender material's name.
func _piece(label: String, at: Transform3D, looks: Dictionary) -> MeshInstance3D:
	if _mount_meshes.is_empty():
		var scene := (load(MOUNTS) as PackedScene).instantiate()
		for m: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			_mount_meshes[String(m.name)] = m.mesh
		scene.free()
	var piece := MeshInstance3D.new()
	piece.name = label
	piece.mesh = _mount_meshes.get(label)
	piece.transform = at
	if piece.mesh != null:
		for s in piece.mesh.get_surface_count():
			var m := piece.mesh.surface_get_material(s)
			if m != null and looks.has(m.resource_name):
				piece.set_surface_override_material(s, looks[m.resource_name])
	add_child(piece)
	return piece


## The cave's rock (its shader, as CaveVenue's walls are), for the crystals' shelf.
static func _cave_rock() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://core/venues/shaders/cave_rock.gdshader")
	for k: String in CAVE_ROCK:
		m.set_shader_parameter(k, CAVE_ROCK[k])
	return m


## The cave wall's rock (CaveVenue._build_grotto's `wall`), a little lighter so the shelf reads
## against the dark round it.
const CAVE_ROCK := {"dark": Color(0.11, 0.1, 0.13), "light": Color(0.42, 0.38, 0.46),
		"strata_tint": Color(0.32, 0.25, 0.22), "scale": 1.8, "bump": 1.0, "strata": 0.5, "wet_below": 0.8}


## A thin upright rod from `foot` up `tall`.
func _rod(foot: Vector3, tall: float, radius: float, material: Material, label: String) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.name = label
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = maxf(tall, 0.001)
	mesh.radial_segments = 6
	mesh.rings = 1
	piece.mesh = mesh
	piece.position = foot + Vector3.UP * tall * 0.5
	piece.material_override = material
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(piece)
	return piece


static func _look(colour: Color, metal: float, rough: float, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.metallic = metal
	m.roughness = rough
	if colour.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = Color(colour.r, colour.g, colour.b)
		m.emission_energy_multiplier = glow
	return m


# --- a bar ------------------------------------------------------------------------------------

## One bar of a venue's set: a fixed pitched instrument of the room (`venue1`..`venue8`), dressed as
## the set's kind wherever the studio stands it (`dress`). See the class above.
class Bar extends InstrumentItem:
	## Which bar of its set this is, 0-based: the first rings the key's own note.
	var n := 0
	## The set it is dressed as (VenueInstrument.filled): empty until it is.
	var set_spec: Dictionary = {}
	## Its length, its half width across the row and its half depth out of it, as dressed.
	var length := 0.3
	var radius := 0.015
	var depth := 0.015
	## A piano key's tail notched for a sunk black key on its left and its right (`notch`).
	var notched := [false, false]
	var _letters: Array[Label3D] = []
	var _reletter_in := 0.0

	func _init(index := 0) -> void:
		n = clampi(index, 0, VenueInstrument.MOST - 1)
		id = VenueInstrument.bar_id(n)
		fixed = true
		own_home = true
		super()

	## Dressed as one of `spec`'s bars: its look, its grip and its letters built again for the kind.
	func dress(spec: Dictionary) -> void:
		set_spec = spec
		length = VenueInstrument.bar_length(spec, n)
		radius = VenueInstrument.bar_radius(spec, n)
		depth = VenueInstrument.bar_depth(spec, n)
		for child in body.get_children():
			body.remove_child(child)
			child.queue_free()
		_letters.clear()
		body.add_child(_build_look())
		_shape.shape = _grip_shape()
		_shape.position = _middle()
		if _tag != null:
			_tag.position = _middle() + Vector3.UP * (_extent().y * 0.5 + 0.05)
		_reletter()

	## A piano key's tail notched for the sunk black keys either side of it (VenueInstrument._repattern),
	## its look built again where that changes.
	func notch(left: bool, right: bool) -> void:
		if notched == [left, right]:
			return
		notched = [left, right]
		if not set_spec.is_empty():
			dress(set_spec)

	func shape() -> StringName:
		return VenueInstrument.bar_shape(set_spec, n) if not set_spec.is_empty() else VenueInstrument.HANG

	## Whether it is the set's gong (`gong`): the first bar of the stage's, hung behind its cymbals.
	func is_gong() -> bool:
		return n == 0 and set_spec.has("gong")

	## Whether it is round (`disc`): a cymbal lying, or the gong hanging.
	func is_disc() -> bool:
		return set_spec.get("disc", false)

	func item_title() -> String:
		if set_spec.is_empty():
			return "VENUE BAR %d" % (n + 1)
		if is_gong():
			return str(set_spec["gong"].get("one", "GONG"))
		return "%s %d" % [set_spec["one"], n + 1]

	## What its jack is called (Jacks.source_name): the set's, since the set has the one.
	func jack_title() -> String:
		return str(set_spec.get("title", item_title()))

	## The set's one source, whichever bar of it is struck.
	func jack_source() -> StringName:
		return VenueInstrument.SOURCE

	## The set's jack is on its mount, not on each bar.
	func has_own_jack() -> bool:
		return false

	func readout() -> String:
		var at := InstrumentItem.now()
		var h := harmony_at(at)
		var said := "rings %s, the %s of %s" % [h.note_name(note_at(at)), _ordinal(n % 7 + 1), h.key_name]
		if not h.named:
			said += " (NO KEY SET)"
		return "%s  ·  %s" % [said, InstrumentItem.path_words()]

	func hint() -> String:
		if InstrumentItem.hands_hint:
			if set_spec.get("touch", false):
				return "touch it with a hand, or a controller's tip or grip: a touch rings it · brush across the set to ring several"
			return "strike it with a hand, or a controller's tip or grip · brush across the set to ring several"
		return "click to strike it, Shift-click softly · hold the button and drag across the set to brush it"

	## Its note at song position `seconds`: its scale tone up from the set's tonic (scale_tone).
	func note_at(seconds: float) -> int:
		return VenueInstrument.scale_tone(harmony_at(seconds), int(set_spec.get("low", 72)), n)

	func pitch() -> int:
		return note_at(InstrumentItem.now())

	func channel() -> int:
		return InstrumentItem.MELODIC_CHANNEL

	func note_seconds() -> float:
		return VenueInstrument.RING_SECONDS

	## Its kind's sound, or the gong's own for the gong.
	func sound_kind(_struck: bool) -> StringName:
		if is_gong():
			return set_spec["gong"].get("sound", &"gong")
		return set_spec.get("sound", &"chime")

	## From the note its kind's sound rings at (Foley.venue_bar_note) to `note`.
	func sound_pitch(note: int) -> float:
		return pow(2.0, float(note - Foley.venue_bar_note(sound_kind(true))) / 12.0)

	## A glass that rings at a touch (`touch`) rings at TOUCH_LEAST, slower than a strike.
	func strike_least() -> float:
		return VenueInstrument.TOUCH_LEAST if set_spec.get("touch", false) else super()

	## A touch on a glass rings it softly, from TOUCH_SOFT up to TOUCH_FIRM as it comes up to a
	## stroke's speed; faster, as any strike.
	func velocity_of(speed: float) -> int:
		if set_spec.get("touch", false) and speed < InstrumentItem.STROKE_MIN:
			var along := clampf((speed - VenueInstrument.TOUCH_LEAST) / (InstrumentItem.STROKE_MIN - VenueInstrument.TOUCH_LEAST), 0.0, 1.0)
			return roundi(lerpf(VenueInstrument.TOUCH_SOFT, VenueInstrument.TOUCH_FIRM, along))
		return super(speed)

	## In a headset its tag says which way its hits are heard, once for the set: on the first bar.
	func tag_text() -> String:
		return super() if n == 0 else ""

	func centre_height() -> float:
		return _middle().y

	## Where it is struck: a hanging or standing bar's four sides (a plane through its axis on each,
	## out at its surface, its +Y out of that side), so a hand through it from any side across rings
	## it; a tubular bell's cap, or a pot's base, as well; a lying bar's top (a cymbal's round); a
	## gong's face, front and back. The railing's balusters are struck from the terrace side and along
	## it, not from over the edge.
	func faces() -> Array:
		var out: Array = []
		if set_spec.is_empty():
			return out
		var g := global_transform
		if shape() == VenueInstrument.LIE:
			var thick: float = set_spec.get("thick", 0.03)
			var top := g * Transform3D(Basis.IDENTITY, Vector3(0, thick, 0))
			if is_disc():
				out.append({"frame": top, "radius": radius})
			else:
				out.append({"frame": top, "half": Vector2(radius, length * 0.5)})
			return out
		var middle := Vector3(0, length * 0.5, 0)
		if is_gong():
			for out_of: Vector3 in [Vector3.BACK, Vector3.FORWARD]:
				out.append({"frame": g * Transform3D(Basis(out_of.cross(Vector3.UP), out_of, Vector3.UP), middle + out_of * depth),
						"radius": radius})
			return out
		var sides: Array = [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]
		if set_spec.get("kind") == &"railing":
			sides = [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK]
		for out_of: Vector3 in sides:
			# Its +Y out of the side, its Z up the bar and its X across it: a flat bar's faces out at its
			# half thickness, its edges at its half width.
			var across := out_of.cross(Vector3.UP)
			var off := radius if out_of.x != 0.0 else depth
			var wide := depth if out_of.x != 0.0 else radius
			out.append({"frame": g * Transform3D(Basis(across, out_of, Vector3.UP), middle + out_of * off),
					"half": Vector2(wide + 0.01, length * 0.5)})
		if set_spec.get("caps", false) or set_spec.get("top", false):
			out.append({"frame": g * Transform3D(Basis.IDENTITY, Vector3(0, length, 0)), "radius": _top_radius() + 0.005})
		return out

	func zone_at(_point: Vector3) -> StringName:
		return &""

	## Its top's radius: a pot's base, narrower than its mouth; else its own.
	func _top_radius() -> float:
		return radius * POT_BASE if set_spec.get("pot", false) else radius

	func _middle() -> Vector3:
		return Vector3(0, float(set_spec.get("thick", 0.03)) * 0.5, 0) if shape() == VenueInstrument.LIE \
				else Vector3(0, length * 0.5, 0)

	## Its size: across, up and along (a lying bar's length along Z).
	func _extent() -> Vector3:
		if shape() == VenueInstrument.LIE:
			return Vector3(radius * 2.0, float(set_spec.get("thick", 0.03)), length)
		return Vector3(radius * 2.0, length, depth * 2.0)

	func _grip_shape() -> Shape3D:
		var box := BoxShape3D.new()
		var size := _extent() if not set_spec.is_empty() else Vector3(0.04, 0.3, 0.04)
		# A little bigger than it, but never into the next bar's: a piano key's by no more than the
		# gap to the next.
		var more := Vector3(0.016, 0.02, 0.016)
		if set_spec.get("keys", false):
			more.x = 0.001
		box.size = size + more
		return box

	## How wide a pot's base is, upside down on top, against its mouth on the bench; and how far up its
	## rim its body starts, so the two are not one plane where they stand on the bench.
	const POT_BASE := 0.68
	const POT_FOOT := 0.004

	func _build_look() -> Node3D:
		var root := Node3D.new()
		root.name = "Look"
		var colour: Color = set_spec["colour"]
		var m := VenueInstrument._look(colour, float(set_spec.get("metal", 0.0)), float(set_spec.get("rough", 0.5)),
				float(set_spec.get("glow", 0.0)))
		if set_spec.get("stone", false):
			# Each stone its own: a little lighter or darker, a little warmer or cooler.
			var shade := 0.88 + 0.24 * fposmod(float(n) * 0.618, 1.0)
			m = VenueInstrument._look(Color(colour.r * shade, colour.g * shade * 0.98, colour.b * (2.0 - shade) * 0.5 + colour.b * 0.5),
					0.0, float(set_spec["rough"]))
		var mesh := MeshInstance3D.new()
		mesh.name = "Bar"
		if set_spec.get("keys", false):
			_build_key(root, m)
		elif shape() == VenueInstrument.LIE and is_disc():
			_build_cymbal(root, m)
		elif is_gong():
			_build_gong(root)
		elif shape() == VenueInstrument.LIE:
			var box := BoxMesh.new()
			box.size = _extent()
			mesh.mesh = box
			mesh.position = _middle()
			if set_spec.get("stone", false):
				# Laid by hand: not quite square to the row.
				mesh.rotation.y = (fposmod(float(n) * 0.37, 1.0) - 0.5) * 0.08
		elif set_spec.has("plate"):
			var box := BoxMesh.new()
			box.size = _extent()
			mesh.mesh = box
			mesh.position = _middle()
		else:
			var tube := CylinderMesh.new()
			tube.height = length
			tube.radial_segments = 6 if set_spec.get("facets", false) else 14
			tube.rings = 1
			tube.top_radius = radius
			tube.bottom_radius = radius
			if set_spec.get("taper", false):
				# An icicle: thick at its root, up top, to a point.
				tube.bottom_radius = 0.0015
			elif set_spec.get("pot", false):
				# A flowerpot upside down: its mouth on the bench (inside its rim), its base on top.
				tube.top_radius = radius * POT_BASE
				tube.radial_segments = 24
				tube.height = length - POT_FOOT
			elif set_spec.get("pipe", false):
				# Up into its tee's socket, so the two do not meet in one plane.
				tube.height = length + 0.012
			elif set_spec.get("facets", false):
				# A crystal: its point a short pyramid on top.
				tube.height = length * 0.84
				var tip := MeshInstance3D.new()
				tip.name = "Point"
				var cone := CylinderMesh.new()
				cone.radial_segments = 6
				cone.rings = 1
				cone.top_radius = 0.001
				cone.bottom_radius = radius
				cone.height = length * 0.16
				tip.mesh = cone
				tip.position = Vector3(0, length * 0.92, 0)
				tip.material_override = m
				root.add_child(tip)
			mesh.mesh = tube
			mesh.position = Vector3(0, tube.height * 0.5 + (POT_FOOT if set_spec.get("pot", false) else 0.0), 0)
		if mesh.mesh != null:
			mesh.material_override = m
			root.add_child(mesh)
		else:
			mesh.free()
		if set_spec.has("collar"):
			# The railing's tuned balusters: a brass collar at each end, so they read from the others.
			for y: float in [0.06, length - 0.06]:
				_ring(root, "Collar", radius + 0.006, 0.03, y, VenueInstrument._look(set_spec["collar"], 0.9, 0.3), 12)
		if set_spec.get("caps", false):
			# Proud of the tube's top by a hair, so the two tops are not one plane.
			_ring(root, "Cap", radius + 0.004, 0.02, length - 0.009, VenueInstrument._look(Color(0.78, 0.66, 0.36), 0.9, 0.25), 14)
		if set_spec.get("pipe", false):
			# A steam pipe: a flange where it leaves its tee, a coupling a third of the way down, and a
			# cap screwed on its foot.
			var iron := VenueInstrument._look(colour.lightened(0.08), 0.7, 0.45)
			_ring(root, "Flange", radius + 0.008, 0.016, length - 0.03, iron, 14)
			_ring(root, "Coupling", radius + 0.005, 0.03, length * 0.66, iron, 14)
			_ring(root, "FootCap", radius + 0.004, 0.035, 0.0125, VenueInstrument._look(Color(0.62, 0.48, 0.24), 0.9, 0.35), 14)
		if set_spec.get("pot", false):
			# Its rim, round the mouth on the bench, and the drainage hole in its base on top.
			_ring(root, "Rim", radius + 0.005, 0.03, 0.013, VenueInstrument._look(colour.darkened(0.06), 0.0, 0.9), 24)
			var hole := _ring(root, "Hole", radius * 0.14, 0.002, length + 0.0005, VenueInstrument._look(Color(0.08, 0.05, 0.04), 0.0, 1.0), 12)
			hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if set_spec.has("edge"):
			# A hull panel: a line of light up its left edge, and a darker border inset round its face.
			_box_on(root, "Edge", Vector3(0.004, length - 0.04, 0.003), Vector3(-radius + 0.008, length * 0.5, depth + 0.0019),
					VenueInstrument._look(set_spec["edge"], 0.0, 0.4, 2.2))
			_box_on(root, "Inset", Vector3(radius * 2.0 - 0.03, length - 0.05, 0.0016), Vector3(0.003, length * 0.5, depth + 0.0012),
					VenueInstrument._look(colour.darkened(0.25), 0.7, 0.35))
		if set_spec.get("drawn", false):
			var half := Vector2(radius, length * 0.5)
			var top := float(set_spec.get("thick", 0.03))
			var outline := PackedVector3Array([Vector3(-half.x, top, -half.y), Vector3(half.x, top, -half.y),
					Vector3(half.x, top, half.y), Vector3(-half.x, top, half.y), Vector3(-half.x, top, -half.y)])
			root.add_child(Chalk.drawing([outline], Chalk.NEON[n % Chalk.NEON.size()], 0.004, false, 2, 4300 + n))
		_letter(root)
		return root

	## A short upright cylinder on `root`: a collar, a cap, a rim.
	func _ring(root: Node3D, label: String, r: float, tall: float, y: float, material: Material, sides: int) -> MeshInstance3D:
		var ring := MeshInstance3D.new()
		ring.name = label
		var c := CylinderMesh.new()
		c.top_radius = r
		c.bottom_radius = r
		c.height = tall
		c.radial_segments = sides
		c.rings = 1
		ring.mesh = c
		ring.position = Vector3(0, y, 0)
		ring.material_override = material
		root.add_child(ring)
		return ring

	func _box_on(root: Node3D, label: String, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
		var piece := MeshInstance3D.new()
		piece.name = label
		var box := BoxMesh.new()
		box.size = size
		piece.mesh = box
		piece.position = at
		piece.material_override = material
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(piece)
		return piece

	## A piano key: its head full width at the front, its tail behind narrowed on each side that has a
	## sunk black key beside it (`notched`), as a white key is cut round the black ones.
	func _build_key(root: Node3D, ivory: Material) -> void:
		var thick := float(set_spec["thick"])
		var wide := radius * 2.0
		var sunk := float(set_spec["pitch"]) * VenueInstrument.SUNK_WIDE * 0.5 + 0.0008
		var tail_long := VenueInstrument.SUNK_LONG
		var head_long := length - tail_long
		_box_on(root, "Head", Vector3(wide, thick, head_long), Vector3(0, thick * 0.5, length * 0.5 - head_long * 0.5), ivory)
		var left := -radius + (sunk - (float(set_spec["pitch"]) * 0.5 - radius) if notched[0] else 0.0)
		var right := radius - (sunk - (float(set_spec["pitch"]) * 0.5 - radius) if notched[1] else 0.0)
		_box_on(root, "Tail", Vector3(right - left, thick, tail_long), Vector3((left + right) * 0.5, thick * 0.5, -length * 0.5 + tail_long * 0.5),
				ivory)

	## A cymbal lying on its pin: a thin disc with a bell in its middle.
	func _build_cymbal(root: Node3D, bronze: Material) -> void:
		var thick := float(set_spec["thick"])
		var disc := _ring(root, "Bar", radius, thick, thick * 0.5, bronze, 32)
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var bell := MeshInstance3D.new()
		bell.name = "Bell"
		var dome := SphereMesh.new()
		dome.radius = radius * 0.3
		dome.height = radius * 0.3
		dome.is_hemisphere = true
		dome.radial_segments = 20
		dome.rings = 6
		bell.mesh = dome
		bell.position = Vector3(0, thick, 0)
		bell.material_override = bronze
		root.add_child(bell)

	## The gong, hung facing the player: a bronze disc, its turned-back rim and its boss.
	func _build_gong(root: Node3D) -> void:
		var bronze := VenueInstrument._look(Color(0.86, 0.62, 0.3), 0.65, 0.35)
		var face := Basis(Vector3.RIGHT, PI * 0.5)
		var disc := _ring(root, "Bar", radius - 0.012, depth * 2.0, 0.0, bronze, 40)
		disc.transform = Transform3D(face, _middle())
		var rim := MeshInstance3D.new()
		rim.name = "Rim"
		var torus := TorusMesh.new()
		torus.inner_radius = radius - 0.018
		torus.outer_radius = radius
		torus.rings = 40
		torus.ring_segments = 8
		rim.mesh = torus
		rim.transform = Transform3D(face, _middle())
		rim.material_override = VenueInstrument._look(Color(0.42, 0.28, 0.12), 0.85, 0.4)
		root.add_child(rim)
		var boss := MeshInstance3D.new()
		boss.name = "Boss"
		var dome := SphereMesh.new()
		dome.radius = radius * 0.22
		dome.height = radius * 0.16
		dome.radial_segments = 24
		dome.rings = 8
		boss.mesh = dome
		boss.transform = Transform3D(face, _middle() + Vector3(0, 0, depth))
		boss.material_override = VenueInstrument._look(Color(0.85, 0.65, 0.3), 0.9, 0.22)
		root.add_child(boss)

	## The note it rings now, lettered where it is read from the front: on a lying bar's near end,
	## flat; on a vertical one at its foot, upright, facing out; on a gong under its rim.
	func _letter(root: Node3D) -> void:
		var l := Label3D.new()
		l.name = "Note"
		l.pixel_size = 0.0002
		l.font_size = roundi(float(set_spec.get("letter_cap", VenueInstrument.LETTER_CAP)) / l.pixel_size)
		l.outline_size = 10
		l.modulate = Color(0.98, 0.96, 0.9)
		l.outline_modulate = Color(0.05, 0.04, 0.03)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		Lettering.range_to_legibility(l)
		if set_spec.get("keys", false):
			# On the key's head, dark on the ivory as a key's maker's name is.
			l.modulate = Color(0.12, 0.1, 0.09)
			l.outline_modulate = Color(0.95, 0.92, 0.84)
			l.outline_size = 4
			var thick := float(set_spec["thick"])
			l.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, thick + 0.0015, length * 0.5 - 0.02))
		elif shape() == VenueInstrument.LIE:
			var top := float(set_spec.get("thick", 0.03))
			var near := length * 0.5 - (0.025 if is_disc() else 0.04)
			l.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, top + 0.002, near))
		elif shape() == VenueInstrument.HANG:
			l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			l.position = Vector3(0, -0.015, depth + VenueInstrument.LETTER_OUT)
		else:
			# Over its top, or where its kind says (`letter_y`): the railing's just over its foot collar,
			# under the rail its tops run into; a pot's over its rim.
			l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			l.position = Vector3(0, float(set_spec.get("letter_y", length + 0.015)), depth + VenueInstrument.LETTER_OUT)
		root.add_child(l)
		_letters.append(l)

	## What its letters say now: the note it rings.
	func letters() -> String:
		return _letters[0].text if not _letters.is_empty() else ""

	func _process(delta: float) -> void:
		_reletter_in -= delta
		if _reletter_in <= 0.0:
			_reletter_in = VenueInstrument.RELETTER
			_reletter()

	func _reletter() -> void:
		if _letters.is_empty() or set_spec.is_empty():
			return
		var at := InstrumentItem.now()
		var said := harmony_at(at).note_name(note_at(at), bool(set_spec.get("octave", true)))
		for l in _letters:
			if l.text != said:
				l.text = said

	static func _ordinal(k: int) -> String:
		return ["", "first", "second", "third", "fourth", "fifth", "sixth", "seventh"][clampi(k, 0, 7)] + " degree"
