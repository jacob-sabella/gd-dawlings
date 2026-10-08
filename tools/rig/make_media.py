#!/usr/bin/env python3
"""Stems for the live rig's session: short loops with real level on them, so meters move,
and distinct enough per track that a fader moved on the wrong track is audible in the meters.
Mono 16-bit 44.1k, 8 seconds each, looped by the items that use them."""
import math, os, random, struct, sys, wave

RATE = 44100
SECONDS = 8.0
out = sys.argv[1]
os.makedirs(out, exist_ok=True)


def write(name, fn):
    path = os.path.join(out, name + ".wav")
    if os.path.exists(path):
        return
    n = int(RATE * SECONDS)
    frames = bytearray()
    for i in range(n):
        v = max(-1.0, min(1.0, fn(i / RATE)))
        frames += struct.pack("<h", int(v * 32000))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(bytes(frames))


beat = 60.0 / 120.0
rnd = random.Random(3)
noise = [rnd.uniform(-1, 1) for _ in range(RATE)]

write("kick", lambda t: math.sin(2 * math.pi * 55 * (t % beat) * (1 + 3 * math.exp(-(t % beat) * 30))) * math.exp(-(t % beat) * 9) * 0.9)
write("snare", lambda t: noise[int(t * RATE) % RATE] * math.exp(-((t - beat) % (2 * beat)) * 14) * 0.6)
write("hat", lambda t: noise[int(t * RATE * 3) % RATE] * math.exp(-(t % (beat / 2)) * 40) * 0.35)
write("bass", lambda t: math.sin(2 * math.pi * [55, 55, 73.4, 65.4][int(t / (beat * 4)) % 4] * t) * 0.6)
write("pad", lambda t: sum(math.sin(2 * math.pi * f * t) for f in (220, 277.2, 329.6)) * 0.18)
write("lead", lambda t: math.sin(2 * math.pi * [440, 494, 523, 587][int(t / beat) % 4] * t) * (0.5 if (t % beat) < beat * 0.7 else 0.05))
write("vox", lambda t: math.sin(2 * math.pi * 330 * t + 4 * math.sin(2 * math.pi * 5 * t)) * 0.4 * (0.5 + 0.5 * math.sin(2 * math.pi * 0.25 * t)))
write("gtr", lambda t: math.copysign(1, math.sin(2 * math.pi * 196 * t)) * 0.25 * math.exp(-(t % (beat * 2)) * 2))
print("media ok")
