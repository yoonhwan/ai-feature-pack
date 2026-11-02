#!/usr/bin/env bash
# r1282 — ft_stall_scan 판정 단계 기한 D(기본 60 · 10~70 밖·숫자 아님 = 60) + 자식 묶음(프로세스 그룹) 정리 시험.
#   반례·계약 정본: design/harness/indices/진행/r1282-stall-scan-judge-phase-cap-child-group-kill.md (R1~R13 · R7b · 변이 10)
#   판정 기한 넘김 = 처리 0 · 상태 저장 0 · 1줄(stdout + stall-scan.log) · rc 3 / 처리 단계는 호출별 timeout 만(총 상한 0).
#   시험은 전부 스텁 세계(실 좌석 깨우기·ring·kill 0) · press 0 · 네트워크 0 · 자기 재호출 0.
# 사용: bash test_stall_scan_judge_cap_r1282.sh [fast|judge1|judge2|proc|mutate1|mutate2|mutate3|all]
#   단계마다 70초 안 · all 은 회차(7분) 안에서 단계를 이어 돌린다. 기본 = fast.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "$0")" && pwd)"
BINDIR="${BINDIR:-$(cd "$HERE/../../kit/fable-team/bin" && pwd)}"
NOW=1800000000
FAILED=0
PASS=0
BG=()

say() { printf '%s\n' "$*"; }
bad() { printf '  · 실패: %s\n' "$*" >&2; FAILED=1; STAGE_FAIL=1; }   # 실패 줄 하나도 단계 rc 에 누적
have() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
now_s() { python3 -c 'import time;print(f"{time.time():.2f}")'; }
el() { python3 -c "print(round($2-$1,2))"; }
le() { python3 -c "import sys;sys.exit(0 if $1<=$2 else 1)"; }
ge() { python3 -c "import sys;sys.exit(0 if $1>=$2 else 1)"; }
alive() { pgrep -f "grandson.py $1" >/dev/null 2>&1; }
iso() { python3 -c "import time;print(time.strftime('%Y-%m-%dT%H:%M:%S', time.gmtime($NOW-$1*60)))"; }   # turn TURN_END = UTC(ft-seat-status 꼴)
iso_local() { python3 -c "import time;print(time.strftime('%Y-%m-%dT%H:%M:%S', time.localtime($NOW-$1*60)))"; }  # mailbox ts = 로컬 시각(mbox 꼴)

# ── 스텁 세계 ────────────────────────────────────────────────────────────────
new_world() {
  W=$(mktemp -d "${TMPDIR:-/tmp}/r1282.XXXXXX")
  S="$W/stub"
  R="$W/repo"
  mkdir -p "$S/turn" "$S/jsonl" "$S/slow" "$S/grandbg" "$S/ignore-term" "$R/.fable-team/state" "$R/.fable-team/comm" \
    "$R/design" "$R/.worktrees/wt-t1/design/t1/indices/대기" "$R/.worktrees/wt-t1/design/t1/indices/진행"
  printf '# 팀 명단(시험)\n\n| 팀 | 폴더 | 상태 |\n|---|---|---|\n| t1 | `design/t1/` | 현역 |\n' > "$R/design/TEAMS.md"   # r1309 — 명부 정본 = design/TEAMS.md
  : > "$S/tmux"
  cat > "$S/seat-status.sh" <<'STUB'
#!/bin/sh
d="$FT_STUB/turn"
case "$1" in
  turn)
    s="$2"
    [ "$2" = --file ] && s=$(basename "$3" .jsonl)
    echo "$s" >> "$FT_STUB/turn.calls"
    [ -f "$FT_STUB/slow/$s" ] && sh "$FT_STUB/slow.sh" "$s"
    [ -f "$FT_STUB/grandbg/$s" ] && sh "$FT_STUB/grandbg.sh" "$s"
    cat "$d/$s" 2>/dev/null || echo "UNKNOWN - - - pane"
    ;;
  jsonl)
    [ -f "$FT_STUB/jsonl/$2.jsonl" ] && echo "$FT_STUB/jsonl/$2.jsonl" || exit 1
    ;;
esac
STUB
  cat > "$S/slow.sh" <<'STUB'
#!/bin/sh
# slow/<좌석> = "N:초" — N=0 이면 매 호출 · N=k 이면 k번째 호출만
v=$(cat "$FT_STUB/slow/$1")
nth=${v%%:*}
secs=${v#*:}
c=$(( $(cat "$FT_STUB/count.$1" 2>/dev/null || echo 0) + 1 ))
echo "$c" > "$FT_STUB/count.$1"
if [ "$nth" != 0 ] && [ "$c" != "$nth" ]; then exit 0; fi
sh "$FT_STUB/grandson.sh" "$1" >/dev/null 2>&1 &   # bg-ok: 손자는 호출의 프로세스 그룹에 남아야 한다(정리 대상 · 스텁은 회수된다)
sleep "$secs"
STUB
  cat > "$S/grandbg.sh" <<'STUB'
#!/bin/sh
# R13 — 호출은 곧바로 rc 0 으로 끝나지만 손자는 계속 산다(정상 종료 뒤 그룹 정리 확인용)
#   손자는 부모 파이프를 안 물려받는다 — 안 그러면 정리와 무관하게 communicate 가 EOF 를 못 본다
sh "$FT_STUB/grandson.sh" "$1" >/dev/null 2>&1 &   # bg-ok: R13 = 호출이 끝나도 남는 손자(그룹 정리 확인용 · 회수는 ft_stall_state.reap)
exit 0
STUB
  cat > "$S/grandson.sh" <<'STUB'
#!/bin/sh
exec python3 "$FT_STUB/grandson.py" "$1"
STUB
  cat > "$S/grandson.py" <<'STUB'
import os, signal, sys, time
name = sys.argv[1]
stub = os.environ["FT_STUB"]
if os.path.exists(os.path.join(stub, "ignore-term", name)):
    signal.signal(signal.SIGTERM, signal.SIG_IGN)   # TERM 을 무시하는 손자 — KILL 까지 가야 죽는다
path = os.path.join(stub, "hb." + name)
for _ in range(9000):
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(f"{time.time():.2f}\n")
    time.sleep(0.1)
STUB
  cat > "$S/tmux.sh" <<'STUB'
#!/bin/sh
case "$1" in
  list-sessions) cat "$FT_STUB/tmux" 2>/dev/null ;;
  list-panes)
    case "$*" in
      *pane_pid*) awk '{print $1"|75"}' "$FT_STUB/tmux" 2>/dev/null ;;
      *) awk '{print $1"|%"NR}' "$FT_STUB/tmux" 2>/dev/null ;;
    esac ;;
  send-keys) echo "$*" >> "$FT_STUB/tmux.log" ;;
esac
STUB
  cat > "$S/mbox.sh" <<'STUB'
#!/bin/sh
case "$1" in
  send)
    echo "send|$2|$3" >> "$FT_STUB/mbox.log"
    if [ -f "$FT_STUB/slowsend" ] && [ "$(cat "$FT_STUB/slowsend")" = "$2" ]; then
      sh "$FT_STUB/grandson.sh" send >/dev/null 2>&1 &   # bg-ok: TERM 무시 손자(R6·R10 = KILL 까지 가는지 보는 대상)
      sleep 40
    fi
    ;;
  ring) echo "ring|$2|" >> "$FT_STUB/mbox.log" ;;
esac
STUB
  cat > "$S/lint.sh" <<'STUB'
#!/bin/sh
exit 0
STUB
  cat > "$S/ps.sh" <<'STUB'
#!/bin/sh
cat "$FT_STUB/ps" 2>/dev/null
STUB
  cat > "$S/bad.sh" <<'STUB'
#!/bin/sh
exit 1
STUB
  cat > "$S/ctx.sh" <<'STUB'
#!/bin/sh
if [ -f "$FT_STUB/ctxsleep" ]; then
  sleep "$(cat "$FT_STUB/ctxsleep")"
  : > "$FT_STUB/ctx.done"      # 스스로 끝났다 = 호출 상한(7초)이 안 걸렸다
fi
echo 95
STUB
  cat > "$S/feed.py" <<'PY'
# FIFO 우편함 피더 — 줄 간격을 «마감 시각» 으로 잡아 드리프트 0
#   argv: fifo lead n1 g1 n2 g2
#   lead = 앞선 «빠른 회차» 수(1줄 즉시 EOF) · 1단계 n1줄을 g1 간격으로 · 2단계 n2줄을 g2 간격으로(빠른 꼬리)
#   왜 2단계인가: 판정측 기한 검사가 «줄 200개마다»라 한 번 놓치면 다음 검사가 200×g1 만큼 뒤다.
#   1단계가 D 를 살짝 넘기고, 2단계가 검사 간격을 200×g2 로 줄여 D 바로 뒤에서 잡히게 한다.
import sys, time
fifo, lead, n1, g1, n2, g2 = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), float(sys.argv[4]), int(sys.argv[5]), float(sys.argv[6])
line = '{"seq":1,"ts":"2026-01-01T00:00:00","to":"t1-master#1","from":"x","body":"발주"}'
for _ in range(lead):
    with open(fifo, "w", encoding="utf-8") as fh:
        fh.write(line + "\n")
t0 = time.time()
try:                             # 독자가 먼저 죽으면(판정 불가로 끝남) 조용히 끝난다
    with open(fifo, "w", encoding="utf-8") as fh:
        for i in range(n1):
            fh.write(line + "\n"); fh.flush()
            d = t0 + (i + 1) * g1 - time.time()
            if d > 0:
                time.sleep(d)
        for j in range(n2):
            fh.write(line + "\n"); fh.flush()
            d = t0 + n1 * g1 + (j + 1) * g2 - time.time()
            if d > 0:
                time.sleep(d)
except BrokenPipeError:
    pass
while True:                      # 뒤에 오는 리더는 즉시 EOF(블록 방지)
    try:
        open(fifo, "w").close()
    except OSError:
        break
PY
  : > "$S/ps"
  heartbeat          # 팀장 심박 = 신선한 [정리] 1통(없으면 팀장 심박 «판정 불가» = u)
  mk_env
}

heartbeat() {
  printf '{"seq":1,"ts":"%s","to":"t1-master#1","from":"t1-master#1","body":"[정리] 한 일 3줄"}\n' "$(iso_local 2)" \
    > "$R/.fable-team/comm/mailbox.jsonl"
}

mk_env() {   # 세계 환경변수 — export 로만 건다(h70 분류기: 변수·치환으로 실행 명령을 만들지 않는다)
  export FT_ROOT="$R" FT_STUB="$S" FT_NOW="$NOW"
  export FT_SEAT_STATUS="$S/seat-status.sh" FT_TMUX="$S/tmux.sh" FT_MBOX_SH="$S/mbox.sh"
  export FT_INDEX_LINT="$S/lint.sh" FT_MBOX_DIR="$R/.fable-team/comm"
  export FT_STALL_STATE_DIR="$R/.fable-team/state" FT_PS="$S/ps.sh" FT_CTX_CMD="$S/ctx.sh"
  export FT_SEAT_QUIESCE_BIN="$S/bad.sh"   # ft-child-watch 가 큐를 안 열고 즉시 끝나게(리더 수 고정)
  export FT_ROOTS_TSV="$S/no-roots.tsv"    # 기계 루트 명부 없음 = 단일 루트(실 기계 명부를 안 읽는다)
  unset FT_STALL_SCAN_TOTAL_S FT_STALL_PENALTY_TIMEOUT
}

add_team() {  # add_team <label> <master> [좌석...]
  local label=$1 master=$2
  shift 2
  local rows="{\"_master\":\"$master\",\"_label\":\"$label\",\"_cards\":\"design/$label/indices\",\"_cards_wt\":\"wt-$label\",\"$master\":{\"role\":\"master\"}"
  local s
  for s in "$@"; do rows="$rows,\"$s\":{\"role\":\"nano\"}"; done
  printf '%s}' "$rows" > "$R/.fable-team/seats-$label.json"
}

live() { printf '%s 0\n' "$1" >> "$S/tmux"; }

no_lead() {  # 팀장 행 role 을 nano 로 — lead_alert(우편함 두 번째 독자) 를 꺼 FIFO 독자를 하나로 고정한다
  python3 - "$R/.fable-team/seats-$1.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding="utf-8"))
for _k, v in d.items():
    if isinstance(v, dict) and v.get("role") == "master":
        v["role"] = "nano"
json.dump(d, open(p, "w", encoding="utf-8"))
PY
}
idle() { printf 'IDLE %s 1000 no jsonl\n' "$(iso "${2:-5}")" > "$S/turn/$1"; }
slow() { printf '%s\n' "$2" > "$S/slow/$1"; }
future_jsonl() {  # 미래형 선언으로 끝나는 마지막 턴(도구 0) → b
  printf '%s\n%s\n%s\n' \
    '{"type":"system","subtype":"turn_duration"}' \
    '{"type":"assistant","message":{"content":[{"type":"text","text":"이어서 진행하겠습니다"}]}}' \
    '{"type":"system","subtype":"turn_duration"}' > "$S/jsonl/$1.jsonl"
}

run_scan() { bash "$BINDIR/ft-stall-scan.sh" "$@"; }   # 세계 환경변수 = mk_env 가 export 한 것

rm_world() {
  local p
  for p in ${BG[@]+"${BG[@]}"}; do kill "$p" >/dev/null 2>&1; done
  BG=()
  # 손자·피더가 남으면 다음 케이스로 샌다
  pkill -f "$S/grandson.py" >/dev/null 2>&1
  [ -n "${W:-}" ] && rm -rf "$W"
  W=""
}

# FIFO 우편함 피더 — $1=fifo $2=줄수 $3=줄당 지연 $4=꼬리(초당 1줄, 초 · 0 이면 없음)
feed() { python3 "$S/feed.py" "$1" "$2" "$3" "$4" "${5:-0}" "${6:-0}" & BG+=($!); }

# ── R1 ─ 빠른 좌석 3 · 지금과 같은 요약 줄 · rc 0 · 처리·저장 그대로
c_R1() {
  new_world
  add_team t1 't1-master#1' 't1-nano#0' 't1-nano#1'
  live 't1-master#1'; live 't1-nano#0'; live 't1-nano#1'
  idle 't1-master#1'; idle 't1-nano#0'; idle 't1-nano#1'
  local t0 r rc out
  t0=$(now_s); out=$(run_scan 2>&1); rc=$?
  t1=$(now_s)
  say "  R1 rc=$rc elapsed=$(el "$t0" "$t1")"
  [ "$rc" = 0 ] || bad "R1 rc=$rc (0 이어야)"
  # h·u 칸의 h? 는 r1290 헤드라인 판정 몫(이 카드 밖) — 여기서는 기한 도입 전과 같은 a~e·seats 만 본다
  have "$out" "stall=0 a=0 b=0 c=0 d=0 e=0 seats=3" || bad "R1 요약 줄 다름: $(echo "$out" | head -1)"
  [ -f "$R/.fable-team/state/stall-scan.json" ] || bad "R1 상태 저장 0"
  have "$(cat "$R/.fable-team/state/stall-scan.log" 2>/dev/null)" "stall=0 a=0" || bad "R1 자기 로그 0"
  [ -f "$S/mbox.log" ] && bad "R1 쪽지 발신 있음(처리할 것 없음)"
  rm_world
  return "$FAILED"
}

# ── R2 ─ 느린 좌석 1(손자 띄우고 오래 잠) · D=10 → 판정 불가 1줄 · rc 3 · 손자 0 · 처리·저장 0 · ≤ D+1
c_R2() {
  new_world
  add_team t1 't1-master#1' 't1-nano#0' 't1-nano#1'
  live 't1-master#1'; live 't1-nano#0'; live 't1-nano#1'
  idle 't1-master#1'; idle 't1-nano#0'; idle 't1-nano#1'
  slow 't1-nano#0' '0:30'
  export FT_STALL_SCAN_TOTAL_S=10
  local t0 r rc out
  t0=$(now_s); out=$(run_scan 2>&1); rc=$?
  t1=$(now_s)
  local took; took=$(el "$t0" "$t1")
  say "  R2 rc=$rc elapsed=$took"
  [ "$rc" = 3 ] || bad "R2 rc=$rc (3 이어야) out=$(echo "$out" | head -3)"
  have "$out" "stall-scan 판정 불가 — 판정 기한 10 s 초과(좌석 " || bad "R2 판정 불가 1줄 없음: $(echo "$out" | head -2)"
  have "$out" "· 처리 0)" || bad "R2 «처리 0» 없음"
  have "$(cat "$R/.fable-team/state/stall-scan.log" 2>/dev/null)" "판정 불가 — 판정 기한 10 s 초과" || bad "R2 stall-scan.log 1줄 없음"
  [ -f "$R/.fable-team/state/stall-scan.json" ] && bad "R2 상태 파일 바뀜(저장 0 이어야)"
  [ -f "$R/.fable-team/state/stall-scan.last.json" ] && bad "R2 last.json 저장됨"
  [ -f "$S/mbox.log" ] && bad "R2 처리 쪽지 있음: $(cat "$S/mbox.log")"
  if alive 't1-nano#0'; then bad "R2 손자 생존"; fi
  le "$took" 11 && say "  R2 총 실행 $took ≤ D+1" || bad "R2 총 실행 $took > D+1"
  unset FT_STALL_SCAN_TOTAL_S FT_STALL_PENALTY_TIMEOUT
  rm_world
  return "$FAILED"
}

# ── R3 ─ R2 직후 다음 실행 → 잠금 잡힘(«앞 실행이 아직 돈다» 0)
c_R3() {
  new_world
  add_team t1 't1-master#1' 't1-nano#0' 't1-nano#1'
  live 't1-master#1'; live 't1-nano#0'; live 't1-nano#1'
  idle 't1-master#1'; idle 't1-nano#0'; idle 't1-nano#1'
  slow 't1-nano#0' '0:30'
  export FT_STALL_SCAN_TOTAL_S=10
  _=$(run_scan 2>&1)
  rm -f "$S/slow/t1-nano#0"
  local out rc
  out=$(run_scan 2>&1); rc=$?
  have "$out" "앞 실행이 아직 돈다" && bad "R3 잠금이 안 풀렸다"
  [ "$rc" = 0 ] || bad "R3 다음 실행 rc=$rc"
  unset FT_STALL_SCAN_TOTAL_S FT_STALL_PENALTY_TIMEOUT
  rm_world
  return "$FAILED"
}

# ── R4 ─ D 값: 500→60 · 1→60 · abc→60 · 20→20
c_R4() {
  local got
  for pair in '500:60' '1:60' 'abc:60' '20:20' '70:70' '71:60'; do
    got=$(cd "$BINDIR" && FT_STALL_SCAN_TOTAL_S="${pair%%:*}" python3 -c 'import ft_stall_state as s;print(f"{s.judge_budget():g}")' 2>&1)
    [ "$got" = "${pair##*:}" ] && say "  R4 ${pair%%:*} → $got" || bad "R4 ${pair%%:*} → $got (${pair##*:} 이어야)"
  done
  return "$FAILED"
}

# ── R5 ─ 판정은 기한 안 · b 깨우기 2좌석(빠른 스텁) → Escape·ring·쪽지 · handled · 처리 로그 · 처리 총 상한 0
c_R5() {
  new_world
  add_team t1 't1-master#1' 't1-nano#0' 't1-nano#1'
  live 't1-master#1'; live 't1-nano#0'; live 't1-nano#1'
  idle 't1-master#1'; idle 't1-nano#0'; idle 't1-nano#1'
  future_jsonl 't1-nano#0'; future_jsonl 't1-nano#1'
  local out rc
  out=$(run_scan 2>&1); rc=$?
  say "  R5 rc=$rc b=$(have "$out" " b=2 " && echo 2 || echo '?')"
  [ "$rc" = 0 ] || bad "R5 rc=$rc"
  have "$out" "b=2" || bad "R5 b=2 아님: $(echo "$out" | head -1)"
  [ "$(grep -c 'send-keys' "$S/tmux.log" 2>/dev/null)" = 2 ] || bad "R5 Escape 2회 아님: $(cat "$S/tmux.log" 2>/dev/null | tr '\n' ' ')"
  [ "$(grep -c '^ring|t1-nano#0|' "$S/mbox.log" 2>/dev/null)" = 1 ] || bad "R5 ring t1-nano#0 아님"
  [ "$(grep -c '^ring|t1-nano#1|' "$S/mbox.log" 2>/dev/null)" = 1 ] || bad "R5 ring t1-nano#1 아님"
  [ "$(grep -c '^send|t1-nano#' "$S/mbox.log" 2>/dev/null)" = 2 ] || bad "R5 쪽지 2통 아님: $(cat "$S/mbox.log" 2>/dev/null | tr '\n' ' ')"
  have "$(cat "$R/.fable-team/state/stall-scan.json")" 'b:t1-nano#0' || bad "R5 handled 기록 0"
  have "$(cat "$R/.fable-team/state/stall-scan.log")" 'act=b to=t1-nano#0' || bad "R5 처리 로그 0"
  rm_world
  return "$FAILED"
}

# ── R6 ─ 처리 단계 호출(쪽지)이 TERM 무시 손자를 띄우고 호출별 timeout 넘김 → 실패 rc 갈래 · 손자 0 · 저장 계속
c_R6() {
  new_world
  add_team t1 't1-master#1' 't1-nano#0' 't1-nano#1'
  live 't1-master#1'; live 't1-nano#0'; live 't1-nano#1'
  idle 't1-master#1'; idle 't1-nano#0'; idle 't1-nano#1'
  future_jsonl 't1-nano#0'
  echo 't1-nano#0' > "$S/slowsend"; : > "$S/ignore-term/send"   # 처리 단계 쪽지(b) = 40초 잠 · TERM 무시 손자
  local t0 r rc out took
  t0=$(now_s); out=$(run_scan 2>&1); rc=$?
  took=$(el "$t0" "$(now_s)")
  say "  R6 rc=$rc elapsed=$took"
  [ "$rc" = 0 ] || bad "R6 rc=$rc (0 — 처리는 계속)"
  have "$(cat "$R/.fable-team/state/stall-scan.json" 2>/dev/null)" 'b:t1-nano#0' || bad "R6 handled 저장 0"
  have "$(cat "$R/.fable-team/state/stall-scan.log" 2>/dev/null)" 'act=b to=t1-nano#0' || bad "R6 처리 로그 0"
  if alive send; then bad "R6 손자 생존(KILL 까지 안 감)"; fi
  le "$took" 20 && say "  R6 호출 상한 15초에서 끊김($took)" || bad "R6 15초 상한 아님($took)"
  rm_world
  return "$FAILED"
}

# ── R7 ─ 외부 호출 없이 우편함 읽기만으로 판정 기한 넘김(200줄 검사가 잡음) · --dry-run → rc 3 · ≤ D+1
c_R7() {
  new_world
  add_team t1 't1-master#1' 't1-nano#0' 't1-nano#1'
  live 't1-master#1'; live 't1-nano#0'; live 't1-nano#1'
  idle 't1-master#1'; idle 't1-nano#0'; idle 't1-nano#1'
  no_lead t1                                  # FIFO 독자 = 큐 읽기 하나
  rm -f "$R/.fable-team/comm/mailbox.jsonl"; mkfifo "$R/.fable-team/comm/mailbox.jsonl"
  feed "$R/.fable-team/comm/mailbox.jsonl" 0 400 0.024 2500 0.002   # --dry-run 이라 ft-child-watch 0 · 1단계 400줄=9.6초(200줄 검사 4.8·9.6초 모두 D 안) → 2단계 빠른 꼬리(검사 간격 0.4초)로 D 직후에 잡힘 · 변이 5(200줄 검사 제거)면 꼬리 5초를 더 읽어 총 > D+1
  export FT_STALL_SCAN_TOTAL_S=10
  local t0 r rc out took
  t0=$(now_s); out=$(run_scan --dry-run 2>&1); rc=$?
  took=$(el "$t0" "$(now_s)")
  say "  R7 rc=$rc elapsed=$took"
  [ "$rc" = 3 ] || bad "R7 rc=$rc (3)"
  have "$out" "판정 불가 — 판정 기한 10 s 초과" || bad "R7 판정 불가 1줄 없음: $(echo "$out" | head -2)"
  le "$took" 11 && say "  R7 총 실행 $took ≤ D+1" || bad "R7 총 실행 $took > D+1"
  [ -f "$S/mbox.log" ] && bad "R7 dry-run 인데 쪽지"
  unset FT_STALL_SCAN_TOTAL_S FT_STALL_PENALTY_TIMEOUT
  rm_world
  return "$FAILED"
}

# ── R7b ─ 마지막 외부 호출이 D−1.3초에 끝나고, 이어지는 파일 판정(우편함 150줄 · 200줄 검사 미발동)이 1.6초
#          → «판정 끝» 검사만 잡는다(외부 호출 0 구간의 초과 · 변이 4 를 가른다)
c_R7b() {
  local out rc
  out=$(cd "$BINDIR" && FT_STALL_SCAN_TOTAL_S=10 python3 - <<'PY' 2>&1
import sys, time
import ft_stall_state as stm
stm.begin()                 # 판정 단계 시작(기준 시각 = main 진입)
time.sleep(8.7)             # 마지막 외부 호출이 끝난 시각 = D − 1.3
time.sleep(1.6)             # 이어지는 파일 판정 — 외부 호출 0
try:
    stm.judge_done()        # 판정 끝 검사
except stm.JudgeTimeout:
    print("JUDGE-END-CAUGHT")
    sys.exit(3)
print("NOT-CAUGHT")
sys.exit(0)
PY
)
  rc=$?
  say "  R7b rc=$rc $out"
  [ "$rc" = 3 ] || bad "R7b rc=$rc (3 — 판정 끝 검사가 잡아야)"
  have "$out" "JUDGE-END-CAUGHT" || bad "R7b 판정 끝 검사가 안 잡음: $(echo "$out" | head -2)"
  return "$FAILED"
}

# ── R8 ─ ctx 스텁이 8초 뒤 95 반환 · 기한 여유 → 호출 상한 7초 그대로(e 판정 지금과 같음)
c_R8() {
  new_world
  add_team t1 't1-master#1' 't1-nano#0' 't1-nano#1'
  live 't1-master#1'; live 't1-nano#0'; live 't1-nano#1'
  idle 't1-master#1'; idle 't1-nano#0'; idle 't1-nano#1'
  live 'stray#1'; idle 'stray#1' 40          # 명부 밖 라이브 좌석 = e 후보
  printf '75 1 claude --resume\n' > "$S/ps"
  echo 8 > "$S/ctxsleep"
  local t0 r rc out took
  t0=$(now_s); out=$(run_scan 2>&1); rc=$?
  took=$(el "$t0" "$(now_s)")
  say "  R8 rc=$rc elapsed=$took $(echo "$out" | head -1)"
  [ "$rc" = 0 ] || bad "R8 rc=$rc"
  have "$out" "e=1" || bad "R8 e=1 아님(판정이 지금과 달라짐): $(echo "$out" | head -3)"
  have "$out" "ctx ?" || bad "R8 «ctx ?» 없음"
  [ -f "$S/ctx.done" ] && bad "R8 ctx 가 스스로 끝남(7초 상한 안 걸림 · elapsed $took)" || say "  R8 ctx 호출 7초 상한에서 잘림(elapsed $took)"
  le "$took" 9.5 || bad "R8 elapsed $took (9.5 초과)"
  rm_world
  return "$FAILED"
}

# ── R9 ─ 판정 단계 TERM 무시 손자 · D=10 → 만료·KILL·scan 끝 시각 기록 · KILL ≤ 시작+D · 손자 0
c_R9() {
  new_world
  add_team t1 't1-master#1' 't1-nano#0' 't1-nano#1'
  live 't1-master#1'; live 't1-nano#0'; live 't1-nano#1'
  idle 't1-master#1'; idle 't1-nano#0'; idle 't1-nano#1'
  slow 't1-nano#0' '0:30'
  : > "$S/ignore-term/t1-nano#0"
  export FT_STALL_SCAN_TOTAL_S=10
  local t0 r rc out took kill
  t0=$(now_s); out=$(run_scan 2>&1); rc=$?
  took=$(el "$t0" "$(now_s)")
  kill=$(python3 - "$S/hb.t1-nano#0" "$t0" <<'PY'
import sys
try:
    last = float(open(sys.argv[1]).read().split()[-1])
except (OSError, IndexError, ValueError):
    last = 0.0
print(round(last - float(sys.argv[2]), 2) if last else -1)
PY
)
  say "  R9 rc=$rc elapsed=$took kill=+${kill}s (D=10 · 손자 마지막 심박으로 잰 KILL 시각)"
  [ "$rc" = 3 ] || bad "R9 rc=$rc (3)"
  if ge "$kill" 0; then
    le "$kill" 10 && say "  R9 KILL 시각 +${kill}s ≤ 시작+D" || bad "R9 KILL 시각 +${kill}s > 시작+D"
  else
    bad "R9 손자 심박 기록 0(측정 불가)"
  fi
  if alive 't1-nano#0'; then bad "R9 손자 생존(TERM 무시 → KILL 까지 안 감)"; fi
  le "$took" 13 && say "  R9 scan 끝 +${took}s(TERM 무시 손자 → KILL 회수 몫)" || bad "R9 scan 끝 +$took s (D+3 초과)"
  unset FT_STALL_SCAN_TOTAL_S FT_STALL_PENALTY_TIMEOUT
  rm_world
  return "$FAILED"
}

# ── R10 ─ 페널티 켜짐 · 발신이 TERM 무시 손자를 띄우고 상한 넘김 → 그 발신 실패 rc · 손자 0 · 처리·handled 저장 계속
c_R10() {
  new_world
  add_team t1 't1-master#1' 't1-nano#0' 't1-nano#1'
  live 't1-master#1'; live 't1-nano#0'; live 't1-nano#1'
  idle 't1-master#1'; idle 't1-nano#0'; idle 't1-nano#1'
  future_jsonl 't1-nano#0'
  printf '{"handled":{"t1-nano#0":%s},"prev":["b:t1-nano#0"],"seats":{}}' "$NOW" > "$R/.fable-team/state/stall-scan.json"   # 처리 뒤에도 또 감지 = 페널티 켜짐
  echo 't1-master#1' > "$S/slowsend"; : > "$S/ignore-term/send"   # 페널티 발신(팀장)만 느리게
  export FT_STALL_PENALTY_TIMEOUT=2
  local t0 r rc out took
  t0=$(now_s); out=$(run_scan 2>&1); rc=$?
  took=$(el "$t0" "$(now_s)")
  say "  R10 rc=$rc elapsed=$took"
  [ "$rc" = 0 ] || bad "R10 rc=$rc"
  have "$out" "ft_penalty: 쪽지 발신 실패" || bad "R10 발신 실패 rc 줄 없음: $(echo "$out" | head -3)"
  have "$(cat "$R/.fable-team/state/stall-scan.log" 2>/dev/null)" "b:t1-nano#0" || bad "R10 처리 로그 0"
  have "$(cat "$R/.fable-team/state/stall-scan.json" 2>/dev/null)" 'b:t1-nano#0' || bad "R10 handled 저장 0"
  if alive send; then bad "R10 손자 생존"; fi
  le "$took" 12 && say "  R10 페널티 발신 상한 2초에서 끊김($took)" || bad "R10 발신 상한 안 걸림($took)"
  unset FT_STALL_SCAN_TOTAL_S FT_STALL_PENALTY_TIMEOUT
  rm_world
  return "$FAILED"
}

# ── R11 ─ 파일 판정 뒤 경과 9.2초 · 다음 외부 호출 필요 → 부르지 않고 판정 불가 · rc 3 · 처리 0
c_R11() {
  new_world
  add_team t1 't1-master#1' 't1-nano#0' 't1-nano#1'
  live 't1-master#1'; live 't1-nano#0'; live 't1-nano#1'
  idle 't1-master#1'; idle 't1-nano#0'; idle 't1-nano#1'
  no_lead t1                                  # FIFO 독자 = 큐 읽기 하나
  rm -f "$R/.fable-team/comm/mailbox.jsonl"; mkfifo "$R/.fable-team/comm/mailbox.jsonl"
  feed "$R/.fable-team/comm/mailbox.jsonl" 0 400 0.0245 0 0        # 400줄 ≈ 9.8초 — 피더가 판정 시작보다 조금 먼저 떠도 EOF 가 기한(D−1=9초) 뒤 · D(10초) 앞에 온다
  export FT_STALL_SCAN_TOTAL_S=10
  local t0 r rc out took
  t0=$(now_s); out=$(run_scan --dry-run 2>&1); rc=$?   # --dry-run: 판정 경로는 같고 ft-child-watch 만 0
  took=$(el "$t0" "$(now_s)")
  say "  R11 rc=$rc elapsed=$took turn_calls=$(cat "$S/turn.calls" 2>/dev/null | wc -l | tr -d ' ')"
  [ "$rc" = 3 ] || bad "R11 rc=$rc (3)"
  have "$out" "판정 불가 — 판정 기한 10 s 초과" || bad "R11 판정 불가 1줄 없음"
  say "  R11 다음 외부 호출 $(cat "$S/turn.calls" 2>/dev/null | wc -l | tr -d ' ')회(부하에 따라 기한 안쪽에서 1~N회 — «부르지 않음» 판별은 R11(c) 단위 구동이 맡는다)"
  # R11(c) — 예산 0 이하 = «부르지 않고» 판정 불가(단위 구동 · 경과 9.5초를 sleep 없이 만든다 · 변이 7 을 가른다)
  local z
  z=$(cd "$BINDIR" && FT_STALL_SCAN_TOTAL_S=10 python3 - <<'PY' 2>&1
import sys, time
import ft_stall_state as stm
stm.begin()
stm._J["t0"] = time.monotonic() - 9.5          # 경과 9.5초 = D−0.5 → 남은 예산 -0.5
open("/tmp/r1282-mark.sh", "w").write("#!/bin/sh\n: > /tmp/r1282-called\n")   # 불리면 자국을 남긴다
try:
    stm.grun(["bash", "/tmp/r1282-mark.sh"], None, 15)
except stm.JudgeTimeout:
    print("BUDGET0-CAUGHT")
    sys.exit(3)
print("BUDGET0-MISSED")
sys.exit(0)
PY
)
  rm -f /tmp/r1282-called /tmp/r1282-mark.sh
  [ "$z" = "BUDGET0-CAUGHT" ] && say "  R11(c) 예산 0 이하 → 부르지 않고 JudgeTimeout" || bad "R11(c) 예산 0 이하인데 호출/일반 실패로 넘김: $z"
  [ -f "$R/.fable-team/state/stall-scan.json" ] && bad "R11 처리·저장 있음"
  unset FT_STALL_SCAN_TOTAL_S FT_STALL_PENALTY_TIMEOUT
  rm_world
  return "$FAILED"
}

# ── R12 ─ D=10 · e 후보 ctx 호출을 경과 5초에 시작 · 4.5초 뒤 95 → 기한 때문에 4.0초에 잘림 → 판정 불가(e «제외» 아님)
#          같은 스텁이 경과 1초 시작이면 4.5초에 95 → e 판정 지금과 같음
c_R12() {
  new_world
  add_team t1 't1-master#1' 't1-nano#0' 't1-nano#1'
  live 't1-master#1'; live 't1-nano#0'; live 't1-nano#1'
  idle 't1-master#1'; idle 't1-nano#0'; idle 't1-nano#1'
  live 'stray#1'; idle 'stray#1' 40
  printf '75 1 claude --resume\n' > "$S/ps"
  echo 4.5 > "$S/ctxsleep"
  slow 't1-nano#1' '0:5'          # 판정 5초 경과 뒤 ctx 시작
  export FT_STALL_SCAN_TOTAL_S=10
  local t0 r rc out took
  t0=$(now_s); out=$(run_scan 2>&1); rc=$?
  took=$(el "$t0" "$(now_s)")
  say "  R12(a) rc=$rc elapsed=$took t0=$t0"; say "$out" | sed 's/^/    | /' 
  [ "$rc" = 3 ] || bad "R12(a) rc=$rc (3 — 기한 잘림은 e «제외» 가 아니다)"
  have "$out" "판정 불가 — 판정 기한 10 s 초과" || bad "R12(a) 판정 불가 1줄 없음"
  # R12(c) — 기한 때문에 잘린 호출은 «호출 실패» 가 아니라 판정 불가(단위 구동 · 경과 8.8초를 sleep 없이 만든다)
  local cut
  cut=$(cd "$BINDIR" && FT_STALL_SCAN_TOTAL_S=10 FT_STUB="$S" python3 - <<'PY' 2>&1
import sys, time
import ft_stall_state as stm
stm.begin()
stm._J["t0"] = time.monotonic() - 8.8      # 경과 8.8초(= D − 1.2) — 남은 예산 1.2초
open("/tmp/r1282-slow-ctx.sh", "w").write("#!/bin/sh\nsleep 5\necho 95\n")   # 호출 상한 7초 · 스텁 5초 → 기한에 잘린다
try:
    stm.grun(["bash", "/tmp/r1282-slow-ctx.sh"], None, 7)
except stm.JudgeTimeout:
    print("CUT-CAUGHT")
    sys.exit(3)
print("CUT-MISSED")
sys.exit(0)
PY
)
  [ "$cut" = "CUT-CAUGHT" ] && say "  R12(c) 기한 잘림 → JudgeTimeout" || bad "R12(c) 기한 잘림을 일반 실패로 넘김: $cut"
  rm -f "$S/slow/t1-nano#1" "$S/count.t1-nano#1"
  local out2 rc2 t2 took2
  t2=$(now_s); out2=$(run_scan 2>&1); rc2=$?
  took2=$(el "$t2" "$(now_s)")
  say "  R12(b) rc=$rc2 elapsed=$took2 $(echo "$out2" | head -1)"
  [ "$rc2" = 0 ] || bad "R12(b) rc=$rc2 (0 — 기한 안 실행은 지금과 같다)"
  have "$out2" "e=1" || bad "R12(b) e=1 아님: $(echo "$out2" | head -3)"
  le "$took2" 8 && say "  R12(b) ctx 4.5초 그대로($took2)" || bad "R12(b) ctx 시간 이상($took2)"
  unset FT_STALL_SCAN_TOTAL_S FT_STALL_PENALTY_TIMEOUT
  rm_world
  return "$FAILED"
}

# ── R13 ─ 호출이 출력을 파일로 돌린 손자를 백그라운드로 띄우고 rc 0 → 호출 끝 뒤 그룹 정리 · 손자 0
c_R13() {
  new_world
  add_team t1 't1-master#1' 't1-nano#0' 't1-nano#1'
  live 't1-master#1'; live 't1-nano#0'; live 't1-nano#1'
  idle 't1-master#1'; idle 't1-nano#0'; idle 't1-nano#1'
  : > "$S/grandbg/t1-master#1"
  local t0 r rc out took
  t0=$(now_s); out=$(run_scan 2>&1); rc=$?
  took=$(el "$t0" "$(now_s)")
  say "  R13 rc=$rc elapsed=$took"
  [ "$rc" = 0 ] || bad "R13 rc=$rc"
  have "$out" "stall=0" || bad "R13 요약 줄 없음: $(echo "$out" | head -2)"
  if alive 't1-master#1'; then bad "R13 정상 종료 뒤 손자 생존(그룹 정리 0)"; fi
  rm_world
  return "$FAILED"
}

# ── 변이 ────────────────────────────────────────────────────────────────────
mut_copy() {  # 변이용 bin 사본
  MB="$W/mbin"
  cp -R "$BINDIR" "$MB"
  BINDIR_SAVE="$BINDIR"
  BINDIR="$MB"
}

mut_restore() {
  BINDIR="$BINDIR_SAVE"
}

mutate() {  # $1 = 이름 · $2 = python 패치 코드 — 바뀐 파일이 없으면 «MUT-NOCHANGE» 로 실패(조용한 통과 0)
  local name=$1 code=$2 out
  out=$(python3 - "$MB" <<PY
import hashlib, pathlib, sys
d = pathlib.Path(sys.argv[1])
before = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in d.glob("*.py")}
$code
after = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in d.glob("*.py")}
print("MUTATED" if before != after else "MUT-NOCHANGE")
PY
)
  if ! have "$out" "MUTATED"; then
    say "  ✗ 변이 $name 적용 실패($out) — 패치 무효"
    STAGE_FAIL=1
    return 1
  fi
}

run_case() {  # $1 = 케이스 함수 이름 — 케이스 하나라도 실패하면 단계 rc 1(중간 실패를 삼키지 않는다)
  FAILED=0
  local t0 rc
  t0=$(now_s)
  "$1"
  rc=$?
  say "  ─ $1 rc=$rc ($(el "$t0" "$(now_s)")초)"
  [ "$rc" = 0 ] || STAGE_FAIL=1
  return "$rc"
}

mutant() {  # $1 = 변이 이름 · $2 = 케이스 · $3 = python 패치 — 적용 실패·생존은 단계 rc 1
  local name=$1 case=$2 code=$3
  BINDIR_BASE="$BINDIR"
  local rc t0
  FAILED=0
  t0=$(now_s)
  W_MUT=$(mktemp -d "${TMPDIR:-/tmp}/r1282m.XXXXXX")
  MB="$W_MUT/bin"
  cp -R "$BINDIR_BASE" "$MB"
  BINDIR="$MB"
  mutate "$name" "$code" || return 0   # 패치 실패는 이미 STAGE_FAIL(그 줄에서 처리)
  local saved=$STAGE_FAIL
  STAGE_FAIL=0                          # 변이 케이스의 실패 = 기대값 — 판정은 아래 생존/죽음으로만
  "$case"
  rc=$?
  STAGE_FAIL=$saved
  BINDIR="$BINDIR_BASE"
  rm -rf "$W_MUT"
  if [ "$rc" = 0 ]; then
    say "  ✗ 변이 $name 살아남음($case 통과) — 시험이 약하다"
    STAGE_FAIL=1
  else
    say "  ✓ 변이 $name → $case FAIL(죽음)"
  fi
  say "  ─ 변이 $name ($(el "$t0" "$(now_s)")초)"
  return 0
}

stage_fast() {
  run_case c_R1; PASS=$((PASS+1))
  run_case c_R4
  run_case c_R5
  run_case c_R8
  run_case c_R13
}

stage_judge1() { run_case c_R2; run_case c_R3; run_case c_R7; run_case c_R7b; }
stage_judge2() { run_case c_R9; run_case c_R11; run_case c_R12; }
stage_proc() { run_case c_R6; run_case c_R10; }

stage_mutate1() {   # 기한 검사·자식 정리 기본 갈래(빠른 케이스 중심)
  mutant '판정기한검사제거' c_R2 '
p = d / "ft_stall_state.py"; s = p.read_text()
s = s.replace("    if _J[\"on\"] and time.monotonic() - _J[\"t0\"] > _J[\"d\"]:\n        raise JudgeTimeout", "    return")
s = s.replace("    end = min(call_end, _J[\"t0\"] + _J[\"d\"] - 1.0) if judging else call_end", "    end = call_end")
p.write_text(s)'
  mutant '자식묶음정리제거' c_R2 '
p = d / "ft_stall_state.py"; s = p.read_text()
s = s.replace("start_new_session=True", "start_new_session=False")
s = s.replace("def reap(p: subprocess.Popen, grace: float) -> None:", "def reap(p: subprocess.Popen, grace: float) -> None:\n    return")
p.write_text(s)'
  mutant '호출상한15고정' c_R8 '
p = d / "ft_stall_state.py"; s = p.read_text()
s = s.replace("    call_end = time.monotonic() + timeout", "    call_end = time.monotonic() + 15")
p.write_text(s)'
  mutant '정상종료뒤정리제거' c_R13 '
p = d / "ft_stall_state.py"; s = p.read_text()
s = s.replace("    reap(p, grace)\n    return p.returncode, out", "    return p.returncode, out")
p.write_text(s)'
}

stage_mutate2() {   # 파일 판정·페널티 발신 갈래
  mutant '판정끝검사제거' c_R7b '
p = d / "ft_stall_state.py"; s = p.read_text()
s = s.replace("def judge_done() -> None:\n    check()", "def judge_done() -> None:\n    return")
p.write_text(s)'
  mutant '우편함200줄검사제거' c_R7 '
p = d / "ft_stall_detect.py"; s = p.read_text()
s = s.replace("            if i % 200 == 199:\n                stm.check()\n", "")
p.write_text(s)'
  mutant '페널티옛subprocess' c_R10 '
p = d / "ft_penalty.py"; s = p.read_text()
s = s.replace("    rc, out = run([\"bash\", sh, \"send\"", "    rr = subprocess.run([\"bash\", sh, \"send\"")
s = s.replace(", timeout=timeout)\n    if rc != 0:", ", capture_output=True, text=True, timeout=timeout)\n    rc, out = rr.returncode, rr.stdout\n    if rc != 0:")
p.write_text(s)'
}

stage_mutate3() {   # 예산·유예·기한 잘림 갈래
  mutant '유예1초제거' c_R9 '
p = d / "ft_stall_state.py"; s = p.read_text()
s = s.replace("_J[\"t0\"] + _J[\"d\"] - 1.0", "_J[\"t0\"] + _J[\"d\"]")
p.write_text(s)'
  mutant '예산0이하일반실패' c_R11 '
p = d / "ft_stall_state.py"; s = p.read_text()
s = s.replace("    if judging and end - time.monotonic() <= 0:\n        raise JudgeTimeout", "    if judging and end - time.monotonic() <= 0:\n        end = call_end")
p.write_text(s)'
  mutant '기한잘림일반실패' c_R12 '
p = d / "ft_stall_state.py"; s = p.read_text()
s = s.replace("        if judging and end < call_end:\n            raise JudgeTimeout\n", "")
p.write_text(s)'
}

load() { python3 -c 'import os;p=os.getloadavg();print(f"{p[0]:.2f}/{p[1]:.2f}/{p[2]:.2f}")'; }

main() {
  local stage=${1:-fast}
  STAGE_FAIL=0
  say "r1282 판정 기한 시험 — bin=$BINDIR stage=$stage load=$(load) cpu=$(sysctl -n hw.ncpu 2>/dev/null || echo ?)"
  case "$stage" in
  fast) stage_fast ;;
  judge1) stage_judge1 ;;
  judge2) stage_judge2 ;;
  proc) stage_proc ;;
  mutate1) stage_mutate1 ;;
  mutate2) stage_mutate2 ;;
  mutate3) stage_mutate3 ;;
  all|stages)   # 회차(7분) 안에서 단계를 이어 돌린다 — 단계마다 초·부하를 찍는다
    local t0 one
    for one in fast judge1 judge2 proc mutate1 mutate2 mutate3; do
      t0=$(now_s)
      "stage_$one"
      say "  ─ 단계 $one $(el "$t0" "$(now_s)")초 load=$(load)"
    done ;;
  c_*) run_case "$stage" ;;   # 단일 케이스(디버그)
  *) say "usage: bash $(basename "$0") [fast|judge1|judge2|proc|mutate1|mutate2|mutate3|stages|all|c_<케이스>]"; return 2 ;;
  esac
  if [ "$STAGE_FAIL" = 0 ]; then say "OK (rc 0) load=$(load)"; else say "FAIL (rc 1) load=$(load)"; fi
  return "$STAGE_FAIL"
}

trap 'rm_world >/dev/null 2>&1' EXIT
main "$@"
