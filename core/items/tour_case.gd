class_name TourCase
extends Node3D

## The road case chained shut in the back of house: where a Tour run starts.
##
## Not a pickup-able Item -- it never leaves the floor -- but it answers a thrown item's hit the
## same way a Hoop does (`struck`), registered with the room as a generic target
## (`ItemRoom.targets`, `target_struck`) rather than Tour-named infrastructure. It knows nothing
## of Session or Tour by name, but it is told *whose* throw each hit was (`struck`'s
## `thrown_by`, a peer id) and only counts the host's own toward breaking it -- "Only the HOST
## can break it" -- the one thing here that is not duck-typed exactly like a Hoop's `struck`.
## scenes/studio.gd still decides what to do once the lid is open (core/tour/tour.gd's
## `start_run`) and shows the toast on a non-host's attempt -- see its `_on_tour_case_struck`.

const MODEL := "res://assets/models/tour_case.glb"
## A few hits from the host's own thrown items break it (`struck`'s `thrown_by`); somebody
## else's thud and nothing more. core/tour/tour.gd's run never counts these itself -- see the
## class note.
const HITS_TO_BREAK := 5
## How far a thrown item's hit still finds it (ItemRoom.target_struck's radius).
const STRIKE_RADIUS := 0.55
## tools/blender/tour_case.py's sizes, repeated here for the labels' spots and its footprint.
const CASE_WIDTH := 0.74
const CASE_DEPTH := 0.46
const BODY_H := 0.42
const LID_H := 0.055
## How far open the lid swings, and how long the burst takes to get there.
const LID_OPEN_DEGREES := -118.0
const BURST_SECONDS := 0.45

## Every hit, broken or not, host's or not: scenes/studio.gd tells a non-host's thrower the
## toast off this.
signal break_attempted()
## The hit that broke it.
signal broken_open()

var hits: int = 0
var broken := false
## Who is clicking on this machine (`Session.local_peer_id`), set by scenes/studio.gd: a knock
## by hand counts the way a throw by the same person would.
var local_peer: Callable = Callable()

var _lid: Node3D
var _chain: Node3D
var _title: Label3D
var _tally: Label3D


## What it blocks a person walking, as a walker footprint ({c, h, a, top}) in `at`'s frame: the
## whole case, floor to the top of its shut lid -- the same shape `Hoop.solids` answers for a
## hoop, for `Venue.solids()` to append.
static func solids(at: Transform3D) -> Array:
	return [{"c": Vector2(at.origin.x, at.origin.z), "h": Vector2(CASE_WIDTH, CASE_DEPTH) * 0.5,
			"a": at.basis.get_euler().y, "top": BODY_H + LID_H}]


func _init() -> void:
	name = "TourCase"
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	add_child(model)
	_dress(model)
	_lid = model.find_child("Lid", true, false) as Node3D
	_chain = model.find_child("Chain", true, false) as Node3D
	# +0.004, not -0.001: the shell's own front face is a solid wall at exactly this depth
	# (tools/blender/tour_case.py's "stencil" box sits a hair BEHIND it, not visible through
	# any cut), so a label behind it is a label painted on the inside of an opaque box. Proud of
	# the face instead, the way a sticker actually sits on a case.
	_title = _label(26, Vector3(0, BODY_H * 0.66, CASE_DEPTH * 0.5 + 0.004))
	_title.text = "TOUR"
	_tally = _label(9, Vector3(0, BODY_H * 0.30, CASE_DEPTH * 0.5 + 0.004))
	_lamp()
	var knock := Knock.new()
	knock.position = Vector3(0, (BODY_H + LID_H) * 0.5, 0)
	add_child(knock)
	knock.knocked.connect(_on_knocked)
	reset(0, 0)


## A small light of its own, angled down at the stencil, with a bare glowing strip for a fixture
## -- the same two-part lamp a Hoop stands over its own board (ZoneKit.glow): the back of house
## is where the room's own light is thin, and a bright SpotLight3D alone, with no visible source,
## still reads as a dark case in a dark corner. The strip is what a person actually notices first.
func _lamp() -> void:
	# Out and up from the front, at roughly a gallery light's angle: nearly overhead lights only
	# the lid (a grazing, near-zero angle onto the vertical stencil face); this one is far enough
	# in front that its beam actually lands square on the panel a person reads.
	var at := Vector3(0, BODY_H + 0.32, CASE_DEPTH * 0.5 + 0.32)
	var strip := ZoneKit.block(self, Vector3(0.14, 0.012, 0.03), at, ZoneKit.glow(Color(1.0, 0.8, 0.55), 3.0),
			"CaseLampStrip")
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := SpotLight3D.new()
	light.name = "CaseLight"
	light.light_color = Color(1.0, 0.8, 0.55)
	light.light_energy = 3.0
	light.spot_range = 2.2
	light.spot_angle = 45.0
	light.spot_attenuation = 0.7
	light.shadow_enabled = false
	light.transform = Transform3D(Basis.looking_at(Vector3(0, BODY_H * 0.45, CASE_DEPTH * 0.5) - at,
			Vector3.UP), at)
	add_child(light)


## The model's materials, tools/blender/tour_case.py's five names ("shell", "corner",
## "stencil", "chain", "latch") swapped for real paint and steel -- the same pass Hoop's
## `_init` makes over its own model.
func _dress(model: Node3D) -> void:
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.09, 0.095, 0.105)
	shell.roughness = 0.8
	var corner := StandardMaterial3D.new()
	corner.albedo_color = Color(0.7, 0.71, 0.74)
	corner.metallic = 0.75
	corner.roughness = 0.4
	var stencil := StandardMaterial3D.new()
	stencil.albedo_color = Color(0.2, 0.18, 0.15)
	stencil.roughness = 0.9
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.75, 0.75, 0.78)
	metal.metallic = 0.85
	metal.roughness = 0.3
	var swap := {"shell": shell, "corner": corner, "stencil": stencil, "chain": metal, "latch": metal}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])


func _label(size: int, at: Vector3) -> Label3D:
	var l := Label3D.new()
	l.font_size = size * 4
	l.pixel_size = 0.0012
	l.position = at
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.modulate = Color(0.92, 0.9, 0.86)
	Lettering.range_to_legibility(l)
	# Stencilled paint, not a sign: a hairline of outline, not the panels' thick one.
	l.outline_size = maxi(2, l.font_size / 24)
	add_child(l)
	return l


## Its latch hit at `speed`, from a thrown item, by `thrown_by` (their peer id -- the host's is
## always 1, ItemRoom.target_struck's) -- the same duck-typed shape as `Hoop.struck`, called by
## `ItemRoom.target_struck`. Every hit sounds and is said (`break_attempted`), which is what
## tells a non-host's the toast; only the host's own throws count toward the fifth that bursts
## the lid open (`broken_open`) -- "Only the HOST can break it" -- so somebody else's hits thud
## and nothing more. A hit once it is already open does nothing.
func struck(speed: float, thrown_by: int) -> void:
	if broken:
		return
	Foley.play(self, Foley.gear_bump(), clampf(linear_to_db(speed / 5.0), -24.0, 0.0))
	break_attempted.emit()
	if thrown_by != 1:
		return
	hits += 1
	if hits >= HITS_TO_BREAK:
		_burst()


## Knocked on by hand (a click, or a hand in a headset): a hit from whoever is at this machine.
func _on_knocked() -> void:
	struck(3.0, int(local_peer.call()) if local_peer.is_valid() else 1)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1.03, 0.97, 1.03), 0.05)
	tw.tween_property(self, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The run really started, by the host's own word (`Session.tour` going non-empty) -- open it
## to match, the same way a fifth real hit would, for a guest whose own view of the hits never
## reached `HITS_TO_BREAK` (someone else's throws, a dropped one, lag): "every guest sees it
## break" rides the run's synced state, not this guest's own local count. A no-op once it
## already is.
func sync_broken() -> void:
	if not broken:
		_burst()


func _burst() -> void:
	broken = true
	Foley.play(self, Foley.tour_stinger(), 0.0)
	if _chain != null:
		_chain.visible = false
	if _lid != null:
		var tw := _lid.create_tween()
		tw.tween_property(_lid, "rotation_degrees:x", LID_OPEN_DEGREES, BURST_SECONDS) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	broken_open.emit()


## The lid rattles when the room is about to go wrong -- a chaos event's telegraph, on every
## peer at the same moment (core/tour/tour.gd's `chaos_telegraphed`, wired in scenes/studio.gd).
## Knows nothing of why: a jitter about however open the lid already is (always
## `LID_OPEN_DEGREES` by the time a brief is under way to rattle at all) and a settle back to it.
func rattle(seconds := 1.6) -> void:
	if _lid == null:
		return
	var tw := _lid.create_tween()
	var step := seconds / 6.0
	for k in 6:
		var jitter: float = 4.0 if k % 2 == 0 else -4.0
		tw.tween_property(_lid, "rotation_degrees:x", LID_OPEN_DEGREES + jitter, step * 0.5)
		if k == 1 or k == 4:
			tw.tween_callback(func() -> void: Foley.play(self, Foley.gear_bump(), -14.0))
	tw.tween_property(_lid, "rotation_degrees:x", LID_OPEN_DEGREES, step * 0.5)


## Chained again, hits and lid reset, the tally on its side brought up to date: a run's ending
## (won or lost) and nothing else calls this.
func reset(tally_runs: int, tally_wins: int) -> void:
	hits = 0
	broken = false
	if _chain != null:
		_chain.visible = true
	if _lid != null:
		_lid.rotation_degrees.x = 0.0
	if _tally != null:
		_tally.text = "RUNS %d   WINS %d" % [tally_runs, tally_wins]


## The tally swapped for the run's own seed (`TourRun.attempt_seed`) for as long as one is under
## way: every draw a brief or a card makes already comes off this one number (`TourRun.song_rng`,
## `chaos_rng`, `TourDeck`'s own cards), so reading it off the case is enough for the same run to
## be asked for again. `reset` puts the RUNS/WINS tally back once the run ends.
func show_seed(seed: int) -> void:
	if _tally != null:
		_tally.text = "SEED %d" % seed


## The whole case, to click on: each click a knock on its latch, five from the host to burst
## it. A throw does the same; this is the way anyone will try first. Personal, like the
## wardrobe's buttons: one person's knocking is not a control the others see held.
class Knock extends ControlAffordance:
	signal knocked()

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(CASE_WIDTH + 0.02, BODY_H + LID_H, CASE_DEPTH + 0.02)
		shape.shape = box
		add_child(shape)

	func personal() -> bool:
		return true

	func _default_title() -> String:
		return "TOUR  CASE"

	func _default_readout() -> String:
		var case := get_parent() as TourCase
		if case == null:
			return ""
		if case.broken:
			return "open: a run is under way"
		return "%d of %d knocks" % [case.hits, HITS_TO_BREAK]

	func hint() -> String:
		return "click it %d times to break it open and start a run (the host)" % HITS_TO_BREAK

	func _on_grab_begin(_at: Vector3) -> void:
		knocked.emit()
