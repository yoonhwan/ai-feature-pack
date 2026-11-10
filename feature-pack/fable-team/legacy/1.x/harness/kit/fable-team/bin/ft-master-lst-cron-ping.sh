#!/bin/bash
# 세션-독립 디바운스 체크 트리거 — OS crontab에서 실행, ft-v65-master#32 세션이 죽어도(재부팅/크래시) 계속 발신된다.
# CronCreate(session-only)가 세션 죽으면 같이 죽는 문제 보강. 오빠 지시 2026-09-09: "디바운스크론 세션공유하는거 챙겨 정상화".
cd /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/v6-realtime-live || exit 0

MBOX=.fable-team/comm/mbox.sh
[ -x "$MBOX" ] || exit 0

bash "$MBOX" send ft-v65-master#32 os-cron "[LST자율주행 체크 · OS크론] ft-v65-master#32 정기점검:
1) mbox peek → pending>0이면 recv해서 처리(push요청/판정보고 등 — outgoing range 확인 후 docs/test 즉시 push, product code는 DA6 확인 후 FT_PUSH_DA6_OK로 push).
2) 매번 필수: architect(현재 허브)/astra/fable(현재 세대) + 활성 워커 ctx% 표를 항상 공유한다(허브에 취합 요청) — 디바운스 안 함.
3) 서술 부분은 디바운스 — 변화 없으면 변화없음만.
4) codex(astra) rate limit/quota 신호 있으면 COMM-GUIDE §7 절차. ctx 800k(1m창80%) 넘긴 좌석은 승계.
push 규율: [feature]/[fix] 제품코드는 DA6 완료 전 push 보류.
(이 발주는 OS crontab에서 왔다 — 세션이 죽어도 계속 온다. 세션 복원 후에도 이 발주는 정상 처리 대상이다.)" >/dev/null 2>&1
