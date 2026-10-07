# Co-location: how several headsets agree where the console is

## The problem

Two people in passthrough headsets standing in the same studio **do not share a coordinate
system**. Each runtime picked its own origin when it started — somewhere near where that headset
was switched on, facing wherever it happened to face. Put a console at `(0, 0, -1)` in each and
it appears in two different places a metre or two apart.

Which breaks the entire premise. When one person points at the kick fader, the other has to see
them pointing at the kick fader.

## The fix: two pieces of tape

Both people mark **the same two physical points** — opposite corners of a desk, two bits of tape
on the floor — in the same order. The first is the session origin; the direction to the second
is session +X.

That is enough to pin the frame completely, because **gravity supplies the third axis for free.**
Every XR runtime knows which way is down to within a fraction of a degree, so only position and
*yaw* are actually unknown, and two points on a plane determine exactly those.

```
            physical room                      session space
                                               
     ╔═══════════════════════╗                      +Z
     ║                       ║                       │
     ║   ✕ B ─────────▶      ║                       │
     ║   │                   ║            A ─────────┼────────▶ +X
     ║   ✕ A                 ║         (0,0,0)       │     B (span, 0, 0)
     ║                       ║                       
     ╚═══════════════════════╝         everyone who marked the same
                                        tape gets the same frame
```

No marker tracking, no cloud anchors, no vendor lock-in. It works for a screen participant too:
they type the distance between the two points and get a studio laid out to the real room's
dimensions.

## Two details that are not obvious

**The span vector is flattened against gravity before anything else.** The two marks are never at
exactly the same height — a hand placing them is a couple of centimetres out. Letting that tilt
reach the frame would rotate the whole studio a degree or two about the horizontal, which over a
2m console is several centimetres of disagreement at the far end. There is a test for this.

**The measured span is the honesty check.** Everyone marking the same tape should agree on how far
apart it is. If two headsets disagree by more than 3cm — about the width of a fader cap, so
beyond it two people reaching for the same control are reaching for different ones — one of them
has drifted. The right response is to re-mark, not to average two wrong frames together.

A disagreeing participant is still calibrated, and told. Refusing would leave them with no frame
at all, which is worse than a slightly wrong one.

## Session space vs world space

| | |
|---|---|
| **World space** | this headset's own tracking origin. Private, arbitrary, different for everyone. |
| **Session space** | the shared frame. Where ROOM-anchored surfaces and head poses live. |

`RoomAnchor` **is** `world_from_session`: parent a console at session `(0,0,0)` and it lands on
the first piece of tape. Head poses are published in session space, never world space — that
distinction is the whole of this document.

## Mixed rooms

Not everyone in a session is in the same physical room, and some are in no room at all.

- **AR, in the room** — marks the tape, gets the shared frame, sees hardware standing in it.
- **VR, elsewhere** — no tape to mark. Adopts the session frame outright via
  `adopt_virtual_frame(span)` and stands in the same layout, rendered as a virtual set.
- **Screen** — same, through a camera.

All three see the console at the same session coordinates. Only the two in the physical room are
also seeing the real floor it is standing on.

## Status

The two-point calibration maths is implemented and tested. What is **not** yet built is the
in-headset gesture for placing the marks — right now `mark_origin` / `mark_forward` are called
with points, and nothing calls them from a controller. See `docs/loop_backlog.md`.
