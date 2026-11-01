#!/usr/bin/env bash
# R1298 TEAMSET custom fixture compatibility and active-roster cap gate.
set -uo pipefail
export LC_ALL=C
HERE="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/root"; MD="$TMP/TEAMSET.md"; FAKE="$TMP/fake"
mkdir -p "$ROOT/design" "$FAKE"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| alpha | design/teams/alpha/ | x | 현역 |\n| sleeping | design/teams/sleeping/ | x | 휴면 |\n' > "$ROOT/design/TEAMS.md"
cat > "$MD" <<'EOF'
## 표 1 — 역할 표준
| 역할 | 수 | 모델 | effort | 명부 키 | 승계 | 닫기 |
|---|---|---|---|---|---|---|
| master | 필수 1 | sonnet | high | _master | a | b |
| arch | 상시 | opus | high | _arch | a | b |
| nano | 상한 N | sonnet | high | - | a | b |
- 나노 상한 기본: 3
- 명부 공용 키: _name _doc _closed
## 표 2 — 팀별 덮어쓰기
| 팀 | 나노 상한 | tester | arch 상시 |
|---|---|---|---|
| harness | 4 | 0 | 상시 |
| sleeping | 2 | 0 | 상시 |
EOF
printf '#!/bin/sh\n[ "$1" = list-sessions ] && exit 0\nexit 1\n' > "$FAKE/tmux"; chmod +x "$FAKE/tmux"
cap() { PATH="$FAKE:$PATH" python3 "$BIN/ft_teamset.py" cap --root "$ROOT" --md "$MD" --prefix "$1" 2>&1; }
out="$(cap byz-harness-nano-)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == "CAP harness live=0 cap=4" ]] || { echo "FAIL custom fixture rc=$rc $out"; exit 1; }
out="$(cap byz-alpha-nano-)"; rc=$?
[ "$rc" = 3 ] && [[ "$out" == *"TEAMSET 행 없음"* ]] || { echo "FAIL active missing row rc=$rc $out"; exit 1; }
out="$(cap byz-sleeping-nano-)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == *"SKIP"* ]] || { echo "FAIL dormant row rc=$rc $out"; exit 1; }
echo "PASS custom table row · active row missing rc3 · dormant team SKIP"
