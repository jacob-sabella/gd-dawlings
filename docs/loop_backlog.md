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

Done since: the 2U rack faceplate, which was filed as "rack ears" and was the wrong unit of
work -- the ears are not a separate part, they are the ends of the panel with holes in them.
Asking "which half does not depend on the session" gave the right answer again: a rack is as
tall as the session has plugins, but a 2U panel is 19 inches by 2U in every session there has
ever been.

That exhausts the parts worth authoring for now. The remaining geometry is either procedural
by nature (the console, the rack frame, the timeline) or furniture that nobody looks at. The
meter bridge arm is the one leftover, and it is two posts and a shelf because that is what it
should be.

Still outstanding from before any of this: the mobile renderer pass (3782 tris per reel is
fine on desktop and worth re-measuring on a standalone headset), audio, consuming
GetProjectStructure, guest write round-tripping, and the participant roster.

## Audio

Done. `core/audio/foley.gd` synthesises five sounds; see architecture.md for the shape of it.

Two findings worth keeping:

**The mix was never the gap.** "The studio is silent" had been sitting in this list for a while,
and the obvious reading of it -- play the audio -- is wrong. Reaper is already making that sound
through the monitors in the same room, and a second copy a few milliseconds late is a comb
filter. The gap was the *gear*: a desk you can touch that makes no noise when you touch it.
Worth remembering the next time something on this list is phrased as an absence; the absence and
the fix are not always the same thing.

**`tools/verify.sh` could pass over a build that did not build.** A broken `knob.gd` printed
`499 checks, 0 failed` -- a GDScript that fails to parse does not throw, it simply is not there,
so `Knob.new()` returned null, every check that would have touched a knob never executed, and
the count dropped by seventeen while the summary stayed green. Fixed: verify now greps its own
output for `SCRIPT ERROR` and fails the run. This had been true for the whole project and would
have been true for every future tick.

## GetProjectStructure

Done. Colour, folder structure and send destination indices now come off the bridge on an
eight-second poll; see architecture.md.

Three findings:

**A level-change rule cuts a bus off from its own children.** The obvious way to draw folder
breaks is "where the nesting level changes", and it is wrong, because a folder's parent sits at
the *outer* level -- that is what makes it the parent. It put the VOX bus in with the guitars.
The rule that works is: break where a track opens a folder, or where the level drops.

**The stand-in project was lying about Reaper's data model.** It had folders with `Kick` as the
parent, which is legal and is not what a session looks like -- Reaper folders are parent-first
and the parent is the submix bus. Reordered with `DRUMS` and `VOX` buses at the head of their
groups. Worth watching for generally: the offline project is the only session anyone can open
without Reaper running, so anything it models incorrectly is what the feature gets designed
against.

**Two tests were pinned to incidental demo numbers**, not to what they meant -- a literal track
count of 12, and "track 1 has items" where track 1 is now a bus that correctly has none. Both
now assert the intent (guest count *equals host count*; the arrangement is non-empty across the
project). A test that breaks when the fixture changes shape was testing the fixture.

## Mobile / drawing budget

Measured, and the measurement overturned this list's own framing. See architecture.md.

**This entry was wrong about what the problem was.** It said "re-measure 3782 tris/reel, ~100
knobs at 1088" -- a triangle budget. Triangles were never the issue: 203k at 90 tracks is
nothing. Draw calls were, at 3,370, and the single biggest contributor was the VU meters at 37%
of the whole studio. A vertex problem and a draw-call problem have opposite fixes, so a guess
here would have cost a tick and fixed nothing.

**Two of the three performance monitors I reached for were wrong by orders of magnitude** --
`Performance.TIME_PROCESS` by 100x, `Engine.get_frames_per_second()` by enough to be useless on
a short sample. Both now deleted from the tool. If a number in a measuring tool is wrong it is
worse than absent, because it is the one that gets acted on.

**A MultiMesh cannot be tested headless.** Its buffer lives in the rendering server and the
headless one is a stub that accepts writes and returns black. Any future widget converted this
way has to lift its decision into a pure function first, or it silently stops being covered.

### Still open

- More draw-call reduction: the console is still ~1,032 meshes at 90 tracks. Buttons (2 meshes
  each) and the fader slot/cap are the next candidates; the same MultiMesh trick applies to the
  button lamps. Measure before and after with `tools/budget.sh`, as above.
- The budget tool measures one camera angle, so culling flatters wide desks. A second pose
  (nose-to-the-desk, where nothing is culled) would bound the worst case.
- Guest write round-tripping of provisional values; participant roster on a guest.
- The timeline rebuilds every lane while the overview scrubber is dragged (one rebuild/frame).
  Fine at 12 tracks, not at 90; items want moving rather than recreating, as the playhead does.
