class_name Presentation
extends RefCounted

## Where a surface is anchored for the person looking at it.
##
## Three modes, and the reason there are exactly three is that there are exactly three answers to
## "what is this thing's position relative to?":
##
##   SCREEN  relative to the viewer's CAMERA. A flat panel on a monitor. Does not exist in the
##          room; cannot be walked around; is the right answer for the arrange timeline, which is
##          a 40-minute-long object and absurd as furniture.
##   ROOM    relative to the SHARED PHYSICAL ROOM. The console stands where everyone in that room
##          agrees it stands, whether they see it through passthrough or are just remembering it
##          is there. This is the mode that makes co-located mixing mean anything.
##   STUDIO  relative to the VIRTUAL SET. For a participant who is not in the physical room at
##          all: full VR, or a screen user flying around a rendered studio.
##
## A surface is written once and works in all three. It must never ask which mode it is in --
## if a surface needs to branch on mode, the thing that actually differs belongs in its mount or
## its affordances, not in it. The test: the same ConsoleSurface instance, reparented between a
## ScreenStage and a RoomAnchor at runtime, keeps working and keeps its state.

const Mode := {SCREEN = 0, ROOM = 1, STUDIO = 2}

const MODE_NAMES := {Mode.SCREEN: "screen", Mode.ROOM: "room", Mode.STUDIO: "studio"}

## What the person is looking THROUGH, which is a different question from the above. A participant
## in passthrough AR has ROOM surfaces around them and may still have a SCREEN surface on a
## tablet; a flat-screen user can be shown ROOM surfaces as a rendered room.
const Medium := {SCREEN = 0, AR = 1, VR = 2}


## The default mode for a surface class, given what the viewer is wearing.
##
## Defaults only -- a participant's LayoutProfile overrides any of it, and the point of the
## project is that they will. Encoded here so a fresh join is immediately usable instead of
## opening onto an empty room that needs placing by hand.
static func default_mode(surface_kind: StringName, medium: int) -> int:
	match medium:
		Medium.AR:
			# In AR everything belongs in the room, the timeline included: it used to start
			# pinned to the face as a screen, which in a headset is a flat sheet that follows
			# you about and hides the room (2026-10-13). The SCREEN key still puts it there.
			return Mode.ROOM
		Medium.VR:
			return Mode.STUDIO
		_:
			# On a monitor too the timeline is mounted in the room, on its stand, where the
			# rest of the gear is: pinned to the camera it covered the room it was meant to be
			# part of (2026-10-14). The SCREEN key still puts it on the glass, for whoever wants it.
			return Mode.STUDIO
