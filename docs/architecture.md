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
                                              └── GodotBackend  the same mix, actually played
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
The patchbay says READ ONLY on its own face rather than silently dropping writes. Same for
`RECORD_ARM` and `FX_PARAM_NAMES`. The stand-in backend keeps its own sends, so it can patch.

**The patchbay reads left to right.** FROM (every track's output) down the left, TO (every
track's input) down the right, and every send a cable across the gap between them. A row is the
thing you aim at -- chip, name, jacks -- and a cable goes in the row's free jack; each row has one
more jack than the busiest row needs, so no two plugs share one. Drag a row across to patch, drag
a plug to another row to re-patch, pull it off to unplug, scroll it for the level. A removed send
travels as `/track/N/sends` (the count), which is the only address that can say a send is gone.
The bay stands in its own cabinet on the floor, off to the right of the desk.

**The taper is the backend's.** `taper_to_db` is virtual, because a fader's 0..1 travel maps to
dB differently in every DAW, and baking Reaper's curve into the mesh would make every other
backend read a lie on the dB caption.

`OfflineBackend` is not a mock. It is the thing that runs when you launch dawlings with no DAW
open, it drives real meters, and it is what the test suite and every screenshot in `shots/` are
built on. Keeping it a peer of `ReaperBackend` rather than a `if not connected` branch is what
keeps the abstraction honest — a seam with one implementation is just indirection.

### The built-in engine: `GodotBackend`

`--built-in` swaps the stand-in for one that makes sound, for anyone without a DAW. It is the
offline backend's own mix, with its state, undo and replication, turned into Godot's
`AudioServer` (`core/built_in/`):

- **A bus per track**, named `R3D <n>`, sending to its folder's bus or to `R3D Master`, so a
  folder fader moves its children the way it does in Reaper. Slot 0 is a panner and the rack
  starts at slot 1. Volume, mute and pan go straight onto the bus.
- **Solo is solo-in-place**: a soloed track keeps the folders above it and the returns it sends
  to audible. `audible()` is the rule, and is tested on its own.
- **The rack is Godot's own effects** (`FXCatalogue`): EQ6, compressor, reverb, delay, chorus,
  low-pass, drive, phaser, limiter. Each knob is a `Param` with a range and unit, and
  `read_fx_param_text` answers in those units, the way Reaper answers with the plugin's text.
- **A send is a second player** on the same part, routed to the return's bus, at the send
  level times the fader.
- **The song is synthesised, not shipped** (`DemoSong`): ten parts, each four bars at 32kHz,
  rendered on worker threads and cached in `user://built_in` per tempo. A tempo change renders
  a new set and swaps all of it at once, so no part plays at the old tempo against the new.
  Each part starts at the song position modulo its loop, only under its track's items, and is
  nudged back if it drifts more than 60ms from the transport.
- **Meters are the buses' real peaks**, through the same fader law.
- **Guests hear the master bus**: an `AudioEffectCapture` on `R3D Master` is the session's
  `MixSource` (`BusSource`), resampled to the wire's 48kHz if a sound card insists on another
  rate. `tools/session_probe.sh --built-in` checks the guest hears it, 26 to 33ms behind. It runs
  the host on a real audio driver into the null sink, because headless Godot's dummy driver mixes
  in 85ms lumps.

Not there yet: recording, your own audio files, playing MIDI items through a synth, and
third-party plugins, which Godot cannot host.

### dawkit: the engine is its own product

The DAW engine is being built as **dawkit**, a separate repository (`~/Projects/dawkit`,
proprietary, so it can be sold on its own), not as part of this game. It is a Godot addon with
its own tests (`tools/test.sh` there) and no reference to anything in dawlings. This repository
holds it as a git submodule at `vendor/dawkit`, with a symlink `addons/dawkit` pointing at the
addon inside it. `vendor/.gdignore` keeps Godot from scanning dawkit's own project and tests a
second time.

The direction of dependency is one way. The game adapts to dawkit in
`core/built_in/project_bridge.gd` (`ProjectBridge`), and dawkit never adapts to the game:

- `ProjectBridge.capture(backend)` turns the stand-in's or the built-in engine's mix into a
  `DawKitProject`: tapers to dB, pan 0..1 to -1..1, Reaper's folder depth deltas to parents,
  bank indices to track ids ("t1"...), the engine's effect kinds, and clips with fades, gain,
  files and notes.
- `ProjectBridge.load(project, backend)` does the reverse. It replaces the whole project,
  refuses one whose references are broken (`DawKitProject.problems()`), drops undo history,
  lets the backend rebuild (`OfflineBackend.project_loaded`; the built-in engine lays its buses,
  effects and players down again), and emits `project_replaced`. Session answers that by
  sending every guest the new project whole, as it does for a guest that has just joined.
- Captured, loaded and captured again, a project is `same_as` the first. Track and master
  levels are read from the cache's own decibels, because taper to dB and back is not exact.
  Send levels are rounded to a millionth of a dB.

Saving and opening (`core/built_in/project_files.gd`) is the game's half of dawkit's DAWproject
support. A take is copied into the file. A demo-song item, which has no file, has its track's
part rendered to a WAV once, and each item becomes a looped clip of it, starting where the song's
loop had reached, because the engine plays a part locked to the bar grid and not to the item. So
another DAW opening the file hears the song. Opening unpacks the media to `user://open_project`,
and since the game names a clip's file by name alone (a guest never learns the host's paths), the
engine is given a map from name to file (`OfflineBackend.set_media`). A guest may press save,
and the host saves where the project already is. Only the host chooses a path, opens or starts a
project. Reaper saves its own project through its own "Save project" action and does nothing
else from here.

The controls: a SAVE key on the timeline beside SPLIT, Ctrl+S, and a PROJECT section on the
session panel (`scenes/session_panel.gd`), which has Save for everyone and Save As…, Open… and
New for the host when the DAW owns its files, with a native file dialog. Every save is told to
the whole room: a guest's save goes to the host as an intent and becomes
`Session.save_project_for(name)`, and the host's own save comes out of `DAW.project_saved`, so
hardware never names Session. Opening and starting a project are announced by
`Session.tell_room`. A refusal is a toast for the person who asked, and nobody else.

Recording on the built-in engine: the DAW cannot record its own inputs (`RECORDS_OWN_INPUTS` is
false), so the host's microphone goes through the same recorder as a guest's (`GuestAudio` with
`for_host`, which is `Session.host_audio`). Its take is timed against `Session.host_heard`, the
playhead less the output's latency, and kept by Session's take path from the host's own id, so it
is written, placed and announced exactly as a guest's would be. The host's keys are the same: GuestMidi
plays for such a host (`host_records`) and times notes by `host_heard`. The engine's metronome
(dawkit's `DawKitMetronome`) plays into the master, which is what the host and its guests both play to.

Sound files come in through `DAW.import_audio` (`core/daw/audio_import.gd` chooses the name and
the track). dawkit's `DawKitAudioFile.bring_in` reads the file and puts it in the takes folder as a
WAV the engine plays, and it is placed with `insert_audio_take` like a recorded take. So it saves
into a DAWproject like one, and plays on Reaper through the bridge.

What moves into dawkit next, step by step: the file format, then the mixer and transport
(today `GodotBackend` here), then everything after.

### Its file format: DAWproject

The built-in engine saves and opens **DAWproject** (`.dawproject`,
[github.com/bitwig/dawproject](https://github.com/bitwig/dawproject), MIT): a zip of
`project.xml`, `metadata.xml` and the audio files, defined by a published XSD. It is the only
open project format that several major DAWs read and write directly. We do not invent a format of
our own. Whatever DAWproject cannot hold goes in an extension namespace inside the same
`project.xml`, and the list of what another DAW loses is kept here.

Who can open what a game session saves (checked 2026-10-09):

| DAW | DAWproject | How |
|---|---|---|
| Bitwig Studio 5.0.9+ | native, both ways | File > Open / Export |
| Studio One 6.5+ (Fender Studio Pro) | native, both ways | |
| Cubase 14+ / Nuendo 13+, Cubasis, VST Live | native, both ways | |
| Tracktion Waveform, n-Track | native | |
| **Reaper** | **not native** | [ProjectConverter](https://github.com/git-moss/ProjectConverter) (Jürgen Moßgraber; .rpp to and from DAWproject, a separate program). [DawVert](https://github.com/SatyrDiamond/DawVert) also converts. |
| **Ableton Live** | **none** | Ableton has announced nothing, and there is no .als writer we could rely on. A project goes to Live as stems (the mixdown step renders them). |
| Logic Pro | none | stems, as for Live |

So "transferable" means: native in Bitwig, Studio One and Cubase; Reaper through
ProjectConverter, which is free and open source; Live and Logic by stems only. A Reaper host can
already save a project through Reaper itself. The DAWproject path is for the built-in engine.

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
| The mix's sound | ✅ to guests who ask | they are not in the room with the speakers |
| Who is here, head poses, pointers, holds | ✅ | you need to see someone point |
| Which bank the desk shows | ✅ | the host has one Reaper link, so one bank |
| ROOM placement of a surface | ✅ | a fact about the room, not a taste |
| The venue, plugins out on stands, where every stand and trolley is, where the desk stands | ✅ the host's | one room; a guest asks (rolls the rack, pulls a plugin) and is shown the host's answer, and cannot change the venue. Its own room waits in its profile for when it is on its own (`Session.room`, `Studio.apply_room`) |
| Which mode a surface is in *for you* | ❌ | **this is the feature** |

**The room is predicted, not waited for.** A guest's push, pull or dock happens on its own screen
at once and is sent to the host as a numbered ask (`Session.ask_room`). The host's room comes
back carrying the last number it answered for each guest (`"acks"`); `Studio.apply_room` puts
the host's room up and then the guest's still-unanswered moves back on top, so a room published
a moment before the ask arrived never flicks a stand back. Once answered, the room is the truth:
whatever the host would not do goes back -- the rollback. While a stand is being pushed its place
streams to everyone a few dozen times a second, unreliably on its own channel
(`Session.send_motion`), and everyone else's copy rolls after it on the trolley's own spring
(`Trolley.roll_to`) rather than being put down. Only positions: the mix is never predicted, and
nothing here touches audio.

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
cabinet, a trolley means nothing and is not drawn in ROOM mode at all, because the
participant already has real furniture. Mixing the two means a rack that cannot stand on the
floor without inventing a plugin to justify its legs.

## Replication: the address space is the wire format

State reaches guests as `(address, args)` pairs in **the vocabulary `MixWire` defines**. That is
the whole trick: a guest has exactly one code path for "state arrived", the host has one for
"state left", and a field added to `MixState` replicates the day it is *parsed* rather than
the day someone remembers to add it to a serialiser.

The vocabulary is Reaper-shaped — `/track/3/volume` — by inheritance rather than by coincidence,
and that is fine: it is now *dawlings's* vocabulary, and a non-Reaper backend translates into
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

`tools/session_probe.sh` is the scripted version: a host ("Ada") and a guest ("Grace") check
the roster, colours, heads, snapshot, an intent round-trip, hold refusal, release, the goodbye
and the guest's fall back to solo. `--reaper` runs the host against the rig's real Reaper.
`tools/session_shot.sh` opens two visible windows, has the host drag a fader while the guest
aims at another, and photographs both sides.

## Multiplayer: people in the room, not just values on the wire

Replication moves the mix between processes. Everything below is about the *people*: who is in
the session, where they are looking, and what they are holding. All of it lives in
`core/session/` (the `Session` autoload and the `Presence` node the studio builds). Nothing in
`hardware/` knows any of it exists. `tools/verify.sh` enforces that.

### The roster is the host's word

The host owns the participant list and broadcasts it whole, as rows of
`[peer_id, name, medium, colour_index]`, whenever anyone joins, leaves or renames. A guest never
edits its own copy. Colours come from an eight-entry palette, handed out first-free by the host,
so two people never share a colour, and a colour is kept for as long as its owner is in the
session.

### Presence travels as a control key, never as a position

Each participant sends their head pose and pointer at 20Hz, unreliable and ordered. The
pointer is **a control key plus an offset on that control**, not a world point. Everyone's
layout is their own (see *What is shared and what is not*), so Ada's KICK fader may be in front
of her and on a monitor for Grace. A world-space beam would point at empty air. A beam aimed at
"KICK LEVEL, 3cm up its throw" lands on the KICK fader wherever Grace has put it.

`ControlAffordance.network_key()` is the title by default. A surface whose title is not unique
overrides it (the timeline answers `TIMELINE`).

The head is sent in session space, relative to the room anchor. A desktop participant's head
is their camera.

An avatar stays hidden until its participant has been heard from. A headless host has no head.

Everyone is drawn as a big blue ghost: a lathe-turned body (modelled at 1.3m, drawn at 0.72 of
that, so the dome is a hand above a standing person's head and the hem is at desk height) with a scalloped, drifting hem, two oversized heavy-lidded eyes and no arms: a pair of cartoon gloves (`Glove`) float at its sides. It turns with its owner's yaw, leans a little and rolls its pupils with their pitch, blinks, and bobs. The blue is shared; who it is shows in the glow round its edge, its name tag, its cuffs, its pointer beam and the rim on what it holds. The right glove flies to whatever they point at -- fingertip on the spot if it is within `Avatar.REACH`, otherwise as far as it goes, with the beam carrying the rest -- and grips what they hold. Every move is a spring: flights overshoot and settle, a grab squashes it, a let-go boings, and the left glove jumps and makes a fist while the right one holds. Your own reflection's gloves follow your own cursor, so the mirror shows you grabbing too. `tools/glove_preview.tscn` renders the gloves acting out a grab, frame by frame. When its owner goes quiet the glow fades and the lids droop.
Its body also hides within 0.6m of your own eye, because somebody standing inside you is
noise, not information.

**Mirrors.** Every venue has a mirror, framed in its style (walnut in the studio, neon on the
grid, chalk in the chalk zone), on the left wall behind the treatment. It is a true planar
mirror: a second camera at your eye reflected through the glass, with an off-axis frustum fitted
to the glass and its near plane on it, rendered only while the glass is in view (`Mirror`,
`core/venues/mirror.gd`). You see yourself because Presence keeps a ghost of you at your eye on
render layer 20, which only mirror cameras draw. The panels that ride in front of your face in
screen mode are on layer 19, which mirrors never draw, so they do not cover your reflection.
In a headset the mirror is rendered from the centre eye, so it is flat rather than stereo. This
is where customising your ghost will go.

**The wardrobe.** Beside every mirror hangs a small board (`Wardrobe`, styled by the venue's
`_dress_wardrobe`) with a row each for body colour, eyes, hat and gloves, stepped with ◀ ▶
buttons; you watch the change happen in the glass. A look (`GhostLook`) is a Dictionary of small
indices, cleaned on the way in from anywhere, so a peer with more hats than you never breaks
you. `Session.set_look` keeps it in `user://ghost_look.cfg` and passes it on the way a rename is:
a guest re-introduces itself in `_hello`, a host rebroadcasts, and the roster's fifth column
carries everyone's (a four-column roster from an older host means the default look). Your
session colour still glows round your edge, tints your hat and cuffs and colours your beam, so a
look changes what you wear, never who you read as. The wardrobe's buttons are `personal()`:
never claimed as holds, never published as what you point at. `--ghost hat=4,eyes=1` dresses a
run without saving, and `--fresh-layout` captures never save a look either.
`tools/look_preview.tscn` lines up every hat.

### One hand per control, decided by the host

Two people dragging one fader produce a value that belongs to neither of them. Grabbing a
control therefore **claims** it from the host, which keeps a `holds{key: peer}` table and
grants claims first-come. Everyone else is told; their copy of the control gets `claimed_by`.
It then refuses grabs and nudges, wears the holder's colour on its rim, and still follows the
holder's values as they arrive. A losing claim gets `hold_refused` and the local grab is let
go. A participant who leaves frees every hold they had.

### A control ignores its own echo

After release, a control ignores incoming values for 450ms (`SETTLE_MSEC`). Before that, the
round trip through host and DAW delivered stale values that snapped a released fader back a
step. Remote values land again once the echo window is over.

### Surfaces never rebuild under a hand

A rebuild frees every control a surface built. If one lands mid-drag, the hand is left holding
nothing. `Surface._process` therefore holds a dirty rebuild until no control on that surface is
held. This was found on a live host: Reaper restates the project size a few times a second, and
each restatement was announced as a bank change, cutting a drag off about a second in.
`MixWire` now announces a bank change only when the size actually changes.

### Finding a session, and leaving one

- **Discovery.** A host broadcasts a small JSON beacon every second on UDP 7333, to
  255.255.255.255 and to 127.0.0.1. The session panel (**M**) lists what it hears with a Join
  button. You can also join by address.
- **Leaving.** A host that ends the session sends a `_goodbye` and keeps polling for 0.3s so
  the goodbye is not overtaken by the disconnect. Quitting the app does the same.
- **Falling back.** A guest that loses its host, for any reason, returns to solo on its own
  backend and says why with a toast. It does not sit staring at a frozen mix.

Volatile state goes out in parcels of at most 1100 bytes. An unreliable packet over the MTU is
dropped whole, and a 40-track meter frame was over it.

### A code at the door

A host can ask for a session code (**Ask for a code** in the panel, or `--code`). Four
characters, drawn from an alphabet with nothing that can be misread across a room: no 0/O,
1/I/L, 5/S, 2/Z or 8/B. It is compared without regard to case or spaces, because it gets read
aloud.

The code is a door, not encryption. What it buys depends on the host deciding who is in the
room, not on what the transport happens to deliver:

- A new connection is **pending**, not a participant. Its first `_hello` carries the code. A
  wrong code gets a reason (`_turned_away`) and is hung up on 0.3s later, so the explanation
  arrives before the disconnect. Silence for 6s is also hung up on.
- Until it is admitted, nothing reaches it: no snapshot, no roster, no presence, no audio
  ticket. Everything the host says goes to `_audience()`, the admitted guests, never to
  `.rpc()`, which would reach every socket.
- Guests do not talk to each other directly. `server_relay` is off. A guest's presence goes to
  the host, which forwards it as `_presence_of(peer_id, ...)` to the others. A guest at the door
  therefore cannot reach the people inside, and nobody can send a pose under another's id.
- Intents, claims and releases from anyone not admitted are dropped.

The beacon says `locked`, and the nearby list shows "code needed".

### Hearing the mix from another room

A guest who is not in the host's room hears nothing, because Reaper plays to the host's
speakers and nowhere else. With the mix carried to them, a guest can do more than watch
faders: they can mix. With the latency low enough, they can play along.

**Measured: 46ms from the host's speakers to the guest's** (`tools/audio_latency.sh`, on one
machine). It is measured, not estimated. A click track goes to the host's tap and, at the same
time, straight into a null sink. The guest plays into the same sink, and the gap between the two
clicks in a recording of it is the delay a person hears. Over a wired LAN the network adds well
under a millisecond. Wifi adds its jitter, which the buffer measures and absorbs.

Where the 46ms goes:

| Stage | ms | Why that much |
|---|---|---|
| Host capture | ~5 | `PULSE_LATENCY_MSEC=3` on the capture stream only. Godot's default fragment is 1024 frames, which is 21ms. |
| Packet | 2.7 | 128 frames of 16-bit stereo, 528 bytes, under any MTU. |
| Jitter buffer + generator queue | ~15 | Godot's mixer takes 512 frames at a time; the queue has to hold one gulp plus the measured lateness. |
| Guest output | ~20 | `audio/driver/output_latency=5`. 3 measured no better. |

**Getting the sound (host).** The DAW plays to the OS, so `MixTap` (core/audio) adds a
listener. On PipeWire it creates a virtual source, `dawlings_tap`, and links Reaper's output
ports into it alongside whatever they already feed. Nothing is unlinked, so the engineer's
monitoring is untouched. It is not the default sink's monitor: that would carry this app's own
fader clicks and every notification chime to every guest. Linux with PipeWire only; elsewhere
the host is told in plain words why guests will not hear anything, and the session carries on.
The capture is read with `AudioServer.get_input_frames`, never an `AudioStreamMicrophone`, so
the host never plays its own mix back on top of itself.

**Sending it (`MixFeed`).** Its own UDP socket and its own threads. ENet is serviced once a
frame on the main thread, which would put up to 16ms of jitter on every packet, and every
millisecond of jitter is a millisecond of buffer. The threads wake every half millisecond.
Admission rides on the session's: an admitted guest is handed a random ticket over the reliable
channel. The audio socket ignores anything without one. The guest speaks first, so the replies
come back through its own NAT. A keepalive every 250ms carries a timestamp the host echoes,
which times the round trip on the path the sound actually takes.

**Playing it (`JitterBuffer`).** Two disagreements, each with its own answer:

- **Jitter.** The target depth is the measured *lateness* (how much later the latest recent
  packet was than the earliest), plus one mixer gulp. It is not the average jitter, because a
  buffer sized for the typical packet runs dry on the untypical one.
- **Drift.** Two sound cards are two clocks; 0.1% apart is a second an hour. The read rate is
  bent by at most 0.2% (about three cents, inaudible), steering the combined depth of jitter
  buffer and generator queue to the target. Tested over twenty simulated minutes against a fast
  clock and a slow one.

Arriving audio goes straight on to Godot's generator a packet at a time, so there is one buffer
and not two in a row. The first version kept a fixed queue in the generator and refilled it from
a buffer sized for 128-frame reads. Godot's mixer takes 512 at a time, and it ran dry fifteen
times a second. Real dropouts are read from the generator's own skip counter, since only it
knows when the listener actually heard a gap. A lost packet is filled with the last frame faded
out rather than closed up, so what follows is not pulled early. A packet that arrives after its
gap was filled is dropped.

**Who hears it.** On for a guest on another machine; off for a guest on the host's own machine,
whose speakers already play it. Nothing can tell from here who shares a room with whom, so the
panel has **Hear the mix**, your own level, and the number: "46 ms behind Ada's speakers". The
number matters because nobody can judge by ear, while also trying to play, whether they are at
40ms or 120.

**Not done:**

- **No codec.** 1.5Mbit/s per listener is nothing on a LAN and too much for a phone tether.
  Godot has no low-latency codec; Opus through a GDExtension would cut it to a tenth.
- **Playing *into* the session** is built for MIDI: see "Recording a guest" below. Audio from a
  guest is not.
- **Picture and sound are not aligned.** Meters and the playhead arrive in ~1ms over ENet; the
  sound arrives ~45ms later. That is invisible at mixing speed and visible on a hard transient.
- **A host whose Reaper restarts** keeps a dead link until the session is hosted again.

### Recording a guest

A guest plays along to the mix they hear, and they hear it late: about 46ms behind the host's
speakers. If a guest's notes were placed by when they reached the host, every take would land
late by the whole round trip, plus however long each note took on the network. So takes are
placed by **song position**. Each note is stamped with the moment of the song that was coming
out of the guest's speakers when the key went down. A note played in time with what the guest
heard lands in time with the song.

**Every packet of the mix says which moment it is.** The `MixFeed` header carries the host's
song position for the packet's first frame (a 64-bit float), plus playing and recording flags.
The position comes from `SongClock`. Reaper reports its playhead a few dozen times a second.
Each report is block-quantised and is read on the next frame, not when it arrived. So the clock
runs on the wall clock between reports and treats each report as a correction. It averages the
first reports after a start or a jump evenly (gain 1/n), then takes 4% of each one after that. A
disagreement over 0.25s is taken as a seek. The stamp is read at
`now - capture offset`, because a captured frame left Reaper that long before the host read it.

After a start the clock **holds at the start point** until the reported position moves (or half
a second passes), and reports not-playing and not-recording meanwhile. Reaper says it is playing
before its playhead has left the start, by about 130ms on the rig. Before the hold, the clock ran
from the moment Reaper said "playing", and every take recorded on Reaper landed that much early.

**The guest knows which moment it is hearing.** `HeardClock` joins two facts. The first is the
per-packet stamps, kept in a ring by sequence number. The second is which stream frame is at the
speaker now: the jitter buffer's read head (`JitterBuffer.read_frame`), less the generator's
queue, half a mixer gulp, and the card's output latency. That measurement is a 10.7ms staircase,
so it corrects a smoothed clock (gain 0.002 per half-millisecond measurement). A lost packet
falls back to the last stamp heard. `Session.mix_feed.heard_position()` returns
`{seconds, playing, recording, valid}`. A guest that is not listening to the stream (in the
host's room) falls back to the replicated playhead, which is less exact by however late the
host's speakers are.

**Playing (`GuestMidi`).** Notes come from `OS.open_midi_inputs()` (InputEventMIDI in `_input`;
a note-on at velocity 0 counts as a note-off, and CC64 is the sustain pedal). They can also come
from the computer keyboard: `KeyCatcher`, opt-in from the panel, plays only while it has focus,
because the studio already uses WASD, Space, F, E, G, V, B and N. A on the home row is C, the
row above holds the black keys, Z and X change octave, and Esc gives the keys back. The guest
hears its own keys from `MonitorSynth`, a 16-voice two-operator electric piano with a sustain
pedal. A round trip through the host's Reaper would be ~90ms, which is unplayable. Where it can,
the synth is its own PipeWire node and reads MIDI itself (see *Your own keys in four
milliseconds*, under Audio). Each note's stamp is moved later by the monitor's own latency, and a
note the helper heard is moved earlier by how long ago it arrived. The player lines up the *sound* of
the key with the mix, so the key went down that much earlier than what they heard.

**A take follows what the guest hears.** It begins when the guest hears the host start
recording and ends when it hears recording stop. Heard, not told, so the take's edges are on the
same clock as its notes. Keys already down are in it from the start. Notes still down at the end
are closed there. The take goes to the host as **one intent**:
`DAW.insert_midi_take(track, start, end, [[on, off, pitch, velocity, channel], ...], name)`.
The host checks it (`DAW.midi_take_refusal`: readable, a track that exists, any notes, and a
backend that can take MIDI), clamps it (`MidiTake.clean_args`: positions, 10,000 notes, a
64-character name), places it, and tells both the room and the guest. A refusal reaches the guest
in words; nothing is dropped silently.

**Placing it.** The stand-in makes an item that carries its notes, as one undo step that
replicates. On the wire, an item has an optional sixth field of item-relative notes. Reaper gets
the take through the bridge, never OSC: one Undo block around `CreateNewMIDIItemInProj`,
`MIDI_GetPPQPosFromProjTime` and `MIDI_InsertNote` per note, then `MIDI_Sort`. Without the bridge,
`can(MIDI_TAKES)` is false and the guest is told to load it. The bridge's timeline poll reports
MIDI items' notes (up to 512 per item), so takes made in Reaper itself show up too, and the
timeline draws them as a small piano roll on the item.

**Measured, by `tools/session_probe.sh`.** The guest injects InputEventMIDI notes on the clicks
of the host's test tone and between them. The tone clicks on every whole song second, so a click
heard at stream frame *n* says that second was at the speaker then. The host checks each placed
note against that. **Offline: within 0.25ms. Against the rig's Reaper: 0.4-1.4ms**, since the
song clock holds at the start (it was 0.7-2.2ms, and up to ~5ms in a take's first second,
before). Reaper itself rounds every note to its PPQ grid.

**Singing (`GuestAudio`).** A microphone take works the same way, for sound. It is opt-in: the
panel's YOUR MIC section chooses an input and a track, and the microphone is not opened until
"Record my mic when the host records" is on. From then on it is read every frame, which drives
the level meter, and a take begins and ends on what the guest *hears* of the host's record
button, exactly like a MIDI take.

- **Where it starts.** The newest frame a read returns left the microphone the input's latency
  before the read. At that moment the guest was hearing `heard - latency`, so every read is an
  estimate of where the take's first frame sits in the song. Capture arrives in blocks, so one
  estimate is jittery by up to a block. The take's start is the median of every estimate over
  its first second, and nothing is sent until that second is over. Frames from before the top
  of the song are trimmed off.
- **Staying there.** The microphone has its own clock. Two sound cards 100 parts per million
  apart drift 18ms over a three-minute take. After the first second the same estimate keeps
  being made, against where the take's own frames say they are, and the difference steers the
  resampler's rate: a critically damped PI loop (`TRACK_GAIN` 1, `DRIFT_GAIN` 0.25, limit
  ±2000ppm) that settles in a few seconds. A jump of more than 0.25s (a loop going round, a seek)
  ends the take there.
- **Getting it to the host.** The take streams up as it is made, a fifth of a second of 48kHz
  mono 16-bit at a time, as reliable RPCs on its own ENet channel (3), so it never queues behind
  the mix or the room. The host writes it to `user://takes/<who>-take<n>-<time>.wav` as it
  arrives. When the take ends there is almost nothing left to send. It is placed with
  `DAW.insert_audio_take` when the guest stops, when they leave, or when the host closes the
  session. **A guest never names a file.** The host makes the name; `insert_audio_take` is not
  in `DAW.COMMANDS`, so no peer can ask the host to place a file of its choosing. A take is cut
  off at 30 minutes.
- **Placing it.** The stand-in keeps an undoable item. Reaper copies the WAV beside a saved
  project and adds it through the bridge (`InsertAudioTake`: `AddMediaItemToTrack`,
  `PCM_Source_CreateFromFile`, one undo block). The built-in engine plays it on the track's bus
  from `AudioStreamWAV.load_from_file`. An item carries its file's name, where in the file it
  starts (`source_offset`, so the right half of a cut plays on from the cut), and a 50-per-second
  loudness overview, which travels with the item to every guest and is drawn on the timeline as
  a waveform.
- **Measured, by `tools/session_probe.sh`.** The guest's probe microphone claps on every click it
  hears of the host's test tone, and the host finds the claps in the WAV it wrote. **Offline:
  within 0.7ms. Against the rig's Reaper: within 1ms**, with the loop finding a clock difference
  of a few hundred ppm between the two processes' audio.


**Calibration.** The two numbers that are not measured on the fly:

- **Capture offset.** How long a frame of Reaper's output takes to reach the host's capture.
  The default is the capture fragment, about 5.3ms. Set `R3D_CAPTURE_OFFSET_MS` on the host to
  override it. The right value is the one that puts a guest's notes on a click recorded in the
  host's Reaper. A per-host calibration routine for it is not built.
- **The guest's output latency,** as Godot reports it. A device that reports wrongly puts every
  take early or late by the error. A loopback measurement (`tools/audio_latency.sh`) is the way to
  check it.

**Not done:**

- **A guest's microphone on a real sound card.** The probe's microphone is synthetic. The
  arithmetic is the same for a real one, but a card that misreports its input latency puts every
  take early or late by the error, and there is no calibration step for the input yet
  (`GuestAudio.offset_ms` is where it would go).
- **Hearing yourself.** A guest hears their voice through the room or headphones, not through the
  game: there is no input monitoring of the microphone.
- **Stereo takes.** The two sides of the input are averaged into one channel.
- **Live preview on the host while the guest plays.** The host hears a take only once it is
  placed. Reaper's `/vkb_midi/` OSC path could play the notes late, as a preview, but it is not
  wired.
- **Bank offsets.** The take's track index is the one the host's cache uses, as for every other
  item edit; with Reaper banked past track 1 this is the bank slot.
- **The guest's own gear's latency.** With "Hear my keys" off, the guest hears its own synth,
  whose latency is not known here, so no correction is applied.

### Not done

- **XR calibration across participants is untested.** There is no headset runtime on this
  machine, so this rests on the arithmetic only.
- **No delta compression.** The full volatile frame goes out every tick.
- **A door, not a lock.** With a session code, only those told it get in. Nothing is encrypted,
  so the code is for a studio LAN with a neighbour on the wifi, not for the open internet.

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
without a second code path. Two of those are dawlings's own namespace rather than Reaper's --
`mix_wire.gd` had defined `colour` in advance for exactly this.

### A send points at two things, and they disagree

`SendState` carries both `dest_name` and `dest_track`, and `resolve()` prefers the index. That
is not belt-and-braces: with the bridge loaded the bay is *exact*, and without it the bay is
still roughly right rather than empty. The name is what OSC gives and it is ambiguous the moment
a project has two tracks called "Verb" -- which is completely normal, and which the old
name-only lookup resolved silently and wrongly, forever.

Sends are numbered **from 1** everywhere above the bridge, because that is how OSC numbers them:
`/track/3/send/1` is track 3's first send. ReaScript counts from 0, so `_on_structure` adds one
and `remove_send` takes it off again. Until that was written down, the bridge's destination
landed on send 0 and OSC's level on send 1, and the bay drew every real send twice. The stand-in
numbers from 1 for the same reason.

### Sends on faders

Send level and pan are verbs (`set_send_volume`, `set_send_pan`) on Reaper's own OSC addresses,
so a send is ridden like a fader and replicates like one. They are **on** the faders: the
master section's SENDS key flips the whole desk so that each strip's fader and pan are that
strip's send to one return, the next press moves to the next return, and past the last the
faders are levels again. A strip with no send to that return reads NO SEND and its fader cannot
be taken hold of. The readouts turn amber while flipped, because a desk of send levels looks
exactly like a desk of levels otherwise. The flip is this participant's view of the desk, never
replicated, and like a bank change it is refused while a hand is on a fader or knob.

### Markers are made by the bridge and read by the poll

OSC has no message that makes a marker, so `add_marker` is a bridge edit (`AddMarker`, one
undo point) and markers come back with the timeline poll as they always did. The backend writes
the new marker into the cache straight away, so MARK shows at once; `_edit` holds the poll that
was already on its way, so it cannot draw the marker away again for a beat. Markers are keyed by
seconds, and Reaper keeps a marker on its beat when the tempo changes, so the same marker has a
different key after a tempo edit. Anything that looks a marker up afterwards goes by name.

### Three states on one lamp

Input monitoring is the only strip key with three states, and a lamp has two. Off is dark and on
is lit; auto, which lets the input through only while the track is armed and stopped or
recording, blinks. A blink costs a `_process` on the strip, so a strip only processes while its
track is on auto. Like the other three keys, the lamp is coded by shape as well as colour -- a
dot, after record's bar, solo's stub and mute's line -- and the suite checks the four differ.

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

**The mix is not ours to play -- in the room where Reaper is.** Reaper is already running,
through monitors, in the room this is running in. Rendering the same audio here would put a
second copy of a critical listening signal a few milliseconds behind the first, which is a comb
filter rather than a feature. So the host never plays programme audio, and that is a boundary
rather than a backlog item.

A guest in another room is the one exception, and it is the whole of *Hearing the mix from
another room*, under Multiplayer: there is no first copy for a second one to comb against.

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

### Every sound on a stream of its own

Asked for "fully simulated I/O out of this process for ease of routing". On Linux the app's sound
does not leave as one stream: each kind leaves as a PipeWire node of its own, and what it takes in
arrives on one, so a patchbay (qpwgraph, Helvum, pavucontrol) can send each anywhere.

| Stream | What | Made by |
|---|---|---|
| `dawlings · mix` | the built-in engine's master; on a guest, the host's mix it hears | `MixFeed`, `GodotBackend` |
| `dawlings · monitor` | a guest's own keys, played the instant they are pressed | `NativeKeys` (`MonitorSynth` where not) |
| `dawlings · gear` | the room: buttons, detents, faders, plugs, reel motors | `Foley.emitter` |
| `dawlings · mic` (in) | what a guest records | `GuestAudio`, via `MixSource.Piped` |
| `dawlings · mix tap` (in) | what a host passes on to its guests | `MixTap`, via `MixSource.Piped` |

Each starts on the default device, like any app's sound, and the session manager remembers
wherever it is moved to: each has its own `application.name`, which is what WirePlumber's
stream-restore keys on, so moving the gear does not move the mix.

**How.** `AudioPorts` (core/audio). Godot opens one output and that is left alone: it is the
clock. Each kind plays on a bus of its own (`Mix`, `Monitor`, `Gear`); an `AudioEffectCapture`
on the bus takes the sound, and the bus is sent on into `Ported`, a muted bus, so nothing is
heard twice. A thread moves what the captures hold into a `pacat` per bus every millisecond,
raw stereo float at 48kHz, 8ms of buffering asked of the server (`R3D_PORT_LATENCY_MS`).
Godot's mixer is paced by its own output, which runs on the device's clock, so the pipes neither
fill nor run dry. Writes are never more than `PIPE_BUF` (512 frames) and non-blocking: a pipe
takes such a write whole or not at all, so a player that falls behind loses a block and stays in
step, rather than taking half of one and swapping left and right for every sample after.

Inputs are `parec` streams read the same way, a partial frame kept for the next read.

**What it costs.** `tools/audio_latency.sh` (host's tap in, guest's mix out, sound card to
sound card), 2026-10-09, two runs each: 45.4 and 46.3 ms with `--direct-audio`, 38.2 and 43.7 ms
ported, each run steady to about a millisecond. The output's extra hop is paid for by the input:
`parec` hands the tap over sooner than Godot's own capture does. `R3D_LATENCY_ARGS=--direct-audio`
measures the old way.

**Where not.** No `pacat` (not Linux, no Pulse tools), the Dummy driver (headless), or
`--direct-audio`: the buses play to Master and everything comes out of Godot's one stream as it
did before. A player that dies mid-session (its server restarted) is taken down and its bus goes
back to Master, so the sound is heard from the app's own output rather than not at all.

### Your own keys in four milliseconds

Asked for: "all audio that could be performance based to be low latency". That is a guest's own
keys -- the one sound here that answers a hand. The mix a guest plays along to is late by design
and stamped for it (*Hearing the mix from another room*); the gear's clicks and the room are
not played; a voice is best heard through the interface's own direct monitoring, before any
software.

Through Godot, a key cost 30-50ms: read once a frame (up to 17ms), queued deep enough to feed
Godot's 512-frame mix (16ms), then behind an output (10-20ms), with PipeWire's default 1024-frame
cycle (21ms) under all of it. So the keys left Godot. `native/keys.c` is MonitorSynth in C, a
PipeWire stream of its own (`dawlings · monitor`) rendered in the graph's realtime callback. It
asks for a 128-frame cycle (2.7ms; `R3D_KEYS_QUANTUM`), and reads MIDI from the ALSA sequencer
the moment it arrives, on a port of its own ("dawlings: keys in", so anything can be routed to
it) linked to every hardware source when MIDI is opened from the panel. Notes from the computer
keyboard and the panel go to it as commands. It passes every MIDI note back to `GuestMidi`
stamped with when it arrived, so the take is made in the app as before -- and more exactly
than before, since a note is no longer stamped by the frame that read it.

`NativeKeys` builds it with `cc` the first time (0.4s, at startup) and whenever the source is
newer. No compiler, no PipeWire or ALSA headers, not Linux, the Dummy driver, `--direct-audio`
or `R3D_GODOT_KEYS=1`: MonitorSynth plays through Godot as before. If the helper dies, the keys
go back to Godot mid-session.

**Measured.** `tools/keys_latency.sh` sends sequencer notes to the helper and times their sound
arriving at the rig's null sink by the graph's own clock: 2026-10-09, key to sink 4.3-4.7ms
median at a 128-frame cycle (34ms at PipeWire's default 1024, 3.0ms at 64), the same 4.3ms with
the helper started by a guest in a running session. A real card adds its own output latency
after the sink. The helper's own account of each note, which the stamps use, is checked against
it. The panel shows it beside "Hear my keys".

The cost: the graph runs at the smallest cycle any node asks for, so while a guest session is
open everything on that card runs at 128 frames -- more wakeups for every program on it.

## Items: things you pick up

An `Item` (`core/items/item.gd`) is a `ControlAffordance`, so a mouse ray, a controller and a
pinch all take hold of it through the one grab contract. For an item `grab_begin` means "pick me
up": it calls `Interactor.pick_up`, and the item stays in the hand after the button is released.
While something is carried, a press that hovers nothing is the item's `use(down)`. Q, or the
put-down call, hands the item to its room.

An item is in one of three places: `HOME` on the venue's prop shelf, `HELD` riding the hand's
`Interactor.carry_pose()`, or `LOOSE` on the floor. Every move is a spring stepped at a fixed
120 Hz: an overshoot into the hand, a bounce on landing, and a slow arc home. At rest an item
stops ticking. A loose item tidies itself home after `TIDY_SECONDS` on a single timer.

`ItemRoom` (`core/items/item_room.gd`) lives in `studio_set`, which is the walker's frame, and
owns every item. It knows the floor because the studio gives it `Walker.reachable` and `ground_at`, so
it judges a put-down, not the hand. The aim meets the floor within `PUT_REACH`, or the item lands
at your feet. Somewhere a person could not stand to pick it up again sends it home. When the venue
changes, `set_spots` moves the items at home to the new shelf, and loose ones the new room has no
floor for go home too.

Where the hand is belongs to the interactor. `MouseInteractor.carry_pose()` is lower left in your
view, and the interactor draws a left glove under the item (`Glove`, palm up, GRIP while using) on
`Mirror.NOT_REFLECTED`, so it is only seen in your own view. The item itself goes on that layer
too while held. A mirror's ghost carries a look-alike instead (`ItemRoom.look_of`,
`Presence.Avatar.carry`), on its own left palm.

In a session the items are the room's. Carrying one is a hold in the host's table, like a
fader's, but it lasts for as long as the item is carried rather than while a button is down.
`Presence.claim_carries` reads every hand each tick and claims or lets go to match, so no way of
emptying a hand leaves a claim behind. Whoever else holds it, everyone sees the real item, not a
copy, ride that person's ghost's left palm (`Item.follow`, `Avatar.carried_pose`). It wears that
person's colour as a rim (`core/items/item_rim.gdshader`) and sits where their
`Session.send_carry` says, relative to their head, on the motion channel. A squeeze goes out
reliably (`Session.send_item_use`) and squeaks on everyone's copy. A put-down is a room ask
(`put_item`, `home_item`), done at once by a guest and rolled back if the host disagrees. The
host takes it only from whoever holds the item. The room says where every item is that is not
home (`Session.room["items"]`). The order matters: a hand asks, then lets go, so the host's word
on where the item went arrives before the news that the hand is empty. A hold that ends without
a word, because its holder left, sends the item home.

A throw is launched, not streamed. Holding R winds up (`MouseInteractor.begin_throw`, the hand
drawn back over `CHARGE_SECONDS`) and letting go throws along your aim, lofted a little, harder
the longer you held. In a headset, letting go of the grip while the hand is moving faster than
`FLICK_SPEED` throws at the hand's speed; slower, it is a put-down. Either way the hand calls
`ItemRoom.throw`, which works the whole flight out at once (`core/items/flight.gd`): a fixed
120 Hz step with gravity, air drag, bounces off the walkable floor's edges and the venue's solids
(`Walker.fixed`, down onto their tops too), floor bounces that die into a roll, and a rest. There
is no clock and no randomness, and the item faces the way it was thrown, not the way it sat in
the hand, so the same launch gives the same flight on every machine. The launch goes out once as
a `throw_item` room ask (from, velocity, spin, as Vector3s in the room's frame). While it flies,
the room's entry for the item carries the throw count and the launch as well as where it will
rest, so a copy that has not flown that throw flies it. It does not collide with the gear: one
that comes down where nobody could stand goes home once it has landed. `Item.flies()` gives each
kind its bounce, roll and drag (a duck thuds, `BallItem` bounces), and `on_bounce` its sound.

A `PlaneItem` glides. Its `flies()` carries a `wing` (trim speed, glide ratio, stall speed, most
lift, flutter speed, settle time, lean), and `Flight` flies it as a point mass with lift across
its path that grows with the square of its speed and is tipped sideways by the lean, so it turns.
It has drag along its path, extra drag above its flutter speed, and lift that ramps in over the
first `settle` seconds out of the hand. Thrown level at about walking pace, it crosses the live
room. Thrown at the floor, it hits the floor before its wing takes hold. Thrown hard, it
flutters and falls short. The first thing it touches ends the glide; after that it is a sheet
sliding to a stop.

Where a loose item may lie is `Walker.reachable`, not `fits`. The spot must be on the floor (or
something you step up onto) and inside nothing, with somewhere a person fits within `ARM` of it.
So a ball in a corner stays in the corner. A put-down's aim is stopped by the gear's footprints
(`ItemRoom.gear`): aimed past the console at the floor behind it, the item was aimed at the
console, and goes home.

An empty hand catches what is thrown at it (`Interactor._catch`). An item in the air for longer
than `Item.CATCH_AFTER`, long enough to have left the hand that threw it, is caught by a hand
whose `catch_point` it passes within `catch_reach` of. On a screen that is round your head
(`MouseInteractor.CATCH_REACH`); in a headset, the palm. A catch is an ordinary pick-up, so it is
claimed like one, and everyone else's copy leaves its flight for the catcher's glove when the
host's table says so. Whoever's hand it lands in first, by the host's clock, has it.

An item in somebody else's hand stays grabbable (`Item.follow` keeps its grip, `Item.grab_begin`
looks past the claim). Grabbing it takes it: the hand marks it `taken`, and `claim_carries` asks
with `Session.take_hold` rather than `claim_hold`. The host moves the hold rather than refusing,
for keys its `takeable` says are items, so a fader somebody has is still theirs alone. The hand
it was taken from hears the new table and lets go (`Presence._apply_items`), with a notice of who
took it. Hovered, it says whose hand it is in and that it can be taken.

The mic (`MicItem`) has a home of its own. `ItemRoom.set_spots(spots, homes)` takes
homes by kind, and the studio gives the mic `Venue.mic_spot()`: the clip at the end of the
booth's mic stand (`ZoneKit.mic_stand`, its clip at `ZoneKit.mic_clip`), along the boom. A venue
with no stand gives null, and the mic takes a shelf spot. The shelf's spots go to the kinds
without a home, in `KINDS` order. In any hand the mic's band glows. In a hand here it is `live`,
and the studio's `MicArm` (`core/session/mic_arm.gd`) puts a voice on a track: the one a guest
already chose, else the first named for a voice, else the first. On the host that means an
armed track with monitoring on, asked through `Session.send_intent`. On a guest it means
`GuestAudio.target_track` and `record_with_host`, and nothing armed on the host, whose input
would record over the guest's take. Whatever it changed it puts back when the mic leaves the
hand, however it leaves.

The headphones (`HeadphonesItem`) are worn, the first thing that is. Their home is a hook under
the prop shelf (`Venue.headphones_spot`, `ZoneKit.HEADPHONE_HOOK`), so `Item.own_home` is set and
they hang with their cups square; anywhere else on a floor they swivel flat. `Item.wearable`
lets a hand's `wear` move what it carries into its `worn` slot. The item keeps `carried_by`, so
everything that asks whether it is carried here still holds. `Item.set_worn` puts it on the
wearer's mirror-only layer (`Mirror.SELF_ONLY`), riding the reflection's `worn_pose`, and turns
off its grip on somebody else's head. `take_off` (H on a desktop, or a reach to your head in a
headset, `Interactor.head_reach`) brings it back to the hand, if the hand is free. Presence
claims both slots, so moving between hand and head never lets go of the hold. The room carries
`[true]` for something on a head (`wear_item`). Remote ghosts wear the real item on
`Avatar.worn_pose`, scaled to the dome, with their own hat hidden.

What headphones on a head here change is local (`Ears`, `core/audio/ears.gd`): an
`AudioEffectAmplify` at the head of each of this machine's buses. The room (`Gear`) drops 14 dB
and the personal mix plays: `Mix` and `Monitor` at the levels `Ears.listen` is given, which are
the mix and your keys until the tablet's patches say otherwise (docs/items_loop.md). A host on
Reaper hears Reaper through the system, which the game cannot quiet (`Ears.reaches_mix`), and is
told so.

The tablet (`TabletItem`) is the personal mixer. Its home is the shelf's lower tier
(`Venue.tablet_spot`, `ZoneKit.SHELF_LOWER_TOP`). While a hand here holds it, its glass shows a
`TabletFace`, which is a body child, so nobody else and no mirror sees it. The face has four
receiver rows (meter, level slider) and four wireless plugs in a tray. Dropping a plug on a
`SendSocket` patches it there; the master section has one for MIX and one for KEYS
(`hardware/console/send_socket.gd`). Where the plugs are is room state: `patches`, {peer id:
[socket per receiver]}, changed with the `patch` verb and predicted on a guest like every room
ask. The sockets draw everyone's plugs, stacked in their owners' colours. The levels are local
(`PersonalMix`, `core/audio/personal_mix.gd`), as is what they add up to: `ears_levels()` sums the
receivers per bus for `Ears.listen`. With nothing patched, it is the mix and your keys.

Each channel strip has a send socket too (`ChannelStrip.send`, source `track_N`). A track is
heard by itself where this machine plays the tracks (`PersonalMix.hears_tracks`: the built-in
engine, not on a guest). While headphones are on, the studio asks `GodotBackend.set_cues` for
the patched tracks. Each cue is another player of the track's part on a bus of its own
(`GodotBackend.cue_bus`), sharing the track bus's effect objects: post-effects, pre-fader,
following mute, and in time because `_sync_players` keeps it to the song clock. It plays to
Master, never into the mix a host sends its guests. The strips' sockets are one `MeshBank`
(`MeshBank.meshed`) with shadows off; a lit ring and plugs are made only for a socket with
plugs in it.

Every other player's ghost wears a KEYS pack (`Avatar.wear_keys_pack`, `core/session/presence.gd`)
with a send socket named `keys_N` for their peer id. Their notes come here, not their audio:
`GuestMidi` passes each note to `Session.send_note`, which relays it on `KEYS_CHANNEL` (reliable)
and emits `note_played` everywhere else. `TheirKeys` (`core/audio/their_keys.gd`) plays the patched
players' notes on a `MonitorSynth` each, on bus "Their keys N", only while headphones are on.
Notes are played on arrival with no jitter buffer, so they land one network trip late (two, guest
to guest) plus the synth's queue. The notice gives the figure from ENet's round trip
(`Session.note_delay_ms`).

A player who switches ON AIR on their tablet (the room's `on_air` list) grows a MONITOR socket
under their KEYS pack (`monitor_N`). Plugged in, `TheirMonitor` (`core/audio/their_monitor.gd`)
rebuilds what they hear without anything being streamed. Their notes carry the song position they
heard (`GuestMidi.song`, `Session.note_played`'s `song`). This machine's mix is captured at the
head of the Mix bus into a per-performer delay line ("Their monitor N"), and each note is played
when the delayed backing reaches its stamp. The line grows when a note misses it and never
shrinks while plugged in.

Hand percussion (`InstrumentItem`: `ShakerItem`, `TambourineItem`) is played by moving the hand
that holds it. A stroke that stops or turns back is a hit, as hard as the stroke was fast. The
movement is `Interactor.shake_point`: the controller in a headset, and the mouse's wiggle of the
carried pose on a desktop (`MouseInteractor.wiggle`). The player hears the hit at once on their
own keys' bus. Everyone else gets `Session.item_hit` and hears it in the room, from the hand that
holds it (`Presence._on_item_hit`). `HitRecorder` (`core/items/hit_recorder.gd`) follows the
transport as `GuestMidi.heard()` reports it and records each hit as a drum note, stamped by song
position. The take goes onto the first armed track through `DAW.insert_midi_take`. Other
players' hits are only heard in the room, never in a personal mix.

The keytar (`KeytarItem`) has no sound of its own here. In this player's hands it sets
`GuestMidi.keytar`. Their keys then play on the keys' low-latency synth, go to everyone as notes,
and are recorded as a take whatever this machine's role (`GuestMidi.plays`). A take with no track
chosen goes onto the armed one. On a desktop the studio's own `KeyCatcher` (`keytar_keys`) is its
piano while it is held. `Walker` reads the arrow keys while a control in the `walks_on_arrows`
group has the keyboard. `GuestMidi.key` shows each note on its key. Someone else's notes, while
they hold the keytar (`Presence._on_note_played`), play out of it on a `MonitorSynth` with a
`speaker`: an AudioStreamPlayer3D on the room's bus.

The chips and the cards (`ChipsItem`, `CardsItem`) are pure idle, and both are a `FidgetItem`.
Each press of the hand's button starts the next of its tricks in turn. A press while a trick is
still playing finishes it at once (`finish`), so a quick run of clicks never queues. The presses
relay like any item's use, so every copy plays the same tricks. Everything a trick leaves behind
comes from the count of tricks: the chips' order, the cards' order, and the fan's hand (seeded from
`tricks_done`). Putting the item down resets it. A trick's sounds play at its `cue` points, never in
a trick cut short. Card faces are a texture atlas drawn by `tools/make_cards.sh`, because the game's
font has no suit signs. The models come from `tools/blender/table_games.py`.

The darts (`DartItem`, three of them) live in a board over the prop shelf (`ZoneKit._dartboard`,
lit by its own lamp; a chalk drawing of one in the chalk venue). Their homes are in the board,
points in (`Venue.dart_spot`). A `Flight` given `boards` (the room's `boards`, from
`Venue.dart_boards`: the board and the cork round it) and a `point` checks each step for going into
a board's face before anything else; if it does, it is `stuck` there, turned nose-first along the
way it was going, and `stuck_on` says where on the face. Every machine flies the same launch, so
every one sees it go in at the same place and `DartItem.score` scores it the same. A loose item
whose rest is not upright is stuck (`Item.is_stuck`), and the room's state carries the whole turn
for it (`"stuck"` and a quaternion, applied with `stick_at`). A dart's throw is aimed
(`aim_scatter`): the hand throws at where the cursor's ray meets a board (`ItemRoom.aim_point`), as
a lob (`ItemRoom.lob`) at a pace from how wound up the throw is, with a wobble. A flight's wall
check is skipped over solid footprints (`_over_solid`), because the walkable floor stops short of
the shelf and a dart thrown at the board hit an invisible wall there. The models come from
`tools/blender/darts.py`.

The mini hoop (`Hoop`) is furniture, not an item. Each venue stands one at `Venue.hoop_spot`,
built with the prop shelf, and gives its shape to the room as `Venue.hoops` (`ItemRoom.hoops`).
Something thrown that says it is round (a `"radius"` in `flies()`: the ball) flies against it in
`Flight.fly`, in the hoop's own frame (`_hoop_step`): off the board, off the rim (the nearest
point of the ring), and held by the net, which is a narrowing wall that takes the speed out of a
ball sideways. Dropping down through the ring is recorded in the flight as a basket
(`Flight.baskets`, clean if it touched nothing of that hoop). Each hit records what it was
against (`Flight.hit_on`). As the item plays its flight, a rim or board hit is sounded by the
nearest hoop (`ItemRoom.hoop_struck`) rather than as the item's own bounce, and a basket is
handed to the hoop (`ItemRoom.basket`, `Hoop.sink`), which swishes and springs its net. All of it
comes from the one launch, like everything else in a flight, so every machine sees the same
basket. The model comes from `tools/blender/hoop.py`.

The Newton's cradle (`CradleItem`) is a third `FidgetItem`. Its tricks lift one, two or three
balls; its swing is a function of time alone (`swing`, `strikes` for the clacks). A fidget put
home by `Item.snap_home`, not only by `go_home`, is put down (`on_put_down`), so it stops.

The yo-yo (`YoyoItem`) is a fourth `FidgetItem`. Its origin is the finger; the yo-yo and its
string are posed from the trick and its time, against the world's down and the hand's forward
(`_ways`), so they hang true in a tilted hand. Its string is shorter when it is your own hand on a
desktop (`string_length`), where the full length plays out of the picture. It is the one item
whose look depends on who holds it.

Pockets (`Pockets`) are a person's, shared by every hand on the machine (`Pockets.mine`,
`Interactor.pockets`). A pocketed item stays HELD and `carried_by` the hand that stowed it, with
`Item.pocket` saying which; the room publishes it as `["pocket", n]` and a guest asks with
`pocket_item`. Presence claims what is in pockets with what is in hands, reading every hand
together. It poses a pocketed item on a ghost with `Avatar.pocket_pose`, and on your own mirror
ghost through `Item.pocket_at`. `Item.in_hand` is the test for "in this hand, not stowed or
worn", and `on_stowed` is where an item stops what it was doing.

The venue's toy (`ToyItem`, kind `toy`) is one item whose look and flight are the venue's: a
table of nine (`ToyItem.TOYS`), from one model file of nine objects (`tools/blender/toys.py`).
`ItemRoom.set_venue` turns it into the new venue's toy when the venue changes, even in a hand,
by swapping its body and grip. The venue is the host's, so every machine has the same toy and
flies it the same. It lives on the floor in front of the hoop (`Venue.toy_spot`). A ghost
carrying it shows this machine's venue's toy (`ToyItem.shown`, read by `ItemRoom.look_of`).

The radio plane (`RcPlaneItem`, kind `rcplane`) is one item in two places. The radio is the
item's body, so it goes in hands and pockets like anything else. The plane is a child of the
item, not the body: docked beside the radio (`RcPlaneItem.DOCK`) when the item is out of every
hand, and `top_level` in the room once a hand has it (`on_picked_up` here, `follow` for somebody
else's). Only the hand that has the radio flies it, in the room's frame, from its own aim
(`Interactor.aim`), against `ItemRoom.blocked` (the floor's edges, the venue's solids and the
gear) and `ItemRoom.ground`. Presence sends the plane's pose and `Mode` from the flying machine
(`Session.send_flier`, unreliable, on the motion channel); other machines `hear` it and ease the
plane toward it. A click on another machine's copy changes nothing: its mode is the flyer's.

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

## No signal is carried by colour alone

Three identical rectangles in a vertical column, telling you record from solo from mute by red
against amber against blue. No label, no shape, no distinguishing position. Red against amber
is precisely the pair a deuteranope cannot separate, so roughly one man in twelve read that
console wrong -- and this is the most common accessibility defect in audio software, not an
exotic one.

Two channels now, and the second is the one that always works:

**Shape.** The lamp in each button has its own silhouette -- record a full bar, solo a narrow
stub, mute a thin line. Lettering was the obvious answer and is the wrong one: at 16 by 10
millimetres a legend would be under 3mm of cap height, which is below the legibility threshold
this project already enforces everywhere else. Shape costs nothing, because a `MeshBank` places
each instance from a node's transform, so scaling one marker scales one lamp and the console
still draws every lamp it owns in a single call.

**A palette chosen for the reader.** `Ergonomics.signal_colour` is a per-vision-type table, not
one "colourblind-safe" set for everyone -- the sets that work for deutans and for tritans are
different sets, and a compromise between them is worse for both than either alone. Deutan and
protan keep the blue-to-yellow axis; tritan keeps red-green; monochromacy gets a lightness ramp
and leans entirely on the shapes.

What makes this testable rather than a matter of taste is that colour deficiency is a
*measurable transform*. `Ergonomics.simulate` is Vienot-Brettel-Mollon in linear light (sRGB is
the usual shortcut, and it flatters the result), and the suite runs every signal pair through
every vision type and requires they stay apart. The tuned palettes keep a worst-pair separation
of 0.34; the default palette through the same eyes collapses to **0.105** for a deutan and
**0.052** for a monochromat -- which is to say, the same light. One of the checks asserts that
collapse, so that if the default palette were ever safe this whole mechanism would fail as
ceremony rather than sit there looking virtuous.

The simulation exists to be tested against, never to be rendered through. The studio does not
show anyone an impression of their own eyesight; it picks a palette and then proves, in the
suite, that the palette survives the eyes it was picked for.

One check in this group was wrong when first written -- it asserted that deuteranopia pulls
pure red and pure green together. It does not: those two differ hugely in brightness and a
deuteranope separates them easily. The confusion is between hues matched in lightness, which is
exactly what a row of equally bright status LEDs is. The check now says that instead.

## Every control needed a steady hand on a small target

That was the only way to work anything here: a press, held, on something a centimetre across.
It is the one interaction a tremor, a prosthetic, a one-handed session with a cable in the
other hand, and a cheap tracker all fail at -- and there was no alternative to it anywhere.

Dwell is the alternative: look at a control long enough and it fires. Three decisions in it are
worth stating, because each one is a way the obvious implementation goes wrong.

**Controls opt in, and almost none do.** Dwell fires from ATTENTION, and attention lands on
things by accident constantly. A momentary button dwelt on by mistake issues a command that can
be undone with one press; a fader dwelt on by mistake takes the mix somewhere nobody asked for.
So `dwell_activates()` is false on `ControlAffordance` and true only on `PanelButton`. Faders
and knobs are deliberately not dwellable, and a test asserts it.

**It shows its progress, in the lamp.** A timer that fires with no indication of how long is
left is the interaction equivalent of an unlabelled button -- the first thing anyone does is
look away in case it goes off, which defeats the mechanism entirely. The button already has the
one thing a person is staring at while they wait, so the lamp fills in. A separate ring would
mean watching two things to understand one.

**It latches once spent.** The first version cleared its state on firing, so the count restarted
the very next frame and the button held itself down -- a command repeating at the frame rate,
which is far worse than never firing at all. The dwell is now spent until the gaze leaves the
control. A press cancels an unfinished dwell rather than racing it, for the same reason: someone
who dwells half way and then presses has pressed, once.

Off by default (`dwell_seconds = 0.0`), because an always-on dwell fires at anything the eye
rests on. `--dwell 0.8` turns it on.

The transport's play, stop and record buttons are now on the signal palette and carry
silhouettes too; they had exactly the defect the console strip had.

## And the drag

Dwell removed the press. This removes the drag, which is the harder one: a press is a moment, a
drag is a press *sustained while the hand moves accurately*, and nothing in this studio could
set a value without one.

`Ergonomics.step` turns on notches, and it changes two things at once because only one of them
would be useless:

* a drag lands on notches rather than anywhere, and
* a TAP on the trough moves one notch instead of jumping to where it was tapped.

The second is the one that matters. Jumping to the tap is the behaviour that demands precisely
the aim the mechanism exists to stop needing; nudging means tap above the cap to go up, below
to go down, with no accuracy required anywhere and no drag at all. Quantising the drag alone
would have been a feature nobody could reach.

`nudge` works off the CURRENT value rather than off the nearest notch. A control sitting between
notches -- because Reaper set it, or because it was dragged before stepping was switched on --
still moves exactly one notch on the first tap. The snap-then-move version silently eats that
first tap, and eating the first tap is how a stepped control earns a reputation for being
unresponsive.

Off by default, because quantising a mix engineer's fader without being asked takes resolution
away from someone who had a use for it. `--step 0.05` turns it on.

### The accessibility flags, in one place

| flag | what it changes |
|---|---|
| `--eyes N` | text scale; buys DISTANCE, not just bigger glyphs |
| `--seated` | lower eyes, shorter reach, steeper gaze |
| `--height M` | how tall you are, in metres; remembered in `user://body.cfg`. Only the eye moves -- the room stays its size, so shorter reads as a bigger room. Also set in the room: Tab, "your height", 5 cm a step |
| `--vision deutan\|protan\|tritan\|mono` | signal palette chosen for those eyes |
| `--dwell N` | look-to-activate, in seconds; replaces the press |
| `--step N` | notches and tap-to-nudge; replaces the drag |
| `--no-motion` | surfaces cut rather than glide |
| `--focus ID` | start with a surface summoned |
| `--detach-body` | freeze the body frame, to photograph it from outside |

## Which of these five am I using?

The rig moves five surfaces at once and only one of them is the work. From inside the arc the
only thing distinguishing them was distance -- and distance is also what changes when a surface
is a different size, so a small surface close by and a large one further out read identically.
State needed its own channel.

`FocusHalo` puts corner brackets on every surface the rig is holding: bright on the focused
one, dim on the parked ones. It does a second job at the same time, which is why it marks the
parked surfaces too rather than only the focused one -- it says the thing is SUMMONED rather
than standing in the room. That difference is real and worth drawing, because gear on the body
frame follows you and gear in the room does not, and someone who cannot tell which is which
will walk away from a console expecting it to stay put.

Brackets rather than a full border: a closed rectangle around a panel reads as a frame the
panel is mounted in, which is furniture again, while four corner marks read as something
projected over it. They are also a quarter of the geometry, and the whole set is built into one
ArrayMesh with a shared unshaded material per state, so the entire arc costs two draw calls
rather than one per surface.

Unshaded deliberately. A bracket that dimmed when the lamp was far away would be a state
indicator that stopped indicating in exactly the corner of the room where it is needed.

The arm length is a fraction of the surface, capped. A fixed arm is a border on a patchbay and
a speck on a ninety-track desk; an uncapped fraction puts a 15cm bracket on the console, which
stops reading as a corner mark and starts reading as two sides of a box that failed to meet.

Grouped as `presentation_chrome`, so `content_aabb` does not measure them. They are sized FROM
that box, and counting them would grow the box, which would resize them, which would grow the
box -- the same circularity the grab handle is excluded for.

### And the hole it left

A rack frame with its units gone and a stand with nothing on it are honest -- the gear really
did leave -- but they read as a modelling mistake, which is the same failure the blanking
panels exist to avoid one level down. What they actually are is a vacant berth, so they are
drawn as one, in the same language: the brackets that say "this is a presented surface" out at
the body, dimmer still, say "this is where it goes back to" in the room.

Sized and placed from `_home`, so a berth is automatically the right shape in the right spot
for whatever left, with no table of furniture to keep in step with the furniture.

A berth is only drawn inside the ROOM, and the rig has to be told which node that is rather
than guessing. The timeline lives under the screen stage, which is a child of the camera: a
berth drawn there is parented to the viewpoint and sails around the room with it, marking a
place that does not exist. It is also not a berth in any sense -- nothing was vacated, because
the surface was never standing anywhere. With `room` left unset no berths are drawn at all,
which is the right answer for a rig that has not been told where the room is, rather than a
guess about it.

## A desk too wide to face

> **Later:** the desk no longer bends. Everything below is still how the sizing works -- the
> radius search, the tiers, the span arithmetic, the elbow-height placement -- but the final
> yaw is off (`ConsoleSurface.CURVED`). Paging turned out to be the fix; once a desk is twelve
> strips wide it already fits in front of you, and bending it only buys a fanned gap between
> every pair of panels. Read the section for why the numbers are what they are, not for the
> shape.


The console was the surface that would not fit. Thirteen tracks is 0.92m of desk and sits
comfortably at arm's length; forty-eight is 2.99m and ninety is 5.53m, and both of those failed
`too_big_to_place` — no distance satisfies both "I can sweep it with a head-turn" and "I can
read the legends". The documented answer was "bank it, arc it, or split it", and nothing did.

So the desk now bends. `Surface.wrap_radius()` returns zero for a flat surface and a radius for
a curved one; `Ergonomics.place_wrapped` puts the arc's **centre of curvature at the eye**,
which is the whole trick. Once the eye is at the centre, every strip is exactly one radius
away, head-on, and the desk has no near end and no far end. Width stops being a distance
problem and becomes an angle problem.

### What wrapping does not buy you

It does not buy width. An arc is longer than its chord, so for the same angular extent a
wrapped surface has to sit *further* away than a flat one. Bending the desk makes it worse at
fitting and better at everything else — uniform distance, uniform obliquity, uniform reach.
The flat 3m desk was legible in the middle and illegible at the ends; the wrapped one is the
same everywhere.

The number that governs it: **at arm's length a neck sweeps about a metre of arc.** Seventeen
channel strips. A 90-track session is five times that, and no radius fixes it, because growing
the circle to gain arc also pushes the lettering out of range.

What does fix it is **rows**. Growing the radius buys capacity twice over — a longer arc per
row, and vertical room for another row — so the two together converge where the radius alone
never would. `Ergonomics.wrap_radius_for` walks outward from reach in centimetre steps and
stops at the first radius whose rows hold the desk, or at the legibility ceiling if none does.

| tracks | width | radius | rows | worst bearing |
|--------|-------|--------|------|---------------|
| 13     | 0.92m | flat   | 1    | ±46°          |
| 48     | 2.99m | 0.81m  | 2    | ±61°          |
| 90     | 5.53m | 0.98m  | 3    | ±62°          |

Three constraints of three kinds again, unchanged: reach is where the search *starts*, the
sweep is a lower bound, legibility is a hard upper bound. When nothing satisfies all three the
desk is still drawn — a mixer that refuses to appear is worse than one you turn your head for —
and `push_warning` says how much arc overflowed. Reporting, not hiding.

### Two bugs a render could not have found

**The tube.** The first wrapped desk used a fixed arm's-length radius, and 90 tracks came out at
±179°: sixty strips behind the mixer's own head. From any camera placed in front it rendered as
a magnificent wall of channels. Only a probe printing bearings in body space said otherwise.

**The sign.** `place_wrapped` tipped the desk *up* by its gaze drop instead of down, putting the
top row sixty degrees above the horizon. The cause is worth keeping: a flat panel is placed by
moving it, so the basis that turns it to face the eye tips it the same way it hangs; a wrapped
one is placed by rotating the whole arc about a centre *ahead* of it, and that moves it the
opposite way. Same twenty degrees of gaze, opposite sign. The two functions disagree on purpose.

### Where the bend has to be applied

At the moment each module is positioned, never as a pass over the finished panel. The MeshBanks
read each instance's transform off the node as it enters the tree, so a bend applied afterwards
would move the strips and leave every banked knob, cap and lamp standing in the flat positions
they were claimed at — a console of floating controls next to the console they belong to. This
is also why the wrapped desk drops its three full-width slabs: a single five-metre box cannot
follow an arc, and the strips carry their own backing plates, which is what makes the bend
possible at all.

### The smallest label on the desk was not on the desk

Choosing a radius means asking how far the lettering survives, which means asking for the
smallest cap height on the surface. `FocusRig.smallest_cap` was answering 5.2mm when the
smallest legend on the panel is 5.8mm — the extra 0.6mm was the caption on the *drag handle*,
presentation chrome that only exists while you are moving the thing it is attached to. Every
surface in the room was being held ten centimetres nearer than its own lettering asked for, to
keep legible a label nobody reads. `smallest_cap` now skips chrome, the same way `content_aabb`
already did.

The desk declares its own `SMALLEST_CAP`, because the radius has to be chosen before a single
label exists — the radius decides the layout and the layout builds the labels. A declared
constant can drift from the thing it describes, so there is a test that rebuilds the console,
measures every label it actually made, and fails if the declaration is off by a hundredth of a
millimetre.

### Still open

At 90 tracks the top row reaches 33° of elevation against a 30° gaze sweep, and the furthest
strip is 1.09m against a 1.07m reading limit. Both overshoot by about a tenth. More to the
point, 0.98m is well past the 0.51m reach: you can read a 90-track wrapped desk but you cannot
touch the far rows. The honest fix is not a cleverer curve — it is a narrower bank, which the
`BankSelector` already exists to page through. The bank width is currently whatever the protocol
offers (Reaper's is 64). It should be a body measurement.
