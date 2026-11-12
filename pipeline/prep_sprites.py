#!/usr/bin/env python3
"""Scale source sprites by a fixed per-directory ratio and write a manifest.

Run from the repository root:
    python3 -I pipeline/prep_sprites.py
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC_ROOT = ROOT / "assets" / "sprites"
OUT_ROOT = ROOT / "game" / "art"

# directory -> (scale ratio, mode)
SPECS = {
    "full": (2.0 / 3.0, "RGBA"),
    "half": (0.75, "RGBA"),
    "bust": (0.75, "RGBA"),
    "cutin": (0.75, "RGBA"),
}


def scaled_size(width: int, height: int, ratio: float) -> tuple[int, int]:
    """Round each source dimension half-up while preserving aspect ratio."""
    return int(width * ratio + 0.5), int(height * ratio + 0.5)


def resize_premultiplied(src: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Resize RGBA while RGB is premultiplied, then restore straight alpha.

    Pillow's LANCZOS filter is used for both the RGB and alpha channels.  Doing
    the resize in premultiplied space prevents the colour of fully transparent
    pixels from bleeding into the visible edge.
    """
    rgba = src.convert("RGBA")
    values = np.asarray(rgba, dtype=np.float32) / 255.0
    values[..., :3] *= values[..., 3:4]

    premultiplied = Image.fromarray(
        np.clip(np.rint(values * 255.0), 0, 255).astype(np.uint8), "RGBA"
    )
    resized = premultiplied.resize(size, Image.LANCZOS)
    out = np.asarray(resized, dtype=np.float32) / 255.0

    alpha = out[..., 3:4]
    rgb = np.divide(
        out[..., :3],
        alpha,
        out=np.zeros_like(out[..., :3]),
        where=alpha > 0.0,
    )
    rgb = np.clip(rgb, 0.0, 1.0)
    combined = np.concatenate((rgb, alpha), axis=2)
    return Image.fromarray(
        np.clip(np.rint(combined * 255.0), 0, 255).astype(np.uint8), "RGBA"
    )


def resize_rgb(src: Image.Image, size: tuple[int, int]) -> Image.Image:
    return src.convert("RGB").resize(size, Image.LANCZOS)


def alpha_bbox(image: Image.Image) -> list[int]:
    """Return an exclusive (x0, y0, x1, y1) bbox for alpha > 8."""
    if image.mode != "RGBA":
        width, height = image.size
        return [0, 0, width, height]

    mask = np.asarray(image.getchannel("A")) > 8
    if not mask.any():
        return [0, 0, 0, 0]
    ys, xs = np.nonzero(mask)
    return [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1]


def remove_stale_outputs(out_dir: Path, expected_names: set[str]) -> list[str]:
    """Delete generated PNG/import pairs whose source sprite is gone."""
    removed: list[str] = []
    if not out_dir.exists():
        return removed

    for old in sorted(out_dir.glob("*.png")):
        if old.name not in expected_names:
            old.unlink()
            removed.append(old.name)

    for old in sorted(out_dir.glob("*.png.import")):
        source_name = old.name[: -len(".import")]
        if source_name not in expected_names:
            old.unlink()
            removed.append(old.name)
    return removed


def main() -> None:
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    manifest: dict[str, dict[str, object]] = {}

    for directory, (ratio, default_mode) in SPECS.items():
        src_dir = SRC_ROOT / directory
        out_dir = OUT_ROOT / directory
        out_dir.mkdir(parents=True, exist_ok=True)

        sources = sorted(src_dir.glob("*.png"))
        expected_names = {path.name for path in sources}
        removed = remove_stale_outputs(out_dir, expected_names)

        for src_path in sources:
            with Image.open(src_path) as source:
                size = scaled_size(source.width, source.height, ratio)
                # The cut-in eye assets are opaque close-ups: Godot only needs
                # RGB for them.  All other sprites carry an alpha channel.
                if directory == "cutin" and src_path.stem.startswith("eyes"):
                    result = resize_rgb(source, size)
                elif default_mode == "RGBA":
                    result = resize_premultiplied(source, size)
                else:
                    result = resize_rgb(source, size)

                out_path = out_dir / src_path.name
                result.save(out_path, format="PNG", optimize=True)

            key = f"{directory}/{src_path.stem}"
            manifest[key] = {
                "size": [int(result.width), int(result.height)],
                "bbox": alpha_bbox(result),
            }

        total_bytes = sum(path.stat().st_size for path in out_dir.glob("*.png"))
        print(
            f"{directory:5s}: {len(sources):2d} 张, "
            f"{total_bytes / 1024 / 1024:.3f} MiB"
        )
        if removed:
            print(f"       清理旧输出: {', '.join(removed)}")

    manifest_path = OUT_ROOT / "manifest.json"
    with manifest_path.open("w", encoding="utf-8") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")

    total_files = sum(len(list((OUT_ROOT / d).glob("*.png"))) for d in SPECS)
    total_bytes = sum(
        path.stat().st_size for d in SPECS for path in (OUT_ROOT / d).glob("*.png")
    )
    print(
        f"总计  : {total_files} 张, {total_bytes} 字节 "
        f"({total_bytes / 1024 / 1024:.3f} MiB)"
    )
    print(f"manifest: {manifest_path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
