#!/usr/bin/env bash
# test_dead_seat_resume_r615.sh — R615: ft-tick 죽은 좌석 자동 재개가 «정상으로 닫힌 나노» 를 되살리지 않고(ⓐ),
#   재개 직전(claim 앞)에 명부를 다시 읽어 그 줄이 없거나 닫힌 표식이면 재개 0(ⓑⓒ) · 역할 좌석 재개는 그대로(ⓓ) · 기존 시험 회귀 0(ⓔ).
# 전부 mktemp 안 — 임시 HOME(seat-live·sessions·projects) · 임시 좌석표 · 가짜 tmux(PATH 앞) · 가짜 mbox·자율 모드·자원 문지기·zombie-clean · 실 tmux·실 상태 0.
# base 대조: R615_BIN=<origin/main 판 폴더> bash <이 파일> — 그 폴더에 ft-tick.sh·ft-resume-attempt.sh 가 있어야 한다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_TEAMSET=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="${R615_BIN:-$REPO/harness/bin}"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()   { echo "PASS $1"; }
bad()  { echo "FAIL $1"; fail=$((fail+1)); }
eq()   { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:300}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «${2}»";; *) ok "$3";; esac; }
cnt()  { local n; n="$(grep -c -F -- "$2" "$1" 2>/dev/null)"; echo "${n:-0}"; }
zc()   { wc -l < "$ZLOG" | tr -d ' '; }

bash -n "$BIN/ft-tick.sh" && ok "bash -n ft-tick.sh" || bad "bash -n ft-tick.sh"
if [ -z "${R615_BIN:-}" ]; then cmp -s "$BIN/ft-tick.sh" "$KIT/ft-tick.sh" && ok "키트 사본 cmp 0 ft-tick.sh" || bad "키트 사본 어긋남 ft-tick.sh"; fi

# ── 가짜 도구(전부 mktemp 안) ──
H="$T/home"; F="$T/fake"; ATT="$T/att"; LIVE="$H/.claude/state/seat-live"; SESSF="$T/sessions.txt"; KIDF="$T/kids.txt"; MLOG="$T/mbox.log"; ZLOG="$T/zc.log"; SEATS="$T/seats.json"
mkdir -p "$F" "$H/.claude/sessions" "$H/.claude/projects"
cat > "$F/tmux" <<EOF
#!/bin/bash
case "\$1" in
  list-panes) [ -f "$T/tmux.rc" ] && exit "\$(cat "$T/tmux.rc")"; awk '{print \$1" "\$2}' "$SESSF";;
  has-session) awk -v n="\${3#=}" '\$1==n{f=1}END{exit !f}' "$SESSF";;
  display) n="\${4#=}"; n="\${n%:}"; awk -v n="\$n" '\$1==n{print \$3; f=1}END{exit !f}' "$SESSF";;
  *) exit 0;;
esac
EOF
cat > "$F/mbox.sh" <<EOF
#!/bin/bash
case "\$1" in
  send) echo "\$*" >> "$MLOG";;
  peek) echo "pending=0 scanned=1";;
esac
EOF
cat > "$F/autonomy.sh" <<EOF
#!/bin/bash
cat "$T/auto.mode" 2>/dev/null || echo off
EOF
cat > "$F/gate.sh" <<EOF
#!/bin/bash
rc=\$(cat "$T/gate.rc" 2>/dev/null || echo 0)
[ "\$rc" = 0 ] && echo "OK disk=99" || echo "REJECT resource swap=99999 limit=8192"
exit "\$rc"
EOF
cat > "$F/zc.sh" <<EOF
#!/bin/bash
echo "\$*" >> "$ZLOG"
exit 0
EOF
cat > "$F/seat-status.sh" <<EOF
#!/bin/bash
k="\${2//#/_}"
case "\$1" in
  turn) [ -f "$T/turn.\$k" ] && cat "$T/turn.\$k" || echo "UNKNOWN - - no jsonl";;
  jsonl) [ -f "$T/jl.\$k" ] && cat "$T/jl.\$k" || exit 1;;
esac
EOF
chmod +x "$F"/*
cat > "$F/pgrep" <<EOF
#!/bin/bash
[ "\$1" = -P ] && awk -v p="\$2" '\$1==p{print \$2}' "$KIDF"
exit 0
EOF
chmod +x "$F/pgrep"

M="byz-t-master-claude#1"; P="byz-t-planner-claude#1"; A="byz-t-arch-claude#1"; N="byz-t-nano-x#0"
roster() {   # 인자: seat:role:agent …
  python3 - "$SEATS" "$@" <<'PY'
import json, sys
d = {"_master": "byz-t-master-claude#1", "_hil_route": "byz-t-planner-claude#1"}
for s in sys.argv[2:]:
    k, role, agent = s.split(":")
    d[k] = {"role": role, "agent": agent, "tick": None, "model": "claude-sonnet-5-5[1m]"}
json.dump(d, open(sys.argv[1], "w"), ensure_ascii=False)
PY
}
reset() { rm -rf "$ATT" "$T/state" "$LIVE" "$T"/jl.* "$T"/turn.* "$T/tmux.rc"; : > "$SESSF"; : > "$KIDF"; : > "$MLOG"; : > "$ZLOG"; echo off > "$T/auto.mode"; echo 0 > "$T/gate.rc"; WRAP=""; }
live() {   # seat pane ppid kid uuid — 살아 있는 claude 좌석(세션 파일 + jsonl)
  local cwd="$T/cwd/$4" enc; mkdir -p "$cwd"; enc="$(printf '%s' "$cwd" | sed 's/[^A-Za-z0-9]/-/g')"; mkdir -p "$H/.claude/projects/$enc"
  grep -q "^$1 " "$SESSF" || echo "$1 $2 $3" >> "$SESSF"; grep -q "^$3 $4\$" "$KIDF" || echo "$3 $4" >> "$KIDF"
  printf '{"name":"%s","pid":%s,"sessionId":"%s","cwd":"%s"}' "$1" "$4" "$5" "$cwd" > "$H/.claude/sessions/$4.json"
  [ -f "$H/.claude/projects/$enc/$5.jsonl" ] || printf '{"type":"user"}\n{"type":"assistant"}\n' > "$H/.claude/projects/$enc/$5.jsonl"
}
die_seat() { grep -v -F "$1 " "$SESSF" > "$SESSF.n"; mv "$SESSF.n" "$SESSF"; }
TICK() {
  (cd "$T" && env HOME="$H" PATH="$F:$PATH" FT_TICK_PATH_FIRST="$F" FT_ROOT="$T" FT_TICK_SEATS="$SEATS" FT_TICK_STATE_DIR="$T/state" FT_TICK_STAMP_PREFIX="$T/stamp-" FT_TICK_PIDFILE="$T/tick.pid" \
    FT_TICK_MBOX="$F/mbox.sh" FT_TICK_SEAT_STATUS="$F/seat-status.sh" FT_TICK_AUTONOMY_BIN="$F/autonomy.sh" FT_TICK_RESOURCE_GATE="$F/gate.sh" FT_TICK_ZOMBIE_CLEAN="$F/zc.sh" \
    FT_TICK_RESUME_ATTEMPT="${WRAP:-$BIN/ft-resume-attempt.sh}" FT_RESUME_STATE="$ATT" ZC_LIVE_DIR="$LIVE" FT_TICK_IDLE_ENABLED=0 FT_TICK_WT_SWEEP=0 FT_TICK_HIL=0 FT_TICK_DRIFT=0 FT_TICK_RAISED=0 \
    FT_TICK_NEWS_LEDGER=0 FT_TICK_API_OUTAGE=0 FT_TICK_LAUNCHD=0 FT_TICK_MAGAZINE=0 FT_TICK_STALL_INTERVAL=9999999999 bash "$BIN/ft-tick.sh" --once 2>&1)
}
WRAP=""

# ── ⓐ 정상으로 닫힌 나노는 재개 대상 아님(로그 1줄 · 하루 1번) · 죽음 목록에도 안 실림 ──
reset; roster "$M:master:claude" "$N:nano:claude"
live "$M" %1 100 1001 uuid-m; live "$N" %2 200 1002 uuid-n; TICK >/dev/null   # 살아 있는 동안에만 스냅샷(재개 기록)
echo on > "$T/auto.mode"; die_seat "$N"
o="$(TICK)"; eq "$(zc)" 0 "ⓐ 죽은 나노 → 재개 호출 0"
has "$o" "dead_seat_watch: $N — 재개 대상 아님(nano · spawn 으로 다시 연다)" "ⓐ 나노 제외 로그 1줄"
hasnt "$(cat "$MLOG")" "$N(" "ⓐ 나노는 죽음 목록 알림에 안 실린다"
eq "$(cnt "$MLOG" "[죽은 좌석")" 0 "ⓐ 나노만 죽었으면 죽음 목록 알림 자체가 없다"
o="$(TICK)"; eq "$(printf '%s\n' "$o" | grep -c '재개 대상 아님(nano')" 0 "ⓐ 같은 좌석은 같은 날 다시 안 찍는다(하루 1번)"
die_seat "$M"; o="$(TICK)"; eq "$(zc)" 1 "ⓐ 대조 — 역할 좌석은 여전히 재개(나노 제외가 전체를 죽이지 않는다)"

# ── ⓑ 경합: 첫 읽기 뒤 · claim 전에 명부에서 줄이 사라짐 → 재개 0 · claim 0 ──
mk_wrap() {   # $1 = 변이 종류(absent|retired|stopready) — arch 의 record jsonl(첫 루프) 때 명부를 바꿔 «읽기와 claim 사이 닫힘» 을 만든다
  cat > "$T/ra-wrap.sh" <<EOF
#!/bin/bash
if [ "\$1" = record ] && [ "\$2" = "$A" ] && [ "\$3" = jsonl ] && [ ! -f "$T/mutated" ]; then
  out="\$(bash "$BIN/ft-resume-attempt.sh" "\$@" 2>&1)"; printf '%s\n' "\$out"; : > "$T/mutated"
  python3 - "$SEATS" "$1" <<'PY2'
import json, sys
p, kind = sys.argv[1], sys.argv[2]
d = json.load(open(p)); k = "byz-t-arch-claude#1"
if kind == "absent": d.pop(k, None)
elif kind == "retired": d[k]["_replaced_by"] = "zzz"
else: d[k]["role"] = "stop-ready"
json.dump(d, open(p, "w"), ensure_ascii=False)
PY2
  exit 0
fi
exec bash "$BIN/ft-resume-attempt.sh" "\$@"
EOF
  chmod +x "$T/ra-wrap.sh"; rm -f "$T/mutated"; WRAP="$T/ra-wrap.sh"
}
reset; roster "$M:master:claude" "$P:planner:claude" "$A:arch:claude"
live "$M" %1 100 1001 uuid-m; live "$P" %2 200 1002 uuid-p; live "$A" %3 300 1003 uuid-a; TICK >/dev/null
echo on > "$T/auto.mode"; die_seat "$A"; mk_wrap absent
o="$(TICK)"; eq "$(zc)" 0 "ⓑ 명부에서 사라진 줄 → 재개 호출 0"
has "$o" "dead_seat_watch: $A — 명부에 없음(닫힘) — 재개 0" "ⓑ «명부에 없음(닫힘)» 로그 1줄"
eq "$(ls "$ATT" 2>/dev/null | grep -c "${A}__")" 0 "ⓑ 원장 선점 0(claim 안 함)"
WRAP=""

# ── ⓒ 같은 경합에서 행이 닫힌 표식으로 바뀜(_replaced_by · role=stop-ready) → 재개 0 ──
for kind in retired stopready; do
  reset; roster "$M:master:claude" "$P:planner:claude" "$A:arch:claude"
  live "$M" %1 100 1001 uuid-m; live "$P" %2 200 1002 uuid-p; live "$A" %3 300 1003 uuid-a; TICK >/dev/null
  echo on > "$T/auto.mode"; die_seat "$A"; mk_wrap "$kind"
  o="$(TICK)"; eq "$(zc)" 0 "ⓒ $kind 로 바뀐 줄 → 재개 호출 0"
  has "$o" "dead_seat_watch: $A — 재개 대상 아님" "ⓒ $kind 로그 1줄"
  WRAP=""
done

# ── ⓓ 회귀 0: 역할 좌석이 그대로면 지금처럼 재개 1 ──
reset; roster "$M:master:claude" "$P:planner:claude" "$A:arch:claude"
live "$M" %1 100 1001 uuid-m; live "$P" %2 200 1002 uuid-p; live "$A" %3 300 1003 uuid-a; TICK >/dev/null
echo on > "$T/auto.mode"; die_seat "$A"; TICK >/dev/null
eq "$(zc)" 1 "ⓓ 역할 좌석 그대로 → 재개 호출 1"; has "$(cat "$ZLOG")" "resume $A --from-live" "ⓓ 재개 대상 = arch"

# ── ⓕ 같은 계보(같은 베이스)의 더 큰 번호 세션이 살아 있으면 재개 0 — 로그에 그 이름 · claim 0 ──
L5="byz-x-arch-claude#5"; L6="byz-x-arch-claude#6"
reset; roster "$L5:arch:claude"
live "$L5" %1 100 1001 uuid-l5; TICK >/dev/null
echo on > "$T/auto.mode"; die_seat "$L5"; echo "$L6 %9 900" >> "$SESSF"
o="$(TICK)"; eq "$(zc)" 0 "ⓕ 같은 계보 $L6 생존 → 재개 호출 0"
has "$o" "dead_seat_watch: $L5 — 재개 대상 아님(같은 계보 $L6 생존) — 재개 0" "ⓕ 로그에 살아 있는 이름"
eq "$(ls "$ATT" 2>/dev/null | grep -c "${L5}__")" 0 "ⓕ 원장 선점 0(claim 안 함)"
echo 1 > "$T/tmux.rc"; o="$(TICK)"; eq "$(zc)" 0 "ⓕ tmux 목록 못 읽음 → 재개 0(fail-closed)"
has "$o" "재개 대상 아님(tmux 목록 못 읽음) — 재개 0" "ⓕ 못 읽음 로그 1줄"

# ── ⓖ 더 작은 번호만 생존 · 다른 계보 → 지금처럼 재개(회귀 0) ──
reset; roster "$L5:arch:claude"
live "$L5" %1 100 1001 uuid-l5; TICK >/dev/null
echo on > "$T/auto.mode"; die_seat "$L5"; echo "byz-x-arch-claude#4 %8 800" >> "$SESSF"; echo "byz-y-arch-claude#9 %7 700" >> "$SESSF"
TICK >/dev/null; eq "$(zc)" 1 "ⓖ 더 작은 번호·다른 계보만 생존 → 재개 호출 1"; has "$(cat "$ZLOG")" "resume $L5 --from-live" "ⓖ 재개 대상 = $L5"

# ── ⓔ 기존 시험 회귀 0 ──
if [ -z "${R615_BIN:-}" ]; then
  o="$(bash "$HERE/test_dead_seat_resume.sh" 2>&1 | tail -1)"
  eq "$o" "ALL PASS" "ⓔ test_dead_seat_resume.sh(dead_seat_watch·live_snapshot·idle_long_watch) ALL PASS"
fi
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED=$fail"
exit "$fail"
