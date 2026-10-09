# Builds one stalk of giant kelp and writes assets/models/kelp.glb.
#
#     blender --background --python tools/blender/kelp.py
#
# The kelp forest outside the underwater dome: a holdfast gripping the sand, one stipe rising
# about 7 m with a lazy S in it, and blades all the way up, each on a small gas float, hanging
# off alternate sides and turning round the stalk as it climbs. The dome sways it in a vertex
# shader by height, so the holdfast stays put and the top moves most. Materials "stipe" and
# "blade". Blender Z is up (Godot +Y); the origin is on the sand under the holdfast.

import math
import os
import random

import bpy
import bmesh

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
random.seed(7)
stipe_mat = bpy.data.materials.new("stipe")
blade_mat = bpy.data.materials.new("blade")

HEIGHT = 7.2
RINGS = 18
SIDES = 6


def centre(t):
    """The stipe's centre line at height fraction t: a lazy S, leaning a little."""
    return (0.35 * math.sin(t * 3.3) + 0.25 * t, 0.2 * math.sin(t * 2.1 + 1.0), t * HEIGHT)


bm = bmesh.new()
mat_index = {}

# The stipe: a tube tapering from 3 cm to 1.5 cm, flared at the foot into the holdfast.
rings = []
for r in range(RINGS + 1):
    t = r / RINGS
    cx, cy, cz = centre(t)
    radius = 0.03 - 0.015 * t
    if r == 0:
        radius = 0.11
    elif r == 1:
        radius = 0.045
    ring = []
    for s in range(SIDES):
        a = 2 * math.pi * s / SIDES
        ring.append(bm.verts.new((cx + radius * math.cos(a), cy + radius * math.sin(a), cz)))
    rings.append(ring)
for r in range(RINGS):
    for s in range(SIDES):
        f = bm.faces.new((rings[r][s], rings[r][(s + 1) % SIDES], rings[r + 1][(s + 1) % SIDES], rings[r + 1][s]))
        f.material_index = 0

# The blades: from 0.6 m up, every 0.32 m, alternating sides and turning as they climb. Each is a
# ribbon, wide in the middle and pointed at the tip, drooping and twisting along its length,
# with a float where it leaves the stalk.
h = 0.6
side = 1
turn = 0.0
blades = 0
while h < HEIGHT - 0.2:
    t = h / HEIGHT
    cx, cy, cz = centre(t)
    turn += 2.4
    a = turn
    out = (math.cos(a), math.sin(a))
    length = 0.7 + random.random() * 0.45
    if t > 0.85:
        length *= 1.4
    segs = 5
    prev = None
    for i in range(segs + 1):
        u = i / segs
        width = 0.13 * math.sin(math.pi * min(u * 1.15 + 0.05, 1.0)) + 0.01
        # Out and up at first, then drooping, the tip curling round.
        d = u * length
        px = cx + out[0] * (0.06 + d)
        py = cy + out[1] * (0.06 + d)
        pz = cz + d * 0.55 - (d * d) * 0.55
        twist = a + math.pi * 0.5 + u * 0.9
        wx, wy = math.cos(twist) * width * 0.5, math.sin(twist) * width * 0.5
        # A little ruffle: the blade's edges are wavy.
        wz = 0.02 * math.sin(u * 12.0)
        l = bm.verts.new((px - wx, py - wy, pz - wz))
        rr = bm.verts.new((px + wx, py + wy, pz + wz))
        if prev:
            f = bm.faces.new((prev[0], prev[1], rr, l))
            f.material_index = 1
        prev = (l, rr)
    # The float: a small squashed ball where the blade leaves the stalk.
    fx, fy = cx + out[0] * 0.05, cy + out[1] * 0.05
    ball = bmesh.ops.create_uvsphere(bm, u_segments=6, v_segments=4, radius=0.028)
    for v in ball["verts"]:
        v.co = (fx + v.co.x, fy + v.co.y, cz + v.co.z * 1.4)
    for f in {f for v in ball["verts"] for f in v.link_faces}:
        f.material_index = 0
    blades += 1
    h += 0.32
    side = -side

mesh = bpy.data.meshes.new("kelp")
bm.to_mesh(mesh)
bm.free()
mesh.materials.append(stipe_mat)
mesh.materials.append(blade_mat)
for p in mesh.polygons:
    p.use_smooth = True
obj = bpy.data.objects.new("Kelp", mesh)
bpy.context.scene.collection.objects.link(obj)
print("kelp: %d blades, %d faces" % (blades, len(mesh.polygons)))

bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/kelp.glb"), export_format="GLB")
print("wrote kelp.glb")
