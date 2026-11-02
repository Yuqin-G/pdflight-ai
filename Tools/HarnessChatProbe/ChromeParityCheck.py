#!/usr/bin/env python3
"""Render the independent Harness reference and migrated chat in Chromium.

Uses a fresh, disposable headless Chrome profile and synthetic messages only.
Requires websocket-client in the selected Python environment.
"""
import argparse
import base64
import functools
import http.server
import json
import subprocess
import tempfile
import threading
import time
import urllib.request
from pathlib import Path
import websocket


def differences(a, b, path='layout'):
    if isinstance(a, (int, float)) and not isinstance(a, bool) and isinstance(b, (int, float)) and not isinstance(b, bool):
        return [] if abs(a - b) <= .8 else [f'{path}: {a} != {b}']
    if type(a) is not type(b):
        return [f'{path}: types differ']
    if isinstance(a, dict):
        if set(a) != set(b):
            return [f'{path}: keys differ']
        return [d for k in a for d in differences(a[k], b[k], path+'.'+k)]
    if isinstance(a, list):
        if len(a) != len(b):
            return [f'{path}: lengths {len(a)} != {len(b)}']
        return [d for i, (x, y) in enumerate(zip(a, b)) for d in differences(x, y, f'{path}[{i}]')]
    return [] if a == b else [f'{path}: {a!r} != {b!r}']


class Page:
    def __init__(self, endpoint, url, device_scale_factor):
        req = urllib.request.Request(endpoint+'/json/new?about:blank', method='PUT')
        target = json.load(urllib.request.urlopen(req))
        self.ws = websocket.create_connection(target['webSocketDebuggerUrl'], suppress_origin=True, timeout=20)
        self.counter = 0
        self.call('Page.enable')
        self.call('Emulation.setDeviceMetricsOverride', {'width':420, 'height':900,
                  'deviceScaleFactor':device_scale_factor, 'mobile':False})
        self.call('Page.navigate', {'url': url})
        for _ in range(100):
            if self.evaluate('Boolean(window.PDFlightReplaceMessages && window.__setChatZoom)'):
                break
            time.sleep(.05)
        else:
            raise RuntimeError('Renderer not ready: '+url)

    def call(self, method, params=None):
        self.counter += 1
        request_id = self.counter
        self.ws.send(json.dumps({'id':request_id, 'method':method, 'params': params or {}}))
        while True:
            result = json.loads(self.ws.recv())
            if result.get('id') == request_id:
                if 'error' in result:
                    raise RuntimeError(result['error'])
                return result.get('result', {})

    def evaluate(self, expression):
        # Give each independent page a foreground rendering frame, including
        # IntersectionObserver-driven code rendering in the original UI.
        self.call('Page.bringToFront')
        result = self.call('Runtime.evaluate', {'expression': expression, 'awaitPromise': True, 'returnByValue': True})
        if 'exceptionDetails' in result:
            raise RuntimeError(result['exceptionDetails'])
        return result.get('result', {}).get('value')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('production', type=Path)
    parser.add_argument('reference', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--chrome', default='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
    parser.add_argument('--device-scale-factor', type=float, default=2,
                        help='Match the backing scale of the WebKit test window (2 on this Retina display)')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    here = Path(__file__).resolve().parent
    fixture = (here/'parity-fixture.js').read_text()
    measure = (here/'parity-metrics.js').read_text()
    with tempfile.TemporaryDirectory(prefix='pdflight-chrome-parity-') as temporary:
        root = Path(temporary)
        (root/'production').symlink_to(args.production.resolve(), target_is_directory=True)
        (root/'reference').symlink_to(args.reference.resolve(), target_is_directory=True)
        class QuietHandler(http.server.SimpleHTTPRequestHandler):
            def log_message(self, *args): pass
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(QuietHandler, directory=str(root)))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        process = subprocess.Popen([args.chrome, '--headless=new', '--disable-gpu', '--disable-background-networking',
            '--disable-sync', '--disable-extensions', '--no-first-run', '--no-default-browser-check',
            '--remote-debugging-port=0', '--user-data-dir='+str(root/'profile'), 'about:blank'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            portfile = root/'profile/DevToolsActivePort'
            for _ in range(200):
                if portfile.exists(): break
                if process.poll() is not None: raise RuntimeError('Headless Chrome exited early')
                time.sleep(.05)
            port = portfile.read_text().splitlines()[0]
            endpoint = 'http://127.0.0.1:'+port
            base = 'http://127.0.0.1:'+str(server.server_port)
            pages = [Page(endpoint, base+'/production/preview.html', args.device_scale_factor),
                     Page(endpoint, base+'/reference/reference.html', args.device_scale_factor)]
            for page in pages:
                actual_scale = page.evaluate('devicePixelRatio')
                if actual_scale != args.device_scale_factor:
                    raise RuntimeError(f'Backing scale {actual_scale} differs from requested {args.device_scale_factor}')
            for page in pages: page.evaluate('(async()=>{'+fixture+'})()')
            # Highlighted code loads its renderer asynchronously. Measure the
            # settled components, not the transient plain-pre fallback.
            for page in pages:
                page.evaluate('(async()=>{await document.fonts.ready; document.querySelector("pre")?.scrollIntoView(); await new Promise(r=>setTimeout(r,600));})()')
            failures=[]
            for width in [420, 680, 1100]:
                for page in pages:
                    page.call('Emulation.setDeviceMetricsOverride', {'width':width, 'height':900, 'deviceScaleFactor':args.device_scale_factor, 'mobile':False})
                for zoom in [.8, 1, 1.6, 2.4]:
                    label=f'{width}px-{round(zoom*100)}pct'
                    samples=[]
                    for page, name in zip(pages, ['migrated', 'reference']):
                        sample=json.loads(page.evaluate('(async()=>{window.__setChatZoom('+str(zoom)+');'+measure+'})()'))
                        samples.append(sample)
                        (args.output/(label+'-'+name+'.json')).write_text(json.dumps(sample, ensure_ascii=False, indent=2))
                        shot=page.call('Page.captureScreenshot', {'format':'png', 'captureBeyondViewport':False})
                        (args.output/(label+'-'+name+'.png')).write_bytes(base64.b64decode(shot['data']))
                    errors=differences(samples[0], samples[1])
                    print(('FAIL' if errors else 'PASS')+': Chromium reading parity '+label+(' '+str(errors[:3]) if errors else ''), flush=True)
                    failures.extend(errors)
            if failures: raise SystemExit(1)
        finally:
            process.terminate()
            try: process.wait(timeout=10)
            except subprocess.TimeoutExpired: process.kill(); process.wait()
            server.shutdown()


if __name__ == '__main__': main()
