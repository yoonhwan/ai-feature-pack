# r551 증거 — 주간 점검표 planner 칸 P1·P2 의 «읽는 출처» = origin/main gitref (r545 꼴 · 쓰는 자리 그대로)

카드: `design/harness/indices/진행/r551-weekly-review-planner-reads-origin-main.md` · 팩 브랜치 `nano/r551-weekly-review-planner-reads-origin-` · 1.1.104 · base = origin/main `c2d4a24b`(r546 병합 뒤)

| 파일 | 무엇 |
|---|---|
| `before-red-base-code.txt` | **base 코드(1.1.103) + 새 시험** — `6 failed, 11 passed`(red-first · ⓐ~ⓓ + 기존 사실 시험이 체크아웃 판을 읽어 빨강) |
| `after-pass-mine.txt` | **고친 코드 + 새 시험** — `17 passed` |
| `base-tests-with-my-code.txt` | 고친 코드 + **옛 픽스처 시험** — `3 failed, 10 passed`: 옛 픽스처에는 `origin/main` 자체가 없다(옛 계약 = 디스크 출처). 새 계약에서는 그 픽스처가 성립하지 않으므로 이 사분면은 «빨강이 정상»(r545 4분면 꼴) |
| `real-behind-checkout-readonly.txt` | 실 체크아웃(290커밋 뒤처짐) 읽기 전용 실측 — 고치기 전/뒤 + 원장 두 판 실제 차이(333줄 vs 310줄 · diff 64줄) |
| `ruff.txt` | `All checks passed!`(kit·bin·시험) |

## 계약 (시험 ⓐ~ⓔ)

- ⓐ `test_p2_ignores_behind_checkout` — 체크아웃의 «문제 0» 원장이 아니라 origin/main 판(문제 1줄). **base 에서 FAIL**.
- ⓑ `test_p2_source_is_origin_main_sha` — 사실 칸 끝에 `origin/main@<sha10>` = `git rev-parse --verify origin/main` 앞 10자.
- ⓒ `test_p1_reads_origin_main_queue` — 대기열도 origin/main 판(체크아웃 = 열린 행 0) + 같은 출처 표기.
- ⓓ `test_planner_folder_missing_on_ref_is_said_not_checkout` — ref 에 planner 폴더가 없으면 «확인 못 함»(조용히 체크아웃으로 내려가지 않는다 · 0번 규칙).
- ⓔ 기존 시험 13건 전부 통과(같은 파일 · 같은 단언) · 짝 셸 시험 `tests/test_team_literal_paths.sh` `fail=0`(ⓐ1·ⓐ2 p1_queue 포함 · 120 PASS).

## 바뀐 것

- `kit/fable-team/bin/ft_weekly_review.py`(정본) = `harness/bin/ft_weekly_review.py`(짝 cmp0):
  - `p1_queue`·`p2_ledger` = `planner_ref()` 가 푼 `<ref commit>:<planner 폴더>/<파일>` 에서 읽는다 — 파일 목록 = `git ls-tree`, 본문 = `git show`. ref = env `FT_TEAMS_REF`(기본 `origin/main`).
  - 폴더는 r545 `ft_goal_ledger.planner_rel_in_ref` **재사용**(ref 트리에서 정확히 1개 · 디스크 실재 여부 안 봄).
  - ref 에 없으면 예외 → 지금 `safe()` 가 «확인 못 함» 으로 칸에 남긴다(체크아웃 후퇴 0).
- `tests/scripts/test_ft_weekly_review.py`: 픽스처에 «뒤처진 체크아웃 + 앞선 origin/main» 2판을 넣고(옛 픽스처 = `design/planner` 문제 0, ref = `design/teams/planner` 문제 1) ⓐ~ⓓ 시험 추가. 기존 단언·기존 시험 본문은 그대로. `test_unreadable_source_is_said_not_silent` 만 «못 읽는 출처» 입력을 디스크 chmod → 없는 ref(`FT_TEAMS_REF=origin/없는가지`)로 바꿨다(출처가 gitref 라 디스크 권한이 더는 출처가 아니다).

## 범위 밖 (그대로)

점검표를 쓰는 자리(planner 좌석 체크아웃 · 설계대로) · `v6-realtime-live` 에 생긴 untracked 점검표 파일(planner 팀 몫) · planner 좌석이 뒤처진 공용 체크아웃에 앉는 문제(planner·ops 몫) · H1~H8 칸 · 쪽지 규칙.

press(라이브 오디오) 0 — 이 카드는 점검 도구의 읽기 출처이고 제품 키·말풍선·음성 경로를 건드리지 않는다. **press 필요 없음.**
설치(`install.sh --apply` → LIVE_BIN cmp0 1)·실사건(다음 월요일 실행 원문의 P2 칸)은 master 집행.
