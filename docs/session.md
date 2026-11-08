# Session and networking

The host is the authority. Everyone else is a guest who asks the host for changes and adopts what the host says.
One `Session` autoload per process owns the socket; this page is the map of its files. The ways in (LAN, address,
join code through noray) are `docs/multiplayer.md`; the DAW/Reaper wire is `docs/transport.md`; the physical-room
frame for AR is `docs/colocation.md`.

## Files

`Session` (`core/session/session.gd`, autoload, `extends SessionBase`, 793 lines) keeps the state and the `@rpc`
entry points. Bodies live in ten `RefCounted` helpers held as fields (state stays on the autoload; each helper has
`var session: Session`; the autoload keeps a one-line delegate with the `@rpc` line for every name the network, a
string or another file reaches):

| Field | Class | Owns |
|---|---|---|
| `linking` | `SessionLink` | hosting and joining online by code (noray), punched and relayed paths, the roster's route for a guest |
| `admitting` | `SessionRoster` | peers connecting and leaving, hello and admission, the door code, the audio ticket |
| `guest_writes` | `SessionIntents` | a guest's write path: an intent sent to the host and applied there, save and render announcements |
| `take_work` | `SessionTakes` | a guest's recording: begin, chunks, end; the host writing them |
| `room_work` | `SessionRoom` | the room as the host has it: `publish_room`, `ask_room`, made items, tour run and roulette roll rows |
| `movers` | `SessionMotion` | things pushed, carried, flown, used and hit |
| `sharing` | `SessionShares` | a guest's devices offered to the host, allowed one kind at a time |
| `play_work` | `SessionPlay` | notes, controls and jack events as played, with the host's checks |
| `replicating` | `SessionState` | track spectra, replicated project state, presence (head and pointing), holds on controls |
| `life` | `SessionLife` | starting solo, hosting, joining, leaving, who is the authority, renaming |

`SessionBase` (`session_base.gd`) is the vocabulary: ports, channels, limits, the verb tables `ROOM_VERBS` and
`TOUR_VERBS`, the `Note` enum and every signal. Beside the session: `Presence` (everyone else's heads, hands and
what they hold), `MixFeed`/`MixSource`/`JitterBuffer`/`HeardClock`/`SongClock` (the host's programme audio to guests
on its own UDP socket, and which moment of the song a guest hears), `GuestMidi`/`GuestPlay`/`GuestAudio`/`GuestLive`/
`MonitorSynth`/`TheirKeys` (a guest's keys and microphone), `FileSend` (sound files from a guest into the host's
project), `NorayLink`/`InternetDoor` (join by code, UPnP), `Glove`/`GhostLook`/`PoseTrail` (how others look),
`PatchHost` (jacks, `core/session/patch_host.gd`, a Studio helper).

Channels (constants in `SessionBase`): game traffic on ENet's default; `AUDIO_TAKE_CHANNEL` 3, `MOTION_CHANNEL` 4,
`KEYS_CHANNEL` 5, `CONTROLS_CHANNEL` 6, `SPECTRA_CHANNEL` 7, `MIX_CHANNEL` 9, `LIVE_CHANNEL` 10, each separate so one
kind of traffic never queues behind another.

## How a change to the room flows

1. A guest calls `Session.ask_room(verb, args)`. `SessionRoom.room_ask_is_valid` checks the verb is in
   `ROOM_VERBS` and each argument has the declared type. The guest goes ahead and predicts it; the ask's number
   comes back in the room row's `acks`.
2. The host receives `_room_asked` (an `@rpc` on `Session`), checks the sender is a member, and emits
   `Session.room_asked(verb, args, from)`. (The host's own asks skip the network and emit it directly.)
3. `Studio.room_rows._on_room_asked` (connected in `SurfaceHost`) is a `match` on the verb that calls the studio
   helper that does it.
4. The studio publishes: `RoomRows.room_state()` builds the dictionary and `Session.publish_room` sends it to
   everyone. A refused ask still gets the room as it is, which takes the guest's prediction back.
5. Guests receive `_receive_room`, set `Session.room`, emit `room_changed`; `RoomRows.apply_room` adopts it.

Other flows follow the same shape with their own verb tables and rows: the tour (`TOUR_VERBS`, `publish_tour`), the
roulette roll (`publish_roll`), made items (`made_changed`), the project state (`SessionState`, DAW intents).

## What a guest sees move (meters, clock, the modular room, the lights)

A guest's DAW is an `OfflineBackend` holding the replicated cache (`is_authority` false), never a link to the host's
engine. Everything that moves on a guest's screen comes from the host's volatile stream, `SessionState.broadcast_state`
at 20 Hz, unreliable: `/master/vu/*`, `/track/N/vu/*`, `/time`, `/beat/str`, and `/rack/live`.

- **Meters and clock.** The stand-in's own meter generator runs only where `is_authority` (solo, the host's stand-in).
  A guest used to run it too, which overwrote the host's meters every frame with a canned pattern (and drove the
  lights from it); now `OfflineBackend._drive_meters` on a guest only runs the playhead on between the host's `/time`.
- **The modular room.** The rack engine is a process on the host, so a guest's `RackVoice` never runs. The host's
  `RackHost` records `/rack/live` (`RackLive`: each module's meter as a byte, each sequencer's step, the scopes as
  bytes every other tick, the glow's level and hit; `[false]` once when the engine stops) from its 30 Hz follow; it
  lands in `MixState.rack_live`, and a guest's `RackHost._show_live_rack` feeds the wall (step lights, pillars,
  scopes, glow) and the annex from it. A reading older than `RackLive.STALE_MSEC` counts as quiet. About 150 to
  600 bytes a tick per guest, nothing at all with nobody connected.
- **The lights.** `ViewHost` pulses the venue with the larger of the master meter and `RackHost.rack_level()` (the
  engine's level on the host, the replicated one on a guest), so a rack that sounds on a monitor bus instead of a
  track still moves the room.
- **The audio patchbay** (`PatchWallSurface`) is the machine's own graph and stays local; the one exception is the
  `dawlings_mix` stream on a guest that is not playing the host's mix here (same machine), which reads the
  replicated master level instead of its own silent bus.

Tests: `tests/guest_live_tests.gd`.

## How to add an rpc verb (a thing a guest may ask of the room)

1. Add the verb and its argument types to `SessionBase.ROOM_VERBS`. Strings, numbers, `StringName`, `Vector3`,
   `Transform3D`, arrays; a new type needs nothing else, the checker compares `typeof`.
2. Add an arm to `RoomRows._on_room_asked` that checks what only the host can know and calls the helper that does it.
3. If guests must see the result, put it in `RoomRows.room_state()` and read it in `RoomRows.apply_room()`.
4. In the guest's UI call `Session.ask_room(verb, args)` and predict locally; keep what to undo until the ack.
5. Test with a host `Studio` and a guest `Studio` in one tree (the pattern of `tests/layout_share_tests.gd`) and,
   for the wire, `tools/session_probe.sh` (docs/tools.md).

A new raw network message (not a room verb): write the body in the fitting `Session*` helper, add the delegate with
its `@rpc("any_peer" | "authority", ...)` line to `session.gd` (an rpc must be declared on the node the network
addresses, which is the autoload), and a doc comment saying who may call it. A new channel constant goes in
`SessionBase`.

## Tests

`tests/run_tests.gd` (the `_test_a_guest_*`, `_test_the_host_*` groups), `tests/layout_share_tests.gd` (two studios in
one tree), `tests/guest_live_tests.gd` (a guest follows the host's meters, clock and rack), `tests/fake_noray.gd` (a noray in-process), `tools/session_probe.sh` (a headless host and guest on one
timeline), `tools/pair_probe.gd`. See `docs/testing.md`.
