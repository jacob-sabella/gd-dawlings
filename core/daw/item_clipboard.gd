class_name ItemClipboard
extends RefCounted

## What a player copied, as plain data the host keeps for them (DAW.copy_items): each clip packed
## as a cassette packs one (MixWire.pack_item), with how far it sits from the copy's top track and
## from its earliest start. A paste lays the same shape down somewhere else. Static: the keeping,
## and whose it is, are DAW's.


## Entries {row, at, packed, name} for `targets` ([track, index, start, length]), in their order.
## `row` counts along state.track_indices() from the topmost target's track, `at` is seconds after
## the earliest target's start. Empty when any target's track or item is not there.
static func capture(state: MixState, targets: Array) -> Array:
	if state == null or targets.is_empty():
		return []
	var order := state.track_indices()
	var top := -1
	var earliest := INF
	for target: Array in targets:
		var row := order.find(int(target[0]))
		var item := state.item(int(target[0]), int(target[1]))
		if row < 0 or item == null:
			return []
		top = row if top < 0 else mini(top, row)
		earliest = minf(earliest, item.start)
	var out: Array = []
	for target: Array in targets:
		var item := state.item(int(target[0]), int(target[1]))
		out.append({"row": order.find(int(target[0])) - top, "at": item.start - earliest,
				"packed": MixWire.pack_item(item, state.track(int(target[0])).part), "name": item.name})
	return out


## Where `entries` land with their top track at `track` and their earliest start at `seconds`:
## [[track, start, packed], ...] in their order. Empty when `track` is not there or any row falls
## past the last track, because half a paste is worse than none.
static func plan(entries: Array, state: MixState, track: int, seconds: float) -> Array:
	if state == null or entries.is_empty():
		return []
	var order := state.track_indices()
	var base := order.find(track)
	if base < 0:
		return []
	var out: Array = []
	for entry: Dictionary in entries:
		var row := base + int(entry["row"])
		if row >= order.size():
			return []
		out.append([int(order[row]), maxf(seconds, 0.0) + float(entry["at"]), entry["packed"]])
	return out
