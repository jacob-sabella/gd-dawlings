# Builds the desert camp's furnishings and writes assets/models/desert_props.glb.
#
#     blender --background --python tools/blender/desert_props.py
#
# One file, one object per piece, each with its origin on the floor under its middle (the
# lantern's too: it is hung by the ring on its top, LANTERN_RING above its origin):
#   lantern     a pierced-brass Moroccan lantern: six glass panes in a brass cage, an onion dome,
#               a finial and a ring to hang it by. 0.52 m to the top of the ring.
#   teapot      a Moroccan teapot: round belly, flared foot, tall lid with a knob, a long spout
#               curving up out of the belly, and a handle. 0.2 m.
#   tea_glass   a little tea glass, flared, 8 cm.
#   tray_table  a round engraved brass tray, 0.72 m across, on a folding six-legged stand of
#               turned wood, 0.4 m high.
#   cushion     a floor cushion, 0.62 m square and 0.16 thick, plump, with piping round its seams.
#   bolster     a long round pillow, 0.72 m, its ends gathered.
#   pouf        a round leather pouffe, 0.5 m across, 0.3 tall, stitched into gores.
#   campfire    a ring of stones round a fire of crossed logs on a bed of embers, 1.1 m across.
#   water_jar   a tall clay water jar, round-shouldered, 0.62 m.
# Materials, which DesertVenue swaps by name: "brass", "glass", "silver", "tea", "wood",
# "cushion", "piping", "leather", "stone", "log", "ember", "clay".
# Blender +Z is Godot +Y; everything here is round or square, so there is no front to turn.

import math
import os

import bpy
import bmesh
from mathutils import Euler, Vector, noise

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)

MATS = {}
for name in ("brass", "glass", "silver", "tea", "wood", "cushion", "piping", "leather", "stone", "log",
             "ember", "clay"):
    MATS[name] = bpy.data.materials.new(name)


def lathe(bm, profile, segments, mat, cap_top=True, cap_bottom=True, phase=0.0):
    """A solid of revolution round Z from (radius, z) pairs, bottom to top."""
    rings = []
    for r, z in profile:
        ring = []
        for k in range(segments):
            a = phase + math.tau * k / segments
            ring.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, z)))
        rings.append(ring)
    faces = []
    for a, b in zip(rings, rings[1:]):
        for k in range(segments):
            faces.append(bm.faces.new((a[k], a[(k + 1) % segments], b[(k + 1) % segments], b[k])))
    if cap_bottom and profile[0][0] > 1e-4:
        faces.append(bm.faces.new(list(reversed(rings[0]))))
    if cap_top and profile[-1][0] > 1e-4:
        faces.append(bm.faces.new(rings[-1]))
    for f in faces:
        f.material_index = mat
    return rings


def box(bm, size, centre, mat, rz=0.0, rx=0.0):
    ret = bmesh.ops.create_cube(bm, size=1.0)
    for v in ret["verts"]:
        co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
        co.rotate(Euler((rx, 0.0, rz)))
        v.co = co + Vector(centre)
    for f in {f for v in ret["verts"] for f in v.link_faces}:
        f.material_index = mat
    return ret["verts"]


def tube(bm, a, b, r, mat, segments=8):
    """A cylinder from point a to point b."""
    a, b = Vector(a), Vector(b)
    axis = b - a
    ret = bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=r, radius2=r, depth=axis.length)
    rot = Vector((0, 0, 1)).rotation_difference(axis.normalized())
    for v in ret["verts"]:
        v.co = rot @ v.co + (a + b) * 0.5
    for f in {f for v in ret["verts"] for f in v.link_faces}:
        f.material_index = mat
    return ret["verts"]


def new_object(name, mats):
    me = bpy.data.meshes.new(name)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    for m in mats:
        me.materials.append(MATS[m])
    return ob, bmesh.new()


def finish(ob, bm, x, smooth=True):
    bm.normal_update()
    bm.to_mesh(ob.data)
    bm.free()
    for p in ob.data.polygons:
        p.use_smooth = smooth
    # Laid out in a row in the file so they can be looked at; the venue reads each one's mesh.
    ob.location.x = x
    print("%s: %d faces, %s, dims %s" % (ob.name, len(ob.data.polygons), [m.name for m in ob.data.materials],
                                       [round(d, 3) for d in ob.dimensions]))
    return ob


# --- lantern ------------------------------------------------------------------------------------
LANTERN_RING = 0.52
ob, bm = new_object("lantern", ["brass", "glass"])
SIDES = 6
# The foot and the bowl under the cage.
lathe(bm, [(0.055, 0.0), (0.075, 0.012), (0.06, 0.03), (0.05, 0.05), (0.1, 0.075), (0.115, 0.09)], SIDES * 2, 0)
# The cage: a hexagonal frame, glass panes set in from its posts.
BODY_LO, BODY_HI, R = 0.09, 0.3, 0.112
for k in range(SIDES):
    a = math.tau * k / SIDES
    p = (math.cos(a) * R, math.sin(a) * R)
    tube(bm, (p[0], p[1], BODY_LO), (p[0], p[1], BODY_HI), 0.008, 0, 6)
    a2 = math.tau * (k + 1) / SIDES
    q = (math.cos(a2) * R, math.sin(a2) * R)
    for z in (BODY_LO + 0.004, (BODY_LO + BODY_HI) * 0.5, BODY_HI - 0.004):
        tube(bm, (p[0], p[1], z), (q[0], q[1], z), 0.0045, 0, 5)
    # The pane, a little inside the frame.
    inset = 0.96
    pa = (p[0] * inset, p[1] * inset)
    qa = (q[0] * inset, q[1] * inset)
    vs = [bm.verts.new((pa[0], pa[1], BODY_LO + 0.006)), bm.verts.new((qa[0], qa[1], BODY_LO + 0.006)),
          bm.verts.new((qa[0], qa[1], BODY_HI - 0.006)), bm.verts.new((pa[0], pa[1], BODY_HI - 0.006))]
    bm.faces.new(vs).material_index = 1
    # Pierced brass over the upper half of each pane: a pointed arch of strap round its top.
    mid = ((pa[0] + qa[0]) * 0.5 * 1.04, (pa[1] + qa[1]) * 0.5 * 1.04)
    tube(bm, (p[0] * 1.0, p[1] * 1.0, BODY_HI - 0.07), (mid[0], mid[1], BODY_HI - 0.015), 0.004, 0, 5)
    tube(bm, (q[0] * 1.0, q[1] * 1.0, BODY_HI - 0.07), (mid[0], mid[1], BODY_HI - 0.015), 0.004, 0, 5)
# The light inside: a glass globe the venue lights, so the lantern glows from its middle.
lathe(bm, [(0.0, 0.13), (0.035, 0.145), (0.045, 0.18), (0.035, 0.215), (0.0, 0.23)], 10, 1)
# The onion dome, pierced in rows (as bands of brass and glass, the light coming through).
dome = [(0.118, 0.3), (0.13, 0.315), (0.122, 0.34), (0.1, 0.37), (0.07, 0.40), (0.04, 0.425), (0.022, 0.44),
        (0.012, 0.455)]
lathe(bm, dome, SIDES * 2, 0, cap_bottom=True, cap_top=False)
lathe(bm, [(0.115, 0.3), (0.12, 0.33), (0.0, 0.33)], SIDES * 2, 1, cap_bottom=False, cap_top=False)
# Finial: beads up to the ring.
lathe(bm, [(0.012, 0.455), (0.02, 0.465), (0.012, 0.475), (0.016, 0.485), (0.008, 0.495), (0.006, 0.5)], 10, 0)
# The ring, upright, made of short tubes round a circle.
for k in range(14):
    a = math.tau * k / 14
    b = math.tau * (k + 1) / 14
    tube(bm, (math.cos(a) * 0.016, 0, 0.5 + 0.016 + math.sin(a) * 0.016),
         (math.cos(b) * 0.016, 0, 0.5 + 0.016 + math.sin(b) * 0.016), 0.003, 0, 4)
finish(ob, bm, 0.0)

# --- teapot -------------------------------------------------------------------------------------
ob, bm = new_object("teapot", ["silver"])
belly = [(0.035, 0.0), (0.042, 0.006), (0.036, 0.016), (0.05, 0.03), (0.07, 0.055), (0.074, 0.075),
         (0.066, 0.1), (0.042, 0.118), (0.032, 0.124)]
lathe(bm, belly, 24, 0)
lid = [(0.034, 0.124), (0.036, 0.13), (0.028, 0.14), (0.018, 0.16), (0.012, 0.175), (0.016, 0.182),
       (0.01, 0.192), (0.006, 0.2), (0.0, 0.203)]
lathe(bm, lid, 18, 0, cap_bottom=False)
# The spout: out of the belly low down, curving up to above the rim.
pts = []
for k in range(9):
    t = k / 8
    x = 0.06 + 0.075 * t
    z = 0.05 + 0.1 * t ** 1.6
    pts.append((x, 0.0, z))
for a, b in zip(pts, pts[1:]):
    t = pts.index(a) / 8
    tube(bm, a, b, 0.012 - 0.007 * t, 0, 8)
# The handle: a loop on the far side.
for k in range(10):
    a = -0.3 + math.pi * 1.1 * k / 10
    b = -0.3 + math.pi * 1.1 * (k + 1) / 10
    c = (-0.07, 0, 0.085)
    tube(bm, (c[0] - math.sin(a) * 0.03, 0, c[2] + math.cos(a) * 0.04),
         (c[0] - math.sin(b) * 0.03, 0, c[2] + math.cos(b) * 0.04), 0.005, 0, 6)
finish(ob, bm, 0.5)

# --- tea glass ----------------------------------------------------------------------------------
ob, bm = new_object("tea_glass", ["glass", "tea"])
lathe(bm, [(0.02, 0.0), (0.022, 0.004), (0.02, 0.012), (0.024, 0.05), (0.03, 0.08)], 14, 0, cap_top=False)
# The tea inside: a disc of amber a little under the rim, and the body of it.
lathe(bm, [(0.018, 0.006), (0.0215, 0.05), (0.025, 0.064), (0.0, 0.064)], 14, 1, cap_top=False)
finish(ob, bm, 0.8)

# --- tray table ---------------------------------------------------------------------------------
ob, bm = new_object("tray_table", ["brass", "wood"])
TOP = 0.4
lathe(bm, [(0.0, TOP - 0.006), (0.34, TOP - 0.006), (0.36, TOP), (0.362, TOP + 0.022), (0.35, TOP + 0.024),
           (0.345, TOP + 0.006), (0.0, TOP + 0.006)], 48, 0, cap_top=False, cap_bottom=False)
# The stand: six turned legs, crossing in pairs like a folding stand, and a ring under the tray.
for k in range(3):
    a = math.tau * k / 3
    for s in (-1, 1):
        lo = Vector((math.cos(a + s * 0.5) * 0.26, math.sin(a + s * 0.5) * 0.26, 0.0))
        hi = Vector((math.cos(a - s * 0.5) * 0.27, math.sin(a - s * 0.5) * 0.27, TOP - 0.02))
        tube(bm, lo, hi, 0.016, 1, 8)
        # A bead turned on each leg, two-thirds up.
        mid = lo.lerp(hi, 0.62)
        tube(bm, mid - (hi - lo).normalized() * 0.018, mid + (hi - lo).normalized() * 0.018, 0.024, 1, 8)
lathe(bm, [(0.27, TOP - 0.05), (0.29, TOP - 0.05), (0.29, TOP - 0.03), (0.27, TOP - 0.03)], 32, 1,
      cap_top=False, cap_bottom=False)
finish(ob, bm, 1.6)

# --- cushion ------------------------------------------------------------------------------------
ob, bm = new_object("cushion", ["cushion", "piping"])
bmesh.ops.create_cube(bm, size=1.0)
bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=6, use_grid_fill=True)
for v in bm.verts:
    x, y, z = v.co
    # Plump: square at the seams, bellied in the middle of each face.
    bulge = (1.0 - (2 * x) ** 2) * (1.0 - (2 * y) ** 2)
    v.co = Vector((x * 0.62, y * 0.62, (z * 0.11 + math.copysign(0.035 * bulge, z)) + 0.08))
for f in bm.faces:
    f.material_index = 0
# Piping round the seam where top meets sides, and bottom meets sides.
for zz in (0.08 + 0.055, 0.08 - 0.055):
    for (ax, ay), (bx, by) in (((-1, -1), (1, -1)), ((1, -1), (1, 1)), ((1, 1), (-1, 1)), ((-1, 1), (-1, -1))):
        tube(bm, (ax * 0.31, ay * 0.31, zz), (bx * 0.31, by * 0.31, zz), 0.008, 1, 6)
finish(ob, bm, 2.4)

# --- bolster ------------------------------------------------------------------------------------
ob, bm = new_object("bolster", ["cushion", "piping"])
prof = [(0.0, -0.36), (0.05, -0.355), (0.1, -0.33), (0.11, -0.3), (0.112, 0.0), (0.11, 0.3), (0.1, 0.33),
        (0.05, 0.355), (0.0, 0.36)]
lathe(bm, prof, 16, 0, cap_top=False, cap_bottom=False)
for v in bm.verts:
    # Laid on its side along X, resting on the floor.
    x, y, z = v.co
    v.co = Vector((z, x, y + 0.112))
for zz in (-0.32, 0.32):
    tube(bm, (zz - 0.01, 0, 0.112), (zz + 0.01, 0, 0.112), 0.105, 1, 16)
finish(ob, bm, 3.2)

# --- pouf ---------------------------------------------------------------------------------------
ob, bm = new_object("pouf", ["leather", "piping"])
prof = [(0.0, 0.0), (0.2, 0.0), (0.24, 0.03), (0.255, 0.15), (0.24, 0.27), (0.2, 0.298), (0.0, 0.302)]
lathe(bm, prof, 24, 0, cap_top=False, cap_bottom=False)
# Gores: the seams pinched in a little, so the leather reads as panels.
for v in bm.verts:
    a = math.atan2(v.co.y, v.co.x)
    r = math.hypot(v.co.x, v.co.y)
    pinch = 1.0 - 0.025 * (0.5 + 0.5 * math.cos(a * 8)) ** 6
    v.co.x = math.cos(a) * r * pinch
    v.co.y = math.sin(a) * r * pinch
tube(bm, (0, 0, 0.29), (0, 0, 0.31), 0.06, 1, 16)
finish(ob, bm, 4.0)

# --- campfire -----------------------------------------------------------------------------------
ob, bm = new_object("campfire", ["stone", "log", "ember"])
# Embers: a low mound.
lathe(bm, [(0.0, 0.0), (0.36, 0.0), (0.3, 0.04), (0.16, 0.07), (0.0, 0.08)], 20, 2, cap_bottom=False)
# Stones round it, each a lumpy squashed ball.
for k in range(11):
    a = math.tau * k / 11 + 0.1 * math.sin(k * 3.1)
    c = Vector((math.cos(a) * 0.48, math.sin(a) * 0.48, 0.05))
    ret = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
    s = (0.11 + 0.025 * math.sin(k * 1.7), 0.085 + 0.02 * math.cos(k * 2.3), 0.075)
    for v in ret["verts"]:
        n = noise.noise(v.co * 1.8 + Vector((k * 7.0, 0, 0)))
        co = Vector((v.co.x * s[0], v.co.y * s[1], v.co.z * s[2])) * (1.0 + 0.22 * n)
        co.rotate(Euler((0, 0, a)))
        v.co = co + c
    for f in {f for v in ret["verts"] for f in v.link_faces}:
        f.material_index = 0
# Logs, leant together in a cone over the embers, and two lying across.
for k in range(5):
    a = math.tau * k / 5 + 0.3
    lo = Vector((math.cos(a) * 0.32, math.sin(a) * 0.32, 0.04))
    hi = Vector((math.cos(a + 0.4) * 0.05, math.sin(a + 0.4) * 0.05, 0.42))
    tube(bm, lo, hi, 0.035 - 0.004 * (k % 2), 1, 7)
tube(bm, (-0.3, -0.12, 0.06), (0.32, 0.08, 0.07), 0.04, 1, 7)
tube(bm, (-0.08, 0.3, 0.07), (0.1, -0.3, 0.1), 0.035, 1, 7)
finish(ob, bm, 5.0, smooth=False)

# --- water jar ----------------------------------------------------------------------------------
ob, bm = new_object("water_jar", ["clay"])
prof = [(0.0, 0.0), (0.09, 0.0), (0.1, 0.02), (0.17, 0.12), (0.2, 0.26), (0.19, 0.4), (0.14, 0.5),
        (0.07, 0.55), (0.065, 0.59), (0.085, 0.61), (0.08, 0.62), (0.06, 0.6), (0.05, 0.5)]
lathe(bm, prof, 24, 0, cap_top=False)
# Two loop handles at the shoulder.
for side in (-1, 1):
    for k in range(8):
        a = math.pi * k / 8
        b = math.pi * (k + 1) / 8
        tube(bm, (side * (0.12 + math.sin(a) * 0.07), 0, 0.53 - math.cos(a) * 0.08 + 0.0),
             (side * (0.12 + math.sin(b) * 0.07), 0, 0.53 - math.cos(b) * 0.08), 0.012, 0, 6)
finish(ob, bm, 6.0)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/desert_props.glb"), export_format="GLB",
                          use_selection=True)
print("wrote desert_props.glb")
