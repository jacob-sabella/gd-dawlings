class_name ShotDrive
extends RefCounted

## The scripted hand: dragging, the bead aim, turning a wheel and pointing at a control by its title, per physics tick.
## Moved out of `tools/screenshot.gd` without change of behaviour; the state stays on the autoload, which keeps a one-line delegate for each name another file or a string reaches.

var shot: Screenshot


func _init(of: Screenshot) -> void:
	shot = of


## Driven on physics ticks, not rendered frames. Captures run with vsync off, so hundreds of
## frames are drawn per tick, and a drag paced by frames was over before the interactor -- which
## reads its button on the physics tick, like every hand -- had looked once.
func _physics_process(_delta: float) -> void:
	shot._ticks += 1
	if not shot._drags.is_empty():
		_drive_drag()
	_drive_scripted()
	_drive_bead()
	if shot._lob.size() == 4 and shot._ticks == shot._lob_tick:
		var studio := shot.get_tree().current_scene.get_node_or_null("Studio")
		var hand := studio.get_node_or_null("MouseHand") as MouseInteractor if studio else null
		if hand != null and hand.carrying is Item:
			var from := hand.carry_pose().origin
			var to := Vector3(shot._lob[0], shot._lob[1], shot._lob[2])
			hand.throw_item(ItemRoom.lob(from, to, shot._lob[3]), Vector3.ZERO)
		shot.stepping._watch_the_throw(studio)
	if shot._throw.y > 0 and shot._ticks == int(shot._throw.y):
		var studio := shot.get_tree().current_scene.get_node_or_null("Studio")
		var hand := studio.get_node_or_null("MouseHand") as MouseInteractor if studio else null
		if hand != null:
			# Aimed at the middle of the view, not wherever the window's cursor was left.
			if hand.pointer_override.x < 0.0 and hand.camera != null:
				hand.pointer_override = hand.camera.get_viewport().get_visible_rect().size * 0.5
			hand.throw_with(shot._throw.x)
		shot.stepping._watch_the_throw(studio)
	if shot._shot_tick >= 0 and shot._ticks == shot._shot_tick:
		shot._shot_frame = shot._frames + 2
		if shot._quit_tick < 0:
			shot._quit_after = shot._frames + 6
	if shot._quit_tick > 0 and shot._ticks >= shot._quit_tick and shot._ticks > shot._shot_tick:
		shot.get_tree().quit()


func _drive_drag() -> void:
	var hands := shot.get_tree().root.find_children("*", "MouseInteractor", true, false)
	if hands.is_empty():
		return
	var hand := hands[0] as MouseInteractor
	for drag in shot._drags:
		var first: int = drag[2]
		var last: int = drag[3]
		if shot._ticks == last + 1:
			hand.press_override = 0
		if shot._ticks < first or shot._ticks > last:
			continue
		var t := float(shot._ticks - first) / float(maxi(1, last - first))
		hand.pointer_override = (drag[0] as Vector2).lerp(drag[1], t)
		hand.press_override = 1
		if shot._turn != 0 and shot._ticks == (first + last) / 2:
			_wheel(hand)


## `--bead`: on its tick the shown bead's place on the screen, and from two ticks on the button
## down on it and the pointer up and down from there, 70 px each way every 1.2 s, drifting down.
func _drive_bead() -> void:
	var hand := _scripted_hand()
	if hand == null or shot._bead_aim == "" or shot._ticks < shot._bead_tick:
		return
	var camera := shot.get_viewport().get_camera_3d()
	if shot._ticks == shot._bead_tick:
		if hand.bead != null and hand.bead.shown() and camera != null:
			shot._bead_from = camera.unproject_position(hand.bead.global_position)
			hand.pointer_override = shot._bead_from
			shot._hover = shot._bead_from
			print("SHOT_BEAD over %s at %s" % [hand.bead.control.title(), shot._bead_from])
		else:
			push_warning("SHOT: no bead shown over %s" % shot._bead_aim)
		return
	if shot._bead_from.x < 0.0:
		return
	var t := float(shot._ticks - shot._bead_tick - 2) / 60.0
	hand.pointer_override = shot._bead_from + Vector2(0, -70.0 * sin(TAU * t / 1.2) + 50.0 * minf(t, 1.0))
	hand.press_override = 1 if shot._ticks >= shot._bead_tick + 2 else 0


func _wheel(hand: MouseInteractor) -> void:
	for n in absi(shot._turn):
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP if shot._turn > 0 else MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		wheel.position = hand.pointer_override
		shot.get_viewport().push_input(wheel)


func _scripted_hand() -> MouseInteractor:
	var hands := shot.get_tree().root.find_children("*", "MouseInteractor", true, false)
	return hands[0] as MouseInteractor if not hands.is_empty() else null


## The control whose title is this -- exactly if one is, else the first that contains it.
func _control_called(title: String) -> ControlAffordance:
	# `_` for a space: SHOT_ARGS is split on whitespace, and titles are "TRACK  CONTROL".
	# `+` joins pieces that must all appear, for titles with a part too awkward to spell in a
	# shell word: LEAD_VOX__REACOMP+POWER finds "LEAD VOX  REACOMP (COCKOS)  POWER".
	title = title.replace("_", " ")
	var pieces := title.to_upper().split("+")
	var loose: ControlAffordance = null
	var stack: Array = [shot.get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is ControlAffordance and (n as Node3D).is_visible_in_tree():
			var t: String = (n as ControlAffordance).title()
			if t == title:
				return n
			if loose == null and Array(pieces).all(func(piece): return t.to_upper().contains(piece)):
				loose = n
	return loose


func _screen_of(title: String) -> Vector2:
	var c := _control_called(title)
	var camera := shot.get_viewport().get_camera_3d()
	if c == null or camera == null:
		if c == null:
			push_warning("SHOT: no control called %s" % title)
		return Vector2(-1, -1)
	var centre := c.global_position
	for child in c.get_children():
		if child is CollisionShape3D:
			centre = (child as CollisionShape3D).global_position
			break
	if OS.get_cmdline_user_args().has("--shot-debug"):
		print("SHOT_AIM %s -> %s at %s (world %s, cam-local %s)" % [title, c.get_path(), camera.unproject_position(centre), centre, camera.global_transform.affine_inverse() * centre])
	return camera.unproject_position(centre)


func _drive_scripted() -> void:
	var hand := _scripted_hand()
	if hand == null:
		return
	for click in shot._clicks:
		if shot._ticks == click[1]:
			hand.pointer_override = _screen_of(click[0])
			print("SHOT_CLICK %s at %s" % [click[0], hand.pointer_override])
		if shot._ticks >= click[1] and shot._ticks < click[1] + 4:
			hand.press_override = 1
		elif shot._ticks == click[1] + 4:
			hand.press_override = 0
	for pull in shot._pulls:
		var a: int = pull[2]
		var b: int = pull[3]
		if shot._ticks == a - 2:
			pull.append(_screen_of(pull[0]))
			hand.pointer_override = pull[4]
		if shot._ticks >= a and shot._ticks <= b and pull.size() > 4:
			var t := float(shot._ticks - a) / float(maxi(1, b - a))
			hand.pointer_override = (pull[4] as Vector2) + (pull[1] as Vector2) * t
			hand.press_override = 1
		elif shot._ticks == b + 1:
			hand.press_override = 0
