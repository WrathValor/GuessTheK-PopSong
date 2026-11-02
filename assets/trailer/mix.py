# Lays the SFX on the trailer timeline and joins the scenes.  python3 mix.py -> trailer.mp4
import os, wave, subprocess
import numpy as np
from trailer import SCENES
HERE = os.path.dirname(os.path.abspath(__file__)); SR = 44100
def load(n):
    with wave.open(os.path.join(HERE, "sfx", n + ".wav")) as w:
        return np.frombuffer(w.readframes(w.getnframes()), np.int16).reshape(-1, 2).astype(float) / 32767
total = sum(d for _, d, _ in SCENES)
start = {}; s = 0.0
for n, d, _ in SCENES: start[n] = s; s += d
CUES = {  # scene: [(t within scene, sound, gain)]
  "hook": [(0.0, "tick", .7), (0.33, "tick", .7), (0.66, "tick", .8), (1.0, "tick", .9), (0.25, "riser", .8), (1.25, "impact", 1.0)],
  "panic": [(0.0, "impact", 1.0), (0.02, "buzzer", .7), (0.05, "whoosh", .7), (0.7, "pop", .7)],
  "title": [(0.0, "whoosh", .7), (0.1, "impact", .8), (0.5, "impact", 1.0), (0.9, "impact", .9)],
  "tiers": [(0.0, "whoosh", .6), (0.2, "pop", .6)] + [(0.6 + 0.26 * i, "tick", .8) for i in range(5)] + [(2.0, "ding", .9), (2.0, "pop", .6)],
  "answers": [(0.0, "whoosh", .6), (0.0, "pop", .5)] + [(0.15 + 0.18 * i, "pop", .7) for i in range(4)] + [(1.6, "ding", 1.0), (1.7, "coin", .7)],
  "duel": [(0.0, "pop", .8), (0.25, "pop", .8), (0.3, "riser", .8), (1.3, "impact", 1.0), (1.3, "zap", .9), (1.3, "crowd", .7), (1.6, "whoosh", .6), (1.9, "impact", .8), (2.7, "zap", .6)],
  "stakes": [(0.0, "whoosh", .6), (0.0, "pop", .7), (0.9, "impact", .8)] + [(1.5 + 0.12 * i, "coin", .6) for i in range(6)],
  "win": [(0.0, "impact", .9), (0.0, "win", 1.0), (0.0, "crowd", .7), (0.4, "whoosh", .6), (1.4, "pop", .7)] + [(0.3 + 0.3 * i, "coin", .5) for i in range(8)],
  "collect": [(0.0, "whoosh", .7), (0.25, "impact", .8), (0.75, "pop", .7)],
  "end": [(0.0, "whoosh", .6), (0.1, "impact", .8), (0.25, "impact", 1.0), (0.7, "ding", .8), (0.7, "pop", .6)],
}
mixbuf = np.zeros((int(total * SR) + SR, 2))
for scene, cues in CUES.items():
    for t, name, g in cues:
        x = load(name) * g; i = int((start[scene] + t) * SR)
        mixbuf[i:i + len(x)] += x[:len(mixbuf) - i]
mixbuf = mixbuf[:int(total * SR)]
peak = np.max(np.abs(mixbuf)); mixbuf = np.tanh(mixbuf / peak * 1.4) / np.tanh(1.4) * 0.89
mixbuf[-int(0.6 * SR):] *= np.linspace(1, 0, int(0.6 * SR))[:, None]
with wave.open(os.path.join(HERE, "sfx_mix.wav"), "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes((mixbuf * 32767).astype(np.int16).tobytes())
with open(os.path.join(HERE, "scenes", "list.txt"), "w") as f:
    for n, _, _ in SCENES: f.write(f"file '{n}.mp4'\n")
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", os.path.join(HERE, "scenes", "list.txt"), "-c", "copy", os.path.join(HERE, "video_only.mp4")], check=True)
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", os.path.join(HERE, "video_only.mp4"), "-i", os.path.join(HERE, "sfx_mix.wav"),
                "-map", "0:v", "-map", "1:a", "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest", os.path.join(HERE, "trailer.tmp.mp4")], check=True)
os.replace(os.path.join(HERE, "trailer.tmp.mp4"), os.path.join(HERE, "trailer.mp4"))
print("ok", total)
