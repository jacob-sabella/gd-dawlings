# Builds the patchbay jack socket and writes assets/hardware/jack.glb.
#
#     blender --background --python tools/blender/jack.py
#
# WHY THIS PART, FOURTH
#
# The plugs were made properly a while back -- tip, two insulating rings, sleeve, collar, a
# tapered boot -- and the thing they plug into was a torus with a flat dark disc behind it. A
# good plug entering a painted dot is worse than two rough parts, because the eye goes straight
# to the join.
#
# It is also the one place on the whole rig where a hand aims at something small. A jack is 18mm
# across and the target inside it is 11mm, so the mouth has to read as a HOLE from whatever
# angle the ray comes in at -- which a flat disc does not, and a chamfer does.
#
# THE BARREL IS NOT DECORATION
#
# A real jack is mostly behind the panel, and so is a seated plug: patch_cable.gd drives its
# tip 18mm in. The old bore was 8mm deep, so a plug's tip came out the back of the hole it was
# supposed to be inside and the bay only looked right from dead in front. The barrel here is
# 20mm with a back wall, which both swallows the plug and gives the bay something to look like
# from behind -- a row of barrels, which is what the back of a patchbay is.
#
# ORIENTATION
#
# Modelled axis-up (+Z), arriving axis-up (+Y), stood up by a 90-degree X rotation on the
# importing node: the knob's convention, for the same reason -- the axis is the panel normal,
# which is local Z. See _parts.py.

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _parts import (  # noqa: E402
    bevel_rings, clear_scene, cone, cut, cylinder, export, fuse, join, material,
    paint_faces, report, smooth,
)

# --- Dimensions, in metres. ----------------------------------------------------------------

## Unchanged: the bay laid its grid out around it, and the collision sphere is 1.5x this.
RADIUS = 0.0090

## The mounting nut, hexagonal because that is what a panel jack is held on by, and because six
## flats catch six different amounts of light -- which is most of what makes a small metal part
## look machined rather than drawn.
NUT_FRONT = 0.0012
NUT_BACK = -0.0012

BARREL_RADIUS = 0.0068
BARREL_BACK = -0.0205

BORE_RADIUS = 0.0056
BORE_BACK = -0.0197          # Leaves a back wall. A bore you can see through is a hole in the
                             # panel, and the room behind the patchbay is not always dark.

## The chamfered mouth. The whole reason a jack reads as something that accepts a plug, and the
## one feature that still reads when the ray comes in at an angle.
MOUTH_RADIUS = 0.0072
MOUTH_DEPTH = 0.0018

## The sleeve contact: a bright band part way down the bore. Visible only when you are looking
## more or less into the jack, which is exactly when a plain black tube stops being convincing.
CONTACT_Z = -0.0062
CONTACT_HEIGHT = 0.0011
CONTACT_RADIUS = 0.0053   # Inside the bore, so it reads as a ledge rather than vanishing
                          # into the wall it is supposed to be standing proud of.

OUT = "assets/hardware/jack.glb"


def build():
    clear_scene()

    nut = cone("Nut", 6, RADIUS, RADIUS, NUT_FRONT - NUT_BACK, (NUT_FRONT + NUT_BACK) * 0.5)
    barrel = cone("Barrel", 24, BARREL_RADIUS, BARREL_RADIUS,
                  NUT_FRONT - BARREL_BACK, (NUT_FRONT + BARREL_BACK) * 0.5)
    body = fuse(nut, barrel)
    body.name = "Jack"

    # Chamfer the nut's own edges BEFORE the bore goes through, while its rings are still
    # findable by height. Afterwards the front ring is an annulus the mouth cut in half.
    bevel_rings(body, [(NUT_FRONT, 0.00035, 2), (NUT_BACK, 0.00035, 1)])

    # Mouth first, then the bore straight down through it: a cone and a cylinder sharing an
    # axis, which leaves one continuous surface from the chamfer into the tube.
    cut(body, cone("Mouth", 32, BORE_RADIUS, MOUTH_RADIUS,
                   MOUTH_DEPTH, NUT_FRONT - MOUTH_DEPTH * 0.5 + 0.0002))
    cut(body, cylinder("Bore", BORE_RADIUS, (NUT_FRONT + 0.004) - BORE_BACK,
                       (0.0, 0.0, ((NUT_FRONT + 0.004) + BORE_BACK) * 0.5), vertices=32))

    contact = cone("Contact", 32, CONTACT_RADIUS, CONTACT_RADIUS, CONTACT_HEIGHT, CONTACT_Z)

    # Named, not ordered. hardware/part.gd matches on these; see docs/architecture.md.
    #
    # The contact gets the SAME material object as the nut, not a second one that looks alike.
    # Blender merges slots that reference one material, so the part exports as two primitives
    # instead of three -- and three would mean one more surface on every jack on the bay for a
    # band that is the same metal as the thing it sits inside.
    bezel = material("JackBezel", (0.56, 0.57, 0.60, 1.0), 0.30)
    for part in (body, contact):
        part.data.materials.clear()
        part.data.materials.append(bezel)
    body.data.materials.append(material("JackBore", (0.035, 0.038, 0.042, 1.0), 0.85))

    # The tube and its back wall go dark; the chamfered mouth stays metal, because the chamfer
    # is the bit that catches the light and tells you there is a hole here at all.
    paint_faces(body, 1, lambda c: c.length_squared - c.z * c.z < (BORE_RADIUS + 0.0001) ** 2
                and c.z < NUT_FRONT - MOUTH_DEPTH)

    jack = join(body, [contact])
    jack.name = "Jack"
    return report(smooth(jack, 30.0))


if __name__ == "__main__":
    export(build(), OUT)
