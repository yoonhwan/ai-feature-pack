# 인덱스: 그래픽·UI/UX 팀 «graphics» 설치 — 명부·env·골·카드 폴더·governance 팀 표 (판정 649 · 오빠 확정 10-09 · planner#16 #67767 → 하네스 master#22 #67771 · 제안서 판정 635/636/641)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 649(오빠 확정 「그래픽 UI/UX 팀 이 구성으로 확정 — arch=codex astra · 나노=codex sol ≤2 · 상시 0 · 요청 때 하네스가 개설·닫기 · DA=Claude Opus」)
- 상태: 대기
- 선행: 제안서 `design/harness/PROPOSAL-team-graphics-20261009.md` r5 (arch 서명 `27aeb63af0` · Opus DA r3 APPROVE `580821eada`)
- 시험 입력: 아래 «산출 파일» 스테이징 사본 + 기존 래퍼 `--dry-run`(실 좌석·워크트리 생성 0)
- 기준값(arch#24 실측): 팀 env 자동 로드 = `scripts/fable-team-bin/ft-nano-spawn.sh` 가 카드 경로 `design/<팀>/indices/` 의 팀으로 `$ROOT/.fable-team/bin-<팀>/<팀>-env.sh` 를 source(없으면 REJECT) · 나노 브랜치 = `nano/<카드 slug>` 고정(128·132행) · `scripts/fable-team-bin/ft-nano-close.sh` ③ = 브랜치 `nano/*` 아니면 REJECT · `ft-role-spawn.sh` = v65 inbox·README 고정(28·29행) → ops·loom 선례대로 arch·DA 는 `tmuxc open` + 명부 손 등록 · 이름 lint `byz-graphics-arch-codex#0`·`byz-graphics-da-claude#0` PASS.

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 B / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」 — 오빠 값 = 판정 649 · 반영 sha = 설치 랜딩 sha.
골의 축: 원문 2(메인·위성 팀 개선 협의 — 공용 그래픽 팀 추가 구성) + 원문 1·C(정본화·설치).

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
오빠가 그래픽·UI/UX 팀을 «상시 0 · 요청 때만 하네스가 열고 닫는 공용 서비스 팀»으로 확정했다(제안서 r5 = 정본 계약). 이 카드는 그 팀이 «열릴 수 있게» 하는 설치만 한다 — 좌석·워크트리를 실제로 열지 않는다. 팀 운영값은 기존 팀(ops·loom — 판정 370·372)과 같은 자리에 둔다: 명부 `.fable-team/seats-<팀>.json` · env `.fable-team/bin-<팀>/<팀>-env.sh` · 골 `design/<팀>/GOAL-<팀>.md` · 카드 `design/<팀>/indices/{대기,진행,완성}` · governance 정본 §1 팀 목록·§1-1 팀 값 표. 차이 3: ①master 0(열기·감시·닫기 = 하네스 master — 명부 `_master` = 하네스 현역 master) ②상시 틱 0(launchd plist 0 — 감시는 하네스 master 10분 틱) ③좌석 모델이 codex arch·나노 + Claude Opus DA. 루트 `.fable-team/` 은 git 밖이므로 나노는 «tracked 스테이징 사본»을 만들고 master 가 cp+cmp 로 설치한다.

## 사전검증
- 소환: 아니오 — 계약은 제안서 r5 에서 Codex DA r1·r2 + Claude Opus DA r3 를 거쳐 APPROVE·서명됐다. 이 카드는 그 계약의 «설정값 배치»이고 코드 변경 0(아래 «오빠 1줄 승인 항목»을 ⓑ 로 받으면).
- 조사 근거: 위 «기준값» 줄(래퍼 행 번호 실측) · ops 선례 `.fable-team/bin-ops/ops-env.sh`·`seats-ops.json` `_` 키.

## ★오빠 1줄 승인 항목 (설치와 분리 · planner 경유)★ — graphics 나노 닫기 방식
제안서 r5 §5 «설치 때 정할 것 1»: `ft-nano-close.sh` 는 브랜치 `nano/*` 만 닫는다.
- ⓐ 닫기 래퍼가 `graphics/*` 도 받게 확장 — 나노 정리 표준승인(2026-09-25 · 조건 3 그대로 · 브랜치 삭제 0)의 «범위 확장» → ★오빠 1줄 필요★ + 래퍼 코드 변경(나노·DA⑥).
- ⓑ ★(arch#24 권고 변경 — 새 실측)★ 브랜치 이름을 `nano/<카드 slug>` 로 둔다(카드 이름 = `g<Issue>-<slug>` → 브랜치 `nano/g<Issue>-<slug>`). `ft-nano-spawn.sh` 가 이미 `nano/<slug>` 를 만들고 `ft-nano-close.sh` 가 이미 닫는다 → ★코드 변경 0 · 표준승인 범위 그대로 · 오빠 승인 불필요★. 제안서 §3.3 의 `graphics/<Issue>-<slug>` 는 «이름 표기»만 바뀌고 계약(요청 1건 = 본 브랜치 1개 · 2석 = 페이지별 하위 브랜치 → 본 브랜치 병합 · sha 하나)은 같다.
- 권고 바뀐 이유: 서명 때(r5)는 spawn 이 `nano/` 를 고정으로 만든다는 사실을 확인하지 않았다 — ⓐ 는 close 뿐 아니라 spawn 도 고쳐야 해 일이 두 배다.
- ⓑ 로 가면 이 항목은 «알림 1줄»(오빠 결정 0)로 바뀐다. 결정은 planner#16 경유.

## 설계 (닫힌 목록 · ⓑ 기준)
1. **명부** `.fable-team/seats-graphics.json`: `_name` Seatbelt-GRAPHICS · `_doc`(상시 0 · 요청 때 하네스 master 가 열고 닫음 · 제안서 경로 · ft-role-spawn 미사용 = tmuxc open + 손 등록) · `_master` = 하네스 현역 master(`byz-harness-master-claude#22` · 하네스 master 승계 때 같이 고침 — `_doc` 에 한 줄) · `_hil_route` = `byz-planner-master-claude#16` · `_arch` = "" (열릴 때 채움) · `_cards` `design/graphics/indices` · `_cards_wt` `harness-ops` · `_label` `graphics` · `_tick` null · 좌석 0.
2. **env** `.fable-team/bin-graphics/graphics-env.sh` (ops-env.sh 포크): `FT_SEATS_JSON`=seats-graphics.json · `FT_NANO_PREFIX=byz-graphics-nano-` · `FT_NANO_WT_PREFIX=graphics-nano-` · `FT_ACTIVE_TAG=@zc_graphics_active` · `FT_NANO_LEDGER_WT`=harness-ops 워크트리 · `FT_NANO_LEDGER=design/graphics/NANO-LEDGER-graphics.md` · `FT_GOAL_LEDGER=design/graphics/GOAL-graphics.md` · ★`FT_IMPL_MODEL` 은 넣지 않는다★(spawn 기본 agent = claude · `ft-nano-spawn.sh` 11행 — env 로 agent 를 못 바꾼다 → graphics 나노는 RUNBOOK·발주에서 항상 `--agent codex --model gpt-6.1-sol` 명시) · `FT_SEND_FROM`=하네스 현역 master · `FT_BIN`(harness-env 와 같은 값) · `FT_NANO_FEAT=origin/main` · `FT_GOAL_LINES_FILE=.fable-team/bin-graphics/goal-lines-graphics.txt` · `FT_MBOX_SH` · `FT_CARD_REQUIRE_PREVERIFY=1`.
3. **골 줄** `.fable-team/bin-graphics/goal-lines-graphics.txt` + **골 파일** `design/graphics/GOAL-graphics.md` = 제안서 «오빠 원문» 4줄(판정 636) 그대로 복붙(불변 · 수정은 오빠 승인).
4. **카드 폴더** `design/graphics/indices/{대기,진행,완성}/.gitkeep` + `design/graphics/NANO-LEDGER-graphics.md`(빈 원장 머리 1줄) — harness-ops 워크트리(`ops/main-base`).
5. **governance 정본**(`~/.claude/skills/fable-team/references/main-team-governance.md`): 머리 인용에 «판정 649 graphics 신설» 1줄 · §1 오케 이름 목록 = graphics 는 master 0 이라 넣지 않고 «graphics = master 0 · 하네스 master 가 대행» 1줄 · §1-1 표 1행 `| graphics | byz-graphics- · team:graphics | seats-graphics.json · bin-graphics/ | design/graphics/GOAL-graphics.md | 요청 때만 여는 공용 서비스 — 페이지 요청 = 홈피 기준 업그레이드 + FE 코드 연동 · 디자인 시스템 · 모션 — 기능 기획·과금·발행 경로·랜딩 0 (제안서 판정 635) |` · §8 끝에 «graphics 좌석이 열려 있는 동안 하네스 master 는 seats-graphics.json 현역 좌석 전체를 자기 10분 틱 감시 대상에 넣는다» 1줄.
6. **라벨** `team:graphics` — issues master 에 생성 요청(GitHub 쓰기 = issues 경로 · 이 카드에서 0).
7. **열기·닫기 절차 1장** `design/graphics/RUNBOOK-open-close.md`(≤40줄): 열기 = 경계·승인 근거 확인 → `tmuxc open` arch(`--agent codex --model gpt-6-astra`)·명부 등록 → 카드 `design/graphics/indices/대기/g<Issue>-<slug>.md` → `ft-nano-spawn.sh <카드> --agent codex --model gpt-6.1-sol --base origin/main` · DA = `tmuxc open --agent claude --model claude-opus-5-5 --effort high` · 닫기 = 제안서 §3.7 공통 3실측 → `ft-nano-close.sh`(나노) · arch·DA 세션 닫기(★graphics arch·DA 계보도 keep-last-2 대상 — 닫기 전 오빠 판단 필요 여부를 하네스 master 가 planner 에 1줄★).

## 구현 범위 (닫힌 목록 · 나노)
기존 근거 파일(읽기): `design/harness/PROPOSAL-team-graphics-20261009.md` · `scripts/fable-team-bin/ft-nano-spawn.sh` · `scripts/fable-team-bin/ft-nano-close.sh` · `scripts/fable-team-bin/ft-name-lint.sh` · 홈 governance 정본 ~/.claude/skills/fable-team/references/main-team-governance.md(읽기만) · 루트 .fable-team/bin-ops/ops-env.sh·.fable-team/seats-ops.json(포크 원본 · 읽기만).
아래 경로는 전부 «이 경로에 새로 만든다»:
1. 스테이징 사본(tracked) 폴더 scripts/harness-install/graphics/ 에 seats-graphics.json · graphics-env.sh · goal-lines-graphics.txt · install.sh(루트 .fable-team/ 로 cp · 이미 있으면 .bak-<ts> 후 덮기 · cmp 출력) — 설계 1~3.
2. repo 파일: 설계 3(design/graphics/GOAL-graphics.md) · 4(design/graphics/indices/{대기,진행,완성}/.gitkeep · design/graphics/NANO-LEDGER-graphics.md) · 7(design/graphics/RUNBOOK-open-close.md).
3. governance 변경 = 스테이징 design/harness/staged-649/main-team-governance.md(현 정본 사본 + 설계 5 의 4곳만 · diff 는 그 4곳만).
4. 시험 tests/harness/test_graphics_install.sh (실 좌석·워크트리 0): ①`bash -n` 전 스크립트 ②임시 ROOT 에 install.sh → 3파일 cmp 0 ③source graphics-env.sh 뒤 설계 2 의 변수(FT_IMPL_MODEL 제외) 전부 비어 있지 않음 ④seats-graphics.json JSON 파싱 + _master·_hil_route·_cards 존재 ⑤`scripts/fable-team-bin/ft-name-lint.sh` 로 byz-graphics-nano-g0-test#0 · byz-graphics-arch-codex#0 · byz-graphics-da-claude#0 PASS ⑥임시 카드로 `scripts/fable-team-bin/ft-nano-spawn.sh` <임시 카드 design/graphics/indices/대기/g0-dryrun.md> --agent codex --model gpt-6.1-sol --dry-run 의 PLAN 줄에 branch=nano/g0-dryrun · wt=…/graphics-nano-g0-dryrun (env 자동 로드 확인 · 임시 env 는 임시 ROOT 로 · 임시 카드는 시험 뒤 지움) ⑦staged governance 와 현 정본 diff = 설계 5 의 4곳만.
커밋은 자기 브랜치, **push 금지**. **금지**: 루트 .fable-team/·홈 ~/.claude/ 쓰기(설치는 master) · tmux 좌석 열기 · GitHub 쓰기 · 래퍼 코드 수정(ⓑ 기준).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 위 시험 rc=0 · arch 독립 재현.
- 카드 증거 줄: 세트: <40hex> · 시험: bash tests/harness/test_graphics_install.sh rc=0 · 이슈: 0.
- 루트 지침: 완료 그 턴에 증거 줄 + arch#24 에 `[완료·휴식]` 1통.
- ★랜딩 뒤 master 집행★: PR → 병합 → `bash scripts/harness-install/graphics/install.sh`(cmp 0) → governance 스테이징 cp + cmp → 라벨 요청(issues master) → planner#16 에 「graphics 설치 끝 · 첫 요청 = cfo 크레딧 페이지(INVENTORY `323002d0c1`) 받을 준비」 1줄.

## 상태
- base_sha: 0a569d783aaab3487f384aa2d7a9f45424edbe85 (spawn 2026-10-09)
- 2026-10-09 — 대기/ 생성 (byz-harness-arch-claude#24 · 판정 649 · master#22 #67771).
- 정본 영향: governance §1·§1-1·§8 (설치 때 master cp) · 루트 `.fable-team/` 새 파일 3 · 래퍼 코드 0.
- 2026-10-09 11:06 — 대기→진행 · 좌석 byz-harness-nano-g649-graphics-team-install#0
- 2026-10-09 — arch#24 독립 재현: `tests/harness/test_graphics_install.sh` ALL PASS rc=0 · governance 스테이징 = 홈 정본(sha256 앞16 8abe67008b24dac1) + 추가 4곳 · GOAL = 636 원문 4줄 → arch 서명 · 판정서 초안 §107 → master 집행 요청.

## 결과
- 세트: 97ae908ab1e635a32469eae5991300794f6d1916 · 시험: bash tests/harness/test_graphics_install.sh rc=0 · 이슈: 0
정본 영향 없음: 제품 정본(docs/architect) 변경 없음 — 하네스 팀 정본(홈 governance 추가 4줄)·그래픽스 팀 키트만 (PR 1076 4fc3140297 · 홈 설치 cmp OK).
- 2026-10-09 11:13 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§107
