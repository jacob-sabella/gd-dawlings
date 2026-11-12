# The singer: CHIMERA's voice in the vocal booth, on the rack, in every venue

A physical model of a human voice, from the lungs to the lips, is the studio's singer. It sings the song's lyrics on
a MIDI track's notes, a syllable a note. It speaks English or IPA, beatboxes, becomes a creature, and its mouth can
be grabbed by hand. The voice is Jameson Hodge's CHIMERA (MIT), pinned as the submodule `vendor/chimera` at
`1d3ea49` and never copied. This page is the map.

## Files

| Layer | Files | What |
|---|---|---|
| Engine | `vendor/chimera` (submodule), `native/voice/` (Rust crate `dawlings-voice`: `src/lib.rs`, `voice.h`), `tools/voice_build.sh` | CHIMERA's `chimera` and `chimera-wasm` crates built natively as a static library, with a small C ABI (`dv_*`) for the rack: voices, plans, lyrics, telemetry, the head's outlines, creatures and the beat |
| Rack module | `native/rack/modules_voice.cc`, `mods/builtin/chimera/mod.json`, `core/music/rack/help/voice.json` | VOICE: SING, VOWEL, BEAT, BEAST; CV in (pitch, gate, vowel, open, breath), audio and envelope out; words in through the rack's `text MOD.KEY ...` verb; reports its body on stderr |
| Godot data | `SingerRow`, `VocalPart`, `VoiceTele`, `Bestiary` (`core/music/singer/`), `SingerLive` (`core/session/`) | the room's row `singer` and its asks; a MIDI track as the voice's song line; the engine's telemetry; the creature of each venue; what guests are sent |
| Sound (host only) | `Singer`, `Creature` (`core/music/singer/`), both `RackVoice`s | the booth's voice, a rack of one VOICE into OUT, run as an engine process like the modular room's rack; the creature's, a second one woken by a stone |
| The booth | `SingerHead`, `SingerBooth`, `CreaturePerch` (`hardware/singer/`), `SingerHost` (`core/room/`) | the cutaway head (airway rings lit by pressure, breath beads, grips on jaw, tongue, tip, lips, velum and larynx), the desk, the perch; standing them, the asks, recording, replication |
| Tools | `tools/voice_parity.sh`, `tools/singer_preview.tscn`, `tools/shot.sh --walk singer` / `--walk perch` | the bit-for-bit check against CHIMERA's CLI; a scene for the head alone; shots of the booth |

## How it fits

- **Planning off the audio thread.** CHIMERA plans a phrase (`sing::plan_song`, `plan_note_on`, `planner::plan_utterance`, the
  beat) into gestures, which allocates. The VOICE module plans on a thread of its own and hands the plan to the audio
  thread, which only schedules and renders (CHIMERA's contract: nothing allocates while it renders). An offline render
  (`rack --render`) plans in line, so it is deterministic.
- **Sample for sample CHIMERA's.** The engine renders in 128-sample sub-blocks at 2x oversampling whatever the host's
  block is, as `chimera render notes` does, so the rack's output equals the CLI's exactly: `tools/voice_parity.sh`
  renders `tests/fixtures/voice/parity_melody.json` both ways and compares every sample (0 of 264000 differ).
- **SING.** The song's lyrics (`MixState.lyrics`, LRC) become one line of words (`Singer.words_of`) and CHIMERA's
  syllables (CMUdict, then letter-to-sound). The row's `part` names a MIDI track; `VocalPart.notes_of` reads its
  notes in beats, monophonic (a chord sings its top note), and `song_line` sends `song FIRST BPM BEAT midi beats ...`
  (a gap is a rest, and a rest ends a phrase). Live, the module plans `PAD` (0.6 s) ahead and starts each phrase so
  its consonants come before the beat and the vowel lands on it. A seek re-plans from the syllable at the new beat.
  Keys or pads at the booth sing the next syllable, legato. Each VOICE report says which syllable it is on.
- **The lyric board.** `SingerHost` places that syllable on the lyrics' lines (`VocalPart.sung_span`: the syllables are
  pieces of the words' spelling, found in order; a held `~` is the one before). `LyricBoard.sung_source` shows that
  line as the line now, lit up to the end of that syllable.
- **The prompter and the desk.** Beside the head's face, at eye height, the prompter shows the line being sung with
  its syllables marked (`VocalPart.marked`: twin·kle), lit karaoke-fashion up to the end of the syllable sung (the lit
  words are drawn over the line from its own origin, never measured into place, so they sit on its letters in any
  venue's face) with a bar that fills along the line, the
  next line, and a status line that says how the words fit the notes (`SingerHost._fit`: "24 notes · 31 syllables:
  the last 7 not sung"). The desk: the modes, SPEAK, LYRICS (the session panel's LYRICS box at a desk, so a whole
  song can be pasted; the typing pad in a headset, " / " between lines), SEQ, and big PART (only tracks with notes),
  TRACK (the first press finds or makes a "Singer" track) and REC (records the song, choosing the TRACK first).
- **Lettering by venue, readable always.** `SingerStyle.of(venue)` letters the prompter, the desk, the perch and the
  lyric board in the venue's mood colours and its own character (the club's spaced neon capitals, the chalk zone's
  leaning hand, the desert's heavy capitals...). `SingerStyle.readable` holds every venue to 7:1 for the words and
  the small print and 4.5:1 for the sung words and dim lines against their panel, gives the sung words a colour of
  their own (saturation 0.45 or more, so a pale venue's are not white on white), caps slant, spacing, weight and
  glow, never shrinks a size and never puts lyric lines or status in capitals. The prompter's panel is opaque (a
  see-through one was drawn over some of its words). The desk's keys are unshaded and a lit key is painted the
  venue's colour made deep enough for its legend at 7:1 (`SingerStyle.key_paint`), so the booth's lamp and a
  bright venue cannot wash it out. `_test_singer_every_venue_letters_the_words_readably` checks
  every venue.
- **PLAY.** The head's grips (`SingerHead.Grip`, a `ControlAffordance`) take a hand, a controller or the mouse; a drag
  moves the articulator in centimetres (`artic NAME =cm`), and letting go hands it back to the planner. The vowel pad
  blends i e a o u along one axis, and opens the jaw along the other.
- **SPEAK.** `TypingPad` in a headset, a prompt at a desk; `/slashes/` mean IPA. The body knobs blend man to woman and
  toward a child (the tract is rebuilt once the knob settles).
- **BEAT.** The pads hit CHIMERA's beatbox sounds. The 16 steps edit the pattern (CHIMERA's notation, or a preset), and
  SEQ plays it locked to the song: the module starts its sequencer on the bar and follows the song's tempo.
- **BEAST and the bestiary.** The booth's BEAST mode plays CHIMERA's four creatures by their calls. Each venue also has
  its creature on a perch (`Bestiary`, `CreaturePerch`): eight stones played like the venue's instrument, stone n
  sounding the creature's call on the n-th tone of the song's scale (`VenueInstrument.scale_tone`), lettered with the
  note it sounds now. The elephant (the desert's) plays its rumble, the one call CHIMERA pitches (8 to 45 Hz), its
  stones round C0 and heard by the overtones through its trunk; its trumpet's valve is not a pitch param. Each kind
has its own outline on the perch (`CreaturePerch`: bird, seal, gator, elephant with its trunk lifting as it calls).
- **Recording.** The row's `track` is the track the voice sounds and records on, as the rack does (`RackVoice`): through
  `InputMonitor.feeds` on the built-in engine, and through its own direct stream under Reaper, caught by
  `record_start` / `record_stop` into `DAW.import_audio` at the song position the take began. The voice keeps its own clock while
  the song plays, by the wall clock (RackVoice), and the take is stamped with it (`song_seconds`), so the take is
  placed on the clock it was sung to. It follows the song's place only when that place moves: Reaper stops reporting
  for a second or more while a take starts (and the frame stalls), then sends a burst of old places. A place more than
  a quarter beat off is taken only once it has held for 0.15 s, and just after a stale stretch a difference under a
  beat is kept as an offset rather than jumped to (a jump re-planned the part and lost its last note). Measured on the
  rig: all eight notes of a test part in the take, each within 0.05 s, in three runs.
- **Multiplayer.** The row `singer` is replicated like the rack's (every change one ask, `Session.ask_room(&"singer",
  [op, args])`, answered on the host; a guest predicts its own). Moments (say, hit, grab, play, cry, strike) are
  played on the host. The host sends the voice's body, the head's outlines (16-bit hundredths of a centimetre), the
  syllable, the step and the board's span as the volatile entry `/singer/live` (`SingerLive`). A guest's head moves
  with it, and they hear the voice through the track like any monitored input.
- **Lights.** The room's pulse takes `SingerHost.level()` with the mix and the rack. The booth's halo and lamp warm
  from blue to amber with the voice, and so does the perch.
- **Cost.** The voice is about 17.5% of a core in the rack process (the human), and a creature 20 to 32% while one
  sounds. The singer runs while someone is within 3.5 m of the booth or it has a part (a part keeps it
  awake, so it is ready before the part's first note; POWER turns it off); the creature sleeps 20 s after
  its last stone. Drawn, the station adds no measurable draws or frame time (`tools/budget.sh`: 3,422 draws at
  13 tracks with it and on the commit before it, 2026-11-12).

## The demo and its clip

`--singer-demo` (`tools/singer_demo.gd`) does the whole thing as a player would: a key held at the booth, the jaw
and tongue taken by hand to shape the vowel, a 4-bar chorus put on a MIDI track and sung from it, recorded from a
bar before and played back; then the beatbox (BEAT, the default pattern on SEQ with the song) and the venue's creature
(its eight stones struck up the scale, the view stood at its perch). `tools/singer_clip.sh out.mp4` makes the clip of
it with its sound (a clip run quits itself when the clip is written), in real time on
workspace 10: the movie writer cannot, as it runs the game at its own pace and the singer's engine in real time
(its movie has no singing and an empty take). The clip's sound is the Mix bus caught inside the game, since the
song's mix leaves Godot on a stream of its own (AudioPorts) and the master bus hears none of it.
`tools/singer_clip.sh out.mp4 --reaper` makes it on the rig's Reaper (`tools/reaper_rig.sh up` first): the song and
the take play in Reaper, so its part is the null sink recorded beside the run, cut to the clip's first frame by the
wall clock the demo writes, and the singer is the game's Monitor bus (where it plays under Reaper; the game's own
streams reach the sink only at the per-app volumes you keep). The two are mixed and brought to a peak of -1 dB.

## Building

`tools/rack_build.sh` builds the rack and links `$(tools/voice_build.sh)` (`cargo build --release --locked`,
target `build/voice/`). It needs the `vendor/chimera` submodule and a Rust toolchain. The dictionary is read at run
time from `vendor/chimera/public/data/cmudict.txt.gz` (`dv_init`; `DAWLINGS_CMUDICT` names another). `VOICE_TARGET`
builds for another Rust target (`RACK_TARGET=windows tools/rack_build.sh` sets it). A release carries the engine and
the dictionary in `rack/` beside the game (`tools/rack_ship.sh`, `RackEngine.SHIPPED`). Notices: `THIRD_PARTY_NOTICES.md`.

## Tests

`tests/singer_tests.gd` (the `_test_singer_*` wrappers): the row and its asks; the vocal part; the syllable on the
board; what guests are sent; a creature in every venue and in key, each drawn as itself; the beat locked to the song;
a render through the rack; the VOICE played from its jacks alone (pitch and gate CV from a sequencer, through Rings,
its ENV on a VCA); parity with the CLI (`tools/voice_parity.sh`); the voice live; a take in sync. In `run_tests.gd`
with a studio: every venue's booth stands its creature, and the room's light rises with the voice while the song is
stopped. The manifest test (`rack_mod_tests.gd`) holds the VOICE's skin and pad to
its mod.
