#!/usr/bin/env bash
# ft-team-rename.sh (--plan|--apply) <옛> <새>  |  --verify <새>  |  --revert <스냅샷.json>   (r468 · 팀 «이름» 바꾸기 — 명단·폴더·명부·env·저장 참조 한 번)
#   --plan   표만(쓰기 0): 명단 2행 · 팀 폴더 파일·본문 치환 예상 · 명부 칸 4·행 수 · 저장 참조 7종 before · env 폴더 · 점유(pane cwd·lsof) · 쌍둥이 · 끝줄 PLAN-END blockers=<n>
#   --apply  선검사(깨끗한 트리 · blockers 0 · 새 이름 명단에 없음 · 옛 꼴/쌍둥이면 REJECT 먼저 ft-team-move) → 스냅샷(.fable-team/state/team-rename/<ts>-<옛>-<새>/)
#            → git mv design/teams/<옛> design/teams/<새> + TEAMS/TEAMSET 행 + 본문 치환(`design/teams/<옛>/` · `byz-<옛>-` 둘뿐) + TEAMS 각주 1줄 → 한 커밋
#            → 명부 seats-<옛>.json → seats-<새>.json(.bak-rename-<ts> · _name/_label/경로 칸/_doc · _renamed_from · 행 이름 불변)
#            → nano-card-base·worktree-info·baton·추가 파일(FT_TEAM_MOVE_EXTRA) → env bin-<옛>/ → bin-<새>/(파일 이름·값) → AFTER 줄
#            명단에 <새> 만 있고 명부 _renamed_from=<옛> 이면 같은 명령 = RESYNC(받은 워크트리의 _move_pending 만 · git 변경 0)
#   --verify 읽기 전용: 명단·폴더·map-lint·명부 index·카드 기준선·팀 집합·옛 자리 잔존 = ERR · 잔여 «<옛>» 글자 = WARN(각주·옛 좌석 이름 제외) → VERIFY ERR=<n> WARN=<m>
#   --revert 만든 파일 지움 → 저장 파일 바이트 복원(sha256) → git revert(이동 도구 revert 그대로)
#   좌석 교대·워크트리·가지·제품 코드는 대상 밖(가지 삭제 0 · 명부 옛 행 삭제 0). exit 0 = 완료 · 1 = REJECT/ERROR · 2 = usage
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
for f in ft_team_rename.py ft_team_move.py ft_team_move_apply.py ft-team-lib.sh; do
  [ -f "$HERE/$f" ] || { echo "REJECT 이름 바꾸기 도구 구성 파일 없음: $HERE/$f"; exit 1; }
done
exec python3 -I "$HERE/ft_team_rename.py" "$@"
