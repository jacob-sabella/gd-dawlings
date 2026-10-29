class_name HandDrum
extends InstrumentItem

## A circle of hand drums (docs/spatial_loop.md part two, slice 40, idea #30): a djembe, a high and
## a low conga and a cajón, standing in a ring on the drum riser for the band (Venue.drum_circle_spot,
## the station `drums`). Each is a fixed kind of the room (ItemRoom.KINDS, `Item.fixed`): it never
## leaves its place, and where it is struck picks its sound.
##
## On a round head, by how far from its middle the strike lands: bass inside BASS_WITHIN of the
## radius, slap past SLAP_PAST, tone between (`zone_at`). On the cajón, whose head is its front face
## (the tapa), the face's middle is bass and its top edge, the corners a cajón player slaps, the slap
## (within CAJON_SLAP of the top).
##
## Each zone rings a sound of its own (Foley.hand_drum, `zone_kind`), heard on the fast path for
## this player's own hand (slice 39) and from where the drum stands for everyone else's, and is
## recorded as a General MIDI drum on the drums' channel (`zone_note`, NOTES), so a take plays back
## as drums (ItemVoices, slice 16): the djembe's bass, tone and slap as the low conga (64), the open
## high conga (63) and the muted high conga (62); the high conga 63 open and 62 slapped; the low
## conga 64, its slaps too; the cajón's bass as the kick (36) and its slap as the snare (38).
##
## Bare hands strike it by their palms and fingers, controllers by their tips and grip points
## (Strike); the mouse by a click whose zone is where it lands, Shift-click softly (`struck_by`).
## Each has its own output jack, on its front, which is toward the ring's open side.

## The four, in the order they stand round the ring (Venue.drum_circle_spot's n).
const KINDS: Array[StringName] = [&"djembe", &"conga_hi", &"conga_lo", &"cajon"]
const CAJON := &"cajon"
## Where a round head's zones meet, as a share of its radius from the middle: bass inside, slap past.
const BASS_WITHIN := 0.35
const SLAP_PAST := 0.8
## How far down from the cajón's top edge its slap reaches (m): the top corners, and the edge between.
const CAJON_SLAP := 0.1
const MODELS := {&"djembe": "res://assets/models/djembe.glb", &"conga_hi": "res://assets/models/conga.glb",
		&"conga_lo": "res://assets/models/conga.glb", &"cajon": "res://assets/models/cajon.glb"}
## How high each one stands off the riser on its stand: the djembe and the congas in a three-legged
## one, the cajón on a frame that much taller than a sitter's. A riser's height (ZoneKit.RISER_HEIGHT),
## since a player stands on the riser with them (Stations.seat puts a headset's floor on its top),
## so each head is as high above that player's feet as it would be above the floor beside it.
const STAND := 0.3
## Each one's look and its head, as tools/blender/hand_drums.py builds it: its title, its head's
## height off what it stands on (its stand's feet), and its head's radius (a round one) or its face's
## size (the cajón, `face`, width and height, and `lift`, the stand it is on, so its face starts that
## far up), and where its jack is on a round one's shell (`jack`: how high, and the shell's radius
## there). The low conga is the high one's model widened by its radius (`widen`). A round one's
## grip is its shell above its stand, and the djembe's its bowl and head only (`grip_from` up),
## since a cylinder as wide as its head down to its foot would swallow the jack on its narrow waist.
const SPECS := {
	&"djembe": {"title": "DJEMBE", "height": 0.62 + STAND, "radius": 0.165, "jack": Vector2(0.26 + STAND, 0.077),
			"grip_from": 0.36 + STAND},
	&"conga_hi": {"title": "HIGH CONGA", "height": 0.76 + STAND, "radius": 0.14, "jack": Vector2(0.45 + STAND, 0.163),
			"grip_from": STAND},
	&"conga_lo": {"title": "LOW CONGA", "height": 0.76 + STAND, "radius": 0.155, "widen": 0.155 / 0.14,
			"jack": Vector2(0.45 + STAND, 0.163 * 0.155 / 0.14), "grip_from": STAND},
	&"cajon": {"title": "CAJÓN", "height": 0.74 + STAND, "face": Vector2(0.3, 0.48), "lift": 0.26 + STAND, "depth": 0.3},
}
## Each one's zones, and the General MIDI drum each is recorded as.
const ZONES := {
	&"djembe": [&"bass", &"tone", &"slap"],
	&"conga_hi": [&"bass", &"tone", &"slap"],
	&"conga_lo": [&"bass", &"tone", &"slap"],
	&"cajon": [&"bass", &"slap"],
}
const NOTES := {
	&"djembe": {&"bass": 64, &"tone": 63, &"slap": 62},
	&"conga_hi": {&"bass": 63, &"tone": 63, &"slap": 62},
	&"conga_lo": {&"bass": 64, &"tone": 64, &"slap": 64},
	&"cajon": {&"bass": 36, &"slap": 38},
}
## What each one's card says of its zones.
const WORDS := {
	&"djembe": "centre bass · between tone · rim slap",
	&"conga_hi": "centre bass · between tone · rim slap",
	&"conga_lo": "centre bass · between tone · rim slap",
	&"cajon": "the face's middle bass · its top corners slap",
}
## The materials the model's surfaces are named for, as this game draws them.
const LOOKS := {
	"shell": [Color(0.36, 0.2, 0.1), 0.55], "skin": [Color(0.86, 0.79, 0.64), 0.85],
	"rope": [Color(0.78, 0.7, 0.52), 0.9], "hoop": [Color(0.72, 0.72, 0.74), 0.3],
	"stave": [Color(0.5, 0.18, 0.09), 0.35], "wood": [Color(0.62, 0.43, 0.24), 0.6],
	"tapa": [Color(0.8, 0.62, 0.4), 0.5], "screw": [Color(0.15, 0.14, 0.13), 0.4],
	"hole": [Color(0.04, 0.03, 0.02), 0.9], "stand": [Color(0.12, 0.11, 0.1), 0.6],
}

var kind := &"djembe"


func _init(which := &"djembe") -> void:
	kind = which if SPECS.has(which) else &"djembe"
	id = kind
	fixed = true
	own_home = true
	super()
	_shape.position = _grip_middle()


func item_title() -> String:
	return SPECS[kind]["title"]


func _spec() -> Dictionary:
	return SPECS[kind]


## Its head's height off what it stands on: a round one's skin, the cajón's top.
func head_height() -> float:
	return _spec()["height"]


## A round head's radius (0 for the cajón).
func head_radius() -> float:
	return _spec().get("radius", 0.0)


func pitch() -> int:
	return NOTES[kind][&"tone" if kind != CAJON else &"bass"]


func sound_kind(_struck: bool) -> StringName:
	return zone_kind(&"tone" if kind != CAJON else &"bass")


## Where it is struck: a round head facing up, or the cajón's face, facing out of its front (-Z),
## its frame's Z up the face (so `half` is its half width and half height).
func faces() -> Array:
	if kind == CAJON:
		var face: Vector2 = _spec()["face"]
		var middle := Vector3(0, float(_spec()["lift"]) + face.y * 0.5, -float(_spec()["depth"]) * 0.5)
		return [{"frame": global_transform * Transform3D(Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP), middle),
				"half": face * 0.5}]
	return [{"frame": global_transform * Transform3D(Basis.IDENTITY, Vector3.UP * head_height()),
			"radius": head_radius()}]


## Bass at the centre, slap at the rim, tone between, by how far across the head from its middle
## `point` is, whatever its height (a click on the shell's side is at the rim). On the cajón, the
## slap within CAJON_SLAP of its top, the bass everywhere else on it.
func zone_at(point: Vector3) -> StringName:
	var local := global_transform.affine_inverse() * point
	if kind == CAJON:
		return &"slap" if local.y > head_height() - CAJON_SLAP else &"bass"
	var out := Vector2(local.x, local.z).length() / head_radius()
	if out < BASS_WITHIN:
		return &"bass"
	if out > SLAP_PAST:
		return &"slap"
	return &"tone"


func zone_words() -> String:
	return WORDS[kind]


## Foley's own sound for each zone: Foley.hand_drum's, by this kind and the zone.
func zone_kind(zone: StringName) -> StringName:
	return Foley.hand_drum_sound(kind, zone) if zone in ZONES[kind] else &""


func zone_note(zone: StringName, seconds: float) -> int:
	return NOTES[kind].get(zone, note_at(seconds))


func has_zone(zone: StringName) -> bool:
	return zone == &"" or zone in ZONES[kind]


func centre_height() -> float:
	return head_height() * 0.5


## Its jack on its front (-Z), toward the ring's open side and the desk, so it is seen from where a
## player stands at it and from the seat: on a round one's shell below its head, out of its grip; on
## the cajón low on its stand's front, under the face that is struck.
func jack_point() -> Vector3:
	if kind == CAJON:
		return Vector3(0, float(_spec()["lift"]) * 0.45, -float(_spec()["depth"]) * 0.5 - 0.012 - JackSocket.REACH * 0.6)
	var at: Vector2 = _spec()["jack"]
	return Vector3(0, at.x, -at.y - JackSocket.REACH * 0.6)


func jack_out() -> Vector3:
	return Vector3.FORWARD


func _grip_middle() -> Vector3:
	var from: float = _spec().get("grip_from", 0.0)
	return Vector3(0, (from + head_height()) * 0.5, 0)


func _grip_shape() -> Shape3D:
	if kind == CAJON:
		var box := BoxShape3D.new()
		var face: Vector2 = _spec()["face"]
		box.size = Vector3(face.x + 0.02, head_height(), float(_spec()["depth"]) + 0.02)
		return box
	var s := CylinderShape3D.new()
	s.radius = head_radius() + 0.01
	s.height = head_height() - float(_spec().get("grip_from", 0.0))
	return s


func _build_body() -> Node3D:
	var root := Node3D.new()
	var scene := load(MODELS[kind]) as PackedScene
	if scene == null:
		return root
	var model := scene.instantiate() as Node3D
	var widen: float = _spec().get("widen", 1.0)
	model.scale = Vector3(widen, 1.0, widen)
	root.add_child(model)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(s)
			if m != null and LOOKS.has(m.resource_name):
				mesh.set_surface_override_material(s, _look(m.resource_name))
	return root


static var _looks: Dictionary = {}


static func _look(material: String) -> StandardMaterial3D:
	if not _looks.has(material):
		var m := StandardMaterial3D.new()
		m.albedo_color = LOOKS[material][0]
		m.roughness = LOOKS[material][1]
		_looks[material] = m
	return _looks[material]
