# Builds the panel knob mesh and writes assets/hardware/knob.glb.
#
#     blender --background --python tools/blender/knob.py
#
# WHY A SCRIPT AND NOT A .blend
#
# Everything else in this project computes its own geometry at load: the console is as wide as
# the track count, the timeline is as long as the song. A .blend committed next to that would be
# the one shape in the scene nobody could read, diff or adjust -- and the first time a knob
# needed to be 2mm smaller it would need Blender open on somebody's desk.
#
# WHY BLENDER AND NOT MORE GDSCRIPT
#
# The bevels. A knob reads as moulded plastic rather than as a cylinder almost entirely through
# its rounded edges, and chamfering an edge loop is the one modelling operation that is
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
# z -0.0065 to +0.0065 about the node origin. A hundred of these were already laid out by a
# console that measured itself around the old numbers.

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _parts import (  # noqa: E402
    bevel_all, bevel_rings, box, clear_scene, cone, export, join, material, report, smooth,
)

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

OUT = "assets/hardware/knob.glb"


def knurl(obj):
    """Push alternating angular columns of the skirt outward.

    Done on the mesh data rather than with a modifier because the displacement has to be an
    exact function of the vertex's own angle: a noise or wave texture would wander off the
    column boundaries and leave flutes that do not close at the top and bottom rings.
    """
    for v in obj.data.vertices:
        column = round(math.atan2(v.co.y, v.co.x) / (2.0 * math.pi) * (FLUTES * 2))
        if column % 2:
            continue
        radius = math.hypot(v.co.x, v.co.y)
        if radius < 1e-6:
            continue
        scale = (radius + FLUTE_DEPTH) / radius
        v.co.x *= scale
        v.co.y *= scale


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
    bevel_all(indicator, 0.00018, 2)

    body.data.materials.append(material("KnobBody", (0.14, 0.15, 0.17, 1.0)))
    indicator.data.materials.append(material("KnobIndicator", (0.86, 0.88, 0.91, 1.0)))

    knob = join(body, [indicator])
    knob.name = "Knob"
    return report(smooth(knob))


if __name__ == "__main__":
    export(build(), OUT)
