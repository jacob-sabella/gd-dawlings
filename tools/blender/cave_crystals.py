# Builds the crystal cave's crystals and writes assets/models/cave_crystals.glb.
#
#     blender --background --python tools/blender/cave_crystals.py
#
# Quartz grows as six-sided prisms capped by six-sided points, each face a little wider or
# narrower than its neighbours; a pocket of them grows out of a lump of the rock they formed in.
# One file, several objects, each placed by CaveVenue by name (as one MultiMesh a kind, the
# colour -- amethyst or ice-blue quartz -- given per instance):
#   Cluster0   a druse: a crowd of short points packed over a squat lump, 0.5 m across
#   Cluster1   a fan of seven long clear prisms leaning out of a cleft, 0.7 m tall
#   Cluster2   three big points and their brood of small ones, 0.8 m tall
#   Cluster3   a spray of thin needles, 0.6 m long
#   Shard      one great crystal alone, 1.4 m from its buried root to its point: the giants
# Each grows up Blender +Z (Godot +Y) from an origin on the rock it grows out of; the lump runs
# a little below it so the cluster can be set into an uneven wall without a gap.
# Materials "crystal" and "matrix" (the host rock). Every crystal face carries a UV whose V runs
# from 0 at the crystal's root to 1 at its point (Godot's UV.y is 1 - V), so the cave's shader can
# make each glow from its heart outward.

import math
import os
import random

import bpy
import bmesh
from mathutils import Vector, Matrix, noise

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
random.seed(5)
mats = {n: bpy.data.materials.new(n) for n in ["crystal", "matrix"]}


def finish(bm, name, x_offset):
    mesh = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mats["crystal"])
    mesh.materials.append(mats["matrix"])
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    # Crystal faces flat -- their facets are what catches light -- and the matrix smooth.
    for p in mesh.polygons:
        p.use_smooth = p.material_index == 1
    obj.location.x = x_offset
    bb = [Vector(c) for c in obj.bound_box]
    print("%s: %d faces, z %.2f..%.2f" % (name, len(mesh.polygons), min(p.z for p in bb), max(p.z for p in bb)))


def crystal(bm, uv, base, direction, length, radius, point=1.7):
    """One prism from `base` along `direction`, `length` to the shoulder of its point, then the
    point itself, `point` radii tall. Its root is closed so a crystal standing proud of a lump
    is still solid."""
    d = direction.normalized()
    side = d.cross(Vector((0.0, 0.0, 1.0)))
    if side.length < 0.1:
        side = d.cross(Vector((1.0, 0.0, 0.0)))
    side.normalize()
    up = d.cross(side).normalized()
    spin = random.uniform(0, math.pi / 3)
    ring = []
    for s in range(6):
        a = spin + math.pi / 3 * s
        rr = radius * random.uniform(0.82, 1.12)
        ring.append((side * math.cos(a) + up * math.sin(a)) * rr)
    total = length + radius * point
    root = [bm.verts.new(base + o) for o in ring]
    # The shoulder a little ragged: real terminations are rarely all at one height.
    shoulder = [bm.verts.new(base + o + d * (length + random.uniform(-0.04, 0.04) * radius)) for o in ring]
    tip = bm.verts.new(base + d * total + side * random.uniform(-0.15, 0.15) * radius)
    faces = []
    for s in range(6):
        faces.append(bm.faces.new((root[s], root[(s + 1) % 6], shoulder[(s + 1) % 6], shoulder[s])))
        faces.append(bm.faces.new((shoulder[s], shoulder[(s + 1) % 6], tip)))
    faces.append(bm.faces.new(list(reversed(root))))
    for f in faces:
        f.material_index = 0
        for loop in f.loops:
            along = (loop.vert.co - base).dot(d) / total
            loop[uv].uv = (0.0, max(0.0, min(1.0, along)))


def lump(bm, uv, radius, height, seed):
    """The host rock: a squashed, knobbly half ball, its foot sunk below the origin."""
    made = bmesh.ops.create_icosphere(bm, subdivisions=3, radius=1.0)
    for v in made["verts"]:
        d = v.co.normalized()
        bump = 1.0 + noise.fractal(d * 2.2 + Vector((seed, 0, 0)), 0.6, 2.0, 3) * 0.25
        v.co = Vector((d.x * radius * bump, d.y * radius * bump, d.z * height * bump))
        if v.co.z < -0.06:
            v.co.z = -0.06 + (v.co.z + 0.06) * 0.2
    for f in {f for v in made["verts"] for f in v.link_faces}:
        f.material_index = 1
        for loop in f.loops:
            loop[uv].uv = (0.0, 0.0)


def on_lump(radius, height):
    """A point on the lump's upper face and the way out of it there."""
    a = random.uniform(0, 2 * math.pi)
    r = math.sqrt(random.random()) * 0.85
    p = Vector((math.cos(a) * r * radius, math.sin(a) * r * radius, height * math.sqrt(max(0.0, 1.0 - r * r)) * 0.8))
    out = Vector((math.cos(a) * r * 0.9, math.sin(a) * r * 0.9, 1.0)).normalized()
    return p, out


def new_bm():
    bm = bmesh.new()
    return bm, bm.loops.layers.uv.new("UVMap")


# Cluster0, the druse: thirty short fat points shoulder to shoulder.
bm, uv = new_bm()
lump(bm, uv, 0.26, 0.12, 1.0)
for i in range(30):
    p, out = on_lump(0.26, 0.12)
    out = (out + Vector((random.uniform(-0.25, 0.25), random.uniform(-0.25, 0.25), 0))).normalized()
    crystal(bm, uv, p - out * 0.02, out, random.uniform(0.03, 0.1), random.uniform(0.018, 0.032), 1.6)
finish(bm, "Cluster0", 0.0)

# Cluster1, the fan: seven long prisms out of a narrow cleft, splayed in one plane-ish.
bm, uv = new_bm()
lump(bm, uv, 0.2, 0.1, 2.0)
for i in range(7):
    a = -0.65 + 1.3 * i / 6 + random.uniform(-0.1, 0.1)
    out = Vector((math.sin(a), random.uniform(-0.25, 0.25), math.cos(a))).normalized()
    crystal(bm, uv, Vector((random.uniform(-0.05, 0.05), random.uniform(-0.04, 0.04), 0.02)), out,
            random.uniform(0.3, 0.55) * (1.0 - abs(a) * 0.4), random.uniform(0.035, 0.05), 1.8)
finish(bm, "Cluster1", 1.5)

# Cluster2: three big points and a brood of small ones round their feet.
bm, uv = new_bm()
lump(bm, uv, 0.3, 0.14, 3.0)
for i in range(3):
    a = 2 * math.pi * i / 3 + random.uniform(-0.3, 0.3)
    out = Vector((math.cos(a) * 0.35, math.sin(a) * 0.35, 1.0)).normalized()
    crystal(bm, uv, Vector((math.cos(a) * 0.06, math.sin(a) * 0.06, 0.04)), out, random.uniform(0.45, 0.6),
            random.uniform(0.07, 0.09), 1.7)
for i in range(14):
    p, out = on_lump(0.3, 0.14)
    crystal(bm, uv, p - out * 0.02, out, random.uniform(0.05, 0.16), random.uniform(0.02, 0.035), 1.6)
finish(bm, "Cluster2", 3.0)

# Cluster3: a spray of needles from one root, thin and long, every which way upward.
bm, uv = new_bm()
lump(bm, uv, 0.12, 0.07, 4.0)
for i in range(16):
    a = random.uniform(0, 2 * math.pi)
    lean = random.uniform(0.15, 1.0)
    out = Vector((math.cos(a) * lean, math.sin(a) * lean, 1.0)).normalized()
    crystal(bm, uv, Vector((0, 0, 0.03)), out, random.uniform(0.25, 0.55), random.uniform(0.008, 0.014), 2.2)
finish(bm, "Cluster3", 4.5)

# The Shard: one giant, its root buried 0.2 m deep, a hand off true.
bm, uv = new_bm()
crystal(bm, uv, Vector((0, 0, -0.2)), Vector((0.08, 0.05, 1.0)), 1.38, 0.13, 1.75)
finish(bm, "Shard", 6.0)

bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/cave_crystals.glb"), export_format="GLB")
print("wrote cave_crystals.glb")
