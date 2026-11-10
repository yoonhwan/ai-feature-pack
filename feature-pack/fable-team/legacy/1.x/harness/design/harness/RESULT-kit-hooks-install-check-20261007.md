# RESULT: 키트 홈 훅 2개 추가 + install 훅 등록 확인 줄 (kit-hooks-install-check)

골의 축: C — 머신별 「반영됨」 행의 근거(설치 출력이 «훅 파일이 키트와 같은가 · settings 에 등록됐는가» 를 찍는다).
브랜치 `nano/kit-hooks-install-check` · base `828b243ab2` · push 없음.

## 변경 (인덱스 §구현 범위 3건 + RESULT)
1. `scripts/harness-install/fable-team/templates/hooks/block-destructive.sh` 신규 — 홈 `~/.claude/hooks/block-destructive.sh` 바이트 복사(`cmp` 동일 · 실행 비트 유지 · 내용 수정 0).
2. `scripts/harness-install/fable-team/install.sh` — dry-run·apply 공통 읽기 전용 출력: templates/hooks 각 `*.sh` 마다 `hook <이름> home=<same|diff|absent> settings=<registered|absent>` + 끝 요약 `hooks same= diff= absent= registered=`. 홈 훅 복사·settings 편집 0.
3. `tests/harness/test_install_hook_check.sh` 신규 — mktemp 홈 ⓐabsent ⓑsame/registered ⓒ1바이트 diff ⓓsettings 없음, rc=0, 기존 줄(machine=·files=·kit_sha=) 유지, dry-run 에서 dest·홈 `.claude` 미생성, block-destructive 템플릿==홈 파일.

## 검증
- `bash -n install.sh` OK.
- `bash tests/harness/test_install_hook_check.sh` → ALL PASS (17 PASS · rc=0).
- 기존 `tests/harness/test_*.sh` 20개: 19개 rc=0. `test_branch_candidates.sh` 는 120초 제한에서 timeout, 재실행(257초)에서 `FAIL 브랜치 수 변함 1108 -> 1109` — 이 시험이 «실 리포 전체 브랜치 수»를 시작·끝에 비교하는데 실행 중 다른 좌석이 브랜치를 1개 만든 것(공유 리포 경합). 내 변경(install.sh·훅 템플릿·신규 시험)과 접점 없음 — master 확인 필요(리포가 조용할 때 재실행).
- FE Next.js 이슈(에러 오버레이·console.error): 해당 없음(셸 키트·시험만).

## 이 Mac 실제 홈 대상 dry-run (2026-10-07, machine=MacBook-Pro, files=78, kit_sha=4a0be49566dc)
```
hook block-destructive.sh home=same settings=registered
hook boot-read-gate.sh home=diff settings=registered
hook context-distill-gate.sh home=same settings=registered
hook context-hygiene-clean.sh home=same settings=absent
hook da-live-evidence-gate.sh home=absent settings=absent
hook ft-session-restore.sh home=absent settings=absent
hook ft-worker-guard.sh home=absent settings=absent
hook gh-issue-author-guard.sh home=same settings=registered
hook orchestration-gate.sh home=diff settings=registered
hook orchestration-turn-reset.sh home=same settings=registered
hook pre-compact-writethrough.sh home=absent settings=absent
hook spawn-route-gate.sh home=absent settings=absent
hook teammate-idle-gc.sh home=same settings=registered
hook track-lifecycle-gate.sh home=absent settings=absent
hooks same=6 diff=2 absent=6 registered=7
```
읽는 법: 홈과 키트가 다른 훅 2개(`boot-read-gate.sh`·`orchestration-gate.sh` — 둘 다 등록돼 «실제로 도는» 중)가 RELEASE 0.4 머신 표의 «반영 안 됨» 후보. absent 6개 중 settings 미등록은 정상일 수 있음(팀 한정 훅) — 판단은 master.
