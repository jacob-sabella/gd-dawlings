# Third-party code

Pulled in as git submodules pinned to an exact commit, never copied into this tree.

| Path | Upstream | Pinned at | Licence |
| --- | --- | --- | --- |
| `vendor/dawkit` | this project's plugin host | see `git submodule status` | see its LICENSE |
| `vendor/mutable-eurorack` | https://github.com/pichenettes/eurorack (Mutable Instruments, the STM32 projects only: Plaits, Rings, Clouds and the like) | `f4cfa76` | MIT (the AVR projects are GPL-3.0 and are not used) |
| `vendor/mutable-eurorack/stmlib` | https://github.com/pichenettes/stmlib | `e3bd7c9`, as Mutable Instruments pins it | MIT |
| `vendor/daisysp` | https://github.com/electro-smith/DaisySP | `2c72eaf` | MIT (its `DaisySP-LGPL` folder is not used) |

Only the `vendor/mutable-eurorack/stmlib` submodule is initialised inside the Mutable Instruments
checkout; its AVR submodules are not.
