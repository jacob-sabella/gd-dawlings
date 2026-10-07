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
