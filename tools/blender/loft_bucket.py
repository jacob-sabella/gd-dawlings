# Builds a galvanised bucket and writes assets/models/loft_bucket.glb.
#
#     blender --background --python tools/blender/loft_bucket.py
#
# For the loft in a thunderstorm (LoftVenue, arrangement 2): the old roof leaks, and someone has
# put a bucket under the drip. A pressed-steel pail 0.3 m across the rim, 0.28 tall, a rolled
# rim, two stiffening ribs round its side, ears riveted on and a wire bail with a wooden grip,
# laid down on the floor side. Water a third of the way up inside, its surface a disc. Origin
# on the floor under its middle.
#
# Materials, swapped by name: "zinc", "water", "grip".

import math
import os

import bpy
import bmesh
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
ORDER = ["zinc", "water", "grip"]
SEG = 28
bm = bmesh.new()


def lathe(profile, mat, segments=SEG):
    rings = []
    for r, z in profile:
        if r == 0.0:
            rings.append([bm.verts.new((0, 0, z))])
            continue
        rings.append([bm.verts.new((r * math.cos(a), r * math.sin(a), z))
                      for a in (math.tau * i / segments for i in range(segments))])
    for lower, upper in zip(rings, rings[1:]):
        for i in range(segments):
            j = (i + 1) % segments
            if len(lower) == 1:
                f = bm.faces.new((lower[0], upper[j], upper[i]))
            elif len(upper) == 1:
                f = bm.faces.new((lower[i], lower[j], upper[0]))
            else:
                f = bm.faces.new((lower[i], lower[j], upper[j], upper[i]))
            f.material_index = ORDER.index(mat)


def tube(points, radius, mat, sides=6):
    rings = []
    for i, p in enumerate(points):
        a = points[max(i - 1, 0)]
        b = points[min(i + 1, len(points) - 1)]
        t = (b - a).normalized()
        n = t.cross(Vector((0, 0, 1)))
        if n.length < 1e-4:
            n = t.cross(Vector((1, 0, 0)))
        n.normalize()
        m = t.cross(n)
        rings.append([bm.verts.new(p + (n * math.cos(k * math.tau / sides) + m * math.sin(k * math.tau / sides)) * radius)
                      for k in range(sides)])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(sides):
            f = bm.faces.new((r0[k], r0[(k + 1) % sides], r1[(k + 1) % sides], r1[k]))
            f.material_index = ORDER.index(mat)


R0, R1, H = 0.11, 0.15, 0.28
# Outside: a foot ring, the tapered side with two ribs, the rolled rim; then down the inside.
side = [(0.0, 0.004), (R0 - 0.01, 0.004), (R0 - 0.004, 0.0), (R0, 0.008)]
for z in (0.09, 0.18):
    r = R0 + (R1 - R0) * z / H
    side += [(r, z - 0.008), (r + 0.004, z), (r, z + 0.008)]
side += [(R1, H - 0.01), (R1 + 0.006, H - 0.006), (R1 + 0.007, H), (R1 + 0.002, H + 0.004), (R1 - 0.003, H),
         (R1 - 0.004, H - 0.01), (R0 - 0.004, 0.012), (0.0, 0.012)]
lathe(side, "zinc")
WATER = 0.1
rw = R0 - 0.004 + (R1 - R0) * WATER / H
lathe([(rw, WATER), (0.0, WATER)], "water")
# The ears, and the bail lying down over the rim on one side.
for s in (-1, 1):
    ear = bmesh.ops.create_cube(bm, size=1.0)
    for v in ear["verts"]:
        v.co = Vector((v.co.x * 0.008, v.co.y * 0.03, v.co.z * 0.035)) + Vector((s * (R1 + 0.002), 0, H - 0.03))
    for f in {f for v in ear["verts"] for f in v.link_faces}:
        f.material_index = ORDER.index("zinc")
pts = []
for k in range(17):
    a = math.pi * k / 16
    # Laid down: the arc tipped over toward -Y and resting on the rim.
    x = -math.cos(a) * (R1 + 0.012)
    lift = math.sin(a)
    pts.append(Vector((x, -lift * 0.16, H - 0.03 + lift * 0.05)))
tube(pts, 0.003, "zinc")
grip = [Vector((x, -0.165, H + 0.018)) for x in (-0.045, -0.02, 0.0, 0.02, 0.045)]
tube(grip, 0.011, "grip", 10)

me = bpy.data.meshes.new("bucket")
bm.normal_update()
bm.to_mesh(me)
bm.free()
for name in ORDER:
    me.materials.append(bpy.data.materials.new(name))
for p in me.polygons:
    p.use_smooth = True
ob = bpy.data.objects.new("bucket", me)
bpy.context.collection.objects.link(ob)
print("bucket", len(me.polygons), "faces")
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/loft_bucket.glb"), export_format="GLB")
print("wrote loft_bucket.glb")
