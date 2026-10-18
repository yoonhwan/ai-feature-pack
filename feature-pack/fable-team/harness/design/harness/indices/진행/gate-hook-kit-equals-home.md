# 인덱스: 키트 orchestration-gate 훅을 홈 정본과 같은 바이트로 (오빠 결정 판정 343 집행 · ⓪ 생명주기 deny 는 보류 상태로 키트에서도 빠짐)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → 오빠 결정 판정 343(design/teams/harness/TABLE-gate-hook-copies-20261008.md 「오빠 결정」 문단 · 커밋 48f29c330e)
- 상태: 대기
- 선행: 없음
- 시험 입력: 기존 tests/harness/test_orch_gate_top_models.sh(키트·프로젝트 사본 TOP_MODELS 정합 · 홈 파일 안 건드림)
- 기준값: 지금 `cmp` 키트 ↔ 홈 = 다름(키트 307줄 · 홈 270줄 · diff 37줄 = 키트에만 있는 블록 2개 · 홈에만 있는 줄 0 · arch#9 실측)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 원문 5(머신 독립 배분 — 다른 머신이 키트에서 받는 훅이 이 Mac 에서 실제로 도는 훅과 같아야 한다) + 6-b(오빠 결정 343 반영). 핵심 한 줄: 오빠가 «홈 훅 = 정본, 키트 = 홈 = 같은 바이트»로 정했고 ⓪ 생명주기 deny 켜기는 보류했다 — 그런데 키트 사본에는 ⓪ 가 «켜진 채» 들어 있다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
`orchestration-gate.sh` 는 사본이 여럿이다. 이 Mac 의 모든 세션에서 실제로 도는 것은 홈 사본 `~/.claude/hooks/orchestration-gate.sh` 이고, 오빠가 이것을 정본으로 정했다(판정 343). 키트 사본 `scripts/harness-install/fable-team/templates/hooks/orchestration-gate.sh` 는 다른 머신에 나눠 줄 원본인데, 홈과 비교하면 블록 2개가 «키트에만» 있다: ⓪ 생명주기 deny(`tmuxc open|kill|clean|distill` 직접 호출 전면 차단 · 원래 41–58행 `LIFECYCLE_RE`·`in_ft_tmux()` 정의 + 105–123행 deny/면제 블록) 와 ⓐ 그에 딸린 워커 면제(`FT_WORKER_ROLE`·`^ft-` 세션명). 오빠는 ⓪ 켜기를 «ft-tmux 래퍼 라이브 설치가 먼저»라며 보류했으므로, 키트에 ⓪ 가 남아 있으면 키트를 받는 머신만 ⓪ 가 켜진 판을 갖게 된다. 그래서 키트 사본을 홈 바이트 그대로 덮는다. 홈에만 있는 줄은 0이라 잃는 기능은 ⓪·ⓐ 둘뿐이고, 둘은 git 이력(`b75314ace2` 의 키트 사본)에 그대로 남아 ⓪ 를 켜는 날 홈·키트에 같이 다시 넣는다. `install.sh` 는 훅을 홈에 복사하지 않고 same/diff 만 보고한다(59–72행) — 이 카드 뒤 그 줄이 `home=same` 이 된다.

## 사전검증
- 소환: 아니오
- 면제: 사람이 이미 정한 기준(판정 343)으로 키트 템플릿 1개를 홈 바이트로 맞추는 복사이고, 라이브에서 도는 홈 훅·settings.json 은 0 변경이다. 빠지는 블록은 «보류»로 결정된 기능뿐이며 git 이력에 원문이 남는다. 되돌림 1커밋 revert. 최종 DA 는 완성 이동 때 1회. — arch 서명 byz-harness-arch-claude#9

## 조사 근거
- `diff 키트 홈` 헝크 2개뿐: `41,58d40`(LIFECYCLE_RE·in_ft_tmux 정의) · `105,123d86`(⓪ deny + ⓐ FT_WORKER_ROLE·in_ft_tmux 면제). `^>`(홈에만 있는 줄) 0.
- 홈 `~/.claude/hooks/orchestration-gate.sh` 수정 9-29 13:56 · 키트 마지막 변경 `b75314ace2`(TOP_MODELS 정합).
- `tests/harness/test_orch_gate_top_models.sh` 현재 pass=10 fail=0 — 키트 TOP_MODELS 기본값만 보므로 덮은 뒤에도 같아야 한다(홈 TOP_MODELS 를 키트가 이미 따라감).
- 키트 문서 `scripts/harness-install/fable-team/templates/rules/orchestration.md:39` 가 «orchestration-gate 가 면제 판별보다 먼저 생명주기 deny 를 평가» 라고 적는다 — 덮은 뒤엔 사실이 아니게 되므로 같은 줄을 보류 문구로 바꾼다.
- (arch#21 · 2026-10-09 · origin/main `d23385ef35`) 키트 훅 19개 ↔ 홈 전수 cmp: 같음 9(block-destructive 포함 — §95 설치 직후) · 홈에 없음 8 · 다름 2 = orchestration-gate(이 카드) + boot-read-gate(머리 주석 2줄만 · 동작 같음 · 이 카드 범위 밖).
- `FT_WORKER_ROLE` 은 키트 `bin/ft-tmux-spawn.sh`·`ft-tmux-distill.sh`·`templates/hooks/ft-worker-guard.sh` 에서도 쓴다 — 이 카드는 그 셋을 건드리지 않는다(ft-worker-guard 는 별도 훅이고 env 주입은 해가 없다).

## 구현 범위 (이 둘만 — 닫힌 목록)
1. `scripts/harness-install/fable-team/templates/hooks/orchestration-gate.sh`: `cp ~/.claude/hooks/orchestration-gate.sh` 로 덮는다(실행 비트 유지). 손편집 0.
2. `scripts/harness-install/fable-team/templates/rules/orchestration.md:39`: 문장 끝에 ` — ★보류(오빠 판정 343 · 2026-10-08): 이 deny 는 ft-tmux 래퍼 라이브 설치 뒤 홈·키트 훅에 함께 켠다. 지금 훅에는 없다 — 원문 b75314ace2 의 키트 훅 41–58·105–123행.★` 를 붙인다. 다른 줄 0.

커밋은 자기 브랜치, **push 금지**. **금지**: 홈 `~/.claude/hooks/` 수정 · `.claude/settings.json` 수정 · 프로젝트 사본 `.claude/hooks/orchestration-gate.sh` 수정(위임 1줄 전환은 판정 343 보류) · 키트 bin 변경(드리프트 검사 BLOCK 위험).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `cmp scripts/harness-install/fable-team/templates/hooks/orchestration-gate.sh ~/.claude/hooks/orchestration-gate.sh` rc=0.
- `bash tests/harness/test_orch_gate_top_models.sh` rc=0(pass=10 fail=0).
- `bash scripts/harness-install/fable-team/install.sh --home "$HOME" 2>&1 | grep 'hook orchestration-gate.sh'` 에 `home=same`.
- RESULT 에 위 세 줄 출력 복붙.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_orch_gate_top_models.sh rc=0 · 이슈: 0`.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: d23385ef35ba92c29132a3c8c0e8f776b2601d1f (spawn 2026-10-09)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#9 · 오빠 결정 판정 343 집행). spawn 은 master 판단.
- 2026-10-09 — 재검증(byz-harness-arch-claude#21 · 판정 592 순서 ①): origin/main `d23385ef35` 기준 diff 헝크 `41,58d40`·`105,123d86` 그대로 · `^>` 0 · 키트 307 / 홈 270(홈 수정 9-29 13:56 · 그 뒤 변경 0) · test_orch_gate_top_models pass=10 fail=0 → 카드 내용 보강 불요. 이 카드는 홈을 바꾸지 않는다(키트 ← 홈 복사) — 589 홈 설치 조건 해당 없음.
- 정본 영향 없음: 하네스 키트 템플릿·키트 문서 1줄 — docs/architect 제품 정본 변경 없음.
- 2026-10-09 02:25 — 대기→진행 · 좌석 byz-harness-nano-gate-hook-kit-equals-home#0

## 결과 (나노 RESULT · master#20 옮김 2026-10-09)
세트: 4ed459ddfc7178ecb8a04751f32832f2ddd11202 · 시험: bash tests/harness/test_orch_gate_top_models.sh rc=0 · 이슈: 0
정본 영향 없음: 하네스 키트 훅 사본·규칙 템플릿만 — docs/architect 제품 정본 변경 없음.
