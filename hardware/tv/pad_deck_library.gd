class_name PadDeckLibrary
extends RefCounted

## The sample and kit library on the deck: browsing, saving, loading and deleting a sample or a kit. Moved out of
## `hardware/tv/pad_deck.gd` without change of behaviour.

var deck: PadDeck


func _init(of: PadDeck) -> void:
	deck = of


func _browsed_words() -> String:
	var all := PadLibrary.kits() if deck._browsed == "kit" else PadLibrary.samples()
	var at := deck.lib_kit if deck._browsed == "kit" else deck.lib_sample
	if deck._browsed == "" or at < 0 or at >= all.size():
		return ""
	return "%s %s" % ["KIT" if deck._browsed == "kit" else "LIB", all[at]]


func _base_name() -> String:
	return deck.tv.title if deck.tv != null and deck.tv.title != "" else "sample"


func save_to_library() -> void:
	var sound := deck.bank.slice_frames(deck.selected)
	if sound.is_empty():
		deck.said.emit("Pad %d has no sound to keep." % (deck.selected + 1))
		return
	var name := PadLibrary.fresh("%s_pad%d" % [_base_name(), deck.selected + 1], PadLibrary.samples())
	if PadLibrary.save_sample(name, sound):
		deck.lib_sample = PadLibrary.samples().find(name)
		deck._browsed = "sample"
		deck.said.emit("Kept pad %d as sample \"%s\" (%d in your library)." % [deck.selected + 1, name, PadLibrary.samples().size()])
	else:
		deck.said.emit("The sample could not be saved.")
	deck.refresh()


func step_library() -> void:
	var all := PadLibrary.samples()
	deck._del_armed = false
	if all.is_empty():
		deck.said.emit("Your library has no samples yet: SAVE keeps the selected pad.")
		return
	deck.lib_sample = (deck.lib_sample + 1) % all.size()
	deck._browsed = "sample"
	deck.said.emit("Sample %d of %d: \"%s\" (LOAD puts it on pad %d)." % [deck.lib_sample + 1, all.size(), all[deck.lib_sample], deck.selected + 1])
	deck.refresh()


func load_from_library() -> void:
	var all := PadLibrary.samples()
	if deck.lib_sample < 0 or deck.lib_sample >= all.size():
		deck.said.emit("Browse a sample first: LIB.")
		return
	var sound := PadLibrary.load_sample(all[deck.lib_sample])
	if sound.is_empty():
		deck.said.emit("That sample would not load.")
		return
	deck.bank.put(deck.selected, sound)
	deck._made_here()
	deck.said.emit("Pad %d plays \"%s\"." % [deck.selected + 1, all[deck.lib_sample]])
	deck.refresh()


func save_kit() -> void:
	var name := PadLibrary.save_kit(PadLibrary.fresh("kit", PadLibrary.kits()), deck.bank, _base_name())
	if name == "":
		deck.said.emit("There is no sample on the pads to keep as a kit.")
		return
	deck.lib_kit = PadLibrary.kits().find(name)
	deck._browsed = "kit"
	deck.said.emit("Kept the pads as kit \"%s\" (%d kits)." % [name, PadLibrary.kits().size()])
	deck.refresh()


func step_kits() -> void:
	var all := PadLibrary.kits()
	deck._del_armed = false
	if all.is_empty():
		deck.said.emit("You have no kits yet: KSAVE keeps the pads as one.")
		return
	deck.lib_kit = (deck.lib_kit + 1) % all.size()
	deck._browsed = "kit"
	deck.said.emit("Kit %d of %d: \"%s\" (KLOAD puts it on the pads)." % [deck.lib_kit + 1, all.size(), all[deck.lib_kit]])
	deck.refresh()


func load_kit() -> void:
	var all := PadLibrary.kits()
	if deck.lib_kit < 0 or deck.lib_kit >= all.size():
		deck.said.emit("Browse a kit first: KITS.")
		return
	deck.stop_all()
	var filled := PadLibrary.load_kit(all[deck.lib_kit], deck.bank)
	if filled == 0:
		deck.said.emit("That kit would not load (its samples are gone?).")
		return
	deck._made_here()
	deck.said.emit("Kit \"%s\" is on the pads (%d sounds)." % [all[deck.lib_kit], filled])
	deck.refresh()


func delete_browsed() -> void:
	var is_kit := deck._browsed == "kit"
	var all := PadLibrary.kits() if is_kit else PadLibrary.samples()
	var at := deck.lib_kit if is_kit else deck.lib_sample
	if deck._browsed == "" or at < 0 or at >= all.size():
		deck.said.emit("Browse a sample (LIB) or a kit (KITS) first.")
		return
	if not deck._del_armed:
		deck._del_armed = true
		deck.said.emit("Press DEL again to delete %s \"%s\" for good." % ["kit" if is_kit else "sample", all[at]])
		return
	deck._del_armed = false
	var ok := PadLibrary.delete_kit(all[at]) if is_kit else PadLibrary.delete_sample(all[at])
	if is_kit:
		deck.lib_kit = mini(deck.lib_kit, PadLibrary.kits().size() - 1)
	else:
		deck.lib_sample = mini(deck.lib_sample, PadLibrary.samples().size() - 1)
	deck.said.emit("Deleted \"%s\"." % all[at] if ok else "Could not delete it.")
	deck.refresh()
