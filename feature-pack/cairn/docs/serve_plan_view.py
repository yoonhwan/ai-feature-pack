#!/usr/bin/env python3
"""cairn plan viewer 서버 모드 프로토타입.

file:// 는 브라우저가 로컬 문서 열기를 차단 → localhost 서버가 /open?path= 요청 시
OS `open`을 서버측에서 실행. 이게 설계문서에 넣을 `cairn render --serve`의 실체.

사용: serve_plan_view.py <view.html> [port]
"""
import os
import subprocess
import sys
import urllib.parse
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

VIEW = Path(sys.argv[1]).resolve()
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8899
ROOT = VIEW.parent


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=str(ROOT), **k)

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        if u.path == "/open":
            q = urllib.parse.parse_qs(u.query)
            path = (q.get("path") or [""])[0]
            ok = bool(path) and os.path.exists(path)
            if ok:
                subprocess.run(["open", path], check=False)  # macOS: 기본 앱으로 열기
            self.send_response(200 if ok else 404)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"ok" if ok else b"not found")
            return
        if u.path == "/":
            self.path = "/" + VIEW.name
        return super().do_GET()

    def log_message(self, *a):
        pass


print(f"cairn viewer: http://localhost:{PORT}/  (view={VIEW.name})")
ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
