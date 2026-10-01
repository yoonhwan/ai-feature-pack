# Nano item5 U1 r2 결과 — DA r8 결함 4건 수정 (tick.py)

- 세션: `ft-airag-nano-r1#0` · 모델: claude-sonnet-5-5[1m]
- 골의 어느 축인가: A03 — A02 트리 5순위(C12·C07) — 상시 서비스 틱 래퍼 `tick.py` 의 값 비노출·로그 경계 결함 수정 → DA major 0.
- 변경: `feature-pack/rag-consumer/src/airag_consumer/tick.py` · `tests/test_tick.py`. **코어(`cli.py`·`runtime.py`) 무변경** — 모든 수정이 tick 쪽 경계에서 가능했다. 커밋·push 안 함. 실제 op·1Password·운영 경로·launchd 미접촉(합성 스텁·tmp), 키 값 미출력.
- pytest (`feature-pack/rag-consumer`): `233 passed in 12.20s` (기준선 228 + 신규 5, 기존 10 테스트 유지)

## 대조 — DA r8 설명 4건 모두 코드와 일치

### R8-M1 — 오류 코드·구성요소 출력으로 값 노출
- 원인: ①CLI 는 예외 메시지가 `[A-Z0-9_:.~-]{1,160}` 형태면 `error.code` 로 그대로 내보내고, tick 의 두 번째 정규식도 형태만 확인해 64자 대문자 hex(=키 형태)를 통과시킨 뒤 stdout JSON 과 날짜 로그에 기록했다. ②`cli.main(stdout=, stderr=)` 는 CLI 자신의 출력만 받으므로, 같은 프로세스의 구성요소가 `print`/`sys.stderr.write`/fd 직접 쓰기로 낸 출력은 그대로 launchd 로그로 갔다.
- 수정(코드): `_safe_code` — 형태가 «값이 실릴 수 없는 모양»일 때만 통과(언더스코어로 나눈 단어가 24자 이하이고, 언더스코어를 지운 문자열에 16자 이상 hex 연속이 없을 것). 아니면 `RUNTIME_FAILED`. 대신 CLI 가 이미 내보내는 `error.type`(예외 클래스 이름, 같은 방식으로 검사)을 로그·출력의 `type` 필드로 추가해 진단 가능성 유지. `tick.py` `_safe_code`·`_error_fields`·`TickError.kind`.
- 수정(구성요소 출력): `_discard_component_output` — 패스 동안 `sys.stdout/err` 를 메모리 버퍼로, fd 1·2 를 `/dev/null` 로 돌렸다가 `finally` 에서 복원. Python 수준·fd 수준 출력 모두 폐기(진단용 출력도 함께 사라지는 의도된 선택: 값 비노출 우선). `tick.py` `_discard_component_output`.
- 추가 테스트: `test_key_shaped_error_text_never_reaches_output_or_log`(키 형태 예외 → exit 40, 출력·로그에 없음, `code=RUNTIME_FAILED`·`type=RuntimeError`) · `test_component_output_is_discarded_at_process_level`(`print`·`sys.stderr`·`os.write(1/2)` marker 4개가 `capfd` 에 없음, JSON 요약은 정상).
- Red: 로그·stdout 의 `code` 에 키 형태 문자열이 그대로 남음 / 네 marker 모두 프로세스 stdout·stderr 에 출력.

### R8-M2 — 로그·락 심볼릭 링크
- 원인: `append_log` 가 일반 `open("a")`·`stat()` 라 symlink 를 따라 log-dir 밖 파일에 append, `tick.lock` 도 `open("a")` 로 파일 형식 검증 없음.
- 수정: `_open_regular` — `O_NOFOLLOW|O_NONBLOCK`(특수 파일 대기 방지)로 열고 `fstat` 이 일반 파일이 아니면 거부, 새 파일은 0600(umask 의존 제거 방향). 로그는 이 함수로만 열고(거부 시 기존 `log_write_failed` 경로 — 틱 결과는 유지), 락은 거부 시 `config_error`/`LOCK_FILE_UNSAFE`. 로그 디렉터리는 `mkdir(mode=0o700)` 후 symlink·비디렉터리면 `LOG_DIR_UNSAFE`. 오래된 로그 prune 의 `unlink` 는 파일별 `OSError` 무시(링크 자체만 지움). `tick.py` `_open_regular`·`append_log`·`main`.
- 추가 테스트: `test_symlinked_log_or_lock_is_refused_and_new_files_are_private` — 날짜 로그 symlink 면 외부 파일 불변+`log_write_failed`, 락 symlink 면 exit 20+외부 파일 불변, `umask(0)` 에서 새 디렉터리 0700·새 파일 0600.
- Red: symlink 대상(log-dir 밖 파일)에 JSON 줄이 append 됨.

### R8-m1 — 로그 상한
- 원인: 회전 판단이 «현재 크기 > 상한» 이라 정확히 상한이면 다음 줄이 상한을 넘겨 쓰인 뒤에야 회전.
- 수정: 쓰기 전에 «현재 크기 + 새 줄 UTF-8 바이트 > 상한» 이면(그리고 크기>0) 먼저 `.1` 로 회전. 같은 `append_log`. 
- 추가 테스트: `test_log_is_rotated_before_a_line_would_cross_the_cap`(정확히 1,000,000B → `.1` 이 1,000,000B, 새 파일은 새 줄만). 기존 `test_log_rotation_caps_size_and_prunes_old_days` 유지.
- Red: 회전 안 됨(`.1` 없음).

### R8-m2 — op 자식 env 상속
- 원인: 저장소 키 3개·알려진 OP 변수만 제거하는 차단목록 방식이라 다른 `*_KEY_HEX`·API 자격 변수가 값 그대로 상속.
- 수정: 허용목록 `OP_ENV_ALLOWLIST = (PATH, HOME, USER, LOGNAME, LANG, LC_ALL, LC_CTYPE, TMPDIR)` + 서비스 계정 토큰만. `tick.py` `OP_ENV_ALLOWLIST`·`load_keys`. 참고: 프록시 변수(`HTTPS_PROXY` 등)·`SSL_CERT_*` 는 URL 에 자격이 실릴 수 있어 의도적으로 제외했다. 실제 `op` 가 필요로 하면 허용목록에 이름을 추가하는 사용자 판정 사항.
- 추가 테스트: `test_op_child_environment_is_an_allowlist` — 스텁 `op` 가 받은 환경 변수 «이름»만 기록(값 없음)해 `PATH`·`HOME`·`OP_SERVICE_ACCOUNT_TOKEN` 은 있고 `OTHER_RUNTIME_KEY_HEX`·`OP_EXTRA_SECRET`·`SOME_API_TOKEN`·`OP_SESSION_*`·`AIRAG_MEMORY_API_KEY`·프로필/참조 키 변수는 없음을 확인.
- Red: 위 변수들이 op 자식 환경에 포함.

## 알려진 한계
- 템플릿의 `launchd.out.log`/`launchd.err.log`(plist 가 지정하는 launchd 파일)는 tick 의 크기 상한·prune 대상이 아니다(DA 보고서가 명시한 범위). 이제 구성요소 출력이 폐기되므로 이 두 파일에는 틱 JSON 한 줄 정도만 쌓이지만 자동 회전은 구현하지 않았다.
- 실제 `op`·실제 launchd 로드는 실행하지 않았다(합성 스텁).
- 로그 디렉터리의 «상위» 경로 symlink 는 검사하지 않는다(leaf 만).

## 변경 파일
- `feature-pack/rag-consumer/src/airag_consumer/tick.py` · `feature-pack/rag-consumer/tests/test_tick.py` (이전 U1 산출물과 함께 아직 미추적)
