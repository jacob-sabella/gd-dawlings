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
