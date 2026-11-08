class_name ModListing
extends RefCounted

## The mod registry as rows a person (the MODS screen) or a script (`tools/rack_describe.sh`) can read:
## one per mod folder, in registry order, then the folders that were refused. Pure data: it reads a
## ModRegistry and changes nothing, and a bad manifest or a missing binary is a row with a reason, never
## an error (docs/mods.md section 5).
##
## A row is `{id, name, version, licence, source, kind, status, reason, notes, folder}`. `status` is
## `ok` or `unavailable`; `reason` is "" for an ok mod and the sentence for an unavailable one; `notes`
## are the warnings and the entries that were dropped.

const OK := "ok"
const UNAVAILABLE := "unavailable"
## What a missing field shows as.
const NONE := "-"


## Every mod folder the registry read: the mods that parsed (available or not, in dependency order),
## then the folders it refused (a bad manifest, a reserved or repeated id).
static func rows(reg: ModRegistry) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in reg.mods():
		out.append(_row(m, _reason(reg, m), _notes(reg, m)))
	for r in reg.rejected():
		var m: ModManifest = r["manifest"]
		out.append(_row(m, "%s: %s" % [r["code"], r["reason"]], _warnings(m)))
	return out


## How many rows are unavailable.
static func unavailable_count(rows_: Array[Dictionary]) -> int:
	return rows_.filter(func(r: Dictionary) -> bool: return r["status"] == UNAVAILABLE).size()


## The source pin as one line: `submodule vendor/daisysp @ 2c72eaf`, `binary tool 1.2 sha 3fa9c1d2`, `in_tree
## core/built_in`, `data`, `user_installed`; "-" when the manifest did not say.
static func source_text(src: Dictionary) -> String:
	match str(src.get("kind", "")):
		"submodule":
			return "submodule %s @ %s" % [src.get("path", "?"), src.get("commit", "?")]
		"binary":
			return "binary %s %s sha %s" % [src.get("file", "?"), src.get("version", "?"), str(src.get("sha256", "?")).left(8)]
		"in_tree":
			return "in_tree %s" % src.get("path", "?")
		"":
			return NONE
	return str(src["kind"])


## What the mod provides, counted by entry kind: `rack_module x3, rack_preset x1`; "-" when it
## provides nothing readable.
static func kind_text(m: ModManifest) -> String:
	var counts := {}
	for e in m.entries:
		counts[str(e.get("kind", "?"))] = int(counts.get(str(e.get("kind", "?")), 0)) + 1
	var parts: Array[String] = []
	for k in counts:
		parts.append("%s x%d" % [k, counts[k]])
	return ", ".join(parts) if not parts.is_empty() else NONE


## The rows as text, one line each, tab separated: `status id version licence source kind reason`.
static func to_lines(rows_: Array[Dictionary]) -> PackedStringArray:
	var out := PackedStringArray()
	for r in rows_:
		out.append("\t".join([r["status"], r["id"], r["version"], r["licence"], r["source"], r["kind"], r["reason"]]))
	return out


static func _row(m: ModManifest, reason: String, notes: Array[String]) -> Dictionary:
	return {
		"id": m.id,
		"name": m.mod_name if m.mod_name != "" else m.id,
		"version": m.version if m.version != "" else NONE,
		"licence": str(m.licence.get("spdx", NONE)),
		"source": source_text(m.source),
		"kind": kind_text(m),
		"status": UNAVAILABLE if reason != "" else OK,
		"reason": reason,
		"notes": notes,
		"folder": m.folder,
	}


## The sentences for a mod that parsed but is unavailable (a missing dependency, a missing binary...).
static func _reason(reg: ModRegistry, m: ModManifest) -> String:
	if m.status == ModManifest.STATUS_OK:
		return ""
	var why: Array[String] = []
	for p in reg.problems():
		if p.mod == m.id and p.entry == "" and p.is_error():
			why.append("%s: %s" % [p.code, p.message])
	return "; ".join(why) if not why.is_empty() else "unavailable"


## The mod's warnings, and a note for each entry that was dropped (a type collision, a bad composite).
static func _notes(reg: ModRegistry, m: ModManifest) -> Array[String]:
	var out: Array[String] = []
	for p in reg.problems():
		if p.mod == m.id and (not p.is_error() or p.entry != ""):
			out.append(_note(p))
	return out


static func _warnings(m: ModManifest) -> Array[String]:
	var out: Array[String] = []
	for p in m.problems:
		if not p.is_error():
			out.append(_note(p))
	return out


static func _note(p: ModProblem) -> String:
	return "%s: %s" % [p.code, p.message]
