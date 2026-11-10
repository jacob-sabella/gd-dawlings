# Third-party code

Pulled in as git submodules pinned to an exact commit, never copied into this tree.

| Path | Upstream | Pinned at | Licence |
| --- | --- | --- | --- |
| `vendor/dawkit` | this project's plugin host | see `git submodule status` | see its LICENSE |
| `vendor/mutable-eurorack` | https://github.com/pichenettes/eurorack (Mutable Instruments, the STM32 projects only: Plaits, Rings, Clouds, Warps, Elements, Braids, Beads, Tides 2, Stages, Peaks, Streams, Marbles) | `f4cfa76` | MIT (the AVR projects are GPL-3.0 and are not used) |
| `vendor/mutable-eurorack/stmlib` | https://github.com/pichenettes/stmlib | `e3bd7c9`, as Mutable Instruments pins it | MIT |
| `vendor/airwindows` | https://github.com/airwindows/airwindows (Chris Johnson; the plugin sources are compiled in place, against a host stand-in written for this project, not Steinberg's VST SDK) | `94cb679` | MIT, Copyright (c) 2018 Chris Johnson (the repository's LICENSE; each source file's header says the same) |
| `vendor/daisysp` | https://github.com/electro-smith/DaisySP | `2c72eaf` | MIT (its `DaisySP-LGPL` folder is not used; used for the oscillators, filters, effects, drums, physical models and noise sources of `native/rack/modules_core.cc` and `modules_daisy.cc`) |

Only the `vendor/mutable-eurorack/stmlib` submodule is initialised inside the Mutable Instruments
checkout; its AVR submodules are not.
