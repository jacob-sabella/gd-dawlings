# Backlog

What is actually finished, what is scaffolded, and what has not been started. Kept honest
because a scaffold that reads as a finished project wastes the next person's afternoon.

## Working, verified

- **OSC link.** Codec (encode, decode, bundles, padding), UDP peer, echo guard. 65 headless
  checks green via `tools/verify.sh`.
- **State cache.** Tracks, FX, sends, transport parsed from Reaper's address space.
- **Console.** A strip per track: fader, pan, rec/mute/solo, VU with real ballistics, colour
  chip, dB readout. Built from live track count.
- **Tape deck.** Transport buttons, position counter, tempo, reels that turn only while Reaper
  says it is rolling.
- **FX racks.** 19" units, one per FX slot, in Reaper's own order. Knobs are the plugin's first
  eight real parameters with Reaper's names.
- **Patchbay.** Jacks per track, hanging cables for existing sends, drag-to-patch gesture.
- **Presentation split.** Three anchors, per-viewer layout profile, runtime reparenting.
- **Room calibration.** Two-point maths, gravity flattening, drift detection. Tested.
- **Offline stand-in.** 12-track synthetic mix with moving meters, so everything above is
  developable and photographable with no DAW running.
- **Capture harness.** `tools/shot.sh`, with reproducible camera framing on the command line.

## Scaffolded — the shape is right, the wiring is not finished

- **Guest replication.** Intents travel guest → host and are applied. State does **not** travel
  back down yet, so a guest currently sees an empty console. This is the single biggest gap:
  everything else in the multi-user design is built around it.
  *Next:* host publishes a delta per changed track on a fixed tick; guests apply into the same
  `ReaperState` the surfaces already read.
- **Calibration gesture.** `RoomAnchor.mark_origin/mark_forward` work and are tested; nothing
  calls them from a controller yet. Needs a two-step in-headset prompt.
- **ReaScript bridge.** Lua side is written and syntax-clean; `GetProjectStructure` is not yet
  consumed by anything. Track colours, folder structure and unambiguous send destinations are
  all sitting there unused.
- **XR session.** `XRBootstrap` initialises OpenXR and negotiates passthrough; no `XROrigin3D`
  rig, controllers or hand interactors are instantiated in the studio scene yet. `XRInteractor`
  exists and is unreferenced.
- **Presentation switching.** `SurfaceMount.set_mode()` works; no UI or binding calls it, so
  moving a surface between screen and room is currently a code change.

## Not started

- **Arrange timeline.** The one surface that is explicitly *not* hardware — a long flat thing
  that belongs in SCREEN mode. `Presentation.default_mode` already routes `&"timeline"` there.
- **Master section** on the console: master fader, monitor level, meters.
- **Track banking.** Fine up to 64 tracks; beyond that the bank has to scroll, and a strip must
  never change which track it means while a hand is on its fader.
- **Participant avatars.** Head poses are replicated and nothing draws them. Seeing where
  someone is looking is most of the value of being in a room together.
- **Peer discovery.** `--join <address>` only. mDNS would remove the last typed IP.
- **Mobile renderer pass.** `project.godot` sets the override; nothing has been tested on a
  standalone headset, and the headline hybrid client is exactly that.
- **Audio.** The studio is silent. Reaper's output does not come through this process at all.

## Known rough edges

- Rack unit labels can overlap their first knob caption on long plugin names.
- `PatchCable` rebuilds its whole mesh on every patchbay rebuild rather than moving endpoints.
- The offline stand-in's meter ballistics are eyeballed, not matched to Reaper's.
- No master-bus meter anywhere, which is the one meter an engineer actually watches.
