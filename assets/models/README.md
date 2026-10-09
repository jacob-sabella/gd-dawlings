# Models

| File | What | Made |
|---|---|---|
| `palms.glb` | Two low-poly palms, one straight and one leaning (~240 tris each), origin at the foot of the trunk | Scripted in Blender 5.2 (bmesh: a tapered, ringed trunk on a curve plus arched fronds with sawtooth leaflets) and exported without materials. Godot rebuilds them with barycentric vertex colours for `neon_wire.gdshader` (`GridVenue.wireframe`), so the edges in the model are the lines you see. Keep them clean quads/tris. |
| `firs.glb` | Three low-poly snowy firs (250-400 faces), one unit tall, origin at the foot; materials `needles`, `snow`, `bark` | `tools/blender/firs.py`. The cabin's woods, as MultiMeshes. |
| `wood_stove.glb` | A cast-iron box stove, door to Blender -Y (Godot +Z); materials `iron`, `fire` | `tools/blender/wood_stove.py`. The cabin's corner. |
| `rocking_chair.glb` | Poly Haven `Rockingchair_01` (CC0), decimated to half | `tools/blender/polyhaven_props.py` |
| `lantern.glb` | Poly Haven `Lantern_01` (CC0), decimated to 8%; glass material `Lantern_01_glass` | `tools/blender/polyhaven_props.py`. |

Godot extracts the textures of the Poly Haven props beside them on import (`lantern_*`, `rocking_chair_*`). The scene it imports refers to them, so they are committed with the `.glb`; delete one and the model fails to load until it is imported afresh (delete its `.glb.import` too).
