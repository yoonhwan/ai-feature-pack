#!/usr/bin/env bash
# ★런타임 사본은 git 추적 밖이다(작동 원리 — README 참조). 추적 백업: tools/comm-canonical/ · 드리프트 확인: tools/comm-canonical/check-drift.sh
# 벽 읽음 기록 — 좌석이 벽 읽고 원칙 1개 인용해야 기록(집행 증거)
set -euo pipefail
SEAT="${1:?seat}"; CITED="${2:?cite one wall principle phrase}"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
# R383: 벽 문서 = v65 팀 폴더(ROOT 의 design/TEAMS.md · 팀 이름 글자 0) — 못 풀면 set -e 로 ERROR 종료(옛 경로 후퇴 0)
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ft-team-lib.sh"
WALL="$(FT_REPO_ROOT="$ROOT" ft_team_rel v65)DIRECTIVE-v65-wall.md"
LEDGER="$ROOT/.fable-team/state/wall-read-ledger.json"
SHA="$(git -C "$ROOT" log -1 --format=%h -- "$WALL" 2>/dev/null || echo unknown)"
# 인용 검증 — 벽에 실제 있는 문구인가(집행)
grep -qF "$CITED" "$ROOT/$WALL" || { echo "REJECT: cited phrase not in wall (열지 않았다) — $CITED"; exit 3; }
python3 - "$LEDGER" "$SEAT" "$SHA" "$CITED" <<'PY'
import json,sys,os,datetime
led,seat,sha,cited=sys.argv[1:5]
d=json.load(open(led)) if os.path.exists(led) else {}
d[seat]={"wall_sha":sha,"read_at":datetime.datetime.now().isoformat(timespec="seconds"),"cited":cited[:80]}
os.makedirs(os.path.dirname(led),exist_ok=True); json.dump(d,open(led,"w"),ensure_ascii=False,indent=1)
print(f"WALL-READ seat={seat} sha={sha} OK")
PY
