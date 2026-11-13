# 인덱스: ci-search-nonascii-panic — 끝: ci search 가 probe 결과 줄 panic(rc 134·101 · stderr «panicked at»)을 감지하면 부분 출력을 버리고 rg 폴백 결과를 낸다 · stdout 첫 줄 = 폴백 표지 · rc 정직(결과 0 / 0건 1 / 폴백 실패 3 · 134 그대로 내보냄 0) · 반례 시험 1개 rc0 · 기준판 FAIL · 착지 · 설치 cmp0 · 실 명령 panic 0
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: 없음 — planner#286 aifp 4186 · harness#235 BYZ #295172 · 발주 aifp-ft-master-pi#7 aifp 4187(발주서 .fable-team/state/team-main/aifp-ft/orders/ci-search-nonascii-panic-20261113.md) · 하드 룰 16(ci 불가 = 결함)
- 제안서: 없음 — 래퍼 1곳 결함 복구(새 안 0) · 설계 1쪽 = design/aifp/arch-ci-search-nonascii-panic-20261113.md(감지 조건·폴백 꼴·rc 규칙·반례)
- 근거: 실측 2026-11-13(aifp-ft-arch-pi#2 · origin/main a7f459c5 · probe-code 0.6.0) — `ci search "판정 불가" feature-pack/fable-team/ft2/core --max 3` rc 134 · stderr `src/search/search_output.rs:2566:31 end byte index 30 is not a char boundary; it is inside '·'` · stdout 앞 40줄만 · ASCII `reopen` 도 rc 134(panic 2회 = md 뺀 재시도도 panic) · `verdict` rc 0 · `… 2>/dev/null | head -3` 의 `$?`=0 · `PIPESTATUS[0]`=134
- 원인 1줄: probe 0.6.0 이 결과 줄을 출력할 때 바이트로 자른다(파일 종류·질의 문자 무관) · 래퍼 feature-pack/code-intel/skill/scripts/ci search 갈래(:127~174)는 «markdown AST panic» 만 가정해 md 만 빼고 재시도 → 다시 panic → rc 134·부분 stdout 이 그대로 나감
- 상태: 대기
- 설치: 있음 — ~/.local/bin/ci = 루트 checkout feature-pack/code-intel/skill/scripts/ci 심링크(착지 뒤 루트 main 반영 = 설치) · 사본 2곳 ~/.claude/skills/code-intel/scripts/ci · ~/.agents/skills/code-intel/scripts/ci ← 팩 판 cmp0
- 선행: 없음(팩 origin/main)
- 시험 입력: 임시 폴더 fixture(core/a.py · doc.md · 다중 바이트 400자 줄 · hit 10파일) · 가짜 probe(PROBE_BIN · 단계별 꼴 panic/rconly/nohits/hit/errpanic · rc 134/133/101/1/0) · RG_BIN 대역(결과 뒤 rc2 · 3초 sleep · 인자 기록)/없는 경로 · PATH 앞 가짜 timeout(상한 기록) · HOME·TMPDIR 격리 · 네트워크 0 · 실 probe 0 · 재진입 가드 · ulimit -u + timeout 70
- 기준값: 실 명령 3개 중 2개 rc 134(판정 불가 · 판정 · reopen) · 부분 stdout 40줄 → 목표 = panic 새는 수 0 · rc 134 0
- 규칙: 없음 — 래퍼 내부 폴백이라 하드 룰 16 문구와 훅은 그대로 둔다
- 대상: 팩 feature-pack/code-intel/skill/scripts/ci(search 갈래만) · 시험 feature-pack/code-intel/tests/test_ci_search_nonascii_panic.sh(신설 · 100644)
- 정본 영향 없음: code-intel 래퍼 search 갈래 내부 동작 · 스킬 문서·정본 문서 변경 0
- 배정: 대기(DA · 2026-11-13T15:23)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」. 골의 축: A(모니터·요청 — 모든 하네스가 쓰는 코드 탐색 도구 ci 가 한국어 코드 줄에서 죽지 않는다). 이 카드의 증거 = 착지 sha + 시험 rc0 + 설치 cmp0 + 실 명령 panic 0 원문.

## 배경 (한 단락)
하드 룰 16 은 코드 찾기를 ci 로 먼저 하게 한다. 그런데 결과 줄에 `·`·한글이 든 파일이 걸리면 probe 0.6.0 이 출력 단계에서 panic 하고 ci 는 rc 134 와 잘린 stdout 을 낸다. 11-09 수정은 질의 쪽(비ASCII 질의면 md 를 rg 로 분리)만 고쳤다. 코드 파일 결과 줄은 그대로 죽는다. ASCII 질의도 같은 자리에서 죽는다(reopen 실측). 부른 쪽이 `| head` 로 받으면 `$?` 가 0 이라 조용한 실패처럼 보인다. probe 는 외부 바이너리라 래퍼가 panic 을 감지해 rg 로 폴백한다. 설계 = 제안서 §2(D1~D8).

## 계약
- C1 panic 판정 = probe rc ∈ {134, 133, 101}(stderr 없어도) 또는 stderr 에 `panicked at`(rc 0 이어도) (D2)
- C2 panic 이면 모든 단계 부분 stdout 0 · stdout 첫 줄 `== rg 폴백 (probe panic rc=<N>) ==` · stderr `[warn] probe panic …` 1줄 · rg 결과 `파일:줄` + 본문 앞 160자(문자 단위 · UTF-8 유효) (D3)
- C3 rc(실패 먼저): rg 없음·rgrc 124·rgrc≥2 = 3 + stdout 전체 0줄(rg 가 낸 줄·비ASCII 갈래 md 절도 내지 않음) + `판정 불가 ci search: …` → 그다음 rgrc 1 = 1 → rgrc 0 = 0 · rgrc 는 결과 제한 전에 받는다(rg→파일 · head 는 파일에서 · 파이프 0) · 134/133/101 그대로 내보냄 0 (D3·D4)
- C4 panic 난 probe 가 `-i '*.md'` 였으면 rg 도 `-g '!*.md'` · 비ASCII 갈래 md 절은 그대로 · 겹침 0 (D3·D8)
- C5 ASCII 갈래의 md 뺀 probe 재시도 삭제 · 첫 단계 panic 이면 OR probe 안 부름 (D5·D6)
- C6 panic 아닌 호출은 지금과 같다(stdout·stderr·rc·순서 그대로) (D1a·D2·D8)
- C7 rg 경로 = RG_BIN 우선 → _resolve rg · 상한 = min(CI_RG_TIMEOUT, 25) · 정수 아니면 25 (D3·D7)
- C8 출력 보류: OR 재시도 여부가 정해질 때까지 모든 단계 출력을 내지 않는다 · 어느 단계든 panic 이면 첫 단계 `No results found` 까지 버리고 폴백 → 표지 = 언제나 전체 stdout 첫 줄 (D1·D1a·D6)

## 구현 범위 (나노 1 · 팩 base origin/main)
1. feature-pack/code-intel/skill/scripts/ci search 갈래(:127~174) — `_probe_search` 1함수(stdout 쓰기 0) + 호출 3곳 교체 + 끝에 한 번 내기 + RG_BIN 해석 1줄(C1~C8) · 다른 갈래 손 0
2. 시험 신설 feature-pack/code-intel/tests/test_ci_search_nonascii_panic.sh — 가짜 probe(test_ci_ast_probe_panic.sh 꼴 · PROBE_BIN 대역 · 단계별 꼴) · P1~P17(설계 §3 표) · 변이 V1~V10 · 기준판 = origin/main 판 ci(git show 로 임시 파일) · 재진입 가드 · ulimit -u + timeout 70 · 100644
3. 회귀: feature-pack/code-intel/tests/test_ci_ast_probe_panic.sh · test_ci_outline_missing_path.sh · test_ci_lsp_crashloop.sh rc0

## 완료 조건
1. [ ] 나노: 새 시험 P1~P17 rc0 · 걸린 초
2. [ ] 나노: 기준판(origin/main ci) P7·P8 빼고 전부 FAIL · P7·P8 PASS 원문
3. [ ] 나노: 변이 V1~V10 각각 지정 반례 FAIL(10/10)
4. [ ] 나노: 회귀 3파일 rc0 · 시험 파일 100644
5. [ ] master: 착지 sha → 설치(루트 main 반영 · 사본 2곳 cmp0)
6. [ ] master: 실 명령 `ci search "판정 불가" feature-pack/fable-team/ft2/core --max 3` 원문 — panic 새지 않음 · 폴백 표지 + 결과 · `PIPESTATUS[0]` ≠ 134 → planner#286 1통(착지 경로·sha)
- 나노 끝선(5줄 이내): 바꾼 줄 범위 · 시험 결과 줄·초 · 기준판·변이 FAIL 목록 · 설계와 다르게 한 점(없으면 «없음») · «설치 h 필요» 1줄

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| C1 panic 판정 | P1 · P2 · P3a · P3b · P3c · P4 · V1 · V2 · V3 |
| C2 폴백 꼴·문자 단위 자르기 | P1 · P9 · P11 · V5 |
| C3 rc 규칙(실패 먼저·rgrc 먼저 받기) | P1 · P5 · P6 · P11 · P13a · P13b · P14 · P15 · V4 · V8 |
| C4 md 겹침 0 | P10 · V6 |
| C5 md 재시도 삭제·OR 안 부름 | P2 · P5 |
| C6 정상 호출 그대로 | P7 · P8 |
| C7 rg 경로·상한 25 | P6 · P14 · P16 · P17 · V9 · V10 |
| C8 출력 보류 | P12 · V7 |

## 범위 밖
- probe 바이너리 수정(외부 · upstream 신고 별건)
- 부른 쪽 파이프의 `$?`(래퍼가 바꿀 수 없음 · 표지 첫 줄과 PIPESTATUS 로만 보임)
- outline/sym/ast 갈래 · SKILL.md 문구

## 상태
- 2026-11-13 · 대기 — aifp-ft-arch-pi#2 작성(aifp 4187 · 실측 rc 134 재현 · ASCII 질의 panic 추가 확인) · 다음 = DA aifp-ft-da-codex#0 사전검증 → APPROVE 뒤 aifp-ft-master-pi#7 1통 → 나노 1석
- 2026-11-13 · 대기 — DA REJECT 보정(aifp 4189 · 동결 e3bdb757) R1 출력 보류 C8·P12 · R2 rgrc 먼저 받기·실패 먼저·P13a/b·P14·P15 · R3 상한 min(…,25)·rc-only P3a/b/c·RG_BIN P16·상한 P17 · 변이 10
