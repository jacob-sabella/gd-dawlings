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
   `flock ~/.cache/dawlings/shared.lock tools/session_probe.sh` (host and guest 0 failed; the
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
- Audio: `PULSE_SINK=dawlings_null PIPEWIRE_NODE=dawlings_null` on every run, and nothing that
  plays through the speakers. The null sink stays at 0% except while a script measures it. Never
  touch the user's volumes or mutes without asking.
- Every change to the mix goes through `Session.send_intent` / `DAW._do`. An item that changes
  routing (headphones, the mic arming a track) asks; it never writes the DAW itself.
- Never write the real `user://layout_profile.cfg`, `user://ghost_look.cfg` or `user://body.cfg`
  (no `--height` in shots). Tests use a test save path.
- Never touch `~/.config/REAPER`; the rig is `~/.cache/dawlings/rig`. Wrap rig use, probes
  and shots in `flock ~/.cache/dawlings/shared.lock` (except `tools/light_check.sh` and
  `tools/keys_latency.sh`, which take it themselves). Outputs go under `~/.cache/dawlings/`.
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
- [x] Other players' gear into the personal mix: a send socket on someone else's instrument or mic.
      Needs their notes (played here on the same instrument) or their audio sent across the
      session. Say what latency it adds.
      Done: every other player's ghost wears a KEYS pack on its hip (`Avatar.wear_keys_pack`):
      a little transmitter with an aerial, a lamp in their colour, and a `SendSocket` named
      `keys_N` by peer id (`PersonalMix.player_socket`), labelled "NAME'S KEYS". Their notes
      travel, not their audio: `GuestMidi` hands each note on, off and pedal to
      `Session.send_note`, which relays it on its own reliable channel (`KEYS_CHANNEL`), and
      `TheirKeys` plays it here on a `MonitorSynth` of that player's own, on a bus of its own
      ("Their keys N"), only while headphones are on and the pack is patched. So it is heard
      the same on a host, a guest, Reaper or the built-in engine. Latency: no jitter buffer, a
      note is played when it arrives, so it lands one network trip after it was played (host to
      guest, or guest to host), two through the host for guest to guest, plus the synth's own
      ~16 ms and the output buffer. The notice says "about N ms", from ENet's round trip
      (`Session.note_delay_ms`). A player who leaves takes their pack, and the host puts any
      plugs in it back in their trays. Their mic (live audio) is parked in docs/loop_backlog.md.
      Learned: a ghost is not scaled until it has a pose, so the pack's socket test checks scale
      relative to the ghost, not absolutely. `tools/screenshot.gd --visitor x,z,yaw` stands a
      second player in a shot. A player's synth and bus are kept once made rather than freed
      when unpatched, since a bus removed under a playing synth is a script error a frame later.
- [x] "Their monitor": patch into what another player hears, captured on their machine (their mix
      with their own playing, in time as they hear it) and sent on. It cannot keep everyone in
      time at once, but it can stage a performance: the performer's machine is the reference,
      and the audience hears the performer in time with the backing track they played to.
      Design it with the user first: who may be listened to, what it costs the performer's
      upload, and how it is shown.
      Asked: rebuild it here rather than stream it, performer opts in (ON AIR), a second socket.
      Done: an ON AIR key in the tablet's header (`TabletFace.OnAirSwitch`) puts this person in
      the room's `on_air` list (the `on_air` verb, predicted on a guest). Their ghost's pack
      grows a block under KEYS with a lit ON AIR sign and a MONITOR socket (`monitor_N`,
      `Avatar.set_on_air`). Off air, the block goes and the host returns its plugs to their
      trays, and the host refuses a plug into the monitor of someone not on air. No audio is
      sent: each note now carries the song position its player heard as they played it
      (`GuestMidi.song`, the fifth argument of `Session.note_played`). `TheirMonitor` copies the
      mix this machine plays (an AudioEffectCapture at the head of the Mix bus, ahead of the
      headphones' gain) into a delay line per performer, an AudioStreamGenerator on "Their
      monitor N". Each note waits until the delayed backing reaches the position it was played
      to. The line starts at 80 ms plus the note's one-way trip. A note that comes too late is
      played at once and the line grows by the miss plus 30 ms, by a gap in the backing. It
      never shrinks while plugged in, and it is capped at 1.5 s. So you hear them in time, not
      live. A host on Reaper has no mix in the game to copy, so it hears their notes alone.
      Learned: with a tone through the line, an 80 ms line came out 84 ms behind the mix while
      its queue read a sawtooth of 69 and 80 ms. The capture lags by one of Godot's 512-frame
      mix steps, which is now added to the estimate. A headless run is not real time: a check
      that counts frames finishes before the sound has played, so cap max_fps and use the clock.
      A host's own keys go to its DAW and are not relayed, so ON AIR is for players whose keys
      come through GuestMidi (a guest's).
- [x] Instruments, the first two: a shaker and a tambourine, played by shaking (mouse motion
      while held on a desktop, controller velocity in a headset). They are heard at once on the
      low-latency path and recorded as MIDI hits on the armed track by song position.
      Done: both are modelled in `tools/blender/percussion.py` and live on the prop shelf's lower
      tier beside the tablet. `InstrumentItem` turns the hand's movement into hits: it keeps the
      fastest point of a stroke and plays when the stroke stops or turns back, 0.35 m/s to
      2.4 m/s mapped to velocity 40 to 127, at most one hit per 60 ms. A click is a firm strike.
      The hand's movement comes from `Interactor.shake_point`. In a headset that is the
      controller. On a desktop the mouse wiggles the hand while it carries an instrument: the
      hand follows the cursor a little way (at most 7 cm) and springs back. A hit is heard at
      once on the player's own keys' bus, Foley takes generated in code. It goes to everyone as
      `Session.item_hit` and is heard from the holder's hand in the room. It is recorded by
      `HitRecorder` while the song records: the first armed track gets a General MIDI drum note
      on channel 10 per hit, at the song position heard plus the output latency, in one
      `insert_midi_take` when recording stops. With nothing armed, the player is told once.
      Learned: held face on, a tambourine is a disc that hides half the desk. Held nearly flat
      and turned a little across, the head reads at a slant and the jingles show. A pale skin
      right under the shelf lamp burned out to white. A tan skin and bright nickel jingles read
      as a tambourine. Smooth shading on the head's thin disc drew a seam across it. A Vector3
      holds 32-bit floats, so a value clamped to a constant can read a hair over it in a check.
      Not yet tried in a headset.
- [x] A keytar into `GuestMidi`: played from its keys (the computer keyboard's piano rows, or a
      MIDI device) while you walk round holding it.
      Done: a 25-key keytar (`tools/blender/keytar.py`, each key a node on its hinge) stands on
      its edge on a rack of two posts and pegs at the back of the prop shelf, inside the shelf's
      footprint, in every venue. In your hands, `GuestMidi.keytar` makes your keys play, send and
      record whatever role you are, and a take with no track chosen goes onto the armed one
      (named "… keytar N"). On a desktop, picking it up makes the computer keyboard its piano: the
      studio's own `KeyCatcher`, with a notice saying how. The arrow keys walk while it has the
      letters (the `walks_on_arrows` group, read by `Walker`), so it is played on the move. Esc
      gives the keyboard back; a click with the keytar in hand takes it again. Each note pushes
      its key down and lights it amber. Another player's keytar plays their notes out of itself,
      on a `MonitorSynth` whose `speaker` makes it a 3D player in the room. Learned: held up face
      on, the keytar hid the desk, and one held where the glove was left the glove a hand's
      width off it: hold it by the body's edge and tip the keys to the eye. A real key's 4 mm
      travel cannot be seen from where it is held, so pressed keys go down further and light.
      Above the shelf's lamp a dark red is black. Two blocks with one name: Godot renames the
      second "@MeshInstance3D@…", so name them by index or a test's report is unreadable.
      `tools/shot.sh` played into the default sink, so a shot of a keytar sounds; shots now go
      to the null sink. A host's MIDI keyboard is still Reaper's, not the keytar's (in the
      backlog), and it is not yet tried in a headset.
- [x] Chips and cards: a stack of chips that riffles, splits and flips in your hand (the
      PokerStars fidget), and a deck to shuffle and fan. Both pure idle.
      Done: a `FidgetItem` base runs a trick on each click: the next one in turn, plus a quick
      click finishes the one playing. The trick count is the whole of its state, so relayed clicks
      keep everybody's copy the same. The chips are 12 clay chips (`tools/blender/table_games.py`),
      six red and six blue. Their tricks:
      - riffle: split side by side, spread, pushed together one from each pile;
      - flip: the top chip thumbed up 12 cm, two and a half turns;
      - cut: the top four under the rest.
      The cards are a deck of two blocks plus eight loose cards that do the moving. Their tricks:
      - shuffle: halves apart, tipped, cards falling in turn, squared;
      - fan: seven turned face up and spread from the near end, a hand dealt from the trick count;
      - square up.
      New Foley for both: clack, riffle, card riffle and sweep. Both live at the front corners of
      the shelf's top.
      Learned:
      - Anything in front of a toy as seen from the seat steals that toy's clicks: the seat test
        caught chips in front of the ball and cards in front of the duck. Small things also need a
        grip at least 7 px from the seat, so they went to the ends.
      - Noto Sans has no suit signs, so the faces are a drawn atlas.
      - Pale paper glares under the work light right by the head: the faces and backs are toned
        down.
      - A stack held where the glove is is hidden by it: hold it on the fingers above.
      - Comparing a float32 position with `==` fails; use `is_equal_approx`.
      Not tried in a headset, where tricks would want a gesture rather than a trigger.
- [x] Toys round the room, first: darts and a board.
      Done: a regulation board, on a cork panel with its own lamp, over the prop shelf, and three
      darts living in it, points in, flights in three colours. A click throws one at the cursor
      (R wound up throws it harder and flatter, with less wobble). It flies point first and sticks
      where it goes in: board or cork. What it scored shows over it for a moment ("T20  60"), and
      its readout says "in the board: T20". Learnings:
      - The walkable floor stops short of the shelf, so a flight's wall check hit an invisible
        wall in front of the board. Flights now skip the wall check over solid footprints.
      - An aimed lob landed low twice: once for want of half a step's gravity in the launch, once
        for the dart's drag. A dart has no drag now.
      - The shot window's cursor is wherever it was left, so `--throw` now aims at the middle of
        the view. Shots are 1600x900: crop from that, not from 1080p guesses.
      - A copy that is told a dart is stuck must not keep an old score from an earlier throw.
      Not tried in a headset, where a throw is a real arm's throw and wants no aim assist.
- [x] Toys round the room, second: a mini hoop.
      Done: a mini hoop on a weighted stand, against the right-hand wall at the front of the live
      room, across the room from the shelf the ball lives on. It has a 23 cm rim, a lined
      backboard and a cord net, a lamp on an arm over the board, and the venue's own steel or
      chrome. In the chalk zone it is drawn. A thrown ball comes off the rim (a clang) and off the
      board (a smack). Dropping down through the ring is a basket: the net swishes, stretches and
      swings, and "SWISH" (touched nothing) or "IN" rises over the board. Only round things meet
      it; a duck flies through as if it were not there. It adds 42 draws and about 9.7k triangles
      to the wide view, and nothing per frame at rest. Learnings:
      - A net has to be a wall, not just drag: with drag alone, a ball going in at a slant ran
        out through the side of the net and on under the board.
      - A ball's air drag puts a drag-free lob about 3 cm short over 2 m, which is the difference
        between a swish and the front of the rim. Aim a touch long.
      - `--lob x,y,z,speed@tick` in the shot tool throws exactly at a point, for a shot of
        something getting there.
      Not tried in a headset, where a basket is a real throw and should be very satisfying.
- [x] Toys round the room, third: a Newton's cradle.
      Done: a chrome-framed cradle on a black plinth, five steel balls on V threads, standing at
      the back of the prop shelf's top in the middle. It is a `FidgetItem`: picked up, each click
      lifts one, then two, then three end balls and lets go. The row clacks back and forth on its
      own for a few seconds, each clack a little quieter, and a click mid-swing stops it dead and
      starts the next. The swing is the textbook one (one group out at a time, a damped pendulum,
      `CradleItem.swing`), so the trick count is all of its state, as for the chips. Learnings:
      - `Item.snap_home` never called `on_put_down`, so a fidget sent home by the room (a host's
        word, a reset) went on playing its trick on the shelf. It does now, as `go_home` does.
      - Its first spot, the back-left corner, was hidden behind the ball and out of the shelf
        lamp's light. The back middle, behind the low duck and the flat plane, shows it.
      Not tried in a headset, where pulling a ball out by hand is the obvious thing to want.
- [x] Toys round the room, fourth: a yo-yo.
      Done: a red yo-yo with silver hub caps, lying on its side at the front of the prop shelf.
      It is a `FidgetItem` with three tricks in turn: throw it down (it sleeps, whirring, at the
      end of its string, and is tugged back with a clack), around the world, and loop the loop.
      The string is a thin cylinder stretched from the finger to the axle each frame. The tricks
      are laid out against world down and your forward, so it hangs true however the hand is
      tilted. It is round, so it bounces, rolls and goes through the hoop. Learnings:
      - On a desktop the glove is at the bottom corner of the view, and a real 70 cm string's
        tricks happen below and behind the picture: the first shots showed nothing but a line.
        Your own desktop hand throws a 15 cm string (`DESK_STRING`); everybody else, and a
        headset, sees the full length.
      - Lifting the finger above the glove to make room looked like the yo-yo hanging from
        nothing. The string has to come out of the fingertips.
      Not tried in a headset, or as a guest watching a host's ghost throw the full string.
- [x] Toys round the room, the rest: each venue gets one toy of its own (a snowball, a beach ball,
      a slinky...). The desk itself could have a toy (the cradle's twin by the console), if one
      fits without coming between the seat and the controls.
      Done: one toy per venue, lying on the floor in front of the hoop: a knit hacky sack in the
      studio, a neon ball on the grid, a ball of paper in the chalk zone, a tennis ball in the
      loft, a snowball in the cabin, a beach ball on the roof, a foam planet on the station, a
      rubber starfish in the dome and the eight ball in the club; later a geode in the crystal
      cave, a lemon in the glasshouse, a green glow stick on the festival stage, a silk temari
      ball in the temple garden and a tumbleweed in the desert. They are one item, `ToyItem`,
      whose look, size, flight and sound come from the venue. The snowball lands dead and puffs
      snow; the neon and tennis balls bounce; the beach ball is all air and comes down short;
      the paper drifts; the starfish squeaks and is not round, so the hoop ignores it, and nor is
      the glow stick, which lies a stick's radius off the floor (`TOYS[...]["rest"]`); the
      tumbleweed is the size of a beach ball and lighter, and all drag. Changing
      venue changes the toy, even in your hand. New Foley: a soft thud, a snow crunch and a
      beach ball's bop. It adds 8 draws and about 1.5k triangles to the wide view. Learnings:
      - The hand is close to the eye on a desktop: a held pose a few centimetres up moves the
        toy a long way in the picture. Small things sit in the palm, as the ball does.
      - A shot of something picked up from across the room must wait for it to arrive:
        `--shot-frame 200`.
      - Left of the hoop is inside the studio's curtain wall; the test now checks every
        venue's spot is floor you can reach, a toy's width all round.
      Not done: a slinky, and a desk toy by the console. The toys only differ in how they fly.
- [x] Pockets: carry more than one thing. A few slots on your ghost (a belt, a back pocket),
      number keys and a wheel on a desktop, a reach over the shoulder in a headset.
      Done: three pockets, the left hip, the right hip and across the back. On a desktop, 1, 2
      and 3 swap the hand with that pocket (in, out, or one for the other). The wheel goes round
      them while you carry anything; ctrl and the wheel still zooms. Picking something up with a
      full hand pockets what was in it, if a pocket is free, instead of sending it home. In a
      headset, the trigger with a hand at a hip, or reached back over the shoulder, does the
      same. What is pocketed is still yours, claimed with the host like what is in the hand, and
      everyone else sees it on your ghost's hips and back. You see it only in a mirror, as you
      do a hat. A toy pocketed mid-trick stops, and a keytar on your back gives the keys back.
      Learnings:
      - Pockets are a person's, not a hand's: a headset's two hands share them, and one hand
        can take out what the other put in. The claims are read off every hand together, so a
        thing moving between hands is never let go of on the way.
      - A swap has to empty the pocket before filling it, or it wipes what it just put there.
      - A wheel that always starts from the first pocket only ever swaps with that one: it has
        to remember where it got to.
      - The ghost's resting hands cover its sides: hip pockets sit a little forward of them.
      Not tried in a headset.
- [ ] A props box: ask for any item from a menu and it appears in your hand (as PokerStars VR's
      props do), next to walking to the shelf. Park it with the user first if it would make the
      shelves pointless.
- [x] The wind-up/radio plane: a little plane you fly round the room from a controller held in
      the other hand. Others see it fly, and it lands or crashes.
      Done: a radio plane, a little foam high-wing trainer and its transmitter, waiting on the
      floor past the hoop with its nose toward the room (`RcPlaneItem`, `tools/blender/rcplane.py`).
      Pick it up and the radio is in your hand, while the plane stays where it lay. Click and the
      motor runs up, the plane runs along the floor and lifts off at about 2 m/s, then flies where
      you point: your aim, a little past the plane. Look at it and it flies on away from you;
      look beside it and it banks round that way. It climbs no steeper than one in two, never
      above 2.3 m. Another click cuts the motor and it glides down at half a metre a second.
      Onto its wheels gently, level, it lands and rolls to a stop. Into a wall, the gear,
      furniture or the floor too steeply, it crashes: a crunch, a short tumble, and it lies
      nosed in with a wing down until a click sets it back on its wheels. Pocket the radio in
      flight and the motor cuts, so it glides on unsteered. Put the radio down and the plane is
      back beside it. The radio's light is green while the plane is up, and the motor buzzes
      faster the faster it goes. Everyone else sees it fly where the flyer's machine says, 20
      times a second (`Session.send_flier`), with the motor and the crash sounds.
      Learnings:
      - Steering at a point on your aim as far away as the plane is breaks the moment you look
        at the plane: the point is the plane, and it thrashes. A point past it along the aim
        steers like pointing.
      - The live room is not open floor. It has a riser and things standing in it, so a glide
        has to be lined up down the back of the room, and a low pass into a riser's side is a
        crash.
      - Twelve materials cost 60 draws once their shadows were counted. Down to eight, and no
        shadow on the radio or the spinning prop, it is 20.
      Not tried in a headset, where the aim is the controller's.
- [x] Pass over everything with two instances: a host and a guest, each playing with every
      item for a while. Shoot it, measure the budget, and even out what drifted.
      Done: two real windows (`tools/session_shot.sh`), the host Ada carrying each of the
      seventeen items in turn while the guest Grace watched, and then Ada with three things in
      her pockets, and Ada flying the radio plane round the room. Every item arrives in Ada's
      ghost's glove on Grace's screen, the headphones on its head and the pockets on its hips
      and back, with no script errors on either side. Grace's radio plane flies the same path as
      Ada's, and lies where Ada's crashed, to the millimetre. One thing had drifted: the
      colour round a held item (`item_rim.gdshader`) turned a keytar held edge-on into a white
      blaze, because a long flat face seen edge-on is all edge. It is narrower and dimmer now,
      for every item. Budget, wide at 48 tracks: 4097 draws, 478k triangles, unchanged by the
      pass. A screenshot option, `--rc-debug`, prints where the plane is on either machine, and
      `--carry rcplane:fly@N` takes off late enough for a guest to see.
      Learnings:
      - A guest that joins after something has happened sees only how it ended. A two-window
        shot of anything that moves has to start it after the guest is in.
      - The two windows draw at different rates, so a frame number means a different moment on
        each. Line the guest's shot up from its own log.
      - One run in eighteen the guest never joined. Run it again before calling it a fault.
      Not tried with two headsets.
- [x] Work items are personal, not shared (the user's design, 2026-10-11). A mic, headphones, a
      tablet and a keytar are each one player's own gear, not a thing passed round: everyone
      reaching for the shelf's mic gets a mic of their own, at once, not a turn waiting for the
      first hand to let go.
      Done: the shelf still holds one of each (`ItemRoom.PERSONAL_KINDS`: mic, headphones,
      tablet, keytar) but it is a dispenser now, never itself held. `Item._on_grab_begin` on one
      of the four hands the grab to `ItemRoom.take_personal(kind, peer)` instead, which spawns
      (or finds) `"<kind><peer id>"` — `tablet1`, `keytar7` — bound to that peer with the existing
      spill-instrument machinery (`bound_to`/`may_hold`), told to the host with a new ask
      (`take_personal`), modelled on `_spill_instrument`. A personal copy has no shelf rest of its
      own: putting one down (`ItemRoom.retire`) despawns it rather than sending it home, and a
      guest's `apply()` now spawns a peer's copy on sight, not only ids it already knew about.
      Pocketing still works, since that was already per-player. A toy is untouched: still one
      shared instance, still refused to a second hand without being destroyed.
      Learned: `ItemRoom.apply()` only ever walked the ids it already had locally, which is fine
      for an already-known item's state but never discovers a brand-new one — Tour's spilled
      instruments get around this with their own side channel (`Session.tour`); a personal copy's
      peer is recoverable from its id alone, so `apply()` grew one discovery loop instead of a
      second channel. `queue_free()` is deferred, so a test right after `despawn()` has to check
      `get_parent() == null`, not `is_instance_valid()`.
