# dawlings

A room full of hardware instead of a window full of panels. Multiplayer: several people stand
in the same studio and work the same desk.

The desk is a desk. The plugins are rack units with knobs on them. The routing is cables you can
see hanging. The transport is a machine with reels that turn while it rolls. None of that hardware
knows or cares what is actually making the sound — it calls verbs on a `DAW` autoload, and
whatever answers decides what happens. By default that is a DAW engine built into the game
itself, with no install required. If you already have a real project in Reaper, dawlings can
drive that instead, live, over OSC.

The part that shapes everything else: **several people, one physical room, different eyes.** One
at a monitor with a mouse, two in passthrough headsets standing where the console appears to be,
one in full VR somewhere else entirely. They all reach for the same channel 8 fader and they all
see the same result.

```
          ┌──────────┐              ┌──────────┐
          │  GODOT   │              │  REAPER  │   one of two backends
          │ BACKEND  │              │          │   behind the same DAW verbs
          └────┬─────┘              └────┬─────┘
               │ no process to miss      │ OSC (values) + ReaScript (structure)
               └────────────┬─────────────┘
                        ┌────┴─────┐
                        │   DAW    │   autoload: one backend, one door
                        └────┬─────┘
                        ┌────┴─────┐
                        │   HOST   │   exactly one process holds the link
                        └────┬─────┘
                  ┌──────────┼──────────┐
              ┌───┴───┐  ┌───┴───┐  ┌───┴───┐
              │screen │  │  AR   │  │  VR   │   each picks, per surface,
              │ panel │  │ room  │  │  set  │   where it wants that surface
              └───────┘  └───────┘  └───────┘
```

## Running it

```bash
godot --path .                               # offline stand-in, screen participant
godot --path . -- --built-in                 # the built-in DAW: Godot's own audio, actually playing
godot --path . -- --reaper                   # host, OSC to a local Reaper
godot --path . -- --reaper --host            # host, and open the session to peers
godot --path . -- --join 192.168.1.40 --ar   # join someone else's session, in passthrough
godot --path . -- --xr                       # host or join in VR, not passthrough
godot --path . -- --view 20:52               # open the timeline on seconds 20-52 (start:span)
godot --path . -- --venue grid               # stand in a given venue (studio / grid / chalk / …)
```

With no Reaper it comes up on a synthetic ten-track mix with the meters moving — silent by
default, audible with `--built-in` — so the studio can be built, lit and photographed without a
DAW in the loop. An exported build defaults to `--built-in` on its own, since whoever runs it
has no Reaper; run from the editor and you get the silent stand-in unless you ask otherwise.
Right-drag orbits, the wheel zooms, WASD walks. V cycles the venues — the studio room, a
synthwave grid, the chalk zone, and others. Only the world changes; the gear and the layout stay
the same. See `docs/venues.md`.

## Tour mode

A roguelike gig-rescue mode, one person alone or a band of up to eight online. A run starts by
breaking open the road case chained shut at the back of the room — the host throws things at it
until the lid gives. Each run is a gig in trouble: a brief hands the band a looped song with
something wrong in it (a buried vocal, a muddy EQ, a dragging lane, a hard-panned guitar, a
kicked tempo, …) and a clock. Fix the flaws on the desk, play the parts the brief asks for, and
the crowd lets you move on; chaos events hit the room at random along the way, drafted
instruments and cards carry over between briefs, and reputation tracks how the run is going
overall. Busier with every friend who joins, winnable solo. See `core/tour/`, the case itself in
`core/items/tour_case.gd`, and the "Tour" section of `docs/loop_backlog.md` for what is actually
built versus still aspirational.

## Other DAWs

Reaper is one backend, not a hard-coded dependency. Nothing under `hardware/` knows any DAW's
protocol: a fader calls `DAW.set_track_volume(i, v)` on the `DAW` autoload, which holds exactly
one `DAWBackend`. `ReaperBackend` turns that into OSC; `OfflineBackend` writes it to a cache and
drives the synthetic mix; `GodotBackend` is the same stand-in made audible, on Godot's own
`AudioServer` — the engine behind it, `dawkit`, is documented below.

To add a backend, extend `core/daw/daw_backend.gd`:

- implement the command vocabulary (`set_track_volume`, `set_fx_param`, `transport_play`,
  `create_send`, and the rest of the DAW's verbs) and push incoming state through
  `MixWire.apply(state, address, args)`;
- answer `can(capability)` honestly — the patchbay greys out when `ROUTING` is false rather
  than dropping writes on the floor;
- override `taper_to_db` / `db_to_taper` if your fader law is not Reaper's, so the dB caption
  under each fader stays true.

Then hand it to `DAW.use(MyBackend.new(), true, options)` from `scenes/bootstrap.gd`. Surfaces,
replication and the session layer need no changes — guests speak verbs, not protocols, so a
guest never learns which backend the host opened.

## The built-in engine: dawkit

The built-in DAW (`--built-in`, `GodotBackend`) is built on **dawkit**, a DAW engine that runs
inside Godot — a project model, a mixer and transport on `AudioServer`, and project files in
DAWproject, the open interchange format Bitwig, Studio One and Cubase also read and write.
dawkit is developed as its own repository (`vendor/dawkit`, a git submodule), with no reference
to anything game-specific: dawlings adapts to dawkit in `core/built_in/project_bridge.gd`, never
the other way around. See `docs/architecture.md` for the split and `vendor/dawkit/README.md`
for the engine itself.

## Connecting a real Reaper

Two channels, because one is not enough — see `docs/transport.md` for why.

1. **OSC**, for everything that moves. Copy `reaper/Dawlings.ReaperOSC` into Reaper's
   `OSC/` folder, then add an OSC device under *Options → Preferences → Control/OSC/web*:
   device port **9000**, local listen port **8000**, pattern config **Dawlings**. Set the
   outgoing max packet size to **16384** and the wait between packets to **1** ms: at Reaper's
   defaults the meters crowd out everything else and a 40-track session takes many seconds to
   name its tracks. `tools/reaper_rig.sh up` runs a private, silent Reaper set up exactly this
   way, with a 40-track test session, for checking the link without touching your own setup.
2. **ReaScript**, for everything structural. Copy `reaper/dawlings_bridge.lua` into Reaper's
   `Scripts/` folder and run it once from the action list. Without it you get a full console,
   a working transport and live racks; what you lose is the ability to *create* routing from the
   patchbay, because OSC has no message for it.
3. **Recording from the desk.** Untick *Preferences → Recording → Prompt to save/delete/rename
   new files* (or tick its "only when stopping" options off). With it on, every take you stop
   from the desk opens a dialog in Reaper's window, and while that dialog is open Reaper ignores
   OSC entirely — the desk goes dead until someone clicks it away.

## Layout

| Path | What lives there |
|---|---|
| `core/daw/` | The DAW-agnostic layer: backend contract, mix state, wire vocabulary, offline mix |
| `core/built_in/` | The built-in backend: `GodotBackend` on `AudioServer`, the demo song, the dawkit bridge |
| `core/reaper/` | The Reaper backend: OSC codec, UDP peer, the ReaScript bridge |
| `core/tour/` | Tour mode: briefs, flaws, parts, chaos events, drafts, reputation |
| `core/session/` | Who is in the room, who may write to the DAW, intent forwarding |
| `core/presentation/` | Surfaces, and the per-viewer choice of screen / room / set |
| `core/venues/` | The worlds the studio can stand in, and their shaders |
| `core/xr/` | OpenXR startup, and the two-point shared room calibration |
| `core/input/` | One grab contract for mouse, controller and hand |
| `core/items/` | Pickable and interactive room props, including the Tour road case |
| `hardware/` | Console, FX racks, tape deck, patchbay — built from live state |
| `scenes/` | Entry point and the studio itself |
| `reaper/` | The half that runs inside Reaper |
| `vendor/dawkit/` | The built-in DAW engine, as its own repository (git submodule) |
| `tools/` | `verify.sh` (tests), `shot.sh` (screenshots), `tour_probe.sh` (headless Tour run) |

## Verifying

```bash
tools/verify.sh                       # headless tests: OSC framing, state parsing, room maths
tools/shot.sh shots/latest.png        # render a real frame and look at it
SHOT_CAM="0,-0.28,1.35,0,0.95,0" tools/shot.sh shots/console.png
```

`verify.sh` covers the things that fail *silently* — a mispadded OSC packet is ignored rather
than rejected, a track index off by one moves a different fader, a room calibration a degree out
just puts your console slightly in the wrong place. None of them announce themselves.

It covers nothing about how any of it looks. That is what `shot.sh` is for.

## Reading order

1. `docs/architecture.md` — the three-way split, the DAW-as-backend seam, and the dawkit split
2. `docs/transport.md` — the Reaper link, what each channel can and cannot carry
3. `docs/colocation.md` — how several headsets agree where the console is
4. `docs/loop_backlog.md` — what is scaffolded versus what is finished, Tour included
