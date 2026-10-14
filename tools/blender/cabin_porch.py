# Builds the porch's odds and ends and writes assets/models/cabin_porch.glb.
#
#     blender --background --python tools/blender/cabin_porch.py
#
# For the covered porch on a night of northern lights (CabinVenue, arrangement 2), and the grass
# of a summer evening (arrangement 1). Objects, each with its origin on the ground:
#
#   chopping_block  a round of spruce 0.5 m across and 0.45 tall, bark on, its top end grain
#                   checked with cracks, and an axe sunk in it: a forged head and a curved ash
#                   handle sticking up and out.
#   bench           a split-log bench, 1.4 m long (along X): a half log, flat side up, on four
#                   peeled legs pegged through it; 0.45 tall.
#   grass           a tuft of meadow grass for MultiMeshes: a dozen blades from one root,
#                   arching out, 0.35 tall.
#
# Materials, swapped by name: "bark", "end_grain", "steel", "ash" (the axe handle and the
# bench's peeled legs), "grass".

import math
import os
import random

import bpy
import bmesh
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
ORDER = ["bark", "end_grain", "steel", "ash", "grass"]
MATS = [bpy.data.materials.new(n) for n in ORDER]


def slot(n):
    return ORDER.index(n)


def tube(bm, points, radius, mat, sides=8, cap=True):
    rings = []
    for i, p in enumerate(points):
        a = points[max(i - 1, 0)]
        b = points[min(i + 1, len(points) - 1)]
        t = (b - a).normalized()
        n = t.cross(Vector((0, 0, 1)) if abs(t.z) < 0.95 else Vector((1, 0, 0))).normalized()
        m = t.cross(n)
        r = radius(i) if callable(radius) else radius
        rings.append([bm.verts.new(p + (n * math.cos(k * math.tau / sides) + m * math.sin(k * math.tau / sides)) * r)
                      for k in range(sides)])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(sides):
            f = bm.faces.new((r0[k], r0[(k + 1) % sides], r1[(k + 1) % sides], r1[k]))
            f.material_index = slot(mat)
    if cap:
        for ring, rev in ((rings[0], True), (rings[-1], False)):
            f = bm.faces.new(list(reversed(ring)) if rev else ring)
            f.material_index = slot(mat)


def obj(name, bm, x, smooth=()):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for m in MATS:
        me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = me.materials[p.material_index].name in smooth
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.location.x = x
    print(name, len(me.polygons), "faces")


rnd = random.Random(4)

# --- the chopping block and the axe.
bm = bmesh.new()
R, H = 0.25, 0.45
SIDES = 16
ring_lo = [bm.verts.new((math.cos(a) * R * rnd.uniform(0.96, 1.04), math.sin(a) * R * rnd.uniform(0.96, 1.04), 0.0))
           for a in (math.tau * k / SIDES for k in range(SIDES))]
ring_hi = [bm.verts.new((v.co.x * 0.97, v.co.y * 0.97, H + rnd.uniform(-0.01, 0.01))) for v in ring_lo]
for k in range(SIDES):
    f = bm.faces.new((ring_lo[k], ring_lo[(k + 1) % SIDES], ring_hi[(k + 1) % SIDES], ring_hi[k]))
    f.material_index = slot("bark")
# The top: end grain, in a fan from the middle so the checks can be cut in as dark slots.
mid = bm.verts.new((0, 0, H))
for k in range(SIDES):
    f = bm.faces.new((mid, ring_hi[k], ring_hi[(k + 1) % SIDES]))
    f.material_index = slot("end_grain")
f = bm.faces.new(list(reversed(ring_lo)))
f.material_index = slot("bark")
# The axe: its bit sunk in the top, the head standing up out of the wood, and the handle out
# through the eye toward +X, rising, with the swell of an ash handle at its end.
head_at = Vector((-0.06, 0.02, H + 0.03))
hx = bmesh.ops.create_cube(bm, size=1.0)
for v in hx["verts"]:
    # A wedge: thick at the poll (up), sharp at the bit (down, in the wood); a little longer at
    # the bit than at the eye, as a felling axe's cheek flares.
    w = 0.014 if v.co.z > 0 else 0.002
    flare = 0.05 if v.co.z > 0 else 0.075
    v.co = head_at + Vector((v.co.x * flare * 2.0, v.co.y * w * 2.0, v.co.z * 0.16))
for fc in {fc for v in hx["verts"] for fc in v.link_faces}:
    fc.material_index = slot("steel")
eye = head_at + Vector((0.0, 0.0, 0.05))
handle = [eye + Vector((-0.03, 0, -0.01)), eye + Vector((0.12, 0, 0.05)), eye + Vector((0.26, 0, 0.12)),
          eye + Vector((0.4, 0, 0.17)), eye + Vector((0.52, 0, 0.19)), eye + Vector((0.58, 0, 0.18))]
tube(bm, handle, lambda i: 0.017 if i in (0, 5) else (0.019 if i == 4 else 0.013), "ash", 8)
obj("chopping_block", bm, 0.0, ("bark", "ash"))

# --- the bench: a half log on four legs.
bm = bmesh.new()
L, LR, TOP = 1.4, 0.15, 0.45
n = 10
verts = []
for end in (-1, 1):
    row = []
    for k in range(n + 1):
        a = math.pi * k / n
        row.append(bm.verts.new((end * L * 0.5, math.cos(a) * LR, TOP - math.sin(a) * LR * 0.8)))
    verts.append(row)
for k in range(n):
    f = bm.faces.new((verts[0][k + 1], verts[0][k], verts[1][k], verts[1][k + 1]))
    f.material_index = slot("bark")
# The flat, split face on top.
f = bm.faces.new((verts[0][0], verts[0][n], verts[1][n], verts[1][0]))
f.material_index = slot("end_grain")
for row, rev in ((verts[0], False), (verts[1], True)):
    f = bm.faces.new(list(reversed(row)) if rev else row)
    f.material_index = slot("end_grain")
for sx in (-1, 1):
    for sy in (-1, 1):
        top = Vector((sx * (L * 0.5 - 0.18), sy * 0.06, TOP - 0.06))
        foot = Vector((sx * (L * 0.5 - 0.1), sy * 0.16, 0.0))
        tube(bm, [foot, top], 0.025, "ash", 7)
obj("bench", bm, 1.2, ("bark", "ash"))

# --- a tuft of grass.
bm = bmesh.new()
for k in range(12):
    a = rnd.uniform(0, math.tau)
    out = Vector((math.cos(a), math.sin(a), 0))
    side = out.cross(Vector((0, 0, 1)))
    tall = rnd.uniform(0.18, 0.35)
    reach = rnd.uniform(0.04, 0.14)
    pts = [out * 0.01 + out * reach * (s / 4) ** 1.5 + Vector((0, 0, tall * math.sin(s / 4 * math.pi * 0.45) / 0.987))
           for s in range(5)]
    left = [bm.verts.new(p + side * 0.006 * (1 - s / 4.4)) for s, p in enumerate(pts)]
    right = [bm.verts.new(p - side * 0.006 * (1 - s / 4.4)) for s, p in enumerate(pts)]
    for s in range(4):
        f = bm.faces.new((left[s], right[s], right[s + 1], left[s + 1]))
        f.material_index = slot("grass")
obj("grass", bm, 2.4, ("grass",))

bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/cabin_porch.glb"), export_format="GLB")
print("wrote cabin_porch.glb")
