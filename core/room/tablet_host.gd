class_name TabletHost
extends RefCounted

## The studio's tablets and track racks: tearing a plugin or a track off the wall, standing it as a tablet or a rack in the
## room, putting it back, and remembering where the player left them. Moved out of `scenes/studio.gd` without change of
## behaviour; the state stays on the studio, which delegates the calls other code makes.

## Guest: how many stands it has put out on its own say-so, for naming them until the host does.
var _predicted_tablets := 0

var _predicted_track_racks := 0

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

var studio: Studio


func _init(of: Studio) -> void:
	studio = of


func _on_tear_requested(track: int, fx: int, at: Vector3, from: Node3D = null) -> void:
	var f := DAW.state.fx(track, fx, false)
	if f == null or f.name == "":
		return
	# Out from the rack along its facing, so a tablet pulled straight off lands in front of it
	# rather than inside it.
	var out := (from if from != null else studio.rack).global_basis.z.normalized()
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
	for id in studio.tablets:
		var tablet: PluginTablet = studio.tablets[id][1]
		if tablet.track_index == track and tablet.fx_index == fx:
			(studio.tablets[id][0] as Trolley).place(where, _facing_mix(where))
			return id
	var n := 1
	while studio.tablets.has(StringName("tablet_%d" % n)) or (Session.layout != null \
			and Session.layout.tablets.has(StringName("tablet_%d" % n))):
		n += 1
	var id := StringName("tablet_%d" % n)
	_build_tablet(id, track, fx, plugin_name)
	(studio.tablets[id][0] as Trolley).place(where, _facing_mix(where))
	_remember_tablets()
	studio.room_rows._publish_room()
	return id


func _facing_mix(from: Vector2) -> float:
	var to := Vector2(0, Studio.MIX_POSITION_Z) - from
	return atan2(to.x, to.y)


func _build_tablet(id: StringName, track: int, fx: int, plugin_name: String) -> void:
	var stand := studio.rack_host._trolley("PluginStand_%s" % id, id, Vector3(0, 0, 0.6), 0.0)
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
	if studio.focus != null:
		studio.focus.surfaces.append(tablet)
		tablet.rebuilt.connect(studio.focus._on_surface_rebuilt.bind(tablet))
	studio.tablets[id] = [stand, tablet]


## Takes the tablet `id` down, forgets where it stood and, on the host, clears its saved spot.
func close_tablet(id: StringName) -> void:
	if not studio.tablets.has(id):
		return
	_take_down_tablet(id)
	if Session.layout != null and Session.is_authority():
		Session.layout.clear_transform(StringName("floor/%s" % id), Presentation.Mode.STUDIO)
	_remember_tablets()
	studio.room_rows._publish_room()


## The stand gone from this room, and nothing remembered or told about it.
func _take_down_tablet(id: StringName) -> void:
	var stand: Trolley = studio.tablets[id][0]
	var tablet: PluginTablet = studio.tablets[id][1]
	if studio.focus != null:
		if studio.focus.focused_id == id:
			studio.focus.release()
		studio.focus.surfaces.erase(tablet)
	studio.tablets.erase(id)
	studio.floor_plan.pieces.erase(stand)
	stand.queue_free()


## Put back on the rack: here if the room is ours; if it is the host's, here at once and asked.
func _dock_tablet(id: StringName) -> void:
	if Session.is_authority():
		close_tablet(id)
	elif studio.tablets.has(id) and studio.room_rows._predict(&"close_tablet", [id]) > 0:
		_take_down_tablet(id)


func _predicted_tablet(track: int, fx: int, plugin_name: String, where: Vector2) -> StringName:
	for id in studio.tablets:
		var t: PluginTablet = studio.tablets[id][1]
		if t.track_index == track and t.fx_index == fx:
			(studio.tablets[id][0] as Trolley).place(where, _facing_mix(where))
			return id
	_predicted_tablets += 1
	var id := StringName("mine_%d" % _predicted_tablets)
	if studio.room_rows._predict(&"open_tablet", [track, fx, plugin_name, where.x, where.y], id) == 0:
		return StringName()
	_build_tablet(id, track, fx, plugin_name)
	studio._applying_room = true
	(studio.tablets[id][0] as Trolley).place(where, _facing_mix(where))
	studio._applying_room = false
	return id


## The list of what is out, saved whenever a tablet is opened or closed. Not when a tablet finds
## its plugin somewhere new: the name finds it again next time anyway, and a profile rewritten
## because a different session happened to be open would be a file changed by looking at it.
func _remember_tablets() -> void:
	# A guest's tablets are the host's room, not its own: its own wait for it in the profile.
	if Session.layout == null or not Session.is_authority():
		return
	var out := {}
	for id in studio.tablets:
		var t: PluginTablet = studio.tablets[id][1]
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
	for id in studio.track_racks:
		if (studio.track_racks[id][1] as RackSurface).track_index == track:
			(studio.track_racks[id][0] as Trolley).place(where, _facing_mix(where))
			return id
	var n := 1
	while studio.track_racks.has(StringName("track_rack_%d" % n)) or (Session.layout != null \
			and Session.layout.track_racks.has(StringName("track_rack_%d" % n))):
		n += 1
	var id := StringName("track_rack_%d" % n)
	_build_track_rack(id, track)
	(studio.track_racks[id][0] as Trolley).place(where, _facing_mix(where))
	_remember_track_racks()
	studio.room_rows._publish_room()
	return id


func _build_track_rack(id: StringName, track: int) -> void:
	var stand := studio.rack_host._trolley("TrackRackTrolley_%s" % id, id, Vector3(0, 0, 0.6), 0.0)
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
		if studio.track_racks.has(id):
			_paint_track_band(id))
	pulled.rebuilt.connect(studio.patch_host._show_patches)
	if studio.focus != null:
		studio.focus.surfaces.append(pulled)
		pulled.rebuilt.connect(studio.focus._on_surface_rebuilt.bind(pulled))
	studio.track_racks[id] = [stand, pulled]
	_paint_track_band(id)


## The band on a pulled-out rack's plinth, in its track's colour as this venue shows it.
func _paint_track_band(id: StringName) -> void:
	var band := (studio.track_racks[id][0] as Node).find_child("TrackBand", true, false) as MeshInstance3D
	var track := (studio.track_racks[id][1] as RackSurface).track_index
	if band != null and DAW.state.tracks.has(track):
		band.material_override = Materials.track_stripe(DAW.state.track(track).shown_colour())


## The venue's palette changed what every track is shown in: everything that shows a track's
## colour is built again in it.
func _recolour_tracks() -> void:
	if studio.mount != null:
		for surface_id in studio.mount.mounted_ids():
			studio.mount.surface(surface_id).mark_dirty()
	for id in studio.tablets:
		(studio.tablets[id][1] as Surface).mark_dirty()
	for id in studio.track_racks:
		(studio.track_racks[id][1] as Surface).mark_dirty()
		_paint_track_band(id)


## Takes the track rack `id` down, forgets where it stood and, on the host, clears its saved spot.
func close_track_rack(id: StringName) -> void:
	if not studio.track_racks.has(id):
		return
	_take_down_track_rack(id)
	if Session.layout != null and Session.is_authority():
		Session.layout.clear_transform(StringName("floor/%s" % id), Presentation.Mode.STUDIO)
	_remember_track_racks()
	studio.room_rows._publish_room()


func _take_down_track_rack(id: StringName) -> void:
	var stand: Trolley = studio.track_racks[id][0]
	var pulled: RackSurface = studio.track_racks[id][1]
	if studio.focus != null:
		if studio.focus.focused_id == id:
			studio.focus.release()
		studio.focus.surfaces.erase(pulled)
	studio.track_racks.erase(id)
	studio.floor_plan.pieces.erase(stand)
	stand.queue_free()


## FOLD: back into the main rack. Here if the room is ours; if it is the host's, here at once
## and asked.
func _fold_track_rack(id: StringName) -> void:
	if Session.is_authority():
		close_track_rack(id)
	elif studio.track_racks.has(id) and studio.room_rows._predict(&"close_track_rack", [id]) > 0:
		_take_down_track_rack(id)


func _predicted_track_rack(track: int, where: Vector2) -> StringName:
	for id in studio.track_racks:
		if (studio.track_racks[id][1] as RackSurface).track_index == track:
			(studio.track_racks[id][0] as Trolley).place(where, _facing_mix(where))
			return id
	_predicted_track_racks += 1
	var id := StringName("mine_rack_%d" % _predicted_track_racks)
	if studio.room_rows._predict(&"open_track_rack", [track, where.x, where.y], id) == 0:
		return StringName()
	_build_track_rack(id, track)
	studio._applying_room = true
	(studio.track_racks[id][0] as Trolley).place(where, _facing_mix(where))
	studio._applying_room = false
	return id


## Tracks renumbered: each pulled-out rack follows its own track, and one whose track is gone
## is folded away, since there is nothing left on it to rack.
func _fold_orphaned_track_racks() -> void:
	if not Session.is_authority():
		return
	for id in studio.track_racks.keys():
		if not DAW.state.tracks.has((studio.track_racks[id][1] as RackSurface).track_index):
			close_track_rack(id)
	_remember_track_racks()


## Saved like the tablets: what is out, by track. Where each stands is its floor transform.
func _remember_track_racks() -> void:
	if Session.layout == null or not Session.is_authority():
		return
	var out := {}
	for id in studio.track_racks:
		out[id] = (studio.track_racks[id][1] as RackSurface).track_index
	if out == Session.layout.track_racks:
		return
	Session.layout.track_racks = out
	Session.layout.save()


func _restore_track_racks() -> void:
	if Session.layout == null or not Session.is_authority():
		return
	for id in Session.layout.track_racks:
		if not studio.track_racks.has(id):
			_build_track_rack(id, int(Session.layout.track_racks[id]))
