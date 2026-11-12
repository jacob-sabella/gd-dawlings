class_name SingerHead
extends Node3D

## The singer's head: a head over twice life size cut down the middle, drawn in glowing lines, with the voice's
## insides moving in it as the engine sings (the vector-display look of CHIMERA's own screens, made a thing in the
## room). Everything inside comes from the engine (Singer.body, Singer.frame): the walls, tongue, lips, teeth, jaw,
## soft palate, epiglottis and nose as CHIMERA computes them for the articulators now; the airway as a tube of rings
## whose size is the cross-section the acoustics see and whose colour is the pressure in it; the breath as beads
## running up the airway as fast as the air does; the vocal folds fluttering at the bottom. The skull and face around
## it are only the far half (the near half is cut away, so the inside is seen).
##
## Hands (and the mouse) take hold of it: the jaw, the tongue's body, its tip, the lips, the soft palate and the
## larynx (`Grip`, a ControlAffordance each). A grip moves its articulators by as much as the hand moves, in the
## body's centimetres (`moved`), and lets go (`let_go`); the booth turns those into the voice's (Singer.grab).
##
## Its frame: body centimetres times `SCALE`, +X the way the face looks, +Y up, +Z toward the side that is cut
## away (the viewer's), the origin at the glottis.

## A hand moved articulator `name` to `cm` (its own units, as CHIMERA's ArticKey).
signal moved(name: String, cm: float)
## A hand let go of a grip that moved `names`.
signal let_go(names: PackedStringArray)

## Metres per body centimetre: a head about 66 cm from the neck to the crown, big enough to read the mouth's
## insides from the desk (0.015 until 2026-11-12, "the cool head thing could be a bit bigger").
const SCALE := 0.0225
## How much bigger than it was first drawn (SCALE 0.015): the grips' handles grow with it, and the booth's
## pedestal and halo (SingerBooth).
const GROWN := SCALE / 0.015
## The palette: blue is the body, amber is sound, the grips each a colour of their own.
const BLUE := Color(0.31, 0.71, 0.95)
const BLUE_DIM := Color(0.12, 0.37, 0.55)
const AMBER := Color(1.0, 0.70, 0.25)
const GRIP_COLOURS := {"jaw": Color(1.0, 0.36, 0.25), "tongue": Color(0.36, 0.89, 0.51), "tip": Color(0.55, 1.0, 0.65),
		"lips": Color(1.0, 0.45, 0.81), "velum": Color(0.93, 0.96, 0.97), "larynx": Color(1.0, 0.85, 0.45)}
## What each grip moves: [articulator for across (body x), articulator for up (body y), sign of up].
const GRIPS := {"jaw": ["", "jaw", -1.0], "tongue": ["tbX", "tbY", 1.0], "tip": ["ttX", "ttY", 1.0],
		"lips": ["lipProt", "lipAp", -1.0], "velum": ["", "velum", -1.0], "larynx": ["", "larynx", 1.0]}
const BEADS := 48

## The far half of a head, my own proportions (body cm, y up from the glottis): for each height, how far forward the
## face is, how far back the skull, and the half-width.
const SHELL := [[-5.0, 3.2, -4.6, 5.0], [-1.0, 3.0, -4.8, 5.2], [2.0, 3.6, -5.0, 5.4], [4.0, 7.0, -5.6, 5.8],
		[6.0, 7.5, -6.4, 6.3], [8.0, 7.4, -7.2, 6.8], [10.0, 7.8, -8.0, 7.2], [12.0, 8.2, -8.8, 7.5], [14.0, 8.0, -9.4, 7.6],
		[16.0, 8.6, -9.6, 7.6], [18.0, 8.1, -9.4, 7.4], [20.0, 7.3, -8.6, 6.8], [22.0, 5.4, -6.8, 5.6],
		[23.6, 2.4, -4.0, 3.4], [24.4, 0.0, -1.6, 1.0]]
## The face's profile on the midline (throat, chin, lips, nose, brow), body cm, from the neck up over the crown:
## fitted round CHIMERA's own anatomy (its lips are about 7 cm in front of the glottis and 8 cm above it).
const PROFILE := [Vector2(3.2, -5.0), Vector2(3.0, -1.0), Vector2(3.4, 2.0), Vector2(5.0, 3.6), Vector2(7.0, 4.0),
		Vector2(7.5, 4.9), Vector2(7.6, 6.0), Vector2(7.5, 7.0), Vector2(7.2, 7.6), Vector2(7.6, 8.4), Vector2(7.4, 9.4),
		Vector2(7.7, 9.9), Vector2(9.3, 10.6), Vector2(8.9, 11.4), Vector2(8.1, 12.8), Vector2(7.8, 13.8),
		Vector2(8.6, 15.0), Vector2(8.5, 17.5), Vector2(7.4, 20.0), Vector2(5.0, 22.6), Vector2(1.5, 24.0),
		Vector2(-1.6, 24.4)]

var _mesh := ImmediateMesh.new()
var _lines: MeshInstance3D
var _body := {}
var _frame := {}
var _beads := PackedFloat32Array()
var _fold_phase := 0.0
var _glow := 0.0
var grips := {}
## A hand on the mouth now (the grip's name), for the hint and the lights.
var holding := ""


func _ready() -> void:
	_lines = MeshInstance3D.new()
	_lines.name = "Lines"
	_lines.mesh = _mesh
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lines.material_override = line_material()
	add_child(_lines)
	_beads.resize(BEADS)
	for i in BEADS:
		_beads[i] = float(i) / BEADS
	for g in GRIPS:
		var grip := Grip.new()
		grip.name = "Grip_" + g
		grip.part = g
		grip.colour = GRIP_COLOURS[g]
		grip.head = self
		add_child(grip)
		grips[g] = grip
	_draw()


## The lines' look: unlit, added onto what is behind (a glow on a dark booth), coloured per vertex.
static func line_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.no_depth_test = false
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## The voice now: `body` as VoiceTele.read gives it, `frame` as RackEngine.frames (either may be {}).
func show_voice(body: Dictionary, frame: Dictionary) -> void:
	if not body.is_empty():
		_body = body
	if not frame.is_empty():
		_frame = frame
		_place_grips()


## A body point (cm) in this node's frame.
static func at(p: Vector2, z := 0.0) -> Vector3:
	return Vector3(p.x, p.y, z) * SCALE


## A local point in this node's frame back to body cm (the midline's plane).
static func cm_of(local: Vector3) -> Vector2:
	return Vector2(local.x, local.y) / SCALE


func _process(delta: float) -> void:
	var rms := float(_body.get("rms", 0.0))
	_glow = lerpf(_glow, clampf(rms * 14.0, 0.0, 1.0), clampf(delta * 10.0, 0.0, 1.0))
	# the air: beads ride up the airway as fast as the flow at their place, the folds at the voice's pitch
	var flow: PackedFloat32Array = _body.get("flow", PackedFloat32Array())
	var fpeak := VoiceTele.peak(flow)
	for i in BEADS:
		var u := _beads[i]
		var k := clampi(int(u * flow.size()), 0, maxi(flow.size() - 1, 0))
		var speed := 0.08 + (absf(flow[k]) / fpeak * 0.9 * _glow if flow.size() > 0 else 0.0)
		u += speed * delta
		_beads[i] = u - floorf(u)
	_fold_phase = fposmod(_fold_phase + delta * minf(float(_body.get("f0", 0.0)), 12.0), 1.0)
	_draw()


func _draw() -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_draw_shell()
	var lines: Dictionary = _frame.get("lines", {})
	if not lines.is_empty():
		_draw_anatomy(lines)
		_draw_airway(lines)
	_draw_folds()
	_mesh.surface_end()


func _seg(a: Vector3, b: Vector3, c: Color) -> void:
	_mesh.surface_set_color(c)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(c)
	_mesh.surface_add_vertex(b)


func _poly(pts: PackedVector2Array, c: Color, z := 0.0, closed := false) -> void:
	for i in pts.size() - 1:
		_seg(at(pts[i], z), at(pts[i + 1], z), c)
	if closed and pts.size() > 2:
		_seg(at(pts[-1], z), at(pts[0], z), c)


## The far half of the skull and face, ring by ring, and the face's profile on the cut.
func _draw_shell() -> void:
	var dim := BLUE_DIM * Color(1, 1, 1, 0.22 + 0.18 * _glow)
	var rings: Array = []
	for row: Array in SHELL:
		var y: float = row[0]
		var front: float = row[1]
		var back: float = row[2]
		var half: float = row[3]
		var ring: Array = []
		for j in 13:
			# from the face round the far side to the back: a half ellipse, the near half cut away
			var a := PI * float(j) / 12.0
			var x := lerpf(front, back, (1.0 - cos(a)) * 0.5)
			ring.append(at(Vector2(x, y), -half * sin(a)))
		rings.append(ring)
		for j in 12:
			_seg(ring[j], ring[j + 1], dim)
	for j in range(0, 13, 3):
		for r in rings.size() - 1:
			_seg(rings[r][j], rings[r + 1][j], dim * Color(1, 1, 1, 0.6))
	_poly(PackedVector2Array(PROFILE), BLUE * Color(1, 1, 1, 0.55))


func _draw_anatomy(lines: Dictionary) -> void:
	var walls := BLUE * Color(1, 1, 1, 0.9)
	_poly(lines["outer"], walls)
	_poly(lines["inner"], walls * Color(1, 1, 1, 0.7))
	_poly(lines["nasal_cavity"], BLUE_DIM, 0.0, true)
	_poly(lines["epiglottis"], walls)
	_poly(lines["jaw_bone"], _grip_colour("jaw") * Color(1, 1, 1, 0.7))
	_poly(lines["upper_teeth"], Color(0.93, 0.96, 0.97, 0.8), 0.0, true)
	_poly(lines["lower_teeth"], Color(0.93, 0.96, 0.97, 0.8), 0.0, true)
	_poly(lines["velum"], _grip_colour("velum"))
	_poly(lines["upper_lip"], _grip_colour("lips"), 0.0, true)
	_poly(lines["lower_lip"], _grip_colour("lips"), 0.0, true)
	# the tongue, swept sideways into ribs: the midline outline and narrower copies toward each side
	var tongue: PackedVector2Array = lines["tongue"]
	var tc := _grip_colour("tongue")
	_poly(tongue, tc, 0.0, true)
	if tongue.size() > 2:
		var centre := Vector2.ZERO
		for p in tongue:
			centre += p
		centre /= tongue.size()
		for side in [-2.2, -1.2, 1.2, 2.2]:
			var shrink := 1.0 - absf(side) * 0.16
			var ribbed := PackedVector2Array()
			for p in tongue:
				ribbed.append(centre + (p - centre) * shrink)
			_poly(ribbed, tc * Color(1, 1, 1, 0.35), side, true)


## The airway's midline (body cm) from the glottis to the lips: halfway between the outer and inner walls, read
## at the same fraction of each.
static func midline(lines: Dictionary, glottis: Vector2, n: int) -> PackedVector2Array:
	var outer: PackedVector2Array = lines.get("outer", PackedVector2Array())
	var inner: PackedVector2Array = lines.get("inner", PackedVector2Array())
	var out := PackedVector2Array()
	if outer.size() < 2 or inner.size() < 2 or n < 2:
		return out
	for i in n:
		var u := float(i) / float(n - 1)
		out.append((along(outer, u) + along(inner, u)) * 0.5)
	out[0] = out[0].lerp(glottis, 0.5)
	return out


## The point a fraction `u` of the way along polyline `pts` by length.
static func along(pts: PackedVector2Array, u: float) -> Vector2:
	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	var want := clampf(u, 0.0, 1.0) * total
	for i in pts.size() - 1:
		var d := pts[i].distance_to(pts[i + 1])
		if want <= d or i == pts.size() - 2:
			return pts[i].lerp(pts[i + 1], clampf(want / maxf(d, 1e-6), 0.0, 1.0))
		want -= d
	return pts[-1]


## The airway: a ring per section, as wide as its cross-section and as hot as its pressure; and the breath.
func _draw_airway(lines: Dictionary) -> void:
	var areas: PackedFloat32Array = _body.get("areas", PackedFloat32Array())
	var pressure: PackedFloat32Array = _body.get("pressure", PackedFloat32Array())
	var n := areas.size()
	var mid := midline(lines, _frame.get("glottis", Vector2.ZERO), maxi(n, 24))
	if mid.size() < 2:
		return
	var ppeak := VoiceTele.peak(pressure)
	for i in n:
		var u := float(i) / float(maxi(n - 1, 1))
		var p := along(mid, u)
		var d := (along(mid, minf(u + 0.02, 1.0)) - along(mid, maxf(u - 0.02, 0.0))).normalized()
		var normal := Vector2(-d.y, d.x)
		var r := sqrt(maxf(areas[i], 0.0) / PI)
		var hot := clampf(absf(pressure[i]) / ppeak if i < pressure.size() else 0.0, 0.0, 1.0)
		var c := BLUE_DIM.lerp(AMBER, clampf(hot * (0.5 + _glow), 0.0, 1.0))
		c.a = 0.3 + 0.7 * clampf(hot * (0.4 + _glow), 0.0, 1.0)
		var last := Vector3.ZERO
		for j in 11:
			var a := TAU * float(j) / 10.0
			var q := at(p + normal * r * cos(a), r * 0.85 * sin(a))
			if j > 0:
				_seg(last, q, c)
			last = q
	# the breath: short dashes riding the midline
	if _glow > 0.02:
		for i in BEADS:
			var u := _beads[i]
			var a2 := along(mid, u)
			var b2 := along(mid, minf(u + 0.015, 1.0))
			var c2 := AMBER * Color(1, 1, 1, clampf(_glow * 1.6, 0.0, 1.0))
			_seg(at(a2, sin(u * 40.0 + i) * 0.4), at(b2, sin(u * 40.0 + i) * 0.4), c2)


## The vocal folds at the glottis: two lips of a slit seen from above, as open as the voice's cycle says.
func _draw_folds() -> void:
	var g: Vector2 = _frame.get("glottis", Vector2.ZERO)
	var folds: PackedFloat32Array = _body.get("folds", PackedFloat32Array())
	var fpeak := VoiceTele.peak(folds)
	var open := 0.15
	if folds.size() > 0:
		open = clampf(folds[int(_fold_phase * folds.size()) % folds.size()] / fpeak, 0.0, 1.0) * float(_body.get("voicing", 0.0))
	var c := _grip_colour("larynx")
	var w := 0.9
	for side in [-1.0, 1.0]:
		var last := Vector3.ZERO
		for j in 9:
			var t := float(j) / 8.0
			var x := lerpf(-w, w, t)
			var gap: float = side * (0.08 + open * 0.35) * sin(PI * t)
			var q := at(g + Vector2(x * 0.6, 0.0), gap * 2.0) + Vector3(0, 0, 0)
			if j > 0:
				_seg(last, q, c)
			last = q


func _grip_colour(g: String) -> Color:
	var c: Color = GRIP_COLOURS[g]
	var grip: Grip = grips.get(g)
	if grip != null and (grip.held_by != null or grip.hovered):
		return c.lightened(0.45)
	return c * Color(1, 1, 1, 0.85)


## Where each grip sits on the outlines now (body cm).
func grip_points(lines: Dictionary, glottis: Vector2) -> Dictionary:
	var out := {}
	var tongue: PackedVector2Array = lines.get("tongue", PackedVector2Array())
	if tongue.size() > 0:
		var centre := Vector2.ZERO
		var tip := tongue[0]
		for p in tongue:
			centre += p
			if p.x > tip.x:
				tip = p
		out["tongue"] = centre / tongue.size()
		out["tip"] = tip
	var ul: PackedVector2Array = lines.get("upper_lip", PackedVector2Array())
	var ll: PackedVector2Array = lines.get("lower_lip", PackedVector2Array())
	if ul.size() > 0 and ll.size() > 0:
		out["lips"] = (_front(ul) + _front(ll)) * 0.5 + Vector2(0.6, 0.0)
	var lt: PackedVector2Array = lines.get("lower_teeth", PackedVector2Array())
	var jb: PackedVector2Array = lines.get("jaw_bone", PackedVector2Array())
	if jb.size() > 0:
		out["jaw"] = _low(jb)
	elif lt.size() > 0:
		out["jaw"] = _low(lt)
	var vel: PackedVector2Array = lines.get("velum", PackedVector2Array())
	if vel.size() > 0:
		out["velum"] = along(vel, 0.6)
	out["larynx"] = glottis + Vector2(2.4, -0.6)
	return out


static func _front(pts: PackedVector2Array) -> Vector2:
	var best := pts[0]
	for p in pts:
		if p.x > best.x:
			best = p
	return best


static func _low(pts: PackedVector2Array) -> Vector2:
	var best := pts[0]
	for p in pts:
		if p.y < best.y:
			best = p
	return best


func _place_grips() -> void:
	var pts := grip_points(_frame.get("lines", {}), _frame.get("glottis", Vector2.ZERO))
	for g in grips:
		var grip: Grip = grips[g]
		if grip.held_by == null and pts.has(g):
			grip.position = at(pts[g], 0.0)


## The articulator's value now, from the body (NAN before the engine has said).
func artic_now(name: String) -> float:
	var a: Dictionary = _body.get("artic", {})
	return float(a.get(name, NAN))


## A handle on part of the mouth: a hand closes on it and moves its articulators by as much as the hand moves.
class Grip extends ControlAffordance:
	var part := ""
	var colour := Color.WHITE
	var head: SingerHead
	var hovered := false
	var _from := Vector2.ZERO
	var _start := {}
	var _shape: MeshInstance3D

	func _ready() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.022 * SingerHead.GROWN
		shape.shape = sphere
		add_child(shape)
		_shape = MeshInstance3D.new()
		var m := SphereMesh.new()
		m.radius = 0.0055 * SingerHead.GROWN
		m.height = 0.011 * SingerHead.GROWN
		m.radial_segments = 8
		m.rings = 4
		_shape.mesh = m
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = colour
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_shape.material_override = mat
		_shape.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_shape)
		hover_changed.connect(func(h: bool) -> void: hovered = h)

	func _default_title() -> String:
		return {"jaw": "JAW", "tongue": "TONGUE", "tip": "TONGUE TIP", "lips": "LIPS", "velum": "SOFT PALATE",
				"larynx": "LARYNX"}.get(part, part.to_upper())

	func _default_readout() -> String:
		return "drag"

	func hint() -> String:
		return {"jaw": "drag down to open the jaw", "tongue": "drag the tongue: front, back, high, low",
				"tip": "drag the tongue tip to the teeth or the ridge behind them", "lips": "drag down to open the lips, forward to round them",
				"velum": "drag down to open the nose", "larynx": "drag the larynx up or down"}.get(part, "drag")

	func _cm(world: Vector3) -> Vector2:
		return SingerHead.cm_of(head.to_local(world))

	func _on_grab_begin(at: Vector3) -> void:
		_from = _cm(at)
		_start = {}
		var spec: Array = SingerHead.GRIPS[part]
		for k in [spec[0], spec[1]]:
			if k != "":
				_start[k] = head.artic_now(k)
		head.holding = part

	func _on_grab_move(at: Vector3) -> void:
		var d := _cm(at) - _from
		var spec: Array = SingerHead.GRIPS[part]
		position = SingerHead.at(_from + d)
		if spec[0] != "" and not is_nan(float(_start.get(spec[0], NAN))):
			head.moved.emit(spec[0], float(_start[spec[0]]) + d.x)
		if spec[1] != "" and not is_nan(float(_start.get(spec[1], NAN))):
			head.moved.emit(spec[1], float(_start[spec[1]]) + d.y * float(spec[2]))

	func _on_grab_end() -> void:
		var spec: Array = SingerHead.GRIPS[part]
		var names := PackedStringArray()
		for k in [spec[0], spec[1]]:
			if k != "":
				names.append(k)
		head.holding = ""
		head.let_go.emit(names)
