class_name RackJack
extends ModularJack

## A jack on the modular room's rack: the same socket and gesture as the old wall's, named from the
## rack's catalogue and whose patch it sits in.

var type_title := ""
var wall_patch: Dictionary = {}


static func make(path: String, is_output: bool, title: String) -> RackJack:
	var j := RackJack.new()
	j.jack = StringName(path)
	j.output = is_output
	j.type_title = title
	j.name = "Jack_%s" % path.replace(".", "_")
	return j


func _default_title() -> String:
	var port := String(jack).get_slice(".", 1).to_upper()
	return "RACK  %s %s %s" % [type_title, port, "OUT" if output else "IN"]


func _default_readout() -> String:
	if plugged_to.is_empty():
		return "not patched"
	var names := plugged_to.map(func(j: StringName) -> String: return String(j).to_upper())
	return ("to %s" if output else "from %s") % ", ".join(names)


func hint() -> String:
	if output:
		return "drag to an input to patch a cable · an output feeds as many as you like"
	if plugged_to.is_empty():
		return "drag to an output to patch a cable into it"
	return "drag its plug to another input, or off the jacks to pull it out · inputs add what is patched into them"
