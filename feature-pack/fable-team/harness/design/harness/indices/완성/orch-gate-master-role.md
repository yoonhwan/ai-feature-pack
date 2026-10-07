# 인덱스: orchestration-gate 에 «master 좌석» 판별 — 세션명 역할로 켜고 코드·시안·카드 증거 직접 편집 0
<!-- ledger: design/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 6-b(오케 개선요청 접수·협의) · 원문 7. 핵심 한 줄: 오빠 10-07 「코드를 왜 너가 작업해? 하네스 지침 몰라? 나노워커는 왜 안쓰는지 확인」 — v65 master 가 시안 HTML 을 8회 직접 고치고 나노 증거 줄을 손으로 넣었는데 게이트가 한 번도 안 걸렸다. master 좌석은 코드·시안·카드 증거 직접 편집 0 이 원칙(governance §6 · BOOT 15번째 줄)이고 게이트가 그것을 물리로 막아야 한다. 출처: arch 판정 58472 · master 승인 58475.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
BYZ 세션에는 프로젝트 훅 `.claude/hooks/orchestration-gate.sh`(BYZ `.claude/settings.json` PreToolUse 등록)가 돈다. 이 훅은 «모델»로 오케를 가린다: TOP_MODELS = `fable|opus-?4-?8`(28행) — 지금 master 좌석 모델은 claude-opus-5-5[1m](v65)·claude-sonnet-5-5[1m](harness)라 108행에서 전부 allow(게이트 꺼짐). 게다가 EXCLUDE_PATH(120행대)가 경로 속 `/.worktrees/` 를 «코드 아님»으로 빼는데 거의 모든 좌석이 `.worktrees/<이름>/` 안에서 일해서, TOP 모델이어도 셈에 안 들어간다. `.html` 은 CODE_EXT 에 없다. 좌석 이름 규칙(`ft-name-lint.sh` · `<프로젝트>-<팀>-<역할>[-꼬리]#N`, 역할 예약어에 master 포함)의 3번째 토큰이 역할이고, 훅 프로세스는 Claude 프로세스의 TMUX_PANE 을 물려받는다(실측: `tmux display-message -p -t $TMUX_PANE '#S'` → `byz-harness-arch-claude#5`). 옛 이름 `ft-v65-master-claude#142` 도 같은 문법이라 3번째 토큰이 master 다.

## 구현 범위 (이 둘만 — 닫힌 목록)
1. 훅 `.claude/hooks/orchestration-gate.sh` — 서브에이전트 면제(agent_id) 바로 뒤, 모델 판별 «앞»에 master 모드 추가:
   ⓐ역할 판별: TMUX_PANE 이 있으면 `tmux display-message -p -t <pane> '#S'`(timeout 2초) → `#` 앞을 `-` 로 나눠 3번째 토큰이 `master` 면 MASTER 모드. 못 읽음·토큰 부족 = MASTER 아님(기존 동작 그대로 · fail-open 관례).
   ⓑMASTER 모드에서만: 코드 한도 0(첫 코드 파일 Edit/Write 부터 deny) · 코드로 세는 확장자에 html·htm·css 추가 · EXCLUDE_PATH 에서 `worktrees` 만 빼기(`.fable-team`·`.claude`·`.git`·`.omc` 등 나머지 제외는 유지 — 설치 cp·명부·규칙 동기는 계속 통과) · 경로가 `design/<무엇>/indices/(진행|완성)/` 아래 `.md` 인 Edit/Write 는 deny(증거 줄은 나노 것 — 카드 이동은 `ft-index-move.sh` Bash 경유라 안 막힌다) · 기존 Bash 우회 판정(sed -i·리다이렉트·cp/mv/tee)은 위 확장 기준 그대로 적용.
   ⓒdeny 메시지(MASTER 전용): 「master 는 코드·시안·카드 증거 줄 직접 편집 0 — 코드=나노(ft-nano-spawn), 시안·설계=arch, 증거 REJECT=그 나노에 반송 (오빠 10-07). master 손 = 랜딩·커밋·push·좌석·명부·원장·검증된 파일 설치 복사」.
   ⓓMASTER 아닌 좌석은 동작 변화 0(모델 판별·한도 2·기존 제외 전부 그대로). TOP_MODELS 값은 이 카드에서 바꾸지 않는다.
2. 시험 `tests/harness/test_orch_gate_master.sh`(신규): PATH 앞에 가짜 `tmux`(세션명을 env 로 돌려주는 2줄 스크립트)를 둬서 훅에 JSON stdin 을 넣는다. 케이스 — master 세션(`byz-v65-master-claude#143`·옛 `ft-v65-master-claude#142` 둘 다): `.worktrees/x/a.ts` Write → 2 · `.worktrees/x/mock.html` Edit → 2 · `design/v65/indices/진행/c.md` Edit → 2 · `design/v65/indices/완성/c.md` Edit → 2 · `design/harness/OPS-VERDICTS-20261006.md` Edit → 0 · `design/v65/indices/대기/c.md` Write → 0 · `.fable-team/seats.json` Edit → 0 · Bash `sed -i s/a/b/ .worktrees/x/a.py` → 2 · Bash `cp a.sh ~/.claude/hooks/a.sh` → 0. arch 세션(`byz-harness-arch-claude#5`)·nano 세션: 같은 html·ts Edit → 0(모델 판별에서 면제 · 지금과 같음). TMUX_PANE 없음 → 기존 동작(0). agent_id 있는 입력 → 0.
커밋은 자기 브랜치, **push 금지**. **금지**: 홈 `~/.claude/hooks/orchestration-gate.sh`·스킬 템플릿 사본 수정(세 사본 정합은 다음 단위 — 요청 원장 행) · TOP_MODELS 변경 · 다른 훅 수정.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_orch_gate_master.sh` fail=0 · 훅 `bash -n` OK · 변경 파일 = 위 2개뿐.
- 기존 동작 회귀 0: MASTER 아닌 케이스 결과가 수정 전 훅과 같다(시험에서 수정 전 사본으로 같은 입력을 돌려 대조한 표를 RESULT 에).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 43eb52ed632a36146ae523aa8122e672322a37fa (spawn 2026-10-07)
- base: 최신 origin/main.
- 2026-10-07 — 대기/ 생성 (byz-harness-arch-claude#5 · master 발주 58475 승인).
- 랜딩 뒤 반영 주의(ops): 프로젝트 훅은 «그 워크트리 브랜치에 들어 있어야» 돈다 — v65 master 가 일하는 워크트리(v6-realtime-live)·harness-ops 등 활성 워크트리가 main 을 병합해야 효과가 난다. 병합 순번은 각 팀 master.
- 정본 영향 없음: 하네스 훅·시험만 수정 — docs/architect 제품 정본 변경 없음
- 2026-10-07 11:56 — 대기→진행 · 좌석 byz-harness-nano-orch-gate-master-role#0
- 세트: f8e08734873d11adee58e4ec185d858e8b73b043 · 시험: bash tests/harness/test_orch_gate_master.sh rc=0 · 이슈: 0
- 2026-10-07 12:08 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§22
