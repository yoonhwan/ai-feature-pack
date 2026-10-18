# 인덱스: 팀 열기·닫기 한 명령 — ft-team-open / ft-team-close(admission→정리→검증 3단) + nano-close fetch 7초 (N2 · 팀 운영 구조 근원 수정 · 판정 1070·1079 · arch#29)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → planner ORDER(판정 1069·1070) · 설계 PLAN-harness-networking-20261011.md §2 D1 · §4 · §9 ①-c
- 제안서: 없음 — 오빠 판정 1070 으로 착수 승인된 하네스 구조 수정(판정 1079 3차 DA APPROVE #76290)
- 상태: 대기
- 선행: N1(seats-lint 가 `_kept`·OPENING 을 읽는다) · N3(은퇴 REJECT 가 승계 원자성과 짝) · 설계 = `git show f0d974ab20:design/teams/harness/PLAN-harness-networking-20261011.md`(r2 · ★나노 워크트리에는 없다★)
- 시험 입력: 임시 git 리포 + 가짜 `tmuxc`/`tmux`/`launchctl` 스텁(env `FT_TMUX_CMD`·`FT_LAUNCHCTL_CMD`·`FT_TMUXC_CMD`) + 가짜 좌석 jsonl(WORKING/IDLE) + 가짜 `ft-reach-check`(도달/미도달) + 가짜 nano-close(rc 0/3) — 실 세션·실 plist·루트 `.fable-team/`·실 원격 fetch 0
- 기준값(arch#29 실측 · 2026-10-11): 팀 열기·닫기 도구 0(STRUCTURE §2 개설 6항·종료 4항이 글로만) · 팀 신설 3건(ops·loom·graphics) 전부 손 작업 · tmux 세션 85(keep-last-2 초과 계보 다수) · launchd 틱 plist 4(loom·feature·ops·cfo) · `ft-nano-close.sh` 361~373행 `_fetch_remote_feat` `git fetch` 상한 0.

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
상위 제약(제품 골 · CLAUDE.md ACTIVE TRACK GOAL 바이트 일치): 목표는 빠른 유용 원문, 실시간 교정, N언어의 병렬·독립 발행, 소실·비의도 중복 없는 최종 말풍선이다. / LST ON 우선이며 LST OFF/전환과 기존 M0–M7·통합 조건도 남긴다. / 단순히 실패 사례를 많이 모았다는 이유로 실험을 닫지 않는다.
planner 원문 2(팀 배정·운영 · 베이스-위성 연결 관리) / 닫는 증거(PLAN §6 N2 복붙): 「다음에 여는 팀 1건이 `ft-team-open` 1명령으로 열리고(`_master` 확정 사건 로그 + BOARD 행) · 마감 끝난 팀 1건이 `ft-team-close` 3단 로그로 닫힘(보존 2 `_kept` · kill 계획 /tmp/h)」 + §8 「승계(①-b)/일(50 → ≤3)」.
골의 축: 근원 ①(팀 상시 → 승계 128회) — 채택안 A.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
팀 8개가 상시 열려 있어 각자 틱·승계·명부 갱신을 돌리고, 열고 닫는 절차가 글로만 있어 매번 손으로 하다 명부·route·plist 를 빠뜨렸다. 이 카드는 STRUCTURE §2 생애주기를 두 명령으로 만든다. `ft-team-open.sh <팀> --goal <경로> --master-model <ID> [--arch <ID>] [--from <planner>]` = ①GOAL 실재 ②`seats-<팀>.json`(없으면 템플릿 · `_hil_route`=현역 planner `_master` · `_master`=빈 값(개설 중)) ③`bin-<팀>/<팀>-env.sh`(kk 꼴) ④tick plist 는 상시 팀(planner·harness·v65)만 ⑤master 좌석 `tmuxc open`(zsh -lc · --model 명시) + 명부 행 ⑥부팅 쪽지 relay(골 3줄 선두) ⑦**확정 사건 = 부팅 보고 도달(`ft-reach-check` 7초 창+1회) 뒤에만 `_master`·`_opened` 원자 쓰기** → BOARD 행 · `team-events.jsonl` append(open). `ft-team-close.sh <팀>` = **①admission**(CLOSEOUT 최신 파일 실재·골 3줄 포함·커밋됨·원격 sha 줄 · 미커밋 0 · 진행 카드 0 · **역할 좌석 전부 `ft-seat-status.sh turn` IDLE — WORKING 1석이면 rc 3 거절**) → **②정리**(순서 고정 · 실패 = 그 단계 멈춤 rc 1 · 재실행 이어서: nano-close → plist `.disabled`+unload(어느 plist 지웠는지 출력) → 역할 좌석 계보당 최근 2 보존 + 그 밖 `tmux kill-session`(표준승인) → 명부 전 행 `closed`(보존 2 = `stopped`+`_kept=true`) + `_closed` 원자 쓰기) → **③검증**(STRUCTURE 4항 + 보존 좌석 IDLE 재측정 → BOARD 행 · `team-events.jsonl` append(close) · 보존 2 kill 계획 `/tmp/h<N>` 1줄 = 사람 손 HIL). 같이 고치는 1 hunk: `ft-nano-close.sh` `_fetch_remote_feat` 의 `git fetch` 를 `timeout 7` + 재시도 1 로(실패 = 기존 `bad+=` 그대로 · 성공으로 접지 않음). 세부는 PLAN §2 D1 · §4 가 정본 — 카드와 PLAN 이 다르면 PLAN 이 이긴다.

## 사전검증
- 소환: 예 — DA byz-harness-da-codex#1 r0 HOLD #76217(F1 소유·닫힘) · r1 F1 교정 확인 #76265 · r2 APPROVE #76290(판정 1079) — arch 서명 byz-harness-arch-claude#29
- 조사 근거: `design/planner/STRUCTURE-main-satellite.md` §2(개설 6항·종료 4항·«활성 작업 0») · `~/.claude/rules/closeout-policy.md` 5 · `scripts/fable-team-bin/ft-nano-close.sh`(361~373행) · `ft-seat-retire.sh`(명부 꼴) · `ft-seat-status.sh turn` · `.fable-team/bin-kk/kk-env.sh`(env 템플릿) · launchd plist `com.byz.ft-tick-<팀>` 꼴 · `ft-hil.sh`(R83 · 있으면 /tmp/h 번호 재사용)
- 7초 룰 점검(판정 666): 원격 = nano-close 간접 `git fetch` → `timeout 7`+1 · 도달 확인 `ft-reach-check` 7초 창+1 · tmux·launchctl·파일은 로컬

## 구현 범위 (닫힌 목록 · 나노 · PLAN §6 N2 · 한 번에 하나)
관련 파일(기존 · origin/main 실재 · 나노 base): scripts/fable-team-bin/ft-nano-close.sh · scripts/fable-team-bin/ft-seat-status.sh · scripts/fable-team-bin/ft-seat-retire.sh · scripts/fable-team-bin/ft-hil-ask.sh
1. ①시험 빨강 먼저 — 새 `tests/harness/test_team_open_close.sh` + 픽스처(명부·GOAL·CLOSEOUT 2종(원격 sha 있음/없음)·좌석 jsonl WORKING/IDLE·스텁 출력). open: 7단계 각 실패 → raise+되돌림 목록 · 도달 미확인 → `_master` 빈 채 rc 5. close: admission 각 항 거짓 rc 3(특히 역할 좌석 WORKING) · 정리 2단계 실패 → rc 1 + 재실행 시 이어서 · 검증 4항 · 보존 2 `_kept` · team-events 2행 append-only. fetch: 스텁 `sleep 9` → 거절(성공 0). 이 커밋 rc≠0(빨강).
2. ②새 `scripts/fable-team-bin/ft-team-open.sh`(≤200줄 · 7단계 · 공용 python 조각은 `ft_team_lib.py` ≤200줄).
3. ③새 `scripts/fable-team-bin/ft-team-close.sh`(≤200줄 · 3단 · 같은 lib).
4. ④`scripts/fable-team-bin/ft-nano-close.sh` `_fetch_remote_feat` 1 hunk(`timeout 7 git … fetch` + 1회 재시도 · 그 밖 변경 0).
5. ⑤미러: `scripts/harness-install/fable-team/bin/` `cmp` 0.

커밋은 자기 브랜치(단계별 · [test]→[feature]→[fix] 분리), **push 금지**. **금지**: 실 tmux·launchd·명부·plist 조작 · 루트 `.fable-team/` 쓰기 · 브랜치·워크트리 삭제 · STRUCTURE/closeout-policy 글 변경(S5 arch 초안) · 위 목록 밖 파일 수정 0.

## 완료 조건 (닫힘 판정 기준)
- `bash tests/harness/test_team_open_close.sh` rc=0 · 기존 nano-close 시험(`tests/harness/test_nano_close*.sh` 있으면) rc=0 · `bash -n`·`py_compile` · 미러 `cmp` 0 · 신규 파일 각 ≤200줄.
- 카드 증거 줄(«세트:» 로 시작 · 접두 없음): 세트: <40hex> · 시험: bash tests/harness/test_team_open_close.sh rc=0 · 이슈: 0
- 루트 지침: 완료 그 턴에 증거 줄 + arch#29 에 `[완료·휴식]` 1통.

## 상태
- base: origin/main 32d0374ed0e8c600e3c7ae07537cc814be989b60 (arch#29 카드 작성 시점 · spawn 때 `--base origin/main` 으로 다시 고정 · base_sha 줄은 spawn 도구가 쓴다)
- 2026-10-12 — 대기/ 생성 (byz-harness-arch-claude#29 · N2 · 설계 PLAN r2 f0d974ab20 · DA APPROVE #76290 · 판정 1070·1079).
- 정본 영향: 하네스 키트 bin 신규 2(+lib 1) · ft-nano-close 1 hunk · governance §11·STRUCTURE §2·closeout-policy 5 글은 S5.
