# Builds the radio-controlled plane and its transmitter, and writes assets/models/rcplane.glb.
#
#     blender --background --python tools/blender/rcplane.py
#
# A little foam trainer (docs/items_loop.md): high wing, fat body, tail, two wheels and a tail
# wheel, and the radio you fly it from. Three objects, Godot's y up and -Z forward:
#   "Plane"  the airframe, its origin at its middle, nose toward -Z; its wheels touch y = -WHEELS.
#   "Prop"   the propeller, its origin at its hub, blades along X, spun about Z.
#   "Radio"  the transmitter, held flat, sticks up, aerial out of the far edge (-Z); its origin
#            the middle of the case.
# Materials named for what they are: foam, trim, dark (the cowl, tyres, legs and prop), case, metal,
# led. Few of them, since each is a draw, and each again in every shadow it casts.
#
# Sizes in Godot's terms, which RcPlaneItem repeats.

import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
WHEELS = 0.059
NOSE = -0.135

bpy.ops.wm.read_factory_settings(use_empty=True)


def g(v):
	# Godot's (x, y up, z toward you) as Blender's (x, -z, y).
	return Vector((v[0], -v[2], v[1]))


def godot(v):
	return Vector((v[0], v[2], -v[1]))


class Part:
	def __init__(self, name, mats):
		self.name = name
		self.mats = mats
		self.bm = bmesh.new()

	def _add(self, geom_verts, mat):
		faces = {f for v in geom_verts for f in v.link_faces}
		for f in faces:
			f.material_index = self.mats.index(mat)

	def box(self, lo, hi, mat, taper=None):
		# A box from `lo` to `hi` (Godot); `taper` (sx, sy) scales its -Z end's cross-section
		# about the middle.
		before = set(self.bm.verts)
		res = bmesh.ops.create_cube(self.bm, size=1.0)
		c = [(lo[i] + hi[i]) * 0.5 for i in range(3)]
		s = [hi[i] - lo[i] for i in range(3)]
		for v in res["verts"]:
			p = godot(v.co)
			p = Vector((p.x * s[0], p.y * s[1], p.z * s[2]))
			if taper is not None and p.z < 0:
				p.x *= taper[0]
				p.y *= taper[1]
			v.co = g(p + Vector(c))
		self._add(res["verts"], mat)
		return res["verts"]

	def tube(self, r, a, b, mat, segments=12, r2=None):
		# A cylinder from Godot point `a` to `b`.
		a, b = Vector(a), Vector(b)
		res = bmesh.ops.create_cone(self.bm, cap_ends=True, segments=segments, radius1=r,
				radius2=r if r2 is None else r2, depth=(b - a).length)
		axis = g(b - a).normalized()
		rot = Vector((0, 0, 1)).rotation_difference(axis).to_matrix().to_4x4()
		bmesh.ops.transform(self.bm, matrix=Matrix.Translation(g((a + b) * 0.5)) @ rot, verts=res["verts"])
		self._add(res["verts"], mat)
		return res["verts"]

	def ball(self, r, at, mat, scale=(1, 1, 1)):
		res = bmesh.ops.create_uvsphere(self.bm, u_segments=14, v_segments=8, radius=r)
		for v in res["verts"]:
			p = godot(v.co)
			v.co = g(Vector((p.x * scale[0], p.y * scale[1], p.z * scale[2])) + Vector(at))
		self._add(res["verts"], mat)
		return res["verts"]

	def finish(self, smooth=False):
		for f in self.bm.faces:
			f.smooth = smooth
		mesh = bpy.data.meshes.new(self.name)
		self.bm.normal_update()
		self.bm.to_mesh(mesh)
		self.bm.free()
		ob = bpy.data.objects.new(self.name, mesh)
		bpy.context.collection.objects.link(ob)
		for m in self.mats:
			ob.data.materials.append(bpy.data.materials.get(m) or bpy.data.materials.new(m))
		return ob


# The airframe.
plane = Part("Plane", ["foam", "trim", "dark"])
# The body: deep and wide at the cockpit, narrowing to a thin tail.
plane.box((-0.021, -0.024, -0.105), (0.021, 0.026, 0.0), "foam", taper=(0.8, 0.85))
plane.box((-0.021, -0.024, 0.0), (0.021, 0.026, 0.155), "foam")
# Pull the tail end in: every vertex behind the wing narrows toward the tail.
for v in plane.bm.verts:
	p = godot(v.co)
	if p.z > 0.001:
		k = 1.0 - 0.72 * (p.z / 0.155)
		p.x *= k
		p.y = 0.018 + (p.y - 0.018) * k if p.y < 0.018 else 0.018 + (p.y - 0.018) * max(k, 0.4)
		v.co = g(p)
# The cowl, and a red stripe down each side.
plane.box((-0.018, -0.02, NOSE + 0.004), (0.018, 0.022, -0.103), "dark")
plane.box((-0.0222, -0.006, -0.1), (0.0222, 0.0, 0.07), "trim")
# The wing on top: a flat slab, tips raised a little (dihedral), red tips.
for side in (-1, 1):
	verts = plane.box((min(0, 0.17 * side), 0.026, -0.072), (max(0, 0.17 * side), 0.034, -0.008), "foam")
	for v in verts:
		p = godot(v.co)
		p.y += abs(p.x) * 0.1
		# A little swept and tapered toward the tip.
		t = abs(p.x) / 0.17
		mid = -0.04
		p.z = mid + (p.z - mid) * (1.0 - 0.3 * t) + 0.006 * t
		v.co = g(p)
	tip = 0.17 * side
	plane.box((min(tip, tip - 0.03 * side), 0.0265 + 0.017, -0.06), (max(tip, tip - 0.03 * side), 0.0345 + 0.0175, -0.016), "trim")
# The tail: a stabiliser and a fin.
plane.box((-0.065, 0.014, 0.112), (0.065, 0.019, 0.155), "foam")
plane.box((-0.065, 0.0141, 0.112), (-0.045, 0.0191, 0.155), "trim")
plane.box((0.045, 0.0141, 0.112), (0.065, 0.0191, 0.155), "trim")
plane.box((-0.002, 0.018, 0.1), (0.002, 0.07, 0.158), "trim")
for v in plane.bm.verts:
	p = godot(v.co)
	# Sweep the fin's leading edge back as it rises.
	if p.y > 0.019 and abs(p.x) <= 0.0021 and p.z < 0.12:
		p.z += (p.y - 0.018) * 0.7
		v.co = g(p)
# The undercarriage: wire legs and two wheels, and a little tail wheel.
for side in (-1, 1):
	plane.tube(0.0018, (0.012 * side, -0.02, -0.07), (0.045 * side, -WHEELS + 0.014, -0.075), "dark", 6)
	plane.tube(0.014, (0.045 * side - 0.004, -WHEELS + 0.014, -0.075), (0.045 * side + 0.004, -WHEELS + 0.014, -0.075), "dark", 16)
plane.tube(0.0015, (0, -0.012, 0.13), (0, -WHEELS + 0.007, 0.142), "dark", 6)
plane.tube(0.007, (-0.002, -WHEELS + 0.007, 0.142), (0.002, -WHEELS + 0.007, 0.142), "dark", 12)
plane_ob = plane.finish()

# The propeller: two blades, a spinner.
prop = Part("Prop", ["dark"])
for side in (-1, 1):
	verts = prop.box((min(0, 0.062 * side), -0.006, -0.0015), (max(0, 0.062 * side), 0.006, 0.0015), "dark")
	for v in verts:
		p = godot(v.co)
		# Twisted along the blade, narrow at the tip.
		t = abs(p.x) / 0.062
		p.y *= 1.0 - 0.45 * t
		a = 0.5 * (1.0 - t) * side
		p.y, p.z = p.y * math.cos(a) - p.z * math.sin(a), p.y * math.sin(a) + p.z * math.cos(a)
		v.co = g(p)
prop.ball(0.011, (0, 0, -0.006), "dark", (1, 1, 1.4))
prop_ob = prop.finish()
prop_ob.location = g((0, 0.003, NOSE))

# The transmitter: a chunky case, two sticks on gimbals, an aerial, a light.
radio = Part("Radio", ["case", "metal", "led", "trim"])
radio.box((-0.068, -0.017, -0.046), (0.068, 0.017, 0.046), "case")
# Rounded-ish edges: pull the corners in.
for v in radio.bm.verts:
	p = godot(v.co)
	if abs(p.x) > 0.06 and abs(p.z) > 0.04:
		p.x *= 0.93
		p.z *= 0.9
	v.co = g(p)
# Grips under each end.
for side in (-1, 1):
	radio.ball(0.024, (0.05 * side, -0.016, 0.018), "case", (1.0, 0.8, 1.6))
	# A gimbal: a metal dish, a stick, a ball on top.
	radio.tube(0.016, (0.034 * side, 0.016, 0.003), (0.034 * side, 0.0185, 0.003), "metal", 20)
	radio.tube(0.0022, (0.034 * side, 0.018, 0.003), (0.034 * side, 0.041, 0.003), "case", 8)
	radio.ball(0.0045, (0.034 * side, 0.042, 0.003), "case")
# A red band along the near edge, and the light in the middle.
radio.box((-0.06, 0.0165, 0.034), (0.06, 0.0175, 0.042), "trim")
radio.tube(0.0035, (0, 0.016, 0.026), (0, 0.0195, 0.026), "led", 10)
# The aerial: out of the far edge, up and away from you.
radio.tube(0.006, (0.05, 0.004, -0.044), (0.05, 0.004, -0.056), "case", 10)
radio.tube(0.0022, (0.05, 0.004, -0.054), (0.05, 0.1, -0.12), "metal", 6, r2=0.0016)
radio.ball(0.0035, (0.05, 0.1, -0.12), "case")
radio_ob = radio.finish()

for ob in bpy.data.objects:
	lo = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
	mn = godot(Vector(tuple(min(v[i] for v in lo) for i in range(3))))
	mx = godot(Vector(tuple(max(v[i] for v in lo) for i in range(3))))
	print(ob.name, "bounds (godot)", tuple(round(min(mn[i], mx[i]), 4) for i in range(3)),
			tuple(round(max(mn[i], mx[i]), 4) for i in range(3)), len(ob.data.polygons), "faces")
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/rcplane.glb"), export_format="GLB")
print("wrote assets/models/rcplane.glb")
