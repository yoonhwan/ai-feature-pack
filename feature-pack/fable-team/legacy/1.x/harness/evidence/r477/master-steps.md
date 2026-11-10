# r477 master-steps — 병합 줄 대조가 «팀 폴더 옛 꼴 글자만 바꾼 줄» 을 같은 줄로 센다 (집행 순서 · master)

카드 `design/harness/indices/진행/r477-merge-lines-gate-pathsubst-team-folder-rewrite-is-same-line.md` · 나노 byz-harness-nano-r477-merge-lines-gate-pathsubst-team-fol#0

## 가지 1
| 리포 | 가지 | 내용 |
|---|---|---|
| ai-feature-pack | `nano/r477-merge-lines-gate-pathsubst-team-fol` (워크트리 `.worktrees/nano-r477-merge-lines-gate-pathsubst-team-fol` · base 1bc45eb2 = origin/main) | 키트 1 파일(bin·kit 짝 cmp0) `ft_merge_lines.py` · 시험 1 `tests/test_merge_lines_pathsubst.sh` · CHANGES 1절 · manifest 1.1.39 · evidence 2 |
| BYZ-Agents | `nano/r477-merge-lines-gate-pathsubst-team-fol` | 커밋 0(이 단위는 팩만) |

## 순서
1. 팩 PR → main 착지(push·PR·`ft-merge-land` = master). 착지 전 팩 루트에서 `tests-rc.txt` 의 명령 재실행.
2. 설치: `bash feature-pack/fable-team/harness/install.sh --apply --project <BYZ 공용 루트>` → LIVE_BIN `ft_merge_lines.py`·`ft_team_lib.py` `cmp` rc0 · 되돌림 = `.bak-r477`. `ft-live-install-check.sh --range 1bc45eb2..<착지 sha>` OK(설치 필요 카드).
3. 실사건(설치 뒤 · 읽기만): `bash <LIVE_BIN>/ft-merge-gate.sh <loom PR 1976 head>` — ★카드 기대 «PASS» 는 head 280b041aa5 로 안 나온다(아래 편차)★.

## 실사건 실측 (읽기만 · M=75b386c55e = 2026-10-19 19:26 main · S=280b041aa569 = PR 1976 head)
- 옛 판(1.1.30): `DENY … F=299767bef7` 83파일 · PATHSUBST 0. 게이트 출력은 `bad[:8]` 이라 첫 8개만 보인다 — 카드의 «8파일» 은 절단값이다.
- 새 판: **DENY 2파일 · PATHSUBST 155줄**. 남은 2:
  - `design/teams/loom/indices/완성/loom-1826-byz-common-cap-exemption.md` — main 줄의 `design/concierge/…` 를 S 가 `design/teams/concierge/…` 로 바꿈.
  - `design/teams/loom/indices/완성/loom-2006-1-chat-rule-include-conditions.md` — 같은 꼴.
- 왜 거절인가: `concierge` 는 r468 에서 `chatbot` 으로 개명돼 **현행 명단(`TEAMS.md`)에 없다** — 카드 §구현범위 1·시험 ⓒ «명단에 없는 팀 글자는 치환 0 · 추측 0» 대로 DENY(개명 별칭 추측 금지). `design/teams/concierge/` 는 실제 폴더도 아니다.
- 통과 조건: loom 이 그 2줄을 main 판 그대로 두거나(옛 경로 글자 유지 · lint 예외), main 이 먼저 `design/teams/chatbot/…` 로 고친 뒤 그 줄을 S 가 같게 가져가야 한다. → planner/arch 가 loom 에 값으로 내려야 한다(하네스가 추측으로 별칭을 넣지 않는다).

## 편차
- **카드 내부 모순 1**: §구현범위 1 은 «`added_lines` Counter 키와 `have` Counter 키 둘 다 정규화» 라고 쓰지만, 양쪽을 대칭 정규화하면 시험 ⓓ(«새 꼴 → 옛 꼴» 역방향 = DENY)가 PASS 로 뒤집힌다(실측 · 새 시험 ⓓ). 고침 = 정규화는 «main 이 더한 줄» 에만(한 방향) · 후보 줄은 원문 그대로 센다. 카드의 «정규화는 한 방향 · 옛 꼴 복원은 소실» 문장과 일치 — arch/DA 가 이 편차를 판정해야 한다.
- **카드 기대 실사건 미충족**: «loom PR 1976 PASS» 는 위 2파일 때문에 이 head 로 성립하지 않는다. 원인은 구현이 아니라 PR 이 명단 밖 재명명 팀(`concierge`) 경로를 바꾼 것 — 새 판은 81파일/155줄을 살렸고, 남은 2는 규칙대로 거절한다.
- **WARN 조건**: 명단을 «기대할 수 있는» 저장소(명시 `FT_TEAMS_REF` · 체크아웃 `design/TEAMS.md` · ref 트리 `design/TEAMS.md`)에서만 stderr WARN 1줄. 합성 픽스처(명단 없음)는 WARN 0 — 기존 시험 출력을 안 깨뜨린다(옛 merge 시험 9종 ALL PASS 로 확인).
- 선재 빨강(내 변경 무관 · origin/main 그대로): `test_goal_hook_merge.sh` fail=2(팩에 BYZ 스크립트 경로 없음) · `test_spawn_gate_landing_branch.sh` FAILED=1.

## 정본
- 없음(게이트 판정식 1개 · 지침 줄 0) · 되돌림 = `.bak-r477`(설치 시).
