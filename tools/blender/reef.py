# Builds the underwater dome's reef and its fish, and writes assets/models/reef.glb.
#
#     blender --background --python tools/blender/reef.py
#
# One file, several objects, each placed by DomeVenue by name:
#   Rock0..2      boulders: lumpy, flat underneath where they sit in the sand, about a metre across
#   CoralBranch   staghorn coral: a clump of forking round branches, 0.5 m tall
#   CoralBrain    brain coral: a squat dome ridged with winding grooves, 0.5 m across
#   CoralFan      a sea fan: a flat lacework of branches on a short stalk, 0.6 m tall, in Blender's
#                 XZ plane (Godot XY)
#   Fish          a small reef fish, 0.18 m nose to tail, nose at +X; its tail is the -X end, which
#                 the dome's shader swings as it swims
# Every origin is on the sand (the fish's is its middle). Materials "rock", "coral" (each coral
# its own: "staghorn", "brain", "fan") and "fish".

import math
import os
import random

import bpy
import bmesh
from mathutils import Vector, noise

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bpy.ops.wm.read_factory_settings(use_empty=True)
random.seed(3)
NAMES = ["rock", "staghorn", "brain", "fan", "fish"]
mats = {n: bpy.data.materials.new(n) for n in NAMES}


def finish(bm, name, mat_names, x_offset, smooth_angle=50):
    mesh = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    for m in mat_names:
        mesh.materials.append(mats[m])
    for p in mesh.polygons:
        p.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    for o in bpy.context.scene.objects:
        o.select_set(o == obj)
    bpy.ops.object.shade_auto_smooth(angle=math.radians(smooth_angle))
    obj.location.x = x_offset
    print("%s: %d faces" % (name, len(mesh.polygons)))


# The rocks: an icosphere pushed about by noise, squashed, its underside cut flat.
for i in range(3):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=3, radius=0.5)
    seed = Vector((i * 7.3, i * 3.1, i * 5.7))
    stretch = Vector((1.0 + random.random() * 0.6, 0.8 + random.random() * 0.4, 0.55 + random.random() * 0.25))
    for v in bm.verts:
        d = v.co.normalized()
        bump = noise.fractal(d * 1.6 + seed, 0.6, 2.0, 4) * 0.22
        v.co = Vector((v.co.x * stretch.x, v.co.y * stretch.y, v.co.z * stretch.z)) * (1.0 + bump)
        # Sunk into the sand: everything below a little under the middle is pressed flat.
        if v.co.z < -0.08:
            v.co.z = -0.08
        v.co.z += 0.08
    finish(bm, "Rock%d" % i, ["rock"], i * 1.3)


def tube(bm, a, b, r0, r1, sides=7):
    """A tapered round branch from a to b, capped at the tip."""
    a, b = Vector(a), Vector(b)
    d = (b - a).normalized()
    side = d.cross(Vector((0, 0, 1)))
    if side.length < 0.1:
        side = d.cross(Vector((1, 0, 0)))
    side.normalize()
    up = side.cross(d).normalized()
    rings = []
    for p, r in [(a, r0), (b, r1)]:
        rings.append([bm.verts.new(p + (side * math.cos(2 * math.pi * s / sides) + up * math.sin(2 * math.pi * s / sides)) * r)
                      for s in range(sides)])
    for s in range(sides):
        bm.faces.new((rings[0][s], rings[0][(s + 1) % sides], rings[1][(s + 1) % sides], rings[1][s]))
    tip = bm.verts.new(b + d * r1)
    for s in range(sides):
        bm.faces.new((rings[1][s], rings[1][(s + 1) % sides], tip))


# Staghorn: branches forking twice or three times from a few stems, reaching up and out.
bm = bmesh.new()


def branch(at, direction, length, r, depth):
    end = at + direction * length
    tube(bm, at, end, r, r * 0.75)
    if depth == 0:
        return
    for k in range(2):
        turn = Vector((random.uniform(-0.7, 0.7), random.uniform(-0.7, 0.7), random.uniform(0.2, 0.9)))
        branch(end, (direction + turn * 0.8).normalized(), length * random.uniform(0.65, 0.85), r * 0.72, depth - 1)


for k in range(8):
    a = 2 * math.pi * k / 8 + random.random() * 0.5
    branch(Vector((math.cos(a) * 0.05, math.sin(a) * 0.05, 0.0)),
           Vector((math.cos(a) * 0.8, math.sin(a) * 0.8, 1.0)).normalized(), 0.13, 0.02, 3)
finish(bm, "CoralBranch", ["staghorn"], 4.2, 60)

# Brain coral: a squashed half sphere, grooved by a winding ridge pattern.
bm = bmesh.new()
bmesh.ops.create_uvsphere(bm, u_segments=64, v_segments=24, radius=0.25)
for v in bm.verts:
    if v.co.z < 0:
        v.co.z = 0.0
    else:
        d = v.co.normalized()
        ridges = math.sin(noise.noise(d * 2.5) * 40.0)
        v.co = d * 0.25 * (1.0 + 0.035 * ridges)
        v.co.z *= 0.75
finish(bm, "CoralBrain", ["brain"], 5.0, 80)

# The sea fan: a stalk, then branches spreading in one plane, joined into a lace.
bm = bmesh.new()
tube(bm, (0, 0, 0), (0, 0, 0.1), 0.02, 0.015)


def fan(at, angle, length, r, depth):
    end = at + Vector((math.sin(angle), 0.0, math.cos(angle))) * length
    tube(bm, at, end, r, r * 0.8, sides=5)
    if depth == 0:
        return
    for s in (-1, 1):
        fan(end, angle + s * random.uniform(0.2, 0.42), length * 0.82, r * 0.82, depth - 1)


fan(Vector((0, 0, 0.1)), 0.0, 0.1, 0.01, 5)
finish(bm, "CoralFan", ["fan"], 5.8, 60)

# The fish: a lathed body along X, flattened side to side, a forked tail and a dorsal fin.
bm = bmesh.new()
profile = [(0.09, 0.0), (0.085, 0.012), (0.06, 0.026), (0.02, 0.032), (-0.03, 0.026), (-0.065, 0.012), (-0.075, 0.006)]
sides = 10
rings = []
for x, r in profile:
    rings.append([bm.verts.new((x, r * math.cos(2 * math.pi * s / sides) * 0.45, r * math.sin(2 * math.pi * s / sides)))
                  for s in range(sides)])
for i in range(len(rings) - 1):
    for s in range(sides):
        bm.faces.new((rings[i][s], rings[i][(s + 1) % sides], rings[i + 1][(s + 1) % sides], rings[i + 1][s]))
nose = bm.verts.new((0.093, 0, 0))
for s in range(sides):
    bm.faces.new((rings[0][(s + 1) % sides], rings[0][s], nose))
tail_root = rings[-1]
tail = [bm.verts.new(p) for p in [(-0.075, 0, 0.004), (-0.105, 0, 0.035), (-0.095, 0, 0.0), (-0.105, 0, -0.035), (-0.075, 0, -0.004)]]
bm.faces.new(tail)
dorsal = [bm.verts.new(p) for p in [(0.03, 0, 0.03), (-0.01, 0, 0.05), (-0.04, 0, 0.024)]]
bm.faces.new(dorsal)
finish(bm, "Fish", ["fish"], 6.5, 70)

bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "assets/models/reef.glb"), export_format="GLB")
print("wrote reef.glb")
