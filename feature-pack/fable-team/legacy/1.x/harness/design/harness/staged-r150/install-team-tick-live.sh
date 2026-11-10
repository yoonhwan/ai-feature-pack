#!/bin/bash
# install-team-tick-live.sh — R150: 팀 틱(cfo·feature·loom·ops)이 팀 폴더 사본 대신 «라이브 ft-tick.sh» 를 돌게 한다. 사람 실행(arch 가 ft-hil.sh --add).
#   설치:   plist 백업(.bak-r150) → ProgramArguments[1] = 라이브 ft-tick.sh → EnvironmentVariables 4키 추가
#           (FT_TICK_STATE_DIR=/tmp/ft-tick-state-<팀> · FT_TICK_DRIFT=0 · FT_TICK_WT_SWEEP=0 · FT_TICK_RAISED=0 — drift·sweep·raised 경보는 메인 틱 전담) → bootout/bootstrap → 로그 끝 3줄
#   되돌림: --rollback  백업 plist 복원 → bootout/bootstrap (옛 팀 사본 bin-<팀>/ft-tick.sh 그대로 실행 — 사본은 건드리지 않는다)
#   --dry-run 은 계획만 · plist 값 원문은 출력하지 않는다(키 이름만).
#   env(시험용): R150_PLIST_DIR(~/Library/LaunchAgents) · R150_LAUNCHCTL(launchctl) · R150_LIVE(메인 plist 의 ProgramArguments[1]) · R150_WAIT(5)
set -uo pipefail
TEAMS="cfo feature loom ops"
PLIST_DIR="${R150_PLIST_DIR:-$HOME/Library/LaunchAgents}"; LCTL="${R150_LAUNCHCTL:-launchctl}"; WAIT="${R150_WAIT:-5}"
PB=/usr/libexec/PlistBuddy; DOM="gui/$(id -u)"
MODE=install; DRY=0
for a in "$@"; do case "$a" in --rollback) MODE=rollback;; --dry-run) DRY=1;; *) echo "usage: $0 [--rollback] [--dry-run]" >&2; exit 2;; esac; done
die() { echo "ERR $*" >&2; exit 1; }
pget() { "$PB" -c "Print :$2" "$PLIST_DIR/$1" 2>/dev/null; }
LIVE="${R150_LIVE:-$(pget com.byz.ft-tick.plist ProgramArguments:1)}"
for t in $TEAMS; do [ -f "$PLIST_DIR/com.byz.ft-tick-$t.plist" ] || die "plist 없음: com.byz.ft-tick-$t.plist"; done
if [ "$MODE" = install ]; then
  [ -f "$LIVE" ] || die "라이브 ft-tick.sh 없음 (메인 plist ProgramArguments[1])"
  bash -n "$LIVE" || die "라이브 ft-tick.sh 문법 오류"
  grep -q FT_TICK_MASTER_MSG "$LIVE" && grep -q FT_TICK_PM_MSG "$LIVE" || die "라이브 ft-tick.sh 가 R150 판이 아님(팀 문구 두 변수 없음) — arch 의 라이브 bin 교체가 먼저"
  grep -q 'FT_TICK_WT_SWEEP' "$LIVE" && grep -q 'FT_TICK_DRIFT' "$LIVE" && grep -q 'FT_TICK_RAISED' "$LIVE" || die "라이브 ft-tick.sh 에 FT_TICK_WT_SWEEP/FT_TICK_DRIFT/FT_TICK_RAISED 스위치 없음"
fi

reload() {  # $1=plist 파일 이름 $2=label — bootout 은 «안 떠 있음»이어도 계속, bootstrap 실패는 중단
  "$LCTL" bootout "$DOM/$2" >/dev/null 2>&1
  "$LCTL" bootstrap "$DOM" "$PLIST_DIR/$1" || die "bootstrap 실패: $2 — --rollback 으로 되돌린다"
}
log_tail() {  # $1=plist 파일 이름 — 재기동 뒤 첫 루프 확인 줄
  local lf; lf="$(pget "$1" StandardOutPath)"; sleep "$WAIT"
  echo "  log(${lf##*/}) 끝 3줄:"; tail -3 "$lf" 2>/dev/null | sed 's/^/    /'
}

for t in $TEAMS; do
  f="com.byz.ft-tick-$t.plist"; p="$PLIST_DIR/$f"; bak="$p.bak-r150"; label="$(pget "$f" Label)"
  cur="$(pget "$f" ProgramArguments:1)"
  if [ "$MODE" = rollback ]; then
    [ -f "$bak" ] || die "백업 없음: $f.bak-r150 — 되돌릴 수 없다"
    echo "[$t] rollback: $f ← .bak-r150"
    [ "$DRY" = 1 ] && continue
    cp -p "$bak" "$p" || die "복원 실패: $f"
    old="$(pget "$f" ProgramArguments:1)"; [ -f "$old" ] || die "복원된 ProgramArguments[1] 파일이 없다: $f"
    reload "$f" "$label"; log_tail "$f"; continue
  fi
  echo "[$t] install: ProgramArguments[1] → 라이브 · env +FT_TICK_STATE_DIR +FT_TICK_DRIFT +FT_TICK_WT_SWEEP +FT_TICK_RAISED"
  [ "$cur" = "$LIVE" ] && { echo "  이미 라이브 — 건너뜀"; continue; }
  [ -f "$cur" ] || die "현재 ProgramArguments[1] 파일이 없다(되돌림 불가): $f"
  [ "$DRY" = 1 ] && continue
  if [ -e "$bak" ]; then cmp -s "$bak" "$p" || die "백업이 이미 있고 현재 plist 와 다르다: $f.bak-r150 — 사람 확인"; else cp -p "$p" "$bak" || die "백업 실패: $f"; fi
  "$PB" -c "Set :ProgramArguments:1 $LIVE" "$p" || die "ProgramArguments 갱신 실패: $f"
  for kv in "FT_TICK_STATE_DIR=/tmp/ft-tick-state-$t" FT_TICK_DRIFT=0 FT_TICK_WT_SWEEP=0 FT_TICK_RAISED=0; do
    k="${kv%%=*}"; v="${kv#*=}"
    "$PB" -c "Add :EnvironmentVariables:$k string $v" "$p" >/dev/null 2>&1 || "$PB" -c "Set :EnvironmentVariables:$k $v" "$p" || die "env 키 쓰기 실패: $k ($f)"
  done
  plutil -lint "$p" >/dev/null || die "plist 문법 오류: $f — 백업 .bak-r150 으로 복원"
  reload "$f" "$label"; log_tail "$f"
done
echo "OK $MODE ($TEAMS)$([ "$DRY" = 1 ] && echo ' dry-run')"
