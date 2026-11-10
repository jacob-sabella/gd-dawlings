class_name AssistantPanel
extends Node3D

## The assistant's board (docs/mcp_assistant.md): a panel on the control room's right wall, beside the Workshop's
## place, where the room's assistant is asked and followed. Station `assistant` (Stations), for everyone in the
## room: a guest's question runs on the host. Its face is the last lines of the conversation; its keys ASK (a text
## box at a desk, a typing pad in a headset), CANCEL, NEW CHAT and OPEN (the full panel, F10 from anywhere).
## Every key is personal: it asks as whoever presses it. Its frame: the origin on the floor under the middle of
## its face, +Z out of the face into the room.

const STATION := &"assistant"
const FACE := Vector2(1.12, 0.8)
const MIDDLE := 1.42
const DEPTH := 0.03
const OFF_WALL := 0.4
const ON_WALL := 0.16
## How far toward the desk from the live room's opening (Venue.assistant_spot): past the Workshop's panel.
const FROM_LIVE_ROOM := 2.8
const PLAQUE_GAP := 0.03
const FRAME_TOP := Vector3(0, MIDDLE + FACE.y * 0.5, 0)
const FRAME_FOOT := Vector3(0, MIDDLE - FACE.y * 0.5 - PLAQUE_GAP - 0.36, 0.02)
const PAD_AT := Transform3D(Basis(Vector3.RIGHT, -0.55), Vector3(0, MIDDLE - FACE.y * 0.5 - 0.12, 0.22))
const LINES := 15
const LEFT := -FACE.x * 0.5 + 0.04
const TITLE_INK := Color(0.78, 0.9, 0.95)
const INK := Color(0.92, 0.91, 0.86)
const DIM := Color(0.6, 0.62, 0.64)
const GOOD := Color(0.55, 0.9, 0.6)
const BAD := Color(1.0, 0.5, 0.42)
const ASKED := Color(0.62, 0.78, 1.0)
const KEY_SIZE := Vector2(0.2, 0.07)
const KEYS := ["ASK", "CANCEL", "NEW CHAT", "OPEN"]

var host: ControlHost
var title: Label3D
var status: Label3D
var lines: Array[Label3D] = []
var keys := {}


func _init() -> void:
	name = "AssistantPanel"


func _ready() -> void:
	var face := MeshInstance3D.new()
	face.name = "Face"
	var box := BoxMesh.new()
	box.size = Vector3(FACE.x, FACE.y, DEPTH)
	face.mesh = box
	face.position = Vector3(0, MIDDLE, -DEPTH * 0.5)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.05, 0.07, 0.09)
	glass.emission_enabled = true
	glass.emission = Color(0.07, 0.1, 0.13)
	glass.roughness = 0.35
	face.material_override = glass
	add_child(face)
	var posted: bool = host != null and host.studio != null and host.studio.venue != null \
			and host.studio.venue.back_wall_gear_stands()
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
	title = _label("ASSISTANT", 0.045, TITLE_INK)
	title.name = "Title"
	title.position = Vector3(LEFT, top - 0.04, 0.002)
	add_child(title)
	status = _label("", 0.016, DIM)
	status.name = "Status"
	status.position = Vector3(LEFT, top - 0.085, 0.002)
	add_child(status)
	for i in LINES:
		var l := _label("", 0.0165, DIM)
		l.name = "Line%d" % i
		l.position = Vector3(LEFT, top - 0.125 - i * 0.0275, 0.002)
		add_child(l)
		lines.append(l)
	var row_y := MIDDLE - FACE.y * 0.5 + KEY_SIZE.y * 0.5 + 0.012
	for i in KEYS.size():
		var k := PanelKey.new()
		k.panel = self
		k.word = KEYS[i]
		k.name = "Key" + KEYS[i].replace(" ", "")
		k.size = KEY_SIZE
		k.position = Vector3((i - (KEYS.size() - 1) * 0.5) * (KEY_SIZE.x + 0.01), row_y, 0.0)
		add_child(k)
		keys[KEYS[i]] = k
	var plaque := Stations.plaque(STATION)
	var tall := float(plaque.get_meta(&"plaque_tall", 0.2))
	plaque.position = Vector3(0, MIDDLE - FACE.y * 0.5 - PLAQUE_GAP - tall * 0.5, 0.004)
	add_child(plaque)
	for side in ([] if posted else [-1.0, 1.0]):
		var stand := MeshInstance3D.new()
		stand.name = "StandOff"
		var sm := BoxMesh.new()
		sm.size = Vector3(0.04, 0.04, ON_WALL)
		stand.mesh = sm
		stand.position = Vector3(side * FACE.x * 0.35, MIDDLE, -DEPTH - ON_WALL * 0.5 + 0.005)
		stand.material_override = Materials.brushed_metal()
		add_child(stand)
	if host != null:
		host.assistant.changed.connect(refresh)
	refresh()


## Everything on the face from the conversation as it is now: the newest lines, each clipped to the face.
func refresh() -> void:
	if host == null:
		return
	status.text = host.screen.status_text() if host.screen != null else ""
	var rows := board_rows(host.assistant, LINES)
	for i in LINES:
		var l := lines[i]
		if i < rows.size():
			l.text = rows[i]["text"]
			l.modulate = rows[i]["colour"]
		else:
			l.text = ""
	(keys["CANCEL"] as PanelKey).set_word("CANCEL")


## The last `n` lines of the conversation as {text, colour}: what was asked, what was said, what was done.
static func board_rows(assistant: Assistant, n: int) -> Array:
	var all: Array = []
	if assistant == null or assistant.runs.is_empty():
		all.append({"text": "Nothing asked yet. ASK about the room, or for a change.", "colour": INK})
	else:
		for r: Dictionary in assistant.runs.slice(maxi(0, assistant.runs.size() - 4)):
			all.append({"text": _clip("%s: %s" % [str(r["who"]), str(r["text"])], 84), "colour": ASKED})
			for ev: Dictionary in r["events"]:
				match str(ev["kind"]):
					"say", "result":
						for part in str(ev["text"]).split("\n", false):
							all.append({"text": _clip("  " + part, 90), "colour": INK})
					"tool":
						all.append({"text": _clip("    › " + str(ev["text"]), 90), "colour": DIM})
					"tool_result":
						if not bool(ev.get("ok", true)):
							all.append({"text": _clip("    refused: " + str(ev["text"]), 90), "colour": BAD})
					"error":
						all.append({"text": _clip(str(ev["text"]), 90), "colour": BAD})
			match str(r["status"]):
				"queued":
					all.append({"text": "  waiting for its turn...", "colour": DIM})
				"running":
					all.append({"text": "  working...", "colour": GOOD})
	return all.slice(maxi(0, all.size() - n))


static func _clip(s: String, n: int) -> String:
	var one := s.replace("\n", " ")
	return one if one.length() <= n else one.left(n - 1) + "…"


## A key pressed: what it does.
func press(word: String) -> void:
	if host == null:
		return
	match word:
		"ASK":
			ask_by_typing()
		"CANCEL":
			var id := host.screen.mine_running()
			if id > 0:
				host.assistant.cancel(id)
		"NEW CHAT":
			host.assistant.new_conversation()
		"OPEN":
			host.screen.toggle()
	refresh()


## The question typed: on the monitor a box, in a headset a pad under the face.
func ask_by_typing() -> void:
	var limit := Session.ASSISTANT_ASK_MAX
	if get_viewport() != null and get_viewport().use_xr:
		var old := get_node_or_null("TypingPad")
		if old != null:
			old.queue_free()
		var pad := TypingPad.ask(self, "Ask the assistant: OK sends it", "", PAD_AT)
		pad.limit = limit
		pad.answered.connect(func(text: String) -> void: host.assistant.ask(text))
		return
	var prompt := NamePrompt.ask(host, "Ask the assistant: Enter sends it, Escape leaves it", "", limit)
	prompt.answered.connect(func(text: String) -> void: host.assistant.ask(text))


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


## One of the panel's keys: personal (it asks as whoever presses it), pressed on grab.
class PanelKey extends ControlAffordance:
	var panel: AssistantPanel
	var word := ""
	var size := Vector2(0.2, 0.07)
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
		paint.albedo_color = Color(0.2, 0.3, 0.38) if word == "ASK" else Color(0.24, 0.24, 0.26)
		paint.roughness = 0.55
		cap.material_override = paint
		add_child(cap)
		legend = AssistantPanel._label(word, 0.02, AssistantPanel.INK)
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
		return word in ["ASK", "OPEN"]

	func _default_title() -> String:
		return "ASSISTANT  " + word

	func hint() -> String:
		match word:
			"ASK":
				return "ask the room's assistant a question or for a change: it runs on the host's machine, acts as you, and asks you before anything destructive · F10 from anywhere at a desk"
			"CANCEL":
				return "stop the assistant's run (yours, or any if you are the host)"
			"NEW CHAT":
				return "forget the conversation so far: the next question starts fresh"
			"OPEN":
				return "the full panel: the whole conversation, with ALLOW and DENY for anything it asks first"
		return ""

	func _on_grab_begin(_at: Vector3) -> void:
		var hand := held_by
		grab_end(hand)
		if panel != null:
			panel.press(word)
