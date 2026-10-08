"""Exercise the real control socket with isolated settings and no desktop windows."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

binary = str(Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix="hesh-control-test-") as temporary:
    env = dict(os.environ, XDG_RUNTIME_DIR=temporary, XDG_CONFIG_HOME=temporary,
               XDG_DATA_HOME=temporary, XDG_CACHE_HOME=temporary,
               QT_QPA_PLATFORM="offscreen", QTWEBENGINE_CHROMIUM_FLAGS="--disable-gpu")
    def control(**request):
        result = subprocess.run([binary, "--control", json.dumps(request)], env=env,
                                capture_output=True, text=True, timeout=10)
        return result.returncode, json.loads(result.stdout)
    with open(Path(temporary) / "backend.log", "w+") as log:
        backend = subprocess.Popen([binary, "--background"], env=env, stdout=log, stderr=log)
        try:
            for _ in range(50):
                code, reply = control(action="list")
                if code == 0:
                    break
                if backend.poll() is not None:
                    log.seek(0)
                    raise AssertionError(log.read())
                time.sleep(0.1)
            assert reply["ok"] and reply["devices"] == [], reply
            code, created = control(action="create", name="Socket test", profile="Pixel 7", url="http://localhost:9")
            assert code == 0, created
            device_id = created["id"]
            _, reply = control(action="list")
            assert reply["devices"][0]["name"] == "Socket test"
            assert control(action="start", id=device_id)[0] == 0
            _, reply = control(action="list")
            assert reply["devices"][0]["status"] == "Running"
            assert control(action="stop", id=device_id)[0] == 0
            _, reply = control(action="list")
            assert reply["devices"][0]["status"] == "Stopped"
            assert control(action="url", id=device_id, url="file:///etc/passwd")[0] != 0
            assert control(action="url", id=device_id, url="http://localhost:10")[0] == 0
            assert control(action="preview", id="missing")[0] != 0
            assert control(action="create", name="Invalid", profile="Unknown", url="http://localhost:9")[0] != 0
            second = subprocess.run([binary, "--background"], env=env, capture_output=True, timeout=10)
            assert second.returncode == 0
            assert control(action="list")[1]["devices"][0]["url"] == "http://localhost:10"
            print("Control smoke test passed: create, list, start/stop, URL validation, singleton backend")
        finally:
            backend.terminate()
            backend.wait(timeout=10)
