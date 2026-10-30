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

**The patchbay is a pin matrix.** Every track's output is a row (FROM) down the left, every
track's input a column (TO) across the top, each header a colour chip and the name in letters;
a send is a seated pin at the crossing, its head the track's colour, its fill the level, and it
pulses with what the send carries (`SignalBeads.level_between`). Click (or poke) a pin to patch
or pull it, wheel it (or pinch-drag it) for the level, Shift-wheel or wheel a header to scroll,
drag the bars or press the arrows; a hover card says `KICK -> BASS DI  send -6.0 dB (sidechain)`
and pointing at a pin or a header lights its row and column and dims the rest. There are no
pages: the grid scrolls smoothly under pinned headers and pools only the pins in view, so 256
tracks cost what 23 do, and the foot says where you are (`ROWS 31-53 OF 64 · COLUMNS 21-43 OF 64`).
A track's own crossing is blocked, and so is any send that would loop (`DAW.send_refusal`: the
destination already feeds the source, through sends or folder parents; a key send is a sidechain
and loops nothing); the pin says why rather than doing nothing. A guest's pin asks the host
(`apply_intent` refuses a loop there too) and shows pending until the answer lands. A removed
send travels as `/track/N/sends` (the count), which is the only address that can say a send is
gone. The bay stands in its own cabinet on the floor, off to the right of the desk. The same
matrix (`hardware/patchbay/pin_matrix.gd`, `PinMatrix`) is the AUDIO DEVICES wall: PipeWire
ports grouped under their nodes, a node's row folding its ports away with a count, every port a
scroll away.

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
  folder fader moves its children the way it does in Reaper. Slot 0 is a panner left at the
  centre, holding the rack's place, and the rack starts at slot 1. Volume and mute go straight onto
  the bus. The bus's tail, after every rack slot, is the track's width (`TrackState.width`), an
  `AudioEffectStereoEnhance` whose `pan_pullout` is the width (`width_effect`), and then the
  panner that is its pan (`pan_effect`). Width before pan, as Reaper's stereo pan has it: the
  enhancer folds each side toward the middle, so after the pan it would pull a panned track back
  to the centre. Rack effects are put in before the tail (`_fx_end`), so `fx + 1` is still each
  effect's slot, and the cue, tap and send copies take the rack slots and not the tail.
- **A sidechain is a send bus that only compressors hear.** A key send (`SendState.key`) gets a
  send bus like any other, `R3D <n>><dest>`, but it plays into `R3D Keys`, a muted bus made just
  after the master, instead of into the destination's mix. Every `AudioEffectCompressor` on the
  destination's bus has its `sidechain` set to that key bus by name (`GodotBackend.listen`, after
  any send or chain is built again), and back to empty with no key into the track. The key buses
  play unmuted at full volume because a compressor reads its key bus's buffer as the mixer left
  it, which for a bus already mixed is after its volume and mute; only `R3D Keys` is muted. A key
  bus follows its track's own mute, not the desk's solos, so a soloed bass still ducks.
- **Solo is solo-in-place**: a soloed track keeps the folders above it and the returns it sends
  to audible. `audible()` is the rule, and is tested on its own.
- **The rack is Godot's own effects** (`FXCatalogue`): EQ6, compressor, reverb, delay, chorus,
  low-pass, drive, phaser, limiter. Each knob is a `Param` with a range and unit, and
  `read_fx_param_text` answers in those units, the way Reaper answers with the plugin's text.
- **A send is a second player** on the same part, on a bus of its own that holds the track's pan
  and effect objects and then the send's pan, routed to the return's bus, at the send level
  times the fader: post-effects and post-fader.
- **The song is synthesised, not shipped** (`DemoSong`): ten parts, each four bars at 32kHz,
  rendered on worker threads and cached in `user://built_in` per tempo. A tempo change renders
  a new set and swaps all of it at once, so no part plays at the old tempo against the new.
  Each bar is played in its own time signature (`DemoSong.pulses`), so a waltz is a waltz.
  With tempo or signature changes a part plays windows of itself rendered through the map and
  the meter instead (`DemoSong.render_window`, `GodotBackend._part_window`), two loops of
  `BARS` bars at a time, the next asked for halfway through a loop.
- **Bars go through the meter** (`MixState.meter()`, dawkit's `DawKitMeter`): the time
  signature's changes, saved as DAWproject `TimeSignatureAutomation`. Bar numbers, bar starts,
  the count-in, the ruler and the click all count through it; in Reaper they are its tempo
  markers' signatures.
- **The song plays through dawkit's native lanes** (`LaneEngine`, `core/built_in/lane_engine.gd`)
  where the core is built and a sound card mixes: one `DawKitLane` per track, played by every
  player the track has (its own, each send's, each cue's) against one `DawKitTransport`, so
  every item, send and cue starts on the same sample. Each frame the lanes are given their clips
  when they changed: takes, imports, MIDI renders, the demo parts on the bar grid (or their tempo
  map windows), each cut where a newer item lies over it (`LaneEngine.visible`); the click has a
  lane of its own on the master, which a count-in's hold does not silence. The playhead is the
  transport's, eased toward its reading and never back (`LaneEngine._follow`), so a punch's edge
  is crossed once. `first_frame_at` says where the first frame after play is in the song, for
  `MixRender` and the probe. Headless (the Dummy driver) and without the core, the old way runs:
  each part starts at the song position modulo its loop, only under its track's items, the
  playhead is the sound card's (`audio_time`, a silent looping player), and a player is put back
  only when it drifts more than 25ms from its own first reading.
- **Items carry gain and fades**, played as their player's volume (`item_level`). Delete,
  duplicate, trim, gain, fades, transpose, quantise and adding, removing and renaming tracks are
  DAW verbs, one undo step each, and Reaper gets them
  through the bridge.
- **Meters are the buses' real peaks**, through the same fader law.
- **Guests hear the master bus**: an `AudioEffectCapture` on `R3D Master` is the session's
  `MixSource` (`BusSource`), resampled to the wire's 48kHz if a sound card insists on another
  rate. `tools/session_probe.sh --built-in` checks the guest hears it, 26 to 33ms behind. It runs
  the host on a real audio driver into the null sink, because headless Godot's dummy driver mixes
  in 85ms lumps.

Automation: each track's (and the master's) volume, pan, mute, send levels and plugin parameters
as lanes of points, moved by the engine as the song plays, written from the desk in touch or latch,
drawn and edited on the timeline, and kept in the project as DAWproject `Points`. Under Reaper they
are its envelopes, through the bridge.

Mixdown: `DAW.render(stems)` writes the loop range (or the whole song) as a WAV of the mix and,
with stems, one per track, beside the project; the MIX and STEMS keys under the timeline ask for
it. The built-in engine renders in real time (`MixRender`: captures at the end of each bus, each
block multiplied by the fader it was mixed with, started inside one hold of the audio lock so the
file lines up with the song); Reaper renders offline through its own render, via the bridge.
Both ring out after the range for up to `DAWBackend.RENDER_TAIL_SECONDS`: the built-in engine
until the mix is silent, Reaper for its fixed render tail.

Not there yet: rendering faster than real time here (that waits on the engine mixing its own
sound), and third-party plugins, which Godot cannot host. See "Built-in DAW" in `docs/loop_backlog.md`.

### dawkit: the engine is its own product

The DAW engine is being built as **dawkit**, a separate repository (`~/Projects/dawkit`,
MIT licensed like this game), not as part of this game. It is a Godot addon with
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

With no track chosen, every armed track records, by its input: one microphone recording goes onto
each armed track of the same device, as that side or both (`GuestAudio.take_plan`, "audio:<device>#1"
and "#2"), each its own file from the same moment, kept by Session as parts of one take; one take
of the keys onto each armed track that takes them. Godot opens one input device at a time, so a
track naming another is left out, and the host told why.

A count-in (`DAW.set_count_in`, only with the click on, as in Reaper) runs the transport from that
many bars before the record point with the click alone, recording all the while as Reaper reports
it; `MixState.taking()` is false until the playhead reaches `count_in_to`, and every take follows
`taking()`, not `recording`. Reaper counts in itself (its project's metronome flag &16, set by the
bridge's SetCountIn); `DAWBackend.follow_count_in` finds the record point from where the transport
stood. With pre-roll (`DAW.set_pre_roll`, `MixState.pre_roll`, `/countin/song`) the song plays
under the count (`MixState.song_held()` is false); in Reaper it is Reaper's own pre-roll in place
of its count-in, which starts on a bar line, the start of the bar before the record point's. Punching (`DAW.set_punch`) limits what is taken to the loop range, Reaper's time
selection auto-punch there. Every take asks `MixState.takes_at` of the moment it hears, so the
take's edges are where the song is, not where the playhead was a latency earlier. Each track names
its input (`DAW.set_track_input`, one of the DAW's `MixState.inputs`), saved with the project; the
host's own microphone records from the device its take's track names.

The built-in engine's playhead is moved by the sound card: a silent player runs all the time, and
while the song plays the playhead is where play (or a seek) began plus how far that player has
been mixed. Every player is started against it, and put back only when it moves by more than a
mix step from where it started. Keys a host plays into a track are heard through that track's
bus (`DAW.monitor_bus`).

MIDI items play through the engine's instrument, dawkit's `DawKitTine`. Each item is rendered
whole on a worker thread, every note on its own sample, and played like a take, locked to the
item's start. A project marks the track with a built-in instrument device, and opening one keeps
instruments out of the desk's effect chain.

Notes on the hand percussion's channel (9) and the pitched items' (10) are not the tine's:
`ItemVoices` (core/built_in/item_voices.gd) rings them from Foley's own synthesis (`Foley.samples`),
channel 9 as General MIDI drums (each of the room's items' notes as that item's sound) and channel
10 as the handbell at the note's pitch, each note's take seeded by its time. `render_midi` splits
an item by channel and sums the two; an item with neither is the tine's alone, to the sample. On
Reaper the track's own instrument plays them, as any MIDI.

Sound files come in through `DAW.import_audio` (`core/daw/audio_import.gd` chooses the name and
the track). dawkit's `DawKitAudioFile.bring_in` reads the file (WAV, AIFF, FLAC through
`DawKitFlac`, Ogg, MP3) and puts it in the takes folder as a
WAV the engine plays, and it is placed with `insert_audio_take` like a recorded take. So it saves
into a DAWproject like one, and plays on Reaper through the bridge. Files dropped on the window
with the cursor over the timeline's lanes go onto that lane at the beat under the cursor
(`SessionPanel.drop_spot`, a fresh cast through `MouseInteractor.under_cursor`); elsewhere, onto
the import box's track at the playhead. The panel goes through `DAW.import_audio_files`, which
reads each file on a worker thread and places it on the main thread when it is in, so a long
file does not stop the room.
A guest's files go to the host whole (`FileSend`, on ENet channel 6), and the host brings them
in the same way, crediting the guest.

What moves into dawkit next, step by step: the file format, then the mixer and transport
(today `GodotBackend` here), then everything after.

### The 2D view: dawkit's interface over the game's mix

F2 (or `--flat`) puts dawkit's 2D DAW interface (`DawKitStudio`, `vendor/dawkit/addons/dawkit/ui/`)
over the room: `FlatView` (`scenes/flat_view.gd`). The interface asks a `DawKitHost` for every
change, and the game's is `FlatHost` (`core/flat/flat_host.gd`): it reads the state cache as a
project (any backend, a guest's copy too) and turns every edit into a `DAW` call, so a fader
moved in 2D is a fader moved at the desk, one undo step, sent to the host from a guest. The room
keeps playing behind it; its keys and clicks stop at the 2D view. In a headset (holding the
menu button, or F2) the same view is a panel in the room instead, `FlatPanel`
(`core/flat/flat_panel.gd`): a SubViewport on a quad drawn over the room, and a control like a
fader is, so the ray, a poke or the mouse all reach it the same way -- hover is the pointer, a
grab is the left button, a press held still is the right, a nudge is the wheel. How the
interface was built, a slice at a time: `docs/flat_loop.md`.

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

Proved against the official examples (the projects bitwig/dawproject's own tests write, kept in
dawkit as fixtures): each opens through dawkit and through the game with its clips, offsets, fades,
notes, mix and automation where they sound; what the game saves of each is valid against the
schema; and saved and opened again it is the same, with or without our extension. What a file
from elsewhere loses here, always said as it opens (dawkit's warnings: the room hears "opened it,
but: ..."): MIDI expression lanes (CC, pitch bend, pressure), automation
inside clips, clip launcher scenes, video, time stretching (a stretched clip plays at its file's
speed), and a plug-in's state when the file does not carry it.

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

A nudge (`ControlAffordance.nudge`) is the contract's relative move: the mouse wheel over a
control, and a controller's thumbstick (`XRInteractor.flick`: a notch per flick past 0.6, again
every 0.25 s while held, ready again under 0.3) on whatever the hand hovers or holds. A bare hand
has no stick, so anything that nudges has buttons a finger can press too.

Beside the grab contract, an interactor gives readings an instrument may ask for:
`finger_pinches()` (a mask, index 1, middle 2, ring 4, little 8), `palm_up()` and `tilt()`
(roll and pitch, -1..1, full at 45 degrees). A bare hand answers from its `HandGestures`
(`core/xr/hand_gestures.gd`, one per hand under the XRRig), which reads its joint tracker each
physics frame through `HandPose` (`core/input/hand_pose.gd`): static and pure over the 26 joint
positions, so the suite poses hands of its own. A pinch closes under 18 mm and opens over 30,
scaled by the hand's size (wrist to middle knuckle, 95 mm the reference) and by Ergonomics'
`finger_scale`. A controller answers the same questions from its trigger, grip, A/X and B/Y and
its aim's basis: its palm is round the side of the grip, toward the other hand (OpenXR's grip X,
`-side * aim().basis.x`), so held thumb up it faces sideways and a quarter turn outward is palm
up. The mouse answers its tilt from its wiggle (`MouseInteractor.tilt`). While
`fingers_play` is on, a hand's pinches are notes, so `is_pressing()` is false and it grabs,
dwells, uses and catches nothing; the left hand's B/Y is then its little finger, not the rig's
calibration button (`XRRig.watch_calibration`). Hand poses never cross the wire: what they play
does. docs/spatial_loop.md slice 7.

Fingertip notes (`FingertipNotes`, `core/music/fingertip_notes.gd`, one per local hand, made by
`Studio._lend_fingertips`) play those readings: thumb to index, middle, ring and little play the
song's chord's root, third, fifth and top, voiced at C4 and read at the pinch's own stamp, as the
player's keys with source `&"fingertips"`. A bare hand or a controller turns them on and off by
being held empty, open and palm up, not toward the eyes, for 0.4 s, and plays with the palm down
or on its side; no pinch is played palm up or toward the head, which is Quest's own menu gesture.
The interactor's `faces_head()`, `hand_open()` and `finger_travel()` (how far each finger has come
in, for velocity) are what it reads. On a desktop there is one reader of the keys: a second
`KeyCatcher` (`Studio.fingertip_keys`, J K L ;) whose keys down are the mouse's
`finger_pinches()`, and whose focus is whether the fingertips play (T gives it; a click, Esc or T
takes it back). While they are on the interactor draws a right `Glove` playing them, its pinched
fingers curled to the thumb and each lettered with its note. docs/spatial_loop.md slice 8.

Chord shapes (`ChordHand`, `core/music/chord_hand.gd`, one per player, made by
`Studio._lend_chord_hand`) are the player's own chord over the song's: the static
`ChordHand.at(seconds)` is Harmony.at with the held degree's triad (or seventh) in the key there
put in its place, and the harp, the fingertips, a bell carried here (`InstrumentItem.harmony_at`)
and the wheel's follow-ups read it instead of Harmony.at. It is never shared: the shape is this
machine's, and what it plays goes out as notes with their pitches. Three ways in. The chord hand
(the left, or the right for a left-handed player) held up, palm toward the room and fingers up,
counts the fingers held out (`HandPose.extended`, the thumb as the fifth), palm up one or two is vi
or vii°, read pure over the joints by `shape_of` and counted once held 0.12 s; a fist, a flat hand,
a point (a level index), a palm to the eyes or a hand lowered below the chest is none. A
controller's stick click is a mode (`XRInteractor.chord_stick`) in which the stick's direction
latches a degree and nudges nothing. A desktop's C is a layer over whichever `KeyCatcher` has the
keyboard (`KeyCatcher.chord_keys`, a static Callable: 1 to 7, Shift, 0, Esc), not a third catcher,
with the mouse still pressing (`Interactor.presses_while_playing`) so a click strums the harp; a
left `Glove` in Pose.SHAPE holds the chord up on the screen and the HUD says `CHORDS · IV F`.
docs/spatial_loop.md part two, slice 32. The one way a shape leaves the machine is the chord hand's
own jack, `chord:P` (slice 33): into a bandmate, `Jacks.send_chord` sends `ChordHand.own_chord` as
a `Jack.Kind.CHORD` on each change of it, and on Q `ChordHand.take` makes it Q's chord while Q
holds none of their own (`their_chord`, the latest taken; the harp's crown `IV from ADA`, the HUD
`CHORDS · IV F FROM ADA`), let go on quality 0, an unplug or P leaving. Sent once, it is not
lost to a replug: Q holds a CHORD that beats the room's word on the plug (`_held_chords`) until
the next patch says yes or no, and P sends it again once the host's room answers the plug
(`Jacks.answered`).

## Furniture is not a surface

A surface exists because the project has tracks or plugins, and its size follows them. A stand, a
cabinet, a trolley means nothing and is not drawn in ROOM mode at all, because the
participant already has real furniture. Mixing the two means a rack that cannot stand on the
floor without inventing a plugin to justify its legs.

## Room layout: neighbourhoods round a middle

The room grew one station at a time, each put in whatever gap was left, until twenty stations,
thirty-six items and forty footprints stood in one 8 x 6 m control room and a 14 x 4.5 m strip of
live room behind it: thirteen pairs of pieces closer than 0.6 m, the harp, the bells and the music
box 12 cm apart, the sampler 3 cm off the booth's wall, and with a 0.9 m walkway the harp, the
music box, the modular and the lyric board could not be reached at all (2026-10-28: "EVERYTHING is
way too cramped"). The layout is now a rule rather than a residue, in three parts.

**Bigger, through the shared constants.** The control room is `Studio.ROOM_WIDTH` 11.2 x
`ROOM_DEPTH` 8 m under 3.6 m (it still grows with the desk, `SessionLayout.fit`); the live room
behind it runs from `Studio.ROOM_BACK` (4.0) to `Venue.LIVE_ROOM_BACK` (12.4) and
`Venue.LIVE_ROOM_HALF` (8.8) either side, under 5 m: 148 m^2 where it had 64. Every venue draws
its walls, floor and scenery from these, so all fourteen grew together; scenery that was placed by
number scales by the room over `Venue.DRAWN_HALF` / `DRAWN_BACK`, the old room's size.

**Named neighbourhoods.** `Neighbourhoods` (core/room/neighbourhoods.gd) says which stations
belong together, where their middle is, and hangs a banner over it with the name in words (a
billboard `Label3D`, so it reads from the seat, the far wall and the next cluster alike; text, not
colour, says which is which). Where each station stands is still the venue's, in its
`default_*_spot`, derived from the zone boxes, so a venue that moves a zone carries its cluster:

| Neighbourhood | Where | What |
| --- | --- | --- |
| MIXING | the control room, a ring round the seat | desk, timeline, rack, deck and platter, patch stand, patch wall, EQ wall, stage table, station board |
| RHYTHM | straight ahead turned round from the desk | drum riser with the hand drums and the looper; the lattice and its marble run; the venue's instrument on the back wall behind the riser |
| HARMONY & STRINGS | front right | the bricks table (fifths wheel, chord ledge, section blocks); harp, music box and string spool in a row facing it; handbells across its far end |
| SYNTH & SOUND DESIGN | back right | the keyboard stand and modular wall; theremin, grain cloud and sampler round a middle in front of it |
| VOCALS | back left | the booth (3.4 x 3.1 m, a 1.2 m door), the lyric board, room for a talk box |
| TAPE & TOYS | front left | prop shelf and cassette rack on the wall, hoop and Tour case across the middle from them; the items' homes |

The most-used live stations, the riser and the lattice, are the ones straight ahead of the seat
turned round; the venue's own instrument and weather belong to no neighbourhood.

**Clearances, measured.** Between any two pieces 0.6 m (but for one activity's own furniture in
its own zone, and a riser stood on); between neighbourhoods a 1.2 m walkway; nothing within 0.8 m
of the console but what is played from the seat (the deck's cart, the timeline's stand); and every
station's seat reached from the desk down a 0.9 m walkway, in every venue and arrangement.
`tools/layout_dump.tscn` and `tools/layout_map.py` draw it and count it;
`_test_every_venue_keeps_its_pieces_apart_and_every_station_in_reach` holds it, with the same
reckoning, and one test per neighbourhood holds that its stations stand together and are signed.

A saved layout from a smaller room would pin the gear in the old places: every piece is saved
when it settles, moved or not. `Studio.was_an_old_default` knows the old rooms' defaults (the 8 x 6
room's spots, and its rule's lines for a widened desk), and a saved spot that is one of them is
nobody's choice, so the piece takes the new room's; a spot a player pushed it to stays.

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

### Pointing at a time, a bandmate or the room

A control key cannot name a moment in the song, a bandmate or a spot on the floor, so
`pointing_at` takes three more forms (docs/spatial_loop.md part two, slice 35): `ruler:<seconds>`,
`ghost:<peer>` and `room`, the last with `pointing_local` in session space. It is still the one
unreliable 20 Hz stream, with no new message. Every receiver redraws a song time where its own
ruler puts it (`Presence.ruler_point`, the studio's `TimelineSurface.ruler_point`), so a time
lands on the right bar on everyone's layout, as a control key does. The beam then ends at a dot,
with the pointer's name and the time (`Lin  0:46`) lettered just back along it
(`Avatar.point_at(null, point, false, words)`). `Presence.pointing_of` decides which form to use, in
this order: a ghost nearer than any control, a song time (`Presence.time_at`, filled in by the
studio's `PointAndMark`: the 3D ruler, the lanes, a note's card and the miniature's bed), a control, and
otherwise the room. It only does this while the hand is pointing (`Interactor.pointing`: Z held
at a desk; `HandPose.pointing` for a bare hand; the non-chord controller's stick click held,
`XRInteractor.points_by_stick`). When the hand is not pointing, the old hover and hold publishing
is unchanged.

`PointAndMark` (scenes/point_and_mark.gd) is the studio's glue for slice 35, and is not a surface.
O drops a sticky note, a `NOTE ` marker (see *The song's key is written in its markers*), at the
hovered time or at the playhead, then asks for its words: NamePrompt at a desk, as the deck's
rename does, or a TypingPad over the note pad in a headset. Enter with Z held, or a pinch of
thumb and middle by the pointing hand, plays from the pointed time. `NotePad`
(hardware/console/note_pad.gd) is a desk prop on the wing's outer strip (`Studio.WING_PAD`); in AR,
where there is no wing, it stands at the console's left end (`Studio._place_note_pad`). It
does not know about the song: drag a card off it, let go over something, and it emits `stuck` with
what was under the ray. Listening is `Session.listen_from`, `DAW.seek` then `DAW.transport_play`,
which are intents on a guest. The room is told `Ada: listen from 1:23 (CHORUS)` by the host (a
guest asks with `_listen_asked`), so the line comes from one place.

### One hand per control, decided by the host

Two people dragging one fader produce a value that belongs to neither of them. Grabbing a
control therefore **claims** it from the host, which keeps a `holds{key: peer}` table and
grants claims first-come. Everyone else is told; their copy of the control gets `claimed_by`.
It then refuses grabs and nudges, wears the holder's colour on its rim, and still follows the
holder's values as they arrive. A losing claim gets `hold_refused` and the local grab is let
go. A participant who leaves frees every hold they had.

### One undo step per gesture, by edit group

A fader's drag is many writes to one control, and `OfflineBackend._remember` folds those by time
(`GESTURE_MS`) into one step, as Reaper does. A gesture that writes several values -- a grouped
fader taking its group, pan and volume at once, a send and a threshold -- alternates between
controls, and folding by control made a step of nearly every frame. So a gesture brackets itself:
`DAW.open_edit(name)` on the grab and `DAW.close_edit()` on the let-go (a ControlAffordance with
`edits_as_one`). Between them, everything that player writes is one step, whatever it writes: a
control written again keeps where it started, switches and lane edits keep their order, and undo
takes them back last first. Each player has their own: `DAWBackend.acting_peer` says whose a
write is (`DAW.apply_intent`'s `from`, the guest's peer id; 0 for the host's own), a guest's
open and close are intents like its writes, and another player's write in between is a step of
its own, and so are the writes the host makes in answer to a guest (her take placed, her room
ask carried out: `DAW.on_behalf_of`). An edit closes on its let-go, after `EDIT_IDLE_MSEC` (10 s)
with nothing written, and when its player leaves (`DAW.close_edits_of`), so a lost let-go cannot
hold history open. Any undo or redo, by anyone, ends every open edit's step but keeps the edit:
the undo takes the step back whole, and what a hand still on the control writes next is one fresh
step rather than a step a frame. A scroll on an `edits_as_one` control is one edit too: the first
notch opens it, and notches closer together than `GESTURE_MS` share it. On Reaper (`EDIT_GROUPS` only with the bridge) the bridge verbs inside an edit are
held, shown on the cache at once, and sent at the let-go as one `Batch` request that the bridge
runs inside one Undo block, the handlers' own blocks stood down for it; OSC writes have no block
to share and stay Reaper's own undo points, one per control.

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

### Joining by a code, from anywhere

A session across town used to need an address and a router that agreed to forward ports
(`InternetDoor`, UPnP). **Host online** asks a noray server instead
([foxssake/noray](https://github.com/foxssake/noray); dawlings runs one at
`dawlings.jacobsabella.com`) for a six-character join code. A guest types the code under
**JOIN BY CODE**. Neither of them needs an address or a router setting. The full account is in
docs/multiplayer.md; in short:

- **`NorayLink`** (core/session/noray_link.gd) is dawlings' own client for noray's line
  protocol: `register-host` → `set-oid`/`set-pid`, the private id sent over UDP from the socket
  being registered, then `connect <code>` (the punch) or `connect-relay <code>` (the relay).
  noray's refusals come back quoted, and are kept in words. The host registers its ENet server's
  socket through `socket_send`, and confirms the registration by asking `connect` to its own code.
- **The guest** (`Session.join_by_code`) registers its own UDP port, and has ENet dial from that
  port. Its phases are `finding`, then `punching`, then `relaying` if no punch connects within
  `LINK_SECONDS` (6 s). It ends up `link_kind` `"direct"` or `"relayed"`. The panel and the host's
  roster (`route_of`) say which. **The host** (`Session.host_online`) punches toward every address
  noray announces, from the ENet socket, ten times a second for three seconds.
- **The mix** has its own socket, so it gets its own noray registration (`mix_online`). The host
  registers it through `MixFeed.send_raw`, on the feed's thread. The guest receives the mix's code
  with its ticket, then punches or relays its own mix socket (`mix_route`). If neither is heard
  within 3 s, the mix is **carried** over ENet channel 9 (`MixFeed.carried`). That is a last
  resort: the probe measured it at 110 ms behind, against 22 ms on the mix's own socket.
- **The door is unchanged.** A guest by code is pending until its `_hello`, which carries the door
  code. Tickets still gate the mix. The join code finds a session and is not a secret.

`tools/session_probe.sh` with `PROBE_NORAY=1` (or `=relay`) runs the whole session probe through a
real noray on this machine (`tools/noray_local.sh`). The guest joins by code, and every other check
has to pass unchanged.

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
- **Typing in a headset** is a `TypingPad`: keys in the room, pressed by hand, that answer as a
  `NamePrompt` does (`answered`). The timeline's NAME opens one in front of the panel where the
  viewport is XR (or `type_on_desk` is set); tested with a hand, untried in a headset.
- **No delta compression.** The full volatile frame goes out every tick.
- **A door, not a lock.** With a session code, only those told it get in. Nothing is encrypted,
  so the code is for a studio LAN with a neighbour on the wifi, not for the open internet.
- **Online by a code is unencrypted too.** A relayed session passes through the noray server as
  it is. A real symmetric NAT (a phone tether) has not been measured, only the relay forced on one
  machine. See docs/multiplayer.md, *Not done*.

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

### The song's key is written in its markers

`Harmony` (core/music/harmony.gd) reads a key and a chord a bar from brackets at the end of a
marker's name, `Intro [A minor: Am F C G]`, and `Harmony.at(state, seconds)` answers the key and
chord at any song position by counting bars from that marker with `MixState.bar_at`. Markers
already replicate, undo, save through Reaper and .dawproject and are edited on the 2D ruler, so
the harmony needs no DAW verb and every machine reading the same markers hears the same chord.
Before the first bracket it is `Harmony.NONE` (C major, `named` false). Everything that shows a
marker as a section shows `Harmony.section_of(name)`, the name without its brackets: the chalk
board, the tape deck's section and locator text, the 3D ruler's flags (with the harmony as a
second line) and the region page's ADD name. A marker that is only brackets names no section.
Only the 2D ruler shows the whole name, because that is where it is typed. A marker named `NOTE ...`
(`Harmony.NOTE_PREFIX`) is a sticky note, not a section. `Harmony.parse` returns null for it, and
`section_of` returns "", so every section reader skips it, and so do PREV and NEXT on the deck.
Brackets in a note are words, not harmony. The 3D ruler draws a note as a card over its time,
and the whole card is a LISTEN key (`TimelineSurface.listen_asked`). A note is kept 1.5 ms off any
marker at the same time (`Harmony.note_spot`), so it never renames one. The stand-in's Intro
carries `DemoSong.HARMONY`, so the demo song is in its own key. docs/spatial_loop.md has the
decisions.

The key and chords are also written from the room, on the circle-of-fifths wheel on the bricks
table (`FifthsWheel`, `core/music/fifths_wheel.gd`, stood by the studio at `Venue.wheel_spot`).
Its key and strip of chords are each player's own; SET writes `[key: chords]` into the markers at
one bar (the next while playing, the playhead's while stopped): onto a marker already there, its
section kept and its old brackets replaced (`Harmony.written`, `DAW.edit_marker`), or as a marker
of brackets alone (`DAW.add_marker`). That is one undo step, still no DAW verb, and nothing before
the bar changes. A guest's SET is a room ask, `harmony` [bar, inside], so the host writes at the bar
the guest chose rather than at its own playhead, and the markers replicate as any edit's do.

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

Later the bay stopped being jacks at all (see the pin matrix above). With a session past a
dozen tracks the cables and mults were a thicket nobody could read from the seat, and the
answer to "which tracks send where" is a grid, which a pin matrix is in hardware: one pin a
crossing, so one hole holds one plug by construction and the mult and its test went with the
cables. The rule still holds: the matrix's pins are a real patch field's, and a crossing the
mix cannot take (a self-send, a loop) is a blocked socket that says so, not a pin that quietly
does nothing.

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
| `dawlings · hits` | this player's own strikes and shakes, a few milliseconds after the hand | `NativeKeys` started with no MIDI (`Monitor` bus where not) |
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

### Strikes on the fast path

Everything struck by this player's own hand (a shaker, a bell, a drum's head: every
`InstrumentItem`) answers a hand as the keys do, so it takes the same road (docs/spatial_loop.md
part two, slice 39). `native/keys.c` also holds one-shot sample voices: `load SLOT PATH` reads a
48 kHz 16-bit mono WAV into one of 256 slots (`SLOTS`, mirrored as `Foley.HIT_SLOTS`; 128 until slice 42's seven sounds took Foley's struck sounds past it; slice 43's eight bring them to 44 kinds, 176 slots), on the helper's main loop, and answers `loaded SLOT
FRAMES` or `refused SLOT WHY`; `hit SLOT GAIN PAN [SPEED]` plays it once on one of 16 voices (the
oldest stolen), in the realtime callback, added after the tine's saturation so it is its WAV at
that gain exactly. A slot loaded again stops its voices there and hands the old samples back to the
main loop to free. `--parse` says what each line was taken as, and `--render` plays hits as it
plays notes, for the suite.

The studio starts a second helper of its own, `dawlings · hits` with `--no-midi`
(`Studio._start_hit_voices`), wherever the keys' helper could run. At launch `Foley.write_hits`
writes every one of `Foley.SOUNDS`' `TAKES` takes, read across from Foley's 44.1 kHz to 48 kHz
(`hit_wav`, `resampled`), to user://hits/ on a worker thread (`NativeKeys.load_hits`), and `poll`
loads each into its slot (`Foley.hit_slot`: its place in SOUNDS times TAKES, plus the take).
`InstrumentItem.play` asks `InstrumentItem.fast_path` (the studio's `_hit_on_fast_path`) first,
with the hit's Foley kind (its zone's, on a fixed one), take, level (`monitor_gain`: `level_db`
through the Monitor bus's own fader and mute), pitch and a pan of HAND_PAN (0.3) to the side of
the hand that played it (`XRInteractor.hand_side`, `Strike.side_of`; the mouse is the middle). It
is played there when the helper holds that slot, and on the Monitor bus through Godot otherwise:
not started, its sounds not loaded yet, a kind with no slot (the duck), or the helper gone, which
`_follow_hit_voices` notices and drops mid-session. A bandmate's hit is never sent there: it is
placed in the room where they hold it or where it stands, and placing is Godot's. Each
instrument's hover card and, in a headset, its tag say which way its hits are heard and how late
(`InstrumentItem.path_tag`: "FAST PATH · 5 ms", "MONITOR · 41 ms"), from the helper's own
`latency` once it has measured a hit, two cycles before that.

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

Four kinds are not shared: the mic, the headphones, the tablet and the keytar
(`ItemRoom.PERSONAL_KINDS`) are each one player's own, so the shelf's instance of one is a
dispenser, never itself held. `Item._on_grab_begin` hands a grab of one of these to
`ItemRoom.take_personal(kind, peer)` instead of `Interactor.pick_up`, which spawns (or finds) a
copy under its own id, `"<kind><peer id>"`, built on the same `spawn`/`bound_to`/`may_hold` that
Tour's spilled instruments already use to bind a spawned item to one peer's hand. The host hears
it as a room ask (`take_personal`), idempotent like `spawn` itself, so a prediction that beat the
ask there is a no-op. The copy has no home of its own: a put-down (`ItemRoom.retire`) despawns it
rather than sending it back to a shelf spot, though pocketing one still works, since a pocket was
already a hand's own. A guest's `apply()` spawns a peer's copy the moment it appears in the
room's state, not only once it is already known locally, which is what lets a brand-new id reach
a guest at all; every other kind still relies on already knowing its id.

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
following mute, and in time because it plays the track's lane (or, without lanes, because
`_sync_players` keeps it to the song clock). It plays to
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

Each note also carries its `source`: what of the player's played it (`GuestMidi.instruments`'
names, `&""` for plain keys; the host takes a name over `Session.NOTE_SOURCE_MAX` as plain keys).
Two instruments can hold the same pitch, so wherever one player's notes are sounded on one synth
(their own monitor, `TheirKeys`, `TheirMonitor`) a `KeysDown` (`core/session/keys_down.gd`) counts
each pitch by source, and its note-off is sounded only when the last source lets it go.
`Presence` plays only a keytar holder's keys notes (`&"keytar"` or plain) out of the keytar.

Beside the notes go the controls: the pitch wheel (`DawKitClip.PITCH_BEND`), the mod wheel (CC 1)
and expression (CC 11), `GuestMidi.control(kind, value, source, at)`. They travel by
`Session.send_control` on `CONTROLS_CHANNEL`, unreliable and ordered, so a lost one never holds a
note-on back behind a retransmit; notes stay reliable on `KEYS_CHANNEL`. The host passes those
three (`Session.CONTROL_KINDS`), clamps each by kind (`control_value`: -8192 to 8191, 0 to 127),
refuses any other (`controls_refused`) and emits `control_played` everywhere else. A player has
one wheel, as a keyboard does: it belongs to the source of their newest held note
(`GuestMidi.wheel_source`, from `KeysDown.newest`), and another source's moves are dropped until
it does, so two instruments never fight over one voice. A control off its rest
(`Session.control_rest`: the wheel centred, the mod wheel down, expression full) is sent again
at least every `GuestMidi.CONTROL_EVERY` (50 ms), and at the player's last note-off every end
rests it by itself, so no reset has to arrive. Each receiver (`TheirKeys.control`,
`TheirMonitor.control`, which queues it in the line with the notes, and `ChordHarp.heard_control`
through `Presence`) plays a control only while that player has a note down, because a resend
overtaking the last note-off on its own channel would otherwise leave the wheel off rest with
nothing to put it back; one moved before a note is sent again right behind the note-on. Controls
sound through `MonitorSynth.control`, into the render thread's queue to `DawKitTine.control`, or
to the native helper as `bend V` and `cc K V` lines (`NativeKeys.control`), which bend every
voice's increment and scale the output by expression, as the tine does. Neither plays the mod
wheel; it is kept for a track's own instrument.

A take keeps the controls too (docs/spatial_loop.md slice 14). `MidiTake.control` thins them as
they come: a move is kept when it has gone `BEND_STEP` (32) for the bend or `CC_STEP` (1) for a CC
since the last one kept of its kind *and* `CONTROL_GAP` (8 ms) has passed; a move that is neither
waits, and the latest one waiting is kept once it has stood `CONTROL_HOLD` (50 ms), a note lets go
or the take ends, so where a bend came to rest is exact. No two land closer than 8 ms, and there
are at most `MAX_CONTROLS` (20,000). The player's last note-off puts the wheel back at rest in the
take as it does everywhere else, kept whatever the thinning says, so an item never bends its next
note. A hardware keyboard's controls go in on its own MIDI channel, as its notes do. Its mod wheel
and expression are not sprung and are never sent again, so the plain keys remember where they
stand (`GuestMidi._hardware`); a plain-keys note-on that takes the wheel puts them back, heard,
sent right behind the note and kept in the take, after a note-off rested them. The helper's wheel
moves are stamped where they were played (`song(age)`), as its notes are. A MIDI item's hover card
names its controller events (`TimelineLanes.controls_text`: "mod wheel 4, pitch wheel 2"). `finish()` gives `controls`, flat `[time, kind, value, channel]` in song seconds, which
`insert_midi_take` carries as its sixth argument; `clean_args` refuses any row whose controller is
not one of `MidiTake.CONTROL_KINDS` (which `Session.CONTROL_KINDS` is) or whose value is out of its
kind's range, and pulls each time inside the take. Every backend puts them on the new item,
counted from its start (`ItemState.controls`, which the built-in engine renders with the notes
and the wire carries whole: `MixWire.CONTROLS_MAX` is `MAX_CONTROLS`). Reaper's bridge writes them
with `MIDI_InsertCC` (`0xE0` and the wheel's fourteen bits, low then high; `0xB0` for 1 and 11)
after the notes, inside the same Undo block, and its timeline poll reads them back
(`item_controls`, 2,048 an item, like the notes' sketch). A MIDI keyboard's wheels come in as the
plain keys' (`&""`) controls: `GuestMidi._input` reads `MIDI_MESSAGE_PITCH_BEND` (0 to 16383 in
`pitch`, less 8192) and CC 1 and 11; where the native helper reads the keyboard it passes them on
as `wheel V` and `ctl K V` lines without playing them, since whether this player's wheel takes them
is `GuestMidi.control`'s to say.

What moves the wheel without a keyboard is the playing hand (docs/spatial_loop.md part two, slice
15). `Wobble` (`core/music/wobble.gd`, a RefCounted, one per playing hand on each instrument that
bends: `KeytarItem.wobble` on the hand holding it, `ChordHarp.wobble` on the hand that plucked last,
`FingertipNotes.wobble` on its own hand, and `MouseInteractor`'s own for the plain keys) is stepped
each physics frame. It reads its hand's `Interactor.tilt_angles()` (`HandPose.angles_of`: roll and
pitch in radians, unclamped, of which `tilt()` is the clamped form; a bare hand's `HandGestures
.angles`, a controller's aim, the mouse's wiggle) and, only while one of its `sources` owns the
wheel, sends one bend through `GuestMidi.control` with that source, at most 60 a second and only
when it changed. The bend is measured from the roll at the moment its source took the wheel (a
note's press, or the first after every note let go, `GuestMidi.rests`), wrapped to half a turn:
`sign(d) * clamp((|d|/45 - 0.08) / 0.92, 0, 1) * 2` semitones, so a bare hand level palm down and a
controller level thumb up bend alike, and a hand held tilted before it played bends nothing. The
wobble is the roll band-passed from 3 to 8 Hz (two one-pole high-passes and a low-pass), the
hand's own shake rather than an LFO, up to 0.4 semitones; the bend is read from the roll less that
shake, so a tremble is not also a bend. `GuestMidi.tilt_bends` ("Tilt bends" in the session panel)
off, the tilt counts for nothing. The hand's `bend_wheel()` is added: the desktop's Alt with the
mouse moving up or down, 100 px a semitone, springing back as Alt is let go
(`MouseInteractor.bend_by`). So nothing new crosses the wire: a tilt is a bend like any other,
heard, sent, rested at the last note-off and kept in the take. The mouse's wiggle runs while an
instrument or the keytar is carried, the fingers play, or the cursor rests ungrabbed on a control
that `plays_under_cursor()` (the harp). `KeyCatcher` gives only Ctrl and Meta keys to the studio,
and a key let go always sends its note-off.

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

A tracked bare hand holds the shaker and the tambourine (`InstrumentItem.held_in_fist`) by
closing round them, not only by a pinch (`XRInteractor.step_hold`, docs/spatial_loop.md slice 17):
three fingers past `HandPose.HOLD_CURL` with the palm within 6 cm of the item's `grip_point`, taken
as the hand closes. It lets go only after 0.1 s open on confident frames (`HandGestures.confident`:
every joint seen, not inferred); a hand tracked with guessed joints goes on carrying it at the palm
and playing it. It holds through a tracking loss where the hand was last seen for `LOST_HOLD`
(0.4 s) and then sends it home, and throws only from the palm's speed over confident
frames. Its strokes are the palm's (`shake_point`, levered by `shake_lever`), and none are felt
while the hand is not tracked (`shake_tracked`). A hand carrying anything is not one of XRRig's two
escape fists (`XRRig.escape_fist`). `HitRecorder.hit` snaps a hand percussion hit's recorded
stamp, never its sound or its sent `at`, half way to the nearest sixteenth when within 35 ms
(`snapped_at`), by its player's flag (`GuestMidi.snap_hits`, "Snap hand percussion" in the
session panel, in a box of its own after the keys, shown whatever the DAW), which
`Session.item_hit` carries with the hit's Foley take (`snap`, `take`).

An instrument that stands still (docs/spatial_loop.md part two, slice 38) is still an
`InstrumentItem`, with `Item.fixed` set: a drum head, a chime, a pad. It is never carried. The
grab contract's `grab_begin` on it is let go of at once and is a strike where it landed
(`Item.struck_by`, `zone_at`), at 96 or with the fine modifier (Shift) 64. `Interactor.pick_up`,
`Item.follow` and ItemRoom's `lay`, `throw`, `fly`, `pocket`, `put_down` and `apply` all leave it at
its station. A headset strikes it through `Strike` (`core/music/strike.gd`), a node the studio
stands. Every physics frame Strike reads this player's own striking points (`Strike.points`): each
`HandGestures` hand's tips and palm and its poke's tip while the hand is `confident`, and each
`XRInteractor` controller's tip and grip point while its pose is HIGH confidence. A strike is a
point crossing one of the instrument's `faces` inward faster than 0.4 m/s
(`InstrumentItem.velocity_for` of the speed along the normal). A point must be seen on both frames
and must not jump more than 0.25 m, and each hand strikes each instrument once per 70 ms. Where it
crosses is a `zone`, which `played`, `ItemRoom.played`, `Jacks.hit`, `HitRecorder.hit` (its note,
`zone_note`), `Session.send_item_hit`, `item_hit` and `heard` all carry. The host passes on only a
short word (`Session.clean_zone`). Nobody holds a fixed instrument, so `Presence._on_item_hit` plays
a bandmate's strike on it from where it stands, whoever sent it, and the studio sends the strike as a
hit rather than a use. `TestDrumItem` is the suite's and the probe's fixed kind and is never in
`ItemRoom.KINDS`.

The first fixed kinds a player meets are the circle of hand drums (`HandDrum`,
`core/items/hand_drum_item.gd`, slice 40): `djembe`, `conga_hi`, `conga_lo` and `cajon`, last in
`ItemRoom.KINDS`. They stand round the drum riser's middle (`Venue.drum_ring`, `drum_circle_spot(n)`,
`DRUM_RING` 0.72 m out on the diagonals, the ring's front toward the mix position), on what a person
stands on there (`Venue.drum_floor`: the riser's top where it is a step in `zone_solids`, the floor
where it is only drawn, as in the chalk zone), each on a stand `HandDrum.STAND` (a riser's height)
tall, so a head is as high above the feet of a player on the riser as it would be on the floor, as the studio's
`_item_homes`, and the ring's middle is the station `drums` (zone `drums`), where the studio stands
the plaque on a post (`Studio.drum_circle`). A fixed kind in KINDS never takes a shelf spot:
`ItemRoom._rehome` stands it at its home or, where the venue has none (the Rig Roulette room, AR),
puts it away (`ItemRoom.stand(id, null)`: hidden, PROCESS_MODE_DISABLED so out of the physics, and so
not struck, since Strike reads only what is seen). `ZoneKit.solids` adds each drum's footprint on the
riser, so the walker goes round them and a throw bounces off them. A round head's zone is by radius
(bass inside 0.35, slap past 0.8, tone between); the cajón's head is its front face (a rectangle
face), its top 10 cm the slap and the rest the bass. Each zone is its own Foley sound
(`Foley.hand_drum(kind, zone, take)`, named `<kind>_<zone>` in `Foley.SOUNDS`, so each has fast-path
slots: 29 kinds at four takes, 116 of what was then the helper's 128) and its own General MIDI drum on channel 9
(`HandDrum.NOTES`), which ItemVoices plays back as drums.

The drum pads (slice 41) are one more fixed kind, the room's shared `kit` (`KitItem`,
`core/items/kit_item.gd`), last in `ItemRoom.KINDS`, whose faces are six pads on the console's front
rail (`ConsoleSurface.pad_rail`, under the strips' middle; the studio stands the kit there every
frame it has moved, `Studio._follow_kit`) and this machine's own pads on real surfaces
(`SurfacePads`, `core/music/surface_pads.gd`, `KitItem.surface`). A face's zone is its drum (`kick`,
`snare`, `hat`, `clap`, `tom`, `rim`: GM 36, 38, 42, 39, 47, 37 on channel 9, rung as Foley's kick,
snare, hihat, clap, pad and rim), chosen by the nearest face's middle. SurfacePads keeps up to eight
pads in the session frame (`frame`: RoomAnchor times `XRRig.away_from_home`, so a pad stays on its
real surface when the play space travels) and saves them to `user://pads.cfg`, never to the room. A
pad is marked while MARK on the PADS card (`SurfacePads.build_card`, hung off the rail under the
kit) is on: a confident index tip, or a controller's tip with its trigger held (`mark_points`),
still within 12 mm for 0.6 s (`dwell`); its face is level for a tip that came down from above, else
across the way it came in (`plane_of`), and lifted 6 mm out of the surface so a tap the real
surface stops still crosses it. A dwell on a pad takes it away, and while marking a strike on one
steps its drum. Each marked pad is a `SurfacePads.Pad` affordance for a ray (a click or trigger
strikes it, a nudge steps its drum). An unplugged instrument may say where its hits go by default
(`InstrumentItem.default_sink`, `Jacks.goes_to`): the kit's is the drum track (`KitItem.drum_track`:
a track named DRUMS, else the first whose demo part is a drum's), never a bandmate. Since a
bandmate's pad may be on their own knee, `Presence._on_item_hit` rings their hit on the kit from a
glove of their ghost (`KitItem.heard_at`, `InstrumentItem.ring_on`). AR's ItemRoom makes only the
kit (`ItemRoom.only`, `AR_KINDS`), so the hits' wiring (HitRecorder, Strike, Jacks) is built there
too. At a desk 4 to 9 strike the rail's six (`Studio.strike_desk_pad`), Shift softly.

Every venue has something to play (slices 42 and 43). `VenueInstrument`
(`core/music/venue_instrument.gd`) is a set of tuned bars, and it adds a third kind of fixed
instrument: a pitched one, struck where it stands. Every venue in `Venue.IDS` has one; the Rig
Roulette room has none and no station row for one.

- **The bars.** The room makes eight fixed bars (`VenueInstrument.Bar`, kinds `venue1`..`venue8`
  in `ItemRoom.KINDS`, after the hand drums). They are dressed differently in every venue.
- **What the venue says.** A venue says what it has in `Venue.instrument()`: a `kind`, a `count`,
  a `spot` and a `low` note. `VenueInstrument.filled` fills in the rest from the kind
  (`VenueInstrument.KINDS`): title, shape (HANG, STAND or LIE), sizes, look, sound and help lines.
  `Venue.back_wall_instrument` and `side_wall_instrument` place a set against a wall, and
  `instrument_solids` adds its footprint where the room is solid.
- **Standing a set.** The studio stands the set's mount, a VenueInstrument node in the venue at
  its spot, which holds the mount meshes, the plaque and the set's one JackSocket. It then dresses
  the first `count` bars as the set (`VenueInstrument.dress`) before their homes are stood
  (`VenueInstrument.homes`, merged into `_item_homes`). A bar with no home is put away
  (`ItemRoom.stand`).
- **Pitch.** A bar's note is a scale tone (`VenueInstrument.scale_tone`): the n-th pitch class of
  `Harmony.scale` (root first), up from the key's root nearest `low`, each above the one before.
  So the set follows the song's key at every bracket, and each bar letters the note it rings now.
- **Striking.** A bar is struck through `Strike` on its faces. A vertical bar has four sides (the
  railing's three), so a brush across a row rings each bar in turn, and a tubular bell also has
  its cap. A lying bar is struck on its top. At a desk it is the Item grab's click, and
  `VenueInstrument.brush` strikes each further bar a held drag comes onto.
- **Sound and recording.** A strike plays and records as every pitched item does: the fast path
  with `Foley.venue_bar(kind)` pitched from `Foley.venue_bar_note(kind)`, `MELODIC_CHANNEL`, and a
  bandmate's copy rung where it hangs at their song position.
- **One jack for the set.** `InstrumentItem.jack_source` and `has_own_jack` make the whole set the
  one source `VenueInstrument.SOURCE` (`venue`) for `Jacks.hit`, the socket and the patch. The
  studio's plug checks find its item through `ItemRoom.source_item`.
- **Its station.** The set is the station `venue` (area VENUE, `mounted`). `Stations.row_in(venue,
  id)` merges `VenueInstrument.row_for` into the row: title, help lines, look point, frame and
  seats. `Stations.row` reads it for the venue the studio is in (`Stations.here`), so the help card, the
  board, I and the plaque all name that venue's set.
- **Its seats.** A desk's seat (`seat`, `VenueInstrument.seat_for`) stands back as far as it takes
  for a standing view at the room's lens to hold the set's top and its plaque's foot. A headset's
  seat (`reach`) is `VenueInstrument.REACH` in front of the set, within a hand's reach;
  `Stations.seat(..., hands)` picks it for `Studio._travel_to_station`. The plaque and the jack
  stand in front of `VenueInstrument.front_of`, which is the mount's front where that stands out
  further than the bars (the crystals' shelf).
- **Its mounts.** The cave's shelf, the bells' frame and the icicles' eave are modelled
  (`tools/blender/venue_mounts.py`, `VenueInstrument.MOUNTS`, placed by object name in `_piece`),
  and so are slice 43's steam pipes' header, valve and tees, the pots' bench, the gong rack and the
  desert's sandstone ledge.
- **Slice 43's shapes.** A set's geometry is per bar (`bar_x`, `bar_frame`, `bar_length`,
  `bar_radius`, `bar_depth`, `bar_shape`), and `half_width`, `half_depth`, `front_of`, `back_of`,
  `top_of` and `bottom_of` are taken over every bar. A kind may have flat bars (`plate`: the hull
  panels, the glass), set round an arc (`arc`: the panels face the ring's middle), bars that grow
  with their length set their own width apart (`grow`, `gap`: the pots), round bars (`disc`: the
  cymbals), and a gong hung behind the rest as the first bar (`gong`, with its own sound). A bar may
  ring slower than a strike (`InstrumentItem.strike_least`, `velocity_of`, which `Strike` reads):
  the dome's glass rings at a touch, softly. A curved mount (the hull's ribs, `_arc_band`) is
  smooth pieces end to end (`ARC_PIECES`), so each piece's bounds hug the band and a plaque in
  front of the ring is not inside one box round the whole bend.
- **The piano.** The club's instrument is its upright's middle octave (`ClubVenue.piano_case`,
  `instrument`). club.glb and club_showtime.glb leave that octave's keys out (club.py's `GAP`), and
  the set's eight keys lie in their place, the scale's notes. The mount's sunk black keys
  (`VenueInstrument.pattern`, `_repattern`) stand in each slot between two keys a whole tone apart,
  level with them, and each key's tail is notched round them (`Bar.notch`). In the speakeasy the
  piano stands against the back wall by the stage.

Generative weather (slice 44). `Weather` (`core/music/weather.gd`) is a schedule and a station.
Four arrangements have one (`Venue.weather`): the loft's Thunderstorm, the greenhouse's Rain, the
cabin's Snowy night, and the cave's `drips` in the grotto and on the lake.

- **The schedule is a pure function of the song clock.** `Weather.drops(spec, seed, state, from,
  to)` walks the sixteenths in the span. For each one, `mix(bar, step, seed)` decides whether a
  drop lands (against the arrangement's `density`, which the storm gusts over `GUST_BARS`), and
  where it lands on the glass. The cave allows one candidate a bar. The seed is an FNV-1a hash
  of the venue id (`seed_of`). The note is the scale tone (`VenueInstrument.scale_tone`, from
  `Harmony.at`) of the drop's height on the glass, or of its pool. Every machine with the same
  song therefore schedules the same drops, and nothing crosses the wire but the switch.
- **The switch is a room row.** `weather` (LISTEN or OFF, false when a room starts) is a room
  verb of one bool (`Session.ROOM_VERBS`). A guest predicts it, as the sampler's REC does
  (`Studio._on_weather_pressed`, `_predict`, `apply_room`). The station `weather` is a mounted
  row that `Stations.row_in` fills from `Weather.row_for`. Its switch, plaque and jack stand on
  the window's sill, or on an iron post (`solid`) where there is no sill.
- **Its jack is a world source.** `weather` and `drips` are in `Jack.WORLD`: sources that are not
  items. They go onto a track only (`Jacks.sinks`, `plug_refusal`). On the host, each drop that
  lands while the song records becomes a note on the plugged track (`HitRecorder.note`, the
  jacked take), whether the switch is on LISTEN or OFF.
- **Sound and drawing.** A heard drop is a Foley emitter at its landing (`Foley.weather_drop`,
  synthesised and pitched to its note). Drops are drawn in two MultiMeshes, beads and rings. At
  `Ergonomics` motion 0 a bead stays where it landed and fades, and a ring keeps one size. With
  motion, beads run down the glass and drips fall into their pools. The venue's particle rain
  is still only decoration.

A looper, by hand (slice 45). `Looper` (`core/music/looper.gd`) is a pad on a tripod stand at the
drum riser's front corner (`Venue.looper_at`, `looper_spot`; its foot is a `ZoneKit.solids` entry
marked with its station), station `looper` (LIVE, mounted on the `drums` zone).

- **Who loops is a room row.** `looper` [peer, from_bar, bars] (`Session.ROOM_VERBS`, [] for
  nobody). A slap is planned where it is heard (`Looper.plan`: the loop's own bars when a loop is
  set, else the next bar for the player's LENGTH, or -1 with the transport stopped) and answered on
  the host (`Looper.answer`): another player's row refuses it (`ADA is looping`), a stopped
  transport is started from the start of the current bar, a far bar becomes the next one, and a
  first layer sets the loop range to its span and turns looping on. A guest predicts the row
  (`Studio._predict`) and the host's room is the truth.
- **The layer is taken down where it is played.** Each machine's Looper follows its own heard clock
  (`GuestMidi.heard`): COUNT until the song arrives at the span's first bar (crossing it, or the
  loop going round to it), REC until its end. It takes this player's keys from `GuestMidi.sends`
  (every source that goes through GuestMidi) and their hits from the studio's `items.played`, the
  hits as HitRecorder would (snapped, zone notes, channel 9). A key a hair before the first bar is
  its downbeat (`EARLY`).
- **The host writes it.** `looper_layer` [start, end, notes] goes to the host, which writes it only
  while the row is that player's (`Looper.write_layer`: a LOOPER folder at the end of the project
  the first time, then `<PLAYER> LOOP n` in it, one MIDI item over the span), and clears the row.
  A guest's write is the guest's (`DAW.on_behalf_of`, which Session wraps room asks in).
- **Screen in words and shapes.** REC beside a disc, PLAY beside a triangle, READY beside a
  square, COUNT with the beats left as large dots; who and which bar in words, and the beat as a
  row of large and small dots.
- **Layers are rings on its post (slice 46).** `LooperRings` (`core/music/looper_rings.gd`, the
  looper's child `rings`) draws the project's LOOPER folder (`LooperRings.layers`), so every
  machine's mirror of the host's mix shows the same stand: a ring a layer round a post over the
  stand, inside its footprint, lettered `ADA 2`, turning once a pass (`turn_of`, a beat a step at
  motion 0), as bright as its track's level (`SignalBeads.glow` of `track_level`). It reads this
  player's hands itself (`hands_in`, `step_hands`): a grip or a pinch begun with the hand inside a
  ring's band (`band_of`) takes it, and nothing else does (a brush, a poke, the ray, a dwell). A
  grab is one edit (`DAW.open_edit`/`close_edit`): the mute it toggles, and `remove_track` if it is
  pulled past PULL (0.4 m). A click on a ring toggles its mute, and the `LayerList` over the screen
  has MUTE and X per layer. A guest's writes are DAW intents like any edit, and its ring shows the
  mute or its going at once (PREDICT_MS) until the host's mix says so. The ring's toasts go out
  through the studio (`told`).

A music-box sequencer (slice 47). `MusicBox` (`core/music/music_box.gd`) is a brass cylinder of 16
steps by 8 rows on a case on a plinth of its own (tools/blender/music_box.py), station `music_box`
(LIVE, free-standing, a `Venue.WHEELED` trolley at `Venue.music_box_spot`: beside the harp away
from the bells, or up the loft's aisle).

- **The pattern is one MIDI item, read back, never kept.** Its pegs are the notes of the first MIDI
  item on its track under its bars (`item_of`, `pegs_of`), each frame: a note moved in the roll
  moves its peg, an undo takes it back, and every machine's mirror shows the host's pegs. Its bars
  are the loop's, a LENGTH a page, else the playhead's page (`span_of`); its rows the scale of the
  song's key at its first bar (`Harmony.at`) from a root, or semitones (`rows_of`). A note on no
  row is drawn at the nearest one, leaning and collared (by shape).
- **A peg is an ordinary edit.** A press is `DAW.insert_note` or `delete_note` inside
  `open_edit`/`close_edit`, and a drag along a row is every cell it passes in the same edit, so one
  undo step either way. Where there is no MUSIC BOX track or no item, the first peg asks for them
  (`add_track`, then `insert_midi_take` with the pegs so far as notes) and the rest wait in a queue
  (`flush`). On a guest these are DAW intents like any edit, its pegs shown at once (`_predicted`)
  until the host's mix says so, and it waits for its mirror to show what it sent before naming a
  note index again.
- **Its settings are a room row.** `music_box` [track, length, root, chromatic]
  (`Session.ROOM_VERBS`), cleaned on the host (`MusicBox.clean`) and predicted on a guest
  (`Studio._on_music_box_asked`, `_set_music_box`, `apply_room`); the four keys on its front step it.
  The view's own turn (`view_steps`) is this player's alone: by the wheel or a stick over the
  cylinder, or by a hand on the knurled `Thumbwheel` past its right cheek (pushed up or down, or
  pressed for a step), which is how a tracked hand, with no wheel or stick, reaches the steps
  round the back.
- **It turns with the song.** `turn_of` puts the sounding step under the comb at the top; a peg
  reaching it flicks its row's tooth. At `Ergonomics` motion 0 it steps a step at a time and the
  teeth stand. It sounds only as the track plays.

A string across the room (slice 48). `RoomString` (`core/music/room_string.gd`) is one string
between two points the room chose, and `RoomString.Spool` the bobbin on a stand that makes them
(tools/blender/string_spool.py), station `strings` (LIVE, free-standing, a `Venue.WHEELED` trolley
at `Venue.string_spool_spot`: in the aisle between the drum riser and the lattice, or at the loft
lattice's front corner).

- **The strings are a room row.** `strings` {id: [a, b, maker]} (the ends in the venue's frame),
  asked with `string` [id, a, b] (`Session.ROOM_VERBS`), a and b the same point to cut.
  `RoomString.answer` is the rule (0.3 to 12 m, ends inside BOUND, at most 8, any id may be cut):
  the host keeps it (`Studio._answer_string`, the refusal told to whoever asked), and a guest
  refuses it in words at once where the host would, else predicts it (`ask_string`, `_predict`,
  `apply_room` folding unanswered asks back on top). The row is the studio's, not the venue's, so
  a venue change stands the same strings again in the new one (`_show_strings`).
- **Its length is its note.** `raw_pitch` is 76 - 48 log(l / 0.3) / log(40) (E5 to E1 over the
  allowed lengths), `pitch_in` snaps it to the key (`Harmony.snap`), never under E1. It is
  lettered at its middle and retuned as the key changes.
- **Played as the harp is.** A fingertip whose path goes past the line within TOUCH (`tips`, by
  default `HandGestures.local_tips`) or a grab (a click, a pinch's ray, a trigger) plucks it on
  this player's keys with source `&"string"`, ringing RING (2.5 s). It shakes in its shader (a glow
  instead at motion 0), and one `Wobble` for all strings bends what rings by the plucking hand's
  tilt. A bandmate's string notes come through `Presence.strings_heard` to the string that plays
  that pitch here (`Studio._on_string_heard`, `RoomString.heard`, a MonitorSynth of its own).
  Grabbed and pulled CUT_PULL (0.4 m) off its line, or a knot (`RoomString.Knot`) pressed, it asks
  to be cut (`cut_asked`).
- **An end is a tool in the hand.** `Interactor.tool` is a Callable that, while it is set, takes
  the hand's button in place of pressing what it points at (`_use_tool`). The spool's reel sets it
  (`Spool.take_end`; a poke's end goes to the same hand's ray, `tying_hand`). The next press ties
  the first end, and the let-go somewhere else (or, after a press and let-go in one place, the
  next press) ties the second. Where is the first thing the ray meets (`surface_hit`): any body
  but the walker's layer, the floor, the ceiling at `Venue.LIVE_ROOM_HEIGHT`, the walker's solids
  as boxes up to their tops, and the walls round the rooms a person walks in. Between the two ends
  the string is drawn with its note and length, or TOO LONG or TOO SHORT. Esc, or the reel pressed
  again, drops the end.

A marble run (slice 49). `MarbleRun` (`core/music/marble_run.gd`) is the lattice zone's 12 by 12 by
12 cells of 0.25 m with blocks in them (tools/blender/marble_blocks.py: a grooved ramp, a funnelled
drop, a splitter with a brass vane, a bell block with a bell under an arch), station `marbles` (LIVE,
mounted on the `matrix` zone at `Venue.marbles_spot`: a tray on a post at the cube's face toward the
desk, off its middle, whose foot is a `ZoneKit.solids` entry marked with its station).

- **The blocks are a room row.** `marbles` {cell: [kind, facing]} (Vector3i cells), asked with
  `marble` [cell, kind, facing], an empty kind to take one out (`Session.ROOM_VERBS`).
  `MarbleRun.answer` is the rule (a cell inside the lattice, one of four kinds and four facings, at
  most 144): the host keeps it (`Studio._answer_marble`, the refusal told to whoever asked), and a
  guest refuses it in words at once where the host would, else predicts it (`ask_marble`,
  `_predict`, `apply_room`). The row is the studio's, so a venue change stands the same run again.
  `marble_balls` (the beats of the last eight BALL marbles, asked with `marble_ball` [beat]) is a
  row beside it.
- **The marbles are a pure function of the song clock, like the weather.** A marble is let go at
  the run's top (`top_of`) on every bar's downbeat, and at each BALL beat. It walks the blocks a
  cell a sixteenth (`path`: a ramp or a bell on the way it faces, a drop down, a splitter its way
  on even marbles and the other on odd ones), never physics, until an empty cell or the lattice's
  edge, or MOST_STEPS. `rings(rows, balls, state, from, to)` is every bell entered in the span, its
  note the scale tone of its height (`VenueInstrument.scale_tone` of `Harmony.at`). Every machine
  with the same rows and song rings the same bells, and nothing crosses the wire but the rows.
- **Its jack is a world source.** `marbles` is in `Jack.WORLD`, onto a track only. On the host each
  ring while the song records is a note on the plugged track (`HitRecorder.note`), heard or not.
  Marbles never touch mix state otherwise. With the song stopped, BALL rolls a preview here alone at
  the song's tempo, never recorded.
- **A block is a tool in the hand.** A tray key sets `Interactor.tool`, as the spool's reel does.
  A mouse keeps the block for click after click; each goes in the cell `pick` finds (a grid walk
  of the ray: beside the face of the first block it meets, else on the working layer, which Shift
  and the wheel raise). The wheel turns what is carried, or the block under the cursor, Backspace
  takes one out and Esc puts the carried one back. A hand lets the block go in the cell it is in,
  and a placed block taken and let go outside the lattice is taken out. A ghost of the carried
  block, its cell's edges and words (`BELL  RIGHT  C5 · LAYER 1`) show where it would go.
- **Sound and drawing.** A ring is a Foley emitter at its block (`Foley.venue_bar`, the chime,
  pitched to its note), and its bell swings. Marbles are a MultiMesh: with motion they glide from
  cell to cell and fall as they fade from the last one. At `Ergonomics` motion 0 a marble shows the
  cell it was in on the beat, a step per beat, and the bells hang still.

A theremin (slice 50). `Theremin` (`core/music/theremin.gd`) is a walnut cabinet on a stand with a
splayed foot, an upright chrome pitch rod on its right and a level volume loop on its left
(tools/blender/theremin.py), station `theremin` (LIVE, free-standing, a `Venue.WHEELED` trolley at
`Venue.theremin_spot`: by default in front of the drum riser's outer end in the ring's frame,
`Venue.default_theremin_spot`, facing the desk; in the studio's side-room arrangement off the
riser's long edge, `StudioVenue.default_theremin_spot`). Its row has `air` 1 m round `air_at`, the
hands' place: the clearance test samples a half disc of that radius toward the station and to
either side, clear of every solid taller than the hands' lowest and on walkable floor.

- **The law is static and pure.** `pitch_for(distance)` is C6 at NEAR (0.1 m) from the rod's axis
  down to C3 at FAR (0.6 m), log in distance (each octave the same factor), `distance_for` its
  inverse; `expression_for(height)` is CC 11, 0 resting on the loop up to 127 VOLUME_SPAN above.
  `target_for` is the SCALE switch: FREE, the nearest scale step (`Harmony.snap`) or the nearest
  chord tone, inside the range. Snapped, the played pitch glides to the target (GLIDE, 50 ms).
- **One note on the keys, bent, handed on.** It plays this player's keys (GuestMidi) with source
  `&"theremin"`: its first note goes down after its CC 11 and bend, so it sounds where it should
  from its first moment; within `Wobble.BEND_MOST` (two semitones) it is bent, and past that the
  nearest note goes down, bent to the hand, before the last lets go (`handed_on`), so no frame is
  silent and the take is legato notes, bends and CC 11, which play back on any synth. Controls go
  at most 60 a second. The volume hand down on the loop lets it go, and the keys rest the wheel.
- **Hands, sorted to their jobs.** `local_hands` is every confident tracked bare palm and every
  sure tracked controller (or `hands`, a Callable, for the suite, the probe and `--theremin`);
  `sort_hands` makes the one nearest over the loop the volume hand and, of the rest, the one
  nearest the rod inside its field the pitch hand. A tracked hand lost for under LOST holds its
  note; a cursor that leaves the field means it. Tilt and shake are read by a `Wobble` whose
  `sending` is off (it only measures), and its semitones are added to the glide before the note
  is chosen, so a tilt past the range hands on as a reach would.
- **The guide.** Rings round the rod at GUIDE_Y at each scale step (each chord tone in CHORD), the
  key's root rings heavier, each lettered on a rule out from the rod (the lowest and each root
  with its octave; alternately over and under it, made smaller where the rings crowd near the
  rod). The ring nearest the hand's own pitch is lit and its letter larger, a ring is drawn at the
  hand's distance, and a bar runs from the lit ring to it: how far off it is, not by colour alone.
  The hover card says it in words (`A4 +30 cents`, the volume, what SCALE snaps to).
- **At a desk.** `Theremin.Field` is a band DESK_BAND over and under the rule (not the whole air
  round the rod, so the booth's mic behind it stays clickable from the seat): the cursor resting in
  it is the pitch hand, across along the lettered rule; the wheel over it is `desk_volume`, from
  silent, shown as a ghost disc over the loop; the button held plays it full; the cursor leaving
  puts the volume down. The mouse's wiggle wobbles and Alt bends it, as everywhere.
  `Theremin.ModeKey`, on the cabinet's front, cycles FREE, SCALE and CHORD (the wheel or a stick
  steps it), starting FREE as the real instrument is; the studio keeps the switch across venues
  (`Studio.theremin_snap`).
  `Studio._follow_theremin` reaches for its source while it sounds, its field is hovered or this
  player stands within ChordHarp.NEAR of it.

A modular synth wall (slice 51). `ModularWall` (`hardware/modular/modular_wall.gd`) is a Surface,
station `modular` (LIVE, mounted in the `synth` zone, `"surface": &"modular"`), hung at
`Venue.modular_spot` over the keyboard stand (ZoneKit.keyboard_stand): its panel's face
MODULAR_BACK in from the zone's middle and its foot MODULAR_BOTTOM up, facing the room, slid along
the stand by OFF_MIDDLE so the panel and the plaque beside it stand over the stand together. The
venue's own rack dressing ("Module..." under `Zone_synth`) gives way to it (`ZoneKit.yield_rack`).
It is in F's round (`parks` false: a place, it stays home while something is brought), and a visit
walks to its station's seat (`Studio._walk_to_station`), since where `seat_for` would stand a desk
the bricks table stands.

- **Eleven modules.** `Modular.MODULES` from the left: KEYS (this player's keys' pitch, gate and
  velocity out, its newest note lettered and a GATE lamp, and PLAY, a `EqWall.WallKey` that takes
  the computer keys on a KeyCatcher of the studio's, `modular_keys`), LFO, NOISE, VCO 1 and 2, MIX
  of four, VCF, ENV 1 and 2, VCA and OUT, whose tag says the road and its figure. Its jacks are
  `ModularJack`s (the jack mesh `PatchCable.JACK_MESH`, an output's on a pale plate, a ring that lights brighter
  and grows where a carried cable could go and more where it will), its knobs the console's
  `Knob`, its cables `PatchCable`s from the room's patch; under it, on the stand's upper deck,
  thirteen `ModularTouch` keys (the wheel moves them an octave). A lamp on a stalk lights it.
- **The patch is the room's.** The row `modular` {cables: [[from, to]], knobs: {id: v}}
  (`Modular.clean`, `default_patch`: KEYS to VCO 1 to the VCF to the VCA to OUT, KEYS' gate to ENV 1
  to the VCA). The room verbs `modular_patch` [from, to, song] (an empty `to` pulls the cable at
  `from`) and `modular_knob` [id, v, song] are answered by `Modular.answer_patch` and `answer_knob`
  (refused: an unknown jack, output to output or input to input, an input with a cable in it
  already, pulling nothing); the studio's `ask_modular_patch`/`ask_modular_knob` do it on the host
  and predict it on a guest, and `apply_room` puts this guest's unanswered asks back on top, as
  the patchbay's `patch`. The wall never changes its own patch: it asks (`patch_asked`,
  `knob_set`) and shows the room's answer (`show_patch`).
- **A knob's turn is streamed, not asked.** As it turns the wall says so every change
  (`knob_turning`), and at most once each STREAM_GAP_MSEC (`knob_streamed`, on an injectable
  `clock`), which is what every voice here hears (slice 52: `Studio._on_knob_streamed`, so this
  player hears of their own turn exactly what the band and a take get) and what goes out as
  `Session.send_knob(id, v, song)`: reliable, on
  its own GESTURE_CHANNEL, passed by the host to everyone else (`_pass_knob` refuses a knob that is
  not one and clamps the value), heard as `Session.knob_turned`, which turns the wall's knob and the
  voice. Only the let-go, once the knob has rested for SETTLE, is a `modular_knob` ask.
- **Within reach.** The wall's jacks, knobs, keys and the mount's handle take the pointer only
  while this player is at it (`within_reach`: standing in front of the stand, MODULAR_NEAR to
  MODULAR_FAR out and MODULAR_SIDE either side where the wall's own seat is the nearest station's,
  `Studio._station_seats`, or with it visited or brought), so a click from the desk never lands on
  a 2 cm jack six metres off, and a player at the harp, the music box or the bells beside the stand
  plays them, not the patch; its plaque's keys always do.
- **Cables.** Each is a PatchCable at CABLE_SAG; one across more than LONG_CABLE hangs to
  CABLE_FLOOR under the lowest row of jacks (`cable_sag`), so a busy patch keeps its jacks' names
  in view.
- **The DSP, twice.** `Modular` (`core/music/modular/modular.gd`) is the arithmetic in GDScript,
  `render(patch, events, from, frames)` at 48 kHz in blocks of 64, pure and deterministic (an event
  at the start of the block it falls in), and runnable a block at a time (`run`, `apply`). Every
  input reads its source a sample late, only modules whose sound reaches OUT run, and last-note
  priority keys feed KEYS. `native/modular.c`, included by `native/keys.c`, is the same in C in
  double precision: the helper takes `mod on N`, `mod clear`, `mod cable X Y`, `mod cut X` and
  `mod knob ID V` lines (`NativeKeys.modular_lines`, a knob with 17 digits), plays this player's
  keys through it while `mod on 1` (the tine silent), and `wait N` in `--render` renders N frames
  before the lines after it. The suite holds the two within 1e-4.
- **The road.** `ModularVoice` (`core/music/modular/modular_voice.gd`) plays this player's keys
  through the room's patch while `engaged` (`Studio._follow_modular`: at the wall, or PLAY on): on
  the helper where the keys' MonitorSynth has one (`modular_patch` and `modular_on`), else on
  MONITOR through Godot, a Modular of its own on a thread, the MonitorSynth handing it its notes
  (`MonitorSynth.modular`) instead of playing its tine. `tag()` is OUT's: `HELPER · 5.3 ms`,
  `THROUGH GODOT · 42 ms`, or how to play it; while a take goes through the wall, OUT says REC on a
  line of its own at a module title's size under it (`ModularWall.set_recording`).

The modular, recorded and heard by the band (slice 52):

- **What a player sends at the wall is the modular's.** While `Modular.SOURCE` is in GuestMidi's
  reach (`through_modular`), every note and control their keys send goes out with that source,
  decided at the note-on and kept for its note-off (`GuestMidi._sent_as`), since everything the
  keys sound then plays the patch.
- **Bandmates hear it at the wall.** Presence routes the modular's notes and controls by source
  alone (`modular_heard`, `modular_control_heard`) to the studio, which keeps a `ModularVoice` for
  each bandmate playing it (`Studio.modular_heard`): with a `speaker` (the wall) it plays the notes
  it is handed through the room's patch on a Modular of its own through Godot, out of an emitter at
  the wall (Foley's, on GEAR). The room's patch, the knob streams and the cables change every voice
  here (`_modular_voices`), and a bandmate's last note-off rests their wheel. Quiet for
  `rest_after` (5 s) with no note held, a bandmate's voice rests (`engaged` off: no thread, no
  emitter) and their next note wakes it on the patch as it stands. Gone, their voice goes.
- **A take is what was played, not sound.** `ModularTake` (`core/music/modular/modular_take.gd`)
  is the patch as a take began and every event after it with its song: notes, the wheel (rested at
  the last note-off on every end), knobs as streamed and cables as the room took them.
  `render()` is Modular.render of it from its start for its span; `write` puts its 16-bit WAV in
  AudioTake.DIR. `Session.modular_takes` (`ModularTakes`, `core/session/modular_takes.gd`) holds
  them. GuestMidi begins this player's own (`mine`) when a take begins with the modular in reach
  or its first note goes through it (`_take_modular`), feeds it the notes and bends it sends, and at
  the end calls `finish` with the take's tracks. The notes sent as the modular's are not in the
  MidiTake; whatever else the take holds (the harp before the player walked up to the wall, the keys
  after they left it while the take rolled on) is, and goes in by `DAW.insert_midi_take` beside the
  audio. `Session.send_knob`, `_pass_knob` and `_knob` feed it knobs; the studio's
  `_show_modular(patch, song)` feeds it each cable pulled or put in and each knob let go that no
  hand here is turning, at the song the room's verb was asked at (`_take_modular_change`).
- **The host renders it from what reached it.** A guest marks its take begun and ended twice
  (`Session.send_modular_take`): `_modular_take_keys` on KEYS_CHANNEL behind its notes and
  `_modular_take_gestures` on GESTURE_CHANNEL behind its knobs, all reliable. The host takes that
  guest's modular notes (`heard_note`, from `_note_up`) and wheel (`heard_bend`, from
  `_modular_bend_up`: each move the take keeps, sent again reliable on KEYS_CHANNEL by
  `Session.send_modular_bend`, since the live wheel rides CONTROLS_CHANNEL unreliable and a lost
  move would make the host's render differ) from the keys' begin to the keys' end, with what they hold at the begin at the
  take's start, and the room's knobs and cables from the gestures' begin, when it takes the patch
  as it hears it (`ModularTakes.patch`, the studio's `heard_modular_patch`), until it is placed.
  With both ends in and SETTLE (0.25 s) more, or ENDS_WAIT after one, it renders the take and
  writes its WAV (the encode and the overview too) on a worker thread, and on the main thread
  inserts it on the take's tracks at its start as an audio take named `modular`, on the player's
  behalf (`placed`). A take past AudioTake.MAX_SECONDS is cut there and its player told. A host's own take is `mine`, placed the same
  way. Everything is stamped, so a sweep heard late lands where it was turned, and the host's render
  is the player's own (the probe checks the digests).

The world plugs into the modular (slice 53):

- **A world socket is an output of the patch.** `Modular.WORLD` names twelve (`world:weather`,
  `world:drips`, `world:venue`, `world:ring_1`..`world:ring_8`, `world:marbles`; `is_output`,
  `is_world`, `world_title`), so a cable from one is a `[from, to]` in the room's `modular` row,
  asked with `modular_patch` and answered, mirrored and predicted as any other. Each carries a level
  (`Modular.world`, Event.WORLD) and a gate (`trig`, Event.TRIG: open WORLD_GATE_BLOCKS, 48 ms,
  shut a block first if already open). The ENVs' gates (`GATE_INS`) read the gate and every other
  input the level. The output slots run the modules' outs, `_ZERO`, the twelve levels, the twelve
  gates (`_slot`, `_reads`); native/modular.c is the same (`mod_world`, `mod_trig`, `mod_slot`), and
  the keys helper reads `mod world NAME V` and `mod trig NAME` (`NativeKeys.modular_world_line`).
- **What plays into them is worked out, not sent.** `ModularWorld`
  (`core/music/modular/modular_world.gd`, `Studio.modular_world`) is pure: `events(from, to)` is
  [song, WORLD or TRIG, socket, value] in order from the song clock and the rows (the weather's
  `Weather.level` each sixteenth and a gate each `Weather.drops`; the cave's drips, the venue
  instrument's strikes at their item_hit `song` and the marbles' bells as pulses; each looper layer's
  own notes' velocities as its ring's level, `ring_level`), the same on every machine and nothing of
  it on the wire. `levels_at` is where the levels stand at a moment. `follow` hands each frame's span
  on (`fired`) to every ModularVoice here (`Studio._on_world_fired`): this player's, each bandmate's,
  and the studio's world-only voice at the wall (`modular_world_voice`), engaged while a world cable
  is in the patch and the wall is in view. A take hears it once, when finished or placed
  (`ModularTakes.world` = `for_take`, `ModularTake.hear_world`), so the host's render has it too.
- **The sockets stand where the sound comes from.** `WorldSocket`
  (`core/music/modular/world_socket.gd`, a ControlAffordance, group `modular_world_sockets`): beside
  the weather's track jack (the drips' at the cave's pool), the venue instrument's, on the marble
  run's tray, and one per looper ring on a rod beside the rings (`LooperRings._show_sockets`). A
  click, dwell or press steps its cable through the wall's free inputs (`Modular.step_input`,
  `free_inputs`, WORLD_INPUTS, around to unpatched), P and Shift+P over it at a desk likewise
  (MouseInteractor), each step asked of the host (`Studio._on_world_step`). Its long cable is a
  CableSweep along the floor (`WorldSocket.route`, `CableSweep.rest_on`), and its track jack row is
  untouched, so one socket can record onto a track and drive the filter at once.

A sample as a cloud of grains (slice 54). `GrainCloud` (`core/music/grain_cloud.gd`) is a plaster
plinth with a turned brass bowl on its cap and two brass posts up to a rail under the cloud's front
edge (tools/blender/grain_cloud.py), and over it a cloud a metre across, half a metre tall and 40 cm
deep. Station `grains` (LIVE, free-standing, a `Venue.WHEELED` trolley at `Venue.grains_spot`: by
default in the aisle between the drum riser and the lattice, behind the string spool, its back
GRAINS_GAP off the lattice and facing across the aisle, `Venue.default_grains_spot`; in the loft,
whose aisle is the harp's, on the open floor beside the desk, `LoftVenue.default_grains_spot`). Its
plaque hangs on the plinth's side toward the desk, since the cloud stands side on to it; its row has
`air` round `air_at`, the cloud's middle, which the clearance test samples as the theremin's.

- **The bowl is a holder.** `bowl`, one slot (`ItemRoom.HOLDS` takes cassettes), laid by
  `Studio._hold_the_bowl` wherever the trolley stands. The cassette in it is the cloud's sound, made
  on a worker as the platter makes its own: a file's (a sample's or an audio clip's, fetched by a
  guest with FileSend, the tag FETCHING meanwhile), a MIDI clip's render or a demo part's window
  (`CassetteItem.sound_work`), mono at `GrainVoice.RATE` (24 kHz, `mono_of`), at most SOURCE_MOST
  (30 s). Its length lies left to right as COLUMNS of motes (a MultiMesh), each as bright as its
  stretch is loud (`envelope_of`); an empty bowl's motes are faint and grey and its tag says PUT A
  SAMPLE IN THE BOWL.
- **The hand's place is the law.** `at_for` across (where in the sound), `length_for` up (SHORTEST
  20 ms to LONGEST 200 ms), `density_for` in, away from the player (SPARSEST 4 to DENSEST 60 a
  second, each step the same proportion), `place_for` the inverse. The spray is a bare hand's
  thumb-to-little-finger span (`spread_of_span`), a controller's grip travel, or the desk's wheel,
  up to SPREAD_MOST (30%) of the sound either way. `local_hands` is every confident tracked palm and
  sure controller (or `hands`, a Callable, for the suite and `--grains`); the nearest the middle of
  those in the cloud plays it.
- **Events, never the hand.** Thirty times a second (`GrainVoice.EVENT_HZ`) the hand is read into an
  event (`GrainVoice.event`: tick, at, length, density, spread, pitch; `is_event` checks one), kept
  in `events`, and the voice plays that. `GrainVoice.Renderer` makes a window's grains from its event
  alone: their onsets and places drawn from a generator seeded by the event's tick, each read at its
  pitch under a Hann window, as loud as LEVEL over the root of the overlap, at most MOST (32)
  sounding, carried window to window. `GrainVoice.render(sound, events)` is the same Renderer over a
  list, so what the voice played (`kept`, while `keeping`) equals the render of its events sample for
  sample: what slice 55 sends to bandmates and records.
- **Heard by its player.** On MONITOR through an AudioStreamGenerator (PREROLL queued ahead of the
  first window), at `latency_seconds`, said on the tag (`GRAINS · MONITOR 82 ms`): a texture one
  player makes, as decided. KEY, the room's row `grains_key` (verb `grains_key` [bool],
  `Studio._on_grains_key_pressed`, predicted), pitches every grain by the chord's root from the key's
  tonic, a fourth down to a tritone up (`pitch_for`, read from `ChordHand.at`).
- **At a desk.** `GrainCloud.Face`, the cloud's front, takes only a mouse's button: held, it plays
  from where it is held (dragged, from where it is dragged); the wheel over it is `desk_spread`, and
  Shift with it `desk_density`, since the face has no depth. The bowl (`GrainCloud.Bowl`) takes a
  click with a cassette in the hand. The help card's PLAY page and the hover cards say all of it.
  Motes and sparks move by `Ergonomics.motion_scale`; the tag says in words what is playing.

The grain cloud recorded and heard (slice 55). Every event the cloud plays is `GrainCloud.played`,
and the studio sends it (`Session.send_grains(e, GrainTakes.song())`): fourteen bytes
(`GrainVoice.pack`, `unpack`; `GrainVoice.event` puts each number on the wire's grid as it makes one,
so the event played and the one unpacked are the same numbers), reliable and ordered on
`Session.GESTURE_CHANNEL` beside the modular's knobs, through the host, which refuses bytes that are
not an event (`grains_refused`) and passes the rest on (`Session.grains_played`). Its song stamp is
what the player hears (GuestMidi.heard) moved on by `GrainVoice.latency_seconds`, -1 while the song
is not playing.
- **Heard by the band.** `Presence.grains_heard` gives a bandmate's events to the studio's cloud
  (`GrainCloud.hear`), which plays them on a `GrainVoice` of theirs (`GrainCloud.theirs`,
  `voice_of`) from its own sound, out of the air at the cloud on the gear bus (`GrainVoice.speaker`,
  a `Foley.emitter`). It begins THEIRS_WAIT (3) windows after their first event, then each window
  plays its own tick's event or a rest, so uneven arrival is ridden over and what is heard of them is
  `GrainVoice.render` of their events; one later than its window is dropped, and more than
  THEIRS_MOST waiting skips ahead. Their grains light the sparks where they play from
  (`GrainCloud.place_for`), the tag says who plays it, and nothing plays while this cloud's sound is
  still FETCHING or RENDERING: a guest's fetch of the bowl's file is asked once (FileSend.fetch,
  through `Studio._platter_file`).
- **Recorded as audio.** `Session.grain_takes` (`GrainTakes`, `core/session/grain_takes.gd`) gets
  every event this player's cloud sends (`played`). While the song records as they hear it
  (`GrainTakes.rolling`: past any count-in, inside any punch range) the first event begins a
  `GrainTake` (`core/audio/grain_take.gd`: the events and each one's song) onto the keys' chosen
  track or the armed one (`GrainTakes.track`; with neither, the player is told once); recording
  heard to stop ends it (`finish` drops anything stamped past the end), kept as `last_mine`. A guest
  marks the take to the host, begun and ended (`Session.send_grain_take`), on the same channel as
  its events, so the host takes exactly the events between the marks (`heard_event`, `heard_mark`).
  Ended, the host renders the take from its own copy of the cloud's sound (`GrainTakes.sound`, the
  studio's `grains_sound`) and writes it as a WAV at AudioTake.RATE (`GrainTake.at_take_rate`: every
  other sample the render's own, the one between halfway) on a worker thread, then puts it in as an
  audio take named `grains` at its first event's song (`GrainTake.lands`), on the player's behalf.
  The render keeps the events' spacing (a window a tick; the cloud counts the ticks of windows a
  long frame missed), so a hand let go mid-take is a gap in it, and since the live voice plays from
  the same events, the take is what the player heard, sample for sample.

Lyrics in the booth (slice 56). The song's words are one LRC text, `MixState.lyrics`, replicated as
`/timeline/lyrics` (durable, in the snapshot; `lyrics_changed`). `Lyrics` (`core/music/lyrics.gd`)
is the only thing that reads it: `parse` and `write` (tags on lines of their own, a line per stamp,
one break between verses), `at(seconds)` for the line sung, `sequence` for the order sung (timed by
time, then untimed as written), `tap(seconds)` stamping the next untimed line, `clean` for what the
song may keep, and `from_notes`/`into_notes` for Reaper's project notes. The board asks it every
frame and a song may be a thousand lines, so `sequence`, each line's `place` in it and the counts are
worked out once per parse (`_index`), again only after `tap`, `add` or `untime` (`changed`), and
`at` halves its way through the timed lines rather than looking at them all.
- **Written as one edit.** `DAW.set_lyrics(text)` (a COMMAND, so a guest's is a `set_lyrics` intent
  the host checks and makes; refused without Capability LYRICS, `lyrics_refusal`). Offline it is one
  undo step (`lyrics`). Reaper has LYRICS only with the bridge: `SetLyrics` rewrites the `[lyrics]`
  block of the project notes in one Reaper undo block (the Lua `lyrics_into_notes` is
  `Lyrics.into_notes` line for line), and GetTimeline's `notes` bring it back on the poll. The
  built-in engine's .dawproject keeps it as metadata.xml's Comment (`ProjectFiles._keep_lyrics` and
  `lyrics_of`; `ProjectBridge.load` takes it).
- **The board.** `LyricBoard` (`core/music/lyric_board.gd`, station `lyrics`, LIVE, zone-mounted at
  `Venue.lyrics_spot`, beyond the mic stand in the vocal booth, facing the singer at the mic, built to
  Ergonomics.eye_height) shows the last, the sung and the next line in a scroller. The sung one is
  large with ▶ before it and a bar filling toward the next timed line, and the line TAP times next
  reads `TAP ›`. A line on, the scroller glides up for GLIDE times motion_scale, and at motion 0 it
  steps. Every line and key sits above the mic's body as the singer sees it, and the plaque hangs
  beside the face (the suite checks this in every booth). `display(heard)` is what it shows, from
  `heard_source` (GuestMidi.heard unless given). Writes go through `write` (DAW.set_lyrics unless
  given) and are believed for PREDICT_MSEC until the host's arrive.
- **TAP and EDIT.** `BoardKey` TAP (a press) and EDIT (dwell-able). A click on the `Face` arms it at
  a desk, so Enter TAPs and Esc lets go (consumed, so that is all Esc does: the studio's walk back to
  the desk never hears it), and its top row says so in words; the row is written again only when the
  text or the arming changes. `arm` is a desk's: in a headset a poke on the face does nothing. EDIT is
  `Studio.edit_lyrics`: in a headset the TypingPad at PAD_AT by the right hand adds a line, and at a
  desk `lyrics_edit_asked` opens the session panel's LYRICS box (`SessionPanel.edit_lyrics`: the
  whole LRC in a text box, Set lyrics, Untime).

The toast on arriving at a station names its area in words (`Stations.where`, `AREA_WHERE`: "in
the control room", "in this venue"), not the card page's title.

Pitched items are instruments of the same kind whose note is a function of song position
(`InstrumentItem.note_at`, `channel`, `note_seconds`). The four handbells (`HandbellItem`,
`bell1`..`bell4`, on a stand beside the chord harp at `Venue.bell_spot`) ring their number's
chord tone, voiced at 72, on `InstrumentItem.MELODIC_CHANNEL` (10, 0-based), 0.8 s long. Each hit
reads `InstrumentItem.clock` (the studio's `HitRecorder.stamp`) once: that one position pitches
the sound, which is started before `play` returns, is what HitRecorder records it at (`hit`'s
`at`, no second stamp), and goes out with it (`Session.item_hit`'s `song`). Whoever hears it
pitches it by that `song` (`heard`), not by their own position when it arrives, so a ring just
before a bar line is the old chord's tone everywhere. A click on a bell is sent as a hit as well
as a use, and a bandmate's use of a pitched item rings nothing, so it rings once. Tour's keys
parts ignore both item channels (`TourPart.ITEM_CHANNELS`). The bells sound through Godot's
mixer like the percussion; the session panel shows that path's latency beside the keys', and over
25 ms they are to get a `MonitorSynth` voice. docs/spatial_loop.md slice 4 has the decisions.

Every instrument has an output jack (`JackSocket`, `core/music/jack_socket.gd`, a
`ControlAffordance` at `InstrumentItem.jack_point()`). Where each goes is a row in the room, not
a send and not a PipeWire link: `room_state()["jacks"]`, {source: sink}, kept by the studio's
`Jacks` (`core/music/jacks.gd`) and asked with the `plug` room verb, predicted and rolled back
like the tablet's `patch`. `Jack` (`core/music/jack.gd`) names the ends: sources are item ids,
`harp`, `keys:P` (player P's own keys) and `chord:P` (P's chord hand, part two slice 33), sinks
`track_N` and `player_P`; an empty sink is unplugged. Every hit played here goes through `Jacks.hit` (from `ItemRoom.played`): unplugged it
is the old path, onto the armed track; into `track_N`, `HitRecorder` keeps a take of its own for
N and records it there, armed or not, and not on the armed track as well. A press steps a socket
through unplugged and every track that takes MIDI (`Jacks.sinks`: all but a frozen one), round
again; the wheel and thumbstick step either way. The hand that carries the instrument never
reaches its own socket: `Interactor._cast` leaves `own_jack()` out of its ray, so that hand's
trigger or click still strikes the instrument, and the other hand (or P and Shift+P,
`MouseInteractor.step_own_jack`, on a desktop) steps it. The host takes a plug from the hand that
holds the source, or from anyone while it is at home, and never into a track that is not there
(`Jacks.refusal`); a copy that leaves the room (`ItemRoom.despawn`) takes its plug with it. A
plugged instrument shows a tag in words (`-> 3 SNARE`) and a short lead ending in a plug, never a
cable to the patchbay, which shows sends. docs/spatial_loop.md slice 5.

A jack into a bandmate (`player_P`) is a cable between players. What the source plays goes to P's
own keys instead of where it went: a bell its note and, `note_seconds` later, its off; the harp
its strings (heard here from the harp itself); percussion a TRIGGER; and `keys:P` what P plays,
as a thru (P's keys go on as before, and what came in on a cable or from the harp is not passed
on, so two players plugged into each other never feed back), with its controls beside the notes
as `Jack.Kind.CC` (`pitch` the controller, `velocity` its value; a resend of the value the cable
already has is not sent again, but one right behind a note-on is). Each event carries the one song
position it was played to. `Session.send_jack` takes it up to the host on `KEYS_CHANNEL`,
reliable, and the host passes it to P alone (`jack_played`) only when both are in the room, P is
not the sender, the room's patch sends that source into P and the sender is the source's player:
the holder of an item (Session.holds), P for `keys:P`, anyone for the harp (`Session.jack_refusal`,
`Session.jack_check`, the studio's `Jacks.send_refusal`). It clamps by kind: a note's or a
trigger's pitch and velocity to 0-127, a CC's value by its controller (`control_value`, so a bend
of -8192 arrives intact), and refuses a CC that is not one of `CONTROL_KINDS`. `chord:P` sends
only `Jack.Kind.CHORD` and nothing else does: `pitch` the chord's root as a pitch class (clamped to
0-11), `velocity` one more than its quality's place in `Harmony.QUALITIES` (0 for no shape; past
their count refused), spelled back on the receiver in its own key (`Jack.chord_named`); only P
plugs and sends it, never onto a track. On P, `Jacks.received` plays it on P's
keys with source `&"cable"` at that song position, so it sounds on P's synth, goes to everyone as
P's notes and lands in P's take where it was played; a TRIGGER is the chord tone at its song, one
up the chord each hit, for 0.3 s; a CC moves P's wheel as the cable (`GuestMidi.control`), taken
while the cable owns it, and so lands in P's take beside the notes. `&"cable"` is in P's `GuestMidi.instruments` while anything
goes into P. Whoever a jack goes into may unplug it (a press on it, or Shift+P with an empty hand
on a desktop), and is told who plugged what. The harp's socket is on its pillar; a player's keys'
is on their left wrist (`HandSkeleton.wrist`), on the left controller while that hand holds one,
and P with an empty hand on a desktop; the chord hand's (MY CHORDS) is on the chord hand's wrist
and controller beside it (`Studio._wear_chord_jacks`), and P in the chord layer on a desktop
(`ChordHand._chord_key`). Into a bandmate the socket draws a slack cable to the
nearer glove of their ghost (`Presence.cable_end`), rebuilt at most 15 times a second while an
end moves. docs/spatial_loop.md slice 6.

The keytar (`KeytarItem`) has no sound of its own here. In this player's hands it sets
`GuestMidi.keytar`, a view of `&"keytar"` in `GuestMidi.instruments`: the set of instruments in
this player's reach that play their keys (the keytar, the harp, the fingertips, a cable, the
wheel; docs/spatial_loop.md). Each puts in and takes out only its own name (`GuestMidi.reach`).
While the set is not empty their keys play on the keys' low-latency synth, go to everyone as
notes, and are recorded as a take whatever this machine's role (`GuestMidi.plays`). Off a guest
the synth is started when the first instrument comes into reach, before its first note, and
stopped when the last goes. A take with no track chosen goes onto the armed one, runs across the
gaps between notes, and is named after what played in it (`GuestMidi.take_name`:
`Ada harp+fingertips 1`; plain keys alone are `Ada take 1`). A note given its own song position
(`note_on`'s `at`, for one played elsewhere) is recorded and sent at it. On a desktop the studio's own `KeyCatcher` (`keytar_keys`) is its
piano while it is held. `Walker` reads the arrow keys while a control in the `walks_on_arrows`
group has the keyboard. `GuestMidi.key` shows each note on its key. Someone else's notes, while
they hold the keytar (`Presence._on_note_played`), play out of it on a `MonitorSynth` with a
`speaker`: an AudioStreamPlayer3D on the room's bus.

The chord harp (`ChordHarp`, `core/music/chord_harp.gd`) is not an item but a control, stood by
the studio in each venue at `Venue.harp_spot` (behind the bricks table, against the live room's
back wall). Its eight strings are `Harmony.tones(55, 8)` at the song position each strum is played
to, so it is always in the song's chord. A grab plucks the nearest string and a held move plucks
every string it crosses; a bare hand strums by touch through `tips` (the tracked fingertips), and
a fingertip's poke is not also a grab. Its notes are this player's keys with source `&"harp"`
(heard at once, sent to everyone, a take on the armed track), and the studio keeps `&"harp"` in
`GuestMidi.instruments` while the player is near it, a hand is on it, or a string rings, so a run
of strums is one take. `Presence` routes everyone else's harp notes by their source to
`ChordHarp.heard`, a `MonitorSynth` speaking from the harp, keyed by (peer, pitch) rather than by
who holds the harp, and lets go of a leaver's. The octave (two crown buttons, the wheel, the
thumbstick) is each player's own. docs/spatial_loop.md has the decisions.

Everything that stands somewhere to be played is a station, and the stations are one list:
`Stations` (`core/music/stations.gd`, static). A row is `id`, `title`, `area` (control, live or
venue), `zone` (the Venue.ZONES zone it is mounted in, or empty), `air`, `spot` (the Venue method
that places it, null where the venue has no room for it), `at` (what is looked at) and two help
lines, `desk` and `hands`; a free-standing row also gives its footprint, so `Stations.solid` is
the venue's own solid for it. `Stations.HELD` is the same help for what is carried. Made from the
list: the studio's stands (`_stand_the_harp`, `_stand_the_wheel` read their spots through it), the
help card's PLAY pages (`WelcomeCard.pages`, one an area, running on to numbered pages that each
fit 1600x900 less margins), the desktop's go-to (`Studio.cycle_stations` on I and Shift-I, and
`go_to_station`, which eases the walker to `Stations.seat` facing the station, looking where
`Stations.look_from` holds its `frame` (its controls' top first) in view from that seat, and moves
the body so Esc walks home), each station's plaque (`Stations.plaque`: title and hands line at 30 mm), and
the suite's clearance loop, in two kinds: free-standing rows take the harp's checks, zone-mounted
ones are checked inside their zone. The help card holds the keyboard focus while open, so the
walker stands still; F2 still opens the 2D view, which puts the card away. docs/spatial_loop.md part two, slice 10.

A headset goes to a station by travelling, since a play space is two metres square and the live
room's stations are several metres behind the desk. `XRRig.travel(to)` puts the play space's centre
(the XROrigin3D) on `to`'s floor point facing its way, at that point's height, so where the player
stands in their own play space is kept and their real floor is what they see under them (a seat is on
whatever is stood on there, `Venue.floor_at`, so at the hand drums the riser's top; the desktop's
walker is put down on it the same way, `Walker.travel_to` standing on `ground_at`), and `travel_home()` puts it back at `home`, the mix position (`XRRig.settle`: the
studio centres a VR play space at (0, 0, MIX_POSITION_Z), in front of the desk with the station
board in view; passthrough keeps its real floor). It is a cut behind a veil, a black sphere round the head drawn through
everything and never in a mirror, closing over `XRRig.FADE` (0.15 s) and opening again; a plain
cut at motion 0. Calibration does not travel: RoomAnchor keeps the session's frame, and a floor
mark taken while away is converted to the play space at home (`untravelled`). `travelled` fires at
the cut, and the body frame takes the new yaw whole (`BodyFrame.recentre`). `Studio.go_to_station`
in a headset is `_travel_to_station`: the desktop's seat (`Stations.seat` with a walker's `fits`,
one kept out of the tree when there is no walker), focused gear let go. `StationBoard`
(`hardware/station_board.gd`) stands on a post by the desk's left end: the PLAY pages' stations a
row each (`rows_for`, Stations.by_area in the card's order), a press going there (a walk on a
desktop, a travel in a headset). Every plaque has two keys (`StationBoard.PlaqueKey`):
INSTRUMENTS puts a `compact` board's rows up beside the plaque until a row or INSTRUMENTS again,
and BACK goes home (`Studio.go_home`: `travel_home`, or Esc's walk). A key finds the studio by
walking up to an ancestor with `plaque_key`. In a co-located room (`Studio.co_located`: the frame
taken from floor marks, `RoomAnchor.marked`, with another headset in the session) travel is
refused (`travel_refusal`), every board lettering CAN'T GO and the reason, the rows beside a
plaque left up so the refusal is read where it was pressed. Presence publishes the
travelled head as it is (`Presence.head_in_session`), so bandmates see the ghost at the station.
docs/spatial_loop.md part two, slice 11.

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

### The session in miniature

`MiniatureItem` (kind `miniature`, docs/spatial_loop.md part two, slice 34) is the whole song on a
40 cm tray to hold, a room item like the duck whose home is the desk's left wing
(`Venue.miniature_spot`, read from `Studio.desk_wing`, which `_place_desk_wing` keeps beside the
console's left end as the desk grows, in the floor plan by `_wing_footprint`). It draws the song from
`DAW.state` in a frame of its own (`_content`, reader at +Z, time along +X): a strip a track with
its name and a block an item, the regions as bands and the markers as flags (a `NOTE ` marker a
pinned card) along the far edge, the loop as a bracket, and the playhead, stepped a beat at motion
0. It redraws on the DAW's timeline, bank, track and project signals, and on a cheap shape key
every half second. It is all unshaded and its own materials, since `Item.set_rim` rings every
material under a body. The tray is taken by its front edge only (the item's grip, a box in front
of the pins): its bed is a `Face` control, a thin box at block height so a glancing ray lands where
the eye meant, and each station standing here is a `Pin` round the lip on its station's side of
the mix position (`pin_spots`, spread PIN_GAP apart). Both are turned +Z up (`FACE_UP`), since a
fingertip (PokeInteractor) lets go as it lifts along a control's +Z. Carried in a hand, the tray
lies wholly inside that hand's own ray (`held_pose`), so the hand that carries it never points at
or presses its own bed; the other hand does. The tray maps points and says what was
pressed (`spot_at`, `card`, `pressed`, `station_pressed`); the studio acts on it
(`_on_miniature_pressed`): `DAW.seek`, then for an item `DAW.select_item` and the timeline's
window moved to it (`set_view`) and brought, else `ConsoleSurface.bank_to_track` and the console
brought. Bringing is `FocusRig.focus` (a visit at a desk, a summons in a headset), except that a
surface the mount shows on the screen is already in view, so a desk lets its gear go instead
(`Studio._bring`). A pin is `go_to_station`. Seeks and selections are DAW verbs, so a guest's are
intents; nothing here is new on the wire.

## The stage table: the mix as places

The stage table (`StageTable`, `hardware/stage/stage_table.gd`) is a `Surface` on a trolley
beside the mix position (`Studio.STAGE_AT`, a station: `Stations`' `stage_table` row). It is
furniture of the control room, not of the venue, so `Venue.stage_table_spot` reads it from the
studio. Each track of a page of the bank (or the soloed or selected tracks, by SHOW) stands on it
as a `StageVoice`, a `ControlAffordance`. Where it stands is the mix: across is pan, back from the
front edge is level (+6 dB to -40 dB, linear in decibels, -inf on the lip behind), and the ring
round its foot (`StageVoice.Ring`) is its width. Nothing is stored on the table. A voice reads
its place from `DAW.state`, and a placing writes `DAW.set_track_pan`, `set_track_volume` and
`set_track_width`, so the console's knob and fader follow and a guest's placing is an intent.
A voice `edits_as_one`, so a placing is one undo step: pan, level and any width the wheel set
while it was held. A press with no drag (`DRAG_START`) moves nothing, and two in
`DOUBLE_PRESS` reset the track as an edit of its own, as do Backspace and the tag's RESET key.

The width is a capability (`DAWBackend.Capability.WIDTH`). Where it is missing (Reaper without
the bridge, since OSC has no width) a voice has no ring and its card says so. On Reaper the
bridge's `SetTrackWidth` sets `D_WIDTH`, first putting a track in stereo pan (`I_PANMODE` 5) if
its pan mode ignores width, in the same Undo block. `GetState` reads the width back only in the
stereo and dual pan modes. `ReaperBackend.pan_mode_set` says so once, and `stereo_panned` keeps
it for the voice's card. The built-in engine holds the width in each bus's tail (above), and
`.dawproject` keeps it in the zip's extras (`ProjectFiles`, `widths` by track id).

Depth is a handle of its own, never a side effect of level. Each voice stands on a stalk
(`StageVoice.Stalk`), and how far it is lifted off the table is its send to the room
(`StageTable.room_track()`: the first track with a reverb that another track sends to, or a track
called ROOM with one, which the rail's ROOM key makes). The send is an ordinary
`DAW.create_send` and `set_send_volume`, made inside the stalk's edit, so the first lift is one
undo step with its level. A mist round the ball shows it.

### A sidechain as a rope

A rope (`StageTable.Rope`, docs/spatial_loop.md slice 20) is a key send between two voices on the
table, whoever made it: `Sidechain.pairs()` reads them from `DAW.state`, so one the patchbay made
is a rope too, and the patchbay shows a rope's key send. Tying one (a drag from the knot under a
ball, `StageVoice.Knot`, to another voice) is one edit of existing verbs: `add_fx` of the DAW's
first compressor when the other track has none, then `create_sidechain`. Whether the rope added
the compressor is the room row `ropes` (`{"2>6": added}`, project track numbers, asked with
`Session.ask_room(&"rope", ...)` and predicted by the table), so a cut (`remove_fx` if added, then
`remove_send`, one edit) takes away only what the rope made. Pulling the rope's middle is
`set_send_volume` on the key send and `set_fx_param` on the compressor's threshold, inside the
rope's own edit. `Sidechain` (`core/music/sidechain.gd`, static) is the arithmetic: neither
engine reports gain reduction, so how hard a rope ducks, and how far it lifts each hit, is
`Sidechain.reduction` of the key track's meter plus the key send's level over the threshold at
the compressor's ratio, the same on both engines. On Reaper the bridge's `CreateSidechain` sets
every ReaComp on the destination to its auxiliary input, by the detector parameter's own words,
and adds one when there is none; `RemoveTrackSend` sets them back to their main input once
nothing keys the track.

### Leaning in and clapping to mute

Leaning in is personal and changes no DAW state (`Ears.lean`). It needs this machine to play the
tracks one by one, so only a host on the built-in engine can: `GodotBackend.set_lean` adds that
track's cue beside the personal mix's, kept at its fader plus `LEAN_DB`, and Ears lowers the Mix
bus under it. A guest hears only the host's stereo stream and a host on Reaper hears Reaper, so
both get a card saying so. Clapping (`Clap`, core/input/clap.gd) is the other way round: it is an
ordinary `DAW.set_track_mute`, so a guest's is an intent and every mute shows on the voice and
the strip. Its input is two hands' readings (`XRInteractor.clap_palm`: a bare palm and its normal
by `HandPose.palms_meet`, or a controller's grip point), or K at a desk. What it aims at is read
once, as the hands meet, by `Studio.track_under`, which turns any control on the stage table, the
console, the rack or the timeline's lanes into its track.

## Signal you can see, and a room that hears the mix

`SignalBeads` (`hardware/signal_beads.gd`, docs/spatial_loop.md part two slice 21) is one
`MeshBank` of beads, sized once at `CAPACITY` (640) and drawn `show_first(n)` deep: one draw call
for every bead in the room. It owns no cables. Each frame it reads the `SignalBeads.CARRIERS`
group, where every cable puts itself, and asks each one four things: `signal_spine()` (its centre
line, world space, cached against its transform), `signal_length()`, `signal_level()` (0..1 on
the fader law, so 0.716 is 0 dBFS) and `signal_radius()`. The carriers are PatchCable (its
`source_track`'s level through its send's fader, `SignalBeads.send_level`), GearLoom (its
`level_source`, which the studio sets per machine with `Studio.loom_level`: the console's
loudest heard track, the rack's loudest heard track with a plugin, the deck's master),
JackSocket (its lead, or its cable into a bandmate, at `Jacks.level_of` its source's last hit,
fading over `Jacks.HEARD_FADE`) and StageTable.Rope (`level_between` its key and its voice).
`SignalBeads.Run` is a carrier for anything else. "Heard" is not muted and not left out by a
solo, so a muted track's meter never reaches its loom.

A carrier's level follows its source fast up and slow down. Spacing goes in five steps, from
`SPACING_QUIET` (15 cm) to `SPACING_LOUD` (4.5 cm), so a meter's flicker never shakes a bead far
down a long cable. Speed goes from 7 to 42 cm/s, times `Ergonomics.motion_scale`. Size and
brightness go with the level, and the hue never changes. At motion 0 the beads stand at
`SPACING_STILL`, all the same size, and only their brightness moves. Over capacity `allot`
shares the bank so every lit carrier keeps at least one bead.

The room hears a clip in `Studio.follow_clip`, every frame. A heard track or the master over
0 dBFS (`MasterSection.clipping`) lights its OVER: the master's lamp and readout
(`MasterSection.show_over`), and a strip's readout (`ChannelStrip.show_over`, the word OVER in the
over colour). Each is held `OVER_HOLD` (1 s). It also calls `Venue.hear_clip`, which lifts the
practicals by `LIFT` (30%), falling over `LIFT_SECONDS` (0.15 s), at most once every
`FLASH_GAP` (2 s), and only while `reactive` and `lift_on_clip` both hold. `Studio.lift_lamps`
writes the lamps only when the lift changes, and never while a chaos event's tween has them.

COMFORT is the session panel's box for three of the body's settings: `motion_scale` (Full 1,
Gentle 0.4, Still 0), `room_reacts` (Venue.reactive, which the studio no longer derives from
motion) and `lift_on_clip`. Each choice is saved by itself (`Ergonomics.save_comfort`) in the
`comfort` section of `Ergonomics.HEIGHT_PATH`, beside the height. Bootstrap reads it with
`Ergonomics.take_comfort`, and `--no-motion` overrides it with Still and a room that does not
react.

## Seeing the signal: the graph, its meters, and the glasses

`SignalGraph` (`core/audio/signal_graph.gd`, docs/spatial_loop.md part three) is a model, rebuilt
from MixState whenever it is wanted (`build(state, sources)`, about 15 times a second while the
view is on): a stage for each place a sound passes (a source, a track's playback and input, each
plugin, its fader, each send, the master, OUT), ids like `t6:fx0`, `t6:fader`, `t6:send1`,
`src:harp`. Each stage has a level (`peak_db`, `rms_db`, `gr_db`), says whether it was measured or
estimated (`level_words()`: "−6.0 dBFS", "≈ −9.1 dBFS", "not measured"), the next stage and any
branches (sends), and, where the sound stops, `halt` (one of fifteen reasons, each with a heading
in `HEADINGS`), `why` in words and a `fix` ({label, verb, args, step}). `trace(from)` follows `next`
to the first halt; a mute on a folder is said as the child's FOLDER_MUTED. `apply_fix` runs the
fix's DAW verb inside one edit, so a fix is one undo step, and on a guest is the host's intent like
any other write. Nothing is decided by colour alone: `health()` ("ok", "hot", "clip", "silent")
always comes with the figure.

The meters are DAW-neutral fields on `MixState.TrackState`: `meter_peak` and `meter_rms` (the
input, then each plugin, dBFS), `meter_gr` (each plugin's gain reduction, NaN where it has none),
`meter_sends` and `main_send`. On the wire they are one volatile key, `/track/N/vu/signal` (four
arrays, `MixWire.pack_meters`), and the durable `/track/N/mainsend`, in the snapshot. A guest
builds its graph from the host's meters off the replication stream; it measures nothing itself.

Meters cost something, so they are made only while wanted: `DAWBackend.want_signal_meters()`,
called each frame the view is on, keeps them for `SIGNAL_KEEP_MSEC` (1.5 s), and a host keeps them
while guests are connected (`signal_meters_wanted`). The built-in engine (`GodotBackend`) builds a
probe bus a stage, each with copies of the track's chain up to it and an `AudioEffectCapture` at
its end, played by an extra player into the muted keys bus; peaks at METER_HZ, RMS from the
capture, the gain reduction worked out from a compressor's in and out RMS (`gr_derived`), sends from
their buses, recorded at METER_SEND_HZ. Reaper has a track's meter but no stage's: the fader is
measured, a send estimated from it and the send level (pre-fader: less the fader), and the
bridge's `GetMeters` (polled at METER_POLL_SECONDS while wanted) adds each plugin's own
`GainReduction_dB` where the plugin reports it, and the master send.

The view is this player's alone. `SignalView` (`hardware/signal_view.gd`) draws a graph through a
`place` callable (stage id to a point in the room, or null), so it knows nothing of Session or the
studio: one MultiMesh of tube segments on arcs (the lamp shader), Label3D pools for signs and
tags, a bead for a trace, and on a desktop a card on a CanvasLayer. The studio supplies the places
(`Studio.signal_place`: a track's stages at its stage voice, else its strip; the master at the
console's master section, OUT above it), the sources (`signal_sources`: instruments onto their
jack's track or the armed one, the mic onto its voice track, the sampler, grain cloud and platter
as local) and what a pointed-at thing traces from (`signal_target_of`). `signal_view_on()` is the
local hand's worn `SignalGlassesItem` or X; neither is room state. The glasses are a personal kind
and share the one head slot (`Interactor.worn`) with the headphones.

Levels everywhere (part three, D to G). `SignalGraph` has three allocation-free readers for
anything that meters: `fader_level(t)` (peak, RMS, measured), `send_level(t, slot)` (measured from
`meter_sends`, else the track's meter plus the send, ESTIMATED), and `arrival_level(state, dest)`
(the senders' peaks added as amplitudes, the worst case, and how many). `PinMatrix` reads them
through callables (`row_meter`, `col_meter`, `pin_meter`, `level_db`, `set_level_db`) so it knows
no DAW: header bars and clip lights always, and with `skyline` on (the studio's
`_follow_skyline`, while this player's view is on) a tower a pin whose top is a `Tower`
ControlAffordance, one undo step a drag. The AUDIO DEVICES wall meters only dawlings's own streams
by their AudioServer buses (PipeWire reports volumes and timings, not levels; a per-port peak would
need a capture stream on every port), and Reaper's outputs by its master meter.

`LevelsWall` (hardware/levels) is a surface on its own trolley in the MIXING ring: a column a track
(the fader through `DAW.set_track_volume`, `edits_as_one`), gain reduction from `meter_gr`, and the
master's loudness from `MasterState.lufs_*`, `true_peak_*` and `correlation`. Those come from
`LoudnessMeter` (core/audio), an ITU-R BS.1770 meter that `GodotBackend` feeds from a second capture
on the master bus on a WorkerThreadPool task, only while `loudness_wanted()` (a reader within reach,
or guests connected), and sends as the volatile `/master/vu/loudness` ([0] when not measured).
Other backends say `measures_loudness()` false, and the wall says "not measured". RESET is the DAW
verb `reset_loudness`.

Look to solo is `LookSolo` (core/input), run where the mix is: the host's own, and one per guest
asked by the room verb `look_solo` [track, held] and run `on_behalf_of` that guest. It keeps what it
changed ({track: [solo, mute]}) and puts exactly that back, group-free, inside one edit. The studio
lets go on focus loss, the view going off, a guest leaving and a project replaced; one is held in the
room at a time.

## Automation by gesture: a write bead

A `WriteBead` (`core/input/write_bead.gd`, docs/spatial_loop.md part two slice 22) is a
ControlAffordance that each Interactor stands over the automatable control it is on while the song
plays. A control says which lane it writes with `automates` (`automation_target()`: [track,
target] as MixState names lanes, or []), and is written through `write_from_bead`, its own write
path, so the bead drives the control and the control drives the mix. Pulled, the bead is the
control: its height over 0.5 m is the whole range. While it is out, three things hold:

- The lane does not play. `DAW.hold_lane` is a DAW verb (a guest's is an intent). The backend keeps
  `held_lanes` by player, OfflineBackend's `follow_automation` skips them, and `_writes_lane`
  makes no touch pass of one, so no automation mode changes and nothing times the hold out but
  the let-go or the player leaving (`release_lanes_of`, from `DAW.close_edits_of`). On Reaper the
  bridge's `HoldLane` switches the envelope's ACTIVE flag off and back, and the timeline poll still
  reads a held envelope.
- The control is held (`ControlAffordance.bead`, counted by `is_held()`): it ignores echoes,
  refuses hands and nudges, and no surface rebuilds or re-points it. Its network key is claimed, as
  a hand's grab would claim it.
- The bead keeps its own points at the song position its player HEARD (`GuestMidi.heard`), as
  takes are stamped, so a guest's lane is in time with what the guest heard, not with the host's
  playhead.

A pass is a stretch of those points: inside the loop while looping (in at its start, out at a
wrap or on leaving it), from the pull to the let-go when not. Each pass ends as one `set_automation`
of the whole lane (`WriteBead.merged`: the old lane kept outside the span, pinned 1 ms either
side), inside an edit opened at the pull or at the previous pass's end and closed with it. So
each pass is one undo step that takes back the lane and the control together.

## Items made while playing: cassettes

Every item in the room up to slice 23 is one of `ItemRoom.KINDS`: built into every room the same
way, so the room's state only ever says where each one is. A made item is different
(docs/spatial_loop.md part two, slice 23): it exists because somebody made it while playing, and it
carries something of its own. The first is the cassette (`CassetteItem`), a clip pulled out of the
3D timeline. Four decisions keep made items cheap and host-owned.

- **The host mints, and names.** `ItemRoom.mint(kind, data, maker)` runs on the host only. It picks
  the next free id in the shape `kind_of` reads (`cassette1`, `cassette2`, ...), and never reuses
  one in a room (`_made_after`), so a late row cannot be mistaken for a newer one. A guest never
  sends data. Its pull is the room verb `make` [kind, from], with `from` naming the clip
  ("clip:<track>:<index>"). The host packs it from its own song (`ItemRoom.made_data`).
- **What it carries travels once.** The row is {id: [kind, maker, bytes]}, with bytes being
  `var_to_bytes` of the item's data. It lives in `Session.made`, the same Dictionary as the
  room's `ItemRoom.made`. It goes out on its own reliable message, `_made`, before the room that
  names it. It is also sent to each joining guest in `admit()`, before the room. `_unmade` takes it
  away again. The room's state names only the ids (`"made"`) and where each one is, so a put-down,
  a throw or a give republishes a few bytes, never a clip. A guest keeps a row until the room names
  it (`apply_made`), and lets one go when the room stops naming it.
- **Bounded.** `MADE_BYTES` (256 KiB) caps an item, `MADE_TOTAL` (4 MiB) the room, and `MADE_MOST`
  (64) the count. Past any of them, `mint` refuses and says which (`made_refusal`), and the host
  tells the asker. A guest's `_made` refuses the same rows. `MixWire.pack_item` is what keeps a
  cassette small: notes and controls as PackedFloat32Array, an audio item's file by name with its
  offset, fades, gain and loop but never its peaks, and a demo item's `part` with its window. A
  two-minute take bent at 60 a second packs to 122 KiB.
- **A guest predicts.** Its pull puts a blank look-alike (`ItemRoom.look_of`) in the hand at once
  (`Studio._making`). The host's answer is three messages: the row, the holds (`Session.hand_to`
  puts the new item in the guest's hand), and the room naming it, acked. `apply_room` then drops
  the look-alike, and `_take_given` puts the real one into the hand that pulled it. A refused pull
  is acked with nothing named, and the look-alike goes.

Furniture can hold made items in slots: `ItemRoom.holders` is {holder: [Transform3D per slot]},
and an item in one is LOOSE at the slot's pose, with `slot_in`/`slot_n` and a room entry of
["slot", holder, n]. The cassette rack (`CassetteRack`, a station beside the prop shelf) is holder
`rack` (12 slots) and its BIN is holder `bin` (1 slot). Anything put into the bin is retired on
the host (`unmake`): it goes from the room and from `Session.made`, everywhere. A made item let go
within SLOT_REACH of a slot, or aimed at a free slot, goes into it (`put_down`). On a desktop, a
click on the rack's face or its bin with a cassette in the hand does the same. A full rack says so.
The room verb `slot_item` [id, holder, n] is a guest's ask.

Handing over is the room verb `give` [id, peer]. Only the item's holder can give it, and only to
someone in the room. The host carries it out with `Session.hand_to`, and the receiving hand takes it
when the holds arrive. A desktop player clicks a bandmate's ghost while carrying the item
(`Presence.peer_at`). Ghosts have no collision on the control layer, so a bandmate standing at the
desk or a station would lose the click to the control behind them. `ItemRoom.press_ahead` (the
studio's) tells the Interactor how far along the ray the ghost is, and a control further away than
that is not hovered, so the press is the item's. In a headset, the item is held within 0.25 m of their glove for 0.5 s
(`Presence.glove_near`). The host's made items are kept with its layout
(`LayoutProfile.made`, written beside the profile only when changed), slots and all, and are there
again the next time it opens the room. Joining someone else's session sets them aside without
saving: `Session.join` clears their rows (`_forget_made`), so only the host's room's are here and
none of ours count against its limits. On leaving, the host's go, and `Studio._on_role_changed`
gives ours back from the layout (`_restore_made`, only those not already here).

A cassette pastes (docs/spatial_loop.md part two, slice 24). `DAW.paste_item(track, start, packed)`
is a host-only verb, like `insert_audio_take`, and not in COMMANDS: no peer hands the host a clip.
It answers why not (`paste_refusal`) or "" and calls the backend's `paste_item`, one undo step under
Capability.PASTE_ITEMS. OfflineBackend (and so the built-in engine) unpacks the clip with
`MixWire.unpack_item` and lands it on the lane (`DAWBackend._locally_paste`), its peaks drawn from
the file here. ReaperBackend shows it on the cache the same way and sends one bridge `PasteItem`
(`paste_request`): a MIDI item with its notes and controls in project seconds, or an audio item of
the file by its absolute path with its offset, fades, shapes, gain, loop and direction. The
refusals are a frozen track, MIDI onto a track whose input is a microphone (or a DAW without
MIDI_TAKES), a file this machine does not have, and a demo part where there are no parts
(Capability.DEMO_PARTS, false on Reaper). The press is the Interactor's: with something that
`pastes` in the hand, a press on a control whose `paste_spot` names a place (TimelineLanes: the lane
and time under it, snapped unless fine; a strip's controls, a stage voice and its name by
`pastes_onto`: that track at the playhead) goes to `ItemRoom.paste` instead of a grab. A headset's
hand also pastes by pushing the cassette into a control's face (`_tend_push`, a ray from where its
middle was to where it is, inward). Letting go never pastes. The studio's `_on_paste_pressed`
pastes on the host (`paste_cassette`); a guest asks with the room verb `paste` [id, track, time],
and the host pastes the clip in its own row, only for the player holding that cassette. The hover
card says what a press would paste and where (`ControlAffordance.paste_words`).

A cassette at the ear plays its clip to that player alone (docs/spatial_loop.md part two, slice 25).
`EarCue` (core/audio/ear_cue.gd) is one node per studio. `Studio._follow_ear` gives it, each frame,
whichever hand here says it holds one there (`Interactor.cassette_at_ear`: XRInteractor within
HEAD_REACH of the head, with EAR_LEAVE of hysteresis; MouseInteractor while L is held). It is
personal like a lean. Its one player is on the keys' bus (AudioPorts.MONITOR), never the Mix bus, and
`Ears.cue` ducks everything else CUE_DUCK_DB on this machine. Nothing reaches the DAW. The sound is
made from the cassette's packed clip, so it works on any backend and on a guest: MIDI through
`GodotBackend.render_midi_frames` and a demo part through `DemoSong.render_window`, both made into
their streams on a worker (`EarCue.midi_stream`, `demo_stream`), and audio from the file. A render
outlives the cassette being taken from the ear: it is kept when done, picked up if the same one is
held up again, and nothing on the main thread waits for it but `_exit_tree`. Only the file is ever missing. A guest fetches it from the host with
`FileSend.fetch`, FileSend's one host-to-guest path: asked once by name, sent from the host's media
folder only when something in the room plays it (`_plays_here`), and kept in `user://fetched` until
the player stops being a guest.

### The sampler: one sound, one cassette

Anything can be a sample (docs/spatial_loop.md part two, slice 26). `Sampler` (core/music/sampler.gd)
is a station (`sampler`) standing against the outside of the vocal booth, a step from the cassette
rack: a pad bank, a gooseneck mic (`MIC_AT`) and a REC key (`Sampler.Rec`). REC is the room row
`sampler`, the peer it is armed for or 0; a guest's press is the room verb `sampler` [on], shown at
once and taken back if the host's room says otherwise, like any other prediction. It catches by the
same rule everywhere, but only on the host (`Sampler.heard`): the next use of an item within REACH
(1.5 m) of the mic, or by whoever armed it, then REC goes off.

What makes the sample exact is that every use carries its Foley take. `Item.use_take` is the take a
use rang (the duck's `squeak_take`, an instrument's `sound_take`), sent with the use as
`Session.item_used`'s `take`, as slice 17 sent it with `item_hit`. A copy elsewhere rings that same
take (`Item.heard_use`, Presence). The host's sampler writes `Foley.take_of(kind, take)` as it is,
its 16-bit samples after a header at Foley's rate (`Sampler.write`, `AudioTake.header(frames,
rate)`). The file is the very stream the player heard. A take's own tuning (the duck's squeaks, the
ball's bounces) is baked into the stream rather than played as a pitch. What the room does play as
a pitch, an instrument's second voice (`VOICE_PITCH`), a Tour curse and a handbell's chord tone
(`InstrumentItem.tune_at`, `Item.use_pitch`), reaches `Sampler.heard` as its `pitch`, and the take is
resampled to it before it is written (`Foley.resampled`). The kind is the item's (`Item.use_kind`,
`InstrumentItem.sound_kind`): a click or squeeze is a use; a shake reaches the host as a hit and is
caught as shaken, as is a pitched instrument's click, whose song position only the hit carries. A
yo-yo's or a deck's trick is a use too. Its take is the trick's count (`FidgetItem`), so a copy that
hears it plays that trick. Its sound is the whole trick, every sound in the trick's table
(`trick_sounds`) mixed where it rings (`Foley.layered`, `yoyo_trick`, `cards_trick`). A ball's bounce
is no use. It is `Item.rang` on every copy, as a throw is flown the same everywhere (Flight), and its
take is the bounce's number in the throw, so the host's own copy rings the take the thrower heard.
The host catches it for the thrower. The file goes into the media (`DAWBackend.media_path`,
`duck_squeeze_3.wav`, the next number free). The cassette is an ordinary made one
(`ItemRoom.mint`): an audio clip of the file, `sample` in its data, slotted into the rack's first free
slot. So the ear (FileSend fetches it for a guest) and the paste already work for it.

### The platter: the playhead by hand, and a scratch in your own ears

A DJ platter (docs/spatial_loop.md part two, slice 27). `Platter` (core/music/platter.gd, model
tools/blender/platter.py) stands on a leaf off the far end of the tape deck's cart, so it rides the
cart and is pushed with it; its station row says so (`cart`) rather than giving a footprint, and
`Venue.platter_spot` reads where the cart is now. Its one number is `turns`: bars from the song's
start, a turn a bar (`MixState.bar_at`, `bar_to_seconds`). Bare and let be, it follows the song and
its label turns with it.

Turned by a hand (`Platter.Disc`, a ControlAffordance whose plane is the record's face), the angle is
the song position. On the host that is `DAW.scrub(seconds, speed)`, a verb in the vocabulary like any
other, and the backend decides what it sounds like (`DAWBackend.Capability.SCRUB`). The base class
seeks quietly, which is all the stand-in does. The built-in engine seeks and, while stopped, opens a
short window (`GodotBackend.SCRUB_WINDOW`) in which its players, or the native lanes, play the mix
from the dragged place, each move afresh (`scrubbing`, `take_fresh_scrub`). Reaper is given OSC's
`/scrub` and the seek. Its card says which of these a turn is on this machine (`Platter.scrub_words`).
Holding it stops the transport; letting go plays on if it was playing. A flick back faster than
BACKSPIN turns a second spins on alone, slowing at a drag that lands it on the bar line its speed
spun back to, with `Foley.spinback` once; with no motion wanted it lands at once. A guest's turns are
not scrubs: they are seeks asked of the host, SEEK_HZ a second at most and the last always sent
(`_send_seek_if_due`), and the needle the guest hears is a Foley loop of its own (`Foley.needle_drag`).
Let go, a guest's platter stands where its last seek put it until the host's song is within a beat
of there, or SEEK_WAIT has passed (`_predicting`), so it does not jump back to the host's old place
for the round trip.

A cassette stood in its slot (the room's holder `platter`, laid by the studio wherever the cart is)
makes it a scratch instead, and the song is left alone. The clip is rendered as the ear renders it
(EarCue's MIDI and demo renders on a worker, or the audio file, fetched by a guest) and read by
`Varispeed` (core/audio/varispeed.gd): an AudioStreamGenerator on MONITOR, through Godot's mixer, fed
each frame the stretch from where the hand last had the clip to where it has it now, read in a
straight line, as loud as it is fast. It is this player's alone. Its tag says so at its figure
(`SCRATCH · MONITOR n ms`, `Varispeed.latency_seconds`). A scratch is also a path (`Varispeed.path`,
[dt, seconds, ...]), and `Varispeed.render` is the same arithmetic over it, so a scratch let go while
REC waits is the sample of exactly what was heard: the host renders it from its own render of the
clip and gives it to `Sampler.heard_stream` (a guest's path comes as the room verb `scratch`).
A render is real work on the host's main thread, so it is done only when REC waits and would catch
it (`Sampler.catches`, checked first in `Studio._sample_scratch`), and only of a path that fits
(`Varispeed.fits`: PATH_MOST steps and PATH_SECONDS, ten seconds, at most; what `follow` records
always does, and `render` stops at PATH_SECONDS whatever it is given).

### The history reel: undo by a crank

The tape deck's supply reel carries the history list (docs/spatial_loop.md part two, slice 28).
`ReelCrank` (hardware/transport/reel_crank.gd) is a ControlAffordance on the reel's hub, turned like
the platter's record: round its middle by a mouse or a fingertip, by a controller's twist. A notch
(30 degrees) is a step; anticlockwise is back. The crank gathers notches and does nothing to the mix
while it turns: once it has stood still SETTLE it calls `DAW.undo_to` once, the same verb the
timeline's history rail commits, so a turn of twelve notches is one jump, a guest's crank is one
intent, and the backends' undo_to (OfflineBackend's loop of its own undo and redo, Reaper's steps)
are untouched. Its ends are the history's (`MixState.undo_depth` and `redo_depth`), met with a knock;
where the DAW does not say its depth, a settle is that many undos or redos instead. Its readout is
words from `MixState.undo_names`, so an edit group is read by its name. With the song stopped a
settle plays two bars there with ordinary transport verbs and seeks back, which a guest asks like
any other; the two bars are timed from `MixState.counting_in()` ending, so a count-in before
playback is not taken for the song. A hand that settles while it still holds is re-based there, so
its next move counts from the settled step. It knows the DAW and not the session, as hardware does.

## Sections rearranged, as one edit

`DAW.arrange_sections(order)` (docs/spatial_loop.md part two, slice 29) lays the song's regions end
to end in a new order: `order` is `MixState.regions`, which are in song order, by their indices
there. It is a verb in COMMANDS under Capability.ARRANGE, one undo step ("arrange sections"), and it
answers why not (`DAW.arrange_refusal`) or "". A guest's is an intent carrying the order. The host
checks it again against its own regions in `apply_intent`, and Session's `_arrange_for` makes it as
the guest's, tells the room the new order, and tells the guest a refusal.

The plan is DAWBackend's and pure, so every backend and the bridge share it. `arrange_pieces` turns
the regions and the order into pieces, [from, end, to] in seconds in the new order: each region, and
each gap between two, which keeps its slot while the regions around it change. Laid end to end from
the first region's start, they end where the last ended, so nothing after moves. `arrange_cuts` is
every edge between two pieces side by side (or a piece and the song beyond) that move by different
amounts. Only there is anything cut, so a section nobody moved is left whole. Then each kind of
thing is laid out by its own function:
- items, split at a cut they cross (`item_slice`, on their own lane, notes and controls kept), each
  part moved with its piece (`arranged_items`);
- a comp's spans, the same way (`arranged_spans`);
- markers, with the piece each sits on, so a section's harmony and notes go with it
  (`arranged_markers`). A section with no bracket at its start plays the one before it (Harmony),
  which may not be before it now. `arranged_brackets` writes the harmony it had at its new start:
  onto the marker there ("Verse 2 [A minor]"), or as a marker that is only brackets. A progression
  is written turned round to start at the bar it had reached. The song after the last region keeps
  its harmony the same way when anything is there. A section from before any bracket takes what is
  before it now, since no bracket says "no key";
- the regions themselves (`arranged_regions`);
- every lane of automation (`arranged_lane`). Its own points move with the piece. Where a piece
  now meets one it did not, a point goes at its start with the value it had there, and a point
  just before an edge it ramps into (ARRANGE_EDGE). A point at the last region's end keeps the
  rest of the song as it was.

The song's clock moves only at a piece's start. `arrange_clock_refusal` refuses a tempo or
signature change anywhere else inside, and a tempo ramp through the pieces. So each piece keeps its
beats, and `arranged_clock` puts the tempo and signature held at each piece's start at its new
start, in beats, keeping what held past the end.

`_locally_arrange` writes all of it through the replicating addresses. OfflineBackend (and so the
built-in engine) remembers `_arrangement()` before and after as one step, which `_put_arrangement`
puts back. ReaperBackend shows it on the cache the same way and sends one bridge
`ArrangeSections` (`arrange_request`): the pieces, the tempo map and signatures only when they
moved, and those brackets. In one Undo block, the bridge reads everything first. It splits each item
at the cuts (SplitMediaItem), learns where each part, marker, region and envelope point goes, sets
the tempo map, and then puts everything there in seconds (SetMediaItemPosition, SetProjectMarker4,
InsertEnvelopePoint). A bracket renames the marker where it lands, or is a new one
(AddProjectMarker2). The master's "Tempo map" envelope is not among the envelopes: it is the clock,
which SetTempoMap and SetTimeSignatures set, and its points carry the signatures, so putting its old
points back would undo both. That way an item whose timebase is beats lands where the rest do. Its own
check refuses a locked item in the way, on tracks outside the bank too.

### Section blocks: the verb's surface

`SectionBlocks` (core/music/section_blocks.gd, station `sections`, slice 30) is the room's way to
the verb: the regions as a row of blocks along the bricks table's far long edge, each as long as its
bars. The table is laid out in bands (`Venue.TABLE_BANDS`, in the table's own frame from
`Venue.bricks_table`): the wheel's board at the end nearest the control room, the blocks along the
far edge, and the ledge for chord bricks (slice 31) along the near one. `Venue.band_spot` stands a
band's station facing the near edge, and the clearance loop holds the bands apart by BAND_GAP
instead of by each station's `air`. Each block is its own ControlAffordance whose frame's +Z is
up, so a held ray moves it along the table (Interactor._plane_point). While it is held the others
make room where it would go (`order_with`), and nothing is written. Its let-go is one
`DAW.arrange_sections` call, or none when it goes back to its place or is let go off the row. [
and ] (Studio), the wheel and the thumbstick move a block a place, a call each. A guest's row shows
the order it asked for until the host's regions arrive, or PENDING seconds pass. The row is rebuilt
from MixState whenever the regions or the clock change, and never under a hand. The block the
playhead is in is painted lighter and carries a mark at the playhead, a bar at a time at motion 0.
With no regions the row is one key, MAKE SECTIONS FROM MARKERS: a region per section marker's span
(`spans`; brackets alone and `Harmony.is_note` notes skipped, the last to the song's end at a bar),
added inside one open_edit, so it is one undo step and a guest's is that edit's intents.

### Chord bricks: a progression you hold

`ChordBrick` (core/items/chord_brick_item.gd, slice 31) is a made item of kind `brick`, and the
wheel is what makes them. A strip tile pulled off the board is a brick in the hand that pulled it
("chord:<key>:<chord>"), and MAKE BRICKS makes the strip into bricks on the ledge
("ledge:<key>:<chord>"). The host packs {chord, key} from those words alone. A brick's length is
not in its data but in the room's row `bricks` {id: bars}, so a nudge is one small row and never
resends what the item carries. A bare hand has no stick, so the brick in a hand is also turned to
another length (`ChordBrick.follow_turn` on Interactor.twist, a sixth of a turn a step), by the
same nudge.

The ledge (`ChordLedge`, station `ledge` in the bricks table's near band) is ItemRoom holder
`ledge`, whose slots' order is the progression (`ledge_row`). Holders now differ in three ways,
each a table in ItemRoom:
- `IN_ORDER` holders fill from the row's end (`next_in_order`), except a let-go right on a free
  slot (SLOT_EXACT), or a brick put back by, or aimed at, the free slot it was taken from;
- `BINS` swallow what goes in;
- `HOLDS` names the kinds a holder takes, so a cassette is refused by the ledge and a brick by the
  rack, and each says why (`kind_refusal`). Aiming along an IN_ORDER holder skips only its
  taken-slot check, never its kinds, so a cassette aimed along the ledge goes down instead.

Pressing is the cassette's paste, made general. `ControlAffordance.paste_spot_for(item, at, fine)`
lets a control take one kind of item and refuse another (a section block takes only a brick, at
its region's start, track ChordBrick.SECTION), and `Item.paste_text(spot)` lets the item word the
hover card. A brick pressed into a track is one `insert_midi_take` of block chords (a guest's is
that take's intent). Pressed into a section block, it writes the row's harmony at that section's
bar through `FifthsWheel.write`, the same one edit_marker the wheel's SET makes (a guest's is the
wheel's `harmony` ask). So everything that reads Harmony follows it. A sticky note on that bar line
is never renamed: it is moved `Harmony.NOTE_NUDGE` along and the brackets are added at the bar, in
one edit (`DAW.open_edit`).

## Spectra: what each track takes of the frequencies

The EQ wall (docs/spatial_loop.md part two, slice 36) shows each track's spectrum and where two
tracks fight for the same bands. Four parts, each knowing only the next:

- **Measured where the sound is.** `GodotBackend` ends every track bus ("R3D N") with an
  AudioEffectSpectrumAnalyzer, after the width and the pan, so it hears what the track puts out.
  Cues, probes and sends copy a bus's effect slots, not its tail, so none of them carries one, and
  a render's capture goes on after it. Godot runs a bus's effects before its volume, so
  `track_spectrum(i)` adds the fader (taper and VCA) itself, and a track not heard reads the floor.
  It reads only while someone has asked in the last 1.5 s: 20 times a second, 31 third-octave
  bands, the power averaged over 300 ms. Capability SPECTRA says which engines can; Reaper plays
  to its own outputs and cannot, nor can the stand-in.
- **Held by one node.** `Spectra` (core/audio/spectra.gd) is the studio's. On a host, or a lone
  player, it reads every track that makes sound. On a guest it reads `Session.spectra`, while that
  is fresh. It holds the reference the clash rule and the wall are drawn against: the mix's loudest
  band, rising at once and falling 6 dB a second, never under -48 dBFS. A fixed -30 dBFS floor
  found nothing in a mix whose loudest band is -20. Its static half is the arithmetic, with no
  state: band edges and names, `clashes` (both within 30 dB of the reference, within 6 dB of each
  other, runs of bands, worst first), and `pack`/`unpack` for the wire. Folders are not measured,
  being their children's sum. A return fed by sends is measured, but `feeds` keeps it from
  clashing with any track whose sound reaches it (through a send or a folder's), and a clash with
  a return ranks after every clash between two dry tracks. In the demo the reverb return otherwise
  took every glow from the kick and the bass.
- **Sent as bytes, and allowed to be lost.** `Session.send_spectra` sends the host's bands five
  times a second, a byte a band per track (0.4 dB steps from -96 to +6) in parcels under 1100
  bytes, unreliable and ordered on `SPECTRA_CHANNEL`. A lost parcel is replaced 200 ms later, so
  nothing waits on it, and it shares no channel with an edit.
- **Drawn without knowing where from.** `EqWall` takes callables (`spectra`, `reference`,
  `reason`, `motion`) and never names Session or the backend, as no hardware surface does. Its
  layers are see-through and sorted by render priority (shapes, then glows, then lettering), since
  a name at a shape's far edge would otherwise be drawn under the shape. Only the worst four
  clashes that do not overlap glow. A wall lit everywhere points nowhere, and SHOW's WORST CLASH is
  there for the rest. The glows are laid out first, and the shapes' names are put clear of them
  and of one another. A name is left off where a glow over its band already names that track.
- **Carved through the verbs that exist.** A glow is grabbed on one track's side and pushed (slice
  37). `EqCarve` (core/music/eq_carve.gd) is static and pure, like `Sidechain`: which engine
  carves, read from the plugin choices so a guest reads it as its host does (the built-in `eq21`
  kind, AudioEffectEQ21's 21 half-octave bands, or a ReaEQ); which bands a clash's span covers;
  ReaEQ's band, frequency, bandwidth and gain found by their parameters' names; and the writes.
  There is no carve verb. The push is `add_fx` (the first one, at the chain's end) and
  `set_fx_param`, inside the glow's one edit (ControlAffordance.edits_as_one). The EQ is asked for
  only once the push has cut (a Shift notch's worth): a click or a grab held still asks for nothing
  and leaves no undo step. The glow keeps its push until the EQ is in the state, so where the EQ
  comes later (a guest's host, Reaper's poll) the bands are written when DAW.fx_changed says it
  has come, once the plugin has finished landing; meanwhile the track is remembered as asked for
  (Clash.asked_for, static, lapsing after ASKED_FOR_MSEC), so a let-go and a grab again carries
  the waiting push on and never asks twice. The wheel turned during a drag moves the push's base
  under the drag. On Reaper the carve is ReaEQ's one band, so a carve on a second clash moves it
  and gives the first back; the card says so where the band is cutting elsewhere. A glow in a hand keeps its clash, so
  a carve that ends the clash does not put the glow out under the hand. Godot's bands overlap: a
  sine at the centre of two bands cut 12 dB loses about 5, so the card names the bands it cuts
  rather than promising a notch.

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
| `--no-motion` | surfaces cut rather than glide, signal beads stand still, the room does not react; wins over COMFORT's saved Motion and Room reacts |
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

## The Workshop: changing the game from inside it

A dev tool, only ever on the developer's own machine (docs/workshop.md has all of it). A request
typed on the Workshop's panel (station `workshop`, on the control room's right wall, or F9 from
anywhere at a desk) is handed to the Claude Code CLI, which edits this repo; the game checks the
change and reloads itself onto it.

- **Gated, not hidden.** `Workshop.enabled()`: a dev flag (`--workshop`, DAWLINGS_WORKSHOP=1, the
  project setting `dawlings/dev/workshop`, or user://workshop.cfg), not an exported build, `claude`
  on PATH, and never a guest. Off, `Venue.workshop_spot` is null, so the row (`"dev": true`) is no
  station at all: not on the card, the board, I's cycle or the clearance loop. The suite forces it
  off. Nothing of it is replicated; its keys are `personal()`.
- **Never waited on.** The CLI is a process of its own (`WorkshopRunner`: `claude -p
  --output-format stream-json --restricted --permission-mode dontAsk` with an allow-list of tools
  and commands), its stream a file tailed a little each frame (`WorkshopStream` turns it into panel
  lines); git and the checks run on a thread.
- **A request's change is its own.** The tree always has other uncommitted work, so a request's
  change is the files whose git blob ids moved while it ran (`WorkshopCheckpoint`), copied before
  and after; Undo restores only those, and only where they are still as it left them.
- **What "this" means.** `WorkshopJournal` keeps the player's last five minutes from the places
  everything already passes (every ControlAffordance's grab and value, every Item's state, the
  station, the focus, the transport, the toasts, the engine's log, a sparse trail and what is
  looked at), and `WorkshopContext` writes it with the game's state to a file the prompt names,
  scrubbed of codes, tokens, addresses and home paths.
- **A reload is a new process.** Live script reload with the room standing is fragile, so
  `WorkshopResume` saves where the player is, the song and the panel's history, starts the game
  again with `--resume`, and quits; the new one puts it all back. Guests are told; they rejoin by hand
  (the session has no reconnect yet).
