# The Reaper link

Two channels to one DAW. Not redundancy — they carry different things, and neither one can do
the other's job.

| | OSC | ReaScript bridge |
|---|---|---|
| Carries | values that **move** | structure that does **not** |
| Latency | sub-millisecond on loopback | ~30ms (one deferred tick) |
| Transport | UDP, bidirectional | JSON files in a dropbox directory |
| Reaper side | built in, no script | `reaper/dawlings_bridge.lua` |
| Without it | nothing works | console, transport and racks still work |

## OSC: everything that moves

Faders, pan, mute, solo, rec-arm, meters, transport, FX parameters, send and receive levels.
Reaper streams these at roughly 30Hz per channel without being asked.

It is **not** a request/response protocol. You bind a port, Reaper floods it, and you send back
when a control moves. There is no handshake and no error — which means **a wrong port number is
indistinguishable from a stopped Reaper.** Both are silence. That is why `OSCPeer` counts
packets and the HUD shows the count: it is the only way to tell the two apart from inside.

### Setup

Copy `reaper/Dawlings.ReaperOSC` to Reaper's `OSC/` folder, then
*Options → Preferences → Control/OSC/web → Add → OSC*:

```
Mode:                Configure device IP + port
Device port:         9000      dawlings listens here; Reaper sends here
Device IP:           127.0.0.1, or the host machine on the LAN
Local listen port:   8000      Reaper listens here; dawlings sends here
Pattern config:      Dawlings
```

The pattern file is Reaper's own `Default.ReaperOSC` with the `DEVICE_` counts raised and
nothing else touched, so everything documented for the default surface is true here too.

### Why the bank size matters

Reaper streams a **bank** of tracks, not all of them, and the stock bank is 8. A console built
against that silently stops at channel 8 on a 30-track project — no error, no gap, just a desk
missing most of the session. The shipped file asks for 64, and `ReaperLink` re-sends
`/device/track/count` on connect so it holds even against a stale pattern file.

### Gotchas that cost real time

- **Padding.** Every OSC chunk is a multiple of four bytes, and a string that already lands on a
  boundary still takes a whole extra word, because its null terminator must be inside the pad.
  Reaper does not reject a mispadded packet — it ignores it. Covered by `tests/run_tests.gd`.
- **Bundles.** Reaper coalesces a bank of meter updates into one packet. A decoder that returns
  only the first message makes channel 1 move while the other 63 sit still.
- **`bypass` means enabled.** `b/track/@/fx/@/bypass` sends 1 when the plugin is *running*.
- **Booleans are floats.** Reaper reads `b/` and `t/` patterns as 0.0/1.0. Sending OSC's typed
  `True` is legal OSC that Reaper ignores — a uniquely annoying bug to chase.
- **`n/tempo` is normalised**, not BPM. Only `/tempo/raw` is a number of beats per minute.
- **Echoes.** Reaper echoes every change back. Without a guard, a fader being dragged receives
  its own previous value a frame later and visibly fights the hand holding it.

## ReaScript: everything structural

OSC has no message for *how many tracks exist*, *what plugin is in slot 2*, *what colour a track
is*, *where the items on a track are*, or **create a send from track 6 to track 12**. Those
exist only in ReaScript.

This is why the patchbay is split down the middle: it **displays** routing from OSC (which
streams send levels and destination names) and **changes** routing through the bridge. With the
bridge not loaded, a patch gesture is refused out loud rather than dropped. A patchbay that
silently fails to patch is worse than one that admits it cannot — with the former you spend
twenty minutes assuming you missed the jack.

### Two reads, two clocks

`GetProjectStructure` and `GetTimeline` are deliberately separate calls rather than one, because
they change on completely different schedules. Structure — track count, plugin chains, routing —
changes when someone reaches for it. The arrangement changes on every drag of every item. Polling
one at the rate the other needs means either a stale patchbay or a thousand plugin parameters
re-read twice a second. The timeline is polled every 2s; structure is read on demand.

Reaper has no notification for "an item moved" on any channel this project can reach, so a poll
is the only honest option and the interval is a straight trade between latency on someone else's
edit and load on a project with a few thousand items.

`GetTimeline` **omits tracks with nothing on them**, and dawlings clears every lane before
applying the answer. That is not an optimisation: the Lua encoder cannot tell an empty list from
an empty object, so an explicit empty `items` arrives as `{}` and would have to be guessed at. A
track that just lost its last item is therefore reported by its *absence* — and a merge rather
than a replace would leave deleted blocks on screen with nothing to clear them.

### Why files

ReaScript's Lua has no socket API. A file dropbox polled on a deferred timer is the pattern
`~/.config/REAPER/Scripts/mcp_bridge.lua` on this machine already uses daily, so this follows a
proven one rather than inventing something. dawlings writes `request_<id>.json`; the script
reads it, deletes it, and writes `response_<id>.json` beside it.

The request is deleted **before** the handler runs. A handler that errors would otherwise leave
it on disk to be retried every tick, forever, thirty times a second.

### Indexing

Reaper indexes tracks from 0. OSC addresses them from 1. Everything crossing that boundary goes
through one pair of helpers in the Lua, because an off-by-one here moves the *wrong fader* —
which looks like a working bridge right up until the moment it matters.

One place the bridge is strictly better than OSC: a send's destination. OSC can only identify it
by **name**, which is ambiguous the moment a project has two tracks called "Verb" — and
duplicate track names are completely normal. `GetProjectStructure` returns indices.

### The bank is not a scroll position

Reaper streams a **bank** of 64 tracks, not a project. In a 90-track session the OSC indices
mean tracks 1–64 or 65–90 depending on where the bank is, and **nothing in the message says
which**. Left alone, a 90-track project is indistinguishable from a 64-track one.

So `MixState` carries `bank_offset`, and moving it **clears the track cache**. That is not
over-caution: after a bank change every index means a different track, so what is cached is
wrong rather than stale, and keeping it leaves the previous bank's names on this bank's faders
until each one happens to be re-sent.

`/device/track/bank/select` takes a bank *number*, so an offset that is not a multiple of the
bank width cannot be asked for and is rounded down rather than silently ignored. Reaper
acknowledges by re-sending the tracks and never by naming the bank, so the authority states
`/bank` locally rather than waiting for a confirmation that never comes.

How big the project actually is comes from `GetTimeline`'s `track_count` — the only channel
that knows. Without it the bank buttons have nothing to be enabled or greyed by, which is why
`can(TRACK_BANKING)` is false until the ReaScript bridge is loaded.

**`/bank` is the first entry in a snapshot**, before a single track message. A bank statement
redefines what every index after it means and applying one clears the cache, so a snapshot that
stated the bank at the end would deliver a whole project and then throw it away — leaving a
guest with an empty desk and nothing in the log. The suite asserts the ordering.

### What the arrangement costs on the wire

Items replicate to guests as **one address per lane holding a flat list** —
`/track/3/items [start, length, muted, name, …]` — not one address per field. Forty items would
otherwise be a hundred and sixty messages that must all arrive before the lane is drawable, and a
lane half-populated from a torn update draws blocks that were never there.

`/timeline/...` is **durable**, and the prefix is a trap worth naming: the volatile test used to
be `begins_with("/time")`, which swept the whole arrangement into the unreliable channel. Items
are edge-triggered — dropped once, they are never resent — so a guest would have shown a project
with nothing in it and nothing would have errored.

## The offline stand-in

With no DAW, `ReaperLink` runs a synthetic 12-track mix with meters moving and the clock running.
It lives in the shipping class rather than in `tests/` because it is a development stand-in, not
a mock: the studio has to be buildable, lightable and photographable without Reaper in the loop.
A still studio photographs as a dead one — meters dark, reels stopped, every LED off — which is
an accurate picture of nothing happening and a useless one for judging whether gear reads as gear.
