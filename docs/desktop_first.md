# Desktop first

*Written after asking: why does this feel like a demo on a monitor when every control in it works?*

## The diagnosis

The best early decision in this codebase is `ControlAffordance`: one contract, `grab_begin /
grab_move / grab_end`, that a mouse ray, a tracked controller and a pinching hand all drive. That
decision is why the desktop build works at all.

It also explains why the desktop build doesn't feel like a desktop app. **The contract is the
hand's native gesture**: take hold of something, move it continuously, let go. A mouse and
keyboard have their own native gestures, and four of the five aren't in the contract:

| desktop gesture | what it is | in the contract? |
|---|---|---|
| hover | the cursor is always *somewhere*; a hand usually isn't | computed every frame, **drawn nowhere** |
| drag | continuous positional move | yes, it's the only thing there |
| wheel | relative nudge, no position | no; the wheel zooms the camera even over a knob |
| type | an exact value | no |
| modifiers | fine/coarse, reset, constrain | no |

So on a monitor this is a hand simulator driven with a mouse. Everything can be reached, but
none of the desktop's own strengths are available. **First-class desktop doesn't mean polishing
the hand simulator. It means making the desktop's gestures members of the same contract.**

That isn't the divergence `control_affordance.gd` warns against ("two divergent control sets").
The codebase already has the precedent: **dwell** is a non-press route into the same contract,
added for accessibility, and nobody calls it a second control set. Wheel-over-a-knob is the same
kind of thing: a different way to say the same sentence to the same object.

## What was verified, not assumed

- `Interactor.hovered` is set every physics frame. The only readers are the dwell timer and
  patch-cable dragging. **Nothing renders it.** On a monitor you can't tell what's under the
  cursor until you click and something moves.
- **No control can tell you its value.** Drag a fader and the feedback is the cap position and
  the slide sound. There's no dB anywhere.
- **Undo doesn't exist.** The word only appears in comments, including `panel_button.gd`
  justifying a design choice with "a mute you did not mean is one press to undo". The design
  already assumes it exists.
- **Knobs turn by circular drag around their own centre** (`knob.gd`, `atan2` of the contact
  point). A rack knob is about 15 px on a monitor; a few pixels near the middle is a huge
  angle. Plugin UIs moved to vertical drag for this reason.
- **No reset gesture.** No double-click, no modifier-click, no default value on any control.
- **Navigation is three models competing**: right-drag orbit (which you said feels sickening),
  WASD walk, and F to cycle focus. Getting to the tape deck is F four times.
- **Discoverability is one 13 px line of text** naming seven keys.

## Conventions a Reaper user already has in their hands

These aren't inventions. They're what every DAW and plugin does, so following them costs the
user nothing to learn:

- Hover highlights the control and shows **name + value in its own units** (-4.2 dB, 1.8 kHz, 4:1).
- **Wheel** adjusts the control under the cursor. Shift (or Ctrl) for fine.
- Knobs **drag vertically**, regardless of where you grabbed them. Shift-drag for fine.
- **Double-click resets** to default (0 dB, centre pan, the plugin's default).
- Double-click or Enter on the readout to **type an exact value**.
- **Ctrl-Z / Ctrl-Shift-Z.**
- Drag across a row of mute/solo buttons to **paint** them.
- Number keys jump straight to a view; you don't cycle through four things to reach the fifth.

## Navigation

Nobody in a real studio flies around the room. You sit at the desk, lean over to the rack,
stand back to see the whole room. That's a handful of **good seats**, not free flight:

- `1`-`5` jump straight to console, patchbay, rack, tape deck, timeline. `` ` `` (or Esc) is
  "stand back and see the room". `F` cycling stays, for controllers and anything without
  number keys.
- The seat change is a short eased move, so you always see where you went. The motion-sickness
  setting that already scales the gear's glide scales this too.
- Orbit stays as the escape hatch, but it pivots on **the point under the cursor** instead of a
  fixed spot in mid-air. Pivoting around nothing in particular is what makes orbiting feel like
  being spun. Middle-drag pans, as in Blender and every 3D tool.
- The wheel follows the convention above: **over a control it adjusts the control, over
  anything else it zooms toward the cursor.**

## Readable at a glance

- A **hover card** next to the cursor: control name, track, value in units, and the gestures
  that apply ("wheel · double-click resets · type to enter"). It teaches the conventions in
  place without a manual.
- The **hovered control lights up** with a thin rim in the same accent across all gear, so
  "this is what you'll touch" looks the same everywhere.
- **While dragging, the readout stays up and updates**, pinned beside the control, not the
  cursor (the cursor leaves the control on long fader throws).
- The HUD line becomes a quiet **help overlay on `?`/F1**, grouped by what you're trying to do
  instead of a list of keys. The always-visible strip shrinks to the session name, what's
  focused, and "? for help".

## Undo

`ControlAffordance` already emits `value_committed`. A `MixJournal` listens to every commit,
records `(control, before, after, who)`, and Ctrl-Z writes `before` back through the same
`write_value` path the control uses, so the DAW proxy stays the only route to Reaper. `who` is
the participant id: unused in a solo session, but it's what lets a later multiplayer session
undo *your* moves and not someone else's.

## How VR gets these for free

None of this is desktop-only plumbing. It's the contract getting wider:

- `hover_enter / hover_exit`: on desktop, the cursor; in VR, a fingertip within a couple of
  centimetres. Same rim, same card.
- `nudge(steps, fine)`: wheel on desktop, thumbstick in VR.
- `readout()`: every control returns its value in its own units. The hover card, the drag
  readout and a screen reader all read the same string.
- `reset()`: double-click on desktop, double-pinch in VR.
- Undo is medium-agnostic.

## Order of work

Each step should be usable on its own, so every tick leaves the app better:

1. **Hover + readout.** Rim highlight, hover card with name and value. The biggest single win:
   the desk becomes legible under the cursor.
2. **Knobs drag vertically** on desktop; **wheel nudges** the hovered control, with a fine
   modifier.
3. **Double-click resets** (needs a default value on each control).
4. **Undo / redo journal.**
5. **Number-key seats, orbit pivoting on the cursor point, middle-drag pan, zoom to cursor.**
6. **Type-in values.**
7. **Help overlay** replacing the HUD line.
8. Paint-drag across mute/solo.

Each one gets a test the way the framing work did. The rule from that work still holds: a
passing test isn't a working app, so each step also gets driven through the real input path.

## Found along the way

- **FX parameters read as a percentage** ("THRESH 44%"). Correct, but nobody sets a compressor
  in percent. Reaper sends each parameter's formatted value over OSC; the backend should cache
  it and the rack knob's `describe_value` should prefer it.
- **The focused surface is still easing at frame 90** of a capture: the rack sat ~30 px apart
  between frame 40 and frame 90 of the same setup. Something settles long after the 0.42 s glide.
- **Unfocused gear intrudes into the frame.** With the rack focused, the console fills the
  bottom-right third of the shot. The furniture-yielding pass only moves `room_furniture`, and
  the console is a surface.


## The room is furniture (added)

"I want this to also feel like a studio where I can push racks around on wheels and move stuff
around in general." The focus rig brings gear to you; this is the other half -- the room itself
is yours to arrange, and it stays arranged.

- Done: the rack plinth, the deck cart and the timeline stand are `Trolley`s on swivel casters;
  the lamps slide on their bases and carry their light. Grab the structure (never the gear),
  drag, and it follows with weight; scroll while holding to turn it. It collides with the
  console, the walls and the other pieces (`FloorPlan`), the casters trail and roll, it rumbles
  and knocks, the looms re-route behind it, and where it ended up is saved.
- A summoned surface whose stand is pushed goes home to where the stand now is.
- The console is a fixture on purpose: it is what the mix position is measured from.
- Next: the camera should go to the gear instead of the gear coming to the camera on a monitor
  (step 5's seats), so a rearranged room stays the room you work in; thumbstick turning in a
  headset; a grip on the rack cabinet itself, not only its plinth; more furniture (speaker
  stands, a sofa) once there are things worth moving for.
- Shared sets: `FloorPlan` is the one place a move is decided and reports who made it, so it is
  where replication goes when the virtual set is shared.
