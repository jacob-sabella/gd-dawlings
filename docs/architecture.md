# Architecture

## The one idea

Three questions get asked about every object in this project, and the whole design is keeping
them from collapsing into each other:

| Question | Answer lives in | Scope |
|---|---|---|
| **What is this thing's value?** | Reaper | global, one truth |
| **Who may change it?** | `core/session` | one writer per session |
| **Where do I see it?** | `core/presentation` | **per viewer, and they disagree** |

The third one is the project. A normal DAW front-end has no answer to it because there is only
ever one viewer. Here there are four people in a room who legitimately want different answers,
and any design that forces agreement deletes the feature.

## Authority: Reaper is the truth, one process holds the pen

Reaper owns the mix. Everything in `ReaperState` is a cache of what arrived over the wire and
may be a frame stale. Nothing in the scene treats a local value as committed.

Exactly one process — the **host** — opens the OSC link. Everyone else is a **guest** whose
writes become *intents* forwarded to the host.

This is not an optimisation. If three headsets and a laptop each opened their own link, Reaper
would broadcast every change to all four, each would apply it locally, and a fader being dragged
would fight its own echo three times over. One link, one writer.

```
guest fader grab ──intent──▶ host ──OSC──▶ Reaper ──OSC──▶ host ──replication──▶ every guest
```

A guest's write goes out as the OSC address verbatim rather than as a hand-rolled action enum.
That keeps the guest path from drifting behind the host path: anything a control can express
locally is already expressible remotely, including FX parameters nothing in this codebase knows
the names of.

**The trust model is a trusted LAN, stated plainly.** Any peer that reaches the session may move
any fader. That is correct for four people in a studio and wrong for anything exposed past the
door.

## Presentation: three anchors, and a surface that never asks which

A **Surface** is a piece of hardware — console, rack, tape deck, patchbay. It reads
`ReaperState` and builds geometry. It is rebuilt when the project's *shape* changes (a track
added, an FX inserted) and **never** when a *value* changes, because rebuilding on value change
destroys and recreates a fader while a hand is holding it.

A surface hangs from exactly one of three anchors:

- **SCREEN** — a child of the viewer's camera. A panel. Where a timeline belongs: it is a
  40-minute-long object and absurd as furniture.
- **ROOM** — the shared physical frame, calibrated against two marks on the real floor. Stands
  still while you walk around it, and everyone in that room agrees where it is.
- **STUDIO** — the virtual set, for a participant who is not in the physical room at all.

**A surface must never ask which mode it is in.** If one needs to branch on mode, the thing that
actually differs belongs in its mount or its affordances. The test: the same `ConsoleSurface`
instance, reparented from a `ScreenStage` to a `RoomAnchor` at runtime, keeps working and keeps
its state. That reparent is a supported operation, not a trick — it is someone at the desk
pulling the console off their monitor and standing it in the room mid-session.

`SurfaceMount` is the only class that reads a `LayoutProfile`. That is what lets every surface
stay ignorant: a surface is a node, and a node's parent is not its business.

### What is shared and what is not

| | Shared | Why |
|---|---|---|
| Track values, FX, transport | ✅ | it is the mix |
| Who is here, head poses | ✅ | you need to see someone point |
| ROOM placement of a surface | ✅ | a fact about the room, not a taste |
| Which mode a surface is in *for you* | ❌ | **this is the feature** |

Replicating the last row would force one view on the room. The engineer at the desk has the
console as a panel on a 32:9 monitor while two people behind them see it as a physical object
between them, and nobody is wrong.

## Input: one grab contract

Mouse ray, tracked controller and pinching hand all arrive at `ControlAffordance` as the same
three calls. That is the only reason the console works identically on a monitor and in
passthrough. Giving the mouse its own path — because a mouse has a scroll wheel and a hand does
not — ends with two divergent control sets.

Grabbed values are **provisional**: while held, a control shows the hand's value and writes it,
and ignores what Reaper echoes about itself. On release it stops ignoring and snaps to whatever
Reaper settled on. That gap is deliberate — Reaper may clamp or quantise, and the fader should
end up where the mix really is.

Two people reaching for one fader: first hand wins, second is told no. Averaging two hands
produces a value neither person asked for.

## Furniture is not a surface

A surface exists because Reaper has tracks or plugins, and its size follows them. A stand, a
meter bridge, a trolley means nothing and is not drawn in ROOM mode at all, because the
participant already has real furniture. Mixing the two means a rack that cannot stand on the
floor without inventing a plugin to justify its legs.

## Things that are deliberately not done yet

See `docs/loop_backlog.md`. The short version: state replication between host and guests is
scaffolded (intents go up, nothing comes back down yet), and the arrange timeline does not
exist. Both are named rather than hidden.
