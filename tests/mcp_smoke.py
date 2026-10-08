"""End-to-end MCP → local IPC → Qt WebEngine test with isolated storage/keyring."""
import http.server
import json
import os
from pathlib import Path
import select
import ssl
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / "build/hesh"
HTML = b'''<!doctype html><title>MCP fixture</title><body><h1>Test app</h1>
<form><label for="email">Email</label><input id="email" type="email" autocomplete="username">
<label for="password">Password</label><input id="password" type="password">
<button id="submit" type="button" onclick="document.querySelector('#result').textContent=document.querySelector('#email').value + (document.querySelector('#password').value==='dummy-test-password' ? ' LOGIN_OK' : ' CLICK_OK')">Sign in</button></form>
<button class="duplicate">One</button><button class="duplicate">Two</button><p id="result"></p></body>'''

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        self.wfile.write(HTML)
    def log_message(self, *args):
        pass

with tempfile.TemporaryDirectory(prefix="hesh-mcp-test-") as folder:
    temporary = Path(folder)
    env = dict(os.environ, XDG_RUNTIME_DIR=folder, XDG_CONFIG_HOME=folder,
               XDG_DATA_HOME=folder, XDG_CACHE_HOME=folder,
               QT_QPA_PLATFORM="offscreen", QTWEBENGINE_CHROMIUM_FLAGS="--disable-gpu --ignore-certificate-errors",
               QT_QUICK_BACKEND="software", PATH=folder + os.pathsep + os.environ["PATH"])
    # Stub only the keyring boundary: no test accesses a user's real passwords.
    secret = temporary / "secret-tool"
    secret.write_text('''#!/usr/bin/env python3
import json, sys
from pathlib import Path
path = Path(__file__).with_name('test-keyring.json')
values = json.loads(path.read_text()) if path.exists() else {}
action = sys.argv[1]
args = sys.argv[2:]
if args and args[0].startswith('--label='): args.pop(0)
if args and args[0] == '--': args.pop(0)
key = json.dumps(args)
if action == 'store': values[key] = sys.stdin.read()
elif action == 'clear': values.pop(key, None)
elif action == 'lookup':
    if key not in values: sys.exit(1)
    print(values[key]); sys.exit(0)
path.write_text(json.dumps(values))
''')
    secret.chmod(0o700)
    subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", str(temporary / "key.pem"),
                    "-out", str(temporary / "cert.pem"), "-days", "1", "-subj", "/CN=localhost"], check=True, capture_output=True)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(temporary / "cert.pem", temporary / "key.pem")
    server.socket = context.wrap_socket(server.socket, server_side=True)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    site = f"https://127.0.0.1:{server.server_port}"
    backend = None
    mcp = None
    with open(temporary / "backend.log", "w+") as log:
        def start_backend():
            process = subprocess.Popen([str(BINARY), "--background"], env=env, stdout=log, stderr=log)
            for _ in range(100):
                if (temporary / "hesh-control").exists() and control(action="list").get("ok"): return process
                if process.poll() is not None:
                    log.seek(0); raise AssertionError(log.read())
                time.sleep(0.1)
            raise AssertionError("Backend startup timed out")
        def control(**command):
            result = subprocess.run([str(BINARY), "--control", json.dumps(command)], env=env, capture_output=True, text=True, timeout=20)
            return json.loads(result.stdout)
        counter = 0
        def rpc(method, params=None):
            global counter
            counter += 1
            mcp.stdin.write(json.dumps({"jsonrpc": "2.0", "id": counter, "method": method, "params": params or {}}) + "\n")
            mcp.stdin.flush()
            assert select.select([mcp.stdout], [], [], 25)[0], "MCP response timed out"
            reply = json.loads(mcp.stdout.readline())
            assert reply["id"] == counter, reply
            return reply
        def call(tool_name, **arguments):
            response = rpc("tools/call", {"name": tool_name, "arguments": arguments})
            assert "result" in response, response
            return json.loads(response["result"]["content"][0]["text"])
        try:
            backend = start_backend()
            mcp = subprocess.Popen([sys.executable, str(ROOT / "integrations/mcp/hesh_mcp.py"), "--no-autostart"],
                                   env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            init = rpc("initialize", {"protocolVersion": "2025-11-25", "clientInfo": {"name": "MCP test"}})
            assert init["result"]["protocolVersion"] == "2025-11-25"
            mcp.stdin.write('{"jsonrpc":"2.0","method":"notifications/initialized"}\n'); mcp.stdin.flush()
            assert len(rpc("tools/list")["result"]["tools"]) == 5
            assert rpc("tools/call", {"name": "hesh_devices", "arguments": {"action": "clear"}})["error"]["code"] == -32602
            assert call("hesh_memory", action="put", key="test/task", value={"status": "remember me"})["ok"]
            assert call("hesh_memory", action="get", key="test/task")["value"]["status"] == "remember me"
            created = call("hesh_devices", action="create", name="MCP fixture", profile="Desktop", url=site)
            assert created["ok"], created
            device = created["id"]
            page = call("hesh_inspect", id=device)
            assert page["ok"], page
            assert page["page"]["title"] == "MCP fixture", page
            context = call("hesh_devices", action="context", id=device)
            assert context["context"]["id"] == device
            assert context["context"]["presentation"] == "standalone window", context
            assert context["context"]["visible"] is True
            assert context["context"]["viewport"]["width"] > 0
            assert device in context["prompt"] and "hesh_inspect" in context["prompt"]
            assert "standalone window" in context["prompt"]
            assert any(e["selector"] == "#email" for e in page["page"]["elements"])
            started = time.monotonic()
            result = call("hesh_interact", id=device, steps=[{"action": "fill", "selector": "#email", "value": "agent@example.com"}, {"action": "click", "selector": "#submit"}])
            elapsed = (time.monotonic() - started) * 1000
            assert result["ok"] and "agent@example.com CLICK_OK" in result["page"]["text"], result
            assert not call("hesh_interact", id=device, steps=[{"action": "click", "selector": ".duplicate"}])["ok"]
            assert not call("hesh_interact", id=device, steps=[{"action": "fill", "selector": "#password", "value": "blocked"}])["ok"]
            assert not control(action="credential_save", origin="http://example.com", email="a", password="b")["ok"]
            assert control(action="credential_save", origin=site, email="saved@example.com", password="dummy-test-password")["ok"]
            assert call("hesh_logins", action="list")["accounts"][0]["email"] == "saved@example.com"
            assert not call("hesh_logins", action="fill", id=device, origin="https://different.example", email="saved@example.com")["ok"]
            filled = call("hesh_logins", action="fill", id=device, origin=site, email="saved@example.com")
            assert filled["ok"] and filled["submitted"] is False, filled
            assert "dummy-test-password" not in json.dumps(filled)
            snapshot = call("hesh_inspect", id=device)
            assert "dummy-test-password" not in json.dumps(snapshot)
            clicked = call("hesh_interact", id=device, steps=[{"action": "click", "selector": "#submit"}])
            assert "saved@example.com LOGIN_OK" in clicked["page"]["text"], clicked
            state_path = temporary / "Hesh/Hesh/automation/state.json"
            assert "dummy-test-password" not in state_path.read_text()
            assert state_path.stat().st_mode & 0o777 == 0o600
            backend.terminate(); backend.wait(timeout=10)
            backend = start_backend()
            assert call("hesh_memory", action="get", key="test/task")["value"]["status"] == "remember me"
            assert call("hesh_devices", action="list")["devices"][0]["id"] == device
            assert control(action="credential_delete", origin=site, email="saved@example.com")["ok"]
            assert call("hesh_logins", action="list")["accounts"] == []
            assert call("hesh_memory", action="delete", key="test/task")["ok"]
            assert not call("hesh_memory", action="get", key="test/task")["ok"]
            print(f"MCP smoke passed: protocol, validation, real WebEngine inspection/batch ({elapsed:.1f} ms), keyring boundary, origin restriction, no password in responses/storage, persistence")
        except Exception:
            log.flush(); log.seek(0); print(log.read(), file=sys.stderr)
            raise
        finally:
            if mcp: mcp.terminate(); mcp.wait(timeout=10)
            if backend: backend.terminate(); backend.wait(timeout=10)
            server.shutdown()
