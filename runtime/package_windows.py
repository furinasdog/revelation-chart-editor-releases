"""Package an exported editor and its matching local source tree for Windows."""

import argparse
import os
import re
import subprocess
import tempfile
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


ROOT = Path(__file__).resolve().parents[1]
APP = "更好的制谱器"
DOCS = ["README.md", "LICENSE", "THIRD_PARTY.md", "CONTRIBUTING.md", "功能与入口说明.md"]
COMPONENTS = ["revelation_rhythm.dll", "onnxruntime.dll", "revelation-essentia.exe",
              "revelation-madmom.exe", "revelation-music2emo.exe", "revelation-rmvpe.exe",
              "revelation-stems.exe"]


def add_tree(archive, folder, prefix):
    for path in sorted(folder.rglob("*")):
        if path.is_file() and "__pycache__" not in path.parts and path.suffix != ".pyc":
            archive.write(path, prefix / path.relative_to(folder))


def sources():
    paths = ["editor", "native", "runtime", "docs", "CMakeLists.txt", ".gitignore", *DOCS]
    if (ROOT / ".git").exists():
        data = subprocess.check_output(["git", "ls-files", "-co", "--exclude-standard", "-z", "--", *paths], cwd=ROOT)
        return sorted({ROOT / os.fsdecode(p) for p in data.split(b"\0") if p})
    files = []
    for name in paths:
        path = ROOT / name
        files.extend(path.rglob("*") if path.is_dir() else [path])
    return sorted(files)


def create(export, deps, output):
    version = re.search(r'^config/version="([\d.]+)"$', (ROOT / "editor/project.godot").read_text("utf-8"), re.M)[1]
    app = Path(APP)
    archives = [f"Revelation-Editor-v{version}-Windows-x64.zip", f"Revelation-Editor-v{version}-LocalSource.zip"]
    output.mkdir(parents=True, exist_ok=True)
    if any((output / name).exists() for name in archives):
        raise FileExistsError("Choose an output directory without existing archives for this version.")
    with tempfile.TemporaryDirectory(dir=output) as temp:
        work = Path(temp)
        with ZipFile(work / archives[0], "w", ZIP_DEFLATED, compresslevel=5) as z:
            for name, target in [("game.exe", APP + ".exe"), ("game.pck", APP + ".pck"), *[(c, c) for c in COMPONENTS]]:
                z.write(export / name, app / target)
            descriptor = export / "cuda-addon.signed.json"
            if descriptor.is_file():
                z.write(descriptor, app / descriptor.name)
            for name in ["msvcp140.dll", "msvcp140_1.dll", "vcruntime140.dll", "vcruntime140_1.dll"]:
                z.write(deps / name, app / name)
            for name in ["python.exe","python313.zip"]:
                if not (deps / "tools/python" / name).is_file():
                    raise FileNotFoundError(name)
            add_tree(z, deps / "tools/python", app / "tools/python")
            z.write(deps / "tools/ffmpeg.exe", app / "tools/ffmpeg.exe")
            z.write(deps / "models/rmvpe.onnx", app / "models/rmvpe.onnx")
            licenses = {p.name: p for base in [deps / "licenses", ROOT / "editor/licenses"] for p in base.iterdir() if p.is_file()}
            licenses.update({"LICENSE-GDSO-Godot.txt": export / "LICENSE-Godot.txt", "LICENSE-Grit.txt": export / "LICENSE-Grit.txt"})
            if (export / "COPYRIGHT-Godot.txt").is_file():
                licenses["COPYRIGHT-Godot.txt"] = export / "COPYRIGHT-Godot.txt"
            for name, path in sorted(licenses.items()):
                z.write(path, app / "licenses" / name)
            for name in ["cli.py", "rpy.py", "worker.py", "mcp_stdio.py"]:
                z.write(ROOT / "runtime" / name, app / "runtime" / name)
            z.write(ROOT / "runtime/revelation.cmd", app / "revelation.cmd")
            for name in DOCS:
                z.write(ROOT / name, app / name)
            z.write(ROOT / "更好的制谱器Hub/guides/editor.md", app / "新手教程.md")
            add_tree(z, ROOT / "docs/tutorial", app / "docs/tutorial")
            z.write(ROOT / "docs/上游1.10.1同步.md", app / "docs/上游1.10.1同步.md")
        with ZipFile(work / archives[1], "w", ZIP_DEFLATED, compresslevel=5) as z:
            for path in sources():
                name = path.relative_to(ROOT)
                if not path.is_file() or any(p in (".godot", ".autoconverted", "__pycache__") for p in name.parts):
                    continue
                if path.name in ("chart_agent.cfg","export_credentials.cfg",".env") or path.suffix in (".pdb",".pyc",".key"):
                    continue
                z.write(path, Path(f"Revelation-Editor-v{version}") / name)
        for name in archives:
            with ZipFile(work / name) as z:
                if z.testzip():
                    raise ValueError(f"Invalid ZIP: {name}")
        for name in archives:
            (work / name).rename(output / name)
            print(output / name)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for opt in ["export-dir", "dependencies", "output"]:
        parser.add_argument("--" + opt, type=Path, required=True)
    args = parser.parse_args()
    create(args.export_dir, args.dependencies, args.output)
