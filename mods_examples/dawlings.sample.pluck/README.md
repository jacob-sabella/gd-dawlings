# dawlings.sample.pluck

The sample mod of `docs/mods.md` (section 3.5): a composite rack module built only from modules the game
already has (`builtin.plaits` -> `builtin.env` -> `builtin.vca`), a skin, and a preset that plays it from
the keys. It is data: no code, no model, no engine change. It is licensed CC0-1.0.

Install: copy this folder into the player's mods folder (`user://mods/`, on Linux
`~/.local/share/godot/app_userdata/<project>/mods/`) or into any folder named in `$DAWLINGS_MODS`
(colon separated). Start the game. PLUCK appears in the rack's ADD list under Voice, and "Pluck demo" among
the presets.

Take the folder away and a patch that used PLUCK keeps its plate as a labelled "not installed" plate, with its
place and cables; a guest without the mod sees the same plate and still hears the host.

The proof that this works is `_test_a_sample_mod_dropped_in_a_folder_appears_plays_saves_reloads_and_replicates`
(`tests/sample_mod_proof_tests.gd`). This folder is not exported with the game (`mods_examples/*` is in the export
filters).
