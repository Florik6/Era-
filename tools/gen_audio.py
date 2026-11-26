#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ERA: Ascension -- procedural audio generator.

Every sound effect and music track in assets/audio is synthesized here from scratch
(additive synthesis, FM, Karplus-Strong plucked strings, filtered noise, formant voices,
convolution reverb with synthetic impulse responses). No samples or third-party audio.

Usage:   python3 tools/gen_audio.py            (all)
         python3 tools/gen_audio.py sfx        (only effects)
         python3 tools/gen_audio.py music      (only music)
Output:  assets/audio/sfx/<name>.wav    22050 Hz, mono, 16-bit PCM
         assets/audio/music/<name>.ogg  44100 Hz, stereo, Vorbis q3 (seamless loops)
Requires python3 + numpy and ffmpeg (libvorbis) on PATH.
"""
import os
import sys
import wave
import time
import subprocess
import tempfile

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SFX_DIR = os.path.join(ROOT, "assets", "audio", "sfx")
MUS_DIR = os.path.join(ROOT, "assets", "audio", "music")
SR = 22050      # sfx sample rate
MSR = 44100     # music sample rate
TAU = 2.0 * np.pi
rng = np.random.default_rng(20261123)


# ----------------------------------------------------------------------------
# Generic DSP helpers
# ----------------------------------------------------------------------------
def T(dur, sr=SR):
    return np.arange(int(round(dur * sr))) / sr


def N(n):
    return rng.uniform(-1.0, 1.0, n)


def eperc(t, a=0.003, tau=0.2):
    e = np.exp(-np.maximum(t - a, 0.0) / tau)
    if a > 0:
        e = e * np.clip(t / a, 0.0, 1.0)
    return e


def eadsr(t, dur, a=0.01, d=0.1, s=0.7, r=0.2):
    hold = max(dur, a + d)
    return np.interp(t, [0.0, a, a + d, hold, hold + r], [0.0, 1.0, s, s, 0.0])


def fade(x, sr=SR, fin=0.002, fout=0.02):
    x = np.array(x, dtype=float)
    n = len(x)
    a = min(n, int(fin * sr))
    b = min(n, int(fout * sr))
    if a > 0:
        x[:a] *= np.linspace(0.0, 1.0, a)
    if b > 0:
        x[n - b:] *= np.linspace(1.0, 0.0, b)
    return x


def tone(t, f, sr=SR, ph=0.0):
    f = np.broadcast_to(np.asarray(f, dtype=float), t.shape)
    return np.sin(TAU * np.cumsum(f) / sr + ph)


def expsweep(t, f0, f1, dur=None):
    d = dur if dur else max(t[-1], 1e-6)
    return f0 * (f1 / f0) ** np.clip(t / d, 0.0, 1.0)


def ffilt(x, sr=SR, lo=None, hi=None, order=2, circular=False, peak=None, q=3.0, gain=4.0):
    """Magnitude-domain (zero phase) filter. circular=True keeps loops seamless."""
    n0 = len(x)
    if not circular:
        x = np.concatenate([x, np.zeros(2048)])
    n = len(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1.0 / sr)
    f[0] = 1e-3
    m = np.ones_like(f)
    if hi:
        m /= np.sqrt(1.0 + (f / hi) ** (2 * order))
    if lo:
        m /= np.sqrt(1.0 + (lo / f) ** (2 * order))
    if peak:
        m *= 1.0 + gain * np.exp(-0.5 * ((f - peak) / (peak / q)) ** 2)
    y = np.fft.irfft(X * m, n)
    return y[:n0]


def svf(x, fc, q=0.707, mode="lp", sr=SR):
    """Topology-preserving state variable filter with per-sample cutoff."""
    n = len(x)
    fc = np.clip(np.broadcast_to(np.asarray(fc, dtype=float), (n,)), 20.0, sr * 0.49)
    g = np.tan(np.pi * fc / sr)
    k = 1.0 / q
    a1 = 1.0 / (1.0 + g * (g + k))
    a2 = g * a1
    a3 = g * a2
    xs = x.tolist()
    A1 = a1.tolist()
    A2 = a2.tolist()
    A3 = a3.tolist()
    v1o = [0.0] * n
    v2o = [0.0] * n
    ic1 = 0.0
    ic2 = 0.0
    for i in range(n):
        v3 = xs[i] - ic2
        v1 = A1[i] * ic1 + A2[i] * v3
        v2 = ic2 + A2[i] * ic1 + A3[i] * v3
        ic1 = 2.0 * v1 - ic1
        ic2 = 2.0 * v2 - ic2
        v1o[i] = v1
        v2o[i] = v2
    v1a = np.array(v1o)
    v2a = np.array(v2o)
    if mode == "lp":
        return v2a
    if mode == "bp":
        return v1a
    return x - k * v1a - v2a


def metal(t, f0, ratios=(1.0, 2.76, 5.40, 8.93, 13.34), taus=(0.6, 0.4, 0.25, 0.15, 0.1),
          amps=(1.0, 0.6, 0.4, 0.25, 0.15), sr=SR):
    out = np.zeros_like(t)
    for r, ta, a in zip(ratios, taus, amps):
        if f0 * r < sr * 0.45:
            out += a * np.sin(TAU * f0 * r * t + rng.uniform(0, TAU)) * np.exp(-t / ta)
    return out


def fm(t, freq, ratio=1.4, index=3.0, tau=1.0, idx_tau=None, sr=SR, a=0.002):
    env = eperc(t, a, tau)
    ienv = index * np.exp(-t / (idx_tau if idx_tau else tau * 0.5))
    return env * np.sin(TAU * freq * t + ienv * np.sin(TAU * freq * ratio * t))


FORM_AH = ((730, 90, 1.0), (1090, 110, 0.5), (2440, 160, 0.25))
FORM_OH = ((500, 80, 1.0), (850, 100, 0.45), (2400, 150, 0.15))
FORM_OO = ((320, 60, 1.0), (870, 90, 0.3), (2240, 140, 0.1))
FORM_EE = ((280, 60, 0.8), (2250, 150, 0.5), (2900, 180, 0.3))


def formant_voice(t, f, formants=FORM_AH, sr=SR, nh=48, tilt=0.3):
    f = np.broadcast_to(np.asarray(f, dtype=float), t.shape)
    ph = TAU * np.cumsum(f) / sr
    out = np.zeros_like(t)
    fmin, fmax = float(np.min(f)), float(np.max(f))
    static = fmax < fmin * 1.03
    fmean = float(np.mean(f))
    for k in range(1, nh + 1):
        if k * fmin > sr * 0.45:
            break
        if static:
            fk = k * fmean
            g = 0.015 + sum(a * np.exp(-0.5 * ((fk - fc) / bw) ** 2) for fc, bw, a in formants)
        else:
            fk = k * f
            g = np.full_like(t, 0.015)
            for fc, bw, a in formants:
                g += a * np.exp(-0.5 * ((fk - fc) / bw) ** 2)
            g *= (fk < sr * 0.45)
        out += g * np.sin(k * ph) / (k ** tilt)
    return out


def place(buf, sig, idx, wrap=False):
    """Add sig into buf at sample idx (optionally wrapping around: seamless loops)."""
    n = len(buf)
    if wrap:
        idx %= n
        L = len(sig)
        first = min(L, n - idx)
        buf[idx:idx + first] += sig[:first]
        rest = sig[first:]
        while len(rest) > 0:
            m = min(len(rest), n)
            buf[:m] += rest[:m]
            rest = rest[m:]
    else:
        if idx >= n:
            return
        e = min(n, idx + len(sig))
        buf[idx:e] += sig[:e - idx]


def norm(x, peak=0.9):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 1e-9 else x


def write_wav(path, x, sr=SR):
    x = np.clip(x, -1.0, 1.0)
    if x.ndim == 2:
        d = (x.T.reshape(-1) * 32767.0).astype("<i2")
        ch = 2
    else:
        d = (x * 32767.0).astype("<i2")
        ch = 1
    with wave.open(path, "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(d.tobytes())


def write_ogg(path, x, sr=MSR, q=3):
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tf:
        tmp = tf.name
    try:
        write_wav(tmp, x, sr)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis",
                        "-q:a", str(q), path], check=True)
    finally:
        os.unlink(tmp)


# ----------------------------------------------------------------------------
# SOUND EFFECTS (22050 Hz mono)
# ----------------------------------------------------------------------------
def thump(t, f0=90, f1=45, tau=0.06, sr=SR):
    return tone(t, expsweep(t, f0, f1, 0.08), sr) * eperc(t, 0.001, tau)


def whoosh(dur, f0, f1, q=1.2, amp_peak=0.45, sr=SR):
    t = T(dur, sr)
    src = N(len(t))
    fc = expsweep(t, f0, f1)
    y = svf(src, fc, q, "bp", sr)
    env = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.5
    env *= np.clip(t / (dur * amp_peak + 1e-6), 0, 1) ** 0.5
    return y * env


def S_step():
    t = T(0.14)
    x = 0.9 * thump(t, 110, 55, 0.035)
    x += 0.6 * ffilt(N(len(t)), lo=150, hi=1400) * eperc(t, 0.001, 0.02)
    x += 0.15 * ffilt(N(len(t)), lo=2000, hi=6000) * eperc(t, 0.004, 0.015)
    return x


def S_step_metal():
    t = T(0.22)
    x = 0.7 * thump(t, 120, 60, 0.03)
    x += 0.35 * metal(t, 820, taus=(0.12, 0.08, 0.05, 0.04, 0.03))
    x += 0.3 * ffilt(N(len(t)), lo=1500, hi=7000) * eperc(t, 0.001, 0.02)
    return x


def S_swing():
    return whoosh(0.28, 400, 2600, 1.4)


def S_swing_heavy():
    x = whoosh(0.45, 180, 1200, 1.0)
    t = T(0.45)
    x += 0.4 * ffilt(N(len(t)), hi=400) * np.sin(np.pi * t / 0.45) ** 2
    return x


def S_hit_flesh():
    t = T(0.25)
    x = 1.0 * thump(t, 140, 50, 0.05)
    x += 0.7 * ffilt(N(len(t)), lo=200, hi=1800) * eperc(t, 0.001, 0.035)
    x += 0.25 * ffilt(N(len(t)), lo=2500, hi=5000) * eperc(t, 0.001, 0.01)
    return x


def S_hit_metal():
    t = T(0.6)
    x = 0.8 * metal(t, 610, taus=(0.35, 0.25, 0.15, 0.1, 0.07))
    x += 0.5 * metal(t, 1210, taus=(0.2, 0.12, 0.08, 0.05, 0.04))
    x += 0.6 * ffilt(N(len(t)), lo=1500, hi=9000) * eperc(t, 0.0005, 0.015)
    x += 0.5 * thump(t, 160, 80, 0.04)
    return x


def S_block():
    t = T(0.35)
    x = 0.9 * thump(t, 150, 70, 0.05)
    x += 0.45 * metal(t, 480, taus=(0.18, 0.1, 0.07, 0.05, 0.03))
    x += 0.5 * ffilt(N(len(t)), lo=600, hi=4000) * eperc(t, 0.0005, 0.02)
    return x


def S_parry():
    t = T(0.8)
    x = 0.7 * metal(t, 1320, taus=(0.6, 0.45, 0.3, 0.2, 0.12))
    x += 0.5 * metal(t, 1975, taus=(0.5, 0.3, 0.2, 0.12, 0.08))
    x += 0.6 * ffilt(N(len(t)), lo=3000, hi=10000) * eperc(t, 0.0005, 0.01)
    x += 0.15 * tone(t, 2640) * eperc(t, 0.01, 0.4) * (1 + 0.3 * np.sin(TAU * 7 * t))
    return x


def S_dodge():
    x = whoosh(0.26, 900, 300, 0.9)
    t = T(0.26)
    x += 0.25 * ffilt(N(len(t)), lo=2000, hi=6000) * eperc(t, 0.03, 0.05)
    return x


def S_bow_draw():
    t = T(0.55)
    f = 30 + 25 * t / 0.55
    creak = (np.sin(TAU * np.cumsum(f) / SR) > 0.85).astype(float)
    creak = ffilt(creak * N(len(t)) * 0.6 + creak * 0.4, lo=300, hi=3000)
    x = creak * np.clip(t / 0.4, 0, 1) * eperc(t, 0.0, 10)
    x += 0.15 * ffilt(N(len(t)), lo=1000, hi=4000) * np.clip(t / 0.5, 0, 1)
    return fade(x, fout=0.05)


def S_bow_release():
    t = T(0.4)
    f = 110 * (1 + 0.2 * np.exp(-t / 0.02))
    x = 0.8 * tone(t, f) * eperc(t, 0.001, 0.09) * (1 + 0.5 * np.sin(TAU * 220 * t))
    x += 0.6 * whoosh(0.4, 2400, 700, 1.0) * np.exp(-t / 0.2)
    x += 0.4 * ffilt(N(len(t)), lo=500, hi=3000) * eperc(t, 0.0005, 0.008)
    return x


def S_crossbow():
    t = T(0.35)
    x = 0.7 * ffilt(N(len(t)), lo=1500, hi=8000) * eperc(t, 0.0005, 0.006)
    x += 0.8 * tone(t, 160) * eperc(t, 0.001, 0.06) * (1 + 0.6 * np.sin(TAU * 480 * t))
    x += 0.4 * whoosh(0.35, 3000, 900, 1.0) * np.exp(-t / 0.15)
    x += 0.4 * metal(t, 900, taus=(0.05, 0.04, 0.03, 0.02, 0.02))
    return x


def gunshot(dur, crack_tau, boom_f, boom_tau, tail_tau, bright=6000, crack=1.0, boom=1.0, tail=0.6):
    t = T(dur)
    x = crack * ffilt(N(len(t)), lo=800, hi=bright) * eperc(t, 0.0003, crack_tau)
    x += boom * tone(t, expsweep(t, boom_f * 2.2, boom_f, 0.06)) * eperc(t, 0.001, boom_tau)
    x += tail * ffilt(N(len(t)), hi=900) * eperc(t, 0.004, tail_tau)
    return np.tanh(1.8 * x)


def S_gun_flint():
    t = T(1.0)
    click = 0.5 * metal(t, 2100, taus=(0.02, 0.015, 0.01, 0.01, 0.01))
    pan = 0.4 * ffilt(N(len(t)), lo=1000, hi=6000) * eperc(t - 0.04, 0.001, 0.05) * (t > 0.04)
    shot = np.zeros_like(t)
    g = gunshot(0.9, 0.04, 70, 0.12, 0.35, 5000, 1.0, 1.0, 0.9)
    place(shot, g, int(0.1 * SR))
    return click + pan + shot


def S_gun_revolver():
    return gunshot(0.55, 0.02, 120, 0.06, 0.2, 9000, 1.1, 0.8, 0.5)


def S_gun_rifle():
    return gunshot(0.85, 0.025, 90, 0.08, 0.35, 8000, 1.1, 0.9, 0.8)


def S_gun_shotgun():
    return gunshot(0.9, 0.04, 60, 0.12, 0.4, 5000, 1.0, 1.3, 1.0)


def S_gun_modern():
    t = T(0.45)
    x = gunshot(0.45, 0.015, 140, 0.05, 0.15, 10000, 1.2, 0.9, 0.4)
    m = np.zeros_like(t)
    place(m, 0.35 * metal(T(0.08), 3200, taus=(0.02, 0.015, 0.01, 0.01, 0.01)), int(0.07 * SR))
    return x + m


def S_laser():
    t = T(0.32)
    f = expsweep(t, 2400, 300)
    x = np.sin(TAU * np.cumsum(f) / SR + 2.0 * np.sin(TAU * np.cumsum(f * 0.5) / SR))
    return x * eperc(t, 0.002, 0.12)


def S_plasma():
    t = T(0.55)
    f = expsweep(t, 900, 90)
    ph = TAU * np.cumsum(f) / SR
    x = np.sign(np.sin(ph)) * 0.5 + 0.5 * np.sin(2 * ph)
    x = svf(x, expsweep(t, 6000, 400), 2.5, "lp")
    x += 0.3 * ffilt(N(len(t)), lo=2000) * (rng.random(len(t)) > 0.97) * 3
    return x * eperc(t, 0.003, 0.2)


def S_reload():
    t = T(0.65)
    x = np.zeros_like(t)
    for at, f in ((0.02, 1800), (0.28, 1300), (0.5, 2300)):
        c = 0.6 * metal(T(0.12), f, taus=(0.04, 0.03, 0.02, 0.015, 0.01))
        c += 0.4 * ffilt(N(len(T(0.12))), lo=2000, hi=8000) * eperc(T(0.12), 0.0003, 0.006)
        place(x, c, int(at * SR))
    return x


def S_fire_cast():
    t = T(0.65)
    x = whoosh(0.65, 200, 1800, 0.8) * 1.2
    crack = (rng.random(len(t)) > 0.985).astype(float) * N(len(t))
    x += 0.5 * ffilt(crack, lo=1500, hi=7000) * np.clip(t / 0.3, 0, 1)
    x += 0.3 * ffilt(N(len(t)), hi=500) * np.sin(np.pi * t / 0.65)
    return x


def S_explosion():
    t = T(1.45)
    x = 1.2 * tone(t, expsweep(t, 90, 30, 0.6)) * eperc(t, 0.002, 0.35)
    x += 1.0 * ffilt(N(len(t)), hi=expsweep(t, 3000, 200).mean()) * eperc(t, 0.001, 0.4)
    x += 0.8 * svf(N(len(t)), expsweep(t, 4000, 150), 0.6, "lp") * eperc(t, 0.0005, 0.5)
    debris = (rng.random(len(t)) > 0.995).astype(float) * N(len(t)) * (t > 0.2)
    x += 0.3 * ffilt(debris, lo=800, hi=4000) * np.exp(-t / 0.6)
    return np.tanh(1.5 * x)


def S_ice_cast():
    t = T(0.65)
    x = np.zeros_like(t)
    for i, f in enumerate((2093, 2637, 3136, 3951, 4699)):
        x += 0.25 * fm(t - i * 0.04, f, 2.01, 1.2, 0.35) * (t > i * 0.04)
    x += 0.3 * ffilt(N(len(t)), lo=4000, hi=10000) * np.sin(np.pi * t / 0.65) ** 2
    x += 0.2 * whoosh(0.65, 3000, 800, 2.0)
    return x


def S_ice_shatter():
    t = T(0.75)
    x = np.zeros_like(t)
    for _ in range(40):
        at = rng.uniform(0, 0.25) ** 1.5
        f = rng.uniform(2500, 7500)
        seg = T(0.12)
        place(x, rng.uniform(0.1, 0.35) * np.sin(TAU * f * seg) * eperc(seg, 0.0005, 0.02), int(at * SR))
    x += 0.6 * ffilt(N(len(t)), lo=2500, hi=10000) * eperc(t, 0.0005, 0.05)
    x += 0.4 * thump(t, 200, 90, 0.04)
    return x


def S_lightning():
    t = T(0.55)
    zaps = (rng.random(len(t)) > 0.93).astype(float) * N(len(t))
    env = eperc(t, 0.001, 0.15) * (0.6 + 0.4 * (np.sin(TAU * 23 * t) > 0))
    x = ffilt(zaps, lo=1500, hi=10000) * env * 2.0
    x += 0.6 * ffilt(N(len(t)), lo=400, hi=4000) * eperc(t, 0.0005, 0.03)
    x += 0.3 * tone(t, 120) * np.sign(np.sin(TAU * 60 * t)) * eperc(t, 0.001, 0.1)
    return np.tanh(3.0 * x / max(np.max(np.abs(x)), 1e-6))


def S_thunder():
    t = T(1.5)
    x = svf(N(len(t)), expsweep(t, 2500, 120, 0.8), 0.6, "lp") * eperc(t, 0.003, 0.5)
    x += 1.2 * ffilt(N(len(t)), hi=180) * eperc(t, 0.05, 0.6) * (1 + 0.5 * np.sin(TAU * 3 * t))
    x += 0.5 * ffilt(N(len(t)), lo=2000, hi=8000) * eperc(t, 0.0005, 0.02)
    return np.tanh(1.3 * x)


def S_dark_cast():
    t = T(0.85)
    f = expsweep(t, 220, 70)
    x = 0.5 * np.sin(TAU * np.cumsum(f) / SR) + 0.35 * np.sin(TAU * np.cumsum(f * 1.06) / SR)
    x += 0.25 * np.sin(TAU * np.cumsum(f * 1.5) / SR)
    rev = np.clip(t / 0.6, 0, 1) ** 3
    x *= np.where(t < 0.6, rev, np.exp(-(t - 0.6) / 0.08))
    x += 0.35 * ffilt(N(len(t)), lo=100, hi=900) * np.where(t < 0.6, rev, np.exp(-(t - 0.6) / 0.1))
    return x


def S_teleport():
    t = T(0.6)
    f = expsweep(t, 300, 3200)
    x = np.sin(TAU * np.cumsum(f) / SR) * 0.5
    x += 0.4 * np.sin(TAU * np.cumsum(f * 1.5) / SR) * (0.5 + 0.5 * np.sin(TAU * 18 * t))
    x += 0.4 * svf(N(len(t)), expsweep(t, 600, 6000), 3.0, "bp")
    env = np.clip(t / 0.05, 0, 1) * np.exp(-np.maximum(t - 0.3, 0) / 0.12)
    return x * env


def S_time_slow():
    t = T(1.0)
    f = 440 * np.exp(-t * 2.2) + 40
    ph = TAU * np.cumsum(f) / SR
    x = 0.6 * np.sin(ph) + 0.3 * np.sin(2 * ph) + 0.15 * np.sin(3 * ph)
    x = svf(x, expsweep(t, 5000, 300), 1.2, "lp")
    x += 0.2 * fm(t, 1760, 1.5, 2.0, 0.6) * 0.5
    return x * eperc(t, 0.01, 0.5)


def bell_arp(notes, step, tau=0.5, ratio=2.0, index=1.5, dur=1.0, amp=0.35):
    t = T(dur)
    x = np.zeros_like(t)
    for i, f in enumerate(notes):
        seg = T(dur - i * step)
        place(x, amp * fm(seg, f, ratio, index, tau), int(i * step * SR))
    return x


def S_heal():
    x = bell_arp((523.25, 659.25, 783.99, 1046.5), 0.09, 0.45, 1.0, 0.8, 0.85)
    t = T(0.85)
    x += 0.15 * ffilt(N(len(t)), lo=3000, hi=9000) * np.sin(np.pi * t / 0.85) ** 2
    return x


def S_pickup():
    t = T(0.16)
    x = np.zeros_like(t)
    place(x, 0.5 * np.sin(TAU * 880 * T(0.07)) * eperc(T(0.07), 0.002, 0.03), 0)
    place(x, 0.5 * np.sin(TAU * 1320 * T(0.1)) * eperc(T(0.1), 0.002, 0.04), int(0.055 * SR))
    return x


def S_coin():
    t = T(0.35)
    x = 0.5 * fm(t, 2637, 2.4, 0.8, 0.12) + 0.4 * fm(t - 0.06, 3520, 2.4, 0.8, 0.15) * (t > 0.06)
    return x


def S_xp():
    t = T(0.11)
    return np.sin(TAU * np.cumsum(expsweep(t, 1200, 1700)) / SR) * eperc(t, 0.003, 0.035)


def S_drop_epic():
    x = bell_arp((659.25, 783.99, 987.77, 1174.66, 1318.5), 0.07, 0.4, 3.0, 1.1, 0.95, 0.3)
    t = T(0.95)
    x += 0.25 * svf(N(len(t)), expsweep(t, 800, 5000), 4.0, "bp") * np.sin(np.pi * t / 0.95)
    return x


def S_drop_legendary():
    t = T(1.35)
    x = bell_arp((523.25, 659.25, 783.99, 1046.5, 1318.5, 1567.98), 0.06, 0.6, 2.0, 1.0, 1.35, 0.28)
    for f in (523.25, 659.25, 783.99):
        x += 0.12 * np.sin(TAU * f * t) * eadsr(t, 0.9, 0.05, 0.2, 0.7, 0.4)
    sparkle = (rng.random(len(t)) > 0.996).astype(float)
    x += 0.4 * ffilt(sparkle, lo=4000, hi=10000) * np.clip(t / 0.3, 0, 1)
    x += 0.5 * thump(t, 120, 50, 0.12)
    return x


def S_drop_mythic():
    t = T(1.5)
    x = 1.0 * tone(t, expsweep(t, 70, 35, 0.6)) * eperc(t, 0.002, 0.5)
    for f in (130.81, 138.59, 185.0, 196.0):
        x += 0.12 * formant_voice(t, f * (1 + 0.004 * np.sin(TAU * 5 * t)), FORM_AH) * eadsr(t, 1.0, 0.3, 0.2, 0.8, 0.4)
    x += 0.35 * svf(N(len(t)), expsweep(t, 200, 3000), 3.0, "bp") * np.clip(t / 1.0, 0, 1) * eperc(t, 0, 0.9)
    x += 0.3 * fm(t, 261.6, 1.41, 4.0, 1.0)
    return np.tanh(1.4 * x)


def S_chest_open():
    t = T(0.75)
    f = 180 + 120 * np.clip(t / 0.35, 0, 1)
    creak = ffilt((np.sin(TAU * np.cumsum(f) / SR) > 0.8).astype(float) * 1.0, lo=400, hi=4000)
    x = 0.5 * creak * (t < 0.35)
    th = np.zeros_like(t)
    place(th, 0.9 * thump(T(0.2), 150, 70, 0.05) + 0.3 * ffilt(N(len(T(0.2))), hi=1500) * eperc(T(0.2), 0.001, 0.03), int(0.36 * SR))
    x += th
    sp = np.zeros_like(t)
    place(sp, bell_arp((1318.5, 1975.5), 0.06, 0.25, 2.0, 1.0, 0.35, 0.25), int(0.4 * SR))
    return x + sp


def S_mimic():
    t = T(0.95)
    f = 160 + 100 * np.clip(t / 0.25, 0, 1)
    creak = ffilt((np.sin(TAU * np.cumsum(f) / SR) > 0.8).astype(float), lo=400, hi=4000) * (t < 0.25)
    gr = 0.8 * formant_voice(t, 70 * (1 + 0.3 * np.sin(TAU * 31 * t)), FORM_OH) * eadsr(t, 0.4, 0.05, 0.1, 0.8, 0.2) * (t > 0.2)
    gr += 0.4 * ffilt(N(len(t)), lo=100, hi=1200) * eadsr(t, 0.4, 0.05, 0.1, 0.6, 0.2) * (t > 0.2)
    ch = np.zeros_like(t)
    for at in (0.62, 0.78):
        place(ch, 0.8 * thump(T(0.15), 220, 90, 0.03) + 0.5 * ffilt(N(len(T(0.15))), lo=800, hi=5000) * eperc(T(0.15), 0.0005, 0.015), int(at * SR))
    return 0.5 * creak + gr + ch


def splinter(dur, density=0.97, tau=0.15):
    t = T(dur)
    cr = (rng.random(len(t)) > density).astype(float) * N(len(t))
    return ffilt(cr, lo=600, hi=6000) * eperc(t, 0.001, tau)


def S_door_break():
    t = T(0.85)
    x = 1.0 * thump(t, 120, 45, 0.1)
    x += 1.5 * splinter(0.85, 0.94, 0.2)
    x += 0.5 * ffilt(N(len(t)), lo=100, hi=900) * eperc(t, 0.001, 0.12)
    for at in (0.35, 0.55):
        seg = 0.6 * thump(T(0.2), 100, 50, 0.05)
        place(x, seg, int(at * SR))
    return np.tanh(1.3 * x)


def S_wood_break():
    t = T(0.5)
    x = 0.8 * thump(t, 160, 70, 0.05) + 1.5 * splinter(0.5, 0.95, 0.12)
    x += 0.3 * ffilt(N(len(t)), lo=300, hi=2500) * eperc(t, 0.001, 0.05)
    return x


def S_death():
    t = T(0.95)
    f = expsweep(t, 190, 80) * (1 + 0.01 * np.sin(TAU * 6 * t))
    x = formant_voice(t, f, FORM_OH) * eadsr(t, 0.6, 0.04, 0.2, 0.7, 0.3)
    x += 0.2 * ffilt(N(len(t)), lo=300, hi=3000) * eadsr(t, 0.6, 0.04, 0.2, 0.5, 0.3)
    place(x, 0.5 * thump(T(0.25), 110, 50, 0.06), int(0.7 * SR))
    return x


def S_death_monster():
    t = T(1.15)
    f = expsweep(t, 110, 45) * (1 + 0.25 * np.sin(TAU * 27 * t))
    x = formant_voice(t, f, FORM_OH) * eadsr(t, 0.8, 0.05, 0.2, 0.8, 0.3)
    x += 0.5 * ffilt(N(len(t)), lo=80, hi=1500) * eadsr(t, 0.8, 0.05, 0.2, 0.6, 0.3)
    return np.tanh(1.5 * x)


def S_robot_hit():
    t = T(0.45)
    x = 0.8 * metal(t, 340, taus=(0.25, 0.15, 0.1, 0.08, 0.05))
    x += 0.5 * thump(t, 150, 60, 0.05)
    buzz = np.sign(np.sin(TAU * 110 * t)) * 0.4 + 0.2 * np.sign(np.sin(TAU * 333 * t))
    x += svf(buzz, 2500, 1.5, "lp") * eperc(t, 0.01, 0.1) * (rng.random(len(t)) > 0.3)
    return x


def S_boss_roar():
    t = T(1.5)
    f = 75 * (1 + 0.3 * np.sin(np.pi * t / 1.5)) * (1 + 0.15 * np.sin(TAU * 33 * t))
    x = formant_voice(t, f, FORM_AH, nh=60) * eadsr(t, 1.1, 0.12, 0.2, 0.85, 0.3)
    x += 0.4 * formant_voice(t, f * 0.5, FORM_OH, nh=60) * eadsr(t, 1.1, 0.12, 0.2, 0.85, 0.3)
    x += 0.6 * ffilt(N(len(t)), lo=100, hi=2500) * eadsr(t, 1.1, 0.12, 0.2, 0.7, 0.3)
    return np.tanh(1.8 * x)


def S_boss_phase():
    t = T(1.5)
    x = 1.2 * tone(t, expsweep(t, 80, 30, 0.5)) * eperc(t, 0.002, 0.4)
    x += 0.8 * ffilt(N(len(t)), hi=1500) * eperc(t, 0.001, 0.25)
    f = expsweep(t, 110, 440)
    x += 0.35 * (np.sin(TAU * np.cumsum(f) / SR) + 0.5 * np.sin(TAU * np.cumsum(f * 1.5) / SR)) * np.clip(t / 1.2, 0, 1) * (t < 1.4)
    return np.tanh(1.3 * fade(x, fout=0.1))


def S_portal_open():
    t = T(1.4)
    x = np.zeros_like(t)
    for i, f in enumerate((220, 277.18, 329.63, 440)):
        ff = f * (1 + 0.01 * np.sin(TAU * (0.7 + i * 0.3) * t)) * expsweep(t, 0.5, 1.0, 1.0)
        x += 0.22 * np.sin(TAU * np.cumsum(ff) / SR + i)
    x *= np.clip(t / 0.8, 0, 1) * np.exp(-np.maximum(t - 1.0, 0) / 0.15)
    x += 0.3 * svf(N(len(t)), 800 + 1500 * (0.5 + 0.5 * np.sin(TAU * 2.5 * t)), 4.0, "bp") * np.sin(np.pi * t / 1.4)
    return x


def S_portal_enter():
    t = T(1.0)
    x = 0.8 * whoosh(1.0, 150, 4000, 1.2)
    x += 0.4 * np.sin(TAU * np.cumsum(expsweep(t, 200, 1600)) / SR) * np.sin(np.pi * t / 1.0) ** 2
    c = np.zeros_like(t)
    place(c, bell_arp((1046.5, 1567.98), 0.05, 0.3, 2.0, 1.0, 0.4, 0.3), int(0.6 * SR))
    return x + c


def S_era_transition():
    t = T(1.5)
    x = 0.6 * whoosh(1.5, 80, 5000, 0.9)
    for f in (261.63, 329.63, 392.0, 523.25):
        x += 0.13 * np.sin(TAU * f * t) * eadsr(t, 1.0, 0.4, 0.2, 0.8, 0.4)
    x += 0.5 * fm(t, 130.8, 1.4, 3.0, 1.5)
    x += 0.4 * fm(t - 0.5, 1046.5, 3.5, 1.0, 0.8) * (t > 0.5)
    return x


def S_level_up():
    x = bell_arp((523.25, 659.25, 783.99, 1046.5, 1318.5), 0.07, 0.35, 1.0, 0.6, 0.95, 0.35)
    t = T(0.95)
    for f in (523.25, 783.99, 1046.5):
        x += 0.1 * np.sin(TAU * f * t) * eadsr(t, 0.5, 0.3, 0.1, 0.8, 0.3)
    return x


def S_ui_click():
    t = T(0.05)
    return np.sin(TAU * 1900 * t) * eperc(t, 0.0005, 0.008) + 0.3 * ffilt(N(len(t)), lo=3000) * eperc(t, 0.0003, 0.003)


def S_ui_open():
    t = T(0.22)
    return 0.6 * whoosh(0.22, 500, 2500, 1.5) + 0.25 * np.sin(TAU * np.cumsum(expsweep(t, 600, 1200)) / SR) * eperc(t, 0.01, 0.07)


def S_ui_close():
    t = T(0.22)
    return 0.6 * whoosh(0.22, 2500, 500, 1.5) + 0.25 * np.sin(TAU * np.cumsum(expsweep(t, 1200, 600)) / SR) * eperc(t, 0.01, 0.07)


def S_curse_bind():
    t = T(1.25)
    x = np.zeros_like(t)
    for f in (110.0, 116.54, 155.56, 164.81):
        x += 0.2 * formant_voice(t, f, FORM_OO, nh=30) * eadsr(t, 0.7, 0.01, 0.2, 0.7, 0.5)
    x += 0.6 * thump(t, 90, 40, 0.15)
    for _ in range(14):
        at = rng.uniform(0.1, 0.9)
        place(x, 0.25 * metal(T(0.1), rng.uniform(1800, 3200), taus=(0.03, 0.02, 0.015, 0.01, 0.01)), int(at * SR))
    return x


def S_quest_done():
    return bell_arp((783.99, 987.77, 1174.66), 0.13, 0.5, 1.0, 0.7, 0.95, 0.4)


def brass_voice(t, f, dur, a=0.04, bright=12, sr=SR):
    out = np.zeros_like(t)
    f = np.broadcast_to(np.asarray(f, dtype=float), t.shape)
    ph = TAU * np.cumsum(f) / sr
    for k in range(1, bright + 1):
        if np.max(f) * k > sr * 0.45:
            break
        hk = np.clip(t / (a + 0.012 * k), 0, 1) ** 1.5
        out += (1.0 / k ** 0.9) * hk * np.sin(k * ph)
    return out * eadsr(t, dur, a, 0.08, 0.8, 0.15)


def S_capture():
    t = T(1.05)
    x = np.zeros_like(t)
    for at, f, d in ((0.0, 392.0, 0.25), (0.28, 523.25, 0.65)):
        seg = T(1.05 - at)
        place(x, 0.4 * brass_voice(seg, f * (1 + 0.003 * np.sin(TAU * 5 * seg)), d), int(at * SR))
    return x


def S_growl():
    t = T(0.85)
    f = 85 * (1 + 0.35 * np.sin(TAU * 29 * t)) * (1 + 0.1 * np.sin(np.pi * t / 0.85))
    x = formant_voice(t, f, FORM_OH) * eadsr(t, 0.6, 0.08, 0.1, 0.8, 0.2)
    x += 0.4 * ffilt(N(len(t)), lo=100, hi=1500) * eadsr(t, 0.6, 0.08, 0.1, 0.7, 0.2)
    return np.tanh(1.4 * x)


def S_wolf():
    t = T(1.5)
    f = np.interp(t, [0, 0.25, 0.9, 1.5], [330, 520, 500, 380]) * (1 + 0.012 * np.sin(TAU * 5.5 * t))
    x = formant_voice(t, f, FORM_OO, nh=20) * eadsr(t, 1.2, 0.2, 0.2, 0.9, 0.3)
    x += 0.05 * ffilt(N(len(t)), lo=500, hi=3000) * eadsr(t, 1.2, 0.2, 0.2, 0.9, 0.3)
    return x


def S_mastery_up():
    x = bell_arp((659.25, 987.77), 0.1, 0.4, 3.0, 1.2, 0.6, 0.4)
    t = T(0.6)
    x += 0.2 * svf(N(len(t)), expsweep(t, 1500, 7000), 4.0, "bp") * np.sin(np.pi * t / 0.6)
    return x


def S_achievement():
    t = T(1.25)
    x = np.zeros_like(t)
    for at, f, d in ((0.0, 523.25, 0.12), (0.13, 659.25, 0.12), (0.26, 783.99, 0.12), (0.4, 1046.5, 0.6)):
        seg = T(1.25 - at)
        place(x, 0.3 * brass_voice(seg, f, d, 0.02, 10), int(at * SR))
    x += bell_arp((2093.0, 2637.0, 3136.0), 0.05, 0.4, 2.0, 1.0, 1.25, 0.12)
    return x


def S_error():
    t = T(0.32)
    x = np.zeros_like(t)
    for at in (0.0, 0.15):
        seg = T(0.12)
        place(x, 0.5 * np.sign(np.sin(TAU * 150 * seg)) * eperc(seg, 0.002, 0.06), int(at * SR))
    return svf(x, 2000, 0.7, "lp")


# ---- seamless ambient loops (circular processing) ----
def L_rain():
    dur = 3.0
    n = int(dur * SR)
    x = 0.5 * ffilt(N(n), lo=500, hi=7000, circular=True)
    x += 0.25 * ffilt(N(n), hi=600, circular=True)
    drops = np.zeros(n)
    for _ in range(140):
        seg = T(0.03)
        f = rng.uniform(1800, 5000)
        place(drops, rng.uniform(0.05, 0.25) * np.sin(TAU * f * seg) * eperc(seg, 0.0005, 0.006), rng.integers(0, n), wrap=True)
    return x + drops


def L_wind():
    dur = 3.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for fc, per, ph, a in ((250, 3.0, 0.0, 0.6), (480, 1.5, 1.3, 0.45), (900, 1.0, 2.1, 0.25), (1600, 0.75, 0.5, 0.12)):
        band = ffilt(N(n), lo=fc * 0.6, hi=fc * 1.5, circular=True)
        lfo = 0.55 + 0.45 * np.sin(TAU * t / per + ph)
        x += a * band * lfo
    return x


def L_night():
    dur = 3.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = 0.08 * ffilt(N(n), lo=200, hi=1500, circular=True)
    for period, fcar, pulses, pr, off, a in ((0.75, 4400, 3, 32, 0.05, 0.25), (1.0, 4900, 4, 38, 0.4, 0.18),
                                             (0.6, 3900, 2, 28, 0.22, 0.14), (1.5, 5300, 5, 45, 0.9, 0.1)):
        reps = int(round(dur / period))
        chirp_len = pulses / pr
        seg = T(chirp_len)
        am = np.clip(np.sin(np.pi * (seg * pr % 1.0)), 0, 1) ** 2
        chirp = a * np.sin(TAU * fcar * seg) * am
        for r in range(reps):
            place(x, chirp, int((off + r * period) * SR), wrap=True)
    return x


def L_magic_storm():
    dur = 3.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = 0.4 * ffilt(N(n), hi=250, circular=True) * (0.7 + 0.3 * np.sin(TAU * t / 3.0))
    for fc, per in ((700, 1.5), (1300, 1.0), (2100, 0.75)):
        x += 0.25 * ffilt(N(n), circular=True, lo=fc * 0.9, hi=fc * 1.1, order=4) * (0.5 + 0.5 * np.sin(TAU * t / per))
    pent = (1046.5, 1174.66, 1318.5, 1567.98, 1760.0, 2093.0)
    for _ in range(10):
        seg = T(0.6)
        place(x, 0.12 * fm(seg, pent[rng.integers(0, len(pent))], 3.5, 1.5, 0.25), rng.integers(0, n), wrap=True)
    return x


SFX = {
    "step": S_step, "step_metal": S_step_metal, "swing": S_swing, "swing_heavy": S_swing_heavy,
    "hit_flesh": S_hit_flesh, "hit_metal": S_hit_metal, "block": S_block, "parry": S_parry,
    "dodge": S_dodge, "bow_draw": S_bow_draw, "bow_release": S_bow_release, "crossbow": S_crossbow,
    "gun_flint": S_gun_flint, "gun_revolver": S_gun_revolver, "gun_rifle": S_gun_rifle,
    "gun_shotgun": S_gun_shotgun, "gun_modern": S_gun_modern, "laser": S_laser, "plasma": S_plasma,
    "reload": S_reload, "fire_cast": S_fire_cast, "explosion": S_explosion, "ice_cast": S_ice_cast,
    "ice_shatter": S_ice_shatter, "lightning": S_lightning, "thunder": S_thunder,
    "dark_cast": S_dark_cast, "teleport": S_teleport, "time_slow": S_time_slow, "heal": S_heal,
    "pickup": S_pickup, "coin": S_coin, "xp": S_xp, "drop_epic": S_drop_epic,
    "drop_legendary": S_drop_legendary, "drop_mythic": S_drop_mythic, "chest_open": S_chest_open,
    "mimic": S_mimic, "door_break": S_door_break, "wood_break": S_wood_break, "death": S_death,
    "death_monster": S_death_monster, "robot_hit": S_robot_hit, "boss_roar": S_boss_roar,
    "boss_phase": S_boss_phase, "portal_open": S_portal_open, "portal_enter": S_portal_enter,
    "era_transition": S_era_transition, "level_up": S_level_up, "ui_click": S_ui_click,
    "ui_open": S_ui_open, "ui_close": S_ui_close, "curse_bind": S_curse_bind,
    "quest_done": S_quest_done, "capture": S_capture, "growl": S_growl, "wolf": S_wolf,
    "mastery_up": S_mastery_up, "achievement": S_achievement, "error": S_error,
}
LOOPS = {"rain_loop": L_rain, "wind_loop": L_wind, "night_loop": L_night, "magic_storm_loop": L_magic_storm}


def gen_sfx():
    os.makedirs(SFX_DIR, exist_ok=True)
    for name, fn in SFX.items():
        x = fn()
        x = fade(x, SR, 0.001, 0.015)
        x = norm(x, 0.89)
        write_wav(os.path.join(SFX_DIR, name + ".wav"), x)
    for name, fn in LOOPS.items():
        x = fn()
        x = x - np.mean(x)
        x = norm(x, 0.7)
        write_wav(os.path.join(SFX_DIR, name + ".wav"), x)
    print("sfx: %d files" % (len(SFX) + len(LOOPS)))


# ----------------------------------------------------------------------------
# MUSIC (44100 Hz stereo)
# ----------------------------------------------------------------------------
NOTE = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6,
        "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}
CHORD_IV = {"maj": (0, 4, 7), "min": (0, 3, 7), "dim": (0, 3, 6), "sus4": (0, 5, 7), "7": (0, 4, 7, 10),
            "m7": (0, 3, 7, 10), "maj7": (0, 4, 7, 11), "sus2": (0, 2, 7)}
SCALES = {"major": (0, 2, 4, 5, 7, 9, 11), "minor": (0, 2, 3, 5, 7, 8, 10), "dorian": (0, 2, 3, 5, 7, 9, 10),
          "harm_minor": (0, 2, 3, 5, 7, 8, 11), "phrygian": (0, 1, 3, 5, 7, 8, 10), "whole": (0, 2, 4, 6, 8, 10)}


def mtof(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def chord_notes(ch, octave=4):
    root, q = ch
    base = 12 * (octave + 1) + NOTE[root]
    return [base + i for i in CHORD_IV[q]]


def scale_notes(key, scale, lo, hi):
    pcs = [(NOTE[key] + s) % 12 for s in SCALES[scale]]
    return [m for m in range(lo, hi + 1) if m % 12 in pcs]


def chord_tones_in(ch, lo, hi):
    pcs = [(NOTE[ch[0]] + i) % 12 for i in CHORD_IV[ch[1]]]
    return [m for m in range(lo, hi + 1) if m % 12 in pcs]


def gen_phrase(r, chords, key, scale, bpb, rhythms, lo, hi, start, end_on_root=True):
    """Returns list of (beat, dur, midi) for len(chords) bars (one chord per bar)."""
    notes = []
    cur = start
    sc = scale_notes(key, scale, lo, hi)
    for bar, ch in enumerate(chords):
        rhy = rhythms[r.integers(0, len(rhythms))]
        tb = 0.0
        last_bar = bar == len(chords) - 1
        for i, d in enumerate(rhy):
            if d < 0:
                tb += -d
                continue
            strong = abs(tb - round(tb)) < 1e-6 and (int(round(tb)) % 2 == 0 or bpb == 3 and int(round(tb)) == 0)
            cands = chord_tones_in(ch, lo, hi) if (strong or (last_bar and i == len(rhy) - 1)) else sc
            if last_bar and i == len(rhy) - 1 and end_on_root:
                rp = [m for m in cands if m % 12 == NOTE[ch[0]]]
                if rp:
                    cands = rp
            ca = np.array(cands)
            w = np.exp(-np.abs(ca - cur) / 2.2) + 0.02
            w[ca == cur] *= 0.35
            w /= w.sum()
            m = int(r.choice(ca, p=w))
            notes.append((bar * bpb + tb, d, m))
            cur = m
            tb += d
    return notes


def shift_notes(notes, beat_off):
    return [(b + beat_off, d, m) for (b, d, m) in notes]


# ---- instruments (all return mono arrays at MSR) ----
def ks(freq, dur, t60=1.5, bright=0.6, sr=MSR):
    Np = max(2, int(round(sr / freq - 0.5)))
    n = int(dur * sr)
    g = 10.0 ** (-3.0 / (freq * max(t60, 0.05)))
    exc = rng.uniform(-1, 1, Np)
    for _ in range(int((1.0 - bright) * 6)):
        exc = 0.5 * (exc + np.roll(exc, 1))
    exc -= exc.mean()
    total = n + 1
    y = np.zeros(max(total, Np + 2))
    y[1:Np + 1] = exc
    pos = Np + 1
    L_all = len(y)
    while pos < L_all:
        L = min(Np, L_all - pos)
        y[pos:pos + L] = g * 0.5 * (y[pos - Np:pos - Np + L] + y[pos - Np - 1:pos - Np - 1 + L])
        pos += L
    out = y[1:1 + n]
    return fade(out, sr, 0.0005, 0.03)


def i_lute(f, dur):
    x = ks(f, dur + 0.6, 1.4, 0.55) + 0.5 * ks(f * 1.003, dur + 0.6, 1.2, 0.5)
    return x


def i_harpsi(f, dur):
    t = T(dur + 0.5, MSR)
    x = ks(f, dur + 0.5, 1.1, 0.9) + 0.6 * ks(f * 2.0005, dur + 0.5, 0.8, 0.95)
    x += 0.15 * ffilt(N(len(t)), MSR, lo=2000, hi=9000) * eperc(t, 0.0005, 0.004)
    return x


def additive(f, dur, amps, tail=0.3, vib_rate=0.0, vib_depth=0.0, vib_delay=0.2, harm_decay=None,
             harm_attack=None, sr=MSR):
    t = T(dur + tail, sr)
    fr = np.full_like(t, f)
    if vib_depth:
        fr = fr * (1.0 + vib_depth * np.sin(TAU * vib_rate * t + rng.uniform(0, TAU)) * np.clip((t - vib_delay) / 0.3, 0, 1))
    ph = TAU * np.cumsum(fr) / sr
    out = np.zeros_like(t)
    for k, a in enumerate(amps, start=1):
        if a == 0 or k * f > sr * 0.42:
            continue
        c = a * np.sin(k * ph + rng.uniform(0, TAU))
        if harm_decay:
            c *= np.exp(-t * harm_decay * (k - 1))
        if harm_attack:
            c *= np.clip(t / (harm_attack * (1 + 0.35 * k)), 0, 1)
        out += c
    return out, t


_MEMO = {}


def memo(fn):
    def w(*a, **kw):
        key = (fn.__name__, tuple(round(x, 4) if isinstance(x, float) else (tuple(x) if isinstance(x, list) else x) for x in a),
               tuple(sorted((k, round(v, 4) if isinstance(v, float) else (tuple(v) if isinstance(v, list) else v)) for k, v in kw.items())))
        try:
            hash(key)
        except TypeError:
            return fn(*a, **kw)
        if key not in _MEMO:
            _MEMO[key] = fn(*a, **kw)
        return _MEMO[key]
    return w


SAW = [1.0 / k for k in range(1, 17)]
SAW_SOFT = [1.0 / k ** 1.4 for k in range(1, 13)]
SQUARE = [1.0 / k if k % 2 else 0.0 for k in range(1, 16)]


@memo
def i_pad(f, dur, att=0.6, rel=1.0, detune=0.005, amps=SAW_SOFT):
    x = np.zeros(int((dur + rel) * MSR))
    for d in (-detune, 0.0, detune):
        y, t = additive(f * (1 + d), dur, amps, tail=rel)
        x += y[:len(x)]
    t = T(dur + rel, MSR)[:len(x)]
    return x * eadsr(t, dur, att, 0.3, 0.85, rel) / 3.0


@memo
def i_strings(f, dur, att=0.12, rel=0.35, bright=1.0):
    amps = [(1.0 / k) * (bright ** (k - 1)) for k in range(1, 15)]
    x = np.zeros(int((dur + rel) * MSR))
    for d in (-0.003, 0.003):
        y, t = additive(f * (1 + d), dur, amps, tail=rel, vib_rate=5.5, vib_depth=0.004, vib_delay=0.15)
        x += y[:len(x)]
    t = T(dur + rel, MSR)[:len(x)]
    return 0.5 * x * eadsr(t, dur, att, 0.1, 0.9, rel)


@memo
def i_stacc(f, dur):
    y, t = additive(f, 0.12, [1.0 / k for k in range(1, 12)], tail=0.15)
    y2, _ = additive(f * 1.004, 0.12, [1.0 / k for k in range(1, 12)], tail=0.15)
    return 0.5 * (y + y2) * eperc(t, 0.006, 0.07)


def i_oboe(f, dur, rel=0.15):
    y, t = additive(f, dur, [1.0, 0.85, 0.65, 0.5, 0.32, 0.2, 0.12, 0.06], tail=rel, vib_rate=5.0, vib_depth=0.005, vib_delay=0.18)
    return y * eadsr(t, dur, 0.05, 0.1, 0.85, rel)


def i_flute(f, dur, rel=0.18):
    y, t = additive(f, dur, [1.0, 0.25, 0.1, 0.04], tail=rel, vib_rate=5.2, vib_depth=0.006, vib_delay=0.2)
    br = ffilt(N(len(t)), MSR, lo=f * 0.8, hi=f * 4) * 0.08
    return (y + br) * eadsr(t, dur, 0.06, 0.1, 0.85, rel)


def i_hurdy(f, dur, rel=1.0):
    y, t = additive(f, dur, [1.0 / k ** 1.1 for k in range(1, 14)], tail=rel, vib_rate=4.0, vib_depth=0.002)
    buzz = 1.0 + 0.15 * np.sign(np.sin(TAU * f * 2 * t))
    return y * buzz * eadsr(t, dur, 0.5, 0.2, 0.9, rel)


def i_bell(f, dur, ratio=3.5, index=1.2, tau=1.0):
    t = T(dur + tau * 2.5, MSR)
    return fm(t, f, ratio, index, tau, sr=MSR)


@memo
def i_bass(f, dur, decay=6.0, rel=0.06):
    y, t = additive(f, dur, [1.0 / k for k in range(1, 20)], tail=rel, harm_decay=decay)
    sub = np.sin(TAU * f * 0.5 * t) * 0.0 + np.sin(TAU * f * t) * 0.6
    return (y + sub) * eadsr(t, dur, 0.004, 0.1, 0.8, rel)


@memo
def i_subbass(f, dur, rel=0.05):
    t = T(dur + rel, MSR)
    x = np.sin(TAU * f * t) + 0.25 * np.sin(TAU * 2 * f * t) + 0.08 * np.sin(TAU * 3 * f * t)
    return x * eadsr(t, dur, 0.005, 0.05, 0.9, rel)


@memo
def i_arp(f, dur):
    y, t = additive(f, 0.1, SQUARE, tail=0.25, harm_decay=9.0)
    y2, _ = additive(f * 1.006, 0.1, SQUARE, tail=0.25, harm_decay=9.0)
    return 0.5 * (y + y2) * eperc(t, 0.002, 0.12)


@memo
def i_brass(f, dur, rel=0.2):
    t = T(dur + rel, MSR)
    fr = f * (1 + 0.003 * np.sin(TAU * 5 * t) * np.clip((t - 0.2) / 0.3, 0, 1))
    x = brass_voice(t, fr, dur, 0.05, 14, MSR)
    x2 = brass_voice(t, fr * 1.004, dur, 0.06, 14, MSR)
    return 0.5 * (x + x2)


@memo
def i_choir(f, dur, form=FORM_AH, rel=0.6):
    t = T(dur + rel, MSR)
    x = np.zeros_like(t)
    for d in (-0.006, 0.0, 0.006):
        fr = f * (1 + d) * (1 + 0.005 * np.sin(TAU * (4.8 + 3 * d * 100) * t + rng.uniform(0, TAU)))
        x += formant_voice(t, fr, form, MSR, nh=30)
    return x * eadsr(t, dur, 0.35, 0.2, 0.9, rel) / 3.0


def i_saw_lead(f, dur, rel=0.1):
    y, t = additive(f, dur, [1.0 / k for k in range(1, 18)], tail=rel, vib_rate=5.5, vib_depth=0.004, vib_delay=0.25, harm_decay=0.8)
    return y * eadsr(t, dur, 0.01, 0.15, 0.75, rel)


# ---- drums ----
def d_kick(f0=120, f1=45, tau=0.18):
    t = T(0.45, MSR)
    x = np.sin(TAU * np.cumsum(expsweep(t, f0, f1, 0.07)) / MSR) * eperc(t, 0.001, tau)
    x += 0.3 * ffilt(N(len(t)), MSR, lo=1500, hi=8000) * eperc(t, 0.0002, 0.003)
    return np.tanh(1.5 * x)


def d_snare():
    t = T(0.3, MSR)
    x = 0.5 * np.sin(TAU * np.cumsum(expsweep(t, 260, 180, 0.03)) / MSR) * eperc(t, 0.001, 0.05)
    x += 0.8 * ffilt(N(len(t)), MSR, lo=1200, hi=9000) * eperc(t, 0.001, 0.085)
    return x


def d_hat(open_=False):
    t = T(0.35 if open_ else 0.1, MSR)
    return 0.6 * ffilt(N(len(t)), MSR, lo=7000, hi=16000) * eperc(t, 0.0005, 0.12 if open_ else 0.025)


def d_clap():
    t = T(0.3, MSR)
    x = np.zeros_like(t)
    src = ffilt(N(len(t)), MSR, lo=900, hi=4000)
    for i, off in enumerate((0.0, 0.011, 0.022)):
        x += src * eperc(t - off, 0.0005, 0.008) * (t >= off)
    x += src * eperc(t - 0.03, 0.001, 0.09) * (t >= 0.03)
    return x


def d_tom(f):
    t = T(0.5, MSR)
    x = np.sin(TAU * np.cumsum(expsweep(t, f * 1.6, f, 0.08)) / MSR) * eperc(t, 0.001, 0.22)
    x += 0.2 * ffilt(N(len(t)), MSR, lo=300, hi=3000) * eperc(t, 0.0005, 0.02)
    return x


def d_doum():
    t = T(0.6, MSR)
    x = np.sin(TAU * np.cumsum(expsweep(t, 95, 62, 0.1)) / MSR) * eperc(t, 0.002, 0.26)
    x += 0.25 * ffilt(N(len(t)), MSR, hi=600) * eperc(t, 0.001, 0.05)
    return x


def d_tek():
    t = T(0.2, MSR)
    x = 0.6 * ffilt(N(len(t)), MSR, lo=1800, hi=6000) * eperc(t, 0.0005, 0.035)
    x += 0.3 * np.sin(TAU * 420 * t) * eperc(t, 0.001, 0.03)
    return x


def d_anvil(f0=620):
    t = T(0.9, MSR)
    x = metal(t, f0, taus=(0.7, 0.5, 0.3, 0.2, 0.12), sr=MSR)
    x += 0.5 * ffilt(N(len(t)), MSR, lo=2000, hi=10000) * eperc(t, 0.0003, 0.008)
    return x


def d_steam():
    t = T(0.7, MSR)
    return ffilt(N(len(t)), MSR, lo=2500, hi=9000) * eadsr(t, 0.35, 0.06, 0.1, 0.7, 0.3)


def d_piston():
    t = T(0.12, MSR)
    x = 0.6 * ffilt(N(len(t)), MSR, lo=400, hi=2500) * eperc(t, 0.0005, 0.02)
    x += 0.5 * np.sin(TAU * 180 * t) * eperc(t, 0.001, 0.02)
    return x


def d_timp(f=65.4):
    t = T(1.6, MSR)
    x = np.zeros_like(t)
    for r, ta, a in ((1.0, 0.9, 1.0), (1.5, 0.6, 0.5), (1.98, 0.45, 0.35), (2.44, 0.3, 0.2)):
        x += a * np.sin(TAU * f * r * t) * eperc(t, 0.003, ta)
    x += 0.3 * ffilt(N(len(t)), MSR, hi=1200) * eperc(t, 0.001, 0.03)
    return x


def d_crash():
    t = T(2.0, MSR)
    x = 0.6 * ffilt(N(len(t)), MSR, lo=4000, hi=15000) * eperc(t, 0.001, 0.7)
    for _ in range(12):
        x += 0.04 * np.sin(TAU * rng.uniform(3000, 9000) * t) * eperc(t, 0.001, rng.uniform(0.3, 1.0))
    return x


def d_tick(f=2600):
    t = T(0.06, MSR)
    return np.sin(TAU * f * t) * eperc(t, 0.0003, 0.006) + 0.4 * ffilt(N(len(t)), MSR, lo=3000) * eperc(t, 0.0002, 0.002)


def d_boom():
    t = T(2.5, MSR)
    x = np.sin(TAU * np.cumsum(expsweep(t, 60, 28, 1.0)) / MSR) * eperc(t, 0.003, 0.9)
    x += 0.5 * ffilt(N(len(t)), MSR, hi=300) * eperc(t, 0.002, 0.5)
    return np.tanh(1.3 * x)


# ---- mixer ----
def make_ir(sec, sr, seed, damp=5500.0, predelay=0.015):
    n = int(sec * sr)
    t = np.arange(n) / sr
    r = np.random.default_rng(seed)
    x = r.standard_normal(n) * np.exp(-6.9 * t / sec)
    x = ffilt(x, sr, lo=120, hi=damp)
    pd = int(predelay * sr)
    x = np.concatenate([np.zeros(pd), x])
    for d, g in ((0.011, 0.6), (0.019, 0.45), (0.027, 0.35), (0.041, 0.3), (0.053, 0.22), (0.071, 0.15)):
        x[int(d * sr)] += g * (1 if r.random() > 0.5 else -1)
    return x / np.sqrt(np.sum(x ** 2))


class Mix:
    def __init__(self, seconds, loop=True, tail=6.0, sr=MSR):
        self.sr = sr
        self.loop = loop
        self.n = int(round(seconds * sr))
        self.tail = int(tail * sr)
        L = self.n + self.tail
        self.groups = {}
        self.L = L

    def _g(self, name):
        if name not in self.groups:
            self.groups[name] = [np.zeros((2, self.L)), np.zeros((2, self.L))]
        return self.groups[name]

    def add(self, sig, t_sec, gain=1.0, pan=0.0, rev=0.25, group="main"):
        s = int(round(t_sec * self.sr))
        if s < 0:
            sig = sig[-s:]
            s = 0
        if s >= self.L:
            return
        e = min(self.L, s + len(sig))
        seg = sig[:e - s]
        ang = (np.clip(pan, -1, 1) + 1.0) * np.pi / 4.0
        gl = gain * np.cos(ang) * 1.4142
        gr = gain * np.sin(ang) * 1.4142
        dry, snd = self._g(group)
        dry[0, s:e] += seg * gl
        dry[1, s:e] += seg * gr
        if rev > 0:
            snd[0, s:e] += seg * gl * rev
            snd[1, s:e] += seg * gr * rev

    def render(self, rev_sec=2.0, wet=1.0, damp=5500.0, envs=None, peak=0.89, drive=1.2, max_sec=None):
        envs = envs or {}
        dry = np.zeros((2, self.L))
        snd = np.zeros((2, self.L))
        for name, (d, s) in self.groups.items():
            if name in envs:
                e = envs[name]
                d = d * e
                s = s * e
            dry += d
            snd += s
        irl = make_ir(rev_sec, self.sr, 11, damp)
        irr = make_ir(rev_sec, self.sr, 23, damp)
        if self.loop:
            n = self.n
            def fold(a):
                out = a[:, :n].copy()
                rest = a[:, n:]
                while rest.shape[1] > 0:
                    m = min(rest.shape[1], n)
                    out[:, :m] += rest[:, :m]
                    rest = rest[:, m:]
                return out
            dry = fold(dry)
            snd = fold(snd)
            wl = np.fft.irfft(np.fft.rfft(snd[0]) * np.fft.rfft(irl, n), n)
            wr = np.fft.irfft(np.fft.rfft(snd[1]) * np.fft.rfft(irr, n), n)
            out = dry + wet * np.vstack([wl, wr])
        else:
            n = self.L + len(irl)
            wl = np.fft.irfft(np.fft.rfft(snd[0], n) * np.fft.rfft(irl, n), n)
            wr = np.fft.irfft(np.fft.rfft(snd[1], n) * np.fft.rfft(irr, n), n)
            d2 = np.zeros((2, n))
            d2[:, :self.L] = dry
            out = d2 + wet * np.vstack([wl, wr])
            # trim trailing silence
            amp = np.max(np.abs(out), axis=0)
            thr = np.max(amp) * 0.003
            idx = np.nonzero(amp > thr)[0]
            end = int(idx[-1]) + 1 if len(idx) else n
            if max_sec:
                end = min(end, int(max_sec * self.sr))
            out = out[:, :end]
            fl = min(out.shape[1], int(0.7 * self.sr))
            out[:, -fl:] *= np.linspace(1, 0, fl)
        out -= out.mean(axis=1, keepdims=True)
        out = norm(out, 1.0)
        out = np.tanh(drive * out) / np.tanh(drive)
        return norm(out, peak)


def duck_curve(L, sr, beat, depth=0.6, rel=0.18):
    t = np.arange(L) / sr
    ph = np.mod(t, beat)
    return 1.0 - depth * np.exp(-ph / rel)


def human(r, s=0.008):
    return r.normal(0, s)


# ---- tracks ----
def song_menu():
    r = np.random.default_rng(101)
    bpm, bpb, bars = 76.0, 4, 16
    beat = 60.0 / bpm
    prog = [("D", "min"), ("Bb", "maj"), ("G", "min"), ("A", "maj")] * 3 + [("D", "min"), ("F", "maj"), ("G", "min"), ("A", "7")]
    mx = Mix(bars * bpb * beat)
    tick, tock = d_tick(2900), d_tick(2100)
    for b in range(bars * bpb):
        mx.add(tick if b % 2 == 0 else tock, b * beat, 0.16, -0.35 if b % 2 == 0 else 0.35, 0.3)
        if b >= 32:
            mx.add(d_tick(4200), (b + 0.5) * beat, 0.05, 0.6, 0.4)
    for i, ch in enumerate(prog):
        notes = chord_notes(ch, 3)
        for j, m in enumerate(notes[:3]):
            mx.add(i_pad(mtof(m), bpb * beat + 0.3, 1.2, 1.6), i * bpb * beat, 0.16, -0.4 + 0.4 * j, 0.6)
        mx.add(i_strings(mtof(12 * 3 + NOTE[ch[0]]), bpb * beat, 0.6, 0.8, 0.7), i * bpb * beat, 0.22, 0.0, 0.4)
        if i % 4 == 0:
            mx.add(i_bell(mtof(12 * 3 + NOTE["D"]), 3.0, 1.4, 3.5, 3.5), i * bpb * beat, 0.25, 0.0, 0.7)
    rh = [[1, 1, 1, 1], [1, 0.5, 0.5, 2], [1.5, 0.5, 1, 1], [2, 1, 1], [0.5, 0.5, 1, -1, 1], [3, -1]]
    A = gen_phrase(r, prog[0:4], "D", "harm_minor", bpb, rh, 69, 86, 74)
    B = gen_phrase(r, prog[4:8], "D", "harm_minor", bpb, rh, 69, 88, 77)
    C = gen_phrase(r, prog[12:16], "D", "harm_minor", bpb, rh, 67, 86, 74)
    mel = shift_notes(A, 0) + shift_notes(A, 16) + shift_notes(B, 32) + shift_notes(C, 48)
    for (bt, d, m) in mel:
        mx.add(i_bell(mtof(m), d * beat, 3.5, 1.1, 0.9), bt * beat + human(r), 0.32, r.uniform(-0.3, 0.3), 0.55)
    return mx.render(3.2, 1.1)


def song_era0():
    r = np.random.default_rng(202)
    bpm, bpb, bars = 104.0, 3, 24
    beat = 60.0 / bpm
    cyc = [("D", "min"), ("C", "maj"), ("D", "min"), ("G", "maj"), ("F", "maj"), ("C", "maj"), ("A", "min"), ("D", "min")]
    prog = cyc * 3
    mx = Mix(bars * bpb * beat)
    # drone (hurdy-gurdy) D + A, overlapping 8-bar notes
    for k in range(3):
        st = k * 8 * bpb * beat
        mx.add(i_hurdy(mtof(38), 8 * bpb * beat + 0.4, 1.2), st, 0.16, -0.2, 0.3)
        mx.add(i_hurdy(mtof(45), 8 * bpb * beat + 0.4, 1.2), st, 0.11, 0.2, 0.3)
    # lute arpeggios
    for i, ch in enumerate(prog):
        cn = chord_notes(ch, 3)
        pat = [cn[0], cn[2], cn[0] + 12, cn[1] + 12, cn[2], cn[1]]
        for j, m in enumerate(pat):
            vel = 0.35 if j == 0 else 0.25
            mx.add(i_lute(mtof(m), 0.6), (i * bpb + j * 0.5) * beat + human(r), vel * r.uniform(0.85, 1.0), 0.25, 0.25)
    # frame drum
    doum, tek = d_doum(), d_tek()
    for b in range(bars):
        base = b * bpb * beat
        mx.add(doum, base + human(r, 0.004), 0.5, -0.05, 0.2)
        mx.add(tek, base + 1 * beat + human(r, 0.004), 0.28, 0.1, 0.2)
        mx.add(tek, base + 2 * beat + human(r, 0.004), 0.3, 0.1, 0.2)
        if b % 2 == 1:
            mx.add(tek, base + 2.5 * beat, 0.18, 0.15, 0.2)
        if b % 8 == 7:
            mx.add(doum, base + 2.5 * beat, 0.35, -0.05, 0.2)
    # recorder melody (bars 8-23)
    rh = [[1, 1, 1], [2, 1], [1.5, 0.5, 1], [0.5, 0.5, 1, 1], [3], [1, 0.5, 0.5, 1]]
    A = gen_phrase(r, cyc[0:4], "D", "dorian", bpb, rh, 69, 86, 74)
    B = gen_phrase(r, cyc[4:8], "D", "dorian", bpb, rh, 69, 86, 76)
    A2 = gen_phrase(r, cyc[0:4], "D", "dorian", bpb, rh, 69, 86, 74)
    mel = shift_notes(A, 8 * bpb) + shift_notes(B, 12 * bpb) + shift_notes(A2, 16 * bpb) + shift_notes(B, 20 * bpb)
    for (bt, d, m) in mel:
        mx.add(i_flute(mtof(m), d * beat * 0.95), bt * beat + human(r), 0.3, 0.1, 0.35)
    # counter line on low strings in bars 16-23
    for i in range(16, 24):
        mx.add(i_strings(mtof(chord_notes(prog[i], 2)[0]), bpb * beat * 0.98, 0.15, 0.3, 0.6), i * bpb * beat, 0.2, -0.1, 0.3)
    return mx.render(2.2, 0.9)


def song_era1():
    r = np.random.default_rng(303)
    bpm, bpb = 88.0, 4
    beat = 60.0 / bpm
    G, C, D, Em, Am, Bm = ("G", "maj"), ("C", "maj"), ("D", "maj"), ("E", "min"), ("A", "min"), ("B", "min")
    prog = [G, C, D, G, Em, Am, D, G, C, G, Am, Em, C, Am, D, D, G, C, D, G]
    bars = len(prog)
    mx = Mix(bars * bpb * beat)
    for i, ch in enumerate(prog):
        cn = chord_notes(ch, 4)
        if ch[0] in ("A", "B"):
            cn = [m - 12 for m in cn]
        pat = [cn[0], cn[1], cn[2], cn[0] + 12, cn[2], cn[1], cn[2], cn[1]] * 2
        for j, m in enumerate(pat):
            mx.add(i_harpsi(mtof(m), 0.25), (i * bpb + j * 0.25) * beat + human(r, 0.004),
                   (0.22 if j % 4 == 0 else 0.16), 0.3 if j % 2 else 0.15, 0.2)
        root = 12 * 3 + NOTE[ch[0]]
        if root > 52:
            root -= 12
        mx.add(i_strings(mtof(root), 2 * beat * 0.95, 0.06, 0.25, 0.8), i * bpb * beat, 0.28, -0.3, 0.25)
        fifth = root + 7 if i % 2 == 0 else root + 12
        mx.add(i_strings(mtof(fifth), 2 * beat * 0.95, 0.06, 0.25, 0.8), (i * bpb + 2) * beat, 0.22, -0.3, 0.25)
        if i >= 4:
            for j, m in enumerate(chord_notes(ch, 4)[:3]):
                mx.add(i_strings(mtof(m), bpb * beat, 0.35, 0.5, 0.65), i * bpb * beat, 0.07, -0.5 + 0.5 * j, 0.45)
    rh = [[1, 1, 1, 1], [1.5, 0.5, 1, 1], [0.5, 0.5, 0.5, 0.5, 2], [2, 1, 1], [1, 0.5, 0.5, 1, 1], [3, 1]]
    A = gen_phrase(r, prog[0:4], "G", "major", bpb, rh, 67, 86, 74)
    B = gen_phrase(r, prog[4:8], "G", "major", bpb, rh, 67, 86, 79)
    Cp = gen_phrase(r, prog[8:12], "G", "major", bpb, rh, 67, 88, 76)
    Dp = gen_phrase(r, prog[12:16], "G", "major", bpb, rh, 67, 86, 74)
    mel = shift_notes(A, 4 * bpb) + shift_notes(B, 8 * bpb) + shift_notes(Cp, 12 * bpb) + shift_notes(Dp, 16 * bpb)
    for (bt, d, m) in mel:
        mx.add(i_oboe(mtof(m), d * beat * 0.92), bt * beat + human(r), 0.22, 0.05, 0.35)
    return mx.render(1.9, 0.8)


def song_era2():
    r = np.random.default_rng(404)
    bpm, bpb = 100.0, 4
    beat = 60.0 / bpm
    cyc = [("E", "min"), ("E", "min"), ("C", "maj"), ("B", "maj")]
    bars = 24
    prog = cyc * 6
    mx = Mix(bars * bpb * beat)
    kick, piston, anvil, steam = d_kick(90, 40, 0.22), d_piston(), d_anvil(560), d_steam()
    anvil2 = d_anvil(840)
    pat = [0, 0, 12, 0, 7, 0, 12, 7]
    for i, ch in enumerate(prog):
        base = i * bpb * beat
        root = 12 * 2 + NOTE[ch[0]]
        if root > 40:
            root -= 12
        for j, iv in enumerate(pat):
            mx.add(i_bass(mtof(root + iv), 0.5 * beat * 0.8, 9.0), base + j * 0.5 * beat, 0.3 if j % 2 == 0 else 0.22, 0.0, 0.1)
        mx.add(kick, base, 0.7, 0, 0.1)
        mx.add(kick, base + 2 * beat, 0.6, 0, 0.1)
        if i % 2 == 1:
            mx.add(kick, base + 3.5 * beat, 0.45, 0, 0.1)
        mx.add(anvil, base + 1 * beat + human(r, 0.003), 0.22, 0.25, 0.4)
        mx.add(anvil2 if i % 4 == 3 else anvil, base + 3 * beat + human(r, 0.003), 0.22, 0.3, 0.4)
        for s in range(16):
            g = 0.2 if s % 4 == 2 else 0.1
            mx.add(piston, base + s * 0.25 * beat, g, -0.4 + 0.8 * (s % 2), 0.1)
        if i % 2 == 1:
            mx.add(steam, base + 3.5 * beat, 0.18, -0.6, 0.3)
        if i >= 8:
            for j, m in enumerate(chord_notes(ch, 3)[:3]):
                mx.add(i_pad(mtof(m), bpb * beat, 0.4, 0.6, 0.004, SAW), base, 0.07, -0.4 + 0.4 * j, 0.5)
    rh = [[4], [2, 2], [3, 1], [2, 1, 1]]
    A = gen_phrase(r, cyc, "E", "minor", bpb, rh, 52, 67, 59)
    B = gen_phrase(r, cyc, "E", "minor", bpb, rh, 55, 71, 64)
    mel = shift_notes(A, 8 * bpb) + shift_notes(B, 12 * bpb) + shift_notes(A, 16 * bpb) + shift_notes(B, 20 * bpb)
    for (bt, d, m) in mel:
        mx.add(i_brass(mtof(m), d * beat * 0.9), bt * beat, 0.2, -0.1, 0.4)
    for _ in range(40):
        at = r.uniform(0, bars * bpb * beat)
        mx.add(d_tick(r.uniform(1500, 3500)), at, 0.08, r.uniform(-0.8, 0.8), 0.6)
    return mx.render(2.6, 0.9, damp=4000)


def song_era3():
    r = np.random.default_rng(505)
    bpm, bpb = 128.0, 4
    beat = 60.0 / bpm
    cyc = [("A", "min"), ("F", "maj"), ("D", "min"), ("E", "maj")]
    bars = 28
    prog = cyc * 7
    mx = Mix(bars * bpb * beat)
    kick, snare, hat, ohat = d_kick(130, 48, 0.16), d_snare(), d_hat(), d_hat(True)
    for i, ch in enumerate(prog):
        base = i * bpb * beat
        mx.add(kick, base, 0.75)
        mx.add(kick, base + 2 * beat, 0.7)
        if i % 2:
            mx.add(kick, base + 2.5 * beat, 0.5)
        mx.add(snare, base + 1 * beat, 0.5, 0.05, 0.2)
        mx.add(snare, base + 3 * beat, 0.5, 0.05, 0.2)
        for s in range(8):
            mx.add(hat, base + s * 0.5 * beat, 0.22 if s % 2 else 0.14, 0.35, 0.05)
        if i % 4 == 3:
            for s in range(4):
                mx.add(snare, base + (3 + s * 0.25) * beat, 0.25 + 0.08 * s, -0.1 + 0.1 * s, 0.2)
        if i % 8 == 0:
            mx.add(d_crash(), base, 0.25, -0.3, 0.3)
        root = 12 * 2 + NOTE[ch[0]]
        if root > 40:
            root -= 12
        for s in range(8):
            mx.add(i_bass(mtof(root + (12 if s == 6 else 0)), 0.5 * beat * 0.7, 7.0), base + s * 0.5 * beat, 0.32, 0.0, 0.05)
        cn = chord_notes(ch, 4)
        for s in range(8):
            mx.add(i_stacc(mtof(cn[s % 3] if s % 2 == 0 else cn[(s + 1) % 3]), 0.1), base + s * 0.5 * beat, 0.12, -0.35 if s % 2 else 0.35, 0.3)
        for j, m in enumerate(chord_notes(ch, 3)[:3]):
            mx.add(i_pad(mtof(m), bpb * beat, 0.3, 0.5, 0.006, SAW_SOFT), base, 0.06, -0.5 + 0.5 * j, 0.5)
    rh = [[2, 2], [1.5, 1.5, 1], [1, 1, 2], [4]]
    A = gen_phrase(r, cyc, "A", "harm_minor", bpb, rh, 64, 81, 69)
    B = gen_phrase(r, cyc, "A", "harm_minor", bpb, rh, 64, 83, 72)
    mel = shift_notes(A, 12 * bpb) + shift_notes(B, 16 * bpb) + shift_notes(A, 20 * bpb) + shift_notes(B, 24 * bpb)
    for (bt, d, m) in mel:
        mx.add(i_saw_lead(mtof(m), d * beat * 0.9), bt * beat, 0.12, 0.0, 0.4)
    return mx.render(1.6, 0.7)


def song_era4():
    r = np.random.default_rng(606)
    bpm, bpb = 118.0, 4
    beat = 60.0 / bpm
    cyc = [("C", "min"), ("Ab", "maj"), ("Eb", "maj"), ("Bb", "maj")]
    bars = 24
    prog = cyc * 6
    mx = Mix(bars * bpb * beat)
    kick, clap, hat, ohat = d_kick(140, 42, 0.2), d_clap(), d_hat(), d_hat(True)
    for i, ch in enumerate(prog):
        base = i * bpb * beat
        for b in range(4):
            mx.add(kick, base + b * beat, 0.75, 0, 0.05)
            mx.add(ohat, base + (b + 0.5) * beat, 0.16, 0.3, 0.15)
        mx.add(clap, base + 1 * beat, 0.4, -0.05, 0.35)
        mx.add(clap, base + 3 * beat, 0.4, -0.05, 0.35)
        for s in range(16):
            mx.add(hat, base + s * 0.25 * beat, 0.08 if s % 2 else 0.05, -0.3, 0.05)
        root = 12 * 2 + NOTE[ch[0]]
        if root > 40:
            root -= 12
        for b in range(4):
            mx.add(i_subbass(mtof(root), 0.4 * beat), base + (b + 0.5) * beat, 0.42, 0, 0.0, group="duck")
        cn = chord_notes(ch, 4)
        arp = [cn[0], cn[1], cn[2], cn[0] + 12, cn[2] + 12, cn[0] + 12, cn[2], cn[1]] * 2
        for s, m in enumerate(arp):
            mx.add(i_arp(mtof(m), 0.1), base + s * 0.25 * beat, 0.13, -0.6 if s % 2 else 0.6, 0.35)
        for j, m in enumerate(chord_notes(ch, 3)):
            mx.add(i_pad(mtof(m), bpb * beat, 0.08, 0.3, 0.012, SAW), base, 0.07, -0.6 + 0.6 * j, 0.5, group="duck")
    rh = [[2, 2], [1, 1, 2], [3, 1], [1.5, 1.5, 1]]
    A = gen_phrase(r, cyc, "C", "minor", bpb, rh, 72, 89, 79)
    B = gen_phrase(r, cyc, "C", "minor", bpb, rh, 72, 89, 84)
    mel = shift_notes(A, 8 * bpb) + shift_notes(B, 12 * bpb) + shift_notes(A, 16 * bpb) + shift_notes(B, 20 * bpb)
    for (bt, d, m) in mel:
        mx.add(i_bell(mtof(m), d * beat, 2.0, 1.6, 0.5), bt * beat, 0.18, r.uniform(-0.3, 0.3), 0.5)
    duck = duck_curve(mx.L, MSR, beat, 0.65, 0.16)
    return mx.render(2.0, 0.8, envs={"duck": duck})


def song_boss():
    r = np.random.default_rng(707)
    bpm, bpb = 150.0, 4
    beat = 60.0 / bpm
    cyc = [("C", "min"), ("C", "min"), ("Ab", "maj"), ("G", "maj"), ("C", "min"), ("C", "min"), ("Db", "maj"), ("G", "maj")]
    bars = 32
    prog = cyc * 4
    mx = Mix(bars * bpb * beat)
    kick, snare, timp, crash = d_kick(110, 45, 0.15), d_snare(), d_timp(65.4), d_crash()
    toms = [d_tom(f) for f in (180, 140, 110, 85)]
    for i, ch in enumerate(prog):
        base = i * bpb * beat
        dbl = (i % 8) >= 4
        for s in range(8 if not dbl else 16):
            step = 0.5 if not dbl else 0.25
            if not dbl and s % 2 == 1 and s not in (3, 7):
                continue
            mx.add(kick, base + s * step * beat, 0.55 if s % 2 == 0 else 0.4)
        mx.add(snare, base + 1 * beat, 0.5, 0.05, 0.25)
        mx.add(snare, base + 3 * beat, 0.5, 0.05, 0.25)
        mx.add(timp, base, 0.35, -0.2, 0.4)
        if i % 4 == 0:
            mx.add(crash, base, 0.22, 0.3, 0.3)
        if i % 8 == 7:
            for s in range(8):
                mx.add(toms[s // 2], base + (2 + s * 0.25) * beat, 0.4, -0.5 + 0.14 * s, 0.3)
        root = 12 * 2 + NOTE[ch[0]]
        if root > 40:
            root -= 12
        for s in range(16):
            m = root + (12 if s % 2 else 0)
            mx.add(i_stacc(mtof(m), 0.1), base + s * 0.25 * beat, 0.2, -0.2, 0.2)
        cn = chord_notes(ch, 4)
        for at in (0.0, 2.5):
            for j, m in enumerate(cn[:3]):
                mx.add(i_brass(mtof(m - 12), 0.35 * beat if at else 0.9 * beat), base + at * beat, 0.12, -0.4 + 0.4 * j, 0.35)
        for j, m in enumerate(chord_notes(ch, 3)[:3]):
            mx.add(i_choir(mtof(m + 12), bpb * beat * 0.95, FORM_AH, 0.4), base, 0.12, -0.5 + 0.5 * j, 0.5)
    return mx.render(2.2, 0.85, drive=1.5)


def song_rift():
    r = np.random.default_rng(808)
    bpm, bpb = 60.0, 4
    beat = 60.0 / bpm
    bars = 12
    total = bars * bpb * beat
    mx = Mix(total)
    clusters = [(48, 49, 54, 55), (46, 50, 52, 58), (47, 48, 53, 59), (45, 51, 52, 56)]
    for i in range(bars // 2):
        cl = clusters[i % len(clusters)]
        st = i * 2 * bpb * beat
        for j, m in enumerate(cl):
            mx.add(i_pad(mtof(m), 2 * bpb * beat, 2.5, 2.5, 0.008, SAW_SOFT), st, 0.12, -0.6 + 0.4 * j, 0.7)
    wt = scale_notes("C", "whole", 60, 90)
    for k in range(10):
        f = mtof(wt[r.integers(0, len(wt))])
        dur = r.uniform(1.5, 3.0)
        y, t = additive(f, dur, [1, 0.3, 0.2, 0.1], tail=0.05)
        env = (np.clip(t / dur, 0, 1) ** 3) * (t <= dur)
        st = r.uniform(0, total)
        mx.add(y * env, st, 0.18, r.uniform(-0.9, 0.9), 0.8)
    for k in range(22):
        f = mtof(wt[r.integers(0, len(wt))])
        mx.add(i_bell(f, 1.0, 1.41, 2.5, 1.6), r.uniform(0, total), 0.1, r.uniform(-0.9, 0.9), 0.8)
    t = T(total + 1.0, MSR)
    drone = (np.sin(TAU * 32.7 * t) + 0.5 * np.sin(TAU * 49.0 * t)) * (0.7 + 0.3 * np.sin(TAU * t / total * 2))
    mx.add(drone, 0, 0.18, 0, 0.2)
    wind = ffilt(N(int(total * MSR)), MSR, lo=300, hi=1400, circular=True) * (0.5 + 0.5 * np.sin(TAU * np.arange(int(total * MSR)) / MSR / total * 3))
    mx.add(wind, 0, 0.1, 0.3, 0.5)
    return mx.render(4.0, 1.3)


def song_legendary():
    mx = Mix(4.0, loop=False)
    mx.add(d_timp(65.4), 0.0, 0.5, 0, 0.3)
    for i, m in enumerate((60, 64, 67, 72)):
        mx.add(i_brass(mtof(m), 0.14), i * 0.12, 0.3, -0.2 + 0.13 * i, 0.4)
    for j, m in enumerate((60, 64, 67, 72, 76)):
        mx.add(i_brass(mtof(m), 1.8, 0.6), 0.5, 0.18, -0.5 + 0.25 * j, 0.45)
        mx.add(i_strings(mtof(m + 12), 1.8, 0.2, 0.7, 0.8), 0.5, 0.08, 0.5 - 0.25 * j, 0.5)
    rr = np.random.default_rng(9)
    pent = (84, 86, 88, 91, 93, 96)
    for k in range(14):
        mx.add(i_bell(mtof(pent[rr.integers(0, 6)]), 0.3, 2.0, 1.2, 0.5), 0.45 + k * 0.1, 0.12, rr.uniform(-0.8, 0.8), 0.6)
    return mx.render(2.4, 0.9, max_sec=3.3)


def song_mythic():
    mx = Mix(7.0, loop=False)
    mx.add(d_boom(), 0.0, 0.8, 0, 0.3)
    t = T(1.0, MSR)
    timp = d_timp(55.0)
    for k in range(14):
        mx.add(timp, k * 0.07, 0.08 + 0.025 * k, -0.2 + 0.03 * k, 0.3)
    y, tt = additive(mtof(48), 1.0, [1, 0.5, 0.3, 0.2, 0.1], tail=0.02)
    mx.add(y * np.clip(tt / 1.0, 0, 1) ** 3, 0.0, 0.3, 0, 0.6)
    for j, m in enumerate((48, 49, 54, 60, 61)):
        mx.add(i_brass(mtof(m), 1.0, 0.3), 1.0, 0.16, -0.5 + 0.25 * j, 0.45)
    mx.add(d_boom(), 1.0, 0.5, 0, 0.3)
    for j, m in enumerate((48, 51, 55, 60, 63)):
        mx.add(i_brass(mtof(m), 2.4, 0.8), 2.2, 0.15, -0.5 + 0.25 * j, 0.5)
        mx.add(i_choir(mtof(m + 12), 2.6, FORM_AH, 1.0), 2.1, 0.16, 0.5 - 0.25 * j, 0.6)
    mx.add(d_timp(65.4), 2.2, 0.6, 0, 0.4)
    mx.add(i_bell(mtof(36), 3.0, 1.4, 4.0, 2.5), 2.2, 0.35, 0, 0.6)
    return mx.render(3.0, 1.0, drive=1.4, max_sec=6.0)


def song_era_unlock():
    mx = Mix(9.0, loop=False)
    timp = d_timp(65.4)
    for k in range(18):
        mx.add(timp, k * 0.065, 0.06 + 0.02 * k, 0.0, 0.3)
    seq = [(1.2, ("C", "maj")), (2.2, ("F", "maj")), (3.2, ("G", "maj")), (4.2, ("C", "maj"))]
    for idx, (at, ch) in enumerate(seq):
        dur = 0.9 if idx < 3 else 2.4
        for j, m in enumerate(chord_notes(ch, 3)):
            mx.add(i_brass(mtof(m), dur, 0.4), at, 0.13, -0.5 + 0.5 * j, 0.45)
            mx.add(i_strings(mtof(m + 12), dur, 0.15, 0.6, 0.9), at, 0.08, 0.5 - 0.5 * j, 0.5)
            mx.add(i_choir(mtof(m + 12), dur, FORM_AH, 0.8), at, 0.08, 0.0, 0.6)
        mx.add(timp, at, 0.5, 0, 0.35)
    top = [(1.2, 72, 0.45), (1.7, 74, 0.45), (2.2, 77, 0.9), (3.2, 79, 0.45), (3.7, 83, 0.45), (4.2, 84, 2.4)]
    for at, m, d in top:
        mx.add(i_brass(mtof(m), d, 0.4), at, 0.22, 0.0, 0.45)
    mx.add(d_crash(), 4.2, 0.35, 0.2, 0.4)
    rr = np.random.default_rng(12)
    for k in range(16):
        mx.add(i_bell(mtof((84, 88, 91, 96)[rr.integers(0, 4)]), 0.3, 2.0, 1.0, 0.6), 4.2 + k * 0.12, 0.1, rr.uniform(-0.8, 0.8), 0.6)
    return mx.render(2.8, 0.9, max_sec=7.8)


def song_tension():
    """Exploration under threat: low pulse, string tremolo, sparse toms."""
    r = np.random.default_rng(909)
    bpm, bpb, bars = 84.0, 4, 12
    beat = 60.0 / bpm
    total = bars * bpb * beat
    mx = Mix(total)
    cyc = [("D", "min"), ("D", "min"), ("Bb", "maj"), ("A", "maj")]
    for i in range(bars):
        ch = cyc[i % 4]
        base = i * bpb * beat
        cn = chord_notes(ch, 3)
        for j, m in enumerate(cn[:3]):
            mx.add(i_strings(mtof(m - 12), bpb * beat * 0.98, 0.6, 0.6, 0.5), base, 0.11, -0.4 + 0.4 * j, 0.45)
        root = 12 * 2 + NOTE[ch[0]]
        if root > 40:
            root -= 12
        for s in range(8):
            mx.add(i_bass(mtof(root), 0.3, 8.0), base + s * 0.5 * beat, 0.22 if s % 2 == 0 else 0.12, 0.0, 0.15)
        if i % 2 == 1:
            mx.add(d_tom(95), base + 3.0 * beat, 0.3, -0.3, 0.35)
            mx.add(d_tom(80), base + 3.5 * beat, 0.25, 0.3, 0.35)
    for k in range(10):
        mx.add(i_bell(mtof(74 + int(r.integers(0, 6))), 1.0, 3.5, 1.0, 1.4), r.uniform(0, total), 0.06, r.uniform(-0.8, 0.8), 0.7)
    return mx.render(2.8, 1.0)


def song_combat():
    """Field combat: driving drums, staccato low strings, brass hits."""
    r = np.random.default_rng(1001)
    bpm, bpb, bars = 132.0, 4, 16
    beat = 60.0 / bpm
    mx = Mix(bars * bpb * beat)
    cyc = [("E", "min"), ("C", "maj"), ("D", "maj"), ("B", "maj")]
    kick, snare, hat, crash = d_kick(115, 45, 0.14), d_snare(), d_hat(), d_crash()
    for i in range(bars):
        ch = cyc[i % 4]
        base = i * bpb * beat
        for s in range(8):
            if s in (0, 3, 4, 6):
                mx.add(kick, base + s * 0.5 * beat, 0.5)
            mx.add(hat, base + s * 0.5 * beat + human(r, 0.003), 0.12, 0.3, 0.1)
        mx.add(snare, base + 1 * beat, 0.42, 0.05, 0.25)
        mx.add(snare, base + 3 * beat, 0.42, 0.05, 0.25)
        if i % 4 == 0:
            mx.add(crash, base, 0.2, 0.3, 0.3)
        root = 12 * 2 + NOTE[ch[0]]
        if root > 40:
            root -= 12
        for s in range(16):
            m = root + (12 if s % 4 == 2 else 0)
            mx.add(i_stacc(mtof(m), 0.1), base + s * 0.25 * beat, 0.18, -0.2, 0.2)
        cn = chord_notes(ch, 4)
        for j, m in enumerate(cn[:3]):
            mx.add(i_brass(mtof(m - 12), 0.4 * beat), base, 0.1, -0.4 + 0.4 * j, 0.35)
            if i % 2 == 1:
                mx.add(i_brass(mtof(m - 12), 0.3 * beat), base + 2.5 * beat, 0.08, -0.4 + 0.4 * j, 0.35)
    return mx.render(2.0, 0.8, drive=1.4)


def song_ritual():
    """Cleansing ritual / sanctuary: choir pads, bells, soft drone."""
    r = np.random.default_rng(1111)
    bpm, bpb, bars = 60.0, 4, 8
    beat = 60.0 / bpm
    total = bars * bpb * beat
    mx = Mix(total)
    cyc = [("F", "maj"), ("D", "min"), ("Bb", "maj"), ("C", "maj")]
    for i in range(bars):
        ch = cyc[i % 4]
        base = i * bpb * beat
        for j, m in enumerate(chord_notes(ch, 3)[:3]):
            mx.add(i_choir(mtof(m + 12), bpb * beat * 0.98, FORM_AH, 0.8), base, 0.1, -0.5 + 0.5 * j, 0.6)
    arp = scale_notes("F", "major", 72, 91)
    for k in range(24):
        mx.add(i_bell(mtof(arp[int(r.integers(0, len(arp)))]), 1.4, 2.0, 1.2, 1.8), k * total / 24 + human(r, 0.05), 0.08, r.uniform(-0.7, 0.7), 0.8)
    t = T(total + 1.0, MSR)
    mx.add(np.sin(TAU * 43.65 * t) * 0.8, 0, 0.12, 0, 0.3)
    return mx.render(4.0, 1.2)


SONGS = {
    "menu": song_menu, "era0": song_era0, "era1": song_era1, "era2": song_era2, "era3": song_era3,
    "era4": song_era4, "boss": song_boss, "rift": song_rift,
    "legendary_sting": song_legendary, "mythic_sting": song_mythic, "era_unlock": song_era_unlock,
    "tension": song_tension, "combat": song_combat, "ritual": song_ritual,
}


def gen_music(only=None):
    os.makedirs(MUS_DIR, exist_ok=True)
    for name, fn in SONGS.items():
        if only and name not in only:
            continue
        t0 = time.time()
        x = fn()
        rms_db = 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-9)
        if rms_db > -12.5:
            x = x * 10 ** ((-12.5 - rms_db) / 20.0)
        write_ogg(os.path.join(MUS_DIR, name + ".ogg"), x, MSR, 3)
        print("music %-16s %.1fs audio, %.1fs to render" % (name, x.shape[1] / MSR, time.time() - t0))


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args or "sfx" in args:
        gen_sfx()
    if not args or "music" in args:
        gen_music()
    elif len(args) > 0 and args[0] == "song":
        gen_music(args[1:])
