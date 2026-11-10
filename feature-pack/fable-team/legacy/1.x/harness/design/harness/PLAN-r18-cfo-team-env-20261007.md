# PLAN — R18 CFO 팀 env 파일 (arch#7 안 · 2026-10-07)

## 골 원문 (GOAL-harness.md 복붙)
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골 축: 원문 6-b(메인 오케 CFO 의 개선요청 #59915 를 등록·개선) + 원문 7(팀별로 쪼개 동시에 — 팀 env 1장이 팀 분리의 단위).

## 결론
**승인 — bin-cfo/cfo-env.sh 신설(아래 본문 그대로) + CFO 전용 나노 원장 신설.** 낮은 우선이지만 지금 하면 원장 오기록이 멈춘다.

## 실측 (이 세션)
- `.fable-team/bin-cfo/` 실재, `cfo-env.sh` 없음 → ft-nano-close 좌석명 자동 로드(40–46행)가 `REJECT 팀 env 없음`.
- ★오기록 발견★: CFO 나노 닫기 5건(u3#0·u3#1·u4#0·u4#1·u5#0)이 `.worktrees/c-level-planning/design/teams/harness/NANO-LEDGER-harness.md` 에 쓰였다(미커밋 +5행). 원인 = 손 주입이 `FT_NANO_LEDGER_WT=c-level-planning` 만 주고 `FT_NANO_LEDGER` 는 하네스 값이 남아 있던 것으로 보인다(추정 — 행 위치가 근거). CFO 전용 원장 파일은 없다.
- CFO 나노 base = origin/main (nano/overdraft-u6 의 merge-base = d84e49ed93 · #778 U5 squash). docs/cfo-main 아님.
- CFO 골 정본 = `.worktrees/c-level-planning/design/cfo/GOAL-cfo.md`. goal-lines-cfo.txt 없음.
- 살아 있는 `byz-cfo-nano-overdraft-u6#0` 에 `@zc_*` 태그 없음(정보 — 닫기에는 영향 없음, 해제가 no-op).

## 이유 3줄
1. 6개 값을 매번 손으로 맞추는 동안 이미 1개(원장 경로)가 어긋나 5행이 남의 원장에 들어갔다 — 재현성 문제가 실측으로 확인됐다.
2. harness-env·feature-env 와 같은 틀이라 ft-nano-close 수정 0 · 파일 1장으로 닫힌다.
3. 원장을 CFO 전용으로 떼야 하네스 원장(harness-ops)과 CFO 기록이 섞이지 않는다(원문 7 팀 분리).

## 파일 본문 — `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/bin-cfo/cfo-env.sh`
```
# source 해서 쓴다 — CFO 팀 값 (feature-env.sh 포크 · 2026-10-07 R18 · arch#7 안)
export FT_SEATS_JSON=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/seats-cfo.json
export FT_NANO_PREFIX=byz-cfo-nano-
export FT_NANO_WT_PREFIX=cfo-
export FT_ACTIVE_TAG=@zc_cfo_active
export FT_NANO_LEDGER_WT=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/c-level-planning
export FT_NANO_LEDGER=design/cfo/NANO-LEDGER-cfo.md
export FT_GOAL_LEDGER=design/cfo/GOAL-cfo.md
export FT_IMPL_MODEL='claude-sonnet-5-5[1m]'
export FT_SEND_FROM='byz-cfo-master-claude#54'   # 승계 때 갱신(.bak-succN 관례)
export FT_BIN=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/v6-realtime-live/.fable-team/bin
export FT_NANO_FEAT=main   # CFO 나노 base = origin/main (u6 merge-base d84e49ed93 실측)
export FT_MBOX_SH=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh
```
- `FT_GOAL_LINES_FILE` 은 넣지 않는다 — 골 3줄은 CFO 소유 원문이라 CFO master 가 GOAL-cfo.md 에서 복붙한 `goal-lines-cfo.txt` 를 줄 때 한 줄 추가(그 전엔 spawn lint 를 CFO 가 지금 방식대로).
- `FT_CARD_REQUIRE_PREVERIFY` 는 넣지 않는다(R16 = feature 만).

## 집행 순서
1. **CFO master(#54)에 먼저 1줄 확인** — FT_NANO_FEAT=main · 원장 경로 design/cfo/NANO-LEDGER-cfo.md 두 값이 CFO 의도와 맞는지(오빠 값을 뒤집지 않기 위해 · 원장 위치는 CFO 소유).
2. harness master: 위 본문으로 `cfo-env.sh` 설치(chmod 644 · source 전용).
3. CFO master(자기 워크트리 c-level-planning): `design/cfo/NANO-LEDGER-cfo.md` 신설 → 오기록 5행을 그대로 옮김 → `git restore design/teams/harness/NANO-LEDGER-harness.md`(c-level-planning 쪽 · 옮긴 뒤에만) → 커밋.
4. 확인: ft-nano-close 에 dry-run 이 없다(실측 · FT_WT_AUTOCLEAN=0 은 워크트리 정리만 끔). → u6 이 끝나 닫을 때 CFO 가 env 손 주입 «없이» `bash scripts/fable-team-bin/ft-nano-close.sh byz-cfo-nano-overdraft-u6#0 …` 를 첫 실닫기로 돌리고, 「팀 env 없음」 REJECT 0 + 행이 NANO-LEDGER-cfo.md 에 찍히는지 본다. 살아 있는 u6 을 확인용으로 닫지 않는다.
5. 되돌림: `cfo-env.sh` 삭제(파일 1장 · 다른 팀 무영향).

## 닫는 증거
cfo-env.sh 설치 cmp 1줄 + 다음 CFO 나노 닫기 1건이 NANO-LEDGER-cfo.md 에 기록된 행 1줄 + c-level-planning 의 harness 원장 diff 0.
