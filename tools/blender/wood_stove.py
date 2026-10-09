# Builds the cabin's wood stove and writes assets/models/wood_stove.glb.
#
#     blender --background --python tools/blender/wood_stove.py
#
# A small cast-iron box stove on four legs: a raised door frame on the front with the fire
# showing through its glass between two bars, an ash lip under it, and the flue collar on the
# top towards the back. Two materials, "iron" and "fire", which CabinVenue swaps by name for its
# own (the fire glows). Blender -Y is the door, which arrives in Godot as +Z; the origin is on
# the floor under its middle.

import os
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
import bpy, bmesh, math
from mathutils import Vector
bpy.ops.wm.read_factory_settings(use_empty=True)
iron = bpy.data.materials.new("iron"); iron.diffuse_color=(0.03,0.03,0.03,1)
fire = bpy.data.materials.new("fire"); fire.diffuse_color=(1.0,0.45,0.1,1)
col = bpy.context.collection

def box(name, size, loc, mat, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.object; o.name=name; o.scale=size
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(mat)
    if bevel:
        m=o.modifiers.new("b","BEVEL"); m.width=bevel; m.segments=3; m.limit_method='ANGLE'
    return o

def cyl(name, r, depth, loc, mat, rot=(0,0,0), verts=24):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=loc, rotation=rot, vertices=verts)
    o=bpy.context.object; o.name=name; o.data.materials.append(mat); return o

W,D,H,LEG = 0.56, 0.5, 0.58, 0.16
parts=[]
parts.append(box("body",(W,D,H),(0,0,LEG+H/2),iron,0.02))
parts.append(box("top",(W+0.06,D+0.06,0.03),(0,0,LEG+H+0.015),iron,0.008))
parts.append(box("plinth",(W+0.03,D+0.03,0.03),(0,0,LEG+0.015),iron,0.006))
for sx in (-1,1):
    for sy in (-1,1):
        parts.append(cyl("leg",0.025,LEG,(sx*(W/2-0.05),sy*(D/2-0.05),LEG/2),iron,verts=10))
# The door on the front (-Y here, +Z in Godot): a raised frame, the fire seen through its glass.
fy = -D/2
parts.append(box("doorframe",(0.40,0.03,0.32),(0,fy-0.012,LEG+H*0.5),iron,0.008))
parts.append(box("glass",(0.30,0.01,0.22),(0,fy-0.03,LEG+H*0.5),fire))
for x in (-0.05,0.05):
    parts.append(box("bar",(0.012,0.012,0.22),(x,fy-0.036,LEG+H*0.5),iron))
parts.append(box("handle",(0.02,0.04,0.09),(0.17,fy-0.05,LEG+H*0.5),iron,0.004))
# The ash-pan lip under the door, and the flue collar on the top towards the back.
parts.append(box("ashlip",(0.34,0.04,0.05),(0,fy-0.02,LEG+0.08),iron,0.006))
parts.append(cyl("collar",0.08,0.1,(0,0.08,LEG+H+0.08),iron))
for p in parts:
    bpy.context.view_layer.objects.active=p
    for m in list(p.modifiers): bpy.ops.object.modifier_apply(modifier=m.name)
bpy.ops.object.select_all(action='DESELECT')
for p in parts: p.select_set(True)
bpy.context.view_layer.objects.active=parts[0]
bpy.ops.object.join(); o=bpy.context.object; o.name="wood_stove"
bpy.ops.object.shade_flat()
print("wrote wood_stove.glb, faces", len(o.data.polygons), [m.name for m in o.data.materials], [round(d,3) for d in o.dimensions])
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/wood_stove.glb"), export_format='GLB')
