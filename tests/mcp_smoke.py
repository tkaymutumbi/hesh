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

NATIVE = "--native" in sys.argv
ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / "build/hesh"
HTML = b'''<!doctype html><meta http-equiv="Content-Security-Policy" content="script-src 'self' 'unsafe-inline'"><title>MCP fixture</title><body><h1>Test app</h1>
<form><label for="email">Email</label><input id="email" type="email" autocomplete="username">
<label for="password">Password</label><input id="password" type="password">
<button id="submit" type="button" onclick="document.querySelector('#result').textContent=document.querySelector('#email').value + (document.querySelector('#password').value==='dummy-test-password' ? ' LOGIN_OK' : ' CLICK_OK')">Sign in</button></form>
<input id="files" type="file" multiple style="display:none" onchange="document.querySelector('#filename').textContent=Array.from(this.files).map(f=>f.name).join(',')">
<button id="choose" onclick="document.querySelector('#files').click()">Choose file</button><p id="filename"></p>
<button class="duplicate">One</button><button class="duplicate">Two</button><p id="result"></p>
<script>window.fixtureState = {answer: 42}; console.log('fixture-log'); console.warn('fixture-warn'); console.error('fixture-error');</script></body>'''

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(429 if self.path == "/http-challenge" else 200)
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
    if NATIVE: env["HESH_DESKTOP_BROWSER"] = "chromium"
    else: env["HESH_DESKTOP_BROWSER"] = "embedded"
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
            assert {t["name"] for t in rpc("tools/list")["result"]["tools"]} >= {"hesh_apps", "hesh_logins", "hesh_session"}
            assert rpc("tools/call", {"name": "hesh_devices", "arguments": {"action": "clear"}})["error"]["code"] == -32602
            assert call("hesh_memory", action="put", key="test/task", value={"status": "remember me"})["ok"]
            assert call("hesh_memory", action="get", key="test/task")["value"]["status"] == "remember me"
            created = call("hesh_devices", action="create", name="MCP fixture", profile="Desktop", url=site)
            assert created["ok"], created
            device = created["id"]
            page = call("hesh_inspect", id=device)
            assert page["ok"], page
            assert page["page"]["title"] == "MCP fixture", page
            app = call("hesh_apps", action="save", name="Test application", url=site)
            assert app["ok"], app
            app_id = app["siteId"]
            assert call("hesh_apps", action="list")["sites"][0]["id"] == app_id
            assert not call("hesh_apps", action="save", name="Bad", url="https://user:password@example.com")["ok"]
            assert call("hesh_apps", action="save", siteId=app_id, name="Updated application", url=site)["ok"]
            context = call("hesh_devices", action="context", id=device)
            assert context["context"]["id"] == device
            assert context["context"]["presentation"] == "standalone window", context
            assert context["context"]["visible"] is True
            assert context["context"]["viewport"]["width"] > 0
            actual = call("hesh_eval", id=device, expression="({width: innerWidth, height: innerHeight, ua: navigator.userAgent})")
            assert abs(actual["value"]["width"] - context["context"]["viewport"]["width"]) <= 2, (context, actual)
            assert "Mobile" not in actual["value"]["ua"] and "Chrome/120." not in actual["value"]["ua"], actual
            assert device in context["prompt"] and "hesh_inspect" in context["prompt"]
            assert "standalone window" in context["prompt"]
            assert any(e["selector"] == "#email" for e in page["page"]["elements"])
            # Console is buffered from page load, filterable, and clearable.
            logs = call("hesh_console", id=device)
            assert logs["ok"] and {"fixture-log", "fixture-warn", "fixture-error"} <= {m["message"] for m in logs["messages"]}, logs
            assert [m["message"] for m in call("hesh_console", id=device, level="error")["messages"]] == ["fixture-error"]
            assert {m["level"] for m in call("hesh_console", id=device, level="warning")["messages"]} == {"warning", "error"}
            assert [m["message"] for m in call("hesh_console", id=device, pattern="LOG$")["messages"]] == ["fixture-log"]
            assert not call("hesh_console", id=device, pattern="(")["ok"]
            assert call("hesh_console", id=device, clear=True)["ok"]
            assert call("hesh_console", id=device)["messages"] == []
            # HTTP errors with a real response body must remain visible and
            # controllable (e.g. a site's verification page), not get hidden
            # under the browser's connection-error overlay.
            assert call("hesh_devices", action="url", id=device, url=site + "/http-challenge")["ok"]
            for _ in range(40):
                challenge = call("hesh_inspect", id=device)
                if challenge.get("ok") and challenge["page"]["url"].endswith("/http-challenge"): break
                time.sleep(.1)
            assert challenge["ok"] and challenge["page"]["title"] == "MCP fixture", challenge
            assert call("hesh_devices", action="url", id=device, url=site)["ok"]
            for _ in range(40):
                restored_page = call("hesh_inspect", id=device)
                if restored_page.get("ok") and not restored_page["page"]["url"].endswith("/http-challenge"): break
                time.sleep(.1)
            assert restored_page["ok"], restored_page
            assert call("hesh_apps", action="open", siteId=app_id, id=device)["ok"]
            assert call("hesh_devices", action="applications", id=device)["ok"]
            # Eval: page globals, isolated world, promises, errors.
            assert call("hesh_eval", id=device, expression="window.fixtureState.answer")["value"] == 42
            assert call("hesh_eval", id=device, expression="Promise.resolve({a: [1, 2]})")["value"] == {"a": [1, 2]}
            assert call("hesh_eval", id=device, expression="typeof window.fixtureState", world="isolated")["value"] == "undefined"
            assert call("hesh_eval", id=device, expression="document.title")["value"] == "MCP fixture"
            assert not call("hesh_eval", id=device, expression="nope.nope")["ok"]
            assert not call("hesh_eval", id=device, expression="new Promise(() => {})", timeoutMs=600)["ok"]
            # Screenshot: PNG of the page content, saved to the requested path.
            shot_path = str(Path(folder) / "shot.png")
            shot = call("hesh_devices", action="screenshot", id=device, path=shot_path)
            assert shot["ok"] and shot["path"] == shot_path and shot["width"] > 0 and shot["bytes"] > 1000, shot
            assert Path(shot_path).read_bytes()[:8] == b"\x89PNG\r\n\x1a\n"
            assert not call("hesh_devices", action="screenshot", id=device, path="relative.png")["ok"]
            assert not call("hesh_devices", action="screenshot", id=device, path=str(Path(folder) / "x.jpg"))["ok"]
            assert rpc("tools/call", {"name": "hesh_devices", "arguments": {"action": "delete", "id": device}})["error"]["code"] == -32602
            started = time.monotonic()
            result = call("hesh_interact", id=device, steps=[{"action": "fill", "selector": "#email", "value": "agent@example.com"}, {"action": "click", "selector": "#submit"}])
            elapsed = (time.monotonic() - started) * 1000
            assert result["ok"] and "agent@example.com CLICK_OK" in result["page"]["text"], result
            assert not call("hesh_interact", id=device, steps=[{"action": "click", "selector": ".duplicate"}])["ok"]
            assert not call("hesh_interact", id=device, steps=[{"action": "fill", "selector": "#password", "value": "blocked"}])["ok"]
            upload = temporary / "upload-fixture.txt"
            upload.write_text("local upload fixture")
            attached = call("hesh_interact", id=device, steps=[{"action": "upload", "selector": "#files", "paths": [str(upload)]}])
            assert attached["ok"] and 'upload-fixture.txt' in attached["page"]["text"], attached
            assert call("hesh_eval", id=device, expression="document.querySelector('#files').files[0].name")["value"] == 'upload-fixture.txt'
            if NATIVE:
                staged = temporary / "staged-fixture.txt"
                staged.write_text("staged upload fixture")
                result = call("hesh_interact", id=device, steps=[{"action": "upload", "paths": [str(staged)]}, {"action": "click", "selector": "#choose"}])
                assert result["ok"], result
                for _ in range(40):
                    chosen = call("hesh_eval", id=device, expression="document.querySelector('#files').files[0]?.name")
                    if chosen.get("value") == 'staged-fixture.txt': break
                    time.sleep(.1)
                assert chosen.get("value") == 'staged-fixture.txt', chosen
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
            # The same vault entry can fill a separate mobile web device.
            mobile = call("hesh_devices", action="create", name="Mobile fixture", profile="Pixel 7", url=site)["id"]
            assert call("hesh_inspect", id=mobile)["ok"]
            assert call("hesh_logins", action="fill", id=mobile, origin=site, email="saved@example.com")["ok"]
            assert "saved@example.com LOGIN_OK" in call("hesh_interact", id=mobile, steps=[{"action": "click", "selector": "#submit"}])["page"]["text"]
            # Privacy can change while retaining the password in the keyring.
            assert control(action="credential_save", origin=site, email="saved@example.com", private=True)["ok"]
            assert call("hesh_logins", action="list")["accounts"] == []
            assert not call("hesh_logins", action="fill", id=mobile, origin=site, email="saved@example.com")["ok"]
            assert not call("hesh_logins", action="save", origin=site, email="saved@example.com", password="replacement")["ok"]
            assert control(action="credential_save", origin=site, email="saved@example.com", private=False)["ok"]
            assert call("hesh_logins", action="fill", id=device, origin=site, email="saved@example.com")["ok"]
            # Username and password can live on separate sign-in steps.
            assert call("hesh_eval", id=device, expression="(document.querySelector('#password').style.display='none',true)")["ok"]
            part = call("hesh_logins", action="fill", id=device, origin=site, email="saved@example.com")
            assert part["ok"] and part["fields"] == ["username"], part
            assert call("hesh_eval", id=device, expression="(document.querySelector('#password').style.display='',document.querySelector('#email').style.display='none',true)")["ok"]
            part = call("hesh_logins", action="fill", id=device, origin=site, email="saved@example.com")
            assert part["ok"] and part["fields"] == ["password"], part
            assert call("hesh_eval", id=device, expression="(document.querySelector('#email').style.display='',true)")["ok"]
            # Human authentication cannot be resumed or bypassed by the agent.
            handoff = call("hesh_session", action="login", id=device, message="Complete two-factor authentication.")
            assert handoff["ok"] and handoff["pausedBy"] == "user", handoff
            assert not call("hesh_inspect", id=device)["ok"]
            assert not call("hesh_session", action="resume")["ok"]
            assert call("hesh_session", action="pause")["pausedBy"] == "user"
            assert not call("hesh_session", action="start")["ok"]
            assert control(action="agent_resume")["ok"]
            assert call("hesh_inspect", id=device)["ok"]
            # Detect an OTP challenge before any agent fills or clicks it.
            assert call("hesh_eval", id=device, expression="(()=>{let e=document.createElement('input');e.id='otp';e.autocomplete='one-time-code';document.body.append(e);return true})()")["ok"]
            challenge = call("hesh_inspect", id=device)
            assert challenge["ok"] and challenge["humanRequired"], challenge
            assert call("hesh_session", action="status")["pausedBy"] == "user"
            assert not call("hesh_interact", id=device, steps=[{"action":"fill", "selector":"#otp", "value":"123456"}])["ok"]
            assert control(action="eval", id=device, expression="(document.querySelector('#otp').remove(),true)")["ok"]
            assert control(action="agent_resume")["ok"]
            # A popup shares cookies/storage, retains its opener, and becomes the MCP target.
            assert call("hesh_eval", id=device, expression="(localStorage.setItem('session-fixture','persistent'),document.cookie='hesh_session=logged-in; path=/; SameSite=Lax; Secure',true)")["ok"]
            assert call("hesh_eval", id=device, expression="(window.open('/popup', 'fixture-auth'),true)")["ok"]
            for _ in range(40):
                popup_context = call("hesh_devices", action="context", id=device)
                if popup_context["context"]["popup"] and popup_context["context"]["url"].endswith('/popup'): break
                time.sleep(0.1)
            assert popup_context["context"]["popup"], popup_context
            popup_page = call("hesh_inspect", id=device)
            assert popup_page["ok"], popup_page
            shared = call("hesh_eval", id=device, expression="({opener:!!window.opener,cookie:document.cookie,stored:localStorage.getItem('session-fixture')})")
            assert shared["value"]["opener"] and 'hesh_session=logged-in' in shared["value"]["cookie"] and shared["value"]["stored"] == 'persistent', shared
            assert call("hesh_logins", action="fill", id=device, origin=site, email="saved@example.com")["ok"]
            call("hesh_eval", id=device, expression="(window.close(),true)")
            for _ in range(40):
                restored = call("hesh_devices", action="context", id=device)
                if not restored["context"]["popup"]: break
                time.sleep(0.1)
            assert not restored["context"]["popup"], restored
            # Browsing to a different URL preserves the original site's data.
            assert call("hesh_devices", action="url", id=device, url=site + '/another')["ok"]
            assert call("hesh_inspect", id=device)["ok"]
            assert call("hesh_eval", id=device, expression="localStorage.getItem('session-fixture')")["value"] == 'persistent'
            assert call("hesh_devices", action="list")["devices"][0]["url"].endswith('/another')
            # Chromium flushes cookies periodically, including forced-persistent session cookies.
            time.sleep(32)
            state_path = temporary / "Hesh/Hesh/automation/state.json"
            assert "dummy-test-password" not in state_path.read_text()
            assert state_path.stat().st_mode & 0o777 == 0o600
            assert control(action="quit")["ok"]
            backend.wait(timeout=15)
            backend = start_backend()
            assert call("hesh_memory", action="get", key="test/task")["value"]["status"] == "remember me"
            assert call("hesh_devices", action="list")["devices"][0]["id"] == device
            assert call("hesh_apps", action="list")["sites"][0]["name"] == "Updated application"
            assert call("hesh_inspect", id=device)["page"]["url"].endswith('/another')
            persisted = call("hesh_eval", id=device, expression="({cookie:document.cookie,stored:localStorage.getItem('session-fixture')})")
            assert persisted["value"]["stored"] == 'persistent' and 'hesh_session=logged-in' in persisted["value"]["cookie"], persisted
            assert call("hesh_logins", action="fill", id=device, origin=site, email="saved@example.com")["ok"]
            assert call("hesh_apps", action="delete", siteId=app_id)["ok"]
            assert call("hesh_apps", action="list")["sites"] == []
            assert control(action="credential_delete", origin=site, email="saved@example.com")["ok"]
            assert call("hesh_logins", action="list")["accounts"] == []
            assert call("hesh_memory", action="delete", key="test/task")["ok"]
            assert not call("hesh_memory", action="get", key="test/task")["ok"]
            print(f"MCP smoke passed: protocol, validation, real {"Chromium" if NATIVE else "WebEngine"} inspection/batch ({elapsed:.1f} ms), keyring boundary, origin restriction, no password in responses/storage, persistence")
        except Exception:
            log.flush(); log.seek(0); print(log.read(), file=sys.stderr)
            raise
        finally:
            if mcp: mcp.terminate(); mcp.wait(timeout=10)
            if backend: backend.terminate(); backend.wait(timeout=10)
            server.shutdown()
