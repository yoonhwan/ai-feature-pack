# 인덱스: R64 block-destructive `mbox_ok` 가 상대경로 정본 mbox 송신을 글 싱크로 안 봄 — 본문 글자 오탐(r63b 설치 직후 원복 원인) (원장 R64 · master#20 쪽지 #66677)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → 요청 원장 R64(우선 높음 · r63b ㉠ 재설치의 선행)
- 상태: 대기
- 선행: r63b 랜딩(완료 · PR 1047 · main 7826b70515) — 홈 설치는 오탐 1건으로 원복됨(백업 `~/.claude/hooks/block-destructive.sh.bak-r63b-20261009`)
- 시험 입력: 키트 훅에 PreToolUse JSON 만 넣어 종료코드를 본다(`tests/harness/test_block_destructive.sh` 꼴 · 명령 실행 0 · 홈 훅 0) — 임시 git 리포 + 하위 폴더 cwd
- 기준값: arch#20 재현(origin/main 템플릿 · JSON cwd = `.worktrees/harness-ops`): `bash ../../.fable-team/comm/mbox.sh send a b 'redis-cli SET 금지'` = **2**(같은 본문 절대경로 = 0) · 같은 상대경로에 `rm -rf zz 인용` 본문 = **2**(★지금 홈 훅에서도 2 — r63b 이전부터 있던 같은 종류 오탐★) · 평범한 본문 = 0. 원인 = `mbox_ok`(템플릿 39-47행)가 «글자 그대로의 절대경로»만 정본으로 본다(판정 466 r2 결정: 변수·`..`·글롭 0).
## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: C(배포·반영 — 측정 조작 차단 훅을 전 좌석에 설치하려면 정상 쪽지 송신 오탐 0 이 선행) + A(오빠 절대지침 장치). 핵심 한 줄: 워크트리 안에서 상대경로로 정본 mbox 를 부르는 쪽지도 글로 취급되고, 정본이 아닌 스크립트는 여전히 글로 취급되지 않는다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
전역 Bash 훅 `block-destructive.sh` 의 `judge()`(판정 466)는 «정본 mbox 송신» 을 글 싱크로 보고 본문 글자를 검사에서 뺀다. 정본 판정 `mbox_ok(path, cwd)` 는 지금 경로가 `/` 로 시작하고 `..`·변수·글롭이 없을 때만 realpath 를 «JSON cwd 의 git 공통 루트 + `/.fable-team/comm/mbox.sh`» 와 비교한다. 그래서 워크트리 좌석이 흔히 쓰는 `bash ../../.fable-team/comm/mbox.sh send …` 는 정본이 아니라 «실행» 으로 취급돼, 본문에 인용한 `rm -rf`·`redis-cli SET` 같은 글자로 막힌다(r63b 설치 직후 원복 = 원장 R64). 이 카드는 상대경로를 «JSON cwd 기준 realpath» 로 정본 비교에 넣되, 명령 안에 디렉터리 이동(`cd`·`pushd`·`popd`)이 있으면 실제 실행 위치가 JSON cwd 와 달라지므로 상대경로 인정을 끈다(fail-closed). 절대경로 규칙은 그대로다.

## 사전검증
- 소환: 아니오 (설계 = 이 카드 · 판정 466 의 정본 비교 원칙(realpath 일치)은 그대로 · 상대 해석 기준만 추가)
- 구현 DA: ★예 1회★ — 전 좌석 Bash 훅의 글 싱크 자격을 넓히는 변경(우회 = 파괴 명령이 글로 통과). 질문 고정: Q1 상대경로 정본 = 0 · Q2 우회 닫힘(아래 차단 행) · Q3 절대경로·기존 91 행 회귀 0. bounded(새 요구 0 · 2 HOLD 면 리뷰 종료).

## 조사 근거 (main 7826b70515 · arch#20)
- 템플릿 `scripts/harness-install/fable-team/templates/hooks/block-destructive.sh:39-47` `mbox_ok` · `:108` `classify` 의 `g["mbox"] = … mbox_ok(words[1], cwd)` · `:114` `judge(cmd, cwd)` · `:139` JSON `cwd`.
- 시험 `tests/harness/test_block_destructive.sh`(138줄 · `run()` 의 JSON cwd = 임시 리포 `$T` 고정 · 92행 비정본 경로 차단 · 99행 절대경로 `..` 차단).
- 시험 `tests/harness/test_block_destructive_inject.sh`(mbox 픽스처 `$T/.fable-team/comm/mbox.sh` 있음).

## 구현 범위 (닫힌 목록)
1. 키트 템플릿 `scripts/harness-install/fable-team/templates/hooks/block-destructive.sh` 의 `mbox_ok` 와 그 호출만:
   - 절대경로(`/` 시작): 지금 규칙 그대로(`..`·변수·글롭 0 · realpath == want).
   - 상대경로(그 밖): ①변수·`~`·글롭·백틱 글자 0(지금 정규식 그대로) ②JSON `cwd` 가 문자열로 있어야 함(없으면 False) ③★명령 전체에 디렉터리 이동 단어가 없어야 함★ — 원문 `cmd` 에 `(^|[[:space:];&|(])(cd|pushd|popd)([[:space:]]|$)` 가 있으면 False(따옴표 안 글자라도 False = 더 엄격한 쪽) ④`os.path.realpath(os.path.join(cwd, path)) == want`(`..` 허용 — realpath 가 푼다 · 심링크도 realpath 가 따라가 정본과 같을 때만 참).
   - `judge` 가 원문 `cmd` 를 `classify`→`mbox_ok` 까지 넘기거나 «이동 단어 있음» 불리언 1개를 넘긴다(최소 변경 · 다른 판정 경로 불변).
   - 주석 1줄: 「상대경로 정본 = JSON cwd 기준 realpath 일치 · 명령에 cd/pushd/popd 가 있으면 실행 위치가 달라 인정 0(R64)」.
   - 줄 수 증가 6줄 이하 · bash 3.2 셔뱅 그대로(파이썬 부분 변경).
2. `tests/harness/test_block_destructive.sh` — `run()` 에 선택 인자 «JSON cwd» 1개(없으면 `$T`) · 200줄 이하 · 행 추가:
   - 통과(0): cwd=`$T/a/b` 에서 `bash ../../.fable-team/comm/mbox.sh send x y 'rm -rf zz 인용'` · cwd=`$T` 에서 `bash .fable-team/comm/mbox.sh send x y 'git branch -D x 인용'` · cwd=`$T/a/b` 에서 정본을 가리키는 심링크(`$T/a/link.sh → $MB`) `bash ../link.sh send x y 'rm -rf zz'`.
   - 차단(2): `cd /tmp && bash ../../.fable-team/comm/mbox.sh send x y 'rm -rf zz'`(이동 단어) · 다른 루트(두 번째 임시 리포 `$T2/.fable-team/comm/mbox.sh`)를 상대경로로 `bash ../../<T2 기준>/.fable-team/comm/mbox.sh send …`(realpath ≠ want) · 다른 스크립트를 가리키는 심링크(`$T/a/evil.sh → /tmp/<임시>/x.sh`) `bash ../evil.sh send x y 'rm -rf zz'` · `bash $D/../.fable-team/comm/mbox.sh send …`(변수) · JSON 에 `cwd` 없음 + 상대경로.
   - 기존 92·99행 그대로(비정본 절대경로 · 절대경로 `..` 차단 유지).
   - 변이: 이동 단어 검사를 빼면 `cd /tmp && …` 행 FAIL · 상대경로 분기를 빼면 첫 통과 행 FAIL.
3. `tests/harness/test_block_destructive_inject.sh` — 통과 1행: cwd=`$T/a/b` 에서 `bash ../../.fable-team/comm/mbox.sh send x y 'redis-cli SET 금지 /dev/bubble-replay'` = 0.
4. 기존 시험 PASS: 위 2개 전체 · `bash -n` 템플릿.
커밋은 자기 브랜치, **push 금지**. **금지**: 홈 `~/.claude/hooks/` 쓰기·settings.json · PATTERN·STAGE·INJECT 블록·다른 싱크 판정 변경.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 위 시험 rc=0 · 구현 DA 판정문 APPROVE(또는 2 HOLD 뒤 arch 서명).
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_block_destructive.sh rc=0 · 이슈: 0` (+ `bash tests/harness/test_block_destructive_inject.sh rc=0`).
- 루트 지침(governance §9 · BOOT 19 · 판정 514·532): 완료 조건을 다 채운 «그 턴에» 증거 줄 기록 + master 에 머리 `[완료·휴식]` 1통 → 쉰다.
- ★랜딩 뒤 master 집행(카드 밖 · r63b 재설치 · §93 7단계 그대로)★: 백업 → 키트 → 홈 cp+cmp → 셔뱅 재생(R64 원 명령 `bash ../../.fable-team/comm/mbox.sh send … 'redis-cli SET …'` 을 JSON cwd=워크트리로 = 0 포함) → 첫 도구 호출 실측(워크트리 좌석 1곳의 상대경로 쪽지 1통 포함) → 오탐 1건이면 즉시 원복.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 7826b7051566c496b999b35984aa0b51957911c7 (spawn 2026-10-09)
- 2026-10-09 02:1x — 대기/ 생성 (byz-harness-arch-claude#20 · 원장 R64 · master#20 쪽지 #66677 · arch 재현: 상대경로 본문 오탐 = r63b 이전부터 있던 같은 종류(rm -rf 인용도 2)).
- 정본 영향 없음: 하네스 훅 템플릿·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-09 02:03 — 대기→진행 · 좌석 byz-harness-nano-r63e-mbox-ok-relative-path#0

## 결과 (나노 RESULT r3 · master#20 옮김 2026-10-09)
세트: 4f5a1383c82d956ed5edc07c44d6af3d0a97fc09 · 시험: bash tests/harness/test_block_destructive.sh rc=0 · 이슈: 0
정본 영향 없음: 하네스 훅 템플릿·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-09 02:23 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§95
