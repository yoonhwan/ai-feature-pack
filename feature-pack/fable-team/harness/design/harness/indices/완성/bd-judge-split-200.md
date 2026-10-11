# 인덱스: block-destructive 훅 209줄 → 판정기(파이썬)를 옆 파일로 분리 · 두 파일 200줄 이하 · 동작 바이트 동일 (planner 판정 592 순서 ② · master#20 쪽지 #66754)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → planner 판정 592 순서 ②(① gate-hook-kit-equals-home 닫힘 §96 · PR 1049)
- 상태: 대기
- 선행: §95 r63e 랜딩·홈 설치(완료 · PR 1048 · 홈 = main 키트 cmp 동일)
- 시험 입력: 기존 `tests/harness/test_block_destructive.sh` · `tests/harness/test_block_destructive_inject.sh` · `tests/harness/test_install_hook_check.sh`(키트 훅에 PreToolUse JSON 만 · 명령 실행 0 · 홈 파일 미접촉)
- 기준값: origin/main `4f5009a926` 키트 `scripts/harness-install/fable-team/templates/hooks/block-destructive.sh` = **209줄**(200줄 규칙 초과) · 그중 파이썬 판정기 heredoc 본문 = 26–146행(121줄). test_block_destructive `blocked=74 pass=23 fail=0` · test_block_destructive_inject `block=22 pass=32 mutant=15 fail=0`.

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「RELEASE-<ver>.md 1장 + 머신별 「반영됨 <machine> <sha>」 행 전부」.
골의 축: C(업그레이드·반영 — 전 좌석 Bash 훅을 200줄 규칙 안으로) + 원문 5(머신 독립 배분 — 키트를 받는 머신이 두 파일을 같이 받고, 홈 정합 검사가 두 파일을 다 본다). 핵심 한 줄: 판정 결과는 한 글자도 안 바뀌고, 파일만 둘로 나뉜다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
전역 Bash 훅 `block-destructive.sh`(홈 `~/.claude/hooks/` 에 설치 · settings.json 이 `bash /Users/yoonhwan/.claude/hooks/block-destructive.sh` 로 부름)는 판정 466·§93·§95 를 거치며 209줄이 됐다(CLAUDE.md 파일 200줄 규칙 초과). 그중 121줄이 `judge()` 안의 파이썬 heredoc(«글자로만 들어 있는» 파괴 명령을 걸러 내는 판정기)이다. 이 카드는 그 파이썬 본문을 같은 폴더의 `block-destructive-judge.py` 로 «글자 그대로» 옮기고, 훅은 `python3 "<훅과 같은 폴더>/block-destructive-judge.py" "$CMD" "$INPUT"` 로 부르게 바꾼다. 판정기 파일이 없거나 실패하면 지금과 똑같이 `EFFECTIVE=$CMD`(명령 전체에 PATTERN — 더 엄격한 쪽)로 떨어진다. 시험의 변이 사본은 임시 폴더에 훅만 복사하므로 판정기도 같이 복사해야 지금과 같은 결과가 나온다. `install.sh` 의 홈 정합 보고는 지금 `templates/hooks/*.sh` 만 보므로 `.py` 도 보게 한다(안 보면 다른 머신에서 판정기만 어긋나도 아무도 모른다).

## 사전검증
- 소환: 아니오 — 구조 이동(파이썬 본문 바이트 동일 이동 + 호출 1줄)이고 판정 규칙 변경 0. arch 서명 byz-harness-arch-claude#21.
- 최종 DA: ★예 1회(완성 이동 때)★ — 전 좌석 Bash 훅이고 홈 설치가 뒤따른다. 질문 고정: Q1 판정 동일(본문 바이트 동일 · 기존 시험 수 동일) · Q2 판정기 경로 해석(홈 `bash <절대경로>` 호출 · 심링크 · 파일 없음 = fail-closed) · Q3 install.sh·홈 정합 시험이 두 파일을 다 보는가. bounded(새 요구 0 · 2 HOLD 면 리뷰 종료 → arch 서명).

## 조사 근거 (origin/main `4f5009a926` · arch#21)
- 훅 구조: 1–23 머리·PATTERN · 24–148 `judge()`(25 `python3 - "$@" <<'PYEOF'` · 26–146 파이썬 본문 · 147 `PYEOF` · 148 `}`) · 149 `EFFECTIVE=$(judge "$CMD" "$INPUT" 2>/dev/null) || EFFECTIVE=$CMD` · 151–156 PATTERN 차단 · 158–181 INJECT · 183–208 STAGE · 209 `exit 0`.
- 파이썬 본문은 `sys.argv[1]`(명령)·`sys.argv[2]`(JSON 원문)만 쓴다 — 표준입력 0 → 파일 실행으로 옮겨도 입력 계약 같음.
- 홈 등록 = `bash /Users/yoonhwan/.claude/hooks/block-destructive.sh` → `${BASH_SOURCE[0]}` 가 절대경로(bash 3.2 지원).
- 변이 사본: `tests/harness/test_block_destructive_inject.sh` 의 `mut()`(36–41행)이 `$T/m1.sh`~`m7.sh` 로 훅만 복사 — 변이 대상 글자는 전부 셸 INJECT 구간(108–116행)이라 판정기 쪽 변이는 0. `test_block_destructive.sh` 는 변이 사본 0(BD_HOOK 덮어쓰기만).
- `install.sh` 59–72행: `for tpl in "$KIT"/templates/hooks/*.sh` 로 홈과 cmp · settings.json 등록(`hooks/<이름>`) 여부 보고. 복사는 `--apply` 때 `bin`·`templates` 전체(34·46행) — 판정기 파일도 자동으로 실린다.
- ★arch#21 사본 실측(이 처방 그대로 · origin/main `4f5009a926`)★: 훅 **87줄** · 판정기 **123줄** · 본문 diff 0 · test_block_destructive blocked=74 pass=23 fail=0 rc=0 · inject block=22 pass=32 mutant=15 fail=0 rc=0 · JSON 31행(§95 재현 세트) 불일치 0 · 훅만 다른 폴더에 복사(판정기 없음) → `echo '<파괴 명령 인용>'` = 2(판정기 있으면 0) = fail-closed 확인.
- 알고 둔 경계: 훅을 «심링크»로 설치하면 `${BASH_SOURCE[0]}` 가 링크 폴더라 판정기를 못 찾아 fail-closed(과차단) — 실측 2. 설치는 cp(install.sh `--apply` = `cp -p`)라 해당 없음 · 심링크 설치는 이 카드 밖.
- `tests/harness/test_install_hook_check.sh` 52–60행: block-destructive 템플릿 == 홈 파일 cmp(홈 파일 있을 때만).

## 구현 범위 (닫힌 목록 — 이것만)
커밋 2개 · 자기 브랜치 · **push 금지**.
1. `[structure]` 커밋:
   - 새 `scripts/harness-install/fable-team/templates/hooks/block-destructive-judge.py` = 머리 주석 2줄(`# block-destructive.sh 의 판정기(판정 466) — 훅이 python3 <이 파일> <명령> <JSON 원문> 으로 부른다.` · `# 출력 = PATTERN 을 볼 글자. 예외는 Inelig → 명령 전체(fail-closed).`) + 기존 26–146행 «바이트 그대로». 실행 비트 불요.
   - `block-destructive.sh` 24–148행(`judge() {` … `}`)을 아래 3줄로 바꾼다. 149행 이하 0 변경.
     ```
     # 판정기 = 같은 폴더 block-destructive-judge.py (판정 466 · 없거나 실패하면 아래 || 로 명령 전체에 PATTERN — fail-closed)
     JUDGE="$(dirname "${BASH_SOURCE[0]}")/block-destructive-judge.py"
     judge() { python3 "$JUDGE" "$@"; }
     ```
   - `tests/harness/test_block_destructive_inject.sh`: `T="$(mktemp -d)"` 바로 다음 줄에 `cp "$(dirname "$HOOK")/block-destructive-judge.py" "$T/"` 1줄(변이 사본이 판정기를 찾게) · 없어도 지금 15행 결과는 같다(arch 실측 — 변이가 전부 INJECT 구간) · 변이 사본이 실제 훅과 같은 판정기로 재게 하는 충실도 줄).
2. `[test]` 커밋(홈 정합 검사가 두 파일을 다 보게):
   - `scripts/harness-install/fable-team/install.sh` 61행 `for tpl in "$KIT"/templates/hooks/*.sh; do` → `for tpl in "$KIT"/templates/hooks/*.sh "$KIT"/templates/hooks/*.py; do`. `.py` 행의 settings 칸은 `s_state="n/a"`(등록 대상 아님 — `case "$name" in *.py) …` 1줄). 합계 줄 그대로.
   - `tests/harness/test_install_hook_check.sh` 52–60행 꼴로 `block-destructive-judge.py` 템플릿 존재 + 홈 파일 있으면 cmp 1묶음 추가.

**금지**: 홈 `~/.claude/hooks/` · `.claude/settings.json` 수정 · PATTERN·STAGE·INJECT·판정기 본문 글자 변경 · 시험 기대값(표 수) 변경 · 다른 훅.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `wc -l` 훅 ≤ 200 · 판정기 ≤ 200.
- 본문 동일: `diff <(git show origin/main:scripts/harness-install/fable-team/templates/hooks/block-destructive.sh | sed -n '26,146p') <(tail -n +3 scripts/harness-install/fable-team/templates/hooks/block-destructive-judge.py)` 출력 0.
- `bash tests/harness/test_block_destructive.sh` rc=0 · `SUMMARY blocked=74 pass=23 … fail=0`(기준값과 같은 수).
- `bash tests/harness/test_block_destructive_inject.sh` rc=0 · `block=22 pass=32 mutant=15 fail=0`.
- `bash tests/harness/test_install_hook_check.sh` rc=0 (홈은 아직 옛 판이라 두 cmp 는 «다름»으로 나와야 정상 — 이 경우 그 두 줄만 FAIL 이면 RESULT 에 그대로 적고 rc 를 함께 적는다 · 홈 설치 뒤 master 가 재실행해 rc=0).
- `bash scripts/harness-install/fable-team/install.sh --home "$HOME" | grep 'block-destructive'` 에 두 줄(`.sh` · `.py settings=n/a`).
- 판정기 없음 = fail-closed 확인: 훅만 임시 폴더에 복사해 `bash ../../.fable-team/comm/mbox.sh send a b '평범한 보고'` 꼴 글 싱크가 아니라 `echo 'rm -rf zz'`(판정기 있으면 0) 를 넣으면 = 2.
- RESULT 에 위 출력 복붙 + 카드 증거 줄(필수 · 시험 칸은 명령 1개): `세트: <40hex> · 시험: bash tests/harness/test_block_destructive.sh rc=0 · 이슈: 0`.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 랜딩 뒤 홈 설치 (master 집행 · 카드 밖 · 589 조건 · 앞 단계 값이 다르면 멈추고 보고)
① PR(origin/main · `--body-file`) 병합. ② 홈 현재 = main 이전 키트(`4f5009a926`) 훅과 cmp 동일 확인 → 백업 `cp ~/.claude/hooks/block-destructive.sh ~/.claude/hooks/block-destructive.sh.bak-bdsplit-20261009`. ③ ★판정기 먼저★ `block-destructive-judge.py` cp+cmp → 그다음 훅 cp+cmp(순서가 바뀌면 그 사이 모든 Bash 가 fail-closed 로 과차단). ④ 셔뱅 그대로(`/bin/bash`) 홈 설치본 JSON 재생: ★평소 명령 — R64 원 명령(`bash ../../.fable-team/comm/mbox.sh send … 'redis-cli SET …'`, JSON cwd=워크트리) = 0 · `echo 'rm -rf zz'` = 0 · `git status` = 0 · `ls` = 0★ · 차단 `rm -rf /tmp/zz` = 2 · `cd; bash ../../.fable-team/comm/mbox.sh send … '<파괴 명령 인용>'` = 2 · `redis-cli PUBLISH ch x` = 2 · `git add -A` = 2. ⑤ 적용 뒤 «첫 도구 호출» 실측 — 평범한 Bash 1회 + 다른 좌석 1곳의 다음 Bash·mbox 송신 정상. ⑥ ★오탐 1건이면 즉시 원복★(백업 훅 cp · 판정기 파일은 남겨도 무해 — 옛 훅은 안 부름 · 원장 기록 · 카드 반송). ⑦ `test_install_hook_check.sh` 재실행 rc=0 + 완료 보고 = 랜딩 sha + 재생 행 rc.

## 상태
- base_sha: 4f5009a926c6f185842a0962df9d98f97056ec7f (spawn 2026-10-09)
- 2026-10-09 — 대기/ 생성 (byz-harness-arch-claude#21 · planner 판정 592 ② · master#20 시작 신호 #66754). spawn 은 master 판단(`--base origin/main`).
- 정본 영향 없음: 하네스 키트 훅·키트 설치 보고·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-09 02:35 — 대기→진행 · 좌석 byz-harness-nano-bd-judge-split-200#0

## 결과 (나노 RESULT · master#20 옮김 2026-10-09)
세트: 7e8b08cb7e3228c1f0cea3aaa781b173c08814ba · 시험: bash tests/harness/test_block_destructive.sh rc=0 · 이슈: 0
정본 영향 없음: 하네스 훅 템플릿·설치 스크립트·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-09 02:44 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§97
