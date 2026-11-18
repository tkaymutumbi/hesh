"""Private Chromium DevTools pipe bridge. No debugging port or third-party modules."""
import base64
import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import threading
import time
from urllib.parse import urlparse

OUTPUT_LOCK = threading.Lock()
def emit(value):
    with OUTPUT_LOCK:
        print(json.dumps(value, separators=(',', ':')), flush=True)

class Browser:
    def __init__(self, config):
        self.pending = {}
        self.lock = threading.Lock()
        self.counter = 0
        self.pages = []
        self.sessions = {}
        self.main_page = None
        self.script = config['script']
        self.headless = config.get('headless', False)
        self.closed = False
        self.staged = {}
        # Chromium expects its private CDP input/output on descriptors 3 and 4.
        child_read, self.writer = os.pipe()
        self.reader, child_write = os.pipe()
        args = [config['binary'], '--remote-debugging-pipe', '--no-first-run',
                '--no-default-browser-check', '--disable-background-mode',
                '--restore-last-session', '--user-data-dir=' + config['storage'],
                '--window-size=' + str(config['width']) + ',' + str(config['height']),
                '--window-position=' + str(config['x']) + ',' + str(config['y']),
                '--class=hesh-desktop-' + config['id']]
        if config.get('headless'):
            args += ['--headless=new', '--disable-gpu', '--ignore-certificate-errors']
        restoring = (Path(config['storage']) / 'Default' / 'Sessions').exists()
        if not restoring:
            args += ['--new-window', config['url']]
        bootstrap = ('import os,sys; '
                     'os.dup2(int(sys.argv[1]),3); os.dup2(int(sys.argv[2]),4); '
                     'os.set_inheritable(3,True); os.set_inheritable(4,True); '
                     'os.execv(sys.argv[3],sys.argv[3:])')
        self.process = subprocess.Popen([sys.executable, '-c', bootstrap, str(child_read), str(child_write), *args],
                                       pass_fds=(child_read, child_write), stdin=subprocess.DEVNULL,
                                       stdout=subprocess.DEVNULL, stderr=sys.stderr)
        os.close(child_read)
        os.close(child_write)
        threading.Thread(target=self.read, daemon=True).start()
        self.cdp('Target.setDiscoverTargets', {'discover': True})
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            try:
                self.refresh()
                if not self.pages and time.monotonic() > deadline - 9:
                    self.cdp('Target.createTarget', {'url': config['url']})
                    self.refresh()
                if self.pages:
                    match = next((p for p in self.pages if p['url'].rstrip('/') == config['url'].rstrip('/')), self.pages[0])
                    self.main_page = match['targetId']
                    self.current()
                    self.state()
                    break
            except RuntimeError:
                pass
            time.sleep(.1)
        else:
            raise RuntimeError('Chromium did not open a browser page')

    def read(self):
        buffered = b''
        try:
            while True:
                data = os.read(self.reader, 65536)
                if not data:
                    break
                buffered += data
                while b'\0' in buffered:
                    raw, buffered = buffered.split(b'\0', 1)
                    if not raw:
                        continue
                    event = json.loads(raw)
                    if 'id' in event:
                        with self.lock:
                            waiter = self.pending.get(event['id'])
                        if waiter:
                            waiter.put(event)
                    elif event.get('method') == 'Page.fileChooserOpened':
                        session = event.get('sessionId')
                        files = self.staged.pop(session, [])
                        if files:
                            threading.Thread(target=self.attach_files,
                                args=(session, event['params']['backendNodeId'], files), daemon=True).start()
                    elif event.get('method') == 'Runtime.consoleAPICalled':
                        params = event['params']
                        values = params.get('args', [])
                        message = ' '.join(str(v.get('value', v.get('description', ''))) for v in values)[:4000]
                        kind = params.get('type', 'log')
                        emit({'event': 'console', 'level': 2 if kind == 'error' else 1 if kind == 'warning' else 0,
                              'message': message, 'line': 0, 'source': ''})
                    elif event.get('method') == 'Runtime.exceptionThrown':
                        details = event['params']['exceptionDetails']
                        emit({'event': 'console', 'level': 2, 'message': details.get('exception', {}).get('description', details.get('text', 'JavaScript error'))[:4000],
                              'line': details.get('lineNumber', 0), 'source': details.get('url', '')})
        finally:
            self.closed = True
            with self.lock:
                for waiter in self.pending.values():
                    waiter.put({'error': {'message': 'Desktop browser closed'}})
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.terminate()
            emit({'event': 'closed'})
            # Wake the stdin loop so its parent can reap this bridge.
            os._exit(0)

    def attach_files(self, session, node, files):
        try:
            self.cdp('DOM.setFileInputFiles', {'backendNodeId': node, 'files': files}, session)
        finally:
            try:
                self.cdp('Page.setInterceptFileChooserDialog', {'enabled': False}, session)
            except RuntimeError:
                pass

    def cdp(self, method, params=None, session=None, timeout=10):
        with self.lock:
            if self.closed:
                raise RuntimeError('Desktop browser closed')
            self.counter += 1
            number = self.counter
            waiter = queue.Queue()
            self.pending[number] = waiter
            command = {'id': number, 'method': method, 'params': params or {}}
            if session:
                command['sessionId'] = session
            payload = json.dumps(command).encode() + b'\0'
            while payload:
                payload = payload[os.write(self.writer, payload):]
        try:
            try:
                reply = waiter.get(timeout=timeout)
            except queue.Empty:
                raise RuntimeError('Desktop browser did not respond in time')
            if 'error' in reply:
                raise RuntimeError(reply['error'].get('message', 'Browser operation failed'))
            return reply.get('result', {})
        finally:
            with self.lock:
                self.pending.pop(number, None)

    def refresh(self):
        targets = self.cdp('Target.getTargets')['targetInfos']
        current = {t['targetId']: t for t in targets if t['type'] == 'page' and not t['url'].startswith('chrome://')}
        previous = [p['targetId'] for p in self.pages if p['targetId'] in current]
        previous += [p for p in current if p not in previous]
        self.pages = [current[p] for p in previous]

    def session_for(self, page):
        target = page['targetId']
        if target not in self.sessions:
            session = self.cdp('Target.attachToTarget', {'targetId': target, 'flatten': True})['sessionId']
            self.sessions[target] = session
            self.cdp('Runtime.enable', session=session)
            self.cdp('Page.enable', session=session)
        return self.sessions[target]

    def current(self):
        self.refresh()
        if not self.pages:
            raise RuntimeError('Page is not ready; open the desktop device preview')
        # Follow the user's focused tab/window, falling back to the newest popup.
        if not self.headless:
            for page in reversed(self.pages):
                session = self.session_for(page)
                try:
                    if self.evaluate('document.hasFocus()', session, 'isolated', timeout=1):
                        return page, session
                except RuntimeError:
                    continue
        page = self.pages[-1]
        return page, self.session_for(page)

    def evaluate(self, expression, session, world='page', timeout=8, user_gesture=False):
        params = {'expression': expression, 'awaitPromise': True, 'returnByValue': True,
                  'timeout': max(500, int(timeout * 1000)), 'userGesture': user_gesture}
        if world == 'isolated':
            frame = self.cdp('Page.getFrameTree', session=session)['frameTree']['frame']['id']
            params['contextId'] = self.cdp('Page.createIsolatedWorld', {'frameId': frame, 'worldName': 'Hesh automation'}, session)['executionContextId']
        result = self.cdp('Runtime.evaluate', params, session, timeout + 1)
        if result.get('exceptionDetails'):
            details = result['exceptionDetails']
            raise RuntimeError(details.get('exception', {}).get('description', details.get('text', 'Page execution failed'))[:1000])
        value = result.get('result', {})
        if value.get('subtype') == 'error':
            raise RuntimeError(value.get('description', 'Page execution failed')[:1000])
        return value.get('value')

    def state(self):
        try:
            page, session = self.current()
            metrics = self.evaluate('({width:innerWidth,height:innerHeight,dpr:devicePixelRatio})', session)
            main = next((p for p in self.pages if p['targetId'] == self.main_page), None)
            emit({'event': 'state', 'url': page['url'], 'mainUrl': main['url'] if main else page['url'],
                  'popup': bool(page.get('openerId')), 'viewport': {'width': (metrics or {}).get('width', 0), 'height': (metrics or {}).get('height', 0), 'devicePixelRatio': (metrics or {}).get('dpr', 1)}})
        except RuntimeError:
            pass

    def execute(self, command):
        action = command['action']
        if action == 'state':
            return {'ok': True}
        if action == 'close':
            self.cdp('Browser.close')
            return {'ok': True}
        if action in ('navigate', 'focus', 'reload', 'back', 'forward'):
            page, session = self.current()
            if action == 'navigate':
                main = next((p for p in self.pages if p['targetId'] == self.main_page), page)
                if main['targetId'] != page['targetId']:
                    session = self.sessions.get(main['targetId']) or self.cdp('Target.attachToTarget', {'targetId': main['targetId'], 'flatten': True})['sessionId']
                self.cdp('Page.navigate', {'url': command['url']}, session)
            elif action == 'focus':
                self.cdp('Target.activateTarget', {'targetId': page['targetId']})
            elif action == 'reload':
                self.cdp('Page.reload', {'ignoreCache': command.get('ignoreCache', False)}, session)
            else:
                history = self.cdp('Page.getNavigationHistory', session=session)
                index = history['currentIndex'] + (-1 if action == 'back' else 1)
                if 0 <= index < len(history['entries']):
                    self.cdp('Page.navigateToHistoryEntry', {'entryId': history['entries'][index]['id']}, session)
            return {'ok': True}
        page, session = self.current()
        # Account sign-in and verification challenges belong to the user.
        reason = ''
        if command.get('agent'):
            if urlparse(page['url']).hostname == 'accounts.google.com':
                reason = 'Complete Google sign-in in the browser, then click Resume AI in Hesh Logins.'
            else:
                challenge = self.evaluate("Array.from(document.querySelectorAll('input[autocomplete=one-time-code],input[name=captcha],iframe[title*=challenge i]')).some(e=>e.getClientRects().length && getComputedStyle(e).visibility!=='hidden')", session)
                if challenge:
                    reason = 'Complete the verification challenge yourself, then click Resume AI.'
        if reason and action not in ('inspect', 'screenshot'):
            return {'ok': False, 'error': reason, 'humanRequired': True}
        if action == 'eval':
            timeout = min(10, max(.5, command.get('timeoutMs', 8000) / 1000))
            value = self.evaluate(command['expression'], session, command.get('world', 'page'), timeout, user_gesture=True)
            if len(json.dumps(value)) > 200000:
                raise RuntimeError('Result is larger than 200000 characters')
            return {'ok': True, 'value': value}
        if page['url'] in ('', 'about:blank') or self.evaluate('document.readyState', session) == 'loading':
            raise RuntimeError('Page is not ready; retry after loading finishes')
        if action == 'screenshot':
            result = self.cdp('Page.captureScreenshot', {'format': 'png', 'captureBeyondViewport': False}, session)
            path = command['path']
            Path(path).write_bytes(base64.b64decode(result['data']))
            metrics = self.evaluate('({width:innerWidth,height:innerHeight,dpr:devicePixelRatio})', session)
            return {'ok': True, 'path': path, 'width': round(metrics['width'] * metrics['dpr']), 'height': round(metrics['height'] * metrics['dpr'])}
        if action == 'interact':
            results = []
            for index, step in enumerate(command.get('steps', [])):
                try:
                    page, session = self.current()
                    if step['action'] == 'stage' and step.get('paths'):
                        self.staged[session] = step['paths']
                        self.cdp('Page.setInterceptFileChooserDialog', {'enabled': True}, session)
                    single = dict(command, steps=[step])
                    raw = self.evaluate('(' + self.script + ')(' + json.dumps(single) + ')', session,
                                        'isolated', user_gesture=True)
                    result = json.loads(raw)
                    if result.get('humanRequired'):
                        result['results'] = results
                        return result
                    if not result.get('ok'):
                        raise RuntimeError(result.get('results', [{}])[-1].get('error', result.get('error', 'Interaction failed')))
                    results.append({'index': index, 'ok': True})
                except Exception as error:
                    results.append({'index': index, 'ok': False, 'error': str(error)[:1000]})
                    return {'ok': False, 'error': 'Batch stopped; earlier steps may have completed', 'results': results}
            page, session = self.current()
            snapshot = dict(command, action='inspect')
            raw = self.evaluate('(' + self.script + ')(' + json.dumps(snapshot) + ')', session, 'isolated')
            result = json.loads(raw)
            result['results'] = results
            return result
        reply = self.evaluate('(' + self.script + ')(' + json.dumps(command) + ')', session, 'isolated', user_gesture=action == 'interact')
        if not isinstance(reply, str):
            raise RuntimeError('Page execution failed')
        result = json.loads(reply)
        if result.get('page', {}).get('url') == 'about:blank':
            return {'ok': False, 'error': 'Page is not ready; navigation has not committed yet'}
        if reason:
            result['humanRequired'] = True
            result['message'] = reason
        return result

if __name__ == '__main__':
    browser = None
    try:
        browser = Browser(json.loads(sys.stdin.readline()))
        for line in sys.stdin:
            request = json.loads(line)
            token = request.pop('token', '')
            try:
                reply = browser.execute(request)
            except Exception as error:
                # Credential commands must never appear in errors or logs.
                reply = {'ok': False, 'error': str(error)[:1000]}
            browser.state()
            emit({'token': token, 'reply': reply})
    except Exception as error:
        emit({'event': 'failed', 'error': str(error)[:1000]})
    finally:
        if browser and browser.process.poll() is None:
            try:
                browser.cdp('Browser.close', timeout=2)
                browser.process.wait(timeout=3)
            except Exception:
                browser.process.terminate()
