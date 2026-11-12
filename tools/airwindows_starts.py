#!/usr/bin/env python3
"""Measures a starting point for every Airwindows effect that does nothing heard at its own defaults, and writes
core/music/rack/airwindows_starts.json, which tools/airwindows_mods.py lays over those defaults.

Many Airwindows effects ship neutral (no drive, no density, a filter wide open), so a module added at the plugin's
defaults changes nothing and seems broken. Each effect is rendered offline by the rack engine on a test signal
(two detuned saws, one a side, pulsed by a square LFO); the change is the difference from the dry signal, in dB
under it, on the worse channel. An effect whose defaults already change it by at least AUDIBLE dB is left alone.
For the others one knob at a time is moved, nearest positions first, and the first setting that is heard and keeps
the level within LEVEL dB is the effect's start; failing that two knobs together (an amount and its dry/wet, both
shipped at 0), then one knob letting the level move up to WIDE_LEVEL dB (a high-pass takes a saw's fundamental).
One where none is (a dither, an ultrasonic filter, a timer that flips the sides every few minutes) keeps its
defaults.

    python3 tools/airwindows_starts.py        # needs build/rack/rack (tools/rack_build.sh)
"""
import json
import os
import struct
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
RACK = os.path.join(ROOT, "build", "rack", "rack")
EFFECTS = os.path.join(ROOT, "core", "music", "rack", "airwindows.json")
OUT = os.path.join(ROOT, "core", "music", "rack", "airwindows_starts.json")
LETTERS = "abcdefghijkl"
AUDIBLE = -20.0  # dB of change under the dry signal that counts as heard
LEVEL = 6.0  # dB the level may move at a start
WIDE_LEVEL = 12.0  # dB it may move where nothing within LEVEL is heard
POSITIONS = [0.0, 0.25, 0.5, 0.75, 1.0]
SECONDS = 2.0
RATE = 48000

SOURCE = """bpm 120
clear
add osc vco
add osc2 vco
add lfo lfo
add amp vca
add amp2 vca
add out out
knob osc.wave 0.625
knob osc.tune 0.375
knob osc2.wave 0.625
knob osc2.tune 0.45
knob lfo.rate 0.60587
knob lfo.shape 0.7
knob amp.level 0.5
knob amp.curve 0.25
knob amp2.level 0.5
knob amp2.curve 0.25
knob out.level 0.5
cable osc.out amp.in
cable osc2.out amp2.in
cable lfo.out amp.cv
cable lfo.out amp2.cv
"""


def script(effect=None, knobs=None):
    s = SOURCE
    if effect is None:
        return s + "cable amp.out out.l\ncable amp2.out out.r\nrun %g\n" % SECONDS
    s += "add fx airwindows\nknob fx.effect %.9f\n" % effect
    for k, v in knobs.items():
        s += "knob fx.%s %.5f\n" % (k, v)
    return s + "cable amp.out fx.l\ncable amp2.out fx.r\ncable fx.l out.l\ncable fx.r out.r\nrun %g\n" % SECONDS


def render(text, tmp):
    fd, path = tempfile.mkstemp(suffix=".txt", dir=tmp)
    with os.fdopen(fd, "w") as f:
        f.write(text)
    wav = path[:-4] + ".wav"
    subprocess.run([RACK, "--render", wav, path], env=dict(os.environ, RACK_FLOAT="1"),
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    data = open(wav, "rb").read()
    os.remove(path)
    os.remove(wav)
    i, channels = 12, 2
    while i < len(data):
        cid, size = data[i:i + 4], struct.unpack("<I", data[i + 4:i + 8])[0]
        if cid == b"fmt ":
            channels = struct.unpack("<H", data[i + 10:i + 12])[0]
        if cid == b"data":
            a = np.frombuffer(data[i + 8:i + 8 + size], dtype=np.float32).astype(np.float64)
            return a.reshape(-1, channels)[RATE // 2:]
        i += 8 + size
    raise RuntimeError("no data in the render")


def measure(wet, dry):
    """The change (dB under dry, worse channel) and the level move (dB, the channel that moved most)."""
    n = min(len(wet), len(dry))
    wet, dry = wet[:n], dry[:n]
    if not np.isfinite(wet).all():
        return -999.0, 999.0
    change, level = [], []
    for c in (0, 1):
        d = np.sqrt((dry[:, c] ** 2).mean())
        change.append(20 * np.log10(np.sqrt(((wet[:, c] - dry[:, c]) ** 2).mean()) / d + 1e-12))
        level.append(20 * np.log10(np.sqrt((wet[:, c] ** 2).mean()) / d + 1e-12))
    return max(change), max(level, key=abs)


def main():
    if not os.path.exists(RACK):
        sys.exit("no rack engine at %s: run tools/rack_build.sh" % RACK)
    effects = json.load(open(EFFECTS))["effects"]
    tmp = tempfile.mkdtemp(prefix="aw_starts_")
    dry = render(script(), tmp)
    jobs = {}
    for i, e in enumerate(effects):
        pos = (i + 0.5) / len(effects)
        default = {LETTERS[j]: p["default"] for j, p in enumerate(e["params"][:len(LETTERS)])}
        jobs[(e["id"], None, None)] = script(pos, default)
        for k in default:
            for p in POSITIONS:
                if abs(p - default[k]) > 0.01:
                    jobs[(e["id"], k, p)] = script(pos, dict(default, **{k: p}))
    pool = ThreadPoolExecutor(os.cpu_count())
    heard = dict(zip(jobs, pool.map(lambda key: measure(render(jobs[key], tmp), dry), jobs)))
    defaults = {e["id"]: {LETTERS[j]: p["default"] for j, p in enumerate(e["params"][:len(LETTERS)])} for e in effects}
    quiet = [e for e in effects if heard[(e["id"], None, None)][0] < AUDIBLE]

    def ok(result, level):
        return result[0] >= AUDIBLE and abs(result[1]) <= level

    def single(eid, level):
        d = defaults[eid]
        tries = sorted((abs(p - d[k]), LETTERS.index(k), k, p) for k in d for p in POSITIONS if (eid, k, p) in heard)
        return next(({k: p} for _, _, k, p in tries if ok(heard[(eid, k, p)], level)), None)

    starts = {}
    for e in quiet:
        found = single(e["id"], LEVEL)
        if found is not None:
            starts[e["id"]] = found
    # Two knobs together, for what one alone did not wake.
    pairs = {}
    for i, e in enumerate(effects):
        eid = e["id"]
        if e not in quiet or eid in starts:
            continue
        d = defaults[eid]
        ks = list(d)
        for x in range(len(ks)):
            for y in range(x + 1, len(ks)):
                for px in POSITIONS:
                    for py in POSITIONS:
                        if abs(px - d[ks[x]]) > 0.01 and abs(py - d[ks[y]]) > 0.01:
                            pairs[(eid, ks[x], px, ks[y], py)] = script((i + 0.5) / len(effects), dict(d, **{ks[x]: px, ks[y]: py}))
    heard2 = dict(zip(pairs, pool.map(lambda key: measure(render(pairs[key], tmp), dry), pairs)))
    pool.shutdown()
    os.rmdir(tmp)
    kept = []
    for e in quiet:
        eid = e["id"]
        if eid in starts:
            continue
        d = defaults[eid]
        tries = sorted((abs(k[2] - d[k[1]]) + abs(k[4] - d[k[3]]), LETTERS.index(k[1]), LETTERS.index(k[3]), k)
                       for k in heard2 if k[0] == eid)
        found = next(({k[1]: k[2], k[3]: k[4]} for *_, k in tries if ok(heard2[k], LEVEL)), None)
        if found is None:
            found = single(eid, WIDE_LEVEL)
        if found is None:
            kept.append(eid)
            continue
        starts[eid] = found
    with open(OUT, "w") as f:
        f.write(json.dumps({
            "about": "Starting knob values for the Airwindows effects that do nothing heard at their own defaults; "
                     "measured by tools/airwindows_starts.py, laid over the defaults by tools/airwindows_mods.py.",
            "starts": starts,
            "neutral_by_design": kept}, indent=1, sort_keys=True) + "\n")
    print("%d effects: %d start moved, %d neutral by design: %s" % (len(effects), len(starts), len(kept), ", ".join(kept)))


if __name__ == "__main__":
    main()
