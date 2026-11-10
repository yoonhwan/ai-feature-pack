# impl-runner-hostws: Host WS Registry

## Changes (2 files)

### tests/e2e/realtime_multi_e2e.py
1. **`_HOST_WS` module-level variable** (line ~580): `str | None = None`, guest registry `_GUEST_WS_BY_TOKEN` 와 대칭.
2. **`_register_host_ws(ws)` helper** (line ~585): global 에 ws 저장 + stderr `host_ws_registered` 로그.
3. **`_realtime_ws(want_guest=False)` registry-first** (line ~547): `_HOST_WS` 있으면 `_eval_async("1")` 생존 확인 후 반환 (path=registry). 사망 시 초기화 + enumerate 폴백 (path=enumerate). want_guest=True 경로 무변경.
4. **`host_enter()` 등록** (line ~1966, ~1978): `_realtime_ws(False)` 성공 시 `_register_host_ws(_hw)` 호출 (두 success path 모두).
5. **`_cleanup_room_tabs()` 초기화** (line ~3435): `_GUEST_WS_BY_TOKEN.clear()` 직후 `_HOST_WS = None`.

### tests/e2e/multi_realtime_corpus/lib/dialogue_runner.py
6. **`_ensure_single_armed` 사전 어설션** (line ~34): host 체크 직전 `rt._HOST_WS is None` 이면 stderr 경고 `single_armed_blind host_ws=None — disarm 검증 불가` (동작 변경 없음, 가시화만).

## Registry coverage — _realtime_ws(want_guest=False) callsites (18)

All callsites below benefit from registry (enumerate 생략):

| Line | Context |
|------|---------|
| 1966 | host_enter — first success check (registers) |
| 1978 | host_enter — retry success check (registers) |
| 1996 | host_connect |
| 2025 | host_issue_qr retry loop |
| 2373 | _speak_cycle — pending latch listener |
| 2414 | _poll_self_bubble — pending indicator |
| 2416 | _poll_self_bubble — listener stamp |
| 2608 | _speak_simultaneous |
| 3110 | _run_ptt_rapid_tts_serial |
| 3604 | _run_host_only |
| 3732 | _run_ptt_multi_utterance |
| 3821 | _run_toggle_nospeak |
| 3866 | _run_multi_round |
| 4310 | _run_cross_lang_3way |
| 4551 | _run_ptt_independence |
| 4680 | _run_reconnect_rejoin |

Plus indirect calls via `_eval(js, want_guest=False)`, `_is_recording(False)`, `_is_connected(False)`, `_finalized_count(False)`, `_read_last_bubble(False)`, `_read_last_other_bubble(False)`, `_pending_indicator_visible(False)`.

## Verification
- ast.parse: 2/2 OK
- Module-level symbols: `_HOST_WS`, `_register_host_ws`, `_GUEST_WS_BY_TOKEN` confirmed
- No product code (clients/web, gateway, worker) modified
