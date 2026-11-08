# Tools

Everything under `tools/` and what it is for. All scripts run from any directory (they `cd` to the repo). **Any
tool that opens a game window goes through `offscreen_run` (`. tools/offscreen.sh`), which puts the window on
workspace 10 on Hyprland; never run a bare `godot --path .`.** The shot, budget and walkthrough scripts already do.

## Looking at the game

| Tool | What |
|---|---|
| `tools/shot.sh [out.png] [frame] [quit]` | run the studio in a real window and write a PNG (`SHOT_CAM`, `SHOT_RES`, `SHOT_ARGS=--venue grid`...). The harness is the `Screenshot` autoload `tools/screenshot.gd` (inert unless `--shot`), split into `ShotArgs` (the command line), `ShotScenes` (scenes a flag asks for), `ShotFrames` (the per-frame script and the capture), `ShotDrive` (the scripted hand), `ShotDemos` (longer demonstrations). To add a scene: a flag in `shot_args.gd`, the setup in `shot_scenes.gd`. |
| `tools/shot.sh` flags for the layout, maker and mod systems | `SHOT_DATA_HOME=dir` gives the run its own user data (`XDG_DATA_HOME`; the window is started by the compositor, so it is passed as `env` in the command), and is required for the flags that write: `--rack-patch f.json` (put as the host's autosave, `user://patches/_current.patch.json`), `--delta f.json` (a room delta, filed under the `room` key it names, e.g. `studio.0`), `--mod folder` (copied into `user://mods/`, repeatable), `--make-room size[:zone+zone\|all[:Title_words[:style]]]` (frame 3: the maker's own MAKE, the band taken in). They refuse to run on the real user data dir. `--panel layout[:piece[:nudge]]` / `--panel maker` open the F3 / F4 panel from frame 6. `--walk rack[,dist[,sideways[,height[,turn]]]]` stands square to the modular rack wall (along its normal; metres along the wall from its middle). Code: `ShotArgs`, `ShotScenes.install_files/_make_a_room/_open_panel`, `ShotFrames`. Example: `SHOT_DATA_HOME=/tmp/d SHOT_ARGS="--no-hud --walk rack,1.5,-1.2,1.75 --rack-patch p.json --mod mods_examples/dawlings.sample.pluck" tools/shot.sh out.png`. Live room framing: `--walk 2.5,11.5,0.6,-0.1`. |
| `tools/light_check.sh [venue...]` | photograph every venue from the standing spot, across the room and from the zones; exits non-zero when one is over the light budget |
| `tools/walkthrough.sh`, `tools/session_shot.sh` | photograph `docs/session_walkthrough.md` against a live Reaper; a two-person session from both sides |
| `tools/movie.sh out.mp4` | record a clip with Godot's movie writer and encode it |
| `tools/layout_dump.tscn` + `tools/layout_map.py` | headless floor-plan dump per venue (what stands where) and the PNG maps/contact sheet |
| `tools/look_preview`, `foley_preview`, `glove_preview` (`.gd`/`.tscn`) | ghost looks; every synthesised sound as a WAV and SVG; the hands |

## Measuring

| Tool | What |
|---|---|
| `tools/budget.sh [sizes]` (`VENUE=`) | frame time, draws, primitives, nodes, memory and per-surface meshes at 13/24/48/90 tracks, two poses; the `Budget` autoload is `tools/budget.gd` (inert unless `--budget`). Numbers: `docs/performance.md`. |
| `tools/patchbay_stress.tscn` | the routing bay at several sizes, what it costs |
| `tools/render_demo_song.gd` | renders the demo song's parts and times them |
| `tools/audio_latency.sh`, `tools/keys_latency.sh` | how far behind the host a guest hears the mix; key-down to sound through the keys helper |

## Checking the code

| Tool | What |
|---|---|
| `tools/quality_check.sh [--all] [--docs] [--limit N]` | files over 800 lines (substantively changed ones, decision 8), unreferenced public symbols, public signals and non-trivial funcs without a `##` comment and files without a class header; exit 1 when anything is reported. Rules at the top of `tools/quality_check.py`. |
| `tools/verify.sh` | the headless suite, 90 s timeout, flags `SCRIPT ERROR`. Its timeout is stale: the full suite takes 20 to 40 minutes now (`docs/testing.md`). |
| `godot --headless --path . --import` | the import check, prints `SCRIPT ERROR` / `Parse Error` for a script that does not compile |

## Sessions, rigs and probes

| Tool | What |
|---|---|
| `tools/session.sh` | a host and a guest on this machine (`--reaper`, `SHOT=` to capture the guest) |
| `tools/session_probe.sh [--reaper\|--built-in]` | headless host and guest on one timeline; non-zero if either saw a failure. `PROBE_NORAY=1\|relay` joins by code through a local noray. The probe is `tools/probe/session_probe*.gd` (`session_probe_host`, `_guest`, `_items`, `_room`, `_takes`, `_render`). |
| `tools/tour_probe.sh N` | a Tour run with N players, every flaw fixed and every part played |
| `tools/noray_local.sh up\|down\|status` | a noray on loopback for the above |
| `tools/pair_probe.tscn` | host and guest with the rack (`PAIR=host` / `PAIR=guest`) |
| `tools/reaper_rig.sh up\|down\|status`, `tools/rig/` | a real Reaper kept apart from the user's, for live probes (`tools/probe/live_check`, `live_dump`, `flat_live`, `plugin_tablet_live`, `reaper_menu_live`, `hosted_plugin_live`) |

## Building

`tools/rack_build.sh` (the rack engine from the pinned submodules), `tools/rack_probe.sh` (one Plaits note),
`tools/build_quest.sh` (APK), `tools/fetch_openxr_vendors.sh`, `tools/make_cards.sh`, `tools/make_action_map.gd`,
`tools/blender/`
(model scripts), `tools/discord_bridge/`, `tools/mock/`.

### Checking an export

`godot --headless --path . --export-pack Linux /tmp/x.pck` needs no display and uses the installed templates. All three presets
in `export_presets.cfg` use `export_filter="all_resources"`; Godot imports `.json` as a resource, so `mods/**/*.json`,
`layouts/**/*.json` (schemas, `layouts/import/floor_v1.json`) and `core/music/rack/modules.json` ship without an
`include_filter`. Only `tests/`, `mods_examples/`, `tools/probe/`, `shots/` and `docs/` are excluded. To list what is in a pack,
call `ProjectSettings.load_resource_pack(pck)` from a `--script` and walk `DirAccess` over `res://mods` and `res://layouts`
(checked 2026-11-07: all 43 JSON files present and parseable). If a preset's filter ever changes to `scenes_only` or
`selected_resources`, add `include_filter="mods/*, layouts/*, core/music/rack/modules.json"`. Run `git checkout project.godot`
afterwards.

## How to add a tool

A script gets a header comment saying what it does, how to run it and what its exit status means; a game-window tool
sources `tools/offscreen.sh` and starts the window with `offscreen_run`; a Godot-side harness that observes a running
game is an autoload that stays inert unless its flag is passed (see `Budget`, `Screenshot` in `project.godot`). Add
a line here.
