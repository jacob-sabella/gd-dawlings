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

## Geometry: computed by default, authored where bevels matter

Almost every shape in here computes itself at load. That is not laziness -- the console is as
wide as the project has tracks and the timeline is as long as the song, so most of the hardware
is genuinely a different object for every session and could not have been modelled in advance.

The exception is the part that is always the same part. A knob is a knob whatever the track
count is, and what makes it read as moulded plastic rather than as a cylinder is almost entirely
its chamfers -- the one modelling operation that is painful to write against `ArrayMesh`. Those
are authored in Blender.

What is committed is the **script**, not a `.blend`:

```
tools/blender/build.sh          # every part -> assets/hardware/*.glb
```

Each part is one file in `tools/blender/` holding its own dimensions and its own reasons;
`_parts.py` holds the shared scaffolding and, once, the Blender-to-Godot axis mapping that
every part has to get right.

The `.glb` is committed too, so a clone does not need Blender -- but the shape lives in numbers
next to every other dimension in the project, and changing it is an edit rather than an
appointment with somebody's workstation.

Two rules on the Godot side, both of which exist because an asset can fail in ways procedural
geometry cannot:

- **Match surfaces by material name, never by index.** The exporter decides what order the
  primitives come out in. An index that quietly swaps paints the body white and the indicator
  black, which is a part that looks fine and is wrong. `Part.build()` is the only loader, so
  the rule is kept in one place and the authored material names are the contract.
- **Keep a procedural stand-in.** Every control falls back to the shape it had before, so a
  missing or unimported asset is a plainer desk rather than a desk with invisible controls on
  it. `_test_knob_is_the_moulded_part` is what notices the desk is running on stand-ins.

Authored so far: the knob, the channel fader cap, the tape reel flange, the patchbay jack
socket, and the 2U rack faceplate.

The reel is where the line between the two kinds of geometry is sharpest, and worth reading as
the example. The flange is the same object in every session, so it is authored -- including its
three windows, which exist because a smooth disc spinning is indistinguishable from a disc at
rest. The **tape pack** is not in the asset: how much tape is on a reel is a function of how
far through the song you are, so Godot draws it, as a disc behind the flange that is visible
only through those windows. That is also what the windows are for on a real machine.

Which makes the transport say something it could not say before. It was three booleans and a
float -- rolling, armed, where -- and now the reels carry *how far through*, readable from
across the room without reading anything. The pack grows as a square root, because tape winds
by area; `TapeDeck.song_fraction()` returns -1 rather than guessing when no backend has said
how long the project is, and the reels then sit half wound and make no claim.

## What OSC cannot say, and where the answers come from

Three facts about a project exist only in ReaScript, and all three have visible consequences on
the gear:

| Fact | Why OSC cannot say it | What it changes |
|---|---|---|
| **track colour** | no message for it, at all | a colour chip is how you find the kick on 32 identical strips |
| **folder structure** | no message for it, at all | a 32-strip desk with no breaks is a wall |
| **a send's destination INDEX** | OSC gives a *name* | two tracks called "Verb" made the patchbay guess |

`ReaperBackend` polls `GetProjectStructure` on an **eight-second** clock against the timeline's
two, because the two change on completely different schedules: the arrangement moves on every
drag of every item, while colour, folders and routing change when a person reaches for them. The
request asks for the **light** form -- plugin names and bypasses but no parameter values -- since
OSC already streams those continuously and re-reading a thousand of them on the slowest channel
in the system is pure duplication.

Nothing in that handler writes volume, pan, mute, solo or FX parameters, even though the bridge
reports some of them. OSC is the authority on those at 30Hz, and painting an eight-second-old
copy over the top would make every fader stutter backwards once per poll.

All three land on addresses the wire already understands (`/track/N/colour`, `/track/N/folder`,
`/track/N/send/M/dest`), so they ride the normal replication stream and a guest gets them
without a second code path. Two of those are reaper-3d's own namespace rather than Reaper's --
`mix_wire.gd` had defined `colour` in advance for exactly this.

### A send points at two things, and they disagree

`SendState` carries both `dest_name` and `dest_track`, and `resolve()` prefers the index. That
is not belt-and-braces: with the bridge loaded the bay is *exact*, and without it the bay is
still roughly right rather than empty. The name is what OSC gives and it is ambiguous the moment
a project has two tracks called "Verb" -- which is completely normal, and which the old
name-only lookup resolved silently and wrongly, forever.

### The parent heads its group

Reaper stores `I_FOLDERDEPTH` as a **delta** per track, not a level; the level is a running sum
in track order, which is what `MixState.folder_level` works out.

The console's group breaks are **not** "the level changed", which is the obvious rule and the
wrong one. A folder's parent sits at the *outer* level -- that is what makes it the parent -- so
a level-change rule cuts between the bus and its own children and leaves the bus lumped in with
whatever preceded it. On the demo project that put the VOX bus in with the guitars. The rule is
instead: a group starts where a track **opens** a folder, or where the level **drops** back out
of one.

`ConsoleSurface._group_breaks` recomputes this in one pass rather than calling `folder_level`
per strip, which would make laying out a 90-track desk quadratic. That optimisation is only safe
while it agrees with the readable definition, so the suite checks the two **against each other**
rather than checking either alone.

## Audio: the gear, not the mix

**The mix is not ours to play.** Reaper is already running, through monitors, in the room this
is running in. Rendering the same audio here would put a second copy of a critical listening
signal a few milliseconds behind the first, which is a comb filter rather than a feature. So
nothing in this project touches programme audio, and that is a boundary rather than a backlog
item.

What was missing is the sound the *hardware* makes, and in a headset that is not decoration. A
fader you have grabbed and a fader you are about to grab look nearly identical, there is nothing
under your fingers to tell them apart, and a tracked hand is off by a centimetre about as often
as it is on. Sound is the only channel left that can say "contact" at the instant contact
happens -- and because it is positional, it also says *which one*.

### Synthesised, for the same reason everything else is computed

`core/audio/foley.gd` builds every sound from arithmetic into an `AudioStreamWAV`. No samples are
committed. A `.wav` sitting next to all of this would be the one asset nobody could read or
adjust, and the alternative is a few lines per sound that anyone can tune.

It also makes the suite possible, which matters more than it sounds like. The two ways
synthesised audio goes wrong are both silent to a reader and obvious in a buffer:

- **a loop that steps at the seam** -- the last sample far from the first, which is a click
  repeating at the loop rate; inaudible as a defect, impossible to ignore as a rhythm.
- **a one-shot cut off before it has decayed** -- the same click by another route.

`tests/run_tests.gd` checks both on every sound, plus clipping, DC, duration and that the energy
is at the front where an attack belongs. `tools/foley_preview.gd` writes the five sounds out as
playable `.wav` files and one `.svg` of their waveforms, because the only review that finally
counts on a sound is listening to it.

### Where the sounds attach

`ControlAffordance` owns the *mechanism* -- a `_foley_contact()` virtual, played on grab -- and
deliberately not the *sound*. Every control gets contact feedback for free without growing its
own player, but a base class that invented one generic noise for everything would be worse than
silence: it would make four different objects feel like one object. A fader cap does not click
and a patch point does not tick, so those return null and say what they do elsewhere.

| Sound | Fires on | Why there |
|---|---|---|
| button click | `PanelButton` grab | two transients, because a snap-action switch has two |
| knob detent | every notch **crossed**, not every frame changed | so a slow turn ticks slowly and a fast one ticks fast |
| fader slide | held, gain from smoothed speed | continuous, so it needs a loudness rather than a moment |
| plug seating | only the send that actually took | a sound on a refused patch would say the cable is in |
| reel motor | `DAW.state.playing`, faded | same rule as the spin: it cannot outlive a stop |

The two continuous sounds are owned by the object making them, because they have a state and
that object is what knows it. The fader's `_process` is off until a hand arrives, so ninety
strips cost nothing when nobody is touching them, and its slide player is parented to the *cap*
-- emitted from the strip origin it would sit at the bottom of the throw no matter where the
hand was, which on a desk three faders wide is audibly the wrong fader.

## Things that are deliberately not done yet

See `docs/loop_backlog.md`.
