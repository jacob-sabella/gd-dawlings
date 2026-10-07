extends SceneTree

## Generate res://openxr_action_map.tres from Godot's own defaults.
##
##   godot --headless --path . --script tools/make_action_map.gd
##
## Generated rather than hand-written, and checked in rather than generated at run time. Both
## halves matter. Hand-writing a .tres full of interaction-profile paths is how you get a headset
## whose trigger silently does nothing -- the file is accepted, the binding just never matches.
## And OpenXR reads the action map before the first frame, so it cannot be built at startup.
##
## Re-run this after a Godot upgrade that adds controller profiles; the defaults move.

func _initialize() -> void:
	var map := OpenXRActionMap.new()
	map.create_default_action_sets()
	var err := ResourceSaver.save(map, "res://openxr_action_map.tres")
	if err != OK:
		printerr("could not save action map: %s" % error_string(err))
		quit(1)
		return
	print("action map written: %d action set(s), %d interaction profile(s)" % [
		map.get_action_set_count(), map.get_interaction_profile_count()])
	quit(0)
