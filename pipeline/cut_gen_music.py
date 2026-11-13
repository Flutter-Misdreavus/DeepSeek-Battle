#!/usr/bin/env python3
"""Cut the generated soundtrack (MiniMax Music 3 takes) into game sections.

Put the chosen take of each track in assets/audio/gen/<name>.<mp3|wav|flac>
(names: title p1 p2 p3 final gameover ending), then run from the repo root:
    python3 -I pipeline/cut_gen_music.py            # all tracks found
    python3 -I pipeline/cut_gen_music.py p2 final   # only these

For every track the tempo and the beat grid are measured (librosa beat tracking,
then a least-squares line through the beat times so the grid does not drift).
- Looping tracks (title p1 p2 p3 ending): the loop is a whole number of 4-beat bars
  whose start and end sound most alike (chroma + loudness), joined with a
  10 ms crossfade.  p1 also yields "intro" = its first 32 beats, which the
  opening chat scene plays before the battle loop starts.
- One-shot tracks (final gameover): from the first beat to the end,
  trailing silence trimmed.
Output: game/audio/music/<section>.wav and sections.json (per-section "bpm").
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

os.environ.setdefault("NUMBA_CACHE_DIR", str(Path(tempfile.gettempdir()) / "deepseek_battle_numba_cache"))

import librosa
import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "audio" / "gen"
OUT = ROOT / "game" / "audio" / "music"
SR = 44100
GAIN_PEAK = 0.89
XFADE = int(0.010 * SR)
LOOPING = {"title", "p1", "p2", "p3", "ending"}
ORDER = ["title", "p1", "p2", "p3", "final", "gameover", "ending"]
HINT_BPM = {"title": 84, "p1": 110, "p2": 124, "p3": 140, "final": 150, "gameover": 72, "ending": 80}   # 提示词里写的速度
INTRO_BEATS = 32


def decode(path: Path) -> np.ndarray:
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(path), "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"]
    raw = subprocess.run(cmd, check=True, stdout=subprocess.PIPE).stdout
    return np.frombuffer(raw, dtype="<f4").reshape(-1, 2).copy()


def beat_grid(mono: np.ndarray, hint: float) -> tuple[float, float, float]:
    """Return (bpm, time of beat 0, grid score).

    A rough tempo from librosa is snapped to the octave nearest the prompt's
    BPM, then the whole-track grid (tempo + phase) is refined by maximizing
    the mean onset strength sampled at the grid points — this keeps a long
    track from drifting even if the tracker skipped a beat somewhere.
    """
    hop = 256
    env = librosa.onset.onset_strength(y=mono, sr=SR, hop_length=hop)
    env = env / (env.max() + 1e-9)
    fps = SR / hop
    rough, _ = librosa.beat.beat_track(onset_envelope=env, sr=SR, hop_length=hop, start_bpm=hint)
    rough = float(np.atleast_1d(rough)[0])
    rough = min((rough * k for k in (0.5, 2 / 3, 0.75, 1.0, 4 / 3, 1.5, 2.0)), key=lambda b: abs(b - hint))
    dur = len(env) / fps
    best = (0.0, rough, 0.0)
    for bpm in np.arange(rough * 0.97, rough * 1.03, 0.01):
        spb = 60.0 / bpm
        grid = np.arange(0.0, dur - spb, spb)
        phases = np.arange(0.0, spb, 1.0 / fps)
        idx = ((grid[None, :] + phases[:, None]) * fps).astype(int)
        idx = np.clip(idx, 0, len(env) - 1)
        scores = env[idx].mean(axis=1)
        i = int(np.argmax(scores))
        if scores[i] > best[0]:
            best = (float(scores[i]), float(bpm), float(phases[i]))
    return best[1], best[2], best[0]


def bar_features(mono: np.ndarray, t0: float, spb: float, beat: int) -> tuple[np.ndarray, float]:
    a = int((t0 + beat * spb) * SR)
    w = mono[a : a + int(spb * SR)]
    chroma = librosa.feature.chroma_stft(y=w, sr=SR).mean(axis=1)
    return chroma, float(np.sqrt(np.mean(w * w)) + 1e-9)


def seam(mono: np.ndarray, t0: float, spb: float, s: int, e: int) -> float:
    ca, ra = bar_features(mono, t0, spb, s)
    cb, rb = bar_features(mono, t0, spb, e)
    cos = float(np.dot(ca, cb) / (np.linalg.norm(ca) * np.linalg.norm(cb) + 1e-9))
    return cos - 2.0 * abs(ra - rb) / max(ra, rb)


def choose_loop(mono: np.ndarray, t0: float, spb: float, total_beats: int, min_start: int) -> tuple[int, int, float]:
    best = None
    for s in range(min_start, min_start + 33, 4):
        for length in (32, 48, 64, 96, 128):
            e = s + length
            if e + 1 > total_beats:
                continue
            sc = seam(mono, t0, spb, s, e)
            if best is None or sc > best[2]:
                best = (s, e, sc)
    if best is None:
        raise RuntimeError("track too short for a loop")
    return best


def write(name: str, audio: np.ndarray) -> None:
    peak = float(np.max(np.abs(audio))) or 1.0
    audio = audio * min(1.0, GAIN_PEAK / peak)
    sf.write(OUT / f"{name}.wav", audio.astype(np.float32), SR, subtype="PCM_16")


def loop_clip(audio: np.ndarray, a: int, b: int) -> np.ndarray:
    seg = audio[a:b].copy()
    if a >= XFADE:
        ramp = np.linspace(0.0, 1.0, XFADE)[:, None]
        seg[-XFADE:] = seg[-XFADE:] * (1 - ramp) + audio[a - XFADE : a] * ramp
    return seg


def trim_tail(audio: np.ndarray) -> np.ndarray:
    level = np.abs(audio).max(axis=1)
    loud = np.nonzero(level > 0.01)[0]
    end = int(loud[-1]) + int(0.3 * SR) if len(loud) else len(audio)
    return audio[: min(end, len(audio))]


def main() -> None:
    want = sys.argv[1:] or ORDER
    OUT.mkdir(parents=True, exist_ok=True)
    meta_path = OUT / "sections.json"
    meta = json.loads(meta_path.read_text()) if meta_path.exists() else {"sections": {}}
    meta.pop("placeholder", None)
    for name in want:
        files = sorted(SRC.glob(f"{name}.*"))
        if not files:
            print(f"{name:9s} (没有文件，跳过)")
            continue
        audio = decode(files[0])
        mono = audio.mean(axis=1)
        bpm, t0, gscore = beat_grid(mono, HINT_BPM[name])
        spb = 60.0 / bpm
        total = int((len(audio) / SR - t0) / spb)
        if name in LOOPING:
            start_min = INTRO_BEATS if name == "p1" else 0
            s, e, sc = choose_loop(mono, t0, spb, total, start_min)
            a = int((t0 + s * spb) * SR)
            b = int((t0 + e * spb) * SR)
            write(name, loop_clip(audio, a, b))
            meta["sections"][name] = {"bpm": round(bpm, 3), "beats": e - s, "length_sec": (b - a) / SR,
                                      "loop": True, "first_beat_in_clip": 0.0, "seam_score": round(sc, 4),
                                      "source": files[0].name, "source_beats": [s, e]}
            info = f"loop {s}-{e} ({e - s} beats) seam {sc:.3f}"
            if name == "p1":
                ia = int(t0 * SR)
                ib = int((t0 + INTRO_BEATS * spb) * SR)
                write("intro", audio[ia:ib])
                meta["sections"]["intro"] = {"bpm": round(bpm, 3), "beats": INTRO_BEATS, "length_sec": (ib - ia) / SR,
                                             "loop": False, "first_beat_in_clip": 0.0, "source": files[0].name}
                info += f" + intro 0-{INTRO_BEATS}"
        else:
            a = int(max(0.0, t0) * SR)
            clip = trim_tail(audio[a:])
            write(name, clip)
            meta["sections"][name] = {"bpm": round(bpm, 3), "beats": int(len(clip) / SR / spb), "length_sec": len(clip) / SR,
                                      "loop": False, "first_beat_in_clip": 0.0, "source": files[0].name}
            info = f"one-shot {len(clip) / SR:.1f}s"
        print(f"{name:9s} {bpm:7.2f} BPM  beat0 {t0:6.3f}s  grid {gscore:.3f}  {info}")
    meta_path.write_text(json.dumps(meta, indent=2, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
