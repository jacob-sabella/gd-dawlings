# The pad deck and the sampling station

The sampling station is an MPC-style sampler in the room: a TV that plays a video (or takes another source) and a
console under it of sixteen pads. You cut a sample, chop it into the pads, play them by click, keys or MIDI, and the
hits are recorded to a DAW track like any other instrument (`HitRecorder`). The product description, the slices
and the library are in `docs/sampling_station.md`; this page is the code map.

## Files

| Class | File | What |
|---|---|---|
| `TvSurface` | `hardware/tv/tv_surface.gd` | the TV and the deck on it: search/paste a link, playback, the deck as a child (`deck = PadDeck.new()`) |
| `PadDeck` | `hardware/tv/pad_deck.gd` (723 lines) | the console: 16 pads, the waveform, rows of keys, the state the helpers share |
| `PadDeckBuild` | `pad_deck_build.gd` | building the pads, waveform, keys and their labels; the key pages |
| `PadDeckVoices` | `pad_deck_voices.gd` | how a pad sounds: strike and release through the voice pool, the track's monitor bus, clicks, MIDI notes |
| `PadDeckLibrary` | `pad_deck_library.gd` | browsing, saving, loading and deleting a sample or a kit |
| `PadDeckSampling` | `pad_deck_sampling.gd` | making the sample: SAMPLE from the video's sound, source and device, trim, chop |
| `PadBank` | `core/sampling/pad_bank.gd` | the data: one sample, a slice a pad, what each pad plays (RATE frames, chop by attacks or equal parts) |
| `PadCapture` | `pad_capture.gd` | the other sources: room mic, an audio interface, the mix itself (resampling) |
| `PadLibrary` | `pad_library.gd` | every sample kept as a WAV, every kit as a small file |
| `PadShare` | `pad_share.gd` | the host's sample as a WAV in the project's media and the room's `pads` row, so a guest fetches and cuts it the same |
| `Tube`, `TubeFrames` | `tube.gd`, `tube_frames.gd` | a video fetched with yt-dlp, decoded by ffmpeg for the picture; `Tube.missing_tool()` says what is absent |
| `Sampler` | `core/music/sampler.gd` | the cabinet beside the cassette rack: anything can be a sample (REC, the `sampler` room row) |
| `SamplerHost` | `core/room/sampler_host.gd` | the studio's side of the sampler |

`PadDeck*` helpers hold `var deck: PadDeck` (the same pattern as the Studio helpers: state on the deck, a delegate
only for names reached from elsewhere).

## How it fits

`TvSurface` is built by `SurfaceHost` on the TV mount (`FurnitureHost`). The deck plays through the monitor bus of the
track `HitRecorder` has armed (`DAW.monitor_bus(HitRecorder.armed_track())`), so a hit sounds through that track's
chain and is taken down as MIDI by the same recorder as the other hand percussion. The
sample is the host's: `PadShare` writes it once and the room's `pads` row (published through `RoomRows`) tells
guests which file and how it is cut; guests fetch it with `FileSend.shared` and their pads sound the same.

## How to extend it

- **A new source**: add it to `PadCapture` (give it a `start`/`stop` like the room mic) and a button in
  `PadDeckSampling`; the sample it returns is stereo frames at `PadBank.RATE`.
- **A new pad behaviour** (a mode on how pads play): the data in `PadBank`, the sound in `PadDeckVoices`, the label
  and the key page in `PadDeckBuild`.
- **A new thing the room shares about the deck**: extend `PadShare`'s row and the `pads` row in `RoomRows`.

## Tests and tools

`tests/run_tests.gd` groups for the sampling station (`_test_*pad*`, `_test_*tube*`, with `tests/fixtures/fake_tube.sh`
standing in for yt-dlp); the picture needs ffmpeg and is not tested headless.
