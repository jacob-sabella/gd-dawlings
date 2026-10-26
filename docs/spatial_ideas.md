# Spatial ideas

Ways to use the 3D space that are fun without costing usability. Rule for all of them: each is
another view of the same DAW state, every gesture has a precise fallback (the faders, the 2D
view), and nothing moves the room around the reader.

## Kept (the user, 2026-10-25, over three rounds)

1. **The stereo field as a stage.** Each track is a glowing object in front of you: left/right
   is pan, distance is depth (level, reverb send), size is width. Grab and place. Snaps to the
   centre line; double-press resets. Every move is a pan/volume edit the faders show.
2. **Automation by gesture.** Grab a parameter and move your hand while the song plays; the
   motion records as automation. Punch in/out inside the loop only, one undo step per pass, the
   curve lands in the 2D automation lane for cleanup.
3. **Signal you can see.** Pulses run along the patch cables and looms, scaled to level, so
   "why is there no sound" is answered by following the light until it stops. Brightness and
   motion, not colour alone.
4. **Clips as objects.** Pull a clip out of the arrangement and it is a cassette in your glove:
   shelve it (a visible clipboard), hand it over, drop it on a track. A new item kind.
5. **The room reacts to the mix, peripherally.** Venue lights breathe with the master; the room
   flashes on a clip. Subtle, with an Ergonomics motion setting.
6. **The session in miniature.** A small model of the whole session to hold (tracks as strips,
   the playhead moving); point at a spot and its gear comes to you via FocusRig.
7. **Point, mark and listen together.** A pointing ray others see; sticky notes pinned to a
   song time, in the room and on the 2D ruler; "listen from my spot".
8. **EQ as a wall of frequencies.** Lows at the floor, highs up high; each track's spectrum is a
   see-through shape, and where two fight for the same band (kick vs bass) the overlap glows.
   Grab the clash and push it down to carve it.
9. **Song sections as blocks on a table.** The regions (verse, chorus, bridge) as blocks to
   rearrange by hand. One undo step per rearrangement; the 2D view shows the result.
10. **Drum pads on anything.** Tap the desk, a crate or a knee and it plays the drum track; pads
    marked on real surfaces via the room calibration.
11. **A tape reel for undo history.** Crank a reel to scrub the history list (`undo_to`),
    clicking at each step and playing the song as it was there.
12. **Anything can be a sample.** Grab an item, squeeze the duck or hit the cowbell, and its
    (synthesised) foley drops into a sampler track.
13. **Hold a cassette to your ear.** A clip-cassette (#4) or a sample held to the ear plays for
    you alone: browsing sounds is picking them up and listening.
14. **Clap to mute.** Palms pressed together mute the track you are pointing at while held; a
    clap latches it.
15. **A music-box sequencer.** A turning cylinder with pegs on a grid; placing pegs programs a
    pattern that plays an instrument track, as ordinary MIDI.
16. **Chord bricks.** Chords as blocks stacked into a progression on a shelf; dropped on a track
    they write the notes. Pairs with section blocks (#9).
17. **A DJ platter for scrubbing.** A turntable on the desk is the playhead: spin to scrub, hold
    to stop, back-spin for fun.
18. **Sidechain as a rope.** Tie a rope from the kick to the bass; it goes taut each time the
    bass ducks, and pulling harder ducks more.
19. **Every venue has something to play.** Chimes in the garden, icicles in the cabin, crystals
    in the cave, the rooftop railing: tuned to the song's key, recordable to a track.
20. **Generative weather.** In a weather arrangement (the Loft's thunderstorm), raindrops on the
    glass trigger notes from the song's scale; record it as a track or ignore it.
21. **A looper station, by hand.** Slap the looper's pad to record a loop, slap again to stack a
    layer. Each layer is a ring around you: grab it to mute, pull it away to delete. Hands only:
    no stomping (feet are not an input).
22. **An air harp of the current chord.** Strings in the air tuned only to the chord playing now
    (from the chord bricks): strum or pluck, no wrong notes, recorded as MIDI.
23. **A theremin.** One hand pitch, the other volume; optionally snapped to the song's scale,
    with a visible pitch guide so it is playable, not only a novelty.
24. **A sample as a cloud of grains.** Reach into the cloud and it plays grains from where your
    hand is; spread the fingers to widen the spray. Granular synthesis made intuitive.
25. **A modular synth wall.** A modular synth patched with cables, on the existing patchbay and
    cable physics.
26. **Lyrics in the booth.** Lyrics at eye level in the vocal booth, scrolling with the song,
    the current line lit.
27. **The song in the sky.** At night venues the song's sections are constellations crossing the
    sky as it plays: look up to see where you are.
28. **Chord shapes on one hand.** Fingers held up on the left hand pick the chord (one is I, four
    is IV), the right hand strums. Pairs with the chord harp: no wrong chords.
29. **A circle-of-fifths wheel.** A wheel of the key's chords: touch a segment to play it, and the
    chords that would sound good next glow. Feeds the chord bricks.
30. **A circle of hand drums.** Djembe, congas and a cajón in a ring for the band; where the
    head is struck changes the tone (slap at the rim, bass at the centre).
31. **The world plugs into the modular.** The weather, the venue instruments and the looper
    rings get output jacks on the modular wall: patch rain density into a filter, the cave's
    drips into a drum trigger.
32. **A handbell choir.** Each player holds handbells tuned to the current chord's notes; swing
    to ring. They retune when the chord changes, so the band cannot clash.
33. **Cables between players.** Plug a cable from your instrument into a bandmate's: your hand
    drums trigger their synth, your chord hand drives their harp.
34. **A string across the room.** Stretch a string between any two points; its length sets the
    pitch, snapped to the key. A giant bass string across the room, or five by the window.
35. **A marble run.** Build a run from blocks; marbles roll in time with the song and each block
    they hit plays its note. The marbles never touch mix state.
36. **Your fingertips are notes.** Thumb to each finger plays the current chord's notes (index
    the root, middle the third, and so on). No prop; hand tracking.
37. **Bend and wobble by tilting.** Tilting the playing hand bends pitch, shaking it adds
    vibrato, on the keytar, harp and theremin.
38. **Shakers and a tambourine.** Hand percussion to hold and shake; hits snap gently to the
    beat.
39. **A talk box.** Sing into a tube while the other hand holds a chord shape; the voice comes
    out as that chord.

## Constraints learned

- Inputs are hands (controllers, hand tracking, mouse). No feet: stomps and pedals pressed
  underfoot do not work.

## Avoid

- The timeline as a hallway you walk down.
- Fun that costs precision with no way to refine it.
- Physics on anything that holds mix state.
- Effects that move the room around the reader.
