# Realms: everyone's game is a place, and you can visit

Status: steps 1 to 5 built (2026-11-13), on branch `realms`; step 6 (handing a realm over) not started. The
listing service is written but **not deployed yet**: until it is, the lobby says it cannot reach it. Chosen
over a dedicated server (below).

## The idea

Every running game is a **realm**: its owner's room, rack, project and mix. You can **visit**
other people's realms from a **lobby**, hop between them, and go home, where your own realm is
just as you left it. Later, you can **carry things between realms**: a rack, a room layout, and at
the end a whole project with its sounds.

Nobody runs a server for the music. The owner's machine is the realm's authority and its sound
card, as a host is today. So the person whose realm it is plays with no delay, and visitors hear
the mix streamed, the same as guests do today.

## Why not a dedicated server

We weighed three shapes (the conversation of 2026-11-13):

| Shape | Good | Bad |
|---|---|---|
| A headless server that holds the room and mixes the sound | the room outlives everyone; nobody's PC is special | *everyone* hears the mix late, the owner included; it needs a real audio driver or the null sink (the dummy driver mixes in 85 ms lumps); someone pays for the box |
| A server that holds the state, plus one player's "primary audio claim" | the claimant plays with no delay; the server is cheap | two authorities: every edit goes guest → server → claimant; files have to live on the claimant's disk and move when the claim moves; recording timing moves to the claimant; handing the claim over means a dropout and rebuilding the engine |
| **Realms** (this page) | one authority per place, as today; no server state; the owner plays with no delay; most of it already exists | a realm closes when its owner quits (see *Handing a realm over*, the last step) |

The "audio claim" is built into realms: the owner of a realm has its sound, so there is no
claim to pass around.

## What is already there

The session is already shaped this way. Only the lobby and the hopping are missing.

- **A solo game is its own authority** (`Session.Role.SOLO`, `SessionLife.start_solo`), with its
  own DAW, rack and room.
- **Opening your realm is hosting** (`Session.host`, `Session.host_online`). Online, noray hands
  out a six-character join code (`docs/multiplayer.md`). The admission code (`Session.code`)
  decides who gets in.
- **Visiting is joining** (`Session.join`, `Session.join_by_code`). The visitor sees the owner's room
  (`Session.room`), sends asks (`Session.ask_room`, DAW intents), hears the mix (`MixFeed`), and
  records takes that the owner's machine places (`host_heard`).
- **Your realm waited while you were away, in part.** A guest's own venue and tablets wait in its
  layout (`Session.room`'s doc comment), and its made items are set aside and given back on leaving
  (`Studio._restore_made`). The DAW was not kept: joining swaps it for an `OfflineBackend` that only
  mirrors the owner's state (`SessionLife.join`), and leaving starts it again from the launch
  arguments (`Session.solo_backend` → `bootstrap._start_daw`), so unsaved work at home was lost.
  Step 2 closed this.
- **Files can move both ways.** `FileSend` carries sound files from a guest into the host's project.
  It also fetches a single file from host to guest by name (`fetch`), for a clip something in the
  room plays.
- **Things can be offered and accepted.** `ModSend` and the mod share flow already do "offered,
  accepted, declined, installed" for mods, and that is the shape copying needs.
- **A rack travels as one dict.** `RackPatch.to_dict` and `RackPatchFile` save it, and
  `RackUserPresets` keeps the player's own presets. A visitor's own preset already goes to the host
  as a `load` ask.

## What was built

Each step is useful on its own. The code is in `core/session/realm_*.gd` (three children of the Session autoload),
`scenes/realm_box.gd` (the session panel's REALMS part), `scenes/realm_leave_prompt.gd`, and `deploy/realms/`.

### 1. The lobby: realms you can see without a code

The session panel (M) has a **REALMS** part, under IN THE ROOM:

- **Your realm:** OPEN MY REALM (hosts online), its name, who sees it (*Friends see it*, the default; *Anyone
  sees it*; *Code only*), what visitors may copy (*Visitors ask to copy*, the default; *Visitors copy freely*; *No
  copying*), *Show my song on my card*, *Open my realm when the game starts*, and your **friend code** with Copy.
- **Friends:** add one by their friend code and a name; remove one.
- **Open now:** REFRESH asks the listing; each realm is a card (name, owner, how many are in, the song and tempo
  if shown, ★ for a friend's) with VISIT, and a box for the session code when its door asks for one.

`RealmLobby` (`Session.lobby`) keeps the settings, the realm id and a secret token in `user://realm.cfg`. While
this game hosts online by a noray code and the realm is not code-only, it posts its card to the listing every 30
seconds and on every change (roster, settings), and takes it down when it stops hosting or quits. A card says the
noray server its code is good on, so a visitor joins through the same one.

**The listing** is `deploy/realms/realms.mjs`: plain `node:http`, no packages, so it runs on the VPS's bun beside
noray and under node for its tests (`node --test deploy/realms/`). Cards live in memory only and are gone 90
seconds after their last refresh. A request's id is bound to the first token that names it, so knowing a friend
code lets nobody post that realm's card or see what its owner's friends see. Bodies over 8 KB are refused, each
address gets 60 asks a minute, at most 5000 cards are kept and 200 are listed.

It listens on **TCP 8892, plain HTTP**, straight to the internet, as noray's TCP 8890 does. It is not behind
Caddy because Caddy runs in rootless docker on the VPS and cannot reach the host's loopback. The token therefore
crosses the wire unencrypted. That is good enough for a friends list, and it is a reason never to make the token
worth more than that. `deploy/noray/deploy.sh` now ships it too (`dawlings-realms.service`, 96 MB at most) and
`--verify` checks it. **The owner opens 8892/tcp** in the provider's firewall and ufw, as for noray's ports.
`DAWLINGS_REALMS` or the project setting `dawlings/session/realms_server` points the game at another listing.

Changed from the plan:
- **A friend is one-sided:** adding someone's code lets *them* see *your* friends-only realm. There is no mutual
  accept flow and no exchange in a session; you swap codes however you like.
- **LAN:** the beacon's ON THIS NETWORK list is unchanged rather than merged into the lobby.
- **No "away" card:** a realm whose owner is visiting is simply not listed.

### 2. Home is kept while you visit

Leaving home now goes through `RealmLeavePrompt.leave_home` from every way out in the panel: VISIT, JOIN BY CODE
and JOIN by address. It asks only when there is something to lose:

- **Unsaved changes:** SAVE AND GO (saves where the song is, or, if it was never saved, in the projects folder
  beside and never over a song of that name; if the save fails, you stay), GO WITHOUT SAVING, or STAY (Escape).
- **Visitors in your realm:** they are sent home, and the prompt says how many.

In a headset there is no screen to ask on, so a song with unsaved changes is refused with a notice instead.

`RealmHome` (`Session.home`) remembers the song's file and how the realm was open (not, on this network, online).
When the game is on its own again and not on its way into another realm (role SOLO, no noray link under way),
it opens the song again and opens the realm as it was. That covers GO HOME, the owner ending the session, a lost
connection, a refusal at the door, and a failed join. It reopens the song only if the DAW was actually replaced: a
visit that never got in left the song open as it was. Hopping from realm to realm keeps home as it was first set
aside.

### 3. Hopping

VISIT on a lobby card: home set aside (2), then join by the card's code, through its noray server, with the door
code typed beside it. A guest can VISIT another realm straight from the one it is in. **GO HOME** (while visiting)
leaves and lets RealmHome bring home back.

Not built: a door standing in the room (it would be built the way the Rig Roulette door is).

### 4. Copying the small things: the rack and the room

While visiting, TAKE HOME FROM THIS REALM has **The rack** and **The room**. `RealmCopy` (`Session.realm_copy`)
asks the owner over the session (FileSend's ENet channel), and the owner's rule answers: *never* refuses,
*always* gives, and *ask* waits under VISITORS ASK in the owner's panel with Yes and No (and a notice).

- **The rack** is kept as one of the visitor's rack presets, "Ada's rack" (or "Ada's rack 2"...), through
  `RackUserPresets`.
- **The room** is kept as one of the visitor's made rooms, "Den (from Ada)", through `MadeRooms.keep_copy`: a
  new id, checked as a room file is. If the room is one of the game's own venues, nothing is copied and the
  visitor is told it is in their venue chooser already.

Not built: offering missing mods alongside a copy. A rack whose modules are missing here loads as the rack
already does with a module it lacks.

### 5. Copying a song, with its sounds

- **The song** (TAKE HOME): the owner's machine saves a copy of the project as it stands (`ProjectFiles.save` with
  `copy`, so the owner's own file and unsaved state are untouched). That is one `.dawproject` zip with every
  sound in it, sent in 32 KB slices, 4 a frame, and kept in the visitor's projects folder as "Demo (from Ada)",
  to open at home. It needs an engine that keeps its own files: a Reaper host refuses.
- **BRING ONE OF YOUR SONGS:** the visitor picks one of their saved projects and OFFERS it; the owner always
  says yes or no, even under *always*, because it lands on their disk. It arrives in the owner's projects folder
  as "Tune (from Grace)". Nothing opens by itself.
- A file is taken only when it was asked for or said yes to, only from the right peer, and not if it comes
  longer or shorter than announced. The limit is 256 MB (FileSend's). Leaving drops whatever is in flight.

### 6. Handing a realm over: not started

What a dedicated server would have given: the room carrying on when its owner goes.

- **HAND OVER TO … :** the owner picks a visitor. The project and its sounds go to them (step 5's
  transfer), their game opens the realm as its own host, and everyone else is moved there: the
  old owner sends each guest the new join code, and they hop (step 3).
- There is a short dropout while the new host opens the project and its engine starts. That is the
  honest cost, and the reason this step comes last.
- Automatic handover when an owner crashes is out of scope: nobody would have the files.

## What is not changing

- **One authority per realm:** the host, as in `docs/architecture.md`, *Authority*.
- **The mix:** `MixFeed`, its jitter buffer and take timing are untouched. A visitor is a guest.
- **Join codes and door codes** keep working without the lobby.
- **The LAN beacon** and joining by address stay.

## Risks

- **The listing is a public service.** Rate limits, a size cap on cards, cards in memory only and gone
  90 seconds after their owner stops refreshing them, and nothing kept for a code-only realm. There is no
  watchdog for it yet, as there is for noray.
- **A friend code and its token are not an account.** Losing `user://realm.cfg` loses your friends and
  your code, and the token crosses the internet unencrypted (plain HTTP on 8892). That is good enough for a
  friends list and not for anything that matters more.
- **Home being lost.** Step 2 is the guard, and `tools/realm_probe.sh` checks it with a real visit.
- **Copying is honour-system for what a visitor already has.** A visitor already holds the rack and room
  rows (the room is replicated), so *never* stops the game from copying them, not a modified client.
  Songs are different: the visitor never has the project file unless the owner sends it.

## Testing

- `tests/realm_tests.gd` (`_test_realm_*`, 55 checks): home set aside and come back to, including a
  visit that never got in and a hop; the prompt's SAVE, GO WITHOUT SAVING and STAY; the lobby's settings,
  friends and card against a stand-in listing; the real listing under node, where node is installed
  (a friend sees the card, a stranger does not); keeping a rack and a made room, and the owner's rules;
  a song arriving in slices, and refused when unasked, too long, too short or from the wrong peer.
- `node --test deploy/realms/`: the listing's own checks (cleaning a card, friends, token binding,
  expiry, rate limit, over HTTP).
- `tools/realm_probe.sh`: two headless processes over real ENet. Grace saves her song, changes it again,
  visits Ada, takes Ada's rack and song (and the song opens), brings her own song (Ada says yes, and it
  opens), goes home, and her song is open again as she saved it.
