# 인덱스: CI 비용 차단 5개 — .github/workflows/ci.yml 문서 제외 · concurrency · observe-only 수동화 · main push 축소 · 로컬 검증 (판정 436 · 오빠 즉시)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 436(오빠 「github ci/cd bucket 크래딧 소모가 심각해」「1주?사이에 $120」 · planner#10 REQ-436 · master#15 #62971)
- 상태: 대기
- 선행: 없음(origin/main 최신에서 브랜치)
- 시험 입력: ci.yml 파일만 — 실제 GitHub Actions 실행 0(결제 정지 · 로컬 검증만)
- 기준값: planner 실측(10-07 00Z 이후 ≈1.6일) CI 188회 · 회당 평균 53분 · ≈10,000분 ≈ $80 · 회당 분 = Python Test 21.0 · Python Test [RED] observe-only 12.2 · Web Test 6.8 · 나머지 1~2 · main push 129회(PR 통과분 재실행) · 이벤트 push 118 · pull_request 129

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: C(업그레이드·반영 — 전 트랙 랜딩 경로 CI 비용). 핵심 한 줄: 같은 커밋을 PR·main 에서 두 번 돌리고 문서 커밋·관찰 전용 잡까지 매번 돌던 CI 를 «PR 에서 한 번 전체 · main 은 가벼운 것만 · 문서·관찰 전용은 안 돈다» 로 바꾼다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
`.github/workflows/ci.yml`(567줄 · 잡 14개)은 pull_request·push(main·develop) 둘 다에서 모든 잡을 돌린다. 그래서 PR 에서 통과한 커밋이 main 에 들어갈 때 같은 전체 시험을 다시 돌고(main push 129회), 문서만 바뀐 커밋도 전체를 돌고, 결과를 보지 않는 observe-only 잡(Python/Web RED observe · RBAC drift)도 매번 돌며, 같은 PR 에 연속 push 하면 이전 실행이 취소되지 않고 끝까지 돈다. 오빠 판정 436 은 다섯 가지로 막는다: ①문서 경로 변경은 CI 를 띄우지 않음 ②같은 PR/ref 의 이전 실행은 취소(main push 는 취소하지 않음) ③observe-only 3개는 수동(workflow_dispatch)만 ④main·develop push 는 린트·스키마·LLM 계약(스모크)만 · 전체 Python/Web/Mobile 시험은 pull_request 에서만 ⑤로컬 검증. 지금 결제가 정지돼 이 PR 자체 CI 는 못 돌기 때문에 로컬 검증 증거로 이 PR 1건만 squash 머지한다(오빠 판정 436 범위의 예외). CD(Dev) 는 cd-dev.yml 의 main push 트리거라 이 카드에서 건드리지 않는다. 저장소는 브랜치 보호 필수 체크가 없는 요금제(rulesets API 403 · arch 실측)라 문서 제외로 PR 이 「필수 체크 대기」에 걸릴 일은 없다.

## 사전검증
- 소환: 아니오
- 면제: 오빠 판정 436 「즉시」 · DA 생략 지시(master #62971) · 변경은 ci.yml 1파일 트리거·조건만(되돌림 = revert 1커밋) — arch 서명 byz-harness-arch-claude#14

## 조사 근거
- `.github/workflows/ci.yml:4`~`:8` 트리거 = pull_request·push [main, develop] · workflow_dispatch 없음 · concurrency 없음.
- 잡 목록(origin/main 실측): `:15` static_v4_feature_guard(이미 PR 전용) · `:32` python-lint · `:55` file-size-budget(이미 PR 전용) · `:78` python-test(needs python-lint) · `:191` python-test-red-observe · `:260` schema-migrations · `:340` llm-contract · `:394` rbac-critical-drift(continue-on-error) · `:437` v5-spike-test · `:458` web-lint · `:481` web-test · `:508` web-test-red-observe · `:543` mobile-test.
- `.github/workflows/cd-dev.yml` 트리거 = push [main] + workflow_dispatch — ci.yml 과 독립(needs·workflow_run 연결 없음) → 이 카드 범위 밖 · 변경 0.

## 구현 범위 (닫힌 목록 · `.github/workflows/ci.yml` 1파일)
1. 트리거(`.github/workflows/ci.yml:4`): `pull_request`·`push` 둘 다 `paths-ignore: ['docs/**', 'design/**', '**/*.md', '.fable-team/**']` · `workflow_dispatch:` 추가(수동 전체 실행 입구).
2. 워크플로 최상위 `concurrency:` — `group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}` · `cancel-in-progress: ${{ github.event_name == 'pull_request' }}`(main·develop push 는 취소 0).
3. observe-only 3잡(`python-test-red-observe` · `web-test-red-observe` · `rbac-critical-drift`): `if: github.event_name == 'workflow_dispatch'`(기존 if 가 있으면 `&&` 로 합침).
4. 전체 시험 잡(`python-test` · `web-test` · `mobile-test` · `v5-spike-test`): `if: github.event_name != 'push'`(= pull_request · workflow_dispatch 에서만) · main·develop push 에 남는 잡 = `python-lint` · `web-lint` · `schema-migrations` · `llm-contract`(스모크) — 이 넷의 조건은 바꾸지 않는다.
5. 다른 잡의 `needs:` 가 3·4 에서 조건이 붙은 잡을 가리키면(건너뜀 → 연쇄 건너뜀) 목록으로 보고하고 고치지 않는다(지금 실측상 해당 0 — 4 의 잡은 전부 needs 를 «받는» 쪽).
6. 잡 본문(steps·services·env)·다른 워크플로 파일 변경 0.

커밋은 자기 브랜치(`[chore] CI 비용 차단 — 판정 436`) · **push 금지**(master 가 PR·예외 squash 머지 집행). **금지**: 잡 삭제 · 시험 내용 변경 · `.github/workflows/cd-dev.yml` · `.github/workflows/cd-prod.yml` 변경 · 실제 Actions 실행·재실행.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 로컬 검증 4개(RESULT 에 출력 복붙):
  ①`python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml'))"` rc=0
  ②잡 이름·needs 대조 스크립트 출력: 변경 전후 잡 집합 동일(14개) · 모든 needs 대상 실재 · 이벤트별 실행 잡 표(pull_request / push main / workflow_dispatch / 문서만 바뀐 push = 워크플로 미기동)
  ③`actionlint .github/workflows/ci.yml` rc=0(로컬 /opt/homebrew/bin/actionlint 있음) — 새 경고 0
  ④회당 분 전/후 예상 1줄(planner 회당 분 근거): PR 1회 = 전 ≈53 → 후 ≈40(RED observe 12.2·RBAC 제외) · main push 1회 = 전 ≈53 → 후 ≈5(린트·스키마·LLM 계약) · 문서 전용 push = 0 · 연속 push = 마지막 1회만.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: actionlint .github/workflows/ci.yml rc=0 · 이슈: 0`.
- 랜딩(master 집행 · 카드 밖): PR 생성 → 로컬 검증 증거를 PR 본문에 → ★결제 복구 전 squash 머지 1건 예외(판정 436)★ → planner 에 PR 번호 + 검증 증거 + 회당 분 전/후 1줄 회신 → 결제 복구 뒤 첫 PR 1건에서 이벤트별 잡 표 실측 대조.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: b3a509e97f073ee26d980699e7ed29489bde558b (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#14 · 판정 436 · master #62971 · 오빠 즉시 · DA 생략).
- 정본 영향 없음: CI 트리거·조건만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 15:12 — 대기→진행 · 좌석 byz-harness-nano-v436-ci-cost-cut#0
- 2026-10-08 — 구현 완료(미push) · 세트: 6fe01a83a1f27fed2386520a8a67ceac166079d1 · 시험: actionlint -shellcheck= .github/workflows/ci.yml rc=0 (기본 actionlint 는 SC2086 info 2건 rc=1 — 변경 전부터 동일·본문 미변경) · 이슈: 0
- 2026-10-08 15:31 — 진행→완성 · 좌석 byz-harness-nano-v436-ci-cost-cut#0 · DA design/harness/OPS-VERDICTS-20261006.md#§60
- 2026-10-08 15:3x — 정정(master#15): 위 이동의 DA 인용 §60 은 카드 2 판정 절로 오기재. 이 카드의 닫힘 근거 = design/harness/OPS-VERDICTS-20261006.md#§61

세트: 6fe01a83a1f27fed2386520a8a67ceac166079d1 · 시험: actionlint -shellcheck= .github/workflows/ci.yml rc=0 · 이슈: 0
