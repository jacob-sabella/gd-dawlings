# Multiplayer without port forwarding

There are three ways into someone's session. All three lead to the same session, with the same
host authority, the same door code and the same mix:

| Way | Who it is for | What it needs |
|---|---|---|
| **On this network** (the panel's list) | the same room, or the same LAN | nothing: the host's beacon on UDP 7333 |
| **Join by address** (+ *Open to internet*) | someone outside, when the host's router does UPnP or the host forwards UDP 7332 and 7334 by hand | the host's public address |
| **Join by code** (*Host online*) | anyone, anywhere, behind any router | a noray server, which dawlings runs at `dawlings.jacobsabella.com` |

This page is about the third. The first two are unchanged (docs/architecture.md, *Finding a
session*).

## Using it

**Host.** Press **M**, then **Host online** (or **Go online** if you are already hosting). The
panel shows a six-character join code, such as `N6U U9K`. Read it out a letter at a time, or press
**Copy** and paste it into a message. The code is also on the strip at the top right of the screen
while the panel is closed. `--online` at launch does the same.

**Guest.** Press **M**, type the code under **JOIN BY CODE**, and choose **Join by code**. Case,
spaces and dashes do not matter. In a headset, **Join by code** with the box empty opens the typing
pad over the note pad. `--join-code N6UU9K` at launch does the same. If the host also turned on
**Ask for a code**, type that four-character door code in **SESSION CODE** as well.

The panel then says how you are connected:

- **direct**: noray punched a path through both routers, and the session runs straight between
  the two machines;
- **relayed through dawlings.jacobsabella.com**: no punch got through within 6 seconds, so the
  noray server passes the traffic on. This adds the server's round trip, and the server's bandwidth
  limits apply.

The host's roster shows the same word on each guest's row. The sound line says how the mix
reaches you: *direct*, *relayed*, or (as a last resort) *carried by the session*.

`--relay` (or `DAWLINGS_NORAY_RELAY=1`) skips the punch and goes straight to the relay. This is for
testing a strict network without having one.

## Which noray server

In order, the first one set is used:

1. `--noray-server host[:port]` for this run;
2. `DAWLINGS_NORAY` in the environment (the tooling uses this; `127.0.0.1` for a local one);
3. the player's own, typed under **NORAY SERVER** in the session panel and kept in
   `user://online.cfg`;
4. the project setting `dawlings/session/noray_server`, so a build can ship another default;
5. `dawlings.jacobsabella.com` (`NorayLink.DEFAULT_SERVER`).

The port defaults to 8890. If the server cannot be reached, the panel says so, and says where to
set another one. It never falls silent.

## How it works

noray ([foxssake/noray](https://github.com/foxssake/noray), MIT) is a small server that does two
jobs. It introduces two machines to each other. Where an introduction is not enough, it relays.
dawlings talks to it with its own small client, `core/session/noray_link.gd` (`NorayLink`). The
reason is given below, under *Why not the netfox.noray addon*.

1. **Register.** Each side opens TCP to noray and sends `register-host`. noray answers with
   `set-oid <code>` and `set-pid <private id>`. The open id is the join code.
2. **Say where you are.** The private id is sent over UDP to noray's registrar (port 8809),
   *from the socket that will carry the game*. That is how noray learns the address that socket
   has on the internet: the router's address and port, not the LAN's.
   - The **guest** registers with a socket of its own, reads the `OK`, then binds ENet to the same
     local port.
   - The **host's** socket already belongs to its ENet server. So the private id goes out through
     `ENetConnection.socket_send`, and ENet drops noray's `OK` unread. To find out that the
     registration worked, the host then sends `connect` with its own code. noray only answers that
     with an address once it has one, and the address it gives is the host's public address.
3. **Punch.** The guest sends `connect <code>`. noray tells the guest the host's address, and
   tells the host the guest's address. The guest's ENet dials straight away. The host's ENet socket
   sends a few datagrams toward the guest, ten a second for three seconds. That way each router
   sees traffic from the other side as an answer to something its own side sent, and lets it in.
4. **Relay.** If ENet has not connected within 6 seconds (`Session.LINK_SECONDS`), or fails sooner,
   the guest sends `connect-relay <code>`. noray gives each side a port on the server. The guest
   dials `server:<host's relay port>` from the same registered local port. The host punches toward
   `server:<guest's relay port>`. The server passes each datagram on as-is.

noray relays one registered address to another, and nothing beside them. **The mix is not on the
session's socket** (MixFeed has its own UDP socket and threads, for latency). So the mix gets a
path of its own in the same way:

- when the host goes online, it also registers its mix socket, using the feed's own thread to send
  (`MixFeed.send_raw`);
- the host hands each admitted guest the mix's code along with the audio ticket;
- a guest by code registers its own mix socket, then punches to the host's mix socket. It uses
  the relay if the session itself needed the relay, or if no sound is heard over the punch within
  3 seconds.

If both of those fail, the same packets are **carried** as unreliable ENet packets on channel 9.
This works anywhere the session works, but it is late. The probe measured carried packets at
110 ms behind the host's speakers, with hundreds of packets lost on a busy frame. The feed's own
socket, punched or relayed, measured 22 ms on loopback. Nothing else a guest needs is outside ENet.
File sends and microphone takes are on ENet channels of their own, and the LAN beacon is for the
LAN only.

### Why not the netfox.noray addon

The addon (netfox 1.49.4, `addons/netfox.noray`) needs netfox's logger from `netfox.internals`,
and it installs two autoloads. It also awaits the scene tree inside every call. Its reply parser
splits each line on the first space and keeps one word. noray's errors come back quoted
(`connect "Error: Unknown host oid: X"`), so the addon reads an unknown code as a connect to the
address `Error`. The protocol itself is four commands. A client of about 400 lines (half of it comments) is simpler to keep
correct than three vendored addons with a patch. It is polled from the session's frame, it keeps
every refusal in words, and it can register a socket that someone else owns (ENet's, or the mix
thread's). Nothing from netfox is vendored.

## Security

- **A join code is not a secret.** It is six characters from a 25-letter alphabet, so about 244
  million codes. It is new every time a host goes online, and gone when the host goes offline or
  ends the session. It finds a session, and nothing more. Anyone who has it can knock.
- **The door is still the host's.** A guest by code arrives as a *pending* connection, exactly as
  one by address does. It is let in by its `_hello`, which carries the session's door code if the
  host asked for one (**Ask for a code**). Until it is admitted, it receives nothing, as before.
- **Tickets are still required for the mix.** The host's mix socket answers only keepalives that
  carry a ticket. Tickets are handed out over the admitted, reliable channel. A carried keepalive
  must also come from the peer its ticket was granted to.
- **noray sees addresses, not content.** The server learns each party's public address. A relayed
  session's packets pass through it, but they are ENet and the mix's own format. Nothing is
  encrypted, here or on the LAN, so the door code protects you from a neighbour on the wifi, not
  from someone who owns the route.
- **The private id** is held only in memory and sent only to the registrar. It is what stops
  someone else from registering an address under your code.

## Running a noray server

noray runs on **bun** 1.3 or later, not Node, because it uses Bun's own sockets. The exact noray
commit and bun version that dawlings deploys and tests are pinned in `deploy/noray/pin.env`:
commit `e5a9ff7`, `package.json` version 1.5.5, 2026-09-20; noray tags no releases. The settings
are in `deploy/noray/noray.env`.

**Ports** (open them all to the internet):

| Port | Protocol | What |
|---|---|---|
| 8890 | TCP | registration and `connect` |
| 8809 | UDP | the registrar (learns each player's public address) |
| 49152-49215 | UDP | relays: one port for each relayed address |
| 8891 | TCP | Prometheus metrics; keep it on loopback |

**On your own machine** (for development, and what the probe uses):

```
tools/noray_local.sh up        # fetches noray at its pin, and bun from npm if needed, into ~/.cache/dawlings
DAWLINGS_NORAY=127.0.0.1 godot --path . -- --online
tools/noray_local.sh down
```

**By hand**, anywhere with bun (`npm install -g bun@1.3.1` works if there is no bun):

```
git clone https://github.com/foxssake/noray && cd noray && git checkout e5a9ff7b7978e467a8a432f0300ce007602277c1
bun install --production
set -a; . /path/to/dawlings/deploy/noray/noray.env; set +a
bun bin/noray.ts
```

**With Docker** (rootful, and on the host network, or noray sees the bridge's address instead of
the players' addresses and no punch or relay works):

```
docker run --network host --env-file deploy/noray/noray.env ghcr.io/foxssake/noray:main
```

**A cheap VPS** is plenty. noray idles at about 70 MiB, and introducing players costs nothing. The
relay is the only real load. **Bandwidth:**

- the mix is about 1.5 Mbit/s (190 KiB/s) to each listening guest;
- the session's ENet traffic is tens of KiB/s;
- a *relayed* session of one host and three listening guests is therefore about 5 Mbit/s each
  way, through the server, for as long as it lasts: roughly 2.3 GB an hour.

noray's default relay limit, 128 KiB/s per relay, is below a single mix. That would cut the sound
to pieces, so dawlings' `noray.env` sets 1 MiB/s per relay and 8 MiB/s in all. It also raises the
lifetime cap from 4 hours to 12. Most sessions punch through and use no relay at all.

## dawlings.jacobsabella.com

The dawlings server is on the shared VPS 15.204.11.205 (Ubuntu, `ubuntu` account), next to the
sockbowl and aa stacks. Everything for it is in `deploy/noray/`:

| File | What |
|---|---|
| `pin.env` | the noray commit and bun version |
| `noray.env` | noray's settings: ports, relay range, limits, the code alphabet |
| `dawlings-noray.service` | the systemd **user** unit, with memory limits |
| `noray-watchdog.sh`, `dawlings-noray-watchdog.{service,timer}` | every two minutes, asks noray for a join code as a host would, and restarts it if it gives none twice (2026-10-30: its TCP side went quiet for hours while the service looked healthy) |
| `dawlings.caddy` | the Caddy site block: a landing page and `/health` |
| `deploy.sh` | the deploy, run by a person from this repo; `--dry-run` says everything first |

**Why not in Docker there.** The VPS's Docker is rootless, with rootlesskit's builtin port
driver. That driver rewrites every connection's source address to the bridge gateway
(`172.21.0.1`). noray's whole job is to learn each player's real public address and to relay to
it. So in a container there, every player would look like one machine, and no punch or relay
could work. There are two other ways to keep source addresses:

- switch rootlesskit to the slirp4netns or pasta port driver. That is a host-wide change to how
  every other container on the box receives traffic;
- run noray as a plain process.

So noray runs as a **systemd user service** of `ubuntu`, straight on the host. bun is shipped
beside it as one binary in `~/dawlings-noray/bin/bun`, so nothing is installed system-wide and
there is no container to name. Caddy cannot carry noray either, because it only carries HTTP.
Caddy serves only the landing page.

**Memory.** The service is throttled above 128 MiB and restarted above 192 MiB (`MemoryHigh` /
`MemoryMax`, no swap). The box has about half a GiB free.

### First deploy (the owner)

1. **DNS.** In Cloudflare, zone `jacobsabella.com`, create an **A record `dawlings` →
   `15.204.11.205`**, **DNS only (grey cloud)**, TTL Auto. It must not be proxied: the orange cloud
   carries HTTP only, and the game's TCP 8890 and UDP ports must reach the VPS directly.
2. **Lingering** for the user, so the service runs without an ssh session open. Run this once:
   `sudo loginctl enable-linger ubuntu`. Rootless Docker already needs lingering, so it is probably
   on already. deploy.sh checks and says.
3. **Firewall.** Open 8890/tcp, 8809/udp and 49152-49215/udp. Do it in the provider's network
   firewall if it has one, and in ufw if ufw is active:
   `sudo ufw allow 8890/tcp && sudo ufw allow 8809/udp && sudo ufw allow 49152:49215/udp`.
   deploy.sh does not use sudo, so it only reports what it can see.
4. **Look first:** `deploy/noray/deploy.sh --dry-run --caddy`. This prints every command, both
   local and remote, and changes nothing.
5. **Deploy:** `deploy/noray/deploy.sh --caddy`. It runs in this order:
   1. it bundles noray at its pin, with its packages and the bun binary, on this machine;
   2. it copies them to `~/dawlings-noray/` with rsync;
   3. it installs the unit, then enables and restarts it;
   4. it backs up the Caddyfile to `Caddyfile.bak.pre-dawlings-<ts>` (mode 600);
   5. it builds a candidate: the live file without any earlier `BEGIN/END dawlings-noray` region,
      with the block appended;
   6. it prints only the dawlings lines of the difference (the file holds other sites'
      credentials, so it is never printed or copied);
   7. it validates the candidate inside `aa-caddy`;
   8. it writes the candidate in place with `cat candidate > Caddyfile`. The Caddyfile is a
      single-file bind mount, so `sed -i` or `mv` would leave the container reading the old inode;
   9. it reloads Caddy, and checks that `magic.` and `armagetronad.` still answer.

   Caddy gets the certificate through its Cloudflare DNS-01 challenge, so step 5 can run before the
   A record exists.

To update later, run `deploy/noray/deploy.sh` again. It is idempotent. Add `--caddy` only if the
block changed.

### Verify

`deploy/noray/deploy.sh --verify`, or by hand:

```
dig +short dawlings.jacobsabella.com                          # 15.204.11.205
printf 'register-host\n' | nc -w 2 dawlings.jacobsabella.com 8890   # set-oid ..., set-pid ...
printf 'nobody' | nc -u -w 2 dawlings.jacobsabella.com 8809         # Unknown host pid: "nobody"
curl -s https://dawlings.jacobsabella.com/health                     # ok
curl -sI https://dawlings.jacobsabella.com/ | head -1                # HTTP/2 200
```

Then the real test: two machines on two different networks (a phone hotspot for one of them).
**Host online** on one, **Join by code** on the other, and the panel says *direct* or *relayed*.
`--relay` on the guest exercises the relay on purpose. On the VPS,
`journalctl --user -u dawlings-noray -f` shows each registration and connect.

### Rollback

- **The landing page:** `deploy/noray/deploy.sh --rollback-caddy <ts>`, with `<ts>` as printed by
  the deploy. This restores the byte-identical Caddyfile in place and reloads.
- **The service:** `deploy/noray/deploy.sh --stop` disables and stops it, and keeps its files.
  Removing it altogether, on the VPS:
  `rm -rf ~/dawlings-noray ~/.config/systemd/user/dawlings-noray.service && systemctl --user daemon-reload`.
- **DNS:** the owner deletes the `dawlings` record.
- **The game:** guests and hosts fall back to the other two ways. A noray server that cannot be
  reached is reported in the panel. Players can point **NORAY SERVER** at another one.

## Tested by

- `_test_noray_lines_and_codes_are_read_as_noray_writes_them`: the line format and quoted errors,
  addresses, code cleaning, the server setting's order, and the launch switches.
- `_test_noray_registers_finds_punches_and_relays`: against `tests/fake_noray.gd`, a GDScript
  stand-in that speaks noray's TCP, registrar and relay on the loopback. It covers both sides
  registering (the host through its ENet socket), the punch announced to both, a relay given to
  both, an unknown code, a server that is not there, none set, and a registrar that never answers.
- `_test_a_guest_by_code_says_direct_or_relayed`: `Session` itself as the guest. It covers a punch
  that says *direct*, a punch that goes nowhere and falls back to the relay by itself (*relayed*),
  a code nobody has, and `--relay`.
- `_test_the_mix_is_carried_for_a_guest_by_code`: the carried mix, its ticket bound to the peer,
  and noray's datagrams leaving from the feed's own socket.
- **The probe, through a real noray:** `PROBE_NORAY=1 tools/session_probe.sh` (punch) and
  `PROBE_NORAY=relay tools/session_probe.sh` (forced relay). They start `tools/noray_local.sh` if
  it is not up, and stop it again. The guest joins by the host's code instead of its address, and
  every other check of the session probe has to pass unchanged. The audio checks are included:
  under 30 ms behind, with no packet lost on loopback. There are also two more checks: that the
  guest came in *direct* (or *relayed*), and that the mix came on its own socket the same way.

## Not done

- **A real strict NAT has not been measured.** The relay is exercised on one machine, and the
  punch on loopback. A real symmetric NAT on a phone tether is the next test, and needs two
  networks.
- **IPv6.** noray's addresses are IPv4 here. A host that has only IPv6 has no way in by a code.
- **The relay is unencrypted and has no accounts.** Anyone may relay through a public noray, up to
  its limits.
- **Carried mix** is a last resort, and it is as late as the session's frame.
