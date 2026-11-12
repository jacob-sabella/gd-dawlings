# Audio-reactive visuals

Screens and simulations that move with the music. All written for this project. The ideas came from MIT, BSD and
Unlicense projects, but none of their code is used (`THIRD_PARTY_NOTICES.md`, "Ideas re-implemented").

## What the music is doing: `AudioFeatures` (`core/audio/audio_features.gd`)

One node, stood up by the studio, works out each frame what every visual reads:

- `level` (0..1, auto-gained).
- `bass`, `mid` and `treb`: each measured against its own recent average, MilkDrop-style, so 1 is typical and 2 is a hit. Each also has an eased `*_att` version.
- `hit`: a spectral-flux onset weighted to the low end. It is also emitted as the `onset` signal.
- `beat` and `beat_phase`: the song's beat while the transport plays; otherwise a free clock at 120 BPM.
- 32 log-spaced `bars`, smoothed by `CavaBars`.
- `wave`: 128 samples of the mix.

It listens through an analyzer and a small capture added to the end of the MIX bus. On Reaper that bus is
silent, so the rack's own loudness and hits, lent by `RackHost` (`lend`), move things instead.
`AudioFeatures.now()` always returns something (a silent stand-in if no studio is running).

## Cost: `VisualBudget` (`hardware/visuals/visual_budget.gd`)

The tier is OFF, LOW or HIGH. It is chosen in the session panel (COMFORT → Visuals) and kept in
`user://visuals.cfg`, or set for one run with `--visuals=off|low|high` or `DAWLINGS_VISUALS`. Without either, it
is HIGH on Forward+, LOW on the mobile renderer, and OFF on compatibility or headless (so the test suite runs with
the visuals OFF unless a test sets the tier).

Every heavy visual calls `ask(self, distance)` each frame:

- Off screen, its distance is INF.
- Only the nearest on-screen visuals run: three on HIGH, one on LOW, and one on HIGH while the frames average slower than 1/50 s.
- One that is not granted does no work, and its last picture stays.
- Further away, a visual steps less often (`rate_hz`): every frame under 4 m, 30 Hz under 9 m, then 15 Hz.
- `pick(high, low)` sizes buffers and particle counts by tier.

## The pieces

| What | Where | How |
| --- | --- | --- |
| Scope beam | every SCOPE and VECTOR screen, and the annex TV with the visuals OFF (`ScopeScreen`) | Each trace segment is a quad lit by a Gaussian spot swept along it (`scope_beam.gdshader`, after woscope). Fast swings are faint and lingering parts burn bright. |
| Cava bars | SPECTRUM screens, and the annex's light columns and truss bars | `CavaBars`: bars rise at once and fall under gravity, with integral smoothing, neighbour lift (monstercat) and auto-sensitivity. Frame-rate independent. |
| Visualizer TV | the annex's side wall (`MilkScreen`, `MilkPresets`) | MilkDrop-style. Two half-float buffers take turns warping each other (zoom, rotate, shift, wobble, fade), the wave is drawn on top, and a composite pass adds the echo, gamma, hue and flashes. 10 presets crossfade every 30 s, or on a big hit after 20 s. A patched SCOPE's wave replaces the mix's own. Click the glass for the next picture; FIND opens `MilkFinderScreen` (search, live preview, HOLD). |
| Fluid tank | on the annex bench under the TV (`FluidTank`) | Stable fluids on the GPU with vorticity, Jacobi pressure and dye at twice the grid size. Hits fire jets of ink up from the floor; mids and treble stir sideways. |
| Slime-mould ceiling | over the whole annex (`PhysarumSheet`) | Physarum agents sense, turn, move and deposit, then a diffuse-and-decay pass. Louder music speeds them up; a hit throws a ring of agents out. It replaces the ceiling tiles wherever compute runs. |
| Particle-life pane | the vocal booth's side wall (`ParticleLifePane`) | 6 species attract and repel through a matrix. Each species is driven by its own sixth of the bars, hits shake the matrix, and a new matrix blends in every 45 s. |

The three simulations are compute shaders (`hardware/visuals/shaders/*.glsl`) behind `GpuSim`. Where compute cannot
run (OFF, compatibility, headless) they build the object with a faint stand-in glow and make no GPU calls. On an
RTX 5080 at HIGH each measured under 0.1 ms of GPU time. The visualizer is about four draws a step.

## Not done

- Community MilkDrop presets (`.milk`) are not loaded. The packs carry no licence (projectM's), or none from their
  hundreds of authors (Butterchurn's), and reading them would need a `.milk` interpreter: their equation language,
  per-vertex grid and DirectX shaders.
- The pictures are this machine's own. A guest's TV picks its own pictures, from the host's mix.
