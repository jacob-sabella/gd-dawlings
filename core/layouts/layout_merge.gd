class_name LayoutMerge
extends RefCounted

## How layout pieces of data combine (docs/layouts.md section 5.1): a fragment under a venue, a
## variant over its base. Pure functions on plain dictionaries; nothing here reads a file.
##
## The rule: objects merge key by key, and a key whose value is null in the override is removed.
## The lists `pieces` and `groups` merge by `id` and `wiring` by `kind|from|to`: an entry already
## there is merged into, a new one is appended, order is kept. Every other list replaces. An entry
## with `enabled: false` stays through merging (so a later fragment can switch it on again) and is
## taken out by `settle`. A placement (`at`) is one thing and replaces whole, so an override can
## swap an anchor placement for a frame one without leaving half of each.

## The keys of a layout body that merge as lists, and what identifies an entry.
const LIST_KEYS: Array[String] = ["pieces", "groups", "wiring"]
## Keys whose object value replaces instead of merging.
const ATOMIC_KEYS: Array[String] = ["at"]
## Places a wire may point at that are not pieces.
const WIRE_AREAS: Array[String] = ["live_room", "control_room"]


## `base` with `over` merged on top; neither is changed.
static func merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for key in over.keys():
		var v: Variant = over[key]
		if v == null:
			out.erase(key)
		elif v is Array and out.get(key) is Array and key in LIST_KEYS:
			out[key] = _merge_list(str(key), out[key], v)
		elif v is Dictionary:
			# Merged into what is there, or into nothing (which still drops its null keys).
			out[key] = merge(out[key] if out.get(key) is Dictionary and not key in ATOMIC_KEYS else {}, v)
		else:
			out[key] = v.duplicate(true) if v is Array else v
	return out


## The identity of a list entry under `key`: its id, or kind|from|to for a wire; "" if it has none.
static func identity(key: String, entry: Variant) -> String:
	if not entry is Dictionary:
		return ""
	if key == "wiring":
		return "%s|%s|%s" % [entry.get("kind", ""), entry.get("from", ""), entry.get("to", "")]
	return str(entry.get("id", ""))


## Takes out what `enabled: false` switched off, and with it every group member and wire that named
## a removed piece. Changes `body` and returns the removed piece ids.
static func settle(body: Dictionary) -> Array[String]:
	var gone: Array[String] = []
	var kept: Array = []
	for p: Dictionary in body.get("pieces", []):
		if p.get("enabled", true) == false:
			gone.append(str(p.get("id", "")))
		else:
			kept.append(p)
	if body.has("pieces"):
		body["pieces"] = kept
	var wires: Array = []
	for w: Dictionary in body.get("wiring", []):
		if w.get("enabled", true) != false and str(w.get("from", "")) not in gone and str(w.get("to", "")) not in gone:
			wires.append(w)
	if body.has("wiring"):
		body["wiring"] = wires
	for g: Dictionary in body.get("groups", []):
		if g.get("members") is Array:
			g["members"] = (g["members"] as Array).filter(func(m: Variant) -> bool: return str(m) not in gone)
	return gone


static func _merge_list(key: String, a: Array, b: Array) -> Array:
	var out := a.duplicate(true)
	var at := {}
	for i in out.size():
		at[identity(key, out[i])] = i
	for entry: Variant in b:
		var k := identity(key, entry)
		if k != "" and at.has(k):
			out[at[k]] = merge(out[at[k]], entry)
		else:
			at[k] = out.size()
			out.append(entry.duplicate(true) if entry is Dictionary else entry)
	return out
