# Items loop

The brief for iterating on the things people pick up in the studio. Read it at the start of every
pass, do ONE item from the queue at the bottom, and leave the queue truer than you found it.

Started with `/loop iterate on items: follow docs/items_loop.md`.

## Where this is going

A studio is full of things you pick up. Some of them are work: a mic you sing into, a tablet you
mix from on the far side of the room, headphones you plug into whatever you want to hear, a
shaker you play along on. Most of the rest are what you do with your hands while somebody else
does a take. Think of the idle side of PokerStars VR: chips riffled and stacked while you wait,
props pulled from a box, things thrown across the table at a friend, a lighter flicked for no
reason. That is half of why people stay in the room. This loop builds both halves on one item
system.

| Kind | What it is | What holding it does |
|---|---|---|
| Toy | a paper plane, a ball, a rubber duck, chips, a yo-yo... | fidget, throw, play catch; makes a little noise |
| Instrument | a shaker, a tambourine, a keytar, a uke... | you play it, others hear it, and it can be recorded as a take |
| Mic | a handheld mic, from the booth's stand or a shelf | your voice goes in: recorded on the armed track, and heard by you at once |
| Tablet | a handheld control and monitoring screen | a surface in your hand: a mixer page, meters, transport, a plugin |
| Headphones | a pair you put on, with a lead and a jack | wearing them patches your ears: plug the jack into what you want to hear |

### The contract, as the first passes should build it

- **One `Item` class, `core/items/`.** An item has a kind, a home (the spot it goes back to), and
  one of three states: AT_HOME, HELD (by a peer, in a hand) and LOOSE (lying where it fell, or
  flying). What an item *does* is a small set of overridable calls on the item: `use(down)`
  (the primary action), `held_pose()` (how it sits in the hand), `on_picked_up`, `on_put_down`,
  and `thrown(velocity)`. It does not branch on the medium.
- **Homes come from the venue.** `Venue.item_spots()` reports spots in studio space, dressed in
  the venue's style the way zones are: a prop shelf, a toy chest, the mic on the booth's stand,
  headphones on a hook by the desk. Every venue has them, none of them is on the footprint, and
  every one of them is reachable on foot (test this, as the zones are tested). Venue-specific
  toys are welcome: a snowball in the cabin, a beach ball on the grid, a slinky for the loft's
  stair.
- **The host's word, predicted.** Items are part of the room (`Session.room`), and they work
  the way trolleys and tablets already do. A pick-up is a claim (one hand per item, first hand
  wins, the loser's glove opens). A put-down or a throw is a numbered ask, predicted locally and
  rolled back if the host says no. While an item is held, its pose streams on the motion channel
  (`Session.send_motion`), and everyone else's copy follows it on a spring.
- **Throws are launched, not streamed.** A throw sends its launch once, reliably: where it left
  the hand, its velocity and spin, and the wall-clock moment it let go. Every peer flies the same
  deterministic flight from that: ballistic, a glide model for the plane, bounces off the
  walker's walls and the venue's solids. The host's landing is the truth. Do not stream a flying
  object's position.
- **Never lost, never in the way.** An item that lands outside the walkable floor, or lies loose
  and untouched for a few minutes, floats home. Items never stand on the console's controls or
  between the seat and the desk. A dropped item there slides off, or goes home.
- **Held in the glove.** Your own held item sits in your right glove in front of the camera on a
  desktop, and in your hand in a headset. Everyone else sees it in your ghost's glove, rimmed in
  your colour, the way held controls are. The glove's GRIP pose exists already; use it.
- **Desktop is first class.** Every item has to be picked up, used, thrown, put down and handed
  over with a mouse and keyboard, with nothing about it feeling like a fallback. Click to pick
  up; the left button uses; a throw is charged and aimed; a key drops it where you are looking.
  Many keys are already taken (`grep -rhoE "KEY_[A-Z0-9_]+" scenes core`, plus the KeyCatcher's
  piano rows); check before taking one, and put the keys in the help overlay. A headset uses the
  controller's grip and trigger, and a hand uses a pinch, all through the same `Interactor`
  calls as everything else (*Input: one grab contract* in `docs/architecture.md`).
- **Only the tablet is a surface.** Items are furniture, not instruments of the mix (*Furniture
  is not a surface*). The tablet's screen holds a real surface, and it does so through a new
  mount (in a hand), never by teaching a surface where it is.

## What "good" looks like

- **Tactile and springy.** Everything already moves on springs: the gloves, the trolleys. Items
  should too. A pick-up has a little squash, a put-down settles, a throw spins. A toy that looks
  like an icon being dragged is not done.
- **Every touch makes a sound.** Synthesised like the rest of the foley (*Audio: the gear, not
  the mix*), on the foley's own stream (*Every sound on a stream of its own*), and spatial, so
  you hear a duck squeak across the room from where it was squeezed. A toy's noise never goes
  into a take.
- **Performance is low latency.** Anything you play or sing is heard by you within a few
  milliseconds. It is played by the native helper where it can be (*Your own keys in four
  milliseconds*), and it is stamped and recorded the way `GuestMidi` and guest recording already
  do it. A shaker heard 40 ms late is a broken shaker.
- **Readable across the room.** Who is holding what, at a glance: in the glove, in their colour.
- **Fits every venue.** The prop shelf in the studio is walnut, on the grid it is neon, in the
  chalk zone it is sketched. Models come from Blender, run headless and scripted in
  `tools/blender/`, not from box primitives.
- **Cheap.** Run `tools/budget.sh` before and after anything that adds meshes or per-frame
  work. A toy at rest costs nothing per frame.

## Ideas to draw from

Toys: a paper plane you throw that glides and banks; a wind-up or radio-controlled plane you
steer round the room; a rubber duck that squeaks; a stress ball; a bouncy ball; a hacky sack;
a yo-yo; a fidget spinner; a slinky; a Newton's cradle on a side table; poker chips to stack,
riffle and flip; a deck of cards to shuffle and fan; darts and a board on a wall; a mini
basketball hoop over the door; a frisbee; a beach ball; a snowball; a confetti popper and a party
horn; a bubble wand; glow sticks; a fire extinguisher (PokerStars VR's classic); a coffee mug to
sip from; drumsticks to twirl; sunglasses or a hat to put on (they go with the wardrobe).

Instruments: a shaker, a tambourine, a cowbell, claves, a triangle, a kazoo, a keytar (into
`GuestMidi`), a ukulele strummed through the chord held on the keys, a theremin you play with
your hand's height.

Work: a handheld mic with a cable (and the booth's mic, which appears where you want to sing
in the zones' contract); a control tablet (mixer page, meters, transport, a plugin); headphones
(a cue mix, a track soloed in your ears only, another player's instrument, the talkback, the
click); a talkback button; a clipboard with the session notes; a tape measure for the gear's
ergonomics.

## One pass

1. Read this file, `docs/architecture.md` (*Input*, *Multiplayer*, *Audio*) and
   `docs/venues.md`. Pick the FIRST unchecked item in the queue. If it needs the user (a taste
   call between options, a change to how Reaper is routed, anything outward-facing), park it in
   `docs/loop_backlog.md` under "Waiting on the user" with what is needed, and take the next.
2. Build it. Match the surrounding code's comments and naming, and add no magic numbers without
   a line saying why. Models are scripted in Blender, headless, under `tools/blender/`.
3. Look at it and use it. Shoot it from the seat and up close (`tools/shot.sh`, `SHOT_CAM=`,
   `--walk`). If it moves, shoot frames or a strip of it moving. Where two people matter, run a
   host and a guest and shoot the guest's view of the host holding it. Judge the pictures
   honestly against "what good looks like" and iterate until they meet it.
4. Test it. Add a check for each new behaviour in `tests/run_tests.gd`: a pick-up claims it, a
   second hand is refused, a throw lands where the flight says, a lost item goes home, every
   venue's homes are reachable, and so on. Add a session-probe check where it crosses the wire.
   Then run `tools/verify.sh` (0 failed, no SCRIPT ERROR) and
   `flock ~/.cache/reaper-3d/shared.lock tools/session_probe.sh` (host and guest 0 failed; the
   audio-timing checks occasionally flake, so rerun before believing them).
5. Commit: a small plain-English message saying what was wrong or missing and what is there now.
   No attribution lines. Never push.
6. Send the user one or two pictures (`magick x.png -quality 82 x.jpg`, SendUserFile, a one-line
   caption).
7. Tick the item off below with a line on what was built, add anything the pass taught you to the
   queue, and keep the item system's section of `docs/architecture.md` true.

## Rules that do not bend

- Windows go offscreen (`tools/shot.sh` / `tools/offscreen.sh` do it). Never move the user's
  workspace. Never kill a godot this loop did not start (the user's own instances included).
- Audio: `PULSE_SINK=reaper3d_null PIPEWIRE_NODE=reaper3d_null` on every run, and nothing that
  plays through the speakers. The null sink stays at 0% except while a script measures it. Never
  touch the user's volumes or mutes without asking.
- Every change to the mix goes through `Session.send_intent` / `DAW._do`. An item that changes
  routing (headphones, the mic arming a track) asks; it never writes the DAW itself.
- Never write the real `user://layout_profile.cfg`, `user://ghost_look.cfg` or `user://body.cfg`
  (no `--height` in shots). Tests use a test save path.
- Never touch `~/.config/REAPER`; the rig is `~/.cache/reaper-3d/rig`. Wrap rig use, probes
  and shots in `flock ~/.cache/reaper-3d/shared.lock` (except `tools/light_check.sh` and
  `tools/keys_latency.sh`, which take it themselves). Outputs go under `~/.cache/reaper-3d/`.
- `hardware/` must not reference `Session`, `Presentation.`, `Medium.`, `XRServer`,
  `is_authority` or `multiplayer.` in code lines.
- The gear and its footprint do not move for an item, and the walker is never trapped by one.
- Never raise `tools/light_check.sh`'s limits. A glowing toy is lit within them.

## Queue

- [x] The contract, end to end on one toy, alone. `Item`, `Venue.item_spots()` and a prop shelf
      dressed in every venue. Pick up, hold in the glove, squeeze (`use`), and put down, on a
      desktop and through the same `Interactor` calls a controller uses. The toy is a rubber duck
      that squeaks. Test: homes clear of the footprint and reachable on foot, the state
      changes, and the duck goes home when put down off the floor.
      Done: `Item` (HOME/HELD/LOOSE on springs, stops ticking at rest, tidies home after 3 min),
      `ItemRoom` judging put-downs with the walker's `fits`, `DuckItem` (Blender model from
      `tools/blender/duck.py`, synthesised squeak and rubber tap), a lit prop shelf in every
      venue (sketched in chalk), a palm-up left glove under the carried item on desktop, the
      mirror ghost carrying a look-alike, Q to put down. Learned: a held item in a capture needs
      `tools/shot.sh OUT 200 210` (physics lags render frames); the shelf lamps need to stay dim
      (0.9) or the yellow blows out to a halo; test with `is_instance_valid`, not `!= null`, for a
      carried item that may be freed.
- [x] The duck in company: a pick-up claimed with the host, refused to a second hand, seen in the
      holder's ghost's glove in their colour, its held pose streamed, and its put-down a
      predicted, numbered room ask. Two-instance probe checks.
      Done: carrying is a hold, claimed and let go of by `Presence.claim_carries` reading the
      hands each tick (so no way of emptying a hand leaves a claim behind); the real item rides
      the holder's ghost's left palm (`Item.follow`, `Avatar.carried_pose`), rimmed in their
      colour (`item_rim.gdshader`), where their `Session.send_carry` says relative to their
      head; squeezes go out on `Session.send_item_use`; put-downs are `put_item`/`home_item`
      room asks, predicted, and only the holder's is heard; the room carries `"items"`. Probe:
      host 44, guest 43. Learned: a put-down must reach the host before the hold is let go of
      (ask, then release, on one reliable channel), or everyone sees it float home and then
      jump to the floor. `start_solo` drops the peer, so a test that wants asks sent sets an
      `OfflineMultiplayerPeer`. `tools/session_shot.sh` with `HOST_ARGS="--carry duck"` once
      left the guest hanging before its picture; it did not happen again in two runs. Watch for it.
- [x] Throwing: a charged, aimed throw on a desktop and a flick in a headset; a deterministic
      flight from one reliable launch; bounces off the walker's walls and solids; settles; floats
      home when lost or left. The rubber duck and a bouncy ball.
      Done: hold R and let go (charged, along the aim, lofted) or flick the grip in a headset;
      `Flight.fly` works the whole flight out up front at 120 Hz (walls at the walkable floor's
      edges, solids' sides and tops, bounces dying into a roll), so the room knows where it will
      rest the moment it leaves the hand. One `throw_item` ask carries the launch; the room's
      entry carries it too while it flies (8 elements, with a throw count) so any copy flies the
      same throw once. `BallItem` (Blender, `tools/blender/ball.py`) with its own bounce foley.
      Probe: host 45, guest 43. Learned: the flight's starting turn must come from the launch
      (facing the velocity), not the hand, which differs per machine. Not colliding with the
      gear is fine: coming down on a desk is "somewhere it can't stay", and it goes home after
      landing. A multi-exposure strip (`--throw W@TICK`, one shot a tick, `magick
      -evaluate-sequence max`) is the way to judge a throw from stills.
- [x] The paper plane: a glide model (lift, drag, a bank into a turn, a stall), thrown from the
      hand, so a good throw crosses the room and a bad one noses into the floor.
      Done: `Flight.fly` takes a `wing` and glides until the first touch (lift ∝ speed², capped;
      stall below 3 m/s; flutter drag above 5; lift ramps in over 0.4 s out of the hand; a lean
      turns it). `PlaneItem` (Blender, `tools/blender/plane.py`, single faces drawn both sides)
      with a paper swish on launch (`Item.on_launch`) and a paper tick on touching. Learned: a
      point-mass wing with lift on at once pulls out of any dive, so a throw at the floor never
      reached it until the lift was made to settle in. `fits` (room for a body) was the wrong
      test for where a thing may lie: thrown items landing near walls kept going home. Items now
      use `Walker.reachable`, and a put-down's aim stops at the gear, which `fits` had been
      catching by accident. `--spectate` in `tools/screenshot.gd` watches a flight from the side.
- [x] Catching and handing over: an item thrown at someone is caught if their hand is free and
      near, and an item held out to someone is taken from you by their grab.
      Done: a free hand catches anything in the air past `CATCH_AFTER` that comes within its
      `catch_reach` (0.45 m round a screen person's head, 0.16 m of a headset palm), as an
      ordinary claimed pick-up. Anything in another's hand can be grabbed: `Session.take_hold`
      moves the hold on the host for `takeable` keys (items only), and the old holder's hand
      lets go with "Grace took the rubber duck." Probe: host 46, guest 44 (the plane goes host →
      guest → nobody). Learned: the hand-over needed almost nothing new on the losing side.
      `_apply_items` already made a hand let go when the table said someone else had its item;
      a take is just the host saying so on purpose. The catch is decided by the catcher's
      machine and settled by the host's first-come rule, like any other pick-up.
- [x] The handheld mic: picking it up asks to arm your input on a track (through
      `Session.send_intent`), you hear yourself at once on the low-latency path, and your take
      is recorded and placed by song position the way guest recording is. Put down, it disarms.
      If the native path cannot yet carry a voice, find out what it takes, and park the
      routing choice if it needs the user.
      Done: `MicItem` (Blender, `tools/blender/mic.py`) lives in the clip of the booth's mic
      stand (`Venue.mic_spot`, the shelf in chalk, which has no stand), and its band glows red
      in anyone's hand. Live in a hand here, it drives `MicArm`. On the host it arms the
      vocal track (or the first track) with monitoring on, through `send_intent`, so the host
      hears themself through the DAW. On a guest it points `GuestAudio` at the track and opts
      in to recording with the host. It arms nothing there, because an armed host track records
      the host's input over the guest's take. Put down, thrown or taken, the track goes back to
      how it was. Parked: a guest hearing themself, because `native/keys.c` carries keys, not a
      voice (docs/loop_backlog.md, "Waiting on the user"). Learned: joining Blender objects
      keeps the active object's transform, so a model centred by its vertex mean before
      `transform_apply` came out with its origin off to the side and floated beside the glove.
      Also, the stand's clip was an upright cup that no handheld mic sits in; it is now a ring
      along the boom, and the mic's home is worked out from the same numbers.
- [x] Headphones: put on, they show on your ghost (its hat comes off) and in your mirror, and
      while they are on you hear your personal mix (the tablet's, below) with the room muffled.
      No cord and no socket: worn is enough. Until the tablet patches anything, the personal mix
      is the mix and your keys. Taken off with H on a desktop, or by reaching to your head in a
      headset. Home is a hook under the prop shelf.
      Done: `HeadphonesItem` (Blender model from `tools/blender/headphones.py`, cups that swivel
      flat on a floor and square on the hook), `Item.wearable`/`set_worn`, the hand's `worn`
      slot with `wear`/`take_off`, Presence claiming both slots, `wear_item` in the room,
      `Avatar.worn_pose`, and `Ears` muffling the room by 14 dB. Learned: a first cut had a cord
      to PHONES sockets on the master. The user's design replaced it with the tablet as a
      personal mixer, so the sockets became the tablet's wireless send plugs (next). Also,
      `--walk mirror[,distance]` in `tools/screenshot.gd` stands you in front of the venue's
      mirror; a hand-picked walk point was black inside a wall twice. The patchbay's
      `PatchPlug`/`PatchCable` (`hardware/patchbay/`) are there to build the senders from.
- [x] The tablet is your personal mixer (the user's design, 2026-10-09). A handheld tablet whose
      face is a patch panel only you see: a row of receivers, each with a level and a meter, and
      what they add up to is what your headphones play. Its senders are wireless patch plugs that
      everyone sees: pull one off the tablet's edge and plug it into a send socket out in the
      room, and its receiver on your tablet lights with that source. Begin with the send sockets
      for the master mix (on the master section) and your own keys (on whatever you play). The
      plugs are room state, so everyone sees who is listening to what; the levels are yours. A
      later page of the same tablet carries a control surface (a mixer page, meters, transport,
      a plugin's page), working the same way on a desktop and in a headset.
      Done: `TabletItem` (Blender model and the wireless plug from `tools/blender/tablet.py`),
      `TabletFace` drawn on its glass only while a hand here holds it, `PersonalMix` (four
      receivers, a level each, summed per bus for `Ears.listen`), and `SendSocket`s for MIX and
      KEYS on the master section, where everyone's plugs stack in their owners' colours. The
      plugs are the room's `patches` (verb `patch`); clicking a send pulls your own plug back.
      Home is the shelf's lower tier, because the top's spots are full in venues with no stand.
      Learned: a face that looked skewed held at an angle was right square-on, so look square-on
      before blaming the layout. On a desktop the tablet is held facing the eye
      (`TabletItem.facing_eye`) with its left edge in the hand, where the glove covers no row.
      The glass is matte under an unshaded backlight quad, so the room's lamps neither glare on
      it nor grey it. Lying flat, it is near edge-on from the seat, so its grip box is taller
      than the slate. Still to come: the control-surface page.
- [x] Single tracks into the personal mix: a send socket on each channel strip. Heard where the
      track's audio is in this process: the built-in engine's per-track buses. A guest gets the
      host's whole mix in one stream, and a host on Reaper hears Reaper, so per-track cue there
      needs routing (Reaper cue sends to an output this game taps, or per-listener stems
      streamed to a guest): park the choice in the backlog with the options.
      Done: `ChannelStrip.send`, a `SendSocket` named `track_N` (`PersonalMix.track_socket`),
      beside mute and monitor. `GodotBackend.set_cues` plays a cue of each patched track while
      headphones are on: a third player of the same part, kept in time by `_sync_players`, on a
      bus of its own (`cue_bus`) that holds the track bus's own effect objects, so it is
      post-effects and pre-fader and follows mute. `Ears.listen` takes cue buses alongside the
      mix and keys, and turns them off with the headphones. Where tracks are not played here
      (`PersonalMix.hears_tracks` false: a guest, Reaper, the silent stand-in), the plug still
      goes in for all to see, and the row says "not here" and the notice says why. The options
      are parked in docs/loop_backlog.md. Learned: `tools/budget.sh 90` caught the sockets'
      bank drawn into every lamp's shadow maps, at +450k primitives for a nut 12mm across, so
      it casts no shadow now (+22k). A strip's socket seen at an angle hid behind the monitor
      button's click box, so its own box stands out in front of the panel, where a plug does.
      A row of bright nickel nuts read as white rings, louder than the lamps, so they are dark
      satin now.
- [ ] Other players' gear into the personal mix: a send socket on someone else's instrument or mic.
      Needs their notes (played here on the same instrument) or their audio sent across the
      session. Say what latency it adds.
- [ ] "Their monitor": patch into what another player hears, captured on their machine (their mix
      with their own playing, in time as they hear it) and sent on. It cannot keep everyone in
      time at once, but it can stage a performance: the performer's machine is the reference,
      and the audience hears the performer in time with the backing track they played to.
      Design it with the user first: who may be listened to, what it costs the performer's
      upload, and how it is shown.
- [ ] Instruments, the first two: a shaker and a tambourine, played by shaking (mouse motion
      while held on a desktop, controller velocity in a headset). They are heard at once on the
      low-latency path and recorded as MIDI hits on the armed track by song position.
- [ ] A keytar into `GuestMidi`: played from its keys (the computer keyboard's piano rows, or a
      MIDI device) while you walk round holding it.
- [ ] Chips and cards: a stack of chips that riffles, splits and flips in your hand (the
      PokerStars fidget), and a deck to shuffle and fan. Both pure idle.
- [ ] Toys round the room: darts and a board, a mini hoop over a door, a Newton's cradle by the
      desk, a yo-yo. Each venue gets one toy of its own (a snowball, a beach ball, a slinky...).
- [ ] Pockets: carry more than one thing. A few slots on your ghost (a belt, a back pocket),
      number keys and a wheel on a desktop, a reach over the shoulder in a headset.
- [ ] A props box: ask for any item from a menu and it appears in your hand (as PokerStars VR's
      props do), next to walking to the shelf. Park it with the user first if it would make the
      shelves pointless.
- [ ] The wind-up/radio plane: a little plane you fly round the room from a controller held in
      the other hand. Others see it fly, and it lands or crashes.
- [ ] Pass over everything with two instances: a host and a guest, each playing with every
      item for a while. Shoot it, measure the budget, and even out what drifted.
