# DA 사전검증 발주 — PLAN-harness-networking r0 (arch#29 → da-codex#1 · bounded · 2026-10-11)

골 원문(3줄):
「목표는 빠른 유용 원문, 실시간 교정, N언어의 병렬·독립 발행, 소실·비의도 중복 없는 최종 말풍선이다.」
「LST ON 우선이며 LST OFF/전환과 기존 M0–M7·통합 조건도 남긴다.」
「단순히 실패 사례를 많이 모았다는 이유로 실험을 닫지 않는다.」
골의 어느 축: planner 원문 2(팀 배정·운영 · 베이스-위성 연결 관리) — 팀 운영 구조의 근원 5 제거(판정 1069·1070 · 오빠 「그래」 = REVIEW §6 A~D 채택).

## 고정 대상
- 파일: `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops/design/harness/PLAN-harness-networking-20261011.md` (r0 · 커밋 `ca65722ee106a4f535b8e2d09439b27738eefc00` ops/main-base · 파일 sha256 앞16 `ea71413cc3e3bd99` · 148줄)
- 범위: §2 장치 D1~D9 + §3 설치 순서. 범위 밖 = D10(기존 제안 ① · 판정 881) · 근원 ④(R102 랜딩 15b8920236 · 유지만) · 오빠 채택안 A~D 자체(값 — 뒤집지 않는다).
- 기준 코드: origin/main `32d0374ed0e8` · 라이브 도구 `v6-realtime-live/.fable-team/bin`(ft-board.py · ft-seat-retire.sh · ft-seat-status.sh · mbox.sh=루트 `.fable-team/comm/mbox.sh`) · 정본 `~/.claude/skills/fable-team/references/main-team-governance.md` · `~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md`.
- 런타임 범위: 메인 팀 9(planner·harness·v65 상시 · 그 외 일감 단위) · tmux 세션 85 · 명부 seats*.json 10 · launchd 틱 4 · 쪽지 2,164/일.

## 수락 증거 (PLAN §0 실측 · §8 닫는 증거)
- §0 표 12행이 바이트 실측(틱 73% · planner 238/일 · 분류 ⑥+⑤ 57% · 세션 85 · 도구 실재/부재).
- 목표 숫자 3: 승계 ≤2/일 · planner 앞 쪽지 ≤60/일 · 틱 1회 jsonl 증가 ≤4KB.

## DA 가 답할 질문 (한 번에 · 원인별 묶음 · 반례 1개씩 직렬 HOLD 금지 — docs/rules/bounded_da_review.md)
1. **닫는 사건**(once_set_state): D1 `ft-team-close` 가 closeout-policy 5(전부 닫기) · 전역 하드 룰 2(역할 좌석 keep-last-2 · 초과 kill 은 표준승인 · 보존 2 는 HIL) · STRUCTURE §2 종료 4항 — 셋과 동시에 정합한가. 열린 상태(일감 단위 팀)의 «닫는 사건»이 기계로 판정되는가.
2. **D4 가 막아서 늦어지는 비가역이 있나**: `[HIL]` 머리 REJECT(별칭 0) 가 라이브 장애·파괴 승인 보고를 1턴 늦추는 경로가 있나. `[긴급]` 별칭이 필요한가, 아니면 `[결정]` 3줄로 충분한가.
3. **D2 한 줄 틱이 BOOT 18(정지 3분 = 그 턴 처리)을 약화시키나**: stalled 행이 틱 줄에 실리는 설계로 충분한지, 「할 일 없음」 조기 종료가 놓치는 상태(완료 선언 미처리 · 완료 뒤 작업)가 있는지.
4. **D3 REJECT 의 창**: 승계 직후 후계 이름이 명부에 아직 없는 구간(은퇴 표시 전)에 발신이 막히거나 옛 큐로 새는 경로가 남나. `_replaced_by`·`closed` 둘 외 상태값(`stop-ready`·`_retired_role`)의 취급.
5. **부하·메모리 칸**(async_io 규칙): D2 `--from-snapshot`(launchd 300초 스냅샷)이 틱 시점과 최대 5분 어긋나는 것이 상태 거짓(판정 511)에 해당하나. 새 데몬 0 주장의 반례.
6. **7초 룰**(§4): 외부 호출 누락 지점.

## 시간 · 회차
- 첫 검토 10분 + 보정 검토 10분. HOLD 2회면 중단 → arch 가 범위를 D4 + D1 close 로 좁혀 1회 더(판정 1060 선례). 그 뒤는 planner 허가.
- 판정 회신: `mbox send byz-harness-arch-claude#29 byz-harness-da-codex#1 "[DA r0] APPROVE|HOLD — 원인별 묶음 <n>건 · 각 1줄 + 파일:절"` · 긴 본문은 relay 파일(`design/harness/DA-harness-networking-r0.md` 에 Write 가능 · 커밋 0).
- 실행 헤더 `model:`/`provider:` 두 줄 남길 것(실브레인 확인).
