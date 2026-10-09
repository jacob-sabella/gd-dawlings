extends Node
## Draw where a person can walk in every venue, from above, as SVG: the floor you can walk on
## (green), what stands on it and stops you (red; orange for what you step up onto), the
## furniture (grey), the zones (blue outlines), and the mix position. For seeing at a glance
## where the room is tight.
##   godot --headless --path . tools/probe/walk_map.tscn -- [--out DIR]

const SCALE := 40.0
const VIEW := Rect2(-11, -6, 22, 15)


func _ready() -> void:
	var out_dir := OS.get_cache_dir().path_join("reaper-3d/tmp/walkmap")
	var argv := OS.get_cmdline_user_args()
	for i in argv.size():
		if argv[i] == "--out" and i + 1 < argv.size():
			out_dir = argv[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DAW.use(OfflineBackend.new())
	# A fresh layout, never the person's: a venue change here must not be saved over theirs.
	Session.layout = LayoutProfile.new()
	Session.layout.save_path = "user://walk_map_layout.cfg"
	var studio := Studio.new()
	studio.medium = Presentation.Medium.SCREEN
	add_child(studio)
	await get_tree().process_frame
	for id: StringName in Venue.IDS:
		for v in Venue.variant_titles(id).size():
			studio.set_venue(id, false, v)
			await get_tree().process_frame
			var path := out_dir.path_join("%s_%d.svg" % [id, v])
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_string(svg(studio, "%s, %s" % [id, Venue.variant_titles(id)[v]]))
			f.close()
			print(path)
	get_tree().quit()


func svg(studio: Studio, title: String) -> String:
	var w := studio.walker
	var s := PackedStringArray()
	s.append('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="%f %f %f %f">'
			% [VIEW.size.x * SCALE, VIEW.size.y * SCALE, VIEW.position.x, VIEW.position.y, VIEW.size.x, VIEW.size.y])
	s.append('<rect x="%f" y="%f" width="%f" height="%f" fill="#222"/>' % [VIEW.position.x, VIEW.position.y, VIEW.size.x, VIEW.size.y])
	for r: Rect2 in w.walkable:
		s.append('<rect x="%f" y="%f" width="%f" height="%f" fill="#2e6b3a"/>' % [r.position.x, r.position.y, r.size.x, r.size.y])
	for f in w.footprints():
		s.append(_box(f, "#999", 0.9))
	for f in w.fixed:
		var steppable: bool = f.get("top", Walker.SOLID_HEIGHT) <= Walker.STEP_HEIGHT
		s.append(_box(f, "#e8a33a" if steppable else "#d23c3c", 0.8))
	for id in studio.venue.zones():
		var b: AABB = studio.venue.zones()[id]
		s.append('<rect x="%f" y="%f" width="%f" height="%f" fill="none" stroke="#5aa0ff" stroke-width="0.05"/>'
				% [b.position.x, b.position.z, b.size.x, b.size.z])
	s.append('<circle cx="0" cy="%f" r="0.22" fill="#fff"/>' % Studio.MIX_POSITION_Z)
	s.append('<text x="%f" y="%f" font-size="0.6" fill="#fff">%s</text>' % [VIEW.position.x + 0.3, VIEW.position.y + 0.8, title])
	# A metre grid, so the gaps can be read.
	for x in range(int(VIEW.position.x), int(VIEW.end.x) + 1):
		s.append('<line x1="%d" y1="%f" x2="%d" y2="%f" stroke="#fff" stroke-opacity="0.08" stroke-width="0.02"/>' % [x, VIEW.position.y, x, VIEW.end.y])
	for y in range(int(VIEW.position.y), int(VIEW.end.y) + 1):
		s.append('<line x1="%f" y1="%d" x2="%f" y2="%d" stroke="#fff" stroke-opacity="0.08" stroke-width="0.02"/>' % [VIEW.position.x, y, VIEW.end.x, y])
	s.append("</svg>")
	return "\n".join(s)


func _box(f: Dictionary, colour: String, alpha: float) -> String:
	var h: Vector2 = f["h"]
	var c: Vector2 = f["c"]
	# Godot turns +x toward -z for a positive angle about Y; on this map (x right, z down) that is
	# an anticlockwise turn, which SVG writes as negative.
	return '<rect x="%f" y="%f" width="%f" height="%f" fill="%s" fill-opacity="%f" transform="translate(%f %f) rotate(%f)"/>' \
			% [-h.x, -h.y, h.x * 2.0, h.y * 2.0, colour, alpha, c.x, c.y, -rad_to_deg(f["a"])]
