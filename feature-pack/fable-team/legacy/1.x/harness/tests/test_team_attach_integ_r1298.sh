#!/usr/bin/env bash
# R1298 integration — team tick 왕복(R16), TEAMSET 게시 단계(R18).
set -uo pipefail
export LC_ALL=C
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok() { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

ROOT="$TMP/tick-root"; mkdir -p "$ROOT/design/teams/zztest/indices" "$ROOT/.fable-team/bin" "$ROOT/.fable-team/state" "$ROOT/LaunchAgents"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| zztest | design/teams/zztest/ | x | 현역 |\n' > "$ROOT/design/TEAMS.md"
cat > "$ROOT/design/TEAMSET.md" <<'EOF'
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
| planner | 3 | 0 | 상시 |
EOF
git -C "$ROOT" init -q -b main; git -C "$ROOT" -c user.name=t -c user.email=t@t add design
git -C "$ROOT" -c user.name=t -c user.email=t@t commit -q -m seed
printf '#!/bin/sh\nexit 0\n' > "$ROOT/.fable-team/bin/ft-tick.sh"
printf '#!/bin/sh\necho IDLE\n' > "$ROOT/.fable-team/bin/ft-seat-status.sh"
chmod +x "$ROOT/.fable-team/bin/ft-tick.sh" "$ROOT/.fable-team/bin/ft-seat-status.sh"
cat > "$TMP/launchctl" <<'EOF'
#!/bin/sh
case "$1" in
  bootstrap) basename "$3" .plist >> "$LC_STATE"; exit 0;;
  bootout) label="$(basename "$2")"; sed "/$label/d" "$LC_STATE" > "$LC_STATE.tmp"; mv "$LC_STATE.tmp" "$LC_STATE"; exit 0;;
  list) while IFS= read -r label; do echo "0 0 $label"; done < "$LC_STATE"; exit 0;;
  print) label="$(basename "$2")"; grep -q "$label" "$LC_STATE"; exit $?;;
esac
exit 1
EOF
chmod +x "$TMP/launchctl"; : > "$TMP/launchctl.state"
export LC_STATE="$TMP/launchctl.state" FT_ROOT="$ROOT" FT_TEAMS_MD="$ROOT/design/TEAMS.md" FT_TEAMSET_MD="$ROOT/design/TEAMSET.md"
export FT_TEAM_ATTACH_SANDBOX=1 FT_TICK_TEAM_TSV="$ROOT/.fable-team/bin/team-tick-env.tsv"
export FT_TICK_PLIST_DIR="$ROOT/LaunchAgents" FT_TICK_LAUNCHCTL="$TMP/launchctl"
echo '# team-tick-env.tsv' > "$FT_TICK_TEAM_TSV"
# r1314: 팀 행은 팩 표(PR)에 미리 있다 — own-tick 은 표를 쓰지 않는다(표 쓰기 0)
printf 'zztest\tseats-zztest.json\t/tmp/ft-tick-state-zztest\t/tmp/ft-tick-zztest.pid\t/tmp/ft-tick-zztest-\tFT_TICK_MAGAZINE,FT_TICK_LAUNCHD\tFT_TICK_FIRE_V2=1\n' >> "$FT_TICK_TEAM_TSV"
tsv_before="$(shasum -a 256 "$FT_TICK_TEAM_TSV" | cut -d' ' -f1)"
out="$(bash "$BIN/ft-team-attach.sh" --apply zztest --own-tick 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && [ -f "$ROOT/LaunchAgents/com.byz.ft-tick-zztest.plist" ] && grep -q '^zztest[[:space:]]' "$FT_TICK_TEAM_TSV" && grep -q 'com.byz.ft-tick-zztest' "$LC_STATE" && [ "$(shasum -a 256 "$FT_TICK_TEAM_TSV" | cut -d' ' -f1)" = "$tsv_before" ]; } && ok "R16 attach가 plist·launchctl 을 설정(팀 틱 표는 읽기만 · 바이트 그대로)" || bad "R16 apply rc=$rc $out"
out="$(bash "$BIN/ft-team-attach.sh" zztest --check 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$out" == *"S6 전용 틱 OK"* ]]; } && ok "R16 S6 세 쌍 OK" || bad "R16 check rc=$rc $out"
sed -i '' 's/현역/휴면/' "$ROOT/design/TEAMS.md"
out="$(bash "$BIN/ft-team-attach.sh" zztest --detach 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && [ ! -f "$ROOT/LaunchAgents/com.byz.ft-tick-zztest.plist" ] && [ ! -s "$LC_STATE" ]; } && ok "R16 detach가 서비스·plist를 분리" || bad "R16 detach rc=$rc $out"
snapshot="$(find "$ROOT/.fable-team/state/team-attach" -name manifest.json -print -quit)"
out="$(bash "$BIN/ft-team-attach.sh" --revert "$snapshot" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ -f "$ROOT/LaunchAgents/com.byz.ft-tick-zztest.plist" ] && grep -q 'com.byz.ft-tick-zztest' "$LC_STATE" \
  && ok "R16 revert가 plist·launchctl 상태를 복원" || bad "R16 revert rc=$rc $out"

ORIGIN="$TMP/origin.git"; SEED="$TMP/seed"; CLONE="$TMP/clone"; FAKE="$TMP/fakebin"
git init -q --bare "$ORIGIN"; git init -q -b main "$SEED"; mkdir -p "$SEED/design/teams/zztest"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| zztest | design/teams/zztest/ | x | 현역 |\n' > "$SEED/design/TEAMS.md"
cat > "$SEED/design/TEAMSET.md" <<'EOF'
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
| planner | 3 | 0 | 상시 |
EOF
git -C "$SEED" -c user.name=t -c user.email=t@t add design
git -C "$SEED" -c user.name=t -c user.email=t@t commit -q -m seed
git -C "$SEED" remote add origin "$ORIGIN"; git -C "$SEED" push -q -u origin main
git clone -q -b main "$ORIGIN" "$CLONE"; mkdir -p "$FAKE"
printf '#!/bin/sh\n[ "$1" = list-sessions ] && exit 0\nexit 1\n' > "$FAKE/tmux"; chmod +x "$FAKE/tmux"
export FT_ROOT="$CLONE" FT_TEAMS_MD="$CLONE/design/TEAMS.md" FT_TEAMSET_MD="$CLONE/design/TEAMSET.md"
export FT_TEAM_ATTACH_SANDBOX=1 PATH="$FAKE:$PATH"
out="$(bash "$BIN/ft-team-attach.sh" zztest --apply 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && grep -q '| zztest | 3 | 0 | 상시 |' "$CLONE/design/TEAMSET.md"; } || { bad "R18 apply rc=$rc $out"; }
cap() { python3 "$BIN/ft_teamset.py" cap --root "$CLONE" --md gitref:origin/main:design/TEAMSET.md --prefix byz-zztest-nano- 2>&1; }
out="$(cap)"; rc=$?; [ "$rc" = 3 ] && [[ "$out" == *"TEAMSET 행 없음"* ]] && ok "R18 파일 행만 있어 cap rc3" || bad "R18 file rc=$rc $out"
git -C "$CLONE" -c user.name=t -c user.email=t@t add design/TEAMSET.md
git -C "$CLONE" -c user.name=t -c user.email=t@t commit -q -m local
out="$(cap)"; rc=$?; [ "$rc" = 3 ] && ok "R18 로컬 커밋만 있어 cap rc3" || bad "R18 commit rc=$rc $out"
git -C "$CLONE" push -q origin main; git -C "$CLONE" fetch -q origin
out="$(cap)"; rc=$?; [ "$rc" = 0 ] && [[ "$out" == CAP* ]] && ok "R18 push·fetch 뒤 cap 통과" || bad "R18 fetch rc=$rc $out"

echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit "$fail"

