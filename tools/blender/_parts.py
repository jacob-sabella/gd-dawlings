"""Shared scaffolding for the authored hardware parts.

Each part is its own script -- tools/blender/knob.py, tools/blender/fader_cap.py -- holding
nothing but its own dimensions and its own reasons. What lives here is the machinery those
scripts are tired of repeating, and one rule that is easy to get wrong.

THE RULE: every primitive operator hands back a mesh centred on its own origin with the
placement left in the object matrix, so a vertex at the top rim reads at one height in its own
space and another in the scene. Everything downstream that finds geometry BY POSITION -- which
is how bevels pick their edge loops -- then searches a different space than the numbers were
written in, finds nothing, and the part exports fine and wrong. So `_flatten` runs on every
primitive the moment it is made, and the finders raise rather than warn.

ORIENTATION, once, for all parts:

    Blender +X  ->  Godot +X
    Blender +Z  ->  Godot +Y        (glTF's Y-up conversion)
    Blender +Y  ->  Godot -Z

A part is modelled in whatever Blender orientation is natural to sculpt in, and the importing
node is told which rotation, if any, stands it back up. The mapping is written down here so
that decision is made against a fact rather than against a memory of one.
"""

import math
import os

import bpy
import bmesh
from mathutils import Vector


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.objects):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def _flatten(obj):
    """Bake the object transform into the vertices. See THE RULE above."""
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj


def cone(name, vertices, r1, r2, depth, z):
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices, radius1=r1, radius2=r2, depth=depth, location=(0.0, 0.0, z)
    )
    obj = bpy.context.active_object
    obj.name = name
    return _flatten(obj)


def box(name, size, centre, pitch=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=centre)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = Vector(size)
    obj.rotation_euler = (pitch, 0.0, 0.0)
    return _flatten(obj)


def cylinder(name, radius, depth, centre, axis="Z", vertices=24):
    """A cylinder lying along one axis. Used far more often as a cutter than as a part."""
    rot = {"Z": (0.0, 0.0, 0.0), "X": (0.0, math.pi / 2, 0.0), "Y": (math.pi / 2, 0.0, 0.0)}[axis]
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=depth, location=centre, rotation=rot
    )
    obj = bpy.context.active_object
    obj.name = name
    return _flatten(obj)


def cut(obj, cutter):
    """Subtract `cutter` from `obj` and throw the cutter away."""
    bpy.context.view_layer.objects.active = obj
    mod = obj.modifiers.new("Cut", "BOOLEAN")
    mod.object = cutter
    mod.operation = "DIFFERENCE"
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)
    return obj


def bevel_rings(obj, rings):
    """Chamfer the horizontal edge loops at the given heights.

    Loops are found by height rather than by index because joining renumbers everything, and an
    index that was right before the join is silently wrong after it.
    """
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for z, offset, segments in rings:
        geom = [
            e for e in bm.edges
            if abs(e.verts[0].co.z - z) < 1e-5 and abs(e.verts[1].co.z - z) < 1e-5
        ]
        if not geom:
            # Loud, because the failure mode is an export that works and a part that is a
            # primitive. Nothing downstream can tell the difference.
            raise RuntimeError("no edge ring at z=%.5f -- geometry moved, bevel heights stale" % z)
        bmesh.ops.bevel(
            bm, geom=geom, offset=offset, offset_type="OFFSET",
            segments=segments, profile=0.5, affect="EDGES", clamp_overlap=True,
        )
    bm.to_mesh(obj.data)
    bm.free()
    return obj


def bevel_all(obj, offset, segments):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.bevel(
        bm, geom=list(bm.edges) + list(bm.verts), offset=offset, offset_type="OFFSET",
        segments=segments, profile=0.5, affect="EDGES", clamp_overlap=True,
    )
    bm.to_mesh(obj.data)
    bm.free()
    return obj


def material(name, colour, roughness=0.45):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    principled = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    principled.inputs["Base Color"].default_value = colour
    if "Roughness" in principled.inputs:
        principled.inputs["Roughness"].default_value = roughness
    return mat


def join(target, others):
    """Merge into `target`, which keeps its material slots first.

    Slot ORDER is not cosmetic: the Godot side matches surfaces by material name precisely so
    it does not depend on this, but a part whose body is slot 0 is the one a reader expects.
    """
    bpy.ops.object.select_all(action="DESELECT")
    for o in others:
        o.select_set(True)
    target.select_set(True)
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.join()
    return bpy.context.active_object


def smooth(obj, angle_degrees=38.0):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_smooth()
    # Blender dropped per-mesh auto-smooth in 4.1; the modifier is the supported replacement,
    # and the exporter applies it. Without it every chamfer reads as a faceted band.
    if hasattr(bpy.ops.object, "shade_auto_smooth"):
        bpy.ops.object.shade_auto_smooth(angle=math.radians(angle_degrees))
    return obj


def report(obj):
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print("%s: %d verts, %d tris, %d material slots"
          % (obj.name, len(obj.data.vertices), tris, len(obj.data.materials)))
    for i, slot in enumerate(obj.data.materials):
        print("  slot %d: %s" % (i, slot.name if slot else "<none>"))
    bb = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    print("  bounds x %.4f..%.4f  y %.4f..%.4f  z %.4f..%.4f" % (
        min(p.x for p in bb), max(p.x for p in bb),
        min(p.y for p in bb), max(p.y for p in bb),
        min(p.z for p in bb), max(p.z for p in bb),
    ))
    return obj


def export(obj, relative_path):
    out = os.path.join(os.getcwd(), *relative_path.split("/"))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    kwargs = {
        "filepath": out,
        "export_format": "GLB",
        "use_selection": True,
        "export_apply": True,
        "export_yup": True,
    }
    # The exporter's keywords move between releases, so anything it does not recognise is
    # dropped rather than taken down the whole build.
    allowed = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    bpy.ops.export_scene.gltf(**{k: v for k, v in kwargs.items() if k in allowed})
    print("wrote %s (%d bytes)" % (out, os.path.getsize(out)))
