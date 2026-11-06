# COMM-GUIDE-INDEX — 절 지도 (필요한 절만 `Read offset/limit≤200`)

전문 정본 = `COMM-GUIDE.md` (410줄). 상시 로드본 = `COMM-GUIDE-BOOT.md` (17줄 ≤2KB, 여기 지도는 그 파일에서 내렸다).

- 전문 sha256 앞16 = `d64777274c4b371a` · 기준일 2026-11-06 · 전문이 바뀌면 이 값과 아래 줄 범위를 같이 갱신한다. 대조 = `ft-version.sh check`.
- 읽기 규칙: 전문 Read·cat 금지. 아래 줄 범위로 `Read(offset, limit≤200)` 한 절씩.
- HARD 열 = «읽기 전에 실행되는 계약». BOOT 17줄에 조항 단위로 실려 있으면 O, 아니면 X(경보).

| 절 | 줄 | HARD | 1줄 요지 |
|---|---|---|---|
| Serena 활성화(옛 기록 · 10-22 은퇴 — 따르지 않는다) | 8–31 | | 은퇴 문장만 유효 |
| Command Code 특이사항 | 33–61 | | cmd 세션만. 부팅 3항이 다르고 `cmd status` 크레딧 확인 |
| i-have-adhd | 63–71 | | master·architect·pm·DA·desk 기본 탑재 |
| §1 채널 선택 · #seq · ring 재발주 · 3초 busy | 73–99 | HARD | 발주=본문 파일 큐 + 창 한 줄. 재발주=ring. 같은 발주 send 반복 0 |
| jsonl 도달판정 | 101–107 | HARD | 도달 판정은 pane capture 아니라 jsonl(`ft-reach-check.sh`) |
| §1.05 안 보내고 대기 금지 · 3확인 | 109–117 | HARD | 회신은 send 로 마감. 대기 전 peek+pane+입력줄 |
| §1.1 mbox 명령·규약 | 119–155 | | send·recv·peek·relay·notify 규칙, READ 인용 |
| §1.5 발신 규율 5조항 | 157–199 | HARD | 3~5줄 · 진행보고는 파일 · master 로는 2종 · fan-out 금지 |
| relay 정본 절차 | 201–219 | HARD | 긴 본문은 relay. EMPTY_SUMMARY 는 코드 강제 |
| §0 보냈다 ≠ 도착했다 | 221–235 | | tmux 폴백 시 3회 도달검증 |
| §1 메시지 포맷 | 237–254 | | `[{from}->{to}]` · ASCII 화살표 |
| §2 검증 송신 4스텝 · Step1 HARD GATE | 256–297 | HARD | `-l`/`Enter` 별도 호출 · `pgrep -P`=0 이면 send 금지 |
| §3 수신 · §4 보고 · §4a 파일 우선 | 299–330 | | 수신·보고 규약 |
| §4b DA approve loop | 332–359 | | architect 설계 → DA 반박 → checker 확인 |
| §4c 버전 정합 | 361–401 | | tester·checker press 전 기동>최신커밋 |
| §5 금지 요약 | 403–410 | | 금지 9항 |

## HARD 조항 → BOOT 줄 대조 (6곳 전부 O)

| HARD 절 | BOOT 줄 |
|---|---|
| §1 ring·3초 | 3 |
| jsonl 도달판정 | 6 |
| §1.05 3확인 | 8 |
| §1.5 master 2종·연속 발신 | 4 |
| relay | 4 |
| §2 Step1 `pgrep -P` 게이트 | 7 |

BOOT 밖으로 빠진 «읽기 전 계약» 이 생기면 위 표에 X 를 적는다. X 가 곧 경보다.
