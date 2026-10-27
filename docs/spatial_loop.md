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
    which the host refuses; the host holds G4 and bends it 4096 at 55.29 and lets go at 55.35; the
    guest's TheirKeys has the bend at 55.33 and has it at rest at 55.39.

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
    (6) and sees the key send come back by 58.65; the host finds it at 58.7 (and, on the built-in
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
    probe: the guest's bead rides BEAD_TRACK's fader at 58.72 to a clock of its own from 640 s, and
    the host finds its lane at those positions, a point each 50 ms, rising, let go, one step undone;
    the guest has the lane back by 58.8. The host's end moved to 58.9. shots/spatial22.png is the
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
    whose next sound it waits for (LISTENING FOR YOUR NEXT SOUND), so it is never colour alone.
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
    Not caught: what rings no take: the ball's squeeze, a bounce, a throw, the yo-yo's and the cards'
    tricks (FidgetItem plays them over time) and the keytar. Their `use_kind` is empty, so REC waits
    for something it can keep. Discoverable: the plaque and both help lines (PLAY · LIVE ROOM, the
    I walk), the REC key's hover card, the notice on each press and each catch, the screen, and the
    welcome card's TOGETHER page ("Sample it").

    `_test_a_squeeze_after_rec_is_one_sample_on_the_rack` checks:
    - the sampler stands beside the rack with its plaque and REC key;
    - REC off, a squeeze writes nothing, and the key and screen say off;
    - REC by the key is this player's, the room's row, said in words and lit, with a notice;
    - a squeeze in the presser's hand writes one WAV, byte for byte Foley's stream for its take at
      44.1 kHz, the squeak the duck rang, and it opens as a WAV;
    - one sample cassette, an audio clip of the whole file named for it, in the rack's first slot,
      REC off, the screen naming it, the presser told, and it pastes;
    - a second squeeze writes nothing; REC pressed twice is off and catches nothing;
    - with a guest's REC, the host's squeeze far from the mic catches nothing and REC stays on;
    - the ball's squeeze by the mic rings nothing it knows, and REC stays on;
    - the tambourine struck within reach is caught for the guest's REC, made by whoever struck it,
      onto the next slot;
    - a shaker shaken is caught as its take;
    - as a guest, the host's row shows; its own press is asked and shown at once, kept against a room
      that crossed it, and the answer is the room's; its own squeeze writes nothing.

    `_test_a_guests_squeeze_is_sampled_on_the_host_with_its_take` checks:
    - the take is cleaned as a hit's is;
    - a squeeze by someone not holding the duck is not caught;
    - hers, take 3, rings take 3 on the host's copy and is written as Foley's take 3, not 2;
    - the cassette is hers, on the rack, and REC is off for the room;
    - her second squeeze writes nothing;
    - her shake is caught as her take, shaken;
    - her REC off is the room's, and a REC ask is a yes or no.

    The probe: at 59.36 the guest asks REC. By 59.42 the room's `sampler` row is the guest. At 59.44
    it takes the duck, and at 59.48 squeezes it with take SAMPLE_TAKE (3). At 59.52 the host has
    heard that take. Its Sampler (as the studio's) has written one WAV equal to Foley's stream for
    it, made a cassette the guest made, and turned REC off, in the room too. By 59.56 the guest has
    the cassette's row, the room naming it, and REC off. The host takes them away at 59.58. The host's
    end moved to 59.6 and the guest's to 59.78. Not run with this slice: the checkpoint runs it.
    shots/spatial26.png is the sampler lit and listening, its screen saying so, beside the rack with
    the two sample cassettes on its top row
    (`SHOT_CAM="2.35,-0.28,1.75,-6.3,1.15,4.45" SHOT_ARGS="--samples 2 --hover 30,890"
    tools/shot.sh shots/spatial26.png 60 66`).

27. [ ] **A DJ platter.** The proving idea, #17. `Platter` (core/music/platter.gd, station
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

28. [ ] **A tape reel for undo history.** The proving idea, #11. The tape deck's supply reel gets a
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

29. [ ] **Sections rearranged, as one edit.** #9's verb. `DAW.arrange_sections(order)` takes the
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

30. [ ] **Song sections as blocks on a table.** The proving idea, #9. `SectionBlocks`
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
    front calls arrange once with [3, 1, 2]; no call while held; [ and ]; MAKE SECTIONS makes a
    region a marker and is one undo step; every venue's table holds the wheel, the blocks and the
    ledge clear of each other (the clearance loop); the mark follows the playhead (stepping at
    motion 0). shots/spatial30.png is the table with blocks and the wheel.

31. [ ] **Chord bricks, fed by the wheel.** The proving ideas, #16 and #29's feeding. `ChordBrick`
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

32. [ ] **Chord shapes on one hand.** The proving idea, #28. `ChordHand` (core/music/chord_hand.gd,
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

33. [ ] **Your chord hand drives their harp.** #33 finished. A `chord:P` jack source has a socket on
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

34. [ ] **The session in miniature.** The proving idea, #6. `MiniatureItem`
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

35. [ ] **Point, mark and listen together.** The proving idea, #7. Pointing: hold Z at a desk, point
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

36. [ ] **EQ as a wall of frequencies: spectra and clashes.** The proving idea, #8, first half.
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

37. [ ] **Carving the clash.** #8 finished. Grab a glowing overlap and push it into the wall to cut.
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

38. [ ] **Instruments that stand still.** No new idea; the drums, pads, venues' instruments and the
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

39. [ ] **Strikes on the fast path.** No new idea; it is the latency budget for everything struck.
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

40. [ ] **A circle of hand drums.** The proving idea, #30. `HandDrum` (core/items/hand_drum_item.gd)
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

41. [ ] **Drum pads on anything.** The proving idea, #10. `SurfacePads` (core/music/surface_pads.gd,
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

42. [ ] **Every venue has something to play: the first seven.** The proving idea, #19.
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

43. [ ] **Every venue has something to play: the other seven.** #19 finished. The loft's steam pipes
    along the brick (struck pipes), the station's hull ribs as a ring of tuned panels, the dome's
    glass vault's ribs (a touch rings the glass), the club's upright piano (its keys struck: the
    scale's notes, the black keys out of the key sunk; one source for the keyboard), the
    greenhouse's terracotta pots on a bench, the stage's row of tuned cymbals and a gong, and the
    desert's ringing stones (a lithophone on a rock shelf). The Rig Roulette room has none and says
    nothing. Touches the seven venues, venue_instrument.gd, foley.gd. The suite checks the same over
    all fourteen, and that every venue in Venue.IDS but the Rig Roulette room has one.
    shots/spatial43_*.png.

44. [ ] **Generative weather, and the cave's drips.** The proving idea, #20. `Weather`
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

45. [ ] **A looper, by hand: loops and layers.** The proving idea, #21, first half. `Looper`
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

46. [ ] **The looper's rings.** #21 finished. Each layer is a ring stacked round the looper's post,
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

47. [ ] **A music-box sequencer.** The proving idea, #15. `MusicBox` (core/music/music_box.gd,
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

48. [ ] **A string across the room.** The proving idea, #34. Strings are room rows (`strings` {id:
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

49. [ ] **A marble run.** The proving idea, #35. In the lattice zone, which no kept idea uses:
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

50. [ ] **A theremin.** The proving idea, #23, and #37 on it. `Theremin` (core/music/theremin.gd,
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

51. [ ] **A modular synth wall: modules and patching.** The proving idea, #25, first half.
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

52. [ ] **The modular, recorded and heard by the band.** #25 finished. Bandmates hear a player's
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

53. [ ] **The world plugs into the modular.** The proving idea, #31. As decided, the world's outputs
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

54. [ ] **A sample as a cloud of grains: playing it.** The proving idea, #24, first half.
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

55. [ ] **The grain cloud, recorded and heard.** #24 finished. A player's grain events (hand place,
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

56. [ ] **Lyrics in the booth.** The proving idea, #26. `DAW.set_lyrics(text)` and MixState.lyrics
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
