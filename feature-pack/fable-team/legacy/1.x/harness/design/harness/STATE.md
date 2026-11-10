# harness 상태

재개용 요약 + 링크만 · 좌석 정본 = 명부(`.fable-team/seats-harness.json`) · 작업 상태 정본 = 카드 폴더(`indices/`) · 갱신 = 팀 오케.
좌석·진행 단위를 여기에 복사하지 않고 가리키기만 한다.

## 골·지침 (복제 0 — 정본을 가리킨다)

- 골 정본(불변): `GOAL-harness.md` · 팀 지침: `GUIDE-harness.md` · 팀 폴더 설치 1장: `GUIDE-team-tree-install-20261018.md`
- 요청 원장(축 B): `REQUEST-LEDGER.md` · 착지 원장: `LANDING-LEDGER.md` · 나노 원장: `NANO-LEDGER-harness.md`

## 지금 하는 단위

- R373 — 하네스 도그푸딩 + 시험 팀 신규 랜딩 시나리오: `indices/진행/r373-harness-dogfood-new-team-landing-scenario.md`

## 열린 카드 (폴더 링크 — 목록을 여기에 옮겨 적지 않는다)

| 폴더 | 뜻 |
|---|---|
| `indices/inbox/` | planner·오빠 접수 |
| `indices/대기/` | 착수 전 카드 |
| `indices/진행/` | 나노가 일하는 카드 |
| `indices/완성/` | DA 판정 뒤 닫힌 카드 |

## 최근 착지 (main · 원장 = `LANDING-LEDGER.md`)

| 요청 | 무엇 | sha |
|---|---|---|
| R368 | 팀 폴더 표준 일괄 적용 + 명부 버전 패치 | `0d94a216c1` |
| R364 | 직접 spawn 좌석 재개 기록 바인딩(1단계) | `7ce8b2d05d` |
| R370 | 승계 좌석 index 상속 + nano-close 사슬 후퇴 | `8884f4229f` |
| R372 | 가드 판정기 경로 LIVE_BIN 해석 | `77d05f7ffc` |
| R371 | 골 표 상태 칸 = planner 원장 자동 읽기 | `a2ad95246c` |

## 설치 (전 팀 패치 순서 = planner 판정 2262)

| 단계 | 상태 | 증거 |
|---|---|---|
| 하네스 팀 자기 설치(도그푸딩) | 진행 — R373 | 위 카드 «시나리오 기록» |
| planner 팀 설치 | 대기 — R373 착지 뒤 | h48 |
| 전 팀 `ft-team-upgrade.sh --all` | 대기 — 완성 뒤 | R373 카드 |
