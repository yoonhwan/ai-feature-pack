# harness-ops 트랙 — 이 폴더 하나로 시작한다 (fable-team Seatbelt 규약 · 2026-10-04 · planner P9)

목표는 빠른 유용 원문, 실시간 교정, N언어의 병렬·독립 발행, 소실·비의도 중복 없는 최종 말풍선이다.
LST ON 우선이며 LST OFF/전환과 기존 M0–M7·통합 조건도 남긴다.
단순히 실패 사례를 많이 모았다는 이유로 실험을 닫지 않는다.

> harness-ops = 메인 팀 ①. 제안서 정본 = v6-realtime-live/design/planner/PROPOSAL-team-harness-ops.md(r1 · 오빠 GO 13:0x). 코드 범위 = .fable-team/** · .claude/** · hooks/** · 글로벌 ~/.claude/skills/**(커밋 밖 → 설치 스크립트). 제품 코드 0 · 라이브 인프라 0 · 머신 안 세션 send-keys 0.
> 원리 세 줄: 작업 = 인덱스 파일 1개 · 상태 = 폴더 · 좌석은 갈아 끼운다(파일이 상태).

## 파일 지도
| 파일 | 역할 |
|---|---|
| `GOAL-harness.md` | ★불변★ 오빠 원문 + 축 A·B·C 좌표표 |
| `GUIDE-harness.md` | 팀 지침 — 팀 폴더 설치 1장은 GUIDE-team-tree-install-20261018.md |
| `STATE.md` | 재개용 요약 1장 — 지금 단위·카드 폴더·착지·설치 표(링크만) |
| `REQUEST-LEDGER.md` | 축 B 원장 — 요청자·증상·Issue #·오빠 값·반영 sha (행 추가만) |
| `RELEASE-<ver>.md` | 축 C 발행 1장/버전 — 변경·설치 명령·머신별 반영 행 |
| `indices/{대기,진행,완성}/` | 카드 1장 = 1단위 · inbox/arch/ = planner·오빠 접수 |

## 부팅 5단계
① 골 대조: GOAL 원문 읽고 「첫 단위가 축 A/B/C 어디인가」 한 줄.
② 내 자리: 루트 .fable-team/seats-harness.json 에 내 행(_master).
③ 내 일: indices/inbox/arch/ 맨 위(00-first-unit.md).
④ 통신: bash <루트>/.fable-team/comm/mbox.sh recv <나> · 보고 3~5줄 · HIL = [HIL] → byz-planner-arch#1(seats-harness.json _hil_route) — 인터뷰 금지.
⑤ 첫 보고: byz-planner-arch#1 에 「세션명 / 모델·창 / Serena / ①의 한 줄」.

## 운영 루프
수신 이벤트(오빠 요청 · 오케 개선요청 mbox/Issue · 모니터 이상) → Issue 등록(team:shared-harness) → 검토·수정 → 시험(훅은 셔뱅 그대로 -n · 적용 뒤 첫 도구 호출 확인) → 커밋·push(feat/harness-ops → PR → main · 로컬 검증 먼저) → RELEASE 발행 → 반영 회수. 글로벌 CLAUDE.md 하드 룰·훅 deny 변경·전 머신 강제 재설치 = [HIL].
