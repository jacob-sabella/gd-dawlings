# Builds the Tour road case and writes assets/models/tour_case.glb.
#
#     blender --background --python tools/blender/tour_case.py
#
# A battered flight case chained shut in the back of house (core/items/tour_case.gd): a shell
# with corner protectors and a recessed stencil panel (TourCase stamps "TOUR" over it with a
# Label3D -- no text baked into the mesh), built facing -Y in Blender (+Z once exported, into
# the room), origin on the floor under its middle. Three objects: "Body", everything that stays
# put, "Lid", hinged from the BACK top edge (its own origin there) so the game can swing it open
# on the hit that breaks the case, and "Chain", the chain and padlock across the latch, kept
# separate so the game can hide it the instant the case bursts and show it again once reset.
# Materials "shell", "corner", "stencil", "chain", "latch".
#
# Sizes in Godot's terms (y up, z out of the front toward the room), which TourCase and
# Venue.tour_case_spot() repeat.

import math
import os

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

WIDTH = 0.74
DEPTH = 0.46
BODY_H = 0.42
LID_H = 0.055
CORNER = 0.045
# How far the corner protectors and the latch stand proud of the shell: flush, their faces and
# the shell's share a plane and fight over every pixel of it.
PROUD = 0.004
# The hinge: the back top edge, in Godot space. Front is +Z, so back is -Z.
HINGE = (0.0, BODY_H, -DEPTH * 0.5)


def reset():
	bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name):
	return bpy.data.materials.get(name) or bpy.data.materials.new(name)


def tag(ob, mat):
	ob.data.materials.append(material(mat))
	return ob


def g(x, y, z):
	# Godot's (x, y up, z toward the room) as Blender's (x, -z, y).
	return (x, -z, y)


def box(size, at, mat):
	bpy.ops.mesh.primitive_cube_add(size=1, location=g(*at))
	ob = bpy.context.active_object
	ob.scale = (size[0], size[2], size[1])
	bpy.ops.object.transform_apply(scale=True)
	return tag(ob, mat)


def join(objs, name):
	bpy.ops.object.select_all(action="DESELECT")
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = objs[0]
	if len(objs) > 1:
		bpy.ops.object.join()
	ob = bpy.context.active_object
	ob.name = name
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	return ob


reset()

# --- the body: shell, corner posts (the body's own height), stencil recess -------------------
body_parts = []
body_parts.append(box((WIDTH, BODY_H, DEPTH), (0, BODY_H * 0.5, 0), "shell"))
for cx in (-1.0, 1.0):
	for cz in (-1.0, 1.0):
		at = (cx * (WIDTH * 0.5 - CORNER * 0.5 + PROUD), BODY_H * 0.5, cz * (DEPTH * 0.5 - CORNER * 0.5 + PROUD))
		body_parts.append(box((CORNER, BODY_H - 0.004, CORNER), at, "corner"))
body = join(body_parts, "Body")

# --- the chain and padlock across the latch, its own object so it can be hidden on a burst -----
chain_parts = []
chain_parts.append(box((0.05, 0.03, 0.02), (0, BODY_H, DEPTH * 0.5 - 0.01 + PROUD), "latch"))
bpy.ops.mesh.primitive_torus_add(major_radius=0.018, minor_radius=0.004, major_segments=16,
		minor_segments=8, location=g(0, BODY_H + 0.025, DEPTH * 0.5 - 0.01),
		rotation=(math.radians(90), 0, 0))
chain_parts.append(tag(bpy.context.active_object, "latch"))
# A run of small flattened links, corner to corner across the front, each turned a quarter from
# the last so they read as links rather than a row of rings.
chain_from = Vector((-WIDTH * 0.35, BODY_H * 0.92, DEPTH * 0.5 + 0.006))
chain_to = Vector((WIDTH * 0.32, BODY_H * 0.18, DEPTH * 0.5 + 0.006))
LINKS = 7
for k in range(LINKS):
	f = k / (LINKS - 1)
	at = chain_from.lerp(chain_to, f)
	bpy.ops.mesh.primitive_torus_add(major_radius=0.026, minor_radius=0.0045, major_segments=12,
			minor_segments=6, location=g(at.x, at.y, at.z),
			rotation=(math.radians(90) * (k % 2), math.radians(35), 0))
	chain_parts.append(tag(bpy.context.active_object, "chain"))
chain = join(chain_parts, "Chain")

# --- the lid: hinged from the back top edge, its own origin there ------------------------------
# Built relative to HINGE as if it were the local origin, then moved there afterward (the way
# hoop.py's "Net" is built round the rim and moved up to it) -- not baked, so the hinge survives.
lid_parts = []
lid_parts.append(box((WIDTH, LID_H, DEPTH), (0, LID_H * 0.5, DEPTH * 0.5), "shell"))
for cx in (-1.0, 1.0):
	for cz_edge in (CORNER * 0.5, DEPTH - CORNER * 0.5):
		at = (cx * (WIDTH * 0.5 - CORNER * 0.5 + PROUD), LID_H * 0.5,
				cz_edge + (PROUD if cz_edge > DEPTH * 0.5 else -PROUD))
		lid_parts.append(box((CORNER, LID_H - 0.004, CORNER), at, "corner"))
# A handle, toward the front edge so a hand reaching for it falls where a lid is grabbed.
lid_parts.append(box((0.12, 0.025, 0.05), (0, LID_H + 0.0125, DEPTH - 0.1), "latch"))
lid = join(lid_parts, "Lid")
lid.location = g(*HINGE)

bpy.context.view_layer.update()
for ob in bpy.data.objects:
	lo = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
	print(ob.name, "bounds", tuple(round(min(v[i] for v in lo), 4) for i in range(3)),
			tuple(round(max(v[i] for v in lo), 4) for i in range(3)), len(ob.data.polygons), "faces")
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/tour_case.glb"), export_format="GLB")
print("wrote assets/models/tour_case.glb")
