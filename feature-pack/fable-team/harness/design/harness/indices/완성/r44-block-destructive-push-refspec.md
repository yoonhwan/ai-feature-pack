# 인덱스: block-destructive 훅 — 원격 브랜치를 덮거나 지우는 push 꼴(`+<ref>` 강제 · `:<ref>` 삭제 · `--delete`/`-d` · `--mirror`)도 강제 push 와 같이 차단 (R44)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → R44(byz-harness-arch-claude#16 v466 독립 재현 반례 · master#17 #63966 접수 지시 · 우선순위 planner)
- 상태: 대기
- 선행: 없음 — origin/main 최신에서 브랜치(판정 466 PR #962 병합본 위 · 홈 훅 = origin/main 키트 사본 cmp 같음 · arch#16 확인)
- 시험 입력: 훅에 넣는 PreToolUse JSON 문자열만(기존 `tests/harness/test_block_destructive.sh` 의 `blk`/`pas` 꼴) — 실제 push·원격 쓰기 0
- 기준값: origin/main 키트 훅 `PATTERN` 의 push 항목 = `git +push[^&|;]*(--force|-f\b)` → `git push origin +main`·`git push origin :main`·`git push --delete origin x`·`git push -d origin x`·`git push --mirror origin` 전부 exit 0(옛 훅·v466 훅 공통 · v466 반례 재현 §73 ⑤).

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 6-b(개선요청 접수 — R44) + C(반영 — 홈 훅 설치). 핵심 한 줄: 전역 HIL 하드 룰의 «force push» 는 플래그 이름이 아니라 «원격 브랜치를 덮거나 지우는 push» 다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
전역 하드 룰은 브랜치 삭제·force push 를 사람 승인 없이 금지하고, `block-destructive.sh` 가 그것을 `PATTERN` 정규식으로 강제한다. 그런데 push 항목은 `--force`·`-f` 글자만 본다. git 에는 같은 효과를 내는 다른 꼴이 있다: refspec 앞 `+`(그 ref 만 강제 덮어쓰기) · refspec 앞 `:`(원격 ref 삭제) · `--delete`/`-d`(원격 ref 삭제) · `--mirror`(로컬에 없는 원격 ref 를 전부 삭제하고 나머지를 강제 덮어씀). `--force-with-lease`·`--force-if-includes` 는 이미 `--force` 글자를 포함해 막힌다(유지). 고칠 곳은 `PATTERN` 의 push 항목 한 곳이다 — v466 의 «구간 판정·글 싱크» 로직은 그대로라, 쪽지 본문·커밋 메시지 안의 같은 글자는 계속 통과한다. 차단만 늘어나는 변경이라 안전 방향이다(오탐 위험: `HEAD:refs/heads/x` 처럼 refspec 안쪽의 `:` 는 앞이 공백이 아니라 걸리지 않게 — 아래 정규식).

## 사전검증
- 소환: 아니오
- 면제: `PATTERN` push 항목 1개에 대안 4개 추가 · 차단만 늘어남(통과 범위 축소 0 → 우회 신설 위험 0) · v466 판정 로직 무변경 · 되돌림 1커밋 — arch 서명 byz-harness-arch-claude#16

## 조사 근거
- `scripts/harness-install/fable-team/templates/hooks/block-destructive.sh:18` `PATTERN`(origin/main · v466 병합본) — push 항목 `git +push[^&|;]*(--force|-f\b)`.
- origin/main 시험 `test_block_destructive.sh`(ops/main-base 에 없음 · 같은 바이트 = `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/feature-main/tests/harness/test_block_destructive.sh:38`) ~`:39` push 차단 2행(`--force` · `-f`) · `:101` 커밋 메시지 안 `--force` 글자 통과.
- 판정서 §73 ⑤(design/harness/OPS-VERDICTS-20261006.md) — `git push origin +main` 옛·새 훅 둘 다 exit 0.

## 구현 범위 (닫힌 목록 — 키트 사본만 고치고 홈 설치는 master)
1. `scripts/harness-install/fable-team/templates/hooks/block-destructive.sh` `PATTERN` 의 push 항목을 `git +push[^&|;]*(--force|-f\b|--mirror|--delete|[[:space:]]-d\b|[[:space:]]\+[^[:space:]]|[[:space:]]:[^[:space:]])` 로 바꾼다(다른 항목·판정 로직·메시지 무변경 · 주석 1줄: R44).
2. `tests/harness/test_block_destructive.sh` 에 행 추가:
   - `blk`(exit 2): `git push origin +main` · `git push origin +HEAD:main` · `git push origin :main` · `git push --delete origin x` · `git push -d origin x` · `git push --mirror origin` · `git push --force-with-lease origin x`(기존 동작 고정).
   - `pas`(exit 0): `git push origin main` · `git push -u origin feat/x` · `git push origin HEAD:refs/heads/x` · `git push --dry-run origin x` · `git commit -m "git push origin +main 금지 기록"` · 정본 mbox send 본문에 `git push --delete` 인용.
3. 홈 훅·`~/.claude/settings.json` 무변경.

커밋은 자기 브랜치, **push 금지**. **금지**: 다른 `PATTERN` 항목 변경 · v466 글 싱크·2단 판정 로직 변경 · 실제 git push 실행.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_block_destructive.sh` rc=0(기존 행 전부 + 새 13행) · `bash -n` · 키트 훅 ≤ 180줄 · `bash tests/harness/test_kit_bin_sync.sh` rc=0.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_block_destructive.sh rc=0 · 이슈: 0`.
  - 나노 워크트리(origin/main 기준)에 이 카드가 없으면 RESULT 맨 끝 줄에 `카드 증거 줄: 세트: <40hex> · 시험: bash tests/harness/test_block_destructive.sh rc=0 · 이슈: 0` 을 복붙 가능한 그대로 쓴다 — master 가 카드 끝에 옮기고 `ft-nano-evidence-check.sh` 로 확인(master#16 #63821).
- 랜딩 뒤 master 집행(카드 밖): 홈 `~/.claude/hooks/block-destructive.sh` 에 키트 사본 cp + cmp(판정 343) · 설치 뒤 첫 Bash 호출 1회로 훅 동작 확인 · 원장 R44 상태 = 반영 sha.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>` — 판정 절에 「대상 카드: r44-block-destructive-push-refspec」 줄.

## 상태
- base_sha: d69c75053987bb3a3506fe25341ff2027627171e (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#16 · R44 · 선작성 — 착수 순서 planner).
- 정본 영향 없음: 전역 안전 훅의 push 차단 항목과 시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 20:16 — 대기→진행 · 좌석 byz-harness-nano-r44-block-destructive-push-refspec#0
세트: f2c63e4bb6e5eaf58f64b3a471703ead84fd96a9 · 시험: bash tests/harness/test_block_destructive.sh rc=0 · 이슈: 0
- 2026-10-08 20:31 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§75
