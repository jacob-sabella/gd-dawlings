# Builds the jazz club's furniture and writes assets/models/club.glb.
#
#     blender --background --python tools/blender/club.py
#
# One file, several objects, each placed by ClubVenue by name:
#   Table      a bistro table: a round marble top on a cast-iron column and foot, 0.74 m high
#   Chair      a bentwood cafe chair: round seat, four splayed legs, a hoop back and a leg ring
#   Stool      a bar stool: a padded round seat, brass legs and a foot ring, 0.76 m to the seat
#   Banquette  one bench of a booth: a channel-tufted high back and a padded seat on a wood
#              plinth, 1.3 m long, its seat facing Blender -Y (Godot +Z)
#   Bottle0..3 bottles for the back bar: wine, a tall spirit, a squat one, a long neck
# Every origin is on the floor (a bottle's on its base). Materials "marble", "iron", "wood",
# "leather", "brass", "glass_green", "glass_amber", "glass_clear", "label".

import math
import os

import bpy
import bmesh
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
NAMES = ["marble", "iron", "wood", "leather", "brass", "glass_green", "glass_amber", "glass_clear", "label"]
mats = {n: bpy.data.materials.new(n) for n in NAMES}


class Part:
    """One object being built: a bmesh and the materials it uses."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.used = []

    def index(self, mat):
        if mat not in self.used:
            self.used.append(mat)
        return self.used.index(mat)

    def lathe(self, profile, mat, at=(0, 0, 0), sides=24):
        """Spins (r, z) pairs round the vertical axis, capped where r is 0."""
        rings = []
        for r, z in profile:
            ring = []
            for s in range(sides):
                a = 2 * math.pi * s / sides
                ring.append(self.bm.verts.new((at[0] + r * math.cos(a), at[1] + r * math.sin(a), at[2] + z)))
            rings.append(ring)
        k = self.index(mat)
        for i in range(len(rings) - 1):
            for s in range(sides):
                f = self.bm.faces.new((rings[i][s], rings[i][(s + 1) % sides],
                                       rings[i + 1][(s + 1) % sides], rings[i + 1][s]))
                f.material_index = k

    def tube(self, points, radius, mat, sides=8, closed=False):
        """A round rod along `points`."""
        pts = [Vector(p) for p in points]
        n = len(pts)
        rings = []
        for i, p in enumerate(pts):
            if closed:
                d = (pts[(i + 1) % n] - pts[(i - 1) % n]).normalized()
            else:
                d = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
            side = d.cross(Vector((0, 0, 1)))
            if side.length < 0.1:
                side = d.cross(Vector((1, 0, 0)))
            side.normalize()
            up = side.cross(d).normalized()
            ring = []
            for s in range(sides):
                a = 2 * math.pi * s / sides
                ring.append(self.bm.verts.new(p + (side * math.cos(a) + up * math.sin(a)) * radius))
            rings.append(ring)
        k = self.index(mat)
        count = n if closed else n - 1
        for i in range(count):
            a, b = rings[i], rings[(i + 1) % n]
            for s in range(sides):
                f = self.bm.faces.new((a[s], a[(s + 1) % sides], b[(s + 1) % sides], b[s]))
                f.material_index = k

    def box(self, size, at, mat, bevel=0.0):
        geom = bmesh.ops.create_cube(self.bm, size=1.0)
        verts = geom["verts"]
        for v in verts:
            v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])) + Vector(at)
        faces = {f for v in verts for f in v.link_faces}
        k = self.index(mat)
        for f in faces:
            f.material_index = k
        if bevel > 0.0:
            edges = list({e for v in verts for e in v.link_edges})
            bmesh.ops.bevel(self.bm, geom=edges, offset=bevel, segments=3, affect="EDGES", profile=0.5)

    def finish(self, x_offset):
        mesh = bpy.data.meshes.new(self.name)
        self.bm.normal_update()
        self.bm.to_mesh(mesh)
        self.bm.free()
        for m in self.used:
            mesh.materials.append(mats[m])
        for p in mesh.polygons:
            p.use_smooth = True
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        bpy.context.view_layer.objects.active = obj
        for o in bpy.context.scene.objects:
            o.select_set(o == obj)
        bpy.ops.object.shade_auto_smooth(angle=math.radians(40))
        # Laid out in a row in the file so they can be looked at; each is placed in Godot.
        obj.location.x = x_offset
        print("%s: %d faces" % (self.name, len(mesh.polygons)))


# The table.
t = Part("Table")
t.lathe([(0.0, 0.0), (0.24, 0.0), (0.24, 0.02), (0.1, 0.05), (0.045, 0.09), (0.03, 0.2), (0.025, 0.66),
         (0.06, 0.69), (0.08, 0.705), (0.0, 0.705)], "iron")
t.lathe([(0.0, 0.705), (0.33, 0.705), (0.335, 0.72), (0.33, 0.74), (0.0, 0.74)], "marble", sides=40)
t.finish(0.0)

# The chair: a seat, four legs splayed out, a ring between them, and a hoop back in one bend.
c = Part("Chair")
c.lathe([(0.0, 0.44), (0.2, 0.44), (0.215, 0.455), (0.21, 0.475), (0.0, 0.48)], "wood", sides=28)
legs = []
for i in range(4):
    a = math.radians(45 + 90 * i)
    top = Vector((0.15 * math.cos(a), 0.15 * math.sin(a), 0.44))
    foot = Vector((0.23 * math.cos(a), 0.23 * math.sin(a), 0.0))
    legs.append((top, foot))
    c.tube([foot, foot.lerp(top, 0.5), top], 0.014, "wood")
ring = []
for s in range(24):
    a = 2 * math.pi * s / 24
    ring.append((0.19 * math.cos(a), 0.19 * math.sin(a), 0.17))
c.tube(ring, 0.009, "wood", closed=True)
# The back: from the seat's back corners, up and round in a hoop, leaning back a little.
hoop = []
for s in range(19):
    a = math.pi * s / 18
    x = 0.17 * math.cos(a)
    z = 0.48 + 0.18 + 0.2 * math.sin(a)
    hoop.append((x, 0.17 + 0.06 * (z - 0.48), z))
back = [(0.17, 0.16, 0.48), (0.17, 0.17, 0.66)] + hoop[1:-1] + [(-0.17, 0.17, 0.66), (-0.17, 0.16, 0.48)]
c.tube(back, 0.012, "wood")
c.tube([(0.0, 0.18, 0.48), (0.0, 0.19, 0.6), (0.0, 0.2, 0.86)], 0.009, "wood")
c.finish(1.0)

# The stool.
s = Part("Stool")
s.lathe([(0.0, 0.7), (0.17, 0.7), (0.19, 0.72), (0.19, 0.76), (0.17, 0.785), (0.0, 0.79)], "leather", sides=28)
s.lathe([(0.0, 0.68), (0.16, 0.68), (0.16, 0.7), (0.0, 0.7)], "brass", sides=28)
for i in range(4):
    a = math.radians(45 + 90 * i)
    top = (0.12 * math.cos(a), 0.12 * math.sin(a), 0.68)
    foot = (0.21 * math.cos(a), 0.21 * math.sin(a), 0.0)
    s.tube([foot, top], 0.013, "brass")
ring = []
for k in range(24):
    a = 2 * math.pi * k / 24
    ring.append((0.18 * math.cos(a), 0.18 * math.sin(a), 0.28))
s.tube(ring, 0.011, "brass", closed=True)
s.finish(2.0)

# The banquette: a wood plinth, a padded seat, and a high back in vertical channels.
b = Part("Banquette")
LENGTH = 1.3
b.box((LENGTH, 0.5, 0.2), (0, 0.0, 0.1), "wood")
b.box((LENGTH - 0.02, 0.52, 0.14), (0, -0.01, 0.27), "leather", bevel=0.03)
b.box((LENGTH, 0.14, 1.12), (0, 0.27, 0.56), "wood")
channels = 7
w = (LENGTH - 0.04) / channels
for i in range(channels):
    x = -LENGTH / 2 + 0.02 + w * (i + 0.5)
    b.box((w - 0.008, 0.09, 0.62), (x, 0.17, 0.72), "leather", bevel=0.035)
b.box((LENGTH + 0.02, 0.18, 0.05), (0, 0.27, 1.145), "wood", bevel=0.01)
b.finish(3.5)

# The bottles: (profile, glass, label band (z0, z1) or None).
BOTTLES = [
    ([(0.0, 0.0), (0.037, 0.0), (0.038, 0.01), (0.038, 0.2), (0.03, 0.24), (0.014, 0.27), (0.013, 0.31),
      (0.015, 0.315), (0.014, 0.33), (0.0, 0.33)], "glass_green", (0.07, 0.15)),
    ([(0.0, 0.0), (0.04, 0.0), (0.041, 0.01), (0.041, 0.2), (0.036, 0.22), (0.016, 0.25), (0.015, 0.3),
      (0.017, 0.305), (0.016, 0.32), (0.0, 0.32)], "glass_amber", (0.06, 0.14)),
    ([(0.0, 0.0), (0.05, 0.0), (0.052, 0.01), (0.052, 0.13), (0.045, 0.15), (0.02, 0.17), (0.019, 0.21),
      (0.021, 0.215), (0.02, 0.23), (0.0, 0.23)], "glass_clear", (0.04, 0.1)),
    ([(0.0, 0.0), (0.032, 0.0), (0.033, 0.01), (0.033, 0.17), (0.026, 0.2), (0.011, 0.22), (0.01, 0.34),
      (0.012, 0.345), (0.011, 0.36), (0.0, 0.36)], "glass_green", None),
]
for i, (profile, glass, label) in enumerate(BOTTLES):
    p = Part("Bottle%d" % i)
    p.lathe(profile, glass, sides=16)
    if label:
        r = profile[2][0] + 0.002
        p.lathe([(r, label[0]), (r, label[1])], "label", sides=16)
    p.finish(5.0 + i * 0.2)

bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/club.glb"), export_format="GLB")
print("wrote club.glb")
