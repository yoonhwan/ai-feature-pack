# h 묶음 — desk 승인 질문 답글 wake (r1574 · Issue byz#8213)

목적: desk 가 오빠 승인 질문을 Slack 에 올린 뒤 답글이 와도, desk 는 쪽지가 와야 깨어난다(팀 크론 0). 그래서 답글이 34분 놓였다(실사건 #279211 · planner master #279205). 기존 감시 주기(launchd `com.byz.ft-stall-scan` · 120초)가 질문 글 ts 장부를 비모델로 훑어 오빠 답글을 찾고, 찾으면 현역 desk 에 쪽지 1통을 넣는다.

산출물(이 묶음)
| 파일 | 역할 |
|---|---|
| `feature-pack/fable-team/legacy/1.x/harness/bin/ft_desk_reply_wake.py` | 점검·등록 1개(등록은 desk 게시 직후 · 점검은 stall-scan 주기) |
| `feature-pack/fable-team/legacy/1.x/harness/bin/ft-stall-scan.sh` | 점검 호출 1줄(120초 주기 재사용 · 새 launchd 0 · 로그 `/tmp/ft-desk-reply-wake.log`) |
| `feature-pack/fable-team/legacy/1.x/harness/tests/test_desk_reply_wake_r1574.sh` | 격리 시험(가짜 명부·mbox·replies·시계·h 폴더) + 변이 4 |
| `feature-pack/fable-team/legacy/1.x/harness/docs/h-r1574-desk-slack-reply-wake.md` | 이 문서(장부 꼴 · desk 절차 · 설치 h) |

---

## §1 장부 꼴 (정본 = 이 절)

자리: `<루트>/.fable-team/state/desk-reply-wait.jsonl` — 일반 파일(0644) · 한 줄 = 한 질문 · UTF-8(BOM 없음) · 시험은 `FT_DESK_REPLY_LEDGER` 로 바꾼다.

| 칸 | 값 | 누가 씀 |
|---|---|---|
| `q_ts` | 질문 글 ts(`1794295513.494289` 꼴) | 등록 |
| `h` | `h<N>`(질문이 승인받으면 실행할 h 번호) | 등록 |
| `sha` | 질문 글에 적은 40hex | 등록 |
| `at` | 등록 epoch | 등록 |
| `deadline` | `at + 86400`(끝 시각) | 등록 |
| `state` | `open` → `notified`(답글 알림 보냄) → `closed` | 점검 |
| `notified_ts` | 알린 오빠 답글 ts(중복 억제 키 = 질문 ts·답글 ts) | 점검 |
| `notified_at` | 알린 epoch | 점검 |
| `closed` | `executed`(h 실행 기록 생김) · `timeout`(끝 시각 경과) | 점검 |

쓰기는 점검 1회마다 원자적 1회(임시 파일 → `os.replace`). 장부가 JSON 이 아니거나 못 읽으면 «판정 불가» 1줄 + 쓰기 0(줄을 지우지 않는다).

## §2 desk 게시 절차 1줄 (정본 반영 대상 · 반영은 master/arch)

정본(설치 뒤 desk 게시 절차)에 이 1줄을 넣는다 — **«Slack 승인 질문 게시 직후 장부 등록 같이: `python3 <하네스 bin>/ft_desk_reply_wake.py --register <질문 글 ts> h<N> <sha40>` · 실패면 desk 보고에 «감시 등록 실패» 1줄(조용한 0 금지)»**

등록이 빠진 질문은 감시되지 않는다(알려진 한계) — 그래서 실패를 보고에 드러낸다.

## §3 점검(120초 주기 · 비모델)

`ft_desk_reply_wake.py` (인자 없음) — 장부의 열린 줄마다:

1. `<HIL_DIR>/h<N>.ran` 있음 → 그 줄 `closed/executed`(쪽지 0).
2. 지금 ≥ `deadline` → planner `_master`(seats-planner.json)에 `[답글 없음 24시간] h<N> ts=<질문ts> → 장부 줄 닫힘` 1통 → `closed/timeout`.
3. 그 밖에 `state=open|notified`(끝나지 않은 줄) → `ft_oppa_slack_check.py <질문ts> <sha>` 1회(7초 · 재시도 1) → `SLACK-OK … reply=<ts>` 이고 `notified_ts` 와 다르면(다른 답글 ts = 1통 더) seats-planner.json `_desk` 로 `[오빠 답글] h<N> ts=<답글> → 실행 차례` 1통 → `notified`.
4. 조회 실패·토큰 없음·`_desk` 없음 → stderr «판정 불가» 1줄 · 알림 완료 기록 0(다음 주기에 다시 본다).

한 주기 조회 상한 = 4줄(`FT_DESK_REPLY_MAX`) — 4 × (7초 × 2시도) ≤ 56초 < stall-scan 예산 70초.
쓰기 범위 = 이 장부와 쪽지뿐. Slack 쓰기 0 · h 실행 0(실행은 desk).

## §4 설치 h (master · 병합 뒤)

1. 팩 → 라이브 바이너리 반영(설치기 기본 경로 · 새 launchd 0 · 새 실행 비트 0 — `bash`/`python3` 로 부른다).
2. 확인 1: `bash <라이브 bin>/ft_desk_reply_wake.py` → `desk-reply-wake 열린=0 알림=0 닫힘=0 판정불가=0` (장부 없음 = 조용한 0 아님, 요약 1줄).
3. 확인 2: `launchctl print gui/$UID/com.byz.ft-stall-scan | grep state` → running · `/tmp/ft-desk-reply-wake.log` 첫 줄 생성(120초 뒤).
4. 정본 반영: §2 1줄을 desk 게시 절차 문서에 넣는다(반영 주체 = master/arch).

## §5 시험

```
bash feature-pack/fable-team/legacy/1.x/harness/tests/test_desk_reply_wake_r1574.sh
```
격리 임시 폴더만 쓴다(실 우편함·실 Slack·실 장부 0) · `timeout 70` · ulimit 안전선 · 자기 재호출 0.
변이 4(M1 중복 억제 제거 → ⓑ FAIL · M2 조회 실패를 알림함으로 기록 → ⓓ FAIL · M3 끝 시각 검사 제거 → ⓒ FAIL · M4 수신자를 명부 첫 `_desk` 정렬값으로 → ⓑ FAIL)가 «FAIL 로 잡히는지» 까지 본다.

## §6 알려진 한계

- 감지 지연 = stall-scan 주기 1회(최대 ~2분 + 조회 시간).
- desk 가 §2 등록을 빠뜨린 질문은 감시되지 않는다.
- 장부 줄은 지우지 않는다(닫힘 표시만). 줄이 많이 쌓이면 `FT_DESK_REPLY_MAX` 가 조회를 4줄로 자른다 — 오래된 열린 줄부터 본다.
- 오빠가 답글을 지우거나 수정하면 `ft_oppa_slack_check` 판정 규칙(부모 수정 전 · 다음 질문 전)을 그대로 따른다.
