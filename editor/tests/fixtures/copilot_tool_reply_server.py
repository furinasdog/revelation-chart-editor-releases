import json
import pathlib
import sys
import time
import traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

def markup(name, attributes="", close=False, old=False):
    separator = "｜DSML｜" if old else "| | DSML | | "
    return "<" + ("/" if close else "") + separator + name + attributes + ">"

def calls(operations, old=False):
    wrapper = "function_calls" if old else "calls"
    reply = [markup(wrapper, old=old)]
    for name, arguments in operations:
        reply.append(markup("invoke", f' name="{name}"', old=old))
        for key, value in arguments.items():
            string = isinstance(value, str)
            parameter = markup("parameter", f' name="{key}" string="{str(string).lower()}"', old=old)
            reply.append(parameter + (value if string else json.dumps(value)) + markup("parameter", close=True, old=old))
        reply.append(markup("invoke", close=True, old=old))
    return "\n".join(reply) + "\n" + markup(wrapper, close=True, old=old)

class Mock(BaseHTTPRequestHandler):
    malformed_requests = 0

    def do_POST(self):
        try:
            data = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            assert data["stream"]
            messages = data["messages"]
            brief = json.loads(messages[1]["content"])["project"]["brief"]
            if brief.startswith("请为当前歌曲制作 EX"):
                assert "保留主歌" in brief and json.loads(messages[1]["content"])["project"]["difficulty"] == "EX"
                operations = [dict(name="add_notes", arguments=dict(notes=[dict(type="note",time_ms=4200,lane=0,x=850,y=480)]))] if len(messages)==2 else [dict(name="finish",arguments=dict(summary="已补谱"))]
                fragments = [{"content": json.dumps({"actions":operations},ensure_ascii=False)}]
            elif brief == "测试不完整调用":
                type(self).malformed_requests += 1
                attempt = type(self).malformed_requests
                assert len(messages) == min(attempt + 1, 4)
                if attempt <= 3:
                    fragments = [{"content": markup("calls") + markup("invoke", ' name="get_bpm"')}]
                else:
                    assert attempt == 4
                    fragments = [{"content": json.dumps({"actions": [
                        {"name": "reply", "arguments": {"message": "已恢复。"}}
                    ]}, ensure_ascii=False)}]
            elif len(messages) == 2:
                if brief == "测试 DSML 读取":
                    content = calls([("get_bpm", {}), ("get_project_context", {}), ("get_emotions", {}),
                                     ("get_audio_features", dict(from_ms=0, to_ms=16000, window_ms=4000, limit=64))])
                    fragments = [{"content": part} for part in [content[:1], content[1:7], content[7:17], content[17:]]]
                elif brief == "测试原生工具流":
                    fragments = [{"content": None, "tool_calls": [{"index": 0, "id": "mock-0", "type": "function",
                                   "function": {"name": "get_", "arguments": "{"}}]},
                                 {"tool_calls": [{"index": 0, "function": {"name": "bpm", "arguments": "}"}}]}]
                elif brief == "测试 DSML 写入审批":
                    fragments = [{"content": calls([("add_notes", {"notes": [dict(type="note", time_ms=4200,
                                   lane=0, x=850, y=480)]})], old=True)}]
                else:
                    raise AssertionError(brief)
            else:
                results = {item["name"]: item["result"] for item in json.loads(messages[-1]["content"])["tool_results"]}
                if brief == "测试 DSML 写入审批":
                    assert "拒绝" in results["add_notes"]["error"], results
                    answer = "已取消写入。"
                else:
                    assert results["get_bpm"]["items"][0]["bpm"] == 122, results
                    if brief == "测试 DSML 读取":
                        assert len(results) == 4, results
                        assert results["get_project_context"]["note_count"] == 0, results
                        assert results["get_emotions"]["items"][0]["tags"][0]["label"] == "calm", results
                        windows = results["get_audio_features"]["items"]
                        assert [(w["time_ms"], w["end_ms"]) for w in windows] == [
                            (0, 4000), (4000, 8000), (8000, 12000), (12000, 16000)
                        ], results
                    answer = "工具结果显示速度 122 BPM。"
                reply = json.dumps(dict(actions=[dict(name="reply", arguments=dict(message=answer))]), ensure_ascii=False)
                fragments = [{"content": reply[:31]}, {"content": reply[31:]}]
            chunks = [("data: " + json.dumps({"choices": [{"index": 0, "delta": delta}]}, ensure_ascii=False)
                       + "\n\n").encode() for delta in fragments]
            chunks.append(b'data: {"choices":[],"usage":{"total_tokens":40}}\n\ndata: [DONE]\n\n')
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Content-Length", str(sum(map(len, chunks))))
            self.end_headers()
            for chunk in chunks:
                self.wfile.write(chunk)
                self.wfile.flush()
                time.sleep(0.04)
        except Exception:
            with open(sys.argv[2], "a", encoding="utf-8") as logfile:
                traceback.print_exc(file=logfile)
            self.send_error(500)

    def log_message(self, *_):
        pass

with ThreadingHTTPServer(("127.0.0.1", 0), Mock) as server:
    pathlib.Path(sys.argv[1]).write_text(str(server.server_port))
    server.serve_forever()


