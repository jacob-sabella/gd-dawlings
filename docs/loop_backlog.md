# Backlog

What is actually finished, what is scaffolded, and what has not been started. Kept honest
because a scaffold that reads as a finished project wastes the next person's afternoon.

## Working, verified

- **DAW abstraction.** `core/daw/` holds the backend contract, the mix cache, the wire
  vocabulary and the autoload; `core/reaper/` holds only what is Reaper's. Capability queries
  and the fader taper are per-backend, and `OfflineBackend` is a peer rather than a fallback
  branch. Adding a second DAW is implementing one class.
- **OSC link.** Codec (encode, decode, bundles, padding), UDP peer, echo guard. Headless
  checks green via `tools/verify.sh`.
- **State cache.** Tracks, FX, sends, transport parsed into `MixState`.
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
- **Arrange timeline.** A lane per track with the track's colour and flags, a bar ruler from
  the tempo whose label spacing follows the zoom, section markers, the blocks on each lane, and
  a playhead that moves without rebuilding the panel. An overview bar underneath scrolls with
  its body and zooms by either end; the view pages forward on its own while the transport
  rolls and leaves the window alone while it is stopped. Defaults to SCREEN in every medium,
  including AR. The window arithmetic, the clipping, the follow rule and the item wire format
  are tested.
- **Track banking.** `MixState` knows which slice of the project its indices mean, moving the
  bank drops the cache rather than leaving the previous bank's names on this bank's faders,
  and the desk grows a BANK module saying "65-90 OF 90" when there is more project than bank.
  A bank asked for while a hand is on a control is deferred until the hand lets go. Tested,
  but never photographed or run against a project big enough to need it -- the stand-in has
  twelve tracks and correctly builds no bank module at all.
- **Capture harness.** `tools/shot.sh`, with reproducible camera framing on the command line.
- **Presentation switching, both ways.** The flat overlay (Tab) for the screen participant, and
  a grab handle clipped to each surface for everyone else: tap to cycle anchor, drag to place.
  Both call the same `SurfaceMount.set_mode()`. The tap/carry split and the anchor cycle are
  tested; the headset half of it has never met a runtime, like the rest of the XR path.
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
- **ReaScript bridge.** `GetTimeline` is written, parsed and tested against the payload shapes
  it actually produces, and `can(TIMELINE)` now tracks whether the bridge is loaded -- but none
  of it has run against a live Reaper, only against replayed answers.
  `GetProjectStructure` is still not consumed by anything: track colours, folder structure and
  unambiguous send destinations are all sitting there unused.
- **XR session.** The rig is built and wired: `XRRig` instantiates the head, both controllers
  and an `XRInteractor` per hand, the studio builds it instead of the desktop camera when the
  medium is not SCREEN, and the left controller's `by_button` runs the two-mark room
  calibration. Untested against an actual runtime -- there is none on this machine -- so what
  is verified is the arithmetic and the construction, not the tracking.

## Parked

- **Multiplayer.** Not needed for this round (decided 2026-10-07). The replication path works
  end to end -- two processes, host and guest, durable state reliable and meters unreliable --
  and it stays in the tree rather than being torn out, because taking it back out and putting
  it back later costs more than leaving it. Nothing further is invested in it: no avatars, no
  discovery, no delta compression. The constraint it still imposes on new code is the one worth
  keeping: a control change goes through `Session.send_intent()` rather than straight at
  `Reaper`, so that whoever owns the link is a question the surfaces never have to ask.

## Not started

- **Mobile renderer pass.** `project.godot` sets the override; nothing has been tested on a
  standalone headset, and the headline hybrid client is exactly that.
- **Audio.** The studio is silent. Reaper's output does not come through this process at all.

## Known rough edges

- Rack unit labels can overlap their first knob caption on long plugin names.
- `PatchCable` rebuilds its whole mesh on every patchbay rebuild rather than moving endpoints.
- The timeline rebuilds every lane while the overview bar is being dragged -- one rebuild per
  frame, which is fine at twelve tracks and will not be at ninety. Items want to be moved
  rather than recreated, the way the playhead already is.
- The offline stand-in's meter ballistics are eyeballed, not matched to Reaper's.
- The master section has no monitor level, dim or mono. Those belong to a monitor controller,
  which Reaper does not know about and has no OSC address for -- deliberately absent rather
  than faked, and the gap closes only if something other than Reaper ends up driving it.

## Blender-authored parts

Done: the knob (`tools/blender/knob.py` → `assets/hardware/knob.glb`).

Finding from photographing it: **the knurling does not pay at FX-rack distance.** Front-on, the
skirt hides behind the cap and 18 flutes cost geometry for a silhouette nobody can resolve. It
pays where the skirt is actually seen -- the console pan row, looked down on from a seat at the
desk -- and it will pay in VR. Before authoring the next part, decide what distance it is read
from and spend the triangles there; 1088 tris is on the heavy side for something there are a
hundred of, and most of them are in the chamfers, which do pay.

Done since: the fader cap, and the tape reel flange.

The fader cap confirmed the rule -- its scooped silhouette reads at ordinary desk distance
where the knob's knurling did not. The reel went further and found the better question: not
"how detailed should this part be" but "which half of it is the same in every session". The
flange is; the tape pack is not, and splitting them that way turned a cosmetic pass into a
readout the transport did not have.

Done since: the jack socket. The plug shells were already made properly during the cable work
and did not need redoing -- the socket was the half that was letting them down.

Next candidates, in order of how much screen they own:
- Chamfered chassis edges and 19" rack ears.
- The meter bridge arm, which is currently two posts and a shelf.

Still outstanding from before any of this: the mobile renderer pass (3782 tris per reel is
fine on desktop and worth re-measuring on a standalone headset), audio, consuming
GetProjectStructure, guest write round-tripping, and the participant roster.
