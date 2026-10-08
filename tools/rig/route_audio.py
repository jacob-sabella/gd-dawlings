#!/usr/bin/env python3
"""Point a freshly started Reaper's outputs at a sink, and nowhere else.

    route_audio.py snapshot FILE            remember which Reaper nodes exist now
    route_audio.py route FILE SINK          route every Reaper node that is NOT in FILE to SINK

Why it is needed: the rig's Reaper is meant to play into a null sink, and PULSE_SINK says so --
but on a PipeWire machine with pipewire-jack installed, Reaper's default audio system is JACK,
JACK ignores PULSE_SINK, and Reaper auto-connects its outputs to the system playback ports.
Forty tracks of test tones out of the studio monitors is exactly what the rig promised never
to do. Routing at the graph is the one fix that holds whichever audio system Reaper picks.

The snapshot is what keeps this from touching YOUR Reaper: a node that existed before the rig
launched is not the rig's, and is left exactly as it was.
"""
import json
import re
import subprocess
import sys
import time

REAPER_NODE = re.compile(r"^REAPER(-\d+)?$")


def dump():
    return json.loads(subprocess.run(["pw-dump"], capture_output=True, text=True).stdout or "[]")


def reaper_nodes(objects):
    out = {}
    for o in objects:
        if o.get("type") != "PipeWire:Interface:Node":
            continue
        props = o.get("info", {}).get("props", {})
        if REAPER_NODE.match(props.get("node.name", "")):
            out[o["id"]] = props.get("node.name")
    return out


def main():
    mode, path = sys.argv[1], sys.argv[2]
    if mode == "snapshot":
        with open(path, "w") as f:
            json.dump(sorted(reaper_nodes(dump())), f)
        return 0
    sink = sys.argv[3]
    before = set(json.load(open(path))) if path else set()
    # The JACK client registers its ports a moment after the process starts.
    for _ in range(50):
        objects = dump()
        mine = {i: n for i, n in reaper_nodes(objects).items() if i not in before}
        outs = [o for o in objects if o.get("type") == "PipeWire:Interface:Port"
                and o["info"]["props"].get("node.id") in mine and o["info"]["direction"] == "output"]
        if len(outs) >= 2:
            break
        time.sleep(0.2)
    else:
        print("route_audio: no new Reaper outputs appeared", file=sys.stderr)
        return 1
    ports = {o["id"]: o for o in objects if o.get("type") == "PipeWire:Interface:Port"}
    outs.sort(key=lambda o: o["info"]["props"].get("port.id", 0))
    out_ids = {o["id"] for o in outs}
    for link in objects:
        if link.get("type") != "PipeWire:Interface:Link":
            continue
        if link["info"].get("output-port-id") in out_ids:
            subprocess.run(["pw-link", "-d", str(link["id"])], capture_output=True)
    sink_in = sorted((p for p in ports.values() if p["info"]["direction"] == "input"
                      and str(p["info"]["props"].get("object.path", "")).startswith(sink + ":")),
                     key=lambda p: p["info"]["props"].get("port.id", 0))
    for out, into in zip(outs[:2], sink_in[:2]):
        subprocess.run(["pw-link", str(out["id"]), str(into["id"])], capture_output=True)
    print("route_audio: %s -> %s" % (",".join(sorted(set(mine.values()))), sink))
    return 0


if __name__ == "__main__":
    sys.exit(main())
