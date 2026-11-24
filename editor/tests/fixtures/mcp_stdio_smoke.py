import http.client
import json
from pathlib import Path
import subprocess
import sys
import tomllib
from urllib.parse import urlsplit


def run(folder, client):
    codex = tomllib.loads((folder / ".codex/config.toml").read_text("utf-8"))["mcp_servers"]["revelation"]
    claude = json.loads((folder / ".mcp.json").read_text("utf-8"))["mcpServers"]["revelation"]
    assert claude["type"] == "stdio" and codex["tool_timeout_sec"] == 240
    assert all(codex[key] == claude[key] for key in ("command", "args"))
    private = Path(codex["args"][-1])
    connection = json.loads(private.read_text("utf-8"))
    assert not private.resolve().is_relative_to(folder.resolve())
    assert connection["token"] not in json.dumps(codex) + json.dumps(claude)
    legacy = folder / "connection.json"
    if legacy.exists():
        assert json.loads(legacy.read_text("utf-8")) == {"config": codex["args"][-1]}
    with subprocess.Popen([codex["command"], *codex["args"]], stdin=subprocess.PIPE,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          creationflags=subprocess.CREATE_NO_WINDOW) as process:
        def call(request_id, method, params):
            body = {"jsonrpc": "2.0", "id": request_id, "method": method, "params": params}
            process.stdin.write((json.dumps(body) + "\n").encode())
            process.stdin.flush()
            message = json.loads(process.stdout.readline())
            assert message["id"] == request_id
            return message["result"]

        try:
            result = call(1, "initialize", {"protocolVersion": "2025-11-25", "capabilities": {},
                                           "clientInfo": {"name": client, "version": "1"}})
            assert "scale_hold_paths" in result["instructions"]
            assert call(2, "prompts/list", {})["prompts"][0]["name"] == "revelation-charting"
            names = {tool["name"] for tool in call(3, "tools/list", {})["tools"]}
            assert {"import_audio", "run_rpy", "get_editing_guide"} <= names
            # Open four clients that leave no drafts, forcing the oldest (this bridge) out of the pool.
            url = urlsplit(connection["url"])
            headers = {"Authorization": "Bearer " + connection["token"], "Content-Type": "application/json"}
            others = []
            for number in range(4):
                request = http.client.HTTPConnection("127.0.0.1", url.port, timeout=3)
                message = {"jsonrpc": "2.0", "id": number, "method": "initialize", "params": {
                    "protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": client}}}
                request.request("POST", url.path, json.dumps(message), headers)
                response = request.getresponse()
                assert response.status == 200
                others.append(response.getheader("Mcp-Session-Id"))
                response.read()
                request.close()
            assert call(4, "ping", {}) == {}, "Recover a reclaimed session in the same stdio process"
            for session in others:
                request = http.client.HTTPConnection("127.0.0.1", url.port, timeout=3)
                request.request("DELETE", url.path, headers={**headers, "Mcp-Session-Id": session})
                request.getresponse().read()
                request.close()
        finally:
            process.stdin.close()
            if process.wait(timeout=3):
                raise RuntimeError(process.stderr.read().decode("utf-8", "replace"))


if __name__ == "__main__":
    report = Path(sys.argv[3])
    try:
        run(Path(sys.argv[1]), sys.argv[2])
    except Exception as error:
        report.write_text(repr(error), "utf-8")
        raise
    report.write_text("OK", "utf-8")
