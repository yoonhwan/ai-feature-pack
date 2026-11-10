# LANDING-LEDGER — 하네스 팀 랜딩 원장 (팀 공통 형식 · L-3)

> 정본: `design/teams/harness/issue-improvement/SPEC-planner-issue-queue-20261005.md` §3 L-3 · 기계 = `scripts/fable-team-bin/ft-land.sh`(④ 후보 확정, push 없음).
> 팀마다 1 파일(`design/<팀>/LANDING-LEDGER.md`). 「랜딩됨」은 갱신할 때마다 대상 HEAD 를 다시 확인한다(`merge-base --is-ancestor <결과 sha> <대상>`) — 원장은 감사 기록이고 게이트 REJECT 를 대신하지 못한다.
> planner 큐 행에는 이 원장의 «결과 sha» 만 복붙한다.

| 카드 | 결과 sha | Issue | 방식 | 대상 | 후보 tree OID | HEAD 재확인 |
|---|---|---|---|---|---|---|
| c9m-landing-ledger-machine | (랜딩 전) | #(미배정) | ff·merge·cherry-pick -x·squash 중 1 | main | ft-land.sh 출력 `OID=` 복붙 | YYYY-MM-DD HH:MM · 원격 sha == 후보 sha |
