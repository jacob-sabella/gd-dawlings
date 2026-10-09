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
- [ ] The duck in company: a pick-up claimed with the host, refused to a second hand, seen in the
      holder's ghost's glove in their colour, its held pose streamed, and its put-down a
      predicted, numbered room ask. Two-instance probe checks.
- [ ] Throwing: a charged, aimed throw on a desktop and a flick in a headset; a deterministic
      flight from one reliable launch; bounces off the walker's walls and solids; settles; floats
      home when lost or left. The rubber duck and a bouncy ball.
- [ ] The paper plane: a glide model (lift, drag, a bank into a turn, a stall), thrown from the
      hand, so a good throw crosses the room and a bad one noses into the floor.
- [ ] Catching and handing over: an item thrown at someone is caught if their hand is free and
      near, and an item held out to someone is taken from you by their grab.
- [ ] The handheld mic: picking it up asks to arm your input on a track (through
      `Session.send_intent`), you hear yourself at once on the low-latency path, and your take
      is recorded and placed by song position the way guest recording is. Put down, it disarms.
      If the native path cannot yet carry a voice, find out what it takes, and park the
      routing choice if it needs the user.
- [ ] Headphones: put on, they show on your ghost. Their jack plugs into a point (a channel
      strip, the patchbay, another player's instrument, the click, the talkback), and your ears
      get that source. Begin with the sources this process already has. A per-track cue from
      the host needs routing in Reaper: park that choice in the backlog with the options.
- [ ] The control tablet: a handheld screen carrying a surface through a mount in the hand. It
      shows a mixer page, meters and transport, and switches to a plugin's page. Pulled off its
      shelf, it works the same way on a desktop and in a headset.
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
