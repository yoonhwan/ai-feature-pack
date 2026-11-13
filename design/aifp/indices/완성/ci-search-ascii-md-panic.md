# 인덱스: ci-search-ascii-md-panic — 끝: ci search 가 질의 종류(ASCII·비ASCII)와 상관없이 markdown 을 probe 에 넘기지 않고 rg 절로 따로 찾는다 · BYZ harness-ops-m175 의 «request register» 가 panic 경고 0 · 버린 줄 0 · 7초 안 · rc 정직 · probe 단계 상한 25초
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: #8519 — 등록 planner#291 aifp 4315 · 요청 harness#242 aifp 4306 · 발견 harness arch#337 BYZ 296913·296914 · 발주 aifp-ft-master-pi#9 aifp 4307(발주서 .fable-team/state/team-main/aifp-ft/orders/ci-search-ascii-md-panic-20261113.md) · 하드 룰 12·16
- 제안서: 없음 — 앞 카드 남은 갈래 복구(새 안 0) · 설계 1쪽 = design/aifp/arch-ci-search-ascii-md-panic-20261113.md(길 3개 · 추천 (가) · 반례 A1~A9 · 변이 W1~W4)
- 근거: 실측 2026-11-13 21:3x(aifp-ft-arch-pi#3 · 팩 origin/main 36509bff · probe-code 0.6.0) — BYZ .worktrees/harness-ops-m175 에서 `ci search "request register" . --max 3` rc 0 · real 6.79초 · stderr `[warn] probe panic rc=134 (src/language/markdown.rs:240:69:) → rg 폴백 · 부분 출력 2줄 버림` · 같은 자리 비ASCII 질의(md 를 probe 에서 뺌) real 2.89초 panic 0 · 팀장 재현 7.07초 · timeout 7 이면 rc 124
- 원인 1줄: 래퍼 feature-pack/code-intel/skill/scripts/ci search 갈래는 비ASCII 질의만 md 를 probe 에서 뺀다 · ASCII 질의는 md 를 probe 의 markdown 청커(markdown.rs:240)에 넘기고, 다중 바이트 md 에서 panic 한다
- 앞 카드: design/aifp/indices/완성/ci-search-nonascii-panic.md(착지 a9ab9b3c0bd87f6c516751d595425b64c1f47414 · PR #1049) — 이 카드는 그 카드 C6 «ASCII 정상 호출 그대로» 를 md 절·[info] 1줄 범위만 바꾼다
- 상태: 완성
- 착지: 97528b12bd16eec71dad28164ac651113f317ca8(팩 main · PR #1087 · 사람 승인 길 · 오빠 «네» 1794575543.474599 · 세트 556e22f8 · 설치 사본 2곳 cmp0)
- DA: aifp-ft-da-codex#0 APPROVE-DESIGN 142ee11edecffd532d6cb6087dd41a7efe95323b(aifp 4312 · 판정문 .fable-team/state/team-main/aifp-ft/DA-ci-search-ascii-md-panic-design-142ee11e.md) · 구현 메모 3점: ① probe 25초 = 로컬 하네스 단계 상한(7초는 실 명령 별도 실측) ② C6 변경에 ASCII md hit rc1→0 보정·OR 재시도 생략 포함(P7·P8 기대 고침 · 검사 삭제 0) ③ 가짜 timeout 은 실행 대상으로 단계 구분(A7 probe · P14 폴백 rg · P17 rg 25초 기록) · A3 기준판 FAIL 검사에 [info] 1줄 포함
- 설치: 있음 — ~/.local/bin/ci = 루트 checkout feature-pack/code-intel/skill/scripts/ci 심링크(착지 뒤 루트 main 반영 = 설치) · 사본 2곳 ~/.claude/skills/code-intel/scripts/ci · ~/.agents/skills/code-intel/scripts/ci ← 팩 판 cmp0
- 선행: 없음(팩 origin/main)
- 시험 입력: 기존 시험 fixture(core/a.py · doc.md · 다중 바이트 400자 줄) + md 없는 fixture 1 · 가짜 probe(PROBE_BIN · 인자 기록 · 정상 hit/nohits/panic/스스로 kill -ABRT) · RG_BIN 대역(md rg rc 2) · PATH 앞 가짜 timeout(인자 기록 · 즉시 rc 124) · sleep 0 · HOME·TMPDIR 격리 · 네트워크 0 · 실 probe 0
- 기준값: 재현 명령 panic 경고 1 · 버린 줄 2 · real 6.79~7.07초 → 목표 = panic 경고 0 · 버린 줄 0 · 7초 안
- 규칙: 없음 — 래퍼 내부 동작이라 하드 룰 16 문구와 훅은 그대로 둔다
- 대상: 팩 feature-pack/code-intel/skill/scripts/ci(search 갈래 · `_probe_search` 만) · 시험 feature-pack/code-intel/tests/test_ci_search_nonascii_panic.sh(덧붙임)
- 정본 영향 없음: code-intel 래퍼 search 갈래 내부 동작 · 스킬 문서·정본 문서 변경 0
- 배정: 대기(DA · 2026-11-13T21:39)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」. 골의 축: A(모니터·요청 — 모든 하네스가 쓰는 코드 탐색 도구 ci 가 markdown 이 많은 리포에서 죽지 않고 7초 안에 답한다). 이 카드의 증거 = 착지 sha + 시험 rc0 + 설치 cmp0 + 재현 명령 panic 0 원문.

## 배경 (한 단락)
하드 룰 16 은 코드 찾기를 ci 로 먼저 하게 한다. 앞 카드는 probe 출력 단계 panic 을 감지해 rg 로 폴백하게 했다. 그런데 ASCII 질의는 여전히 md 를 probe 에 넘긴다. probe 의 markdown 청커가 다중 바이트 md 에서 panic 하면 폴백은 되지만 경고가 나고, 부분 출력을 버리고, panic 까지 md 를 다 읽느라 7초 근처가 된다(timeout 7 이면 rc 124). 비ASCII 갈래처럼 md 를 처음부터 rg 로 나누면 panic 이 안 나고 2.9초다. 설계 = 설계 1쪽 §3(E1~E8).

## 계약
- K1 1단계 probe 는 질의 종류와 상관없이 `-i '*.md'` · `md_excl=1` 고정 · nonascii 갈림 삭제 (E1)
- K2 md rg 절은 모든 질의에 돈다 · 자리·순서·rc 1→0 보정은 앞 카드 D8 그대로 (E2)
- K3 md rg 질의 = `-F` + 낱말마다 `-e`(read -ra · glob 0) · 정규식 `md_pat` 삭제 (E3)
- K4 md rg 경로 = RG_BIN → _resolve rg · 상한 min(CI_RG_TIMEOUT, 25) · rc ≥ 2·124 이면 md 절 0 + `[warn] markdown rg 실패 rc=<N>` 1줄 · probe 결과·rc 그대로 (E4)
- K5 `[info] markdown 은 rg 로 분리 검색(probe panic 회피)` 1줄 · 모든 질의 공통 (E5)
- K6 probe 단계 = GNU timeout min(CI_TIMEOUT, 25)(정수 아니면 25) · probe `--timeout` 도 같은 값 · 124 = stdout 0줄 + `판정 불가 ci search: probe 시간 초과 rc=124 — scope 를 좁히세요` + rc 124 (E6)
- K7 panic 판정 = 앞 카드 C1 그대로 · timeout 감싼 뒤에도 134·133·101 보임 (E7)
- K8 그대로: 앞 카드 C2·C3·C4·C8 · OR 재시도(D6) · _cut160 · 다른 갈래 (E8)

## 구현 범위 (나노 1 · 팩 base origin/main)
1. feature-pack/code-intel/skill/scripts/ci search 갈래 — 1단계 if 삭제 · md 조건 2곳 삭제 · md rg -F/-e · md rg 실패 1줄 · `_probe_search` 에 timeout 감싸기 · [info] 문구(K1~K7) · 다른 갈래 손 0
2. 시험 덧붙임 feature-pack/code-intel/tests/test_ci_search_nonascii_panic.sh — A1~A9 · 변이 W1~W4 · P7·P8 기대값 고침(삭제 0) · 기준판 = origin/main 판 ci · 재진입 가드 · ulimit -u + timeout 70 · 100644
3. 회귀: feature-pack/code-intel/tests/test_ci_ast_probe_panic.sh · test_ci_outline_missing_path.sh · test_ci_lsp_crashloop.sh rc0

## 완료 조건
1. [ ] 나노: 시험 전체(P1~P21 + A1~A9) rc0 · 걸린 초
2. [ ] 나노: 기준판(origin/main ci) A1·A3·A7·A8·A9 FAIL 원문
3. [ ] 나노: 변이 W1~W4 각각 지정 반례 FAIL(4/4)
4. [ ] 나노: 회귀 3파일 rc0 · 시험 파일 100644
5. [ ] master: 착지 sha → 설치(루트 main 반영 · 사본 2곳 cmp0)
6. [ ] master: 재현 명령 원문(BYZ harness-ops-m175 · `ci search "request register" . --max 3`) — panic 경고 0 · 버린 줄 0 · real 7초 안 · `| head -1` 의 `PIPESTATUS[0]` ≠ 134 → harness#242 1통
7. [ ] master: 비ASCII 회귀 `ci search "판정 불가" feature-pack/fable-team/ft2/core --max 3` 원문 — 앞 카드 끝 기준 그대로
- 나노 끝선(5줄 이내): 바꾼 줄 범위 · 시험 결과 줄·초 · 기준판·변이 FAIL 목록 · P7·P8 고친 기대 줄 · 설계와 다르게 한 점(없으면 «없음»)

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| K1 md 늘 뺌 | A1 · A3 · W1 |
| K2 md 절 모든 질의 | A1 · A2 · A4 |
| K3 md rg 글자 그대로 | A8 · W2 |
| K4 md rg 경로·실패 | A9 · W4 |
| K5 [info] 1줄 | A1 · A3 |
| K6 probe 상한 25 | A7 · W3 |
| K7 panic 판정 유지 | A5 · A6 |
| K8 앞 카드 그대로 | A2 · A5 · 기존 P1~P21 |

## 범위 밖
- probe 바이너리 수정(외부 · upstream markdown.rs 신고 별건)
- 부른 쪽 파이프의 `$?`(래퍼가 바꿀 수 없음)
- outline/sym/refs/ast 갈래 · SKILL.md 문구 · rg md 결과 순위 품질

## 상태
- 2026-11-13 · 대기 — aifp-ft-arch-pi#3 작성(aifp 4307 · 실측 재현 panic 1·버린 줄 2·6.79초 · md 뺀 경로 2.89초) · 다음 = DA aifp-ft-da-codex#0 사전검증 → APPROVE 뒤 aifp-ft-master-pi#9 → 나노 1석
- 세트: 556e22f8bebf76b12957d6f9aa108f4937f6ed96 · 시험: bash feature-pack/code-intel/tests/test_ci_search_nonascii_panic.sh rc=0 · 이슈: #8519
- 완료: aifp-ft-nano-ci-search-ascii-md-panic#0 · 한 일: ci search md 늘 rg 절 · probe 단계 상한 25초 · [info] 1줄(DA APPROVE-IMPLEMENTATION 556e22f8 aifp 4327) · 산출: nano/ci-search-ascii-md-panic@556e22f8 · 병합 상태: 착지 97528b12bd(PR #1087) · 남은 일: 없음
- 2026-11-13 · 완성 — 나노 닫힘(ft-nano-close landed-pr=1087) · 설치 사본 2곳 cmp0
