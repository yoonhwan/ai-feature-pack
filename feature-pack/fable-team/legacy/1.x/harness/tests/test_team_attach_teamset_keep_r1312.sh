#!/usr/bin/env bash
# R1312 — ft-team-attach --apply 는 design/TEAMSET.md 의 «있는» 팀 행을 덮지 않는다(없는 행만 추가 · 있는 파일 내용은 안 바꿈).
# 임시 FT_ROOT 샌드박스 · 실제 명부·design 무접촉.
set -uo pipefail
export LC_ALL=C
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/root"
mkdir -p "$ROOT/design/teams/harness/indices" "$ROOT/design/teams/ops/indices" "$ROOT/design/teams/zztest/indices" "$ROOT/.fable-team/comm"
fail=0
ok() { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
mtime() { python3 -c 'import os,sys;print(os.stat(sys.argv[1]).st_mtime_ns)' "$1"; }

cat > "$ROOT/design/TEAMS.md" <<'EOF'
| 팀 | 폴더 | 오케 | 상태 |
|---|---|---|---|
| harness | `design/teams/harness/` | byz-harness-master#1 | 현역 |
| ops | `design/teams/ops/` | byz-ops-master#1 | 현역 |
EOF
cat > "$ROOT/design/TEAMSET.md" <<'EOF'
## 표 2 — 팀별 덮어쓰기
| 팀 | 나노 상한 | tester | arch 상시 |
|---|---|---|---|
| harness | 18 | 0 | 상시 |
| ops | 5 | 2 | 상시 |
EOF
cp "$ROOT/design/TEAMSET.md" "$TMP/teamset.orig"
export FT_ROOT="$ROOT" FT_TEAMS_MD="$ROOT/design/TEAMS.md" FT_TEAMSET_MD="$ROOT/design/TEAMSET.md"
export FT_TEAM_ATTACH_SANDBOX=1

# R1 — 있는 행 2개(harness 18·0·상시 · ops 5·2·상시) → 바이트 그대로 · KEEP 2줄 · 파일 쓰기 0
before_mtime="$(mtime "$ROOT/design/TEAMSET.md")"
out="$(bash "$BIN/ft-team-attach.sh" --all --apply 2>&1)"; rc=$?
keep="$(printf '%s\n' "$out" | grep -c '^KEEP TEAMSET ')"
after_mtime="$(mtime "$ROOT/design/TEAMSET.md")"
{ [ "$rc" = 0 ] && [ "$keep" = 2 ] && cmp -s "$ROOT/design/TEAMSET.md" "$TMP/teamset.orig" && [ "$before_mtime" = "$after_mtime" ] \
  && [[ "$out" == *"KEEP TEAMSET harness 기존 행 유지(18, 0, 상시)"* ]] && [[ "$out" == *"KEEP TEAMSET ops 기존 행 유지(5, 2, 상시)"* ]]; } \
  && ok "R1 있는 행 유지 · KEEP=$keep · 쓰기 0" || bad "R1 rc=$rc KEEP=$keep write=$([ "$before_mtime" = "$after_mtime" ] && echo 0 || echo 1) out=$out"

# R2 — 없는 팀(zztest) → 행 1 추가 · 있는 행 2개는 그대로
printf '| zztest | `design/teams/zztest/` | x | 현역 |\n' >> "$ROOT/design/TEAMS.md"
out="$(bash "$BIN/ft-team-attach.sh" --apply zztest 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && grep -q '^| zztest | 3 | 0 | 상시 |$' "$ROOT/design/TEAMSET.md" \
  && grep -q '^| harness | 18 | 0 | 상시 |$' "$ROOT/design/TEAMSET.md" && grep -q '^| ops | 5 | 2 | 상시 |$' "$ROOT/design/TEAMSET.md" \
  && [ "$(printf '%s\n' "$out" | grep -c '^KEEP TEAMSET ')" = 0 ]; } \
  && ok "R2 없는 행만 추가(기존 행 무접촉)" || bad "R2 rc=$rc out=$out"

# R3 — --detach 는 지금 그대로: 옛 행을 manifest 에 기록하고 표 2 행을 «휴면» 으로 바꾼다(회귀) · revert 가 원복
sed -i '' 's/^| zztest | `design\/teams\/zztest\/` | x | 현역 |$/| zztest | `design\/teams\/zztest\/` | x | 휴면 |/' "$ROOT/design/TEAMS.md"
out="$(bash "$BIN/ft-team-attach.sh" zztest --detach 2>&1)"; rc=$?
snapshot="$(find "$ROOT/.fable-team/state/team-attach" -name manifest.json -print -quit 2>/dev/null)"
{ [ "$rc" = 0 ] && [ -n "$snapshot" ] && grep -q '^| zztest | 0 | 0 | 휴면 ' "$ROOT/design/TEAMSET.md" \
  && python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));sys.exit(0 if d.get("teamset_before_sha") and d.get("teamset_after_sha") else 1)' "$snapshot"; } \
  && ok "R3 detach 옛 행 기록·휴면 전환(회귀)" || bad "R3 rc=$rc snapshot=$snapshot out=$out"
out="$(bash "$BIN/ft-team-attach.sh" --revert "$snapshot" 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && grep -q '^| zztest | 3 | 0 | 상시 |$' "$ROOT/design/TEAMSET.md"; } \
  && ok "R3 revert 가 표 2 원복" || bad "R3 revert rc=$rc out=$out"

echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit "$fail"
