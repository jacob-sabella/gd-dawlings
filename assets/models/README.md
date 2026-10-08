# Models

| File | What | Made |
|---|---|---|
| `palms.glb` | Two low-poly palms, one straight and one leaning (~240 tris each), origin at the foot of the trunk | Scripted in Blender 5.2 (bmesh: a tapered, ringed trunk on a curve plus arched fronds with sawtooth leaflets) and exported without materials. Godot rebuilds them with barycentric vertex colours for `neon_wire.gdshader` (`GridVenue.wireframe`), so the edges in the model are the lines you see. Keep them clean quads/tris. |
