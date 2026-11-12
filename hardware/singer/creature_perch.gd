class_name CreaturePerch
extends Node3D

## The venue's creature in its vocal booth (Bestiary): a line drawing of the animal on a plinth, in the singer's
## look (SingerHead: blue lines, amber when it sounds), and in front of it a sloped ledge of Bestiary.STONES stones
## played like the venue's instrument. Stone n sounds the creature's call on the n-th tone of the song's scale
## (Bestiary.note), and is lettered with the note it sounds now, so it is read, not told by colour; the letters
## follow the key as the song moves through it. A stone is struck by a hand, a controller or a click.
##
## It only asks (`struck` n) and shows (`sound` how loud the creature is, which opens its mouth and lights it).
## Its frame: the floor under the plinth, +Z toward whoever plays it, +X to their right.

signal struck(n: int)

const PLINTH := 0.82
const LEDGE_AT := Vector3(0.0, 0.86, 0.26)
const LEDGE_TILT := deg_to_rad(-30.0)
const STONE := Vector2(0.075, 0.075)
## The figure's size: about 0.45 m nose to tail.
const FIGURE := 0.45
## How often the stones' letters are looked at again (s), as VenueInstrument's bars'.
const RELETTER := 0.1

var spec := {}
var stones: Array[SingerBooth.BoothKey] = []
var _mesh: ImmediateMesh
var _mat: StandardMaterial3D
var _level := 0.0
var _shown_level := -1.0
var _reletter := 0.0
var _plaque: Label3D


func _init(creature: Dictionary = {}) -> void:
	spec = creature if not creature.is_empty() else Bestiary.of(&"studio")


func _ready() -> void:
	_build_plinth()
	var figure := MeshInstance3D.new()
	figure.name = "Figure"
	_mesh = ImmediateMesh.new()
	figure.mesh = _mesh
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	figure.material_override = _mat
	figure.position = Vector3(0, PLINTH + 0.02, -0.04)
	figure.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(figure)
	var ledge := Node3D.new()
	ledge.name = "Ledge"
	ledge.position = LEDGE_AT
	ledge.rotation.x = LEDGE_TILT
	add_child(ledge)
	var slab := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(Bestiary.STONES * (STONE.x + 0.01) + 0.03, STONE.y + 0.05, 0.02)
	slab.mesh = box
	slab.position.z = -0.012
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.03, 0.04, 0.05)
	paint.roughness = 0.6
	slab.material_override = paint
	ledge.add_child(slab)
	var left := -(Bestiary.STONES - 1) * (STONE.x + 0.01) * 0.5
	for n in Bestiary.STONES:
		var k := SingerBooth.BoothKey.new()
		k.size = STONE
		k.name = "Stone%d" % n
		k.position = Vector3(left + n * (STONE.x + 0.01), 0.0, 0.0)
		k.down.connect(func(d: bool) -> void:
			if d:
				struck.emit(n))
		ledge.add_child(k)
		stones.append(k)
	_plaque = Label3D.new()
	_plaque.name = "Name"
	_plaque.text = "THE %s  ·  in the song's key" % String(spec.get("title", ""))
	_plaque.font_size = 40
	_plaque.pixel_size = 0.016 / 40.0
	_plaque.modulate = SingerBooth.INK
	_plaque.position = Vector3(0, STONE.y * 0.5 + 0.017, 0.003)
	ledge.add_child(_plaque)
	_letter()
	_draw()


func _build_plinth() -> void:
	var post := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, PLINTH, 0.32)
	post.mesh = box
	post.position = Vector3(0, PLINTH * 0.5, -0.04)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.05, 0.06, 0.07)
	paint.roughness = 0.5
	post.material_override = paint
	add_child(post)
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.position = Vector3(0, PLINTH + 1.15, -0.1)
	lamp.light_volumetric_fog_energy = 0.0
	lamp.omni_range = 1.8
	lamp.light_energy = 0.5
	lamp.light_color = SingerHead.BLUE
	add_child(lamp)


## How loud the creature is now, 0..1: its mouth opens and it lights amber with it.
func sound(level: float) -> void:
	_level = clampf(level, 0.0, 1.0)


func _process(delta: float) -> void:
	_reletter -= delta
	if _reletter <= 0.0:
		_reletter = RELETTER
		_letter()
	if absf(_level - _shown_level) > 0.01:
		_draw()
	var lamp := get_node_or_null("Lamp") as OmniLight3D
	if lamp != null:
		lamp.light_color = SingerHead.BLUE.lerp(SingerHead.AMBER, _level)
		lamp.light_energy = 0.5 * (1.0 + _level)


## Each stone lettered with the note it sounds now.
func _letter() -> void:
	var h := Bestiary.harmony_now()
	for n in stones.size():
		var said := h.note_name(Bestiary.note(h, spec, n), true)
		if stones[n].legend_text != said:
			stones[n].legend_text = said
			stones[n].tip = "the %s's call on %s" % [String(spec.get("title", "")).to_lower(), said]


## The note stone `n` sounds now (MIDI).
func note_of(n: int) -> int:
	return Bestiary.note(Bestiary.harmony_now(), spec, n)


## A stone lit while it sounds.
func light(n: int, on: bool) -> void:
	if n >= 0 and n < stones.size():
		stones[n].lit = on


# --- the drawing: polylines in the figure's plane (x along the body, y up), metres --------------------------

func _draw() -> void:
	_shown_level = _level
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var c := SingerHead.BLUE.lerp(SingerHead.AMBER, _level)
	var open := _level
	match StringName(spec.get("kind", &"songbird")):
		&"seal":
			_seal(c, open)
		&"alligator":
			_gator(c, open)
		&"elephant":
			_elephant(c, open)
		_:
			_bird(c, open)
	_mesh.surface_end()


func _line(pts: PackedVector2Array, c: Color, z := 0.0, closed := false) -> void:
	var n := pts.size()
	for i in (n if closed else n - 1):
		var a := pts[i] * FIGURE
		var b := pts[(i + 1) % n] * FIGURE
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(Vector3(a.x, a.y, z))
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(Vector3(b.x, b.y, z))


## An ellipse's outline round `at`, radii `r`, as a figure's body; rings across it give it depth.
func _blob(at: Vector2, r: Vector2, c: Color, rings := 3) -> void:
	for k in rings:
		var z := (float(k) / maxf(rings - 1, 1) - 0.5) * r.y * FIGURE * 1.2
		var shrink := sqrt(maxf(1.0 - pow(2.0 * float(k) / maxf(rings - 1, 1) - 1.0, 2) * 0.7, 0.05))
		var pts := PackedVector2Array()
		for i in 24:
			var t := TAU * i / 24.0
			pts.append(at + Vector2(cos(t) * r.x, sin(t) * r.y) * shrink)
		_line(pts, c * (1.0 if k == rings / 2 else 0.55), z, true)


func _bird(c: Color, open: float) -> void:
	_blob(Vector2(0.0, 0.32), Vector2(0.24, 0.15), c)
	_blob(Vector2(0.24, 0.5), Vector2(0.09, 0.085), c)
	var gape := 0.02 + open * 0.08
	_line(PackedVector2Array([Vector2(0.31, 0.51), Vector2(0.46, 0.5 + gape * 0.3), Vector2(0.31, 0.47)]), SingerHead.AMBER)
	_line(PackedVector2Array([Vector2(0.31, 0.47), Vector2(0.44, 0.47 - gape), Vector2(0.31, 0.45)]), SingerHead.AMBER)
	_line(PackedVector2Array([Vector2(-0.22, 0.34), Vector2(-0.48, 0.42), Vector2(-0.46, 0.3), Vector2(-0.2, 0.26)]), c)
	_line(PackedVector2Array([Vector2(-0.12, 0.38), Vector2(0.06, 0.42), Vector2(0.14, 0.32), Vector2(-0.1, 0.28)]), c * 0.8)
	for x in [-0.04, 0.06]:
		_line(PackedVector2Array([Vector2(x, 0.18), Vector2(x, 0.02), Vector2(x + 0.05, 0.0)]), c * 0.8)
	_line(PackedVector2Array([Vector2(-0.12, 0.0), Vector2(0.2, 0.0)]), c * 0.6)
	_line(PackedVector2Array([Vector2(0.27, 0.53), Vector2(0.275, 0.535)]), Color.WHITE)


func _seal(c: Color, open: float) -> void:
	var body := PackedVector2Array()
	for i in 25:
		var t := float(i) / 24.0
		body.append(Vector2(lerpf(-0.5, 0.3, t), 0.02 + sin(t * PI * 0.85) * lerpf(0.06, 0.24, t)))
	for i in 25:
		var t := 1.0 - float(i) / 24.0
		body.append(Vector2(lerpf(-0.5, 0.3, t), 0.0))
	_line(body, c, 0.0, true)
	_line(PackedVector2Array([Vector2(0.22, 0.22), Vector2(0.3, 0.26)]), c)
	_blob(Vector2(0.36, 0.25), Vector2(0.1, 0.08), c)
	var gape := open * 0.06
	_line(PackedVector2Array([Vector2(0.44, 0.24), Vector2(0.52, 0.23 + gape * 0.3)]), SingerHead.AMBER)
	_line(PackedVector2Array([Vector2(0.44, 0.22), Vector2(0.51, 0.21 - gape)]), SingerHead.AMBER)
	for k in 3:
		_line(PackedVector2Array([Vector2(0.46, 0.23), Vector2(0.58, 0.25 - k * 0.025)]), c * 0.5)
	_line(PackedVector2Array([Vector2(0.12, 0.1), Vector2(0.2, 0.0), Vector2(0.28, -0.0)]), c * 0.8)
	_line(PackedVector2Array([Vector2(-0.5, 0.02), Vector2(-0.6, 0.1), Vector2(-0.58, -0.0), Vector2(-0.5, 0.0)]), c * 0.8)
	_line(PackedVector2Array([Vector2(0.39, 0.28), Vector2(0.395, 0.285)]), Color.WHITE)


func _gator(c: Color, open: float) -> void:
	_blob(Vector2(-0.08, 0.1), Vector2(0.26, 0.08), c)
	_line(PackedVector2Array([Vector2(-0.33, 0.1), Vector2(-0.7, 0.04), Vector2(-0.34, 0.05)]), c)
	var gape := 0.01 + open * 0.12
	_line(PackedVector2Array([Vector2(0.16, 0.14), Vector2(0.52, 0.11 + gape * 0.4), Vector2(0.52, 0.1 + gape * 0.4)]), SingerHead.AMBER)
	_line(PackedVector2Array([Vector2(0.16, 0.06), Vector2(0.52, 0.09 - gape), Vector2(0.5, 0.08 - gape)]), SingerHead.AMBER)
	for k in 6:
		var x := 0.22 + k * 0.05
		var t := (x - 0.16) / 0.36
		var top := lerpf(0.14, 0.11 + gape * 0.4, t)
		_line(PackedVector2Array([Vector2(x, top), Vector2(x + 0.01, top - 0.018)]), c * 0.7)
	for x in [-0.22, 0.08]:
		_line(PackedVector2Array([Vector2(x, 0.05), Vector2(x - 0.04, 0.0), Vector2(x + 0.02, 0.0)]), c * 0.8)
	for k in 7:
		var x := -0.3 + k * 0.07
		_line(PackedVector2Array([Vector2(x, 0.17), Vector2(x + 0.02, 0.2), Vector2(x + 0.04, 0.17)]), c * 0.6)
	_line(PackedVector2Array([Vector2(0.17, 0.16), Vector2(0.175, 0.165)]), Color.WHITE)


## The elephant: a great body on four pillar legs, the head forward with its fanned ear, and the trunk, which lifts
## and curls out as it rumbles (`open`); the tusk in the mouth's amber.
func _elephant(c: Color, open: float) -> void:
	_blob(Vector2(-0.08, 0.36), Vector2(0.3, 0.18), c)
	_blob(Vector2(0.26, 0.44), Vector2(0.12, 0.11), c)
	# the ear, fanned back over the shoulder
	_line(PackedVector2Array([Vector2(0.2, 0.52), Vector2(0.08, 0.56), Vector2(0.04, 0.42), Vector2(0.1, 0.32),
			Vector2(0.2, 0.36)]), c * 0.8)
	# the legs: pillars, a toe line at the foot
	for x in [-0.3, -0.18, 0.04, 0.14]:
		_line(PackedVector2Array([Vector2(x, 0.24), Vector2(x, 0.0), Vector2(x + 0.07, 0.0), Vector2(x + 0.07, 0.22)]), c * 0.8)
	# the tail
	_line(PackedVector2Array([Vector2(-0.38, 0.42), Vector2(-0.44, 0.3), Vector2(-0.43, 0.24)]), c * 0.6)
	# the trunk: hanging when quiet, lifted and curled forward as it calls
	var trunk := PackedVector2Array()
	for i in 13:
		var t := float(i) / 12.0
		var hang := Vector2(0.36 + 0.06 * t, 0.42 - 0.38 * t + 0.04 * t * t)
		var lift := Vector2(0.36 + 0.24 * t, 0.42 - 0.08 * t + 0.22 * t * t)
		trunk.append(hang.lerp(lift, clampf(open, 0.0, 1.0)))
	_line(trunk, c)
	_line(PackedVector2Array([Vector2(0.33, 0.38), Vector2(0.42, 0.32), Vector2(0.45, 0.34)]), SingerHead.AMBER)
	_line(PackedVector2Array([Vector2(0.29, 0.48), Vector2(0.295, 0.485)]), Color.WHITE)


## The venue's lettering (SingerStyle) on the perch's name and stones.
func apply_style(s: Dictionary) -> void:
	if _plaque != null:
		SingerStyle.dress(_plaque, s, "key")
	for k in stones:
		k.style = s
