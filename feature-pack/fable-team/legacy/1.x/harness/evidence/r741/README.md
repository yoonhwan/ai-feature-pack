# R741 증거 — r725 문서 전용 승인 면제를 팀 폴더 «하위 폴더» 로 확대 (r3 = 오빠 결정 선택지 1 「하위 폴더는 새 파일 추가(A) 만」)

카드: `design/harness/indices/진행/r741-doc-exempt-team-subfolders.md` · 좌석 `byz-harness-nano-r741-doc-exempt-team-subfolders#0`
브랜치 `nano/r741-doc-exempt-team-subfolders` (base = 팩 origin/main `e0d2b265`) · push 는 master.

## 무엇이 바뀌었나 (범위 1줄)
- 옛 판 = `design/teams/<팀>/` **직속** `.md` 만 면제 → `if "/" in name: return "", "팀 하위 폴더"` 1줄이 하위 폴더를 전부 거절(8장 중 2장만 통과).
- 새 판 = 팀 폴더 **아래 어느 깊이** 의 `.md` 도 면제. 단 `indices`(카드 폴더) · `inbox`(역할 좌석의 일) · `keys`(키 원장) = **도구가 판정 입력으로 읽는 폴더** 는 제외 — 문서 PR 로 바꾸면 `ft-index-move` · `ft-role-spawn` · `key_change_ledger` 게이트를 건너뛰는 길이 된다(카드 ⓒ).
- 점으로 시작하는 조각(`.omc` 등 숨김) · 빈 조각 · `.` · `..` = 경로 모양 우회로 거절.
- 이름 거절 목록(CANON) = **모든 깊이** 의 **파일 이름** 에 **대소문자 무시** · `"LEDGER"` 접두 추가.

## r3 (오빠 결정 선택지 1 · PACKET-r741-after-2hold.md · arch 124 f283edcce0)
| 처방 | 구현 | 시험 |
|---|---|---|
| ① 하위 폴더 = 추가(A)만 | `team_of(path, status)` — 하위 폴더에서 M/D/R 거절 · 직속은 A·M 그대로 | ⓗ① 수정 rc1 · ⓗ② 삭제 rc1 · ⓗ③ 이름바꾸기 rc1 · ⓗ④ 새 파일 rc0 · ⓗ⑤ 직속 회귀 0 · ⓗ⑥ 변이 |
| ② 가드 폴더 경로 오타 | `KHOOK=harness/kit/hooks` · `SLACK=harness/kit/slack-mirror` (옛 판 = fable-team 아래 없는 경로) | ⓘ①b 실재 · ⓘ⑦·⑦b 가짜 폴더 변이 · ⓘ⑧ 16개 이름 실측 |
| ③ 반례 시험 | 위 항목들 | 127 PASS · 10 PASS ALL PASS |

## r2 (DA⑥ r1 HOLD 처방 1~6 · arch 124 판정문 §198 · 커밋 5c5450b439)
| 처방 | 구현 | 시험 |
|---|---|---|
| 1 비교 키 NFKC+casefold | `key()` 하나로 폴더·이름·CANON 접두 전부 비교 + 조각이 NFKC 로 바뀌면(ſ·ﬁ·전각) 그 자체로 거절 | ⓕ 긴 s ſ 폴더·파일 · ﬁ · NFC 아님 / ⓙ②f 변이 → rc0 |
| 2 `baselines/` 제외 | `EXCLUDE_DIRS = (indices, inbox, keys, baselines)` | ⓓ2 `baselines/FLAGS.md` · `Baselines/` (대소문자) / ⓙ②g 변이 → rc0 |
| 3 판정 입력 이름 목록 | `EXCLUDE_NAMES` = 키트 5폴더의 `.md` 토큰 101개(key 값) · 허용 목록 0 · 재생성 = `--emit` | ⓔ·ⓓ2 `BTS.md`(깊이 2) · `bts.MD` · `readme.md` / ⓙ②h 변이 → rc0 |
| 4 가드 시험 재작성 | 다섯 폴더(kit bin · kit/hooks · templates/hooks · slack-mirror · harness/bin) 훑기 + **변수 조립 경로**(`$V65/baselines/FLAGS.md`) 탐지 · `--emit` 재생성 경로 확인 | ⓘ①~⑥ (변이 2 = FLAGS.md 제거 → FAIL · baselines 제거 → FAIL) |
| 5 반례 경로 시험 | 위 항목들 | 121 PASS · ALL PASS |
| 6 범위 밖 지킴 | ft-merge-land · ft-merge-lib · 가드 훅 변경 0 | 직속 판정 회귀 0 (r725 원 항목 전부 PASS) |

## 파일
- `kit/fable-team/bin/ft_doc_exempt_paths.py` (**신규 125줄**) = 제외 폴더 목록·경로 조각 검사·CANON 한 곳. `harness/bin/` 짝 사본 cmp0.
- `kit/fable-team/bin/ft_doc_exempt.py` — 311 → **286줄**(BYZ 200 상한 초과 상태를 늘리지 않음 · 카드 §구현 범위 0). `team_of` 는 새 모듈 호출 1줄(`paths.team_of`), 머리말 ③ 범위 문구 갱신.
- `harness/tests/test_doc_exempt_r725.sh` — 확장(ⓑ 하위 폴더 면제 5 · ⓒ 제외/모양 10 · ⓓ 대소문자·이름 거절 9 · ⓕ 모듈 직접 9 · ⓙ 변이 8 · ⓚ 격리) · 기존 51 PASS → **121 PASS**.
- `harness/tests/test_doc_exempt_guard_r741.sh` (**신규**) = 가드. 키트 bin·훅에서 `design/teams/<팀>/<조각>` 리터럴을 모아 그 조각이 `EXCLUDE_DIRS`(또는 이유를 적은 `ALLOW_READERS`)에 있는지 대조 — 새 도구가 팀 하위 폴더를 판정 입력으로 읽기 시작하면 FAIL.

## 증거 파일
- `01-red-old-vs-new.txt` — ⓐ 빨강. 옛 판(origin/main)이 카드 실측 4경로(`feature/evidence/` · `room/evidence-t1/` · `planner/20261022/` · `feature/a/b/c`) 를 `NOT 팀 하위 폴더` rc1 로 거절, 새 판은 같은 4건 `DOC-EXEMPT … team=<팀> by=<좌석>` rc0 (임시 origin+clone · 가짜 tmux 좌석 · 실 착지 0).
- `02-tests.txt` — `bash harness/tests/test_doc_exempt_r725.sh` 전문 · **127 PASS · ALL PASS**.
- `03-guard-tests.txt` — `bash harness/tests/test_doc_exempt_guard_r741.sh` 전문 · **10 PASS · ALL PASS**(다섯 폴더 스캔이 읽는 곳을 실제로 찾음 · 빠진 이름/폴더 0 · 변이 2건이 실제로 잡힘 · `--emit` == 모듈 블록).
- `04-kit-bin-cmp.txt` — 키트 ↔ harness/bin cmp0 2파일 · 줄 수(ft_doc_exempt 311→287 · 새 모듈 132) · EXCLUDE_NAMES 101개.
- `05-scope-change.txt` — 옛 `team_of` ↔ 새 모듈 원문, 기존 시험 기대값 중 뒤집힌 항목 3개 목록(ⓗ).
- `06-regression.txt` / `06-regression-baseline-r1.txt` — 관련 계약 시험 9종 rc · 선행 실패 3종은 origin/main 사본에서 같은 값.
- `07-da6-r1-prescription.txt` — DA⑥ r1 처방 1~6 ↔ 구현·시험·반례 원문 대조.
- `08-r3-choice1-a-only.txt` — 오빠 선택지 1(하위 폴더 A 만) ↔ 구현·시험·반례 · 가드 경로 오타 고침 원문.

## 재현 명령
```
cd feature-pack/fable-team/harness
bash tests/test_doc_exempt_r725.sh          # 127 PASS
bash tests/test_doc_exempt_guard_r741.sh    # 10 PASS
bash tests/test_doc_exempt_guard_r741.sh --emit   # EXCLUDE_NAMES 튜플 재생성(모듈에 그대로 붙인다)
```

## master 몫 (이 카드 밖)
- 설치: 키트 bin 폴더 참조(`ft-root-bin-shim.sh --path kit/fable-team/bin`) — **새 모듈 `ft_doc_exempt_paths.py` 도 LIVE_BIN 트리에 함께 있어야** import 가 산다(cmp 대상 2파일).
- DA⑥ 1회(제외 목록 완전성 · 경로 모양 우회 · 대소문자 · 가드가 실제로 잡는지) → 착지 → planner GUIDE 범위 문구 1줄 → ⓛ 실사건(증거 하위 폴더 문서 PR 무승인 착지 원문) → 카드 꼬리 줄 → 완성 이동.
- press 필요: 없음(이 단위는 라이브 오디오 축 아님 · 단위·격리 시험만).

## 발견(카드 밖 · 목록만)
- `key_change_ledger.py:15` 의 `LEDGER_REL = "design/ops/keys/LEDGER-keys.md"` 가 옛 경로(R318 팀 폴더 이동 뒤 실재 = `design/teams/ops/keys/LEDGER-keys.md`) — 별 카드 후보(카드 §발견 그대로).
