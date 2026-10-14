# Builds the deep dome's jellyfish and writes assets/models/dome_jelly.glb.
#
#     blender --background --python tools/blender/dome_jelly.py
#
# One jellyfish, a bell 0.36 m across: the bell (a thin lathed dome, scalloped at its margin,
# its rim a ring of lappets), four frilled oral arms hanging from its middle, and a fringe of
# sixteen fine tentacles from the margin, a metre and a bit long. DomeVenue scatters it in one
# MultiMesh and dome_jelly.gdshader pulses the bell, trails the tentacles and lights it.
#
# Blender Z up (Godot +Y), the origin at the middle of the bell's margin. Every vertex carries,
# in its UV's v, how far down the animal it is (0 at the bell's crown, 1 at the tentacles' ends)
# and, in u, 0 for the bell and 1 for what hangs from it; the shader reads both.
#
# Object "Jelly", materials "bell" and "trail".

import math
import os
import random

import bpy
import bmesh
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
random.seed(8)
mats = {n: bpy.data.materials.new(n) for n in ["bell", "trail"]}

R = 0.18          # the bell's radius at its margin
DOME = 0.16       # its height over the margin
TENTACLE = 1.2
SIDES = 32
TOTAL = DOME + TENTACLE

bm = bmesh.new()
uv = bm.loops.layers.uv.new("UVMap")


def depth(z):
    return (DOME - z) / TOTAL


def face(verts, mat, hang):
    f = bm.faces.new(verts)
    f.material_index = mat
    for loop in f.loops:
        loop[uv].uv = (hang, depth(loop.vert.co.z))
    return f


# The bell: a lathed dome, outer and inner skins, its margin scalloped into lappets.
profile = [(math.sin(a) * R, math.cos(a) * DOME) for a in [i / 10 * math.pi / 2 for i in range(11)]]
outer, inner = [], []
for k, (r, z) in enumerate(profile):
    ro, ri = [], []
    for s in range(SIDES):
        a = 2 * math.pi * s / SIDES
        scallop = 1.0 + (0.06 * abs(math.sin(a * 8)) if k == len(profile) - 1 else 0.0)
        lip = -0.02 * abs(math.sin(a * 8)) if k == len(profile) - 1 else 0.0
        d = Vector((math.cos(a), math.sin(a), 0))
        ro.append(bm.verts.new(d * r * scallop + Vector((0, 0, z + lip))))
        ri.append(bm.verts.new(d * r * scallop * 0.9 + Vector((0, 0, z * 0.8 + lip))))
    outer.append(ro)
    inner.append(ri)
for k in range(len(profile) - 1):
    for s in range(SIDES):
        t = (s + 1) % SIDES
        face((outer[k][s], outer[k + 1][s], outer[k + 1][t], outer[k][t]), 0, 0.0)
        face((inner[k][t], inner[k + 1][t], inner[k + 1][s], inner[k][s]), 0, 0.0)
for s in range(SIDES):
    t = (s + 1) % SIDES
    face((outer[-1][s], inner[-1][s], inner[-1][t], outer[-1][t]), 0, 0.0)


def ribbon(points, width, twist, mat=1):
    """A flat ribbon down a list of points, `width` wide, its flat turning by `twist` a metre."""
    left, right = [], []
    for i, p in enumerate(points):
        a = twist * (DOME - p.z)
        across = Vector((math.cos(a), math.sin(a), 0)) * width[i] * 0.5
        left.append(bm.verts.new(p - across))
        right.append(bm.verts.new(p + across))
    for i in range(len(points) - 1):
        face((left[i], right[i], right[i + 1], left[i + 1]), mat, 1.0)


# The oral arms: four frilled ribbons from the middle of the bell's underside, wavering down.
for k in range(4):
    a = k * math.pi / 2 + 0.4
    pts, widths = [], []
    n = 14
    for i in range(n + 1):
        t = i / n
        r = 0.03 + 0.04 * math.sin(t * math.pi)
        wobble = 0.025 * math.sin(t * 9.0 + k)
        pts.append(Vector((math.cos(a) * r + wobble, math.sin(a) * r - wobble, DOME * 0.7 - 0.62 * t)))
        widths.append(0.07 * (1.0 - t * 0.7) * (1.0 + 0.4 * math.sin(t * 25.0 + k)))
    ribbon(pts, widths, 4.0 + k)

# The tentacles: sixteen fine threads from the margin, trailing.
for k in range(16):
    a = 2 * math.pi * (k + 0.5) / 16
    length = TENTACLE * random.uniform(0.75, 1.0)
    pts, widths = [], []
    n = 16
    for i in range(n + 1):
        t = i / n
        r = R * (0.95 - 0.25 * t)
        pts.append(Vector((math.cos(a) * r, math.sin(a) * r, -0.01 - length * t)))
        widths.append(0.008 * (1.0 - t * 0.8))
    ribbon(pts, widths, 2.0)

mesh = bpy.data.meshes.new("Jelly")
bm.normal_update()
bm.to_mesh(mesh)
bm.free()
for m in mats.values():
    mesh.materials.append(m)
for p in mesh.polygons:
    p.use_smooth = True
obj = bpy.data.objects.new("Jelly", mesh)
bpy.context.scene.collection.objects.link(obj)
print("Jelly: %d faces" % len(mesh.polygons))
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/dome_jelly.glb"), export_format="GLB")
print("wrote dome_jelly.glb")
