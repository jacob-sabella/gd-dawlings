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
## The circle-of-fifths wheel on the bricks table (FifthsWheel), stood again with each venue at
## its `wheel_spot`: where the song's key and chords are written from the room. Null in AR.
var wheel: FifthsWheel
## The song's sections as blocks along the bricks table's far edge (SectionBlocks, docs/spatial_loop.md
## part two, slice 30), stood again with each venue at its `sections_spot`. Null in AR.
var sections: SectionBlocks
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
## The modular room's rack over the synth zone's keyboard stand (RackWall, docs/architecture.md), a
## surface hung again with each venue at its `modular_spot`; null in AR. Its voice (RackVoice, the
## engine), the room's row `rack` {patch, track} (RackPatch), and the computer keys as its keys.
var rack_wall: RackWall
var rack_voice: RackVoice
## Loads the host's saved rack when the wall is built and saves it a moment after each change.
var rack_files := RackAutosave.new()
## The delta of the room this studio is in: where its furniture was left (`RoomDeltas`).
var room_deltas := RoomDeltas.new()
## What the weather, the rings and the venue's instrument play into the rack's WORLD module.
var modular_world: ModularWorld
var modular_annex: ModularAnnex
var rack_row := {"patch": RackPatch.preset(&"keys_voice"), "track": 0}
## The lyric board in the vocal booth (LyricBoard, docs/spatial_loop.md part two, slice 56), stood
## again with each venue at its `lyrics_spot`; null where there is no booth and in AR. What it shows is
## the song's (MixState.lyrics), so nothing of it is the room's.
var lyric_board: LyricBoard
var modular_keys: KeyCatcher
var _modular_held := {}
var _modular_last := -1
## Whether the rack's take under way began with the song's recording (and so ends with it).
var _rack_auto_take := false
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
## (`RoomSync.wheel_in`). Empty in AR.
var live_pieces := {}
## Builds the wheeled pieces from their definitions and carries what rides with them.
var pieces := PieceHost.new(self)
## The host's edits of the room's layout (move, rotate, add, remove, reset), asked through `ask_layout`.
var layout_edit := LayoutEdit.new(self)
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
	add_child(room_deltas)
	_build_environment()
	# In AR the room is already there -- it is the one the participant is standing in. Drawing a
	# virtual floor over a real one is not a smaller version of the VR experience, it is a worse
	# one: it hides the actual floor and it disagrees with it by however much calibration is off.
	if medium != Presentation.Medium.AR:
		if Session.layout != null:
			set_venue(Session.layout.venue, false, Session.layout.venue_variant)
		else:
			set_venue(Venue.IDS[0], false)
	surface_host._build_anchors()
	if medium != Presentation.Medium.AR:
		furniture_host._build_furniture()
	surface_host._build_surfaces()
	station_host._build_point_and_mark()
	if camera != null:
		_build_walker()
		_update_camera()
	if medium != Presentation.Medium.AR:
		item_host._build_items()
		tour_room._build_tour_case()
		roll_room._build_rig_roulette_station()
	else:
		# AR's room is the player's own real one: of the room's items, only the drum pads' kit on the
		# desk's rail, which plays there as anywhere (docs/spatial_loop.md part two, slice 41).
		item_host._build_items()
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
	room_deltas.enter(venue.venue_id(), venue.variant)
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
	tablet_host._recolour_tracks()
	# Every venue a touch brighter than it dressed itself: the mid-tones read dark on an ordinary
	# monitor, AgX's above all. Exposure rather than brightness, so blacks stay black.
	env.tonemap_exposure *= EXPOSURE_LIFT
	world_env.environment = env
	add_child(venue)
	_hang_the_roulette_door()
	# Before anything stands at its spot: the spots of what is wheeled about are its trolley's.
	RoomSync.wheel_in(self)
	pieces.stand_all()
	_stand_the_modular()
	pieces.stand(&"weather")
	furniture_host._hang_hood_signs()
	var mirror := venue.make_mirror(env)
	venue.add_child(mirror)
	_stand_a_patch_wall()
	furniture_host._set_levels_niche()
	furniture_host._set_tv_mount()
	# The venue built its shelf and hoop where their trolleys stood in the last one.
	furniture_host._carry_all_live()
	mirror.wardrobe.look = Session.local_look
	mirror.wardrobe.look_changed.connect(Session.set_look)
	_relight()
	if persist and Session.layout != null and Session.is_authority():
		Session.layout.venue = id
		Session.layout.venue_variant = venue.variant
		Session.layout.save()
	_walk_where_the_venue_lets()
	venue_changed.emit(id)
	room_rows._publish_room()


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


## The room's venue bars dressed as this venue's set, the first of them its count, for the mount to
## brush across: before their homes are stood (ItemRoom.set_spots), so each stands in its own look.
func _dress_venue_bars() -> void:
	if items == null or venue_instrument == null or not is_instance_valid(venue_instrument):
		return
	venue_instrument.bars = VenueInstrument.dress(items, venue_instrument.spec)


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


## Where made item number `n` lies with nowhere else to be: the rack's tray.
func _made_home(_kind: StringName, n: int) -> Transform3D:
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
## turned to face the desk (`ControlRoom`, the `patch_wall` piece).
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
	var at: Transform3D = legs.transform if legs != null else ControlRoom.spot(&"patch_wall", room_width)
	return _set_to_venue(at) * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * PATCH_WALL_SCALE),
			Vector3(0, PATCH_WALL_TOP, 0))


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
		out.append_array(venue.walk_rooms())
	return out


## The venue's ceiling, over the walker wherever it is.
func _ceiling() -> float:
	return venue.ceiling_height() if venue != null else Venue.LIVE_ROOM_HEIGHT


## The modular room's roof is lower than the live room's: under it, that is the ceiling.
func _ceiling_at(where: Vector3) -> float:
	if modular_annex != null and is_instance_valid(modular_annex) and modular_annex.is_inside_tree():
		var local := modular_annex.to_local(where)
		if ModularAnnex.inside(modular_annex.half).has_point(Vector2(local.x, local.z)):
			return ModularAnnex.HEIGHT
	return 1000.0


func _walk_where_the_venue_lets() -> void:
	if walker != null:
		walker.walkable = _walkable()
		walker.fixed = venue.solids() if venue != null else []
		walker.ceiling = _ceiling()
		walker.rebuild_walls()
		walker.unstick()
	if items != null and venue != null:
		items.boards = venue.dart_boards()
		items.hoops = RoomSync.hoops(self)
		items.set_venue(venue.venue_id())
		items.set_spots(venue.item_spots(), _item_homes())
	pieces.hold_the_rack()
	if tour_case != null and venue != null:
		tour_case.transform = _venue_to_set(venue.tour_case_spot())
		pieces.rehome_spills()


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


## Where the stage table's trolley stands: beside the mix position on the right and a little
## behind it, turned to face it, clear of the deck trolley and the patch stand however wide the
## desk grows (the desk's footprint ends in front of the mix position, and these stand behind
## it). The top is desk height; the rail along its front drops RAIL below it. Far enough back
## that from the seat the right-hand lamp's foot is seen past its corner, not through it.
const STAGE_TOP := 0.74


## The plaque's top edge on the trolley's front, under the rail.
const STAGE_PLAQUE_TOP := 0.6


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


## The pads' row (PadShare): what the host's sampling station holds, for the room.
var pads_row := {}
var _pads_rev := -1
var _pads_file := ""
var _pads_followed := {}
var _pads_loaded := ""


## The time a desk put down across the room takes to get there on this screen.
const GLIDE_SECONDS := 0.25


const MOTION_MSEC := 50


## The stands someone else is pushing, by id: what their push sent, played back.
var _pushed_trails := {}


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
	room_rows._publish_room()


func _put_back_own_room() -> void:
	_showing_hosts_room = false
	_predictions.clear()
	if Session.layout == null:
		return
	room_deltas.enter_own(Session.layout)
	for id in tablets.keys():
		tablet_host._take_down_tablet(id)
	for id in track_racks.keys():
		tablet_host._take_down_track_rack(id)
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
			var left: Variant = room_deltas.saved(t.piece_id, Session.layout)
			var own: Transform3D = left if left != null else _authored_floor[t.piece_id]
			t.place(Vector2(own.origin.x, own.origin.z), own.basis.get_euler().y)
		RoomSync.wheel_in(self)
		furniture_host._carry_all_live()
		_applying_room = false
		_fit_room_to_session()
	var own := Session.layout.venue if Venue.is_known(Session.layout.venue) else Venue.IDS[0]
	var own_variant := Venue.known_variant(own, Session.layout.venue_variant)
	if medium != Presentation.Medium.AR and venue != null \
			and (venue.venue_id() != own or venue.variant != own_variant):
		set_venue(own, false, own_variant)
	# The host's made room goes with the host's room: it was held for this guest in memory only.
	MadeRooms.drop_adopted()
	if floor_plan != null:
		tablet_host._restore_tablets()
		tablet_host._restore_track_racks()


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
		room_rows.apply_room(Session.room)
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
			var at: Transform3D = ControlRoom.spot(&"eq_wall", room_width)
			want = [Vector2(at.origin.x, at.origin.z), ControlRoom.heading(at)]
		elif t.built_in:
			continue
		elif id.begins_with("lamp_") and _authored_floor.has(t.piece_id):
			var home: Transform3D = _authored_floor[t.piece_id]
			want = [SessionLayout.widen(Vector2(home.origin.x, home.origin.z), room_width),
					home.basis.get_euler().y]
		var saved := room_deltas.saved(t.piece_id, Session.layout) != null
		var here := Vector2(t.position.x, t.position.z)
		if want != null and not saved:
			if not (want[0] as Vector2).is_equal_approx(here) or not floor_plan.is_clear(t, here, t.rotation.y):
				t.place(want[0], want[1])
		elif not floor_plan.is_clear(t, here, t.rotation.y):
			t.place(here, t.rotation.y)
	_fitting = false
	_looms_dirty = true
	room_rows._publish_room()


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
	var saved: Variant = room_deltas.saved(id, Session.layout)
	if saved != null and not (id == &"levels" or id == &"tv"):
		piece.transform = saved
	piece.settled.connect(_on_trolley_settled.bind(piece))
	piece.moved.connect(room_rows._on_trolley_moved.bind(piece))
	studio_set.add_child(piece)
	floor_plan.add_piece(piece)
	return piece


## A piece of furniture the control-room fragment places (`ControlRoom`), standing where it says
## in this room's width: `_trolley` with its authored spot and turn.
func _authored(of_name: String, id: StringName) -> Trolley:
	var args := ControlRoom.trolley_args(id, room_width)
	return _trolley(of_name, id, args[0], args[1])


func _on_trolley_settled(piece: Trolley) -> void:
	var steered := piece.steered
	piece.steered = false
	var told := not _fitting and not _applying_room and not (steered and not Session.is_authority())
	if told and not Session.is_authority():
		# Wheeled here: it stays here, and the host is told; see apply_room.
		var verb := &"move_tablet" if tablets.has(piece.piece_id) else &"move_piece"
		room_rows._predict(verb, [piece.piece_id, piece.position.x, piece.position.z, piece.rotation.y])
	else:
		# Where the host's room has things is not where this guest keeps its own. A spot that is where the
		# room stands the piece is not a place anyone chose: in the next venue, or a wider room, it goes there.
		if not (_fitting or _showing_hosts_room or piece.built_in):
			room_deltas.settle(piece.piece_id, piece.transform, RoomFloor.at_default(self, piece), Session.layout)
		if told:
			room_rows._publish_room()
	_looms_dirty = true


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


# --- the modular room's rack (docs/architecture.md, "The modular room") ----------------------
#
# The patch is the room's row `rack` {patch: {modules, cables}, track} (RackPatch): every change to it
# is the one ask `rack` [op, args] (RackPatch.answer: add, remove, move, cable, pull, pull_one, knob,
# preset; and `track`, the track the rack sounds through), shown at once here and rolled back if the
# host refuses it, as the patchbay's `patch` is. The engine (native/rack, RackVoice) runs on the host
# alone, and what it plays goes through a track of the song (InputMonitor.feeds), so every guest hears
# it in the mix; a guest's keys at the rack reach it as notes the host plays (Presence.modular_heard).
# A knob turning is the ask too, at most Session.KNOBS_PER_SECOND, so the room hears a sweep as it is
# made. The rack is caught as audio on its track while the song records, or with its REC key.

## Where a player stands to play the rack, in its frame (m): in front of the stand, out to the seat and a step
## past it (3.0), and no wider than the case. Its jacks and knobs take the pointer
## only from here (and only where no other station's seat is nearer, `at_modular`), or while it is
## visited or brought.
const MODULAR_NEAR := 0.3
const MODULAR_FAR := 4.4
const MODULAR_SIDE := 3.6
## How often the stations' seats are worked out again for `at_modular` (s): a trolley pushed
## moves its seat, but not every frame's worth.
const MODULAR_SEATS_EVERY := 0.5

## Every station's seat here on the floor (global x, z), by id, for `at_modular`, and when they were
## worked out (ms) and for which venue.
var _modular_seats := {}
var _modular_seats_at := -1
var _modular_seats_venue := 0


## The rack, its voice and its computer keys, made once with the surfaces; hung at the venue's spot
## (`_stand_the_modular`). None in AR.
func _build_rack() -> void:
	add_child(rack_files)
	rack_files.restore(rack_row)
	rack_wall = RackWall.new()
	rack_wall.name = "RackWall"
	rack_wall.parks = false
	rack_wall.pillars = false
	rack_wall.within_reach = false
	rack_wall.patch = rack_row["patch"].duplicate(true)
	studio_set.add_child(rack_wall)
	mount.register(rack_wall)
	rack_wall.edit_asked.connect(ask_rack)
	rack_wall.knob_streamed.connect(func(id: String, k: String, v: float) -> void: ask_rack("knob", [id, k, v]))
	rack_wall.knob_set.connect(func(id: String, k: String, v: float) -> void: ask_rack("knob", [id, k, v]))
	rack_wall.told.connect(func(text: String) -> void: Session.notice.emit(text))
	rack_wall.touched.connect(_on_rack_touched)
	rack_wall.keys_asked.connect(func() -> void: _modular_play(not modular_keys.is_active()))
	rack_wall.track_asked.connect(func() -> void: ask_rack("track", [0]))
	rack_wall.record_asked.connect(_rack_toggle_record)
	rack_voice = RackVoice.new()
	rack_voice.name = "RackVoice"
	add_child(rack_voice)
	rack_voice.set_patch(rack_row["patch"])
	# The world plays into the rack's WORLD module, worked out from the song clock and the rows as it
	# always was, the same on every machine; only the host's engine sounds it.
	modular_world = ModularWorld.new()
	modular_world.weather = func() -> Variant: return weather
	modular_world.has_venue = func() -> bool: return venue_instrument != null and is_instance_valid(venue_instrument)
	add_child(modular_world)
	modular_world.fired.connect(func(events: Array) -> void: rack_voice.play_world(events))
	modular_keys = KeyCatcher.new()
	modular_keys.name = "RackKeys"
	modular_keys.base = 48
	add_child(modular_keys)
	modular_keys.note_on.connect(func(pitch: int, velocity: int) -> void: _on_rack_touched(pitch, true, velocity))
	modular_keys.note_off.connect(func(pitch: int) -> void: _on_rack_touched(pitch, false))
	modular_keys.active_changed.connect(func(on: bool) -> void: rack_wall.show_playing(on))
	if presence != null:
		presence.modular_heard = _on_rack_heard
	if Session.guest_midi != null:
		Session.guest_midi.key.connect(_on_modular_key)
	_show_rack(rack_row)


## The rack, hung at this venue's spot over the stand (Venue.modular_spot), the venue's rack giving way
## to it, in the venue's mood; put away, and out of F's round, where the venue has none.
func _stand_the_modular() -> void:
	if rack_wall == null or not is_instance_valid(rack_wall) or venue == null:
		return
	var spot: Variant = Stations.spot(venue, Modular.STATION)
	rack_wall.visible = spot != null
	rack_wall.set_mood(RackMood.palette(venue.venue_id()))
	if spot == null:
		if focus != null:
			if focus.focused_id == rack_wall.surface_id:
				focus.release()
			focus.surfaces.erase(rack_wall)
		return
	_stand_the_annex()
	var at := _venue_to_set(spot as Transform3D)
	mount.seat(rack_wall.surface_id, func() -> Transform3D: return at)
	if focus != null and not focus.surfaces.has(rack_wall):
		focus.surfaces.append(rack_wall)


## The modular room built onto this venue's live room: its walls, its doorway cut through the live
## room's wall, its lights in the venue's mood.
func _stand_the_annex() -> void:
	if venue == null or venue.get_node_or_null("ModularAnnex") != null:
		return
	ModularAnnex.cut_the_wall(venue)
	ModularAnnex.clear_the_site(venue)
	modular_annex = ModularAnnex.build(venue)
	rack_wall.extra_controls.clear()
	for kn in modular_annex.bench:
		rack_wall.extra_controls.append(kn)
	modular_annex.bench_turned.connect(func(k: int, v: float) -> void:
		if rack_voice != null:
			rack_voice.set_hand(k, v))
	rack_wall._apply_reach()


## A world socket's press (WorldSocket.step_asked): its cable out of the input it is in and into the
## next free one `way` on, the rack's WORLD module put in the case first if it has none.
func _on_world_step(socket: StringName, way: int) -> void:
	var patch: Dictionary = rack_row["patch"]
	if not RackPatch.has_type(patch, RackPatch.WORLD_MODULE):
		ask_rack("add", ["world", -1, 0])
		patch = rack_row["patch"]
		if not RackPatch.has_type(patch, RackPatch.WORLD_MODULE):
			return
	var now := RackPatch.world_sink(patch, socket)
	var next := RackPatch.step_world(patch, socket, way)
	if now != "":
		var out := ""
		for c in patch["cables"]:
			if c[1] == now and RackPatch.type_of(patch, String(c[0]).get_slice(".", 0)) == RackPatch.WORLD_MODULE:
				out = c[0]
		if out != "":
			ask_rack("pull_one", [out, now])
	if next != "":
		ask_rack("cable", [RackPatch.world_out(patch, socket, next), next])
		Session.notice.emit("%s goes into %s on the rack. Press it again for the next free input."
				% [Modular.world_title(socket).capitalize(), next.replace(".", " ").to_upper()])


## Where a plug in the rack's input `path` sits, for a world socket's cable.
func _rack_jack(path: StringName) -> Variant:
	if rack_wall == null or not is_instance_valid(rack_wall) or not rack_wall.is_visible_in_tree():
		return null
	var jack: RackJack = rack_wall.jacks.get(String(path))
	return jack.plug_transform() if jack != null and jack.is_inside_tree() else null


## Each frame: every world socket in the room wired to its press and to the rack, and showing where
## the rack has its cable.
func _follow_world_sockets() -> void:
	var patch: Dictionary = rack_row["patch"]
	for node in get_tree().get_nodes_in_group(WorldSocket.SOCKETS):
		var socket := node as WorldSocket
		if socket == null:
			continue
		if not socket.has_meta(&"wired"):
			socket.set_meta(&"wired", true)
			socket.step_asked.connect(_on_world_step)
			socket.wall_jack = _rack_jack
		var into := StringName(RackPatch.world_sink(patch, socket.socket))
		if socket.into != into:
			socket.show_into(into)


## An edit of the rack, `op` and `args` as RackPatch.answer takes them (or `track` [step]): done on the
## host, asked by a guest and shown at once, or refused here in words where the host would refuse it.
func ask_rack(op: String, args: Array) -> void:
	if op == "knob" and args.size() == 3 and _turn_knob(String(args[0]), String(args[1]), float(args[2])):
		return
	if Session.is_authority():
		_answer_rack(op, args, Session.local_peer_id)
		return
	var row := rack_row.duplicate(true)
	var refusal := _rack_apply(row, op, args)
	if refusal != "":
		Session.notice.emit(refusal)
		return
	if op == "knob":
		# A sweep is many asks and one room: the turn is shown here, and the host's room catches up.
		Session.ask_room(&"rack", [StringName(op), args])
		_show_rack(row)
		return
	if room_rows._predict(&"rack", [StringName(op), args]) > 0:
		_show_rack(row)


## An edit of the room's layout, `op` and `args` as `LayoutEdit` takes them: done on the host, refused in
## words where the host would refuse it (and for a guest, which may only push). The refusal, or "".
func ask_layout(op: String, args: Array) -> String:
	return layout_edit.ask(op, args)


## One knob turned: only that value is set, on the wall, in the voice and in the row. The patch is not
## copied, sanitized, diffed or laid out again (that cost ~60 ms a turn). False if the knob is not there,
## and the whole ask goes the long way to be refused in words.
func _turn_knob(id: String, k: String, v: float) -> bool:
	var patch: Dictionary = rack_row.get("patch", {})
	if not RackPatch.set_knob(patch, id, k, v):
		return false
	v = RackPatch.knob_of(patch, id, k)
	rack_files.note(rack_row)
	if rack_wall != null and is_instance_valid(rack_wall):
		rack_wall.show_knob(id, k, v)
	if Session.is_authority():
		if rack_voice != null and is_instance_valid(rack_voice):
			if not rack_voice.running() and _rack_engaged():
				_rack_wake()
			rack_voice.knob(id, k, v)
		_publish_room_soon()
	else:
		Session.ask_room(&"rack", [&"knob", [id, k, v]])
	return true


## `op` done to the row `row`; the refusal in words, or "".
func _rack_apply(row: Dictionary, op: String, args: Array) -> String:
	if op == "track":
		var tracks: Array = DAW.state.track_indices() if DAW.state != null else []
		tracks.sort()
		var at := tracks.find(int(row["track"]))
		var step := int(args[0]) if args.size() > 0 else 0
		if step == 0:
			# Round the tracks, and to none after the last.
			row["track"] = tracks[at + 1] if at + 1 < tracks.size() and at >= -1 else 0
			if at == -1 and not tracks.is_empty():
				row["track"] = tracks[0]
		elif tracks.has(step) or step < 0:
			row["track"] = maxi(step, 0)
		return ""
	return RackPatch.answer(row["patch"], op, args)


func _answer_rack(op: String, args: Array, from: int) -> void:
	var row := rack_row.duplicate(true)
	var refusal := _rack_apply(row, op, args)
	if refusal != "":
		Session.tell(from, refusal)
		return
	_show_rack(row)
	_publish_room_soon()


## The room's rack as `row` has it, here: on the wall and in the voice, with a knob a hand here is still
## turning kept where the hand has it. On the host it wakes the engine for any edit.
func _show_rack(row: Dictionary) -> void:
	rack_row = {"patch": RackPatch.sanitize(row.get("patch", {})), "track": int(row.get("track", 0))}
	rack_files.note(rack_row)
	var turning := rack_wall.turning() if rack_wall != null and is_instance_valid(rack_wall) else {}
	var patch: Dictionary = rack_row["patch"]
	for key: String in turning:
		RackPatch.set_knob(patch, key.get_slice(".", 0), key.get_slice(".", 1), float(turning[key]))
	if rack_wall != null and is_instance_valid(rack_wall):
		rack_wall.show_patch(patch)
		rack_wall.set_track(int(rack_row["track"]), _rack_track_name(int(rack_row["track"])))
	if rack_voice != null and is_instance_valid(rack_voice) and Session.is_authority():
		if rack_voice.running() or _rack_engaged():
			_rack_wake()
		rack_voice.set_patch(patch)
		rack_voice.set_track(int(rack_row["track"]))
	elif rack_voice != null and is_instance_valid(rack_voice):
		rack_voice.patch = patch


func _rack_track_name(index: int) -> String:
	if index <= 0 or DAW.state == null:
		return ""
	var t: MixState.TrackState = DAW.state.track(index, false)
	return t.name if t != null else ""


## Start the engine if it is not going (host only), the track chosen for it if none is: the first one.
func _rack_wake() -> void:
	if rack_voice == null or not Session.is_authority() or rack_voice.running():
		return
	if not RackEngine.available():
		return
	if rack_voice.start():
		if int(rack_row["track"]) <= 0 and DAW.state != null:
			var tracks: Array = DAW.state.track_indices()
			if tracks.is_empty():
				# A song with no track has nothing for the rack to sound through: it gets one.
				DAW.add_track(1, "Modular")
				tracks = DAW.state.track_indices()
			tracks.sort()
			if not tracks.is_empty():
				rack_row["track"] = tracks[0]
		rack_voice.set_patch(rack_row["patch"])
		rack_voice.set_track(int(rack_row["track"]))
		_show_rack(rack_row)


func _rack_engaged() -> bool:
	return at_modular() or (modular_keys != null and modular_keys.is_active())


## REC on the rack: a take of what it plays, on its track at the song position it began.
func _rack_toggle_record() -> void:
	if not Session.is_authority():
		Session.notice.emit("The host records the rack: its sound is in the mix on its track.")
		return
	_rack_wake()
	if rack_voice.recording():
		var made := rack_voice.record_stop()
		Session.notice.emit("Rack take: %s" % ("kept on track %d" % int(rack_row["track"]) if str(made.get("error", "")) == ""
				else str(made["error"])))
	elif not rack_voice.record_start(DAW.state.position_seconds if DAW.state != null else 0.0):
		Session.notice.emit("Pick a track for the rack to sound through first: TRACK.")
	if rack_wall != null:
		rack_wall.set_recording(rack_voice.recording())


## A touch key, or the computer keys under PLAY: a note on this player's keys, to the rack.
func _on_rack_touched(pitch: int, down: bool, velocity := 100) -> void:
	if Session.guest_midi == null:
		return
	if down:
		Session.guest_midi.note_on(pitch, velocity, 0, 0.0, false, Modular.SOURCE)
	else:
		Session.guest_midi.note_off(pitch, 0, 0.0, false, Modular.SOURCE)


## A bandmate's note through the rack (Presence.modular_heard): the host plays it.
func _on_rack_heard(_peer: int, kind: int, pitch: int, velocity: int) -> void:
	if not Session.is_authority() or rack_voice == null:
		return
	_rack_wake()
	if kind == Session.Note.ON:
		rack_voice.note_on(pitch, velocity)
	elif kind == Session.Note.OFF:
		rack_voice.note_off(pitch)


## A key played on this player's keys, from anywhere: KEYS' lamp.
func _on_modular_key(pitch: int, down: bool) -> void:
	if down:
		_modular_held[pitch] = true
		_modular_last = pitch
	else:
		_modular_held.erase(pitch)
	if rack_wall != null and is_instance_valid(rack_wall):
		rack_wall.show_keys(_modular_last, not _modular_held.is_empty())


## The computer keys as the rack's, on or off, and said so the first time.
func _modular_play(on: bool) -> void:
	if modular_keys == null or on == modular_keys.is_active():
		return
	modular_keys.set_active(on)
	if on:
		Session.notice.emit("Rack: A to ' play from %s, Z and X move the octave. Esc gives the keys back; PLAY takes them again."
				% modular_keys.octave_name())


## Whether this player is at the rack: with it visited or brought, or standing in front of the
## stand (MODULAR_NEAR to MODULAR_FAR out, MODULAR_SIDE either side) where the rack's own seat is
## the nearest station's, so standing at a station beside it plays it
## and not the patch.
func at_modular() -> bool:
	if rack_wall == null or not is_instance_valid(rack_wall) or not rack_wall.visible \
			or not rack_wall.is_inside_tree():
		return false
	if focus != null and focus.focused_id == rack_wall.surface_id:
		return true
	var me := _standing_at()
	var local := rack_wall.global_transform.affine_inverse() * me
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
	var fits := walker.fits if walker != null else station_host._station_fits()
	var hands := medium != Presentation.Medium.SCREEN
	for id in station_host.station_ids():
		var seat: Variant = Stations.seat(venue, id, fits, hands)
		if seat != null:
			var p: Vector3 = frame_of * (seat as Transform3D).origin
			_modular_seats[id] = Vector2(p.x, p.z)
	return _modular_seats


## Whether this player stands at the sampling station (or has it focused): its pads then answer the
## computer keys and a MIDI keyboard's notes 36-51.
func at_tv() -> bool:
	if tv == null or not is_instance_valid(tv) or not tv.is_inside_tree() or tv.deck == null:
		return false
	if focus != null and focus.focused_id == tv.surface_id:
		return true
	var local := tv.global_transform.affine_inverse() * _standing_at()
	return local.z > 0.2 and local.z < 3.2 and absf(local.x) < 1.8


func _follow_pads() -> void:
	var here := at_tv()
	if tv != null and is_instance_valid(tv) and tv.deck != null:
		if tv.deck.engaged and not here:
			tv.deck.stop_all()
		tv.deck.engaged = here
	if Session.guest_midi != null:
		var sink := Callable(tv.deck, "midi") if here else Callable()
		if Session.guest_midi.pad_sink != sink:
			Session.guest_midi.pad_sink = sink


## Each frame: this player's keys play the rack while they are at it (or its PLAY has the computer
## keys), its controls take the pointer only then, its lamps follow its meters, and the case glows with
## what it plays in the venue's mood. The song's recording is caught from it on the host.
var _modular_owed := 1.0


func _follow_modular() -> void:
	if rack_wall == null or not is_instance_valid(rack_wall):
		return
	var here := at_modular()
	var engaged := here or (modular_keys != null and modular_keys.is_active())
	rack_wall.within_reach = here
	if Session.guest_midi != null:
		Session.guest_midi.reach(Modular.SOURCE, engaged)
		Session.guest_midi.synth.redirect = rack_voice if engaged and Session.is_authority() else null
	if not here and modular_keys != null and modular_keys.is_active() and not rack_wall.visible:
		_modular_play(false)
	_follow_world_sockets()
	if rack_voice == null or not is_instance_valid(rack_voice):
		return
	if engaged and Session.is_authority():
		_rack_wake()
	if rack_voice.running():
		rack_wall.show_meters(rack_voice.meters)
		rack_wall.show_scopes(rack_voice.scopes)
		rack_wall.show_steps(rack_voice.steps)
		rack_wall.glow_with(rack_voice.level, rack_voice.hit)
		if modular_annex != null and is_instance_valid(modular_annex):
			modular_annex.glow_with(rack_voice.level, rack_voice.hit)
			modular_annex.show_levels(rack_wall.module_levels(rack_voice.meters))
			modular_annex.show_scope(rack_voice.scopes)
		rack_wall.set_recording(rack_voice.recording())
		# The song recording catches the rack: begun at the take's start, kept where it ends.
		if DAW.state != null and int(rack_row["track"]) > 0:
			if DAW.state.recording and not rack_voice.recording() and DAW.state.playing:
				_rack_auto_take = rack_voice.record_start(DAW.state.position_seconds)
			elif not DAW.state.recording and rack_voice.recording() and _rack_auto_take:
				rack_voice.record_stop()
				_rack_auto_take = false
	else:
		rack_wall.glow_with(0.0, 0.0)
		if modular_annex != null and is_instance_valid(modular_annex):
			modular_annex.glow_with(0.0, 0.0)


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
	elif room_rows._predict(Sampler.VERB, [on]) > 0:
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
## the pitch it rang for them (their song position `song` pitches a bar). Their strike on one that
## stands still is nobody's to hold: caught struck, on its zone.
func _on_someones_hit(id: StringName, velocity: int, from: int, song := -1.0, _snap := false, take := -1,
		zone := &"") -> void:
	var item := items.items.get(id) as InstrumentItem if items != null else null
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
		var place: Variant = row[3]
		if item == null or not (place is Array):
			continue
		if (place as Array).size() == 3 and str(place[0]) == "slot":
			items.slot(item, StringName(str(place[1])), int(place[2]))
		elif (place as Array).size() >= 4:
			items.lay(item, Vector2(float(place[0]), float(place[2])), float(place[3]))


## What the host has set for the next roll: kept here, not in the panel, so it outlives the
## panel (which only stands in the Rig Roulette room) and a roll anywhere reads it.
var roll_settings := RollSettings.new()

## How much bigger the setup wall in the room is than the panel it was.
const SETUP_WALL_SCALE := 2.9


## Where the saved presets live; a test points it elsewhere.
var roll_presets_path := RollPresets.PATH


static func wall_pool(pool: RollSettings.Pool) -> RigRouletteStation.Pool:
	return int(pool) as RigRouletteStation.Pool


## What the big board shows: &"" for the roll's write-up, or a mounted surface's id. The room's
## choice, the same for everyone in it (`room_state`'s "board").
var board_source: StringName = &""


static func board_title(source: StringName) -> String:
	match source:
		&"": return "ROLL"
		&"rack": return "FX RACK"
		&"tape_deck": return "TAPE DECK"
	return String(source).replace("_", " ").to_upper()


var _roll_shown := 0
## Rolls made since the band last came into the Rig Roulette room.
var _rolls_this_visit := 0


## How many tracks a roll starts the new project with.
const ROLL_TRACKS_MIN := RollSettings.TRACKS_MIN
const ROLL_TRACKS_MAX := RollSettings.TRACKS_MAX

## How many rolls back an undo can go.
const ROLL_HISTORY_MAX := 8

## What the project was before each roll, newest last: {file, original, prev_roll}.
var _roll_history: Array = []
var _history_swept := false


## A roll in a few words, for the board's list of the ones before.
static func roll_summary(roll: Dictionary) -> String:
	var key: String = roll.get("key", "")
	return "#%d  %d tracks, %d pedal%s%s" % [roll.get("n", 0), roll.get("tracks", 0), (roll.get("pedals", []) as Array).size(),
			"" if (roll.get("pedals", []) as Array).size() == 1 else "s", (", " + key) if not key.is_empty() else ""]


## Up to three of the room's loose, unheld things, thrown in from the back of house at the desk:
## the room's own flight (ItemRoom.fly), so a guest sees exactly the same throw through the room
## state -- nothing new rides the wire. Seeded off the run, so a replay throws the same things at
## the same spots. Host only: the room is the host's.
const CROWD_PROPS: Array[StringName] = [&"duck", &"ball", &"toy", &"plane"]

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


## What this player is told on plugging `source` (its `item`, if it is one) from `was` into
## `sink`: where what it plays goes now.
static func plugged_text(source: StringName, item: Item, was: StringName, sink: StringName) -> String:
	var the := "Your keys" if Jack.keys_player(source) > 0 else "The " + Jacks.source_name(source, item)
	var player := Jack.player_of(sink)
	if Jack.chord_player(source) > 0:
		# A chord hand (part two, slice 33): no notes, a chord for their fingertips.
		if player > 0:
			return "Your chord hand goes into %s: the chord you hold is theirs, on their fingertips." \
					% Session.name_of(player)
		return "Your chord hand is unplugged."
	if player > 0:
		var plays := "its hits play chord tones" if item is InstrumentItem and not (item as InstrumentItem).pitched() \
				else "its notes play"
		if Jack.keys_player(source) > 0:
			plays = "what you play plays"
		return "%s go%s into %s: %s on their keys." % [the, "" if Jack.keys_player(source) > 0 else "es",
				Session.name_of(player), plays]
	if sink != &"" and Jack.is_world(source):
		return "%s's jack is in %s: every drop is recorded there while the song records, heard or not." % [the, Jacks.sink_name(sink)]
	if sink != &"":
		return "%s's jack is in %s: its hits are recorded there, armed or not." % [the, Jacks.sink_name(sink)]
	if Jack.player_of(was) == Session.local_peer_id and Session.local_peer_id != 0:
		return "%s is unplugged from you." % the
	if Jack.is_world(source):
		return "%s is unplugged: its drops are recorded nowhere." % the
	if not Jack.is_item(source):
		return "%s %s unplugged." % [the, "are" if Jack.keys_player(source) > 0 else "is"]
	return "%s is unplugged: its hits go on the armed track again." % the


## How a player at `medium` (Presentation.Medium) takes out a jack that goes into them, in words:
## at a desk Shift+P with an empty hand, in a headset a press on the INTO ME jack on their left
## wrist; and, `own_jack` (an item, not a bandmate's keys, whose socket is on the
## bandmate), a press on its own jack as well.
static func unplug_how(medium: int, own_jack: bool) -> String:
	var how := "Shift+P with an empty hand" if medium == Presentation.Medium.SCREEN \
			else "A press on the INTO ME jack on your left wrist"
	return "%s%s unplugs it." % [how, ", or a press on its jack," if own_jack else ""]


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
		room_rows._predict(verb, args)


## The room told once at the end of the frame, however many things in it moved during it.
func _publish_room_soon() -> void:
	if Session.role != Session.Role.HOST or _applying_room or _room_publish_due:
		return
	_room_publish_due = true
	# A method and not a lambda: a studio freed before the frame ends is skipped, not called.
	_publish_room_due.call_deferred()


func _publish_room_due() -> void:
	_room_publish_due = false
	room_rows._publish_room()


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
	walker.ceiling = _ceiling()
	walker.ceiling_at = _ceiling_at
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
## modular's PLAY, the fingertips): held back, so a stray I in the middle of a phrase
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
	# A text field has the keyboard: none of the room's key shortcuts are for it.
	if event is InputEventKey and TextFocus.held(get_viewport()):
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
			signal_views.look_solo_press(&"key")
		else:
			signal_views.look_solo_release(&"key")
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
				station_host._sit_down()
			# The other half of the desk. A console pages by default, because twelve strips
			# you can face beats forty-eight you have to turn your head through -- but a
			# mix is sometimes a thing you want to see all of at once, and then the tiers
			# are worth the neck. One key, and it is the one the desk is named after.
			KEY_E:
				_toggle_expanded()
			KEY_G:
				station_host._toggle_summoning()
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
				signal_views.toggle_signal_view()
			# Why can't I hear this? Y over it, with the signal showing; Shift-Y does the fix.
			KEY_Y when not event.ctrl_pressed and not event.meta_pressed:
				if event.shift_pressed:
					signal_views.fix_traced()
				else:
					signal_views.trace_pointed(get_node_or_null("MouseHand") as Interactor)
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
				surface_host.toggle_fingertips()
			# The computer keyboard as a piano, to play whatever instrument is on the track: P.
			KEY_P when not event.ctrl_pressed and not event.meta_pressed:
				computer_keys_toggled.emit()
			# The chord layer: C for chords. 1 to 7 then pick them in the keys that play.
			KEY_C when not event.ctrl_pressed and not event.meta_pressed:
				surface_host.toggle_chords()
			# Go to the instruments one at a time, as F goes to the gear: I for instrument.
			# Shift goes the other way. The help card's PLAY pages go to one by name.
			KEY_I:
				station_host.cycle_stations(-1 if event.shift_pressed else 1)
			KEY_ESCAPE:
				_on_escape()
			# Backspace over a voice on the stage table, or anything of its tag: that track back to
			# centre, 0 dB and full width, as a double-click on it does.
			KEY_BACKSPACE:
				var hand := get_node_or_null("MouseHand") as MouseInteractor
				var under: Node = (hand.held if hand.held != null else hand.hovered) if hand != null else null
				if stage != null and hand != null:
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
	signal_views._follow_signal(delta)
	room_rows._drive_pushed()
	surface_host._refresh_looms_if_moved(delta)
	_follow_clap(delta)
	signal_views._follow_look_solo(delta)
	_follow_lean()
	_follow_ear()
	_follow_wheel()
	_modular_owed += get_process_delta_time()
	if _modular_owed >= 1.0 / 30.0 - 0.001:
		_modular_owed = 0.0
		_follow_modular()
		_follow_pads()
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
	if focus != null:
		focus.release()
	_release_stray_screens()
	station_host._sit_down()


func _release_stray_screens() -> void:
	for id in mount.mounted_ids():
		if mount.mode_of(id) == Presentation.Mode.SCREEN \
				and mount.mode_of(id) != mount.default_mode_of(id, medium):
			mount.set_mode(id, mount.default_mode_of(id, medium))


var _walk: Tween


# --- going to the instruments (docs/spatial_loop.md part two, slice 10) ------------------------

## The station last gone to (a Stations id), so I and Shift-I go on round from it; empty before
## the first.
var station := &""


## How fast going to a station covers the floor (m/s), at motion 1: a brisk walk, so the live
## room's far wall is a second and a half from the desk rather than a lurch.
const STATION_PACE := 4.0


# --- going to a station in a headset (docs/spatial_loop.md part two, slice 11) -----------------

## The station board's stand, back by the way into the live room on the right, turned to face the
## mix position: out of the seat's view of the desk (it stood at the desk's left elbow, in the face
## of everyone who sat down), and on the way to the stations it lists. Desktop players reach the
## same rows with I and F1; a headset player turns round to it.
## (The fragment's `station_board`.)

## The board by the desk (StationBoard): every station that stands here, a row each, and a press
## goes there. Null in AR, where nothing stands yet (slice 60).
var station_board: StationBoard
## The board's rows beside a plaque, while its INSTRUMENTS key has them up; else null.
var _beside: StationBoard
## A walker kept out of the tree, for where a person fits when there is no walker of our own (a
## headset): so a headset's seat is the desktop's seat, in from a table that stands in the way.
var _seat_finder: Walker


## The stand's grip, round the board's foot and post.
var _board_grip: CollisionShape3D


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


var _signal_rows: Array = []


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


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		# Never a stuck solo: a key let go while another window had focus never comes here.
		signal_views.look_solo_release()


## The Rig Roulette panel, setup wall and the roll itself (`RollRoom`).
var roll_room := RollRoom.new(self)


## Delegates to `roll_room.board_sources`.
func board_sources() -> Array[StringName]:
	return roll_room.board_sources()


## Delegates to `roll_room.choose_board_source`.
func choose_board_source(source: StringName) -> void:
	roll_room.choose_board_source(source)


## Delegates to `roll_room._roll_rig`.
func _roll_rig() -> void:
	roll_room._roll_rig()


## Delegates to `roll_room._throw_the_knobs`.
func _throw_the_knobs(track: int, fx: MixState.FXState, rng: RandomNumberGenerator, chaos: int) -> void:
	roll_room._throw_the_knobs(track, fx, rng, chaos)


## Delegates to `roll_room._forget`.
func _forget(entry: Dictionary) -> void:
	roll_room._forget(entry)


## Delegates to `roll_room.undo_the_roll`.
func undo_the_roll() -> void:
	roll_room.undo_the_roll()


## The Tour case, its chaos, spills and crowd in the room (`TourRoom`).
var tour_room := TourRoom.new(self)


## Delegates to `tour_room._on_tour_case_struck`.
func _on_tour_case_struck() -> void:
	tour_room._on_tour_case_struck()


## Delegates to `tour_room._on_tour_run_ended`.
func _on_tour_run_ended(won: bool) -> void:
	tour_room._on_tour_run_ended(won)


## Delegates to `tour_room._spill_home`.
func _spill_home(n: int) -> Transform3D:
	return tour_room._spill_home(n)


## Items in the room: their homes, minting, giving, weather and the looper (`ItemHost`).
var item_host := ItemHost.new(self)


## Delegates to `item_host._item_homes`.
func _item_homes() -> Dictionary:
	return item_host._item_homes()


## Delegates to `item_host._on_clip_pulled`.
func _on_clip_pulled(track: int, index: int, hand: Node) -> void:
	item_host._on_clip_pulled(track, index, hand)


## Delegates to `item_host._mint_for`.
func _mint_for(kind: StringName, from: String, maker: int) -> Item:
	return item_host._mint_for(kind, from, maker)


## Delegates to `item_host._follow_making`.
func _follow_making() -> void:
	item_host._follow_making()


## Delegates to `item_host.give_item`.
func give_item(item: Item, peer: int) -> void:
	item_host.give_item(item, peer)


## Delegates to `item_host._on_weather_pressed`.
func _on_weather_pressed(on: bool) -> void:
	item_host._on_weather_pressed(on)


## Delegates to `item_host._on_weather_dropped`.
func _on_weather_dropped(drop: Dictionary) -> void:
	item_host._on_weather_dropped(drop)


## Delegates to `item_host._looper_name`.
func _looper_name(peer: int) -> String:
	return item_host._looper_name(peer)


## Delegates to `item_host._on_looper_slapped`.
func _on_looper_slapped() -> void:
	item_host._on_looper_slapped()


## Delegates to `item_host._on_looper_layer`.
func _on_looper_layer(start: float, end: float, notes: Array) -> void:
	item_host._on_looper_layer(start, end, notes)


## Delegates to `item_host._on_looper_called_off`.
func _on_looper_called_off() -> void:
	item_host._on_looper_called_off()


## Delegates to `item_host._on_looper_player_left`.
func _on_looper_player_left(peer: int) -> void:
	item_host._on_looper_player_left(peer)


## Jacks, patch cables and the on-air light in the room (`PatchHost`).
var patch_host := PatchHost.new(self)


## Delegates to `patch_host._on_patch_asked`.
func _on_patch_asked(receiver: int, socket: StringName) -> void:
	patch_host._on_patch_asked(receiver, socket)


## Delegates to `patch_host._on_plug_asked`.
func _on_plug_asked(source: StringName, sink: StringName) -> void:
	patch_host._on_plug_asked(source, sink)


## Delegates to `patch_host._plug_refusal`.
func _plug_refusal(source: StringName, sink: StringName, from: int, here := false) -> String:
	return patch_host._plug_refusal(source, sink, from, here)


## Delegates to `patch_host._on_jack_player_left`.
func _on_jack_player_left(peer: int) -> void:
	patch_host._on_jack_player_left(peer)


## Delegates to `patch_host._wear_chord_jacks`.
func _wear_chord_jacks() -> void:
	patch_host._wear_chord_jacks()


## Delegates to `patch_host._show_patches`.
func _show_patches() -> void:
	patch_host._show_patches()


## Delegates to `patch_host._on_send_pressed`.
func _on_send_pressed(source: StringName) -> void:
	patch_host._on_send_pressed(source)


## Delegates to `patch_host._set_on_air`.
func _set_on_air(peer: int, on: bool, show := true) -> void:
	patch_host._set_on_air(peer, on, show)


## Tablets and track racks: open, build, close, dock and remember (`TabletHost`).
var tablet_host := TabletHost.new(self)


## Delegates to `tablet_host._on_tear_requested`.
func _on_tear_requested(track: int, fx: int, at: Vector3, from: Node3D = null) -> void:
	tablet_host._on_tear_requested(track, fx, at, from)


## Delegates to `tablet_host.open_tablet`.
func open_tablet(track: int, fx: int, plugin_name: String, where: Vector2) -> StringName:
	return tablet_host.open_tablet(track, fx, plugin_name, where)


## Delegates to `tablet_host._build_tablet`.
func _build_tablet(id: StringName, track: int, fx: int, plugin_name: String) -> void:
	tablet_host._build_tablet(id, track, fx, plugin_name)


## Delegates to `tablet_host.close_tablet`.
func close_tablet(id: StringName) -> void:
	tablet_host.close_tablet(id)


## Delegates to `tablet_host._take_down_tablet`.
func _take_down_tablet(id: StringName) -> void:
	tablet_host._take_down_tablet(id)


## Delegates to `tablet_host._predicted_tablet`.
func _predicted_tablet(track: int, fx: int, plugin_name: String, where: Vector2) -> StringName:
	return tablet_host._predicted_tablet(track, fx, plugin_name, where)


## Delegates to `tablet_host.open_track_rack`.
func open_track_rack(track: int, where: Vector2) -> StringName:
	return tablet_host.open_track_rack(track, where)


## Delegates to `tablet_host.close_track_rack`.
func close_track_rack(id: StringName) -> void:
	tablet_host.close_track_rack(id)


## Delegates to `tablet_host._fold_orphaned_track_racks`.
func _fold_orphaned_track_racks() -> void:
	tablet_host._fold_orphaned_track_racks()


## The control room's furniture and live pieces (`FurnitureHost`).
var furniture_host := FurnitureHost.new(self)


## Delegates to `furniture_host._build_furniture`.
func _build_furniture() -> void:
	furniture_host._build_furniture()


## Delegates to `furniture_host._levels_niche_at`.
func _levels_niche_at() -> Transform3D:
	return furniture_host._levels_niche_at()


## Delegates to `furniture_host._grip`.
func _grip(t: Trolley, size: Vector3, at: Vector3) -> CollisionShape3D:
	return furniture_host._grip(t, size, at)


## Delegates to `furniture_host._go_live`.
func _go_live(t: Trolley) -> void:
	furniture_host._go_live(t)


## Delegates to `furniture_host._live_default`.
func _live_default(id: StringName) -> Variant:
	return furniture_host._live_default(id)


## Delegates to `furniture_host._carry_live`.
func _carry_live(id: StringName) -> void:
	furniture_host._carry_live(id)


## The room rows: publishing, applying and answering room verbs (`RoomRows`).
var room_rows := RoomRows.new(self)


## Delegates to `room_rows.room_state`.
func room_state() -> Dictionary:
	return room_rows.room_state()


## Delegates to `room_rows._publish_room`.
func _publish_room() -> void:
	room_rows._publish_room()


## Delegates to `room_rows.apply_room`.
func apply_room(state: Dictionary, glide := false) -> void:
	room_rows.apply_room(state, glide)


## Delegates to `room_rows._follow_room`.
func _follow_room(t: Trolley, x: float, z: float, heading: float, glide: bool) -> void:
	room_rows._follow_room(t, x, z, heading, glide)


## Delegates to `room_rows._predict`.
func _predict(verb: StringName, args: Array, id := StringName()) -> int:
	return room_rows._predict(verb, args, id)


## Delegates to `room_rows._on_room_motion`.
func _on_room_motion(id: StringName, x: float, z: float, heading: float, _from: int) -> void:
	room_rows._on_room_motion(id, x, z, heading, _from)


## Delegates to `room_rows._drive_pushed`.
func _drive_pushed() -> void:
	room_rows._drive_pushed()


## Delegates to `room_rows._on_room_asked`.
func _on_room_asked(verb: StringName, args: Array, from: int) -> void:
	room_rows._on_room_asked(verb, args, from)


## Delegates to `room_rows._floor_piece`.
func _floor_piece(id: StringName) -> Trolley:
	return room_rows._floor_piece(id)


## Anchors, surfaces, lamp stands and looms (`SurfaceHost`).
var surface_host := SurfaceHost.new(self)


## Delegates to `surface_host._reseat`.
func _reseat(id: StringName, put: Transform3D) -> void:
	surface_host._reseat(id, put)


## Delegates to `surface_host.toggle_chords`.
func toggle_chords() -> void:
	surface_host.toggle_chords()


## Delegates to `surface_host.toggle_fingertips`.
func toggle_fingertips() -> void:
	surface_host.toggle_fingertips()


## Delegates to `surface_host._on_tracks_renumbered`.
func _on_tracks_renumbered(_map: Dictionary) -> void:
	surface_host._on_tracks_renumbered(_map)


## Delegates to `surface_host.refresh_looms`.
func refresh_looms() -> void:
	surface_host.refresh_looms()


## Delegates to `surface_host.edit_lyrics`.
func edit_lyrics() -> void:
	surface_host.edit_lyrics()


## Seats, stations, the station board and the desk wing (`StationHost`).
var station_host := StationHost.new(self)


## Delegates to `station_host._sit_down`.
func _sit_down() -> void:
	station_host._sit_down()


## Delegates to `station_host._walk_to_seat`.
func _walk_to_seat() -> void:
	station_host._walk_to_seat()


## Delegates to `station_host._toggle_summoning`.
func _toggle_summoning() -> void:
	station_host._toggle_summoning()


## Delegates to `station_host.station_ids`.
func station_ids() -> Array[StringName]:
	return station_host.station_ids()


## Delegates to `station_host.cycle_stations`.
func cycle_stations(direction: int) -> StringName:
	return station_host.cycle_stations(direction)


## Delegates to `station_host.go_to_station`.
func go_to_station(id: StringName) -> bool:
	return station_host.go_to_station(id)


## Delegates to `station_host.plaque_key`.
func plaque_key(id: StringName, kind: StringName, key: Node3D) -> void:
	station_host.plaque_key(id, kind, key)


## Delegates to `station_host.travel_refusal`.
func travel_refusal() -> String:
	return station_host.travel_refusal()


## Delegates to `station_host.co_located`.
func co_located() -> bool:
	return station_host.co_located()


## Delegates to `station_host.go_home`.
func go_home() -> void:
	station_host.go_home()


## Delegates to `station_host._station_fits`.
func _station_fits() -> Callable:
	return station_host._station_fits()


## Delegates to `station_host._wire_miniature`.
func _wire_miniature() -> void:
	station_host._wire_miniature()


## Signal view, look-solo and trace (`SignalViews`).
var signal_views := SignalViews.new(self)


## Delegates to `signal_views.signal_view_on`.
func signal_view_on() -> bool:
	return signal_views.signal_view_on()


## Delegates to `signal_views.toggle_signal_view`.
func toggle_signal_view() -> void:
	signal_views.toggle_signal_view()


## Delegates to `signal_views.signal_sources`.
func signal_sources() -> Array:
	return signal_views.signal_sources()


## Delegates to `signal_views.signal_place`.
func signal_place(id: String) -> Variant:
	return signal_views.signal_place(id)


## Delegates to `signal_views._follow_signal`.
func _follow_signal(delta: float) -> void:
	signal_views._follow_signal(delta)


## Delegates to `signal_views.looked_track`.
func looked_track() -> int:
	return signal_views.looked_track()


## Delegates to `signal_views._follow_look_solo`.
func _follow_look_solo(delta: float) -> void:
	signal_views._follow_look_solo(delta)


## Delegates to `signal_views.signal_target_of`.
func signal_target_of(node: Node, point := Vector3.ZERO) -> Array:
	return signal_views.signal_target_of(node, point)


## Delegates to `signal_views.trace_pointed`.
func trace_pointed(hand: Interactor) -> bool:
	return signal_views.trace_pointed(hand)


## Delegates to `signal_views.trace_from`.
func trace_from(from: String, title: String) -> bool:
	return signal_views.trace_from(from, title)


## Delegates to `signal_views.fix_traced`.
func fix_traced() -> bool:
	return signal_views.fix_traced()
