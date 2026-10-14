# Builds a jug of wildflowers and writes assets/models/cabin_wildflowers.glb.
#
#     blender --background --python tools/blender/cabin_wildflowers.py
#
# For the cold stove on a summer evening (CabinVenue, arrangement 1): what is picked from the
# clearing and stood on the stove top when there is no fire to light. A stoneware jug (0.2 m
# tall, a round belly, a pinched lip and a handle), and out of it a loose armful: ox-eye daisies
# (a yellow eye in a ring of white petals), cornflowers (blue, ragged), yellow tansy buttons in
# flat clusters, and a few grass heads. Origin on the bottom of the jug.
#
# Materials, swapped by name: "jug", "glaze" (its dipped top), "stem", "white", "blue",
# "yellow".

import math
import os
import random

import bpy
import bmesh
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
ORDER = ["jug", "glaze", "stem", "white", "blue", "yellow"]
SEG = 18
bm = bmesh.new()
rnd = random.Random(17)


def lathe(profile, mat_for, segments=SEG):
    rings = []
    for r, z in profile:
        if r == 0.0:
            rings.append([bm.verts.new((0, 0, z))])
            continue
        rings.append([bm.verts.new((r * math.cos(a), r * math.sin(a), z))
                      for a in (math.tau * i / segments for i in range(segments))])
    for n, (lower, upper) in enumerate(zip(rings, rings[1:])):
        for i in range(segments):
            j = (i + 1) % segments
            if len(lower) == 1:
                f = bm.faces.new((lower[0], upper[j], upper[i]))
            elif len(upper) == 1:
                f = bm.faces.new((lower[i], lower[j], upper[0]))
            else:
                f = bm.faces.new((lower[i], lower[j], upper[j], upper[i]))
            f.material_index = ORDER.index(mat_for(n))


def tube(points, radius, mat, sides=4):
    rings = []
    for i, p in enumerate(points):
        a = points[max(i - 1, 0)]
        b = points[min(i + 1, len(points) - 1)]
        t = (b - a).normalized()
        n = t.cross(Vector((0, 0, 1)) if abs(t.z) < 0.95 else Vector((1, 0, 0))).normalized()
        m = t.cross(n)
        rings.append([bm.verts.new(p + (n * math.cos(k * math.tau / sides) + m * math.sin(k * math.tau / sides)) * radius)
                      for k in range(sides)])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(sides):
            f = bm.faces.new((r0[k], r0[(k + 1) % sides], r1[(k + 1) % sides], r1[k]))
            f.material_index = ORDER.index(mat)


def blob(centre, size, mat, flat=1.0, subdiv=1):
    ret = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    for v in ret["verts"]:
        v.co = centre + Vector((v.co.x * size, v.co.y * size, v.co.z * size * flat))
    for f in {f for v in ret["verts"] for f in v.link_faces}:
        f.material_index = ORDER.index(mat)


# The jug: belly, shoulder, neck, flared lip; the top third dipped in a dark glaze. The inside
# drops a little way down, as far as anyone could see into it.
profile = [(0.0, 0.0), (0.05, 0.0), (0.058, 0.01), (0.07, 0.05), (0.071, 0.08), (0.062, 0.12),
           (0.045, 0.15), (0.04, 0.17), (0.046, 0.195), (0.048, 0.2), (0.043, 0.2), (0.036, 0.17),
           (0.036, 0.15), (0.0, 0.15)]
lathe(profile, lambda n: "glaze" if 5 <= n <= 11 else "jug")
# The handle on the back, a strap from the neck to the belly.
pts = [Vector((-0.04, 0, 0.18)), Vector((-0.075, 0, 0.175)), Vector((-0.095, 0, 0.14)),
       Vector((-0.088, 0, 0.1)), Vector((-0.068, 0, 0.075))]
tube(pts, 0.008, "glaze", 6)

NECK = 0.19


def stem_to(head, bend):
    """A stem from inside the neck up to `head`, bowed a little outward."""
    base = Vector((rnd.uniform(-0.012, 0.012), rnd.uniform(-0.012, 0.012), NECK - 0.04))
    mid = base.lerp(head, 0.5) + Vector((head.x, head.y, 0)).normalized() * bend
    tube([base, base.lerp(mid, 0.5), mid, mid.lerp(head, 0.5), head], 0.0016, "stem")


def daisy(head, facing):
    blob(head, 0.01, "yellow", 0.5, 1)
    up = facing.normalized()
    n = up.cross(Vector((0, 0, 1)) if abs(up.z) < 0.95 else Vector((1, 0, 0))).normalized()
    m = up.cross(n)
    for k in range(12):
        a = math.tau * k / 12
        d = n * math.cos(a) + m * math.sin(a)
        s = d.cross(up).normalized()
        root = head + d * 0.006
        tip = head + d * 0.034 - up * 0.005
        v = [bm.verts.new(root + s * 0.003), bm.verts.new(tip + s * 0.0045), bm.verts.new(tip - s * 0.0045),
             bm.verts.new(root - s * 0.003)]
        f = bm.faces.new(v)
        f.material_index = ORDER.index("white")


for i in range(26):
    a = i * 2.39996 + rnd.uniform(-0.2, 0.2)
    out = rnd.uniform(0.03, 0.17)
    tall = NECK + rnd.uniform(0.07, 0.17) - out * 0.4
    head = Vector((math.cos(a) * out, math.sin(a) * out, tall))
    stem_to(head, rnd.uniform(0.0, 0.03))
    kind = i % 4
    facing = Vector((math.cos(a) * out * 3, math.sin(a) * out * 3, 1.0))
    if kind == 0 or kind == 3:
        daisy(head, facing)
    elif kind == 1:
        # A cornflower: a ragged blue head.
        blob(head, 0.016, "blue", 0.8, 1)
        for k in range(7):
            b = math.tau * k / 7
            blob(head + Vector((math.cos(b) * 0.014, math.sin(b) * 0.014, 0.005)), 0.007, "blue", 1.0, 0)
    else:
        # Tansy: a flat cluster of yellow buttons.
        for k in range(6):
            b = math.tau * k / 6 + rnd.random()
            r = rnd.uniform(0.004, 0.016)
            blob(head + Vector((math.cos(b) * r * 1.3, math.sin(b) * r * 1.3, rnd.uniform(-0.003, 0.003))), 0.0065, "yellow", 0.7, 0)
# Grass heads, long and thin, over the rest.
for i in range(10):
    a = rnd.uniform(0, math.tau)
    out = rnd.uniform(0.08, 0.2)
    head = Vector((math.cos(a) * out, math.sin(a) * out, NECK + rnd.uniform(0.12, 0.2)))
    stem_to(head, 0.04)
    tube([head, head + Vector((math.cos(a) * 0.02, math.sin(a) * 0.02, 0.05))], 0.003, "yellow", 4)

me = bpy.data.meshes.new("wildflowers")
bm.normal_update()
bm.to_mesh(me)
bm.free()
for name in ORDER:
    me.materials.append(bpy.data.materials.new(name))
for p in me.polygons:
    p.use_smooth = me.materials[p.material_index].name in ("jug", "glaze")
ob = bpy.data.objects.new("wildflowers", me)
bpy.context.collection.objects.link(ob)
print("wildflowers", len(me.polygons), "faces")
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/cabin_wildflowers.glb"), export_format="GLB")
print("wrote cabin_wildflowers.glb")
