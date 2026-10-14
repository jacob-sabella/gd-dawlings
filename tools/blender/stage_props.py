# Builds the festival stage's rig and writes assets/models/stage_props.glb.
#
#     blender --background --python tools/blender/stage_props.py
#
# One file, several objects, each placed by StageVenue by name (Blender +Y is Godot -Z, toward
# the audience; Blender +Z is Godot +Y):
#   Truss        one 2 m length of 0.29 m box truss along X: four chords, ladder rungs and a
#                diagonal on every face of every bay, its origin in its middle
#   LineArray    a hung line array: a flying bumper and twelve boxes splayed into a J, their
#                grilles toward Blender +Y; origin at the top of the bumper, 4.5 m to the bottom
#   HeadBase, HeadYoke, Head
#                a moving-head fixture hung under a truss, in three parts so it can pan and tilt:
#                the base (origin at its clamp on the truss), the yoke (origin on the pan axis at
#                the base's underside, 0.2 m below the clamp), the head (origin on the tilt axis,
#                0.31 m below the yoke's; its lens toward Blender -Z, straight down at rest)
#   Barricade    one 1 m section of crowd barrier: a front panel to the crowd (Blender +Y), a
#                foot plate the crowd stands on, braces and a padded top rail; origin on the
#                ground under its middle
#   Wedge        a floor monitor, its sloped grille toward Blender -Y (back toward the band)
#   Sub          a subwoofer box, grille toward Blender +Y, 1.2 x 0.6 x 0.75 m
#   RoadCase     a 1.2 x 0.6 x 0.8 m flight case on casters: ply skin, aluminium edges, steel
#                ball corners, recessed handles; origin on the floor
#   Cab, AmpHead a 4x12 guitar cabinet and the amp head on it, grille toward Blender +Y
#   Person0..2   a crowd silhouette, 1.72 m: arms down, one arm up with a phone, both arms up
#   Seat         one arena seat: a folding pan and a back on a standard, facing Blender +Y
# Every origin is on the floor unless said. Materials "cab", "grille", "alu", "steel", "lens",
# "pad", "case", "rubber", "body", "seat", "ply", "panel".

import math
import os

import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
NAMES = ["cab", "grille", "alu", "steel", "lens", "pad", "case", "rubber", "body", "seat", "ply", "panel"]
mats = {n: bpy.data.materials.new(n) for n in NAMES}


class Part:
    """One object being built: a bmesh and the materials it uses."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.used = []

    def _k(self, mat):
        if mat not in self.used:
            self.used.append(mat)
        return self.used.index(mat)

    def _paint(self, verts, mat):
        k = self._k(mat)
        faces = set()
        for v in verts:
            faces.update(v.link_faces)
        for f in faces:
            f.material_index = k

    def box(self, size, centre, mat, rot=None):
        m = Matrix.Translation(Vector(centre))
        if rot is not None:
            m = m @ rot.to_4x4()
        m = m @ Matrix.Diagonal(Vector((size[0], size[1], size[2], 1.0)))
        out = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)
        self._paint(out["verts"], mat)

    def cyl(self, radius, depth, centre, mat, axis="Z", sides=12, radius2=None, rot=None):
        r = {"Z": Matrix.Identity(3), "X": Matrix.Rotation(math.pi / 2, 3, "Y"),
             "Y": Matrix.Rotation(math.pi / 2, 3, "X")}[axis]
        if rot is not None:
            r = rot @ r
        m = Matrix.Translation(Vector(centre)) @ r.to_4x4()
        out = bmesh.ops.create_cone(self.bm, cap_ends=True, segments=sides, radius1=radius,
                                    radius2=radius if radius2 is None else radius2, depth=depth, matrix=m)
        self._paint(out["verts"], mat)

    def rod(self, a, b, radius, mat, sides=6):
        """A round bar from a to b."""
        a = Vector(a)
        b = Vector(b)
        d = b - a
        rot = d.to_track_quat("Z", "Y").to_matrix()
        m = Matrix.Translation((a + b) * 0.5) @ rot.to_4x4()
        out = bmesh.ops.create_cone(self.bm, cap_ends=False, segments=sides, radius1=radius, radius2=radius,
                                    depth=d.length, matrix=m)
        self._paint(out["verts"], mat)

    def ico(self, radius, centre, mat, subdiv=1):
        out = bmesh.ops.create_icosphere(self.bm, subdivisions=subdiv, radius=radius,
                                         matrix=Matrix.Translation(Vector(centre)))
        self._paint(out["verts"], mat)

    def poly(self, verts, faces, mat):
        vs = [self.bm.verts.new(v) for v in verts]
        k = self._k(mat)
        for f in faces:
            face = self.bm.faces.new([vs[i] for i in f])
            face.material_index = k

    def finish(self, park_x):
        me = bpy.data.meshes.new(self.name)
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-6)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.used:
            me.materials.append(mats[m])
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.collection.objects.link(ob)
        for p in me.polygons:
            p.use_smooth = False
        # Parked apart so they do not sit in one another in the file; Godot takes each mesh
        # in its own space.
        ob.location.x = park_x
        print("%s: %d faces, %s" % (self.name, len(me.polygons), self.used))
        return ob


park = [0.0]


def done(part):
    park[0] += 6.0
    return part.finish(park[0])


# --- truss -----------------------------------------------------------------------------------

def truss():
    p = Part("Truss")
    L = 2.0
    H = 0.145  # half the chord spacing
    R = 0.024
    for y in (-H, H):
        for z in (-H, H):
            p.rod((-L / 2, y, z), (L / 2, y, z), R, "alu", sides=8)
    bays = 4
    bay = L / bays
    for i in range(bays + 1):
        x = -L / 2 + i * bay
        x = min(max(x, -L / 2 + 0.03), L / 2 - 0.03)
        # The ladder rungs round each station.
        for a, b in (((x, -H, -H), (x, H, -H)), ((x, -H, H), (x, H, H)),
                     ((x, -H, -H), (x, -H, H)), ((x, H, -H), (x, H, H))):
            p.rod(a, b, 0.009, "alu", sides=5)
    for i in range(bays):
        x0 = -L / 2 + i * bay + 0.03
        x1 = -L / 2 + (i + 1) * bay - 0.03
        flip = i % 2 == 0
        a, b = (x0, x1) if flip else (x1, x0)
        # One diagonal on each face, zig-zagging bay to bay.
        p.rod((a, -H, -H), (b, H, -H), 0.009, "alu", sides=5)
        p.rod((a, -H, H), (b, H, H), 0.009, "alu", sides=5)
        p.rod((a, -H, -H), (b, -H, H), 0.009, "alu", sides=5)
        p.rod((a, H, -H), (b, H, H), 0.009, "alu", sides=5)
    # The fork ends, where one length couples to the next.
    for x in (-L / 2 + 0.012, L / 2 - 0.012):
        for y in (-H, H):
            for z in (-H, H):
                p.cyl(0.032, 0.024, (x, y, z), "steel", axis="X", sides=8)
    done(p)


# --- line array ------------------------------------------------------------------------------

def line_array():
    p = Part("LineArray")
    W = 1.1
    DEEP = 0.5
    TALL = 0.36
    # The bumper: a flat frame with two pick-up points.
    p.box((W + 0.12, DEEP + 0.1, 0.07), (0, -DEEP / 2 + 0.02, -0.035), "steel")
    for x in (-0.35, 0.35):
        p.box((0.06, 0.12, 0.12), (x, -DEEP / 2, 0.06), "steel")
    # Splay between boxes, degrees: straight at the top for the far crowd, curling to the front.
    splay = [0, 0.5, 0.5, 1, 1, 1.5, 2, 3, 4, 5, 6, 8]
    pivot = Vector((0, 0.0, -0.075))
    angle = 0.0
    for i, s in enumerate(splay):
        angle += s
        rot = Matrix.Rotation(math.radians(-angle), 3, "X")

        def at(local):
            return pivot + rot @ Vector(local)
        # The box, a little narrower at the back as real ones are: a body and a grille.
        p.box((W, DEEP - 0.03, TALL - 0.012), at((0, -DEEP / 2 - 0.015, -TALL / 2)), "cab", rot)
        p.box((W - 0.06, 0.03, TALL - 0.05), at((0, -0.012, -TALL / 2)), "grille", rot)
        # The rigging plates down each side.
        for x in (-W / 2 - 0.012, W / 2 + 0.012):
            p.box((0.024, 0.08, TALL + 0.02), at((x, -0.06, -TALL / 2)), "steel", rot)
            p.box((0.024, 0.08, TALL + 0.02), at((x, -DEEP + 0.06, -TALL / 2)), "steel", rot)
        pivot = at((0, 0, -TALL))
    done(p)


# --- moving head -----------------------------------------------------------------------------

def moving_head():
    base = Part("HeadBase")
    # The clamp round the bottom chord, then the base box hanging under it.
    base.cyl(0.035, 0.08, (0, 0, -0.01), "steel", axis="Y", sides=8)
    base.box((0.04, 0.04, 0.06), (0, 0, -0.06), "steel")
    base.box((0.42, 0.3, 0.11), (0, 0, -0.145), "cab")
    base.box((0.12, 0.012, 0.05), (0.1, 0.152, -0.145), "lens")  # the little display
    done(base)
    yoke = Part("HeadYoke")
    # The pan bearing, the cross bar, and the two arms down either side of the head.
    yoke.cyl(0.1, 0.03, (0, 0, -0.015), "steel", sides=16)
    yoke.box((0.44, 0.14, 0.06), (0, 0, -0.06), "cab")
    for x in (-0.2, 0.2):
        yoke.box((0.05, 0.14, 0.3), (x, 0, -0.22), "cab")
    done(yoke)
    head = Part("Head")
    head.cyl(0.14, 0.34, (0, 0, 0.02), "cab", sides=20, radius2=0.11)
    # The front lens, the bezel round it, and the tilt hubs.
    head.cyl(0.15, 0.03, (0, 0, -0.15), "cab", sides=20)
    head.cyl(0.115, 0.012, (0, 0, -0.168), "lens", sides=20)
    for x in (-0.16, 0.16):
        head.cyl(0.05, 0.04, (x, 0, 0), "steel", axis="X", sides=10)
    # Cooling fins at the back.
    for z in (0.12, 0.15, 0.18):
        head.cyl(0.105, 0.01, (0, 0, z), "steel", sides=20)
    done(head)


# --- crowd barrier -----------------------------------------------------------------------------

def barricade():
    p = Part("Barricade")
    L = 1.0
    T = 1.22
    # The front face to the crowd: a sheet of aluminium between two posts.
    p.box((L - 0.02, 0.02, T - 0.3), (0, 0.05, 0.15 + (T - 0.3) / 2), "alu")
    for x in (-L / 2 + 0.03, L / 2 - 0.03):
        p.box((0.05, 0.05, T), (x, 0.05, T / 2), "steel")
        # A raking brace behind, back to the stage-side foot.
        p.rod((x, 0.05, T - 0.15), (x, -0.85, 0.02), 0.022, "steel", sides=6)
        p.box((0.06, 0.95, 0.04), (x, -0.4, 0.02), "steel")
    # The foot plate the crowd stands on (its own weight keeps the barrier where it is).
    p.box((L - 0.004, 0.9, 0.025), (0, 0.5, 0.0125), "alu")
    # The top: a padded roll over a rail.
    p.cyl(0.05, L - 0.02, (0, 0.05, T + 0.02), "pad", axis="X", sides=10)
    done(p)


# --- monitors and speakers ----------------------------------------------------------------------

def wedge():
    p = Part("Wedge")
    W = 0.62
    # Side profile (y, z): the back low at Blender +Y, the sloped face rising toward -Y.
    prof = [(0.22, 0.0), (-0.28, 0.0), (-0.28, 0.12), (0.02, 0.36), (0.22, 0.36)]
    verts = [(x, y, z) for x in (-W / 2, W / 2) for (y, z) in prof]
    n = len(prof)
    faces = [list(range(n))[::-1], [n + i for i in range(n)]]
    for i in range(n):
        j = (i + 1) % n
        faces.append([i, j, n + j, n + i])
    p.poly(verts, faces, "cab")
    # The grille along the sloped face, a hair proud of it.
    a = Vector((0, -0.28, 0.12))
    b = Vector((0, 0.02, 0.36))
    mid = (a + b) / 2
    slope = math.atan2(b.z - a.z, b.y - a.y)
    rot = Matrix.Rotation(slope, 3, "X")
    normal = rot @ Vector((0, 0, 1))
    p.box((W - 0.06, (b - a).length - 0.04, 0.012), mid + normal * 0.004, "grille", rot)
    done(p)


def sub():
    p = Part("Sub")
    p.box((1.2, 0.75, 0.6), (0, 0, 0.3), "cab")
    p.box((1.12, 0.02, 0.52), (0, 0.38, 0.3), "grille")
    for x in (-0.62, 0.62):
        p.box((0.04, 0.2, 0.06), (x, 0, 0.42), "steel")
    done(p)


def cab():
    p = Part("Cab")
    p.box((0.76, 0.36, 0.76), (0, 0, 0.38), "cab")
    p.box((0.68, 0.02, 0.68), (0, 0.185, 0.38), "grille")
    for x in (-0.39, 0.39):
        for y in (-0.19, 0.19):
            for z in (0.02, 0.74):
                p.box((0.04, 0.04, 0.04), (x, y, z), "steel")
    done(p)
    h = Part("AmpHead")
    h.box((0.74, 0.3, 0.26), (0, 0, 0.13), "cab")
    h.box((0.66, 0.012, 0.09), (0, 0.155, 0.16), "steel")
    for i in range(8):
        h.cyl(0.012, 0.02, (-0.26 + i * 0.07, 0.165, 0.16), "panel", axis="Y", sides=8)
    h.box((0.03, 0.03, 0.006), (0.28, 0.162, 0.16), "lens")
    h.box((0.2, 0.03, 0.03), (0, 0, 0.27), "rubber")
    done(h)


def road_case():
    p = Part("RoadCase")
    W, D, T = 1.2, 0.6, 0.72
    lift = 0.09
    p.box((W - 0.01, D - 0.01, T - 0.01), (0, 0, lift + T / 2), "case")
    # Aluminium extrusion along all twelve edges, a hair proud of the skin.
    e = 0.03
    for y in (-D / 2, D / 2):
        for z in (lift, lift + T):
            p.box((W - 0.04, e, e), (0, y, z), "alu")
    for x in (-W / 2, W / 2):
        for z in (lift, lift + T):
            p.box((e, D - 0.04, e), (x, 0, z), "alu")
        for y in (-D / 2, D / 2):
            p.box((e, e, T - 0.04), (x, y, lift + T / 2), "alu")
    # The lid's seam: a band of extrusion round it a quarter of the way down.
    seam = lift + T * 0.78
    p.box((W + 0.006, D + 0.006, 0.02), (0, 0, seam), "alu")
    for x in (-W / 2, W / 2):
        for y in (-D / 2, D / 2):
            for z in (lift, lift + T):
                p.ico(0.03, (x, y, z), "steel", subdiv=1)
    # Recessed handles on the ends, butterfly latches on the long sides.
    for x in (-W / 2 - 0.006, W / 2 + 0.006):
        p.box((0.014, 0.2, 0.08), (x, 0, lift + T * 0.55), "steel")
    for x in (-0.35, 0.35):
        for y in (-D / 2 - 0.006, D / 2 + 0.006):
            p.box((0.07, 0.014, 0.07), (x, y, seam), "steel")
    # Casters.
    for x in (-W / 2 + 0.1, W / 2 - 0.1):
        for y in (-D / 2 + 0.1, D / 2 - 0.1):
            p.box((0.07, 0.07, 0.02), (x, y, lift - 0.01), "steel")
            p.cyl(0.035, 0.03, (x, y, 0.036), "rubber", axis="X", sides=10)
    done(p)


# --- people and seats ----------------------------------------------------------------------------

def person(name, arms):
    p = Part(name)
    # In a crowd only the silhouette reads, and a body is wider than it is deep: so every part is
    # a low prism squashed front to back. Legs, hips, a torso widening to the shoulders, a neck,
    # a head; the arms in the pose asked for.
    flat = Matrix.Diagonal(Vector((1.0, 0.62, 1.0)))
    for x in (-0.09, 0.09):
        p.cyl(0.075, 0.86, (x, 0, 0.43), "body", sides=6, radius2=0.062, rot=flat)
    p.cyl(0.17, 0.2, (0, 0, 0.92), "body", sides=8, radius2=0.165, rot=flat)
    p.cyl(0.165, 0.46, (0, 0, 1.25), "body", sides=8, radius2=0.225, rot=flat)
    # Rounded shoulders: a short squat prism over the top of the torso.
    p.cyl(0.225, 0.06, (0, 0, 1.51), "body", sides=8, radius2=0.16, rot=flat)
    p.cyl(0.05, 0.08, (0, 0, 1.56), "body", sides=6)
    p.ico(0.1, (0, 0.0, 1.67), "body", subdiv=1)
    sh = 1.47
    for side, pose in zip((-1, 1), arms):
        s = Vector((side * 0.2, 0, sh))
        if pose == "down":
            elbow = Vector((side * 0.25, 0.02, 1.15))
            p.rod(s, elbow, 0.045, "body", sides=5)
            p.rod(elbow, (side * 0.25, 0.08, 0.86), 0.04, "body", sides=5)
        elif pose == "up":
            elbow = Vector((side * 0.3, 0.04, 1.8))
            p.rod(s, elbow, 0.045, "body", sides=5)
            p.rod(elbow, (side * 0.27, 0.08, 2.12), 0.04, "body", sides=5)
        else:  # "phone": forearm raised in front, the phone held up
            elbow = Vector((side * 0.28, 0.18, 1.55))
            hand = Vector((side * 0.2, 0.3, 1.88))
            p.rod(s, elbow, 0.045, "body", sides=5)
            p.rod(elbow, hand, 0.04, "body", sides=5)
    done(p)


def seat():
    p = Part("Seat")
    p.box((0.46, 0.4, 0.05), (0, 0.05, 0.44), "seat")
    rot = Matrix.Rotation(math.radians(-12), 3, "X")
    p.box((0.46, 0.05, 0.42), (0, -0.17, 0.72), "seat", rot)
    p.box((0.05, 0.3, 0.42), (-0.25, -0.05, 0.21), "steel")
    done(p)


truss()
line_array()
moving_head()
barricade()
wedge()
sub()
cab()
road_case()
person("Person0", ("down", "down"))
person("Person1", ("down", "phone"))
person("Person2", ("up", "up"))
seat()

bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/stage_props.glb"), export_format="GLB")
print("wrote stage_props.glb")
