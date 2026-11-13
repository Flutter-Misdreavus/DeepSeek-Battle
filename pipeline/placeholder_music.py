#!/usr/bin/env python3
"""Synthesize placeholder music so the game can be built and timed before the
real soundtrack exists.  Every section is a plain chiptune loop at the tempo
the final track is meant to have; replace them with the real files later
(same names, update sections.json).

Run from the repository root:
    python3 -I pipeline/placeholder_music.py
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "game" / "audio" / "music"
SR = 44100

# name: (bpm, beats, loop, root midi note, style)
SECTIONS = {
    "title": (84, 32, True, 57, "soft"),
    "intro": (110, 32, False, 62, "intro"),
    "p1": (110, 32, True, 62, "groove"),
    "p2": (124, 32, True, 66, "deep"),
    "p3": (140, 32, True, 64, "hard"),
    "final": (150, 160, False, 60, "hard"),
    "gameover": (72, 16, False, 57, "soft"),
    "spare": (92, 48, False, 62, "major"),
    "kill": (70, 40, False, 61, "dark"),
}

MINOR = [0, -4, -9, -2]          # i  VI  III  VII  (offsets of chord roots)
MAJOR = [0, 7, 9, 5]             # I  V   vi   IV


def midi_hz(n: float) -> float:
    return 440.0 * 2 ** ((n - 69) / 12)


def env(n: int, a: float, d: float) -> np.ndarray:
    t = np.arange(n) / SR
    return np.minimum(1.0, t / max(a, 1e-4)) * np.exp(-t / d)


def square(f: float, n: int, duty: float = 0.5) -> np.ndarray:
    ph = (np.arange(n) * f / SR) % 1.0
    return np.where(ph < duty, 1.0, -1.0)


def tri(f: float, n: int) -> np.ndarray:
    ph = (np.arange(n) * f / SR) % 1.0
    return 4 * np.abs(ph - 0.5) - 1


def add(buf: np.ndarray, at: float, sig: np.ndarray, gain: float) -> None:
    i = int(at * SR)
    j = min(len(buf), i + len(sig))
    if i < len(buf):
        buf[i:j] += sig[: j - i] * gain


def kick(n: int) -> np.ndarray:
    t = np.arange(n) / SR
    f = 50 + 90 * np.exp(-t * 30)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9)


def noise(n: int, d: float, rng: np.random.Generator) -> np.ndarray:
    return rng.uniform(-1, 1, n) * np.exp(-np.arange(n) / SR / d)


def render(name: str, bpm: int, beats: int, root: int, style: str) -> np.ndarray:
    spb = 60.0 / bpm
    n = int(round(beats * spb * SR))
    buf = np.zeros(n)
    rng = np.random.default_rng(len(name))
    prog = MAJOR if style == "major" else MINOR
    third = 4 if style == "major" else 3
    for b in range(beats):
        t0 = b * spb
        bar = b // 4
        cr = root + prog[bar % 4]
        drums = style in ("groove", "deep", "hard")
        if drums or (style == "major" and b >= beats // 2):
            add(buf, t0, kick(int(0.25 * SR)), 0.55)
            if b % 2 == 1:
                add(buf, t0, noise(int(0.15 * SR), 0.05, rng), 0.25)
        if style in ("groove", "deep", "hard", "intro"):
            for h in (0.0, 0.5) if style != "intro" else (0.0,):
                add(buf, t0 + h * spb, noise(int(0.03 * SR), 0.008, rng), 0.10)
        if style == "dark" and b >= beats // 2:
            k = (b - beats // 2) / (beats // 2)
            for s in range(int(1 + 3 * k)):
                add(buf, t0 + s * spb / (1 + 3 * k), noise(int(0.02 * SR), 0.006, rng), 0.12)
        # bass: root on each beat (eighths when hard)
        bl = spb * (0.5 if style == "hard" else 0.9)
        for h in (0.0, 0.5) if style in ("hard", "deep") else (0.0,):
            m = int(bl * SR)
            add(buf, t0 + h * spb, tri(midi_hz(cr - 24), m) * env(m, 0.005, bl * 0.6), 0.30)
        # arpeggio: root, third, fifth, octave in 16ths / 8ths
        steps = 4 if style in ("groove", "hard", "deep") else 2
        if style in ("soft", "major", "dark"):
            steps = 2
        for s in range(steps):
            note = cr + [0, third, 7, 12][(b * steps + s) % 4]
            d = spb / steps
            m = int(d * 0.9 * SR)
            wave = square(midi_hz(note), m, 0.25) if style in ("groove", "hard", "deep") else tri(midi_hz(note + 12), m)
            g = 0.10 if style != "intro" else 0.05
            if style == "intro" and b < 4:
                g = 0.0
            add(buf, t0 + s * d, wave * env(m, 0.003, d * 0.5), g)
        # pad: whole bar chord at bar starts
        if b % 4 == 0:
            m = int(4 * spb * SR)
            pad = sum(tri(midi_hz(cr + o), m) for o in (0, third, 7)) / 3
            add(buf, t0, pad * env(m, 0.3, 4 * spb), 0.08)
    peak = np.max(np.abs(buf)) or 1.0
    return buf / peak * 0.6


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    meta = {"spb": 60.0 / 110.0, "placeholder": True, "sections": {}}
    for name, (bpm, beats, loop, root, style) in SECTIONS.items():
        y = render(name, bpm, beats, root, style)
        sf.write(OUT / f"{name}.wav", np.stack([y, y], axis=1).astype(np.float32), SR, subtype="PCM_16")
        meta["sections"][name] = {
            "bpm": bpm,
            "beats": beats,
            "length_sec": len(y) / SR,
            "loop": loop,
            "first_beat_in_clip": 0.0,
        }
        print(f"{name:9s} {bpm:3d} BPM  {beats:3d} beats  {len(y) / SR:6.2f}s  loop={loop}")
    (OUT / "sections.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
