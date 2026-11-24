import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile


def invoke(*args):
    entry = Path(sys.argv[1])
    command = [sys.executable, str(entry)] if entry.suffix == ".py" else [str(entry)]
    completed = subprocess.run(command + list(map(str, args)), check=False, capture_output=True)
    if completed.returncode:
        raise AssertionError((completed.returncode, completed.stdout.decode("utf-8", "replace"),
                              completed.stderr.decode("utf-8", "replace")))
    return json.loads(completed.stdout)


def main(folder):
    source = folder / "study.zip"
    edited = folder / "edited.zip"
    playable = folder / "playable.zip"
    original = Path(sys.argv[2])
    script = Path(sys.argv[3]).resolve()
    hold = {"type": "hold", "startTime": 1500, "judgeTime": 2600, "endTime": 4900,
            "position": [600, 400], "line": [[600, 400], [1000, 400], [800, 430]],
            "chartEditor": {"track": 1}}
    with zipfile.ZipFile(original) as template, zipfile.ZipFile(source, "w", zipfile.ZIP_DEFLATED) as output:
        for name in ("music.wav", "background.png", "black_cover.png"):
            output.writestr(name, template.read(name))
        output.writestr("chart.json", json.dumps({"basic": {"chartName": "CLI study", "difficulty": "HD",
                       "music": "music.wav", "bgPath": "background.png", "maskPath": "black_cover.png"},
                       "data": [hold]}))
    assert invoke("inspect", source, "--json")["note_count"] == 1
    assert invoke("validate", source, "--json")["error_count"] == 0
    assert invoke("references", "--id", "phrase-study", "--section", "paths")["total"] == 2
    reference = invoke("references", "--import", source)
    assert reference["title"] == "CLI study"
    details = invoke("references", "--id", reference["id"], "--section", "paths", "--from-ms", 3000)
    assert details["items"][0]["line"][1] == [1000, 400]
    result = invoke("run", source, "--script", script, "--output", edited)
    assert result["operation_count"] == 1 and result["result"]["factor"] == 1.3 and "Scaled" in result["log"]
    invoke("export", edited, "--output", playable)
    with zipfile.ZipFile(playable) as z:
        new_hold = json.loads(z.read("chart.json"))["data"][0]
        assert new_hold["startTime"] == hold["startTime"]
        assert new_hold["judgeTime"] == hold["judgeTime"] and new_hold["endTime"] == hold["endTime"]
        assert new_hold["line"][1] == [1120, 400]
    if os.environ.get("REVELATION_TEST_RENDER"):
        frame = folder / "frame.png"
        video = folder / "clip.mp4"
        invoke("render", edited, "--frame-ms", "3000", "--output", frame)
        invoke("render", edited, "--from-ms", "3000", "--to-ms", "3300", "--output", video)
        from PIL import Image
        png = Image.open(frame).convert("RGB")
        assert png.size == (1920, 1080) and png.getbbox()
        assert video.stat().st_size > 1000
    print("CLI pipeline: reference library, trusted script, chart geometry, timing, validate and export verified")


with tempfile.TemporaryDirectory(prefix="revelation-pipeline-", dir=os.environ.get("REVELATION_TEST_TMP")) as session:
    main(Path(session))
