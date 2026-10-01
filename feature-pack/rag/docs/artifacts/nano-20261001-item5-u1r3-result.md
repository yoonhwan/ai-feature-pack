# Nano item5 U1 r3 결과 — DA r9 결함 4건 수정 (tick.py)

- 세션: `ft-airag-nano-r1#0` · 모델: claude-sonnet-5-5[1m]
- 골의 어느 축인가: A03 — A02 트리 5순위(C12·C07) — 상시 서비스 틱 래퍼 `tick.py` 의 값 비노출·로그 경계 잔존 결함 → DA major 0.
- 변경: `feature-pack/rag-consumer/src/airag_consumer/tick.py` · `tests/test_tick.py`. 코어 무변경. 커밋·push 안 함. 실제 op·1Password·운영 경로·launchd 미접촉(합성 스텁·tmp), 키 값 미출력.
- pytest (`feature-pack/rag-consumer`): `239 passed in 14.89s` (기준선 233 + 신규 6, 기존 15 테스트 유지)

## R9-M1 — 짧은 예외 값 통과 · 캐시된 stream 버퍼
- 원인(DA 설명과 일치): ①r8 의 «형태 휴리스틱»은 단어 24자 이하·hex 16연속 없음이면 임의 예외 메시지도 코드로 믿었다. ②`_discard_component_output` 은 fd 를 복원한 «뒤»에 진입 전부터 보관된 `sys.stdout/stderr` 객체의 보류 버퍼가 flush 되어 marker 가 출력됐다.
- 수정(코드): 형태 대신 «이 소프트웨어가 실제로 내는 코드 목록»만 허용 — `_known_codes()` 가 `airag_consumer`(와 가능하면 `airag`) 소스의 대문자 문자열 리터럴을 수집(`lru_cache`)하고 `_safe_code` 는 그 목록에 있는 값만 통과, 나머지는 `RUNTIME_FAILED`. 예외 타입 이름은 기존대로 `type` 필드. `tick.py` `_known_codes`·`_safe_code`.
- 수정(버퍼): 진입 시 원래 `sys.stdout/stderr` 를 보관하고, 종료 `finally` 에서 «fd 를 복원하기 전에» 보관 객체를 flush(그 시점 fd 1·2 는 `/dev/null` 이므로 보류분이 폐기됨). 정상 종료·예외 두 경로 동일. `tick.py` `_discard_component_output`.
- 테스트: `test_short_error_value_is_not_trusted_as_a_reason_code`(짧은 합성 값 → `RUNTIME_FAILED`+`type=RuntimeError`, 출력·로그에 없음; 기존 `test_runtime_failure_is_reported_by_code_only` 에 «실제 코드는 그대로 보고»를 확인하는 단언 추가) · `test_buffered_component_output_is_flushed_into_the_discard_window[False/True]`(버퍼링된 fd 1·2 스트림을 보관한 뒤 write, 정상·예외 종료 모두 `capfd` 에 marker 없음).
- Red: 짧은 값이 `code` 로 출력·로그에 남음 / 두 경로 모두 marker 가 복원 뒤 출력됨.

## R9-M2 — 거부한 log-dir 로 오류 로그 쓰기·prune
- 원인: `log_dir` 변수를 검증 «전»에 대입해, `LOG_DIR_UNSAFE` 로 거부한 뒤에도 마지막 오류 로깅이 같은 경로로 `append_log`(쓰기·회전·prune)를 호출.
- 수정: log-dir 검증(mkdir 0700·symlink/비디렉터리 거부)을 config 확인보다 앞에 두고, 검증을 통과한 뒤에만 `log_dir` 에 대입 — 쓰기·회전·prune 는 이 «검증된 같은 디렉터리» 에만 일어난다. 검증 전/실패 시에는 stderr 에 값 없는 한 줄(`tick log_unavailable`)만. `tick.py` `main`.
- 테스트: `test_rejected_log_dir_is_never_written_or_pruned`(log-dir 이 symlink → exit 20, op 미호출, 대상 디렉터리의 기존 로그 내용 불변·오래된 로그 존속·새 파일 없음). Red: 대상 로그에 오류 줄이 append 되고 오래된 로그가 삭제.

## R9-m1 — 출력 폐기 준비 실패 시 복제 fd 누수
- 원인: `os.dup` 두 번과 `/dev/null` open 이 `try` 앞에 있어, open 실패 시 복제 fd 가 해제 경계 밖에 남음.
- 수정: 자원 확보(dup·dup·open) 전부를 `try` 안으로 옮기고 `finally` 가 «확보된 것만» 복원·close. `tick.py` `_discard_component_output`.
- 테스트: `test_discard_setup_failure_does_not_leak_duplicated_fds`(`os.open(devnull)` 만 EMFILE 로 실패시키고 dup 이 만든 fd 가 모두 닫혔는지 확인). Red: 복제 fd 2개 열림.

## R9-m2 — 부분 쓰기를 성공으로 처리
- 원인: `os.write` 반환 바이트 수를 검사하지 않음.
- 수정: 전부 쓸 때까지 반복하고, 0 바이트 이하면 `OSError` → 기존 `log_write_failed` 경계. `tick.py` `append_log`.
- 테스트: `test_partial_log_writes_are_completed_or_reported`(한 번에 5바이트만 쓰는 `os.write` 에서도 줄이 완전히 기록됨, 0 반환이면 `OSError`). Red: 불완전한 줄이 성공으로 반환.

## 남은 사실 (이번 범위 밖, DA 보고서의 운영 판단)
- op 자식 환경 허용목록이 `HTTPS_PROXY`·`SSL_CERT_*` 를 뺀다. `op` 가 그 변수에 의존하는 환경이면 키 로딩이 exit 30 으로 실패하고 다음 틱도 같다. 이 호스트에서 필요한지는 실제 `op` 를 호출하지 않아 판단하지 않았다 — U2 활성화 단계에서 필요한 변수를 정해 `OP_ENV_ALLOWLIST` 에 추가하는 사용자 판정 사항.
- 로그 디렉터리의 상위 경로 symlink 미검사, launchd.out/err 자동 회전 없음(이전 결과와 동일).

## 변경 파일
- `feature-pack/rag-consumer/src/airag_consumer/tick.py` · `feature-pack/rag-consumer/tests/test_tick.py` (U1 산출물과 함께 아직 미추적)
