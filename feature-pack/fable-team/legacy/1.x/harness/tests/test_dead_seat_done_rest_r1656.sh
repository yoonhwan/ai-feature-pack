#!/usr/bin/env bash
# test_dead_seat_done_rest_r1656.sh — r1656 ⓔⓕ: ft-tick dead_seat_watch 가 `ft-seat-close --done` 으로 닫힌 팀장(_closed.done)을
#   받을 일 0(open-work rc0) 이면 «쉬는 중» 으로 보고 재개 0 · 받을 일 생김(rc1) 이면 지금 재개 길 그대로 · 표식 없는 죽은 팀장 = 지금과 같음.
#   ① done 행 + rc0 → DRY kind=dead-seat seat= 0 · 쉬는 중 로그 1줄 ② done 행 + rc1 → DRY kind=dead-seat seat= 1 · 표식 그대로
#   ③ done 없는 죽은 팀장 → DRY kind=dead-seat seat= 1 · open-work 호출 0 · 변이 M3(쉬는 중 갈래 삭제 → ① 이 재개로 바뀜) — bin 사본에서만.
# 전부 mktemp 안 — 임시 HOME · 임시 좌석표 · 가짜 tmux·mbox·자율 모드·자원 문지기·zombie-clean·open-work · 실 tmux·실 상태 0 · sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export FT_TEAMSET=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
T0=$SECONDS
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."; BIN="$REPO/harness/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()   { echo "PASS $1"; }
bad()  { echo "FAIL $1"; fail=$((fail+1)); }
eq()   { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }
H="$T/home"; F="$T/fake"; ATT="$T/att"; LIVE="$H/.claude/state/seat-live"; SESSF="$T/sessions.txt"; KIDF="$T/kids.txt"; ZLOG="$T/zc.log"; SEATS="$T/seats.json"; OWLOG="$T/ow.log"
mkdir -p "$F" "$H/.claude/sessions" "$H/.claude/projects"
cat > "$F/tmux" <<EOF
#!/bin/bash
case "\$1" in
  list-panes) awk '{print \$1" "\$2}' "$SESSF";;
  has-session) awk -v n="\${3#=}" '\$1==n{f=1}END{exit !f}' "$SESSF";;
  display) n="\${4#=}"; n="\${n%:}"; awk -v n="\$n" '\$1==n{print \$3; f=1}END{exit !f}' "$SESSF";;
  *) exit 0;;
esac
EOF
printf '#!/bin/bash\n[ "$1" = peek ] && echo "pending=0 scanned=1"\nexit 0\n' > "$F/mbox.sh"
printf '#!/bin/bash\ncat "%s/auto.mode" 2>/dev/null || echo off\n' "$T" > "$F/autonomy.sh"
printf '#!/bin/bash\necho "OK disk=99"\n' > "$F/gate.sh"
printf '#!/bin/bash\necho "$*" >> "%s"\n' "$ZLOG" > "$F/zc.sh"
printf '#!/bin/bash\nk="${2//#/_}"\ncase "$1" in turn) echo "UNKNOWN - - no jsonl";; jsonl) [ -f "%s/jl.$k" ] && cat "%s/jl.$k" || exit 1;; esac\n' "$T" "$T" > "$F/seat-status.sh"
printf '#!/bin/bash\n[ "$1" = -P ] && awk -v p="$2" '"'"'$1==p{print $2}'"'"' "%s"\nexit 0\n' "$KIDF" > "$F/pgrep"
printf 'import sys\nopen("%s", "a").write(" ".join(sys.argv[1:]) + "\\n")\nsys.exit(int(open("%s/ow.rc").read().strip() or 0))\n' "$OWLOG" "$T" > "$F/ow-stub.py"
chmod +x "$F"/*

M="byz-t-master-claude#1"
roster() {   # roster <done 0|1> — 팀장 1석(_master) · 1 = _closed.done 표식(ft-seat-close --done 꼴 · role 그대로)
  python3 - "$SEATS" "$1" "$M" <<'PY'
import json, sys
p, dn, m = sys.argv[1], sys.argv[2] == "1", sys.argv[3]
d = {"_master": m, "_hil_route": m, m: {"role": "master", "agent": "claude", "tick": None, "model": "claude-sonnet-5-5[1m]"}}
if dn: d[m]["_closed"] = {"by": "caller#0", "at": "2026-11-15T00:00:00", "reason": "r1656", "done": {"ts": "2026-11-15T00:00:00", "seq": 5}}
json.dump(d, open(p, "w"), ensure_ascii=False)
PY
}
reset() { rm -rf "$ATT" "$T/state" "$LIVE" "$T"/jl.*; : > "$SESSF"; : > "$KIDF"; : > "$ZLOG"; : > "$OWLOG"; echo off > "$T/auto.mode"; echo 0 > "$T/ow.rc"; }
live() {   # seat pane ppid kid uuid — 살아 있는 claude 좌석(세션 파일 + jsonl)
  local cwd="$T/cwd/$4" enc; mkdir -p "$cwd"; enc="$(printf '%s' "$cwd" | sed 's/[^A-Za-z0-9]/-/g')"; mkdir -p "$H/.claude/projects/$enc"
  echo "$1 $2 $3" >> "$SESSF"; echo "$3 $4" >> "$KIDF"
  printf '{"name":"%s","pid":%s,"sessionId":"%s","cwd":"%s"}' "$1" "$4" "$5" "$cwd" > "$H/.claude/sessions/$4.json"
  printf '{"type":"user"}\n{"type":"assistant"}\n' > "$H/.claude/projects/$enc/$5.jsonl"
}
TICK() {   # TICK [bin 폴더] [--dry-run]
  local b="$1"; shift
  (cd "$T" && env HOME="$H" PATH="$F:$PATH" FT_TICK_PATH_FIRST="$F" FT_ROOT="$T" FT_TICK_SEATS="$SEATS" FT_TICK_STATE_DIR="$T/state" FT_TICK_STAMP_PREFIX="$T/stamp-" FT_TICK_PIDFILE="$T/tick.pid" \
    FT_TICK_MBOX="$F/mbox.sh" FT_TICK_SEAT_STATUS="$F/seat-status.sh" FT_TICK_AUTONOMY_BIN="$F/autonomy.sh" FT_TICK_RESOURCE_GATE="$F/gate.sh" FT_TICK_ZOMBIE_CLEAN="$F/zc.sh" \
    FT_TICK_RESUME_ATTEMPT="$b/ft-resume-attempt.sh" FT_RESUME_STATE="$ATT" ZC_LIVE_DIR="$LIVE" FT_TICK_IDLE_ENABLED=0 FT_TICK_WT_SWEEP=0 FT_TICK_HIL=0 FT_TICK_DRIFT=0 FT_TICK_RAISED=0 \
    FT_TICK_NEWS_LEDGER=0 FT_TICK_API_OUTAGE=0 FT_TICK_LAUNCHD=0 FT_TICK_MAGAZINE=0 FT_TICK_STALL_INTERVAL=9999999999 FT_SEAT_OPEN_WORK="$F/ow-stub.py" bash "$b/ft-tick.sh" --once "$@" 2>&1)
}
prep() {   # prep <done 0|1> <open-work rc> — 살아 있을 때 스냅샷(재개 기록 · live_snapshot 과 같은 호출) → 자율 ON → 세션 사라짐 → 표식
  reset; roster 0; live "$M" %1 100 1001 uuid-m
  (cd "$T" && env HOME="$H" PATH="$F:$PATH" FT_ROOT="$T" FT_RESUME_STATE="$ATT" ZC_LIVE_DIR="$LIVE" bash "$BIN/ft-resume-attempt.sh" snapshot "$M" --agent claude --model m >/dev/null 2>&1)
  echo on > "$T/auto.mode"; : > "$SESSF"; roster "$1"; echo "$2" > "$T/ow.rc"; : > "$OWLOG"
}
dseat() { printf '%s\n' "$1" | grep -c "^DRY kind=dead-seat seat=$M "; }

echo "== ① done 행 + open-work rc0 → 쉬는 중 · DRY kind=dead-seat seat= 0"
prep 1 0; o="$(TICK "$BIN" --dry-run)"
eq "$(dseat "$o")" 0 "① DRY kind=dead-seat seat=$M 0"
eq "$(printf '%s\n' "$o" | grep -c "dead_seat_watch: $M — 쉬는 중(--done 닫힘 · 받을 일 0) — 재개 0")" 1 "① 쉬는 중 로그 1줄"
eq "$(grep -c "^$M --root $T --mbox-dir $F\$" "$OWLOG")" 1 "① open-work 1회(좌석·root·mbox-dir)"
eq "$(printf '%s\n' "$o" | grep -c 'DRY kind=dead-seat mode=on dead=0')" 1 "① 죽음 목록 0"

echo "== ② done 행 + open-work rc1(받을 일 생김) → 지금 재개 길 · DRY kind=dead-seat seat= 1 · 표식 그대로"
prep 1 1; o="$(TICK "$BIN" --dry-run)"
eq "$(dseat "$o")" 1 "② DRY kind=dead-seat seat=$M 1"
eq "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))[sys.argv[2]]["_closed"]["done"]["seq"])' "$SEATS" "$M")" 5 "② _closed.done 지우지 않음"
prep 1 3; o="$(TICK "$BIN" --dry-run)"
eq "$(dseat "$o")" 1 "②b open-work rc3(판정 불가) → 지금 재개 길(숨기지 않음)"

echo "== ③ done 없는 죽은 팀장 → 지금과 같음(open-work 호출 0)"
prep 0 0; o="$(TICK "$BIN" --dry-run)"
eq "$(dseat "$o")" 1 "③ DRY kind=dead-seat seat=$M 1"
eq "$(wc -l < "$OWLOG" | tr -d ' ')" 0 "③ 표식 없으면 open-work 호출 0"

echo "== 변이 M3 (bin 사본 · 쉬는 중 갈래 삭제)"
MB="$T/mb"; cp -R "$BIN" "$MB"
python3 - "$MB/ft-tick.sh" <<'PY' || bad "M3 치환 실패"
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read(); o = 'done_rest "$seat" && {'
if s.count(o) != 1: sys.exit("mut: 개수 %d" % s.count(o))
open(p, "w", encoding="utf-8").write(s.replace(o, 'false && {'))
PY
prep 1 0; o="$(TICK "$MB" --dry-run)"
eq "$(dseat "$o")" 1 "M3 쉬는 중 갈래 삭제 → 사례① 이 재개 대상(변이 잡힘)"

echo "RUN test_dead_seat_done_rest_r1656 $((SECONDS - T0))s"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
