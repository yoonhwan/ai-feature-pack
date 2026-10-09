#!/usr/bin/env bash
# install.sh [ROOT] — graphics 팀 스테이징 사본 3개를 <ROOT>/.fable-team/ 으로 cp 한다 (판정 649 · 690 · master 가 랜딩 뒤 집행).
#   seats-graphics.json → .fable-team/seats-graphics.json   (★루트에 «없을 때만» 복사 — 있으면 라이브 명부 보존, _doc·_master 는 손으로★)
#   graphics-env.sh · goal-lines-graphics.txt → .fable-team/bin-graphics/
# env·goal-lines 는 이미 있으면 .bak-<ts> 로 옮긴 뒤 덮는다. 끝에 cmp 결과를 찍고, 하나라도 다르면 exit 1.
set -uo pipefail
SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-$(git -C "$SRC" rev-parse --path-format=absolute --git-common-dir | sed 's|/\.git$||')}"
[ -d "$ROOT" ] || { echo "REJECT ROOT 없음: $ROOT"; exit 1; }
TS="$(date +%Y%m%d%H%M%S)"
mkdir -p "$ROOT/.fable-team/bin-graphics" || exit 1
rc=0
while IFS='|' read -r name dest mode; do
  src="$SRC/$name"; dst="$ROOT/.fable-team/$dest"
  [ -f "$src" ] || { echo "REJECT 스테이징 사본 없음: $src"; rc=1; continue; }
  if [ "$mode" = once ] && [ -f "$dst" ]; then
    echo "SKIP $dest (라이브 명부 보존 — _doc·_master 는 손으로)"; continue
  fi
  [ -f "$dst" ] && ! cmp -s "$src" "$dst" && cp "$dst" "$dst.bak-$TS" && echo "BACKUP $dst.bak-$TS"
  cp "$src" "$dst" || { echo "REJECT cp 실패: $dst"; rc=1; continue; }
  if cmp -s "$src" "$dst"; then echo "CMP OK  $dest"; else echo "CMP DIFF $dest"; rc=1; fi
done <<'LIST'
seats-graphics.json|seats-graphics.json|once
graphics-env.sh|bin-graphics/graphics-env.sh|
goal-lines-graphics.txt|bin-graphics/goal-lines-graphics.txt|
LIST
exit $rc
