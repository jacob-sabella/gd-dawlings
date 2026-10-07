# Builds the 2U rack faceplate and writes assets/hardware/rack_panel.glb.
#
#     blender --background --python tools/blender/rack_panel.py
#
# WHY THE WHOLE PANEL AND NOT JUST THE EARS
#
# The backlog said "rack ears", which was the wrong unit of work. A rack is as tall as the
# session has plugins, so the RACK is procedural -- but a 2U panel is 19 inches by 2U in every
# session there has ever been. The panel is the thing that is always the same part; only how
# many of them varies. Same split as the reel: ask which half does not depend on the session.
#
# And the ears are not a separate thing to model anyway. That was the old code's mistake: it
# bolted two raised plates onto the face, and a real rack panel has no such plates. The ends of
# the panel ARE the ears, with oblong holes cut through them. Modelling the plates was modelling
# a misunderstanding.
#
# WHAT ACTUALLY READS
#
# The chamfer. A 1.2mm bevel is nothing up close and it puts a continuous highlight down 483mm
# of edge, which at rack distance is the single strongest cue that the thing is a folded metal
# panel rather than a rectangle. The slots and screws are the second cue and they are cheap.
#
# ORIENTATION
#
# Modelled standing, facing -Y, which is how it is used -- the fader cap's convention, and it
# needs no rotation on the importing node. See _parts.py for the mapping.

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _parts import (  # noqa: E402
    bevel_all, box, clear_scene, cut, cylinder, export, fuse, join, material, report, smooth,
)

# --- Dimensions, in metres. ----------------------------------------------------------------

WIDTH = 0.483            # Nineteen inches.
U = 0.0445
UNITS = 2
HEIGHT = U * UNITS - 0.002   # The 2mm is the gap between units in a filled rack. Without it a
                             # stack of panels is one tall slab.
DEPTH = 0.012

EDGE = 0.0012            # The chamfer. See above.

## Standard rack hardware: a 1/4 x 3/8 inch oblong, 0.625in in from the panel edge, so the screw
## has somewhere to move while you line a heavy box up with a threaded strip.
SLOT_INSET = 0.0159
SLOT_WIDTH = 0.0063
SLOT_HEIGHT = 0.0095
## Near the ends, which is where a panel is actually bolted -- the fixing has to be outboard
## of everything on the face or there is nothing holding the corners. The old code put them at
## half a U, which is a quarter of the way down a 2U panel and looks like two pairs of dots.
SLOT_ROWS = (HEIGHT * 0.5 - 0.0095, -(HEIGHT * 0.5 - 0.0095))

SCREW_RADIUS = 0.0048
SCREW_HEAD = 0.0017
SCREW_DRIVE = 0.0010     # The screwdriver slot across the head.

OUT = "assets/hardware/rack_panel.glb"


def slot_cutter(x, z):
    """A stadium: two round ends with a straight waist. One box and two cylinders, fused --
    not joined, because this gets subtracted and a difference against overlapping shells is
    the one boolean the solver reliably gets wrong."""
    reach = (SLOT_HEIGHT - SLOT_WIDTH) * 0.5
    body = box("Slot", (SLOT_WIDTH, DEPTH * 3.0, SLOT_HEIGHT - SLOT_WIDTH), (x, 0.0, z))
    for sz in (1.0, -1.0):
        end = cylinder("SlotEnd", SLOT_WIDTH * 0.5, DEPTH * 3.0,
                       (x, 0.0, z + sz * reach), axis="Y", vertices=16)
        body = fuse(body, end)
    return body


def screw(x, z):
    """A pan head with a driver slot across it.

    Built with `cylinder`, not `cone`, for the reason that cost the first attempt: `cone`
    stands along Z and this head's axis is Y -- out of the panel. A cone placed by its z
    argument came out as a flat disc lying IN the panel, which exported and rendered and was
    simply invisible, because a disc edge-on to the face is nothing at all.
    """
    front = -DEPTH * 0.5
    head = cylinder("Screw", SCREW_RADIUS, SCREW_HEAD,
                    (x, front - SCREW_HEAD * 0.5 + 0.0002, z), axis="Y", vertices=20)
    # Rounds the rim into something like a pan head, and takes the knife edge off the rest.
    bevel_all(head, 0.00055, 2)
    cut(head, box("Drive", (SCREW_RADIUS * 2.2, SCREW_DRIVE, SCREW_DRIVE),
                  (x, front - SCREW_HEAD + SCREW_DRIVE * 0.30, z)))
    return head


def build():
    clear_scene()

    panel = box("RackPanel", (WIDTH, DEPTH, HEIGHT), (0.0, 0.0, 0.0))
    # Chamfered before anything is cut, with bevel_all rather than bevel_rings: the edges that
    # matter here run in two directions, and bevel_rings only finds the horizontal ones.
    bevel_all(panel, EDGE, 2)

    heads = []
    for side in (1.0, -1.0):
        x = side * (WIDTH * 0.5 - SLOT_INSET)
        for z in SLOT_ROWS:
            cut(panel, slot_cutter(x, z))
            heads.append(screw(x, z))

    face = material("RackPanelFace", (0.17, 0.18, 0.20, 1.0), 0.55)
    metal = material("RackPanelScrew", (0.48, 0.49, 0.52, 1.0), 0.32)
    panel.data.materials.clear()
    panel.data.materials.append(face)
    for head in heads:
        head.data.materials.clear()
        head.data.materials.append(metal)

    whole = join(panel, heads)
    whole.name = "RackPanel"
    return report(smooth(whole, 36.0))


if __name__ == "__main__":
    export(build(), OUT)
