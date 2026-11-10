#!/usr/bin/env bash
# test_install_team_tick_live.sh — R150: install-team-tick-live.sh 를 격리 시험(임시 plist 폴더·가짜 launchctl).
#   설치 → 3키·경로·백업·재기동 / 재실행 멱등 / 되돌림 뒤 ProgramArguments 가 옛 경로(파일 실재) · 팀 사본 불변 / 라이브가 R150 판이 아니면 거부.
# 실제 launchctl·~/Library/LaunchAgents 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."
INSTALL="$REPO/harness/design/harness/staged-r150/install-team-tick-live.sh"
KIT="$REPO/harness/kit/fable-team/bin/ft-tick.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PB=/usr/libexec/PlistBuddy
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
pv() { "$PB" -c "Print :$2" "$TMP/plists/$1" 2>/dev/null; }

bash -n "$INSTALL" && ok "bash -n" || bad "bash -n"
mkdir -p "$TMP/plists" "$TMP/live"; cp "$KIT" "$TMP/live/ft-tick.sh"
printf '#!/bin/bash\necho "$*" >> "$LCTL_LOG"\n' > "$TMP/launchctl"; chmod +x "$TMP/launchctl"
mkplist() {  # $1=파일 $2=ProgramArguments[1]
  local p="$TMP/plists/$1"
  "$PB" -c "Add :Label string lbl-${1%.plist}" -c "Add :StandardOutPath string $TMP/${1%.plist}.log" \
        -c "Add :ProgramArguments array" -c "Add :ProgramArguments:0 string /bin/bash" -c "Add :ProgramArguments:1 string $2" \
        -c "Add :EnvironmentVariables dict" -c "Add :EnvironmentVariables:FT_TICK_SEATS string /x/seats-keep.json" "$p" >/dev/null
}
mkplist com.byz.ft-tick.plist "$TMP/live/ft-tick.sh"
for t in cfo feature loom ops; do
  mkdir -p "$TMP/bin-$t"; echo "old-$t" > "$TMP/bin-$t/ft-tick.sh"; mkplist "com.byz.ft-tick-$t.plist" "$TMP/bin-$t/ft-tick.sh"
  cp "$TMP/plists/com.byz.ft-tick-$t.plist" "$TMP/orig-$t.plist"; echo "boot-line-$t" > "$TMP/com.byz.ft-tick-$t.log"
done
export R150_PLIST_DIR="$TMP/plists" R150_LAUNCHCTL="$TMP/launchctl" R150_WAIT=0 LCTL_LOG="$TMP/lctl.log"
run() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY bash "$INSTALL" "$@" > "$TMP/out" 2>&1; echo $?; }
nlc() { [ -f "$LCTL_LOG" ] && wc -l < "$LCTL_LOG" | tr -d ' ' || echo 0; }

chk "dry-run rc" "$(run --dry-run)" 0
chk "dry-run: launchctl 호출 0" "$(nlc)" 0
chk "dry-run: plist 불변" "$(cmp -s "$TMP/orig-ops.plist" "$TMP/plists/com.byz.ft-tick-ops.plist" && echo same || echo changed)" same

# 라이브가 R150 판이 아니면 거부 (변이: 팀 문구 변수 없는 라이브)
grep -v FT_TICK_MASTER_MSG "$KIT" > "$TMP/live-old.sh"; grep -v FT_TICK_RAISED "$KIT" > "$TMP/live-noraised.sh"; cp "$TMP/live/ft-tick.sh" "$TMP/live-r150.sh"
chk "구판 라이브 → 설치 거부 rc" "$(R150_LIVE="$TMP/live-old.sh" run)" 1
chk "RAISED 스위치 없는 라이브 → 설치 거부 rc" "$(R150_LIVE="$TMP/live-noraised.sh" run)" 1
chk "구판 라이브 거부: plist 불변·launchctl 0" "$(cmp -s "$TMP/orig-cfo.plist" "$TMP/plists/com.byz.ft-tick-cfo.plist" && echo same || echo changed)/$(nlc)" same/0

chk "설치 rc" "$(run)" 0
for t in cfo feature loom ops; do
  f="com.byz.ft-tick-$t.plist"
  chk "$t ProgramArguments[1] = 라이브" "$(pv $f ProgramArguments:1)" "$TMP/live/ft-tick.sh"
  chk "$t env 4키" "$(pv $f EnvironmentVariables:FT_TICK_STATE_DIR) $(pv $f EnvironmentVariables:FT_TICK_DRIFT) $(pv $f EnvironmentVariables:FT_TICK_WT_SWEEP) $(pv $f EnvironmentVariables:FT_TICK_RAISED)" "/tmp/ft-tick-state-$t 0 0 0"
  chk "$t 기존 키 불변" "$(pv $f EnvironmentVariables:FT_TICK_SEATS)" /x/seats-keep.json
  chk "$t 백업 = 원본" "$(cmp -s "$TMP/orig-$t.plist" "$TMP/plists/$f.bak-r150" && echo same || echo differ)" same
  plutil -lint "$TMP/plists/$f" >/dev/null && ok "$t plutil -lint" || bad "$t plutil -lint"
done
chk "launchctl bootout·bootstrap 팀마다 1쌍(8줄)" "$(nlc)" 8
chk "첫 루프 확인 줄 출력" "$(grep -c 'boot-line-' "$TMP/out")" 4
chk "설치 재실행(멱등) rc" "$(run)" 0
chk "멱등: launchctl 추가 호출 0" "$(nlc)" 8

chk "되돌림 rc" "$(run --rollback)" 0
for t in cfo feature loom ops; do
  f="com.byz.ft-tick-$t.plist"
  chk "$t 되돌림 = 원본 plist" "$(cmp -s "$TMP/orig-$t.plist" "$TMP/plists/$f" && echo same || echo differ)" same
  old="$(pv $f ProgramArguments:1)"; chk "$t 되돌림 ProgramArguments[1] = 옛 경로·파일 실재" "$old $([ -f "$old" ] && echo exists)" "$TMP/bin-$t/ft-tick.sh exists"
  chk "$t 팀 사본 내용 불변" "$(cat "$TMP/bin-$t/ft-tick.sh")" "old-$t"
done
chk "되돌림 launchctl 8줄 추가(총 16)" "$(nlc)" 16
rm -f "$TMP/plists/com.byz.ft-tick-ops.plist.bak-r150"
chk "백업 없는 되돌림 거부 rc" "$(run --rollback)" 1
chk "인자 오류 rc" "$(run --bogus)" 2

echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit "$fail"
