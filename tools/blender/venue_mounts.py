# Builds what three of the venues' own instruments stand on, hang from or hang under
# (VenueInstrument, core/music/venue_instrument.gd), and writes assets/models/venue_mounts.glb.
#
#     blender --background --python tools/blender/venue_mounts.py
#
# One file, several objects, each placed by VenueInstrument._build_mount by name:
#   CaveShelf   the cave's crystals' rock shelf: a ledge of the cave's rock 1 m across, its top
#               level at 0.825 m (the crystals stand on it from 0.82, so their feet are in the
#               rock they grew out of), its front a rounded lip no further out than SHELF_FRONT,
#               undercut below so the plaque and the jack stand clear in front of it, its ends
#               rounding off into the floor, a few small points of crystal growing at each end.
#               Materials "rock" (the cave's own rock shader goes on it) and "crystal".
#   BellPost    one upright of the tubular bells' frame: a steel tube from its foot to just under
#               the rail, a collar at its foot and a ball finial on top, 1.86 m. Its origin the
#               middle of its foot. Material "steel".
#   BellRail    the frame's top rail: a steel tube 1 m long along X, with a T-fitting at each end
#               where a post meets it (scaled along X to the frame's width). Origin its middle.
#               Material "steel".
#   BellFoot    a post's foot: a steel tube 0.3 m along Z (front to back) with a rubber cap at each
#               end, sitting on the floor. Origin its middle on the floor. Materials "steel",
#               "rubber".
#   Eave        the icicles' eave: a timber board with a moulded drip edge, 1 m along X (scaled to
#               the row), a lumpy cap of snow on it drooping over its front. Origin the middle of
#               the board's foot, where the icicles hang from. Materials "wood", "snow".
#
# And slice 43's:
#   PipeHeader  the loft's steam pipes' header: an iron pipe 1 m along X (scaled to the row), its
#               axis PIPE_HEADER over the origin (where the pipes hang from), a flange at each end,
#               two brackets back to the brick behind. Materials "iron", "brass", "wheel".
#   PipeValve   a gate valve on the header's left end (its origin there): the valve's body, its
#               bonnet out toward the room and a red handwheel on it, the pipe going on from it up a
#               riser and back into the wall.
#   PipeTee     the tee over each pipe: a collar round the header and the socket the pipe drops from,
#               its origin the socket's foot.
#   PotBench    the greenhouse's potting bench: a zinc-topped board top at 0.8 m, 1 m along X
#               (scaled), its front edge 0.13 m out, legs, aprons, a slatted shelf under it and a
#               board up the back. Materials "wood", "zinc".
#   GongRack    the stage's rack: two steel posts on feet at z -0.18 (the gong's plane), 1 m apart
#               (scaled), a top bar at GONG_BAR the gong hangs from, and arms forward to a lower rail
#               at z 0 under the cymbals, its top at GONG_RAIL. Materials "steel", "rubber".
#   StoneShelf  the desert's ledge of sandstone for the ringing stones: 1 m along X (scaled), two
#               ridges along its top at z +-0.11, their tops at STONE_RIDGE, its front face no further
#               out than 0.2, its ends rounding down into the sand. Material "rock".
#
# Sizes in Godot's terms (y up, z toward the player): Blender's +Z is Godot's +Y, Blender's -Y is
# Godot's +Z. VenueInstrument repeats the ones it needs (SHELF_FRONT, SHELF_TOP, SHELF_WIDE,
# PIPE_HEADER, GONG_BAR, GONG_RAIL, STONE_RIDGE).

import math
import os
import random

import bpy
import bmesh
from mathutils import Vector, noise

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
random.seed(42)
mats = {n: bpy.data.materials.new(n) for n in ["rock", "crystal", "steel", "rubber", "wood", "snow", "iron", "brass",
                                                 "wheel", "zinc"]}

SHELF_WIDE = 1.0
SHELF_TOP = 0.825
SHELF_FRONT = 0.15
SHELF_BACK = -0.33


def g(x, y, z):
    """A point in Godot's terms (y up, z toward the player) as Blender's."""
    return Vector((x, -z, y))


def finish(bm, name, materials, x_offset, smooth=True):
    mesh = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    for m in materials:
        mesh.materials.append(mats[m])
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    for p in mesh.polygons:
        p.use_smooth = smooth
    obj.location.x = x_offset
    bb = [Vector(c) for c in obj.bound_box]
    print("%s: %d verts, %d faces, bounds x %.3f..%.3f  y(godot) %.3f..%.3f  z(godot) %.3f..%.3f" % (
        name, len(mesh.vertices), len(mesh.polygons), min(p.x for p in bb), max(p.x for p in bb),
        min(p.z for p in bb), max(p.z for p in bb), -max(p.y for p in bb), -min(p.y for p in bb)))
    return obj


def resample(loop, count):
    """A closed loop of (y, z) points walked again at `count` even steps."""
    seg = []
    total = 0.0
    for i in range(len(loop)):
        a = Vector(loop[i])
        b = Vector(loop[(i + 1) % len(loop)])
        seg.append((a, b, (b - a).length))
        total += (b - a).length
    out = []
    for k in range(count):
        want = total * k / count
        for a, b, length in seg:
            if want <= length or (a, b, length) == seg[-1]:
                t = want / length if length > 0 else 0.0
                out.append(a.lerp(b, min(t, 1.0)))
                break
            want -= length
    return out


# --- the cave's rock shelf ------------------------------------------------------------------

# Its section, (y, z), round from the floor at the back: up the back, over the top, out to the
# lip, down the undercut face and back along the floor.
SECTION = [
    (0.0, SHELF_BACK), (0.45, SHELF_BACK - 0.005), (0.78, SHELF_BACK + 0.01), (SHELF_TOP, SHELF_BACK + 0.06),
    (SHELF_TOP, -0.1), (SHELF_TOP, 0.06), (0.815, 0.11), (0.79, 0.14), (0.76, SHELF_FRONT), (0.72, 0.135),
    (0.66, 0.095), (0.55, 0.07), (0.4, 0.07), (0.22, 0.085), (0.08, 0.11), (0.0, 0.12), (0.0, -0.1),
]


def shelf():
    bm = bmesh.new()
    loop = resample(SECTION, 72)
    stations = 48
    centre = Vector((0.36, -0.1))
    rings = []
    tops = set()
    for s in range(stations + 1):
        u = s / stations
        t = abs(u - 0.5) * 2.0
        # Full section across the crystals' span; past it the rock rounds off down into the floor.
        f = 1.0 if t < 0.78 else math.sqrt(max(0.0, 1.0 - ((t - 0.78) / 0.22) ** 2)) * 0.8 + 0.2 * (1.0 - (t - 0.78) / 0.22)
        f = max(f, 0.18)
        # The face bellies out and in along the shelf, so no two sections are the same stone.
        belly = noise.noise(Vector((u * 2.3, 1.7, 0.4))) * 0.035
        ring = []
        for p in loop:
            y = centre.x + (p.x - centre.x) * f if p.x > 0.001 else 0.0
            z = centre.y + (p.y - centre.y) * f
            if p.y > 0.0 and p.x < 0.74:
                z += belly - 0.03
            # Its ends slope: wider at the floor than at the top, as a ledge of rock stands.
            x = (u - 0.5) * SHELF_WIDE * (1.1 - 0.16 * y / SHELF_TOP)
            v = bm.verts.new(g(x, y, z))
            if p.x > SHELF_TOP - 0.004 and SHELF_BACK + 0.07 < p.y < 0.06 and t < 0.8:
                tops.add(v)
            ring.append(v)
        rings.append(ring)
    n = len(loop)
    for s in range(stations):
        for i in range(n):
            a, b = rings[s][i], rings[s][(i + 1) % n]
            c, d = rings[s + 1][(i + 1) % n], rings[s + 1][i]
            bm.faces.new((a, d, c, b)).material_index = 0
    for s, flip in ((0, False), (stations, True)):
        mid = bm.verts.new(g((s / stations - 0.5) * SHELF_WIDE * 1.0, 0.05, centre.y))
        for i in range(n):
            a, b = rings[s][i], rings[s][(i + 1) % n]
            bm.faces.new((mid, b, a) if not flip else (mid, a, b)).material_index = 0
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    # Craggy, along each point's own normal: big lumps, small grain, and the ledges of its strata
    # (a sawtooth in height, warped), pushing in more than out. The top the crystals stand on stays
    # level within a few millimetres; nothing comes out past the lip, the floor or the back.
    moved = {}
    for v in bm.verts:
        gx, gy, gz = v.co.x, v.co.z, -v.co.y
        q = Vector((gx, gy, gz))
        if v in tops:
            moved[v] = g(gx, SHELF_TOP - abs(noise.noise(q * 9.0)) * 0.004, gz)
            continue
        strata = ((gy * 7.0 + 0.5 * noise.noise(q * 1.7)) % 1.0)
        out = 0.05 * noise.fractal(q * 3.2, 0.6, 2.0, 4) + 0.016 * noise.noise(q * 12.0) - 0.024 * strata - 0.012
        if gy < 0.12:
            out += (0.12 - gy) * 0.35
        normal = Vector((v.normal.x, v.normal.z, -v.normal.y))
        p = q + normal * out
        p.y = min(max(p.y, 0.0), SHELF_TOP)
        p.z = min(max(p.z, SHELF_BACK - 0.01), SHELF_FRONT - 0.004)
        moved[v] = g(p.x, p.y, p.z)
    for v, co in moved.items():
        v.co = co
    # A few small points of crystal at each end of the top, and low in the rock at the ends, leaning
    # out and up, as the cave's own grow: none where the plaque and the jack stand.
    for side in (-1.0, 1.0):
        for k in range(4):
            base = Vector((side * random.uniform(0.40, 0.46), SHELF_TOP - 0.06 - k * 0.07, random.uniform(-0.2, 0.02)))
            lean = Vector((side * random.uniform(0.25, 0.7), 1.0, random.uniform(-0.25, 0.1))).normalized()
            crystal(bm, base, lean, random.uniform(0.05, 0.13), random.uniform(0.012, 0.022))
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(bm, "CaveShelf", ["rock", "crystal"], 0.0)


def crystal(bm, base, direction, length, radius, point=1.7):
    """A six-sided prism from `base` (Godot's terms) along `direction`, `length` to the shoulder
    of its point, then the point; its root closed."""
    d = direction.normalized()
    side = d.cross(Vector((0.0, 0.0, 1.0)))
    if side.length < 0.1:
        side = d.cross(Vector((1.0, 0.0, 0.0)))
    side.normalize()
    up = d.cross(side).normalized()
    foot, shoulder = [], []
    for i in range(6):
        a = 2.0 * math.pi * i / 6.0
        r = radius * random.uniform(0.85, 1.15)
        off = side * math.cos(a) * r + up * math.sin(a) * r
        foot.append(bm.verts.new(g(*(base + off))))
        shoulder.append(bm.verts.new(g(*(base + d * length + off))))
    tip = bm.verts.new(g(*(base + d * (length + radius * point))))
    for i in range(6):
        j = (i + 1) % 6
        bm.faces.new((foot[i], foot[j], shoulder[j], shoulder[i])).material_index = 1
        bm.faces.new((shoulder[i], shoulder[j], tip)).material_index = 1
    bm.faces.new(list(reversed(foot))).material_index = 1


# --- the tubular bells' frame ---------------------------------------------------------------

def lathe(bm, profile, material, segments=20, axis="y", at=Vector((0, 0, 0))):
    """A solid turned about Godot's `axis` through `at`: `profile` is (radius, along) from one end
    to the other, each end closed."""
    rings = []
    for r, h in profile:
        ring = []
        for i in range(segments):
            a = 2.0 * math.pi * i / segments
            c, s = math.cos(a) * r, math.sin(a) * r
            if axis == "y":
                p = Vector((c, h, s))
            elif axis == "x":
                p = Vector((h, c, s))
            else:
                p = Vector((c, s, h))
            ring.append(bm.verts.new(g(*(at + p))))
        rings.append(ring)
    for k in range(len(rings) - 1):
        for i in range(segments):
            j = (i + 1) % segments
            bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i])).material_index = material
    for ring, flip in ((rings[0], True), (rings[-1], False)):
        face = bm.faces.new(ring if not flip else list(reversed(ring)))
        face.material_index = material
    return rings


TUBE = 0.018


def bell_post():
    bm = bmesh.new()
    # A collar at the foot where it sits in its foot's fitting, the tube, a fitting where it meets
    # the rail, and a ball finial over it.
    lathe(bm, [(0.0, 0.03), (0.03, 0.03), (0.03, 0.09), (0.024, 0.1), (TUBE, 0.105), (TUBE, 1.79),
               (0.026, 1.795), (0.026, 1.845), (0.016, 1.85)], 0)
    finial = [(0.0, 1.845)]
    for i in range(1, 9):
        a = math.pi * i / 9.0
        finial.append((math.sin(a) * 0.024, 1.87 - math.cos(a) * 0.024))
    finial.append((0.0, 1.894))
    lathe(bm, finial, 0)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(bm, "BellPost", ["steel"], 2.0)


def bell_rail():
    bm = bmesh.new()
    # 1 m along X; end fittings a little fatter where the posts come up into them.
    lathe(bm, [(0.0, -0.5), (0.024, -0.5), (0.026, -0.49), (0.026, -0.455), (TUBE * 0.9, -0.445),
               (TUBE * 0.9, 0.445), (0.026, 0.455), (0.026, 0.49), (0.024, 0.5), (0.0, 0.5)], 0, axis="x")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(bm, "BellRail", ["steel"], 3.5)


def bell_foot():
    bm = bmesh.new()
    lathe(bm, [(0.0, -0.15), (0.013, -0.15), (0.016, -0.145), (0.016, -0.12), (0.014, -0.115), (0.014, 0.115),
               (0.016, 0.12), (0.016, 0.145), (0.013, 0.15), (0.0, 0.15)], 0, axis="z", at=Vector((0, 0.017, 0)))
    # Rubber caps on the ends, and the fitting the post's collar stands in.
    for end in (-1.0, 1.0):
        lathe(bm, [(0.0, end * 0.15), (0.017, end * 0.15), (0.017, end * 0.165), (0.0, end * 0.168)], 1, axis="z",
              at=Vector((0, 0.017, 0)))
    lathe(bm, [(0.0, 0.0), (0.032, 0.0), (0.032, 0.034), (0.0, 0.034)], 0)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(bm, "BellFoot", ["steel", "rubber"], 4.5)


# --- the icicles' eave ----------------------------------------------------------------------

def eave():
    bm = bmesh.new()
    # The board's section (y, z), its foot at 0: a fascia 8 cm tall with a drip edge at the front.
    board = [(0.0, -0.05), (0.0, 0.0), (0.006, 0.012), (0.012, 0.012), (0.018, 0.006), (0.08, 0.006),
             (0.08, -0.05)]
    stations = 2
    rings = []
    for s in range(stations + 1):
        x = (s / stations - 0.5)
        rings.append([bm.verts.new(g(x, y, z)) for y, z in board])
    for s in range(stations):
        for i in range(len(board)):
            j = (i + 1) % len(board)
            bm.faces.new((rings[s][i], rings[s + 1][i], rings[s + 1][j], rings[s][j])).material_index = 0
    bm.faces.new(list(reversed(rings[0]))).material_index = 0
    bm.faces.new(rings[-1]).material_index = 0
    # The snow on top: a lumpy roll, higher in the middle, curling over the front edge.
    snow = []
    count = 40
    for s in range(count + 1):
        x = s / count - 0.5
        q = Vector((x * 6.0, 0.0, 0.0))
        lift = 0.018 + 0.012 * (0.5 + 0.5 * noise.fractal(q, 0.5, 2.0, 3))
        over = 0.012 + 0.008 * (0.5 + 0.5 * noise.noise(q + Vector((3.0, 1.0, 0.0))))
        section = [(0.08, -0.055), (0.08 + lift * 0.7, -0.045), (0.08 + lift, -0.015), (0.08 + lift * 0.85, 0.01 + over * 0.3),
                   (0.08 + lift * 0.3, 0.012 + over), (0.08 - 0.008, 0.008 + over * 0.6), (0.078, 0.006)]
        snow.append([bm.verts.new(g(x * 1.01, y, z)) for y, z in section])
    for s in range(count):
        for i in range(len(snow[s]) - 1):
            bm.faces.new((snow[s][i], snow[s + 1][i], snow[s + 1][i + 1], snow[s][i + 1])).material_index = 1
    for ring, flip in ((snow[0], True), (snow[-1], False)):
        face = bm.faces.new(ring if not flip else list(reversed(ring)))
        face.material_index = 1
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(bm, "Eave", ["wood", "snow"], 5.5)


# --- slice 43's -----------------------------------------------------------------------------

PIPE_HEADER = 0.05
PIPE_R = 0.034
WALL_BACK = -0.144
GONG_BAR = 1.9
GONG_RAIL = 0.975
GONG_Z = -0.18
STONE_RIDGE = 0.78


def box(bm, size, centre, material):
    """A box `size` (Godot's x, y, z) about `centre` (Godot's terms)."""
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    cx, cy, cz = centre
    v = [bm.verts.new(g(cx + sx * hx, cy + sy * hy, cz + sz * hz))
         for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
    for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
        bm.faces.new([v[i] for i in f]).material_index = material


def torus(bm, centre, radius, tube, material, axis="z", segments=32, sides=8):
    """A ring about Godot's `axis` through `centre`."""
    rings = []
    for i in range(segments):
        a = 2 * math.pi * i / segments
        ring = []
        for k in range(sides):
            b = 2 * math.pi * k / sides
            r = radius + tube * math.cos(b)
            off = tube * math.sin(b)
            if axis == "z":
                p = Vector((math.cos(a) * r, math.sin(a) * r, off))
            else:
                p = Vector((math.cos(a) * r, off, math.sin(a) * r))
            ring.append(bm.verts.new(g(*(Vector(centre) + p))))
        rings.append(ring)
    for i in range(segments):
        for k in range(sides):
            a, b = rings[i], rings[(i + 1) % segments]
            bm.faces.new((a[k], b[k], b[(k + 1) % sides], a[(k + 1) % sides])).material_index = material


def pipe_header():
    bm = bmesh.new()
    at = Vector((0, PIPE_HEADER, 0))
    lathe(bm, [(0.0, -0.5), (0.05, -0.5), (0.05, -0.485), (PIPE_R, -0.48), (PIPE_R, 0.48), (0.05, 0.485),
               (0.05, 0.5), (0.0, 0.5)], 0, segments=20, axis="x", at=at)
    # Two brackets: a strap round the pipe and a flat bar back to a plate on the brick.
    for x in (-0.33, 0.33):
        lathe(bm, [(0.0, x - 0.012), (PIPE_R + 0.006, x - 0.012), (PIPE_R + 0.006, x + 0.012), (0.0, x + 0.012)], 0,
              segments=20, axis="x", at=at)
        box(bm, (0.024, 0.012, -WALL_BACK - PIPE_R), (x, PIPE_HEADER, (WALL_BACK - PIPE_R) / 2), 0)
        box(bm, (0.07, 0.09, 0.008), (x, PIPE_HEADER, WALL_BACK + 0.004), 0)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(bm, "PipeHeader", ["iron", "brass", "wheel"], 6.5)


def pipe_valve():
    bm = bmesh.new()
    y = PIPE_HEADER
    # The body, flanged to the header's end, swelling round the gate.
    lathe(bm, [(0.0, 0.0), (0.05, 0.0), (0.05, -0.015), (0.04, -0.025), (0.058, -0.06), (0.058, -0.1), (0.04, -0.135),
               (0.05, -0.145), (0.05, -0.16), (0.0, -0.16)], 0, segments=20, axis="x", at=Vector((0, y, 0)))
    # On from it: a short run, an elbow up a riser, and the riser back into the brick over it.
    lathe(bm, [(0.0, -0.16), (PIPE_R, -0.16), (PIPE_R, -0.24), (0.0, -0.24)], 0, segments=20, axis="x",
          at=Vector((0, y, 0)))
    lathe(bm, [(0.0, y - 0.034), (PIPE_R + 0.006, y - 0.034), (PIPE_R + 0.006, y + 0.034), (0.0, y + 0.034)], 0,
          segments=20, at=Vector((-0.26, 0, 0)))
    lathe(bm, [(0.0, y), (PIPE_R, y), (PIPE_R, 0.62), (0.0, 0.62)], 0, segments=20, at=Vector((-0.26, 0, 0)))
    lathe(bm, [(0.0, 0.584), (PIPE_R + 0.006, 0.584), (PIPE_R + 0.006, 0.652), (0.0, 0.652)], 0, segments=20,
          at=Vector((-0.26, 0, 0)))
    lathe(bm, [(0.0, WALL_BACK), (0.05, WALL_BACK), (0.05, WALL_BACK + 0.012), (PIPE_R, WALL_BACK + 0.014),
               (PIPE_R, 0.0), (0.0, 0.0)], 0, segments=20, axis="z", at=Vector((-0.26, 0.618, 0)))
    # The bonnet out toward the room, its gland in brass, the stem, and the handwheel on it.
    lathe(bm, [(0.0, 0.0), (0.03, 0.0), (0.03, 0.08), (0.02, 0.09), (0.0, 0.09)], 0, segments=16, axis="z",
          at=Vector((-0.08, y, 0.03)))
    lathe(bm, [(0.0, 0.0), (0.017, 0.0), (0.017, 0.025), (0.0, 0.025)], 1, segments=12, axis="z",
          at=Vector((-0.08, y, 0.12)))
    lathe(bm, [(0.0, 0.0), (0.006, 0.0), (0.006, 0.06), (0.0, 0.06)], 0, segments=8, axis="z",
          at=Vector((-0.08, y, 0.14)))
    torus(bm, (-0.08, y, 0.19), 0.06, 0.008, 2)
    # Its spokes: two bars crossing at the hub.
    box(bm, (0.12, 0.009, 0.009), (-0.08, y, 0.19), 2)
    box(bm, (0.009, 0.12, 0.009), (-0.08, y, 0.19), 2)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(bm, "PipeValve", ["iron", "brass", "wheel"], 7.5)


def pipe_tee():
    bm = bmesh.new()
    lathe(bm, [(0.0, -0.04), (PIPE_R + 0.009, -0.04), (PIPE_R + 0.009, 0.04), (0.0, 0.04)], 0, segments=20, axis="x",
          at=Vector((0, PIPE_HEADER, 0)))
    lathe(bm, [(0.0, 0.0), (0.033, 0.0), (0.033, 0.012), (0.03, 0.014), (0.03, PIPE_HEADER), (0.0, PIPE_HEADER)], 0,
          segments=16)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(bm, "PipeTee", ["iron", "brass", "wheel"], 8.0)


def pot_bench():
    bm = bmesh.new()
    front, back = 0.13, -0.16
    # The top: boards along X, a zinc sheet over them turned up at the back.
    box(bm, (1.0, 0.025, front - back), (0, 0.7845, (front + back) / 2), 0)
    box(bm, (1.0, 0.003, front - back - 0.004), (0, 0.7985, (front + back) / 2), 1)
    box(bm, (1.0, 0.04, 0.003), (0, 0.82, back + 0.0035), 1)
    # Legs, the aprons under the top, front and back, and the ends.
    for x in (-0.46, 0.46):
        for z in (back + 0.03, front - 0.035):
            box(bm, (0.05, 0.772, 0.05), (x, 0.386, z), 0)
        box(bm, (0.025, 0.08, front - back - 0.06), (x, 0.73, (front + back) / 2), 0)
    box(bm, (0.92, 0.08, 0.022), (0, 0.73, front - 0.021), 0)
    box(bm, (0.92, 0.08, 0.022), (0, 0.73, back + 0.011), 0)
    # The slatted shelf under it, on its rails.
    for x in (-0.46, 0.46):
        box(bm, (0.03, 0.04, front - back - 0.06), (x, 0.2, (front + back) / 2), 0)
    for k in range(4):
        z = back + 0.05 + k * (front - back - 0.1) / 3
        box(bm, (0.95, 0.018, 0.05), (0, 0.229, z), 0)
    # The board up its back, on two posts.
    box(bm, (1.0, 0.2, 0.02), (0, 0.9, back - 0.01), 0)
    for x in (-0.46, 0.46):
        box(bm, (0.04, 0.24, 0.03), (x, 0.88, back - 0.025), 0)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(bm, "PotBench", ["wood", "zinc"], 9.0, smooth=False)


def gong_rack():
    bm = bmesh.new()
    for x in (-0.5, 0.5):
        # A post on its foot, a finial on top.
        lathe(bm, [(0.0, 0.03), (0.026, 0.03), (0.026, 0.07), (0.02, 0.08), (0.02, GONG_BAR + 0.04), (0.0, GONG_BAR + 0.04)],
              0, segments=16, at=Vector((x, 0, GONG_Z)))
        knob = [(0.0, GONG_BAR + 0.04)]
        for i in range(1, 8):
            a = math.pi * i / 8.0
            knob.append((math.sin(a) * 0.026, GONG_BAR + 0.066 - math.cos(a) * 0.026))
        knob.append((0.0, GONG_BAR + 0.092))
        lathe(bm, knob, 0, segments=16, at=Vector((x, 0, GONG_Z)))
        lathe(bm, [(0.0, -0.22), (0.016, -0.22), (0.016, 0.22), (0.0, 0.22)], 0, segments=12, axis="z",
              at=Vector((x, 0.018, GONG_Z)))
        for end in (-1, 1):
            lathe(bm, [(0.0, end * 0.22), (0.019, end * 0.22), (0.019, end * 0.245), (0.0, end * 0.25)], 1, segments=12,
                  axis="z", at=Vector((x, 0.018, GONG_Z)))
        # The arm forward from the post to the cymbals' rail.
        lathe(bm, [(0.0, GONG_Z), (0.011, GONG_Z), (0.011, 0.0), (0.0, 0.0)], 0, segments=10, axis="z",
              at=Vector((x, GONG_RAIL - 0.012, 0)))
    # The top bar the gong hangs from, and the cymbals' rail.
    lathe(bm, [(0.0, -0.5), (0.022, -0.5), (0.022, 0.5), (0.0, 0.5)], 0, segments=16, axis="x",
          at=Vector((0, GONG_BAR, GONG_Z)))
    lathe(bm, [(0.0, -0.5), (0.012, -0.5), (0.012, 0.5), (0.0, 0.5)], 0, segments=12, axis="x",
          at=Vector((0, GONG_RAIL - 0.012, 0)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(bm, "GongRack", ["steel", "rubber"], 10.0)


def stone_shelf():
    bm = bmesh.new()
    # Its section (y, z) round from the floor at the back: up the back, over the two ridges with a
    # hollow between them, down the front face, undercut a little, and back along the sand.
    section = [(0.0, -0.24), (0.4, -0.235), (0.68, -0.2), (0.75, -0.16), (STONE_RIDGE, -0.12), (STONE_RIDGE, -0.1),
               (0.745, -0.06), (0.735, 0.0), (0.745, 0.06), (STONE_RIDGE, 0.1), (STONE_RIDGE, 0.12), (0.75, 0.165),
               (0.69, 0.19), (0.55, 0.18), (0.4, 0.165), (0.2, 0.185), (0.0, 0.2), (0.0, -0.02)]
    loop = resample(section, 64)
    stations = 40
    rings = []
    for s in range(stations + 1):
        x = s / stations - 0.5
        # Flat along the top where the stones lie, rounding down into the sand past them.
        out = max(0.0, (abs(x) - 0.38) / 0.12)
        drop = math.sqrt(max(0.0, 1.0 - out * out))
        ring = []
        for p in loop:
            y, z = p.x, p.y
            q = Vector((x * 4.0, y * 4.0, z * 4.0))
            bump = 0.012 * noise.fractal(q, 0.6, 2.2, 4)
            top = y >= STONE_RIDGE - 0.002 and abs(x) < 0.38
            yy = y * (0.35 + 0.65 * drop) if not top else y
            zz = z * (0.8 + 0.2 * drop)
            if not top:
                zz += bump
                yy += bump * 0.5 if y > 0.01 else 0.0
            ring.append(bm.verts.new(g(x + (bump * 0.5 if abs(x) > 0.4 else 0.0), yy, zz)))
        rings.append(ring)
    n = len(loop)
    for s in range(stations):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((rings[s][i], rings[s][j], rings[s + 1][j], rings[s + 1][i])).material_index = 0
    bm.faces.new(list(reversed(rings[0]))).material_index = 0
    bm.faces.new(rings[-1]).material_index = 0
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(bm, "StoneShelf", ["rock"], 11.5)


shelf()
bell_post()
bell_rail()
bell_foot()
eave()
pipe_header()
pipe_valve()
pipe_tee()
pot_bench()
gong_rack()
stone_shelf()

bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/venue_mounts.glb"), export_format="GLB")
print("wrote venue_mounts.glb")
