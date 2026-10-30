class_name Stations
extends RefCounted

## Every instrument that stands somewhere, as one list (docs/spatial_loop.md part two, slice 10):
## the help card's PLAY pages, the desktop's go-to (I and Shift-I, a click on a PLAY line), the
## headset's station board (slice 11) and the suite's clearance loop are all made from it, so a
## later slice that appends its row cannot forget any of them.
##
## A row (`ALL`) is a station: `id`; `title`, as its plaque and the card letter it; `area`, the
## part of the world it is in (CONTROL, LIVE or VENUE, one PLAY page each); `zone`, the
## Venue.ZONES zone it is mounted in, or empty for one that stands on the floor by itself; `air`,
## the free radius it needs round where it is played (m), and, where a row says it (`air_at`, the
## theremin's hands), the point in its frame that air is round; `spot`, the Venue method that places it
## (a Transform3D, or null where the venue has no room for it); `at`, the point in that frame a
## player looks at while playing it; and two lines of help, `desk` (mouse and keys) and `hands`
## (hands and buttons); and `frame`, what of it a player should see from where they stand, its
## top and its foot (two points in its frame, its controls' top first: the harp's crown with its
## 8va buttons, the bells' handles, the wheel board's top edge; then its plaque's bottom, under
## its keys, Stations.plaque_bottom). Every station's front is its frame's +Z: whoever plays it
## stands there, facing back along -Z.
##
## A free-standing row also says its footprint (`foot`, half its size on the floor, and `foot_z`,
## how far along Z its middle is) and how tall it stands (`top`): the footprint of the trolley it
## is pushed about on in a studio (Venue.WHEELED), and the solid a venue gives it standing on its
## own, so the clearance loop, the trolley and the venue cannot disagree about where it is.
##
## A row that rides a piece of the control room's furniture (the platter on the tape deck's cart,
## slice 27) names it (`cart`, the trolley's id): it stands where the cart has been wheeled, has no
## footprint of its own, and says its own `seat`.
##
## A row that is a surface rather than an instrument (the stage table, slice 18, the EQ wall,
## slice 36) says so (`surface`, its surface id), stands on a trolley rather than a venue solid (no
## `foot`), and may say its own `seat`, how far in front of it a player stands (m), where SEAT
## would leave its back edge out of reach, or the whole of a tall one out of view.
##
## A zone-mounted row on the bricks table (the wheel, the section blocks, slice 30, and the chord
## ledge, slice 31) has a band of the table to itself (Venue.TABLE_BANDS, by its id): the clearance loop
## holds those bands clear of each other rather than their `air`, which is for the floor round it.
##
## A row mounted on the venue itself (`mounted`: the venue's own instrument, slice 42, hung from its
## beam, its eave or its back wall, or set into its railing) is neither: it has no trolley and no
## zone, and the venue says what it is as well as where (Venue.instrument), so its title, its help
## lines, what is looked at and its frame are the venue's (`row_in`, VenueInstrument.row_for). Its
## walker solid is the venue's (Venue.solids). Every venue but the Rig Roulette room has one in the
## end (slice 43); a venue with none answers null for its spot. So is the venue's weather's switch
## (`weather`, slice 44, Weather.row_for), on a window's sill or a post, in the arrangements that have
## weather.
##
## Things carried, not stood anywhere (the keytar, the shaker, the tambourine, the bells in a
## hand, the fingertips, the session in miniature, the jacks), the drum pads (on the desk and on
## whatever real surface a headset marks, slice 41), and what the hands do anywhere (clapping to mute, leaning in),
## are `HELD`: help lines only, on PLAY · HELD.

const CONTROL := &"control"
const LIVE := &"live"
const VENUE := &"venue"
const HELD_AREA := &"held"
## The areas in the order the card pages them.
const AREAS: Array[StringName] = [CONTROL, LIVE, VENUE]
const AREA_TITLES := {&"held": "HELD", &"control": "CONTROL ROOM", &"live": "LIVE ROOM", &"venue": "THIS VENUE"}
## Where each area is, as a toast says a station is there ("THE HARP, in the control room: ..."):
## not the page's title lowered, which would say "in the this venue".
const AREA_WHERE := {&"held": "in hand", &"control": "in the control room", &"live": "in the live room",
		&"venue": "in this venue"}
## How far in front of a station its seat is (m), and the nearest it comes in when something
## stands on the floor there: the far side of a table, a wall.
const SEAT := 1.1
const NEAREST := 0.45
## The plaque's lettering: 30 mm letters, readable at 1.5 m and well beyond (Lettering), and how
## wide its hands line runs before it wraps.
const PLAQUE_CAP := 0.03
const PLAQUE_WIDTH := 0.66
## The plaque's keys (INSTRUMENTS and BACK): each this tall, at most PLAQUE_KEY_WIDE, in a row
## this far under the lettering. 7 cm is what the seat audit's 7 px asks of a key the far side of
## the live room from the desk.
const PLAQUE_KEY := 0.07
const PLAQUE_KEY_WIDE := 0.24
const PLAQUE_KEYS_ROW := PLAQUE_KEY + 0.02

const ALL := [
	{
		"id": &"harp", "title": "CHORD HARP", "area": LIVE, "zone": &"", "air": 0.5,
		"spot": &"harp_spot", "at": Vector3(0, 1.05, 0),
		"frame": [Vector3(0, 1.73, 0), Vector3(0, 0.16, 0.26)],
		"foot": Vector2(0.35, 0.2), "foot_z": -0.06, "top": 1.73,
		"desk": "click a string to pluck · drag across to strum · wheel or 8va for the octave · wiggle over a ringing string to wobble · Alt + mouse up or down bends",
		"hands": "brush the strings with a fingertip, or pinch and sweep · 8va on the crown · tilt to bend · shake to wobble",
	},
	{
		"id": &"bells", "title": "HANDBELLS", "area": LIVE, "zone": &"", "air": 0.5,
		"spot": &"bell_stand_spot", "at": Vector3(0, 0.85, 0),
		"frame": [Vector3(0, 1.0, 0), Vector3(0, 0.41, 0.13)],
		"foot": Vector2(0.27, 0.12), "foot_z": 0.0, "top": 0.8,
		"desk": "click a bell to pick it up · swing the mouse or click to ring its chord tone",
		"hands": "pick a bell up and swing it · bells 1 to 4 ring the chord's root, third, fifth, top",
	},
	{
		"id": &"wheel", "title": "FIFTHS WHEEL", "area": LIVE, "zone": &"bricks", "air": 0.5,
		"spot": &"wheel_spot", "at": Vector3(0, 0.45, -0.2),
		"frame": [Vector3(0, 0.77, -0.35), Vector3(0, -0.29, 0.06)],
		"desk": "click a chord to hear it · drag round the hub or wheel for the key · SET writes it · drag a strip tile off the board for a chord brick, MAKE BRICKS for the strip",
		"hands": "press a chord · twist the hub for the key · SET writes them into the song · pull a strip tile out toward you for a chord brick",
	},
	{
		"id": &"sections", "title": "SECTION BLOCKS", "area": LIVE, "zone": &"bricks", "air": 0.3,
		"spot": &"sections_spot", "at": Vector3(0, 0.04, SectionBlocks.ROW_Z),
		"frame": [Vector3(0, SectionBlocks.PLAQUE_TOP, SectionBlocks.PLAQUE_Z),
				Vector3(0, 0, SectionBlocks.ROW_Z + SectionBlocks.DEPTH * 0.5)],
		"desk": "drag a section along the row to move it, the others make room · [ and ] move the one under the cursor a place · let go and the song is rearranged, one undo step · no sections yet: MAKE SECTIONS FROM MARKERS",
		"hands": "lift a section and set it down elsewhere in the row · the others make room · let go to rearrange the song · the stick moves it a place",
	},
	{
		"id": &"ledge", "title": "CHORD LEDGE", "area": LIVE, "zone": &"bricks", "air": 0.3,
		# Close up to the near edge it runs along, its letters a brick's face, and back just far
		# enough that CLEAR at its left end and the BIN at its right are both in a desk's view.
		"seat": 0.85, "spot": &"ledge_spot", "at": Vector3(0, 0.04, ChordLedge.SLOT_Z),
		"frame": [Vector3(0, 0.08, ChordLedge.SLOT_Z),
				Vector3(0, -0.32, ChordLedge.PLAQUE_Z)],
		"desk": "MAKE BRICKS on the wheel stands the strip here as chord bricks · wheel over one for 1, 2 or 4 bars · take one and click a lane, a strip or a section block: the whole row is written · click the rail to stand a brick, BIN or CLEAR to bin",
		"hands": "stand chord bricks in a row: it is the progression · take one and turn it in your hand, or the stick over one, for 1, 2 or 4 bars · aimed back at its slot it goes back in its place · press one into a lane, a strip or a section block to write the row",
	},
	{
		"id": &"stage_table", "title": "STAGE TABLE", "area": CONTROL, "zone": &"", "air": 0.5,
		"spot": &"stage_table_spot", "at": Vector3(0, 0.74, 0.05),
		"frame": [Vector3(0, 0.80, -0.47), Vector3(0, 0.30, 0.585)],
		"seat": 0.95, "surface": &"stage_table",
		"desk": "drag a track's ball, or its tag's name: across is pan, back is quieter · wheel 0.5 dB, Shift 0.1 · its ring, or the wheel while held, is width · drag the stalk under it up for more of the room (ROOM makes one) · drag from the knot under a ball to another: a sidechain rope, pull its middle to duck harder, X cuts · double-click or Backspace resets · < > banks, SHOW · L held leans in",
		"hands": "take a track's ball, or its tag's name, and stand it where it should sound: across is pan, back is quieter · its ring is width, its stalk the room · pull a rope from the knot under it to another to duck that one, harder the more you pull, the X by the knot cuts it · press it twice to reset · lean in to hear it",
	},
	{
		"id": &"cassette_rack", "title": "CASSETTE RACK", "area": LIVE, "zone": &"", "air": 0.5,
		"spot": &"cassette_rack_spot", "at": Vector3(0, 1.15, 0),
		"frame": [Vector3(0, 1.5, 0), Vector3(0, 0.05, 0.1)],
		"foot": CassetteRack.FOOT, "foot_z": 0.0, "top": CassetteRack.TOP,
		"desk": "drag a clip off the timeline's edge: a cassette of it in your hand · carried, hold L to hear it, click a slot to shelve it, the BIN to bin it, a bandmate to hand it over · click a racked one to take it",
		"hands": "pull a clip out of the timeline toward you · hold it to your ear to hear it · let it go by a slot to shelve it, in the BIN to bin it · hold it by a bandmate's glove to hand it over",
	},
	{
		"id": &"sampler", "title": "SAMPLER", "area": LIVE, "zone": &"", "air": 0.5,
		"spot": &"sampler_spot", "at": Vector3(0, 1.0, 0),
		"frame": [Vector3(0, 1.33, 0), Vector3(0, 0.3, 0.13)],
		"foot": Sampler.FOOT, "foot_z": 0.0, "top": Sampler.TOP,
		"desk": "click REC, then squeeze, click or shake something you carry, do a yo-yo or card trick, or throw the ball to bounce, or use anything within 1.5 m of its mic: one sample, a WAV and a cassette on the rack · click REC again to stop",
		"hands": "press REC, then squeeze, hit or shake something in your hand, do a yo-yo or card trick, or bounce the ball, or near the mic · that one sound is a cassette on the rack · press REC again to stop",
	},
	{
		"id": &"platter", "title": "PLATTER", "area": CONTROL, "zone": &"", "air": 0.4,
		"spot": &"platter_spot", "at": Platter.AXIS + Vector3(0, Platter.DISC_TOP, 0),
		"frame": [Vector3(0.13, 0.1, -0.12), Vector3(0, -0.33, 0.21)],
		"seat": 0.6, "cart": &"deck_trolley",
		"desk": "drag round it to scrub the song, a turn a bar · hold still to stop, let go to play on · flick it back fast and let go to spin back · wheel a beat · click a cassette into its slot, then drag to scratch it, in your ears alone",
		"hands": "take hold of the record and turn it to scrub, a turn a bar · hold it still to stop · flick it back and let go to spin back · stand a cassette in its slot and turn to scratch it, in your ears alone",
	},
	{
		"id": &"eq_wall", "title": "EQ WALL", "area": CONTROL, "zone": &"", "air": 0.5,
		"spot": &"eq_wall_spot", "at": Vector3(0, 1.15, 0),
		"frame": [Vector3(0, EqWall.BOTTOM + EqWall.TALL + 0.06, 0), Vector3(0, EqWall.BOTTOM, 0.05)],
		"seat": 1.9, "surface": &"eq_wall",
		"desk": "F walks to it, G brings it · each track's shape is its level in each band, 20 Hz at the floor to 20 kHz at the top · a glow is a clash: two tracks both above -30 dB and within 6 dB · hover a glow or a name in the key for its card · drag a glow's side down, or wheel over it, to cut that track there, an EQ at its chain's end · SHOW: all, the soloed or the worst clash · a host on the built-in engine",
		"hands": "frequency up its height, lows at the floor · each track's shape is its level in each band · where two glow they clash: point at a glow for its card · grab a glow on a track's side and push it into the wall to cut that track there · press SHOW for all, the soloed or the worst clash",
	},
	{
		# LEVELS (slice 66): a wall of every track's level and the master's loudness, set into a niche
		# in the control room's front wall left of the timeline (Venue.levels_niche_spot).
		"id": &"levels", "title": "LEVELS", "area": CONTROL, "zone": &"", "air": 0.5,
		"spot": &"levels_spot", "at": Vector3(0, 1.4, 0),
		"frame": [Vector3(0, (LevelsWall.BOTTOM + LevelsWall.TALL + 0.08) * LevelsWall.FACE, 0), Vector3(0, LevelsWall.BOTTOM * LevelsWall.FACE, 0.05)],
		"seat": 2.8, "surface": &"levels",
		"desk": "F walks to it, G brings it · a column a track, its peak after the fader against lines at -18, -6 and 0 dBFS, the held peak over it · a blue bar down from the top is a compressor's gain reduction · drag a column up or down for that track's gain, wheel 0.5 dB (Shift 0.1) · drag or wheel the names to scroll · the master: short-term and integrated LUFS against the TARGET (press it: streaming -14, club -8, broadcast -23, custom; wheel it for custom), true peak and phase · RESET starts the integrated again",
		"hands": "a column a track against lines at -18, -6 and 0 dBFS · blue from the top is gain reduction · take hold of a column and raise or lower it for that track's gain · the master's loudness against the TARGET, its true peak and its phase · press TARGET for the next, RESET to start the loudness again",
	},
	{
		# The sampling station's TV (docs/sampling_station.md): YouTube on the control room's front
		# wall right of the timeline (Venue.tv_mount_spot).
		"id": &"tv", "title": "SAMPLING STATION", "area": CONTROL, "zone": &"", "air": 0.5,
		"spot": &"tv_spot", "at": Vector3(0, (TvSurface.TOP + TvSurface.FOOT) * 0.5, 0),
		"frame": [Vector3(0, TvSurface.TOP + 0.04, 0), Vector3(0, TvSurface.FOOT, 0.05)],
		"seat": 2.2, "surface": &"tv",
		"desk": "F walks to it, G brings it · FIND: type a search or paste a YouTube link, then PLAY, ◀ and ▶ · SAMPLE at the start of what to take and again at its end · CHOP: by its hits, or 16, 8 or 4 equal slices · click a pad to play its slice, through the armed track, recorded as a note while the song records · SCALE spreads the last pad across all sixteen in the song's key; KEY and MODE step it",
		"hands": "YouTube over sixteen pads · PLAY, ◀ and ▶ the video · SAMPLE at the start and the end of what to take · CHOP cuts it · strike a pad for its slice · SCALE spreads one pad across all sixteen in a key; KEY and MODE step it",
	},
	{
		# The circle of hand drums on the drum riser (HandDrum, slice 40): the ring's middle, its front
		# toward the desk, the drums round it items of the room, the plaque low between the front two.
		"id": &"drums", "title": "HAND DRUMS", "area": LIVE, "zone": &"drums", "air": 0.5,
		"spot": &"drum_circle_spot", "at": Vector3(0, 0.62 + HandDrum.STAND, 0),
		"frame": [Vector3(0, 0.8 + HandDrum.STAND, -0.51), Vector3(0, DRUM_PLAQUE.y - 0.15, DRUM_PLAQUE.z)],
		"desk": "click a drum's head: the centre is bass, the rim slap, between the tone · Shift-click softly · the cajón's face: its middle bass, its top corners slap · click a drum's jack to plug it into a track",
		"hands": "strike the head: centre bass, rim slap · controllers are steadier for fast parts",
	},
	{
		# The looper (Looper, slice 45): a pad on a stand at the drum riser's front corner, played from
		# the floor in front of it, its screen and LENGTH key behind the pad, its plaque on an arm
		# off the pole, in front of the case and below it. Its layers are rings on a post over it, and
		# a LAYERS list over the screen (LooperRings, slice 46). Its frame's top is the last ring the
		# post could stand (LooperRings.STACK_TOP), so a desk sees the whole stack turn, shine and go
		# dashed with the plaque's foot under it: so its seat stands 1.7 m back, further than SEAT.
		"id": &"looper", "title": "LOOPER", "area": LIVE, "zone": &"drums", "air": 0.3,
		"seat": 1.7, "spot": &"looper_spot", "at": Vector3(0, Looper.PAD_Y, 0.03),
		"frame": [Vector3(0, LooperRings.STACK_TOP, LooperRings.POST.z), Looper.PLAQUE_FOOT],
		"reach": 0.5,
		"desk": "click the pad to loop: a bar's count, then everything you play (keys, hits) for LENGTH bars is a layer on a track of your own · click LENGTH for 1, 2, 4 or 8 · the first sets the loop · click again while it loops to stack a layer · one player at a time · each layer is a ring on the post: click it to mute, again to unmute · the LAYERS list has MUTE and X (delete) for each",
		"hands": "slap the pad: a bar's count, then everything you play for LENGTH bars is a layer · slap again while it loops to stack another · one player at a time · each layer is a ring: grab to mute, again to unmute, pull away to delete",
	},
	{
		# The music box (MusicBox, slice 47): a brass cylinder on a case on a plinth of its own, standing
		# on the floor by itself beside the harp, so a trolley in a studio. Its frame's top is the
		# plaque's top on the open lid, its foot the front edge of its keys on the deck.
		"id": &"music_box", "title": "MUSIC BOX", "area": LIVE, "zone": &"", "air": 0.5,
		"spot": &"music_box_spot", "at": MusicBox.AXIS + Vector3(0, -0.05, 0.1),
		"frame": [MusicBox.FRAME_TOP, MusicBox.FRAME_FOOT],
		"foot": MusicBox.FOOT, "foot_z": MusicBox.FOOT_Z, "top": MusicBox.TOP,
		"desk": "click a cell on the cylinder for a peg, a peg to take it out · drag along a row for a run, one undo step · the wheel over it, or dragging the knurled wheel at its right end, turns it round · TRACK, LENGTH, ROOT and SCALE in front: click for the next, the wheel either way · it plays its track's MIDI item as the song plays",
		"hands": "a fingertip on a cell for a peg, on a peg to take it out · along a row for a run · roll the wheel at its right end, or the stick, to turn it round · a key steps on",
	},
	{
		# The string spool (RoomString.Spool, slice 48): a bobbin of string on a stand of its own, standing
		# on the floor by itself in the aisle between the drum riser and the lattice (at the lattice's
		# front corner in the loft; Venue.default_string_spool_spot), so a trolley in a studio. Its
		# frame's top is the reel's top, its foot its plaque's on the post, opened.
		"id": &"strings", "title": "STRING SPOOL", "area": LIVE, "zone": &"", "air": 0.5,
		"spot": &"string_spool_spot", "at": RoomString.SPOOL_AXLE + Vector3(0, -0.15, 0),
		"frame": [RoomString.SPOOL_FRAME_TOP, RoomString.SPOOL_FRAME_FOOT],
		"foot": RoomString.SPOOL_FOOT, "foot_z": RoomString.SPOOL_FOOT_Z, "top": RoomString.SPOOL_TOP,
		"desk": "click the spool for an end · click where it goes, then where it ends: anything the cursor meets, across the room for a bass, a hand's width for a high note · click a string to pluck · wiggle to wobble · Alt + mouse up or down bends · drag it hard off its line, or click a knot, to cut",
		"hands": "press the spool for an end · press where it goes, carry it, let go where it ends · its length is its note · brush it to pluck · tilt to bend · pull it hard to cut",
	},
	{
		# The marble run (MarbleRun, slice 49): mounted in the lattice zone, its tray at the cube's face
		# toward the desk, looked past into the lattice. Its frame's top is just over the tray's board,
		# its foot its plaque's keys under the board, folded, so a seat brought in close (studio:2's
		# glass) still holds both.
		"id": &"marbles", "title": "MARBLE RUN", "area": LIVE, "zone": &"matrix", "air": 0.5,
		"spot": &"marbles_spot", "at": MarbleRun.LOOK,
		"frame": [MarbleRun.FRAME_TOP, MarbleRun.FRAME_FOOT],
		"desk": "click a block on the tray (RAMP DROP SPLITTER BELL), then click cells: on the lattice's floor, or a block's face for the cell beside it · Shift + wheel raises the layer, the wheel turns it · click a placed block to move it, Backspace takes it out, Esc puts it back · a marble rolls from the top block each bar, BALL for one now · each bell rings its height's note · its jack records them",
		"hands": "take a block from the tray and let it go in a cell · the stick turns it · pull one out of the lattice to take it out · a marble rolls from the top block each bar · each bell rings its height's note",
	},
	{
		# The theremin (Theremin, slice 50): free-standing in front of the drum riser's outer end, facing
		# the desk, its player between it and the control room, so a trolley in a studio. Its `air` is a
		# metre round where its hands play (`air_at`), toward it and either side. Its frame's top is the
		# pitch rod's tip, its foot its plaque's under the cabinet, opened.
		"id": &"theremin", "title": "THEREMIN", "area": LIVE, "zone": &"", "air": 1.0,
		"spot": &"theremin_spot", "at": Theremin.LOOK, "air_at": Theremin.AIR_AT,
		"frame": [Theremin.FRAME_TOP, Theremin.FRAME_FOOT],
		"foot": Theremin.FOOT, "foot_z": Theremin.FOOT_Z, "top": Theremin.TOP,
		"desk": "rest the cursor on the lettered rule out from the tall rod: across is pitch, nearer the rod higher · the wheel over it is volume, up from silent · hold the button to play it full · SCALE on its front: free, the key's scale or the chord · wiggle to wobble · Alt + mouse up or down bends",
		"hands": "one hand near the tall rod is the pitch, nearer is higher · the other over the loop is the volume, silent down on it · the lit ring is your note · tilt to bend · shake to wobble",
	},
	{
		# The grain cloud (GrainCloud, slice 54): free-standing in the aisle between the drum riser and
		# the lattice, behind the string spool, its back to the lattice, so a trolley in a studio. Its
		# `air` is round the cloud's middle (`air_at`), where the hands play, toward it and either side.
		# Its frame's top is the cloud's top, its foot its plaque's on the plinth's side toward the
		# desk, opened.
		"id": &"grains", "title": "GRAIN CLOUD", "area": LIVE, "zone": &"", "air": GrainCloud.AIR,
		"spot": &"grains_spot", "at": GrainCloud.LOOK, "air_at": GrainCloud.AIR_AT,
		"frame": [GrainCloud.FRAME_TOP, GrainCloud.FRAME_FOOT],
		"foot": GrainCloud.FOOT, "foot_z": GrainCloud.FOOT_Z, "top": GrainCloud.TOP,
		"desk": "click the bowl with a cassette in your hand (a sample, or any clip pulled off the timeline) and the cloud is its sound · hold the button on the cloud to play grains from there: across is where in the sound, up is longer grains · the wheel widens the spray, Shift + wheel is more grains a second · KEY on its front follows the chord's root · the band hears it · while the song records, your grains go onto the armed track as audio",
		"hands": "let a cassette go over the bowl · reach into the cloud: across is where in the sound, up is longer grains, further in is more of them · spread your fingers, or squeeze the grip, to widen the spray · KEY follows the chord's root · the band hears it · while the song records, your grains go onto the armed track as audio",
	},
	{
		# The modular wall (ModularWall, slice 51): its help lines say where the world's sockets are
		# (WorldSocket, slice 53), since they are out in the room and not on it. A surface hung on the synth zone's module rack over
		# the keyboard stand, its touch keys on the stand's upper deck under it and its plaque beside
		# it. Mounted in the zone, not a trolley. Its frame's top is the case's top, its foot the touch
		# keys' near edge; its seat as far back as the bricks table behind it lets, and a headset's
		# (`reach`) at the decks' front, the panel in arm's reach over them.
		"id": &"modular", "title": "MODULAR", "area": LIVE, "zone": &"synth", "air": 0.5,
		"spot": &"modular_spot", "at": ModularWall.LOOK,
		"frame": [ModularWall.FRAME_TOP, ModularWall.FRAME_FOOT],
		"seat": 1.3, "reach": 0.8, "surface": &"modular",
		"desk": "F walks to it, G brings it · drag from a jack to another to patch a cable: an output (pale) into an input · drag a cable's plug out of an input to move it, off the jacks to pull it · drag a knob up or down, or wheel it, to turn it · standing at it your keys play it: the touch keys under it, a MIDI keyboard, or PLAY for A to ' · OUT says which road it sounds on · record at it and the take is its sound, audio named modular · the world plugs in too: click a MODULAR socket (or P over it) by the weather, the venue's instrument, a looper ring or the marble run to step its long cable into the wall's next free input",
		"hands": "pinch a jack and carry the cable to another: an output (pale) into an input · pull a plug out to move it, or let it go off the jacks · twist a knob · standing at it your keys play it, or touch the keys under it · record at it and the take is its sound · press a MODULAR socket by the weather, the venue's instrument, a looper ring or the marble run to patch the world in",
	},
	{
		# The lyric board (LyricBoard, slice 56): in the vocal booth on a stand of its own, across the mic
		# stand's foot from the singer, its lines at eye height over the mic as they look out through the
		# glass. Mounted in the zone, not a trolley: the booth is the venue's. Its seat is at the mic. Its
		# frame's top is the board's top, its foot its plaque's on the post, opened.
		"id": &"lyrics", "title": "LYRIC BOARD", "area": LIVE, "zone": &"vocals", "air": 0.15,
		"spot": &"lyrics_spot", "at": Vector3(0, LyricBoard.EYE + LyricBoard.LINES_UP, 0),
		"frame": [LyricBoard.FRAME_TOP, LyricBoard.FRAME_FOOT],
		"seat": LyricBoard.SEAT,
		"desk": "the song's lyrics at the mic, the line sung now large and marked · M, LYRICS edits them (EDIT opens it) · play the song, click the board, and press Enter or TAP as each untimed line starts",
		"hands": "the line sung now is large and marked · the song playing, press TAP as the next line starts to time it · EDIT types a line onto the end",
	},
	{
		# The Workshop (WorkshopPanel, docs/workshop.md): a panel on the control room's right wall for
		# asking Claude Code for a change from inside the game. A dev tool: its spot is null, so it is
		# no station at all, unless Workshop.enabled (a dev flag, this machine, never a guest).
		"id": &"workshop", "title": "WORKSHOP", "area": CONTROL, "zone": &"", "air": 0.5, "dev": true,
		"spot": &"workshop_spot", "at": Vector3(0, WorkshopPanel.MIDDLE, 0),
		"frame": [WorkshopPanel.FRAME_TOP, WorkshopPanel.FRAME_FOOT], "seat": 1.2, "reach": 0.6,
		"desk": "F9 from anywhere, or ASK: type a change you want, Enter sends it to Claude Code with what you were just doing · it edits the repo, checks it, and the game reloads back here · UNDO LAST takes it back · FIX asks it to fix failed checks · SHOT and CONTEXT say what is sent · dev only, this machine",
		"hands": "ASK opens a typing pad: OK sends it to Claude Code with what you were just doing · the game reloads back here when it is done · UNDO LAST takes it back · dev only, this machine",
	},
	{
		# The venue's own instrument (VenueInstrument, slice 42): what it is, where and how it is played
		# are the venue's (`row_in`); these are for a card with no venue to ask.
		"id": &"venue", "title": "THE VENUE'S INSTRUMENT", "area": VENUE, "zone": &"", "air": 0.5,
		"spot": &"instrument_spot", "mounted": true, "at": Vector3(0, 1.3, 0),
		"frame": [Vector3(0, 1.9, 0), Vector3(0, 0.95, 0.1)],
		"desk": "click a bar, a tube or a crystal to strike it, Shift-click softly · hold the button and drag across them to brush them · each a note of the song's scale",
		"hands": "strike it with a fingertip or a controller · brush across to ring several · each a note of the song's scale",
	},
	{
		# The venue's weather (Weather, slice 44): its switch on a window's sill, or on a post by the
		# cave's pools. What it is is the venue's (`row_in`); these are for a card with no venue to ask.
		"id": &"weather", "title": "THE WEATHER", "area": VENUE, "zone": &"", "air": 0.4,
		"spot": &"weather_spot", "mounted": true, "at": Vector3(0, 0.95, 0),
		"frame": [Vector3(0, 1.05, 0), Vector3(0, 0.5, 0.02)],
		"desk": "click the switch: LISTEN plays each drop as a note of the song's scale, OFF silences them · click its jack to record them onto a track",
		"hands": "press the switch: LISTEN, each drop a note of the song's scale · OFF, silent · its jack into a track records them",
	},
]
## Where the hand drums' plaque stands in the ring's frame (Venue.drum_ring), between the front two
## drums and low, leant back like a lectern's (DRUM_PLAQUE_TILT, radians) so it reads from above and
## is under the line from the desk's seat to the drums behind it; and how wide it is, to fit between
## the front two.
const DRUM_PLAQUE := Vector3(0, 0.28 + HandDrum.STAND, 0.6)
const DRUM_PLAQUE_TILT := 0.7
const DRUM_PLAQUE_WIDTH := 0.56

const HELD := [
	{
		"id": &"keytar", "title": "KEYTAR", "area": HELD_AREA,
		"desk": "click it on the shelf to take it · A to ' play · Z X octave · arrows walk · wiggle the mouse to wobble · Alt + mouse up or down bends",
		"hands": "take it by the neck · play it from a MIDI keyboard or the computer's keys · tilt the neck hand to bend · shake to wobble",
	},
	{
		"id": &"shaker", "title": "SHAKER", "area": HELD_AREA,
		"desk": "click it on the shelf to pick it up · shake it with the mouse · click strikes · P jack · hits snap gently to the beat (session panel)",
		"hands": "close your hand round it and shake · each stroke that stops is a hit · a pinch carries it too · controllers are steadier for fast parts",
	},
	{
		"id": &"tambourine", "title": "TAMBOURINE", "area": HELD_AREA,
		"desk": "click it on the shelf to pick it up · shake it with the mouse · click strikes · P jack · hits snap gently to the beat (session panel)",
		"hands": "close your hand round the bare hoop and shake · the trigger strikes it · controllers are steadier for fast parts",
	},
	{
		"id": &"bells_held", "title": "A HANDBELL", "area": HELD_AREA,
		"desk": "carried: swing the mouse or click to ring · 1 to 3 pocket it · Q puts it down",
		"hands": "carried: swing it down to ring · its tab says the note it rings now",
	},
	{
		"id": &"fingertips", "title": "FINGERTIPS", "area": HELD_AREA,
		"desk": "T, then J K L ; play the chord's root, third, fifth and top · T or Esc gives them back · wiggle the mouse to wobble · Alt + mouse up or down bends",
		"hands": "hold an empty hand open, palm up, to turn them on · thumb to each fingertip plays · tilt to bend · shake to wobble",
	},
	{
		"id": &"chord_hand", "title": "CHORD SHAPES", "area": HELD_AREA,
		"desk": "C turns the chord layer on · 1 to 7 pick the key's I to vii° for the harp, the fingertips and a bell you carry · Shift adds the seventh · 0 the song's own · a click still strums · C or Esc ends it",
		"hands": "hold your chord hand up (the left, or the right if left-handed), palm out: fingers up count I to IV, the thumb too V · palm up, one or two: vi, vii° · open flat or lowered: the song's · controller: click the stick, then push it toward a chord, up is I",
	},
	{
		"id": &"clap", "title": "CLAP TO MUTE", "area": HELD_AREA,
		"desk": "K held over a track (a stage voice, a strip, a lane, a rack) mutes it while held · a tap latches it, another unlatches",
		"hands": "palms pressed together, pointing at a track, mute it until they part · a quick clap latches it · controllers: grips together",
	},
	{
		"id": &"lean", "title": "LEAN IN", "area": HELD_AREA,
		"desk": "L held over a stage voice: that track 6 dB up in your ears alone, the mix 6 dB down · a host on the built-in engine",
		"hands": "lean your head within 25 cm of a stage voice to hear it up close · a host on the built-in engine",
	},
	{
		"id": &"cassette", "title": "A CASSETTE", "area": HELD_AREA,
		"desk": "drag a clip off the timeline's edge for one · hold L to hear it · click a timeline lane, a strip or a stage voice to paste it · click a bandmate to hand it over · click a rack slot to shelve it · Q puts it down · 1 to 3 pocket it",
		"hands": "pull a clip out of the timeline toward you · hold it to your ear to hear it · push it into a timeline lane, a strip or a stage voice to paste it · hold it by a bandmate's glove for half a second to hand it over · throw it to them · let it go by a rack slot to shelve it",
	},
	{
		"id": &"chord_brick", "title": "A CHORD BRICK", "area": HELD_AREA,
		"desk": "drag a strip tile off the fifths wheel for one · click a timeline lane, a strip or a stage voice to write its chords there · click a section block for its harmony · from the ledge, its whole row · Q puts it down",
		"hands": "pull a tile out of the wheel's strip toward you · turn it in your hand for 1, 2 or 4 bars · push it into a lane, a strip or a stage voice to write its chords · into a section block for that section's harmony · taken from the ledge, the whole row",
	},
	{
		"id": &"miniature", "title": "MINIATURE", "area": HELD_AREA,
		"desk": "the session to hold, on the side table by the seat: click a track to play from there and bring the console · an item to select it on the timeline · a pin to walk to its station · its front edge to carry it · the table itself to push it anywhere",
		"hands": "point at it or touch it with a fingertip: the card names the track and time · press to play from there and bring the console · an item brings the timeline · a pin travels to its station · take it by its front edge",
	},
	{
		# The drum pads (slice 41): the kit on the desk's front rail, and this player's own on real
		# surfaces, marked from the PADS card under the rail. Played anywhere, so held, not stood.
		"id": &"pads", "title": "DRUM PADS", "area": HELD_AREA,
		"desk": "six on the desk's front rail, KICK SNARE HAT CLAP TOM RIM: click one, Shift-click softly, or 4 to 9 from anywhere · they play the drum track · their jack at the rail's left end plugs them elsewhere",
		"hands": "tap a pad on the desk's rail · MARK on the PADS card under it, then touch a desk, a crate or a knee with a fingertip, or a controller's tip with its trigger held, and hold still: a pad there · while marking, tap a pad for its next drum, hold still on it to take it away · the stick over one changes its drum",
	},
	{
		"id": &"jacks", "title": "JACKS", "area": HELD_AREA,
		"desk": "P steps what you carry into a track or a bandmate · Shift-P unplugs",
		"hands": "with the other hand, press the jack on what you carry · press again to step",
	},
]


## The venue this player is in, for the rows that are the venue's own (`row_in`) wherever no venue is
## given: the plaque, the board and the toasts. Set by the studio as it builds one.
static var here: Venue = null


## Where station row `r` is, for a toast: its area's AREA_WHERE ("in this venue"), or "here".
static func where(r: Dictionary) -> String:
	return String(AREA_WHERE.get(r.get("area", &""), "here"))


## The row with this id, from ALL or HELD, as it is in the venue this player is in (`here`); empty if
## there is none.
static func row(id: StringName) -> Dictionary:
	return row_in(here if here != null and is_instance_valid(here) else null, id)


## The row with this id as it is in `venue`: a mounted row (the venue's own instrument, its weather)
## with the venue's title, help lines, look point and frame over its own (VenueInstrument.row_for,
## Weather.row_for). Empty if there is none.
static func row_in(venue: Venue, id: StringName) -> Dictionary:
	for r: Dictionary in ALL + HELD:
		if r["id"] == id:
			if r.get("mounted", false) and venue != null:
				var own := Weather.row_for(Weather.spec_of(venue)) if id == Weather.STATION \
						else VenueInstrument.row_for(VenueInstrument.spec_of(venue))
				if not own.is_empty():
					var out := r.duplicate()
					out.merge(own, true)
					return out
			return r
	return {}


## Where station `id` stands in `venue`, in the venue's frame, its front toward +Z; null where
## the venue has no room for it (the Rig Roulette room has no bricks table) or there is no venue.
static func spot(venue: Venue, id: StringName) -> Variant:
	var r := row(id)
	if venue == null or r.is_empty() or not r.has("spot") or not venue.has_method(r["spot"]):
		return null
	var at: Variant = venue.call(r["spot"])
	return at if at is Transform3D else null


## What a player at station `id` looks at, in the venue's frame; null where it does not stand.
static func look_point(venue: Venue, id: StringName) -> Variant:
	var at: Variant = spot(venue, id)
	if at == null:
		return null
	return (at as Transform3D) * (row_in(venue, id)["at"] as Vector3)


## How far inside the edge of the view a station's frame is held (degrees): its foot just inside
## the bottom, its top further in from the top, clear of the HUD's line and the toast under it
## (about 6 degrees of a 58-degree lens), which says how to play what you have just walked to.
const FRAME_MARGIN := 3.0
const FRAME_TOP := 8.0


## Where a player whose eye is at `eye` (the venue's frame) looks to play station `id`, with a
## view `fov` degrees tall: toward its look point, tipped up or down only as far as it takes to
## hold its `frame`'s top and foot inside the view (FRAME_TOP and FRAME_MARGIN in from its edges). Where both do not fit (a seat the room has
## brought in close: the harp's, with the bricks table in front of it) the top wins, because that
## is where its controls are: the harp's chord readout and its 8va buttons are on its crown, and
## its plaque is for a headset, which reads it close up. The point is as far off, along the
## floor, as the look point. Null where the station does not stand.
static func look_from(venue: Venue, id: StringName, eye: Vector3, fov: float) -> Variant:
	var at: Variant = look_point(venue, id)
	if at == null:
		return null
	var look := at as Vector3
	var ahead := Vector3(look.x - eye.x, 0.0, look.z - eye.z)
	var along := ahead.length()
	if along < 0.001:
		return look
	ahead /= along
	var pitch := atan2(look.y - eye.y, along)
	var points: Array = row_in(venue, id).get("frame", [])
	if points.size() == 2:
		var frame := spot(venue, id) as Transform3D
		var tip := func(p: Vector3) -> float:
			var q := frame * p
			return atan2(q.y - eye.y, maxf(0.05, (q - eye).dot(ahead)))
		var lowest: float = tip.call(points[0]) - deg_to_rad(fov * 0.5 - FRAME_TOP)
		var highest: float = tip.call(points[1]) + deg_to_rad(fov * 0.5 - FRAME_MARGIN)
		pitch = clampf(pitch, lowest, highest) if lowest <= highest else lowest
	return eye + ahead * along + Vector3.UP * along * tan(clampf(pitch, -1.4, 1.4))


## Where a player stands to play station `id`, in the venue's frame: on the floor SEAT in front
## of it (or its row's own `seat`), facing it (the transform's -Z toward its look point), and level,
## on whatever is there to stand on (Venue.floor_at: the drum riser's top at the hand drums, so a
## headset's play space is put down where its real floor is the riser it sees). `fits` (a Vector2 on
## the floor -> bool, the walker's own) says where a person may stand; given, the seat comes in
## along the station's front toward NEAREST until it fits, then tries either side, and is the
## plain SEAT in front only when nothing fits. `hands` is a headset's seat: a row that is played
## only by hand within arm's length (the venue's own set) says how near that is, its `reach`, where
## a desk's seat stands back far enough to hold the whole of it in view. Null where the station does
## not stand.
static func seat(venue: Venue, id: StringName, fits := Callable(), hands := false) -> Variant:
	var at: Variant = spot(venue, id)
	if at == null:
		return null
	var frame := at as Transform3D
	var look: Vector3 = look_point(venue, id)
	var r := row_in(venue, id)
	var far: float = r.get("reach", r.get("seat", SEAT)) if hands else r.get("seat", SEAT)
	var chosen := frame * Vector3(0, 0, far)
	if fits.is_valid():
		var found := false
		for side in [0.0, 0.15, -0.15, 0.3, -0.3, 0.45, -0.45]:
			var d := far
			while d >= NEAREST - 0.001 and not found:
				var p := frame * Vector3(side, 0, d)
				if fits.call(Vector2(p.x, p.z)):
					chosen = p
					found = true
				d -= 0.05
			if found:
				break
	chosen.y = venue.floor_at(Vector2(chosen.x, chosen.z))
	var toward := Vector3(look.x - chosen.x, 0.0, look.z - chosen.z)
	if toward.length() < 0.001:
		toward = -frame.basis.z
	return Transform3D(Basis.looking_at(toward.normalized(), Vector3.UP), chosen)


## The ids of the stations that stand in `venue`, in list order.
static func ids(venue: Venue) -> Array[StringName]:
	var out: Array[StringName] = []
	for r: Dictionary in ALL:
		if spot(venue, r["id"]) != null:
			out.append(r["id"])
	return out


## {area: [row, ...]} of the stations that stand in `venue`, every area in AREAS present (an
## area with none has an empty list). With no venue, every row, as a card with no studio shows.
static func by_area(venue: Venue) -> Dictionary:
	var out := {}
	for area in AREAS:
		out[area] = []
	var stood: Array[StringName] = ids(venue)
	for r: Dictionary in ALL:
		if venue != null and not stood.has(r["id"]):
			continue
		# A dev tool is no station at all where it is off, card or no card (Workshop.enabled).
		if r.get("dev", false) and not Workshop.enabled():
			continue
		(out[r["area"]] as Array).append(row_in(venue, r["id"]))
	return out


## Whether station `id` is mounted in a zone (checked inside it) rather than free-standing.
static func zoned(id: StringName) -> bool:
	return row(id).get("zone", &"") != &""


## A free-standing station's walker solid at `venue`'s spot for it ({c, h, a, top}); empty for a
## zone-mounted one, which the zone's own solids carry, or one that does not stand there.
static func solid(venue: Venue, id: StringName) -> Dictionary:
	var r := row(id)
	var at: Variant = spot(venue, id)
	if at == null or not r.has("foot"):
		return {}
	var frame := at as Transform3D
	var middle := frame * Vector3(0, 0, r["foot_z"])
	return {"c": Vector2(middle.x, middle.z), "h": r["foot"], "a": frame.basis.get_euler().y, "top": r["top"]}


## A station's plaque: its title and its hands line, lettered at PLAQUE_CAP on a dark plate
## `width` wide, facing +Z (out of the station's front), for a headset player to read what it is
## and how hands play it; and under them its two keys (StationBoard.PlaqueKey, slice 11),
## INSTRUMENTS, the station board's rows beside the plaque, and BACK, home to the desk, so a
## player who has travelled here has the way on and the way back where they are looking. The
## lettering's middle is the node's origin; the keys' row hangs PLAQUE_KEYS_ROW below it. Named
## "Plaque", its keys "Instruments" and "Back".
static func plaque(id: StringName, width := PLAQUE_WIDTH) -> Node3D:
	var r := row(id)
	var holder := Node3D.new()
	holder.name = "Plaque"
	var lines := _plaque_lines(r.get("hands", ""), width - 0.04)
	var tall := PLAQUE_CAP * 1.6 + lines * PLAQUE_CAP * 1.45 + 0.03
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	var box := BoxMesh.new()
	box.size = Vector3(width, tall + PLAQUE_KEYS_ROW, 0.008)
	plate.mesh = box
	plate.position = Vector3(0, -PLAQUE_KEYS_ROW * 0.5, -0.004)
	var ink := StandardMaterial3D.new()
	ink.albedo_color = Color(0.07, 0.065, 0.06)
	ink.roughness = 0.6
	plate.material_override = ink
	holder.add_child(plate)
	var top := tall * 0.5 - 0.015
	var title := _plaque_label(r.get("title", String(id)), Color(0.95, 0.9, 0.78))
	title.name = "Title"
	title.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	title.position = Vector3(0, top, 0.001)
	holder.add_child(title)
	var hands := _plaque_label(r.get("hands", ""), Color(0.86, 0.84, 0.8))
	hands.name = "Hands"
	hands.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	hands.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hands.width = (width - 0.04) / hands.pixel_size
	hands.position = Vector3(0, top - PLAQUE_CAP * 1.6, 0.001)
	holder.add_child(hands)
	var wide := minf(PLAQUE_KEY_WIDE, (width - 0.06) * 0.5)
	for kind in [StationBoard.PlaqueKey.INSTRUMENTS, StationBoard.PlaqueKey.BACK]:
		var key := StationBoard.PlaqueKey.new()
		key.name = "Instruments" if kind == StationBoard.PlaqueKey.INSTRUMENTS else "Back"
		key.station = id
		key.kind = kind
		key.size = Vector2(wide, PLAQUE_KEY)
		var side := -1.0 if kind == StationBoard.PlaqueKey.INSTRUMENTS else 1.0
		key.position = Vector3(side * (wide * 0.5 + 0.01), -tall * 0.5 - PLAQUE_KEYS_ROW * 0.5 + 0.005, 0.0)
		holder.add_child(key)
	# The title row is the key that opens and closes the how-to-play lines under it.
	var fold := StationBoard.PlaqueFold.new()
	fold.name = "Fold"
	fold.station = id
	# The whole of the folded plate above the keys, so it is as big to aim at as it looks.
	fold.size = Vector2(width, PLAQUE_CAP * 1.6 + 0.03)
	fold.position = Vector3(0, tall * 0.5 - (PLAQUE_CAP * 1.6 + 0.03) * 0.5, 0.0)
	holder.add_child(fold)
	holder.set_meta(&"plaque_tall", tall)
	fold_plaque(holder, false)
	return holder


## Whether `holder`'s how-to-play lines are showing.
static func plaque_open(holder: Node3D) -> bool:
	return bool(holder.get_meta(&"plaque_open", false))


## A plaque opened to its how-to-play lines, or folded to its title and keys (how every plaque
## starts: the lines are for the first time at a station, not every time). The top edge stays where
## it is and the plate grows down from it, so a folded plaque does not hang in mid-air.
static func fold_plaque(holder: Node3D, open: bool) -> void:
	holder.set_meta(&"plaque_open", open)
	var r := row(StringName(holder.get_node("Fold").get("station"))) if holder.has_node("Fold") else {}
	var tall: float = holder.get_meta(&"plaque_tall", 0.2)
	var shown := tall if open else PLAQUE_CAP * 1.6 + 0.03
	var plate := holder.get_node_or_null("Plate") as MeshInstance3D
	if plate != null:
		(plate.mesh as BoxMesh).size.y = shown + PLAQUE_KEYS_ROW
		plate.position.y = tall * 0.5 - (shown + PLAQUE_KEYS_ROW) * 0.5
	var hands := holder.get_node_or_null("Hands") as Node3D
	if hands != null:
		hands.visible = open
	var title := holder.get_node_or_null("Title") as Label3D
	if title != null:
		title.text = "%s  %s" % [r.get("title", title.text.rstrip(" +–")), "–" if open else "+"]
	for key_name in ["Instruments", "Back"]:
		var key := holder.get_node_or_null(key_name) as Node3D
		if key != null:
			key.position.y = tall * 0.5 - shown - PLAQUE_KEYS_ROW * 0.5 + 0.005


## How far below a plaque's origin its plate's bottom edge is, for `id`'s hands line at `width`:
## the foot of the station's `frame`, where the plaque is its lowest part.
static func plaque_bottom(id: StringName, width := PLAQUE_WIDTH) -> float:
	var lines := _plaque_lines(row(id).get("hands", ""), width - 0.04)
	return (PLAQUE_CAP * 1.6 + lines * PLAQUE_CAP * 1.45 + 0.03) * 0.5 + PLAQUE_KEYS_ROW


static func _plaque_label(text: String, colour: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = 0.00025
	l.font_size = roundi(PLAQUE_CAP / l.pixel_size)
	l.modulate = colour
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.double_sided = false
	Lettering.range_to_legibility(l)
	return l


## How many lines `text` takes at PLAQUE_CAP, wrapped to `width` metres, so the plate fits it.
static func _plaque_lines(text: String, width: float) -> int:
	var f: Font = Lettering.face()
	if f == null:
		f = ThemeDB.fallback_font
	var size := roundi(PLAQUE_CAP / 0.00025)
	var per := width / 0.00025
	var lines := 1
	var run := 0.0
	var space := f.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	for word in text.split(" ", false):
		var w := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if run > 0.0 and run + space + w > per:
			lines += 1
			run = w
		else:
			run += (space if run > 0.0 else 0.0) + w
	return lines
