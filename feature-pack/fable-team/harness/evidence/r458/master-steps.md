# r458 master-steps — 원장 뉴스 출처 1곳 + 팀별 완성 진행 블록 (집행 순서 · master)

카드 `design/harness/indices/진행/r458-news-magazine-stall-recovery-and-team-progress-block.md` · 나노 byz-harness-nano-r458-news-magazine-stall-recovery-and-te#0

## 가지 1
| 리포 | 가지 | 내용 |
|---|---|---|
| ai-feature-pack | `nano/r458-news-magazine-stall-recovery-and-te` (워크트리 `.worktrees/nano-r458-news-magazine` · base d56b9c0e = origin/main) | 키트 6(bin·kit 짝 cmp0) `ft_news_ledger.py` `ft_goal_ledger.py` `ft_goal_table.py` `ft-goal-table.sh` `ft_news_ledger_text.py` `ft_news_post.py` + `slack-mirror/magazine_goal.py` `magazine_doc.py` · 시험 1 · 픽스처 1 · CHANGES · manifest 1.1.29 |
| BYZ-Agents | `nano/r458-news-magazine-stall-recovery-and-te` | 커밋 0(이 단위는 팩만) |

## 순서
1. 팩 PR → main 착지(master). 착지 전 팩 루트에서 `tests-rc.txt` 명령 재실행.
2. 설치: `install.sh --apply --project <BYZ 공용 루트>` → LIVE_BIN 6 파일 cmp0 + `~/.hermes/scripts/magazine_goal.py`·`magazine_doc.py` cmp0 · `ft-live-install-check.sh --range d56b9c0e..<착지 sha>` OK.
3. ★원장 정본 한 곳 정하기(뉴스가 나가려면 필수)★ — 나노 실측(읽기만 · 새 도구 함수 직접 호출 · 발행 0):
   - **안 A(가장 빠름 · 설치 즉시 발행)**: plist 에서 h182 env 2개(`FT_LEDGER_REPO`·`FT_NEWS_DIR`)를 지워 기본값(LIVE_ROOT = v6-realtime-live)으로 → `OK v6-realtime-live design/planner/PLAN-oppa-ledger.md cur 48f75dab49 news <루트>/design/planner/news` (그 리포 자신의 TEAMS.md 가 `design/planner/` 라 «후퇴» 아님 · 기준선 c7b4a5db8b 도 같은 경로 판 → 검사 통과). planner 폴더 이동 때(이동 순번 맨 끝) 아래 안 B 로 넘어간다.
   - **안 B(h182 유지)**: `ERR c-level-planning design/teams/planner/PLAN-oppa-ledger.md :: 기준선 c7b4a5db8b 판에 원장 정본 … 이 없다` — 아래 3단계를 다 해야 발행.
   지금 두 판이 갈라져 있다: v6-realtime-live `design/planner/`(최신 6913ea6dd2) vs c-level-planning·origin/main `design/teams/planner/`(c42c9a5d82 · 내용 22시간 묵음). 새 도구는 옛 경로로 후퇴하지 않으므로:
   - planner: 최신 원장 내용을 정본 리포의 `design/teams/planner/PLAN-oppa-ledger.md` 로 커밋(master 가 요청 · 113018).
   - plist `com.byz.ft-news-planner` env: `FT_LEDGER_REPO=<그 리포>`(경로는 그 리포 TEAMS.md 로 풀리므로 FT_LEDGER_PATH 불요) · h182 의 `FT_NEWS_DIR` 은 지운다(뉴스 폴더 = `<FT_ROOT>/design/teams/planner/news` — 실재 확인 필요 · 다른 곳을 원하면 FT_NEWS_DIR 유지).
   - 기준선: `<FT_ROOT>/.fable-team/state/news-ledger/last.sha` 지금 값 c7b4a5db8b(옛 경로 판) → 그대로면 `기준선 c7b4a5db8b 판에 원장 정본 … 이 없다` ERROR 가 계속 난다. 정본 경로 판 sha(예: c42c9a5d82 — 새 경로 첫 판)로 바꾼다(되돌림 = 옛 값 c7b4a5db8b9f16b5e014f605e47d0b5024be6ba7). 그 뒤 planner 원장 커밋 1번이면 차이 발행.
4. 실사건: launchd `com.byz.ft-news-planner` 다음 발행 1건 — `/tmp/byz-ft-news-planner.log` 에 `팀 명단 없음`·`exists on disk, but not in`·`기준선 … 이 없다` 0 · 뉴스 파일 첫 판에 `★골 표 A6` + `★팀별 완성 진행` 블록(원장에 `## 팀별 완성 진행` 표가 생긴 뒤 · 없으면 WARN 만 · 발행은 됨).
5. planner 발주 1통: 원장에 `## 팀별 완성 진행` 표(열 = 팀 | 끝선 N/M | 마지막 착지 | 지금 하는 것 · 행 = 재가동 표 순번 0~11 팀).
6. 집행 3줄(카드 §6 · 착지와 무관): ft-tick kickstart · airag plist 2개 bootout + `.disabled` · 매거진 재발행(planner 원장 §4 정정 뒤).

## 남은 것(나노 기록)
- 기준선 비교용 스크래치 체크아웃 `/private/tmp/claude-501/-Users-yoonhwan-Project-Agent-BYZ-Work-BYZ-Agents--worktrees-harness-r458-news-magazine-stall-recovery-and-te/44a1d545-3987-433e-9daf-7438ffd39990/scratchpad/base`(팩 d56b9c0e detached) — 정리 명령이 파괴 차단 훅에 막혀 남음(우회 0). 정리 = master 손 또는 scratch sweep.
- 세션 상태 스냅샷 낡음(`235627-c2195e7f.json` 10-16) ERROR 로그는 뉴스 발행을 막지 않음(절에 «갱신 안 됨» 표시) · 스냅샷 생성기 정지는 별도 카드 후보.
