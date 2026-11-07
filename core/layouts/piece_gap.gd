class_name PieceGap
extends Node3D

## The stand-in for a piece a room has that this build cannot make (docs/layouts.md 7, "Sharing"): the host
## added a piece of a kind whose mod this player lacks, or a newer game's. It mirrors the rack's unavailable
## plate (`RackGaps`): a flat pad the size of the piece's declared footprint and a small plate on a post
## that names it, "<NAME> not installed", with the mod and version beneath when the entry says them
## (`uses: {mod, version, title}`). It is in the piece's place and nothing else: no trolley, nothing to
## push or walk into, no sound. The entry stays in the room's delta untouched, so nothing is lost: the
## host can still take it out, and a player who installs the mod sees the real piece next time.

## The pad's colour and the plate's.
const PAD := Color(0.30, 0.30, 0.33)
const PLATE := Color(0.12, 0.12, 0.14)
const POST_HEIGHT := 0.7
## Used when the entry names no footprint (half extents, m).
const DEFAULT_HALF := Vector2(0.25, 0.25)

## The entry's piece kind and what the plate says.
var kind: StringName = &""
var words := ""


## A stand-in for room-delta entry `entry` (`{id, piece, footprint?, uses?}`).
static func for_entry(entry: Dictionary) -> PieceGap:
	var gap := PieceGap.new()
	gap.kind = StringName(entry.get("piece", ""))
	gap.name = RoomSync.node_name(StringName(entry.get("id", "")))
	var uses: Dictionary = entry["uses"] if entry.get("uses") is Dictionary else {}
	gap.words = words_for(gap.kind, uses)
	gap._build(entry.get("footprint"))
	return gap


## "GONG not installed" and, under it, "dawlings.gong 1.0.0" when the entry says which mod.
static func words_for(piece: StringName, uses: Dictionary) -> String:
	var title := String(uses.get("title", ""))
	if title == "":
		title = LayoutChecks.name_of(String(piece).get_slice(".", String(piece).get_slice_count(".") - 1))
	var text := "%s not installed" % title.to_upper()
	var mod := String(uses.get("mod", ""))
	if mod != "":
		text += "\n%s" % ("%s %s" % [mod, uses.get("version", "")]).strip_edges()
	return text


func _build(footprint: Variant) -> void:
	var half := DEFAULT_HALF
	if footprint is Array and footprint.size() >= 2 and (footprint as Array).all(func(v: Variant) -> bool: return (v is float or v is int) and is_finite(float(v))):
		half = Vector2(clampf(absf(float(footprint[0])), 0.05, 3.0), clampf(absf(float(footprint[1])), 0.05, 3.0))
	var pad := MeshInstance3D.new()
	pad.name = "Pad"
	var pad_mesh := BoxMesh.new()
	pad_mesh.size = Vector3(half.x * 2.0, 0.01, half.y * 2.0)
	pad.mesh = pad_mesh
	pad.position = Vector3(0, 0.005, 0)
	pad.material_override = _flat(PAD)
	add_child(pad)
	var post := MeshInstance3D.new()
	post.name = "Post"
	var rod := CylinderMesh.new()
	rod.top_radius = 0.008
	rod.bottom_radius = 0.008
	rod.height = POST_HEIGHT
	post.mesh = rod
	post.position = Vector3(0, POST_HEIGHT * 0.5, 0)
	post.material_override = _flat(PLATE)
	add_child(post)
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(0.36, 0.12, 0.01)
	plate.mesh = plate_mesh
	plate.position = Vector3(0, POST_HEIGHT + 0.06, 0)
	plate.material_override = _flat(PLATE)
	add_child(plate)
	var label := Label3D.new()
	label.name = "Words"
	label.text = words
	label.font_size = 28
	label.pixel_size = 0.0016
	label.modulate = Color(0.92, 0.9, 0.84)
	label.position = Vector3(0, POST_HEIGHT + 0.06, 0.007)
	add_child(label)


static func _flat(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.9
	return m
