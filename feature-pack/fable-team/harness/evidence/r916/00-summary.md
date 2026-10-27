# r916 (재설계 r2) — ft-inbox `close` 한 줄 · 증거

카드: `design/harness/indices/진행/r916-decision-count-ref-read-and-inbox-close-one-line.md` §재설계 r2
범위(동결): `close <seq|group…> "<사유>" [--seat <좌석>]` = **한 잠금 안에서** mark(처리·사유) + reported · 줄마다 CLOSED/NOTFOUND · 하나라도 NOTFOUND 면 rc≠0. 그 밖(결정 셈 ref 읽기 · 질문 표식 · 뉴스·매거진 · 원장 정본 단일화)은 범위 밖.
브랜치: `nano/r916-decision-count-ref-read-and-inbox-c-r2` (base `origin/main` `44aa6978`) · push 는 master.

## 바뀐 파일 (3)
| 파일 | 무엇 |
|---|---|
| `harness/bin/ft-inbox.py` (+ `kit/fable-team/bin` 짝, cmp0) | `cmd_close` 신설 · `main` 분기 · docstring/usage 1줄에 close · `sys.exit(main(...))` 로 rc 전달 |
| `harness/tests/test_inbox.sh` | 기존 파일에 «9e) close» 칸 1개(ⓐⓑⓒ + 묶음 + 남의 큐) — 새 시험 파일 0 |
| `harness/evidence/r916/` | 이 폴더 |

`ft-inbox.sh` 는 3줄 exec 래퍼라 본문 변경 0 — usage 1줄은 `ft-inbox.py` 의 die 문구(196행)와 docstring(4행)에 있다.

## ★주의 — 200줄 한도 때문에 «이어붙임» 만 했다 (동작 무변경)
`tests/test_inbox_waive.sh:117` 이 `ft-inbox.py` ≤ 200줄을 강제하고(현재 200), 카드가 «새 파일 0 · 기존 시험 그대로» 라서 close(15줄)를 넣으려면 같은 파일에서 줄을 비워야 했다.
비운 방법은 **연속 줄 이어붙이기·지역 변수 한 줄화·`with locked(q := …)`** 뿐이다(로직·출력·순서 변경 0). `git diff` 로 확인 가능: 삭제된 줄은 전부 «원래 한 문장이 두 줄로 접혀 있던 것».
`cmd_waive` 의 두 `print` 는 `print(a, b, sep="\n")` 로 합쳤다(출력 바이트 동일 — `test_inbox_waive.sh` ⓕ 골든이 통과).

## 시험 (명령·결과)
| 축 | 명령 | 결과 |
|---|---|---|
| 초록 | `bash harness/tests/test_inbox.sh` | `RESULT fail=0` · PASS 95 · rc=0 (`green.txt`) |
| 빨강(base) | 위 시험 × base `44aa6978` 판 | `RESULT fail=11` · rc=1 (`red-base.txt`) — close 셀만 빨강 |
| 변이 3 | `bash harness/evidence/r916/mutation.sh` | 3/3 DETECTED (`mutation.txt`) — 검출식 = «FAIL 줄 ∧ rc≠0» |
| 정적 | `ruff check` · 200줄 · kit 짝 cmp0 · `bash -n` | 전부 통과 (`lint.txt`) |
| 회귀 | inbox 계열 11종 + report_hooks · r928 · board_publish · sheet/mirror 3종 · live_install | 전부 rc0 |
| 실 한 줄 | `close-line.txt` — 임시 FT_ROOT 에서 3줄 → close 2줄 → 1줄 → 0줄 | `CLOSED 901 seq=901` / `NOTFOUND 999` rc=1 / 사유 빈 값 rc=2 |

변이 3종 = ⓐ `reported` 생략(→ ⓐ 5줄 빨강) · ⓑ `return 0`(→ ⓑ 3줄 빨강) · ⓒ usage 검사 삭제(→ ⓒ 3줄 빨강).
ⓒ·「남의 큐」 셀은 `usage: close`·`NOTFOUND 821` **문구**까지 본다 — base 에서도 rc 만 2/1 이라 초록이던 구멍을 막았다(DA⑥ r1 반례 4 «초록도 합격»).

## 반례 집합(동결) 대응
| 반례 | 처리 | 시험 |
|---|---|---|
| R1 `close` 가 mark 만 찍고 reported 를 안 찍음(표시 ≠ 닫힘 · r593) | 같은 `with locked` 안에서 `x.update(mark=m, reported=True)` 한 번 | ⓐ · 변이 `reported-생략` |
| R2 없는 seq → NOTFOUND rc≠0 (조용한 성공 0) | 없는 대상은 `NOTFOUND <t>` 출력 + `return 1`, 나머지는 닫음 | ⓑ · 변이 `NOTFOUND-rc0` |
| R3 잠금 밖 두 단계 → 중간 끊김에 반만 닫힘 | 대상 조회(`mine`)부터 `write_q` 까지 **잠금 1개** — `hits()` 를 밖에서 부르면 그 사이 archive 가 줄을 옮겨 rc0·출력 0(DA⑥ r1 반례 2) | close 본문 · 변이 `usage-검사-삭제` 가 rc 경로를 건드림 |

## 범위 밖에서 본 것 (고치지 않음 · 언급만)
`bash harness/tests/test_question_board.sh` → `FAIL 줄 수 ≤ 200: byz_mbox_slack_mirror.py 204` — base `44aa6978` 에서도 같은 빨강(내 변경과 무관).

## press
없음 — 단위·대조 시험만. 이 카드는 press 가 필요 없다(라이브 오디오 축 0).
