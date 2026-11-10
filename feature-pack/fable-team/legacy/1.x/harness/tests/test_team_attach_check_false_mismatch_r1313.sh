#!/usr/bin/env bash
# R1313 — ft-team-attach --check 의 거짓 어긋남 3갈래를 잡는다.
#   S3 _cards = 명부 규칙(루트/.worktrees/<_cards_wt>/<_cards>) · S3 _label = «비어 있지 않음» 만 · S6 표 = 틱이 실제 읽는 LIVE_BIN 쪽.
#   격리 FT_ROOT 샌드박스 · 실제 명부·design·LIVE_BIN 무접촉 · press 0(단위 시험만).
set -uo pipefail
export LC_ALL=C
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${FT_ATTACH_BIN:-$HERE/../bin}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/root"; HARNESS_WT="$ROOT/.worktrees/harness-ops"
fail=0
ok() { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
sha() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; }
run() { out="$(bash "$BIN/ft-team-attach.sh" "$@" 2>&1)"; rc=$?; }

mkdir -p "$HARNESS_WT/design/harness/indices" "$ROOT/design/teams/zzsandbox/indices" \
  "$ROOT/design/teams/zzlive/indices" "$ROOT/.fable-team/bin" "$ROOT/.fable-team/state/harness-tick" \
  "$ROOT/.fable-team/state/zzlive-tick" \
  "$ROOT/LaunchAgents" "$ROOT/livebin"
cat > "$ROOT/design/TEAMS.md" <<'EOF'
| 팀 | 폴더 | 오케 | 상태 |
|---|---|---|---|
| harness | `$FT_HARNESS_ROOT/design/teams/harness/` | byz-harness-master#150 | 현역 |
| zzsandbox | `design/teams/zzsandbox/` | x | 현역 |
| zzlive | `design/teams/zzlive/` | x | 현역 |
EOF
cat > "$ROOT/design/TEAMSET.md" <<'EOF'
## 표 2 — 팀별 덮어쓰기
| 팀 | 나노 상한 | tester | arch 상시 |
|---|---|---|---|
| harness | 18 | 0 | 상시 |
| zzsandbox | 3 | 0 | 상시 |
| zzlive | 3 | 0 | 상시 |
EOF
printf '09:30 헤드라인 없음 · harness · 좌석 0\n' > "$ROOT/.fable-team/state/harness-tick/HEADLINE.md"
printf '09:30 헤드라인 없음 · zzlive · 좌석 0\n' > "$ROOT/.fable-team/state/zzlive-tick/HEADLINE.md"
printf 'harness\t.\torigin/main\tdesign/harness/indices\n' > "$ROOT/.fable-team/state/directive-roots.tsv"
seat() {  # seat <팀> <_label> <_cards> <_cards_wt>
  printf '{"_label":"%s","_master":"byz-%s-master-claude#150","_cards":"%s","_cards_wt":"%s","_doc":"r1313 test"}\n' \
    "$2" "$1" "$3" "$4" > "$ROOT/.fable-team/seats-$1.json"
}
seat harness harness design/harness/indices harness-ops
seat zzlive zzlive design/teams/zzlive/indices ""
# 틱 표(샌드박스 · 쓰기 길) — zzlive 행은 «LIVE_BIN 쪽 표에만» 둔다(실제 h5819 사건 꼴)
printf '# team-tick-env.tsv\nharness\tseats-harness.json\t/tmp/s\t/tmp/p\t/tmp/t\tOFF\tON=1\n' > "$ROOT/.fable-team/bin/team-tick-env.tsv"
printf '# LIVE_BIN 쪽 표 — 이 파일은 건드리지 않는다\nzzlive\tseats-zzlive.json\t/tmp/s2\t/tmp/p2\t/tmp/t2\tOFF\tON=1\n' > "$ROOT/livebin/team-tick-env.tsv"
printf '%s\n' "$ROOT/livebin" > "$ROOT/.fable-team/LIVE_BIN"
printf 'plist\n' > "$ROOT/LaunchAgents/com.byz.ft-tick-harness.plist"
printf 'plist\n' > "$ROOT/LaunchAgents/com.byz.ft-tick-zzlive.plist"
printf 'com.byz.ft-tick-harness\ncom.byz.ft-tick-zzlive\n' > "$TMP/launchctl.state"
cat > "$TMP/launchctl" <<'EOF'
#!/bin/sh
case "$1" in
  bootstrap) basename "$3" .plist >> "$LC_STATE"; exit 0;;
  bootout) exit 0;;
  list) while IFS= read -r l; do [ -n "$l" ] && echo "0 0 $l"; done < "$LC_STATE"; exit 0;;
  print) exit 0;;
esac
exit 1
EOF
chmod +x "$TMP/launchctl"
git -C "$ROOT" init -q -b main
git -C "$ROOT" -c user.name=t -c user.email=t@t add design
git -C "$ROOT" -c user.name=t -c user.email=t@t commit -q -m seed
printf '#!/bin/sh\nexit 0\n' > "$ROOT/.fable-team/bin/ft-tick.sh"
printf '#!/bin/sh\necho IDLE\n' > "$ROOT/.fable-team/bin/ft-seat-status.sh"
chmod +x "$ROOT/.fable-team/bin/ft-tick.sh" "$ROOT/.fable-team/bin/ft-seat-status.sh"

export FT_ROOT="$ROOT" FT_TEAMS_MD="$ROOT/design/TEAMS.md" FT_TEAMSET_MD="$ROOT/design/TEAMSET.md"
export FT_TEAM_ATTACH_SANDBOX=1 FT_HARNESS_ROOT="$HARNESS_WT"
export FT_TICK_TEAM_TSV="$ROOT/.fable-team/bin/team-tick-env.tsv"
export FT_TICK_PLIST_DIR="$ROOT/LaunchAgents" FT_TICK_LAUNCHCTL="$TMP/launchctl" LC_STATE="$TMP/launchctl.state"

# R1 — 팀 폴더가 $FT_HARNESS_ROOT 안(실제 h5819 꼴) · _cards 는 _cards_wt 폴더 기준 → S3 OK
run harness --check
{ [ "$rc" = 0 ] && [[ "$out" == *"S3 OK"* ]] && [[ "$out" != *"S3 어긋남"* ]]; } \
  && ok "R1 루트 안 FT_HARNESS_ROOT + _cards_wt 카드 폴더 → S3 OK" || bad "R1 rc=$rc out=$out"

# R1b — --apply 가 만든 새 명부(_master "")도 S3 OK
run --apply zzsandbox
apply_rc="$rc"
run zzsandbox --check
{ [ "$apply_rc" = 0 ] && [ "$rc" = 0 ] && [[ "$out" == *"S3 OK"* ]] && grep -q '"_master": ""' "$ROOT/.fable-team/seats-zzsandbox.json"; } \
  && ok "R1b apply 가 만든 _master 빈 명부 → S3 OK" || bad "R1b apply=$apply_rc rc=$rc out=$out"

# R2 — _cards 가 없는 폴더면 진짜 어긋남은 계속 잡는다
seat harness harness design/harness/nope harness-ops
run harness --check
{ [ "$rc" = 1 ] && [[ "$out" == *"S3 어긋남 폴더 없음"* ]]; } \
  && ok "R2 카드 폴더 없음 → S3 어긋남" || bad "R2 rc=$rc out=$out"
seat harness harness design/harness/indices harness-ops

# R3 — 표시 이름(m.lecture 꼴)은 OK · 빈 _label 만 어긋남
seat harness m.lecture design/harness/indices harness-ops
run harness --check
{ [ "$rc" = 0 ] && [[ "$out" == *"S3 OK"* ]]; } && ok "R3 표시 이름 m.lecture → S3 OK" || bad "R3 rc=$rc out=$out"
seat harness "" design/harness/indices harness-ops
run harness --check
{ [ "$rc" = 1 ] && [[ "$out" == *"S3 어긋남 _label"* ]]; } && ok "R3 빈 _label → S3 어긋남" || bad "R3b rc=$rc out=$out"
seat harness harness design/harness/indices harness-ops

# R4 — S6 = 틱이 실제 읽는 표. a) FT_TICK_TEAM_TSV 표 b) env 없이 LIVE_BIN 표(팀 행은 그쪽에만 있다) → 둘 다 전용 틱 OK
run harness --check
{ [ "$rc" = 0 ] && [[ "$out" == *"S6 전용 틱 OK"* ]]; } && ok "R4 S6 = 검사 전용 표(FT_TICK_TEAM_TSV) + plist + launchctl" || bad "R4a rc=$rc out=$out"
unset FT_TICK_TEAM_TSV
run zzlive --check
{ [ "$rc" = 0 ] && [[ "$out" == *"S6 전용 틱 OK"* ]] && [[ "$out" != *"S6 TSV·plist"* ]]; } \
  && ok "R4 env 없이 LIVE_BIN 표만 있을 때도 S6 OK" || bad "R4b rc=$rc out=$out"

# R5 — FT_TICK_TEAM_TSV 없음 + LIVE_BIN 파일 없음 → 판정 불가(unknown 1 · rc3) · 쓰기 0
tsv_before="$(sha "$ROOT/.fable-team/bin/team-tick-env.tsv")"; seats_before="$(sha "$ROOT/.fable-team/seats-harness.json")"
mv "$ROOT/.fable-team/LIVE_BIN" "$TMP/LIVE_BIN.off"
run harness --check
{ [ "$rc" = 3 ] && [[ "$out" == *"S6 판정 불가(LIVE_BIN 없음)"* ]] && [[ "$out" == *"mismatch=0 unknown=1"* ]] \
  && [ "$(sha "$ROOT/.fable-team/bin/team-tick-env.tsv")" = "$tsv_before" ] \
  && [ "$(sha "$ROOT/.fable-team/seats-harness.json")" = "$seats_before" ]; } \
  && ok "R5 LIVE_BIN 없음 → S6 판정 불가 · unknown=1 · rc3 · 쓰기 0" || bad "R5 rc=$rc out=$out"
mv "$TMP/LIVE_BIN.off" "$ROOT/.fable-team/LIVE_BIN"
export FT_TICK_TEAM_TSV="$ROOT/.fable-team/bin/team-tick-env.tsv"

# R6 — FT_HARNESS_ROOT 없음 → 그 팀만 판정 불가 1줄 · 다른 팀 줄은 그대로 · rc3
unset FT_HARNESS_ROOT
run --all --check
{ [ "$rc" = 3 ] && [[ "$out" == *"harness 판정 불가("* ]] && [[ "$out" == *"FT_HARNESS_ROOT 없음"* ]] \
  && [ "$(printf '%s\n' "$out" | grep -c '^zzsandbox S2')" = 1 ]; } \
  && ok "R6 팀별 판정 불가 · 다른 팀 계속 · rc3" || bad "R6 rc=$rc out=$out"
export FT_HARNESS_ROOT="$HARNESS_WT"

# R7 — 쓰기 길 무변경: --own-tick 은 팀 틱 표를 «읽기만» 한다(r1314 · 행은 팩 PR) — 두 표 바이트 그대로 · plist 만 새로 쓴다
printf 'zzlive\tseats-zzlive.json\t/tmp/ft-tick-state-zzlive\t/tmp/ft-tick-zzlive.pid\t/tmp/ft-tick-zzlive-\tFT_TICK_MAGAZINE\tFT_TICK_FIRE_V2=1\n' >> "$ROOT/.fable-team/bin/team-tick-env.tsv"
live_before="$(sha "$ROOT/livebin/team-tick-env.tsv")"; sandbox_before="$(sha "$ROOT/.fable-team/bin/team-tick-env.tsv")"
run --apply zzlive --own-tick
{ [ "$rc" = 0 ] && [ "$(sha "$ROOT/livebin/team-tick-env.tsv")" = "$live_before" ] \
  && [ "$(sha "$ROOT/.fable-team/bin/team-tick-env.tsv")" = "$sandbox_before" ] \
  && grep -q 'com.byz.ft-tick-zzlive' "$ROOT/LaunchAgents/com.byz.ft-tick-zzlive.plist"; } \
  && ok "R7 쓰기 길 무변경(두 표 바이트 같음 · plist 만 새로 씀)" || bad "R7 rc=$rc out=$out"

# R8 — 회귀 기대 유지: 명부 부품이 빠지고 틱 표가 있으면 rc=1(판정 불가 3 이 아니다)
R8="$TMP/r8"; mkdir -p "$R8/design/teams/zztest/indices" "$R8/.fable-team/bin"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| zztest | `design/teams/zztest/` | x | 현역 |\n' > "$R8/design/TEAMS.md"
printf '## 표 2 — 팀별 덮어쓰기\n| 팀 | 나노 상한 | tester | arch 상시 |\n|---|---|---|---|\n' > "$R8/design/TEAMSET.md"
printf '# team-tick-env.tsv\n' > "$R8/.fable-team/bin/team-tick-env.tsv"
out="$(env -u FT_HARNESS_ROOT FT_ROOT="$R8" FT_TEAMS_MD="$R8/design/TEAMS.md" FT_TEAMSET_MD="$R8/design/TEAMSET.md" \
  FT_TEAM_ATTACH_SANDBOX=1 FT_TICK_TEAM_TSV="$R8/.fable-team/bin/team-tick-env.tsv" \
  FT_TICK_PLIST_DIR="$R8/.fable-team/state/launchd" FT_TICK_LAUNCHCTL="$TMP/launchctl" LC_STATE="$TMP/launchctl.state" \
  bash "$BIN/ft-team-attach.sh" --all --check 2>&1)"; rc=$?
{ [ "$rc" = 1 ] && [[ "$out" == *"S2 빠짐"* ]] && [[ "$out" == *"S6 전용 틱 없음"* ]]; } \
  && ok "R8 표가 있으면 명부 부품 누락 = rc1(기대값 그대로)" || bad "R8 rc=$rc out=$out"

echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit "$fail"
