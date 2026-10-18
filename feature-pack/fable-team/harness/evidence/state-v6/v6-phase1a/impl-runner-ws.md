# impl-runner-ws — RUNNER_WRONG_TAB fix
status: IMPLEMENTED

## 변경 (파일별 diff 요약)

### tests/e2e/realtime_multi_e2e.py (1 file, 3 insertion points)

1. **`_GUEST_WS_BY_TOKEN` registry** (line ~573): Module-level `dict[str, str]` — `token → webSocketDebuggerUrl` 캐시. `guest_enter_token` 성공 시 등록, `_cleanup_room_tabs` 시 초기화.

2. **`_realtime_ws_by_token()` 수정** (line ~579): Registry-first path 추가.
   - 캐시 히트 → `_eval_async(ws, "1", 2)` 생존 확인 → 성공 시 그대로 반환(CDP /json 재열거 생략)
   - 캐시 히트 but ws 사망 → 레지스트리에서 제거 + 기존 enumerate 폴백
   - 캐시 미스 → 기존 enumerate 경로(동작 보존)
   - 양쪽 경로 모두 `path=registry|enumerate` + `token` + `target/ws` stderr 1줄 계측 로그

3. **`guest_enter_token()` 등록** (line ~2273): `_wait_connected_tok` 성공 후, `_realtime_ws_by_token(token)` 1회 호출해 ws 확보 → `_GUEST_WS_BY_TOKEN[token] = ws` 등록.

4. **`_cleanup_room_tabs()` 초기화** (line ~3382): 함수 진입 시 `_GUEST_WS_BY_TOKEN.clear()` — 탭 제거와 동시에 stale ws 잔류 방지.

### tests/e2e/multi_realtime_corpus/lib/dialogue_runner.py (0 changes)
`guest_enter_token` 반환 시그니처(str|None) 무변경. `_speak_cycle_tok`은 내부에서 `_realtime_ws_by_token` 경유 → 레지스트리 자동 수혜. 무변경이 최소 diff.

## 방식 (레지스트리 — 반환 시그니처 무변경이 더 작은 diff)

## 검증 결과
- `ast.parse` 문법 검증: realtime_multi_e2e.py ✅, dialogue_runner.py ✅
- basedpyright 진단: 신규 0건 (기존 pre-existing generic type arg warnings만)
- `_real_click_tok`, `_is_recording_tok`, `_eval_tok` 등 모든 token 계열 함수는 `_realtime_ws_by_token` 경유 확인 → 레지스트리 자동 수혜
- `_ensure_single_armed` (dialogue_runner.py): `rt._is_recording_tok`/`rt._real_click_tok` 사용 → 자동 수혜, 무변경
