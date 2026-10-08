class_name Chalk
extends RefCounted

## Drawing in chalk: polylines in, stroke meshes out, plus a small alphabet of doodles.
##
## Everything in the chalk zone that is drawn -- the floating stars and planets, the outline of
## the working floor -- is built here, as a polyline baked into a mesh that `chalk_stroke`
## widens on the GPU. One material draws all of it, so the whole zone can glow to the music by
## setting one uniform.
##
## The doodles are deliberately unsteady. A perfect circle in chalk reads as a vector graphic
## pretending; a hand-drawn one wobbles, overshoots where it closes, and is often gone over
## twice. `wobble` and the second pass in `stroke_mesh` are that hand.

const PINK := Color(1.0, 0.25, 0.75)
const CYAN := Color(0.2, 0.95, 1.0)
const LIME := Color(0.6, 1.0, 0.25)
const YELLOW := Color(1.0, 0.92, 0.3)
const ORANGE := Color(1.0, 0.55, 0.15)
const VIOLET := Color(0.7, 0.4, 1.0)
const WHITE := Color(0.92, 0.94, 1.0)
const NEON: Array[Color] = [PINK, CYAN, LIME, YELLOW, ORANGE, VIOLET]

static var _material: ShaderMaterial


## The one material every stroke shares.
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://core/venues/shaders/chalk_stroke.gdshader")
	return _material


## Bake polylines into one mesh. Each entry of `lines` is a PackedVector3Array; `width` is the
## half-width in metres. `flat` lays the strokes on the ground instead of turning them to face
## the eye. `passes` above 1 goes over each line again slightly off the first, as a hand does.
static func stroke_mesh(lines: Array, colour: Color, width: float, flat := false,
		passes := 1, rng: RandomNumberGenerator = null) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colours := PackedColorArray()
	var index := PackedInt32Array()
	for line: PackedVector3Array in lines:
		for p in passes:
			var drawn := line
			if p > 0 and rng != null:
				drawn = wobble(line, width * 1.6, rng)
			if drawn.size() < 2:
				continue
			var run := 0.0
			for i in drawn.size():
				var prev := drawn[maxi(i - 1, 0)]
				var next := drawn[mini(i + 1, drawn.size() - 1)]
				var tangent := (next - prev).normalized()
				if i > 0:
					run += drawn[i].distance_to(drawn[i - 1])
				# Thinner at the ends, where the chalk lifts off the board.
				var t := float(i) / float(drawn.size() - 1)
				var taper := clampf(minf(t, 1.0 - t) * 8.0, 0.35, 1.0)
				var base := verts.size()
				for s in [-1.0, 1.0]:
					verts.append(drawn[i])
					normals.append(tangent)
					uvs.append(Vector2(run, s))
					uv2s.append(Vector2(width * taper * (1.0 if p == 0 else 0.7), 1.0 if flat else 0.0))
					colours.append(colour)
				if i > 0:
					index.append_array([base - 2, base - 1, base, base - 1, base + 1, base])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = index
	var mesh := ArrayMesh.new()
	if not verts.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A node that draws `lines`. Its cull margin covers the widening the shader does.
static func drawing(lines: Array, colour: Color, width: float, flat := false, passes := 2,
		seed := 0) -> MeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var node := MeshInstance3D.new()
	node.mesh = stroke_mesh(lines, colour, width, flat, passes, rng)
	node.material_override = material()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = width * 4.0
	return node


## Jitter a line by up to `amount`, smoothly, so it reads as a hand and not as noise.
static func wobble(line: PackedVector3Array, amount: float, rng: RandomNumberGenerator) -> PackedVector3Array:
	var out := PackedVector3Array()
	var drift := Vector3.ZERO
	for p in line:
		drift = drift * 0.7 + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1),
				rng.randf_range(-1, 1)) * amount * 0.3
		out.append(p + drift)
	return out


## Points around an ellipse in the XY plane, starting at `from` and running `sweep` radians.
static func arc(centre: Vector3, rx: float, ry: float, from: float, sweep: float,
		steps := 32) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in steps + 1:
		var a := from + sweep * float(i) / float(steps)
		out.append(centre + Vector3(cos(a) * rx, sin(a) * ry, 0.0))
	return out


## A circle that overshoots where it closes, the way a quick one in chalk always does.
static func loop(centre: Vector3, r: float, steps := 40) -> PackedVector3Array:
	return arc(centre, r, r, 0.4, TAU + 0.35, steps)


# ---- the doodle alphabet. Each is unit-ish size in the XY plane, facing +Z. -----------------

static func star(points := 5) -> Array:
	var line := PackedVector3Array()
	for i in points * 2 + 1:
		var a := PI * 0.5 + PI * float(i) / float(points)
		var r := 1.0 if i % 2 == 0 else 0.42
		line.append(Vector3(cos(a) * r, sin(a) * r, 0.0))
	return [line]


static func spiral(turns := 3.0) -> Array:
	var line := PackedVector3Array()
	var steps := int(turns * 28)
	for i in steps + 1:
		var t := float(i) / float(steps)
		var a := t * turns * TAU
		line.append(Vector3(cos(a), sin(a), 0.0) * t)
	return [line]


static func cloud() -> Array:
	var line := PackedVector3Array()
	var bumps := [[-0.7, 0.0, 0.35], [-0.3, 0.3, 0.42], [0.2, 0.35, 0.45], [0.65, 0.05, 0.35]]
	for b in bumps:
		line.append_array(arc(Vector3(b[0], b[1], 0), b[2], b[2], PI * 1.05, -PI * 1.1, 14))
	line.append(Vector3(-1.05, -0.05, 0))
	return [line, PackedVector3Array([Vector3(-1.05, -0.12, 0), Vector3(1.0, -0.12, 0)])]


static func moon() -> Array:
	var outer := arc(Vector3.ZERO, 1.0, 1.0, PI * 0.35, PI * 1.3, 30)
	var inner := arc(Vector3(-0.38, 0.0, 0), 0.78, 0.78, PI * 1.62, -PI * 1.24, 26)
	inner.append(outer[0])
	return [outer, inner]


static func lightning() -> Array:
	return [PackedVector3Array([Vector3(0.2, 1.0, 0), Vector3(-0.35, 0.05, 0),
			Vector3(0.12, 0.08, 0), Vector3(-0.3, -1.0, 0), Vector3(0.45, 0.25, 0),
			Vector3(-0.02, 0.2, 0), Vector3(0.45, 1.0, 0)])]


static func heart() -> Array:
	var line := PackedVector3Array()
	for i in 49:
		var t := TAU * float(i) / 48.0
		var x := 16.0 * pow(sin(t), 3.0)
		var y := 13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t)
		line.append(Vector3(x, y, 0.0) / 16.0)
	return [line]


static func planet() -> Array:
	var body := loop(Vector3.ZERO, 0.62)
	# The ring passes behind the planet, so its back half is not drawn.
	var ring := arc(Vector3.ZERO, 1.25, 0.32, -0.25, PI + 0.5, 30)
	var front := PackedVector3Array()
	for p in ring:
		front.append(Vector3(p.x, -p.y * 0.9 - p.x * 0.18, 0.0))
	return [body, front]


static func note() -> Array:
	var head := loop(Vector3(-0.25, -0.75, 0), 0.24, 20)
	for i in head.size():
		head[i] = Vector3(-0.25 + (head[i].x + 0.25) * 1.25, head[i].y, 0)
	var stem := PackedVector3Array([Vector3(0.05, -0.72, 0), Vector3(0.05, 0.9, 0)])
	var flag := PackedVector3Array([Vector3(0.05, 0.9, 0), Vector3(0.45, 0.55, 0),
			Vector3(0.55, 0.15, 0), Vector3(0.35, -0.15, 0)])
	return [head, stem, flag]


static func sparkle() -> Array:
	return [PackedVector3Array([Vector3(0, 1, 0), Vector3(0, -1, 0)]),
			PackedVector3Array([Vector3(-1, 0, 0), Vector3(1, 0, 0)]),
			PackedVector3Array([Vector3(-0.5, 0.5, 0), Vector3(0.5, -0.5, 0)]),
			PackedVector3Array([Vector3(-0.5, -0.5, 0), Vector3(0.5, 0.5, 0)])]


static func shapes() -> Array[Callable]:
	return [star, spiral, cloud, moon, lightning, heart, planet, note, sparkle]
