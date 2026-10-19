# r453 master-steps — `pipefail` + `… | grep -q` 64 KB SIGPIPE 오판 (집행 순서 · master)

카드 `design/harness/indices/진행/r453-nano-close-worktree-list-pipe-sigpipe-pipefail.md` · 나노 byz-harness-nano-r453-nano-close-worktree-list-pipe-sigpi#0

## 가지 1
| 리포 | 가지 | 내용 |
|---|---|---|
| ai-feature-pack | `nano/r453-nano-close-worktree-list-pipe-sigpi` (워크트리 `.worktrees/r453-wl-pipe` · base fec5d3b3 = origin/main · 그 위에 r457 87ccd812·r456 d9c35e93 병합 — master 112374) | 키트 4 파일(bin·kit 짝 cmp0): `ft-nano-close.sh`(3줄) · `ft-landed-check.sh` · `ft-index-move-canon.sh` · `ft-scratch-repo.sh` · 새 시험 `tests/test_nano_close_worktree_list_pipe.sh` · CHANGES 1절 · manifest 1.1.25 · 이 파일 · `tests-rc.txt` |
| BYZ-Agents | `nano/r453-nano-close-worktree-list-pipe-sigpi` | 커밋 0(이 단위는 팩만) |

## 순서
1. 팩 PR → main 착지(push·PR·`ft-merge-land` = master). 착지 전 팩 루트에서 `tests-rc.txt` 의 명령 재실행.
2. 설치: `bash feature-pack/fable-team/harness/install.sh --apply --project <BYZ 공용 루트>` → LIVE_BIN 4 파일 `cmp` rc0(`ft-nano-close.sh` · `ft-landed-check.sh` · `ft-index-move-canon.sh` · `ft-scratch-repo.sh`) · 되돌림 = `.bak-r453`. `ft-live-install-check.sh --range fec5d3b3..<착지 sha>` OK.
3. 실사건 2(설치 뒤 · 라이브 실행본 · BYZ 공용 루트 cwd):
   `bash <LIVE_BIN>/ft-nano-close.sh 'byz-ops-nano-ta-1-tree-read#0' --plan-only <루트>/.worktrees/ops-nano-ta-1-tree-read`
   `bash <LIVE_BIN>/ft-nano-close.sh '<cfo 좌석>#0' --plan-only <루트>/.worktrees/cfo-cfo-insight-billing-flashlite-peg-1283`
   → 기대 = 각 `PLANNED <계획 경로>`(옛 판 = `REJECT --plan-only: 이 리포 .worktrees/ 아래 등록 워크트리가 아니다`). 두 줄을 카드 `- 실사건:` 에 복붙.
   ★주의★: 라이브 BYZ porcelain 은 나노 실측 시점 62,091 B(64 KB 경계 바로 아래)라 옛 판도 지금은 통과할 수 있다 — 실사건이 «고침의 증거» 가 되려면 `git -C <루트> worktree list --porcelain | wc -c` 값을 같은 줄에 적는다(>65,536 이면 옛 판 재현 조건). 결함 재현 자체는 시험 ⓐ(162,697 B 픽스처 · rc141)가 남긴다.
   (`PLANNED` 뒤 계획 실행 = 판정 2367 경로 · 이 단위 밖)
4. 정본 1줄(arch 손 · 착지 뒤): BYZ `.claude/rules/git-worktree-pitfalls.md` 5c 옆 «pipefail + `| grep -q` 도 같은 SIGPIPE 계열 — 긴 출력은 변수로 받은 뒤 here-string(`<<<`)으로 grep · printf 파이프도 같음(r453)».

## 편차
- 카드 처방 `printf '%s\n' "$_wl" | grep -qxF` → `grep -qxF … <<<"$_wl"`: printf 파이프도 같은 141(실측 · 시험 ⓐ 단언). here-string 은 파이프가 없어 SIGPIPE 0.
- 카드 «2곳» → `ft-nano-close.sh` 3곳: `--wt` ⓐ(`printf "$_porc" | grep -qxF`)도 같은 목록 · 같은 꼴.
- 전수 린트로 키트 3 파일 추가(표 = CHANGES): `ft-landed-check.sh`(미착지 → «cherry» fail-open) · `ft-scratch-repo.sh`(쓰는 중 tmp → 삭제 후보 fail-open) · `ft-index-move-canon.sh`(오판 REJECT). 입력이 작은 4곳은 유지.

## 남은 빨강 (이 단위 밖 · 내 변경 무관)
- `tests/test_evidence_inject_scan.sh` FAILED 5: ⑧ 증거 파일 `design/feature/evidence/multilingual-linebreak-impl-20261008/run.py` MISSING · ⑩⑩b⑫⑬ 임시 bin 에 `ft_da_hold_gate.py` 없음(REJECT `ft_da_hold_gate.py 없음`) — 시험 픽스처가 r456 류 새 의존을 안 복사. 새 카드 후보(판정 1395 «기존 RED» 변명 0).
