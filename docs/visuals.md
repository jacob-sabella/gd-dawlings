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
| Visualizer TV | the annex's side wall (`MilkScreen`, `MilkPresets`) | MilkDrop-style. Two half-float buffers take turns warping each other (zoom, rotate, shift, wobble, fade), the wave is drawn on top, and a composite pass adds the echo, gamma, hue and flashes. 10 built-in presets, and `.milk` files (below), crossfade every 30 s, or on a big hit after 20 s. A patched SCOPE's wave replaces the mix's own. Click the glass for the next picture; FIND opens `MilkFinderScreen` (search, live preview, HOLD). |
| Fluid tank | on the annex bench under the TV (`FluidTank`) | Stable fluids on the GPU with vorticity, Jacobi pressure and dye at twice the grid size. Hits fire jets of ink up from the floor; mids and treble stir sideways. |
| Slime-mould ceiling | over the whole annex (`PhysarumSheet`) | Physarum agents sense, turn, move and deposit, then a diffuse-and-decay pass. Louder music speeds them up; a hit throws a ring of agents out. It replaces the ceiling tiles wherever compute runs. |
| Particle-life pane | the vocal booth's side wall (`ParticleLifePane`) | 6 species attract and repel through a matrix. Each species is driven by its own sixth of the bars, hits shake the matrix, and a new matrix blends in every 45 s. |

The three simulations are compute shaders (`hardware/visuals/shaders/*.glsl`) behind `GpuSim`. Where compute cannot
run (OFF, compatibility, headless) they build the object with a faint stand-in glow and make no GPU calls. On an
RTX 5080 at HIGH each measured under 0.1 ms of GPU time. The visualizer is about four draws a step.

## MilkDrop preset files

The TV also plays MilkDrop `.milk` files, through the same crossfade, click-for-next and finder as the built-in
looks. The list is the built-ins, then `user://milk/own/` (any folders below it), then
`user://milk/cream-of-the-crop/` (its folders become the finder's categories). Each file is read only when it is
shown.

- `MilkFile` reads a file into base values, the per-frame, per-frame-init and per-pixel equations, up to four
  custom waves and shapes, and the MilkDrop 2 `warp_`/`comp_` shaders.
- `MilkEel` parses MilkDrop's equation language (EEL) and turns it into a GDScript class (`MilkVM`) for the
  per-frame, wave and shape code. The per-pixel code becomes Godot shader code inside a warp shader made for that
  preset (MilkPlayer, cached by its text). That shader also does MilkDrop's warp: zoom with zoomexp, stretch,
  wobble, turn and drift, with the fade in gamma space.
- `MilkHlsl` translates a MilkDrop 2 warp or composite shader into Godot's shader language. It handles the types,
  `lerp`/`frac`/`saturate`/`mul`, HLSL's implicit float-to-vector spreads in `pow`/`min`/`max`/`lerp`/`clamp`,
  `tex2D` on the main, blur and noise samplers, GetPixel/GetBlur, and q1..q32. If the translation or the compile
  fails, the preset uses the plain warp (with the fade held below 1) or the plain glass.
- `MilkPlayer` runs one preset each step. It draws the main wave (modes 0 to 7), up to 4 custom waves of 256
  points, 8 shape instances, the borders and the motion vectors into the buffer. Additive strokes go through a
  second, add-blended ink.
- What a preset could not do is listed in its notes. The finder shows it as "approx" and gives the reasons.

MORE PICTURES in the finder fetches projectM's "Cream of the Crop" pack, about 9,800 presets and 32 MB, but only
when the player clicks DOWNLOAD and then confirms (`MilkDownload`). The zip goes to `user://milk/cream.zip`. Only
its `.milk` files are unpacked, on a thread, and then the zip is deleted. REMOVE deletes the pack. The presets are
their authors' work and carry no licence, so they are never shipped or kept in this repository. OPEN FOLDER opens
`own/` for the player's own files. "Include the pack in the shuffle" (in `user://visuals.cfg`) decides whether
auto-advance and the click pick from the pack.

Of the pack's 9,795 presets, every file reads. Per-frame code compiles for 9,386. Per-pixel code compiles for
5,965 of the 6,049 that have it. MilkDrop 2 warp shaders translate for 4,508 of 7,924, and composites for 5,571 of
7,971. 4,837 play with nothing dropped. On an RTX 5080 at HIGH, a step costs 0.2 to 2.2 ms of CPU, and the
buffer's GPU time is under 0.1 ms.

## Not done

- The MilkDrop 2 shader translation covers a safe subset. A preset that hands a sampler to a function, uses
  `#if`, `tex2Dlod`, structs, arrays, the comma operator, or adds float3 to float4 without a swizzle falls back to
  the plain warp or glass, and the finder marks it "approx". GetBlur1..3 are a ring of taps, not MilkDrop's three
  blurred copies. A texture a preset names (MilkDrop's own pictures, not in the pack) is drawn as noise.
- EEL's `loop`, `while`, `megabuf` and `gmegabuf` are not run, so per-frame code that uses them is dropped (about
  400 of the pack's presets). The per-pixel code runs per pixel, not on MilkDrop's 48 by 36 grid.
- A preset's code is compiled, and its shaders built, on the frame it is chosen: about 16 ms on average and up to
  60 ms for the heaviest. The warp shader is warmed up during the crossfade; a translated composite is not.
- The pictures are this machine's own. A guest's TV picks its own pictures, from the host's mix.
