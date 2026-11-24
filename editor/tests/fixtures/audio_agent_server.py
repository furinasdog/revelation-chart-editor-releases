"""Local Chat Completions fixture for the audio tools."""
import base64
import json
import os
import pathlib
import sys
import traceback
from http.server import BaseHTTPRequestHandler, HTTPServer


def action(name, **arguments):
    return {"name": name, "arguments": arguments}


def check_figure(image, result, kind, start, end):
    url = image["image_url"]["url"]
    assert image["type"] == "image_url" and url.startswith("data:image/jpeg;base64,")
    payload = base64.b64decode(url.split(",", 1)[1], validate=True)
    assert payload.startswith(b"\xff\xd8") and payload.endswith(b"\xff\xd9")
    assert 500 < len(payload) <= 72000
    assert result["kind"] == kind and result["from_ms"] == start and result["to_ms"] == end
    assert result["image_size"][0] > 300
    assert "_preview_image" not in result


def shape_actions(messages):
    assert "create_shape_asset" in messages[0]["content"]
    if len(messages) == 2:
        return [action("create_shape_asset", width=180, height=128,
                       shapes=[{"kind": "square", "stroke": "#81A9FF", "stroke_width": 0.02}])]
    content = messages[-1]["content"]
    tools = json.loads(content[0]["text"] if isinstance(content, list) else content)["tool_results"]
    if len(messages) == 4:
        return [action("view_shape_asset", shape_id=tools[0]["result"]["shape_id"])]
    if len(messages) == 6:
        url = content[1]["image_url"]["url"]
        assert url.startswith("data:image/png;base64,")
        assert base64.b64decode(url.split(",", 1)[1], validate=True).startswith(b"\x89PNG\r\n\x1a\n")
        shape_id = tools[0]["result"]["shape_id"]
        return [action("add_animation_layer", source="shape", shape_id=shape_id, keyframes=[
            {"time_ms": 0, "opacity": 0, "x": 720},
            {"time_ms": 1000, "opacity": 0.42, "x": 940},
            {"time_ms": 2700, "opacity": 0, "x": 1110}
        ]), action("set_chart_metadata", fields={"name": "图形测试"})]
    assert len(messages) == 8 and all("error" not in item["result"] for item in tools)
    return [action("finish", summary="已加入图形动画。")]


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            document = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            messages = document["messages"]
            context = json.loads(messages[1]["content"])["project"]
            if context["brief"] == "把第25拍，12秒的普通键向右移动。":
                assert context["editor"]["playhead"]["label"] == "第 25 拍 · 0:12.0", context["editor"]
                if len(messages) == 2:
                    self.respond([action("locate_notes", ruler_beat=25, seconds=12),
                                  action("get_audio_features", from_ms=11500, to_ms=12499, window_ms=500)])
                    return
                results = json.loads(messages[-1]["content"])["tool_results"]
                if len(messages) == 4:
                    found, features = [entry["result"] for entry in results]
                    assert found["total"] == 2
                    note = next(n for n in found["items"] if n["match"] == "judgement")
                    assert any(n["match"] == "hold_span" for n in found["items"])
                    assert note["time_ms"] == 12000 and note["label"] == found["location"]["label"]
                    assert any(12000 in w.get("accents_ms", []) for w in features["items"])
                    assert all("rms_dbfs" in w and len(w["band_rms"]) == 6 for w in features["items"])
                    self.respond([action("set_positions", notes=[dict(id=note["id"], x=1100, y=500)])])
                else:
                    assert "error" not in results[0]["result"]
                    self.respond([action("finish", summary="已移动第 25 拍 · 0:12.0 的普通键。")])
                return
            if context["brief"] == "导入指定的另一段音频并检查。":
                prompt = messages[0]["content"]
                assert "内置 Co-pilot 使用直接工具" in prompt and "斜上方" in prompt and "scale_hold_paths" in prompt
                assert "run_rpy" not in prompt
                if len(messages) == 2:
                    self.respond([action("import_audio", path=os.environ["REVELATION_TEST_IMPORT_PATH"])])
                    return
                tools = json.loads(messages[-1]["content"])["tool_results"]
                if len(messages) == 4:
                    assert tools[0]["result"]["imported"]
                    self.respond([action("get_audio_info"), action("list_notes")])
                    return
                assert tools[0]["result"]["filename"].startswith("tempo-change-")
                assert tools[1]["result"]["total"] == 1
                self.respond([action("reply", message="音频已导入并校验。")])
                return
            if context["brief"] == "把这两个音符向右移动。":
                if len(messages) == 2:
                    self.respond_message({"tool_calls": [{"function": {"name": "set_positions", "arguments": "{"}}]})
                    return
                if len(messages) == 3:
                    self.respond_message({"content": '{"actions":'})
                    return
                if len(messages) == 4:
                    self.respond([action("list_notes"), action("run_rpy", source="print(1)")])
                    return
                tools = json.loads(messages[-1]["content"])["tool_results"]
                if len(messages) == 6:
                    notes = tools[0]["result"]["items"]
                    assert len(notes) == 2 and "直接工具" in tools[1]["result"]["error"]
                    self.respond([action("set_positions", notes=[{"id": n["id"], "x": n["x"] + 50, "y": n["y"]} for n in notes])])
                    return
                assert len(messages) == 8 and "error" not in tools[0]["result"]
                self.respond([action("finish", summary="两个音符已向右移动。")])
                return
            overview = context["audio_loudness_overview"]
            assert overview and overview[0][:2] == [2500, 5000] and -120 <= overview[0][2] <= 0
            assert "get_audio_features" in messages[0]["content"] and "响度" in messages[0]["content"]
            if context["brief"] == "绘制方形动画":
                assert context["requires_visible_animation"]
                self.respond(shape_actions(messages))
                return
            share = context["brief"] == "带图检查选段"
            assert context["selected_audio_span_ms"] == [2500, 5000]
            assert context["audio_figure_available"] == share
            if len(messages) == 2:
                actions = [action("get_audio_loudness"), action("view_audio_figure", kind="waveform")]
            elif len(messages) == 4:
                content = messages[-1]["content"]
                tools = json.loads(content[0]["text"] if share else content)["tool_results"]
                loudness = tools[0]["result"]
                assert loudness["unit"] == "dBFS" and loudness["time_ms"] == 2500 and loudness["end_ms"] == 5000
                assert len(loudness["items"]) == 3 and -100 < loudness["rms_dbfs"] <= 0
                if share:
                    check_figure(content[1], tools[1]["result"], "waveform", 2500, 5000)
                    actions = [action("view_audio_figure", kind="spectrum", from_ms=4500, to_ms=7000)]
                else:
                    assert "error" in tools[1]["result"]
                    actions = [action("reply", message="选段响度已检查。")]
            else:
                assert share and len(messages) == 6
                content = messages[-1]["content"]
                tools = json.loads(content[0]["text"])["tool_results"]
                check_figure(content[1], tools[0]["result"], "spectrum", 4500, 7000)
                actions = [action("reply", message="选段波形和频谱已检查。")]
            self.respond(actions)
        except Exception:
            with open(sys.argv[2], "a", encoding="utf-8") as log:
                traceback.print_exc(file=log)
            self.send_error(500)

    def respond(self, actions):
        self.respond_message({"content": json.dumps({"actions": actions})})

    def respond_message(self, message):
        body = json.dumps({"choices": [{"message": message}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


with HTTPServer(("127.0.0.1", 0), Handler) as server:
    pathlib.Path(sys.argv[1]).write_text(str(server.server_port))
    server.serve_forever()
