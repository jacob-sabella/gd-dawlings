class_name DartItem
extends Item

## A steel-tip dart, one of three, for the board over the prop shelf (docs/items_loop.md).
##
## It flies point first and sticks where it goes into the board, or the cabinet round it
## (Flight.fly's `boards`): every machine flies the same launch, so every one sees it go in at the
## same place and scores it the same (`score`), shown for a moment on the board by where it went in. Off the
## board it is a thrown thing like any other, and clatters to the floor. Its home is in the board:
## a dart is put away by being left in it.
##
## On a desktop a click throws it at the cursor, at an easy pace; R wound up throws it harder,
## flatter. Either way it is aimed (`aim_scatter`): it goes where the cursor is, less a hand's
## wobble that is worse the softer the throw.

const MODEL := "res://assets/models/dart.glb"
## From its point to the end of its flights (tools/blender/darts.py).
const LENGTH := 0.15
## How far the point goes in.
const POINT_IN := 0.012
## Where what it scored is lit: this far proud of the board's face, and this far up it from the
## dart, clear of its flights (m).
const SCORE_OFF_BOARD := 0.005
const SCORE_OVER := 0.06
## Half the barrel and flights' own width (measured off `tools/blender/darts.py`'s model): stuck
## in the board the point is the origin and right where it is, but lying loose it is on its
## side, and without this its flights are drawn half into the floor they are lying on.
const LOOSE_LIFT := 0.0111
## The board's rings, from its middle (m), and its numbers clockwise from the top.
const BULL := 0.00635
const OUTER_BULL := 0.0159
const TREBLE_IN := 0.099
const TREBLE_OUT := 0.107
const DOUBLE_IN := 0.162
const DOUBLE_OUT := 0.170
const ORDER := [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]
## The flights, one colour a dart, so whose throw was whose is told at a glance.
const FLIGHTS := [Color(0.9, 0.42, 0.06), Color(0.1, 0.55, 0.62), Color(0.72, 0.12, 0.4)]
## A click's throw: how wound up it counts as.
const CLICK_THROW := 0.6

## Which of the three.
var index := 0
## What the throw in the air will score when it goes in, worked out as it is thrown; empty when
## it will not go in the board.
var _will_score := {}
var _popup: Label3D = null
## The name of what it scored where it is stuck now ("T20", "MISS"), or empty.
var scored := ""


func _init(n := 0) -> void:
	index = n
	id = StringName("dart%d" % (n + 1))
	super()
	_shape.position = Vector3(0, 0, LENGTH * 0.5)


func item_title() -> String:
	return "DART"


func hint() -> String:
	if state == State.HELD and not is_held_elsewhere():
		return "click to throw it at the cursor  ·  hold R to throw it harder"
	if is_stuck():
		return "click to pull it out"
	return _hint("click to pick up")


func readout() -> String:
	if not is_stuck():
		return super()
	# What it scored, when this copy saw it go in; a copy that was told it is in only knows that.
	return "in the board" if scored.is_empty() else "in the board: %s" % scored


## What a dart in at `on` on the board's face (its x right and y up, m) scores: {points, name}.
static func score(on: Vector2) -> Dictionary:
	var r := on.length()
	if r <= BULL:
		return {"points": 50, "name": "BULL"}
	if r <= OUTER_BULL:
		return {"points": 25, "name": "25"}
	if r > DOUBLE_OUT:
		return {"points": 0, "name": "MISS"}
	# Clockwise from straight up, as the numbers go round.
	var turn := fposmod(rad_to_deg(atan2(on.x, on.y)) + 9.0, 360.0)
	var n: int = ORDER[int(turn / 18.0) % 20]
	if r >= TREBLE_IN and r <= TREBLE_OUT:
		return {"points": n * 3, "name": "T%d" % n}
	if r >= DOUBLE_IN:
		return {"points": n * 2, "name": "D%d" % n}
	return {"points": n, "name": str(n)}


## Aimed: thrown at the cursor, wobbling this far (m, about) at what it is aimed at.
func aim_scatter(wound: float) -> float:
	return lerpf(0.04, 0.012, wound)


func use(down: bool) -> void:
	# Thrown after the click is done with, not inside it: the throw ends the hand's use.
	if down and carried_by is MouseInteractor:
		(carried_by as MouseInteractor).throw_with.call_deferred(CLICK_THROW)


func on_launch() -> void:
	_will_score = {}
	scored = ""
	if flight != null and flight.stuck:
		_will_score = score(flight.stuck_on) if flight.stuck_board == 0 else {"points": 0, "name": "MISS"}
	if not landed.is_connected(_on_landed):
		landed.connect(_on_landed)


func _on_landed() -> void:
	if _will_score.is_empty():
		return
	Foley.play(self, Foley.dart_thunk(randi()), -2.0, randf_range(0.95, 1.05))
	scored = _will_score["name"]
	_show_score(_will_score)
	_will_score = {}


## What it scored, for a couple of seconds, lit flat on the board just over where it went in: on
## the board, as a scorer chalks it, and not hung in the air in front of it and over everything.
func _show_score(s: Dictionary) -> void:
	if _popup != null and is_instance_valid(_popup):
		_popup.queue_free()
	var label := Label3D.new()
	label.name = "Score"
	var points: int = s["points"]
	label.text = s["name"] if points == 0 or s["name"] == str(points) else "%s  %d" % [s["name"], points]
	label.font_size = 72
	label.outline_size = 14
	label.pixel_size = 0.0011
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	# Over what stands out of the board (the rim, the darts in it), for the moment it is up.
	label.no_depth_test = true
	label.double_sided = false
	label.modulate = Color(1.0, 0.85, 0.4) if points > 0 else Color(0.75, 0.75, 0.75)
	label.outline_modulate = Color(0.05, 0.04, 0.03)
	label.top_level = true
	add_child(label)
	# Stuck, its +Z is back out along the way it flew in, out of the board; the point is POINT_IN
	# behind the face. Its face looks that way, upright on the board, SCORE_OFF_BOARD proud of it.
	var out := global_basis.z.normalized()
	var up := (Vector3.UP - out * out.dot(Vector3.UP))
	up = up.normalized() if up.length() > 0.01 else Vector3.FORWARD
	label.global_transform = Transform3D(Basis(up.cross(out), up, out),
			global_position + out * (POINT_IN + SCORE_OFF_BOARD) + up * SCORE_OVER)
	_popup = label
	var fade := label.create_tween()
	fade.tween_interval(1.6)
	fade.tween_property(label, "modulate:a", 0.0, 0.6)
	fade.tween_callback(label.queue_free)


func on_picked_up() -> void:
	_will_score = {}
	scored = ""
	if _popup != null and is_instance_valid(_popup):
		_popup.queue_free()


## Put somewhere by the room, or home: whatever it scored is not where it is now.
func on_put_down() -> void:
	scored = ""


func _build_body() -> Node3D:
	var root := Node3D.new()
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	root.add_child(model)
	var point := Materials.brushed_metal()
	var barrel := StandardMaterial3D.new()
	barrel.albedo_color = Color(0.32, 0.33, 0.35)
	barrel.metallic = 0.9
	barrel.roughness = 0.35
	var ring := StandardMaterial3D.new()
	ring.albedo_color = Color(0.12, 0.12, 0.13)
	ring.metallic = 0.8
	ring.roughness = 0.5
	var shaft := StandardMaterial3D.new()
	shaft.albedo_color = Color(0.04, 0.04, 0.045)
	shaft.roughness = 0.4
	var flight_paint := StandardMaterial3D.new()
	flight_paint.albedo_color = FLIGHTS[index % FLIGHTS.size()]
	flight_paint.roughness = 0.5
	flight_paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	var swap := {"point": point, "barrel": barrel, "ring": ring, "shaft": shaft, "flight": flight_paint}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(s, swap[m.resource_name])
	return root


## A ball round its middle: a dart is a thin thing to point at, in a board across the room.
func _grip_shape() -> Shape3D:
	var s := SphereShape3D.new()
	s.radius = 0.05
	return s


## It turns about its point: the point is where it goes in, and where it is.
func centre_height() -> float:
	return 0.0


## Only when it is not stuck: lying on its side, not standing on its point.
func loose_rest_lift() -> float:
	return LOOSE_LIFT


## Held like a pencil, between finger and thumb, point out ahead and a little up.
func held_pose() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, 0.12) * Basis(Vector3.RIGHT, 0.1), Vector3(0.06, 0.07, -0.02))


func flies() -> Dictionary:
	return {"bounce": 0.2, "roll": 6.0, "drag": 0.0, "point": POINT_IN}


func on_bounce(speed: float) -> void:
	# Going in is its own sound, when it lands (`_on_landed`).
	if flight != null and flight.stuck and _hits_played == flight.hits.size():
		return
	Foley.play(self, Foley.dart_clatter(int(speed * 10.0)), clampf(linear_to_db(speed / 4.0), -18.0, 0.0))


func _foley_contact() -> AudioStream:
	return Foley.dart_clatter(0)
