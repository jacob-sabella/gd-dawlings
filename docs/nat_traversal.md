# Joining from outside the room, without port forwarding

Research only: no code in this document has been written. It sets out how someone across town
could join a session without the host touching their router, compares the realistic options for
a Godot 4 project shaped like this one, and recommends one.

## What has to get through

Before comparing options, what a session puts on the wire today (`core/session/`):

| Stream | Transport | Port (default) | Who opens it | Cares about |
|---|---|---|---|---|
| Everything replicated: roster, holds, intents, the room, presence, keys, controls, spectra, gestures, takes, files | `ENetMultiplayerPeer`, one server socket, channels 0 and 3 to 8 | UDP 7332 | the guest dials the host | ~ms latency for keys and gestures; reliable and unreliable-ordered both |
| The mix's audio (`MixFeed`) | its own `PacketPeerUDP`, own thread waking every 0.5 ms | UDP 7334 (`port + AUDIO_PORT_OFFSET`) | the guest speaks first, the host answers | jitter above all; 375 packets/s, ~1.5 Mbit/s per listener |
| Discovery beacon | `PacketPeerUDP` broadcast | UDP 7333 | the host | LAN only; never needs to leave the room |

Three facts about this shape decide most of what follows:

1. **It is a star, and the host is fixed.** The host is whoever holds the DAW (`Session.is_authority`,
   `core/reaper`), so it is in practice a desktop with Reaper or the built-in engine on it. Guests
   never talk to each other (`server_relay = false`); everything goes through the host. So only
   *host-to-guest* paths need to work, and there is no "migrate the host" problem to solve.
2. **A dedicated authoritative server is not an option.** The authority is the DAW on the host's
   machine. Anything on a server can only *carry* packets, never decide anything. Every "server"
   below is therefore a rendezvous or a relay, not a game server.
3. **The guest's own NAT is already handled.** Both ENet and `MixFeed` have the guest send first,
   so the replies come back through the guest's NAT. What is missing is a way *in* to the host.
   Today that is `InternetDoor`: UPnP on the host's router, opt-in, with "forward UDP 7332 and 7334
   yourself" as the fallback message. UPnP is off on many routers, absent on most carrier-grade
   NATs (CGNAT: mobile, many fibre ISPs, student halls), and never available to someone who does
   not own the router.

The Quest build (`export_presets.cfg`, "Quest", Android arm64) matters on the **guest** side only,
because a Quest does not host a DAW. Anything that has to run on a guest must run on Android; things
that run only on the host need only Linux and Windows.

## Background: what "hole punching" can and cannot do

Most home NATs keep the same public port for a socket whatever it sends to ("endpoint-independent
mapping"). If both sides learn each other's public `address:port` from a third party, and both send
to it at about the same time, each NAT sees outgoing traffic first and lets the reply in. This is
UDP hole punching. A STUN server is the third party's "what is my public address" half; a
rendezvous (signalling) server is the "tell the other side" half.

It fails when a NAT picks a new public port for each destination ("symmetric" NAT; common on
CGNAT and some corporate networks) and when a firewall blocks UDP outright. Then the only way
through is a **relay** both sides can reach outbound (TURN, in WebRTC terms). The figure commonly
quoted from WebRTC deployments is that something like 10–20 % of real connections need a relay;
treat that as an order of magnitude, not a measurement of this audience. Musicians on home
broadband should mostly punch through; a guest on a phone hotspot often will not.

IPv6 helps for free: where both ends have it, there is no NAT, only a stateful firewall, which the
same "both send first" trick opens. Godot's ENet already binds dual-stack.

## The options

Numbers below are for the shape above: a host plus up to four guests listening to the mix.
**Bandwidth through a relay**, if every guest is relayed: each listener's mix is ~1.5 Mbit/s of
payload, about 0.75 GB an hour with headers, and the relay both receives and sends it. Four
listeners for a three-hour session is ~9 GB out of the relay. ENet traffic is small beside it.

Prices and platform support were written from knowledge as of 2026, **without being re-checked
online** (web access was not available while writing). Check them before committing.

### 1. Own rendezvous + UDP hole punching on the existing sockets, with own relay fallback

Keep ENet and `MixFeed` exactly as they are; add a small service on a public host that (a) maps a
short join code to the host's public endpoints and (b) forwards packets for pairs that cannot
punch through.

- **Punching with ENet.** Godot 4's `ENetConnection.socket_send(address, port, packet)` exists for
  precisely this: send from the host's bound ENet socket to a guest's public endpoint to open the
  host's NAT. The guest side binds a known local port (`ENetMultiplayerPeer.create_client`'s
  `local_port` argument) so the public mapping the rendezvous saw is the one ENet then uses.
  `MixFeed`'s socket is punched the same way: it is already a plain `PacketPeerUDP`.
- **Relay fallback.** A UDP forwarder with TURN-like allocations: the guest sends to the relay, the
  relay forwards to the host from a per-guest port, the host's ENet sees each guest as a distinct
  relay address. The host keeps those allocations open with outbound packets, which it already
  sends.

| | |
|---|---|
| **Latency** | Direct when punched: the internet path and nothing else. Relayed: the detour via the relay's region, typically +5–30 ms in-continent. ENet's main-thread servicing and `MixFeed`'s 0.5 ms thread are untouched, so the 46 ms budget in `docs/architecture.md` grows only by the network. |
| **Cost** | One small VPS (a few €/$ a month). Many include terabytes of traffic, which covers the relay comfortably at ~9 GB a session. |
| **Hosting** | A public box running one small program (rendezvous + relay). Monitoring, updates and abuse limits (tickets, rate caps) are yours. |
| **Godot integration** | Small on the client: a `Rendezvous` helper beside `InternetDoor`, and `Session.host`/`join` taking endpoints from it. No new native dependency; ENet, `@rpc` channels and `MixFeed` unchanged. The relay itself is custom code outside Godot (or a headless Godot build). |
| **Android / OpenXR** | Works: only built-in Godot networking on the guest. |
| **Security** | ENet is unencrypted today. Godot 4's ENet supports DTLS (`ENetConnection.dtls_server_setup` / `dtls_client_setup`), with the host's certificate fingerprint handed out by the rendezvous. `MixFeed` would stay cleartext unless given its own encryption. |

### 2. WebRTC (ICE: STUN + TURN, data channels)

Replace `ENetMultiplayerPeer` with `WebRTCMultiplayerPeer`, one `WebRTCPeerConnection` per guest,
with a signalling server to exchange offers and ICE candidates. ICE gathers every candidate (LAN,
IPv6, STUN-reflexive, TURN) and picks the best pair that works. TURN can run over UDP, TCP or TLS
on 443, so it gets through firewalls nothing else here does.

| | |
|---|---|
| **Latency** | Direct when ICE finds a direct pair; via TURN otherwise, with the same detour as any relay. Data channels are SCTP over DTLS: a few percent of overhead, a little more CPU, no extra round trips once open. Unreliable unordered channels (`maxRetransmits = 0`) are suitable for audio, but `MixFeed`'s own-thread send would have to become a data channel serviced by `poll()`; keeping its 0.5 ms cadence needs care (a thread polling the connection) and would need re-measuring with `tools/audio_latency.sh`. |
| **Cost** | STUN is free. TURN: self-hosted coturn on the same kind of VPS as option 1, or a managed TURN service billed per GB (managed services have ranged from roughly $0.05/GB to $0.40/GB; unverified). Only relayed sessions cost anything. |
| **Hosting** | A signalling server (WebSocket, small) plus TURN (coturn, off the shelf) or a managed TURN account. |
| **Godot integration** | Largest of the options. Native builds need the `webrtc-native` GDExtension (WebRTC is built in only for the web export): a new binary per platform, including Android arm64 for the Quest (believed to be published; verify). `session.gd` assumes ENet in several places (`disconnect_peer` at the door, `get_peer(...).get_statistic(PEER_ROUND_TRIP_TIME)` for `round_trip_ms`, the hand-polled goodbye in `_exit_tree`, the `is ENetMultiplayerPeer` checks). Data channels have one fixed mode each, so the channel plan must be checked: **channel 6 carries both `CONTROLS_CHANNEL` (unreliable ordered) and `FileSend.FILE_CHANNEL` (reliable)**, which ENet allows and a data channel does not. |
| **Android / OpenXR** | Works if the GDExtension's Android build loads in the Quest export; untested here. |
| **Security** | Encrypted by default (DTLS). The signalling server must not hand a session to anyone who asks; it carries the join code. |

### 3. Platform relay networking (Steam, Epic Online Services)

**Steam Networking Sockets** with Steam Datagram Relay, via GodotSteam's multiplayer peer: Valve
punches through or relays on its own backbone, free, often with *better* latency than the public
internet. But it needs a Steam app ID (a Steamworks fee per app), the Steam client running on every
machine, and every participant to have a Steam account. **There is no Steam on a standalone Quest**,
so a Quest guest cannot join this way. Ruled out unless Dawlings ships on Steam and drops standalone
Quest guests.

**Epic Online Services P2P** (relay included, free) has community Godot 4 bindings with a
multiplayer peer and Android support (verify the current state of the plugin). Users can sign in
with an anonymous device ID, no Epic account. It needs an Epic developer organisation and product,
ties sessions to Epic's service and terms, and puts a large third-party SDK into every build.

The Meta platform SDK is not a contender: its peer-to-peer networking was deprecated, and it would
not cover desktop guests anyway.

| | Steam | EOS |
|---|---|---|
| **Latency** | Direct or Valve backbone; good | Direct or Epic relay; relay region not under your control |
| **Cost** | Free relay; Steamworks app fee | Free |
| **Hosting** | None | None |
| **Godot integration** | GodotSteam GDExtension + peer; `session.gd` ENet assumptions as for WebRTC; `MixFeed` must move onto the platform's channels | Community GDExtension + peer; same rework |
| **Android / OpenXR** | **No** (no Steam on Quest) | Yes, per the plugin; untested |

### 4. Tunnel and overlay services (playit.gg, Tailscale, ZeroTier, ngrok)

No code: something outside the app makes the host reachable.

- **Host-side public tunnel (playit.gg and similar).** An agent on the host gives it a public
  `address:port` on the provider's edge, which forwards to the host's local port. Guests need
  nothing installed, so it works for a Quest guest. Two UDP tunnels are needed (7332 and 7334), and
  every packet takes the provider's detour; latency depends on how near their edge is. Free tiers
  exist, with limits on tunnels and regions (unverified). Note that a guest's `MixFeed.listen`
  dials `joined_address` at the port the host *bound* (sent with the ticket, `_give_audio_ticket`),
  so the audio tunnel must come out on the **same public address and the same port number** as the
  host's local audio port, or the host must be able to announce the public one instead.
- **Mesh VPN (Tailscale, ZeroTier).** Every participant installs the client and joins one network;
  then the session works exactly as on a LAN (join by the overlay address). Direct WireGuard paths
  when punchable. Tailscale's fallback relays (DERP) carry traffic over TCP/HTTPS, which puts
  head-of-line blocking on the audio: usable for mixing, poor for playing along. On a Quest, a VPN
  client needs sideloading at best (unverified).
- **ngrok and Cloudflare Tunnel** are built for TCP/HTTP; neither carries the session's raw UDP in a
  usable way. Not suitable.

| | Host-side tunnel | Mesh VPN |
|---|---|---|
| **Latency** | Always via the provider's edge | Direct when punched; poor via TCP relay |
| **Cost** | Free tier; paid for more tunnels or regions | Free tiers for small groups |
| **Hosting** | None (third party) | None (third party) |
| **Godot integration** | None, or a field for a separate audio port | None |
| **Android / OpenXR** | Yes (nothing on the guest) | Awkward to unsupported |

These are worth writing up in the README *today*, as the stopgap for someone who wants to play
across town before anything below is built.

## Summary

| Option | Direct path when possible | Gets through CGNAT / symmetric NAT | New native dependency | Quest guest | Running cost | Change to `core/session` |
|---|---|---|---|---|---|---|
| 1. Own rendezvous + punch + relay | yes | yes (relay) | none | yes | one small VPS | small |
| 2. WebRTC + TURN | yes | yes (TURN, even TCP/443) | `webrtc-native` | likely | VPS or per-GB TURN | large |
| 3a. Steam | yes | yes | GodotSteam | **no** | Steamworks fee | large |
| 3b. EOS | yes | yes | EOS SDK + bindings | likely | free | large |
| 4a. Host tunnel | no | yes | none | yes | free tier / small | none |
| 4b. Mesh VPN | yes | yes (slow relay) | none (app installs) | poor | free tier | none |

## Recommendation: option 1, own rendezvous with hole punching and a relay fallback

Build a small **Dawlings rendezvous** on one VPS, and keep everything else.

Why this one:

- **It keeps the transport the latency work was measured on.** The 46 ms speaker-to-speaker figure,
  the jitter buffer's steering and the take-placement accuracy (0.4–1.4 ms against Reaper) all rest
  on `MixFeed` sending raw UDP from its own thread, and on ENet's channel plan. Option 1 changes how
  the first packet finds its way, and nothing after it. WebRTC and the platform SDKs all replace one
  or both, and every measurement would have to be redone.
- **No new native code on the Quest.** The guest uses only Godot's built-in ENet and UDP.
- **It fits the star.** Only host-to-guest paths are needed, the guest already speaks first, and
  the host already keeps its sockets busy, so punching and relay allocations stay open on traffic
  that is sent anyway.
- **The join code it adds is the one already there in spirit.** People already read a four-letter
  code across a room; a join code read over a phone call is the same act.
- **Cost is a flat few euros a month** rather than per gigabyte, and the relay only carries the
  sessions that cannot punch through.

What it costs you: running a public service, and writing a small relay rather than using coturn.
If running code on a server is the part you would rather not own, **WebRTC with a managed TURN
service is the runner-up**: more client work and a new GDExtension, but the relay becomes someone
else's job and traffic is encrypted by default.

### How it fits what is there

- `InternetDoor` stays as the first thing tried: a router that does UPnP gives a direct, relay-free
  path for nothing. The rendezvous is the second, and the relay the last.
- `Session.host()` registers with the rendezvous after `create_server` and gets a join code;
  `Session.join()` accepts a join code as well as an address. The admission code (`Session.code`,
  `_hello`, `_turned_away`) is unchanged and still decides who gets in: a join code says *where*
  the session is, the admission code says *whether you may enter*. They could be shown together.
- `server_relay = false`, the `_audience()` rule and the ticketed `MixFeed` socket keep their
  meaning; a relayed guest is just a guest whose address is the relay's.
- `joined_address`, which `MixFeed.listen` dials and which decides `hear_mix` by loopback, becomes
  "the endpoint the rendezvous gave". The audio endpoint must come from the rendezvous too: today the
  guest dials `joined_address` at the port the host bound (`_give_audio_ticket`), and neither a NAT
  mapping nor a relay allocation keeps the host's local port number.
- The LAN beacon on 7333 is untouched: in the room, nothing changes.
- `round_trip_ms` and `note_delay_ms` keep working (ENet still measures), and become the way to tell
  a relayed guest from a direct one in the panel.

### Rough implementation outline

1. **Rendezvous service** (outside the Godot project, or a headless Godot scene): a UDP endpoint
   that records the public `ip:port` each packet arrives from. A host registers its ENet socket and
   its `MixFeed` socket (two packets from the two sockets, so both mappings are seen) and gets a
   join code; a guest looks a code up and gets the host's endpoints, and the host is told the
   guest's. Codes expire with the session; lookups are rate-limited.
2. **Host side, `core/session/rendezvous.gd`** (a sibling of `InternetDoor`, opt-in from the same
   panel row, "Let people join with a code"): registers on hosting, keeps the registration alive,
   and on each "guest is coming" note calls `ENetConnection.socket_send` from the server's socket
   and `put_packet` from `MixFeed`'s socket at the guest's public endpoints a few times, to open the
   host's NAT.
3. **Guest side:** pick a local port, learn its public mapping from the rendezvous from that port,
   then `create_client(host_ip, host_port, ..., local_port)` while the host punches back. ENet's
   own connect retries cover the timing. If not connected within ~3 s, go to step 4.
4. **Relay fallback:** the guest asks the rendezvous for a relay allocation; the relay forwards
   ENet and audio traffic between the guest and a per-guest port facing the host; the host is told
   to send to that port first. Allocations carry the session's tickets and close when either side
   goes quiet (the same 3 s `LISTENER_TIMEOUT_MSEC` idea as `MixFeed`).
5. **Panel and notices:** show the join code beside the admission code, and for each guest whether
   they are direct or relayed and their round trip, so a 90 ms relayed guest knows why playing along
   feels late.
6. **Encryption (separate step):** turn on ENet DTLS with a per-session certificate whose fingerprint
   the rendezvous hands the guest; decide separately whether the mix stream needs encrypting. Until
   then the "door, not a lock" warning in `docs/architecture.md` applies over the internet too.
7. **Testing:** `tools/session_probe.sh` already runs a host and a guest; a variant that runs them
   in two network namespaces behind `iptables` masquerade (one endpoint-independent, one symmetric)
   would test punching and the relay fallback on one machine. Re-run `tools/audio_latency.sh`
   through the relay to put a number on its detour.

Cheapest order to ship: steps 1–3 and 5 first (most home connections punch through), then 4 for
CGNAT and hotspots, then 6.

## Not covered here

- Picking a VPS provider or region, and what to do when guests are on different continents (one
  relay region will not suit both; a relay per region is a later problem).
- Codec work for the mix feed. `docs/architecture.md` already notes that Opus would cut it to a
  tenth; over the internet that matters more than on a LAN, but it is independent of traversal.
- Hosting from a Quest. Not possible today (the host needs the DAW), and not assumed.
