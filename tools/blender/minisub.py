# Builds a small research submersible and writes assets/models/minisub.glb.
#
#     blender --background --python tools/blender/minisub.py
#
# The sub docked at the underwater dome, beside the vocal booth: a two-seat yellow hull, round
# in section, with a big acrylic bubble for a bow, a sail on top with its hatch, two ducted
# thrusters aft and one each side, a pair of skids under it, lamps either side of the bubble, and
# a docking collar on its flank that the dome's collar meets. Materials "hull", "glass", "dark",
# "steel" and "lamp". Blender X is along the sub, bow at +X (Godot +X); the collar faces
# Blender -Y (Godot +Z); the origin is the middle of the hull.

import math
import os

import bpy
import bmesh
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
mats = {n: bpy.data.materials.new(n) for n in ["hull", "glass", "dark", "steel", "lamp"]}
order = list(mats)

LENGTH = 3.4
RADIUS = 0.85
SIDES = 36

bm = bmesh.new()


def tag(faces, name):
    for f in faces:
        f.material_index = order.index(name)


def lathe(profile, name, place=lambda x, y, z: (x, y, z), sides=SIDES):
    """Spins (x, r) pairs round the X axis -- a hull, a duct, a collar -- then `place` moves
    each point where that part goes."""
    rings = []
    for x, r in profile:
        ring = []
        for s in range(sides):
            a = 2 * math.pi * s / sides
            ring.append(bm.verts.new(place(x, r * math.cos(a), r * math.sin(a))))
        rings.append(ring)
    faces = []
    for i in range(len(rings) - 1):
        for s in range(sides):
            faces.append(bm.faces.new((rings[i][s], rings[i][(s + 1) % sides],
                                       rings[i + 1][(s + 1) % sides], rings[i + 1][s])))
    tag(faces, name)


def box(size, at, name):
    geom = bmesh.ops.create_cube(bm, size=1.0)
    for v in geom["verts"]:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])) + Vector(at)
    tag({f for v in geom["verts"] for f in v.link_faces}, name)


# The hull: a capsule, its stern tapering to the thrusters, open at the bow for the bubble.
# The stern a quarter ellipse down to the thruster mount, in ten steps.
stern = [(-LENGTH / 2 + 0.5 - 0.75 * math.cos(math.radians(a)), 0.18 + (RADIUS - 0.18) * math.sin(math.radians(a)))
         for a in range(0, 91, 10)]
lathe(stern + [(LENGTH / 2 - 0.55, RADIUS), (LENGTH / 2 - 0.4, RADIUS * 0.98)], "hull")
# A dark band where the bubble seats, and the stern cap.
lathe([(LENGTH / 2 - 0.4, RADIUS * 0.98), (LENGTH / 2 - 0.3, RADIUS * 0.98)], "dark")
lathe([(-LENGTH / 2 - 0.25, 0.18), (-LENGTH / 2 - 0.26, 0.0)], "dark")
# The bubble: a hemisphere, clear.
lathe([(LENGTH / 2 - 0.3 + RADIUS * 0.98 * math.sin(math.radians(i * 10.0)),
        RADIUS * 0.98 * math.cos(math.radians(i * 10.0)) + 0.001) for i in range(10)], "glass")

# The sail on top, its hatch ring lying flat on it, and a mast light.
# (a lathed teardrop, narrowed side to side, its lower half sunk inside the hull)
lathe([(-0.5, 0.0)] + [(-0.5 + 0.9 * i / 8, 0.3 * math.sin(math.pi * min(1.0, 0.15 + i / 8 * 1.1)) + 0.02)
                       for i in range(1, 8)] + [(0.4, 0.0)], "hull",
      lambda x, y, z: (-0.1 + x, y * 0.85, RADIUS - 0.05 + z * 1.1), 20)
lathe([(0, 0.24), (0.06, 0.24), (0.06, 0.0)], "steel",
      lambda x, y, z: (-0.1 + y, z, RADIUS + 0.32 + x), 16)
box((0.06, 0.06, 0.12), (-0.45, 0, RADIUS + 0.38), "lamp")

# The thrusters: a ducted pair aft, each on a fin.
for side in [-0.75, 0.75]:
    lathe([(0, 0.24), (0.32, 0.26), (0.32, 0.21), (0, 0.19), (0, 0.24)], "dark",
          lambda x, y, z, side=side: (-LENGTH / 2 - 0.1 + x, y + side, z - 0.15), 16)
    box((0.3, 0.35, 0.05), (-LENGTH / 2 + 0.25, side * 0.75, -0.15), "hull")
# The skids: two bars on struts.
for y in [-0.5, 0.5]:
    box((LENGTH * 0.85, 0.08, 0.08), (0.0, y, -RADIUS - 0.32), "dark")
    for x in [-0.9, 0.9]:
        box((0.08, 0.06, 0.32), (x, y * 0.85, -RADIUS - 0.14), "dark")
# The lamps, either side of the bubble: a steel can with a lit face.
for y in [-0.6, 0.6]:
    lathe([(0, 0.11), (0.12, 0.11), (0.12, 0.0)], "steel",
          lambda x, yy, z, y=y: (LENGTH / 2 - 0.55 + x, yy + y, z + 0.42), 12)
    box((0.01, 0.17, 0.17), (LENGTH / 2 - 0.42, y, 0.42), "lamp")

# The docking collar on the -Y flank: a short steel tube and a flange ring, square to the hull.
lathe([(0, 0.62), (0.3, 0.62), (0.3, 0.72), (0.36, 0.72), (0.36, 0.55)], "steel",
      lambda x, y, z: (y, -(RADIUS - 0.12) - x, z), 24)

mesh = bpy.data.meshes.new("minisub")
bm.normal_update()
bm.to_mesh(mesh)
bm.free()
for m in mats.values():
    mesh.materials.append(m)
for p in mesh.polygons:
    p.use_smooth = True
obj = bpy.data.objects.new("Minisub", mesh)
bpy.context.scene.collection.objects.link(obj)
bpy.context.view_layer.objects.active = obj
obj.select_set(True)
bpy.ops.object.shade_auto_smooth(angle=math.radians(35))
print("minisub: %d faces" % len(mesh.polygons))

bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/minisub.glb"), export_format="GLB")
print("wrote minisub.glb")
