# Performance backlog

Measured with `tools/budget.sh` (desktop RTX 5080, 1600x900, vsync off, wide pose, 13 tracks, quiet room: no song, no second player). Desktop numbers are for slope and breakdown, not the Quest budget.

## Baseline 1 (before any optimisation)

| venue:arr | prims | draws | objects | frame ms | worst ms | nodes | start ms | mem MB |
|---|---|---|---|---|---|---|---|---|
| studio:0 | 649470 | 4814 | 5396 | 7.32 | 7.41 | 3807 | 3737 | 461.0 |
| studio:1 | 758076 | 5569 | 6481 | 7.12 | 7.14 | 3849 | 3572 | 463.9 |
| studio:2 | 662874 | 5216 | 5801 | 7.88 | 8.33 | 3864 | 3551 | 464.5 |
| grid:0 | 483220 | 3660 | 4284 | 5.37 | 5.56 | 3821 | 3576 | 418.1 |
| grid:1 | 487524 | 3634 | 4262 | 5.85 | 6.43 | 3798 | 3397 | 417.9 |
| grid:2 | 645552 | 3702 | 4306 | 6.47 | 8.02 | 3813 | 3572 | 417.9 |
| chalk:0 | 478182 | 3069 | 3620 | 6.45 | 6.67 | 3831 | 3448 | 415.1 |
| chalk:1 | 481486 | 3048 | 3609 | 5.70 | 6.44 | 3711 | 3472 | 414.5 |
| chalk:2 | 648194 | 4166 | 4756 | 7.25 | 7.41 | 4048 | 3319 | 419.8 |
| loft:0 | 535160 | 4609 | 5238 | 6.78 | 7.59 | 3971 | 3804 | 421.6 |
| loft:1 | 692554 | 4758 | 5449 | 6.98 | 8.91 | 3983 | 4190 | 424.2 |
| loft:2 | 598850 | 4641 | 5279 | 8.71 | 10.03 | 3995 | 4084 | 428.8 |
| cabin:0 | 737263 | 4979 | 5708 | 6.11 | 8.00 | 3926 | 4059 | 422.8 |
| cabin:1 | 1403423 | 4454 | 5028 | 6.56 | 8.01 | 3965 | 3996 | 426.2 |
| cabin:2 | 723085 | 5029 | 5722 | 7.31 | 8.64 | 3955 | 4097 | 423.5 |
| rooftop:0 | 547956 | 4217 | 4792 | 6.45 | 9.39 | 3871 | 4271 | 421.1 |
| rooftop:1 | 547902 | 4207 | 4797 | 6.74 | 7.14 | 3871 | 4040 | 421.1 |
| rooftop:2 | 506864 | 3940 | 4513 | 5.93 | 7.23 | 3871 | 4256 | 420.8 |
| station:0 | 654128 | 4291 | 4867 | 6.35 | 6.67 | 3853 | 3543 | 421.5 |
| station:1 | 716660 | 4615 | 5193 | 6.70 | 7.58 | 3871 | 3598 | 423.6 |
| station:2 | 706466 | 4613 | 5220 | 6.69 | 8.06 | 3855 | 3417 | 421.8 |
| dome:0 | 1001584 | 3951 | 4543 | 6.29 | 8.17 | 3869 | 3787 | 423.0 |
| dome:1 | 789416 | 3825 | 4403 | 6.75 | 9.26 | 3904 | 3876 | 429.4 |
| dome:2 | 1096020 | 3982 | 4571 | 7.02 | 7.58 | 3961 | 4033 | 425.3 |
| club:0 | 641082 | 3832 | 4418 | 5.84 | 7.54 | 3887 | 4015 | 425.3 |
| club:1 | 868110 | 4154 | 4765 | 6.73 | 7.14 | 3956 | 3891 | 428.9 |
| club:2 | 746428 | 4229 | 4838 | 6.65 | 6.67 | 3937 | 4265 | 427.8 |
| cave:0 | 1143130 | 3381 | 3953 | 6.04 | 6.62 | 3853 | 3604 | 419.9 |
| cave:1 | 1049662 | 3594 | 4165 | 5.57 | 6.25 | 4040 | 3813 | 425.4 |
| cave:2 | 1010596 | 3474 | 4045 | 6.50 | 6.83 | 3941 | 4185 | 424.0 |
| greenhouse:0 | 2738923 | 5029 | 5634 | 6.81 | 8.94 | 3865 | 4486 | 422.4 |
| greenhouse:1 | 2791357 | 4874 | 5468 | 7.20 | 7.41 | 3876 | 4408 | 429.9 |
| greenhouse:2 | 2817178 | 4890 | 5497 | 6.24 | 6.25 | 3880 | 4205 | 425.5 |
| stage:0 | 3095372 | 4139 | 4804 | 7.71 | 8.33 | 4178 | 3497 | 433.0 |
| stage:1 | 1621828 | 4313 | 4915 | 6.34 | 7.41 | 4139 | 3475 | 430.9 |
| stage:2 | 4031396 | 3597 | 4165 | 6.86 | 9.05 | 4018 | 3641 | 427.3 |
| garden:0 | 11646006 | 6006 | 6706 | 7.42 | 7.58 | 3959 | 4227 | 428.2 |
| garden:1 | 11341414 | 5580 | 6169 | 7.08 | 7.58 | 3959 | 4401 | 426.7 |
| garden:2 | 7922048 | 5416 | 6006 | 6.21 | 6.37 | 3961 | 4391 | 426.5 |
| desert:0 | 7564482 | 5040 | 5727 | 7.22 | 8.11 | 3909 | 4194 | 422.6 |
| desert:1 | 5892332 | 4345 | 4993 | 6.91 | 8.34 | 3912 | 3996 | 424.3 |
| desert:2 | 5956662 | 4839 | 5484 | 7.06 | 7.25 | 4049 | 3845 | 425.1 |

## What the baseline says

- Draw calls are 3000-6000 in EVERY venue, and objects 3600-6700. The venue is not the main cost: the studio gear is (13-track studio fitted: Timeline 585 meshes / 238 labels / 80k tris, Patchbay 107 meshes, PatchWall 93). A mobile headset draws this twice.
- Primitives vary a lot by venue: garden 8-12M, desert 6-7.5M, stage 1.6-4M, greenhouse 2.7M, vs 0.5-0.8M for the rest.
- Startup to first frame is 3.3-4.5 s everywhere; memory is 415-465 MB.
- Not yet measured: CPU per script, audio callback time and xruns, bytes per second on the wire, busy-room runs (song playing, reactive loud, second player), Quest-sized settings.

## Where the draws come from (studio:0, 13 tracks, wide)

`tools/budget.gd` now takes `--no-shadows` (drops shadows from every light, as the headset's mobile renderer does: `rich_rendering()` is false there) and prints `BUDGET.parent`, the busiest mesh parents.

| | draws | objects | prims |
|---|---|---|---|
| desktop, 9 shadow-casting lights | 3055 | 3703 | 403k |
| no shadows (the Quest proxy) | 1056 | 1676 | 81k |

So two thirds of the desktop draw count is shadow passes, which the headset never pays. The Quest cost is the second row. Its biggest mesh parents: PatchWall 69, Swivel 48, Wheel 48, Ruler 31, PropShelf 30, studio venue 26, keytar 26, Plug 24.

## Labels (studio:0, 13 tracks, wide pose, no shadows)

| | draws | objects | frame ms |
|---|---|---|---|
| as it is | 1233 | 1783 | 5.19 |
| 469 Label3Ds hidden | 1130 | 1681 | 4.15 |

Labels are batched well (only 103 draws) but cost about 1 ms a frame on the desktop CPU, 20% of it. The same run shows `Caster` is 7 meshes each (plate, kingpin, two cheeks, tyre, two spokes) and 16 of them stand under the furniture: 112 objects that merge to about 48.

## Ranked candidates

1. The 469 Label3Ds: about 1 ms of a 5.2 ms frame. Find why they cost (per-frame text updates? mesh rebuilds? submission?) before changing anything.
2. The ~1000 draws that remain on the Quest proxy: merge or instance the busiest parents (PatchWall, Swivel, Wheel, Ruler, PropShelf).
3. Casters: 7 meshes each, 16 of them; merge into 3 each (plate; fork; wheel with two surfaces).
4. Garden and desert primitive counts (instancing / LOD).
5. Startup (3.3-4.5 s) and memory.

## Dead ends

(none yet)
