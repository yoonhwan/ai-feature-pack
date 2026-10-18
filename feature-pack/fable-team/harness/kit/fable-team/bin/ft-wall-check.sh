#!/usr/bin/env bash
# ★런타임 사본은 git 추적 밖이다(작동 원리 — README 참조). 추적 백업: harness/comm/ · 드리프트 확인: harness/comm/check-drift.sh
# 작업 전 벽 읽음 체크 — 원장 sha != 현재 벽 sha 면 재읽기 요구
set -euo pipefail
SEAT="${1:?seat}"
# ★파이프 금지(impl-cc#5 #350)★: 이 출력을 | head 등에 물리면 exit 가 파이프 끝단 것(0)으로 읽혀 REREAD-REQUIRED 가 통과로 오독된다. 직접 호출 + $? 확인.
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
# R383: 벽 문서 = v65 팀 폴더(ROOT 의 design/TEAMS.md · 팀 이름 글자 0) — 못 풀면 set -e 로 ERROR 종료(옛 경로 후퇴 0)
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ft-team-lib.sh"
WALL="$(FT_REPO_ROOT="$ROOT" ft_team_rel v65)DIRECTIVE-v65-wall.md"
LEDGER="$ROOT/.fable-team/state/wall-read-ledger.json"
SHA="$(git -C "$ROOT" log -1 --format=%h -- "$WALL" 2>/dev/null || echo unknown)"
python3 - "$LEDGER" "$SEAT" "$SHA" <<'PY'
import json,sys,os
led,seat,sha=sys.argv[1:4]
d=json.load(open(led)) if os.path.exists(led) else {}
e=d.get(seat)
if not e: print(f"REREAD-REQUIRED seat={seat} (원장 부재 — 증류/승계/신규) 현재벽 sha={sha}"); sys.exit(3)
if e.get("wall_sha")!=sha: print(f"REREAD-REQUIRED seat={seat} 원장 sha={e.get('wall_sha')} != 현재 {sha} (벽 갱신됨)"); sys.exit(3)
print(f"WALL-OK seat={seat} sha={sha} read_at={e.get('read_at')}")
PY
