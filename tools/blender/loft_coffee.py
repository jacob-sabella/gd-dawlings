# Builds a Sunday coffee set on a tray and writes assets/models/loft_coffee.glb.
#
#     blender --background --python tools/blender/loft_coffee.py
#
# For the loft on a Sunday morning (LoftVenue, arrangement 1), on the low table by the windows:
# a walnut tray 0.46 x 0.3 m, and on it a cafetiere (glass jug in a steel frame, half full, its
# plunger up), two mugs (one cream, one a speckled blue, with handles), a side plate with a
# croissant on it, and a little milk jug. One object, origin at the middle of the tray's
# underside, the long side along X.
#
# Materials, swapped by name in the venue: "tray", "glass", "steel", "coffee", "cream" (the
# cream mug, the plate, the jug), "blue" (the other mug), "pastry".

import math
import os

import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
ORDER = ["tray", "glass", "steel", "coffee", "cream", "blue", "pastry"]
SEG = 20
bm = bmesh.new()


def slot(name):
    return ORDER.index(name)


def lathe(profile, mat, at=Vector((0, 0, 0)), segments=SEG):
    rings = []
    for r, z in profile:
        if r == 0.0:
            rings.append([bm.verts.new(at + Vector((0, 0, z)))])
            continue
        rings.append([bm.verts.new(at + Vector((r * math.cos(a), r * math.sin(a), z)))
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
            f.material_index = slot(mat)


def box(size, centre, mat):
    ret = bmesh.ops.create_cube(bm, size=1.0)
    for v in ret["verts"]:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])) + Vector(centre)
    faces = {f for v in ret["verts"] for f in v.link_faces}
    for f in faces:
        f.material_index = slot(mat)


def tube(points, radius, mat, sides=8):
    """A round bar along a polyline: a handle, a frame strap."""
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
            f.material_index = slot(mat)


def mug(at, mat, turn):
    # A thick-walled mug: outside up, over the lip, down the inside to a coffee surface.
    lathe([(0.0, 0.0), (0.036, 0.0), (0.04, 0.006), (0.041, 0.09), (0.038, 0.093), (0.035, 0.09),
           (0.035, 0.03)], mat, at)
    lathe([(0.035, 0.07), (0.0, 0.07)], "coffee", at)
    # The handle, a loop out of the side.
    d = Vector((math.cos(turn), math.sin(turn), 0))
    pts = []
    for k in range(9):
        a = -math.pi * 0.5 + math.pi * k / 8
        pts.append(at + d * (0.039 + 0.022 * math.cos(a)) + Vector((0, 0, 0.048 + 0.026 * math.sin(a))))
    tube(pts, 0.006, mat, 6)


# The tray: a board with a low lip round it.
W, D, T = 0.46, 0.3, 0.014
box((W, D, T), (0, 0, T * 0.5), "tray")
for sx, sy, cx, cy in ((W, 0.012, 0, D * 0.5 - 0.006), (W, 0.012, 0, -D * 0.5 + 0.006),
                       (0.012, D - 0.024, W * 0.5 - 0.006, 0), (0.012, D - 0.024, -W * 0.5 + 0.006, 0)):
    box((sx, sy, 0.026), (cx, cy, T + 0.013), "tray")
top = T

# The cafetiere, at the back left: a glass cylinder in a steel cradle, coffee in it, a lid, the
# plunger rod and knob up out of it, and a handle.
cp = Vector((-0.13, 0.05, top))
lathe([(0.0, 0.0), (0.046, 0.0), (0.046, 0.012)], "steel", cp)
lathe([(0.043, 0.012), (0.043, 0.17)], "glass", cp)
lathe([(0.042, 0.013), (0.042, 0.11), (0.0, 0.11)], "coffee", cp)
lathe([(0.046, 0.165), (0.047, 0.175), (0.04, 0.185), (0.0, 0.188)], "steel", cp)
tube([cp + Vector((0, 0, 0.18)), cp + Vector((0, 0, 0.25))], 0.003, "steel", 6)
lathe([(0.0, 0.0), (0.012, 0.004), (0.012, 0.014), (0.0, 0.02)], "steel", cp + Vector((0, 0, 0.25)), 10)
# Two straps up its sides, and a handle out of the frame.
for a in (math.pi * 0.5, -math.pi * 0.5):
    d = Vector((math.cos(a), math.sin(a), 0))
    box((0.012, 0.003, 0.15), cp + d * 0.0455 + Vector((0, 0, 0.088)), "steel")
h = Vector((1, 0, 0))
tube([cp + h * 0.046 + Vector((0, 0, 0.15)), cp + h * 0.075 + Vector((0, 0, 0.145)),
      cp + h * 0.08 + Vector((0, 0, 0.09)), cp + h * 0.07 + Vector((0, 0, 0.04)),
      cp + h * 0.046 + Vector((0, 0, 0.035))], 0.006, "steel", 6)

# The mugs, in front of it, handles turned different ways.
mug(Vector((-0.02, -0.07, top)), "cream", -0.4)
mug(Vector((0.08, 0.06, top)), "blue", 2.3)

# The plate and the croissant, to the right.
pp = Vector((0.15, -0.055, top))
lathe([(0.0, 0.0), (0.04, 0.0), (0.045, 0.004), (0.072, 0.012), (0.076, 0.016), (0.07, 0.013),
       (0.04, 0.007), (0.0, 0.007)], "cream", pp)
# A croissant: a crescent of fat segments, thickest in the middle, tapering to the horns.
segs = 9
for k in range(segs):
    a0 = -1.1 + 2.2 * k / segs
    a1 = -1.1 + 2.2 * (k + 1) / segs
    mid = (a0 + a1) * 0.5
    t = 1.0 - abs(mid) / 1.2
    r = 0.012 + 0.013 * t
    c = pp + Vector((math.sin(mid) * 0.04, -math.cos(mid) * 0.04 + 0.035, 0.007 + r * 0.8))
    tangent = Vector((math.cos(mid), math.sin(mid), 0))
    rot = Vector((0, 0, 1)).rotation_difference(tangent).to_matrix()
    ring = bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=5, radius=1.0)
    for v in ring["verts"]:
        v.co = c + rot @ Vector((v.co.x * r, v.co.y * r * 0.8, v.co.z * 0.03))
    for f in {f for v in ring["verts"] for f in v.link_faces}:
        f.material_index = slot("pastry")

# The milk jug, small, between them.
mj = Vector((0.06, -0.1, top))
lathe([(0.0, 0.0), (0.022, 0.0), (0.026, 0.02), (0.022, 0.05), (0.024, 0.06), (0.02, 0.058), (0.02, 0.03)],
      "cream", mj, 14)
tube([mj + Vector((-0.024, 0, 0.05)), mj + Vector((-0.038, 0, 0.044)), mj + Vector((-0.036, 0, 0.022)),
      mj + Vector((-0.025, 0, 0.016))], 0.004, "cream", 6)

me = bpy.data.meshes.new("coffee_set")
bm.normal_update()
bm.to_mesh(me)
bm.free()
for name in ORDER:
    me.materials.append(bpy.data.materials.new(name))
for p in me.polygons:
    p.use_smooth = me.materials[p.material_index].name not in ("tray",)
ob = bpy.data.objects.new("coffee_set", me)
bpy.context.collection.objects.link(ob)
print("coffee_set", len(me.polygons), "faces")
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/loft_coffee.glb"), export_format="GLB")
print("wrote loft_coffee.glb")
