# Builds the desert's rock and writes assets/models/desert_rocks.glb.
#
#     blender --background --python tools/blender/desert_rocks.py
#
# Sandstone, in the shapes the desert wears it into. Origin at the foot of each, in the middle:
#   boulder_a, boulder_b, boulder_c   rounded blocks a metre or two across, fractured flat on a
#                                     face or two and bedded into the sand (their feet below 0).
#   butte         a butte, one unit across and one tall (the venue scales it to a mesa or a
#                 tower): a cap rock with a lip, cliffs stepped in ledges where the softer beds
#                 between the hard ones weathered back, and a talus apron at the foot.
#   canyon_wall   one face of a canyon, 30 m along Godot x, 46 m tall, its face toward Godot +Z
#                 (Blender -Y) with the rim and the mesa top going back from it: the face
#                 stepped in ledges like the butte, undercut in alcoves near its foot, scalloped
#                 along its length. Laid end to end round the camp by the venue.
# One material, "rock": DesertVenue's strata shader bands it by height.

import math
import os

import bpy
import bmesh
from mathutils import Vector, noise

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
rock = bpy.data.materials.new("rock")


def new_object(name):
    me = bpy.data.meshes.new(name)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    me.materials.append(rock)
    return ob, bmesh.new()


def finish(ob, bm, x, smooth=False):
    bm.normal_update()
    bm.to_mesh(ob.data)
    bm.free()
    for p in ob.data.polygons:
        p.use_smooth = smooth
    ob.location.x = x
    print("%s: %d faces, dims %s" % (ob.name, len(ob.data.polygons), [round(d, 2) for d in ob.dimensions]))


def ledges(h, beds, hard=0.7):
    """How far a cliff has weathered back at height h (0..1): the soft beds between hard ones go
    back further, so the face steps."""
    u = h * beds
    f = u - math.floor(u)
    # Hard at the top of each bed, soft below it; the lip between worn round.
    return 1.0 - hard * (0.5 - 0.5 * math.cos(math.tau * f ** 0.7)) ** 1.4


# --- boulders -----------------------------------------------------------------------------------
for name, seed, size, cut in (("boulder_a", 1, (1.0, 0.8, 0.65), (0.4, 0.2)), ("boulder_b", 2, (1.4, 1.0, 0.7), (-0.3, 0.3)),
                              ("boulder_c", 3, (0.7, 0.65, 0.9), (0.1, -0.5))):
    ob, bm = new_object(name)
    bmesh.ops.create_icosphere(bm, subdivisions=4, radius=1.0)
    plane = Vector((cut[0], cut[1], 0.4)).normalized()
    for v in bm.verts:
        n = noise.fractal(v.co * 1.3 + Vector((seed * 5.0, 0, 0)), 0.5, 2.0, 3)
        co = v.co * (1.0 + 0.18 * n)
        # A fractured face: anything past the plane is pressed back onto it.
        d = co.dot(plane) - 0.62
        if d > 0:
            co -= plane * d * 0.9
        co = Vector((co.x * size[0], co.y * size[1], co.z * size[2]))
        # Bedded: the bottom flattened, and sunk a little.
        if co.z < -size[2] * 0.5:
            co.z = -size[2] * 0.5 + (co.z + size[2] * 0.5) * 0.2
        v.co = co + Vector((0, 0, size[2] * 0.42))
    finish(ob, bm, seed * 4.0, smooth=True)

# --- butte --------------------------------------------------------------------------------------
ob, bm = new_object("butte")
SEG, ROWS = 64, 72
rings = []
for j in range(ROWS + 1):
    h = j / ROWS
    ring = []
    for k in range(SEG):
        a = math.tau * k / SEG
        wobble = 1.0 + 0.16 * noise.noise(Vector((math.cos(a) * 1.4, math.sin(a) * 1.4, h * 0.6)))
        if h < 0.18:
            # The talus apron: a slope of fallen rock out to the foot.
            r = 0.5 + 0.45 * (1.0 - h / 0.18) ** 1.5
        else:
            r = 0.42 + 0.08 * ledges((h - 0.18) / 0.82, 4)
        ring.append(bm.verts.new((math.cos(a) * r * 0.5 * wobble, math.sin(a) * r * 0.5 * wobble, h)))
    rings.append(ring)
for a, b in zip(rings, rings[1:]):
    for k in range(SEG):
        bm.faces.new((a[k], a[(k + 1) % SEG], b[(k + 1) % SEG], b[k]))
cap = bm.verts.new((0, 0, 1.01))
for k in range(SEG):
    bm.faces.new((rings[-1][k], rings[-1][(k + 1) % SEG], cap))
finish(ob, bm, 14.0, smooth=True)

# --- canyon wall --------------------------------------------------------------------------------
# Eroded, not stacked: the ledges are where hard beds stand out over soft ones, but the wind and
# the water have rounded every lip, the beds thicken and thin and wander up and down along the
# wall, and the whole face is worn by noise at three scales -- the bays and buttresses, the
# rounded bulges between them, the pitting. Fine enough (and smooth-shaded) that no facet shows.
ob, bm = new_object("canyon_wall")
LONG, TALL, BACK = 30.0, 46.0, 14.0
NU, NV = 96, 150


def soft_ledges(u, hard):
    """How far the face has weathered back at bed-coordinate u: a rounded lip at the top of each
    bed, a smooth hollow under it (the soft bed), easing back out to the next lip."""
    f = u - math.floor(u)
    # Rounded hollow: a raised cosine, skewed so the overhang is under the lip.
    g = f ** 0.7
    return hard * (0.5 - 0.5 * math.cos(math.tau * g)) ** 1.4


face = []
for i in range(NU + 1):
    x = -LONG * 0.5 + LONG * i / NU
    col = []
    for j in range(NV + 1):
        h = j / NV
        z = TALL * h
        # The beds wander up and down along the wall and thicken and thin.
        u = h * 9.0 + 0.45 * noise.noise(Vector((x * 0.045, 3.1, 0.0))) + 0.25 * math.sin(x * 0.11 + h * 4.0)
        # Ledges stand out more in some beds than others.
        hard = 0.9 + 0.7 * noise.noise(Vector((math.floor(u) * 1.7, 0.4, 2.0)))
        step = 1.3 * soft_ledges(u, hard)
        lean = 2.5 * h
        # Bays and buttresses along the wall, then rounded bulges, then the pitting.
        scallop = 1.8 * math.sin(x * 0.42 + 1.3 * math.sin(x * 0.13)) * (0.6 + 0.4 * h)
        p = Vector((x * 0.09, z * 0.06, 0.0))
        n = noise.fractal(p, 0.55, 2.1, 4) * 1.4
        bulge = noise.fractal(Vector((x * 0.3, z * 0.25, 5.0)), 0.5, 2.0, 3) * 0.45
        pit = noise.noise(Vector((x * 1.4, z * 1.1, 9.0))) * 0.08
        # Alcoves undercut near the foot, where seeps have eaten in: rounded hollows.
        alcove = 2.4 * max(0.0, math.sin(x * 0.31 + 0.6)) ** 3 * math.exp(-((h - 0.12) / 0.07) ** 2)
        y = step + lean + scallop + n + bulge + pit + alcove
        # Toward either end the face eases onto one shared profile, so walls laid end to end meet
        # without a seam: the same ledges at the same depths, whatever each did in between.
        seam_u = h * 9.0
        seam = 1.3 * soft_ledges(seam_u, 1.2) + lean + 0.6
        edge = min(x + LONG * 0.5, LONG * 0.5 - x)
        w = max(0.0, 1.0 - edge / 4.0)
        w = w * w * (3.0 - 2.0 * w)
        y = y + (seam - y) * w
        # The foot runs a couple of metres into the sand.
        col.append(bm.verts.new((x, y, z - 2.0)))
    face.append(col)
for i in range(NU):
    for j in range(NV):
        bm.faces.new((face[i][j], face[i + 1][j], face[i + 1][j + 1], face[i][j + 1]))
# The rim and the mesa top going back from it, a little rough.
top = []
for i in range(NU + 1):
    x = -LONG * 0.5 + LONG * i / NU
    rim = face[i][NV]
    row = [rim]
    for d in (1.5, 5.0, BACK):
        row.append(bm.verts.new((x, rim.co.y + d, TALL - 2.0 + 0.4 * noise.noise(Vector((x * 0.2, d * 0.3, 0.0))))))
    top.append(row)
for i in range(NU):
    for k in range(3):
        bm.faces.new((top[i][k], top[i][k + 1], top[i + 1][k + 1], top[i + 1][k]))
# Faces toward Blender -Y (where the camp is) after the fact: flip if the winding came out the
# other way.
bm.normal_update()
mid = face[NU // 2][NV // 2]
f = mid.link_faces[0]
if f.normal.y > 0:
    for f in bm.faces:
        f.normal_flip()
finish(ob, bm, 30.0, smooth=True)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/desert_rocks.glb"), export_format="GLB",
                          use_selection=True)
print("wrote desert_rocks.glb")
