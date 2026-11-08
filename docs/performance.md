# Performance

How the studio is measured, what it costs at `HEAD` of the `modular-room` branch, where the time goes and what
was and was not done about it. The long history (the 144 fps loop, startup, dead ends) is in
`docs/perf_backlog.md`; this page is the current state.

## How to measure

```
. tools/offscreen.sh                 # windows open on workspace 10, never in the user's face
tools/budget.sh 13 48                # fitted and wide pose at 13 and 48 tracks (runs offscreen_run itself)
VENUE=cabin tools/budget.sh 13       # another venue
XDG_DATA_HOME=/tmp/clean tools/budget.sh 13   # with no saved rooms, patches or profile
```

`tools/budget.sh` starts the game with `--budget --tracks N --quit-after 200` (`tools/budget.gd`), vsync off, and
prints one row per pose: primitives, draw calls, objects, mean and worst frame time, nodes, start-up time and
static memory, then per-surface mesh and triangle counts. A window is needed (headless draws nothing), so it
goes through `offscreen_run`. Draw calls, primitives, nodes and meshes are deterministic as means over the window (not as single frames: see "One frame is not the scene"); frame times are not
(see "Noise").

The target is a standalone headset: this room twice (once per eye) at 72 Hz, 6.94 ms a frame, on a mobile GPU. Desktop frame times are not that budget; read the counts and the slope.

## Numbers at HEAD (2026-11-07, after the VU fix below)

Desktop GPU, 1600x900, vsync off, studio venue, arrangement 0, quiet room, shadows as the desktop renderer has
them. Run: `tools/budget.sh 13 48`.

| tracks | pose | prims | draws | objects | frame ms | worst ms | nodes | start ms | mem MB |
|---|---|---|---|---|---|---|---|---|---|
| 13 | fitted | 403548 | 3388 | 3647 | 13.47 | 23.48 | 10713 | 4807 | 692.2 |
| 13 | wide | 887580 | 6052 | 6322 | 16.43 | 23.97 | 10716 | 4795 | 697.8 |
| 48 | fitted | 458155 | 3869 | 4118 | 20.92 | 30.86 | 13544 | 4698 | 720.8 |
| 48 | wide | 994128 | 5673 | 5949 | 23.01 | 30.09 | 13547 | 4752 | 725.3 |

`prims`, `draws` and `objects` are means over the sampled frames. Slope: 35 more tracks cost about 480 draws and 55k
primitives in the fitted pose (about 14 draws a track); in the wide pose the count falls (6052 to 5673) because the
bigger desk pushes more of the room's shadow casters out of the lights' reach, so read the fitted slope. The nodes
grow from 10.7k to 13.5k (80 per track). Before the fix the 13-track rows were 3736 / 467k (fitted) and 6606 / 1.00M
(wide).

Surfaces, 13 tracks, wide (meshes / labels / triangles): RackWall 796 / 102 / 412190, Timeline 661 / 257 / 91024,
StageTable 142 / 97 / 16284, Tv 124 / 73 / 1468, TapeDeck 50 / 20 / 11520, Console 56 / 90 / 2740, Rack 46 / 31 /
1268, EqWall 31 / 33 / 262, PatchWall 25 / 74 / 166, Patchbay 15 / 60 / 56, Levels 7 / 66 / 84, ClipEditor 2 / 1 / 24.

## Against the start of the branch

The same tool on a clean checkout of `master` (the branch point `d3ad499`), same machine, 13 and 48 tracks, wide
and fitted pose (`tools/budget.sh 13 48`; `prims` and `draws` are now the mean over the 40 sampled frames, see
"One frame is not the scene"). Frame times are not comparable between the two checkouts' runs (see "Noise").

| | pose | master prims / draws | HEAD before the fix | HEAD after |
|---|---|---|---|---|
| 13 tracks | fitted | 403031 / 3254 | 467372 / 3736 | 403548 / 3388 |
| 13 tracks | wide | 930088 / 6332 | 999864 / 6606 | 887580 / 6052 |
| 48 tracks | fitted | 426905 / 3530 | 562565 / 4486 | 458155 / 3869 |
| 48 tracks | wide | 1027903 / 5849 | 1153661 / 6576 | 994128 / 5673 |

Nodes are 6 % fewer at HEAD (10713 against 11410) and memory 49 MB lower; both identical in repeat runs.

### The +772 draws, found (not bisected: profiled)

The earlier figure (+772 draws, +172k prims, wide pose, 13 tracks) was one frame read from each build. It was real
in direction and wrong in size, and it was **not geometry**. `tools/budget.sh` now takes `--tree` (see "Profiling
where the draws are"), and the breakdown, 13 tracks, wide pose, fresh user data on both sides, was:

| | master | HEAD |
|---|---|---|
| visible meshes / surfaces | 2819 / 3111 | 2574 / 2799 |
| triangles | 786k | 708k |
| shadow-casting meshes | 1853 | 1634 |
| draws with every shadow off (`--no-shadows`) | 1878 | 1875 |
| draws, shadows on (mean of 30 frames) | 6293, the same every frame | 6760: 7067 most frames, 6042 the rest |

By subtree (`Studio/...`, meshes master to HEAD): Items 255 to 200 and the venue's showcase instruments (Theremin, MusicBox, MarbleRun,
ChordHarp, BellStand, GrainCloud, StringSpool, ChordLedge: 0 at HEAD in a fresh-data run; why they are not built
there was not traced, and it can only lower the counts), ModularAnnex 339 to 232, StationBoard 25 to 17, PropShelf 31 to 24; and
the two that grew on purpose: RackWall 757 to 775 (the second-face pads, `RackPad`) and Tv 31 to 46, hidden 9 to 78
(`PadDeck`). Duplicated geometry (same mesh resource at the same place): 5 on both. So HEAD draws **less**, and with
the shadows off the two builds draw the same number. The whole difference was in the shadow passes.

Cause. The studio has three shadow-casting omni lights; Godot caches a positional light's shadow map and redraws it
(about 1,000 draw calls for the lamp's) only when something in its range changes. On master the lamp stand's light
was never redrawn after the first frames (ablating its shadow changed nothing); at HEAD it was redrawn on about
three frames in four (ablating it took 7067 to 6045). The difference is `30acdd6` ("physics ticks at 30 a second
with interpolation", `project.godot`): with physics interpolation on, the renderer treats every write to an
interpolated instance as a change, where without it an unchanged write is dropped. The console's VU meters
(`hardware/console/vu_meter.gd`, 15 of them, a `MultiMesh` ladder repainted from `_process`) were interpolated, so
every repaint invalidated the shadow map of every light within reach of the console. Located by elimination, with
no assumption about which commit: `--shadow-off-index` (the lamp's light), `--hide-node` (hiding Items, Console and
other sets), `--no-interp-node` (interpolation off for `Console` alone removed it), `--without-script` for
`vu_meter.gd` (removed it) and the same project settings with interpolation off in `override.cfg` (removed it).
`MeshBank` had already been given `physics_interpolation_mode = OFF` for the same reason, in its comment.

Fix: `VUMeter` sets `physics_interpolation_mode = OFF` on its `MultiMeshInstance3D`. Nothing it draws moves with
physics, so no behaviour changes. Result, 13 tracks wide: 6606 to 6052 draws, 999864 to 887580 prims (master: 6332 and
930088), now steady frame to frame. This is a branch change (the `project.godot` commit), not a refactor regression.

Left as they are because they are on purpose: `RackPad` and `PadDeck` (draws fitted +134 against master) and the 30 Hz
physics with interpolation (the heavy rig 55 to 155 fps, per that commit). Anything else that repaints a
`MultiMeshInstance3D` from `_process` has the same exposure; look for it with `tools/budget.sh` and the series line
(a draw count that alternates between two values is a shadow map being redrawn).

- **Frame times were lower at HEAD in some runs and should not be believed to that precision.** See "Noise".
- The pre-modular baseline in `docs/perf_backlog.md` (studio:0, 13 tracks, wide: 7.3 ms, 4814 draws, 649k prims,
  3807 nodes) predates the modular room (`9a2b1f1`, 2026-11-02), whose wall alone is now 412k triangles; it is not
  comparable with either row above.

### One frame is not the scene

Godot redraws a light's shadow map on a rotation and when a caster in range changes, so a single frame of
`RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME` is a high one or a low one depending on the phase it lands on (HEAD
before the fix alternated 6042 and 7067 draws frame to frame; the +772 above was one such frame against a flat one).
`tools/budget.gd` now reports the mean over the sampled frames in `prims`, `draws` and `objects`, plus
`prims_lo`, `prims_hi`, `draws_lo`, `draws_hi`, and a `BUDGET.series` line with every sampled frame's draw count.
A series that is flat is a scene whose shadows are cached; one that alternates is a light being redrawn.

### Profiling where the draws are

`tools/budget.sh` runs with the surface table only; for the breakdown run the game directly (through `offscreen_run`):

```
. tools/offscreen.sh
offscreen_run env XDG_DATA_HOME=/tmp/clean godot --path . --resolution 1600x900 -- --budget --tree --tree-depth 4 \
    --tracks 13 --quit-after 200 --cam 0,-0.35,7.0,0,1.0,0 > out.txt
```

(`env XDG_DATA_HOME=...` is what gives a run empty user data: an environment variable set before `offscreen_run` does
not reach a window the compositor starts. Saved rooms and items change what is built, so compare like with like.)
`--tree` prints, per subtree to `--tree-depth` segments: visible meshes, hidden meshes, surfaces, triangles, shadow
casters, duplicates (same mesh resource, same place), lights, surfaces in the camera frustum (`inview`), caster
surfaces within range of a shadow-casting omni or spot light (`lit`), and the casters that moved in the sample window
(`moving`, `moves`); then `BUDGET.light`, `BUDGET.shadow` (casters in range, per shadow light), `BUDGET.shadowsrc`
(the same by subtree), `BUDGET.other` (labels, multimeshes), `BUDGET.mover` (every geometry instance or light that
changed during the window, with its position and which shadow lights reach it) and `BUDGET.proc` (the scripts that
process every frame). Ablations to find what a cost hangs on: `--no-shadows`, `--no-omni-shadows`, `--no-dir-shadows`,
`--shadow-off-index N` (one light), `--hide-node A,B` (subtrees by node name), `--no-interp-node A,B` (physics
interpolation off for subtrees), `--without-script res://x.gd`, `--hide-labels`. Diff two builds' `BUDGET.tree` lines by
subtree (the throwaway `git worktree` of `master` needs `vendor/dawkit` and imports).

## Where the cost is

1. **RackWall**: 796 meshes and 412k triangles, 38 % of all primitives in the wide pose. Every module plate, knob,
   jack and cable is a mesh of its own, and the modular room is built onto every venue, so it is paid everywhere.
2. **Timeline**: 661 meshes, 91k triangles, 257 labels (a clip per mesh).
3. **Start-up**: 4.7 to 4.8 s to the first frame (`start ms`), against about 2.9 s in the older breakdown in
   `perf_backlog.md`; the room has more in it, and 10.7k nodes are built in code.
4. **Draw calls** at about 3600 (fitted) to 7000 (wide) are the render-side problem the older loop ended on: the
   shadow passes redraw every caster per light (`perf_backlog.md`, "Iteration 3").

## What was done, and why not more

Item 11 was a documentation slice with no behaviour change, and every candidate below changes
what is drawn. Each needs the look-preserving proof (a before and after shot with `tools/shot.sh`, the budget
numbers, and the targeted tests) and belongs in item 12 or later, not in a docs commit.

Candidates, in the order they are worth trying:

- Merge the rack wall's static plate geometry into one mesh per module (or per face) with a texture or vertex
  colours for the skin, keeping knobs and jacks as nodes: likely hundreds of draws and 100k+ triangles saved.
- Let the rack wall's far-side geometry go (a module's second face, the case's back) until the camera is in the
  annex, with a visibility range on the annex node.
- (Done: the +772 draws, see above.)
- MultiMesh for the timeline's clips.

## Noise

Frame time on this machine moved 30 % between runs of the same build (HEAD, 13 tracks, fitted: 18.07 ms in the
first run, 13.42 ms in the second, same code, same flags): the GPU and the compositor are shared, and nothing here
pins clocks. Only compare frame times from runs alternated back to back, three or more pairs, as the perf backlog's
method note says; compare draws, primitives, nodes and meshes freely, they do not move.
