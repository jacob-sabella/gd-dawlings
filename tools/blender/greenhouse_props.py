# Builds the glasshouse's ironwork, stone and furniture and writes assets/models/greenhouse_props.glb.
#
#     blender --background --python tools/blender/greenhouse_props.py
#
# One file, several objects, each placed by GreenhouseVenue by name:
#   Column      a cast-iron column, 5.0 m: a square plinth, a moulded base, a fluted shaft with a
#               little entasis, a necking ring, a bell capital dressed in eight curling leaves and
#               a square abacus. Origin on the floor at its centre.
#   Spandrel    the pierced iron bracket in the corner between a column and the beam it carries:
#               a quarter-round arch, a ring and a smaller ring in the spandrel, in Blender's XZ
#               plane (Godot XY), 0.9 m each way. Origin at the corner, the column side at x 0,
#               the beam side at z 0, the bracket reaching +X and down.
#   Fountain    a stone fountain, 2.1 m: a moulded basin 2.5 m across, a baluster pedestal, a
#               scalloped upper bowl and a small top bowl under a pine-cone finial.
#   FountainWater  the water standing in the three bowls (material "water").
#   FountainVeil   the water falling off the two upper rims as round veils, and the jet off the
#               finial (material "veil"), which the venue animates in a shader.
#   Pot         a terracotta flower pot with a rolled rim and soil in it, 0.3 m.
#   Bench       a potting bench, 2.0 x 0.65 m, its slatted top at 0.85 m, a back board and a
#               slatted shelf under it. Its back is at Blender +Y (Godot -Z).
#   Staging     tiered plant staging, 2.4 x 1.1 m: three slatted steps on iron ends, rising to the
#               back (Blender +Y, Godot -Z).
#   Basket      a hanging wire basket lined with moss on three chains from a ring. Origin at the
#               ring; the basket's rim 0.55 m below it.
#   Lantern     a hexagonal hanging lantern: a glass body in an iron frame, a crown and a ring.
#               Origin at the ring, the body below it. Materials "iron", "glass", "brass".
#   LampPost    a garden lamp: a fluted iron post with a ladder bar, the lantern on top, 3.2 m.
#   Urn         a stone garden urn on a pedestal, 1.3 m.
#   WateringCan a zinc can with a long spout and its rose, 0.4 m.
#   TreeRound / TreeTall   broadleaf trees for the garden, one unit tall (the venue scales them):
#               a trunk forking into the crown, the crown lumpy clouds of leaves.
#   Yew         a clipped yew cone, one unit tall.
# Origins on the ground unless said. Materials: "iron", "stone", "water", "veil", "terracotta",
# "soil", "wood", "moss", "glass", "brass", "zinc", "bark", "canopy", "yew".

import math
import os
import random

import bpy
import bmesh
from mathutils import Vector, noise

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
random.seed(5)
NAMES = ["iron", "stone", "water", "veil", "terracotta", "soil", "wood", "moss", "glass", "brass", "zinc",
         "bark", "canopy", "yew"]
mats = {n: bpy.data.materials.new(n) for n in NAMES}
UP = Vector((0, 0, 1))


class Builder:
    def __init__(self, name, slots):
        self.name = name
        self.slots = slots
        self.bm = bmesh.new()

    def v(self, p):
        return self.bm.verts.new(Vector(p))

    def face(self, verts, slot):
        f = self.bm.faces.new([x if isinstance(x, bmesh.types.BMVert) else self.v(x) for x in verts])
        f.material_index = self.slots.index(slot)
        return f

    def lathe(self, profile, slot, segments=32, scallop=None, phase=0.0):
        """Revolve (r, z) points round Z. `scallop(i, a)` may scale the radius of profile point i
        at angle a, for a scalloped rim."""
        rings = []
        for i, (r, z) in enumerate(profile):
            ring = []
            for s in range(segments):
                a = phase + 2 * math.pi * s / segments
                rr = r * (scallop(i, a) if scallop else 1.0)
                ring.append(self.v((rr * math.cos(a), rr * math.sin(a), z)))
            rings.append(ring)
        for i in range(len(rings) - 1):
            for s in range(segments):
                self.face([rings[i][s], rings[i][(s + 1) % segments], rings[i + 1][(s + 1) % segments],
                           rings[i + 1][s]], slot)
        return rings

    def box(self, size, centre, slot):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        for vert in bm.verts:
            vert.co = Vector((vert.co.x * size[0] + centre[0], vert.co.y * size[1] + centre[1],
                              vert.co.z * size[2] + centre[2]))
        self._merge(bm, slot)

    def _merge(self, bm, slot):
        mapping = {}
        for vert in bm.verts:
            mapping[vert] = self.v(vert.co)
        for f in bm.faces:
            nf = self.bm.faces.new([mapping[x] for x in f.verts])
            nf.material_index = self.slots.index(slot)
        bm.free()

    def bar(self, a, b, w, d, slot, up=None):
        """A square-section bar from a to b, `w` across and `d` the other way."""
        a, b = Vector(a), Vector(b)
        axis = (b - a).normalized()
        up = Vector(up) if up else (UP if abs(axis.z) < 0.9 else Vector((0, 1, 0)))
        side = axis.cross(up).normalized()
        upn = side.cross(axis).normalized()
        corners = [side * w * 0.5 + upn * d * 0.5, -side * w * 0.5 + upn * d * 0.5,
                   -side * w * 0.5 - upn * d * 0.5, side * w * 0.5 - upn * d * 0.5]
        ra = [self.v(a + c) for c in corners]
        rb = [self.v(b + c) for c in corners]
        for k in range(4):
            self.face([ra[k], ra[(k + 1) % 4], rb[(k + 1) % 4], rb[k]], slot)
        self.face(list(reversed(ra)), slot)
        self.face(rb, slot)

    def path(self, points, w, d, slot, up=None):
        """Bars along a polyline, mitred only by overlap: cheap and fine at this size."""
        for i in range(len(points) - 1):
            self.bar(points[i], points[i + 1], w, d, slot, up)

    def tube(self, points, radii, sides, slot, closed_end=True):
        rings = []
        for i, p in enumerate(points):
            d = (points[min(i + 1, len(points) - 1)] - points[max(i - 1, 0)]).normalized()
            side = d.cross(UP if abs(d.z) < 0.9 else Vector((1, 0, 0))).normalized()
            up = side.cross(d).normalized()
            rings.append([self.v(p + (side * math.cos(2 * math.pi * s / sides) + up * math.sin(2 * math.pi * s / sides))
                                 * radii[i]) for s in range(sides)])
        for i in range(len(rings) - 1):
            for s in range(sides):
                self.face([rings[i][s], rings[i][(s + 1) % sides], rings[i + 1][(s + 1) % sides], rings[i + 1][s]],
                          slot)
        if closed_end:
            self.face(list(reversed(rings[0])), slot)
            self.face(rings[-1], slot)

    def blob(self, centre, radius, squash, seed, slot, subdiv=2, rough=0.3):
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
        c = Vector(centre)
        sv = Vector((seed * 3.1, seed * 1.7, seed * 5.3))
        for vert in bm.verts:
            d = vert.co.normalized()
            bump = 1.0 + noise.fractal(d * 2.2 + sv, 0.6, 2.0, 3) * rough
            vert.co = c + Vector((d.x * radius, d.y * radius, d.z * radius * squash)) * bump
        self._merge(bm, slot)

    def finish(self, x_offset, smooth=True, angle=40):
        mesh = bpy.data.meshes.new(self.name)
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-6)
        self.bm.normal_update()
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for s in self.slots:
            mesh.materials.append(mats[s])
        for p in mesh.polygons:
            p.use_smooth = smooth
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        if smooth:
            bpy.context.view_layer.objects.active = obj
            for o in bpy.context.scene.objects:
                o.select_set(o == obj)
            bpy.ops.object.shade_auto_smooth(angle=math.radians(angle))
        obj.location.x = x_offset
        print("%s: %d faces" % (self.name, len(mesh.polygons)))
        return obj


def ring_points(centre, radius, n, plane="XZ", start=0.0, end=2 * math.pi):
    c = Vector(centre)
    out = []
    for i in range(n + 1):
        a = start + (end - start) * i / n
        if plane == "XZ":
            out.append(c + Vector((math.cos(a) * radius, 0, math.sin(a) * radius)))
        else:
            out.append(c + Vector((math.cos(a) * radius, math.sin(a) * radius, 0)))
    return out


# --- the column -------------------------------------------------------------------------------

COLUMN_H = 5.0


def column():
    b = Builder("Column", ["iron"])
    b.box((0.36, 0.36, 0.3), (0, 0, 0.15), "iron")
    # The base: a torus over a scotia over a torus, round on the plinth.
    base = [(0.0, 0.3), (0.165, 0.3), (0.17, 0.33), (0.155, 0.36), (0.13, 0.38), (0.14, 0.41),
            (0.125, 0.44), (0.11, 0.46)]
    b.lathe(base, "iron", 24)
    # The shaft, fluted: sixteen shallow flutes, the radius pinched between them.
    flutes = 16
    shaft = []
    for k in range(13):
        t = k / 12
        z = 0.46 + (4.42 - 0.46) * t
        shaft.append((0.105 - 0.02 * t + 0.008 * math.sin(math.pi * t), z))

    def flute(i, a):
        return 1.0 - 0.07 * (0.5 + 0.5 * math.cos(a * flutes))
    b.lathe(shaft, "iron", flutes * 2, scallop=flute)
    # The necking, the bell, the leaves round it and the abacus.
    neck = [(0.0, 4.42), (0.1, 4.42), (0.12, 4.45), (0.12, 4.49), (0.095, 4.5), (0.1, 4.6), (0.13, 4.72),
            (0.18, 4.86), (0.2, 4.9), (0.0, 4.9)]
    b.lathe(neck, "iron", 24)
    for k in range(8):
        a = 2 * math.pi * k / 8 + math.pi / 8
        out = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-math.sin(a), math.cos(a), 0))
        pts = []
        for j in range(7):
            t = j / 6
            r = 0.1 + 0.11 * t + 0.06 * max(0.0, t - 0.6) * 2.5
            z = 4.52 + 0.36 * t - 0.12 * max(0.0, t - 0.7) ** 2 * 10
            pts.append(out * r + Vector((0, 0, z)))
        for j in range(6):
            w0 = 0.055 * math.sin(math.pi * min(j / 6 * 1.1 + 0.15, 1.0))
            w1 = 0.055 * math.sin(math.pi * min((j + 1) / 6 * 1.1 + 0.15, 1.0))
            b.face([pts[j] - side * w0, pts[j] + side * w0, pts[j + 1] + side * w1, pts[j + 1] - side * w1], "iron")
    b.box((0.42, 0.42, 0.1), (0, 0, COLUMN_H - 0.05), "iron")
    return b.finish(0.0, angle=50)


# --- the spandrel bracket ----------------------------------------------------------------------

def spandrel():
    b = Builder("Spandrel", ["iron"])
    s = 0.9
    w, d = 0.035, 0.03
    # The frame: down the column, along the beam, and the arch between.
    b.bar((0.0, 0, 0.0), (0.0, 0, -s), w, d, "iron", up=(0, 1, 0))
    b.bar((0.0, 0, 0.0), (s, 0, 0.0), w, d, "iron", up=(0, 1, 0))
    arc = [Vector((s - s * math.cos(t), 0, -s + s * math.sin(t))) for t in
           [math.pi * 0.5 * i / 16 for i in range(17)]]
    # The arch runs from the column's foot of the bracket (0, -s) up to the beam's end (s, 0):
    # concave, like the soffit of an arch.
    arc = [Vector((s * (1 - math.sin(t)), 0, -s * (1 - math.cos(t)) - 0.0)) for t in
           [math.pi * 0.5 * (1 - i / 16) for i in range(17)]]
    b.path(arc, w * 1.2, d, "iron", up=(0, 1, 0))
    # The rings in the spandrel: a big one in the corner and a small one either side of it.
    b.path(ring_points((0.24, 0, -0.24), 0.14, 20), 0.025, d * 0.8, "iron", up=(0, 1, 0))
    b.path(ring_points((0.24, 0, -0.24), 0.06, 12), 0.02, d * 0.8, "iron", up=(0, 1, 0))
    b.path(ring_points((0.55, 0, -0.08), 0.055, 12), 0.02, d * 0.8, "iron", up=(0, 1, 0))
    b.path(ring_points((0.08, 0, -0.55), 0.055, 12), 0.02, d * 0.8, "iron", up=(0, 1, 0))
    # A drop finial under the corner where the arch meets the column.
    return b.finish(1.0, smooth=False)


# --- the fountain -----------------------------------------------------------------------------

def fountain():
    b = Builder("Fountain", ["stone"])
    basin = [(1.14, 0.0), (1.2, 0.08), (1.18, 0.12), (1.2, 0.42), (1.27, 0.48), (1.27, 0.56), (1.22, 0.6),
             (1.1, 0.6), (1.06, 0.55), (1.06, 0.2), (0.32, 0.2)]
    b.lathe(basin, "stone", 48)
    stem = [(0.32, 0.2), (0.34, 0.26), (0.3, 0.3), (0.2, 0.38), (0.15, 0.55), (0.17, 0.7), (0.24, 0.82),
            (0.2, 0.92), (0.13, 1.0), (0.12, 1.08), (0.16, 1.14),
            # The upper bowl's underside, out to its scalloped rim, then back in over its water.
            (0.3, 1.18), (0.5, 1.25), (0.64, 1.33), (0.72, 1.4), (0.72, 1.45), (0.66, 1.46), (0.6, 1.4),
            (0.3, 1.36), (0.1, 1.36), (0.08, 1.42), (0.07, 1.55), (0.1, 1.62),
            # The top bowl.
            (0.2, 1.66), (0.31, 1.72), (0.34, 1.77), (0.3, 1.78), (0.26, 1.74), (0.07, 1.73),
            # The finial: a pine cone on a collar.
            (0.06, 1.8), (0.08, 1.86), (0.09, 1.93), (0.075, 2.0), (0.05, 2.05), (0.02, 2.09), (0.0, 2.1)]

    def scallop(i, a):
        # Only the upper bowl's rim is scalloped: twelve lobes.
        return 1.0 + 0.05 * abs(math.cos(a * 6)) if 13 <= i <= 17 else 1.0
    b.lathe(stem, "stone", 48, scallop=scallop)
    out = b.finish(2.0, angle=45)
    w = Builder("FountainWater", ["water"])
    for r, z in [(1.06, 0.5), (0.61, 1.41), (0.27, 1.75)]:
        w.lathe([(0.0, z), (r, z)], "water", 48)
    w.finish(2.0, smooth=False)
    veil = Builder("FountainVeil", ["veil"])
    # Off the rims, falling and drawing in a little as water does; open tubes, no caps.
    veil.lathe([(0.75, 1.44), (0.77, 1.3), (0.78, 1.0), (0.79, 0.7), (0.8, 0.5)], "veil", 48,
               scallop=lambda i, a: 1.0 + 0.05 * abs(math.cos(a * 6)) * (1 - i / 4))
    veil.lathe([(0.345, 1.77), (0.355, 1.6), (0.36, 1.41)], "veil", 32)
    veil.lathe([(0.012, 2.08), (0.02, 2.25), (0.006, 2.4)], "veil", 8)
    veil.finish(2.0)
    return out


# --- pots, benches and staging ------------------------------------------------------------------

def pot():
    b = Builder("Pot", ["terracotta", "soil"])
    prof = [(0.0, 0.0), (0.1, 0.0), (0.105, 0.01), (0.135, 0.24), (0.14, 0.245), (0.155, 0.25), (0.158, 0.3),
            (0.145, 0.302), (0.138, 0.28), (0.125, 0.24)]
    b.lathe(prof, "terracotta", 20)
    b.lathe([(0.125, 0.24), (0.0, 0.25)], "soil", 20)
    return b.finish(5.0, angle=50)


def bench():
    b = Builder("Bench", ["wood", "iron"])
    L, D, H = 2.0, 0.65, 0.85
    for x in (-L / 2 + 0.06, L / 2 - 0.06):
        for y in (-D / 2 + 0.05, D / 2 - 0.05):
            b.box((0.06, 0.06, H - 0.03), (x, y, (H - 0.03) / 2), "wood")
    for i in range(5):
        y = -D / 2 + 0.065 + i * (D - 0.13) / 4
        b.box((L, 0.115, 0.03), (0, y, H - 0.015), "wood")
    # A back board and the two ends standing up off the top, to hold the soil in.
    b.box((L, 0.025, 0.22), (0, D / 2 - 0.0125, H + 0.11), "wood")
    for x in (-L / 2 + 0.0125, L / 2 - 0.0125):
        b.box((0.025, D, 0.12), (x, 0, H + 0.06), "wood")
    for i in range(4):
        y = -D / 2 + 0.09 + i * (D - 0.18) / 3
        b.box((L - 0.14, 0.1, 0.022), (0, y, 0.28), "wood")
    # Iron rails under the top, end to end.
    for y in (-D / 2 + 0.05, D / 2 - 0.05):
        b.box((L - 0.1, 0.02, 0.06), (0, y, H - 0.07), "iron")
    return b.finish(6.0, smooth=False)


def staging():
    b = Builder("Staging", ["wood", "iron"])
    L, D = 2.4, 1.1
    steps = [(0.5, -D / 2 + 0.18), (0.85, 0.0), (1.2, D / 2 - 0.18)]
    for x in (-L / 2 + 0.03, 0.0, L / 2 - 0.03):
        # An iron end frame: a front leg, a back leg, a raking member and a rail under each step.
        b.bar((x, -D / 2 + 0.02, 0.0), (x, -D / 2 + 0.02, 0.5), 0.04, 0.04, "iron")
        b.bar((x, D / 2 - 0.02, 0.0), (x, D / 2 - 0.02, 1.2), 0.04, 0.04, "iron")
        b.bar((x, -D / 2 + 0.02, 0.5), (x, D / 2 - 0.02, 1.2), 0.03, 0.03, "iron", up=(1, 0, 0))
        for z, y in steps:
            b.bar((x, y - 0.18, z - 0.03), (x, y + 0.18, z - 0.03), 0.03, 0.03, "iron", up=(1, 0, 0))
        b.bar((x, -D / 2 + 0.02, 0.12), (x, D / 2 - 0.02, 0.12), 0.025, 0.025, "iron", up=(1, 0, 0))
    for z, y in steps:
        for k in range(3):
            b.box((L, 0.1, 0.025), (0, y - 0.12 + k * 0.12, z), "wood")
    return b.finish(8.0, smooth=False)


# --- the basket and the lanterns ---------------------------------------------------------------

def basket():
    b = Builder("Basket", ["iron", "moss"])
    r = 0.22
    rim = 0.55
    c = Vector((0, 0, -rim))
    for k in range(8):
        a = 2 * math.pi * k / 8
        pts = [c + Vector((math.cos(a) * r * math.cos(t), math.sin(a) * r * math.cos(t), -r * math.sin(t) * 0.8))
               for t in [math.pi * 0.5 * i / 8 for i in range(9)]]
        b.tube(pts, [0.005] * 9, 4, "iron")
    for t, rr in [(0.0, r), (0.5, r * math.cos(0.5))]:
        pts = [c + Vector((math.cos(a) * rr, math.sin(a) * rr, -r * math.sin(t) * 0.8))
               for a in [2 * math.pi * i / 24 for i in range(25)]]
        b.tube(pts, [0.006] * 25, 4, "iron", closed_end=False)
    moss = []
    for i in range(7):
        t = math.pi * 0.5 * i / 6
        moss.append((r * 0.97 * math.cos(t), -rim - r * 0.8 * 0.97 * math.sin(t)))
    moss.append((0.0, -rim - r * 0.8 * 0.97))
    b.lathe(moss, "moss", 24)
    for k in range(3):
        a = 2 * math.pi * k / 3 + 0.3
        b.tube([c + Vector((math.cos(a) * r, math.sin(a) * r, 0.0)), Vector((0, 0, -0.03))], [0.004, 0.004], 4, "iron")
    b.tube(ring_points((0, 0, -0.015), 0.018, 10), [0.004] * 11, 4, "iron", closed_end=False)
    return b.finish(10.0, angle=60)


def lantern_into(b, top, scale):
    """A hexagonal lantern hung from `top`: ring, crown, cap, glass body, base and drop."""
    def at(r, z):
        return (r * scale, top.z - z * scale)
    t = top
    b.tube([t + Vector((0, 0, 0)) + Vector((math.cos(a) * 0.03 * scale, 0, math.sin(a) * 0.03 * scale - 0.03 * scale))
            for a in [2 * math.pi * i / 12 for i in range(13)]], [0.006 * scale] * 13, 4, "iron", closed_end=False)
    crown = [(0.0, 0.06), (0.025, 0.06), (0.03, 0.1), (0.05, 0.12), (0.17, 0.2), (0.19, 0.22), (0.15, 0.23),
             (0.15, 0.24)]
    rings = b.lathe([(at(r, z)[0], at(r, z)[1]) for r, z in crown], "iron", 6, phase=math.pi / 6)
    for r, z in []:
        pass
    # The glass body, six panes between six iron corner posts.
    top_r, bot_r = 0.15, 0.11
    z0, z1 = 0.24, 0.6
    for k in range(6):
        a0 = math.pi / 6 + 2 * math.pi * k / 6
        a1 = math.pi / 6 + 2 * math.pi * (k + 1) / 6
        p = [Vector((math.cos(a0) * top_r, math.sin(a0) * top_r, -z0)), Vector((math.cos(a1) * top_r, math.sin(a1) * top_r, -z0)),
             Vector((math.cos(a1) * bot_r, math.sin(a1) * bot_r, -z1)), Vector((math.cos(a0) * bot_r, math.sin(a0) * bot_r, -z1))]
        p = [t + q * scale for q in p]
        b.face([p[0], p[3], p[2], p[1]], "glass")
        b.bar(p[0], p[3], 0.016 * scale, 0.016 * scale, "iron")
    base = [(bot_r, z1), (0.125, z1 + 0.01), (0.12, z1 + 0.04), (0.06, z1 + 0.08), (0.03, z1 + 0.14), (0.0, z1 + 0.16)]
    b.lathe([(at(r, z)[0], at(r, z)[1]) for r, z in base], "brass", 6, phase=math.pi / 6)
    # The lamp inside: a glass globe of its own, which the venue lights.
    b.blob(t + Vector((0, 0, -0.43 * scale)), 0.05 * scale, 1.3, 1, "glass", subdiv=1, rough=0.0)


def lantern():
    b = Builder("Lantern", ["iron", "glass", "brass"])
    lantern_into(b, Vector((0, 0, 0)), 1.0)
    return b.finish(11.0, angle=30)


def lamp_post():
    b = Builder("LampPost", ["iron", "glass", "brass"])
    b.lathe([(0.0, 0.0), (0.16, 0.0), (0.16, 0.08), (0.12, 0.12), (0.12, 0.4), (0.09, 0.46), (0.08, 0.5)], "iron", 12)
    shaft = [(0.07 - 0.025 * k / 8, 0.5 + 2.2 * k / 8) for k in range(9)]
    b.lathe(shaft, "iron", 16, scallop=lambda i, a: 1.0 - 0.08 * (0.5 + 0.5 * math.cos(a * 8)))
    b.lathe([(0.045, 2.7), (0.07, 2.74), (0.05, 2.78), (0.06, 2.84), (0.0, 2.86)], "iron", 12)
    b.bar((-0.28, 0, 2.55), (0.28, 0, 2.55), 0.025, 0.025, "iron")
    for x in (-0.28, 0.28):
        b.blob((x, 0, 2.55), 0.025, 1.0, 2, "iron", subdiv=1, rough=0.0)
    # The lantern stands on the post rather than hanging: a short collar, then the body.
    lantern_into(b, Vector((0, 0, 3.6)), 1.25)
    return b.finish(12.0, angle=30)


# --- the garden ---------------------------------------------------------------------------------

def urn():
    b = Builder("Urn", ["stone"])
    b.box((0.5, 0.5, 0.06), (0, 0, 0.03), "stone")
    b.box((0.4, 0.4, 0.5), (0, 0, 0.31), "stone")
    b.box((0.52, 0.52, 0.06), (0, 0, 0.59), "stone")
    prof = [(0.0, 0.62), (0.14, 0.62), (0.14, 0.66), (0.08, 0.7), (0.07, 0.76), (0.12, 0.8), (0.26, 0.88),
            (0.33, 1.0), (0.34, 1.12), (0.38, 1.18), (0.38, 1.24), (0.33, 1.25), (0.3, 1.2), (0.0, 1.18)]
    b.lathe(prof, "stone", 28)
    return b.finish(13.0, angle=45)


def watering_can():
    b = Builder("WateringCan", ["zinc"])
    body = [(0.0, 0.0), (0.11, 0.0), (0.115, 0.02), (0.11, 0.2), (0.09, 0.24), (0.04, 0.26), (0.0, 0.26)]
    b.lathe(body, "zinc", 24)
    spout = [Vector((0.09, 0, 0.04)), Vector((0.2, 0, 0.14)), Vector((0.3, 0, 0.25)), Vector((0.36, 0, 0.32))]
    b.tube(spout, [0.025, 0.018, 0.014, 0.012], 8, "zinc")
    b.tube([Vector((0.36, 0, 0.32)), Vector((0.39, 0, 0.35))], [0.02, 0.035], 10, "zinc")
    handle = [Vector((-0.1, 0, 0.08)), Vector((-0.16, 0, 0.16)), Vector((-0.13, 0, 0.3)), Vector((-0.02, 0, 0.36)),
              Vector((0.06, 0, 0.28))]
    b.tube(handle, [0.01] * 5, 6, "zinc")
    return b.finish(14.0, angle=50)


def tree(name, crown_at, crown_r, squash, blobs, seed, x):
    random.seed(seed)
    b = Builder(name, ["bark", "canopy"])
    trunk = [Vector((0, 0, 0)), Vector((0.0, 0.0, crown_at * 0.5)), Vector((0.01, 0, crown_at))]
    b.tube(trunk, [0.04, 0.03, 0.022], 7, "bark")
    # Three limbs out of the fork into the crown.
    for k in range(3):
        a = 2 * math.pi * k / 3 + 0.4
        tip = Vector((math.cos(a) * crown_r * 0.45, math.sin(a) * crown_r * 0.45, crown_at + crown_r * squash * 0.6))
        b.tube([Vector((0.01, 0, crown_at)), tip], [0.02, 0.008], 5, "bark")
    centre = Vector((0, 0, crown_at + crown_r * squash * 0.75))
    for k in range(blobs):
        a = 2 * math.pi * k / blobs + random.uniform(-0.3, 0.3)
        off = Vector((math.cos(a) * crown_r * 0.5, math.sin(a) * crown_r * 0.5,
                      random.uniform(-0.25, 0.35) * crown_r * squash))
        b.blob(centre + off, crown_r * random.uniform(0.5, 0.65), squash, seed + k, "canopy", subdiv=2, rough=0.35)
    b.blob(centre + Vector((0, 0, crown_r * squash * 0.35)), crown_r * 0.62, squash, seed + 9, "canopy", subdiv=2,
           rough=0.35)
    return b.finish(x, angle=70)


def yew():
    b = Builder("Yew", ["yew", "bark"])
    b.tube([Vector((0, 0, 0)), Vector((0, 0, 0.08))], [0.05, 0.05], 6, "bark")
    prof = []
    for k in range(13):
        t = k / 12
        prof.append(((0.28 * (1 - t) ** 0.9 + 0.005) * (1.0 if k else 0.85), 0.05 + 0.95 * t))
    prof = [(0.0, 0.05)] + prof
    b.lathe(prof, "yew", 16, scallop=lambda i, a: 1.0 + 0.04 * noise.noise(Vector((math.cos(a) * 3, math.sin(a) * 3, i * 0.7))))
    return b.finish(17.0, angle=60)


column()
spandrel()
fountain()
pot()
bench()
staging()
basket()
lantern()
lamp_post()
urn()
watering_can()
tree("TreeRound", 0.35, 0.42, 0.85, 6, 21, 15.0)
tree("TreeTall", 0.3, 0.3, 1.5, 5, 33, 16.0)
yew()

bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/greenhouse_props.glb"), export_format="GLB")
print("wrote greenhouse_props.glb")
