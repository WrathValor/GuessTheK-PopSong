# Synth sound effects for the trailer (no music: the SFX are the rhythm).
# python3 sfx.py -> sfx/*.wav ; the timeline lives in trailer.py (CUES) and mix.py
import os, wave
import numpy as np
SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__)); OUT = os.path.join(HERE, "sfx"); os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(1)
t_ = lambda d: np.arange(int(d * SR)) / SR
def env(n, a=0.003, d=0.2):
    t = np.arange(n) / SR
    return np.minimum(1, t / max(a, 1e-4)) * np.exp(-t / d)
def lp(x, k):  # one-pole low-pass, k in 0..1 (scalar or per-sample)
    k = np.broadcast_to(np.asarray(k, float), x.shape)
    y = np.empty_like(x); s = 0.0
    for i in range(len(x)): s += k[i] * (x[i] - s); y[i] = s
    return y
def hp(x, k): return x - lp(x, k)
def save(name, x, gain=0.9):
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    st = np.stack([x, x], 1)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((st * 32767).astype(np.int16).tobytes())

# tick: short woodblock click
t = t_(0.08); save("tick", np.sin(2 * np.pi * 1900 * t) * env(len(t), 0.001, 0.012) + 0.3 * rng.standard_normal(len(t)) * env(len(t), 0.0005, 0.004), 0.7)
# impact: sub drop + noise crack + tail
t = t_(1.2); f = 120 * np.exp(-t * 6) + 38
sub = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(t), 0.002, 0.45)
crack = lp(rng.standard_normal(len(t)), 0.25) * env(len(t), 0.001, 0.06)
save("impact", sub * 1.0 + crack * 0.8, 0.95)
# whoosh: filtered noise swelling up then gone
t = t_(0.45); n = rng.standard_normal(len(t))
shape = np.sin(np.pi * np.clip(t / 0.45, 0, 1)) ** 2
w = hp(lp(n, 0.08 + 0.25 * shape), 0.01) * shape
save("whoosh", w, 0.6)
# riser: noise + rising tone into a hit
t = t_(1.0); f = 200 + 1400 * (t / 1.0) ** 2
riser = 0.4 * np.sin(2 * np.pi * np.cumsum(f) / SR) * (t / 1.0) ** 2 + hp(rng.standard_normal(len(t)), 0.05) * (t / 1.0) ** 3 * 0.6
save("riser", riser, 0.55)
# buzzer: game-show wrong buzzer (square-ish, low)
t = t_(0.55); b = np.sign(np.sin(2 * np.pi * 110 * t)) * 0.6 + np.sign(np.sin(2 * np.pi * 116 * t)) * 0.4
save("buzzer", lp(b, 0.3) * np.minimum(1, t / 0.01) * np.clip((0.55 - t) / 0.05, 0, 1), 0.5)
# ding: correct (two bell partials, up a fifth)
def bell(f, d=0.9):
    t = t_(d); return (np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * 6) + 0.25 * np.sin(2 * np.pi * f * 5.4 * t) * np.exp(-t * 10)) * env(len(t), 0.002, 0.35)
d1 = bell(1046); d2 = bell(1568); x = np.zeros(int(1.1 * SR)); x[:len(d1)] += d1; x[int(0.09 * SR):int(0.09 * SR) + len(d2)] += d2
save("ding", x, 0.6)
# coin: bright two-note pickup
c1 = bell(1976, 0.3); c2 = bell(2637, 0.5); x = np.zeros(int(0.6 * SR)); x[:len(c1)] += c1; x[int(0.06 * SR):int(0.06 * SR) + len(c2)] += c2
save("coin", x, 0.45)
# pop: UI card pop-in
t = t_(0.12); f = 600 + 900 * np.exp(-t * 40)
save("pop", np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(t), 0.001, 0.035), 0.5)
# zap: lightning crack
t = t_(0.7); n = rng.standard_normal(len(t))
z = hp(n, 0.3) * env(len(t), 0.001, 0.12) + 0.5 * np.sign(np.sin(2 * np.pi * (80 + 60 * rng.standard_normal(len(t)).cumsum() / 4000) * t)) * env(len(t), 0.001, 0.2)
save("zap", z, 0.6)
# crowd: cheering bed (bandpassed noise with swells)
t = t_(4.0); n = rng.standard_normal(len(t))
crowd = lp(hp(n, 0.05), 0.18) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.7 * t) ** 2) * np.minimum(1, t / 0.3) * np.clip((4.0 - t) / 1.0, 0, 1)
save("crowd", crowd, 0.35)
# win jingle: arpeggio of bells
x = np.zeros(int(1.6 * SR))
for i, f in enumerate((1046, 1318, 1568, 2093)):
    b = bell(f, 1.0); s = int(i * 0.09 * SR); x[s:s + len(b)] += b * (0.8 if i < 3 else 1.0)
save("win", x, 0.6)
print("ok", sorted(os.listdir(OUT)))
