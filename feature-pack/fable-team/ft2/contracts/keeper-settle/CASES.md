# ft2 keeper settle 계약 사례표 (r2055 · 보정 3 · 카드 ft2-done-seat-short-idle)

`CONTRACT.md` 의 약속마다 **입력 → 기대 결과**와 그것을 묶은 시험을 적는다.
사례 문장은 설계 정본 §7·§12·§13 과 시험 파일의 사례 주석에서 옮겼다. 새 사례는 없다.
이 폴더에는 replay 검사기가 없다. 사례는 아래 시험 4개가 직접 돈다(임시 루트 · 실 tmux·실 runtime 0).

| 시험 파일(`feature-pack/fable-team/ft2/tests/`) | 사례 | 변이 |
|---|---|---|
| `test_core_park_capacity_r2055.py` | ③ ⑧ ⑪ ⑪′ ⑬ ⑭ ⑮ | M1 · M2 |
| `test_settle_one_path_r2055.py` | ① ② ②′ ③ ④ ④′ ⑤ ⑥ ⑦ ⑨ ⑩ ⑪ ⑫ ⑰가~바 ⑱ ⑲ ⑳ ㉕가·나·다 | M3 · M4 · M5 · M6 |
| `test_settle_da_r2055.py` | DA 반례 R1~R4 · ㉑가~라 · ㉒가~바 · ㉓ · ㉔ | — |
| `test_slack_accept_capacity.py` | ㉖가~바 | M7 · M8 · M9 |
| `test_keeper_notify_recipient.py` | ㉚가~거 | M17 · M18 · M19 · M23 · M24 · M25 · M32 · M33 |
| `test_launch_failed_end.py` | ㉘가~카 · ㉛가~라 | M11 · M12 · M13 · M16 · M30 · M31 |
| `test_prereq_unreadable_once.py` | ㉟가~하 · ㉟거 | M39 · M40 · M41 · M56 · M57 · M58 |
| `test_done_seat_short_idle.py` | ㉙가~도(27) | — (변이는 아래 두 파일) |
| `test_done_seat_short_idle_mutants.py` | — | M20 · M21 · M22 · M44 · M45 |
| `test_done_seat_short_idle_mutants_b.py` | — | M51~M55 |

돌리는 법: `python3.11 -m pytest feature-pack/fable-team/ft2/tests/test_core_park_capacity_r2055.py -q`(나머지도 같은 꼴 · 시험 1개 70초 상한).

## 1. settle 판정 사례 (`test_settle_one_path_r2055.py`)

| 사례 | 입력 | 기대 | 계약 절 |
|---|---|---|---|
| ① | 끝난 나노 · 착지 0 · clean · push 됨 · 유휴 ≥ 60분 | `PARKED` · 닫기 1 · journal parked 1줄 · 용량 −1 · 의무 그대로 | §1 · §2 · §6 |
| ② | 팀 걸친 카드(짝 표 없음 · 본문 경로) · 착지 줄 조상 | `LANDED`(complete + 닫기) | §2 · §8 |
| ②′ | 본문 경로 실패 | 사유 꼬리 · 짝 표가 먼저(본문 읽기 0) · `..` 경로 무시 | §8 |
| ③ · ⑫ | 세션 0 · owner 남음 · intent closed 또는 failed | `UNKNOWN launch-failed`(쉼 1회는 그대로 · `PARKED` 줄 0 · r2058 L3) · owner·예약 해제 · 용량 −1 · 새 attempt 로 다시 | §3 · §5 |
| ④ | ALL_STOP 있음 + ① 입력 | 닫기 0 · park 0 · fill 0 · «예정 PARKED» 1줄 | §7 |
| ④′ | ALL_STOP 깨짐 | 정지 + 판정 불가 1줄 | §7 |
| ⑤ | 새 꼴(intent 에 worktree 칸 없음) | `UNKNOWN` · [긴급] 1통 · 닫기 0 · 같은 지문 = 전송 0 · **전송 실패도 그날 지문**(재시도 0 · 다음 날 1회) | §3 · §4 |
| ⑥ | 스피너 / 일하는 pi(API 대기 · %cpu 0.0 ×2 · jsonl 5분 전 · 스피너 없음) | 둘 다 `WORKING` · 닫힘 0 · park 0 | §2 |
| ⑦ | 유휴 ≥ 60분 · dirty 또는 push 안 됨 | `UNKNOWN` [긴급] · 닫기 0 | §2 · §3 |
| ⑨ | 질문 창(toolUse · jsonl 무활동 16분) · %cpu 0.1 ×2(30초) | `UNKNOWN waiting-input` · [긴급] 팀장 · 닫기 0 | §3 |
| ⑩ | 원장 done ∧ 카드 완성 폴더 · PR 0 · 가지 이름 다름 | `LANDED`(넓힌 근거) · 세션 닫힘 | §2 |
| ⑪ | accept 만 · `PARK_IDLE` 넘음 · 같은 work command 2개 | 용량 1 · 의무 2 · `UNKNOWN accept-only` 1줄 | §3 · §6 |
| ⑰가~바 | 장기 좌석 여섯 사례(2세대 NORECORD · 재개 기록 있음 · 3세대 NORECORD · close 영수만 있는 현역 · ready 0 · 승계 안 된 유휴) | 끝남 근거와 닫기 자격을 둘 다 채울 때만 닫기 · 보존 = `keep-recent`·`keep-last-2` · ready 0 = `ready-wait` | §8 |
| ⑱ | 명부 밖 `byz-*` · 이름 lint 실패 · 1차 쉼 ∧ 닫기 직전 pane Working | `UNKNOWN roster-outside` · `name-bad` · `tmuxc-mismatch` · 닫기 0 | §3 |
| ⑲ | pane 명령 zsh(shell-only) · clean · push / 같은 꼴 dirty | 앞 = `PARKED` · 뒤 = `UNKNOWN shell-only-unsafe` · 둘 다 `WORKING` 아님 | §2 · §3 |
| ⑳ | tmuxc 대조: 사슬 끝(pane → npm → node → pi) %cpu 0.5 / 0.1 ×2(30초) | 0.5 = busy · 0.1 ×2 = idle · 셸 목록·깊이 = tmuxc 규칙 | §2 |
| ㉕가 | dict-work accept 2 + str-work accept-only 1 + 다른 work dispatch 1 | 예외 0 · `UNKNOWN accept-only` = str work 1건만 | §6 |
| ㉕나 | dispatch 0 · dict-work accept 만 | 예외 0 · `UNKNOWN` 0 · [긴급] 0 | §6 |
| ㉕다 | 같은 journal 로 keeper 한 바퀴 | 끝까지 감 · 다른 판정 줄 = dict-work 줄이 없을 때와 같음 | §6 |

변이(원본 같은 사례는 PASS · 변이 사본은 FAIL 이어야 한다):

| 변이 | 바꾸는 곳 | 잡는 사례 |
|---|---|---|
| M3 | 질문 창 판정에서 CPU idle 조건을 거짓으로 | ⑨ |
| M4 | 후손 pid 깊이를 2로 | ⑳ |
| M5 | 유휴 판정에서 jsonl 무활동 조건을 뺌(CPU 단독) | ⑥ |
| M6 | `accept_only` 의 work 문자열 가드를 뺌 | ㉕가 |

## 2. core park·capacity 사례 (`test_core_park_capacity_r2055.py`)

| 사례 | 입력 | 기대 | 계약 절 |
|---|---|---|---|
| ③ | 세션 0 · owner 남음 | `park(launch-failed)` · owner·예약 해제 · 용량 −1 · 의무 그대로 | §5 · §6 |
| ⑧ | 쉼 work 에 새 dispatch(같은 자원 R) | 배정 성공 · parked 지워짐 | §5 |
| ⑪ | 같은 work command 2개(accept 만) | 의무 2줄 · 용량 1칸 | §6 |
| ⑪′ | 상한 8 · 쉼 1 | 9번째 접수 성공(용량 상한 = work 단위 · 쉼 제외) | §6 |
| ⑬ | 쉼 W(done 0 · owner 0) | 마감 gate `PENDING_NOT_ZERO:1` 그대로 · 재개 queue 에 W 남음 | §6 |
| ⑭ | park journal 줄 뒤 state 전 crash → 복구 → park 다시 | 복구가 parked 를 앞섬 · 두 번째 park = `HOLD` 멱등 · 예약 0 | §5 |
| ⑮ | 효과 의도 뒤 결과 0 · uncertain 표식 · 낡은 attempt · 완료 | 거절 · 쓰기 0 | §5 |

| 변이 | 바꾸는 곳 | 잡는 사례 |
|---|---|---|
| M1 | `core/record.py` fold 에서 예약 해제를 뺌 | ⑧ |
| M2 | `core/intake.py` 접수 상한을 `capacity` 대신 `remaining` 으로 | ⑪′ |

## 3. DA 반례·끝남 판독 순서 사례 (`test_settle_da_r2055.py`)

| 사례 | 입력 | 기대 | 계약 절 |
|---|---|---|---|
| R1 | 끝난 좌석 · jsonl 1분 전 | `WORKING` · 닫기 0 | §2 |
| R2 | 재개 기록에 없는 대화 uuid 만 | 검증된 재개 기록이 아님(닫기 0) | §8 |
| R2 | 이름 바뀐 후계 | 양방향 결속일 때만 같은 계보 | §8 |
| R3 | 정지 중 명부 밖 나노 꼴 | `UNKNOWN roster-outside` 판정 줄 있음 | §3 · §7 |
| R3 | attached 조회 실패 | `UNKNOWN` = [긴급] 전송 | §4 |
| R4 | 팀 밖 카드의 끝 표식 | `resolve_card` 로 읽음 | §8 |
| ㉑가 | `tmuxc clean` rc0 · 그 세션 없음 · pane_pid·ps 정상 | capture 0 으로 판정 | §2 |
| ㉑나 | tmuxc 실행 파일 없음 / tmuxc rc 1 | 2차로 내려감 · pane Working = `WORKING` · 쉼 ×2 ∧ 무활동 ≥ `PARK_IDLE` ∧ 안전 = `PARKED`(꼬리 «판독 2차») | §2 |
| ㉑다 | 입력줄 `❯ Working on it` 만 | 쉼(입력줄 글자는 근거 0) | §2 |
| ㉑라 | `tmuxc clean` 이 그 세션을 냄 · clean · push · 무활동 ≥ `PARK_IDLE` | `PARKED` · capture = 가드 1회 | §2 |
| ㉒가·나 | ps rc≠0 / pane_pid 판독 실패 · 끝난 나노 · 무활동 2시간 | 2차 쉼 ×2 → `PARKED` · `WORKING cpu-unknown` 0 | §2 |
| ㉒다·라 | pi 프로세스 또는 shell-only · 세션 파일 없음 | `UNKNOWN session-none` [긴급] · 닫기 0 | §3 |
| ㉒마 | ps 실패 ∧ capture 실패 | `UNKNOWN probe-fail` [긴급] · 닫기 0 | §3 |
| ㉒바 | 같은 폴더를 쓰는 은퇴 좌석 2세대 | 보존 조건 밖 = `session-none` [긴급] 1 · 보존 세대 = `keep-last-2` [긴급] 0 · 닫기 0 | §3 · §8 |
| ㉓ | 명부 나노 · dispatch 0 (정지 중 / 정지 아님) | 판정 줄 있음 · 그 좌석 판정 정확히 1줄 · 닫기 0 | §1 · §7 |
| ㉔ | 짝 표 매핑 카드와 팀 폴더 동명 카드 | 짝 표 매핑 카드가 먼저 | §8 |

## 4. Slack 글 영수(dict-work) 용량 사례 (`test_slack_accept_capacity.py` · r2089)

| 사례 | 입력 | 기대 | 계약 절 |
|---|---|---|---|
| ㉖가 | planner 꼴 dict-work accept 8(`route`·`slack`) → 9번째 Slack 접수 | 접수 전 capacity 0 · remaining 8 → `접수 성공` → capacity 0 · remaining 9 | §6 |
| ㉖나 | issues 꼴 dict-work accept 8(`slack.team` 만) → str-work 접수 1 | capacity 0 · remaining 8 → `접수 성공` → capacity 1 · remaining 9 · complete 손 0 | §6 |
| ㉖다 | dict-work 8 + str-work accept 8 → 다음 str-work 접수 | `용량 부족` · 문구의 남은 일 8(dict 는 안 셈) | §6 |
| ㉖라 | work None 접수 8 → 다음 접수 | `용량 부족`(r2055 §4.1 그대로) | §6 |
| ㉖마 | str-work 8 포화 · thread 에 dict-work 1 · Slack 글 9건 full → str-work 1 complete(여유 1칸) → 답글 settle | 9건 전부 재접수(ts 오래된 순 · dict 재접수는 칸 0) · full 0 · capacity 7 · 같은 settle 다시 = 재접수 0 | §6 |
| ㉖바 | dict-work accept 8 → 알림 1회 → str-work 8 → str-work 1 complete | 첫 호출 알림 0(0/8) · 둘째 꽉 참 1통(8/8) · 셋째 풀림 1통 · 같은 값 다시 = 0통(알림 값 = 투영 `capacity`) | §6 |

| 변이 | 바꾸는 곳 | 잡는 사례 |
|---|---|---|
| M7 | `core/record.py` `capacity` 의 dict 제외를 뺌 | ㉖가 · ㉖나 · ㉖마 |
| M8 | `adapters/slack/reply_done.py` `_requeue` 를 «처음 센 칸 − 성공 수» 로 | ㉖마 |
| M9 | `adapters/pi/full_alert.py` 알림 값을 `remaining` 으로 | ㉖바 |

## 5. 쪽지 받는 곳·도착 확인 사례 (`test_keeper_notify_recipient.py` · r2065 행 E)

가짜 mbox 가 rc·잠든 초·장부에 붙일 줄을 사례가 정한다. 7초 상한은 send 만 0.1초로 자르고 가짜 mbox 가 적재를 먼저 하고 0.3초 자는 대역이다(rc None = 7초 넘김 꼴 · sleep 0).

| 사례 | 입력 | 기대 | 계약 절 |
|---|---|---|---|
| ㉚가 | `_master`·`_desk` 빈칸 · harness `_master` 있음 · [긴급] 3건 | harness 팀장에게 묶음 1통(3건 · 앞 3건) · 둘째 바퀴 0통 · `판정 불가` 0줄 | §4 |
| ㉚나 | `seats-<팀>.json` 없음(v65 아닌 팀) | ㉚가와 같음 | §4 |
| ㉚다 | `_master` 빈칸 · `_desk` 있음 | desk 에게 묶음 1통 · harness 0통 | §4 |
| ㉚라 | `_master` 있음 · send rc 3 | `판정 불가` 1줄 · 실패 지문 · 둘째 바퀴 send 0 · 줄 0 · 날짜 바뀐 바퀴 send 1 | §4 |
| ㉚마 | send 7초 초과(rc None) · 장부에 그 글 없음 | send 1회(재시도 0) · 그 뒤 ㉚라와 같음 | §4 |
| ㉚바 | 받는 곳 세 칸 모두 빈칸 | `판정 불가 … 받는 곳 없음` 1줄 · 둘째 바퀴 0줄 | §4 |
| ㉚사 | `_master` 있음 · [긴급] 6건이 한 바퀴에 | send 3 · `NOTIFY-DEFER` 1줄 · 다음 바퀴 send 3 · 지문 6 | §4 |
| ㉚아 | send rc 0 | `NOTIFIED` 1줄 · 지문 · 둘째 바퀴 0통 · 장부 다시 읽기 0 | §4 |
| ㉚자 | 7초 초과 · 경계보다 큰 seq 로 그 글 있음 | send 1회 · `NOTIFIED … (도착 확인 · rc None)` · 성공 지문 · 같은 글 1통 | §4 |
| ㉚차 | rc 3 · 경계보다 큰 seq 로 그 글 있음 | ㉚자와 같음(rc 3) | §4 |
| ㉚카 | 7초 초과 · 장부 없음(못 읽음) | 실패 지문 · `판정 불가 … 도착 판독 불가` 1줄 · 재시도 0 | §4 |
| ㉚타 | 팀 v65 · `seats-v65.json` 없음 · `seats.json` 에 `_master` / 팀 cfo · `seats-cfo.json` 없음 | v65 = 그 팀장에게 1통(대신 받는 곳 0) · cfo = 명부 없음 → 차례 다음 칸(harness 묶음) | §4 |
| ㉚파 | 같은 초 이전 글(seq 100 · 같은 ts · 같은 본문 첫 줄) · 경계 100 · 새 줄 0 | 도착 아님 · 실패 지문 · `NOTIFIED` 0줄(시각 비교였다면 도착으로 셈) | §4 |
| ㉚하 | ㉚파 장부 그대로 · 경계 100 · 그 사이 seq 101 · 같은 초 · 같은 글 | `NOTIFIED … (도착 확인 · rc None)` · 성공 지문 · 둘째 바퀴 0통 | §4 |
| ㉚거 | 경계 100 · 다른 글 250줄(seq 101~350) · 같은 글 0 | `판정 불가 … 도착 판독 불가` 1줄(«없음» 아님) · 실패 지문 · 재시도 0 | §4 |
| ㉚더 | 같은 날 A 알림 뒤 A 유지 + 새 후보 B(같은 팀 `state.open`) | 그날 2통(A · 다음에 A+B) · B 알림 있음 · 열쇠 = 처음 «안 보낸» 좌석(DA 310738 반례) | §4 |

| 변이 | 바꾸는 곳 | 잡는 사례 |
|---|---|---|
| M17 | `keeper_report.Reporting.cells` 의 `_desk`·harness `_master` 칸을 뺌 | ㉚가 · ㉚나 · ㉚다 |
| M18 | `keeper_report.Reporting.finish` 의 실패 지문 쓰기를 뺌 | ㉚라 · ㉚마 · ㉚바 |
| M19 | `keeper_report.Reporting.budget` 의 한 바퀴 3통 상한을 뺌 | ㉚사 |
| M23 | `keeper_report.Reporting.send` 의 도착 확인을 뺌(7초 초과 = 실패) | ㉚자 · ㉚차 |
| M24 | `launch_roster.roster_path` 의 v65 → `seats.json` 을 뺌 | ㉚타 |
| M25 | `keeper_report.Reporting.send` 를 재시도 1 로 되돌림 | ㉚자 · ㉚마 |
| M32 | seq 경계 대신 시각 비교(`ts` ≥ 지금 초)로 되돌림 | ㉚파 |
| M33 | seq 경계 대신 시각 비교(`ts` > 지금 초)로 되돌림 | ㉚하 |
| M34 | report 의 열쇠를 `fresh[0]` 대신 `seats[0]` 로 | ㉚더 |

## 6. 실사건 기대 (설치 뒤 · 설계 §7 끝 · §12)

- keeper 1바퀴 뒤 «끝난 나노» 0석: 모든 나노 세션이 `WORKING` 이거나 [긴급] 목록에 있다.
- 새로 끝난 나노 1석이 사람 손 없이 `PARKED` 또는 `LANDED` 로 닫힌다.
- 판정 없는 `byz-*` 세션 0 · `UNKNOWN` 은 전부 [긴급] 1줄.
- 이 문서는 실사건 관측 값을 담지 않는다. 관측은 설치 뒤 master 몫이다.

## 7. 열기 실패·열기 멈춤 사례 (`test_launch_failed_end.py` · r2058 · 카드 ft2-launch-failed-end)

계약 L1~L10(`CONTRACT.md` §3 · 설계 `design/DESIGN-p2-launch-failed-no-park-rest-20261116.md`).

| 사례 | 입력 | 기대 | 계약 |
|---|---|---|---|
| ㉘가 | intent failed · 세션 0 · owner 남음 · 착지 0 | park 1 · `UNKNOWN launch-failed` 1줄(intent step·reason 꼬리) · [긴급] 1통 · `PARKED` 줄 0 | L3 |
| ㉘나 | ㉘가 다음 바퀴 | 건너뛰지 않는다(ROUND `unknown=1`) · park 다시 0 · 판정 줄 반복 0 · stall 깨움 0 | L1 · L4 |
| ㉘다 | ㉘가 뒤 카드에 착지 줄 + «남은 범위: 없음» | 다음 바퀴 `COMPLETED` 1 · 닫기 호출 0 · 그 뒤 줄 0 | L2 |
| ㉘라 | r2058 꼴(착지 봄 · «남은 범위» 줄 없음) | 매 바퀴 `UNKNOWN … 남은 범위 줄 없음` · 카드를 고치면 `COMPLETED` | L2 |
| ㉘마 | idle-done 쉼 | 지금처럼 건너뜀 · 줄 0 | L1 |
| ㉘바 | fill 후보 = 착지 카드 1 + 안 한 카드 1 | 안 한 카드만 submit · `NEXT-SKIP` 1줄(값이 바뀔 때만) · 닫기 뒤 pick 도 같음 | L5 |
| ㉘사 | 팀장 좌석(dispatch·intent 0) | 판정 줄 0 · park 0 · [긴급] 0 | L7 |
| ㉘아 | 대기 2장 중 한 장 `- 배정: 대기(사람 · …)` | 그 카드 submit 0 · 다른 카드 submit 1 | L9 |
| ㉘자 | 표식 카드뿐 | `[다음 없음]` 1통 · 막힌 사유별 사람 1 | L9 |
| ㉘차 | 표식 카드 · a1 launch-failed 쉼 · 원장 없음 | a2 dispatch 0 | L9 · L1 |
| ㉘카 | 원장 정지 = 막힘 · 카드 `- 배정: 좌석 …`·`없음` = 안 막음 | 원장 카드 submit 0 · 카드 줄 카드 submit 1 | L9 |
| ㉘타 · ㉘파 · ㉘하 | 원장 없음 · 배정 줄 없음 / `대기(석` / `사람` 표식을 `없음` 으로 고침 | 고름(양성 3칸) | L9 |
| ㉛가 | intent opening 20분 · 세션 0(rc1) · owner 남음 · 잇는 중 아님 | park 1 · `UNKNOWN launch-failed … opening 20분` 1 | L6 |
| ㉛나 | opening 5분 | 손 0(문턱 안쪽) | L6 |
| ㉛다 | opening 20분인데 `fill_open`(잇는 중) | 손 0 | L6 |
| ㉛라 | opening 20분 · tmux 조회 실패(rc2) | park 0 · `판정 불가` 1줄(부재로 읽지 않는다) | L6 |
| ㉘거 | v65 · `seats-v65.json` 없음 ∧ `seats.json` 있음 / 둘 다 없음(`test_pi_launch_roster_r1983.py`) | `seats.json` 에 행 추가 · 둘 다 없음 = «판정 불가 명부 없음» 1구(생성 0) | L10 |

| 변이 | 바꾸는 곳 | 잡는 사례 |
|---|---|---|
| M11 | `keeper.Keeper.team_round` 의 쉼 건너뛰기에서 launch-failed 예외를 뺌 | ㉘나 · ㉘다 · ㉘라 |
| M12 | `keeper_settle.failed_end` 가 UNKNOWN 대신 `PARKED` 낱말을 찍게 | ㉘가 |
| M13 | `keeper_next.choose` 의 착지 카드 제외(`skip_landed`)를 뺌 | ㉘바 |
| M16 | `keeper_settle` 의 opening 멈춤 분기(`stalled`)를 거짓으로 | ㉛가 |
| M30 | `keeper_next.choose` 가 카드 배정 줄(`pre`)을 안 봄 | ㉘아 · ㉘자 · ㉘차 |
| M31 | `keeper_next.prereq` 가 카드 배정 줄 사유 표(`MARK`)를 안 봄(선행만) | ㉘차(그 밖에 ㉘아·㉘자·㉘하도 함께 죽는다) · M67 은 `test_pi_launch_roster_r1983.py`(enroll 명부 경로 하드코딩 되돌림 → ㉘거) |

- 기준판(팩 origin/main c7860542)에서 FAIL 이던 사례 = ㉘가 ㉘나 ㉘다 ㉘라 ㉘바 ㉘아 ㉘자 ㉘차 ㉘하 ㉛가 ㉛나 ㉛다 ㉛라(13) · 지키던 사례 = ㉘마 ㉘사 ㉘카 ㉘타 ㉘파(5).

## 8. 전 세션 정지 재개 전 팀 (`test_penalty_team_no_new_pick.py` · r2073 · 카드 ft2-penalty-team-no-new-pick)

계약 P1~P8(`CONTRACT.md` §10) · 설계 `feature-pack/fable-team/design/DESIGN-pJ-penalty-team-no-new-pick-20261116.md`. 대역 = `keeper_world_r1812` 세계 + 가짜 판정기 `ft-penalty.sh`(rc 를 사례가 정하고 인자·`FT_ROOT` 를 기록) + 가짜 launch·record. 실 판정기·실 `PENALTY_STOP`·runtime 쓰기 0.

| 사례 | 입력 | 기대 | 계약 |
|---|---|---|---|
| ㊲가 | 표식 파일 있음 · 판정기 rc 3 · 빈 나노 칸 · 대기 카드 1 · 두 바퀴 | fill submit 0 · journal 줄 수 그대로 · `NEXT-HOLD <팀> PENALTY_STOP 재개 전 — 다음 카드 0` 1줄 · 둘째 바퀴 0줄 | P1 · P3 · P6 |
| ㊲나 | 표식 있음 · rc 0(재개됨) | fill 1장(submit·assign·deliver·launch·record) · PENALTY 줄 0 | P1 |
| ㊲다 | 표식 파일 없음 | fill 1장 · 판정기 호출 0 | P1 |
| ㊲라 | 표식 있음 · rc 3 · 나노 닫기 1 | 닫기 영수 1(next 없음) · 다음 카드 submit 0 · launch 0 | P3 · P4 |
| ㊲마 | 표식 있음 · rc 3 · `fill_open` 에 잇는 열기 1 | reconcile 그대로(launch 1 · record seat · `NEXT … fill:` 1줄) | P5 |
| ㊲바 | 표식 있음 · rc 3 · gates 거짓(CLOSE-NEXT 표식 없음) · `fill_open` 1 | 복구 launch 0 · 표식 파일 없을 때와 같은 결과 · 판정기 호출 0 | P5 |
| ㊲사 | 판정기 rc 1 / 도구 파일 없음 / 시간 초과 | 셋 다 fill 0 · `판정 불가 <팀> PENALTY_STOP 판독 rc <값> — 다음 카드 0` 1줄 | P1 |
| ㊲아 | rc 3 → 0 → 3 | `NEXT-OPEN` 1줄 + fill 1장 → `NEXT-HOLD` 1줄 다시 | P6 |
| ㊲자 | 1줄 찍은 뒤 keeper 다시 만듦(상태 파일 그대로) | PENALTY 줄 0 · 판정기는 매 바퀴 부른다 | P7 |
| ㊲차 | 두 팀 한 바퀴(rc 0 · rc 3) | rc 0 팀만 fill 1장 · 판정기 호출 팀당 바퀴 1회 | P2 |
| ㊲카 | 팀 PAUSED · 표식 있음 | 판정기 호출 0 · PENALTY 줄 0 | P3 |

| 변이 | 바꾸는 곳 | 잡는 사례 |
|---|---|---|
| M62 | `keeper_next.fill()` 의 pick 줄에서 `and penalty_open(k, team)` 를 뺌 | ㊲가 |
| M63 | `keeper_next.close()` 의 pick 줄에서 `and penalty_open(k, team)` 를 뺌 | ㊲라 |
| M64 | `penalty_open` 이 rc 0 이 아닌 값을 전부 «열림» 으로 봄 | ㊲사 |
| M65 | `reconcile` 의 복구 launch 가드에 `and penalty_open(k, team)` 를 더함 | ㊲바 |
| M66 | `penalty_seen` 이 상태 파일 대신 메모리 사전만 씀 | ㊲가(둘째 바퀴) · ㊲자 |

- 기준판(팩 origin/main cd0bd9ee)에서 FAIL 이던 사례 = ㊲가 ㊲라 ㊲사 ㊲아 ㊲자 ㊲차(6) · 지키던 사례 = ㊲나 ㊲다 ㊲마 ㊲바 ㊲카(5).

## 9. 선행불명 로그·쪽지 (`test_prereq_unreadable_once.py` · 카드 ft2-prereq-unreadable-once)

계약 I1~I9(`CONTRACT.md` §12) · 설계 `feature-pack/fable-team/design/DESIGN-pI-prereq-unreadable-log-once-20261116.md`.
대역 = `keeper_world_r1812` 세계(r1871 시험의 세계 그대로) + 주입 시계 · 사례가 `w.t` 를 밀어 날짜 넘김을 만든다 · sleep 0 · 실 우편함·runtime 쓰기 0.
바퀴마다 keeper 를 새로 만든다(rnd) = 실제처럼 프로세스가 바뀐다 → 세 기억이 상태 파일에 있어야만 통과한다(I9).

| 사례 | 입력 | 기대 | 계약 |
|---|---|---|---|
| ㉟가 | 선행이 글뿐인 카드 1장 · 두 바퀴 | `판정 불가 … 선행 줄 판독 불가(번호 참조 없음) — 건너뜀 · 고칠 꼴 …` 1줄 · 둘째 바퀴 0줄 · 두 바퀴 모두 그 카드 submit 0 | I1 · I2 |
| ㉟나 | ㉟가 뒤 선행 글을 다른 글로 바꿈 | 1줄 다시(= 값이 바뀜) | I1 |
| ㉟다 | 선행 `결정 원문 r5 PR 8503 착지` · 루트에 r5 없음 | 1줄 · 까닭 `루트에 없는 번호 r5` | I2 |
| ㉟라 | ㉟가 뒤 keeper 다시 만듦(상태 파일 그대로) 한 바퀴 | 0줄 · 쪽지 0 | I1 · I9 |
| ㉟마 | ㉟가 뒤 선행을 `없음` 으로 고침 → 고름 → 다시 글로 바꿈 | 고친 바퀴 0줄 · submit 1 · 다시 바꾼 바퀴 1줄 | I4 |
| ㉟바 | 선행불명 2장 + 고를 카드 1장 | `[다음 막힘]` 1통(2장 · 이름 2개) · 고를 카드 submit 1 · 둘째 바퀴 쪽지 0 | I5 |
| ㉟사 | ㉟바 뒤 선행불명 카드 1장이 더 생김 | `[다음 막힘]` 1통 다시(3장) | I5 · I6 |
| ㉟아 | 선행불명 5장 | 쪽지 이름 3개 · 수 5 · 로그 5줄 | I5 |
| ㉟자 | 선행 `r9100` 이 대기에 있음 / 완성에 있음 | 앞 = 판정 `선행`(막힘 · 줄 0 · 쪽지 0) · 뒤 = 열림(submit 1) | I3 |
| ㉟차 | 같은 날 X 쪽지 성공 → `없음` 으로 고침(빈 묶음) → 같은 글로 되돌림(X) | `[다음 막힘]` 2통 · 로그 2줄 | I7 · I8 |
| ㉟카 | 같은 날 X 쪽지 성공 → 카드 1장 더 생겨 Y 성공 → 그 카드를 고쳐 다시 X | `[다음 막힘]` 3통 | I7 · I8 |
| ㉟타 | 선행 `r9100 r9101` · 둘 다 없음 → 다음 바퀴에 r9100 이 완성에 생김(선행 글 그대로) | 첫 1줄 까닭 `루트에 없는 번호 r9100 r9101` · 다음 1줄 까닭 `루트에 없는 번호 r9101` · 쪽지 2통 · submit 0 | I1 · I2 · I6 |
| ㉟파 | X 성공 → Y 가 됨 · send rc 3 → 같은 날 다시 → 날짜 바뀐 바퀴 → 성공 → 같은 날 다시 / 같은 꼴에서 넘김(defer) | 실패한 날 send 1회뿐 · 날짜가 바뀌면 1 · 성공한 뒤 0 · 넘김이면 다음 바퀴 1 | I8 |
| ㉟하 | X 성공 → Y send 실패 → 카드를 고쳐 다시 X | 쪽지 0(팀장이 아는 묶음) · 로그는 바뀐 카드만 1줄 | I8 |
| ㉟거 | 인수 칸(DA BYZ 310229) = 상태 저장 뒤 keeper 다시 만듦 → 변화 없음 발신 0 → 그 뒤 X 재발 | 0통 · 0줄 → X 재발 1통 | I9 |

| 변이 | 바꾸는 곳 | 잡는 사례 |
|---|---|---|
| M39 | `keeper_next.choose` 의 선행불명 로그 기억을 상태 파일 대신 바퀴 캐시(`once`)로 | ㉟가 · ㉟라 |
| M40 | `keeper_next.prereq_tell` 의 기억 치우기(`prereq_seen` pop)를 뺌 | ㉟마 |
| M41 | `[다음 막힘]` 을 고를 카드 0 일 때만 보냄 | ㉟바 |
| M56 | `prereq_told` 를 전송 결과와 상관없이 바꿈 | ㉟파 |
| M57 | 열쇠에서 전이 번호를 뺌(묶음 지문만) | ㉟차 · ㉟카 |
| M58 | 로그 기억에서 까닭을 뺌(선행 값만 비교) | ㉟타 |

- 기준판(팩 origin/main 2b5037d1)에서 FAIL 이던 사례 = ㉟가 ㉟나 ㉟다 ㉟라 ㉟마 ㉟바 ㉟사 ㉟아 ㉟차 ㉟카 ㉟타 ㉟파 ㉟하 ㉟거(14) · 지키던 사례 = ㉟자(1 · 판정 그대로).

## 10. 착지한 좌석의 짧은 문턱 · 빼는 미읽음 사례 (`test_done_seat_short_idle.py` · 카드 ft2-done-seat-short-idle)

계약 A1~A9(`CONTRACT.md` §2) · 설계 `design/DESIGN-pA-done-idle-threshold-20261116.md` r4(DA 대행 APPROVE · BYZ 310212) · DA HOLD-IMPL 반례 1(311515) 반영.
파일 셋 = 사례 `test_done_seat_short_idle.py`(27) · 변이 `test_done_seat_short_idle_mutants.py`(M20~M45) · `test_done_seat_short_idle_mutants_b.py`(M51~M55) — 파일마다 70초 안.
가짜 mbox = 머리줄 + `--rows` JSON 줄(사례가 정함) · 실 tmux·실 우편함·sleep 0 · 사례 1개 70초 안.

| 사례 | 입력 | 기대 | 계약 |
|---|---|---|---|
| ㉙가 | 착지 참 · 마지막 줄 stop · 무활동 6분 · CPU idle 2회 · 쪽지 0 | `COMPLETED` 1 · 닫기 1(complete 1) | A1·A2 |
| ㉙나 | 착지 참 · 마지막 줄 toolUse · 6분 | `WORKING landed-wait` · 닫기 0(턴이 안 닫혔으면 일하는 중) | A1 |
| ㉙도 | 착지 참 · toolUse · 무활동 16분(질문 창 15분 지남) · CPU idle 2회 · 미읽음 0 | `WORKING landed-wait` · 닫기·complete·[긴급] 0 (질문 창 판정은 park 길만 — DA 반례 311515 R1) | A1 |
| ㉙다 | 착지 참 · stop · 4분(문턱 안) | `WORKING landed-wait` · 닫기 0 | A1 |
| ㉙라 | 착지 참 · stop · 6분 · CPU busy | `WORKING cpu-busy` · 닫기 0 | A1 |
| ㉙마 | 착지 0 · stop · 61분 · 미읽음 `[마감 #N] 할 일 0`(75분 · 보낸 이 `_master`) | `PARKED idle-done` · 꼬리 `미읽음 마감 1통 제외(seq …)` · 닫기 1 · 큐 그대로(mark·recv 0) | A6·A8 |
| ㉙바 | 착지 0 · stop · 6분 | `WORKING` · 닫기 0 · park 0(짧은 문턱은 착지 좌석만) | A3 |
| ㉙사 | 착지 0 · stop · 61분 | `PARKED idle-done`(지금 그대로) | A3 |
| ㉙아 | 착지 참 · 셸만 남은 pane · 6분 | `COMPLETED` 1 · 닫기 1(셸은 CPU 무관 · 문턱만 300초) | A1 |
| ㉙자 | 미읽음 `[긴급] …`(75분) | `UNKNOWN mail-pending` · 닫기 0 | A6 |
| ㉙차 | 미읽음 `[발주 #N] …`(75분) | `UNKNOWN mail-pending` | A6 |
| ㉙카 | 미읽음 1통 2줄(첫 줄 닫힌 꼴 + 둘째 줄 `[발주]`) | `UNKNOWN mail-pending`(줄 전체가 맞아야 한다) | A6① |
| ㉙타 | 닫힌 꼴 10분 전(문턱 60분 안쪽) | `UNKNOWN mail-pending` | A6③ |
| ㉙파 | 미읽음 2통 = 닫힌 꼴 + `[발주]` | `UNKNOWN mail-pending`(한 통이라도 막으면 막는다) | A7 |
| ㉙하 | 머리 없는 글(75분) | `UNKNOWN mail-pending` | A6① |
| ㉙거 | peek rc ≠ 0 | `UNKNOWN mail-unknown`(지금과 같음) | A5 |
| ㉙너 | 착지 참 · 6분 · `[마감] 할 일 0 · 착지 4ccf2a6` + `골좌표:` 줄(7분) | `CLOSED-SESSION` 1 · 꼬리 `미읽음 마감 1통 제외` · 닫기 1 · 큐 그대로 | A6·A8 |
| ㉙더 | 착지 참 · 6분 · 닫힌 꼴 2분 전 | 닫기 0(문턱 안 쪽지) | A6③ |
| ㉙러 | 미읽음 1통 4줄(첫 줄 닫힌 꼴 · 4번째 줄 `[긴급][발주]`) | `UNKNOWN mail-pending` · 닫기 0 · 쉼 0 | A6① |
| ㉙머 | DA 입력 2개(자유 글 답장 · «할 일 0» 이 들어 있어도 줄 전체가 안 맞음) | 둘 다 `UNKNOWN mail-pending` | A6① |
| ㉙버 | 현역 seat#1 · 큐에 to = seat#0(옛 이름) `[발주]` 1통 + 자기 몫 닫힌 꼴 1통 | peek pending 2 = 판독 2통 · `UNKNOWN mail-pending`(옛 이름 쪽지도 읽는다) | A4 |
| ㉙서 | 줄 수 ≠ pending(2 vs 1) / 옛 mbox(줄 0 · pending 1) | `mail-unknown` / `mail-pending`(지금과 같음) | A5 |
| ㉙어 · ㉙저 | 자유 글 답장(`[답 #N] 확인했습니다.` / `[답 #N] 할 일 0 은 아니고 …`) | 둘 다 `UNKNOWN mail-pending` | A6① |
| ㉙고 | 닫힌 꼴의 보낸 이가 다른 나노 / 명부 못 읽음 | 둘 다 `UNKNOWN mail-pending` | A6② |
| ㉙허 | `[마감 #N] 할 일 0이 아닙니다`(줄 전체가 안 맞음) | `UNKNOWN mail-pending` | A6① |
| ㉙노 | r2057 실사건 원문(자유 글 답장 · 옛 착지 줄) | `UNKNOWN mail-pending`(치르는 값으로 고정 — 빠지지 않는다) | A6① |

| 변이 | 바꾸는 곳 | 잡는 사례 |
|---|---|---|
| M20 | `keeper_close.land_ready` 가 `DONE_IDLE` 을 안 넘김 | ㉙가 · ㉙아 |
| M21 | 짧은 문턱에서 stop 검사를 뺌 | ㉙나 |
| M22 | park 길에도 `DONE_IDLE` 을 씀 | ㉙바 |
| M44 | 미읽음 행을 `to` 글자 일치로 거름 | ㉙버 |
| M45 | 줄 수 ↔ pending 대조를 뺌 | ㉙서 |
| M51 | 조건 ① 을 «줄 전체 일치» 대신 «`할 일 0` 이 들어 있음» 으로 | ㉙머 · ㉙허 |
| M52 | 조건 ① 을 «첫 줄만 봄» 으로 | ㉙러 · ㉙카 |
| M53 | 조건 ②(보낸 이 = 역할 칸 좌석)를 뺌 | ㉙고 |
| M54 | 조건 ③(나이)을 뺌 | ㉙타 · ㉙더 |
| M55 | 미읽음 판독을 지금(1통이라도 막음)으로 되돌림 | ㉙마 · ㉙너 |

- 기준판(팩 origin/main cd0bd9ee)에서 FAIL 이던 사례 = ㉙가 ㉙마 ㉙아 ㉙너 ㉙서(5 · ㉙서는 첫 갈래만) · 지키던 사례 = 나머지 21. ㉙도 = 1차 구현(head e3e91f00)에서 FAIL 이던 사례(UNKNOWN waiting-input + [긴급] · 기대 WORKING landed-wait) · 보정 뒤 rc0.
- `peek --rows` 사례 = 1.x `tests/scripts/test_mbox_peek_self_sent_r1153.py` r4(줄 수 = pending · 계보 옛 이름 앞 쪽지 포함 · from == me 셈 밖 · `--rows` 없으면 출력 바이트 같음).
