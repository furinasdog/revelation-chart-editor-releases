"""Stage verified third-party runtime files into a Windows export directory."""

import argparse
import hashlib
import shutil
import urllib.request
from pathlib import Path
from zipfile import ZipFile

PYTHON = (
    "python-3.13.17-embed-amd64.zip",
    "https://www.python.org/ftp/python/3.13.17/python-3.13.17-embed-amd64.zip",
    "9e35319bffedab8b36ad44d8f377cb4f1733bcec257a0b6d04d94f01486ddb38",
)
WHEELS = (
    ("numpy-2.4.4-cp313-cp313-win_amd64.whl",
     "https://files.pythonhosted.org/packages/57/fb/48649b4971cde70d817cf97a2a2fdc0b4d8308569f1dd2f2611959d2e0cf/numpy-2.4.4-cp313-cp313-win_amd64.whl",
     "5c70f1cc1c4efbe316a572e2d8b9b9cc44e89b95f79ca3331553fbb63716e2bf"),
    ("pillow-12.2.0-cp313-cp313-win_amd64.whl",
     "https://files.pythonhosted.org/packages/3f/82/8a3739a5e470b3c6cbb1d21d315800d8e16bff503d1f16b03a4ec3212786/pillow-12.2.0-cp313-cp313-win_amd64.whl",
     "390ede346628ccc626e5730107cde16c42d3836b89662a115a921f28440e6a3b"),
)
MODEL_BASE = "https://huggingface.co/Scicom-intl/rmvpe-onnx/resolve/df25b8a1296f183d0bd8ddabeb616f0dcbf26d54"
MODEL_FILES = (
    ("rmvpe.onnx", "rmvpe.onnx", "648e1a7bf3795f39498841d35c2a100ab4997c045e7d5ed555b02aef0f3dfa32"),
    ("RMVPE-MIT.txt", "LICENSE", "bec61ed1eb9a3748644ddbc50303aa6978e14eeaba46822e59a006c722b52585"),
    ("RMVPE-Apache-2.0.txt", "LICENSE-RMVPE-original", "c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4"),
)


def verified(cache, name, url, sha256):
    path = cache / name
    if not path.exists():
        temporary = path.with_suffix(path.suffix + ".part")
        try:
            with urllib.request.urlopen(url, timeout=60) as response, temporary.open("wb") as output:
                shutil.copyfileobj(response, output, 1024 * 1024)
            verify(temporary, sha256)
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)
    verify(path, sha256)
    return path


def verify(path, expected):
    with path.open("rb") as payload:
        actual = hashlib.file_digest(payload, "sha256").hexdigest()
    if actual != expected:
        raise ValueError(f"SHA-256 mismatch: {path}")


def stage_rmvpe(target, cache, model_only=False):
    for destination, filename, sha in MODEL_FILES:
        model = filename.endswith(".onnx")
        if model_only and not model:
            continue
        asset = verified(cache, filename, f"{MODEL_BASE}/{filename}", sha)
        folder = target / ("models" if model else "licenses")
        folder.mkdir(parents=True, exist_ok=True)
        shutil.copy2(asset, folder / destination)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("target", type=Path)
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--rmvpe-engine", type=Path)
    parser.add_argument("--rmvpe-model-only", action="store_true",
                        help="Stage only the verified RMVPE weight below TARGET/models for source runs")
    parser.add_argument("--stems-engine", type=Path)
    args = parser.parse_args()
    args.cache.mkdir(parents=True, exist_ok=True)
    if args.rmvpe_model_only:
        stage_rmvpe(args.target, args.cache, model_only=True)
        return
    python = args.target / "tools" / "python"
    site = python / "Lib" / "site-packages"
    site.mkdir(parents=True, exist_ok=True)
    with ZipFile(verified(args.cache, *PYTHON)) as archive:
        archive.extractall(python)
    (python / "python313._pth").write_text("python313.zip\n.\nLib/site-packages\n", encoding="ascii")
    for wheel in WHEELS:
        with ZipFile(verified(args.cache, *wheel)) as archive:
            archive.extractall(site)
    runtime = args.target / "runtime"
    runtime.mkdir(parents=True, exist_ok=True)
    source = Path(__file__).resolve().parent
    for filename in ("rpy.py", "worker.py", "cli.py", "mcp_stdio.py"):
        shutil.copy2(source / filename, runtime)
    shutil.copy2(source / "revelation.cmd", args.target)
    if args.stems_engine:
        shutil.copy2(args.stems_engine, args.target / "revelation-stems.exe")
    if args.rmvpe_engine:
        shutil.copy2(args.rmvpe_engine, args.target / "revelation-rmvpe.exe")
        stage_rmvpe(args.target, args.cache)


if __name__ == "__main__":
    main()
