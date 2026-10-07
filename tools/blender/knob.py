# Builds the panel knob mesh and writes assets/hardware/knob.glb.
#
# Run from the project root:
#
#     blender --background --python tools/blender/knob.py
#
# WHY A SCRIPT AND NOT A .blend
#
# Everything else in this project computes its own geometry at load: the console is as wide as
# the track count, the timeline is as long as the song. A .blend committed next to that would be
# the one shape in the scene nobody could read, diff or adjust -- and the first time a knob
# needed to be 2mm smaller it would need Blender open on somebody's desk. The mesh is authored
# here, in numbers, for the same reason the rest of the hardware is.
#
# WHY BLENDER AND NOT MORE GDSCRIPT
#
# Because of the bevels. A knob reads as moulded plastic rather than a cylinder almost entirely
# through its rounded edges, and chamfering an edge loop is the one modelling operation that is
# genuinely painful to write by hand against Godot's ArrayMesh.
#
# ORIENTATION
#
# Modelled axis-up (+Z), which glTF's Y-up conversion turns into axis-up (+Y) in Godot; the
# importing node applies the same 90-degree X rotation the old CylinderMesh did, which lands the
# axis along local +Z -- the panel normal. Blender +Y survives that round trip as Godot +Y, so
# the moulded indicator is modelled pointing at +Y and arrives pointing at +Y: straight up at
# value 0.5, exactly where the old box-on-a-pivot pointed.
#
# The envelope matches the mesh it replaces on purpose -- 22mm across, 13mm deep, spanning
# z -0.0065 to +0.0065 about the node origin. A hundred of these are already laid out by a
# console that measured itself around the old numbers.

import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

# --- Dimensions, in metres. ----------------------------------------------------------------

RADIUS = 0.011          # Skirt, and the knob's nominal radius.
BASE = -0.0065          # Behind the panel: where the shaft would go in.
TOP = 0.0065

SKIRT_HEIGHT = 0.0036
SKIRT_TOP = BASE + SKIRT_HEIGHT
## Eighteen flutes: a 36-sided skirt with every other column pushed out. Deep enough to catch a
## specular edge at arm's length, shallow enough not to read as a gear.
FLUTES = 18
FLUTE_DEPTH = 0.00032

CAP_SEGMENTS = 32
CAP_BOTTOM_RADIUS = 0.0093
CAP_TOP_RADIUS = 0.0088

INDICATOR_WIDTH = 0.0016
INDICATOR_PROUD = 0.00035

BODY_MATERIAL = "KnobBody"
INDICATOR_MATERIAL = "KnobIndicator"

OUT = os.path.join(os.getcwd(), "assets", "hardware", "knob.glb")


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.objects):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def cone(name, vertices, r1, r2, depth, z):
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices, radius1=r1, radius2=r2, depth=depth, location=(0.0, 0.0, z)
    )
    obj = bpy.context.active_object
    obj.name = name
    _flatten(obj)
    return obj


def box(name, size, centre, pitch=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=centre)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = Vector(size)
    obj.rotation_euler = (pitch, 0.0, 0.0)
    _flatten(obj)
    return obj


def _flatten(obj):
    """Bake the object transform into the vertices and sit the origin at the world origin.

    Not housekeeping. Every primitive operator hands back a mesh centred on its own origin with
    the placement left in the object matrix, so a vertex at the top rim reads as z=+0.0047 in
    its own space and z=+0.0065 in the scene. The bevels below find edge loops BY HEIGHT, and
    joining reparents all of it into whichever object happened to be active -- so without this,
    every search runs against a different space than the numbers were written in, finds nothing,
    and the knob exports as an unchamfered cylinder with no error anywhere.
    """
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def knurl(obj):
    """Push alternating angular columns of the skirt outward.

    Done on the mesh data rather than with a modifier because the displacement has to be an
    exact function of the vertex's own angle: a noise or wave texture would wander off the
    column boundaries and leave flutes that do not close at the top and bottom rings.
    """
    mesh = obj.data
    for v in mesh.vertices:
        angle = math.atan2(v.co.y, v.co.x)
        column = round(angle / (2.0 * math.pi) * (FLUTES * 2))
        if column % 2:
            continue
        radius = math.hypot(v.co.x, v.co.y)
        if radius < 1e-6:
            continue
        scale = (radius + FLUTE_DEPTH) / radius
        v.co.x *= scale
        v.co.y *= scale


def bevel_rings(obj, rings):
    """Chamfer the horizontal edge loops at the given heights.

    Edges are found by height rather than by index because joining objects renumbers
    everything, and an index that was right before the join is silently wrong after it.
    """
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for z, offset, segments in rings:
        geom = [
            e for e in bm.edges
            if abs(e.verts[0].co.z - z) < 1e-5 and abs(e.verts[1].co.z - z) < 1e-5
        ]
        if not geom:
            # Loud, because the failure mode is an export that works and a knob that is a
            # cylinder. Nothing downstream can tell the difference.
            raise RuntimeError("no edge ring at z=%.5f -- geometry moved, bevel heights stale" % z)
        bmesh.ops.bevel(
            bm, geom=geom, offset=offset, offset_type="OFFSET",
            segments=segments, profile=0.5, affect="EDGES", clamp_overlap=True,
        )
    bm.to_mesh(obj.data)
    bm.free()


def bevel_everything(obj, offset, segments):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.bevel(
        bm, geom=list(bm.edges) + list(bm.verts), offset=offset, offset_type="OFFSET",
        segments=segments, profile=0.5, affect="EDGES", clamp_overlap=True,
    )
    bm.to_mesh(obj.data)
    bm.free()


def material(name, colour):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    principled = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    principled.inputs["Base Color"].default_value = colour
    if "Roughness" in principled.inputs:
        principled.inputs["Roughness"].default_value = 0.45
    return mat


def join(target, others):
    bpy.ops.object.select_all(action="DESELECT")
    for o in others:
        o.select_set(True)
    target.select_set(True)
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.join()
    return bpy.context.active_object


def build():
    clear_scene()

    skirt = cone("Skirt", FLUTES * 2, RADIUS, RADIUS - 0.00015,
                 SKIRT_HEIGHT, BASE + SKIRT_HEIGHT * 0.5)
    knurl(skirt)

    cap_height = TOP - SKIRT_TOP
    cap = cone("Cap", CAP_SEGMENTS, CAP_BOTTOM_RADIUS, CAP_TOP_RADIUS,
               cap_height, SKIRT_TOP + cap_height * 0.5)

    body = join(cap, [skirt])
    body.name = "Knob"
    bevel_rings(body, [
        (BASE, 0.00040, 2),        # Where it meets the panel: no knife edge.
        (SKIRT_TOP, 0.00030, 2),   # The step between skirt and cap, from both sides.
        (TOP, 0.00070, 3),         # The top rim, which is most of why it reads as moulded.
    ])

    # The indicator wraps the top edge: a line across the cap face and a flute down the front.
    # One mark on two faces, because a knob is read from above when you are sitting at the desk
    # and from in front when you are standing at it, and a mark on only one of those is a knob
    # whose position you cannot see from where you happen to be.
    face = box(
        "IndicatorFace",
        (INDICATOR_WIDTH, CAP_TOP_RADIUS, 0.0010),
        (0.0, CAP_TOP_RADIUS * 0.5, TOP - 0.0005 + INDICATOR_PROUD),
    )
    # The cap is a cone, not a cylinder -- three degrees of draft -- so the flank is pitched to
    # match it and placed on the slanted surface rather than on a radius. An upright box on a
    # tapered wall sinks into it at one end and floats off it at the other, which is exactly
    # what the first attempt did: the line vanished entirely below the top chamfer.
    draft = math.atan2(CAP_BOTTOM_RADIUS - CAP_TOP_RADIUS, cap_height)
    # Runs from just clear of the skirt step to just under the top chamfer, so the two marks
    # read as one line bent over the corner rather than two unrelated pips.
    flank_top = TOP - 0.0004
    flank_bottom = SKIRT_TOP + 0.0008
    flank_h = flank_top - flank_bottom
    mid_z = (flank_top + flank_bottom) * 0.5
    mid_r = CAP_BOTTOM_RADIUS + (CAP_TOP_RADIUS - CAP_BOTTOM_RADIUS) \
            * (mid_z - SKIRT_TOP) / cap_height
    flank_t = 0.0010
    flank = box(
        "IndicatorFlank",
        (INDICATOR_WIDTH, flank_t, flank_h),
        (0.0, mid_r + INDICATOR_PROUD - flank_t * 0.5, mid_z),
        pitch=draft,
    )
    indicator = join(face, [flank])
    indicator.name = "Indicator"
    bevel_everything(indicator, 0.00018, 2)

    body.data.materials.append(material(BODY_MATERIAL, (0.14, 0.15, 0.17, 1.0)))
    indicator.data.materials.append(material(INDICATOR_MATERIAL, (0.86, 0.88, 0.91, 1.0)))

    knob = join(body, [indicator])
    knob.name = "Knob"

    bpy.ops.object.select_all(action="DESELECT")
    knob.select_set(True)
    bpy.context.view_layer.objects.active = knob
    bpy.ops.object.shade_smooth()
    # Blender dropped per-mesh auto-smooth in 4.1; the modifier is the supported replacement,
    # and the exporter applies it. Without it every chamfer reads as a faceted band.
    if hasattr(bpy.ops.object, "shade_auto_smooth"):
        bpy.ops.object.shade_auto_smooth(angle=math.radians(38.0))

    tris = sum(len(p.vertices) - 2 for p in knob.data.polygons)
    print("knob: %d verts, %d tris, %d material slots"
          % (len(knob.data.vertices), tris, len(knob.data.materials)))
    for i, slot in enumerate(knob.data.materials):
        print("  slot %d: %s" % (i, slot.name if slot else "<none>"))
    bb = [knob.matrix_world @ Vector(c) for c in knob.bound_box]
    print("bounds x %.4f..%.4f  y %.4f..%.4f  z %.4f..%.4f" % (
        min(p.x for p in bb), max(p.x for p in bb),
        min(p.y for p in bb), max(p.y for p in bb),
        min(p.z for p in bb), max(p.z for p in bb),
    ))
    return knob


def export(knob):
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    knob.select_set(True)
    bpy.context.view_layer.objects.active = knob
    kwargs = {
        "filepath": OUT,
        "export_format": "GLB",
        "use_selection": True,
        "export_apply": True,
        "export_yup": True,
    }
    # The exporter's keywords move between releases, so anything it does not recognise is
    # dropped rather than taken down the whole build.
    allowed = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    kwargs = {k: v for k, v in kwargs.items() if k in allowed}
    bpy.ops.export_scene.gltf(**kwargs)
    print("wrote %s (%d bytes)" % (OUT, os.path.getsize(OUT)))


if __name__ == "__main__":
    export(build())
