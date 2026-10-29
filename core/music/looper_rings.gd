class_name LooperRings
extends Node3D

## The looper's rings (docs/spatial_loop.md part two, slice 46, idea #21, its second half): every
## layer the looper has made is a ring stacked round a post on the looper's own stand, not round the
## player. Each is 0.25 m across, the first FIRST (1.0 m) over the stand's feet and each next STEP
## (6 cm) above it, lettered with its player and number (`ADA 2`, `label_of`), so the stand is a
## stack of the loop's layers that everyone in the room sees the same: the rings are drawn from the
## project's LOOPER folder (`layers`), which every machine's mirror of the host's mix has.
##
## A ring's notch passes the front at its layer's start: it turns once a pass of its layer (`turn_of`),
## a small turn within the stand, never round anybody, and at Ergonomics motion 0 it steps a beat at
## a time. Its brightness follows its track's level as a signal bead's does (SignalBeads.glow of
## SignalBeads.track_level, fast up and slow down), so a quiet layer is dim and a busy one bright.
##
## A ring is taken only by a deliberate grab: a grip (a controller's grip, a bare hand closing) or a
## pinch (a trigger, a bare hand's index pinch) begun with the hand inside its band (`band_of`), never
## by a hand brushing through it, a fingertip's poke or a dwell (`step_hands`). Grabbing a ring mutes
## its track, and the ring goes dim and dashed and says MUTED; grabbing it again unmutes it. Pulling
## it more than PULL (0.4 m) away deletes the layer (DAW.remove_track) and the ring fades. The grab is
## one edit (DAW.open_edit and close_edit), so a pull's mute and delete are one undo step, and so is a
## grab's mute.
##
## At a desk a click on a ring mutes it, and a click again unmutes it. The looper's screen has a
## LAYERS list above it (`LayerList`): each layer by name (`ADA LOOP 2`) with a MUTE key and an X key
## that deletes it, the wheel over the list scrolling it where there are more than ROWS.
##
## A guest's grab asks the host (DAW's intents, as every edit does) and shows its answer at once: the
## mute or the ring's going is predicted here for PREDICT_MS, then the host's mix is the truth.
##
## Each ring has its socket on the modular's patch (slice 53, WorldSocket, `world:ring_N`, N its place
## in the stack from the lowest): on a strip of its own SOCKETS_OUT beside the post, at the ring's
## height and clear of every ring's band, so a grab for a ring never takes a socket. Its layer's own
## notes' velocities over the loop are the level, and each note's start a gate (ModularWorld), patched
## into the modular wall from here.
##
## Its numbers are in the looper's frame (Looper: its origin the middle of the stand's feet, +Z its
## front), and it is the looper's child.

## Where the post stands, across and out from the stand's middle (y unused): back of the middle, so a
## ring round it stays inside the stand's footprint (Looper.STAND_FOOT) and the post is behind the
## screen's sight lines.
const POST := Vector3(0, 0, -0.075)
## A ring: how far across it is outside, how thick its tube is, and so the radius of the tube's middle.
const ACROSS := 0.25
const TUBE := 0.006
const RADIUS := ACROSS * 0.5 - TUBE
## The first ring's height over the stand's feet, how far above it each next is, and the most rings.
const FIRST := 1.0
const STEP := 0.06
const MOST := 8
## The post's top, over the last ring.
const POST_TOP := FIRST + STEP * (MOST - 1) + 0.05
## The top of the last ring there could be, its tube's top: the top of what a desk sees here, so
## Stations' frame's top, which brings the whole stack into view from the looper's seat.
const STACK_TOP := FIRST + STEP * (MOST - 1) + TUBE
## How far beside the post the rings' sockets' strip stands (m, along X), clear of every ring's band,
## and how much smaller than a station's a ring's socket is, to fit a STEP.
const SOCKETS_OUT := 0.21
const SOCKET_SCALE := 0.85
## A hand is inside a ring's band within BAND of the tube's middle, out from the post or in toward it,
## and within half a STEP of its height.
const BAND := 0.05
## A ring pulled further than this (m) from where it was grabbed is deleted.
const PULL := 0.4
## How long (s) a deleted ring takes to fade.
const FADE := 0.5
## How long (ms) a guest's mute or delete is shown before the host's mix has to say so.
const PREDICT_MS := 1500
## A hand that holds a ring and is not seen for this long (s) lets go of it.
const LOST := 0.5
## How many dashes a muted ring is drawn in, and how much of each dash's share of the round it covers.
const DASHES := 12
const DASH_FILL := 0.55
## A muted ring's brightness against a bead's colour: dimmer than any heard ring.
const MUTED_GLOW := 0.4
## The LAYERS list over the screen: its size, its middle across, how far above the screen's top edge
## it begins (along the screen's lean), how many layers it shows at once, its header's and a row's
## height.
const LIST := Vector2(0.385, 0.134)
const LIST_X := -0.0025
const LIST_GAP := 0.004
const ROWS := 3
const HEADER := 0.026
const ROW := 0.034
## A row's keys: MUTE's and X's size, and the gap between them.
const MUTE_KEY := Vector2(0.075, 0.028)
const X_KEY := Vector2(0.04, 0.028)
const KEY_GAP := 0.008
const NAME_SIZE := 72
const HEADER_SIZE := 56
const LABEL_SIZE := 64

## A ring was muted or unmuted, or a layer deleted, here: words for the studio's toast.
signal told(text: String)

## The looper these stand on: its heard song position.
var looper: Looper = null
## The rings, lowest first: one a layer, as the LOOPER folder has them (at most MOST).
var rings: Array[Ring] = []
var list: LayerList = null
## Each ring's socket on the modular's patch (slice 53), lowest first: one a ring.
var sockets: Array[WorldSocket] = []
var _strip: MeshInstance3D = null
## The names the rings were last built for.
var _names: PackedStringArray = []
## Layers deleted here that the host's mix may not have taken out yet: {name: until (msec)}.
var _gone := {}
## Rings fading out after a delete.
var _fading: Array[Ring] = []
## Each hand's last reading: {hand: closed}; when each was last seen, on `_clock`; and what each holds,
## {hand: {"ring": name, "from": Vector3 (this frame), "pulled": bool}}.
var _closed := {}
var _seen := {}
var _held := {}
var _clock := 0.0


func _init() -> void:
	name = "Rings"


func _ready() -> void:
	_build_post()
	list = LayerList.new()
	list.rings = self
	list.name = "Layers"
	list.transform = list_frame()
	add_child(list)
	refresh()


func _process(delta: float) -> void:
	refresh()
	var song := _song()
	var motion := Ergonomics.current.motion_scale if Ergonomics.current != null else 1.0
	var by_name := {}
	for layer: Dictionary in layers(DAW.state):
		by_name[layer["name"]] = layer
	for ring in rings:
		var layer: Dictionary = by_name.get(ring.track_name, {})
		if not layer.is_empty():
			ring.show_layer(layer, song, motion, delta)
	for ring in _fading.duplicate():
		ring.fade_by(delta / FADE)
		if ring.faded():
			_fading.erase(ring)
			ring.queue_free()
	if list != null:
		list.show_layers(shown_layers())


func _physics_process(delta: float) -> void:
	step_hands(hands_in(get_tree()), delta)


# --- where things are -------------------------------------------------------------------------

## Ring `n`'s middle at rest, in the looper's frame.
static func rest_of(n: int) -> Vector3:
	return Vector3(POST.x, FIRST + STEP * n, POST.z)


## The LAYERS list's frame in the looper's: on from the screen's top edge, leant back as it is, across
## the screen and the LENGTH key, +Z out of its face.
static func list_frame() -> Transform3D:
	var lean := Basis(Vector3.RIGHT, -PI * 0.5 + Looper.SCREEN_LEAN)
	var up := lean * Vector3.UP
	var out := lean * Vector3.BACK
	return Looper.deck_frame() * Transform3D(lean, Vector3(LIST_X, 0, Looper.HINGE_Z)
			+ up * (Looper.SCREEN.y + LIST_GAP + LIST.y * 0.5) + out * 0.003)


## The list's top edge's middle, in the looper's frame: the top of what is played at a desk.
static func list_top() -> Vector3:
	return list_frame() * Vector3(0, LIST.y * 0.5, 0)


## Which ring's band a point (the looper's frame) is in, or -1: within BAND of its tube's middle,
## out from the post or in toward it, and within half a STEP of its height. Only rings there are.
func band_of(at: Vector3) -> int:
	var n := roundi((at.y - FIRST) / STEP)
	if n < 0 or n >= rings.size() or absf(at.y - (FIRST + STEP * n)) > STEP * 0.5:
		return -1
	var out := Vector2(at.x - POST.x, at.z - POST.z).length()
	return n if absf(out - RADIUS) <= BAND else -1


## The post the rings stand round, and the rod that holds it: up from the case's back behind the
## screen and the list, over to the post's foot, and the post up to POST_TOP. Named "Post".
func _build_post() -> void:
	var post := Node3D.new()
	post.name = "Post"
	add_child(post)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.1, 0.1, 0.11)
	metal.roughness = 0.4
	metal.metallic = 0.8
	var case_back := Looper.deck_frame() * Vector3(0, -Looper.CASE.y * 0.5, -Looper.CASE.z + 0.01)
	var behind := Vector3(0, list_top().y + 0.012, list_top().z - 0.016)
	var foot := Vector3(POST.x, behind.y + 0.02, POST.z)
	for pair in [[case_back, behind], [behind, foot], [foot, Vector3(POST.x, POST_TOP, POST.z)]]:
		post.add_child(_rod(pair[0], pair[1], 0.007, metal))


static func _rod(from: Vector3, to: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var rod := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = from.distance_to(to)
	mesh.radial_segments = 12
	rod.mesh = mesh
	var along := (to - from).normalized()
	var side := along.cross(Vector3.RIGHT) if absf(along.dot(Vector3.RIGHT)) < 0.9 else along.cross(Vector3.BACK)
	side = side.normalized()
	rod.transform = Transform3D(Basis(along.cross(side).normalized(), along, side), (from + to) * 0.5)
	rod.material_override = material
	return rod


# --- the layers -------------------------------------------------------------------------------

## The looper's layers in `state`: the tracks in its LOOPER folder, in order, each {"index", "name",
## "label" (`label_of`), "muted", "start" and "length" (its first item's, 0 for none)}.
static func layers(state: MixState) -> Array:
	var out: Array = []
	if state == null:
		return out
	var folder := Looper.folder_of(state)
	if folder == 0:
		return out
	var end := Looper.folder_end(state, folder)
	var indices := state.track_indices()
	indices.sort()
	for i in indices:
		if int(i) <= folder or int(i) > end:
			continue
		var t := state.tracks[i] as MixState.TrackState
		var start := 0.0
		var length := 0.0
		if not t.items.is_empty():
			start = (t.items[0] as MixState.ItemState).start
			length = (t.items[0] as MixState.ItemState).length
		out.append({"index": int(i), "name": t.name, "label": label_of(t.name), "muted": t.mute,
				"start": start, "length": length})
	return out


## What a layer's ring is lettered: its player and number (`ADA LOOP 2` is `ADA 2`), or its track's
## name where somebody has called it something else.
static func label_of(track_name: String) -> String:
	var at := track_name.rfind(" LOOP ")
	if at > 0 and track_name.substr(at + 6).is_valid_int():
		return "%s %s" % [track_name.left(at), track_name.substr(at + 6)]
	return track_name


## The layers this stand shows: the folder's, less those deleted here and not yet gone from the mix,
## with a mute predicted here in place of the mix's while its prediction lasts.
func shown_layers() -> Array:
	var now := Time.get_ticks_msec()
	var out: Array = []
	for layer: Dictionary in layers(DAW.state):
		if int(_gone.get(layer["name"], 0)) > now:
			continue
		var ring := ring_named(layer["name"])
		if ring != null:
			layer["muted"] = ring.muted_now(bool(layer["muted"]))
		out.append(layer)
	return out


func ring_named(track_name: String) -> Ring:
	for ring in rings:
		if ring.track_name == track_name:
			return ring
	return null


## The rings stood again for the layers the mix has now (`shown_layers`, the first MOST): one a layer
## in order, a ring kept for a layer that is still there, a new one for a new layer, and one for a
## layer gone taken away.
func refresh() -> void:
	# A delete the mix has taken (the track gone), or one it has not after PREDICT_MS, is done with: an
	# undo that brings the track back brings its ring back.
	var now := Time.get_ticks_msec()
	var there := {}
	for layer: Dictionary in layers(DAW.state):
		there[layer["name"]] = true
	for gone: String in _gone.keys():
		if int(_gone[gone]) <= now or not there.has(gone):
			_gone.erase(gone)
	var shown := shown_layers().slice(0, MOST)
	var names := PackedStringArray()
	for layer: Dictionary in shown:
		names.append(layer["name"])
	if names == _names:
		return
	_names = names
	var kept := {}
	for ring in rings:
		kept[ring.track_name] = ring
	var next: Array[Ring] = []
	for n in shown.size():
		var layer: Dictionary = shown[n]
		var ring: Ring = kept.get(layer["name"])
		if ring == null:
			ring = Ring.new()
			ring.rings = self
			ring.track_name = layer["name"]
			ring.name = "Ring%d" % n
			add_child(ring)
		kept.erase(layer["name"])
		ring.slot = n
		ring.label_text = layer["label"]
		ring.position = rest_of(n) + ring.offset
		next.append(ring)
	for left: String in kept:
		var ring: Ring = kept[left]
		ring.queue_free()
	rings = next
	_show_sockets()


## Ring `n`'s socket's place, in the looper's frame: on the strip beside the post, at the ring's height.
static func socket_of(n: int) -> Vector3:
	return Vector3(POST.x + SOCKETS_OUT, FIRST + STEP * n, POST.z)


## A socket for each ring there is, lowest first, and the strip they stand on up to the highest.
func _show_sockets() -> void:
	while sockets.size() < rings.size():
		var n := sockets.size()
		var socket := WorldSocket.new(Modular.ring_socket(n + 1))
		socket.position = socket_of(n)
		socket.scale = Vector3.ONE * SOCKET_SCALE
		add_child(socket)
		sockets.append(socket)
	while sockets.size() > rings.size():
		var socket: WorldSocket = sockets.pop_back()
		socket.queue_free()
	if _strip != null:
		_strip.queue_free()
		_strip = null
	if sockets.is_empty():
		return
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.1, 0.1, 0.11)
	metal.roughness = 0.4
	metal.metallic = 0.8
	_strip = MeshInstance3D.new()
	_strip.name = "SocketStrip"
	add_child(_strip)
	var foot := Vector3(POST.x, FIRST - STEP * 0.6, POST.z)
	var corner := socket_of(0) + Vector3(0, -STEP * 0.6, -0.012)
	_strip.add_child(_rod(foot, corner, 0.005, metal))
	_strip.add_child(_rod(corner, socket_of(sockets.size() - 1) + Vector3(0, STEP * 0.5, -0.012), 0.005, metal))


# --- what a ring does -------------------------------------------------------------------------

## Layer `track_name`'s track muted, or unmuted where it is muted: asked of the DAW (the host's at
## once, a guest's as an intent) and shown on its ring here at once.
func toggle(track_name: String, by_hand: bool) -> void:
	var layer := _layer_named(track_name)
	if layer.is_empty():
		return
	var ring := ring_named(track_name)
	var muted := not (ring.muted_now(bool(layer["muted"])) if ring != null else bool(layer["muted"]))
	if ring != null:
		ring.predict(muted)
	DAW.set_track_mute(int(layer["index"]), muted)
	var again := "grab it again" if by_hand else "click its ring again"
	told.emit(("%s muted: %s to unmute." % [layer["name"], again]) if muted else ("%s unmuted." % layer["name"]))


## Layer `track_name` deleted: its track taken out of the project (DAW.remove_track), its ring faded.
## `by_hand` (a pull) or a headset says the tape deck's UNDO and its reel's crank bring it back, for
## Ctrl+Z is not to hand there; a desk's toast says Ctrl+Z.
func delete(track_name: String, by_hand := false) -> void:
	var layer := _layer_named(track_name)
	if layer.is_empty():
		return
	DAW.remove_track(int(layer["index"]))
	_gone[track_name] = Time.get_ticks_msec() + PREDICT_MS
	var ring := ring_named(track_name)
	if ring != null:
		rings.erase(ring)
		ring.begin_fade()
		_fading.append(ring)
	_names = PackedStringArray()
	var back := "the tape deck's UNDO or a notch back on its reel's crank brings it back" \
			if by_hand or InstrumentItem.hands_hint else "Ctrl+Z brings it back"
	told.emit("%s deleted: %s." % [layer["name"], back])
	refresh()


## The layer `track_name` is, in the mix now, or {}.
func _layer_named(track_name: String) -> Dictionary:
	for layer: Dictionary in layers(DAW.state):
		if layer["name"] == track_name:
			return layer
	return {}


## The song position the rings turn to: the looper's player's heard one, or the mix's.
func _song() -> float:
	if looper != null:
		var h := looper.heard()
		if bool(h.get("valid", false)):
			return float(h.get("seconds", 0.0))
	return DAW.state.position_seconds if DAW.state != null else 0.0


## How far round (radians) a ring is with its layer from `start` for `length` seconds, at song position
## `song`: its notch at the front at the layer's start and once round a pass, or at `motion` 0, a beat
## at a time.
static func turn_of(state: MixState, start: float, length: float, song: float, motion: float) -> float:
	if length <= 0.0:
		return 0.0
	if motion <= 0.0 and state != null:
		var beats := maxf(roundf(state.beat_at(start + length) - state.beat_at(start)), 1.0)
		var into := fposmod(state.beat_at(song) - state.beat_at(start) + 0.0001, beats)
		return TAU * floorf(into) / beats
	return TAU * fposmod(song - start, length) / length


# --- hands ------------------------------------------------------------------------------------

## This player's hands this frame, each {"hand": its key, "at": where it would take hold (global),
## "closed": gripping or pinching, "busy": carrying something or playing fingertips}: a tracked bare
## hand's palm while it is closed, else its pinch's point; a controller's grip point, closed while its
## grip or its trigger is in. A poke's fingertip is not here: a touch is never a grab.
static func hands_in(tree: SceneTree) -> Array:
	var out: Array = []
	if tree == null:
		return out
	for node in tree.get_nodes_in_group(Interactor.GROUP):
		var hand := node as XRInteractor
		if hand == null or not hand.is_inside_tree():
			continue
		var busy := hand.fingers_play or is_instance_valid(hand.carrying)
		var g := hand.gestures if hand.gestures != null and is_instance_valid(hand.gestures) else null
		if g != null and g.tracked and g.joints.size() >= XRHandTracker.HAND_JOINT_MAX:
			var pinch := (g.pinched & HandPose.INDEX) != 0
			var at: Vector3 = g.palm()
			if pinch and not g.closed:
				at = (g.joints[HandPose.THUMB_TIP] + g.joints[HandPose.TIPS[0]]) * 0.5
			out.append({"hand": g.tracker_name, "at": at, "closed": g.closed or pinch, "busy": busy})
			continue
		var c := hand.controller
		if c == null or not c.is_inside_tree() or hand.bare_hand() or not c.get_has_tracking_data():
			continue
		out.append({"hand": c.tracker, "at": c.global_position, "busy": busy,
				"closed": c.is_button_pressed(hand.grip_action) or c.is_button_pressed(hand.press_action)})
	return out


## One frame of `hands` (as `hands_in` gives them) over `delta`: a hand that closes with its point
## inside a ring's band takes that ring (its track muted or unmuted, one edit opened); a held ring
## follows its hand, and pulled further than PULL from where it was taken is deleted; a hand that
## opens, or goes unseen for LOST, lets go (the edit closed, the ring back in its place). A hand that
## was already closed when it came into a band, or passes through one open, takes nothing.
func step_hands(hands: Array, delta: float) -> void:
	_clock += delta
	for h: Dictionary in hands:
		var key: Variant = h.get("hand", &"")
		var was: bool = _closed.get(key, false)
		var closed: bool = bool(h.get("closed", false))
		_closed[key] = closed
		_seen[key] = _clock
		var at: Vector3 = to_local(h.get("at", Vector3.ZERO)) if is_inside_tree() else h.get("at", Vector3.ZERO)
		if _held.has(key):
			if not closed:
				_let_go(key)
			else:
				_drag(key, at)
			continue
		if not closed or was or bool(h.get("busy", false)):
			continue
		var n := band_of(at)
		if n < 0 or _held.values().any(func(hold: Dictionary) -> bool: return hold["ring"] == rings[n].track_name):
			continue
		_grab(key, rings[n], at)
	for key: Variant in _held.keys():
		if _clock - float(_seen.get(key, _clock)) > LOST:
			_let_go(key)


func _grab(key: Variant, ring: Ring, at: Vector3) -> void:
	_held[key] = {"ring": ring.track_name, "from": at, "pulled": false}
	DAW.open_edit("%s: ring" % ring.track_name)
	toggle(ring.track_name, true)


func _drag(key: Variant, at: Vector3) -> void:
	var hold: Dictionary = _held[key]
	if bool(hold["pulled"]):
		return
	var ring := ring_named(hold["ring"])
	if ring == null:
		return
	var moved: Vector3 = at - hold["from"]
	ring.offset = moved
	ring.position = rest_of(ring.slot) + moved
	if moved.length() > PULL:
		hold["pulled"] = true
		delete(ring.track_name, true)


func _let_go(key: Variant) -> void:
	var hold: Dictionary = _held[key]
	_held.erase(key)
	var ring := ring_named(hold["ring"])
	if ring != null:
		ring.offset = Vector3.ZERO
		ring.position = rest_of(ring.slot)
	DAW.close_edit()


## Whether a hand here holds ring `ring`.
func held(ring: Ring) -> bool:
	return _held.values().any(func(hold: Dictionary) -> bool: return hold["ring"] == ring.track_name)


## A layer's ring: lettered, turning with its layer, as bright as its track is loud, dim and dashed
## while muted. A click mutes it at a desk; a hand takes it by `LooperRings.step_hands`, never by the
## ray's press, a fingertip's touch or a dwell.
class Ring extends ControlAffordance:
	var rings: LooperRings
	## Its layer's track, by name: what it follows as tracks before it come and go.
	var track_name := ""
	## Its place in the stack, 0 the lowest.
	var slot := 0
	## How far its hand has pulled it from its place.
	var offset := Vector3.ZERO
	var label_text := "":
		set(v):
			label_text = v
			_letter()
	## The level it shows, following its track's.
	var level := 0.0
	var turn := 0.0
	var _spin: Node3D
	var _whole: MeshInstance3D
	var _dashed: MeshInstance3D
	var _notch: MeshInstance3D
	var _label: Label3D
	var _lamp: StandardMaterial3D
	var _muted := false
	var _predicted := false
	var _predicted_until := 0
	var _alpha := 1.0

	func _init() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		# Its band, as boxes round the ring, so a click through its middle reaches what is behind.
		for n in DASHES:
			var a := TAU * n / DASHES
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(TAU * RADIUS / DASHES + 0.004, 0.024, 0.024)
			shape.shape = box
			shape.transform = Transform3D(Basis(Vector3.UP, a), Vector3(sin(a), 0, cos(a)) * RADIUS)
			add_child(shape)
		_lamp = StandardMaterial3D.new()
		_lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_lamp.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_lamp.albedo_color = SignalBeads.glow(0.0)
		_spin = Node3D.new()
		_spin.name = "Spin"
		add_child(_spin)
		_whole = _part("Whole", LooperRings.arcs(RADIUS, TUBE, 1, 1.0))
		_dashed = _part("Dashed", LooperRings.arcs(RADIUS, TUBE, DASHES, DASH_FILL))
		_dashed.visible = false
		var tab := BoxMesh.new()
		tab.size = Vector3(0.014, TUBE * 3.2, 0.016)
		_notch = _part("Notch", tab)
		_notch.position = Vector3(0, 0, RADIUS + 0.004)
		_label = Label3D.new()
		_label.name = "Label"
		_label.pixel_size = 0.0002
		_label.font_size = LABEL_SIZE
		_label.modulate = Color(0.95, 0.93, 0.86)
		_label.shaded = false
		_label.double_sided = false
		_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Beside the ring on its left, out of the way of the tube's front and the notch passing it, and
		# on the open floor's side of the stand rather than over the drums.
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_label.position = Vector3(-RADIUS - TUBE - 0.012, 0, 0.03)
		Lettering.range_to_legibility(_label)
		add_child(_label)

	func _part(named: String, mesh: Mesh) -> MeshInstance3D:
		var m := MeshInstance3D.new()
		m.name = named
		m.mesh = mesh
		m.material_override = _lamp
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_spin.add_child(m)
		return m

	func _letter() -> void:
		if _label != null:
			_label.text = "%s  MUTED" % label_text if _muted else label_text

	## What it shows for `layer` (LooperRings.layers'), at song position `song` and `motion`, a frame
	## of `delta` on: its turn, its level, and whether it is muted.
	func show_layer(layer: Dictionary, song: float, motion: float, delta: float) -> void:
		var muted := muted_now(bool(layer["muted"]))
		var target := SignalBeads.track_level(int(layer["index"])) if not muted else 0.0
		var rate := SignalBeads.ATTACK if target > level else SignalBeads.RELEASE
		level += (target - level) * (1.0 - exp(-rate * maxf(delta, 0.0)))
		turn = LooperRings.turn_of(DAW.state, float(layer["start"]), float(layer["length"]), song, motion)
		_spin.rotation.y = -turn
		show_muted(muted)

	## Dim and dashed, lettered MUTED, while `muted`; whole, as bright as its level, while heard.
	func show_muted(muted: bool) -> void:
		if muted != _muted:
			_muted = muted
			_letter()
		_whole.visible = not muted
		_dashed.visible = muted
		var c := SignalBeads.COLOUR * MUTED_GLOW if muted else SignalBeads.glow(level)
		c.a = _alpha
		_lamp.albedo_color = c
		_label.modulate.a = _alpha

	func muted() -> bool:
		return _muted

	## How bright it is drawn now (its lamp's value), for the suite.
	func brightness() -> float:
		return _lamp.albedo_color.v

	## Whether it is drawn dashed.
	func dashed() -> bool:
		return _dashed.visible

	func notch_point() -> Vector3:
		return _notch.global_position

	## Muted as asked here, shown until the mix says so or PREDICT_MS goes by.
	func predict(muted_too: bool) -> void:
		_predicted = muted_too
		_predicted_until = Time.get_ticks_msec() + PREDICT_MS
		show_muted(muted_too)

	## Whether it is muted, the mix saying `in_mix`: as predicted here while that lasts and the mix has
	## not caught up, else as the mix has it.
	func muted_now(in_mix: bool) -> bool:
		if _predicted_until > 0 and Time.get_ticks_msec() < _predicted_until and in_mix != _predicted:
			return _predicted
		_predicted_until = 0
		return in_mix

	func begin_fade() -> void:
		for child in get_children():
			if child is CollisionShape3D:
				(child as CollisionShape3D).disabled = true

	func fade_by(fraction: float) -> void:
		_alpha = maxf(_alpha - fraction, 0.0)
		show_muted(_muted)

	func faded() -> bool:
		return _alpha <= 0.0

	func personal() -> bool:
		return true

	func _default_title() -> String:
		return track_name

	func _default_readout() -> String:
		return "muted · a loop layer" if _muted else "a loop layer, playing"

	func hint() -> String:
		if InstrumentItem.hands_hint:
			return "grab it (grip or pinch, your hand in the ring) to mute, again to unmute · pull it %d cm away to delete it" % roundi(PULL * 100.0)
		return "click to %s · X on the looper's LAYERS list deletes it" % ("unmute" if _muted else "mute")

	## A click at a desk mutes or unmutes it. A headset's ray, a fingertip's touch and a dwell take
	## nothing: a hand grabs a ring only with the hand in it (LooperRings.step_hands).
	func _on_grab_begin(_at: Vector3) -> void:
		var by := held_by
		grab_end(by)
		if by is XRInteractor or by is PokeInteractor or rings == null:
			return
		rings.toggle(track_name, false)


## A tube round the post's axis, `radius` to its middle and `tube` thick, in `count` arcs each `fill`
## of its share of the round (1 and 1.0 for a whole ring): one surface.
static func arcs(radius: float, tube: float, count: int, fill: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 48 / count + 2
	var around := 8
	for c in count:
		var from := TAU * c / count
		var to := from + TAU / count * fill
		for i in along:
			var a0 := lerpf(from, to, float(i) / along)
			var a1 := lerpf(from, to, float(i + 1) / along)
			for j in around:
				var b0 := TAU * j / around
				var b1 := TAU * (j + 1) / around
				var quad := [_on_tube(radius, tube, a0, b0), _on_tube(radius, tube, a1, b0),
						_on_tube(radius, tube, a1, b1), _on_tube(radius, tube, a0, b1)]
				for k in [0, 1, 2, 0, 2, 3]:
					st.set_normal(quad[k][1])
					st.add_vertex(quad[k][0])
	return st.commit()


## A point on a tube of `tube` round a circle of `radius` (y up the axis), `a` round the circle and `b`
## round the tube: [point, normal].
static func _on_tube(radius: float, tube: float, a: float, b: float) -> Array:
	var out := Vector3(sin(a), 0, cos(a))
	var normal := out * cos(b) + Vector3.UP * sin(b)
	return [out * radius + normal * tube, normal]


## The LAYERS list over the looper's screen: every layer by name with a MUTE key and an X key, ROWS at
## a time, the wheel on a key scrolling it; a header saying how many there are.
class LayerList extends Node3D:
	var rings: LooperRings
	## The first layer shown.
	var from := 0
	var header: Label3D
	var names: Array[Label3D] = []
	var mutes: Array[ListKey] = []
	var deletes: Array[ListKey] = []
	var _shown: Array = []

	func _ready() -> void:
		var glass := MeshInstance3D.new()
		glass.name = "Glass"
		var pane := BoxMesh.new()
		pane.size = Vector3(LIST.x, LIST.y, 0.002)
		glass.mesh = pane
		glass.position = Vector3(0, 0, -0.001)
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.03, 0.04, 0.04)
		dark.roughness = 0.45
		dark.metallic = 0.2
		glass.material_override = dark
		add_child(glass)
		header = _label("Header", HEADER_SIZE, Vector3(-LIST.x * 0.5 + 0.012, LIST.y * 0.5 - HEADER * 0.5, 0.0008))
		add_child(header)
		for k in ROWS:
			var y := LIST.y * 0.5 - HEADER - ROW * (k + 0.5)
			var name_label := _label("Name%d" % k, NAME_SIZE, Vector3(-LIST.x * 0.5 + 0.012, y, 0.0008))
			add_child(name_label)
			names.append(name_label)
			var x_at := LIST.x * 0.5 - 0.012 - X_KEY.x * 0.5
			var mute_at := x_at - X_KEY.x * 0.5 - KEY_GAP - MUTE_KEY.x * 0.5
			var mute := ListKey.new(self, k, ListKey.MUTE, MUTE_KEY)
			mute.name = "Mute%d" % k
			mute.position = Vector3(mute_at, y, 0.004)
			add_child(mute)
			mutes.append(mute)
			var x := ListKey.new(self, k, ListKey.DELETE, X_KEY)
			x.name = "Delete%d" % k
			x.position = Vector3(x_at, y, 0.004)
			add_child(x)
			deletes.append(x)
		show_layers([])

	func _label(named: String, size: int, at: Vector3) -> Label3D:
		var l := Label3D.new()
		l.name = named
		l.pixel_size = 0.0002
		l.font_size = size
		l.modulate = Color(0.92, 0.95, 0.88)
		l.shaded = false
		l.double_sided = false
		l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.position = at
		Lettering.range_to_legibility(l)
		return l

	## The layers now (LooperRings.shown_layers): ROWS of them from `from`, each its name (`· MUTED`
	## while it is) and its keys; the rest of the rows and their keys hidden.
	func show_layers(layers: Array) -> void:
		from = clampi(from, 0, maxi(layers.size() - ROWS, 0))
		var said := []
		for layer: Dictionary in layers:
			said.append([layer["name"], layer["muted"]])
		said.append(from)
		if said == _shown:
			return
		_shown = said
		if layers.is_empty():
			header.text = "LAYERS: NONE YET · SLAP TO LOOP"
		elif layers.size() <= ROWS:
			header.text = "LAYERS · %d" % layers.size()
		else:
			header.text = "LAYERS %d-%d OF %d · WHEEL SCROLLS" % [from + 1, mini(from + ROWS, layers.size()), layers.size()]
		Lettering.fit(header, LIST.x - 0.024, HEADER_SIZE, 30)
		for k in ROWS:
			var at := from + k
			var there := at < layers.size()
			names[k].visible = there
			mutes[k].visible = there
			deletes[k].visible = there
			if not there:
				continue
			var layer: Dictionary = layers[at]
			names[k].text = "%s · MUTED" % layer["name"] if bool(layer["muted"]) else str(layer["name"])
			Lettering.fit(names[k], LIST.x - 0.036 - MUTE_KEY.x - X_KEY.x - KEY_GAP * 2.0, NAME_SIZE, 34)
			mutes[k].show_muted(bool(layer["muted"]))

	## The layer row `k` shows now, or {}.
	func layer_at(k: int) -> Dictionary:
		var layers := rings.shown_layers() if rings != null else []
		return layers[from + k] if from + k < layers.size() else {}

	func scroll(by: int) -> bool:
		var count := rings.shown_layers().size() if rings != null else 0
		var was := from
		from = clampi(from + by, 0, maxi(count - ROWS, 0))
		return from != was


## A key on a LAYERS row: MUTE (mute or unmute that layer) or X (delete it). The wheel scrolls the list.
class ListKey extends ControlAffordance:
	const MUTE := 0
	const DELETE := 1
	var list: LayerList
	var row := 0
	var kind := MUTE
	var legend: Label3D
	var _face: MeshInstance3D
	var _size := Vector2.ZERO

	func _init(on: LayerList = null, k := 0, what := MUTE, size := MUTE_KEY) -> void:
		list = on
		row = k
		kind = what
		_size = size
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(size.x, size.y, 0.012)
		shape.shape = box
		add_child(shape)
		_face = MeshInstance3D.new()
		_face.name = "Face"
		var slab := BoxMesh.new()
		slab.size = Vector3(size.x - 0.004, size.y - 0.004, 0.005)
		_face.mesh = slab
		_face.position = Vector3(0, 0, -0.002)
		var cap := StandardMaterial3D.new()
		cap.albedo_color = Color(0.32, 0.3, 0.27)
		cap.roughness = 0.6
		_face.material_override = cap
		add_child(_face)
		legend = Label3D.new()
		legend.name = "Legend"
		legend.text = "MUTE" if kind == MUTE else "X"
		legend.pixel_size = 0.0002
		legend.font_size = 64
		legend.modulate = Color(0.95, 0.92, 0.84)
		legend.shaded = false
		legend.double_sided = false
		legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		legend.position = Vector3(0, 0, 0.0008)
		Lettering.range_to_legibility(legend)
		add_child(legend)

	## MUTE says MUTED and sits sunk in while its layer is muted: by its word and its depth, not colour.
	func show_muted(muted: bool) -> void:
		if kind != MUTE:
			return
		legend.text = "MUTED" if muted else "MUTE"
		Lettering.fit(legend, _size.x - 0.008, 64, 36)
		_face.position.z = -0.005 if muted else -0.002
		legend.position.z = -0.0022 if muted else 0.0008

	func personal() -> bool:
		return true

	func dwell_activates() -> bool:
		return kind == MUTE

	func _layer() -> Dictionary:
		return list.layer_at(row) if list != null else {}

	func _default_title() -> String:
		var layer := _layer()
		var what := "MUTE" if kind == MUTE else "DELETE"
		return "%s  %s" % [layer.get("name", "LOOP LAYER"), what]

	func _default_readout() -> String:
		var layer := _layer()
		if layer.is_empty():
			return ""
		if kind == DELETE:
			return "takes the layer's track out of the project"
		return "muted" if bool(layer["muted"]) else "playing"

	func hint() -> String:
		if kind == DELETE:
			return "press to delete this layer (Ctrl+Z brings it back) · the wheel scrolls the list"
		return "press to mute or unmute this layer · its ring on the post does the same · the wheel scrolls the list"

	func _on_grab_begin(_at: Vector3) -> void:
		var by := held_by
		grab_end(by)
		var layer := _layer()
		if layer.is_empty() or list == null or list.rings == null:
			return
		if kind == DELETE:
			list.rings.delete(layer["name"])
		else:
			list.rings.toggle(layer["name"], false)

	func _on_nudge(notches: int, _fine: bool) -> bool:
		return list != null and list.scroll(-signi(notches))
