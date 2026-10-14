# Builds the station's solar truss and writes assets/models/station_array.glb.
#
#     blender --background --python tools/blender/station_array.py
#
# The power truss that runs out from the ring past the module: a square lattice girder 1.2 m
# deep and forty metres long (four chords, battens and diagonals), a rotary joint part way out,
# and beyond it two solar array wings -- each a pair of long blankets on a central mast, the
# cells in a grid of bays -- with a radiator panel between them, its white fins edge on.
#
# Blender X along the truss, away from the station (Godot +X); the wings' faces toward Blender
# -Y (Godot +Z, toward the module); the origin is the truss's root, where it meets the ring.
#
# Materials "truss" (white-grey struts), "cell" (the blankets, UV'd 0..1 across each for the
# station's cell shader), "frame" (masts, boxes, the joint), "radiator", "red" (a beacon on the far end).

import math
import os

import bpy
import bmesh
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
NAMES = ["truss", "cell", "frame", "radiator", "red"]
mats = {n: bpy.data.materials.new(n) for n in NAMES}

LENGTH = 40.0
DEPTH = 1.2
BAY = 1.6

bm = bmesh.new()
uv = bm.loops.layers.uv.new("UVMap")


def tag(faces, name):
    for f in faces:
        f.material_index = NAMES.index(name)


def strut(a, b, r, name="truss", sides=6):
    a, b = Vector(a), Vector(b)
    d = (b - a).normalized()
    side = d.cross(Vector((0, 0, 1)))
    if side.length < 0.1:
        side = d.cross(Vector((0, 1, 0)))
    side.normalize()
    up = d.cross(side)
    ra = [bm.verts.new(a + (side * math.cos(2 * math.pi * k / sides) + up * math.sin(2 * math.pi * k / sides)) * r)
          for k in range(sides)]
    rb = [bm.verts.new(b + (side * math.cos(2 * math.pi * k / sides) + up * math.sin(2 * math.pi * k / sides)) * r)
          for k in range(sides)]
    faces = [bm.faces.new((ra[k], ra[(k + 1) % sides], rb[(k + 1) % sides], rb[k])) for k in range(sides)]
    faces.append(bm.faces.new(list(reversed(ra))))
    faces.append(bm.faces.new(rb))
    tag(faces, name)


def box(size, at, name, uvs=False):
    geom = bmesh.ops.create_cube(bm, size=1.0)
    for v in geom["verts"]:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])) + Vector(at)
    faces = {f for v in geom["verts"] for f in v.link_faces}
    tag(faces, name)
    if uvs:
        # The blanket's own 0..1 across its face, for the cell shader's grid.
        lo = Vector(at) - Vector(size) * 0.5
        for f in faces:
            for loop in f.loops:
                c = loop.vert.co
                loop[uv].uv = ((c.x - lo.x) / size[0], (c.z - lo.z) / size[2])


# The girder: four chords, a batten square every bay, and a diagonal on each face of each bay.
h = DEPTH * 0.5
corners = [Vector((0, -h, -h)), Vector((0, h, -h)), Vector((0, h, h)), Vector((0, -h, h))]
for c in corners:
    strut(c, c + Vector((LENGTH, 0, 0)), 0.045)
x = 0.0
bay = 0
while x < LENGTH - 0.01:
    x1 = min(LENGTH, x + BAY)
    for k in range(4):
        a, b = corners[k], corners[(k + 1) % 4]
        strut(a + Vector((x, 0, 0)), b + Vector((x, 0, 0)), 0.03)
        if bay % 2 == 0:
            strut(a + Vector((x, 0, 0)), b + Vector((x1, 0, 0)), 0.022)
        else:
            strut(b + Vector((x, 0, 0)), a + Vector((x1, 0, 0)), 0.022)
    x = x1
    bay += 1
for k in range(4):
    strut(corners[k] + Vector((LENGTH, 0, 0)), corners[(k + 1) % 4] + Vector((LENGTH, 0, 0)), 0.03)

# Boxes along it: batteries and the rotary joint, a drum round the girder.
for at, size in [(3.0, (1.2, 1.5, 1.5)), (7.5, (0.9, 1.5, 1.5))]:
    box(size, (at, 0, 0), "frame")
joint = 12.0
rings = []
for xx, r in [(joint - 0.6, 1.1), (joint + 0.6, 1.1)]:
    rings.append([bm.verts.new(Vector((xx, math.cos(2 * math.pi * k / 24) * r, math.sin(2 * math.pi * k / 24) * r)))
                  for k in range(24)])
faces = [bm.faces.new((rings[0][k], rings[0][(k + 1) % 24], rings[1][(k + 1) % 24], rings[1][k])) for k in range(24)]
faces.append(bm.faces.new(list(reversed(rings[0]))))
faces.append(bm.faces.new(rings[1]))
tag(faces, "frame")

# Two wings beyond the joint: a mast up and down from the girder, and a blanket each side of it.
for wx in (19.0, 33.0):
    for up in (1, -1):
        strut((wx, 0, up * h), (wx, 0, up * 15.2), 0.07, "frame", 8)
        box((1.0, 0.6, 0.6), (wx, 0, up * 1.0), "frame")
        for across in (-1, 1):
            # Each blanket in its own frame, a hand's breadth off the mast.
            c = (wx + across * 2.45, -0.02, up * 8.2)
            box((4.4, 0.04, 13.6), c, "cell", uvs=True)
            box((4.5, 0.03, 13.7), (c[0], 0.02, c[2]), "frame")
        box((9.4, 0.12, 0.25), (wx, 0, up * 15.25), "frame")
# The radiator between them: eight white fins, edge on to the module, on a short mast.
strut((26.0, 0, -h), (26.0, 0, -6.0), 0.05, "frame", 8)
for k in range(8):
    box((3.2, 0.06, 0.55), (26.0, 0.0, -1.4 - k * 0.6), "radiator")
# A red beacon on the girder's far end.
box((0.18, 0.18, 0.18), (LENGTH + 0.12, 0, h), "red")

mesh = bpy.data.meshes.new("Array")
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bm.normal_update()
bm.to_mesh(mesh)
bm.free()
for m in NAMES:
    mesh.materials.append(mats[m])
obj = bpy.data.objects.new("Array", mesh)
bpy.context.scene.collection.objects.link(obj)
for o in bpy.context.scene.objects:
    o.select_set(o == obj)
bpy.context.view_layer.objects.active = obj
bpy.ops.object.shade_auto_smooth(angle=math.radians(50))
print("Array: %d faces" % len(mesh.polygons))
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/station_array.glb"), export_format="GLB",
                          export_apply=True)
print("wrote station_array.glb")
