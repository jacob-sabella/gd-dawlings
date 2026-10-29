class_name ChordHand
extends Node

## Chord shapes on one hand (docs/spatial_loop.md part two, slice 32; idea #28): the chord hand
## holds up a number of fingers and that degree of the key is this player's chord, for everything
## they play, while the other hand strums. Paired with the harp, there are no wrong chords.
##
## One for this player (`mine`), made by the studio. The chord hand is the left, or the right for
## a left-handed player (Ergonomics.handedness): `hand`, its pinch ray, and `gestures`, its
## readings while it is a tracked bare hand.
##
## A bare hand's shape (`shape_of`) is held up with its palm toward the room, not the head, and its
## fingers pointing up (pitch over UP_PITCH of HandPose.TILT_MOST), which is what tells degree I
## from a point (a level index). The fingers held out (HandPose.extended) count the degree: one is
## I, two ii, three iii, four IV, and four with the thumb out as well V. The same with the palm
## turned up gives vi (one) and vii° (two). An open flat hand, or one lowered below the chest
## (CHEST_BELOW under the eyes), is no shape: the song's own chord. A fist is never one, since two
## fists are the way out (XRRig.escape_fist), and neither is a hand carrying something. A reading
## counts once it has held HOLD, so a hand passing through a shape does not flicker the chord.
##
## A controller has no fingers to hold up, so the chord hand's stick is a mode, as decided: a click
## of it turns the chord stick on and off (`stick_on`), and while on the stick toward one of seven
## directions (up is I, then clockwise) picks and latches a degree, so the chord holds as the stick
## springs back; XRInteractor.chord_stick takes the stick off nudging meanwhile. Off is the song's
## chord again.
##
## A desktop has the chord layer (`layer`, C): while it is on, 1 to 7 in whichever KeyCatcher has
## the keyboard pick the degree, Shift adds the seventh and 0 goes back to the song's chord
## (KeyCatcher.chord_keys). With no catcher focused, turning it on gives the fingertips' catcher
## the keys, so J K L ; play the fingertips and the mouse strums the harp; a click does not take
## the keys away while it is on (KeyCatcher.click_releases waits for it), and C or Esc does. A left
## Glove low on the left of the view holds up the chord's fingers, `IV · F` over it.
##
## Each degree is the key's chord there (`chord_for`, in Harmony.at's key at that moment), so a
## latched IV is F in C major and Dm in A minor, and follows the song into a new key. While a
## shape is held it is this player's chord (`at`), and only theirs: the harp's strings, letters and
## crown, the fingertips, the wheel's follow-ups and the bells they hold (InstrumentItem.harmony_at)
## all read it, on this machine. A note already ringing keeps its pitch, and the notes played go
## out as notes, with their pitches, as ever: nothing about a hand's shape crosses the wire, but
## down a jack.
##
## A bandmate's chord hand (part two, slice 33; idea #33): plugged into this player, `chord:P`
## sends the chord P's hand holds on each change (Jacks.send_chord), and it is taken here as a
## chord from them (`take`): while P holds it, it is this player's chord, so their harp, their
## fingertips and the bells they hold play P's chord, and the harp's crown says whose
## (`IV from ADA`, `crown_text`). This player's own shape wins over it while they hold one.
## Unplugged, or P gone, it is let go (`let_go`), and so is P opening their hand (quality 0).
## The latest taken wins while two bandmates send at once. What this player holds of their own,
## not a bandmate's, is what goes out of their own jack (`own_chord`), so two players plugged into
## each other never feed back.

## Emitted when the chord this player plays in changes: a shape, a key, the layer or the stick.
signal changed()

## How long a reading has to hold to count (s).
const HOLD := 0.12
## How far up the fingers have to point, of HandPose.TILT_MOST, for a shape held up to count.
const UP_PITCH := 0.6
## A hand whose palm is more than this under the eyes (m) is lowered: below the chest.
const CHEST_BELOW := 0.45
## How far the stick has to be pushed (of its travel) to pick a degree.
const STICK_PAST := 0.6
## How many degrees a key has.
const DEGREES := 7
## Over a tracked hand or a controller: how far above it its words ride (m).
const WORDS_ABOVE := 0.12
## A seventh chord's quality by its third, fifth and seventh over its root (semitones), as the
## modes' own tones make them.
const SEVENTHS := {"4 7 11": "maj7", "4 7 10": "7", "3 7 10": "m7", "3 6 10": "m7b5", "3 6 9": "dim7"}

## This player's, while one is in the tree: what `at` reads.
static var mine: ChordHand = null

## The chord hand's pinch ray, in a headset; null on a desktop.
var hand: XRInteractor = null
## Its readings while it is a tracked bare hand; null for none.
var gestures: HandGestures = null
## Where its person's eyes are, for `faces_head` and the chest: the rig's head. Null reads the
## hand's own `head_point`.
var head: Node3D = null
## On a desktop: the mouse, whose camera the chord glove rides, and the fingertips' keys, which
## the layer gives the keyboard to when nothing has it.
var mouse: MouseInteractor = null
var fingertip_keys: KeyCatcher = null

## The degree held, 0 (I) to 6 (vii°), or -1 for none: the song's chord.
var degree := -1
## Whether the chord is the degree's seventh (the desktop's Shift).
var seventh := false
## The desktop's chord layer, and the controller's chord stick.
var layer := false
var stick_on := false

## The reading being held, and for how long (s).
var _reading := -1
var _reading_for := 0.0
## The stick's click last frame, for its edge.
var _click_was := false
## Whether turning the layer on gave the fingertips' keys the keyboard, so turning it off takes
## it back; a catcher that had it already keeps it.
var _gave_keys := false
## What `changed` was last emitted for.
var _was := ""
## Bandmates' chords taken down a jack, the latest last: [source, from, root, quality] each, as
## Jack.Kind.CHORD sends them (Jack.chord_named).
var _theirs: Array = []
var _glove: Glove = null
var _words: Label3D = null


func _init() -> void:
	name = "ChordHand"


func _enter_tree() -> void:
	mine = self


func _exit_tree() -> void:
	if layer:
		set_layer(false)
	if mine == self:
		mine = null


func _physics_process(delta: float) -> void:
	step(delta)


# --- the chord ----------------------------------------------------------------------------------

## The harmony this player plays in at `seconds`: the song's, with the chord of the shape this
## player holds in its place (`mine`'s), or the song's own with none.
static func at(seconds: float) -> Harmony:
	if mine != null and is_instance_valid(mine):
		return mine.harmony_at(seconds)
	return Harmony.at(DAW.state, seconds)


## The song's harmony at `seconds` with this hand's chord in it, while it holds one; else with a
## bandmate's chord down a jack in it, while one comes (`take`).
func harmony_at(seconds: float) -> Harmony:
	var h := Harmony.at(DAW.state, seconds)
	if degree >= 0:
		return with_chord(h, chord_for(h, degree, seventh))
	var theirs := their_chord(h)
	return with_chord(h, theirs) if theirs != "" else h


## The chord this player's own hand holds at `seconds` (a shape, the stick, the layer), "" with
## none: what goes out of their chord jack. Never a bandmate's chord taken down one.
func own_chord(seconds: float) -> String:
	if degree < 0:
		return ""
	return chord_for(Harmony.at(DAW.state, seconds), degree, seventh)


# --- a bandmate's chord down a jack -------------------------------------------------------------

## `from`'s chord hand, down `source`'s jack into this player: `root` a pitch class and `quality`
## one more than its place in Harmony.QUALITIES, 0 for their hand let go (Jack.Kind.CHORD).
func take(source: StringName, from: int, root: int, quality: int) -> void:
	_theirs = _theirs.filter(func(t: Array) -> bool: return t[0] != source)
	if quality > 0 and quality <= Jack.quality_count() and root >= 0 and root <= 11:
		_theirs.append([source, from, root, quality])
	_tell()


## What came down `source`'s jack let go (unplugged, or its player gone), or with none named, all
## of it.
func let_go(source := &"") -> void:
	if _theirs.is_empty():
		return
	_theirs = _theirs.filter(func(t: Array) -> bool: return source != &"" and t[0] != source)
	_tell()


## The bandmate's chord this player plays in now, spelled as `key` writes its notes (`F`), or ""
## with none coming: the latest taken.
func their_chord(key: Harmony) -> String:
	if _theirs.is_empty():
		return ""
	var t: Array = _theirs[-1]
	return Jack.chord_named(int(t[2]), int(t[3]), key)


## The jacks a bandmate's chord has come down and not been let go, the latest last.
func taken_sources() -> Array[StringName]:
	var out: Array[StringName] = []
	for t in _theirs:
		out.append(StringName(t[0]))
	return out


## Who the bandmate's chord this player plays in comes from, or 0 for none.
func their_player() -> int:
	return int(_theirs[-1][1]) if not _theirs.is_empty() else 0


## Whether a bandmate's chord is what this player plays in now: one comes, and they hold none.
func plays_theirs() -> bool:
	return degree < 0 and not _theirs.is_empty()


## What the harp's crown says under a bandmate's chord: its numeral in `key` and whose it is,
## `IV from ADA` (the chord's own name where it is none of the key's: `F#7 from ADA`); "" while
## this player plays in no bandmate's chord.
func crown_text(key: Harmony) -> String:
	if not plays_theirs():
		return ""
	var chord := their_chord(key)
	return "%s from %s" % [numeral_named(key, chord), Session.name_of(their_player()).to_upper()]


## `chord` as a numeral of `key` (`IV`, `V7`), as a degree's shape would say it; its own name
## where it is none of the key's degrees.
static func numeral_named(key: Harmony, chord: String) -> String:
	var tones := Harmony.chord_tones(chord)
	if key.scale.size() >= DEGREES:
		for d in DEGREES:
			for with_seventh in [false, true]:
				if Harmony.chord_tones(chord_for(key, d, with_seventh)) == tones:
					return numeral_of(key, d, with_seventh)
	return chord


## Whether a shape (or a latched degree) is held now.
func holds() -> bool:
	return degree >= 0


## The chord on `d` (0 is I) of `key`'s scale, of the scale's own tones: its triad, or with
## `with_seventh` its seventh chord. Spelled as the key is: F in C major, Dm in A minor, Bdim.
static func chord_for(key: Harmony, d: int, with_seventh := false) -> String:
	var n := key.scale.size()
	if n < DEGREES or d < 0:
		return key.chord_name
	d = posmod(d, n)
	var pc := key.scale[d]
	var third := posmod(key.scale[(d + 2) % n] - pc, 12)
	var fifth := posmod(key.scale[(d + 4) % n] - pc, 12)
	var quality := "dim" if fifth == 6 else ("aug" if fifth == 8 else ("m" if third == 3 else ""))
	if with_seventh:
		var top := posmod(key.scale[(d + 6) % n] - pc, 12)
		quality = SEVENTHS.get("%d %d %d" % [third, fifth, top], quality)
	return key.note_name(pc, false) + quality


## A copy of `h` sounding `chord` instead of its own: its key and its span kept. Never `h`
## itself, which may be Harmony.NONE.
static func with_chord(h: Harmony, chord: String) -> Harmony:
	var out := Harmony.new()
	out.key_name = h.key_name
	out.root = h.root
	out.mode = h.mode
	out.scale = h.scale
	out.named = h.named
	out.bar = h.bar
	out.since = h.since
	out.until = h.until
	out.flats = h.flats
	out.text = h.text
	out.progression = h.progression
	var tones := Harmony.chord_tones(chord)
	if not tones.is_empty():
		out.chord = tones
		out.chord_name = chord
	else:
		out.chord = h.chord
		out.chord_name = h.chord_name
	return out


## The degree `d` of `key` as a numeral, with its seventh: `IV`, `vi`, `vii°`, `V7`.
static func numeral_of(key: Harmony, d: int, with_seventh := false) -> String:
	var said := key.numeral(chord_for(key, d))
	return said + ("7" if with_seventh else "")


## The chord held, in words, at the keys' clock now: `IV · F`; "" with none.
func words() -> String:
	if degree < 0:
		return ""
	var h := Harmony.at(DAW.state, _now())
	return "%s · %s" % [numeral_of(h, degree, seventh), chord_for(h, degree, seventh)]


## What the HUD's focus field says while the layer is on, or a shape is held: `CHORDS · IV F`, or
## `CHORDS` with the song's own chord; under a bandmate's chord down a jack, `CHORDS · IV F FROM
## ADA`. "" for none of them.
func hud_text() -> String:
	var h := Harmony.at(DAW.state, _now())
	if degree >= 0:
		return "CHORDS · %s %s" % [numeral_of(h, degree, seventh), chord_for(h, degree, seventh)]
	if plays_theirs():
		return "CHORDS · %s %s FROM %s" % [numeral_named(h, their_chord(h)), their_chord(h),
				Session.name_of(their_player()).to_upper()]
	return "CHORDS" if layer or stick_on else ""


## The song position to say the chord at: the keys' clock while the song plays, the playhead while
## it is stopped, as the harp reads it.
func now() -> float:
	return _now()


func _now() -> float:
	var keys := Session.guest_midi
	var song := keys.song() if keys != null else -1.0
	if song >= 0.0:
		return song
	return DAW.state.position_seconds if DAW.state != null else 0.0


## `d` (0..6, or -1 for the song's chord) held, with or without the seventh.
func pick(d: int, with_seventh := false) -> void:
	degree = d if d >= 0 and d < DEGREES else -1
	seventh = with_seventh and degree >= 0
	_tell()


func _tell() -> void:
	var now := "%d%s%s" % [degree, "7" if seventh else "", " layer" if layer else ""] + (" stick" if stick_on else "") \
			+ (" %s" % [_theirs[-1]] if not _theirs.is_empty() else "")
	if now != _was:
		_was = now
		changed.emit()


# --- a bare hand --------------------------------------------------------------------------------

## The degree a hand whose joints are `joints` (any one space, `side` -1 for a left hand) shows
## to eyes at `eyes`, 0 (I) to 6 (vii°), or -1 for none. Held up, palm toward the room and
## fingers up: the fingers held out count I to IV, and with the thumb out as well V. Palm up: one
## finger vi, two vii°. Lowered below the chest, facing the head, flat, a fist: none.
static func shape_of(joints: PackedVector3Array, side: int, eyes: Vector3) -> int:
	if not HandPose.whole(joints):
		return -1
	if joints[HandPose.PALM].y < eyes.y - CHEST_BELOW:
		return -1
	if HandPose.faces_head(joints, eyes, side):
		return -1
	var out := HandPose.extended(joints)
	var fingers := 0
	for bit in HandPose.FINGER_BITS:
		if out & bit:
			fingers += 1
	var count := fingers + (1 if fingers == HandPose.FINGER_BITS.size() and out & HandPose.THUMB else 0)
	if count == 0:
		return -1
	if HandPose.palm_up(joints, side):
		return [-1, 5, 6][count] if count <= 2 else -1
	if HandPose.tilt(joints, side).y <= UP_PITCH:
		return -1
	return count - 1


## One reading of the hand, `delta` seconds on: it counts once it has held HOLD.
func settle(reading: int, delta: float) -> void:
	if reading != _reading:
		_reading = reading
		_reading_for = delta
	else:
		_reading_for += delta
	if _reading_for >= HOLD - 0.0001 and degree != _reading:
		pick(_reading)


# --- a controller -------------------------------------------------------------------------------

## The degree the stick pushed to `at` picks (up is I, then clockwise), or -1 short of STICK_PAST.
static func stick_degree(at: Vector2) -> int:
	if at.length() < STICK_PAST:
		return -1
	var turned := atan2(at.x, at.y)
	return posmod(roundi(turned / (TAU / DEGREES)), DEGREES)


## One frame of the chord hand's stick: `click` down or not, the stick at `at`. A click's edge
## turns the chord stick on or off (off is the song's chord); while on, a push past STICK_PAST
## latches its degree, kept as the stick springs back.
func stick_step(click: bool, at: Vector2) -> void:
	if click and not _click_was:
		stick_on = not stick_on
		if not stick_on:
			degree = -1
			seventh = false
		_tell()
	_click_was = click
	if hand != null and is_instance_valid(hand):
		hand.chord_stick = stick_on
	if stick_on:
		var d := stick_degree(at)
		if d >= 0 and d != degree:
			pick(d)
	elif degree >= 0:
		# A shape a bare hand held, before the controller was picked up.
		pick(-1)


# --- a desktop ----------------------------------------------------------------------------------

## The chord layer on or off (C). On, with no catcher focused, the fingertips' keys take the
## keyboard; off, they give it back if the layer took it, and the song's chord is played again.
func set_layer(on: bool) -> void:
	if on == layer:
		return
	layer = on
	KeyCatcher.chord_keys = _chord_key if on else Callable()
	if on:
		if _focused_catcher() == null and fingertip_keys != null and fingertip_keys.is_inside_tree():
			_gave_keys = true
			fingertip_keys.set_active(true)
	else:
		degree = -1
		seventh = false
		if _gave_keys and fingertip_keys != null and is_instance_valid(fingertip_keys) and fingertip_keys.is_active():
			fingertip_keys.set_active(false)
		_gave_keys = false
	_tell()


## A key in the focused catcher while the layer is on: 1 to 7 pick the degree, Shift its seventh,
## 0 the song's chord, taken (true). P steps the chord hand's own jack (`chord:P`, part two, slice
## 33) on through each bandmate, as the wrist's CHORDS socket does in a headset; Shift+P is left
## to unplug what goes into this player, as ever. Esc turns the layer off and lets the catcher
## have it too, so it gives the keys back as it always does.
func _chord_key(physical: int, shift: bool, pressed: bool) -> bool:
	if physical == KEY_P and not shift:
		var jacks := Jacks.of(self)
		if jacks == null:
			return false
		if pressed:
			jacks.step_source(Jack.chord_source(Session.local_peer_id), 1)
		return true
	if physical == KEY_ESCAPE:
		if pressed:
			set_layer(false)
		return false
	if physical == KEY_0:
		if pressed:
			pick(-1)
		return true
	if physical >= KEY_1 and physical <= KEY_7:
		if pressed:
			pick(physical - KEY_1, shift)
		return true
	return false


## The catcher that has the keyboard now, if one does.
func _focused_catcher() -> KeyCatcher:
	var view := get_viewport() if is_inside_tree() else null
	return view.gui_get_focus_owner() as KeyCatcher if view != null else null


## The layer lives in a catcher: with none focused any more (T, the help card taking the keys), it
## is off.
func _keep_layer() -> void:
	if layer and is_inside_tree() and _focused_catcher() == null:
		set_layer(false)


# --- each frame ---------------------------------------------------------------------------------

## One frame, `delta` seconds on: the hand read (a tracked bare hand's shape, a controller's
## stick), and what shows the chord drawn.
func step(delta: float) -> void:
	_keep_layer()
	if hand != null and is_instance_valid(hand) and not layer:
		var tracked := gestures != null and is_instance_valid(gestures) and gestures.tracked
		if tracked:
			if stick_on:
				stick_on = false
				hand.chord_stick = false
			var empty := not is_instance_valid(hand.carrying) and hand.held == null
			settle(shape_of(gestures.joints, gestures.side, _eyes()) if empty else -1, delta)
		elif hand.controller != null and not hand.bare_hand():
			stick_step(hand.stick_clicked(), hand.stick())
		elif degree >= 0 and not stick_on:
			# A bare hand gone out of view: as if lowered.
			settle(-1, delta)
	_show_words()
	_show_glove()


func _eyes() -> Vector3:
	if head != null and is_instance_valid(head) and head.is_inside_tree():
		return head.global_position
	if gestures != null and gestures.head != null and is_instance_valid(gestures.head) and gestures.head.is_inside_tree():
		return gestures.head.global_position
	return hand.head_point() if hand != null else Vector3(0, 1.6, 0)


## Over the chord hand in a headset, its chord in words, and CHORDS while the stick picks them:
## a Label3D of its own riding above the palm or the controller, turned to the eyes.
func _show_words() -> void:
	var said := words()
	if stick_on:
		said = "CHORDS\n" + (said if said != "" else "stick toward a chord · click: the song's")
	var where := Vector3.INF
	if hand != null and is_instance_valid(hand):
		if gestures != null and is_instance_valid(gestures) and gestures.tracked:
			where = gestures.palm()
		elif hand.controller != null and is_instance_valid(hand.controller) and hand.controller.is_inside_tree():
			where = hand.controller.global_position
	if said == "" or where == Vector3.INF:
		if _words != null:
			_words.visible = false
		return
	if _words == null:
		_words = HandSkeleton.letter_label(56)
		_words.name = "ChordWords"
		_words.top_level = true
		add_child(_words)
	_words.visible = true
	_words.text = said
	_words.global_position = where + Vector3.UP * WORDS_ABOVE


## What the words over the chord hand say now, "" while hidden: for the suite.
func words_shown() -> String:
	return _words.text if _words != null and _words.visible and _words.is_inside_tree() else ""


## The desktop's left glove while the layer is on: the chord's fingers held up (palm up for vi and
## vii°), open and flat for the song's chord, its words over it.
func _show_glove() -> void:
	var cam := mouse.camera if mouse != null and is_instance_valid(mouse) else null
	if cam == null or not cam.is_inside_tree():
		return
	if _glove == null:
		if not layer:
			return
		_glove = Glove.new(-1.0)
		_glove.name = "ChordGlove"
		_glove.make_letters()
		add_child(_glove)
		for node in _glove.find_children("*", "VisualInstance3D", true, false):
			(node as VisualInstance3D).layers = Mirror.NOT_REFLECTED
			if node is GeometryInstance3D:
				(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glove.visible = layer
	if not layer:
		return
	_glove.target = mouse.chord_pose(degree)
	_glove.size = mouse.finger_glove_size()
	if degree < 0:
		_glove.pose = Glove.Pose.OPEN
		_glove.held_up = 0
	else:
		_glove.pose = Glove.Pose.SHAPE
		_glove.held_up = fingers_of(degree)
	var h := Harmony.at(DAW.state, _now())
	_glove.say(words() if degree >= 0 else "song's · %s" % (h.chord_name if h.named else "NO KEY SET"))


## The digits a shape of degree `d` holds out, as HandPose.extended's mask: I the index, on to IV
## all four fingers, V the thumb as well; vi the index and vii° two, palm up.
static func fingers_of(d: int) -> int:
	if d < 0:
		return 0
	var count := d + 1 if d < 5 else d - 4
	var out := 0
	for f in mini(count, HandPose.FINGER_BITS.size()):
		out |= HandPose.FINGER_BITS[f]
	if count >= 5:
		out |= HandPose.THUMB
	return out


## Whether the desktop's chord glove is drawn now, and what it says: for the suite and the shot.
func glove_shown() -> bool:
	return _glove != null and _glove.visible and _glove.is_inside_tree()


func glove() -> Glove:
	return _glove
