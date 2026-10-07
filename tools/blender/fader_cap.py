# Builds the channel fader cap and writes assets/hardware/fader_cap.glb.
#
#     blender --background --python tools/blender/fader_cap.py
#
# WHY THIS PART, SECOND
#
# The knob taught that authored detail only pays at the distance the part is actually read
# from (docs/loop_backlog.md). The fader cap is the opposite case to an FX-rack knob: it is the
# biggest control on the desk, it is the one a hand reaches for first, and at 22mm of travel it
# is the only thing on the console whose silhouette you can read from across the room. So the
# geometry goes into the silhouette -- the scooped waist and the two lips -- rather than into
# surface texture nobody can resolve.
#
# ORIENTATION
#
# The cap is modelled standing the way it looks when you face the console, which is also the
# way it arrives in Godot with NO rotation node at all (see _parts.py for the mapping):
#
#     Blender +X  ->  Godot +X   across the panel, the cap's width
#     Blender +Z  ->  Godot +Y   up the panel: the direction of travel
#     Blender -Y  ->  Godot +Z   out of the panel: the face a finger lands on
#
# So the touched face is at Blender -Y and the panel is behind at +Y, and the script reads as
# a front elevation of the part. The envelope is the box it replaces: 14 x 22 x 16mm centred on
# the node, because the strip, the meter and the slot were all laid out around those numbers.

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _parts import (  # noqa: E402
    bevel_all, box, clear_scene, cut, cylinder, export, join, material, report, smooth,
)

# --- Dimensions, in metres. ----------------------------------------------------------------

WIDTH = 0.014            # X, across the panel.
DEPTH = 0.0135           # Y, out of the panel. Under the 16mm the box had: a real cap is
                         # wider than it is deep, and the box read as a block.
HEIGHT = 0.022           # Z, along the travel.

EDGE = 0.00075           # The chamfer on everything. This is the part that reads.

## The finger scoop, cut with a cylinder lying across the cap.
##
## Radius is chosen so the scoop runs out BEFORE the ends: with a 16mm roller against an 11mm
## half-height the cut closes at about z = +/-7.4mm, leaving a 3.6mm lip at each end. Those
## lips are the whole point. A cap scooped end to end is a trough, and your finger slides off
## it; a cap with lips is a thing you can push and pull without looking at it.
SCOOP_RADIUS = 0.016
SCOOP_DEPTH = 0.0018

## Two grip ridges moulded across each lip. Cut rather than raised, because a raised ridge on
## the one surface a finger drags over is the first thing to wear shiny.
RIDGE_RADIUS = 0.0006
RIDGE_ROWS = (0.0086, 0.0103)

## The pale line across the waist. It is the thing you actually read a fader position from at a
## glance -- the cap's own silhouette against a dark slot is nearly invisible under low studio
## lighting, which is the lighting this scene has.
##
## It sits INSIDE the original face plane rather than proud of it, down in the scoop where the
## finger bridges across and never touches it. Same reasoning as the ridges, opposite solution.
LINE_HEIGHT = 0.0011
LINE_THICKNESS = 0.0013
LINE_SINK = 0.0004       # Behind where the unscooped face would have been.

OUT = "assets/hardware/fader_cap.glb"


def build():
    clear_scene()

    body = box("FaderCap", (WIDTH, DEPTH, HEIGHT), (0.0, 0.0, 0.0))
    bevel_all(body, EDGE, 2)

    face_y = -DEPTH * 0.5

    # Bevel first, cut second. Beveling a boolean result means beveling whatever slivers the
    # boolean left behind, which on a part this small collapses into garbage; cutting a
    # beveled box leaves clean sharp rims, which is what a moulded scoop actually has.
    cut(body, cylinder(
        "Scoop", SCOOP_RADIUS, WIDTH * 2.5,
        (0.0, face_y - SCOOP_RADIUS + SCOOP_DEPTH, 0.0), axis="X", vertices=48,
    ))

    for z in RIDGE_ROWS:
        for sign in (1.0, -1.0):
            cut(body, cylinder(
                "Ridge", RIDGE_RADIUS, WIDTH * 2.5,
                (0.0, face_y + RIDGE_RADIUS * 0.45, sign * z), axis="X", vertices=16,
            ))

    line = box(
        "Line",
        (WIDTH + EDGE, LINE_THICKNESS, LINE_HEIGHT),
        (0.0, face_y + LINE_SINK + LINE_THICKNESS * 0.5, 0.0),
    )
    bevel_all(line, 0.00016, 2)

    # The boolean modifier leaves an empty slot behind for every cutter it consumed. Harmless
    # in Blender, not harmless here: each one exports as its own primitive, and the Godot side
    # would hand it no override and draw it in whatever the importer guessed.
    body.data.materials.clear()
    body.data.materials.append(material("FaderCapBody", (0.17, 0.18, 0.20, 1.0), 0.52))
    line.data.materials.append(material("FaderCapIndicator", (0.86, 0.88, 0.91, 1.0), 0.40))

    cap = join(body, [line])
    cap.name = "FaderCap"
    return report(smooth(cap, 34.0))


if __name__ == "__main__":
    export(build(), OUT)
