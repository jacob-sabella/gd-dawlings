# The control API (MCP server) and the built-in assistant

Status: built (this page began as the design; "As built" below is what is in the tree, the rest is the reasoning). Two features, one spine.

1. **An MCP server** for the running game: add, modify, query and delete on everything (project, tracks, mix, FX,
   timeline, rack, room, mods), by any MCP client.
2. **A built-in assistant**: a chat panel in the game, backed by Claude Code for now, that answers questions and
   does things by calling those MCP tools.

The assistant is just the first client of the server. Build the server so it stands alone; the assistant adds a
process launcher and a panel.

## As built

**Use it from a terminal.** Start the game with `--control` (or `DAWLINGS_CONTROL=1`, or `server=true` under `[control]` in
`user://control.cfg`); it serves MCP over HTTP on `127.0.0.1:47100` to `47199` (the first free) and writes
`user://control.json` (`url`, `token`, `port`, `pid`). Then:

    claude mcp add --transport http dawlings http://127.0.0.1:47100/mcp --header "Authorization: Bearer <token>"

A client that is not the assistant has no one to ask, so a destructive (tier 2) call from it is refused unless the game
was started with `--control-yes` (`DAWLINGS_CONTROL_YES=1`, `auto_confirm=true`). `tools/list?domains=a,b` returns only
those domains' schemas; `tools_search` finds tools by words; `batch` runs a list of calls as one change set.

**Ask it in the room.** The wall station `assistant` (right wall of the control room, past the Workshop's place; ASK,
CANCEL, NEW CHAT, OPEN) and F10 (the whole conversation, ALLOW and DENY for what it asks first) are two views of one
`Assistant`. Anyone may ask, guests too: a guest's question goes to the host (`Session.ask_assistant`), the run is the
host's `claude` with the host's budget and context, every call acts as the asker, the confirm card goes to the asker, the
host may cancel any run, one run at a time, and the transcript is shown to the room. `--model` defaults to `sonnet`
(`model=` under `[control]`; `""` for the CLI's default): all tool schemas are in a conversation's first turn, about 50k
tokens, so a first question costs about $0.20 and the next ones in the same conversation a few cents.

**Files.**

| | |
|---|---|
| `core/control/control_tool.gd`, `control_api.gd`, `control_refs.gd`, `control_tools.gd` | a tool (name, summary, JSON-schema arguments, tier, handler) and its checks; the registry with `invoke`, `batch`, change sets and snapshotters (the rack registers one); addressing tracks by name, `#n` or number; the list of domains |
| `core/control/tools_{project,track,fx,item,rack,room,mods,requests}.gd` | the 223 tools: project and transport, tracks and mix, FX and automation and looking, items and notes, rack and module help, room (every `ROOM_VERBS` entry exposed or listed in the test as not), mods and help |
| `core/control/control_server.gd` | the HTTP/JSON-RPC server: bearer token or a per-run token, local `Host` and `Origin` only |
| `core/control/assistant_runner.gd`, `assistant_stream.gd`, `assistant.gd`, `control_host.gd` | the locked-down `claude` command and its stream; the coordinator (queue, runs, confirm cards, relay to guests); what the bootstrap attaches |
| `hardware/assistant/assistant_panel.gd`, `assistant_screen.gd` | the wall board and the F10 overlay |
| `tools/probe/assistant_live.tscn` | the assistant for real: the game headless, a question asked, the real `claude` working the game over the server |

**Feature requests.** When a player asks for something the game cannot do, reports something broken, or asks it to note
a request, the assistant writes it down with `requests_add` (`core/control/tools_requests.gd`): an entry appended to
`user://feature_requests.md` on the host's machine (on Linux `~/.local/share/godot/app_userdata/dawlings/feature_requests.md`)
with the time, who asked, the kind (feature, bug, idea), a title, what they want and why, and their own words.
`requests_list` reads the titles back so one is not written twice. It is the only file a tool writes, and only there.

**CANCEL and NEW CHAT.** CANCEL ends the run at once: the board says cancelled, the run's token is revoked, the next ask
can start, and the CLI's process group is sent SIGTERM and, two seconds on, SIGKILL. NEW CHAT clears the transcript and
the confirm cards from this machine's view and forgets the conversation (on the host), so the next ask starts fresh; a run
still going stays.

**What the assistant's `claude` may do.** `--restricted --strict-mcp-config --mcp-config <its own file> --tools ""
--allowedTools mcp__dawlings --permission-mode dontAsk`, in a scratch folder, its token revoked when it ends: it has the
game's tools and nothing else (no shell, no files, no network, no other MCP server). Nothing of tier 3 (the filesystem,
the session and hosting, settings, the Workshop, code) is a tool at all; `mods_import` takes a mod folder or zip through
`ModShare`'s checks, `item_import` only audio files under the project, `user://` and the user's Music, Documents,
Downloads and Desktop.

**Tests** (targeted, `DAWLINGS_TESTS=<name>`): `_test_control_api_{rules,batches,refs,server,socket,stream,command,panel,run}`
(the spine, a real loopback HTTP round trip, the command line, the board, and a whole run against
`tests/fixtures/fake_assistant.sh`) and `_test_control_{project,track,fx,item,rack,room,mods}`.

**Known edges.** The OUT module of the rack cannot be removed, so `rack_clear` leaves it. An undo cannot restore a rack module
whose mod is missing. `rack_render` needs the built engine. FX on the master track are not tools (the DAW's FX verbs take
tracks). Time is in seconds, tempo in BPM, levels in dB, pan -1 to 1.

## What is there to build on

| Need | Already in the repo |
|---|---|
| One verb layer for the DAW | `Daw` (`core/daw/daw.gd`): ~150 methods (`set_track_volume`, `add_fx`, `move_item`, `insert_note`, `create_send` ...) all through `_do(verb, args)` to a `DAWBackend`, so Reaper, the offline backend and the multiplayer authority rules already apply. Undo is `Daw.undo/redo/undo_to(depth)`. |
| One verb layer for the room | `Session.ROOM_VERBS` (shape-checked: verb name to arg types) via `Session.ask_room(verb, args)`; the host decides and publishes the row. Guests are asked, and rolled back if refused. |
| One verb layer for the rack | `RackPatch.answer(op, args)`, reached through the `rack` room verb (`RackHost.ask_rack`). Catalogue, finder, help card are pure functions of data: `RackCatalogue`, `RackFinder`, `RackHelp`. |
| Mods | `ModRegistry` (what exists, groups, entries). |
| Running Claude Code from inside the game | `WorkshopRunner` / `Workshop` (`docs/workshop.md`): process group, stream-json tailed a little each frame, `--resume`, cancel, budget cap, locked-down command line, a context builder that scrubs secrets (`WorkshopContext`). |
| Mix snapshot for a prompt | `WorkshopContext` already writes tracks, FX, sends, sections. |

So the work is: (a) one registry that names and schemas these verbs as tools, (b) a transport, (c) a launcher and a
panel. No new authority path: **every write goes through the verb the UI uses**, so undo, multiplayer rules and
refusals are inherited, never re-implemented.

## 1. The control API

### Shape

`ControlApi` (`core/control/`): a registry of tools. A tool is

```
{ name, domain, op, summary, schema (JSON Schema), tier, handler: Callable(args) -> {ok, data | error} }
```

Naming is `<domain>_<op>`, ops limited to **list, get, add, set, remove**, plus a few domain actions
(`transport_play`, `rack_tidy`). Same five words everywhere is what lets the assistant guess the rest.

| Domain | Entities (list/get/add/set/remove) | Routed to |
|---|---|---|
| `project` | project (get, save, open, new, tempo, time-signature map, markers, regions, lyrics) | `Daw` |
| `transport` | play, stop, record, seek, loop, metronome, punch | `Daw` |
| `track` | tracks: name, colour, order/parent, arm, input, monitor, freeze | `Daw` |
| `mix` | volume, pan, width, mute, solo, groups, VCA, master, sends (create/remove/level), sidechain | `Daw` |
| `fx` | plugin chain: add, remove, move, enable, wet, params (by name, not index), presets | `Daw` |
| `item` / `note` | clips, takes, MIDI notes, gain, fades, split, glue, quantize, transpose, humanise, controls, automation lanes | `Daw` |
| `rack` | modules, cables, knobs, presets, patch (get/replace/clear/tidy), module catalogue search, help card, render a snippet | `RackHost.ask_rack`, `RackCatalogue`, `RackFinder`, `RackHelp` |
| `room` | venue, layout, pieces, furniture, items (put/home/wear/make), tablets, stations, weather, on-air | `Session.ask_room` verbs |
| `mods` | list, get, enable/disable (user mods only) | `ModRegistry` |
| `look` | read-only: screenshot, scope/spectrum snapshot, level meters, where the player is | existing shot path, `Ergonomics`, mix state |
| `help` | search the docs and module help | `RackHelp`, `docs/` |

Design rules that keep ~200 tools from being a swamp:

- **Names, not indices, in the interface.** Tracks, FX, modules and items are addressed by a stable id or unique
  name; the handler resolves to the index at call time (an off-by-one moves the wrong fader; see `docs/transport.md`
  "Indexing"). Ids come back from every `list`.
- **Real units.** dB, seconds, beats, semitones, 0..1 knobs documented by the schema; the handler converts (`Daw.db_to_taper`,
  the rack's 0..1 knob wire).
- **Batch.** `batch` takes an ordered list of calls and runs them as one change set (below). A patch of 40 modules
  and 80 cables must be one call, not 120.
- **Refusals are data.** Return the game's own refusal text (`send_refusal`, `paste_refusal`, `midi_take_refusal`,
  RackGaps) as the error, so the model can adapt.
- **Query tools return compact, bounded JSON** with `limit/offset` and a `fields` filter; the 532 Airwindows modules
  are reached with `rack_find`, never by listing.
- **Schemas are generated where possible**: from `ROOM_VERBS` types, from `modules.json` (rack knobs/jacks per
  module type), so they cannot drift. A test checks every registered tool's schema validates its own examples, and
  that every `ROOM_VERBS` entry is either exposed or listed as deliberately not.

### Tiers (what may be done without a person)

| Tier | Examples | Rule |
|---|---|---|
| 0 read | every list/get, look, help | always allowed |
| 1 edit | set a knob, add a module, move an item, add a track | allowed; recorded in a change set and undoable |
| 2 destructive | remove a track with items, clear the rack, replace/open a project, delete a mod's data | needs an in-game confirm (a card in the panel, `ALLOW` / `DENY`), or the client's `confirm` |
| 3 never | the file system, the network, session/hosting/ticket, settings, the Workshop, anything that would run code | not exposed |

### Change sets and undo

Every call (or `batch`) opens a change set: `{id, who, at, calls, daw_undo_depth_before, rack_patch_before}`. `changes_list`
and `changes_undo(id)` let the assistant (or the player) take back "what you just did": the DAW part with
`Daw.undo_to(depth)`, the rack by restoring the patch snapshot through the `rack` verb. To check before building:
whether rack edits have their own undo today, and whether `undo_to` is safe across several tool calls on a Reaper backend.

### Transport

Recommendation: **Streamable HTTP MCP served by the game itself**, tools only (plain JSON-RPC over POST, no SSE
needed for a request/response toolset).

- Bound to `127.0.0.1`, a random port, a fresh bearer token each launch, both written to `user://control.json`
  (mode 600). Off by default; on with `--control`, `DAWLINGS_CONTROL=1` or a setting; always off in a session as a
  guest and in exported builds unless the setting is on (the same gate pattern as `Workshop.enabled()`).
- Claude Code attaches with `claude mcp add --transport http dawlings http://127.0.0.1:<port>/mcp --header "Authorization: Bearer <token>"`;
  a printed one-liner and a generated `--mcp-config` file are provided.
- Handlers run on the main thread, a few per frame (a queue drained in `_process`), because `Daw`, the scene tree
  and `RackPatch` are not thread-safe. A request times out after a few seconds with a clear error.
- For clients that only speak stdio: a ~100-line shim `tools/mcp/dawlings_stdio.py` that reads `control.json` and
  forwards. Not needed for Claude Code, so it comes later.
- Headless: `godot --headless ... -- --control` (offline backend, no window) for scripted and CI use. This also
  makes the server testable in the suite: start it in-process, call it over a loopback socket.

Alternatives considered: a stdio server that spawns its own game (no, the user's running room is the point); a file
dropbox like the Reaper bridge (no, MCP wants request/response and Godot has sockets).
To verify: whether `TCPServer` is already used anywhere in the repo (the grep found none), and the Godot 4.7 HTTP
parsing we need is small enough to hand-write (it is: request line, headers, `Content-Length`, body).

### Multiplayer

The server runs **on the host (or solo) only**; a guest's game never exposes it. Guests still get the assistant: their
panel sends the prompt to the host over the session (a new `assistant` room verb, shape-checked like the others), the
host's machine runs Claude Code against the host's server, and the transcript streams back to the asker. So:

- **It runs on the host**: the host's `claude` install, sign-in and budget. A host without Claude Code simply offers
  no assistant to the room, and guests see that.
- **Its context is the host's**: the host's project, rack and room. A guest's own view (what they look at or hold) is
  added to the prompt as a line, nothing more.
- **Calls act as the asker.** The handler wraps each call in `Daw.on_behalf_of(peer, ...)` and the room verbs carry
  `from`, so the per-peer rules (locks, `close_edits_of`, refusals) apply to a guest's assistant exactly as to the
  guest's hands. A refusal comes back as the tool error.
- **Tier 2 confirms go to the asker**, and the host sees every guest's run and tool rows and can CANCEL any of them.
- One run at a time per room (queued, in order), so two people's turns cannot interleave their change sets.
- Prompts and transcripts are visible to everyone in the room; the panel says so before the first send.

## 2. The built-in assistant

### What it is

A chat panel in the game. You type (or later dictate) "put a slow tremolo on the pad and send it to the verb",
"why is the kick not in the mix", "build me a dub delay patch in the rack and show it". Claude Code runs as a
child process with the game's MCP server attached, calls tools, and streams its reasoning, tool calls and answer
back to the panel.

It reuses the Workshop's plumbing, generalised: `AssistantRunner` beside `WorkshopRunner`, sharing the process
group, stream-json tail, resume, cancel and budget code (extract the common part into `ClaudeRun`; the Workshop
keeps its own tool list).

### Command line (the line, not the prompt, says what it may do)

```
claude -p --output-format stream-json --verbose [--include-partial-messages]
  --strict-mcp-config --mcp-config <user://assistant_mcp.json>   # only the dawlings server
  --tools ""                                                      # no Read/Edit/Bash: it works the game, not the repo
  --allowedTools "mcp__dawlings__*"  --permission-mode dontAsk --permission-prompts none
  --max-budget-usd <setting>  [--resume <session>]
  --append-system-prompt <assistant prompt>
```

Different from the Workshop on purpose: the Workshop has the repo and no MCP; the assistant has the game and no
files. They are separate switches and never share a run.

Tier 2 calls are not decided by Claude Code's permission system (nobody to answer it) but by the game: the server
parks the call, the panel shows the confirm card, the tool result is "approved" or "refused by the player".

### Context

First message of a conversation carries (via `WorkshopContext`'s scrubbed builder, a subset): project summary,
tempo, transport, track list with levels, what the player is looking at/holding/selected, the rack's module list,
the venue. After that the model queries. System prompt: the five ops, units, ids not indices, "prefer batch", "undo
exists, say what you changed", "ask before anything destructive when the request was vague", and the in-game idiom
(the room, the bay, stations).

### The panel

- One panel, two ways in: a wall station (walk there, or I cycles to it) and the F10 overlay. Overlay screen in the style of `RackHelpScreen`/`RackFinderScreen` (`PanelLook`), opened with a key (proposal:
  F10; F9 is the Workshop) and from a station; in a headset a typing pad, dictation later.
- Transcript with streamed text; **each tool call is a row** (`track_set  Pad  volume -6 dB`) that can be expanded;
  a change set summary at the end with **UNDO** (whole turn) and per-row undo for batches.
- Confirm cards for tier 2; CANCEL (kills the process group); a context line (what it was sent) like the Workshop's.
- Rows that name a thing are clickable: the camera goes to the rack/track/station (reuse the walk-to station code).
- States: no `claude` on PATH, not signed in, budget exhausted, server off: each says what to do (the Workshop
  already has the first three).

### What it is not

- Not an editor of the game's code (that is the Workshop).
- Not a separate assistant per player: in a session there is one, on the host (see Multiplayer).
- Claude Code is not bundled or redistributed: it is the player's own install and sign-in. "Backed by Claude Code for
  now" means the runner is one implementation of a small `AssistantBackend` interface (start(prompt), poll(), cancel(),
  resume()); a direct API backend with the same tool registry can follow without touching the panel or server.

## 3. Plan, in slices (all done; the design order)

1. **Registry and read tools.** `ControlApi`, `ControlTool`, the schemas generator, `project/track/mix/fx/rack/room`
   list+get, `help`/`rack_find`. In-process dispatch only; tests call the registry directly.
2. **HTTP MCP endpoint.** `initialize`, `tools/list`, `tools/call`, token, port file, `--control`; a suite test over a loopback socket; `claude mcp add` one-liner in the docs. At this point Claude Code from a terminal can already drive the game.
3. **Write tools by domain** (each with a test against the offline backend): transport and mix, tracks, fx, items/notes, rack, room, mods. Batch, change sets, `changes_undo`.
4. **Tiers and confirms.** Tier-2 parking and the confirm card.
5. **Assistant.** the `assistant` room verb and relay for guests, `ClaudeRun` extracted from `WorkshopRunner` (Workshop tests keep passing), `AssistantRunner`, the panel, key, station, context, states.
6. **Polish.** Click-to-go, dictation, stdio shim, user-defined tools from mods (a mod's `provides` could declare tools).

Testing follows the repo's rule: targeted tests per slice, the full suite only once at the end.

## 4. Decisions (settled)

1. **Transport**: the game serves HTTP MCP itself (stdio shim later, if wanted).
2. **Scope**: every domain in the first release; slices 1 to 3 still go domain by domain, but all land before it ships.
3. **Availability**: any player; guests too. It runs on the host with the host's context (Multiplayer above).
4. **Destructive actions**: in-game confirm to the asker (default; keep unless said otherwise).
5. **Where**: both a wall station (`assistant`, in the station board and the F1 help page) and an overlay key (F10)
   that opens the same panel from anywhere.

## 5. Risks

- **Surface size.** ~200 tools overloads a model's tool list. Mitigations: consistent naming, generated schemas, a
  `tools_search`/domain-scoped listing so the client can load only the domains it needs, and `batch`.
- **Main-thread time.** A big batch must not stall a frame: run a few calls per frame and stream progress.
- **Drift.** Two sources of truth for verbs. Mitigated by generating from `ROOM_VERBS`/`modules.json` and by the
  test that every verb is exposed or listed as not.
- **Reaper backend differences.** Some `Daw` verbs are unsupported by a backend (`Daw.can(capability)`): tools report
  that as a refusal rather than failing silently.
- **Prompt injection.** Track names, lyrics, module help and imported file names are untrusted text that reaches the
  model. Tier gating and "tool results are data" in the system prompt; nothing at tier 3 exists to be tricked into.
