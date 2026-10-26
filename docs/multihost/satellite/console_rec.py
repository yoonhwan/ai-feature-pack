#!/usr/bin/env python3
"""console_rec — 시험용 Chrome(CDP) 의 방 탭 콘솔·SSE 를 «필터 없이» 파일로 남기는 읽기 전용 기록기 (2026-10-26 · aifp-multihost-master-claude#4).

왜: 러너 자체 콘솔 캡처(realtime_multi_e2e.py `_browser_console_event_line`)는 warning/error 와 BROWSER_CONSOLE_MARKERS 줄만 남긴다 →
    «콘솔 0줄» 이 «FE 가 조용했다» 의 증거가 못 된다(v65 arch#313 쪽지 168691 필수 칸 ①).
무엇: /room/ 탭마다 Runtime(consoleAPICalled · exceptionThrown) · Log.entryAdded · Network.eventSourceMessageReceived 를 «받기만» 한다.
      host(URL 에 mockHostId) / guest(URL 에 token=) 로 나눠 <out>/host.log · guest.log 에 «epoch 초 + 줄».
하지 않는 것: 입력·클릭·DOM 쓰기·Redis 접촉 0 (하드 룰 11). 러너와 같은 탭에 별도 CDP 연결로 붙을 뿐이다.
사용: console_rec.py <out_dir> <duration_s> <cdp_port>
"""
import asyncio
import json
import os
import sys
import time
import urllib.request

import websockets

OUT, DUR, PORT = sys.argv[1], float(sys.argv[2]), int(sys.argv[3])
os.makedirs(OUT, exist_ok=True)
_files = {}
_urls = {}


def _label(url):
    if "mockHostId" in url:
        return "host"
    if "token=" in url:
        return "guest"
    return "other"


def _w(tid, line):
    lbl = _label(_urls.get(tid, ""))
    f = _files.get(lbl)
    if f is None:
        f = _files[lbl] = open(os.path.join(OUT, lbl + ".log"), "a", buffering=1)
    f.write("%.3f %s\n" % (time.time(), line))


def _arg(a):
    if "value" in a:
        v = a["value"]
        return json.dumps(v, ensure_ascii=False) if isinstance(v, (dict, list)) else str(v)
    return str(a.get("description") or a.get("className") or a.get("type") or "")


async def _watch(tid, ws_url):
    try:
        async with websockets.connect(ws_url, max_size=2 ** 22) as ws:
            for i, m in enumerate(("Runtime.enable", "Log.enable", "Network.enable"), 1):
                await ws.send(json.dumps({"id": i, "method": m}))
            while True:
                ev = json.loads(await ws.recv())
                m, p = ev.get("method"), ev.get("params") or {}
                if m == "Runtime.consoleAPICalled":
                    _w(tid, "console.%s %s" % (p.get("type"), " ".join(_arg(a) for a in p.get("args", []))[:900]))
                elif m == "Runtime.exceptionThrown":
                    d = p.get("exceptionDetails", {})
                    _w(tid, "exception %s" % (d.get("text", "") + " " + str((d.get("exception") or {}).get("description", "")))[:600])
                elif m == "Log.entryAdded":
                    e = p.get("entry", {})
                    _w(tid, "log.%s %s" % (e.get("level"), str(e.get("text", ""))[:400]))
                elif m == "Network.eventSourceMessageReceived":
                    _w(tid, "sse event=%s id=%s data=%s" % (p.get("eventName"), p.get("eventId"), str(p.get("data", ""))[:400]))
    except Exception as e:  # 탭이 닫히거나 끊기면 조용히 끝(기록기는 러너를 방해하지 않는다)
        _w(tid, "rec_end %s: %s" % (type(e).__name__, str(e)[:120]))


async def main():
    tasks = {}
    end = time.time() + DUR
    while time.time() < end:
        try:
            tabs = json.load(urllib.request.urlopen("http://127.0.0.1:%d/json" % PORT, timeout=3))
        except Exception:
            tabs = []
        for t in tabs:
            if t.get("type") != "page" or "/room/" not in t.get("url", ""):
                continue
            tid = t["id"]
            _urls[tid] = t["url"]
            if tid not in tasks or tasks[tid].done():
                tasks[tid] = asyncio.create_task(_watch(tid, t["webSocketDebuggerUrl"]))
        await asyncio.sleep(0.5)
    for tk in tasks.values():
        tk.cancel()
    await asyncio.gather(*tasks.values(), return_exceptions=True)


asyncio.run(main())
