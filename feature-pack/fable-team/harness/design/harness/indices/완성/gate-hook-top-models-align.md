# 인덱스: orchestration-gate 키트·프로젝트 사본의 TOP_MODELS 를 홈(실행 중) 값으로 정합 — Sonnet 5.5 워커 면제
<!-- ledger: design/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 원문 1 C(배포·반영 — 키트를 설치하면 그대로 돌아야 한다). 핵심 한 줄: 인계 열린 일 6 「게이트 훅 3사본 정합」 · 안 design/harness/PLAN-gate-hook-3copy-align-20261007.md · master#10 승인 #60097(범위 = TOP_MODELS 정합만 · 홈 설치 0).

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
orchestration-gate 훅은 사본이 셋이고 TOP_MODELS 기본값이 서로 다르다. 홈 `~/.claude/hooks/orchestration-gate.sh`(실제로 도는 판 · 수정 금지) = `fable|sonnet-?5(?!-?5)` 로 Sonnet 5.5 워커를 면제한다(전역 troubleshoot 09-29 수정). 키트 `scripts/harness-install/fable-team/templates/hooks/orchestration-gate.sh` = `fable|sonnet-?5` — 이 키트를 설치하면 Sonnet 5.5 나노·tester 가 오케로 잡혀 한 턴 코드 3파일째에서 막힌다(09-29 사고 재발). 프로젝트 `.claude/hooks/orchestration-gate.sh`(`.claude/settings.json` 30행에 등록 · BYZ 세션마다 홈 훅과 같이 돈다) = `fable|opus-?4-?8` 옛 로스터. 세 사본은 다른 기능도 서로 다르다. 키트에만 ⓪ 생명주기(tmuxc open/kill) 차단이 있고, 프로젝트에만 0-b master 좌석 모드가 있다. ★그래서 «한 사본으로 덮기»는 금지이고 TOP_MODELS 두 줄만 바꾼다★. TOP_MODELS 문자열은 python re 로 평가되므로 lookahead `(?!-?5)` 가 쓰인다.

## 사전검증
- 소환: 아니오
- 면제: 바뀌는 것이 기본값 정규식 1줄 + 주석 줄이고, 그 값은 홈에서 09-29 부터 실제로 돌고 있는 값이다(동작 실증). 되돌림 1커밋 revert. 최종 DA 는 완성 이동 때 1회. — arch 서명 byz-harness-arch-claude#7

## 조사 근거
- `scripts/harness-install/fable-team/templates/hooks/orchestration-gate.sh:27` 주석(sonnet-?5 설명) · 28행 `TOP_MODELS="${OMC_GATE_TOP_MODELS:-fable|sonnet-?5}"`.
- `.claude/hooks/orchestration-gate.sh:27` 주석(opus-?4-?8 설명) · 28행 `TOP_MODELS="${OMC_GATE_TOP_MODELS:-fable|opus-?4-?8}"` · 95–109행 master 좌석 모드(건드리지 않음).
- `tests/harness/test_orch_gate_master.sh:5` — 프로젝트 사본을 가짜 tmux 로 돌리는 기존 시험 틀(입력 JSON 조립 `mk` · 실행 `run`). 새 시험은 이 틀을 복사한다.

## 구현 범위 (이 셋만 — 닫힌 목록)
1. `scripts/harness-install/fable-team/templates/hooks/orchestration-gate.sh`: 28행을 `TOP_MODELS="${OMC_GATE_TOP_MODELS:-fable|sonnet-?5(?!-?5)}"   # (?!-?5): sonnet-5-5(Sonnet 5.5)는 워커 면제 — 2026-09-29` 로 바꾸고, 27행 주석 아래에 `# 단 sonnet-5-5(Sonnet 5.5: 나노·tester 워커 모델)는 (?!-?5) 로 제외 — 정규식은 python re 로 평가되므로 lookahead 사용 가능.` 1줄을 넣는다(홈 사본 28–29행과 같은 문자열). 다른 줄 변경 0.
2. `.claude/hooks/orchestration-gate.sh`: 27–28행(opus-?4-?8 주석·값)을 위 1번과 같은 3줄(sonnet-?5 설명 주석 · Sonnet 5.5 제외 주석 · 값)로 바꾼다. 3행 머리 주석의 «opus-4-8» 예시를 «sonnet5» 로 바꾸는 것은 허용(키트 3행 문구와 같게). 그 밖 변경 0 — master 좌석 모드 무변화.
3. 시험 `tests/harness/test_orch_gate_top_models.sh` 신규. 두 사본 각각에 대해 셔뱅 인터프리터(`/bin/bash`)로, 가짜 transcript(마지막 assistant model 값을 넣은 jsonl · mktemp)와 Edit 입력 3개(서로 다른 .py 코드 파일)를 같은 session_id 로 넣는다.
   - Sonnet 5 (`claude-sonnet-5[1m]`) → 3번째 Edit exit 2 · Sonnet 5.5 (`claude-sonnet-5-5[1m]`) → 3번째도 exit 0 · Fable (`claude-fable-5-1`) → exit 2 · `agent_id` 있음 → exit 0.
   - 프로젝트 사본은 비-master 세션(가짜 tmux 세션명 `byz-v65-tester-claude#0` 또는 TMUX_PANE 없음)으로 돌린다.
   - 기존 `tests/harness/test_orch_gate_master.sh` 는 계속 rc=0.

커밋은 자기 브랜치, **push 금지**. **금지**: 홈 `~/.claude/hooks/**` 쓰기 · `.claude/settings.json` 변경 · ⓪ 생명주기 블록을 프로젝트·홈에 옮기기(816 뒤 별건) · master 좌석 모드를 키트로 옮기기(별건) · TOP_MODELS 외 판정 변경.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_orch_gate_top_models.sh` rc=0 · `bash tests/harness/test_orch_gate_master.sh` rc=0 · 두 사본 `bash -n` OK.
- `grep -n 'TOP_MODELS="' <키트> <프로젝트> ~/.claude/hooks/orchestration-gate.sh` 세 줄의 기본값 문자열이 같다 — 출력 3줄을 RESULT 에 복붙.
- 카드 증거 줄 형식(필수 · 없으면 반송): `세트: <sha> · 시험: <명령> rc=0 · 이슈: 0`.
- 랜딩·push 는 master 집행. 홈 설치는 이번 범위에 없다(홈은 이미 그 값).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: f6042b3af34bed1d7b49cf9ffcbbca8261421411 (spawn 2026-10-07)
- base: 최신 origin/main(b56365e381 이후).
- 2026-10-07 — 대기/ 생성 (byz-harness-arch-claude#7 · 인계 열린 일 6 · 승인 #60097).
- 정본 영향 없음: 하네스 훅 사본·시험만 — docs/architect 제품 정본 변경 없음
- 남은 어긋남(이 카드 밖 · 816 줄기): 키트에만 ⓪ 생명주기 차단 · 프로젝트에만 0-b master 좌석 모드 · 홈엔 둘 다 없음.
- 2026-10-07 21:10 — 대기→진행 · 좌석 byz-harness-nano-gate-hook-top-models-align#0
- 2026-10-07 — 증거(나노 byz-harness-nano-gate-hook-top-models-align#0 · 골 축 원문 1 C 배포·반영 · arch#7 재현):
  - 변경 3파일: `.claude/hooks/orchestration-gate.sh` TOP_MODELS 3줄 · `scripts/harness-install/fable-team/templates/hooks/orchestration-gate.sh` TOP_MODELS 2줄 · `tests/harness/test_orch_gate_top_models.sh` 신규(/bin/bash 셔뱅 실행 · KIT·PROJ × Sonnet 5 / Sonnet 5.5 / Fable / agent_id).
  - TOP_MODELS 기본값 3사본(키트·프로젝트·홈) 같은 문자열 `fable|sonnet-?5(?!-?5)` — grep 3줄 동일.
  - master 좌석 모드(프로젝트 0-b)·⓪ 생명주기(키트) 무변화 — diff 는 TOP 줄뿐.
- 세트: a0cf195d871f82cc225095db5c5b2759468417e0 · 시험: bash tests/harness/test_orch_gate_top_models.sh rc=0 · 이슈: 0
- 추가 시험: bash tests/harness/test_orch_gate_master.sh rc=0(pass=36 fail=0) · test_orch_gate_top_models pass=10 fail=0
- 정본 영향: 하네스 훅 사본 2개(키트 템플릿·프로젝트 .claude/hooks)의 기본값 1줄 — docs/architect 제품 정본 변경 없음 · 홈 훅 설치 0(이미 같은 값).
- 2026-10-07 21:13 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§34
