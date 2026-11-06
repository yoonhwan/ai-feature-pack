# 팀셋 — 팀마다 좌석 구성 표준 1장 (판정 2170 · 카드 r-teamset-standard)

> aifp 루트(ai-feature-pack) 판 — BYZ origin/main design/TEAMSET.md 를 형식 그대로 복사하고 표 2 를 aifp 행 하나로 바꿈(r1410 · arch#228 2026-11-05). 표 1·상한·닫기·세대 규칙은 BYZ 판과 같은 글이다 — 바뀌면 같이 고친다.

> 이 파일이 정본이다. 검사 `ft-teamset-check.sh [<팀>|--all]` 와 나노 개설 문지기(`ft-nano-spawn.sh` 상한 칸)가 아래 두 표를 «그대로 읽는다» — 표 형식(머리줄·열 순서)을 바꾸면 도구가 ERROR 를 낸다.
> 모델 값은 이미 정해진 것을 옮긴 것이다(새로 정하지 않음): arch = Opus 5.5 · 나노·tester = Sonnet 5.5 · DA = codex gpt-6.1-sol low · fable 은 막힌 문제에만(판정 1641). 팀 목록은 `.fable-team/seats-*.json` 파일 이름 + `seats.json`(= v65) — `design/TEAMS.md`(r318a) 착지 뒤 그쪽으로 바꾼다.

## 표 1 — 역할 표준

| 역할 | 수 | 모델 | effort | 명부 키 | 승계 | 닫기 |
|---|---|---|---|---|---|---|
| master | 필수 1 | `sonnet-5-5` | high | `_master` | ft-successor-open | 단위 마감 때만 |
| arch | 상시 팀만 1 | `opus-5-5` | high | `_arch` | ft-successor-open | 팀 마감 때 · 대기 팀 전환 때(오빠 판정 · `ft-seat-close --verdict` → 팀장 교대는 arch 없이 통과 · 자율 켜기는 arch 먼저 · r1119) |
| da | 상시 0 (소환형) | `gpt-6.1-sol` | low | `_da` | 소환 때마다 새로 | 판정 직후 |
| tester | 0~1 (press 팀만) | `sonnet-5-5` | high | `_tester` | ft-successor-open | press 끝 |
| nano | 상한 N | `sonnet-5-5` | high | — | 승계 0 | ft-nano-close (keep-last 면제) |
| desk | planner 팀만 1 | `opus-5-5` | high | `_desk` | ft-successor-open | — |

- 나노 상한 기본: 3
- 명부 역할 키(표 1 «명부 키» 열): `_master` `_arch` `_da` `_tester` `_desk`
- 명부 메타 키(표에 없어도 허용): `_name` `_version` `_version_note` `_doc` `_label` `_tree` `_tree_version` `_tree_version_note` `_tick` `_cards` `_cards_wt` `_hil_route` `_hil_route_history` `_parent` `_closed` `_persona_pool_nano` `_slack_channel` `_slack_users`

## 표 2 — 팀별 덮어쓰기

| 팀 | 나노 상한 | tester | arch 상시 |
|---|---|---|---|
| aifp | 3 | 0 | 없음 |

값 근거: 2026-10-17 13:5x 실측(`tmux ls` + 명부). 현행 수가 기본(3)을 넘는 팀(harness 4 · ops 5)은 현행을 상한으로 적었다 — 바꿀지는 팀 master 몫. v65 5 는 09-29 오빠 판정(나노 동시 상한 3 → 5). harness 8 은 10-26 오빠 판정(pi 나노 메모리 = Claude Code 의 절반 실측 · pi 적극 사용 · 최대 10 · 보수 운용 8 — 표 값은 운용 8 · 4 → 8) → 10-27 01:4x 오빠 판정 «나노 최대 18»(planner 쪽지 171604 · 8 → 18). tester 열은 허용 수(정보 · 검사는 세지 않는다). satnano 3 은 mini(위성) 나노 상한이다 — 남김 중인 나노 포함, mini free 25% 미만이면 새로 열지 않는다(첫 시험 실측 뒤 보정 · 정본 `design/teams/satnano/GUIDE-satnano-master.md`). opsintake 0 은 사용자 접수 팀(팀장 `byz-opsintake-master-claude#0` · sonnet-5 · 이 맥)이 나노를 쓰지 않는다는 뜻이다 — 정본 `design/teams/opsintake/GUIDE-opsintake-master.md`. lecture 5 는 2026-11-01 planner#196 결정(쪽지 219652 · 위성 합 8 은 219671) — 착지 직전 main 병합용 유휴 나노 4석(코드 PR 5502·5617·5619·5620)을 둔 채 L105 나노 1석을 열기 위한 임시 값 · 기한 = 그 코드 PR 4건 착지 끝 → 3 으로 복귀(복귀 PR = lecture master 몫).

## 상한 처리 (정지 대신 회수 → 순번)

나노 개설(`ft-nano-spawn.sh`) 때 그 팀 라이브 나노 수가 상한 이상이면:
1. `ft-resource-reclaim.sh --caller <발주 좌석> --need 1 --team <팀>` 1회 — 그 팀(이름 접두 ∧ 팀 명부 행) 끝난 나노(승인 두 행 안)만 닫고, 닫기 직전 소속을 다시 확인한다.
2. 그래도 상한이면 REJECT 대신 `.fable-team/state/spawn-queue-<팀>.tsv` 에 카드 절대경로 1줄 + `QUEUED <팀> 순번=<n>` · **rc 7**(rc 5 = 좌석 생성됐으나 도달 미확인 — 기존 뜻).
3. 큐 항목은 그 카드가 대기/ 에서 진행/ 으로 옮겨질 때(spawn 성공)까지 남는다. `ft-teamset-check.sh` 가 매 실행마다 «빈 석 ∧ 큐 비지 않음» 이면 그 팀 현역 master(`_master`)에 쪽지(같은 카드 10분 1번 · 실패하면 다음 실행이 다시)를 보낸다 — 자동 spawn 0, 발주 좌석이 그 턴 spawn.
4. 다른 팀은 영향 0 — 전 팀 일괄 정지 없음. 끄기: `FT_TEAMSET=0`(spawn 칸) · `FT_TEAMSET_NOTIFY=0`(알림).

## 닫기 관리 (상한과 한 쌍)

> 오빠 10-26: «나노 제한을 늘려준대신. 완료 닫기 관리를 확실히 해야해» · «나노 관리는 패블팀 핵심 지침. 카운트 관리와 같이 둬라» · «오케이 이렇게 확실히 남기고 끝냄을 관리할수있으면 이어할일은 남기는게 나이스한거지.»

상한은 «열 수 있는 수» 이고, 닫기는 그 수를 비워 두는 일이다. 둘은 한 쌍이다. 상한을 올린 팀일수록 닫기를 같은 틱에 한다.

1. **닫는 때 = 그 틱.** 아래 넷 중 하나가 생긴 틱에 닫는다(예외는 2번 «남김» 한 가지).
   - 착지(cherry OK · 팩 착지 sha 확인)
   - 리서치 산출을 넘김
   - 대체됨(다른 카드가 승계)
   - 재설계로 모델을 올려 다시 띄움(옛 석은 중단 닫기)
2. **남겨도 되는 때 = 이어 할 일이 그 나노 몫일 때.** 같은 맥락을 이어 가는 편이 낫다(새로 띄우면 맥락을 다시 읽힌다). 단, 남길 때는 카드 «## 상태» 와 그 틱 보고 둘 다에 1줄을 적는다.
   - 꼴: `남김: <이어 할 일> · <끝내는 조건>` (예: `남김: r937 반송 r3 고침 · 끝내는 조건 = arch 확정 VERDICT 또는 보류 3회`)
   - 끝내는 조건이 오면 그 틱에 닫는다.
   - ★기록 없는 남김 = 닫기 대상★ — 이 줄이 없는 끝난 나노는 «끝났는데 열린 석» 으로 센다.
3. **닫는 길(도구 그대로).**
   | 경우 | 명령 |
   |---|---|
   | 구현(BYZ 작업) | `ft-nano-close.sh <좌석> --result <판정문> --recv <seq>` |
   | 구현(팩 작업) | 위 + `--wt <팩 워크트리> --branch <팩 가지>` — 빼면 ⑥ 증거 줄을 BYZ 워크트리 HEAD 와 비교해 REJECT 된다(10-26 r922a 실측) |
   | 리서치 | `--research` |
   | 재설계로 넘김 | `--suspended "<사유>"` |
   | 대체됨 | `--superseded-by <카드 상대경로>` |
4. **셈 = 틱 보고 1줄.** 팀 master 는 틱마다 «라이브 N / 상한 M · 남김 L · 끝났는데 열린 석 K» 를 보고한다. K>0 이면 그 틱에 닫는다. «끝났는데 열린 석» = 카드 상태 줄에 [완료·휴식] 이 있거나 착지 sha 가 확인됐는데 «남김:» 줄이 없는 좌석(또는 남김의 끝내는 조건이 이미 온 좌석).
5. **사례(10-26).** r922a 착지 뒤 그 나노가 열린 채 남아 r928 재작업이 상한(AT-CAP)에 걸려 기다렸다. r922a 를 닫자 바로 열렸다.

## 세대 규칙 (검사 WARN 기준)

직전 1세대는 재개 기록 유무와 무관하게 정상(판정 1344). WARN = 같은 계보 3세대 이상 동시 라이브(keep-last-2 밖) 또는 현역 2세대 동시 WORKING.
