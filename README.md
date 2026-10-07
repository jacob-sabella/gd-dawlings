# reaper-3d

Reaper, rendered as a room full of hardware instead of a window full of panels.

The desk is a desk. The plugins are rack units with knobs on them. The routing is cables you can
see hanging. The transport is a machine with reels that turn while it rolls. Reaper is still
doing all of the work — this is a control surface that happens to be a 3D studio.

The part that shapes everything else: **several people, one physical room, different eyes.** One
at a monitor with a mouse, two in passthrough headsets standing where the console appears to be,
one in full VR somewhere else entirely. They all reach for the same channel 8 fader and they all
see the same result.

```
                        ┌──────────┐
                        │  REAPER  │   the only source of truth
                        └────┬─────┘
             OSC ────────────┤──────────── ReaScript (file IPC)
      values that move       │       structure that does not
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
godot --path . -- --reaper                   # host, OSC to a local Reaper
godot --path . -- --reaper --host            # host, and open the session to peers
godot --path . -- --join 192.168.1.40 --ar   # join someone else's session, in passthrough
godot --path . -- --view 20:52              # open the timeline on bars 9-27 (seconds: start:span)
```

With no Reaper it comes up on a synthetic 12-track mix with the meters moving, so the studio can
be built, lit and photographed without a DAW in the loop. Right-drag orbits, the wheel zooms,
WASD walks.

## Other DAWs

Reaper is the first backend, not a hard-coded dependency. Nothing under `hardware/` knows the
protocol: a fader calls `DAW.set_track_volume(i, v)` on the `DAW` autoload, which holds exactly
one `DAWBackend`. `ReaperBackend` turns that into OSC; `OfflineBackend` writes it to a cache and
drives the synthetic mix.

To add one, extend `core/daw/daw_backend.gd`:

- implement the ~20 command verbs (`set_track_volume`, `set_fx_param`, `transport_play`,
  `create_send`, …) and push incoming state through `MixWire.apply(state, address, args)`;
- answer `can(capability)` honestly — the patchbay greys out when `ROUTING` is false rather
  than dropping writes on the floor;
- override `taper_to_db` / `db_to_taper` if your fader law is not Reaper's, so the dB caption
  under each fader stays true.

Then hand it to `DAW.use(MyBackend.new(), true, options)` from `scenes/bootstrap.gd`. Surfaces,
replication and the session layer need no changes — guests speak verbs, not protocols, so a
guest never learns which backend the host opened.

## Connecting a real Reaper

Two channels, because one is not enough — see `docs/transport.md` for why.

1. **OSC**, for everything that moves. Copy `reaper/Reaper3D.ReaperOSC` into Reaper's
   `OSC/` folder, then add an OSC device under *Options → Preferences → Control/OSC/web*:
   device port **9000**, local listen port **8000**, pattern config **Reaper3D**.
2. **ReaScript**, for everything structural. Copy `reaper/reaper3d_bridge.lua` into Reaper's
   `Scripts/` folder and run it once from the action list. Without it you get a full console,
   a working transport and live racks; what you lose is the ability to *create* routing from the
   patchbay, because OSC has no message for it.

## Layout

| Path | What lives there |
|---|---|
| `core/daw/` | The DAW-agnostic layer: backend contract, mix state, wire vocabulary, offline mix |
| `core/reaper/` | The Reaper backend: OSC codec, UDP peer, the ReaScript bridge |
| `core/session/` | Who is in the room, who may write to the DAW, intent forwarding |
| `core/presentation/` | Surfaces, and the per-viewer choice of screen / room / set |
| `core/xr/` | OpenXR startup, and the two-point shared room calibration |
| `core/input/` | One grab contract for mouse, controller and hand |
| `hardware/` | Console, FX racks, tape deck, patchbay — built from live state |
| `scenes/` | Entry point and the studio itself |
| `reaper/` | The half that runs inside Reaper |
| `tools/` | `verify.sh` (tests), `shot.sh` (screenshots) |

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

1. `docs/architecture.md` — the three-way split, and why a surface may never ask what it is
2. `docs/transport.md` — the Reaper link, what each channel can and cannot carry
3. `docs/colocation.md` — how several headsets agree where the console is
4. `docs/loop_backlog.md` — what is scaffolded versus what is finished
