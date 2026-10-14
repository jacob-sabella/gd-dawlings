# Builds every venue's own toy, and writes assets/models/toys.glb.
#
#     blender --background --python tools/blender/toys.py
#
# One throwable toy per venue (docs/items_loop.md), each its own object with its origin at its
# middle, Godot's y up:
#   "Sack"      the studio's hacky sack: a knit beanbag in panels, lumpy.
#   "Glow"      the grid's neon ball: a dark shell with three glowing bands round it.
#   "Paper"     the chalk zone's ball of paper, crumpled.
#   "Tennis"    the loft's tennis ball, its seam.
#   "Snowball"  the cabin's snowball, packed by hand.
#   "Beach"     the rooftop's beach ball: six gores and white caps.
#   "Planet"    the station's foam planet: sea, land and ice.
#   "Starfish"  the dome's rubber starfish, lying flat, dotted.
#   "Eight"     the club's eight ball, its white spot facing +Z (the 8 is drawn on in Godot).
#   "Geode"     the crystal cave's geode: a lumpy grey stone split open on a face of amethyst.
#   "Lemon"     the glasshouse's lemon, off the tree in the corner: pointed ends, dimpled rind.
#   "Stick"     the festival stage's glow stick, lying along Godot's x, its caps dark.
#   "Temari"    the temple garden's temari ball: silk thread wound in bands over a red ball.
#   "Tumble"    the desert's tumbleweed: a light ball of dry twigs, open to the light.
# Materials are named by what they are; ToyItem swaps in its own.
#
# Sizes in Godot's terms, which ToyItem repeats.

import math
import os
import random

import bmesh
import bpy
from mathutils import Vector, noise

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SIZES = {"Sack": 0.03, "Glow": 0.035, "Paper": 0.035, "Tennis": 0.033, "Snowball": 0.04,
		"Beach": 0.2, "Planet": 0.04, "Starfish": 0.075, "Eight": 0.028, "Geode": 0.04,
		"Lemon": 0.036, "Stick": 0.08, "Temari": 0.04, "Tumble": 0.12}
# The glow stick's radius: it lies on the floor this far up.
STICK_RADIUS = 0.0065
STAR_THICK = 0.018

bpy.ops.wm.read_factory_settings(use_empty=True)


def g(v):
	# Godot's (x, y up, z toward you) as Blender's (x, -z, y).
	return Vector((v[0], -v[2], v[1]))


def godot(v):
	return Vector((v[0], v[2], -v[1]))


def finish(bm, name, mats, pick, smooth=True):
	# `pick(face centre in Godot's frame, unit direction)` -> material index.
	for f in bm.faces:
		c = godot(f.calc_center_median())
		f.material_index = pick(c, c.normalized() if c.length > 0 else Vector((0, 1, 0)))
		f.smooth = smooth
	mesh = bpy.data.meshes.new(name)
	bm.normal_update()
	bm.to_mesh(mesh)
	bm.free()
	ob = bpy.data.objects.new(name, mesh)
	bpy.context.collection.objects.link(ob)
	for m in mats:
		ob.data.materials.append(bpy.data.materials.get(m) or bpy.data.materials.new(m))
	return ob


def sphere(r, segments=24, rings=12):
	bm = bmesh.new()
	bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=r)
	return bm


def ico(r, level):
	bm = bmesh.new()
	bmesh.ops.create_icosphere(bm, subdivisions=level, radius=r)
	return bm


def lumpy(bm, r, amount, scale, seed):
	for v in bm.verts:
		d = v.co.normalized()
		n = noise.noise(d * scale + Vector((seed, seed * 2, seed * 3)))
		v.co = d * r * (1.0 + amount * n)


# The hacky sack: eight knit panels, alternate colours, a little squashed and lumpy.
r = SIZES["Sack"]
bm = sphere(r, 20, 10)
lumpy(bm, r, 0.08, 3.0, 1.0)
for v in bm.verts:
	v.co.z *= 0.88
finish(bm, "Sack", ["knit_a", "knit_b"],
		lambda c, d: (int(d.x > 0) + int(d.y > 0) + int(d.z > 0)) % 2)

# The neon ball: three bands, one round each axis.
r = SIZES["Glow"]
bm = sphere(r, 32, 16)
finish(bm, "Glow", ["shell", "glow"],
		lambda c, d: 1 if min(abs(d.x), abs(d.y), abs(d.z)) < 0.13 else 0)

# Crumpled paper: an icosphere pushed in and out hard, flat shaded so every crease shows.
r = SIZES["Paper"]
bm = ico(r, 2)
random.seed(7)
for v in bm.verts:
	d = v.co.normalized()
	v.co = d * r * random.uniform(0.72, 1.08)
finish(bm, "Paper", ["paper"], lambda c, d: 0, smooth=False)

# The tennis ball: felt, and the seam where its two halves meet -- the curve that wanders round
# it like a baseball's.
r = SIZES["Tennis"]
seam = []
for k in range(240):
	t = k / 240 * math.tau
	p = Vector((math.cos(t) + 0.5 * math.cos(3 * t), math.sin(t) - 0.5 * math.sin(3 * t),
			1.6 * math.sin(2 * t)))
	seam.append(p.normalized())
bm = sphere(r, 40, 20)
finish(bm, "Tennis", ["felt", "seam"],
		lambda c, d: 1 if min((d - s).length for s in seam) < 0.075 else 0)

# The snowball: packed in two hands, so round-ish and soft-lumpy.
r = SIZES["Snowball"]
bm = ico(r, 3)
lumpy(bm, r, 0.09, 4.5, 3.0)
finish(bm, "Snowball", ["snow"], lambda c, d: 0)

# The beach ball: six gores round its poles (Godot's x axis, so it rolls end over end), and a
# white cap at each pole.
r = SIZES["Beach"]
bm = sphere(r, 36, 18)
for v in bm.verts:
	# Turn the poles from Blender's z onto x.
	v.co = Vector((v.co.z, v.co.y, -v.co.x))


def gore(c, d):
	if abs(d.x) > 0.93:
		return 3
	a = math.atan2(d.z, d.y) % math.tau
	return int(a / (math.tau / 6)) % 3


finish(bm, "Beach", ["gore_a", "gore_b", "gore_c", "cap"], gore)

# The foam planet: land where noise says, ice at the poles.
r = SIZES["Planet"]
bm = sphere(r, 40, 20)


def planet(c, d):
	if abs(d.y) > 0.86:
		return 2
	return 1 if noise.noise(d * 2.4 + Vector((5.0, 1.0, 2.0))) > 0.12 else 0


finish(bm, "Planet", ["sea", "land", "ice"], planet)

# The starfish: five arms, a dome over a star outline, flat underneath. Its origin is its middle
# -- half its thickness up off the floor, like the round ones.
R = SIZES["Starfish"]
ARMS = 5
AROUND = 60
OUT = 6


def outline(a):
	# How far the edge is from the middle at angle `a`: round-tipped arms, deep between them.
	return R * (0.36 + 0.64 * pow(abs(math.cos(a * ARMS * 0.5)), 1.7))


bm = bmesh.new()
top = []
bottom = []
for i in range(OUT + 1):
	s = i / OUT
	ring_t = []
	ring_b = []
	for k in range(AROUND):
		a = k / AROUND * math.tau
		edge = outline(a)
		x = math.cos(a) * edge * s
		z = math.sin(a) * edge * s
		# Thick in the middle and down each arm's spine, thin at the tips.
		arm = pow(abs(math.cos(a * ARMS * 0.5)), 2.0)
		h = STAR_THICK * (1.0 - 0.55 * s * s) * (0.75 + 0.25 * arm) * math.sqrt(max(0.0, 1.0 - s ** 6))
		y_top = -STAR_THICK * 0.5 + max(h, 0.002 if i == OUT else h)
		ring_t.append(bm.verts.new(g((x, y_top if i < OUT else -STAR_THICK * 0.5 + 0.002, z))))
		ring_b.append(bm.verts.new(g((x, -STAR_THICK * 0.5, z))) if i > 0 else None)
	top.append(ring_t)
	bottom.append(ring_b)
for i in range(OUT):
	for k in range(AROUND):
		j = (k + 1) % AROUND
		if i == 0:
			pass
		bm.faces.new((top[i][k], top[i][j], top[i + 1][j], top[i + 1][k]))
		if i > 0:
			bm.faces.new((bottom[i][k], bottom[i + 1][k], bottom[i + 1][j], bottom[i][j]))
# The edge, top rim down to the bottom rim.
for k in range(AROUND):
	j = (k + 1) % AROUND
	bm.faces.new((top[OUT][k], top[OUT][j], bottom[OUT][j], bottom[OUT][k]))
# Close the bottom's middle.
mid = bm.verts.new(g((0, -STAR_THICK * 0.5, 0)))
for k in range(AROUND):
	j = (k + 1) % AROUND
	bm.faces.new((mid, bottom[1][k], bottom[1][j]))
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.000001)
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)


def dots(c, d):
	# Pale bumps down each arm's spine, on top.
	if c.y < 0.0:
		return 0
	a = math.atan2(c.z, c.x)
	s = math.hypot(c.x, c.z)
	spine = abs(math.sin(a * ARMS * 0.5 - math.pi * 0.5 * 0))
	near = min(abs(((a - k * math.tau / ARMS + math.pi) % math.tau) - math.pi) for k in range(ARMS))
	return 1 if near < 0.09 and int(s / 0.011) % 2 == 1 and s > 0.012 else 0


finish(bm, "Starfish", ["star", "dots"], dots)

# The eight ball: black, and the white circle the 8 is drawn in, facing +Z.
r = SIZES["Eight"]
bm = sphere(r, 36, 18)
finish(bm, "Eight", ["black", "spot"], lambda c, d: 1 if d.z > 0.88 else 0)

# The geode: a rough stone, and where a plane cut it in half, a hollow face of crystal. The cut
# faces +Z, so it lies showing its purple when it comes to rest on its back.
r = SIZES["Geode"]
bm = ico(r, 3)
lumpy(bm, r, 0.12, 2.6, 9.0)
for v in bm.verts:
	gv = godot(v.co)
	if gv.z > r * 0.35:
		# Pressed back to the cut, and a little hollow in its middle, so the crystal is a dish.
		inside = 1.0 - min(1.0, math.hypot(gv.x, gv.y) / (r * 0.95))
		v.co = g((gv.x, gv.y, r * 0.35 - inside * r * 0.25))
finish(bm, "Geode", ["rock", "amethyst"], lambda c, d: 1 if c.z > SIZES["Geode"] * 0.1 else 0,
		smooth=False)

# The lemon: an ellipsoid along Godot's x, drawn to a point at both ends, its rind dimpled.
r = SIZES["Lemon"]
bm = sphere(1.0, 32, 16)
for v in bm.verts:
	gv = godot(v.co)
	x = gv.x
	# Long way along x, a nipple at each end.
	reach = 1.0 + 0.22 * pow(abs(x), 6.0)
	waist = 0.78
	gv = Vector((x * reach * r, gv.y * waist * r, gv.z * waist * r))
	d = gv.normalized()
	gv *= 1.0 + 0.012 * noise.noise(d * 28.0)
	v.co = g(gv)
finish(bm, "Lemon", ["lemon"], lambda c, d: 0)

# The glow stick: a capsule along x, the tube lit, a dark cap at each end.
L = SIZES["Stick"]
bm = bmesh.new()
bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=STICK_RADIUS, radius2=STICK_RADIUS,
		depth=L * 2.0)
for v in bm.verts:
	v.co = Vector((v.co.z, v.co.y, v.co.x))
finish(bm, "Stick", ["lightstick", "stick_cap"],
		lambda c, d: 1 if abs(c.x) > L * 0.86 else 0)

# The temari ball: a red ball, thread wound over it in two crossing bands of gold and a white
# equator, each band a strip of faces chosen by where it lies.
r = SIZES["Temari"]
bm = sphere(r, 48, 24)


def temari(c, d):
	if abs(d.y) < 0.07:
		return 2
	for axis in (Vector((1, 0, 0)), Vector((0, 0, 1)), Vector((0.7071, 0, 0.7071)), Vector((-0.7071, 0, 0.7071))):
		if abs(d.dot(axis)) < 0.05:
			return 1
	return 0


finish(bm, "Temari", ["temari", "thread_a", "thread_b"], temari)

# The tumbleweed: a hundred and ninety dry twigs, each a short bent stick lying across the ball's
# surface, enough of them that it reads as a ball and few enough to see through.
r = SIZES["Tumble"]
random.seed(31)
bm = bmesh.new()
for k in range(190):
	a = Vector((random.gauss(0, 1), random.gauss(0, 1), random.gauss(0, 1))).normalized()
	t = a.cross(Vector((0.3, 0.9, 0.2))).normalized()
	t.rotate(__import__("mathutils").Quaternion(a, random.uniform(0, math.tau)))
	length = random.uniform(0.6, 1.1) * r
	steps = 4
	# Most near the surface, some through the middle, so it is a tangle and not a cage.
	depth = random.uniform(0.82, 1.0) if random.random() < 0.7 else random.uniform(0.35, 0.8)
	ring = []
	for i in range(steps + 1):
		u = (i / steps - 0.5) * length
		bend = a * math.sin(i / steps * math.pi) * r * random.uniform(-0.08, 0.12)
		p = (a * r * depth + t * u + bend)
		p = p.normalized() * min(p.length, r)
		ring.append(p)
	# Each twig a thin square tube.
	w = 0.0016
	for i in range(steps):
		p, q = ring[i], ring[i + 1]
		along = (q - p).normalized()
		side = along.cross(a).normalized() * w
		up = along.cross(side).normalized() * w
		quad = [bm.verts.new(g(p + side)), bm.verts.new(g(p + up)), bm.verts.new(g(p - side)), bm.verts.new(g(p - up))]
		quad2 = [bm.verts.new(g(q + side)), bm.verts.new(g(q + up)), bm.verts.new(g(q - side)), bm.verts.new(g(q - up))]
		for j in range(4):
			bm.faces.new((quad[j], quad[(j + 1) % 4], quad2[(j + 1) % 4], quad2[j]))
finish(bm, "Tumble", ["twig"], lambda c, d: 0, smooth=False)

for ob in bpy.data.objects:
	lo = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
	print(ob.name, "bounds", tuple(round(min(v[i] for v in lo), 4) for i in range(3)),
			tuple(round(max(v[i] for v in lo), 4) for i in range(3)), len(ob.data.polygons), "faces")
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/toys.glb"), export_format="GLB")
print("wrote assets/models/toys.glb")
