# ruff: noqa: E401,E702  — 증거 재실행 스크립트(제품 코드 아님)
"""실제 컴포넌트 재생 시험 — Next dev 의 /dev/bubble-replay 에서 높이 계열·computed 줄바꿈·금칙 위반을 잰다.
헤드리스 Chromium(별도 프로필) · 공유 Chrome :9333 0 · 오디오 0.
사용: python3 -I run.py <base_url> <태그> <출력 디렉터리>   예) run.py http://localhost:38381 after out/
"""
import json, sys, pathlib
from playwright.sync_api import sync_playwright

BASE, TAG, OUT = sys.argv[1].rstrip('/'), sys.argv[2], pathlib.Path(sys.argv[3]); OUT.mkdir(parents=True, exist_ok=True)
STATIC = [('source', l) for l in ('ko', 'ja', 'zh-CN', 'zh-TW', 'ar', 'th')] + [('translation', l) for l in ('ko', 'ja', 'zh-CN', 'zh-TW', 'ar', 'th')]
results = {'tag': TAG, 'stream': {}, 'static': {}, 'console_errors': [], 'error_overlay': False}

with sync_playwright() as pw:
  browser = pw.chromium.launch(headless=True)
  for vw in (390, 768):
    ctx = browser.new_context(viewport={'width': vw, 'height': 900}, device_scale_factor=1)
    page = ctx.new_page()
    page.on('console', lambda m: results['console_errors'].append(f'{vw}: {m.text[:200]}') if m.type == 'error' else None)
    page.on('pageerror', lambda e: results['console_errors'].append(f'{vw}: pageerror {str(e)[:200]}'))
    page.goto(f'{BASE}/dev/bubble-replay'); page.wait_for_function('window.__bubbleReplay', timeout=60000)
    labels = page.evaluate('window.__bubbleReplay.labels'); series = []
    for i in range(len(labels)):
      r = page.evaluate('i => window.__bubbleReplay.goto(i)', i); series.append(r); results['error_overlay'] |= r['errorOverlay']
    page.screenshot(path=str(OUT / f'{TAG}-stream-{vw}.png'), full_page=True)
    results['stream'][str(vw)] = series
    for kind, lang in STATIC:
      page.goto(f'{BASE}/dev/bubble-replay?scenario=static&lang={lang}&as={kind}'); page.wait_for_function('window.__bubbleReplay', timeout=60000)
      r = page.evaluate('window.__bubbleReplay.goto(0)'); results['error_overlay'] |= r['errorOverlay']
      results['static'][f'{vw}/{kind}/{lang}'] = r
      if vw == 390: page.screenshot(path=str(OUT / f'{TAG}-static-{vw}-{kind}-{lang}.png'), full_page=True)
    ctx.close()
  results['browser'] = browser.version; browser.close()
(OUT / f'{TAG}-measurements.json').write_text(json.dumps(results, ensure_ascii=False, indent=1))
for vw, series in results['stream'].items():
  hs = [s['height'] for s in series]; changes = sum(1 for a, b in zip(hs, hs[1:]) if a != b)
  print(f'[{TAG}] stream {vw}px 높이 계열 {" ".join(map(str, hs))} · 변화 {changes}회 · 폭 {sorted({s["width"] for s in series})}')
print(f'[{TAG}] console.error {len(results["console_errors"])} · error overlay {results["error_overlay"]} · browser {results["browser"]}')
