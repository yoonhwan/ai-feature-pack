#!/usr/bin/env bash
# ft-team-move.sh (--plan|--apply|--verify) (<팀>|--all) [--sync-worktrees]  |  --revert <스냅샷.json>   (R382 · 팀 폴더 design/<팀>/ → design/teams/<팀>/)
#   --plan   표만(쓰기 0): 팀마다 저장 참조 7종 «before» 줄 · tmux pane cwd·lsof 점유 · 워크트리별 받음/미전환 · (r587) 코드·시험 옛 경로 = `BEFORE <팀> code-ref <n>` 줄 + blockers 에 셈 · 끝줄 PLAN-END blockers=<n>
#            (r447) 명단은 새 꼴인데 옛 폴더에 추적 파일이 남은 «쌍둥이 공존» 팀 = PLAN-TWIN 1줄 · --apply 가 옛 내용 우선 병합 이동(ft_team_move_twin.py) → TWIN-MERGED <팀> MOVED <N> OVERWROTE <M> DROPPED-SAME <K>
#   --apply  점유 0 확인 → 스냅샷(.fable-team/state/team-move/<ts>-<팀>/) → git mv + TEAMS.md·카드 본문·README 지도·.gitignore 한 커밋 → (--sync-worktrees 면 ft-head-sync --apply)
#            → 받은 워크트리 좌석만 명부 index/_tree 재작성 · 못 받은 곳은 `_move_pending` 표식 → nano-card-base·worktree-info·baton·추가 파일(FT_TEAM_MOVE_EXTRA) 재작성 · AFTER 줄
#   --verify 읽기 전용: TEAMS 폴더 칸 해석·map-lint·명부 index 실재·nano-card-base card_path 실재·코드·시험 옛 경로 ERR(r587)·잔여 옛 경로 WARN·TEAMS↔TEAMSET 팀 집합 (기록 archive·evidence·CLOSEOUT 은 셈 밖) → 끝줄 VERIFY ERR=<n> WARN=<m> (ERR>0 rc1)
#   (r899) --classify 읽기 전용: 남은 옛 경로를 LIVE-OK·LIVE-FIX·LIVE-HAND·ARCHIVE(tmux 세션 없음)·CODE-RUN·CODE-NOTE·CODE-RECORD·CODE-FIXTURE 로 가름 → 끝줄 CLASSIFY …
#            --cleanup-plan (<팀>|--all) --out <폴더> = plan.json·plan.tsv·plan.sh 만(실행 0) · plan.sh(master/오빠) → --cleanup-run(sha 고정·실행 시점 tmux 재확인·보관 = 지우기 0)
#            --cleanup-restore <archive.json> = 되살리기 · --verify 코드 칸: 실행 글자·허용 목록 밖 픽스처 = ERR · 주석·기록 = WARN · design/TEAM-MOVE-ALLOW.tsv(사유) 픽스처 = 셈 밖
#   --revert 스냅샷의 저장 참조 파일을 역순 바이트 복원(sha256 대조) → git revert 로 이동 커밋 되돌림
#   팀 폴더 해석은 ft-team-lib.sh 한 곳. env 는 ft_team_move.py 머리 참고. exit 0 = 완료 · 1 = REJECT/ERROR · 2 = usage · 3 = PARTIAL(--sync-worktrees 가 공통 마감 70초 안에 못 끝남 — 이동 커밋은 보존 · 저장 참조는 쓰기 전에 멈춤 · 스냅샷 pending_teams · 같은 팀 --apply 다시 = RESYNC)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
for f in ft_team_move.py ft_team_move_apply.py ft_team_move_twin.py ft_team_move_classify.py ft_team_move_cleanup.py ft-team-lib.sh; do
  [ -f "$HERE/$f" ] || { echo "REJECT 이동 도구 구성 파일 없음: $HERE/$f"; exit 1; }
done
exec python3 -I "$HERE/ft_team_move.py" "$@"
