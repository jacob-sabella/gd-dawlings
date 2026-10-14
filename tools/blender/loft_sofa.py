# Builds a leather sofa and a low table and writes assets/models/loft_sofa.glb.
#
#     blender --background --python tools/blender/loft_sofa.py
#
# For the loft's sunny corner on a Sunday morning (LoftVenue, arrangement 1): a three-seat
# sofa in worn cognac leather on tapered walnut legs, its seat and back in loose cushions with
# rounded edges, arms square and low; and a long low table to stand the coffee on, a walnut top
# on black steel hairpin legs. Two objects:
#
#   sofa   2.0 m long (along X), 0.86 deep, 0.8 tall, its front toward -Y (Godot +Z), origin on
#          the floor under its middle.
#   table  1.0 x 0.5 m, 0.4 tall, origin on the floor under its middle.
#
# Materials, swapped by name in the venue: "leather", "walnut", "steel".

import math
import os

import bpy
import bmesh
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
ORDER = ["leather", "walnut", "steel"]
MATS = [bpy.data.materials.new(n) for n in ORDER]


def cushion(bm, size, centre, mat, round_by):
    """A box with every edge rounded and its top and bottom swelling: a stuffed cushion. Built
    in a bmesh of its own and appended, so no op on it touches what is already there."""
    c = bmesh.new()
    ret = bmesh.ops.create_cube(c, size=1.0)
    for v in ret["verts"]:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    bmesh.ops.bevel(c, geom=list(c.edges) + list(c.verts), offset=round_by, offset_type="OFFSET",
                    segments=3, profile=0.5, affect="EDGES", clamp_overlap=True)
    for v in c.verts:
        px = max(1.0 - (2.0 * v.co.x / size[0]) ** 2, 0.0)
        py = max(1.0 - (2.0 * v.co.y / size[1]) ** 2, 0.0)
        v.co.z += math.copysign(1.0, v.co.z) * px * py * round_by * 0.5
        v.co += Vector(centre)
    for f in c.faces:
        f.material_index = ORDER.index(mat)
    tmp = bpy.data.meshes.new("tmp")
    c.to_mesh(tmp)
    c.free()
    bm.from_mesh(tmp)
    bpy.data.meshes.remove(tmp)


def leg(bm, foot, top, r0, r1, mat):
    ret = bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=r0, radius2=r1,
                                depth=(top - foot).length)
    d = (top - foot).normalized()
    rot = Vector((0, 0, 1)).rotation_difference(d).to_matrix()
    for v in ret["verts"]:
        v.co = (foot + top) * 0.5 + rot @ v.co
    for f in {f for v in ret["verts"] for f in v.link_faces}:
        f.material_index = ORDER.index(mat)


def obj(name, bm):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for m in MATS:
        me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    print(name, len(me.polygons), "faces")
    return ob


# --- the sofa. Blender -Y is its front (Godot +Z).
L, DEEP = 2.0, 0.86
LEG = 0.16
bm = bmesh.new()
# The frame: a base under the seat cushions, the back behind them, an arm at each end.
cushion(bm, (L - 0.04, DEEP - 0.02, 0.16), (0, 0, LEG + 0.08), "leather", 0.03)
cushion(bm, (L - 0.3, 0.2, 0.42), (0, DEEP * 0.5 - 0.11, LEG + 0.16 + 0.2), "leather", 0.05)
for side in (-1, 1):
    cushion(bm, (0.16, DEEP, 0.42), (side * (L * 0.5 - 0.08), 0, LEG + 0.21), "leather", 0.05)
# Three seat cushions, and three back cushions leant against the back.
for k in range(3):
    x = (k - 1) * (L - 0.32) / 3
    cushion(bm, ((L - 0.34) / 3 - 0.01, DEEP - 0.26, 0.15), (x, -0.1, LEG + 0.16 + 0.075), "leather", 0.045)
    cushion(bm, ((L - 0.34) / 3 - 0.01, 0.16, 0.36), (x, DEEP * 0.5 - 0.29, LEG + 0.31 + 0.18), "leather", 0.06)
# Tapered walnut legs, splayed a little.
for sx in (-1, 1):
    for sy in (-1, 1):
        foot = Vector((sx * (L * 0.5 - 0.06), sy * (DEEP * 0.5 - 0.06), 0.0))
        top = Vector((sx * (L * 0.5 - 0.1), sy * (DEEP * 0.5 - 0.1), LEG + 0.01))
        leg(bm, foot, top, 0.014, 0.022, "walnut")
obj("sofa", bm)

# --- the table: a walnut top on four hairpins.
bm = bmesh.new()
TW, TD, TH = 1.0, 0.5, 0.4
cushion(bm, (TW, TD, 0.03), (0, 0, TH - 0.015), "walnut", 0.008)
for sx in (-1, 1):
    for sy in (-1, 1):
        top_a = Vector((sx * (TW * 0.5 - 0.06), sy * (TD * 0.5 - 0.05), TH - 0.03))
        top_b = Vector((sx * (TW * 0.5 - 0.06), sy * (TD * 0.5 - 0.16), TH - 0.03))
        foot = Vector((sx * (TW * 0.5 - 0.08), sy * (TD * 0.5 - 0.1), 0.0))
        leg(bm, foot, top_a, 0.005, 0.005, "steel")
        leg(bm, foot, top_b, 0.005, 0.005, "steel")
obj("table", bm).location.x = 1.5

bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/loft_sofa.glb"), export_format="GLB")
print("wrote loft_sofa.glb")
