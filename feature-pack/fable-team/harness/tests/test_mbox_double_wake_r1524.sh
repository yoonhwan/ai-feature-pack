#!/usr/bin/env bash
# test_mbox_double_wake_r1524.sh — r1524: «받는 쪽» 판정 ext_wake_seat(seats-planner _master·_desk ∧ 확장 설치본) + doorbell 미읽음 0 = 주입 0
#  · 보내는 쪽 사람 판정(user_facing)·_wg_human_sender 는 그대로(DA #276770 R2) · 사람 손 ring 은 그대로(R1)
#  · 자동 ring(ft-idle-wake)은 --auto 1낱말로 구별 — 확장 좌석이면 주입 0 · 출력 doorbell=ext
#  · 이미 읽은 seq 로 다시 깨우기 0 — doorbell 이 주입 직전에 미읽음을 세고 0 이면 doorbell=none(판정 불가 = 기존대로 주입 · fail-loud)
#  격리: 임시 박스(.fable-team/{comm,state}) · FT_MBOX_DIR·FT_MBOX_STATE_DIR·TMPDIR · 임시 명부(FT_SEATS_JSON) ·
#        가짜 tmux(pane 목록·send-keys 기록) · 가짜 ps · 가짜 HOME(확장 설치본 있음/없음) · 가짜 시계(FT_MBOX_NOW) ·
#        실 우편함·실 pane·실 명부 0 · 자기 재호출 0 · sleep 0
#  사례 ①~㉕ + 변이 5. (판 2 = ⑳~㉕ 팀 명부 판정) ⑫(기존 회귀)는 합이 커서 FT_R1524_REGRESSION=1 일 때만 돈다(사례 70초 예산 밖 · 카드 «회차» 예산 안).
#  ⑱⑲ = 적재와 주입 사이에 수신자가 recv 를 끝낸 경합(DA #276870 R1 두 입력 — send·relay) — «방금 적재» 는 미읽음을 보장하지 않는다.
set -uo pipefail
# 예산 상한을 시험이 스스로 소유한다(기본 100000 · test_mbox_doorbell_merge_r1476.sh:10 과 같은 이유)
export FT_MBOX_WAKE_SEAT_MAX=6 FT_MBOX_WAKE_TEAM_MAX=30
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; COMM="$REPO/harness/comm"; IDLE="$REPO/harness/bin/ft-idle-wake.sh"
BASE_PATH="$PATH"   # ⑫ 회귀 자식에게는 이 시험의 가짜 tmux/ps 가 없는 PATH 를 준다(가짜 tmux 가 자식의 실 tmux -L 을 가린다)
T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (기대 '$3' 실제 '$2')"; fi; }

# ── fakebin: tmux(pane 목록·send-keys 기록·세션 있음·클라이언트 없음) / ps(pane 아래 claude 본체) ───────────────
mkdir -p "$T/fakebin"
cat > "$T/fakebin/tmux" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${TMUX_LOG:-/dev/null}"
case "${1:-}" in
  list-panes)
    shift
    if [ "${1:-}" = "-a" ]; then
      # ★r1524 경합 훅(사례 ⑱⑲)★ — 적재와 주입 «사이» 에 수신자가 recv 를 끝낸 상태를 만든다(DA #276870 R1 두 입력).
      #   실 pane 0 · sleep 0 · 한 번만(표식) · 격리 큐 그대로.
      if [ -n "${RACE_C:-}" ] && [ ! -f "$RACE_C/received-once" ]; then
        python3 "$RACE_C/mbox.py" recv "$RACE_SEAT" > "$RACE_C/receiver.log" 2>&1
        echo "$?" > "$RACE_C/receiver.rc"; : > "$RACE_C/received-once"
      fi
      i=0; for s in ${TMUX_SEATS:-}; do i=$((i+1)); printf '%s|%%%d\n' "$s" "$i"; done
    else
      printf '%s\n' "${TMUX_PANE_PID:-900001}"
    fi
    exit 0;;
  has-session|list-clients) exit 0;;
  display-message) printf 'node\n'; exit 0;;
  send-keys) exit 0;;
esac
exit 1
EOF
cat > "$T/fakebin/ps" <<'EOF'
#!/bin/sh
printf '%s\n' '900001     1 S    /bin/zsh' '900002 900001 S    /usr/bin/claude --dangerously-skip-permissions' '900003 900001 S    /usr/local/bin/codex'
EOF
printf '#!/bin/sh\nexit 1\n' > "$T/failpeek.sh"
cat > "$T/seat-status.sh" <<'EOF'
#!/bin/bash
echo "IDLE 2026-11-09T20:00:00 1000 yes jsonl"
EOF
chmod +x "$T/fakebin/tmux" "$T/fakebin/ps" "$T/failpeek.sh"
# 가짜 HOME 두 개 — 확장 설치본 있음 / 없음(⑮). ext_wake_seat 은 «파일 존재» 만 본다.
mkdir -p "$T/ext/.pi/agent/extensions" "$T/nohome"
: > "$T/ext/.pi/agent/extensions/ft-mbox-wake.ts"
printf 'relay 본문\n' > "$T/relay.txt"

# ── 명부 3벌: 정상 / planner 명부 없음 / planner 명부 깨짐(⑪) ────────────────────────────────────────────
SEATS='{"gn#1":{"agent":"claude","team":"h1","tick":null},
 "gn2#1":{"agent":"claude","team":"h1","tick":null},"s1#1":{"agent":"claude","team":"h1","tick":null},
 "bm#1":{"agent":"pi","team":"h1","tick":null}}'
for d in ok nopj broken; do mkdir -p "$T/seats-$d"; printf '%s\n' "$SEATS" > "$T/seats-$d/seats.json"; done
# ⑪ 은 planner 명부가 없거나(nopj) 깨져서(broken) «중복 등록» 이 없다 → seats.json 에 pm#1·dm#1 행을 둔다(ft-agent-alive 생존 판정용)
for d in nopj broken; do python3 - "$T/seats-$d/seats.json" <<'PYJSON'
import json, sys
p = sys.argv[1]; d = json.load(open(p, encoding="utf-8"))
d["pm#1"] = {"agent": "pi", "team": "h1"}; d["dm#1"] = {"agent": "claude", "team": "h1"}
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False)
PYJSON
done
printf '%s\n' '{"_master":"pm#1","_desk":"dm#1","pm#1":{"role":"master","agent":"pi"},"dm#1":{"role":"desk","agent":"pi"}}' > "$T/seats-ok/seats-planner.json"   # 실제 명부처럼 좌석 행도 있다
printf '%s\n' '{깨진' > "$T/seats-broken/seats-planner.json"
# ★판 2 팀 명부★ — hm#1 = pi master · cm#1 = claude master · im#1 = codex master · nm#1 = pi 나노 · bm#1 = 깨진 파일이 주장하는 pi master
printf '%s\n' '{"_master":"hm#1","hm#1":{"agent":"pi","team":"hh1","tick":null},"nm#1":{"agent":"pi","team":"hh1","tick":null}}' > "$T/seats-ok/seats-harness.json"
printf '%s\n' '{"_master":"cm#1","cm#1":{"agent":"claude","team":"c1","tick":null}}' > "$T/seats-ok/seats-cfo.json"
printf '%s\n' '{"_master":"im#1","im#1":{"agent":"codex","team":"i1","tick":null}}' > "$T/seats-ok/seats-issues.json"
printf '%s\n' '{"_master":"bm#1","bm#1":{"agent":"pi"},"x":' > "$T/seats-ok/seats-broken.json"   # JSON 오류(그 파일만 거짓)

ALLSEATS="dm#1 pm#1 gn#1 gn2#1 s1#1 hm#1 cm#1 im#1 nm#1 bm#1"   # pm#1·dm#1 = seats-planner.json 행(중복 등록 0)
export PATH="$T/fakebin:$PATH" FT_PS_CMD="$T/fakebin/ps" FT_AGENT_ALIVE_TIMEOUT=2 \
       TMUX_LOG="$T/tmux.log" TMUX_SEATS="$ALLSEATS" FT_BIN="$T/nobin" \
       FT_MBOX_RECV_LIMIT=50 FT_MBOX_RATE_N=1000 FT_MBOX_RESEND_COOLDOWN=0
: > "$TMUX_LOG"

# 가짜 시계 — 한 시간 창 안에서 출발(창 경계 = 472223).
W0=1700002800; NOW="$W0"
BOX=""; C=""
mkbox() {
  local r="$T/box-$1"
  mkdir -p "$r/.fable-team/comm" "$r/.fable-team/state" "$r/tmp"
  cp "$COMM"/mbox*.sh "$COMM"/mbox*.py "$COMM"/ft-agent-alive.sh "$r/.fable-team/comm/"
  printf '{}\n' > "$r/.fable-team/seats.json"       # ft-idle-slot-fill 이 볼 v65 명부 — 팀장 없음 = 채우기 0
  : > "$r/.fable-team/comm/mailbox.jsonl"
  printf '%s' "$r"
}
use() { BOX="$1"; C="$BOX/.fable-team/comm"; SEATDIR="${2:-$T/seats-ok}"; EXT_HOME="${3:-$T/ext}"
        export FT_MBOX_DIR="$C" FT_MBOX_STATE_DIR="$BOX/.fable-team/state" TMPDIR="$BOX/tmp"; : > "$BOX/err"; : > "$TMUX_LOG"; }
run() {  # <가짜시각> <mbox.sh 하위명령…> → OUT·RC·ERR
  NOW="$1"; shift
  OUT="$(HOME="$EXT_HOME" FT_SEATS_JSON="$SEATDIR/seats.json" FT_MBOX_NOW="$NOW" bash "$C/mbox.sh" "$@" 2>"$BOX/err")"; RC=$?
  ERR="$(cat "$BOX/err" 2>/dev/null)"
}
S()  { run "$NOW" send "$@"; }
R()  { run "$NOW" recv "$@"; }
nv() { printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | head -1; }
inj() { local n; n="$(grep -c "recv $1" "$TMUX_LOG" 2>/dev/null)"; printf '%s' "${n:-0}"; }
pend() { nv "$(FT_MBOX_NOW="$NOW" python3 "$C/mbox.py" peek "$1" 2>/dev/null)" pending; }
heldput() { mkdir -p "$BOX/.fable-team/state/doorbell-held"
  printf 'held ts=%s reason=%s window=%s seat=%s\nseq=%s\n' "$1" "$2" "$3" "$4" "$5" > "$BOX/.fable-team/state/doorbell-held/$4"; }
heldn() { cat "$BOX/.fable-team/state/doorbell-held/$1" 2>/dev/null; }
budput() { mkdir -p "$BOX/.fable-team/state/wake-budget"; printf '{"window": %s, "n": %s}' "$1" "$2" > "$BOX/.fable-team/state/wake-budget/$3.json"; }
ago() { date -r "$(( $(date +%s) - $1 ))" +%Y%m%d%H%M.%S; }
stamps() { touch -t "$(ago "$3")" "$TMPDIR/mbox-recv-$1"; touch -t "$(ago "$2")" "$TMPDIR/mbox-doorbell-$1"; }

# ── 사례 ①②③④⑤ (박스 하나에서 순서대로 — 같은 좌석의 미읽음이 사례마다 쌓인다) ───────────────────────
use "$(mkbox main)"; NOW="$W0"
S dm#1 s1#1 "① 확장 _desk 쪽지"                       # 확장 설치본 있음 ∧ _desk
eq "① send → _desk gate=quiet" "$(nv "$OUT" gate)" quiet
eq "① send → _desk doorbell=quiet" "$(nv "$OUT" doorbell)" quiet
eq "① send → _desk pane 주입 0" "$(inj dm#1)" 0
eq "① 큐에는 들어갔다(pending 1)" "$(pend dm#1)" 1
S pm#1 s1#1 "② 확장 _master 쪽지"                    # 판정 876 회귀
grep -q 'doorbell=quiet' <<<"$OUT" && ok "② send → _master doorbell=quiet(876)" || bad "② send → _master doorbell=quiet(876)" "$OUT"
eq "② send → _master pane 주입 0" "$(inj pm#1)" 0
S gn#1 s1#1 "③ 일반 좌석 쪽지"                        # 명부 밖(planner 아님) = 기존 경로
eq "③ send → 일반 좌석 gate=sent" "$(nv "$OUT" gate)" sent
eq "③ send → 일반 좌석 doorbell=sent" "$(nv "$OUT" doorbell)" sent
eq "③ send → 일반 좌석 pane 주입 1" "$(inj gn#1)" 1
run "$NOW" relay dm#1 s1#1 "$T/relay.txt" "④ relay 요약"
eq "④ relay → _desk doorbell=quiet" "$(nv "$OUT" doorbell)" quiet
eq "④ relay → _desk pane 주입 0" "$(inj dm#1)" 0
eq "④ relay 도 큐에 들어갔다(pending 2)" "$(pend dm#1)" 2
run "$NOW" ring dm#1 1                                # ⑤ 사람 손 ring(--auto 없음) · 미읽음 2
eq "⑤ 손 ring → _desk doorbell=sent(사람 손 허용)" "$(nv "$OUT" doorbell)" sent
eq "⑤ 손 ring → _desk pane 주입 1" "$(inj dm#1)" 1

# ── 사례 ⑥⑦⑧⑨⑩ — 미읽음 0 = 주입 0 · 판정 불가·굶김가드·force 는 그대로 주입 ──────────────────────
R gn#1 >/dev/null                                      # ⑥ 미읽음 0 만들기(다 읽었다)
eq "⑥ recv 뒤 pending 0" "$(pend gn#1)" 0
run "$NOW" ring gn#1 1
eq "⑥ ring · 미읽음 0 → doorbell=none" "$(nv "$OUT" doorbell)" none
eq "⑥ ring · 미읽음 0 → pane 주입 0" "$(inj gn#1)" 1   #③의 1회만 = 이번 ring 은 0
stamps gn#1 200 300                                    # ⑦ 굶김 상한 경로(doorbell > recv · 120초 지남) · 미읽음 0
run "$NOW" ring gn#1 1
eq "⑦ 굶김 상한 경로 · 미읽음 0 → doorbell=none" "$(nv "$OUT" doorbell)" none
eq "⑦ 굶김 상한 경로 · 미읽음 0 → pane 주입 0" "$(inj gn#1)" 1
stamps gn#1 200 300; S gn#1 s1#1 "⑧ 굶김 상한 경로 · 미읽음 1"    # ⑧ 같은 경로 · 미읽음 1 = 굶김 방지 유지
eq "⑧ 굶김 상한 경로 · 미읽음 1 → doorbell=sent" "$(nv "$OUT" doorbell)" sent
eq "⑧ 굶김 상한 경로 · 미읽음 1 → pane 주입 1" "$(inj gn#1)" 2
export FT_MBOX_PEEK_CMD="$T/failpeek.sh"               # ⑨ 미읽음 조회 실패 = 울리는 쪽(fail-loud)
run "$NOW" ring gn2#1 1                                # ring 경로 = 미읽음 검사를 실제로 문다(적재 직후인 send 는 면제)
eq "⑨ peek 실패 → doorbell=sent" "$(nv "$OUT" doorbell)" sent
eq "⑨ peek 실패 → pane 주입 1" "$(inj gn2#1)" 1
unset FT_MBOX_PEEK_CMD
S gn2#1 s1#1 "[인계] a -> b · 항목 0"                  # ⑩ [인계] force 경로(r1160) — 미읽음 ≥1 이라 그대로
eq "⑩ [인계] gate=sent" "$(nv "$OUT" gate)" sent
eq "⑩ [인계] doorbell=sent" "$(nv "$OUT" doorbell)" sent
eq "⑩ [인계] pane 주입 1" "$(inj gn2#1)" 2

# ── 사례 ⑪ planner 명부 없음·깨짐 = user_facing·ext_wake_seat 거짓(기존 pane 경로 · 주입) ─────────────
for d in nopj broken; do
  use "$(mkbox pj-$d)" "$T/seats-$d"; NOW="$W0"
  S dm#1 s1#1 "⑪ planner 명부 $d"
  eq "⑪ planner 명부 $d → doorbell=sent(기존 경로)" "$(nv "$OUT" doorbell)" sent
  eq "⑪ planner 명부 $d → pane 주입 1" "$(inj dm#1)" 1
done

# ── 사례 ⑮⑯ 보내는 쪽 사람 판정 불변(user_facing·_wg_human_sender 그대로) ───────────────────────────
use "$(mkbox human)" "" "$T/nohome"; NOW="$W0"          # 확장 설치본 없음 = ext 판정 0
budput 472223 6 gn#1                                    # 일반 수신 좌석 예산 소진(상한 2)
S gn#1 pm#1 "⑮ _master 발신 · 일반 본문"               # 발신 = planner _master = 사람
eq "⑮ 확장 없음 · 사람 발신 → gate=sent(예외 base 그대로)" "$(nv "$OUT" gate)" sent
budput 472223 6 gn2#1
S gn2#1 dm#1 "⑯ _desk 발신 · 일반 본문"                 # 발신 = _desk(확장 설치) — 사람 예외 «새로 생김 0»
eq "⑯ _desk 발신 · 예산 소진 → gate=budget" "$(nv "$OUT" gate)" budget
eq "⑯ _desk 발신 · pane 주입 0" "$(inj gn2#1)" 0

# ── 사례 ⑰ sweep 억제분이 확장 _desk 에 남음 = nudge · 주입 0 ────────────────────────────────────────
use "$(mkbox sweep)"; NOW="$W0"
heldput "$W0" held 472223 dm#1 "seq=55"
NOW=$((W0 + 400)); run "$NOW" sweep
eq "⑰ sweep → 확장 _desk followup" "$(nv "$OUT" followup)" dm#1
grep -q 'via=nudge' <<<"$OUT" && ok "⑰ sweep → via=nudge" || bad "⑰ sweep → via=nudge" "$OUT"
eq "⑰ sweep → 확장 _desk pane 주입 0" "$(inj dm#1)" 0
eq "⑰ nudge 파일 1" "$(ls "$BOX/.fable-team/state/pi-wake" 2>/dev/null | grep -c '\.nudge$')" 1
[ -z "$(heldn dm#1)" ] && ok "⑰ held 삭제(doorbell=sent)" || bad "⑰ held 삭제(doorbell=sent)"

# ── 사례 ⑳~㉕ 판 2 — 넓힌 판정 = 각 팀 _master(그 행 agent=='pi') ∨ planner _desk ∧ 확장 설치본 ──────────
use "$(mkbox team)"; NOW="$W0"
S hm#1 s1#1 "⑳ harness pi master 쪽지"
eq "⑳ 팀 pi master → pane 주입 0" "$(inj hm#1)" 0
eq "⑳ 팀 pi master → gate=quiet" "$(nv "$OUT" gate)" quiet
S cm#1 s1#1 "㉑ cfo claude master 쪽지"
eq "㉑ 팀 claude master → pane 주입 1(그 좌석엔 확장 없음)" "$(inj cm#1)" 1
S im#1 s1#1 "㉒ issues codex master 쪽지"
eq "㉒ 팀 codex master → pane 주입 1" "$(inj im#1)" 1
S nm#1 s1#1 "㉕ 같은 팀 pi 나노 쪽지"
eq "㉕ pi 나노(_master 아님) → pane 주입 1" "$(inj nm#1)" 1
S bm#1 s1#1 "㉔ 깨진 명부가 주장하는 pi master 쪽지"
eq "㉔ 깨진 명부 파일 좌석 → pane 주입 1" "$(inj bm#1)" 1
S hm#1 s1#1 "㉔ 다른 파일(seats-harness) 판정은 그대로"
eq "㉔ 깨진 파일이 다른 파일 판정을 막지 않는다(주입 0 유지)" "$(inj hm#1)" 0
EXT_HOME="$T/nohome"; S hm#1 s1#1 "㉓ 확장 설치본 없음"
eq "㉓ 확장 파일 없음 → pane 주입 1(깨움 0 금지)" "$(inj hm#1)" 1
EXT_HOME="$T/ext"

# ── 사례 ⑱⑲ 경합 2입력 — 적재와 주입 사이에 수신자가 recv 를 끝내면 «이미 읽은» 이라 주입 0 (DA #276870 R1) ──
for mode in send relay; do
  use "$(mkbox race-$mode)"; NOW="$W0"; export RACE_C="$C" RACE_SEAT="gn#1"   # RACE_* = 가짜 tmux 의 경합 훅
  if [ "$mode" = send ]; then S gn#1 s1#1 "⑱⑲ 일반 좌석 경합"
  else run "$NOW" relay gn#1 s1#1 "$T/relay.txt" "⑱⑲ 일반 좌석 경합 relay"; fi
  eq "⑱⑲ $mode 수신자는 실제로 읽었다(recv rc 0)" "$(cat "$C/receiver.rc" 2>/dev/null)" 0
  eq "⑱⑲ $mode 주입 시점 미읽음 0" "$(pend gn#1)" 0
  eq "⑱⑲ $mode 이미 읽은 뒤 pane 주입 0" "$(inj gn#1)" 0
  eq "⑱⑲ $mode doorbell=none" "$(nv "$OUT" doorbell)" none
  unset RACE_C RACE_SEAT
done

# ── 사례 ⑬⑭ ft-idle-wake 자동 ring = --auto 1낱말 (확장 좌석 pane 0 · 손 ring 은 주입) ────────────────
wake() {  # <박스> <가짜시각> — 실제 ft-idle-wake 1회 (ring 인자를 남기려고 mbox.sh 를 얇게 감싼다)
  local w="$1/mbox-wrap.sh"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/args.log"\nexec bash "%s/mbox.sh" "$@"\n' "$1" "$C" > "$w"
  TMUX_LOG="$TMUX_LOG" TMUX_SEATS="$ALLSEATS" FT_ROOT="$1" FT_MBOX="$w" \
  FT_SEAT_STATUS="$T/seat-status.sh" FT_TMUX="$T/fakebin/tmux" FT_IDLE_WAKE_NOW="$2" \
  FT_SEATS_JSON="$SEATDIR/seats.json" HOME="$EXT_HOME" TMPDIR="$BOX/tmp" \
  FT_MBOX_DIR="$C" FT_MBOX_STATE_DIR="$BOX/.fable-team/state" PATH="$PATH" \
  bash "$IDLE" >"$BOX/wake.out" 2>&1
}
use "$(mkbox idle)"; NOW="$(date +%s)"   # ft-idle-wake 는 큐 ts(실 시각)로 나이를 잰다 — 가짜 시계는 여기서 못 쓴다
S dm#1 s1#1 "⑬ 자동 ring 대상"                          # 확장 좌석 = quiet(주입 0) 이지만 큐에 1통
wake "$BOX" "$((NOW + 200))"
eq "⑬ ft-idle-wake 자동 ring → 확장 _desk pane 주입 0" "$(inj dm#1)" 0
grep -q 'doorbell=ext' "$BOX/.fable-team/state/idle-wake.log" 2>/dev/null && ok "⑬ 로그 doorbell=ext" \
  || bad "⑬ 로그 doorbell=ext" "$(tail -2 "$BOX/.fable-team/state/idle-wake.log" 2>/dev/null)"
grep -qE 'ring dm#1 [0-9]+ --auto' "$BOX/args.log" 2>/dev/null && ok "⑬ ring 인자에 --auto 1낱말" \
  || bad "⑬ ring 인자에 --auto 1낱말" "$(cat "$BOX/args.log" 2>/dev/null)"
run "$NOW" ring dm#1 1                                  # ⑭ 같은 좌석 손 ring(--auto 없음)
eq "⑭ 손 ring → 확장 _desk doorbell=sent" "$(nv "$OUT" doorbell)" sent
eq "⑭ 손 ring → 확장 _desk pane 주입 1" "$(inj dm#1)" 1

# ── 변이 3 — 계약이 실제로 «그 줄»에 걸려 있는지 확인(각 변이는 그 사례를 FAIL 로 만든다) ──────────────
mutbox() {  # <이름> <sed 스크립트> <파일> → 변이 박스 경로
  local r; r="$(mkbox "mut-$1")"
  sed -i '' "$2" "$r/.fable-team/comm/$3" || { echo "MUT-SED-FAIL $1" >&2; }
  printf '%s' "$r"
}
# 변이 1: ext_wake_seat 이 _master 만 본다(원래 판정 = _master·_desk) → 사례 ① 이 FAIL 이어야 한다
c1() { use "$1"; NOW="$W0"; S dm#1 s1#1 "변이 ① 재현"; [ "$(nv "$OUT" doorbell)" = quiet ] && [ "$(inj dm#1)" = 0 ]; }
B="$(mutbox m1 's/if os.path.basename(f) == "seats-planner.json" and j.get("_desk") == seat:/if False:/' mbox.sh)"
c1 "$B" && bad "변이 1(planner _desk 절 끔) 이 ① 을 안 잡음" || ok "변이 1(planner _desk 절 끔) → ① FAIL 확인"
# 변이 2: 미읽음 0 검사를 끈다 → 사례 ⑥⑦ 이 FAIL 이어야 한다
c67() { use "$1"; NOW="$W0"; S gn#1 s1#1 "변이 미읽음 0 재현"; R gn#1 >/dev/null
  run "$NOW" ring gn#1 1; [ "$(nv "$OUT" doorbell)" = none ] && [ "$(inj gn#1)" = 1 ]; }
B="$(mutbox m2 's/if \[ "\$_pn" = 0 \]; then echo none; return 0; fi/:/' mbox_doorbell.sh)"
c67 "$B" && bad "변이 2(미읽음 0 검사 끔) 이 ⑥ 을 안 잡음" || ok "변이 2 → ⑥ FAIL 확인"
# 변이 3: ring 이 --auto 를 무시한다 → 사례 ⑬ 이 FAIL 이어야 한다
c13() { use "$1"; NOW="$W0"; S dm#1 s1#1 "변이 ⑬ 재현"
  wake "$BOX" "$((W0 + 200))"; [ "$(inj dm#1)" = 0 ] && grep -q 'doorbell=ext' "$BOX/.fable-team/state/idle-wake.log" 2>/dev/null; }
B="$(mutbox m3 's/if \[ "\$_auto" = 1 \] && ext_wake_seat "\$sess"; then echo "RING \$sess doorbell=ext"; exit 0; fi/:/' mbox.sh)"
c13 "$B" && bad "변이 3(--auto 무시) 이 ⑬ 을 안 잡음" || ok "변이 3 → ⑬ FAIL 확인"

# 변이 5: agent=='pi' 검사를 끈다(이름만 _master) → 사례 ㉑ 이 FAIL 이어야 한다
c21() { use "$1"; NOW="$W0"; S cm#1 s1#1 "변이 ㉑ 재현"; [ "$(inj cm#1)" = 1 ]; }
B="$(mutbox m5 's/row.get("agent") == "pi"/row.get("agent") is not None/' mbox.sh)"
grep -q 'row.get("agent") is not None' "$B/.fable-team/comm/mbox.sh" || bad "변이 5 sed 미적용"
c21 "$B" && bad "변이 5(agent==pi 검사 끔) 가 ㉑ 을 안 잡음" || ok "변이 5 → ㉑ FAIL 확인"

# 변이 4: 미읽음 검사를 «면제» 한다(고치기 전 fresh=1 꼴 — DA #276870 R1 그 자리) → 사례 ⑱ 이 FAIL 이어야 한다
c18() { use "$1"; NOW="$W0"; export RACE_C="$C" RACE_SEAT="gn#1"
  S gn#1 s1#1 "변이 ⑱ 재현"; unset RACE_C RACE_SEAT
  [ "$(inj gn#1)" = 0 ] && [ "$(nv "$OUT" doorbell)" = none ]; }
B="$(mutbox m4 's/^  _pn="\$(_db_pending "\$to")"$/  _pn=1/' mbox_doorbell.sh)"
grep -q '^  _pn=1$' "$B/.fable-team/comm/mbox_doorbell.sh" || bad "변이 4 sed 미적용" "$(grep -n '_pn=' "$B/.fable-team/comm/mbox_doorbell.sh" | head -3)"
c18 "$B" && bad "변이 4(미읽음 검사 면제) 가 ⑱ 을 안 잡음" || ok "변이 4 → ⑱ FAIL 확인"

# ── 사례 ⑫ 기존 깨움 시험 5개 회귀 0 (합 80초 — 사례 70초 예산 밖이라 FT_R1524_REGRESSION=1 로만) ──────
if [ "${FT_R1524_REGRESSION:-0}" = 1 ]; then
  for t in test_mbox_doorbell_merge_r1476.sh test_mbox_doorbell_merge_r1476b.sh test_pi_mbox_wake_r1477.sh \
           test_mbox_handover_doorbell_force_r1160.sh test_ft_idle_wake.sh; do
    # ★자식에게 이 시험의 격리 env 를 물려주지 않는다★ — 물려주면 자식의 「실 상태」 판정·잠금 대기가 늘어 70초를 넘는다(rc=124 실측).
    env -u FT_MBOX_DIR -u FT_MBOX_STATE_DIR -u TMPDIR -u FT_SEATS_JSON -u TMUX_LOG -u TMUX_SEATS \
        -u FT_PS_CMD -u FT_BIN -u FT_MBOX_PEEK_CMD -u FT_MBOX_RECV_LIMIT -u FT_MBOX_RATE_N \
        -u FT_MBOX_RESEND_COOLDOWN -u FT_MBOX_WAKE_SEAT_MAX -u FT_MBOX_WAKE_TEAM_MAX -u FT_AGENT_ALIVE_TIMEOUT \
        PATH="$BASE_PATH" timeout 70 bash "$HERE/$t" >"$T/reg-$t.log" 2>&1; rc=$?
    eq "⑫ $t rc=0(base 와 같음)" "$rc" 0
  done
else
  echo "SKIP ⑫ 기존 5개 회귀 — FT_R1524_REGRESSION=1 로 따로 돈다(합 90초 · 사례 70초 예산 밖)"
fi

echo "---"; [ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL $fail"; exit 1; }
