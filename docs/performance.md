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
goes through `offscreen_run`. Draw calls, primitives, nodes and meshes are deterministic; frame times are not
(see "Noise").

The target is a standalone headset: this room twice (once per eye) at 72 Hz, 6.94 ms a frame, on a mobile GPU. Desktop frame times are not that budget; read the counts and the slope.

## Numbers at HEAD (2026-11-07)

Desktop GPU, 1600x900, vsync off, studio venue, arrangement 0, quiet room, shadows as the desktop renderer has
them. Run: `tools/budget.sh 13 48`.

| tracks | pose | prims | draws | objects | frame ms | worst ms | nodes | start ms | mem MB |
|---|---|---|---|---|---|---|---|---|---|
| 13 | fitted | 499120 | 3909 | 4225 | 18.07 | 26.99 | 10713 | 4813 | 692.7 |
| 13 | wide | 1096214 | 7070 | 7456 | 16.60 | 23.17 | 10713 | 4744 | 695.4 |
| 48 | fitted | 618034 | 4825 | 5131 | 21.23 | 32.29 | 13544 | 4838 | 720.2 |
| 48 | wide | 1326790 | 7542 | 7930 | 21.56 | 27.83 | 13544 | 4647 | 723.2 |

Slope: 35 more tracks cost about 470 draws and 230k primitives in the wide pose (about 13 draws a track), and
the nodes grow from 10.7k to 13.5k (80 per track).

Surfaces, 13 tracks, wide (meshes / labels / triangles): RackWall 796 / 102 / 412190, Timeline 661 / 257 / 91024,
StageTable 142 / 97 / 16284, Tv 124 / 73 / 1468, TapeDeck 50 / 20 / 11520, Console 56 / 90 / 2740, Rack 46 / 31 /
1268, EqWall 31 / 33 / 262, PatchWall 25 / 74 / 166, Patchbay 15 / 60 / 56, Levels 7 / 66 / 84, ClipEditor 2 / 1 / 24.

## Against the start of the branch

The same tool on a clean checkout of `master` (the branch point `d3ad499`), same machine, same run, 13 tracks, no
saved user data on either side (`XDG_DATA_HOME` empty):

| | prims | draws | nodes | frame ms (fitted / wide) | mem MB |
|---|---|---|---|---|---|
| master | 403030 / 924244 | 3258 / 6298 | 11410 | 20.6 / 22.1 | 741 |
| HEAD | 439906 / 1096214 | 3587 / 7070 | 10713 | 13.4 / 16.8 | 692 |

What this says, and does not say:

- **Nodes are 6 % fewer and memory 49 MB lower** at HEAD. Both were identical in two runs, so it is real; the cause was not
  traced (the branch removed code from the studio and several venues, and moved the layout data out of code).
- **Draws and primitives are higher at HEAD** (wide: +772 draws, +172k prims; fitted: +329 draws, +37k prims),
  and the cause is not in the refactor's descriptions, which say "no behaviour change". Two of the surfaces differ:
  the Tv surface has 124 meshes against 40 at master (+1008 triangles), and RackWall 796 against 777 (+4.9k
  triangles). Those two explain about 100 meshes; the rest of the difference is not in a surface, so it is the
  venue or the pieces standing in the room (layouts, the made-room and edit work all landed on this branch). It
  has not been bisected. **Left for item 12**: bisect with `tools/budget.sh 13` over the slice commits
  (`git log --oneline master..HEAD`), starting from the Tv surface (`PadDeck`, slice 12a-2) and the layout-driven
  placement (slice 6).
- **Frame times were lower at HEAD in this run, by a lot (13 against 21 ms), and should not be believed to that
  precision.** See "Noise".
- The pre-modular baseline in `docs/perf_backlog.md` (studio:0, 13 tracks, wide: 7.3 ms, 4814 draws, 649k prims,
  3807 nodes) predates the modular room (`9a2b1f1`, 2026-11-02), whose wall alone is now 412k triangles; it is not
  comparable with either row above.

## Where the cost is

1. **RackWall**: 796 meshes and 412k triangles, 38 % of all primitives in the wide pose. Every module plate, knob,
   jack and cable is a mesh of its own, and the modular room is built onto every venue, so it is paid everywhere.
2. **Timeline**: 661 meshes, 91k triangles, 257 labels (a clip per mesh).
3. **Start-up**: 4.7 to 4.8 s to the first frame (`start ms`), against about 2.9 s in the older breakdown in
   `perf_backlog.md`; the room has more in it, and 10.7k nodes are built in code.
4. **Draw calls** at about 3600 (fitted) to 7000 (wide) are the render-side problem the older loop ended on: the
   shadow passes redraw every caster per light (`perf_backlog.md`, "Iteration 3").

## What was done, and why not more

Nothing in this pass: item 11 is a documentation slice with no behaviour change, and every candidate below changes
what is drawn. Each needs the look-preserving proof (a before and after shot with `tools/shot.sh`, the budget
numbers, and the targeted tests) and belongs in item 12 or later, not in a docs commit.

Candidates, in the order they are worth trying:

- Merge the rack wall's static plate geometry into one mesh per module (or per face) with a texture or vertex
  colours for the skin, keeping knobs and jacks as nodes: likely hundreds of draws and 100k+ triangles saved.
- Let the rack wall's far-side geometry go (a module's second face, the case's back) until the camera is in the
  annex, with a visibility range on the annex node.
- Bisect the +772 draws above before anything else; if it is a regression it is the cheapest win there is.
- MultiMesh for the timeline's clips.

## Noise

Frame time on this machine moved 30 % between runs of the same build (HEAD, 13 tracks, fitted: 18.07 ms in the
first run, 13.42 ms in the second, same code, same flags): the GPU and the compositor are shared, and nothing here
pins clocks. Only compare frame times from runs alternated back to back, three or more pairs, as the perf backlog's
method note says; compare draws, primitives, nodes and meshes freely, they do not move.
