# RESULT: Issue·PR 코멘트 쓰기를 Tank 봇(byz-tank) 이름으로 — 래퍼 + 가드

골 축: 하네스 6-b(오케 개선요청 접수·협의) · 원문 7. 인덱스 `design/teams/harness/indices/진행/gh-as-tank-wrapper-guard.md` (+ 범위 보강 쪽지 #58358).

## 산출 (브랜치 `nano/gh-as-tank-wrapper-guard` · push 안 함)

| 파일 | 내용 |
|---|---|
| `scripts/fable-team-bin/ft-gh-as-tank.sh` | `create\|comment\|label\|close\|reopen\|pr-comment\|pr-create`. 기본 dry-run(gh 명령만 출력) · `--apply` 만 실행. 토큰 없음 exit 2(폴백 0) · 실행 전 `gh api user` 주인 ≠ byz-tank 이면 REJECT(exit 1). create 는 `ft-issue-create-pair.sh` 재사용. **pr-create 는 dry-run 전용 — Tank(triage) 의 PR 생성 권한 미확인, `--apply` 는 exit 2.** PR merge 는 대상 아님 |
| `scripts/harness-install/fable-team/templates/hooks/gh-issue-author-guard.sh` | PreToolUse Bash 가드. 차단: `gh issue` 쓰기(create·comment·edit·close·reopen…) · `gh pr comment` · 쓰기용 `gh api …/issues`. 통과: 래퍼·쌍 스크립트 경유 · 조회 · `gh pr create/merge/checkout/diff/view`. 명령 «위치»의 gh 만 판정(따옴표·heredoc 본문 제외, `; && \|` 개행 분리, `bash -c`/`eval` 재귀). 파싱 불가 입력은 fail-open(sibling 훅 관례) |
| `tests/harness/test_gh_as_tank.sh` | 가짜 gh(PATH 선두)로 실제 GitHub 호출 0. `fail=0` · PASS 79 |

## 시험 값 (2026-10-07)
- dry-run: create·comment·label·close·reopen·pr-comment·pr-create 7종 명령 출력 일치 · gh 호출 0
- 토큰 없음 `--apply` 6동작 전부 rc=2 · gh 호출 0 · 작성자 불일치(yoonhwan) rc=1 REJECT · 쓰기 gh 0건
- `--apply`(가짜 gh) 6동작 rc=0 · Tank 토큰으로 gh 실행 · 토큰 값 stdout/stderr 미출력
- 가드: 차단 18 · 통과 18 · 비-Bash 도구 통과 2 · JSON 아님 fail-open · `bash -n` 두 스크립트 OK

## 설치·미확인 (ops 소관)
- 가드 훅 `~/.claude/settings.json` PreToolUse Bash 등록 = 오빠 승인 후 ops. 이 카드는 설치하지 않았다.
- Tank 의 PR 생성 권한 미확인 → pr-create 실행 경로 없음. 확인되면 `--apply` 허용을 별도 카드로.
- 실제 `--apply` 실행(진짜 gh)은 하지 않았다(카드 금지) — 첫 실전은 ops 가 시험 Issue 한 건으로.

## 전파 문구 제안 (ops 가 반영 — 나는 문서·~/.claude 를 고치지 않았다)

**`COMM-GUIDE-BOOT.md` §14(하네스 조회) 뒤에 한 줄 추가안**
> 15. **GitHub 쓰기는 Tank 래퍼로만**: Issue 생성·코멘트·라벨·close·reopen·PR 코멘트는 `gh` 직접 호출 금지(작성자가 오빠 계정으로 올라간다) — `bash <루트>/scripts/fable-team-bin/ft-gh-as-tank.sh <create|comment|label|close|reopen|pr-comment> … --apply`(기본 dry-run · Issue 생성은 `ft-issue-create-pair.sh` 규약 그대로). 조회(`gh issue view/list`)는 gh 그대로. 훅(`gh-issue-author-guard.sh`)이 설치되면 직접 호출은 차단된다.

**글로벌 `~/.claude/CLAUDE.md` · 스킬(fable-team·tmuxc)용 한 줄**
> Issue·PR 코멘트 쓰기는 `ft-gh-as-tank.sh`(byz-tank 이름)로만 — `gh issue create/comment/edit/close`·`gh pr comment` 직접 호출 금지.
