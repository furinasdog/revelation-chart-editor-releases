"""Console adapter for the same chart engine used by the Windows desktop app."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def parse():
    parser = argparse.ArgumentParser(prog="revelation")
    commands = parser.add_subparsers(dest="command", required=True)
    for action in ("inspect", "validate", "run", "export", "render", "pitch"):
        cmd = commands.add_parser(action)
        cmd.add_argument("input", type=Path)
        cmd.add_argument("--json", action="store_true", help="Emit JSON (the default)")
        if action in {"run", "export", "render"}:
            cmd.add_argument("--output", type=Path, required=True)
        if action == "run":
            cmd.add_argument("--script", type=Path, required=True)
            cmd.add_argument("--source", "--pitch-source", choices=("essentia", "rmvpe"))
        if action == "pitch":
            cmd.add_argument("--source", choices=("essentia", "rmvpe"), default="essentia")
        if action == "render":
            mode = cmd.add_mutually_exclusive_group(required=True)
            mode.add_argument("--frame-ms", type=int)
            mode.add_argument("--from-ms", type=int)
            cmd.add_argument("--to-ms", type=int)
    ref = commands.add_parser("references")
    source = ref.add_mutually_exclusive_group()
    source.add_argument("--import", type=Path)
    source.add_argument("--id")
    ref.add_argument("--query")
    ref.add_argument("--difficulty")
    ref.add_argument("--allow-images", action="store_true", help="Keep authorized reference images and allow preview render")
    ref.add_argument("--allow-audio", action="store_true", help="Allow local reads of authorized reference audio")
    ref.add_argument("--section", choices=("summary", "notes", "paths", "events", "masks", "keyframes"))
    for field in ("from-ms", "to-ms", "offset", "limit"):
        ref.add_argument("--" + field, type=int)
    args = vars(parser.parse_args())
    args.pop("json", None)
    request = {key: str(value.resolve()) if isinstance(value, Path) else value
               for key, value in args.items() if value is not None}
    if "output" in request:
        output = Path(request["output"])
        if output.exists() or not output.parent.is_dir():
            raise ValueError("Output must be a new file in an existing directory.")
    if args["command"] == "render":
        if "frame_ms" not in request and ("to_ms" not in request or request["to_ms"] <= request["from_ms"]):
            raise ValueError("--to-ms must be after --from-ms.")
    return request


def main():
    try:
        request = parse()
        app = Path(__file__).resolve().parent.parent
        editor = Path(os.environ.get("REVELATION_EDITOR", str(app / "更好的制谱器.exe")))
        if not editor.is_file():
            raise ValueError("Cannot find the editor executable. Set REVELATION_EDITOR for a source build.")
        command = [str(editor)]
        if os.environ.get("REVELATION_PROJECT"):
            command += ["--path", os.environ["REVELATION_PROJECT"]]
        if request["command"] == "render":
            command += ["--audio-driver", "Dummy", "--position", "-32000,-32000"]
        else:
            command += ["--headless"]
        with tempfile.TemporaryDirectory(prefix="revelation-cli-") as folder:
            job = Path(folder) / "request.json"
            response = Path(folder) / "response.json"
            job.write_text(json.dumps(request, ensure_ascii=False), encoding="utf-8")
            command += ["--", "--revelation-cli", str(job), str(response)]
            flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
            process = subprocess.run(command, cwd=editor.parent, stdout=sys.stderr.buffer,
                                     stderr=sys.stderr.buffer, creationflags=flags)
            if not response.exists():
                raise ValueError(f"Editor exited without a CLI result (exit {process.returncode}).")
            result = json.loads(response.read_text("utf-8"))
            code = process.returncode
    except (OSError, ValueError) as error:
        result, code = {"error": str(error)}, 2
    sys.stdout.buffer.write((json.dumps(result, ensure_ascii=False) + "\n").encode())
    return code


if __name__ == "__main__":
    sys.exit(main())
