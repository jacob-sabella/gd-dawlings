# Builds the jazz club's prohibition dressing ("Speakeasy") and writes
# assets/models/club_speakeasy.glb.
#
#     blender --background --python tools/blender/club_speakeasy.py
#
# One file, several objects, each placed by ClubVenue by name:
#   Bookcase    one bay of shelves full of books, 1.0 m wide, 2.5 m high, 0.34 m deep; its back
#               on Blender y = 0, its front toward -Y (Godot +Z). A row of them is the front wall,
#               and one of them is the door to the stair.
#   Barrel      an oak barrel standing on its head, staves and four iron hoops, 0.86 m high
#   Tap         a brass spigot for a barrel's head, in the head's own frame (the head's face on
#               Blender z = 0, the spout toward -Y)
#   BarrelTop   a round oak top that makes a standing barrel a table
#   Crate       a slatted crate 0.62 x 0.42 x 0.36, stencilled MAPLE SYRUP on its long sides
#   Edison      a bare filament bulb in a brass socket, hanging from its origin down Blender -Z
#   DecoMirror  a sunburst of mirror and brass rays in a stepped brass arch, 2.0 m wide and 1.06 m
#               high, its back on y = 0, origin at the middle of its foot
#   DecoSconce  a wall light: a fan of frosted glass on a stepped brass plate, back on y = 0
#   Gramophone  a cabinet gramophone with an outside horn, the horn's mouth toward -Y
#   PokerTable  an octagonal card table in green baize with a padded rail, chips, cards and a
#               cigar left in the ashtray
#   Shade       a green glass billiard shade, long along X, hanging from its origin
# Every origin is on the floor unless it says otherwise. Materials "oak", "hoop", "head", "brass",
# "walnut", "book_red", "book_green", "book_brown", "book_navy", "book_black", "gilt", "crate",
# "stencil", "socket", "bulb", "filament", "mirror", "black", "frost", "baize", "leather",
# "chip_red", "chip_white", "chip_black", "card", "card_back", "ash", "cigar", "glass_clear",
# "shellac", "label", "shade", "shade_inside".

import math
import os
import random

import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
NAMES = ["oak", "hoop", "head", "brass", "walnut", "book_red", "book_green", "book_brown", "book_navy", "book_black",
         "gilt", "crate", "stencil", "socket", "bulb", "filament", "mirror", "black", "frost", "baize", "leather",
         "chip_red", "chip_white", "chip_black", "card", "card_back", "ash", "cigar", "glass_clear", "shellac", "label",
         "shade", "shade_inside"]
mats = {n: bpy.data.materials.new(n) for n in NAMES}
rng = random.Random(1920)


class Part:
    """One object being built: a bmesh and the materials it uses (as tools/blender/club.py)."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.used = []

    def index(self, mat):
        if mat not in self.used:
            self.used.append(mat)
        return self.used.index(mat)

    def lathe(self, profile, mat, at=(0, 0, 0), sides=24):
        """Spins (r, z) pairs round the vertical axis. Returns the new verts."""
        rings = []
        made = []
        for r, z in profile:
            ring = []
            for s in range(sides):
                a = 2 * math.pi * s / sides
                v = self.bm.verts.new((at[0] + r * math.cos(a), at[1] + r * math.sin(a), at[2] + z))
                ring.append(v)
                made.append(v)
            rings.append(ring)
        k = self.index(mat)
        for i in range(len(rings) - 1):
            for s in range(sides):
                f = self.bm.faces.new((rings[i][s], rings[i][(s + 1) % sides],
                                       rings[i + 1][(s + 1) % sides], rings[i + 1][s]))
                f.material_index = k
        return made

    def tube(self, points, radius, mat, sides=8, closed=False, radii=None):
        """A round rod along `points` (each point its own radius when `radii` is given)."""
        pts = [Vector(p) for p in points]
        n = len(pts)
        rings = []
        made = []
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
            r = radii[i] if radii else radius
            ring = []
            for s in range(sides):
                a = 2 * math.pi * s / sides
                v = self.bm.verts.new(p + (side * math.cos(a) + up * math.sin(a)) * r)
                ring.append(v)
                made.append(v)
            rings.append(ring)
        k = self.index(mat)
        count = n if closed else n - 1
        for i in range(count):
            a, b = rings[i], rings[(i + 1) % n]
            for s in range(sides):
                f = self.bm.faces.new((a[s], a[(s + 1) % sides], b[(s + 1) % sides], b[s]))
                f.material_index = k
        return made

    def box(self, size, at, mat, bevel=0.0):
        """A box; returns its verts (bevelled ones included) so it can be turned afterwards."""
        before = set(self.bm.verts)
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
        return [v for v in self.bm.verts if v not in before]

    def prism(self, corners, z0, z1, mat):
        """A straight-sided solid over a polygon (counter-clockwise (x, y) corners), capped."""
        k = self.index(mat)
        lo = [self.bm.verts.new((x, y, z0)) for x, y in corners]
        hi = [self.bm.verts.new((x, y, z1)) for x, y in corners]
        n = len(corners)
        for i in range(n):
            f = self.bm.faces.new((lo[i], lo[(i + 1) % n], hi[(i + 1) % n], hi[i]))
            f.material_index = k
        self.bm.faces.new(list(reversed(lo))).material_index = k
        self.bm.faces.new(hi).material_index = k
        return lo + hi

    def turn(self, verts, matrix):
        for v in verts:
            v.co = matrix @ v.co

    def finish(self, x_offset, smooth_angle=40):
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
        bpy.ops.object.shade_auto_smooth(angle=math.radians(smooth_angle))
        obj.location.x = x_offset
        print("%s: %d faces" % (self.name, len(mesh.polygons)))
        return obj


def about(point, axis, angle):
    p = Vector(point)
    return Matrix.Translation(p) @ Matrix.Rotation(angle, 4, axis) @ Matrix.Translation(-p)


def words(body, size, mat, extrude=0.0006):
    """Filled lettering, lying in Blender X/Z, facing -Y, centred on its origin. Returns the object."""
    bpy.ops.object.text_add()
    text = bpy.context.object
    text.data.body = body
    text.data.size = size
    text.data.align_x = "CENTER"
    text.data.align_y = "CENTER"
    text.data.extrude = extrude
    text.rotation_euler = (math.pi / 2, 0, 0)
    text.data.materials.append(mats[mat])
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.object
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj


def join_into(target, others):
    bpy.ops.object.select_all(action="DESELECT")
    for o in others:
        o.select_set(True)
    target.select_set(True)
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.join()
    return bpy.context.active_object


# --- the bookcase ---------------------------------------------------------------------------
BW, BH, BD = 1.0, 2.5, 0.34
b = Part("Bookcase")
T = 0.03
for sx in (-1, 1):
    b.box((T, BD, BH - 0.02), (sx * (BW / 2 - T / 2), -BD / 2, (BH - 0.02) / 2), "walnut")
b.box((BW - 2 * T, 0.015, BH - 0.12), (0, -0.0075, BH / 2), "walnut")
b.box((BW - 0.01, BD - 0.03, 0.1), (0, -BD / 2 + 0.005, 0.05), "walnut")
# A stepped cornice, art deco: three tiers, each a little narrower, and a brass band on the first.
for i, (w, d, h) in enumerate(((BW + 0.03, BD + 0.03, 0.05), (BW - 0.04, BD - 0.01, 0.04), (BW - 0.16, BD - 0.05, 0.035))):
    z = BH - 0.02 + sum((0.05, 0.04, 0.035)[:i]) + h / 2
    b.box((w, d, h), (0, -d / 2 + 0.015 * (i == 0), z), "walnut")
b.box((BW + 0.035, 0.006, 0.012), (0, -BD - 0.0185, BH + 0.005), "brass")
SHELF_Z = [0.1, 0.49, 0.88, 1.27, 1.66, 2.05]
COLOURS = ["book_red", "book_green", "book_brown", "book_navy", "book_black", "book_brown", "book_red"]
for zi, z in enumerate(SHELF_Z):
    if zi > 0:
        b.box((BW - 2 * T, BD - 0.02, 0.022), (0, -BD / 2 - 0.005, z - 0.011), "walnut")
        b.box((BW - 2 * T, 0.004, 0.024), (0, -BD + 0.0035, z - 0.012), "brass")
    room = (SHELF_Z[zi + 1] if zi + 1 < len(SHELF_Z) else BH - 0.02) - z - 0.025
    x = -BW / 2 + T + 0.005
    end = BW / 2 - T - 0.005
    leaning = False
    while x < end - 0.03:
        w = rng.uniform(0.022, 0.055)
        if x + w > end:
            break
        # Now and then a gap, and the book at its end leaning into it.
        if rng.random() < 0.06 and not leaning:
            x += rng.uniform(0.06, 0.12)
            leaning = True
            continue
        h = min(room - 0.01, rng.uniform(0.2, 0.31))
        d = rng.uniform(0.17, 0.24)
        mat = rng.choice(COLOURS)
        front = -BD + 0.03 + rng.uniform(0.0, 0.025)
        verts = b.box((w - 0.002, d, h), (x + w / 2, front + d / 2, z + h / 2), mat)
        if rng.random() < 0.45:
            for band in (0.04, h - 0.05):
                verts += b.box((w - 0.001, 0.002, 0.008), (x + w / 2, front - 0.0005, z + band), "gilt")
        if leaning:
            # Tipped back against its neighbour, about its foot on the gap side.
            b.turn(verts, about((x, 0, z), "Y", math.radians(-14)))
            x += h * math.sin(math.radians(14)) * 0.6
            leaning = False
        x += w
b.finish(0.0)

# --- barrels --------------------------------------------------------------------------------
BARREL_H = 0.86


def barrel_r(z):
    return 0.255 + 0.05 * math.sin(math.pi * z / BARREL_H)


br = Part("Barrel")
STAVES = 20
ROWS = 12
GAP = 0.006
k = br.index("oak")
for s in range(STAVES):
    a0 = 2 * math.pi * s / STAVES + GAP
    a1 = 2 * math.pi * (s + 1) / STAVES - GAP
    grid = []
    for j in range(ROWS + 1):
        z = BARREL_H * j / ROWS
        r = barrel_r(z) * (1.0 + 0.004 * ((s * 7) % 3))
        row = []
        for a in (a0, (a0 + a1) / 2, a1):
            row.append(br.bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
        grid.append(row)
    for j in range(ROWS):
        for c in range(2):
            f = br.bm.faces.new((grid[j][c], grid[j][c + 1], grid[j + 1][c + 1], grid[j + 1][c]))
            f.material_index = k
# Inside the staves, dark, so the joints read as lines and not as holes.
br.lathe([(barrel_r(BARREL_H * j / ROWS) - 0.012, BARREL_H * j / ROWS) for j in range(ROWS + 1)], "head", sides=STAVES)
# The heads, set in from the ends (the chime), and the hoops.
for z in (0.035, BARREL_H - 0.035):
    r = barrel_r(z) - 0.01
    br.lathe([(0.0, z), (r, z)] if z > 0.1 else [(r, z), (0.0, z)], "head", sides=STAVES)
for z in (0.05, 0.2, BARREL_H - 0.2, BARREL_H - 0.05):
    r = barrel_r(z) + 0.004
    br.lathe([(r - 0.002, z - 0.022), (r, z - 0.02), (r, z + 0.02), (r - 0.002, z + 0.022)], "hoop", sides=40)
# The bung, in the belly.
br.tube([(barrel_r(BARREL_H / 2) - 0.01, 0, BARREL_H / 2), (barrel_r(BARREL_H / 2) + 0.01, 0, BARREL_H / 2)], 0.022, "head",
        sides=10)
br.finish(1.5, smooth_angle=30)

tp = Part("Tap")
tp.lathe([(0.0, 0.0), (0.028, 0.0), (0.028, 0.012), (0.016, 0.02), (0.016, 0.07), (0.019, 0.075), (0.0, 0.08)], "brass",
         sides=12)
tp.tube([(0, 0, 0.06), (0, -0.04, 0.062), (0, -0.065, 0.05)], 0.009, "brass", sides=8)
tp.tube([(0, 0.0, 0.07), (0, 0.06, 0.075)], 0.006, "brass", sides=6)
tp.finish(2.2)

bt = Part("BarrelTop")
bt.lathe([(0.0, 0.0), (0.34, 0.0), (0.35, 0.01), (0.35, 0.035), (0.34, 0.045), (0.0, 0.045)], "oak", sides=40)
bt.finish(2.6)

# --- a crate --------------------------------------------------------------------------------
cr = Part("Crate")
CW, CD, CH = 0.62, 0.42, 0.36
for sx in (-1, 1):
    for sy in (-1, 1):
        cr.box((0.04, 0.04, CH), (sx * (CW / 2 - 0.02), sy * (CD / 2 - 0.02), CH / 2), "crate")
slats = 3
sh = (CH - 0.02) / slats
for i in range(slats):
    z = 0.01 + sh * (i + 0.5)
    for sy in (-1, 1):
        cr.box((CW, 0.018, sh - 0.012), (0, sy * (CD / 2 + 0.009), z), "crate", bevel=0.003)
    for sx in (-1, 1):
        cr.box((0.018, CD, sh - 0.012), (sx * (CW / 2 + 0.009), 0, z), "crate", bevel=0.003)
for i in range(4):
    cr.box((CW + 0.04, CD / 4 - 0.01, 0.018), (0, -CD / 2 + CD / 8 + i * CD / 4, CH + 0.009), "crate", bevel=0.003)
crate = cr.finish(3.2)
stencils = []
for sy in (-1, 1):
    w = words("MAPLE SYRUP", 0.075, "stencil")
    w.location = (0, sy * (CD / 2 + 0.0195), CH * 0.55)
    w.rotation_euler = (0, 0, 0 if sy < 0 else math.pi)
    stencils.append(w)
    w2 = words("No. 7  - THIS SIDE UP -", 0.03, "stencil")
    w2.location = (0, sy * (CD / 2 + 0.0195), CH * 0.3)
    w2.rotation_euler = (0, 0, 0 if sy < 0 else math.pi)
    stencils.append(w2)
for w in stencils:
    bpy.context.view_layer.objects.active = w
    for o in bpy.context.scene.objects:
        o.select_set(o == w)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    w.location.x = 3.2
crate = join_into(crate, stencils)
crate.name = "Crate"

# --- an Edison bulb -------------------------------------------------------------------------
e = Part("Edison")
e.lathe([(0.0, 0.0), (0.012, 0.0), (0.015, -0.005), (0.016, -0.06), (0.013, -0.068), (0.0, -0.068)], "socket", sides=16)
# The glass: long and round-shouldered, an ST64.
prof = [(0.0, -0.066), (0.012, -0.066), (0.013, -0.075)]
for i in range(1, 15):
    t = i / 14
    z = -0.075 - t * 0.135
    r = 0.013 + (0.032 - 0.013) * math.sin(min(1.0, t * 1.35) * math.pi / 2) ** 0.8
    if t > 0.7:
        r *= max(0.0, math.cos((t - 0.7) / 0.3 * math.pi / 2)) ** 0.6
    prof.append((max(r, 0.004), z))
prof.append((0.0, -0.212))
e.lathe(prof, "bulb", sides=18)
# The filament: a squirrel cage of zigzags between two supports, the glass stem up the middle.
e.tube([(0, 0, -0.07), (0, 0, -0.15)], 0.002, "bulb", sides=6)
for s in range(8):
    a = 2 * math.pi * s / 8
    pts = []
    for j in range(7):
        u = j / 6
        r = 0.006 + 0.01 * math.sin(u * math.pi)
        aa = a + 0.12 * (j % 2)
        pts.append((r * math.cos(aa), r * math.sin(aa), -0.1 - u * 0.075))
    e.tube(pts, 0.0011, "filament", sides=4)
e.finish(4.0)

# --- the deco mirror ------------------------------------------------------------------------
dm = Part("DecoMirror")
R = 0.95
RAYS = 15
for i in range(RAYS):
    a0 = math.pi * i / RAYS
    a1 = math.pi * (i + 1) / RAYS
    inner = 0.24
    verts = [dm.bm.verts.new((inner * math.cos(a0), -0.012, inner * math.sin(a0))),
             dm.bm.verts.new((R * math.cos(a0), -0.012, R * math.sin(a0))),
             dm.bm.verts.new((R * math.cos(a1), -0.012, R * math.sin(a1))),
             dm.bm.verts.new((inner * math.cos(a1), -0.012, inner * math.sin(a1)))]
    f = dm.bm.faces.new(list(reversed(verts)))
    # Each pane tipped a hair so the rays catch the light one by one.
    f.material_index = dm.index("mirror")
    tilt = 0.01 * (1 if i % 2 else -1)
    for v in verts:
        v.co.y -= tilt * (v.co.length - inner)
# The rays between the panes: brass, standing proud.
for i in range(RAYS + 1):
    a = math.pi * i / RAYS
    d = Vector((math.cos(a), 0, math.sin(a)))
    dm.tube([d * 0.23 + Vector((0, -0.02, 0)), d * (R + 0.02) + Vector((0, -0.02, 0))], 0.008 if i % 2 else 0.012,
            "brass", sides=6)
# The sun in the middle, and the stepped arch round the outside.
sun = [(0.22 * math.cos(math.pi * s / 24), 0.22 * math.sin(math.pi * s / 24)) for s in range(25)]
sun_verts = dm.prism([(x, -z) for x, z in reversed(sun)], -0.03, 0.0, "brass")
dm.turn(sun_verts, Matrix.Rotation(-math.pi / 2, 4, "X"))
for rr, w in ((R + 0.03, 0.016), (R + 0.075, 0.012), (R + 0.11, 0.009)):
    arc = [(rr * math.cos(math.pi * s / 40), -0.02, rr * math.sin(math.pi * s / 40)) for s in range(41)]
    dm.tube(arc, w, "brass", sides=6)
dm.box((2 * (R + 0.13), 0.05, 0.05), (0, -0.025, -0.025), "brass", bevel=0.006)
dm.box((2 * R + 0.1, 0.012, R + 0.08), (0, -0.006, (R + 0.08) / 2 - 0.03), "black")
dm.finish(5.0)

# --- a deco sconce --------------------------------------------------------------------------
ds = Part("DecoSconce")
for i, (w, h, d) in enumerate(((0.16, 0.3, 0.015), (0.12, 0.24, 0.03), (0.08, 0.18, 0.045))):
    ds.box((w, d, h), (0, -d / 2, 0), "brass", bevel=0.003)
# The glass: a half fan rising from a brass cup, ringed in brass at each step.
glass_k = ds.index("frost")
prof = [(0.03, -0.02), (0.06, 0.02), (0.1, 0.08), (0.125, 0.15), (0.13, 0.19)]
half = 12
rows = []
for r, z in prof:
    row = []
    for s in range(half + 1):
        a = math.pi * s / half
        row.append(ds.bm.verts.new((r * math.cos(a), -0.05 - r * math.sin(a) * 0.8, z)))
    rows.append(row)
for j in range(len(rows) - 1):
    for s in range(half):
        f = ds.bm.faces.new((rows[j][s], rows[j][s + 1], rows[j + 1][s + 1], rows[j + 1][s]))
        f.material_index = glass_k
for r, z in prof[1:]:
    ds.tube([(r * math.cos(math.pi * s / half) * 1.01, -0.05 - r * math.sin(math.pi * s / half) * 0.81, z) for s in range(half + 1)],
            0.004, "brass", sides=5)
ds.lathe([(0.0, -0.04), (0.035, -0.04), (0.035, -0.02), (0.0, -0.02)], "brass", at=(0, -0.05, 0), sides=12)
ds.finish(6.5)

# --- the gramophone -------------------------------------------------------------------------
g = Part("Gramophone")
GW, GH = 0.5, 0.8
for sx in (-1, 1):
    for sy in (-1, 1):
        g.tube([(sx * 0.21, sy * 0.21, 0.0), (sx * 0.2, sy * 0.2, 0.12)], 0.02, "walnut", sides=8)
g.box((GW, GW, GH - 0.12), (0, 0, 0.12 + (GH - 0.12) / 2), "walnut", bevel=0.01)
g.box((GW + 0.02, GW + 0.02, 0.03), (0, 0, GH + 0.015), "walnut", bevel=0.008)
# Deco doors on the front: two panels with a brass fan on each.
for sx in (-1, 1):
    g.box((GW / 2 - 0.04, 0.012, GH - 0.25), (sx * GW / 4, -GW / 2 - 0.006, 0.12 + (GH - 0.12) / 2), "walnut", bevel=0.004)
    g.tube([(sx * 0.02, -GW / 2 - 0.014, 0.47), (sx * 0.02, -GW / 2 - 0.014, 0.55)], 0.006, "brass", sides=6)
    for r in range(5):
        a = math.pi * (0.1 + 0.2 * r)
        g.tube([(sx * GW / 4, -GW / 2 - 0.013, 0.24), (sx * GW / 4 + 0.08 * math.cos(a), -GW / 2 - 0.013, 0.24 + 0.08 * math.sin(a))],
               0.003, "brass", sides=4)
# The turntable: a felt platter, a record on it with its label, the spindle.
g.lathe([(0.0, GH + 0.03), (0.17, GH + 0.03), (0.17, GH + 0.045), (0.0, GH + 0.045)], "black", sides=40)
g.lathe([(0.0, GH + 0.046), (0.16, GH + 0.046), (0.16, GH + 0.049), (0.0, GH + 0.049)], "shellac", sides=40)
g.lathe([(0.0, GH + 0.0495), (0.05, GH + 0.0495), (0.0, GH + 0.05)], "label", sides=24)
g.tube([(0, 0, GH + 0.04), (0, 0, GH + 0.07)], 0.004, "brass", sides=6)
# The tone arm, from a post at the back right corner over the record; the horn rises from the
# post, bends forward and flares toward the room.
post = Vector((0.18, 0.18, GH + 0.03))
g.lathe([(0.0, 0.0), (0.035, 0.0), (0.03, 0.05), (0.0, 0.05)], "brass", at=post, sides=14)
g.tube([post + Vector((0, 0, 0.05)), post + Vector((-0.05, -0.07, 0.07)), Vector((0.02, -0.06, GH + 0.09))], 0.012, "brass",
       sides=10)
g.box((0.04, 0.05, 0.03), (0.01, -0.07, GH + 0.075), "brass", bevel=0.005)
path = []
radii = []
N = 22
for i in range(N + 1):
    u = i / N
    # Up from the post and over toward the front, the bell ending well above the cabinet.
    x = post.x - 0.08 * u
    y = post.y - 0.5 * (u ** 1.3)
    z = post.z + 0.05 + 0.55 * math.sin(u * math.pi * 0.62)
    path.append((x, y, z))
    radii.append(0.022 + 0.3 * u ** 3.2)
g.tube(path, 0.0, "brass", sides=24, radii=radii)
# A rolled rim at the mouth.
mouth = Vector(path[-1])
dirn = (mouth - Vector(path[-2])).normalized()
side = dirn.cross(Vector((0, 0, 1))).normalized()
up = side.cross(dirn).normalized()
rim = [mouth + (side * math.cos(2 * math.pi * s / 32) + up * math.sin(2 * math.pi * s / 32)) * radii[-1] for s in range(32)]
g.tube(rim, 0.008, "brass", sides=6, closed=True)
# The crank on its side.
g.tube([(GW / 2, 0.0, 0.62), (GW / 2 + 0.05, 0.0, 0.62), (GW / 2 + 0.06, 0.0, 0.52), (GW / 2 + 0.09, 0.0, 0.52)], 0.008, "brass",
       sides=6)
g.finish(7.5)

# --- the card table -------------------------------------------------------------------------
pt = Part("PokerTable")
OCT = [(0.6 / math.cos(math.pi / 8) * math.cos(math.pi / 8 + math.pi * i / 4),
        0.6 / math.cos(math.pi / 8) * math.sin(math.pi / 8 + math.pi * i / 4)) for i in range(8)]
TOP_Z = 0.76
pt.lathe([(0.0, 0.0), (0.34, 0.0), (0.34, 0.03), (0.2, 0.06), (0.09, 0.1), (0.07, 0.6), (0.12, 0.64), (0.0, 0.64)], "walnut",
         sides=8)
pt.prism([(x * 0.98, y * 0.98) for x, y in OCT], 0.64, TOP_Z - 0.03, "walnut")
pt.prism([(x * 0.86, y * 0.86) for x, y in OCT], TOP_Z - 0.03, TOP_Z - 0.012, "baize")
# The padded rail round the baize: a fat rounded tube on the octagon.
rail = [(x * 0.93, y * 0.93, TOP_Z - 0.01) for x, y in OCT]
pt.tube(rail, 0.05, "leather", sides=10, closed=True)
pt.tube([(x * 1.0, y * 1.0, TOP_Z - 0.05) for x, y in OCT], 0.012, "brass", sides=6, closed=True)
# At each of five places: a stack or two of chips; two cards face down; the pot in the middle.
CHIP = [(0.0, 0.0), (0.019, 0.0), (0.02, 0.002), (0.02, 0.0045), (0.019, 0.0065), (0.0, 0.0065)]
felt_z = TOP_Z - 0.012
for i in range(5):
    a = math.radians(-60 + 60 * i)
    d = Vector((math.cos(a), math.sin(a), 0))
    s = Vector((-d.y, d.x, 0))
    base = d * 0.36
    for stack, kind in enumerate(("chip_red", "chip_black", "chip_white")[: 2 + (i % 2)]):
        at = base + s * (0.05 * stack - 0.04)
        n = 3 + (i * 5 + stack * 3) % 9
        for c in range(n):
            pt.lathe(CHIP, kind, at=(at.x + 0.0015 * ((c * 7) % 3 - 1), at.y, felt_z + c * 0.0066), sides=14)
    for c in range(2):
        card = pt.box((0.063, 0.088, 0.0012), (0, 0, 0), "card_back")
        pt.turn(card, Matrix.Translation(d * 0.22 + s * (0.02 * c - 0.01) + Vector((0, 0, felt_z + 0.0008 + c * 0.0013)))
                @ Matrix.Rotation(a + math.pi / 2 + 0.15 * (c - 0.5) + 0.2 * i, 4, "Z"))
for c in range(5):
    card = pt.box((0.063, 0.088, 0.0012), (0, 0, 0), "card")
    pt.turn(card, Matrix.Translation(Vector((-0.16 + c * 0.075, -0.03, felt_z + 0.0008))) @ Matrix.Rotation(0.03 * c, 4, "Z"))
for c in range(14):
    kind = ("chip_red", "chip_white", "chip_black")[c % 3]
    pt.lathe(CHIP, kind, at=(0.05 + 0.03 * math.cos(c * 2.4) * (c % 4) / 3, 0.1 + 0.03 * math.sin(c * 2.4) * (c % 4) / 3,
                             felt_z + (c // 5) * 0.0066), sides=14)
# The ashtray, glass, and a cigar left in it with its ash.
pt.lathe([(0.0, 0.0), (0.055, 0.0), (0.06, 0.02), (0.05, 0.022), (0.045, 0.008), (0.0, 0.008)], "glass_clear",
         at=(-0.14, 0.15, felt_z), sides=20)
pt.tube([(-0.14, 0.15, felt_z + 0.018), (-0.06, 0.18, felt_z + 0.03)], 0.009, "cigar", sides=10)
pt.tube([(-0.06, 0.18, felt_z + 0.03), (-0.045, 0.185, felt_z + 0.032)], 0.0088, "ash", sides=10)
pt.finish(9.0)

# --- the shade over the table ---------------------------------------------------------------
sd = Part("Shade")
L = 0.62
ARC = [(0.15 * math.cos(math.pi * s / 16), -0.15 + 0.12 * math.sin(math.pi * s / 16)) for s in range(17)]
k = sd.index("shade")
ends = [[sd.bm.verts.new((x, y, z)) for y, z in ARC] for x in (-L / 2, L / 2)]
for s in range(16):
    sd.bm.faces.new((ends[0][s], ends[0][s + 1], ends[1][s + 1], ends[1][s])).material_index = k
for x, row, flip in ((-L / 2, ends[0], True), (L / 2, ends[1], False)):
    centre = sd.bm.verts.new((x, 0, -0.15))
    for s in range(16):
        tri = (row[s], row[s + 1], centre) if flip else (row[s + 1], row[s], centre)
        sd.bm.faces.new(tri).material_index = k
for x in (-L / 2 - 0.004, L / 2 + 0.004):
    sd.tube([(x, y, z) for y, z in ARC], 0.006, "brass", sides=6)
for y in (-0.152, 0.152):
    sd.tube([(-L / 2 - 0.004, y, -0.15), (L / 2 + 0.004, y, -0.15)], 0.006, "brass", sides=6)
sd.box((0.12, 0.03, 0.02), (0, 0, -0.008), "brass", bevel=0.004)
sd.finish(10.0)

bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/club_speakeasy.glb"), export_format="GLB")
print("wrote club_speakeasy.glb")
