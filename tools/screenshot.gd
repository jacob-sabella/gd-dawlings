extends Node

## Capture harness: run the real studio in a real window and write frames to PNG.
##
## An autoload so it observes whatever is running rather than being wired into a scene. The
## alternative to this -- reading the scene files and asserting the console probably looks like a
## console -- is not verification of anything. A 3D project in particular cannot be reviewed any
## other way: materials, glow and shadow are the difference between gear and grey boxes, and none
## of the three exist until something renders.
##
##   godot --path . -- --shot /tmp/console.png --shot-frame 30 --quit-after 34
##   godot --path . -- --shot /tmp/wide.png --cam 0.5,-0.3,2.6,0,0.95,0
##
## --cam is yaw,pitch,distance,target_x,target_y,target_z. Framing is a command-line argument
## because a capture nobody can reproduce is not evidence: the numbers that produced a shot
## belong next to the shot.

var _shot_path := ""
var _shot_frame := 24
var _quit_after := -1
var _frames := 0
var _cam: Array = []
## x,z,yaw,pitch[,y]: stand the walker somewhere and look, instead of flying the god camera. `y`
## is the floor you stand on, when it is not the ground: a gallery, a riser.
var _walk: Array = []
var _walk_mirror := 0.0
## `--walk rack[,distance[,sideways[,height]]]`: stand facing the modular rack wall (see ShotArgs).
var _walk_rack_on := false
var _walk_rack: Array = []
## `--carry duck`: that item in the mouse's hand from frame 9, as if it had been picked up.
## `--carry duck:squeeze` holds it squeezed. `--carry headphones:wear` puts them on. For a
## personal kind (`ItemRoom.PERSONAL_KINDS`) this takes a copy of your own, as a real grab would,
## rather than holding the shelf's dispenser.
## `--carry tablet:mix:keys` puts its plugs A and B in those SEND sockets (`track_5`: a strip's);
## `:home` after them puts it back on its shelf. `--carry chips:t2@0.5` does a fidget's
## tricks before trick 2 and stops trick 2 half way. `--carry rcplane:fly:cut@300` flies the radio
## plane and cuts its motor on frame 300; `--carry rcplane:fly@400` takes off on frame 400.
var _carry := ""
## `--signal clip:6,mute:8,trace:8,x` (docs/spatial_loop.md part three): at frame 9 track 6's fader
## to the top so it clips, track 8 muted, X for the signal view, and track 8's "why can't I hear
## this?" begun fourteen frames before the shot (`trace:8:30`, thirty), so it is caught mid-trace.
## `look:6`: at frame 12 look to solo held over track 6 (Studio.look_solo), as U held over it does.
var _signal: PackedStringArray = []
## `--pockets duck,ball,cards`: those items picked up and put in pockets 1, 2 and 3 in turn, from
## frame 9, before anything `--carry` puts in the hand.
var _pockets: PackedStringArray = []
## `--visitor 0.6,-0.4,3.0`: another player, Lin (peer 7), standing there (studio x, z) facing
## that yaw, from frame 5: their ghost, and its keys pack (`--carry tablet:keys_7` plugs into it).
var _visitor: Array = []
## `--point ruler:37.5`: with --visitor, what Lin points at from frame 5, as Presence publishes it
## (`ruler:<seconds>`, `room`, `ghost:1`, or a control's key): their ghost's ray to it, their name at
## its end (docs/spatial_loop.md part two, slice 35). `room` points at `--point-at x,y,z`, session space.
var _point := ""
var _point_at := Vector3.ZERO
## `--note 36:try_a_fill_here`: a sticky note (a NOTE marker, PointAndMark.add_note) at that song
## time (an underscore a space, for a shell argument), from frame 6, and the timeline's window put round it.
var _note := ""
## `--plug djembe:player_7`: that source's jack stepped into that sink at frame 10, asked as a hand
## here asks (Studio._on_plug_asked; docs/spatial_loop.md slices 5 and 6). With --visitor, a
## jack into `player_7` runs its cable to Lin's ghost.
var _plug := ""
## `--fingertips 5`: the desktop's fingertips turned on at frame 10, as T turns them, with the keys
## of that mask's fingers held down (HandPose's bits: 1 J, 2 K, 4 L, 8 ;), for a shot of the glove
## playing them (docs/spatial_loop.md slice 8).
var _fingertips := -1
## `--chords 4`: at frame 10 the fifths wheel gone to, the chord layer turned on as C turns it, and that
## key of the number row pressed (1 to 7 the degrees, 0 the song's chord), for a shot of the
## desktop's chord glove at the wheel (docs/spatial_loop.md part two, slice 32).
var _chords := -1
## `--chord-from 4`: at frame 10 the fifths wheel gone to, and Lin's (peer 7) chord hand plugged into this
## player holding that degree of the song's key (1 to 7), taken as it comes down the jack
## (Jacks.received), for a shot of the sender named (part two, slice 33). Lin is
## in the room from then, standing where --visitor puts them if it is given.
var _chord_from := -1
## `--stations 2`: I pressed that many times at frame 10, as a desktop player goes to the
## instruments one by one (Studio.cycle_stations).
var _stations := 0
## `--test-drum`: the suite's fixed test drum (TestDrumItem, docs/spatial_loop.md part two, slice 38)
## stood on the floor in front of the seat at frame 4, for a shot of an instrument that stands still
## and its card (`--aim TEST_DRUM`, `--click TEST_DRUM@40`).
var _test_drum := false
## `--cassettes 3`: that many clips pulled out of the timeline at frame 8, each a cassette shelved
## in the cassette rack, and the rack gone to, for a shot of it holding them (docs/spatial_loop.md
## part two, slice 23).
var _cassettes := 0
## `--samples 2`: at frame 8 the sampler's REC pressed and something carried used that many times
## (the duck squeezed, a yo-yo tricked, the cards shuffled), each a sample cassette on the rack,
## REC pressed once more so it is lit and listening, and the sampler gone to unless SHOT_CAM frames
## it (docs/spatial_loop.md part two, slice 26). Its WAVs go to user://shot_samples, never the project's media.
var _samples := 0
## `--platter`: at frame 8 a clip off the first track with one, minted as a pull is, stood in the DJ
## platter's slot on the deck's cart, and the platter gone to unless SHOT_CAM frames it
## (docs/spatial_loop.md part two, slice 27).
var _platter := false
## `--crank N`: at frame 8 five edits made, each its own step, and the tape deck's history crank
## turned back N notches and left settling, so its readout says where it stands (docs/spatial_loop.md
## part two, slice 28). Not settled: a shot of the crank, not of the song played back.
var _crank := 0
## `--pads-demo`: the sampling station's pads loaded with a synthesized kit and struck in a pattern.
var _pads_demo := false
## `--sections N`: at frame 8 MAKE SECTIONS pressed on the section blocks (the demo's markers made
## regions), the playhead put into the second, and the blocks gone to unless SHOT_CAM frames them;
## N above 0 also takes block N in a stand-in hand and holds it at the front of the row, so the
## others have made room (docs/spatial_loop.md part two, slice 30).
var _sections := -1
var _sections_hand: Node = null
## `--plaque-rows`: after `--stations`, INSTRUMENTS pressed on the plaque of the station gone to,
## at frame 14, for a shot of the board's rows beside it (docs/spatial_loop.md slice 11).
var _plaque_rows := false
## `--help-page LIVE`: the help card open from frame 6 at the first page whose name has that in it
## (`PLAY · LIVE ROOM`).
var _help_page := ""
## `--posed-hand 1.2,1.1,-3.4,0.5,20,1`: a right hand posed (HandPose.posed) at that studio point,
## turned by that yaw (radians), rolled that many degrees right side down, its thumb pinching the
## fingers in that mask (HandPose's bits), from frame 5: reported on a tracker of its own, drawn by
## a HandSkeleton and read by a HandGestures, whose readings are lettered over it
## (docs/spatial_loop.md slice 7). Its index and middle tips pluck a room string, as a tracked hand's do.
var _posed_hand: Array = []
var _posed_gestures: HandGestures
var _posed_label: Label3D
var _posed_tracker: XRHandTracker
var _posed_place: Array = []
var _posed_curls: Array = [0.15, 0.05, 0.1, 0.35, 0.5]
## `--on-air 7`: that player ON AIR from frame 8, so their pack has its MONITOR socket
## (`--carry tablet:monitor_7`); `--on-air 1` is the one at this machine.
var _on_air := 0
## `--throw 0.6@200`: throw what --carry picked up, wound up that far (0..1), on that physics
## tick. Shoot it in flight with --shot-tick a little later.
var _throw := Vector2(-1, -1)
## `--lob 5.93,2.0,3.12,3@200`: throw what --carry picked up from the hand to that point (studio
## space) at that speed (m/s), on that physics tick: a throw that goes exactly where it is
## pointed, for a shot of it getting there. --spectate watches it as for --throw.
var _lob := PackedFloat32Array()
var _lob_tick := -1
## `--spectate 3,1.2,0:0,0.8,-2`: once --throw has thrown, watch from a camera there looking at
## that point (studio space), to see a flight from the side rather than from behind it.
var _spectate: Array = []
var _shot_res := Vector2i.ZERO
## `--panel layout|maker[:piece]`: the F3 layout edit panel or the F4 room-maker panel open from frame 6,
## as the key opens them; `layout:hoop` also picks that piece in the list, `layout:hoop:nudge` and moves it one step (ShotScenes._open_panel).
var _panel := ""
## `--make-room small|standard|large[:zone+zone...[:Title[:style]]]`: at frame 3 that room made by MadeRooms (the
## maker's own MAKE), zones joined with `+` (`all`, the default, is every zone that fits) and the band taken
## into it. Pair with `--walk` to stand in it.
var _make_room := ""
## `--rack-patch file.json`, `--delta file.json`, `--mod folder` (repeatable): put a rack patch (as
## the host's autosave), a room delta (under the key it names in `room`) and a mod folder (under user://mods)
## into the user data before the studio is built. They refuse to run against the real user data dir:
## give the run its own `SHOT_DATA_HOME` (tools/shot.sh), or they exit with a message.
var _rack_patch := ""
var _delta := ""
var _mods: PackedStringArray = []
var _hover := Vector2(-1, -1)
## `--drag 400,600:900,640@20-70`: hold the left button at the first point on physics tick 20,
## move to the second by tick 70, let go. `--turn 2` adds that many wheel notches halfway through.
## [from: Vector2, to: Vector2, first_tick: int, last_tick: int] per --drag; repeatable.
var _drags: Array = []
var _turn := 0
var _ticks := 0
## `--shot-tick 240`: capture on that physics tick instead of a drawn frame, for anything that
## moves in simulated time -- a pushed rack coasting to a stop -- rather than in frames.
var _shot_tick := -1
## `--quit-tick 900`: stay up until then after a --shot-tick capture. For a capture that is one
## half of a pair -- a guest that has to still be in the room when the host takes ITS picture.
var _quit_tick := -1
## Controls addressed by what they are called rather than where they happen to be drawn, so a
## step in the walkthrough survives the desk being re-laid out.
##   --aim KICK_IN__LEVEL               park the pointer on it (its hover card is the evidence)
##   --click TRANSPORT__PLAY@40         press it on tick 40 (repeatable)
##   --pull KICK_IN__LEVEL:0,60@40-90   drag from it by that many pixels over those ticks
## `_` stands for a space. An exact title wins; otherwise the first title containing it.
var _aim := ""
## `--look -0.6,-0.1`: turn the head by that much yaw and pitch (radians) where it already is --
## a look to the side from the seat, rather than --walk's standing somewhere else.
var _look := Vector2.ZERO
var _clicks: Array = []
var _pulls: Array = []
## `--rig-roll`: presses the Rig Roulette ROLL from frame 9.
## `--pull-track`: the first track with plugins pulled out of the rack on its own rack, and its
## first plugin on a tablet, frame 12.
## `--pull-tracks <n>`: the first n tracks with plugins pulled out on racks of their own, in a row
## behind the mix position, frame 12.
## `--board <surface id>`: the big board shows that surface live from frame 12 (after any roll).
## `--tour intact|broken|brief|draft|chaos|crowd|clock_low|win|loss|spill|rig`: the Tour case and its run put in that state from frame 9,
## deterministically (Tour.force_state_for_shot) rather than by waiting out a brief's timer.
## Needs the built-in engine (--built-in): Tour is gated to it, and quietly does nothing on any
## other backend, same as in play.
var _tour := ""
## `--tour-band 8`: fake guests 2..N registered on `Session.participants` at frame 8, before
## `--tour` forces the run's state at frame 9, so a brief's flaw/part count is drawn for that
## band size instead of a solo one -- for a shot of how a crowded card holds up, not for any
## real multiplayer behaviour.
var _tour_band := 0
## `--tl-shelf on|off`: the timeline in its 3D view (or flat), whatever the layout says, from frame 6.
var _tl_shelf := ""
## `--tl-road 30`: the timeline as the road, with the playhead parked at that many seconds, from frame 6.
var _tl_road := -1.0
## `--tl-select 3:0,3:1`: those items (track:item) selected from frame 7, so the timeline's item
## page shows. `--tl-pick 3`: that track picked from frame 7, for the track page.
var _tl_select := ""
## `--patch-wall`: the audio-device patch wall, hung in the middle of the room, showing this machine's graph.
var _patch_wall := false
## `--patch-graph 60`: the wall shows a made-up graph of about that many ports a side instead (nodes
## of four, one of a dozen, a few links), for a shot of a busy machine's grid; implies --patch-wall.
var _patch_graph := 0
## `--bay-scroll 30,20`: the routing bay's matrix scrolled to that row and column from frame 8.
var _bay_scroll := Vector2i(-1, -1)
## `--comfort`: the session panel open from frame 5 and scrolled to its COMFORT box.
var _comfort := false
## `--no-timeline`: the timeline hidden, for a shot of something it would cover.
var _no_timeline := false
## `--tl-region 9:17:Verse,17:25:Chorus`: regions from bar to bar, made at frame 7.
var _tl_region := ""
## `--tl-group 2:1,3:1`: those tracks put in those groups (track:group), at frame 7.
var _tl_group := ""
## `--reopen`: the project saved and opened again at frame 5, to see what a reopened project draws.
var _reopen := false
## `--autosave`: the transport stopped and an edit at frame 5, and the autosave kept straight
## after, to see what says so.
var _autosave := false
## `--recover`: a copy kept at frame 5 as if by an earlier run, so the RECOVER token offers it.
var _recover := false
## `--tl-fade T:I:S[:shape]`: item I of track T given fades of S seconds at each end, frame 7,
## and with a shape (1: equal power) that shape too.
var _tl_fade := ""
## `--clip-editor 3:0`: the clip editor opened on item 0 of track 3 at frame 8. `--clip-take 2:9`: a
## drum take (the demo song's kick, snare and hats, mixed and written as a file) put on track 2 at
## bar 9 at frame 6 and the editor opened on it, so its waveform is the file's. `--clip-span 0.25`:
## the editor's view that many seconds wide round the clip's start. `--clip-hover start`: the
## pointer parked on that handle (start, end, fade_in, fade_out, gain) from frame 10, for its card.
## `--clip-fade 0.05`: the clip given fades that long, `--clip-select fade_in` that handle selected,
## `--clip-zero` ZERO X on, `--clip-screen` the editor put on the glass (SCREEN), for its framing there.
var _clip_zero := false
var _clip_screen := false
var _clip_editor := ""
## `--input-picker 2`: track 2's InputPicker open over the room at frame 8.
var _input_picker := 0
var _clip_take := ""
var _clip_span := 0.0
var _clip_hover := ""
var _clip_fade := 0.0
var _clip_select := ""
## `--tl-xfade T:I`: item I of track T copied to start halfway along itself, and the two
## crossfaded over the overlap, frame 7.
var _tl_xfade := ""
var _tl_pick := -1
## `--wheel-take 7`: a phrase played on track 7 from a MIDI keyboard at frame 6, through the door a
## real one comes in by (GuestMidi._input), its pitch wheel swept and wobbled and its mod wheel
## raised, recorded to a clock of its own a second past the playhead, and the take selected: the
## thinned controls stand on its block as the timeline draws them (docs/spatial_loop.md slice 14).
var _wheel_take := -1
## `--tl-render`: the deck on its RENDER page, from frame 7.
var _tl_render := false
var _roll := false
var _rig_roll := false
var _board := ""
var _pull_track := false
var _pull_tracks := 0
## `--rope 2,6,0.3`: a rope tied on the stage table at frame 6 from track 2's knot to track 6's
## voice, pulled that far (0..1), and the song played, so the kick's own meter lifts it
## (docs/spatial_loop.md slice 20). How far it ducks at the shot is printed.
var _rope: Array = []
## `--paste 6:4@30`: the first item of track 6 pulled into the mouse hand as a cassette at frame 6,
## the timeline opened round bar 30 with the pointer parked on track 4's lane a third of a beat
## past it, and the mouse pressed there at frame 12, so the take is pasted onto the beat and the
## lanes' card still says what a press pastes (docs/spatial_loop.md part two slice 24).
var _paste: Array = []
## `--ear 6`: the first item of track 6 pulled into the mouse hand as a cassette at frame 6 and held to
## the ear with L at frame 8, so it rides raised beside the view with its tag saying what it is doing
## and the toast what it plays (docs/spatial_loop.md part two slice 25).
var _ear := 0
## `--bead KICK_IN__LEVEL@40`: the song rolling round a loop of BEAD_LOOP seconds from the playhead
## (frame 7), the pointer parked on that control so its write bead shows over it, and on that
## physics tick the bead pressed and dragged up and down in a wave, held to the shot: a pass is
## written at each wrap, and its lane drawn (docs/spatial_loop.md part two slice 22).
var _bead_aim := ""
var _bead_tick := -1
var _bead_from := Vector2(-1, -1)
const BEAD_LOOP := 2.4


## The command line, read once at startup.
var cmdline := ShotArgs.new(self)
## Scenes a shot sets up before it is taken.
var scenes := ShotScenes.new(self)
## What happens on each frame of a shot.
var stepping := ShotFrames.new(self)
## The scripted mouse that drags, aims and turns.
var driving := ShotDrive.new(self)
## Longer demonstrations: cassettes, the wheel's takes, the signal and the clip editor.
var demos := ShotDemos.new(self)

func _ready() -> void: cmdline._ready()


func _process(_delta: float) -> void:
	_frames += 1
	if _frames % 15 == 0 and OS.get_cmdline_user_args().has("--shot-debug"):
		print("SHOT_FRAME %d tick %d at %d ms" % [_frames, _ticks, Time.get_ticks_msec()])

	stepping._process_framing()
	stepping._process_scenes()
	stepping._process_chords()
	stepping._process_hands()


func _capture() -> void: stepping._capture()

## Driven on physics ticks, not rendered frames. Captures run with vsync off, so hundreds of frames are drawn per tick, and a drag paced by frames was over before the interactor -- which reads its button on the physics tick, like every hand -- had looked once (`ShotDrive._physics_process`).
func _physics_process(_delta: float) -> void: driving._physics_process(_delta)

func _wheel(hand: MouseInteractor) -> void: driving._wheel(hand)


const CLIP_HANDLES := {"start": ClipEditorSurface.START, "end": ClipEditorSurface.END,
		"fade_in": ClipEditorSurface.FADE_IN, "fade_out": ClipEditorSurface.FADE_OUT, "gain": ClipEditorSurface.GAIN}
