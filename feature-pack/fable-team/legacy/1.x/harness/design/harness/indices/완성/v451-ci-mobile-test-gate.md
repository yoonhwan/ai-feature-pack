# 인덱스: CI Mobile Test — clients/mobile 변경 때만 실행(잡 레벨 변경 감지) + Set up Flutter 5분 timeout (판정 451 ⓐ+ⓑ · 판정 436 후속)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 451(planner#11 #63462 · master#16 #63468 · 근거 master 실측 #63459)
- 상태: 대기
- 선행: 없음 — origin/main 최신에서 브랜치(ci.yml 은 main 이 ops/main-base 보다 앞)
- 시험 입력: `actionlint` + 임시 git 리포 2쌍(모바일 변경 있음/없음)에서 ci.yml 의 변경 감지 step 스크립트를 그대로 뽑아 실행 — 실제 PR·push·Actions 실행 0
- 기준값: Mobile Test 평소 1m25s · PR #936 에서 Set up Flutter 가 07:36~07:50 행 → 잡 timeout 15분에 cancelled · 지금 조건은 `if: github.event_name != 'push'` 뿐(모든 PR 에서 돈다 · paths 필터 0)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: A(오빠 요청 — CI 비용) + C(반영). 핵심 한 줄: 모바일을 안 건드린 PR 은 Mobile Test 를 건너뛰고(통과 취급), Flutter 설치가 멈추면 5분에 끊는다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
Mobile Test 잡은 모든 PR 에서 Flutter 를 내려받아 analyze·test 를 돈다. 대부분의 PR 은 `clients/mobile` 을 안 건드리고, PR #936 에서는 `subosito/flutter-action@v2` 설치 단계가 14분 멈춰 잡 timeout 15분을 다 썼다. 두 가지를 한다. ⓐ변경 감지 잡(`changes`)을 하나 두고 Mobile Test 를 `needs: changes` + `if:` 로 거른다 — 워크플로 레벨 `paths` 필터는 쓰지 않는다(필수 검사로 지정된 잡이면 «Expected — 대기» 로 PR 을 막는다 · 잡 레벨 skip 은 통과 취급). required check 실측: `gh api repos/SecondWindStudio/byz-agents/branches/main/protection` 과 `…/rulesets` 둘 다 HTTP 403 「Upgrade to GitHub Pro or make this repository public」(arch#15 · 2026-10-08) — 비공개 리포·무료 플랜이라 보호 규칙 기능 자체가 없다 → 지금 필수 검사는 없다고 본다. 그래도 잡 레벨 방식은 나중에 필수 검사가 생겨도 안전하므로 그대로 간다. 감지는 외부 액션(dorny/paths-filter 등) 없이 `git diff --name-only <PR base sha> <PR head sha>` 로 하고, 대상 = `clients/mobile/` 아래 또는 `.github/workflows/ci.yml` 자신(워크플로를 고친 PR 은 모바일도 한 번 돈다). `workflow_dispatch` 는 항상 돈다. ★감지 실패는 조용히 건너뛰지 않는다★(#0 RULE): 감지 step 은 `set -euo pipefail` 로 실패하면 `changes` 잡이 빨갛게 실패해 CI 가 실패로 보인다(모바일 «skip» 으로 위장 0). ⓑ Set up Flutter step 에 `timeout-minutes: 5`. 모바일 코드는 `clients/mobile` 밖 경로 의존이 없다(pubspec path 의존 0 · lib 의 `../` import 는 전부 lib 안 — arch 실측).

## 사전검증
- 소환: 아니오
- 면제: CI 1파일 · 되돌림 1커밋 · 위험 2개(감지 실패 시 조용한 skip · 모바일이 밖 경로에 의존)를 카드에서 막음(fail-loud · 의존 0 실측) · planner 판정 451 GO — arch 서명 byz-harness-arch-claude#15

## 조사 근거
- `.github/workflows/ci.yml:543` mobile-test 잡(ops/main-base 사본 줄 · origin/main 은 561) · `if: github.event_name != 'push'` · `timeout-minutes: 15` · `.github/workflows/ci.yml:553` Set up Flutter step(origin/main 572) — step timeout 없음.
- `.github/workflows/ci.yml:4` `on:` — pull_request·push 의 `paths-ignore`(docs·design·md·.fable-team) · workflow_dispatch.
- branch protection·rulesets API 403(위 배경) — 필수 검사 없음.

## 구현 범위 (닫힌 목록)
1. `.github/workflows/ci.yml` 만:
   - 새 잡 `changes`(name: Detect Changes · `if: github.event_name != 'push'` · ubuntu-latest · timeout-minutes 5 · checkout fetch-depth 0) — step id `detect` 하나: pull_request 면 `${{ github.event.pull_request.base.sha }}`·`head.sha` 사이 `git diff --name-only` 에 `^clients/mobile/` 또는 `^\.github/workflows/ci\.yml$` 가 있으면 `mobile=true` · workflow_dispatch 면 `mobile=true` · 그 밖 `mobile=false` → `$GITHUB_OUTPUT` · `set -euo pipefail`(diff 실패 = 잡 실패) · 판단 근거(바뀐 파일 수·매칭 수)를 로그 1줄. outputs `mobile: ${{ steps.detect.outputs.mobile }}`.
   - `mobile-test`: `needs: changes` · `if: github.event_name != 'push' && needs.changes.outputs.mobile == 'true'` · 그 밖 무변경.
   - `Set up Flutter` step: `timeout-minutes: 5`.
   - 다른 잡 무변경.
2. 시험(리포 파일 추가 0 · RESULT 에 명령·출력 그대로): ①`actionlint .github/workflows/ci.yml` rc=0 ②ci.yml 에서 `changes` 잡 `detect` step 의 `run` 본문을 python(yaml)으로 뽑아, 임시 git 리포 3경우에 base/head sha·event 를 env 로 주고 실행 → (a)`clients/mobile/lib/x.dart` 변경 = `mobile=true` (b)`worker/x.py` 만 변경 = `mobile=false` (c)`.github/workflows/ci.yml` 변경 = `mobile=true` (d)없는 sha = rc≠0(fail-loud) (e)workflow_dispatch = `mobile=true`. 각 경우 `GITHUB_OUTPUT` 파일 내용을 RESULT 에.
3. RESULT 에 `if:` 식 검토 1줄: needs 가 실패하면 mobile-test 는 skip 되지만 changes 잡 실패로 워크플로 전체가 실패로 보인다(조용한 통과 0).

커밋은 자기 브랜치, **push 금지**. **금지**: 외부 paths-filter 액션 추가 · 워크플로 레벨 `paths` 필터 · 다른 잡 조건 변경 · 실제 PR/Actions 실행(CI 는 master 가 랜딩 PR 에서 1회).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `actionlint` rc=0 · 시험 2 (a)~(e) 기대값 전부 · RESULT 에 명령·출력.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: actionlint .github/workflows/ci.yml rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): 랜딩 PR 1회의 CI 에서 «Detect Changes» 결과 확인 — 그 PR 은 ci.yml 을 바꾸므로 Mobile Test 가 돌아야 한다(경우 c 의 실물) · 다음 비모바일 PR 1건에서 Mobile Test = skipped 확인(경우 b 의 실물 · 별도 PR 만들지 않고 다음 정상 PR 로) → planner 회신. 되돌림 = 1커밋 revert.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 1da5a43a3d951b258e2eb3b1e6fc6ad1d0455c78 (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#15 · 판정 451 · master #63468).
- 정본 영향 없음: CI 워크플로 1파일 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 17:05 — 대기→진행 · 좌석 byz-harness-nano-v451-ci-mobile-test-gate#0
세트: 5ce91ec4ce966f4bf65f249264f6a06de5823eed · 시험: actionlint -shellcheck= .github/workflows/ci.yml rc=0 · 이슈: 0
- 2026-10-08 17:19 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§65
