# 인덱스: 나노 spawn·close 가 «팀»을 스스로 안다 — 팀 env 자동 로드 + codex 모델 기본 + --base 인자
<!-- ledger: design/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 6-b(오케 개선요청 접수·협의) · 원문 7. 핵심 한 줄: 새 이름 규칙(byz-<팀>-nano-<슬러그>#N) 뒤로 나노 spawn·close 가 «v65 기본값»으로 돌아 팀 env 를 손으로 source 하지 않으면 REJECT 되거나 엉뚱한 base·모델로 뜬다 — planner 요청 #58688 ①(close 접두) · v65 보고(codex 모델) · harness master 발견(base). 출처: arch 58640 판정 ②③ + 이 카드 안.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
대상은 키트 사본 `scripts/harness-install/fable-team/bin/`(카드 kit-bin-adopt 랜딩 뒤 단일 원본 · 추적본 scripts/fable-team-bin 은 같은 바이트로 같이 고친다 — test_kit_bin_sync 가 검사). 팀 env 는 `$ROOT/.fable-team/bin-<팀>/<팀>-env.sh`(실재: harness·issues·kk·planner · v65 는 없음 = 스크립트 기본값이 v65)이고 FT_NANO_PREFIX·FT_SEATS_JSON·FT_NANO_WT_PREFIX·FT_NANO_LEDGER 등을 export 한다. ft-nano-close.sh 23행 `NANO_PREFIX="${FT_NANO_PREFIX:-ft-v65-temp-}"` · 24행 접두 게이트(나노만 닫는 안전장치 — 표준승인 kill·워크트리 정리 범위) · 217행 `_KEY` = 좌석명에서 접두 제거한 슬러그. env 없이 부르면 접두뿐 아니라 SEATS·원장도 v65 값이라, 접두만 유도하면 그 다음 ⑥(카드 못 찾음)에서 REJECT 된다. ft-nano-spawn.sh 는 첫 인자가 카드 경로(`design/<팀>/indices/대기/X.md`) · 11행 MODEL 기본 = FT_IMPL_MODEL(claude) — `--agent codex` 만 주면 claude 모델이 넘어간다(22-33행 티어 경로만 gpt) · 96행 BASE_BRANCH = 부른 워크트리의 현재 HEAD · 140행이 `.worktree-info.json` 에 base 를 기록한다. 닫기의 cherry/증거 판정은 FT_NANO_FEAT(기본 feat/v6-realtime-live · 하네스 env 값은 옛 feat/slack-inbound-820)를 쓴다.

## 구현 범위 (이 셋만 — 닫힌 목록)
1. 팀 env 자동 로드(spawn·close 공통 · `scripts/harness-install/fable-team/bin/ft-nano-close.sh` 와 ft-nano-spawn.sh 머리, 인자 파싱 직후): FT_NANO_PREFIX 가 «이미 설정돼 있으면 아무것도 안 함»(명시가 이긴다). 없으면 팀 글자 유도 — close 는 좌석명이 `^byz-([a-z0-9]+)-nano-` 이면 그 팀 · spawn 은 카드 경로가 `design/([a-z0-9]+)/indices/` 이고 그 팀이 v65 가 아니면 그 팀. 팀이 나오면 `$ROOT/.fable-team/bin-<팀>/<팀>-env.sh` 를 source · 그 파일이 없으면 REJECT(「팀 env 없음: <경로>」 · 추측 0). 팀이 안 나오면(옛 이름 ft-v65-temp-* · design/v65/) 지금 기본값 그대로. 로드 결과를 한 줄 출력: `ENV team=<팀|default> prefix=<값> seats=<경로>`. 24행 게이트는 그대로(유도된 접두도 «-nano-» 로 끝나 나노만 닫힘이 유지된다).
2. ft-nano-spawn `--model` 미지정 시 에이전트별 기본: 인자 파싱 뒤 MODEL 을 사용자가 안 줬고 AGENT 가 claude 가 아니면 codex → `${FT_LUNA_MODEL:-gpt-6-luna}` · cmd → `${FT_CMD_MODEL:-deepseek/deepseek-v4-flash}` · 그 밖(opencode 등) → REJECT(「--model 필수」). 티어 경로(22-33행) 동작은 그대로.
3. base 정합: spawn 에 `--base <ref>` 인자(주면 그 ref 로 worktree add · 없으면 지금처럼 현재 HEAD — v65 무변화) · close 의 cherry/증거 판정 base = FT_NANO_FEAT 가 «명시 설정»이면 그 값, 아니면 좌석 워크트리 `.worktree-info.json` 의 base, 그것도 없으면 지금 기본값. 팀 env 의 FT_NANO_FEAT 는 이 카드에서 바꾸지 않는다(env 는 운영 파일 — 값 정리는 master).
4. 시험 `tests/harness/test_nano_team_env.sh`(신규 · 임시 ROOT 에 가짜 `.fable-team/bin-<팀>/<팀>-env.sh` 를 만들고 tmux·git 이 필요한 단계 전에 끝나는 경로만 본다 — spawn 은 `--dry-run`): close — byz-planner-nano-x#0(env 없음 상태로 호출) → ENV team=planner prefix=byz-planner-nano- · byz-zzz-nano-x#0 → REJECT 팀 env 없음 · ft-v65-temp-x#0 → ENV team=default prefix=ft-v65-temp- · FT_NANO_PREFIX 명시 + byz-planner-nano-x#0 → 자동 로드 안 함 · byz-harness-arch-claude#5 → 접두 게이트 REJECT. spawn — design/planner/indices/대기/c.md → team=planner · design/v65/indices/대기/c.md → default · `--agent codex`(모델 미지정) → PLAN model=gpt-6-luna · `--agent opencode` → REJECT · `--base origin/main` → PLAN base=origin/main · `--base` 없음 → base=현재 HEAD. 공유 닫기(가짜 git 워크트리 2개 · 가짜 tmux) — `--shared-wt` 없이 공유 cwd 좌석 → 지금처럼 REJECT · 전용 워크트리가 있는 좌석 + `--shared-wt` → REJECT(전용 경로로) · 공유 cwd 가 nano/* 브랜치 → REJECT · result 경로 미추적 또는 그 경로 미커밋 → REJECT · 공유 워크트리의 «다른» 파일 미커밋만 있음 → 통과 · 증거 sha 가 공유 HEAD 의 조상 → 통과 · 조상 아님 → REJECT · 통과 시 출력에 mode=shared-wt 이고 wt-clean 계획 파일·cherry 호출 0.
5. 공유 워크트리 좌석 닫기(오빠 10-07 · 원장 R8 · 실례 byz-cfo-nano-credit-rows-939#0 — pane cwd = 공유 c-level-planning · 전용 워크트리·nano 브랜치 없음 → 지금 ③ «추측 금지»·⑤ 브랜치 없음으로 REJECT): ft-nano-close 에 «명시» 인자 `--shared-wt` 추가(자동 판별 안 함 — 기존 fail-closed(DA607 H1) 유지 · 인자 없으면 지금 동작 그대로). 인자가 있을 때만 이 순서로 «전부» 확인하고 하나라도 아니면 REJECT: ⓐ좌석 이름에 해당하는 전용 워크트리(브랜치 nano/<key>[-rN])가 «없다» — 있으면 «전용 경로로 닫아라» REJECT ⓑpane cwd 의 toplevel 이 등록된 워크트리이고 그 브랜치가 nano/* 가 «아니다» ⓒ기존 종료조건 3(①--result 경로 실재 ②--recv seq 실재 ③jsonl 유휴 ≥ IDLE_MIN) 그대로 ⓓ--result 경로가 그 워크트리에서 «추적 중이고 그 경로에 미커밋 변경 0»(`git ls-files --error-unmatch` + `git status --porcelain -- <경로>` 빈 값 — 공유 워크트리 «전체»의 미커밋은 다른 세션 것이라 보지 않는다) ⓔ카드 증거 줄: 형식은 그대로, 단 세트 sha 는 «현재 HEAD 와 같음» 대신 «공유 워크트리 HEAD 의 조상»(공유 HEAD 는 다른 세션이 계속 옮긴다) — `scripts/harness-install/fable-team/bin/ft-nano-evidence-check.sh` 에 `--ancestor-of <ref>` 인자 1개로 넣는다(없으면 지금 동작). 통과하면 ⑤cherry 게이트·워크트리 정리 계획(wt-clean)은 «건너뛰고» 세션 kill(10-02 표준승인 nano-close 경로)·명부 CLOSED·원장 행만 — 원장 행에 `mode=shared-wt wt=<공유 경로> (정리 0 · 브랜치 0)`. 워크트리·파일·브랜치는 손대지 않는다.
커밋은 자기 브랜치, **push 금지**. **금지**: 라이브 FT_BIN 쓰기(전환은 install 단계) · 팀 env 파일 수정 · 24행 게이트 완화 · 공유 워크트리 자동 판별(반드시 `--shared-wt` 명시) · 공유 모드에서 파일·워크트리·브랜치 변경 · ft-role-spawn.sh 수정(별도 카드) · 기본 접두 ft-v65-temp- 변경.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_nano_team_env.sh` rc=0 · `tests/harness/test_kit_bin_sync.sh` rc=0(키트·추적본 같은 바이트) · 기존 `tests/harness/test_*.sh` 전부 rc=0 · 세 스크립트(spawn·close·evidence-check) `bash -n` OK.
- v65 무변화 실측: v65 카드로 spawn `--dry-run` 의 PLAN 줄이 수정 전과 같다(RESULT 에 전후 줄).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 1aca03ade2f098175548f1c549ed4be6b837ea6d (spawn 2026-10-07)
- base: kit-bin-adopt 랜딩 뒤 최신 origin/main(키트가 단일 원본이 된 뒤). 그 전에 열면 추적본·키트 바이트가 달라 sync 시험이 깨진다.
- 2026-10-07 — 대기/ 생성 (byz-harness-arch-claude#5 · master#8 발주 58692 + arch 58640 후속 ②③ 합침).
- 정본 영향 없음: 하네스 나노 도구·시험만 — docs/architect 제품 정본 변경 없음
- 2026-10-07 13:32 — 대기→진행 · 좌석 byz-harness-nano-nano-spawn-close-team-env#0
- 2026-10-07 13:43 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§26
- 세트: 45a1ee516ab4b28f4b06af7fe8db928c41f6a45f · 시험: bash tests/harness/test_nano_team_env.sh rc=0 · 이슈: 0
