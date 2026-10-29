class_name LyricBoard
extends Node3D

## The song's lyrics at eye height in the vocal booth (docs/spatial_loop.md part two, slice 56):
## a board on a stand beyond the mic, facing whoever stands at it, that scrolls with the song.
##
## It shows three lines of the song's lyrics (MixState.lyrics, read by Lyrics): the last one sung,
## dim and small; the one being sung now, large, with a mark before it and a bar under it that fills
## as the song goes toward the next line; and the next. So which line is now is said three ways, its
## place, its size and its mark, never by its colour alone. When the line changes the three glide up
## a line, and at motion 0 (Ergonomics.motion_scale) they step, a line a step. With no lyrics it says
## how to add them.
##
## Lines with no time yet are timed by TAP: while the song plays, a press of the big TAP key (or of
## Enter at a desk, once the board has been clicked) stamps the next untimed line at the song
## position this player hears (GuestMidi.heard, so a guest's TAP lands where their ears put it), and
## the next line shown says TAP before it until it is timed. EDIT asks for a line to add at the end:
## the studio opens the typing pad for a headset and the session panel's LYRICS box at a desk
## (`edit_asked`).
##
## Every change is the whole text through DAW.set_lyrics (`write`), one undo step. A guest's goes to
## the host as an intent; meanwhile the board shows it as asked (`_predicted`), and a second TAP
## before the first comes back builds on it, so quick taps are never lost to the round trip.
##
## Its frame: +Z out of the board's face toward the singer, the origin on the floor under the middle
## of the board, its post rising there. Venue.lyrics_spot stands it IN_BOOTH, in line with the mic
## stand (ZoneKit.MIC_AT) on the far side of it from the singer, so the lines are over the mic as
## the singer looks out through the glass. The stand is the booth's: no trolley, the zone's solids
## carry its foot.

## A line was stamped by TAP: its index in Lyrics.lines, and the time it shows at.
signal tapped(line: int, seconds: float)
## EDIT was pressed: the studio asks for a line (TypingPad in a headset, the session panel at a desk).
signal edit_asked()
## Something to tell the player, as a toast: a refusal, or how to time the lines.
signal told(text: String)

const STATION := &"lyrics"
## The eye height the board is drawn for when nobody has said one: Ergonomics' default. The board's
## lines stand at the player's own (Ergonomics.current.eye_height), between EYE_LOWEST and EYE_HIGHEST.
const EYE := Ergonomics.DEFAULT_HEIGHT - Ergonomics.EYE_BELOW_CROWN
const EYE_LOWEST := 1.1
const EYE_HIGHEST := 1.8
## Where it stands in the booth's frame (the vocal zone's floor centre), its face toward -X: across
## the mic stand's foot from where the singer stands (ZoneKit.MIC_AT, its boom reaching back toward
## the middle), in line with it, clear of it and of the glass behind it.
const IN_BOOTH := Vector3(0.86, 0.0, ZoneKit.MIC_AT.z)
## How far in front of it the singer stands, at the mic.
const SEAT := 1.3
## The face of the board: wide along X, its middle over the eye, its foot just under it; and how thick
## it is. Seen from the mic, the mic's own body covers the view from about 3 degrees under the eye
## down, so nothing on the face is lower than that.
const PANEL := Vector2(0.84, 0.29)
const PANEL_UP := 0.075
const PANEL_DEPTH := 0.024
## The lines' column: from TEXT_LEFT across TEXT_WIDE, each PITCH under the one before, the one sung
## now LINES_UP over the eye (2.6 degrees from SEAT, at the eye as near as matters), the next under it
## still over the mic. Their letters' cap heights (m): 55 mm for the one sung, 2.4 degrees at SEAT.
const TEXT_LEFT := -0.36
const TEXT_WIDE := 0.54
const LINES_UP := 0.06
const PITCH := 0.09
const CAP_NOW := 0.055
const CAP_SIDE := 0.032
## The bar under the line sung now, this far under it, and the mark before it.
const BAR_DOWN := 0.045
const BAR_TALL := 0.007
const MARK := 0.03
## The keys, at the singer's right of the lines, by their middles over the eye: TAP big beside the
## line sung now, EDIT over it.
const TAP_AT := Vector2(0.31, 0.06)
const TAP_SIZE := Vector2(0.16, 0.11)
const EDIT_AT := Vector2(0.31, 0.17)
const EDIT_SIZE := Vector2(0.16, 0.05)
## The status row along the top of the face, over the last line, from the mark's place to EDIT.
const STATUS_UP := 0.2
const STATUS_WIDE := 0.6
const STATUS_CAP := 0.016
## The stand: a disc on the floor and a post up to the board.
const BASE := 0.12
const POST := 0.014
## The plaque, beside the face on the singer's right, its middle level with the face's and on the
## post's plane, held there by an arm off the post along its top: from the mic everything under the
## eye near the middle is behind the mic and its boom, so it is not under the board but beside it.
const PLAQUE := Vector3(PANEL.x * 0.5 + 0.03 + 0.2, EYE + PANEL_UP, -PANEL_DEPTH * 0.5 - POST)
const PLAQUE_WIDTH := 0.4
## The station row's frame: the board's top, and the plaque's foot opened (Stations.plaque_bottom).
const FRAME_TOP := Vector3(0, EYE + PANEL_UP + PANEL.y * 0.5, 0)
const FRAME_FOOT := Vector3(PLAQUE.x, PLAQUE.y - 0.26, PLAQUE.z)
## How long a line's glide up takes at full motion (s); slower as motion is turned down.
const GLIDE := 0.28
## How long a guest's asked-for lyrics are shown before the host's word is all that is believed (ms).
const PREDICT_MSEC := 3000
## Where the typing pad is put for a headset, in the board's frame: near the singer's right hand,
## tipped up toward them, under the boom.
const PAD_AT := Transform3D(Basis(Vector3.RIGHT, -0.6), Vector3(0.12, EYE - 0.36, SEAT - 0.36))

const INK := Color(0.95, 0.93, 0.86)
const DIM := Color(0.62, 0.62, 0.6)

## () -> Dictionary, GuestMidi.heard's shape: the song this player hears. Session.guest_midi's
## unless given (the suite, the probe).
var heard_source: Callable = Callable()
## (text: String) -> String: how the lyrics are written, answering why not or "". DAW.set_lyrics
## unless given.
var write: Callable = Callable()
## Whether Enter TAPs: on from a click on the board at a desk, off with Esc or another click.
var armed := false
## The eye height it is built for.
var eye := EYE

var tap_key: BoardKey
var edit_key: BoardKey
var face: Face
## The three lines, last, now and next, in `scroller`, which glides.
var scroller: Node3D
var last_line: Label3D
var now_line: Label3D
var next_line: Label3D
var mark: MeshInstance3D
var bar: MeshInstance3D
var bar_track: MeshInstance3D
## The row along the top: how many lines and how many to TAP, and ENTER TAPS while Enter does.
var status: Label3D

## What is shown now ({last, now, next, mark, through, tap_next, line}), as `display` made it.
var shown := {}
var _lyrics: Lyrics = Lyrics.new()
var _parsed_text := ""
var _parsed := false
var _predicted := ""
var _predicted_at := -1
var _glide := 0.0
## What the status row says was worked out for: the lyrics parsed and whether it was armed. It is
## worked out again only when either changes, not each frame.
var _status_of: Lyrics
var _status_armed := false


func _init() -> void:
	name = "LyricBoard"


func _ready() -> void:
	eye = clampf(Ergonomics.current.eye_height if Ergonomics.current != null else EYE, EYE_LOWEST, EYE_HIGHEST)
	_build_stand()
	_build_face()
	var plaque := Stations.plaque(STATION, PLAQUE_WIDTH)
	# With the face, at the eye it is built for.
	plaque.position = PLAQUE + Vector3(0, eye - EYE, 0)
	add_child(plaque)
	# Its arm off the post, along the plaque's top.
	var arm := MeshInstance3D.new()
	arm.name = "PlaqueArm"
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(PLAQUE.x - PLAQUE_WIDTH * 0.5 + POST * 2.0, 0.012, 0.012)
	arm.mesh = bar_mesh
	# Its top 3 mm under the plate's, so the two are not one face.
	arm.position = Vector3(bar_mesh.size.x * 0.5 - POST, plaque.position.y + float(plaque.get_meta(&"plaque_tall", 0.2)) * 0.5 - 0.009,
			PLAQUE.z - 0.012)
	arm.material_override = Materials.brushed_metal()
	add_child(arm)
	if DAW.state != null:
		DAW.lyrics_changed.connect(_on_lyrics_changed)
	_show(display(heard()))


func _on_lyrics_changed() -> void:
	if _predicted_at >= 0 and DAW.state != null and DAW.state.lyrics == _predicted:
		_predicted_at = -1


# --- what it reads -----------------------------------------------------------------------------

func heard() -> Dictionary:
	if heard_source.is_valid():
		return heard_source.call()
	if Session.guest_midi != null:
		return Session.guest_midi.heard()
	var s := DAW.state
	return {"seconds": s.position_seconds if s != null else 0.0, "playing": s != null and s.playing, "valid": s != null}


## The lyrics as this player should see them: what they asked for while the host has not answered
## (PREDICT_MSEC at most), else the song's.
func text() -> String:
	if _predicted_at >= 0 and Time.get_ticks_msec() - _predicted_at < PREDICT_MSEC:
		return _predicted
	_predicted_at = -1
	return DAW.state.lyrics if DAW.state != null else ""


## The lyrics parsed, kept until the text changes.
func lyrics() -> Lyrics:
	var now := text()
	if now != _parsed_text or not _parsed:
		_parsed = true
		_parsed_text = now
		_lyrics = Lyrics.parse(now)
	return _lyrics


## What the board shows at the song position `h` (heard's shape): {last, now, next: the three lines'
## words; mark: whether a line is being sung; through: how far through it (0..1, NAN with nothing
## timed after it); tap_next: whether the next is the one TAP times; line: the index sung, or -1;
## empty: no lyrics at all}.
func display(h: Dictionary) -> Dictionary:
	var lyr := lyrics()
	var out := {"last": "", "now": "", "next": "", "mark": false, "through": NAN, "tap_next": false, "line": -1,
			"empty": false}
	if lyr.is_empty():
		out["empty"] = true
		out["now"] = "No lyrics yet"
		out["next"] = "EDIT adds a line  ·  at a desk, M: LYRICS"
		return out
	var seconds := float(h.get("seconds", 0.0))
	var order := lyr.sequence()
	var line := lyr.at(seconds)
	var k := lyr.place(line)
	out["line"] = line
	if line >= 0:
		out["mark"] = true
		out["now"] = _words(lyr, line)
		out["through"] = lyr.through(line, seconds)
		if k > 0:
			out["last"] = _words(lyr, order[k - 1])
	else:
		# Before the first line: the song's intro.
		out["now"] = "♪"
	var after: int = order[k + 1] if k + 1 < order.size() else -1
	if after >= 0:
		out["tap_next"] = after == lyr.next_untimed()
		out["next"] = ("TAP ›  " if out["tap_next"] else "") + _words(lyr, after)
	return out


static func _words(lyr: Lyrics, i: int) -> String:
	var said := str(lyr.lines[i]["text"])
	return said if not said.is_empty() else "♪"


## A line about the lyrics for the status row and the face's card: how many lines and how many are
## left to tap, and how.
func status_words() -> String:
	var lyr := lyrics()
	if lyr.is_empty():
		return "a headset: EDIT types a line · a desk: the session panel's LYRICS"
	var lines := lyr.sequence().size()
	var left := lyr.untimed_count()
	if left == 0:
		return "%d line%s, all timed" % [lines, "" if lines == 1 else "s"]
	return "%d line%s · %d to TAP: play the song and TAP as each starts" % [lines, "" if lines == 1 else "s", left]


# --- what it does ------------------------------------------------------------------------------

## TAP: the next untimed line stamped at the song this player hears, as one write. "" when it was,
## else what was said instead (told too).
func tap() -> String:
	var h := heard()
	if not bool(h.get("playing", false)):
		return _say("TAP times a line while the song plays: play it, then TAP as each line starts.")
	var lyr := Lyrics.parse(text())
	if lyr.is_empty():
		return _say("There are no lyrics to time yet: EDIT adds a line, or at a desk the session panel's LYRICS.")
	var seconds := float(h.get("seconds", 0.0))
	var i := lyr.tap(seconds)
	if i < 0:
		return _say("Every line is timed. EDIT adds one; UNTIME in the session panel's LYRICS starts the tapping again.")
	var why := write_text(lyr.write())
	if not why.is_empty():
		return why
	tapped.emit(i, lyr.shown(i))
	return ""


## A line of words added at the end of the lyrics, untimed, as one write.
func add_line(words: String) -> String:
	var lyr := Lyrics.parse(text())
	lyr.add(words)
	return write_text(lyr.write())


## The lyrics made `lrc`: written (`write`), and shown so at once. "" when it was, else why not (told).
func write_text(lrc: String) -> String:
	var clean := Lyrics.clean(lrc)
	var why: String = write.call(clean) if write.is_valid() else DAW.set_lyrics(clean)
	if not why.is_empty():
		return _say(why)
	_predicted = clean
	_predicted_at = Time.get_ticks_msec()
	_show(display(heard()))
	return ""


func edit() -> void:
	edit_asked.emit()


## Enter TAPs from now (a click on the board at a desk), or no longer. A desk's only: in a headset
## there is no Enter to give it, so it is never armed there.
func arm(on: bool) -> void:
	if on and _in_headset():
		return
	armed = on
	if status != null:
		_show(display(heard()))
	if on:
		told.emit("The lyric board has Enter: press it as each line starts, the song playing. Esc, or another click on the board, lets it go.")


func _in_headset() -> bool:
	return is_inside_tree() and get_viewport() != null and get_viewport().use_xr


func _say(text: String) -> String:
	told.emit(text)
	return text


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or not armed:
		return
	if key.keycode == KEY_ESCAPE:
		# Enter is the room's again, and that is all Esc does: the studio's Esc (walking back to the
		# desk) never hears it.
		arm(false)
		get_viewport().set_input_as_handled()
	elif (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER) and not key.ctrl_pressed \
			and not key.meta_pressed and not Input.is_key_pressed(KEY_Z):
		# Z held makes Enter listen from where the mouse points (PointAndMark), not TAP.
		tap()
		get_viewport().set_input_as_handled()


# --- following the song ------------------------------------------------------------------------

func _process(delta: float) -> void:
	var was: int = int(shown.get("line", -1))
	var d := display(heard())
	if int(d["line"]) != was and was >= 0 and int(d["line"]) >= 0 and lyrics().place(int(d["line"])) \
			== lyrics().place(was) + 1:
		# One line on: the three glide up a line, or step at motion 0.
		_glide = -PITCH if _motion() > 0.0 else 0.0
	_glide = move_toward(_glide, 0.0, delta * PITCH / GLIDE * maxf(_motion(), 0.0001))
	_show(d)


static func _motion() -> float:
	return Ergonomics.current.motion_scale if Ergonomics.current != null else 1.0


func _show(d: Dictionary) -> void:
	shown = d
	if now_line == null:
		return
	_set_line(last_line, str(d["last"]), CAP_SIDE)
	_set_line(now_line, str(d["now"]), CAP_NOW)
	_set_line(next_line, str(d["next"]), CAP_SIDE)
	scroller.position.y = eye + LINES_UP + _glide
	# The next line comes in from under the board's edge as the three glide up.
	next_line.modulate.a = 1.0 - clampf(absf(_glide) / PITCH, 0.0, 1.0)
	mark.visible = bool(d["mark"])
	var through := float(d["through"])
	bar_track.visible = bool(d["mark"])
	bar.visible = bool(d["mark"]) and not is_nan(through) and through > 0.001
	if bar.visible:
		bar.scale.x = maxf(through, 0.001)
		bar.position.x = TEXT_LEFT + TEXT_WIDE * through * 0.5
	var lyr := lyrics()
	if lyr == _status_of and armed == _status_armed:
		return
	_status_of = lyr
	_status_armed = armed
	var said := ("ENTER TAPS  ·  Esc lets go  ·  " if armed else "") + status_words()
	if status.text != said:
		status.text = said
		Lettering.fit(status, STATUS_WIDE, roundi(STATUS_CAP / status.pixel_size), 40)


func _set_line(label: Label3D, words: String, cap: float) -> void:
	if label.text != words:
		label.text = words
		Lettering.fit(label, TEXT_WIDE, roundi(cap / label.pixel_size), roundi(cap * 0.5 / label.pixel_size))


# --- building it --------------------------------------------------------------------------------

func _build_stand() -> void:
	var metal := Materials.brushed_metal()
	var base := MeshInstance3D.new()
	base.name = "Base"
	var disc := CylinderMesh.new()
	disc.top_radius = BASE - 0.01
	disc.bottom_radius = BASE
	disc.height = 0.02
	base.mesh = disc
	base.position.y = 0.01
	base.material_override = metal
	add_child(base)
	var post := MeshInstance3D.new()
	post.name = "Post"
	var rod := CylinderMesh.new()
	rod.top_radius = POST
	rod.bottom_radius = POST + 0.002
	rod.height = eye + PANEL_UP - PANEL.y * 0.5 - 0.02 + 0.03
	post.mesh = rod
	post.position.y = 0.02 + rod.height * 0.5
	post.position.z = -PANEL_DEPTH * 0.5 - POST
	post.material_override = metal
	add_child(post)


func _build_face() -> void:
	var panel := MeshInstance3D.new()
	panel.name = "Panel"
	var box := BoxMesh.new()
	box.size = Vector3(PANEL.x, PANEL.y, PANEL_DEPTH)
	panel.mesh = box
	panel.position = Vector3(0, eye + PANEL_UP, 0)
	var ink := StandardMaterial3D.new()
	ink.albedo_color = Color(0.045, 0.045, 0.05)
	ink.roughness = 0.7
	panel.material_override = ink
	add_child(panel)
	var front := PANEL_DEPTH * 0.5 + 0.001

	face = Face.new()
	face.board = self
	face.name = "Face"
	face.size = Vector2(TEXT_WIDE + 0.08, PANEL.y)
	face.position = Vector3(TEXT_LEFT - 0.04 + face.size.x * 0.5, eye + PANEL_UP, front)
	add_child(face)

	scroller = Node3D.new()
	scroller.name = "Lines"
	scroller.position = Vector3(0, eye + LINES_UP, front + 0.001)
	add_child(scroller)
	last_line = _line("Last", PITCH, CAP_SIDE, DIM)
	now_line = _line("Now", 0.0, CAP_NOW, INK)
	next_line = _line("Next", -PITCH, CAP_SIDE, Color(0.82, 0.82, 0.8))

	# The mark before the line sung: a small wedge pointing at it.
	mark = MeshInstance3D.new()
	mark.name = "Mark"
	var wedge := PrismMesh.new()
	wedge.size = Vector3(MARK, MARK * 0.9, 0.004)
	mark.mesh = wedge
	mark.rotation.z = -PI * 0.5
	mark.position = Vector3(TEXT_LEFT - MARK * 0.85, 0.0, 0.0)
	mark.material_override = _glow(INK)
	scroller.add_child(mark)
	# The bar under it: a dim track the width of the column, and the part of it sung so far.
	bar_track = _bar("BarTrack", Color(0.22, 0.22, 0.24), 0.0)
	bar_track.position.x = TEXT_LEFT + TEXT_WIDE * 0.5
	bar = _bar("Bar", Color(0.95, 0.78, 0.42), 0.0005)
	(bar.mesh as BoxMesh).size.x = TEXT_WIDE

	status = _label("", STATUS_CAP, DIM)
	status.name = "Status"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	status.position = Vector3(TEXT_LEFT - MARK, eye + STATUS_UP, front + 0.001)
	add_child(status)

	tap_key = BoardKey.new()
	tap_key.board = self
	tap_key.name = "Tap"
	tap_key.kind = BoardKey.TAP
	tap_key.size = TAP_SIZE
	tap_key.position = Vector3(TAP_AT.x, eye + TAP_AT.y, front)
	add_child(tap_key)
	edit_key = BoardKey.new()
	edit_key.board = self
	edit_key.name = "Edit"
	edit_key.kind = BoardKey.EDIT
	edit_key.size = EDIT_SIZE
	edit_key.position = Vector3(EDIT_AT.x, eye + EDIT_AT.y, front)
	add_child(edit_key)


func _line(named: String, y: float, cap: float, colour: Color) -> Label3D:
	var l := _label("", cap, colour)
	l.name = named
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.position = Vector3(TEXT_LEFT, y, 0.0)
	scroller.add_child(l)
	return l


func _bar(named: String, colour: Color, lift: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = named
	var slab := BoxMesh.new()
	slab.size = Vector3(TEXT_WIDE, BAR_TALL, 0.002)
	m.mesh = slab
	m.position = Vector3(TEXT_LEFT + TEXT_WIDE * 0.5, -BAR_DOWN, lift)
	m.material_override = _glow(colour)
	scroller.add_child(m)
	return m


static func _label(words: String, cap: float, colour: Color) -> Label3D:
	var l := Label3D.new()
	l.text = words
	l.pixel_size = 0.0002
	l.font_size = roundi(cap / l.pixel_size)
	l.modulate = colour
	l.shaded = false
	l.double_sided = false
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Lettering.range_to_legibility(l)
	return l


static func _glow(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## TAP and EDIT: a key on the board's face, pressed by a fingertip, a pinch's ray or a click. TAP
## times the next line; EDIT asks for one.
class BoardKey extends ControlAffordance:
	const TAP := 0
	const EDIT := 1
	var board: LyricBoard
	var kind := TAP
	var size := Vector2(0.1, 0.06)
	var legend: Label3D

	func _ready() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(size.x, size.y, 0.03)
		shape.shape = box
		add_child(shape)
		var cap := MeshInstance3D.new()
		cap.name = "Cap"
		var slab := BoxMesh.new()
		slab.size = Vector3(size.x - 0.008, size.y - 0.008, 0.012)
		cap.mesh = slab
		cap.position.z = 0.006
		var paint := StandardMaterial3D.new()
		paint.albedo_color = Color(0.36, 0.3, 0.2) if kind == TAP else Color(0.24, 0.24, 0.26)
		paint.roughness = 0.55
		cap.material_override = paint
		add_child(cap)
		legend = LyricBoard._label("TAP" if kind == TAP else "EDIT", 0.045 if kind == TAP else 0.022, LyricBoard.INK)
		legend.name = "Legend"
		legend.position.z = 0.0125
		add_child(legend)

	func personal() -> bool:
		return true

	func dwell_activates() -> bool:
		# A TAP is a moment in the song: looking at the key for a second is never that moment.
		return kind == EDIT

	func _default_title() -> String:
		return "LYRICS  TAP" if kind == TAP else "LYRICS  EDIT"

	func _default_readout() -> String:
		if board == null:
			return ""
		var lyr := board.lyrics()
		if kind == EDIT:
			var n := lyr.sequence().size()
			return "%d line%s" % [n, "" if n == 1 else "s"] if n > 0 else "no lyrics yet"
		var i := lyr.next_untimed()
		return "next: %s" % str(lyr.lines[i]["text"]) if i >= 0 else "every line is timed"

	func hint() -> String:
		if kind == TAP:
			return "press as the next line starts, the song playing: it is timed where you hear it · at a desk, click the board and Enter taps"
		return "type a line onto the end (a headset) · at a desk, the session panel's LYRICS box has them all"

	func _on_grab_begin(_at: Vector3) -> void:
		var hand := held_by
		grab_end(hand)
		if board == null:
			return
		if kind == TAP:
			board.tap()
		else:
			board.edit()


## The board's face, behind its lines: its hover card says what the lyrics are and how they are
## edited and timed, and a click at a desk gives the board Enter (LyricBoard.arm), or takes it back.
class Face extends ControlAffordance:
	var board: LyricBoard
	var size := Vector2(0.6, 0.3)

	func _ready() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(size.x, size.y, 0.01)
		shape.shape = box
		add_child(shape)

	func personal() -> bool:
		return true

	func _default_title() -> String:
		return "LYRIC BOARD"

	func _default_readout() -> String:
		return board.status_words() if board != null else ""

	func hint() -> String:
		return "the line sung now is large, marked and barred · TAP times the next untimed one · at a desk, click to let Enter TAP · EDIT adds a line"

	func _on_grab_begin(_at: Vector3) -> void:
		var hand := held_by
		grab_end(hand)
		# A desk's click: a poke or pinch in a headset that misses TAP does nothing (LyricBoard.arm).
		if board != null:
			board.arm(not board.armed)
