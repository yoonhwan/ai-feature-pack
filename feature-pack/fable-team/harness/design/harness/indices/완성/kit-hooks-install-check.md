# 인덱스: 키트에 홈 훅 2개 추가 + install 출력에 «훅 등록 확인 줄» (반영 행의 근거)
<!-- ledger: design/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「RELEASE-<ver>.md 1장 + 머신별 「반영됨 <machine> <sha>」 행 전부」.
골의 축: C. 핵심 한 줄: install.sh 는 키트를 `$HOME/.fable-team/<팀>/` 에 복사만 하고 «실제로 도는 훅»(홈 `~/.claude/hooks` + `~/.claude/settings.json` 등록)은 보지 않는다 — 머신별 「반영됨」 행을 정직하게 쓰려면 설치 출력이 «훅 파일이 키트와 같은가 · settings 에 등록됐는가» 를 찍어야 한다. 출처: arch 58611 · master 발주 58634.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
`scripts/harness-install/fable-team/install.sh`(기본 dry-run · `--apply` 때만 복사 · `--home` 으로 홈 지정 · 출력 끝에 `machine=… files=… kit_sha=…`)는 머리 주석대로 원격 접속·launchd·글로벌 설정을 건드리지 않는다 — 이 원칙은 유지한다(settings.json 편집 0). 훅 템플릿 폴더 `scripts/harness-install/fable-team/templates/hooks/` 에는 gh 가드(`gh-issue-author-guard.sh`)가 이미 홈 설치본과 바이트 같다(arch 실측 cmp). 홈 `~/.claude/hooks/block-destructive.sh`(파괴 명령 차단 · 전역 PreToolUse)는 리포 추적본이 하나도 없다(git ls-files 0). settings.json 의 훅 등록은 `"command": "$HOME/.claude/hooks/<이름>.sh"` 형태다.

## 구현 범위 (이 셋만 — 닫힌 목록)
1. `scripts/harness-install/fable-team/templates/hooks/block-destructive.sh` 신규 = 홈 `~/.claude/hooks/block-destructive.sh` 를 «바이트 그대로» 복사(읽기만 · 내용 수정 0 · 실행 비트 유지).
2. `scripts/harness-install/fable-team/install.sh` 에 확인 출력 추가(dry-run·apply 둘 다 · 읽기 전용): templates/hooks 의 각 `*.sh` 마다 한 줄 `hook <이름> home=<same|diff|absent> settings=<registered|absent>` — home = `<HOME>/.claude/hooks/<이름>` 과 cmp · settings = `<HOME>/.claude/settings.json` 안에 `hooks/<이름>` 문자열 존재(파일 없으면 absent). 맨 끝 요약 한 줄 `hooks same=<n> diff=<n> absent=<n> registered=<n>`. 이 출력은 홈 훅을 «복사하지 않는다»(복사·등록은 머신별 master 집행).
3. 시험 `tests/harness/test_install_hook_check.sh`(신규): mktemp 홈에 ⓐ훅 파일 없음 → absent ⓑ키트와 같은 파일 + settings 에 등록 → same/registered ⓒ한 바이트 다른 파일 → diff ⓓsettings.json 없음 → settings=absent · 설치 rc=0 · 기존 출력 줄(machine=·files=·kit_sha=)이 그대로 있는지. block-destructive 템플릿이 홈 파일과 cmp 같은지(홈 파일이 있는 머신에서만 · 없으면 skip 줄 출력).
커밋은 자기 브랜치, **push 금지**. **금지**: `~/.claude` 쓰기 · settings.json 편집 기능 추가 · block-destructive 내용 변경(패턴·메시지 — 다음 단위) · 다른 훅 템플릿 수정 · bin/ 수정(옆 카드 kit-bin-adopt 몫).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_install_hook_check.sh` rc=0 · 기존 `tests/harness/test_*.sh` 전부 rc=0 · install.sh `bash -n` OK.
- 이 Mac 실제 홈 대상 dry-run 출력의 hook 줄 전부를 RESULT `design/harness/RESULT-kit-hooks-install-check-20261007.md` 에 붙인다(현재 반영 상태 실측 = RELEASE 0.4 머신 표의 근거).
- 변경 파일 = 위 3개 + RESULT 뿐.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 828b243ab2070bd12d3537703f2d8d8cd1da8e76 (spawn 2026-10-07)
- base: 최신 origin/main(0304b966f7 이후).
- 2026-10-07 — 대기/ 생성 (byz-harness-arch-claude#5 · master 발주 58634). 옆 카드 kit-bin-adopt 와 파일 겹침 0 → 동시 진행 가능.
- 정본 영향 없음: 하네스 설치 키트·시험만 — docs/architect 제품 정본 변경 없음
- 2026-10-07 12:53 — 대기→진행 · 좌석 byz-harness-nano-kit-hooks-install-check#0
- 2026-10-07 13:33 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§24
