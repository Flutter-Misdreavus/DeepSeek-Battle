#!/usr/bin/env python3
"""Synthesize all game sound effects from scratch with numpy.

Run from the repository root:
    python3 -I pipeline/sfx_synth.py

No external audio is read.  Every effect is a table of oscillator/noise layers;
phases are integrated so slides and vibrato remain in tune.  Each effect is
peak-normalized to -1 dBFS, then given short anti-click fades and written as a
mono 16-bit 44.1 kHz WAV.
"""

from __future__ import annotations

import math
import zlib
from pathlib import Path

import numpy as np
import scipy.signal
import soundfile as sf

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "game" / "audio" / "sfx"
PREVIEW_DIR = ROOT / "pipeline" / "out"
SR = 44100
TARGET_PEAK = 0.891  # -1 dBFS
FADE_IN = int(round(0.002 * SR))
FADE_OUT = int(round(0.005 * SR))
PREVIEW_GAP = 0.4


SFX_TABLE: list[dict[str, object]] = [
    {
        "name": "menu_move",
        "layers": [
            {"wave": "square", "f0": 880, "dur": 0.03, "r": 0.02, "vol": 0.35},
        ],
    },
    {
        "name": "menu_select",
        "layers": [
            {
                "wave": "square",
                "duty": 0.25,
                "f0": 660,
                "arp": [0, 7],
                "arp_step": 0.04,
                "dur": 0.08,
                "vol": 0.4,
            },
        ],
    },
    {
        "name": "menu_back",
        "layers": [
            {"wave": "square", "f0": 520, "f1": 390, "dur": 0.07, "vol": 0.35},
        ],
    },
    {
        "name": "text_sys",
        "layers": [
            {
                "wave": "square",
                "duty": 0.125,
                "f0": 1200,
                "dur": 0.018,
                "r": 0.01,
                "vol": 0.18,
            },
        ],
    },
    {
        "name": "voice_blue",
        "layers": [
            {"wave": "triangle", "f0": 520, "dur": 0.035, "vol": 0.3},
            {"wave": "square", "f0": 1040, "dur": 0.035, "vol": 0.1},
        ],
    },
    {
        "name": "voice_red",
        "layers": [
            {
                "wave": "square",
                "f0": 360,
                "dur": 0.04,
                "crush": 4,
                "vol": 0.3,
            },
        ],
    },
    {
        "name": "slash",
        "layers": [
            {
                "wave": "noise",
                "f0": 22050,
                "dur": 0.25,
                "a": 0.001,
                "d": 0.25,
                "s": 0,
                "vol": 0.4,
            },
            {
                "wave": "square",
                "f0": 1600,
                "f1": 200,
                "dur": 0.18,
                "vol": 0.25,
            },
        ],
    },
    {
        "name": "hit_enemy",
        "layers": [
            {
                "wave": "square",
                "f0": 140,
                "f1": 60,
                "dur": 0.15,
                "crush": 6,
                "vol": 0.5,
            },
            {
                "wave": "noise",
                "f0": 11025,
                "dur": 0.08,
                "d": 0.08,
                "s": 0,
                "vol": 0.4,
            },
        ],
    },
    {
        "name": "miss",
        "layers": [
            {"wave": "triangle", "f0": 600, "f1": 300, "dur": 0.2, "vol": 0.25},
        ],
    },
    {
        "name": "player_hurt",
        "layers": [
            {"wave": "square", "f0": 300, "f1": 80, "dur": 0.12, "vol": 0.5},
            {
                "wave": "noise",
                "f0": 8000,
                "dur": 0.06,
                "crush": 5,
                "vol": 0.35,
            },
        ],
    },
    {
        "name": "heart_crack",
        "layers": [
            {"wave": "noise", "f0": 16000, "dur": 0.05, "vol": 0.6},
            {
                "wave": "square",
                "f0": 200,
                "dur": 0.05,
                "crush": 3,
                "vol": 0.4,
            },
        ],
    },
    {
        "name": "heart_shatter",
        "layers": [
            {
                "wave": "noise",
                "f0": 12000,
                "dur": 0.35,
                "d": 0.35,
                "s": 0,
                "vol": 0.5,
            },
            {"wave": "square", "f0": 900, "dur": 0.04, "vol": 0.25, "delay": 0},
            {
                "wave": "square",
                "f0": 700,
                "dur": 0.04,
                "vol": 0.25,
                "delay": 0.05,
            },
            {
                "wave": "square",
                "f0": 1100,
                "dur": 0.04,
                "vol": 0.25,
                "delay": 0.10,
            },
            {
                "wave": "square",
                "f0": 500,
                "dur": 0.04,
                "vol": 0.25,
                "delay": 0.15,
            },
        ],
    },
    {
        "name": "heal",
        "layers": [
            {
                "wave": "triangle",
                "f0": 523,
                "arp": [0, 4, 7, 12],
                "arp_step": 0.06,
                "dur": 0.3,
                "vol": 0.35,
            },
        ],
    },
    {
        "name": "spare",
        "layers": [
            {
                "wave": "sine",
                "f0": 880,
                "dur": 0.7,
                "a": 0.001,
                "d": 0.6,
                "s": 0,
                "vol": 0.3,
            },
            {
                "wave": "sine",
                "f0": 1320,
                "dur": 0.7,
                "a": 0.001,
                "d": 0.5,
                "s": 0,
                "vol": 0.2,
            },
            {
                "wave": "noise",
                "f0": 6000,
                "dur": 0.5,
                "lp": 0.08,
                "d": 0.5,
                "s": 0,
                "vol": 0.15,
            },
        ],
    },
    {
        "name": "levelup",
        "layers": [
            {
                "wave": "square",
                "duty": 0.25,
                "f0": 440,
                "arp": [0, 6, 12],
                "arp_step": 0.05,
                "dur": 0.18,
                "crush": 5,
                "vol": 0.3,
            },
        ],
    },
    {
        "name": "warn",
        "layers": [
            {"wave": "square", "f0": 1320, "dur": 0.06, "vol": 0.25},
            {
                "wave": "square",
                "f0": 1320,
                "dur": 0.06,
                "delay": 0.09,
                "vol": 0.25,
            },
        ],
    },
    {
        "name": "beam",
        "layers": [
            {
                "wave": "saw",
                "f0": 110,
                "dur": 0.4,
                "a": 0.005,
                "d": 0.35,
                "s": 0.2,
                "vib": [30, 0.03],
                "vol": 0.35,
            },
            {
                "wave": "noise",
                "f0": 9000,
                "dur": 0.4,
                "lp": 0.2,
                "d": 0.4,
                "s": 0,
                "vol": 0.25,
            },
        ],
    },
    {
        "name": "spinner_burst",
        "layers": [
            {
                "wave": "noise",
                "f0": 10000,
                "dur": 0.12,
                "d": 0.12,
                "s": 0,
                "vol": 0.4,
            },
            {
                "wave": "square",
                "f0": 700,
                "f1": 200,
                "dur": 0.12,
                "vol": 0.3,
            },
        ],
    },
    {
        "name": "popup_open",
        "layers": [
            {
                "wave": "square",
                "duty": 0.25,
                "f0": 784,
                "arp": [0, 5],
                "arp_step": 0.04,
                "dur": 0.1,
                "vol": 0.3,
            },
        ],
    },
    {
        "name": "stamp",
        "layers": [
            {
                "wave": "noise",
                "f0": 6000,
                "dur": 0.06,
                "lp": 0.3,
                "vol": 0.5,
            },
            {
                "wave": "square",
                "f0": 90,
                "f1": 50,
                "dur": 0.1,
                "vol": 0.55,
            },
        ],
    },
    {
        "name": "shatter",
        "layers": [
            {
                "wave": "noise",
                "f0": 14000,
                "dur": 0.25,
                "d": 0.25,
                "s": 0,
                "crush": 4,
                "vol": 0.4,
            },
            {
                "wave": "square",
                "f0": 1800,
                "f1": 900,
                "dur": 0.06,
                "vol": 0.2,
            },
            {
                "wave": "square",
                "f0": 1300,
                "f1": 600,
                "dur": 0.06,
                "delay": 0.05,
                "vol": 0.2,
            },
        ],
    },
    {
        "name": "marquee",
        "layers": [
            {"wave": "noise", "f0": 4000, "dur": 0.3, "lp": 0.5, "vol": 0.1},
        ],
    },
    {
        "name": "delete",
        "layers": [
            {"wave": "square", "f0": 220, "f1": 55, "dur": 0.25, "vol": 0.5},
            {
                "wave": "noise",
                "f0": 9000,
                "dur": 0.2,
                "crush": 4,
                "d": 0.2,
                "s": 0,
                "vol": 0.4,
            },
        ],
    },
    {
        "name": "click",
        "layers": [
            {
                "wave": "square",
                "f0": 2400,
                "dur": 0.012,
                "r": 0.005,
                "vol": 0.35,
            },
            {"wave": "noise", "f0": 20000, "dur": 0.01, "vol": 0.3},
        ],
    },
    {
        "name": "spread",
        "layers": [
            {
                "wave": "triangle",
                "f0": 180,
                "f1": 160,
                "dur": 0.08,
                "crush": 5,
                "vol": 0.25,
            },
        ],
    },
    {
        "name": "rewind",
        "layers": [
            {
                "wave": "saw",
                "f0": 200,
                "f1": 1600,
                "dur": 0.6,
                "a": 0.05,
                "vol": 0.3,
            },
            {
                "wave": "noise",
                "f0": 5000,
                "dur": 0.6,
                "lp": 0.3,
                "vol": 0.15,
            },
        ],
    },
    {
        "name": "brick",
        "layers": [
            {
                "wave": "noise",
                "f0": 5000,
                "dur": 0.05,
                "lp": 0.15,
                "vol": 0.45,
            },
            {
                "wave": "triangle",
                "f0": 110,
                "f1": 70,
                "dur": 0.08,
                "vol": 0.45,
            },
        ],
    },
    {
        "name": "slam",
        "layers": [
            {"wave": "square", "f0": 80, "f1": 35, "dur": 0.35, "vol": 0.7},
            {
                "wave": "noise",
                "f0": 7000,
                "dur": 0.3,
                "lp": 0.25,
                "crush": 4,
                "d": 0.3,
                "s": 0,
                "vol": 0.5,
            },
        ],
    },
    {
        "name": "crack",
        "layers": [
            {"wave": "noise", "f0": 18000, "dur": 0.09, "vol": 0.35},
            {
                "wave": "square",
                "f0": 3000,
                "f1": 800,
                "dur": 0.05,
                "vol": 0.25,
            },
        ],
    },
    {
        "name": "glitch",
        "layers": [
            {
                "wave": "noise",
                "f0": 3000,
                "dur": 0.25,
                "gate": [0.03, 0.5],
                "crush": 3,
                "vol": 0.3,
            },
        ],
    },
    {
        "name": "transition",
        "layers": [
            {
                "wave": "saw",
                "f0": 80,
                "f1": 800,
                "dur": 1.2,
                "a": 1.0,
                "r": 0.05,
                "vol": 0.4,
            },
            {
                "wave": "noise",
                "f0": 12000,
                "dur": 0.5,
                "delay": 1.2,
                "d": 0.5,
                "s": 0,
                "vol": 0.5,
            },
            {
                "wave": "square",
                "f0": 60,
                "f1": 30,
                "dur": 0.4,
                "delay": 1.2,
                "vol": 0.5,
            },
        ],
    },
    {
        "name": "ash",
        "layers": [
            {
                "wave": "noise",
                "f0": 9000,
                "dur": 1.2,
                "a": 0.1,
                "d": 1.1,
                "s": 0,
                "lp": 0.15,
                "vol": 0.3,
            },
        ],
    },
    {
        "name": "boot",
        "layers": [
            {
                "wave": "square",
                "f0": 110,
                "arp": [0, 12, 24],
                "arp_step": 0.08,
                "dur": 0.26,
                "crush": 4,
                "vol": 0.35,
            },
        ],
    },
    {
        "name": "version_tick",
        "layers": [
            {
                "wave": "square",
                "duty": 0.25,
                "f0": 1500,
                "dur": 0.02,
                "r": 0.01,
                "vol": 0.2,
            },
        ],
    },
    {
        "name": "stop_press",
        "layers": [
            {"wave": "square", "f0": 660, "f1": 440, "dur": 0.08, "vol": 0.35},
            {
                "wave": "square",
                "f0": 440,
                "dur": 0.05,
                "delay": 0.08,
                "vol": 0.3,
            },
        ],
    },
]


def make_rng(name: str) -> np.random.Generator:
    seed = zlib.crc32(name.encode("utf-8")) & 0xFFFFFFFF
    return np.random.default_rng(seed)


def frequency_curve(n: int, layer: dict[str, object]) -> np.ndarray:
    f0 = float(layer["f0"])
    dur = float(layer["dur"])
    f1 = float(layer.get("f1", f0))
    t = np.arange(n, dtype=np.float64) / SR

    if "arp" in layer:
        step = float(layer.get("arp_step", 0.05))
        step_samples = max(1, int(round(step * SR)))
        semitones = np.asarray(layer["arp"], dtype=np.float64)
        indices = (np.arange(n) // step_samples) % len(semitones)
        frequencies = f0 * np.power(2.0, semitones[indices] / 12.0)
    elif f1 == f0:
        frequencies = np.full(n, f0, dtype=np.float64)
    elif layer.get("slide", "exp") == "lin":
        frequencies = np.linspace(f0, f1, n, endpoint=False)
    else:
        frequencies = f0 * np.power(f1 / f0, t / dur)

    vibrato = layer.get("vib")
    if vibrato:
        vib_hz, depth = float(vibrato[0]), float(vibrato[1])
        frequencies = frequencies * (
            1.0 + depth * np.sin(2.0 * math.pi * vib_hz * t)
        )
    return np.maximum(frequencies, 1.0)


def oscillator(
    n: int, layer: dict[str, object], rng: np.random.Generator
) -> np.ndarray:
    wave = str(layer["wave"])
    frequencies = frequency_curve(n, layer)
    phase = np.cumsum(frequencies) / SR

    if wave == "square":
        duty = float(layer.get("duty", 0.5))
        return np.where((phase % 1.0) < duty, 1.0, -1.0)
    if wave == "triangle":
        return 2.0 * np.abs(2.0 * (phase % 1.0) - 1.0) - 1.0
    if wave == "sine":
        return np.sin(2.0 * math.pi * phase)
    if wave == "saw":
        return 2.0 * (phase % 1.0) - 1.0
    if wave == "noise":
        # Sample-and-hold: one new random value per oscillator cycle.  A high
        # f0 therefore sounds like bright hiss, a low one like coarse noise.
        step_indices = np.floor(phase).astype(np.int64)
        held = rng.uniform(-1.0, 1.0, size=int(step_indices.max()) + 2)
        return held[step_indices]
    raise ValueError(f"unknown wave: {wave}")


def envelope(n: int, layer: dict[str, object]) -> np.ndarray:
    attack = float(layer.get("a", 0.002))
    decay = float(layer.get("d", 0))
    sustain = float(layer.get("s", 1.0))
    release = float(layer.get("r", 0.02))

    env = np.ones(n, dtype=np.float64)
    attack_n = min(n, max(0, int(round(attack * SR))))
    if attack_n:
        env[:attack_n] = np.arange(attack_n, dtype=np.float64) / attack_n

    decay_n = min(max(0, n - attack_n), max(0, int(round(decay * SR))))
    if decay_n:
        env[attack_n : attack_n + decay_n] = np.linspace(
            1.0, sustain, decay_n
        )
        env[attack_n + decay_n :] = sustain
    else:
        env[attack_n:] = sustain

    release_n = min(n, max(0, int(round(release * SR))))
    if release_n:
        # Multiplying by the ramp is equivalent to starting the release at the
        # current envelope value; if release overlaps attack it still sounds.
        env[n - release_n :] *= np.linspace(1.0, 0.0, release_n)
    return env


def bitcrush(samples: np.ndarray, bits: int) -> np.ndarray:
    levels = 2 ** int(bits)
    if levels <= 1:
        return np.zeros_like(samples)
    return (
        np.round((samples + 1.0) * 0.5 * (levels - 1))
        / (levels - 1)
        * 2.0
        - 1.0
    )


def render_layer(
    layer: dict[str, object], rng: np.random.Generator
) -> np.ndarray:
    duration = float(layer["dur"])
    n = int(round(duration * SR))
    if n <= 0:
        raise ValueError(f"layer duration too short: {layer}")

    samples = oscillator(n, layer, rng)
    if "crush" in layer:
        samples = bitcrush(samples, int(layer["crush"]))
    samples = samples * envelope(n, layer)

    if "lp" in layer:
        coefficient = float(layer["lp"])
        samples = scipy.signal.lfilter(
            [coefficient], [1.0, -(1.0 - coefficient)], samples
        )

    if "gate" in layer:
        block_sec, keep_probability = layer["gate"]
        block_n = max(1, int(round(float(block_sec) * SR)))
        block_count = int(math.ceil(n / block_n))
        keep = rng.random(block_count) < float(keep_probability)
        gate = np.repeat(keep.astype(np.float64), block_n)[:n]
        samples = samples * gate

    samples = samples * float(layer.get("vol", 0.5))
    delay_n = max(0, int(round(float(layer.get("delay", 0.0)) * SR)))
    if delay_n:
        samples = np.pad(samples, (delay_n, 0))
    return samples


def render_sfx(name: str, layers: list[dict[str, object]]) -> tuple[np.ndarray, float]:
    rng = make_rng(name)
    rendered = [render_layer(layer, rng) for layer in layers]
    total_n = max(len(layer) for layer in rendered)
    mix = np.zeros(total_n, dtype=np.float64)
    for layer in rendered:
        mix[: len(layer)] += layer

    peak_before = float(np.max(np.abs(mix)))
    if peak_before <= 0.0:
        raise ValueError(f"{name} rendered silence")
    mix *= TARGET_PEAK / peak_before

    mix[:FADE_IN] *= np.linspace(0.0, 1.0, FADE_IN, endpoint=False)
    mix[-FADE_OUT:] *= np.linspace(1.0, 0.0, FADE_OUT)
    return mix, peak_before


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)

    output: list[np.ndarray] = []
    print(f"合成 {len(SFX_TABLE)} 个音效 -> {OUT_DIR.relative_to(ROOT)}")
    print("name             dur_s     pre_peak    post_peak")
    for entry in SFX_TABLE:
        name = str(entry["name"])
        layers = entry["layers"]
        samples, peak_before = render_sfx(name, layers)
        path = OUT_DIR / f"{name}.wav"
        sf.write(path, samples, SR, subtype="PCM_16")

        check, check_sr = sf.read(path, dtype="float32")
        if check_sr != SR or check.ndim != 1:
            raise RuntimeError(f"{name}: bad WAV layout")
        post_peak = float(np.max(np.abs(check)))
        if post_peak > 0.9:
            raise RuntimeError(f"{name}: peak {post_peak} exceeds 0.9")
        output.append(samples)

        print(
            f"{name:16s} {len(samples) / SR:7.4f} "
            f"{peak_before:10.6f} {post_peak:11.6f}"
        )

    if len(output) != len(SFX_TABLE):
        raise RuntimeError("not every table row was rendered")

    silence = np.zeros(int(round(PREVIEW_GAP * SR)), dtype=np.float64)
    preview_parts: list[np.ndarray] = []
    for index, samples in enumerate(output):
        if index:
            preview_parts.append(silence)
        preview_parts.append(samples)
    preview = np.concatenate(preview_parts)
    preview_path = PREVIEW_DIR / "sfx_preview.wav"
    sf.write(preview_path, preview, SR, subtype="PCM_16")

    preview_check, _ = sf.read(preview_path, dtype="float32")
    print(
        f"\n预览: {preview_path.relative_to(ROOT)} "
        f"({len(preview) / SR:.3f} s, 峰值 {np.max(np.abs(preview_check)):.6f})"
    )


if __name__ == "__main__":
    main()
