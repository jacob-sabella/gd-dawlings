class_name SurfacePads
extends Node3D

## Drum pads on anything (docs/spatial_loop.md part two, slice 41, idea #10): up to MOST pads this
## player has marked on real surfaces, a desk, a crate's side, a knee, each a 6 cm disk
## (KitItem.PAD_RADIUS) that plays the room's kit (KitItem) when it is struck.
##
## They are this machine's, since the surfaces are this person's own: kept in the session frame
## (RoomAnchor, through `frame`), so a pad stays on the real surface it was marked on however the
## play space has travelled, and is where it was after the room is calibrated again (a pad marked on
## a calibrated room comes back on the same surface next time, which is calibrated against the same
## marks); and saved here (`path`, user://pads.cfg), never in the room. Nobody else sees them, and
## a bandmate's hit on one is heard from their ghost (KitItem.heard_at).
##
## MARKING. The PADS card on the desk (`build_card`, under the rail's pads) has a MARK key. While
## it is on (`marking`), a bare hand's index fingertip, or a controller's tip (XRRig.TIP_OFFSET) with
## its trigger held (`mark_points`), touching a surface and held still for DWELL marks a pad there
## (`dwell`): a ring at the tip fills as it is held. Its face is the surface: level where the tip
## came down onto it from above (within LEVEL_WITHIN of straight down), or across the way the tip
## came in, for a crate's side or a knee reached from the front (`plane_of`). Its drum is the next of
## KitItem.DRUMS no pad has yet. Held still on a pad already there, the dwell takes it away. While
## marking, a strike on a pad steps it on to its next drum and rings that (KitItem.strike), so a
## pad's drum is set by tapping it, and the hand may rest there after without its dwell taking the
## pad away (`tapped`); a controller's stick, or the mouse wheel, over a pad steps it either way at
## any time (its nudge, `Pad`). The drum is lettered on it. CLEAR, pressed twice, takes them all
## away.
##
## At a desk there are no hands to mark with (`hands` false): the MARK key says so, and the rail's
## six pads, clicked or struck with 4 to 9, are the desk's.

## Something about the pads changed: one marked, taken away, a drum stepped, all cleared.
signal changed()
## Something for this player to be told: the studio's toast.
signal told(text: String)

const MOST := 8
## How long a fingertip or a controller's tip is held still on a surface to mark a pad there (s),
## how far it may wander meanwhile and still be still (m), and how far back before it went still its
## approach is read from (s).
const DWELL := 0.6
const STILL := 0.012
const APPROACH := 0.2
## A point that has marked must move this far from where it marked before it marks again (m).
const AWAY := 0.05
## A dwell this near a pad's middle is on that pad, and takes it away (m).
const NEAR := 0.045
## An approach within this many degrees of straight down marks a level pad.
const LEVEL_WITHIN := 40.0
## How far out of the surface a pad's face is, from where the tip was held (m): a tap the real
## surface stops where the tip rested still crosses it (Strike).
const LIFT := 0.006
const PATH := "user://pads.cfg"
## The card under the rail's pads: its size, its lettering's caps, its keys.
const CARD := Vector2(0.27, 0.075)
const CARD_TILT := 50.0
const KEY := Vector2(0.075, 0.028)
const MARK := &"mark"
const CLEAR := &"clear"
## How soon a second press of CLEAR must follow the first to take the pads away (s).
const CLEAR_SURE := 3.0

## Where they are saved; the suite points it elsewhere.
var path := PATH
## Each pad, in the session frame: {at: Vector3, normal: Vector3 (out of the surface), toward:
## Vector3 (along the surface, the way its letters' feet face: toward where its marker stood),
## drum: StringName}.
var pads: Array = []
## Whether this player's hands are marking pads (MARK).
var marking := false
## Whether this machine has hands to mark with: a headset. At a desk the MARK key says how a desk
## plays the pads instead.
var hands := false
## () -> Transform3D: the session frame in global space, where the pads are now (the studio's:
## RoomAnchor, moved by however far the play space has travelled). Unset, this node's own.
var frame: Callable = Callable()
## () -> Vector3: where this player's eye is (global), for which way a new pad's letters read.
var eye: Callable = Callable()
## The kit the pads play (KitItem), for a click on one.
var kit: KitItem = null
## The card's keys and its status line, once built.
var card: Node3D = null

## Each marking point's recent path, {key: [[seconds, Vector3 global], ...]}, and where each last
## marked, {key: Vector3}, until it moves AWAY.
var _history := {}
var _spent := {}
## How far each point's dwell has got, {key: [0..1, Vector3 global]}, for its ring.
var _progress := {}
var _clock := 0.0
## When CLEAR was first pressed (s, on the engine's clock), waiting for its second, or -1.
var _clear_asked := -1.0
var _drawn: Node3D
var _rings: Array[MeshInstance3D] = []


func _ready() -> void:
	_drawn = Node3D.new()
	_drawn.name = "Pads"
	add_child(_drawn)
	load_pads()
	_follow_frame()
	redraw()


func _physics_process(delta: float) -> void:
	_follow_frame()
	if marking:
		dwell(mark_points(get_tree()), delta)
	_show_rings()


func _follow_frame() -> void:
	if frame.is_valid():
		var at: Variant = frame.call()
		if at is Transform3D and not (at as Transform3D).is_equal_approx(global_transform):
			global_transform = at


# --- marking ----------------------------------------------------------------------------------

## The points that mark, this frame, in global space: each confidently tracked bare hand's index
## fingertip, and each controller's tip while its trigger is held and its pose is tracked, as
## {[hand, part]: Vector3}, keyed as Strike.points keys them. A controller whose trigger is holding a
## control or carrying an item is busy with that, not marking.
static func mark_points(tree: SceneTree) -> Dictionary:
	var out := {}
	if tree == null:
		return out
	for node in tree.get_nodes_in_group(HandGestures.GROUP):
		var g := node as HandGestures
		if g == null or not g.tracked or not g.confident or g.joints.size() < XRHandTracker.HAND_JOINT_MAX:
			continue
		out[[g.tracker_name, 0]] = g.joints[HandPose.TIPS[0]]
	for node in tree.get_nodes_in_group(Interactor.GROUP):
		var hand := node as XRInteractor
		if hand == null or hand.bare_hand() or hand.held != null or hand.carrying != null:
			continue
		var c := hand.controller
		if c == null or not c.is_inside_tree() or not Strike.controller_sure(c) \
				or not c.is_button_pressed(XRRig.PRESS_ACTION):
			continue
		out[[c.tracker, &"tip"]] = c.global_transform * XRRig.TIP_OFFSET
	return out


## One frame, `delta` on from the last, of the marking points `now` ({key: Vector3 global},
## `mark_points`): each held still for DWELL marks a pad where it is, or takes away the pad it is
## on. Nothing while not marking. The suite gives its own points.
func dwell(now: Dictionary, delta: float) -> void:
	if not marking:
		return
	_clock += delta
	for key in _history.keys():
		if not now.has(key):
			_history.erase(key)
			_spent.erase(key)
			_progress.erase(key)
	for key in now:
		var p: Vector3 = now[key]
		var path_of: Array = _history.get(key, [])
		path_of.append([_clock, p])
		while path_of.size() > 2 and _clock - float(path_of[0][0]) > DWELL + APPROACH + 0.1:
			path_of.pop_front()
		_history[key] = path_of
		if _spent.has(key):
			if p.distance_to(_spent[key]) <= AWAY:
				continue
			_spent.erase(key)
		# How long it has been within STILL of where it is now, and the last place it was not.
		var since := _clock
		var i := path_of.size() - 1
		while i >= 0 and (path_of[i][1] as Vector3).distance_to(p) <= STILL:
			since = float(path_of[i][0])
			i -= 1
		var held := _clock - since
		_progress[key] = [clampf(held / DWELL, 0.0, 1.0), p]
		if held + 0.0001 < DWELL:
			continue
		# Where it came from: the point APPROACH before it went still, or the oldest kept; none (a
		# point that was still from the first frame it was seen) is a level pad.
		var before := p
		for j in range(i, -1, -1):
			before = path_of[j][1]
			if since - float(path_of[j][0]) >= APPROACH:
				break
		_mark_or_take(p, p - before)
		_spent[key] = p
		_progress.erase(key)


## Pad `n` struck while marking, which stepped its drum (KitItem.strike): each marking point at it
## is spent there, as if it had just marked, so it must move AWAY from the pad before its dwell
## counts again. A hand rests where it tapped; that rest is not the dwell that takes the pad away.
## Only a fresh landing on it, one that struck nothing, does.
func tapped(n: int) -> void:
	if n < 0 or n >= pads.size():
		return
	var middle := global_transform * (pads[n]["at"] as Vector3)
	for key in _history:
		var path_of: Array = _history[key]
		# Its last point may be the frame before it crossed the face, a fast tap's few cm above it.
		if not path_of.is_empty() and (path_of[-1][1] as Vector3).distance_to(middle) <= NEAR + AWAY:
			_spent[key] = middle
			_progress.erase(key)


## The way out of a surface a tip came to rest on after moving `approach` (global): up, for a tip
## that came down onto it from above (within LEVEL_WITHIN of straight down) or one that did not move;
## back along the way it came, for one that came in across it (a crate's side, a knee from the front).
static func plane_of(approach: Vector3) -> Vector3:
	if approach.length() < 0.005:
		return Vector3.UP
	var way := approach.normalized()
	if way.dot(Vector3.DOWN) >= cos(deg_to_rad(LEVEL_WITHIN)):
		return Vector3.UP
	return -way


func _mark_or_take(at: Vector3, approach: Vector3) -> void:
	var local := global_transform.affine_inverse() * at
	var on := nearest(local)
	if on >= 0:
		var drum: StringName = pads[on]["drum"]
		pads.remove_at(on)
		_changed()
		told.emit("Pad taken away (%s): %d left." % [KitItem.TITLES.get(drum, String(drum)), pads.size()])
		return
	if pads.size() >= MOST:
		told.emit("Eight pads already: hold still on one to take it away, or CLEAR them.")
		return
	var out := plane_of(approach)
	var normal := (global_transform.basis.inverse() * out).normalized()
	# Its letters' feet toward where its marker's eye was, along the surface.
	var looking := (eye.call() as Vector3) if eye.is_valid() else at + Vector3.BACK
	var toward := global_transform.basis.inverse() * (looking - at)
	toward = (toward - normal * toward.dot(normal))
	if toward.length() < 0.001:
		toward = Vector3.BACK - normal * Vector3.BACK.dot(normal)
		if toward.length() < 0.001:
			toward = Vector3.RIGHT
	var drum := next_drum()
	pads.append({"at": local, "normal": normal, "toward": toward.normalized(), "drum": drum})
	_changed()
	told.emit("Pad %d marked: %s. Tap it for the next drum while marking; MARK again to stop." %
			[pads.size(), KitItem.TITLES[drum]])


## The pad whose middle is within NEAR of `local` (the session frame), nearest first, or -1.
func nearest(local: Vector3) -> int:
	var best := NEAR
	var out := -1
	for n in pads.size():
		var d := local.distance_to(pads[n]["at"])
		if d <= best:
			best = d
			out = n
	return out


## The drum a new pad takes: the first of KitItem.DRUMS no pad is yet, or round them again.
func next_drum() -> StringName:
	var taken := pads.map(func(p: Dictionary) -> StringName: return p["drum"])
	for drum in KitItem.DRUMS:
		if not (drum in taken):
			return drum
	return KitItem.DRUMS[pads.size() % KitItem.DRUMS.size()]


## Pad `n`'s drum.
func drum_of(n: int) -> StringName:
	return pads[n]["drum"] if n >= 0 and n < pads.size() else &""


## Pad `n` on `way` drums (1 the next, -1 the one before, a notch of the wheel each): its new drum.
func step_drum(n: int, way: int) -> StringName:
	if n < 0 or n >= pads.size():
		return &""
	var at := KitItem.DRUMS.find(pads[n]["drum"])
	var drum := KitItem.DRUMS[posmod(at + way, KitItem.DRUMS.size())]
	pads[n]["drum"] = drum
	_changed()
	return drum


## Every pad taken away.
func clear() -> void:
	pads.clear()
	_changed()


func set_marking(on: bool) -> void:
	marking = on and hands
	_history.clear()
	_spent.clear()
	_progress.clear()
	_show_card()


## The card's key `kind` pressed (MARK or CLEAR).
func press(kind: StringName) -> void:
	match kind:
		MARK:
			if not hands:
				told.emit("Pads are marked on real surfaces in a headset. Here, click the rail's pads or press 4 to 9.")
				return
			set_marking(not marking)
			told.emit("Marking: touch a surface with a fingertip, or a controller's tip with its trigger held, and hold still. MARK again to stop."
					if marking else "Pads: %d marked." % pads.size())
		CLEAR:
			var had := pads.size()
			if had == 0:
				told.emit("No pads marked yet.")
				return
			# It sits beside MARK and has no undo, so it asks once: a second press within CLEAR_SURE.
			var now := Time.get_ticks_msec() / 1000.0
			if _clear_asked < 0.0 or now - _clear_asked > CLEAR_SURE:
				_clear_asked = now
				told.emit("Press CLEAR again to take away all %d pads." % had)
				return
			_clear_asked = -1.0
			clear()
			told.emit("All %d pads taken away." % had)


func _changed() -> void:
	save_pads()
	redraw()
	_show_card()
	changed.emit()


# --- where a strike lands -----------------------------------------------------------------------

## Pad `n`'s frame, global: its origin LIFT out of the surface over where it was marked, its +Y out of
## the surface, its +Z the way its letters' feet face.
func pad_frame(n: int) -> Transform3D:
	var p: Dictionary = pads[n]
	var y: Vector3 = (global_transform.basis * (p["normal"] as Vector3)).normalized()
	var z: Vector3 = global_transform.basis * (p["toward"] as Vector3)
	z = (z - y * z.dot(y)).normalized()
	var x := y.cross(z).normalized()
	return Transform3D(Basis(x, y, z), global_transform * ((p["at"] as Vector3) + (p["normal"] as Vector3) * LIFT))


## Each pad as a face for Strike (InstrumentItem.faces): {frame, radius, drum, marked}.
func faces() -> Array:
	var out: Array = []
	for n in pads.size():
		out.append({"frame": pad_frame(n), "radius": KitItem.PAD_RADIUS, "drum": pads[n]["drum"], "marked": n})
	return out


# --- kept here ----------------------------------------------------------------------------------

func save_pads() -> void:
	var rows: Array = []
	for p: Dictionary in pads:
		var at: Vector3 = p["at"]
		var n: Vector3 = p["normal"]
		var t: Vector3 = p["toward"]
		rows.append([at.x, at.y, at.z, n.x, n.y, n.z, t.x, t.y, t.z, String(p["drum"])])
	var file := ConfigFile.new()
	file.set_value("pads", "rows", rows)
	file.save(path)


## The pads saved here, each checked: a row that is not ten numbers and a drum is left out.
func load_pads() -> void:
	pads.clear()
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return
	var rows: Variant = file.get_value("pads", "rows", [])
	if not (rows is Array):
		return
	for row: Variant in rows:
		if not (row is Array) or (row as Array).size() != 10 or pads.size() >= MOST:
			continue
		var r: Array = row
		var drum := StringName(str(r[9]))
		var numbers := r.slice(0, 9)
		if not (drum in KitItem.DRUMS) or not numbers.all(func(v: Variant) -> bool: return v is float or v is int):
			continue
		var n := Vector3(r[3], r[4], r[5])
		var t := Vector3(r[6], r[7], r[8])
		if n.length() < 0.5 or t.length() < 0.5:
			continue
		pads.append({"at": Vector3(r[0], r[1], r[2]), "normal": n.normalized(), "toward": t.normalized(), "drum": drum})


# --- drawn --------------------------------------------------------------------------------------

## Each pad drawn where it is: a disk on the surface with its drum lettered on it, and its own reach
## for a ray (Pad).
func redraw() -> void:
	if _drawn == null:
		return
	for child in _drawn.get_children():
		_drawn.remove_child(child)
		child.queue_free()
	for n in pads.size():
		var pad := Pad.new()
		pad.name = "Pad%d" % n
		pad.pads = self
		pad.index = n
		_drawn.add_child(pad)
		var f := global_transform.affine_inverse() * pad_frame(n)
		pad.transform = Transform3D(f.basis, f.origin - f.basis.y * LIFT)


func _show_rings() -> void:
	var showing: Array = _progress.values().filter(func(p: Array) -> bool: return marking and float(p[0]) > 0.15)
	while _rings.size() < showing.size():
		var ring := MeshInstance3D.new()
		ring.name = "Dwell"
		var torus := TorusMesh.new()
		torus.inner_radius = KitItem.PAD_RADIUS * 0.85
		torus.outer_radius = KitItem.PAD_RADIUS
		ring.mesh = torus
		var glow := StandardMaterial3D.new()
		glow.albedo_color = Color(0.95, 0.85, 0.5)
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = glow
		ring.top_level = true
		add_child(ring)
		_rings.append(ring)
	for n in _rings.size():
		var ring := _rings[n]
		ring.visible = n < showing.size()
		if ring.visible:
			# A ring at the tip that closes in to a pad's size as the dwell fills: its state, not a flash.
			var share := float(showing[n][0])
			ring.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * lerpf(2.0, 1.0, share)),
					showing[n][1] as Vector3)


## The PADS card: its title, a line saying what MARK does now, and its two keys, MARK and CLEAR,
## facing +Z, its top edge at its origin. The studio hangs it off the rail under the kit's pads.
func build_card() -> Node3D:
	card = Node3D.new()
	card.name = "PadsCard"
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	var box := BoxMesh.new()
	box.size = Vector3(CARD.x, CARD.y, 0.006)
	plate.mesh = box
	plate.position = Vector3(0, -CARD.y * 0.5, -0.003)
	var ink := StandardMaterial3D.new()
	ink.albedo_color = Color(0.07, 0.065, 0.06)
	ink.roughness = 0.6
	plate.material_override = ink
	card.add_child(plate)
	var title := _card_label("DRUM PADS · 4 to 9", 0.009, Color(0.95, 0.9, 0.78))
	title.name = "Title"
	title.position = Vector3(0, -0.009, 0.001)
	card.add_child(title)
	var line := _card_label("", 0.0068, Color(0.86, 0.84, 0.8))
	line.name = "Line"
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.width = (CARD.x - 0.02) / line.pixel_size
	line.position = Vector3(0, -0.022, 0.001)
	line.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	card.add_child(line)
	for kind in [MARK, CLEAR]:
		var key := CardKey.new()
		key.name = "Mark" if kind == MARK else "Clear"
		key.pads = self
		key.kind = kind
		key.position = Vector3((-1.0 if kind == MARK else 1.0) * (KEY.x * 0.5 + 0.008), -CARD.y + KEY.y * 0.5 + 0.006, 0)
		card.add_child(key)
	_show_card()
	return card


## What the card's line and MARK key say now: marking or not, how many pads, or at a desk how a desk
## plays them. The key says MARKING while it is on, not only lit.
func _show_card() -> void:
	if card == null or not is_instance_valid(card):
		return
	var line := card.get_node_or_null("Line") as Label3D
	if line != null:
		if not hands:
			line.text = "click a pad or press 4 to 9: the drum track · MARK is a headset's"
		elif marking:
			line.text = "MARKING · touch a surface, hold still · %d of %d · on a pad: tap for its drum, hold to take it away" % [pads.size(), MOST]
		else:
			line.text = "MARK, then touch a desk, a crate, a knee and hold still · %d of %d marked" % [pads.size(), MOST]
	var key := card.get_node_or_null("Mark/Legend") as Label3D
	if key != null:
		key.text = "MARKING" if marking else "MARK"


static func _card_label(text: String, cap: float, colour: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = 0.0001
	l.font_size = roundi(cap / l.pixel_size)
	l.modulate = colour
	l.outline_size = 0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.double_sided = false
	Lettering.range_to_legibility(l)
	return l


## A marked pad, for a ray: a click, a trigger or a pinch aimed at it strikes it (a fingertip's touch
## is Strike's, as it crosses the face), and a stick or the wheel over it steps its drum. Each
## player's own: nobody else has it.
class Pad extends ControlAffordance:
	var pads: SurfacePads = null
	var index := 0

	func _ready() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		var drum := pads.drum_of(index)
		var rubber := StandardMaterial3D.new()
		rubber.albedo_color = KitItem.RUBBER
		rubber.roughness = 0.95
		var disk := MeshInstance3D.new()
		disk.name = "Disk"
		var mesh := CylinderMesh.new()
		mesh.top_radius = KitItem.PAD_RADIUS
		mesh.bottom_radius = KitItem.PAD_RADIUS
		mesh.height = 0.002
		mesh.radial_segments = 32
		disk.mesh = mesh
		disk.position = Vector3(0, 0.001, 0)
		disk.material_override = rubber
		add_child(disk)
		var ring := MeshInstance3D.new()
		ring.name = "Edge"
		var torus := TorusMesh.new()
		torus.inner_radius = KitItem.PAD_RADIUS - 0.002
		torus.outer_radius = KitItem.PAD_RADIUS + 0.001
		ring.mesh = torus
		var rim := StandardMaterial3D.new()
		rim.albedo_color = KitItem.INK
		rim.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = rim
		ring.position = Vector3(0, 0.002, 0)
		ring.scale = Vector3(1, 0.3, 1)
		add_child(ring)
		add_child(KitItem.pad_lettering(KitItem.TITLES.get(drum, ""), "PAD %d" % (index + 1), Vector3(0, 0.0026, 0)))
		var shape := CollisionShape3D.new()
		var reach := CylinderShape3D.new()
		reach.radius = KitItem.PAD_RADIUS
		reach.height = 0.02
		shape.shape = reach
		add_child(shape)
		describe_title = func() -> String: return "PAD %d  %s" % [index + 1, KitItem.TITLES.get(pads.drum_of(index), "")]
		describe_value = func(_v: float) -> String: return "on a real surface, yours alone"

	func hint() -> String:
		return "strike it · the stick or the wheel over it for another drum"

	func personal() -> bool:
		return true

	func _on_grab_begin(_at: Vector3) -> void:
		var hand := held_by as Interactor
		grab_end(held_by)
		if hand == null or hand.touches_directly() or pads.kit == null:
			return
		pads.kit.strike_marked(index, Strike.click_velocity(hand), InstrumentItem.side_of(hand))

	func _on_nudge(notches: int, _fine: bool) -> bool:
		return pads.step_drum(index, notches) != &""


## The card's MARK and CLEAR keys.
class CardKey extends ControlAffordance:
	var pads: SurfacePads = null
	var kind := MARK

	func _ready() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		StationBoard.dress_key(self, KEY, "MARK" if kind == MARK else "CLEAR", 0.009)
		pads._show_card()

	func _default_title() -> String:
		return "DRUM PADS  %s" % ("MARK" if kind == MARK else "CLEAR")

	func hint() -> String:
		if kind == CLEAR:
			return "press twice to take away every pad you have marked"
		if not pads.hands:
			return "pads on real surfaces are marked in a headset · here, click the rail's pads or 4 to 9"
		return "press, then touch a surface and hold still for a pad there · press again to stop"

	func dwell_activates() -> bool:
		return true

	func personal() -> bool:
		return true

	func _on_grab_begin(_at: Vector3) -> void:
		pads.press(kind)
