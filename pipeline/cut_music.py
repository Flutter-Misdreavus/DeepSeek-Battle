#!/usr/bin/env python3
"""Cut the boss theme into game sections, choosing loop points by seam score.

Run from the repository root:
    python3 -I pipeline/cut_music.py

The source is decoded once with ffmpeg to raw little-endian float32 stereo and
all cuts are sample-accurate slices of that array.  Loop sections get a 10 ms
crossfade so that the last sample flows continuously into the first sample.
"""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import warnings
from pathlib import Path

# Numba (used by librosa's CQT) needs an explicitly writable cache directory
# under the isolated (-I) interpreter used for this project.  Keep generated
# caches out of the repository.
os.environ["NUMBA_CACHE_DIR"] = str(
    Path(tempfile.gettempdir()) / "deepseek_battle_numba_cache"
)
os.environ["MPLCONFIGDIR"] = str(
    Path(tempfile.gettempdir()) / "deepseek_battle_mplconfig"
)

import librosa
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets" / "audio" / "stronger_than_you.mp3"
OUT_DIR = ROOT / "game" / "audio" / "music"
PLOT_DIR = ROOT / "pipeline" / "out"

SR = 44100
BPM = 98.0
SPB = 60.0 / BPM
T0 = 0.18
BEAT_SAMPLES = int(round(SPB * SR))
LOOP_XFADE = int(round(0.010 * SR))
GAIN = 0.85

P1_STARTS = (16, 20, 24)
P1_LENGTHS = (32, 48, 64)
P2_STARTS = (104, 108, 112)
P2_ENDS = (140, 144, 148)
P3_STARTS = (76, 80)
P3_ENDS = (104, 108, 112)


def beat_sample(beat: float) -> int:
    """Absolute sample index of a beat according to t(b) = T0 + b * SPB."""
    return int(round((T0 + beat * SPB) * SR))


def decode_audio() -> np.ndarray:
    command = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        "-i",
        str(SOURCE),
        "-f",
        "f32le",
        "-ac",
        "2",
        "-ar",
        str(SR),
        "-",
    ]
    result = subprocess.run(
        command,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    audio = np.frombuffer(result.stdout, dtype="<f4").reshape(-1, 2).copy()
    if not len(audio):
        raise RuntimeError("ffmpeg returned no audio samples")
    return audio


class SeamScorer:
    """Cache chroma/RMS features for one-beat windows after each beat."""

    def __init__(self, audio: np.ndarray) -> None:
        self.audio = audio
        self.cache: dict[int, tuple[np.ndarray, float]] = {}

    def features(self, beat: int) -> tuple[np.ndarray, float]:
        if beat not in self.cache:
            start = beat_sample(beat)
            window = self.audio[start : start + BEAT_SAMPLES]
            mono = window.mean(axis=1)
            chroma = librosa.feature.chroma_cqt(y=mono, sr=SR).mean(axis=1)
            rms = float(librosa.feature.rms(y=mono).mean())
            self.cache[beat] = (chroma, rms)
        return self.cache[beat]

    def score(self, start_beat: int, end_beat: int) -> dict[str, float]:
        chroma_a, rms_a = self.features(start_beat)
        chroma_b, rms_b = self.features(end_beat)
        denominator = float(np.linalg.norm(chroma_a) * np.linalg.norm(chroma_b))
        chroma_similarity = (
            float(np.dot(chroma_a, chroma_b)) / denominator if denominator else 0.0
        )
        rms_denominator = max(float(rms_a), float(rms_b))
        rms_penalty = (
            2.0 * abs(float(rms_a) - float(rms_b)) / rms_denominator
            if rms_denominator
            else 0.0
        )
        return {
            "score": chroma_similarity - rms_penalty,
            "chroma": chroma_similarity,
            "rms_a": float(rms_a),
            "rms_b": float(rms_b),
        }


def p1_candidates() -> list[tuple[int, int, int]]:
    return [
        (start, start + length, length)
        for start in P1_STARTS
        for length in P1_LENGTHS
        if start + length <= 80
    ]


def p2_candidates() -> list[tuple[int, int, int]]:
    return [
        (start, end, end - start)
        for start in P2_STARTS
        for end in P2_ENDS
        if end > start and (end - start) % 4 == 0
    ]


def p3_candidates() -> list[tuple[int, int, int]]:
    return [
        (start, end, end - start)
        for start in P3_STARTS
        for end in P3_ENDS
        if end > start and (end - start) % 4 == 0
    ]


def choose(
    name: str, candidates: list[tuple[int, int, int]], scorer: SeamScorer
) -> tuple[tuple[int, int, int], list[dict[str, object]]]:
    rows: list[dict[str, object]] = []
    for start, end, length in candidates:
        details = scorer.score(start, end)
        rows.append(
            {
                "name": name,
                "start": start,
                "end": end,
                "length": length,
                **details,
            }
        )

    ranked = sorted(
        rows, key=lambda row: (-float(row["score"]), row["start"], row["end"])
    )
    winner = ranked[0]

    print(f"\n[{name}] 接缝候选（按分数从高到低）")
    print("  start  end  len_beats      score     chroma      rms_a      rms_b")
    for row in ranked:
        marker = "  <== 选中" if row is winner else ""
        print(
            f"  {row['start']:5d}  {row['end']:4d}  {row['length']:9d}"
            f"  {row['score']: .6f}  {row['chroma']: .6f}"
            f"  {row['rms_a']: .6f}  {row['rms_b']: .6f}{marker}"
        )

    return (
        int(winner["start"]),
        int(winner["end"]),
        int(winner["length"]),
    ), rows


def crossfade_loop(
    audio: np.ndarray, start_sample: int, end_sample: int, name: str
) -> np.ndarray:
    """Cut a loop and splice its tail into the pre-start audio."""
    segment = audio[start_sample:end_sample].copy()
    if len(segment) <= LOOP_XFADE:
        raise ValueError(f"{name} is too short for a {LOOP_XFADE}-sample crossfade")
    if start_sample < LOOP_XFADE:
        raise ValueError(f"{name} starts too early for a loop crossfade")

    weights = np.linspace(0.0, 1.0, LOOP_XFADE, dtype=np.float64)[:, None]
    tail = audio[end_sample - LOOP_XFADE : end_sample]
    pre_start = audio[start_sample - LOOP_XFADE : start_sample]
    segment[-LOOP_XFADE:] = tail * (1.0 - weights) + pre_start * weights
    return segment


def write_wav(path: Path, samples: np.ndarray) -> tuple[int, float]:
    """Write PCM16, clipping only the unrepresentable float overs."""
    clipped = int(np.count_nonzero((samples < -1.0) | (samples > 1.0)))
    peak = float(np.max(np.abs(samples)))
    sf.write(path, np.clip(samples, -1.0, 1.0), SR, subtype="PCM_16")
    return clipped, peak


def plot_seam(name: str, segment: np.ndarray, start: int, end: int, score: float) -> Path:
    half = int(round(0.5 * SR))
    joined = np.concatenate((segment[-half:, 0], segment[:half, 0]))
    times = np.arange(-half, half, dtype=np.float64) / SR

    frame = int(round(0.010 * SR))
    frame_count = len(joined) // frame
    rms = np.sqrt(
        np.mean(
            joined[: frame_count * frame].reshape(frame_count, frame) ** 2,
            axis=1,
        )
    )
    rms_times = (np.arange(frame_count) + 0.5) * 0.010 - 0.5

    fig, (wave_ax, rms_ax) = plt.subplots(2, 1, figsize=(16, 5), dpi=100)
    wave_ax.plot(times, joined, color="#2c6fbb", linewidth=0.7)
    wave_ax.axvline(0.0, color="red", linewidth=1.2)
    wave_ax.set_xlim(-0.5, 0.5)
    wave_ax.set_ylabel("left channel")
    wave_ax.set_title(
        f"{name} loop seam: beat {start} -> {end}, score {score:.6f}",
        fontsize=11,
    )
    wave_ax.grid(alpha=0.25)

    rms_ax.plot(rms_times, rms, color="#c85a17", linewidth=1.0, marker=".", ms=2.5)
    rms_ax.axvline(0.0, color="red", linewidth=1.2)
    rms_ax.set_xlim(-0.5, 0.5)
    rms_ax.set_xlabel("time relative to seam (s)")
    rms_ax.set_ylabel("RMS per 10 ms")
    rms_ax.grid(alpha=0.25)

    fig.tight_layout()
    path = PLOT_DIR / f"seam_{name}.png"
    fig.savefig(path, dpi=100)
    plt.close(fig)
    return path


def main() -> None:
    warnings.filterwarnings(
        "ignore", message="n_fft=1024 is too large for input signal.*"
    )
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    PLOT_DIR.mkdir(parents=True, exist_ok=True)

    audio = decode_audio()
    source_peak = float(np.max(np.abs(audio)))
    print(
        f"解码: {len(audio)} 帧 / {len(audio) / SR:.3f} s, "
        f"源峰值 {source_peak:.6f}"
    )

    # A constant gain cancels in both the chroma cosine and the RMS ratio.
    # Score the reference decode first so sections.json stays byte-stable,
    # then attenuate the entire array before any section is cut.
    scorer = SeamScorer(audio)
    p1, p1_rows = choose("p1", p1_candidates(), scorer)
    p2, p2_rows = choose("p2", p2_candidates(), scorer)
    p3, p3_rows = choose("p3", p3_candidates(), scorer)

    choices = {"p1": p1, "p2": p2, "p3": p3}
    scores = {
        name: float(
            next(row["score"] for row in rows if row["start"] == choices[name][0]
                 and row["end"] == choices[name][1])
        )
        for name, rows in (("p1", p1_rows), ("p2", p2_rows), ("p3", p3_rows))
    }

    audio *= GAIN
    print(
        f"GAIN {GAIN:.2f}: 全曲峰值 {source_peak:.6f} -> "
        f"{np.max(np.abs(audio)):.6f}"
    )

    # Order follows the music's section table, not chronological beat order:
    # p3 deliberately overlaps the p1/p2 ranges in the source.
    section_specs: list[tuple[str, int, int, bool]] = [
        ("intro", 0, 16, False),
        ("p1", p1[0], p1[1], True),
        ("p2", p2[0], p2[1], True),
        ("p3", p3[0], p3[1], True),
        ("final", 204, 268, False),
        ("ending", 264, -1, False),
    ]

    sections: dict[str, dict[str, object]] = {}
    for name, start_beat, end_beat, is_loop in section_specs:
        start_sample = 0 if name == "intro" else beat_sample(start_beat)
        end_sample = len(audio) if end_beat == -1 else beat_sample(end_beat)

        if is_loop:
            segment = crossfade_loop(audio, start_sample, end_sample, name)
        else:
            segment = audio[start_sample:end_sample].copy()

        if name == "intro":
            fade_in = int(round(0.005 * SR))
            segment[:fade_in] *= np.linspace(
                0.0, 1.0, fade_in, endpoint=False
            )[:, None]
        elif name == "ending":
            fade_out = int(round(2.0 * SR))
            if fade_out > len(segment):
                raise ValueError("ending is shorter than the 2 second fade-out")
            segment[-fade_out:] *= np.linspace(1.0, 0.0, fade_out)[:, None]

        output_path = OUT_DIR / f"{name}.wav"
        clipped, peak = write_wav(output_path, segment)
        duration = len(segment) / SR

        actual_end_beat = (
            float(end_beat)
            if name != "ending"
            else start_beat + len(segment) / BEAT_SAMPLES
        )
        info: dict[str, object] = {
            "start_beat": start_beat,
            "end_beat": (
                int(actual_end_beat)
                if name != "ending"
                else round(actual_end_beat, 6)
            ),
            "start_sec": round(start_sample / SR, 6),
            "length_sec": round(duration, 6),
            "loop": is_loop,
            "first_beat_in_clip": T0 if name == "intro" else 0.0,
        }
        if is_loop:
            info["seam_score"] = round(scores[name], 6)
        sections[name] = info

        print(
            f"{name:6s}: {start_sample:8d}..{end_sample:<8d} "
            f"{duration:8.3f} s  峰值 {peak:.6f}  clipped {clipped}"
        )

        if is_loop:
            plot_path = plot_seam(
                name, segment, start_beat, end_beat, scores[name]
            )
            print(f"        接缝图: {plot_path.relative_to(ROOT)}")

    sections_path = OUT_DIR / "sections.json"
    with sections_path.open("w", encoding="utf-8") as handle:
        json.dump({"spb": SPB, "sections": sections}, handle, indent=2)
        handle.write("\n")
    print(f"\nsections: {sections_path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
