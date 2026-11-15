# 인덱스: mbox-peek-rows-pass — 끝: mbox.sh peek <좌석> --rows 가 mbox.py peek <좌석> --rows 와 같은 줄을 낸다 · 인자 없는 peek 출력은 글자 그대로다 · 모르는 인자는 조용히 버리지 않고 rc 2 로 멈춘다
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: 없음(초안) — 넘김 byz-harness-master-pi#293 aifp 5782 · 팀장 aifp-ft-master-pi#21 발주 aifp 5783 · 발견 = 이 좌석 실측 aifp 5768(설치 뒤 keeper 가 미읽음 판독 --rows 로 막음)
- 제안서: 없음 — 결함 복구(인자 1개 넘기기) · 설계 = 이 카드 «계약»·«반례 표»
- 근거: 실측 2026-11-16 05:58(aifp-ft-arch-pi#21 · BYZ .fable-team/comm · 읽기만) — 아래 «기준값» 절
- 원인 1줄: feature-pack/fable-team/legacy/1.x/harness/comm/mbox.sh 323줄 `peek)  exec python3 "$MBOXPY" peek "${1:?me}"` 가 첫 인자만 넘긴다 · 뒤 인자(--rows)는 말없이 버려진다 · mbox.py 166줄은 `--rows` 를 이미 읽는다
- 앞 카드: 진행/ft2-done-seat-short-idle(A4 = peek --rows · 착지 14c2f051 · 조건 6·7 [~]) · r1153(peek = recv 와 같은 대상 규칙)
- 앞 카드와의 관계: 진행/ft2-done-seat-short-idle 은 mbox.py·mbox_ops.py 에 --rows 를 넣었지만 keeper 가 부르는 입구는 mbox.sh 다(ft2/adapters/pi/keeper_settle.py 395줄 `bash <mbox.sh> peek <좌석> --rows`) · 이 카드가 착지·설치되면 그 카드의 조건 6(설치 판 ft2 + mbox)·조건 7(`미읽음 마감 n통 제외` 실사건)을 다시 잴 수 있다
- 상태: 대기
- 설치: 있음 — 1.x comm 도구(mbox.sh) 설치 1회(harness) · ft2 판 올림 없음 · 되돌림 = 앞 mbox.sh 로(keeper 는 지금처럼 미읽음 1통이라도 막는 동작으로 돌아간다)
- 선행: 없음
- 시험 입력: 가짜 쪽지함 폴더(FT_MBOX_DIR) · 가짜 명부(FT_SEATS_JSON) · 시험 안에서 보낸 쪽지 · sleep 0 · 네트워크 0 · 실 우편함 읽기·쓰기 0 · tmux 호출 0 · 사례 1개 70초 안
- 기준값: 지금 `bash mbox.sh peek <좌석> --rows` = 머리줄 1줄뿐(pending=2 인데 행 0줄) → 목표 = 머리줄 + 미읽음마다 JSON 1줄(mbox.py 와 같은 바이트)
- 규칙: 없음 — 상시 로드 변경 0(도구 한 줄과 사용법 글만 바뀐다)
- 규칙 상세: 하드 룰 20(외부 명령 실패 = rc≠0 1줄) · 하드 룰 22
- 대상: 팩 feature-pack/fable-team/legacy/1.x/harness/comm/mbox.sh(peek 갈래 1줄 · 사용법 2줄) · 새 시험 feature-pack/fable-team/legacy/1.x/harness/tests/scripts/test_mbox_sh_peek_rows.py
- 정본 영향 없음: aifp 정본(docs/architect · docs/rules · design 팀 GUIDE·README) 변경 0 — 바뀌는 것은 팩 1.x comm 도구 mbox.sh 와 그 시험뿐이다
- 크기: 코드 1파일(3줄 안팎) · 새 시험 1파일 · PR 1개
- 배정: 대기(DA · 2026-11-16T05:58)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
6 — 하네스 운영 정리. 하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」. 골의 축: 6(끝난 좌석을 keeper 가 마감 쪽지 1통 때문에 붙잡지 않는다). 이 카드의 증거 = 착지 sha + 시험 rc0 + 설치 뒤 `bash mbox.sh peek <좌석> --rows` 원문(머리줄 + JSON 줄) + keeper 로그의 `미읽음 판독 --rows` 줄이 더 늘지 않음.

## 배경 (한 단락)
앞 카드는 끝난 좌석 앞에 마감 쪽지만 남았으면 닫기를 막지 않게 했다. 그러려면 keeper 가 미읽음 쪽지의 본문을 읽어야 한다. 그래서 peek 에 --rows 를 넣었다. 그런데 keeper 가 부르는 것은 mbox.sh 이고, mbox.sh 의 peek 갈래는 좌석 이름만 mbox.py 로 넘긴다. --rows 가 사라지니 keeper 는 행을 못 받고, 미읽음이 1통이라도 있으면 막는 옛 동작으로 떨어진다. 2.0.70 설치 뒤 harness 두 좌석이 그렇게 막혔다.

## 기준값 (실측 원문 · 2026-11-16 05:58 · BYZ .fable-team/comm · 좌석 byz-harness-nano-r1909-ft20-root-of-ft-root-caller-rc#0)
| 명령 | 출력 |
|---|---|
| `bash mbox.sh peek <좌석> --rows` | `pending=2 latest_seq=311840 from=ft-nano-record scanned=1 lineage=0` 1줄 · rc 0 |
| `python3 mbox.py peek <좌석> --rows` | 같은 머리줄 + JSON 2줄(seq 311834 · 311840 · ts · to · from · body) |
| `bash mbox.sh peek <좌석>` | 머리줄 1줄(위와 같은 글자) |
| BYZ comm 의 `--rows` 글자 | mbox.py 1줄 · mbox_ops.py 1줄(고친 때 05:56) · mbox.sh 0줄 |
| keeper 로그(설치 05:31:49 뒤) | `05:37:51 UNKNOWN harness r1909-…#0 mail-pending · 미읽음 판독 --rows` · `05:37:54 UNKNOWN harness r1924-…#0 mail-pending · 미읽음 판독 --rows` |

팩 안에서 mbox.sh peek 에 좌석 이름 말고 다른 인자를 주는 곳은 keeper_settle.py 395줄 1곳뿐이다(시험 밖 .sh·.py·.ts 를 grep 으로 봄 · 나머지 부르는 곳은 `peek <좌석>` 꼴).

## 계약
- Q1 `mbox.sh peek <좌석> --rows` = `python3 mbox.py peek <좌석> --rows` 를 그대로 실행한다 · stdout 바이트와 rc 가 같다
- Q2 `mbox.sh peek <좌석>`(뒤 인자 없음) = 지금과 같은 명령 · 출력 글자 그대로
- Q3 모르는 인자 = 좌석 뒤에 `--rows` 가 아닌 낱말이 있거나 인자가 3개 이상이면 rc 2 · stdout 0줄 · stderr 에 `usage: mbox.sh peek <me> [--rows]` 1줄 · mbox.py 호출 0(조용히 버리지 않는다)
- Q4 좌석 이름은 첫 인자다 · `peek --rows <좌석>` 은 Q3 으로 멈춘다 · 좌석 없음은 지금처럼 오류로 끝난다
- Q5 사용법 글(파일 머리 5줄 · 끝 usage 줄)의 peek 칸을 `peek <me> [--rows]` 로 고친다
- Q6 그대로: recv 갈래 안의 peek 호출(319줄 · PENDING-AFTER) · mbox.py · mbox_ops.py · 다른 갈래 · keeper_settle.py

## 반례 표 (가짜 쪽지함)
| # | 입력 | 기대 | 지금 |
|---|---|---|---|
| ㊶가 | 미읽음 2통 · `mbox.sh peek <좌석> --rows` | 3줄 · `mbox.py peek <좌석> --rows` 출력과 바이트 같음 · rc 0 · JSON 줄의 seq 가 보낸 순서 | 1줄 |
| ㊶나 | 미읽음 2통 · `mbox.sh peek <좌석>` | 머리줄 1줄 · 기준판 mbox.sh 출력과 바이트 같음 | 같음 = 회귀 고정 |
| ㊶다 | 미읽음 0통 · `--rows` | `pending=0 …` 1줄 · rc 0 | 같음 |
| ㊶라 | `mbox.sh peek <좌석> --row` · `peek <좌석> x` · `peek <좌석> --rows x`(3칸) | 칸마다 rc 2 · stdout 0줄 · usage 1줄 | rc 0 · 머리줄(인자 버림) |
| ㊶마 | `mbox.sh peek --rows <좌석>` | rc 2 · usage 1줄 | `--rows` 를 좌석 이름으로 넘김 |
| ㊶바 | `mbox.sh recv <좌석>` 뒤 끝 줄 | `PENDING-AFTER <n>` 그대로 | 같음 = 회귀 고정 |
| ㊶사 | ㊶가 뒤 다시 `peek <좌석>` | pending 2 그대로(--rows 가 읽음 표시·소비를 하지 않는다) | — |

범위 밖 입력(하드 룰 18·19·20): 줄바꿈·탭 든 좌석 이름 · 권한을 바꾼 쪽지함 파일 · python3 가 없는 환경.

## 구현 범위 (나노 1 · 팩 base origin/main 최신 · DA 설계 승인 뒤)
1. 커밋 1 [test] — 새 시험 feature-pack/fable-team/legacy/1.x/harness/tests/scripts/test_mbox_sh_peek_rows.py(㊶가~사 · 변이 M92·M93) · 쪽지함 대역은 같은 폴더 test_mbox_peek_self_sent_r1153.py 의 꼴(FT_MBOX_DIR · FT_SEATS_JSON)을 쓴다 · 기준판 FAIL 원문(㊶가 · ㊶라 · ㊶마)을 PR 본문에 붙인다
2. 커밋 2 [fix] — Q1~Q5 = feature-pack/fable-team/legacy/1.x/harness/comm/mbox.sh 의 peek 갈래 1줄 + 사용법 2줄 · 다른 갈래 손 0 · 다른 파일 손 0
3. 회귀 rc0(파일별 · 각 70초 상한): test_mbox_peek_self_sent_r1153 · ft2 tests 의 test_done_seat_short_idle
4. 실행 = `python3.11 -m pytest` · 착지 = PR 1개(팀장 집행) · 설치 = harness(1.x comm)

변이: M92 --rows 를 넘기지 않음(지금 줄) → ㊶가 / M93 뒤 인자를 검사 없이 전부 넘김 → ㊶라·㊶마

## 범위 밖
- keeper 가 mbox.sh 대신 mbox.py 를 직접 부르게 바꾸기(입구 1곳 원칙 · ft2 손 0)
- kit 사본(feature-pack/fable-team/legacy/1.x/harness/kit 아래 ft-mbox.py 등)과 skill 사본의 peek — 이 카드는 keeper 가 부르는 comm/mbox.sh 만 고친다 · 사본 맞추기는 설치 도구 몫
- 미읽음 판독의 뜻(A5~A8)과 마감 쪽지 꼴 — 앞 카드 그대로

## 완료 조건
1. [ ] 나노: 커밋 1 기준판 FAIL 원문(㊶가 · ㊶라 · ㊶마)
2. [ ] 나노: 새 시험 전체 rc0 · 걸린 초
3. [ ] 나노: 변이 M92 → ㊶가 FAIL · M93 → ㊶라·㊶마 FAIL
4. [ ] 나노: 회귀 rc0(파일별 초)
5. [ ] 팀장: PR 착지 sha · harness comm 설치 확인 1줄
6. [ ] arch: 설치 뒤 읽기 실측 = BYZ `bash .fable-team/comm/mbox.sh peek <미읽음 있는 좌석> --rows` 원문(머리줄 + JSON 줄 수 = pending) · 그 뒤 keeper 로그에 `미읽음 판독 --rows` 줄이 새로 0 · 진행/ft2-done-seat-short-idle 조건 6·7 을 다시 잰 줄을 그 카드에 적는다

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| Q1 --rows 넘김 | ㊶가 · ㊶다 · ㊶사 · M92 |
| Q2 인자 없는 peek 그대로 | ㊶나 |
| Q3 모르는 인자 rc 2 | ㊶라 · M93 |
| Q4 좌석이 첫 인자 | ㊶마 · M93 |
| Q5 사용법 글 | ㊶라(usage 줄 글자) |
| Q6 그대로 | ㊶바 |

## 상태
- base_sha: a964e15c581c955851729936f6d4dabfcf53778a
- 2026-11-16 05:58 · 대기 — aifp-ft-arch-pi#21 초안(팀장 aifp 5783 · 넘김 harness#293 aifp 5782 · 실측 = BYZ comm 명령 3개 원문 · 구현 0) · 다음 = 팀장 PR → DA 설계 → Issue → 나노 1석 → harness comm 설치
