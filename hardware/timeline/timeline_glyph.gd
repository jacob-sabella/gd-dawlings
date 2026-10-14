class_name TimelineGlyph
extends Node3D

## A tool's mark as a small sculpture rather than a word: a curled arrow for undo, a block cut by
## a blade for split, two blocks for duplicate. The timeline's tools are things in the room, and
## a thing in the room says what it is by its shape -- the hover card says it in words for anyone
## who has not learnt the shapes yet.
##
## Built from a handful of primitives in a unit square (-1..1 each way), scaled by `size`, all in
## one finish, so a glyph can be relit (`set_light`) without rebuilding it.

## Half the glyph's width, in metres.
var size := 0.0105
var _material: StandardMaterial3D
var _kind := &""


## A glyph of `kind` in `colour`. An unknown kind is a dot, so a typo is visible and not nothing.
static func of(kind: StringName, colour: Color, half := 0.0105) -> TimelineGlyph:
	var g := TimelineGlyph.new()
	g.size = half
	g._kind = kind
	g._material = StandardMaterial3D.new()
	g._material.roughness = 0.32
	g._material.metallic = 0.15
	g._material.emission_enabled = true
	g.set_light(colour, 1.0)
	g._build()
	return g


## How it is lit: its colour, and how brightly it glows (0 dark, 1 lit, above that hot).
func set_light(colour: Color, glow: float) -> void:
	_material.albedo_color = colour.lerp(Color(0.1, 0.1, 0.12), 0.35 if glow < 0.5 else 0.0)
	_material.emission = colour
	_material.emission_energy_multiplier = 0.08 + glow * 1.15
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if glow < 0.2 else BaseMaterial3D.TRANSPARENCY_DISABLED
	_material.albedo_color.a = 0.45 if glow < 0.2 else 1.0


func _build() -> void:
	var s := size
	scale = Vector3(s, s, s)
	match _kind:
		&"undo", &"redo":
			var m := -1.0 if _kind == &"redo" else 1.0
			_arc(Vector2(0.1 * m, -0.15), 0.62, 25.0, 185.0, 0.15, m)
			_cone(Vector2(-0.52 * m, -0.28), Vector2(0, -1), 0.34, 0.5)
		&"split":
			_box(Vector2(-0.56, 0), Vector2(0.72, 0.95), 0.6)
			_box(Vector2(0.56, 0), Vector2(0.72, 0.95), 0.6)
			_rod(Vector2(0, -1.15), Vector2(0, 1.15), 0.08, 0.5)
		&"duplicate":
			_box(Vector2(-0.25, 0.25), Vector2(1.1, 0.8), 0.5, -0.2)
			_box(Vector2(0.25, -0.25), Vector2(1.1, 0.8), 0.5, 0.25)
		&"delete":
			_box(Vector2.ZERO, Vector2(2.0, 0.34), 0.4, 0.0, 45.0)
			_box(Vector2.ZERO, Vector2(2.0, 0.34), 0.4, 0.0, -45.0)
		&"ripple_delete":
			_box(Vector2(-0.45, 0.45), Vector2(1.0, 0.18), 0.3, 0.0, 45.0)
			_box(Vector2(-0.45, 0.45), Vector2(1.0, 0.18), 0.3, 0.0, -45.0)
			_box(Vector2(0.55, -0.45), Vector2(0.8, 0.5), 0.45)
			_cone(Vector2(-0.3, -0.45), Vector2(-1, 0), 0.28, 0.45)
			_rod(Vector2(-0.15, -0.45), Vector2(0.1, -0.45), 0.09, 0.3)
		&"ripple":
			# A train of blocks with an arrow under it: what follows comes along.
			for k in 3:
				_box(Vector2(-0.68 + k * 0.68, 0.32), Vector2(0.52, 0.62), 0.5)
			_rod(Vector2(-0.95, -0.55), Vector2(0.5, -0.55), 0.1, 0.4)
			_cone(Vector2(0.68, -0.55), Vector2(1, 0), 0.3, 0.45)
		&"select_all":
			for gx in [-0.68, 0.0, 0.68]:
				for gy in [0.34, -0.34]:
					_box(Vector2(gx, gy), Vector2(0.54, 0.5), 0.45)
		&"zoom_out", &"zoom_in":
			_ring(Vector2(-0.18, 0.18), 0.66, 0.14)
			_rod(Vector2(0.32, -0.32), Vector2(0.92, -0.92), 0.17, 0.4)
			_box(Vector2(-0.18, 0.18), Vector2(0.64, 0.16), 0.3)
			if _kind == &"zoom_in":
				_box(Vector2(-0.18, 0.18), Vector2(0.16, 0.64), 0.3)
		&"fit":
			for m in [-1.0, 1.0]:
				_rod(Vector2(0.95 * m, -0.8), Vector2(0.95 * m, 0.8), 0.11, 0.4)
				_rod(Vector2(0.95 * m, 0.8), Vector2(0.62 * m, 0.8), 0.11, 0.4)
				_rod(Vector2(0.95 * m, -0.8), Vector2(0.62 * m, -0.8), 0.11, 0.4)
				_cone(Vector2(0.48 * m, 0), Vector2(m, 0), 0.28, 0.4)
			_rod(Vector2(-0.3, 0), Vector2(0.3, 0), 0.1, 0.4)
		&"lanes":
			for y in [0.62, 0.0, -0.62]:
				_box(Vector2(0, y), Vector2(1.9, 0.34), 0.18)
		&"shelves":
			var i := 0
			for y in [0.62, 0.0, -0.62]:
				_box(Vector2(-0.3 + i * 0.3, y), Vector2(1.2, 0.4), 0.9, 0.45 - i * 0.2)
				i += 1
		&"road":
			_rod(Vector2(-1.0, -0.95), Vector2(-0.25, 0.95), 0.12, 0.3)
			_rod(Vector2(1.0, -0.95), Vector2(0.25, 0.95), 0.12, 0.3)
			for y in [-0.65, 0.0, 0.6]:
				_box(Vector2(0, y), Vector2(0.12, 0.3 - y * 0.1), 0.3)
		&"save":
			_rod(Vector2(0, 1.0), Vector2(0, 0.0), 0.15, 0.4)
			_cone(Vector2(0, -0.12), Vector2(0, -1), 0.36, 0.5)
			_rod(Vector2(-0.85, -0.3), Vector2(-0.85, -0.88), 0.12, 0.4)
			_rod(Vector2(-0.85, -0.88), Vector2(0.85, -0.88), 0.12, 0.4)
			_rod(Vector2(0.85, -0.88), Vector2(0.85, -0.3), 0.12, 0.4)
		&"recover":
			# The save's tray with an arrow coming back up out of it, and a spark: the kept copy.
			_rod(Vector2(0, -0.6), Vector2(0, 0.55), 0.15, 0.4)
			_cone(Vector2(0, 0.68), Vector2(0, 1), 0.36, 0.5)
			_rod(Vector2(-0.85, -0.3), Vector2(-0.85, -0.88), 0.12, 0.4)
			_rod(Vector2(-0.85, -0.88), Vector2(0.85, -0.88), 0.12, 0.4)
			_rod(Vector2(0.85, -0.88), Vector2(0.85, -0.3), 0.12, 0.4)
			_ball(Vector2(0.72, 0.72), 0.17, 0.3)
		&"item":
			_box(Vector2(0, -0.1), Vector2(1.9, 1.0), 0.5)
			var hs := [0.3, 0.7, 0.45, 0.85, 0.35, 0.6]
			for k in hs.size():
				_box(Vector2(-0.75 + k * 0.3, -0.1), Vector2(0.16, hs[k]), 0.35, 0.4)
		&"track":
			_gem(Vector2.ZERO, 0.95)
		&"tempo", &"bpm":
			_prism(Vector2(0, -0.1), Vector2(1.3, 1.7), 0.6)
			_rod(Vector2(0, -0.55), Vector2(0.55, 0.85), 0.09, 0.55)
			_ball(Vector2(0.38, 0.42), 0.17, 0.6)
		&"render":
			_ring(Vector2.ZERO, 0.72, 0.2)
			_ball(Vector2.ZERO, 0.22, 0.0)
		&"render_mix":
			_ring(Vector2(-0.2, 0), 0.62, 0.17)
			_ball(Vector2(-0.2, 0), 0.18, 0.0)
			_cone(Vector2(0.78, 0), Vector2(1, 0), 0.3, 0.45)
		&"render_stems":
			for k in 3:
				_ring(Vector2(-0.5 + k * 0.5, 0.25 - k * 0.25), 0.42, 0.11)
		&"lock":
			_arc(Vector2(0, 0.15), 0.42, 0.0, 180.0, 0.12)
			_box(Vector2(0, -0.35), Vector2(1.2, 0.95), 0.5)
		&"mute":
			_ring(Vector2.ZERO, 0.72, 0.15)
			_rod(Vector2(-0.6, -0.6), Vector2(0.6, 0.6), 0.14, 0.3)
		&"normalise":
			_box(Vector2(0, 0.85), Vector2(1.8, 0.2), 0.4)
			_rod(Vector2(0, -0.95), Vector2(0, 0.25), 0.15, 0.4)
			_cone(Vector2(0, 0.38), Vector2(0, 1), 0.36, 0.45)
		&"copy_here":
			_box(Vector2(-0.4, 0), Vector2(0.95, 0.85), 0.55)
			_rod(Vector2(0.6, -1.0), Vector2(0.6, 0.85), 0.08, 0.4)
			_ball(Vector2(0.6, 0.95), 0.2, 0.0)
		&"region", &"region_add":
			# A span between two posts, its name's slab along the top.
			_box(Vector2(-0.85, 0.0), Vector2(0.16, 1.6), 0.4)
			_box(Vector2(0.85, 0.0), Vector2(0.16, 1.6), 0.4)
			_box(Vector2(0.0, 0.5), Vector2(1.55, 0.42), 0.5)
			_rod(Vector2(-0.75, -0.25), Vector2(0.75, -0.25), 0.06, 0.25)
			if _kind == &"region_add":
				_box(Vector2(0.0, -0.45), Vector2(0.7, 0.18), 0.55)
				_box(Vector2(0.0, -0.45), Vector2(0.18, 0.7), 0.55)
		&"loop":
			_ring(Vector2.ZERO, 0.66, 0.15)
			_cone(Vector2(0.66, 0.0), Vector2(0, -1), 0.3, 0.45)
		&"crossfade":
			_rod(Vector2(-0.95, -0.7), Vector2(0.95, 0.7), 0.13, 0.4)
			_rod(Vector2(-0.95, 0.7), Vector2(0.95, -0.7), 0.13, 0.4)
		&"pitch_up", &"pitch_down":
			var d := 1.0 if _kind == &"pitch_up" else -1.0
			_cone(Vector2(0, 0.15 * d), Vector2(0, d), 0.6, 0.85)
			_box(Vector2(0, -0.7 * d), Vector2(1.3, 0.2), 0.3)
		&"quantise":
			for x in [-0.7, 0.0, 0.7]:
				_rod(Vector2(x, -0.95), Vector2(x, 0.95), 0.05, 0.25)
			_box(Vector2(-0.7, 0.45), Vector2(0.4, 0.3), 0.55)
			_box(Vector2(0.0, -0.2), Vector2(0.4, 0.3), 0.55)
			_box(Vector2(0.7, 0.2), Vector2(0.4, 0.3), 0.55)
		&"reverse":
			# A wave's swell, and an arrow back along it.
			_box(Vector2(-0.6, 0.3), Vector2(0.18, 0.25), 0.4)
			_box(Vector2(-0.25, 0.3), Vector2(0.18, 0.55), 0.4)
			_box(Vector2(0.1, 0.3), Vector2(0.18, 0.85), 0.4)
			_box(Vector2(0.45, 0.3), Vector2(0.18, 1.1), 0.4)
			_rod(Vector2(0.75, -0.6), Vector2(-0.45, -0.6), 0.08, 0.35)
			_cone(Vector2(-0.45, -0.6), Vector2(-1, 0), 0.25, 0.4)
		&"humanise":
			# Notes as a hand plays them: off the grid, each its own size and lean.
			_box(Vector2(-0.62, 0.42), Vector2(0.55, 0.36), 0.55, 0.0, 14.0)
			_box(Vector2(0.05, -0.35), Vector2(0.42, 0.28), 0.55, 0.0, -10.0)
			_box(Vector2(0.66, 0.30), Vector2(0.5, 0.42), 0.55, 0.0, 6.0)
			_arc(Vector2(-0.3, -0.75), 0.3, 200.0, 340.0, 0.06)
			_arc(Vector2(0.3, -0.75), 0.3, 160.0, 20.0, 0.06)
		&"swing":
			# A swung pair: long, then short, on a line.
			_box(Vector2(-0.42, 0.15), Vector2(0.95, 0.55), 0.5)
			_box(Vector2(0.68, 0.15), Vector2(0.42, 0.55), 0.5)
			_rod(Vector2(-0.95, -0.55), Vector2(0.95, -0.55), 0.07, 0.25)
		&"softer", &"harder":
			var hs := [1.6, 0.9, 0.45] if _kind == &"softer" else [0.45, 0.9, 1.6]
			for k in 3:
				_box(Vector2(-0.62 + k * 0.62, -0.9 + hs[k] * 0.5), Vector2(0.42, hs[k]), 0.4)
		&"add":
			_box(Vector2.ZERO, Vector2(1.6, 0.34), 0.4)
			_box(Vector2.ZERO, Vector2(0.34, 1.6), 0.4)
		&"remove":
			_box(Vector2.ZERO, Vector2(1.6, 0.34), 0.4)
		&"rename":
			_rod(Vector2(-0.55, -0.55), Vector2(0.7, 0.7), 0.2, 0.4)
			_cone(Vector2(-0.7, -0.7), Vector2(-1, -1), 0.2, 0.4)
			_box(Vector2(0, -0.92), Vector2(1.8, 0.1), 0.2)
		&"colour":
			_ball(Vector2(-0.45, -0.3), 0.42, 0.0)
			_ball(Vector2(0.45, -0.3), 0.42, 0.1)
			_ball(Vector2(0.0, 0.42), 0.42, 0.2)
		&"scheme":
			for k in 4:
				_ball(Vector2(-0.75 + k * 0.5, 0.0), 0.26, 0.0)
			_box(Vector2(0, -0.6), Vector2(1.9, 0.12), 0.2)
		&"input":
			_rod(Vector2(-1.0, 0), Vector2(0.15, 0), 0.16, 0.4)
			_ring(Vector2(0.55, 0), 0.38, 0.12)
			_ball(Vector2(0.55, 0), 0.14, 0.0)
		&"auto":
			var prev := Vector2(-1.0, -0.2)
			for k in range(1, 9):
				var p := Vector2(-1.0 + k * 0.25, sin(k * 0.8) * 0.6)
				_rod(prev, p, 0.1, 0.35)
				prev = p
		&"lane":
			var pts := [Vector2(-0.95, -0.6), Vector2(-0.3, 0.5), Vector2(0.35, 0.1), Vector2(0.95, 0.75)]
			for k in range(1, pts.size()):
				_rod(pts[k - 1], pts[k], 0.08, 0.3)
			for p in pts:
				_ball(p, 0.17, 0.1)
		&"ramp":
			_rod(Vector2(-0.95, -0.7), Vector2(0.95, 0.7), 0.12, 0.4)
			_ball(Vector2(-0.95, -0.7), 0.22, 0.0)
			_ball(Vector2(0.95, 0.7), 0.22, 0.0)
			_box(Vector2(0, -0.92), Vector2(1.9, 0.08), 0.2)
		&"gain":
			_ring(Vector2.ZERO, 0.72, 0.14)
			_rod(Vector2.ZERO, Vector2(0.42, 0.5), 0.13, 0.4)
			_ball(Vector2.ZERO, 0.2, 0.1)
		&"fade_in":
			_rod(Vector2(-0.95, -0.8), Vector2(0.95, 0.8), 0.13, 0.4)
			_box(Vector2(0, -0.88), Vector2(1.9, 0.1), 0.2)
		&"fade_out":
			_rod(Vector2(-0.95, 0.8), Vector2(0.95, -0.8), 0.13, 0.4)
			_box(Vector2(0, -0.88), Vector2(1.9, 0.1), 0.2)
		&"depth_16", &"depth_24":
			# A sine sampled in steps: fewer for fewer bits.
			var n := 5 if _kind == &"depth_16" else 9
			var w := 1.9 / n
			for k in n:
				var x := -0.95 + w * (k + 0.5)
				var y := roundf(sin(x * PI / 0.95) * (2.0 if n == 5 else 4.0)) / (2.0 if n == 5 else 4.0) * 0.75
				_box(Vector2(x, y), Vector2(w * 0.92, 0.22), 0.35)
		&"depth_32":
			_arc(Vector2(-0.475, 0.0), 0.475, 180.0, 0.0, 0.1)
			_arc(Vector2(0.475, 0.0), 0.475, 180.0, 360.0, 0.1)
		&"grid_bar", &"grid_4", &"grid_8", &"grid_16", &"grid_off":
			_box(Vector2.ZERO, Vector2(1.9, 0.9), 0.3)
			var cells: int = {&"grid_4": 4, &"grid_8": 8, &"grid_16": 16}.get(_kind, 1)
			for k in range(1, cells):
				var x := -0.95 + 1.9 * k / cells
				_rod(Vector2(x, -0.62), Vector2(x, 0.62), 0.07 if cells < 16 else 0.04, 0.42)
			if _kind == &"grid_off":
				_rod(Vector2(-0.9, -0.8), Vector2(0.9, 0.8), 0.12, 0.5)
		_:
			_ball(Vector2.ZERO, 0.4, 0.0)


## Each part a hair further out than the one before: two parts of one mark that cross (the
## strokes of a cross, a ring and the bar in it) would otherwise share their faces' plane.
func _add(mesh: Mesh, at: Vector3, basis := Basis.IDENTITY) -> MeshInstance3D:
	at.z += get_child_count() * 0.045
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = _material
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.transform = Transform3D(basis, at)
	add_child(m)
	return m


func _box(at: Vector2, extent: Vector2, depth: float, z := 0.0, degrees := 0.0) -> void:
	var b := BoxMesh.new()
	b.size = Vector3(extent.x, extent.y, depth)
	_add(b, Vector3(at.x, at.y, z + depth * 0.5), Basis(Vector3.BACK, deg_to_rad(degrees)))


## A rod from a to b, round, `r` thick, standing `z` out.
func _rod(a: Vector2, b: Vector2, r: float, z := 0.3) -> void:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = (b - a).length() + r
	c.radial_segments = 10
	c.rings = 1
	var mid := (a + b) * 0.5
	_add(c, Vector3(mid.x, mid.y, z), Basis(Vector3.BACK, (b - a).angle() - PI * 0.5))


func _arc(centre: Vector2, radius: float, from_deg: float, to_deg: float, r: float, mirror := 1.0) -> void:
	var steps := 9
	var prev := Vector2.ZERO
	for k in steps + 1:
		var a := deg_to_rad(lerpf(from_deg, to_deg, float(k) / steps))
		var p := centre + Vector2(cos(a) * radius * mirror, sin(a) * radius)
		if k > 0:
			_rod(prev, p, r)
		prev = p


func _cone(at: Vector2, towards: Vector2, r: float, length: float) -> void:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = length
	c.radial_segments = 12
	c.rings = 1
	_add(c, Vector3(at.x, at.y, 0.3), Basis(Vector3.BACK, towards.angle() - PI * 0.5))


## A ring facing out of the glyph.
func _ring(at: Vector2, radius: float, r: float) -> void:
	var t := TorusMesh.new()
	t.inner_radius = radius - r
	t.outer_radius = radius + r
	t.rings = 24
	t.ring_segments = 8
	_add(t, Vector3(at.x, at.y, 0.3), Basis(Vector3.RIGHT, PI * 0.5))


func _ball(at: Vector2, r: float, z := 0.0) -> void:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 14
	s.rings = 7
	_add(s, Vector3(at.x, at.y, 0.3 + z))


## A cut stone: an octahedron, its points up and down.
func _gem(at: Vector2, r: float) -> void:
	var s := SphereMesh.new()
	s.radius = r * 0.8
	s.height = r * 2.0
	s.radial_segments = 4
	s.rings = 1
	_add(s, Vector3(at.x, at.y, 0.4), Basis(Vector3.UP, PI * 0.25))


func _prism(at: Vector2, extent: Vector2, depth: float, degrees := 0.0) -> void:
	var p := PrismMesh.new()
	p.size = Vector3(extent.x, extent.y, depth)
	_add(p, Vector3(at.x, at.y, depth * 0.5), Basis(Vector3.BACK, deg_to_rad(degrees)))
