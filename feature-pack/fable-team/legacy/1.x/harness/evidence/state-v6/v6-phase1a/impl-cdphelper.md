# impl-cdphelper: cdp_helper.py 명시 ws_url 우선 수정

## 변경 diff 요약

파일: `tests/e2e/cdp_helper.py`

3곳 동일 패턴 수정 (라인 404→405, 623→625, 657→660):

```
# Before (bug) — 명시 ws_url을 무시하고 get_tab_ws 재해석 우선
current_ws = get_tab_ws(url_match="realtime") or ws_url

# After (fix) — 명시 ws_url 우선, None/빈 값일 때만 fallback
# 명시 ws_url 우선 — 재해석 금지 (RUNNER_WRONG_TAB 사고 2026-07-03)
current_ws = ws_url or get_tab_ws(url_match="realtime")
```

### 수정 위치

| 함수 | 수정 라인 | 역할 |
|------|-----------|------|
| `_eval_async` | :405 | JS eval — host/guest 탭 구분 |
| `_mouse_click_async` | :625 | trusted mouse click (getUserMedia) |
| `_key_event_async` | :660 | trusted key event (Space/Enter/Arrow) |

### 동일 패턴 미해당 (정상)

- `_insert_text_async` (:676) — `ws_url` 직접 사용, 재해석 없음. 수정 불요.
- `_reload_async` (:440) — `ws_url` 직접 사용. 수정 불요.
- 공개 함수들 (`cdp_eval`, `cdp_mouse_click` 등) — `get_tab_ws(url_match=url_match)` 결과를 ws_url로 넘기므로 정상.

## 콜사이트 계약 확인 (5건)

1. **realtime_multi_e2e.py:537** — `_eval_async(_HOST_WS, "1", 2)` — 캐시된 호스트 ws 명시 전달. 수정 후 _HOST_WS가 우선 사용됨 (정상).
2. **realtime_multi_e2e.py:853** — `_eval_async(ws, js, timeout)` — `_realtime_ws(want_guest)` 리졸버가 host/guest 분리한 ws 전달. 수정 후 해당 ws 우선 (정상).
3. **realtime_multi_e2e.py:901** — `_mouse_click_async(ws, x, y)` — host/guest 분리 ws 명시 전달 (정상).
4. **realtime_multi_e2e.py:938** — `_key_event_async(ws, " ", "Space", 32)` — 명시 ws 전달 (정상).
5. **lecture_multi_e2e.py:100** — `_eval_async(ws, js, timeout)` — lecture 전용 ws 명시 전달 (정상).

## 검증

- `ast.parse`: OK
- `import cdp_helper`: OK
- 구패턴 `get_tab_ws(...) or ws_url` 잔존: 0건
- 신패턴 `ws_url or get_tab_ws(...)` 적용: 3건 (405, 625, 660)
