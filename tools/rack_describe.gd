extends SceneTree

## Prints the mod registry as `ModListing` rows, for tools/rack_describe.sh (see it for the flags). Runs
## under `godot --headless --script`, and brackets its output between `@@begin` and `@@end` lines so the
## wrapper can drop the engine's banner. The roots are the shipped folder and `$DAWLINGS_MODS`; the
## player's `user://mods/` only with `--user`, so a run never touches that folder by default.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var roots: Array[String] = ModRegistry.default_roots() if "--user" in args else _roots()
	var reg := ModRegistry.new()
	reg.scan(roots)
	var rows := ModListing.rows(reg)
	print("@@begin")
	if "--json" in args:
		print(JSON.stringify({"roots": roots, "mods": rows}, "  "))
	else:
		print("# status\tid\tversion\tlicence\tsource\tprovides\treason")
		for line in ModListing.to_lines(rows):
			print(line)
		print("# %d mods, %d unavailable" % [rows.size(), ModListing.unavailable_count(rows)])
	print("@@end")
	quit(1 if "--strict" in args and ModListing.unavailable_count(rows) > 0 else 0)


## The shipped root and the colon-separated `$DAWLINGS_MODS`, with no `user://`.
func _roots() -> Array[String]:
	var out: Array[String] = [ModRegistry.SHIPPED_ROOT]
	for p in OS.get_environment(ModRegistry.ENV).split(":", false):
		out.append(p.strip_edges())
	return out
