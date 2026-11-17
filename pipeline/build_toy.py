"""Build the complete Bilibili Toy ZIP with Godot's single-thread release template."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
MUSIC = ("title", "intro", "p1", "p2", "p3", "final", "gameover", "ending")


def build():
    music = ROOT / "game/audio/music"
    sections = json.loads((music / "sections.json").read_text())["sections"]
    for track in MUSIC:
        if track not in sections or not (music / (track + ".wav")).is_file():
            raise ValueError(f"Missing soundtrack section: {track}")

    BUILD.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(dir=BUILD) as tmp:
        stage = Path(tmp)
        game = stage / "game"
        shutil.copytree(ROOT / "game", game, ignore=shutil.ignore_patterns(".godot", ".DS_Store"))
        shutil.copytree(ROOT / "web", stage / "web")
        # Preserve original dimensions, alpha, alignment and native export quality.
        for group in ("bust", "half", "full", "cutin"):
            for settings in (game / "art" / group).glob("*.png.import"):
                data = settings.read_text().replace("compress/mode=0", "compress/mode=1")
                settings.write_text(data)
        output = stage / "output"
        output.mkdir()
        godot = ["godot", "--headless", "--path", str(game), "--log-file", str(stage / "godot.log")]
        subprocess.run(godot + ["--import"], check=True)
        subprocess.run(godot + ["--export-release", "Bilibili Toy", str(output / "index.html")], check=True)
        for suffix in ("html", "js", "wasm", "pck"):
            if not (output / f"index.{suffix}").stat().st_size:
                raise ValueError(f"Empty index.{suffix}")
        if (output / "index.html").stat().st_size >= 1_000_000:
            raise ValueError("index.html exceeds Toy entry limit")
        archive = stage / "DeepSeekBattle-Toy.zip"
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as package:
            for item in sorted(output.iterdir()):
                package.write(item, item.name)
        with zipfile.ZipFile(archive) as package:
            if package.testzip():
                raise ValueError("ZIP integrity check failed")
        print(f"{archive.name}: {archive.stat().st_size:,} bytes")
        archive.replace(BUILD / archive.name)


if __name__ == "__main__":
    build()
