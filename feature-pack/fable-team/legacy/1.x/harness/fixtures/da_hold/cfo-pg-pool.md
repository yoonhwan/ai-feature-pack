<!-- ledger: design/cfo/GOAL-cfo.md -->
# 인덱스: gateway/infrastructure/db/supabase_pg.py 풀이 PG 풀 1580 이전 «옛 모양»(대여 전 확인 없음 · 끊긴 상대 감지 없음 · 문장 상한 없음 · 지연 생성)이라 죽은 연결을 내줘 SSL eof → 503 이 같은 모양으로 재발할 수 있다 — 1580 공용 팩토리·수명 소유자로 옮긴다 (PG 풀 카드 완료 조건 ⑥)

- Issue: #773 (Refs) · 담당 팀: CFO
- 제안서: 없음 — PG 풀 카드(진행/cfo-gateway-pg-pool-stale-ssl-1580.md) 구현 범위 8 «옛 모양 풀 2곳» 분리분
- 근거 문서: 세트 f02bd15440 기준 gateway/infrastructure/db/supabase_pg.py — AsyncConnectionPool(min_size=1 · max_size=4 · timeout=connect · kwargs connect_timeout 만) · check 없음 · DEAD_PEER_GUARD 없음 · statement_timeout 없음 · 첫 호출 때 지연 생성(get_pool 이 풀이 없으면 만듦). DSN = SUPABASE_DB_URL. 용도 = 운영자 권한 조회(is_internal_operator · get_platform_role) — 인증 의존(gateway/infrastructure/auth/deps.py)이라 죽은 연결 1번이 요청 전체 503.
- 상태: 대기 — PG 풀 1580 랜딩 뒤(공용 팩토리 키워드 3개 · pg_pool 수명 소유자 모양이 그 카드에서 생김)
- 시험 입력: 격리 postgres 통합 시험 + 단위 · press 0 · 운영 PG 쓰기 0

## 골 원문
병원과 호텔에 판다.
고객사마다 운영툴에서 용어집·지식(RAG)을 관리한다. 생성 시 b2c 베이스 도메인을 공통층으로 깔고 그 위에 고객사 것을 얹는다. 초기 설정은 우리가 넣어준다. 이후에는 고객사 관리자가 직접 등록·수정·관리한다.
통역·전사의 번역 데이터는 우리 서버에서만 처리한다. (chat·STT·TTS는 외부 선택 가능)
작업은 파일로 남아서, 세션이 죽어도 다음 세션이 열어서 잇는다.

## 골좌표
**병원·호텔 계약 체결(1줄)** 「| 1 | 병원·호텔 계약 체결 | 병원·호텔에 계약이 서고 운영된다 |」 — 계약 고객 요청 경로가 죽은 PG 연결 때문에 503 으로 떨어지지 않는다. 닫는 증거: 아래 완료 조건. **완성 전**.

## 배경
PG 풀 카드(1580)는 «결제·도메인 풀 1곳» 만 고쳤다 — 완료 표현도 «gateway 전체 재발 제거» 가 아니다(그 카드 구현 범위 8). 같은 DSN 을 쓰는 supabase_pg 풀은 옛 모양 그대로라 죽은 backend 를 내주는 같은 결함이 남는다. 이 풀은 운영자 권한 조회(인증 의존)에 쓰여, 죽은 연결 1번이 그 요청 전체를 503 으로 만든다. 1580 이 만든 공용 팩토리·수명 소유자 모양을 그대로 옮기는 단위다.

## 구현 범위 (닫힌 목록 · 1580 과 같은 모양)
1. 첫 수(읽기만): 호출자 전수 표(auth/deps.py · organizations 서비스 4 · credits·secrets 라우트 · session_knowledge_scope · main.py) · 지금 timeout·재시도 값 · 이 풀이 같은 DSN 연결 예산(대기/cfo-pg-connection-budget-revision-overlap-1580b.md)에 주는 몫.
   - [DA② r1 원문 반영] 호출자 표에 test_concierge_voice_flag._fake_pg와 test_main_shutdown_closes_pg_pools.lifespan_stubs를 포함한다. _get_pool→get_pool 변경 시 패치 대상도 함께 갱신한다. lifespan 단위 픽스처는 supabase_pg.open_pool을 명시적으로 대역 처리하고 별도 시험에서 실제 open 배선을 검증한다. 독립 실 PG 진입점은 pool_scope로 열고 닫는다. 확인되지 않은 스크립트·CLI 호출자는 발견 없음으로 기록한다. 호출자 표에는 상한 유지(max 4)와 상시 연결 증가(lifespan 전환으로 미사용 프로세스도 min_size=1 을 미리 엶)를 구분해 적는다.
2. 공용 팩토리(shared/db/pg_pool_factory.py)로 생성 — check + dead_peer_guard=True + statement_timeout_ms=7000(배치 경로가 있으면 1580 의 extend_statement_timeout + batch_deadline 그대로).
   - [DA② r1 원문 반영] 대여 대기 timeout=3.0 유지. 생성한 풀에 1580의 _bound_borrow를 적용하여 대기+check 합계 시도 1회를 7초로 제한한다. 시간 초과·호출자 취소 뒤 늦게 반환된 연결은 반드시 반납한다. RED5의 포화·느린 check·취소 삼킴·늦은 반환 누수 시험을 supabase_pg에 적용한다. 배치 문구 정정: 지금 조회 두 개는 단건 SELECT 라 배치 확장 불필요 — 확인된 분할 불가능·크기가 알려진 배치만 크기 비례 예산, 재시도 포함 총 70초 이하(«크기 모르는 배치 70초» 문구 복제 금지).
3. 수명: lifespan 소유 open/close · 독립 진입점은 pool_scope · 미등록 get_pool = RuntimeError(지연 생성 0 · #0 RULE).
   - [DA② r1 원문 반영] get_pool 미등록은 RuntimeError 그대로 유지한다. 인증 조회 경계에서는 이 미등록 오류를 명시적으로 503으로 변환하고, False/None·env 소스로 대체하지 않는다. is_internal_operator/get_platform_role의 대여부터 조회·정리까지 시도당 7초, 일시 장애 재시도 1회의 소유자를 하나로 정한다. 기존 concierge 재시도와 중첩 금지. 비운영자 False/None은 정상 결과이며 재시도하지 않는다. require_internal_operator 경유 미등록·대여 초과·문장 초과의 HTTP 503 시험을 추가한다. 부팅 중 open 실패는 startup 실패 — main.py lifespan 의 정리 구간 안에 새 open 을 넣어 이미 열린 다른 풀도 닫히게 한다.
4. 시험: ★단일 생성★ — 지금 _get_pool 은 «_pool is None» 검사 뒤 await pool.open 에서 양보해 동시 첫 요청 여럿이 풀을 각각 만들고 앞 풀을 잃는다(1580b 사전 DA② r1 발견 2 · 닫히지 않는 풀 = 연결 예산 초과). lifespan 단일 생성으로 바꾸고 «동시 첫 요청 N개 → 생성 풀 1개 · 종료 시 전부 닫힘» 시험 + 1580 RED1(죽은 backend 재대여 0 · check 제거 변이 RED) · RED2(미등록 raise) · 문장 7 s raise 를 이 풀에 대해 1벌.
   - [DA② r1 원문 반영] 미등록 cold 상태에서 동시 get_pool N개는 모두 RuntimeError이며 생성 호출 0회임을 검증한다. 이어 실제 lifespan에서 생성 1회, 동시 조회 N개에서 추가 생성 0회, 정상 종료·startup 후속 실패·본문 예외에서 생성한 풀의 close를 검증한다. open_pool의 동시 호출은 단일 소유자 밖 금지인지 직렬화 대상인지 명시한다. check 제거 변이는 실제 supabase 생성 경로의 check만 제거하고 동일한 «죽은 backend 재대여 금지» 양성 시험이 실패함을 확인한다. 격리 PG 필수 모드로 실행하여 skip을 완료 증거로 인정하지 않는다.
★금지★: 폴백 0 · 70 s 초과 값 0 · 연결 수 증가 0(max_size 4 유지 — 늘리려면 1580b 계산 먼저).

## 부하·메모리
| | 지금 | 뒤 |
|---|---|---|
| 부하 | 죽은 연결 대여 시 그 요청 503 · 문장 상한 없음(서버 기본 0 = 무제한) | 대여 때 check 1 왕복 · 문장 7 s |
| 메모리 | 연결 ≤ 4 | 같음 |

## 완료 조건
① 첫 수 표 · ② RED 3벌 rc=0 + check 제거 변이 RED · ③ ruff + 호출자 관련 pytest rc=0 · ④ 사전 DA②(bounded · codex gpt-6.1-sol low) · ⑤ PR 본문 Refs #773.
세트: <40hex> · 시험: <명령> rc=<n> · 이슈: design/cfo/indices/대기/cfo-supabase-pg-pool-old-shape-1580e.md

## 상태
- base_sha: 52b18395e6abbcd3ef24c611ac60a9054d5ac0df (spawn 2026-10-13)
- 2026-10-13 — 대기/ 생성 · byz-cfo-arch-claude#28 (PG 풀 카드 완료 조건 ⑥ · master#82 #86124)
- 2026-10-13 20:5x byz-cfo-arch-claude#28 — 배경 절 추가(spawn lint · master#82 #86379) · spawn base = PG 풀 끝 52b18395e6abbcd3ef24c611ac60a9054d5ac0df(1580 공용 팩토리·pool_healthy 가 그 세트에 있음) · 랜딩 순서 1580 → 이 카드(rebase).
- 2026-10-13 21:1x byz-cfo-arch-claude#28 — 시험 4 에 단일 생성(동시 첫 요청 경쟁) 명시 · 크기 변경(max 4→1)은 이 카드 밖 = 1580b 층 1(1580e 랜딩 뒤 · DA2-r1.md a5b7418a7f) · 사전 DA② 소환(master #86478).
- 2026-10-13 21:2x byz-cfo-arch-claude#28 — 사전 DA② r1 HOLD 4 → DA 수정안 원문을 구현 범위 1~4 에 그대로 반영(evidence/supabase-pg-pool-old-shape-1580e/DA2-r1.md) · bounded = 원문 반영으로 설계 닫음(r2 없음) · ★spawn 가능★ (base 52b18395e6) · 구현 뒤 DA⑥ 필수(제품 경로 · 인증 503 계약).
- 2026-10-13 21:00 — 대기→진행 · 좌석 byz-cfo-nano-cfo-supabase-pg-pool-old-shape-1580e#0
- 2026-10-13 nano#0 — 구현 완료(DA⑥ 대기) · 브랜치 nano/cfo-supabase-pg-pool-old-shape-1580e · 커밋 e1af3e652b[fix] · 67e9a641ef[test] · 13fa29f6fa[docs RESULT: design/cfo/evidence/supabase-pg-pool-old-shape-1580e/RESULT.md — 호출자 표·DA⑥ 포인트] · push 0 · press 0
세트: 13fa29f6fa9de45a4934f8fcea68593b34b09f51 · 시험: PAYMENT_MODE=local_mock M6_POOL_TEST_DB_URL=postgresql://postgres@127.0.0.1:38394/postgres M6_POOL_TEST_REQUIRED=1 pytest(unit 7 + integration 1580·1580e 풀·lifespan, 231 passed) + ruff check gateway tests rc=0 · 이슈: 0
- 2026-10-13 nano#0 — DA⑥ r1 HOLD 3 시험 보강 완료(제품 diff 0) · 커밋 31820e6960
세트: 31820e696073360aa733d0dab68d1dc2c0cd1d75 · 시험: PAYMENT_MODE=local_mock M6_POOL_TEST_DB_URL=postgresql://postgres@127.0.0.1:38394/postgres M6_POOL_TEST_REQUIRED=1 pytest(unit 6 + integration 1580·1580e, 231 passed; 소스 변이 3 RED: bound_borrow 제거 3·close 생략 5·오류→None 6) + ruff gateway·신규 시험 rc=0 · 이슈: 0
- 2026-10-13 22:1x byz-cfo-arch-claude#28 — DA⑥ r1 HOLD 3(시험 검출력 · 8d50f3a368) → 반송 31820e6960 arch 실측: 36 passed · 변이 3종 전부 검출 → ★APPROVE(arch)★ · 아침 큐(1580 → 1580e) · 다음 = 1580b 층 1(P=6 · CI 시험).
- 세트: 31820e696073360aa733d0dab68d1dc2c0cd1d75 · 시험: pytest test_supabase_pg_pool_1580e + test_supabase_pg_lifespan_1580e (M6_POOL_TEST_REQUIRED=1) rc=0 · 이슈: #773 Refs
- 2026-10-13 nano#0 — 1580 main 랜딩(7f53404938) 뒤 4커밋 rebase 완료 · pg_pool.py 분할 충돌은 main 판을 취하고 label/attempt_deadline 을 pg_batch_deadline.py·pg_pool.py 에 이식(행위 변경 0) · 줄 수 pg_pool 174·pg_batch_deadline 82·pg_pool_factory 155·pg_pool_acquire 64·supabase_pg 151
세트: b7090eb2a210c2805586eec4c4af6607685f360c · 시험: APP_ENV=local M6_POOL_TEST_REQUIRED=1 M6_POOL_TEST_DB_URL=postgresql://postgres@127.0.0.1:38394/postgres pytest tests/gateway/unit tests/shared/db(2730 passed) + 네 시험·1580 시험·shutdown(PAYMENT_MODE 없이) 75 passed + ruff gateway shared 신규시험 rc=0 · 이슈: 0
- 2026-10-13 23:5x byz-cfo-arch-claude#29 — rebase 회수 실측(master#83 #87414): b7090eb2a210c2805586eec4c4af6607685f360c on main 7f53404938 · range-diff = 커밋 2·3·4 동일(=) · 커밋 1 차이는 위치만 — attempt_deadline 이 pg_pool.py → pg_batch_deadline.py(1580s 분할판) · supabase_pg import 1줄 분리. AST 본문 대조 _BatchDeadline 48줄·batch_deadline·attempt_deadline·extend_statement_timeout·_bound_borrow(label 이식 포함) 전부 31820e6960 과 동일 · attempt_deadline 가져가는 곳 supabase_pg 1곳 · pg_batch_deadline 82·pg_pool 174 줄 → ★APPROVE(arch) 유지★ · 병합 = master.
- 2026-10-14 00:0x byz-cfo-arch-claude#29 — ★main 깨짐 회수 판정★(master#84 #87563): 1580e 병합 5b448c027c 가 concierge_voice_flag.py 의 retry_transient 와 _with_retry(wrap_non_retryable) 를 지웠는데, 바로 앞에 들어간 #1511(8f51a19c28)이 그 함수를 새로 2곳에서 쓴다(concierge_profile_inject.py:16,28 · routes/api/v1/concierge_org.py:16,67) → import 실패. 되돌리기 PR #1526(master).
  ★다시 맞추는 방식★(nano 반송 · 새 base = #1526 병합 뒤 main):
  1. concierge_voice_flag.py 는 ★main(#1511) 그대로 둔다★ — retry_transient · _with_retry(wrap_non_retryable) 삭제 0. #1511 의 두 호출자는 PgConciergeProfileRepository(결제·도메인 pg_pool) 조회를 감싸는 것이라 supabase_pg 재시도와 «중첩» 이 아니다 → 1580e 의 «재시도 소유자 1곳» 원칙과 충돌 없음.
  2. 1580e 가 바꾸는 것은 routes/api/v1/concierge.py 의 require_concierge_admin 한 곳만(require_admin 직접 호출 · 503 만 컨시어지 코드로) — supabase_pg 를 감싸던 중첩 재시도 제거는 유지.
  3. supabase_pg·pg_pool·pg_batch_deadline 변경은 b7090eb2a2 그대로(arch APPROVE 범위).
  4. 확인(나노): python -c "import gateway.main" 성공 · tests/gateway/unit 전체 수집 오류 0 · concierge 시험(tests 아래 concierge 포함 파일 전부) + 1580e 격리 PG 묶음(M6_POOL_TEST_REQUIRED=1) · ruff. range-diff 로 b7090eb2a2 대비 차이 = concierge_voice_flag.py 되살림뿐임을 RESULT 에 1줄.
  ★재발 방지 1줄★: 랜딩 직전 회수 시험은 «병합 대상 main 끝» 위에서 돈다 — 이번 건은 1580e 시험이 7f53404938 위에서 돌았고 그 뒤 #1511 이 먼저 들어갔다(import 전수 수집이 있었으면 잡혔다).
- 2026-10-14 nano#0 — 재작업 r2 완료: 브랜치 nano/cfo-supabase-pg-pool-old-shape-1580e-r2 · base origin/main b7f37dcb29 · range-diff = 기존 4커밋 전부 동일(=) + 신규 1커밋(397433aba7: concierge_voice_flag.py 를 main 그대로 되살림 — main 대비 diff 0, retry_transient·wrap_non_retryable 유지) · import gateway.main 성공 · 변경 concierge 쪽은 concierge.py require_concierge_admin 한 곳 · pg_pool 174·pg_batch_deadline 82·supabase_pg 151줄
세트: 397433aba7ce9799e9bcb2805b17e8791bd56a38 · 시험: APP_ENV=local M6_POOL_TEST_REQUIRED=1 M6_POOL_TEST_DB_URL=postgresql://postgres@127.0.0.1:38394/postgres pytest 1580e 풀·lifespan + 1580 + concierge unit + shutdown(168 passed) + tests/gateway/unit 2749 passed(수집 오류 0) + ruff gateway shared tests/gateway rc=0 · 이슈: 0
- 2026-10-14 00:4x byz-cfo-arch-claude#29 — r2 회수 실측 ★APPROVE(arch)★(master#84 #87806): 세트 397433aba7(base b7f37dcb29) · range-diff 1~4 '=' + 신규 5(voice_flag main 그대로) · ★병합 대상 main 끝 bd446df7e2 위 merge-tree(6a921004ef · 충돌 0) 복사본★에서: import gateway.main 성공 · tests/gateway/unit 2753 수집 · 2750 passed 3 failed(= 1395e 진짜 Redis 3건 · 이 단위 무관) · 1580e 격리 PG 묶음 + main_shutdown 54 passed(:38394 REQUIRED=1) · ruff 0.
세트: f7aa63da43f2593f5e0db54ee6a0030dd177dd40 · 시험: APP_ENV=local M6_POOL_TEST_REQUIRED=1 M6_POOL_TEST_DB_URL=postgresql://postgres@127.0.0.1:38394/postgres pytest 1580e 풀·lifespan + 1580 + concierge unit + shutdown(116 passed) · import gateway.main OK · ruff gateway shared 신규시험 rc=0 · 이슈: 0
- 2026-10-16 — 좌석 없음 → 완성 이동(진행→완성) · 세트 f7aa63da43 · 세트 = PR #1531 head · 병합 67a0c8f025 가 origin/main 조상 (squash) · 이동 근거 카드 cfo-in-progress-cards-seat-reconcile
