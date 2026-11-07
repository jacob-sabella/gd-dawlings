class_name VenueLook
extends RefCounted

## The room's look and its floor: the environment and house light, the studio lamps (relight, follow a clip, flicker, lights out),
## the ceiling and where the player may walk. Moved out of `scenes/studio.gd` without change of behaviour; the state stays on the studio, which delegates the calls other code makes.

## How far a practical reaches. Short on purpose: at 6.5m each lamp lit all three walls, and
## three of them made the empty half of the room as bright as the gear (37.0 against 38.7 on
## the console's face). A floor lamp is a pool, not a sun.
## Longer since the room grew: at 3.6 m the 11 m room's corners were black.
const LAMP_RANGE := 4.6

var _lamps_lifted := 0.0

## The one tween either `_flicker_lights` or `_lights_out` ever runs, killed before the other
## starts a new one, so a second chaos event mid-blackout can never fight the first over a lamp.
var _lights_tween: Tween

var studio: Studio


func _init(of: Studio) -> void:
	studio = of


func _build_environment() -> void:
	studio.world_env = WorldEnvironment.new()
	studio.world_env.environment = _house_environment()
	studio.add_child(studio.world_env)
	if studio.venue_switch.rich_rendering():
		_tune_renderer()

	# Key light from above and in front, as a studio's ceiling panel would be. Shadows are what
	# seat the gear on the desk rather than leaving it floating a centimetre above it.
	studio.key_light = DirectionalLight3D.new()
	studio.key_light.name = "Key"
	_house_key(studio.key_light)
	studio.add_child(studio.key_light)

	# The practicals, the lamps an actual control room has. They also give the metal something to
	# catch: brushed aluminium under a single light source reads as flat grey. The stands that
	# hold them up are furniture and are built there, because an AR participant has real lamps
	# in a real room and needs these to light the virtual gear without appearing in front of him.
	for spec in Studio.PRACTICALS:
		var lamp := OmniLight3D.new()
		lamp.position = spec[0]
		lamp.light_color = spec[1]
		lamp.light_energy = spec[2]
		lamp.omni_range = LAMP_RANGE
		lamp.shadow_enabled = false
		if studio.venue_switch.rich_rendering():
			# Soft, contact-hardening shadows from a bulb the size of a bulb. A lamp that lights
			# gear without shadowing it is what made everything look pasted onto the room.
			lamp.shadow_enabled = true
			lamp.light_size = 0.06
			lamp.shadow_bias = 0.04
			lamp.shadow_normal_bias = 1.0
			lamp.light_volumetric_fog_energy = 0.6
		studio.add_child(lamp)
		studio._lamps.append(lamp)


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
	if studio.venue_switch.standalone_headset():
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
	if studio.venue_switch.standalone_headset():
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
	var view := studio.get_viewport()
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
	if drawn == null or studio.screen_stage == null or not is_instance_valid(studio.screen_stage):
		return
	if studio.screen_stage.is_ancestor_of(drawn):
		# Bit by bit rather than the whole mask: the big board's feed marks what it shows with a
		# layer of its own (BoardFeed.ON_BOARD), which this must leave alone.
		if drawn.layers & 1:
			drawn.layers = (drawn.layers & ~1) | Mirror.NOT_REFLECTED
			drawn.set_meta(&"kept_out_of_mirrors", true)
	elif drawn.has_meta(&"kept_out_of_mirrors"):
		drawn.layers = (drawn.layers & ~Mirror.NOT_REFLECTED) | 1
		drawn.remove_meta(&"kept_out_of_mirrors")


## The practicals back to the venue's own colour and energy, and the venue's own house lights
## back on (`Venue.blackout(false)`) -- `set_venue`'s own tail, factored out so a chaos event's
## blackout (`_lights_out`) has somewhere to put the room back, however it found it: a run
## ending mid-dark, or a second strike landing before the first one's `_relight` fired.
func _relight() -> void:
	for i in studio._lamps.size():
		if i < Studio.PRACTICALS.size():
			studio._lamps[i].light_color = studio.venue.lamp_colour(i, Studio.PRACTICALS[i][1])
			studio._lamps[i].light_energy = studio.venue.lamp_energy(i, Studio.PRACTICALS[i][2])
	if studio.venue != null:
		studio.venue.blackout(false)


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
	if studio.console != null:
		if studio.console.master != null:
			studio.console.master.show_over(master_over, delta)
		for strip in studio.console.strips:
			if is_instance_valid(strip):
				strip.show_over(over.has(strip.track_index), delta)
	studio.venue.hear_clip(any, delta)
	lift_lamps(studio.venue.lift)


## The practicals at their venue's energy, `by` (a share) above it. Left alone while a chaos
## event's tween has them, and written only when it changes.
func lift_lamps(by: float) -> void:
	if _lights_tween != null and _lights_tween.is_valid() and _lights_tween.is_running():
		return
	if is_equal_approx(by, _lamps_lifted):
		return
	_lamps_lifted = by
	for i in studio._lamps.size():
		if i < Studio.PRACTICALS.size():
			studio._lamps[i].light_energy = studio.venue.lamp_energy(i, Studio.PRACTICALS[i][2]) * (1.0 + by)


## `power_flicker`'s telegraph: the practicals dip to a sixth and back, twice, fast -- a flicker
## you feel coming, not a cut you only notice after. `_lights_tween` is the one tween either this
## or `_lights_out` ever runs, killed first so the two can never fight over the same lamps.
func _flicker_lights() -> void:
	if studio._lamps.is_empty():
		return
	if _lights_tween != null:
		_lights_tween.kill()
	var base: Array[float] = []
	for lamp in studio._lamps:
		base.append(lamp.light_energy)
	_lights_tween = studio.create_tween()
	for _k in 2:
		_lights_tween.set_parallel(true)
		for i in studio._lamps.size():
			_lights_tween.tween_property(studio._lamps[i], "light_energy", base[i] / 6.0, 0.08)
		_lights_tween.chain().set_parallel(true)
		for i in studio._lamps.size():
			_lights_tween.tween_property(studio._lamps[i], "light_energy", base[i], 0.08)
		_lights_tween.chain()


## `power_flicker`'s strike: the practicals die, the venue's own house lights with them
## (`Venue.blackout(true)`), for one bar -- then `_relight` brings both back however the run has
## left them (a leaver, a second strike), rather than assuming anything about where this one
## found them.
func _lights_out(seconds: float) -> void:
	if _lights_tween != null:
		_lights_tween.kill()
	_lights_tween = studio.create_tween()
	_lights_tween.set_parallel(true)
	for lamp in studio._lamps:
		_lights_tween.tween_property(lamp, "light_energy", 0.0, 0.12)
	if studio.venue != null:
		studio.venue.blackout(true)
	_lights_tween.chain().tween_callback(_relight).set_delay(seconds)


## On foot you can go where the room goes: the working footprint and, behind it, the venue's
## live room with its zones. The furniture's floor plan is still the footprint alone.
func _walkable() -> Array[Rect2]:
	var out: Array[Rect2] = [studio.venue_switch._room_bounds()]
	if studio.venue != null:
		out.append_array(studio.venue.walk_rooms())
	return out


## The venue's ceiling, over the walker wherever it is.
func _ceiling() -> float:
	return studio.venue.ceiling_height() if studio.venue != null else Venue.LIVE_ROOM_HEIGHT


## The modular room's roof is lower than the live room's: under it, that is the ceiling.
func _ceiling_at(where: Vector3) -> float:
	if studio.modular_annex != null and is_instance_valid(studio.modular_annex) and studio.modular_annex.is_inside_tree():
		var local := studio.modular_annex.to_local(where)
		if ModularAnnex.inside(studio.modular_annex.half).has_point(Vector2(local.x, local.z)):
			return ModularAnnex.HEIGHT
	return 1000.0


func _walk_where_the_venue_lets() -> void:
	if studio.walker != null:
		studio.walker.walkable = _walkable()
		studio.walker.fixed = studio.venue.solids() if studio.venue != null else []
		studio.walker.ceiling = _ceiling()
		studio.walker.rebuild_walls()
		studio.walker.unstick()
	if studio.items != null and studio.venue != null:
		studio.items.boards = studio.venue.dart_boards()
		studio.items.hoops = RoomSync.hoops(studio)
		studio.items.set_venue(studio.venue.venue_id())
		studio.items.set_spots(studio.venue.item_spots(), studio.item_host._item_homes())
	studio.pieces.hold_the_rack()
	if studio.tour_case != null and studio.venue != null:
		studio.tour_case.transform = studio.venue_switch._venue_to_set(studio.venue.tour_case_spot())
		studio.pieces.rehome_spills()


## Somewhere else to stand, if this is somebody's to say: the room is the host's, so a guest
## asking is told so rather than taken somewhere nobody else is.
## How tall you are, changed in the room: the eye goes there at once and the height is kept
## for next time. The gear stays where it is -- it is the room's, and you are the one who grew.
func set_body_height(height: float) -> void:
	studio.ergonomics.set_height(height)
	Ergonomics.save_height(studio.ergonomics.height, studio.body_path)
	if studio.walker != null:
		studio.walker.standing_eye = studio.ergonomics.eye_height
		studio.walker.eye_height = studio.ergonomics.eye_height
		studio.walker._place_camera()
	if studio.body != null and studio.medium == Presentation.Medium.SCREEN:
		studio.body.position.y = studio.ergonomics.eye_height
