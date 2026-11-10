# RESULT — kit-bin-adopt (2026-10-07 · 좌석 byz-harness-nano-kit-bin-adopt#0 · 브랜치 nano/kit-bin-adopt)

골좌표: 하네스 C 축 / 닫는 증거(정본 복붙): 「RELEASE-<ver>.md 1장 + 머신별 「반영됨 <machine> <sha>」 행 전부」 — 이 단위는 그 전제(키트 bin 단일 원본)만 만든다.

라이브 = `.worktrees/v6-realtime-live/.fable-team/bin/`(`.bak*`·`__pycache__` 제외) · 추적본 = `scripts/fable-team-bin/` · 키트 = `scripts/harness-install/fable-team/bin/`. sha 는 sha256 앞 8자, `-` = 없음.

## 분류 요약

| 분류 | 파일 수 |
|---|---|
| 라이브=키트·추적본 다름 | 5 |
| 추적본만 | 24 |
| 라이브=키트(추적본 없음) | 13 |
| 동일 3열 | 16 |
| 키트만 | 11 |
| 라이브=키트·추적본 다름(추적본 채택) | 2 |
| 셋 다 다름 | 2 |
| **합계** | **73** |

## 3열 sha 표 (73행)

| 파일 | 라이브 | 추적본 | 키트 | 분류 | 채택본·이유 |
|---|---|---|---|---|---|
| ft-blocked-on-master.sh | 2855ad7c | 65658b0e | 2855ad7c | 라이브=키트·추적본 다름 | 키트(=라이브) 채택 → 추적본을 키트 바이트로 |
| ft-branch-candidates.sh | - | d559553a | - | 추적본만 | 추적본 채택 → 키트에 추가(추적본 바이트) |
| ft-broadcast.sh | 8ac9ceef | - | 8ac9ceef | 라이브=키트(추적본 없음) | 라이브=키트 — 손대지 않음 |
| ft-bundle-state.sh | - | 3c243fbd | - | 추적본만 | 추적본 채택 → 키트에 추가(추적본 바이트) |
| ft-checkpoint.sh | d4402461 | d4402461 | d4402461 | 동일 3열 | 세 사본 같음 — 손대지 않음 |
| ft-claude-context.sh | 8ce8fb2f | - | 8ce8fb2f | 라이브=키트(추적본 없음) | 라이브=키트 — 손대지 않음 |
| ft-close-reason-check.sh | - | b3ae7269 | - | 추적본만 | 추적본 채택 → 키트에 추가(추적본 바이트) |
| ft-context-monitor.sh | 9038582a | - | 9038582a | 라이브=키트(추적본 없음) | 라이브=키트 — 손대지 않음 |
| ft-ctx-triage.sh | - | - | ee37415d | 키트만 | 키트만 있음 — 삭제·변경 0 |
| ft-env-fingerprint.sh | 1b43dfd4 | - | 1b43dfd4 | 라이브=키트(추적본 없음) | 라이브=키트 — 손대지 않음 |
| ft-gh-as-tank.sh | - | 30fe9a64 | - | 추적본만 | 추적본 채택 → 키트에 추가(추적본 바이트) |
| ft-goal-check.sh | 440069a9 | 440069a9 | 440069a9 | 동일 3열 | 세 사본 같음 — 손대지 않음 |
| ft-goal-tick.sh | 15ee0964 | 15ee0964 | 15ee0964 | 동일 3열 | 세 사본 같음 — 손대지 않음 |
| ft-gzip.sh | - | - | d91102ea | 키트만 | 키트만 있음 — 삭제·변경 0 |
| ft-harness-info.sh | - | e5de9d3e | - | 추적본만 | 추적본 채택 → 키트에 추가(추적본 바이트) |
| ft-hil-answer.sh | - | 84334bc5 | - | 추적본만 | 추적본 채택 → 키트에 추가(추적본 바이트) |
| ft-hil-ask.sh | - | 8058e3c9 | - | 추적본만 | 추적본 채택 → 키트에 추가(추적본 바이트) |
| ft-index-gate.sh | b5ff54b3 | b5ff54b3 | b5ff54b3 | 동일 3열 | 세 사본 같음 — 손대지 않음 |
| ft-index-lint.sh | 2f597acd | - | 2f597acd | 라이브=키트(추적본 없음) | 라이브=키트 — 손대지 않음 |
| ft-index-move.sh | 44059276 | 48eae91c | 44059276 | 라이브=키트·추적본 다름 | 키트(=라이브) 채택 → 추적본을 키트 바이트로 |
| ft-issue-classify.sh | - | 9a235db5 | - | 추적본만 | 추적본 채택 → 키트에 추가(추적본 바이트) |
| ft-issue-close-check.sh | - | ab8c685c | - | 추적본만 | 추적본 채택 → 키트에 추가(추적본 바이트) |
| ft-issue-create-pair.sh | - | fcf85fb2 | - | 추적본만 | 추적본 채택 → 키트에 추가(추적본 바이트) |
| ft-issue-reopen.sh | - | 957e0925 | - | 추적본만 | 추적본 채택 → 키트에 추가(추적본 바이트) |
| ft-land.sh | - | 8c66012a | - | 추적본만 | 추적본 채택 → 키트에 추가(추적본 바이트) |
| ft-lib.sh | - | - | 258dbb38 | 키트만 | 키트만 있음 — 삭제·변경 0 |
| ft-master-lst-cron-ping.sh | b21075ae | - | b21075ae | 라이브=키트(추적본 없음) | 라이브=키트 — 손대지 않음 |
| ft-master-tick.sh | c7875699 | - | c7875699 | 라이브=키트(추적본 없음) | 라이브=키트 — 손대지 않음 |
| ft-mbox-bridge.sh | 98eeb09a | 98eeb09a | 98eeb09a | 동일 3열 | 세 사본 같음 — 손대지 않음 |
| ft-mbox-census.sh | e7f351ef | - | e7f351ef | 라이브=키트(추적본 없음) | 라이브=키트 — 손대지 않음 |
| ft-mbox.py | - | - | 5ab6ad3f | 키트만 | 키트만 있음 — 삭제·변경 0 |
| ft-mbox.sh | - | - | 35740710 | 키트만 | 키트만 있음 — 삭제·변경 0 |
| ft-name-lint.sh | - | d3472375 | - | 추적본만 | 추적본 채택 → 키트에 추가(추적본 바이트) |
| ft-nano-cherry-gate.sh | 90f020aa | 90f020aa | 90f020aa | 동일 3열 | 세 사본 같음 — 손대지 않음 |
| ft-nano-close.sh | 7a450dbf | fb6aa899 | 7a450dbf | 라이브=키트·추적본 다름 | 키트(=라이브) 채택 → 추적본을 키트 바이트로 |
| ft-nano-evidence-check.sh | 08a5506b | 08a5506b | 08a5506b | 동일 3열 | 세 사본 같음 — 손대지 않음 |
| ft-nano-freshness.sh | db3f6526 | db3f6526 | db3f6526 | 동일 3열 | 세 사본 같음 — 손대지 않음 |
| ft-nano-slots.sh | 001ba657 | 29f9105f | 001ba657 | 라이브=키트·추적본 다름(추적본 채택) | ★추적본이 더 새로움★ — 추적본 채택 → 키트를 추적본 바이트로(arch 판정 ⓐ · 58708 · §추적본 채택 2 파일) |
| ft-nano-spawn.sh | d75e12c6 | aa252c7d | d75e12c6 | 라이브=키트·추적본 다름(추적본 채택) | ★추적본이 더 새로움★ — 추적본 채택 → 키트를 추적본 바이트로(arch 판정 ⓐ · 58708 · §추적본 채택 2 파일) |
| ft-news-tick-cfo.sh | 0924cbe5 | 0924cbe5 | 0924cbe5 | 동일 3열 | 세 사본 같음 — 손대지 않음 |
| ft-news-tick.sh | ad9335fc | 51e35f93 | ad9335fc | 라이브=키트·추적본 다름 | 키트(=라이브) 채택 → 추적본을 키트 바이트로 |
| ft-news-tree.py | 6b2a08af | 2a48d801 | 10beca84 | 셋 다 다름 | 라이브 채택 → 키트=라이브 바이트, 추적본=키트 바이트(diff 요약 아래) |
| ft-orphan-cards.sh | - | 730ceaa4 | - | 추적본만 | 추적본 채택 → 키트에 추가(추적본 바이트) |
| ft-plan-handoff.sh | - | e93a5c79 | - | 추적본만 | 추적본 채택 → 키트에 추가(추적본 바이트) |
| ft-pm-tick.sh | 0cf62a8b | - | 0cf62a8b | 라이브=키트(추적본 없음) | 라이브=키트 — 손대지 않음 |
| ft-pm-watchd.sh | - | - | 8cef25e6 | 키트만 | 키트만 있음 — 삭제·변경 0 |
| ft-press-gate.sh | c19f7368 | c19f7368 | c19f7368 | 동일 3열 | 세 사본 같음 — 손대지 않음 |
| ft-press-permit.sh | - | 81ecff55 | - | 추적본만 | 추적본 채택 → 키트에 추가(추적본 바이트) |
| ft-press-set-check.sh | 1c273acd | 1c273acd | 1c273acd | 동일 3열 | 세 사본 같음 — 손대지 않음 |
| ft-reach-check.sh | e208fff4 | - | e208fff4 | 라이브=키트(추적본 없음) | 라이브=키트 — 손대지 않음 |
| ft-regress-pack.sh | - | ac6db321 | - | 추적본만 | 추적본 채택 → 키트에 추가(추적본 바이트) |
| ft-regress-reopen.sh | - | 9c8018d2 | - | 추적본만 | 추적본 채택 → 키트에 추가(추적본 바이트) |
| ft-role-spawn.sh | b135b558 | 0bdf3a22 | 4fac2b26 | 셋 다 다름 | 라이브 채택 → 키트=라이브 바이트, 추적본=키트 바이트(diff 요약 아래) |
| ft-seat-live.sh | - | 836201f9 | - | 추적본만 | 추적본 채택 → 키트에 추가(추적본 바이트) |
| ft-seat-request.sh | - | 902e6eec | - | 추적본만 | 추적본 채택 → 키트에 추가(추적본 바이트) |
| ft-seat-status.sh | 9437bac5 | 9437bac5 | 9437bac5 | 동일 3열 | 세 사본 같음 — 손대지 않음 |
| ft-send-verified.sh | 0faf7f7d | - | 0faf7f7d | 라이브=키트(추적본 없음) | 라이브=키트 — 손대지 않음 |
| ft-tank-verify.sh | - | 59bc4ed0 | - | 추적본만 | 추적본 채택 → 키트에 추가(추적본 바이트) |
| ft-test-bundle-lint.sh | - | a1543977 | - | 추적본만 | 추적본 채택 → 키트에 추가(추적본 바이트) |
| ft-tick-install.sh | f2760542 | f2760542 | f2760542 | 동일 3열 | 세 사본 같음 — 손대지 않음 |
| ft-tick.plist | a5fca2ac | a5fca2ac | a5fca2ac | 동일 3열 | 세 사본 같음 — 손대지 않음 |
| ft-tick.sh | d28c3234 | 80f1a437 | d28c3234 | 라이브=키트·추적본 다름 | 키트(=라이브) 채택 → 추적본을 키트 바이트로 |
| ft-tmux-distill.sh | - | - | 7a4672a4 | 키트만 | 키트만 있음 — 삭제·변경 0 |
| ft-tmux-kill.sh | - | - | 13c54fda | 키트만 | 키트만 있음 — 삭제·변경 0 |
| ft-tmux-poll.sh | - | - | 3de34cf9 | 키트만 | 키트만 있음 — 삭제·변경 0 |
| ft-tmux-send.sh | - | - | 0e0cc552 | 키트만 | 키트만 있음 — 삭제·변경 0 |
| ft-tmux-spawn.sh | - | - | 3d1243aa | 키트만 | 키트만 있음 — 삭제·변경 0 |
| ft-wall-check.sh | c803a79c | - | c803a79c | 라이브=키트(추적본 없음) | 라이브=키트 — 손대지 않음 |
| ft-wall-read.sh | b4a9b964 | - | b4a9b964 | 라이브=키트(추적본 없음) | 라이브=키트 — 손대지 않음 |
| ft-worktree-triage.sh | 191895bb | 191895bb | 191895bb | 동일 3열 | 세 사본 같음 — 손대지 않음 |
| ft-wt-sweep.sh | e288d2de | e288d2de | e288d2de | 동일 3열 | 세 사본 같음 — 손대지 않음 |
| harness-monitor.sh | - | 02481f89 | - | 추적본만 | 추적본 채택 → 키트에 추가(추적본 바이트) |
| mbox-v2.sh | - | 40fa2188 | - | 추적본만 | 추적본 채택 → 키트에 추가(추적본 바이트) |

## 셋 다 다른 2 파일 — diff 요약 (라이브 채택 · 합치지 않고 보고만)

**ft-role-spawn.sh** (라이브 b135b558 · 추적본 0bdf3a22 · 키트 4fac2b26)
- 라이브 vs 키트: 10-07 이름 접두 수정(`FT_ROLE_BASE_PREFIX`·`LEGACY_BASE`·옛 계보 번호 이어받기/교체)만 라이브에 있음 — 키트는 그 앞 세대.
- 라이브 vs 추적본: 위 + 역할 `tester` 추가 · 기본 모델 `claude-opus-5-5[1m]`(09-29 오빠 확정) · `gpt-6-astra*` effort low 강제 REJECT · 같은 계열(베이스명)만 교체. 추적본 기본 모델은 `claude-fable-5-1[1m]`.
- **라이브에 없는 다른 사본의 변경 줄: 없음**(추적본·키트 모두 라이브의 부분집합 — 라이브 채택으로 잃는 줄 0). 추적본 실행 비트는 644 → 채택 후 755(키트와 동일).

**ft-news-tree.py** (라이브 6b2a08af · 추적본 2a48d801 · 키트 10beca84)
- 라이브 vs 추적본: 라이브에 세션 상태 절(`seat_state`·`session_block`·`short`·`tmux_alive` · 09-29 오빠 지시)이 있고 추적본엔 없음.
- 라이브 vs 키트: 키트는 라이브와 «공백·줄바꿈·괄호 정리»만 다름(공백·괄호 제거 후 비교 시 동일) — 기능 차이 0.
- **라이브에 없는 다른 사본의 변경 줄: 없음.**

## 추적본 채택 2 파일 (arch 판정 ⓐ · 58708) — 카드 전제와 어긋난 곳

카드 «라이브=키트 7개는 추적본만 뒤처짐» 이 2개에서는 반대였다(추적본 마지막 커밋 3928822c16 · 10-06). 키트로 덮으면 `test_baseline_lint`·`test_nano_slots` 가 깨지는 것을 실측해 master 에 물었고(58704), arch 가 ⓐ(키트·추적본 둘 다 추적본 바이트)로 판정했다. 나머지 5(ft-blocked-on-master·ft-index-move·ft-nano-close·ft-news-tick·ft-tick)는 키트가 새것이라 카드대로 채택.

| 파일 | 추적본에만 있는 줄 | 키트(=라이브)에만 있는 줄 |
|---|---|---|
| ft-nano-slots.sh | 27 | 12 |
| ft-nano-spawn.sh | 10 | 0 |

**설치 때 라이브에 생기는 동작 변화** (키트 설치 = 라이브가 추적본 바이트로 바뀜)
- **ft-nano-slots.sh**
  - 기본 슬롯 상한 6 → 5(`FT_NANO_SLOTS` 로 조정 가능).
  - 후보 필터가 «press 불요 표기(`press 0|불요|없음`·`서버 0`·`시험만`·`읽기 전용`)» 에서 «대기/ 카드 머리줄 4줄(Issue·상태·선행·시험 입력)» 로 바뀐다 → 머리줄이 모자란 대기 카드는 후보에서 제외(제외 사유 1줄 출력)되어 지금 대기 카드 대부분이 후보에서 빠진다.
  - `FT_ACTIVE_ISSUES="#12,#13"` 로 활성 Issue 카드만 후보로 거를 수 있고, 예약석 +1(상한 밖 · `"reserved": true` 행 · `상태:` 에 «라이브» 가 든 카드 전용)이 생긴다.
  - SLOTS 줄 형식이 `점유 N/상한 (일하는 석 · 노는 석) · 빈 석 · 예약석` 으로 바뀌고, 노는 석은 빈 석이 아니라 «푸는 대상»으로 센다. 빈 석 안내 줄(「★빈 석 N — 이 턴에 spawn 한다…」)은 제거.
- **ft-nano-spawn.sh**: 라이브 상위집합(+10줄). 카드 머리줄 4줄 누락(C6)·기준값 머리줄 누락/빈칸(C20)을 REJECT 가 아니라 «WARN 후보 제외» 로 알린다 — spawn 자체는 막지 않는다.

## 검증 값

- 키트 bin 파일 수 = **73**(24 추가 후) · 추적본 49 → «추적본의 모든 파일이 키트에 있고 바이트·실행 비트 같음».
- `bash scripts/harness-install/fable-team/install.sh --home <mktemp>` 드라이런: `files=101`(bin 73 + templates 등 28) · bin 줄 수 73 = 키트 bin 파일 수.
- 시험: `tests/harness/test_kit_bin_sync.sh`(음성 대조 3종 포함).
