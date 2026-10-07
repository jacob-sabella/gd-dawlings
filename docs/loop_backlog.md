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
- **Guest replication.** Host buffers changes by address at 20Hz, split durable/volatile for
  opposite delivery guarantees, with a full reliable snapshot on join. Verified two ways: the
  snapshot round-trip is asserted field by field in the suite, and `tools/session.sh` brings up
  a real headless host and a real guest that renders what it was sent.

## Scaffolded — the shape is right, the wiring is not finished

- **Guest writes round-tripping.** Intents reach the host and are applied, and the result
  replicates back — but a guest's own fader shows its hand position until that round trip
  completes, which on wifi is long enough to see. Needs the same provisional-value treatment
  the host's controls already get from the echo guard.
- **Participant list on a guest.** A guest registers peers it hears from; the host never sends
  the roster, so a guest does not know who else is in the session until they speak.
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

## Parked

- **Multiplayer.** Not needed for this round (decided 2026-10-07). The replication path works
  end to end -- two processes, host and guest, durable state reliable and meters unreliable --
  and it stays in the tree rather than being torn out, because taking it back out and putting
  it back later costs more than leaving it. Nothing further is invested in it: no avatars, no
  discovery, no delta compression. The constraint it still imposes on new code is the one worth
  keeping: a control change goes through `Session.send_intent()` rather than straight at
  `Reaper`, so that whoever owns the link is a question the surfaces never have to ask.

## Not started

- **Arrange timeline.** The one surface that is explicitly *not* hardware — a long flat thing
  that belongs in SCREEN mode. `Presentation.default_mode` already routes `&"timeline"` there.
- **Master section** on the console: master fader, monitor level, meters.
- **Track banking.** Fine up to 64 tracks; beyond that the bank has to scroll, and a strip must
  never change which track it means while a hand is on its fader.
- **Mobile renderer pass.** `project.godot` sets the override; nothing has been tested on a
  standalone headset, and the headline hybrid client is exactly that.
- **Audio.** The studio is silent. Reaper's output does not come through this process at all.

## Known rough edges

- Rack unit labels can overlap their first knob caption on long plugin names.
- `PatchCable` rebuilds its whole mesh on every patchbay rebuild rather than moving endpoints.
- The offline stand-in's meter ballistics are eyeballed, not matched to Reaper's.
- No master-bus meter anywhere, which is the one meter an engineer actually watches.
