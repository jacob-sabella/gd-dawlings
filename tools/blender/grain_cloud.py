# Builds the grain cloud's plinth and its bowl, and writes assets/models/grain_cloud.glb.
#
#     blender --background --python tools/blender/grain_cloud.py
#
# WHAT IT IS FOR
#
# A sample as a cloud of grains (docs/spatial_loop.md part two, slice 54, idea #24): a cassette put in
# the bowl is the cloud's sound, and the cloud a metre across over it is played by reaching in. So it
# looks like a gallery plinth with a turned brass bowl on its cap: a dark kick at the floor, a pale
# column, a cap a little proud of it, and the bowl, low and wide, its inner floor where a cassette
# stands on its edge. Over the cap, two slim brass posts rise from the cap's front corners to a thin
# rail along the cloud's front, so the cloud's foot reads as a place in the air and not as nothing.
# The rail runs under the cloud's tag, its lettering standing on it, so nothing crosses the words for
# what plays from any eye above it.
# The cloud, its motes, its sparks, its lettering, the KEY switch and the plaque are GrainCloud's own
# (they light, move and change); this is everything that does not.
#
# GrainCloud (core/music/grain_cloud.gd) repeats every number below that it places things by (the
# footprint, the cap's top, the bowl's rim, floor and radius, the cloud's middle and size), so the
# two agree.
#
# ORIENTATION (see _parts.py)
#
# Godot +Y is Blender +Z and Godot -Z is Blender +Y. Its origin is the middle of the plinth's foot,
# on the floor; its front, where you stand, is Godot +Z: Blender -Y.

import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _parts import (  # noqa: E402
    _flatten, bevel_all, box, clear_scene, export, join, material, report, smooth,
)

# --- In metres, in Godot's terms (y up, z toward you), as GrainCloud has them. ----------------

FOOT = (0.16, 0.16)       # half the footprint: x, z
SKIRT = 0.05              # the dark kick at the floor
PLINTH_TOP = 0.9          # the cap's top
CAP = 0.03                # the cap's thickness
BOWL_RIM = 0.95           # the bowl's rim
BOWL_FLOOR = 0.914        # its inner floor
BOWL_RADIUS = 0.12        # its rim's radius
MID = (0.0, 1.32, 0.1)    # the cloud's middle
HALF = (0.5, 0.26, 0.2)   # half the cloud's size
POST = 0.006              # a post's radius
RAIL = 0.005              # the front rail's radius
RAIL_Y = 0.975            # its height: under the tag (GrainCloud TAG_AT, its two lines down to ~1.0)

MATS = []


def g(p):
    """A point in Godot's terms as Blender has it."""
    return Vector((p[0], -p[2], p[1]))


def gbox(name, lo, hi, ease=0.0015):
    """A box from Godot-space corners: x, y up, z toward you, its edges eased."""
    size = (hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1])
    centre = ((lo[0] + hi[0]) * 0.5, -(lo[2] + hi[2]) * 0.5, (lo[1] + hi[1]) * 0.5)
    return bevel_all(box(name, size, centre), ease, 1)


def rod(name, a, b, radius, vertices=16):
    """A cylinder from Godot point `a` to `b`."""
    a = g(a)
    b = g(b)
    d = b - a
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=d.length,
            location=(a + b) * 0.5, rotation=d.to_track_quat("Z", "Y").to_euler())
    obj = bpy.context.active_object
    obj.name = name
    return _flatten(obj)


def metal(name, colour, roughness, metallic):
    """A material that is metal: _parts.material sets only the colour and the roughness."""
    mat = material(name, colour, roughness)
    principled = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    if "Metallic" in principled.inputs:
        principled.inputs["Metallic"].default_value = metallic
    return mat


def slot(obj, index):
    obj.data.materials.clear()
    for m in MATS:
        obj.data.materials.append(m)
    for p in obj.data.polygons:
        p.material_index = index
    return obj


def lathe(name, profile, segments=40):
    """A turned shape from (radius, height) pairs in Godot's terms, round Godot's +Y."""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    rings = []
    for r, y in profile:
        if r == 0.0:
            rings.append([bm.verts.new((0.0, 0.0, y))])
            continue
        rings.append([bm.verts.new((r * math.cos(a), r * math.sin(a), y))
                for a in (math.tau * i / segments for i in range(segments))])
    for lower, upper in zip(rings, rings[1:]):
        for i in range(segments):
            j = (i + 1) % segments
            if len(lower) == 1:
                bm.faces.new((lower[0], upper[i], upper[j]))
            elif len(upper) == 1:
                bm.faces.new((lower[i], lower[j], upper[0]))
            else:
                bm.faces.new((lower[i], lower[j], upper[j], upper[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def plinth_parts():
    fx, fz = FOOT
    parts = []
    parts.append(slot(gbox("Skirt", (-fx, 0.0, -fz), (fx, SKIRT, fz), 0.003), 2))
    parts.append(slot(gbox("Column", (-fx + 0.02, SKIRT, -fz + 0.02), (fx - 0.02, PLINTH_TOP - CAP, fz - 0.02), 0.004), 0))
    parts.append(slot(gbox("Cap", (-fx - 0.01, PLINTH_TOP - CAP, -fz - 0.01), (fx + 0.01, PLINTH_TOP, fz + 0.01), 0.004), 0))
    return parts


def bowl_parts():
    # Low and wide: a foot ring on the cap, the belly out to the rim, a rolled lip, and the inside
    # down to a flat floor where the cassette stands.
    r = BOWL_RADIUS
    profile = [(0.0, PLINTH_TOP), (0.05, PLINTH_TOP), (0.055, PLINTH_TOP + 0.006), (0.085, PLINTH_TOP + 0.02),
            (r - 0.008, BOWL_RIM - 0.008), (r, BOWL_RIM - 0.002), (r - 0.004, BOWL_RIM), (r - 0.01, BOWL_RIM - 0.003),
            (r - 0.03, BOWL_FLOOR + 0.02), (0.07, BOWL_FLOOR + 0.002), (0.0, BOWL_FLOOR)]
    return [slot(lathe("Bowl", profile), 1)]


def frame_parts():
    # Two posts from the cap's front corners up and out to the cloud's front, and a rail between them
    # under the cloud's tag: where the cloud begins, in brass, the tag's lettering standing on it.
    fx, fz = FOOT
    front = MID[2] + HALF[2]
    parts = []
    for side in (-1.0, 1.0):
        x = side * (fx - 0.01)
        parts.append(slot(rod("Post", (x, PLINTH_TOP, fz - 0.01), (x, RAIL_Y, front - 0.02), POST), 1))
    parts.append(slot(rod("Rail", (-HALF[0] * 0.6, RAIL_Y, front - 0.02), (HALF[0] * 0.6, RAIL_Y, front - 0.02), RAIL), 1))
    return parts


def grain_cloud():
    clear_scene()
    MATS[:] = [material("plaster", (0.62, 0.6, 0.56, 1.0), 0.8),
            metal("brass", (0.78, 0.58, 0.26, 1.0), 0.35, 0.9),
            material("kick", (0.05, 0.04, 0.035, 1.0), 0.7)]
    parts = plinth_parts() + bowl_parts() + frame_parts()
    first = parts.pop(0)
    obj = join(first, parts)
    obj.name = "GrainCloud"
    smooth(obj, 30.0)
    report(obj)
    export(obj, "assets/models/grain_cloud.glb")


os.chdir(os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")))
grain_cloud()
