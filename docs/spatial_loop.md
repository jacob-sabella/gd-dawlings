# Spatial instruments loop

Goal: the four foundations under the kept spatial ideas (docs/spatial_ideas.md), each proved by
one idea a player can pick up and play. A: the song's key and chords (`Harmony`,
`core/music/harmony.gd`), asked by any instrument for "what may I play now". B: output jacks
(`Jack`, `Jacks`, `core/music/`), a plug on any instrument that sends what it plays to a track
or into a bandmate's instrument. C: hand gestures (`HandPose`, `core/input/hand_pose.gd`, and
new `Interactor` readings), finger pinches, palm up and tilt from hand tracking, with the same
readings from a controller and from the keyboard. D: instruments as items, pitched by the chord
(`InstrumentItem.note_at`). One slice per iteration. Every slice: `godot --headless --path .
--editor --quit` after a new class_name, the suite (`timeout 900 godot --headless --path .
tests/tests.tscn`) at 0 failed, `flock ~/.cache/dawlings/shared.lock tools/session_probe.sh` at 0
failed on both sides when it crosses the network, and a shot of what changed (tools/shot.sh).

## Decisions

- **The key and chords are written in marker names.** A marker's name may end in brackets:
  `Intro [A minor: Am F C G]`. Inside is a key (a root, RigRoll.KEY_NAMES or its other spelling,
  and a mode, RigRoll.MODES, `m` for minor, major when none), then optionally a colon and one
  chord a bar, cycling, counted from the bar the marker falls in (`-` holds the chord before it
  another bar). No chords means the key's own tonic triad all along. The harmony holds until the
  next bracketed marker; plain section markers do not end it. A marker that is only brackets
  changes the harmony and names no section. Why markers: they are already song state. They
  replicate, undo, save through Reaper and .dawproject, and the 2D ruler edits them (double-
  click to rename). Using them adds no DAW verb, so nothing touches the three backends or the
  Lua bridge. One marker per time is why the harmony shares the section's marker rather than
  having its own: the stand-in's Intro is at 0.0, and so would the key be. Regions were the other
  candidate, but two at one start replace each other in the same way.
- **Every place that shows a marker's name as a section shows `Harmony.section_of(name)`.** That
  is the name without its brackets. The chalk board (ChalkVenue.board_from), the tape deck's
  section label (TapeDeck.section_at, which also skips a brackets-only marker, so the section
  before it goes on), its PREV/NEXT/MARK hover text, the 3D timeline's ruler flags and their
  widths (timeline_surface.gd), and the region page's ADD name (timeline_region_page.gd) all use
  it. PREV and NEXT still stop at a brackets-only marker: it is where the harmony changes, a
  place worth landing on. Their hover text then names its key (`A minor`), not an empty section.
  The 3D ruler writes the brackets' text as a smaller second line under a bracketed marker's
  flag, so the harmony is seen where the arrangement is. The 2D ruler (FlatHost) shows the whole
  name, because that is where it is typed.
- **The chord now is a function of song position, never a stream.** `Harmony.at(state, seconds)`
  reads the markers and counts bars with `MixState.bar_at`, so tempo and meter changes and a
  wrapping loop are right. Every machine gets the same answer from the replicated markers. Each
  played event takes ONE song position, when it is played, and that one position picks its
  pitch, is what it is recorded at, and is what it is sent with (`song`). The receiving machine
  pitches and records by that `song`, never by its own heard position or its arrival time, so
  the chord heard, sent and recorded agree across a bar line on every machine.
- **Voicing is a rule, not a guess.** `Harmony.voiced(h, centre, count)` places the chord's root
  at the one pitch of its pitch class in `centre - 6 .. centre + 5`. The other tones follow it
  upward in chord order (third, fifth, then the seventh in a four-note chord, else the octave)
  until there are `count` of them. Bells use centre 72 (C5) and fingertips 60 (C4). In Am the
  bells ring A4 C5 E5 A5. In F they ring F5 A5 C6 F6. They jump with the root, and that keeps
  each bell's job the same in every chord. The harp is `Harmony.tones(55, 8)`: the chord's
  first eight tones at or above G3.
- **No key is a state, not a guess.** Before the first bracket, and in a project with none,
  `Harmony.at` is `Harmony.NONE`: C major on C, `named` false. Chord instruments still play, and
  their label says NO KEY SET. The stand-in's Intro marker carries `DemoSong.HARMONY`
  (`A minor: Am F C G`), so the demo song plays in its own key from the first launch.
- **A player's keys have many instruments, held as a set.** Today `GuestMidi.keytar` is one bool
  with a setter that starts the synth. It becomes `GuestMidi.instruments`, a set of what is in
  reach: `&"keytar"`, `&"harp"`, `&"fingertips"`, `&"cable"`, `&"wheel"`. Each writer adds and
  removes only its own name (`reach(name, on)`). `keytar` stays as a read/write view of
  `&"keytar"` in the set, so KeytarItem, studio.gd and their tests are unchanged. The synth is
  started when the set goes from empty to one, and stopped when it empties. An instrument
  enters the set when it comes in reach, not when its first note plays, so a native helper
  starting up never eats a first note. `plays()` and `take_track()` answer while the set is not
  empty, so a recording is one take across the gaps between strums, not one item per strum. The
  take is named after what played in it (`harp`, `harp+fingertips`). `held` counts each pitch
  by source, so a harp A4 let go does not stop a fingertip A4 still held. session_panel.gd's
  two `keytar` reads (the keys box, "The armed track") read `has_instruments()`.
- **Notes say where they came from.** `Session.send_note` and `note_played` gain a `source`
  (StringName: the instrument's name, `&""` for plain keys). Presence routes a note by its
  source, not by Session.holds: `harp` notes from anyone to `ChordHarp.heard`, keyed by
  (peer, pitch), so a note_off always finds its note_on, and everything a peer left with is let
  go. The holds table is a different channel with no ordering against KEYS_CHANNEL, and a
  pluck holds the harp for less time than its string rings, so it cannot gate notes.
- **Notes leave through the two paths there are.** Pitched things you play with your hands
  (the harp, your fingertips, a cable into you) play the player's keys, `GuestMidi.note_on`.
  That is the fast path (about 4 ms on the native helper). The notes go to everyone, are heard
  from the instrument by others, and are recorded as a take by heard position. Things you shake
  or strike stay on `InstrumentItem`: heard at once on AudioPorts.MONITOR, sent as `item_hit`,
  recorded by HitRecorder. There is no new synth.
- **Drums keep channel 9 and their GM pitches; pitched items get channel 10.** Melodic items
  (the bells) record on `InstrumentItem.MELODIC_CHANNEL`, 10 (0-based). Tour's "any channel but
  9" (Measure._matches, channel -1) becomes "any channel but TourPart.ITEM_CHANNELS", [9, 10].
  Those are the hand percussion's and the pitched items' channels, mirrored there because Tour
  code knows nothing of core/items/, and a suite check keeps the two lists equal. So a bell rung
  during a brief neither passes nor spoils a keys part. The harp's and fingertips' notes are the
  player's keys (channel 0), and they do count as keys, as a MIDI keyboard's do.
- **A jack is a row in the room, not a send.** Patches are `room_state()["jacks"]`
  {source id: sink id}, asked with one room verb, `plug`, and predicted and rolled back the way
  the tablet's `patch` is. Sources are item ids, `harp`, and `keys:P` (player P's own keys, the
  fingertips' among them). Sinks are `track_N` (recorded onto track N as MIDI) and `player_P`
  (into player P's instrument). An unplugged source does exactly what it does today. It is not
  the patchbay's data (DAW sends: a cable there must be a send) and not the patch wall's
  (machine-local PipeWire). It reuses only their cable meshes (PatchCable, CableSweep).
- **A jack sends what its source is.** Pitched sources (the harp, `keys:P`, the bells) send
  NOTE_ON and NOTE_OFF of their own pitches, so bell1 into a bandmate plays its root. Only
  unpitched percussion sends TRIGGER, which the receiver turns into the next chord tone.
- **Gestures are readings, not events.** `HandPose` is static and pure over the 26 joint
  positions, so the suite can test it with synthetic hands. Interactor gains neutral virtuals
  beside `shake_point` and `twist`: `finger_pinches()` (a mask, index 1, middle 2, ring 4,
  little 8), `palm_up()` and `tilt()`. A bare hand answers from its tracker, a controller from
  its buttons and its basis, and the mouse from the fingertip keys and its wiggle. Instruments
  read only the readings. Hand poses never cross the wire; the notes they make do.
- **No gesture faces the head.** On Quest the runtime takes a pinch made with the palm toward the
  headset (the system and menu gesture), whatever the app wants. `HandPose.faces_head(joints,
  head)` is true when the palm's normal is within 60 degrees of the hand-to-head direction. Our
  gestures avoid it. Fingertip notes turn on and off with an open hand, palm up, no pinch, and
  play with the palm down or on its side, like air piano. Pinches read while the palm faces the
  head are ignored.
- **Every control has a hand, a controller and a desktop path.** The thumbstick
  (`primary`, read nowhere today) becomes nudge(): XRInteractor sends one notch per flick (past
  0.6, back under 0.3, repeating every 0.25 s while held) to what it hovers or holds, as the
  mouse wheel does. A bare hand has no stick, so anything that nudges also has buttons a finger
  can press. There are no double-clicks: ControlAffordance has no such gesture, and on an
  instrument two clicks are two notes.
- **New code goes in new files.** Most of it is under `core/music/`. Files with someone else's
  uncommitted edits get small additive edits only: `offline_backend.gd`'s Intro marker in slice
  1, new tests appended to `tests/run_tests.gd` with their calls appended to `_ready()`, and the
  one shelf count in slice 4 (`- 14` to `- 18`). Hands only, never feet. Every state is shown by
  text, shape or motion, never by colour alone.

### The review (22 points), checked against the code

Accepted, each fixed in the slice named: 1 (left Y is calibration: slice 7), 2 (holds cannot
gate harp notes: the source tag, slices 2 and 3), 3 (GuestMidi.instrument overwritten: the set,
slice 2), 4 (the shelf count: slice 4), 5 (brackets on the deck, ruler and region page: slice
1), 6 (SET at the next bar: slice 9), 7 (mouse tilt zeroed: slice 7), 8 (no thumbstick nudge, no
double-click: slice 3 and the decision above), 9 (item_hit without song: slice 4), 10 (two times
in one hit: slice 4), 11 (a jack note stamped at arrival: slice 6), 12 (no NOTE producers: slice
6), 13 (the socket under its own hand's ray: slice 5), 14 (desktop fingertips' focus, two key
readers, the glove: slice 8), 15 (Quest's palm pinch: the decision above, slice 8), 16 (poke
cannot strum: slice 3), 17 (slices too big: now nine), 18 (the harp's spot unchecked: slice 3),
19 (voicing and the hand's size undefined: the decision above, slice 7), 20 ("theirs" undefined:
slice 6), 21 (bells in Tour's keys lanes: the channel decision, slice 4).

Taken in part. 5: PREV and NEXT keep stopping at a brackets-only marker. A harmony change is a
place to land, and only their text changes. 22: latency cannot be measured by the headless
suite. Slice 4 bounds what the code adds (the sound starts in the same call as the hit), shows
the mixer path's reported latency beside the keys', and sets the rule that moves bells to a
MonitorSynth voice. 12: "your chord hand drives their harp" (#33 with #28) would retune a
bandmate's harp from your chord shape. That needs chord shapes, which are not in this loop.
What is built is the NOTE path a chord hand would use.

## Plan

1. [x] **Harmony, read wherever markers are shown.** `Harmony` (core/music/harmony.gd,
   RefCounted): `parse(name)` reads the brackets (or returns null). `at(state, seconds)` returns
   a value with `key_name`, `root`, `scale` (pitch classes), `chord` (pitch classes, root first),
   `chord_name`, `named`, the bar the chord began and `until` (seconds). It also has
   `snap(pitch)` (to the scale, ties down), `tones(from_pitch, count)` (the chord's tones going
   up), `voiced(h, centre, count)` (the decision's rule), `note_name(pitch)` (sharp or flat by
   the key) and `section_of(name)`. `DemoSong.HARMONY` is the stand-in Intro's brackets
   (offline_backend.gd `_arrange`, one line). section_of is used at every place in the decision:
   ChalkVenue.board_from (skips a brackets-only marker), TapeDeck.section_at (skips one too) and
   its PREV/NEXT/MARK hover text, timeline_surface.gd's ruler flags (section on top, harmony
   under, width from the longer line) and timeline_region_page.gd's next_name (the section, or
   "Region N" when the marker is brackets only). The proving idea is the demo song showing its
   own key: INTRO on the deck and `A minor: Am F C G` under the Intro flag on the 3D ruler.
   Touches harmony.gd, demo_song.gd, offline_backend.gd, chalk_venue.gd, tape_deck.gd,
   timeline_surface.gd, timeline_region_page.gd. The suite checks parsing (keys, modes, both
   spellings, `-`, malformed, a section name with no brackets); the chord through a tempo change,
   3/4, a second bracket and a plain marker between; NONE with no markers; that HARMONY's chords
   are DemoSong.CHORDS's pitch classes and the stand-in's Intro has them; snapping, tones and
   voicing (bells in Am and F, fingertips in Am and F, a seventh chord's top); and section_of at
   each place: the board, `section_at` over `Intro [A minor]`, a brackets-only marker inside a
   Verse leaving VERSE showing, the PREV hover over a brackets-only marker naming its key, the
   ruler's label width, the region's ADD name. shots/spatial1.png is the tape deck and ruler.

   Built. `Harmony` is a value: `at` and `parse` return one, with `snap`, `tones` and
   `note_name` on it and `voiced` beside it; it also keeps `mode`, `since` (the chord's start in
   seconds), `text` (the brackets' inside) and `progression`. A chord lasts while the bars after
   it are `-` or the same chord, so `Am Am` is one chord and `until` is where another comes. A
   chord is a root (either spelling) and a quality (`m`, `dim`, `aug`, `sus2`, `sus4`, `7`,
   `maj7`, `m7`, `dim7`, `m7b5`, `6`, `m6`, `5`), and `|` may part the bars. Brackets that do
   not read as a key are left in the name (section_of does not strip them), so a typo shows on
   the deck and the board instead of quietly playing in C. `TapeDeck.marker_label` is the
   locator's name for a marker. On the 3D ruler the section goes up into the bar numbers' row
   (none are drawn under a flag) and the harmony goes under it, cut with an ellipsis before the
   next flag when the section is narrow (`TimelineSurface.flag_lines`, `flag_width`). `--at 6
   --view 0:24` frames the shot. 74 checks in five tests (`_test_harmony_*`,
   `_test_the_demo_song_is_in_its_own_key`, `_test_brackets_are_kept_off_every_section`).
2. [x] **One player's keys, many instruments.** GuestMidi's `instruments` set, `reach(name, on)`,
   `has_instruments()`, the `keytar` view, the synth started on the first entry and stopped on the
   last, `plays()`/`take_track()`/`_track_plugin()`/`_hear_host_keys()`/`_on_role_changed()`
   reading the set, `held` counted by source, and the take named after what played. `note_on` and
   `note_off` gain `source` (StringName) and `at` (a song position, NAN for "now"): with `at`, the
   take and the sent Note use it instead of `stamp()`. Session.send_note, `_note_up`, `_note` and
   `note_played` gain `source`. Every `note_played` listener takes the extra argument.
   session_panel.gd reads `has_instruments()`. No new idea; it is what the harp, fingertips, cables
   and wheel all stand on. Touches guest_midi.gd, session.gd, presence.gd, their_keys.gd,
   their_monitor.gd, keytar_item.gd and studio.gd (every `note_played` listener), session_panel.gd,
   tools/probe/session_probe.gd. The suite checks that the keytar alone behaves as before (its
   existing checks unchanged); that two instruments in reach keep the synth running when one
   leaves; that the synth starts on reach, before any note; that one take spans two strums with a
   gap, on a host on the built-in engine; that one source letting go of a pitch leaves another
   source's same pitch sounding; that `at` lands a note where it says; and that the panel shows the
   keys box for a harp in reach. The probe checks that a note's source arrives at the host and at
   the guest. Both sides at 0 failed.

   Built. `instruments` is {name: true}, and `reach` is its one writer: going out of reach lets
   go of what that instrument still had down. `held` stays {pitch: velocity}, the union, so the
   keytar and its tests read it as before. What holds each pitch is a `KeysDown`
   (core/session/keys_down.gd), and a note-off sounds, and closes the note in the take, only when
   the last source lets go. A note-off from a source that never had the pitch, while another holds
   it, touches nothing. Every source's note-on and note-off is still sent, so a bandmate's harp
   can hear its own strings let go. `TheirKeys` and `TheirMonitor` count by source the same way.
   Presence plays out of the keytar only a holder's `&"keytar"` or plain notes. The studio's
   keytar piano plays with source `&"keytar"`, and plain keys played while the keytar is in hand
   name the take `keytar`, as before. `GuestMidi.take_name` joins the sources in the order they
   first played (`harp+fingertips`); plain keys alone are `take`. The host takes a source longer
   than `Session.NOTE_SOURCE_MAX` (24) as plain keys. The suite's synth is `_SpySynth`, a
   MonitorSynth that counts starts and stops and the pitches sounding, since a headless run has
   no sound card. The two-strum take test sets `roll_every` to 0: a Tour test earlier in the
   suite leaves it at 2.4, which would send the take between strums. 31 checks in four tests
   (`_test_one_players_keys_hold_many_instruments`,
   `_test_a_pitch_two_instruments_hold_sounds_until_both_let_go`,
   `_test_one_take_spans_two_strums_and_lands_notes_at_their_at`,
   `_test_the_panel_shows_the_keys_for_a_harp_in_reach`), and one probe check on each side.
3. [x] **A chord harp, and the thumbstick.** The proving idea, #22: `ChordHarp`
   (core/music/chord_harp.gd, a ControlAffordance) stands at `Venue.harp_spot()`. Its default in
   venue.gd is against the live room's back wall behind the bricks table, the side away from the
   shelf, mirror, wardrobe, door and tour case. Its walker solid is appended inside `solids()`'s
   `prop_shelf_solid()` branch, so a drawn-only venue stays drawn-only. It is rebuilt on
   set_venue. Its body is a Blender model (tools/blender/chord_harp.py,
   assets/models/chord_harp.glb), with eight strings tuned to `Harmony.tones(55, 8)` at the
   stamp. A grab (mouse, pinch ray, controller) plucks the nearest string, and a grab_move plucks
   every string it crosses since the last move, either way: a strum, with velocity from the
   speed across (InstrumentItem.velocity_for, at least 50). A bare hand strums by touch. Each
   physics frame the harp takes the local tracked hands' index and middle tips (HandGestures, or
   PokeInteractor.tip until slice 7). A tip within 3 cm of the string plane and inside the frame
   plucks every string whose x lies between where it was last frame and where it is now, either
   way. So a hand brushing back and forth is a strum each pass. A grab from a PokeInteractor is
   ignored, so a touch is never counted twice. Each note rings RING (1.6 s) or until its string is
   plucked again. Two octave buttons on the crown (small ControlAffordances, `8va UP` and `8va
   DOWN`, pressable by finger, ray, controller and mouse) move the strings an octave, at most two
   either way. The wheel and the thumbstick nudge the same. The crown shows the shift as text
   (`+1 OCT`). The hover card says CHORD HARP, `Am (A minor), bar 2 of 4`. The chord's name is on
   the crown and each string's note at its top. A sounding string visibly shakes. On a chord
   change the strings retune at once, and a ringing note keeps its pitch. The studio puts
   `&"harp"` in GuestMidi.instruments while the walker stands within 1.6 m of the harp, a hand
   here hovers or holds it, or a string still rings. Notes are played with source `&"harp"`.
   Presence plays a bandmate's `harp` notes on `ChordHarp.heard`, a MonitorSynth with the harp as
   its speaker (KeytarItem's pattern), keyed by (peer, pitch). XRInteractor reads `primary` and
   nudges what it hovers or holds (the decision's flick rule), which every knob and fader gets
   too. Touches chord_harp.gd, venue.gd, studio.gd, presence.gd, xr_interactor.gd,
   tools/blender/chord_harp.py, tools/probe/session_probe.gd. The suite checks a strum across the
   harp under a given heard position playing the chord ascending, retuned after the bar line, and
   recorded on the armed track with those pitches as one take across two strums; a synthetic
   fingertip passing through the strings and back plucking each twice; a poke grab plucking
   nothing; the octave buttons and a nudge moving the strings, stopping at two; a bandmate's
   harp note heard from the harp and its note_off arriving 1.6 s after their hold went still
   letting it go; a thumbstick flick nudging a fader one notch and a held stick repeating; and
   that every venue and variant (the shelf check's loop) puts the harp on the floor, off the
   footprint, clear of the zones, their solids and every other spot's prop, with room to stand in
   front of it, and keeps `ChalkVenue.solids().size() == zone_solids().size()`. The probe checks
   that a guest's strum reaches the host as harp-tagged notes of the chord and that the host's
   strum reaches the guest. Both sides at 0 failed. shots/spatial3.png is the harp in its corner.

   Built. `ChordHarp` stands in the venue's frame (a child of it, like the roulette door,
   `Studio._stand_the_harp`), its solid is `ChordHarp.solid(spot)`, and `Studio.harp` and
   `Presence.harp` point at it. Its pitch, record position and sent `song` come from one read of
   the keys' clock per strum (`_moment`: `GuestMidi.song()` while the song plays, else the
   playhead). A sweep plucks the strings it reaches, not the one it set out from
   (`ChordHarp.crossed`), so a grab plucks the nearest string and a drag from there does not pluck
   it twice. A pluck of a pitch another string still rings (after a retune) ends that note first,
   so one pitch is one note. Only the index tips are read for now (PokeInteractor has no middle
   tip); `tips` is a Callable of {id: point}, so slice 7 swaps in HandGestures without touching
   the harp. A touching tip must be in the plane band in both frames, and a string counts only if
   it is long enough to be where the tip passed. `8va UP`/`8va DOWN` are `ChordHarp.OctaveButton`s
   (personal, dwell-pressable); a nudge at the end of the range is taken, so the wheel over the
   harp never falls through to the camera. The hover card's bar is counted from the bracket's own
   bar (`_bracket_bar`). The corner is dark in most venues, so the harp carries a music-stand
   lamp on an arm out from the crown (a SpotLight3D, not an OmniLight, which the practicals'
   check counts). The loft's gallery and stair fill the back wall behind the bricks table, so
   `LoftVenue.harp_spot` stands it at the gallery's edge in the aisle between the riser and the
   lattice. The studio's reach test uses the walker on a desktop and the head in a headset.
   `XRInteractor.flick(along, delta)` is the stick rule (eased off between 0.3 and 0.6 neither
   repeats nor rearms). 178 checks in six tests (`_test_a_harp_strum_plays_the_chord_and_is_one_take`,
   `_test_a_fingertip_brushes_the_harp_both_ways`, `_test_the_harp_moves_by_the_octave_and_stops_at_two`,
   `_test_a_bandmates_harp_note_is_heard_from_the_harp`, `_test_a_thumbstick_flick_nudges_one_notch`,
   `_test_every_venue_stands_the_harp_clear`), and three probe checks on each side: the host
   writes `[D minor: Dm]` at the playhead's bar, the guest strums at 41 s and the host at 43 s, and
   each hears the other's eight strings as D minor's, each let go. shots/spatial3.png, and
   shots/spatial3_crown.png for the crown.
4. [x] **Instruments as items, and handbells.** InstrumentItem gains `note_at(seconds)` (default
   `pitch()`), `channel()` (default 9), `note_seconds()` (default NOTE_SECONDS), `MELODIC_CHANNEL`
   (10) and a static `clock` (a Callable, set by the studio to HitRecorder.stamp, so
   InstrumentItem still knows nothing of core/session/). `play()` reads `clock` once into `at`,
   pitches its sound by `note_at(at)`, starts it in the same call, and emits `played(velocity,
   struck, at)`. HitRecorder.hit(item, velocity, at) records `note_at(at)` on `channel()` for
   `note_seconds()` at `at`, with no second stamp. `Session.send_item_hit(item, velocity, song)`
   carries the song position (`song` as GuestMidi.song has it, -1 when not playing), and so do
   `_item_hit_up`, `_item_hit` and `item_hit`. A struck pitched item (a click on a bell) sends
   item_hit too, since its use is only its ring. Presence's `_on_item_hit` calls
   `heard(velocity, struck, song)`, which pitches by `note_at(song)` (its own heard position only
   when `song` is -1) and drops the random pitch wobble for a pitched item. The percussion's notes
   are unchanged. The proving idea, #32: `HandbellItem` (core/items/handbell_item.gd), ids
   `bell1`..`bell4` appended to ItemRoom.KINDS (ids with digits, as the darts have) with a `make`
   case each. Their homes are `Venue.bell_spot(n)` (four pegs on a small stand beside the harp,
   via Studio._item_homes). The stand's solid goes in the same branch as the harp's. A bell's job
   is its number, voiced at centre 72: bell1 the chord's root, bell2 its third, bell3 its fifth,
   bell4 its top. Swing to ring (InstrumentItem's stroke, the mouse's wiggle on a desktop); a
   click rings it. The sound is `Foley.handbell(take)`, synthesised at C5 (a few inharmonic
   partials, a long decay) and pitched to the note. It records on channel 10, 0.8 s long. The
   handle shows its number and the note it rings now (Label3D), which changes at each chord
   change. The model is tools/blender/handbell.py, one bell with the numbers as labels. A band
   holding the four cannot clash, and one player can hold two and pocket two. Tour:
   `TourPart.ITEM_CHANNELS` and Measure._matches as decided. Latency: the session panel's MY KEYS
   row shows the item path's reported latency (AudioServer.get_output_latency) beside the keys'
   (MonitorSynth.latency_seconds). If the item path is over 25 ms on the target machine, the
   Quest preset included, bells move to a MonitorSynth voice of their own as the next slice.
   tests/run_tests.gd's shelf check becomes `ItemRoom.KINDS.size() - 18`, its comment naming the
   bells. Touches instrument_item.gd, hit_recorder.gd, handbell_item.gd, item_room.gd, foley.gd,
   venue.gd, studio.gd, session.gd, presence.gd, tour_part.gd, measure.gd, session_panel.gd,
   tools/blender/handbell.py, tools/probe/session_probe.gd. The suite checks each bell's pitch in
   Am and in F and across a bar line; that a hit's sound pitch, recorded pitch and sent song come
   from one `clock` read, with a clock that moves between reads; that a bell hit is recorded as
   its chord tone on channel 10 for 0.8 s while a shaker in the same take is still 82 on 9 for
   0.06; that a bandmate's hit sent at a song position just before a bar line, heard here after
   it, rings the sender's chord tone; that a bell note in a keys part neither passes nor spoils
   it and that ITEM_CHANNELS matches the two constants; that play() has a sound playing before
   it returns; that the shelf check passes with 22 kinds; and that every venue gives the bells
   homes a person can reach. The probe checks the four bells in both rooms' items and a guest's
   ring reaching the host with its song. Both sides at 0 failed. shots/spatial4.png is the bells
   on their stand.
   Built. `HandbellItem` (core/items/handbell_item.gd) is one class for the four, `number` 1 to 4
   (`HandbellItem.new(n)`, ids `bell1`..`bell4`); a bell's note is `Harmony.voiced(Harmony.at(
   state, seconds), 72, 4)[number - 1]`. `InstrumentItem.now()` is the one read (`clock`, or the
   playhead when it is unset or its HitRecorder is gone), and `last_note` is the note the last hit
   rang, here or heard. `pitched()` is `channel() != HitRecorder.CHANNEL`; `sound_pitch(note)`
   (1.0 for percussion, `2^((note - 72) / 12)` for a bell) is what the sound is pitched by, on
   top of `pitch_scale()`. ItemRoom.played gains `at` too, so slice 5's jacks get the hit's one
   position. The `song` sent is the hit's own `at`, not GuestMidi.song's -1 while stopped: while
   stopped `at` is the replicated playhead, which every machine has the same, so there is still
   one read and nothing to fall back on; -1 stays the "not known" a receiver pitches by its own
   clock. The host takes a non-finite or negative `song` as -1. A bandmate's click on a pitched
   item arrives as a use as well as a hit: `use` on a copy not in a hand here rings a pitched item
   not at all, so it rings once, at its song. The studio sends hits through `Studio.send_item_hit`
   (Session.send_item_hit, the suite's spy). `Foley.handbell` is six partials (strike note and
   twelfth true, the hum, tierce and two shimmers a hair off) at C5, 2.2 s with its last 0.4 s
   faded. The tab at the handle's foot letters the number (Label3D) and the note now, relettered
   every 0.1 s. The stand is `HandbellItem.stand()` (tools/blender/handbell.py writes
   assets/models/handbell.glb and bell_stand.glb), stood by `Studio._stand_the_harp` at
   `Venue.bell_stand_spot()`: on the harp's high side, a hand's width (0.12 m) off its plinth,
   backs in line, facing the same way. The seats are low felt bosses, not pegs, so a bell stands
   mouth down over one with its clapper clear. `HandbellItem.seat(n)` is a bell's place on it,
   lowest on the left as you face it, tab toward you; `Venue.bell_spot(n)` (n 1 to 4) is that in
   studio space. In the loft the aisle by the gallery is too narrow for the gap either side, so
   `LoftVenue.bell_stand_spot` centres the stand between the plinth and the drum riser. The
   session panel's keys row shows `Bells  ·  N ms` (AudioServer.get_output_latency) beside
   `Hear my keys  ·  N ms`, and `, over 25` when it is (`InstrumentItem.LATENCY_MOST`): this
   machine's headless runs cannot measure it, so whether the bells need their own voice is read
   off the panel on the target machines. 201 checks in five tests
   (`_test_each_handbell_rings_its_chord_tone`, `_test_a_bell_hit_takes_one_clock_read`,
   `_test_a_bell_neither_passes_nor_spoils_a_keys_part`, `_test_the_panel_says_how_late_the_bells_are`,
   `_test_every_venue_gives_the_bells_reachable_homes`), and the four existing hit tests take the
   new `at`/`song` arguments. Three probe checks on the host and two on the guest: the four bells
   in both rooms' items (`ItemRoom` on each half), the guest ringing bell 2 at 44 s a quarter
   second past the host's D minor marker as F5, and the host receiving it with that song and
   ringing F5 there.
   shots/spatial4.png is the bells on their stand beside the harp, and shots/spatial4_tabs.png
   their tabs up close (1 A4, 2 C5, 3 E5, 4 A5 in the demo song's Am).
5. [x] **Output jacks, onto tracks.** `Jack` (core/music/jack.gd): the event kinds NOTE_ON,
   NOTE_OFF and TRIGGER, the source and sink names (`track_N`, `player_P`, item ids, `harp`,
   `keys:P`), and `valid_sink`. `Jacks` (core/music/jacks.gd, the studio's, beside HitRecorder)
   takes every instrument hit (`ItemRoom.played`, so every percussion item and bell has a jack
   with no change to it) and reads the room's patch. Unplugged, it is the old path. Into
   `track_N`, HitRecorder records onto N whether or not it is armed (it keeps a take per track).
   Room: ROOM_VERBS `plug` [TYPE_STRING_NAME, TYPE_STRING_NAME] (an empty sink unplugs). The host
   lets the hand holding the source plug it, and anyone plug it while it is at home. It refuses an
   unknown track. The patch is in `room_state()` and `apply_room`, with `plug` in its prediction
   filter beside `patch`. A personal copy put back takes its plug with it. Hands: each
   InstrumentItem has a `JackSocket` (core/music/jack_socket.gd, a ControlAffordance at the
   subclass's `jack_point()`). A press steps it through unplugged and then the tracks that take
   MIDI, round again, so every hand gets back to unplugged by pressing. A nudge (wheel,
   thumbstick) steps either way, and its hover card says where it goes. The carrying hand's ray
   leaves out its own item's socket (the ray query's `exclude` gets the socket's body while
   `carrying` is its item). So the trigger or click still strikes the shaker, and the other hand,
   a bandmate or the desktop key plugs it. A desktop player holding the instrument presses P to
   step it and Shift+P to step back. A patched item shows a tag, `-> 3 BASS`, and a short lead
   ending in a plug, never a cable to the patchbay, which shows sends. Touches jack.gd, jacks.gd,
   jack_socket.gd, hit_recorder.gd, instrument_item.gd, interactor.gd (the exclude),
   mouse_interactor.gd (P), session.gd, studio.gd, tools/probe/session_probe.gd. The suite checks
   that an unplugged hit records as before; that a track jack records onto an unarmed patched
   track and not the armed one; that the carrying hand's trigger over its own socket strikes the
   item and the other hand's press steps the socket; the host's checks (whose hand, at home,
   unknown track); that a guest's plug survives a room that has not answered it and goes when
   refused; and that a retired copy's patch is dropped. The probe checks that a guest's plug
   reaches the host's room state and the host's reaches the guest's. Both sides at 0 failed.
   shots/spatial5.png is the shaker on the shelf with its lead and tag.

   Built. `Jack` is static: `track_sink`/`track_of`, `player_sink`/`player_of`, `keys_source`,
   `valid_sink` (by shape only: empty, `track_N` or `player_P` with N, P whole and above 0),
   `valid_source` (a name of at most `NAME_MOST`, 32) and `kinds_of(pitched)`. `Jacks` keeps the
   patch as {String: String}, the shape the room carries, and has `plug`, `set_patch` (the host's
   rows replace the patch whole), `state`, `drop`, `hit`, `next_sink`/`step` and `sinks()`:
   unplugged, then every track but a frozen one (a frozen track's items are one render). Its
   `refusal(item, sink, from, holder)` is the host's rule in words, and the studio asks the same
   of a hand here before predicting, so a plug that would be refused (the instrument in somebody
   else's hand, or lying on the floor) is said in a notice and never asked. Into a player is
   refused until slice 6, and a jack into a track that has since gone records the old way. The
   socket is on the instrument's -X end, the end on your right as you face it
   (`InstrumentItem.jack_point`, `jack_out`), just past its grip: from the mix position the shelf
   is seen along its length from that end, and the seat audit needs a ray to find it before the
   instrument. The bells' ends all but touch on their stand, so `HandbellItem` puts its jack on
   its front, low by the mouth. The socket's look is under the item's body, so it is hidden, kept
   out of the mirror and squashed with it; its shape is beside the body, like the grip, and off
   while the item is pocketed, worn or hidden. It has its own metal, since `Item.set_rim` rims
   every material in a held body. It is `personal()` (where it goes is the room's, not a hold) and
   dwell-pressable, and its hover card says where a press takes it (`press for 4 HAT`). HitRecorder
   keeps `_jacked`, {track: MidiTake}: a jack's take begins with its first hit, from where the
   song is heard or the hit if that is a hair earlier, and is sent with the armed one's when
   recording stops or rolls on (`jacked_tracks()`). `Interactor.own_jack()` is what the ray
   leaves out. P is not taken on a key's repeat. A copy leaving the room is caught by the item
   room's `child_exiting_tree` for an id it no longer lists, so a whole studio closing does not
   unplug anything. The plan's "the other hand, a bandmate or the desktop key plugs it" is read
   with the host's rule: a bandmate plugs an instrument while it is at home, and only its holder
   while it is in a hand. 58 checks in five tests (`_test_a_jack_names_its_ends`,
   `_test_a_track_jack_records_onto_its_track`, `_test_the_carrying_hand_strikes_and_the_other_plugs`,
   `_test_the_host_says_who_may_plug`, `_test_a_guests_plug_is_predicted_and_rolled_back`), and
   three probe checks: the guest plugs the shaker on its shelf into track 3 at 44.5 s, the host's
   room takes it (by `Jacks.refusal`), the host plugs bell 1 into track 5, and the guest's room has
   both. shots/spatial5.png is the shaker on the shelf patched into 3 SNARE by three clicks on its
   socket through the mouse's ray (`SHOT_CAM="2.05,-0.32,0.85,-6.68,0.29,3.69" SHOT_ARGS="--click
   SHAKER__JACK@30 --click SHAKER__JACK@44 --click SHAKER__JACK@58 --aim SHAKER__JACK"
   tools/shot.sh shots/spatial5.png 160 166`).
6. [x] **Cables between players.** The proving idea, #33. The socket's cycle gains each bandmate
   (`player_P`). The harp gets a JackSocket on its pillar, and `keys:P` gets one on P's wrist
   (HandSkeleton's wrist, or the desktop's P with an empty hand), pressed by the other hand. Into
   `player_P`, Jacks calls `Session.send_jack(to, source, kind, pitch, velocity, song)`, a new
   relay on KEYS_CHANNEL, reliable. It goes up to the host and on to P alone. The host passes it
   only when `to` is a member and the patch row sends `source` into `player_to`, and only from the
   source's player. For an item that is its holder in Session.holds of its network key; for
   `keys:P` it is P; for `harp` any member, since the harp is the room's to play. Pitched sources
   send their own NOTE_ON/NOTE_OFF (the harp's strings, the keys' notes, a bell's note with its
   0.8 s off). Percussion sends TRIGGER. On P, `Jacks.received` plays it on P's keys with source
   `&"cable"` and `at = song` (GuestMidi.note_on's `at`), so it lands in P's take where the player
   played it. A TRIGGER takes the chord tone at `song` (`Harmony.at(state, song)`, one tone up per
   hit: root, third, fifth, top, round again) for 0.3 s. `&"cable"` is in P's instruments while
   anything is plugged into P. It sounds on P's synth, goes to everyone as P's notes, and is in
   P's take. The sink's player may unplug anything going into them (Shift+P on a desktop with an
   empty hand unplugs all of it), and the host refuses a peer not in the room. Into a bandmate, a
   slack cable (CableSweep, rebuilt at most 15 Hz while either end moves) runs to their ghost's
   nearer glove. The receiving player is told who plugged what into them. Touches jack.gd,
   jacks.gd, jack_socket.gd, chord_harp.gd, hand_skeleton.gd, session.gd, studio.gd,
   guest_midi.gd, presence.gd (the cable's far end), mouse_interactor.gd,
   tools/probe/session_probe.gd. The suite checks that a trigger into a player walks up the chord
   at `song` (not at arrival: a song before a bar line arriving after it) and lets each note go;
   that a bell into a player plays its own note and its off; that harp notes into a player play
   those pitches and land in P's take at their `song`; the host's checks (a non-holder's event for
   a held item refused, `keys:P` from anyone but P refused, a peer not in the room, the sink's
   owner unplugging); and that `cable` leaves P's instruments when the last plug goes. The probe
   checks that a guest plugs the shaker into the host and the host's keys play the guest's hits
   as chord tones; that the host plugs a bell into the guest and the guest plays its pitch; and
   that a guest's harp strum patched into the host lands in the host's take. Both sides at 0
   failed. shots/spatial6.png is a cable from the shaker to a ghost's glove.

   Built. `Jacks.sinks(source)` is unplugged, then the tracks (an item's only), then each
   bandmate (`Jacks.bandmates`, the room's members but this player, by id) but the source's own
   player: the harp's and a player's keys' sockets step through bandmates only, since their notes
   are keys and already go onto the armed track by the keys' own choice (`plug_refusal` says so of
   a track). `Jack.keys_player` and `Jack.is_item` name the other two kinds of source, and a sink
   or a player's keys may name any peer id ENet gives out, ten digits up to 2^31 - 1
   (`Jack.NUMBER_MOST`): the probe's first run found `player_1717822209` refused at six. The room's
   word on a plug is `Jacks.plug_refusal(source, item, sink, from, holder, now, members)`: whoever a
   jack now goes into may take it out (a press on that jack, by any hand, unplugs it rather than
   stepping it); into a member of the room, not into yourself; the harp anyone's; `keys:P` only
   P's; an item `refusal`'s, as before. The host tells whoever a jack goes into, or no longer
   does, who did it (`Session.tell`), and the one plugging is told where it goes in words (`The
   shaker goes into Lin: its hits play chord tones on their keys.`). A leaver's jacks, into them
   and out of their keys, come out with them (`Jacks.drop_player`). The relay is
   `Session.send_jack` / `_jack_up` / `_pass_jack` / `_jack` on KEYS_CHANNEL, reliable; the host's
   word is `Session.jack_refusal` (both ends members, not the same player, then
   `Session.jack_check`, which the studio sets to `Jacks.send_refusal` over its patch and
   Session.holds). It clamps pitch and velocity, refuses a kind that is not one, takes a song
   that is not finite or is negative as -1, counts refusals (`jacks_refused`), and emits
   `jack_played` on P alone. On P, `Jacks.received` plays on P's keys (`Jacks.keys`,
   Session.guest_midi) with source `&"cable"` and `at = song`, and keeps each note by (sender,
   source, pitch), so two cables on one pitch sound until both let go and an unplugged source
   lets go of what it had down. `received` also puts `&"cable"` in reach at once, ahead of the
   room that says so. A TRIGGER is `Jacks.walk`: `Harmony.voiced(Harmony.at(state, song), 60,
   4)`, one step on per (sender, source), let go TRIGGER_SECONDS later at `song + 0.3`. A bell
   sends `last_note` and its off `note_seconds` later at `at + note_seconds`, and rung again
   before that off, the off goes first. Into a bandmate a hit is not taken down here. The harp
   with a plug in it sends its strings down the cable (the ring-out's off at the song then) and
   is heard here from the harp's own room voice (`ChordHarp.heard` under this player's id), not
   on this player's keys. `keys:P` is a thru: GuestMidi gains a `note` signal (each note as it is
   sent), and `Jacks` passes P's notes on, all but `&"cable"`'s (two players plugged into each
   other never feed back) and the harp's, which has its own jack; P's keys are still heard, sent
   and taken down at home. `JackSocket.new(null, source)` is a socket on no instrument, with its
   look its own and `available` for when it may be pressed; `mine_keys` makes it `keys:P` for
   whoever this player is now. The harp's is on the short pillar's front (`ChordHarp.JACK_AT`),
   and the keys' are under `HandSkeleton.wrist` (`wrist_mount`: on the back of the left wrist,
   facing out) and on the left controller while that hand is not tracked (`Studio.wrist_jacks`).
   On a desktop, P with an empty hand steps the keys' jack and Shift+P unplugs everything into
   this player (`MouseInteractor.bare_jack`, `Studio._on_bare_jack`); a headset does the same by
   pressing the INTO ME socket worn 6 cm up the arm from the keys' (`JackSocket.into_me`, there
   only while something goes into them, its tag naming what: `<- GRACE'S KEYS`), the only hand
   path out for a bandmate's keys, whose socket is on the bandmate. The receiver's notice says the
   way for their medium (`Studio.unplug_how`). A jack into the player who is playing its source is
   no cable (`Jacks.cable_into`): the harp or a home shaker someone else plugged into Ada plays on
   her keys and into her take when she plays it, not into herself. A source that went into this
   player and was taken out is cut (`Jacks._cut`) until it goes into them again: a NOTE_ON or
   TRIGGER the host passed before it heard the unplug is dropped, since its off will be refused,
   and every room state lets go of whatever a cable has down that it no longer sends here. Into a bandmate the socket
   draws a top-level cable (`JackSocket.slack`: sagging by 0.08 m plus 0.18 of its span, never
   under 3 cm off the floor, coming up into the glove from below) to `Presence.cable_end`, the
   nearer glove of their ghost (`Avatar.nearer_glove`), rebuilt at most CABLE_HZ (15) and only
   when an end has moved 5 mm; with no ghost here the short lead hangs instead, and the tag says
   their name (`-> LIN`). The shot harness gains `--plug source:sink` (frame 10, asked as a hand
   asks). 71 checks in six new tests and one more in `_test_a_jack_names_its_ends`
   (`_test_a_trigger_into_a_player_walks_the_chord_at_its_song`,
   `_test_cable_leaves_my_keys_with_the_last_plug`, `_test_harp_notes_into_a_player_land_in_their_take`,
   `_test_a_jack_into_a_bandmate_sends_what_its_source_plays`,
   `_test_the_host_says_who_may_send_down_a_jack`, `_test_the_keys_jack_is_worn_on_the_wrist`);
   slice 5's "not built yet" checks now say a player not in the room is refused. Five probe checks
   on the host and four on the guest: the guest holds the shaker and plugs it and the harp into
   the host at 48.3, hits it four times at 48.8 and the host's keys play D minor's 62 65 69 74 at
   those songs and let each go; the host holds bell 1, plugs it into the guest at 48.6 and rings
   it at 49, and the guest's keys play D5 and its off 0.8 later with the cable in reach; the guest
   strums the harp into the host at 50.2 to a clock of its own, and the host, recording to a
   clock of its own onto track 9, has one take, `Ada cable 1`, with the eight strings each at the
   song the guest plucked it. The probe's end moves from 49.4 to 55.4. shots/spatial6.png:
   `SHOT_CAM="2.05,-0.22,1.9,-6.4,0.8,4.1" SHOT_ARGS="--visitor -6.3,4.6,1.0 --plug
   shaker:player_7" tools/shot.sh shots/spatial6.png 160 166`.
7. [x] **Hand readings.** `HandPose` (core/input/hand_pose.gd, static, pure): from the joints,
   `size` (wrist to the middle finger's proximal joint; the reference hand is 0.095 m), `curls`
   (five, 0 open to 1 curled, along each finger against the palm), `pinches(joints, was)` (thumb
   tip to each fingertip, in under 18 mm and out over 30 mm at the reference size, scaled by
   size / 0.095 and by Ergonomics' `finger_scale`, default 1), `palm_normal`, `palm_up` (normal
   within 35 degrees of world up), `faces_head(joints, head)` and `tilt` (pitch and roll of the
   palm's basis against level, each clamped to TILT_MOST, 45 degrees, and read as -1..1).
   `HandGestures` (core/xr/hand_gestures.gd, one per hand under XRRig beside HandSkeleton) reads
   the tracker (XRRig.HAND_TRACKERS, POSITION_VALID as HandSkeleton checks) each physics frame
   and keeps the latched state. Interactor gains `finger_pinches()` (0), `palm_up()` (false),
   `tilt()` (Vector2.ZERO) and `fingers_play`: while it is true, `is_pressing()` is false, so a
   playing hand grabs nothing. XRInteractor answers a bare hand from HandGestures, and a
   controller from trigger (index), grip (middle), A/X (ring), B/Y (little), and its aim basis for
   palm up and tilt. The left controller's B/Y is XRRig's calibration button. So XRRig skips the
   calibration edge while the left hand's `fingers_play` is on, and keeps tracking
   `_calibrate_was_down` all the while, so a Y held as fingertips turn off takes no mark.
   MouseInteractor's `tilt()` is its wiggle over WIGGLE_MOST, and `wiggle()` now runs while
   `fingers_play` is on as well as while carrying an InstrumentItem. ChordHarp takes its tips from
   HandGestures. No new idea is played. It is proved on the harp and on a fader by the readings.
   Touches hand_pose.gd, hand_gestures.gd, xr_rig.gd, interactor.gd, xr_interactor.gd,
   mouse_interactor.gd, ergonomics.gd, chord_harp.gd. The suite builds posed hands from 26
   synthetic joints (`_posed_hand(curls, pinched, palm, scale)`, beside `_fake_hand`, at the
   reference size unless scaled) and checks: curls of an open hand and a fist; each finger's
   pinch held through 25 mm of jitter and let go past 32 mm, and at 0.8 scale held through 20 mm
   and let go past 25.6 mm; palm up and faces_head for a hand held out flat, one turned to the
   eyes and one palm down; tilt of 20 degrees roll reading the same from a posed hand, a
   controller basis rolled 20 degrees and a mouse wiggle at 20/45 of WIGGLE_MOST; the controller's
   button mask matching the hand's; a left Y press with fingers_play on taking no calibration
   mark, and one after it goes off taking one; and a hand with fingers_play grabbing nothing.
   shots/spatial7.png is a posed hand's readings in the shot rig (a test view).

   Built. `HandPose` takes a hand as a PackedVector3Array of the 26 positions, and what depends on
   the palm's facing takes `side` (-1 left, 1 right, as a Glove): positions alone cannot tell a
   left hand from a mirrored right one. `frame(joints, side)` is the hand's basis (+Y out of its
   back, -Z wrist to middle knuckle, across from the knuckles), and `palm_normal`, `palm_up`,
   `faces_head` (from the PALM joint) and `tilt` read it. `tilt_of(basis)` is the same reading of
   any basis held the way a hand is, so a controller's aim answers through it, and `faces_up`
   is palm up for any normal. A controller's palm is round the side of its grip, facing in toward
   the other hand (OpenXR's grip pose puts X through the palm), so it is `-side * aim().basis.x`
   (`XRInteractor.hand_side`, from its tracker): held thumb up it faces sideways, and the
   forearm's own quarter turn outward makes it palm up.
   Tilt is `Vector2(roll, pitch)`: roll positive clockwise as the person sees it from behind (the
   right side down, as `twist` counts), measured from the up that is level about the way the hand
   points; pitch positive fingers up. A curl is the bending added up along a digit's chain, the
   first bend against its metacarpal, over `CURL_FULL` (130 degrees for the thumb's two joints,
   250 for a finger's three). `mask_of` is a controller's buttons as fingers, `pinch_words` the
   mask in words, and `posed(curls, pinched, palm, scale, side, gap)` builds a hand (the suite's
   `_posed_hand` wraps it, and puts it on a tracker when named). `HandGestures` also takes
   positions straight (`take`), lets every reading go when the hand is not tracked or any joint's
   position is not valid, runs ahead of the interactors (`process_physics_priority` -1), and
   gives the harp its index and middle tips: `ChordHarp.tips` unset reads
   `HandGestures.local_tips`, keyed [hand, finger], so the studio's PokeInteractor `_fingertips`
   is gone. XRRig keeps `interactors` and `gestures` per controller beside `pokes` and
   `skeletons`, and the calibration edge is `watch_calibration(down)`; only the left hand's
   `fingers_play` holds it off. `fingers_play` also keeps the hand from catching, dwelling and,
   on a controller, throwing on the grip. Ergonomics gains `finger_scale` (1). One thing slice 8
   must mind: a palm up held in close at the chest faces the head by 60 degrees (at 1.25 m and
   0.25 m out, with the eyes at 1.6 m, the way to them is about 36 degrees off up), so it reads
   as facing the head; held out toward arm's length it does not. Nor is a controller's tilt level
   where a bare hand's is: level held thumb up, where the bare hand is level palm down, so the
   same hand reads about a quarter turn of roll apart with and without one. The bend and vibrato
   slice says which level it means. The shot harness gains
   `--posed-hand x,y,z,yaw,roll,mask` (frame 5: a tracker of its own, drawn by a HandSkeleton,
   read by a HandGestures, its readings lettered over it). 85 checks in eight tests
   (`_test_a_hand_pose_reads_its_size_and_curls`,
   `_test_a_pinch_holds_through_jitter_and_lets_go_past_its_gap`,
   `_test_a_palm_reads_up_and_toward_the_head`,
   `_test_a_tilt_reads_the_same_from_a_hand_a_controller_and_a_mouse`,
   `_test_a_controllers_buttons_are_the_hands_fingers`,
   `_test_a_left_y_with_the_fingers_playing_takes_no_mark`,
   `_test_a_hand_whose_fingers_play_grabs_nothing` (on a fader, and a button for the dwell),
   `_test_the_harp_is_strummed_by_the_hands_readings`). shots/spatial7.png is a right hand posed
   among the harp's strings, rolled 20 degrees and pinching its ring finger, with its readings
   over it: `SHOT_CAM="2.8,-0.15,1.2,4.85,1.1,6.8" SHOT_ARGS="--posed-hand
   5.0,0.98,6.77,3.14159,20,4 --hover 1580,880" tools/shot.sh shots/spatial7.png 40 46`.
8. [x] **Fingertip notes.** The proving idea, #36: `FingertipNotes`
   (core/music/fingertip_notes.gd, one per local hand). It turns on when an empty hand is held
   open, palm up, unpinched and not facing the head, for 0.4 s (a controller turned palm up, a
   quarter outward, counts), and off by the same again. While on it plays with the palm down or on its side. Pinches read
   while `faces_head` is true are ignored, so Quest's menu pinch never plays and playing never
   opens it. While on, it sets `fingers_play` and puts `&"fingertips"` in GuestMidi.instruments.
   Thumb to index plays the chord's root, middle its third, ring its fifth, little its top, voiced
   at centre 60, held as long as the pinch, with source `&"fingertips"`. The chord is read at the
   pinch's stamp. A held note keeps its pitch through a chord change, and the next pinch takes
   the new chord. Velocity comes from how fast the pinch closed: the trigger or grip's travel on a
   controller, 96 from a key. Desktop: one reader. A second KeyCatcher (`layout` a var, here J K L
   ;) is the fingertips' keys. T gives it focus, and `fingers_play` follows its focus, so a click
   elsewhere or Esc turns the fingertips off whole: the keys stop and the mouse grabs again
   together. MouseInteractor reads its mask from that catcher (`finger_source`) and reads no keys
   itself. While the fingertips are on, the desktop draws a right Glove (side 1, low right of the
   view) whether or not anything is carried. Glove gains `pinched` (a mask), and a pinched finger
   curls to meet the thumb. Shown, not coloured: each fingertip carries its note's name, which
   grows while pinched, and the chord's name sits over the palm (HandSkeleton's tips, or the
   glove's fingers). Touches fingertip_notes.gd, key_catcher.gd, mouse_interactor.gd,
   interactor.gd (the glove while fingertips are on), glove.gd, hand_skeleton.gd, studio.gd. The
   suite checks: palm up open for 0.4 s turning notes on and again turning them off; a palm-up
   pinch facing the head playing nothing; a pinch playing the chord's tone at the stamp and its
   release letting it go, with a chord change mid-hold; the keys' mask matching the hand's; the
   take on the armed track; a click elsewhere turning fingertips off and the mouse grabbing on the
   next press; that J pressed with fingertips off plays nothing; and the glove drawn with an empty
   hand. No new wire: the notes are the keys'. shots/spatial8.png is the desktop glove with its
   fingertip notes.

   Built. `FingertipNotes` (core/music/fingertip_notes.gd) steps each physics frame on its
   `hand`'s readings, which Interactor gains for it: `faces_head()` (a bare hand's
   HandGestures.faces_head), `hand_open()` (a bare hand's four fingers under
   `HandPose.OPEN_CURL`, 0.3, and none pinched, `HandPose.is_open`; a controller with no finger
   button down; by default nothing pinched), `finger_travel()` (each finger 0..1 toward the
   thumb: a bare hand's gap from `HandPose.TRAVEL_FROM`, 9 cm, in to PINCH_IN, `HandPose.travel`;
   a controller's analog `trigger` and `grip`; NAN for a button) and `finger_pose()`. The turning
   hold counts only while the hand is empty and holds no control, and one hold turns it once, so a
   hand left palm up does not flicker. A pinch plays only while the palm is neither up nor toward
   the head, so a palm-up pinch held out plays nothing either; a held note lets go when its pinch
   opens whatever the palm does. Velocity is the travel's rise over the last 0.06 s, 30 at rest to
   127 at 10 a second (`velocity_for`), and 96 (`KEY_VELOCITY`) with nothing to read. The note is
   `tones_at(seconds)[finger]` at one read of the keys' clock (`_moment`, the harp's: GuestMidi.song
   while the song plays, else the playhead), and is played, sent and taken down at it. A pitch
   any finger here already has down (another hand's, or a finger's from the chord before) is one
   note, let go by the last finger on it. `&"fingertips"` is in reach while any hand's are on.
   Turning `fingers_play` off is a setter now: `_fingers_stopped()`, on the mouse, spends a button
   still down (`_press_spent`) until it comes up, so the click that gives the keys back does not
   also grab what it landed on. KeyCatcher gains `layout` (KeyCatcher.FINGERS for these, base 0,
   so a key's value is its finger), `octave_keys`, `velocity`, `click_releases` (a left click
   anywhere lets the keys go, as Esc does) and `held()`; a key's note-off is said after it is
   gone from `held()`, so a reader that polls sees it up. The studio's `fingertip_keys` is that
   catcher; MouseInteractor's `finger_source` is it, and its `finger_pinches()` is the catcher's
   keys down as fingers. FingertipNotes steps on the catcher's notes and focus at once, not a
   physics frame later. T toggles it (`Studio.toggle_fingertips`, told once); with it on the
   arrows still walk and WASD does not, as with the keytar's piano. `_lend_fingertips` makes one
   FingertipNotes for the mouse on a desktop and one per rig hand in a headset (with its
   HandSkeleton). The desktop's right glove is `Interactor._show_finger_glove`, at
   `MouseInteractor.finger_pose` (low right, turned in 0.35 rad and tipped down 1 rad, so its back
   and fingers face you past its cuff), drawn while `fingers_play` whatever the left glove
   carries. Glove gains `pinched`, a pinched finger curling to PINCH_CURL and the thumb across to
   meet it, and `make_letters`/`letter`/`letters`: a billboard name just past each fingertip, 1.5
   times larger while pinched, and the chord over the back of the hand (NO KEY SET with no
   bracket). HandSkeleton's `letter` does the same at a tracked hand's tips and over its palm. A
   controller's hand is not drawn, and a controller turned over by chance loses its trigger's
   grab, its grip's throw and (the left) Y's calibration, so a controller playing them carries a
   row of its fingers' notes over it, the chord above and "palm up 0.4 s: grab again" below
   (FingertipNotes `pad_letters`, top level on the XRController3D, turned to the head), and the
   rig hides that hand's pinch ray while its fingers play (`XRRig._show_hands`). The desktop
   glove sits at (0.2, -0.12, -0.5), high enough that its letters clear the bottom of the screen,
   and follows the wheel's zoom (`MouseInteractor.view_scale`, against FINGERS_FOV 58): drawn in
   and smaller by as much, it keeps its place and size on the screen. T is listed on the welcome
   card and the HUD (P as well, on the HUD). The shot harness gains `--fingertips
   mask` (frame 10: T, and that mask's keys held). 40 checks in two tests, and two more on the rig's ray
   (`_test_an_open_palm_up_turns_the_fingertips_on_and_off`,
   `_test_the_desktops_fingertips_are_four_keys_and_a_glove`). shots/spatial8.png is the desktop
   glove with J and L down in the stand-in's Am, lettered A3 C4 E4 A4 under Am, A3 and E4 grown:
   `SHOT_ARGS="--fingertips 5" tools/shot.sh shots/spatial8.png 40 46`.
9. [x] **Writing the harmony in the room, and a circle-of-fifths wheel.** Harmony gains
   `diatonic(key)` (the key's seven chords in fifths order), `follows(key, chord)` (the chords
   that lead well from it: its fifth down, the IV, the vi, the V of the next) and
   `written(name, harmony)` (a marker's name with its brackets set, or added after the section's
   name). The proving idea, #29: `FifthsWheel` (core/music/fifths_wheel.gd, a ControlAffordance
   on the bricks table every venue reserves, `Venue.zones()` "bricks"). Its outer ring has the
   twelve major chords in fifths order and the inner ring their relative minors. The key's seven
   stand raised; the others are lower and dimmed, and are lettered all the same. The chords that
   follow well from the last one pressed rise further and breathe (Ergonomics motion). Pressing a
   segment plays its chord (`&"wheel"` in GuestMidi.instruments while a hand is on or over the
   wheel, the notes 0.6 s) and adds it to the strip of up to eight bar tiles along the rim. The
   hub turns the key by fifths: twist in a hand, the wheel or thumbstick as a nudge, and two arrow
   buttons on the hub for a finger. Pressing the hub's middle swaps major and minor. SET writes
   `[key: strip]` at the bar it starts from. That bar is the one after the playhead's while the
   song plays (as this player hears it), and the playhead's own bar while stopped. A marker
   already at that bar gets the brackets (`written`, DAW.edit_marker); otherwise DAW.add_marker
   puts a brackets-only marker there. Either way it is one undo step. The harmony before that bar,
   and the bracket it came from, are untouched. The new chords count from that bar, and the
   harmony goes back to the old one only at the next bracketed marker after it, as any bracket
   does. CLEAR empties the strip. A guest's SET is an intent the host applies with the bar the
   guest chose. The harp, bells and fingertips everywhere follow from that bar as the markers
   replicate, and the 2D ruler shows the new name. The hover card names each segment
   (`F · IV of C major · follows well`) and SET's says the bar it will write at. Touches
   harmony.gd, fifths_wheel.gd, studio.gd, venue.gd if the bricks table needs a spot,
   tools/probe/session_probe.gd. The suite checks the diatonic chords and what follows; SET while
   playing in Verse 2 adding a brackets-only marker at the next bar and leaving the Intro's
   brackets as they were; SET while stopped onto a section marker at the playhead's bar; SET at a
   bar that already has a bracket replacing it; undo restoring the old name or removing the added
   marker; a progression too long for MARKER_NAME_MAX cut at a whole chord; a guest's SET sent as
   an intent with its bar; and the harp in the new chord from that bar and in the old one before
   it. The probe checks that a guest's SET adds the host's marker at the guest's bar and that
   `Harmony.at` agrees on both sides. Both sides at 0 failed. shots/spatial9.png is the wheel on
   the bricks table.

   Built. `Harmony.diatonic(key)` is the triads on the key's scale from the one whose root has no
   fifth below it in the scale, on up by fifths (C major and A minor: F C G Dm Am Em Bdim), spelled
   as the key spells notes. `Harmony.follows(key, chord)` is, in order and each once, the chord a
   fifth down (the key's triad there, or a major one when that root is out of the key), the key's
   triads on its fourth and sixth degrees, and a major triad on the chord's own root (the V of the
   next); the chord itself is left out (after Am in C: Dm F A). `numeral(chord)` (`IV`, `vi`,
   `vii°`, "" for a chord out of the key) and `chord_tones(name)` are on it too.
   `Harmony.written(name, harmony)` is `section [key: chords]`, or the brackets alone for "", and
   drops whole chords off the end until it fits `DAW.MARKER_NAME_MAX`, shortening the section only
   when the key alone does not fit. `FifthsWheel` (core/music/fifths_wheel.gd) is the hub itself (a
   ControlAffordance whose plane is the wheel's face), with 24 `FifthsWheel.Segment`s (each a
   twelfth of a ring, `sector_mesh`, sunk into the board so only its top stands proud: 5 mm out of
   the key, 16 mm in it, 28 mm risen) and `FifthsWheel.WheelButton`s for the hub's middle and two
   arrows, CLEAR and SET; all personal and dwell-pressable. The key is `turn` (fifths clockwise of
   C to the key's major) and `minor`; the middle swaps to the relative minor (C major and A
   minor), so the same seven stay raised. The key's diminished chord is the inner segment two
   clockwise of the key, lettered `Bdim` while it is; a segment in the key is spelled as the key
   spells it (Gb in Db major), one out of it as the wheel letters it (MAJORS, MINORS). The wheel
   starts in the song's key where it is heard (a major or minor one). A press plays the chord
   voiced at 60, four notes, at one read of the keys' clock (the harp's `_moment`), lets it go after
   RING (0.6 s) or at the next press, and adds it to the strip if there is room. The hub turns by a
   twist (a twelfth of a turn a fifth), by dragging round its middle with a mouse or a fingertip
   (counting again from where it is every half turn, so it never wraps back), by a nudge over the
   hub or any segment, and by the arrows (`<` and `>`). Follow-ups breathe by `BREATH` (3 mm) at
   0.5 Hz, scaled by `Ergonomics.motion_scale`, and stand still and higher with no motion. The
   bar is `target_bar()`; SET on a host (or alone) is `FifthsWheel.write(bar, inside)` there, and a
   guest's is the room ask `harmony` [bar, inside] (Session.ROOM_VERBS), which the studio answers
   with `FifthsWheel.answer` (a bar from 0 to BAR_MOST and a key that reads, else nothing). A
   marker is "at" the bar when it is within a millisecond of the bar's start
   (`DAWBackend.marker_key`). The board leans back 25 degrees on the table on a strut, at
   `Venue.wheel_spot()` (the bricks table's end nearest the control room, facing it, 6 cm in; null
   in the Rig Roulette room, which has no zones), placed by `FifthsWheel.on_stand`; a lamp on an
   arm over the board lights its face, which the table's own downlight misses. The cabin's table
   lantern moved to the table's far end. The studio stands it beside the harp
   (`Studio._stand_the_wheel`) and keeps `&"wheel"` in reach while a hand is on or over it or a
   chord sounds (`_follow_wheel`). The seat audit found the segments' shapes centred on the
   wheel's middle (a ray there hits the hub's middle), so each segment's shape sits at its own
   middle, and the arrows at 4 cm under 7 px, so they are 5.5 by 5 cm. The face-plane audit found the
   ledge and the board the same width, so the ledge is 12 mm wider. 103 checks in five tests
   (`_test_harmony_names_a_keys_chords_and_what_follows`,
   `_test_the_fifths_wheel_raises_the_key_and_what_follows`,
   `_test_the_fifths_wheel_sets_the_harmony_at_a_bar`, `_test_a_guests_set_is_asked_with_its_bar`,
   `_test_every_venue_puts_the_wheel_on_the_bricks_table`). Three probe checks on the host and two
   on the guest: the guest asks at 53.7 for `E minor: Em C G D` at bar 421, the host's room takes
   the ask from it with that bar and writes `[E minor: Em C G D]` there, and both sides' markers
   have it, with `Harmony.at` reading C in E minor in bar 422 and D minor's Dm in the bar before.
   shots/spatial9.png is the wheel in the stand-in's A minor after Am F C G were clicked onto the
   strip, with C, Dm and F risen after G and SET's card
   (`SHOT_CAM="3.14159,-0.25,1.0,4.95,1.3,4.1" SHOT_ARGS="--click FIFTHS_WHEEL__Am@40 --click
   FIFTHS_WHEEL__F@52 --click FIFTHS_WHEEL__C@64 --click FIFTHS_WHEEL__G@76 --aim
   FIFTHS_WHEEL__SET" tools/shot.sh shots/spatial9.png 160 166`), and shots/spatial9_side.png the
   same from the side, where the heights show.

## Notes

- Tilt bend and vibrato (#37) is next once slice 8 is in. `tilt()` is there, but MonitorSynth
  (DawKitTine), the native helper (native/keys.c), Session.Note and MidiTake all lack pitch bend,
  so it is a slice of its own. The desktop's tilt is the wiggle (slice 7).
- The shakers' gentle snap to the beat (#38) goes in HitRecorder's stamp, not before the sound:
  the hit is heard when played, and only the recorded note moves.
- The modular wall (#25) and the world into the modular (#31) are a third jack kind (CONTROL,
  0..1) and a surface of typed sockets. The venue instruments (#19), weather (#20) and the looper
  (#21) are new Jack sources. All of them are deterministic from the song clock, never from
  physics.
- A chord hand driving a bandmate's harp (#33 with #28) needs chord shapes: the hand's chord
  would retune their harp through a jack. Slice 6 builds the NOTE path it would ride on.
- A roll of Rig Roulette could write its key into the song's brackets. Today the roll's key is
  only its label.
- Handbells, like the hand percussion, are heard through Godot's mixer (its reported output
  latency, shown since slice 4), not the keys' fast path. Over 25 ms, they move to a MonitorSynth
  voice of their own.
- A cable from one guest into another is two trips late, and notes are not jitter-buffered. They
  are recorded at their `song`, so the take is right; only the sound is late.
- Bells are in none of Tour's pools, and their channel is out of its keys lanes. The harp's and
  fingertips' notes are keys, and count as keys.
- A bracket holds about twelve chords in MARKER_NAME_MAX (64).
- Fingertip notes from a bandmate are heard through a plug in their keys (TheirKeys), since a
  ghost has no hand pose. Sending a compact pose would let a ghost's hand show it.
- Only the local player's tracked tips strum the harp. A bandmate's strum arrives as their notes,
  never as their fingers.

# Part two

Goal: every kept idea that slices 1 to 9 did not build, built whole, on a desktop and in a headset:
#1 to #21, #23 to #28, #30, #31, #34, #35 and #39, and the rest of four that were started: #29 (the
wheel feeds the chord bricks), #33 (a chord hand drives a bandmate's harp), #37 (tilt bends and
shake wobbles, through the keys) and #38 (hand percussion shaken by a bare hand, snapped gently, and
found). Also what a desktop player could not find last time: the help card (F1) and the welcome card
name every instrument and its keys, the HUD fits at 1600x900, and every instrument can be reached
without hunting, at a desk and in a headset. Same rules as part one. `godot --headless --path .
--editor --quit` after a new class_name. The suite (`timeout 1200 godot --headless --path .
tests/tests.tscn`) at 0 failed with no SCRIPT ERROR (the 90 s in tools/verify.sh is too short now).
`flock ~/.cache/dawlings/shared.lock tools/session_probe.sh` at 0 failed on both sides when a slice
crosses the network. A shot of what changed, through tools/shot.sh, as shots/spatialN_*.png.

The order puts what is shared first. Finding things and getting to them (10, 11) go before the
things. One undo step per gesture (12) goes before every slice whose gesture writes two values.
Controls beside the keys (13, 14) go before anything that bends. Hits that play back as hits (16) go
before the hand percussion, the drums and the looper. The stage table (18) goes before what stands
on it: depth, leaning in, clapping to mute and the sidechain rope. Items made while playing (23) go
before cassettes, samples, the ear, the platter's scratch, chord bricks and the grain cloud. Section
blocks (29, 30) go before chord bricks, which drop onto them. Chord shapes (32) go before the chord
hand on a cable (33) and the talk box (58). Instruments that stand still (38) and strikes on the
fast path (39) go before the drums, the pads, the venues' instruments and the looper. The weather,
the venues' instruments and the looper go before the world plugs into the modular (53). Stations in
a real room (60) is last, when every station exists. Every slice leaves the suite green.

## Part two: decisions

- **Every instrument that stands somewhere is a station, and the stations are one list.** `Stations`
  (core/music/stations.gd, static) has a row per station: `id`, `title`, `area` (`control`, `live`
  or `venue`), `zone` (the Venue.ZONES zone it is mounted in, or empty), `air` (the free radius it
  needs round where it is played: 0.5 m for most, 1 m for the theremin), the Venue method that
  places it (`spot`), and two lines of help, `desk` (mouse and keys) and `hands` (hands and
  buttons). Slice 10 starts it with the harp, the bells and the wheel. Each later slice appends its
  own row. Four things are made from the list, so no slice can forget them: the help card's PLAY
  pages, the desktop's go-to, the headset's station board, and the suite's clearance loop. The loop
  is `_test_every_venue_stands_the_harp_clear` made general, in two kinds. A free-standing station
  (the harp, the theremin, the music box) keeps every check the harp's has: on the floor, off the
  footprint, clear of every zone box, every other station's solid and every item spot, with room to
  stand in front. A zone-mounted station (its `zone` set: the wheel, the section blocks and the
  ledge on the bricks table, the keyboard stand and the modular wall in the synth zone, the drum
  circle and the looper on the riser) is checked inside its zone instead, since standing in a zone
  is its point: clear of the zone's own solids (Venue.zone_solids) and of every other station
  mounted there, with its `air` free and a standing place in front on walkable floor. A venue with
  no room for a station (the Rig Roulette room has no zones) answers null, and all four skip it
  there. Things you carry (the shaker, the tambourine, the keytar, the bells, cassettes) are
  `Stations.HELD`: help lines only.
- **A desktop player goes to an instrument by name.** Every line of the help card's PLAY pages is a
  button, and a click walks there, so no station is found by cycling past the others. I walks to the
  next station and Shift-I to the one before, as F does to gear, for a player who has not opened the
  card. `Studio.go_to_station(id)` eases the walker to `Stations.seat(venue, id)`, 1.1 m in front of
  the station and facing it, on walkable floor. The glide is Studio._walk_to_seat's, scaled by
  `Ergonomics.motion_scale` (a cut at 0). God mode is left first. A toast says the title and the
  desk line. A station that is also a surface (the stage table, the EQ wall, the modular wall) is in
  both cycles, and G still brings a surface to you.
- **A headset player is taken to a station, in a blink.** A play space is about 2 m square, and the
  live room's stations are 3.4 to 7.3 m behind the mix position (Venue.ZONES), so walking cannot be
  the way, and XRRig today has only calibration, escape and the 2D view. `XRRig.travel(to)` moves
  the rig: an offset on the XROrigin3D, applied after the calibration (RoomAnchor), that puts the
  play space's centre at `Stations.seat` facing the station, so where you stand in your own play
  space is kept. It is a cut behind a 0.15 s fade to black and back (a plain cut at motion 0), never
  a glide: a view that moves under a still body is what makes people sick. Three things travel. The
  station board (`StationBoard`, on the desk at the mix position) has the PLAY pages' rows, each
  pressed by a poke, a pinch's ray or a trigger. Each station's plaque (`Stations.plaque`, a Label3D
  at its foot: its title and hands line, 30 mm letters, readable at 1.5 m) has two keys: INSTRUMENTS
  shows the board's rows beside the plaque, and BACK travels to the mix position. And the
  miniature's pins (slice 34). Presence already publishes the head in the session frame, so
  bandmates see you at the station. In a co-located room (two rigs calibrated to the same floor
  marks) travel is refused and the board says why: a body there has to stay where the others in the
  room see it. Gear still comes to you by G (FocusRig), and travel never moves a surface.
- **The desktop's keys.** I and Shift-I go to instruments. C turns the chord layer on and off
  (below). K held mutes the track under the cursor for as long as it is held, and a tap under 0.3 s
  latches it: the desktop's clap. L held listens: to a carried cassette or sample, as if at your
  ear, or by leaning in to the stage voice under the cursor. Z held points, and bandmates see the
  ray (Ctrl+Z is still undo). Enter while Z is held is "listen from there": not Space, which the
  walker polls as a jump. O puts a sticky note at the song time under the cursor. Alt with the mouse
  moving up or down bends the keys while a note of yours sounds. 4 to 9 strike the desk's six pads.
  [ and ] move the hovered section block. Backspace resets the hovered stage voice. No modifier gets
  a second meaning: Shift (or Ctrl) is fine everywhere, as docs/desktop_first.md has it. So the
  write bead is dragged itself rather than Ctrl-dragging its control, a stage voice's pan has its
  own keys on its tag, and the carve picks its track by where it is grabbed. A focused KeyCatcher
  (the keytar's piano, the fingertips) still takes its own keys first, and the studio's keys work
  only while no catcher has focus, as today. KeyCatcher stops giving keys held with Alt to the
  studio (only Ctrl and Meta stay the studio's), so a piano key plays while Alt bends, and a key let
  go always sends its note-off, whatever modifier is down.
- **The desktop's chord keys are a layer, not a third catcher.** Only one control has the keyboard,
  and J K L ; are the fingertips'. So the chords are `KeyCatcher.chord_keys`: while the layer is on,
  1 to 7 pick the degree (Shift adds the seventh, 0 goes back to the song's chord) in whichever
  catcher has focus. Both catchers' layouts leave the number row free (the piano's is letters, the
  fingertips' J K L ;). C turns the layer on. With no catcher focused, C also gives the fingertips'
  catcher the keys, so J K L ; play the fingertips and the mouse strums the harp. While the layer is
  on, a click does not take the keys away (`click_releases` waits for it to go off): C or Esc does,
  as T does for the fingertips. The HUD's focus field says `CHORDS · IV F`.
- **The help card has pages, and the HUD is one line that fits.** WelcomeCard keeps its name and
  gains pages. START: play, look and move, change things, record, keys and mic, F2 the 2D view (the
  precise way into everything, which every spatial control falls back on), Ctrl-Z and Ctrl-Shift-Z,
  and B to split. PLAY, built from Stations, one page an area: PLAY · HELD, PLAY · CONTROL ROOM,
  PLAY · LIVE ROOM and PLAY · THIS VENUE. A page that would not fit runs on to a numbered next one
  (`PLAY · LIVE ROOM 2/2`), so the card grows with the slices rather than failing its fit check.
  Each PLAY line is the station's title and desk line, and a click on it goes there. TOGETHER: host,
  join, cables into a bandmate, pointing, notes, listening from a spot. ROOM: walking, F and
  Shift-F, G, E, V, N, Q, R, 1 to 3, H, the text size, Tab (the stage manager, unchanged), rolling
  stands, the Comfort box. While open, the card holds the keyboard focus, so the walker stands still
  (it walks only with no focus owner). Left and Right, or Page Up and Page Down, turn the page. A
  click on a page's name goes to that page, a click on a PLAY line goes there, and a click anywhere
  else, Esc or F1 closes it, as now. The suite generates every page at text scale 1 and holds each
  to 1600x900 less the margins. The HUD keeps who you are and what is focused, and says where the
  rest is: `dawlings | host / screen | <DAW> | 8 tracks | CONSOLE | F1 help · F2 2D view · I
  instruments · M session`. It is cut to 1568 px at 13 px for the longest DAW summary and venue
  title. The long list moves to the ROOM page. In a headset, the same rows are the station board.
- **One undo step per gesture is an edit group, not timing.** OfflineBackend._remember folds a write
  into the last step only when its key is the same and within GESTURE_MS. A drag that writes two
  values (pan and volume, a send and a threshold, an EQ band's gains) alternates keys, so it makes a
  step almost every frame. `DAW.open_edit(name)` and `DAW.close_edit()` bracket a gesture. On
  OfflineBackend (and so the built-in engine), every _remember while an edit is open folds into the
  edit's one step, whatever its key: named `name`, its `back` the backs in reverse, its `again` the
  agains in order. A gesture's let-go closes it. So does a quiet EDIT_IDLE (10 s) or the player
  leaving, so a lost let-go cannot hold history open. An undo or redo ends an open edit's step and
  keeps the edit, so a hand still dragging makes one fresh step, not a step a frame. A guest's open_edit and close_edit are
  intents like the edits between them, and the host keeps one open edit per peer: another player's
  write in between is a step of its own, and the edit's step stays where it began. On Reaper, the
  bridge's verbs inside an edit are sent as one `Batch` request inside one Undo block. Plain control
  writes there (OSC pan and volume) stay Reaper's own undo points, one per control, and the slices
  that make them say so. Capability EDIT_GROUPS. Every slice that writes more than one value per
  gesture uses it: the stage, the rope, the bead, the carve, MAKE SECTIONS, the music box's drag.
- **Eight new DAW verbs, each saying where it cannot go.** Four are edits, one undo step each:
  `set_track_width`, `paste_item`, `arrange_sections` and `set_lyrics`. Four are not: `open_edit`
  and `close_edit` (history, above), `scrub(seconds, speed)` (transport) and `hold_lane(track,
  target, on)` (a lane stops following while a write bead is out). Each is in DAW.COMMANDS, has a
  DAWBackend.Capability (WIDTH, PASTE_ITEMS, ARRANGE, LYRICS, EDIT_GROUPS, SCRUB, LANE_HOLD), and is
  built on OfflineBackend (which the built-in engine extends) and on ReaperBackend through a handler
  in reaper/dawlings_bridge.lua, an edit inside one Undo_BeginBlock. Each edit replicates as the
  state it changes. Everything else reuses a verb that exists: the rope is create_sidechain,
  set_send_volume, set_fx_param, remove_send and remove_fx; the bead's pass is set_automation; the
  carve is add_fx and set_fx_param; MAKE SECTIONS is add_region inside an edit; the music box is
  insert_note and delete_note. A backend without one of these answers false, and the control that
  would use it says so in its hover card ("spectra need the built-in engine"), as the bank readout
  does.
- **Controls ride beside the keys, not on them.** Pitch bend, the mod wheel (CC 1) and expression
  (CC 11) are `Session.send_control(kind, value, song, source)`, on a channel of their own
  (CONTROLS_CHANNEL), unreliable but ordered. Notes stay reliable on KEYS_CHANNEL, so a lost control
  never holds a note-on back behind its retransmit (the head-of-line delay MixFeed's notes warn of).
  The host passes those three controllers and refuses any other, with `value` clamped by kind (bend
  -8192 to 8191, CC 0 to 127). A lost one costs little: a bend off centre is sent again at least
  every 50 ms, and both ends put the wheel back to centre when the player's last note lets go, a
  rule each applies to the notes it already has, so no reset has to arrive. GuestMidi gains
  `control(kind, value, source, at)`, and its `_input` reads a hardware keyboard's pitch wheel and
  CC 1 and 11 as well as notes and the pedal. Controls sound on the keys' synth (MonitorSynth, then
  DawKitTine.control, which already bends; the native helper gains `bend V` and `cc K V` lines, in
  the style of its `on` and `sus`), are sent, and are taken down as the take's controls on channel
  0. `insert_midi_take` gains them. DawKitTine plays the bend and 11 and ignores 1, which is kept
  for the track's own instrument on Reaper.
- **A player has one pitch wheel, as a keyboard does.** MonitorSynth has one DawKitTine voice for
  every source, TheirKeys one MonitorSynth per peer, and ChordHarp.heard one synth for every
  bandmate. A bend per source cannot be heard per source without a voice per source, so it is not
  attempted. The wheel belongs to the source of the player's newest held note
  (`GuestMidi.wheel_source`). Only that source's controls are played and sent (a hardware keyboard's
  wheel is the plain keys' source, `&""`), and another source's tilt is ignored until it owns the
  wheel. So the harp hand, the keytar hand and a hardware wheel never fight, and the return to
  centre at the player's last note-off is the one reset there is. The bend range is
  DawKitTine.BEND_SEMITONES, two. Anything that glides further (the theremin) hands one note on to
  the next, legato, at the edge of the range.
- **A tilt is measured from where the note began, unclamped.** Slice 7 found a bare hand level palm
  down and a controller level thumb up, a quarter turn apart. HandPose.tilt_of clamps the absolute
  roll and pitch to TILT_MOST (45 degrees), so a bend read from it saturates for a hand that starts
  past 45 degrees, such as a hand plucking the harp palm sideways. So `HandPose.angles_of(basis)`
  answers the same roll and pitch in radians, unclamped (tilt_of becomes that, clamped, so nothing
  else changes), and Interactor gains `tilt_angles()` beside `tilt()`. A bend takes the roll's
  change since its note's press, wrapped to ±180 degrees, as `d`: `bend = sign(d) * clamp((abs(d) /
  45 - 0.08) / 0.92, 0, 1) * 2` semitones, a dead zone of 0.08 and two semitones at a 45-degree tip.
  So "tip it from where you started" means the same in either hand, from any start, and with the
  mouse's wiggle.
- **Things made while playing are spawned items the host makes, and their data travels once.**
  Cassettes, sample cassettes and chord bricks exist only once somebody makes them. They use the
  spawn system ItemRoom already has for Tour's spills and personal copies (`spawn`, `despawn`,
  `spawned_ids`, and `apply` making real on a guest what it has not met), not a second one.
  `ItemRoom.mint(kind, data)` on the host (not `make`, which is the existing factory by kind) picks
  the next free id in the shape the room already reads, `cassette7` or `brick3`, so `kind_of`,
  `look_of` and a ghost's carried look are right. It spawns the item at its home (the rack, the
  ledge). Where it lies is ordinary room state. What it carries is not: the host keeps every made
  item's data in `Session.made` {id: [kind, maker, bytes]}, sends each once to everyone on a
  reliable message of its own (`_made`), and sends all of it to a guest as it joins. `room_state()`
  names only the ids, so a put-down, a throw or a plug never resends a clip (publish_room sends the
  whole room on every ask). `data` is a Dictionary, packed by var_to_bytes, of at most MADE_BYTES
  (256 KiB) an item and MADE_TOTAL (4 MiB) a room, and there are at most MADE_MOST (64) items. Notes
  and controls pack as PackedFloat32Array. An audio clip carries its source's name, never its peaks,
  and the cassette draws them from the file where this machine has it. A guest asks with the room
  verb `make` [kind, what it is made from: a clip's track and item index, or a chord], never its
  data, so the host packs the data from its own state. The guest holds a ghost of it in its glove
  until the row arrives or is refused, as `plug` is predicted. Made items pocket, throw, catch,
  shelve and are handed over like any item. They are retired by the BIN on the cassette rack. The
  host remembers its room's made items with its layout, as it remembers tablets.
- **Some furniture holds items in slots.** An item lies only on reachable floor, never on the gear,
  and `ItemRoom.state()` knows floor, hand, head and pocket. A fifth place is added: `{id: ["slot",
  holder, n]}`, asked with the room verb `slot_item` [id, holder, n] and predicted as `put_item` is.
  Holders are `ItemRoom.holders` {holder: [Transform3D per slot]}, filled by whatever builds the
  furniture: the cassette rack (`rack`, 12), the bricks ledge (`ledge`, 16), the platter (`platter`,
  1) and the grain cloud's bowl (`bowl`, 1). An item let go within 8 cm of a free slot goes into it,
  a taken slot refuses and says so, and `apply` lays a slotted item there on every machine. Only
  made items take slots. Let-go keeps the meaning it has on XRInteractor's grip (put down, slot or
  throw): pasting is a press, never a let-go.
- **A clip packs what makes it sound.** MixWire's item packing (`_pack_items`, made public as
  `pack_item`) carries a MIDI item's notes and controls, or an audio item's source with its offset,
  fades, gain and loop. The built-in demo song's items have neither: each is a window in which its
  track's part sounds (DemoSong.role_of the track's name). So a demo item packs as its `part` (the
  role) and its window. ItemState gains `part` (empty for every other item), and GodotBackend plays
  an item's own `part` where it has one, before its track's. A demo cassette pasted onto another
  track plays the part it was pulled from. At the ear and in the grain cloud it is
  DemoSong.render_window of that part. On Reaper there are no parts, and pasting one is refused with
  the reason (`a demo part plays only on the built-in engine`).
- **Every sound has a path and a budget.** MonitorSynth's header puts Godot's mixer at 30 to 50 ms
  against 4.5 ms for the native helper, and 10 to 20 ms as where an instrument stops feeling like
  yours. So each new sound says which path it takes, and its tag shows the figure (slice 4's
  readout). Pitched things played by hand (the harp, fingertips, keytar, strings, theremin) are the
  keys: the helper where it runs. Things struck (shakers, hand drums, pads, the venues' instruments,
  the looper's pad) are heard on MONITOR at once, as today, and slice 39 puts local strikes on the
  helper too: one-shot voices of Foley's sounds, loaded once and fired by a line, about 5 ms on top
  of the tracking's own. The modular is played from the keys, so its arithmetic is C in the helper,
  as the tine's is, with the same arithmetic in GDScript for recording and for bandmates, checked
  equal through the helper's `--render` as the tine is. Where the helper cannot run, all of these
  play through Godot, and the tag says so. The grain cloud and the platter's scratch are textures
  heard by one player, through Godot at its figure, said on their tags. The talk box is a sung voice
  through a mic: the mic's input latency, 11 ms for a 512-point analysis, and Godot's output, about
  60 ms, said on its tag. Its player hears it late, and the take is placed by the voice's own
  capture estimate (GuestAudio's), so the recording is in time.
- **An instrument that does not move is still an InstrumentItem.** A drum head, a chime or a pad on
  your desk is an InstrumentItem with `fixed` true. A grab plays it rather than picking it up, and
  its home is its station. So it keeps everything an instrument has: heard at once on MONITOR,
  `item_hit` with its `song`, HitRecorder, its jack, a bandmate hearing it from where it stands.
  `Strike` (core/music/strike.gd) finds the strikes. It reads each local tracked hand's fingertips
  and palm (HandGestures), each controller's tip (XRRig.tip_of) and grip point, and each poke. It
  counts a crossing of a head's plane, inward, faster than STRIKE_MIN (0.4 m/s), with velocity from
  the speed (InstrumentItem.velocity_for), and only from a hand tracked with confidence on both
  frames, so a hand that drops out and reappears on the far side is no strike. A mouse click is 96,
  Shift-click 64. Where on a head it was struck is a `zone` (bass, tone and slap on a drum; which
  drum on a pad). `played`, `ItemRoom.played`, `Session.send_item_hit`, `item_hit` and `heard` gain
  `zone`, as slice 4 gave them `at`.
- **Two more kinds down a jack, and the world into the modular is a patch, not a jack.**
  `Jack.Kind.CC` carries a pitched source's controls down a cable into a player (`pitch` the
  controller, `velocity` the value), beside its notes. `Jack.Kind.CHORD` carries a chord hand's
  chord (slice 33). Session._pass_jack clamps by kind, not every event to 0..127: notes and triggers
  0 to 127, CC `pitch` 1, 11 or 128 (DawKitClip.PITCH_BEND) with `velocity` -8192 to 8191 for the
  bend and 0 to 127 otherwise, CHORD as slice 33 says, and a kind past CHORD refused. As in part
  one, a jack is a row in the room, never a send, and maps one source to one sink. That is why the
  world does not reach the modular by jack: the weather recording onto a track could not also drive
  a filter. The world's outputs (`world:weather`, `world:drips`, `world:venue`, `world:ring_N`,
  `world:marbles`) are sockets on the modular's own patch (`modular` cables [from, to], slice 51),
  beside the modules' outputs, so a source's jack row and its modular cables are independent. A
  venue instrument's set is one jack source (`venue`), however many items it has, with one socket on
  its stand.
- **Markers carry notes; lyrics are the project's notes.** A sticky note is a marker whose name
  begins `NOTE ` (`Harmony.NOTE_PREFIX`). `Harmony.parse` answers null for one, so Harmony.at and
  everything it feeds (the harp, the bells, the wheel, the fingertips, the venues' instruments, the
  weather) never read a note's brackets: a note saying `try [G major] here` changes nothing. Every
  place that reads a marker as a section skips it, just as `section_of` strips brackets. That is
  ChalkVenue.board_from, TapeDeck.section_at and its PREV/NEXT text, the 3D ruler's flags (which
  draw a note as a pinned card instead) and the region page's ADD name. The 2D ruler shows the whole
  name, as it does every marker's. So notes undo, replicate, save to Reaper and .dawproject, and are
  edited on the 2D ruler, with no new verb. A note that would land within a millisecond of another
  marker is put a millisecond after it (one marker per time). Lyrics are not markers: forty lines
  would bury the ruler. They are the song's LRC text (`[01:23.40]line`), in MixState.lyrics, written
  by `set_lyrics`: Reaper keeps them in the project notes, and .dawproject in the project's metadata
  comment.
- **What is personal stays in your ears.** A cassette at your ear and a cassette scratched on the
  platter play on this player's MONITOR, never the mix, and change no DAW state. Leaning in to a
  stage voice works only where this machine plays the tracks: a host on the built-in engine. Ears
  has a gain per bus, not per track, and a track's own bus feeds the master that MixFeed streams to
  guests, so a lean cannot touch it. Instead `Ears.lean(track)` asks GodotBackend for that one
  track's cue (set_cues: a third player of its part, pre-fader), sets the cue to the track's own
  fader level plus 6 dB, and lowers Mix by 6 dB, with headphones on or off. A guest hears only the
  host's stereo stream, and a host on Reaper hears Reaper, so neither can lift one track: the
  voice's card says so, and nothing changes.
- **The world's music is a function of the song clock and the room.** Rain, drips, marbles, rings
  and ropes never put physics into mix state. A raindrop is a hash of (bar, sixteenth, seed). A
  marble's path is a walk of the placed blocks, a cell per sixteenth. A rope's sag is drawn, and its
  pull is a send level. Every machine with the same markers, tempo and room rows hears the same
  drops and marbles, so only switches and rows cross the wire.
- **Every switch a bandmate can see is a room row, and a choice about your own playing rides on what
  it is about.** The music box's TRACK, LENGTH, root and SCALE, the looper's arm (who is recording
  and from which bar), the sampler's REC, the weather switch, and the grain cloud's KEY switch are
  room rows, asked and predicted. "Snap hand percussion" is the player's own: each hit carries its
  `snap` flag, and the host's HitRecorder snaps a guest's hit by it.
- **Gestures do not collide.** Two bare fists held for ESCAPE_HOLD are the way out (XRRig), so a
  hand carrying something (a shaker held in a closed hand) does not count toward it, and the chord
  hand's "no shape" is an open hand or one lowered, never a fist. Chord shapes count only with the
  fingers pointing up (pitch over 0.6 of TILT_MOST). Pointing is the index held level along the
  forearm (HandPose `pointing`, pitch within ±0.3), so degree I and a point are told apart by where
  the finger points. A controller's thumbstick nudges what that hand hovers (XRInteractor), so the
  chord stick is a mode: a click of the chord hand's stick turns it on (the glove says CHORDS) and
  off. While on, the stick picks a degree and latches it, so the chord holds when the stick springs
  back, and the stick nudges nothing. Pointing on a controller is the other hand's stick click,
  held.
- **Motion has a setting, still means still, and nothing large moves.** Everything that moves by
  itself (signal beads, venue breathing, the sky's moon, marbles, the music box's cylinder, looper
  rings, the platter's label) is scaled by `Ergonomics.motion_scale`. At 0 it shows its state
  without moving: a step per beat or section, a filled bar, a brightness. Nothing that fills the
  view moves: the sky stands still and a moon crosses it, and the looper's rings turn on their
  stand, not round the player. Nothing flashes: a clip lifts the room's practicals 30% for 0.15 s,
  at most once every FLASH_GAP (2 s), however often it clips. Slice 21 gives the setting a place in
  the session panel (COMFORT), saved with the body.
- **In AR the stations stand where the player puts them.** The harp and the wheel are null in AR
  today, since the room is a real one, and by that rule every station in part two would vanish
  there, the drum pads on real surfaces among them, which suit AR best. The pads are this machine's
  and work in AR from the start (slice 41). Every other station answers null in AR until slice 60,
  which lets the AR room's host place any station on its real floor or a real surface (a room row,
  as a placed surface is), and the PLAY page meanwhile says `place it (AR)`.
- **New code in new files, as before.** studio.gd, session.gd and presence.gd get small additive
  edits. Tests are appended to tests/run_tests.gd with their calls appended to `_ready()`. The shelf
  check's count (`ItemRoom.KINDS.size() - 18`) and its comment change only where a slice adds shelf
  kinds (the hand drums are fixed and not on the shelf, so they are counted out by name, and made
  items are never KINDS). Hands only, never feet. No state is shown by colour alone.

### Room layout

- **Neighbourhoods, not a strip.** Twenty stations put in whatever gap was left had ended nose to
  tail along the live room's back wall, too close to walk between (2026-10-28, "EVERYTHING is way
  too cramped"). The room is now organised by what you do in each part of it: MIXING (the control
  room's ring round the seat), RHYTHM, HARMONY & STRINGS, SYNTH & SOUND DESIGN, VOCALS and TAPE &
  TOYS, each a cluster round a middle its stations face, with a banner over it naming it
  (`Neighbourhoods`, docs/architecture.md "Room layout"). A new station joins a neighbourhood's
  row in `Neighbourhoods.ALL` and stands from its zone in the venue, never in a leftover gap. The
  harmony and synth banners are one behind the other from the desk, so they hang at different
  heights (a row's `lift`): at one height their long titles ran together.
- **Bigger, together.** The control room is 11.2 x 8 m under 3.6 m and the live room 17.6 x 8.4 m
  under 5 m, through the shared constants, so every venue grew at once; outdoor venues got more open
  ground with them.
- **Measured clearances.** 0.6 m between pieces, a 1.2 m walkway between neighbourhoods, 0.8 m clear
  of the console but for what is played from the seat, and every seat reached down a 0.9 m walkway,
  in every venue and arrangement; held by the suite, and drawn by tools/layout_map.py.
- **Room for what is next.** The booth is 3.4 x 3.1 m with a 1.2 m door: the talk box (slices 58
  and 59) stands in it beside the mic.

### The second review (36 points), checked against the code

Each was checked against the code named in it, and every one stands. Accepted, each fixed in the
decision or slice named: 1 (no way to move in a headset: the travel decision, slice 11), 2 (no
single undo step for a two-value drag: edit groups, slice 12), 3 (EQ6 has no frequency or width: a
21-band kind and a narrower promise, slice 37), 4 (`make` taken, `cassette_7` breaking `kind_of`, a
second spawn system: `mint` on the existing spawn, slice 23), 5 (the whole room resent on every ask:
made data sent once on its own message, knobs on a stream, slices 23 and 51), 6 (MADE_BYTES refusing
ordinary clips: 256 KiB, float32 packing, no peaks, slice 23), 7 (demo items with no notes or
source: parts, slice 23), 8 (one voice per peer: one wheel per player, slice 13), 9 (tilt clamped at
45 degrees, and the dead zone ignored by the test: `angles_of` and the formula, slice 15), 10 (Alt
dropped by KeyCatcher, the wiggle zeroed over the harp: slice 15), 11 (the hardware wheel dropped,
the jack clamp: slice 14), 12 (controls behind notes on a reliable channel, a thinning rule that
keeps everything: CONTROLS_CHANNEL and an AND rule, slices 13 and 14), 13 (no latency budget: the
decision, slices 39 and 51), 14 (the talk box neither rendered by bandmates nor heard, and EQ21's
bands: the decision, slices 58 and 59), 15 (Ears has no per-track gain: a cue on a built-in host,
slice 19), 16 (spectra on cue buses, pre-fader: the track bus's tail, scaled by the fader, slice
36), 17 (distance making sends, a stage over the timeline, no banks: the stalk, the stage table,
banks, slices 18 and 19), 18 (D_WIDTH ignored in balance mode, the enhancer's slot: I_PANMODE and
the bus's tail, slice 18), 19 (the bead's touch pass ending when still, wrapping, landing late, a
verb not listed: the bead's own song-stamped points through set_automation, and hold_lane listed,
slice 22), 20 (pointing already published: extended, slice 35), 21 (a note's brackets read by
Harmony.at: `parse` answers null, slice 35), 22 (fists as escape, degree I as a point, the stick's
nudge: the gestures decision, slices 17 and 32), 23 (one keyboard focus: the chord layer, slice 32),
24 (Space jumps, the card's keys walk and close it, Tab is the stage manager's, Shift and Ctrl
overloaded: the keys decisions, slices 10, 18, 22, 35 and 37), 25 (F2 and Ctrl-Z missing, PLAY too
long, cycling to reach a station, no headset index: slices 10 and 11), 26 (too much in the synth
zone and on the table, zone stations failing the harp's checks: two kinds of clearance, the theremin
and music box free-standing, slices 10, 30, 47 and 50), 27 (no slot state, paste on let-go: slots
and paste on a press, slices 23 and 24), 28 (the take is per machine, REC unreplicated, a WAV per
hit: the take on the wire, a sample a press, slice 26), 29 (hits played back as tines: slice 16), 30
(subsonic strings: a new law, slice 48), 31 (knobs, patches and grains unstamped or lossy: stamped
and reliable on a channel of their own, slices 51, 52 and 55), 32 (a jack source per chime, one sink
per source, no drips: one source a set, the world into the modular as patch cables, drips in the
cave, slices 42, 44 and 53), 33 (snap, the music box and the looper unowned: the flag on each hit
and room rows, slices 17, 45 and 47), 34 (a clip strobe, rings within reach, a turning sky: the
motion decision, slices 21, 46 and 57), 35 (no controller pad marking, tracking dropouts, AR: slices
17, 38, 41 and 60), 36 (slices too big, a step per marker, verbs miscounted: slice 11 is now 13 and
14, slice 34 is now 38 and 40, MAKE SECTIONS is one edit, and the verbs decision lists eight).

Taken in part. 13: the grain cloud, the platter's scratch and the talk box stay on Godot's mixer, at
a figure shown on their tags. They are textures or heard by one player, and a native granular voice
or vocoder would be a second implementation of each for little gain. 15: a guest still cannot lean
in. It would need a stream per track from the host, and that is not part two. 29: on Reaper a
recorded hit plays through whatever instrument its track has, which is the user's choice, as for any
MIDI. 35: hand tracking at drum speeds cannot be fixed here. Holding survives a dropout, strikes
need confident frames, and the plaques suggest controllers for fast parts. 31: grain and knob events
are reliable on a channel of their own rather than unreliable, so the host's render equals the live
one. The cost is that a retransmit holds back later grain or knob events, never notes. Rejected:
none.

## Part two: plan

10. [x] **Stations, a help card that names them, and going to them at a desk.** No new idea. It is
    what makes every later instrument findable. `Stations` as decided: `ALL`, `HELD`, `spot(venue,
    id)`, `seat(venue, id)`, `ids(venue)`, `by_area(venue)`, `plaque(id)`. The harp, the bell stand
    and the wheel become its first rows (`Studio._stand_the_harp` and `_stand_the_wheel` read their
    spots through it, unchanged; the wheel's row names the `bricks` zone). `HELD` has the keytar,
    shaker, tambourine, the bells as held, the fingertips (T) and the jacks (P, Shift-P).
    `Studio.cycle_stations(direction)` on I and Shift-I, and `go_to_station(id)` with the toast.
    WelcomeCard gains PAGES, the generated PLAY pages, `page_size(page)`, the focus it holds while
    open, Left/Right and Page Up/Down, and clickable page names and PLAY lines. bootstrap.gd's HUD
    becomes the short line, both builds. The plaques go under the harp, the bell stand and the wheel
    (their keys come in slice 11). Touches stations.gd, welcome_card.gd, bootstrap.gd, studio.gd,
    chord_harp.gd, fifths_wheel.gd and handbell_item.gd (their plaques). The suite checks: every row
    has a title, an area, a desk line and a hands line; the PLAY pages name the harp, bells, wheel,
    P and Shift-P, T, the keytar, the shaker and the tambourine; START names F2, Ctrl-Z and B; each
    generated page's measured size is within 1600x900 less 2 x 28 px margins at text scale 1, and an
    area padded with 40 synthetic rows runs on to numbered pages that each fit; the HUD's measured
    width is under 1568 px at 13 px for host, guest and solo, screen and vr, with a 60-character DAW
    summary and the longest venue title, and it names F1, F2, I and M; with the card open, Right
    held for 0.5 s turns the page and leaves the walker where it was, and a click on a page's name
    changes the page without closing the card; a click on the harp's PLAY line walks to the harp's
    seat; I three times walks to the harp, the bells and the wheel, a fourth comes back round, and
    Shift-I goes back; the walker ends at each seat facing its station within the walkable floor.
    `_test_every_venue_stands_every_station_clear` replaces the harp's loop: free-standing rows keep
    every check the harp's had, and zone-mounted rows (the wheel) take the zone checks, for every
    venue and variant. shots/spatial10_help.png is the PLAY page and shots/spatial10_goto.png the
    view after I.

    Built. `Stations` (core/music/stations.gd) is static; a stood row also carries `at` (the point
    looked at, in its frame) and, free-standing, `foot`, `foot_z` and `top`, so `Stations.solid` is
    exactly the solid the venue gives it (`ChordHarp.solid`, `HandbellItem.stand_solid`). Every
    station's front is its frame's +Z. `Stations.seat(venue, id, fits)` is SEAT (1.1 m) in front
    when a person fits there; given the walker's `fits`, it comes in along the front toward
    NEAREST (0.45 m) and then tries either side. In the studio the bricks table stands between the
    harp and 1.1 m, so the harp's seat is 0.8 m in front of its strings, between the table's end
    and the plinth; the wheel's is pulled in too. So the look is framed from where the walker
    actually stands (`Stations.look_from(venue, id, eye, fov)`): each stood row gives `frame`, its
    controls' top and its foot (the plaque's bottom), and the look tips from `at` only as far as
    it takes to hold both inside the room's 58-degree lens (the top 8 degrees in, under the HUD's
    line and the toast, the foot 3), the top alone where both do not fit. At the harp's 0.8 m they do not: its crown (the chord readout and both 8va buttons)
    stays in view and its plaque, which a headset reads close up, falls below the frame; the
    desktop has the toast's same lines. `_test_going_to_a_station_holds_its_controls_in_view`
    projects the crown and both buttons from the harp's seat in every venue and variant, below the
    top 110 px. `Stations.HELD` is six rows: the keytar, the shaker, the
    tambourine, a bell in hand (`bells_held`), the fingertips (T) and the jacks (P, Shift-P). The
    plaques (`Stations.plaque(id, width)`: a dark plate, the title and the wrapped hands line, both
    30 mm) stand on a leant plate at the harp's plinth, on the bell stand's front and hung on the
    bricks table's end under the wheel. `Studio.cycle_stations` wraps round (F's cycle walks off
    its end instead; Esc is the way back here, and every toast says so), and `go_to_station` stands
    the monitor's panels down and moves the body as a visit to gear does, so Esc's `_sit_down`
    walks home. The glide is `_walk_to_seat`'s curve at STATION_PACE (4 m/s, 0.55 to 2 s) times
    motion_scale. In a headset `go_to_station` refuses with a toast of where it stands and its
    hands line until slice 11's travel. WelcomeCard wraps its own lines (`_wrap`) so a page
    measures the same out of the tree, and `page_size` is the built panel's minimum size. The row
    of names has one a section (a run-on page is `PLAY · LIVE ROOM 2/2` in its heading and counter,
    and its section's name goes to its first page), the page's own boxed as well as lit. The
    wheel turns pages too; every other key is swallowed while the card is open but F2, which the
    2D view (later in the tree) hears first: its opening puts the card away (bootstrap). PLAY ·
    HELD's subtitle (`WelcomeCard.HELD_HOMES`) says where each kind is kept: the keytar, the shaker
    and the tambourine on the prop shelf, the handbells on their stand beside the harp, the
    fingertips and the jacks always on you. The PLAY line
    under the cursor gets an arrow and the pointing-hand cursor. The HUD is
    `bootstrap.hud_text` in both builds, with the venue's title and the focus field (the focused
    surface, else WALKING or FLYING); it shortens the DAW summary, then the venue's title, with an
    ellipsis. tools/screenshot.gd gained `--stations N` and `--help-page LIVE`. The suite's
    `_test_the_welcome_card_opens_on_f1_and_is_seen_once` waits a frame before its click, which
    now has to land outside the laid-out card. shots/spatial10_help.png, shots/spatial10_goto.png
    (`--stations 1 --no-motion`), and shots/spatial10_wheel.png (three presses of I).

11. [x] **Going to a station in a headset.** No new idea; it is how a headset player reaches every
    later one. `XRRig.travel(to)` and `travel_home()` as decided: an offset on the rig after the
    calibration, a 0.15 s fade (a black sphere round the head) or a cut at motion 0. `StationBoard`
    (hardware/station_board.gd) stands on the desk at the mix position, its rows from Stations by
    area, pressed by a poke, a pinch's ray or a trigger, and says on its face "press a row to go
    there · BACK on any plaque comes home". The plaques gain INSTRUMENTS (the board's rows beside
    the plaque, until one is pressed or INSTRUMENTS again) and BACK. Travel is refused in a
    co-located room, with the board saying why. Touches xr_rig.gd, station_board.gd, stations.gd
    (plaque keys), studio.gd, tools/probe/session_probe.gd. The suite checks: a travel puts the
    simulated head (--xr-sim) at the seat facing the station within 5 cm, keeping the head's offset
    from the play space's centre; BACK returns to the mix position; the fade runs, and at motion 0
    there is none; a co-located session refuses; the head published to Presence is at the station;
    the board's rows are the PLAY pages' stations; every plaque's keys and the board's rows pass the
    seat audit. The probe checks that a guest's travel puts its ghost at the harp's seat on the
    host. Both sides at 0 failed. shots/spatial11.png is the station board on the desk.

    Built. `XRRig.travel(to)` levels `to` to its yaw and floor point and puts the XROrigin3D there,
    so the head keeps its tracked offset (and turn) inside the play space; `travel_home()` puts it
    back at `home`, which in VR is the mix position (`XRRig.settle`: the studio centres a VR play
    space at (0, 0, MIX_POSITION_Z) as it builds the rig, where it had stood at the room's origin
    inside the console's carcass; passthrough keeps its own floor), so the board is in view from
    it. Both close a veil first (a black sphere of 25 cm round the head, unshaded, drawn
    through everything at the top render priority, on Mirror.NOT_REFLECTED only) over FADE, 0.15 s,
    cut under it fully black, and open it over FADE; at motion 0 (`Studio._travel_fade`) it is a
    plain cut and the veil is never drawn. A travel under way is overtaken from where its veil is.
    `travelled` fires at the cut and `BodyFrame.recentre` takes the new yaw whole, so summoned gear
    does not swing round after you. RoomAnchor is never moved: floor marks taken while away go
    through `untravelled` to where they are with the play space at home. `RoomAnchor.marked` says
    the frame came from real floor marks (`adopt_virtual_frame` clears it), and
    `Studio.co_located` is that with another headset (AR or VR) in the session; then
    `travel_refusal` says why and `_travel_to_station` refuses: every board letters `CAN'T GO ·`
    and the reason on its face for 8 s, and a toast says it too; the rows beside a plaque stay up
    when refused, so the press is answered where it was made, and go only on a travel. BACK still
    comes home, and at home already its toast says so. In a
    headset `go_to_station` travels to the desktop's own seat (`Stations.seat` with a walker's
    `fits`: a Walker kept out of the tree, `_seat_finder`, where there is no walker), letting
    focused gear go first, and the toast says the hands line and that BACK comes home.
    `StationBoard` (hardware/station_board.gd) stands on a post by the desk's left end
    (`Studio.BOARD_AT`, turned 38 degrees to the seat, in view from it), a floor plan fixture, and
    moves beyond a desk spread wide enough to reach it (`_place_station_board`, on the console's
    `rebuilt`): the 40-track desk is 2.5 m wide, and the seat audit found the board standing
    between the seat and strips 10 to 13. Its face leans back 35 degrees: INSTRUMENTS, "press a row
    to go there · BACK on any plaque comes home", each area's name and its rows
    (`StationBoard.rows_for`, Stations.by_area in the card's order), 32 by 6.2 cm, and room for two
    lines of refusal. A row is pressed by anything that presses (poke, pinch ray, trigger, click,
    dwell), and its hover card says where it is and how to come back. On a desktop a row walks
    there. `Stations.plaque` gained a row of two keys under its lettering (StationBoard.PlaqueKey,
    7 cm tall, at most 24 cm wide, the plate growing down by PLAQUE_KEYS_ROW, so each station's
    `frame` foot moved down to the new bottom); a key finds the studio by walking up to an ancestor
    with `plaque_key`. INSTRUMENTS stands a `compact` board (rows only) beside the plaque, top
    level with it, on its lean; INSTRUMENTS again, or a row, takes it down (hidden and out of the
    physics space at once, freed at the frame's end, since the press may be its own). BACK is
    `Studio.go_home`: travel home in a headset, Esc's walk on a desktop. `Presence.head_in_session`
    is what `_publish` sends. The help card's START line for instruments names the board and BACK.
    tools/screenshot.gd gained `--plaque-rows`. Tests: `_test_a_headset_travels_to_a_station_and_back`,
    `_test_a_co_located_headset_stays_where_it_is_seen`,
    `_test_the_station_board_is_the_play_pages_and_its_rows_go` (every venue's rows against the
    card's PLAY lines), and the seat audit checks the board's rows and every plaque's keys are among
    what it audits at 13 and 40 tracks. The probe's guest stands a simulated rig in the session's
    frame at 53.8 and travels to the harp's seat in the room's venue (plain `Stations.seat`: no
    furniture stands round it there), and publishes the head as Presence would; the host finds it
    there by 55. shots/spatial11.png is the board by the desk; shots/spatial11_plaque.png the rows
    beside the harp's plaque (`--stations 1 --plaque-rows --look -0.3,-0.8`).

12. [x] **One undo step per gesture.** No new idea; the stage, the rope, the bead, the carve and
    MAKE SECTIONS need it. `DAW.open_edit(name)` and `close_edit()` as decided: OfflineBackend's
    open edit folds every `_remember` into its step; ReaperBackend sends an edit's bridge verbs as
    one `Batch` inside one Undo block. EDIT_IDLE closes a forgotten edit, and an undo closes one
    first. A guest's edits are intents, with one open edit per peer on the host, closed when the
    peer leaves. Capability EDIT_GROUPS. ControlAffordance gains `edits_as_one`, for controls whose
    drag writes two values: it opens an edit on grab and closes it on let-go. Touches daw.gd,
    daw_backend.gd, offline_backend.gd, reaper_backend.gd, dawlings_bridge.lua,
    control_affordance.gd, session.gd (a leaving peer's edit closed). The suite checks: a 60-frame
    diagonal drag of pan and volume inside an edit is one undo step that restores both, and without
    an edit a single fader's drag still folds by GESTURE_MS as before; another peer's write in
    between is a step of its own; EDIT_IDLE closes; an undo inside an open edit closes it and undoes
    it whole; the bridge decodes Batch and runs it in one block (tests/bridge_decode_test.lua). The
    probe checks that a guest's two-value drag inside an edit is one step in the host's history.
    Both sides at 0 failed.

    Built. `DAW.open_edit(edit_name)` and `close_edit()` are verbs in DAW.COMMANDS (a peer's
    open_edit must carry a name, cut to MARKER_NAME_MAX), and `DAW._call` sets
    `DAWBackend.acting_peer` beside `acting`: 0 for this machine, the sender's peer id for an
    intent (`DAW.apply_intent(verb, args, from)`, which `Session._receive_intent` passes).
    OfflineBackend keeps `_open_edits` by player; an edit's step joins the history at its first
    write (key "group", named for the edit, or for its first write when the name is ""), and
    `_fold_into_edit` keeps one [key, back, again] per control written (first back, last again)
    until a write that does not fold, which is kept in order and starts every control afresh; back
    runs them last first, again first first. An edit opened over an open one closes it; undo, redo
    and undo_to end every open edit's step first and keep the edit (`_restart_open_edits`), so an
    undo inside one takes it back whole and a hand still moving gathers one fresh step;
    `close_idle_edits` runs each frame and before every write (EDIT_IDLE_MSEC, 10 s); and
    `Session._on_peer_disconnected` calls `DAW.close_edits_of(peer)`. A guest's take
    (`_place_take`, `from` passed on), her recording placed and her room asks run as hers
    (`DAW.on_behalf_of(peer, fn)`), so they never fold into the host's own open edit. Capability EDIT_GROUPS:
    true on the stand-in and the built-in engine, and on ReaperBackend only with the bridge. There
    `_bridge_write` holds the acting player's bridge verbs (every edit through `_edit` and
    `_restructure`, FX parameters past the OSC bank, wet, presets, moving, adding and removing
    plugins, sends and sidechains) while an edit is open, and `close_edit` sends them as one
    `Batch` (`batch_request`: the name, then each call's function, argument count and arguments,
    flat for the bridge's one-level decoder); each call's callback gets its own part of the
    answer. An undo or redo sends open edits ahead of itself and keeps them open, EDIT_IDLE sends a forgotten one, and
    closing the link sends what is held. OSC writes (pan, volume, send levels) go at once and stay
    Reaper's own undo points. The bridge's `decode_batch` reads the calls by count, and
    `run_batch` runs them inside one `Undo_BeginBlock` / `Undo_EndBlock("dawlings: <name>", -1)`
    with the handlers' own block calls stood down for its length; a call that fails says so in its
    result and the rest still run; a Batch inside a batch is refused. `ControlAffordance` gained
    `edits_as_one` (open on grab, close on let-go, and on leaving the tree mid-grab; a scroll's
    notches within GESTURE_MS share one, so the wheel on a grouped fader is one step as its drag
    is) and
    `describe_edit` for the step's name; the console's channel faders use it, since a grouped
    track's fader writes its whole group every frame (the 2D view's faders are dawkit's, which has
    no gesture bracket yet, and still fold per control). The help card's Undo line says a drag is
    undone whole. Tests: `_test_a_two_value_drag_inside_an_edit_is_one_step` (60 frames of pan and
    volume, one step, both restored, and GESTURE_MS folding without an edit),
    `_test_another_players_write_is_a_step_of_its_own` (and a leaving guest's edit closed),
    `_test_a_forgotten_edit_closes_itself`, `_test_an_undo_inside_an_edit_takes_it_back_whole`,
    `_test_a_grouped_faders_drag_is_one_step` (a real strip's fader, grabbed and dragged),
    `_test_reaper_sends_an_edit_as_one_batch` (request files in a bridge directory of the test's
    own) and `_test_the_bridge_runs_a_batch_in_one_undo_block`, which runs
    tests/bridge_decode_test.lua (now with a Batch decoded and run against a stand-in `reaper`
    table) when a Lua is installed. The probe's guest drags track 6's pan and volume together
    inside an edit at 54.55 while the host moves track 10 at 54.7; both see two steps, the
    guest's one named "Probe: place", and the host's two undos put all three values back. No shot:
    nothing in the room looks different.

13. [x] **Controls beside the keys: the wire and the wheel.** Groundwork for #37 and the theremin,
    as decided. Session.`send_control(kind, value, song, source)` on CONTROLS_CHANNEL, unreliable
    ordered, passed on by the host as notes are, clamped by kind, and refused for any controller but
    the bend, 1 and 11. GuestMidi.`control(kind, value, source, at)`, `wheel_source`, the resend at
    least every 50 ms while off centre, and the return to centre at the player's last note-off, at
    both ends. MonitorSynth.`control(kind, value)` goes through its event queue to
    DawKitTine.control. native/keys.c reads `bend V` and `cc K V` (the bend scales every voice's
    increment, 11 scales the output) and NativeKeys.`control` writes them. TheirKeys, TheirMonitor
    and ChordHarp.heard apply a bandmate's controls to the one voice they have for that peer, and
    centre it at that peer's last note-off. Touches session.gd, guest_midi.gd, monitor_synth.gd,
    native_keys.gd, native/keys.c, their_keys.gd, their_monitor.gd, chord_harp.gd,
    tools/probe/session_probe.gd. The suite checks: a bend sounds on the spy synth; a second
    source's bend while the first owns the wheel is ignored, and is played once the first has let
    go; the wheel centres at the player's last note-off and not at one source's; with every second
    control dropped, the receiver is at the sent value within 50 ms; the control rpc is on
    CONTROLS_CHANNEL and unreliable ordered, and notes stay reliable on KEYS_CHANNEL; values clamp
    and unknown controllers are refused; the native helper parses `bend` and `cc` lines (its line
    parser, headless). The probe checks that the host's bend during a held note is heard on the
    guest's TheirKeys and centres at the note-off. Both sides at 0 failed.

    Built. Session gains CONTROLS_CHANNEL (6), CONTROL_KINDS (DawKitClip.PITCH_BEND, 1, 11),
    `send_control`, the `_control_up` and `_control` rpcs (unreliable ordered on that channel),
    `_pass_control` (refuses any other controller and counts it in `controls_refused`, clamps by
    `control_value`, a long source is plain keys, an unknown song -1), `control_rest` (the wheel
    centred, the mod wheel down, expression full) and the `control_played` signal. KeysDown keeps
    what is down in press order (`newest`, `is_empty`). GuestMidi.`control(kind, value, source,
    at)` answers whether it was taken; `wheel_source()` is the newest held note's source, or null
    with nothing down, when the wheel is anyone's; `controls` is the player's wheel as it is;
    `resend_controls(now, now_all)` sends again what is off rest every CONTROL_EVERY (50 ms, less
    CONTROL_SLACK so it is not a frame late), from `_process` and right behind every note-on; the
    `control_sent` signal is every send; `ticks` is the suite's clock. A control plays on the track's
    instrument plugin where the keys play one (a bend only if it has `pitch_bend`). The last
    note-off rests every control here, sending nothing. MonitorSynth.`control` queues CONTROL
    events to DawKitTine.control, keeps `controls`, and `rest_controls()`; NativeKeys.`control`
    writes `control_line` (`bend V`, `cc K V`); native/keys.c bends every voice's increment by the
    tine's formula and scales the output by expression before its saturation, and ignores CC 1.
    TheirKeys.`control`, TheirMonitor.`control` (a CONTROL entry in the line, played with the
    notes at its song; one already behind the backing plays at once without growing the line; an
    OFF that is their last carries `rest`) and ChordHarp.`heard_control` (through Presence, by
    source; the bandmate who moved it last has the shared voice's wheel, `_wheel_peer`, until
    their own last harp note) play a control only while that player has a note down, since a
    resend can overtake the last note-off on its own channel, and rest at that player's last
    note-off. The studio connects `control_played` to TheirKeys and TheirMonitor. Nothing moves a
    control yet but code: the tilt, Alt-drag and a hardware wheel are slices 14 and 15, so there is
    nothing new on screen or in the help card, and no shot. Tests:
    `_test_a_bend_sounds_on_the_keys_synth`, `_test_the_tine_and_the_helper_bend_and_swell_alike`
    (A4 bent full up crosses zero as often as B4, full down as G4; expression quieter, the mod wheel
    identical; the helper's `--render` reads `bend` and `cc` and matches the tine within 0.002),
    `_test_a_player_has_one_wheel`, `_test_their_wheel_rests_at_their_last_note_off` (TheirKeys,
    TheirMonitor and the harp), `_test_a_lost_control_is_made_good_within_50_ms` (a 60 Hz sweep
    with every second message dropped: the last move was lost and caught up 50 ms later),
    `_test_controls_ride_their_own_unreliable_channel` (Script.get_rpc_config) and
    `_test_the_host_clamps_controls_and_refuses_others`. The probe's guest sends CC 7 at 55.27,
    which the host refuses; the host holds G4 and bends it 4096 at 55.29 and lets go at 55.45; the
    guest's TheirKeys has the bend at 55.37 and has it at rest at 55.55 (each 70 ms or more from
    the host's, since the two clocks start apart).

14. [x] **Controls in takes, from a real keyboard, and down a cable.** The rest of #37's groundwork.
    MidiTake.`control(kind, value, channel, at)` keeps a control when it has moved at least 32
    (bend) or 1 (CC) since the last kept one and at least 8 ms have passed, and always keeps the
    last value before a note-off or a 50 ms gap, so a held bend's end is exact. It keeps at most
    MAX_CONTROLS (20000). `finish()` gains `controls` (flat [time, kind, value, channel], as
    ItemState.controls). `insert_midi_take` and MidiTake.clean_args gain `controls`. OfflineBackend
    puts them on the new item. The bridge's InsertMidiTake writes them with MIDI_InsertCC (0xE0 for
    the bend, 0xB0 for 1 and 11). GuestMidi._input reads a hardware keyboard's
    MIDI_MESSAGE_PITCH_BEND and CC 1 and 11, as the plain keys' source. Jacks pass a pitched
    source's controls into a player as `Jack.Kind.CC`, and Session._pass_jack clamps by kind as
    decided. Touches midi_take.gd, guest_midi.gd, daw.gd, offline_backend.gd, reaper_backend.gd,
    reaper/dawlings_bridge.lua, jack.gd, jacks.gd, session.gd, tools/probe/session_probe.gd. The
    suite checks: a 60 Hz bend sweep of 2 s keeps fewer controls than were sent, keeps both ends,
    and keeps no two closer than 8 ms; it lands in the take at its `at`; it is inserted with the
    notes on the built-in engine, and the item's controls hold it; clean_args refuses out-of-range
    values and unknown controllers; a synthetic hardware pitch bend and CC 1 reach the take; a bend
    of -8192 down a jack arrives at a player intact, and a note's clamp is unchanged. The probe
    checks that the guest's bend at 56.2 s during a held note reaches the host's take as a control
    at that song. Both sides at 0 failed.

    Built. MidiTake gains CONTROL_KINDS (which Session.CONTROL_KINDS now is), MAX_CONTROLS,
    BEND_STEP, CC_STEP, CONTROL_GAP, CONTROL_HOLD, `controls` and `control(kind, value, channel, at,
    keep)`: a move waits in `_moved` until it has gone far enough and long enough, and the latest
    waiting one is kept once it has stood 50 ms, a note lets go or the take ends, at the time it was
    first reached; a kept move lands no sooner than 8 ms after the one before, so no two are closer
    even for a burst. `keep` is the wheel put back at rest at the player's last note-off, which
    GuestMidi now writes into the take too (`_rest_controls(at)`), so an item never bends its next
    note; a take that begins with the wheel off rest starts with it. `finish()` gives `controls`
    flat in song seconds (`flat_controls`), `clean_args` gives them as its sixth entry through
    `clean_controls` (a row out of its kind's range, not a whole number, or of another controller is
    left out; times pulled inside the take), and DAW.insert_midi_take, DAWBackend, OfflineBackend
    (so the built-in engine, which renders an item's controls with its notes) and ReaperBackend take
    `controls` after the name. `_locally_insert_take` counts them from the item's start. MixWire's
    CONTROLS_MAX is MAX_CONTROLS, so a take reaches a guest whole. ReaperBackend.midi_take_request
    appends a control count and four numbers per control; the bridge's InsertMidiTake writes each
    with MIDI_InsertCC (0xE0 with the wheel's fourteen bits low then high, 0xB0 for 1 and 11) in the
    same Undo block and answers `controls`, and its timeline poll reads them back (`item_controls`,
    2048 an item), which ReaperBackend passes on as the item's controls. GuestMidi._input reads
    MIDI_MESSAGE_PITCH_BEND (`pitch` less 8192) and CC 1 and 11 as the plain keys' controls, and
    `last_take` counts the controls. Where the native helper reads the keyboard, native/keys.c
    passes SND_SEQ_EVENT_PITCHBEND and CC 1 and 11 on as `wheel V ch when` and `ctl K V ch when`
    lines without playing them (NativeKeys.hear makes them `control` entries), since whose wheel it
    is is GuestMidi.control's to say; the answer comes back as the `bend` and `cc` lines it already
    plays. Jack.Kind gains CC (`kinds_of(true)` has it). Jacks sends this player's own keys'
    controls (GuestMidi.control_sent) down `keys:P` as CC, not a cable's or the harp's, and not a
    resend of the value the cable already has (`_cabled`, forgotten at every note, so the resend
    right behind a note-on goes); `received` plays a CC as GuestMidi.control with source `&"cable"`
    at its song, so it lands in P's take. Session._pass_jack refuses a kind past CC and a CC that is
    not one of CONTROL_KINDS, clamps a CC's value with `control_value`, and a note's or trigger's
    pitch and velocity to 0..127 as before. The session panel's MIDI line says "Listening to ...:
    keys, pitch wheel, mod wheel." and its button's hover card says the wheels are played, heard by
    the band and kept in takes. The harp's own jack carries no controls yet: nothing bends the harp
    until slice 15. Tests: `_test_a_bend_sweep_is_thinned_into_the_take` (121 sent, fewer kept, both
    ends, none closer than 8 ms, each at the song it was sent at; a burst a millisecond apart; a rest
    kept 8 ms on; the MAX_CONTROLS cap), `_test_a_takes_controls_land_on_the_built_in_engine` (on
    GodotBackend: the item holds them from its start, one undo step, a guest's snapshot has them,
    DawKitTine plays A4 bent as B4, a peer's out-of-range bend and CC 7 are left out),
    `_test_a_peers_take_controls_are_cleaned`, `_test_a_hardware_wheel_reaches_the_take`
    (InputEventMIDI pitch bend and CC 1 into the take on the keyboard's channel and back at rest at
    the note-off, the mod wheel back at the next note -- a keyboard's mod wheel and expression stay
    where they were left and are remembered, `GuestMidi._hardware` -- CC 7 not the keys', the
    wheel's fourteen bits, the helper's `wheel` and `ctl` lines; the item's hover card names its
    controls; a helper's wheel move is stamped when it moved, before a note-off in the same frame) and
    `_test_a_bend_goes_down_a_jack_intact`; tests/bridge_decode_test.lua lifts InsertMidiTake and
    `item_controls` out of the bridge and checks the 0xE0 and 0xB0 writes and the read back. The
    probe's guest lets go of its first take's hanging note at 55.9, records BENT_PITCH at
    BENT_SONG (480 s) to a clock of its own onto TAKE_TRACK, bends it with a keyboard pitch-bend
    event at 56.2 and lets go at 56.3; the host finds the bend in that take within 5 ms of where the
    guest moved it, during the note, and the rest at the note-off. The host now leaves at 56.8.
    shots/spatial14_take.png is a phrase played from a MIDI keyboard into Gtr Amp (`SHOT_ARGS="--wheel-take
    8 --no-hud --hover 640,465" SHOT_CAM="0,-0.05,1.0,0.15,1.45,-1.0"`): its thinned bend and wobble stand on the selected
    take as the timeline's amber posts.

15. [x] **Bend and wobble by tilting.** The proving idea, #37. `Wobble` (core/music/wobble.gd, one
    per playing hand) takes the hand's `tilt_angles()` each physics frame. `bend` is the decision's
    formula over the roll since the note's press. `vibrato` is the high-passed roll (3 to 8 Hz, the
    hand's own shake filtered, not an LFO), up to VIBRATO_MOST (0.4 semitones). Their sum goes out
    as one control through GuestMidi.control with the instrument's source, at most 60 times a
    second, while that source owns the wheel. On the keytar the hand holding its neck bends. On the
    harp, the plucking hand bends while a string it plucked rings. With the fingertips, the playing
    hand bends. The theremin's pitch hand gets the same in slice 50. Desktop: the mouse's wiggle is
    `tilt()` (slice 7). MouseInteractor.wiggle now also runs while the cursor is over something that
    plays under it (the harp's strings, a string, the theremin's field: `plays_under_cursor`), not
    only with an InstrumentItem carried or the fingers on, so a wiggle wobbles the harp too. Alt
    with the mouse moving up or down is the bend wheel (100 px a semitone), springing back on Alt's
    release. KeyCatcher no longer gives Alt to the studio, so piano keys still play while Alt bends,
    and one let go under Alt still sends its note-off. The keys box in the session panel gains "Tilt
    bends" (on by default), for players who want a steady pitch from a hand that moves. Shown, not
    coloured: the harp's ringing string curves by its bend, the glove's fingertip letters say
    `+1.3`, and the keytar's neck tag says BEND. The PLAY page's harp, keytar and fingertips lines
    say "tilt to bend · shake to wobble · alt-drag bends", each true on its instrument. Touches
    wobble.gd, hand_pose.gd (`angles_of`), interactor.gd, xr_interactor.gd, mouse_interactor.gd,
    key_catcher.gd, keytar_item.gd, chord_harp.gd, fingertip_notes.gd, glove.gd, session_panel.gd,
    stations.gd. The suite checks: a posed hand rolled 20 degrees after its press bends (20/45 -
    0.08) / 0.92 x 2 = 0.79 semitones, as a bend value on the spy synth; the same roll from a
    controller's thumb-up start does too; a hand pressed at 90 degrees of roll bends both ways by
    the same amounts; a 3-degree roll (inside the dead zone) bends nothing; a hand held tilted
    before the press bends nothing; a 5 Hz roll of 6 degrees gives vibrato within VIBRATO_MOST, and
    a 0.5 Hz drift gives none; Alt with mouse motion bends and springs back; a piano key pressed and
    let go while Alt is held plays and stops; a wiggle over a harp string with nothing carried
    wobbles it; "Tilt bends" off sends no control; the take holds the bend; the harp string's curve
    follows. The probe checks that a guest's keytar note bent by a synthetic tilt reaches the host's
    take with its bend. Both sides at 0 failed. shots/spatial15.png is a posed hand bending a harp
    string.

    Built. `Wobble` (core/music/wobble.gd, a RefCounted: `keys`, `sources`, `hand`, `tilts`) is
    stepped each physics frame by what plays: `KeytarItem.wobble` (the hand carrying it, for
    `&"keytar"` and the plain keys it plays as; `midi` is its GuestMidi), `ChordHarp.wobble` (the
    hand that plucked last: a grab's interactor, or a touch's HandGestures, found from the tip's
    [hand, finger] key; `pluck` gains `by`), `FingertipNotes.wobble` (its own hand, while its fingers
    hold a note and no other hand's fingertips pinched since) and MouseInteractor's `_keys_wobble`
    (the plain keys, `&""`, no tilt, only Alt; not while the keytar is in hand, which bends them
    itself). It sends only while one of its sources owns the wheel, at most SENDS_A_SECOND (60),
    and only a changed value; it never sends a rest, which GuestMidi makes at the last note-off. It
    measures from the roll at the moment its source took the wheel, and again after every note let
    go (GuestMidi gains `rests`, counted there), so a string plucked again while it was the only one
    ringing begins again level. The bend is `bend_for(d)` over the roll less its shake; the shake is
    the roll through two one-pole high-passes at SHAKE_LOW (3 Hz) and a low-pass at SHAKE_HIGH (8 Hz),
    vibrato from SHAKE_FROM (0.75 degrees) to VIBRATO_MOST at SHAKE_FULL (6 degrees). A hand with
    nothing to read (a bare hand out of tracking, `tilt_angles` NAN, or one freed) holds its last
    roll. `value_of`, `semitones_of` and `words` (`+1.3`) convert. HandPose gains `angles_of` and
    `angles`, `tilt_of` is their clamped form; HandGestures keeps `angles`; Interactor gains
    `tilt_angles()` (Vector2.ZERO) and `bend_wheel()` (0); XRInteractor answers a bare hand from
    HandGestures and a controller from its aim; MouseInteractor's is its wiggle over WIGGLE_MOST
    times TILT_MOST. ControlAffordance gains `plays_under_cursor()` (false; the harp's true), and
    MouseInteractor.`wiggles()` is an InstrumentItem or the keytar carried, the fingers playing, or
    the cursor ungrabbed on a control that plays under it. Alt: `alt_down()` (`alt_override` for the
    suite), `_input` turns mouse motion with Alt into `bend_by(-relative.y)`, BEND_PIXELS (100) a
    semitone, clamped to two, and `_spring_bend` takes it back to the middle over BEND_SETTLE (60
    ms) once Alt is up. KeyCatcher lets a key go whatever modifier is down (`_down` is checked
    first) and gives only Ctrl and Meta keys to the studio. GuestMidi gains `tilt_bends` (on), and
    the session panel's keys box "Tilt bends", whose hover card says what tips, what shakes, the
    mouse's wiggle and that Alt still bends with it off. Shown: each harp string's own
    ShaderMaterial bows its middle across by its bend (`bow(i)`, BOW_MOST 3 cm at two semitones,
    toward the high strings for up; a bandmate's bend, from `heard_control`, bows the strings it
    shakes); the fingertips' held fingers are lettered `E4 +1.3` (Glove.`bent`), on the mouse's
    glove, a tracked hand's skeleton and a controller's row alike; the keytar's neck carries a
    `BendTag` saying `BEND +1.3` while it is bent, mine or the bandmate's holding it (Presence routes
    their `&""` and `&"keytar"` controls to `KeytarItem.heard_control`, which also plays them out of
    the keytar and rests at their last note there). The harp's, the keytar's and the fingertips'
    PLAY lines (Stations) and the harp's and keytar's hover hints say "wiggle ... to wobble · Alt +
    mouse up or down bends" for a desk and "tilt to bend · shake to wobble" for hands, and the
    keytar's notice says Alt bends. The harp's jack still carries no controls: a harp plucked into
    a bandmate is not bent. Tests: `_test_a_tilt_bends_from_where_its_note_began` (20 degrees after
    the press is 0.79 semitones, as the spy synth's bend; down alike; back inside the dead zone at
    rest; 3 degrees sends nothing; tilted 30 before the press sends nothing; from 90 degrees of roll
    both ways alike; nothing while a harp note is newer; a controller from thumb up the same; no more
    than 60 sends a second), `_test_a_shake_wobbles_and_a_drift_does_not` (5 Hz at 6 degrees is
    vibrato within VIBRATO_MOST with no bend, 0.5 Hz none), `_test_tilt_bends_off_sends_nothing`
    (and Alt still bends), `_test_alt_and_the_mouse_bend_and_spring_back` (150 px is 1.5
    semitones on the plain keys, full down clamps, motion without Alt is nothing, back to the middle
    within half a second; the piano plays and stops under Alt, stops under Ctrl, and Ctrl's keys
    stay the studio's), `_test_a_wiggle_over_the_harp_wobbles_it` (no wiggle over nothing; over the
    harp with nothing carried a 5 Hz wiggle sends harp bends and the plucked string bows the way it
    bends, an unplucked one does not, straight again rung out; a posed hand that plucked, tipped
    20 degrees, bends 0.79 and bows by its share) and `_test_a_bend_is_shown_and_kept_in_the_take`
    (Glove.bent; the keytar's tag, mine by Alt and a bandmate's, gone at the note-off; a desktop
    fingertip's letter `+1.3`; a tilted keytar note's take rises to the tilt's bend and rests at the
    note-off). The probe's guest holds a keytar in an XRInteractor reading a posed HandGestures,
    plays TILT_PITCH at 56.65 onto TAKE_TRACK at TILT_SONG (520 s) to a clock of its own, tips the
    hand TILT_DEGREES (20) over 56.7 to 56.8 and lets go at 57.25; the host finds the take with its
    note and the bend the guest's keys had, during the note, and the rest at its note-off. The host
    now leaves at 57.7. shots/spatial15.png is a posed bare hand that plucked the harp's A4 string,
    tipped 35 degrees after the pluck, the string bowed by its 1.5-semitone bend
    (`SHOT_CAM="2.8,-0.15,1.0,4.9,1.1,6.8" SHOT_ARGS="--posed-hand 5.0,0.98,6.77,3.14159,0,0
    --harp-bend 35 --hover 1580,880" tools/shot.sh shots/spatial15.png 38 42`; `--harp-bend` plucks at
    the shot harness's HARP_PLUCK_FRAME and its readings add the bend).

16. [x] **Hits that play back as hits.** No new idea; the hand percussion's takes, the drums', the
    pads' and the looper's need it. The built-in engine plays every MIDI item through DawKitTine
    (`render_notes`) and ignores the channel, so a recorded shaker or drum plays back as a tine.
    `ItemVoices` (core/built_in/item_voices.gd) renders a MIDI item's channel 9 notes as GM drums
    from Foley's own synthesis (36 kick, 38 snare, 37 rim, 39 clap, 42/44/46 hats, 41 to 50 toms, 49
    crash, 51 ride, 54 tambourine (its jingles shaken), 56 cowbell, 62 to 64 congas, 69/70 cabasa
    and maracas from the shaker, 75 claves, 76/77 woodblock, any other a short click), and channel
    10 notes as the pitched items' voice (the handbell's partials at the note's pitch). Each note's
    take is seeded by its time, so a render is the same every time. GodotBackend's MIDI render
    splits an item by channel: 9 and 10 through ItemVoices, the rest through the tine as today,
    summed. On Reaper the track's own instrument plays what it is given, as for any MIDI. Touches
    item_voices.gd, godot_backend.gd, foley.gd (each kind's sound as a static render by take). The
    suite checks: one GM 38 on channel 9 renders a snare (energy above 2 kHz, no partial at 38's
    pitch); 56 is the cowbell's take; a channel 10 note at 72 has its fundamental at C5; channel 0
    renders as before; two renders are equal; the demo song's render is unchanged.

    Built. `ItemVoices.DRUMS` maps GM drum notes to [Foley's sound, ratio]: each of the room's
    items' own notes (ShakerItem 82, CowbellItem 56/68, PadItem 47/45, the claves' 58...) is that
    item's sound at its voice's pitch (InstrumentItem.VOICE_PITCH), so a take sounds as it was
    heard, and the kit round them is Foley's too. TambourineItem records a shake and a strike alike
    as 54, so 54 is `Foley.jingle`, the shake, which is how the tambourine is mostly played. Foley
    gains `kick`, `snare`, `rim`, `clap`, `crash` (china and splash are it pitched), `ride` (its
    bell pitched up), `conga` and `click`, and `samples(kind, take)`, the buffer the room plays as
    floats; its cache is filled under a lock now, as renders run on worker threads. A note is a
    one-shot that rings out whole, gained by the curve InstrumentItem.level_db plays a hit at live
    (times LEVEL, 0.8), resampled from Foley.RATE at its ratio; a channel 10 note is the handbell at
    2^((note - 72)/12). `take_at` is the note's start to the millisecond, hashed, so a run is
    several takes and a render the same on any machine. `GodotBackend.render_midi` splits
    (`ItemVoices.split`) and sums; an item with no channel 9 or 10 notes takes the tine's path
    unchanged, and one with only them skips the tine. The channels are mirrored, as
    TourPart.ITEM_CHANNELS are, and checked equal. No interface: the sound is the same at a desk and
    in a headset, wherever an item plays (the timeline, a lane, a render). Test:
    `_test_hits_play_back_as_hits` (the above, plus each item's notes as its own sound and voice, an
    unknown note a click, a mixed item the sum within a sample's rounding, notes past the end or on
    other channels not rung, and the same render after Foley's cache is emptied; the demo song is
    pinned by its kick, snare and hat hashes at DemoSong.VERSION 7).

17. [x] **Shakers and a tambourine, in a bare hand, snapped gently.** The proving idea, #38,
    finished. A tracked bare hand takes hold of hand percussion by closing round it: three fingers
    past HOLD_CURL (0.6) with the palm within 6 cm of its grip, not a pinch. It keeps it while
    closed, and lets go only when the hand has been open past OPEN_CURL for 0.1 s with confident
    tracking. Tracking lost while holding keeps the item held where the hand was last seen for
    LOST_HOLD (0.4 s), and sends it home after, and a throw is only ever from the velocity of
    confident frames, so a dropout mid-shake never throws it. For a bare hand, `shake_point()` is
    HandGestures' palm joint, so a wrist's shake is a stroke. A pinch still carries it too. A hand
    carrying anything no longer counts toward XRRig's two-fists escape. Snap: HitRecorder's stamp,
    never the sound, moves a hand percussion hit's recorded time toward the nearest sixteenth
    (MixState.bar_at's grid) by SNAP_PULL (half) when it is within SNAP_WINDOW (35 ms). What is
    heard and what is sent (`at`) are the hit's own. "Snap hand percussion" (on) sits in the session
    panel, just after the keys box, and is the player's: `send_item_hit` and `item_hit` gain `snap` and `take`
    (the hit's Foley take, so everyone hears the sound its player heard), and the host's HitRecorder
    snaps a guest's hit by its flag. The item's shelf tag says `SNAP` while on. Discoverable: the
    shaker's and tambourine's hover hint says "shake it · click strikes · P jack", their PLAY lines
    say it for both media, and in a headset their shelf tags say "close your hand round it and shake
    · controllers are steadier for fast parts". Touches xr_interactor.gd, xr_rig.gd (escape skips a
    carrying hand), hand_gestures.gd, hand_pose.gd (`grips`), instrument_item.gd, hit_recorder.gd,
    session.gd, presence.gd, session_panel.gd, shaker_item.gd, tambourine_item.gd,
    tools/probe/session_probe.gd. The suite checks: a posed fist round the shaker's grip holds it,
    and an open hand lets it go after 0.1 s; a 0.3 s tracking dropout mid-shake neither drops nor
    throws it, and a 0.5 s one sends it home; two fists, one holding the shaker, do not escape, and
    two empty fists still do; a synthetic palm swinging at 4 Hz with 0.3 m/s peaks plays one hit a
    stroke; a pinch-carried shaker still plays; a hit 20 ms early is recorded 10 ms early, one 60 ms
    off is untouched, and its sent `at` is unmoved; a guest's hit with snap off is recorded as
    played on the host, and with it on is snapped; a guest's hit sounds its own take on the host;
    the take plays back as a shaker (slice 16); the tambourine the same. The probe checks that a
    guest's snapped shaker hit lands snapped in the host's take. Both sides at 0 failed.
    shots/spatial17.png is a posed fist shaking the shaker.

    Built. HandPose gains HOLD_CURL (0.6), HOLD_FINGERS (3), GRIP_REACH (0.06), `closed` and
    `grips(joints, point)`. HandGestures gains `confident` (every joint POSITION_TRACKED, not only
    VALID; `take(at, sure)`), `closed`, `palm()` and `palm_pose()`. XRInteractor's `step_hold`
    (each physics frame, after the base's) takes hold as a seen hand closes, never with a fist
    already made and moved onto it (the closing edge is read off every tracked frame, guessed
    joints included, so fingers closing out of sight still take hold and a guess on the way never
    makes a made fist look new; a dropout leaves it as last seen), of the nearest `grippable` InstrumentItem: `held_in_fist()`
    (ShakerItem and TambourineItem), at home or loose, whose `grip_point()` (the point its
    `held_pose` puts at the hand: the shaker's middle, the tambourine's bare stretch of hoop) is
    under the palm. While `fist_holding` it carries it at the palm, FIST_DEPTH (2 cm) into the fist
    (`carry_pose`); the hand counts as open only on confident frames, and LET_GO_AFTER (0.1 s) of
    them lets go, thrown by `palm_velocity` (confident frames over FLICK_WINDOW, cleared on any
    loss or guess) past FLICK_SPEED, put down otherwise. A hand still tracked but with joints only
    guessed (fingers hidden in the fist, a blurred shake) keeps carrying it at its palm and playing
    its strokes; only its letting go and its throw wait for confident frames. Lost from tracking
    altogether, it stays where the hand was last seen, and after LOST_HOLD (0.4 s) goes home through
    ItemRoom.send_home. The runtime's own fist
    (grip_click) neither puts it down nor pinches while it holds. Interactor gains `shake_tracked`
    and `shake_lever`: a bare hand's `shake_point` is its palm, levered by PALM_LEVER (1.6, the
    shaker's end swinging further than the palm), and InstrumentItem feels no stroke while it is not
    tracked (guessed joints are still tracked), so a hand coming back is a fresh stroke, not a jump. XRRig's `escape_fist(tracked,
    fist, hand)` leaves out a hand carrying anything; `watch_fists` is the two-fists count. HitRecorder
    gains SNAP_PULL, SNAP_WINDOW, `nearest_sixteenth` (quarter-note beats from the start of the bar
    MixState.bar_at puts it in, so 3/8 and cut-short bars are their own grid), `snapped_at` and
    `snaps()` (GuestMidi.snap_hits, on); `hit(item, velocity, at, track, snap)` moves only an
    unpitched item's stamp, by the hit's own flag (1 or 0) or, given -1, this player's. Session's
    `send_item_hit` and `item_hit` gain `snap` and `take`, cleaned on the host by `clean_item_hit`
    (velocity 1..127, a song or -1, a take or -1) and passed on; Presence plays a bandmate's hit as
    `heard(velocity, struck, song, take, snap)`, the take their hand rang (`sound_take`) at their own
    pitch, without the wobble. The studio sends `HitRecorder.snaps()` and `sound_take()` with every
    hit and sets InstrumentItem's `snapping` and `hands_hint` (the medium is a headset). Hand
    percussion has a shelf tag (a Label3D, read again on a timer every RETAG, 0.25 s, since an item
    at rest does not tick): SNAP while this player snaps, or in a bandmate's hand while they do; in a
    headset also "close your hand round it and shake / controllers are steadier for fast parts";
    never over it in your own hand. "Snap hand percussion" has a box of its own in the session
    panel ("YOUR HAND PERCUSSION", `_hits_box`), just after the keys box and shown to every player:
    a solo player or host on Reaper, whose keys box is hidden (Reaper records their keys itself),
    still records hand percussion hits, so the setting the desk line points at is always there. Both hints say "shake it · click strikes · P jack"; the
    PLAY · HELD lines say it for both media, and the desk line says where snapping is turned off.
    Who records a hit is unchanged: each player's own HitRecorder takes their hits down and sends the
    take as an intent, so a guest's take reaches the host already placed by its own flag and the
    host never snaps it again (`_place_take` places it as sent); the flag on the wire is what any
    machine that takes a hit down obeys, and what the bandmates' tags show. The two older tests
    that check a hit lands exactly at its read turn snapping off. The suite checks the above
    (`_test_a_closed_bare_hand_holds_hand_percussion`, `_test_a_hand_carrying_anything_is_no_escape_fist`,
    `_test_hand_percussion_is_snapped_gently_as_it_is_recorded`,
    `_test_a_guests_hit_is_snapped_by_its_flag_and_heard_as_its_take`,
    `_test_snap_hand_percussion_is_in_reach_where_reaper_records_its_own_input`): a closed hand
    tracked but unconfident for 0.6 s keeps the shaker, carries it at its palm and plays its strokes,
    and opened while guessed at does not let go; the snap switch is shown for a solo player, a host
    and a guest on Reaper, between the keys and the microphone, and is their own; a 4 Hz, 0.3 m/s swing plays
    8 hits for 8 strokes; a flick as the hand opens throws it; three fingers past HOLD_CURL are
    closed and two are not; the bell is never moved and never held in a fist; in 3/8 the grid is
    the bar's. The probe's guest records two shaker hits onto TAKE_TRACK at SNAP_SONG (560) at 57.42
    with a HitRecorder of its own, one 20 ms before a sixteenth with snap on and one with it off, and
    sends both as hits; the host finds the first 10 ms early by the guest's grid and its own, the
    second as played, and both hits with their flags and takes. The host now leaves at 57.8.
    shots/spatial17.png is a posed right fist that closed round the shaker on the shelf, lifted and
    shaking it, its readings saying HOLDING SHAKER, CLOSED HAND, and SNAP over the tambourine
    (`SHOT_CAM="2.5,-0.3,0.9,-6.74,0.47,3.62" SHOT_ARGS="--posed-hand 0,0,0,1.5708,0 --fist-shake
    --hover 1580,880" tools/shot.sh shots/spatial17.png 40 46`; `--fist-shake` puts the posed hand
    over the shaker's grip, closes it at frame 8 and swings it at 4 Hz, an XRInteractor reading it).

18. [x] **The stereo field as a stage.** The proving idea, #1. `StageTable`
    (hardware/stage/stage_table.gd) is a Surface on its own trolley beside the desk, so F visits it
    and G brings it: a table top 1.2 m wide and 0.9 m deep at the desk's height, lettered L, C and R
    along its front and with distance rings in dB, so it hides neither the timeline nor the console,
    and every voice is within a reach of its front. Each track of the console's bank (8 or 16, with
    < and > keys on the table's front that call set_track_bank, as the console's do) is a
    `StageVoice` (hardware/stage/stage_voice.gd, a ControlAffordance: a lit sphere lettered with its
    number and name). The table's SHOW key picks the bank, the soloed or the selected tracks. Across
    is pan. Distance from the front edge is volume: the front edge is +6 dB and the back edge -40,
    linear in dB, past it -inf. Size is width: a radius of 2 to 8 cm for 0 to 100 percent, set by
    dragging the ring round it. A grab places a voice, by mouse on the table's plane, by a hand, or
    by a controller, inside an edit (slice 12), so a placing is one undo step; on Reaper its pan and
    volume are Reaper's own points, one each, and the card says so. It snaps to the centre line
    within 1 cm unless fine. The wheel or thumbstick nudges volume half a decibel a notch (Shift
    fine), and the voice's tag has PAN < and > keys, a percent a press (the wheel over them nudges
    pan). A double press (two presses without a drag within 0.35 s; a voice is no instrument, so two
    presses are not two notes), Backspace on a desktop, or the RESET on its tag sets it back to
    centre, 0 dB and full width. Every move is DAW.set_track_pan, set_track_volume or
    `set_track_width(index, width)`. TrackState gains `width` (1). The built-in engine's track bus
    gains an AudioEffectStereoEnhance whose `pan_pullout` is the width, in the bus's tail: after
    every FX slot, so `fx + 1` still finds each effect, and moved past an effect added later; the
    track's pan follows it there, since a width after the pan would pull a panned track back to
    the middle (slot 0 stays a panner, at the centre). The cue, tap and send copies take the FX slots only, not the tail. .dawproject keeps the
    width in an extension attribute. The bridge's SetTrackWidth sets I_PANMODE to stereo pan (5)
    when the track's mode ignores D_WIDTH, then sets D_WIDTH; GetState reads D_WIDTH back only in
    the stereo and dual pan modes (else 1). The card says `pan mode set to stereo pan` the first
    time. The console's pan knob and fader move with it, since they read the same state. The hover
    card says `3 BASS · pan 20 L · -4.2 dB · width 60%`. Muted voices dim and carry a slash, a
    soloed one has a ring, and a voice is lettered, not colour-coded. Touches stage_table.gd,
    stage_voice.gd, mix_state.gd, daw.gd, daw_backend.gd, offline_backend.gd, godot_backend.gd,
    project_files.gd, reaper_backend.gd, dawlings_bridge.lua, studio.gd (the trolley's place),
    stations.gd (a station and a surface). The suite checks: placing a voice writes pan from its x,
    volume from its distance and width from its ring, as one undo step; the centre snap and fine;
    the double press and Backspace reset, and a press then a drag is no reset; PAN < and >; the bank
    keys show tracks 9 to 16; the console's pan and fader follow; the enhancer follows the width and
    sits after the FX, an add_fx afterwards leaves every FX index right, a cue copies no enhancer,
    and a save and load keeps it; the bridge decodes SetTrackWidth and sets the pan mode
    (tests/bridge_decode_test.lua); with the capability off there is no ring and the card says so;
    the table stands clear of the console, timeline and mix position in every venue. The probe
    checks that a guest's drag reaches the host as pan and volume in one step. Both sides at 0
    failed. shots/spatial18.png is the demo song's tracks on the table.

    Built. `StageTable` (hardware/stage/stage_table.gd) and `StageVoice`
    (hardware/stage/stage_voice.gd, with `StageVoice.Ring` for the width) stand on the stage
    trolley at `Studio.STAGE_AT` (1.1, 1.4), turned to face the mix position, its top at
    `STAGE_TOP` (0.74). It stands far enough back that from the seat the right-hand lamp's foot is
    seen past its corner. The trolley carries the station's plaque, and the table is a focus
    surface, so F visits it and G brings it. `Stations` has a `stage_table` row in the control room
    with a `surface`. The PLAY · CONTROL ROOM page, the station board and I (now four stations)
    name it. The table's arithmetic is static (`spot_of`, `z_of_db`, `db_of_z`, `pan_of_x`,
    `ring_of`, `width_of`, `pan_words`, `db_words`), and so is the probe's. `place` writes pan and
    volume only where they changed, snaps within SNAP unless fine, and puts anything past the back
    edge at -inf on the lip (OFF_Z). `nudge_volume` (DB_STEP 0.5, DB_FINE 0.1), `nudge_width`
    (WIDTH_STEP 5%, WIDTH_FINE 1%) and `nudge_pan` (PAN_STEP 1%; the wheel over PAN < > 5% a
    notch, Shift 1%) are the wheel's. A voice's wheel is its level, or its width while it is held,
    inside the placing's edit. `pressed`/`forget_press` count double presses. `reset` is its own
    edit (`<name>: reset`). `reset_under` is the studio's Backspace, given the mouse's held or
    hovered control. The rail along the front edge, sloped toward the player, has a `Tag` per voice
    (number and name, a colour chip, MUTE/SOLO in words, the readout, PAN < >, RESET, which does not
    dwell), BANK < > (`page`, held while a hand is on the table, then `_go_to`, which asks
    `DAW.set_track_bank` past the cached bank) with "9-16 OF 20", and SHOW. A leader runs from each
    tag to its voice, so which ball is which is read without colour. A muted voice is darkened,
    barely lit and struck through, and a soloed one wears a halo. Voices glow with their meters.
    DAW gains `set_track_width` (a COMMAND, its intent checked). DAWBackend gains
    `Capability.WIDTH`. MixState.TrackState gains `width` (1), on the wire as `/track/N/width`
    (MixWire, kept to 0..1). OfflineBackend undoes it. GodotBackend puts an
    AudioEffectStereoEnhance in each track bus's tail (`_fx_end`, `width_effect`), then the
    track's pan (`pan_effect`; slot 0 is left at the centre), so the width is taken before the pan
    as Reaper's stereo pan takes it, and the rack's adds, moves, removals and the cue, tap and send
    copies work within the slots before it. A ball under another (tracks at one pan and level
    stand in one place) is taken by the name on its tag (`StageTable.NameGrip`, "2 KICK  BALL"),
    whose frame is the voices' plane: a drag from it moves the voice as far as the hand goes
    (`StageVoice.steered`), the wheel is its level or, held, its width (`nudge_voice`), two
    presses and Backspace reset, and while it is hovered or held its voice stands RAISE over the
    pile (`StageVoice.pick`). The voice's card and the station's desk and hands lines say so.
    ProjectFiles and ProjectBridge keep widths in the .dawproject extras by track id. ReaperBackend
    sends `SetTrackWidth` by the bridge (one call per track in an edit's batch, the last), holds
    the poll's width off for WIDTH_SETTLE_MSEC, and has `stereo_panned` and `pan_mode_set`. The
    table's notice says `<n NAME>: pan mode set to stereo pan, so it can have a width.`, and the
    card says so after. The bridge gains `SetTrackWidth` and `track_width` in GetState and the
    structure poll. The suite: `_test_a_placing_on_the_stage_table_is_one_step`,
    `_test_the_stage_table_snaps_to_centre_and_resets`, `_test_a_ball_under_another_is_taken_by_its_tag`,
    `_test_the_stage_table_banks_and_shows`,
    `_test_with_no_width_the_stage_table_has_no_ring`, `_test_the_built_in_engine_keeps_a_tracks_width`,
    `_test_reaper_sets_a_width_by_the_bridge`, `_test_the_stage_tables_voices_are_clickable_at_it`
    (from the table's own visit, a click lands on every tag key and tag name, and on every voice
    and ring band unless it is under another, wholly or in part, and so is taken by its name; the
    seat audit leaves voices to it, since tracks at one pan and
    level stand together and the top is seen nearly edge-on from the seat) and
    `_test_the_stage_table_stands_clear_in_every_venue`. tests/bridge_decode_test.lua decodes
    SetTrackWidth, sets stereo pan once inside the Undo block, and reads a width only in pan modes
    5 and 6. The older rack, cue, send and hosted-plugin tests count the rack's slots up to
    `_fx_end`. The station tests expect four stations, and the board's plaque keys are looked
    for in the whole studio. The probe's guest stands a table of its own at 57.7 and drags
    STAGE_TRACK (4) to STAGE_PAN 0.3 and STAGE_DB -10 in fifteen moves. The host finds both at
    58.1, as one step named `<name>: place`, which one undo takes back whole (on Reaper it puts them
    back by hand), and now leaves at 58.2. shots/spatial18.png is the demo song's eight first tracks
    on the table, the HAT muted and struck through, with RHODES' card (`SHOT_CAM="-2.165,-0.75,1.35,1.1,0.74,1.4"
    SHOT_ARGS="--hover 704,585" tools/shot.sh shots/spatial18.png 40 46`).

19. [x] **The stage in depth, leaning in, and clapping to mute.** #1 finished, and #14. Depth is its
    own handle, never a side effect of volume. Each voice stands on a stalk, and lifting it off the
    table (up to 0.3 m) is how much it sends to the project's room. The room is the first track
    whose chain holds a reverb and that another track sends to (`StageTable.room_track()`). A mist
    round the voice shows the send's level, and a voice on the table has none, however quiet it is.
    The first lift makes the send inside the lift's edit, so it is the same undo step as its level,
    said in the toast. With no room, the table's ADD ROOM key makes one: a track `ROOM` with a
    reverb. Leaning in, as decided: on a host whose engine plays the tracks, a head (headset) or the
    camera (desktop, L held over a voice) within 0.25 m of a voice lifts that track in this player's
    ears alone (`Ears.lean(track)`). Nothing goes to the DAW. A guest, or a host on Reaper, gets the
    card `leaning needs the tracks played here (a host on the built-in engine)`. Clap (#14): `Clap`
    (core/input/clap.gd) reads both tracked palms. Within 5 cm, normals opposed within 40 degrees,
    they are pressed. Pressed and held, the track being pointed at is muted until they part. A clap
    (meeting faster than 0.8 m/s and parting within 0.3 s) latches it: a mute toggle. The track
    pointed at is the one under either hand's ray as they met, or else the head's gaze
    (`Studio.track_under(ray)`, answering stage voices, console strips, the timeline's lanes and
    track racks). Two controllers' grip points within 8 cm are the same. On a desktop, K held over a
    track, or tapped. The mute is DAW.set_track_mute. A pressed mute shows on the voice and the
    strip as any mute does, and a toast says `3 BASS muted while held`. Touches stage_table.gd,
    stage_voice.gd, ears.gd, godot_backend.gd (the lean's cue), clap.gd, hand_pose.gd,
    xr_interactor.gd, studio.gd, stations.gd (HELD lines). The suite checks: the send's level by the
    stalk's height and its creation in the same step; no send for a voice on the table at -20 dB;
    ADD ROOM; leaning lifts the track's cue and lowers Mix, changes nothing in DAW.state, and on a
    guest changes nothing and shows the card; posed palms pressed mute and unmute; a fast meet and
    part latches; controllers; K held and tapped; track_under for each kind of surface. The probe
    checks that the guest's latched clap-mute reaches the host's track. Both sides at 0 failed.
    shots/spatial19.png is a raised voice with its room mist beside a muted one.

    Built. Every `StageVoice` stands on a `StageVoice.Stalk` (a ControlAffordance in the table's
    own frame, its foot on the table, so a held ray moves in the upright plane through it), and
    `LIFT` is now 0.06 so the stalk shows between the ball and its ring. How far it is lifted
    (`lift()`, up to `STALK_MOST` 0.3 m) is the send to `StageTable.room_track()`, the first track
    whose chain holds a reverb (a plugin named "...verb...") that another track sends to (not as a
    key), or else the first called ROOM with a reverb: `send_db_of_lift` is -inf on the table,
    `ROOM_LOW_DB` (-40) just off it and `ROOM_TOP_DB` (0) at the top, linear in dB, and
    `lift_of_send_db` reads it back. `send_to_room` makes the send (`DAW.create_send`) inside the
    stalk's own edit (`<name>: room`), so the first lift is one undo step with its level, and the
    toast says `4 HAT: a send to 13 VERB RTN made, at -20.0 dB: one undo step with this lift.`; a
    guest asks for the send and sets its level when it arrives. Set back on the table, the send
    stays at -inf. The wheel over a stalk is a decibel a notch (`nudge_room`, Shift a tenth). A
    `Mist` round the ball, its size and opacity by the send, shows it, and the card says
    `room -12.8 dB`. The rail's left end has the ROOM key and a label, `ADD ROOM` (lit) while there
    is no room and `ROOM  13 VERB RTN` after: `add_room` adds a track ROOM at the end with the DAW's
    first reverb choice (`reverb_choice`), as one step `Stage: add room` (or, on a DAW that adds
    tracks by its poll, the reverb when the track arrives). `Ears.lean(track)` (`can_lean`: not a
    guest, and the built-in engine) asks `GodotBackend.set_lean`, a cue of that track beside the
    personal mix's (`_cued_tracks`) whose bus `_apply_tracks` keeps at the track's fader, and its
    VCA, plus `LEAN_DB` (6), and lowers the Mix bus by `LEAN_MIX_DB` (-6), headphones on or off;
    `listen` keeps both while it lasts. The studio leans (`_follow_lean`, `lean_wanted`): in a
    headset to the nearest voice within `LEAN_REACH` (0.25 m) of the head, at a desk to the voice
    under the cursor while L is held; elsewhere the notice is `3 SNARE: leaning needs the tracks
    played here (a host on the built-in engine).`, once a voice, and every voice's card says so.
    `HandPose.palms_meet` (`PALMS_TOUCH` 5 cm, `PALMS_OPPOSED_WITHIN` 40 degrees) and
    `palms_pressed`; `XRInteractor.clap_palm` gives a bare hand's palm and its normal, or a
    controller's grip point. `Clap` (core/input/clap.gd) reads the two (`Clap.reading`: palms by
    palms_meet, grips by `GRIPS_TOUCH` 8 cm) a frame at a time (`step`): the meeting presses
    (`press`), reading the track once from `target`, mutes it unless it is muted, and says
    `3 SNARE muted while held`; the parting (`release`) latches if the meeting was faster than
    `CLAP_SPEED` (0.8 m/s, over `SPEED_WINDOW`) and it parted within `LATCH_WITHIN` (0.3 s), toggling
    the mute from what it was, and else puts it back. It keeps what it asked, so a guest's release
    answers its own press. The studio has two: `clap` for the rig's hands, aimed by
    `_clap_target` (either hand's held or hovered control, else `track_under` the head's gaze),
    and `key_clap` for K, whose press is always quick, so a tap latches. `Studio.track_under`
    casts on the control layer, and `track_of` answers a `stage_track` meta (voices, rings,
    stalks, tags and their keys), a ChannelStrip, a RackUnit or the rack, and the timeline's lanes
    (`track_at_point`); `pointed_by(hand)` is a hand's. `Stations.HELD` gains CLAP TO MUTE and LEAN
    IN, and the stage table's desk and hands lines name the stalk and L. The suite:
    `_test_a_voices_stalk_is_its_send_to_the_room`, `_test_add_room_makes_a_room_to_send_to`,
    `_test_leaning_in_lifts_one_track_in_your_ears_alone`,
    `_test_pressed_palms_mute_and_a_clap_latches` (posed palms 2 cm apart pressed, 9 cm or turned
    60 degrees not, read through two XRInteractors' HandGestures; two XRController3D grips),
    `_test_k_mutes_and_l_leans_at_a_desk` and `_test_track_under_answers_each_kind_of_surface`; the
    slice 18 tests stand voices at their lift, read `room` on the card, and click every stalk too
    (one behind another raised voice's stalk is taken by its tag's name). The probe's guest claps
    a latch at CLAP_TRACK (6) at 58.2 and sees the mute come back by 58.35; the host finds it
    toggled at 58.4 and puts it back, and now leaves at 58.5. shots/spatial19.png is the demo
    song's table with 7 RHODES and 3 SNARE lifted in their mist beside 4 HAT muted, and RHODES'
    stalk's card (`SHOT_CAM="-2.165,-0.75,1.35,1.1,0.74,1.4" SHOT_ARGS="--hover 700,560"
    tools/shot.sh shots/spatial19.png 40 46`).

20. [x] **Sidechain as a rope.** The proving idea, #18. Each stage voice has a knot under it.
    Dragging from one voice's knot (the kick) to another voice (the bass) ties a rope, in one edit:
    `DAW.create_sidechain(kick, bass)` and a compressor on the bass that listens to it. On the
    built-in engine the key send is no longer skipped (godot_backend.gd's "nothing here listens for
    one"). It feeds the compressor's own sidechain input (AudioEffectCompressor.sidechain, the key's
    bus name). On Reaper the bridge's handler adds ReaComp with its detector on the auxiliary input.
    Whether the rope added the compressor is a room row (`ropes` {"kick>bass": added}). The rope is
    a CableSweep curve between the voices. It sags when slack, and pulls straight and lifts each
    time the bass ducks, by `Sidechain.reduction(key_db, threshold, ratio)` from the key's meter
    (the same estimate on both engines, since neither reports gain reduction). Pulling the rope's
    middle away is how hard it ducks: the key send's level (set_send_volume) and the compressor's
    threshold (set_fx_param) together, inside an edit, so one undo step per let-go. Its card says
    `KICK -> BASS · ducks 6 dB on each hit · pull for more`. The knot's X cuts it in one edit:
    remove_send, and remove_fx for the compressor if the rope added it. No new verb. The patchbay
    shows the key send as it does now, which is the precise way in. Desktop: drag from the knot, and
    drag the rope's middle to pull. Touches stage_table.gd, stage_voice.gd, sidechain.gd (new,
    core/music), godot_backend.gd, offline_backend.gd, reaper_backend.gd, dawlings_bridge.lua,
    session.gd (the `ropes` row), cable_sweep.gd (reuse only). The suite checks: tying makes the key
    send and a compressor with its sidechain on the built-in engine, as one undo step; an offline
    render (MixRender) of two bars of the demo's kick and bass has the bass's level lower on the
    kicks with the rope than without; a 30-frame pull raises the send and lowers the threshold in
    one step; untying removes what the rope made in one step and leaves a compressor that was there;
    the rope's lift follows the estimate. The probe checks that a guest's rope is the host's send.
    Both sides at 0 failed. shots/spatial20.png is the rope taut on a kick.

    Built. Every `StageVoice` has a `StageVoice.Knot` on its stalk, `KNOT_DROP` (3 cm) under the
    ball, a lump of rope taken within `KNOT_REACH`; the ball is taken within `BALL_REACH` (1.3 of
    its radius, was 1.6) and the stalk up to the knot. A drag from a knot draws a loose rope to the
    hand (`StageTable.draw_loose`, naming the voice it is over once), and the let-go ties it to
    the nearest other voice within `TIE_REACH` (7 cm, `drop_target`), else says there is none; a
    press with no drag says how. `StageTable.tie(from, to)` is one edit, `Kick > Bass DI: rope`:
    `DAW.add_fx` of `Sidechain.compressor_choice()` (the built-in "compressor", Reaper's ReaComp)
    when the track has no compressor, then `DAW.create_sidechain`, and the threshold of a
    compressor it added set to `Sidechain.THRESHOLD_SLACK_DB` (-30) once it is there (at once on
    the built-in engine, inside the edit; as it arrives on a guest or by Reaper's poll,
    `_rope_wanted`). The room row is `ropes` (`{"2>6": added}`, project track numbers,
    `Sidechain.rope_key`): the host writes it and publishes the room (`ropes_changed`); a guest
    asks `Session.ask_room(&"rope", [key, tied, added])` (a ROOM_VERB) and keeps its own on top
    until answered (`apply_ropes`); the studio's room carries it and `_on_room_asked` answers it.
    Every key send between two voices on the table is a `StageTable.Rope` (`Sidechain.pairs()`,
    so one the patchbay made too), a CableSweep tube from knot to knot (`rope_spine`, laid on the
    table by `rest_on`) that sags `sag_of` (35% of its span, at most 8 cm, less the more it is
    pulled) and lifts `lifted` = the sag times `ducking / DUCK_TAUT_DB` (12 dB), times
    Ergonomics' motion scale. `ducking` is `Sidechain.ducks`: `Sidechain.reduction(key_db,
    threshold, ratio)` (a hard knee) of the key track's meter plus the key send's level over the
    first compressor's threshold at its ratio, each frame from the table's smoothed meter, the
    same on both engines. A threshold and ratio are read from the plugin's own words while they
    describe the knob, else by its law: ReaComp's threshold as an amplitude, the built-in one's as
    FXCatalogue's -60 to 0 dB. A rope's middle, taken (its frame level with the table, +X along
    it), is pulled by how far the hand goes from the line between the knots: `pull` (0..1 of
    `PULL_MOST`, 20 cm) is `Sidechain.of_pull`, the key send 0 to +6 dB and the threshold -30 to
    -60 dB, written by `StageTable.pull` inside the rope's own edit (`Kick > Bass DI: pull`), and
    read back from the threshold (`pull_of`); the wheel pulls it 5% a notch, Shift 1%. Its card
    is `KICK -> BASS DI · ducks 9 dB on each hit · pull for more`, from the key's heard peak
    (`Sidechain.HIT_DB`, -6, before one is heard), and its hint names the pull, the wheel, the
    cut and the patchbay, in three lines. The X (`StageVoice.cut_key`, a TableKey beside the knot,
    there only while the voice has a rope out) and Backspace over a rope (`reset_under`) cut it:
    `StageTable.cut`, one edit `Kick > Bass DI: cut`, `remove_fx` of the compressor if the row says
    the rope added it and no other key send still feeds that track, then `remove_send`; when another
    does (the snare roped to the bass too), the compressor stays and that key's row is given the
    rope's "added" (`_heir_of`), so the last rope cut takes it away. Only the compressor a key
    reaches counts (`Sidechain.compressor_on` by `Sidechain.listens`, the engine read from the
    DAW's plugin choices so a guest reads it as its host): the built-in AudioEffectCompressor, not a
    hosted plugin with the word in its name; on Reaper a ReaComp, as the bridge's `compressors`
    keys, not a third-party compressor, beside which a rope adds a ReaComp of its own. Undo and the
    `ropes` row: the row is room state, not mix state, so an undo does not carry it, and the host
    keeps it true to the mix at each frame's end (`_reconcile_rows`, asked for by `_refresh_ropes`).
    A row whose key send it has seen and is gone is dropped: an undone tie leaves no row that could
    later take away a compressor someone added. A row that said "added", dropped or cut, is
    shelved, and comes back when its key send does by the rope's own history (the step just
    redone is its `: rope`, or the one just undone its `: cut`), so tie, undo, redo and tie, cut,
    undo both cut away the compressor the rope made; a key send back by the patchbay drops it. A
    DAW that names no steps (Reaper) never brings a row back: there an undone cut's rope cuts as
    one that keeps its compressor, which the desk's X on the plugin takes away. A voice's card says `rope to 6 BASS DI` or `ducks under
    2 KICK`, its hint how to tie one, and the table's top says A KNOT TIES A ROPE; the station's
    desk and hands lines name the knot, the pull and the X. The built-in engine: a key send's bus
    plays into `GodotBackend.KEYS_BUS` ("R3D Keys", muted, made just after the master so every key
    bus can send to it) rather than the destination's mix, and `GodotBackend.listen()` sets every
    AudioEffectCompressor on a keyed track's bus to `sidechain` = its first key bus
    (`key_bus_into`), and back to empty, after any send or chain is built; a key bus follows its
    track's own mute and not the solos. The bridge's `CreateSidechain` sets every ReaComp on the
    destination to its auxiliary input (`set_detector`, by the parameter named detector and the
    setting whose words say aux), adding a ReaComp where there is none (`compressor_added` in its
    answer); `RemoveTrackSend` sets them back to their main input once nothing keys the track
    (`keyed`), in an Undo block of its own. No new verb: ReaperBackend and OfflineBackend are
    unchanged. The suite: `_test_a_rope_ties_a_sidechain_on_the_built_in_engine` (a knot dragged
    to the keys makes the key send and a compressor whose sidechain is the key bus, which plays
    into the muted keys bus, as one step; the row says added; undo and redo; the X cuts both in
    one step; tied to the bass its own compressor listens and Backspace's cut leaves it, listening
    to itself again), `_test_a_rope_ducks_the_bass_in_a_render` (two bars rendered by MixRender
    with every stem, the bass's own compressor off its chain: on the kick's hits the bass is 9.2
    dB lower with the rope, 0.8 dB between them), `_test_a_pulled_rope_ducks_harder_in_one_step`
    (30 frames pulled 60%: the send +3.6 dB and the threshold -48 dB, one undo step that puts both
    back; the wheel), `_test_a_ropes_lift_follows_the_estimate` (Sidechain.reduction; a kick at -16
    dB ducks 10.5 dB and the rope lifts that share of its sag; still with motion held; slack again
    with the kick silent) and `_test_a_guests_rope_asks_the_host` (one edit of intents, add_fx then
    create_sidechain; the threshold asked for when they arrive; the row kept on top until
    answered; a cut is remove_fx then remove_send). The clickable test aims at every knot too.
    tests/bridge_decode_test.lua runs CreateSidechain and RemoveTrackSend on a stand-in Reaper.
    The probe's guest drags a rope at 58.5 on a table of its own from ROPE_FROM (2) to ROPE_TO
    (6) and sees the key send come back by 58.6; the host finds it at 58.67 (and, on the built-in
    engine, the bass's compressor listening to it), as one step named for the rope, which one undo
    takes back (on Reaper, by hand), and now leaves at 58.8. tools/screenshot.gd's `--rope 2,8,0.35`
    ties and pulls a rope at frame 6 and plays the song. shots/spatial20.png is the demo's table
    with 2 KICK roped to 8 GTR AMP, pulled a third of the way and lifted on a hit, and the rope's
    card (`SHOT_CAM="-2.165,-0.75,1.35,1.1,0.74,1.4" SHOT_ARGS="--rope 2,8,0.35 --hover 887,669"
    tools/shot.sh shots/spatial20.png 40 46`), and shots/spatial20_close.png the same up close
    (`SHOT_CAM="-2.165,-0.7,0.55,0.74,0.77,1.3" SHOT_ARGS="--rope 2,8,0.35 --hover 787,542"`).

21. [x] **Signal you can see, and a room that hears the mix.** The proving ideas, #3 and #5.
    `SignalBeads` (hardware/signal_beads.gd) is one MeshBank of small bright beads riding cables:
    the patch cables (PatchCable), the looms' runs (GearLoom), the jacks' leads and cables, the
    modular's cables, and the stage's ropes. They are spaced and paced by the level at the cable's
    source: a track's meter, a send's level times its track's, the master, a jack's last hit. Bigger
    and faster when louder, none where there is nothing. A muted track's loom stops at its strip, a
    send at zero carries nothing, and a jack with nothing playing is still. So "why is there no
    sound" is answered by following the light until it stops. It is brightness and motion, never
    colour, and at motion 0 the beads stand still and the line's brightness alone carries the level.
    The drawing budget (tools/budget.sh) holds: one multimesh for every bead. The room: venues
    already breathe with the master (Venue.hear and pulse). A clip is added: the master or any track
    over 0 dBFS lifts the room's practicals 30% for 0.15 s (heard_hit's shape), at most once every
    FLASH_GAP (2 s), and lights the clipping strip's OVER lamp while it clips. Comfort: the session
    panel gains COMFORT, with Motion (full, gentle at 0.4, still at 0), Room reacts (on or off,
    today's `reactive`), and Lift on clip (on). It is saved in Ergonomics.HEIGHT_PATH beside the
    body and read at launch, and `--no-motion` still wins. Touches signal_beads.gd, patch_cable.gd,
    gear_loom.gd, jack_socket.gd, studio.gd, venue.gd, ergonomics.gd, session_panel.gd,
    master_section.gd. The suite checks: the bead rate goes with the level; no beads on a muted
    track's loom or past a zero send; still beads at motion 0; a track clipping on every beat at 120
    bpm lifts the room at most once in 2 s, by 30% and never more, and not at all with Lift or Room
    reacts off; COMFORT writes and reads back and `--no-motion` overrides it; the bead count stays
    in budget with every cable drawn. shots/spatial21_beads.png is the patchbay with signal running,
    and shots/spatial21_comfort.png the box.

    Built. `SignalBeads` (hardware/signal_beads.gd) extends MeshBank: one MultiMesh of `CAPACITY`
    (640) unshaded beads, committed once and drawn `show_first(n)` deep, so every bead in the room
    is one draw call. It finds what to ride each frame in the `SignalBeads.CARRIERS` group. A carrier
    answers `signal_spine()` (world space, cached against its transform), `signal_length()`,
    `signal_level()` (the fader law, 0.716 is 0 dBFS) and `signal_radius()`. PatchCable carries
    `source_track`'s send `send_index` (set by PatchbaySurface._draw_cables) through the send's
    fader (`SignalBeads.send_level`, the dBs added), so a carried cable and a send at zero carry
    nothing. GearLoom carries its `level_source` along its middle core. `Studio.loom_level` gives
    the console's loom the loudest heard track, the rack's the loudest heard track with a plugin,
    and the deck's the master. "Heard" (`SignalBeads.heard`) is not muted and not left out by a
    solo, so a desk of muted strips sends nothing down its loom whatever the meters show. It is
    constant time: whether anything is soloed (`SignalBeads.any_solo`) is worked out again only
    when MixState.TrackState.solo_version moves (a solo changed, a track came or went), so a
    ninety-track frame of strips, looms and cables costs ninety looks, not ninety sorts of ninety.
    JackSocket carries its lead, or its cable into a bandmate, at `Jacks.level_of` its source.
    Jacks.hit and a keys or harp note-on (`heard_from`) set it, fading over HEARD_FADE (0.6 s), so
    an instrument with nothing playing is still. A note or trigger down a cable into this player
    (`Jacks.received`) sets it too, so a bandmate's lead playing into me carries what I hear
    through it. A third player watching A play into B sees that cable dark: the notes go only to
    B, and the beads are not networked. StageTable.Rope carries `level_between` its key
    and its voice. `SignalBeads.Run` is the same for anything else. There is no modular in the room
    yet; its cables would be Runs. A carrier's level follows its source fast up and slow down.
    Spacing goes in five steps from 15 cm to 4.5 cm, speed from 7 to 42 cm/s times
    Ergonomics.motion_scale, size 1.6 to 2.7 cable radii, and brightness 0.55 to 3.2 of one warm
    white. At motion 0 the beads stand at 9 cm, one size, and only their brightness follows the
    level. Over capacity `allot` shares the bank so every lit carrier keeps at least one bead. The
    room: `Venue.hear_clip(over, delta)` lifts `lift` to LIFT (0.3) and lets it fall over
    LIFT_SECONDS (0.15 s), at most once in FLASH_GAP (2 s), only while `reactive` and
    `lift_on_clip`. `Studio.follow_clip` finds the master or any heard track over 0 dBFS
    (`MasterSection.clipping`) every frame and lifts the practicals (`lift_lamps`: their venue
    energy times 1 + lift, written only when it changes, never under a chaos event's tween). It
    lights the master's new OVER lamp over its meters, with its readout saying OVER
    (`MasterSection.show_over`). A strip's readout says OVER in the over colour
    (`ChannelStrip.show_over`): its lamp is the readout already there rather than ninety new
    objects. Each OVER is held OVER_HOLD (1 s). COMFORT is the session panel's last box: Motion
    (Full, Gentle, Still: Ergonomics.MOTION_STEPS 1, 0.4, 0), Room reacts (Ergonomics.room_reacts,
    which the studio now gives Venue.reactive in place of motion > 0) and Lift on clip (greyed
    while the room does not react). Each has a hover card. Each choice is saved by itself
    (`Ergonomics.save_comfort`) in the `comfort` section of Ergonomics.HEIGHT_PATH, beside the
    height. Bootstrap reads it with `Ergonomics.take_comfort(path, no_motion)`, and `--no-motion`
    then sets Still and a room that does not react. `--seated` is now applied first, so the
    choices after it are no longer lost to its fresh body. The help card's ROOM page has "Signal
    and comfort". The project buttons in the panel flow onto more lines (HFlowContainer): in one
    line they pushed the panel past the screen's edge and every switch in it off. The suite:
    `_test_beads_go_with_the_level` (the rate goes with the level; closer, bigger and brighter on
    the louder cable, one hue; none on a silent one; the pace at full and at gentle; still and
    evenly spaced at motion 0, brightness alone telling them apart; a jack's last hit fades to
    nothing; an unplugged socket carries nothing), `_test_no_beads_on_a_muted_loom_or_past_a_zero_send`
    (a 0 dB send carries its track's level, 12 dB down 12 dB less, at zero nothing; every track
    muted with the meters up, the console's loom and the send carry nothing; a soloed track
    carries again; a track left out by a solo is not heard), `_test_every_cable_is_drawn_within_the_bead_budget`
    (`allot`; 300 loud 2 m cables fit in the bank with none dark; one MultiMesh),
    `_test_a_clip_on_every_beat_lifts_the_room_once_in_two_seconds` (six seconds of a 50 ms over
    every half second: three lifts, 2 s apart, at 30% and never more, gone in 0.15 s; none with
    Lift on clip or Room reacts off), `_test_a_clip_lifts_the_studios_lamps_and_lights_over` (in
    the studio: one bank, every loom and patch cable a carrier; a clipping track lifts the
    practicals 30% and says OVER on its strip, not on the master; the master over lights its
    lamp, with no second lift inside 2 s; both let go after their hold; Room reacts off holds the
    lamps) and `_test_comfort_is_kept_and_no_motion_wins` (round trip beside the height; taken at
    launch; `--no-motion` wins; the box shows the body, fits the panel, has hover cards, and sets
    and keeps each choice by itself). tools/screenshot.gd's `--comfort` opens the panel scrolled to
    the box. shots/spatial21_beads.png is the patchbay with the demo rolling, beads on the sends
    into VERB RTN, closer on the louder, and none on the snare's at that moment (`SHOT_CAM="-1.2566,-0.08,0.95,1.8,1.2,-0.3"
    SHOT_ARGS="--roll" tools/shot.sh shots/spatial21_beads.png 50 56`). shots/spatial21_comfort.png
    is the box (`SHOT_ARGS="--comfort" tools/shot.sh shots/spatial21_comfort.png 30 36`).

22. [x] **Automation by gesture.** The proving idea, #2. Every automatable control (fader, pan,
    mute, send level, a rack knob) has a write bead. While the control is hovered and the song
    plays, a small bead on a thread shows above it, itself a ControlAffordance. A pinch or grab
    pulls it out in a headset, and a drag of the bead does at a desk (its hover card says "drag the
    bead to write automation"; a drag of the control itself is the ordinary drag). Held, the bead
    follows the hand: its height is the value across the control's whole range over 0.5 m, finer
    than the control itself, and the control follows the bead. While it is out,
    `DAW.hold_lane(track, target, true)` stops that lane following, so you hear what you are doing,
    and the control's writes are ordinary sets inside an edit (and are not touch passes, even on a
    track in touch or latch). The bead keeps its own points, each at the song position this player
    heard when it was made, as everything played is stamped, so a guest's pass is in time. A value
    held still still makes a point every 50 ms. Looping, the pass records only inside the loop: it
    punches in when the playhead enters the loop, and at a wrap, or on leaving the loop, the pass
    ends: its points replace the lane over the pass's span, written with DAW.set_automation (one
    call), and its edit closes. Holding on opens the next pass and edit. Not looping, it records
    from where it began and ends on let-go. So each pass is one undo step that restores the lane and
    the control. On let-go hold_lane is released. `_writes_lane`'s touch passes are not used, so no
    automation mode is changed and a hold cannot time out. On Reaper hold_lane is the bridge's
    HoldLane (the envelope's active flag off, and back), and set_automation is the bridge's existing
    handler. Capability LANE_HOLD; without it the bead's card says `the lane plays over you while
    writing`. The lane shows on the 3D lanes and in the 2D view's automation lanes (FlatHost) for
    cleanup. Touches control_affordance.gd (`automation_target()`), write_bead.gd (new, core/input),
    fader.gd, knob.gd, channel_strip.gd, rack_unit.gd, mouse_interactor.gd, daw.gd, daw_backend.gd,
    offline_backend.gd, godot_backend.gd (a held lane not followed), reaper_backend.gd,
    dawlings_bridge.lua. The suite checks: a bead pass over a looped stretch records points only
    between the loop's ends; two wraps make two undo steps, each restoring its pass; a value held
    still for 2 s mid-pass is a flat stretch in the lane; FlatHost's lane has the points; not
    looping, it records from where it began; a held lane is not followed, and is followed again
    after; no track's automation mode changes; an FX parameter and a send are written; a guest's
    pass lands at the guest's song positions, not shifted by the latency; a drag of the control
    itself while playing is an ordinary drag. The probe checks that a guest's pass is the host's
    lane at its song positions. Both sides at 0 failed. shots/spatial22.png is a bead held over a
    fader with the lane below.

    Built. `WriteBead` (core/input/write_bead.gd) extends ControlAffordance. Each Interactor makes
    one the first time it is on an automatable control while the song plays (`Interactor.bead`,
    `_tend_bead` after the press each physics tick), and `tend` shows it over that control:
    `bead_anchor()` (a fader's is over the top of its travel, out from the panel) on a thread from
    `bead_foot()` (a fader's cap). It faces the viewer, is kept LINGER_SECONDS (0.8 s) after the
    hand leaves the control so the hand can reach it, and is not shown over a held or claimed
    control or over one another hand's bead is on. A control says what it writes with `automates`,
    asked as `automation_target()`, which gives [track, target] or []: a strip's fader "volume", or
    flipped to a return "send:<dest>"; its pan "pan" (none while flipped: a send's pan has no lane);
    its mute "mute" (written through `bead_writes`); a rack knob "fx:<slot>:<param>" for whatever
    parameter it means then; and the master's fader and balance on track 0. Pulled (the base grab
    contract, so a pinch, a trigger or a click), it calls `DAW.hold_lane(track, target, true)` and
    opens an edit named "Kick: level automation". Its height from where it was taken, over
    RANGE_METRES (0.5 m), is the control's whole range (Shift a tenth of it). In a headset the
    height is the hand's own (`catch_point`), and at a desk it is the drag's point in the plane of
    the screen through the bead. Each value is written through the control (`write_from_bead`:
    Fader `_set_value`, Knob turns and emits `turned`), so the control follows the bead and the mix
    follows the control. Meanwhile the control is `is_held()` (its `bead`): it ignores echoes, takes
    no hand, and no bank or page moves under it. `network_key()` is the control's, so its claim
    holds the control for everyone. Each physics tick it `follow`s what this player hears (`heard`:
    GuestMidi.heard, as every take is stamped, or `heard_source`). It keeps a point at least every
    POINT_SECONDS (50 ms) of song, at the heard position, so a still hand is a flat stretch. A pass
    begins where it is rolling: anywhere not looping, inside the loop while looping, and at the
    loop's start when it came in from before or wrapped. It ends when the heard position goes back
    (a wrap, to the loop's end, or a seek), leaves the loop by PAST_LOOP (0.15 s), the loop is
    switched, the song stops, or at the let-go. Ending writes `merged`: the lane's points outside
    the span are kept, pinned EDGE (1 ms) either side to what the lane was (or the control's value
    before the bead, for a lane that had none), and the pass's points go between, thinned to the
    wire's AUTOMATION_POINTS_MAX. It is one `DAW.set_automation`, inside the edit, and then the edit
    closes. Held on, the next edit opens at once. A pass shorter than a point (a let-go at a wrap's
    instant) writes nothing. A still bead rewrites its value every second so a long pass's edit is
    never closed as idle (`write_from_bead(v, true)`: a control that writes only changes, the
    mute, writes it anyway). At the let-go it writes what is open, closes the edit, releases the hold
    and lets the control settle (`_hold_against_echoes`). One pass per player at a time. The
    backend side: `DAWBackend.held_lanes` ([track, target] -> acting_peer), `hold_lane` (a lane another
    player holds is neither held nor let go by anybody else), `lane_held` and `release_lanes_of(peer)`, called by `DAW.close_edits_of` when a player leaves. It is a DAW
    verb, a guest's an intent checked like set_automation's (a target DawKitAutomation names, only
    volume and pan on the master), and not history. OfflineBackend (and the built-in engine, which
    plays what it leaves on the controls) does not follow a held lane in `follow_automation`, and
    `_writes_lane` makes no touch pass of one, so no automation mode is changed. Let go, it is
    followed again at once. ReaperBackend's `_hold_lane` is the bridge's `HoldLane`, sent at once
    and never batched: the envelope's ACTIVE flag off (still visible) and back to what it was. The
    bridge's `held_lanes` keeps a pass's SetEnvelope from switching it on again, and the timeline
    poll reads a held envelope as playing, so no lane vanishes from anyone's desk. Reaper has
    LANE_HOLD only with the bridge, and the bead's card says "the lane plays over you while
    writing" without it. On Reaper the bead's OSC writes stay Reaper's own undo points (as every
    OSC write in an edit does), and a track Reaper itself has in touch or latch may also write its
    own envelope from them. The 3D timeline shows the lane being written: the studio's
    `WriteBead.on_pull` picks the track and `show_lane`s the target. Discoverable: the control's
    hover card (`card_hint`) adds "the bead above writes automation" while the song plays, the
    bead's own says "drag the bead up or down to write automation · shift for fine" and reads the
    value with "writing" or "waiting for the loop" (and a ring round it while writing, so not by
    colour), and the help card's START page has "Automation". The suite:
    `_test_a_looped_bead_pass_writes_inside_the_loop_a_step_a_pass` (looping 2-6 on a track in
    touch: punched in at the loop's start, points only between the loop's ends, the lane outside as
    it was, 2 s held still a flat point every 50 ms, FlatHost's lane the same, the held lane not
    followed and followed again after, two wraps two steps each undone to its pass, a let-go at the
    wrap no third, no mode changed and no touch pass), `_test_a_bead_not_looping_records_from_where_it_began`
    (10 to 12 s, one step undoing pan and lane), `_test_a_bead_writes_a_plugin_parameter_a_send_and_a_mute`,
    `_test_a_guests_bead_pass_lands_at_its_song_positions` (heard 0.3 s behind the host's playhead:
    intents hold, edit, sets, the lane, close, release, at the guest's positions; carried out by the
    host as its lane, one step; malformed holds refused; a leaving guest's hold released) and
    `_test_a_bead_shows_over_a_hovered_control_and_its_drag_is_ordinary` (shown only while playing,
    over the travel's top, lingering, gone while the fader is held, whose drag is one ordinary step
    with no lane; the card without LANE_HOLD). tests/bridge_decode_test.lua checks HoldLane. The
    probe: the guest's bead rides BEAD_TRACK's fader at 58.74 to a clock of its own from 640 s, and
    the host finds its lane at those positions, a point each 50 ms, rising, let go, one step undone;
    the guest has the lane back by 58.81. The host's end moved to 58.9. shots/spatial22.png is the
    lead vox fader's bead held mid-pass on a 2.4 s loop, its card saying "writing", and the pass's
    wave on the timeline's VOLUME row above (`SHOT_ARGS="--bead LEAD_VOX__LEVEL@40 --shot-tick 330"
    tools/shot.sh shots/spatial22.png`).

23. [x] **Items made while playing, and clips as cassettes.** The proving idea, #4, first half. Made
    items, slots and clip packing as decided: `ItemRoom.mint`, `Session.made` and its `_made`
    message, the `make` and `slot_item` room verbs, ItemRoom.holders, MADE_BYTES, MADE_TOTAL and
    MADE_MOST, the ghost in the glove, MixWire.`pack_item`, and ItemState.`part` played by
    GodotBackend. `CassetteItem` (core/items/cassette_item.gd) is lettered with its clip's name,
    track and length. It carries the clip packed and where it came from. Pulling: drag an item out
    of the 3D timeline's face, past PULL (8 cm) toward you with a hand, or off the timeline's edge
    with the mouse, and the host mints a cassette of it in that hand. The arrangement does not
    change: it is a copy. The cassette rack, a visible clipboard: twelve slots on a wall rack beside
    the prop shelf (`Venue.cassette_rack_spot`, a free-standing station in the clearance loop),
    holder `rack`. A full rack says so, and the BIN at its end retires one. Handing over: thrown and
    caught, as any item is; held within 0.25 m of a bandmate's ghost glove for 0.5 s; or at a desk,
    clicked on their ghost while carried. The room verb `give` [id, peer] puts it in their hand.
    Touches item_room.gd, cassette_item.gd, mix_wire.gd, mix_state.gd (`part`), godot_backend.gd,
    timeline_lanes.gd, timeline_surface.gd, venue.gd, studio.gd, session.gd (`made`, ROOM_VERBS
    `make`, `slot_item`, `give`), presence.gd (the ghost's glove as a target), stations.gd (HELD
    line), tools/blender/cassette.py. The suite checks: pulling makes a cassette whose data is the
    item's, and the timeline is unchanged; its id is `cassette1`, `kind_of` answers `cassette`, and
    `look_of` gives its look; a guest's pull is asked, held as a ghost, and dropped when refused
    (MADE_MOST, MADE_TOTAL, a data past MADE_BYTES); a two-minute MIDI clip with a bend on every
    beat packs under MADE_BYTES, and an hour-long audio clip packs with no peaks; a put-down after a
    mint republishes the room with no made data in it; the rack keeps cassettes in their slots in
    room state and refuses a thirteenth; `give` moves one to the bandmate's hand; the bin retires
    it; made items and their data reach a guest who joins late; a pulled demo item packs its part
    and window; the shelf count stays (made items are not shelf kinds). The probe checks that a
    guest's pull becomes a host-made cassette in the guest's glove on both sides, and that a give
    from host to guest arrives. Both sides at 0 failed. shots/spatial23.png is the rack with three
    cassettes.

    Built. Made items are ItemRoom's (docs/architecture.md, "Items made while playing"). They are
    MADE_KINDS ([cassette]) and never KINDS, so the shelf keeps its 22, `spawned_ids` leaves them
    out, and a Tour run's end does not swallow them. `mint(kind, data, maker)` refuses past
    MADE_MOST (64), MADE_BYTES (256 KiB) or MADE_TOTAL (4 MiB), and `mint_refusal` says which.
    Otherwise it picks the next id never given in this room and keeps the row
    [kind, maker, var_to_bytes(data)] in `made`, which is `Session.made` itself. It then spawns
    the item at its home, the rack's tray (`made_home`, `CassetteRack.tray_spot`). The room state
    names only `"made"` ids and where each one is, ["slot", holder, n] for a slotted one. The row
    travels once: `Session.publish_made` sends `_made` to every guest, `admit` sends it before the
    room, and `drop_made` sends `_unmade`. A guest's `_made` keeps only a made id of its own kind
    within MADE_BYTES and MADE_MOST. `apply_made` makes real what the room names and the row is
    here for, and removes what it no longer names. `MixWire.pack_item` packs the clip:
    notes and controls as PackedFloat32Array, a file by name with its offset, fades, gain, loop and
    reversal, never peaks, and a demo item's `part` (its own, else its track's) with its window.
    `unpack_item` sanitises it as a lane from a peer is. `ItemState.part` rides the wire in
    `_pack_items`, a split keeps it, and GodotBackend plays it (`part_of`, `_roles`), so a demo clip
    pasted elsewhere plays what it was cut from. `CassetteItem` is tools/blender/cassette.py's
    100 x 64 x 12 mm cassette (label, window, hubs, tape and screws). Its label is lettered on both
    faces with the clip's name and "TRACK · n bars". Its card reads MIDI, audio or the demo's part,
    the track it came from, its length and where it is. Pulling is in `TimelineLanes`: a press on
    an item records how far out of the face the hand was. The drag is pulled out
    (`pulled_out`) when a hand has come PULL (8 cm) toward you, or the point is PULL_EDGE (4 cm)
    past the lanes' edge, which a mouse can do. The preview goes, nothing moves and nothing enters
    the history, and the surface emits `clip_pulled(track, index, hand)`. The lanes' card says "off
    the edge for a cassette of it". The studio's `_on_clip_pulled` has the host mint it into the
    pulling hand. A guest predicts `make` [kind, "clip:t:i"] and holds a blank look-alike
    (`look_of`) that follows its hand (`_making`). The host's `make` mints from its own song,
    `Session.hand_to` puts it in the guest's hand by the holds, and the room names it. The guest's
    `apply_room` settles the ask by its ack: the look-alike goes, and `_take_given` puts the made
    one in the waiting hand, or a free one. A refusal is told to the asker, and its look-alike
    goes. The cassette rack (`CassetteRack`, tools/blender/cassette.py) is a station in the live
    room, `cassette_rack` in Stations.ALL beside the prop shelf (`Venue.cassette_rack_spot`), and a
    walker solid. It has twelve face-out ledges (holder `rack`), a tray and the BIN (holder `bin`).
    Item gains `slot_in`/`slot_n`: slotted is LOOSE at the slot's pose and never tidied away.
    `slot_item` is a hand's (a guest's is the room verb `slot_item`). A put-down within SLOT_REACH
    of a slot, or aimed at a free one, slots it. A click on the rack's face shelves into the free
    slot nearest the click, and a click on the BIN bins. A taken slot or a full rack is told, not
    done. The bin on the host is `unmake`: gone everywhere, "Binned cassette N.". `give`
    [id, peer] is a room verb, from the item's holder to someone in the room. The host carries it
    out with `_give`: the holds first, then a hand here if it is the host's. At a desk, a click
    with a cassette in hand on a bandmate's ghost gives it (`Presence.peer_at`, within 0.35 m of
    their head or chest along the ray). In a headset, a hand held within GIVE_REACH (0.25 m) of
    their glove for GIVE_HOLD (0.5 s) gives it (`Presence.glove_near`). The guest's own glove lets
    go into theirs meanwhile (`palm_of`). The host's made items and their places are kept beside
    its layout (`LayoutProfile.made`, `<profile>_made.bin`, written only when changed), and are
    restored when the room is built again. Long toasts now wrap in the session panel
    (TOAST_WIDTH), so a station's or a cassette's line fits a 1600-wide window. The welcome card's
    TOGETHER page has "Hand it over". The suite:
    `_test_a_clip_pulled_off_the_timeline_is_a_cassette_in_the_hand` checks:
    - a mouse drag off the lanes' edge is cassette1, kind cassette, in the hand, the arrangement
      and history unchanged;
    - `look_of`;
    - the demo item's part and window;
    - the room naming it without its clip;
    - let go by a slot, it is shelved, with ["slot", "rack", 0] in the room;
    - twelve by the face, then a thirteenth refused, and a taken slot refused;
    - the BIN retires one;
    - ids are never reused;
    - a studio built again has them back in their slots.

    `_test_a_cassette_packs_its_clip_whole_and_small` checks:
    - a two-minute take bent 60 times a second packs to 122 KiB, under MADE_BYTES;
    - an hour of audio packs to 308 bytes with no peaks;
    - fades, gain, loop and file by name round-trip;
    - a demo part plays on another track and reaches a guest's mirror;
    - each of the three limits refuses.

    `_test_a_guests_pull_is_a_ghost_until_the_host_answers` checks:
    - the ask names the clip;
    - the look-alike follows the hand;
    - the row is kept until the room names it;
    - the answer is the made cassette in the pulling hand;
    - a refusal drops the look-alike;
    - bad rows are refused;
    - `_unmade` removes it;
    - leaving clears the rows.

    `_test_the_host_mints_a_guests_pull_and_cassettes_are_handed_over` checks:
    - the guest's pull is minted into its glove by the holds;
    - the room grows by the name, not the clip;
    - a put-down sends no clip;
    - a guest's slotting;
    - each refusal through `make`;
    - `give` only from the holder to a member, guest to host and host to guest;
    - `peer_at`, `glove_near`, and a headset's hold-to-give;
    - a click through the mouse hand's own tick on a bandmate standing in front of a fader hands
      it over and leaves the fader alone; with them behind it, the fader is under the hand;
    - a late joiner's room makes it, slotted, from the rows.

    `_test_a_players_own_cassettes_wait_while_they_are_a_guest` checks:
    - joining sets the player's own cassettes aside (`Session.join` clears its rows and their
      items) without saving over the layout;
    - the host's room may then carry MADE_MOST - 1 of its own, ours counting nothing;
    - leaving gives the host's back and ours again, in their slots (`Studio._restore_made`, only
      what is missing);
    - the next mint keeps all three, on disk too.

    A click on a bandmate is theirs even with a control behind them: `ItemRoom.press_ahead` (the
    studio's `_press_ahead`, from `Presence.peer_along`) says how far along the ray a made item's
    hand-over target stands, and the Interactor drops a control further than that from the hover,
    so the press is the item's. A hand-over toast names the clip as the song has it: "Handed the
    Kick Verse 1 cassette to Grace."

    The probe: the guest asks `make` for clip 2:0 at 58.86. The host mints cassette1 into the
    guest's hand and, at 58.9, hands it a cassette2 of its own. By 58.97 both halves find both
    cassettes in the guest's glove, with the rows the same. The host's end moved to 59.0.
    shots/spatial23.png is the rack with Kick, Snare and Hat cassettes in its top row, the Hat
    one hovered (`SHOT_ARGS="--cassettes 3 --hover 770,243" tools/shot.sh shots/spatial23.png 200
    206`; the station's framing settles a little differently each run, so the hover point may
    need moving). The lettering on the cassettes is pen-sized (about 9 mm) and at the station's
    distance is too small to read at 1600x900. On a desktop the name comes from the hover card
    ("CASSETTE  Hat Verse 1", its track, length and slot). The rack's plaque runs off the
    bottom of the frame, as spatial19's does.

24. [x] **A cassette onto a track.** #4 finished. `DAW.paste_item(track, start, packed)`:
    OfflineBackend makes the ItemState from the packed clip (`MixWire.unpack_item`) at `start`,
    `part` and all. The bridge's PasteItem makes it in Reaper (CreateNewMIDIItemInProj with its
    notes and CCs, or AddMediaItemToTrack with its source, offset, fades, gain and loop). It is one
    undo step under Capability PASTE_ITEMS. It refuses a frozen track, MIDI onto a track that takes
    none, an audio source the host does not have, and a demo part on Reaper, and each says so.
    Pasting is a press, not a let-go: a cassette held over a timeline lane and pushed into the
    lane's face (a crossing, as Strike reads one), or with a controller's trigger pressed while its
    grip holds the cassette, pastes there at the hovered time, snapped to the beat unless fine. Over
    a console strip or a stage voice it pastes on that track at the playhead. The cassette stays in
    the hand, since a clipboard pastes again, and letting go still puts it down, slots it or throws
    it. At a desk: carry it and click where it goes. A guest's paste is an intent naming the
    cassette, its track and time, and the host pastes the data it holds. Touches daw.gd,
    daw_backend.gd, offline_backend.gd, reaper_backend.gd, dawlings_bridge.lua, mix_wire.gd,
    cassette_item.gd, timeline_lanes.gd, channel_strip.gd, stage_voice.gd. The suite checks: MIDI,
    audio and demo-part cassettes paste items equal to their sources but for start and track, and a
    pasted demo part plays its own part on the built-in engine; the snap and fine; the four
    refusals; undo takes it away; a let-go over a lane does not paste; a guest's intent carries its
    time; the bridge decodes PasteItem. The probe checks that a guest pastes a host-made cassette
    onto track 4 at bar 30. Both sides at 0 failed.

    Built. `DAW.paste_item(track, start, packed)` is host-only and outside COMMANDS: it returns
    "" when pasted and otherwise why not, from `DAW.paste_refusal`. The reasons are checked in
    this order: no PASTE_ITEMS (Reaper without the bridge), no clip, no such track, a frozen track,
    a clip with no notes, controls, file or part, a source file not on this machine (`media_path`),
    a demo part where the backend lacks the new Capability DEMO_PARTS (Reaper), and MIDI onto a
    track whose input is an audio one ("takes no MIDI"). The empty clip is what a cassette of a
    Reaper item's own audio is: the cache knows a file only for takes recorded through the desk
    (`take_peaks`), and pasted down the MIDI path it would be an empty MIDI item, so it is refused
    with the reason. Carrying Reaper's own audio by its full path is left for later: a cached
    `source` turns on the desk's own stretch, reverse and overview paths for that item too. Its step is named for the track (NAMED_BY_TRACK: "Hat: paste item").
    `DAWBackend._locally_paste` lands the unpacked ItemState in a copy of the lane
    (`_land_in_lane`) at `start`. Its overview comes from the file here (`take_peaks`, reversed
    when it is), since a clip carries no peaks. OfflineBackend.`paste_item` wraps that in one
    `_remember_edit`, so one Ctrl-Z takes it back. ReaperBackend shows it on the cache at once and
    sends the bridge's `PasteItem` as one flat list (`paste_request`). Notes and controls are in
    project seconds. The source is a full path, which the bridge copies into a saved project's
    media folder. PasteItem refuses a missing track, an empty length or a missing file. In one
    undo block it makes a MIDI item (CreateNewMIDIItemInProj, notes and CCs) or an audio one
    (AddMediaItemToTrack, its source, offset, length, fades and their shapes, gain, loop and
    reversal), then rebuilds peaks. Reaper loops the item's whole file, not its loop window.

    The press is in the Interactor, not in each surface. A ControlAffordance has `paste_spot(at,
    fine)`, which for a strip's or voice's controls is [track, playhead] from `pastes_onto`, and for
    the lanes is their `drop_spot` (snapped unless fine). An `Item.pastes()` one in the hand (a
    cassette with a clip), pressed on such a control, goes to `ItemRoom.paste` and
    `paste_pressed` in place of the control's own press. A headset hand (`pushes_to_paste`) also
    pastes by crossing into a pasting control's face from outside, a ray from last tick's hand to
    this one that leaves out the cassette itself. Held in and drawn out does nothing more, and a
    new push pastes again. A jump is not a push: a step longer than PUSH_MAX_STEP (0.25 m) in one
    frame pastes nothing, XRRig._arrive forgets where every hand's cassette was (`forget_push`)
    when the play space travels, and a bare hand pushes only on frames it is tracked with every
    joint seen (`push_tracked`, HandGestures.confident), this one and the last. Letting go is as it was: put down, slotted or thrown. The cassette stays
    in the hand. The control's card says what a press would do: "click pastes the Rhodes Intro
    cassette onto OH L/R at 20.1.00; Q puts it down", or the trigger or a push in a headset
    (`Interactor.paste_press_words`); a tracked bare hand, which has no trigger, is told of the
    push alone, on the card and in the held cassette's notice. Every
    strip control but the send socket pastes, as do the stage voices and the table's name grips.
    The studio's `paste_cassette` tells the paster, and the host when a guest pasted. A guest
    predicts the room verb `paste` [id, track, seconds] (ROOM_VERBS). The host pastes the clip of
    its own row for that id, only when the asker holds it (`Session.holder_of`), and tells it why
    not otherwise. The cassette's held hint, the welcome card's TOGETHER page ("Paste it") and the
    lanes' hint say so.

    `_test_a_cassette_pastes_onto_a_track_as_the_clip_it_was` checks:
    - a MIDI take pasted by the trigger onto Track 4's lane, snapped to the beat, equal to its
      source but for start and track, as one undo step named for the track;
    - undone, it is gone;
    - fine, it goes off the grid where it was pressed;
    - a let-go over a lane pastes nothing;
    - a push into the face pastes, held in pastes nothing more, and a fresh push pastes again,
      while a mouse moving in does not;
    - a one-frame jump through the face, a step across a travel, and a step from or to a frame
      the hand was not seen well on paste nothing, and a bare hand's card names only the push;
    - an audio cassette on Track 5's strip pastes at the playhead with its file, offset, fades,
      gain and loop, and its overview drawn here;
    - a demo cassette on a stage voice pastes its window and plays the part it was cut from, not
      its track's.

    `_test_a_paste_is_refused_and_says_why` checks:
    - a frozen track, MIDI where none is taken (though audio goes there), a missing file, no such
      track, no clip and a clip of nothing (a Reaper item's own audio) are each refused with the
      reason, and nothing is pasted;
    - a guest's DAW never pastes itself;
    - Reaper without the bridge says so, and a demo part on Reaper is refused for the built-in
      engine;
    - with the bridge, a MIDI cassette is one PasteItem with its notes in project seconds, shown
      on the cache, and an audio one names its file by path, offset and loop.

    `_test_a_guests_paste_names_its_cassette_track_and_time` checks:
    - a guest's press is asked as `paste` naming the cassette, track and time, never the clip;
    - from someone not holding it, nothing is pasted;
    - the host pastes its own row's clip there and is told who pasted what where;
    - a refused one pastes nothing.

    tests/bridge_decode_test.lua decodes PasteItem and runs its MIDI, audio and refusal paths
    against a stand-in reaper. The probe: at 58.99 the guest asks `paste` for the host-made
    cassette2 on track 4 at bar 30. At 59.08 both sides find the pasted item, and the guest has
    the "Pasted" notice. On Reaper, a demo-part cassette expects the built-in-engine refusal
    instead. At 59.1 the host undoes it and unmakes the made items. The host's end moved to 59.14
    and the guest's to 59.32. shots/spatial24_paste.png is the Rhodes Intro cassette clicked onto
    OH L/R's lane a third of a beat past bar 20 and pasted on the beat
    (`SHOT_ARGS="--paste 7:5@20 --no-hud" SHOT_CAM="0,-0.05,1.0,0.15,1.45,-1.0" tools/shot.sh
    shots/spatial24_paste.png 30 36`). The cassette is in the hand. The toast says where it went,
    and the card under the pointer says what the next click would paste. The timeline's view
    is held within the song's length (`_clamp_view`), which cannot frame bar 30 of the demo song,
    so the shot uses bar 20.

25. [x] **Hold a cassette to your ear.** The proving idea, #13. A cassette (or a sample, slice 26)
    held at the ear (XRInteractor.HEAD_REACH, as headphones are put on) plays its clip to this
    player alone, from its start, looping, at its own gain, until taken away. A desk holds L while
    carrying one. It plays on MONITOR as a cue (Ears), never the mix, and the room ducks 10 dB for
    this player meanwhile. MIDI clips are rendered here (DawKitTine.render_notes, and ItemVoices for
    channels 9 and 10), and a demo part by DemoSong.render_window. Audio clips play their file where
    this machine has it: the host, or a guest once FileSend has fetched it (the tag says FETCHING).
    Where the file cannot be had, the tag says `not on this machine`. Touches cassette_item.gd,
    ears.gd, xr_interactor.gd, mouse_interactor.gd, file_send.gd, studio.gd. The suite checks: at
    the ear it starts, and away it stops; nothing reaches the Mix bus; the MIDI render's length is
    the clip's; a demo cassette plays its part's window; a guest without the file asks once and
    plays when it arrives; L at a desk. The probe checks that a guest's ear on an audio cassette
    fetches the host's file. Both sides at 0 failed.

    Built. `EarCue` (core/audio/ear_cue.gd, one per studio, `Studio.ear`) plays the cassette at an
    ear here. `Studio._follow_ear` asks every hand each frame (`Interactor.cassette_at_ear`): a
    headset's, the cassette's middle within XRInteractor.HEAD_REACH (0.22 m) of the eyes, and away
    again only past HEAD_REACH + EAR_LEAVE (0.06 m), so a hand wavering at the edge does not start and
    stop it; a desk's, L held while carrying one (`MouseInteractor.ear_held`, taken before the studio's
    lean sees the key, and let go when the cassette leaves the hand). Held up, the desk's cassette
    rides raised beside the view (`EAR_AT`), tipped toward you. The clip plays on the keys' bus
    (AudioPorts.MONITOR) as a cue, from its start, looping, at its own gain. `Ears.cue` takes the Mix
    bus, the room's sounds and any cues CUE_DUCK_DB (10 dB) down for this player while it sounds, and
    keeps the keys' bus heard even where a personal mix leaves it out. MIDI is rendered on a worker
    (`EarCue.midi_frames`: GodotBackend.render_midi_frames, the tine and ItemVoices for channels 9
    and 10, now split out of `render_midi` with `wav_of`), exactly the clip long, its tail added
    onto its start. A demo part is `EarCue.demo_samples`: DemoSong.render_window through the song's
    tempo map and meter, each window from its loop's first bar to the next's, the clip's start to its
    end. Both are made into their streams on the worker (`midi_stream`, `demo_stream`); a render goes
    on when the cassette is taken away, is kept when done, and is picked up if it is held up again,
    so changing cassettes never waits for one. Audio is its file (`clip_stream`): the stream loops the clip's stretch from its offset; one
    with a loop of its own is started again every clip length; a reversed one plays the file backwards.
    The host plays it from its media folder. A guest asks `FileSend.fetch` once by name. The host
    (`fetch_asked`) sends only a file something in the room plays (`_plays_here`: an item of the
    song or a made cassette's clip), a slice at a time on FILE_CHANNEL, into the guest's
    `user://fetched`, which goes when it stops being a guest. Meanwhile the tag says FETCHING, and
    the clip plays as the copy lands. Refused, or with no file anywhere, the tag says `not on this
    machine` and keeps it once lowered. A clip of nothing (a Reaper item's own audio) says "nothing
    to hear". Renders are kept (six), so a cassette held up again plays at once. The tag is the
    cassette's lower line (`CassetteItem.hearing`: RENDERING, AT YOUR EAR, FETCHING, ...), and one
    notice says what it plays and how to stop it. Discoverable: the held cassette's card and notice,
    the cassette rack's desk and hands lines, and the welcome card's TOGETHER page ("Listen to it").

    `_test_a_cassette_at_the_ear_plays_to_this_player_alone` checks:
    - L held at a desk with a MIDI cassette starts it, RENDERING then AT YOUR EAR, and is no lean;
    - the render is the clip's length to the frame, looping, the clip's notes with the tail rung in;
    - it is on Monitor alone, never the Mix bus, the Mix and the room 10 dB down, the keys not;
    - one notice; nothing changed in the song;
    - L let go stops it and the room is as it was; held up again, the kept render plays at once;
    - drums and bells (channels 9 and 10) are rung, the clip long;
    - a headset hand: held out, nothing; at the ear, it plays; just past the edge, still; away, it
      stops; back at the edge, not again until within HEAD_REACH.

    `_test_a_demo_or_audio_cassette_at_the_ear_plays_its_own_sound` checks:
    - a demo cassette renders, then plays its part's window from the clip's start, the clip long;
    - an audio cassette plays its file at once on the host, from its offset, the clip's stretch
      looping, at its gain; a looped one goes back to its start each clip length;
    - a file this machine lacks is `not on this machine`, said, and kept on the tag once lowered;
    - a clip of nothing has nothing to hear, and says why.

    `_test_a_guest_fetches_an_audio_cassettes_file_once_to_hear_it` checks:
    - a guest without the file asks the host once by name, FETCHING meanwhile, and says so;
    - lowered and raised again, it does not ask again;
    - it plays as the copy arrives, byte for byte the host's, from `user://fetched`;
    - the host refuses a file nothing in the room plays, and a path, and the copy here is untouched;
    - no longer a guest, the copies go.

    The probe: at 59.12 the host mints an audio cassette of a file only its media folder has (`Probe
    Ear <port>.wav`). At 59.2 the guest's EarCue holds it, FETCHING, asked once. By 59.32 the copy is
    in its fetched folder, byte for byte the host's, and plays on Monitor. At 59.34 the host has sent
    one file whole (`FileSend.fetches_served`), then unmakes the cassette and deletes the file. The
    host's end moved to 59.38 and the guest's to 59.56. shots/spatial25_ear.png is the Rhodes Intro
    demo cassette held up with L, AT YOUR EAR on its tag and the notice saying what it plays
    (`SHOT_ARGS="--ear 7" tools/shot.sh shots/spatial25_ear.png 240 246`: a long demo part takes a
    few seconds to render in a window).

26. [x] **Anything can be a sample.** The proving idea, #12. The sampler is a station (`sampler`, a
    small pad bank with a mic on a gooseneck beside the cassette rack). Its REC is a room row
    (`sampler` [the peer who pressed it, or 0]). One press of REC catches one sound: the next use,
    by anyone, of an item within 1.5 m of its mic, or of one held by whoever pressed REC: the duck
    squeezed, the cowbell hit, the shaker shaken, the ball bounced, the yo-yo, the cards. Then REC
    goes off, so it is a sample a press, never a file a hit. The sound is Foley's for that use's
    kind and `take`. `item_used` gains `take`, as slice 17 gave it to `item_hit`, so the host makes
    exactly the sound the player heard. The host writes it as a WAV into the project's media folder
    (`duck_squeeze_3.wav`) and mints a sample cassette into the rack. A rhythm squeezed while
    recording is already recorded, as hits on the armed or jacked track (HitRecorder), and plays
    back as hits (slice 16). To make a sample a track of audio, paste its cassette (slice 24).
    Sample cassettes go to the ear (25), onto tracks (24) and into the grain cloud (54). Touches
    sampler.gd (new, core/music), foley.gd (`take_of(use)`), session.gd (`take` on item_used),
    cassette_item.gd, item_room.gd, studio.gd, venue.gd, stations.gd. The suite checks: a squeeze
    after REC writes one WAV equal to Foley's stream for that take and mints a cassette, and REC is
    off after; a second squeeze writes nothing; out of the mic's reach nothing is caught; REC off
    does nothing; a guest's squeeze is sampled on the host with the guest's take; REC replicates.
    The probe checks it from the guest. Both sides at 0 failed. shots/spatial26.png is the sampler
    with two sample cassettes.

    Built. `Sampler` (core/music/sampler.gd, station `sampler`, model tools/blender/sampler.py) stands
    with its back to the outside of the vocal booth's front wall, a step from the cassette rack, facing
    the front of the live room (`Venue.sampler_spot`; none in the Rig Roulette room, which has no
    booth). The floor beside the rack is too narrow for it: the booth starts 0.29 m past the rack. It
    is a cabinet with eight pads and a round REC key on its deck, a screen along the back and a mic on
    a gooseneck bent over the pads. REC is the room row `sampler`, the peer it is armed for or 0
    (`Sampler.armed_by`), asked by a guest with the room verb `sampler` [on] and shown at once. A
    press while it is on turns it off. The key lights, says REC ON, and its card and the screen say
    whose next sound it waits for (REC · YOUR NEXT SOUND), so it is never colour alone.
    Every use now carries its take: `Item.use_take`, sent as `Session.item_used`'s `take` (cleaned like
    a hit's, `Session.clean_take`), and rung by every copy (`Item.heard_use`). The duck's squeak is
    a take of its own (`Foley.squeak_take`, its tuning baked in, not a random pitch), and an
    instrument's sound is named (`InstrumentItem.sound_kind`). `Foley.take_of(kind, take)` is the one
    stream for any of them. Only the host catches (`Sampler.heard`): its own hand's uses and hits, and
    a guest's use or hit of something in that guest's hand, with the guest's take. It catches one within
    REACH (1.5 m) of the mic, or anywhere by whoever armed it. It writes the stream's own samples
    after a header at Foley's rate (`Sampler.write`, `AudioTake.header` now takes a rate) to
    `DAWBackend.media_path`, the kind and the next free number (`duck_squeeze_1.wav`,
    `tambourine_hit_1.wav`). It mints a cassette (`Sampler.sample_data`: an audio clip of the whole
    file, `sample` in its data) into the rack's first free slot, turns REC off and tells the presser
    what it caught and where it went. A sample cassette is lettered `SAMPLE · 0.26 s`
    (`CassetteItem.is_sample`). It goes to the ear, the guest fetching its file, and pastes as audio.
    The ball bounced, the yo-yo's trick and the cards' trick are caught too. A trick is a use
    (`FidgetItem.trick_kind`: `yoyo_trick`, `cards_trick`) whose take is its count since it was picked
    up. That count goes with the press, so a copy that hears it plays that trick, not its own next.
    Its sounds are a table (`trick_sounds`: the yo-yo's whirr and catch, the deck's riffle, sweep and
    knock), rung where they fall in the trick. The sample is the whole trick, those sounds mixed where
    they ring (`FidgetItem.trick_stream`, `Foley.layered`). A bounce is no use. Every copy flies a
    throw the same (Flight), so each rings `Item.rang` (`ball_bounce`, its take the bounce's number in
    the throw, tuned by `Foley.BOUNCE_TUNES` instead of a random pitch). The host's copy catches it
    for the thrower, or by the mic. The ball's squeeze is not its sound, so REC waits for its bounce.
    Every sound is kept at the pitch the room played it: a second voice (`VOICE_PITCH`, a fifth
    down), a Tour curse, a bell's chord tone (`InstrumentItem.tune_at`, `Item.use_pitch`) reach
    `Sampler.heard` as its `pitch`, and the take is resampled to it before it is written
    (`Foley.resampled`). A guest's pitched click is caught from its hit, which carries the song
    position that pitches it. Not caught: the keytar, and the chips' tricks. The screen is two short
    lines, large: `REC · YOUR NEXT SOUND` over `by the mic, or in your hand`, or `PRESS REC` over the
    last sample's name. The legend lies large on the deck in front of the key (`REC ON`). The cassette
    rack has a lamp under its top (`CassetteRack._lamp`, a wide spot), so a racked sample's label
    reads in the top's shade. Discoverable: the plaque and both help lines (PLAY · LIVE ROOM, the I
    walk), the REC key's hover card, the notice on each press and each catch, the screen, and the
    welcome card's TOGETHER page ("Sample it"), which all name the tricks and the bounce.

    `_test_a_squeeze_after_rec_is_one_sample_on_the_rack` checks:
    - the sampler stands beside the rack with its plaque and REC key;
    - REC off, a squeeze writes nothing, and the key and screen say off;
    - REC by the key is this player's, the room's row, said in words and lit, with a notice;
    - a squeeze in the presser's hand writes one WAV, byte for byte Foley's stream for its take at
      44.1 kHz, the squeak the duck rang, and it opens as a WAV;
    - one sample cassette, an audio clip of the whole file named for it, in the rack's first slot,
      REC off, the screen naming it, the presser told, and it pastes;
    - a second squeeze writes nothing; REC pressed twice is off and catches nothing;
    - the screen's headline and the REC ON legend are large enough to read from where you stand;
    - with a guest's REC, the host's squeeze far from the mic catches nothing and REC stays on;
    - the tambourine struck within reach is caught for the guest's REC, made by whoever struck it,
      onto the next slot;
    - a shaker shaken is caught as its take;
    - the ball's squeeze by the mic is not its sound and REC waits; dropped by somebody else beside
      the mic, its first bounce rings take 1, is caught as Foley's take 1, and later bounces are not;
    - a yo-yo trick is a use with its count for a take, caught as one WAV of the whole trick (its
      whirr and catch, where they ring), and the next trick is only a trick;
    - a card trick (the shuffle) is caught whole, riffle and knock;
    - a handbell rung in Am rings A4 and is kept at A4, longer than Foley's C5 by as much, and its
      cassette is that long;
    - a low-voiced tambourine is kept a fifth down, not at its own pitch;
    - as a guest, the host's row shows; its own press is asked and shown at once, kept against a room
      that crossed it, and the answer is the room's; its own squeeze writes nothing.

    `_test_a_guests_squeeze_is_sampled_on_the_host_with_its_take` checks:
    - the take is cleaned as a hit's is;
    - a squeeze by someone not holding the duck is not caught;
    - hers, take 3, rings take 3 on the host's copy and is written as Foley's take 3, not 2;
    - the cassette is hers, on the rack, and REC is off for the room;
    - her second squeeze writes nothing;
    - her shake is caught as her take, shaken;
    - her fourth yo-yo trick reaches the host's copy, which plays her fourth, and is kept whole as
      Foley's take 4 of it;
    - her bell's click as a use is left for its hit, which is kept at the chord tone her song
      position rang;
    - her REC off is the room's, and a REC ask is a yes or no.

    The probe: at 59.36 the guest asks REC. By 59.42 the room's `sampler` row is the guest. At 59.44
    it takes the duck, and at 59.48 squeezes it with take SAMPLE_TAKE (3). At 59.52 the host has
    heard that take. Its Sampler (as the studio's) has written one WAV equal to Foley's stream for
    it, made a cassette the guest made, and turned REC off, in the room too. By 59.55 the guest has
    the cassette's row, the room naming it, and REC off. The host takes them away at 59.62. The host's
    end moved to 59.6 and the guest's to 59.78. Not run with this slice: the checkpoint runs it.
    shots/spatial26.png is the sampler lit and listening, its screen saying REC · YOUR NEXT SOUND and
    the legend REC ON, readable from where you stand
    (`SHOT_CAM="3.14159,-0.5,1.2,-5.3,1.0,4.75" SHOT_ARGS="--samples 2 --no-hud" tools/shot.sh
    shots/spatial26.png 60 66`). shots/spatial26_rack.png is the two sample cassettes it made on the
    rack's top row under its lamp, `duck squeeze 1` and `tambourine hit 1`, each lettered
    `SAMPLE · 0.20 s` and `SAMPLE · 0.34 s` (`SHOT_CAM="1.5708,-0.2,0.6,-6.98,1.3,4.42"
    SHOT_ARGS="--samples 2 --no-hud" tools/shot.sh shots/spatial26_rack.png 200 206`).

27. [x] **A DJ platter.** The proving idea, #17. `Platter` (core/music/platter.gd, station
    `platter`, on the deck cart beside the tape deck) is a turntable whose label turns with the
    song: a turn a bar. Bare, it is the playhead. Grab it and turn it to scrub: the song position
    follows its angle, sounded by `DAW.scrub(seconds, speed)`. The built-in engine plays short
    windows of the mix at the dragged place. Reaper takes OSC's scrub. Where neither can, it is
    quiet seeks, said on its card. Hold it still to stop: transport_stop while held, playing again
    on let-go if it was playing. A back-spin (a flick backward faster than three turns a second)
    plays the spin-back sound (Foley.spinback, synthesised) and seeks back the bars spun. Put a
    cassette in its slot (holder `platter`) and it scratches that clip for this player alone on
    MONITOR: the clip's render read at the platter's speed and direction (`Varispeed`), the playhead
    untouched, through Godot's mixer at the figure on its tag. A scratch can be sampled by the
    sampler. A guest's turns are seeks asked of the host, at most 15 a second. Its scrub sound is
    its own. The wheel nudges a beat. Touches platter.gd, varispeed.gd (new, core/audio), daw.gd,
    daw_backend.gd, godot_backend.gd, reaper_backend.gd, foley.gd, tape_deck.gd (the cart's room),
    stations.gd. The suite checks: angle to seek; a hold stops and the let-go resumes; a back-spin
    seeks back the bars spun and plays the sound once; a slotted cassette's scratch plays on MONITOR
    and not the mix; a guest's turns are rate-limited; scrub's capability card. The probe checks
    that a guest's spin moves the host's playhead. Both sides at 0 failed. shots/spatial27.png is
    the platter with a cassette on it.

    Built. `Platter` (core/music/platter.gd, station `platter`, models tools/blender/platter.py:
    platter.glb, the plinth, plate, tonearm and slot housing, and platter_disc.glb, the record that
    turns, with a mat, a cream label with a red stripe and sixteen strobe dots) stands on a leaf off
    the far end of the tape deck's cart (`Platter.ON_CART`), away from the seat, a centimetre under
    the shelf and running in beneath its end so the two share no face. The leaf has two posts, a
    foot and two casters of its own, and the cart's footprint grows to take it in
    (`Studio._build_platter_leaf`), so the cart is pushed, and stood clear of, as one piece. The
    station row names the cart (`cart`: `deck_trolley`) instead of a footprint, and
    `Venue.platter_spot` reads where the cart has been wheeled. Its plaque hangs from the leaf's
    front below the plinth, folded. Lettering along the plinth's front says what it is doing (`BAR 4
    · PLAYING`, `HELD · STOPPED · BAR 4`, `SPIN BACK`, `SCRATCH · Kick Verse 1`), never colour alone.
    Its one number is `turns`, bars from the song's start (`bars_at`, `seconds_of`). Bare, it
    follows the song and the label turns clockwise from above, a beat at a time when no motion is
    wanted. The record's face (`Platter.Disc`, a ControlAffordance in the record's plane) is turned
    by going round its middle, however many times round, or by a controller's twist. On the host
    each frame's turn is `DAW.scrub(seconds, speed)` (new verb, a guest's intent checked as two
    finite numbers, speed clamped). `DAWBackend.Capability.SCRUB` and `DAWBackend.scrub` (a quiet
    seek, the stand-in's) are new. The built-in engine seeks and, stopped, opens an 80 ms window
    (`GodotBackend.SCRUB_WINDOW`) in which its players, or the native lanes (`LaneEngine.drive`),
    play the mix from the place dragged to, each move afresh; a hand held still opens none, and
    while playing it is only a seek. Reaper gets OSC's `/scrub` (rotary, the speed over four) and the
    seek. The card says which (`Platter.scrub_words`: the built-in engine plays the song where you
    turn it; Reaper scrubs it; quiet seeks: this DAW cannot scrub; a guest's are seeks, 15 a second
    at most). Taking hold stops the transport (`was_playing`), and let go it plays on. A flick back
    faster than BACKSPIN (3 turns a second, over the last 80 ms) spins on alone at a drag that lands
    it on the bar line about `v²/(2·SPIN_DRAG)` bars back from where it was let go, and plays
    `Foley.spinback` (new: falling partials over a noise band) once; caught mid-spin, it lands
    there and is held. A guest's turns are seeks asked (`_send_seek_if_due`, SEEK_HZ 15, the last
    always sent, play asked after it), never a scrub, and the needle she hears turning is her own
    (`Foley.needle_drag`, a looping crackle, as loud as she turns). The wheel nudges the playhead a
    beat, a quarter fine.
    A cassette clicked into the slot (`Platter.Slot`, the room's holder `platter`, laid at
    `ON_CART * SLOT_POSE` on the cart and laid again when it is pushed, `Studio._hold_the_platter`)
    stands upright with its label to the front, and the platter is a scratch. Its clip is rendered as
    the ear renders it (`EarCue.midi_frames` or `demo_samples` on a worker, or the audio file's
    stretch, `Varispeed.frames_of`; a guest fetches the file, FileSend), and its tag says RENDERING,
    FETCHING, not on this machine, nothing to scratch, or `SCRATCH · MONITOR 76 ms`. `Varispeed`
    (core/audio/varispeed.gd, new) is an AudioStreamGenerator on MONITOR through Godot's mixer, fed
    each frame the clip read in a straight line from where the hand last had it to where it has it,
    a turn a bar of the clip, forwards or back, as loud as it is fast (GAIN_SPEED). Its figure is its
    queue and the card's (`latency_seconds`). The playhead is untouched and nothing reaches the DAW.
    The wheel plays a beat of the clip. A scratch is also its path (`Varispeed.path`, [dt, seconds,
    ...], at most PATH_MOST steps and PATH_SECONDS, 10 s), and `Varispeed.render` is the same arithmetic over it. Let go
    with REC waiting, it is a sample: the host renders the path from its own render of the clip
    (`Platter.render_scratch`) and gives it to `Sampler.heard_stream` (new, `heard` now calls it) as
    `platter_scratch_1.wav` and a sample cassette; a guest's path comes as the room verb `scratch`
    [cassette id, path], checked against what is in the slot, rendered only if REC waits and would
    catch it (`Sampler.catches`) and the path fits (`Varispeed.fits`), so an ask costs the host no
    work otherwise. A guest's platter let go stands where its seek put it until the host's song is
    within a beat of there (or SEEK_WAIT, 1 s), not back at the host's old place. The help card's TOGETHER page says
    "Scratch it"; the tape deck's header says what shares its cart.

    `_test_a_platter_is_the_playhead_scrubbed_by_hand` checks: bar 3 is two turns, the stripe at the
    back, and a quarter bar on is a quarter turn clockwise; the lettering says the bar; taken hold of,
    the song stops; turned half round, it is half a bar on, and a whole turn a bar; held still, it
    stays stopped and says HELD · STOPPED; let go it plays on, nothing spun back; taken while
    stopped, it stays stopped; a flick back faster than BACKSPIN spins back, the sound once, lands
    the bars it spun back on the bar line and plays on; with no motion it lands at once; the wheel is
    a beat, and fine a quarter; the card's quiet seeks, the built-in engine's and Reaper's SCRUB and
    their words, and the guest's. `_test_the_built_in_engine_plays_a_scrub_in_short_windows`: a scrub
    while stopped seeks and opens a window that closes on its own; held still none; playing, a seek;
    never before the start; the stand-in seeks quietly.
    `_test_a_guests_platter_turns_are_rate_limited_seeks`: held, she asks to stop; a second of
    turning asks 10 to 15 seeks, never a scrub; her needle is her own; let go, the last place is sent
    and then play; it stands where she sent it until the host's song is there, then follows it; a
    nudge stands a bar on at once; an ask never answered gives way in SEEK_WAIT. `_test_the_platter_rides_the_deck_cart_clear_in_every_venue`: on the cart with its
    leaf and plaque, a control-room station; the cart clear of the desk, the timeline, the mix
    position and the rest in every venue and variant, on the floor, with room to stand at it; its
    spot is where it stands; the footprint takes in the leaf; the slot is the room's holder, and
    stays under it when the cart is pushed. `_test_a_cassette_on_the_platter_scratches_on_monitor`:
    the slot says what it is for; a cassette clicked in stands there; RENDERING, then `SCRATCH ·
    MONITOR n ms`; the card says ears alone; turned, it is heard on Monitor and nothing on the Mix
    bus, a turn a bar of the clip, and back; the playhead and the DAW untouched; let go, silent; with
    REC, the very scratch is a WAV and a sample cassette; a scratch ask is checked; a guest's
    scratch is sampled from the host's render, and one of a cassette not in the slot is not; with
    REC off an ask writes and renders nothing, and a path past PATH_SECONDS is refused unrendered;
    a slow hand's recorded path is kept to its first PATH_SECONDS, so it always fits; the
    wheel plays a beat of it; taken out, it is the playhead's again. The station tests now stand
    seven stations, I walks to seven, and the cart and its leaf share no face with anything.
    The probe: at 59.6 the guest takes hold of a platter of its own and turns it to PLATTER_TURNS
    (6, bar 7) by 59.68, letting go. Its turns were seeks, within SEEK_HZ a second, the last at bar
    7, and no scrub. At 59.74 the host's playhead is at bar 7 (or just past it, playing on). The
    host's end moved to 59.76 and the guest's to 59.9. Not run with this slice: the checkpoint runs
    it. shots/spatial27.png is the platter with the Kick Verse 1 cassette standing in its slot, its
    tag `SCRATCH · MONITOR 76 ms` and the plinth lettered `SCRATCH · Kick Verse 1`
    (`SHOT_CAM="-0.65,-0.55,0.8,1.53,0.93,0.27" SHOT_ARGS="--platter --no-hud" tools/shot.sh
    shots/spatial27.png 150 156`). shots/spatial27_cart.png is the deck's cart in the room with the
    leaf off its far end, clear of the desk (`SHOT_CAM="-0.35,-0.5,2.6,1.1,0.6,0.1"`, the same).

28. [x] **A tape reel for undo history.** The proving idea, #11. The tape deck's supply reel gets a
    crank on its hub (a ControlAffordance). Turning it back a notch (30 degrees) is one step of
    history back, and forward is one on. Once the crank settles (0.25 s),
    `DAW.undo_to(MixState.undo_depth - notches)`, one jump, not a step a frame. Each notch clicks
    (Foley.reel_click), and the deck's readout shows `12 / 15 · Move 3 BASS` from
    MixState.undo_names (an edit group shows its name). With the song stopped, each settled step
    plays two bars from the playhead and stops, so you hear the song as it was there. Playing, it
    just keeps playing. Turning past either end stops with a dull knock. The wheel and thumbstick
    nudge a step. Ctrl-Z is unchanged. A guest's crank asks undo_to, as the history list does.
    Touches tape_deck.gd, reel_crank.gd (new, hardware/transport), foley.gd. The suite checks: three
    notches back then a settle is one undo_to(depth - 3); turning on settles once; the ends; the
    click count; the preview starts and stops; a guest's crank is an intent. The probe checks the
    guest's crank on the host's history. Both sides at 0 failed. shots/spatial28.png is the crank
    and readout.

    Built. `ReelCrank` (hardware/transport/reel_crank.gd, a ControlAffordance) stands on the supply
    reel's hub in front of its flange (`TapeDeck.crank`, CRANK_Z): a metal boss, an arm and an amber
    handle standing out towards the hand. It is not a child of the reel, which turns with the song, so
    its arm stands at the step it has been turned to, a notch (30 degrees) a step clockwise from
    twelve o'clock (the start). The whole reel's face takes the grab: a mouse or a fingertip goes
    round its middle, however many times round, a controller twists. Anticlockwise, winding tape back
    onto the supply, is back. Each notch clicks (`Foley.reel_click`, a pawl's tick and the hub's
    answer, new), one sound for a frame's notches, counted every one (`clicks`). Nothing is undone
    while it turns: once it has stood still SETTLE (0.25 s), held or let go, it is one
    `DAW.undo_to(depth + notches)`, and back and on again to where it was is nothing; a hand that
    settles while it holds goes on from the settled step, its turn so far not made twice. Turned past
    either end it stops there with `Foley.reel_knock` (new, low and muffled), once each time the end
    is met, and the hand's turn past it is not kept, so turning back comes off it at once. The wheel
    and the thumbstick are a step a notch, gathered into one settle the same way. The deck's readout,
    along its top edge over the reel in the history keys' amber, says `2 / 5 · Kick: volume`: the
    step it stands at, of how many, and that step's name from MixState.undo_names (`step_name`, an
    edit group's own name, the start for 0, cut at NAME_MOST), and it says where the crank is turned
    to before it settles. With the song stopped, a settled step plays PREVIEW_BARS (2) bars from the
    playhead (`transport_play`), counted from after any count-in so the two bars are the song's
    and not the click, then stops and seeks back to where it began; a step settled while
    that plays starts it again from the same place without a stop; stopped by somebody else it gives
    up and puts nothing back. With the song playing a settle is the jump alone. A guest's crank asks
    undo_to through DAW, as the history rail does, and stands where it asked until the host's history
    comes back there (ASK_WAIT, 1 s, at most). Where the DAW does not say its depth (Reaper with no
    bridge), a settle is that many undos or redos and the readout says only how far it is turned
    (`HISTORY · 2 BACK`). UNDO, REDO and Ctrl-Z are unchanged, and the arm follows the history
    however it moved. Its hover card is `EDIT  HISTORY REEL` with the readout and how to turn it; the
    welcome card's Undo line names the crank. The deck's header says what its supply reel is now.

    `_test_a_tape_reel_cranks_back_through_the_history_in_one_jump`: the crank on the supply reel's
    hub; the readout `5 / 5 · ...`; three notches back are three clicks, nothing undone, the crank
    and readout at 2 and the arm three notches round; settled, one undo_to(2) and only once; a hand
    going round clockwise two notches, let go, settles once to 4; back and on again settles nothing;
    past the end, one knock, none more held there, another when met again, settled at 5; a hand past
    the end knocks and stands there, and a notch back is a notch off; back past the start stands at 0
    with a knock and a click a step; the readout names the start; two wheel notches are one
    undo_to(2); Ctrl-Z still undoes and the arm follows; a hand turned on three, held still, settles
    at 4 while held, a jitter moves it nowhere, a notch on is 5 with no knock, and let go it settles
    at 5 once. `_test_a_settled_step_plays_two_bars_of_the_song_there`:
    stopped, a settle plays; half way it plays; two bars on it stops and seeks back to bar 3; a
    second settle mid-way seeks back and plays on, not stopped between, and stops two bars after;
    stopped by a hand, it plays and seeks no more; playing, a settle is the jump alone; with no depth
    said, the readout is `HISTORY · 2 BACK` and a settle two undos; with a 2-bar count-in before
    playback it counts in to bar 3, still plays after the click, and stops two bars of the song on. `_test_a_guests_crank_asks_undo_to_of_the_host`:
    nothing asked while turning; settled, one undo_to(3) intent and, stopped, a play after it; she
    stands at 3 (`3 / 8 · c`) until the host's history is there; an unanswered ask gives way in
    ASK_WAIT; her two bars end with a stop and a seek. `_test_the_reel_click_and_knock_are_two_sounds`.
    The probe: at 59.76 the host notes its depth; at 59.78 the guest turns a crank of its own back
    CRANK_NOTCHES (2), not played back, and by 60.08 it asked one undo_to(depth - 2) (two undos where
    the depth is unsaid); at 60.12 the host's history is two back and the guest's copy and crank say
    so; the host puts it back at 60.14. The host's end moved to 60.16 and the guest's to 60.3. Not run
    with this slice: the checkpoint runs it. shots/spatial28.png is the crank turned back three of
    five steps with the readout `2 / 5 · Kick: volume` (`SHOT_CAM="-0.45,-0.4,0.36,1.17,1.05,-0.17"
    SHOT_ARGS="--crank 3 --no-hud" tools/shot.sh shots/spatial28.png 30 36`; `--crank N` in
    tools/screenshot.gd makes five steps and turns the deck's crank back N, held unsettled).

29. [x] **Sections rearranged, as one edit.** #9's verb. `DAW.arrange_sections(order)` takes the
    regions in song order (MixState.regions, sorted) and a new order of them. Everything from the
    first region's start to the last's end is laid end to end in the new order: items (split at the
    regions' edges, DAWBackend.item_slice), markers (so a section's brackets and notes move with it,
    and the harmony with them), the regions themselves, automation points and MIDI controls. A gap
    between regions is a span of its own and keeps its place in the order given. What is after the
    last region is unchanged. It is refused, and says so, when a tempo or meter change falls inside
    the span anywhere but at a region's start (one at a start moves with its region), when regions
    overlap, or when an item it would move is locked. It is one undo step, under Capability ARRANGE.
    OfflineBackend builds it in DAWBackend._locally_arrange. The bridge's ArrangeSections uses
    SplitMediaItem, SetMediaItemPosition, SetProjectMarker4 and the envelopes' points inside one
    Undo block. Touches daw.gd, daw_backend.gd, offline_backend.gd, reaper_backend.gd,
    dawlings_bridge.lua. The suite checks: ABC to CAB moves items, markers with brackets, regions,
    automation and controls; an item across an edge is split; the gap rule; each refusal; undo
    restores all of it; FlatHost shows the result; the bridge decodes ArrangeSections; a guest's
    intent carries the order. The probe checks a guest's rearrangement on the host's regions. Both
    sides at 0 failed.

    Built. `DAW.arrange_sections(order)` is in COMMANDS under the new Capability ARRANGE. `order`
    is MixState.regions (in song order) by their indices there, so ABC to CAB is [2, 0, 1]. It
    answers "" when done or asked, and otherwise why not, from `DAW.arrange_refusal`. The reasons,
    in order: no ARRANGE (Reaper without the bridge), fewer than two regions, not an order of them
    all (each once), two that overlap, the order they are in, the clock, a frozen track with
    something it would move, and a locked item it would cut or move. The clock reasons come from
    `DAWBackend.arrange_clock_refusal`: a tempo or signature change inside a section anywhere but
    at a piece's start, or a tempo ramp through the sections. A refusal names the section, as the
    region is called, or "the gap after" one. Its step is "arrange sections".

    The plan is DAWBackend's and pure. `arrange_pieces` makes each region, and each gap between
    two, a piece [from, end, to] in the new order. The gap keeps its slot among the regions, so it
    stays after the first section, whichever that now is, and moves in seconds when the sections
    before it are longer or shorter. `arrange_cuts` is each edge between two pieces side by side
    (or a piece and the song beyond them) that move by different amounts. Only there is anything
    cut, so a section that keeps its place is left whole. Laid out from those:
    - items, split at a cut they cross by `item_slice` (on their own lane, notes and controls
      counted from each part's start), each part with its piece (`arranged_items`);
    - comps' spans, the same (`arranged_spans`);
    - markers, by the piece each is on, so the harmony and notes inside a section go with it
      (`arranged_markers`). A section with no bracket at its start played the one before it, which
      may not be before it now, so `arranged_brackets` writes the harmony it had at its new start:
      onto the marker there ("Verse 2 [A minor]"), or as a marker that is only brackets, a
      progression turned round to start at the bar it had reached. The song after the last region
      keeps its harmony the same way when anything is there. A section from before any bracket
      takes what is before it now: no bracket says "no key";
    - the regions (`arranged_regions`);
    - every lane of automation, the master's too (`arranged_lane`). A section's own points move
      with it. Where a section now meets one it did not, it gets a point at its start with its
      value there, and a point a millisecond (ARRANGE_EDGE) before an edge it ramps into, so every
      moment plays as it did. A point at the last region's end, and one at 0 when nothing was
      before, keep the song outside as it was.

    A tempo or signature change at a piece's start goes with the piece (`arranged_clock`, in
    beats; each piece keeps its beats, so the song after keeps its seconds and its beats). A
    change back at the end that the new last piece already holds is dropped.

    `DAWBackend._locally_arrange` writes it all through the replicating addresses. OfflineBackend
    (and so the built-in engine) keeps `_arrangement()` from before and after as one step, which
    `_put_arrangement` restores. ReaperBackend shows it on the cache and sends one
    `ArrangeSections` (`arrange_request`: the pieces, then the tempo map in seconds and the
    signatures, each only when it moved, then those brackets). In one Undo block, the bridge refuses the lot if a
    locked item is in the way, on any track. Otherwise it reads everything first: SplitMediaItem
    at each cut, where each part, marker and region (by its number) and envelope point goes, then
    SetTempoMap and SetTimeSignatures quietly inside the block. Then it puts each where it goes in
    seconds (SetMediaItemPosition, SetProjectMarker4, InsertEnvelopePoint after
    DeleteEnvelopePointRange), so an item whose timebase is beats lands with the rest. A bracket
    renames the marker where it lands, or is a new one (AddProjectMarker2). The master's "Tempo
    map" envelope is left out of the envelopes: SetTempoMap and SetTimeSignatures set the clock, and
    putting its old points back would undo the map and drop the signatures on it. A guest's is
    an intent carrying the order. `DAW.apply_intent` refuses a malformed one or one the host's own
    regions refuse. `Session._arrange_for` makes it as the guest's step, tells the room ("Grace
    rearranged the sections: Verse 2 · Verse 1 · Chorus 1."), and tells the guest a refusal. A
    guest sees a refusal its own cache can find at once. No surface calls it yet: the blocks on the
    bricks table, dragged or moved with [ and ], are slice 30.

    `_test_sections_rearranged_move_everything_with_them` checks, on the demo's Verse 1, Chorus 1
    and Verse 2 as regions:
    - CAB is one step called for it, and the regions are in the new order end to end;
    - every section's items went with it, the Rhodes' notes and controls as they were;
    - the section markers moved, and the harmony marker inside Chorus 1 with it, still read;
    - Verse 2 and Verse 1, whose harmony came from brackets before them, keep it on their start
      markers, and every bar plays the key and chord it did;
    - a take across the Chorus-Verse 2 edge is cut there, each half with its own note and
      mod-wheel move;
    - the Snare's volume ramp and the master's pan play every moment of every section as they did,
      and before and after the sections as before;
    - the 2D view (FlatHost) draws the new order;
    - one undo puts every item, marker, region and lane back, and a redo does it again.

    `_test_a_gap_keeps_its_place_and_the_clock_goes_with_its_section` checks:
    - CBA with a gap after A puts the longer C first and the gap second;
    - B's take goes with B, whole;
    - C's 90 bpm and 3/4 at its start go with it, the change back at the end with them;
    - the song after the sections keeps its seconds and beats, and undo puts the map back;
    - a section nobody moves has no cut at its edges.

    `_test_a_rearrangement_is_refused_and_says_why` checks each refusal, with nothing changed. On
    Reaper with the bridge, BA is one ArrangeSections of the pieces in the new order, no clock and
    B's bracket from A, shown on the cache at once. `_test_a_guests_rearrangement_is_an_intent_carrying_the_order`
    checks:
    - a guest's order is the intent, and nothing moves on the guest;
    - a refusal is said at once and nothing is asked;
    - malformed intents are refused on the host;
    - a refused one is told to the guest;
    - the host makes it as one step and tells the room the new order.

    `_test_a_sections_harmony_from_before_it_goes_with_it` checks that a section from the second
    bar of `C - F G` starts the song on `C F G C`, that the marker after the sections keeps its bar
    of it, that every bar plays the chord it did, and that a section with its own bracket needs
    none.

    tests/bridge_decode_test.lua decodes ArrangeSections and runs it on a stand-in Reaper:
    - an item across the edge is split, each part with its section;
    - the regions and the marker move by their numbers;
    - the envelope plays each section as it did;
    - the tempo map is set inside the same block, and the master's "Tempo map" envelope is left
      to it;
    - a bracket renames the marker where it lands, or is a new marker;
    - a locked item refuses everything.

    The probe: at 60.16 the host makes three two-bar regions from ARRANGE_BAR (460), past
    everything else the probe writes, with a marker in the second and a take in the third. At
    60.24 the guest asks C A B of its copy, the host's other regions where they are. By 60.34 the
    host has C where A was with its take, the marker gone with B, as one step named for it (built-in
    engine), and the guest's copy and the room's notice say so. At 60.36 the host takes all of it
    back with undo_to, or a step at a time where its DAW does not say its depth. The host's end
    moved to 60.4 and the guest's to 60.54. Not run in this slice (checkpoints run it); the probe
    script loads.

30. [x] **Song sections as blocks on a table.** The proving idea, #9. `SectionBlocks`
    (core/music/section_blocks.gd, station `sections`, zone `bricks`): one block a region in song
    order along the bricks table's far long edge, its length the region's bars, lettered with its
    name and bars. The table is laid out in three bands, each a zone-mounted station checked by the
    clearance loop: the blocks along the far edge, the wheel at the near-left end, and the ledge
    (slice 31) along the near edge. The playing block has a mark moving along it and is lit
    brighter. Lift a block and put it elsewhere in the row, and the others make room. Nothing
    changes until it is let go, and then `DAW.arrange_sections` is called once: one undo step per
    rearrangement, shown in the 2D view. At a desk: drag a block along the row, or [ and ] move the
    hovered one. A song with no regions shows MAKE SECTIONS FROM MARKERS: a region per marker's span
    (notes skipped), add_region each, inside one edit, so one undo step. Touches section_blocks.gd,
    venue.gd (the table's bands), studio.gd, stations.gd. The suite checks: dragging block 3 to the
    front calls arrange once with [2, 0, 1] (indices into MixState.regions); no call while held; [ and ]; MAKE SECTIONS makes a
    region a marker and is one undo step; every venue's table holds the wheel, the blocks and the
    ledge clear of each other (the clearance loop); the mark follows the playhead (stepping at
    motion 0). shots/spatial30.png is the table with blocks and the wheel.

    Built. `SectionBlocks` (core/music/section_blocks.gd) is station `sections`, SECTION BLOCKS on
    the LIVE ROOM page after the wheel, mounted in zone `bricks` at `Venue.sections_spot`. The
    table's bands are `Venue.TABLE_BANDS`, rectangles in the table's own frame
    (`Venue.bricks_table`: x across it toward the far long edge, z along it away from the control
    room): `wheel` at the control room's end, where the wheel already stood, `sections` along the far
    long edge past it, and `ledge` along the near long edge beside it, for slice 31. Seen from the
    blocks' seat, the wheel is at the near left end. `Venue.band_spot(id)` stands a band's station at
    its middle on the top, facing the near edge, so its +X runs along the table, left to right for
    the player there. The clearance loop (`_check_zone_station`) holds two banded stations apart by
    their bands, BAND_GAP (4 cm) or more, rather than by their `air`, which is for the floor round
    them. The blocks' `air` is 0.3 m.

    The row is ROW (1.3 m) long in a wooden tray, a block a region in song order. Each block is a
    region's bars long at up to PER_BAR_MOST (5 cm) a bar, scaled so the song fills the row. It is
    a wedge 12 cm deep, its top sloped toward the player, lettered on the slope with the name, fitted
    to the block, and its bars ("bars 9–24"). The plaque stands behind the row on two rods, its top
    PLAQUE_TOP (0.4 m) up, so opened its foot is still above the table. Each block is its own
    control (`SectionBlocks.Block`) with its frame's +Z up, so a held ray or a pinch moves it in the
    table's plane. Its hover card says its bars, its length and its place ("2 of 6"), and while held
    where it would go ("to place 1: Verse 2 · Verse 1 · Chorus 1"). Held, it stands LIFT (5 cm) off
    the row where the hand has it, and the others slide to make room (`order_with`, the place
    nearest), easing at EASE times motion_scale and jumping at motion 0. Nothing is written while it
    is held. Let go, `let_go` asks for that order once, unless it is the order already or the block
    was let go more than OFF_ROW (0.3 m) from the row. [ and ] (Studio._unhandled_input,
    `step_under` on the hovered or held block, with the cursor's point), the mouse wheel and the
    thumbstick (its nudge, `Block.nudge` keeping its pointer's point) move a block a place, one
    call each, from the order the row shows. Again with the pointer within STILL (2.5 cm) of where
    it was, the block the last step moved goes on along the row, not the neighbour that slid in
    under the pointer, so ] ] walks Verse 1 two places at two undo steps rather than swapping it
    back; that block is forgotten once the pointer moves on, or no block is under a pointer for
    LEAVE (0.3 s). On a held block they move it a place in the held order (`Block.slide_to`, the
    hand's hold going on from there) and ask nothing: let go writes it once. At an end of the row it
    says it is first or last and asks nothing. A refusal (DAW.arrange_refusal) is said as a notice,
    and the row stays as the song is. A host is told the new order. A guest is told it was asked,
    and their row shows the asked order until the host's regions arrive, or PENDING (3 s) passes.
    One is asked at a time, since the host applies an order to the sections it has then: a move
    made while one is asked is shown (`_queued`) and asked, in the new regions' indices, when the
    answer's regions arrive (their names in the asked order). The row is rebuilt whenever the
    regions, the tempo or the meter change, and not while a block is held, unless the regions
    change under it (the host's, an undo): then the hold ends, the block goes back and that is said,
    and its let-go asks nothing.

    The block the playhead is in is painted lighter (paint, not a glow, which bloomed over its
    lettering) and has a glowing mark across its top at the playhead's bar. At motion 0 the mark
    steps a bar at a time. With no regions the row is one key, MAKE SECTIONS FROM MARKERS, whose
    card names the sections it would make. `spans` makes one per marker that names a section, from
    it to the next, the last to the song's end at a bar (the last item's end, else the project's
    length). A marker that is only brackets sets a key and names no section, and a sticky note
    (`Harmony.NOTE_PREFIX`, "NOTE ", added here with `Harmony.is_note` for slice 35) is not a
    section. Both are skipped. `make_sections` adds them inside one open_edit/close_edit, so it is
    one undo step, and a guest's is that edit's intents. With no section marker it says so and
    makes nothing. Studio stands it with each venue (`_stand_the_sections`, `Studio.sections`, null
    in AR and in the Rig Roulette room, which have no bricks table). tools/screenshot.gd's
    `--sections N` makes the demo's sections, puts the playhead in the second, and holds block N at
    the front of the row for N above 0.

    `_test_dragging_a_section_block_is_one_rearrangement` checks:
    - a block a region in song order, as long as its bars, lettered with them;
    - block 3 dragged to the front: the others make room, its card says where, and nothing is asked
      or changed while held;
    - let go: arrange is called once with [2, 0, 1], as one undo step, and FlatHost shows it;
    - the row is rebuilt in the new order;
    - let go off the row, or in its own place, nothing is asked;
    - undo puts the song and the row back.

    `_test_brackets_move_the_hovered_section_block` checks, through the studio's own keys and
    blocks, that ] and [ move the hovered block a place (one step each), that [ on the first one
    says so and asks nothing, that the wheel is the same nudge, that a locked item's refusal is said
    and changes nothing, and that the plaque and the PLAY line say how. `_test_make_sections_from_markers_is_one_step`
    checks the six demo markers made six regions by name, a note and a key marker skipped, each to
    the next marker and the last to bar 89, as one undo step, MAKE gone and back with undo, and
    nothing made from no section markers. `_test_the_section_mark_follows_the_playhead` checks the
    lit, marked block and the mark at 4.5 bars of 16, moving with the playhead, stepping a bar at
    motion 0, and going on into the next section. `_test_the_bricks_table_holds_its_three_bands_clear`
    checks the three bands clear of each other on the top and, in every venue and variant, the
    wheel's board, strut and ledge inside its band, the blocks' tray, rods and plaque inside theirs,
    the plaque's foot above the table when opened, and the blocks facing the near edge. The
    clearance loop, I's walk, the help card, the station board and the go-to framing tests take the
    new station in.

    Shots: shots/spatial30.png (the table from above the near side: the wheel at the near left end,
    the six demo sections along the far edge, Verse 1 lit with its mark, the near band empty for
    the ledge) and shots/spatial30_held.png (Chorus 1 held at the front of the row, the others moved
    along for it).

31. [x] **Chord bricks, fed by the wheel.** The proving ideas, #16 and #29's feeding. `ChordBrick`
    (core/items/chord_brick_item.gd) is a made item (`brick3`, data {chord}) lettered with its chord
    and numeral (Harmony.numeral). Its length (1, 2 or 4 bars) is its nudge and a room row (`bricks`
    {id: bars}), so a nudge never resends data. The fifths wheel feeds them. A tile pulled up out of
    its strip with a hand, or dragged off the wheel with the mouse (a click still plays it), becomes
    a brick of its chord in the hand. The wheel's MAKE BRICKS key makes the whole strip as bricks
    into the ledge. The ledge is holder `ledge`: 16 slots along the table's near edge, and the
    slots' order is the progression. A brick let go near the ledge goes into the first free slot
    after the bricks there. Pressed into a track (a lane, a strip or a stage voice, as a cassette is
    pasted), the ledge's row (when the brick came from the ledge) or the single brick writes block
    chords voiced at 60 (Harmony.voiced, four notes), one chord per brick for its bars, from the bar
    under the press (a lane) or the playhead's bar, as one insert_midi_take named `chords`. Pressed
    into a section block, it writes the row's harmony into that section's marker by the wheel's SET
    path (Harmony.written, edit_marker, or a guest's `harmony` ask), so the harp, the bells and the
    fingertips follow that section. Touches chord_brick_item.gd, fifths_wheel.gd, section_blocks.gd,
    item_room.gd (the ledge holder), session.gd (`bricks` row), studio.gd, stations.gd,
    tools/blender/chord_brick.py. The suite checks: the wheel's strip to bricks in the ledge with
    its chords; the ledge's order and lengths; a nudge changes the row and sends no made data; a
    press on a lane writes the voiced notes at the bar; a press on a section block writes the
    bracket at that section's marker and the harp follows; undo; a guest's bricks are minted on the
    host. The probe checks a guest's ledge row pressed onto a host section block. Both sides at 0
    failed. shots/spatial31.png is a progression on the ledge.

    Built. `ChordBrick` (core/items/chord_brick_item.gd) is made kind `brick` (`brick1`, ...). Its
    data is {chord, key}, packed by the host from the words of the ask alone (`data_from`: a key and
    a chord that read together by Harmony.parse), so its numeral is its key's (`Harmony.numeral`).
    The made "from" strings are "chord:<key>:<chord>" (into the maker's hand) and
    "ledge:<key>:<chord>" (onto the ledge). It is a 6 x 3.5 x 4.5 cm painted block
    (tools/blender/chord_brick.py, assets/models/chord_brick.glb), lettered on both long faces with
    its chord and, under it, its numeral and length ("VI · 2 BARS"), dark ink with a thin halo of
    the paint, so it reads on a face in shade. A stud on its top for each bar says the length again
    without letters. Its length (LENGTHS 1, 2, 4) is its nudge: the mouse wheel over it at a desk,
    the thumbstick in a headset, and, since a bare hand has no stick, the brick turned in the hand
    that holds it (`follow_turn`, Interactor.twist): a sixth of a turn (TURN_STEP) clockwise is a
    step longer and back the other way shorter, a turn on past 1 or 4 bars not counted, as a key at
    its stop. It is the room's row `bricks` {id: bars} (Session.ROOM_VERBS, a
    guest's ask, shown at once and kept until answered, honoured only for whoever may hold it), and
    the made row's bytes never change. The layout keeps it as a fifth column of the made row
    (LayoutProfile, a row of 4 or 5).

    The wheel feeds them. Each strip tile is its own control (`FifthsWheel.StripTile`, "Tile1" to
    "Tile8"): a click plays its chord. Drawn PULL (8 cm) out of the board's face by a hand, or
    dragged PULL_EDGE (4 cm) past the board's edge with the mouse, it emits `brick_pulled` once, and
    the studio puts a brick of that chord in that hand. The strip keeps its tiles, since a brick is a
    copy. MAKE BRICKS (a WheelButton beside the strip, "MakeBricks") emits `bricks_made` with the
    whole strip, and the studio makes a brick of each at the end of the ledge's row. Empty, it says
    so. The host mints its own at once. A guest asks `make` for each, and a pulled one holds a blank
    look-alike ("MakingBrick") until the host answers, as a pulled cassette does.

    The ledge (`ChordLedge`, core/music/chord_ledge.gd, assets/models/chord_ledge.glb) is station
    `ledge`, CHORD LEDGE on the LIVE ROOM page after SECTION BLOCKS. It is mounted in the bricks
    table's `ledge` band (`Venue.ledge_spot`, `band_spot`), facing the near edge, and seated
    close (`seat` 0.85 m, so CLEAR and the BIN at its two ends are both in a desk's view). It is a
    rail of sixteen felt slots, numbered on the lip's face in front of them, ItemRoom holder `ledge`,
    whose order is the progression (`ChordBrick.ledge_row`). Behind it is a tray where a brick with
    nowhere else to be lies (`tray_spot`, the studio's `_made_home`). At the right end is a BIN
    (holder `ledge_bin`), and at the left a CLEAR key that bins the whole row. Its plaque hangs
    under the table's near edge, folded. ItemRoom gained three rules for it, kept in tables:
    - `IN_ORDER` holders (`ledge`): a brick let go near the ledge goes into the first free slot
      after the bricks there (`next_in_order`), unless it is let go within SLOT_EXACT (3 cm) of a
      free slot, which is how a row is put in another order, or it is a brick let go by, or aimed
      back at, the free slot it was taken from (`from_ledge`), which it goes back into, so one taken
      out to be turned to another length keeps its place;
    - `BINS` (`bin`, `ledge_bin`);
    - `HOLDS`: the rack and the platter take cassettes, the ledge bricks, and anything else is
      refused and says so (`slot_refusal`, its kind half `kind_refusal`). Aimed along the ledge
      (`free_slot_along`), a cassette is not offered it, and goes down where it is aimed.

    At a desk a click on the rail with a brick in the hand stands it on the free slot under the click,
    or at the row's end. A brick taken from the ledge remembers its slot (`from_ledge`), and its row
    is the ledge's with it in its place (`row_of`); a brick from anywhere else is a row of one. Its
    card says its numeral, length and place ("VI of A minor · 1 bar · on the ledge, 2 of 4: Am F C
    G"), and the rail's card says the row ("Am F C G · 4 bricks, 4 bars").

    A brick pastes as a cassette does. `ControlAffordance.paste_spot_for(item, at, fine)` (its
    default `paste_spot`) lets a control take one kind of item and not another, and
    `Item.paste_text(spot)` lets the item word the card ("click writes the ledge's Am F C G (5
    bars) onto Bass from bar 20"). The Interactor's press and push go through them, and
    `ItemRoom.paste` sends the press to `Studio.press_brick`. Into a track (a lane: the bar under the
    press; a strip or a stage voice: the playhead's bar), `ChordBrick.notes_of` voices each brick's
    chord at CENTRE 60 in VOICES 4 notes (Harmony.voiced) for its bars, one after another, as one
    `DAW.insert_midi_take` named `chords`: one undo step, and a guest's is that take's intent. The
    refusals (`write_refusal`) are no MIDI takes, no such track, a frozen track and a microphone's.
    A `SectionBlocks.Block` takes a brick at its region's start (track ChordBrick.SECTION) and
    nothing else. The row's harmony (`inside_of`, "A minor: Am F - C G", a "-" a held bar) goes to
    that section's bar (`section_ask`) by the wheel's SET, `FifthsWheel.write`
    (Harmony.written onto the marker there, one edit_marker, one undo step), or a guest's
    `harmony` ask. So the harp, the bells and the fingertips follow it there and nowhere before.
    The brick stays in the hand after a press.

    `_test_the_wheels_strip_is_bricks_on_the_ledge` checks:
    - MAKE BRICKS stands Am F C G on slots 1 to 4 as brick1 to brick4, each a made brick with
      {chord, key} and no length, lettered "F" / "VI · 1 BAR" with one stud;
    - the cards; the strip kept;
    - a nudge to 2, 4 and back to 2, the studs following, each said once, the room's row having it
      and the made bytes unchanged; the row's harmony "A minor: Am F - C G", 5 bars;
    - a tile click plays and makes nothing; dragged past the board's edge a brick is in the
      mouse's hand, and a hand drawn 10 cm out of the board (not 5) pulls one;
    - let go 5 cm over slot 11 a brick goes to slot 5, the row's end, and right on free slot 10 into
      it; a cassette is refused by the ledge and a brick by the rack;
    - CLEAR bins the row, and ids are never given twice.

    `_test_a_pressed_brick_writes_its_rows_chords` checks:
    - a lane press at bar 12.6 writes one take `chords` from bar 12, 5 bars, Am F C G voiced
      [57 60 64 69] [65 69 72 77] [60 64 67 72] [55 59 62 67], F held two bars, one undo step;
    - a strip's card and press from the playhead's bar 20;
    - a brick not from the ledge writes itself alone; a frozen track refuses it and says so;
    - a section block takes only a brick; its card; the press writes "Verse 2 [A minor: Am F - C
      G]" as one undo step, the harp tuned to F in its third bar, where the Intro's C was, and
      nothing changed before the section; undo gives the name back.

    `_test_a_bare_hand_turns_a_brick_and_the_desk_clicks_the_ledge` checks:
    - the ledge's and the brick's hands lines name turning it; a bare hand (XRInteractor) has no
      stick; F taken from slot 2 into it says to turn it, and turned the short way at 1 bar
      nothing, then back past a sixth of a turn 2 bars, on round 4 and no further, and a sixth back
      from that stop 2, each said once, the room's row having it and the made bytes unchanged; a
      mouse cannot turn one;
    - aimed back at its own free slot it goes back in its place, and at another to the row's end;
    - a cassette aimed along the ledge is not offered it and goes down, nothing refused;
    - the mouse's click on the rail over free slot 10 stands G there, over a taken slot at the
      row's end, with nothing in the hand nothing; the rail's card the row; a click on the BIN with
      a brick bins it for good.
    `_test_going_to_a_station_holds_its_controls_in_view` also holds both ends of the ledge, CLEAR
    and the BIN, in a desk's view from its seat in every venue.

    `_test_a_guests_bricks_are_minted_on_the_host` checks the host's side and then the guest's.
    - The host mints a guest's ledge bricks onto its ledge in order, made by them (the next after
      the row, not into a gap). A pulled one goes into their glove by the holds. Words that do not
      read make nothing. The `bricks` ask is honoured, and refused when the brick is in another's
      glove or the length is not one. The room names the bricks and never their chords. A guest's
      section press is written at its bar.
    - The guest's MAKE BRICKS is `make` asks, and a pull is an ask with a blank brick in the hand.
      The host's answer stands them on the ledge and the blank goes. A nudge is a `bricks`
      prediction, kept across a stale room. A section press is the `harmony` ask with the section's
      bar. A lane press is the take's intent with its notes, and the guest writes nothing.

    The probe (tools/probe/session_probe.gd, 60.38 to 60.58) has the host lay out "Probe D" at
    BRICK_BAR. The guest's MAKE BRICKS of Am F C is minted onto the host's ledge, and its nudge
    makes F 2 bars in the host's row. Its press of its own ledge row onto the host's section block
    asks [480, "A minor: Am F - C"]. Both halves then find "Probe D [A minor: Am F - C]" and the
    third bar in F. The probe's ending moved to 60.62 and 60.74 (host) and 60.76 (guest).
    tools/screenshot.gd's `--bricks N` makes the strip N chords of the key and presses MAKE BRICKS,
    two of them nudged to 2 bars.

    Shots:
    - shots/spatial31.png: Am F C G Dm Em on the ledge, F and Em two studs, from just above the
      near edge. Made with `SHOT_CAM="-1.35,-0.5,0.5,4.57,0.94,4.80" SHOT_ARGS="--no-hud --bricks 6"
      tools/shot.sh shots/spatial31.png 200 206`.
    - shots/spatial31_station.png: the same row from the ledge's own station seat, with CLEAR, the
      rail, the slots' numbers, the BIN and its hanging plaque. Made with `SHOT_ARGS="--no-hud
      --bricks 6" tools/shot.sh shots/spatial31_station.png 500 506` (late enough that the walk
      there has ended).

32. [x] **Chord shapes on one hand.** The proving idea, #28. `ChordHand` (core/music/chord_hand.gd,
    one for this player). The chord hand (the left, flipped by Ergonomics.handedness) is held up
    with its palm toward the room, not the head, and its fingers pointing up (pitch over 0.6 of
    TILT_MOST), which is what tells degree I from a point. The fingers held up (curl under
    HandPose.OPEN_CURL, the thumb as the fifth) count the degree: one is I, two ii, three iii, four
    IV, five V. The same with the palm turned up gives vi (one) and vii° (two). An open flat hand,
    or the hand lowered below the chest, is no shape: the song's own chord. A fist is never used,
    since two fists are the way out. Each degree is the key's chord there (Harmony.diatonic at
    Harmony.at's key). A shape counts once held 0.12 s, so passing through one does not flicker.
    While a shape is held, it is this player's chord for everything they play. The harp's strings
    retune for them, and only for them: they see the strings, their letters and the crown in the
    shape's chord. So do their fingertips, the wheel's sound, and bells they hold
    (InstrumentItem.note_at asks the holder's ChordHand). A note already ringing keeps its pitch.
    Others hear the notes played, which carry their pitches. Controller, as decided: a click of the
    chord hand's stick turns the chord stick on and off; while on, the stick toward one of seven
    directions (up is I, then clockwise) picks and latches a degree, stick nudges are off, and the
    glove says CHORDS. Desktop: the chord layer as decided (C, 1 to 7 in any catcher, Shift for the
    seventh, 0 for the song's), with the harp strummed by the mouse and the fingertips on J K L ;. A
    left glove shows the fingers held up and `IV · F` over it. Touches chord_hand.gd, hand_pose.gd
    (`extended`), key_catcher.gd (`chord_keys`, `click_releases` waiting), xr_interactor.gd (the
    stick's mode), chord_harp.gd, fingertip_notes.gd, handbell_item.gd, fifths_wheel.gd, glove.gd,
    bootstrap.gd (the HUD's CHORDS field), studio.gd (C), stations.gd. The suite checks: posed hands
    of one to five fingers up and palm-up one and two read their degrees; a level index (a point)
    reads none; facing the head reads none; a fist and an open hand read none, and two fists still
    escape; the hold time; the harp retunes for the player and back on an open hand; fingertips play
    the shape's chord; C then 4 gives IV in A minor (Dm), with the fingertips' catcher focused and J
    still playing; a click on the harp while the layer is on strums and keeps the layer; the stick's
    directions latch through a spring to centre, and the stick nudges nothing meanwhile; a bell rung
    under a shape rings the shape's tone. No new wire. shots/spatial32.png is the desktop's chord
    glove over the harp.

    Built. `ChordHand` (core/music/chord_hand.gd) is one node the studio makes (`Studio.chord_hand`,
    `_lend_chord_hand`), its static `mine` the one `ChordHand.at(seconds)` reads: the song's
    Harmony.at with the held degree's chord in its place (`with_chord`, a copy, so Harmony.NONE is
    never written), or the song's own with none. A degree is `chord_for(key, d, seventh)`, the
    scale's own triad on it (C Dm Em F G Am Bdim in C major, Dm on IV in A minor), or its seventh
    chord (maj7, 7, m7, m7b5, dim7 by its intervals), at the key there at that moment, so a latched
    degree follows the song into a new key; `numeral_of` names it (Harmony.numeral, `7` added). A bare
    hand is read by `shape_of(joints, side, eyes)`, pure over HandPose: the palm more than
    CHEST_BELOW (0.45 m) under the eyes, or facing them, is nothing; the digits held out are
    `HandPose.extended` (each curled under OPEN_CURL, a mask of the fingers' bits and the new THUMB
    bit), and the four fingers count I to IV, with the thumb out too V (a thumb out beside fewer
    fingers is not counted, as a relaxed one is out); palm up, one finger is vi and two vii°; and
    otherwise only with the fingers up, tilt pitch over UP_PITCH (0.6). A fist and a flat open hand
    read nothing, so two fists still escape. A hand carrying or holding something reads nothing.
    `settle` counts a reading once it has held HOLD (0.12 s, the frame it was seen in counting),
    both ways, so a shape passed through never sounds and none between two shapes does not drop to
    the song's chord. In a headset the chord hand is the rig's left, or right for a left-handed
    player; tracked, its shape is read every physics frame. A controller there runs
    `stick_step(click, stick)`: the stick's click (XRInteractor.stick_clicked, `primary_click`)
    turns `stick_on` on and off, off being the song's chord; while on, a push past STICK_PAST (0.6)
    picks `stick_degree` (up I, a seventh of a turn each clockwise) and latches it through the
    spring back, and XRInteractor.chord_stick makes `flick` nudge nothing; a stick still out as the
    mode goes off waits to come back before it nudges again. The words over the chord hand (a
    Label3D riding above the palm or the controller) say `IV · F`, and `CHORDS` over them while the
    stick picks. On a desktop C is `Studio.toggle_chords` (Ctrl-C left alone), `set_layer`: with no
    catcher focused it gives the fingertips' keys the keyboard (and takes them back when it goes off,
    but leaves keys it did not give), and sets `KeyCatcher.chord_keys`, a static Callable every
    catcher asks before its own layout while it is valid: 1 to 7 pick the degree, Shift the seventh,
    0 the song's chord, all taken so the studio never sees them (its 1 to 3 pockets and 0 text
    size), and Esc turns the layer off and lets the catcher give its keys back. `click_releases`
    waits while `chords_on()`, and Interactor gains `presses_while_playing()`, true for the mouse
    while the layer is on, so a click strums the harp while J K L ; play. The layer lives in a
    catcher: with none focused (T, F1's card) it goes off. A left Glove (new Pose.SHAPE holding up
    `held_up`, `fingers_of(degree)`, and `say` for words past its fingertips) rides
    MouseInteractor.chord_pose, placed by the view's own size (CHORD_ACROSS of the half-width left,
    CHORD_DOWN of the half-height down at half a metre), so it is on the screen in any window and
    zoom: fingers up and its back to you for I to V, the thumb tucked across the palm unless it is
    held up (Glove.SHAPE_THUMB), so IV is four digits and V five; palm up and side on for vi and
    vii°, the fingers held out pointing across toward the middle of the view, clear of the curled
    ones; flat for the song's chord, `iv · Dm` or `song's · Am` over it. The HUD's focus field is `hud_text()`: `CHORDS · iv
    Dm`, or `CHORDS`. What reads the player's chord: ChordHarp.harmony_at (strings, letters, crown,
    and the hover card says `F, your IV (C major)`), FingertipNotes.tones_at, names and chord_name,
    InstrumentItem.harmony_at, the new home of the bells' (ChordHand.at while a hand here carries
    one, the song's otherwise), and the fifths wheel, which raises what follows well from the held
    chord (`held_chord`) instead of the last pressed and says `your chord hand's` on its segment;
    the held chord is the song's key's degree, what the hand plays, so with the hub turned to
    another key the follow-ups lead from it into the wheel's key, as from an outsider pressed. A
    ringing note keeps its pitch, and notes go out as notes. Stations.HELD gains CHORD SHAPES, the
    help card's ROOM page a Chords line, and the shot rig `--chords N` (the harp gone to, C, then
    key N; spatial32 is taken at frame 1500, once the go-to's and the layer's toasts have gone).
    The suite: `_test_chord_shapes_read_their_degrees_on_one_hand`,
    `_test_a_chord_shape_retunes_what_you_play`, `_test_the_chord_stick_latches_and_nudges_nothing`
    and `_test_the_desktops_chord_layer_is_c_and_the_number_row`. Not done: a bell rung under a shape
    is rung in the song's chord on a bandmate's machine, since a hit carries only its song position
    and the slice adds no wire; slice 33's `chord:P` is what tells the room the shape.
    shots/spatial32.png is the desktop's chord glove holding up iv over the harp, its strings in Dm.

33. [x] **Your chord hand drives their harp.** #33 finished. A `chord:P` jack source has a socket on
    the chord hand's wrist, beside keys:P (`wrist_mount`), and at a desk P steps it while the chord
    layer is on. `Jack.Kind.CHORD` goes down Session.send_jack on each shape's change: `pitch` the
    chord's root pitch class, `velocity` its quality's index in Harmony's qualities, 0 for none, and
    the host's per-kind clamp keeps them to 0..11 and the qualities' count. Into `player_Q`, Q's
    ChordHand takes it as a remote chord with the sender's name. Q's harp, fingertips and held bells
    play P's chord while P holds a shape, and Q's own shape wins over it. Unplugging or leaving lets
    it go. The host checks as for keys:P: only P sends chord:P. The cable is drawn as in slice 6,
    and the harp's crown says `IV from ADA`. Touches jack.gd, jacks.gd, jack_socket.gd,
    chord_hand.gd, session.gd, hand_skeleton.gd, studio.gd, tools/probe/session_probe.gd. The suite
    checks: a chord into a player retunes their harp's strum; their own shape wins; it lets go on
    unplug and on leaving; the host refuses chord:P from anyone else and an out-of-range quality.
    The probe checks that the guest holds IV with chord:P plugged into the host, and the host's
    strum plays IV's tones. Both sides at 0 failed. shots/spatial33.png is the harp's crown naming
    the sender.

    Built. `Jack.CHORD` (`chord:P`, `chord_source`, `chord_player`, and `own_player` for either of a
    player's own sources) and `Jack.Kind.CHORD`, appended so the other kinds keep their numbers: a
    chord as its root's pitch class (`chord_root`) and one more than its quality's place in
    Harmony.QUALITIES (`chord_quality`, 0 none), spelled back in the receiver's key
    (`chord_named`). `Jacks.send_chord`, each frame in `tick`, sends `ChordHand.own_chord` (the
    hand's own shape, never a chord it took, so two players plugged into each other never feed
    back) whenever [to, root, quality] changes: a new shape, a latched degree in a new key, the
    jack into another bandmate; an open hand is quality 0, sent only to whoever had a chord.
    `Jacks.received` hands a CHORD to `ChordHand.take`, and `_follow_cables` lets go every taken
    chord whose jack no longer goes into this player, as a stray note. A chord is sent once, so a
    replug must not lose it: the host passes it the moment it plugs the jack, before its room says
    so, and a CHORD from a `_cut` source is held (`_held_chords`) until the next patch says yes
    (taken) or no (dropped); and once the host's room says P's chord jack goes into a bandmate it
    did not say before (`Jacks.answered`, from `Studio.apply_room` before the guest's own
    predictions), P sends what it holds again, an open hand too; `drop_player` takes out a leaver's chord jack with their keys'. `sinks` steps a
    chord jack through bandmates only, `plug_refusal` lets only P plug it and never onto a track
    (`a chord hand goes into a bandmate, not onto a track`), `send_refusal` only P send down it
    (`that is Ada's chord hand`), and `Session._pass_jack` passes CHORD only down a chord jack and
    nothing else down one, refuses a quality outside 0..Jack.quality_count() and clamps the root
    to 0..11. `ChordHand` keeps `_theirs`, [source, from, root, quality], the latest winning;
    `harmony_at` is the own shape first, then `their_chord`; `crown_text` is `IV from ADA` (by
    `numeral_named`, the chord's own name where it is none of the key's degrees); `hud_text` says
    `CHORDS · IV F FROM ADA`; ChordHarp's crown shows `crown_text` fitted between its octave
    buttons (`CROWN_TEXT_WIDE`, Lettering.fit) and its hover card `F, Ada's IV (C major)`. The
    fingertips and carried bells follow through ChordHand.at as they did for a shape. At a desk P in
    the chord layer (`ChordHand._chord_key`, ahead of the catcher's own keys) steps `chord:P`;
    Shift+P still unplugs what goes into you. In a headset `JackSocket.mine_chord` (MY CHORDS) is
    worn by `Studio._wear_chord_jacks` on the chord hand: on the left wrist WRIST_CHORD_APART down
    onto the back of the hand from MY KEYS and as far across the left controller, or for a
    left-handed player on the right wrist and controller where MY KEYS sits on the left; its cable
    is slice 6's. The studio's notices say what a chord jack does (`Your chord hand goes into
    Grace: ...`, and to Grace who plugged it), and the help card's TOGETHER line names P in the
    chord layer. The shot rig gains `--chord-from N` (Lin's chord hand plugged in holding degree
    N). The probe: the guest plugs chord:G into the host at 60.62 and holds IV (Gm in D minor),
    the host's harp is Gm's with `iv from <GUEST>` on its crown and its strum plays Gm's tones, and
    it is let go once the guest unplugs at 60.74; the ending moved to 60.84 and 60.96 (host) and
    60.98 (guest). The suite: `_test_a_chord_jack_says_its_chord_in_two_numbers`,
    `_test_a_chord_into_a_player_retunes_their_harp`, `_test_my_chord_hand_sends_its_chord_down_its_jack`,
    `_test_the_host_says_who_may_send_a_chord` and `_test_my_chord_hands_jack_is_worn_on_its_wrist`.
    shots/spatial33.png is the harp's crown saying `iv from LIN`, its strings Lin's Dm in A minor.
34. [x] **The session in miniature.** The proving idea, #6. `MiniatureItem`
    (core/items/miniature_item.gd, kind `miniature`, home on the desk's left wing at
    `Venue.miniature_spot`) is a 40 cm model of the session to hold. Tracks are strips with their
    items as blocks and their names lettered, regions are bands, markers are flags (notes as pinned
    cards), and the loop is a bracket. The playhead moves (a step a beat at motion 0). The room's
    stations are pins round its edge, lettered. Pointing at a spot (a ray onto it, or the other
    hand's fingertip on it) names it in the hover card: track and time. A press seeks there and
    brings its gear via FocusRig: the console banks to the track (set_track_bank) and comes
    (FocusRig.focus(&"console")), and a press on an item selects it and brings the timeline scrolled
    to it. A press on a station's pin goes there: XRRig.travel in a headset (slice 11),
    go_to_station at a desk. At a desk: hover and click it on the desk, or carry it. Touches
    miniature_item.gd, item_room.gd, focus_rig.gd, studio.gd, venue.gd, the tests' shelf count and
    comment. The suite checks: the strips match the tracks and items; a press maps to (track, time);
    seek and bank; an item press selects and scrolls; a pin press travels in --xr-sim and walks at a
    desk; the shelf count. shots/spatial34.png is the miniature in a hand.

    Built. `MiniatureItem` (core/items/miniature_item.gd, kind `miniature`, the 23rd of ItemRoom.KINDS,
    last, with a home of its own) lies on a wooden tray (tools/blender/miniature.py,
    assets/models/miniature.glb: a slab, a felt bed sunk inside a 3 cm lip, four feet). The desk's left
    wing is `Studio.desk_wing`: a board at desk height (WING, WING_TOP) on a cheek and a rail, WING_GAP
    off the console's left end and standing out toward the seat (its back WING_BACK behind the desk's
    front), so a wide desk's end never puts the tray in the seat's line to the rack. `_place_desk_wing`
    follows the console's home box on every rebuild and rehomes the items; `_wing_footprint` is a floor
    plan fixture; `Venue.miniature_spot` reads it, the tray's reader's edge toward the mix position.
    Drawn in its own frame (reader at +Z, time along +X, the far strip the first track), unshaded and
    of its own materials: a strip a track with a chip of its colour and its name (fitted, left off
    under NAMED_LEAST), a block an item (a seam between items that meet, a muted one dark, a selected
    one taller with a light rail on top), the regions as lettered bands and the markers as flags with
    their names (the harmony after ` [` left off) along the far edge, a `NOTE ` marker as a card
    pinned at its time lettered without the word, the loop as a bracket, the playhead a lit line
    (`playhead_seconds`: the beat it is in at motion 0), and on the far lip `THE SESSION · point and
    press: play from there` and the clock. It redraws on the DAW's signals and a shape key. A pin a
    station standing here (`Studio._pin_stations`, again on a venue change), on the lip on its
    station's side as seen from the mix position (`pin_spots`, spread PIN_GAP apart), its head by its
    area and its title lettered along the edge. Taken by its front edge only (the grip, a box in
    front of the pins); the bed is the `Face` control, a thin box at block height so a glancing ray
    from the seat lands within a strip of where the eye meant. `spot_at` maps a point to {track,
    seconds, item} (the names' column a track and no time, the ruler a time and no track), `card`
    is the hover card (`MINIATURE  BASS`, `Chorus 1 on Bass · 17.1.00 · CHORUS`, `press: ...`), and
    a press says `pressed(track, seconds, item)`. `Studio._on_miniature_pressed` seeks, then on an
    item selects it alone, picks its track and moves the timeline's window so it starts SHOWN_IN in,
    and brings the timeline; on a track `ConsoleSurface.bank_to_track` (the bank keys' own deferred
    request) and brings the console. `Studio._bring` is `FocusRig.focus` (a visit at a desk, a
    summons in a headset), checked with the new `FocusRig.surface(id)`; a surface the mount shows on
    the screen (the timeline by default) is in view already, so a desk lets its gear go. A pin's press
    is `go_to_station`: XRRig.travel in a headset, the walk at a desk. Carried at a desk it rides low
    in the view tipped up to be read (VIEW_AT, VIEW_TIP); in a hand by its outer side, lying across
    in front of you wholly inside that hand's ray (HELD_CLEAR past its edge, by `hand_side`), so the
    carrying hand still points past it and its trigger never presses the bed. The bed and the pins
    are turned +Z up (FACE_UP), as Platter's Disc and SectionBlocks.Block are, so a fingertip's
    press lets go as it lifts straight off. Discoverable: its hover cards, the tray's own caption,
    and a HELD row `MINIATURE` on the help card. The suite: `_test_the_miniature_is_the_session_to_hold`,
    `_test_a_press_on_the_miniature_seeks_and_brings_its_gear`,
    `_test_a_pin_on_the_miniature_goes_to_its_station` and
    `_test_the_miniature_in_a_hand_and_under_a_fingertip`; the shelf counts in four older tests are 23
    and the duck's shelf comment names the miniature. shots/spatial34.png is the miniature carried at
    a desk, shots/spatial34_wing.png on the wing.

35. [x] **Point, mark and listen together.** The proving idea, #7. Pointing: hold Z at a desk, point
    the index level with the other fingers curled (HandPose `pointing`, as decided), or hold the
    non-chord hand's stick click on a controller. Presence already publishes what a player points at
    (`publish_presence`'s `pointing_at`, a control's key, and `pointing_local`), and draws a ghost
    pointing at it (Presence.find_control, avatar.point_at). That path is extended rather than
    doubled: `pointing_at` also takes `ruler:<seconds>`, `ghost:<peer>` and `room` (with
    `pointing_local` then in the session frame), and avatar.point_at draws a ray from the ghost's
    glove to a point as well as to a control, with the pointer's name at its end. It stays
    unreliable, like the head. Marks: a sticky note is a `NOTE ` marker as decided, and
    `Harmony.parse` answers null for one. O at a desk over the 3D ruler, the lanes or the miniature
    drops one at the hovered song time (or the playhead) and opens the typing pad (TypingPad). In a
    headset, the note pad on the desk gives a card to stick on the ruler or a lane, then the typing
    pad. Every section reader skips notes, and the 3D ruler draws each as a pinned card over its
    time. Listen from my spot: a note's LISTEN key, and the pointed time's while pointing at the
    ruler (Enter at a desk while Z is held; a pinch of the pointing hand's thumb and middle in a
    headset), seeks the shared transport there and plays (`seek` and `transport_play` as intents).
    Everyone is told `Ada: listen from 1:23 (CHORUS)`. Touches session.gd, presence.gd (the avatar's
    ray to a point), hand_pose.gd, xr_interactor.gd, mouse_interactor.gd, harmony.gd (NOTE_PREFIX,
    `parse`), chalk_venue.gd, tape_deck.gd, timeline_surface.gd, timeline_region_page.gd,
    typing_pad.gd, studio.gd. The suite checks: a ruler point and a room point are published through
    `pointing_at` and drawn as a ghost's ray, and a control point still draws as before; NOTE
    markers are skipped by the board, the deck, the flags and the ADD name, and shown whole by
    FlatHost; a note `NOTE try [G major] here` leaves Harmony.at in A minor; a note nudged a
    millisecond off a marker; LISTEN seeks and plays; Z with Enter listens and the walker does not
    jump; a guest's note is an add_marker intent. The probe checks that a guest's ruler point
    arrives at the host, and that its note is in the host's markers. Both sides at 0 failed.
    shots/spatial35.png is a bandmate's ray on the ruler beside a note.

    Built. Pointing: `Interactor.pointing`. PointAndMark sets it while Z is held at a desk (said
    once in a notice, and cleared when the window loses focus). In a headset,
    `XRInteractor.read_pointing` sets it each physics frame: a bare hand by `HandPose.pointing`
    (index level within POINT_LEVEL, uncurled, and the other three curled past POINT_CURL; once
    pointing, only the index is checked), and a controller by its stick click held, only on the
    hand that is not the chord hand (`points_by_stick`). While a hand points,
    `Presence.pointing_of` publishes `ghost:<peer>` for a bandmate nearer than any control;
    `ruler:<seconds>` for a song time (`Presence.time_at`, which is `PointAndMark.time_at`: the 3D
    ruler, the seek and loop strips, the lanes, and the miniature's bed); a control's key as before;
    or `room` with the ray's hit (or POINT_REACH out along it) in session space. Not pointing, the
    old hover and hold publishing is unchanged. A receiver draws a ruler time at its own ruler
    (`TimelineSurface.ruler_point`). The beam ends at a dot with the name and the time (`Lin  0:46`)
    lettered just back along it, in the pointer's colour (`Avatar.point_at(null, point, false,
    words)`). Marks: `NOTE ` markers. `Harmony.parse` returns null for one, and `section_of`
    returns "", so the board, the deck (section, locator text, and PREV and NEXT too), the flags,
    the grid lines and the ADD name all skip notes. `Harmony.section_at` is the deck's section
    reader now. `marker_label` says `note: ...`. FlatHost shows the whole name.
    `Harmony.note_spot` moves a note 1.5 ms off any marker it would land on, and `note_named` caps
    the name at MARKER_NAME_MAX. O over a time drops a note there (anywhere else, at the playhead)
    via `PointAndMark.drop_note`. At a desk the words are typed on NamePrompt, as the deck's MARK
    rename does, not on a TypingPad (a keyboard is at hand). In a headset they are typed on a
    TypingPad over the note pad. `NotePad` (hardware/console/note_pad.gd) is a block of yellow
    notes on a strip added to the wing's outer end (`Studio.WING_PAD`, 10 cm, in the floor plan as
    a second footprint). Grabbed, a card rides the ray. Let go, it emits `stuck` with what the ray
    was on, and PointAndMark drops a note there, or says where notes go. The 3D ruler lays each
    note out as a pale card pinned over its time (`_note_layout`). The card sits in the bar
    numbers' band, and stands a row up on a stem if it would run into a flag or another card, up to
    NOTE_ROWS. It is as wide as its words at NOTE_TEXT_SIZE, up to NOTE_WIDEST, with a play mark at
    its end. The whole card is the LISTEN key: a ControlAffordance named `Listen`, whose hover card
    reads `NOTE  <words>` / `press: LISTEN, everyone hears the song from <bar>`. Listen:
    `Session.listen_from` (DAW.seek, then DAW.transport_play; a guest's are intents). The host tells
    the room `Ada: listen from 1:23 (CHORUS)` (`Session.listen_words`); a guest asks with
    `_listen_asked`. Enter with Z held listens from the pointed time (Enter, not Space, so the walker
    does not jump). A pointing hand's thumb-and-middle pinch edge does the same in a headset. The
    help card's TOGETHER page has three new rows: Point, Sticky notes and Listen from there. Tools:
    `--point <key>` and `--point-at x,y,z` make the visitor Lin point. `--note secs:words` (`_` for
    a space) sticks a note and scrolls the timeline to it. The suite has four new tests:
    `_test_notes_are_not_sections_and_hold_no_harmony`,
    `_test_pointing_publishes_a_time_a_bandmate_or_the_room`,
    `_test_listen_from_a_note_or_where_you_point` and `_test_a_hand_points_by_its_pose`. The probe:
    the guest points at `ruler:37.25` and sticks `probe note` at 520 s from 60.82; the host checks
    both at 60.9 and takes the note back at 60.92. Its work line is now `of 60.96`, the host leaves
    at 60.96 and waits until 61.08, and the guest ends at 61.1. The probe was not run for this
    slice; it is left to the next checkpoint. shots/spatial35.png is Lin's ray on the ruler at 0:46
    beside the note `try a fill here`. shots/spatial35_pad.png is the note pad on the wing with its
    hover card.

    After review. `FifthsWheel.write` (the wheel's SET and a section brick's stamp) never renames a
    note on the bar line, which O at a bar line while stopped puts exactly there: the note moves to
    `Harmony.note_spot` and the brackets are added at the bar, both in one edit
    (`DAW.open_edit`), checked in `_test_the_fifths_wheel_sets_the_harmony_at_a_bar`. In AR, where
    there is no wing, the note pad stands at the console's left end at the desk's height
    (`Studio._place_note_pad`, NOTE_PAD_GAP off it, placed again when the console rebuilds), checked
    by `_test_in_ar_the_note_pad_stands_by_the_console`. A pointing hand's pinch listens only when
    the hand pointed the frame before, so a thumb already on the middle as the index goes out does
    not listen. A note's card is a song time (`TimelineSurface.note_time`, through
    `PointAndMark.time_at`): pointed at, it goes out as `ruler:<its time>`, and Z with Enter over it
    listens from it. Follow-up, not built: a headset player cannot yet edit or remove a note, since
    PREV and NEXT skip notes (so the deck's MARK cannot reach one) and the 2D ruler is desktop-only;
    a note card wants an edit and a remove of its own.

36. [x] **EQ as a wall of frequencies: spectra and clashes.** The proving idea, #8, first half.
    `EqWall` (hardware/eq_wall/eq_wall_surface.gd) is a Surface on its own trolley at the control
    room's side wall, so F visits it and G brings it. It is 2 m tall, with frequency up its height
    (20 Hz at the floor to 20 kHz at the top, log, lettered). Each track's spectrum is a see-through
    shape whose width at each height is the track's level in that band. They are centred and
    overlaid, each named and hatched its own way. Where two tracks are both above -30 dB in a band
    and within 6 dB of each other, the overlap glows, by brightness and a cross-hatch, and each side
    of the overlap is lettered with its track's name. Spectra: where the tracks are played (the
    built-in engine), each track bus ("R3D N") gets an AudioEffectSpectrumAnalyzer (Measure's way)
    at the very end of its tail, after the width enhancer, where cue, tap and send copies never take
    it. A bus's effects run before its volume, so the bands are scaled by the track's fader gain and
    are silent while it is muted, which makes them the levels heard. They are read in 31
    third-octave bands and averaged over 300 ms (`GodotBackend.track_spectrum`). The host sends them
    to guests five times a second as a byte a band per track (Session `spectra`, unreliable). On
    Reaper the wall says "spectra need the built-in engine" (Capability SPECTRA). Its SHOW key picks
    all tracks, the soloed, or the two that clash most. Touches eq_wall_surface.gd, spectra.gd (new,
    core/audio), godot_backend.gd, session.gd, studio.gd, stations.gd. The suite checks: a sine's
    band; the analyzer is the bus's last effect, and no cue or send carries one; a track faded 12 dB
    reads 12 dB lower and a muted one empty; the demo's kick and bass found clashing at their low
    bands; the wire's packing; the Reaper card; F visits the wall. The probe checks that the host's
    spectra reach the guest. Both sides at 0 failed. shots/spatial36.png is the wall with a glowing
    clash.

    Built. `Spectra` (core/audio/spectra.gd, a node the studio stands) holds the bands (ISO
    third-octave centres 20 Hz to 20 kHz), the clash rule, the wire's packing and the wall's
    reason. `GodotBackend._build_buses` puts an AudioEffectSpectrumAnalyzer (FFT 4096, 0.5 s
    buffer) last on every track bus, after the width and the pan; a cue, a tap and a send copy only
    the effects before it, and a render's capture goes on after it. `track_spectrum(i)` keeps the
    reads alive while it is asked (1.5 s), reads 20 times a second, averages the last six powers
    (300 ms), and adds the fader (its taper and the VCA) in software, since Godot runs a bus's
    effects before its volume. A track not heard (muted, or left out by a solo) reads the floor
    (-96 dB). The host, or a lone player, reads every track that makes sound (not a folder) at 20
    Hz, and the host calls `Session.send_spectra` every 200 ms: a byte a band (-96 to +6 dB in 0.4
    dB steps) after a u16 track, in parcels of at most 1100 bytes, unreliable and ordered on its
    own channel (`SPECTRA_CHANNEL` 7), to `_spectra_from_host`. A guest's Spectra reads
    `Session.spectra` while it is fresh (1.5 s). Capability SPECTRA: the built-in engine only; on
    Reaper, or on the stand-in, the wall says "spectra need the built-in engine", and a guest whose
    host sends none says it needs the host on it. `EqWall` (hardware/eq_wall/eq_wall_surface.gd)
    stands on its trolley at the control room's right wall (`Studio._eq_wall_at`, 62 cm in, at
    z -1.55, turned -74 degrees), station `eq_wall` with its plaque folded on its column; F visits
    it and G brings it. While other gear is brought it stays on its trolley rather than parking in
    the arc (`Surface.parks` false): parked, its 2 m alone pushed the arc out past 3 m. Each shape
    is an ImmediateMesh fill under one hatch shader (its own angle and spacing a track, `HATCHES`)
    and an edge line, named at its loudest band, beside its edge or just inside it where the name
    would run off the plot (`EqWall.beside`). The key down the column shows each track's swatch
    and name (ten rows and "+N more"), with a hover card of where it is loudest. A glow is the
    narrower shape over the clash's run, cross-hatched and brighter, its two names on either side
    (dark on the glow when they sit inside it) and its span above, and its hover card reads, for one
    in the demo, `CLASH  2 KICK / 6 BASS DI`, `63 Hz · -42 and -38
    dBFS`. A glow that is put out takes no pointer, so it shows no card. SHOW steps ALL
    TRACKS, SOLOED and WORST CLASH; the words in the middle say what is missing (play the song,
    nothing is soloed, no two tracks clash now). The wall redraws ten times a second, once a second
    at motion 0.

    One change from the plan: -30 dB is not under full scale but under the mix's loudest band,
    held by Spectra (it rises at once and falls 6 dB a second, and never under -48 dBFS). The demo's
    loudest band is about -20 dBFS and its bass is under -30 dBFS in its own lows, so at full scale
    the demo's kick and bass never clash. The wall is drawn against the same reference: its width
    is 0 to 60 dB under the loudest band, lettered at -30 and 0. The other: a full mix clashes in
    more places than a wall can show (the demo has about ten at once), so only the worst four that do
    not sit over one another glow, each lettered, and SHOW's caption counts the rest ("5 more
    clashes not lit"); WORST CLASH shows the worst pair alone.

    After review, three more. First, the reverb return took the glows. A return fed by sends is a
    sum of its senders, as a folder is of its children, so it matched each of them band for band,
    and in the demo all four glows were 13 VERB RTN pairs while the kick and the bass went unlit.
    `Spectra.feeds` now says whether a track's sound reaches another, through its sends, its
    folders' and a return's own. A pair one of which carries the other never clashes. A clash with
    a return that does not carry the other is "wet" and ranks after every dry one, in `clashes` and
    in `worst_pair`, so the four glows go first to fights at the source. Second, names printed over
    each other ("6 BASS DIDES", "136/ERB RTN"). The glows are now laid out before the shapes'
    names, and each name takes the nearest height clear of every lit glow (its span lettering
    included) and of the names before it (`EqWall.clear_height`). It is left off where a glow over
    its band already names that track. A glow's name runs into the left margin only between the
    frequencies lettered there. Third, a glow that was put out still caught the pointer and showed
    an empty "EQ WALL  CLASH" card; it now gives up its shape.

    The suite: `_test_a_tracks_spectrum_is_read_at_the_end_of_its_bus` (a 1 kHz sine into the
    snare's bus lands in band 1k; the analyzer is last and no cue or send bus has one; faded 12 dB
    it reads 12 dB lower; muted, the floor), `_test_the_demos_kick_and_bass_clash_at_their_lows`
    (the demo from bar 10, on the built-in engine; no clash pairs the return with a track that
    sends to it, and on a wall watched for 3 s the kick's and the bass's glow is lit most of the
    times they clash, and is otherwise kept off only by a dry fight sitting over it, with no name
    on the plot printing over another), `_test_spectra_ride_the_wire` (and `feeds`, through a
    folder's send and not a key's, and the wet ranking),
    `_test_on_reaper_the_eq_wall_says_spectra_need_the_built_in_engine`,
    `_test_the_eq_wall_draws_spectra_and_glows_where_they_clash` (with no name on the plot over
    another, and a glow put out taking no pointer) and
    `_test_f_visits_the_eq_wall_on_its_trolley`. The width test's bus lists end with the analyzer,
    and the every-venue station list has `eq_wall`. The probe: from 60.92 to 61.12 the host stands a
    Spectra measuring a made-up kick and bass and sends them; at 61.1 the guest checks the values
    within half a step and the one clash, bands 4 to 7. The host leaves at 61.16 (`of 61.16`) and
    waits until 61.28, and the guest ends at 61.3. The probe was not run for this slice.
    shots/spatial36.png is the wall during the demo (`--built-in --focus eq_wall --at 10 --roll`)
    with three glowing clashes: the kick's and the bass's at 63 Hz, the bass's and the return's at
    125 Hz, and the snare's and the rhodes's at 200 Hz. shots/spatial36_card.png is the kick and
    bass glow's hover card.

    Found on the way: `GodotBackend._exit_tree` removed every "R3D" bus, and `DAW.use` frees the
    old engine at the frame's end, after the new one has built its buses. A test that swapped one
    built-in engine for another was left with none, so the next one's render never finished and
    its spectra read the floor. It now removes buses only while it still has its own (not after
    `close`).

37. [x] **Carving the clash.** #8 finished. Grab a glowing overlap and push it into the wall to cut.
    The track cut is the one whose lettered side the grab was on, and the hover card names both:
    `push: cut BASS at 63 + 90 Hz`. No modifier. FXCatalogue gains a second EQ kind, `eq21`
    (AudioEffectEQ21: 21 fixed half-octave bands, 22 Hz to 22 kHz, gain only, each a Param named by
    its band), since EQ6's six bands cannot carve a clash: its 100 Hz band covers both a kick's and
    a bass's lows. The first push puts an `eq21` on that track at the chain's end (or ReaEQ on
    Reaper), inside the push's edit. Each push sets its bands: on the built-in engine, the bands
    whose centres fall inside the clash's span (at least the nearest one) are cut by how far it was
    pushed (0 to -12 dB). On Reaper, ReaEQ's band is set to the clash's frequency, its bandwidth to
    the clash's span and its gain to the push, by parameter name. One undo step a push. So the
    built-in carve is half-octave wide, not a narrow notch, and its card says so (`cuts the 63 and
    90 Hz bands`). The rack shows the EQ, and the wall redraws the carved shape. At a desk: drag the
    overlap's side down, with the wheel 0.5 dB a notch. Touches eq_wall_surface.gd, fx_catalogue.gd
    (`eq21`, a band's parameter by name), daw.gd (add_fx, set_fx_param reused), godot_backend.gd
    (the new kind), rack_surface.gd (none, it reads state). The suite checks: an `eq21` renders a
    cut at 90 Hz and not at 1 kHz; a push on the bass's side cuts the bass's bands inside the
    clash's span and is one undo step with the EQ's adding; a second push moves the same EQ; a grab
    on the kick's side cuts the kick; undo; the Reaper path names ReaEQ's band, frequency, bandwidth
    and gain parameters. The probe checks a guest's carve on the host's FX. Both sides at 0 failed.

    Built. `EqCarve` (core/music/eq_carve.gd) is static and pure, as Sidechain is: which engine
    carves (from the plugin choices, so a guest reads its host's), `bands_for` (the EQ21 bands whose
    centres are inside the clash's span, else the nearest), ReaEQ's first peaking band found by its
    parameters' names (`reaeq_params`: "Freq-Band 2", "Gain-Band 2", "BW-Band 2", or the bare
    "Freq-Band" form, Q as well as BW), and the writes. FXCatalogue has `eq21` ("EQ21", 21 bands
    named "22 Hz" to "22 kHz", -15 to +15 dB like EQ6's), `EQ21_HZ` and `param_named`; the built-in
    engine needed nothing else, since it builds every kind from the catalogue. The glow
    (EqWall.Clash) is the push: `edits_as_one`, so a grab or a wheel turn is one edit named "Bass DI:
    carve 50-100 Hz". The grab's side picks the track; the first push adds the EQ at the chain's end
    (`add_fx`, -1); the cut is how far the hand went into the wall since it closed (its aim's
    distance out, as the fifths wheel reads a pull) or how far the grab went down the wall, the
    larger, EqCarve.PUSH_FULL (0.2 m) for -12 dB, and back out or up raises it, each band from where
    it was and never boosted past it. The wheel over a side is 0.5 dB a notch (Shift 0.1). The card
    names both tracks in its title and, for the side under the pointer, `push: cut BASS DI at 63 +
    90 Hz · cuts the 63 and 90 Hz bands, each half an octave` and the desk's way; held, its value
    line and the span over the glow say the cut ("50-100 Hz · BASS DI -6.0 dB"). Where the EQ is not
    in the state yet (a guest's host, Reaper's poll, a ReaEQ whose names have not come) the push is
    kept and written when DAW.fx_changed says it has come ("its EQ on its way" until then). A glow
    in a hand keeps its clash while held, so a carve that ends the clash does not put the glow out
    under the hand; the others keep off it. The station's desk and hands lines (F1's PLAY page, the
    plaque, the board) say how.

    Honest limits. Godot's EQ21 bands overlap: two bands at -12 dB take about 5 dB off a sine at
    90 Hz (measured -2.6 to -7.9 dB), so the heard carve is gentler than the bands' numbers, and
    the card names bands, not a depth. ReaEQ's normalised laws are taken, not measured (frequency
    logarithmic over 20 Hz to 24 kHz, gain amplitude over four, bandwidth linear over 0 to 4
    octaves), and its parameter names are matched by pattern; neither was checked against a running
    Reaper. On Reaper the ReaEQ's adding is the edit's Undo block, but the band's writes are OSC's,
    each Reaper's own undo point, as the edit-groups decision allows, and they wait for the
    structure poll's names, so the first push's band lands after the let-go. The stand-in's ReaEQ
    has no parameter names, so on the stand-in a push adds the ReaEQ and sets nothing.

    The suite: `_test_an_eq21_cuts_its_band_and_not_a_kilohertz` (the kind's 21 named bands, flat
    by default, `param_named`, `bands_for(4, 7)` = 63 and 90 Hz; on the snare's bus its 63 and 90 Hz
    bands at -12 dB take a 90 Hz sine down and leave a 1 kHz one within 1 dB),
    `_test_a_push_on_a_glow_carves_the_track_on_its_side` (on the built-in engine: the card; a click adds nothing; a push on
    the bass's side adds an EQ21 at its chain's end; half a push down cuts 63 and 90 Hz 6 dB and the
    other 19 bands stay flat; no deeper than -12, on the bus too; held, the glow keeps its clash when
    the wall finds none; one step named for the carve; a second push moves the same EQ; two undos
    take it all back; a push on the kick's side cuts the kick; a hand pushed a quarter of the way
    into the wall cuts 3 dB; two wheel notches over the kick's side cut 1 dB as one step) and
    `_test_on_reaper_a_push_sets_reaeqs_band_by_name` (on the stand-in, whose choices are Reaper's:
    the ReaEQ added, waiting, and once named its band's frequency, bandwidth and gain set by name,
    one step with the adding). 37 checks, 0 failed; the eq wall's, the rack's and the stations' own
    tests at 1348 checks, 0 failed. The probe: from 61.14 the guest grabs the kick and bass glow of a
    wall of its own on the bass's side and drags it half way, held until 61.22; by 61.24 it has the
    host's EQ on the bass, cut -6 dB on the built-in engine; at 61.26 the host checks the EQ at the
    end of its bass's chain, on the built-in engine its bands at -6 dB and the rest flat and the
    EQ21 on the bus, and on the stand-in and the built-in engine one step named for the carve, which
    one undo takes back (on Reaper the ReaEQ is removed by hand). The host leaves at 61.3 (`of 61.3`)
    and waits until 61.42, and the guest ends at 61.44. The probe was not run for this slice.
    Fixed after review: the EQ was asked for as the grab began, so a click on a glow to see what it
    does left a flat EQ21 (a ReaEQ in the user's project on Reaper) and an undo step that changed
    nothing; it is now asked for once the push has cut at least a Shift notch (Clash.PUSHED_DB),
    still inside the push's edit. Where the EQ is on its way, a second grab asked again; the track
    is now remembered as asked for (`Clash.asked_for`, cleared when the EQ is in the state, lapsing
    after 8 s so an asking that never came can be made again), and a grab on a push still waiting
    carries its cut on. The wheel during a drag counted the drag twice; the push now keeps the
    wheel's total (`base`) apart from the drag's cut (`drag`), and the wheel turned while a grab
    holds carries that push on. A landed EQ's cut is written once the plugin has finished landing,
    since its name arrives before its flat parameters do. On Reaper the card warns where ReaEQ's one
    band is cutting another clash ("its one band, cutting 300 Hz now, moves here"). The station
    board's test now builds the desk before measuring its footprint (it read [] and stopped with a
    SCRIPT ERROR). The suite adds `_test_a_carve_asks_for_its_eq_once_while_it_is_on_its_way`, and
    the push test checks that a click adds nothing and is no undo step and that a wheel notch during
    a 6 dB drag gives 6.5 dB; the probe's guest clicks the glow before its push, so the host's chain
    shows one EQ, not two.

    shots/spatial37.png is the wall during the demo with a held push on the kick and rhodes glow's
    rhodes side (`--built-in --focus eq_wall --at 10 --roll --no-hud --drag 870,612:870,660@44-80`,
    frame 74): its span and the card say "RHODES -5.9 dB". shots/spatial37_card.png is the kick and
    bass glow's card at 40 Hz (`--hover 860,698`, frame 58): "push: cut BASS DI at 44 Hz · cuts the
    44 Hz band".

38. [x] **Instruments that stand still.** No new idea; the drums, pads, venues' instruments and the
    looper's pad stand on it. Fixed instruments as decided: `Item.fixed` (a grab plays, its home is
    its station, ItemRoom never lays, throws or pockets it), `Strike` (fingertips, palms, controller
    tips and grip points, pokes; confident frames only), and `zone` through `played`,
    ItemRoom.played, `Session.send_item_hit`, `item_hit` and `heard`. Presence plays a bandmate's
    fixed hit from where the item stands, not from the bandmate's hand. The mouse strikes by a click
    (96, Shift 64) whose zone the item answers from where it lands (`zone_at(point)`). It is proved
    in the suite by a test-only fixed kind; the first player-facing ones are slice 40's drums.
    Touches item.gd, instrument_item.gd, strike.gd, item_room.gd, hit_recorder.gd, session.gd,
    presence.gd, mouse_interactor.gd, xr_interactor.gd, tools/probe/session_probe.gd. The suite
    checks: a tip crossing a head at 1 m/s plays with its velocity and zone, a slow touch does
    nothing, and a hand that loses tracking on one side and reappears on the other plays nothing; a
    controller tip strikes; the mouse's click strikes with its zone; a fixed item cannot be carried,
    thrown or pocketed, and a grab strikes it; item_hit carries the zone and Presence plays it at
    the item. The probe checks that a guest's strike on a fixed test item reaches the host with its
    zone and song. Both sides at 0 failed.

    Built. `Item.fixed` is a flag a kind sets before it enters the room. A grab on a fixed item is
    let go of at once, as the personal dispenser's is, and struck where it landed (`Item.struck_by`;
    InstrumentItem's strikes `zone_at(at)` at `Strike.click_velocity`: 96, or 64 with the hand's
    fine modifier, Shift on a desk). A fingertip's touch (a PokeInteractor, `touches_directly`) is
    left to Strike, so it is not struck twice. `Interactor.pick_up` refuses it, `Item.follow` (a
    hold that says somebody has it) does nothing, and ItemRoom's `lay` (home, false), `throw`, `fly`,
    `pocket` and `put_down` leave it, `apply` never moves it, and `spawned_ids` does not count it as
    a spill. `Strike` (core/music/strike.gd) is a node the studio stands. Each physics frame it reads
    `Strike.points`: each HandGestures hand's five tips and palm and each poke's tip, only while
    that hand is `confident`, and each XRInteractor's controller tip (XRRig.TIP_OFFSET) and grip
    point, only while its pose is HIGH confidence and it is not a bare hand. Points are keyed by
    tracker name, so a hand's joints and its poke are one hand. `crossing` finds a point that went
    from outside a face (InstrumentItem.faces: a frame with +Y out of it, and a radius or a
    rectangle's half size, EDGE 1 cm of slack) to on or inside it, and its speed along the normal.
    STRIKE_MIN is 0.4 m/s, a step past MOST_STEP (0.25 m) is a tracking jump, and a point missing on
    either frame is no crossing. Each hand's fastest crossing of an instrument in a frame is its
    strike, and the same hand strikes the same instrument again only after AGAIN_AFTER (70 ms), so a
    slap's six joints are one hit. The velocity is InstrumentItem.velocity_for(speed). InstrumentItem
    gains the virtuals `faces`, `zone_at`, `zone_words`, `zone_kind` (the zone's Foley sound,
    `kind_of_hit`), `zone_note` (the zone's recorded note) and `has_zone`, plus `strike`, `last_zone`,
    a fixed item's card (its zones as the readout, and "click to strike it, Shift-click softly ·
    where you click picks the sound" at a desk, "strike it with a hand, or a controller's tip or
    grip" in a headset) and the group Strike.GROUP. `played`, `ItemRoom.played`, `Jacks.hit`,
    `HitRecorder.hit`, `Session.send_item_hit`, its two rpcs, `item_hit` and `heard` carry `zone`.
    The host passes on only a short lower-case word (`Session.clean_zone`), and a copy rings a zone
    it has not got as none. The studio sends a fixed item's strike as a hit, though struck, since
    there is no use to send it as. Presence plays a bandmate's strike on a fixed item from whoever
    sent it (not this player), with nobody holding it, struck, on their zone, with Foley.play on the
    item where it stands. The host's sampler catches it on that zone too. The test-only kind is
    `TestDrumItem` (core/items/test_drum_item.gd, `testdrum`, made by ItemRoom.make but never in
    KINDS). It has one round head 30 cm across (15 cm in radius) at 62 cm, with bass inside 0.35 of
    the radius, slap past 0.8 and tone between, as slice 40's drums will have. Each zone has its own
    sound (conga, bongo, rim) and GM note (64, 63, 62). mouse_interactor.gd and xr_interactor.gd
    needed nothing: the mouse strikes through the grab contract and its existing `fine`, and Strike
    reads the controllers off their XRInteractors.

    Honest limits. No player-facing fixed kind exists yet, so nothing in a player's room is struck
    this way until slice 40, and F1 and the welcome card do not mention it; the hover card is where
    a desk learns it. The crossing is the joint's own point against the face, with no finger
    thickness, and a hand resting on a head that lifts off and comes down slowly within 70 ms of a
    strike is not struck again. The controller's grip point is the grip pose's origin, inside the
    fist, so a controller brought down butt first strikes late. None of it was tried in a headset.
    Strike hears only this player's own hands. A bandmate's strike is a hit on the wire, at the
    keys channel's latency, as every hit is, and the fast path is slice 39's.

    The suite: `_test_a_strike_crosses_a_head_with_its_speed_and_zone`. A tip crossing the head's
    middle at 1 m/s plays velocity_for(1.0) on the bass. Between is the tone and the rim the slap,
    each as hard as it was struck. A slow touch, a hand going down beside it, one coming up out of
    it and a 0.4 m jump do nothing. A real HandGestures hand slapped flat is one strike. A hand that
    loses tracking above and reappears below plays nothing, and neither does one with guessed
    joints. A controller registered with XRServer strikes with its tip at velocity_for of its
    speed on the bass, but not with LOW confidence. `_test_a_fixed_instrument_is_struck_never_carried`:
    the room stands the test drum and it is no spill. A grab strikes 96 on the bass and does not
    pick it up. With fine held it is 64, and the shell's side is the slap. A poke's grab strikes
    nothing. It cannot be carried, laid, thrown, flown, pocketed or put down, a room's word and a
    hold do not move it, and its card says how at a desk and in a headset. Its notes are 64, 62 and
    63. `_test_a_click_strikes_a_fixed_instrument_and_a_bandmate_hears_it_there`: in a studio on a
    desktop, the mouse over the head finds it. A click strikes the bass at 96 and is sent as a hit
    with its zone, heard on MONITOR, not carried. A Shift-click at the rim is the slap at 64, both
    recorded onto the armed track as their own notes. A bandmate's `item_hit` with `slap` is played
    by an AudioStreamPlayer3D at the drum, Foley's rim take it named. A zone it has not got is none,
    my own hit come back is not played twice, and `clean_zone` keeps only a word. 37 checks, 0
    failed. The existing tests for the code it touches (the shaker, percussion, bells, jacks, snap,
    sampler, presence, throws, pockets, personal copies, spills, the closed hand and the fingertip)
    run at 397 checks, 0 failed (434 with the three new). The probe: by 61.28 each half stands the
    test drum at DRUM_HOME. At 61.3 the guest's fingertip comes down through its rim at 2 m/s, its Strike stepped
    by hand, to a clock of its own at 700 s. By 61.36 the host has the hit from the guest with zone
    `slap`, song 700 and velocity_for(2), and its drum plays it through Presence's `_on_item_hit` where
    it stands, held by nobody. The host leaves at 61.4 and waits until 61.52, and the guest ends at
    61.54. The probe was not run for this slice.

    shots/spatial38.png is the test drum stood on the floor right of the desk (`--test-drum --aim
    TEST_DRUM --click TEST_DRUM@40`, frame 70), with its card: "TEST DRUM · centre bass · between
    tone · rim slap · click to strike it, Shift-click softly · where you click picks the sound".

39. [x] **Strikes on the fast path.** No new idea; it is the latency budget for everything struck.
    native/keys.c gains one-shot sample voices: `load SLOT PATH` reads a 48 kHz WAV into one of 128
    slots, and `hit SLOT GAIN PAN` plays it on one of 16 voices, in the graph's callback, as notes
    are. NativeKeys gains `load` and `hit`. At launch, each struck kind's Foley takes (eight a kind
    and zone) are rendered to user://hits/ and loaded. InstrumentItem plays a hit from this player's
    own hand on the helper, panned by the hand's side, when the helper runs, and on MONITOR as today
    when it does not. A bandmate's hit stays on Godot's mixer, placed where the item stands. The
    instrument's tag shows which path it takes and its figure. Touches native/keys.c,
    native_keys.gd, instrument_item.gd, foley.gd (renders to files), studio.gd. The suite checks:
    the helper parses `load` and `hit` lines (its line parser, headless); its `--render` of a hit
    line equals the slot's WAV at that gain; a local hit goes to the helper when it runs and to
    MONITOR when not; a bandmate's hit never goes to the helper; the tag names the path.

    Built. native/keys.c holds SLOTS (128) one-shot sample voices beside the tine. `load SLOT PATH`
    reads a 48 kHz 16-bit mono WAV (at most ten seconds) on the main loop and answers `loaded SLOT
    FRAMES` or `refused SLOT WHY` (no such file, no such slot, not 48 kHz, not 16-bit mono PCM).
    The samples go to the realtime thread as an event, so a voice never reads a slot being swapped,
    and a slot loaded again stops its voices there and hands the old samples back to the main loop
    to free. `hit SLOT GAIN PAN [SPEED]` plays it on one of HIT_VOICES (16, the oldest stolen) in
    the callback: GAIN linear, PAN -1 to 1 with both sides whole in the middle, SPEED a pitch_scale
    read between samples in a straight line. It is added after the tine's saturation and volume, so
    it is its WAV at that gain exactly, and its arrival is the `latency` the helper measures, as a
    note's is. `--no-midi` makes no sequencer port. `--parse` says what each line was taken as
    (`ignored ...` for the rest), and `--render` plays hits as it plays notes. NativeKeys gains
    `start`'s `midi` and `name`, `load_slot`, `hit`, `hit_line`, `play_hit` (false where it does
    not hold that slot), `loaded` and `refused` (from `hear`), `hit_latency`, and `load_hits`:
    Foley.write_hits on a worker thread, each written file loaded by `poll`. Foley gains HIT_RATE,
    `hit_slot` (a kind's place in SOUNDS times TAKES, plus the take; -1 for a kind not in SOUNDS),
    `hit_wav` (the very stream `sound` makes, read across from 44.1 to 48 kHz by `resampled`) and
    `write_hits` (every take of every kind to user://hits/). The studio starts a second helper,
    `dawlings · hits`, wherever the keys' helper could run (`_start_hit_voices`), sets
    `InstrumentItem.fast_path` and `fast_latency`, reads its news each frame
    (`_follow_hit_voices`), and drops it if it dies, every hit back on MONITOR. InstrumentItem.play
    asks the fast path first with the hit's Foley kind (`kind_of_hit`, a zone's on a fixed one),
    take, gain (`monitor_gain`: `level_db` through the Monitor bus's fader and mute, as Godot would
    have played it), pan (HAND_PAN, 0.3, times the hand's side: `side_of`, an XRInteractor's
    `hand_side`, Strike.side_of a tracker's name, 0 for the mouse) and speed (`pitch_scale` and a
    pitched one's note), and plays an AudioStreamPlayer on MONITOR only where it says no.
    `last_path` says which. `heard` (a bandmate's) never asks it. The hover card says "heard on the
    fast path, 5 ms" or "heard on MONITOR through the app, N ms" after what the item is doing
    (`path_words`), and in a headset, which has no card, a shelf item's and a fixed one's tag say
    "FAST PATH · 5 ms" or "MONITOR · N ms" (`path_tag`). The figure is the helper's own last
    measured `latency` once it has one, and two 128-frame cycles (5 ms) before its first hit. The
    fast path counts as running only once some sound is loaded.

    Honest limits. Foley has four takes a kind (TAKES), not eight, and its 18 kinds at four take 72
    slots; eight would be 144, past the 128. A zone is its own kind (conga, bongo, rim), so a zone's
    takes are its kind's. Writing the 72 files takes a few seconds at launch on a worker thread, and
    until they are in every hit is on MONITOR, as the tag says. Hits are as fast as notes: one
    run of native/keys.c measuring both, by its own `latency`, gave hits 3.1 to 5.3 ms and the
    notes after them 3.2 to 5.0 ms into the rig's null sink at `--quantum 128` (where
    tools/keys_latency.sh measures the keys' 4.3 ms), and 10.8 to 16.0 ms for hits and 11.8 to
    15.0 ms for notes on this machine's default device. So the fast path meets the decision's
    "about 5 ms" wherever the keys do, and a real card adds its own output latency after the
    sink, for notes and hits alike. tools/keys_latency.sh itself still sends only notes. The
    "5 ms" a card shows before the first hit is the two-cycle estimate, and the figure after it
    is the helper's own measurement on whatever device it is on. A hit on the fast path never
    passes through Godot's buses: the Monitor bus's volume and mute are read into its gain, but
    nothing else on that bus (its effects, whatever a personal mix takes from it) acts on it.
    Nothing was tried in a headset. The probe has nothing new to check, since nothing on the wire changed.

    The suite: `_test_the_hits_helper_loads_and_plays_struck_sounds`: every sound's every take has
    a slot of its own inside 128, the duck none; a hit's WAV is its sound at 48 kHz and as long;
    write_hits writes them all; `loaded` and `refused` are kept; the line parser (`--parse`, headless)
    loads a 48 kHz WAV into its slot and refuses a 44.1 kHz one, a missing file and slot 200, each
    saying why, reads a hit's gain, pan and speed (1 when left out), and ignores slot 999; its
    `--render` of a hit is the slot's WAV at that gain on both sides (worst under 0.00001), hard left
    is all left, twice as fast is half as long, and an empty slot is silence.
    `_test_a_hit_here_takes_the_fast_path_and_a_bandmates_never`: a shake here goes to the fast path
    with its kind, take, level and speed and not through Godot as well; a left hand's is panned left
    and a right's right; a second copy's lower voice is slower there; where the path says no, and
    where there is none, it is on MONITOR at its level; a bandmate's never goes to it; a helper that
    holds the slot writes that slot's `hit` line and one that has not loaded it is MONITOR; a left
    palm on the test drum is the conga panned left and a click on its rim the rim in the middle; the
    tag and the card name the path and its figure, MONITOR with none, and a drum's tag says it in a
    headset and nothing at a desk. `_test_the_studio_plays_hits_on_its_helper_while_it_runs`:
    headless there is none and the path says so; a helper whose sounds are not in is not the fast
    path, and once they are it is, at its figure; it plays a slot it holds and not one it does not;
    one not running is dropped; a studio gone leaves no fast path. 36 checks, 0 failed. With the
    existing tests for the code it touches (the keys helper, the monitor synth, bends, the shaker,
    percussion, hit takes, bells, the carrying hand, hits played back, the closed hand, snapping, a
    guest's hit, the strikes and the fixed drum, the duck) 328 checks, 0 failed.

    shots/spatial39.png is the test drum's card at a desk (`--test-drum --aim TEST_DRUM`, frame
    240), the real hits helper running: "TEST DRUM · centre bass · between tone · rim slap · heard
    on the fast path, 5 ms".

40. [x] **A circle of hand drums.** The proving idea, #30. `HandDrum` (core/items/hand_drum_item.gd)
    is four fixed kinds in ItemRoom.KINDS: `djembe`, `conga_hi`, `conga_lo` and `cajon`, standing in
    a ring on the drum riser (`Venue.drum_circle_spot(n)`, zone `drums`, solids in the zone's
    branch). Where the head is struck picks its zone: bass at the centre (inside 0.35 of the
    radius), slap at the rim (past 0.8), tone between. On the cajón the top corners slap and the
    face's middle is bass. Each zone records as its GM pitch on channel 9 and plays back as a drum
    (slice 16): the djembe's bass, tone and slap as low conga 64, open high conga 63 and mute high
    conga 62; the congas 63 and 62 high, 64 low with slaps; the cajón's bass as kick 36 and its slap
    as snare 38. Foley.hand_drum(kind, zone, take) synthesises each, heard through the fast path
    (slice 39). Bare hands strike by palm and fingers, controllers by their tips and grip points,
    and the mouse by a click whose zone is where it lands (Shift soft). They record, plug and are
    heard from where they stand. Their plaque says "strike the head: centre bass, rim slap ·
    controllers are steadier for fast parts". Touches hand_drum_item.gd, item_room.gd, foley.gd,
    venue.gd, stations.gd, the tests' shelf count (fixed kinds counted out by name),
    tools/blender/hand_drums.py, tools/probe/session_probe.gd. The suite checks: the zones by
    radius, from a hand and from the mouse; GM pitches per zone; a recorded djembe pattern plays
    back as drums on the built-in engine; every venue's riser holds the ring clear (the zone
    checks). The probe checks that the guest's slap on the djembe reaches the host with its zone and
    song. Both sides at 0 failed. shots/spatial40.png is the ring on the riser.

    Built. `HandDrum` (core/items/hand_drum_item.gd) is one InstrumentItem for the four, `kind` its
    id: `djembe`, `conga_hi`, `conga_lo` and `cajon`, last in ItemRoom.KINDS (`make` answers them).
    The djembe's head is 33 cm across at 92 cm, the high conga's 28 cm and the low's 31 cm at 1.06 m,
    each in a three-legged steel stand `HandDrum.STAND` (30 cm, a riser's height) tall, and the cajón
    a 30 by 48 cm face (its tapa) on a 56 cm stand, so all are played standing on the riser with
    their heads where they would be above the floor beside it. A round
    head's zone is by radius (bass inside 0.35, slap past 0.8, tone between, a click on the shell's
    side the slap); the cajón's face is a rectangle face to Strike, its top 10 cm (CAJON_SLAP: the
    top corners and the edge between them) the slap and the rest the bass. NOTES records the
    djembe 64, 63, 62; the high conga 63 bass and tone, 62 slapped; the low conga 64 for all three;
    the cajón 36 and 38; on HitRecorder.CHANNEL, so ItemVoices plays them back as its congas, kick
    and snare. `Foley.hand_drum(kind, zone, take)` synthesises each zone: a round head's bass a low
    swept sine under a dull palm knock, its tone the drumhead's five inharmonic modes (MEMBRANE)
    settling in pitch, its slap a highpassed crack of noise over the tone choked short (per drum
    from HAND_DRUM_TUNING); the cajón's bass a box's boom with its wires just touched, its slap a
    dry crack and the wires' buzz. Each is a kind of `Foley.SOUNDS` named `<kind>_<zone>` (11), so
    each has its own fast-path slots: 29 kinds at four takes is 116 of the helper's 128. Each drum
    has its own jack on its front, out of its grip so a click from the desk finds it: on the
    djembe's waist under its bowl (its grip is the bowl and head only, `grip_from`), on a conga's
    belly, and on the cajón's stand under its face. `Venue.drum_ring(box, n, floor)` places the ring: its middle on the riser's top
    (`Venue.drum_floor`: the step the walker climbs there in `zone_solids`, or the floor where the
    riser is only drawn, as in the chalk zone, so a drum never hangs over a drawn one), its
    front (+Z) toward the mix position snapped to the nearest of the four ways, and the drums
    DRUM_RING (0.72 m) out on the diagonals, the djembe front left, the cajón front right and the
    two congas, the tallest, behind, every drum's front toward the ring's front, so its jack and the
    cajón's face are seen from the seat. `drum_circle_spot(n)` is it in a venue's own zones (-1 the
    middle, the station's spot), null with no drums zone. `ZoneKit.solids` adds each drum's
    footprint (DRUM_FOOT, a side toward the ring's middle) to the riser's, so the walker goes round
    them, a throw bounces off them, and every venue that builds on ZoneKit has them (the chalk zone,
    which walks through its sketches, does not, and draws only the riser's outline round them, its
    sketched kick and snare gone from among them). A station's seat is on whatever is stood on there
    (`Stations.seat`, `Venue.floor_at`, `Walker.ground_of`), and `XRRig.travel` keeps its height, so a
    headset travelling to HAND DRUMS has its real floor put down on the riser's top it sees, and is
    seen by bandmates standing on it; the desktop's walker is put down on it the same way
    (`Walker.travel_to` stands on `ground_at`). The station `drums` (HAND DRUMS, zone `drums`, air
    0.5) is the ring's middle; the studio stands its plaque low on a slim post between the front two
    drums, leant back 40 degrees like a lectern's so it reads from above and stays under the line
    from the desk's seat to the congas behind it (`Studio.drum_circle`, Stations.DRUM_PLAQUE and
    DRUM_PLAQUE_TILT, 56 cm wide to fit), folded,
    and `_item_homes` gives each drum its place, so the PLAY page, I and Shift-I, the station board,
    the headset's travel and the clearance loop all have it. A fixed kind in KINDS never takes a
    shelf spot: `ItemRoom._rehome` stands it at its home or, where there is none (the Rig Roulette
    room, AR), puts it away with `ItemRoom.stand(id, null)` (hidden and PROCESS_MODE_DISABLED, so no
    ray, socket or Strike finds it); `stands(id)` says which. tools/blender/hand_drums.py builds
    assets/models/djembe.glb (a carved goblet, its skin, two rope rings and the rope's zigzag),
    conga.glb (glued staves under a chrome hoop and six lugs, widened by HandDrum for the low one)
    and cajon.glb (plywood, a paler tapa with screws at its top corners, a sound hole in its back,
    a black steel stand). The probe stands the djembe on both halves at DJEMBE_HOME by 61.28
    (`ItemRoom.stand`, since a room without a venue has it put away), and at 61.32 the guest's
    fingertip comes down through its rim at 2 m/s to a song position of 702 s; by 61.36 the host
    checks the hit from the guest, `slap`, song 702 and velocity_for(2), and that its own djembe rings
    it where it stands on its slap's sound, held by nobody.

    Honest limits. The cajón is struck only on its face: a hand coming down on its top (where a
    player sits) strikes nothing, and nobody sits on it, since a standing headset player has no
    seat; it stands on a stand instead. The cajón's slap is its whole top edge, not only its
    corners, as a click at the top middle is a slap too. The low conga records every zone as 64
    and the high conga its bass as its open tone, since General MIDI has three conga notes, so on
    playback (and on Reaper's own instrument) those zones are not told apart; heard live they are.
    ItemVoices plays the recorded djembe as its congas, not as the djembe's own synthesis. The
    drums stand only on a venue's riser: in AR they are put away, as every station but the pads is
    until slice 60. In the chalk zone, whose riser is only drawn and walked through, they stand on
    the floor inside its outline, and a headset there stands on the floor too. None of it was
    tried in a headset, and hand tracking at fast parts is what the plaque warns of. The probe
    was not run for this slice.

    The suite: `_test_hand_drums_play_where_the_head_is_struck`: the room makes the four, fixed,
    titled DJEMBE, HIGH CONGA, LOW CONGA and CAJÓN; across each round head from three ways, bass
    inside 0.35, tone to 0.8, slap past it and on the shell's side; the cajón's middle and low
    corners bass, its top corners and edge slap; eleven zones, eleven sounds Foley knows; a
    fingertip on the djembe's middle is the bass, at its rim the slap, a controller's tip between
    the tone, each at velocity_for its speed; a palm into the cajón's top corner the slap, its
    middle the bass, one coming out nothing; a click on the low conga's middle is the bass at 96,
    a Shift-click on its rim the slap at 64, a click on the cajón's top corner the slap, heard as
    its own sound; the card says the zones and how a desk strikes it; the jacks.
    `_test_hand_drums_record_as_gm_drums_and_play_back_as_drums`: the GM notes per zone on channel
    9, which ItemVoices plays as congas, kick and snare; an eight-hit djembe pattern recorded and
    rendered by GodotBackend.render_midi is ItemVoices' drums to a sample and not the tine's;
    Foley's eleven, each take a slot inside 128, a slap brighter than a tone brighter than a bass,
    two takes different. `_test_the_hand_drums_stand_in_a_ring_on_every_riser`: in every venue and
    arrangement each drum at its place, on what the walker stands on there (the riser's top where
    it is solid, the floor in the chalk zone, where it is not), inside its edge, apart, solid to the
    walker, the ring facing the desk; its seat on the same floor, every head 85 cm to 1.1 m above
    the seat's feet; the chalk zone's drums sketch only the riser's outline; the plaque's line is "strike the head: centre bass, rim slap
    · controllers are steadier for fast parts", folded; a bandmate's slap on the djembe rings at it
    with the slap's sound; in the Rig Roulette room the drums are put away and a hand there strikes
    nothing, and in the next venue they stand and strike. 65 checks, 0 failed. The seat's click
    audit found the first plaque (upright, at the drums' height) in front of the low conga and its
    jack, and the djembe's and the cajón's jacks inside their own grips; the plaque was lowered and
    leant back and the jacks moved out, and it passes. The clearance loop
    now holds the drums (`_station_stands`, its zone check: air clear of the zone's solids, the
    drums' own among them) in every venue, the shelf counts count the four out by name
    (`_shelf_kinds`), and the station lists (by area, the PLAY page, I, the board) have it last.
    With the existing tests for the code it touches (the stations, the clearance loop, going to and
    travelling to a station, the help card, the board, the duck, the bells, the cassette, the
    bricks, the miniature, the walls and the riser, the big board, the strikes and the fixed drum,
    the hits helper and the fast path, hits played back, percussion, the stage table, the platter, the EQ wall, the seat's click audit, the trolleys) 1883 checks, 0 failed.

    shots/spatial40.png is the ring on the studio's riser from behind the seat (`SHOT_CAM
    "3.14,-0.42,2.9,-3.0,0.75,5.8"`, `--no-hud`): the djembe and the cajón in front, the two congas
    behind, each on its stand, the folded HAND DRUMS plaque low on its post between. shots/spatial40_card.png is the
    djembe's hover card at a desk (`--aim DJEMBE`): "DJEMBE · centre bass · between tone · rim slap
    · heard on MONITOR through the app, 34 ms · click to strike it, Shift-click softly · where you
    click picks the sound".

    Review. A headset travelling to HAND DRUMS had its play space's floor at 0 under the riser it
    saw, 30 cm down: hands went through the "floor" and bandmates saw the avatar sunk into it, and
    the heads were only comfortable because of the mismatch. Now `Stations.seat` stands a seat on
    whatever is stood on there (`Venue.floor_at`, by `Walker.ground_of` as the walker finds its
    floor), `XRRig.travel` keeps the seat's height, and `Walker.travel_to` puts the desktop's feet
    on it too; the drums went up on stands by the riser's height (`HandDrum.STAND`; the djembe and
    congas in three-legged stands, the cajón's frame 30 cm taller, rebuilt by
    tools/blender/hand_drums.py), the plaque and the station's look point with them, so each head
    is where it was above the player's real feet. In the chalk zone the ring hung 30 cm over a
    riser that is only drawn; it now stands on the floor there (`Venue.drum_floor`), and the
    sketched kick and snare among the drums are gone. The suite: the ring test holds every drum to
    what the walker stands on at the ring (the riser's top where it is solid, the floor in the chalk
    zone), the seat to the same floor with every head 85 cm to 1.1 m above its feet, and the chalk
    zone's sketch to the riser's outline; the clearance loop holds every station's seat to the
    walker's floor under it; the headset travel test goes to the drums and checks the play space's
    floor is the riser's top, and the floor again at home. With the tests for the code it touches
    (the drums, the clearance loop, going, walking and travelling to a station, the help card, the
    walls and the riser, the seat's click audit, the strikes and the fixed drum, the EQ wall's
    visit) 1678 checks, 0 failed. shots/spatial40.png is retaken on the stands;
    shots/spatial40_chalk.png is the chalk zone's ring on its floor (same `SHOT_CAM`, `--venue chalk`).

41. [x] **Drum pads on anything.** The proving idea, #10. `SurfacePads` (core/music/surface_pads.gd,
    this machine's) are up to eight pads, each a 6 cm disk on a real surface, kept in the session
    frame (RoomAnchor) and saved here (user://pads.cfg), since the surfaces are this person's own.
    Marking, in a headset: the PADS card on the desk's MARK key, then touch a surface with an index
    tip, or a controller's tip (XRRig.tip_of) with its trigger held, and hold still 0.6 s. A pad
    appears there, its plane the surface (horizontal at the tip, or along the tip's last approach
    for a knee or a crate's side). Each pad's drum (KICK, SNARE, HAT, CLAP, TOM, RIM) is its nudge,
    lettered on it. Struck through Strike, the pads play the shared fixed item `kit` with `zone` as
    the pad's drum, so hits are item_hit heard from the striker's ghost, plugged and recorded as GM
    drums, and played back as drums (slice 16). Its jack defaults to the drum track (the track whose
    part is drums, or named DRUMS, else the armed one), so a tap on the desk plays the drum track.
    They work in AR from the start, where real surfaces are seen. At a desk: six pads drawn along
    the console's front rail, clicked, or struck with 4 to 9. Pads survive recalibration, since they
    are in the session frame. Touches surface_pads.gd, strike.gd, item_room.gd, jacks.gd (a default
    sink), console_surface.gd (the rail's pads), studio.gd (4 to 9), stations.gd. The suite checks:
    a fingertip dwell and a controller-tip dwell each mark a pad at the tip; a strike through it
    plays its drum with velocity; the default jack records onto the drum track; saved pads reload in
    the session frame after a recalibration; pads mark and play in AR; desktop clicks and 4 to 9.
    The probe checks a guest's pad hit on the host's take. Both sides at 0 failed.
    shots/spatial41.png is the desk's six pads.

    Built. `KitItem` (core/items/kit_item.gd) is the room's shared fixed kind `kit`, last in
    ItemRoom.KINDS: six 6 cm pads (PAD_RADIUS 0.03, PAD_PITCH 0.064, so the row fits the smallest
    desk's armrest) lettered KICK, SNARE, HAT, CLAP, TOM, RIM with their keys 4 to 9 under them,
    stood on the console's armrest under the middle of the strips (`ConsoleSurface.pad_rail`; the
    studio stands it there again whenever the desk moves, grows or is brought, `_follow_kit`). Its
    faces are those six and this machine's marked pads (`KitItem.surface`), so Strike reads them all,
    and a strike's zone is the nearest face's drum. The drums record as GM 36, 38, 42, 39, 47 and 37 on
    the drums' channel and ring Foley's kick, snare, hihat, clap, pad and rim, already on the fast
    path, so ItemVoices plays a take back as those drums. `SurfacePads` (core/music/surface_pads.gd)
    holds up to eight pads in the session frame (its `frame`: RoomAnchor, times
    `XRRig.away_from_home` so a pad stays on its real surface when the play space travels), saved to
    user://pads.cfg and checked as it is read back. MARK on the PADS card (`build_card`, hung off the
    armrest's front edge under the pads, leant back 50 degrees, with CLEAR, which asks once and takes
    them all away on a second press within 3 s, and a line saying what MARK does now; the key says
    MARKING while on) puts the hands to marking: a confident index tip, or a controller's tip with its
    trigger held and holding nothing (`mark_points`), held within 12 mm for 0.6 s (`dwell`; a
    ring at the tip closes in as it fills) marks a pad there, level for a tip that came down from
    within 40 degrees of straight down, otherwise facing back along its approach (`plane_of`), its
    face lifted 6 mm so a tap the real surface stops still crosses it, its letters reading from where
    its marker's eye was, its drum the first no pad has yet. Held still on a pad, the dwell takes it
    away; a ninth is refused with a word. While marking, a tap on a pad steps it to its next drum and
    rings that, which is how a bare hand sets a drum, and spends the point there
    (`SurfacePads.tapped`): a hand left resting on the pad after its tap must move 5 cm away before
    its dwell counts again, so only a fresh landing that struck nothing takes a pad away; a
    controller's stick or the wheel over one
    (`SurfacePads.Pad`, its own affordance, also struck by a click, trigger or pinch aimed at it)
    steps it either way at any time. An instrument may now say where it goes unplugged
    (`InstrumentItem.default_sink`, `Jacks.goes_to`, its jack's card `-> 1 DRUMS (unplugged)`): the
    kit's is the drum track (`KitItem.drum_track`: the track named DRUMS, else the first whose demo
    part is a drum's, kick, snare, hat or overheads), never a bandmate, so a tap on the desk records
    onto the drum track whatever is armed; plugged, it goes where it is plugged. A bandmate's hit on
    the kit is rung from a glove of their ghost (`Presence._on_item_hit`, `KitItem.heard_at`,
    `InstrumentItem.ring_on`), or at the kit with no ghost. In AR, the ItemRoom makes only the kit
    (`ItemRoom.only`, `AR_KINDS`; `spawn` refuses the rest), so the hits' wiring (HitRecorder, Strike,
    Jacks) exists there now, and the pads mark and play from the start. At a desk 4 to 9 strike the
    six (`Studio.strike_desk_pad`), Shift softly, and a click strikes the pad it lands on; no surface
    pads are drawn there and MARK says it is a headset's. The help card has a HELD row, DRUM PADS,
    with both lines, which ran PLAY · HELD on to two pages; the card now shares a run-on section's
    lines out evenly between its pages where they fit, so neither is a page of one row. The probe:
    by 61.28 both halves stand the kit at KIT_HOME; at 61.32 the guest marks a pad by a dwell at
    PAD_AT and comes down through it at DRUM_SPEED to PAD_SONG, the kick; by 61.36 the host checks the
    hit on `kit` from the guest with its drum, song and velocity, and that its kit rings it.

    Honest limits. The probe checks the guest's pad hit reaching the host with its drum and song, not
    a recorded take on the host: a guest's hits are taken down on the guest and sent as its take, as
    every instrument's are. The pads were not tried in a headset: the dwell, the plane from the
    approach and the 6 mm lift are reasoned, not measured on a real knee, and hand tracking at drum
    speeds is the decision's known limit. A pad marked before the room is calibrated moves when it is
    calibrated (it was kept in the uncalibrated frame); one marked after comes back on its surface. In
    VR the session frame is the runtime's own, so a recentred headset carries the pads with it. The
    rail pads sit on the armrest in front of the strips, and only a strike faster than 0.4 m/s down
    through one plays it, so a wrist resting there plays nothing, but a hand slapped down on the
    armrest there would. A strike on a pad while marking always steps its drum, even a hard one meant
    to play it. From the desktop's seat the rail is below the view; the help card and 4 to 9 are how
    a desk finds them. Each hand strikes the kit once per 70 ms (Strike.AGAIN_AFTER), so one hand on
    two pads inside that is one hit. The probe was not run for this slice. A controller marks with
    its trigger held, and the trigger is also its ray's press: one pressed over a control or the kit
    presses that once as it starts marking (a controller then holding a control marks nothing); the
    ray's press is not held off while marking, which wants a headset to judge. The 4 to 9 under each
    rail pad's name are small at the desk's framing; the help card and the kit's card say them too.

    The suite: `_test_a_dwell_marks_a_drum_pad_at_the_tip`: nothing at 0.5 s, a level pad at the
    fingertip at 0.6 s, the first drum; held on, nothing more; a controller's tip in across a crate's
    side marks a pad facing back along it, the next drum; `plane_of` from above, a slant and across;
    a dwell on a pad takes it away and a new one takes the free drum; eight at most and the ninth
    refused; drums in order then round; not marking, a dwell marks nothing; CLEAR asks, then clears;
    MARK at a desk marks nothing. `_test_a_marking_reads_index_tips_and_held_triggers`, through
    `mark_points` on a simulated HandGestures and controller: a confident hand's index tip alone, an
    unconfident hand none, and its dwell marks a pad at the tip; a controller only with its trigger
    held, at its tip, not guessed at, not holding a control, and its dwell marks a pad at the tip; a
    bare hand's controller pose none.
    `_test_a_strike_on_a_pad_plays_its_drum`: six rail faces KICK to RIM; a fingertip through the
    second is the snare and a controller's tip through the last the rim, at their speeds; marked pads
    are faces, struck level and across a crate's side, and not coming out; while marking a tap steps
    the drum and rings the new one, and the hand left resting on it after does not take it away;
    clicks (Shift soft) on the rail and on a marked pad; a nudge steps a marked pad's drum either way; `strike_rail`; heard at once on its sound; the card's words;
    GM 36 38 42 39 47 37 on channel 9, played back as the drums it rang; a bandmate's hit rung from
    where they are. `_test_the_desks_pads_play_the_drum_track`: at a desk the kit stands on the rail
    inside the desk's width; no surface pads; the card's line; the drum track is DRUMS, the jack's
    card says so; a mouse click on the first pad is the kick; 6 the hat, Shift-9 the rim soft;
    recorded onto DRUMS and not the armed track as 36 42 37; plugged into track 5, there; the help
    row. `_test_saved_pads_reload_in_the_session_frame_after_a_recalibration`: kept and saved in the
    session frame; read back after a second calibration, where the new frame puts it; travelled, with
    the play space; bad rows left out. `_test_pads_mark_and_play_in_ar`: AR's room makes only the
    kit, standing on the rail; the card's MARK says MARKING; a dwell marks a pad; MARK stops; a tap on
    it is sent as the kit's kick. 49 checks, 0 failed. With the existing tests for the code it
    touches (the strikes, the fixed drum and its click, the fast path, the hand drums, AR, the note
    pad in AR, the jacks and their beads, percussion recorded, the help card and its pages, the
    stations' lines, the board, the items' shelf counts, personal items, the headset rigs, the seat's
    click audit, every control saying what it is) 573 checks, 0 failed.

    shots/spatial41.png is the desk's six pads on the armrest under the strips, KICK to RIM with 4 to
    9, their jack at the row's left end, and the PADS card hanging under them with MARK and CLEAR
    (`SHOT_CAM "0,-0.75,0.7,-0.05,0.76,0.17"`, `--no-hud`).

42. [x] **Every venue has something to play: the first seven.** The proving idea, #19.
    `VenueInstrument` (core/music/venue_instrument.gd) is a set of fixed pitched InstrumentItems on
    channel 10, as the bells are. Each one's `note_at` is the song's scale (Harmony.at's scale) from
    a low note the venue picks, so the set is in the song's key and retunes at a bracket. They are
    struck by Strike, a click or a controller, recorded, and heard from where they hang, on the fast
    path for the striker (slice 39). The whole set is one jack source, `venue`, with one socket on
    its stand, as decided. The venue supplies `instrument()`: its kind, count, spot, look and sound
    (Foley, synthesised per kind). The first seven: the garden's wind chimes (eight tubes off a
    pergola beam; a brush across rings several), the cabin's icicles along the porch window's eave
    inside the glass, the cave's crystals, the rooftop's railing (each baluster a note), the
    studio's tubular bells on a frame in the live room, the grid's neon bars, and the chalk zone's
    chalk-drawn xylophone. Every venue's instrument is a station (`venue`, area `venue`), so the
    PLAY page and the board find it and its plaque says how. Touches venue_instrument.gd, venue.gd,
    the seven venues, foley.gd, item_room.gd (fixed kinds `venue1`..`venueN`), jacks.gd (a set's one
    source), studio.gd, stations.gd, tools/blender as each needs. The suite checks, over the seven:
    in A minor and after a `[D minor]` bracket each bar rings its scale tone; strikes play and
    record on channel 10 and play back as the pitched voice; plugging `venue` into a track records
    every bar of the set onto it; clearance; each says its title on its plaque. The probe checks a
    guest's strike on the rooftop railing with its song. Both sides at 0 failed.
    shots/spatial42_*.png, one a venue.

    Built. `VenueInstrument` (core/music/venue_instrument.gd) is the set's mount, and its inner
    `Bar` is a fixed pitched InstrumentItem. The room makes eight of them, the fixed kinds `venue1`
    to `venue8` in ItemRoom.KINDS. The studio dresses the first `count` as this venue's set
    (`dress`) and stands them at their homes on the mount (`homes`, through `_item_homes`). A venue
    with no set, the Rig Roulette room among them, puts every bar away.

    What a set is comes from the venue's `instrument()`: kind, count, spot and low note. The rest
    comes from its kind (VenueInstrument.KINDS): title, shape (HANG, STAND or LIE), sizes, look,
    sound and help lines. Bar n rings the n-th tone of the key up from the key's root nearest
    `low`. Harmony's scale is pitch classes, root first, so each tone is taken above the one
    before. In A minor the studio's bells ring A4 to A5; after `[D minor]` they ring D5 to D6.
    Each bar is lettered with the note it rings now, re-read every 0.1 s, so the key change shows
    on the bars and not only in colour.

    The seven sets and where they stand:
    - studio: TUBULAR BELLS, with caps, on a tubular steel frame (posts on rubber-capped feet, a
      rail across their tops)
    - cave: CRYSTALS, faceted and glowing, growing out of a craggy shelf of the cave's own rock
    - grid: NEON BARS, lying across a lit frame, struck from above
    - chalk zone: CHALK XYLOPHONE, drawn in chalk, struck from above
    - garden: WIND CHIMES, off a beam hung from the pergola's top, on the right-hand strip
    - cabin: ICICLES, under a snow-capped eave board inside the left wall's porch window
    - rooftop: THE RAILING, eight brass-collared balusters in the front parapet's run; the
      rooftop leaves its plain balusters out where the tuned run stands

    The studio, cave, grid and chalk zone stand theirs on the back wall between the kit and the
    lattice. The shelf, the bells' frame and the eave are modelled in Blender
    (tools/blender/venue_mounts.py, assets/models/venue_mounts.glb); the shelf takes the cave's rock
    shader, so it is one stone with the wall behind it, and a few small points of crystal grow at its
    ends. A hanging set has a small lamp on an arm out from its rail, soft and aimed back at the
    bars' middle, because the wall behind is often dark. The icicles have none: the moonlit window
    lights them, and even a faint lamp that close blooms clear ice white. The crystals light their
    shelf in their own colour.

    How a set is struck, played and recorded:
    - Strikes: a hand or a controller crosses a bar's faces through Strike. A vertical bar's four
      sides, the railing's three, and a tubular bell's cap all count, so a brush across the row
      rings each in turn. A lying bar is struck on its top. At a desk, a click strikes a bar, and
      Shift-click strikes it softly. Holding the button and dragging across the others brushes
      them (`brush`). A drag begun off the set brushes nothing.
    - Sound: each strike is heard at once on the fast path. It uses the kind's own Foley sound
      (`venue_bar`: chime, icicle, crystal, baluster, tubular, neon, xylophone, each its own
      partials and knock, the neon with a tremolo), pitched from its reference note to the bar's.
      A bandmate hears the hit from the bar's spot, pitched by their song position.
    - Recording: a strike goes into the take on channel 10 and plays back as ItemVoices' pitched
      voice.
    - The jack: the whole set is one source, `venue` (InstrumentItem.jack_source and has_own_jack,
      Jacks.hit). Its one JackSocket hangs beside the plaque. Plugged into a track, every bar is
      recorded onto that track (ItemRoom.source_item finds the set's item for the studio's plug
      checks). A fixed instrument's notes down a cable into a bandmate are anyone's to send
      (Jacks.send_refusal `fixed`), and this now covers the hand drums too.
    - The station: it is the station `venue` (area VENUE, `mounted`). Stations.row_in fills its
      title, help lines, look point and frame from the venue's set, through `Stations.here`, so
      the PLAY · THIS VENUE page, the station board, I and the plaque all name the set.
    - The plaque and the jack stand in front of the set's front (`front_of`): the bars', or the
      mount's where it stands further out. The crystals' shelf lip is SHELF_FRONT out, so their
      plaque is on the shelf's face under the lip, and the jack is beside it.
    - The seats: a desk's seat is the nearest, from 1.1 m out, from which a standing view at the
      room's lens holds the set's top and its plaque's foot (`seat_for`). That is 1.55 m for the
      studio's tubular bells, whose rail is at 1.85 m. A headset's seat is 0.45 m in front of the
      set (`reach`, Stations.seat's `hands`), every bar within a hand's reach.
    - The toast going there says where the set is in words (Stations.where): "TUBULAR BELLS, in
      this venue: ...". Before, it lowered the page's title and said "in the this venue".

    Foley's struck sounds grew to 37, more than the hits helper's 128 slots could hold at four
    takes each. native/keys.c SLOTS is now 256, mirrored as Foley.HIT_SLOTS.

    Limits:
    - The bars are procedural meshes. The chimes' beam and the neon and chalk frames are plain,
      since a timber beam and a lit or drawn frame are what they are meant to be.
    - Played back from a take, every set sounds as ItemVoices' one pitched voice (the handbell's),
      since channel 10 does not carry which set it was. Live, each set rings its own sound.
    - The probe was not run for this slice. Its checks were added: the guest strikes the rooftop
      railing's third baluster to RAILING_SONG, and the host hears it on venue3 with its song and
      rings it on that song's scale tone.

    The suite: `_test_every_venue_has_something_to_play_in_its_key` covers each of the seven: its
    set and mount at its spot, eight fixed pitched bars of the one source, in A minor and after a
    `[D minor]` bracket each bar on its scale tone, the letters following the key, the plaque
    titled, folded and saying how hands play it, the plaque (open and folded) and the jack clear of
    every piece of the set's own mount, and its station row on THIS VENUE's page. The
    other seven venues and the Rig Roulette room have none. `_test_a_venue_bar_rings_struck_brushed_and_clicked`:
    a fingertip into a chime's front, a brush across all eight low to high, a slow drift ringing
    none, a click at 96, Shift at 64, a drag across three more, none from a drag begun off the
    set, the fast path with the chime's sound pitched to its note, else MONITOR, and a neon bar
    struck from above. `_test_venue_strikes_record_on_the_pitched_channel_and_play_back`: eight
    scale tones on channel 10, rendered as the pitched voice and not as tines, and the seven Foley
    sounds, each with its own slots inside HIT_SLOTS, matching keys.c.
    `_test_plugging_the_venue_records_every_bar_onto_a_track`: the set's one jack, the plug allowed
    and said, every bar recorded onto track 5 and not the armed track, a bandmate's strike rung
    where the bar hangs on D minor's tone, and a fixed instrument's cable send allowed. The run
    printed `56 checks, 0 failed`. The venue station also joined `_test_every_venue_stands_every_station_clear`
    (`_check_venue_station`: clear of zones, solids, props, stations and the control room, at the
    floor's edge, every bar in reach from a headset's seat, solid where the room is). The I tour,
    the help card's pages, the stations' areas, the hits helper's slot checks and the shelf counts
    were updated for it. With the existing tests for the code it touches (stations, the help card
    and board, I, the jacks, the hits helper, the hand drums and pads, the fixed drum, the fast
    path, venues' clearances, furniture, mirrors, toys, doors, bells' homes, the seat's click
    audit), those runs printed `1677 checks, 0 failed` and `4803 checks, 0 failed`.

    After review: `_test_going_to_a_station_holds_its_controls_in_view` also holds the set's
    INSTRUMENTS and BACK keys and its jack in view from a desk's seat in every venue. The I tour's
    toasts say each station's area in words, and never "in the this". The headset's travel test
    goes to the studio's bells and lands within reach of them, short of the desk's seat, told "in
    this venue". Its board now lists `venue` too.

    shots/spatial42.png is the studio's tubular bells on the back wall, lettered A4 to A5 with the
    plaque under them (`SHOT_CAM "3.14159,-0.12,2.0,-0.7,1.3,7.0"`, `--no-hud`). The lamp lights
    the tubes' length without blooming, and the frame's posts show. shots/spatial42_cave.png is the
    cave's crystals on their rock shelf, the plaque and the jack on its face
    (`SHOT_CAM "3.14159,-0.3,1.7,-0.7,0.85,7.0"`, `--no-hud --venue cave`).
    shots/spatial42_rooftop.png is the rooftop's railing: eight brass-collared balusters lettered
    A4 to A5 in the parapet, the plaque on them (`SHOT_CAM "0.0,-0.35,1.6,-5.55,0.45,-3.35"`,
    `--no-hud --venue rooftop`).

43. [x] **Every venue has something to play: the other seven.** #19 finished. The loft's steam pipes
    along the brick (struck pipes), the station's hull ribs as a ring of tuned panels, the dome's
    glass vault's ribs (a touch rings the glass), the club's upright piano (its keys struck: the
    scale's notes, the black keys out of the key sunk; one source for the keyboard), the
    greenhouse's terracotta pots on a bench, the stage's row of tuned cymbals and a gong, and the
    desert's ringing stones (a lithophone on a rock shelf). The Rig Roulette room has none and says
    nothing. Touches the seven venues, venue_instrument.gd, foley.gd. The suite checks the same over
    all fourteen, and that every venue in Venue.IDS but the Rig Roulette room has one.
    shots/spatial43_*.png.

    Built. Seven more kinds in VenueInstrument.KINDS, each venue's `instrument()` naming one, so
    all fourteen venues but the Rig Roulette room have a set (the Roulette room still puts every
    bar away and its board says nothing of one). Where each stands, clear of zones, solids, homes
    and stations, at the floor's edge and within reach of its headset seat: the loft's PIPES on
    its right wall (`side_wall_instrument(1.0, 0.9, ...)`: the back wall is the gallery's and
    the harp's), the station's HULL PANELS and the stage's CYMBALS AND GONG, the greenhouse's
    TERRACOTTA POTS and the desert's RINGING STONES on their back walls, the dome's SINGING GLASS
    on its left wall clear of the hatch, and THE PIANO as the club's own upright.

    The KINDS grew fields for the shapes: `plate` (a flat panel, its thickness), `arc` (bars
    round a ring of that radius, each turned to face its middle), `grow` and `gap` (bars as wide
    as they are big, side by side: the pots), `disc` (cymbals, struck on their top), `gong` (one
    more bar behind the row, at the middle: GONG, its own sound), `touch`, `top` (a cap struck
    from above), `keys` and `letter_cap`. Every per-bar size (`bar_length`, `bar_x`,
    `bar_frame`, `half_width`, `front_of`, `top_of`) reads them, so the solid, the plaque and the
    seat check follow each set. The pipes hang from a header with a valve wheel and a tee per
    pipe; the panels stand between two ribs bent round the ring (one smooth mesh in pieces, with a
    line of light), the glass in a steel sill with a rib between panes; the pots stand upside
    down on a potting bench, the cymbals on felts under a gong rack, the stones on a rock shelf
    (tools/blender/venue_mounts.py: PipeHeader, PipeValve, PipeTee, PotBench, GongRack,
    StoneShelf). The gong's rack gets the hanging sets' lamp, over its top bar.

    The piano: the club's upright (tools/blender/club.py and club_showtime.py) leaves its middle
    octave's keys out (`GAP`, white keys 26 to 33 and the black keys between), and the eight bars
    lie there as keys (`PIANO_KEY` wide, notched at the head where a black key sits), lettered on
    their heads with the note and not its octave (`octave` false, at a 15 mm cap: `C#4` at a size
    read from the desk is wider than a key; the hover readout and the plaque still say it). Black keys out of the song's key are sunk: `pattern()` says, slot by slot, where
    two neighbouring tones are more than a semitone apart, and the mount's `Sunk%d` keys show
    there, a hair proud of the key bed, repatterned every 0.1 s, so a key change moves them. The
    keyboard is the one `venue` source. The case stands where each club's piano stood, and in the
    speakeasy, which had none, against the back wall beside the stage (`piano_case()`); the
    after-hours bass moved to z -0.4 and the showtime bench along by 0.75 m, so the seat fits.

    The glass rings at a touch: InstrumentItem gained `strike_least()` and `velocity_of()`, which
    Strike now asks; a pane's least is 0.08 m/s (STRIKE_MIN for everything else) and a touch
    plays soft to firm (18 to 40). Foley.VENUE_BAR_SOUNDS gained pipe, panel, glass, piano,
    terracotta, crotale, gong (4 s, beating) and stone: 44 kinds, 176 of HIT_SLOTS's 256.

    Tests (tests/run_tests.gd): VENUE_SETS lists all fourteen, so
    `_test_every_venue_has_something_to_play_in_its_key` checks the other seven as the first
    (pitched, in the key and retuned at a bracket, lettered, its plaque and jack clear of its
    mount, one station on the venue's page), plus that every venue in Venue.IDS has one and the
    Roulette room has none; its Foley check now counts 15 distinct sounds.
    `_test_the_other_seven_are_struck_as_they_are_made` strikes each as made: a pipe's tube, a
    panel's face, a pane at a touch too slow for a bar, a cymbal's top, the gong's face, a pot's
    base, a stone's top, a key. `_test_the_pianos_black_keys_out_of_the_key_are_sunk` checks
    `pattern()` for A minor `[t,t,f,t,t,f,t,t,t]` and A major `[f,t,t,f,t,t,t,f,t]`, the keys
    lettered A3 to A4 in A major, the sunk keys shown where the pattern says and not struck, and
    the speakeasy's piano. Also fixed: the hull rib in eight pieces (one box round the whole bend
    held the plaque), the hanging sets' lamp arm a hair over its can, slice 42's chime caps and
    neon leg glow off their tubes' and legs' planes. After review: the hull's struts stood in its
    end panels (centred inside the outermost panels' edges round the ring); its ribs now run out to
    6 cm past the outermost panels' edges along the arc and the struts stand a centimetre clear of
    them, which `_test_the_other_seven_are_struck_as_they_are_made` checks (each strut wholly to one
    side of every panel across its width; the z-fight test misses it, the faces crossing rather than
    sharing a plane). KitItem's pads (slice 41's) stood on their bezels' plane and the bezels
    overlapped each other on theirs: each bezel is now a millimetre short of the next and each pad's
    foot a millimetre up inside its bezel.

    shots/spatial43_club_piano.png is the club's upright, the lettered octave in its keyboard with
    the sunk black keys (`SHOT_CAM "1.5708,-0.45,1.2,-4.95,0.72,0.0"`, `--no-hud --venue club`).
    shots/spatial43_station_panels.png is the hull's ring of panels, its struts clear of the end
    panels (`SHOT_CAM "3.14159,-0.25,2.0,-0.7,0.9,6.9"`, `--no-hud --venue station`).
    shots/spatial43_greenhouse_pots.png is the eight pots lettered A4 to A5 on the potting bench
    (`SHOT_CAM "3.14159,-0.3,1.6,-0.7,0.85,6.9"`, `--no-hud --venue greenhouse`).

44. [x] **Generative weather, and the cave's drips.** The proving idea, #20. `Weather`
    (core/music/weather.gd) runs in the weather arrangements: the loft's Thunderstorm (rain on the
    tall windows), the greenhouse's Rain (on the glass roof) and the cabin's Snowy night (snow on
    the big window, sparse and soft). The cave gets the same as `drips`: a drop off the ceiling into
    its pools every few bars, so #31's example (the cave's drips into a trigger) has a source. Drops
    are a function of the song clock as decided. In each sixteenth, hash(bar, step, venue seed) says
    whether a drop lands and where. Each drop plays a scale note, by its height on the glass (or the
    pool it falls in), softly. Density comes from the arrangement, with the storm's gusts rising and
    falling over eight bars. The drops are drawn where they land and run, and the venue's rain is
    given the hit list. A switch on the sill (station `weather`, a room row): OFF (the drops fall
    silent), or LISTEN (heard by everyone, from the glass). Its jack, `weather` (or `drips`), into a
    track records its notes onto it (HitRecorder's jacked take), and that is independent of any
    modular cable from it (slice 53). Everyone hears the same drops, since everyone has the same
    clock and seed, so nothing else crosses the wire. Touches weather.gd, loft_venue.gd,
    greenhouse_venue.gd, cabin_venue.gd, cave_venue.gd, jacks.gd (a source that is not an item),
    hit_recorder.gd, session.gd (the switch's row), studio.gd, stations.gd. The suite checks: the
    same notes for the same span from two Weather instances; a bracket retunes; density by
    arrangement; the cave's drips are sparse and deterministic; OFF is silent; the jack records
    exactly the scheduled notes; the drops are drawn still at motion 0. The probe checks that both
    sides schedule the same drops over one bar of the Thunderstorm, and that a guest's switch
    reaches the host's row. Both sides at 0 failed. shots/spatial44.png is the loft's window in
    rain.

    Built. `Weather` (core/music/weather.gd, a Node3D the studio stands in the venue at
    `Venue.weather_spot`) reads its arrangement from `Venue.weather()`, filled out by kind
    (`KINDS`: storm, rain, snow and drips; title, density, gust, velocity, sound, run and life).
    `Weather.drops(spec, seed, state, from, to)` is the schedule: a pure function of the song clock.
    For each sixteenth in the span, `mix(bar, step, seed)` says whether a drop lands against
    `density(spec, bar)` and where it lands (u and v on the glass). The storm runs 0.08 to 0.42 a
    sixteenth and gusts over `GUST_BARS` 8, the rain is a steady 0.16 and the snow 0.045. The drips
    get one candidate a bar (`mix(bar, 0xD1, seed)`) and land with chance 0.35, into one of four
    pools. The seed is an FNV-1a hash of the venue id, 24 bits. The note is
    `VenueInstrument.scale_tone(Harmony.at(...), low, degree)`: its height on the glass picks one
    of 8 tones, its pool one of the scale's 1st, 3rd, 5th and 8th degrees. Soft velocities
    throughout.

    Where each stands, clear of zones, solids, homes and stations:
    - the loft's storm on the sill of the left wall's second window bay (z 1.25);
    - the greenhouse's rain on an iron post at its left edge, the glass just past the bed;
    - the cabin's snow on the sill of the right wall's first bay (z 0.3), not on the big window:
      that one stands behind the synth zone;
    - the cave's drips on a post at the left edge among four pools of standing water (CaveVenue's
      `POOLS`, `_fill_the_pools`) in the grotto and on the lake. None in the lava tube.

    The switch (`Weather.Switch`, a ControlAffordance) is a brass lever on an iron plate, with
    LISTEN or OFF lettered on a legend leaning out from it (words, not a colour). It is the room's
    row `weather` (Session.ROOM_VERBS `[TYPE_BOOL]`, `Studio.room_state`, `apply_room`). It starts
    OFF and is kept across a change of venue. A guest predicts its press and asks for it, as the
    sampler's REC does, and the host's room is the truth. A notice says what LISTEN and OFF do.
    The station `weather` (THE WEATHER, area VENUE, mounted) is a row `Stations.row_in` fills from
    `Weather.row_for`. Its plaque (folded) hangs under the sill or the post's cap, and its jack is
    beside the switch.

    The jack: `weather` and `drips` are `Jack.WORLD` sources, not items. `Jacks.sinks` offers
    unplugged and the tracks only, and `plug_refusal` refuses a bandmate ("the weather goes onto a
    track: everyone hears it already"). On the host, every drop that lands while the song records
    goes onto the plugged track, heard or not: `HitRecorder.note`, the jacked take, on the pitched
    channel. A heard drop is a Foley emitter where it landed, pitched to its note
    (`Foley.weather_drop`: rain_glass, snow and drip, synthesised, each with a glide and a
    lowpass). The drawing is two MultiMeshes, beads and rings:
    - on glass, a bead runs down the pane (`run`) and a ring stands in the glass's plane;
    - a drip is drawn falling from FALL_FROM before it lands, and a ring spreads on its pool;
    - at Ergonomics motion 0 a bead stays where it landed and fades, a ring keeps one size, and
      nothing falls.

    The venue's own particle rain is left as it was: still decoration, not given the hit list.
    Also: `--play` is a new launch switch (scenes/bootstrap.gd) that starts the transport after
    `--at`, for the shots.

    Tests (tests/run_tests.gd):
    - `_test_the_weather_falls_the_same_from_the_same_clock`: the arrangements that have weather
      and those that have none; two Weathers at 60 and 23 fps land the same drops as the schedule
      says; scale tones in A minor, and in D minor after the bracket; density by arrangement and
      the gust; the drips sparse, deterministic, and changed by another seed.
    - `_test_the_weathers_switch_is_the_rooms_and_off_is_silent`: OFF lands and draws drops but
      rings none; LISTEN rings each; the room verb; a guest's ask on the host, and the host's room
      on a guest; kept across a change of venue.
    - `_test_the_weathers_jack_records_exactly_the_scheduled_drops`: sinks and refusals; the
      socket's notice; recording while OFF takes exactly the scheduled drops onto track 5 at their
      song positions; unplugged, nothing is taken.
    - `_test_the_drops_are_drawn_still_at_motion_0`.
    - The station clearance, in-view and venue-instrument tests take in the weather's station.

    "31 checks, 0 failed" for the four new tests. "5525 checks, 0 failed", "108 checks, 0 failed"
    and "5211 checks, 0 failed" for the existing tests of what this touches: stations, jacks,
    HitRecorder, the sampler, venue instruments and solids. tools/probe/session_probe.gd: at 61.28
    the host schedules the Thunderstorm's bar WEATHER_BAR (5, the top of its gust) and publishes
    it (`weather_probe`). At 61.3 the guest presses the switch, and by 61.34 it checks the room's
    row is LISTEN and that its own schedule of the bar is the host's, drop for drop. At 61.36 the
    host checks the ask arrived. The probe was not run in this slice (checkpoints run it).

    shots/spatial44.png is the loft's window in the storm: beads and rings on the panes, the OFF
    switch on the sill, the THUNDERSTORM plaque (`SHOT_CAM "1.5708,0.0,2.7,-7.1,1.75,1.25"`,
    `SHOT_ARGS "--no-hud --venue loft:2 --at 5 --play"`, frames 210/216).
    shots/spatial44_cave.png is the grotto's post and pools, a drip's ring on the second pool
    (`SHOT_CAM "1.5708,-0.5,3.0,-7.5,0.2,1.3"`, `SHOT_ARGS "--no-hud --venue cave:0 --at 4 --play"`,
    frames 120/126).

45. [x] **A looper, by hand: loops and layers.** The proving idea, #21, first half. `Looper`
    (core/music/looper.gd, station `looper`, zone `drums`, a pad on a stand at the riser's front
    corner, itself a fixed instrument struck through Strike). Slap the pad (any strike: a hand, a
    controller, a click; never a foot) to arm. Who is recording and from which bar is a room row
    (`looper` [peer, from_bar, length]), so everyone's pad shows it, and a slap by another player
    while it is armed or recording is refused with `ADA is looping`. Recording starts at the next
    bar, after a bar's count shown as dots, and lasts its LENGTH: 1, 2, 4 or 8 bars by its nudge, or
    the loop range if one is set. With the transport stopped, a slap starts it (`transport_play`)
    and the count is the first bar played. It takes everything this player plays: their keys from
    every source, and their hits. Slap again while it plays to stack another layer from the loop's
    start. Each layer is a MIDI item on a track of its own in a LOOPER folder (`ADA LOOP 1`,
    add_track and insert_midi_take), and its hits play back as hits (slice 16). The first layer sets
    the transport's loop range to its span and turns looping on. The pad's screen shows bars, beats,
    and REC or PLAY by shape. Anyone can use the looper, one at a time. Each player's layers are
    their own tracks, named for them. Touches looper.gd, guest_midi.gd (a tap on what this player
    sends), hit_recorder.gd, session.gd (the `looper` row), studio.gd, stations.gd. The suite
    checks: a slap records from the next bar for LENGTH bars onto a new LOOP track; a slap with the
    transport stopped starts it and records from the bar after the count; a second slap stacks; the
    loop range and looping; another player's slap while armed is refused with the reason; a guest's
    layer lands on the host's tracks; hits and keys in one layer, and the hits play back as drums.
    The probe checks a guest's two-bar layer. Both sides at 0 failed. shots/spatial45.png is the pad
    recording.

    Built. `Looper` (core/music/looper.gd, a Node3D the studio stands in the venue at
    `Venue.looper_spot`: `looper_at`, the drum ring's frame moved to its front corner, `LOOPER_CORNER`
    0.98 m) is a drummer's sample pad on a snare stand, modelled in Blender (tools/blender/looper.py,
    assets/models/looper.glb): three splayed legs, a pole, a tilt clamp, and a dark case tipped 0.4
    rad toward the player, its rubber pad (`Looper.Pad`, a fixed InstrumentItem in Strike's group,
    lettered SLAP TO LOOP, no jack) inside a raised rim, and a panel leant back behind it with the
    screen on its left and the LENGTH key (`Looper.LengthKey`: a press steps 1, 2, 4, 8; the wheel
    nudges) on its right. Its foot is a `ZoneKit.solids` entry marked with its station, so the walker
    and the trolleys keep off it and its own clearance check leaves it out. The station `looper`
    (LOOPER, area LIVE, zone `drums`, mounted) has its plaque, folded, on a slim arm off the pole
    (`Looper.PLAQUE`, `PLAQUE_ARM`): in front of the case and below it, leant back `PLAQUE_TILT` 0.5
    rad like the hand drums' so it reads from above, and 0.5 m wide so its hands line takes five
    lines. All of it is in front of the case's front face, so the case hides none of it from an eye
    over the pad, standing or at the desk's camera; the station's frame's foot is its plate's lowest
    point opened (`PLAQUE_FOOT`). (It first hung on the pole right under the case, where the case
    hid its title row and clipped its keys from any standing eye.)

    The room's row `looper` [peer, from_bar, bars] (Session.ROOM_VERBS `[TYPE_INT, TYPE_INT]`, the
    ask [from_bar, bars]; `Studio.room_state`, `apply_room`). A slap is planned where it is heard
    (`Looper.plan`): the loop's own bars when a loop is set, else the bar after the one heard for
    LENGTH bars, or -1 with the transport stopped. The host answers it (`Looper.answer`):
    - another player's row refuses it, said as "ADA is looping: one player at a time", on the
      slapper's own machine before anything is asked and by the host if asked;
    - with the transport stopped it seeks to the start of the bar the playhead is in and starts it,
      so that bar is the count (with a loop set, the bar before the loop);
    - a bar more than two past the host's own is replaced by the next one;
    - with no loop set it sets the loop range to the layer's span and turns looping on, so the
      playhead goes round at its end and the player hears the layer at once.
    A slap during one's own count calls it off; during REC it says when the layer ends. A guest
    predicts the row and the host's room is the truth. Whoever was looping leaving clears it.

    The layer is taken down on the machine of whoever plays it, by its heard clock (`follow`): COUNT
    until the song arrives at the span's first bar (crossing it, or the loop going round to it), REC
    until its end, DONE. A count first heard playing less than WRAP (0.25 s) past its first bar (the
    frame after a stall) begins at once rather than a whole pass later. It takes their keys from
    GuestMidi's new `sends` signal (every key source that goes through GuestMidi) and their hits
    from the studio's `items.played`, as HitRecorder takes them (snapped, the zone's note, channel
    9, so they play back as drums through ItemVoices). A key a hair (EARLY, 0.08 s) before the first
    bar is its downbeat; one played in the count is not taken. The layer goes to the host
    (`looper_layer` [start, end, notes], `[TYPE_FLOAT, TYPE_FLOAT, TYPE_ARRAY]`), which writes it only
    while the row is that player's (`Looper.write_layer`: a LOOPER folder at the end of the project
    the first time, then `ADA LOOP n` added after its last track, moved into it, and one MIDI item
    over the span), says where it went, and clears the row. The span is the row's own bars as the
    host has them (`span_of`), not the start and end the layer came with, and only the notes begun
    inside them are taken (`Looper.inside`, each let go by the span's end), so a guest's layer lands
    where the room says it was recorded. A layer with nothing in it makes no track.

    The screen says it in words and shapes, never by colour: REC beside a disc, PLAY beside a
    triangle, READY beside a square, COUNT with the beats left as large dots; who and which bar
    (`ADA · BAR 1 OF 2`); and the beat as a row of large and small dots. The pad's card and hint say
    the same and how to slap it at a desk (a click) or by hand. Also: `--slap` is a new launch switch
    (scenes/bootstrap.gd) that slaps the pad after `--play`, for the shots.

    Limits, for later slices: a layer is several undo steps (the folder, the track, its move and its
    item), not one; LENGTH is each player's own, not a room row; a loop range off the bar lines is
    taken to its nearest bars; the slap itself is not heard by bandmates (the pad is not a room item);
    on Reaper with more of the project than the bank holds, the new tracks are not in the host's
    mirror when write_layer looks them up, so the item is not placed; not tried in a headset; the
    station board's stand is hidden from the seat by the board's face (nine rows in the live room
    now), so a desk player walks to it to push the board.

    Tests (tests/run_tests.gd):
    - `_test_a_slap_loops_the_next_bars_onto_a_track_of_your_own`: where it stands; its plaque,
      folded and opened, all in front of the case's front face and under the deck, above the riser,
      held by its arm, its lowest point the station's frame's foot; READY; slapped in bar 3, armed
      from bar 4 for 2 bars, COUNT with the beats left, the first layer's loop range;
      keys and a djembe slap in the span (not the key in the count) onto ADA LOOP 1 in a new LOOPER
      folder, the slap on the drums' channel and played back as a conga; PLAY by its triangle; a
      second slap counts the rest of the pass and stacks ADA LOOP 2 after it in the folder.
    - `_test_a_slap_with_the_transport_stopped_starts_it_and_counts_a_bar`: the transport started
      from the bar's start, a whole bar's count, a key a hair early is the downbeat; stopped in a
      count, it is called off; armed for a bar just passed when first heard, it records at once.
    - `_test_one_player_loops_at_a_time_and_a_guests_layer_lands_on_the_host`: refusals on the host
      and on the guest; a layer from the wrong player is not written; leaving clears the row; a
      guest's layer is taken down by its own heard clock and lands on the host as GRACE LOOP 1,
      over her row's bars (6 s to 10 s) though sent with another span, a note sent from outside
      them dropped.
    - The station listing, help card, station board, walk, headset travel, clearance, in-view and
      seat-audit tests take in the looper. The seat audit leaves out the station board's stand,
      whose face, nine rows in the live room now, hides it from the seat (its rows are audited).

    "34 checks, 0 failed" for the three new tests (after the plaque and the layer's span were fixed;
    with the stations' clearance, in-view, seat-audit, headset-travel and focus-fit tests, 1747
    checks, 0 failed). "128 checks, 0 failed" and "5406 checks, 0
    failed" for the existing tests of what this touches: the stations, the help card, the board,
    walking and travelling to stations, the seat audit, the hand drums and their recording, the
    clearance, in-view and activity-room tests. tools/probe/session_probe.gd: at 61.34 the guest asks
    for the looper at a far bar; the host answers as the studio does (`Looper.answer`) and by 61.36
    the guest checks the row is its own, from the next bar, for 2 bars, and sends a key and a hit
    over that span. By 61.38 the host checks the asks arrived and the layer is "<GUEST> LOOP 1" in
    the LOOPER folder with both notes over the span, and the row clear; by 61.39 the guest's mirror
    has the track in the folder. The host takes the tracks, loop and transport back at 61.395. The
    probe was not run in this slice (checkpoints run it).

    shots/spatial45.png is the pad recording from a standing player's eye (about 1.58 m up, 0.6 m in
    front): REC by its disc, `JSABELLA · BAR 1 OF 2`, the beat's dots, THE LOOP 2 BARS on its key,
    the folded plaque in front of the case with its title (`LOOPER +`) and its INSTRUMENTS and BACK
    keys whole, and the hand drums behind it on the riser (`SHOT_CAM
    "3.1416,-0.75,0.85,-1.6,1.0,4.85"`, `SHOT_ARGS "--no-hud --at 3 --play --slap"`, frames 240/246).
    The screen's glass is a softer dark (roughness 0.45), so a lamp's highlight does not wash out
    REC and the who-and-bar line from the desk's side either.

46. [x] **The looper's rings.** #21 finished. Each layer is a ring stacked round the looper's post,
    on its stand, not round the player: 0.25 m across, the first at 1.0 m up and each next 6 cm
    above, lettered with its player and number (`ADA 2`). Its notch passes the front at the loop's
    start, a small turn within the stand, and it steps a beat at a time at motion 0. A ring is taken
    only by a deliberate grab (a grip or a pinch with the hand inside its band), never by a brush.
    Grabbing a ring mutes its track (the ring goes dim and dashed), and grabbing it again unmutes.
    Pulling it more than 0.4 m away deletes the layer (remove_track, one undo step), and the ring
    fades. A ring's brightness follows its track's level (slice 21's beads). Everyone sees the same
    stand. At a desk: the pad's screen lists `ADA LOOP 2` with MUTE and X keys, and a click on a
    ring mutes it. Touches looper.gd, looper_rings.gd (new), studio.gd. The suite checks: a grab
    mutes and unmutes; a brush through a ring does nothing; a pull deletes; rings follow the layers;
    the rings stay inside the stand's footprint; the desktop's keys. The probe checks a guest's ring
    pull deleting its track on the host. Both sides at 0 failed. shots/spatial46.png is three rings
    on the stand.

    Built. `LooperRings` (core/music/looper_rings.gd) is the looper's child (`Looper.rings`), made in
    its `_ready`, in its frame. Its rings are drawn from the project's LOOPER folder
    (`LooperRings.layers`: each track in it, in order, with its first item's start and length), so
    every machine's mirror of the host's mix stands the same rings and nothing new crosses the wire.
    A ring (`LooperRings.Ring`, a ControlAffordance) is a tube 0.25 m across (`RADIUS` 0.119 to its
    middle, `TUBE` 6 mm) round a post at `POST` (0.075 m behind the stand's middle), the first at
    `FIRST` 1.0 m over the stand's feet and each next `STEP` 6 cm above, at most `MOST` 8. The post
    is three steel rods: up from the case's back behind the screen and the list, over to the post's
    foot, and up to `POST_TOP`, so nothing of it stands in front of the screen. Every ring and the
    post stay inside the stand's footprint (Looper.STAND_FOOT). Each ring is lettered beside it on
    its left, the open floor's side (`label_of`: `ADA LOOP 2` is `ADA 2`), out of the way of the
    tube's front and its notch. Its notch, a tab on the tube, passes the front at its layer's start
    and goes round once a pass (`turn_of`); at Ergonomics motion 0 it steps a beat at a time. Its
    lamp is unshaded, `SignalBeads.glow` of its track's `SignalBeads.track_level`, following it with
    the beads' ATTACK and RELEASE. A muted ring is drawn in `DASHES` 12 dashes at `MUTED_GLOW` 0.4 of
    the beads' colour, dimmer than a silent heard ring, and lettered `ADA 2  MUTED`: by shape and
    word, not colour.

    The rings read this player's hands themselves each physics frame (`hands_in`: a tracked bare
    hand's palm while closed or its pinch point, a controller's grip point with its grip or its
    trigger in; a hand carrying something or playing fingertips is busy; a fingertip's poke is not a
    hand here). `step_hands` takes a ring only on a hand's closing edge with its point inside that
    ring's band (`band_of`: within `BAND` 5 cm of the tube's middle and half a STEP of its height).
    A grab opens one edit (`DAW.open_edit("ADA LOOP 2: ring")`) and toggles the track's mute
    (`toggle`); the held ring follows the hand; past `PULL` 0.4 m from where it was taken the layer
    is deleted (`delete`: DAW.remove_track) and the ring fades over `FADE` 0.5 s; opening the hand,
    or losing it for `LOST` 0.5 s, closes the edit and puts the ring back. So a grab's mute is one
    undo step, and a pull's mute and delete are one together, which an undo takes back to the layer
    as it was before the grab. The ray's press (XRInteractor), a fingertip's touch (PokeInteractor)
    and a dwell take nothing: `Ring._on_grab_begin` lets them go at once. A click from anything
    else, the desk's mouse, toggles the mute. A guest's writes are DAW intents like every edit, and
    its ring shows the mute (`Ring.predict`) or its going (`_gone`) at once, for `PREDICT_MS` 1.5 s
    or until the host's mix says so; a delete the mix has taken is forgotten, so an undo brings the
    ring back. What a grab, a click or a pull did is said by a toast (`told`, which the studio sends
    to Session.notice).

    At a desk: the LAYERS list (`LooperRings.LayerList`, `list_frame`) is a second pane on from the
    screen's top edge, leant back as it is, across the screen and the LENGTH key. Its header says
    `LAYERS · 2`, `LAYERS: NONE YET · SLAP TO LOOP`, or `LAYERS 2-4 OF 5 · WHEEL SCROLLS`; each of
    its `ROWS` 3 rows is a layer's name (`GRACE LOOP 1 · MUTED` while muted) with a MUTE key, which
    says MUTED and sits sunk while it is, and an X key that deletes it (one undo step). The wheel
    on a key scrolls the list. Rows with no layer are hidden, keys and all. The station's frame's
    top is the last ring the post could stand (`LooperRings.STACK_TOP`, 1.426 m over the stand's
    feet), its foot the plaque's opened, and its seat stands 1.7 m back (further than `SEAT`), so
    from it a desk sees the whole stack of rings turn, shine and go dashed, under the toast, with the
    list, the pad and the plaque; where the room brings the seat in (the studio's "Through the
    glass", 1.4 m) the top wins and the rings and the plaque's keys are still in view. A delete's
    toast says Ctrl+Z at a desk, and the tape deck's UNDO or a notch back on its reel's crank after a
    pull or in a headset. The pad's card, the rings' and keys' cards and
    the station's desk and hands lines say how; the hands line made the plaque two lines taller, so
    it hangs 4 cm lower along its lean (`Looper.PLAQUE`) to keep its title in front of the case, and
    its foot is `PLAQUE_FOOT` (0, 0.112, 0.402). Also: `--rings N` is a new launch switch
    (scenes/bootstrap.gd), N layers on the looper with the second muted and the loop set, for the
    shots.

    Limits, for later slices: rings stand for the first MOST layers (the list has every one); on
    Reaper the mute is an OSC write and Reaper's own undo point, so a pull there is two steps; a
    ring's brightness on a guest follows its mirror's meters, as the beads do; not tried in a
    headset.

    Tests (tests/run_tests.gd):
    - `_test_a_grab_on_a_looper_ring_mutes_it_and_a_pull_deletes_it`: three layers stand three rings
      lettered ADA 1, ADA 2, GRACE 1 at 1.0 m and 6 cm apart, 0.25 m across, every ring there could
      be and the post inside the footprint, over the list's top; an open hand brushing through,
      a fist carried in, a busy hand, a poke and the ray take nothing; a hand closing in the band
      mutes (dashed, dim, MUTED), one step; again unmutes; a 0.3 m pull follows the hand and goes
      back; past 0.4 m deletes in one step with a toast, the ring fades over half a second, and one
      undo brings the layer and its ring back; the rings follow layers taken out and made.
    - `_test_a_looper_ring_turns_with_its_layer_and_shines_with_its_level`: the turn at a pass's
      start, a quarter and round again, a beat a step at motion 0, the notch at the front at the
      start and a quarter round after a quarter; brighter with the level, as a bead at that level.
    - `_test_the_looper_layers_list_mutes_and_deletes_at_a_desk`: the list's header, names, MUTE and
      X; from the looper's seat every ring the post could stand (top, front and lettering), the pad,
      the plaque's keys and its foot are in view under the toast, and a click on screen reaches both
      rows' keys and each ring's front; a click on a
      ring mutes and unmutes with a toast; MUTE mutes GRACE's; X deletes in one step; five layers
      scroll by the wheel; the cards and the station's lines.
    - `_test_a_guests_ring_pull_asks_the_host`: a guest's grab and pull are the intents open_edit,
      set_track_mute, remove_track and close_edit, and its ring is shown muted and gone at once.
    - The first looper test takes the plaque's new place and foot.
    - `_test_going_to_a_station_holds_its_controls_in_view` takes in the looper's every ring, its pad
      and its plaque's keys, in every venue.

    "32 checks, 0 failed" for the four new tests. "1793 checks, 0 failed" for them and the existing
    tests of what this touches: the three looper tests, the station listing, the help card's pages and keys,
    the station board, walking and travelling to stations, the clearance, in-view and seat-audit
    tests. tools/probe/session_probe.gd: at 61.40 the guest stands rings of its own from its mirror,
    closes a hand on "<GUEST> LOOP 1"'s ring and pulls it 0.5 m off; by 61.43 the host's project no
    longer has the track, the LOOPER folder left, on the built-in engine one step named
    `<GUEST> LOOP 1: ring`; by 61.44 the guest's mirror no longer has it. The host takes the rest back
    at 61.44 and ends the session at 61.45 (from 61.4). The probe was not run in this slice
    (checkpoints run it).

    shots/spatial46.png is three rings on the stand from a standing player's eye: ADA 1 and
    JSABELLA 1 lit, GRACE 1 dashed and dim and lettered MUTED, their notches, the post, and the
    LAYERS list over the screen with MUTE, MUTED and X (`SHOT_CAM "3.1416,-0.32,1.05,-1.6,1.22,4.8"`,
    `SHOT_ARGS "--no-hud --rings 3 --at 3 --play"`, frames 90/96).

47. [x] **A music-box sequencer.** The proving idea, #15. `MusicBox` (core/music/music_box.gd,
    station `music_box`, free-standing on a plinth of its own beside the bell stand at
    `Venue.music_box_spot`, since the synth zone has no room left) is a brass cylinder of 16 steps
    by 8 rows turning past a comb. The rows are the key's scale up from the box's root (or
    chromatic, by its switch). It turns with the song: one turn is its LENGTH of 1, 2 or 4 bars. Its
    pegs are the notes of one MIDI item on its TRACK (its tag's nudge picks the track, and a new
    MUSIC BOX track is the default), from the loop's or the playhead's bar. TRACK, LENGTH, root and
    SCALE are a room row (`music_box`), so every player sees the same pegs. Pressing a cell adds a
    peg (DAW.insert_note at the step, one undo step), and pressing a peg takes it out (delete_note).
    A drag along a row adds a run of pegs inside one edit. The pegs are read back from the item, so
    a note moved in the 2D roll moves its peg, and one off the rows (after a key change) is drawn at
    its nearest row with a mark. It sounds as the track plays: ordinary MIDI. The comb's teeth flick
    as pegs pass, and stand at motion 0. A desk clicks cells, and the wheel turns the view. Touches
    music_box.gd, venue.gd (the plinth's place), session.gd (the row), studio.gd, stations.gd,
    tools/blender/music_box.py. The suite checks: a peg at row 3, step 5 inserts that pitch at that
    time; pressing it removes it; a drag is one undo step; an edit elsewhere moves its peg; a key
    change's mark; the cylinder's angle at song positions; a guest's LENGTH change reaches the
    host's row; the plinth clears its neighbours (the free-standing checks). The probe checks a
    guest's peg in the host's item. Both sides at 0 failed. shots/spatial47.png is the box with a
    pattern.

    Built. `MusicBox` (core/music/music_box.gd) is a brass cylinder of `STEPS` 16 steps round by
    `ROWS` 8 rows across (`ROW_PITCH` 4 cm, row 0 the lowest at the left, as on a keyboard), on a
    walnut case on a plinth of its own (tools/blender/music_box.py, assets/models/music_box.glb: the
    plinth, the base board at `DECK_Y` 0.88 m, two brass cheeks holding the axle, the comb's steel
    block and plate behind the cylinder, a back wall and the lid hinged open behind with its felt
    toward the player). The cylinder, its pegs, the comb's teeth, the row names and the keys are
    MusicBox's own. Station `music_box` (LIVE, free-standing), so a trolley in a studio
    (`Venue.WHEELED`, `Studio.LIVE_TROLLEYS`), gone to by name and pushed about like the harp.

    Where it stands is not where the slice said. Beside the bell stand its far side is in the
    lattice's zone in the studio, so `Venue.default_music_box_spot` stands it on the harp's other
    side, away from the bells, its back in line with the harp's plinth and `MUSIC_BOX_GAP` (0.12 m)
    clear of it: the harp between the bells and the box. The loft's aisle has no room beside the harp
    on the lattice's side, so `LoftVenue.default_music_box_spot` stands it `BOX_UP_AISLE` 1.3 m up
    the aisle toward the desk, its back a hand's width off the lattice, facing across the aisle to
    the riser. None in the Rig Roulette room (no zones).

    The pattern is one MIDI item. Its pegs are the notes of the first MIDI item on its TRACK under its
    bars (`item_of`), read back every frame (`pegs_of`), never kept: a note moved in the roll moves
    its peg, an undo takes it back, every player's box shows the host's mix. Its bars (`span_of`) are
    the loop's from its first bar, LENGTH a page; else the LENGTH-bar page the playhead is in. Its
    rows (`rows_of`) are the scale of the song's key at its first bar (Harmony.at) up from the tonic
    put in A3 to G#4, moved by ROOT, or semitones (SCALE chromatic). A note on no row is drawn at its
    nearest row with a mark, by shape: the peg leans toward its pitch and wears a collar. Pressing a
    cell is DAW.insert_note at that step, a step long; pressing a peg is delete_note; each in an edit
    of its own (`DAW.open_edit("MUSIC BOX: pegs")`), so one undo step. A drag along a row
    (`extend_gesture`, the short way round) changes every cell it passes, as its first was: a run in,
    or a run out where it began on a peg, one edit. The first peg where there is no MUSIC BOX track
    asks for one at the end of the project (add_track), and with no item it asks for the item with
    the pegs so far as its notes (insert_midi_take); the cells pressed meanwhile wait in a queue
    (`flush`), so a drag begun on an empty box is still one undo step. A guest waits for its mirror
    to show what it sent before it sends more, so the indices it names are the host's. A cell past
    the end of an item shorter than the box's bars is refused with a toast ("Step 12 is past the end
    of MUSIC BOX's item: lengthen it on the timeline."), as is a locked item.

    It turns with the song (`turn_of`): the sounding step passes under the comb at the top, the steps
    to come on the front. A peg reaching the comb flicks its row's tooth (`FLICK` 0.35 rad, dying
    over `FLICK_TIME` 0.12 s). At Ergonomics motion 0 the cylinder steps a step at a time and the
    teeth stand. It sounds as the track plays, as any MIDI does.

    The keys TRACK, LENGTH (1, 2, 4 bars), ROOT and SCALE (`SettingKey`, on the base board's front,
    tipped up toward the player, each lettered with its value: `LENGTH 1 BAR`, `SCALE A MINOR`) are
    the room's row `music_box` [track, length, root, chromatic] (Session.ROOM_VERBS), cleaned on the
    host (`MusicBox.clean`: a length not in LENGTHS or a track not in the project is refused) and
    predicted on a guest (`Studio._on_music_box_asked`, `_set_music_box`, `apply_room`). TRACK 0 is
    the MUSIC BOX track, then the project's tracks. A press steps a key on; the wheel or a stick steps
    it either way. The row names (`A3 B3 C4 ...`) stand on a rail between the cylinder and the keys,
    and the step numbers round the cylinder's right end. The cylinder (`Drum`) takes a click, a
    fingertip's press or a pinch; its drag plane stays upright through the axle, so `cell_at` reads a
    drag's point as the cell under it however the brass is turned. The wheel over it turns the view
    round a step, this player's own (`view_steps`), to reach the steps round the back. A hand has
    the knurled brass wheel on the axle past the right cheek (`Thumbwheel`, `WHEEL_X` 0.243 m,
    `WHEEL_RADIUS` 4 cm), turning with the brass: pushed up or down at its front (a fingertip's touch
    and slide, a pinch's or a click's drag on the upright plane through the axle) it turns the view a
    step every 1.6 cm of travel, the front of the brass going the way the hand goes; a press that
    does not roll it turns it a step on, and a stick or the wheel over it a step either way. Stopped,
    steps 9 to 15 are under and behind the brass, by the comb's block, where no fingertip or pinch's
    ray reaches, so without it a tracked hand could peg only the front half of the pattern. Its card
    says which step faces you (`front_step`). In a headset (`InstrumentItem.hands_hint`) the
    cylinder's card names the thumbwheel and the stick, the keys' cards the stick, and the hands
    line says "roll the wheel at its right end, or the stick, to turn it round" (kept to five lines
    so the plaque opened stays on the lid). A lamp under the lid's top edge lights the brass,
    brushed (roughness 0.62) so it lights evenly instead of in one hotspot over the pegs, and the
    pegs are dark blued steel with polished heads, so a peg seen end-on is a bright dot ringed dark,
    never one of the holes (drilled brass, only a little darker than the cylinder); a marked peg's
    collar is a bright steel ring well past its foot (`MARK_RING` 13.5 mm). The case's brass cheeks
    and the comb's steel are metallic in the model too (music_box.py's `metal`), as MusicBox's own
    brass and comb are.

    Its plaque hangs on the open lid's felt, as a music box's label does, leaning back with the lid
    (`lid_frame`, `PLAQUE_UP`): first it was on the plinth's front under the deck, where from the
    desk's seat the chord ledge's plaque covered its keys (the seat audit), and no move of the box a
    sensible distance from the harp cleared it. The hands line is a line shorter so the plaque opened
    stays on the lid. The station's frame is its plaque's top folded (`FRAME_TOP`) and its keys' front
    edge (`FRAME_FOOT`). The keys are `KEY` 0.13 by 0.07 m, 7 px or more from the seat. `--pegs` is a
    launch switch (scenes/bootstrap.gd): twelve pegs and one marked note, for the shots.

    Limits, for later slices: the pegs are one item's notes, so steps past a short item's end are
    refused rather than lengthening it; a step is one note a step long at the inserted velocity (no
    velocity or length per peg); the MUSIC BOX track is a bare add_track, no instrument chosen for
    it, so it plays on whatever the engine gives a new track; the key is read at the box's first bar, so a key change inside a
    longer turn marks the pegs after it; not tried in a headset.

    Tests (tests/run_tests.gd):
    - `_test_a_peg_on_the_music_box_is_a_note_of_its_track`: A minor's rows A3 to A4, the first bar a
      turn, the keys' legends; every cell's point on the brass and on the drag plane is that cell
      however it is turned; a click at row 3, step 5 makes the MUSIC BOX track at the project's end
      and one item over the bar with D4 at step 5's time, one undo step, its peg stood; a second peg
      is G4 at 1.125 s; pressing the first takes its note out, Ctrl-Z puts it back; an existing item is
      added to; the station's row and lines; the plaque on the lid, its top the frame's, opened still
      on the lid; the cylinder's card.
    - `_test_a_drag_along_a_music_box_row_is_one_undo_step`: a drag from step 2 to 5 is C4 at four
      steps, one undo step, which one undo takes away; a drag begun on a peg takes the run out.
    - `_test_the_music_box_reads_its_pegs_back_from_the_item`: a note moved in the roll moves its peg,
      transposed it changes row; in A major C4 is on no row, drawn at B3 marked (leaning, collared),
      and pressing it takes it out; chromatic rows, ROOT up 3; another track's notes are not pegs
      until TRACK steps to it; a cell past a short item's end is refused in words; TRACK, LENGTH,
      ROOT and SCALE step and wrap, the wheel stopping LENGTH at its ends.
    - `_test_the_music_box_turns_with_the_song`: a quarter round a quarter through the bar, round again
      at the next, a step at a time at motion 0; step 5 under the comb at its time; the playhead's
      and the loop's bars; the view's turn is this player's; stopped, step 12 is out of reach round
      the back, and a fingertip pushing the thumbwheel up eight steps' travel brings it to the front,
      down three turns back three, a press turns a step on, a nudge a step back; a headset's cards
      and the hands line name the thumbwheel and the stick; a tooth flicks and the flick dies, and at
      motion 0 the teeth stand.
    - `_test_a_guests_music_box_keys_and_pegs_ask_the_host`: the studio stands it beside the harp on
      its trolley; a guest's LENGTH asks the row, the host keeps it and refuses a length of 3 and an
      unknown track, a guest's room shows the host's row; a guest's first peg is open_edit and
      add_track, the rest of its drag waits, then insert_midi_take with its pegs and close_edit; a
      later peg is one insert_note in its own edit.
    - Existing tests take it in: the clearance (every venue stands every station clear, null in the
      roulette room), the station listing, the help card's pages and keys, the station board's rows,
      I walking to every station, a headset's travel, being pushed about, the seat audit and the
      in-view test (`_music_box_looks`: both ends of the rows top and front, every key's corners, the
      plaque's keys).

    "57 checks, 0 failed" for the five new tests (65 with the thumbwheel's checks, added after
    review; with the clearance, the station listing, the help card's pages and keys, the station
    board, the seat audit and the in-view test, "1879 checks, 0 failed"; with I-walk and a headset's
    travel, "116 checks, 0 failed"). "2187 checks, 0 failed" for them and the existing
    tests of what this touches: the clearance, the station listing, the help card's pages and keys,
    the station board, I-walk, the bells' homes, the miniature's pin, the seat audit, the in-view
    test, the looper's six and the weather's switch; and "92 checks, 0 failed" for a headset's travel,
    the layers list, the furniture rolling and pushed about, and the roulette room. On the probe
    (tools/probe/session_probe.gd): at 61.45 the guest stands a box of its own hearing the song at
    760 s and presses row 3, step 5; by 61.5 the host's MUSIC BOX track has one item over that bar
    with the row's pitch at the step's time, on the built-in engine one step `MUSIC BOX: pegs`, and a
    box of the host's own reads it as that peg; the guest's mirror has it too. The host takes the
    track out at 61.51 and ends the session at 61.52 (from 61.45). The probe was not run in this
    slice (checkpoints run it).

    shots/spatial47.png is the box with a pattern from a standing player's eye, close: the pegs on the
    brass with their bright heads and the marked one leaning in its collar, the row names A3 to A4,
    the four keys lettered, the comb's steel, the brass cheeks and the thumbwheel at the right end,
    with no hotspot over the pegs and the pointer parked off every station so no card is up
    (`SHOT_CAM "3.1416,-0.55,0.78,5.72,1.0,6.95"`, `SHOT_ARGS "--no-hud --pegs --hover 40,40"`).

48. [x] **A string across the room.** The proving idea, #34. Strings are room rows (`strings` {id:
    [a, b, maker]}, at most eight), asked with the room verb `string` [id, a, b] (empty to cut). The
    host checks a length of 0.3 to 12 m and the count, and a guest predicts. A spool (station
    `strings`) gives an end. Press at a point to tie the first end, carry the string to another
    point, and let go to tie the second. A desk clicks the two points (the ray's hits, any surface).
    Its length sets its pitch over four octaves, log in length: `76 - 48 * log2(length / 0.3) /
    log2(40)`, so 0.3 m is E5, a metre is about middle C, and 12 m is E1 (41 Hz), the bottom of a
    bass. It is snapped to the song's scale (Harmony.snap). So a string across the room is a low
    bass, and short ones by the window are high, lettered at their middles. Pluck it by brushing (a
    tip crossing it, the harp's rule), a grab or a click. It plays on the keys with source
    `&"string"`, rings 2.5 s, visibly shakes, and bends by tilt (slice 15). Grab its middle and pull
    hard, or press its knot's X, to cut it. Touches room_string.gd (new, core/music), session.gd
    (ROOM_VERBS `string`), studio.gd, stations.gd. The suite checks: 0.3 m, 1 m and 12 m give E5, C4
    and E1 before snapping, and length to pitch snaps in A minor; no length gives a pitch under E1;
    a pluck plays on the keys with its source; a row predicted and a too-long one refused; a cut;
    strings kept across a publish. The probe checks that the guest's string appears in the host's
    rows and its pluck in the host's take. Both sides at 0 failed. shots/spatial48.png is a long
    bass string across the live room.

    Built. `RoomString` (core/music/room_string.gd) is one string, a child of the venue, standing at
    the middle of its ends with its X along it: a thin cylinder (2.5 mm radius at 0.3 m up to 7 mm at
    12 m, steel going to bronze-wound), bowed and shaken in a shader of its own, a brass knot at each
    end with an X over it (`Knot`), its note lettered above its middle. `RoomString.Spool` is the
    station `strings`: a bobbin of string on a turned stand with a weighted foot and a brass eyelet
    (tools/blender/string_spool.py, assets/models/string_spool.glb), its reel (`Reel`) the control
    that gives an end, its plaque (`Stations.plaque`, folded) on an arm off the post. A trolley in a
    studio (`Venue.WHEELED`, `Studio.LIVE_TROLLEYS`), gone to by name and pushed about like the harp.

    Where it stands. Not by the window: the studio's live room has none, and the first place tried,
    the lattice's front corner, is behind the through-glass variant's wall in studio:2. So
    `Venue.default_string_spool_spot` stands it in the aisle between the drum riser and the lattice
    (`STRING_SPOOL_GAP` 1.13 m off the lattice's side, `STRING_SPOOL_IN` 0.7 m back along it, about
    (-1.0, 4.4)): off the straight walk from the desk to the back wall, and out of the line from the
    seat to the tubular bells, whose BACK key it hid (the seat audit). The loft's aisle holds the
    harp and the music box, so `LoftVenue.default_string_spool_spot` keeps the lattice's front
    corner. None in the Rig Roulette room (no zones).

    The law. `raw_pitch` is 76 - 48 log(l / 0.3) / log(40), held at its ends past them; `pitch_in`
    snaps it with Harmony.snap, and where that would go under E1 (12 m in E flat major snaps to E flat 1)
    it takes the scale's next tone up. Its letter is the note now (a string still ringing keeps the
    pitch it was plucked at), its card `STRING  C2` with `C2, 6.0 m (A minor)`.

    The row. `strings` {id: [a, b, maker]}, asked with `string` [id, a, b] (StringName, Vector3,
    Vector3), the ends in the venue's frame. `RoomString.answer` is both sides' rule: a and b the
    same point cuts (anyone's string); 0.3 to 12 m; the ends inside BOUND (40 m, y -2 to 20); a new
    id only while the room has fewer than 8. The refusals are words: "A string is 12 m at the
    longest: that one would be 12.5 m.", "The room has 8 strings, the most it takes: cut one first
    (pull it hard, or press a knot).". The host (`Studio._answer_string`) tells them to whoever
    asked and publishes the row. A guest (`ask_string`) refuses at once in the same words where the
    host would, so a too-long string is never asked, and otherwise predicts: the string stands at
    once, and `apply_room` folds its unanswered asks back on top of the host's row, so the host's
    answer without it takes it down. The row is the studio's, not the venue's, so it is kept across a
    publish of anything else and stood again in a new venue. A new string's id is
    `s<peer>_<n>`, so two players' ids never meet.

    Tying. The reel pressed gives the hand an end: `Interactor.tool`, a new hook (core/input/
    interactor.gd), takes that hand's button in place of pressing what it points at until it is
    cleared. The press that took it ties nothing. The next press ties the first end where its ray
    first meets something (`RoomString.surface_hit`: any physics body but the walker's layer, the
    floor, the ceiling at Venue.LIVE_ROOM_HEIGHT, the walker's solids as boxes up to their tops, the
    walls round the rooms a person walks in, crossing the openings between them; INF past FAR, 14
    m). The let-go 30 cm or more away ties the second. A press and let-go in one place, a desk's
    click, waits for the next press, which ties it. The card says what to do in the hand's words
    ("STRING: click where its first end goes (any wall, the floor, the gear), then where its second
    goes · Esc drops it" at a desk, "press ... carry it, let go ..." in a headset). Between the ends
    the string is drawn as it would be and lettered `D3  2.0 m`, `TOO LONG  12.5 m (12 m most)` or
    `TOO SHORT  20 cm (30 cm least)`. Esc, the reel pressed again, or the end's own press on the
    reel puts the end back. A fingertip's poke on the reel gives the end to the same hand's ray
    (`tying_hand`), since a poke reaches only what it touches. While a hand carries an end, or
    stands within ChordHarp.NEAR of the spool, or a string is touched or ringing, `&"string"` is in
    the player's reach (`Studio._follow_strings`), so the synth is up before the first pluck.

    Playing. A grab (a click, a pinch's ray, a trigger) plucks it at 84; a fingertip brushing past
    the line within TOUCH (2 cm), its nearest point inside the frame's path and away from the knots,
    plucks it as hard as it went (`InstrumentItem.velocity_for`, at least 50). The first rule taken
    from the harp, "from one side to the other" as the sign of a dot product, missed a tip passing a
    centimetre off in steps of two (the suite's brush), so the rule is the path's nearest point
    instead. A poke is not a grab as well. It plays on this player's keys (`keys.note_on` with source
    `&"string"` and the song position), so it is heard here, sent and taken down as a take named
    `Ada string 1`. One pitch is one note across the strings (`_sounding`). It rings RING (2.5 s) and
    is let go. While it rings, its middle swings (SHAKE 6 mm a metre's worth, wider and slower as it
    is longer), and at Ergonomics motion 0 it does not swing but glows. One `Wobble` (slice 15) for
    every string on the source bends what rings by the plucking hand's tilt and wobbles it by its
    shake, and its middle bows with the bend. At a desk, the mouse's wiggle over a ringing string is
    the shake and Alt with the mouse up or down bends, as the harp's. A bandmate's string notes come
    to `Presence.strings_heard` by source, and the studio sounds them from the string that plays that
    pitch here (`_on_string_heard`, `RoomString.heard`, a MonitorSynth of its own), which shakes.

    Cutting. Grabbed and pulled 40 cm off its line from where it was taken (a hand's own place, a
    mouse's ray in the string's upright plane), it is cut; up to 20 cm of the pull shows as the
    string bowed toward the hand. A knot pressed cuts it too. "The string is cut." to whoever cut it.

    The help card's LIVE ROOM page took one more station than it holds, so it is two pages now (PLAY
    · LIVE ROOM 1/2 and 2/2). `--strings` is a launch switch (scenes/bootstrap.gd) for the shots: a
    long string from the live room's left wall to the bricks table's corner, three short ones fanned
    up from the reel, and the long one plucked.

    Limits, for later slices: the strings stand in the venue's frame, so a venue change stands them
    at the same numbers wherever those are in the new room (in the air, through furniture); a
    bandmate's bend is heard on their notes but not shown on the string; the walker walks through
    strings; strings tied from one shared point letter their notes on top of each other; there is no
    undo of a string (it is the room's, not the project's); not tried in a headset.

    Tests (tests/run_tests.gd):
    - `_test_a_strings_length_is_its_note`: 0.3, 1 and 12 m are E5, C4 and E1 before snapping; log
      in length; in A minor 6 m (C#2) snaps to C2 and 2 m (D#3) to D3; no length in any of the 24
      keys goes under E1 or off its scale; 12 m in E flat major is F1.
    - `_test_a_plucked_string_plays_on_the_keys_with_its_source`: a 6 m string in A minor is lettered
      C2, its card; a grab plays 36 held by source `&"string"`, bent by the hand that plucked it; it
      rings 2.5 s; it shakes, and at motion 0 glows instead; a brush 1 cm off plucks, 4 cm off does
      not, a poke does not; one take "Ada string 1" with both plucks; a bandmate's note heard from it.
    - `_test_a_string_is_tied_from_the_spool_to_anything_the_ray_meets`: surface_hit meets the floor,
      a wall, the ceiling, a solid up to its top, the far wall through an opening, and nothing from
      outside; in the studio the reel gives an end with the hands' words; the press that took it ties
      nothing; FIRST END, then `D3  2.0 m` drawn; let go, the row with its ends and maker; a click,
      let-go and click; Esc, the reel again and the end's press on the reel drop it; too long drawn
      and refused in words; eight taken and a ninth refused; reach while carrying; the reel's count.
    - `_test_a_string_is_cut_by_a_pull_or_its_knot`: a knot press cuts and says so; a hand's 20 cm
      pull bows it and holds, 45 cm cuts; a mouse's drag 30 cm along its plane holds, 50 cm cuts.
    - `_test_a_guests_string_is_predicted_and_a_too_long_one_refused`: the verb's shapes; the host
      keeps a guest's string with its maker and refuses 12.5 m; kept across a publish of the music
      box and shown again from a published room; kept across a venue change to the loft and back; a
      bandmate's note routed to the string by Presence; a guest's string shown at once and rolled
      back by the host's answer without it; a guest's too-long one refused there and never asked.
    - Existing tests take it in: the clearance (every venue stands every station clear, null in the
      roulette room), the station listing, the help card's pages (LIVE ROOM now two) and keys, the
      station board's rows, I walking to every station (sixteen), a headset's travel, being pushed
      about, the furniture rolling, the miniature's pin, the roulette room, and the seat audit.

    "68 checks, 0 failed" for the five new tests. "2176 checks, 0 failed" for them run beside the
    existing tests of what this touches: the clearance, the seat audit, the station listing, the help
    card's pages and keys, the in-view test, I-walk, a headset's travel, the station board, pushed
    about, the furniture rolling, the miniature's pin, the roulette room, the harp's brush and a
    bandmate's harp note, a guest's plug and a guest's music box. `_test_you_walk_into_the_room_and_
    not_through_it` run alone is "126 checks, 1 failed" ("the desk has a footprint to walk into"), the
    same with the spool taken out: it needs the DAW tracks an earlier test leaves. On the probe
    (tools/probe/session_probe.gd): at 62.3 the guest asks `string` for `probe_string`, 2 m; the
    host answers as the studio does and publishes; by 62.36 the host's row has it with the guest as
    its maker, and the guest's mirror too; at 62.36 the guest plucks a string of its own at those
    ends onto TAKE_TRACK, its clock at 780 s, and by 62.5 the host has heard the pluck with the
    string's source and has the take, one note, the string's pitch in its key there. The host leaves
    at 62.56 (from 62.3) and the guest ends at 62.68. The probe was not run in this slice
    (checkpoints run it).

    shots/spatial48.png is the live room from its back with the long string across it, lettered F1,
    the spool in the aisle and three short strings fanned up from its reel (`SHOT_CAM
    "0.0,-0.12,3.6,0,1.3,3.6"`, `SHOT_ARGS "--no-hud --strings"`). shots/spatial48_spool.png is the
    spool close, its folded plaque, the bass string passing it to the riser (`SHOT_CAM
    "2.7,-0.3,1.8,-1.0,1.05,4.4"`).

49. [x] **A marble run.** The proving idea, #35. In the lattice zone, which no kept idea uses:
    `MarbleRun` (core/music/marble_run.gd, station `marbles`, zone `matrix`). Blocks go in the
    lattice's cells (0.25 m) as room rows (`marbles` {cell: [kind, facing]}, asked with `marble`
    [cell, kind, facing]): ramps in four directions, drops, splitters, and bell blocks whose note is
    the scale degree their height gives (Harmony). A marble is let go at the run's top on each bar,
    or on its BALL key. It travels the run a cell each sixteenth from the bar's start, the path
    walked from the blocks, never physics, so its notes fall on the beat. Each bell block it enters
    rings its note from the block. Marbles are the room's, like rain: every machine computes them
    from the clock and the rows, they never touch mix state, and they are recorded only through the
    run's `marbles` jack into a track. At a desk: click a cell to place the chosen block, the wheel
    turns it, Backspace takes it out. Headset: take blocks from the tray and put them in cells.
    Touches marble_run.gd, session.gd (`marble`), jacks.gd, studio.gd, stations.gd,
    tools/blender/marble_blocks.py. The suite checks: a path through placed blocks rings at the
    expected sixteenths; two machines agree; a block placed changes the path; a cell outside the
    lattice is refused; the jack records the notes; motion 0 shows the marble a cell per beat. The
    probe checks a guest's block in the host's rows and both sides' rings over a bar. Both sides at
    0 failed. shots/spatial49.png is a run in the lattice.

    Built. `MarbleRun` (core/music/marble_run.gd) is a child of the venue with its origin on the
    floor at the middle of the lattice cube's face toward the desk (`frame_in`), the 12 by 12 by 12
    cells behind it. It holds the blocks (`MarbleRun.Block`, a control each), the marbles (one
    MultiMesh), a ghost of the carried block, and the tray (`Tray`). The tray is a maple board on a
    post with five wells, `TrayKey`s RAMP, DROP, SPLITTER, BELL and BALL, each with a small block (or a
    marble) in it and lettered in front. Its plaque (`Stations.plaque`, folded) leans under the board,
    and its jack is off the board's left end. The blocks and the tray are tools/blender/marble_blocks.py
    (assets/models/marble_blocks.glb): a grooved ramp, a drop with a funnel ringed in brass, a
    splitter with a level groove through and a brass vane, a bell block with a small bell under a
    brass arch, every out end -Z. Ramps, splitters and bells have raised chevrons on their rails for
    their facing, and a bell has its note lettered over it (by shape and words, never colour). The station `marbles` (LIVE)
    is zone-mounted in `matrix`. Its spot is the tray (`spot_in`, `Venue.marbles_spot`), and the
    tray's foot is a `ZoneKit.solids` entry marked with the station. There is none in the Rig
    Roulette room.

    The rule. `marbles` {cell: [kind, facing]} and `marble` [cell, kind, facing] are as the slice
    says, with an empty kind to take a block out. `MarbleRun.answer` refuses, in words, a cell outside
    the lattice ("That cell is outside the lattice: a block goes in one of its 12 by 12 by 12
    cells."), a kind not known, a facing not 0 to 3, and a 145th block. The host answers
    (`Studio._answer_marble`, with `Session.tell` for a refusal). A guest refuses at once where the
    host would, and otherwise predicts (`ask_marble`, `_predict`, with `apply_room` folding unanswered
    asks back on top). The row is the studio's, so a venue change stands the same run again. BALL is
    a second row, `marble_balls`, holding the beats of the last eight (asked with `marble_ball`
    [beat], the next beat after the press, or the one after that when the next would send it the
    same way through a splitter as the BALL before it, still rolling: `ball_beat`). That way a BALL marble is the room's like the bar's, and
    every machine rolls it.

    The path. `top_of` is the highest block, then the front-most, then the left-most. `path(rows, n)`
    walks from there a cell a sixteenth:
    - a ramp or a bell goes on the way it faces;
    - a drop goes down;
    - a splitter goes its way on even marbles and the other way on odd ones (a bar's marble is
      numbered by its bar, a BALL's by its beat, `ball_number`), its vane tipped toward the bar's way.
    An empty cell is the path's last cell, where the marble falls out: there is no gravity besides
    drops, so a run is built, not tumbled. So is the lattice's edge. A ring of ramps stops at
    MOST_STEPS (32). `rings` is every bell entered in a span, on the scale tone of its row
    (`VenueInstrument.scale_tone(Harmony.at(...), 72, y)`: from the key's tonic nearest C5, so a
    falling run plays down the scale). It follows `Weather.drops`: a pure function of the rows and
    the song clock, read in pieces the same as whole, a seek of 1 s or more ringing nothing between.
    A ring is the chime (`Foley.venue_bar`) at the block, and the bell swings. On the host, while the
    song records and the jack is in a track, it is a note there (`HitRecorder.note`), heard or not.
    With the song stopped, BALL rolls a preview here alone at the song's tempo, which nobody takes
    down.

    The hands. A tray key sets `Interactor.tool`, as the string spool's reel does. The mouse keeps
    the block and puts one per click. Each goes where `pick` (a grid walk of the ray) finds: beside
    the face of the first block it meets, or on the working layer (the floor first; Shift and the
    wheel raise it, and a grid shows it). The wheel turns what is carried (the next off the tray
    faces so too), and turns a placed block under the cursor. A click on a placed block picks it up to
    move it. Backspace takes one out, and Esc puts the carried block back. A hand lets the block go
    in the cell it is in. A tap leaves it in the hand for a press where it goes (the ray's cell). A
    block carried from the press that took it has no ray (`_since_take`) unless the hand points on
    purpose: let go outside the lattice, a placed one is out of it and one off the tray is back on
    the tray, wherever the hand faces, and the ghost's words say which. Let go where it was, a placed
    block turns a quarter. A headset hand's stick turns what it carries wherever it is
    (`Interactor.tool_stick`, asked first by `XRInteractor._nudge_by_stick`), as the wheel does a
    mouse's. While
    carrying, a ghost of the block, its cell's edges and words (`BELL  RIGHT  C5 · LAYER 1`) show
    where it would go. At motion 0 a marble shows the cell it was in on the beat (a step per beat:
    every fourth cell), and bells do not swing. With motion it glides, and falls and fades from its
    last cell.

    Where the tray stands, and a deviation. At the face's middle, the tray hid the handbells' jacks
    from the desk seat (the seat audit). One side over, it hid the music box's keys and the ledge. So
    the tray stands TRAY_X (1.05 m) to the face's right, as seen from it, and the station's spot is
    the tray's, not the run's. Its jack is on the board's left end, toward the lattice's middle,
    because on its right end the close seat in studio:2 (in front of the glass) lost it out of view.
    The slice's "click a cell" is a click on a tray key and then clicks into the lattice: a cell in
    the air cannot be clicked without something there, hence the working layer and the faces. The
    `--marbles` launch switch builds a 21-block run for the shots.

    Limits, for later slices:
    - The run is the room's, and has no undo.
    - A bell's note is its row, not a choice.
    - A mouse cannot put a block in a cell with no block below it and nothing beside it on the
      working layer without raising the layer first.
    - The blocks are not solid to the walker, who walks through the cube.
    - Not tried in a headset.

    Tests (tests/run_tests.gd):
    - `_test_a_marble_rings_each_bell_on_its_path_at_its_sixteenth`: an eight-block run's top; an
      even and an odd bar's paths through its splitter; over two bars the bells at 0.25, 0.75, 1.25,
      4.25, 4.75 and 5.5 beats on their heights' scale tones in A minor, and after the bracket in D
      minor; song positions, source and length; four ramps in a ring stop at 32; the edge; a BALL
      marble on beat 10; in pieces the same as whole; nothing in an empty lattice.
    - `_test_two_marble_runs_ring_the_same_from_the_same_clock`: two runs at 60 and 23 fps ring the
      same 27 bells over eight bars as the schedule; a seek and a stopped song ring nothing.
    - `_test_a_block_placed_changes_the_marbles_path`: a drop put where the marble fell out takes it
      down; a block taken out ends the path there; turned, it goes the other way; a new top; a cell
      outside refused in words, as are a kind not known, a facing not four and the 145th; the verbs'
      shapes; the last eight BALLs.
    - `_test_the_marble_runs_jack_records_its_bells`: the studio stands it; the jack's sinks and
      refusal; plugged into track 5 while recording, the host takes down exactly the 12 bells the
      schedule rings over four bars at their song positions on the pitched channel, none on the
      armed track; unplugged, nothing.
    - `_test_a_marble_is_drawn_a_cell_per_beat_at_motion_0`: a glide half way at full motion and a
      fall at the last cell; at motion 0 the top, then the fifth and the ninth cell on beats 0, 1 and
      2, still between; gone after; the run draws it; a rung bell still at 0 and swinging at 1.
    - `_test_a_ray_picks_the_cell_a_block_goes_in`: the floor's cell, the layer's, on top of a block,
      in front of its face, none before an edge block, aslant from a standing eye, none outside.
    - `_test_a_desk_builds_a_marble_run_from_the_tray`: the station row and folded plaque; the keys'
      legends; BELL taken with its words; the taking click puts nothing; the ghost's words; a floor
      click; on top, turned; on a raised layer; out of the lattice refused in words; Esc; a block
      picked up and moved; the wheel turns it; Backspace through the studio takes it out; BALL with
      the song stopped rings three bells as a preview, nothing recorded; a hand takes a ramp, lets
      it go in a cell, pulls one out of the lattice and carries one off the tray out of it with its
      ray aimed into the lattice (out, and back on the tray), turns one with a headset's stick over
      nothing, and taps a drop and presses it in; two BALLs in a row go opposite ways through a
      splitter, and a third asked on a beat of the same parity waits a beat.
    - `_test_a_guests_marble_block_is_predicted_and_refused_outside_the_lattice`: the host keeps a
      guest's block, refuses one outside, takes a guest's BALL; kept across a publish, a room
      applied and a venue change; a guest's block predicted and rolled back by the host's answer; one
      outside refused there and never asked; a guest's BALL predicted and asked.
    - Existing tests take it in: the clearance (with null in the roulette room), the station
      listing (LIVE twelve), the help card's live lines, the station board's rows, I walking to every
      station (seventeen), the in-view test (the tray's keys and jack), and the seat audit.

    "77 checks, 0 failed" for the eight new tests. "2420 checks, 0 failed" for them run beside the
    existing tests of what this touches: the roulette, being pushed about, the furniture, the seat
    audit, the roulette room, the clearance, the station listing, the help card's pages and keys,
    the in-view test, I-walk, a headset's travel, the station board, the weather's jack, a guest's
    string, a jack's ends and who may plug.

    On the probe (tools/probe/session_probe.gd): at 62.56 the guest asks a ramp at (4, 9, 5) facing
    right, a bell in the cell it rolls into, and a bell outside the lattice. The host answers as the
    studio does (refusing the third to the guest in words) and publishes. By 62.62 the host's row
    has the two and its rings over bar 7 are published (`marbles_probe`). By 62.68 the guest's mirror
    has the two, it was told the refusal, and its own rings over that bar from its copy of the
    host's song are the host's. The host leaves at 62.74 (from 62.56) and the guest ends at 62.86.
    The probe was loaded and compiles, but it was not run in this slice (checkpoints run it).

    shots/spatial49.png is the run in the studio's lattice from above its front: a ramp at the top
    rolling along two bells (B5) into a drop, two bells (A5) into a splitter, its two branches down
    through falling bells (G5, F5) and out, a marble on its way, and the tray with its plaque at the
    face (`SHOT_CAM "3.0,-0.4,2.7,1.5,1.5,4.8"`, `SHOT_ARGS "--no-hud --marbles --play"`).
    shots/spatial49_tray.png is the tray close, RAMP DROP SPLITTER BELL BALL lettered, its folded
    plaque, the run above (`SHOT_CAM "3.35,-0.32,1.25,0.35,1.2,4.0"`). The lattice's light is dim on
    the run's top rows.

50. [x] **A theremin.** The proving idea, #23, and #37 on it. `Theremin` (core/music/theremin.gd,
    station `theremin`, free-standing at `Venue.theremin_spot` on open live-room floor, with `air` 1
    m: a metre of free air round both hands, which the synth zone does not have) has a pitch antenna
    and a volume loop. The pitch hand's distance from the antenna is the pitch, continuous over
    three octaves (nearer is higher), and the volume hand's height over the loop is expression (CC
    11, silent at the loop). It plays on the keys with source `&"theremin"`, so on the fast path:
    one held note, moved by bend within two semitones and handed on legato to the next note past
    that (the decision). So its take is notes, bends and expression, and plays back on any synth.
    Its SCALE switch (free, scale or chord) snaps it to Harmony.snap, with short glides between. The
    pitch guide: rings round the antenna at each scale step, lettered, with the nearest one lit and
    a bar showing how far off the hand is, so it is playable, not only a novelty. The pitch hand's
    tilt and shake wobble it (slice 15). At a desk: hold the mouse in its field: across is pitch
    along the guide's lettered rule, and the wheel is volume. Touches theremin.gd, wobble.gd,
    venue.gd (the spot), studio.gd, stations.gd, tools/blender/theremin.py. The suite checks:
    distance to pitch (log); the hand-on at the bend's edge with no gap; expression from the loop;
    the snap modes; the guide's letters and lit ring; the take's bends and CC 11; the desktop's drag
    and wheel; every venue's spot has its metre of air (the clearance loop). The probe checks a
    guest's theremin glide in the host's take. Both sides at 0 failed. shots/spatial50.png is the
    theremin with its guide.

    Built. `Theremin` (core/music/theremin.gd) is a walnut cabinet at waist height on a stand with
    a splayed foot, the chrome pitch rod standing in a brass collar on its right end and an arm out
    to the level chrome volume loop on its left (tools/blender/theremin.py, assets/models/theremin.glb),
    its folded plaque hung under the cabinet's front and its SCALE key on it. Station `theremin`
    (LIVE, `air` 1 m round `air_at`, the hands' place) on a `Venue.WHEELED` trolley at
    `Venue.theremin_spot`: by default (`default_theremin_spot`) in the drum ring's frame, in front
    of the riser's outer end, THEREMIN_IN (0.7 m) in from its side away from the looper and its back
    THEREMIN_GAP (0.2 m) off the riser's front edge, facing the desk, its player between it and the
    control room. In the studio's side-room arrangement the riser's front is a step from the window
    wall, so `StudioVenue.default_theremin_spot` stands it off the riser's long edge in the way to
    the booth, facing the riser. Its footprint is in `wheeled_solids`.

    - The law: `pitch_for` C6 at NEAR (0.1 m) from the rod's axis to C3 at FAR (0.6 m), log in
      distance (`distance_for` its inverse); `expression_for` CC 11 from 0 resting on the loop to
      127 VOLUME_SPAN (0.35 m) over it. The SCALE switch (`Theremin.Snap`, FREE, SCALE, CHORD;
      `target_for`) snaps to `Harmony.snap` or the chord's nearest tone, with a 50 ms glide.
    - One note on the keys with source `&"theremin"`: its CC 11 and bend first, then the note;
      bent within `Wobble.BEND_MOST`; past it the nearest note goes down bent to the hand before
      the last lets go (`handed_on`), so no frame is silent. Snapped, the note handed on to is the
      tone it snaps to inside the bend nearest where the glide is going (`_note_for`), so E4 to G4
      hands on to G4 and A4 to C5 to C5, and a snapped take is the scale's notes, not the ones
      between that a glide passes. Controls at most 60 a second. The
      volume hand down on the loop lets it go.
    - The hands: every confident bare palm and sure controller (`local_hands`); the one over the
      loop is the volume hand, and of the rest the nearest the rod in its field the pitch hand
      (`sort_hands`). A tracked hand lost for under a quarter second holds its note. Its tilt and
      shake come through a `Wobble` whose new `sending` flag is off (wobble.gd), its semitones
      added to the glide. A desk's cursor is not tilted by its travel along the rule, since that
      travel is the pitch: its Wobble reads the mouse's wiggle up and down (`Wobble.axis`, new),
      only its vibrato counts, and Alt's bend wheel (the vibrato left out while Alt is down).
    - The guide: a ring at each scale step (each chord tone in CHORD) round the rod at 1.3 m, the
      root's heavier, lettered along a rule out from the rod (the lowest and each root with its
      octave, alternately over and under, each sized from the far end in to its measured width
      with room to the last on its side, and left off where it would be smaller than
      `LETTER_LEAST`), the nearest lit and its letter larger and a row further out from the rule,
      clear of its own row, a ring at the hand and a bar from the lit ring to it; the card says
      `A4 +30 cents`. The switch is lettered SNAP over its mode (`SNAP / SCALE`).
    - At a desk: `Theremin.Field`, a band 0.1 m over and under the rule (so from the seat a click
      on the booth's mic is not taken by the air round the rod): the cursor resting on it is the
      pitch hand, the wheel is volume from silent (a ghost disc over the loop shows it), the button
      held plays it full, a drag carries it, and the cursor leaving puts the volume down and lets
      it go. `Theremin.ModeKey` cycles the switch (the wheel steps it), kept across venues.
      `Studio._follow_theremin` reaches for its source near it, hovering it or while it sounds.

    The tests:

    - `_test_a_theremins_pitch_is_the_hands_distance_from_its_rod`: C6 at NEAR, C3 at FAR, each
      octave the same factor of distance (F#4 at the geometric mean), nearer always higher and held
      past the ends, the inverse; the loop's expression (0 resting, 64 half way, 127 full); FREE,
      SCALE and CHORD snapping inside the range; the guide's pitches and letters.
    - `_test_a_theremin_holds_one_note_bent_and_hands_on_past_the_bend`: A4 at its distance and CC
      11 64 from the half-raised loop hand; drawn in to 70.5 still A4 bent +1.5; on to 73.3 handed
      on twice (A4, B4, C#5) with no silent frame and never two held; let down onto the loop, let
      go and the wheel rested; the take named `<name> theremin N` with the three notes legato, its
      bends gliding to the edge and dropping at each hand-on, and its CC 11 from 64 fading out.
    - `_test_a_theremins_guide_letters_its_scale_and_lights_the_nearest_ring`: 22 rings C3..C6
      lettered (the root with its octave), A4's at its distance; a hand at 69.3 lights A4, its
      letter larger and no other, 30 cents in words and in the title, the bar the right length;
      SCALE glides to B4 over frames, CHORD rings ten tones and takes G4, FREE plays the hand's
      pitch at once; the lit letter a row out and no two shown letters on a side running together;
      the key cycles FREE, SCALE, CHORD and the wheel steps back; a 20-degree roll
      bends A4 up `Wobble.bend_for(20)` on top, its Wobble sending nothing itself.
    - `_test_a_desk_plays_the_theremin_across_its_rule_and_its_wheel_is_the_volume`: a click at the
      rule lands on the field and one over its band does not; resting is silent until the wheel
      (four notches: A4 at 64, a fine notch 67); across nearer the rod higher; the wheel down lets
      it go; the button held plays G4 full and a drag glides to F; the cursor leaving puts the
      volume down and lets it go; the hints at a desk and in a headset.
    - `_test_a_snapped_theremin_hands_on_to_the_tone_it_glides_to`: in SCALE, E4 to G4 hands on to
      G4 (never F#4), A4 to C5 ends on C5, a long glide down holds only the scale's notes, and FREE
      still hands on to the nearest note.
    - `_test_a_desk_theremins_cursor_travel_is_its_pitch_and_not_a_bend`: the cursor swept 380 px
      along the rule from C4 to D3 rolls the mouse 35 degrees, yet the heard pitch never leaves the
      glide (before the fix it was 1.5 semitones off) and rests on D3; a wiggle up and down five
      times a second wobbles it within the vibrato's most; Alt and a semitone up bends it one.
    - Existing tests take it in: the clearance (its half disc of air sampled in all 42 venue
      arrangements, `_check_free_air`), the station listing (LIVE thirteen), the help card's live
      lines, the station board's rows, I walking to every station (eighteen), the in-view test,
      the roulette, and the seat audit (which found the field's first, taller slab taking the
      booth's mic from the seat; the band fixed it). The walk test's check that the lattice's zone
      is open floor now allows slice 49's marble tray, its own station's solid, which ZoneKit has
      stood there since that slice.

    "48 checks, 0 failed" for the four new tests. "3442 checks, 0 failed" for them run beside the
    existing tests of what this touches: the clearance, the station listing, a headset's travel,
    being pushed about, I-walk, the in-view test, the station board, the EQ wall's trolley, the
    miniature's pins, the help card's pages and keys, the seat audit, the hand drums' ring, every
    venue's instrument in its key, the tilt, the shake, tilt off, the harp's wiggle, the bend in
    the take, the furniture, walking in, the roulette, the roulette room's door and the band going
    in, the timeline's screen band, one tilt from three hands, the keys' instruments, the bells' homes,
    the platter's cart and the stage table.

    On the probe (tools/probe/session_probe.gd): from 62.72 the guest plays a theremin of its own
    (FREE) with two hands of the probe's, the volume hand half way up over the loop, the pitch hand
    gliding in from A4 to 73.6 by 62.84, recording onto TAKE_TRACK at song 800; at 62.84 the volume
    hand comes down and it is silent; its clock stops at 62.86 and the take goes. By 62.92 the host
    has heard its notes with the theremin's source and has one item there named for the theremin,
    its notes rising and each down before the last let go, with bends and CC 11 (64 first). The
    host leaves at 62.98 (from 62.74) and waits until 63.05; the guest ends at 63.1. The probe
    loads and compiles, but it was not run in this slice (checkpoints run it).

    shots/spatial50.png is the theremin in front of the studio's drum riser from where its player
    stands, played by `--theremin`'s two hands (the pitch hand 30 cents sharp of A4, the volume
    hand half way up): the guide's rings round the rod, A4's lit and lettered large, the rule's
    letters, the loop, the SCALE key and the plaque (`SHOT_CAM "2.85,-0.5,1.15,-3.9,1.2,4.15"`,
    `SHOT_ARGS "--no-hud --theremin"`). The rings, out to 0.6 m, fill the view at this distance, and
    the letters nearest the rod are small.

51. [x] **A modular synth wall: modules and patching.** The proving idea, #25, first half.
    `ModularWall` (hardware/modular/modular_wall.gd) is a Surface on the synth zone's module rack
    above the keyboard stand (zone `synth`), so F reaches it, and a station. Its modules: two VCOs
    (saw, square or sine, tune, FM in), NOISE, a VCF (low-pass: cutoff, resonance, CV in), a VCA,
    two ENVs (ADSR, gate in), an LFO (rate, shape), a MIX of four, and OUT. The KEYS module takes
    this player's keys (pitch and gate from their notes) while they stand at the keyboard stand.
    Jacks are PatchPoint-style sockets, cables are PatchCables with CableSweep's sag, and knobs are
    the console's Knob. The patch is room state (`modular` {cables: [[from, to]], knobs: {id: v}}),
    asked with `modular_patch` [from, to, song] (empty `to` unplugs) and `modular_knob` [id, v,
    song], and predicted and rolled back as the patchbay's `patch` is. A knob's turn is not a room
    ask per step: while it turns, `Session.send_knob(id, v, song)` streams it at most 30 times a
    second, reliable on GESTURE_CHANNEL (its own, so a retransmit holds back only knob and grain
    events, never notes), and only the let-go is a `modular_knob` ask. The DSP is C as decided:
    native/modular.c, built into the keys helper (`mod` lines carry the patch, the knob values and
    the keys), so a player's own modular is on the fast path. `Modular`
    (core/music/modular/modular.gd) is the same arithmetic in GDScript, `render(patch, events, from,
    frames)` at 48 kHz in blocks of 64, pure and deterministic, for recordings and bandmates.
    `ModularVoice` plays this player's keys through the patch live: on the helper where it runs,
    else on MONITOR on a thread, and the wall's tag says which and its figure. A default patch (KEYS
    to VCO to VCF to VCA to OUT, KEYS gate to ENV to VCA) sounds at first touch. Touches
    modular_wall.gd, modular.gd, native/modular.c, native/keys.c, native_keys.gd, modular_voice.gd,
    the module scripts, session.gd (two room verbs, `send_knob`, GESTURE_CHANNEL), studio.gd,
    stations.gd, zone_kit.gd (the rack's dressing yields to the wall). The suite checks: the default
    patch's render has its energy at the note's frequency; a re-patch changes the route; the same
    events render the same samples twice; the helper's `--render` of a patch and notes equals
    Modular.render within 1e-4; a 2 s knob turn sends at most 60 knob events and one room ask, and
    republishes the room once; the room verbs are predicted and refused (an unknown jack, an input
    taken twice); knobs replicate; the wall's controls pass the seat audit. The probe checks the
    guest's re-patch in the host's rows. Both sides at 0 failed. shots/spatial51.png is the wall
    patched.

    Built. `ModularWall` hangs at `Venue.modular_spot` over the synth zone's stand in every venue
    with zones (none in the Rig Roulette room), its rack's own dressing hidden (`ZoneKit.yield_rack`):
    a case of eleven 11 cm modules in wall order (KEYS, LFO, NOISE, VCO 1, VCO 2, MIX, VCF, ENV 1,
    ENV 2, VCA, OUT), a lamp on a stalk over it, its plaque on an arm beside it, and thirteen touch
    keys (`ModularTouch`) on the stand's upper deck under it. Two things moved from the plan as it
    was laid out. The touch keys went to the upper deck and the plaque beside the panel, because the
    bricks table stands about a metre behind the stand: no seat a desk can stand at sees the panel
    and anything on the lower deck at once. And F's visit walks to the station's seat
    (`Studio._walk_to_station`, shared with I) rather than `FocusRig.seat_for`'s, which stood the
    camera behind the table with the fifths wheel's board across the view. Its jacks
    (`ModularJack`) carry cables as the patchbay's do: from an output the free inputs light, from a
    patched input its plug comes out, to another input or off the jacks. Their rings light brighter
    and grow, so the sign is not colour alone. Its knobs are `Knob`, and its jacks, knobs, keys and
    handle take the pointer only while this player is at it (`within_reach`, `Studio.at_modular`):
    visited, or standing in front of the stand (0.3 to 1.7 m out, 0.6 m either side) where its own
    seat is the nearest station's (`_station_seats`, every half second, so a pushed trolley counts).
    The first area reached 2.8 m out and 1.1 m wide, and the harp, the bells, the section blocks and
    the music box's seats were all in it: the harp's plucks went through the patch and the wall's
    jacks took clicks from their seats. The help lines name F,
    G, the drags, the knobs, the keys, PLAY and OUT's road. PLAY takes the computer keys (A to ',
    from C3).

    The patch is the room's row `modular`, asked and predicted through the studio (`ask_modular_patch`,
    `ask_modular_knob`, `_answer_*`, `apply_room`), and a turn streams through `Session.send_knob` on
    GESTURE_CHANNEL (8), at most one value every 34 ms. `Modular` and native/modular.c are one
    arithmetic: the TPT state-variable low-pass, exponential ADSRs, the LFO and VCOs by phase, an LCG
    noise, a soft clip at OUT, every input a sample late, and only what reaches OUT run. The helper
    takes `mod` lines and `wait N`. `ModularVoice` plays the keys through it while `engaged`: on the
    helper where it runs (`HELPER · 5.3 ms` on this machine), else on MONITOR on a thread
    (`THROUGH GODOT · 42 ms`), the MonitorSynth handing it its notes instead of playing its tine.

    The tests (tests/run_tests.gd):
    - `_test_the_modular_default_patch_plays_the_note_it_is_given`: the default patch; an A at 440 Hz
      over twenty times a semitone either side, a C5 at 523 Hz, silence before the key, a release.
    - `_test_a_modular_repatch_changes_the_route`: the VCA's input pulled is silence; noise in the
      VCO's place has no 440; a cable into a MIX that reaches nothing changes no sample; an LFO
      patched onto the VCF's CV mid-render changes it from its block on; refused shapes.
    - `_test_the_modular_renders_the_same_events_the_same_twice`: twice, in any listed order, and
      a block at a time, the same samples; a knob 10 ms later is another sound.
    - `_test_the_keys_helper_renders_the_modular_as_godot_does`: a seven-cable patch, two keys, a
      knob and a let-go through `--render` equal Modular.render within 1e-4, the same in both ears;
      the parser's `mod` lines and what it ignores.
    - `_test_the_modular_voice_plays_the_keys_through_godot_off_the_helper`: the Godot road, the
      tag, the tine silent, a knob heard, and the tine back once disengaged.
    - `_test_the_modular_walls_cables_are_carried_from_jack_to_jack`: the drags and their lights,
      the asks they make, the refusal in words, and the room's patch shown.
    - `_test_a_modular_knob_turn_streams_and_is_one_room_ask`: `_knob_up`/`_knob` reliable on
      GESTURE_CHANNEL, a channel of its own. A host's 2 s turn streams 21 to 60 times, is the row
      once let go and publishes the room once. A bandmate's stream turns the wall and the voice but
      not the row, clamped, unknown knobs refused. A guest's turn is one predicted ask.
    - `_test_the_modular_verbs_are_predicted_and_refused`: a guest's cable and knob kept by the host,
      an unknown jack and an input taken twice refused, the verbs' types, the room applied again, a
      change of venue, and a guest's cable predicted, kept, rolled back, refused in words, pulled.
    - `_test_the_modular_wall_is_played_where_it_hangs`: from the desk none of its controls take a
      click and the keys do not play it. Walked to, they do, and every one of its controls takes a
      click from the eye at 7 px or more. A touch key plays this player's keys and KEYS letters
      it, the wheel moves the keys an octave, PLAY takes the computer keys and gives them back, and
      F's visit puts it in reach. Every touch key's letter stands clear of its cap (they lean on
      the cap's top and ride it down with the press; they were half sunk in it), C3's too.
    - `_test_the_modular_is_played_only_at_its_own_stand`: walked to each of the other stations
      (seventeen in the studio), the wall is out of reach and the keys do not play it; at its own
      seat they do.
    - Existing tests take it in: the clearance (its zone check, since a surface mounted in a zone
      is checked there now), the station listing (LIVE fourteen), the help card's live lines, the
      station board's rows, I walking to every station (nineteen), the in-view test (its top
      corners, its keys' ends and its plaque's keys), and the summon test, where a surface that
      stays home (the EQ wall, the modular) is checked to stay home rather than to be in the arc.

    "73 checks, 0 failed" for the nine new tests. "3622 checks, 0 failed" for them run beside the
    existing tests of what this touches: the clearance, the in-view test, I-walk, the station
    listing, the help card's pages, a headset's travel, the station board, the seat audit, the EQ
    wall's three, the summon test and the focus and surface tests around it, the marble guest's
    prediction, the desk theremin, the keys helper's three, the pedal, the keys' instruments and
    the controls' channel and clamps. The suite's guest checks use an OfflineMultiplayerPeer, so
    its `send_knob` and `ask_room` print the engine's "RPC on yourself" ERROR lines as the marble
    guest test's asks do. They are not script errors.

    On the probe (tools/probe/session_probe.gd): at 62.94 the guest asks an LFO onto the VCF's CV
    and the noise into the same input, streams three values of the cutoff and lets it go at 0.85.
    The host answers as the studio does and by 63.0 checks that its row has the cable and the knob
    and not the refused cable, and that it heard the three values from the guest in order. By 63.04
    the guest's mirror has them and it was told the refusal in words. The host leaves at 63.08
    (from 62.98) and waits until 63.15, and the guest ends at 63.2. The probe was not run in this
    slice (checkpoints run it).

    shots/spatial51.png is the wall from its station's seat in the studio (`SHOT_ARGS "--no-hud
    --focus modular --modular"`). `--modular` re-patches it as the wall asks: VCO 1 and VCO 2 a
    fifth up through the MIX with the noise low, the MIX into the VCF, the LFO on its CV and ENV 2
    on VCO 1's FM. An A3 is held on its touch keys, KEYS letters it with its gate lit, and OUT's tag
    says THROUGH GODOT · 42 ms. A cable across more than a module and a half hangs to the panel's
    foot under its lowest row of jacks (`ModularWall.cable_sag`, CABLE_FLOOR), so the long runs cross
    the modules below their jacks and names instead of over VCO 1 OUT, VCO 2 OUT and MIX IN3 and IN4,
    as they first did.

52. [x] **The modular, recorded and heard by the band.** #25 finished. Bandmates hear a player's
    modular: they render the same patch (room state) with that player's keys (their notes and
    controls already arrive with their source and `song`) and knob events, on a ModularVoice for
    each playing peer, from the wall, through Godot. Recording: while a player's keys record through
    the modular, the take keeps its notes, controls, knob events and patch changes, each with the
    `song` it was made at (the knob stream's and the room verbs' `song`), so a sweep lands where it
    was turned, not where the host received it. The player's own live voice reads the same knob
    events it sends, not the knob itself, so the live sound and the take's render are one. When the
    take ends, the host renders it from what it received and holds, reliable and stamped, so no file
    is sent. The WAV goes into the project's media folder and in as an audio take named `modular` on
    the take's track, and the notes' MIDI take is not inserted. Touches modular_voice.gd,
    guest_midi.gd (the take's route), presence.gd, session.gd, studio.gd. The suite checks: two
    renders of one take are equal; the WAV's length is the take's span; it is inserted on the
    built-in engine at its start; a cutoff sweep made mid-take and delivered 80 ms late is heard
    where it was made; a patch change mid-take likewise. The probe checks that a guest plays the
    modular with a knob sweep while the host records, and the host has one audio take at the guest's
    song, equal to the guest's own render of it. Both sides at 0 failed.

    Built. While the modular is in a player's reach (`GuestMidi.through_modular`) everything their
    keys sound plays the patch, so everything they send goes out as the modular's (source
    `Modular.SOURCE`, decided at the note-on and kept for its note-off, `_sent_as`), a hardware
    keyboard's and the computer keys' as well as the touch keys'. Presence routes those notes and
    controls by source (`modular_heard`, `modular_control_heard`), and the studio plays each
    bandmate on a `ModularVoice` of theirs with a `speaker`, the wall: through the room's patch, on a
    Modular of its own through Godot, out of an emitter at the wall (`Studio.modular_heard`). The
    room's patch, everyone's knob streams and the cables change every voice here, their wheel bends
    theirs while they hold a note, their last note-off rests it, quiet for `rest_after` (5 s) with
    no note held their voice rests (no thread, no emitter) until their next note, and gone, their
    voice goes. This
    player's own voice now hears a turn as it is streamed (`_on_knob_streamed`), not as the knob
    moves under the hand, and a knob still under the hand is kept on the voices at its streamed value.

    A take is `ModularTake` (core/music/modular/modular_take.gd): the patch as it began and every
    event after it with the song it was made at (notes, the wheel, knobs, cables), rendered by
    Modular.render from its start for its span and written as AudioTake's 16-bit WAV. `ModularTakes`
    (core/session/modular_takes.gd, `Session.modular_takes`) holds them. GuestMidi begins the
    player's own when a take begins at the wall or its first note goes through it, feeds it what it
    sends, and at the end calls `finish` with the take's tracks. Its notes sent as the modular's are
    not in the MidiTake, but the rest of the take is: a take that rolls on through the harp, the
    wall and the keys away from it puts in the wall's notes as audio and the others as a MIDI take
    beside it (`midi_notes` in `last_take`), so nothing played around the wall is lost.
    The knobs come from `Session.send_knob`, `_pass_knob` and `_knob`; the cables, and a knob let go
    with no hand on it here, from the studio's `_show_modular(patch, song)` at the song the room's
    verb was asked at (`_take_modular_change`). A guest marks its take begun and ended twice, on
    KEYS_CHANNEL behind its notes and on GESTURE_CHANNEL behind its knobs (`send_modular_take`), so
    the host takes the guest's notes and wheel between the keys' marks (each move of the wheel the
    take keeps sent again reliable on KEYS_CHANNEL, `Session.send_modular_bend`, `heard_bend`) (keys held at the begin at the
    take's start) and the room's knobs and cables from the gestures' begin, when it takes the patch
    as it hears it (`ModularTakes.patch`, `Studio.heard_modular_patch`), until it is placed: a third
    player's knob can arrive after the end. Two things the plan did not say. The marks are the only
    thing sent of the take, and they come in pairs because one mark on one channel could overtake or
    trail the other channel's events. And the host waits SETTLE (0.25 s) after both ends, or
    ENDS_WAIT (2 s) after one, for a cable asked on the room's own channel just before the end, then
    renders and writes the WAV on a worker thread (the render about 35 ms a second of take here, and
    the 16-bit encode and the overview another 5, which on the main thread froze the host 0.9 s for
    a three-minute take) and on the main thread puts it in on the take's tracks at its start, named
    `modular`, on the player's behalf, telling both. A take past AudioTake.MAX_SECONDS (30 min) is
    cut there, and both are told. A host's own take is the
    player's own and is placed the same way. A take with no notes puts nothing in. On the wall, OUT
    says REC on a line of its own, at a module title's size, while a take goes through it, and the
    station's help lines say that a take recorded at it is its sound. The live wheel still rides the
    controls' unreliable channel, a lost move made good by its resend within 50 ms for the ear; the
    take's wheel is the reliable copy, so the host's render is the player's own under loss too.

    The tests (tests/run_tests.gd):
    - `_test_a_modular_take_renders_the_same_twice_as_long_as_its_span`: a key held as it began at
      its start, the wheel rested at the last note-off, nothing unstamped kept, two renders equal,
      1.25 s long, its WAV in AudioTake.DIR that long and the render's samples to 16 bits.
    - `_test_a_guests_modular_take_is_rendered_by_the_host_where_it_was_played`: the marks reliable
      on KEYS_CHANNEL and GESTURE_CHANNEL; the host's take of a guest from its keys' begin, the held
      key at the start, a harp note and a note after its keys' end left out; a cutoff sweep made
      mid-take and delivered 80 ms late equals the take as played and differs from it at arrival,
      the take's wheel reliable on KEYS_CHANNEL and a resend of where it stands not kept again,
      open before and shut after; a cable pulled mid-take, delivered after the take's end, likewise;
      one audio take named modular at its start on the built-in engine, 1 s, no MIDI; none for a
      take of knobs alone.
    - `_test_a_modular_take_is_put_in_as_audio_on_the_built_in_engine`: a host's keys at the wall
      sent as the modular's, its take begun at the wall, a knob streamed into it, no MIDI take, then
      on a worker thread one audio take named modular at its start, the WAV the player's own render;
      away from the wall, a key is its own again and the take is MIDI.
    - `_test_a_take_of_the_harp_then_the_modular_then_the_keys_keeps_all_three`: one take rolling
      through a harp note, a note at the wall and a key away from it; the harp's and the keys' notes
      a MIDI take, the wall's alone in the modular's take, and once placed the track holds both.
    - `_test_a_bandmates_modular_is_heard_at_the_wall_through_the_rooms_patch`: a bandmate's voice at
      the wall through Godot playing 440 Hz, another instrument's note not on it, someone's knob
      stream and the room's cable heard in it, their wheel two semitones up while held and rested at
      the note-off, a wheel with no note not played, quiet for its spell their voice resting with no
      thread or emitter and woken by their next note; this player's own turn not heard until it is
      streamed, then in both voices; gone, their voice goes.

    "47 checks, 0 failed" for the five new tests. "459 checks, 0 failed" for them run beside the
    existing tests of what this touches: the modular's nine, GuestMidi's takes, bends, wheels and
    lost controls, the string, the harp and keytar, the controls' channel, the keys pack, the host's
    audio take and the built-in engine's recorded take, the help card's pages and its walk, the
    station board and the stations' help lines, the patch sockets (the tablet, a strip's send, a
    rack's OUTs, on air) and the theremin. The keys pack's test had failed in the tree (its plug not
    shown on a bandmate's pack: the desk builds a frame or two after the studio and `_show_patches`
    returned before any socket while it had no master); the pack and the racks are now shown whether
    the desk is built or not.

    On the probe (tools/probe/session_probe.gd): from 63.06 the guest plays the modular at the wall
    hearing the song at MODULAR_SONG and recording onto TAKE_TRACK, MODULAR_PITCH held, and at 63.1
    moves the wheel up (its take's copy reliable behind the notes) and sweeps the cutoff through
    MODULAR_SWEEP a frame at a time; let go at 63.24, its clock stops
    at 63.26 and the take ends. By 63.62 the host checks one audio take named modular on TAKE_TRACK
    at the guest's song and no MIDI, the notes heard as the modular's and the sweep as it streamed,
    and publishes the WAV's start, frames and digest (`modular_probe`); by 63.68 the guest checks
    them against its own render of the take. As in the theremin's step, the recording is the one the
    guest hears (a clock of the probe's saying the host records), not the host's own transport. The
    host answers the modular's verbs into the takes as the studio does. The host now leaves at 63.72 (from 63.08) and waits until 63.79, and the guest
    ends at 63.84. The probe script compiles with the autoloads loaded; it was not run in this slice
    (checkpoints run it).

    shots/spatial52.png is the wall from its station's seat with a take going through it
    (`SHOT_ARGS "--no-hud --focus modular --modular-rec"`): the slice 51 patch, an A3 held, and OUT's
    REC on its own line under its tag `THROUGH GODOT · 43 ms`.

53. [x] **The world plugs into the modular.** The proving idea, #31. As decided, the world's outputs
    are sockets on the modular's patch, not jacks: `world:weather` (its density as a level, and a
    gate a drop), `world:drips` (a gate a drip, in the cave), `world:venue` (a gate a strike, and
    its level), `world:ring_N` (a looper layer's level) and `world:marbles` (a gate a ring). Their
    sockets sit on the weather switch, the cave's pool, the venue instrument's stand, each ring and
    the run's base, and a long modular cable runs from there to an input on the wall (`vcf.cv`,
    `env1.gate`), drawn with CableSweep. At a desk, P on a world socket steps through the wall's
    free inputs. Every one of them is computed on every machine, from the song clock and the rows:
    weather, drips and marbles as decided; a strike from its item_hit's `song`; a ring's level from
    its layer's own notes' velocities over the loop (not a meter), so the modular sounds the same
    everywhere. A world socket's jack row into a track is untouched by its modular cables, so the
    rain can record onto a track and drive the filter at once. Touches modular.gd, native/modular.c
    (the world inputs), modular_wall.gd, weather.gd, venue_instrument.gd, looper_rings.gd,
    marble_run.gd, session.gd, studio.gd, tools/probe/session_probe.gd. The suite checks: rain
    density into the VCF's cutoff changes the render; a drip gates an ENV in the cave; a ring's
    level follows its layer's notes and is equal on two machines; the weather's track jack and its
    modular cable work together; the cable is drawn. The probe checks a guest patching the weather
    into the host's VCF, and both renders agreeing over a bar. Both sides at 0 failed.
    shots/spatial53.png is a cable from the window to the wall.

    Built. A world socket is an output of the patch like a module's (`Modular.WORLD`, twelve:
    `world:weather`, `world:drips`, `world:venue`, `world:ring_1` to `world:ring_8`,
    `world:marbles`; `Modular.is_output`, `is_world`), so it is a cable in the room's `modular` row
    like any other, asked with the same `modular_patch` verb, answered by the same
    `Modular.answer_patch`, and kept, mirrored and predicted the same way. Each socket carries a level
    and a gate: `Modular.world(socket, level)` (Event.WORLD) sets the level, `trig(socket)`
    (Event.TRIG) opens the gate WORLD_GATE_BLOCKS (36 blocks, 48 ms), shutting it for one block first
    if it is open, so two drops close together are two gates. ENV 1's and ENV 2's gates
    (`Modular.GATE_INS`) read the gate and every other input reads the level, so the rain into the
    VCF's CV is its density and the rain into an ENV's gate is a gate each drop. The output slots are
    the modules' outs, then `_ZERO`, then the twelve levels, then the twelve gates (`_slot`, `_reads`).
    native/modular.c has the same (`mod_world`, `mod_trig`, `mod_slot`, `mod_reads`, `MOD_SLOTS`),
    and the keys helper reads `mod world NAME V` and `mod trig NAME` lines
    (`NativeKeys.modular_world`, `modular_trig`, `modular_world_line`, the level to 17 digits), so the
    helper's route plays the world as Godot's does.

    What plays into the sockets is `ModularWorld` (core/music/modular/modular_world.gd,
    `Studio.modular_world`), pure: `events(from, to)` is [song, WORLD or TRIG, socket, value] in order
    (`ordered`, a stable sort by song), the same whole or in pieces, from the song clock and the rows
    alone. The weather says its level every sixteenth (`Weather.level`, the smooth gust, a share of
    WEATHER_TOP 0.42) and a gate each drop (`Weather.drops`). The cave's drips, a strike of the venue
    instrument and a marble's bell are pulses (`_pulses`): the velocity as the level and a gate at the
    hit, the level back to 0 WORLD_GATE later unless the next hit comes first. A ring's level is its
    layer's own notes' velocities over the loop, the loudest sounding, 0 between them, with a gate
    each note begins (`ring_events`, `ring_notes`, `ring_level`), and a muted track or item gives
    none. A strike comes from Session.item_hit's `song` (`strike`: from `_on_item_played` for this
    player's and `_on_someones_hit` for a bandmate's), and one heard after its song has gone by is
    played in at once. `levels_at` is where each level stands at a moment, so a voice starting
    mid-song starts from it. As the song plays here, `follow` hands each frame's span on (`fired`) to
    every copy of the patch this machine plays (`Studio._on_world_fired`): this player's ModularVoice,
    each bandmate's, and a world-only voice of the studio's at the wall (`modular_world_voice`,
    `world_only`, -6 dB, never resting of itself), engaged while the wall is up in the venue
    (`modular_wall.visible`), a world cable is in the patch and no other voice here is playing it
    (`_modular_played_here`: this player's at the wall or under PLAY, or a bandmate's not yet
    rested), so the world is carried by exactly one copy here when nobody plays and a drip into a
    gate is not heard twice a few ms apart. It sounds by itself only where a world socket drives a
    gate or the VCA's path, such as a drip into ENV 1's gate once keys.gate is pulled: in the
    default patch only ENV 1 from keys.gate opens the VCA, so the rain into vcf.cv alone is silent
    with no key held. ModularVoice keeps the world's
    levels (`world`, `trig`, `world_levels`) and sends them again when its route changes or a new
    thread starts. A take hears the world once, when it is finished (this player's) or placed (a
    guest's, before its render): `ModularTakes.world` is `ModularWorld.for_take`, and
    `ModularTake.hear_world` puts in the levels at its start and every event over its span.

    The sockets are `WorldSocket`s (core/music/modular/world_socket.gd, a ControlAffordance in the
    group `modular_world_sockets`): a socket on a small pale plate (an output's, as on the wall)
    lettered MODULAR and its short name, with a tag above it saying where it goes ("-> MODULAR VCF CV
    IN"). The weather's sits BESIDE (7.5 cm) its track jack on the sill (in the cave it is the drips'
    socket, at the pool), the venue instrument's beside its jack on the stand, the marble run's on its
    tray, and the looper's on a rod out SOCKETS_OUT from the rings, one at each ring's height, lowest
    first, lettered RING N, clear of every ring's band (`LooperRings._show_sockets`, `socket_of`), a
    layer's going with it. A click, a dwell or a hand's press steps the cable into the wall's next
    free input, and around past the last it is pulled (`Modular.free_inputs`, `step_input`, the order
    WORLD_INPUTS: the VCF's CV first, then the ENVs' gates, the VCA's CV, the FMs, MIX, the pitches,
    the audio ins). P over it at a desk steps on, Shift+P or the wheel back (MouseInteractor, before
    the own jack's step), and each step is asked of the host (`Studio._on_world_step`) and said in a
    notice (`world_patched_text`). The cable is drawn as CableSweep from its plug out, down to the
    floor, along it, out WALL_CLEAR (0.6 m) in front of the wall's stand and up into the input
    (`WorldSocket.route`, `CableSweep.smooth`, `rest_on`), sand-coloured, rebuilt when an end moves.
    The wall's input card says where it comes from (`Modular.world_title`, "THE WEATHER"), and its
    plug dragged out of that input pulls the cable or moves it to another input, as any cable's,
    carried with a sand stub. The socket's own track jack row is untouched by any of this, so the rain records onto
    a track and drives the filter at once. The stations' help lines for the modular say how, at a desk
    and with hands. Two things the plan did not say: a socket's gate is kept separate from its level
    (an ENV's gate reading a level would hold open through a whole storm), and the world's own voice
    at the wall plays what the world does with no one at the keys.

    The tests (tests/run_tests.gd):
    - `_test_rain_density_into_the_modular_filter_changes_its_sound`: the weather into the VCF's CV a
      cable kept as the room's row, a socket into an output no cable; over eight bars a level each
      sixteenth and a gate each drop, the same read whole or in pieces; brighter at the gust's top
      than its foot, where with no rain both are alike; into a patch with no cable from it, the world
      changes no sample.
    - `_test_a_drip_gates_an_env_in_the_cave`: the cave's weather into the drips' socket, a gate each
      drip and its velocity as the level back to 0 48 ms on; the drips into ENV 1's gate in KEYS'
      place silent until the first drip's block and sounding at once, dying away before the next,
      the gate open 36 blocks.
    - `_test_a_rings_level_follows_its_layers_notes_the_same_on_two_machines`: two layers, the level
      up at each note and down between, the loudest where two sound, a gate each note; a second
      machine with the room's mirror (MixWire.apply_replicated) works out the same events, whole or
      in pieces, and the ring into the VCA's CV renders the same samples on both; muted, no level.
    - `_test_the_keys_helper_plays_the_world_into_the_modular_as_godot_does`: the patch's lines carry
      world cables, the helper renders world lines as Modular.render does to within 1e-4, and its
      parser reads them and ignores a socket it has not.
    - `_test_a_modular_take_hears_the_world`: ended, a take holds what the world played over it, the
      level at its start first, put in once, and its render differs from the take without the world.
    - `_test_the_weathers_track_jack_and_its_modular_cable_work_together` (the studio in the loft's
      storm): the socket beside the track jack, its card's desk and headset lines, a click patching
      it into the VCF's CV and saying so, the cable drawn from its plug down to the floor and up into
      the input, the wall's input naming it, the track jack still into track 5; P on to ENV 2's gate
      (ENV 1's is KEYS'), Shift+P back; the jack recording the drops onto track 5 while the world
      tells the level every sixteenth; every voice hearing it and the world's voice engaged, and at rest
      while this player's own voice plays the patch under PLAY (one copy of a drip, not two); stepped
      past the last input it is out, its cable gone, the voice at rest, the jack still in; the venue
      instrument's and the marble run's sockets beside their jacks.
    - `_test_a_looper_rings_sockets_stand_clear_of_their_bands`: a socket for each ring, lowest first,
      at its ring's height and clear of every band, lettered with its place, a press on ring 2's into
      the VCF's CV, a layer gone and its socket with it.

    "53 checks, 0 failed" for the seven new tests. "3459 checks, 0 failed" for the 93 existing tests of
    what this touches (the modular's fifteen, the weather, the looper rings, the marble run, the venue
    instrument, the stations' help lines and board, the help card, the jacks and the patch sockets),
    and "86 checks, 0 failed" for the keys helper's, the hits helper's and the P key's.

    On the probe (tools/probe/session_probe.gd): at 63.74 the guest pulls the LFO out of the VCF's CV
    and patches `world:weather` into it, each asked of the host. At 63.8 the host checks its row has
    it and renders WEATHER_BAR (5, the top of its gust) of the loft's Thunderstorm through its patch,
    MODULAR_PITCH held, with the weather's events, and publishes the frames and digest
    (`world_probe`). By 63.86 the guest checks its own render of that bar through its mirror of the
    patch against them, sample for sample. The host now leaves at 63.92 (from 63.72) and waits until
    63.99, and the guest ends at 64.04. The probe script loads with the autoloads; it was not run in
    this slice (checkpoints run it).

    Limits. A take's world is worked out from the rows as they stand when it ends, so a looper layer
    edited or the weather switched mid-take is heard as it is at the end. The world's own voice rests
    while any other voice here plays the patch, so a player at the wall hears a world gate once, in
    their own voice; but two players at the wall at once each have a voice that hears it, so there a
    drop into an ENV's gate is heard once in each. `world:ring_N` is the Nth layer lowest first,
    so deleting a lower layer moves a cable to the next one up.

    shots/spatial53.png is the loft's window in a thunderstorm with the weather's MODULAR socket
    patched (`SHOT_ARGS "--no-hud --venue loft:2 --world"`, `SHOT_CAM "1.2,-0.4,2.4,-6.6,0.55,1.1"`):
    the rain on the glass, the THUNDERSTORM plaque, the pale socket beside it with its tag, and the
    sand cable falling to the floor and running into the room. shots/spatial53_wall.png
    (`SHOT_CAM "-1.2,-0.25,1.7,6.6,0.85,5.2"`) is its other end: the cable up off the floor in front
    of the keyboard stand and into the VCF's CV on the wall. `--world` steps the weather's socket
    once at launch. The notice saying where it went shows even with `--no-hud`.

54. [x] **A sample as a cloud of grains: playing it.** The proving idea, #24, first half.
    `GrainCloud` (core/music/grain_cloud.gd, station `grains`, a cloud a metre across over a plinth
    in the live room). Put a sample cassette (26) or a clip cassette (23) in its bowl (holder
    `bowl`) and the cloud is that sound: a file's audio, a MIDI clip's render, or a demo part's
    window. Its length lies left to right, drawn as motes brightest where it is loud. A hand in the
    cloud (tracked, a controller, or the mouse held on its face) plays grains from where the hand
    is: across is position, up is grain length (20 to 200 ms), and in is density. Spreading the
    fingers (the span of the tips, a controller's grip travel, the wheel) widens the spray, up to
    30% of the sample. `GrainVoice` (core/audio/grain_voice.gd) makes deterministic grains (seeded
    by their event's time) in Hann windows, at most 32 at once, on MONITOR through Godot, with its
    figure on the cloud's tag (a texture, as decided). It plays from grain events made 30 times a
    second from the hand, never from the hand directly, so what it plays is what slice 55 sends and
    records. Its pitch follows the chord's root when its KEY switch (a room row) is on. Touches
    grain_cloud.gd, grain_voice.gd, cassette_item.gd, studio.gd, stations.gd. The suite checks: the
    hand's place maps to position, length and density; spread widens the positions; the same events
    render the same output; a sample, a MIDI and a demo cassette each fill the cloud, and an empty
    cloud says "put a sample in the bowl"; the desktop's hold and wheel. shots/spatial54.png is a
    hand in the cloud.

    Built. `GrainCloud` (core/music/grain_cloud.gd) is a plaster plinth with a turned brass bowl on
    its cap and two brass posts up to a rail along the cloud's front, under its tag, so it crosses
    no word (tools/blender/grain_cloud.py, assets/models/grain_cloud.glb), and over it a cloud 1 m
    across, 0.52 m tall and 0.4 m deep.
    Station `grains` (LIVE, `air` 0.55 m round `air_at`, the cloud's middle) on a `Venue.WHEELED`
    trolley at `Venue.grains_spot`: by default (`default_grains_spot`) in the aisle between the drum
    riser and the lattice, behind the string spool, its plinth's back GRAINS_GAP (5 cm) off the
    lattice and its middle GRAINS_IN (1.6 m) back from the lattice's front, facing across the aisle
    toward the riser. Side on to the desk, it hides nothing the seat clicks (the venue's instrument on
    the back wall), and it stands far enough up the aisle to leave that instrument's floor free. The
    loft's aisle is the harp's, the bells' and the music box's, so `LoftVenue.default_grains_spot`
    stands it on the open floor beside the desk on the right, ahead of the steam pipes. Its folded
    plaque hangs on the plinth's side toward the desk, since the cloud stands side on to it (on its
    front it was edge on to the seat, and the seat audit could not click its BACK); the KEY switch is
    on the front. Its footprint is in `wheeled_solids`.

    - The bowl is the room's holder `bowl` of one slot (ItemRoom.HOLDS takes cassettes; laid by
      `Studio._hold_the_bowl` wherever the trolley stands, again when it is pushed). The cassette in
      it is made into mono at `GrainVoice.RATE` (24 kHz) on a worker, as the platter makes its own:
      a sample's or an audio clip's file (`find_file`, the platter's; a guest's fetch with FileSend,
      the tag FETCHING meanwhile), a MIDI clip's render or a demo part's window
      (`CassetteItem.sound_work`), 30 s at most. Its length lies left to right as 40 columns of motes,
      each as bright as its stretch is loud (`GrainVoice.envelope_of`, `mote_level`); START, END with
      the length, and LONG GRAINS letter the cloud's edges. Empty, the motes are faint and grey and
      the tag says PUT A SAMPLE IN THE BOWL; a file not here says NOT ON THIS MACHINE.
    - The law: `at_for` across, `length_for` up (20 to 200 ms), `density_for` in, away from the
      player (4 to 60 grains a second, each step the same proportion), `place_for` the inverse. The
      spray is a bare hand's thumb-to-little-finger span (`spread_of_span`, 5 to 17 cm), a
      controller's grip travel, or at a desk the wheel, up to 30% of the sound either way. The hand
      is the nearest the middle of every confident tracked palm and sure controller in the cloud
      (`local_hands`, or `hands` for the suite and `--grains`).
    - Events, never the hand: each EVENT_HZ (30) window, `play_window` reads the hand into an event
      (`GrainVoice.event`: tick, at, length, density, spread, pitch; `is_event` checks one), keeps it
      in `events` (the newest 300) and plays it; no hand, a rest. `GrainVoice.Renderer` makes a
      window's grains from its event alone, onsets and places drawn from a generator seeded by its
      tick, each read at its pitch under a Hann window, LEVEL over the root of the overlap, at most
      MOST (32) sounding, carried window to window. `GrainVoice.render(sound, events)` is the same
      Renderer over a list, so the live voice's output (`kept`, while `keeping`) is the render of
      its events sample for sample: what slice 55 sends and records.
    - Heard on this player's MONITOR through an AudioStreamGenerator (PREROLL queued ahead), at
      `latency_seconds`. Rung out, the voice feeds the card silent windows (none of them `kept`)
      for IDLE before it lets its player go, so a hand back within half a second (a button let go
      and pressed again, a hand slipping past the cloud's edge) plays on with no gap; a card found
      with nothing left queued (a long frame) is given PREROLL again. The figure is on the tag and
      the cassette's (`GRAINS · MONITOR 82 ms`), and the tag says
      in words what plays (`at 10.20 s · 120 ms grains · 15 a second · spray ±15%`). Sparks light
      where each grain starts and a bar shows the spray at the hand; their drift and the motes'
      shimmer go by `Ergonomics.motion_scale`.
    - KEY, the room's row `grains_key` (verb `grains_key` [bool] in Session.ROOM_VERBS, predicted as
      the weather's switch is, `Studio._on_grains_key_pressed`, kept across venues in
      `Studio.grains_key`), pitches every grain by the chord's root from the key's tonic, the nearer
      way round: a fourth down to a tritone up (`pitch_for`, from `ChordHand.at`).
    - At a desk: `GrainCloud.Face`, the cloud's front, takes only a mouse's button: held, it plays
      from where it is held, dragged from where it is dragged; the wheel over it is the spray
      (`desk_spread`), and Shift with it the density (`desk_density`), since the face has no depth.
      The bowl (`GrainCloud.Bowl`) takes a click with a cassette in the hand. The PLAY page, the
      toasts, the I walk and the hover cards say all of it; a headset lets a cassette go over the
      bowl and reaches in.

    The suite (tests/run_tests.gd): `_test_a_hand_in_the_grain_cloud_is_where_how_long_and_how_many`,
    `_test_a_grain_clouds_spray_widens_where_its_grains_play_from`,
    `_test_the_same_grain_events_render_the_same_sound` (and the live voice equal to the render of
    its events, no click in a steady sound grained, the 32-grain cap, MONITOR),
    `_test_a_sample_a_midi_clip_and_a_demo_part_each_fill_the_grain_cloud` (and the empty and the
    missing file's words), `_test_a_desk_plays_the_grain_cloud_by_holding_its_face_and_the_wheel_sprays_it`,
    `_test_the_grain_clouds_key_is_the_rooms_and_follows_the_chords_root` (KEY kept on across a
    venue changed while the bowl's sound renders on a worker),
    `_test_a_grain_cloud_let_go_and_played_again_is_heard_without_a_gap`,
    `_test_a_headsets_hands_and_controllers_play_the_grain_cloud` (`local_hands`); the station
    lists of the clearance loop, the help card, I and the headset's board have it, and every venue
    stands it clear with its air.

    shots/spatial54.png is a hand in the cloud (`SHOT_ARGS "--no-hud --grains"`, `SHOT_CAM
    "-1.85,-0.12,1.55,-0.05,1.2,5.3"`, frames 120 and 126 so the demo part's render is in): the first
    clip of the song in the bowl, its motes lit by the kick's loudness, the spray bar at the hand a
    third of the way across, and the tag saying what plays. shots/spatial54_aisle.png
    (`SHOT_CAM "2.75,-0.18,2.6,-0.1,1.1,5.1"`) is the cloud from the aisle's mouth, side on beside
    the string spool, its plaque on the side toward the desk. `--grains` puts a cassette of the
    song's first clip in the bowl and holds a hand of the shot's own in the cloud.

55. [x] **The grain cloud, recorded and heard.** #24 finished. A player's grain events (hand place,
    spread and length, 30 a second, stamped with `song`) go to bandmates by `Session.send_grains`,
    reliable on GESTURE_CHANNEL (its own, so a lost one is resent and never holds a note back), a
    few bytes each. Bandmates render the same grains from the same sample. A bandmate without the
    sample's file fetches it once with FileSend, and the cloud's tag says FETCHING. Recording keeps
    the events and renders them to a WAV audio take at the take's end, as decided. Since the live
    voice plays from the same events, the take's render equals what the player heard. Touches
    session.gd, grain_cloud.gd, grain_voice.gd, file_send.gd, presence.gd, studio.gd,
    tools/probe/session_probe.gd. The suite checks: events round-trip; a guest without the file asks
    once; the take's render equals the live render sample for sample; the take's start. The probe
    checks a guest's grains landing as the host's audio take, equal to the guest's own render. Both
    sides at 0 failed.

    Built. Every event the cloud plays is `GrainCloud.played`, and the studio sends it with
    `Session.send_grains(e, GrainTakes.song())`: the song the player hears (GuestMidi.heard) moved on
    by the cloud's own figure (`GrainVoice.latency_seconds`), since they hear its grains that much
    later, or -1 while the song is not playing.

    - On the wire an event is fourteen bytes (`GrainVoice.pack`, `unpack`): its tick in 32 bits and
      its five numbers in 16 each, on grids nothing is heard of (a 60000th of the sound, 10 µs of a
      grain, a thousandth of a grain a second, a hundred-thousandth of the spray, a cent).
      `GrainVoice.event` puts every number on its grid as it makes one, so the event played and the
      one a bandmate unpacks are the same numbers and render the same samples. Reliable and ordered
      on GESTURE_CHANNEL with the knobs (`_grains_up`, `_grains`), through the host, which refuses
      bytes that are not an event (`Session.grains_refused`) and passes the rest on
      (`Session.grains_played`).
    - Heard by the band: `Presence.grains_heard` gives a bandmate's events to the studio's cloud
      (`GrainCloud.hear`), which plays them on a `GrainVoice` of theirs (`theirs`, `voice_of`) from
      its own sound, out of the air at the cloud on the gear bus (`GrainVoice.speaker`, a
      `Foley.emitter`, 3 dB down). It begins THEIRS_WAIT (3) windows after their first event, then
      each window plays its own tick's event or a rest, so uneven arrival is ridden over and what is
      heard of them is the render of their events; one arriving after its window is dropped, and
      more than THEIRS_MOST (12) waiting skips ahead. Their grains light the sparks where they play
      from, the tag says `Grace is playing it · reach in too`, and a bandmate gone is let go
      (`forget`). The cloud's hover card now says the band hears it, and the PLAY page that the
      grains go onto the armed track as audio while the song records.
    - A guest whose bowl holds a sample it has no file of asks the host once (FileSend.fetch through
      `Studio._platter_file`, as slice 54 already did), the tag FETCHING meanwhile, and nothing of a
      bandmate's grains plays until the sound is in. file_send.gd needed nothing new.
    - Recorded: `Session.grain_takes` (`GrainTakes`, core/session/grain_takes.gd) gets each event as
      it is sent (`played`). While the song records as the player hears it (`rolling`, past any
      count-in and inside any punch range), the first event begins a `GrainTake`
      (core/audio/grain_take.gd: the events and each one's song) onto the keys' chosen track or the
      armed one (`GrainTakes.track`); with neither, the player is told once a recording. Recording
      heard to stop ends it (`finish` drops anything stamped past its end), kept as `last_mine`. A
      guest marks the take begun and ended to the host (`Session.send_grain_take`, `_grain_take_up`)
      on the same channel as its events, so the host takes exactly the events between the marks
      (`heard_event`, `heard_mark`); a third player's and those from before the begin are not in it.
      Ended, the host renders it from its own copy of the cloud's sound (`GrainTakes.sound`, the
      studio's `grains_sound`), writes a WAV at AudioTake.RATE (`GrainTake.at_take_rate`: every other
      sample the render's own, the one between halfway) on a worker thread, and puts it in as an
      audio take named `grains` at its first event's song (`GrainTake.lands`) on the player's behalf,
      both sides told. A host with no sound in its bowl places nothing and says so.
    - The render keeps the events' spacing, a window a tick, so a hand let go mid-take is a gap of
      its length in the take; the cloud now counts the ticks of windows a long frame made it miss,
      so its ticks keep the clock's time. Since the live voice plays the same events through the same
      Renderer, the take of an unbroken gesture is what the player heard, sample for sample. A take
      begun with grains already ringing from before recording starts without their tails, as a
      recording begun mid-note does. A long take is a long render: it runs on the worker, about as
      fast as the cloud plays.

    The suite (tests/run_tests.gd): `_test_grain_events_go_to_bandmates_in_a_few_bytes_and_come_back_the_same`
    (200 events round-trip, their renders equal, refused bytes counted, reliable on GESTURE_CHANNEL),
    `_test_a_guest_without_the_grain_clouds_sample_fetches_it_once` (two seconds of looking, asked
    once, FETCHING, a bandmate's grains not played until it is in),
    `_test_a_grain_take_is_what_its_player_heard_where_they_heard_it` (nothing kept unrecorded, told
    once with no track, the take's render equal to what the cloud played sample for sample, placed
    at its first event's song moved on by the figure, its WAV the render at the take's rate, a gap
    kept), `_test_a_guests_grain_take_is_rendered_by_the_host_from_its_own_sound` (only the events
    between the marks, the host's WAV the guest's own render),
    `_test_a_bandmates_grains_play_from_the_cloud_as_their_events_render` (uneven arrival, the late
    one dropped, the emitter at the cloud on the gear bus). The desk test now looks for "the band
    hears it" on the cloud's card, where it said "in your ears alone". The session probe
    (`_play_the_grains`, `_check_the_grain_take`, from 63.88; the session now ends at 64.32) checks
    a guest's twelve grain events heard in order on the host and landing as one audio take named
    `grains` on TAKE_TRACK at the guest's first event's song, whose digest equals the guest's own
    render; it was not run with this slice (the checkpoints run it).

    shots/spatial55.png is a bandmate playing the cloud (`SHOT_ARGS "--no-hud --grains-band"`, the
    slice 54 camera, frames 120 and 126): the first clip in the bowl, its motes lit, and the tag
    saying `Grace is playing it · reach in too`. `--grains-band` feeds Grace's events to the cloud
    each frame as `Session.grains_played` would; with `--grains` the shot's own hand plays too.

56. [x] **Lyrics in the booth.** The proving idea, #26. `DAW.set_lyrics(text)` and MixState.lyrics
    as decided. `Lyrics` (core/music/lyrics.gd) parses and writes LRC and answers the line at a
    time. Reaper keeps them in the project notes, in a `[lyrics]` block, through the bridge. The
    built-in engine's .dawproject keeps them in the project's metadata comment. One undo step,
    Capability LYRICS. `LyricBoard` (core/music/lyric_board.gd, station `lyrics`, zone `vocals`)
    stands in the vocal booth at eye height (Ergonomics.eye_height), facing whoever stands at the
    mic. It shows three lines: the last dim, the current large with a bar under it and a mark before
    it, and the next. It scrolls with the song, a line a step at motion 0, and says how to add
    lyrics when there are none. Editing: the board's EDIT opens the typing pad, and at a desk the
    session panel's new LYRICS box. Lines with no time are timed by TAP: while the song plays, TAP
    (a big key on the board, or Enter at a desk with the board clicked) stamps the next untimed line
    at the position heard. Touches daw.gd, daw_backend.gd, offline_backend.gd, project_files.gd,
    reaper_backend.gd, dawlings_bridge.lua, mix_state.gd, lyrics.gd, lyric_board.gd,
    session_panel.gd, studio.gd, stations.gd. The suite checks: LRC round-trips; the current line at
    times; TAP stamps in order; undo; save and load keeps them; the bridge decodes the notes block;
    a guest's set_lyrics intent; the board stands clear of the mic stand in every booth. The probe
    checks a guest's TAP in the host's lyrics. Both sides at 0 failed. shots/spatial56.png is the
    board mid-song.

    Built. The song's lyrics are one LRC text, `MixState.lyrics`, on the wire as `/timeline/lyrics`
    (durable, in the snapshot, `lyrics_changed` on a change). `DAW.set_lyrics(text)` cleans it
    (`Lyrics.clean`: a line at most LINE_MOST, the whole MOST, the block's own `[lyrics]` and
    `[/lyrics]` lines taken out) and is a COMMAND, so a guest's is a `set_lyrics` intent the host
    checks (one text, not too long) and makes. Offline it is one undo step named `lyrics`. On Reaper,
    LYRICS is there only with the bridge open: the bridge's `SetLyrics` rewrites the `[lyrics]` block
    of the project notes (its `lyrics_into_notes` is `Lyrics.into_notes`, line for line, everything
    else in the notes left alone) inside one Reaper undo block, and GetTimeline returns the notes, so
    the poll reads the block back (`Lyrics.from_notes`). The built-in engine's .dawproject keeps them
    as its metadata.xml's Comment (`ProjectFiles._keep_lyrics`, read back by `lyrics_of` when it is
    opened).

    `Lyrics` keeps lines in the order written, each with its time or UNTIMED, a blank between verses
    kept as one break. Tags (`[ar:]`, `[ti:]`, `[offset:]`) count only on a line of their own, so
    `[Chorus]` stays a line of words. A line with several stamps is one line for each. `at(seconds)` is
    the latest timed line shown by then. `sequence()` is the timed lines by time, then the untimed in
    order, so `tap(seconds)` stamps the first untimed line, to the hundredth with the offset put back.

    The board stands on the booth floor beyond the mic stand (`Venue.lyrics_spot`, IN_BOOTH), facing
    the singer at the mic and built to the player's eye height. Its three lines are a scroller: the
    last small and dim, the sung one large (55 mm caps, 2.4 degrees from the mic) with ▶ before it and
    a bar under it that fills toward the next timed line, and the next. The next one TAP will time
    reads `TAP ›` before it, so the mark is in words as well as colour. A line on, the three glide up
    for GLIDE scaled by Ergonomics motion, and at motion 0 they step. With no lyrics it reads `No
    lyrics yet` and `EDIT adds a line · at a desk, M: LYRICS`; the row along its top counts the lines
    and those left to TAP. Everything on the face is above the mic's body as the singer sees it. The
    folded plaque hangs beside the face on the singer's right, held by an arm off the post: from the
    mic, everything below the eye near the middle is behind the mic and its boom. TAP is a big key
    (a press); EDIT a small one, dwell-able, which in a headset opens the TypingPad by the singer's
    right hand (`PAD_AT`), the words typed added as a line at the end, and at a desk opens the session
    panel's LYRICS box (a text box with Set lyrics and Untime). A click on the board's face arms it,
    and its top row then says `ENTER TAPS · Esc lets go`; Enter TAPs (not while Z is held) and Esc or
    another click lets go. A write a guest asked for is shown at once and believed for PREDICT_MSEC,
    until the host's own arrives. The board, the station row (`lyrics`, LIVE, zone `vocals`, frame from
    the board's top to its plaque's opened foot) and a ZoneKit solid for its foot are new. `--lyrics`
    sets a demo song and plays the board at 7 s, for shots.

    The suite (tests/run_tests.gd): `_test_lyrics_round_trip_as_lrc` (tags, multi-stamp lines,
    breaks, offset, clean, `[Chorus]` kept as words), `_test_the_line_sung_at_a_time`,
    `_test_tap_stamps_the_next_untimed_line_in_order`, `_test_the_lyrics_are_one_undo_step`,
    `_test_the_lyrics_save_and_open_with_the_project` (the .dawproject's comment),
    `_test_the_bridge_keeps_the_lyrics_in_the_notes_block` (from_notes and into_notes, LYRICS
    only with the bridge open, the poll, a write cached at once and sent as SetLyrics), `_test_a_guests_lyrics_are_an_intent`, and
    `_test_the_lyric_board_stands_clear_of_the_mic_stand_in_every_booth`. That last one stands the
    board in all 42 booths (fourteen venues, three variants each): its foot clear of the stand and the glass, facing the singer, and from
    the singer's eye every line, key, plaque corner and plaque title seen past the pole, the boom and
    the mic (MicItem's model, 0.053 across). It also checks the frame's foot, the empty and mid-song
    faces, the glide and the step, and TAP and EDIT by a hand and by Enter. The station tests now
    count sixteen live room stations and look for `lyrics` among them, the headset's station board
    lists it, and no face of it shares a plane with another (it stands on what the mic stand stands
    on, the studio's felt or a millimetre over the floor, and the plaque's arm is under the plate's top). The session probe
    (`_tap_the_lyrics`, `_check_the_guests_tap`, from 64.32; the session now ends at 64.56) checks
    that a guest's board writing two lines and then TAPping lands in the host's lyrics, the first
    line stamped at the song the guest heard and the second untimed. It was not run with this slice
    (the checkpoints run it). Reaper's own undo of the notes was not tried on a live Reaper.

    shots/spatial56.png is the studio's booth mid-song (`SHOT_ARGS "--no-hud --lyrics"`, `SHOT_CAM
    "-1.5708,-0.05,1.45,-4.84,1.5,5.85"`): the mic in front, `Wires hum beneath the floor` dim,
    `▶ Every fader finds its place` large with its bar half filled, `We tune the room until it's
    ours` under it, the TAP and EDIT keys, and the plaque beside the face.

57. [ ] **The song in the sky.** The proving idea, #27. At night venues (`Venue.night()`: the
    rooftop's Night, every cabin, the station, the desert's Starlit canyon, the loft's City night,
    the grid's Neon sea, and the garden's Winter after dark), `SongSky` (core/venues/song_sky.gd)
    draws each section (a region, else a marker's span; notes skipped) as a constellation. Its stars
    are a hash of its name, as many as its bars, with its name lettered beside it, on one great arc
    that stands still across the sky, from the first section low in the east to the last low in the
    west. The sky never turns: a moon, a small lit disc lettered with the section's name, moves
    along the arc to where the song is (about a degree a bar), so you look up to see where you are,
    and the current constellation is brighter and its lines drawn. At motion 0 the moon steps at
    each section's start. Nothing that fills the view moves. Touches song_sky.gd, venue.gd and the
    night venues (a sky layer each), studio.gd. The suite checks: the night list; a constellation a
    section; the stars' places are the same at every song position; the moon's angle at song
    positions; it steps at motion 0; none in daylight variants. shots/spatial57.png is the rooftop's
    Night sky mid-song.

58. [ ] **A talk box: the voice as a chord.** The proving idea, #39, first half. `TalkBox`
    (core/audio/talk_box.gd) is a channel vocoder from Godot's own effects. The mic's bus (MicArm's
    input) carries an AudioEffectSpectrumAnalyzer (a 512-point FFT) read every frame in 13 bands,
    the centres of AudioEffectEQ21's bands from 125 Hz to 8 kHz (its bands 6 to 18). Their envelopes
    set those 13 band gains of an AudioEffectEQ21 on a carrier, and the bands outside are held at
    -60 dB: `ChordCarrier`, a bright chord voice playing this player's chord. That is their chord
    hand's (32) when a shape is held, else the song's (Harmony.at), voiced at 48. A tube hangs from
    the booth's mic stand (station `talk_box`, zone `vocals`). Taking its end to your mouth (within
    0.12 m of the head, as the ear) turns it on. At a desk the booth's TALK key does, with the chord
    from the chord layer or the song. Live, as decided, it is heard by its player alone, on MONITOR
    at about 60 ms (said on its tag): bandmates do not hear any mic live today, and the talk box
    does not change that. They hear its take (slice 59). Touches talk_box.gd, chord_carrier.gd,
    mic_arm.gd, chord_hand.gd, zone_kit.gd (the tube), studio.gd, stations.gd. The suite checks,
    with a test signal (a pulse train through two formants) in place of a voice: the output's band
    gains follow its formants in the 13 bands; the carrier's pitch classes are the chord's and
    follow a shape; on and off by the tube at the mouth and by TALK; the tag's figure.
    shots/spatial58.png is the tube at the mic stand.

59. [ ] **The talk box, recorded and heard.** #39 finished. While the talk box is on, the voice
    recorded is its output, not the dry voice. A guest records it the guest's way: GuestAudio's
    take, captured from the talk box's bus instead of the mic's, placed by song position and sent to
    the host. A host has no GuestAudio, so `BusTake` (core/session/bus_take.gd) is GuestAudio's
    placing without the network: a capture on a bus of this machine, its start the median of its
    first second's estimates, inserted with insert_audio_take. The host's own input arm for that
    track is held off meanwhile, since Reaper would record the dry input. The take is named
    `talkbox`. Bandmates hear it as they hear any take: once it is in the project, played by the
    host's engine and its mix stream. Touches talk_box.gd, guest_audio.gd (its source bus),
    bus_take.gd (new), mic_arm.gd, studio.gd, tools/probe/session_probe.gd. The suite checks: a
    guest's take recorded with the talk box on is the processed bus's; a host's BusTake places a
    test signal within 5 ms of where it was played; the host's arm is held off and restored; the
    take's name and start. The probe checks a guest's talk-box take on the host. Both sides at 0
    failed.

60. [ ] **Stations in a real room.** No new idea; it is every station in AR, as decided. In AR, the
    station board's rows say PLACE. A press on one, then a dwell (a fingertip, or a controller's tip
    with its trigger held, still 0.6 s, as the pads are marked) on the real floor or a real surface,
    stands that station there, facing the player. Where each stands is a room row (`placed` {station
    id: Transform3D in the session frame}), asked with the room verb `place_station` [id,
    Transform3D] and checked by the host as `place_surface` is: on a floor or a surface, clear of
    the other placed stations by their `air`. So bandmates in the same AR room see them where they
    are. A placed station has its plaque with a MOVE key, and the PLAY page names it. Nobody travels
    in AR: the room is real, and you walk. A venue's instruments and the weather have no venue there
    and stay away. Touches stations.gd, station_board.gd, studio.gd (the AR branch, every station's
    stand reading `placed`), session.gd (`place_station`), tools/probe/session_probe.gd. The suite
    checks: in AR, an unplaced harp is null and its row says PLACE; a dwell stands it at the point
    facing the player; a second station too close is refused with the reason; MOVE moves it;
    placements survive a publish and a recalibration; the PLAY page's lines in AR. The probe checks
    that a guest's placement in an AR session reaches the host's row. Both sides at 0 failed.
    shots/spatial60.png is a placed harp, shot with `--ar`.

# Part three: seeing the signal

Goal: "the complication of trying to get a sound out the way I want it -- normal DAW stuff, but now
we're in 3D." A desk answers "is it loud" with a meter and "why is it silent" with nothing. This
part makes the room answer both where the sound is: put on a pair of signal glasses and the audio
path is drawn as glowing pipes from every source to its track, along the sends and folders to the
master and out; where the signal stops, the pipe ends at a sign saying why in words; point at
anything that should sound and ask, and the chain lights a stage at a time to the first break,
with a one-press fix where one is safe. Under both, one model of the path with a level at every
stage (`SignalGraph`), fed by real taps on the built-in engine, by Reaper's meters and the bridge
where Reaper has them (estimates marked `≈` where it does not), and by the host's meters on a guest.
Same rules as parts one and two: `godot --headless --path . --editor --quit` after a new
class_name, targeted tests while building and the whole suite once at the end, a shot of what
changed (shots/signalN_*.png). Desktop first: every mode has a key, a hover card and an F1 line,
and the HUD still fits 1600x900. No signal by colour alone: every amber and red carries its words
and its number.

## Part three: decisions

- **One model of the path, built from the mix and nothing else.** `SignalGraph`
  (core/audio/signal_graph.gd, pure, RefCounted) is built from a MixState and a list of the room's
  sources, so a host, a guest and the suite build the same graph from the same cache. Its stages
  (`SignalGraph.Stage`) are, per track `N`: `tN:play` (what the track itself plays: its items),
  `tN:in` (what arrives at the track: items, takes, a live input, its folder children), one
  `tN:fxK` a plugin slot in chain order, `tN:fader` (fader, pan, mute, solo, the master/parent
  send), one `tN:sendS` a send slot; then `master` and `out` (the speakers). A room source is
  `src:<id>` and feeds the track it reaches. The main road from a track is in, its plugins, its
  fader, then its folder's `in` or the master; a send is a branch from the fader (post-fader) or
  from the last plugin (pre-fader) into its destination's `in`; a key send (a sidechain) is a
  branch that goes to a detector, never to the ears.
- **A source is a row the studio gives**: `{id, title, track, kind, jacked}`. `kind` is `notes` (an
  instrument: heard live on this machine's MONITOR, and onto a track only when it is recorded: its
  jack's track whether armed or not, else the armed track), `voice` (the mic: the track's live input,
  heard through the DAW's monitoring), `playback` (a station whose sound is notes on a track, as the
  music box's pegs are) or `local` (heard in your own ears only: the sampler, the grain cloud and
  the platter, which reach a track as a cassette pasted onto it). The graph knows no node in the
  room; the view puts each stage somewhere.
- **A break is a stage with a reason, and the reasons are words.** `Stage.halt` is one of
  `muted`, `soloed_out` (another track is soloed, read as the built-in engine's solo-in-place:
  a soloed track's folders and the returns it sends to stay up), `fader_silent` (the fader at
  −∞), `send_silent` (a send at −∞), `monitor_off`, `not_armed`, `no_input` (a record input the DAW
  does not list), `plugin_silent` (a plugin with signal in and none out, from levels), `instrument_
  bypassed` (an instrument plugin, type ending in `i`, bypassed: it plays nothing), `no_route` (no
  master/parent send: Reaper's B_MAINSEND off), `folder_muted` (its folder is muted, said where a
  trace reaches the folder from a child), `stopped` (the transport is stopped, for a track's own
  playback), `empty` (nothing on the track to play), `no_track` and `local`. An effect bypassed is
  not a break (the sound passes dry) and its stage says `bypassed`. `Stage.why` is the sentence on
  the sign, naming what does it: `muted`, `soloed out: KICK is soloed`, `send at −∞`.
- **A fix is one DAW intent, one undo step, or none.** `Stage.fix` is `{label, verb, args, step}`:
  UNMUTE (`set_track_mute`), UNSOLO (every solo let go), FADER TO 0 dB, SEND TO −12 dB
  (`set_send_volume`), MONITOR ON, ARM, BYPASS OFF (`set_fx_enabled`), SEND TO MASTER (a new verb,
  `set_track_main_send`), MASTER TO 0 dB and PLAY. `SignalGraph.apply_fix` runs it inside
  `DAW.open_edit(step)` / `close_edit`, so a grouped mute or an unsolo of three tracks is one Ctrl-Z,
  and through `DAW`, so a guest's fix is an intent the host carries out. A plugin that outputs
  silence, a missing record input and a source heard locally have no fix: the sign says what to
  do. Play is not an edit and leaves no step.
- **Levels are dBFS at every stage, measured where they can be, estimated where they cannot, and
  marked.** `Stage.peak_db`, `rms_db`, `gr_db` (NAN where nothing reports a gain reduction),
  `measured`, `estimated`. Thickness is the peak, smoothed (fast up, slow down) and mapped from
  FLOOR_DB (−60) to +6 dBFS; colour is health: the track's colour while under HOT_DB (−3),
  amber from there to 0 dBFS, red pulsing over it, and every amber and red stage carries its number
  (`−1.2 dBFS`, `CLIPPING +2.3 dB at BASS DI fader`). An estimate's figure starts `≈`.
- **The meters live in MixState and ride the mix's own stream.** TrackState gains `meter_peak` and
  `meter_rms` (PackedFloat32Array, dBFS: the input, then after each plugin in chain order),
  `meter_gr` (dB per plugin, NAN none) and `meter_sends` (dBFS per send slot in order), empty when
  this DAW cannot measure them; and `main_send`. The backend writes them as one volatile key a track,
  `/track/N/vu/signal` [peak, rms, gr, sends], at METER_SEND_HZ (10), so the host's replication
  carries them to guests unreliably at a modest rate, parcelled with the other meters, and a guest's
  graph reads them as the host's. `/track/N/mainsend` is durable and in the snapshot.
- **Built-in engine taps are real and cost nothing until asked.** While anyone wants stage meters
  (`DAWBackend.want_signal_meters`, kept alive SIGNAL_KEEP_MSEC by whatever draws them, and always
  while guests are connected, since any of them may put the glasses on), each track gets meter probes:
  a bus a stage, `R3D Meter N@K`, holding the track bus's own effect objects up to stage K (none for
  the input), played by one more playback of the track's lane (as a cue is) and sent into the muted
  KEYS_BUS, so nobody hears them. A probe's peak is the AudioServer's own bus peak (exact, no script
  loop); its RMS is an AudioEffectCapture at the probe's end, read at METER_HZ (30), at most
  RMS_FRAMES a read, every second frame, and cleared. Post-fader is the track bus's peak, each send
  its send bus's, a folder's sum its own bus's, the master the master bus's: all exact. A
  compressor's gain reduction is derived from its probes (RMS out less RMS in less makeup) and
  marked derived; Godot's compressor does not report one. Limits, said: the probes hear what the
  track plays (items, MIDI through its instrument, takes), not a live input monitored straight
  into the track bus, so with a live input the stage meters are those of its playback; and each
  probe runs its effects once more, so they are torn down SIGNAL_KEEP_MSEC after the last ask.
- **Reaper has a track's meter, not a stage's.** OSC streams each track's post-fader peak (vu) and
  each send's level. The bridge's `GetMeters` adds what ReaScript has: each track's peak and peak
  hold (Track_GetPeakInfo, Track_GetPeakHoldDB), its B_MAINSEND, and each plugin's gain reduction
  where the plugin reports one (TrackFX_GetNamedConfigParm "GainReduction_dB": ReaComp, ReaXcomp
  and plugins that implement it), polled at METER_POLL_SECONDS (0.25) while meters are wanted. There
  is no per-plugin in/out peak in the API, so on Reaper a plugin's stage and the track's input are
  `not measured`, the fader is measured, and a send is estimated from the track's meter and the
  send's level (post-fader: track peak plus send dB; pre-fader: less the fader too), marked `≈`.
  `plugin_silent` is never claimed there.
- **The glasses are this player's alone.** A pair of signal glasses lies on the prop shelf
  (`SignalGlassesItem`, kind `glasses`, a personal kind as the headphones are: a copy of your own).
  On your head they turn on the signal view for you; bandmates see them on your ghost, and their
  room is unchanged. At a desk, X toggles the view with or without the pair ("x-ray"; G is taken by
  the gear's summoning). The view's on-ness is never room state, never sent, never published:
  `Studio.signal_view_on()`. The glasses share the head with the headphones (Interactor.worn is one
  slot), so putting one on sends the other home; the X key is not limited by that.
- **What the view draws** (`SignalView`, hardware/signal_view.gd, given the graph and a callable
  that places a stage): one pipe a road between places, a source to its track's place (the stage
  table's voice, else its console strip), a track to its folder's, a send to its destination's, a
  track to the master section, and the master to OUT over the desk. Each pipe is a tube of
  segments drawn as one MultiMesh (one draw call for the room's pipes), on the lamp material,
  glowing. A road that stops ends at a sign (a billboard: the reason in capitals, the stage, the
  fix's key), a clipping stage gets a red tag with its figure. At Ergonomics.motion_scale 0 the red
  does not pulse and the glow alone carries it.
- **Why can't I hear this** (`SignalGraph.trace(from_id)`, B). With the view on, Y over anything
  that sounds (an item, a station, a stage voice, a channel strip, a control on one) traces from it:
  its source, or the track's own playback, along the main road to OUT. The trace card (beside the
  HUD's toast, and in a headset on the trace's sign) lights the stages one at a time (TRACE_STEP,
  0.18 s, all at once at motion 0), each with its level, and stops at the first break with its reason
  and its fix; Shift-Y or the card's FIX key (a click, a poke) does the fix. In a headset, a trigger
  held still on something for TRACE_HOLD (0.6 s) with the view on traces it; the fix is the sign's
  key. A trace of something that is heard ends at OUT with HEARD and the level at the master.

## Part three: plan

61. [x] **C. The signal graph and its meters.** Built. The graph, its fifteen reasons in words and
    their fixes (one undo step each, `SignalGraph.apply_fix`), the meter fields on the wire, the
    built-in engine's probes (a bus a stage with copies of the chain to it and a capture at its
    end, torn down SIGNAL_KEEP_MSEC after the last glance, kept while guests are connected) and
    Reaper's estimates with the bridge's GetMeters (per-plugin GainReduction_dB where the plugin
    reports one) and SetMainSend. Building it found two engine bugs, both fixed: a send's own
    player was played at full level, its send level overwritten by `_sync_players` (headless) and
    by LaneEngine's `_keep_playing`. As planned: `SignalGraph` as decided: `build(state, sources)`,
    `stage(id)`, `trace(from_id)` (the stages from it to OUT, stopping after the first break, with
    the reason and fix), `roads()` (every pipe: [from, to, level stage]), `clips()`, `clip_words`,
    `apply_fix(fix)`, and the statics `soloed_out(state, index)`, `health(peak_db)`, `thickness`.
    MixState's meter fields and `main_send`; MixWire's `/track/N/vu/signal` (volatile) and
    `/track/N/mainsend` (durable, in the snapshot). The built-in engine's probes, read at METER_HZ
    and written at METER_SEND_HZ, built while wanted and while guests are connected. The new verb
    `set_track_main_send` through DAW, the stand-in (undoable), the built-in engine (a bus with no
    master send plays into the muted keys bus) and Reaper (the bridge's SetTrackValue B_MAINSEND).
    The bridge's `GetMeters`, polled by ReaperBackend while wanted, and decoded into the same keys.
    Touches signal_graph.gd (new), mix_state.gd, mix_wire.gd, daw.gd, daw_backend.gd,
    offline_backend.gd, godot_backend.gd, reaper_backend.gd, reaper/dawlings_bridge.lua,
    tests/bridge_decode_test.lua. The suite checks: the graph's stages and roads for a plain track,
    a plugin chain, a folder and its children, sends post and pre and a key send; every break reason
    and its words, the solo-in-place cases, a bypassed effect is no break and a bypassed instrument
    is; the first break wins; each fix is one undo step; the probes with a known signal (a sine
    take: input, after a plugin, post-fader, the send, the master); the Reaper estimate path (`≈`,
    post and pre); a guest's graph reads the host's meters off the replicated stream; the bridge's
    GetMeters against the stand-in.

62. [x] **A. Signal glasses and the pipes.** Built. The pipes are one MultiMesh of short tube
    segments on arcs (the lamp shader, so they glow), as thick as the smoothed dB, the track's
    colour, amber at HOT_DB with the figure tagged, red and pulsing (still at Motion 0) past 0 dBFS
    with a CLIPPING tag; a stage nobody measures (an instrument nobody plays) is a thread; a stopped
    road is a stub and a sign, stacked where two breaks stand together; OUT carries the words
    "OUT · TO THE SPEAKERS" and the master's level. A track's stages stand at its stage voice, else
    its strip. The glasses share the one head slot with the headphones (putting one on sends the
    other home), which found a bug fixed in `Interactor.wear` (the hand lost what it carried when
    the old personal copy was despawned). As planned: `SignalGlassesItem` on the prop shelf
    (Venue.glasses_spot), a personal kind; X at a desk. `SignalView` as decided; the studio places
    stages (`_signal_place`) and lists the sources (`signal_sources`): every instrument item, the
    venue's set, the harp, the theremin, the modular, the looper, the mic, the music box, and the
    sampler, the grain cloud and the platter as local. Hover card and hint on the glasses; the F1
    ROOM page names X and Y. Touches signal_glasses_item.gd (new), item_room.gd, venue.gd,
    signal_view.gd (new), studio.gd, welcome_card.gd. The suite checks: the glasses toggle the view
    for the wearer only (a bandmate wearing them, in the room's state, changes nothing here; nothing
    of the view is in the room's state); X toggles it without them; the pipes' thickness follows the
    level and their health its figure; a muted track's road ends at a MUTED sign; a clipping stage's
    tag says CLIPPING with its figure and stage; the ROOM page still fits. shots/signal62_glasses.png
    (glasses on, the song playing), shots/signal62_clip.png (a clipping track), shots/signal62_muted.png
    (a muted break's sign).

63. [x] **B. Why can't I hear this.** Built. A white-hot bead walks the chain (a third of
    TRACE_STEP between stages that stand at one place, so it does not dwell on a voice), the lit
    roads drawn white over the pipe, red on the break; the card (desktop, top right) says each
    stage with ✓ and its level, the break with ✗, its heading and words, then FIX: LABEL (Shift-Y)
    or HEARD; the toast says it in a line; a FIX key stands by the break for a hand. After a fix the
    trace is run again (on a guest once the host has had RETRACE_AFTER to answer). As planned: `SignalGraph.trace` driven by the studio: Y (and the
    headset's held trigger) over a target, `signal_target_of(node)` resolving a control, a strip, a
    voice, an item or a station to the stage it starts from; the trace card stepping at TRACE_STEP;
    Shift-Y and the card's FIX. Touches signal_view.gd, studio.gd. The suite checks: a trace stops
    at the first break with its reason; a heard one ends at OUT; the fix is one undo step and the
    trace then runs on; a guest's fix is an intent the host carries out; a target with nothing to
    trace says so. shots/signal63_trace.png (mid-trace).

64. [x] **D. Pin-matrix header meters, pulsing pins, glowing crossings in hot rows (always on).**
    Built. Each row header of the routing bay carries a thin level bar (the track after its fader:
    peak fill, RMS mark, a held peak tick), a clip light that stays lit CLIP_MSEC after a peak over
    0 dBFS, and its figure on hover ("peak −6.0 dBFS · RMS −14.2"); each column header meters what
    arrives there, the peaks added as amplitudes (the worst case, said "peaks added"), with its own
    clip light, and a column whose sum passes 0 dBFS while no one send does says so in words: "OVER 0
    dBFS TOGETHER (+1.4 dB), though no one send is". A seated pin pulses with what its send
    carries (`SignalGraph.send_level`: measured on the built-in engine, else the track's meter and
    the send level, marked ≈), and is dull when patched but carrying nothing, its card saying
    "patched · no signal: <why>" from the graph's halt (the track muted, its folder muted, the
    transport stopped, nothing sounding). Empty crossings in a hot row (over HOT_DB) glow faintly
    amber. Cheap: only the visible lines and pins are read, at METER_HZ (30), once a second at
    Motion 0, every bar a slot of one MeshBank, nothing allocated per read. The AUDIO DEVICES wall
    meters its ports where dawlings can read them cheaply (below, E). Touches signal_graph.gd
    (fader_level, send_level, arrival_level, db_words), pin_matrix.gd, patchbay_surface.gd. The
    suite checks: a row's bar and clip light follow the track, the light holding after the clip and
    the bar falling rather than dropping; a column sums its senders and says a sum over 0 that no
    single send reaches; a send's card gives its level and what it carries, ≈ for an estimate and
    plain when measured; a pin carrying nothing is dull and says why; a stopped transport is said;
    a hot row's empty crossings glow; reading the meters makes no nodes.
    shots/signal64_bay.png (the bay with the song playing: row bars, clip lights, a hot row).

65. [x] **E. The pin-matrix skyline (glasses on).** Built. With the view on (glasses or X) each
    seated pin extrudes out of the bay into a column of light as tall as what its send carries
    (dB-mapped from FLOOR_DB to TOP_DB, `PinMatrix.level_share`), easing with the music (still
    between once-a-second readings at Motion 0); each column header stands a sum tower; a top is
    amber near 0 dBFS and red past it with a "+x dB" tag (TAGS of them at most, the loudest).
    Pointing at a tower lights its row and column, and its card reads "KICK → BASS DI" over "−6.0 dB
    send · peaking ≈ −3.1 dBFS". A tower's top is a control: dragged up or down (a desk's drag, a
    hand's pinch, or pulled out of the bay) it sets the send level, relative to where it was taken,
    the tower showing the new level while held, one undo step a drag (`edits_as_one`); the wheel is
    the pin's; a still press and let-go pulls the pin as a crossing's press does. Every write is
    DAW's, so a guest's drag is an open_edit / set_send_volume / close_edit intent. The AUDIO DEVICES
    wall: PipeWire reports volumes (pw-dump, pw-cli) and timings (pw-top), not levels; a port's peak
    would need a capture stream of its own on every port, as pavucontrol opens, which is not cheap.
    So the wall meters only dawlings's own streams, by the AudioServer bus each one plays
    (dawlings_mix, dawlings_monitor, dawlings_gear, and the app's own output by the Master bus),
    and on Reaper the REAPER outputs and dawlings_tap by Reaper's master meter; every other port's
    card says "level not measured: PipeWire reports none for this port", and its header has no
    bar. Towers stand there the same, from those levels. Touches pin_matrix.gd (Tower),
    patchbay_surface.gd, patch_wall_surface.gd, studio.gd (`_follow_skyline`). The suite checks:
    no towers without the view; a tower as tall as its level, louder taller, amber near 0 with its
    figure, red past it with "+x dB"; a column's sum tower; Motion 0; the card; a drag is one undo
    step and Ctrl-Z puts it back; a guest's drag is the host's intent; the view off takes them down;
    the AUDIO DEVICES wall meters dawlings's own streams and the app's output, and no other port.
    shots/signal65_skyline.png (the bay's skyline, X on, the song playing).

66. [x] **F. A LEVELS room off MIXING.** Built, as a wall: LEVELS, a station of its own set into
    a niche in the control room's front wall, left of the timeline (2026-10-30, from a trolley at
    the front left: "its own like divet in the wall so it can be an entire wall in each of the
    venues"). `Venue.levels_niche_spot`, 2.25 m in from the left wall; a plaster surround, sill and
    lintel standing out of the wall with a lit strip under the lintel, the board drawn
    LevelsWall.FACE 1.3 times its own measures (3.1 m wide), the master on its left; where the
    venue's wall is not one to build into (`back_wall_gear_stands`) a cabinet of the same stands
    0.75 m in. It never rolls (Trolley.built_in). `Venue.levels_spot`; in the MIXING neighbourhood, on the station
    list, the I cycle (after the EQ wall), the PLAY page and F1. Nothing stands closer than 0.6 m to
    it in any of the 14 venues and their 3 variants, at 13 tracks or 40 (tools/layout_dump.tscn,
    tools/layout_map.py; the pairs under 0.6 m that remain are the loft's and the club's own
    dressing, and at 40 tracks the desk and the deck's cart, none of them LEVELS). A column a track
    (`LevelsWall`, hardware/levels/levels_wall.gd), its peak after the fader against fixed lettered
    lines at −18, −6 and 0 dBFS, falling 24 dB/s, its held peak a tick and a figure over it (red
    "+2.5" past 0), its name under it, its fader's setting a notch at its side; a compressor's gain
    reduction a blue bar hanging from the top as many dB long, lettered "GR −4.1" (SignalGraph's
    `meter_gr`: worked out on the built-in engine, the plugin's own on Reaper). A column dragged up
    or down (click-drag, a hand's pinch) is the track's fader, a dB a dB of the scale, Shift-fine,
    one undo step a drag; the wheel 0.5 dB, Shift 0.1; a guest's an intent. More tracks than fit
    (16) scroll: drag or wheel the names, or ◀ ▶, the foot saying "TRACKS 1-16 OF 40". The master:
    short-term LUFS large, integrated (since play from stop, or RESET, a DAW verb) and momentary
    under it, from `LoudnessMeter` (core/audio/loudness_meter.gd), a BS.1770-4 meter: K-weighting
    (the two biquads, recomputed for the mix rate), 400 ms blocks every 100 ms, the absolute gate
    at −70 LUFS and the relative at −10 LU over a 0.1 LU histogram, a 4x Catmull-Rom true-ish peak,
    and the correlation over the last 300 ms. It runs on the built-in engine's master tap (a second
    AudioEffectCapture), fed on a WorkerThreadPool task so the frame does not pay for it, only while
    someone reads the wall (`want_loudness`, and while guests are connected), its readings sent to
    guests as the volatile `/master/vu/loudness`. Checked: a −23 dBFS 1 kHz stereo sine reads −23.0
    LUFS momentary, short-term and integrated at 48 and 44.1 kHz; silence after it is gated out.
    A TARGET key steps STREAMING −14, CLUB −8, BROADCAST −23 and CUSTOM (the wheel over it sets
    custom), this player's own, the loudness a bar against it and in words: "+1.2 LU OVER STREAMING
    −14", "3.4 LU UNDER CLUB −8", "ON TARGET" within 1 LU. TRUE PEAK "≈ −0.8 dBTP", amber within 1
    dB of 0 and saying "OVER 0: IT CLIPS" past it; PHASE a needle from −1 to +1 and in words,
    MONO-SAFE, WIDE ("check it in mono") under +0.5, and "OUT OF PHASE: in mono it cancels" under
    −0.3. On Reaper the loudness and phase are not measured and it says so (put a loudness meter on
    Reaper's master), the peak then Reaper's master meter "not a true peak". The wall reads only
    while this view's camera is within 7 m and turned to it. Touches levels_wall.gd (new),
    loudness_meter.gd (new), mix_state.gd, mix_wire.gd, daw_backend.gd, daw.gd, godot_backend.gd,
    stations.gd, venue.gd, neighbourhoods.gd, studio.gd, welcome_card.gd. The suite checks the
    meter (the sine, the gate, ±1 correlation, 44.1 kHz, RESET), the wire both ways, a guest's
    RESET as an intent, and the wall: a column a track, its top its peak, the held figure, the fall,
    the red figure and CLIPPING over 0, the gain reduction's length, place and letters, a drag one
    undo step, the wheel, a guest's drag an intent, "not measured", the LUFS, the verdict, the
    target key and custom, the true peak and the phase in words, scrolling a 40-track session,
    Motion 0; and the trolley: in every venue a station, clear, with room to stand at it, visited by
    F, riding its trolley. shots/signal66_levels.png (the built-in engine playing, loudness
    measured), shots/signal66_levels_40.png (40 tracks, scrolled window, a master over 0).

67. [x] **G. Look to solo.** Built. With the view on, hold U at a desk (the track under the cursor)
    or, in a headset, cup a hand to an ear -- a controller beside the head with its grip squeezed,
    or a bare hand held there, carrying nothing -- and the track looked at (the head's gaze, through
    `signal_target_of` as Y resolves it: an instrument is its track) is soloed alone: every other
    solo let go and its own mute lifted; while held the solo follows the look once it rests 0.3 s
    on another track; let go, every solo and mute it touched is put back exactly as it was
    (`LookSolo`, core/input/look_solo.gd), group-free (a grouped track's mates are not soloed with
    it). While one is held the view puts up no SOLOED OUT sign on every other track
    (`SignalView.quiet`): they are out on purpose. U without the view on says what it needs. History: one edit "Look to solo" is open from
    press to let-go, so a Ctrl-Z mid-hold puts every solo back; once let go the step changes
    nothing (a backend cannot drop a step from its history, Reaper's least of all, so "nothing left
    in the history" became "one step that does nothing"). A guest: there is no solo in one player's
    ears alone (a guest hears only the host's stereo mix), so a guest's look-solo asks the host (the
    room verb `look_solo` [track, held]), the toast saying so, and the host runs a LookSolo for that
    guest with its writes theirs (`DAW.on_behalf_of`) and tells the room who is soloing what. One at
    a time: a second while one is held is refused, saying whose it is. Never stuck: the window
    losing focus lets go (NOTIFICATION_APPLICATION_FOCUS_OUT), the view going off lets go, a guest
    leaving lets theirs go (Session.participant_left), and a project replaced forgets it. Said in
    the toast, in X's toast and the F1 ROOM line. Touches look_solo.gd (new), studio.gd,
    session.gd, welcome_card.gd, tools/screenshot.gd (`--signal look:N`). The suite checks: alone,
    its mute lifted, another's mute untouched; a glance does not move it, a rest does; let go, every
    solo and mute as it was; one history step, which undone changes nothing; group mates left
    alone; pressed at nothing it changes nothing; in the studio U needs the view, U over a strip
    solos its track and the let-go restores; focus lost and the view off let go; a guest's is run by
    the host, follows their look, refuses the host's own meanwhile, and their leaving or let-go puts
    it back. shots/signal67_look_solo.png (U held over RHODES, X on).
