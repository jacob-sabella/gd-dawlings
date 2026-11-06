# The sampling station

2026-10-30: "I want a sampling station (think Akai MPC Sample) that replaces the simple sampler
system that exists now. I want to be able to sample from youtube videos played in game though."

Chosen with the user the same day:

- **Pads + DAW.** Sample, chop into 16 pads, play them by click, keys or MIDI. Recording plays the
  pads into a DAW track as notes, like every other instrument here (HitRecorder). No sequencer of
  its own.
- **A TV in the room** for YouTube: type a search (the top results as a list) or paste a link. It
  plays with picture and sound, and you sample while it plays.
- **Everyone, in step.** The host picks the video; every player's game fetches the same video
  itself and plays it at the host's position. The samples are the room's: made on the host, sent
  like cassettes (Session.files).
- **The old sampler's trick stays as an input.** The station's sources: the TV, the room mic
  (catches an item's sound, as the Sampler does today), the audio interface, and the mix itself
  (resampling).

- **A scale mode for the pads** (2026-10-30: "the 16 pads need a scale mode btw. full scale, all
  modes"). In scale mode, one sound spreads across all 16 pads, each pad repitched to the next
  degree of a scale from the bottom-left pad up. Sixteen degrees is more than two octaves of a
  seven-note scale, so every note of the scale is on the pads. The root and mode can be picked,
  and by default they follow the song's key (Harmony.at). The choices are all seven modes
  (Harmony.SCALES: major/ionian, dorian, phrygian, lydian, mixolydian, minor/aeolian, locrian),
  plus harmonic and melodic minor, major and minor pentatonic, blues, and chromatic. The pad
  sound comes from the pad chosen, or a whole sample. It is repitched by playback rate, with
  the same slice and the same envelope. Recorded as notes, a scale-mode pad is a note at its
  pitch, so the take reads as a melody in the DAW.

It replaces Sampler (core/music/sampler.gd): the station stands where the sampler stood, on its
trolley, and a sample is still a cassette on the rack as well as a pad.

## How the TV works

- `yt-dlp` searches (`ytsearch8:`, flat JSON, under a second) and fetches a video at 480p or less,
  H.264 and AAC in an MP4, into the user cache, keyed by the video's id. Nothing is streamed from
  YouTube while it plays: a 30 s video arrives in about 2 s.
- `ffmpeg` decodes the sound once to a 48 kHz WAV beside it (tens of milliseconds a minute). That
  WAV is what plays and the clock everything follows, so what is heard, what is seen and what is
  sampled are the same audio, to the frame.
- The picture is decoded as it plays: `ffmpeg -ss <at> ... -f rawvideo -pix_fmt rgb24` through a
  pipe, 384x216 at 24 fps, onto a texture on the TV's screen; a seek restarts the pipe at the new
  time. Frames are shown by the audio's position, never by a clock of their own.
- Every fetch, decode and pipe runs off the main thread.
- Missing tools say so on the TV ("yt-dlp is not installed") rather than failing quietly.

## Slices

1. [x] **Tube**: search, fetch and decode (core/sampling/tube.gd), the picture through a pipe
   (core/sampling/tube_frames.gd), off the main thread, tested against a stand-in for both tools
   (tests/fixtures/fake_tube.sh) so the suite never touches the network. Live: a search in under
   a second, an 8 s video fetched and decoded in about 2 s, its first frame 57 ms after asking.
2. [x] **The TV** (hardware/tv/tv_surface.gd): on the control room's front wall right of the
   timeline, as LEVELS is left of it, on a bracket (Venue.tv_mount_spot; a stand where the wall is
   not one to hang it on). FIND asks for a search or a link (NamePrompt), a search's results are
   chosen in a PluginPicker; PLAY, ◀ and ▶ 5 s; picture from the pipe, sound from the WAV on the
   monitor bus. The lamp that stood in front of it moved left; the slate panel narrowed.
3. [x] **The station** (hardware/tv/pad_deck.gd, core/sampling/pad_bank.gd): the pads are a
   console under the TV, one station (SAMPLING STATION): 16 pads, a screen with the sample's waveform, SAMPLE from the TV (the span
   between two presses, cut from the WAV exactly), chop by transients (DawKitTransients) or into
   equal slices, a pad a slice; pads heard through the armed track's bus (DAW.monitor_bus), and
   taken down onto the armed track as notes (36-51) while the song records.
4. [x] **Playing and recording the pads**: click, the computer keys (ZXCV ASDF QWER 1234, pad 1 at
   the bottom left), and a MIDI keyboard's notes 36-51 (in scale mode every note), all while the
   player stands at the station (Studio.at_tv); a hardware note the pads take is not heard on the
   player's instrument (GuestMidi.pad_sink). Each pad has its own volume, tune, reverse, play mode
   (TRIG: one-shot, gate while held, loop until struck again) and choke group, edited with the
   second row of keys on the selected pad; velocity sets the level; 16 voices. Struck, it is
   recorded as a note (HitRecorder.note). Still to come: a track's notes played back as the pads.
5. [x] **Scale mode**: a pad's sound across all 16 in a key and mode (above): every mode,
   following the song's key unless one is picked, played and recorded at the scale's pitches.
   SCALE spreads the last pad struck; KEY steps the root, MODE the scale. Still to come with slice
   4: a track's notes played back as the pads (until then a take plays through the track's own
   instrument).
6. [x] **The other sources** (core/sampling/pad_capture.gd): SRC steps TV, MIX (the Master bus,
   resampling), ROOM (the Gear bus: items, castors, tape motors) and IN (the audio interface);
   SAMPLE twice catches up to 30 s. The old Sampler's item-triggered catch is still its own.
   Also in 2026-11-04's pass: per-pad trim (IN/OUT), attack, release, a state-variable filter
   (low pass closing to high pass opening), an FX send (reverb, delay or both, on the PadFx bus),
   key-lock (the slice is overlap-add stretched by the rate it is played at, so pitch moves and
   length does not), pan, MIDI learn (the next note names the selected pad), and SEQ (the armed
   track's recorded notes are struck through the pads as the playhead crosses them).
7. [x] **The room**: the room's `tv` row (video, playing, position) and `pads` row (PadShare: the
   sample's file, its cuts, each pad's settings, scale mode, first note). A guest's FIND, PLAY and
   skips are asked of the host (the `tv` verb) and its TV follows the host's row: it fetches the
   video itself (Tube) and plays it at the host's position. The host writes its sample once as a
   WAV in the project's media, named by what is in it, and guests fetch it (FileSend.shared makes
   it servable) and cut it the same. A guest's pads play locally; the samples are the host's.
8. [x] **The old Sampler kept (decided, not retired)**: it is the host-side catch of item sounds (duck, ball, cassette, yo-yo, card tricks) into sample cassettes on the rack, wired through Session, Venue, Stations and six item classes, and the station's pads do not replace that. The station's own ROOM source (PadCapture) covers sampling the room into pads. Revisit only if the item catch is to be rebuilt on the pads.

## Sampling your own sounds (2026-11-06)

The pads are not only for the TV. SRC steps TV, MIX, ROOM and IN, and **IN is any audio input this
machine has**: a microphone, an audio interface, a webcam's mic, or any source the sound server
offers (a phone or another device linked in as a source shows up in the list the same way).

- **DEV** (CUT page) steps through the inputs, the default first, by the names the sound server
  gives people ("Scarlett Solo (3rd Gen.) Pro", "MPC Sample"); it also switches SRC to IN.
- SAMPLE starts catching, SAMPLE again ends it (up to 30 s); the screen shows what it is catching
  from, the length, and a level meter (`[###-----]`) so you can see the input is alive.
- **TRIM** (lit by default) cuts the quiet off both ends of a live catch, so a mic take starts at the
  hit and the pads chop what you played, not the silence round it.
- The input is read directly, never played back out of the speakers, so a mic does not feed back.
- A guest samples from **their own** machine's inputs. The moment a guest samples or loads a sound
  of their own, the pads are theirs: the host's pads row stops replacing them (their cuts would not
  fit the host's sample anyway). **SYNC** (STORE page) takes the room's pads back, as the host has
  them now.

Checked on this machine's six real inputs (`PadCapture.devices`, then `start("IN")` on each): every
one opened and delivered audio in real time.

## The library (2026-11-04)

Your samples and kits live in `user://sampling/samples/*.wav` and `user://sampling/kits/*.json` (`PadLibrary`),
folders you can open and rename in. On the pads' last key row: SAVE keeps the selected pad's sound
(named after the video and the pad), LIB steps through your samples, LOAD puts the one shown on the selected
pad, KSAVE keeps all sixteen pads and their settings as a kit, KITS steps through kits, KLOAD puts one on the
pads, DEL (twice) deletes what was browsed last. A kit holds its sounds by name, so one sample serves any
number of kits, and the same sound is never kept twice.

The keys are on pages (2026-11-04): CUT, PLAY, SHAPE, MIDI and STORE tabs and STOP, always there, and under
them only the keys of the tab chosen, two rows at most. The library keys above are the STORE page.

Seeing what you edit (2026-11-04): the selected pad glows blue and its slice is bright on the waveform (the
others dimmed, trimmed-away ends darker); striking a pad selects it. Off the CUT page the line above the waveform
reads the selected pad's settings back ("PAD 4 · GATE · TUNE +2 · PAN L25"), only what is not as it comes.
