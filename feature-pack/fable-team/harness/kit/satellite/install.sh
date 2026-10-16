#!/usr/bin/env bash
# install.sh [ROOT] — 위성팀(room·lecture) 명부 틀 2 + env 2 를 <ROOT>/.fable-team/ 으로 깐다 (R252 · 판정 1942·1943 · master 가 랜딩 뒤 집행).
#   seats-<팀>.json → .fable-team/seats-<팀>.json   (★«없을 때만» — 있으면 `SKIP exists <파일>` · 좌석 행이 생긴 라이브 명부 보존★)
#                      `_hil_route` 는 <ROOT>/.fable-team/seats-planner.json 의 `_master`(현역 planner)로 채운다 — 없으면 ERROR · 명부 쓰기 0
#   <팀>-env.sh     → .fable-team/bin-<팀>/<팀>-env.sh  (이미 있으면 .bak-<ts> 로 옮긴 뒤 덮는다 · cmp 확인)
set -uo pipefail
SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-$(git -C "$SRC" rev-parse --path-format=absolute --git-common-dir | sed 's|/\.git$||')}"
[ -d "$ROOT" ] || { echo "REJECT ROOT 없음: $ROOT"; exit 1; }
TS="$(date +%Y%m%d%H%M%S)"; FB="$ROOT/.fable-team"; rc=0
for team in room lecture; do
  dst="$FB/seats-$team.json"
  if [ -f "$dst" ]; then echo "SKIP exists seats-$team.json"
  else
    hil="$(python3 -c 'import json,sys; v=json.load(open(sys.argv[1], encoding="utf-8")).get("_master"); print(v) if isinstance(v,str) and v else sys.exit(1)' "$FB/seats-planner.json" 2>/dev/null)" \
      || { echo "ERROR planner 명부 없음 또는 _master 비었음: $FB/seats-planner.json — seats-$team.json 쓰기 0"; rc=1; continue; }
    python3 - "$SRC/seats-$team.json" "$dst" "$hil" <<'PY' || { echo "ERROR seats-$team.json 쓰기 실패"; rc=1; continue; }
import sys
src = open(sys.argv[1], encoding="utf-8").read()
ph = "<설치 때 seats-planner.json _master 로 채움>"
assert ph in src, "틀에 _hil_route 자리표시자가 없다"
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(ph, sys.argv[3]))
PY
    echo "WROTE seats-$team.json _hil_route=$hil"
  fi
  mkdir -p "$FB/bin-$team" || { rc=1; continue; }
  e="$FB/bin-$team/$team-env.sh"
  [ -f "$e" ] && ! cmp -s "$SRC/$team-env.sh" "$e" && cp "$e" "$e.bak-$TS" && echo "BACKUP $e.bak-$TS"
  cp "$SRC/$team-env.sh" "$e" || { echo "REJECT cp 실패: $e"; rc=1; continue; }
  if cmp -s "$SRC/$team-env.sh" "$e"; then echo "CMP OK  bin-$team/$team-env.sh"; else echo "CMP DIFF bin-$team/$team-env.sh"; rc=1; fi
done
exit $rc
