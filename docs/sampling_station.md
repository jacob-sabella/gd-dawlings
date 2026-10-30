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
4. [ ] **Playing and recording the pads**: click, the keyboard's 16 keys, MIDI notes 36-51;
   recorded as notes on a track (HitRecorder.note), and played back from them as the pads' slices.
5. [x] **Scale mode**: a pad's sound across all 16 in a key and mode (above): every mode,
   following the song's key unless one is picked, played and recorded at the scale's pitches.
   SCALE spreads the last pad struck; KEY steps the root, MODE the scale. Still to come with slice
   4: a track's notes played back as the pads (until then a take plays through the track's own
   instrument).
6. [ ] **The other sources**: the room mic (the Sampler's catching), the audio interface input,
   the mix.
7. [ ] **The room**: the TV's row (video, playing, position at time) and the pads' row; a guest
   fetches the video itself and follows the host; samples sent as files.
8. [ ] **The old Sampler retired**: its station row, verb and tests moved to the new station.
