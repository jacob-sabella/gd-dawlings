# Builds the station's pressure hatch frame and writes assets/models/hatch.glb.
#
#     blender --background --python tools/blender/hatch.py
#
# The frame a corridor's doorway is cut through on a station: square outside, where it meets the
# wall's panels, and rounded inside, the way a pressure door's opening is, with its reveal
# striped in hazard paint and a lamp bar over the top. StationVenue sets it in the side walls
# with the wall's opening fitted to its outside. Materials "frame", "hazard" and "lamp".
# Blender X is across the doorway and Y through the wall (it arrives in Godot as -Z); the origin
# is on the floor under the middle of the opening.

import math
import os

import bpy
import bmesh

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
frame = bpy.data.materials.new("frame")
hazard = bpy.data.materials.new("hazard")
lamp = bpy.data.materials.new("lamp")

# The outside, the opening through it, and how deep it runs (proud of a 0.2 m wall each side).
OUT_W, OUT_H = 2.0, 2.7
IN_W, IN_H, IN_R = 1.4, 2.25, 0.32
SILL = 0.06
DEPTH = 0.36
SEG = 6


def outline(w, h, r, bottom):
    """A rounded rectangle, anticlockwise from the bottom middle, in X/Z."""
    pts = []
    corners = [(w / 2 - r, bottom + r, -90), (w / 2 - r, bottom + h - r, 0),
               (-w / 2 + r, bottom + h - r, 90), (-w / 2 + r, bottom + r, 180)]
    for cx, cz, start in corners:
        for i in range(SEG + 1):
            a = math.radians(start + 90 * i / SEG)
            pts.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    return pts


inner = outline(IN_W, IN_H, IN_R, SILL)
outer = outline(OUT_W, OUT_H, 0.04, 0.0)
bm = bmesh.new()


def ring(pts, y):
    return [bm.verts.new((x, y, z)) for x, z in pts]


of, ob = ring(outer, -DEPTH / 2), ring(outer, DEPTH / 2)
inf, inb = ring(inner, -DEPTH / 2), ring(inner, DEPTH / 2)
n = len(inner)
for i in range(n):
    j = (i + 1) % n
    # The two faces of the frame, the outside edge, and the reveal through it.
    bm.faces.new((of[i], of[j], inf[j], inf[i])).material_index = 0
    bm.faces.new((ob[j], ob[i], inb[i], inb[j])).material_index = 0
    bm.faces.new((of[j], of[i], ob[i], ob[j])).material_index = 0
    bm.faces.new((inf[i], inf[j], inb[j], inb[i])).material_index = 1
me = bpy.data.meshes.new("hatch")
bm.normal_update()
bm.to_mesh(me)
bm.free()
ob_frame = bpy.data.objects.new("hatch", me)
bpy.context.collection.objects.link(ob_frame)
for m in (frame, hazard, lamp):
    me.materials.append(m)
# The lamp bar over the opening, on both faces.
for y in (-DEPTH / 2 - 0.02, DEPTH / 2 + 0.02):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, y, SILL + IN_H + 0.12))
    bar = bpy.context.object
    bar.scale = (0.6, 0.04, 0.05)
    bpy.ops.object.transform_apply(scale=True)
    bar.data.materials.append(frame)
    bar.data.materials.append(hazard)
    bar.data.materials.append(lamp)
    for p in bar.data.polygons:
        p.material_index = 2
    bar.select_set(True)
ob_frame.select_set(True)
bpy.context.view_layer.objects.active = ob_frame
bpy.ops.object.join()
o = bpy.context.object
# Hazard stripes want UVs that run round the reveal: unwrap it by its own length.
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.02)
bpy.ops.object.mode_set(mode="OBJECT")
bpy.ops.object.shade_flat()
print("hatch faces", len(o.data.polygons), [m.name for m in o.data.materials], [round(d, 2) for d in o.dimensions])
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/hatch.glb"), export_format="GLB")
print("wrote hatch.glb")
