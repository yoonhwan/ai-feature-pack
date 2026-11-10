<!-- ledger: design/cfo/GOAL-cfo.md -->
# 인덱스: 매일 Redis 잔액 ↔ PG 재구성 자동 대조 + 닫히지 않은 돈 표식 건수 보고 — 손실이 나면 다음 날 안다 (판정 1519 ①)

- Issue: #773 (Refs — 완료조건 ② 무손실은 판정 162 보류 유지 · 이 카드는 재개 조건 ① «실제 손실 관측»을 잴 수 있게 만든다)
- 제안서: 없음 — 오빠 판정 1519(①: 보류 유지 + 매일 대조·실패 표식 회수부터 · 무손실 재설계·HA 는 손실 관측 뒤)
- 설계: design/cfo/DESIGN-credit-durability-758-773-781-20261013.md §1·§2·§3 ⓒ·§6 (5ff10f661d)
- 근거 문서: origin/main 196edd8d8c — 대조 도구 `scripts/ops/credit_reconstruct_check.py:1-9`(수동 CLI 뿐 · 워크플로 참조 0) · 크론 모양 `.github/workflows/credit-expire.yml`(GATEWAY_URL_CRON + INTERNAL_SECRET curl · 알림은 별도 스텝)
- 상태: 대기 — 판정 1519 ① 의 첫 카드 · 다음 카드 = 대기/cfo-credit-consume-guard-reclaim-1519.md(이 카드 뒤) · spawn `--base origin/main`
- 시험 입력: 격리 Redis 픽스처(`isolated_redis_server`) + 시험 PG · 라이브 dev 1회 실행은 읽기 전용(쓰기 0) · press 0

## 골 원문
병원과 호텔에 판다.
고객사마다 운영툴에서 용어집·지식(RAG)을 관리한다. 생성 시 b2c 베이스 도메인을 공통층으로 깔고 그 위에 고객사 것을 얹는다. 초기 설정은 우리가 넣어준다. 이후에는 고객사 관리자가 직접 등록·수정·관리한다.
통역·전사의 번역 데이터는 우리 서버에서만 처리한다. (chat·STT·TTS는 외부 선택 가능)
작업은 파일로 남아서, 세션이 죽어도 다음 세션이 열어서 잇는다.

## 골좌표
**병원·호텔 계약 체결(1줄)** 「| 1 | 병원·호텔 계약 체결 | 병원·호텔에 계약이 서고 운영된다 |」 — 계약 고객 잔액이 Redis 에만 있고 PG 기록과 어긋나면 다음 날 오빠 슬랙에 뜬다. 닫는 증거: 아래 완료 조건. **완성 전**.

## 배경
- 잔액 권위는 Redis 이고 PG 5표(credit_slots · expirations · adjustments · consumptions · opening_balances)로 재구성하는 읽기 전용 대조 도구가 이미 있다 — 그런데 사람이 손으로 돌릴 때만 돈다.
- 소비·면제 보정은 Redis 를 먼저 깎고 PG 를 뒤에 쓴다. PG 기록이 실패하면 표식 `credit_consume_guard`(TTL −1)가 남는데 이걸 세는 곳이 없다. 보류 스트림 `v5:usage:held`·`tts:usage:held` 도 경보가 없다(`credit:held` 만 매일 건수 경보).
- 그래서 판정 162 의 재개 조건 «실제 손실 관측»이 손실이 나도 켜지지 않는다.

## 구현 범위 (닫힌 목록)
1. 게이트웨이 내부 엔드포인트 1개(INTERNAL_SECRET 보호 · 기존 `internal/expire` 와 같은 모양): 기존 `check_wallet`·`classify` 를 그대로 불러 «증거 보유 지갑» 을 커서 기반 묶음으로 대조 → 응답 = 분류별 카운트 + 확정 불일치 목록(uid 앞 8자리 · 차이 micro) + 다음 커서. ★대조 식·분류를 새로 짓지 않는다★ — 도구의 함수를 import.
2. 같은 응답에 «닫히지 않은 돈 표식» 건수: `credit_consume_guard:*` 중 TTL −1 · `credit_add_cmd` 미봉인 · `credit_expire_pending:*` · `v5:usage:held`·`tts:usage:held`·`credit:held` XLEN · `v5:usage`·`tts:usage` 소비 지연(마지막 커서 뒤 길이 · MAXLEN 2000 대비). SCAN 은 COUNT 묶음 + 7초 상한.
3. 대조가 `refund_reserved`(환불 진행 중 예약분)를 읽지 않는 구멍(`_credit_reconstruct_classify.py:20-29`) — 읽어서 분류에 반영하거나, 환불 진행 중 지갑을 «진행 중» 분류로 따로 센다(어느 쪽인지 산출에 1줄 · 오탐을 불일치로 세지 않음).
4. 크론 워크플로 1개(매일 · `credit-expire.yml` 모양 · 커서가 빌 때까지 반복 호출) + 알림 스텝(확정 불일치 ≥1 또는 표식 건수 > 0 → `OPS_ADMIN_SLACK_WEBHOOK` · 알림 실패는 대조 실패로 오보하지 않음 · continue-on-error 는 알림 스텝만).
5. 시험: RED1 Redis 를 PG 보다 높게 만든 지갑 → 확정 불일치 1 · RED2 TTL −1 소비 표식 1개 → 건수 1 · RED3 환불 예약 중 지갑 → 불일치로 세지 않음 · RED4 묶음 상한 초과 시 커서로 이어짐(빠진 지갑 0) · 변이 RED(재조회 1회 제거 → 일시 차이를 확정으로 셈 · 표식 SCAN 제거 → RED2 실패).
★금지★: Redis 쓰기 0(대조는 읽기 전용) · PG 쓰기 0 · 폴백(PG/Redis 오류를 «일치»나 빈 결과로) 0 — 오류는 raise → 엔드포인트 5xx → 크론 실패 · skip/xfail 0 · 임의 Redis 주입 0(시험은 격리 픽스처).

## ★사전 DA② r1 반영 — 아래가 «구현 범위»에 더해지고 앞 항목보다 우선한다 (판정 원문 evidence/redis-pg-daily-reconcile-1519/DA2-r1-1519-arch26-verdict.txt)★
6. ★구조 먼저(Tidy First · 별도 [structure] 커밋)★: 게이트웨이 이미지에 `scripts/` 가 없다(`docker/gateway.Dockerfile:31-44`). → `check_wallet`·재조회·`classify`·Redis/PG 보조 reader 를 `gateway/domains/credit/reconstruction/` 아래로 옮기고 CLI(`scripts/ops/credit_reconstruct_check.py`)가 그걸 import. 식·분류 알고리즘 변경 0(옮긴 커밋에서 기존 시험 그대로 통과).
7. 연결: PG = 부팅 때 공용 팩토리(`make_async_pool`)로 만든 풀에서 연결을 빌려 기존 `conn` 인자로 주입(지연 생성 `pg_pool.get_pool()` 경로 사용 0) · Redis = `shared.redis.client.get_redis_client()`. 새 원시 클라이언트 0(docs/rules/async_io_and_connections.md).
8. ★오류는 요청 실패다★: 최초 조회·재조회 어느 쪽이든 `*_UNAVAILABLE` 이 하나라도 나오면 그 호출 전체 5xx(정상·장애 지갑이 섞인 묶음도 성공 0) — 지금 CLI 처럼 결과 줄로 바꾸고 성공 종료하지 않는다(`credit_reconstruct_check.py:59-66,150`).
9. ★«진행 중» 지갑은 불일치로 세지 않고 따로 센다★: 아래 중 하나라도 있으면 분류 `IN_FLIGHT`(사유 코드 함께) — 환불 예약분 `refund_reserved` > 0 · 충전/구독 환불 작업 미완료(reclaim 뒤 PG 마감 전 창 · `personal_topup_refund_service.py:42-45`) · 소비 표식 존재(TTL −1 또는 양수 · 면제 보정 포함 · `credit_outage_waive_lua.py:64-69`) · 부분 지급 `personal_grant_applied:*` 의 `v2p|`(`_credit_reconstruct_redis.py:45-51`) · 만료 pending · 미봉인 관리자 추가. ★`IN_FLIGHT` 가 다음 날에도 같은 사유로 남으면 그 지갑은 «닫히지 않은 표식»으로 알림★(하루 넘은 진행 중 = 닫는 사건 실패).
10. ★SCAN 완주 계약★: 표식 SCAN 도 호출마다 «다음 SCAN 커서 · 완료 여부» 를 돌려주고, 크론은 지갑 커서·SCAN 커서 둘 다 끝날 때까지 반복. 응답은 표식 키(uid 앞 8자리 + 종류)를 돌려주고 합산·중복 제거는 크론 쪽(SCAN 은 같은 키를 두 번 줄 수 있음). 부분 결과를 «완료 건수»로 내지 않는다. ★첫 수 = dev 라이브 키 수·패턴별 SCAN 소요 실측(읽기 전용) → 묶음 크기 결정★.
11. ★지갑 커서 = 정렬된 uid keyset★: 모집단 조회를 `ORDER BY user_id` + `user_id > 마지막 완료 uid` 로(지금 ORDER BY 없는 UNION 전체 fetchall · `_credit_reconstruct_pg.py:9-14,35-41`). 실행 중 새로 생긴 증거 지갑은 다음 날 실행 몫(산출에 1줄).
12. ★사용량 스트림 trim 유실 검출★: 소비자 커서가 스트림 첫 항목 id(`XINFO STREAM` first-entry)보다 앞이면 = 읽기 전에 trim 된 사용량 = «유실 관측» 표식(`v5:usage`·`tts:usage` · MAXLEN 2000 · `pulse_consumer.py:67,75`). 남은 길이만 세지 않는다.
13. 시험 추가: 최초/재조회 PG·Redis 장애 → 5xx · 진행 중 사유별 1건씩 → 불일치 0 · `IN_FLIGHT` 이틀 연속 → 알림 · SCAN 중복·빈 페이지·0 아닌 커서·기한 중단 후 재개 · uid 순서 + 실행 중 모집단 변경 → 빠진 지갑 0 · 소비 커서가 trim 된 경우 → 유실 표식 1 · 여러 페이지 합산(마지막 페이지 0건이어도 앞 페이지 발견이 알림에 남음) · 알림 실패가 대조 결과를 바꾸지 않음.

14. ★(r2 major 1) 소비 표식 «존재»만으로 진행 중이라 하지 않는다★: 정상 소비도 PG INSERT 뒤 표식을 24h 남긴다(`credit_consume_record.py:166-172`) → TTL 양수 표식이 있다고 제외하면 실제 손실이 숨는다. 진행 중 = ①TTL −1 표식 또는 ②표식이 가리키는 소비(user_id + idempotency_key)의 PG 행이 없거나 면제 보정 결과가 PG 와 다를 때만. 그 밖의 지갑은 표식이 있어도 정상 대조. TTL 만으로 가르지 않는다(면제 보정은 양수 TTL 유지 · `credit_outage_waive_lua.py:63-69`). — 9번의 «소비 표식 존재(TTL −1 또는 양수)» 문구는 이 14번으로 대체.
15. ★(r2 major 2) 표식 식별자 = 전체 키 기준★: 응답은 표시용 uid 앞 8자리와 별도로 표식 키 전체를 구별하는 안정 식별자(예: 키 해시)를 돌려주고, 크론 중복 제거는 그 식별자로(소비 표식 = user_id + idempotency_key 단위 · `shared/redis/keys.py:238-248`). 같은 지갑·같은 종류·다른 키 2건 = 건수 2. — 10번의 «uid 앞 8자리 + 종류» 는 표시용으로만.
16. ★(r2 major 3) 시험 추가 3★: 정상 PG 행 + 양수 TTL 표식 지갑에 확정 차이 → 불일치 1 · 양수 TTL 면제 보정이 PG 미반영 → 진행 중(정상 봉인과 구별) · 같은 지갑 다른 미봉인 표식 2개 + 같은 키 재등장 → 건수 2.
- 후속(차단 아님 · r2 minor): 12번 «소비자 커서 < 스트림 첫 항목 id» 는 처리 끝난 항목만 trim 된 경우·커서 없음(`"0"` · `usage_billing_consumer.py:90-107`)에도 걸린다 → 보고는 «trim 위험·관측 불가»로 쓰고 «확정 유실»이라 부르지 않는다. 확정 유실 구별은 후속.
> bounded 규칙: 사전 DA② HOLD 2회(r1·r2) → 종이 검토 중단. r2 가 r1 8건 중 5건 닫음 · 남은 3건 = 위 14~16 으로 계약 고정 · 남은 확인 = 구현 뒤 DA⑥(6~16 대조표).

## 7초 룰 (판정 1375)
- 엔드포인트 1회 = «크기 아는 배치» → 시도당 상한 `min(고정비 + 7 s × ceil(지갑수 / 기준량), 70 s)` · 재시도 포함 총 70 s · 재시도는 첫 출력 전 실패만. 기준량(지갑 몇 개 = 7 s)은 dev 실측 1회로 정하고 산출에 값·근거 1줄 — 지어내지 않는다.
- ★호출 1회 총 마감 70 s 안에 재시도·쓰로틀·표식 SCAN 을 모두 포함★(쿼리별 5 s `pg_wallet_event_reader.py:36,118-130` 는 전체 상한이 아니다) · 분할 가능한 조회는 먼저 묶음으로 쪼갠다 · 엔드포인트 내부 예산 < curl `--max-time` ≤ 70 s · Cloud Run 요청 timeout 값을 산출에 1줄(70 s 보다 짧으면 그 값 기준).
- 크론 쪽 curl 도 같은 상한(`--max-time`). 지갑이 늘면 상한을 늘리지 않고 커서 묶음이 늘어난다.
- 지갑 사이 쓰로틀 `_SLEEP_S` 그대로(공유 PG off-peak).

## 부하·메모리
| | 지금 | 뒤 |
|---|---|---|
| 부하 | 0(수동) | 하루 1회 · 지갑당 PG 5표 읽기 + Redis HGETALL 1 + 재조회 시 1회 더 · 표식 SCAN 1회 — 실측(지갑 수 · 총 소요 · PG p95) 산출에 1줄 |
| 메모리 | 0 | 묶음 1개분 사건만 메모리(커서 단위) · 응답 크기 = 카운트 + 확정 불일치 목록 |
| 돈 | 0 | 0(읽기 전용) |

## 완료 조건
① RED1~4 + 13번 시험 + 변이 RED 2 통과 · ①-b 위 6~16 대조표(구현 줄 · 시험 이름) · ② ruff + 관련 pytest rc=0 · ③ dev 라이브 1회 실행(workflow_dispatch · 읽기 전용) 결과 = 분류 카운트 + 표식 건수 표를 카드에 붙임(그 값이 판정 162 재개 조건 ① 의 첫 관측값) · ④ 사전 DA② APPROVE(bounded · codex gpt-6.1-sol low) · ⑤ PR 본문 `Refs #773`.
세트: <40hex> · 시험: <명령> rc=<n> · 이슈: design/cfo/indices/대기/cfo-credit-redis-pg-daily-reconcile-1519.md

## 상태
- base_sha: 50b24ff1689ba9ae398575e05da9066cf8561a78 (spawn 2026-10-13)
- 2026-10-13 — 대기/ 생성 · byz-cfo-arch-claude#26 (판정 1519 · master#80 84282)
- 2026-10-13 16:51 — 대기→진행 · 좌석 byz-cfo-nano-cfo-credit-redis-pg-daily-reconcile-1519#0
- 2026-10-13 17:0x — 사전 DA② r1 HOLD(major 8) → 6~13 반영 · r2(교정 검토 1회) 진행 · byz-cfo-arch-claude#26
- 2026-10-13 17:1x — 사전 DA② r2 HOLD(r1 8건 중 5 닫힘 · 남은 major 3) → 14~16 계약 고정 · bounded 중단 · 남은 확인 = DA⑥ · byz-cfo-arch-claude#26
- 2026-10-13 구현 완료(나노 #0) — 브랜치 nano/cfo-credit-redis-pg-daily-reconcile-1519 · 커밋 511520d140([structure]) · 8e952f4535 · ea0fe98963 · 4e31ee1c64 · push 0
  세트: 4e31ee1c64dc98b8857bbb68a9d04bb423a00843 · 시험: `PAYMENT_MODE=local_mock APP_ENV=local RECON_CHECK_PG_REQUIRED=1 .venv/bin/python -m pytest tests/gateway/unit -k "credit_reconstruct or credit_daily or credit_unclosed or credit_reconcile or shutdown_closes" tests/scripts/test_credit_reconcile_run.py tests/gateway/integration/{test_credit_reconstruct_check_redis,test_credit_reconstruct_tail_loss,test_credit_opening_capture_absent,test_credit_daily_reconcile_pg}.py` rc=0 (127 passed · 통합 4파일은 로컬 일회용 postgres:16) + ruff 변경 파일 통과 + actionlint 통과 · 이슈: design/cfo/indices/대기/cfo-credit-redis-pg-daily-reconcile-1519.md
  ★6~16 대조표 (구현 줄 · 시험 이름)★ — 시험 파일: U=tests/gateway/unit/test_credit_daily_reconcile.py · M=…/test_credit_unclosed_markers.py · E=…/test_credit_reconcile_endpoint.py · S=…/test_main_shutdown_closes_pg_pools.py · R=tests/scripts/test_credit_reconcile_run.py · I=tests/gateway/integration/test_credit_daily_reconcile_pg.py
  | 항 | 구현 | 시험 |
  |---|---|---|
  | 6 구조 | 511520d140 — `gateway/domains/credit/reconstruction/{classify,redis_state,pg_evidence,wallet_check}.py` 로 이동 · scripts 는 옛 경로 재노출+CLI | 기존 `test_credit_reconstruct_*` 59 passed (옮긴 커밋 단독) · 통합 3파일 34 passed |
  | 7 연결 | `gateway/main.py` lifespan `make_async_pool("SUPABASE_DB_URL", read_only=False)` + `pg_readers.pooled_readers` 가 풀에서 대여 · `get_pool()` 지연 경로 0 · Redis=`get_redis_client()` | S `test_credit_reconcile_pool_is_opened_at_boot_via_factory_and_closed_at_shutdown` · E `test_pool_not_opened_at_boot_is_5xx_not_lazy_pool` · I `test_reconcile_page_runs_through_pooled_connections` |
  | 8 오류=요청 실패 | `daily_reconcile.reconcile_page` 가 `*_UNAVAILABLE` 집계 → `credit_reconcile_internal.py` 503 (섞인 묶음도) | U `test_pg_error_on_first_or_reread_is_unavailable_never_equal[1,2]` · `test_redis_error_is_unavailable` · E `test_unavailable_wallets_raise_5xx_even_if_batch_is_mixed` |
  | 9 진행 중 | `in_flight.py`(redis_reasons·consume_reasons) + `pg_evidence.uids_with_open_refund_job` → 분류 `IN_FLIGHT`+사유 · 하루 넘음 = `credit_reconcile_run.alert_lines` | U `test_each_in_flight_reason_is_not_a_mismatch`(7사유: refund_job·expire_pending·partial_grant·add_unsealed·consume_unsealed·consume_unrecorded·waive_unrecorded) · `test_red3_refund_reserved_is_in_flight_not_mismatch` · R `test_in_flight_two_days_in_a_row_alerts_but_first_day_does_not` |
  | 10 SCAN 완주 | `unclosed_markers.scan_markers`(토큰 `종류:커서`·걸음 상한·7초) · 응답=표식 id+종류+uid8 · 크론이 단계별 cursor 완주+id 중복 제거 | M `test_scan_resumes_across_calls_without_dropping_markers` · `test_empty_page_with_nonzero_cursor_keeps_going` · `test_duplicate_key_from_scan_is_returned_twice_for_cron_to_dedupe` · R `test_cursors_are_followed_until_empty_for_every_phase` · `test_never_ending_cursor_fails_instead_of_looping` |
  | 11 uid keyset | `pg_evidence.evidence_user_ids_page`(`ORDER BY user_id`·`user_id > after`) · 실행 중 새 증거 지갑=다음 날 몫 | I `test_keyset_pages_cover_every_wallet_once_in_uid_order` · U `test_red4_cursor_pages_cover_every_wallet_once` · `test_population_change_mid_run_skips_no_existing_wallet` |
  | 12 trim | `unclosed_markers.usage_stream_report`(커서<첫 항목·커서 없음 → `trim_risk` — «trim 위험·관측 불가», 확정 유실 아님) | M `test_consumer_cursor_behind_first_entry_is_trim_risk` · `test_streams_report_held_lag_and_trim_risk` |
  | 13 시험 추가 | 위 + 알림 분리 | 장애 5xx=8행 · 진행 중 사유별=9행 · 이틀 연속=R · SCAN 중복·빈 페이지·0 아닌 커서·재개=10행 · 모집단 변경=11행 · trim=12행 · 여러 페이지 합산 R `test_multi_page_sum_last_page_zero_keeps_earlier_finding` · 알림 실패 R `test_alert_failure_cannot_change_reconcile_result` |
  | 14 양수 TTL | `consume_guards.guards_for_uids` + `in_flight.consume_reasons`: TTL −1 · PG 행 없음 · 면제 가드인데 PG waived_amount 0 만 진행 중 | U `test_positive_ttl_guard_with_matching_pg_row_does_not_hide_a_real_mismatch` · `test_sealed_waive_matching_pg_is_not_in_flight` |
  | 15 전체 키 id | 표식 id = sha1(전체 키)[:16] (uid8 은 표시용) · 크론 id 로 중복 제거 | M `test_two_unsealed_keys_of_same_wallet_have_distinct_ids` · R `test_markers_deduped_by_full_key_id_but_same_wallet_two_keys_count_two` |
  | 16 시험 3 | — | 정상 PG 행+양수 TTL+확정 차이→불일치 1 = U `…does_not_hide_a_real_mismatch` · 양수 TTL 면제 PG 미반영→진행 중 = U `…[waive_unrecorded]` vs 정상 봉인 U `…sealed_waive…` · 같은 지갑 미봉인 2+같은 키 재등장→2 = M `…distinct_ids` + R `…deduped…` |
  변이 RED 실행 확인: 재조회 제거→U 2건 실패 · TTL−1 사유 제거→U 1건 · 면제-PG 대조 제거→U 1건 · 표식 SCAN 제거→M 3건 · trim 검출 제거→M 1건 (각 복원 뒤 전부 통과).
  3번 선택: «읽어서 분류에 반영» — `HMGET_FIELDS` 끝에 `refund_reserved` 추가 · `classify` 가 `REFUND_IN_PROGRESS`(비교 안 함) → 일일 대조에서 `IN_FLIGHT`(사유 refund_reserved)로 센다.
  7초 룰: 지갑 묶음 20개(기준량 **잠정 20** · 고정비 7 s 잠정) → 묶음 마감 `min(7 + 7×ceil(n/20), 70)` = 14 s · 표식 호출 7 s · 러너 호출 `urlopen(timeout=70)`+재시도 1회(첫 출력 전) · Cloud Run `byz-agents-gateway-dev` 요청 timeout **300 s**(gcloud 실측) > 70 s. ★기준량·고정비는 PG 지갑당 시간 실측 전 잠정값★ — 그 실측은 사전 DA APPROVE 이후 PG 읽기(판정 922)로만 가능해 미실측.
  dev Redis 읽기 실측(터널 38371 내 것만 열고 닫음): DBSIZE 5247 · `credit_consume_guard:*` 134(TTL −1 0) · `credit_add_cmd:*` 0 · `credit_expire_pending:*` 0 · `user_credits:*` 231 · `personal_grant_applied:*` 46 · SCAN count=500 전체 ≈0.8 s(왕복 70 ms) · 키별 TTL 개별 호출 134건 9.5 s → 파이프라인 사용 · XLEN `v5:usage` 1850/2000 · `tts:usage` 768 · `v5:usage:held` 1 · 그 외 held 0 · 두 소비 커서 모두 첫 항목 뒤(trim 위험 0).
  남은 완료조건: ③ dev 라이브 1회(머지 후 workflow_dispatch — master) · ④ DA⑥(6~16 대조표) · ⑤ PR `Refs #773`. press 필요: 없음.
- 2026-10-13 DA⑥ r1 HOLD 6건 교정(나노 #0) — 커밋 9105c17a54 · push 0
  세트: 9105c17a5435df7e12b69fad4883afd13a4f3074 · 시험: `PAYMENT_MODE=local_mock APP_ENV=local .venv/bin/python -m pytest tests/gateway/unit -k "credit_reconstruct or credit_daily or credit_unclosed or credit_reconcile or shutdown_closes" tests/scripts/test_credit_reconcile_run.py tests/gateway/integration/{test_credit_reconstruct_check_redis,test_credit_reconstruct_tail_loss,test_credit_opening_capture_absent,test_credit_daily_reconcile_pg}.py` rc=0 (139 passed · 통합은 로컬 일회용 postgres:16 · skip 0) + ruff·actionlint 통과 · 이슈: design/cfo/indices/대기/cfo-credit-redis-pg-daily-reconcile-1519.md
  | DA⑥ # | 고친 곳 | 막는 시험 |
  |---|---|---|
  | 1 URL | 러너 `RECONCILE_PATH="/api/v1/internal/credit-reconcile/daily"` (실제 등록 경로 — `create_app().routes` 로 실측) | E `test_runner_url_is_a_post_route_of_the_real_app` (앱 실제 라우트 기준) |
  | 2 총 마감 | `shared/config/external_call.py` 에 `BATCH_CEILING_S=70.0` 신설 · 러너·`daily_reconcile` 이 거기서만 파생(70 리터럴 0) · 시도마다 «남은» 시간만 · 4xx 재시도 0 · 기준량 20·고정비 7 s «잠정» 주석 유지(dev 첫 실행 실측 전 머지 0) | R `test_http_post_second_attempt_gets_only_the_remaining_budget` · `…stops_when_budget_is_gone_and_does_not_retry_4xx` · `test_time_constants_come_only_from_shared_external_call` · U `test_deadline_constants_derive_from_shared_external_call` |
  | 3 면제액 | 가드 v4 마지막 칸 면제액 == PG `waived_amount` 값 비교, 다르면 `waive_unrecorded` | U `test_waive_guard_amount_must_equal_pg_amount_not_just_nonzero`(10↔4 → 1) · `test_sealed_waive_matching_pg_is_not_in_flight`(4↔4 → 0) · `[waive_unrecorded]` |
  | 4 쌍 지속 | 진행 중 항목에 `pairs`{사유→(지갑,사유) id} · 러너 상태 파일 = 쌍 id · 지속 = 쌍 단위 | R `test_persistence_is_per_wallet_reason_pair_not_whole_reason_set`([환불,소비미봉인]→[환불] ⇒ 환불 1건) · `…two_days_in_a_row…` |
  | 5 증거 | ①표식 SCAN 기한 만료 계약 = «완료한 걸음까지 + 다음 토큰(미완료)», 진행 0 이면 TimeoutError · 지갑 묶음 만료 계약 = raise(5xx → 크론 실패) ②③ | M `test_deadline_expiry_returns_checkpoint_and_resume_loses_nothing` · `…without_any_progress_raises` · U `test_wallet_page_deadline_expiry_raises_not_partial_ok` · ② U `test_redis_reread_failure_is_unavailable_not_confirmed_or_equal` · ③ R `test_workflow_only_the_alert_send_step_is_continue_on_error`(YAML 구조: 알림 전송 스텝만 continue-on-error·대조 스텝은 아님) + 기존 `test_alert_failure_cannot_change_reconcile_result` |
  | 6 skip | 통합 시험 `skipif`·REQUIRED 분기 제거 — docker/PG 없으면 «실패» (integration 마커로 고른 실행) | I 3건(skip 0) |
  변이 RED(교정분): URL 변경→E 1 · 시도별 새 예산→R 2 · 면제액 0 검사로 되돌림→U 2 · 지속 판정 제거→R 2 (각 복원 뒤 41 passed).

- 완료 조건 ③ 닫힘 — dev 1회 실측(지갑 544·대조 68초·확정 불일치 0 · REFERENCE_WALLETS=20·PAGE_FIXED_S=7 그대로 · 꼬리 미측정 한계는 evidence/redis-pg-daily-reconcile-1519/dev-first-run-20261013.md)
- 세트: 7e10ea56c0e856d63b584c63bb14ffbb62e565f1 · 시험: dev workflow_dispatch run 38374992014 success rc=0 · 이슈: design/cfo/indices/진행/cfo-credit-redis-pg-daily-reconcile-1519.md
- 2026-10-16 — 좌석 없음 → 대기 복귀 · 남은 것: 세트 7e10ea56c0 가 원격(origin/main·docs/cfo-main) 조상 아님·병합 PR head 와도 불일치 — 랜딩 확인 또는 재착수 필요 · 이동 근거 카드 cfo-in-progress-cards-seat-reconcile
- 2026-10-16 — 완성(대조): PR #1464 · main 6c79a98cdc (cfo-waiting-cards-merged-reconcile · 표 design/cfo/evidence/waiting-merged-reconcile/TABLE.md)
