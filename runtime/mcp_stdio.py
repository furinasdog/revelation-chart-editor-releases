"""Forward local MCP stdio to the running Revelation editor over loopback."""

from concurrent.futures import ThreadPoolExecutor
import http.client
import json
from pathlib import Path
import re
import sys
from threading import Lock
from urllib.parse import urlsplit


MAX_REQUEST = 384_000
MAX_RESULT = 4 * 1024 * 1024


class Relay:
    def __init__(self, config):
        url = urlsplit(config["url"])
        if (url.scheme != "http" or url.hostname != "127.0.0.1" or not url.port
                or url.username is not None or url.query or url.fragment
                or not re.fullmatch(r"/(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+", url.path)):
            raise ValueError("Expected a Revelation loopback endpoint")
        token = config["token"]
        if not re.fullmatch(r"[0-9a-f]{64}", token):
            raise ValueError("Invalid Revelation connection token")
        self.port = url.port
        self.path = url.path
        self.token = token
        self.session = None
        self.initialize_body = None
        self.session_lock = Lock()
        self.output_lock = Lock()

    def request(self, method, body=None, timeout=245, session=None):
        headers = {"Authorization": "Bearer " + self.token,
                   "Accept": "application/json, text/event-stream"}
        if body is not None:
            headers["Content-Type"] = "application/json"
        if session:
            headers["Mcp-Session-Id"], headers["MCP-Protocol-Version"] = session
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=timeout)
        try:
            connection.request(method, self.path, body=body, headers=headers)
            response = connection.getresponse()
            payload = response.read(MAX_RESULT + 1)
            if len(payload) > MAX_RESULT:
                raise ValueError("Revelation response exceeded 4 MiB")
            return response.status, response.getheader("Mcp-Session-Id"), payload
        finally:
            connection.close()

    def send(self, message):
        data = json.dumps(message, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        with self.output_lock:
            sys.stdout.buffer.write(data + b"\n")
            sys.stdout.buffer.flush()

    def forward(self, message):
        method = message.get("method")
        has_request_id = "id" in message and isinstance(method, str)
        try:
            body = json.dumps(message, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            if method == "initialize":
                with self.session_lock:
                    self.initialize_body = body
                    status, _, payload = self.initialize()
            else:
                previous = self.session
                status, _, payload = self.request("POST", body, session=previous)
                # HTTP 404 with a session is rejected before a tool runs. Only retry after that response.
                if status == 404 and previous and self.reconnect(previous):
                    status, _, payload = self.request("POST", body, session=self.session)
            if payload:
                reply = json.loads(payload)
                self.send(reply)
            elif status not in (200, 202, 204):
                raise ValueError(f"Revelation rejected the request (HTTP {status})")
        except (OSError, ValueError, http.client.HTTPException) as error:
            if has_request_id:
                self.send({"jsonrpc": "2.0", "id": message["id"], "error": {
                    "code": -32000, "message": f"Revelation MCP: {error}. Check the editor's MCP server."}})

    def initialize(self):
        result = self.request("POST", self.initialize_body)
        status, identifier, payload = result
        if status == 200 and identifier:
            version = json.loads(payload)["result"]["protocolVersion"]
            self.session = (identifier, version)
        return result

    def reconnect(self, previous):
        with self.session_lock:
            if self.session == previous:
                status, identifier, _ = self.initialize()
                if status != 200 or not identifier:
                    return False
                self.request("POST", b'{"jsonrpc":"2.0","method":"notifications/initialized"}', session=self.session)
            return True

    def close(self):
        if self.session:
            try:
                self.request("DELETE", timeout=2, session=self.session)
            except (OSError, ValueError, http.client.HTTPException):
                pass


def load_connection(path):
    with path.open(encoding="utf-8") as file:
        config = json.load(file)
    private = path.parent.parent / "mcp_private" / "connection.json"
    if path.parent.name == "mcp_connection" and path.name == "connection.json" and "config" in config:
        if Path(config["config"]).resolve() != private.resolve():
            raise ValueError("Invalid migrated Revelation connection")
        with private.open(encoding="utf-8") as file:
            return json.load(file)
    return config


def main():
    relay = Relay(load_connection(Path(sys.argv[1])))
    with ThreadPoolExecutor(max_workers=8) as tasks:
        try:
            while data := sys.stdin.buffer.readline(MAX_REQUEST + 1):
                if len(data) > MAX_REQUEST:
                    raise ValueError("MCP request exceeded the supported size")
                try:
                    message = json.loads(data)
                except ValueError:
                    relay.send({"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "Invalid JSON"}})
                    continue
                if not isinstance(message, dict):
                    relay.send({"jsonrpc": "2.0", "id": None, "error": {"code": -32600, "message": "Expected a JSON object"}})
                elif message.get("method") in ("server/discover", "initialize"):
                    relay.forward(message)
                else:
                    tasks.submit(relay.forward, message)
        finally:
            relay.close()


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, IndexError, TypeError) as error:
        print(f"Revelation MCP: {error}", file=sys.stderr)
        sys.exit(1)
