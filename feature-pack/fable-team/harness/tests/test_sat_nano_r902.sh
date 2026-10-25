#!/usr/bin/env bash
# ft-sat-nano.sh 시험 (r902) — ssh·tmux·tmuxc·pgrep·lsof «대역» 만. 실 mini 접속 0 · 제품 쪽지함 쓰기 0 · 실 tmux 세션 0 · 실 프로세스 기동 0.
#   덮는 것: ⓐ open(사전점검 REJECT·pi 기동 HARD GATE·TASK.md·기록) ⓑ task(전달·중복 0·남의 세션 0) ⓒ pull(배달·ack·2번 배달 0)
#            ⓓ fetch·close(이 도구가 연 것만·닫기 확인 실패 rc6·강제 kill 0) ⓕ 변이 3개(dedupe 끔·opened 검사 끔·7초 룰)
#   실행: env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE bash tests/test_sat_nano_r902.sh
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
HARNESS="$(cd "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$HARNESS/bin/ft-sat-nano.sh"; KIT="$HARNESS/kit/fable-team/bin"
T="$(mktemp -d)"; RH="$T/rhome"; FB="$T/fakebin"; RSESS="$T/remote-sessions"; SEND="$T/sendlog"
RDIR="Project/satellite-nano/r1"; RMBOX="$T/rmbox"; MACBOX="$T/macbox"
mkdir -p "$FB" "$MACBOX" "$RMBOX"; : >"$RSESS"; : >"$SEND"; : >"$T/pi-pids"
trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=1; }
instate() { cut -f1 "$SAT_STATE_DIR/opened.tsv" 2>/dev/null | grep -qxF -- "$1"; }
macn() { python3 -c 'import json,os,sys
p=os.path.join(os.environ["FT_MBOX_DIR"],"mailbox.jsonl")
print(sum(1 for l in open(p) if l.strip() and json.loads(l).get("to")==sys.argv[1]) if os.path.exists(p) else 0)' "$1" 2>/dev/null; }

# ── 대역 (실 프로세스·실 tmux 0) ───────────────────────
cat >"$FB/ssh" <<'EOF'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do case "$1" in -o|-l|-p|-i) shift 2;; -*) shift;; *) break;; esac; done
shift 2>/dev/null || exit 255          # host(mini)
cmd="$*"; pf='export PATH=/opt/homebrew/bin:$HOME/.local/bin:$PATH; '
export HOME="$FAKE_RHOME" PATH="$FAKE_BIN:$PATH" FT_MBOX_DIR="$FAKE_RMBOX"
exec bash -c "${cmd#"$pf"}"            # 대역 원격에는 그 PATH 접두가 필요 없다(tmux 스텁이 이겨야 한다)
EOF
cat >"$FB/tmuxc" <<'EOF'
#!/usr/bin/env bash
[ "$1" = open ] || { echo "tmuxc: unsupported $*" >&2; exit 2; }
dir="$2"; shift 2; name=""
while [ $# -gt 0 ]; do case "$1" in --name) name="$2"; shift 2;; --agent|--role|--model|--effort) shift 2;; *) shift;; esac; done
[ -d "$dir" ] || exit 3
printf '%s\n' "$name" >>"$FAKE_SESS"
echo "OPEN ok name=$name pane_pid=4242"
EOF
cat >"$FB/tmux" <<'EOF'
#!/usr/bin/env bash
sub="$1"; shift; tgt=""; args="$*"
while [ $# -gt 0 ]; do case "$1" in -t) tgt="$2"; shift 2;; *) shift;; esac; done
tgt="${tgt#=}"; tgt="${tgt%:}"
case "$sub" in
  has-session) grep -qxF -- "$tgt" "$FAKE_SESS" ;;
  display)     grep -qxF -- "$tgt" "$FAKE_SESS" && echo 4242 || exit 1 ;;
  send-keys)   echo "$tgt|$args" >>"$FAKE_SEND" ;;
  kill-session) grep -qxF -- "$tgt" "$FAKE_SESS" || exit 1; grep -vxF -- "$tgt" "$FAKE_SESS" >"$FAKE_SESS.t"; mv "$FAKE_SESS.t" "$FAKE_SESS" ;;
  *) exit 1 ;;
esac
EOF
cat >"$FB/pgrep" <<'EOF'
#!/usr/bin/env bash
case "$1" in -P) echo 4243 ;; -x) cat "$FAKE_PI_PIDS" ;; esac
EOF
cat >"$FB/lsof" <<'EOF'
#!/usr/bin/env bash
[ -n "${FAKE_PI_CWD:-}" ] && printf 'n%s\n' "$FAKE_PI_CWD"; exit 0
EOF
printf '#!/bin/sh\nexit 0\n' >"$FB/pi"
chmod 755 "$FB"/*
export FAKE_RHOME="$RH" FAKE_BIN="$FB" FAKE_SESS="$RSESS" FAKE_SEND="$SEND" FAKE_RMBOX="$RMBOX" FAKE_PI_PIDS="$T/pi-pids"
export SAT_STATE_DIR="$T/state" SAT_MINI_MBOX_PY="$KIT/ft-mbox.py" SAT_MBOX_SH="$KIT/ft-mbox.sh"
export SAT_OUT_DIR="$T/out" FT_MBOX_DIR="$MACBOX" PATH="$FB:$PATH"
SEAT='byz-sat-nano-pi#0'; FOREIGN='other-tool-nano#0'

# ── ⓐ open — 사전점검 · 세션 1 · TASK.md · 기록 1행 ─────
printf '요약하라. 끝에 SAT-DONE host=x 한 줄.\n' >"$T/card.md"
o1="$(bash "$TOOL" open "$T/card.md" --run r1 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && grep -q "OPEN ok" <<<"$o1" && [ -s "$RH/$RDIR/TASK.md" ] && grep -qxF "$SEAT" "$RSESS" \
  && [ "$(awk -F'\t' '{print $1}' "$SAT_STATE_DIR/opened.tsv" | grep -cxF "$SEAT")" = 1 ] \
  && grep -q "^$SEAT|.*TASK.md" "$SEND" && grep -q "3/4 pi 기동 확인" <<<"$o1"; } \
  && ok "ⓐ open: pi 기동 HARD GATE 통과 · 세션 1 · TASK.md 사본 · 기록 1행 · 지시 전달" || bad "ⓐ open rc=$rc: $o1"

o2="$(bash "$TOOL" open "$T/card.md" --run r1 --name byz-sat-nano-pi#1 2>&1)"; rc2=$?
printf '%s\n' "$FOREIGN" >>"$RSESS"
o3="$(bash "$TOOL" open "$T/card.md" --run r2 --name "$FOREIGN" 2>&1)"; rc3=$?
o4="$(bash "$TOOL" open "$T/card.md" --run r1 --name byz-sat-nano-pi#2 2>&1)"; rc4=$?
{ [ "$rc2" = 2 ] && grep -q "폴더가 이미 있다" <<<"$o2" && [ "$rc3" = 2 ] && grep -q "남의 세션이라 건드리지 않는다" <<<"$o3" \
  && [ "$rc4" = 2 ] && grep -q "폴더가 이미 있다" <<<"$o4" && [ ! -d "$RH/Project/satellite-nano/r3" ] && ! grep -qxF 'byz-sat-nano-pi#2' "$RSESS"; } \
  && ok "ⓐ-2 open 재실행 = 폴더 REJECT(새 폴더 생성 0) · 남의 이름 세션 있음 = REJECT(덮지 않음)" || bad "ⓐ-2 rc=$rc2/$rc3/$rc4: $o2 / $o3 / $o4"

# ── ⓑ task — 전달 · 같은 내용 2번 = SKIP(중복 0) · 남의 세션 0 ──
printf '두번째 작업\n' >"$T/t2.md"
o="$(bash "$TOOL" task "$SEAT" "$T/t2.md" 2>&1)"; rc=$?
n1="$(find "$RH/$RDIR" -maxdepth 1 -name 'TASK-*' | wc -l | tr -d ' ')"
o2="$(bash "$TOOL" task "$SEAT" "$T/t2.md" 2>&1)"; rc2=$?
n2="$(find "$RH/$RDIR" -maxdepth 1 -name 'TASK-*' | wc -l | tr -d ' ')"
{ [ "$rc" = 0 ] && [ "$rc2" = 0 ] && [ "$n1" = 1 ] && [ "$n2" = 1 ] && grep -q SKIP <<<"$o2"; } \
  && ok "ⓑ task: 파일 1개 전달 · 같은 작업 2번째 SKIP(중복 0)" || bad "ⓑ task rc=$rc/$rc2 files=$n1/$n2: $o / $o2"
o="$(bash "$TOOL" task "$FOREIGN" "$T/t2.md" 2>&1)"; rc=$?
{ [ "$rc" = 5 ] && grep -q "남의 세션" <<<"$o"; } && ok "ⓑ-2 task 남의 세션 = REJECT(쓰기 0)" || bad "ⓑ-2 rc=$rc: $o"

# ── ⓒ pull — 배달 · ack · 2번 배달 0 ───────────────────
FT_MBOX_DIR="$RMBOX" bash "$KIT/ft-mbox.sh" send 'seat-a#0' 'mini-nano#0' "SAT-MBOX-REPLY host=mini" >/dev/null 2>&1
o="$(bash "$TOOL" pull --seats 'seat-a#0' 2>&1)"; rc=$?
got="$(FT_MBOX_DIR="$MACBOX" bash "$KIT/ft-mbox.sh" peek 'seat-a#0' 2>&1 | head -1)"
o2="$(bash "$TOOL" pull --seats 'seat-a#0' 2>&1)"
rmq="$(FT_MBOX_DIR="$RMBOX" bash "$KIT/ft-mbox.sh" peek 'seat-a#0' 2>&1 | head -1)"
{ [ "$rc" = 0 ] && grep -q "delivered=1" <<<"$o" && grep -q "pending=1" <<<"$got" && [ "$(macn 'seat-a#0')" = 1 ] \
  && grep -q "delivered=0" <<<"$o2" && grep -q "pending=0" <<<"$rmq"; } \
  && ok "ⓒ pull: 이 맥 배달 1 · mini ack(pending 0) · 2번째 pull 중복 0" || bad "ⓒ pull rc=$rc: $o | $o2 | $got | $rmq"
o="$(bash "$TOOL" pull 2>&1)"; rc=$?
{ [ "$rc" = 2 ] && grep -q "수신 좌석이 없다" <<<"$o"; } && ok "ⓒ-2 pull --seats 없음 = REJECT" || bad "ⓒ-2 rc=$rc: $o"

# ── ⓓ fetch · close — 이 도구가 연 세션만 ───────────────
printf '요약 3줄\nSAT-DONE host=mini\n' >"$RH/$RDIR/out.md"
o="$(bash "$TOOL" fetch "$SEAT" 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && grep -q "SAT-DONE" "$T/out/r1/out.md"; } && ok "ⓓ fetch: out.md 회수" || bad "ⓓ fetch rc=$rc: $o"
o="$(bash "$TOOL" close "$FOREIGN" 2>&1)"; rc=$?
{ [ "$rc" = 5 ] && grep -q "남의 세션" <<<"$o" && grep -qxF "$FOREIGN" "$RSESS"; } \
  && ok "ⓓ-2 close 남의 세션 = REJECT · 세션 살아 있음" || bad "ⓓ-2 rc=$rc: $o"
printf '999\n' >"$FAKE_PI_PIDS"; export FAKE_PI_CWD="$RH/$RDIR"   # 닫았는데 그 폴더에 pi 가 남은 상황
o="$(bash "$TOOL" close "$SEAT" 2>&1)"; rc=$?
{ [ "$rc" = 6 ] && grep -q "pi_left=1" <<<"$o" && instate "$SEAT"; } \
  && ok "ⓓ-3 close 확인 실패(pi_left=1) = rc6 표시만 · 기록 보존(강제 kill 0)" || bad "ⓓ-3 rc=$rc: $o"
: >"$FAKE_PI_PIDS"; unset FAKE_PI_CWD
o="$(bash "$TOOL" close "$SEAT" 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && grep -q "session=gone pi_left=0" <<<"$o" && ! grep -qxF "$SEAT" "$RSESS" \
  && ! instate "$SEAT" && grep -qxF "$FOREIGN" "$RSESS"; } \
  && ok "ⓓ-4 close: 이 도구가 연 세션만 닫힘 · 기록 삭제 · 남의 세션 보존" || bad "ⓓ-4 rc=$rc: $o"

# ── ⓕ 변이 — dedupe·opened 검사·7초 룰 ──────────────────
cat >"$T/mboxmod-acksavefail.py" <<'EOF'
import importlib.util, os
_s = importlib.util.spec_from_file_location("real", os.environ["REAL_MPY"])
real = importlib.util.module_from_spec(_s); _s.loader.exec_module(real)
globals().update({k: v for k, v in real.__dict__.items() if not k.startswith("__")})
def _save(*a, **k):
    raise RuntimeError("ack save disabled (시험 대역)")
EOF
export SAT_MINI_MBOX_PY="$T/mboxmod-acksavefail.py" REAL_MPY="$KIT/ft-mbox.py"
FT_MBOX_DIR="$RMBOX" bash "$KIT/ft-mbox.sh" send 'seat-d#0' 'mini-nano#0' "ACKFAIL-1" >/dev/null 2>&1
b0="$(macn 'seat-d#0')"; b0="${b0:-0}"; bash "$TOOL" pull --seats 'seat-d#0' >/dev/null 2>&1; b1="$(macn 'seat-d#0')"; b1="${b1:-0}"
bash "$TOOL" pull --seats 'seat-d#0' >/dev/null 2>&1; b2="$(macn 'seat-d#0')"; b2="${b2:-0}"
{ [ "$b1" = "$((b0 + 1))" ] && [ "$b2" = "$b1" ]; } \
  && ok "ⓕ-1 dedupe: ack 실패 창에서 같은 쪽지 2번 배달 0 (${b0}→${b1}→${b2})" || bad "ⓕ-1 dedupe b0=$b0 b1=$b1 b2=$b2"
sed 's/^_seen() .*/_seen() { return 1; }/' "$TOOL" >"$T/mut-dedupe.sh"
o3="$(bash "$T/mut-dedupe.sh" pull --seats 'seat-d#0' 2>&1)"; b3="$(macn 'seat-d#0')"; b3="${b3:-0}"
{ grep -q DELIVER_FAIL <<<"$o3" && [ "$b3" = "$b2" ]; } \
  && ok "ⓕ-2 변이(dedupe 끔) → 같은 쪽지를 다시 배달 시도(DELIVER_FAIL · 제품 쪽지함이 내용 중복을 거부) = 변이 감지" \
  || bad "ⓕ-2 변이(dedupe 끔)인데 재배달 시도가 없다 — dedupe 시험이 헛돌고 있다: $o3"
unset SAT_MINI_MBOX_PY REAL_MPY
sed 's/^_opened() .*/_opened() { return 0; }/' "$TOOL" >"$T/mut-opened.sh"
o="$(bash "$T/mut-opened.sh" close "$FOREIGN" 2>&1)"; rc=$?
{ [ "$rc" = 2 ] && grep -q "상태 기록이 깨졌다" <<<"$o" && grep -qxF "$FOREIGN" "$RSESS"; } \
  && ok "ⓕ-3 변이(opened 검사 끔)여도 2차 방어(fail-closed: 상태 없는 세션은 폴더를 모른다)로 남의 세션 보존" || bad "ⓕ-3 변이 rc=$rc: $o"
mkdir -p "$T/hangbin"; printf '#!/usr/bin/env bash\nsleep 10\n' >"$T/hangbin/ssh"; chmod 755 "$T/hangbin/ssh"
o="$(SAT_TMO=1 PATH="$T/hangbin:$PATH" bash "$TOOL" pull --seats 'seat-a#0' 2>&1)"; rc=$?
{ [ "$rc" = 5 ] && grep -q "mini 쪽지함 읽기 실패\|쪽지함 응답 해석 실패" <<<"$o"; } \
  && ok "ⓕ-4 7초 룰: 원격이 안 답하면 SAT_TMO 에서 끊고 rc5(매달리지 않는다)" || bad "ⓕ-4 7초 룰 rc=$rc: $o"

# ── ① 정적 검사 ────────────────────────────────────────
bash -n "$TOOL" && ok "① bash -n ft-sat-nano.sh" || bad "① bash -n"
cmp -s "$TOOL" "$KIT/ft-sat-nano.sh" && ok "① 키트 사본 cmp 0" || bad "① 키트 사본 불일치"
bash "$TOOL" bogus >/dev/null 2>&1; [ $? = 2 ] && ok "① usage rc=2" || bad "① usage rc"
grep -q "kill -9\|pkill\|kill-server" "$TOOL" && bad "① 강제 kill 문구가 도구에 있다" || ok "① 강제 kill 문구 0"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED"
exit $fail
