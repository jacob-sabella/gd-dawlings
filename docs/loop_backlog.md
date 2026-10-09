# Backlog

What is actually finished, what is scaffolded, and what has not been started. Kept honest
because a scaffold that reads as a finished project wastes the next person's afternoon.

## Working, verified

- **Guest audio takes.** A guest's microphone records onto the host's track, placed by the song
  position the guest heard and kept there by a rate loop against clock drift. Within 1ms of the
  click offline and on Reaper (`tools/session_probe.sh`). Drawn as a waveform on the timeline,
  played by the built-in engine, placed through the bridge on Reaper.
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
  says it is rolling. The tempo is set from the deck: a knob beside the BPM readout (40-240) and a TAP key
  (three taps or more, averaged over the run). `DAW.set_tempo` is clamped to Reaper's 1-960 on
  both sides of a session, is undoable offline, and goes to Reaper as `/tempo/raw`. A guest's
  tempo reaching a live Reaper and coming back is checked by `session_probe.sh --reaper`.
  A CLICK key opposite TAP switches the metronome (`DAW.set_metronome`, `/click` on the wire).
  Reaper's `/click` is a toggle like `/repeat` -- checked on the rig: 1 flips it, 0 is ignored,
  and Reaper answers with the state -- so a press is sent only when it would change something.
  `live_check` reads the metronome back through the bridge's GetState (action 40364's toggle
  state), and checks a send level and pan the same way.
  A locator between the reels: the section the playhead is in (the last marker at or before it)
  under the counter, and PREV / MARK / NEXT keys. MARK is `DAW.add_marker` -- undoable offline,
  the bridge's `AddMarker` in Reaper (one "Insert marker" undo point), so it needs the bridge
  (`Capability.MARKERS`). PREV inside 0.4s past a marker goes to the one before it, so pressing
  it while rolling is not pinned in place. Checked by the suite, `session_probe.sh` (a guest's
  marker reaches the host, also `--reaper`) and `live_check` (Reaper's marker list has it, and
  one undo takes it out). Reaper's markers keep their beat, so a tempo change moves them in
  seconds -- seen on the rig when the probe's guest tempo moved its own marker.
- **Send level and pan.** `DAW.set_send_volume` / `set_send_pan` (a send is a track and its
  1-based slot, as OSC numbers it; a guest's intent is checked and clamped on the host), undoable
  offline, `/track/N/send/M/volume|pan` to Reaper. On the desk as SENDS ON FADERS: the master
  section's SENDS key flips every strip's fader and pan to its send to one return, then the next,
  then back. Fixed on the way: the bridge's sends were 0-based against OSC's 1-based (two
  half-sends per real one), and `/send/M/volume/str` was parsed as the level. Verified by the
  suite, `session_probe.sh` (a guest's send level reaches the mix and comes back) and
  `session_probe.sh --reaper`; Reaper was seen to take an OSC send write (-11.0dB, 50%L back).
- **Input monitoring.** `DAW.set_track_monitor` (Reaper's I_RECMON numbers: 0 off, 1 on, 2 auto;
  clamped on both sides of a session), undoable offline, `/track/N/monitor` to and from Reaper --
  which, checked on the rig, sends and takes one float despite its config listing a b/ and an
  i/ pattern there. A fourth key on every strip under MUTE steps off -> on -> auto; its lamp is
  a green dot, steady for on and blinking for auto. `live_check` checks both directions against
  GetState's I_RECMON; `session_probe.sh` (also `--reaper`) has a guest set it.
- **FX racks.** 19" units, one per FX slot, in Reaper's own order. Knobs are the plugin's first
  eight real parameters with Reaper's names.
- **Patchbay.** Jacks per track, hanging cables for existing sends, drag-to-patch gesture.
- **Presentation split.** Three anchors, per-viewer layout profile, runtime reparenting.
- **Room calibration.** Two-point maths, gravity flattening, drift detection. Tested.
- **Multiplayer.** A host-owned roster with colours, avatars, and pointers addressed by control
  key. The host arbitrates holds, so a control has one hand. Late echoes are ignored after
  release. Sessions are found by LAN discovery and managed from the session panel (**M**). A
  goodbye is sent on leave, and a guest falls back to solo when its host is gone. An optional
  session code admits only those told it; nothing reaches a guest until it is admitted. Verified
  by `tools/session_probe.sh` (also `--reaper`) and `tools/session_shot.sh`. Still open: XR
  calibration across participants is untested, and nothing is encrypted.
- **The mix's sound, to guests.** Reaper's outputs are tapped through PipeWire and sent over
  UDP to admitted guests, with an adaptive jitter buffer and clock-drift correction. Measured at
  46ms end to end by `tools/audio_latency.sh`. Still open: no codec (1.5Mbit/s per listener),
  picture ~45ms ahead of sound, and Linux/PipeWire hosts only.
- **Recording a guest (MIDI).** Every mix packet carries the host's song position. The guest
  stamps each note with the moment it heard, monitors on a local electric piano, and sends a take
  as one `insert_midi_take` when it hears recording stop. The take is placed offline (undoable,
  replicated) or in Reaper through the bridge, and drawn as a piano roll on the timeline. MIDI
  keyboards, or the computer keyboard by opt-in. Verified by `tools/session_probe.sh`
  (also `--reaper`): notes land within 0.25ms offline, and within 2.2ms against Reaper after a
  take's first second (~5ms in it). See docs/architecture.md, "Recording a guest".
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

## Built-in engine (GodotBackend), next

- Recording into the built-in engine (a track armed takes the mic through `AudioEffectRecord`).
- The user's own audio files and stems as items, not just the synthesised demo song.
- MIDI items played through a small built-in synth. A guest's take already lands on the built-in
  engine (it inherits the stand-in's `insert_midi_take`) but is silent; MonitorSynth is the
  obvious voice for it.
- The click and input monitoring are accepted by the built-in engine but make no sound yet.
- Saving and loading a project, probably as DAWproject (MIT).
- The demo mix is heavy below 150Hz; worth a pass by ear.
- The alternatives if more than Godot's effects is wanted: a headless Ardour over OSC (GPL at
  arm's length, desktop only), or Tracktion Engine (GPLv3 or commercial).

## Parked

- **Where the host keeps guests' recordings.** Takes are written to `user://takes/` and, on
  Reaper, copied beside the project when it has been saved. Unsaved, Reaper points at the copy
  in `user://takes/`. Whether the host should choose a folder (or be asked on first take) is a
  decision for the user.

- **More than about ten listeners.** A session admits up to 32 guests (Godot's default), but
  the mix is uncompressed at about 1.5 Mbit/s per listener, and there are 8 colours, so the ninth
  ghost shares one. Opus would make the audio cheap, and a longer palette (or hue variants) the
  colours. Not started: nobody has asked for big rooms yet.

## Not started

- **A guest's microphone, calibrated.** Audio takes from guests work (see "Recording a guest"
  in docs/architecture.md), measured with a synthetic microphone. A real card that misreports
  its input latency puts takes early or late by the error; a clap-on-the-click calibration that
  sets `GuestAudio.offset_ms` would close it.
- **Hearing your own microphone** through the game while recording, with its latency allowed
  for the way "Hear my keys" is.
- **A calibration routine for the capture offset** (`R3D_CAPTURE_OFFSET_MS`): record a guest
  playing on a click into the host's Reaper and read the offset off the take.
- **Live preview of a guest's notes on the host** through Reaper's `/vkb_midi/` OSC path,
  labelled as late.

- **Mobile renderer pass.** `project.godot` sets the override; nothing has been tested on a
  standalone headset, and the headline hybrid client is exactly that.

- **Reaper parity, still missing** (after sends on faders, the click, the locator and input
  monitoring):
  - Send mute: there is no OSC address for it, so it would be a bridge edit.
  - Pre-roll and count-in.
  - Automation modes. `t/track/@/autoread` and its siblings exist, but Reaper reports them only
    for the selected track.
  - FX: adding, removing, presets (`fx/@/preset+-`) and wet/dry (`n/track/@/fx/@/wetdry`).
  - Tracks: adding, renaming and recolouring them.
  - Markers: renaming and deleting them, and regions of any kind.
  - Time signature.
  - `tools/shot.sh --focus patchbay` frames only the floor.

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

**The budget tool was measuring one camera angle, and that angle was hiding more than half the
scene.** The default framing fits the console to the viewport, so at 90 tracks the desk runs off
both edges and most of it is culled. The numbers reported in the previous entry were flattering
by **2.3x** -- the real worst case was 4,911 draw calls, not 2,132. `tools/budget.sh` now sweeps
two poses and `wide` is the one to read. A benchmark whose framing discards the workload is not
measuring the workload.

**Buttons are now banked too.** `MeshBank` is the general form of the meter's one-off: claim a
slot, get a transform and a colour back, one draw call for the lot. Console meshes 1,032 -> 492;
wide-pose draw calls at 90 tracks 4,911 -> 3,295. The bank is optional -- a `PanelButton` with no
bank builds its own two meshes -- so nothing outside a console surface had to change.

**The plate, the colour chip and the fader slot are banked too.** 2,492 draw calls at 90 tracks
wide, from 3,295; the console itself is 222 meshes, from 1,032 three ticks ago.

**Two things the draw-call number could not have told me**, both caught by looking:

- `MeshBank.parts` had never honoured per-instance colour at all. A `StandardMaterial3D` ignores
  `COLOR` unless `vertex_color_use_as_albedo` is set, and it was not. This was invisible for a
  whole tick because the only caller claimed everything `Color.WHITE`, so the bug and the
  intended result were the same picture. The moment something actually needed a tint it would
  have drawn 90 chips in one shade.
- **Driving a colour chip like a lamp destroys the thing it is for.** At the lamp's 2.4 gain
  every pastel track colour clipped to the same pale wash, which is the exact failure the chip
  exists to prevent. Chips now scale by the headroom available, so hue is preserved exactly.
  A screenshot A/B found this in seconds; no number in the budget tool would ever have mentioned
  it. Performance work needs a picture as well as a measurement.

**The patchbay's jacks are banked, and the result forced a correction to how this whole effort
has been measured.** Banking 180 jacks moved the draw-call count *not at all*, while objects
fell 4,919 -> 3,845 and primitives halved. That looked like a broken counter, so I stopped and
microbenchmarked it rather than guessing: 400 boxes, loose with one shared material, loose with
a material each, and as one MultiMesh.

    loose, one shared material     draws 7       objects 1100
    loose, a material each         draws 1100    objects 1100
    one MultiMesh                  draws 3       objects 3

Both counters are honest; they measure different things. `draws` is driven by the number of
DISTINCT MATERIALS in frame, because the renderer batches whatever shares one. `objects` is
per-instance submission and only instancing removes it. The jacks all wear the same two
finishes, so they were already batching -- banking them bought CPU submission work and no GPU
draw calls. Worth having on a standalone headset, where the CPU is as likely to be the wall,
but it is not the same win as the console's.

This also explains the console results in hindsight: what paid there was replacing per-colour
`Materials.led()` instances with one unshaded bank, i.e. collapsing MATERIALS, not objects.
And it says where the remaining draw calls are -- every `Label3D` carries its own glyph
texture, so 517 labels is close to 517 unbatchable draw calls.

**The timeline's items are banked, and scrolling no longer rebuilds the surface.** Two things in
one because they are the same code path. Draw calls 1,757 -> 727 at 90 tracks wide -- the
largest single step of the whole effort, and it is the MATERIAL collapse doing it rather than
the object collapse: every item block and lane chip carried its own track colour, so each was
its own material and its own unbatchable call.

The scroll fix is the one worth keeping for its own sake. `mark_dirty()` on a view change meant
a full rebuild per frame for the length of a drag; the split that fixes it is between what the
window decides (items, ruler numbers) and what the project decides (lanes, labels, flags). The
items bank is sized to every item in the project and drawn down with `show_first(n)`, because
capacity is a fact about the project and visibility is a fact about the window.

**A per-instance colour is linear and `albedo_color` is sRGB**, which made the blocks come back
pale and flat. No counter would ever have said so -- it was an A/B screenshot, again. That is
twice now that a draw-call win has quietly changed how something looks, so the A/B is not
optional on this kind of work.

I also nearly shipped a regression test that did not test anything: reverting the scroll fix
left it green, because `mark_dirty()` only sets a flag and the test never ran the frame that
acts on it. The mutation check is what found that, not the test passing.

**A rack unit could only reach a plugin's first eight parameters**, and said nothing about the
rest. The class doc had claimed a page control since it was written; there was never one. Same
silent failure the console's BankSelector exists to prevent -- gear that looks complete for a
simpler thing than the one actually loaded -- so it now works the same way, down to deferring
a page change made while a knob is held.

**It was invisible because the stand-in made it invisible.** Every FX in the offline project
had exactly four parameters, so the overflow case never arose in the only session anyone can
open without Reaper running. A real ReaEQ is four bands of four; a real ReaComp is a dozen and
more. The stand-in now has realistic counts. This is the SECOND time the stand-in has designed
a problem out of existence by being tidier than reality -- the first was folder structure --
which makes it a pattern rather than an accident: **the stand-in has to be at least as awkward
as the thing it stands in for.**

**`verify.sh` now times out.** Its own comment already described the hang -- a parse error in
run_tests.gd leaves the scene with no script, so nothing calls quit() and the run sits forever
looking like a slow suite -- but nothing bounded it. I lost two stretches to exactly that
today, both times assuming the suite had got slow. It is under a second; sixty is the limit,
and on a timeout it says what the cause almost certainly is.

**The reels turned at a flat 2.4 rad/s and both at the same one.** The class header had claimed
a rate "proportional to playback" since the deck was written -- second doc-ahead-of-code gap in
two ticks, after the rack's page control. Now derived: tape crosses the head at one speed, so a
reel's angular rate is that speed over the radius it is paying out at, and the takeup therefore
starts fast and slows all song while the supply does the reverse. That difference IS the thing
you read peripherally; two reels on one rate are two wheels on an axle.

Driving it from position rather than from `playing` is what makes a scrub and a rewind work, and
it costs nothing: the position is the only number that cannot disagree with the DAW. A stop is
the position stopping.

**The speed has to be smoothed, and not for looks.** Position arrives over the wire at the
link's rate, not the frame rate, so at 60fps most frames see the same number as the one before
and read as a dead stop. Unsmoothed the reels stutter to a halt twenty times a second, which
looks like a fault -- and a peripheral display that looks broken is worse than an absent one.
The test for this asserts on the SPREAD of per-frame rotation under a deliberately polled
position, because that is what an eye picks up and what a raw reading destroys.

**And the screenshot found two things no test could.** The left reel was blown to flat white --
`brushed_metal` at 0.34 roughness is right for a fader cap, which is small and angled, and wrong
for a 17cm disc angled into a practical, which puts the whole face near the mirror angle at
once. That is the failure `master_plate` already documents, at a scale that hid a whole feature.
A reel flange has a real reason to be blasted rather than brushed, so it now has its own
material. And with the glare gone it was clear the TAPE PACK had never been visible either: at
0.21 albedo, in the recess the flange shadows, the windows read as holes with nothing behind
them. Lightened, and the supply/takeup asymmetry the pack exists to show is legible for the
first time since it was built.

Third tick running where an A/B screenshot caught something every counter and every test was
happy with. It is not a nice-to-have on this project; it is the only instrument that measures
the thing the project is actually for.

**Swept every doc comment for claims the code does not honour**, because two ticks running had
found one by accident and twice is a pattern. 312 doc lines make a falsifiable claim; the sweep
narrowed to the absolute ones -- always, never, cannot, must -- and found a third:

`_follow()`, the timeline's auto-page, still called `mark_dirty()`. The manual scroll path was
fixed last tick and has a regression test; this is the SAME scroll arriving by itself, and it
is the worse of the two. A drag is something a person is doing on purpose and watching. This
fires unattended, once per window, for the whole of a rolling take, tearing down and recreating
every lane label while the transport runs. **Fixing one caller and leaving the other is how a
bug survives its own fix** -- and the test that was written for the drag could not see it,
because it tested the caller rather than the rule.

It only bites when zoomed in: the timeline opens showing the whole project, and a playhead
cannot run off a window that contains everything. That is why it lasted.

**Three invariants are now enforced on the source instead of asserted in a header.**
presentation.gd says "A surface... must never ask which mode it is in"; surface.gd says the
same for who is looking and for which process is the host. All three were still true. None was
checked -- and an invariant that holds today and is guarded by a comment is one reasonable-
looking `if` away from not holding, written by someone not editing the file the rule lives in.
There is now a scan over every .gd under hardware/ for the six ways out (`Presentation.`,
`Medium.`, `XRServer`, `Session.`, `is_authority`, `multiplayer.`), which prints the offending
file and line. It carries its own self-check: it is pointed at core/presentation, the layer that
IS allowed to know, and must light up there -- a scan that cannot fail is decoration.

The files come from DirAccess rather than a list, because a list is something a new file gets
left out of, and a file left out is exempt from every rule without anyone deciding that.

The general lesson, now three for three: **prose makes claims and only the suite holds anyone
to them.** Worth re-running the sweep whenever a header gets written.

**The room was one wall, and the stated reason for that did not apply to this renderer.**
`_build_room` said a fully enclosed room "makes the desk harder to read in a screenshot, because
every light then bounces into the lens". True with global illumination; this environment is
AMBIENT_SOURCE_COLOR with no SDFGI, no VoxelGI and no SSIL, so ambient is a flat constant and
walls bounce nothing. Three walls now, and the wide shot goes from gear parked in front of a
flat to a corner you are standing in. Measured rather than assumed: 2 draw calls, 2 objects,
0.01ms. The ceiling stays off and THAT reason does survive -- the key is a DirectionalLight3D
with shadows on, so a ceiling does not soften the room, it switches the key off.

Fourth doc-vs-code finding in three ticks, and a new shape: not a missing mechanism this time
but a REASON that was sound somewhere else. Worth checking a justification against this build,
not just against general graphics knowledge.

**The budget tool was measuring the monitor.** Every pose came back at exactly 8.33ms -- the
same number whether the camera faced ninety channel strips or a blank wall, and exactly 1/120s.
That is vsync: the engine sleeps to the refresh and reports the presentation interval. A
measuring instrument that returns the same answer regardless of what it is pointed at is not
conservative, it is broken, and it is worse than having none because its numbers look plausible
enough to write down. `tools/shot.sh` already killed vsync through override.cfg for its own
reasons; the budget wanted it more and never did it. With it off the poses separate again and
land at 1.00ms / 1.37ms worst, consistent with the figures already recorded here -- so the
history was sound and today's run was the anomaly. The suspicious part was never the value, it
was that three different poses agreed to the second decimal.

**A part-filled rack bay was a hole you could see the far wall through.** The frame is built
to the bay's full capacity, because that is what makes two bays line up, and six plugins in a
twelve-U bay left six rows with nothing in them. Blanking panels now, which is what a real rack
has in them and the only honest way to draw the gap -- banked, because every blank is the same
object in a different place.

Same failure family as the bank selector and the rack's page control: the gear misrepresenting
the project in the direction of looking simpler than it is. That is three instances now, and
the tell is always the same -- something absent with nothing saying it is absent.

Also the fifth doc-vs-code gap, and the most embarrassing kind: the class header said "A rack
fills bottom-up" while an inline comment eleven lines below said "Filled from the top down".
**Two comments in one file contradicting each other, with the code agreeing with the lower
one.**

**Two things about the blanks' finish are worth keeping.** The first attempt reused the chassis
albedo with a rougher finish: dimmer in the inspector, BRIGHTER on screen, because roughness
spreads the practicals across the whole panel instead of into one highlight. The second halved
the albedo and changed almost nothing visible -- at which point it stopped being obvious that
albedo was the lever at all, so it was pushed to near-black as a deliberate overshoot to prove
it was. It is now a sixth of chassis, which looks absurd written down and is right on screen,
because the thing a blank is compared against is a faceplate that is mostly knobs, lettering
and the shadows between them.

**And the test caught itself lying.** The first version asserted counts and rows and carried a
comment claiming it would catch blanks placed in the wrong rows. Mutation said otherwise:
reversing the row range, so the blanks cover the gear and the hole stays at the bottom, left
every check green. Same disease as the four found in the source this week -- prose asserting
what the thing below it does not do -- this time in the suite that exists to catch it. Now
asserts WHERE: every blank below the lowest unit.

**The timeline and the patchbay were showing a bank and calling it the project.** Over a real
Reaper link the cache holds a window of tracks -- 64 of 90 -- and both surfaces drew whatever
was in it with nothing saying so. The console has had a bank control since it was written,
which is exactly why this lasted: a desk captioned "17-64 OF 90" standing beside an uncaptioned
timeline and an uncaptioned patchbay makes the other two look right.

Fourth and fifth instance of the same pattern. The phrase lives on MixState now, not in three
surfaces, because three things saying the same fact in three wordings is three facts to anyone
reading the room. The test is written over a LIST of surfaces so a fourth one is held to the
rule the day it is added, rather than joining the two that quietly were not.

**Then the screenshot caught the caption lying, and the test did not.** The first version keyed
off `has_more_banks()`, which asks whether the PROJECT is bigger than a bank -- a different
question from whether this cache is truncated, and not always the same answer. The offline
stand-in at 90 tracks caches all 90 while bank_size is still 64, so the caption read "TRACKS
1-64 OF 90" over ninety drawn lanes. The test passed, because it only checked that "90"
appeared somewhere, and it did -- in the wrong sentence.

A caption that disagrees with the thing it is captioning is worse than no caption, since being
believed about what is missing is its entire job. It is measured from the keys actually in the
cache now, and the test asserts the sentence rather than the number.

**A test that looks for a substring is a test that will accept a lie containing it.** That is
the second time this week a green check was hiding the thing it named -- the rack blanks were
the first -- and both times mutation or a screenshot found it, never the suite on its own.

**Audited the suite for the weak-assertion shape** that had slipped twice, and the worst
instance was in the test written while diagnosing it. The commit for that tick claimed "the
assertion is on the sentence rather than on the number" -- true of the direct checks, false of
the surface checks, which still swept every label for "90" and counted a hit as proof. The
sentence that broke it, "TRACKS 1-64 OF 90" over ninety lanes, contains "90" in passing.

**Then the mutation found two more layers, neither visible by reading.**

*The expectation called the function under test.* The surface checks compared each label
against `DAW.state.bank_caption()`, so a mutation that changed the caption changed the
expectation too and both sides moved together. It passed. An expectation has to be written
independently or it is not an expectation -- it is a restatement.

*The fixture could not tell the formulas apart.* The cache held exactly 64 of a 64 bank, where
"count what is held" and "assume a full bank" return the same characters. The fixture holds 40
of 64 now, which is also the more honest shape: a bank still filling, or a backend that capped
lower than it was asked.

**And the console was still computing its own range from bank_size** while the other two read
what is held -- the exact drift the shared `bank_caption()` was introduced to prevent, left
behind in the surface that had been right the longest. BankSelector takes `shown_count` now. A
caption contradicted by the faders in front of it is worth less than none.

The through-line for the week: **a green check is evidence about the check, not about the
code.** Three of this week's real bugs were sitting behind passing tests, and in every case it
was a mutation or a screenshot that found them.

### Still open

**Lettering is culled once it is too small to read**, which was the largest remaining cost.
An ablation -- hide every Label3D, re-read the counters -- put the 517 labels at 735 of 2,492
draw calls and 0.70ms of a 1.82ms frame: 30% of the drawing, 38% of the time, for text.

The trade turned out to be free, which is why it is worth recording. Label cost rises as you
stand back and more of the room enters frame; label VALUE falls as you stand back, and falls
faster -- a console strip name is already under five pixels of cap height at 1.2m. So culling
lettering below three pixels of cap removes the cost exactly where the text had stopped saying
anything. Measured at 1.82 -> 1.38ms at 90 tracks wide, with nothing visibly different at a
working distance (checked at 0.8m and 1.8m, not assumed).

Two things worth keeping from how this was done. The ABLATION came first: hiding the labels
and re-measuring is what turned "labels are probably the problem" into a number, and it cost
one flag. And the test walks the whole built studio asserting every label has a range, rather
than testing the helper -- a helper that is correct and uncalled is the actual failure mode
here. Verified by deleting one call site and watching it fail by name.
- Guest write round-tripping of provisional values; participant roster on a guest.
- Draw calls are at 727 at 90 tracks wide, from 7,600. This is probably the point to stop and
  put the effort back into the gear itself; the remaining items are small and the measurement
  tooling is now good enough to catch a regression if one lands.

### Tick L -- four plugs in one hole

Swung back to the gear after three audit ticks and photographed the console close up. The desk
itself reads well. The bay above it did not: four cables fanned down to what turned out to be
a single input jack. One jack takes one plug, and the bay had been drawing four in one bore
since the first cable landed.

Worth noting HOW it was found. Not by the suite -- 838 checks and none of them had ever asked
where a cable ENDS, only that the right number of cables existed. Not by reading the code
either; `_draw_cables` reads perfectly sensibly, and `patch_cable.gd`'s own class note cites
"which return has four things landing on it" as a thing the bay is good at showing. It was
found by cropping a screenshot to 260% and looking at it. That is now three bugs this week
whose only detector was a photograph.

The fix is a **mult** -- real patchbay hardware, a strip of jacks wired in parallel, hung
under the bay on two straps. Sources plug into it, one trunk cable leaves for the return. It
is deliberately the dullest object on the bridge. Multed returns pack left to right in a row
rather than hanging under their own column, which would collide the moment two neighbouring
returns were both multed; a mult is a bussed strip and nothing requires it to live beneath the
jack it feeds. The trunk cable says that.

Two placement mistakes, both caught by the second and third screenshots rather than reasoned
out: the first mult sat halfway through the meter-bridge crossbar, and the first version had no
straps, so it floated under the bay reading as a UI panel that happened to be in the scene.

The test is the part worth keeping. `_test_one_jack_takes_one_plug` does not know what a mult
is. It collects both ends of every cable in the bay and asserts no two are closer than a 1/4"
sleeve is wide, then separately asserts the fan-in was not simply dropped to achieve that.
Written that way it would catch any future way of putting two plugs in one hole, including
ones nobody has thought of. Mutation-checked twice: routing the sources straight at the input
again fails it at "0.0mm apart", and never building a mult fails it by name.

846 checks, 0 failed.

### Tick M -- the last 180 loose objects

Knobs and fader caps, banked. The prediction made when this went on the backlog -- "expect an
`objects` win and little on `draws`" -- was right, and worth recording because it was made
from the batching table rather than from a measurement:

| 90 tracks, wide | draws | objects | frame ms |
|---|---|---|---|
| before | 820 | 2,293 | 1.28 |
| after | 830 | **1,225** | **0.95** |

`draws` went UP by ten. Two new banks of a two-surface part add materials to the frame, and
the 180 objects they replaced already shared materials with each other, so there was no
`draws` win available. Objects nearly halved; the frame dropped a quarter. The console's loose
mesh count went 222 -> 42 at 90 tracks.

The argument that had kept these loose was in `mesh_bank.gd`'s own class note: a bank is
filled once, and these move. That was wrong -- a transform is per-instance, and `move_slot`
has existed since the bank was written, with a doc comment that says "a fader cap slides and a
knob turns". The note has been corrected. A stale justification in a docstring is the same
failure as a stale doc elsewhere in this backlog, and it is worse here because it reads as a
decision rather than as a description.

One thing the design had to concede: the fader cap stays a node even when banked, an empty
one, because the slide emitter parents to it so the sound comes from where the cap is. A bank
slot is a row in a buffer with nowhere to hang a speaker.

Two instruments, because neither alone is enough. A **pixel diff** of the console before
against after: identical apart from a tape reel that had turned between captures, which is
what proves banked and loose land at the same place and the same angle -- the test cannot show
that, because it compares the banked slot against the loose node through the same chain. And
**`_test_a_banked_control_still_moves`**, which mounts one banked and one loose control under
a tilted, offset, rotated parent -- a test at the origin agrees with every wrong composition
-- and then separately asserts the cap crossed its full 100mm and the knob its full 270
degrees, because two frozen controls agree with each other perfectly. Mutation-checked by
deleting both `move_slot` calls: seven checks fail, and informatively ("9.00mm", "50.80mm",
"100.40mm" -- the cap frozen at build position).

Rack knobs left loose on purpose. They are created lazily as parameters arrive and as pages
change, i.e. after the surface has committed, so banking them means sizing for the worst case
and hiding unused slots. The rack's mesh count does not grow with the session, so this buys
little; recorded as a decision rather than an oversight.

858 checks, 0 failed.

### Tick N -- the rack, which had never been looked at closely

The surface carrying the most geometry in the room (65,200 triangles, more than everything
else combined) and the one I had photographed least. Shot it square on at 1200x1400.

**A finding that measurement killed.** My first reaction to the photograph was that the rack
is far too dark -- 48 knobs modelled and barely legible, off at the side away from the key
light. That is a plausible story and it is wrong: mean luminance of a rack faceplate is 47
against the console panel's 54, a 13% difference. The rack looked dark because it was
photographed alone against a dark wall, and because the camera was further from it. Dropped,
and recorded here because the next person to look at that photograph will have the same
reaction. One `magick -format %[fx:mean]` settled it in a second.

**The real finding, at 300%.** The faceplate layout was wrong in a way that is invisible at
rack-wide zoom. The knob row sat at a quarter of the plate height below centre, which put 35mm
of empty metal between the title and the knobs and left 3mm of clearance under the captions.
Dead space in the MIDDLE of a panel is the one place real hardware never leaves it, and the
labels were pressed against the lower edge. Raised the row so the knob-and-caption group is
centred in the area the header leaves -- a bottom margin instead of a hole -- and added the
silkscreened rule under the title that every processor with a title bar has. Without the rule
the header and the controls are two things floating on the same slab.

The test is careful about what it claims. It does NOT pin where the row looks best; that was
settled by a photograph, as it has to be. It pins the BRACKET the row has to stay inside,
which is geometry rather than taste: raise it and the knobs grow through the rule, drop it and
the captions walk off the plate. Mutation-checked at both ends -- +0.010 fails 44 checks on
"keeps knob under the rule", -0.030 fails 44 on "keeps caption on the plate (-4.7mm from the
edge)". The old value would have passed, which is correct: it was ugly, not broken, and a test
that failed it would be a test asserting my taste.

Knobs are now named so a failure says `Knob3` rather than `@StaticBody3D@4327`. Third time
this week an unnamed node made a failure message useless.

971 checks, 0 failed.

### Tick O -- the deck had two reels and nothing between them

Shot the tape machine close up for the first time. The reels are good -- the packs already
shrink and grow at the right rate and the two turn at their own speeds. But there was no tape.
Two wheels on a slab, with a floating counter and three small buttons. Everything that makes a
deck legible as a deck lives in the gap between the reels, and the gap was empty.

Built the path: the ribbon, two guides, a three-head block, a capstan and a pinch roller. The
point of the ribbon is not that it is there -- it is that it comes off the pack on a TANGENT,
so the angle it leaves at swings round as the reel empties. Measured, that is 33 degrees of
swing from a full supply to an empty one. A run drawn to a fixed point on the flange would
look identical in a still photograph and dead in motion.

Three things the photographs corrected, none of which I would have got from the code:

1. **The guides were inside the reels.** At the first PATH_Y the guide posts sat 2mm inside
   the flange circle, so both runs vanished into the reels and read as sticks resting on them.
   Moved the path down and the guides in; the buttons and the tempo readout moved down with
   it.
2. **The run must stop at the FLANGE RIM, not at the pack.** The pack is drawn behind the
   flange and is only visible through the windows, so a run drawn all the way to its tangent
   point ends in the middle of a solid disc. Stopping at the rim reads as tape going in
   behind it, and the angle still comes from the pack, which is the part that has to stay
   true.
3. **The tape was the pack's colour and came back looking like a wooden batten.** A pack is
   lit through a window at the bottom of a recess and needs lifting; a run is out in the open
   and does not. Oxide is nearly black and on the path it should look it.

**The mutation that mattered.** The static geometry tests -- tangent on the circle, square to
the line, run stops on the rim, angle swings one way -- all passed while the takeup reel used
the WRONG tangent. They only ever exercised the supply. Flipping that sign is the single most
likely mistake in this feature and the suite was blind to it. Fixed by asserting the thing the
sign actually decides: with equal packs the two reels are mirror images, so the tape must
leave one and arrive at the other at mirrored points. The wrong sign now fails by 20.3mm of
height and 11.3mm of offset.

Also worth recording: the first version of the swing check failed, and the deck was right. The
run crosses due-west partway through the reel, so the raw angles run 163, 173, 180, -174,
which a plain subtraction reads as the tape snapping back through half a turn. Stepped with
`angle_difference` instead. Second time this week a test was wrong about the thing it was
measuring rather than about the code.

999 checks, 0 failed.

### Tick P -- the wide shot, which is the only one that shows what is missing

Four close reviews in a row, then the framing none of them could substitute for: the whole
room at 2.6m. Two findings, and both are of a kind a close-up cannot produce, because both are
about what is NOT in the frame when you stand close.

**A regression I shipped last tick.** There was a small object floating against the right-hand
wall, a metre from anything. It is the tape deck's grab tab. A tab is placed from its
surface's content box ONCE, when the surface says it has rebuilt -- and the tape runs I added
in tick O are unit-length boxes that a transform shrinks to size, with the two outer ones left
unlaid until the first frame. `rebuilt` fires before that frame. So the handle measured a deck
with two one-metre planks lying across it and clipped itself to the edge of that, 413mm out.
Fixed by laying the runs at build time. It had been there for one tick, through a full suite
run, a close-up of the deck and a mutation campaign, because it is outside every close-up.

The test for it is the general statement rather than the specific bug: every grab tab in the
built studio must sit just outside its own surface's content box and at the middle of it. It
does not know what a tape run is. Getting it to BITE took a second try, and the first failure
is the more useful half: the test built the studio and measured without stepping a frame, so
it compared the handle against the same wrong box the handle had been placed from, and passed
the bug cleanly. A test that reads its expectation from the same stale state as the code is
the same mistake as an expectation that calls the function under test. Stepping one frame
first is what makes it an expectation. Mutation now fails at "413.0mm out".

**The timeline was hanging in the air.** The rack has a plinth, the deck a trolley, the bay a
bridge, the console its own carcass -- and then a metre of lit panel at head height with
nothing holding it. Invisible in a close-up of the timeline, where you are looking at the
lanes. Obvious the moment the room is in frame: it is the one object in the room that is
software. Given two legs, two feet and a crossbar, deliberately the same vocabulary as the
patchbay bridge rather than a new idea -- a room furnished out of three kinds of part looks
like a room, and one furnished out of six looks like a kit.

No test for the stand, on purpose. Its correctness is "does it read as supported", which only
a photograph answers; inventing an assertion for it would be asserting my taste, the same trap
noted in tick N. What IS pinned is the timeline's height and the stand's height as one
constant pair, so moving the panel cannot leave the stand behind.

1020 checks, 0 failed.

## Tick Q -- the room had no wiring in it

**The patchbay was wired to nothing.** The bay draws a cable for every send in the session, and
for sixteen ticks those were the only cables in the room. The console, the rack and the deck
stood in the same room as the bay and had no physical relationship to it: the bay's jacks were
labelled with the names of machines they were visibly not attached to. A patchbay wired to
nothing is a prop of a patchbay.

So, three looms -- console, rack and deck, each to its own landing across the back of the bay.
They are the normalling: the permanent run that makes a jack mean a machine, with the per-send
patches then laid over the top. That is a narrower claim than the patch cables make, and the
code says so: nothing in the DAW state decides where a loom goes, and the only thing a loom
asserts is that this machine is wired to the bay, which is true of every machine here.

**The sweep is now shared.** A loom and a patch cable disagree about everything except the hard
part -- the parallel-transport frame -- so that moved to `hardware/cable_sweep.gd` with the
commentary, and `PatchCable._build_jacket` is eight lines calling it.

**Three measurements, in the order they were taken.** The first render showed three black
vertical lines and nothing else, which is what a loom looks like when the route is wrong, the
colour is wrong and the shape is wrong, all at once.

  * A headless probe of the spines, because the photograph cannot read a number. It said the
    floor runs dipped 81mm THROUGH the floor and climbed 108mm above the gland they were
    arriving at. Neither was visible from any angle I had shot.
  * An ablation on the parameterisation with everything else held still: uniform Catmull-Rom
    81mm / 108mm, centripetal 39mm / 29mm. So centripetal is worth having and is half a fix,
    and the comment in `cable_sweep.gd` now says that instead of the "under a millimetre" I had
    written from memory before measuring. **The first draft of that comment was wrong and the
    test caught it**, which is the right way round.
  * The remaining 39mm is not a spline artefact. It is where a slack cable genuinely wants to
    go, and what stops it is the floor -- so `CableSweep.rest_on` lays a spine on a level it
    cannot pass through, with a C1 parabola at the contact so the touchdown is a curve rather
    than the corner a clamp would leave.

**The console's loom is not a floor run.** It stands directly under the bay. A trunk route down
to the floor and back up would be a longer cable than the one that fits, so it hangs, and its
via is a clearance point rather than a floor point -- which is the whole reason the via became
one waypoint with two readings instead of two fields.

**What the test caught that I had already "fixed".** All three looms arrived three centimetres
INSIDE the meter-bridge crossbar, because the bay's bottom edge is exactly where that bar runs
and the entry was 24mm up from the bottom edge. Raising it to 68mm fixed the rack and the deck.
The console still clipped: it was dropping first and clearing the bar afterwards, and the curve
sagged through the top of the bar fifteen millimetres past the gland. Its via now takes it BACK
before it goes down. Both of those are corrections to code I had looked at a render of and
called done.

Four mutations, four catches, each by the assertion that claims to own it: uniform knots ->
"arrives at the bay instead of over it (110.4mm above)"; no floor contact -> "does not go
through the floor (39.7mm under)"; entry back at the bottom edge -> three looms inside the
bridge; via ignored -> the console through the floor.

The bridge is now `BRIDGE_POS` / `BRIDGE_SIZE` so the test and the furniture read the same
numbers, and moving the bar moves the test with it.

Not done, deliberately: cable flags. Real looms carry a label at each end, and at two metres in
a dark room it would be four unreadable pixels and a Label3D per loom.

1053 checks, 0 failed.

## Tick R -- the room was lit by light sources that do not exist

Straight on from tick Q: the looms were in, and the rack's run was invisible because that
corner of the room had no light reaching it.

**Measured first, because the last time I called something "too dark" I was wrong.** In tick N
the rack's faceplate read 46.9 against the console's 54.1 in a close-up -- 13%, no case to
answer, hypothesis dropped. This is a different measurement on the wide shot and it is not
close: rack face 13.8 against console 22.1, and the floor at the rack's foot 9.1 against 29.5
on the lit side. A factor of two to three.

**And then the actual defect, which was not the darkness.** The room was lit by two OmniLights
floating in mid-air with no fixture anywhere near them. That is the same shape as the patchbay
wired to nothing, one layer up: the light is real, the thing it comes out of does not exist,
and nothing says so. `PRACTICALS` is now one table read twice -- by the environment to make
the lights and by the furniture to make the stands -- and the stands are furniture, so an AR
participant keeps the light on the virtual gear without a virtual lamp appearing in his room.

Floor lamps and not pendants, and that is forced rather than chosen: this room has three walls
and no ceiling, so a hanging fixture would hang from open sky above the wall line.

**Three passes, each one a measurement correcting the one before.**

  1. Stands at the old light positions. Rack face 13.8 -> 21.4, floor at its foot 9.1 -> 19.6,
     everything up 55-115%. But the RATIO rack-to-console went 0.63 -> 0.59: the gap I set out
     to close had not closed, the whole picture had simply got brighter. Worth saying plainly,
     because "everything improved" was true and was not the thing I was after.
  2. The reason: the old positions were abstract fill, chosen when nothing was drawn there.
     Two of the three lamps stood over the empty half of the room, and the third was nearly
     edge-on to the rack's faceplate -- the rack is turned 38 degrees, so a lamp to its left
     rakes its side. Moved to where someone would actually stand a lamp, including one beside
     the desk on the rack's face normal: rack face 28.6, ratio 0.74.
  3. That lit the empty room too: bare floor 37.0 against the console's 38.7. A floor lamp is
     a pool, not a sun, so `omni_range` came down from 6.5m to 3.6m and ambient from 0.58 to
     0.46. Final: rack face 24.3, floor at its foot 12.9, console 35.3, bare floor 32.5.

Against the start: rack face +76%, floor at its foot +41%, console +60%, and the gear is no
longer the dimmest thing in a frame of its own room.

The test pins the pairing, not the brightness. Brightness is taste and belongs in a photograph;
"a light with no fixture" is a fact. Three mutations, three catches: a fourth practical with no
stand -> "3 of 4"; a shade hung 300mm above its lamp -> three failures; a stand 250mm to one
side of its lamp -> three failures. The second one matters because a count check alone would
pass a fixture that renders in the wrong place.

1070 checks, 0 failed.

## Tick S -- the budget figure in the docs was five ticks stale

Two ticks of scenery went in without re-measuring anything, and the architecture doc still
quoted 830 draws / 1,225 objects from tick K as if it were current. So: measure.

**90 tracks wide, now: 964 draws, 1,359 objects, 0.99ms.** Against 830/1,225 that looks like a
sixteen percent regression and it is not one -- the baseline was simply old. Five ticks of
additions sit between them (the mult, the rack rule, the tape path, the timeline stand, then
the looms and lamps), and adding things costs something.

**The useful number needed a real baseline, so I built one.** `git worktree` at the pre-tick-Q
commit, same tool, same two poses: 899 draws / 1,294 objects before, 964 / 1,359 after. Three
looms and three lamp stands for +65 draws and +65 objects, with frame time flat (1.03 -> 0.99,
which is noise). That is a number I can defend; "+134 against a figure from last week" is not.

**Twelve of the sixty-five were a mistake.** Every mesh on a loom has `cast_shadow` off except
the strain-relief collars, which I had simply not set -- so the only part of a cable in the
shadow map was the 30mm collar at each end, six of them, two passes each. Predicted from the
counter before changing anything, then confirmed: 976 -> 964.

**One thing measured and then NOT done.** The loom cores are swept at eight segments per span;
dropping to four saves 3,072 primitives at 90 tracks, which is 3.6% of the fitted pose. Left at
eight. The saving is small, the cost is faceting on the one curve anybody looks at -- where the
cable flattens into the floor -- and frame time did not move, so primitives are not what is
binding here. Writing down that the ablation was run and rejected is the point; otherwise it
gets re-run in three ticks' time.

The new test pins the SHAPE, not the count. A draw count belongs in a benchmark, not a unit
test. What a unit test can say is that the room's dressing costs the same at 64 tracks as at
13 -- three looms because three machines, not one per send. Two mutations: a loom count that
scales with the session -> "20 vs 29 meshes"; the collars casting again -> "18 casters, 12
lamp parts".

1073 checks, 0 failed.

## Plugin tablets — follow-ups (2026-10-08)
- Mark a rack unit whose plugin is out on a tablet (dimmed faceplate, or a "ON TABLET" tag)?
- Patchbay: draw sidechain (key) sends as a distinct cable colour/style.
- Offline stand-in shows preset "—" until a preset is stepped; the built-in engine's wet/dry is state-only (not heard).
- Tablets stand on the floor; placing one on a table/desk top was not done — wanted?
- Tested against Neural DSP (Gojira X, Tim Henson X, Mantra) in the rig: tools/probe/plugin_tablet_live.tscn,
  85 checks. Still open from that:
  - The RACK still only reaches a plugin's first 32 parameters, and rack knobs don't follow values changed
    in Reaper (no signal for param values; the tablet polls its visible knobs, the rack doesn't).
  - On/off parameters ("Gate Active", "REV Active") are knobs on the tablet; switches would read better.
  - 140-210 controls is 15-30 pages; a section jump (scroll the page label through section names) would help.
  - The plugin's own presets step blind: the plugin doesn't tell Reaper the preset's name.
  - The first Wine plugin load can outlast the bridge's 4 s reply timeout (it still loads).
- The tablet's UI face (the plugin's own window, read off X and clicked through XSendEvent) is PARKED:
  built and tested but switched off (`PluginTablet.window_face = false`; `--tablet T:F:ui` turns it on for
  a run) until the window can be kept off the desktop. Best idea so far: the helper moves the plugin's
  window to a Hyprland special workspace (`hyprctl dispatch movetoworkspacesilent special:...`, matched by
  title) — Reaper doesn't save workspaces, so the project's window positions are untouched. Open questions:
  - With the user's own Reaper, the floating window also opens on the desktop wherever Reaper puts it
    (in the rig it is on workspace 10). Hide it — move it to a Hyprland special workspace, or offscreen
    and back on close — or leave it? Moving it risks Reaper saving an offscreen position into the project.
  - Left button, drag and wheel only: no right-click menus, no keyboard (a plugin's text fields can't
    be typed into), and its popup menus open as separate windows that the tablet doesn't show.
  - Two copies of the same plugin on one track have the same window title; the tablet shows the first.
  - The helper is built on first use with `cc` into user://bin; without a compiler or X11 headers the UI
    button just doesn't appear.
- Webcam AR (asked 2026-10-08: "could we somehow simulate what this would look like in AR using my
  webcam?"). Plan: a `--webcam-ar` desktop launch that shows the webcam (`CameraServer`/`CameraFeed`, V4L2,
  /dev/video0) behind the scene and drops the venue's shell the way `XRBootstrap`'s passthrough does, so
  only the gear, the lattice and the zones float over the room. Fixed camera, not head-tracked; the
  virtual camera is lined up with the webcam once by hand. DROPPED for now (2026-10-09: "drop both of
  those for now"); not to be built unless asked again.

## Lattice cells bobbing in zero-g on the station

The station follow-up asked for the matrix "in true zero-g (its cells bobbing slowly)". The
cells belong to the lattice activity, which every venue shares, so a venue cannot move them
without a hook in the activity (e.g. a per-venue `drift` the lattice reads). Decide whether
activities should take a look from the venue they stand in before building it. DROPPED for now
(2026-10-09: "drop both of those for now"); not to be built unless asked again.
