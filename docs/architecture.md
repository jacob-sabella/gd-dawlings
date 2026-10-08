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

## Drawing budget: measured, not guessed

The headline client is a standalone passthrough headset, which has to draw this entire room
**twice** -- once per eye -- at 72Hz on a mobile GPU with no tether. That is a hard budget and
the project had never measured itself against it.

`tools/budget.sh` runs the real studio at several session sizes and prints what it drew.
`tools/budget.gd` is an autoload, inert unless `--budget` is passed, for the same reason the
capture harness is one: it observes whatever is running, so measuring needs no cooperation from
the scene and cannot accidentally measure a different scene from the one that ships.
`--tracks N` pads the offline stand-in, because the authored thirteen-track demo is readable and
is *not* what a session costs.

### What it found

Triangles were never the problem. The backlog had framed this as a vertex budget -- "3782 tris
per reel, ~100 knobs at 1088" -- and the measurement says otherwise: 203k triangles at 90 tracks
is nothing, while **7,600 draw calls** is far over a mobile budget. Those two readings have
opposite fixes, which is the entire argument for measuring before optimising.

The per-surface breakdown said where: **the VU meters were 37% of the whole studio**, because
there is one per strip and each was fourteen separate `MeshInstance3D` segments. Buttons were
the next block, at two meshes each across every strip.

Measured at **two camera poses**, which matters more than it sounds. The default framing fits
the console to the viewport, so a 90-track desk runs off both edges and more than half of it is
culled -- and the first version of this tool measured only that pose, reporting numbers
flattering by **2.3x**. In a headset you can turn your head, and there is no such discount.
`wide` stands far enough back to hold the whole room and is the worst case.

**Two numbers, and they are not the same number.** This took a microbenchmark to pin down, and
getting it wrong means optimising the thing that is not the problem:

| 400 boxes | draws | objects |
|---|---|---|
| loose, one shared material | 7 | 1,100 |
| loose, a material each | **1,100** | 1,100 |
| one MultiMesh | 3 | 3 |

`draws` is real draw calls. The renderer batches geometry that shares a material, so this
number is driven by how many DISTINCT materials are in frame, not by how many objects there
are. `objects` is per-instance submission, one per visible thing per pass, batched or not --
CPU-side work that only instancing removes. On a standalone headset the CPU is as likely to be
the wall as the GPU, so both are worth reading.

The practical consequence: **a MultiMesh over geometry that already shared a material does
nothing for `draws`**. It still collapses `objects`. That is exactly what happened to the
patchbay's jacks, which all wear the same two finishes.

Draw calls at the wide pose, as the MultiMesh conversions landed:

| tracks | original | meters | + buttons | + plate, chip, slot | + lettering | + timeline |
|---|---|---|---|---|---|---|
| 13 | - | 1,596 | 1,124 | 1,014 | 821 | **407** |
| 24 | - | 2,066 | 1,430 | 1,221 | 951 | **449** |
| 48 | - | 3,116 | 2,102 | 1,677 | 1,239 | **545** |
| 90 | **7,600** | 4,911 | 3,295 | 2,492 | 1,757 | **727** |

The timeline step is the largest single one and it is the batching table above doing the work
rather than instancing: every item block and lane chip was tinted with its own track's colour,
which made each one its own material and therefore its own unbatchable call. Collapsing ~180
materials into two banks is worth far more than collapsing 282 objects into 22, and both
happened at once.

Banking the patchbay's 180 jacks then moved `draws` not at all and `objects` from 4,919 to
3,845 at 90 tracks, for the reason above. Primitives halved too, 350k to 171k, because a
shadow-casting jack was being submitted to both passes.

A 90-track console is now 42 meshes where it was 1,032, and the patchbay 55 where it was 235.

### The moving parts, which were the last 180

Knobs and fader caps were left loose for a long time on an argument that turned out to be
wrong: a bank is filled once, and these move. The transform is per-instance, so moving one is
a `move_slot` -- the same buffer write a Node3D would have done for its own transform. The
only real requirement is that the slot be rewritten from the control's own place in the tree
rather than from a formula, because a knob sits under a strip under a panel under a tilted
surface and a second definition of where it is would drift against the first.

That left 180 one-off `MeshInstance3D`s on a 90-track desk, which is what came off:

| 90 tracks, wide | draws | objects | frame ms |
|---|---|---|---|
| before | 820 | 2,293 | 1.28 |
| knobs and caps banked | 830 | **1,225** | **0.95** |

`draws` going UP by ten is the batching table above behaving exactly as it says: two new banks
of a two-surface part is a handful of new materials in frame, and the 180 objects they replace
were already sharing materials with each other, so there was never a `draws` win available
here. `objects` nearly halves and the frame drops a quarter, which is the win that was.

Those figures are from the tick that made them and are not what the room costs now, which is
worth saying because for five ticks afterwards they were quoted as if they were. Re-measured
from scratch, 90 tracks wide: **964 draws, 1,359 objects, 0.99ms**. The drift was not the
instancing coming undone; it was five ticks of things being added, which is what adding things
costs. The mult, the rack rule, the tape path, the timeline stand, then three looms and three
lamps.

The last two of those were measured against their own baseline rather than against the number
above, by building the previous commit in a worktree and running the same tool: 899 -> 964
draws for three looms and three lamp stands, +65. Twelve of those sixty-five were a mistake --
the strain-relief collars at the ends of each loom had been left casting shadows while the
cable itself did not, so the only part of a cable in the shadow map was the one part that is
not the cable. Predicted from the counter, confirmed by re-running: 976 to 964.

What is pinned, in `_test_the_studio_fits_in_a_frame`, is not a draw count -- a number that
only a benchmark can produce does not belong in a unit test. It is the SHAPE: the room's
dressing costs the same at 64 tracks as at 13, because there are three looms because there
are three machines. A loom per send would not look wrong in a screenshot of thirteen tracks.

The cap is still a node even when banked -- an empty one -- because the slide emitter parents
to it so the sound comes from where the cap is, and a bank slot is a row in a buffer with
nowhere to hang a speaker.

Checked for correctness two ways. A pixel diff of the console before and against after came
back identical apart from a tape reel that had turned between captures: banked and loose
geometry land in the same place at the same angle. And `_test_a_banked_control_still_moves`
mounts one banked and one loose control under a tilted, offset, rotated parent and asserts
they agree at three values -- then separately asserts the cap crossed its full 100mm and the
knob its full 270 degrees, because two frozen caps agree with each other perfectly.

Rack knobs are deliberately NOT banked. They are created lazily as a plugin's parameters
arrive and as pages change, which is after the surface would have committed; sizing a bank for
the worst case and hiding the unused slots is a different piece of work, and the rack's mesh
count does not grow with the session anyway.

### Lettering: the largest cost, and nothing to batch it with

What was left after the banks was mostly not meshes: 517 `Label3D`s. An **ablation** settled
what they cost -- hide every label, re-read the counters, same scene otherwise:

| 90 tracks, wide | draws | objects | frame ms |
|---|---|---|---|
| as built | 2,492 | 3,845 | 1.82 |
| labels hidden | 1,757 | 3,110 | 1.12 |

**30% of the drawing and nearly 40% of the frame, for text.** And by the batching table above
it is the one thing a MultiMesh cannot touch: every label carries its own glyph texture, which
makes every label its own material, which makes it an unbatchable draw call by construction.

The fix is not to draw it smaller or less often but **not to draw it when nobody could read
it**. A console strip's name is a 10mm cap, which subtends about 5.6/d pixels on an 850px
viewport at 75 degrees -- under five pixels by 1.2m, and unreadable in a screenshot taken
there. The cost, meanwhile, only arrives as you stand BACK and more of the room enters frame.
Those are the same axis pointing opposite ways, so there is a free trade in it: `Lettering`
gives every label a visibility range ending where its own cap height falls below 0.31 degrees
(three pixels of cap -- not a taste judgement; a capital three pixels tall cannot carry a
glyph), with a fade band entirely outside the readable range so nothing dims while being read.

Done through `GeometryInstance3D.visibility_range_end`, so the culling happens on the rendering
server with no per-frame script, and **per camera** -- which is what makes it right in a
headset, where two eyes and a moving head decide independently.

At 90 tracks wide this is **2,492 -> 1,757 draws and 1.82 -> 1.38ms**, and at a working
distance nothing changes at all. The test walks the whole built studio and insists every label
has a range, because the helper being correct is worth little if a new label forgets to call
it.

Measured on a desktop GPU, so the absolute frame times are not the headset's. The **slope** and
the **breakdown** are hardware-independent, and they are what the tool is for.

### Two monitors that lied

This tool first reported `Performance.TIME_PROCESS` at **177ms per frame** on a scene the wall
clock timed at 1.85ms -- a hundredfold error that would have been a 6fps crisis that does not
exist. `Engine.get_frames_per_second()` went the same way: it averages over a wall second while
this samples forty frames, so on a fast scene it was still reporting the startup.

Both were removed. The raw `delta` was right. A measuring tool should report as few numbers as
it can defend, because a wrong number in it is worse than a missing one -- it is the number that
gets acted on.

### The meter is one object

`VUMeter` is a `MultiMesh`: one draw call for the whole ladder, with segment colour travelling
as per-instance data. That is why it carries a shader at all -- four lines, unshaded, which an
LED should be anyway (a little lamp adds light, it does not take it) and which renders
identically under `forward_plus` and `mobile`, as every material here must.

**A MultiMesh is invisible to the test suite.** Its instance buffer lives in the rendering
server, and the headless server is a stub: `set_instance_color` writes quite happily and
`get_instance_color` returns black forever. Converting any widget to a MultiMesh makes it
untestable unless the decision is lifted out of the buffer -- which is why `segment_colour` and
`segment_y` are static functions. `_paint` is the one line that cannot be checked.

### Repetition is one object: MeshBank

`MeshBank` is the meter's trick generalised, because a console is mostly repetition and almost
all of it was being drawn one box at a time. A surface builds a bank, each widget `claim`s a slot
and gets a transform and a colour back, and the whole population is one draw call.

`MeshBank.parts` **duplicates** the material it is given and switches on
`vertex_color_use_as_albedo`, which is not an optimisation -- it is the only reason per-instance
colour does anything on a `StandardMaterial3D`. The first version did neither, and silently drew
every instance in the shared albedo; nobody noticed, because the only caller at the time claimed
everything white. Duplicated because `Materials` hands out cached singletons.

Banks are **optional**, and that is what keeps the abstraction honest. A `PanelButton` with no
bank assigned builds its own two `MeshInstance3D`s exactly as before, so a button in a patchbay,
a test, or a scene nobody has converted yet still works. Only `ConsoleSurface` -- which already
knows it is about to build ninety of everything -- hands out banks.

`Materials.lamp_colour` exists so that "what colour is a lamp that is off" has one definition
rather than one per widget. It also forced a real trade-off into the open: a banked lamp is
unshaded, so an unlit lamp is a flat fraction of its lit colour instead of a lit surface in a
dark room. That reads *better* at a distance -- an off button is legible rather than black -- and
the honest cost is that **an unlit lamp no longer dims when the room does**. For a console face
that is the right side of the trade; for anything meant to disappear in darkness it would not be.

### A lamp and a colour chip are not the same thing

Both are unshaded patches of per-instance colour, which made it tempting to drive them the same
way. They must not be, and the A/B that proved it is worth keeping:

A lamp is an **indicator**. All it says is on or off, so pushing it to 2.4 and letting the
channels clip costs nothing -- a blown-out red mute light still reads as a red mute light that
is lit, and the clipping is most of what makes it read as emitting.

A colour chip is an **identifier**. The only thing it says is *which track this is*, and
clipping is precisely the operation that destroys that. Reaper's palette is largely pastel, so
at the lamp's gain every chip came back as the same pale wash and a desk of 32 strips went back
to being 32 identical strips -- visible immediately in a before/after crop, and not something
the draw-call number would ever have mentioned.

So `Materials.chip_colour` scales by `CHIP_GAIN` **or by whatever headroom is left, whichever is
less**. Scaling every channel by one factor preserves hue exactly for any input, where a flat
multiply rotates it the moment one channel clips.

`MeshBank.of` banks an **authored part** -- a jack, and in principle a knob or a fader cap --
rather than a plain box. A MultiMeshInstance3D is a `GeometryInstance3D`, not a
`MeshInstance3D`, so it has no per-surface override: its only material lever is
`material_override`, which paints every surface alike and would flatten exactly the detail the
part was modelled for (a jack is a brushed bezel around a dark bore). So the materials are
baked into a **duplicate** of the mesh. The duplicate is the whole trick: `Part.mesh()` caches
one Mesh per asset and hands it to everyone, and painting the shared copy would repaint every
loose jack in the studio. `Part.paint_for` is the shared rule, so a banked jack and a loose one
cannot end up different.

**A per-instance colour is linear; `albedo_color` is sRGB.** This is not a detail and it cost a
visible regression: the timeline's item blocks came back pale and flat because the same `Color`
means something lighter when it travels as instance data than when it is set on the material.
`parts()` therefore sets `vertex_color_is_srgb` as well as `vertex_color_use_as_albedo`, so
that claiming `x` into a bank built from `material(WHITE)` matches `material(x)` drawn loose.
Caught by an A/B screenshot; invisible to every counter.

The headless-testability problem above applies doubly here, so `MeshBank` **retains** its
`_transforms` and `_colours` after `commit()`. They are a few hundred bytes per bank and they are
the only way the suite can see what a bank was asked to draw.

### Scrolling is not a change of shape

The timeline used to call `mark_dirty()` when the overview scrubber moved, which meant a full
rebuild on the next frame: every lane bed, every lane label, every flag and every item torn
down and recreated, once per frame, for the whole of a drag. Survivable at twelve lanes and not
at ninety.

The split is between what the WINDOW decides and what the PROJECT decides. Lanes, their labels
and their flags are the project's shape and do not move when you scroll. Only the items and the
ruler's numbers depend on the window. So a scroll now writes transforms into two MultiMeshes
and rebuilds the ruler -- a bounded handful of nodes whatever the track count -- and a rebuild
is reserved for the project actually changing.

The items bank is sized to EVERY item in the project, not to the visible ones, because capacity
is a fact about the project and visibility is a fact about the window. Each layout packs the
visible items into the low slots and calls `show_first(n)`; the rest keep whatever they last
held and are not drawn. Resizing the buffer per scroll would be the node churn this removed,
wearing a different hat.

## A control that cannot reach everything must say so

Two places now have the same shape, and it is worth naming because the failure mode is
identical and silent in both.

A control surface protocol streams a BANK of tracks, not a project, so a 90-track session
arrives as tracks 1..64 and the rest never appear. A rack faceplate fits eight knobs, so a
plugin with thirty-two parameters shows eight and the rest never appear. In both cases nothing
errors, nothing is logged, and the gear looks like complete gear for a smaller thing than the
one that is actually loaded. That is the worst shape a missing feature can take: you do not go
looking for what you have no reason to believe exists.

So both carry a readout that states the whole, not just the part -- `17-32 OF 90`, `9-16 OF 18`
-- and two buttons to move. Both build the control ONLY when there is more than fits, because a
panel carrying two dead buttons invites the question of what they are for. Both light a button
to mean "there is something that way", because an unlit button at the end is the only thing
that distinguishes the end from a button that has stopped working.

And both defer a change made while a hand is on a control. On the console a strip must not
change which track it means while someone holds its fader; on a rack unit a knob must not
change which parameter it means while someone turns it. Applying immediately sends the new
target the old hand position -- a value nobody asked for, written somewhere nobody was looking.
It is deferred rather than refused, because a press that does nothing is its own bug and the
hand on the control is usually the other hand.

The rack's version of this is why `RackUnit._param_for` is read at the moment of the turn
rather than captured when the knob was built. A captured index would keep writing page one
forever, and would look exactly like a knob that does nothing.

## The hardware has to be able to say what the software means

A patchbay is the clearest case, and it broke before anyone noticed. Reaper's send model lets
any number of tracks send to one track, so four tracks into a reverb return is ordinary. The
bay drew that as four cables ending at the destination's input jack -- four plugs in one bore.
At the zoom the studio is usually photographed at it looked like a tidy fan. It was found by
cropping a screenshot, not by the suite, which had only ever counted cables.

The rule is that a physical metaphor is a constraint, not a decoration. One jack takes one
plug. If the data says something the hardware cannot, the answer is more hardware, not a
sprite that cheats -- because the cheat is invisible until the moment someone leans in, and
the whole premise of the project is that leaning in is allowed.

So fan-in grows a **mult**: a short strip of jacks bussed together, hung under the bay on two
straps, packed left to right in a row so any number of multed returns at any fan-in still
lays out. Each source gets its own way; one trunk cable leaves the mult for the return's
input. Every bore holds exactly one plug, and the extra hardware the routing needs is visible
as extra hardware. A single send stays a single cable -- a mult for one source would be
hardware invented to solve a problem nobody has.

The invariant is now pinned directly rather than through a proxy: `_test_one_jack_takes_one_plug`
collects BOTH ends of every cable in the bay and asserts no two are closer than a 1/4" sleeve
is wide. It does not know about mults. It would catch any future way of drawing two plugs in
one hole.

## A cable is a route and a constraint, and they are different statements

Every cable in this room is swept by `hardware/cable_sweep.gd`, and there are two kinds of
cable that agree on nothing else. A patch cable is 4mm across, spans twenty centimetres and
ends in a plug. A floor loom is 18mm across, spans two metres and ends in a gland on the back
of a chassis. What they share is the frame: parallel transport, carried forward by the minimal
rotation between tangents, because a naive cross-product frame flips where the tangent passes
vertical -- the bottom of a patch cable's sag, and both ends of a loom's drop.

The looms are what makes the patchbay's labels true. The bay draws a cable per send, which is
a claim about signal; the loom is the permanent run from each machine to the bay, which is the
claim that makes a jack labelled RHODES have anything to do with the Rhodes. Before them the
bay was a prop. They are still scenery in the sense that no DAW state decides where they go,
and the comment at the top of `gear_loom.gd` says so.

Shaping them turned out to be the interesting part, and it split cleanly in two.

A loom's ROUTE is a list of places the cable has to be: out of the gland, down to the floor,
along it, up again. That is a Catmull-Rom and not a Bezier, because a Bezier's control points
are places a curve merely leans towards, and a cable that only leaned towards the floor would
hover above it. The knots are centripetal -- spaced by the square root of chord length --
because a loom's spans are wildly unequal, eight centimetres out of a gland then a metre and a
quarter across the floor, which is the case uniform knots handle worst. Measured on the same
loom with everything else held still, uniform overshot 108mm above the gland it was arriving
at; centripetal, 29mm.

The FLOOR is not another waypoint. It is a constraint, and it says something different: not
where the cable goes but how low it may get on the way. `CableSweep.rest_on` applies it, with a
parabola tangent to both the free curve and the level so the touchdown is C1. That boundary is
why the remaining 39mm of dip was left to the floor rather than tuned out of the spline -- 39mm
is where a slack cable genuinely wants to go, and the reason it does not go there is not the
maths.

The test that holds all of this (`_test_a_loom_lies_on_the_floor_and_misses_the_furniture`)
pins the spline's contract, the contact, and the real looms against the meter-bridge crossbar
they all three ran through on the first attempt. The bridge is a pair of constants the
furniture and the test both read, so moving the bar moves the test with it.


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

## The gear goes around the person, not around the room

For six ticks this was a museum of hardware you walk around. Every ergonomic problem it had
descended from that one decision: gear at fixed room positions, at heights sized for an average
standing adult, read off 3mm silkscreen, operated by fine dragging. The tell was a single line
in the renderer -- `const MIN_CAP_ANGLE := 0.0054` -- one person's eyesight baked in as a global
constant, with nothing anywhere able to ask for a different one.

The deeper failure is worth stating plainly, because it is the thing a 3D DAW has to answer for:
a screen DAW shows ninety channels with zero travel, and this room made you walk. Space is a
cost before it is a feature. `FocusRig` is the payment. In a volume, "bring this to me" costs
nothing and loses nothing: the focused surface comes to a measured working distance at the size
your eyes want, and the others do not minimise or go behind a tab -- they arc out to the edge of
vision, full size, still live, one head turn away. No screen can do that.

Three pieces, and the split between them is the design:

* **`Ergonomics`** is a description of a PERSON -- eye height, reach, how far the neck turns,
  how small a letter they can read, how much motion they tolerate. It owns no nodes. Everything
  that used to be an assumption about the reader is now a field on it, and `Lettering.reader`
  points at one, so turning text up buys *distance* rather than merely enlarging glyphs.
* **`BodyFrame`** is where that person is. Position follows the head immediately; yaw follows
  only past a deadzone, and then chases the deadzone EDGE rather than the head. Content on the
  head cannot be looked away from and is nauseating in about a minute; content in the room is
  what made you walk. This is the thing in between, and the damping is an exponential close so
  the comfort setting means the same at 72Hz and 120Hz.
* **`FocusRig`** decides where surfaces go in that frame, and is deliberately not a Mode.
  `Presentation.Mode` says where a surface LIVES and is a preference someone keeps; focus is
  what they are doing this minute. Conflating them would hand someone back a session with the
  compressor still in their face from last Tuesday.

### Three constraints of three different kinds

The placement maths is four lines, and getting it wrong three times was entirely about treating
the constraints as the same kind of thing. They are not:

* fitting inside the eye-and-neck sweep is a **lower** bound -- any closer and it overflows,
* reading the smallest label on it is an **upper** bound,
* and reach is a **preference**, which the other two clamp.

Treating reach as a third hard constraint is what put a 1.2m rack 35cm from the viewer's face.
It is not true that a surface must be within arm's length, only that you would like it to be; a
tall rack cannot be both reachable and visible, and the real resolution is that you lean in,
exactly as at a real rack. The sweep bound also has to be taken on BOTH axes against DIFFERENT
angles, because a neck yaws much further than it pitches. Asking only about width is what let a
narrow rack claim it could come close.

When the two bounds genuinely cross, `too_big_to_place` says so instead of returning a
compromise nobody can use. It is true of the FX rack today, at default settings -- 0.98m to fit
the sweep against 0.96m of legibility -- and mostly because the rack carries six empty blanking
units it inherited from being a real 19" rack in a real room. That is the correct report: it is
a layout problem, not a placement one, and the answer is to bank, arc or trim the surface.

### What a render cannot check

Half of this round's bugs were invisible in a photograph and found only by printing the
arrangement in body space: parked surfaces at 132 degrees (behind the shoulders, where "visible
at a glance" is false), parked surfaces nearer than the focused one, and two sign conventions
for "bearing" disagreeing so the arc was mirrored. All three rendered as a plausible room.

The one that cost the most was the opposite failure -- a render that looked *unchanged*. Focus
ran at `_ready`, before any surface had built its geometry, so every surface measured as an
empty box, took the fallback distance and was never corrected. `--focus` appeared to do nothing
at all, and the first three diagnoses were of the placement maths, which was fine. Surfaces are
now re-placed on every `rebuilt` signal, which is required anyway: a console that gains twenty
tracks is a different size, and a distance derived from the old one is wrong.

### Furniture is not instrument

`Surface.compact` asks a surface to drop the parts of itself that only make sense as furniture.
A rack in a room is a 19" box with blanking panels in the empty U, because that is what a rack
IS and a part-filled bay with holes in it reads as a modelling mistake. A rack held at your
hands is not furniture, has no empty U to explain, and those blanks were a metre of nothing
between the viewer and the controls -- they were most of the reason the FX rack reported itself
as impossible to place at all. Compact, the same rack is 0.53 x 0.59m, needs 0.52m of standoff
against 0.96m of legibility, and lands exactly at working distance.

The surface cannot decide this for itself, because it cannot know whether it is standing in a
room or floating at someone's fingertips. The rig that summoned it can, so the rig sets it.

Trading height for width is the specific move, and it is not arbitrary: a neck yaws much
further than it pitches, so height is the expensive axis and width is the cheap one. The rack
picks rows per bay to come out roughly square -- `p = sqrt(n * BAY_SPACING / unit_height)`, from
setting `(n/p) * BAY_SPACING = p * unit_height`.

### Two bugs that only a measurement finds

**Deferred frees are still in the tree.** `queue_free()` runs at the end of the frame, so the
geometry a rebuild replaces is still a child for the whole of that rebuild. Anything measuring
the surface in that window measures both builds at once -- and the focus rig re-places a surface
the instant it emits `rebuilt`. A rack trimmed from twelve U to six measured as twelve U
forever, and the trim looked like it had silently done nothing. `_clear_built` now removes
before it frees.

**A comfortable drop is not comfortable at the edges.** `gaze_down` is applied to the centre of
a surface, which is right for a panel and wrong for a column: the rack at a 20-degree drop put
its own bottom row 50 degrees below the horizon, outside any cone a person can look through
without moving their head. The drop now yields to the surface -- `drop_for` straightens a tall
surface up until its far edge is back inside the sweep, which for something as tall as the sweep
itself means dead ahead.
