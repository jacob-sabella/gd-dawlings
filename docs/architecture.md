# Architecture

## The one idea

Three questions get asked about every object in this project, and the whole design is keeping
them from collapsing into each other:

| Question | Answer lives in | Scope |
|---|---|---|
| **What is this thing's value?** | the DAW | global, one truth |
| **Who may change it?** | `core/session` | one writer per session |
| **Where do I see it?** | `core/presentation` | **per viewer, and they disagree** |

The third one is the project. A normal DAW front-end has no answer to it because there is only
ever one viewer. Here there are four people in a room who legitimately want different answers,
and any design that forces agreement deletes the feature.

## The DAW is a backend, not a hard-coded protocol

Nothing in `hardware/` has ever heard of Reaper. A fader calls `DAW.set_track_volume(i, v)`;
`DAW` is an autoload holding exactly one **`DAWBackend`**, and the backend decides whether that
becomes an OSC packet, a ReaScript file drop, or a write straight into a cache.

```
hardware/ ──verb──▶ DAW (autoload) ──▶ DAWBackend
                                        ├── ReaperBackend   OSC + ReaScript bridge
                                        └── OfflineBackend  synthetic mix, no DAW running
```

`core/daw/` holds the four pieces that are not Reaper's:

| File | Job |
|---|---|
| `daw_backend.gd` | the contract — the command vocabulary, capability queries, replication plumbing |
| `mix_state.gd` | `MixState`: tracks, sends, FX, master. A cache, never the master copy |
| `mix_wire.gd` | the address vocabulary ⇄ `MixState`, in both directions |
| `daw.gd` | the autoload: one backend, one forwarding verb per command |

Three things make the seam real rather than decorative:

**Verbs, not protocol.** The contract is `set_track_volume`, `set_fx_param`, `transport_play`,
`create_send` — things a DAW does. A backend that speaks MIDI, or Live's UDP, or a plugin host's
C API implements the same twenty methods and every surface works unchanged.

**Capabilities are asked, not assumed.** `DAW.can(Capability.ROUTING)` is false until Reaper's
ReaScript bridge is actually writable, and false forever for a backend that has no way to patch.
The patchbay greys itself out rather than silently dropping writes. Same for `RECORD_ARM` and
`FX_PARAM_NAMES`.

**The taper is the backend's.** `taper_to_db` is virtual, because a fader's 0..1 travel maps to
dB differently in every DAW, and baking Reaper's curve into the mesh would make every other
backend read a lie on the dB caption.

`OfflineBackend` is not a mock. It is the thing that runs when you launch reaper-3d with no DAW
open, it drives real meters, and it is what the test suite and every screenshot in `shots/` are
built on. Keeping it a peer of `ReaperBackend` rather than a `if not connected` branch is what
keeps the abstraction honest — a seam with one implementation is just indirection.

## Authority: the backend is the truth, one process holds the pen

The DAW owns the mix. Everything in `MixState` is a cache of what arrived over the wire and
may be a frame stale. Nothing in the scene treats a local value as committed.

Exactly one process — the **host** — opens the backend. Everyone else is a **guest** whose
writes become *intents* forwarded to the host.

This is not an optimisation. If three headsets and a laptop each opened their own link, the DAW
would broadcast every change to all four, each would apply it locally, and a fader being dragged
would fight its own echo three times over. One link, one writer.

```
guest fader grab ──intent──▶ host ──▶ backend ──▶ DAW ──▶ host ──replication──▶ every guest
```

A guest's write goes out as a verb from `DAW.COMMANDS` with its argument list, not a hand-rolled
action enum per control. That keeps the guest path from drifting behind the host path: anything
a control can express locally is already expressible remotely, including FX parameters nothing
in this codebase knows the names of. It also means a guest never needs to know which backend
the host opened.

**The trust model is a trusted LAN, stated plainly.** Any peer that reaches the session may move
any fader. That is correct for four people in a studio and wrong for anything exposed past the
door.

## Presentation: three anchors, and a surface that never asks which

A **Surface** is a piece of hardware — console, rack, tape deck, patchbay. It reads
`MixState` and builds geometry. It is rebuilt when the project's *shape* changes (a track
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

A surface exists because the project has tracks or plugins, and its size follows them. A stand, a
meter bridge, a trolley means nothing and is not drawn in ROOM mode at all, because the
participant already has real furniture. Mixing the two means a rack that cannot stand on the
floor without inventing a plugin to justify its legs.

## Replication: the address space is the wire format

State reaches guests as `(address, args)` pairs in **the vocabulary `MixWire` defines**. That is
the whole trick: a guest has exactly one code path for "state arrived", the host has one for
"state left", and a field added to `MixState` replicates the day it is *parsed* rather than
the day someone remembers to add it to a serialiser.

The vocabulary is Reaper-shaped — `/track/3/volume` — by inheritance rather than by coincidence,
and that is fine: it is now *reaper-3d's* vocabulary, and a non-Reaper backend translates into
it the same way `ReaperBackend` does. A guest can therefore be fed by a host running any
backend without knowing which.

The host buffers changes keyed by address, so repeats collapse, and flushes at 20Hz. The buffer
is split in two because the halves need opposite guarantees:

| | Carries | Delivery | Why |
|---|---|---|---|
| **Durable** | names, volumes, mute/solo, FX params, colour | reliable | edge-triggered — a dropped packet loses that change *permanently* |
| **Volatile** | meters, playhead | unreliable ordered | level-triggered — arrives again in 50ms anyway |

Getting that split backwards is invisible on loopback and ruinous on real wifi: either names
queue behind stale meter readings, or they are dropped and never resent.

A joining guest is sent a full snapshot, reliably, before any delta reaches it. Without that it
would start empty and grow a channel each time someone touched a fader, never showing the tracks
nobody happened to touch — the deltas are edge-triggered, so there is no second chance.

**One address was never Reaper's at all.** `/track/N/colour` predates the split, because Reaper's
OSC surface has no colour message and a colour chip is how you find the kick on a desk of 32
identical strips. It rides the same stream as everything else.

### Testing it needs two processes

A single run is always its own authority, so every replication bug is invisible until there are
two of them. `tools/session.sh` brings up a headless host and a guest — which is also the shape
a studio would actually use, with the authority on a machine in a rack.

## Things that are deliberately not done yet

See `docs/loop_backlog.md`.
