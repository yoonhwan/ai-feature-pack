# r960 증거 — pi 나노 닫기 두 길(카드가 가지에만 · pi 재개 기록)

카드: `design/harness/indices/진행/r960-pi-nano-close-two-paths.md` · Issue #3656 · base origin/main `b79c4654`(spawn) · 실제 착수 판 `a1fccaf7`
짝 카드: r958(같은 `ft-nano-close.sh` 를 고친다 — 착지 순서 = r842 → r958 → r960 rebase · arch #170216)

## 무엇이 막혔나 (실측 2건)
| 길 | 지금 판 | 원인 |
|---|---|---|
| ⓐ `ft-nano-close --suspended` | `⑥카드 못 찾음` REJECT | 카드 후보가 WT·ROOT·LEDGER_WT·형제 폴더뿐 — 카드가 아직 origin/main 에 없고 좌석 가지에만 있으면 못 찾는다 |
| ⓒⓓ `ft-seat-close --verdict` | `HELD 재개 기록 실패 · kill 0 · rc3` | 재개 기록 근거가 claude 쪽(argv `--model` · `~/.claude/history.jsonl` · claude jsonl)뿐 — pi 좌석은 `NORECORD` → 살아 있는 좌석은 HELD |

## 고친 것 (파일 3 + 시험 2)
| 축 | 값 | 파일 |
|---|---|---|
| ⓐ 가지 카드 | 후보가 다 빈 뒤 좌석 워크트리(그 가지 체크아웃)의 `indices/{진행,완성,대기}/<파일>` 을 본다(읽기·쓰기) · 워크트리에 없으면 가지 tip 의 ref 판을 임시 파일로 꺼내 **읽기 전용** `CARD_READ`. 정보 1줄 = `INFO 카드 위치 ← <가지>:<경로>` | `ft-nano-close.sh`(카드 찾기 블록 1 + trap 2) |
| ⓑ 조용한 통과 0 | 가지에도 origin/main 에도 없으면 지금 그대로 `⑥카드 못 찾음` REJECT(명부·카드·세션 불변) | 같음 |
| ⓒ pi 재개 기록 | `agent=pi` 면 결속 근거 = 그 pane cwd 의 pi 세션 파일(`~/.pi/agent/sessions/<폴더>/*.jsonl` 중 첫 줄 `cwd` 가 pane cwd 와 같고 `timestamp` ≥ 좌석 프로세스 시작(ps lstart) 인 «가장 최근 1개»). 폴더 이름 인코딩은 추측하지 않는다(파일 첫 줄 cwd 로 고른다) → `RESUME ok`(record `engine=pi` · `jsonl`=세션 파일) | `ft-seat-retire.sh`(find_resume/record 에 agent 칸 1줄) · `ft_roster_lib.py`(`pi_seat_resume`) |
| ⓓ pi NORECORD 수용 | 세션 파일이 없으면 `NORECORD <좌석> pi 세션 없음 — 산출 커밋 보존 …` — 이 글자일 때만 살아 있는 pi 좌석도 닫기 진행(산출 커밋은 브랜치 보존). **claude 좌석 NORECORD 는 지금처럼 HELD rc 3** | `ft-seat-close.sh`(case 1줄) |
| 줄 수 상한 | `ft-seat-retire.sh` 200줄 · `ft-seat-close.sh` 120줄 그대로(pi 갈래 본문은 `ft_roster_lib.py` 로 — retire 안에 넣으면 상한 초과) | — |
| 짝 사본 | `kit/fable-team/bin/{ft-nano-close,ft-seat-close,ft-seat-retire}.sh` · `ft_roster_lib.py` cmp0 | — |

## 시험 (신규 2 · ⓐ~ⓕ)
| 축 | 값 | 파일 |
|---|---|---|
| ⓐ | 카드가 나노 가지에만 → `--suspended` 닫기 rc 0 · 카드 원문 경로 `nano/bc:design/…/진행/bc.md` 1줄 · 카드 «중단:» 줄 = 가지 체크아웃 사본 | `tests/test_nano_close_card_branch_r960.sh` |
| ⓐ2 | 같은 상태에서 `--superseded-by` → 가지 카드로 대체됨 대조 → rc 0 | 같음 |
| ⓑ | 카드가 가지에도 없음 → `REJECT … 카드 못 찾음` rc 1 · kill·태그 0 · 명부 그대로 · 원장 0 | 같음 |
| ⓒ | pi 좌석 살아 있음 + 세션 파일 1 → `RESUME ok` · 기록 `engine=pi`·`jsonl=<세션 파일>`·`cwd=pane cwd` · `CLOSED-ROLE … record=<경로>` rc 0 · 명부 stop-ready | `tests/test_seat_close_pi_resume_r960.sh` |
| ⓒ2 | 세션 파일 timestamp 가 좌석 시작 «전» → 이 좌석 세션 아님(NORECORD · 기록 파일 0) | 같음 |
| ⓓ | pi 세션 파일 0 → `record=NORECORD` 인데 rc 0 으로 닫힘 / claude 같은 상황 → `HELD` rc 3 · 명부 안 닫힘 · kill 0 | 같음 |
| ⓔ | 기존 시험 회귀 = `test-green.txt`(10종 rc 0 · PASS 합계 861) | `test-green.txt` |
| ⓕ | 변이 3종(가지 카드 끔 → ⓐ FAIL · pi 갈래 끔 → ⓒ rc 3 · claude NORECORD 수용으로 넓힘 → ⓓ claude 칸 rc 0) | `mutation.txt` |
| ⓖ | 키트 짝 cmp0 · `bash -n` · 600/300초·외부 호출·`GIT_DIR` 0 | 두 시험에 포함 |

## 착수 전부터 빨간 시험 2종 (내 변경 탓 아님 — 같은 수로 실패)
| 시험 | HEAD(a1fccaf7) | 고친 판 |
|---|---|---|
| `test_nano_close_superseded_by.sh` | 139 PASS · 2 FAIL | 139 PASS · 2 FAIL(같음) |
| `test_nano_close_cwd_holders_skip_self_r680.sh` | 5 PASS · 5 FAIL | 같음 |

사유는 둘 다 시험 대역 누락이다 — r680 은 `$T/bin` 에 `ft-team-lib.sh`·`ft_teamset.py` 를 복사하지 않아 `계획 생성 실패`, superseded 는 `--cherry-override` 원장 사유 줄 미기록. 고치려면 그 시험 대역을 손대야 해서 이 카드 범위 밖으로 둔다(원문 = `pre-existing-fail.txt`).

## press 필요
없음(단위·캡처·기존 시험만 — 나노는 press 를 쏘지 않는다). 실사건(실제 pi 나노 1석을 이 두 길로 닫기)은 master+DA 소관.

## r2 (DA⑥ r1 HOLD 2 반송 고침 · 반송서 = `design/harness/evidence/r960-da6/REWORK-r960-r2.md` 58cff41f85)
| 반례 | 자리 | 고친 것 | 시험 칸 |
|---|---|---|---|
| ① 계약 ② — pi 세션 없음이 «조용한 통과» | `bin/ft-seat-close.sh:34`(수용)·`:119`(출력) | 수용한 `NORECORD` 원문 줄(좌석·사유)을 `CLOSED-ROLE` 줄 **다음 줄**에 그대로 출력(`NOLINE`). 첫 줄은 지금처럼 `CLOSED-ROLE`(다른 좌석·시험이 `head -1` 로 읽는다) · 줄 수 120 그대로 | ⓡ (세션 파일 0 → `NORECORD pi#7 pi 세션 없음 — 산출 커밋 보존…` 1줄 + 좌석·사유) |
| ② 계약 ② — 세션 파일이 있는데 `model 못 읽음` | `bin/ft_roster_lib.py` `_pi_model` 신규 · `pi_seat_resume` 의 model 줄 | model 은 세션 파일 **전체**에서 마지막 `model_change.modelId`(pi 머리 줄에는 modelId 가 없다 — 실측 `~/.pi/agent/sessions/*/*.jsonl` 첫 줄 = `type=session` 만) → 없으면 머리 `modelId` | ⓢ (머리 `session` + 뒤 줄 `model_change` → `RESUME ok` · `model=opengateway/deepseek/last-model`) |

- 빨강 먼저: 고치기 전 판(HEAD 350cd4b6)으로 같은 시험 → ⓡ 3 · ⓢ 3 FAIL(`red-first-r2.txt`) · 고친 판 = ALL PASS
- 변이 2종 추가: «수용 뒤 출력 생략» → ⓡ FAIL · `_pi_model` 을 «첫 줄만» 로 되돌림 → ⓢ FAIL(`mutation.txt` · 시험 안에서 사본에 글자만 바꿔 재실행)
- 시험: `test_seat_close_pi_resume_r960.sh` 25 → 37 PASS · 기존 회귀 = `test-green.txt`(16종 · 1042 PASS · 2 FAIL = 착수 전부터 빨간 2종 그대로)
- kit 짝 cmp0 = `{ft-seat-close.sh,ft_roster_lib.py}` (줄 수 상한: close 120 ≤ 120 · retire 200 그대로)

## r3 (DA⑥ r2 HOLD 1 반송 · 같은 축 2회째 = 재설계 · 반송서 = `design/harness/evidence/r960-da6/REWORK-r960-r3.md`)
**원인(축)**: 닫기 결과 줄을 «갈래마다 따로» 찍었다 — r1 은 살아 있는 갈래, r2 는 죽은 좌석 갈래가 같은 `NORECORD` 줄을 빠뜨렸다. 갈래가 늘면 또 빠뜨린다.

| 재설계 | 값 | 시험 칸 |
|---|---|---|
| 출력 함수 하나 | `ft-seat-close.sh` `finish()` — 모든 종료 갈래(`CLOSED-ROLE` · `CLOSED-DEAD` · `CLOSED-SESSION` · `HELD` · `FAIL`)가 이 함수로만 끝난다. 결과 줄들 다음에 ① `NORECORD <좌석> <사유>` 원문 1줄(어느 갈래든 — `NOLINE` 은 retire 출력에서 case **앞**에 잡는다) ② 원문을 못 잡았으면 `pi 세션 없음 — 산출 커밋 보존` 안전망 문구 ③ 기록 성공인데 경로가 결과 줄에 없으면 `RESUME ok <경로>` 1줄 | ⓣ ⓤ |
| 죽은 좌석 갈래(DA r2 반례) | `CLOSED-DEAD <좌석> record=NORECORD handoff=-` + `NORECORD pi#dead pi 세션 없음 — 산출 커밋 보존 …` 2줄 · 첫 줄 형식은 r427 그대로(기존 시험 `ⓐⓑⓒ` 불변) | ⓣ |
| 갈래 묶음 | 살아 있음/죽음 × 세션 파일 있음/없음 + HELD → 각각 «재개 기록 경로» 또는 «`NORECORD` 줄» (죽은 좌석 + 세션 파일 = `RESUME ok <경로>` 줄, HELD = `HELD …` + `NORECORD …` 2줄) | ⓤ |
| 안전망(문자열) | `finish()` 밖 `exit 0` = 0 · `finish()` 밖 결과 줄 직접 `echo "CLOSED|HELD|FAIL…"` = 0 · `finish` 호출 갈래 ≥ 5 — 갈래가 늘어도 이 칸이 잡는다 | ⓤ |
| 줄 수 | `ft-seat-close.sh` 118줄(상한 120) · `ft-seat-retire.sh` 200 · `ft_roster_lib.py` 112 | ⓖ |

- 빨강 먼저: 고치기 전 판(HEAD 5fc418c8 = r2)으로 같은 시험 → ⓣ2 · ⓤ3 · 안전망 3 · 변이표지 2 = 11 FAIL(`red-first-r3.txt`) · 고친 판 = ALL PASS
- 변이 3종: «죽은 갈래 exit 를 함수 앞에» → ⓣ FAIL · «finish 의 NORECORD 줄 생략» → ⓡ FAIL · «첫 줄 modelId 만» → ⓢ FAIL
- 기존 시험 불변: `test_seat_close.sh` 81 PASS · `test_seat_resume_binding.sh` 92 PASS · `test_seat_retire*` 전부 0 FAIL
- 덤(DA r3 요청 1줄): 격리에서 보인 `test_seat_close` 3F · `test_seat_retire_defer_press_r690` 1F 는 여기서 **base 331eb013 도 0F · 이 세트도 0F**(r690 은 부하에서 1회 흔들림 = 시험 대역 잡음 · 같은 건수 아님)
