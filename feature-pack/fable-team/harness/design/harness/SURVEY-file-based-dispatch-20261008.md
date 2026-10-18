# 조사 표 — 파일 기반 발주·작업 원장: 지금 있는 것 · 겹침 · 공백 (판정 359 ① · byz-harness-arch-claude#10 · 2026-10-08)

## ★골 원문 (GOAL-harness.md 복붙)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

골의 축: 6-b(개선요청 접수 → 협의 → 개선) + planner 골 원문 2(팀 배정·운영 · 연결 관리 정리). 오빠 원문(판정 359): 「cfo 축 하네스 파일기록 이런 큰작업은 세션이관에 메모리되고 상태를 바로 파악하고 이슈매니저와 협의하는 파일기반 발주 … 기존 이 역할의 파일이나 구조가 있는지 먼저 파악 개선」.
★주의★: planner 발주문(#61244 전문) 머리 3줄은 **v65 골**(「빠른 유용 원문…」)이 붙어 있다 — 이 단위의 골이 아니다. 위 하네스 골 + planner 골 원문 2 로 대조했다.

## §0 결론 (3줄)
1. «작은 일»(나노 1석 = 카드 1장)과 «건별 Issue»(LOOP-LEDGER 1행)는 파일 정본이 이미 있다. **빠진 것은 그 사이 층 «세트·묶음 발주»(여러 Issue·여러 카드를 묶은 큰 작업)** 하나뿐이다 — 판정 358 CFO 7세트가 실제로 mbox 와 `/tmp/mbox/…planner-cfo-sets.md`(휘발)에만 있다.
2. 겹침은 «오빠 지시 원장»이 팀마다 이름·모양이 다른 것(v65 USER-ORDERS-REGISTER · CCU ORDERS-oppa-ccu · planner BOARD 머리 r 줄)이다. 새 파일을 또 만들지 말고 **세트 파일 1종 + 각 팀 기존 원장은 그대로 두고 링크만** 거는 쪽이 충돌이 적다.
3. 승계 자동 로드는 지금 «사람이 HANDOFF 에 손으로 적는 것»뿐이다(템플릿·map·부팅 발주 어디에도 «열린 세트 파일» 칸 없음). 뷰는 `ft-news-tree.py`(카드 폴더 기반)를 재사용할 수 있다.

## §1 지금 있는 것 (전수 · 실측 경로)
| 무엇 | 경로(실측) | 단위 | 누가 쓰나 | 승계에 실리나 | 상태 즉시 보이나 | Issue 연결 | 판정 359 요구 대비 |
|---|---|---|---|---|---|---|---|
| 나노 카드 | `design/<팀>/indices/{대기,진행,완성}/*.md` | 나노 1석 = 작업 1개 | arch 작성 · master 이동(`ft-index-move.sh`) | 폴더가 상태라 그렇다(파일) | 폴더 = 상태 · `ft-news-tree.py` 가 읽음 | 카드 머리 `- Issue:` 줄(자유 문장) | 작은 일엔 충분 · 세트 상위 없음 |
| 나노 좌석 원장 | `design/<팀>/NANO-LEDGER-<팀>.md` | 좌석 열림·닫힘 1줄 | `ft-nano-spawn/close` | 예 | 줄 시계열 | 없음 | 좌석 기록 — 발주 아님 |
| 이슈 루프 원장 | `design/issues/LOOP-LEDGER.md`(11열 · 31행 · issues master) | Issue 1건 = 1행 | issues master | 예 | 행 = 배분·닫는 사건·PR·재현·종료 | 행 = Issue | 건별엔 충분 · 세트 열 없음(issues master 의견 #61246: 마지막 칸 끝 「세트=<이름>」 만) |
| planner 보드 | `design/planner/BOARD.md`(228줄 · r50 · 10-07) | 팀 전체 할 일 인덱스(P·V·A 행) + 머리 r 줄 시계열 | planner | 예(r 줄에 승계 기록) | 사람이 읽으면 — 머리 r 줄이 수십 줄이라 느림 | 「Issue 가 정본 · BOARD 는 인덱스」 | 세트 칸 없음 · 판정 358 7세트 미기록 |
| planner 뉴스 트리 | `design/planner/NEWS-TREE.md`(10-04 마지막 갱신) · v65·kk 에도 | 트리 노드 = 카드 idx 또는 적힌 값 | planner | 예 | `ft-news-tree.py` 렌더(카드 폴더 → ✅🔄⏳) | 없음 | ★뷰 재사용 후보★ · 단 10-04 이후 갱신 0(stale) |
| CFO 할 일 1장 | `design/issues/LIST-cfo-todo-20261008.md`(issue-manager 워크트리 · 5a7cffde6d) · 같은 파일이 `design/planner/` 사본으로 v6 워크트리에도 | 우선순위 묶음 ①~④ × Issue 44건 | issues master #3 | 날짜 붙은 스냅샷(갱신 아님) | 그날 기준 | 행 = Issue | 7세트의 «재료» — 세트 이름·닫는 사건·상태 칸 없음 · main 미랜딩 |
| 판정 358 7세트 | `/tmp/mbox/20261008T093442-…-planner-cfo-sets.md`(2625B) + mbox seq 61214·61229·61236 | 세트 7 | planner → cfo master → cfo arch | ★아니오(휘발 /tmp · 쪽지)★ | 아니오 | 본문 안 번호 | ★공백 그 자체★ |
| 오빠 지시 원장 v65 | `design/v65/USER-ORDERS-REGISTER.md`(OPEN·DOING·DONE·BLOCKED) | 오빠 지시 1건 | v65 master | 예 | 상태 칸 | 일부 | 지시 단위 — 세트 아님 · 팀마다 모양 다름 |
| 오빠 지시 원장 CCU | `design/ccu/ORDERS-oppa-ccu.md`(골 원문 + 지시 표 · 창 열) | 오빠 지시 1건 | CCU master | 예 | 상태 칸 | 일부 | 위와 같은 역할 · 다른 이름 |
| 하네스 요청 원장 | `design/teams/harness/REQUEST-LEDGER.md`(R1~R25) | 개선요청 1건 | 하네스 master | 예 | 「오빠 값」 칸 | Issue 열 | 6-b 접수 원장 — 세트 아님 |
| 판정서 | `design/teams/harness/OPS-VERDICTS-20261006.md`(§1~§47) | 닫힌 단위 1개 | arch 초안 · master append | 예 | 닫힘만 | 본문 | 사후 기록 — 발주 아님 |
| 승계 스냅샷 | `design/<팀>/HANDOFF-*.md`(매번 손으로) · 정본 절차 `~/.claude/skills/fable-team/references/context-management.md:108` 승계 6단계 | 좌석 1개 | 떠나는 좌석 | 손으로 적은 만큼만 | — | — | ★«열린 세트 파일 경로» 고정 칸 없음★ |
| 마감 정본 | `design/<팀>/CLOSEOUT-*.md` · `~/.claude/rules/closeout-policy.md` | 단위·트랙 1개(끝날 때) | master | 예 | 닫힘만 | 증거 sha | 끝난 뒤 기록 — 진행 중 상태 없음 |
| 하네스 지도 | `ft-harness-info.sh map`(`references/harness-map.md`) | 정본 목차 | 하네스 | — | — | — | 「발주·세트 원장」 행 없음 |
| 좌석 명부 | `.fable-team/seats-<팀>.json` | 좌석 | spawn·승계 | 예 | 라이브 | 없음 | 발주 정보 없음(넣을 곳 아님) |
| baton NEXT.md | 워크트리 `.baton/` | 페이즈 상태 | baton save | 예(워크트리 안) | — | — | 페이즈만(골·발주 아님 — 전역 규칙에 명시) |
| 제안서 흐름 | `docs/rules/proposal_flow.md`(판정 352 · ops/main-base) | 제안서 1장 → Issue 1건 | 팀 master · issues master | 예 | 머리줄 상태 5종 | register 진입점 | 진입로 ④ — 세트 이전 단계 |

## §2 겹침
- **오빠 지시 원장 3벌**: v65 USER-ORDERS-REGISTER · CCU ORDERS-oppa-ccu · planner BOARD 머리 r 줄 — 같은 역할(오빠 지시 → 상태)인데 이름·열·상태 어휘가 다르다. 판정 359 는 이것을 통일하라는 요구가 아니다(세트 발주) — 건드리지 않고 세트 파일에서 «출처 지시 = 그 원장 행» 링크만.
- **CFO 할 일 사본 2벌**: `design/issues/LIST-cfo-todo-20261008.md`(issue-manager 워크트리) · `design/planner/LIST-cfo-todo-20261008.md`(v6-realtime-live 워크트리) — 어느 쪽도 main 에 없음. 세트 파일로 이관하면 둘 다 «스냅샷»으로 남기고 정본 지위는 세트 파일로.
- **상태 뷰 3벌**: BOARD(사람용 장문) · NEWS-TREE(카드 폴더 렌더) · 매거진(24시간 요약) — 세트 뷰는 새로 만들지 말고 NEWS-TREE 렌더기에 «세트 노드» 1종만 더하는 쪽이 최소.

## §3 공백 (판정 359 요구 4 대비)
| 요구 | 지금 | 공백 |
|---|---|---|
| ①큰 작업 발주의 파일 정본 | 세트 발주가 mbox + /tmp relay 뿐(판정 358) | ★세트 파일 1종이 없다★ — 세트명·골 축·포함 Issue·닫는 사건·상태·판정 번호·발주 seq |
| ②승계 자동 로드 | HANDOFF 손 기록 · context-management 승계 6단계에 세트 칸 없음 · map 행 없음 · 부팅 발주 템플릿 없음 | 승계 스냅샷·부팅 발주에 «열린 세트 파일» 고정 줄 + 골 대조 보고에 세트 상태 1줄 + map 행 1개 |
| ③상태 즉시 파악 | NEWS-TREE 렌더기(카드 폴더 기반) · 10-04 이후 stale | 렌더기가 세트 파일의 상태 칸을 읽는 노드 1종 · 팀 × 세트 × 상태 × Issue 표 |
| ④이슈 매니저 협의 = 파일 | LOOP-LEDGER 건별 · 세트 열 없음 · 라벨 `set:` 없음 | issues master 의견(#61246) 그대로: SETS 정본 1장(세트명·골 축·Issue·상태·닫는 사건) → LOOP-LEDGER 마지막 칸 「세트=<이름>」 · Issue 본문 맨 위 「세트: <이름>」(Tank edit · 래퍼 edit 은 R10 미구현) · 단방향 SETS → Issue |

## §4 설계 r1 으로 넘길 쟁점 (조사에서 나온 것만)
1. **세트 파일 위치**: issues master 의견은 `design/issues/SETS.md` 한 장(전 팀). 대안 = 팀별 `design/<팀>/SETS-<팀>.md`. 판정 359 요구 1 은 «팀별 tracked 경로» 예시 — 한 장이면 issues master 가 쓰기 주체, 팀별이면 팀 master 가 주체. 승계(요구 2)는 팀별이 더 단순(자기 팀 파일 1개만 읽음).
2. **Tank edit 의존**: Issue 본문 「세트:」 줄은 Tank 래퍼 edit(원장 R10 · 미구현)이 선행. 없으면 라벨 `set:<이름>` 만 먼저(래퍼 label 은 있음).
3. **CFO 7세트 원문 회수**: 첫 적용 재료는 `/tmp/mbox/20261008T093442-…planner-cfo-sets.md`(휘발) — 지워지기 전에 tracked 로 옮겼다 → `design/teams/harness/drafts/file-dispatch/ORDER-358-cfo-sets-relay-20261008.md`(cmp 일치 · 미커밋).
4. **planner 발주문 골 줄 오기**: 이 단위 발주 머리 3줄이 v65 골 — planner 에 정정 1줄(하드 룰 7).

근거: 실측 명령 = `git ls-tree origin/main design` · `git show origin/main:design/planner/BOARD.md` · `grep 판정 358 .fable-team/comm/mailbox.log.jsonl`(seq 61214·61229·61236) · `ft-harness-info.sh map`.
