# 인덱스: ci-search-yaml-panic — 끝: ci search 가 probe 에서 뺄 확장자를 목록 1개(md·yml·yaml)로 묶어 yaml 도 rg 절로 따로 찾는다 · BYZ ops-lead 의 «consent gate» 가 panic 경고 0 · 버린 줄 0 · 7초 안 · rc 정직
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: #8521 — 등록 planner#291 · 발견 ops arch#107 BYZ 297089 · 정지 예외 planner#291 aifp 4348 · 발주 aifp-ft-master-pi#10 aifp 4352(발주서 .fable-team/state/team-main/aifp-ft/orders/ci-search-yaml-panic-20261113.md) · 하드 룰 12·16
- 제안서: 없음 — 앞 카드와 같은 꼴 결함 복구(새 안 0) · 설계 1쪽 = design/aifp/arch-ci-search-yaml-panic-20261113.md(길 3개 · 추천 (나) · 반례 B1~B9 · 변이 X1~X4)
- 근거: 실측 2026-11-13 22:2x(aifp-ft-arch-pi#3 · 팩 origin/main dab75a5e · probe-code 0.6.0) — BYZ .worktrees/ops-lead 에서 `ci search "consent gate" . --max 3` rc 0 · real 8.75초 · stderr `[warn] probe panic rc=134 (src/language/yaml.rs:232:53:) → rg 폴백 · 부분 출력 2줄 버림` · yaml 도 뺀 실험 사본(/tmp · 팩 손 0) real 5.74~6.83초(4회) panic 0 · 팀장 재현 9.0초
- 원인 1줄: 래퍼 feature-pack/code-intel/skill/scripts/ci search 갈래는 probe 에서 md 만 뺀다 · yaml 은 probe 의 yaml 청커(yaml.rs:232)로 가서 다중 바이트 yaml 에서 panic 한다
- 앞 카드: design/aifp/indices/진행/ci-search-ascii-md-panic.md(착지 97528b12bd16eec71dad28164ac651113f317ca8 · PR #1087) — 이 카드는 그 카드 K1~K5 의 «md» 를 목록(md·yml·yaml)으로 넓힌다
- 상태: 대기
- 설치: 있음 — ~/.local/bin/ci = 루트 checkout feature-pack/code-intel/skill/scripts/ci 심링크(착지 뒤 루트 main 반영 = 설치) · 사본 2곳 ~/.claude/skills/code-intel/scripts/ci · ~/.agents/skills/code-intel/scripts/ci ← 팩 판 cmp0
- 선행: 없음(팩 origin/main · 앞 카드 착지 97528b12 포함)
- 시험 입력: 기존 시험 fixture(core/a.py · doc.md · 다중 바이트 400자 줄) + cfg.yaml·cfg.yml(다중 바이트 줄) + yaml·md 없는 fixture 1 · 가짜 probe(PROBE_BIN · 인자 기록 · 정상 hit/nohits/panic) · RG_BIN 대역 · PATH 앞 가짜 timeout(실행 대상 구분 · 즉시 rc 124) · sleep 0 · HOME·TMPDIR 격리 · 네트워크 0 · 실 probe 0
- 기준값: 재현 명령 panic 경고 1 · 버린 줄 2 · real 8.75~9.0초 → 목표 = panic 경고 0 · 버린 줄 0 · 7초 안(실험 사본 최대 6.83초 · 여유 얇음)
- 규칙: 없음 — 래퍼 내부 동작이라 하드 룰 16 문구와 훅은 그대로 둔다
- 대상: 팩 feature-pack/code-intel/skill/scripts/ci(search 갈래 · probe 인자 2곳 · rg 절 · 폴백 rg glob) · 시험 feature-pack/code-intel/tests/test_ci_search_nonascii_panic.sh(덧붙임)
- 정본 영향 없음: code-intel 래퍼 search 갈래 내부 동작 · 스킬 문서·정본 문서 변경 0
- 배정: 대기(DA · 2026-11-13T22:28)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」. 골의 축: A(모니터·요청 — 모든 하네스가 쓰는 코드 탐색 도구 ci 가 yaml 이 섞인 리포에서도 죽지 않고 7초 안에 답한다). 이 카드의 증거 = 착지 sha + 시험 rc0 + 설치 cmp0 + 재현 명령 panic 0 원문.

## 배경 (한 단락)
앞 카드는 probe 의 markdown 청커 panic 을 피하려고 md 를 probe 에서 빼고 rg 절로 보냈다. 같은 꼴 panic 이 yaml 청커(yaml.rs:232)에서 또 나왔다. 폴백은 되지만 경고가 나고, 부분 출력을 버리고, 9초 가까이 걸린다(7초 룰 넘음). yaml 도 빼면 panic 0 · 5.7~6.8초다. 세 번째 언어가 나와도 낱말 1개로 끝나게 뺄 확장자를 목록 1개로 묶는다. 설계 = 설계 1쪽 §3(Y1~Y6).

## 계약
- L1 목록 1개 `_PROBE_SKIP=(md yml yaml)` · 스크립트 상수 · 환경 변수 0 (Y1)
- L2 probe 호출 2곳(1단계·OR)은 목록에서 `-i '*.<x>'` 를 만든다 · md 하드코딩 삭제 (Y2)
- L3 rg 절 1개 = 목록마다 `-g '*.<x>'` · 나머지는 앞 카드 K2~K4 그대로 (Y3)
- L4 panic 폴백 rg = 목록마다 `-g '!*.<x>'` · 겹침 0 (Y4)
- L5 문구 고정 글자: 절 머리 `== markdown·yaml (rg 폴백 · probe panic 회피) ==` · `[info] markdown·yaml 은 rg 로 분리 검색(probe panic 회피)` · `[warn] markdown·yaml rg 실패 rc=<N>` (Y5)
- L6 그대로: C1·K7 panic 판정 · K6 probe 상한 25 · C8 출력 보류 · D6 OR 조건 · _cut160 · 다른 갈래 (Y6)

## 구현 범위 (나노 1 · 팩 base origin/main)
1. feature-pack/code-intel/skill/scripts/ci search 갈래 — 목록 1개 · probe 인자 2곳 · rg 절 glob · 폴백 rg glob · 문구 3개(L1~L5) · 다른 갈래 손 0
2. 시험 덧붙임 feature-pack/code-intel/tests/test_ci_search_nonascii_panic.sh — B1~B9 · 변이 X1~X4 · 문구 바뀐 기존 검사는 기대 글자만 고침(삭제 0) · 기준판 = origin/main 판 ci · 재진입 가드 · ulimit -u + timeout 70 · 100644
3. 회귀: feature-pack/code-intel/tests/test_ci_ast_probe_panic.sh · test_ci_outline_missing_path.sh · test_ci_lsp_crashloop.sh rc0

## 완료 조건
1. [ ] 나노: 시험 전체(앞 카드 175 + B1~B9) rc0 · 걸린 초
2. [ ] 나노: 기준판(origin/main ci) B1·B2·B3·B6 FAIL 원문
3. [ ] 나노: 변이 X1~X4 각각 지정 반례 FAIL(4/4)
4. [ ] 나노: 회귀 3파일 rc0 · 시험 파일 100644 · B8 `.YAML` 실측 1줄
5. [ ] master: 착지 sha → 설치(루트 main 반영 · 사본 2곳 cmp0)
6. [ ] master: 재현 명령 원문(BYZ ops-lead · `ci search "consent gate" . --max 3`) — panic 경고 0 · 버린 줄 0 · real 7초 안 · 최종 구현 전체 명령 1회의 real·rc·panic·버린 줄 기록 · 추가 확인은 사유 1줄과 함께 1회까지 · 실행한 결과 전부 보존 · 7초를 넘은 결과를 빼고 통과시키지 않음 · 한 번이라도 7초 넘으면 완료 조건 미충족 · 설계 §1 실험 5.74~6.83초는 실험 사본 값 · 최종 증거 아님 → ops arch#107·harness#243·planner#291 1통
7. [ ] master: 앞 카드 재현(BYZ harness-ops-m175 · `ci search "request register" . --max 3`) 원문 — 앞 카드 끝 기준 그대로
- 나노 끝선(5줄 이내): 바꾼 줄 범위 · 시험 결과 줄·초 · 기준판·변이 FAIL 목록 · 기대 글자 고친 검사 줄 · 설계와 다르게 한 점(없으면 «없음»)

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| L1 목록 1개 | B1 · B3 · X1 |
| L2 probe 인자 | B1 · B2 · X4 |
| L3 rg 절 glob | B1 · B3 · B4 · X3 |
| L4 폴백 rg glob | B6 · X2 |
| L5 문구 | B1 · B4 · B9 |
| L6 앞 카드 그대로 | B5 · B7 · B9 |

## 범위 밖
- probe 바이너리 수정(외부 · upstream yaml.rs 신고 별건)
- probe 검색 속도 자체(7초 여유를 더 벌려면 새 카드)
- 다른 언어 청커 panic(목록 낱말 1개 · 새 카드) · outline/sym/refs/ast 갈래 · SKILL.md 문구

## 상태
- 2026-11-13 · 대기 — aifp-ft-arch-pi#3 작성(aifp 4352 · 실측 재현 panic 1·버린 줄 2·8.75초 · yaml 뺀 실험 사본 5.74~6.83초 panic 0) · 다음 = DA aifp-ft-da-codex#0 사전검증 → APPROVE 뒤 aifp-ft-master-pi#10 → 나노 1석
