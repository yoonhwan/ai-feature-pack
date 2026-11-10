# r461 master-steps — 병합 줄 대조가 «다른 폴더로 옮긴 파일» 을 옮긴 곳에서 센다 (집행 순서 · master)

카드 `design/harness/indices/진행/r461-merge-lines-gate-moved-file-is-not-loss.md` · 나노 byz-harness-nano-r461-merge-lines-gate-moved-file-is-not-#0

## 가지 1
| 리포 | 가지 | 내용 |
|---|---|---|
| ai-feature-pack | `nano/r461-merge-lines-gate-moved-file-is-not-` (워크트리 `.worktrees/nano-r461-merge-lines-moved` · base d8305edb = origin/main) | 키트 1 파일(bin·kit 짝 cmp0) `ft_merge_lines.py` · 시험 1 `tests/test_merge_lines_moved.sh` · CHANGES 1절 · manifest 1.1.26 |
| BYZ-Agents | `nano/r461-merge-lines-gate-moved-file-is-not-` | 커밋 0(이 단위는 팩만) |

## 순서
1. 팩 PR → main 착지(push·PR·`ft-merge-land` = master). 착지 전 팩 루트에서 `tests-rc.txt` 의 명령 재실행.
2. 설치: `bash feature-pack/fable-team/harness/install.sh --apply --project <BYZ 공용 루트>` → LIVE_BIN `ft_merge_lines.py` `cmp` rc0 · 되돌림 = `.bak-r461`. `ft-live-install-check.sh --range d8305edb..<착지 sha>` OK.
3. 실사건(설치 뒤 · BYZ 공용 루트 cwd · loom master 실행): `bash <LIVE_BIN>/ft-merge-gate.sh <loom 새 head>`.
   ★주의 — 카드 기대(«39a6d47bc0 통과 1줄»)는 이 규칙만으로 안 나온다★ (나노 실측 · M=30cef9026e = 17:53 거절 당시 origin/main · 읽기만):
   옛 판 DENY 15건 → 새 판 DENY 14건(살린 것 = `대기/loom-789-u2b-preload-empty-locate.md` D → `완성/` 같은 내용 1건).
   남은 14건은 «경로 글자» 가 아니라 카드 본문 줄(base_sha·선행·상태·시험 줄)이 main 판과 다르다 — main 이 F(299767bef7) 이후 고친 카드 내용을
   S 의 «옮긴 카드» 가 안 가졌다. loom ⓐ(origin/main 판 복원)가 같은 경로 파일만 덮어서 옮긴 카드가 빠진 것.
   → loom 쪽 처리: 옮긴 카드 14장에 main 판이 더한 줄을 넣는다(새 판 DENY 문구가 «<새 경로> 로 이동했으나 main 이 더한 줄 N 개 없음» 으로 위치를 짚는다) → 새 head 로 게이트 재실행 → 그 PASS 줄이 실사건.
   14장 목록(`design/teams/loom/indices/` 아래 · 옛 → 새 · 없는 줄 수):
   대기/loom-1512-c → 완성 2 · 대기/loom-2006-1 → 완성 7 · 대기/loom-api-d1 → 진행 12 · 진행/loom-1187-knowledge-cap → 완성 3 ·
   진행/loom-1439-1440-a → 완성 2 · 진행/loom-1439-1440-reembed → 대기 1 · 진행/loom-1470-atoz-r2 → 완성 1 · 진행/loom-1580f-loom-interim → 완성 3 ·
   진행/loom-1653-a → 완성 1 · 진행/loom-1653-b → 완성 1 · 진행/loom-1694 → 완성 1 · 진행/loom-1826 → 완성 1 · 진행/loom-789-u1 → 완성 5 · 진행/loom-789-u4b → 완성 1
4. 정본: 없음(판정기 규칙 · 지침 줄 0).

## 편차
- 카드 «48장 = 경로 글자만 치환» 은 실측과 다르다: M=30cef9026e 기준 게이트가 막은 건 15건이고(나머지 이동은 git R 로 이미 통과), 그중 14건은 본문 줄 차이.
- 카드 처방 «lost>0 이면 basename 재검색» → D 일 때만 재검색(같은 경로 M 파일은 재검색 0 — 다른 폴더의 같은 이름 파일로 소실이 덮이는 오탐 방지). R 은 git 이 고른 새 경로로 센다.
- 치환은 «줄마다 그대로 / 1쌍 치환 중 많은 쪽» — S 가 옛 경로 글자 줄을 그대로 둔 경우(자기 참조 링크 등)도 소실로 안 읽게(전체 치환만 하면 loom-1187·789-u1 에서 소실이 늘어남 · 실측).

## 남은 빨강 (이 단위 밖 · 내 변경 무관)
- `tests/test_goal_hook_merge.sh` rc2 fail=2: `../../scripts/git-hooks/v65-goal-commit-msg.sh` 없음(팩에 BYZ 스크립트 경로) — origin/main 그대로도 같다(이 단위 변경은 `ft_merge_lines.py` 만, 그 시험은 호출 0).
