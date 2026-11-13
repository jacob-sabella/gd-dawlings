# Third-party code

Pulled in as git submodules pinned to an exact commit, never copied into this tree.

| Path | Upstream | Pinned at | Licence |
| --- | --- | --- | --- |
| `vendor/dawkit` | this project's plugin host | see `git submodule status` | see its LICENSE |
| `vendor/mutable-eurorack` | https://github.com/pichenettes/eurorack (Mutable Instruments, the STM32 projects only: Plaits, Rings, Clouds, Warps, Elements, Braids, Beads, Tides 2, Stages, Peaks, Streams, Marbles) | `f4cfa76` | MIT (the AVR projects are GPL-3.0 and are not used) |
| `vendor/mutable-eurorack/stmlib` | https://github.com/pichenettes/stmlib | `e3bd7c9`, as Mutable Instruments pins it | MIT |
| `vendor/airwindows` | https://github.com/airwindows/airwindows (Chris Johnson; the plugin sources are compiled in place, against a host stand-in written for this project, not Steinberg's VST SDK) | `94cb679` | MIT, Copyright (c) 2018 Chris Johnson (the repository's LICENSE; each source file's header says the same) |
| `vendor/daisysp` | https://github.com/electro-smith/DaisySP | `2c72eaf` | MIT (its `DaisySP-LGPL` folder is not used; used for the oscillators, filters, effects, drums, physical models and noise sources of `native/rack/modules_core.cc` and `modules_daisy.cc`) |
| `vendor/chimera` | https://github.com/jamesondh/chimera-vocal-synth (Jameson Hodge's CHIMERA physical-model voice; its `chimera` and `chimera-wasm` crates are built from the checkout as a static library by `native/voice`, for the rack's VOICE module, the vocal booth's singer and the bestiary) | `1d3ea49` | MIT, Copyright (c) 2026 Jameson Hodge |

Only the `vendor/mutable-eurorack/stmlib` submodule is initialised inside the Mutable Instruments
checkout; its AVR submodules are not.

## Data shipped with CHIMERA

The voice reads English through the Carnegie Mellon Pronouncing Dictionary as CHIMERA ships it,
`vendor/chimera/public/data/cmudict.txt.gz`, loaded from the checkout at run time (`dv_init`), not copied into the
repository. A release ships it unchanged beside the engine, `rack/cmudict.txt.gz`, with this file and every licence of
what the engine is built from in `rack/licences/` (`tools/rack_ship.sh`). It is under
its own BSD-style licence, Copyright (C) 1993-2015 Carnegie Mellon University; the full text is
`vendor/chimera/public/data/CMUDICT-LICENSE.txt`.

## Rust crates linked into the voice

`native/voice` (the static library that wraps CHIMERA) links these crates from crates.io, at the versions
`native/voice/Cargo.lock` pins. All are used under the MIT licence where they offer a choice.

| Crate | Version | Licence |
| --- | --- | --- |
| adler2 | 2.0.1 | 0BSD OR MIT OR Apache-2.0 |
| cfg-if | 1.0.5 | MIT OR Apache-2.0 |
| crc32fast | 1.5.5 | MIT OR Apache-2.0 |
| equivalent | 1.0.3 | Apache-2.0 OR MIT |
| flate2 | 1.1.11 | MIT OR Apache-2.0 |
| foldhash | 0.2.0 | Zlib |
| hashbrown | 0.17.1 | MIT OR Apache-2.0 |
| indexmap | 2.14.2 | Apache-2.0 OR MIT |
| itoa | 1.0.19 | MIT OR Apache-2.0 |
| libm | 0.2.16 | MIT |
| memchr | 2.8.3 | Unlicense OR MIT |
| miniz_oxide | 0.9.1 | MIT OR Zlib OR Apache-2.0 |
| serde, serde_core | 1.0.229 | MIT OR Apache-2.0 |
| serde_json | 1.0.154 | MIT OR Apache-2.0 |
| simd-adler32 | 0.3.10 | MIT |
| zmij | 1.0.23 | MIT |

`serde_derive`, `proc-macro2`, `quote`, `syn` and `unicode-ident` run only at build time (MIT OR Apache-2.0;
`unicode-ident` also Unicode-3.0) and are not linked.

## Downloaded on request, not shipped

The finder's MORE PICTURES can download projectM's "Cream of the Crop" MilkDrop preset pack
(https://github.com/projectM-visualizer/presets-cream-of-the-crop) to the player's own computer
(`user://milk/cream-of-the-crop/`), only when the player asks. The presets are their many authors' work and carry
no licence. None of them is in this tree, the game or its releases.

## Ideas re-implemented, no code taken

The audio-reactive visuals (`docs/visuals.md`) were written for this project from the published descriptions of
these projects' techniques. None of their code, shaders or presets is in this tree or the game; they are named here
as credit.

| Idea | From | Their licence |
| --- | --- | --- |
| Bars that rise at once and fall under gravity, integral smoothing, neighbour lift, auto-sensitivity (`CavaBars`) | cava, https://github.com/karlstav/cava | MIT |
| A scope beam lit by a Gaussian spot swept along each segment (`scope_beam.gdshader`) | woscope, https://github.com/m1el/woscope | MIT |
| A feedback-warp visualizer with per-frame equations and a drawn wave (`MilkScreen`) | MilkDrop and Butterchurn, https://github.com/jberg/butterchurn | BSD-3 / MIT |
| Stable fluids with vorticity confinement driven by splats (`FluidTank`) | PavelDoGreat's WebGL Fluid Simulation, https://github.com/PavelDoGreat/WebGL-Fluid-Simulation | MIT |
| Species attracting and repelling by a matrix (`ParticleLifePane`) | Particle Life, https://github.com/hunar4321/particle-life | MIT |
| Slime-mould agents that sense, turn, move and deposit on a decaying trail (`PhysarumSheet`) | Jeff Jones's physarum model; e.g. https://github.com/nicoptere/physarum | Unlicense |
| Reading MilkDrop's `.milk` preset format, its equation language (EEL) and its warp maths, and MilkDrop 2's shader conventions (`MilkFile`, `MilkEel`, `MilkPlayer`, `MilkHlsl`) | MilkDrop by Ryan Geiss, from its preset authoring guide | BSD-3 |
