class_name WorkshopJournal
extends Node

## What the player did in the last few minutes, kept for the Workshop (docs/workshop.md, "Context"),
## so a request like "make this louder" or "this thing I just grabbed is too small" is sent with
## what "this" was.
##
## A ring of at most MAX_EVENTS events ({t, kind, text, data}; `t` in msec since the engine started),
## nothing older than KEEP_MSEC said, and beside it a sparse trail of where the player stood and
## what they looked at (`trail`, at most MAX_TRAIL). Nothing is called from the gear: the journal
## listens where everything already passes:
##
## - every ControlAffordance (the tree's `node_added`, and those already standing): a grab and its
##   let-go are one event with the value before and after and the control's readout; a scroll's
##   `value_committed` is folded into the last event while it is the same control;
## - every Item's `state_changed`: grabbed, thrown or dropped, put back;
## - the studio: its venue, the surface focused (FocusRig), the station gone to (polled, since
##   I, F, a click on the board and a headset's travel all end in `Studio.station`);
## - DAW: the transport (play, stop, record, a seek);
## - Session: every notice (a toast), and the notes and hits this player played, a line an
##   instrument after a pause rather than a line a note;
## - the engine's own log (a Logger, OS.add_logger): SCRIPT ERRORs and warnings, and the last
##   LOG_TAIL lines of everything printed, for the context's log tail;
## - each TICK: where the player is (kept when they moved MOVE_M or turned TURN_DEG) and what is
##   under the cursor or the gaze (kept when it changed).
##
## Cheap per frame: the work is in signals and one check a TICK.

const MAX_EVENTS := 400
const MAX_TRAIL := 150
const KEEP_MSEC := 5 * 60 * 1000
const TICK := 1.0
const MOVE_M := 0.5
const TURN_DEG := 25.0
## How long a run of notes on one instrument may pause and still be one line (msec).
const PLAY_GAP := 2000
## How long a scroll on one control is folded into its last line (msec).
const FOLD_MSEC := 1500
const LOG_TAIL := 120

var studio: Studio
var events: Array = []
var trail: Array = []
## The last LOG_TAIL lines the engine printed or reported, oldest first.
var log_tail: PackedStringArray = []

var _grab_from := {}
var _playing := {}
var _last_pos := Vector3.INF
var _last_yaw := 0.0
var _last_look := ""
var _last_station := &""
var _was_playing := false
var _was_recording := false
var _last_seconds := 0.0
var _last_seconds_at := 0
var _since := 0.0
var _logger: JournalLogger
var _hooked := {}


func _ready() -> void:
	name = "WorkshopJournal"
	get_tree().node_added.connect(_on_node_added)
	# Every control and item standing already (an Item is a ControlAffordance, in the same group).
	for n in get_tree().get_nodes_in_group(ControlAffordance.GROUP):
		_hook(n)
	Session.notice.connect(func(text: String) -> void: record(&"notice", text))
	Session.note_played.connect(_on_note)
	Session.item_hit.connect(_on_hit)
	DAW.transport_changed.connect(_on_transport)
	_logger = JournalLogger.new()
	OS.add_logger(_logger)
	if studio != null:
		watch(studio)


func _exit_tree() -> void:
	if _logger != null:
		OS.remove_logger(_logger)
		_logger = null


## Follow this studio's venue, focus and stations.
func watch(s: Studio) -> void:
	studio = s
	if not s.venue_changed.is_connected(_on_venue):
		s.venue_changed.connect(_on_venue)
	if s.focus != null and not s.focus.focus_changed.is_connected(_on_focus):
		s.focus.focus_changed.connect(_on_focus)


## One event: `kind` (a StringName: station, control, item, transport, venue, focus, notice,
## played, error, warning, look, ...), what it was in words, and anything else worth keeping.
func record(kind: StringName, text: String, data := {}) -> void:
	var now := Time.get_ticks_msec()
	if not events.is_empty():
		var last: Dictionary = events[-1]
		# The same toast twice in a row is said once.
		if last["kind"] == kind and last["text"] == text and now - int(last["t"]) < FOLD_MSEC:
			last["t"] = now
			return
	events.append({"t": now, "kind": kind, "text": text, "data": data})
	if events.size() > MAX_EVENTS:
		events = events.slice(events.size() - MAX_EVENTS)


## The events no older than KEEP_MSEC, oldest first.
func recent(now := Time.get_ticks_msec()) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return now - int(e["t"]) <= KEEP_MSEC)


func _process(delta: float) -> void:
	_drain_log()
	_flush_playing(false)
	_since += delta
	if _since < TICK:
		return
	_since = 0.0
	tick()


## One TICK's look round: the station, the pose, and what is looked at.
func tick() -> void:
	if studio == null or not is_instance_valid(studio):
		return
	if studio.station != _last_station:
		_last_station = studio.station
		if studio.station != &"":
			var r := Stations.row(studio.station)
			record(&"station", "went to %s (%s)" % [r.get("title", String(studio.station)), studio.station],
					{"id": String(studio.station)})
		else:
			record(&"station", "back at the desk")
	var pose := player_pose(studio)
	if pose.is_empty():
		return
	var at: Vector3 = pose["position"]
	var yaw: float = pose["heading_deg"]
	if _last_pos == Vector3.INF or at.distance_to(_last_pos) > MOVE_M or absf(wrapf(yaw - _last_yaw, -180.0, 180.0)) > TURN_DEG:
		_last_pos = at
		_last_yaw = yaw
		trail.append({"t": Time.get_ticks_msec(), "x": snappedf(at.x, 0.01), "y": snappedf(at.y, 0.01),
				"z": snappedf(at.z, 0.01), "heading": snappedf(yaw, 1.0)})
		if trail.size() > MAX_TRAIL:
			trail = trail.slice(trail.size() - MAX_TRAIL)
	var look := looking_at(studio)
	var said := str(look.get("title", look.get("path", "")))
	if said != _last_look:
		_last_look = said
		if said != "":
			record(&"look", "looking at %s" % said, look)


## Where the player is and which way they face, in the studio's frame: {position (the eye),
## heading_deg (0 toward -Z, the desk's way), pitch_deg, eye_height}. Empty with nobody.
static func player_pose(s: Studio) -> Dictionary:
	if s == null:
		return {}
	var cam := s.get_viewport().get_camera_3d() if s.get_viewport() != null else null
	if s.walker != null and s.walker.is_inside_tree() and s.medium == Presentation.Medium.SCREEN:
		return {"position": s.walker.eye(), "heading_deg": rad_to_deg(s.walker.yaw), "pitch_deg": rad_to_deg(s.walker.pitch),
				"eye_height": s.walker.eye_height, "feet": s.walker.global_position}
	if cam != null and cam.is_inside_tree():
		var f := -cam.global_basis.z
		return {"position": cam.global_position, "heading_deg": rad_to_deg(atan2(-f.x, -f.z)),
				"pitch_deg": rad_to_deg(asin(clampf(f.y, -1.0, 1.0))), "eye_height": cam.global_position.y}
	return {}


## What is under the cursor (a desk) or straight ahead of the eye (a headset): {title, readout,
## hint, path, script, kind} for a control, {path, script, kind} for anything else the ray meets.
static func looking_at(s: Studio) -> Dictionary:
	if s == null or s.get_viewport() == null:
		return {}
	var mouse := s.get_node_or_null("MouseHand") as Interactor
	if mouse != null and mouse.hovered != null and is_instance_valid(mouse.hovered):
		return describe(mouse.hovered)
	var cam := s.get_viewport().get_camera_3d()
	if cam == null or not cam.is_inside_tree():
		return {}
	var from := cam.global_position
	var dir := -cam.global_basis.z
	if mouse is MouseInteractor:
		var aim := (mouse as MouseInteractor).aim()
		from = aim.origin
		dir = -aim.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 12.0)
	q.collide_with_areas = true
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or not (hit.get("collider") is Node):
		return {}
	var d := describe(hit["collider"])
	d["distance_m"] = snappedf(from.distance_to(hit["position"]), 0.01)
	return d


## A node as the context says it: its hover card's words where it has them, its path, its script,
## what it is.
static func describe(n: Node) -> Dictionary:
	var out := {"path": str(n.get_path()) if n.is_inside_tree() else n.name, "kind": n.get_class()}
	var sc := n.get_script() as Script
	if sc != null:
		out["script"] = sc.resource_path
		var gn := sc.get_global_name()
		if gn != &"":
			out["kind"] = String(gn)
	if n is Item:
		out["title"] = "item " + String((n as Item).id)
		out["item"] = String((n as Item).id)
	elif n is ControlAffordance:
		var c := n as ControlAffordance
		out["title"] = c.title()
		out["readout"] = c.readout()
		out["hint"] = c.hint()
		out["value"] = snappedf(c.value, 0.001)
	return out


func _on_node_added(n: Node) -> void:
	if n is ControlAffordance:
		_hook(n)


func _hook(n: Node) -> void:
	var key := n.get_instance_id()
	if _hooked.has(key):
		return
	_hooked[key] = true
	n.tree_exited.connect(func() -> void: _hooked.erase(key), CONNECT_ONE_SHOT)
	# An Item is a ControlAffordance too: what matters of it is grabbed, thrown, put back, not its grab.
	if n is Item:
		var it := n as Item
		it.state_changed.connect(_on_item_state.bind(it))
	elif n is ControlAffordance:
		var c := n as ControlAffordance
		c.grab_started.connect(_on_grab_started.bind(c))
		c.grab_ended.connect(_on_grab_ended.bind(c))
		c.value_committed.connect(_on_committed.bind(c))


func _on_grab_started(_by: Node, c: ControlAffordance) -> void:
	if is_instance_valid(c):
		_grab_from[c.get_instance_id()] = c.value


func _on_grab_ended(_by: Node, c: ControlAffordance) -> void:
	if not is_instance_valid(c):
		return
	var was: float = _grab_from.get(c.get_instance_id(), c.value)
	_grab_from.erase(c.get_instance_id())
	var d := describe(c)
	d["from"] = snappedf(was, 0.001)
	d["to"] = snappedf(c.value, 0.001)
	var change := "%.3f → %.3f" % [was, c.value] if absf(was - c.value) > 0.0005 else "pressed"
	var readout := str(d.get("readout", ""))
	record(&"control", "%s: %s%s" % [d.get("title", c.name), change, (" (%s)" % readout) if readout != "" else ""], d)


func _on_committed(v: float, c: ControlAffordance) -> void:
	if not is_instance_valid(c) or c.held_by != null:
		return
	var path := str(c.get_path())
	var now := Time.get_ticks_msec()
	if not events.is_empty():
		var last: Dictionary = events[-1]
		if last["kind"] == &"control" and str(last["data"].get("path", "")) == path and now - int(last["t"]) < FOLD_MSEC:
			last["t"] = now
			last["data"]["to"] = snappedf(v, 0.001)
			last["text"] = "%s: %.3f → %.3f (scrolled%s)" % [c.title(), float(last["data"].get("from", v)), v,
					(", " + c.readout()) if c.readout() != "" else ""]
			return
	var d := describe(c)
	d["from"] = d["value"]
	d["to"] = snappedf(v, 0.001)
	record(&"control", "%s: → %.3f (scrolled%s)" % [d.get("title", c.name), v, (", " + c.readout()) if c.readout() != "" else ""], d)


func _on_item_state(state: int, it: Item) -> void:
	if not is_instance_valid(it):
		return
	var words: String = {Item.State.HELD: "grabbed", Item.State.LOOSE: "threw or dropped", Item.State.HOME: "put back"}.get(state, "moved")
	var d := describe(it)
	d["scale"] = snappedf(it.scale.x, 0.01)
	# A burst (every item put home as a venue is built) is one event naming them all.
	var now := Time.get_ticks_msec()
	if not events.is_empty():
		var last: Dictionary = events[-1]
		if last["kind"] == &"item" and str(last["data"].get("words", "")) == words and now - int(last["t"]) < FOLD_MSEC:
			var ids: Array = last["data"].get("ids", [])
			if not ids.has(String(it.id)):
				ids.append(String(it.id))
			last["data"]["ids"] = ids
			last["t"] = now
			last["text"] = "%s %s" % [words, ", ".join(ids)] if ids.size() <= 6 \
					else "%s %d items (%s, ...)" % [words, ids.size(), ", ".join(ids.slice(0, 6))]
			return
	d["words"] = words
	d["ids"] = [String(it.id)]
	record(&"item", "%s %s" % [words, it.id], d)


func _on_note(kind: int, pitch: int, velocity: int, from: int, _song: float, source: StringName) -> void:
	if from != Session.local_peer_id or kind != Session.Note.ON:
		return
	_add_played(String(source) if source != &"" else "keys", pitch, velocity)


func _on_hit(item: StringName, velocity: int, from: int, _song: float, _snap: bool, _take: int, zone: StringName) -> void:
	if from != Session.local_peer_id:
		return
	_add_played("%s%s" % [item, (" " + String(zone)) if zone != &"" else ""], -1, velocity)


func _add_played(what: String, pitch: int, velocity: int) -> void:
	var p: Dictionary = _playing.get(what, {"n": 0, "low": 999, "high": -1, "loud": 0, "start": Time.get_ticks_msec()})
	p["n"] += 1
	if pitch >= 0:
		p["low"] = mini(p["low"], pitch)
		p["high"] = maxi(p["high"], pitch)
	p["loud"] = maxi(p["loud"], velocity)
	p["last"] = Time.get_ticks_msec()
	_playing[what] = p


func _flush_playing(all: bool) -> void:
	var now := Time.get_ticks_msec()
	for what: String in _playing.keys():
		var p: Dictionary = _playing[what]
		if all or now - int(p["last"]) > PLAY_GAP:
			var span := " notes %d-%d" % [p["low"], p["high"]] if p["high"] >= 0 else ""
			record(&"played", "played %s: %d hit%s%s, loudest %d" % [what, p["n"], "" if p["n"] == 1 else "s", span, p["loud"]],
					{"source": what, "count": p["n"]})
			_playing.erase(what)


## Anything still being played said now (before a snapshot).
func flush() -> void:
	_flush_playing(true)
	_drain_log()


func _on_transport() -> void:
	var s := DAW.state
	if s == null:
		return
	var now := Time.get_ticks_msec()
	if s.recording != _was_recording:
		record(&"transport", "recording" if s.recording else "recording stopped", {"at": s.bar_beat(s.position_seconds)})
	elif s.playing != _was_playing:
		record(&"transport", ("playing from " if s.playing else "stopped at ") + s.bar_beat(s.position_seconds))
	else:
		var expected := _last_seconds + ((now - _last_seconds_at) / 1000.0 if s.playing else 0.0)
		if absf(s.position_seconds - expected) > 1.0:
			record(&"transport", "sought to %s" % s.bar_beat(s.position_seconds))
	_was_playing = s.playing
	_was_recording = s.recording
	_last_seconds = s.position_seconds
	_last_seconds_at = now


func _on_venue(id: StringName) -> void:
	record(&"venue", "venue changed to %s" % id, {"id": String(id), "variant": studio.venue.variant if studio != null and studio.venue != null else 0})


func _on_focus(id: StringName) -> void:
	record(&"focus", "focused %s" % id if id != &"" else "let go of the focused surface", {"id": String(id)})


func _drain_log() -> void:
	if _logger == null:
		return
	for entry: Array in _logger.take():
		var text: String = entry[1]
		for l in text.strip_edges().split("\n"):
			log_tail.append(l)
		if entry[0] != &"":
			record(entry[0], text.strip_edges().split("\n")[0].left(300))
	if log_tail.size() > LOG_TAIL:
		log_tail = log_tail.slice(log_tail.size() - LOG_TAIL)


static func _all_items(n: Node) -> Array:
	var out: Array = []
	if n is Item:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_items(c))
	return out


## The engine's log as it is written: from any thread, so kept under a lock and taken on the main
## thread (`take`). Each entry [kind, text]: kind &"error" or &"warning" for those, empty for a print.
class JournalLogger extends Logger:
	var _lock := Mutex.new()
	var _queue: Array = []

	func _log_message(message: String, error: bool) -> void:
		_lock.lock()
		_queue.append([&"error" if error and message.contains("ERROR") else &"", message])
		if _queue.size() > 400:
			_queue = _queue.slice(_queue.size() - 400)
		_lock.unlock()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var kind := &"warning" if error_type == ERROR_TYPE_WARNING else &"error"
		var what := rationale if rationale != "" else code
		var label := "SCRIPT ERROR" if error_type == ERROR_TYPE_SCRIPT else ("WARNING" if kind == &"warning" else "ERROR")
		_lock.lock()
		_queue.append([kind, "%s: %s (%s:%d %s)" % [label, what, file, line, function]])
		_lock.unlock()

	func take() -> Array:
		_lock.lock()
		var out := _queue
		_queue = []
		_lock.unlock()
		return out
