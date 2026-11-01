#!/usr/bin/env bash
# R1298 unit shell — 격리 루트에서 누락을 찾고 하루 한 번 planner 알림을 보낸다.
set -uo pipefail
export LC_ALL=C
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/root"; mkdir -p "$ROOT/design/teams/zztest/indices" "$ROOT/.fable-team/comm"
cat > "$ROOT/design/TEAMS.md" <<'EOF'
| 팀 | 폴더 | 오케 | 상태 |
|---|---|---|---|
| zztest | `design/teams/zztest/` | x | 현역 |
EOF
cat > "$ROOT/design/TEAMSET.md" <<'EOF'
## 표 2 — 팀별 덮어쓰기
| 팀 | 나노 상한 | tester | arch 상시 |
|---|---|---|---|
EOF
cat > "$ROOT/.fable-team/comm/mbox.sh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$FT_ATTACH_SENT"
EOF
chmod +x "$ROOT/.fable-team/comm/mbox.sh"
export FT_ROOT="$ROOT" FT_TEAMS_MD="$ROOT/design/TEAMS.md" FT_TEAMSET_MD="$ROOT/design/TEAMSET.md"
export FT_TEAM_ATTACH_SANDBOX=1 FT_ATTACH_SENT="$TMP/sent.log" FT_MBOX_SH="$ROOT/.fable-team/comm/mbox.sh"
fail=0
out="$(bash "$BIN/ft-team-attach.sh" --all --check --notify byz-planner-master#1 2>&1)"; rc=$?
[ "$rc" = 1 ] && [[ "$out" == *"S2 빠짐"* ]] && [[ "$out" == *"S3 빠짐"* ]] && [[ "$out" == *"S5 빠짐"* ]] || { echo "FAIL R1 rc=$rc $out"; fail=$((fail+1)); }
[ "$(wc -l < "$FT_ATTACH_SENT" | tr -d ' ')" = 1 ] || { echo "FAIL R9 첫 알림"; fail=$((fail+1)); }
out="$(bash "$BIN/ft-team-attach.sh" --all --check --notify byz-planner-master#1 2>&1)"; rc=$?
[ "$rc" = 1 ] && [ "$(wc -l < "$FT_ATTACH_SENT" | tr -d ' ')" = 1 ] || { echo "FAIL R9 하루 중복 알림"; fail=$((fail+1)); }
echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit "$fail"
