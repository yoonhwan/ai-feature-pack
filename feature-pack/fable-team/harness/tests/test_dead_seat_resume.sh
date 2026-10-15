#!/usr/bin/env bash
# test_dead_seat_resume.sh — R163(판정 1675 ②) 자율 중 죽은 좌석 자동 재개: 고정 수락 기준 ①~⑤ + 추가 축 ⓐ~ⓖ + 변이 3.
# 전부 mktemp 안 — 임시 HOME(seat-live·sessions·projects) · 임시 좌석표 · 가짜 tmux/pgrep(PATH 앞) · 가짜 자원 문지기·자율 모드·zombie-clean·mbox · 실 tmux·실 상태 0.
# 변이 시험은 R163_BIN=<변이 복사본 폴더> 로 같은 시험을 다시 돌린다.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="${R163_BIN:-$REPO/scripts/fable-team-bin}"; KIT="$REPO/scripts/harness-install/fable-team/bin"
ZC="$REPO/scripts/harness-install/zombie-clean/zombie-clean.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()   { echo "PASS $1"; }
bad()  { echo "FAIL $1"; fail=$((fail+1)); }
eq()   { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:240}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «${2}»";; *) ok "$3";; esac; }
cnt()  { local n; n="$(grep -c -F -- "$2" "$1" 2>/dev/null)"; echo "${n:-0}"; }

for f in ft-tick.sh ft-resume-attempt.sh ft-nano-spawn.sh; do bash -n "$BIN/$f" && ok "bash -n $f" || bad "bash -n $f"; done
bash -n "$ZC" && ok "bash -n zombie-clean.sh" || bad "bash -n zombie-clean.sh"
if [ -z "${R163_BIN:-}" ]; then for f in ft-tick.sh ft-resume-attempt.sh ft-nano-spawn.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 사본 cmp 0 $f" || bad "키트 사본 어긋남 $f"; done; fi

# ── 가짜 도구 ──
H="$T/home"; F="$T/fake"; ATT="$T/att"; LIVE="$H/.claude/state/seat-live"; SESSF="$T/sessions.txt"; KIDF="$T/kids.txt"
MLOG="$T/mbox.log"; ZLOG="$T/zc.log"; SEATS="$T/seats.json"
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
printf '#!/bin/bash\n[ "$1" = -P ] && awk -v p="$2" '"'"'$1==p{print $2}'"'"' "%s"\n' "$KIDF" > "$F/pgrep"
printf '#!/bin/bash\ncase "$1" in\n send) echo "$*" >> "%s";;\n peek) f="%s/pend.${2//#/_}"; echo "pending=$( [ -f "$f" ] && cat "$f" || echo 0 ) scanned=1";;\nesac\n' "$MLOG" "$T" > "$F/mbox.sh"
printf '#!/bin/bash\ncat "%s/auto.mode" 2>/dev/null || echo off\n' "$T" > "$F/autonomy.sh"
printf '#!/bin/bash\nrc=$(cat "%s/gate.rc" 2>/dev/null || echo 0)\n[ "$rc" = 0 ] && echo "OK disk=99" || echo "REJECT resource swap=99999 limit=8192"\nexit "$rc"\n' "$T" > "$F/gate.sh"
printf '#!/bin/bash\necho "$*" >> "%s"\nexit $(cat "%s/zc.rc" 2>/dev/null || echo 0)\n' "$ZLOG" "$T" > "$F/zc.sh"
cat > "$F/seat-status.sh" <<EOF
#!/bin/bash
k="\${2//#/_}"
case "\$1" in
  turn) [ -f "$T/turn.\$k" ] && cat "$T/turn.\$k" || echo "UNKNOWN - - no jsonl";;
  jsonl) [ -f "$T/jl.\$k" ] && cat "$T/jl.\$k" || exit 1;;
esac
EOF
chmod +x "$F"/*

M="byz-t-master-claude#1"; P="byz-t-planner-claude#1"; A="byz-t-arch-claude#1"; N="byz-t-nano-x#0"; C="byz-t-da-codex#0"
roster() {   # 인자: seat:role:agent[:extra] …
  python3 - "$SEATS" "$@" <<'PY'
import json, sys
d = {"_master": "byz-t-master-claude#1", "_hil_route": "byz-t-planner-claude#1"}
for s in sys.argv[2:]:
    k, role, agent, *x = s.split(":"); r = {"role": role, "agent": agent, "tick": None, "model": "claude-sonnet-5-5[1m]"}
    if x: r["_replaced_by"] = "zzz"
    d[k] = r
json.dump(d, open(sys.argv[1], "w"), ensure_ascii=False)
PY
}
reset() { rm -rf "$ATT" "$T/state" "$LIVE" "$T"/turn.* "$T"/jl.* "$T"/pend.* "$T"/stamp-* "$T"/*.pid; : > "$SESSF"; : > "$KIDF"; : > "$MLOG"; : > "$ZLOG"; echo off > "$T/auto.mode"; echo 0 > "$T/gate.rc"; echo 0 > "$T/zc.rc"; }
live() {   # seat pane ppid kid uuid  — 살아 있는 claude 좌석(세션 파일 + jsonl)
  local cwd="$T/cwd/$4" enc; mkdir -p "$cwd"; enc="$(printf '%s' "$cwd" | sed 's/[^A-Za-z0-9]/-/g')"; mkdir -p "$H/.claude/projects/$enc"
  grep -q "^$1 " "$SESSF" || echo "$1 $2 $3" >> "$SESSF"; grep -q "^$3 $4\$" "$KIDF" || echo "$3 $4" >> "$KIDF"
  printf '{"name":"%s","pid":%s,"sessionId":"%s","cwd":"%s"}' "$1" "$4" "$5" "$cwd" > "$H/.claude/sessions/$4.json"
  [ -f "$H/.claude/projects/$enc/$5.jsonl" ] || printf '{"type":"user"}\n{"type":"assistant"}\n' > "$H/.claude/projects/$enc/$5.jsonl"
}
jsonl_of() { printf '%s/.claude/projects/%s/%s.jsonl' "$H" "$(printf '%s' "$T/cwd/$1" | sed 's/[^A-Za-z0-9]/-/g')" "$2"; }
die_seat() { grep -v -F "$1 " "$SESSF" > "$SESSF.n"; mv "$SESSF.n" "$SESSF"; }
TICK_X=""
TICK() {
  (cd "$T" && env HOME="$H" PATH="$F:$PATH" FT_TICK_PATH_FIRST="$F" $TICK_X FT_ROOT="$T" FT_TICK_SEATS="$SEATS" FT_TICK_STATE_DIR="$T/state" FT_TICK_STAMP_PREFIX="$T/stamp-" FT_TICK_PIDFILE="$T/tick.pid" \
    FT_TICK_MBOX="$F/mbox.sh" FT_TICK_SEAT_STATUS="$F/seat-status.sh" FT_TICK_AUTONOMY_BIN="$F/autonomy.sh" FT_TICK_RESOURCE_GATE="$F/gate.sh" FT_TICK_ZOMBIE_CLEAN="$F/zc.sh" \
    FT_TICK_RESUME_ATTEMPT="$BIN/ft-resume-attempt.sh" FT_RESUME_STATE="$ATT" ZC_LIVE_DIR="$LIVE" FT_TICK_IDLE_ENABLED=0 FT_TICK_WT_SWEEP=0 FT_TICK_HIL=0 FT_TICK_DRIFT=0 FT_TICK_RAISED=0 \
    FT_TICK_NEWS_LEDGER=0 FT_TICK_API_OUTAGE=0 FT_TICK_LAUNCHD=0 FT_TICK_MAGAZINE=0 FT_TICK_STALL_INTERVAL=9999999999 bash "$BIN/ft-tick.sh" --once 2>&1)
}
RA() { env HOME="$H" PATH="$F:$PATH" FT_ROOT="$T" FT_RESUME_STATE="$ATT" ZC_LIVE_DIR="$LIVE" bash "$BIN/ft-resume-attempt.sh" "$@" 2>&1 | grep -v "setlocale"; }   # C.UTF-8 에서 bash 가 stderr 에 내는 로케일 경고는 값 비교에서 뺀다

# ── ⓐ 살아 있는 좌석 스냅샷: 바뀐 좌석만 · 원자 쓰기 · codex 제외 ──
reset; roster "$M:master:claude" "$N:nano:claude" "$C:da:codex"
live "$M" %1 100 1001 uuid-m; live "$N" %2 200 1002 uuid-n; live "$C" %3 300 1003 uuid-c
TICK_X="FT_NOW=1000"; TICK >/dev/null
[ -f "$LIVE/$M.json" ] && ok "ⓐ master 스냅샷 생김" || bad "ⓐ master 스냅샷 없음"
eq "$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["uuid"],d["source"],d["engine"],d["model"])' "$LIVE/$M.json")" "uuid-m live claude claude-sonnet-5-5[1m]" "ⓐ 스냅샷 키(uuid·source=live·engine·model)"
[ -f "$LIVE/$C.json" ] && bad "ⓐ codex 좌석에 스냅샷이 생김" || ok "ⓐ codex 좌석 스냅샷 0"
eq "$(ls "$LIVE" | grep -c tmp)" 0 "ⓐ tmp 잔존 0(tmp→mv 원자 쓰기)"
at1="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["at"])' "$LIVE/$M.json")"
TICK_X="FT_NOW=2000"; TICK >/dev/null
eq "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["at"])' "$LIVE/$M.json")" "$at1" "ⓐ jsonl 안 바뀐 좌석은 다시 쓰지 않는다"
touch -t 203001010000 "$(jsonl_of 1001 uuid-m)"; TICK_X="FT_NOW=3000"; TICK >/dev/null
[ "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["at"])' "$LIVE/$M.json")" != "$at1" ] && ok "ⓐ jsonl 이 바뀌면 다시 쓴다" || bad "ⓐ jsonl 이 바뀌었는데 안 씀"
TICK_X=""
# zombie-clean --from-live: 기록 경로만 seat-live (검사·명령 동작 불변)
die_seat "$M"
o="$(env HOME="$H" PATH="$F:$PATH" ZC_LIVE_DIR="$LIVE" bash "$ZC" resume "$M" --from-live --dry-run 2>&1)"; has "$o" "[dry] session=$M" "ⓐ resume --from-live dry-run 세션"; has "$o" "claude --resume uuid-m --model 'claude-sonnet-5-5[1m]'" "ⓐ resume --from-live 명령 불변"
o="$(env HOME="$H" PATH="$F:$PATH" ZC_LIVE_DIR="$LIVE" bash "$ZC" resume "$M" --dry-run 2>&1)"; has "$o" "재개 기록 없음" "ⓐ --from-live 없으면 은퇴 기록 경로(스냅샷 안 읽음)"

# ── ⓑⓒ 죽음 판정 + OFF 는 목록 1통(바뀐 때만) · 재개 0 ──
reset; roster "$M:master:claude" "$P:planner:claude" "$A:arch:claude" "$N:nano:claude" "$C:da:codex" "byz-t-gone#0:stop-ready:claude" "byz-t-old#0:nano:claude:x"
live "$M" %1 100 1001 uuid-m; live "$P" %2 200 1002 uuid-p; live "$A" %3 300 1003 uuid-a; live "$N" %4 400 1004 uuid-n; live "$C" %5 500 1005 uuid-c
TICK >/dev/null; die_seat "$N"; die_seat "$C"
TICK >/dev/null
eq "$(cat "$ZLOG")" "" "ⓒ OFF 이면 재개 0"
eq "$(cnt "$MLOG" "[죽은 좌석 2]")" 1 "ⓒ OFF 죽음 목록 1통"; has "$(cat "$MLOG")" "send $P ft-tick" "ⓒ 목록은 planner 에게"
has "$(cat "$MLOG")" "$N(재개 기록 있음" "ⓑ 죽은 claude 나노 표기"; has "$(cat "$MLOG")" "$C(재개 기록 없음" "ⓑ 죽은 codex 좌석은 기록 없음(사람 판정)"
hasnt "$(cat "$MLOG")" "byz-t-gone" "ⓑ stop-ready 좌석은 죽음 대상 아님"; hasnt "$(cat "$MLOG")" "byz-t-old" "ⓑ 은퇴(_replaced_by) 좌석은 죽음 대상 아님"
TICK >/dev/null; eq "$(cnt "$MLOG" "[죽은 좌석")" 1 "ⓒ 같은 목록은 다시 안 보낸다(바뀐 때만)"
die_seat "$A"; TICK >/dev/null; eq "$(cnt "$MLOG" "[죽은 좌석")" 2 "ⓒ 목록이 바뀌면 다시 보낸다"

# ── ⓓ 한 루프 1석 · 순서 master→planner→arch→그 밖 / ⓔ 같은 좌석+uuid 1회 / ③ 틱 재시작 뒤 유지 ──
reset; roster "$M:master:claude" "$P:planner:claude" "$A:arch:claude" "$N:nano:claude"
live "$M" %1 100 1001 uuid-m; live "$P" %2 200 1002 uuid-p; live "$A" %3 300 1003 uuid-a; live "$N" %4 400 1004 uuid-n
TICK >/dev/null; echo on > "$T/auto.mode"; for s in "$N" "$A" "$P" "$M"; do die_seat "$s"; done
TICK >/dev/null; eq "$(wc -l < "$ZLOG" | tr -d ' ')" 1 "ⓓ 한 루프 1석"; has "$(cat "$ZLOG")" "resume $M --from-live" "ⓓ 첫 순번 = master"
for i in 1 2 3 4 5; do TICK >/dev/null; done
eq "$(awk '{print $2}' "$ZLOG" | tr '\n' ' ')" "$M $P $A $N " "ⓓ 순서 master→planner→arch→그 밖"
eq "$(RA state "$M" uuid-m)" failed "ⓔ 재개했으나 세션이 안 떠 있으면(조기 종료) failed"
eq "$(wc -l < "$ZLOG" | tr -d ' ')" 4 "ⓔ 실패한 좌석을 다시 시도하지 않는다(틱 재시작 5회 뒤에도 4회뿐)"
has "$(cat "$MLOG")" "자동 재개 소진" "ⓔ 소진 좌석은 목록으로 사람에게"
o="$(RA claim race-seat uuid-r)"; has "$o" CLAIMED "ⓔ 원장 선점 1번째 호출"; o="$(RA claim race-seat uuid-r)"; has "$o" BLOCKED "ⓔ 원장 선점은 동시에 온 두 번째 호출을 막는다(mkdir lock)"

# ── ① 오빠 재허용 토큰 = 정확히 1회 · 직접 쓰기 무효 · failed 아니면 REJECT ──
o="$(RA allow "$M" uuid-m)"; has "$o" "ALLOWED resume-allow $M uuid-m" "① allow → 토큰+log 줄"
eq "$(cnt "$ATT/allow.log" "resume-allow $M uuid-m")" 1 "① allow.log 에 같은 줄"
TICK >/dev/null; eq "$(grep -c "resume $M" "$ZLOG")" 2 "① 토큰 1개 = 정확히 1회 더"
for i in 1 2 3; do TICK >/dev/null; done; eq "$(grep -c "resume $M" "$ZLOG")" 2 "① 소비 뒤 재시도 0"
eq "$(ls "$ATT" | grep -c 'allow.used')" 1 "① 토큰은 mv 로 소비돼 .used 로 남는다"
printf 'resume-allow %s uuid-p 1\n' "$P" > "$ATT/${P}__uuid-p.state.allow"
for i in 1 2; do TICK >/dev/null; done; eq "$(grep -c "resume $P" "$ZLOG")" 1 "② .allow 직접 쓰기(allow.log 줄 없음) = 소비 0·resume 0"
o="$(RA allow "byz-t-none#9" uuid-z)"; has "$o" "REJECT" "① 원장 없는 좌석 allow 는 REJECT"

# ── ③ 토큰 결속 (DA⑥ H1): 좌석·uuid·형식 — 어긋난 토큰은 can-try·consume 모두 거부 · 토큰·lock·원장 그대로 ──
TB() { local s="$1" u="$2"; RA claim "$s" "$u" >/dev/null; RA settle "$s" "$u" failed >/dev/null; }
TB sA uA; TB sB uB; TB sA uA2; TB sC uC
RA allow sA uA >/dev/null; RA allow sC uC >/dev/null
LA="$(RA allow sB uB; true)"; LINE_A="$(grep -F 'resume-allow sA uA ' "$ATT/allow.log" | head -1)"
printf '%s\n' "$LINE_A" > "$ATT/sB__uB.state.allow"    # ①B 의 토큰 파일에 A 의 승인 줄을 옮겨 넣음
eq "$(RA can-try sB uB; true)" "blocked failed" "③① 다른 좌석 토큰 → can-try 거부"
o="$(RA consume-allow sB uB)"; has "$o" "NONE" "③① 다른 좌석 토큰 → consume 거부"
[ -d "$ATT/sB__uB.state.lock" ] && [ -f "$ATT/sB__uB.state.allow" ] && ok "③① 거부 뒤 lock·토큰 그대로(소비 0)" || bad "③① 거부했는데 lock/토큰이 바뀜"
cp "$ATT/sA__uA.state.allow" "$ATT/sA__uA2.state.allow"  # ②같은 좌석 다른 uuid
o="$(RA consume-allow sA uA2)"; has "$o" "NONE" "③② 같은 좌석 다른 uuid 토큰 → 거부"
[ -d "$ATT/sA__uA2.state.lock" ] && ok "③② 거부 뒤 lock 그대로" || bad "③② lock 이 풀림"
for bad_line in "resume-allow sC uC" "resume-allow sC uC abc" "resume-allow sC uC 123 extra" "allow sC uC 123"; do   # ③잘못된 형식(allow.log 에도 있는 줄이어도)
  printf '%s\n' "$bad_line" >> "$ATT/allow.log"; printf '%s\n' "$bad_line" > "$ATT/sC__uC.state.allow"
  o="$(RA consume-allow sC uC)"; has "$o" "NONE" "③③ 잘못된 형식 «${bad_line}» → 거부"
done
[ -d "$ATT/sC__uC.state.lock" ] && ok "③③ 거부 뒤 lock 그대로" || bad "③③ lock 이 풀림"
o="$(RA consume-allow sA uA)"; has "$o" "CONSUMED sA uA" "③④ 맞는 토큰 → 소비"
o="$(RA consume-allow sA uA)"; has "$o" "NONE" "③④ 두 번째 소비 거부"
o="$(RA claim sA uA)"; has "$o" "CLAIMED" "③④ 소비 뒤 claim 정확히 1회"; o="$(RA claim sA uA)"; has "$o" "BLOCKED" "③④ 두 번째 claim 거부"

# ── ④ 자원 REJECT → resume 호출 0·원장 0 · 통과하면 그제서야 1회 ──
reset; roster "$M:master:claude"; live "$M" %1 100 1001 uuid-m; TICK >/dev/null; echo on > "$T/auto.mode"; die_seat "$M"; echo 3 > "$T/gate.rc"
TICK >/dev/null; eq "$(wc -l < "$ZLOG" | tr -d ' ')" 0 "④ 자원 REJECT 면 zombie-clean 호출 0"; eq "$(ls "$ATT" 2>/dev/null | wc -l | tr -d ' ')" 0 "④ 자원 REJECT 면 원장·lock 0"
has "$(cat "$MLOG")" "자원 문지기 REJECT" "④ REJECT 사유는 planner 에게"
echo 0 > "$T/gate.rc"; TICK >/dev/null; eq "$(wc -l < "$ZLOG" | tr -d ' ')" 1 "④ 자원이 풀리면 1회(REJECT 때 원장을 태우지 않았다)"

# ── 재개 명령 실패 = 즉시 failed · ok 경로 · 새 uuid 만 새 원장 ──
reset; roster "$M:master:claude"; live "$M" %1 100 1001 uuid-m; TICK >/dev/null; echo on > "$T/auto.mode"; die_seat "$M"; echo 1 > "$T/zc.rc"
TICK >/dev/null; eq "$(RA state "$M" uuid-m)" failed "ⓔ resume 명령이 실패하면 그 자리에서 failed"; has "$(cat "$MLOG")" "[재개 실패]" "ⓔ 실패 알림"
reset; roster "$M:master:claude"; live "$M" %1 100 1001 uuid-m; TICK >/dev/null; echo on > "$T/auto.mode"; die_seat "$M"
TICK >/dev/null; eq "$(RA state "$M" uuid-m)" pending "재개 직후 pending"
live "$M" %1 100 1001 uuid-m; touch -t 203001010000 "$(jsonl_of 1001 uuid-m)"; TICK >/dev/null; eq "$(RA state "$M" uuid-m)" ok "세션이 살아 있고 jsonl 이 자라면 ok"
die_seat "$M"; TICK >/dev/null; eq "$(wc -l < "$ZLOG" | tr -d ' ')" 1 "ok 뒤 같은 uuid 로 다시 죽으면 자동 재개 0"
live "$M" %1 100 1001 uuid-m2; TICK >/dev/null; die_seat "$M"; TICK >/dev/null; eq "$(wc -l < "$ZLOG" | tr -d ' ')" 2 "새 uuid 일 때만 새 원장"

# ── 완료·휴식 좌석은 죽음 대상 아님 ──
reset; roster "$N:nano:claude"; live "$N" %1 100 1001 uuid-n; TICK >/dev/null; echo on > "$T/auto.mode"
JL="$(jsonl_of 1001 uuid-n)"; printf '{"type":"assistant","message":"[완료·휴식] 끝"}\n{"type":"system","subtype":"turn_duration"}\n' > "$JL"; TICK >/dev/null; die_seat "$N"
TICK >/dev/null; eq "$(wc -l < "$ZLOG" | tr -d ' ')" 0 "ⓑ 완료·휴식 좌석은 재개 0"
printf '{"type":"assistant","message":"일하는 중"}\n{"type":"system","subtype":"turn_duration"}\n' > "$JL"; TICK >/dev/null; eq "$(wc -l < "$ZLOG" | tr -d ' ')" 1 "ⓑ 쪽지가 없으면 같은 좌석을 재개(대조)"

# ── ⓖ 누적 정지: IDLE ≥10분 ∧ 받은 발주 0 · 바뀐 때만 · master 도 대상 ──
reset; W="byz-t-nano-w#0"; X="byz-t-nano-x2#0"; roster "$M:master:claude" "$P:planner:claude" "$N:nano:claude" "$W:nano:claude" "$X:nano:claude"
for s in "$M" "$P" "$N" "$W" "$X"; do k="${s//#/_}"; live "$s" "%$RANDOM" 1 "$RANDOM" "u-$k"; done
ago() { TZ=UTC date -v-"$1"M +%Y-%m-%dT%H:%M:%S; }
printf 'IDLE %s 5000 yes jsonl\n' "$(ago 15)" > "$T/turn.${N//#/_}"; printf 'IDLE %s 5000 yes jsonl\n' "$(ago 12)" > "$T/turn.${M//#/_}"; printf 'IDLE %s 5000 yes jsonl\n' "$(ago 3)" > "$T/turn.${P//#/_}"
printf 'IDLE %s 5000 yes jsonl\n' "$(ago 20)" > "$T/turn.${W//#/_}"; echo 1 > "$T/pend.${W//#/_}"
printf 'IDLE %s 5000 yes jsonl\n' "$(ago 20)" > "$T/turn.${X//#/_}"; printf '{"type":"assistant","message":"[완료·휴식] x"}\n{"type":"system","subtype":"turn_duration"}\n' > "$T/rest.jsonl"; echo "$T/rest.jsonl" > "$T/jl.${X//#/_}"
TICK >/dev/null; L="$(grep '정지' "$MLOG")"
has "$L" "send $M ft-tick [정지 15분] $N" "ⓖ 일반 좌석 정지는 master 에게"; has "$L" "send $P ft-tick [정지 12분] $M" "ⓖ master 정지는 planner 에게(master 도 대상)"
hasnt "$L" "$P role" "ⓖ 10분 미만은 알리지 않는다"; hasnt "$L" "$W" "ⓖ 받은 발주가 있으면(pending=1) 정지 아님"; hasnt "$L" "$X" "ⓖ 완료·휴식 좌석은 정지 아님"
TICK >/dev/null; eq "$(grep -c '정지' "$MLOG")" 2 "ⓖ 같은 정지는 반복 알림 0"
printf 'IDLE %s 5000 yes jsonl\n' "$(ago 11)" > "$T/turn.${N//#/_}"; TICK >/dev/null; eq "$(grep -c '정지' "$MLOG")" 3 "ⓖ 새 정지(turn_end 변화)는 다시 알린다"

# ── ⓕ spawn 카드 기준선: 성공 직후 기록 · 출력·exit 불변 · 쓰기 실패는 stderr 1줄 ──
R="$T/repo"; B="$T/sbin"; SS="$R/.fable-team/seats.json"; CARD="design/v65/indices/대기/r163x.md"; SF="$T/sfake"; mkdir -p "$R/.fable-team" "$R/design/v65/indices/대기" "$R/design/v65/indices/진행" "$B" "$T/sess" "$SF"
git -C "$R" init -q -b main && : > "$R/.gitkeep" && git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -q -m init
printf '# 인덱스: r163x\n## 상태\n' > "$R/$CARD"; printf 'x\n' > "$R/design/v65/SEATBELT-README.md"
cp -p "$BIN/ft-nano-spawn.sh" "$KIT/ft_raised.py" "$B/"
for f in ft-index-lint.sh ft-proposal-gate.sh ft-send-verified.sh ft-resource-gate.sh; do printf '#!/bin/bash\nexit 0\n' > "$B/$f"; done
printf '#!/bin/bash\nsrc="$1"; dst="${src/\\/대기\\//\\/진행\\/}"; mkdir -p "$(dirname "$dst")"; mv "$src" "$dst"\n' > "$B/ft-index-move.sh"
printf '#!/bin/bash\n[ "$1" = key ] && { echo k; exit 0; }\nexit 0\n' > "$B/ft-sheet-events.sh"
printf '#!/bin/bash\nif [ "$1" = open ]; then n=""; dry=0; while [ $# -gt 0 ]; do [ "$1" = --name ] && n="$2"; [ "$1" = --dry-run ] && dry=1; shift; done; [ $dry = 1 ] && echo "TMUXC-DRY $n" || : > "%s/sess/$n"; fi\n' "$T" > "$SF/tmuxc"
printf '#!/bin/bash\ncase "$1" in\n has-session) [ -e "%s/sess/${3#=}" ];;\n list-panes) for s in "%s"/sess/*; do [ -e "$s" ] && echo "$(basename "$s")|%%1|1700000000"; done; exit 0;;\n show-option) echo 1;;\n *) exit 0;;\nesac\n' "$T" "$T" > "$SF/tmux"
chmod +x "$B"/*.sh "$SF/tmuxc" "$SF/tmux"; printf '{"_master":"m#1","m#1":{"role":"master","agent":"claude","tick":null}}\n' > "$SS"
SP() { (cd "$R" && env PATH="$SF:$PATH" FT_SEATS_JSON="$SS" "$@" bash "$B/ft-nano-spawn.sh" "$R/${CARDX:-$CARD}" --from m#1 2>"$T/sp.err"); }
o="$(SP FT_NANO_CARD_BASE_DIR="$T/cb")"; has "$o" "SPAWNED " "ⓕ spawn 성공 출력 그대로"
NM="$(ls "$T/sess" | head -1)"; CBF="$T/cb/$NM.json"
[ -f "$CBF" ] && ok "ⓕ 기준선 파일 생김" || bad "ⓕ 기준선 파일 없음"
eq "$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["card_path"],d["branch"])' "$CBF")" "design/v65/indices/진행/r163x.md nano/r163x" "ⓕ card_path·branch"
eq "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["card_blob"])' "$CBF")" "$(git -C "$R" hash-object "$R/design/v65/indices/진행/r163x.md")" "ⓕ card_blob = git hash-object"
has "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["worktree"])' "$CBF")" "/.worktrees/v65-r163x" "ⓕ worktree"
eq "$(ls "$T/cb" | grep -c tmp)" 0 "ⓕ tmp 잔존 0"
printf '# 인덱스: r163y\n## 상태\n' > "$R/design/v65/indices/대기/r163y.md"; CARDX="design/v65/indices/대기/r163y.md"
: > "$T/blocker"; o="$(SP FT_NANO_CARD_BASE_DIR="$T/blocker/x")"; has "$o" "SPAWNED " "ⓕ 기준선 쓰기 실패여도 spawn 결과 그대로"; has "$(cat "$T/sp.err")" "WARN spawn 카드 기준선 쓰기 실패" "ⓕ 쓰기 실패 = stderr 1줄"

# ── 변이 3 (정본 실행에서만): 원장 선점 삭제 → ⓔ실패 · log 대조 삭제 → ②실패 · 문지기 검사 삭제 → ④실패 ──
if [ -z "${R163_BIN:-}" ]; then
  MB="$T/mut"; mkdir -p "$MB/a" "$MB/b" "$MB/c" "$MB/d"
  for d in a b c d; do cp -p "$BIN/ft-tick.sh" "$BIN/ft-resume-attempt.sh" "$BIN/ft-nano-spawn.sh" "$MB/$d/"; done
  python3 - "$MB" <<'PY'
import sys
mb = sys.argv[1]
def sub(p, a, b):
    s = open(p, encoding="utf-8").read(); assert a in s, (p, a); open(p, "w", encoding="utf-8").write(s.replace(a, b, 1))
sub(f"{mb}/a/ft-resume-attempt.sh", "try: os.mkdir(ledger(seat, uuid) + \".lock\")\n    except FileExistsError: die(", "try: pass\n    except FileExistsError: die(")
sub(f"{mb}/b/ft-resume-attempt.sh", "    return line in log", "    return True")
sub(f"{mb}/c/ft-tick.sh", "[ \"$rc\" = 0 ] || { lines+=\"$seat(자원 문지기 REJECT", "[ 0 = 0 ] || { lines+=\"$seat(자원 문지기 REJECT")
sub(f"{mb}/d/ft-resume-attempt.sh", "f[1] != seat or f[2] != uuid or ", "")
PY
  mut() { R163_BIN="$MB/$1" bash "$HERE/test_dead_seat_resume.sh" 2>&1 | grep '^FAIL' ; }
  o="$(mut a)"; has "$o" "ⓔ 원장 선점은 동시에 온 두 번째 호출을 막는다" "변이 1(원장 선점 삭제) → ⓔ 실패 검출"
  o="$(mut b)"; has "$o" "② .allow 직접 쓰기" "변이 2(log 대조 삭제) → ② 실패 검출"
  o="$(mut c)"; has "$o" "④ 자원 REJECT 면 zombie-clean 호출 0" "변이 3(문지기 검사 삭제) → ④ 실패 검출"
  o="$(mut d)"; has "$o" "③① 다른 좌석 토큰 → consume 거부" "변이 4(좌석·uuid 대조 제거) → ③① 실패 검출"
fi
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED=$fail"
exit "$fail"
