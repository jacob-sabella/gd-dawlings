class_name WorkshopPanel
extends Node3D

## The Workshop's panel (docs/workshop.md): a board on the control room's right wall where a change
## is asked for and followed. Station `workshop` (Stations), there only where Workshop.enabled.
##
## Its face, top down: WORKSHOP and the line that says it is a dev tool on this machine alone; what
## the last reload brought the game onto; the request running now (or the last), its status and its
## last LINES progress lines (tools used, files edited, test lines, the result); the HISTORY, a line a
## request with its status; the context line (how many events go with the next request, and whether
## a screenshot does); then a row of keys: ASK (the monitor's text box at a desk, a typing pad under
## the panel in a headset, as F9 is from anywhere), CANCEL (or STAY, while a reload counts down),
## UNDO LAST, FIX, RELOAD, SHOT (a screenshot with each request, or not) and CONTEXT (shows what will
## be sent: the monitor's overlay at a desk, a page beside the panel in a headset). Its plaque hangs
## on the wall beside it.
##
## Every key is personal: nothing of the Workshop is shown to or pressed by anyone else.
##
## Its frame: the origin on the floor under the middle of its face, +Z out of the face into the room.

const STATION := &"workshop"
## The face: how big, its middle's height, how far from the wall where it stands on a post, and how
## far toward the desk from the live room's opening (Venue.workshop_spot).
const FACE := Vector2(1.12, 0.8)
const MIDDLE := 1.42
const DEPTH := 0.03
const OFF_WALL := 0.4
## Off a wall: on stand-offs clear of what the venue hangs there (the studio's acoustic panel behind it,
## whose fabric shows above the face).
const ON_WALL := 0.16
const FROM_LIVE_ROOM := 1.4
## The plaque hangs under the face, its top this far below the face's foot: beside it, it ran into
## the open venues' posts.
const PLAQUE_GAP := 0.03
## The station row's frame: the face's top, and the plaque's foot under it, opened (about).
const FRAME_TOP := Vector3(0, MIDDLE + FACE.y * 0.5, 0)
const FRAME_FOOT := Vector3(0, MIDDLE - FACE.y * 0.5 - PLAQUE_GAP - 0.36, 0.02)
## How long a request may be (characters).
const ASK_MAX := 400
## Where a headset's typing pad opens: under the face, tipped up toward whoever stands at it.
const PAD_AT := Transform3D(Basis(Vector3.RIGHT, -0.55), Vector3(0, MIDDLE - FACE.y * 0.5 - 0.12, 0.22))
const LINES := 9
const HISTORY := 5
const LEFT := -FACE.x * 0.5 + 0.04
const TITLE_INK := Color(0.95, 0.9, 0.78)
const INK := Color(0.92, 0.91, 0.86)
const DIM := Color(0.6, 0.62, 0.64)
const GOOD := Color(0.55, 0.9, 0.6)
const BAD := Color(1.0, 0.5, 0.42)
const KEY_SIZE := Vector2(0.142, 0.07)
const KEYS := ["ASK", "CANCEL", "UNDO LAST", "FIX", "RELOAD", "SHOT", "CONTEXT"]

var workshop: Workshop
var title: Label3D
var info: Label3D
var reloaded: Label3D
var current: Label3D
var progress: Array[Label3D] = []
var history_lines: Array[Label3D] = []
var context_line: Label3D
var keys := {}
## The page of what will be sent (a headset), or the overlay (a desk), or null.
var context_view: Node = null


func _init() -> void:
	name = "WorkshopPanel"


func _ready() -> void:
	var face := MeshInstance3D.new()
	face.name = "Face"
	var box := BoxMesh.new()
	box.size = Vector3(FACE.x, FACE.y, DEPTH)
	face.mesh = box
	face.position = Vector3(0, MIDDLE, -DEPTH * 0.5)
	# A screen's glass, faintly lit from inside: the wall it hangs on is the room's dimmest corner,
	# and its lines are what it is for.
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.06, 0.07, 0.08)
	glass.emission_enabled = true
	glass.emission = Color(0.09, 0.1, 0.12)
	glass.roughness = 0.35
	face.material_override = glass
	add_child(face)
	var posted := workshop != null and workshop.studio != null and workshop.studio.venue != null \
			and workshop.studio.venue.back_wall_gear_stands()
	if posted:
		var post := MeshInstance3D.new()
		post.name = "Post"
		var pm := BoxMesh.new()
		pm.size = Vector3(0.06, MIDDLE - FACE.y * 0.5, 0.06)
		post.mesh = pm
		post.position = Vector3(0, pm.size.y * 0.5, -DEPTH - 0.03)
		post.material_override = Materials.brushed_metal()
		add_child(post)
	var top := MIDDLE + FACE.y * 0.5
	title = _label("WORKSHOP", 0.045, TITLE_INK)
	title.name = "Title"
	title.position = Vector3(LEFT, top - 0.04, 0.002)
	add_child(title)
	info = _label("dev only · this machine · nothing goes over the network", 0.016, DIM)
	info.name = "Info"
	info.position = Vector3(LEFT + 0.31, top - 0.045, 0.002)
	add_child(info)
	reloaded = _label("", 0.017, GOOD)
	reloaded.name = "Reloaded"
	reloaded.position = Vector3(LEFT, top - 0.09, 0.002)
	add_child(reloaded)
	current = _label("", 0.022, INK)
	current.name = "Current"
	current.position = Vector3(LEFT, top - 0.13, 0.002)
	add_child(current)
	for i in LINES:
		var l := _label("", 0.0155, DIM)
		l.name = "Line%d" % i
		l.position = Vector3(LEFT + 0.02, top - 0.17 - i * 0.026, 0.002)
		add_child(l)
		progress.append(l)
	var history_top := top - 0.17 - LINES * 0.026 - 0.02
	var heading := _label("HISTORY", 0.016, TITLE_INK)
	heading.name = "HistoryHeading"
	heading.position = Vector3(LEFT, history_top, 0.002)
	add_child(heading)
	for i in HISTORY:
		var l := _label("", 0.0155, INK)
		l.name = "History%d" % i
		l.position = Vector3(LEFT + 0.02, history_top - 0.026 * (i + 1), 0.002)
		add_child(l)
		history_lines.append(l)
	context_line = _label("", 0.015, DIM)
	context_line.name = "ContextLine"
	context_line.position = Vector3(LEFT, history_top - 0.026 * (HISTORY + 1) - 0.006, 0.002)
	add_child(context_line)
	var row_y := MIDDLE - FACE.y * 0.5 + KEY_SIZE.y * 0.5 + 0.012
	for i in KEYS.size():
		var k := PanelKey.new()
		k.panel = self
		k.word = KEYS[i]
		k.name = "Key" + KEYS[i].replace(" ", "")
		k.size = KEY_SIZE
		k.position = Vector3((i - (KEYS.size() - 1) * 0.5) * (KEY_SIZE.x + 0.008), row_y, 0.0)
		add_child(k)
		keys[KEYS[i]] = k
	var plaque := Stations.plaque(STATION)
	# Its top edge stays where it is as it folds and opens (Stations.fold_plaque).
	var tall := float(plaque.get_meta(&"plaque_tall", 0.2))
	plaque.position = Vector3(0, MIDDLE - FACE.y * 0.5 - PLAQUE_GAP - tall * 0.5, 0.004)
	add_child(plaque)
	# Stand-offs from the wall behind, the face's back to it.
	for side in ([] if posted else [-1.0, 1.0]):
		var stand := MeshInstance3D.new()
		stand.name = "StandOff"
		var sm := BoxMesh.new()
		sm.size = Vector3(0.04, 0.04, ON_WALL)
		stand.mesh = sm
		stand.position = Vector3(side * FACE.x * 0.35, MIDDLE, -DEPTH - ON_WALL * 0.5 + 0.005)
		stand.material_override = Materials.brushed_metal()
		add_child(stand)
	if workshop != null:
		workshop.changed.connect(refresh)
	refresh()


func _process(_delta: float) -> void:
	# The countdown to a reload is said as it runs.
	if workshop != null and workshop.reload_in >= 0.0:
		_set_current("reloading in %.0f s: STAY to stay on this code" % ceilf(workshop.reload_in), GOOD)


## Everything on the face from the Workshop as it is now.
func refresh() -> void:
	if workshop == null:
		return
	reloaded.text = ("reloaded onto: " + workshop.reloaded_onto) if workshop.reloaded_onto != "" else ""
	var shown: Dictionary = workshop._current if workshop.busy() else (workshop.history[-1] if not workshop.history.is_empty() else {})
	if shown.is_empty():
		_set_current("Nothing asked yet. ASK (or F9 anywhere) and type a change.", INK)
	else:
		_set_current("%s  %s" % [String(shown["status"]).to_upper(), _clip(str(shown["text"]), 70)], _colour(shown["status"]))
	var lines: Array = shown.get("lines", []) if not shown.is_empty() else []
	for i in LINES:
		var at := lines.size() - LINES + i
		var l := progress[i]
		if at >= 0 and at < lines.size():
			var line: Dictionary = lines[at]
			l.text = _clip(str(line["text"]), 96)
			l.modulate = BAD if line["kind"] in [WorkshopStream.FAILED, WorkshopStream.ERROR] else \
					(GOOD if line["kind"] in [WorkshopStream.RESULT, WorkshopStream.TESTS] else DIM)
		else:
			l.text = ""
	var older := workshop.history.slice(maxi(0, workshop.history.size() - HISTORY))
	older.reverse()
	for i in HISTORY:
		var l := history_lines[i]
		if i < older.size():
			var r: Dictionary = older[i]
			l.text = _clip("%-9s %s%s" % [String(r["status"]), str(r["text"]), (" — " + str(r["summary"])) if str(r["summary"]) != "" else ""], 96)
			l.modulate = _colour(r["status"])
		else:
			l.text = ""
	var events := workshop.journal.recent().size() if workshop.journal != null else 0
	var queued := workshop.history.filter(func(r: Dictionary) -> bool: return r["status"] == Workshop.QUEUED).size()
	context_line.text = "context: %d events, screenshot %s%s" % [events, "✓" if workshop.with_screenshot else "off",
			("  ·  %d queued" % queued) if queued > 0 else ""]
	(keys["CANCEL"] as PanelKey).set_word("STAY" if workshop.reload_in >= 0.0 else "CANCEL")
	(keys["SHOT"] as PanelKey).set_word("SHOT ✓" if workshop.with_screenshot else "SHOT off")
	(keys["CONTEXT"] as PanelKey).set_word("CONTEXT ✓" if context_view != null else "CONTEXT")


func _set_current(text: String, colour: Color) -> void:
	current.text = text
	current.modulate = colour


static func _colour(status: StringName) -> Color:
	if status in [Workshop.FAILED, Workshop.ERROR]:
		return BAD
	if status in [Workshop.READY, Workshop.RELOADED]:
		return GOOD
	if status in [Workshop.UNDONE, Workshop.CANCELLED]:
		return DIM
	return INK


static func _clip(s: String, n: int) -> String:
	var one := s.replace("\n", " ")
	return one if one.length() <= n else one.left(n - 1) + "…"


## A key pressed: what it does.
func press(word: String) -> void:
	if workshop == null:
		return
	match word:
		"ASK":
			workshop.ask_by_typing()
		"CANCEL":
			workshop.cancel()
		"UNDO LAST":
			workshop.undo()
		"FIX":
			workshop.fix()
		"RELOAD":
			workshop.reload()
		"SHOT":
			workshop.with_screenshot = not workshop.with_screenshot
			workshop.save_settings()
		"CONTEXT":
			toggle_context()
	refresh()


## Show what the next request will be sent with, or put it away: at a desk an overlay on the monitor,
## in a headset a page of it beside the panel.
func toggle_context() -> void:
	if context_view != null and is_instance_valid(context_view):
		context_view.queue_free()
		context_view = null
		refresh()
		return
	var text := workshop.preview()
	if get_viewport() != null and get_viewport().use_xr:
		var page := _label(_clip_lines(text, 46), 0.012, INK)
		page.name = "ContextPage"
		page.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		page.position = Vector3(FACE.x * 0.5 + 0.06, MIDDLE + FACE.y * 0.5, 0.01)
		add_child(page)
		context_view = page
	else:
		context_view = ContextOverlay.open(self, text)
		context_view.tree_exited.connect(func() -> void:
			context_view = null
			refresh())
	refresh()


static func _clip_lines(text: String, n: int) -> String:
	var lines := text.split("\n")
	return "\n".join(lines.slice(0, n)) + ("\n…" if lines.size() > n else "")


static func _label(words: String, cap: float, colour: Color) -> Label3D:
	var l := Label3D.new()
	l.text = words
	l.pixel_size = 0.0002
	l.font_size = roundi(cap / l.pixel_size)
	l.modulate = colour
	l.shaded = false
	l.double_sided = false
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Lettering.range_to_legibility(l)
	return l


## One of the panel's keys: personal (never claimed, never shown to anyone else), pressed on grab.
class PanelKey extends ControlAffordance:
	var panel: WorkshopPanel
	var word := ""
	var size := Vector2(0.14, 0.07)
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
		paint.albedo_color = Color(0.36, 0.3, 0.2) if word == "ASK" else Color(0.24, 0.24, 0.26)
		paint.roughness = 0.55
		cap.material_override = paint
		add_child(cap)
		legend = WorkshopPanel._label(word, 0.02, WorkshopPanel.INK)
		legend.name = "Legend"
		legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		legend.position.z = 0.0125
		add_child(legend)

	func set_word(w: String) -> void:
		if legend != null:
			legend.text = w

	func personal() -> bool:
		return true

	func dwell_activates() -> bool:
		return word in ["ASK", "SHOT", "CONTEXT"]

	func _default_title() -> String:
		return "WORKSHOP  " + (legend.text if legend != null else word)

	func hint() -> String:
		match word:
			"ASK":
				return "type a change you want made: Claude Code makes it in the repo, with what you were just doing, and the game reloads back here · F9 from anywhere at a desk"
			"CANCEL":
				return "stop the request running now (what it changed can be undone) · while a reload counts down, stay on this code"
			"UNDO LAST":
				return "put back exactly the files the last request changed, as they were before it ran; nothing else in the tree is touched"
			"FIX":
				return "ask the same Claude session to fix the checks that failed"
			"RELOAD":
				return "start the game again on the code as it is now and come back right here"
			"SHOT":
				return "send a screenshot of your view with each request, or not"
			"CONTEXT":
				return "show what the next request will be sent with: the game's state and your last minutes"
		return ""

	func _on_grab_begin(_at: Vector3) -> void:
		var hand := held_by
		grab_end(hand)
		if panel != null:
			panel.press(word)


## What will be sent, on the monitor: a scrolling text over everything, Escape or the button closes it.
class ContextOverlay extends CanvasLayer:
	static func open(parent: Node, text: String) -> ContextOverlay:
		var o := ContextOverlay.new()
		o.layer = 99
		o.name = "WorkshopContext"
		parent.get_tree().root.add_child(o)
		var box := PanelContainer.new()
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.offset_left = 60
		box.offset_right = -60
		box.offset_top = 40
		box.offset_bottom = -40
		o.add_child(box)
		var column := VBoxContainer.new()
		box.add_child(column)
		var head := Label.new()
		head.text = "What the next Workshop request is sent with (Escape closes)"
		column.add_child(head)
		var view := TextEdit.new()
		view.text = text
		view.editable = false
		view.size_flags_vertical = Control.SIZE_EXPAND_FILL
		view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		column.add_child(view)
		return o

	func _unhandled_input(event: InputEvent) -> void:
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			queue_free()
