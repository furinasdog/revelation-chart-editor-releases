import json
import pathlib
import socket
import sys
import time
import traceback
from http.server import BaseHTTPRequestHandler, HTTPServer

def action(name, **arguments):
    return dict(name=name, arguments=arguments)

def note(time, lane, x):
    return dict(type="note", time_ms=time, lane=lane, x=x, y=480)

def sse(delta, reason=None):
    return ("data: " + json.dumps({"choices": [{"delta": delta, "finish_reason": reason}]}) + "\n\n").encode()

def content(actions):
    return json.dumps({"actions": actions})

attempts = 0
original_request = None

class Mock(BaseHTTPRequestHandler):
    def do_POST(self):
        global attempts, original_request
        try:
            body = self.rfile.read(int(self.headers["Content-Length"]))
            data = json.loads(body)
            assert data["model"] == "mock-retry" and data["stream"]
            assert data["stream_options"]["include_usage"]
            messages = data["messages"]
            if len(messages) == 2:
                context = json.loads(messages[1]["content"])["project"]
                overview = context["audio_loudness_overview"]
                assert len(overview) == 4 and overview[0][:2] == [0, 4000] and overview[-1][:2] == [12000, 16000]
                actions = [action("add_notes", notes=[note(2000, 0, 800)])]
                self.respond("text/event-stream", [b": keep-alive\n\n", sse({"content": content(actions)}),
                    sse({}, "stop"), b'data: {"choices":[],"usage":{"total_tokens":50}}\n\ndata: [DONE]\n\n'])
                return
            assert len(messages) == 4, messages[-1]
            results = json.loads(messages[-1]["content"])["tool_results"]
            assert set(results[0]["result"]) >= {"ids"}, results
            attempts += 1
            if attempts == 1:
                original_request = body
                self.connection.shutdown(socket.SHUT_WR)
                return
            assert body == original_request, "Retry must use exactly the failed request"
            if attempts == 2:
                self.respond("text/event-stream", [sse({"content": content([action("finish")])})])
                return
            if attempts == 3:
                self.respond("text/event-stream", [b": keepalive\n\n", b": trace tr_smoke\n\n",
                    sse({"content": content([action("finish")])}),
                    b'event: error\ndata: {"error":{"code":"upstream_interrupted","message":"broken","type":"api_error"}}\n\n'])
                return
            assert attempts == 4
            reply = content([action("add_notes", notes=[note(4000, 1, 1050)]), action("finish", summary="重试成功")])
            reasoning = sse({"reasoning_content": "x" * 440_000})
            self.respond("text/event-stream", [reasoning] * 5 + [sse({"content": reply[:20]}), b": keep-alive\n\n",
                sse({"content": reply[20:]}), sse({}, "stop"), b'data: {"choices":[],"usage":{"total_tokens":70}}\n\n'])
        except Exception:
            with open(sys.argv[2], "a", encoding="utf-8") as logfile:
                traceback.print_exc(file=logfile)
            self.send_error(500)

    def respond(self, kind, chunks):
        self.send_response(200)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(sum(map(len, chunks))))
        self.end_headers()
        for chunk in chunks:
            self.wfile.write(chunk)
            self.wfile.flush()
            time.sleep(0.04)

    def log_message(self, *_):
        pass

with HTTPServer(("127.0.0.1", 0), Mock) as mock:
    pathlib.Path(sys.argv[1]).write_text(str(mock.server_port))
    mock.serve_forever()
