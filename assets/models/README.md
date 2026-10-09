# Models

| File | What | Made |
|---|---|---|
| `palms.glb` | Two low-poly palms, one straight and one leaning (~240 tris each), origin at the foot of the trunk | Scripted in Blender 5.2 (bmesh: a tapered, ringed trunk on a curve plus arched fronds with sawtooth leaflets) and exported without materials. Godot rebuilds them with barycentric vertex colours for `neon_wire.gdshader` (`GridVenue.wireframe`), so the edges in the model are the lines you see. Keep them clean quads/tris. |
| `firs.glb` | Three low-poly snowy firs (250-400 faces), one unit tall, origin at the foot; materials `needles`, `snow`, `bark` | `tools/blender/firs.py`. The cabin's woods, as MultiMeshes. |
| `jar.glb` | A lathed preserving jar with a screw lid, 0.1 m across and 0.16 m tall, origin on the bottom; materials `glass`, `lid` | `tools/blender/jar.py`. The cabin's shelf, as MultiMeshes. |
| `water_tank.glb` | A city roof's wooden water tank: a cedar barrel bound with steel hoops, a conical cap, six steel legs and a caged ladder on Blender -Y (Godot +Z); 3.4 m across, 6.6 m tall, origin on the roof; materials `staves`, `steel`, `cap` | `tools/blender/water_tank.py`. The rooftop's two tanks. |
| `hatch.glb` | A pressure hatch's frame: square outside, rounded inside, hazard-striped reveal and a lamp bar over it; 2.0 × 2.7 m outside, a 1.4 × 2.25 m opening, 0.36 m deep, origin on the floor; materials `frame`, `hazard`, `lamp` | `tools/blender/hatch.py`. The station's two hatches. |
| `kelp.glb` | One stalk of giant kelp: a holdfast, a 7.2 m stipe with a lazy S in it, and twenty blades on gas floats turning round it as it climbs; origin on the sand under the holdfast; materials `stipe`, `blade` | `tools/blender/kelp.py`. The dome's forest, one MultiMesh, swayed by `kelp.gdshader`. |
| `minisub.glb` | A two-seat research submersible: a round hull with an acrylic bubble bow, a sail with its hatch, ducted thrusters aft, skids, lamps either side of the bubble, and a docking collar on its flank; 3.4 m hull, bow at +X, collar at +Z, origin the hull's centre; materials `hull`, `glass`, `dark`, `steel`, `lamp` | `tools/blender/minisub.py`. Docked at the dome beside the booth. |
| `wood_stove.glb` | A cast-iron box stove, door to Blender -Y (Godot +Z); materials `iron`, `fire` | `tools/blender/wood_stove.py`. The cabin's corner. |
| `rocking_chair.glb` | Poly Haven `Rockingchair_01` (CC0), decimated to half | `tools/blender/polyhaven_props.py` |
| `lantern.glb` | Poly Haven `Lantern_01` (CC0), decimated to 8%; glass material `Lantern_01_glass` | `tools/blender/polyhaven_props.py`. |

Godot extracts the textures of the Poly Haven props beside them on import (`lantern_*`, `rocking_chair_*`). The scene it imports refers to them, so they are committed with the `.glb`; delete one and the model fails to load until it is imported afresh (delete its `.glb.import` too).
