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
const LAMP_SHADE_HEIGHT := 0.150
## The patch stand: the bay's own cabinet, out to the right of the desk past the deck, turned to
## face the mix position. Its own station rather than a strip on a meter bridge between the timeline and
## the console, where it was a hand's width tall and read as part of both. Where on the stand the
## bay's top edge is, and how far the cabinet under it reaches back.
const PATCH_BAY_TOP := 1.78
const PATCH_BAY_FRONT := 0.03

## Set by whoever builds the studio, BEFORE adding it to the tree. The medium is not a rendering
## detail: it decides whether this participant gets a floor and furniture at all, and a studio
## that learned it a frame late would build a virtual room and then delete it in front of someone
## already wearing the headset.
var medium: int = Presentation.Medium.SCREEN
var xr_bootstrap: XRBootstrap = null

## The venue was switched to `id` (after the room was rebuilt).
signal venue_changed(id: StringName)
## EDIT on the lyric board at a desk: the session panel's LYRICS box, which is not the studio's, is
## asked to open (LyricBoard, docs/spatial_loop.md part two, slice 56).
signal lyrics_edit_asked()
## P: the computer keyboard as a piano, on or off (the session panel's KeyCatcher).
signal computer_keys_toggled()

## The world the studio stands in. See core/venues/venue.gd.
var venue: Venue
var world_env: WorldEnvironment
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
## This player's chord hand (ChordHand, docs/spatial_loop.md part two, slice 32): the shape the
## left hand holds up (the right for a left-handed player), the chord stick, and on a desktop the
## chord layer (C).
var chord_hand: ChordHand
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
## The help card of a rack module (RackHelpScreen), opened by a click on a module's name.
var rack_help: RackHelpScreen
var rack_finder: RackFinderScreen
var rack_voice: RackVoice
## Loads the host's saved rack when the wall is built and saves it a moment after each change.
var rack_files := RackAutosave.new()
## The delta of the room this studio is in: where its furniture was left (`RoomDeltas`).
var room_deltas := RoomDeltas.new()
## What the weather, the rings and the venue's instrument play into the rack's WORLD module.
var modular_world: ModularWorld
var modular_annex: ModularAnnex
var rack_row := {"patch": RackPatch.preset(&"keys_voice"), "track": 0, "power": true}
## The lyric board in the vocal booth (LyricBoard, docs/spatial_loop.md part two, slice 56), stood
## again with each venue at its `lyrics_spot`; null where there is no booth and in AR. What it shows is
## the song's (MixState.lyrics), so nothing of it is the room's.
var lyric_board: LyricBoard
## The vocal booth's singer (SingerHost): the room's row `singer` (SingerRow), its station in the booth, and the
## voice itself (the host's only).
var singer_row := SingerRow.fresh()
var singer_booth: SingerBooth
var singer: Singer
var modular_keys: KeyCatcher
## The DJ platter on the leaf of the tape deck's cart (Platter, docs/spatial_loop.md part two, slice
## 27): bare it is the playhead, scrubbed by hand; a cassette in its slot is scratched. Rides the
## cart, so it is the studio's and not the venue's. Null in AR.
var platter: Platter
## A guest's pulls the host has not answered: {seq, hand, look}, the look a blank cassette in that
## hand until the host's made one arrives there or the ask is refused (`_settle_makes`).
var _making: Array = []
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
## Whether what stands here is the host's room rather than this participant's own.
var _showing_hosts_room := false
## A guest's asks the host has not answered yet: {seq, verb, args, id}. See apply_room.
var _predictions: Array = []
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

## The floor and everything on wheels. Null in AR, where the floor is real and so is the
## furniture.
var floor_plan: FloorPlan
var rack_trolley: Trolley
var deck_trolley: Trolley
var timeline_stand: Trolley
var patch_stand: Trolley
## The stage table (StageTable, docs/spatial_loop.md slice 18) and the trolley it stands on.
var stage: StageTable
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
## Surface id -> [the trolley it stands on, where on that trolley].
var _seated_on := {}
var _lamps: Array[OmniLight3D] = []
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
	# What the music is doing, for every visual that moves with it (docs/visuals.md).
	var features := AudioFeatures.new()
	features.name = "AudioFeatures"
	add_child(features)
	venue_look._build_environment()
	# In AR the room is already there -- it is the one the participant is standing in. Drawing a
	# virtual floor over a real one is not a smaller version of the VR experience, it is a worse
	# one: it hides the actual floor and it disagrees with it by however much calibration is off.
	if medium != Presentation.Medium.AR:
		if Session.layout != null:
			venue_switch.set_venue(Session.layout.venue, false, Session.layout.venue_variant)
		else:
			venue_switch.set_venue(Venue.IDS[0], false)
	surface_host._build_anchors()
	if medium != Presentation.Medium.AR:
		furniture_host._build_furniture()
	surface_host._build_surfaces()
	station_host._build_point_and_mark()
	if camera != null:
		player_host._build_walker()
		view_host._update_camera()
	if medium != Presentation.Medium.AR:
		item_host._build_items()
		tour_room._build_tour_case()
		roll_room._build_rig_roulette_station()
	else:
		# AR's room is the player's own real one: of the room's items, only the drum pads' kit on the
		# desk's rail, which plays there as anywhere (docs/spatial_loop.md part two, slice 41).
		item_host._build_items()
	view_host._build_pads()
	if medium == Presentation.Medium.AR and xr_bootstrap != null:
		# Now, and not in XRBootstrap.start(): the environment it has to clear is the one built
		# four lines up.
		xr_bootstrap.apply_passthrough()


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
	if get_tree().node_added.is_connected(venue_look._keep_out_of_mirrors):
		get_tree().node_added.disconnect(venue_look._keep_out_of_mirrors)


## Rig Roulette is switched off for now (the door, the room and the roll): the code is all here,
## and DAWLINGS_ROULETTE=1 turns it back on for working on it.
static var roulette_enabled := OS.get_environment("DAWLINGS_ROULETTE") == "1"


## Delegates to `VenueSwitch.in_roulette_room_venue`.
static func in_roulette_room_venue(v: Venue) -> bool:
	return VenueSwitch.in_roulette_room_venue(v)


## The screen on the legs, its top PATCH_WALL_TOP over them, in the venue's frame.
const PATCH_WALL_SCALE := 0.55
const PATCH_WALL_TOP := 2.2


## Where the stage table's trolley stands: beside the mix position on the right and a little
## behind it, turned to face it, clear of the deck trolley and the patch stand however wide the
## desk grows (the desk's footprint ends in front of the mix position, and these stand behind
## it). The top is desk height; the rail along its front drops RAIL below it. Far enough back
## that from the seat the right-hand lamp's foot is seen past its corner, not through it.
const STAGE_TOP := 0.74


var _pads_followed := {}
var _pads_loaded := ""


## The time a desk put down across the room takes to get there on this screen.
const GLIDE_SECONDS := 0.25


## The desk's measured box. Measuring walks every part of it, and the walker asks every physics
## tick, so it is kept for a quarter of a second -- or until the desk is rebuilt, which is what
## changes it.
const DESK_BOX_FOR_MSEC := 250


## Delegates to `SurfaceHost.loom_level`.
static func loom_level(machine: String) -> Callable:
	return SurfaceHost.loom_level(machine)


## What the host has set for the next roll: kept here, not in the panel, so it outlives the
## panel (which only stands in the Rig Roulette room) and a roll anywhere reads it.
var roll_settings := RollSettings.new()


## Where the saved presets live; a test points it elsewhere.
var roll_presets_path := RollPresets.PATH


## Delegates to `RollRoom.wall_pool`.
static func wall_pool(pool: RollSettings.Pool) -> RigRouletteStation.Pool:
	return RollRoom.wall_pool(pool)


## What the big board shows: &"" for the roll's write-up, or a mounted surface's id. The room's
## choice, the same for everyone in it (`room_state`'s "board").
var board_source: StringName = &""


## Delegates to `RollRoom.board_title`.
static func board_title(source: StringName) -> String:
	return RollRoom.board_title(source)


## Rolls made since the band last came into the Rig Roulette room.
var _rolls_this_visit := 0


## How many tracks a roll starts the new project with.
const ROLL_TRACKS_MIN := RollSettings.TRACKS_MIN
const ROLL_TRACKS_MAX := RollSettings.TRACKS_MAX


## Delegates to `RollRoom.roll_summary`.
static func roll_summary(roll: Dictionary) -> String:
	return RollRoom.roll_summary(roll)


## Delegates to `MixFollow.track_of`.
static func track_of(node: Node, point: Vector3) -> int:
	return MixFollow.track_of(node, point)


## Delegates to `PatchHost.plugged_text`.
static func plugged_text(source: StringName, item: Item, was: StringName, sink: StringName) -> String:
	return PatchHost.plugged_text(source, item, was, sink)


## Delegates to `PatchHost.unplug_how`.
static func unplug_how(medium: int, own_jack: bool) -> String:
	return PatchHost.unplug_how(medium, own_jack)


## A level to give the venue in place of the mix's (0..1), or -1 for the mix's own: for a
## photograph of a room at a chosen loudness (`--feed-level`).
var fed_level := -1.0


var _walk: Tween


# --- going to the instruments (docs/spatial_loop.md part two, slice 10) ------------------------

## The station last gone to (a Stations id), so I and Shift-I go on round from it; empty before
## the first.
var station := &""


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

## The table, its origin on the floor under the middle of its board. Null in AR.
var desk_wing: Trolley
## Pointing, sticky notes and listening from a spot (slice 35), and the pad of notes: on the table,
## or in AR (no table; the room's furniture is the player's own) at the console's left end, at its
## height, NOTE_PAD_GAP off it (`_place_note_pad`).
var point_and_mark: PointAndMark
var note_pad: NotePad
const NOTE_PAD_GAP := 0.04


# --- seeing the signal (docs/spatial_loop.md part three, A and B) ---------------------------------

## The signal view (SignalView): made the first time it is wanted, and this player's alone. Nothing
## about it is room state or sent: a bandmate's glasses change nothing here.
var signal_view: SignalView = null
## X at a desk: the view on without the glasses.
var signal_key_on := false


const EAR_LEAVE := 0.08
## What holds this machine's look-solo: &"key" (U) or &"ear", or &"" for nothing.
var _look_by := &""


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		# Never a stuck solo: a key let go while another window had focus never comes here.
		signal_views.look_solo_release()
		_unfocused_pacing(true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_unfocused_pacing(false)


## A window the compositor is not showing (another workspace, tabbed out) gets no frame callbacks, so a vsynced present
## blocks the main thread for long stretches and the sound that is fed once a frame (the rack's direct feed, the
## monitor synth) runs dry and crackles. Unfocused, present without waiting, and keep the frame rate low; back on focus.
var _vsync_before := -1


func _unfocused_pacing(away: bool) -> void:
	if get_viewport() != null and get_viewport().use_xr:
		return
	if away and _vsync_before < 0:
		_vsync_before = DisplayServer.window_get_vsync_mode()
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 30
	elif not away and _vsync_before >= 0:
		DisplayServer.window_set_vsync_mode(_vsync_before as DisplayServer.VSyncMode)
		Engine.max_fps = 0
		_vsync_before = -1


## The Rig Roulette panel, setup wall and the roll itself (`RollRoom`).
var roll_room := RollRoom.new(self)


## Delegates to `roll_room._forget`.
func _forget(entry: Dictionary) -> void:
	roll_room._forget(entry)


## The Tour case, its chaos, spills and crowd in the room (`TourRoom`).
var tour_room := TourRoom.new(self)


## Items in the room: their homes, minting, giving, weather and the looper (`ItemHost`).
var item_host := ItemHost.new(self)


## Jacks, patch cables and the on-air light in the room (`PatchHost`).
var patch_host := PatchHost.new(self)


## Delegates to `patch_host._on_patch_asked`.
func _on_patch_asked(receiver: int, socket: StringName) -> void:
	patch_host._on_patch_asked(receiver, socket)


## Delegates to `patch_host._on_plug_asked`.
func _on_plug_asked(source: StringName, sink: StringName) -> void:
	patch_host._on_plug_asked(source, sink)


## Delegates to `patch_host._set_on_air`.
func _set_on_air(peer: int, on: bool, show := true) -> void:
	patch_host._set_on_air(peer, on, show)


## Tablets and track racks: open, build, close, dock and remember (`TabletHost`).
var tablet_host := TabletHost.new(self)


## Delegates to `tablet_host.open_tablet`.
func open_tablet(track: int, fx: int, plugin_name: String, where: Vector2) -> StringName:
	return tablet_host.open_tablet(track, fx, plugin_name, where)


## Delegates to `tablet_host.close_tablet`.
func close_tablet(id: StringName) -> void:
	tablet_host.close_tablet(id)


## Delegates to `tablet_host.open_track_rack`.
func open_track_rack(track: int, where: Vector2) -> StringName:
	return tablet_host.open_track_rack(track, where)


## Delegates to `tablet_host.close_track_rack`.
func close_track_rack(id: StringName) -> void:
	tablet_host.close_track_rack(id)


## The control room's furniture and live pieces (`FurnitureHost`).
var furniture_host := FurnitureHost.new(self)


## The room rows: publishing, applying and answering room verbs (`RoomRows`).
var room_rows := RoomRows.new(self)


## Anchors, surfaces, lamp stands and looms (`SurfaceHost`).
var surface_host := SurfaceHost.new(self)


## Delegates to `surface_host.toggle_fingertips`.
func toggle_fingertips() -> void:
	surface_host.toggle_fingertips()


## Delegates to `surface_host.edit_lyrics`.
func edit_lyrics() -> void:
	surface_host.edit_lyrics()


## Seats, stations, the station board and the desk wing (`StationHost`).
var station_host := StationHost.new(self)


## Delegates to `station_host.cycle_stations`.
func cycle_stations(direction: int) -> StringName:
	return station_host.cycle_stations(direction)


## Delegates to `station_host.plaque_key`.
func plaque_key(id: StringName, kind: StringName, key: Node3D) -> void:
	station_host.plaque_key(id, kind, key)


## Delegates to `station_host.go_home`.
func go_home() -> void:
	station_host.go_home()


## Signal view, look-solo and trace (`SignalViews`).
var signal_views := SignalViews.new(self)


## Environment, lamps, ceiling and the walkable floor (`VenueLook`).
var venue_look := VenueLook.new(self)


## Venue changes, the roulette room and fitting the room (`VenueSwitch`).
var venue_switch := VenueSwitch.new(self)


## Delegates to `venue_switch.set_venue`.
func set_venue(id: StringName, persist := true, variant := 0) -> void:
	venue_switch.set_venue(id, persist, variant)


## Delegates to `venue_switch._on_role_changed`.
func _on_role_changed() -> void:
	venue_switch._on_role_changed()


## The rack, the modular room and the annex (`RackHost`).
var rack_host := RackHost.new(self)
var singer_host := SingerHost.new(self)


## The sampler and what the player made (`SamplerHost`).
var sampler_host := SamplerHost.new(self)


## Personal mix, listening and the head follow (`MixFollow`).
var mix_follow := MixFollow.new(self)


## Pockets, headphones, the walker and the debounced saves (`PlayerHost`).
var player_host := PlayerHost.new(self)


## Delegates to `player_host.set_god_mode`.
func set_god_mode(on: bool) -> void:
	player_host.set_god_mode(on)


## Keyboard and mouse input and the hit voices (`InputHost`).
var input_host := InputHost.new(self)


## Delegates to `input_host._unhandled_input`.
func _unhandled_input(event: InputEvent) -> void:
	input_host._unhandled_input(event)


## The per-frame follow, the camera and the kit (`ViewHost`).
var view_host := ViewHost.new(self)


## Delegates to `view_host._process`.
func _process(delta: float) -> void:
	view_host._process(delta)


## Delegates to `view_host.frame`.
func frame(target: Vector3, distance: float, yaw: float, pitch: float) -> void:
	view_host.frame(target, distance, yaw, pitch)


