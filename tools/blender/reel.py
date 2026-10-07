# Builds the tape reel flange and writes assets/hardware/reel.glb.
#
#     blender --background --python tools/blender/reel.py
#
# WHY THIS PART, THIRD
#
# It is the only thing in the room that moves continuously, which changes what the geometry is
# for. A knob is read at rest and a fader cap is read by its silhouette; a reel is read while
# it is turning, from the corner of your eye, across the room. What makes that legible is
# openings -- a smooth disc spinning is indistinguishable from a disc at rest. The old reel
# knew this and put three crossing bars on a plate. Three real windows do the same job and do
# a second one as well.
#
# WHAT IS NOT MODELLED HERE, AND WHY
#
# The tape pack. The flange is the same object in every session; the pack is a function of how
# far through the song you are, and it belongs on the side of the line that computes itself --
# the same rule that keeps the console procedural. Godot draws it as a disc BEHIND this flange,
# which is visible only through these windows. That is not a shortcut, it is what the windows
# are for on a real reel: you look through them to see how much tape is left.
#
# ORIENTATION
#
# Modelled axis-up (+Z), arriving axis-up (+Y) in Godot, stood up by a 90-degree X rotation on
# the importing node -- the knob's convention, for the same reason: the axis is the panel
# normal, which is local Z. See _parts.py for the mapping.

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _parts import (  # noqa: E402
    bevel_rings, clear_scene, cone, cut, cylinder, export, fuse, join, material, report,
    smooth,
)

# --- Dimensions, in metres. ----------------------------------------------------------------

RADIUS = 0.085           # Unchanged: the deck laid itself out around it.
PLATE = 0.0035           # Flange thickness.

RIM_INNER = 0.0790       # The rolled outer edge. A flat disc has no edge to catch light on,
RIM_DEPTH = 0.0085       # and a reel read from across a room is mostly its edge highlight.

WINDOWS = 3
## Sized to clear the collar on the inside and the rim on the outside. They overlap neither,
## because a window cut through a feature takes the feature's edge loop with it -- and the
## bevels that follow are found BY HEIGHT, so what they get instead is nothing at all.
WINDOW_RADIUS = 0.0240
WINDOW_CENTRE = 0.0525

HUB_RADIUS = 0.0190
HUB_DEPTH = 0.0130
## The three-slot keyway every NAB hub has. Cosmetic here, but it is the detail that makes the
## centre read as a machined part rather than as a red dot, and the centre is the one place on
## a spinning reel where the eye can actually resolve something.
HUB_SLOTS = 3
HUB_SLOT_WIDTH = 0.0062

## A raised collar where the pack sits down onto the flange, so the tape has a shoulder rather
## than floating on a plate.
COLLAR_RADIUS = 0.0245
COLLAR_DEPTH = 0.0055

OUT = "assets/hardware/reel.glb"


def build():
    clear_scene()

    plate = cone("Plate", 64, RADIUS, RADIUS, PLATE, 0.0)
    rim = cone("Rim", 64, RADIUS, RADIUS, RIM_DEPTH, 0.0)
    cut(rim, cylinder("RimBore", RIM_INNER, RIM_DEPTH * 2.0, (0.0, 0.0, 0.0), vertices=64))
    collar = cone("Collar", 48, COLLAR_RADIUS, COLLAR_RADIUS, COLLAR_DEPTH, 0.0)

    # Fused, not joined: the three overlap, and what comes next cuts holes through them.
    flange = fuse(fuse(plate, rim), collar)
    flange.name = "Reel"

    for i in range(WINDOWS):
        angle = (i / float(WINDOWS)) * math.tau
        cut(flange, cylinder(
            "Window", WINDOW_RADIUS, PLATE * 4.0,
            (math.cos(angle) * WINDOW_CENTRE, math.sin(angle) * WINDOW_CENTRE, 0.0),
            vertices=32,
        ))

    # Chamfer what survived. Done last and by height, because the booleans moved everything:
    # these are the faces the windows did not eat, and their rims are the whole read.
    bevel_rings(flange, [
        (RIM_DEPTH * 0.5, 0.0009, 2),
        (-RIM_DEPTH * 0.5, 0.0009, 2),
        (COLLAR_DEPTH * 0.5, 0.0007, 2),
    ])

    hub = cone("Hub", 32, HUB_RADIUS, HUB_RADIUS * 0.94, HUB_DEPTH, HUB_DEPTH * 0.5 - PLATE * 0.5)
    for i in range(HUB_SLOTS):
        angle = (i / float(HUB_SLOTS)) * math.tau + math.tau / 6.0
        # Reaching to the hub's own radius, so each cutter takes a bite OUT of the edge. The
        # first attempt placed them at 1.2x and they missed the part completely -- a boolean
        # that intersects nothing removes nothing and says nothing.
        reach = HUB_RADIUS
        cut(hub, cylinder(
            "Slot", HUB_SLOT_WIDTH * 0.5, HUB_DEPTH * 3.0,
            (math.cos(angle) * reach, math.sin(angle) * reach, 0.0), vertices=16,
        ))
    bevel_rings(hub, [(HUB_DEPTH - PLATE * 0.5, 0.0008, 2)])

    flange.data.materials.clear()
    hub.data.materials.clear()
    # Named, not ordered. hardware/part.gd matches on these strings; see docs/architecture.md.
    flange.data.materials.append(material("ReelFlange", (0.62, 0.63, 0.65, 1.0), 0.34))
    hub.data.materials.append(material("ReelHub", (0.60, 0.18, 0.16, 1.0), 0.48))

    reel = join(flange, [hub])
    reel.name = "Reel"
    return report(smooth(reel, 32.0))


if __name__ == "__main__":
    export(build(), OUT)
