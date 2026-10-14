# Builds the underwater dome's shipwreck and writes assets/models/dome_wreck.glb.
#
#     blender --background --python tools/blender/dome_wreck.py
#
# A two-masted wooden brig, eighteen metres from stern to stem, long sunk: lying over on her
# starboard bilge in the sand, her stern quarter stove in so her frames and deck beams stand
# bare, her mainmast snapped off above the deck and lying beside her, her foremast still up with
# its yard hanging askew and a few of its stays still taut. Round her on the sand: her rudder,
# an anchor, two cannon and some barrels.
#
# Built upright (Blender X along the ship, bow at +X; Y to port; Z up, keel at 0), then heeled
# and sunk in one transform, so the origin is on the sand (Godot y = 0 is the sea floor) and
# everything below it is buried. The hull's strakes are each their own strip with a gap between
# them, UV'd one plank of weathered_brown_planks to a strake (u along the ship, 3 m a repeat).
#
# Objects:
#   Wreck        the ship, the spars, the rigging and the debris. Materials "planks" (hull and
#                deck), "frame" (ribs, beams, spars: darker, waterlogged), "iron" (cannon,
#                anchor, hoops), "rope".
#   CoralSpot.*  empties on upward-facing surfaces of the wreck: where DomeVenue grows coral.
#                Their +Z (Godot +Y) is the surface's normal.
#   Mast         an empty at the foremast's foot, its +Z up the mast: what the fish school round.
#   Stump        an empty at the broken mainmast's top.

import math
import os
import random

import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
random.seed(11)
NAMES = ["planks", "frame", "iron", "rope"]
mats = {n: bpy.data.materials.new(n) for n in NAMES}

L = 18.0          # stern to stem, along the waterline
B0 = 2.6          # half the beam, amidships
H0 = 3.2          # keel to gunwale, amidships
STRAKES = 12      # planks up each side
STATIONS = 60     # sections along the hull
GAP = 0.006       # of a strake's t, left open at each edge so the planks read
THICK = 0.07      # planking
DECK_DROP = 0.32  # deck below the gunwale
HEEL = math.radians(28.0)
SINK = 1.25       # how far the heeled hull is pushed into the sand

bm = bmesh.new()
uv_layer = bm.loops.layers.uv.new("UVMap")


def half_breadth(x):
    u = x / (L / 2)
    if u >= 0:
        return B0 * max(0.0, 1.0 - u ** 2.4) ** 0.55
    return B0 * (1.0 - 0.32 * (-u) ** 3)


def sheer(x):
    u = x / (L / 2)
    return H0 + 0.55 * u * u + (0.25 if u < -0.7 else 0.0) * min(1.0, (-0.7 - u) / 0.1)


def keel(x):
    u = x / (L / 2)
    return 1.6 * max(0.0, (u - 0.5) / 0.5) ** 2


def section(x, t, side):
    """A point on the hull's outside at `x`, `t` of the way from keel (0) to gunwale (1)."""
    th = t * math.pi / 2
    n = 3.2
    s, c = math.sin(th), math.cos(th)
    y = half_breadth(x) * (s ** (2 / n) if s > 0 else 0.0)
    z0 = keel(x)
    z = z0 + (sheer(x) - z0) * (1.0 - (c ** (2 / n) if c > 0 else 0.0))
    return Vector((x, side * y, z))


def inward(x, t, side):
    """Into the hull from the outside at (x, t): toward the centreline and up."""
    a = section(x, t, side)
    b = section(x, min(1.0, t + 0.01), side)
    tangent = (b - a)
    tangent.x = 0.0
    if tangent.length < 1e-6:
        return Vector((0, -side, 0))
    tangent.normalize()
    # Perpendicular in the section plane, pointing to the centreline.
    n = Vector((0.0, -tangent.z, tangent.y)) * side
    if n.y * side > 0:
        n = -n
    return n


def tag(faces, name):
    for f in faces:
        f.material_index = NAMES.index(name)


def strip(rows, name, uvs=None):
    """A slab from rows of (outer, inner) points along a strip: rows[i] = [(o0, i0), (o1, i1)],
    the strip's two long edges at station i. Faces outside, inside, both edges and both ends."""
    verts = []
    for i, row in enumerate(rows):
        verts.append([bm.verts.new(p) for pair in row for p in pair])  # o0 i0 o1 i1
    faces = []
    for i in range(len(verts) - 1):
        a, b = verts[i], verts[i + 1]
        faces.append(bm.faces.new((a[0], b[0], b[2], a[2])))   # outside
        faces.append(bm.faces.new((a[3], b[3], b[1], a[1])))   # inside
        faces.append(bm.faces.new((a[1], b[1], b[0], a[0])))   # lower edge
        faces.append(bm.faces.new((a[2], b[2], b[3], a[3])))   # upper edge
        if uvs is not None:
            for f, k in zip(faces[-4:], range(4)):
                for loop in f.loops:
                    idx = [v for v in (a + b)].index(loop.vert)
                    st = i if idx < 4 else i + 1
                    corner = idx % 4
                    u, v0, v1 = uvs[st]
                    loop[uv_layer].uv = (u, v1 if corner >= 2 else v0)
    faces.append(bm.faces.new((verts[0][0], verts[0][2], verts[0][3], verts[0][1])))
    faces.append(bm.faces.new((verts[-1][1], verts[-1][3], verts[-1][2], verts[-1][0])))
    tag(faces, name)
    return faces


def xs(x_from, x_to):
    """The stations from x_from to x_to, ends included exactly."""
    out = [x_from]
    step = L / STATIONS
    x = math.floor(x_from / step) * step + step
    while x < x_to - 0.05:
        out.append(x)
        x += step
    out.append(x_to)
    return out


def strake(side, k, x_from, x_to):
    t0 = k / STRAKES + GAP
    t1 = (k + 1) / STRAKES - GAP
    rows, uvs = [], []
    for x in xs(x_from, x_to):
        o0, o1 = section(x, t0, side), section(x, t1, side)
        rows.append([(o0, o0 + inward(x, t0, side) * THICK), (o1, o1 + inward(x, t1, side) * THICK)])
        uvs.append((x / 3.0, (k % 13) / 13.0 + 0.004, (k % 13 + 1) / 13.0 - 0.004))
    strip(rows, "planks", uvs)


# The hull, strake by strake. The bow's last few centimetres pinch to nothing: stop short.
BOW = L / 2 - 0.15
STERN = -L / 2
# Port side, aft: stove in. Each strake from the turn of the bilge up ends somewhere forward of
# the stern, ragged, so the frames behind stand bare.
for side in (1, -1):
    for k in range(STRAKES):
        start = STERN
        if side == 1 and k >= 3:
            start = STERN + random.uniform(3.6, 5.6) + (k - 3) * 0.12
        elif side == -1 and k >= 9 and random.random() < 0.5:
            # A couple of planks sprung on the starboard side too.
            a = random.uniform(-3.0, 3.0)
            strake(side, k, STERN, a)
            strake(side, k, a + random.uniform(0.8, 1.6), BOW)
            continue
        if side == 1 and 3 <= k <= 6 and random.random() < 0.3:
            # Not every broken strake broken clean: a stub left on the stern too.
            strake(side, k, STERN, STERN + random.uniform(0.5, 1.2))
        strake(side, k, start, BOW)

# The transom: planks across the stern, the port half gone.
for k in range(8):
    z0 = sheer(STERN) * k / 8 + 0.3
    z1 = sheer(STERN) * (k + 1) / 8 + 0.3 - 0.03
    w = half_breadth(STERN) * 0.95
    right = w if k < 3 else random.uniform(-0.6, 0.6)
    left = -w
    for xo, xi in [(STERN, STERN + THICK)]:
        rows = [[(Vector((xo, left, z0)), Vector((xi, left, z0))), (Vector((xo, left, z1)), Vector((xi, left, z1)))],
                [(Vector((xo, right, z0)), Vector((xi, right, z0))), (Vector((xo, right, z1)), Vector((xi, right, z1)))]]
        strip(rows, "planks", [(left / 3.0, k / 13.0, (k + 1) / 13.0), (right / 3.0, k / 13.0, (k + 1) / 13.0)])


def beam(a, b, size, name):
    """A square timber from a to b."""
    a, b = Vector(a), Vector(b)
    d = (b - a).normalized()
    side = d.cross(Vector((0, 0, 1)))
    if side.length < 0.1:
        side = d.cross(Vector((0, 1, 0)))
    side.normalize()
    up = side.cross(d).normalized()
    h = size * 0.5
    ring = [side * h + up * h, -side * h + up * h, -side * h - up * h, side * h - up * h]
    va = [bm.verts.new(a + r) for r in ring]
    vb = [bm.verts.new(b + r) for r in ring]
    faces = [bm.faces.new((va[i], va[(i + 1) % 4], vb[(i + 1) % 4], vb[i])) for i in range(4)]
    faces.append(bm.faces.new(list(reversed(va))))
    faces.append(bm.faces.new(vb))
    tag(faces, name)


def frame_rib(x, side, t_top):
    """One frame, inside the planking, from the keel up to `t_top`."""
    pts = [section(x, t, side) + inward(x, t, side) * (THICK + 0.07) for t in
           [i / 10 * t_top for i in range(11)]]
    for a, b in zip(pts, pts[1:]):
        beam(a, b, 0.13, "frame")


# The frames: every half metre down the stove-in quarter, each broken off at its own height;
# and the keelson along the bottom.
x = STERN + 0.35
while x < STERN + 6.6:
    frame_rib(x, 1, random.uniform(0.75, 1.0) if random.random() < 0.7 else random.uniform(0.4, 0.7))
    frame_rib(x, -1, 1.0)
    x += 0.5
beam((STERN + 0.2, 0, keel(0) + 0.15), (BOW - 1.6, 0, keel(BOW - 1.6) + 0.15), 0.22, "frame")

# The deck: planks fore and aft, narrowing to the bow, broken away over the stern quarter and
# open at the main hatch.
DECK_PLANKS = 18
HATCH = (0.6, 2.4, 0.38)  # from x, to x, half width in plank fraction


def deck_point(x, f):
    w = half_breadth(x) * 0.96
    return Vector((x, f * w, sheer(x) - DECK_DROP))


for j in range(DECK_PLANKS):
    f0 = -1 + 2 * j / DECK_PLANKS + 0.006
    f1 = -1 + 2 * (j + 1) / DECK_PLANKS - 0.006
    pieces = []
    # Broken over the stern: further forward on the port (high) side.
    broken_to = STERN + random.uniform(2.0, 3.4) + max(0.0, (f0 + 1) * 1.6)
    if j < 3:
        broken_to = STERN + random.uniform(0.0, 0.6)
    a = broken_to
    if abs((f0 + f1) * 0.5) < HATCH[2]:
        pieces = [(a, HATCH[0]), (HATCH[1], BOW - 1.0)]
    else:
        pieces = [(a, BOW - 1.0)]
    for p0, p1 in pieces:
        if p1 - p0 < 0.3:
            continue
        rows, uvs = [], []
        for xx in xs(p0, p1):
            o0, o1 = deck_point(xx, f0), deck_point(xx, f1)
            down = Vector((0, 0, -0.06))
            rows.append([(o0, o0 + down), (o1, o1 + down)])
            uvs.append((xx / 3.0, (j % 13) / 13.0 + 0.004, (j % 13 + 1) / 13.0 - 0.004))
        strip(rows, "planks", uvs)

# Deck beams under the broken quarter, a few cracked short.
x = STERN + 0.4
while x < STERN + 4.0:
    w = half_breadth(x) * 0.95
    end = w if random.random() < 0.6 else random.uniform(-0.3, 0.7) * w
    z = sheer(x) - DECK_DROP - 0.13
    beam((x, -w, z), (x, end, z), 0.16, "frame")
    x += 0.62

# The hatch's coaming, and the gunwale caps.
hz = sheer(1.5) - DECK_DROP
cw = half_breadth(1.5) * 0.96 * HATCH[2]
for ya, yb, xa, xb in [(-cw, -cw, HATCH[0], HATCH[1]), (cw, cw, HATCH[0], HATCH[1]),
                       (-cw, cw, HATCH[0], HATCH[0]), (-cw, cw, HATCH[1], HATCH[1])]:
    beam((xa, ya, hz + 0.12), (xb, yb, hz + 0.12), 0.22, "frame")
for side in (1, -1):
    start = STERN + (5.0 if side == 1 else 0.0)
    pts = [section(x, 1.0, side) + Vector((0, -side * 0.03, 0.06)) for x in xs(start, BOW)]
    for a, b in zip(pts, pts[1:]):
        beam(a, b, 0.16, "frame")

# Stem post up the bow.
stem = [Vector((BOW + 0.12 * i / 8, 0, keel(BOW) + (sheer(BOW) + 0.4 - keel(BOW)) * i / 8)) for i in range(9)]
for a, b in zip(stem, stem[1:]):
    beam(a, b, 0.2, "frame")


def spar(a, b, r0, r1, name="frame", sides=10, ragged=0.0):
    """A round spar from a to b, tapering; its top end ragged if it snapped."""
    a, b = Vector(a), Vector(b)
    d = (b - a).normalized()
    side = d.cross(Vector((0, 0, 1)))
    if side.length < 0.1:
        side = d.cross(Vector((1, 0, 0)))
    side.normalize()
    up = side.cross(d).normalized()
    ra, rb = [], []
    for s in range(sides):
        ang = 2 * math.pi * s / sides
        off = side * math.cos(ang) + up * math.sin(ang)
        ra.append(bm.verts.new(a + off * r0))
        rb.append(bm.verts.new(b + off * r1 + d * random.uniform(-ragged, ragged)))
    faces = [bm.faces.new((ra[s], ra[(s + 1) % sides], rb[(s + 1) % sides], rb[s])) for s in range(sides)]
    faces.append(bm.faces.new(list(reversed(ra))))
    faces.append(bm.faces.new(rb))
    tag(faces, name)


# The foremast, standing, with its top and its yard hanging askew; the mainmast's stump.
FORE = 4.6
deck_fore = sheer(FORE) - DECK_DROP
spar((FORE, 0, keel(FORE) + 0.3), (FORE, 0, deck_fore + 9.5), 0.2, 0.13)
spar((FORE, 0, deck_fore + 9.3), (FORE, 0, deck_fore + 13.0), 0.1, 0.06)
spar((FORE + 0.25, -3.0, deck_fore + 7.2), (FORE - 0.15, 3.2, deck_fore + 8.4), 0.08, 0.06)
# The fighting top: a little platform where the topmast meets the mast.
beam((FORE - 0.55, 0, deck_fore + 9.4), (FORE + 0.55, 0, deck_fore + 9.4), 0.12, "frame")
beam((FORE, -0.6, deck_fore + 9.42), (FORE, 0.6, deck_fore + 9.42), 0.1, "frame")
MAIN = -1.6
deck_main = sheer(MAIN) - DECK_DROP
spar((MAIN, 0, keel(MAIN) + 0.3), (MAIN, 0, deck_main + 3.4), 0.24, 0.21, ragged=0.35)
# The bowsprit.
spar((BOW - 1.2, 0, sheer(BOW) - 0.2), (BOW + 4.2, 0, sheer(BOW) + 1.8), 0.16, 0.08)

# Stays and shrouds from the foremast: a few still taut, one hanging slack.
top = Vector((FORE, 0, deck_fore + 9.3))
for side in (1, -1):
    for dx in (-0.6, 0.0, 0.6):
        foot = section(FORE + dx, 1.0, side) + Vector((0, 0, 0.1))
        spar(foot, top + Vector((0, side * 0.2, 0)), 0.022, 0.018, "rope", 5)
spar(Vector((FORE, 0, deck_fore + 12.6)), Vector((BOW + 3.8, 0, sheer(BOW) + 1.6)), 0.02, 0.018, "rope", 5)
# A slack one: down from the stump's direction in a sag, three pieces.
sag = [top + Vector((0, 0.1, -0.2)), Vector((1.6, 0.4, deck_main + 5.0)), Vector((-0.2, 0.7, deck_main + 3.6)),
       Vector((MAIN + 0.2, 0.2, deck_main + 3.2))]
for a, b in zip(sag, sag[1:]):
    spar(a, b, 0.02, 0.02, "rope", 5)

# Every piece is a closed shell: face them all outward, whichever way round each was wound.
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

# The ship's whole transform: heeled over to starboard about her keel, and pushed into the sand.
heel = Matrix.Rotation(-HEEL, 4, "X")
sink = Matrix.Translation((0, 0, -SINK))
bm.transform(sink @ heel)


# --- on the sand (already in the sand's frame: z = 0 is the sea floor) ---------------------------

def lathe(profile, at, axis_dir, name, sides=16):
    """Spins (along, r) pairs round an axis from `at` along `axis_dir`."""
    d = Vector(axis_dir).normalized()
    side = d.cross(Vector((0, 0, 1)))
    if side.length < 0.1:
        side = d.cross(Vector((1, 0, 0)))
    side.normalize()
    up = side.cross(d)
    rings = []
    for along, r in profile:
        rings.append([bm.verts.new(Vector(at) + d * along + (side * math.cos(2 * math.pi * s / sides) +
                                                               up * math.sin(2 * math.pi * s / sides)) * r)
                      for s in range(sides)])
    faces = []
    for i in range(len(rings) - 1):
        for s in range(sides):
            faces.append(bm.faces.new((rings[i][s], rings[i][(s + 1) % sides], rings[i + 1][(s + 1) % sides],
                                       rings[i + 1][s])))
    faces.append(bm.faces.new(list(reversed(rings[0]))))
    faces.append(bm.faces.new(rings[-1]))
    tag(faces, name)


# The mainmast's upper part, fallen beside her to port and half in the sand.
spar((-2.4, 4.4, 0.05), (-9.0, 9.6, 0.25), 0.2, 0.14, ragged=0.2)
spar((-6.8, 6.8, 0.15), (-6.2, 10.8, 0.4), 0.07, 0.05)
# The rudder, flat on the sand off the stern.
for i in range(5):
    beam((-L / 2 - 2.6 + i * 0.26, -2.2, 0.06), (-L / 2 - 2.3 + i * 0.22, 0.7 - i * 0.05, 0.08), 0.24, "frame")
# Two cannon, one half buried, and an anchor off the bow.
for at, d in [((-3.8, 3.2, 0.12), (0.8, 0.3, -0.04)), ((1.2, 3.6, 0.0), (-0.6, 0.7, 0.1))]:
    lathe([(0.0, 0.0), (0.0, 0.2), (0.25, 0.21), (0.3, 0.17), (1.6, 0.13), (1.65, 0.15), (1.72, 0.0)], at, d, "iron")
ax = Vector((L / 2 + 3.2, 2.6, 0.12))
spar(ax, ax + Vector((2.2, 0.8, 0.0)), 0.07, 0.06, "iron", 8)
spar(ax + Vector((2.0, 0.72, 0)), ax + Vector((2.4, -0.4, 0.25)), 0.06, 0.06, "iron", 8)
spar(ax + Vector((0.2, 0.06, 0)), ax + Vector((-0.4, 1.2, 0.1)), 0.06, 0.04, "iron", 8)
spar(ax + Vector((0.2, 0.06, 0)), ax + Vector((0.6, -1.0, 0.05)), 0.06, 0.04, "iron", 8)
# Barrels: three on the sand, one rolled against the hull.
for at, d in [((-5.0, 4.6, 0.3), (0.2, 1, 0)), ((-4.2, 5.4, 0.28), (1, 0.4, 0)), ((3.5, 4.8, 0.3), (1, -0.2, 0.0)),
              ((-11.6, 1.6, 0.42), (0, 0, 1))]:
    prof = [(-0.45, 0.0), (-0.45, 0.24), (-0.3, 0.28), (0.0, 0.31), (0.3, 0.28), (0.45, 0.24), (0.45, 0.0)]
    lathe(prof, at, d, "planks", 14)
    for h in (-0.32, 0.32):
        lathe([(h - 0.03, 0.0), (h - 0.03, 0.29), (h + 0.03, 0.29), (h + 0.03, 0.0)], at, d, "iron", 14)

bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
mesh = bpy.data.meshes.new("Wreck")
bm.normal_update()
bm.to_mesh(mesh)
bm.free()
for m in NAMES:
    mesh.materials.append(mats[m])
obj = bpy.data.objects.new("Wreck", mesh)
bpy.context.scene.collection.objects.link(obj)
bpy.context.view_layer.objects.active = obj
obj.select_set(True)
bpy.ops.object.shade_auto_smooth(angle=math.radians(35))
print("Wreck: %d faces" % len(mesh.polygons))

# Where coral grows: on what faces up and is clear of the sand, not too crowded.
spots = []
poly = list(mesh.polygons)
random.shuffle(poly)
for p in poly:
    if len(spots) >= 70:
        break
    if p.normal.z < 0.6 or p.center.z < 0.25 or p.area < 0.01:
        continue
    if mesh.materials[p.material_index].name not in ("planks", "frame"):
        continue
    if any((p.center - s[0]).length < 0.75 for s in spots):
        continue
    spots.append((p.center.copy(), p.normal.copy()))
for i, (at, n) in enumerate(spots):
    e = bpy.data.objects.new("CoralSpot.%03d" % i, None)
    e.location = at
    e.rotation_euler = n.to_track_quat("Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(e)
print("coral spots: %d" % len(spots))

for name, at, up in [("Mast", Vector((FORE, 0, keel(FORE) + 0.3)), Vector((0, 0, 1))),
                     ("Stump", Vector((MAIN, 0, deck_main + 3.4)), Vector((0, 0, 1)))]:
    e = bpy.data.objects.new(name, None)
    e.location = (sink @ heel) @ at
    e.rotation_euler = (heel.to_3x3() @ up).to_track_quat("Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(e)
    print("%s at %s" % (name, tuple(round(c, 2) for c in e.location)))

bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/dome_wreck.glb"), export_format="GLB",
                          export_apply=True)
print("wrote dome_wreck.glb")
