class_name Studio
extends Node3D

## The room, its lighting, and the three anchors a surface can hang from.
##
## Built in code rather than authored as a .tscn, and that is a considered choice rather than
## laziness. Nothing in here has a fixed shape: the console is as wide as the project has tracks,
## the rack is as tall as it has plugins, and in ROOM mode the whole layout is positioned against
## a physical room measured at run time. A .tscn would be a snapshot of one project's dimensions,
## and every launch would start by discarding it.
##
## THE THREE ANCHORS, which are the whole of the hybrid mode:
##
##   screen_stage  a child of the CAMERA. Things here follow the viewer's head and are read like
##                 a panel. Where a timeline belongs.
##   room_anchor   the shared physical frame, calibrated against two marks on the real floor.
##                 Things here stand still while you walk around them, and everyone in the room
##                 agrees where they are. See core/xr/room_anchor.gd.
##   studio_set    the virtual room. For a participant who is not in the physical one.
##
## A surface is placed in exactly one of them, per viewer, by SurfaceMount.

## The walls of the control room: the working footprint. Each venue builds the rest of its
## world -- and the activity zones behind the mix position -- around this (see Venue.ZONES).
## Sized to feel like a room you can move about in, not a booth: at 6.4 x 5 m under a 2.8 m
## ceiling every venue read as cramped round the gear, and at 8 x 6 m under 3.3 m it still was once
## the room had twenty stations in it (2026-10-28, "EVERYTHING is way too cramped"). The mixing
## neighbourhood is a ring round the seat with aisles between its pieces (docs/architecture.md,
## "Room layout").
const ROOM_WIDTH := 11.2
const ROOM_DEPTH := 8.0
const WALL_HEIGHT := 3.6
## The footprint's open rear and front wall, along z, and its middle. The rear is the line the
## live room's neighbourhoods are laid out from; there is as much room behind the seat (the stage
## table and the station board) as in front of the desk.
const ROOM_BACK := 4.0
const ROOM_FRONT := ROOM_BACK - ROOM_DEPTH
const ROOM_MID := (ROOM_FRONT + ROOM_BACK) * 0.5
## The stand that carries the timeline. Its top sits just under the panel's lower edge, which
## is why it is a constant rather than a number in two places: move the timeline and this has
## to follow or the panel floats again, one centimetre higher.
##
## Scaled up as a whole when it stands in the room, lettering, keys and lanes together: at its own
## size it is an 86cm panel of 2.3cm lanes a metre and a half from the seat, which read as a
## postage stamp (2026-10-13: "the timeline is just so damn tiny you really need to scale that
## up"). Its top stays where it was, so it hides no more of the big board behind it; it grows
## down toward the desk, and its stand is shorter and wider for it.
const TIMELINE_SCALE := 1.7
const TIMELINE_Y := 1.50
const TIMELINE_Z := -1.02
const TIMELINE_STAND_TOP := TIMELINE_Y - 0.16 * TIMELINE_SCALE
const TIMELINE_STAND_Z := TIMELINE_Z - 0.04
## Where the stand's legs stand, either side of the scaled panel.
const TIMELINE_LEG_X := 0.36 * TIMELINE_SCALE
## The clip editor (ClipEditorSurface): clamped to the timeline stand's right-hand leg, just in
## front of it, under the lanes and right of the timeline's deck: the one stretch of the seated
## view with nothing in it, so the clip being trimmed and the arrangement it is in are seen
## together from the desk. Beside the timeline's shoulder it ran off the edge of the frame; above
## it, out of the top. Turned a few degrees away from the seat, not toward it: turned in, its right
## end came within 0.3 m of the tape deck's cart, and the room keeps 0.6 m between its pieces
## (`_test_the_studio_hangs_the_clip_editor_by_the_timeline`). Scaled as the timeline is, a little
## less. Where its board's left edge is on the floor, the height of its origin, and its turn.
const CLIP_EDITOR_SCALE := 1.35
const CLIP_EDITOR_Y := 0.925
const CLIP_EDITOR_LEFT := Vector2(0.43, -0.985)
const CLIP_EDITOR_YAW := 7.0
## The lamps in the room: where the light comes from, what colour, and how hard.
##
## One table, read twice -- once by the environment to make the lights and once by the furniture
## to make the stands under them. They were two floating OmniLights with nothing to come out of,
## which is the lighting version of the patchbay wired to nothing: a room lit by sources you
## cannot see. The third is new, and it is there because the measurement said so -- the rack's
## faceplate read 13.8 against the console's 22.1, and the floor at its foot 9.1 against 29.5.
## Spread 0.8 m further out each side than first placed, with the room: left where they were
## in a wider room they bunched round the desk and stood between the seat and the wardrobe.
const PRACTICALS: Array = [
	[Vector3(-4.3, 1.76, 2.2), Color(1.0, 0.78, 0.52), 6.0],
	# Clear of the deck trolley from the seat: behind it, it was a lamp you could not take hold of.
	# Forward on the right since the patch stand took that side of the room: anywhere behind it
	# the stand was in the way from the seat. Left of the TV since the TV hung on the front wall
	# (docs/sampling_station.md): at (2.7, -3.1) it stood in front of the screen, and right of it
	# there is no room between the EQ wall and the door.
	[Vector3(1.65, 1.70, -3.2), Color(0.6, 0.78, 1.0), 5.5],
	# Moved back and out, and turned down, once the desk started being summoned to the mix
	# position. At (-0.80, 1.72, 0.34) this lamp stood 0.71m from the left end of a summoned
	# desk and 1.55m from the right; inverse square makes that a five-to-one gradient across
	# one console, and the left end blew to white -- the BANK module read as a hole in the
	# panel and its indicator bar lost its colour entirely. It also stood 80cm to the left of
	# the mix position and 30cm in front of it, which is somewhere you would kick it.
	#
	# From here, against the body's own work light, inverse-square irradiance at the two ends
	# comes out within a couple of percent. Summoned gear is lit by the work light; the room's
	# lamps light the ROOM. `_test_the_desk_is_lit_evenly_end_to_end` holds the balance.
	[Vector3(-3.2, 1.72, 0.75), Color(1.0, 0.82, 0.60), 4.5],
]
## How far a practical reaches. Short on purpose: at 6.5m each lamp lit all three walls, and
## three of them made the empty half of the room as bright as the gear (37.0 against 38.7 on
## the console's face). A floor lamp is a pool, not a sun.
## Longer since the room grew: at 3.6 m the 11 m room's corners were black.
const LAMP_RANGE := 4.6
## The lamp head. Wide and low rather than tall and thin: the first pass put a 105mm shade on a
## two-metre pole, which from across the room is a street light. A floor lamp is shorter than
## the people using it and its head is the part you notice.
const LAMP_SHADE_RADIUS := 0.165
const LAMP_SHADE_HEIGHT := 0.150
## The patch stand: the bay's own cabinet, out to the right of the desk past the deck, turned to
## face the mix position. Its own station rather than a strip on a meter bridge between the timeline and
## the console, where it was a hand's width tall and read as part of both. Where on the stand the
## bay's top edge is, and how far the cabinet under it reaches back.
const PATCH_STAND_AT := Vector3(SessionLayout.PATCH_AT.x, 0, SessionLayout.PATCH_AT.y)
const PATCH_STAND_HEADING := SessionLayout.PATCH_HEADING
const PATCH_BAY_TOP := 1.78
const PATCH_BAY_FRONT := 0.03
## How far up the arm from MY KEYS the wrist's INTO ME socket is worn (m): clear of both reaches.
const WRIST_IN_APART := 0.06
## How far down onto the back of the hand from MY KEYS the chord hand's MY CHORDS socket is worn,
## and across the controller from it (m): clear of both reaches, as INTO ME is the other way.
const WRIST_CHORD_APART := 0.056
const PATCH_CABINET_DEPTH := 0.12

## Set by whoever builds the studio, BEFORE adding it to the tree. The medium is not a rendering
## detail: it decides whether this participant gets a floor and furniture at all, and a studio
## that learned it a frame late would build a virtual room and then delete it in front of someone
## already wearing the headset.
var medium: int = Presentation.Medium.SCREEN
var xr_bootstrap: XRBootstrap = null

signal venue_changed(id: StringName)
## EDIT on the lyric board at a desk: the session panel's LYRICS box, which is not the studio's, is
## asked to open (LyricBoard, docs/spatial_loop.md part two, slice 56).
signal lyrics_edit_asked()
## P: the computer keyboard as a piano, on or off (the session panel's KeyCatcher).
signal computer_keys_toggled()

## The world the studio stands in. See core/venues/venue.gd.
var venue: Venue
var world_env: WorldEnvironment
## How much brighter than each venue's own exposure the room is shown.
const EXPOSURE_LIFT := 1.2
var key_light: DirectionalLight3D

var camera: Camera3D
var rig: XRRig
## A bare hand's way about the floor in a headset (Teleport); null on a screen.
var teleport: Teleport
var screen_stage: Node3D
var room_anchor: RoomAnchor
var studio_set: Node3D
var mount: SurfaceMount
var body: BodyFrame
var focus: FocusRig
var presence: Presence
## This participant's body. Everything placed for a person is placed from it, and it is one
## object rather than a scattering of constants precisely so there is somewhere to change it.
var ergonomics := Ergonomics.new()
## Where a height chosen in the room is remembered. Tests point it somewhere of their own.
var body_path := Ergonomics.HEIGHT_PATH

var console: ConsoleSurface
var rack: RackSurface
## The things people pick up and carry. Null in AR, which has a real room's things in it.
var items: ItemRoom
## The chained case in the back of house that starts a Tour run. Null in AR, for the same
## reason `items` is: Tour is gated to the built-in engine (core/tour/tour.gd's `is_available`),
## and AR is a real room with a real case or none at all.
var tour_case: TourCase
## The "roll some gear" panel on the control room wall. Unlike `tour_case`, not AR-gated or
## backend-gated: it works against whichever DAW backend is open, built-in or Reaper alike.
var rig_roulette_station: RigRouletteStation
var roll_board: RollBoard
## What the mic in a hand here has done to a track, to be undone when it leaves the hand.
var mic_arm := MicArm.new()
## Whether the headphones are on a head here, as Ears was last told.
var _heard_phones := false
## The personal mix of whoever is at this machine: the tablet's receivers (docs/items_loop.md).
var personal := PersonalMix.new()
## Other players' keys, played here for the personal mix's plugs in them.
var their_keys: TheirKeys
## Other players' monitors, rebuilt here in time for the personal mix's plugs in them.
var their_monitor: TheirMonitor
## A cassette held to the ear here, playing its clip to this player alone (docs/spatial_loop.md
## part two, slice 25): `_follow_ear` tells it which, each frame.
var ear: EarCue
## The hand percussion played here, taken down onto the armed track while recording.
var hit_recorder: HitRecorder
## The strikes on the instruments that stand still, by this player's hands and controllers (Strike,
## docs/spatial_loop.md part two, slice 38).
var strike: Strike
## This player's own hits on the fast path (docs/spatial_loop.md part two, slice 39): a keys helper
## of its own with no MIDI, "dawlings · hits", holding Foley's struck sounds, while it runs; null
## where it cannot (`_start_hit_voices`), and every hit plays on MONITOR through Godot.
var hit_voices: NativeKeys = null
## Where a hit played here goes out to the room: Session.send_item_hit, or the suite's.
var send_item_hit: Callable = Session.send_item_hit
## Every instrument's output jack: where its hits are recorded (docs/spatial_loop.md slice 5), or
## the bandmate they play into (slice 6). The room's patch, like `patches`.
var jacks: Jacks
## This player's drum pads on real surfaces (SurfacePads, docs/spatial_loop.md part two, slice 41):
## the room's kit's own (KitItem.surface), in the session frame, saved on this machine.
var pads: SurfacePads
## This player's own keys' jack, on their left wrist in a headset (HandSkeleton.wrist) and on
## the left controller while that hand holds one; P with an empty hand on a desktop. Beside it the
## chord hand's (`chord:P`, MY CHORDS, part two slice 33), on the chord hand: the left, or for a
## left-handed player the right; P in the chord layer on a desktop.
var wrist_jacks: Array[JackSocket] = []
## The computer keyboard as the keytar's keys, while it is in this player's hands (KeytarItem).
var keytar_keys: KeyCatcher
## Whether the keytar is in this player's hands, as last seen: for GuestMidi to play it.
var _keytar_mine := false
## The desktop's fingertips' keys, J K L ; (docs/spatial_loop.md slice 8): while it has the
## keyboard the mouse's fingers play notes and the mouse grabs nothing. T gives it the keys.
var fingertip_keys: KeyCatcher
## Each hand's fingertip notes: the mouse's on a desktop, each controller's in a headset.
var fingertips: Array[FingertipNotes] = []
var _told_fingertips := false
## This player's chord hand (ChordHand, docs/spatial_loop.md part two, slice 32): the shape the
## left hand holds up (the right for a left-handed player), the chord stick, and on a desktop the
## chord layer (C).
var chord_hand: ChordHand
var _told_chords := false
## The chord harp against the live room's back wall (ChordHarp), stood again with each venue at
## its `harp_spot`. Null in AR, where the room is a real one.
var harp: ChordHarp
## The circle-of-fifths wheel on the bricks table (FifthsWheel), stood again with each venue at
## its `wheel_spot`: where the song's key and chords are written from the room. Null in AR.
var wheel: FifthsWheel
## The song's sections as blocks along the bricks table's far edge (SectionBlocks, docs/spatial_loop.md
## part two, slice 30), stood again with each venue at its `sections_spot`. Null in AR.
var sections: SectionBlocks
## The ledge for chord bricks along the bricks table's near edge (ChordLedge, docs/spatial_loop.md
## part two, slice 31), stood again with each venue at its `ledge_spot`: a row of bricks is a
## progression, its slots the room's holder ChordBrick.LEDGE. Null in AR.
var ledge: ChordLedge
## The last section harmony a guest's brick asked the host for, as [FifthsWheel.VERB, [bar, inside]]
## (`press_brick`); empty before one.
var brick_asked: Array = []
## The cassette rack beside the prop shelf (CassetteRack, docs/spatial_loop.md part two, slice 23),
## stood again with each venue at its `cassette_rack_spot`: the clips pulled out of the timeline,
## shelved. Null in AR.
var cassette_rack: CassetteRack
## The sampler beside the rack (Sampler, docs/spatial_loop.md part two, slice 26), stood again with
## each venue at its `sampler_spot`: REC, then a sound, is a sample cassette on the rack. Null in AR.
var sampler: Sampler
## The circle of hand drums on the drum riser (HandDrum, docs/spatial_loop.md part two, slice 40): its
## plaque, low on a post between the front two drums and leant back, stood again with each venue at its
## `drum_circle_spot`. The drums are items of the room (ItemRoom.KINDS), at home round it
## (`_item_homes`). Null where there is no riser (the Rig Roulette room) and in AR.
var drum_circle: Node3D
## The venue's own instrument's mount (VenueInstrument, docs/spatial_loop.md part two, slice 42): its
## beam, eave, shelf or frame, its plaque and the set's one jack, in the venue's frame at
## `Venue.instrument_spot`. The bars are items of the room (`venue1`..`venue8`), dressed as its set
## and at home on it (`_dress_venue_bars`, `_item_homes`). Null where the venue has none.
var venue_instrument: VenueInstrument
## The venue's weather (Weather, docs/spatial_loop.md part two, slice 44): its switch, plaque and jack
## on a window's sill or a post, and the drops it draws on the glass or into the cave's pools, in the
## venue's frame at `Venue.weather_spot`. Null where this arrangement has none.
var weather: Weather
## The switch's state, the room's row `weather`: LISTEN (true) or OFF. The room's, not the venue's,
## so it is kept across a change of venue and said to a weather stood afterwards.
var weather_listening := false
## The looper on its stand at the drum riser's front corner (Looper, docs/spatial_loop.md part two,
## slice 45), stood again with each venue at its `looper_spot`. Null where there is no riser and in AR.
var looper: Looper
## The room's row `looper`: [peer, from_bar, bars] of whoever is looping, or [] for nobody. The room's,
## not the venue's, so it is kept across a change of venue.
var looper_row: Array = []
## How many bars this player's next layer is where no loop range is set (the looper's LENGTH): their
## own, kept across a change of venue.
var looper_length := Looper.LENGTH_DEFAULT
## The music box beside the harp (MusicBox, docs/spatial_loop.md part two, slice 47), stood again with
## each venue at its `music_box_spot`, on its trolley. Null where there are no zones and in AR.
var music_box: MusicBox
## The room's row `music_box`: [track, length, root, chromatic] (MusicBox.row). The room's, not the
## venue's, so it is kept across a change of venue.
var music_box_row: Array = MusicBox.DEFAULT_ROW.duplicate()
## The string spool in the aisle between the drum riser and the lattice, at the lattice's front corner
## in the loft (RoomString.Spool, docs/spatial_loop.md part two, slice 48; Venue.default_string_spool_spot),
## stood again with each venue at its `string_spool_spot`, on its trolley. Null where there are no zones
## and in AR.
var spool: RoomString.Spool
## The theremin in front of the drum riser's outer end (Theremin, docs/spatial_loop.md part two,
## slice 50; Venue.default_theremin_spot), stood again with each venue at its `theremin_spot`, on its
## trolley. Its SCALE switch is this player's own, kept across a change of venue (`theremin_snap`).
## Null where there are no zones and in AR.
var theremin: Theremin
var theremin_snap := Theremin.Snap.FREE
## The grain cloud in the aisle between the drum riser and the lattice (GrainCloud, docs/spatial_loop.md
## part two, slice 54; Venue.default_grains_spot), stood again with each venue at its `grains_spot`, on
## its trolley, its bowl the room's holder `bowl`. Null where there are no zones and in AR.
var grain_cloud: GrainCloud
## The room's row `grains_key`: the cloud's KEY switch, on to follow the chord's root. The room's, not
## the venue's, so it is kept across a change of venue.
var grains_key := false
## The room's row `strings`: {id: [a, b, maker]}, each string's ends in the venue's frame and who tied
## it (RoomString.answer). The room's, not the venue's, so it is kept across a change of venue and
## stood again in the next.
var strings_row := {}
## The strings standing in the room, by id (RoomString), stood from `strings_row` (`_show_strings`).
var room_strings := {}
## How many strings this player has tied, for the next one's id.
var _strings_tied := 0
## The marble run in the lattice (MarbleRun, docs/spatial_loop.md part two, slice 49), its tray at the
## lattice's face toward the desk, stood again with each venue at its `marbles_spot`. Null where there
## is no lattice and in AR.
var marbles: MarbleRun
## The room's rows `marbles` {cell: [kind, facing]} (MarbleRun.answer) and `marble_balls`, the beats
## BALL let marbles go on (MarbleRun.answer_ball). The room's, not the venue's, so they are kept across
## a change of venue and stood again in the next.
var marbles_row := {}
var marble_balls: Array = []
## The modular wall over the synth zone's keyboard stand (ModularWall, docs/spatial_loop.md part two,
## slice 51), a surface hung again with each venue at its `modular_spot`; null in AR. The voice that
## plays this player's keys through its patch while they stand at it (ModularVoice), and the room's
## row `modular` {cables, knobs} (Modular), the room's and not the venue's.
var modular_wall: ModularWall
## The lyric board in the vocal booth (LyricBoard, docs/spatial_loop.md part two, slice 56), stood
## again with each venue at its `lyrics_spot`; null where there is no booth and in AR. What it shows is
## the song's (MixState.lyrics), so nothing of it is the room's.
var lyric_board: LyricBoard
var modular_voice: ModularVoice
var modular_row := Modular.default_patch()
## Each bandmate playing the modular, heard through the room's patch at the wall (slice 52): a
## ModularVoice of theirs by peer, and what they hold on it ({peer: {pitch: true}}).
var modular_heard := {}
var _modular_heard_held := {}
## The knobs as this player last streamed them ({id: v}): what their own voice and their take hear
## of a turn, kept on the voice while the room's row has not caught up (`_show_modular`).
var _modular_streamed := {}
## The computer keys as the modular's keys (PLAY on its KEYS module), and this player's newest key
## and how many are held, for KEYS' readout.
var modular_keys: KeyCatcher
var _modular_held := {}
var _modular_last := -1
## The world into the modular (slice 53): what the weather, the venue's instrument, the looper's rings
## and the marble run play into its world sockets (ModularWorld), on every machine from the song
## clock and the rows; and the world's own voice at the wall, which plays the patch with no keys while
## a world socket is patched into it and no other voice here is playing it, so a drip into an ENV's
## gate sounds with nobody playing, and once, not twice, with somebody.
var modular_world: ModularWorld
var modular_world_voice: ModularVoice
## The DJ platter on the leaf of the tape deck's cart (Platter, docs/spatial_loop.md part two, slice
## 27): bare it is the playhead, scrubbed by hand; a cassette in its slot is scratched. Rides the
## cart, so it is the studio's and not the venue's. Null in AR.
var platter: Platter
## A guest's pulls the host has not answered: {seq, hand, look}, the look a blank cassette in that
## hand until the host's made one arrives there or the ask is refused (`_settle_makes`).
var _making: Array = []
## The hands a made item the host has answered for is to go into, oldest first (`_take_given`).
var _awaiting_hands: Array = []
## A headset hand holding a made item by a bandmate's glove: {hand: [peer, seconds]} (`_follow_gives`).
var _give_held := {}
## How near a bandmate's glove a carried made item is held to hand it over (m), and for how long (s).
const GIVE_REACH := 0.25
const GIVE_HOLD := 0.5
## Who is ON AIR, by peer id: whose monitor anyone may plug into. The room's, like `patches`.
var on_air: Array = []
## Who has a plug in which SEND socket: {peer id: [socket name per receiver, "" in the tray]}.
## The room's, so the host's: everyone sees everyone's plugs. Whoever is at this machine hears
## their own row (`personal`).
var patches: Dictionary = {}
## Plugins torn off the rack, each on its own stand: {stand id: [Trolley, PluginTablet]}.
var tablets: Dictionary = {}
## Whole tracks pulled out of the rack, each on a rack of its own on its own trolley:
## {stand id: [Trolley, RackSurface]}. The room's, like the tablets.
var track_racks: Dictionary = {}
## While the host's room is being put up here: a stand set down by it is not news to send back.
var _applying_room := false
var _room_publish_due := false
## Whether what stands here is the host's room rather than this participant's own.
var _showing_hosts_room := false
## A guest's asks the host has not answered yet: {seq, verb, args, id}. See apply_room.
var _predictions: Array = []
var _motion_sent_msec := 0
## Guest: how many stands it has put out on its own say-so, for naming them until the host does.
var _predicted_tablets := 0
var _predicted_track_racks := 0
var deck: TapeDeck
var patchbay: PatchbaySurface
var timeline: TimelineSurface
## The one clip editor, closed until a clip is opened in it (TimelineSurface.edit_asked).
var clip_editor: ClipEditorSurface

## Where each machine's loom leaves it, in that machine's own space, and where it lands across
## the back of the bay. One entry per run: machine, exit point, exit direction, the fraction
## across the bay's back it arrives at, and the point on the floor its run passes through.
##
## The floor points all sit behind the desk rather than in front of it, which is both where real
## trunking goes and the only place in this room where two metres of cable is not underfoot.
## Where each machine's loom leaves it, in that machine's own space; where it lands across the
## back of the bay; and, for the two that take the floor, the point on the floor their run passes
## through -- and a flag saying which kind it is. The console's does not take the floor: it
## stood under the bay once, when the bay rode a meter bridge over it; now the bay has its own
## stand, every run takes the floor behind the desk.
const LOOM_RUNS: Array = [
	["console", Vector3(0, 0.02, -0.19), Vector3(0, 0.6, -1.0), 0.0,
			Vector3(0.30, 0, -0.72), true],
	["rack", Vector3(0, 0.07, -0.29), Vector3(0, -0.18, -1.0), -0.74,
			Vector3(-0.70, 0, -0.72), true],
	["deck", Vector3(0, -0.02, -0.05), Vector3(0, -0.5, -1.0), 0.74,
			Vector3(0.86, 0, -0.96), true],
]

var _looms: Array[GearLoom] = []
var _looms_dirty := false
var _loom_clock := 0.0

## The floor and everything on wheels. Null in AR, where the floor is real and so is the
## furniture.
var floor_plan: FloorPlan
var rack_trolley: Trolley
var deck_trolley: Trolley
var timeline_stand: Trolley
var patch_stand: Trolley
## The stage table (StageTable, docs/spatial_loop.md slice 18) and the trolley it stands on.
var stage: StageTable
## Signal you can see (SignalBeads, docs/spatial_loop.md part two, slice 21): one bank of beads
## riding every cable in the room, and how far the practicals were last lifted by a clip.
var signal_beads: SignalBeads
var _lamps_lifted := 0.0
var stage_trolley: Trolley
## The EQ wall (EqWall, docs/spatial_loop.md part two, slice 36), the trolley it stands on at the
## control room's side wall, and the spectra it shows (Spectra: measured here, or the host's).
var eq_wall: EqWall
var eq_wall_trolley: Trolley
var levels: LevelsWall
## The niche in the front wall LEVELS is set into: a piece of the floor plan that never rolls.
var levels_niche: Trolley
## The sampling station's TV (TvSurface, docs/sampling_station.md), and what holds it: a bracket on
## the front wall, or a stand where there is no wall (Venue.tv_mount_spot). Built in, as the niche is.
var tv: TvSurface
var tv_mount: Trolley
var spectra: Spectra
## What stands on the floor by itself and is pushed about like the gear, though it is not in the
## control room's rig: the venue's free-standing stations and back-of-house furniture
## (Venue.WHEELED), the station board's stand and the audio patch wall's legs. id -> Trolley. Built
## once and the same in every venue, as the rack is; a venue with no room for one hides it
## (`_wheel_in_live_pieces`). Empty in AR.
var live_pieces := {}
## The handbells' stand, a child of the venue at `bell_stand_spot` (HandbellItem.stand).
var _bell_stand: Node3D
## Clap to mute (Clap, docs/spatial_loop.md slice 19): the two hands' palms or grips, and K held at
## a desk. Two of them, so a key and the hands never let go of each other's press.
var clap := Clap.new()
var key_clap := Clap.new()
## Look to solo (LookSolo, docs/spatial_loop.md part three, G): this machine's own, and on a host
## each guest's by peer, run for them.
var look_solo := LookSolo.new()
var guest_look_solos := {}
## Leaning in (Ears.lean): L held at a desk, and the track it was refused for, said once.
var _lean_key := false
var _lean_refused := 0
## Surface id -> [the trolley it stands on, where on that trolley].
var _seated_on := {}
var _lamps: Array[OmniLight3D] = []
## The one tween either `_flicker_lights` or `_lights_out` ever runs, killed before the other
## starts a new one, so a second chaos event mid-blackout can never fight the first over a lamp.
var _lights_tween: Tween
## {piece_id: Transform3D} -- where the authored layout stood each piece, for the things that
## were written against it: the floor points the looms run through.
var _authored_floor: Dictionary = {}
## How wide the room is right now. Starts at the authored width and grows with the desk; see
## SessionLayout.
var room_width := ROOM_WIDTH
## True while the room is moving furniture to fit the session, so those moves are not saved as
## if this participant had pushed everything.
var _fitting := false
var _patch_cabinet: MeshInstance3D
var _patch_cheeks: Array[MeshInstance3D] = []

## Where a person stands to work, on a monitor. Far enough forward of the console's home at
## z = 0.1 that gear summoned to arm's length lands on the desk rather than through it.
const MIX_POSITION_Z := 0.66
## Where the opening view looks: (metres ahead of the mix position, height). Where a standing
## eye's half-radian glance lands on the console, kept for every other eye height.
const DESK_GAZE := Vector2(0.96, 1.096)

## Vertical field of view, in degrees: wide enough to take in a room, long enough to work at a
## desk without the near edge of it bowing away from you.
## The lens for looking AT the room, as against being seated at one thing in it. Named rather
## than written twice, because it was written twice -- 58 where the camera is set up and 75
## where focus is released -- and releasing focus quietly widened the room by seventeen
## degrees every time.
const ROOM_FOV := 58.0
const SEATED_FOV := 54.0
## Roughly what a headset shows vertically. Not a lens anyone sets -- the runtime owns the
## projection -- but surfaces still need a number to size themselves against, and the visor's
## own field is the honest one.
const HEADSET_FOV := 95.0

## You, on foot. The default way to be in the room on a monitor; see walker.gd.
var walker: Walker
## The orbit camera instead of the walker: floats, flies, passes through things. For arranging a
## room and for photographing it. N toggles it.
var god_mode := false
var _orbit_yaw := 0.0
var _orbit_pitch := -0.18
var _orbit_distance := 2.05
var _orbit_target := Vector3(0, 0.92, 0)


func _ready() -> void:
	# A rack unit's words (✕ REMOVE's) are the room's notices.
	RackUnit.say = func(words: String) -> void: Session.notice.emit(words)
	_build_environment()
	# In AR the room is already there -- it is the one the participant is standing in. Drawing a
	# virtual floor over a real one is not a smaller version of the VR experience, it is a worse
	# one: it hides the actual floor and it disagrees with it by however much calibration is off.
	if medium != Presentation.Medium.AR:
		if Session.layout != null:
			set_venue(Session.layout.venue, false, Session.layout.venue_variant)
		else:
			set_venue(Venue.IDS[0], false)
	_build_anchors()
	if medium != Presentation.Medium.AR:
		_build_furniture()
	_build_surfaces()
	_build_point_and_mark()
	if camera != null:
		_build_walker()
		_update_camera()
	if medium != Presentation.Medium.AR:
		_build_items()
		_build_tour_case()
		_build_rig_roulette_station()
	else:
		# AR's room is the player's own real one: of the room's items, only the drum pads' kit on the
		# desk's rail, which plays there as anywhere (docs/spatial_loop.md part two, slice 41).
		_build_items()
	_build_pads()
	if medium == Presentation.Medium.AR and xr_bootstrap != null:
		# Now, and not in XRBootstrap.start(): the environment it has to clear is the one built
		# four lines up.
		xr_bootstrap.apply_passthrough()


func _build_environment() -> void:
	world_env = WorldEnvironment.new()
	world_env.environment = _house_environment()
	add_child(world_env)
	if rich_rendering():
		_tune_renderer()

	# Key light from above and in front, as a studio's ceiling panel would be. Shadows are what
	# seat the gear on the desk rather than leaving it floating a centimetre above it.
	key_light = DirectionalLight3D.new()
	key_light.name = "Key"
	_house_key(key_light)
	add_child(key_light)

	# The practicals, the lamps an actual control room has. They also give the metal something to
	# catch: brushed aluminium under a single light source reads as flat grey. The stands that
	# hold them up are furniture and are built there, because an AR participant has real lamps
	# in a real room and needs these to light the virtual gear without appearing in front of him.
	for spec in PRACTICALS:
		var lamp := OmniLight3D.new()
		lamp.position = spec[0]
		lamp.light_color = spec[1]
		lamp.light_energy = spec[2]
		lamp.omni_range = LAMP_RANGE
		lamp.shadow_enabled = false
		if rich_rendering():
			# Soft, contact-hardening shadows from a bulb the size of a bulb. A lamp that lights
			# gear without shadowing it is what made everything look pasted onto the room.
			lamp.shadow_enabled = true
			lamp.light_size = 0.06
			lamp.shadow_bias = 0.04
			lamp.shadow_normal_bias = 1.0
			lamp.light_volumetric_fog_energy = 0.6
		add_child(lamp)
		_lamps.append(lamp)


## The environment every venue starts from, and the one an AR participant keeps.
func _house_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.021, 0.024, 0.030)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.20, 0.23, 0.30)
	# Dropped from 0.58 when the third practical went in. Ambient is what fills the room rather
	# than the work, so it is the first thing to come down when more lamps are added: the
	# alternative is a room where the empty floor reads as brightly as the console.
	env.ambient_light_energy = 0.46

	# Glow is load-bearing, not a filter. Every LED, meter segment and lamp in this project is an
	# emissive material above 1.0, and without a glow pass they are merely slightly brighter
	# paint -- a muted channel and an unmuted one become almost the same picture.
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 4.0
	env.ssao_enabled = true
	env.ssao_radius = 0.4
	env.ssao_intensity = 1.4
	if standalone_headset():
		# The mobile renderer has no SSAO, and a glow pass is a full-frame blur twice per eye.
		env.ssao_enabled = false
		env.glow_enabled = false
	return env


func _house_key(key: DirectionalLight3D) -> void:
	key.light_energy = 1.05
	key.light_specular = 1.0
	key.light_color = Color(0.92, 0.94, 1.0)
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-62, 18, 0)
	# Fitted to the room, not to the default hundred metres. A directional shadow map is spread
	# over its whole distance, so at 100m every texel was several centimetres across -- coarser
	# than a fader cap -- and the shadows of everything small on the desk shimmered as the
	# camera moved. It reads as z-fighting and it is not; it is a shadow map looking at a
	# console from the far side of a football pitch.
	key.directional_shadow_max_distance = 9.0
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	key.directional_shadow_blend_splits = true
	key.shadow_normal_bias = 1.2
	key.shadow_bias = 0.03
	key.light_angular_distance = 1.2
	key.shadow_blur = 1.0
	key.light_color = Color(0.92, 0.94, 1.0)
	key.rotation_degrees = Vector3(-62, 18, 0)
	key.shadow_enabled = true
	if standalone_headset():
		# Four cascades drawn for two eyes is the Quest's whole frame.
		key.shadow_enabled = false


## Renderer-wide settings for the desktop: shadow resolution and filtering, antialiasing. Not
## per venue -- these are about the machine, not the scenery.
func _tune_renderer() -> void:
	RenderingServer.directional_shadow_atlas_set_size(8192, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
			RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	RenderingServer.positional_soft_shadow_filter_set_quality(
			RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	var view := get_viewport()
	if view != null:
		view.positional_shadow_atlas_size = 8192
		view.msaa_3d = Viewport.MSAA_4X
		view.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
		view.use_debanding = true


## Stand the studio somewhere else. The gear, the furniture, where it has all been pushed and
## what is focused are untouched; the floor, the sky, the air and the light change.
##
## `persist` false for a venue asked for on the command line, which is a look for one run and
## not a change of mind.
## What rides in front of your face in screen mode is seen, never reflected: in a mirror it
## would be the backs of the panels, over your own face. Whatever moves back into the room is
## reflected again. See core/venues/mirror.gd.
func _keep_out_of_mirrors(node: Node) -> void:
	var drawn := node as VisualInstance3D
	if drawn == null or screen_stage == null or not is_instance_valid(screen_stage):
		return
	if screen_stage.is_ancestor_of(drawn):
		# Bit by bit rather than the whole mask: the big board's feed marks what it shows with a
		# layer of its own (BoardFeed.ON_BOARD), which this must leave alone.
		if drawn.layers & 1:
			drawn.layers = (drawn.layers & ~1) | Mirror.NOT_REFLECTED
			drawn.set_meta(&"kept_out_of_mirrors", true)
	elif drawn.has_meta(&"kept_out_of_mirrors"):
		drawn.layers = (drawn.layers & ~Mirror.NOT_REFLECTED) | 1
		drawn.remove_meta(&"kept_out_of_mirrors")


func _exit_tree() -> void:
	if hit_voices != null:
		hit_voices.stop()
		hit_voices = null
	if _seat_finder != null:
		_seat_finder.free()
		_seat_finder = null
	mic_arm.let_go()
	Ears.lean(0)
	Ears.listen(false)
	if DAW.backend is GodotBackend:
		(DAW.backend as GodotBackend).set_cues([])
		(DAW.backend as GodotBackend).set_taps([])
	if get_tree().node_added.is_connected(_keep_out_of_mirrors):
		get_tree().node_added.disconnect(_keep_out_of_mirrors)


func set_venue(id: StringName, persist := true, variant := 0) -> void:
	if medium == Presentation.Medium.AR:
		return
	if not Venue.is_known(id):
		id = Venue.IDS[0]
	if venue != null:
		remove_child(venue)
		venue.queue_free()
	venue = Venue.make(id, variant)
	venue.name = "Venue"
	# The rows that are the venue's own (its instrument's) say this one's from now on.
	Stations.here = venue
	venue.rich = rich_rendering()
	venue.room_width = room_width
	var env := _house_environment()
	_house_key(key_light)
	venue.dress(env, key_light)
	if standalone_headset():
		env.glow_enabled = false
		env.ssao_enabled = false
		key_light.shadow_enabled = false
	Materials.apply_style(venue.gear_style())
	GearShape.use(id, venue.roll_board_chalky(), get_tree() if is_inside_tree() else null)
	TrackColours.use(venue.track_palette())
	_recolour_tracks()
	# Every venue a touch brighter than it dressed itself: the mid-tones read dark on an ordinary
	# monitor, AgX's above all. Exposure rather than brightness, so blacks stay black.
	env.tonemap_exposure *= EXPOSURE_LIFT
	world_env.environment = env
	add_child(venue)
	_hang_the_roulette_door()
	# Before anything stands at its spot: the spots of what is wheeled about are its trolley's.
	_wheel_in_live_pieces()
	_stand_the_harp()
	_stand_the_wheel()
	_stand_the_sections()
	_stand_the_ledge()
	_stand_the_cassette_rack()
	_stand_the_sampler()
	_stand_the_drum_circle()
	_stand_the_looper()
	_stand_the_music_box()
	_stand_the_spool()
	_stand_the_theremin()
	_stand_the_grains()
	_stand_the_marbles()
	_stand_the_lyrics()
	_stand_the_venue_instrument()
	_stand_the_modular()
	_stand_the_weather()
	_hang_hood_signs()
	var mirror := venue.make_mirror(env)
	venue.add_child(mirror)
	_stand_a_patch_wall()
	_set_levels_niche()
	_set_tv_mount()
	# The venue built its shelf and hoop where their trolleys stood in the last one.
	_carry_all_live()
	mirror.wardrobe.look = Session.local_look
	mirror.wardrobe.look_changed.connect(Session.set_look)
	_relight()
	if persist and Session.layout != null and Session.is_authority():
		Session.layout.venue = id
		Session.layout.venue_variant = venue.variant
		Session.layout.save()
	_walk_where_the_venue_lets()
	venue_changed.emit(id)
	_publish_room()


## Rig Roulette is switched off for now (the door, the room and the roll): the code is all here,
## and DAWLINGS_ROULETTE=1 turns it back on for working on it.
static var roulette_enabled := OS.get_environment("DAWLINGS_ROULETTE") == "1"


## The door to (or, in the room itself, out of) Rig Roulette, in the venue's own frame. It is a
## child of the venue, so it goes with it; the venue's own `solids` keep people out of it and the
## floor plan keeps furniture out of it (`_door_footprint`).
func _hang_the_roulette_door() -> void:
	if not roulette_enabled:
		return
	var door := RouletteDoor.new()
	door.name = "RouletteDoor"
	door.leaving = in_roulette_room_venue(venue)
	door.transform = venue.rig_roulette_door()
	door.used.connect(_on_roulette_door_used)
	venue.add_child(door)


## The chord harp, in the venue's own frame at its spot: a child of the venue, so it goes with
## it, and the venue's `solids` keep people out of it. Whatever the old one still had ringing
## was let go as it went (`_exit_tree`).
func _stand_the_harp() -> void:
	harp = ChordHarp.new()
	harp.transform = Stations.spot(venue, &"harp")
	venue.add_child(harp)
	if presence != null:
		presence.harp = harp
	# The handbells' stand beside it (the bells themselves are items: their homes are its seats).
	_bell_stand = HandbellItem.stand()
	_bell_stand.transform = Stations.spot(venue, &"bells")
	venue.add_child(_bell_stand)


## The fifths wheel, in the venue's own frame on the bricks table: a child of the venue, so it
## goes with it. Each player's is their own (its key and strip); what SET writes is the song's.
## None in a venue with no bricks table.
func _stand_the_wheel() -> void:
	wheel = null
	var spot: Variant = Stations.spot(venue, &"wheel")
	if spot == null:
		return
	wheel = FifthsWheel.new()
	wheel.transform = FifthsWheel.on_stand(spot)
	wheel.brick_pulled.connect(_on_brick_pulled)
	wheel.bricks_made.connect(make_bricks)
	venue.add_child(wheel)


## The section blocks, in the venue's own frame on the bricks table, past the wheel: a child of the
## venue, so they go with it. What they show and rearrange is the song's regions. None in a venue
## with no bricks table.
func _stand_the_sections() -> void:
	sections = null
	var spot: Variant = Stations.spot(venue, &"sections")
	if spot == null:
		return
	sections = SectionBlocks.new()
	sections.transform = spot
	venue.add_child(sections)


## The chord ledge, in the venue's own frame on the bricks table, along its near edge: a child of
## the venue, so it goes with it. Its slots are the room's holder ChordBrick.LEDGE and its bin
## ChordBrick.BIN (`_hold_the_ledge`). None in a venue with no bricks table.
func _stand_the_ledge() -> void:
	ledge = null
	var spot: Variant = Stations.spot(venue, &"ledge")
	if spot == null:
		return
	ledge = ChordLedge.new()
	ledge.transform = spot
	ledge.items = items
	venue.add_child(ledge)


## The cassette rack, in the venue's own frame beside the prop shelf: a child of the venue, so it
## goes with it. Its slots are the room's holder RACK and its bin BIN (`_hold_the_rack`).
func _stand_the_cassette_rack() -> void:
	cassette_rack = null
	var spot: Variant = Stations.spot(venue, &"cassette_rack")
	if spot == null:
		return
	cassette_rack = CassetteRack.new()
	cassette_rack.transform = spot
	cassette_rack.items = items
	venue.add_child(cassette_rack)


## The sampler, in the venue's own frame beside the cassette rack: a child of the venue, so it goes
## with it. REC is the room's (`sampler`), kept across a change of venue.
func _stand_the_sampler() -> void:
	var was := sampler.armed_by if sampler != null and is_instance_valid(sampler) else 0
	sampler = null
	var spot: Variant = Stations.spot(venue, &"sampler")
	if spot == null:
		return
	sampler = Sampler.new()
	sampler.transform = spot
	sampler.items = items
	sampler.authority = Session.is_authority
	sampler.local_peer = func() -> int: return Session.local_peer_id
	sampler.name_of = Session.name_of
	sampler.armed_by = was
	sampler.rec_pressed.connect(_on_rec_pressed)
	sampler.told.connect(func(peer: int, text: String) -> void: Session.tell(peer, text))
	sampler.armed_changed.connect(_publish_room_soon)
	venue.add_child(sampler)


## The circle of hand drums' plaque, in the venue's own frame at the ring's middle on the drum riser:
## a child of the venue, so it goes with it. The drums themselves are the room's items, whose homes
## are their places round it (`_item_homes`). None in a venue with no riser.
func _stand_the_drum_circle() -> void:
	drum_circle = null
	var spot: Variant = Stations.spot(venue, &"drums")
	if spot == null:
		return
	drum_circle = Node3D.new()
	drum_circle.name = "DrumCircle"
	drum_circle.transform = spot
	var plaque := Stations.plaque(&"drums", Stations.DRUM_PLAQUE_WIDTH)
	plaque.transform = Transform3D(Basis(Vector3.RIGHT, -Stations.DRUM_PLAQUE_TILT), Stations.DRUM_PLAQUE)
	drum_circle.add_child(plaque)
	# A slim post under it, so it stands on the riser rather than hanging in the air.
	var post := MeshInstance3D.new()
	post.name = "Post"
	var rod := CylinderMesh.new()
	rod.top_radius = 0.012
	rod.bottom_radius = 0.018
	rod.height = Stations.DRUM_PLAQUE.y - 0.02
	post.mesh = rod
	post.position = Vector3(0, rod.height * 0.5, Stations.DRUM_PLAQUE.z - 0.03)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.1, 0.1, 0.11)
	metal.roughness = 0.4
	metal.metallic = 0.8
	post.material_override = metal
	drum_circle.add_child(post)
	venue.add_child(drum_circle)


## The looper (Looper), in the venue's own frame at the drum riser's front corner: a child of the venue,
## so it goes with it. Its row is the room's (`looper_row`) and LENGTH this player's (`looper_length`);
## a layer it was taking down here carries over to the new one. Its rings (LooperRings) are the mix's
## LOOPER folder, so they stand again with it. None in a venue with no riser.
func _stand_the_looper() -> void:
	var was := looper if looper != null and is_instance_valid(looper) else null
	looper = null
	var spot: Variant = Stations.spot(venue, Looper.STATION)
	if spot == null:
		if was != null and was.mine():
			_on_looper_called_off()
		return
	looper = Looper.new()
	looper.transform = spot
	looper.local_peer = func() -> int: return Session.local_peer_id
	looper.name_of = _looper_name
	looper.length = looper_length
	looper.row = looper_row
	if was != null:
		looper.take_over(was)
	looper.slapped.connect(_on_looper_slapped)
	looper.length_changed.connect(func(bars: int) -> void: looper_length = bars)
	looper.layer_done.connect(_on_looper_layer)
	looper.called_off.connect(_on_looper_called_off)
	venue.add_child(looper)
	# Its layers' rings (slice 46) say what a grab, a click or a pull did, as a toast.
	looper.rings.told.connect(func(text: String) -> void: Session.notice.emit(text))


## The music box (MusicBox), in the venue's own frame at its spot beside the harp: a child of the venue,
## so it goes with it, its trolley the studio's. Its row is the room's (`music_box_row`); its pegs are
## its track's item in the mix, so they stand again with it. None where there are no zones.
func _stand_the_music_box() -> void:
	music_box = null
	var spot: Variant = Stations.spot(venue, MusicBox.STATION)
	if spot == null:
		return
	music_box = MusicBox.new()
	music_box.transform = spot
	music_box.row = music_box_row
	music_box.row_asked.connect(_on_music_box_asked)
	music_box.told.connect(func(text: String) -> void: Session.notice.emit(text))
	venue.add_child(music_box)


## The theremin (Theremin), in the venue's own frame at its spot in front of the drum riser: a child of
## the venue, so it goes with it, its trolley the studio's. Its notes are this player's keys; its
## SCALE switch is theirs too, and goes from one venue's theremin to the next. None where there are
## no zones.
func _stand_the_theremin() -> void:
	if theremin != null and is_instance_valid(theremin):
		theremin_snap = theremin.snap
	theremin = null
	var spot: Variant = Stations.spot(venue, Theremin.STATION)
	if spot == null:
		return
	theremin = Theremin.new()
	theremin.transform = spot
	theremin.snap = theremin_snap
	venue.add_child(theremin)


## The grain cloud (GrainCloud), in the venue's own frame at its spot in the aisle: a child of the venue,
## so it goes with it, its trolley the studio's. Its bowl is the room's holder `bowl` (`_hold_the_bowl`);
## its KEY switch the room's row `grains_key`. What it plays is this player's alone. None where there are
## no zones.
func _stand_the_grains() -> void:
	grain_cloud = null
	var spot: Variant = Stations.spot(venue, GrainCloud.STATION)
	if spot == null:
		if items != null:
			items.holders.erase(GrainCloud.HOLDER)
		return
	grain_cloud = GrainCloud.new()
	grain_cloud.transform = spot
	grain_cloud.find_file = _platter_file
	grain_cloud.fetching = func(source: String) -> bool:
		return Session.role == Session.Role.GUEST and Session.files != null \
				and Session.files.fetch_state(source) == FileSend.FETCHING
	grain_cloud.key_on = grains_key
	grain_cloud.key_pressed.connect(_on_grains_key_pressed)
	# Slice 55: each event played goes to the band and into a take, stamped with the song as this
	# player hears it; a bandmate's are played here from the same sound; and the host renders a take
	# from this cloud's sound.
	grain_cloud.played.connect(_on_grains_played)
	if not Session.participant_left.is_connected(_forget_grains_player):
		Session.participant_left.connect(_forget_grains_player)
	Session.grain_takes.sound = grains_sound
	venue.add_child(grain_cloud)
	_hold_the_bowl()


## The venue's own instrument's mount (VenueInstrument), in the venue's own frame at its spot: a child
## of the venue, so it goes with it, its plaque and the set's jack on it. Its bars are the room's
## items, dressed as its set here (`_dress_venue_bars`) and at home on it (`_item_homes`). None in a
## venue with no instrument, whose bars are put away.
func _stand_the_venue_instrument() -> void:
	venue_instrument = null
	var spec := VenueInstrument.spec_of(venue)
	if not spec.is_empty():
		venue_instrument = VenueInstrument.new(spec)
		venue_instrument.transform = spec["spot"]
		venue.add_child(venue_instrument)
	_dress_venue_bars()


## The venue's weather (Weather), in the venue's own frame at its switch's spot: a child of the venue,
## so it goes with it. Its switch is the room's (`weather_listening`). None in an arrangement with no
## weather.
func _stand_the_weather() -> void:
	weather = null
	var spec := Weather.spec_of(venue)
	if spec.is_empty():
		return
	weather = Weather.new(spec, Weather.seed_of(venue.venue_id()))
	weather.transform = spec["spot"]
	weather.listening = weather_listening
	weather.switch_pressed.connect(_on_weather_pressed)
	weather.dropped.connect(_on_weather_dropped)
	venue.add_child(weather)


## The room's venue bars dressed as this venue's set, the first of them its count, for the mount to
## brush across: before their homes are stood (ItemRoom.set_spots), so each stands in its own look.
func _dress_venue_bars() -> void:
	if items == null or venue_instrument == null or not is_instance_valid(venue_instrument):
		return
	venue_instrument.bars = VenueInstrument.dress(items, venue_instrument.spec)


## The rack's slots and bin as the room's holders, and each made item's home its tray, in the
## room's frame (the venue's, as the shelf's spots are).
func _hold_the_rack() -> void:
	if items == null:
		return
	if cassette_rack == null or not is_instance_valid(cassette_rack):
		items.holders.clear()
		_hold_the_platter()
		_hold_the_ledge()
		_hold_the_bowl()
		return
	cassette_rack.items = items
	if sampler != null and is_instance_valid(sampler):
		sampler.items = items
	var at := cassette_rack.transform
	items.set_holder(CassetteRack.RACK, CassetteRack.slots_in(at))
	var bin: Array[Transform3D] = [at * CassetteRack.bin_pose()]
	items.set_holder(CassetteRack.BIN, bin)
	for id in items.made_ids():
		var item: Item = items.items[id]
		item.home = _made_home(ItemRoom.kind_of(id), int(String(id).trim_prefix(String(ItemRoom.kind_of(id)))))
		if item.state == Item.State.HOME:
			item.snap_home()
	_hold_the_platter()
	_hold_the_ledge()
	_hold_the_bowl()


## The ledge's slots and its bin as the room's holders (slice 31), where the bricks table has it; a
## venue with none has neither, and a brick that stood in it goes to its home.
func _hold_the_ledge() -> void:
	if items == null:
		return
	if ledge == null or not is_instance_valid(ledge):
		items.holders.erase(ChordBrick.LEDGE)
		items.holders.erase(ChordBrick.BIN)
		for id in items.made_ids():
			var item: Item = items.items[id]
			if item.slot_in == ChordBrick.LEDGE:
				item.snap_home()
		return
	ledge.items = items
	var at := ledge.transform
	items.set_holder(ChordBrick.LEDGE, ChordLedge.slots_in(at))
	var bin: Array[Transform3D] = [at * ChordLedge.bin_pose()]
	items.set_holder(ChordBrick.BIN, bin)
	for id in items.made_ids():
		var item: Item = items.items[id]
		if not (item is ChordBrick):
			continue
		item.home = _made_home(ChordBrick.KIND, int(String(id).trim_prefix(String(ChordBrick.KIND))))
		if item.state == Item.State.HOME:
			item.snap_home()


## The platter's slot as a holder, where the deck cart stands now (slice 27): again whenever the
## cart is pushed, so a cassette stood in it rides with it.
func _hold_the_platter() -> void:
	if items == null or platter == null or not is_instance_valid(platter):
		return
	platter.items = items
	if deck_trolley == null or not is_instance_valid(deck_trolley):
		return
	var at: Array[Transform3D] = [deck_trolley.transform * Platter.ON_CART * Platter.SLOT_POSE]
	items.set_holder(Platter.HOLDER, at)


## The grain cloud's bowl as a holder of one slot (slice 54), in the room's frame (the venue's), where
## the cloud stands now: again whenever its trolley is pushed, so a cassette in it rides with it.
func _hold_the_bowl() -> void:
	if items == null or grain_cloud == null or not is_instance_valid(grain_cloud):
		return
	grain_cloud.items = items
	var at: Array[Transform3D] = [grain_cloud.slot_in(grain_cloud.transform)]
	items.set_holder(GrainCloud.HOLDER, at)


## Where made item number `n` lies with nowhere else to be: the rack's tray; a chord brick, the
## ledge's tray behind its rail.
func _made_home(kind: StringName, n: int) -> Transform3D:
	if kind == ChordBrick.KIND and ledge != null and is_instance_valid(ledge):
		return ledge.transform * ChordLedge.tray_spot(n)
	if cassette_rack == null or not is_instance_valid(cassette_rack):
		return venue.prop_shelf_spot() if venue != null else Transform3D.IDENTITY
	return cassette_rack.transform * CassetteRack.tray_spot(n)


## The wheel in this player's reach (`&"wheel"` in GuestMidi.instruments) while a hand of theirs
## is on it or over it, or a chord pressed on it still sounds: so the synth is up before the
## first press, and a run of presses is one take.
func _follow_wheel() -> void:
	if Session.guest_midi == null:
		return
	var near := wheel != null and is_instance_valid(wheel) and wheel.is_inside_tree() \
			and (wheel.touched() or wheel.sounding())
	Session.guest_midi.reach(FifthsWheel.SOURCE, near)


## The harp in this player's reach (`&"harp"` in GuestMidi.instruments) while they stand near
## it, a hand of theirs is on it or over it, or a string they plucked still rings: so the synth
## is up before the first pluck, and the strums with gaps between them are one take.
func _follow_harp() -> void:
	if Session.guest_midi == null:
		return
	var near := false
	if harp != null and is_instance_valid(harp) and harp.is_inside_tree():
		var me := _standing_at()
		var at := harp.global_position
		near = harp.touched() or harp.ringing() \
				or Vector2(me.x - at.x, me.z - at.z).length() < ChordHarp.NEAR
	Session.guest_midi.reach(ChordHarp.SOURCE, near)


## Where this player stands, in global space: the walker on a desktop, the head in a headset.
func _standing_at() -> Vector3:
	if walker != null and walker.is_inside_tree():
		return walker.global_position
	if rig != null and rig.head != null and rig.head.is_inside_tree():
		return rig.head.global_position
	if camera != null and camera.is_inside_tree():
		return camera.global_position
	return Vector3(0, 0, 1e6)


static func in_roulette_room_venue(v: Venue) -> bool:
	return v != null and v.venue_id() == Venue.ROULETTE_ID


## The door was used: the host takes the band through it, the way it points. A guest is told whose
## call it is (the enter and leave asks say so themselves).
func _on_roulette_door_used() -> void:
	if in_roulette_room():
		leave_roulette_room()
	else:
		enter_roulette_room()


## What furniture keeps clear of: the door's footprint, as the floor plan's rectangles.
func _door_footprint() -> Array:
	if venue == null or not roulette_enabled:
		return []
	var door := venue.door_solid()
	return [FloorPlan.footprint(door["c"], door["h"], door["a"])]


## The audio patch wall in every venue: where a venue has hung one (the studio's side room), that
## is the one; anywhere else it stands on two legs, at a little over half the size of the room's
## own: the legs are a trolley (`live_pieces`' "patch_wall"), pushed about like the rest of the
## gear, and the screen goes where they are. By default against the control room's left side,
## turned to face the desk (`_patch_wall_default`).
func _stand_a_patch_wall() -> void:
	if venue.get_node_or_null("PatchWall") != null:
		return
	var wall := PatchWallSurface.new()
	wall.name = "PatchWall"
	wall.set_meta(&"on_legs", true)
	wall.transform = _patch_wall_frame()
	wall.follow = DisplayServer.get_name() != "headless"
	venue.add_child(wall)


## The screen on the legs, its top PATCH_WALL_TOP over them, in the venue's frame.
const PATCH_WALL_SCALE := 0.55
const PATCH_WALL_TOP := 2.2
## The legs: how far either side of the middle, and how far behind the screen's face.
const PATCH_WALL_LEG_X := 1.3
const PATCH_WALL_LEG_Z := -0.04


func _patch_wall_frame() -> Transform3D:
	var legs: Trolley = live_pieces.get(&"patch_wall")
	var at := legs.transform if legs != null else _patch_wall_default()
	return _set_to_venue(at) * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * PATCH_WALL_SCALE),
			Vector3(0, PATCH_WALL_TOP, 0))


## Where the legs stand until they are pushed: 55 cm off the control room's left wall, a little
## behind the desk's left end, facing across the room.
func _patch_wall_default() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-room_width * 0.5 + 0.55, 0, -1.5))


## The practicals back to the venue's own colour and energy, and the venue's own house lights
## back on (`Venue.blackout(false)`) -- `set_venue`'s own tail, factored out so a chaos event's
## blackout (`_lights_out`) has somewhere to put the room back, however it found it: a run
## ending mid-dark, or a second strike landing before the first one's `_relight` fired.
func _relight() -> void:
	for i in _lamps.size():
		if i < PRACTICALS.size():
			_lamps[i].light_color = venue.lamp_colour(i, PRACTICALS[i][1])
			_lamps[i].light_energy = venue.lamp_energy(i, PRACTICALS[i][2])
	if venue != null:
		venue.blackout(false)


## The room hearing a clip, one frame: the master or any heard track over 0 dBFS lights its OVER
## lamp (MasterSection.show_over, ChannelStrip.show_over) and lifts the practicals (Venue.hear_clip,
## at most once every Venue.FLASH_GAP). A chaos event's flicker or blackout has the lamps meanwhile.
func follow_clip(delta: float) -> void:
	var master_over := MasterSection.clipping(SignalBeads.master_level())
	var any := master_over
	var over := {}
	# Every track, in no order, each asked in constant time (SignalBeads.heard): a frame of this
	# on a ninety-track desk is ninety looks, not ninety sorts.
	for index in DAW.state.tracks:
		if MasterSection.clipping(SignalBeads.track_level(index)):
			over[index] = true
			any = true
	if console != null:
		if console.master != null:
			console.master.show_over(master_over, delta)
		for strip in console.strips:
			if is_instance_valid(strip):
				strip.show_over(over.has(strip.track_index), delta)
	venue.hear_clip(any, delta)
	lift_lamps(venue.lift)


## The practicals at their venue's energy, `by` (a share) above it. Left alone while a chaos
## event's tween has them, and written only when it changes.
func lift_lamps(by: float) -> void:
	if _lights_tween != null and _lights_tween.is_valid() and _lights_tween.is_running():
		return
	if is_equal_approx(by, _lamps_lifted):
		return
	_lamps_lifted = by
	for i in _lamps.size():
		if i < PRACTICALS.size():
			_lamps[i].light_energy = venue.lamp_energy(i, PRACTICALS[i][2]) * (1.0 + by)


## `power_flicker`'s telegraph: the practicals dip to a sixth and back, twice, fast -- a flicker
## you feel coming, not a cut you only notice after. `_lights_tween` is the one tween either this
## or `_lights_out` ever runs, killed first so the two can never fight over the same lamps.
func _flicker_lights() -> void:
	if _lamps.is_empty():
		return
	if _lights_tween != null:
		_lights_tween.kill()
	var base: Array[float] = []
	for lamp in _lamps:
		base.append(lamp.light_energy)
	_lights_tween = create_tween()
	for _k in 2:
		_lights_tween.set_parallel(true)
		for i in _lamps.size():
			_lights_tween.tween_property(_lamps[i], "light_energy", base[i] / 6.0, 0.08)
		_lights_tween.chain().set_parallel(true)
		for i in _lamps.size():
			_lights_tween.tween_property(_lamps[i], "light_energy", base[i], 0.08)
		_lights_tween.chain()


## `power_flicker`'s strike: the practicals die, the venue's own house lights with them
## (`Venue.blackout(true)`), for one bar -- then `_relight` brings both back however the run has
## left them (a leaver, a second strike), rather than assuming anything about where this one
## found them.
func _lights_out(seconds: float) -> void:
	if _lights_tween != null:
		_lights_tween.kill()
	_lights_tween = create_tween()
	_lights_tween.set_parallel(true)
	for lamp in _lamps:
		_lights_tween.tween_property(lamp, "light_energy", 0.0, 0.12)
	if venue != null:
		venue.blackout(true)
	_lights_tween.chain().tween_callback(_relight).set_delay(seconds)


## On foot you can go where the room goes: the working footprint and, behind it, the venue's
## live room with its zones. The furniture's floor plan is still the footprint alone.
func _walkable() -> Array[Rect2]:
	var out: Array[Rect2] = [_room_bounds()]
	if venue != null:
		out.append_array(venue.rooms())
	return out


func _walk_where_the_venue_lets() -> void:
	if walker != null:
		walker.walkable = _walkable()
		walker.fixed = venue.solids() if venue != null else []
		walker.rebuild_walls()
		walker.unstick()
	if items != null and venue != null:
		items.boards = venue.dart_boards()
		items.hoops = venue.hoops()
		items.set_venue(venue.venue_id())
		items.set_spots(venue.item_spots(), _item_homes())
	_hold_the_rack()
	if tour_case != null and venue != null:
		tour_case.transform = _venue_to_set(venue.tour_case_spot())
		_rehome_spills()


## Somewhere else to stand, if this is somebody's to say: the room is the host's, so a guest
## asking is told so rather than taken somewhere nobody else is.
## How tall you are, changed in the room: the eye goes there at once and the height is kept
## for next time. The gear stays where it is -- it is the room's, and you are the one who grew.
func set_body_height(height: float) -> void:
	ergonomics.set_height(height)
	Ergonomics.save_height(ergonomics.height, body_path)
	if walker != null:
		walker.standing_eye = ergonomics.eye_height
		walker.eye_height = ergonomics.eye_height
		walker._place_camera()
	if body != null and medium == Presentation.Medium.SCREEN:
		body.position.y = ergonomics.eye_height


func choose_venue(id: StringName, variant := 0) -> bool:
	if not Session.is_authority():
		Session.notice.emit("Only %s can change the venue." % Session.name_of(1))
		return false
	set_venue(id, true, variant)
	return true


## Where the band was before the Rig Roulette room took them: {"id", "variant"}, or empty.
var _before_the_room := {}


func in_roulette_room() -> bool:
	return venue != null and venue.venue_id() == Venue.ROULETTE_ID


## The host takes the whole band into the Rig Roulette room. It is a place, not a venue: it is
## not saved as the room's venue (a restart opens the venue it was left from), and it reaches
## guests the way a venue does, through the room the host publishes. Remembers the venue and its
## arrangement for `leave_roulette_room`.
func enter_roulette_room() -> bool:
	if not roulette_enabled:
		return false
	if not Session.is_authority():
		Session.notice.emit("Only %s can take the band into the roulette room." % Session.name_of(1))
		return false
	if in_roulette_room() or venue == null:
		return false
	if Tour.run != null:
		Session.notice.emit("Not in the middle of a tour.")
		return false
	_before_the_room = {"id": venue.venue_id(), "variant": venue.variant}
	_rolls_this_visit = 0
	set_venue(Venue.ROULETTE_ID, false)
	return true


## And back out, to the venue and arrangement the band left, or the room's saved venue if this
## never saw them go in.
func leave_roulette_room() -> bool:
	if not Session.is_authority():
		Session.notice.emit("Only %s can take the band out of the roulette room." % Session.name_of(1))
		return false
	if not in_roulette_room():
		return false
	var id: StringName = _before_the_room.get("id", &"")
	var variant: int = _before_the_room.get("variant", 0)
	if not Venue.is_known(id) or id == Venue.ROULETTE_ID:
		id = Session.layout.venue if Session.layout != null and Venue.is_known(Session.layout.venue) \
				and Session.layout.venue != Venue.ROULETTE_ID else Venue.IDS[0]
		variant = Session.layout.venue_variant if Session.layout != null else 0
	_before_the_room = {}
	set_venue(id, false, variant)
	return true


## The same venue, arranged another way. The host's to choose, like the venue.
func choose_variant(variant: int) -> bool:
	return choose_venue(venue.venue_id() if venue != null else Venue.IDS[0], variant)


func cycle_venue() -> void:
	choose_venue(Venue.next_after(venue.venue_id() if venue != null else Venue.IDS[0]))


## Whether this participant gets the whole renderer: global illumination, screen-space
## reflections, volumetric light, soft shadows. A desktop does; a standalone headset runs the
## mobile renderer, which has none of it and must not be asked. Decided by what is actually
## running rather than by medium alone -- a desktop forced onto the compatibility renderer
## must fall back too.
func rich_rendering() -> bool:
	return medium == Presentation.Medium.SCREEN \
			and RenderingServer.get_current_rendering_method() == "forward_plus"


## A standalone headset: the mobile renderer, drawn twice a frame, with a mobile GPU to do it.
func standalone_headset() -> bool:
	return medium != Presentation.Medium.SCREEN and not rich_rendering()


## Furniture: the things that hold the gear up.
##
## Separate from the surfaces on purpose, and the line matters. A surface is DRIVEN BY REAPER --
## it exists because the project has tracks or plugins, and its size follows them. A stand is
## not; it is set dressing, it means nothing, and in ROOM mode it is not drawn at all because the
## participant already has real furniture. Mixing the two would mean a rack that cannot be put
## on the floor without inventing a plugin to justify its legs.
## One piece of furniture, as one node.
##
## The furniture used to be a flat heap of boxes under the set: four posts, a shelf, two legs,
## a crossbar, all siblings. That is fine to LOOK at and useless to move, and moving it is now
## required -- a surface summoned to the mix position lands exactly where the stand that used
## to hold it is still standing, and a trolley through the master section is the kind of thing
## no amount of lighting rescues. A rig can hide an assembly. It cannot hide half a trolley
## and leave the other two legs up.
func _assembly(of_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = of_name
	node.add_to_group(&"room_furniture")
	studio_set.add_child(node)
	return node


func _build_furniture() -> void:
	floor_plan = FloorPlan.new()
	floor_plan.name = "FloorPlan"
	floor_plan.bounds = _room_bounds()
	floor_plan.fixtures.append(_desk_footprint)
	floor_plan.fixtures.append(_door_footprint)
	add_child(floor_plan)

	_build_lamp_stands()
	# Before the board, whose rows are the stations standing here, the stage table among them.
	_build_stage_trolley()
	_build_eq_wall_trolley()
	_build_levels_niche()
	_build_tv_mount()
	_build_station_board()

	# A trolley for the deck. Two uprights and a shelf on a caster base; a tape machine on a
	# cart is what the right-hand side of a control room looks like, and it is the thing in
	# the room most often wheeled somewhere else.
	deck_trolley = _trolley("DeckTrolley", &"deck_trolley", Vector3(0.80, 0, -0.22), -32.0)
	deck_trolley.footprint_half = Vector2(0.28, 0.21)
	deck_trolley.follow = 10.0
	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(0.56, 0.025, 0.42)
	base.mesh = base_mesh
	base.position = Vector3(0, Caster.HEIGHT + 0.0125, 0)
	base.material_override = Materials.furniture()
	deck_trolley.add_part(base)
	var shelf := MeshInstance3D.new()
	var shelf_mesh := BoxMesh.new()
	shelf_mesh.size = Vector3(0.56, 0.04, 0.42)
	shelf.mesh = shelf_mesh
	shelf.position = Vector3(0, 0.86, 0)
	shelf.material_override = Materials.furniture()
	GearTrim.edges(shelf)
	deck_trolley.add_part(shelf)
	var post_bottom := Caster.HEIGHT + 0.025
	for dx in [-0.22, 0.22]:
		for dz in [-0.16, 0.16]:
			var post := MeshInstance3D.new()
			var post_mesh := BoxMesh.new()
			post_mesh.size = Vector3(0.03, 0.84 - post_bottom, 0.03)
			post.mesh = post_mesh
			post.position = Vector3(dx, (0.84 + post_bottom) * 0.5, dz)
			post.material_override = Materials.brushed_metal()
			deck_trolley.add_part(post)
	deck_trolley.add_corner_casters()
	_build_platter_leaf()
	# The board was made before the cart, and the platter on it is a station: its rows again.
	if station_board != null:
		station_board.set_venue(venue)
		_fit_board_stand()

	# A plinth under the rack. A floor-standing rack puts its lowest unit at ankle height; every
	# control room that has one has it up on something -- and here the something has wheels,
	# because a rack of outboard is the piece of a studio people actually push about.
	rack_trolley = _trolley("RackTrolley", &"rack", Vector3(-1.18, 0, -0.42), 38.0)
	rack_trolley.footprint_centre = Vector2(0, -0.15)
	rack_trolley.footprint_half = Vector2(0.30, 0.17)
	# Heavier than anything else on the floor. It is a cabinet full of steel.
	rack_trolley.follow = 7.5
	var plinth := MeshInstance3D.new()
	var plinth_mesh := BoxMesh.new()
	plinth_mesh.size = Vector3(0.60, 0.30 - Caster.HEIGHT, 0.34)
	plinth.mesh = plinth_mesh
	plinth.position = Vector3(0, (0.30 + Caster.HEIGHT) * 0.5, -0.15)
	plinth.material_override = Materials.furniture()
	GearTrim.edges(plinth)
	rack_trolley.add_part(plinth)
	rack_trolley.add_corner_casters(0.05)

	# A stand under the timeline, which until now hung in the air.
	#
	# It is the only thing in the room that did. The rack has a plinth, the deck a trolley, the
	# bay a bridge, the console its own carcass -- and then a metre of lit panel floating at
	# head height with nothing holding it. In a close-up that reads as a screen. In a wide shot
	# of the room it reads as the one object that is software, which is the single thing this
	# project is trying not to be.
	#
	# Two legs and a crossbar, deliberately the same vocabulary as the patch stand rather than
	# a new idea: a room furnished out of three kinds of part looks like a room, and one
	# furnished out of six looks like a kit. The feet are on casters, like a whiteboard's.
	timeline_stand = _trolley("TimelineStand", &"timeline_stand",
			Vector3(0, 0, TIMELINE_STAND_Z), 0.0)
	timeline_stand.footprint_half = Vector2(TIMELINE_LEG_X + 0.05, 0.11)
	var foot_top := Caster.HEIGHT + 0.022
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.035, TIMELINE_STAND_TOP - foot_top, 0.05)
		leg.mesh = leg_mesh
		leg.position = Vector3(side * TIMELINE_LEG_X, (TIMELINE_STAND_TOP + foot_top) * 0.5, 0)
		leg.material_override = Materials.furniture()
		timeline_stand.add_part(leg)

		# A foot, because a 35mm post standing on a floor is a post that fell over a moment ago.
		var foot := MeshInstance3D.new()
		var foot_mesh := BoxMesh.new()
		foot_mesh.size = Vector3(0.10, 0.022, 0.22)
		foot.mesh = foot_mesh
		foot.position = Vector3(side * TIMELINE_LEG_X, Caster.HEIGHT + 0.011, 0)
		foot.material_override = Materials.furniture()
		timeline_stand.add_part(foot)
		for end in [-0.075, 0.075]:
			timeline_stand.add_caster(Vector2(side * TIMELINE_LEG_X, end))

	var crossbar := MeshInstance3D.new()
	var crossbar_mesh := BoxMesh.new()
	crossbar_mesh.size = Vector3(TIMELINE_LEG_X * 2.0 + 0.07, 0.028, 0.04)
	crossbar.mesh = crossbar_mesh
	# Behind the panel, all of it: nine centimetres deep and centred on the legs, its front stood
	# out through the panel's face across the scrub rail, and seen from below it was a bright
	# slab cut into the bottom of the timeline.
	crossbar.position = Vector3(0, TIMELINE_STAND_TOP + 0.012,
			(TIMELINE_Z - TimelineSurface.DEPTH * TIMELINE_SCALE - 0.004 - 0.02) - TIMELINE_STAND_Z)
	crossbar.material_override = Materials.brushed_metal()
	timeline_stand.add_part(crossbar)

	_build_patch_stand()
	_build_live_pieces()


## The leaf off the deck cart's far end, away from the seat, at the shelf's height, on two posts
## and a foot with casters of its own, and the DJ platter on it (Platter.ON_CART, slice 27). The
## cart's footprint grows to take it in, so it is pushed, and stood clear of, as one piece.
func _build_platter_leaf() -> void:
	var leaf_x := Platter.ON_CART.origin.x
	var top := Platter.ON_CART.origin.y
	# From just under the shelf's end, a step below it, so the two never share a face.
	var leaf_from := Platter.LEAF_FROM
	var leaf_to := leaf_x + Platter.LEAF.x * 0.5
	var leaf := MeshInstance3D.new()
	leaf.name = "PlatterLeaf"
	var leaf_mesh := BoxMesh.new()
	leaf_mesh.size = Vector3(leaf_to - leaf_from, Platter.LEAF_THICK, Platter.LEAF.y)
	leaf.mesh = leaf_mesh
	leaf.position = Vector3((leaf_from + leaf_to) * 0.5, top - Platter.LEAF_THICK * 0.5, 0)
	leaf.material_override = Materials.furniture()
	GearTrim.edges(leaf)
	deck_trolley.add_part(leaf)
	var outer := leaf_x + Platter.LEAF.x * 0.5 - 0.03
	var post_bottom := Caster.HEIGHT + 0.025
	for dz in [-0.16, 0.16]:
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.03, top - Platter.LEAF_THICK - post_bottom, 0.03)
		post.mesh = post_mesh
		post.position = Vector3(outer, (top - Platter.LEAF_THICK + post_bottom) * 0.5, dz)
		post.material_override = Materials.brushed_metal()
		deck_trolley.add_part(post)
	var foot := MeshInstance3D.new()
	var foot_mesh := BoxMesh.new()
	foot_mesh.size = Vector3(0.06, 0.025, 0.42)
	foot.mesh = foot_mesh
	foot.position = Vector3(outer, Caster.HEIGHT + 0.0125, 0)
	foot.material_override = Materials.furniture()
	deck_trolley.add_part(foot)
	for dz in [-0.165, 0.165]:
		deck_trolley.add_caster(Vector2(outer, dz))
	# From the cart's near end to the leaf's far one.
	var near := -0.28
	var far := leaf_x + Platter.LEAF.x * 0.5
	deck_trolley.footprint_centre = Vector2((near + far) * 0.5, 0)
	deck_trolley.footprint_half = Vector2((far - near) * 0.5, maxf(0.21, Platter.LEAF.y * 0.5))
	platter = Platter.new()
	platter.transform = Platter.ON_CART
	platter.authority = Session.is_authority
	platter.find_file = _platter_file
	platter.fetching = func(source: String) -> bool:
		return Session.role == Session.Role.GUEST and Session.files != null \
				and Session.files.fetch_state(source) == FileSend.FETCHING
	platter.scratched.connect(_on_scratched)
	deck_trolley.add_child(platter)
	deck_trolley.moved.connect(_hold_the_platter)
	deck_trolley.settled.connect(_hold_the_platter)


## Where the stage table's trolley stands: beside the mix position on the right and a little
## behind it, turned to face it, clear of the deck trolley and the patch stand however wide the
## desk grows (the desk's footprint ends in front of the mix position, and these stand behind
## it). The top is desk height; the rail along its front drops RAIL below it. Far enough back
## that from the seat the right-hand lamp's foot is seen past its corner, not through it.
const STAGE_AT := Vector3(-2.3, 0, 2.3)
const STAGE_TOP := 0.74


## The stage table's trolley: four legs under an apron, a shelf low down, casters, and the
## table's plaque on its front under the rail (Stations.plaque). The table itself is a surface
## and rides it (`_ride`, in `_build_surfaces`).
func _build_stage_trolley() -> void:
	var at := Vector2(STAGE_AT.x, STAGE_AT.z)
	stage_trolley = _trolley("StageTrolley", &"stage_trolley", STAGE_AT, rad_to_deg(_facing_mix(at)))
	# The table and the rail along its front, on the floor.
	stage_trolley.footprint_centre = Vector2(0, 0.065)
	stage_trolley.footprint_half = Vector2(0.62, 0.53)
	stage_trolley.follow = 9.0
	var apron := MeshInstance3D.new()
	apron.name = "Apron"
	var apron_mesh := BoxMesh.new()
	apron_mesh.size = Vector3(1.12, 0.07, 0.82)
	apron.mesh = apron_mesh
	apron.position = Vector3(0, STAGE_TOP - StageTable.THICK - 0.035, 0)
	apron.material_override = Materials.furniture()
	GearTrim.edges(apron)
	stage_trolley.add_part(apron)
	var shelf := MeshInstance3D.new()
	shelf.name = "Shelf"
	var shelf_mesh := BoxMesh.new()
	shelf_mesh.size = Vector3(1.08, 0.025, 0.78)
	shelf.mesh = shelf_mesh
	shelf.position = Vector3(0, Caster.HEIGHT + 0.12, 0)
	shelf.material_override = Materials.furniture()
	stage_trolley.add_part(shelf)
	var leg_bottom := Caster.HEIGHT
	var leg_top := STAGE_TOP - StageTable.THICK - 0.07
	for dx in [-0.53, 0.53]:
		for dz in [-0.38, 0.38]:
			var leg := MeshInstance3D.new()
			var leg_mesh := BoxMesh.new()
			leg_mesh.size = Vector3(0.035, leg_top - leg_bottom, 0.035)
			leg.mesh = leg_mesh
			leg.position = Vector3(dx, (leg_top + leg_bottom) * 0.5, dz)
			leg.material_override = Materials.brushed_metal()
			stage_trolley.add_part(leg)
			stage_trolley.add_caster(Vector2(dx, dz))
	var plaque := Stations.plaque(&"stage_table")
	# Hung by its top edge, which is where a folded plaque's title and key row stay: low enough
	# under the rail that its title key is not in the way of the rail's tags from the seat.
	plaque.position = Vector3(0, STAGE_PLAQUE_TOP - float(plaque.get_meta(&"plaque_tall")) * 0.5,
			StageTable.SIZE.y * 0.5 + 0.135)
	stage_trolley.add_child(plaque)


## The plaque's top edge on the trolley's front, under the rail.
const STAGE_PLAQUE_TOP := 0.6


## Where the EQ wall's trolley stands: against the right-hand side wall in front of the deck, this
## far in from it, turned a little toward the mix position, clear of the deck's cart, the corner's
## lamp and the door to the Rig Roulette room in the front wall. Its x follows the wall out as the
## room widens (`_fit_room_to_session`).
## Off the wall and into the ring since the room grew: against an 11 m room's wall its handle was
## 5.5 px from the seat.
const EQ_WALL_IN := 1.9
const EQ_WALL_Z := -1.6
const EQ_WALL_HEADING := -74.0


func _eq_wall_at() -> Vector3:
	return Vector3(room_width * 0.5 - EQ_WALL_IN, 0, EQ_WALL_Z)


## The EQ wall's trolley: a plinth on casters and two uprights behind the board's edges, and the
## wall's plaque on the board's right-hand column, under SHOW (Stations.plaque, narrowed to the
## column). The board itself is a surface and rides it (`_ride`, in `_build_surfaces`).
func _build_eq_wall_trolley() -> void:
	eq_wall_trolley = _trolley("EqWallTrolley", &"eq_wall", _eq_wall_at(), EQ_WALL_HEADING)
	var wide := EqWall.PLATE_WIDE + EqWall.BORDER * 2.0
	eq_wall_trolley.footprint_centre = Vector2(0, -0.06)
	eq_wall_trolley.footprint_half = Vector2(wide * 0.5, 0.16)
	eq_wall_trolley.follow = 9.0
	# The uprights first: they are its handle, standing up over the deck's reels from the seat,
	# where the plinth at the floor is behind them (and is taken all the same).
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		post.name = "Upright"
		var post_mesh := BoxMesh.new()
		var high := EqWall.BOTTOM + EqWall.TALL + EqWall.BORDER
		post_mesh.size = Vector3(0.05, high - Caster.HEIGHT, 0.05)
		post.mesh = post_mesh
		post.position = Vector3(side * (wide * 0.5 - 0.06), (high + Caster.HEIGHT) * 0.5, -0.06)
		post.material_override = Materials.brushed_metal()
		eq_wall_trolley.add_part(post)
	var plinth := MeshInstance3D.new()
	plinth.name = "Plinth"
	var plinth_mesh := BoxMesh.new()
	plinth_mesh.size = Vector3(wide, 0.04, 0.3)
	plinth.mesh = plinth_mesh
	plinth.position = Vector3(0, Caster.HEIGHT + 0.02, -0.06)
	plinth.material_override = Materials.furniture()
	GearTrim.edges(plinth)
	eq_wall_trolley.add_part(plinth)
	eq_wall_trolley.add_corner_casters(0.06)
	var plaque := Stations.plaque(&"eq_wall", EqWall.SIDE - 0.02)
	plaque.position = Vector3(EqWall.PLATE_WIDE * 0.5 - EqWall.SIDE * 0.5,
			EqWall.PLAQUE_TOP - float(plaque.get_meta(&"plaque_tall")) * 0.5, 0.012)
	eq_wall_trolley.add_child(plaque)


## The LEVELS niche (slice 66; 2026-10-30, "its own like divet in the wall so it can be an entire
## wall"): where it is is the venue's (Venue.levels_niche_spot), in the set's frame.
func _levels_niche_at() -> Transform3D:
	return _venue_to_set(venue.levels_niche_spot()) if venue != null \
			else Transform3D(Basis.IDENTITY, Vector3(-room_width * 0.5 + Venue.LEVELS_NICHE_FROM_LEFT, 0,
					ROOM_FRONT + Venue.LEVELS_NICHE_IN))


## The niche's measures (m): the surround either side, its depth out of the wall (shallower where
## it stands on its own, to keep 0.6 m from the patch wall's legs), how far its back goes into the
## wall (or, standing, how deep the cabinet is behind the board), how high it stands, the sill the
## board stands on, and how far the lintel and the sill sit back from the cheeks' faces.
const NICHE_SIDE := 0.16
const NICHE_OUT := 0.3
const NICHE_STANDING_OUT := 0.2
const NICHE_INTO_WALL := 0.12
const NICHE_STANDING_BACK := 0.16
const NICHE_TOP := 3.3
const NICHE_SILL := 0.38
const NICHE_STEP := 0.025
const NICHE_PLASTER := Color(0.36, 0.35, 0.33)


## The niche LEVELS is set into: a surround either side and over it standing out of the wall, a
## sill under it and a dark back, so the board is sunk in the wall rather than hung on it; a lit
## strip under the lintel. Where the venue has no wall to build into, a cabinet of the same, with
## a back of its own. A Trolley so the floor plan, the stations and the board's ride treat it as
## they treat every piece, but with nothing to take hold of and never rolled: it stays in the wall
## (`_set_levels_niche`), and a board put down by its handle goes back into it (`_reseat`).
func _build_levels_niche() -> void:
	var at := _levels_niche_at()
	levels_niche = _trolley("LevelsNiche", &"levels", at.origin, rad_to_deg(at.basis.get_euler().y))
	levels_niche.built_in = true
	levels_niche.follow = 9.0
	_set_levels_niche()


## Build the niche for this venue and stand it where this venue keeps it. Its boxes overlap where
## they meet rather than touch, the lintel and the sill a step back from the cheeks, so no two faces
## share a plane to flicker between.
func _set_levels_niche() -> void:
	if levels_niche == null:
		return
	for old in levels_niche.get_children():
		if old.has_meta(&"niche"):
			levels_niche.remove_child(old)
			old.queue_free()
	var standing := venue != null and venue.back_wall_gear_stands()
	var out := NICHE_STANDING_OUT if standing else NICHE_OUT
	var board := LevelsWall.room_y(LevelsWall.WIDE * 0.5 + LevelsWall.BORDER)
	# Room either side for the board's handle, on its left (LevelsWall.handle_left).
	var open := board + 0.12
	var outer := open + NICHE_SIDE
	var back := -(NICHE_STANDING_BACK if standing else NICHE_INTO_WALL)
	var lintel := LevelsWall.room_y(LevelsWall.BOTTOM + LevelsWall.TALL + LevelsWall.BORDER + 0.08) + 0.06
	var behind_board := -LevelsWall.room_y(0.031) - 0.004
	# Plaster a shade off every venue's walls, so it reads as the wall built out round a hollow and
	# not as one more black cabinet against it.
	var surround := Materials.painted_wall(NICHE_PLASTER)
	for side in [-1.0, 1.0]:
		# A hair off the floor, which the wall's own foot is on.
		_niche_box("Cheek", Vector3(NICHE_SIDE, NICHE_TOP - 0.002, out - back),
				Vector3(side * (open + NICHE_SIDE * 0.5), NICHE_TOP * 0.5 + 0.001, (out + back) * 0.5), surround)
	# Into the cheeks either side; a step back from their faces, and short of their tops and backs.
	var span := open * 2.0 + NICHE_SIDE
	var front := out - NICHE_STEP
	var rear := back + 0.01
	_niche_box("Lintel", Vector3(span, NICHE_TOP - 0.01 - lintel, front - rear),
			Vector3(0, (NICHE_TOP - 0.01 + lintel) * 0.5, (front + rear) * 0.5), surround)
	_niche_box("Sill", Vector3(span, NICHE_SILL - 0.004, front - rear),
			Vector3(0, (NICHE_SILL + 0.004) * 0.5, (front + rear) * 0.5), surround)
	_niche_box("Back", Vector3(span - 0.02, lintel - NICHE_SILL + 0.04, 0.02),
			Vector3(0, (lintel + NICHE_SILL) * 0.5, behind_board - 0.01), Materials.recess())
	if standing:
		# Its back: behind the cheeks' and a little inside their sides and top.
		_niche_box("Cabinet", Vector3(outer * 2.0 - 0.02, NICHE_TOP - 0.02, behind_board - 0.02 - (back - 0.01)),
				Vector3(0, NICHE_TOP * 0.5 - 0.005, (behind_board - 0.02 + back - 0.01) * 0.5), surround)
	# Light along the lintel's underside, to the board.
	var strip := MeshInstance3D.new()
	var strip_mesh := BoxMesh.new()
	strip_mesh.size = Vector3(open * 2.0 - 0.1, 0.012, 0.03)
	strip.mesh = strip_mesh
	strip.position = Vector3(0, lintel - 0.007, front - 0.06)
	strip.material_override = Materials.led(Color(1.0, 0.86, 0.66), true)
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	strip.set_meta(&"niche", true)
	strip.name = "Strip"
	levels_niche.add_child(strip)
	# On the floor only in front of the wall: what is in the wall is the wall's.
	var foot_back := back - 0.01 if standing else -0.08
	levels_niche.footprint_centre = Vector2(0, (out + foot_back) * 0.5)
	levels_niche.footprint_half = Vector2(outer, (out - foot_back) * 0.5)
	var plaque := Stations.plaque(&"levels", LevelsWall.room_y(LevelsWall.MASTER_WIDE))
	plaque.set_meta(&"niche", true)
	plaque.position = Vector3(LevelsWall.room_y(LevelsWall.master_left() + LevelsWall.MASTER_WIDE * 0.5),
			LevelsWall.PLAQUE_TOP - float(plaque.get_meta(&"plaque_tall")) * 0.5, front + 0.006)
	levels_niche.add_child(plaque)
	var at := _levels_niche_at()
	levels_niche.place(Vector2(at.origin.x, at.origin.z), at.basis.get_euler().y)


## The TV's bracket (docs/sampling_station.md): where it is is the venue's (Venue.tv_mount_spot), in
## the set's frame.
func _tv_mount_at() -> Transform3D:
	return _venue_to_set(venue.tv_mount_spot()) if venue != null \
			else Transform3D(Basis.IDENTITY, Vector3(room_width * 0.5 - Venue.TV_FROM_RIGHT, 0,
					ROOM_FRONT + Venue.TV_IN))


func _build_tv_mount() -> void:
	var at := _tv_mount_at()
	tv_mount = _trolley("TvMount", &"tv", at.origin, rad_to_deg(at.basis.get_euler().y))
	tv_mount.built_in = true
	tv_mount.follow = 9.0
	_set_tv_mount()


## The TV's bracket for this venue, or its stand where the wall is not one to hang it on, and the
## plaque under it; stood where this venue keeps it.
func _set_tv_mount() -> void:
	if tv_mount == null:
		return
	for old in tv_mount.get_children():
		if old.has_meta(&"mount"):
			tv_mount.remove_child(old)
			old.queue_free()
	var standing := venue != null and venue.back_wall_gear_stands()
	var metal := Materials.brushed_metal()
	var back := -TvSurface.DEPTH
	if standing:
		# Two legs from feet on the floor up the case's back, and a bar across them.
		for side in [-1.0, 1.0]:
			var x: float = side * TvSurface.SCREEN.x * 0.3
			# The leg's foot sunk into the foot's top, the foot a hair off the floor: no face shared.
			_mount_box("Leg", Vector3(0.05, TvSurface.TOP - 0.12, 0.05),
					Vector3(x, 0.02 + (TvSurface.TOP - 0.12) * 0.5, back - 0.03), metal)
			_mount_box("Foot", Vector3(0.08, 0.03, 0.62), Vector3(x, 0.017, back - 0.03 + 0.08), metal)
		# Into the legs, short of their far sides.
		_mount_box("Bar", Vector3(TvSurface.SCREEN.x * 0.6 - 0.02, 0.04, 0.03),
				Vector3(0, TvSurface.FOOT + 0.2, back - 0.03), metal)
		tv_mount.footprint_centre = Vector2(0, back + 0.05)
		tv_mount.footprint_half = Vector2(TvSurface.SCREEN.x * 0.3 + 0.05, 0.31)
	else:
		# An arm from the wall to the case's back.
		var wall := -Venue.TV_IN + 0.05
		_mount_box("Arm", Vector3(0.12, 0.12, back - wall - 0.004),
				Vector3(0, (TvSurface.TOP + TvSurface.FOOT) * 0.5, (back - 0.002 + wall) * 0.5), metal)
		tv_mount.footprint_centre = Vector2(0, -0.06)
		tv_mount.footprint_half = Vector2(TvSurface.SCREEN.x * 0.5 + TvSurface.BEZEL, 0.06)
	var plaque := Stations.plaque(&"tv", TvSurface.SCREEN.x * 0.5)
	plaque.set_meta(&"mount", true)
	plaque.position = Vector3(0, TvSurface.PLAQUE_TOP - float(plaque.get_meta(&"plaque_tall")) * 0.5, 0.006)
	tv_mount.add_child(plaque)
	var at := _tv_mount_at()
	tv_mount.place(Vector2(at.origin.x, at.origin.z), at.basis.get_euler().y)


func _mount_box(of_name: String, size: Vector3, at: Vector3, paint: Material) -> void:
	var box := MeshInstance3D.new()
	box.name = of_name
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.position = at
	box.material_override = paint
	box.set_meta(&"mount", true)
	tv_mount.add_part(box, false)


## FIND on the TV: a search or a link asked for on the monitor; a link plays, a search lists what it
## found (`_on_tv_searched`). From a desk: a headset has no keyboard to type a search with yet.
func find_on_tv() -> void:
	if tv == null or not is_instance_valid(tv):
		return
	if get_viewport() != null and get_viewport().use_xr:
		Session.notice.emit("The TV's FIND is typed: from a desk, for now.")
		return
	var prompt := NamePrompt.ask(self, "YouTube: a search, or paste a link", "", 300)
	prompt.answered.connect(func(text: String) -> void:
		if text.strip_edges() != "" and tv != null and is_instance_valid(tv):
			tv.find(text))


## A pad struck at the sampling station (PadDeck): onto the armed track as a note while the song
## records, as a played key is. The host takes it down; a guest's pads are slice 7's.
func _on_pad_struck(note: int, velocity: int, seconds: float) -> void:
	var track := HitRecorder.armed_track()
	if track <= 0 or hit_recorder == null or not Session.is_authority():
		return
	hit_recorder.note(track, note, velocity, InstrumentItem.MELODIC_CHANNEL, maxf(seconds, 0.05),
			hit_recorder.stamp())


func _on_tv_searched(query: String, rows: Array, error: String) -> void:
	if error != "" or rows.is_empty() or tv == null or not is_instance_valid(tv):
		return
	if get_viewport() != null and get_viewport().use_xr:
		return
	var choices: Array = []
	for row: Dictionary in rows:
		var long := TvSurface._clock(float(row.seconds)) if float(row.seconds) > 0.0 else "live"
		var by := ("  ·  " + str(row.channel)) if str(row.channel) != "" else ""
		choices.append([str(row.id), "%s  ·  %s%s" % [row.title, long, by]])
	var picker := PluginPicker.ask(self, "YouTube: " + query.strip_edges(), choices)
	picker.chosen.connect(func(id: String) -> void:
		if tv != null and is_instance_valid(tv):
			tv.watch(id))


func _niche_box(of_name: String, size: Vector3, at: Vector3, paint: Material) -> void:
	var box := MeshInstance3D.new()
	box.name = of_name
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.position = at
	box.material_override = paint
	box.set_meta(&"niche", true)
	levels_niche.add_part(box, false)


## The bay's own cabinet: a plinth on casters, a carcass under the panel and a cheek either side
## running up past its top, so the bay stands in a frame rather than on a post. The carcass and
## cheeks are sized to the bay once it knows how many rows it has (`_fit_stand_to_bay`).
func _build_patch_stand() -> void:
	patch_stand = _trolley("PatchStand", &"patch_stand", PATCH_STAND_AT, PATCH_STAND_HEADING)
	patch_stand.footprint_centre = Vector2(0, -0.03)
	patch_stand.footprint_half = Vector2(0.62, 0.15)
	patch_stand.follow = 9.0
	var plinth := MeshInstance3D.new()
	var plinth_mesh := BoxMesh.new()
	plinth_mesh.size = Vector3(1.20, 0.03, 0.28)
	plinth.mesh = plinth_mesh
	plinth.position = Vector3(0, Caster.HEIGHT + 0.015, -0.03)
	plinth.material_override = Materials.furniture()
	patch_stand.add_part(plinth)
	_patch_cabinet = MeshInstance3D.new()
	_patch_cabinet.name = "Cabinet"
	_patch_cabinet.mesh = BoxMesh.new()
	_patch_cabinet.material_override = Materials.furniture()
	patch_stand.add_part(_patch_cabinet)
	for side in [-1.0, 1.0]:
		var cheek := MeshInstance3D.new()
		cheek.name = "Cheek"
		cheek.mesh = BoxMesh.new()
		cheek.material_override = Materials.end_cheek()
		patch_stand.add_part(cheek)
		_patch_cheeks.append(cheek)
	patch_stand.add_corner_casters(0.06)
	_fit_stand_to_bay()


# --- what stands out in the venue on its own ------------------------------------------------
#
# The harp, the bells' stand, the cassette rack, the sampler, the Tour case, the prop shelf and
# the hoop stand on the floor by themselves, the way the rack and the deck's cart do, so they are
# pushed about the same way: a trolley each, saved where it was left (`floor/<id>`) and shared
# with the room like the rest. What is built into a venue -- its walls and doors, the riser, the
# booth, the bricks table and the wheel on it, the lattice's frame, the screens on the walls --
# stays where the venue put it, and is what a pushed piece stops at (FloorPlan.stops).
#
# The things themselves are still the venue's children, built with each venue in its own
# materials; their trolley is the studio's and says where they stand (Venue._spot_of), so moving
# it moves them (`_carry_live`), and everything that is measured from them -- a station's seat
# and the board's rows, the items' homes on the shelf and the bells' seats, the rack's slots, the
# baskets a ball goes through, the dartboard on the shelf's posts -- goes with them.

## Each wheeled piece's trolley: its node's name, the footprint in its own frame (centre, half
## extents, from its Stations row or its own class's solid), how heavy it is to push, and the
## grips it is taken hold of by: boxes [size, centre] of its own lowest structure -- a plinth,
## feet, a base -- under whatever on it is played or picked up.
const LIVE_TROLLEYS := {
	&"harp": ["HarpTrolley", Vector2(0, ChordHarp.FOOT_Z), ChordHarp.FOOT, 9.0,
			[[Vector3(0.7, 0.3, 0.4), Vector3(0, 0.15, ChordHarp.FOOT_Z)]]],
	&"bells": ["BellStandTrolley", Vector2.ZERO, HandbellItem.STAND * 0.5, 10.0,
			[[Vector3(HandbellItem.STAND.x, 0.3, HandbellItem.STAND.y), Vector3(0, 0.15, 0)]]],
	&"cassette_rack": ["CassetteRackTrolley", Vector2.ZERO, CassetteRack.FOOT, 9.0,
			[[Vector3(CassetteRack.FOOT.x * 2.0, 0.15, CassetteRack.FOOT.y * 2.0), Vector3(0, 0.075, 0)]]],
	&"sampler": ["SamplerTrolley", Vector2.ZERO, Sampler.FOOT, 9.0,
			[[Vector3(Sampler.FOOT.x * 2.0, 0.15, Sampler.FOOT.y * 2.0), Vector3(0, 0.075, 0)]]],
	# The plinth under the case: above it a click is a cell, a key or the plaque.
	&"music_box": ["MusicBoxTrolley", Vector2(0, MusicBox.FOOT_Z), MusicBox.FOOT, 9.0,
			[[Vector3(MusicBox.FOOT.x * 2.0, 0.3, MusicBox.FOOT.y * 2.0), Vector3(0, 0.15, MusicBox.FOOT_Z)]]],
	# The spool's round foot: above it a click is the reel or its plaque.
	&"strings": ["StringSpoolTrolley", Vector2(0, RoomString.SPOOL_FOOT_Z), RoomString.SPOOL_FOOT, 9.0,
			[[Vector3(RoomString.SPOOL_FOOT.x * 2.0, 0.12, RoomString.SPOOL_FOOT.y * 2.0), Vector3(0, 0.06, RoomString.SPOOL_FOOT_Z)]]],
	# The theremin's splayed foot and its post, under the cabinet: above them a click is its field,
	# its SCALE switch or its plaque.
	&"theremin": ["ThereminTrolley", Vector2(0, Theremin.FOOT_Z), Theremin.FOOT, 9.0,
			[[Vector3(0.58, 0.08, 0.32), Vector3(0, 0.04, 0)], [Vector3(0.07, 0.7, 0.07), Vector3(0, 0.45, 0)]]],
	# The grain cloud's plinth, to the foot of its plaque: above it a click is its plaque, its KEY
	# switch, the bowl or the cloud.
	&"grains": ["GrainCloudTrolley", Vector2(0, GrainCloud.FOOT_Z), GrainCloud.FOOT, 9.0,
			[[Vector3(GrainCloud.FOOT.x * 2.0, 0.3, GrainCloud.FOOT.y * 2.0), Vector3(0, 0.15, GrainCloud.FOOT_Z)]]],
	# The case's bottom edge, a little proud of it: above that a click on the case knocks on it.
	&"tour_case": ["TourCaseTrolley", Vector2.ZERO, Vector2(TourCase.CASE_WIDTH, TourCase.CASE_DEPTH) * 0.5, 7.5,
			[[Vector3(TourCase.CASE_WIDTH + 0.08, 0.1, TourCase.CASE_DEPTH + 0.08), Vector3(0, 0.05, 0)]]],
	# Its legs, under the lower tier the tablet and the percussion lie on.
	&"prop_shelf": ["PropShelfTrolley", Vector2.ZERO, Vector2(ZoneKit.SHELF.x, ZoneKit.SHELF.z) * 0.5, 8.0,
			[[Vector3(ZoneKit.SHELF.x, 0.18, ZoneKit.SHELF.z), Vector3(0, 0.09, 0)]]],
	# The base in front of the pole: the board overhangs the rest of it, which reaches back under
	# the wall's skirting where the venue stands it, and would have the hoop shoved off the wall.
	&"hoop": ["HoopTrolley", Vector2(0, (Hoop.POLE_Z - 0.03 + Hoop.BASE_Z + Hoop.BASE_HALF.y) * 0.5),
			Vector2(Hoop.BASE_HALF.x, (Hoop.BASE_Z + Hoop.BASE_HALF.y - Hoop.POLE_Z + 0.03) * 0.5), 10.0,
			# The pole first, up to under the board: from across the room it is what shows over
			# whatever stands between, and what a hand reaches for.
			[[Vector3(0.07, 1.75, 0.07), Vector3(0, 0.975, Hoop.POLE_Z)],
			[Vector3(Hoop.BASE_HALF.x * 2.0, 0.1, Hoop.BASE_HALF.y * 2.0), Vector3(0, 0.05, Hoop.BASE_Z)]]],
}


## A wheeled piece's trolley for each of Venue.WHEELED, and the patch wall's legs; stood where
## this venue has them (`_wheel_in_live_pieces`) and what stands on them taken there.
func _build_live_pieces() -> void:
	floor_plan.rooms = venue.rooms() if venue != null else []
	floor_plan.stops.append(_venue_stops)
	for id: StringName in Venue.WHEELED:
		var spec: Array = LIVE_TROLLEYS[id]
		var spot: Variant = venue.default_spot(id) if venue != null else null
		var at: Transform3D = spot if spot != null else Transform3D.IDENTITY
		var t := _trolley(spec[0], id, at.origin, rad_to_deg(at.basis.get_euler().y))
		t.footprint_centre = spec[1]
		t.footprint_half = spec[2]
		t.follow = spec[3]
		# Pushed across the floor on its own feet, not wheeled.
		t.rolls = false
		for grip: Array in spec[4]:
			_grip(t, grip[0], grip[1])
		if id == &"hoop":
			# Its base is a step underfoot (Hoop.solids); its pole is what a person walks into.
			t.body_centre = Vector2(0, Hoop.POLE_Z)
			t.body_half = Vector2.ONE * Hoop.POLE_RADIUS
		_go_live(t)
	_build_patch_wall_legs()
	_wheel_in_live_pieces()
	_carry_all_live()


## A box to take a trolley by, of `size` centred at `at` in its frame, with nothing drawn: the
## piece's own plinth or feet are drawn by the piece.
func _grip(t: Trolley, size: Vector3, at: Vector3) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	t.add_child(shape)
	return shape


## Known as one of `live_pieces`, and what stands on it carried along as it moves.
func _go_live(t: Trolley) -> void:
	live_pieces[t.piece_id] = t
	t.moved.connect(_carry_live.bind(t.piece_id))
	t.settled.connect(_carry_live.bind(t.piece_id))


## The patch wall's two legs, on a trolley; the screen is the venue's child (`_stand_a_patch_wall`),
## and goes where the legs are.
func _build_patch_wall_legs() -> void:
	var at := _patch_wall_default()
	var legs := _trolley("PatchWallLegs", &"patch_wall", at.origin, rad_to_deg(at.basis.get_euler().y))
	legs.footprint_centre = Vector2(0, PATCH_WALL_LEG_Z)
	legs.footprint_half = Vector2(PATCH_WALL_LEG_X + 0.06, 0.06)
	legs.follow = 8.0
	legs.rolls = false
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		leg.name = "PatchWallLeg"
		var post := BoxMesh.new()
		post.size = Vector3(0.06, 1.6, 0.06)
		leg.mesh = post
		leg.position = Vector3(side * PATCH_WALL_LEG_X, 0.8, PATCH_WALL_LEG_Z)
		leg.material_override = Materials.furniture()
		legs.add_part(leg)
	_go_live(legs)


## Where piece `id` of `live_pieces` stands in this venue until somebody moves it, in the set's
## frame; null where this venue has no room for it: the Rig Roulette room has no booth for the
## sampler to stand against, and a venue that hangs its own patch wall needs no legs for one.
func _live_default(id: StringName) -> Variant:
	if venue == null:
		return null
	match id:
		&"station_board":
			return Transform3D(Basis(Vector3.UP, deg_to_rad(BOARD_HEADING)), BOARD_AT)
		&"patch_wall":
			var hung := venue.get_node_or_null("PatchWall")
			if hung != null and not hung.has_meta(&"on_legs"):
				return null
			return _patch_wall_default()
	var spot: Variant = venue.default_spot(id)
	return _venue_to_set(spot) if spot != null else null


## Every piece of `live_pieces` stood for this venue: hidden, and out of everyone's way, where it
## has no room for it; else where this player last left it, or, never moved, where the venue
## stands it. Then each is settled against the others and the venue's own solids, so a spot left
## in one venue that is a wall in this one is the nearest clear place to it. Not saved: none of
## this was anyone's push.
func _wheel_in_live_pieces() -> void:
	if floor_plan == null or venue == null or live_pieces.is_empty():
		return
	floor_plan.rooms = venue.rooms()
	var placing: Array[Trolley] = []
	for id: StringName in live_pieces:
		var t: Trolley = live_pieces[id]
		var spot: Variant = _live_default(id)
		t.visible = spot != null
		# Where the venue only draws the shelf, what stands about with it is drawn to walk through.
		t.walk_through = Venue.WHEELED.has(id) and not venue.prop_shelf_solid()
		if spot == null or t.held_by != null:
			continue
		var at: Transform3D = spot
		var key := StringName("floor/%s" % id)
		if not _showing_hosts_room and Session.layout != null \
				and Session.layout.has_transform(key, Presentation.Mode.STUDIO):
			var saved := Session.layout.transform_for(key, Presentation.Mode.STUDIO, at)
			# Saved where an older, smaller room stood it: nobody's choice, so where this one does.
			if not was_an_old_default(id, saved):
				at = saved
		t.position = Vector3(at.origin.x, 0, at.origin.z)
		t.rotation = Vector3(0, at.basis.get_euler().y, 0)
		placing.append(t)
	var was := _fitting
	_fitting = true
	for t in placing:
		t.place(Vector2(t.position.x, t.position.z), t.rotation.y)
	_fitting = was


func _carry_all_live() -> void:
	for id: StringName in live_pieces:
		_carry_live(id)


## Take what stands on piece `id` to where its trolley is now: the thing itself, and whatever is
## measured from it. Each frame it moves, so a shelf's toys ride on it rather than catching up.
func _carry_live(id: StringName) -> void:
	if venue == null or not venue.is_inside_tree():
		return
	match id:
		&"mini_table":
			_rehome_items()
		&"harp":
			if harp != null and is_instance_valid(harp):
				harp.transform = venue.harp_spot()
		&"bells":
			if _bell_stand != null and is_instance_valid(_bell_stand):
				_bell_stand.transform = venue.bell_stand_spot()
			_rehome_items()
		&"cassette_rack":
			if cassette_rack != null and is_instance_valid(cassette_rack):
				cassette_rack.transform = venue.cassette_rack_spot()
				_hold_the_rack()
		&"sampler":
			var at: Variant = venue.sampler_spot()
			if sampler != null and is_instance_valid(sampler) and at != null:
				sampler.transform = at
		&"music_box":
			var at: Variant = venue.music_box_spot()
			if music_box != null and is_instance_valid(music_box) and at != null:
				music_box.transform = at
		&"strings":
			var at: Variant = venue.string_spool_spot()
			if spool != null and is_instance_valid(spool) and at != null:
				spool.transform = at
		&"theremin":
			var at: Variant = venue.theremin_spot()
			if theremin != null and is_instance_valid(theremin) and at != null:
				theremin.transform = at
		&"grains":
			var at: Variant = venue.grains_spot()
			if grain_cloud != null and is_instance_valid(grain_cloud) and at != null:
				grain_cloud.transform = at
				_hold_the_bowl()
		&"tour_case":
			if tour_case != null:
				tour_case.transform = _venue_to_set(venue.tour_case_spot())
				_rehome_spills()
		&"prop_shelf":
			var shelf := venue.get_node_or_null("PropShelf") as Node3D
			if shelf != null:
				shelf.transform = venue.prop_shelf_spot()
			if items != null:
				items.boards = venue.dart_boards()
			_rehome_items()
			# A cassette lies on the shelf when the rack is gone (`_made_home`).
			if cassette_rack == null or not is_instance_valid(cassette_rack):
				_hold_the_rack()
		&"hoop":
			var hoop := venue.get_node_or_null("Hoop") as Node3D
			if hoop != null:
				hoop.transform = venue.hoop_spot()
			if items != null:
				items.hoops = venue.hoops()
			_rehome_items()
		&"station_board":
			if station_board != null and is_instance_valid(station_board):
				station_board.transform = (live_pieces[id] as Trolley).transform
		&"patch_wall":
			var wall := venue.get_node_or_null("PatchWall") as Node3D
			if wall != null and wall.has_meta(&"on_legs"):
				wall.transform = _patch_wall_frame()
	_place_hood_signs()


## The neighbourhoods' banners (Neighbourhoods), the venue's children, one on the wall by each
## neighbourhood that stands here: built with the venue, and moved with what they name
## (`_place_hood_signs`).
func _hang_hood_signs() -> void:
	if venue == null or medium == Presentation.Medium.AR:
		return
	for r: Dictionary in Neighbourhoods.ALL:
		if Neighbourhoods.sign_spot(venue, r["id"]) == null:
			continue
		venue.add_child(Neighbourhoods.make_sign(r["id"]))
	_place_hood_signs()


## Each banner on its wall by its neighbourhood's middle as it stands now: a piece wheeled across
## the room takes its neighbourhood's middle, and so its banner, some of the way along the wall with
## it, or round to another wall.
func _place_hood_signs() -> void:
	if venue == null or not is_instance_valid(venue):
		return
	for r: Dictionary in Neighbourhoods.ALL:
		var sign := venue.get_node_or_null("Sign_%s" % r["id"]) as Node3D
		if sign == null:
			continue
		var at: Variant = Neighbourhoods.sign_spot(venue, r["id"])
		sign.visible = at != null
		if at != null:
			sign.transform = at


## The items' homes from where the shelf, the hoop and the bells' stand now are: one at home goes
## to its new spot (ItemRoom.set_spots).
func _rehome_items() -> void:
	if items != null and venue != null:
		items.set_spots(venue.item_spots(), _item_homes())


## What the Tour case spilled, homed round where the case now stands (`_spill_home`).
func _rehome_spills() -> void:
	if items == null or tour_case == null:
		return
	var spilled := items.spawned_ids()
	for n in spilled.size():
		var item: Item = items.items.get(spilled[n])
		if item != null:
			item.home = _spill_home(n)


## What a pushed piece stops at among the venue's own things: its solids (Venue.solids), which in
## a studio no longer include anything of `live_pieces`, flattened to floor-plan footprints.
func _venue_stops() -> Array:
	var out: Array = []
	if venue == null or not venue.is_inside_tree():
		return out
	for f: Dictionary in venue.solids():
		out.append(FloorPlan.footprint(f["c"], f["h"], f["a"]))
	return out


## A transform in the venue's frame, in the set's (where the trolleys and the items are); and back.
func _venue_to_set(at: Transform3D) -> Transform3D:
	if venue == null or studio_set == null:
		return at
	return studio_set.transform.affine_inverse() * venue.transform * at


func _set_to_venue(at: Transform3D) -> Transform3D:
	if venue == null or studio_set == null:
		return at
	return venue.transform.affine_inverse() * studio_set.transform * at


# --- plugin tablets -------------------------------------------------------------------------
#
# A plugin pulled off the rack stands on its own music stand: a weighted round foot, a pole, and
# a cradle holding the tablet tilted back at a standing reader's hands. On the floor rather than
# on the desk because the desk is the console, and a tablet propped on the faders is in the way
# of the faders; a stand can be wheeled up beside the chair, or across to the rack, or anywhere.

## The top edge of the tablet on its stand, and how far it leans back. Desk height plus a little:
## read standing, or pulled up beside the chair.
const TABLET_TOP := 1.16
const TABLET_LEAN := 28.0
const TABLET_FOOT := 0.19
## How far in front of the rack's face a pulled tablet lands, when it was not pulled anywhere
## in particular.
const TABLET_PULL := 0.6


func _on_tear_requested(track: int, fx: int, at: Vector3, from: Node3D = null) -> void:
	var f := DAW.state.fx(track, fx, false)
	if f == null or f.name == "":
		return
	# Out from the rack along its facing, so a tablet pulled straight off lands in front of it
	# rather than inside it.
	var out := (from if from != null else rack).global_basis.z.normalized()
	var landing := at + Vector3(out.x, 0, out.z).normalized() * TABLET_PULL
	var id: StringName
	if Session.is_authority():
		id = open_tablet(track, fx, f.name, Vector2(landing.x, landing.z))
	else:
		# Out at once, under a name of this guest's own, and asked for: the host's room renames
		# it when it answers, or takes it back if the host would not.
		id = _predicted_tablet(track, fx, f.name, Vector2(landing.x, landing.z))
		if id == StringName():
			return
	# It lands in front of the rack; nobody is walked to it (F does, as for any gear).


## Put a plugin on a stand at `where` on the floor, facing the mix position. One stand per
## plugin: asking again for one that is already out wheels that stand over instead.
func open_tablet(track: int, fx: int, plugin_name: String, where: Vector2) -> StringName:
	for id in tablets:
		var tablet: PluginTablet = tablets[id][1]
		if tablet.track_index == track and tablet.fx_index == fx:
			(tablets[id][0] as Trolley).place(where, _facing_mix(where))
			return id
	var n := 1
	while tablets.has(StringName("tablet_%d" % n)) or (Session.layout != null \
			and Session.layout.tablets.has(StringName("tablet_%d" % n))):
		n += 1
	var id := StringName("tablet_%d" % n)
	_build_tablet(id, track, fx, plugin_name)
	(tablets[id][0] as Trolley).place(where, _facing_mix(where))
	_remember_tablets()
	_publish_room()
	return id


func _facing_mix(from: Vector2) -> float:
	var to := Vector2(0, MIX_POSITION_Z) - from
	return atan2(to.x, to.y)


func _build_tablet(id: StringName, track: int, fx: int, plugin_name: String) -> void:
	var stand := _trolley("PluginStand_%s" % id, id, Vector3(0, 0, 0.6), 0.0)
	stand.rolls = false
	stand.follow = 14.0
	stand.footprint_half = Vector2(TABLET_FOOT, TABLET_FOOT)
	var foot := MeshInstance3D.new()
	foot.name = "Foot"
	var disc := CylinderMesh.new()
	disc.top_radius = TABLET_FOOT * 0.92
	disc.bottom_radius = TABLET_FOOT
	disc.height = 0.025
	disc.radial_segments = 40
	foot.mesh = disc
	foot.position.y = 0.0125
	foot.material_override = Materials.furniture()
	stand.add_part(foot)
	var pole := MeshInstance3D.new()
	pole.name = "Pole"
	var tube := CylinderMesh.new()
	tube.top_radius = 0.012
	tube.bottom_radius = 0.016
	var pole_top := TABLET_TOP - PluginTablet.HEIGHT * cos(deg_to_rad(TABLET_LEAN)) * 0.5
	tube.height = pole_top
	tube.radial_segments = 16
	pole.mesh = tube
	pole.position = Vector3(0, pole_top * 0.5, -0.02)
	pole.material_override = Materials.brushed_metal()
	stand.add_part(pole)

	var tablet := PluginTablet.create(track, fx, plugin_name)
	tablet.surface_id = id
	# Hung from its top edge's middle, leaning back: the cradle's lip is under its bottom edge.
	var lean := Basis(Vector3.RIGHT, -deg_to_rad(TABLET_LEAN))
	tablet.transform = Transform3D(lean, Vector3(0, TABLET_TOP, 0.0)) \
			* Transform3D(Basis.IDENTITY, Vector3(0, -PluginTablet.HEIGHT * 0.5, 0))
	var lip := MeshInstance3D.new()
	lip.name = "Cradle"
	var ledge := BoxMesh.new()
	ledge.size = Vector3(PluginTablet.WIDTH * 0.8, 0.012, 0.03)
	lip.mesh = ledge
	lip.transform = tablet.transform * Transform3D(Basis.IDENTITY,
			Vector3(0, -PluginTablet.HEIGHT * 0.5 - 0.006, -0.002))
	lip.material_override = Materials.brushed_metal()
	stand.add_part(lip, false)
	stand.add_child(tablet)
	tablet.dock_requested.connect(_dock_tablet.bind(id))
	tablet.grows_with_window = true
	# Gear like the rest: F walks to it, and it comes up close to be worked.
	if focus != null:
		focus.surfaces.append(tablet)
		tablet.rebuilt.connect(focus._on_surface_rebuilt.bind(tablet))
	tablets[id] = [stand, tablet]


func close_tablet(id: StringName) -> void:
	if not tablets.has(id):
		return
	_take_down_tablet(id)
	if Session.layout != null and Session.is_authority():
		Session.layout.clear_transform(StringName("floor/%s" % id), Presentation.Mode.STUDIO)
	_remember_tablets()
	_publish_room()


## The stand gone from this room, and nothing remembered or told about it.
func _take_down_tablet(id: StringName) -> void:
	var stand: Trolley = tablets[id][0]
	var tablet: PluginTablet = tablets[id][1]
	if focus != null:
		if focus.focused_id == id:
			focus.release()
		focus.surfaces.erase(tablet)
	tablets.erase(id)
	floor_plan.pieces.erase(stand)
	stand.queue_free()


## Put back on the rack: here if the room is ours; if it is the host's, here at once and asked.
func _dock_tablet(id: StringName) -> void:
	if Session.is_authority():
		close_tablet(id)
	elif tablets.has(id) and _predict(&"close_tablet", [id]) > 0:
		_take_down_tablet(id)


func _predicted_tablet(track: int, fx: int, plugin_name: String, where: Vector2) -> StringName:
	for id in tablets:
		var t: PluginTablet = tablets[id][1]
		if t.track_index == track and t.fx_index == fx:
			(tablets[id][0] as Trolley).place(where, _facing_mix(where))
			return id
	_predicted_tablets += 1
	var id := StringName("mine_%d" % _predicted_tablets)
	if _predict(&"open_tablet", [track, fx, plugin_name, where.x, where.y], id) == 0:
		return StringName()
	_build_tablet(id, track, fx, plugin_name)
	_applying_room = true
	(tablets[id][0] as Trolley).place(where, _facing_mix(where))
	_applying_room = false
	return id


## The list of what is out, saved whenever a tablet is opened or closed. Not when a tablet finds
## its plugin somewhere new: the name finds it again next time anyway, and a profile rewritten
## because a different session happened to be open would be a file changed by looking at it.
func _remember_tablets() -> void:
	# A guest's tablets are the host's room, not its own: its own wait for it in the profile.
	if Session.layout == null or not Session.is_authority():
		return
	var out := {}
	for id in tablets:
		var t: PluginTablet = tablets[id][1]
		out[id] = [t.track_index, t.fx_index, t.fx_name]
	if out == Session.layout.tablets:
		return
	Session.layout.tablets = out
	Session.layout.save()


func _restore_tablets() -> void:
	if Session.layout == null or not Session.is_authority():
		return
	for id in Session.layout.tablets:
		var entry: Array = Session.layout.tablets[id]
		_build_tablet(id, int(entry[0]), int(entry[1]), str(entry[2]))


# --- pulled-out track racks -----------------------------------------------------------------
#
# The rack's track window has a grip like a unit's name strip. Pulled, the whole track's chain
# comes out on a rack of its own: the same RackSurface, pinned to that track (no window to scroll
# to another, a FOLD button instead), up on a short plinth on casters like the main rack's, so it
# can be wheeled over beside whoever is working on that track. FOLD puts it back in.

## How far in front of the rack's face a pulled-out track's rack lands, when it was not pulled
## anywhere in particular. Further than a tablet: it is a rack, half a metre deep.
const TRACK_RACK_PULL := 0.9
const TRACK_RACK_PLINTH := 0.30


func _on_track_tear_requested(track: int, at: Vector3, from: Node3D) -> void:
	if not DAW.state.tracks.has(track):
		return
	var out := from.global_basis.z.normalized()
	var landing := at + Vector3(out.x, 0, out.z).normalized() * TRACK_RACK_PULL
	var where := Vector2(landing.x, landing.z)
	var id: StringName
	if Session.is_authority():
		id = open_track_rack(track, where)
	else:
		id = _predicted_track_rack(track, where)
		if id == StringName():
			return


## Pull track `track` out on its own rack at `where` on the floor, facing the mix position. One
## per track: asking again for one already out wheels that one over instead.
func open_track_rack(track: int, where: Vector2) -> StringName:
	for id in track_racks:
		if (track_racks[id][1] as RackSurface).track_index == track:
			(track_racks[id][0] as Trolley).place(where, _facing_mix(where))
			return id
	var n := 1
	while track_racks.has(StringName("track_rack_%d" % n)) or (Session.layout != null \
			and Session.layout.track_racks.has(StringName("track_rack_%d" % n))):
		n += 1
	var id := StringName("track_rack_%d" % n)
	_build_track_rack(id, track)
	(track_racks[id][0] as Trolley).place(where, _facing_mix(where))
	_remember_track_racks()
	_publish_room()
	return id


func _build_track_rack(id: StringName, track: int) -> void:
	var stand := _trolley("TrackRackTrolley_%s" % id, id, Vector3(0, 0, 0.6), 0.0)
	stand.footprint_centre = Vector2(0, -0.15)
	stand.footprint_half = Vector2(0.30, 0.17)
	stand.follow = 9.0
	var plinth := MeshInstance3D.new()
	plinth.name = "Plinth"
	var plinth_mesh := BoxMesh.new()
	plinth_mesh.size = Vector3(0.60, TRACK_RACK_PLINTH - Caster.HEIGHT, 0.34)
	plinth.mesh = plinth_mesh
	plinth.position = Vector3(0, (TRACK_RACK_PLINTH + Caster.HEIGHT) * 0.5, -0.15)
	plinth.material_override = Materials.furniture()
	GearTrim.edges(plinth)
	stand.add_part(plinth)
	# A band of the track's colour round the plinth's front: which track this rack is, from the
	# far side of the room.
	var band := MeshInstance3D.new()
	band.name = "TrackBand"
	var band_mesh := BoxMesh.new()
	band_mesh.size = Vector3(0.56, 0.035, 0.004)
	band.mesh = band_mesh
	band.position = Vector3(0, (TRACK_RACK_PLINTH + Caster.HEIGHT) * 0.5, 0.024)
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stand.add_part(band, false)
	stand.add_corner_casters(0.05)

	var pulled := RackSurface.new()
	pulled.name = "TrackRack"
	pulled.surface_id = id
	pulled.pinned = true
	pulled.track_index = track
	pulled.position = Vector3(0, TRACK_RACK_PLINTH, 0)
	stand.add_child(pulled)
	pulled.tear_requested.connect(func(t: int, f: int, at: Vector3) -> void: _on_tear_requested(t, f, at, pulled))
	pulled.fold_requested.connect(_fold_track_rack.bind(id))
	# The rack rebuilds when its track's colour changes; the band goes with it.
	pulled.rebuilt.connect(func() -> void:
		if track_racks.has(id):
			_paint_track_band(id))
	pulled.rebuilt.connect(_show_patches)
	if focus != null:
		focus.surfaces.append(pulled)
		pulled.rebuilt.connect(focus._on_surface_rebuilt.bind(pulled))
	track_racks[id] = [stand, pulled]
	_paint_track_band(id)


## The band on a pulled-out rack's plinth, in its track's colour as this venue shows it.
func _paint_track_band(id: StringName) -> void:
	var band := (track_racks[id][0] as Node).find_child("TrackBand", true, false) as MeshInstance3D
	var track := (track_racks[id][1] as RackSurface).track_index
	if band != null and DAW.state.tracks.has(track):
		band.material_override = Materials.track_stripe(DAW.state.track(track).shown_colour())


## The venue's palette changed what every track is shown in: everything that shows a track's
## colour is built again in it.
func _recolour_tracks() -> void:
	if mount != null:
		for surface_id in mount.mounted_ids():
			mount.surface(surface_id).mark_dirty()
	for id in tablets:
		(tablets[id][1] as Surface).mark_dirty()
	for id in track_racks:
		(track_racks[id][1] as Surface).mark_dirty()
		_paint_track_band(id)


func close_track_rack(id: StringName) -> void:
	if not track_racks.has(id):
		return
	_take_down_track_rack(id)
	if Session.layout != null and Session.is_authority():
		Session.layout.clear_transform(StringName("floor/%s" % id), Presentation.Mode.STUDIO)
	_remember_track_racks()
	_publish_room()


func _take_down_track_rack(id: StringName) -> void:
	var stand: Trolley = track_racks[id][0]
	var pulled: RackSurface = track_racks[id][1]
	if focus != null:
		if focus.focused_id == id:
			focus.release()
		focus.surfaces.erase(pulled)
	track_racks.erase(id)
	floor_plan.pieces.erase(stand)
	stand.queue_free()


## FOLD: back into the main rack. Here if the room is ours; if it is the host's, here at once
## and asked.
func _fold_track_rack(id: StringName) -> void:
	if Session.is_authority():
		close_track_rack(id)
	elif track_racks.has(id) and _predict(&"close_track_rack", [id]) > 0:
		_take_down_track_rack(id)


func _predicted_track_rack(track: int, where: Vector2) -> StringName:
	for id in track_racks:
		if (track_racks[id][1] as RackSurface).track_index == track:
			(track_racks[id][0] as Trolley).place(where, _facing_mix(where))
			return id
	_predicted_track_racks += 1
	var id := StringName("mine_rack_%d" % _predicted_track_racks)
	if _predict(&"open_track_rack", [track, where.x, where.y], id) == 0:
		return StringName()
	_build_track_rack(id, track)
	_applying_room = true
	(track_racks[id][0] as Trolley).place(where, _facing_mix(where))
	_applying_room = false
	return id


## Tracks renumbered: each pulled-out rack follows its own track, and one whose track is gone
## is folded away, since there is nothing left on it to rack.
func _fold_orphaned_track_racks() -> void:
	if not Session.is_authority():
		return
	for id in track_racks.keys():
		if not DAW.state.tracks.has((track_racks[id][1] as RackSurface).track_index):
			close_track_rack(id)
	_remember_track_racks()


## Saved like the tablets: what is out, by track. Where each stands is its floor transform.
func _remember_track_racks() -> void:
	if Session.layout == null or not Session.is_authority():
		return
	var out := {}
	for id in track_racks:
		out[id] = (track_racks[id][1] as RackSurface).track_index
	if out == Session.layout.track_racks:
		return
	Session.layout.track_racks = out
	Session.layout.save()


func _restore_track_racks() -> void:
	if Session.layout == null or not Session.is_authority():
		return
	for id in Session.layout.track_racks:
		if not track_racks.has(id):
			_build_track_rack(id, int(Session.layout.track_racks[id]))


# --- the shared room -----------------------------------------------------------------------
#
# The venue and the plugins out on stands are facts about the room, like where the desk is, so
# in a session they are the host's: one room, everyone in it. A guest asks and is shown; its own
# venue and tablets wait in its profile for when it is on its own again.

## The room as it stands here, in the shape Session.room carries.
func room_state() -> Dictionary:
	var out := {}
	for id in tablets:
		var stand: Trolley = tablets[id][0]
		var t: PluginTablet = tablets[id][1]
		out[id] = [t.track_index, t.fx_index, t.fx_name, stand.position.x, stand.position.z,
				stand.rotation.y]
	var floor := {}
	if floor_plan != null:
		for piece in floor_plan.pieces:
			var t := piece as Trolley
			if t != null and is_instance_valid(t) and not tablets.has(t.piece_id) \
					and not track_racks.has(t.piece_id):
				floor[t.piece_id] = [t.position.x, t.position.z, t.rotation.y]
	var pulled := {}
	for id in track_racks:
		var stand: Trolley = track_racks[id][0]
		pulled[id] = [(track_racks[id][1] as RackSurface).track_index, stand.position.x, stand.position.z,
				stand.rotation.y]
	var placed := {}
	if mount != null:
		for surface_id in mount.mounted_ids():
			if not mount.seats.has(surface_id):
				placed[surface_id] = mount.studio_home(surface_id)
	return {"venue": venue.venue_id() if venue != null else Venue.IDS[0],
			"variant": venue.variant if venue != null else 0, "tablets": out,
			"floor": floor, "placed": placed, "items": items.state() if items != null else {},
			"made": items.made_ids() if items != null else [],
			"patches": patches.duplicate(true), "on_air": on_air.duplicate(), "board": board_source,
			"track_racks": pulled, "jacks": jacks.state() if jacks != null else {},
			"ropes": stage.ropes.duplicate() if stage != null else {},
			"sampler": sampler.armed_by if sampler != null and is_instance_valid(sampler) else 0,
			"weather": weather_listening, "bricks": _bricks_row(), "looper": looper_row.duplicate(),
			"music_box": music_box_row.duplicate(), RoomString.ROW: strings_row.duplicate(),
			MarbleRun.ROW: marbles_row.duplicate(), MarbleRun.BALLS: marble_balls.duplicate(),
			Modular.ROW: modular_row.duplicate(true), GrainCloud.ROW: grains_key}


func _publish_room() -> void:
	if Session.role == Session.Role.HOST and not _applying_room:
		Session.publish_room(room_state())


func _on_room_changed() -> void:
	if not Session.is_authority():
		apply_room(Session.room, true)


## Make this room the one `state` describes -- its venue, the same stands in the same places, the
## desk where it stands -- and then put this guest's own unanswered moves back on top.
##
## That last part is the prediction. A guest does what it asked for at once, on its own screen,
## and keeps a note of it until the host's room says the ask was answered: until then the note
## wins over the room, so a stand does not flick back to where it was because a room published a
## moment before the ask arrived crossed it on the wire. Once answered, the room is the truth --
## and if the host would not do it, the stand goes back. That is the rollback.
##
## `glide` rolls things to where the room has them, as if pushed, instead of putting them there.
func apply_room(state: Dictionary, glide := false) -> void:
	_applying_room = true
	_showing_hosts_room = true
	var answered := int((state.get("acks", {}) as Dictionary).get(Session.local_peer_id, 0))
	_predictions = _predictions.filter(func(p: Dictionary) -> bool: return int(p["seq"]) > answered)
	var pending_open := {}
	var pending_close := {}
	var pending_move := {}
	var pending_place := {}
	var pending_items := {}
	for p in _predictions:
		match p["verb"]:
			&"put_item", &"home_item", &"throw_item", &"wear_item", &"pocket_item", &"slot_item", &"give":
				pending_items[p["args"][0]] = true
			&"patch", &"on_air", &"plug", &"rope", &"make", &"paste", &"sampler", &"weather", &"bricks", \
					&"looper", &"looper_layer", &"music_box", &"string", &"marble", &"marble_ball", \
					&"modular_patch", &"modular_knob": pass
			&"open_tablet", &"open_track_rack": pending_open[p["id"]] = true
			&"close_tablet", &"close_track_rack": pending_close[p["args"][0]] = true
			&"move_tablet", &"move_piece": pending_move[p["args"][0]] = true
			&"place_surface": pending_place[p["args"][0]] = p["args"][1]

	var id_wanted := StringName(state.get("venue", &""))
	var variant_wanted := Venue.known_variant(id_wanted, int(state.get("variant", 0)))
	if venue != null and Venue.is_known(id_wanted) \
			and (venue.venue_id() != id_wanted or venue.variant != variant_wanted):
		set_venue(id_wanted, false, variant_wanted)

	var wanted: Dictionary = state.get("tablets", {})
	for id in tablets.keys():
		var t: PluginTablet = tablets[id][1]
		var entry: Variant = wanted.get(id)
		if entry != null and int(entry[0]) == t.track_index and int(entry[1]) == t.fx_index:
			continue
		if pending_open.has(id):
			continue
		# The host's answer to this guest's pull: the same stand, under the name the host gave
		# it, rather than this one taken away and that one put up in its place.
		var named := _hosts_name_for(wanted, t.track_index, t.fx_index)
		if named != StringName() and not tablets.has(named):
			_rename_tablet(id, named)
			continue
		_take_down_tablet(id)

	if floor_plan != null:
		for id in wanted:
			if pending_close.has(id):
				continue
			var entry: Array = wanted[id]
			if not tablets.has(id):
				_build_tablet(id, int(entry[0]), int(entry[1]), str(entry[2]))
				(tablets[id][0] as Trolley).place(Vector2(float(entry[3]), float(entry[4])), float(entry[5]))
			elif not pending_move.has(id):
				_follow_room(tablets[id][0], float(entry[3]), float(entry[4]), float(entry[5]), glide)
		var floor: Dictionary = state.get("floor", {})
		for piece in floor_plan.pieces:
			var t := piece as Trolley
			if t == null or not is_instance_valid(t) or not floor.has(t.piece_id) or pending_move.has(t.piece_id):
				continue
			var spot: Array = floor[t.piece_id]
			_follow_room(t, float(spot[0]), float(spot[1]), float(spot[2]), glide)

	if floor_plan != null and state.has("track_racks"):
		var racks_wanted: Dictionary = state["track_racks"]
		for id in track_racks.keys():
			var entry: Variant = racks_wanted.get(id)
			var mine: RackSurface = track_racks[id][1]
			if (entry != null and int(entry[0]) == mine.track_index) or pending_open.has(id):
				continue
			_take_down_track_rack(id)
		for id in racks_wanted:
			if pending_close.has(id):
				continue
			var entry: Array = racks_wanted[id]
			if not track_racks.has(id):
				# The host's answer to this guest's own pull: its predicted one goes, the host's
				# takes its place.
				for mine_id in track_racks.keys():
					if (track_racks[mine_id][1] as RackSurface).track_index == int(entry[0]) \
							and not racks_wanted.has(mine_id):
						_take_down_track_rack(mine_id)
				_build_track_rack(id, int(entry[0]))
				(track_racks[id][0] as Trolley).place(Vector2(float(entry[1]), float(entry[2])), float(entry[3]))
			elif not pending_move.has(id):
				_follow_room(track_racks[id][0], float(entry[1]), float(entry[2]), float(entry[3]), glide)

	if mount != null:
		var placed: Dictionary = (state.get("placed", {}) as Dictionary).duplicate()
		placed.merge(pending_place, true)
		mount.share_studio(placed, GLIDE_SECONDS if glide else 0.0)
	if items != null and state.has("made"):
		# The made items the room names, real here from the rows the host sent first.
		items.apply_made(state["made"])
	if items != null and state.has("items"):
		items.apply(state["items"], pending_items)
	if items != null and state.has("bricks"):
		_apply_bricks(state["bricks"])
	_settle_makes(answered)
	if state.has("on_air"):
		on_air = (state["on_air"] as Array).duplicate()
		for p in _predictions:
			if p["verb"] == &"on_air":
				_set_on_air(Session.local_peer_id, p["args"][0], false)
	if state.has("patches"):
		patches = (state["patches"] as Dictionary).duplicate(true)
		# This guest's plugs it has moved and not heard back about, on top.
		for p in _predictions:
			if p["verb"] == &"patch":
				_set_patch(Session.local_peer_id, p["args"][0], p["args"][1], false)
		_show_patches()
	if jacks != null and state.has("jacks"):
		var rows: Dictionary = (state["jacks"] as Dictionary).duplicate()
		# The host's word alone first: a chord hand it now says goes into a bandmate sends again.
		jacks.answered(rows)
		# This guest's plugs it has not heard back about, on top: an empty sink, unplugged.
		for p in _predictions:
			if p["verb"] == &"plug":
				rows[String(p["args"][0])] = String(p["args"][1])
		jacks.set_patch(rows)
	if stage != null and state.has("ropes"):
		# The stage table keeps its own unanswered ties and cuts on top.
		stage.apply_ropes(state["ropes"], answered)
	if sampler != null and is_instance_valid(sampler) and state.has("sampler") \
			and not _predictions.any(func(p): return p["verb"] == Sampler.VERB):
		# Once its press is answered, the host's word: on for whoever the room says, or off.
		sampler.armed_by = int(state["sampler"])
	if state.has("weather") and not _predictions.any(func(p): return p["verb"] == Weather.VERB):
		# Once its press is answered, the host's word: LISTEN or OFF.
		_show_weather(bool(state["weather"]))
	if state.has(GrainCloud.ROW) and not _predictions.any(func(p): return p["verb"] == GrainCloud.VERB):
		# Once its press is answered, the host's word: KEY on or off.
		_show_grains_key(bool(state[GrainCloud.ROW]))
	if state.has("looper") and not _predictions.any(func(p): return p["verb"] == Looper.VERB or p["verb"] == Looper.LAYER_VERB):
		# Once its slaps and layers are answered, the host's word: who is looping, from which bar.
		_show_looper(state["looper"])
	if state.has("music_box") and not _predictions.any(func(p): return p["verb"] == MusicBox.VERB):
		# Once its keys are answered, the host's word: TRACK, LENGTH, ROOT and SCALE.
		_show_music_box(state["music_box"])
	if state.has(RoomString.ROW):
		# The host's strings, with this guest's own ties and cuts it has not heard back about on top.
		var rows: Dictionary = (state[RoomString.ROW] as Dictionary).duplicate()
		for p in _predictions:
			if p["verb"] == RoomString.VERB:
				RoomString.answer(rows, p["args"][0], p["args"][1], p["args"][2], Session.local_peer_id)
		_show_strings(rows)
	if state.has(MarbleRun.ROW):
		# The host's blocks, with this guest's own it has not heard back about on top.
		var blocks: Dictionary = (state[MarbleRun.ROW] as Dictionary).duplicate()
		for p in _predictions:
			if p["verb"] == MarbleRun.VERB:
				MarbleRun.answer(blocks, p["args"][0], p["args"][1], p["args"][2])
		_show_marbles(blocks)
	if state.has(MarbleRun.BALLS):
		var held: Array = (state[MarbleRun.BALLS] as Array).duplicate()
		for p in _predictions:
			if p["verb"] == MarbleRun.BALL_VERB:
				held = MarbleRun.answer_ball(held, p["args"][0])
		_show_marble_balls(held)
	if state.has(Modular.ROW):
		# The host's patch, with this guest's own cables and knobs it has not heard back about on top.
		var patch := Modular.clean(state[Modular.ROW])
		for p in _predictions:
			if p["verb"] == Modular.PATCH_VERB:
				Modular.answer_patch(patch, p["args"][0], p["args"][1])
			elif p["verb"] == Modular.KNOB_VERB:
				Modular.answer_knob(patch, p["args"][0], p["args"][1])
		_show_modular(patch)
	if state.has("board") and not _predictions.any(func(p): return p["verb"] == &"board_source"):
		_show_board(StringName(state["board"]))
	_applying_room = false
	_looms_dirty = true


## The time a desk put down across the room takes to get there on this screen.
const GLIDE_SECONDS := 0.25


## A piece to where the room has it -- unless a hand here has hold of it, which wins.
func _follow_room(t: Trolley, x: float, z: float, heading: float, glide: bool) -> void:
	if t.held_by != null:
		return
	var at := Vector2(x, z)
	if at.is_equal_approx(Vector2(t.position.x, t.position.z)) and is_equal_approx(t.rotation.y, heading):
		return
	if glide:
		t.roll_to(at, heading)
	else:
		t.steered = true
		t.place(at, heading)


func _hosts_name_for(wanted: Dictionary, track: int, fx: int) -> StringName:
	for id in wanted:
		if int(wanted[id][0]) == track and int(wanted[id][1]) == fx:
			return id
	return StringName()


## The same stand, known by another name: the one the host gave the stand this guest put out.
func _rename_tablet(from: StringName, to: StringName) -> void:
	var stand: Trolley = tablets[from][0]
	var tablet: PluginTablet = tablets[from][1]
	tablets.erase(from)
	tablets[to] = [stand, tablet]
	stand.piece_id = to
	tablet.surface_id = to
	_authored_floor[to] = _authored_floor.get(from, stand.transform)
	_authored_floor.erase(from)
	if focus != null and focus.focused_id == from:
		focus.focused_id = to
	for p in _predictions:
		if p["verb"] != &"open_tablet" and p["args"].size() > 0 and p["args"][0] == from:
			p["args"][0] = to


## A guest's ask, sent, and done here at once. See apply_room.
func _predict(verb: StringName, args: Array, id := StringName()) -> int:
	var seq := Session.ask_room(verb, args)
	if seq > 0:
		_predictions.append({"seq": seq, "verb": verb, "args": args, "id": id})
	return seq


## A stand being pushed by a hand here, told to everyone else a few dozen times a second so
## theirs rolls after it. The settled place is sent as an ask when it comes to rest.
func _on_trolley_moved(piece: Trolley) -> void:
	_looms_dirty = true
	if piece.held_by == null or not Session.is_networked():
		return
	var now := Time.get_ticks_msec()
	if now - _motion_sent_msec < MOTION_MSEC:
		return
	_motion_sent_msec = now
	Session.send_motion(piece.piece_id, piece.position.x, piece.position.z, piece.rotation.y)


const MOTION_MSEC := 50


## Someone else's hand on a stand: roll ours after it. Not one this guest is pushing, nor one it
## has let go of and not yet heard the host answer for.
func _on_room_motion(id: StringName, x: float, z: float, heading: float, _from: int) -> void:
	var t := _floor_piece(id)
	if t == null or t.held_by != null:
		return
	for p in _predictions:
		if (p["verb"] == &"move_piece" or p["verb"] == &"move_tablet") and p["args"][0] == id:
			return
	# Kept and played back a moment behind (_drive_pushed), rather than sprung after.
	var trail: PoseTrail = _pushed_trails.get(id)
	if trail == null:
		trail = PoseTrail.new()
		_pushed_trails[id] = trail
	trail.push(PoseTrail.now(), Transform3D(Basis(Vector3.UP, heading), Vector3(x, 0, z)))


## The stands someone else is pushing, by id: what their push sent, played back.
var _pushed_trails := {}


func _drive_pushed() -> void:
	var now := PoseTrail.now()
	for id in _pushed_trails.keys():
		var trail: PoseTrail = _pushed_trails[id]
		var t := _floor_piece(id)
		if t == null or t.held_by != null:
			_pushed_trails.erase(id)
			continue
		var pose := trail.sample(now)
		var heading := pose.basis.get_euler().y
		if trail.settled(now):
			# Let go over there: the spring brings it the last of the way and it settles.
			_pushed_trails.erase(id)
			t.roll_to(Vector2(trail.latest().origin.x, trail.latest().origin.z), trail.latest().basis.get_euler().y)
			continue
		t.drive_to(Vector2(pose.origin.x, pose.origin.z), heading)


## The host, answering someone's ask. The same calls the host's own hands make, so the room is
## then published the way any change to it is.
func _on_room_asked(verb: StringName, args: Array, from: int) -> void:
	match verb:
		&"look_solo":
			_on_look_solo_asked(args[0], args[1], from)
		&"patch":
			# A monitor only while its performer is on air: off air, there is no socket to plug into.
			var into := PersonalMix.monitor_of(args[1])
			if PersonalMix.valid_socket(args[1]) and (into == 0 or into in on_air):
				_set_patch(from, args[0], args[1])
				_publish_room_soon()
		&"on_air":
			_set_on_air(from, args[0])
			_publish_room_soon()
		&"plug":
			# The hand that holds it, or anyone while it is home; into a track there is or a
			# bandmate in the room; and whoever a jack goes into may take it out.
			if jacks != null and _plug_refusal(args[0], args[1], from) == "":
				var was := jacks.sink_of(args[0])
				jacks.plug(args[0], args[1])
				_tell_plugged(args[0], was, args[1], from)
				_publish_room_soon()
		&"open_tablet":
			if floor_plan != null and DAW.state.fx(args[0], args[1], false) != null:
				open_tablet(args[0], args[1], args[2], Vector2(args[3], args[4]))
		&"close_tablet":
			close_tablet(args[0])
		&"move_tablet", &"move_piece":
			var piece := _floor_piece(args[0])
			if piece != null:
				piece.place(Vector2(args[1], args[2]), args[3])
		&"place_surface":
			if mount != null and mount.mounted_ids().has(args[0]) and not mount.seats.has(args[0]):
				_place_in_studio(args[0], args[1])
		&"put_item", &"home_item", &"throw_item", &"wear_item", &"pocket_item":
			var item: Item = items.items.get(args[0]) if items != null else null
			if item == null or not _may_put(item, from):
				return
			match verb:
				&"wear_item":
					# Only something in their hand goes on their head.
					if item.state == Item.State.HELD:
						item.set_worn(args[1])
				&"pocket_item":
					# Only something they have goes in their pocket, and only one of theirs.
					if item.state == Item.State.HELD and args[1] >= -1 and args[1] < Pockets.COUNT:
						item.set_pocket(args[1])
				&"put_item": items.lay(item, Vector2(args[1], args[2]), args[3])
				&"home_item": items.retire(item)
				&"throw_item": items.fly(item, args[1], args[2], args[3], from)
		&"take_personal":
			if items != null:
				items.take_personal(args[0], from)
		&"make":
			# A guest's pull: the host packs the clip from its own song, mints it, and it is in
			# their hand -- or it is refused, and they are told why. A brick of MAKE BRICKS goes
			# onto the ledge instead (slice 31).
			var made := _mint_for(args[0], args[1], from)
			if made != null and made is ChordBrick and ChordBrick.into_ledge(args[1]):
				_onto_ledge(made as ChordBrick, from)
			elif made != null:
				_hand_made(made, from)
		&"bricks":
			# A guest's nudge of a chord brick's length: the room's row, if nobody else has it.
			var brick := items.items.get(args[0]) as ChordBrick if items != null else null
			if brick != null and _may_put(brick, from) and args[1] in ChordBrick.LENGTHS:
				brick.bars = args[1]
				_remember_made_soon()
				_publish_room_soon()
		&"slot_item":
			var item: Item = items.items.get(args[0]) if items != null else null
			if item != null and _may_put(item, from) and not items.slot(item, args[1], args[2]):
				Session.tell(from, items.slot_refusal(item, args[1], args[2]))
		&"give":
			var item: Item = items.items.get(args[0]) if items != null else null
			if item != null and Session.holder_of(item.network_key()) == from and args[1] != from \
					and Session.participants.has(args[1]):
				_give(item, args[1], from)
		&"paste":
			# A guest's paste: the cassette in its hand, by id; the clip is the host's own row.
			var cassette := items.items.get(args[0]) as CassetteItem if items != null else null
			if cassette == null or Session.holder_of(cassette.network_key()) != from:
				Session.tell(from, "That cassette is not in your hand here yet: pick it up again and paste.")
			else:
				paste_cassette(cassette, args[1], args[2], from)
		&"open_track_rack":
			if floor_plan != null and DAW.state.tracks.has(args[0]):
				open_track_rack(args[0], Vector2(args[1], args[2]))
		&"close_track_rack":
			close_track_rack(args[0])
		&"harmony":
			# A guest's SET on the fifths wheel: written at the bar they chose, if it reads.
			FifthsWheel.answer(args[0], args[1])
		&"rope":
			# A guest's rope tied or cut on its stage table: the row says what the rope added.
			if stage != null:
				stage.answer_rope(args[0], args[1], args[2])
		&"sampler":
			# A guest's REC: on for their next sound, or off.
			_arm_sampler(args[0], from)
		&"weather":
			# A guest's press on the weather's switch: LISTEN or OFF, for everyone.
			_set_weather(args[0])
		&"grains_key":
			# A guest's press on the grain cloud's KEY: on or off, for everyone.
			_set_grains_key(args[0])
		&"looper":
			# A guest's slap on the looper's pad: armed for them, or refused while somebody else loops.
			_answer_looper(args[0], args[1], from)
		&"looper_layer":
			# A guest's finished layer: onto a track of theirs in the LOOPER folder.
			_write_looper_layer(args[0], args[1], args[2], from)
		&"music_box":
			# A guest's key on the music box: the room's row, if it is one.
			_set_music_box(args)
		&"string":
			# A guest's string tied or cut: the room's row, or told why not.
			_answer_string(args[0], args[1], args[2], from)
		&"marble":
			# A guest's block in the lattice, or taken out: the room's row, or told why not.
			_answer_marble(args[0], args[1], args[2], from)
		&"marble_ball":
			# A guest's BALL: a marble on that beat, for everyone.
			_answer_marble_ball(args[0])
		&"modular_patch":
			# A guest's cable on the modular wall, or one pulled: the room's row, or told why not.
			_answer_modular_patch(args[0], args[1], from, args[2])
		&"modular_knob":
			# A guest's knob let go: the room's row.
			_answer_modular_knob(args[0], args[1], from, args[2])
		&"scratch":
			# A guest's scratch on the platter, for the sampler: of what is in its slot here, and
			# a path that fits (Varispeed.fits: bounded in steps and in time). Rendered only when
			# REC would catch it (_sample_scratch), so an ask with REC off costs the host nothing.
			var path: PackedFloat32Array = args[1]
			var there: Item = items.in_slot(Platter.HOLDER, 0) if items != null else null
			if there != null and there.id == args[0] and there is CassetteItem and Varispeed.fits(path):
				_sample_scratch(there as CassetteItem, path, from)
		&"board_source":
			if board_sources().has(args[0]):
				_show_board(args[0])
				_publish_room()


## Only whoever has an item may put it down: the hand the host's table says has it, or anyone
## when nobody does. Not the guest whose pick-up lost a race, still putting down what it thought
## it had.
func _may_put(item: Item, from: int) -> bool:
	var holder := Session.holder_of(item.network_key())
	return holder == 0 or holder == from


func _floor_piece(id: StringName) -> Trolley:
	if floor_plan == null:
		return null
	for piece in floor_plan.pieces:
		var t := piece as Trolley
		if t != null and is_instance_valid(t) and t.piece_id == id:
			return t
	return null


## Gear that stands on nothing, put somewhere in the studio for the room: remembered as the
## host's own placement, stood there if it is standing in the studio now, and the room told.
func _place_in_studio(surface_id: StringName, where: Transform3D) -> void:
	Session.layout.set_transform(surface_id, Presentation.Mode.STUDIO, where)
	Session.layout.save()
	mount.share_studio({})
	if surface_id == &"console":
		_fit_room_to_session()
	_publish_room()


## The mount's question when the desk is put down in the studio: a guest sends it to the host
## and keeps nothing; the host saves it as ever and tells the room once it has.
func _on_studio_placed(surface_id: StringName, where: Transform3D) -> bool:
	if Session.is_authority():
		_publish_room.call_deferred()
		return false
	if _predict(&"place_surface", [surface_id, where]) > 0:
		var placed := mount.shared_studio.duplicate()
		placed[surface_id] = where
		mount.shared_studio = placed
	return true


## Joined someone: their room arrives on its own. Back on our own, or hosting: our own room, and
## as host, everyone is told what it is.
func _on_role_changed() -> void:
	# This player's keys are `keys:P` for whoever they are now.
	if jacks != null:
		jacks.show_all()
	if Session.role == Session.Role.GUEST:
		return
	if _showing_hosts_room:
		_put_back_own_room()
	# This player's made items, set aside while a guest (Session.join): theirs again.
	_restore_made(true)
	_publish_room()


func _put_back_own_room() -> void:
	_showing_hosts_room = false
	_predictions.clear()
	if Session.layout == null:
		return
	for id in tablets.keys():
		_take_down_tablet(id)
	for id in track_racks.keys():
		_take_down_track_rack(id)
	if mount != null:
		mount.share_studio({})
	if floor_plan != null:
		_applying_room = true
		for piece in floor_plan.pieces:
			var t := piece as Trolley
			if t == null or not is_instance_valid(t) or not _authored_floor.has(t.piece_id):
				continue
			# Each venue stands these where it does: put back for this one below; the niche is in
			# the venue's wall.
			if live_pieces.has(t.piece_id) or t.built_in:
				continue
			var own: Transform3D = Session.layout.transform_for(StringName("floor/%s" % t.piece_id),
					Presentation.Mode.STUDIO, _authored_floor[t.piece_id])
			t.place(Vector2(own.origin.x, own.origin.z), own.basis.get_euler().y)
		_wheel_in_live_pieces()
		_carry_all_live()
		_applying_room = false
		_fit_room_to_session()
	var own := Session.layout.venue if Venue.is_known(Session.layout.venue) else Venue.IDS[0]
	var own_variant := Venue.known_variant(own, Session.layout.venue_variant)
	if medium != Presentation.Medium.AR and venue != null \
			and (venue.venue_id() != own or venue.variant != own_variant):
		set_venue(own, false, own_variant)
	if floor_plan != null:
		_restore_tablets()
		_restore_track_racks()


## The carcass fills from the plinth up to the bay's lower edge and the cheeks run past its top,
## whatever height the session has made the bay.
func _fit_stand_to_bay() -> void:
	if _patch_cabinet == null:
		return
	var height := patchbay.panel_height() if patchbay != null else 0.0
	if height <= 0.0:
		height = 0.8
	var floor_top := Caster.HEIGHT + 0.03
	var under := maxf(PATCH_BAY_TOP - height - 0.004, floor_top + 0.01)
	(_patch_cabinet.mesh as BoxMesh).size = Vector3(PatchbaySurface.PANEL_WIDTH,
			under - floor_top, PATCH_CABINET_DEPTH)
	_patch_cabinet.position = Vector3(0, (under + floor_top) * 0.5,
			PATCH_BAY_FRONT - PatchbaySurface.PANEL_DEPTH - PATCH_CABINET_DEPTH * 0.5 + 0.01)
	GearTrim.edges(_patch_cabinet)
	var top := PATCH_BAY_TOP + 0.03
	for i in _patch_cheeks.size():
		var side := -1.0 if i == 0 else 1.0
		(_patch_cheeks[i].mesh as BoxMesh).size = Vector3(0.035, top - floor_top, 0.16)
		_patch_cheeks[i].position = Vector3(side * (PatchbaySurface.PANEL_WIDTH * 0.5 + 0.0175),
				(top + floor_top) * 0.5, PATCH_BAY_FRONT - 0.06)


func _on_timeline_size_chosen(width_scale: float, lane_height: float) -> void:
	if Session.layout != null:
		Session.layout.timeline_width_scale = width_scale
		Session.layout.timeline_lane_height = lane_height
		Session.layout.save()


func _on_timeline_shelf_chosen(on: bool) -> void:
	if Session.layout != null:
		Session.layout.timeline_shelves = on
		Session.layout.save()


func _room_bounds() -> Rect2:
	return Rect2(-room_width * 0.5 + 0.05, ROOM_FRONT + 0.05, room_width - 0.10, ROOM_DEPTH - 0.05)


## Move the room round the desk. See SessionLayout for the rule.
##
## A piece this participant has put somewhere themselves stays there unless the desk has grown
## into it, and then it is pushed just clear, the way a person would shove it -- not sent back to
## a default they had already rejected. A piece still where the room put it goes where the room
## would put it now.
func _fit_room_to_session() -> void:
	if floor_plan == null or console == null:
		return
	var desk := _desk_footprint()
	if desk.is_empty():
		return
	var fit := SessionLayout.fit((desk[0]["h"] as Vector2).x)
	var width: float = fit["room_width"]
	if not is_equal_approx(width, room_width):
		room_width = width
		floor_plan.bounds = _room_bounds()
		if venue != null:
			set_venue(venue.venue_id(), false, venue.variant)
		_walk_where_the_venue_lets()
	# A guest's room is fitted by the host, who says where everything went.
	if _showing_hosts_room:
		apply_room(Session.room)
		return
	_fitting = true
	for piece in floor_plan.pieces:
		var t := piece as Trolley
		if t == null or not is_instance_valid(t):
			continue
		var id := String(t.piece_id)
		var want: Variant = null
		if fit.has(id):
			want = [fit[id][0], deg_to_rad(fit[id][1])]
		elif id == "eq_wall":
			var at := _eq_wall_at()
			want = [Vector2(at.x, at.z), deg_to_rad(EQ_WALL_HEADING)]
		elif t.built_in:
			continue
		elif id.begins_with("lamp_") and _authored_floor.has(t.piece_id):
			var home: Transform3D = _authored_floor[t.piece_id]
			want = [SessionLayout.widen(Vector2(home.origin.x, home.origin.z), room_width),
					home.basis.get_euler().y]
		var saved := Session.layout != null and Session.layout.has_transform(
				StringName("floor/%s" % id), Presentation.Mode.STUDIO)
		var here := Vector2(t.position.x, t.position.z)
		if want != null and not saved:
			if not (want[0] as Vector2).is_equal_approx(here) or not floor_plan.is_clear(t, here, t.rotation.y):
				t.place(want[0], want[1])
		elif not floor_plan.is_clear(t, here, t.rotation.y):
			t.place(here, t.rotation.y)
	_fitting = false
	_looms_dirty = true
	_publish_room()


## The console does not roll. It is the desk the room is arranged around and the one thing in
## it the mix position is measured from, so it is a fixture: solid, and in the way.
##
## Measured from its home, not its node, because a summoned desk is at the mix position and
## the place it will come back to still has to be kept clear.
func _desk_footprint() -> Array:
	if console == null or mount == null or mount.mode_of(&"console") != Presentation.Mode.STUDIO:
		return []
	var home := focus.home_of(&"console") if focus != null and focus.holds(&"console") \
			else console.transform
	var box := _desk_box()
	if box.size.x <= 0.0:
		return []
	var flat := home * box
	# Down to the floor and out to the toe of the carcass: the panel is what is measured, and
	# the desk under it is what a trolley actually runs into.
	flat = flat.merge(AABB(Vector3(flat.position.x, 0.0, flat.position.z), Vector3(flat.size.x, 0.01, 0.0)))
	return [FloorPlan.footprint_of_box(flat)]


## The desk's measured box. Measuring walks every part of it, and the walker asks every physics
## tick, so it is kept for a quarter of a second -- or until the desk is rebuilt, which is what
## changes it.
const DESK_BOX_FOR_MSEC := 250
var _desk_box_cache := AABB()
var _desk_box_at := -DESK_BOX_FOR_MSEC


func _desk_box() -> AABB:
	var now := Time.get_ticks_msec()
	if now - _desk_box_at >= DESK_BOX_FOR_MSEC:
		_desk_box_cache = console.content_aabb()
		_desk_box_at = now
	return _desk_box_cache


func _forget_desk_box() -> void:
	_desk_box_at = -DESK_BOX_FOR_MSEC


## A piece of furniture that can be pushed around the floor, standing where the layout puts it
## -- or where this participant last left it.
func _trolley(of_name: String, id: StringName, at: Vector3, heading_degrees: float) -> Trolley:
	var piece := Trolley.new()
	piece.name = of_name
	piece.piece_id = id
	piece.floor_plan = floor_plan
	piece.position = at
	piece.rotation_degrees = Vector3(0, heading_degrees, 0)
	_authored_floor[id] = piece.transform
	var key := StringName("floor/%s" % id)
	if Session.layout != null and Session.layout.has_transform(key, Presentation.Mode.STUDIO) \
			and (id == &"levels" or id == &"tv"):
		# Where LEVELS stood on its trolley before it was built into the wall.
		Session.layout.clear_transform(key, Presentation.Mode.STUDIO)
	elif Session.layout != null and Session.layout.has_transform(key, Presentation.Mode.STUDIO):
		var saved := Session.layout.transform_for(key, Presentation.Mode.STUDIO, piece.transform)
		if not _left_where_it_was_authored(id, saved):
			piece.transform = saved
		else:
			# Forgotten, not only passed over: kept, it read as a spot somebody chose, so the room
			# never fitted the piece out of the desk's way and saved it back where it stood.
			Session.layout.clear_transform(key, Presentation.Mode.STUDIO)
	piece.settled.connect(_on_trolley_settled.bind(piece))
	piece.moved.connect(_on_trolley_moved.bind(piece))
	studio_set.add_child(piece)
	floor_plan.add_piece(piece)
	return piece


## Where pieces stood by default before the room was spread out, each time it was (2026-10-26, and
## the 8 x 6 m room of 2026-10-28). A layout saves every piece once it settles, moved or not, so a
## saved spot that is one of these was never chosen by anyone: the piece takes its new default
## instead. A piece somebody did move keeps its place.
const OLD_FLOOR_DEFAULTS := {
	&"rack": [Vector2(-1.18, -0.42), Vector2(-1.75, -0.42)],
	&"deck_trolley": [Vector2(0.80, -0.22), Vector2(1.25, -0.10)],
	&"patch_stand": [Vector2(1.80, -0.30), Vector2(3.05, 1.25)],
	&"stage_trolley": [Vector2(1.10, 1.40), Vector2(-2.1, 1.95)],
	&"eq_wall": [Vector2(3.38, -1.55)],
	&"station_board": [Vector2(1.55, 2.3)],
	&"patch_wall": [Vector2(-3.45, -1.3)],
	&"lamp_1": [Vector2(-2.85, 1.25)],
	&"lamp_2": [Vector2(3.10, 0.95), Vector2(1.9, -2.7), Vector2(2.7, -3.1)],
	&"lamp_3": [Vector2(-2.30, 0.95)],
}
## The old rule's lines for the pieces that make room for the desk (SessionLayout.fit): in a room
## widened for a bigger desk the rack, the deck and the patch stand stood further out along these
## z, so a saved spot on one of them, at the old heading, was the old room's too.
const OLD_FIT_LINES := {
	&"rack": [-0.42, 45.0],
	&"deck_trolley": [-0.10, -50.0],
	&"patch_stand": [1.25, -90.0],
}
## Where the 8 x 6 m room's EQ wall stood off its right-hand wall, whatever its width.
const OLD_EQ_WALL := Vector2(0.62, -1.55)


func _left_where_it_was_authored(id: StringName, saved: Transform3D) -> bool:
	return Studio.was_an_old_default(id, saved)


## Whether a saved floor spot `saved` for piece `id` is one of the defaults an older room stood it
## at (OLD_FLOOR_DEFAULTS, OLD_FIT_LINES, OLD_EQ_WALL), rather than somewhere a player pushed it.
static func was_an_old_default(id: StringName, saved: Transform3D) -> bool:
	var at := Vector2(saved.origin.x, saved.origin.z)
	for was: Vector2 in OLD_FLOOR_DEFAULTS.get(id, []):
		if at.distance_to(was) < 0.02:
			return true
	var heading := rad_to_deg(saved.basis.get_euler().y)
	if OLD_FIT_LINES.has(id):
		var line: Array = OLD_FIT_LINES[id]
		if absf(at.y - float(line[0])) < 0.02 and absf(wrapf(heading - float(line[1]), -180.0, 180.0)) < 0.5:
			return true
	if id == &"eq_wall" and absf(at.y - OLD_EQ_WALL.y) < 0.02 and absf(wrapf(heading - EQ_WALL_HEADING, -180.0, 180.0)) < 0.5:
		# Its x followed the old room's right-hand wall out, in 0.8 m steps.
		var off := at.x + OLD_EQ_WALL.x
		return absf(off / SessionLayout.WIDTH_STEP * 2.0 - roundf(off / SessionLayout.WIDTH_STEP * 2.0)) < 0.03
	return false


## Whether a piece of `live_pieces` is where this venue stands it (`_live_default`), as near as
## the floor plan lets it be. Every piece settling is saved, moved or not; one of these saved where
## the venue happens to stand it would stay there in a venue that stands it somewhere else.
func _where_the_venue_stands_it(piece: Trolley) -> bool:
	if not live_pieces.has(piece.piece_id):
		return false
	var spot: Variant = _live_default(piece.piece_id)
	if spot == null:
		return false
	var at := Vector2((spot as Transform3D).origin.x, (spot as Transform3D).origin.z)
	var heading := (spot as Transform3D).basis.get_euler().y
	if absf(wrapf(piece.rotation.y - heading, -PI, PI)) > 0.002:
		return false
	var here := Vector2(piece.position.x, piece.position.z)
	if here.distance_to(at) < 0.005:
		return true
	return floor_plan != null and here.distance_to(floor_plan.resolve(piece, at, heading)["at"]) < 0.005


func _on_trolley_settled(piece: Trolley) -> void:
	var steered := piece.steered
	piece.steered = false
	if not _fitting and not _applying_room and not (steered and not Session.is_authority()):
		if not Session.is_authority():
			# Wheeled here: it stays here, and the host is told; see apply_room.
			var verb := &"move_tablet" if tablets.has(piece.piece_id) else &"move_piece"
			_predict(verb, [piece.piece_id, piece.position.x, piece.position.z, piece.rotation.y])
			_looms_dirty = true
			return
		_publish_room()
	# Where the host's room has things is not where this guest keeps its own.
	if Session.layout == null or _fitting or _showing_hosts_room:
		_looms_dirty = true
		return
	var key := StringName("floor/%s" % piece.piece_id)
	if _where_the_venue_stands_it(piece):
		# Not a place anyone chose: in the next venue, or a wider room, it goes where that stands it.
		Session.layout.clear_transform(key, Presentation.Mode.STUDIO)
	else:
		Session.layout.set_transform(key, Presentation.Mode.STUDIO, piece.transform)
	Session.layout.save()
	_looms_dirty = true


## The trolley a surface rides on, told how to move that surface's HOME.
##
## Not simply "move the node". A surface on a trolley may be somewhere else entirely when its
## stand is pushed: summoned to the mix position by focus, or sitting on a monitor in SCREEN
## mode. In both cases the stand still moves, and the surface must come back to where the stand
## now is -- so what rides is the surface's studio placement, and the node only moves with it
## when the node is actually standing on the trolley.
## The clip editor, beside the timeline, opened by it: a double click on an item or its EDIT CLIP
## key opens the item here, or retargets the editor to it if it is open on another.
func _build_clip_editor() -> void:
	clip_editor = ClipEditorSurface.new()
	clip_editor.name = "ClipEditor"
	var yaw := deg_to_rad(CLIP_EDITOR_YAW)
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * CLIP_EDITOR_SCALE)
	var left := Vector3(CLIP_EDITOR_LEFT.x, CLIP_EDITOR_Y, CLIP_EDITOR_LEFT.y)
	var at := Transform3D(basis, left - basis * Vector3(-ClipEditorSurface.WIDE * 0.5, 0, 0))
	clip_editor.transform = at
	# Held by an arm from the stand's right-hand leg, which stands just behind it.
	clip_editor.arm_to = at.affine_inverse() * Vector3(TIMELINE_LEG_X, CLIP_EDITOR_Y + 0.1, TIMELINE_STAND_Z)
	studio_set.add_child(clip_editor)
	mount.register(clip_editor)
	timeline.edit_asked.connect(clip_editor.open)


func _ride(piece: Trolley, surface: Surface) -> void:
	var id := surface.surface_id
	var standing := func() -> bool:
		return mount.mode_of(id) == Presentation.Mode.STUDIO and surface.get_parent() == studio_set
	piece.riders.append({
		"get": func() -> Transform3D:
			if focus != null and focus.holds(id):
				return focus.home_of(id)
			if standing.call():
				return surface.transform
			return mount.studio_home(id),
		"set": func(xform: Transform3D, settled_now: bool) -> void:
			if focus != null and focus.holds(id):
				focus.rehome(id, xform)
			elif standing.call():
				surface.transform = xform
			# Nothing saved: a seated surface's place is its stand's, and the stand saves
			# itself. See SurfaceMount.seats.
			pass,
	})
	var offset: Transform3D = _authored_floor[piece.piece_id].affine_inverse() * mount.authored_of(id)
	_seated_on[id] = [piece, offset]
	mount.seat(id, func() -> Transform3D: return piece.transform * offset)


## A seated surface put down by its own handle: roll its stand to where that puts it.
func _reseat(id: StringName, put: Transform3D) -> void:
	if not _seated_on.has(id):
		return
	var piece: Trolley = _seated_on[id][0]
	if piece.built_in:
		return
	var under: Transform3D = put * (_seated_on[id][1] as Transform3D).affine_inverse()
	var ahead := under.basis.z
	piece.place(Vector2(under.origin.x, under.origin.z), atan2(ahead.x, ahead.z))


func _build_anchors() -> void:
	# The head and the hands differ by medium; everything downstream of them does not. That is
	# the point of putting screen_stage on whichever camera exists rather than on the desktop
	# one: a surface in SCREEN mode is a panel in front of your face whether your face is behind
	# a monitor or inside a headset.
	var head: Node3D
	if medium == Presentation.Medium.SCREEN:
		camera = Camera3D.new()
		camera.fov = ROOM_FOV
		# Everything but your own ghost, which only mirrors draw. See core/venues/mirror.gd.
		camera.cull_mask = Mirror.MAIN_VIEW_MASK

		camera.near = 0.02
		add_child(camera)
		head = camera

		var mouse := MouseInteractor.new()
		mouse.camera = camera
		mouse.name = "MouseHand"
		add_child(mouse)
		mouse.bare_jack.connect(_on_bare_jack)
	else:
		rig = XRRig.new()
		rig.name = "XRRig"
		rig.simulated = xr_bootstrap != null and xr_bootstrap.simulated
		add_child(rig)
		head = rig.head
		rig.escape_requested.connect(_on_escape)
		rig.travelled.connect(func(_home: bool) -> void:
			if body != null:
				body.recentre())
		# A bare hand pinched at the floor goes there (Teleport).
		teleport = Teleport.new()
		teleport.name = "Teleport"
		teleport.rig = rig
		# The floor plan's frame, which the walker's footprints and floor are measured in.
		teleport.frame = func() -> Transform3D:
			return studio_set.global_transform if studio_set != null and studio_set.is_inside_tree() else Transform3D.IDENTITY
		teleport.fits = func(p: Vector2) -> bool:
			var fit := _station_fits()
			return fit.is_valid() and bool(fit.call(p))
		teleport.ground = func(p: Vector2) -> float:
			return Walker.ground_of(venue.solids(), p) if venue != null else 0.0
		teleport.refusal = travel_refusal
		teleport.went.connect(func(_to: Vector3) -> void:
			_put_away_beside()
			station = &"")
		add_child(teleport)
		# A VR player's play space is centred on the mix position, in front of the desk, where a
		# desktop's body stands: not at the room's origin, which is inside the console's carcass.
		# From here the desk is at arm's length and the station board is in view, ahead and to
		# the left. Passthrough keeps its own: its floor is a real one, put where the marks say.
		if medium == Presentation.Medium.VR:
			rig.settle(Transform3D(Basis.IDENTITY, Vector3(0, 0, MIX_POSITION_Z)))

	screen_stage = Node3D.new()
	screen_stage.name = "ScreenStage"
	screen_stage.position = Vector3(0, 0, -0.75)
	head.add_child(screen_stage)
	if not get_tree().node_added.is_connected(_keep_out_of_mirrors):
		get_tree().node_added.connect(_keep_out_of_mirrors)

	room_anchor = RoomAnchor.new()
	room_anchor.name = "RoomAnchor"
	add_child(room_anchor)

	studio_set = Node3D.new()
	studio_set.name = "StudioSet"
	add_child(studio_set)

	# The frame a person's own gear sits in, as distinct from the room's. Parented to the studio
	# rather than the head: it follows the head itself, with a deadzone, which is the whole
	# reason it exists. See body_frame.gd.
	body = BodyFrame.new()
	body.name = "BodyFrame"
	add_child(body)
	if medium == Presentation.Medium.SCREEN:
		# On a monitor the camera is NOT a head, and pretending it is makes people ill. The
		# orbit camera swings on a two-metre boom; letting the body take its position meant a
		# mouse drag carried the console bodily around the room on the end of that boom,
		# through the furniture, while the mixer stood still. A drag on a screen is a LOOK.
		#
		# So the body is a mix position instead: a fixed standing spot in the room at eye
		# height, facing the way the room faces. Summoned gear lands in front of it and stays
		# there, and the camera is free to fly around and look at it from anywhere. The gear
		# is still placed from a body -- it is just not a body that chases the lens.
		# In FRONT of the desk, not on top of it. The first version stood the mixer at the room
		# origin, which is where the console's own carcass is, so every summoned surface landed
		# inside the furniture and the render came back with a table sawn through the middle of
		# a mixing desk. A mix position is a place you could actually stand.
		body.position = Vector3(0, ergonomics.eye_height, MIX_POSITION_Z)
	else:
		# In AR and VR it really is a head, and following it is the whole point. See
		# body_frame.gd for the deadzone that keeps a glance from dragging the room.
		body.head = head

	# What a surface may assume it will be seen through. On a monitor that is the seated lens;
	# in a headset it is the visor, which is far wider, and sizing gear to a 54-degree crop
	# there would stack a patchbay into four units that would have fitted in one.
	ergonomics.seated_fov = SEATED_FOV if medium == Presentation.Medium.SCREEN else HEADSET_FOV
	_follow_viewport_shape()
	var view := get_viewport()
	if view != null and not view.size_changed.is_connected(_follow_viewport_shape):
		view.size_changed.connect(_follow_viewport_shape)

	# A light that travels with the person. Summoned gear leaves the room's lamps behind -- the
	# first rack pulled to arm's length arrived in total darkness, which is both useless and a
	# fair description of what body-relative content is: not in the room any more. A headlamp
	# would flatten everything it hit, so this sits up and to the working side, which is where
	# the lamp on a real desk goes and for the same reason. A little ahead of the head rather
	# than over the shoulder, as a desk lamp is: the light is for what is in front, and the
	# full-height rack, framed whole, stands nearly two metres off.
	var work_light := OmniLight3D.new()
	work_light.name = "WorkLight"
	work_light.position = Vector3(0.42 * signf(ergonomics.handedness), 0.30, -0.08)
	work_light.light_color = Color(1.0, 0.95, 0.88)
	work_light.light_energy = 1.0
	work_light.omni_range = 2.4
	work_light.shadow_enabled = false
	body.add_child(work_light)

	mount = SurfaceMount.new()
	mount.name = "SurfaceMount"
	mount.screen_stage = screen_stage
	mount.room_anchor = room_anchor
	mount.studio_set = studio_set
	add_child(mount)

	if rig != null:
		rig.room_anchor = room_anchor

	# A participant with no physical room to mark adopts the session frame outright and stands in
	# the same layout as everyone else. 1.2m is the span the default layout assumes between the
	# two floor marks. An AR participant does NOT get this: they have a real room, and handing
	# them a guessed frame would put the console somewhere plausible and wrong, which is harder
	# to notice than no console at all.
	if medium != Presentation.Medium.AR:
		room_anchor.adopt_virtual_frame(1.2)

	# Everyone else. Built for a solo run too, empty: a session can be hosted from the panel at
	# any moment, and the people who then walk in need somewhere to stand.
	presence = Presence.new()
	presence.name = "Presence"
	presence.head_node = head
	presence.frame = room_anchor
	add_child(presence)
	presence.harp = harp
	presence.strings_heard = _on_string_heard
	presence.grains_heard = _on_grains_heard
	_lend_fingertips()
	_lend_chord_hand()


## This player's fingertips as notes (FingertipNotes, docs/spatial_loop.md slice 8), one per hand:
## each of the headset's, turned on by an open palm up; on a desktop the mouse's, whose fingers
## are J K L ; on a KeyCatcher of their own (`fingertip_keys`), on while it has the keyboard (T).
func _lend_fingertips() -> void:
	if camera != null:
		var mouse := get_node_or_null("MouseHand") as MouseInteractor
		fingertip_keys = KeyCatcher.new()
		fingertip_keys.name = "FingertipKeys"
		fingertip_keys.layout = KeyCatcher.FINGERS
		fingertip_keys.base = 0
		fingertip_keys.octave_keys = false
		fingertip_keys.velocity = FingertipNotes.KEY_VELOCITY
		fingertip_keys.click_releases = true
		add_child(fingertip_keys)
		if mouse != null:
			mouse.finger_source = fingertip_keys
			_add_fingertips(mouse, null)
	if rig != null:
		for controller in rig.interactors:
			_add_fingertips(rig.interactors[controller], rig.skeletons.get(controller) as HandSkeleton)


func _add_fingertips(hand: Interactor, skeleton: HandSkeleton) -> void:
	var notes := FingertipNotes.new()
	notes.name = "Fingertips" + String(hand.get_parent().name if hand.get_parent() != self else hand.name)
	notes.hand = hand
	notes.skeleton = skeleton
	if hand is MouseInteractor:
		notes.catcher = fingertip_keys
	add_child(notes)
	fingertips.append(notes)


## This player's chord hand (ChordHand): in a headset the rig's left hand, or its right for a
## left-handed player (Ergonomics.handedness); on a desktop the chord layer, over the mouse's view
## and the fingertips' keys.
func _lend_chord_hand() -> void:
	chord_hand = ChordHand.new()
	if camera != null:
		chord_hand.mouse = get_node_or_null("MouseHand") as MouseInteractor
		chord_hand.fingertip_keys = fingertip_keys
	if rig != null:
		var controller: XRController3D = rig.left if ergonomics.handedness >= 0 else rig.right
		if controller != null:
			chord_hand.hand = rig.interactors.get(controller) as XRInteractor
			chord_hand.gestures = rig.gestures.get(controller) as HandGestures
			chord_hand.head = rig.head
	add_child(chord_hand)


## C on a desktop: the chord layer on, or off (ChordHand.set_layer). On, 1 to 7 pick the key's
## chords in whichever keys have the keyboard, and with none, the fingertips' take it. Said the
## first time.
func toggle_chords() -> void:
	if chord_hand == null or camera == null:
		return
	chord_hand.set_layer(not chord_hand.layer)
	if chord_hand.layer and not _told_chords:
		_told_chords = true
		Session.notice.emit("Chords: 1 to 7 play the key's I to vii° on the harp, the fingertips (J K L ;) and the bells you hold; Shift adds the seventh, 0 the song's own. A click strums the harp. C or Esc ends it.")


## T on a desktop: the fingertips' keys on, or back to the studio. Said the first time.
func toggle_fingertips() -> void:
	if fingertip_keys == null:
		return
	var on := not fingertip_keys.is_active()
	fingertip_keys.set_active(on)
	if on and not _told_fingertips:
		_told_fingertips = true
		Session.notice.emit("Fingertips: J K L ; play the chord's root, third, fifth and top, held as long as the key. T, Esc or a click gives the keys back.")


func _build_surfaces() -> void:
	# These transforms are the DEFAULT LAYOUT, used until a participant moves something and their
	# LayoutProfile starts overriding them. Heights are real: the desk surface at 0.74m, the
	# patchbay at eye level over it, the rack within arm's reach to the left.
	console = ConsoleSurface.new()
	console.name = "Console"
	console.position = Vector3(0, 0.74, 0.1)
	studio_set.add_child(console)
	mount.register(console)
	if medium != Presentation.Medium.AR:
		_build_desk_wing()

	# On its stand, as authored: the stand's own placement times where the bay sits on it. The
	# stand may since have been wheeled somewhere else; riding it (below) takes care of that.
	patchbay = PatchbaySurface.new()
	patchbay.name = "Patchbay"
	StageLink.wire_bay(patchbay)
	patchbay.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(PATCH_STAND_HEADING)),
			PATCH_STAND_AT) * Transform3D(Basis.IDENTITY, Vector3(0, PATCH_BAY_TOP, PATCH_BAY_FRONT))
	studio_set.add_child(patchbay)
	mount.register(patchbay)

	rack = RackSurface.new()
	rack.name = "Rack"
	rack.position = Vector3(-1.18, 0.30, -0.42)
	rack.rotation_degrees = Vector3(0, 38, 0)
	studio_set.add_child(rack)
	mount.register(rack)

	# Hung on the back wall in the virtual set, which is where it goes for anyone who has
	# chosen to see it as an object. Its default mode is SCREEN in every medium -- a
	# forty-minute song is not furniture -- so most of the time this placement is unused, and
	# it is written anyway so that choosing ROOM does not drop it at the origin.
	timeline = TimelineSurface.new()
	timeline.name = "Timeline"
	timeline.position = Vector3(0, TIMELINE_Y, TIMELINE_Z)
	timeline.scale = Vector3.ONE * TIMELINE_SCALE
	# Shelves or flat lanes, as this person last chose.
	timeline.shelf = Session.layout != null and Session.layout.timeline_shelves
	timeline.shelf_chosen.connect(_on_timeline_shelf_chosen)
	if Session.layout != null:
		timeline.set_size(Session.layout.timeline_width_scale, Session.layout.timeline_lane_height)
	timeline.size_chosen.connect(_on_timeline_size_chosen)
	studio_set.add_child(timeline)
	mount.register(timeline)
	# A write bead pulled out shows its lane on the timeline, so the pass is seen to land there.
	WriteBead.on_pull = _show_written_lane
	_build_clip_editor()

	deck = TapeDeck.new()
	deck.name = "TapeDeck"
	deck.position = Vector3(0.80, 1.02, -0.20)
	deck.rotation_degrees = Vector3(-20, -32, 0)
	studio_set.add_child(deck)
	mount.register(deck)

	focus = FocusRig.new()
	focus.name = "FocusRig"
	focus.body = body
	focus.ergonomics = ergonomics
	focus.surfaces = [console, patchbay, rack, deck, timeline]
	# The stage table, on its trolley beside the mix position (slice 18). None in AR, which has
	# no furniture to stand it on yet.
	if stage_trolley != null:
		stage = StageTable.new()
		stage.name = "StageTable"
		StageLink.wire(stage)
		stage.transform = stage_trolley.transform * Transform3D(Basis.IDENTITY, Vector3(0, STAGE_TOP, 0))
		studio_set.add_child(stage)
		mount.register(stage)
		stage.ropes_changed.connect(_publish_room_soon)
		focus.surfaces.append(stage)
	# The spectra the EQ wall shows: measured here on the built-in engine, sent on to guests, or a
	# guest's host's (slice 36). And the wall, on its trolley at the side wall; none in AR.
	spectra = Spectra.new()
	spectra.name = "Spectra"
	add_child(spectra)
	if eq_wall_trolley != null:
		eq_wall = EqWall.new()
		eq_wall.name = "EqWall"
		eq_wall.spectra = spectra.latest
		eq_wall.reason = spectra.reason
		eq_wall.reference = func() -> float: return spectra.reference
		eq_wall.motion = func() -> float: return ergonomics.motion_scale
		eq_wall.transform = _authored_floor[&"eq_wall"]
		studio_set.add_child(eq_wall)
		mount.register(eq_wall)
		focus.surfaces.append(eq_wall)
	# LEVELS (slice 66), on its trolley at the front left; none in AR.
	if levels_niche != null:
		levels = LevelsWall.new()
		levels.name = "Levels"
		levels.motion = func() -> float: return ergonomics.motion_scale
		levels.transform = _authored_floor[&"levels"]
		studio_set.add_child(levels)
		mount.register(levels)
		focus.surfaces.append(levels)
	# The TV (docs/sampling_station.md), on its bracket right of the timeline; none in AR.
	if tv_mount != null:
		tv = TvSurface.new()
		tv.name = "Tv"
		tv.transform = _authored_floor[&"tv"]
		tv.find_asked.connect(find_on_tv)
		tv.song_position = func() -> float: return hit_recorder.stamp() if hit_recorder != null else 0.0
		tv.pad_struck.connect(_on_pad_struck)
		tv.pads_said.connect(func(words: String) -> void: Session.notice.emit(words))
		tv.searched.connect(_on_tv_searched)
		studio_set.add_child(tv)
		mount.register(tv)
		focus.surfaces.append(tv)
	# The modular wall, over the synth zone's keyboard stand (slice 51); none in AR.
	if medium != Presentation.Medium.AR:
		_build_modular()
		focus.surfaces.append(modular_wall)
	focus.show_halo = medium != Presentation.Medium.SCREEN
	focus.visits = medium == Presentation.Medium.SCREEN
	# Re-seat once the focused surface has been PLACED, which is when it finally knows both its
	# own size and where it ended up. Without this the camera is always aimed using the layout
	# the desk had before it was summoned, and a paged single-tier console is a very different
	# object from the flat 48-track plank it was a frame earlier.
	#
	# Placement, not rebuilding. Both this and the rig itself used to listen to `rebuilt`, and
	# which of them ran first was decided by connection order; this one won, so the camera sat
	# down facing where the gear had been a moment before the rig moved it, and nothing fired
	# again to correct it. `--focus rack` came back as a photograph of the floor.
	focus.placed.connect(_sit_down)
	# A release walks nobody anywhere on its own: what releases to go home (Escape, F off the end,
	# G, BACK) sits down itself, and one that happens to something else -- a tablet closed, a rack
	# folded, a guest handing focus back -- leaves the player where they are (2026-10-30, "i dont
	# like how clicking things moves me to other things in almost all scenarios"). The monitor's
	# panels, put away while gear is visited, come back all the same.
	focus.focus_changed.connect(func(id: StringName) -> void:
		if id == &"" and focus.visits:
			_stand_down_screen(false))
	focus.room = studio_set
	focus.move = _glide
	add_child(focus)
	if mount != null:
		mount.held = focus.holds
	_stand_the_modular()

	# What rides on what. After the rig, because a surface that is summoned rides by its home,
	# and the rig is what holds that.
	if floor_plan != null:
		mount.reseat = _reseat
		mount.studio_placed = _on_studio_placed
		_ride(rack_trolley, rack)
		_ride(deck_trolley, deck)
		_ride(timeline_stand, timeline)
		_ride(timeline_stand, clip_editor)
		_ride(patch_stand, patchbay)
		if stage != null:
			_ride(stage_trolley, stage)
		if eq_wall != null:
			_ride(eq_wall_trolley, eq_wall)
		if levels != null:
			_ride(levels_niche, levels)
		if tv != null:
			_ride(tv_mount, tv)

	# After the gear, because a loom is measured off the transforms of the two things it joins.
	# Rebuilt with the bay, because the bay's width is the track count and the glands are spaced
	# across it: a session that gains tracks moves where its own looms land.
	patchbay.rebuilt.connect(refresh_looms)
	refresh_looms()
	# The beads ride whatever cables there are, found every frame, so a cable rebuilt or freed
	# needs telling nobody.
	signal_beads = SignalBeads.create()
	add_child(signal_beads)

	# The room is fitted to the desk every time the desk changes shape: a live session's tracks
	# arrive after the room is built, and a project that gains a bank gains a metre of console.
	console.rebuilt.connect(_forget_desk_box)
	console.rebuilt.connect(_fit_room_to_session)
	patchbay.rebuilt.connect(_fit_stand_to_bay)
	_fit_room_to_session()

	if floor_plan != null:
		rack.tear_requested.connect(_on_tear_requested)
		rack.track_tear_requested.connect(func(t: int, at: Vector3) -> void: _on_track_tear_requested(t, at, rack))
		_restore_tablets()
		_restore_track_racks()
	Session.room_changed.connect(_on_room_changed)
	# The tablets follow their tracks themselves; what is remembered and told follows them.
	DAW.tracks_renumbered.connect(_on_tracks_renumbered)
	Session.room_asked.connect(_on_room_asked)
	Session.participant_left.connect(_on_look_solo_player_left)
	DAW.project_replaced.connect(func() -> void:
		look_solo.forget()
		_look_by = &""
		guest_look_solos.clear())
	Session.role_changed.connect(_on_role_changed)
	Session.room_motion.connect(_on_room_motion)
	_publish_room()


## A renumbering is answered a frame late, once every tablet has followed its track.
##
## A named method rather than a lambda, because DAW is an autoload that outlives every studio:
## a bound method's connection goes when the studio is freed, and a lambda's does not, so a
## renumbering after a studio was gone ran its deferred body on whatever object later took the
## freed one's memory. A bound method is checked by instance id before it is called, deferred or
## not, and the deferred half also stands down when the studio has left the tree between the
## signal and the next idle frame.
func _on_tracks_renumbered(_map: Dictionary) -> void:
	_after_tracks_renumbered.call_deferred()


func _after_tracks_renumbered() -> void:
	if not is_inside_tree():
		return
	_remember_tablets()
	_fold_orphaned_track_racks()
	_publish_room_soon()


## A stand under every practical.
##
## A tripod floor lamp rather than a pendant, and that is forced rather than chosen: this room
## has three walls and no ceiling, so there is nothing for a hanging fixture to hang from, and a
## stem disappearing into open sky above the wall line would be worse than no fixture at all.
##
## The shade is a cone open at the bottom with an emissive disc inside it, so the lamp reads as
## ON. Nothing about the geometry emits light -- the OmniLight does that, from the middle of the
## shade -- and that division is why the head sits where the light is rather than the other way
## round. Move a practical in the table and its stand follows; there is a test on the pairing,
## because the failure mode is an invisible light source, which is the thing this fixes.
func _build_lamp_stands() -> void:
	for spec in PRACTICALS:
		var at: Vector3 = spec[0]
		var tint: Color = spec[1]
		var number := PRACTICALS.find(spec) + 1
		var stand := _trolley("LampStand", StringName("lamp_%d" % number),
				Vector3(at.x, 0.0, at.z), 0.0)
		stand.add_to_group(&"lamp_stand")
		stand.rolls = false
		stand.follow = 15.0
		stand.footprint_half = Vector2(0.15, 0.15)
		# The light goes with its lamp. Reparented rather than built here, because an AR
		# participant gets the lights with no stands at all -- see _build_environment.
		if number - 1 < _lamps.size():
			_lamps[number - 1].reparent(stand, true)

		var base := MeshInstance3D.new()
		var base_mesh := CylinderMesh.new()
		base_mesh.top_radius = 0.085
		base_mesh.bottom_radius = 0.150
		base_mesh.height = 0.032
		base_mesh.radial_segments = 16
		base.mesh = base_mesh
		base.position = Vector3(0, 0.016, 0)
		base.material_override = Materials.furniture()
		stand.add_part(base)

		# Up to the middle of the shade, so the pole is hidden by the head rather than stopping
		# just short of it and leaving a gap you can see the wall through.
		var pole := MeshInstance3D.new()
		var pole_mesh := CylinderMesh.new()
		pole_mesh.top_radius = 0.0145
		pole_mesh.bottom_radius = 0.0205
		# Rising out of the base rather than standing on the floor inside it, where its foot and
		# the base's underside were one plane.
		pole_mesh.height = at.y - 0.02
		pole_mesh.radial_segments = 10
		pole.mesh = pole_mesh
		pole.position = Vector3(0, (at.y + 0.02) * 0.5, 0)
		pole.material_override = Materials.brushed_metal()
		stand.add_part(pole)

		var shade := MeshInstance3D.new()
		shade.name = "Shade"
		var shade_mesh := CylinderMesh.new()
		shade_mesh.top_radius = LAMP_SHADE_RADIUS * 0.42
		shade_mesh.bottom_radius = LAMP_SHADE_RADIUS
		shade_mesh.height = LAMP_SHADE_HEIGHT
		shade_mesh.radial_segments = 20
		shade_mesh.cap_bottom = false
		shade.mesh = shade_mesh
		shade.position = Vector3(0, at.y, 0)
		shade.material_override = Materials.lamp_shade()
		stand.add_part(shade)

		# The glowing bit. Above the shade's lower rim so the cone shields it from straight on,
		# which is what stops a lamp pointing down reading as a bare bulb from across the room.
		var glow := MeshInstance3D.new()
		var glow_mesh := CylinderMesh.new()
		glow_mesh.top_radius = LAMP_SHADE_RADIUS * 0.80
		glow_mesh.bottom_radius = LAMP_SHADE_RADIUS * 0.80
		glow_mesh.height = 0.004
		glow_mesh.radial_segments = 20
		glow.mesh = glow_mesh
		glow.position = Vector3(0, at.y - LAMP_SHADE_HEIGHT * 0.28, 0)
		glow.material_override = Materials.led(tint, true)
		stand.add_part(glow, false)


# --- looms --------------------------------------------------------------------------------

## The permanent runs from each machine to the back of the patchbay. See hardware/gear_loom.gd
## for what they are claiming.
##
## Skipped for any machine not standing in the virtual set. A surface in SCREEN mode is a panel
## riding in front of someone's face, and a two-metre cable from a panel in the viewer's head
## down to the floor of a room they may not even be rendering is worse than no cable: it moves
## with them, so it reads as the room being dragged around rather than as a loose cable.
func refresh_looms() -> void:
	for loom in _looms:
		if is_instance_valid(loom):
			loom.queue_free()
	_looms.clear()
	if medium == Presentation.Medium.AR or studio_set == null or patchbay == null:
		return
	if patchbay.get_parent() != studio_set:
		return
	# A bay with no jacks has no width, so every landing fraction resolves to the same point and
	# the three looms would stack into one. An empty session gets no looms.
	if patchbay.loom_entry(-1.0).is_equal_approx(patchbay.loom_entry(1.0)):
		return

	for run in LOOM_RUNS:
		var machine: Node3D = get(run[0])
		if machine == null or machine.get_parent() != studio_set:
			continue
		var from_at: Vector3 = machine.transform * (run[1] as Vector3)
		var from_dir: Vector3 = (machine.transform.basis * (run[2] as Vector3)).normalized()
		var entry: Vector3 = patchbay.loom_entry(run[3])
		var to_at: Vector3 = patchbay.transform * entry
		# Into the panel, which is the bay's own -Z however the bay is tilted. Negated because a
		# loom's axis is the direction it RUNS AWAY along, not the direction it points in.
		var to_dir: Vector3 = (patchbay.transform.basis * Vector3.BACK).normalized()
		# A bay standing in its cabinet takes its looms in low, through the cheek on the end
		# that faces the desk, the way a floor-standing bay is wired: from there they go
		# straight to the floor and away behind the desk instead of round the carcass.
		if _stands_in_cabinet():
			var side := -(PatchbaySurface.PANEL_WIDTH * 0.5 + 0.035)
			var fraction: float = run[3]
			to_at = patch_stand.transform * Vector3(side, Caster.HEIGHT + 0.14 + (fraction + 1.0) * 0.045,
					PATCH_BAY_FRONT - 0.06 + fraction * 0.035)
			to_dir = (patch_stand.transform.basis * Vector3.LEFT).normalized()
		var via: Vector3 = run[4]
		# The floor point was written against where the authored layout stood the machine. A
		# machine that has been wheeled somewhere else takes its run of trunking with it.
		var stand := _stand_of(String(run[0]))
		if stand != null and _authored_floor.has(stand.piece_id):
			via = stand.transform * (_authored_floor[stand.piece_id] as Transform3D).affine_inverse() * via
		var loom := GearLoom.create(from_at, from_dir, to_at, to_dir, via, hash(run[0]))
		loom.on_floor = run[5]
		loom.level_source = loom_level(String(run[0]))
		loom.name = "Loom_%s" % run[0]
		studio_set.add_child(loom)
		_looms.append(loom)


## What a machine's loom carries to the bay, for its beads: the console's every heard track (so a
## desk of muted strips sends nothing down it), the rack's every heard track with a plugin on it,
## and the deck's the master it records and plays.
static func loom_level(machine: String) -> Callable:
	match machine:
		"console":
			return func() -> float: return SignalBeads.loudest()
		"rack":
			return func() -> float: return SignalBeads.loudest(
					func(i: int) -> bool: return not DAW.state.track(i).plugins().is_empty())
		"deck":
			return func() -> float: return SignalBeads.master_level()
	return Callable()


func _stands_in_cabinet() -> bool:
	return patch_stand != null and _patch_cabinet != null and _seated_on.has(patchbay.surface_id) \
			and (_patch_cabinet.mesh as BoxMesh).size.y > 0.2


func _stand_of(machine: String) -> Trolley:
	match machine:
		"rack": return rack_trolley
		"deck": return deck_trolley
	return null


## Looms follow furniture that is being pushed, but not every physics frame: a loom is a swept
## mesh, and rebuilding three of them sixty times a second for a rack moving two centimetres is
## the furniture costing more than the console.
func _refresh_looms_if_moved(delta: float) -> void:
	_loom_clock += delta
	if _looms_dirty and _loom_clock >= 0.05:
		_looms_dirty = false
		_loom_clock = 0.0
		refresh_looms()


# --- desktop camera -----------------------------------------------------------------------

## The items' homes off the shelf: the headphones on their hook under it, the handbells on their
## stand by the harp, the mic in the booth's stand, where the venue has one, the session in
## miniature on the side table by the seat, the hand drums in their ring on the drum riser, and the venue's
## instrument's bars on its mount.
func _item_homes() -> Dictionary:
	if venue == null:
		return _kit_homes({})
	var out := {&"headphones": venue.headphones_spot(), &"glasses": venue.glasses_spot(), &"tablet": venue.tablet_spot(),
			&"shaker": venue.shaker_spot(), &"tambourine": venue.tambourine_spot(),
			&"keytar": venue.keytar_spot(), &"chips": venue.chips_spot(), &"cards": venue.cards_spot(),
			&"cradle": venue.cradle_spot(), &"yoyo": venue.yoyo_spot(), &"toy": venue.toy_spot(),
			&"rcplane": venue.rcplane_spot()}
	for n in 3:
		out[StringName("dart%d" % (n + 1))] = venue.dart_spot(n)
	for n in HandbellItem.COUNT:
		out[StringName("bell%d" % (n + 1))] = venue.bell_spot(n + 1)
	var mic_at: Variant = venue.mic_spot()
	if mic_at != null:
		out[&"mic"] = mic_at
	var mini_at: Variant = venue.miniature_spot()
	if mini_at != null:
		out[MiniatureItem.KIND] = mini_at
	# The hand drums round their ring on the drum riser (slice 40); none where there is no riser.
	for n in HandDrum.KINDS.size():
		var drum_at: Variant = venue.drum_circle_spot(n)
		if drum_at != null:
			out[HandDrum.KINDS[n]] = drum_at
	# The venue's instrument's bars on its mount (slice 42); past its count, or with none, put away.
	if venue_instrument != null and is_instance_valid(venue_instrument):
		out.merge(VenueInstrument.homes(venue_instrument.spec))
	return _kit_homes(out)


## `homes` with the drum pads' kit's (slice 41): on the console's front rail, wherever the desk is,
## in AR too; none (put away) with no console built yet.
func _kit_homes(homes: Dictionary) -> Dictionary:
	var at: Variant = kit_home()
	if at != null:
		homes[KitItem.KIND] = at
	return homes


## The things people pick up (docs/items_loop.md), in the set's frame, the floor plan's. They
## lie only where the walker could stand to pick them up again.
func _build_items() -> void:
	items = ItemRoom.new()
	items.name = "Items"
	if medium == Presentation.Medium.AR:
		items.only = ItemRoom.AR_KINDS
	if walker != null:
		items.fits = walker.reachable
		items.ground_at = walker.ground_at
		items.floor_rects = func() -> Array: return walker.walkable
		# What a throw lands on: the venue's fixed things, and the free-standing ones wherever they
		# have been pushed (the walker stops at those as trolleys, which say nothing of how tall).
		items.solids = func() -> Array:
			return walker.fixed + (venue.wheeled_solids() if venue != null and not live_pieces.is_empty() else [])
		items.gear = walker.footprints
	items.local_peer = func() -> int: return Session.local_peer_id
	Session.takeable = func(key: String) -> bool:
		return is_instance_valid(items) and items.items.values().any(
				func(item: Item) -> bool: return item.network_key() == key)
	# A marked instrument (Item.bound_to, Tour's "marked" spill) is refused every other hand by
	# the host's own arbitration, not only by the hand's own `may_hold` check.
	Session.holdable = func(key: String, _peer: int) -> int:
		if not is_instance_valid(items):
			return 0
		for item: Item in items.items.values():
			if item.network_key() == key:
				return item.bound_to
		return 0
	if venue != null:
		ToyItem.shown = venue.venue_id()
	studio_set.add_child(items)
	if venue != null:
		items.boards = venue.dart_boards()
		items.hoops = venue.hoops()
		items.set_venue(venue.venue_id())
	var shelf: Array[Transform3D] = []
	if venue != null:
		shelf = venue.item_spots()
	_dress_venue_bars()
	items.set_spots(shelf, _item_homes())
	var mic := items.items.get(&"mic") as MicItem
	if mic != null:
		mic.live_changed.connect(func(live: bool) -> void:
			if live:
				mic_arm.take()
			else:
				mic_arm.let_go())
	var phones := items.items.get(&"headphones") as HeadphonesItem
	if phones != null:
		phones.worn_changed.connect(_on_phones_changed)
		phones.state_changed.connect(func(_s: Item.State) -> void: _on_phones_changed())
	var tablet := items.items.get(&"tablet") as TabletItem
	if tablet != null:
		tablet.mix = personal
		tablet.colour = _colour_of(Session.local_peer_id)
		tablet.patch_asked.connect(_on_patch_asked)
		tablet.on_air_asked.connect(_on_air_asked)
	personal.changed.connect(_on_personal_changed)
	_wire_miniature()
	their_keys = TheirKeys.new()
	their_keys.name = "TheirKeys"
	add_child(their_keys)
	Session.note_played.connect(their_keys.play)
	# A guest's keys, live on the instrument plugin of the track they play into.
	var guest_play := GuestPlay.new()
	guest_play.name = "GuestPlay"
	add_child(guest_play)
	Session.control_played.connect(their_keys.control)
	their_monitor = TheirMonitor.new()
	their_monitor.name = "TheirMonitor"
	add_child(their_monitor)
	ear = EarCue.new()
	ear.name = "EarCue"
	add_child(ear)
	Session.note_played.connect(their_monitor.play)
	Session.control_played.connect(their_monitor.control)
	console.rebuilt.connect(_show_patches)
	# A rack's OUT is made again with the rack, and shows the plugs in it again.
	if rack != null:
		rack.rebuilt.connect(_show_patches)
	Session.roster_changed.connect(_on_roster_for_patches)
	_show_patches()
	items.asked.connect(_on_items_asked)
	items.refused.connect(_on_item_refused)
	items.used.connect(func(item: Item, down: bool) -> void: Session.send_item_use(item.id, down, item.use_take))
	# What the sampler catches (slice 26): a use or a hit by a hand here, or anyone's the host hears.
	items.used.connect(_sample_use_here)
	items.rang.connect(_sample_ring)
	Session.item_used.connect(_on_someones_use)
	Session.item_hit.connect(_on_someones_hit)
	items.personal_taken.connect(_on_item_personal_taken)
	hit_recorder = HitRecorder.new()
	hit_recorder.name = "HitRecorder"
	add_child(hit_recorder)
	# Every hit's one song position is read from the take's own stamp (InstrumentItem.clock).
	InstrumentItem.clock = hit_recorder.stamp
	# The shelf tags of the hand percussion say SNAP while this player snaps, and in a headset how
	# a bare hand holds one.
	InstrumentItem.snapping = HitRecorder.snaps
	InstrumentItem.hands_hint = medium != Presentation.Medium.SCREEN
	hit_recorder.unarmed.connect(func() -> void:
		Session.notice.emit("Arm a track to record the percussion: hits are only heard until one is."))
	# A fixed instrument is struck where it stands: by a hand or a controller crossing its head here.
	strike = Strike.new()
	strike.name = "Strike"
	add_child(strike)
	# This player's own hits a few milliseconds after the hand, where the helper can run.
	InstrumentItem.fast_path = _hit_on_fast_path
	InstrumentItem.fast_latency = _fast_path_latency
	_start_hit_voices()
	jacks = Jacks.new()
	jacks.name = "Jacks"
	jacks.recorder = hit_recorder
	add_child(jacks)
	jacks.asked.connect(_on_plug_asked)
	# A cable into a bandmate ends at their ghost's glove; one into this player plays their keys.
	jacks.far_end = func(peer: int, from: Vector3) -> Variant:
		return presence.cable_end(peer, from) if presence != null else null
	jacks.keys = Session.guest_midi
	Session.jack_played.connect(jacks.received)
	Session.jack_check = _jack_refusal
	Session.participant_left.connect(_on_jack_player_left)
	_wear_wrist_jacks()
	# The sockets made before there were jacks to ask: shown now.
	jacks.show_all()
	items.child_exiting_tree.connect(_on_item_leaving)
	items.played.connect(_on_item_played)
	keytar_keys = KeyCatcher.new()
	keytar_keys.name = "KeytarKeys"
	add_child(keytar_keys)
	# The keytar's piano plays the player's keys as the keytar (GuestMidi.instruments).
	keytar_keys.note_on.connect(func(pitch: int, velocity: int) -> void:
		if Session.guest_midi != null:
			Session.guest_midi.note_on(pitch, velocity, 0, 0.0, false, &"keytar"))
	keytar_keys.note_off.connect(func(pitch: int) -> void:
		if Session.guest_midi != null:
			Session.guest_midi.note_off(pitch, 0, 0.0, false, &"keytar"))
	var keytar := items.items.get(&"keytar") as KeytarItem
	if keytar != null:
		keytar.wants_keys.connect(func() -> void: _keytar_play(true))
	if Session.guest_midi != null:
		Session.guest_midi.key.connect(_on_key_played)
		# Everything this player's keys send, from every source, into their loop while they loop.
		Session.guest_midi.sends.connect(_on_keys_sent)
	Session.participant_left.connect(_on_looper_player_left)
	items.moved.connect(_on_item_moved)
	if presence != null:
		presence.items = items
	# AR makes no items while playing: no rack, no shelf to keep them on.
	if medium != Presentation.Medium.AR:
		_wire_made_items()


# --- made items: cassettes (docs/spatial_loop.md part two, slice 23) ------------------------
#
# A clip pulled out of the timeline is a cassette in the hand that pulled it: minted by the host
# (ItemRoom.mint) from its own song, its data sent once (Session.publish_made) and named by id in
# the room. A guest's pull is an ask (`make`) and a blank cassette in its hand until the host's
# arrives there or the ask is refused. Handed over: thrown, held by a bandmate's glove
# (GIVE_REACH, GIVE_HOLD), or clicked on their ghost at a desk; the room's `give` puts it in their
# hand. Shelved on the rack's slots, binned in its BIN. Pressed onto a lane, a strip or a stage voice,
# pasted there (slice 24): the host's own at once, a guest's asked by id with the room's `paste`.

func _wire_made_items() -> void:
	items.made = Session.made
	items.authority = Session.is_authority
	items.made_home = _made_home
	items.press_ahead = _press_ahead
	items.minted.connect(_on_minted)
	items.unmade.connect(_on_unmade)
	items.told.connect(_on_items_told)
	items.used.connect(_on_item_used_here)
	items.paste_pressed.connect(_on_paste_pressed)
	items.resized.connect(_on_brick_resized)
	Session.made_changed.connect(_on_made_changed)
	Session.holds_changed.connect(_take_given_soon)
	if timeline != null:
		timeline.clip_pulled.connect(_on_clip_pulled)
	_hold_the_rack()
	_restore_made()


## Something in the room moved: told to the room, and a made item's place kept with the layout.
func _on_item_moved(item: Item) -> void:
	_publish_room_soon()
	if ItemRoom.is_made(item.id) and Session.is_authority():
		_remember_made_soon()


func _on_items_told(text: String) -> void:
	Session.notice.emit(text)


## Minted here, on the host: its row to everyone once, and kept with this host's layout.
func _on_minted(item: Item) -> void:
	Session.publish_made(item.id)
	_remember_made()
	_publish_room_soon()


## Binned here, on the host: gone everywhere, row and all.
func _on_unmade(id: StringName) -> void:
	Session.drop_made(id)
	Session.notice.emit("Binned %s." % _made_name(id))
	_remember_made()
	_publish_room_soon()


func _made_name(id: StringName) -> String:
	var kind := ItemRoom.kind_of(id)
	return "%s %s" % ["chord brick" if kind == ChordBrick.KIND else String(kind), String(id).trim_prefix(String(kind))]


## A guest heard the host take a made item away: here too.
func _on_made_changed(id: StringName, gone: bool) -> void:
	if gone and items != null:
		items.forget_made(id)


## A hand here pulled track `track`'s item `index` out of the timeline: the host's own pull is a
## cassette in that hand at once; a guest's is an ask, and a blank one in the hand meanwhile.
func _on_clip_pulled(track: int, index: int, hand: Node) -> void:
	var interactor := hand as Interactor
	if items == null or interactor == null:
		return
	var from := "clip:%d:%d" % [track, index]
	if Session.is_authority():
		var made := _mint_for(CassetteItem.KIND, from, Session.local_peer_id)
		if made != null:
			interactor.pick_up(made)
			_say_cassette(made)
		return
	var seq := _predict(&"make", [CassetteItem.KIND, from])
	if seq > 0:
		var look := ItemRoom.look_of(CassetteItem.KIND)
		look.top_level = true
		look.name = "MakingCassette"
		add_child(look)
		_making.append({"seq": seq, "hand": interactor, "look": look})
		Session.notice.emit("Asking %s for a cassette of it..." % Session.name_of(1))


## A made item of `kind`, of what `from` names in the host's own song, made by `maker`: minted, or
## null with `maker` told why not.
func _mint_for(kind: StringName, from: String, maker: int) -> Item:
	if items == null:
		return null
	var made := items.mint(kind, ItemRoom.made_data(kind, from), maker)
	if made == null:
		Session.tell(maker, items.mint_refusal)
	return made


## Made item `made`, just minted for `maker`'s pull: in their hand, everywhere.
func _hand_made(made: Item, maker: int) -> void:
	if maker == Session.local_peer_id:
		var hand := _free_hand()
		if hand != null:
			hand.pick_up(made)
	else:
		Session.hand_to(maker, made.network_key())
	_publish_room_soon()


## How a cassette just put in a hand is used, said once. A tracked bare hand has no trigger, so it is
## told only of the push (Interactor.paste_press_words).
func _say_cassette(made: Item) -> void:
	var desk := medium == Presentation.Medium.SCREEN
	var press := made.carried_by.paste_press_words() if is_instance_valid(made.carried_by) else "a press"
	Session.notice.emit(("%s is in your hand: hold L to hear it; click a timeline lane, a strip or a stage voice to paste it, a bandmate to hand it over, a rack slot to shelve it; Q puts it down."
			if desk else "%s is in your hand: hold it to your ear to hear it; " + press + " on a timeline lane, a strip or a stage voice pastes it; hold it by a bandmate's glove to hand it over, let it go by a rack slot to shelve it.")
			% made.item_title().capitalize())


## The blank cassettes waiting in hands follow them.
func _follow_making() -> void:
	for m: Dictionary in _making:
		var hand := m["hand"] as Interactor
		var look := m["look"] as Node3D
		if is_instance_valid(hand) and is_instance_valid(look):
			look.global_transform = hand.carry_pose() * Transform3D(Basis(Vector3.UP, PI), Vector3(0, -0.01, 0))


## The host has answered every pull up to `answered`: each one's blank cassette goes, and its hand
## waits for the made one the holds put there (`_take_given`); a refused one's hand waits for
## nothing, and the host has said why.
func _settle_makes(answered: int) -> void:
	var still: Array = []
	for m: Dictionary in _making:
		if int(m["seq"]) > answered:
			still.append(m)
			continue
		if is_instance_valid(m["look"]):
			(m["look"] as Node3D).queue_free()
		_awaiting_hands.append(m["hand"])
	_making = still
	_take_given()
	_awaiting_hands.clear()


func _take_given_soon() -> void:
	_take_given.call_deferred()


## Whatever the holds say is in this player's hand and no hand here has yet: a made item minted
## for this guest's pull, or something handed over. Into the hand that pulled it, else a free one.
func _take_given() -> void:
	if items == null or not is_inside_tree():
		return
	var pending := {}
	for p in _predictions:
		if p["verb"] in [&"put_item", &"home_item", &"throw_item", &"slot_item", &"give"]:
			pending[p["args"][0]] = true
	for id in items.items:
		var item: Item = items.items[id]
		if item.carried_by != null or pending.has(id) or not ItemRoom.is_made(id) \
				or Session.holder_of(item.network_key()) != Session.local_peer_id \
				or not (item.is_held_elsewhere() or item.state == Item.State.HOME):
			continue
		var hand: Interactor = null
		while hand == null and not _awaiting_hands.is_empty():
			var waiting = _awaiting_hands.pop_front()
			if is_instance_valid(waiting) and (waiting as Interactor).carrying == null:
				hand = waiting
		if hand == null:
			hand = _free_hand()
		if hand != null:
			hand.pick_up(item)


## A hand of this player's with nothing in it: the mouse's on a desktop, else an empty controller
## or hand, else the mouse's or the first, whose pick-up pockets what it has.
func _free_hand() -> Interactor:
	var first: Interactor = null
	for node in get_tree().get_nodes_in_group(Interactor.GROUP):
		var hand := node as Interactor
		if hand == null or not hand.is_inside_tree():
			continue
		if hand.carrying == null:
			return hand
		if first == null:
			first = hand
	return first


## Hand `item`, in a hand here, to `peer`: at once on the host; a guest asks, and its glove lets go
## into theirs meanwhile.
func give_item(item: Item, peer: int) -> void:
	if peer <= 0 or peer == Session.local_peer_id or not Session.participants.has(peer):
		return
	if Session.is_authority():
		_give(item, peer, Session.local_peer_id)
		return
	if item.carried_by != null:
		item.carried_by.lose_carrying()
	if presence != null:
		item.follow(presence.palm_of(peer, item))
	_predict(&"give", [item.id, peer])
	Session.notice.emit("Handed %s to %s." % [_given_name(item), Session.name_of(peer)])


## The host hands `item` from `from` to `peer`: out of a hand here if one has it, into theirs.
func _give(item: Item, peer: int, from: int) -> void:
	if item.carried_by != null:
		item.carried_by.lose_carrying()
	# The table first: the hand that takes it here then finds it already this player's.
	Session.hand_to(peer, item.network_key())
	if peer == Session.local_peer_id:
		var hand := _free_hand()
		if hand != null:
			hand.pick_up(item)
	var what := _given_name(item)
	Session.tell(peer, "%s handed you %s." % [Session.name_of(from), what])
	if from == Session.local_peer_id:
		Session.notice.emit("Handed %s to %s." % [what, Session.name_of(peer)])
	_publish_room_soon()


## A cassette pressed onto `track` at `seconds` by a hand here (ItemRoom.paste_pressed;
## docs/spatial_loop.md part two, slice 24): the host pastes it at once; a guest asks with the room's
## `paste` [id, track, time], and the host pastes the clip it holds. The cassette stays in the hand.
func _on_paste_pressed(item: Item, track: int, seconds: float) -> void:
	if item is ChordBrick:
		press_brick(item as ChordBrick, track, seconds)
		return
	var cassette := item as CassetteItem
	if cassette == null or not cassette.pastes():
		return
	if Session.is_authority():
		paste_cassette(cassette, track, seconds, Session.local_peer_id)
		return
	if _predict(&"paste", [cassette.id, track, seconds]) > 0:
		var t := DAW.state.track(track, false)
		Session.notice.emit("Asking %s to paste the %s cassette onto %s at %s..." % [Session.name_of(1),
				cassette.clip_name(), t.display_name() if t != null else "track %d" % track, DAW.state.bar_beat(seconds)])


## The host pastes `cassette`'s clip onto `track` at `seconds` for `who` (this machine's own peer, or
## the guest who asked): one undo step that is theirs, or refused with the reason. Both are told; the
## host as well when it is a guest's, since an item appearing on its timeline unannounced is a
## surprise mid-session.
func paste_cassette(cassette: CassetteItem, track: int, seconds: float, who: int) -> void:
	var why := DAW.paste_item(track, seconds, cassette.clip)
	if not why.is_empty():
		Session.tell(who, why)
		return
	var said := "the %s cassette onto %s at %s" % [cassette.clip_name(), DAW.state.track(track).display_name(),
			DAW.state.bar_beat(seconds)]
	Session.tell(who, "Pasted %s." % said)
	if who != Session.local_peer_id:
		Session.notice.emit("%s pasted %s." % [Session.name_of(who), said])


## What a hand-over toast calls `item`: a cassette by its clip's name as the song has it ("the
## Kick verse 1 cassette"), anything else by its title.
func _given_name(item: Item) -> String:
	var cassette := item as CassetteItem
	if cassette != null:
		return "the %s cassette" % cassette.clip_name()
	var brick := item as ChordBrick
	if brick != null:
		return "the %s chord brick" % brick.chord
	return item.item_title().to_lower()


# --- chord bricks (docs/spatial_loop.md part two, slice 31) -----------------------------------
#
# The fifths wheel feeds them: a strip tile pulled off it is a brick of its chord in the hand that
# pulled it, and MAKE BRICKS makes the strip as bricks at the end of the ledge's row. Both are made
# items the host mints (`make`, "chord:<key>:<chord>" and "ledge:<key>:<chord>"). A brick's length
# is the room's row `bricks` {id: bars}, its nudge; a guest's is the room's ask `bricks`. Pressed
# into a track it writes its row's block chords as one take (a guest's is the take's intent, as any
# take is); into a section block, its row's harmony at that section's marker (a guest's is the
# wheel's `harmony` ask).

## Every chord brick's length, {id: bars}: the room's row.
func _bricks_row() -> Dictionary:
	var out := {}
	if items != null:
		for id in items.items:
			var brick := items.items[id] as ChordBrick
			if brick != null:
				out[id] = brick.bars
	return out


## The host's row of brick lengths, here: each brick its length, but one this guest has nudged and
## not heard back about.
func _apply_bricks(row: Dictionary) -> void:
	var pending := {}
	for p in _predictions:
		if p["verb"] == &"bricks":
			pending[p["args"][0]] = true
	for id in row:
		var brick := items.items.get(StringName(id)) as ChordBrick
		if brick != null and not pending.has(StringName(id)) and int(row[id]) in ChordBrick.LENGTHS:
			brick.bars = int(row[id])


## A brick's length nudged by a hand here: the host's room is told; a guest asks.
func _on_brick_resized(item: Item, bars: int) -> void:
	if Session.is_authority():
		_remember_made_soon()
		_publish_room_soon()
	else:
		_predict(&"bricks", [item.id, bars])


## Brick `made`, just minted for `maker`'s MAKE BRICKS: at the end of the ledge's row, or, the ledge
## full, left on its tray and they are told. Whether it went on the ledge.
func _onto_ledge(made: ChordBrick, maker: int) -> bool:
	var n := items.next_in_order(ChordBrick.LEDGE) if items.holders.has(ChordBrick.LEDGE) else -1
	if n < 0:
		Session.tell(maker, "The ledge is full: the %s brick is on its tray. Bin some, or press CLEAR." % made.chord)
		_publish_room_soon()
		return false
	items.slot(made, ChordBrick.LEDGE, n)
	_publish_room_soon()
	return true


## The wheel's MAKE BRICKS: a brick of each of `chords`, in `key`, at the end of the ledge's row. The
## host's are minted at once; a guest asks for each.
func make_bricks(chords: PackedStringArray, key: String) -> void:
	if items == null or chords.is_empty():
		return
	if not Session.is_authority():
		for c in chords:
			_predict(&"make", [ChordBrick.KIND, ChordBrick.from_text(true, key, c)])
		Session.notice.emit("Asking %s for chord bricks of %s on the ledge..." % [Session.name_of(1), " ".join(chords)])
		return
	var made := PackedStringArray()
	for c in chords:
		var brick := _mint_for(ChordBrick.KIND, ChordBrick.from_text(true, key, c), Session.local_peer_id) as ChordBrick
		if brick == null or not _onto_ledge(brick, Session.local_peer_id):
			break
		made.append(c)
	if not made.is_empty():
		var desk := medium == Presentation.Medium.SCREEN
		Session.notice.emit(("Made %s as chord bricks on the ledge: %s." % [" ".join(made),
				"click one to take it, then click a lane, a strip or a section block to write the row; the wheel over one makes it 1, 2 or 4 bars"
				if desk else "take one and press it into a lane, a strip or a section block to write the row; turn one in your hand, or the stick over it, for 1, 2 or 4 bars"]))


## A hand here pulled a strip tile off the wheel: the host's own is a brick of it in that hand at
## once; a guest's is an ask, and a blank brick in the hand meanwhile.
func _on_brick_pulled(chord: String, key: String, hand: Node) -> void:
	var interactor := hand as Interactor
	if items == null or interactor == null:
		return
	var from := ChordBrick.from_text(false, key, chord)
	if Session.is_authority():
		var made := _mint_for(ChordBrick.KIND, from, Session.local_peer_id)
		if made != null:
			interactor.pick_up(made)
			_say_brick(made as ChordBrick)
		return
	var seq := _predict(&"make", [ChordBrick.KIND, from])
	if seq > 0:
		var look := ItemRoom.look_of(ChordBrick.KIND)
		look.top_level = true
		look.name = "MakingBrick"
		add_child(look)
		_making.append({"seq": seq, "hand": interactor, "look": look})
		Session.notice.emit("Asking %s for a chord brick of %s..." % [Session.name_of(1), chord])


## How a brick just put in a hand is used, said once.
func _say_brick(made: ChordBrick) -> void:
	var desk := medium == Presentation.Medium.SCREEN
	var press := made.carried_by.paste_press_words() if is_instance_valid(made.carried_by) else "a press"
	Session.notice.emit(("The %s chord brick is in your hand: click a timeline lane, a strip or a stage voice to write it there, a section block for its harmony, the ledge to stand it in the row; Q puts it down."
			if desk else "The %s chord brick is in your hand: " + press + " on a timeline lane, a strip or a stage voice writes it there, on a section block its harmony; let it go by the ledge to stand it in the row.")
			% made.chord)


## A chord brick pressed by a hand here (ItemRoom.paste_pressed): its row (ChordBrick.row_of: the
## ledge's, when it was taken from there) written. Into a track: its block chords from the bar of
## `seconds` (the lane's bar, or the playhead's), one take named ChordBrick.TAKE_NAME, one undo step;
## a guest's is the take's intent. Into a section block (`track` ChordBrick.SECTION, `seconds` its
## start): the row's harmony at that section's bar, by the wheel's SET (FifthsWheel.write), or a
## guest's `harmony` ask. The brick stays in the hand.
func press_brick(brick: ChordBrick, track: int, seconds: float) -> void:
	var s := DAW.state
	if s == null or brick == null or not brick.pastes():
		return
	var row := ChordBrick.row_of(brick)
	var chords := ChordBrick.chords_text(row)
	if track == ChordBrick.SECTION:
		var r := s.region_at(seconds + 0.001)
		var section := str(s.regions[r][2]) if r >= 0 else "the section at %s" % s.bar_beat(seconds)
		var asked := ChordBrick.section_ask(row, s, seconds)
		if not Session.is_authority():
			brick_asked = [FifthsWheel.VERB, asked]
			Session.ask_room(FifthsWheel.VERB, asked)
			Session.notice.emit("Asked %s to put %s in [%s]." % [Session.name_of(1), section, asked[1]])
			return
		var named := FifthsWheel.write(asked[0], asked[1])
		Session.notice.emit("%s is in [%s] now: the harp, the bells and the fingertips follow it there." % [section, asked[1]]
				if named != "" else "Those bricks do not read as a key and chords.")
		return
	var why := ChordBrick.write_refusal(s, track)
	if not why.is_empty():
		Session.notice.emit(why)
		return
	var first := ChordBrick.bar_of(s, seconds)
	var span := ChordBrick.span_of(row, s, first)
	DAW.insert_midi_take(track, span[0], span[1], ChordBrick.notes_of(row, s, first), ChordBrick.TAKE_NAME)
	var said := "%s (%d bars) onto %s from bar %d" % [chords, ChordBrick.bars_in(row), s.track(track).display_name(), first + 1]
	Session.notice.emit(("Wrote %s." if Session.is_authority() else "Asked %s to write %%s." % Session.name_of(1)) % said)


## A click with a made item in the mouse's hand and nothing under the cursor: on a bandmate's
## ghost, it is theirs.
func _on_item_used_here(item: Item, down: bool) -> void:
	if not down or presence == null or not ItemRoom.is_made(item.id) or not (item.carried_by is MouseInteractor):
		return
	var aim := item.carried_by.aim()
	var peer := presence.peer_at(aim.origin, -aim.basis.z)
	if peer != 0:
		give_item(item, peer)


# --- the grain cloud (docs/spatial_loop.md part two, slice 54) -------------------------------
#
# Its KEY switch is the room's row `grains_key`: a guest's press is the room's ask `grains_key` [on],
# shown at once here; the host's is done. What this player's cloud plays goes to the band and, while the
# song records, into a take (Session.send_grains, GrainTakes); a bandmate's plays here (GrainCloud.hear).

## An event this player's grain cloud played (slice 55): to the band, and into a take while the song
## records (Session.send_grains), at the song as this player hears it, moved on by the cloud's figure.
func _on_grains_played(e: PackedFloat32Array) -> void:
	Session.send_grains(e, Session.grain_takes.song())


## A bandmate's grain event (Presence.grains_heard): played from this grain cloud's sound.
func _on_grains_heard(peer: int, e: PackedFloat32Array) -> void:
	if grain_cloud != null and is_instance_valid(grain_cloud):
		grain_cloud.hear(peer, e)


func _forget_grains_player(peer: int) -> void:
	if grain_cloud != null and is_instance_valid(grain_cloud):
		grain_cloud.forget(peer)


## The grain cloud's sound here (mono at GrainVoice.RATE), empty while it has none: what the host
## renders a take on it from (GrainTakes.sound).
func grains_sound() -> PackedFloat32Array:
	if grain_cloud == null or not is_instance_valid(grain_cloud) or grain_cloud.source != GrainCloud.Source.READY:
		return PackedFloat32Array()
	return grain_cloud.voice.source


## A hand here pressed the grain cloud's KEY: on to follow the chord's root, off for its own pitch.
func _on_grains_key_pressed(on: bool) -> void:
	if Session.is_authority():
		_set_grains_key(on)
	elif _predict(GrainCloud.VERB, [on]) > 0:
		_show_grains_key(on)
	Session.notice.emit("Grain cloud: KEY on. Its grains follow the chord's root, for everyone's cloud." if on
			else "Grain cloud: KEY off. Its grains are at the sound's own pitch.")


## The room's word on KEY: shown here and told to the room.
func _set_grains_key(on: bool) -> void:
	_show_grains_key(on)
	_publish_room_soon()


## KEY shown as the room has it, on this cloud and any stood later.
func _show_grains_key(on: bool) -> void:
	grains_key = on
	if grain_cloud != null and is_instance_valid(grain_cloud):
		grain_cloud.key_on = on


# --- the weather (docs/spatial_loop.md part two, slice 44) ----------------------------------
#
# The switch is the room's row `weather`: a guest's press is the room's ask `weather` [on], shown at
# once here; the host's is done. Every machine schedules the same drops from its own song clock, so
# nothing else crosses the wire: the host alone records them, onto the track the jack goes into.

## A hand here pressed the weather's switch: `on` for LISTEN, off for OFF.
func _on_weather_pressed(on: bool) -> void:
	if Session.is_authority():
		_set_weather(on)
	elif _predict(Weather.VERB, [on]) > 0:
		_show_weather(on)
	var what := str(weather.spec.get("title", "the weather")).to_lower() if weather != null else "the weather"
	var said := what.left(1).to_upper() + what.substr(1)
	Session.notice.emit("%s: LISTEN. Each drop is a note of the song's scale, %s, heard by everyone. Its jack records them onto a track." \
			% [said, Weather.pitch_of(weather.spec if weather != null else {})] if on else "%s: OFF. The drops fall silent." % said)


## The room's word on the switch: LISTEN or OFF, shown here and told to the room.
func _set_weather(on: bool) -> void:
	_show_weather(on)
	_publish_room_soon()


## The switch shown as the room has it, on this weather and any stood later.
func _show_weather(on: bool) -> void:
	weather_listening = on
	if weather != null and is_instance_valid(weather):
		weather.listening = on


## A drop landed (Weather.dropped): its jack's lead shows it, and the host records it onto the track
## the jack goes into, heard or not. Every machine has the same drop, so only one takes it down.
func _on_weather_dropped(drop: Dictionary) -> void:
	if jacks == null:
		return
	var source := StringName(drop["source"])
	var track := Jack.track_of(jacks.sink_of(source))
	if track <= 0:
		return
	jacks.heard_from(source, int(drop["velocity"]))
	if Session.is_authority() and hit_recorder != null and Jacks.takes_midi(track):
		hit_recorder.note(track, int(drop["note"]), int(drop["velocity"]), InstrumentItem.MELODIC_CHANNEL,
				float(drop["length"]), float(drop["song"]))


# --- the looper (docs/spatial_loop.md part two, slice 45) -----------------------------------
#
# Who is looping is the room's row `looper` [peer, from_bar, bars]: a guest's slap is the room's ask
# `looper` [from_bar, bars], shown at once here; the host's is answered (Looper.answer). The layer is
# taken down where it is played, by the song as its player hears it, and written on the host: a
# guest's sent whole (`looper_layer`), for the host to put on a track of theirs.

## What a player is called on the looper's screen and their tracks: their name, or this player's own.
func _looper_name(peer: int) -> String:
	if peer == Session.local_peer_id and Session.local_name != "":
		return Session.local_name
	return Session.name_of(peer)


## A hand here slapped the looper's pad: armed (the host's own at once, a guest's asked and shown),
## refused while somebody else loops, called off during this player's own count.
func _on_looper_slapped() -> void:
	if looper == null:
		return
	var me := Session.local_peer_id
	var why := Looper.refusal(looper_row, me, _looper_name)
	if why != "":
		Session.notice.emit("%s: one player at a time. Slap again when their layer is done." % why)
		return
	if not looper_row.is_empty():
		if looper.phase == Looper.Phase.COUNT:
			_on_looper_called_off()
			Session.notice.emit("Loop called off.")
		elif looper.phase == Looper.Phase.REC:
			Session.notice.emit("Recording your layer: it ends at bar %d." % (int(looper_row[1]) + int(looper_row[2])))
		return
	var plan := Looper.plan(DAW.state, looper.heard(), looper_length)
	# Read before the answer, which sets the loop for a first layer.
	var stacking := Looper.loop_set(DAW.state)
	if Session.is_authority():
		_answer_looper(plan[0], plan[1], me)
	elif _predict(Looper.VERB, plan) > 0:
		_show_looper([me, plan[0], plan[1]])
	var bars := int(plan[1])
	Session.notice.emit(("Stacking a layer: the rest of this pass counts in, then %d bar%s of everything you play." \
			if stacking else "Looping: a bar's count, then %d bar%s of everything you play, keys and hits, as a layer of your own.") \
			% [bars, "" if bars == 1 else "s"])


## Host: `from`'s slap (theirs asked, or this player's own): Looper.answer against the room's row, and
## the row told to the room. A refusal is told to them; their own screen goes back with the room.
func _answer_looper(from_bar: int, bars: int, from: int) -> void:
	var out := Looper.answer(looper_row, from_bar, bars, from, _looper_name)
	if bool(out["refused"]):
		Session.tell(from, "%s One player at a time." % out["said"])
	_show_looper(out["row"])
	_publish_room_soon()


## This player's layer is taken down (Looper.layer_done): the host's written at once, a guest's sent.
func _on_looper_layer(start: float, end: float, notes: Array) -> void:
	if Session.is_authority():
		_write_looper_layer(start, end, notes, Session.local_peer_id)
	elif _predict(Looper.LAYER_VERB, [start, end, notes]) > 0:
		_show_looper([])


## Host: `from`'s layer onto a track of theirs (Looper.write_layer), their row cleared. A layer with
## nothing played in it makes no track. Only the row's own player's, and only while it is theirs; and
## it goes where the row says, over the row's bars as the host has them (Looper.span_of), not where
## the layer says it began and ended, with only the notes begun inside them (Looper.inside).
func _write_looper_layer(_start: float, _end: float, notes: Array, from: int) -> void:
	if looper_row.is_empty() or int(looper_row[0]) != from:
		return
	var span := Looper.span_of(looper_row, DAW.state)
	_show_looper([])
	_publish_room_soon()
	var kept := Looper.inside(notes, span).slice(0, MidiTake.MAX_NOTES)
	if kept.is_empty():
		Session.tell(from, "Nothing was played into the loop, so there is no layer. Slap again to try another.")
		return
	var made := Looper.write_layer(_looper_name(from), float(span[0]), float(span[1]), kept)
	Session.tell(from, "%s: %d note%s on a track of its own in the LOOPER folder. Slap again while it loops to stack another." \
			% [made["name"], kept.size(), "" if kept.size() == 1 else "s"])


## This player's count or layer was cut short (the transport stopped, the riser gone): their row
## cleared, by the host or asked of it.
func _on_looper_called_off() -> void:
	if Session.is_authority():
		_answer_looper(0, 0, Session.local_peer_id)
	elif _predict(Looper.VERB, [0, 0]) > 0:
		_show_looper([])


## The room's row on this looper and any stood later.
func _show_looper(row: Array) -> void:
	looper_row = row.duplicate()
	if looper != null and is_instance_valid(looper):
		looper.row = looper_row


## What this player's keys send, into their loop while they loop.
func _on_keys_sent(kind: int, pitch: int, velocity: int, song: float, channel: int) -> void:
	if looper != null and is_instance_valid(looper):
		looper.key(kind, pitch, velocity, song, channel)


## Host: whoever was looping left: nobody is now.
func _on_looper_player_left(peer: int) -> void:
	if Session.is_authority() and not looper_row.is_empty() and int(looper_row[0]) == peer:
		_show_looper([])
		_publish_room_soon()


# --- the music box (docs/spatial_loop.md part two, slice 47) --------------------------------
#
# TRACK, LENGTH, ROOT and SCALE are the room's row `music_box`: a guest's key is the room's ask
# `music_box` [track, length, root, chromatic], shown at once here; the host's is done. The pegs are
# its track's item in the mix, written by DAW.insert_note and delete_note like any edit, so nothing
# else of it crosses the wire.

## A key here asked for the row to be `wanted`.
func _on_music_box_asked(wanted: Array) -> void:
	if Session.is_authority():
		_set_music_box(wanted)
	elif _predict(MusicBox.VERB, wanted) > 0:
		_show_music_box(wanted)


## The room's word on the music box's row: `wanted`, if it is one the host keeps (MusicBox.clean),
## shown here and told to the room.
func _set_music_box(wanted: Array) -> void:
	var row := MusicBox.clean(wanted, DAW.state)
	if row.is_empty():
		return
	_show_music_box(row)
	_publish_room_soon()


## The row shown as the room has it, on this box and any stood later.
func _show_music_box(row: Array) -> void:
	if row.size() != 4:
		return
	music_box_row = row.duplicate()
	if music_box != null and is_instance_valid(music_box):
		music_box.row = music_box_row


# --- strings across the room (docs/spatial_loop.md part two, slice 48) ----------------------
#
# The strings are the room's row `strings` {id: [a, b, maker]}: a guest's tie or cut is the room's ask
# `string` [id, a, b] (a and b the same point to cut), shown at once here; the host's is done. Each
# string is stood from the row on every machine; its plucks are this player's keys, and a bandmate's
# arrive as notes, heard from the string that plays them (`_on_string_heard`).

## The spool (RoomString.Spool), in the venue's own frame at its spot: a child of the venue, so it
## goes with it, its trolley the studio's. Then the room's strings stood again in this venue.
func _stand_the_spool() -> void:
	spool = null
	var spot: Variant = Stations.spot(venue, RoomString.STATION)
	if spot != null:
		spool = RoomString.Spool.new()
		spool.transform = spot
		spool.bounds = _string_bounds
		spool.count = func() -> int: return strings_row.size()
		spool.string_asked.connect(_on_string_asked)
		spool.told.connect(func(text: String) -> void: Session.notice.emit(text))
		venue.add_child(spool)
	# The old venue's strings went with it.
	room_strings.clear()
	_show_strings(strings_row.duplicate())


## What a string's end can meet in this venue, in its frame: the floors a person walks (the rooms
## past the desk and the control room's own), and what stands on them.
func _string_bounds() -> Array:
	if venue == null:
		return [[], []]
	var rooms: Array = venue.rooms().duplicate()
	rooms.append(_room_bounds().grow(0.05))
	return [rooms, venue.solids()]


## The spool's two ends tied by a hand here: a new string, asked of the room.
func _on_string_asked(from_a: Vector3, to_b: Vector3) -> void:
	_strings_tied += 1
	var id := StringName("s%d_%d" % [Session.local_peer_id, _strings_tied])
	while strings_row.has(id):
		_strings_tied += 1
		id = StringName("s%d_%d" % [Session.local_peer_id, _strings_tied])
	ask_string(id, from_a, to_b)


## String `id` tied from `from_a` to `to_b` (the venue's frame), or cut where they are the same point:
## done on the host, asked by a guest and shown at once, or refused here in words where the host
## would refuse it.
func ask_string(id: StringName, from_a: Vector3, to_b: Vector3) -> void:
	if Session.is_authority():
		_answer_string(id, from_a, to_b, Session.local_peer_id)
		return
	var rows := strings_row.duplicate()
	var refusal := RoomString.answer(rows, id, from_a, to_b, Session.local_peer_id)
	if refusal != "":
		Session.notice.emit(refusal)
		return
	if _predict(RoomString.VERB, [id, from_a, to_b]) > 0:
		_show_strings(rows)


## String `id` cut, for everyone.
func cut_string(id: StringName) -> void:
	if strings_row.has(id):
		ask_string(id, Vector3.ZERO, Vector3.ZERO)


## The room's word on a string tied or cut by `from`: the row, told to the room, or why not, to them.
func _answer_string(id: StringName, from_a: Vector3, to_b: Vector3, from: int) -> void:
	var rows := strings_row.duplicate()
	var refusal := RoomString.answer(rows, id, from_a, to_b, from)
	if refusal != "":
		Session.tell(from, refusal)
		return
	var cut := not rows.has(id) and strings_row.has(id)
	_show_strings(rows)
	if cut:
		Session.tell(from, "The string is cut.")
	_publish_room_soon()


## The room's strings as `rows` has them, here: each stood at its ends, the ones gone taken down.
func _show_strings(rows: Dictionary) -> void:
	strings_row = rows.duplicate()
	for id in room_strings.keys():
		var s: RoomString = room_strings[id]
		if not rows.has(id) or s == null or not is_instance_valid(s) or not s.is_inside_tree():
			room_strings.erase(id)
			if s != null and is_instance_valid(s):
				# Out of the room now, so what it rang is let go before anything stands in its place.
				if s.get_parent() != null:
					s.get_parent().remove_child(s)
				s.queue_free()
	if venue == null:
		return
	for id: StringName in rows:
		var row: Array = rows[id]
		var s: RoomString = room_strings.get(id)
		if s == null:
			s = RoomString.new()
			s.id = id
			s.name = "String_%s" % id
			s.a = row[0]
			s.b = row[1]
			s.maker = int(row[2])
			s.cut_asked.connect(cut_string)
			venue.add_child(s)
			room_strings[id] = s
		else:
			s.tie(row[0], row[1], int(row[2]))


## A bandmate's string note (Presence.strings_heard): heard from the string that plays its pitch
## here, or the first one ringing it, if any does.
func _on_string_heard(peer: int, kind: int, pitch: int, velocity: int) -> void:
	var playing: RoomString = null
	for id in room_strings:
		var s: RoomString = room_strings[id]
		if s == null or not is_instance_valid(s):
			continue
		if kind == Session.Note.OFF and s.sounds_for(peer, pitch):
			playing = s
			break
		if playing == null and s.pitch() == pitch:
			playing = s
	if playing != null:
		playing.heard(peer, kind, pitch, velocity)


## The strings in this player's reach (`&"string"` in GuestMidi.instruments) while a hand of theirs
## is on one or carries an end, one they plucked still rings, or they stand at the spool: so the
## synth is up before the first pluck, and a run of plucks is one take.
func _follow_strings() -> void:
	if Session.guest_midi == null:
		return
	var near := spool != null and is_instance_valid(spool) and spool.is_inside_tree() \
			and (spool.carrying() or spool.reel.is_hovered() \
			or Vector2(_standing_at().x - spool.global_position.x, _standing_at().z - spool.global_position.z).length() < ChordHarp.NEAR)
	for id in room_strings:
		var s: RoomString = room_strings[id]
		if s != null and is_instance_valid(s) and (s.touched() or s.ringing()):
			near = true
			break
	Session.guest_midi.reach(RoomString.SOURCE, near)


## The theremin in this player's reach (`&"theremin"` in GuestMidi.instruments) while they stand at
## it, the cursor rests in its field, or it sounds: so the synth is up before the first note, and a
## phrase with rests in it is one take.
func _follow_theremin() -> void:
	if Session.guest_midi == null:
		return
	var near := false
	if theremin != null and is_instance_valid(theremin) and theremin.is_inside_tree():
		var me := _standing_at()
		var at := theremin.global_position
		near = theremin.sounding() or theremin.field.is_hovered() \
				or Vector2(me.x - at.x, me.z - at.z).length() < ChordHarp.NEAR
	Session.guest_midi.reach(Theremin.SOURCE, near)


# --- the marble run (docs/spatial_loop.md part two, slice 49) ------------------------------
#
# The blocks are the room's row `marbles` {cell: [kind, facing]}: a guest's block put in or taken out
# is the room's ask `marble` [cell, kind, facing] (an empty kind to take it out), shown at once here;
# the host's is done. BALL is the room's ask `marble_ball` [beat], kept in the row `marble_balls`.
# Every machine rolls the same marbles from its own song clock and the rows, so nothing else crosses
# the wire: the host alone records the bells, onto the track the run's jack goes into.

## The lyric board (LyricBoard), in the venue's own frame at its spot in the booth: a child of the venue,
## so it goes with it. Its notices are toasts, and its EDIT is `edit_lyrics`.
func _stand_the_lyrics() -> void:
	lyric_board = null
	var spot: Variant = Stations.spot(venue, LyricBoard.STATION)
	if spot == null:
		return
	lyric_board = LyricBoard.new()
	lyric_board.transform = spot
	lyric_board.told.connect(func(text: String) -> void: Session.notice.emit(text))
	lyric_board.edit_asked.connect(edit_lyrics)
	venue.add_child(lyric_board)


## EDIT on the lyric board: in a headset, the typing pad by the singer's hand (LyricBoard.PAD_AT), its
## line added to the end of the lyrics untimed; at a desk, the session panel's LYRICS box, which has
## them all, or where it is when nothing opens it.
func edit_lyrics() -> void:
	if lyric_board == null or not is_instance_valid(lyric_board):
		return
	if get_viewport() != null and get_viewport().use_xr:
		var old := lyric_board.get_node_or_null("TypingPad")
		if old != null:
			old.queue_free()
		var pad := TypingPad.ask(lyric_board, "A line for the lyrics: OK adds it at the end, untimed", "",
				LyricBoard.PAD_AT)
		pad.answered.connect(func(words: String) -> void:
			if lyric_board != null and is_instance_valid(lyric_board):
				lyric_board.add_line(words))
		return
	if lyrics_edit_asked.get_connections().is_empty():
		Session.notice.emit("M opens the session panel: its LYRICS box has the song's lyrics.")
		return
	lyrics_edit_asked.emit()


## The marble run (MarbleRun), in the venue's own frame at its spot in the lattice: a child of the
## venue, so it goes with it. Then the room's blocks and BALL marbles stood again in this venue.
func _stand_the_marbles() -> void:
	marbles = null
	var spot: Variant = Stations.spot(venue, MarbleRun.STATION)
	if spot == null:
		return
	marbles = MarbleRun.new()
	marbles.transform = MarbleRun.frame_at(spot)
	marbles.rows = marbles_row.duplicate()
	marbles.balls = marble_balls.duplicate()
	marbles.block_asked.connect(ask_marble)
	marbles.ball_asked.connect(ask_marble_ball)
	marbles.told.connect(func(text: String) -> void: Session.notice.emit(text))
	marbles.rang.connect(_on_marble_rang)
	venue.add_child(marbles)


## Block `kind` facing `way` in `cell` (an empty kind takes it out): done on the host, asked by a guest
## and shown at once, or refused here in words where the host would refuse it.
func ask_marble(cell: Vector3i, kind: StringName, way: int) -> void:
	if Session.is_authority():
		_answer_marble(cell, kind, way, Session.local_peer_id)
		return
	var rows := marbles_row.duplicate()
	var refusal := MarbleRun.answer(rows, cell, kind, way)
	if refusal != "":
		Session.notice.emit(refusal)
		return
	if _predict(MarbleRun.VERB, [cell, kind, way]) > 0:
		_show_marbles(rows)


## The room's word on a block asked by `from`: the row, told to the room, or why not, to them.
func _answer_marble(cell: Vector3i, kind: StringName, way: int, from: int) -> void:
	var rows := marbles_row.duplicate()
	var refusal := MarbleRun.answer(rows, cell, kind, way)
	if refusal != "":
		Session.tell(from, refusal)
		return
	_show_marbles(rows)
	_publish_room_soon()


## The room's blocks as `rows` has them, here.
func _show_marbles(rows: Dictionary) -> void:
	marbles_row = rows.duplicate()
	if marbles != null and is_instance_valid(marbles):
		marbles.show_rows(rows)


## BALL pressed here with the song playing: a marble on beat `beat`, for everyone.
func ask_marble_ball(beat: float) -> void:
	Session.notice.emit("A marble on the next beat, from the top of the run.")
	if Session.is_authority():
		_answer_marble_ball(beat)
	elif _predict(MarbleRun.BALL_VERB, [beat]) > 0:
		_show_marble_balls(MarbleRun.answer_ball(marble_balls, beat))


## The room's word on a BALL marble: kept with the others, told to the room.
func _answer_marble_ball(beat: float) -> void:
	_show_marble_balls(MarbleRun.answer_ball(marble_balls, beat))
	_publish_room_soon()


## The room's BALL marbles as `held` has them, here.
func _show_marble_balls(held: Array) -> void:
	marble_balls = held.duplicate()
	if marbles != null and is_instance_valid(marbles):
		marbles.balls = held.duplicate()


## A bell rang in the run (MarbleRun.rang): its jack's lead shows it, and the host records it onto the
## track the jack goes into, heard or not. Every machine rings the same bell, so only one takes it
## down; a preview, rolled here alone with the song stopped, is nobody's take.
func _on_marble_rang(r: Dictionary) -> void:
	if jacks == null or r.get("preview", false):
		return
	var track := Jack.track_of(jacks.sink_of(MarbleRun.SOURCE))
	if track <= 0:
		return
	jacks.heard_from(MarbleRun.SOURCE, int(r["velocity"]))
	if Session.is_authority() and hit_recorder != null and Jacks.takes_midi(track):
		hit_recorder.note(track, int(r["note"]), int(r["velocity"]), InstrumentItem.MELODIC_CHANNEL,
				float(r["length"]), float(r["song"]))


# --- the modular wall (docs/spatial_loop.md part two, slice 51) ------------------------------
#
# The patch is the room's row `modular` {cables: [[from, to]], knobs: {id: v}} (Modular): a cable put in
# or pulled is the room's ask `modular_patch` [from, to, song] (an empty `to` pulls), a knob let go the
# ask `modular_knob` [id, v, song], each shown at once here and rolled back if the host refuses it, as
# the patchbay's `patch` is. A knob as it turns is streamed (Session.send_knob, at most
# Session.KNOBS_PER_SECOND), heard where it is made and by bandmates, but never the room's until let
# go. This player's keys play the patch while they stand at the stand (ModularVoice).
#
# Slice 52: a turn is heard here as it is streamed (`_on_knob_streamed`), the same events the band
# hears and a take keeps; each bandmate playing the wall is heard through the room's patch on a voice
# of theirs at it (`modular_heard`, from Presence.modular_heard); and every change of the room's patch
# goes into a take through the modular at the song it was asked at (`_take_modular_change`,
# Session.modular_takes), which the host renders and puts in as audio when it ends.

## Where a player stands to play the wall, in its frame (m): in front of the stand, out to a step
## past the station's seat (1.3), and no wider than the case. Its jacks and knobs take the pointer
## only from here (and only where no other station's seat is nearer, `at_modular`), or while it is
## visited or brought. The harp, the music box and the bells stand within a metre or two of the
## stand: a wider area played the harp's plucks through the patch and put 2 cm jacks under a
## harp player's cursor.
const MODULAR_NEAR := 0.3
const MODULAR_FAR := 1.7
const MODULAR_SIDE := 0.6
## How often the stations' seats are worked out again for `at_modular` (s): a trolley pushed
## moves its seat, but not every frame's worth.
const MODULAR_SEATS_EVERY := 0.5

## Every station's seat here on the floor (global x, z), by id, for `at_modular`, and when they were
## worked out (ms) and for which venue.
var _modular_seats := {}
var _modular_seats_at := -1
var _modular_seats_venue := 0


## The wall, its voice and its computer keys, made once with the surfaces; hung at the venue's spot
## (`_stand_the_modular`). None in AR.
func _build_modular() -> void:
	modular_wall = ModularWall.new()
	modular_wall.name = "ModularWall"
	modular_wall.parks = false
	modular_wall.within_reach = false
	modular_wall.patch = modular_row.duplicate(true)
	studio_set.add_child(modular_wall)
	mount.register(modular_wall)
	modular_wall.patch_asked.connect(ask_modular_patch)
	modular_wall.knob_set.connect(ask_modular_knob)
	# A turn is heard here as it is streamed, not as the hand moves the knob: the same events the
	# band hears and the take keeps (slice 52).
	modular_wall.knob_streamed.connect(_on_knob_streamed)
	modular_wall.told.connect(func(text: String) -> void: Session.notice.emit(text))
	modular_wall.touched.connect(_on_modular_touched)
	modular_wall.keys_asked.connect(func() -> void: _modular_play(not modular_keys.is_active()))
	Session.knob_turned.connect(_on_knob_turned)
	modular_voice = ModularVoice.new()
	modular_voice.name = "ModularVoice"
	modular_voice.keys = Session.guest_midi.synth if Session.guest_midi != null else null
	modular_voice.set_patch(modular_row)
	add_child(modular_voice)
	# Takes through the modular start from the patch as it is heard here; bandmates' keys through it
	# play at the wall (slice 52).
	Session.modular_takes.patch = heard_modular_patch
	if presence != null:
		presence.modular_heard = _on_modular_heard
		presence.modular_control_heard = _on_modular_control_heard
	Session.participant_left.connect(_forget_modular_player)
	Session.role_changed.connect(_on_modular_role_changed)
	modular_keys = KeyCatcher.new()
	modular_keys.name = "ModularKeys"
	modular_keys.base = 48
	add_child(modular_keys)
	modular_keys.note_on.connect(func(pitch: int, velocity: int) -> void: _on_modular_touched(pitch, true, velocity))
	modular_keys.note_off.connect(func(pitch: int) -> void: _on_modular_touched(pitch, false))
	modular_keys.active_changed.connect(func(on: bool) -> void: modular_wall.show_playing(on))
	# The world into it (slice 53).
	modular_world = ModularWorld.new()
	modular_world.weather = func() -> Variant: return weather
	modular_world.marbles = func() -> Variant: return marbles
	modular_world.has_venue = func() -> bool: return venue_instrument != null and is_instance_valid(venue_instrument)
	add_child(modular_world)
	modular_world.fired.connect(_on_world_fired)
	Session.modular_takes.world = modular_world.for_take
	modular_world_voice = ModularVoice.new()
	modular_world_voice.name = "ModularWorldVoice"
	modular_world_voice.speaker = modular_wall
	modular_world_voice.world_only = true
	modular_world_voice.volume_db = -6.0
	modular_world_voice.set_patch(modular_row)
	add_child(modular_world_voice)
	if Session.guest_midi != null:
		Session.guest_midi.key.connect(_on_modular_key)


## The wall, hung at this venue's spot over the stand (Venue.modular_spot), the venue's rack giving way
## to it; put away, and out of F's round, where the venue has none.
func _stand_the_modular() -> void:
	if modular_wall == null or not is_instance_valid(modular_wall) or venue == null:
		return
	var spot: Variant = Stations.spot(venue, Modular.STATION)
	modular_wall.visible = spot != null
	if spot == null:
		if focus != null:
			if focus.focused_id == modular_wall.surface_id:
				focus.release()
			focus.surfaces.erase(modular_wall)
		return
	ZoneKit.yield_rack(venue)
	var at := _venue_to_set(spot as Transform3D)
	mount.seat(modular_wall.surface_id, func() -> Transform3D: return at)
	if focus != null and not focus.surfaces.has(modular_wall):
		focus.surfaces.append(modular_wall)


## The song position a cable or a knob is made at: this player's keys' clock, or -1.
func _modular_song() -> float:
	return Session.guest_midi.song() if Session.guest_midi != null else -1.0


## A cable from `from` into `to`, or with `to` empty the cable at `from` pulled: done on the host, asked
## by a guest and shown at once, or refused here in words where the host would refuse it.
func ask_modular_patch(from: StringName, to: StringName) -> void:
	var song := _modular_song()
	if Session.is_authority():
		_answer_modular_patch(from, to, Session.local_peer_id, song)
		return
	var patch := modular_row.duplicate(true)
	var refusal := Modular.answer_patch(patch, from, to)
	if refusal != "":
		Session.notice.emit(refusal)
		return
	if _predict(Modular.PATCH_VERB, [from, to, song]) > 0:
		_show_modular(patch, song)


## The room's word on a cable asked by `from` at song position `song`: the row, told to the room, or
## why not, to them.
func _answer_modular_patch(cable_from: StringName, to: StringName, from: int, song := -1.0) -> void:
	var patch := modular_row.duplicate(true)
	var refusal := Modular.answer_patch(patch, cable_from, to)
	if refusal != "":
		Session.tell(from, refusal)
		return
	_show_modular(patch, song)
	_publish_room_soon()


## Knob `id` let go at `v`: the room's from now on, done on the host, asked by a guest and kept here.
func ask_modular_knob(id: StringName, v: float) -> void:
	var song := _modular_song()
	if Session.is_authority():
		_answer_modular_knob(id, v, Session.local_peer_id, song)
		return
	var patch := modular_row.duplicate(true)
	var refusal := Modular.answer_knob(patch, id, v)
	if refusal != "":
		Session.notice.emit(refusal)
		return
	if _predict(Modular.KNOB_VERB, [id, v, song]) > 0:
		_show_modular(patch, song)


func _answer_modular_knob(id: StringName, v: float, from: int, song := -1.0) -> void:
	var patch := modular_row.duplicate(true)
	var refusal := Modular.answer_knob(patch, id, v)
	if refusal != "":
		Session.tell(from, refusal)
		return
	_show_modular(patch, song)
	_publish_room_soon()


## The room's patch as `patch` has it, here: on the wall, in this player's voice and every
## bandmate's, with a knob a hand here is still turning kept where its stream has it. What changed
## goes into a take through the modular (Session.modular_takes) at `song`, the song position it was
## asked at (NAN: now, as this player hears it): a cable in or out, and a knob not under a hand here,
## whose stream the take has already.
func _show_modular(patch: Dictionary, song := NAN) -> void:
	var was := modular_row
	modular_row = Modular.clean(patch)
	var turning := modular_wall.turning() if modular_wall != null and is_instance_valid(modular_wall) else {}
	_take_modular_change(was, modular_row, turning, song if is_finite(song) else _modular_song())
	if modular_wall != null and is_instance_valid(modular_wall):
		modular_wall.show_patch(modular_row)
	for voice: ModularVoice in _modular_voices():
		voice.set_patch(modular_row)
		for id: StringName in turning:
			voice.knob(id, _modular_streamed.get(id, turning[id]))


## The room's patch gone from `was` to `now`, into a take through the modular at `song`: each cable
## pulled, then each put in, and each knob moved that no hand here is turning.
func _take_modular_change(was: Dictionary, now: Dictionary, turning: Dictionary, song: float) -> void:
	var before: Array = was.get("cables", [])
	var after: Array = now.get("cables", [])
	for c: Array in before:
		if not after.has(c):
			Session.modular_takes.cable(c[1], &"", song)
	for c: Array in after:
		if not before.has(c):
			Session.modular_takes.cable(c[0], c[1], song)
	var knobs: Dictionary = now["knobs"]
	for id: StringName in knobs:
		if not turning.has(id) and not is_equal_approx(float(knobs[id]), float((was["knobs"] as Dictionary).get(id, -1.0))):
			Session.modular_takes.knob(id, knobs[id], song)


## The modular's patch as it is heard here: the room's, with the knobs as they are being streamed
## (this player's voice has both). What a take through the modular starts from (ModularTakes.patch).
func heard_modular_patch() -> Dictionary:
	return modular_voice.patch if modular_voice != null and is_instance_valid(modular_voice) else modular_row


## This player's voice, every bandmate's and the world's own: all of them play the room's patch.
func _modular_voices() -> Array[ModularVoice]:
	var out: Array[ModularVoice] = []
	if modular_voice != null and is_instance_valid(modular_voice):
		out.append(modular_voice)
	if modular_world_voice != null and is_instance_valid(modular_world_voice):
		out.append(modular_world_voice)
	for peer: int in modular_heard:
		var v: ModularVoice = modular_heard[peer]
		if is_instance_valid(v):
			out.append(v)
	return out


## A knob's turn here as it is streamed (ModularWall.knob_streamed, at most Session.KNOBS_PER_SECOND):
## heard in every voice here, sent to the band and kept in a take, all at once, so what this player
## hears of the turn is what the take renders.
func _on_knob_streamed(id: StringName, v: float) -> void:
	_modular_streamed[id] = v
	for voice: ModularVoice in _modular_voices():
		voice.knob(id, v)
	Session.send_knob(id, v, _modular_song())


## A bandmate's knob as they turn it: on the wall and in every voice here.
func _on_knob_turned(id: StringName, v: float, _from: int, _song: float) -> void:
	if modular_wall != null and is_instance_valid(modular_wall):
		modular_wall.show_knob(id, v)
	for voice: ModularVoice in _modular_voices():
		voice.knob(id, v)


## A bandmate's note through the modular (Presence.modular_heard): played on their voice at the wall,
## made the first time they play it, through the room's patch. Their last note let go rests their
## wheel, as it does on their end.
func _on_modular_heard(peer: int, kind: int, pitch: int, velocity: int) -> void:
	if kind != Session.Note.ON and kind != Session.Note.OFF:
		return
	var voice := _modular_voice_of(peer, kind == Session.Note.ON)
	if voice == null:
		return
	var held: Dictionary = _modular_heard_held.get(peer, {})
	if kind == Session.Note.ON:
		held[pitch] = true
		voice.note_on(pitch, velocity)
	else:
		voice.note_off(pitch)
		if held.erase(pitch) and held.is_empty():
			voice.bend(0)
	_modular_heard_held[peer] = held


## A bandmate's wheel through the modular (Presence.modular_control_heard), while they hold a note.
func _on_modular_control_heard(peer: int, kind: int, value: int) -> void:
	if kind != DawKitClip.PITCH_BEND or (_modular_heard_held.get(peer, {}) as Dictionary).is_empty():
		return
	var voice := _modular_voice_of(peer, false)
	if voice != null:
		voice.bend(value)


## `peer`'s voice at the wall, made (with `make`) if they have none yet; null where there is no wall
## to play it from.
func _modular_voice_of(peer: int, make: bool) -> ModularVoice:
	var voice: ModularVoice = modular_heard.get(peer)
	if voice != null and is_instance_valid(voice):
		return voice
	if not make or modular_wall == null or not is_instance_valid(modular_wall):
		return null
	voice = ModularVoice.new()
	voice.name = "ModularHeard%d" % peer
	voice.speaker = modular_wall
	voice.volume_db = -4.0
	voice.set_patch(modular_voice.patch if modular_voice != null else modular_row)
	if modular_voice != null:
		for socket: StringName in modular_voice.world_levels():
			voice.world(socket, float(modular_voice.world_levels()[socket]))
	add_child(voice)
	voice.engaged = true
	modular_heard[peer] = voice
	return voice


## Out of the session: no bandmate is playing the wall any more.
func _on_modular_role_changed() -> void:
	if Session.role == Session.Role.SOLO:
		for peer: int in modular_heard.keys():
			_forget_modular_player(peer)


## A bandmate gone: their voice at the wall with them.
func _forget_modular_player(peer: int) -> void:
	var voice: ModularVoice = modular_heard.get(peer)
	modular_heard.erase(peer)
	_modular_heard_held.erase(peer)
	if voice != null and is_instance_valid(voice):
		voice.queue_free()


## A touch key, or the computer keys under PLAY: a note on this player's keys, as the modular.
func _on_modular_touched(pitch: int, down: bool, velocity := 100) -> void:
	if Session.guest_midi == null:
		return
	if down:
		Session.guest_midi.note_on(pitch, velocity, 0, 0.0, false, Modular.SOURCE)
	else:
		Session.guest_midi.note_off(pitch, 0, 0.0, false, Modular.SOURCE)


## A key played on this player's keys, from anywhere: KEYS' readout, its newest note and its lamp.
func _on_modular_key(pitch: int, down: bool) -> void:
	if down:
		_modular_held[pitch] = true
		_modular_last = pitch
	else:
		_modular_held.erase(pitch)
	if modular_wall != null and is_instance_valid(modular_wall):
		modular_wall.show_keys(_modular_last, not _modular_held.is_empty())


## The computer keys as the modular's, on or off, and said so the first time.
func _modular_play(on: bool) -> void:
	if modular_keys == null or on == modular_keys.is_active():
		return
	modular_keys.set_active(on)
	if on:
		Session.notice.emit("Modular: A to ' play from %s, Z and X move the octave. Esc gives the keys back; PLAY takes them again."
				% modular_keys.octave_name())


## Whether this player is at the wall: with it visited or brought, or standing in front of the
## stand (MODULAR_NEAR to MODULAR_FAR out, MODULAR_SIDE either side) where the wall's own seat is
## the nearest station's, so standing at the harp, the music box or the bells beside it plays them
## and not the patch.
func at_modular() -> bool:
	if modular_wall == null or not is_instance_valid(modular_wall) or not modular_wall.visible \
			or not modular_wall.is_inside_tree():
		return false
	if focus != null and focus.focused_id == modular_wall.surface_id:
		return true
	var me := _standing_at()
	var local := modular_wall.global_transform.affine_inverse() * me
	if local.z <= MODULAR_NEAR or local.z >= MODULAR_FAR or absf(local.x) >= MODULAR_SIDE:
		return false
	var seats := _station_seats()
	if not seats.has(Modular.STATION):
		return true
	var floor := Vector2(me.x, me.z)
	var own := floor.distance_to(seats[Modular.STATION])
	for id: StringName in seats:
		if id != Modular.STATION and floor.distance_to(seats[id]) < own:
			return false
	return true


## Every station's seat here (Stations.seat, a headset's where this is one), on the floor in global
## space, by id: worked out again every MODULAR_SEATS_EVERY, or for another venue.
func _station_seats() -> Dictionary:
	var now := Time.get_ticks_msec()
	var here := venue.get_instance_id() if venue != null else 0
	if _modular_seats_venue == here and _modular_seats_at >= 0 \
			and now - _modular_seats_at < MODULAR_SEATS_EVERY * 1000.0:
		return _modular_seats
	_modular_seats_venue = here
	_modular_seats_at = now
	_modular_seats = {}
	if venue == null:
		return _modular_seats
	var frame_of := venue.global_transform if venue.is_inside_tree() else venue.transform
	var fits := walker.fits if walker != null else _station_fits()
	var hands := medium != Presentation.Medium.SCREEN
	for id in station_ids():
		var seat: Variant = Stations.seat(venue, id, fits, hands)
		if seat != null:
			var p: Vector3 = frame_of * (seat as Transform3D).origin
			_modular_seats[id] = Vector2(p.x, p.z)
	return _modular_seats


# --- the world into the modular (docs/spatial_loop.md part two, slice 53) ----------------------
#
# The world's sockets (Modular.WORLD) are outputs on the modular's patch, out in the room on the
# stations that make what they carry (WorldSocket): a press steps a socket's long cable through the
# wall's free inputs, each step the room's ask `modular_patch` like any cable. What they carry is
# ModularWorld's, the same on every machine: played into every voice here as the song plays
# (`_on_world_fired`), and into a take when it ends (ModularTakes.world).

## A world socket's press (WorldSocket.step_asked): its cable out of the input it is in, and into the
## next free one `way` on, each asked of the room, and said.
func _on_world_step(socket: StringName, way: int) -> void:
	var now := Modular.sinks_of(modular_row, socket)
	var next := Modular.step_input(modular_row, socket, way)
	if not now.is_empty():
		if next == now[0]:
			return
		ask_modular_patch(now[0], &"")
	if next != &"":
		ask_modular_patch(socket, next)
		Session.notice.emit(world_patched_text(socket, next))
	elif not now.is_empty():
		Session.notice.emit("%s is out of the modular wall." % Modular.world_title(socket).capitalize())


## What this player is told on patching world socket `socket` into the wall's input `to`.
static func world_patched_text(socket: StringName, to: StringName) -> String:
	var what: String = {"world:weather": "its density, and a gate each drop", "world:drips": "a gate each drip",
			"world:venue": "a gate each strike", "world:marbles": "a gate each bell rung"}.get(String(socket),
			"its layer's notes as a level, and a gate each note")
	return "%s goes into %s on the modular wall: %s. Press it again for the next free input." % [
			Modular.world_title(socket).capitalize(), Modular.jack_title(to), what]


## What the world played into the sockets as the song played here, into every voice.
func _on_world_fired(events: Array) -> void:
	for voice: ModularVoice in _modular_voices():
		ModularWorld.play_into(voice, events)


## Where a plug in the wall's input `id` sits, for a world socket's cable: null where the wall is not
## up here.
func _wall_jack(id: StringName) -> Variant:
	if modular_wall == null or not is_instance_valid(modular_wall) or not modular_wall.is_visible_in_tree():
		return null
	var jack: ModularJack = modular_wall.jacks.get(id)
	return jack.plug_transform() if jack != null and jack.is_inside_tree() else null


## Each frame: every world socket in the room wired to its press and the wall, and showing where the
## room's patch has its cable.
func _follow_world_sockets() -> void:
	for node in get_tree().get_nodes_in_group(WorldSocket.SOCKETS):
		var socket := node as WorldSocket
		if socket == null:
			continue
		if not socket.has_meta(&"wired"):
			socket.set_meta(&"wired", true)
			socket.step_asked.connect(_on_world_step)
			socket.wall_jack = _wall_jack
		var sinks := Modular.sinks_of(modular_row, socket.socket)
		var into: StringName = sinks[0] if not sinks.is_empty() else &""
		if socket.into != into:
			socket.show_into(into)


## Whether the room's patch has a cable out of any world socket.
static func world_patched(patch: Dictionary) -> bool:
	for c: Array in patch.get("cables", []):
		if Modular.is_world(StringName(c[0])):
			return true
	return false


## Each frame: this player's keys play the patch while they are at the wall (or its PLAY has the
## computer keys), its controls take the pointer only then, and OUT says which road it sounds on,
## and REC while a take goes through it.
func _follow_modular() -> void:
	if modular_wall == null or not is_instance_valid(modular_wall):
		return
	_follow_world_sockets()
	var here := at_modular()
	var engaged := here or (modular_keys != null and modular_keys.is_active())
	modular_wall.within_reach = here
	if Session.guest_midi != null:
		Session.guest_midi.reach(Modular.SOURCE, engaged)
	if modular_voice != null:
		modular_voice.engaged = engaged
		# Recording through it (slice 52): OUT says so, in words, as the take is the wall's sound.
		var recording := engaged and Session.modular_takes.mine != null
		modular_wall.set_recording(recording)
		modular_wall.set_tag(modular_voice.tag())
	if not here and modular_keys != null and modular_keys.is_active() and not modular_wall.visible:
		_modular_play(false)
	if modular_world_voice != null:
		modular_world_voice.engaged = modular_wall.visible and world_patched(modular_row) \
				and not _modular_played_here()


## Whether a voice here other than the world's own is sounding the patch: this player's at the wall
## or under PLAY, or a bandmate's not yet rested. Each already hears the world's sockets, so the
## world's own voice rests then and a drip into a gate is heard once and not again a few ms later.
func _modular_played_here() -> bool:
	for voice: ModularVoice in _modular_voices():
		if voice != modular_world_voice and voice.engaged and voice.path != ModularVoice.Path.NONE:
			return true
	return false


# --- the sampler (docs/spatial_loop.md part two, slice 26) ----------------------------------
#
# REC is the room's row `sampler`, the peer it is armed for: a guest's press is the room's ask
# `sampler` [on], shown at once here; the host's is done. Every use and hit reaches the host with
# the Foley take its player's hand rang, and the host's sampler (`Sampler.heard`) catches the first
# one in its reach, or in its presser's hand, as a WAV and a cassette on the rack, and REC goes off.

## A hand here pressed the sampler's REC.
func _on_rec_pressed(on: bool) -> void:
	if sampler == null or not is_instance_valid(sampler):
		return
	var me := Session.local_peer_id
	if Session.is_authority():
		_arm_sampler(on, me)
	elif _predict(Sampler.VERB, [on]) > 0:
		sampler.armed_by = me if on else 0
	var desk := medium == Presentation.Medium.SCREEN
	Session.notice.emit(("Sampler REC: the next thing you squeeze, click or shake, a yo-yo or card trick, or a bounce of the ball, or anything used within %.1f m of its mic, is a sample on the rack. Click REC again to stop."
			if desk else "Sampler REC: the next thing you squeeze, hit or shake, a yo-yo or card trick, or a bounce of the ball, or anything used within %.1f m of its mic, is a sample on the rack. Press REC again to stop.") % Sampler.REACH
			if on else "Sampler REC off.")


## The room's word on REC: on for `from`'s next sound, or off.
func _arm_sampler(on: bool, from: int) -> void:
	if sampler == null or not is_instance_valid(sampler):
		return
	sampler.armed_by = from if on else 0
	_publish_room_soon()


## A use of `item` (Foley's `kind`, take `take`, played `pitch` fast) by `from`, for the sampler to
## catch: only the host's does (Sampler.heard).
func _sample(item: Item, kind: StringName, take: int, from: int, pitch := 1.0) -> void:
	if _sampling():
		sampler.heard(item, kind, take, from, pitch)


## Whether the sampler is waiting for a sound: what is asked of a use (its pitch reads the song
## clock) only then.
func _sampling() -> bool:
	return sampler != null and is_instance_valid(sampler) and sampler.armed_by != 0


## Where this machine has the platter's audio clip's file `source`: the host's media folder, or a
## guest's fetched copy, its fetch begun when it has none yet (FileSend.fetch); "" until then.
func _platter_file(source: String) -> String:
	if source.is_empty():
		return ""
	if Session.role == Session.Role.GUEST:
		if Session.files == null:
			return ""
		var got := Session.files.fetched_path(source)
		if got.is_empty() and Session.files.fetch_state(source) == &"":
			Session.files.fetch(source)
		return got
	var path := DAW.backend.media_path(source) if DAW.backend != null else ""
	return path if not path.is_empty() and FileAccess.file_exists(path) else ""


## A scratch a hand here made on the platter (Platter.scratched), for the sampler: the host renders
## it from its own render of the clip and catches it as a sound of the cassette; a guest's is the
## room's ask `scratch`, its path, only while REC waits.
func _on_scratched(cassette: CassetteItem, path: PackedFloat32Array) -> void:
	if not _sampling() or cassette == null or not is_instance_valid(cassette):
		return
	if Session.is_authority():
		_sample_scratch(cassette, path, Session.local_peer_id)
	else:
		Session.ask_room(Platter.SCRATCH_VERB, [cassette.id, path])


## The host: `from`'s scratch of `cassette` along `path`, rendered (Platter.render_scratch) and given
## the sampler as the platter's sound of it. Only when REC waits and would catch it (Sampler.catches):
## a render is real work, and nobody's ask makes it for nothing.
func _sample_scratch(cassette: CassetteItem, path: PackedFloat32Array, from: int) -> void:
	if platter == null or not is_instance_valid(platter) or not _sampling() \
			or not sampler.catches(cassette, from) or not Varispeed.fits(path):
		return
	platter.render_scratch(cassette, path, func(wav: AudioStreamWAV) -> void:
		if wav != null and _sampling() and is_instance_valid(cassette):
			sampler.heard_stream(cassette, &"platter_scratch", wav, from))


## A hand here used what it carries: a squeeze, a click, a trick.
func _sample_use_here(item: Item, down: bool) -> void:
	if down and _sampling():
		_sample(item, item.use_kind(true), item.use_take, Session.local_peer_id, item.use_pitch())


## A sound an item rang of its own on this copy (Item.rang): a ball's bounce, the thrower's. Every
## copy flies a throw the same, so the host's copy's is the one its thrower heard.
func _sample_ring(item: Item, kind: StringName, take: int, pitch: float) -> void:
	_sample(item, kind, take, item.thrown_by, pitch)


## Somebody else's use, as the host hears it, with the take their hand rang: only of what is in
## their hand, as Presence rings only that. A pitched instrument's click comes as a hit too, with
## the song position that pitches it, and is caught from that (`_on_someones_hit`).
func _on_someones_use(id: StringName, down: bool, from: int, take := -1) -> void:
	var item: Item = items.items.get(id) if items != null else null
	if down and _sampling() and item != null and from != Session.local_peer_id and Session.is_authority() \
			and Session.holder_of(item.network_key()) == from \
			and not (item is InstrumentItem and (item as InstrumentItem).pitched()):
		_sample(item, item.use_kind(true), take, from, item.use_pitch())


## Somebody else's shake: heard here as shaken (Presence: `heard`, not struck), and caught so, at
## the pitch it rang for them (their song position `song` pitches a bell). Their strike on one that
## stands still is nobody's to hold: caught struck, on its zone.
func _on_someones_hit(id: StringName, velocity: int, from: int, song := -1.0, _snap := false, take := -1,
		zone := &"") -> void:
	var item := items.items.get(id) as InstrumentItem if items != null else null
	# A bandmate's strike of the venue's instrument, at the song they struck it at (slice 53).
	if item != null and modular_world != null and from != Session.local_peer_id \
			and item.jack_source() == VenueInstrument.SOURCE:
		modular_world.strike(song, velocity)
	if not _sampling() or item == null or from == Session.local_peer_id or not Session.is_authority():
		return
	if item.fixed:
		_sample(item, item.kind_of_hit(true, zone if item.has_zone(zone) else &""), take, from, item.tune_at(song))
	elif Session.holder_of(item.network_key()) == from:
		_sample(item, item.sound_kind(false), take, from, item.tune_at(song))


## How far along the mouse's ray the bandmate a made item in its hand would be handed to stands,
## or INF: nearer than the control behind them, the click is the hand-over (Interactor).
func _press_ahead(item: Item, origin: Vector3, direction: Vector3) -> float:
	if presence == null or not ItemRoom.is_made(item.id) or not (item.carried_by is MouseInteractor):
		return INF
	var hit := presence.peer_along(origin, direction)
	return float(hit[1]) if int(hit[0]) != 0 else INF


## A headset hand holding a made item within GIVE_REACH of a bandmate's glove for GIVE_HOLD hands
## it to them.
func _follow_gives(delta: float) -> void:
	if presence == null or items == null:
		return
	for node in get_tree().get_nodes_in_group(Interactor.GROUP):
		var hand := node as Interactor
		if hand == null or hand is MouseInteractor or not hand.is_inside_tree():
			continue
		var item := hand.carrying
		if not is_instance_valid(item) or not ItemRoom.is_made(item.id):
			_give_held.erase(hand)
			continue
		var peer := presence.glove_near(item.middle(), GIVE_REACH)
		var was: Array = _give_held.get(hand, [0, 0.0])
		if peer == 0:
			_give_held.erase(hand)
			continue
		var held := (float(was[1]) if int(was[0]) == peer else 0.0) + delta
		if held >= GIVE_HOLD:
			_give_held.erase(hand)
			give_item(item, peer)
		else:
			_give_held[hand] = [peer, held]


## The host's made items, with where each is, kept with its layout to be there next time.
func _remember_made() -> void:
	if Session.layout == null or not Session.is_authority() or items == null:
		return
	var where := items.state()
	var out := {}
	for id in items.made:
		var row: Array = items.made[id]
		out[id] = [row[0], row[1], row[2], where.get(id, [])]
		# A chord brick's length is the room's, not its data (slice 31): kept beside its place.
		var brick := items.items.get(id) as ChordBrick
		if brick != null:
			out[id].append(brick.bars)
	if out == Session.layout.made:
		return
	Session.layout.set_made(out)
	Session.layout.save()


## What the host's layout kept of its made items: theirs again, where they were. `missing_only`,
## only those not here already (back from being a guest), never moving one a hand may have.
func _restore_made(missing_only := false) -> void:
	if Session.layout == null or not Session.is_authority() or items == null:
		return
	for id in Session.layout.made:
		if missing_only and items.items.has(id):
			continue
		var row: Array = Session.layout.made[id]
		# A row the session still has (a studio built again in the same run) is the same row.
		if not items.made.has(id):
			if not ItemRoom.made_refusal(items.made, (row[2] as PackedByteArray).size()).is_empty():
				continue
			items.made[id] = [row[0], int(row[1]), row[2]]
		var item := items._make_real(id)
		if item is ChordBrick and row.size() > 4:
			(item as ChordBrick).bars = int(row[4])
		var place: Variant = row[3]
		if item == null or not (place is Array):
			continue
		if (place as Array).size() == 3 and str(place[0]) == "slot":
			items.slot(item, StringName(str(place[1])), int(place[2]))
		elif (place as Array).size() >= 4:
			items.lay(item, Vector2(float(place[0]), float(place[2])), float(place[3]))


## The case that starts a Tour run, chained in the back of house. The small hook the studio
## gives Tour (docs/architecture.md): everything past "it broke" or "the run is over" is
## core/tour/tour.gd's.
func _build_tour_case() -> void:
	tour_case = TourCase.new()
	studio_set.add_child(tour_case)
	tour_case.transform = _venue_to_set(venue.tour_case_spot())
	tour_case.local_peer = func() -> int: return Session.local_peer_id
	if items != null:
		items.targets = [{"node": tour_case, "radius": TourCase.STRIKE_RADIUS}]
	tour_case.break_attempted.connect(_on_tour_case_struck)
	tour_case.broken_open.connect(_on_tour_case_broken_open)
	Tour.run_started.connect(_on_tour_run_started)
	Tour.run_ended.connect(_on_tour_run_ended)
	Tour.brief_started.connect(_on_tour_brief_started)
	Tour.instrument_spilled.connect(_on_tour_instrument_spilled)
	Tour.chaos_telegraphed.connect(_on_tour_chaos_telegraphed)
	Tour.chaos_struck.connect(_on_tour_chaos_struck)
	Tour.flaw_fixed.connect(_on_tour_flaw_fixed)
	Tour.clock_low.connect(_on_tour_clock_low)
	Session.tour_changed.connect(_on_session_tour_changed)
	Session.participant_left.connect(_on_tour_participant_left)
	_sync_tour_roll()


## The panel on the control room wall: works against whichever DAW backend is open, not gated to
## the built-in engine the way Tour is, so it is built unconditionally alongside the case.
func _build_rig_roulette_station() -> void:
	if not roulette_enabled:
		return
	_build_roll_board()
	_stand_the_setup_wall()
	Session.roll_changed.connect(_on_session_roll_changed)
	Session.roll_setup_changed.connect(_on_session_roll_setup_changed)
	venue_changed.connect(func(_id): _build_roll_board())
	venue_changed.connect(func(_id): _stand_the_setup_wall())


## What the host has set for the next roll: kept here, not in the panel, so it outlives the
## panel (which only stands in the Rig Roulette room) and a roll anywhere reads it.
var roll_settings := RollSettings.new()

## How much bigger the setup wall in the room is than the panel it was.
const SETUP_WALL_SCALE := 2.9


## The setup wall (`RigRouletteStation`) stands in the Rig Roulette room and nowhere else: the
## venues have a door instead (`RouletteDoor`). It is a child of the venue, so it goes when the
## venue does; its wheels start from `roll_settings` and write back to it.
func _stand_the_setup_wall() -> void:
	rig_roulette_station = null
	if venue == null or not in_roulette_room():
		return
	var wall := RigRouletteStation.new()
	wall.name = "SetupWall"
	if not Session.is_authority() and not Session.roll_setup.is_empty():
		roll_settings = RollSettings.from_dict(Session.roll_setup)
	wall.read_only = not Session.is_authority()
	wall.count = roll_settings.count
	wall.pool = wall_pool(roll_settings.pool)
	wall.key_locked = roll_settings.key_locked
	wall.per_track_cap = roll_settings.per_track_cap
	wall.no_repeats = roll_settings.no_repeats
	wall.scales = int(roll_settings.scales)
	wall.near_semitones = roll_settings.near_semitones
	wall.replay_last = roll_settings.replay_last
	wall.reroll_limit = roll_settings.reroll_limit
	wall.chaos = roll_settings.chaos
	wall.tempo_pick = roll_settings.tempo_pick
	wall.weights = roll_settings.weights.duplicate()
	wall.transform = venue.rig_roulette_spot()
	# A wall for the whole room to read from the seat, not a panel to stand at.
	wall.scale = Vector3.ONE * SETUP_WALL_SCALE
	wall.roll_requested.connect(_on_rig_roulette_roll_requested)
	wall.changed.connect(func() -> void:
		if not Session.is_authority():
			# Only the host sets the roll: a guest's nudge is put back to the host's word.
			wall.apply_settings(roll_settings)
			Session.notice.emit("Only %s can change the roll." % Session.name_of(1))
			return
		var s := wall.settings()
		roll_settings.count = s.count
		roll_settings.pool = s.pool
		roll_settings.key_locked = s.key_locked
		roll_settings.per_track_cap = s.per_track_cap
		roll_settings.no_repeats = s.no_repeats
		roll_settings.scales = s.scales
		roll_settings.near_semitones = s.near_semitones
		roll_settings.replay_last = s.replay_last
		roll_settings.reroll_limit = s.reroll_limit
		roll_settings.chaos = s.chaos
		roll_settings.tempo_pick = s.tempo_pick
		roll_settings.weights = s.weights
		Session.publish_roll_setup(roll_settings.to_dict()))
	wall.preset_sources = _preset_choices
	wall.undo_requested.connect(undo_the_roll)
	wall.preset_chosen.connect(func(id: int) -> void: _on_preset_chosen(wall, id))
	wall.preset_save_requested.connect(func() -> void: _on_preset_save_requested(wall))
	wall.screen_sources = func() -> Array:
		var out := []
		var sources := board_sources()
		for i in sources.size():
			out.append([i, "SCREEN: " + board_title(sources[i])])
		return out
	wall.screen_chosen.connect(func(i: int) -> void:
		var sources := board_sources()
		if i >= 0 and i < sources.size():
			choose_board_source(sources[i]))
	venue.add_child(wall)
	wall.set_free_standing(true)
	rig_roulette_station = wall
	if not Session.roll.is_empty():
		wall.show_result(Session.roll["tracks"], Session.roll["pedals"].size(), Session.roll["key"])
	if wall.screen_wheel != null:
		wall.screen_wheel.choice = maxi(board_sources().find(board_source), 0)
		wall.screen_wheel.refresh()


## Where the saved presets live; a test points it elsewhere.
var roll_presets_path := RollPresets.PATH


## The PRESET wheel's list: a resting word, the ones that ship, the saved slots.
func _preset_choices() -> Array:
	var out := [[0, "PRESETS"]]
	var built := RollPresets.built_in()
	for i in built.size():
		out.append([1 + i, "LOAD: " + built[i][0]])
	var slots := RollPresets.saved(roll_presets_path)
	for i in slots.size():
		out.append([1 + built.size() + i, "LOAD MINE %d: %s" % [i + 1, "EMPTY" if slots[i].is_empty() else RollPresets.name_of(slots[i])]])
	return out


## A preset was picked: the host's settings become it (seed apart), told to the room.
func _on_preset_chosen(wall: RigRouletteStation, id: int) -> void:
	if id == 0:
		return
	if not Session.is_authority():
		Session.notice.emit("Only %s can change the roll." % Session.name_of(1))
		wall.apply_settings(roll_settings)
		return
	var built := RollPresets.built_in()
	var d: Dictionary = {}
	if id <= built.size():
		d = built[id - 1][1]
	else:
		var slots := RollPresets.saved(roll_presets_path)
		var slot := id - 1 - built.size()
		if slot >= 0 and slot < slots.size():
			d = slots[slot]
	if d.is_empty():
		Session.notice.emit("That slot is empty: set the wheels and press SAVE.")
		return
	var loaded := RollSettings.from_dict(d)
	loaded.seed_value = roll_settings.seed_value
	roll_settings = loaded
	wall.apply_settings(roll_settings)
	Session.publish_roll_setup(roll_settings.to_dict())


func _on_preset_save_requested(wall: RigRouletteStation) -> void:
	if not Session.is_authority():
		Session.notice.emit("Only %s can save a preset." % Session.name_of(1))
		return
	var at := RollPresets.save(roll_settings, roll_presets_path)
	wall.preset_wheel.refresh()
	Session.notice.emit("Saved as mine %d: %s." % [at + 1, RollPresets.name_of(roll_settings.to_dict())])


static func wall_pool(pool: RollSettings.Pool) -> RigRouletteStation.Pool:
	return int(pool) as RigRouletteStation.Pool


## The board the roll is written up on, built again for each venue: how it is drawn and whether
## it stands on its own posts are the venue's to say.
func _build_roll_board() -> void:
	if roll_board != null:
		studio_set.remove_child(roll_board)
		roll_board.queue_free()
	roll_board = RollBoard.new()
	roll_board.landed.connect(_on_roll_result_landed)
	roll_board.chalky = venue.roll_board_chalky()
	roll_board.free_standing = venue.back_wall_gear_stands()
	roll_board.transform = venue.roll_board_spot()
	roll_board.rich = rich_rendering()
	roll_board.environment_from = world_env.environment if world_env != null else null
	studio_set.add_child(roll_board)
	_on_session_roll_changed()
	_show_board(board_source)


## What the big board shows: &"" for the roll's write-up, or a mounted surface's id. The room's
## choice, the same for everyone in it (`room_state`'s "board").
var board_source: StringName = &""


## Everything the big board can show, the write-up first.
func board_sources() -> Array[StringName]:
	var out: Array[StringName] = [&""]
	if mount != null:
		for id in mount.mounted_ids():
			out.append(id)
	return out


static func board_title(source: StringName) -> String:
	match source:
		&"": return "ROLL"
		&"rack": return "FX RACK"
		&"tape_deck": return "TAPE DECK"
	return String(source).replace("_", " ").to_upper()


## Someone here chose what the big board shows: done at once, and the room asked (or told, by
## the host) so every screen in it shows the same.
func choose_board_source(source: StringName) -> void:
	if source == board_source or not board_sources().has(source):
		return
	if Session.is_authority():
		_show_board(source)
		_publish_room()
	else:
		_predict(&"board_source", [source])
		_show_board(source)


func _show_board(source: StringName) -> void:
	if not board_sources().has(source):
		source = &""
	board_source = source
	if roll_board != null:
		roll_board.show_source(mount.surface(source) if source != &"" else null, board_title(source))
	if rig_roulette_station != null and rig_roulette_station.screen_wheel != null:
		rig_roulette_station.screen_wheel.choice = board_sources().find(source)
		rig_roulette_station.screen_wheel.refresh()


## The host's word on the roll's settings reached this guest: kept, and shown on the wall.
func _on_session_roll_setup_changed() -> void:
	if Session.is_authority():
		return
	roll_settings = RollSettings.from_dict(Session.roll_setup)
	if rig_roulette_station != null:
		rig_roulette_station.apply_settings(roll_settings)


var _roll_shown := 0
## Rolls made since the band last came into the Rig Roulette room.
var _rolls_this_visit := 0


## A result landed on the board: a thud, higher each time, and the wheel on the floor spun up.
func _on_roll_result_landed(step: int, of: int) -> void:
	Foley.play(roll_board, Foley.board_thud(step), -6.0, 0.8 + 0.5 * float(step) / float(of))
	if venue.has_method("pulse"):
		venue.pulse(1.0 if step < of else 0.4)


## `Session.roll` changed (the host's own roll, or word of it reaching a guest): the board and
## the panel's own line say what it was.
func _on_session_roll_changed() -> void:
	# A roll not seen yet lands part by part; the same one sent again (a guest admitted late) is
	# simply written up.
	var n: int = Session.roll.get("n", 0)
	var fresh := n != 0 and n != _roll_shown
	_roll_shown = n
	roll_board.show_roll(Session.roll, fresh)
	if fresh and venue.has_method("pulse"):
		venue.pulse(1.0)
	if not Session.roll.is_empty() and rig_roulette_station != null:
		rig_roulette_station.show_result(Session.roll["tracks"], Session.roll["pedals"].size(), Session.roll["key"])


## RigRouletteStation.roll_requested: told so only the host can roll, the same pattern
## `choose_venue` and `_on_tour_case_struck` both use.
func _on_rig_roulette_roll_requested() -> void:
	if not roulette_enabled:
		return
	if not Session.is_authority():
		Session.notice.emit("Only %s can roll the rig." % Session.name_of(1))
		return
	_roll_rig()


## How many tracks a roll starts the new project with.
const ROLL_TRACKS_MIN := RollSettings.TRACKS_MIN
const ROLL_TRACKS_MAX := RollSettings.TRACKS_MAX

## The roll itself, host-only by the time this runs (`_on_rig_roulette_roll_requested`'s own
## gate): refused while the open project has changes no save has kept, since it starts a NEW
## project. The roll is worked out by `RigRoll` from the panel's settings (fresh randomness
## unless a seed is set -- nothing to do with a Tour run's own seed); this starts the project and
## puts the effects on. The key is only named, never applied: the project is empty, so there is
## no note to move. The rolled project is the starting point, not an edit, so it counts as saved
## and can be rolled again untouched.
func _roll_rig() -> void:
	if DAW.has_unsaved_changes():
		Session.notice.emit("Save the project first: a roll starts a new one.")
		return
	var limit := roll_settings.reroll_limit
	if limit >= 0 and _rolls_this_visit > limit:
		Session.notice.emit("No re-rolls left: write the song with this one.")
		return
	# Every roll runs off a seed of its own, so the board can say it and the band can replay it.
	var settings := RollSettings.from_dict(roll_settings.to_dict())
	settings.seed_value = RigRoll.seed_for(settings, int(Session.roll.get("seed", 0)))
	var rng := RigRoll.rng_for(settings)
	var tracks := RigRoll.track_count(rng)
	var before := _remember_before_roll()
	var refused := DAW.new_project(tracks)
	if not refused.is_empty():
		_forget(before)
		Session.notice.emit("Could not start the new project: %s" % "; ".join(refused))
		return

	var indices: Array = []
	for i in DAW.state.track_indices():
		indices.append(i)
	var plan := RigRoll.plan(settings, rng, indices, _rig_roulette_pool(settings), str(Session.roll.get("key", "")))
	# The project is empty, so a new tempo has no item to leave behind in time.
	var tempo: int = plan["tempo"]
	if tempo > 0:
		DAW.set_tempo(float(tempo))
	var landed := 0
	var pedals: Array = []
	for p in plan["pedals"]:
		DAW.add_fx(int(p["track"]), str(p["plugin"]), -1)
		landed += 1
		var added: MixState.FXState = DAW.state.track(int(p["track"])).fx.values()[-1]
		_throw_the_knobs(int(p["track"]), added, rng, settings.chaos)
		pedals.append({"track": DAW.state.track(int(p["track"])).display_name(), "fx": added.name})
	var key: String = plan["key"]
	DAW.mark_clean()
	_rolls_this_visit += 1
	# The board is for the write-up now, whatever it was showing.
	_show_board(&"")
	_publish_room()

	if not before.is_empty():
		_roll_history.append(before)
		while _roll_history.size() > ROLL_HISTORY_MAX:
			_forget(_roll_history.pop_front())
	Session.publish_roll({"by": Session.name_of(Session.local_peer_id), "n": Session.roll.get("n", 0) + 1, "past": _past_rolls(),
			"tracks": tracks, "key": key, "pedals": pedals, "seed": settings.seed_value, "chaos": settings.chaos, "tempo": tempo,
			"left": -1 if limit < 0 else limit - _rolls_this_visit + 1})
	var msg := "%s rolled a new project: %d tracks, %d pedal%s" % [Session.name_of(Session.local_peer_id), tracks,
			landed, "" if landed == 1 else "s"]
	if not key.is_empty():
		msg += ", key of %s" % key
	if tempo > 0:
		msg += ", %d BPM" % tempo
	Session.tell_room(msg + ".")


## A landed pedal's knobs thrown by the chaos, off the roll's own generator so a replay throws them
## the same. The pedal's parameters as the engine reports them; a DAW that has not listed any (Reaper
## gives only the current bank) is left alone.
func _throw_the_knobs(track: int, fx: MixState.FXState, rng: RandomNumberGenerator, chaos: int) -> void:
	if chaos <= 0:
		return
	var params := fx.params.keys()
	params.sort()
	for param in params:
		DAW.set_fx_param(track, fx.index, int(param), RigRoll.knob(rng, float(fx.params[param]), chaos))


## How many rolls back an undo can go.
const ROLL_HISTORY_MAX := 8

## What the project was before each roll, newest last: {file, original, prev_roll}.
var _roll_history: Array = []
var _history_swept := false


## The project as it stands, kept aside before a roll replaces it, so an undo can bring it back.
## Only the built-in engine and its stand-in own project files; against Reaper there is nothing
## to keep, so a roll there cannot be undone (and the wall says so when asked).
func _remember_before_roll() -> Dictionary:
	if not DAW.backend is OfflineBackend:
		return {}
	if not _history_swept:
		# What an earlier run left (a quit, a crash) is no history of this one.
		_history_swept = true
		for f in DirAccess.get_files_at("user://roll_history"):
			DirAccess.remove_absolute("user://roll_history".path_join(f))
	var file := "user://roll_history/before_%d_%d.%s" % [Time.get_ticks_msec(), _roll_history.size(), ProjectFiles.EXTENSION]
	if not ProjectFiles.save(DAW.backend, file, true).is_empty() and not FileAccess.file_exists(file):
		return {}
	return {"file": file, "original": DAW.backend.project_path, "prev_roll": Session.roll.duplicate(true)}


func _forget(entry: Dictionary) -> void:
	if not entry.is_empty():
		DirAccess.remove_absolute(entry["file"])


## A roll in a few words, for the board's list of the ones before.
static func roll_summary(roll: Dictionary) -> String:
	var key: String = roll.get("key", "")
	return "#%d  %d tracks, %d pedal%s%s" % [roll.get("n", 0), roll.get("tracks", 0), (roll.get("pedals", []) as Array).size(),
			"" if (roll.get("pedals", []) as Array).size() == 1 else "s", (", " + key) if not key.is_empty() else ""]


## The rolls before the one on the board, newest first, a few of them.
func _past_rolls() -> Array:
	var out := []
	for i in range(_roll_history.size() - 1, -1, -1):
		var prev: Dictionary = _roll_history[i]["prev_roll"]
		if not prev.is_empty():
			out.append(roll_summary(prev))
		if out.size() >= 3:
			break
	return out


## Host: put the project back as it was before the last roll. Refused with changes no save has
## kept, as a roll is, since it replaces the project.
func undo_the_roll() -> void:
	if not Session.is_authority():
		Session.notice.emit("Only %s can undo a roll." % Session.name_of(1))
		return
	if _roll_history.is_empty():
		Session.notice.emit("Nothing to undo." if DAW.backend is OfflineBackend else "This engine cannot undo a roll.")
		return
	if DAW.has_unsaved_changes():
		Session.notice.emit("Save the project first: undoing a roll replaces it.")
		return
	var entry: Dictionary = _roll_history.back()
	var refused := DAW.open_project(entry["file"])
	if not refused.is_empty():
		Session.notice.emit("Could not bring it back: %s" % "; ".join(refused))
		return
	_roll_history.pop_back()
	# It is the project it was, not the file it was kept in.
	DAW.backend.project_path = entry["original"]
	DAW.backend.name_project()
	DAW.backend.mark_clean()
	_forget(entry)
	_rolls_this_visit = maxi(_rolls_this_visit - 1, 0)
	var prev: Dictionary = entry["prev_roll"].duplicate(true)
	if not prev.is_empty():
		prev["past"] = _past_rolls()
	_roll_shown = int(prev.get("n", 0))
	_publish_room()
	Session.publish_roll(prev)
	Session.tell_room("%s undid the roll." % Session.name_of(Session.local_peer_id))


## The effects a roll may land: CHARACTER draws only the character kinds out of
## `DAW.state.fx_choices`; EVERYTHING, or any pool against a live Reaper list (no kind metadata to
## filter by), is the whole thing.
func _rig_roulette_pool(settings: RollSettings) -> Array:
	return RigRoll.pool_of(settings, DAW.state.fx_choices, not DAW.backend is ReaperBackend)


## A thrown item has hit the case, broken or not (TourCase.break_attempted): told so only the
## host can start the tour, the same pattern `choose_venue` uses for the venue picker.
func _on_tour_case_struck() -> void:
	if not Session.is_authority():
		Session.notice.emit("Only %s can start the tour." % Session.name_of(1))


## The hit that broke the case: starts the run. `Tour.start_run()` is host-only and quiet about
## refusing (wrong engine, a run already under way, or simply not the host) -- nothing else
## here needs to check first.
func _on_tour_case_broken_open() -> void:
	if not Tour.is_available():
		Session.notice.emit("A tour needs the built-in engine: start dawlings with --built-in.")
		tour_case.reset(Tour.unlocks.runs, Tour.unlocks.wins)
		return
	Tour.start_run()


## A run just started, on the host (`Tour.run_started`, which never fires on a guest -- see
## core/tour/tour.gd's class note): the case catches up broken, in case it is still chained --
## true after the normal five hits already burst it, but not after `start_run()` is reached some
## other way (tools/screenshot.gd's `--tour` flag, say). A no-op once it already is.
func _on_tour_run_started() -> void:
	if tour_case != null:
		tour_case.sync_broken()
		if Tour.run != null:
			tour_case.show_seed(Tour.run.attempt_seed)


## The run is over, won or lost: the case is chained again, its tally brought up to date, and the
## result told to the whole room (`Session.tell_room`, not `Session.notice.emit` -- this is
## host-only, unlike a chaos telegraph's every-peer-computes-it-itself pattern, so it has to
## reach a guest the same way a take's own placement notice does). Fires on the host the moment
## `Tour._end_run` runs -- never on a guest (see core/tour/tour.gd's class note) -- which is
## exactly why `tell_room` rather than `notice.emit` alone: a guest's own case still catches up
## from the emptied `Session.tour` (`_on_session_tour_changed`) below, but the result itself has
## no wire state of its own to read once the run is gone, only this one broadcast.
func _on_tour_run_ended(won: bool) -> void:
	if tour_case != null:
		tour_case.reset(Tour.unlocks.runs, Tour.unlocks.wins)
		Foley.play(tour_case, Foley.win_fanfare() if won else Foley.loss_sting())
	var line := "The gig's a hit. Reputation %d." % Tour.unlocks.reputation
	if not won:
		line = "That one got away. Lost a point -- Reputation %d." % Tour.unlocks.reputation
	Session.tell_room(line)
	# Back in the case: every instrument the run spilled stops existing here, the host's own
	# half of the reset (a guest's copies go with it too, off the emptied `Session.tour` --
	# `_sync_spilled`, through `_on_session_tour_changed` below).
	if items != null:
		for id in items.spawned_ids():
			items.despawn(id)
		_publish_room_soon()
	_sync_tour_roll()
	# A run can end mid-`power_flicker`'s blackout (the boss brief lost with the lights still
	# out): never leave the room dark once there is no run left to light it back up for.
	_relight()


## Host only (see core/tour/tour.gd's class note): a new brief is in, which may have a different
## tempo (and so a different bar length) than the last -- `_sync_tour_roll` re-reads it.
func _on_tour_brief_started(_index: int) -> void:
	_sync_tour_roll()


## A guest's half of the same reset: the host's word on the run (`Session.tour`) went empty --
## or just arrived, in which case this guest's own case catches up broken (TourCase.sync_broken),
## in case this guest's own hits never reached it (someone else's throws, a dropped one, lag):
## "every guest sees it break" rides the run's synced state, not a local count. The host skips
## this half -- its own case already broke, from its own authoritative hits, if a run is under
## way at all.
func _on_session_tour_changed() -> void:
	_sync_tour_roll()
	_sync_spilled()
	if tour_case == null:
		return
	if Session.tour.is_empty():
		tour_case.reset(Tour.unlocks.runs, Tour.unlocks.wins)
		_relight()
	elif not Session.is_authority():
		tour_case.sync_broken()
		# Off `Session.tour` directly, not `Tour.run`: `Tour`'s own `Session.tour_changed`
		# connection is made with `call_deferred` (core/tour/tour.gd's `_ready`), so `Tour.run`
		# is not guaranteed to have caught up to this signal yet when this handler runs.
		tour_case.show_seed(int(Session.tour.get("attempt_seed", 0)))


## The host's own word on an instrument hitting the floor (`Tour.instrument_spilled`, which
## never reaches this guest's `Session.tour_changed` -- see Tour's own class note): the real
## item, thrown the same way everyone else sees it land.
func _on_tour_instrument_spilled(id: StringName, kind: StringName, curse: StringName, bound_to: int) -> void:
	_spill_instrument(id, kind, curse, bound_to)


## Makes `id` (a copy of `kind`) a real item in the room, cursed and marked as the card said,
## and tosses it out of the case's open lid; everyone else sees the same flight off the room
## (`ItemRoom.state` carries the launch) -- the host's own half of a spill; a guest's is
## `_sync_spilled`, off the same facts riding `Session.tour`.
func _spill_instrument(id: StringName, kind: StringName, curse: StringName, bound_to: int) -> void:
	if items == null or tour_case == null:
		return
	var n := items.spawned_ids().size()
	var home := _spill_home(n)
	var item := items.spawn(kind, id, home)
	if item == null:
		return
	_dress_spilled(item, id, kind, curse, bound_to)
	var mouth := tour_case.transform * Vector3(0, TourCase.BODY_H + 0.15, TourCase.CASE_DEPTH * 0.5 + 0.06)
	var seed := Tour.run.attempt_seed if Tour.run != null else 0
	items.spill(item, mouth, home.origin, hash([String(id), seed]))
	_announce_spill(item, curse)
	_publish_room_soon()


## The case's thump and the toast, on every machine an instrument falls out on: the host's as
## it throws (`_spill_instrument`), a guest's as it learns of it (`_sync_spilled`) -- a reward
## nobody is told about is one nobody goes looking for.
func _announce_spill(item: Item, curse: StringName) -> void:
	Foley.play(tour_case, Foley.case_toss())
	var low := item.item_title().to_lower()
	match curse:
		&"sour":
			Session.notice.emit("A %s fell out of the case, tuned sour." % low)
		&"low":
			Session.notice.emit("A %s fell out of the case, an octave low." % low)
		&"bound":
			Session.notice.emit("A %s fell out of the case, marked for %s: only they can hold it." % [low, item.bound_name])
		_:
			Session.notice.emit("A %s fell out of the case." % low)


## `item`'s voice, curse and mark, whichever of a fresh spill (`_spill_instrument`) or one a
## guest is only now catching up with (`_sync_spilled`) is asking.
func _dress_spilled(item: Item, id: StringName, kind: StringName, curse: StringName, bound_to: int) -> void:
	if item is InstrumentItem:
		var instrument := item as InstrumentItem
		instrument.voice = 1 if id != kind else 0
		match curse:
			&"sour":
				instrument.curse_pitch = 0.917
			&"low":
				instrument.curse_pitch = 0.5
	item.bound_to = bound_to
	item.bound_name = Session.name_of(bound_to) if bound_to != 0 else ""


## A half-ring 0.85m in front of the case, one spot per copy the case can ever spill
## (TourParts.SPILL_KINDS.size() * TourParts.COPIES, six today), so no two land on the same spot.
func _spill_home(n: int) -> Transform3D:
	var spots := TourParts.SPILL_KINDS.size() * TourParts.COPIES
	var a := lerpf(-1.2, 1.2, float(n) / float(maxi(spots - 1, 1)))
	return tour_case.transform * Transform3D(Basis(Vector3.UP, PI + a), Vector3(sin(a) * 0.85, 0, cos(a) * 0.85))


## This guest's half of `Session.tour`'s `instruments`: spawn whatever is missing, despawn
## whatever is no longer wanted (the run ended), and bring every spill's mark up to date (a
## leaver's unbinding lands here too). Idempotent on the host as well, though the host's own
## spawns already happened off `Tour.instrument_spilled` -- this only ever finds them already
## there.
func _sync_spilled() -> void:
	if items == null:
		return
	var run := TourRun.from_dict(Session.tour) if not Session.tour.is_empty() else null
	var want: Array[StringName] = []
	if run != null:
		want = run.instruments
	for id in items.spawned_ids():
		if not (id in want):
			items.despawn(id)
	if run == null:
		return
	var spawned_any := false
	for i in run.instruments.size():
		var id: StringName = run.instruments[i]
		var item: Item = items.items.get(id)
		if item == null:
			var kind := TourParts.kind_of(id)
			item = items.spawn(kind, id, _spill_home(items.spawned_ids().size()))
			if item == null:
				continue
			_dress_spilled(item, id, kind, run.instrument_curses[i], run.instrument_bound[i])
			# The host already said so as it threw; this is a guest hearing it land.
			if not Session.is_authority() and tour_case != null:
				_announce_spill(item, run.instrument_curses[i])
			spawned_any = true
		else:
			var bound: int = run.instrument_bound[i]
			item.bound_to = bound
			item.bound_name = Session.name_of(bound) if bound != 0 else ""
	if spawned_any:
		apply_room(Session.room, false)


## A hand here was refused an item it is not marked for (ItemRoom.refused, Item.may_hold): the
## same toast a claimed fader gives a second hand.
func _on_item_refused(item: Item, _why: String) -> void:
	Session.notice.emit("Only %s can hold the %s." % [item.bound_name, item.item_title().to_lower()])


## A personal copy was just spawned and bound (ItemRoom.personal_taken): whose it is, which
## stays out of item_room.gd the way `local_peer` does, for the same reason
## (`core/items/item_room.gd`'s own `PERSONAL_KINDS` note).
func _on_item_personal_taken(item: Item) -> void:
	item.bound_name = Session.name_of(item.bound_to) if item.bound_to != 0 else ""


## A peer left the session: any instrument marked for them is nobody's to be marked for any
## more. `Tour._on_participant_left` clears the run's own record (`run.instrument_bound`); this
## clears the real item's here on the host, so a hand can take it up at once rather than it
## staying a brick until the next spill or sync happens to touch it. A personal copy is not
## something anyone else could take up anyway (its id names only the one peer it was ever for),
## so it is retired instead of left bound to someone no longer in the room.
func _on_tour_participant_left(peer_id: int) -> void:
	if items == null or not Session.is_authority():
		return
	for id in items.spawned_ids():
		var item: Item = items.items.get(id)
		if item == null or item.bound_to != peer_id:
			continue
		if items.is_personal_copy(id):
			items.despawn(id)
		else:
			item.bound_to = 0
			item.bound_name = ""


## A running take is sent (and a fresh one begun) about every bar while a brief needs its parts
## ticked live, rather than only when recording stops (Tour.take_roll_seconds). Read from
## `Tour.run`, correct on both sides (live on the host, rebuilt from `Session.tour` on a guest),
## so this one sync point covers Tour's own signals and `Session.tour_changed` alike.
func _sync_tour_roll() -> void:
	var seconds := Tour.take_roll_seconds()
	if hit_recorder != null:
		hit_recorder.roll_every = seconds
	if Session.guest_midi != null:
		Session.guest_midi.roll_every = seconds


## A chaos event's telegraph, on EVERY peer, from their own clock (Tour.chaos_telegraphed is the
## one signal pair here that is not host-only -- see Tour's own class note): the room says so
## before it happens, so getting hit by one is never a surprise from nowhere. `crowd_throws`
## warns with a rumble from the back of house, where the crowd actually is; everything else
## warns from the case itself, the run's own corner of the room.
func _on_tour_chaos_telegraphed(index: int) -> void:
	var run := Tour.run
	if run == null or index < 0 or index >= run.events.size():
		return
	var event := TourChaos.by_id(run.events[index])
	if event == null or tour_case == null:
		return
	_flicker_lights()
	tour_case.rattle()
	if event.id == &"crowd_throws":
		_play_at(_crowd_house_point(), Foley.crowd_rumble(0))
	else:
		Foley.play(tour_case, Foley.chaos_warning())
	var track: int = run.event_track[index] if index < run.event_track.size() else 0
	Session.notice.emit(event.telegraph_for(run, track))


## The strike itself, on every peer: the sound everywhere, and whichever of the events here has
## a presentation of its own on top of the desk's own verb landing through ordinary replication
## (every other event's strike is nothing but a DAW verb, already shown by the strip it moved).
func _on_tour_chaos_struck(index: int) -> void:
	var run := Tour.run
	if run == null or index < 0 or index >= run.events.size():
		return
	var id: StringName = run.events[index]
	if tour_case != null:
		Foley.play(tour_case, Foley.chaos_strike())
	match id:
		&"power_flicker":
			_lights_out(Tour.take_roll_seconds() * TourChaos.LIGHTS_OUT_BARS)
		&"crowd_throws":
			if Session.is_authority():
				_throw_crowd_things(index)


## A flaw just turned fixed, on every peer from their own copy of `run.fixed` (Tour.flaw_fixed is
## not host-only -- see Tour's own class note by `chaos_telegraphed`): the crowd cheers from the
## back of house, the band's own job landing somewhere the room can hear it, on top of the HUD's
## line already flipping to ACCENT the same tick.
func _on_tour_flaw_fixed(index: int) -> void:
	_play_at(_crowd_house_point(), Foley.crowd_cheer(index % 3))


## The clock running out, on every peer from their own `brief_elapsed()` (Tour.clock_low is not
## host-only, the same reasoning as the chaos telegraph): the lid rattles for the whole of the
## brief's last `Tour.CLOCK_LOW_SECONDS` rather than a telegraph's short jitter -- the room living
## through the final stretch with the band, not just warning them it is coming.
func _on_tour_clock_low() -> void:
	if tour_case != null:
		tour_case.rattle(Tour.CLOCK_LOW_SECONDS)
	Session.notice.emit("Ten seconds. Finish it.")


## Where the crowd is, in the frame the gear's floor plan is measured in: the back of house's
## centre, a little short of its far wall -- `crowd_throws`'s rumble comes from here, and so does
## the throw itself.
func _crowd_house_point() -> Vector3:
	if venue == null:
		return Vector3.ZERO
	var rect := venue.back_of_house()
	return Vector3(rect.position.x + rect.size.x * 0.5, 1.5, rect.end.y - 0.4)


## A one-shot emitter at an arbitrary point, for a sound that is not coming from any gear already
## standing there -- `crowd_rumble`, from the house rather than the case. Freed shortly after:
## long enough for the clip to finish, short enough not to litter the set over a busy run.
##
## `not is_inside_tree()`: several tests `remove_child` a studio without freeing it once they are
## done, leaving its signal connections (`Tour.flaw_fixed` among them, which now fires on every
## flaw a test's own brief happens to clear) live on a node with no `SceneTree` of its own --
## `get_tree()` would be null on exactly that node, same reasoning `_walk_to_seat` already needed
## this guard for.
func _play_at(point: Vector3, stream: AudioStream, volume_db := 0.0) -> void:
	if studio_set == null or not is_inside_tree():
		return
	var marker := Node3D.new()
	marker.position = point
	studio_set.add_child(marker)
	Foley.play(marker, stream, volume_db)
	get_tree().create_timer(1.5).timeout.connect(marker.queue_free)


## Up to three of the room's loose, unheld things, thrown in from the back of house at the desk:
## the room's own flight (ItemRoom.fly), so a guest sees exactly the same throw through the room
## state -- nothing new rides the wire. Seeded off the run, so a replay throws the same things at
## the same spots. Host only: the room is the host's.
const CROWD_PROPS: Array[StringName] = [&"duck", &"ball", &"toy", &"plane"]

func _throw_crowd_things(event_index: int) -> void:
	if items == null or Tour.run == null:
		return
	var from := _crowd_house_point()
	var thrown := 0
	for kind in CROWD_PROPS:
		if thrown >= 3:
			break
		var item: Item = items.items.get(kind)
		if item == null or item.carried_by != null or Session.holds.has(kind):
			continue
		if item.state != Item.State.HOME and item.state != Item.State.LOOSE:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([Tour.run.attempt_seed, event_index, thrown])
		var to := Vector3(rng.randf_range(-1.0, 1.0), 1.0, TIMELINE_Z + 0.5)
		var spin := Vector3(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))
		items.fly(item, from, ItemRoom.lob(from, to, 6.0), spin, 1)
		thrown += 1
	if thrown > 0:
		_publish_room_soon()


## What the headphones on this person's head let through (Ears), and what this person is told
## about it when they go on.
func _on_phones_changed() -> void:
	var phones := items.items.get(&"headphones") as HeadphonesItem if items != null else null
	if phones == null:
		return
	var now := phones.carried_by != null and phones.on_head
	if now == _heard_phones:
		return
	_heard_phones = now
	_listen()
	var tablet := items.items.get(&"tablet") as TabletItem
	if tablet != null:
		tablet.listening = now
	if not now:
		return
	if not Ears.reaches_mix(Session.role == Session.Role.GUEST, DAW.backend is ReaperBackend):
		Session.notice.emit("Headphones on: the room shut out. You hear Reaper itself, through the system.")
	elif personal.is_patched():
		Session.notice.emit("Headphones on: your personal mix, the room shut out. H takes them off.")
	else:
		Session.notice.emit("Headphones on: the mix and your keys, the room shut out. The tablet patches what is in them.")


## The personal mix changed -- a plug moved, a level -- and the headphones, if they are on,
## play it at once.
func _on_personal_changed() -> void:
	_listen()


## What this machine plays, with or without headphones: the cues of the tracks patched while they
## are on, and the personal mix's levels on the buses.
func _listen() -> void:
	if DAW.backend is GodotBackend:
		(DAW.backend as GodotBackend).set_cues(personal.tracks() if _heard_phones and personal.hears_tracks else [])
		(DAW.backend as GodotBackend).set_taps(personal.taps() if _heard_phones and personal.hears_tracks else [])
	if their_keys != null:
		their_keys.set_players(personal.players() if _heard_phones else [])
	if their_monitor != null:
		their_monitor.set_performers(personal.performers() if _heard_phones else [])
	Ears.listen(_heard_phones, personal.ears_levels())


## How near (m) a head comes to a stage voice to lean in to it (Ears.lean).
const LEAN_REACH := 0.25


## The track a ray from `origin` along `direction` points at, 0 for none (docs/spatial_loop.md
## slice 19): whatever control it meets first, read by `track_of`. The head's gaze, for a clap
## made pointing at nothing.
func track_under(origin: Vector3, direction: Vector3) -> int:
	if not is_inside_tree() or direction.length() < 0.0001:
		return 0
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * Interactor.RAY_LENGTH)
	query.collision_mask = 1 << (Interactor.CONTROL_LAYER - 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return 0
	return track_of(hit["collider"], hit["position"])


## The track a control at `point` belongs to, 0 for none: a stage voice and anything of its tag,
## ring or stalk (their `stage_track`), a console strip and anything on it, a track's rack and its
## units, and the timeline's lanes (TimelineSurface.track_at_point, the lane under the point).
static func track_of(node: Node, point: Vector3) -> int:
	var n := node
	while n != null:
		if n.has_meta(&"stage_track"):
			return int(n.get_meta(&"stage_track"))
		if n is ChannelStrip:
			return (n as ChannelStrip).track_index
		if n is RackUnit:
			return (n as RackUnit).track_index
		if n is RackSurface:
			return maxi((n as RackSurface).track_index, 0)
		if n is TimelineSurface:
			return (n as TimelineSurface).track_at_point(point)
		n = n.get_parent()
	return 0


## The track what a hand holds or hovers belongs to, 0 for none.
func pointed_by(hand: Interactor) -> int:
	if hand == null or not is_instance_valid(hand):
		return 0
	var control: ControlAffordance = hand.held if hand.held != null else hand.hovered
	if control == null or not is_instance_valid(control):
		return 0
	return track_of(control, hand.hover_point)


func _mouse_track() -> int:
	return pointed_by(get_node_or_null("MouseHand") as Interactor)


## The track a clap is aimed at as the hands meet: under either hand's ray, or else the head's gaze.
func _clap_target() -> int:
	if rig == null:
		return _mouse_track()
	for controller in rig.interactors:
		var t := pointed_by(rig.interactors[controller] as Interactor)
		if t > 0:
			return t
	if rig.head != null and rig.head.is_inside_tree():
		return track_under(rig.head.global_position, -rig.head.global_basis.z)
	return 0


## One frame of the two hands for a clap: their palms (bare hands) or grips (controllers).
func _follow_clap(delta: float) -> void:
	key_clap.hold(delta)
	if not clap.target.is_valid():
		clap.target = _clap_target
	if rig == null or rig.left == null or rig.right == null:
		return
	var a := rig.interactors.get(rig.left) as XRInteractor
	var b := rig.interactors.get(rig.right) as XRInteractor
	if a == null or b == null:
		return
	var r := Clap.reading(a.clap_palm(), b.clap_palm())
	clap.step(r[0], r[1], delta)


## The track to lean in to now, 0 for none: in a headset the stage voice the head is within
## LEAN_REACH of, the nearest; at a desk, the voice under the cursor while L is held.
func lean_wanted() -> int:
	if stage == null or not is_instance_valid(stage):
		return 0
	if rig != null and rig.head != null and rig.head.is_inside_tree():
		var best := 0
		var near := LEAN_REACH
		for track in stage.voices:
			var d := (stage.voices[track] as Node3D).global_position.distance_to(rig.head.global_position)
			if d <= near:
				near = d
				best = int(track)
		if best > 0:
			return best
	if not _lean_key:
		return 0
	var hand := get_node_or_null("MouseHand") as Interactor
	var control: Node = (hand.held if hand.held != null else hand.hovered) if hand != null else null
	if control == null or not is_instance_valid(control) or not stage.is_ancestor_of(control):
		return 0
	return track_of(control, hand.hover_point)


## Leaning in, or out, as `lean_wanted` says: Ears.lean, in this player's ears alone. Where it
## cannot be done, the card says why, once for each voice leant toward.
func _follow_lean() -> void:
	var want := lean_wanted()
	if want == 0:
		_lean_refused = 0
	if want == Ears.leaning:
		return
	if want > 0 and not Ears.can_lean():
		if want != _lean_refused:
			_lean_refused = want
			Session.notice.emit("%s: %s." % [stage.title_of(want), Ears.CANNOT_LEAN])
		return
	if Ears.lean(want) and want > 0:
		Session.notice.emit("Leaning in to %s: %+d dB in your ears alone, the mix %d dB down. Nothing changes in the song."
				% [stage.title_of(want), int(GodotBackend.LEAN_DB), int(Ears.LEAN_MIX_DB)])


## The cassette at an ear here now, null for none (docs/spatial_loop.md part two, slice 25): any
## hand's here that holds one there (Interactor.cassette_at_ear), and that hand. Every hand is
## asked every frame, so each one's memory of being at the ear (XRInteractor.EAR_LEAVE) is of
## now; with one at each ear, the one already playing keeps on, else the first.
func ear_wanted() -> Array:
	var wanted := [null, null]
	for node in get_tree().get_nodes_in_group(Interactor.GROUP):
		var hand := node as Interactor
		var c := hand.cassette_at_ear() if hand != null else null
		if c == null:
			continue
		if wanted[0] == null or (ear != null and c == ear.cassette and wanted[0] != ear.cassette):
			wanted = [c, hand]
	return wanted


## The cassette at the ear playing, or stopping, as `ear_wanted` says.
func _follow_ear() -> void:
	if ear == null:
		return
	var wanted := ear_wanted()
	if wanted[0] != ear.cassette:
		ear.desk = wanted[1] is MouseInteractor or wanted[1] == null
	ear.hold(wanted[0])


## Whether a strip's socket can be heard here: the tracks are played one by one on this machine.
func _hears_tracks() -> bool:
	return DAW.backend is GodotBackend and Session.role != Session.Role.GUEST


## A plug dropped on a socket by a hand here, or brought back to the tray: done here at once,
## and asked of the host, whose table it is.
func _on_patch_asked(receiver: int, socket: StringName) -> void:
	if not PersonalMix.valid_socket(socket) or receiver < 0 or receiver >= PersonalMix.RECEIVERS:
		return
	var letter: String = PersonalMix.LETTERS[receiver]
	_set_patch(Session.local_peer_id, receiver, socket)
	if Session.is_authority():
		_publish_room_soon()
	else:
		_predict(&"patch", [receiver, socket])
	if socket == &"":
		Session.notice.emit("Plug %s is back in the tray." % letter)
	elif personal.unheard(receiver):
		Session.notice.emit("Plug %s in %s. One track by itself is not heard here: %s" % [letter,
				PersonalMix.place_of(socket), _why_no_tracks()])
	else:
		var late := ""
		var player := PersonalMix.player_of(socket)
		if player > 0 and Session.note_delay_ms(player) >= 0.0:
			late = " Their notes are played here, about %d ms after they play them." \
					% roundi(Session.note_delay_ms(player))
		if PersonalMix.monitor_of(socket) > 0:
			late = " In time with the backing they hear: your mix waits for their notes."
			if not Ears.reaches_mix(Session.role == Session.Role.GUEST, DAW.backend is ReaperBackend):
				late += " Reaper's mix is not the game's to copy, so only their notes are heard."
		Session.notice.emit("Plug %s in %s: in your headphones%s.%s" % [letter,
				PersonalMix.place_of(socket), "" if _heard_phones else " when you put them on", late])


## Whether the keytar is in this player's hands now, and if that has changed, its keys given or
## taken back: GuestMidi plays it, and on a desktop the computer keyboard is its piano.
func _follow_keytar() -> void:
	var keytar := items.items.get(&"keytar") as KeytarItem if items != null else null
	# In the hand: not one slung across your back in a pocket.
	var mine := keytar != null and keytar.in_hand()
	if mine == _keytar_mine:
		return
	_keytar_mine = mine
	if Session.guest_midi != null:
		Session.guest_midi.keytar = mine
	if keytar != null and not mine:
		keytar.release_all()
	_keytar_play(mine and medium == Presentation.Medium.SCREEN)


## The computer keyboard as the keytar's piano, on or off, and said so the first time.
func _keytar_play(on: bool) -> void:
	if keytar_keys == null or on == keytar_keys.is_active():
		return
	keytar_keys.set_active(on)
	if on:
		Session.notice.emit("Keytar: A to ' play from %s, Z and X move the octave, the arrows walk. Alt with the mouse moving up or down bends. Esc gives the keys back; click the keytar to take them again."
				% keytar_keys.octave_name())


## A key played on this player's keys: shown on the keytar, while it is theirs.
func _on_key_played(pitch: int, down: bool) -> void:
	var keytar := items.items.get(&"keytar") as KeytarItem if items != null else null
	if keytar != null and _keytar_mine:
		keytar.press(pitch, down)


## An instrument played by a hand here: into the take, and, shaken, out to everyone else. A
## click on percussion is out already, as a use; a pitched item's click is sent as a hit too,
## since its ring is all a use of it is, and only a hit carries the song position (`at`) that
## pitches it. The take and the room both get that one `at`, unmoved: a snap moves only the
## recorded note (HitRecorder.snapped_at), and whether this player snaps goes with the hit, with the
## Foley take their hand rang, so everyone hears the sound they heard. A strike on an instrument that
## stands still (Item.fixed) has no use to go as, so it goes as a hit, with where on it it landed
## (`zone`).
func _on_item_played(item: InstrumentItem, velocity: int, struck: bool, at: float, zone := &"") -> void:
	# Onto the armed track, or the track its jack goes into.
	jacks.hit(item, velocity, at, zone)
	# A strike of the venue's instrument into the modular's `world:venue` (slice 53).
	if modular_world != null and item.jack_source() == VenueInstrument.SOURCE:
		modular_world.strike(at, velocity)
	# And into this player's loop, while they loop (slice 45).
	if looper != null and is_instance_valid(looper):
		looper.hit(item, velocity, at, zone)
	if _sampling():
		_sample(item, item.kind_of_hit(struck, zone), item.sound_take(), Session.local_peer_id, item.tune_at(at))
	if not struck or item.pitched() or item.fixed:
		send_item_hit.call(item.id, velocity, at, HitRecorder.snaps(), item.sound_take(), zone)


## A hand here stepped an instrument's jack (Jacks.asked): done here at once, and asked of the
## host, whose table it is. One that plainly is not this player's to plug -- in somebody else's
## hand, or lying on the floor -- is said instead, and nothing is asked.
func _on_plug_asked(source: StringName, sink: StringName) -> void:
	var item: Item = items.source_item(source) if items != null else null
	if item == null and Jack.is_item(source):
		return
	var whose := "Your keys'" if Jack.keys_player(source) > 0 else "The %s's" % Jacks.source_name(source, item)
	if Jack.chord_player(source) > 0:
		whose = "Your chord hand's"
	var why := _plug_refusal(source, sink, Session.local_peer_id, true)
	if why != "":
		Session.notice.emit("%s jack: %s." % [whose, why])
		return
	if Jack.own_player(source) > 0 and sink == &"" and jacks.sink_of(source) == &"":
		Session.notice.emit("%s jack: there is nobody in the room to plug %s into." % [whose,
				"them" if Jack.keys_player(source) > 0 else "it"])
		return
	var was := jacks.sink_of(source)
	if not jacks.plug(source, sink):
		return
	if Session.is_authority():
		_tell_plugged(source, was, sink, Session.local_peer_id)
		_publish_room_soon()
	else:
		_predict(&"plug", [source, sink])
	Session.notice.emit(plugged_text(source, item, was, sink))


## What this player is told on plugging `source` (its `item`, if it is one) from `was` into
## `sink`: where what it plays goes now.
static func plugged_text(source: StringName, item: Item, was: StringName, sink: StringName) -> String:
	var the := "Your keys" if Jack.keys_player(source) > 0 else "The " + Jacks.source_name(source, item)
	var player := Jack.player_of(sink)
	if Jack.chord_player(source) > 0:
		# A chord hand (part two, slice 33): no notes, a chord for their harp and fingertips.
		if player > 0:
			return "Your chord hand goes into %s: the chord you hold is theirs, on their harp, fingertips and bells." \
					% Session.name_of(player)
		return "Your chord hand is unplugged."
	if player > 0:
		var plays := "its hits play chord tones" if item is InstrumentItem and not (item as InstrumentItem).pitched() \
				else "its notes play"
		if Jack.keys_player(source) > 0:
			plays = "what you play plays"
		return "%s go%s into %s: %s on their keys." % [the, "" if Jack.keys_player(source) > 0 else "es",
				Session.name_of(player), plays]
	if sink != &"" and source == MarbleRun.SOURCE:
		return "%s's jack is in %s: every bell a marble rings is recorded there while the song records, heard or not." % [the, Jacks.sink_name(sink)]
	if sink != &"" and Jack.is_world(source):
		return "%s's jack is in %s: every drop is recorded there while the song records, heard or not." % [the, Jacks.sink_name(sink)]
	if sink != &"":
		return "%s's jack is in %s: its hits are recorded there, armed or not." % [the, Jacks.sink_name(sink)]
	if Jack.player_of(was) == Session.local_peer_id and Session.local_peer_id != 0:
		return "%s is unplugged from you." % the
	if source == MarbleRun.SOURCE:
		return "%s is unplugged: its bells are recorded nowhere." % the
	if Jack.is_world(source):
		return "%s is unplugged: its drops are recorded nowhere." % the
	if not Jack.is_item(source):
		return "%s %s unplugged." % [the, "are" if Jack.keys_player(source) > 0 else "is"]
	return "%s is unplugged: its hits go on the armed track again." % the


## The host's word on `from`'s plug of `source` into `sink` (Jacks.plug_refusal), from what this
## machine knows: who holds the source item, where it goes now, who is in the room. `here`: asked
## by a hand on this machine, which knows its own hand better than the holds table does.
func _plug_refusal(source: StringName, sink: StringName, from: int, here := false) -> String:
	var item: Item = items.source_item(source) if items != null else null
	var holder := 0
	if item != null:
		holder = _holder_here(item) if here else Session.holder_of(item.network_key())
	var members: Array = Session.participants.keys()
	if not members.has(Session.local_peer_id):
		members.append(Session.local_peer_id)
	return Jacks.plug_refusal(source, item, sink, from, holder, jacks.sink_of(source), members)


## The host tells whoever a jack now goes into, or no longer does, who plugged what: a bandmate's
## shaker playing your keys is not a thing to find out by surprise. Not the one who did it.
func _tell_plugged(source: StringName, was: StringName, sink: StringName, by: int) -> void:
	var item: Item = items.source_item(source) if items != null else null
	var what := "the %s" % Jacks.source_name(source, item) if Jack.keys_player(source) == 0 \
			else "their keys"
	if Jack.chord_player(source) > 0:
		what = "their chord hand"
	var into := Jack.player_of(sink)
	if into > 0 and into != by:
		var plays := "its hits play chord tones" if item is InstrumentItem and not (item as InstrumentItem).pitched() \
				else "its notes play"
		if Jack.keys_player(source) > 0:
			plays = "what they play plays"
		var said := "%s on your keys" % plays
		if Jack.chord_player(source) > 0:
			said = "the chord they hold is yours, on the harp, your fingertips and your bells, while you hold none"
		Session.tell(into, "%s plugged %s into you: %s. %s"
				% [Session.name_of(by), what, said, unplug_how(_medium_of(into), Jack.own_player(source) == 0)])
	var out := Jack.player_of(was)
	if out > 0 and out != by and out != into:
		Session.tell(out, "%s unplugged %s from you." % [Session.name_of(by), what])


## How a player at `medium` (Presentation.Medium) takes out a jack that goes into them, in words:
## at a desk Shift+P with an empty hand, in a headset a press on the INTO ME jack on their left
## wrist; and, `own_jack` (an item or the harp, not a bandmate's keys, whose socket is on the
## bandmate), a press on its own jack as well.
static func unplug_how(medium: int, own_jack: bool) -> String:
	var how := "Shift+P with an empty hand" if medium == Presentation.Medium.SCREEN \
			else "A press on the INTO ME jack on your left wrist"
	return "%s%s unplugs it." % [how, ", or a press on its jack," if own_jack else ""]


## The medium player `peer` is in, as they said on joining (screen where not known).
func _medium_of(peer: int) -> int:
	if peer == Session.local_peer_id:
		return medium
	var p: Variant = Session.participants.get(peer)
	return int(p.medium) if p != null else Presentation.Medium.SCREEN


## Host: the studio's word on a jack's event (Session.jack_check): the room's patch and who has
## the source in hand (Jacks.send_refusal).
func _jack_refusal(to: int, source: StringName, from: int) -> String:
	if jacks == null:
		return "there is no room here to say where it goes"
	var item: Item = items.source_item(source) if items != null else null
	var holder := Session.holder_of(item.network_key()) if item != null else 0
	return Jacks.send_refusal(jacks.patch, source, to, from, holder, item != null and item.fixed)


## Somebody left: as host, every jack into them and out of their keys comes out.
func _on_jack_player_left(peer: int) -> void:
	if Session.role == Session.Role.HOST and jacks != null and jacks.drop_player(peer):
		_publish_room_soon()


## P with nothing in the mouse's hand: this player's own keys' jack steps on (a headset wears it on
## the wrist); Shift+P takes out every jack going into this player.
func _on_bare_jack(unplug: bool) -> void:
	if jacks == null:
		return
	if not unplug:
		jacks.step_source(Jack.keys_source(Session.local_peer_id), 1)
	elif jacks.unplug_mine() == 0:
		Session.notice.emit("Nothing is plugged into you.")


## This player's keys' jack, worn on the left wrist: on the tracked hand's wrist, and on the left
## controller while it is held, a hand's width back from the grip. The other hand presses it.
## Beside each, a little further up the arm, the socket for what goes into this player
## (JackSocket.into_me), there while anything does: a press takes it all out, as Shift+P does at a
## desk, and it is the only way a bandmate's keys come out of a headset player.
func _wear_wrist_jacks() -> void:
	if rig == null or rig.left == null or not rig.skeletons.has(rig.left) or not wrist_jacks.is_empty():
		return
	var skeleton := rig.skeletons[rig.left] as HandSkeleton
	var poke := rig.pokes.get(rig.left) as PokeInteractor
	var on_hand := JackSocket.new(null)
	on_hand.mine_keys = true
	on_hand.label = "MY KEYS"
	skeleton.wrist.add_child(on_hand)
	var on_controller := JackSocket.new(null)
	on_controller.mine_keys = true
	on_controller.label = "MY KEYS"
	on_controller.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.03, 0.09))
	on_controller.available = func() -> bool: return poke == null or not poke.tracked()
	rig.left.add_child(on_controller)
	var in_hand := JackSocket.new(null)
	in_hand.into_me = true
	in_hand.label = "INTO ME"
	# The wrist mount's +Y runs out toward the fingers: up the forearm, clear of MY KEYS' reach.
	in_hand.position = Vector3(0, -WRIST_IN_APART, 0)
	skeleton.wrist.add_child(in_hand)
	var in_controller := JackSocket.new(null)
	in_controller.into_me = true
	in_controller.label = "INTO ME"
	in_controller.transform = on_controller.transform.translated(Vector3(0, 0, WRIST_IN_APART))
	in_controller.available = on_controller.available
	rig.left.add_child(in_controller)
	wrist_jacks = [on_hand, on_controller, in_hand, in_controller]
	_wear_chord_jacks()


## The chord hand's jack (`chord:P`, MY CHORDS; part two, slice 33), worn on the chord hand as
## MY KEYS is: on the tracked hand's wrist and on its controller while it holds one. On the left
## hand it sits beside MY KEYS, down onto the back of the hand on the wrist and across the
## controller, clear of both reaches; a left-handed player's chord hand is the right, where it
## sits where MY KEYS does on the left. The other hand presses it, through each bandmate.
func _wear_chord_jacks() -> void:
	var controller: XRController3D = rig.left if ergonomics.handedness >= 0 else rig.right
	if controller == null or not rig.skeletons.has(controller):
		return
	var skeleton := rig.skeletons[controller] as HandSkeleton
	var poke := rig.pokes.get(controller) as PokeInteractor
	var beside := controller == rig.left
	var on_hand := JackSocket.new(null)
	on_hand.mine_chord = true
	on_hand.label = "MY CHORDS"
	on_hand.position = Vector3(0, WRIST_CHORD_APART if beside else 0.0, 0)
	skeleton.wrist.add_child(on_hand)
	var on_controller := JackSocket.new(null)
	on_controller.mine_chord = true
	on_controller.label = "MY CHORDS"
	on_controller.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.03, 0.09))
	if beside:
		on_controller.transform = on_controller.transform.translated(Vector3(WRIST_CHORD_APART, 0, 0))
	on_controller.available = func() -> bool: return poke == null or not poke.tracked()
	controller.add_child(on_controller)
	wrist_jacks.append_array([on_hand, on_controller])


## Whose hand has `item`, as this machine sees it: this player's when a hand here carries it,
## the holder's (or somebody's, -1) when a ghost does, else nobody's (0).
func _holder_here(item: Item) -> int:
	if item.carried_by != null:
		return Session.local_peer_id
	if item.is_held_elsewhere():
		var holder := Session.holder_of(item.network_key())
		return holder if holder != 0 else -1
	return 0


## An item left the room (ItemRoom.despawn: a Tour spill swallowed, a personal copy put back):
## its jack goes with it. Not one leaving with the whole room, which still lists it.
func _on_item_leaving(node: Node) -> void:
	var item := node as Item
	if item == null or jacks == null or items == null or items.items.has(item.id):
		return
	if jacks.drop(item.id):
		_publish_room_soon()


## Why a single track is not heard on this machine (`_hears_tracks`).
func _why_no_tracks() -> String:
	if Session.role == Session.Role.GUEST:
		return "a guest hears the host's mix as one stream."
	if DAW.backend is ReaperBackend:
		return "Reaper plays the tracks, not the game."
	return "the stand-in DAW makes no sound."


## Put `peer`'s receiver `receiver`'s plug in `socket`, or back in its tray (empty).
func _set_patch(peer: int, receiver: int, socket: StringName, show := true) -> void:
	if receiver < 0 or receiver >= PersonalMix.RECEIVERS:
		return
	var row: Array = []
	for i in PersonalMix.RECEIVERS:
		var had: Array = patches.get(peer, [])
		row.append(String(had[i]) if i < had.size() else "")
	row[receiver] = String(socket)
	if row.all(func(s: String) -> bool: return s == ""):
		patches.erase(peer)
	else:
		patches[peer] = row
	if show:
		_show_patches()


## Everyone's plugs in the sockets, in their colours, and this person's own in their ears.
func _show_patches() -> void:
	personal.hears_tracks = _hears_tracks()
	personal.set_sockets(patches.get(Session.local_peer_id, []))
	var peers := patches.keys()
	peers.sort()
	# The desk's sockets once it is built (it builds a frame or two after the studio, and shows
	# them then: `console.rebuilt`); a bandmate's pack and the racks' OUTs whether it is or not.
	var sockets: Array[SendSocket] = []
	if console != null and console.master != null:
		sockets.append_array(console.master.sends)
		for strip in console.strips:
			sockets.append(strip.send)
	# Every effects rack's OUT: the main one and each track pulled out on a rack of its own.
	var racks: Array = [rack] if rack != null else []
	for id in track_racks:
		racks.append(track_racks[id][1])
	for r: RackSurface in racks:
		if is_instance_valid(r):
			sockets.append_array(r.out_sockets())
	if presence != null:
		for peer in Session.participants:
			var avatar := presence.avatar_of(peer)
			if avatar != null:
				avatar.set_on_air(peer in on_air, peer)
		for avatar: Presence.Avatar in presence.avatars():
			if avatar.send != null:
				sockets.append(avatar.send)
			if avatar.monitor_send != null:
				sockets.append(avatar.monitor_send)
	var tablet := items.items.get(&"tablet") as TabletItem if items != null else null
	if tablet != null:
		tablet.on_air = Session.local_peer_id in on_air
	for socket in sockets:
		if not socket.pressed.is_connected(_on_send_pressed):
			socket.pressed.connect(_on_send_pressed.bind(socket.source))
		var colours: Array[Color] = []
		for peer in peers:
			for s: String in patches[peer]:
				if StringName(s) == socket.source:
					colours.append(_colour_of(peer))
		socket.set_plugs(colours)


## A SEND socket clicked: this person's plugs in it come back to their tray. With none in it,
## where the plugs are.
func _on_send_pressed(source: StringName) -> void:
	var mine: Array = patches.get(Session.local_peer_id, [])
	var any := false
	for i in mine.size():
		if StringName(mine[i]) == source:
			_on_patch_asked(i, &"")
			any = true
	if not any:
		Session.notice.emit("Drag a plug onto %s from your tablet: it lies on the prop shelf's lower tier."
				% PersonalMix.place_of(source))


## Who is here changed: colours may have, and a guest who left takes their plugs with them.
func _on_roster_for_patches() -> void:
	var tablet := items.items.get(&"tablet") as TabletItem if items != null else null
	if tablet != null:
		tablet.colour = _colour_of(Session.local_peer_id)
	if Session.role == Session.Role.HOST:
		for peer in patches.keys():
			if not Session.participants.has(peer):
				patches.erase(peer)
				_publish_room_soon()
		for peer in on_air.duplicate():
			if not Session.participants.has(peer):
				_set_on_air(peer, false, false)
				_publish_room_soon()
		# And the plugs in the keys of whoever left come back to their trays.
		for peer in patches.keys():
			var row: Array = patches[peer]
			for i in row.size():
				var into := PersonalMix.player_of(StringName(row[i]))
				if into > 0 and not Session.participants.has(into):
					_set_patch(peer, i, &"", false)
					_publish_room_soon()
	# After the ghosts: a new one's pack is made on the same news.
	_show_patches.call_deferred()


## The ON AIR switch on the tablet in a hand here: done here at once, and asked of the host.
func _on_air_asked(on: bool) -> void:
	_set_on_air(Session.local_peer_id, on)
	if Session.is_authority():
		_publish_room_soon()
	else:
		_predict(&"on_air", [on])
	if on:
		Session.notice.emit("On air: anyone can plug into the MONITOR on your pack and hear your keys in time with the backing you play to.")
	else:
		Session.notice.emit("Off air: the plugs in your monitor went back to their trays.")


## `peer` ON AIR or off. Off, the plugs in their monitor come back to their owners' trays: the
## host's to do, as it keeps the table; a guest predicting its own leaves the others to it.
func _set_on_air(peer: int, on: bool, show := true) -> void:
	if on and peer not in on_air:
		on_air.append(peer)
		on_air.sort()
	elif not on:
		on_air.erase(peer)
		if Session.is_authority():
			for listener in patches.keys():
				var row: Array = patches[listener]
				for i in row.size():
					if PersonalMix.monitor_of(StringName(row[i])) == peer:
						_set_patch(listener, i, &"", false)
	if show:
		_show_patches()


func _colour_of(peer: int) -> Color:
	var p: Session.Participant = Session.participants.get(peer)
	return p.colour if p != null else SendSocket.LAMP


var _made_remember_due := false


## Where the made items are, kept once at the end of the frame (a rack slot taken, a put-down).
func _remember_made_soon() -> void:
	if _made_remember_due:
		return
	_made_remember_due = true
	_remember_made_due.call_deferred()


func _remember_made_due() -> void:
	_made_remember_due = false
	_remember_made()


## A hand here put an item down, or sent it home: a guest asks the host, having done it already.
## A host's room is told by the item moving (`_publish_room_soon`).
func _on_items_asked(verb: StringName, args: Array) -> void:
	if not Session.is_authority():
		_predict(verb, args)


## The room told once at the end of the frame, however many things in it moved during it.
func _publish_room_soon() -> void:
	if Session.role != Session.Role.HOST or _applying_room or _room_publish_due:
		return
	_room_publish_due = true
	# A method and not a lambda: a studio freed before the frame ends is skipped, not called.
	_publish_room_due.call_deferred()


func _publish_room_due() -> void:
	_room_publish_due = false
	_publish_room()



## Off your head into the mouse's hand, or on from it.
func _toggle_headphones() -> void:
	var hand := get_node_or_null("MouseHand") as Interactor
	if hand == null:
		return
	if hand.worn != null:
		if not hand.take_off():
			Session.notice.emit("Your hand is full: put down what is in it first (Q).")
	elif hand.carrying != null and hand.carrying.wearable():
		hand.wear()


## Pocket `slot` and the mouse's hand: swapped.
func _pocket(slot: int) -> void:
	var hand := get_node_or_null("MouseHand") as Interactor
	if hand == null or hand.pockets == null:
		return
	if hand.swap_pocket(slot):
		_say_pockets(hand)
	else:
		Session.notice.emit("Your %s pocket is empty." % Pockets.NAMES[slot])


func _say_pockets(hand: Interactor) -> void:
	Session.notice.emit("Pockets: %s" % hand.pockets.summary())


## Put down whatever any hand here is carrying, where it is aiming.
func put_down_items() -> void:
	for hand in get_tree().get_nodes_in_group(Interactor.GROUP):
		var interactor := hand as Interactor
		if interactor != null and interactor.carrying != null:
			interactor.put_down()


func _build_walker() -> void:
	walker = Walker.new()
	walker.name = "Walker"
	walker.camera = camera
	walker.floor_plan = floor_plan
	walker.walkable = _walkable()
	walker.fixed = venue.solids() if venue != null else []
	walker.solids_parent = studio_set
	walker.standing_eye = ergonomics.eye_height
	walker.eye_height = ergonomics.eye_height
	add_child(walker)
	floor_plan.bodies.append(walker.body_footprint)
	# At the mix position, looking down at the desk. Aimed at a POINT on it rather than set to
	# an angle, because the desk does not move when the eye does: -0.5 rad was right from a
	# standing 1.62 m and, from a seated 1.21 m, put the faders' tops up under the timeline.
	walker.global_position = Vector3(0, 0, MIX_POSITION_Z)
	walker.pitch = -atan2(ergonomics.eye_height - DESK_GAZE.y, DESK_GAZE.x)
	walker.active = not god_mode
	walker._place_camera()


## Swap between walking and flying. The handover keeps the view: going up, the orbit takes the
## walker's eye and a point in front of it; coming down, the walker lands under wherever the
## camera was, inside the room, facing the same way.
func set_god_mode(on: bool) -> void:
	god_mode = on
	if walker == null:
		return
	walker.active = not on
	if on:
		var forward := -walker.look_basis().z
		var at := walker.eye() + forward * 1.6
		frame(at, 1.6, walker.yaw, walker.pitch)
	else:
		var from := camera.global_position
		var b := floor_plan.bounds if floor_plan != null else Rect2(-3, -2, 6, 4.8)
		walker.global_position = Vector3(clampf(from.x, b.position.x + 0.3, b.end.x - 0.3), 0.0,
				clampf(from.z, b.position.y + 0.3, b.end.y - 0.3))
		walker.velocity = Vector3.ZERO
		walker.yaw = _orbit_yaw
		walker.pitch = clampf(_orbit_pitch, -1.2, 0.6)
		walker.eye_height = walker.standing_eye
		walker._place_camera()


## The keys that take you somewhere else: F to the gear (and the seat), I to the next instrument,
## V to the next venue, N up out of your body.
const MOVES_YOU := [KEY_F, KEY_I, KEY_V, KEY_N]


## Whether `keycode` is one that would move you while a piano has the keyboard (KeyCatcher: the
## modular's PLAY, the keytar, the fingertips): held back, so a stray I in the middle of a phrase
## does not carry you off to another instrument with the keys still playing this one. Said, so the
## way on (Esc first) is not a guess.
func _held_while_playing(keycode: int) -> bool:
	if not keycode in MOVES_YOU or get_viewport() == null \
			or not get_viewport().gui_get_focus_owner() is KeyCatcher:
		return false
	Session.notice.emit("The keys are playing: Esc gives them back, then %s moves you." % OS.get_keycode_string(keycode))
	return true


## Orbit on right-drag, zoom on wheel, WASD to walk. Not a replacement for standing in the room;
## it is how the screen half of a hybrid session gets around, and how every screenshot of this
## project is framed.
func _unhandled_input(event: InputEvent) -> void:
	if camera == null:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) \
			and not god_mode and walker != null:
		walker.look(event.relative)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_orbit_yaw -= event.relative.x * 0.005
		_orbit_pitch = clampf(_orbit_pitch - event.relative.y * 0.005, -1.4, 1.2)
		_update_camera()
	elif event is InputEventKey and event.keycode == KEY_R and not event.echo:
		# Hold to wind up a throw of what you carry, let go to throw it where the cursor is.
		# R: beside Q, which puts it down, under the same hand.
		var hand := get_node_or_null("MouseHand") as MouseInteractor
		if hand != null:
			if event.pressed:
				hand.begin_throw()
			else:
				hand.release_throw()
	elif event is InputEventKey and event.keycode == KEY_K and not event.echo and not event.ctrl_pressed:
		# The desktop's clap: K held over a track mutes it while held, a tap latches it.
		# Held for as long as the frames say (_follow_clap), the clock a clap is timed by.
		if event.pressed and not key_clap.pressed:
			key_clap.press(_mouse_track(), true)
		elif not event.pressed and key_clap.pressed:
			key_clap.release(key_clap.held_for())
	elif event is InputEventKey and event.keycode == KEY_U and not event.echo and not event.ctrl_pressed:
		# Look to solo: U held, with the signal view on, solos the track under the cursor alone.
		if event.pressed:
			look_solo_press(&"key")
		else:
			look_solo_release(&"key")
	elif event is InputEventKey and event.keycode == KEY_L and not event.echo and not event.ctrl_pressed:
		# Lean in to the stage voice under the cursor while L is held.
		_lean_key = event.pressed
		_follow_lean()
	elif event is InputEventKey and event.pressed and not event.echo and _held_while_playing(event.keycode):
		pass
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			# Walk the gear past you one piece at a time, and off either end to put it back.
			# Shift goes the other way. One key, no modifier needed to start, and the exit is
			# where you would find it by accident.
			KEY_F:
				focus.cycle(-1 if event.shift_pressed else 1)
				_sit_down()
			# The other half of the desk. A console pages by default, because twelve strips
			# you can face beats forty-eight you have to turn your head through -- but a
			# mix is sometimes a thing you want to see all of at once, and then the tiers
			# are worth the neck. One key, and it is the one the desk is named after.
			KEY_E:
				_toggle_expanded()
			KEY_G:
				_toggle_summoning()
			# Somewhere else to stand. The setup comes along; only the world changes.
			KEY_V:
				cycle_venue()
			# The history, from anywhere in the room. The deck has keys for it too.
			KEY_Z when event.ctrl_pressed:
				DAW.redo() if event.shift_pressed else DAW.undo()
			KEY_Y when event.ctrl_pressed:
				DAW.redo()
			# Split the selected items at the playhead. B for blade: S is walking backwards.
			KEY_B:
				DAW.split_selected(DAW.state.position_seconds)
			# Put down what you are carrying, where you are looking. Q: the key under the hand
			# that is on WASD, and the one games drop things with.
			KEY_Q:
				put_down_items()
			# Headphones on, or off into your hand. H: beside the hand's other item keys.
			KEY_H:
				_toggle_headphones()
			# See the signal (docs/spatial_loop.md part three): X, an x-ray of the mix, with or
			# without the glasses. G was taken by the gear's summoning.
			KEY_X when not event.ctrl_pressed and not event.meta_pressed:
				toggle_signal_view()
			# Why can't I hear this? Y over it, with the signal showing; Shift-Y does the fix.
			KEY_Y when not event.ctrl_pressed and not event.meta_pressed:
				if event.shift_pressed:
					fix_traced()
				else:
					trace_pointed(get_node_or_null("MouseHand") as Interactor)
			# Your pockets: left hip, right hip, back. What is in the hand goes in, and what was
			# in comes out.
			KEY_1, KEY_2, KEY_3:
				_pocket(event.keycode - KEY_1)
			# The desk's six drum pads, KICK to RIM along its front rail: 4 to 9, the number row's
			# next six after the pockets.
			KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				strike_desk_pad(event.keycode - KEY_4, event.shift_pressed)
			# Leave your body and fly, or come back down into it.
			KEY_N:
				set_god_mode(not god_mode)
			# Your fingertips as notes, on J K L ;: T, beside the home row they play on.
			KEY_T:
				toggle_fingertips()
			# The computer keyboard as a piano, to play whatever instrument is on the track: P.
			KEY_P when not event.ctrl_pressed and not event.meta_pressed:
				computer_keys_toggled.emit()
			# The chord layer: C for chords. 1 to 7 then pick them in the keys that play.
			KEY_C when not event.ctrl_pressed and not event.meta_pressed:
				toggle_chords()
			# Go to the instruments one at a time, as F goes to the gear: I for instrument.
			# Shift goes the other way. The help card's PLAY pages go to one by name.
			KEY_I:
				cycle_stations(-1 if event.shift_pressed else 1)
			KEY_ESCAPE:
				_on_escape()
			# Backspace over a voice on the stage table, or anything of its tag: that track back to
			# centre, 0 dB and full width, as a double-click on it does.
			# Over a block in the marble run's lattice (or with one picked up), it is taken out.
			KEY_BACKSPACE:
				var hand := get_node_or_null("MouseHand") as MouseInteractor
				var under: Node = (hand.held if hand.held != null else hand.hovered) if hand != null else null
				if marbles != null and is_instance_valid(marbles) and hand != null and marbles.take_out_under(under):
					pass
				elif stage != null and hand != null:
					stage.reset_under(under)
			# [ and ] over a section block on the bricks table: it a place earlier or later, as one
			# rearrangement of the song; again with the cursor still, the same block on. Held, it
			# moves in the held order, written when it is let go.
			KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
				var hand := get_node_or_null("MouseHand") as MouseInteractor
				if sections != null and is_instance_valid(sections) and hand != null:
					sections.step_under(hand.held if hand.held != null else hand.hovered,
							-1 if event.keycode == KEY_BRACKETLEFT else 1, hand.hover_point)
			# Comfort and eyesight, live, because the only way anyone finds the right value is
			# by changing it while looking at the thing.
			KEY_EQUAL, KEY_KP_ADD:
				_set_text_scale(ergonomics.text_scale * 1.15)
			KEY_MINUS, KEY_KP_SUBTRACT:
				_set_text_scale(ergonomics.text_scale / 1.15)
			KEY_0:
				_set_text_scale(1.0)
	elif event is InputEventMouseButton and event.pressed:
		# The wheel goes through what you carry while you carry anything; ctrl and the wheel
		# still zooms.
		var hand := get_node_or_null("MouseHand") as MouseInteractor
		var notches := 1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0
		# A marble run's block in the mouse's hand: the wheel turns it, Shift and the wheel move the
		# layer it goes on, wherever the cursor is.
		if notches != 0 and not event.ctrl_pressed and marbles != null and is_instance_valid(marbles) \
				and marbles.carried_by_mouse():
			if event.shift_pressed:
				marbles.move_layer(-notches)
			else:
				marbles.turn_carried(-notches)
			return
		if notches != 0 and not event.ctrl_pressed and hand != null and hand.pockets != null \
				and (hand.carrying != null or not hand.pockets.items().is_empty()):
			if hand.cycle_pockets(notches):
				_say_pockets(hand)
			return
		if not god_mode and walker != null:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				camera.fov = maxf(30.0, camera.fov - 3.0)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				camera.fov = minf(ROOM_FOV, camera.fov + 3.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_distance = maxf(0.4, _orbit_distance - 0.12)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_distance = minf(6.0, _orbit_distance + 0.12)
			_update_camera()


## A level to give the venue in place of the mix's (0..1), or -1 for the mix's own: for a
## photograph of a room at a chosen loudness (`--feed-level`).
var fed_level := -1.0


# --- strikes on the fast path (docs/spatial_loop.md part two, slice 39) ---------------------------

## The hits' helper started, where it can run as the keys' does (MonitorSynth.start's conditions:
## a sound card, the ports not bypassed, NativeKeys buildable, R3D_GODOT_KEYS not set), and Foley's
## struck sounds written and loaded into it. Until they are loaded, and wherever it cannot run,
## hits play on MONITOR through Godot, and the tag says so.
func _start_hit_voices() -> void:
	if hit_voices != null or not MonitorSynth.available() or AudioPorts.direct \
			or OS.get_environment("R3D_GODOT_KEYS") == "1" or not NativeKeys.available():
		return
	var keys := NativeKeys.new()
	if not keys.start(AudioPorts.target, false, "dawlings · hits"):
		return
	hit_voices = keys
	hit_voices.load_hits()


## The helper's news read each frame: what it has loaded, how late it is; and if it has gone,
## every hit back on MONITOR.
func _follow_hit_voices() -> void:
	if hit_voices == null:
		return
	hit_voices.poll()
	if not hit_voices.running():
		push_warning("The hits' helper stopped; playing them through the app instead.")
		hit_voices.stop()
		hit_voices = null


## InstrumentItem.fast_path: this player's own hit on the helper, if it holds that sound.
func _hit_on_fast_path(kind: StringName, take: int, gain: float, pan: float, speed: float) -> bool:
	return hit_voices != null and hit_voices.play_hit(kind, take, gain, pan, speed)


## InstrumentItem.fast_latency: the helper's figure once its sounds are in, else -1 (MONITOR).
func _fast_path_latency() -> float:
	if hit_voices == null or hit_voices.loaded.is_empty():
		return -1.0
	return hit_voices.hit_latency()


func _process(delta: float) -> void:
	_follow_hit_voices()
	_follow_signal(delta)
	_drive_pushed()
	_refresh_looms_if_moved(delta)
	_follow_clap(delta)
	_follow_look_solo(delta)
	_follow_lean()
	_follow_ear()
	_follow_keytar()
	_follow_harp()
	_follow_wheel()
	_follow_strings()
	_follow_theremin()
	_follow_modular()
	_follow_making()
	_follow_gives(delta)
	_follow_kit()
	if venue != null and DAW.state != null:
		# A room that holds still for anyone who has asked it to (COMFORT's "Room reacts").
		venue.reactive = ergonomics.room_reacts
		venue.lift_on_clip = ergonomics.lift_on_clip
		venue.pulse(fed_level if fed_level >= 0.0 else maxf(DAW.state.master.vu_l, DAW.state.master.vu_r))
		follow_clip(delta)
	if camera == null or not god_mode:
		return
	# Not while typing a name into the session panel, or every "s" in it flies backwards.
	if get_viewport().gui_get_focus_owner() != null:
		return
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move.z -= 1.0
	if Input.is_key_pressed(KEY_S): move.z += 1.0
	if Input.is_key_pressed(KEY_A): move.x -= 1.0
	if Input.is_key_pressed(KEY_D): move.x += 1.0
	if move != Vector3.ZERO:
		var yaw := Basis(Vector3.UP, _orbit_yaw)
		_orbit_target += yaw * move.normalized() * delta * 1.4
		_update_camera()


## Move a surface to where the focus rig wants it, over time rather than instantly.
##
## The glide is not decoration. Something large arriving next to your face with no transit is
## disorienting and leaves you unsure what you are now looking at; watching it travel tells you
## which thing came and where it came from. It is also the first thing someone prone to motion
## sickness needs to turn off, which is why the duration is a property of the person.
func _glide(surface: Surface, parent: Node3D, local: Transform3D) -> void:
	# Reparented first, keeping the world pose, so the travel is computed inside the frame it is
	# travelling to. Reparenting at the END would teleport the surface on arrival; reparenting
	# without keeping the pose teleports it on departure.
	if parent != null and surface.get_parent() != parent:
		surface.reparent(parent, true)
	var seconds := 0.42 * clampf(ergonomics.motion_scale, 0.0, 2.0)
	if seconds <= 0.01:
		surface.transform = local
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(surface, "transform", local, seconds)


## Lettering is sized once, when a label is built, and then enforced by the rendering server.
## So changing whose eyes it is for means rebuilding the labels -- which is cheap, and is the
## honest consequence of the visibility range being server-side rather than per-frame script.
func _set_text_scale(to: float) -> void:
	ergonomics.text_scale = clampf(to, 0.4, 4.0)
	Ergonomics.current = ergonomics
	for node in find_children("*", "Node3D", true, false):
		if node is Surface:
			(node as Surface).mark_dirty()
	if focus != null and focus.is_focused():
		focus.focus(focus.focused_id)


## Put the screen camera where the mixer is standing, looking at whatever they just summoned.
##
## Focusing moves the gear to the body. On a monitor that is only half the gesture: the body is
## a fixed mix position, so without this you summon a console to a spot in the room and then go
## on watching it from wherever you happened to be orbiting -- usually behind and above it,
## where a wrapped desk reads as four tiers of scaffolding rather than as a desk. The whole
## point of an arc is that it is right from ONE place.
##
## A no-op in AR and VR, where the camera is a head and moving it is not ours to do.
## Swap the focused desk between its paged bank and its full width.
##
## Only the console has two sizes, so this does nothing anywhere else rather than inventing a
## meaning for "expanded" on a tape deck. The re-seat comes free: the desk emits `rebuilt`, and
## the camera is already listening for that.
func _toggle_expanded() -> void:
	if focus == null or not focus.is_focused():
		return
	for surface in focus.surfaces:
		if surface.surface_id != focus.focused_id:
			continue
		var console := surface as ConsoleSurface
		if console != null:
			console.expanded = not console.expanded
		return


## Keep the rig's idea of the frame in step with the actual window.
##
## Resizing changes how much gear fits in view, and gear placed for the old shape is cropped by
## the new one. Cheap enough to redo on every resize: it sets one number and marks the surfaces,
## and a person dragging a window edge is not in the middle of anything precise.
func _follow_viewport_shape() -> void:
	var view := get_viewport()
	if view == null:
		return
	var size := view.get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var aspect := size.x / size.y
	if is_equal_approx(aspect, ergonomics.view_aspect):
		return
	ergonomics.view_aspect = aspect
	if focus != null:
		for surface in focus.surfaces:
			surface.mark_dirty()


## A surface someone's hand caught in SCREEN mode by accident -- the handle that does it is a
## small bar beside whichever control they actually meant to reach, and once its surface fills
## the view the handle is off at the edge of a much bigger picture, nowhere near where they
## would think to look for it (2026-10-11: "escape was not working" trying to get a
## full-screened rack back). Leaves a surface that is in SCREEN mode on purpose -- the timeline
## defaults there -- exactly alone.
## Escape on a keyboard, the menu button or two fists in a headset: let go of what has focus, send
## anything pinned to the face back where it belongs, and sit back down at the desk.
func _on_escape() -> void:
	# A marble run's block in the mouse's hand goes back, and that is all Esc does.
	if marbles != null and is_instance_valid(marbles) and marbles.carried_by_mouse():
		marbles.drop("The block is back in its cell." if marbles.lifted != MarbleRun.NONE else "The block is back on the tray.")
		return
	# An end of string in the mouse's hand goes back on the spool, and that is all Esc does.
	if spool != null and is_instance_valid(spool) and spool.carrying():
		spool.drop("The end is back on the spool.")
		return
	if focus != null:
		focus.release()
	_release_stray_screens()
	_sit_down()


func _release_stray_screens() -> void:
	for id in mount.mounted_ids():
		if mount.mode_of(id) == Presentation.Mode.SCREEN \
				and mount.mode_of(id) != mount.default_mode_of(id, medium):
			mount.set_mode(id, mount.default_mode_of(id, medium))


func _sit_down() -> void:
	if camera == null or body == null or medium != Presentation.Medium.SCREEN:
		return
	if focus != null and focus.visits:
		_walk_to_seat()
		return
	# Aimed at where focused gear GOES, not at where the focused surface currently is. Asking
	# the surface was the first version, and it reads its bounds a frame too early -- focus
	# moves the surface immediately but the rebuild that gives it its shape happens on the next
	# _process, so the camera was aimed using the previous layout's box and ended up on the
	# floor looking at a lamp. This point is a property of the body, which is already final.
	var eye := body.global_position
	var drop := deg_to_rad(ergonomics.gaze_down)
	var ahead := Vector3(0, -sin(drop), -cos(drop)) * ergonomics.working_distance()
	var at: Vector3 = eye + body.global_transform.basis * ahead
	# Aimed at the focused surface's own middle once it HAS one. Reading its bounds is only
	# safe after the rebuild -- focus moves a surface immediately but the rebuild that gives it
	# its shape happens on the next _process -- so this takes the measurement when it is real
	# and falls back to the body's working point when it is not.
	if focus != null and focus.is_focused():
		for surface in focus.surfaces:
			if surface.surface_id == focus.focused_id:
				var box := surface.content_aabb()
				if box.size.y > 0.01:
					# Aimed at where the surface is GOING, not where it currently is. Gear
					# glides to the mix position over a few hundred milliseconds, and the
					# camera is seated the instant placement is decided -- reading the live
					# transform aims it at a console still halfway across the room, and
					# nothing fires afterwards to correct it once the tween lands. This is
					# why `--focus rack` kept coming back as a photograph of the floor even
					# after the signal race behind it was fixed: two separate bugs with one
					# symptom, and fixing the first changed the render not at all.
					#
					# Dead centre of the box, not a quarter up it. The lift was there to
					# stop the camera staring into the desk's underside, and the underside
					# was really the carcass being counted as content, which it no longer is.
					var target := body.global_transform * focus.placement(surface, 0)
					at = target * box.get_center()
	var back := eye - at
	# Through frame() rather than by assigning the four orbit fields, which is what the version
	# before that did: those values are only read when something applies them, so setting them
	# and stopping leaves the camera exactly where it was. The render came back identical twice
	# and both times read as a placement bug rather than a call that never reached the camera.
	#
	# Negative pitch, because the offset is built with Basis(RIGHT, pitch), which sends +pitch
	# DOWN -- the eye is above the desk, so it wants the sign that lifts it.
	# A longer lens while you are working at something. The default 75-degree field is right
	# for walking around a room and wrong for standing over a desk: at half a metre it bows the
	# arc outward at the edges and spends most of the frame on everything that is not the desk.
	# Nobody photographs a console on a wide angle either, and for the same reason.
	camera.fov = SEATED_FOV if focus.is_focused() else ROOM_FOV
	frame(at, back.length(), atan2(back.x, back.z),
			-atan2(back.y, Vector2(back.x, back.z).length()))


## Where the mix position stands when nothing is being visited.
func _home_seat() -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(0, ergonomics.eye_height, MIX_POSITION_Z))


## Visiting: walk the mix position over to the focused gear and look at it from there.
##
## The body goes, not just the lens, because the body is what carries the work light -- and
## because "where I am standing" is what release has to undo. A surface that is not standing in
## the room (a timeline on the monitor) has no seat; focusing it leaves you where you are.
func _walk_to_seat() -> void:
	var seat := _home_seat()
	var look_at := Vector3.ZERO
	var target: Surface = null
	if focus.is_focused():
		for surface in focus.surfaces:
			if surface.surface_id == focus.focused_id:
				target = surface
	# A surface that is a station mounted in a zone (the modular wall, slice 51) is visited where its
	# station is played: where `seat_for` would stand a desk to fit it, the bricks table stands, and
	# the fifths wheel's board across the view.
	if target != null and target == modular_wall and venue != null and Stations.spot(venue, Modular.STATION) != null:
		_walk_to_station(Modular.STATION)
		return
	# Anywhere in the set: a tablet stands on its own stand, a level further down.
	if target != null and studio_set.is_ancestor_of(target):
		var box := target.content_aabb()
		if box.size.y > 0.01:
			seat = focus.seat_for(target)
			# Inside the room and at a height a person's eyes can be at. A rack's bottom unit
			# asks for a seat on the floor; nobody mixes lying down.
			var bounds := floor_plan.bounds if floor_plan != null \
					else _room_bounds()
			seat.origin = Vector3(
					clampf(seat.origin.x, bounds.position.x + 0.2, bounds.end.x - 0.2),
					clampf(seat.origin.y, 0.95, 1.95),
					clampf(seat.origin.z, bounds.position.y + 0.2, bounds.end.y + 0.6))
			look_at = target.global_transform * box.get_center()
	elif target != null:
		return
	_stand_down_screen(target != null)
	if look_at == Vector3.ZERO:
		var drop := deg_to_rad(ergonomics.gaze_down)
		look_at = seat * (Vector3(0, -sin(drop), -cos(drop)) * ergonomics.working_distance())
	camera.fov = SEATED_FOV if target != null else ROOM_FOV
	var back := seat.origin - look_at
	var to := [look_at, back.length(), atan2(back.x, back.z),
			-atan2(back.y, Vector2(back.x, back.z).length())]
	var seconds := 0.55 * clampf(ergonomics.motion_scale, 0.0, 2.0)
	if seconds <= 0.01 or not is_inside_tree():
		body.transform = seat
		frame(to[0], to[1], to[2], to[3])
		return
	# Both at once, on one curve. A body that arrived before its camera would leave the work
	# light lighting the gear from an empty spot for half a second; a camera that arrived first
	# would see the light swing in after it.
	if walker != null and not god_mode:
		_orbit_target = to[0]
		walker.travel_to(seat.origin, look_at, seconds)
		if _walk != null and _walk.is_valid():
			_walk.kill()
		_walk = create_tween()
		_walk.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_walk.tween_property(body, "transform", seat, seconds)
		return
	var body_from := body.transform
	var cam_from := camera.global_transform
	frame(to[0], to[1], to[2], to[3])
	var cam_to := camera.global_transform
	camera.global_transform = cam_from
	if _walk != null and _walk.is_valid():
		_walk.kill()
	_walk = create_tween()
	_walk.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_walk.tween_method(func(t: float) -> void:
		body.transform = body_from.interpolate_with(seat, t)
		camera.global_transform = cam_from.interpolate_with(cam_to, t), 0.0, 1.0, seconds)


var _walk: Tween


## The monitor's own panels step aside while you are over at a piece of gear.
##
## A surface on the screen stage hangs off the lens, so walking to the console carries the
## timeline with you and holds it a hand's width in front of the desk you walked over to see --
## the first honest visit render was a timeline with a console somewhere behind it. Summoning
## never showed this because it pulled the timeline into the arc with everything else.
##
## Disabled as well as hidden: a hidden ControlAffordance is still in the physics space, and
## a click aimed at a fader would land on the invisible clip lane in front of it.
func _stand_down_screen(away: bool) -> void:
	if screen_stage == null:
		return
	screen_stage.visible = not away
	screen_stage.process_mode = Node.PROCESS_MODE_DISABLED if away \
			else Node.PROCESS_MODE_INHERIT


## Visit the gear, or have it brought. Visiting is the monitor's default; bringing is still
## the right answer for some work -- a patchbay you want flat in front of you -- and is how a
## headset works, so it is one key away rather than gone.
func _toggle_summoning() -> void:
	var was := focus.focused_id
	focus.release()
	focus.visits = not focus.visits
	if not focus.visits:
		# Summoned gear lands in front of the mix position, so the mix position has to be back
		# where it stands before anything is summoned to it.
		_stand_down_screen(false)
		body.transform = _home_seat()
	if was != &"":
		focus.focus(was)
	_sit_down()


# --- going to the instruments (docs/spatial_loop.md part two, slice 10) ------------------------

## The station last gone to (a Stations id), so I and Shift-I go on round from it; empty before
## the first.
var station := &""


## The stations that stand here, in Stations' order: none in AR, where the room is a real one and
## nothing stands in it yet (slice 60), and none without a venue.
func station_ids() -> Array[StringName]:
	if medium == Presentation.Medium.AR or venue == null:
		return []
	return Stations.ids(venue)


## I and Shift-I: go to the next station, or the one before, from the one last gone to, round
## and round. Unlike F's cycle there is no end to walk off: Esc is the way back to the desk, and
## the toast at each one says so. Answers the station gone to, or empty.
func cycle_stations(direction: int) -> StringName:
	var ids := station_ids()
	if ids.is_empty():
		Session.notice.emit("No instruments stand in this room.")
		return &""
	var at := ids.find(station)
	var next := (0 if direction >= 0 else ids.size() - 1) if at < 0 \
			else posmod(at + (1 if direction >= 0 else -1), ids.size())
	return ids[next] if go_to_station(ids[next]) else &""


## Walk to station `id`: the walker eased to its seat (Stations.seat, SEAT in front of it on
## floor a person fits on), facing what is played, on the curve visiting gear uses
## (`_walk_to_seat`), longer for a longer way and scaled by Ergonomics.motion_scale (a cut at 0),
## and looking where it holds the station's controls in view (Stations.look_from). God mode is
## left first and focused gear let go, and the monitor's own panels step aside, as they do at
## gear, so the instrument is in full view. The body goes too, as it does to gear,
## so Esc walks back to the desk. A toast says its title and its desk line. In a headset the
## play space travels there instead (`_travel_to_station`). False where it does not stand here,
## or travel is refused.
func go_to_station(id: StringName) -> bool:
	var r := Stations.row(id)
	if r.is_empty() or not station_ids().has(id):
		Session.notice.emit("%s does not stand in this room." % r.get("title", String(id)))
		return false
	# A headset puts the rows beside a plaque away only once it goes: refused, they stay up and
	# say why, where the press was made.
	if medium != Presentation.Medium.SCREEN or camera == null:
		return _travel_to_station(id)
	_put_away_beside()
	if god_mode:
		set_god_mode(false)
	if focus != null and focus.is_focused():
		focus.release()
	station = id
	_walk_to_station(id)
	Session.notice.emit("%s, %s: %s  ·  Esc back to the desk" % [r["title"], Stations.where(r), r["desk"]])
	return true


## The walk (or the cut, at motion 0) to station `id`'s seat, the look framing it from there: for going
## to it, and for visiting a surface that is one (the modular wall, `_walk_to_seat`).
func _walk_to_station(id: StringName) -> void:
	var fits := walker.fits if walker != null else Callable()
	var frame_of := venue.global_transform if venue.is_inside_tree() else venue.transform
	var seat: Transform3D = frame_of * (Stations.seat(venue, id, fits) as Transform3D)
	_stand_down_screen(true)
	camera.fov = ROOM_FOV
	var standing := walker.standing_eye if walker != null else ergonomics.eye_height
	var eye := seat.origin + Vector3(0, standing, 0)
	# Framed from where you actually stand, which the room may have brought in short of SEAT:
	# the look tips to hold the station's top and foot, its controls' top first.
	var look: Vector3 = frame_of * (Stations.look_from(venue, id, frame_of.affine_inverse() * eye, camera.fov) as Vector3)
	var from := walker.global_position if walker != null else camera.global_position
	var way := Vector2(eye.x - from.x, eye.z - from.z).length()
	var seconds := clampf(way / STATION_PACE, 0.55, 2.0) * clampf(ergonomics.motion_scale, 0.0, 2.0)
	if not is_inside_tree():
		seconds = 0.0
	var stand := Transform3D(seat.basis, eye)
	if walker != null:
		walker.eye_height = walker.standing_eye
		_orbit_target = look
		walker.travel_to(eye, look, seconds)
	else:
		var back := eye - look
		frame(look, back.length(), atan2(back.x, back.z), -atan2(back.y, Vector2(back.x, back.z).length()))
	if body != null and focus != null and focus.visits:
		if _walk != null and _walk.is_valid():
			_walk.kill()
		if seconds <= 0.01:
			body.transform = stand
		else:
			_walk = create_tween()
			_walk.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
			_walk.tween_property(body, "transform", stand, seconds)


## How fast going to a station covers the floor (m/s), at motion 1: a brisk walk, so the live
## room's far wall is a second and a half from the desk rather than a lurch.
const STATION_PACE := 4.0


# --- going to a station in a headset (docs/spatial_loop.md part two, slice 11) -----------------

## The station board's stand, back by the way into the live room on the right, turned to face the
## mix position: out of the seat's view of the desk (it stood at the desk's left elbow, in the face
## of everyone who sat down), and on the way to the stations it lists. Desktop players reach the
## same rows with I and F1; a headset player turns round to it.
const BOARD_AT := Vector3(2.2, 0, 2.9)
const BOARD_HEADING := 223.0

## The board by the desk (StationBoard): every station that stands here, a row each, and a press
## goes there. Null in AR, where nothing stands yet (slice 60).
var station_board: StationBoard
## The board's rows beside a plaque, while its INSTRUMENTS key has them up; else null.
var _beside: StationBoard
## A walker kept out of the tree, for where a person fits when there is no walker of our own (a
## headset): so a headset's seat is the desktop's seat, in from a table that stands in the way.
var _seat_finder: Walker


## The board stands on a stand of its own on the floor, pushed about like the rest of the gear
## (`live_pieces`' "station_board"): taken by its post or its foot, the face's rows still being
## pressed. Behind the mix position, so a desk of any width grows clear of it; one it is pushed
## into is shoved off the desk as the room is fitted to it.
func _build_station_board() -> void:
	station_board = StationBoard.new()
	station_board.name = "StationBoard"
	station_board.venue = venue
	station_board.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(BOARD_HEADING)), BOARD_AT)
	station_board.chosen.connect(_on_board_chosen)
	studio_set.add_child(station_board)
	var stand := _trolley("StationBoardStand", &"station_board", BOARD_AT, BOARD_HEADING)
	stand.follow = 11.0
	stand.rolls = false
	_board_grip = _grip(stand, Vector3.ONE * 0.1, Vector3.ZERO)
	_go_live(stand)
	_fit_board_stand()
	_carry_live(&"station_board")
	venue_changed.connect(func(_id: StringName) -> void:
		_put_away_beside()
		station_board.set_venue(venue)
		_fit_board_stand())


## The stand's grip, round the board's foot and post.
var _board_grip: CollisionShape3D


## The stand's footprint and grip to the board as it now stands: the face is as tall as its rows,
## and the foot comes forward under its middle (StationBoard.footprint).
func _fit_board_stand() -> void:
	var stand: Trolley = live_pieces.get(&"station_board")
	if stand == null or station_board == null:
		return
	var z := station_board._middle_z()
	stand.footprint_centre = Vector2(0, z)
	stand.footprint_half = StationBoard.FOOT
	var top := StationBoard.FACE_TOP - station_board._height * 0.5 * cos(StationBoard.TILT)
	(_board_grip.shape as BoxShape3D).size = Vector3(StationBoard.FOOT.x * 2.0, maxf(top - 0.05, 0.1), 0.12)
	_board_grip.position = Vector3(0, maxf(top - 0.05, 0.1) * 0.5, z - 0.03)


func _on_board_chosen(id: StringName) -> void:
	go_to_station(id)


## A key on a station's plaque (StationBoard.PlaqueKey) was pressed: INSTRUMENTS puts the board's
## rows up beside that plaque, or away again; BACK goes home to the desk.
func plaque_key(id: StringName, kind: StringName, key: Node3D) -> void:
	if kind == StationBoard.PlaqueKey.BACK:
		go_home()
		return
	var plaque := key.get_parent() as Node3D
	var shown := _beside != null and is_instance_valid(_beside) and _beside.get_parent() == plaque
	_put_away_beside()
	if shown or plaque == null:
		return
	_beside = StationBoard.new()
	_beside.name = "Beside"
	_beside.compact = true
	_beside.venue = venue
	_beside.chosen.connect(_on_board_chosen)
	# To the plaque's right, its top level with the plaque's, on the plaque's own lean.
	var plate := plaque.get_node_or_null("Plate") as MeshInstance3D
	var size: Vector3 = (plate.mesh as BoxMesh).size if plate != null else Vector3(Stations.PLAQUE_WIDTH, 0.2, 0.01)
	var top := plate.position.y + size.y * 0.5 if plate != null else 0.1
	_beside.position = Vector3(size.x * 0.5 + 0.02 + _beside.face_width() * 0.5, top, 0)
	plaque.add_child(_beside)
	Session.notice.emit("Every instrument, beside the %s's plaque: press one to go there, INSTRUMENTS again to put them away."
			% String(Stations.row(id).get("title", id)).to_lower())


## Take the rows beside a plaque away, if they are up: hidden and out of the physics space at
## once, freed at the frame's end, since the press that put them away may be one of their own.
func _put_away_beside() -> void:
	if _beside != null and is_instance_valid(_beside):
		_beside.visible = false
		_beside.process_mode = Node.PROCESS_MODE_DISABLED
		_beside.queue_free()
	_beside = null


## Why a headset may not travel now, or empty if it may. In a co-located room (`co_located`) a
## body has to stay where the others in the room see it: they see the real person, and a ghost
## sent somewhere else would be standing in the wrong place for everyone.
func travel_refusal() -> String:
	if rig == null:
		return "only a headset travels; on a screen I walks there"
	if co_located():
		return "you share this floor with the others in the room, who see you where you stand: walk over to it, as they would"
	return ""


## Whether this headset shares a real floor with someone else in the session: its frame was taken
## from marks on a real floor (RoomAnchor.marked), and another headset is in the session. Two
## rigs calibrated to the same marks are standing in the same room; a frame handed over whole
## (`adopt_virtual_frame`) is a room of one's own.
func co_located() -> bool:
	if room_anchor == null or not room_anchor.marked or Session.role == Session.Role.SOLO:
		return false
	for peer: int in Session.participants:
		var p: Session.Participant = Session.participants[peer]
		if peer != Session.local_peer_id and p.medium != Presentation.Medium.SCREEN:
			return true
	return false


## The headset's way to station `id`: the play space travels (XRRig.travel) so its centre is on
## the station's seat, facing it, behind a blink of XRRig.FADE (a plain cut at motion 0). The seat
## is the desktop's (Stations.seat, where a person fits) but for a set played only by hand, whose
## headset seat is within arm's reach of it (its row's `reach`), and focused gear is let go first, as on
## a desktop. Refused, the boards say why (StationBoard.refuse) and so does a toast, the rows
## beside a plaque staying up to say it where they were pressed; going, those are put away. The
## toast at the station says its title, its hands line and how to come back.
func _travel_to_station(id: StringName) -> bool:
	var r := Stations.row(id)
	var refused := travel_refusal()
	if refused != "":
		for board in [station_board, _beside]:
			if board != null and is_instance_valid(board):
				(board as StationBoard).refuse(refused)
		Session.notice.emit("%s: %s." % [StationBoard.REFUSED.capitalize(), refused])
		return false
	_put_away_beside()
	if focus != null and focus.is_focused():
		focus.release()
	var frame_of := venue.global_transform if venue.is_inside_tree() else venue.transform
	var seat: Transform3D = frame_of * (Stations.seat(venue, id, _station_fits(), true) as Transform3D)
	station = id
	if station_board != null:
		station_board.clear_refusal()
	rig.travel(seat, _travel_fade())
	Session.notice.emit("%s, %s: %s  ·  BACK on its plaque comes home" % [r["title"], Stations.where(r),
			r["hands"]])
	return true


## Home to the desk: BACK on a plaque. A headset's play space travels back to the mix position
## (XRRig.travel_home), co-located or not, since home is where everyone expects you, and at home
## already a toast says so; a desktop walks back as Esc does.
func go_home() -> void:
	_put_away_beside()
	station = &""
	if rig != null:
		if rig.away:
			rig.travel_home(_travel_fade())
			Session.notice.emit("Back at the desk.")
		else:
			Session.notice.emit("Already at the desk.")
		return
	_on_escape()


## How long the blink closes, and opens, on a travel: XRRig.FADE, or none at motion 0.
func _travel_fade() -> float:
	return XRRig.FADE if ergonomics.motion_scale > 0.0 else 0.0


## Where a person fits on the floor (Walker.fits): our walker's, or, in a headset that has none,
## one kept out of the tree for the purpose, told the same floor and solids.
func _station_fits() -> Callable:
	if walker != null:
		return walker.fits
	if floor_plan == null:
		return Callable()
	if _seat_finder == null:
		_seat_finder = Walker.new()
	_seat_finder.floor_plan = floor_plan
	_seat_finder.walkable = _walkable()
	_seat_finder.fixed = venue.solids() if venue != null else []
	return _seat_finder.fits


# --- the session in miniature (docs/spatial_loop.md part two, slice 34) --------------------------
#
# A 40 cm model of the song to hold (MiniatureItem), at home on the side table by the seat. A press on its
# bed seeks the song there and brings that track's gear by FocusRig: the console, banked to the
# track. A press on an item selects it and brings the timeline, scrolled to it. A press on one of
# the stations' pins round its lip goes there, as the station board's rows do: a headset travels, a
# desk walks (`go_to_station`).

## The side table by the seat: a little table of its own on the floor, at the desk's height, where
## the miniature lies at home within reach of the chair. It stood bolted to the console's left
## end, the one place it could not be moved from and in the corner of the seated view whatever
## was looked at (2026-10-30: "i like it allot itself, just not its location"); now it is pushed
## about like the rest of the gear (`live_pieces`' "mini_table"), the miniature and the note pad
## riding on it, and stays where it was left. At home off the seat's left hand, turned to face
## it, out of the seat's line to the desk and the rack. WING is its board, WING_TOP the height of
## its top.
const WING := Vector3(0.48, 0.03, 0.36)
## The board runs on WING_PAD past the tray's end, outward, for the note pad (NotePad, slice 35):
## its own place beside the miniature, out of the tray's way and of the seat's.
const WING_PAD := 0.10
const WING_TOP := 0.74
## Where the table stands at home, on the floor under the middle of its board, and its turn: its
## reader's edge (+Z, the side the miniature is read from) toward the mix position.
const MINI_TABLE_AT := Vector3(-0.92, 0, 0.36)
const MINI_TABLE_HEADING := 68.0
## How far into the timeline's window an item it is brought to starts, of the window's span.
const SHOWN_IN := 0.1

## The table, its origin on the floor under the middle of its board. Null in AR.
var desk_wing: Trolley
## Pointing, sticky notes and listening from a spot (slice 35), and the pad of notes: on the table,
## or in AR (no table; the room's furniture is the player's own) at the console's left end, at its
## height, NOTE_PAD_GAP off it (`_place_note_pad`).
var point_and_mark: PointAndMark
var note_pad: NotePad
const NOTE_PAD_GAP := 0.04


## The board on a cheek at either end down to the floor, an apron under its front edge: taken by
## any of it, the tray's bed still being pressed. The apron first, the grip a click from the seat
## finds: the board's top is under the tray.
func _build_desk_wing() -> void:
	desk_wing = _trolley("MiniTable", &"mini_table", MINI_TABLE_AT, MINI_TABLE_HEADING)
	desk_wing.follow = 10.0
	desk_wing.rolls = false
	desk_wing.footprint_centre = Vector2(-WING_PAD * 0.5, 0)
	desk_wing.footprint_half = Vector2(WING.x + WING_PAD, WING.z) * 0.5
	var apron := MeshInstance3D.new()
	apron.name = "Apron"
	var strip := BoxMesh.new()
	strip.size = Vector3(WING.x + WING_PAD - 0.08, 0.07, 0.02)
	apron.mesh = strip
	apron.position = Vector3(-WING_PAD * 0.5, WING_TOP - WING.y - 0.035, WING.z * 0.5 - 0.03)
	apron.material_override = Materials.furniture()
	desk_wing.add_part(apron)
	var board := MeshInstance3D.new()
	board.name = "Board"
	var top := BoxMesh.new()
	top.size = WING + Vector3(WING_PAD, 0, 0)
	board.mesh = top
	board.position = Vector3(-WING_PAD * 0.5, WING_TOP - WING.y * 0.5, 0)
	board.material_override = Materials.furniture()
	GearTrim.edges(board)
	desk_wing.add_part(board)
	var side := BoxMesh.new()
	side.size = Vector3(0.025, WING_TOP - WING.y, WING.z - 0.04)
	var cheeks: Array[float] = [-WING.x * 0.5 - WING_PAD + 0.03, WING.x * 0.5 - 0.03]
	for n in cheeks.size():
		var cheek := MeshInstance3D.new()
		cheek.name = "Cheek%d" % n
		cheek.mesh = side
		cheek.position = Vector3(cheeks[n], (WING_TOP - WING.y) * 0.5, 0)
		cheek.material_override = Materials.furniture()
		desk_wing.add_part(cheek)
	_go_live(desk_wing)
	_rehome_items()


## Point, mark and listen together (PointAndMark, docs/spatial_loop.md part two, slice 35): Z, Enter
## and O at a desk, a pointing hand and its pinch in a headset. Presence reads song times through
## it and finds them on this timeline's ruler; a note card's LISTEN key and the wing's note pad
## (`note_pad`) are its too. A controller points by the stick click of the hand that is not the
## chord hand (whose click is the chord stick's).
func _build_point_and_mark() -> void:
	point_and_mark = PointAndMark.new()
	point_and_mark.name = "PointAndMark"
	point_and_mark.studio = self
	point_and_mark.mouse = get_node_or_null("MouseHand") as MouseInteractor
	if rig != null:
		var chords: XRController3D = rig.left if ergonomics.handedness >= 0 else rig.right
		for controller in rig.interactors:
			var hand := rig.interactors[controller] as XRInteractor
			if hand != null:
				hand.points_by_stick = controller != chords
				point_and_mark.hands.append(hand)
	add_child(point_and_mark)
	if presence != null:
		presence.time_at = point_and_mark.time_at
		presence.ruler_point = func(seconds: float) -> Vector3:
			return timeline.ruler_point(seconds) if timeline != null and is_instance_valid(timeline) \
					and timeline.is_visible_in_tree() else Vector3.INF
	if timeline != null:
		timeline.listen_asked.connect(point_and_mark.listen_from)
	if desk_wing == null and console == null:
		return
	note_pad = NotePad.new()
	note_pad.name = "NotePad"
	if desk_wing != null:
		note_pad.position = Vector3(-WING.x * 0.5 - WING_PAD * 0.5, WING_TOP, 0.02)
		desk_wing.add_child(note_pad)
	else:
		studio_set.add_child(note_pad)
		_place_note_pad()
		console.rebuilt.connect(_place_note_pad)
	note_pad.stuck.connect(point_and_mark.on_pad_stuck)


## In AR, the note pad beside the console's left end, as the wing would be, at the desk's height
## and its front edge with the desk's: where the console is at home, wherever it has grown to.
func _place_note_pad() -> void:
	if note_pad == null or desk_wing != null or console == null:
		return
	var home := focus.home_of(&"console") if focus != null and focus.holds(&"console") \
			else console.transform
	var box := console.content_aabb()
	if box.size.x <= 0.0:
		return
	note_pad.transform = home * Transform3D(Basis.IDENTITY,
			Vector3(box.position.x - NOTE_PAD_GAP - NotePad.SIZE.x * 0.5, 0.0, box.end.z - NotePad.SIZE.z * 0.5))


## The miniature's pins are the stations standing here; its presses are the studio's.
func _wire_miniature() -> void:
	var mini := items.items.get(MiniatureItem.KIND) as MiniatureItem
	if mini == null:
		return
	mini.pressed.connect(_on_miniature_pressed)
	mini.station_pressed.connect(func(id: StringName) -> void: go_to_station(id))
	_pin_stations()
	venue_changed.connect(func(_id: StringName) -> void: _pin_stations())


## The stations standing here, for the miniature's pins: each with its plan bearing from the mix
## position, the side of the tray its pin stands on.
func _pin_stations() -> void:
	var mini := items.items.get(MiniatureItem.KIND) as MiniatureItem if items != null else null
	if mini == null:
		return
	var rows: Array = []
	for id in station_ids():
		var spot: Variant = Stations.spot(venue, id)
		if spot == null:
			continue
		var at := _venue_to_set(spot as Transform3D).origin
		var r := Stations.row(id)
		rows.append([id, r["title"], r["area"], Vector2(at.x, at.z - MIX_POSITION_Z)])
	mini.set_stations(rows)


## A press on the miniature's bed: the song sought to `seconds` (none for a track's name), and the
## gear for what was pressed brought by FocusRig. On an item, the item selected alone and the
## timeline brought, its window scrolled so the item starts SHOWN_IN into it; on a track, the
## console brought, banked to the page with that track on it. A guest's seek and selection are
## intents like any other (DAW).
func _on_miniature_pressed(track: int, seconds: float, item: int) -> void:
	if seconds >= 0.0:
		DAW.seek(seconds)
	var it := DAW.state.item(track, item) if item >= 0 else null
	if it != null:
		DAW.select_item(track, item)
		if timeline != null and is_instance_valid(timeline):
			timeline.pick_track(track)
			var span := timeline.view_span if timeline.view_span > 0.0 else DAW.state.timeline_length()
			timeline.set_view(maxf(0.0, it.start - span * SHOWN_IN), span)
			_bring(&"timeline")
		return
	if track > 0 and console != null:
		console.bank_to_track(track)
		_bring(&"console")


## Bring surface `id` by FocusRig: to you in a headset, you to it at a desk (FocusRig.visits). One
## the mount shows on the screen is in front of you already: at a desk, whatever gear you went to is
## let go so the screen's panels come back (`_stand_down_screen`).
func _bring(id: StringName) -> void:
	if focus == null or focus.surface(id) == null:
		return
	if mount != null and mount.mode_of(id) == Presentation.Mode.SCREEN:
		if focus.visits and focus.is_focused():
			focus.release()
		return
	# At a desk that would walk the player to it: a press on the miniature only shows the track or
	# the item, from where they are. A headset's is brought to them.
	if focus.visits:
		return
	focus.focus(id)


## No-op in a headset, where the camera is a head. Kept callable either way so the screenshot
## harness does not have to know which medium it is pointing at.
func frame(target: Vector3, distance: float, yaw: float, pitch: float) -> void:
	if camera == null:
		return
	_orbit_target = target
	_orbit_distance = distance
	_orbit_yaw = yaw
	_orbit_pitch = pitch
	if walker != null and not god_mode:
		var eye := target + Basis(Vector3.UP, yaw) * (Basis(Vector3.RIGHT, pitch) * Vector3(0, 0, distance))
		walker.travel_to(eye, target, 0.0)
		return
	_update_camera()


func _update_camera() -> void:
	if walker != null and not god_mode:
		walker._place_camera()
		return
	var offset := Basis(Vector3.UP, _orbit_yaw) * (Basis(Vector3.RIGHT, _orbit_pitch) * Vector3(0, 0, _orbit_distance))
	camera.position = _orbit_target + offset
	camera.look_at(_orbit_target, Vector3.UP)


## A write bead pulled out (WriteBead.on_pull): its lane shown on the timeline, its track picked, so
## each pass is seen to land there.
func _show_written_lane(track: int, target: String) -> void:
	if timeline != null and is_instance_valid(timeline):
		timeline.pick_track(track)
		timeline.show_lane(target)


# --- drum pads on anything (docs/spatial_loop.md part two, slice 41) ------------------------------
#
# The room's kit (KitItem) stands on the console's front rail, six pads KICK to RIM, struck by a
# click, by 4 to 9, or by a hand or a controller's tip (Strike). This player's own pads on real
# surfaces (SurfacePads) are its faces too: marked in a headset from the PADS card under the rail.

## How far the kit may be from the rail before it is stood there again (m): a desk that moved, grew
## or was brought (FocusRig) takes its pads with it.
const KIT_FOLLOW := 0.001


## The kit's place on the console's rail (ConsoleSurface.pad_rail), in the items' frame; null with no
## console or no room of items.
func kit_home() -> Variant:
	if console == null or items == null or not console.is_inside_tree() or not items.is_inside_tree():
		return null
	var at := items.global_transform.affine_inverse() * console.global_transform * console.pad_rail()
	return at.orthonormalized()


## This player's pads on real surfaces, the kit's: drawn through the session frame (RoomAnchor), moved
## with the play space when it travels (XRRig.away_from_home), saved on this machine; marked from the
## PADS card, which hangs off the rail under the kit's pads. At a desk there are no hands to mark
## with, and the card says how a desk plays them.
func _build_pads() -> void:
	var kit := items.items.get(KitItem.KIND) as KitItem if items != null else null
	pads = SurfacePads.new()
	pads.name = "SurfacePads"
	pads.hands = medium != Presentation.Medium.SCREEN
	pads.frame = func() -> Transform3D:
		var anchor := room_anchor.global_transform if room_anchor != null else Transform3D.IDENTITY
		return (rig.away_from_home() if rig != null else Transform3D.IDENTITY) * anchor
	pads.eye = func() -> Vector3:
		var eye: Node3D = rig.head if rig != null else camera
		return eye.global_position if eye != null and eye.is_inside_tree() else Vector3.ZERO
	pads.kit = kit
	pads.told.connect(func(text: String) -> void: Session.notice.emit(text))
	# None are drawn at a desk: there is no real surface under a mouse.
	pads.visible = pads.hands
	add_child(pads)
	if kit == null:
		return
	kit.surface = pads if pads.hands else null
	var card := pads.build_card()
	card.transform = Transform3D(Basis(Vector3.RIGHT, -deg_to_rad(SurfacePads.CARD_TILT)), KitItem.CARD_AT)
	kit.add_child(card)
	console.rebuilt.connect(_follow_kit.bind(true))
	_follow_kit(true)


## The kit stood on the rail again wherever the desk now is; and, `retag`, its jack's tag shown again,
## since a new desk may have a new drum track (KitItem.default_sink).
func _follow_kit(retag := false) -> void:
	var kit := items.items.get(KitItem.KIND) as KitItem if items != null else null
	if kit == null:
		return
	var at: Variant = kit_home()
	if at == null:
		return
	if not items.stands(KitItem.KIND):
		items.stand(KitItem.KIND, at)
	elif (at as Transform3D).origin.distance_to(kit.home.origin) > KIT_FOLLOW \
			or not (at as Transform3D).basis.is_equal_approx(kit.home.basis):
		# Carried along with a desk on the move, quietly: it never left home, so nothing is told.
		kit.home = at
		kit.transform = at
	if retag and kit.jack != null and jacks != null:
		kit.jack.show_sink(jacks.sink_of(kit.id))


## The desk's pad `n` (0 to 5, KICK to RIM) struck from the keyboard, as a click on it is: 96, or 64
## with Shift.
func strike_desk_pad(n: int, soft := false) -> void:
	var kit := items.items.get(KitItem.KIND) as KitItem if items != null else null
	if kit == null or not items.stands(KitItem.KIND):
		return
	kit.strike_rail(n, Strike.CLICK_SOFT if soft else Strike.CLICK)


# --- seeing the signal (docs/spatial_loop.md part three, A and B) ---------------------------------

## The signal view (SignalView): made the first time it is wanted, and this player's alone. Nothing
## about it is room state or sent: a bandmate's glasses change nothing here.
var signal_view: SignalView = null
## X at a desk: the view on without the glasses.
var signal_key_on := false
## The graph the view last drew, rebuilt at SIGNAL_GRAPH_HZ.
var signal_graph: SignalGraph = null
const SIGNAL_GRAPH_HZ := 15.0
var _signal_clock := 0.0
## What the last trace was traced from (a stage id) and called, so a fix can trace it again.
var _traced_from := ""
var _traced_title := ""
## A trace again this long after a fix, when the host has had time to answer (s).
const RETRACE_AFTER := 0.35
var _retrace_in := -1.0
## The headset's held trigger: the hand, what it is held on, and for how long (s).
const TRACE_HOLD := 0.6
var _trace_holds := {}
## Where OUT stands over the master section.
const OUT_RISE := 0.9


## Whether this player sees the signal: the glasses on this player's own head, or X.
func signal_view_on() -> bool:
	if signal_key_on:
		return true
	for hand in get_tree().get_nodes_in_group(Interactor.GROUP):
		var interactor := hand as Interactor
		if interactor != null and is_instance_valid(interactor.worn) and interactor.worn is SignalGlassesItem:
			return true
	return false


## X at a desk: the view on or off, glasses or none. Said, with what it shows and the next key.
func toggle_signal_view() -> void:
	signal_key_on = not signal_key_on
	if signal_view_on():
		Session.notice.emit("Seeing the signal: pipes as thick as the sound, amber near 0 dB, red over, a sign where it stops. Y over anything: why can't I hear it? Hold U over a track: hear it alone. X again: off.")
	else:
		Session.notice.emit("The signal view is off.")


## The room's sound sources, as SignalGraph.build takes them: every instrument item and the venue's
## set (onto its jack's track, armed or not, else the armed track), the harp, the theremin and the
## modular (the armed track), the mic (its voice track), and the sampler, the grain cloud and the
## platter, heard in one player's ears only.
func signal_sources() -> Array:
	var out: Array = []
	var seen := {}
	var armed := HitRecorder.armed_track()
	var row := func(id: StringName, title: String, node: Node3D, kind: StringName, track: int, jacked := false) -> void:
		if seen.has(id) or node == null or not is_instance_valid(node):
			return
		seen[id] = true
		var r := {"id": String(id), "title": title, "track": track, "kind": kind, "jacked": jacked, "node": node}
		if jacks != null and jacks.level_of(id) > 0.0:
			r["level_db"] = linear_to_db(jacks.level_of(id))
		out.append(r)
	var onto := func(source: StringName, item: Item) -> Array:
		var sink: StringName = jacks.goes_to(source, item) if jacks != null else &""
		var track := Jack.track_of(sink)
		return [track, true] if track > 0 else [armed, false]
	if items != null:
		for item: Item in items.items.values():
			if not item.visible:
				continue
			if item is MicItem:
				row.call(&"mic", "MIC", item, SignalGraph.VOICE, mic_arm.track if mic_arm.track > 0 else MicArm.track_for(DAW.state.tracks))
			elif item is InstrumentItem:
				var source := (item as InstrumentItem).jack_source()
				var to: Array = onto.call(source, item)
				row.call(source, (item as InstrumentItem).item_title(), item, SignalGraph.NOTES, to[0], to[1])
	if harp != null:
		var to: Array = onto.call(ChordHarp.SOURCE, null)
		row.call(ChordHarp.SOURCE, "HARP", harp, SignalGraph.NOTES, to[0], to[1])
	if theremin != null:
		row.call(Theremin.SOURCE, "THEREMIN", theremin, SignalGraph.NOTES, armed)
	if modular_wall != null:
		row.call(Modular.SOURCE, "MODULAR", modular_wall, SignalGraph.NOTES, armed)
	for local in [[&"sampler", "SAMPLER", sampler], [&"grains", "GRAIN CLOUD", grain_cloud], [&"platter", "PLATTER", platter]]:
		if local[2] != null:
			row.call(local[0], local[1], local[2], SignalGraph.LOCAL_SOURCE, 0)
	return out


## Where a stage stands in this room, or null: a source where it is; a track's stages at its voice on
## the stage table, else its channel strip; the master at the console's master section, OUT over it.
func signal_place(id: String) -> Variant:
	if id.begins_with("src:"):
		for r in _signal_rows:
			if r["id"] == id.trim_prefix("src:"):
				return (r["node"] as Node3D).global_position + Vector3.UP * 0.12 if is_instance_valid(r["node"]) else null
		return null
	if id == "master" or id == "out":
		if console == null or console.master == null or not console.master.is_inside_tree():
			return null
		return console.master.global_position + Vector3.UP * (0.3 if id == "master" else OUT_RISE)
	if id.begins_with("t"):
		var track := int(id.substr(1, id.find(":") - 1))
		return track_place(track)
	return null


## A track's place in the room: its voice on the stage table where it is shown, else its strip.
func track_place(track: int) -> Variant:
	if stage != null and is_instance_valid(stage) and stage.voices.has(track):
		var voice := stage.voices[track] as Node3D
		if voice != null and voice.is_inside_tree() and voice.is_visible_in_tree():
			return voice.global_position + Vector3.UP * 0.08
	if console != null:
		for strip in console.strips:
			if strip.track_index == track and strip.is_inside_tree() and strip.is_visible_in_tree():
				return strip.global_position + Vector3.UP * 0.25
	return null


var _signal_rows: Array = []


## Every frame: the view on or off; while on, the graph rebuilt, the meters kept wanted, the
## pipes drawn, the headset's held trigger watched, and a trace run again after its fix.
func _follow_signal(delta: float) -> void:
	var on := signal_view_on()
	_follow_skyline(on)
	if not on:
		if signal_view != null and signal_view.visible:
			signal_view.visible = false
			signal_view.clear_trace()
			if signal_view.card != null:
				signal_view.card.visible = false
		return
	if signal_view == null:
		signal_view = SignalView.new()
		signal_view.name = "SignalView"
		signal_view.screen_card = medium == Presentation.Medium.SCREEN
		signal_view.place = signal_place
		signal_view.fix_asked.connect(_do_signal_fix)
		add_child(signal_view)
	signal_view.visible = true
	signal_view.motion = ergonomics.motion_scale
	DAW.backend.want_signal_meters()
	_signal_clock += delta
	if signal_graph == null or _signal_clock >= 1.0 / SIGNAL_GRAPH_HZ:
		_signal_clock = 0.0
		_signal_rows = signal_sources()
		signal_graph = SignalGraph.build(DAW.state, _signal_rows)
	signal_view.quiet = [SignalGraph.SOLOED_OUT] if look_solo_held() else []
	signal_view.update(signal_graph, delta)
	if _retrace_in >= 0.0:
		_retrace_in -= delta
		if _retrace_in < 0.0 and _traced_from != "":
			signal_graph = SignalGraph.build(DAW.state, signal_sources())
			signal_view.trace(signal_graph.trace(_traced_from), _traced_title)
	_follow_trace_holds(delta)


## The routing bay and the audio devices' wall stand up as skylines while the view is on
## (PinMatrix.skyline, docs/spatial_loop.md part three, E): this player's alone, as the view is.
func _follow_skyline(on: bool) -> void:
	if patchbay != null and patchbay.matrix != null:
		patchbay.matrix.skyline = on
	var wall := venue.get_node_or_null("PatchWall") as PatchWallSurface if venue != null else null
	if wall != null and wall.matrix != null:
		wall.matrix.skyline = on


# --- look to solo (docs/spatial_loop.md part three, G) -------------------------------------------

## A hand held to an ear this near (m) of it, a little out from the head's middle, is cupped to it.
const EAR_REACH := 0.16
const EAR_OUT := 0.09
## Held there this long (s) before it solos, and away by this much (m) more to let go.
const EAR_DWELL := 0.2
const EAR_LEAVE := 0.08
## What holds this machine's look-solo: &"key" (U) or &"ear", or &"" for nothing.
var _look_by := &""
## A hand at the ear, and for how long (s).
var _ear_for := 0.0
## A guest's: the track asked for last, and the look resting on another (track, s).
var _look_asked := 0
var _look_resting := [0, 0.0]


## The track looked at now: in a headset what the head's gaze meets, at a desk what the cursor is
## over; through what the signal view would trace from it (an instrument, its track). 0 for none.
func looked_track() -> int:
	var under: Node = null
	var point := Vector3.ZERO
	if rig != null and rig.head != null and rig.head.is_inside_tree():
		var from := rig.head.global_position
		var query := PhysicsRayQueryParameters3D.create(from, from - rig.head.global_basis.z * Interactor.RAY_LENGTH)
		query.collision_mask = 1 << (Interactor.CONTROL_LAYER - 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			under = hit["collider"]
			point = hit["position"]
	else:
		var hand := get_node_or_null("MouseHand") as Interactor
		if hand != null:
			under = hand.held if hand.held != null else hand.hovered
			point = hand.hover_point
	var target := signal_target_of(under, point)
	if target.is_empty():
		return 0
	var id: String = target[0]
	if id.begins_with("src:"):
		for r in _signal_rows if not _signal_rows.is_empty() else signal_sources():
			if SignalGraph.source_id(r["id"]) == id:
				return int(r["track"])
		return 0
	return int(id.substr(1, id.find(":") - 1)) if id.begins_with("t") else 0


## Look to solo pressed, by `by` (&"key" or &"ear"): with the signal view on, the track looked at
## alone; on a guest asked of the host. Said either way.
func look_solo_press(by: StringName) -> void:
	if _look_by != &"":
		return
	if not signal_view_on():
		if by == &"key":
			Session.notice.emit("Look to solo needs the signal view on: X, or the signal glasses. Then hold U over a track to hear it alone.")
		return
	_look_by = by
	var on := looked_track()
	if Session.is_authority():
		var other := _look_solo_holder(Session.local_peer_id)
		if other != "":
			_look_by = &""
			Session.notice.emit("Look to solo is %s's just now: one at a time, as the room hears it." % other)
			return
		look_solo.peer = 0
		var words := look_solo.press(on)
		if words != "":
			Session.notice.emit(words)
		return
	_look_asked = on
	_look_resting = [on, 0.0]
	Session.ask_room(&"look_solo", [on, true])
	Session.notice.emit("Look to solo asks the host: the whole room hears %s alone while you hold, as a guest hears only the host's mix." % (LookSolo._title(on) if on > 0 else "what you look at"))


## Look to solo let go by `by`, or by anything (&"" -- the window's focus lost, the view off).
func look_solo_release(by: StringName = &"") -> void:
	if _look_by == &"" or (by != &"" and by != _look_by):
		return
	_look_by = &""
	if Session.is_authority():
		var words := look_solo.release()
		if words != "":
			Session.notice.emit(words)
		return
	Session.ask_room(&"look_solo", [0, false])
	_look_asked = 0


## Whether a look-solo is held in this room as far as this machine knows: its own (or, on a guest,
## its ask), or a guest's the host runs.
func look_solo_held() -> bool:
	if _look_by != &"" or look_solo.held:
		return true
	for p in guest_look_solos:
		if (guest_look_solos[p] as LookSolo).held:
			return true
	return false


## Whoever other than `peer` holds a look-solo here (the host's own, or a guest's), by name; "".
func _look_solo_holder(peer: int) -> String:
	if look_solo.held and peer != Session.local_peer_id:
		return Session.name_of(Session.local_peer_id)
	for p in guest_look_solos:
		if p != peer and (guest_look_solos[p] as LookSolo).held:
			return Session.name_of(p)
	return ""


## Host: a guest's look-solo asked (`track`, 0 for nothing; `held` false to let go).
func _on_look_solo_asked(track: int, held: bool, from: int) -> void:
	var ls: LookSolo = guest_look_solos.get(from)
	if not held:
		if ls != null:
			var words := ls.release()
			guest_look_solos.erase(from)
			if words != "":
				Session.tell_room("%s let go of look to solo: every solo and mute as it was." % Session.name_of(from))
		return
	if ls != null and ls.held:
		ls.look(track, LookSolo.FOLLOW_AFTER)
		return
	var other := _look_solo_holder(from)
	if other != "":
		Session.tell(from, "Look to solo is %s's just now: one at a time." % other)
		return
	ls = LookSolo.new()
	ls.peer = from
	guest_look_solos[from] = ls
	ls.press(track)
	if ls.track > 0:
		Session.tell_room("%s is look-soloing %s: the room hears it alone while they hold." % [Session.name_of(from), LookSolo._title(ls.track)])


## Host: a guest gone lets their look-solo go.
func _on_look_solo_player_left(peer: int) -> void:
	var ls: LookSolo = guest_look_solos.get(peer)
	if ls != null:
		ls.release()
		guest_look_solos.erase(peer)


## Every frame: a hand cupped to an ear holds it in a headset; held, the solo follows the look;
## the view going off lets go.
func _follow_look_solo(delta: float) -> void:
	_follow_ear_cup(delta)
	if _look_by == &"":
		return
	if not signal_view_on():
		look_solo_release()
		return
	var on := looked_track()
	if Session.is_authority():
		var words := look_solo.look(on, delta)
		if words != "":
			Session.notice.emit(words)
		return
	# A guest's look rests FOLLOW_AFTER on another track before it is asked.
	if on <= 0 or on == _look_asked:
		_look_resting = [on, 0.0]
		return
	if on != int(_look_resting[0]):
		_look_resting = [on, 0.0]
	_look_resting[1] = float(_look_resting[1]) + delta
	if float(_look_resting[1]) >= LookSolo.FOLLOW_AFTER:
		_look_asked = on
		Session.ask_room(&"look_solo", [on, true])


## A headset's hand cupped to an ear, with the view on: a controller beside the head with its grip
## squeezed, or a bare hand there, carrying nothing either way. Held EAR_DWELL, it presses; taken
## away, it lets go.
func _follow_ear_cup(delta: float) -> void:
	if rig == null or rig.head == null or not rig.head.is_inside_tree():
		return
	var head := rig.head.global_transform
	var nearest := INF
	for controller in rig.interactors:
		var hand := rig.interactors[controller] as XRInteractor
		if hand == null or not is_instance_valid(hand) or is_instance_valid(hand.carrying) or hand.held != null:
			continue
		var palm := hand.clap_palm()
		if palm.is_empty():
			continue
		if not hand._reads_hand() and not (hand.controller != null and hand.controller.is_button_pressed(hand.grip_action)):
			continue
		var at: Vector3 = palm[0]
		for side in [-1.0, 1.0]:
			nearest = minf(nearest, at.distance_to(head.origin + head.basis.x.normalized() * side * EAR_OUT))
	if _look_by == &"ear":
		if nearest > EAR_REACH + EAR_LEAVE:
			look_solo_release(&"ear")
		return
	if nearest <= EAR_REACH and signal_view_on() and _look_by == &"":
		_ear_for += delta
		if _ear_for >= EAR_DWELL:
			look_solo_press(&"ear")
	else:
		_ear_for = 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		# Never a stuck solo: a key let go while another window had focus never comes here.
		look_solo_release()


## The stage a trace of what `node` is starts from, and what it is called: an instrument or a
## station, its source; anything of a track (a strip, a voice, a control on one), that track's own
## playback. Empty for nothing that sounds.
func signal_target_of(node: Node, point := Vector3.ZERO) -> Array:
	if node == null:
		return []
	for r in _signal_rows if not _signal_rows.is_empty() else signal_sources():
		var n: Node = r["node"]
		if is_instance_valid(n) and (n == node or n.is_ancestor_of(node)):
			return [SignalGraph.source_id(r["id"]), str(r["title"])]
	var track := track_of(node, point)
	if track > 0 and DAW.state.tracks.has(track):
		return [SignalGraph.play_id(track), DAW.state.track(track).display_name()]
	return []


## "Why can't I hear this?" for what `hand` points at: traced and shown a stage at a time. True if
## there was something to trace.
func trace_pointed(hand: Interactor) -> bool:
	if not signal_view_on():
		Session.notice.emit("Put on the signal glasses first (X at a desk, or a pair from the prop shelf): then Y asks why.")
		return false
	var under: Node = (hand.held if hand.held != null else hand.hovered) if hand != null else null
	if under == null and hand != null and is_instance_valid(hand.carrying):
		under = hand.carrying
	var target := signal_target_of(under, hand.hover_point if hand != null else Vector3.ZERO)
	if target.is_empty():
		Session.notice.emit("Nothing that sounds is under the cursor: point at an instrument, a station, a stage voice or a channel strip.")
		return false
	return trace_from(target[0], target[1])


## A trace from stage `from`, called `title`, shown in the view and said in the toast.
func trace_from(from: String, title: String) -> bool:
	if signal_view == null:
		_follow_signal(0.0)
	_signal_rows = signal_sources()
	signal_graph = SignalGraph.build(DAW.state, _signal_rows)
	if signal_graph.stage(from) == null:
		return false
	_traced_from = from
	_traced_title = title
	var tr := signal_graph.trace(from)
	signal_view.trace(tr, title)
	if tr.heard():
		Session.notice.emit("%s is heard: it reaches the speakers." % title)
	elif tr.broke_at != null:
		Session.notice.emit("%s stops at %s: %s.%s" % [title, tr.broke_at.title, tr.words,
				(" Shift-Y: %s." % tr.fix["label"]) if not tr.fix.is_empty() else ""])
	return true


## Shift-Y, the card's FIX or the key by the sign: the trace's fix, one undo step, then traced again.
func fix_traced() -> bool:
	if signal_view == null or signal_view.tracing == null or signal_view.tracing.fix.is_empty():
		Session.notice.emit("No fix to do: trace something with Y first.")
		return false
	_do_signal_fix(signal_view.tracing.fix)
	return true


func _do_signal_fix(fix: Dictionary) -> void:
	if not SignalGraph.apply_fix(fix):
		return
	Session.notice.emit("%s: done, one undo step (Ctrl-Z puts it back)." % fix["label"])
	_retrace_in = 0.0 if Session.is_authority() else RETRACE_AFTER


## A headset's trigger held still on something for TRACE_HOLD, with the view on, traces it.
func _follow_trace_holds(delta: float) -> void:
	if rig == null:
		return
	for controller in rig.interactors:
		var hand := rig.interactors[controller] as Interactor
		if hand == null or not is_instance_valid(hand):
			continue
		var on: Node = hand.held if hand.held != null else hand.hovered
		var held: Array = _trace_holds.get(hand, [null, 0.0, false])
		if hand.is_pressing() and on != null and on == held[0]:
			held[1] = float(held[1]) + delta
			if float(held[1]) >= TRACE_HOLD and not held[2]:
				held[2] = true
				trace_pointed(hand)
		else:
			held = [on if hand.is_pressing() else null, 0.0, false]
		_trace_holds[hand] = held
