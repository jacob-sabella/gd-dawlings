class_name RollBoard
extends Node3D

## The big board on the control room's back wall that writes up the last Rig Roulette roll for the
## whole room: what it did to the project, and what the band now has to work with. A lit screen
## in most venues, a slate with chalk lettering where the venue says so (`Venue.roll_board_chalky`).
##
## A DUMB BOARD: it draws the dictionary `Session.roll` carries (`Studio._roll_rig` writes it) and
## nothing else, so the host's board and every guest's read the same thing off the same state.
##
## The dictionary: `by` (who rolled), `n` (which roll this session), `tracks` (how many the new
## project has), `key` (a name, or "" when LOCK KEY kept it), `pedals` (an array of
## {"track", "fx"}, one per pedal that landed).
##
## Or it shows a surface instead: any piece of gear, live, through a `BoardFeed` (`show_source`).
## Which one is the room's choice, made on the Rig Roulette panel's BIG SCREEN wheel, and a roll
## puts the board back to the write-up.

## One part of a ceremony has landed (the first is the track count): `step` of `of`, from 1.
signal landed(step: int, of: int)

## Seconds between one result landing and the next.
const BEAT := 0.7

const WIDTH := 3.6
const HEIGHT := 1.14

const SCREEN_PLATE := Color(0.035, 0.04, 0.05)
const SCREEN_TEXT := Color(0.62, 1.0, 0.8)
const SCREEN_ACCENT := Color(1.0, 0.82, 0.35)
const SLATE_PLATE := Color(0.09, 0.12, 0.11)
const SLATE_TEXT := Color(0.94, 0.96, 0.98)
const SLATE_ACCENT := Color(1.0, 0.92, 0.3)

var chalky := false
## Stood on two posts of its own, for a venue with no wall where it hangs.
var free_standing := false
## Passed on to the feed: the renderer's resolution, and the room's look.
var rich := false
var environment_from: Environment

var _text: Node3D
var _roll: Dictionary = {}
## The writing in the order it lands in a ceremony: each an array of labels that appear together.
var _steps: Array = []
var _ceremony: Tween
var _feed: BoardFeed
var _feed_caption: Label3D


func _ready() -> void:
	var plate := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(WIDTH, HEIGHT, 0.04)
	plate.mesh = mesh
	plate.position = Vector3(0, HEIGHT * 0.5, -0.02)
	var m := StandardMaterial3D.new()
	m.albedo_color = SLATE_PLATE if chalky else SCREEN_PLATE
	# A screen's anti-glare finish, not glass: at 0.25 the lamps hung near it (the rooftop's
	# string lights) sat on the write-up as two big soft discs.
	m.roughness = 0.9 if chalky else 0.75
	m.metallic_specular = 0.2
	if not chalky:
		# A lit screen, not a painted board: it glows a little against the wall it hangs on.
		m.emission_enabled = true
		m.emission = Color(0.05, 0.09, 0.08)
	plate.material_override = m
	add_child(plate)
	var frame := MeshInstance3D.new()
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(WIDTH + 0.08, HEIGHT + 0.08, 0.03)
	frame.mesh = frame_mesh
	frame.position = Vector3(0, HEIGHT * 0.5, -0.037)
	frame.material_override = Materials.furniture()
	GearTrim.edges(frame)
	add_child(frame)
	if free_standing:
		for side in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			post.name = "PostLeft" if side < 0.0 else "PostRight"
			var post_mesh := BoxMesh.new()
			post_mesh.size = Vector3(0.07, position.y, 0.07)
			post.mesh = post_mesh
			post.position = Vector3(side * (WIDTH * 0.5 - 0.3), -position.y * 0.5, -0.08)
			post.material_override = Materials.furniture()
			GearTrim.edges(post)
			add_child(post)
			var foot := MeshInstance3D.new()
			var foot_mesh := BoxMesh.new()
			foot_mesh.size = Vector3(0.16, 0.03, 0.5)
			foot.mesh = foot_mesh
			foot.position = Vector3(side * (WIDTH * 0.5 - 0.3), 0.015 - position.y, -0.08)
			foot.material_override = Materials.furniture()
			add_child(foot)
	_feed = BoardFeed.new()
	_feed.name = "Feed"
	_feed.rich = rich
	_feed.environment_from = environment_from
	_feed.backdrop = SLATE_PLATE if chalky else SCREEN_PLATE
	_feed.screen_size = Vector2(WIDTH - 0.08, HEIGHT - 0.08)
	_feed.position = Vector3(0, HEIGHT * 0.5, 0.002)
	_feed.visible = false
	add_child(_feed)
	_feed_caption = Label3D.new()
	_feed_caption.name = "FeedCaption"
	_feed_caption.font_size = 60
	_feed_caption.pixel_size = 0.0011
	_feed_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_feed_caption.position = Vector3(-WIDTH * 0.5 + 0.07, HEIGHT - 0.07, 0.004)
	_feed_caption.modulate = SLATE_ACCENT if chalky else SCREEN_ACCENT
	_feed_caption.double_sided = false
	_feed_caption.visible = false
	add_child(_feed_caption)
	show_roll(_roll)


## What the board shows now: the surface it is showing, or null for the roll's write-up.
func source() -> Surface:
	return _feed.target if _feed != null and _feed.visible else null


## Show `surface` live, captioned `title`, in place of the write-up; null puts the write-up back.
func show_source(surface: Surface, title := "") -> void:
	var live := surface != null
	_feed.target = surface
	_feed.visible = live
	_feed_caption.visible = live
	_feed_caption.text = title.to_upper()
	if _text != null:
		_text.visible = not live


## Writes the board out again from `roll` (empty before any roll has been made).
func show_roll(roll: Dictionary, ceremony := false) -> void:
	_roll = roll
	_steps = []
	if _ceremony != null:
		_ceremony.kill()
		_ceremony = null
	if _text != null:
		# Out of the tree now, not at the end of the frame: two writings in a row would overlap.
		remove_child(_text)
		_text.queue_free()
	_text = Node3D.new()
	_text.name = "Writing"
	_text.visible = _feed == null or not _feed.visible
	add_child(_text)
	var ink := SLATE_TEXT if chalky else SCREEN_TEXT
	var accent := SLATE_ACCENT if chalky else SCREEN_ACCENT

	_write("RIG ROULETTE", 84, Vector3(0, HEIGHT - 0.10, 0), accent)
	if roll.is_empty():
		_write("Press ROLL on the panel.", 130, Vector3(0, HEIGHT * 0.56, 0), ink)
		_write("A roll starts a NEW project: a random number of tracks, a few pedals dropped on\n"
				+ "random tracks, and a key. Write a song from only that. Save the open project first.", 52,
				Vector3(0, HEIGHT * 0.20, 0), ink)
		return

	var tracks: int = roll.get("tracks", 0)
	var key: String = roll.get("key", "")
	var left := -WIDTH * 0.25
	_step(_write("%d TRACKS" % tracks, 190, Vector3(left, HEIGHT * 0.53, 0), ink))

	var pedals: Array = roll.get("pedals", [])
	var right := WIDTH * 0.22
	if pedals.is_empty():
		_step(_write("no pedals landed", 84, Vector3(right, HEIGHT * 0.5, 0), ink))
	else:
		var y := HEIGHT * 0.66
		# Up to six lines fit between the top rule and the key's line.
		var step := minf(0.20, 0.62 / pedals.size())
		for p: Dictionary in pedals:
			_step(_write("%s  on  %s" % [str(p.get("fx", "")).to_upper(), str(p.get("track", "")).to_upper()], 76,
					Vector3(right, y, 0), ink))
			y -= step
	_step(_write(("KEY OF %s" % key.to_upper()) if not key.is_empty() else "KEY KEPT", 96,
			Vector3(left, HEIGHT * 0.25, 0), ink))
	var rerolls: int = roll.get("left", 0)
	var rule := "No re-rolls: write the song with this." if rerolls == 0 else (
			"%d re-roll%s left." % [rerolls, "" if rerolls == 1 else "s"] if rerolls > 0 else "Roll again if you dare.")
	var seed_text := "  Seed %d." % roll["seed"] if roll.has("seed") else ""
	if int(roll.get("chaos", 0)) > 0:
		seed_text += "  Knobs thrown (%d%%)." % (int(roll["chaos"]) * 100 / RollSettings.CHAOS_MAX)
	var foot := _write("A new project, started by %s (roll %d).%s  %s" % [
			roll.get("by", "someone"), roll.get("n", 1), seed_text, rule], 42, Vector3(0, 0.06, 0), accent)
	_steps[-1].append(foot)
	if ceremony and _text.visible:
		_run_ceremony()


## One part of the writing that lands as a unit.
func _step(label: Label3D) -> void:
	_steps.append([label])


## Everything hidden, then each part lands in turn with a small drop in; `landed` says so for the
## sound. Ends with the writing exactly as a plain `show_roll` leaves it.
func _run_ceremony() -> void:
	for step: Array in _steps:
		for l: Label3D in step:
			l.visible = false
	_ceremony = create_tween()
	for i in _steps.size():
		_ceremony.tween_interval(BEAT)
		_ceremony.tween_callback(_land.bind(i))


func _land(i: int) -> void:
	for l: Label3D in _steps[i]:
		l.visible = true
		var home := l.position
		l.position = home + Vector3(0, 0.06, 0)
		create_tween().tween_property(l, "position", home, 0.18).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	landed.emit(i + 1, _steps.size())


func _write(text: String, size: int, at: Vector3, colour: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0011
	l.position = at + Vector3(0, 0, 0.003)
	l.modulate = colour
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.double_sided = false
	Lettering.range_to_legibility(l)
	_text.add_child(l)
	return l
