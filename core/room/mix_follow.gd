class_name MixFollow
extends RefCounted

## The personal mix and the head: phones and the personal mix, listening, the track under a ray or the mouse, clapping, leaning
## and the ear cup. Moved out of `scenes/studio.gd` without change of behaviour; the state stays on the studio, which delegates the calls other code makes.

var _lean_refused := 0

## How near (m) a head comes to a stage voice to lean in to it (Ears.lean).
const LEAN_REACH := 0.25

var studio: Studio


func _init(of: Studio) -> void:
	studio = of


## What the headphones on this person's head let through (Ears), and what this person is told
## about it when they go on.
func _on_phones_changed() -> void:
	var phones := studio.items.items.get(&"headphones") as HeadphonesItem if studio.items != null else null
	if phones == null:
		return
	var now := phones.carried_by != null and phones.on_head
	if now == studio._heard_phones:
		return
	studio._heard_phones = now
	_listen()
	var tablet := studio.items.items.get(&"tablet") as TabletItem
	if tablet != null:
		tablet.listening = now
	if not now:
		return
	if not Ears.reaches_mix(Session.role == Session.Role.GUEST, DAW.backend is ReaperBackend):
		Session.notice.emit("Headphones on: the room shut out. You hear Reaper itself, through the system.")
	elif studio.personal.is_patched():
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
		(DAW.backend as GodotBackend).set_cues(studio.personal.tracks() if studio._heard_phones and studio.personal.hears_tracks else [])
		(DAW.backend as GodotBackend).set_taps(studio.personal.taps() if studio._heard_phones and studio.personal.hears_tracks else [])
	if studio.their_keys != null:
		studio.their_keys.set_players(studio.personal.players() if studio._heard_phones else [])
	if studio.their_monitor != null:
		studio.their_monitor.set_performers(studio.personal.performers() if studio._heard_phones else [])
	Ears.listen(studio._heard_phones, studio.personal.ears_levels())


## The track a ray from `origin` along `direction` points at, 0 for none (docs/spatial_loop.md
## slice 19): whatever control it meets first, read by `track_of`. The head's gaze, for a clap
## made pointing at nothing.
func track_under(origin: Vector3, direction: Vector3) -> int:
	if not studio.is_inside_tree() or direction.length() < 0.0001:
		return 0
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * Interactor.RAY_LENGTH)
	query.collision_mask = 1 << (Interactor.CONTROL_LAYER - 1)
	var hit := studio.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return 0
	return Studio.track_of(hit["collider"], hit["position"])


## The track what a hand holds or hovers belongs to, 0 for none.
func pointed_by(hand: Interactor) -> int:
	if hand == null or not is_instance_valid(hand):
		return 0
	var control: ControlAffordance = hand.held if hand.held != null else hand.hovered
	if control == null or not is_instance_valid(control):
		return 0
	return Studio.track_of(control, hand.hover_point)


func _mouse_track() -> int:
	return pointed_by(studio.get_node_or_null("MouseHand") as Interactor)


## The track a clap is aimed at as the hands meet: under either hand's ray, or else the head's gaze.
func _clap_target() -> int:
	if studio.rig == null:
		return _mouse_track()
	for controller in studio.rig.interactors:
		var t := pointed_by(studio.rig.interactors[controller] as Interactor)
		if t > 0:
			return t
	if studio.rig.head != null and studio.rig.head.is_inside_tree():
		return track_under(studio.rig.head.global_position, -studio.rig.head.global_basis.z)
	return 0


## One frame of the two hands for a clap: their palms (bare hands) or grips (controllers).
func _follow_clap(delta: float) -> void:
	studio.key_clap.hold(delta)
	if not studio.clap.target.is_valid():
		studio.clap.target = _clap_target
	if studio.rig == null or studio.rig.left == null or studio.rig.right == null:
		return
	var a := studio.rig.interactors.get(studio.rig.left) as XRInteractor
	var b := studio.rig.interactors.get(studio.rig.right) as XRInteractor
	if a == null or b == null:
		return
	var r := Clap.reading(a.clap_palm(), b.clap_palm())
	studio.clap.step(r[0], r[1], delta)


## The track to lean in to now, 0 for none: in a headset the stage voice the head is within
## LEAN_REACH of, the nearest; at a desk, the voice under the cursor while L is held.
func lean_wanted() -> int:
	if studio.stage == null or not is_instance_valid(studio.stage):
		return 0
	if studio.rig != null and studio.rig.head != null and studio.rig.head.is_inside_tree():
		var best := 0
		var near := LEAN_REACH
		for track in studio.stage.voices:
			var d := (studio.stage.voices[track] as Node3D).global_position.distance_to(studio.rig.head.global_position)
			if d <= near:
				near = d
				best = int(track)
		if best > 0:
			return best
	if not studio._lean_key:
		return 0
	var hand := studio.get_node_or_null("MouseHand") as Interactor
	var control: Node = (hand.held if hand.held != null else hand.hovered) if hand != null else null
	if control == null or not is_instance_valid(control) or not studio.stage.is_ancestor_of(control):
		return 0
	return Studio.track_of(control, hand.hover_point)


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
			Session.notice.emit("%s: %s." % [studio.stage.title_of(want), Ears.CANNOT_LEAN])
		return
	if Ears.lean(want) and want > 0:
		Session.notice.emit("Leaning in to %s: %+d dB in your ears alone, the mix %d dB down. Nothing changes in the song."
				% [studio.stage.title_of(want), int(GodotBackend.LEAN_DB), int(Ears.LEAN_MIX_DB)])


## The cassette at an ear here now, null for none (docs/spatial_loop.md part two, slice 25): any
## hand's here that holds one there (Interactor.cassette_at_ear), and that hand. Every hand is
## asked every frame, so each one's memory of being at the ear (XRInteractor.EAR_LEAVE) is of
## now; with one at each ear, the one already playing keeps on, else the first.
func ear_wanted() -> Array:
	var wanted := [null, null]
	for node in studio.get_tree().get_nodes_in_group(Interactor.GROUP):
		var hand := node as Interactor
		var c := hand.cassette_at_ear() if hand != null else null
		if c == null:
			continue
		if wanted[0] == null or (studio.ear != null and c == studio.ear.cassette and wanted[0] != studio.ear.cassette):
			wanted = [c, hand]
	return wanted


## The cassette at the ear playing, or stopping, as `ear_wanted` says.
func _follow_ear() -> void:
	if studio.ear == null:
		return
	var wanted := ear_wanted()
	if wanted[0] != studio.ear.cassette:
		studio.ear.desk = wanted[1] is MouseInteractor or wanted[1] == null
	studio.ear.hold(wanted[0])


## Whether a strip's socket can be heard here: the tracks are played one by one on this machine.
func _hears_tracks() -> bool:
	return DAW.backend is GodotBackend and Session.role != Session.Role.GUEST


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
