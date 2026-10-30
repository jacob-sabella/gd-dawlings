class_name Theremin
extends Node3D

## A theremin (docs/spatial_loop.md part two, slice 50; idea #23, and #37 on it): one hand is the
## pitch, the other the volume, optionally snapped to the song's scale, with a pitch guide you can
## see, so it is playable and not only a novelty.
##
## THE LAW. The pitch hand's distance from the upright pitch rod (across the floor, from its axis,
## at any height in its field) is the pitch, continuous over three octaves and log in distance
## (`pitch_for`): TOP_PITCH (C6) at NEAR, BOTTOM_PITCH (C3) at FAR, nearer is higher. The volume
## hand's height over the loop is expression (`expression_for`, CC 11): silent down on the loop,
## full VOLUME_SPAN above it. A volume hand nowhere over the loop leaves it full, as a real
## theremin is loud with the volume hand away; so a player with only a pitch hand still plays.
##
## THE KEYS. It plays on this player's keys (`keys`, GuestMidi) with source SOURCE, so on the fast
## path: heard at once on the keys' own synth, sent to everyone, taken down as a take. A theremin
## glides and the keys play notes, so it plays one held note, moved by the pitch wheel within the
## bend range (Wobble.BEND_MOST, two semitones), and handed on legato to the next note at the
## range's edge (part two's "A player has one pitch wheel"): the new note goes on, its bend with it,
## and only then the old one off, so there is never a gap and never a rest of the wheel between.
## Its take is notes, bends and CC 11, and plays back on any synth. The note goes on while a pitch
## hand is in the field and the volume is open, and lets go when the pitch hand leaves the field or
## the volume hand comes down onto the loop.
##
## SNAPPED. Its SCALE switch (`snap`) is FREE (every pitch between), SCALE (the song's scale where
## the song is, Harmony.snap) or CHORD (the tones of the chord this player plays in, ChordHand.at),
## with a short glide (GLIDE) from tone to tone, so a snapped theremin still slides. A snapped
## glide hands on to a tone it snaps to, the one inside the bend nearest where it is going, bent
## back to where the glide is (`_note_for`), so a snapped take is the scale's notes and not those
## the glide passes between. The switch is this player's own: what it changes is what their notes
## are, and those are what crosses the wire. It starts FREE, as the real instrument is: snapped, it
## steps from tone to tone, which reads as gaps in what should be one fluid sweep.
##
## THE GUIDE. Rings round the rod at each step it can land on (the scale's tones, or the chord's),
## each lettered (`letters`, never shown: its card says the lit one) on a rule running out from the
## rod at GUIDE_Y, the octave on the key's tonic. The ring nearest the pitch hand is lit (brighter
## and thicker), drawn at the hand's height, and a bar from it to the hand shows how far off the
## hand is, its card naming it, in cents. So a
## player sees where the next note is before they get there.
##
## WOBBLE (slice 15). The pitch hand's tilt bends and its shake wobbles, through a Wobble that only
## reads the hand (`sending` off): its bend is added to the glide before the note is chosen, so a
## tilt past the range hands on as a reach would.
##
## AT A DESK. The cursor resting in the field (`Field`, a band along the rule through the rod) is
## the pitch hand: across is pitch along the lettered rule, nearer the rod higher. The wheel over the
## field is the volume (`desk_volume`), from silent; holding the button down in the field plays it
## full while held, for a quick phrase. The cursor leaving the field puts the volume back down on the loop, so a
## cursor passing over it is silent. The cursor's travel across is the pitch and nothing else, so its
## tilt does not bend here: its wiggle up and down wobbles (Wobble `axis`), and Alt with the mouse up
## or down bends, as everywhere.
##
## IN A HEADSET. Each tracked bare hand's palm and each controller is a hand; whichever is over the
## loop is the volume hand, and of the rest the nearest the rod in its field is the pitch hand.
##
## It stands on the floor by itself (station `theremin`, Venue.theremin_spot), a trolley in a studio,
## with AIR round where the hands play (Stations, `air` and `air_at`).

## What its notes say they came from (Session.send_note's `source`), and its station.
const SOURCE := &"theremin"
const STATION := &"theremin"
const MODEL := "res://assets/models/theremin.glb"

## Its footprint on the floor, half its size (the loop's overhang on the left included), its middle
## on its origin; and how tall it stands, the rod's tip.
const FOOT := Vector2(0.42, 0.15)
const FOOT_Z := 0.0
const TOP := 1.61
## The cabinet (tools/blender/theremin.py): half its width and depth, and its top.
const CABINET := Vector2(0.22, 0.11)
const CABINET_LOW := 0.83
const DECK_Y := 0.95
## The pitch rod: its axis's x and z, and its tip.
const ROD := Vector2(0.2, -0.02)
const ROD_TOP := 1.6
## The volume loop's middle and radius.
const LOOP := Vector3(-0.34, 0.98, 0.0)
const LOOP_RADIUS := 0.075

## The law: TOP_PITCH (C6) at NEAR from the rod's axis, BOTTOM_PITCH (C3) at FAR (m).
const NEAR := 0.1
const FAR := 0.6
const TOP_PITCH := 84
const BOTTOM_PITCH := 48
## The pitch field: the heights a pitch hand counts between, and how far past FAR it is still at the
## bottom note before it has left the field.
const FIELD_LOW := DECK_Y + 0.02
const FIELD_HIGH := ROD_TOP + 0.25
const FIELD_OUT := 0.08
## The volume hand: how far from the loop's middle across the floor it is over the loop, how far
## under the loop it still counts as down on it, the height over it that is silent (resting on it),
## and the height over that which is full.
const LOOP_REACH := 0.16
const LOOP_UNDER := 0.15
const LOOP_REST := 0.02
const VOLUME_SPAN := 0.35
## Where its hands play, in its frame: between the rod and the loop, in front of the cabinet, at the
## height of the hands. Its `air` (Stations) is free round this, toward it and either side; behind it
## is where its player stands. And the lowest a hand goes there: the loop, less a hand's thickness.
const AIR_AT := Vector3(-0.07, 1.2, 0.2)
const HANDS_LOW := LOOP.y - 0.1
## A note goes on once the expression is this or more, and lets go at 0.
const OPENS := 2
## How long a snapped glide takes to get most of the way to the next tone (s, a one-pole's time).
const GLIDE := 0.05
## How hard its notes are played: expression is its dynamics.
const VELOCITY := 100
## The most controls it sends a second, of each kind, between the hand-ons and note-ons that send at
## once.
const SENDS_A_SECOND := 60.0
const SEND_SLACK := 0.002
## A hand not seen for this long (s) has left (a pitch hand's note lets go).
const LOST := 0.25

## The guide: the rings' height and their tube (the key's root's rings ROOT_TUBE, so each octave
## reads without its letter), the lit ring's tube, how far the rule runs past FAR, the letters' cap
## height and how far over or under the rule they stand, how small a letter may be made where the
## rings crowd near the rod (LETTER_LEAST of its size; one that would be smaller is left off, its
## ring still there), how much room a letter keeps to the next on its side of the rule (LETTER_AIR
## times their half widths, so they stay apart seen along the rule too), how much larger the lit
## ring's letter stands, and how far further out from the rule (LIT_LIFT of the cap height), so it
## stands clear of its row.
const GUIDE_Y := 1.3
const RING_TUBE := 0.0016
const ROOT_TUBE := 0.0028
const LIT_TUBE := 0.0045
const RULE_PAST := 0.03
const LETTER_CAP := 0.017
const LETTER_OFF := 0.022
const LETTER_LEAST := 0.45
const LETTER_AIR := 1.6
const LIT_SCALE := 1.7
const LIT_LIFT := 1.5
## Half the height of the band about the rule that a desk's cursor plays in (Field): the rule is
## what it aims along, and a band no taller than the letters' leaves what stands beyond, over and
## under it (the booth's mic, from the seat), to be clicked through the air round the rod.
const DESK_BAND := 0.1

## The SCALE switch.
enum Snap {FREE, SCALE, CHORD}
const SNAP_WORDS := ["FREE", "SCALE", "CHORD"]
## Its key on the cabinet's front: its size and its middle in its frame.
const KEY := Vector2(0.16, 0.07)
const KEY_AT := Vector3(-0.08, 0.89, CABINET.y + 0.002)
## The desk's volume: a wheel notch, and a fine one (Shift).
const WHEEL_STEP := 0.125
const WHEEL_FINE := 0.03125

## The plaque, hung under the cabinet's front: its top edge, how far forward, its lean, its width.
const PLAQUE_TOP := CABINET_LOW - 0.012
const PLAQUE_Z := CABINET.y + 0.01
const PLAQUE_LEAN := 0.18
const PLAQUE_WIDE := 0.44
## The station's frame (Stations.ALL): the rod's tip, and its plaque's foot, opened.
const FRAME_TOP := Vector3(ROD.x, ROD_TOP, ROD.y)
const FRAME_FOOT := Vector3(0, 0.5, 0.14)
## What a player at it looks at: the middle of the field over the cabinet.
const LOOK := Vector3(0.0, 1.2, 0.0)

## Where its notes are played: this player's keys. Session.guest_midi unless told otherwise.
var keys: GuestMidi = null
## () -> Array of {at: Vector3 (global), by: Object (the Interactor or HandGestures it is)}: this
## player's hands now. Not set, every local tracked bare hand's palm and every tracked controller
## (`local_hands`).
var hands: Callable = Callable()
## () -> float: the song position its notes are snapped at. Not set, the keys' song where it is
## playing, else the playhead.
var clock: Callable = Callable()
## Its SCALE switch.
var snap := Snap.FREE:
	set(v):
		snap = posmod(v, Snap.size()) as Snap
		_show_key()
		_guide_for = PackedInt32Array([-1])
## The desk's volume, 0 to 1: the wheel over the field. Back to 0 as the cursor leaves it.
var desk_volume := 0.0

## The note held now, or -1; the pitch it plays now (MIDI, fractional: the glide and the wobble);
## the hand's own pitch, unsnapped; the expression now (0..127).
var note := -1
var pitch := NAN
var raw := NAN
var expression := 127
## How many times a note has been handed on to the next, for the suite.
var handed_on := 0
## The pitch hand's place in its frame while there is one (INF while not), and the volume hand's.
var pitch_at := Vector3.INF
var volume_at := Vector3.INF
## What reads the pitch hand's tilt and shake: its bend, added to the glide (`sending` off).
var wobble: Wobble = null
var field: Field
var key: ModeKey

## The glided pitch before the wobble, NAN while silent.
var _glided := NAN
## The last bend and expression sent, and the seconds since each.
var _bend_sent := 0
var _cc_sent := -1
var _bend_since := INF
var _cc_since := INF
## How long since the pitch hand was last seen (s), and what it was.
var _unseen := 0.0
var _pitch_by: Object = null
## The guide as built: the pitches its rings stand at.
var _guide_for := PackedInt32Array([-1])
var _rings: Node3D
var _letters: Array[Label3D] = []
var _ring_pitches := PackedInt32Array()
var _lit: MeshInstance3D
var _bar: MeshInstance3D
var _hand_ring: MeshInstance3D
var _ghost: MeshInstance3D
var _ring_paint: StandardMaterial3D
var _lit_paint: StandardMaterial3D


func _init() -> void:
	name = "Theremin"


func _ready() -> void:
	if keys == null:
		keys = Session.guest_midi
	wobble = Wobble.new(keys, [SOURCE])
	wobble.sending = false
	if ResourceLoader.exists(MODEL):
		var model := (load(MODEL) as PackedScene).instantiate() as Node3D
		add_child(model)
		_dress(model)
	field = Field.new()
	field.name = "Field"
	field.theremin = self
	var left := ROD.x - (FAR * 0.5 - 0.05)
	var right := ROD.x + FAR + FIELD_OUT
	field.position = Vector3((left + right) * 0.5, GUIDE_Y, ROD.y)
	field.size = Vector3(right - left, DESK_BAND * 2.0, 0.02)
	add_child(field)
	key = ModeKey.new()
	key.name = "ScaleKey"
	key.theremin = self
	key.position = KEY_AT
	add_child(key)
	_show_key()
	var plaque := Stations.plaque(STATION, PLAQUE_WIDE)
	var top := float(plaque.get_meta(&"plaque_tall", 0.2)) * 0.5
	var lean := Basis(Vector3.RIGHT, -PLAQUE_LEAN)
	var edge := Vector3(0, PLAQUE_TOP, PLAQUE_Z)
	plaque.transform = Transform3D(lean, edge - lean * Vector3(0, top, 0))
	add_child(plaque)
	_build_guide_parts()


func _dress(model: Node3D) -> void:
	var swap := {
		"stand": _paint(Color(0.07, 0.065, 0.06), 0.45),
		"walnut": _paint(Color(0.3, 0.17, 0.09), 0.42),
		"brass": Materials.brushed_metal(),
		"rubber": _paint(Color(0.03, 0.03, 0.03), 0.8),
		"chrome": _paint(Color(0.86, 0.87, 0.9), 0.14, 1.0),
	}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])


static func _paint(colour: Color, roughness: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = roughness
	m.metallic = metal
	return m


## Its footprint for the walker, at `at` (Venue.theremin_spot), as {c, h, a, top}.
static func solid(at: Transform3D) -> Dictionary:
	var middle := at * Vector3(0, 0, FOOT_Z)
	return {"c": Vector2(middle.x, middle.z), "h": FOOT, "a": at.basis.get_euler().y, "top": TOP}


# --- the law ------------------------------------------------------------------------------------

## The pitch a hand `distance` metres from the rod's axis plays (MIDI, fractional): TOP_PITCH at
## NEAR down to BOTTOM_PITCH at FAR, log in distance; held at the nearer end past either.
static func pitch_for(distance: float) -> float:
	var d := clampf(distance, NEAR, FAR)
	return TOP_PITCH - (TOP_PITCH - BOTTOM_PITCH) * log(d / NEAR) / log(FAR / NEAR)


## How far from the rod's axis pitch `p` is played (m): `pitch_for` turned round.
static func distance_for(p: float) -> float:
	var t := clampf((TOP_PITCH - p) / float(TOP_PITCH - BOTTOM_PITCH), 0.0, 1.0)
	return NEAR * pow(FAR / NEAR, t)


## The expression a volume hand `height` metres over the loop gives (CC 11, 0..127): silent resting
## on it (LOOP_REST or less), full VOLUME_SPAN above that.
static func expression_for(height: float) -> int:
	return clampi(roundi(clampf((height - LOOP_REST) / VOLUME_SPAN, 0.0, 1.0) * 127.0), 0, 127)


## Where a hand's raw pitch `p` is snapped to by `mode` in harmony `h`: itself (FREE), the nearest
## scale tone (SCALE, Harmony.snap) or the nearest chord tone (CHORD), kept inside the range.
static func target_for(p: float, h: Harmony, mode: int) -> float:
	match mode:
		Snap.SCALE:
			return float(clampi(h.snap(roundi(p)), BOTTOM_PITCH, TOP_PITCH))
		Snap.CHORD:
			if h.chord.is_empty():
				return float(h.snap(roundi(p)))
			var best := roundi(p)
			var gap := INF
			for n in range(floori(p) - 7, ceili(p) + 8):
				if h.chord.has(posmod(n, 12)) and n >= BOTTOM_PITCH and n <= TOP_PITCH and absf(n - p) < gap:
					gap = absf(n - p)
					best = n
			return float(best)
	return p


## The pitches the guide rings stand at for `mode` in harmony `h`, low to high, inside the range:
## the chord's tones in CHORD, the scale's otherwise (a free theremin is still guided to the key).
static func guide_pitches(h: Harmony, mode: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var tones := h.chord if mode == Snap.CHORD and not h.chord.is_empty() else h.scale
	for p in range(BOTTOM_PITCH, TOP_PITCH + 1):
		if tones.has(posmod(p, 12)):
			out.append(p)
	return out


## A guide ring's letter: its note, with its octave on the key's tonic (and the lowest), so the rule
## reads `C3 D E F G A B C4 ...` and stays short where the rings crowd near the rod.
static func letter_for(p: int, h: Harmony, first: bool) -> String:
	return h.note_name(p, first or posmod(p, 12) == h.root)


# --- what it plays in ---------------------------------------------------------------------------

## The song position its notes are snapped at now.
func now() -> float:
	if clock.is_valid():
		return float(clock.call())
	var song := keys.song() if keys != null and is_instance_valid(keys) else -1.0
	if song >= 0.0:
		return song
	return DAW.state.position_seconds if DAW.state != null else 0.0


## The harmony it plays in now: this player's (their chord hand's chord in the song's key).
func harmony_now() -> Harmony:
	return ChordHand.at(now())


# --- the hands ----------------------------------------------------------------------------------

## Every hand of this player's in `tree`: each tracked bare hand's palm, seen with confidence, and
## each tracked controller, as {at, by}.
static func local_hands(tree: SceneTree) -> Array:
	var out: Array = []
	if tree == null:
		return out
	for node in tree.get_nodes_in_group(HandGestures.GROUP):
		var g := node as HandGestures
		if g != null and g.tracked and g.confident and g.joints.size() > HandPose.PALM:
			out.append({"at": g.palm(), "by": g})
	for node in tree.get_nodes_in_group(Interactor.GROUP):
		var hand := node as XRInteractor
		if hand == null or hand.bare_hand():
			continue
		var c := hand.controller
		if c != null and c.is_inside_tree() and Strike.controller_sure(c):
			out.append({"at": c.global_position, "by": hand})
	return out


## A hand at `p` (its frame): whether it is over the loop, and how far from the loop's middle.
static func over_loop(p: Vector3) -> bool:
	return Vector2(p.x - LOOP.x, p.z - LOOP.z).length() <= LOOP_REACH and p.y >= LOOP.y - LOOP_UNDER \
			and p.y <= LOOP.y + LOOP_REST + VOLUME_SPAN + 0.2


## A hand at `p` (its frame): how far from the rod's axis across the floor.
static func from_rod(p: Vector3) -> float:
	return Vector2(p.x - ROD.x, p.z - ROD.y).length()


## A hand at `p` (its frame): whether it is in the pitch field.
static func in_field(p: Vector3) -> bool:
	return from_rod(p) <= FAR + FIELD_OUT and p.y >= FIELD_LOW and p.y <= FIELD_HIGH


## The hands now, sorted to their jobs: [pitch {at (its frame), by} or {}, volume {at, by} or {}].
func sort_hands(readings: Array) -> Array:
	var volume := {}
	var best := INF
	for r: Dictionary in readings:
		var p := to_local(r["at"] as Vector3)
		if over_loop(p):
			var d := Vector2(p.x - LOOP.x, p.z - LOOP.z).length()
			if d < best:
				best = d
				volume = {"at": p, "by": r["by"]}
	var aim := {}
	best = INF
	for r: Dictionary in readings:
		if not volume.is_empty() and r["by"] == volume["by"]:
			continue
		var p := to_local(r["at"] as Vector3)
		if in_field(p) and from_rod(p) < best:
			best = from_rod(p)
			aim = {"at": p, "by": r["by"]}
	return [aim, volume]


func _physics_process(delta: float) -> void:
	step(delta)


## One physics frame, `delta` seconds on: the hands read and sorted, and its note started, moved,
## handed on or let go.
func step(delta: float) -> void:
	var readings: Array = hands.call() if hands.is_valid() else local_hands(get_tree() if is_inside_tree() else null)
	var sorted := sort_hands(readings)
	var aim: Dictionary = sorted[0]
	var volume: Dictionary = sorted[1]
	var by: Object = null
	var cc := 127
	pitch_at = Vector3.INF
	volume_at = Vector3.INF
	if not aim.is_empty():
		pitch_at = aim["at"]
		by = aim["by"]
	elif field != null and field.mouse() != null:
		# The desk: the cursor in the field is the pitch hand, the wheel (or the button) the volume.
		var m := field.mouse()
		pitch_at = to_local(field.point_of(m))
		by = m
		cc = roundi(clampf(desk_volume if desk_volume > 0.0 or field.held_by != m else 1.0, 0.0, 1.0) * 127.0)
	if not volume.is_empty():
		volume_at = volume["at"]
		cc = expression_for((volume["at"] as Vector3).y - LOOP.y)
	if field != null and field.mouse() == null:
		desk_volume = 0.0
	expression = cc
	if by == null:
		_unseen += delta
		if note >= 0 and _unseen < LOST and _pitch_by != null and is_instance_valid(_pitch_by) \
				and not _pitch_by is MouseInteractor:
			# A hand that dropped out of tracking for a moment holds its note where it was; a cursor
			# that left the field meant to.
			_hold(delta)
			return
		raw = NAN
		silence()
		return
	_unseen = 0.0
	_pitch_by = by
	raw = pitch_for(from_rod(pitch_at))
	if note < 0 and cc < OPENS or note >= 0 and cc <= 0:
		silence()
		return
	_sound(raw, cc, by, delta)


## Its note on, moved or handed on for a hand whose raw pitch is `p`, at expression `cc`, `by` the
## hand that bends it.
func _sound(p: float, cc: int, by: Object, delta: float) -> void:
	if keys == null or not is_instance_valid(keys):
		return
	var h := harmony_now()
	var aim := target_for(p, h, snap)
	if is_nan(_glided) or snap == Snap.FREE:
		_glided = aim
	else:
		_glided += (aim - _glided) * (1.0 - exp(-maxf(delta, 0.0) / GLIDE))
	var wob := 0.0
	var mouse := by as MouseInteractor
	wobble.keys = keys
	wobble.hand = by
	wobble.axis = 1 if mouse != null else 0
	if note >= 0:
		wobble.step(delta)
		if not wobble.engaged():
			wob = 0.0
		elif mouse != null:
			# The cursor's travel across the rule is the pitch, so it does not also bend: its wiggle
			# up and down wobbles (but not while Alt is the wheel), and Alt's wheel bends.
			wob = clampf((0.0 if mouse.alt_down() else wobble.vibrato) + mouse.bend_wheel(),
					-Wobble.BEND_MOST, Wobble.BEND_MOST)
		else:
			wob = wobble.semitones
	pitch = clampf(_glided + wob, BOTTOM_PITCH - Wobble.BEND_MOST, TOP_PITCH + Wobble.BEND_MOST)
	_bend_since += delta
	_cc_since += delta
	if note < 0:
		# Nothing down, so the wheel is anyone's: its bend and expression first, then the note, so it
		# sounds where it should from its first moment.
		var n := _note_for(aim, h)
		_send_cc(cc, true)
		_send_bend(pitch - n, true)
		note = n
		keys.note_on(n, VELOCITY, 0, 0.0, false, SOURCE)
		return
	if absf(pitch - note) > Wobble.BEND_MOST:
		# Past the bend's edge: the next note on, bent to where the hand is, then this one off. The
		# new note is down before the old lets go, so there is no gap, and the wheel never rests.
		var n := _note_for(aim, h)
		var was := note
		note = n
		keys.note_on(n, VELOCITY, 0, 0.0, false, SOURCE)
		_send_bend(pitch - n, true)
		keys.note_off(was, 0, 0.0, false, SOURCE)
		handed_on += 1
	else:
		_send_bend(pitch - note)
	_send_cc(cc)


## The note to hold for the pitch now (`pitch`), gliding to `aim` in harmony `h`: the nearest,
## but snapped, of the tones it snaps to inside the bend the one nearest where it glides to, so a
## snapped take is the scale's (or the chord's) notes bent onto the glide, and not the notes
## between that the glide passes. With none inside the bend (a chord's wide gap), the nearest.
func _note_for(aim: float, h: Harmony) -> int:
	if snap == Snap.FREE:
		return roundi(pitch)
	var tones := guide_pitches(h, snap)
	var best := roundi(pitch)
	var gap := INF
	for n in range(ceili(pitch - Wobble.BEND_MOST), floori(pitch + Wobble.BEND_MOST) + 1):
		if tones.has(n) and absf(n - aim) < gap:
			gap = absf(n - aim)
			best = n
	return best


## The pitch hand out of sight for a moment: the note held where it was.
func _hold(delta: float) -> void:
	_bend_since += delta
	_cc_since += delta


func _send_bend(st: float, now_ := false) -> void:
	var value := Wobble.value_of(st)
	if not now_ and (value == _bend_sent or _bend_since < 1.0 / SENDS_A_SECOND - SEND_SLACK):
		return
	_bend_sent = value
	_bend_since = 0.0
	keys.control(DawKitClip.PITCH_BEND, value, SOURCE)


func _send_cc(cc: int, now_ := false) -> void:
	if not now_ and (cc == _cc_sent or _cc_since < 1.0 / SENDS_A_SECOND - SEND_SLACK):
		return
	_cc_sent = cc
	_cc_since = 0.0
	keys.control(11, cc, SOURCE)


## Its note let go, now: the keys rest the wheel and expression at the player's last note-off.
func silence() -> void:
	if note >= 0 and keys != null and is_instance_valid(keys):
		keys.note_off(note, 0, 0.0, false, SOURCE)
	note = -1
	pitch = NAN
	_glided = NAN
	_bend_sent = 0
	_cc_sent = -1
	_bend_since = INF
	_cc_since = INF


## Whether it sounds now.
func sounding() -> bool:
	return note >= 0


func _exit_tree() -> void:
	silence()


# --- the guide ----------------------------------------------------------------------------------

func _build_guide_parts() -> void:
	_ring_paint = StandardMaterial3D.new()
	_ring_paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_paint.albedo_color = Color(0.95, 0.82, 0.5, 0.42)
	_ring_paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_lit_paint = StandardMaterial3D.new()
	_lit_paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lit_paint.albedo_color = Color(1.0, 0.97, 0.86)
	_rings = Node3D.new()
	_rings.name = "Guide"
	add_child(_rings)
	# The rule the rings are lettered on, out from the rod at GUIDE_Y.
	var rule := MeshInstance3D.new()
	rule.name = "Rule"
	var bar := BoxMesh.new()
	bar.size = Vector3(FAR + RULE_PAST - NEAR + 0.02, 0.003, 0.003)
	rule.mesh = bar
	rule.material_override = _ring_paint
	rule.position = Vector3(ROD.x + (NEAR - 0.02 + FAR + RULE_PAST) * 0.5, GUIDE_Y, ROD.y)
	rule.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rule)
	_lit = _torus("Lit", 0.1, LIT_TUBE, _lit_paint)
	_lit.visible = false
	add_child(_lit)
	_hand_ring = _torus("HandRing", 0.1, RING_TUBE * 1.5, _ring_paint)
	_hand_ring.visible = false
	add_child(_hand_ring)
	_bar = MeshInstance3D.new()
	_bar.name = "OffBar"
	var off := BoxMesh.new()
	off.size = Vector3(1.0, 0.008, 0.008)
	_bar.mesh = off
	_bar.material_override = _lit_paint
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar.visible = false
	add_child(_bar)
	# Where the desk's volume stands over the loop: a disc, a ghost of the volume hand.
	_ghost = MeshInstance3D.new()
	_ghost.name = "VolumeGhost"
	var disc := CylinderMesh.new()
	disc.top_radius = LOOP_RADIUS * 0.8
	disc.bottom_radius = LOOP_RADIUS * 0.8
	disc.height = 0.004
	_ghost.mesh = disc
	_ghost.material_override = _ring_paint
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)


static func _torus(called: String, radius: float, tube: float, paint: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = called
	var t := TorusMesh.new()
	t.inner_radius = maxf(radius - tube, 0.0005)
	t.outer_radius = radius + tube
	t.rings = 64
	t.ring_segments = 6
	m.mesh = t
	m.material_override = paint
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


## The rings for `h` and the switch, built again only when their pitches change.
func _show_guide(h: Harmony) -> void:
	var want := guide_pitches(h, snap)
	if want == _guide_for and _letters.size() == want.size():
		return
	_guide_for = want
	_ring_pitches = want
	for c in _rings.get_children():
		# Out of the guide now, so the new rings take their names (Ring69) while the old wait to go.
		_rings.remove_child(c)
		c.queue_free()
	_letters.clear()
	for i in want.size():
		var p := want[i]
		var r := distance_for(p)
		var ring := _torus("Ring%d" % p, r, ROOT_TUBE if posmod(p, 12) == h.root else RING_TUBE, _ring_paint)
		ring.position = Vector3(ROD.x, GUIDE_Y, ROD.y)
		_rings.add_child(ring)
		var l := Label3D.new()
		l.name = "Letter%d" % p
		l.pixel_size = 0.0002
		l.font_size = roundi(LETTER_CAP / 0.7 / l.pixel_size)
		l.outline_size = 6
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.modulate = Color(0.95, 0.88, 0.7)
		# Lettered and sized as ever, never shown: notes floating round the rod were too much of the
		# room (2026-10-29: "i don't like the floating text"). The field's card says the lit one.
		l.visible = false
		l.text = letter_for(p, h, i == 0)
		# Alternately over and under the rule, so the crowded top end's letters do not overlap.
		l.position = Vector3(ROD.x + r, GUIDE_Y + (LETTER_OFF if i % 2 == 0 else -LETTER_OFF), ROD.y)
		Lettering.range_to_legibility(l)
		_rings.add_child(l)
		_letters.append(l)
	_size_letters(want)


## Each guide letter's size, from the far end in: as large as the room to the last letter kept on
## its side of the rule lets it be with LETTER_AIR between, and left off where that would be under
## LETTER_LEAST (shown again while it is lit, when it stands out of its row). So the letters
## crowding at the rod never run together.
func _size_letters(want: PackedInt32Array) -> void:
	var widths: Array[float] = []
	for l in _letters:
		var f := l.font if l.font != null else Lettering.face()
		widths.append(f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x * l.pixel_size
				if f != null else LETTER_CAP * l.text.length())
	var kept: Array[int] = [-1, -1]
	for i in _letters.size():
		var k := kept[i % 2]
		var size := 1.0
		if k >= 0:
			var gap := absf(distance_for(want[i]) - distance_for(want[k]))
			var room := gap / LETTER_AIR - widths[k] * float(_letters[k].get_meta(&"size")) * 0.5
			size = clampf(room / maxf(widths[i] * 0.5, 0.001), 0.0, 1.0)
		if size < LETTER_LEAST:
			size = 0.0
		else:
			kept[i % 2] = i
		_letters[i].set_meta(&"size", size)
		_letters[i].set_meta(&"y", _letters[i].position.y)
		_letters[i].scale = Vector3.ONE * maxf(size, 0.01)
		_letters[i].visible = false


## The guide ring nearest raw pitch `p` (an index into the rings), -1 with none.
func nearest_ring(p: float) -> int:
	var best := -1
	var gap := INF
	for i in _ring_pitches.size():
		if absf(_ring_pitches[i] - p) < gap:
			gap = absf(_ring_pitches[i] - p)
			best = i
	return best


## The lit ring's pitch now, -1 with no pitch hand.
func lit_pitch() -> int:
	if not pitch_at.is_finite() or is_nan(raw):
		return -1
	_show_guide(harmony_now())
	var i := nearest_ring(raw)
	return _ring_pitches[i] if i >= 0 else -1


## How far off the lit ring the pitch hand is, in cents (sharp positive); 0 with none.
func cents_off() -> int:
	var lit := lit_pitch()
	return 0 if lit < 0 or is_nan(raw) else roundi((raw - lit) * 100.0)


## The lit ring's letter as it reads now, and every letter: for the suite and the card.
func letters() -> PackedStringArray:
	var out := PackedStringArray()
	for l in _letters:
		out.append(l.text)
	return out


## How long the bar from the lit ring to the hand is now (m), 0 while it is not shown.
func bar_length() -> float:
	return _bar.basis.get_scale().x if _bar.visible else 0.0


func _process(_delta: float) -> void:
	var h := harmony_now()
	_show_guide(h)
	var lit := -1
	if pitch_at.is_finite() and not is_nan(raw):
		lit = nearest_ring(raw)
	for i in _letters.size():
		var on := i == lit
		var l := _letters[i]
		var size := float(l.get_meta(&"size", 1.0))
		var y := float(l.get_meta(&"y", l.position.y))
		l.scale = Vector3.ONE * (LIT_SCALE if on else maxf(size, 0.01))
		l.visible = false
		# The lit letter a row further out from the rule, larger, so it covers none of its row.
		l.position.y = y + signf(y - GUIDE_Y) * LETTER_CAP * LIT_LIFT if on else y
		l.modulate = Color(1.0, 1.0, 0.92) if on else Color(0.95, 0.88, 0.7)
	_lit.visible = lit >= 0
	_hand_ring.visible = lit >= 0
	_bar.visible = false
	if lit >= 0:
		var r := distance_for(_ring_pitches[lit])
		var y := clampf(pitch_at.y, FIELD_LOW, FIELD_HIGH)
		_set_torus(_lit, r, LIT_TUBE)
		_lit.position = Vector3(ROD.x, y, ROD.y)
		var hand_r := clampf(from_rod(pitch_at), NEAR, FAR)
		_set_torus(_hand_ring, hand_r, RING_TUBE * 1.5)
		_hand_ring.position = Vector3(ROD.x, y, ROD.y)
		# The bar: from the lit ring out (or in) to the hand, on the hand's side of the rod.
		var way := Vector2(pitch_at.x - ROD.x, pitch_at.z - ROD.y)
		way = way.normalized() if way.length() > 0.001 else Vector2.RIGHT
		var span := hand_r - r
		if absf(span) > 0.002:
			var mid := (r + hand_r) * 0.5
			_bar.visible = true
			_bar.transform = Transform3D(Basis(Vector3.UP, -atan2(way.y, way.x)) * Basis.from_scale(Vector3(absf(span), 1, 1)),
					Vector3(ROD.x + way.x * mid, y, ROD.y + way.y * mid))
	var mouse := field.mouse() if field != null else null
	_ghost.visible = mouse != null
	if mouse != null:
		_ghost.position = LOOP + Vector3(0, LOOP_REST + desk_volume * VOLUME_SPAN, 0)


static func _set_torus(m: MeshInstance3D, radius: float, tube: float) -> void:
	var t := m.mesh as TorusMesh
	var inner := maxf(radius - tube, 0.0005)
	if not is_equal_approx(t.inner_radius, inner):
		t.inner_radius = inner
		t.outer_radius = radius + tube


# --- saying what it is --------------------------------------------------------------------------

## The note the pitch hand is at, in words, with how far off the nearest ring: `A4 +18 cents`, `on A4`.
func pitch_words() -> String:
	var lit := lit_pitch()
	if lit < 0:
		return "no hand in its field"
	var h := harmony_now()
	var c := cents_off()
	if absf(c) < 5:
		return "on %s" % h.note_name(lit)
	return "%s %+d cents" % [h.note_name(lit), c]


## What the switch snaps to, in words.
func snap_words() -> String:
	var h := harmony_now()
	match snap:
		Snap.SCALE:
			return "snapped to %s's scale, gliding between" % (h.key_name if h.named else "C major (no key set)")
		Snap.CHORD:
			return "snapped to %s's tones, gliding between" % h.chord_name
	return "free: every pitch between, no snapping"


func _show_key() -> void:
	if key != null:
		key.show_legend("SNAP\n%s" % SNAP_WORDS[snap])


## The pitch field, for a desk: a band through the rod, out along the rule and DESK_BAND over and
## under it. The cursor resting in it is the pitch hand (across is pitch), the wheel over it the
## volume, the button held in it plays it full. A headset's hands play it by being there, not by
## this.
class Field extends ControlAffordance:
	var theremin: Theremin
	var size := Vector3.ONE
	## The mice resting on it now.
	var _mice: Array[MouseInteractor] = []
	## Where the holding mouse's drag is, in global space.
	var _drag := Vector3.INF

	func _ready() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = size
		shape.shape = b
		add_child(shape)

	## The mouse playing it now: the one holding it, else one resting on it; null for none.
	func mouse() -> MouseInteractor:
		if held_by is MouseInteractor and is_instance_valid(held_by):
			return held_by as MouseInteractor
		for m in _mice:
			if is_instance_valid(m) and m.hovered == self:
				return m
		return null

	## Where mouse `m` is pointing in the field (global): its drag while it holds it, else where its
	## ray rests on the band.
	func point_of(m: MouseInteractor) -> Vector3:
		if held_by == m and _drag.is_finite():
			return _drag
		return m.hover_point

	func hover_enter(by: Node) -> void:
		super(by)
		if by is MouseInteractor and not _mice.has(by):
			_mice.append(by as MouseInteractor)

	func hover_exit(by: Node) -> void:
		super(by)
		_mice.erase(by)

	func plays_under_cursor() -> bool:
		return true

	## Playing it is this player's own.
	func personal() -> bool:
		return true

	func grab_begin(by: Node, at: Vector3) -> void:
		# Only a desk's button: a headset's hands play it by being in it.
		if not by is MouseInteractor:
			return
		super(by, at)
		if held_by == by:
			_drag = at

	func grab_move(by: Node, at: Vector3) -> void:
		if held_by == by:
			_drag = at
		super(by, at)

	func grab_end(by: Node) -> void:
		_drag = Vector3.INF
		super(by)

	func _on_nudge(notches: int, fine: bool) -> bool:
		if theremin == null:
			return false
		theremin.desk_volume = clampf(theremin.desk_volume + notches * (WHEEL_FINE if fine else WHEEL_STEP), 0.0, 1.0)
		return true

	func _default_title() -> String:
		if theremin == null or theremin.lit_pitch() < 0:
			return "THEREMIN"
		return "THEREMIN  %s" % theremin.harmony_now().note_name(theremin.lit_pitch())

	func _default_readout() -> String:
		if theremin == null:
			return ""
		var vol := "volume %d%%" % roundi(theremin.expression / 1.27) if theremin.sounding() \
				else "volume %d%% (wheel up to play)" % roundi(theremin.desk_volume * 100.0)
		return "%s · %s · %s" % [theremin.pitch_words(), vol, theremin.snap_words()]

	func hint() -> String:
		if InstrumentItem.hands_hint:
			return "your pitch hand near the rod: nearer is higher, the lit ring is the note\nthe other hand over the loop is the volume, silent down on it · tilt to bend, shake to wobble"
		return "across is pitch along the lettered rule, nearer the rod higher · the wheel is volume, down to silent\nhold the button to play it full · wiggle up and down to wobble · Alt + mouse up or down bends"


## The SCALE switch on the cabinet's front, lettered SNAP over what it snaps to: pressed, FREE,
## SCALE and CHORD in turn; the wheel (or a stick) either way.
class ModeKey extends ControlAffordance:
	var theremin: Theremin
	var legend: Label3D

	func _init() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(KEY.x, KEY.y, 0.02)
		shape.shape = b
		add_child(shape)
		var face := MeshInstance3D.new()
		face.name = "Face"
		var slab := BoxMesh.new()
		slab.size = Vector3(KEY.x - 0.008, KEY.y - 0.008, 0.006)
		face.mesh = slab
		face.position = Vector3(0, 0, 0.001)
		var cap := StandardMaterial3D.new()
		cap.albedo_color = Color(0.12, 0.08, 0.05)
		cap.roughness = 0.55
		face.material_override = cap
		add_child(face)
		legend = Label3D.new()
		legend.name = "Legend"
		legend.pixel_size = 0.0002
		legend.font_size = 78
		legend.outline_size = 0
		legend.modulate = Color(0.96, 0.9, 0.76)
		legend.shaded = false
		legend.double_sided = false
		legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		legend.position = Vector3(0, 0, 0.0045)
		Lettering.range_to_legibility(legend)
		add_child(legend)

	func show_legend(text: String) -> void:
		legend.text = text
		Lettering.fit(legend, KEY.x - 0.014, 78, 40)

	func personal() -> bool:
		return true

	func dwell_activates() -> bool:
		return true

	func _default_title() -> String:
		return "THEREMIN  SNAP  %s" % SNAP_WORDS[theremin.snap] if theremin != null else "THEREMIN  SNAP"

	func _default_readout() -> String:
		return theremin.snap_words() if theremin != null else ""

	func hint() -> String:
		var either := "the stick" if InstrumentItem.hands_hint else "the wheel"
		return "press for FREE, SCALE or CHORD in turn · %s steps either way" % either

	func grab_begin(by: Node, at: Vector3) -> void:
		super(by, at)
		if held_by == by and theremin != null:
			theremin.snap = theremin.snap + 1

	func _on_nudge(notches: int, _fine: bool) -> bool:
		if theremin == null:
			return false
		theremin.snap = theremin.snap + notches
		return true
