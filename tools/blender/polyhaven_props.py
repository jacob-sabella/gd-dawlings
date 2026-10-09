# Fetches the cabin's props from Poly Haven (CC0) and writes them, decimated, to assets/models/.
#
#     blender --background --python tools/blender/polyhaven_props.py
#
# Needs the network. The 1k glTF of each, through the Poly Haven API; decimated to what it is
# worth at the distance it is seen from, and written as one .glb with its textures inside.
#
#   Rockingchair_01 -> rocking_chair.glb   by the stove; half its faces
#   Lantern_01      -> lantern.glb         eight of them in the room, a hand high; 8% of its faces

import json
import os
import tempfile
import urllib.request

import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
PROPS = [("Rockingchair_01", "rocking_chair", 0.5), ("Lantern_01", "lantern", 0.08)]


# The API refuses Python's default User-Agent.
AGENT = {"User-Agent": "reaper-3d-props/1.0"}


def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers=AGENT)).read()


def fetch(asset, into):
    files = json.loads(get(f"https://api.polyhaven.com/files/{asset}"))
    gltf = files["gltf"]["1k"]["gltf"]
    main = os.path.join(into, f"{asset}.gltf")
    with open(main, "wb") as f:
        f.write(get(gltf["url"]))
    for rel, entry in gltf.get("include", {}).items():
        path = os.path.join(into, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(get(entry["url"]))
    return main


for asset, name, ratio in PROPS:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    with tempfile.TemporaryDirectory() as tmp:
        bpy.ops.import_scene.gltf(filepath=fetch(asset, tmp))
        for obj in bpy.data.objects:
            if obj.type == "MESH" and ratio < 1.0 and len(obj.data.polygons) > 2000:
                mod = obj.modifiers.new("decimate", "DECIMATE")
                mod.ratio = ratio
                bpy.context.view_layer.objects.active = obj
                bpy.ops.object.modifier_apply(modifier=mod.name)
            if obj.type == "MESH":
                print(f"{name}: {obj.name} {len(obj.data.polygons)} faces")
        out = os.path.join(ROOT, "assets/models", name + ".glb")
        bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_image_format="JPEG",
                                  export_jpeg_quality=88)
        print("wrote", out)
