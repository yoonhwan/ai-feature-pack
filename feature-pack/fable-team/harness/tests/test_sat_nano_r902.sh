#!/usr/bin/env bash
# ft-sat-nano.sh 시험 (r902 · 반송 r2) — ssh·tmux·tmuxc·pgrep·lsof «대역» 만. 실 mini 접속 0 · 제품 쪽지함 쓰기 0 · 실 tmux 세션 0 · 실 프로세스 기동 0.
#   대역은 «실패 주입» 이 된다(조회 rc·send-keys 실패·ssh 255·느린 tmuxc·세션 신원 바꿔치기·pi cwd 지도).
#   덮는 것: ⓐ open ⓑ task ⓒ pull ⓓ fetch·close
#            ⓖ close 조회 실패=rc6 ⓗ 같은 이름 다른 세션=건드림 0 ⓘ pi 경계(r1 vs r10) ⓙ 동시 pull ⓚ send-keys 실패 뒤 재전송
#            ⓛ 끝 개행 보존 ⓜ 300KB 쪽지 격리 ⓝ 값 검사(원격 호출 0) ⓞ 7초/70초 · 연결 실패 1회 재시도 ⓠ 죽은 잠금 회수
#            ⓕ·ⓟ 변이(dedupe·opened·7초·신원 대조·조회 실패=gone·잠금·값 검사)
#   실행: env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE bash tests/test_sat_nano_r902.sh   (bash 3.2 · /bin/bash 로도 돈다)
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
HARNESS="$(cd "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$HARNESS/bin/ft-sat-nano.sh"; KIT="$HARNESS/kit/fable-team/bin"
T="$(mktemp -d)"; RH="$T/rhome"; FB="$T/fakebin"; RSESS="$T/remote-sessions"; SEND="$T/sendlog"
RDIR="Project/satellite-nano/r1"; RMBOX="$T/rmbox"; MACBOX="$T/macbox"
mkdir -p "$FB" "$MACBOX" "$RMBOX"; : >"$RSESS"; : >"$RSESS.meta"; : >"$SEND"; : >"$T/pi-pids"; : >"$T/pi-cwds"; : >"$T/sshlog"
trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=1; }
instate() { cut -f1 "$SAT_STATE_DIR/opened.tsv" 2>/dev/null | grep -qxF -- "$1"; }
sshn() { wc -l <"$T/sshlog" | tr -d ' '; }
macn() { python3 -c 'import json,os,sys
p=os.path.join(os.environ["FT_MBOX_DIR"],"mailbox.jsonl")
print(sum(1 for l in open(p) if l.strip() and json.loads(l).get("to")==sys.argv[1]) if os.path.exists(p) else 0)' "$1" 2>/dev/null; }
rpend() { python3 -c 'import json,sys
print(sum(1 for l in open(sys.argv[1]) if l.strip() and json.loads(l).get("to")==sys.argv[2]))' "$RMBOX/mailbox.jsonl" "$1"; }
seed() { # seed <seq> <to> <from> <본문파일> — 대역 mini 쪽지함에 행 1개(격리 디렉터리 · 제품 쪽지함 0)
  python3 - "$RMBOX/mailbox.jsonl" "$1" "$2" "$3" "$4" <<'PY'
import json,sys
p,seq,to,frm,bf=sys.argv[1:6]
body=open(bf,encoding='utf-8',newline='').read()
with open(p,'a',encoding='utf-8') as f: f.write(json.dumps({'seq':int(seq),'to':to,'from':frm,'body':body},ensure_ascii=False)+"\n")
PY
}
mkopen() { local o rc; o="$(bash "$TOOL" open "$T/card.md" --run "$1" --name "$2" 2>&1)"; rc=$?; [ "$rc" = 0 ] || { bad "준비 open $1 rc=$rc: $o"; return 1; }; }
sentn() { find "$STUB_SENT_DIR" -type f 2>/dev/null | wc -l | tr -d ' '; }

# ── 대역 (실 프로세스·실 tmux 0) ───────────────────────
cat >"$FB/ssh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$FAKE_SSHLOG"
if [ -s "${FAKE_SSH_FAILS:-/nonexistent}" ]; then
  n="$(cat "$FAKE_SSH_FAILS")"
  if [ "$n" -gt 0 ]; then echo $((n - 1)) >"$FAKE_SSH_FAILS"; echo "ssh: connect to host mini port 22: Operation timed out" >&2; exit 255; fi
fi
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
[ -n "${FAKE_TMUXC_SLEEP:-}" ] && sleep "$FAKE_TMUXC_SLEEP"
n=$(( $(cat "$FAKE_SESS.cnt" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$FAKE_SESS.cnt"
printf '%s\n' "$name" >>"$FAKE_SESS"
printf '%s|$%s|%s|%s\n' "$name" "$n" "$((1000 + n))" "$dir" >>"$FAKE_SESS.meta"
echo "OPEN ok name=$name pane_pid=4242"
EOF
cat >"$FB/tmux" <<'EOF'
#!/usr/bin/env bash
sub="$1"; shift; tgt=""; fmt=""; args="$*"
while [ $# -gt 0 ]; do case "$1" in -t) tgt="$2"; shift 2;; '#'*) fmt="$1"; shift;; *) shift;; esac; done
case "$tgt" in '$'*) tgt="$(awk -F'|' -v i="$tgt" '$2==i{print $1}' "$FAKE_SESS.meta")";; esac
tgt="${tgt#=}"; tgt="${tgt%:}"
case "$sub" in
  has-session) [ -n "${FAKE_HAS_RC:-}" ] && exit "$FAKE_HAS_RC"; grep -qxF -- "$tgt" "$FAKE_SESS" ;;
  display)     grep -qxF -- "$tgt" "$FAKE_SESS" || exit 1
               case "$fmt" in *session_id*) awk -F'|' -v n="$tgt" '$1==n{print $2" "$3" "$4}' "$FAKE_SESS.meta" ;; *) echo 4242 ;; esac ;;
  send-keys)   [ -e "${FAKE_SEND_FAIL:-/nonexistent}" ] && exit 1; echo "$tgt|$args" >>"$FAKE_SEND" ;;
  kill-session) [ -n "$tgt" ] && grep -qxF -- "$tgt" "$FAKE_SESS" || exit 1
               grep -vxF -- "$tgt" "$FAKE_SESS" >"$FAKE_SESS.t"; mv "$FAKE_SESS.t" "$FAKE_SESS"
               awk -F'|' -v n="$tgt" '$1!=n' "$FAKE_SESS.meta" >"$FAKE_SESS.t"; mv "$FAKE_SESS.t" "$FAKE_SESS.meta" ;;
  *) exit 1 ;;
esac
EOF
cat >"$FB/pgrep" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  -P) echo 4243 ;;
  -x) [ -n "${FAKE_PGREP_X_RC:-}" ] && exit "$FAKE_PGREP_X_RC"; [ -s "$FAKE_PI_PIDS" ] && cat "$FAKE_PI_PIDS" || exit 1 ;;
esac
EOF
cat >"$FB/lsof" <<'EOF'
#!/usr/bin/env bash
[ -n "${FAKE_LSOF_RC:-}" ] && exit "$FAKE_LSOF_RC"
pid=""; while [ $# -gt 0 ]; do case "$1" in -p) pid="$2"; shift 2;; *) shift;; esac; done
awk -F'|' -v p="$pid" '$1==p{print "n"$2}' "$FAKE_PI_CWDS"; exit 0
EOF
printf '#!/bin/sh\nexit 0\n' >"$FB/pi"
cat >"$T/stub-mbox.sh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = send ] || exit 2
sleep "${STUB_MBOX_SLEEP:-0}"
mkdir -p "$STUB_SENT_DIR"; f="$(mktemp "$STUB_SENT_DIR/m.XXXXXX")"; printf '%s' "$4" >"$f"
echo "QUEUED seq=1 to=$2 pending=1"
EOF
chmod 755 "$FB"/* "$T/stub-mbox.sh"
export FAKE_RHOME="$RH" FAKE_BIN="$FB" FAKE_SESS="$RSESS" FAKE_SEND="$SEND" FAKE_RMBOX="$RMBOX" FAKE_PI_PIDS="$T/pi-pids" FAKE_PI_CWDS="$T/pi-cwds"
export FAKE_SSHLOG="$T/sshlog" FAKE_SSH_FAILS="$T/ssh-fails" FAKE_SEND_FAIL="$T/sendfail" STUB_SENT_DIR="$T/stub-sent"
export SAT_STATE_DIR="$T/state" SAT_MINI_MBOX_PY="$KIT/ft-mbox.py" SAT_MBOX_SH="$KIT/ft-mbox.sh"
export SAT_OUT_DIR="$T/out" FT_MBOX_DIR="$MACBOX" PATH="$FB:$PATH"
SEAT='byz-sat-nano-pi#0'; FOREIGN='other-tool-nano#0'

# ── ⓐ open — 사전점검 · 세션 1 · TASK.md · 기록 1행(신원 포함) ─────
printf '요약하라. 끝에 SAT-DONE host=x 한 줄.\n' >"$T/card.md"
o1="$(bash "$TOOL" open "$T/card.md" --run r1 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && grep -q "OPEN ok" <<<"$o1" && [ -s "$RH/$RDIR/TASK.md" ] && grep -qxF "$SEAT" "$RSESS" \
  && [ "$(awk -F'\t' '{print $1}' "$SAT_STATE_DIR/opened.tsv" | grep -cxF "$SEAT")" = 1 ] \
  && awk -F'\t' -v n="$SEAT" '$1==n && $5!="" && $6!="" && $7!=""' "$SAT_STATE_DIR/opened.tsv" | grep -q . \
  && grep -q "^$SEAT|.*TASK.md" "$SEND" && grep -q "3/4 pi 기동 확인" <<<"$o1" && [ -f "$RH/$RDIR/TASK.md.sent" ]; } \
  && ok "ⓐ open: pi 기동 HARD GATE 통과 · 세션 1 · TASK.md 사본 · 기록 1행(신원 id·created·path) · 지시 전달 표식" || bad "ⓐ open rc=$rc: $o1"

o2="$(bash "$TOOL" open "$T/card.md" --run r1 --name byz-sat-nano-pi#1 2>&1)"; rc2=$?
printf '%s\n' "$FOREIGN" >>"$RSESS"; printf '%s|$77|7777|/elsewhere\n' "$FOREIGN" >>"$RSESS.meta"
o3="$(bash "$TOOL" open "$T/card.md" --run r2 --name "$FOREIGN" 2>&1)"; rc3=$?
o4="$(bash "$TOOL" open "$T/card.md" --run r1 --name byz-sat-nano-pi#2 2>&1)"; rc4=$?
{ [ "$rc2" = 2 ] && grep -q "폴더가 이미 있다" <<<"$o2" && [ "$rc3" = 2 ] && grep -q "남의 세션이라 건드리지 않는다" <<<"$o3" \
  && [ "$rc4" = 2 ] && grep -q "폴더가 이미 있다" <<<"$o4" && [ ! -d "$RH/Project/satellite-nano/r3" ] && ! grep -qxF 'byz-sat-nano-pi#2' "$RSESS"; } \
  && ok "ⓐ-2 open 재실행 = 폴더 REJECT(새 폴더 생성 0) · 남의 이름 세션 있음 = REJECT(덮지 않음)" || bad "ⓐ-2 rc=$rc2/$rc3/$rc4: $o2 / $o3 / $o4"

# ── ⓑ task — 전달 · 같은 내용 2번 = SKIP(중복 0) · 남의 세션 0 ──
printf '두번째 작업\n' >"$T/t2.md"
o="$(bash "$TOOL" task "$SEAT" "$T/t2.md" 2>&1)"; rc=$?
n1="$(find "$RH/$RDIR" -maxdepth 1 -name 'TASK-*.md' | wc -l | tr -d ' ')"
o2="$(bash "$TOOL" task "$SEAT" "$T/t2.md" 2>&1)"; rc2=$?
n2="$(find "$RH/$RDIR" -maxdepth 1 -name 'TASK-*.md' | wc -l | tr -d ' ')"
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
printf '999\n' >"$T/pi-pids"; printf '999|%s\n' "$RH/$RDIR" >"$T/pi-cwds"   # 닫았는데 그 폴더에 pi 가 남은 상황
o="$(bash "$TOOL" close "$SEAT" 2>&1)"; rc=$?
{ [ "$rc" = 6 ] && grep -q "pi_left=1" <<<"$o" && instate "$SEAT"; } \
  && ok "ⓓ-3 close 확인 실패(pi_left=1) = rc6 표시만 · 기록 보존(강제 kill 0)" || bad "ⓓ-3 rc=$rc: $o"
: >"$T/pi-pids"; : >"$T/pi-cwds"
o="$(bash "$TOOL" close "$SEAT" 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && grep -q "session=gone pi_left=0" <<<"$o" && ! grep -qxF "$SEAT" "$RSESS" \
  && ! instate "$SEAT" && grep -qxF "$FOREIGN" "$RSESS"; } \
  && ok "ⓓ-4 close: 이 도구가 연 세션만 닫힘 · 기록 삭제 · 남의 세션 보존" || bad "ⓓ-4 rc=$rc: $o"

# ── ⓖ close — 조회 실패는 «닫힘» 이 아니다 (tmux·pgrep·lsof rc≠정상) ─
mkopen g1 sat-g#1
o="$(FAKE_HAS_RC=2 bash "$TOOL" close sat-g#1 2>&1)"; rc=$?
{ [ "$rc" = 6 ] && grep -q "조회" <<<"$o" && ! grep -q "닫기 확인 실패" <<<"$o" && instate sat-g#1 && grep -qxF sat-g#1 "$RSESS"; } \
  && ok "ⓖ-1 close: tmux 조회 rc2 → rc6 · 기록 유지 · 세션 보존(조회 실패를 gone 으로 안 봄)" || bad "ⓖ-1 rc=$rc: $o"
printf '4001\n' >"$T/pi-pids"
o="$(FAKE_PGREP_X_RC=2 bash "$TOOL" close sat-g#1 2>&1)"; rc=$?
{ [ "$rc" = 6 ] && instate sat-g#1; } && ok "ⓖ-2 close: pgrep rc2 → rc6(pi 0 으로 안 봄) · 기록 유지" || bad "ⓖ-2 rc=$rc: $o"
mkopen g2 sat-g#2; printf '%s\n' "$$" >"$T/pi-pids"
o="$(FAKE_LSOF_RC=1 bash "$TOOL" close sat-g#2 2>&1)"; rc=$?
{ [ "$rc" = 6 ] && instate sat-g#2; } && ok "ⓖ-3 close: lsof rc1(살아 있는 pid) → rc6(pi 0 으로 안 봄) · 기록 유지" || bad "ⓖ-3 rc=$rc: $o"
: >"$T/pi-pids"
for s in sat-g#1 sat-g#2; do bash "$TOOL" close "$s" >/dev/null 2>&1; done

# ── ⓗ 같은 이름 다른 세션 — 건드림 0 ───────────────────
mkopen h1 sat-h#1
awk -F'|' -v OFS='|' '$1=="sat-h#1"{$2="$99";$3="5555";$4="/some/other/dir"}{print}' "$RSESS.meta" >"$RSESS.t"; mv "$RSESS.t" "$RSESS.meta"   # 같은 이름 새 세션(다른 폴더)
o="$(bash "$TOOL" close sat-h#1 2>&1)"; rc=$?
{ [ "$rc" = 3 ] && grep -q "다른 세션" <<<"$o" && grep -qxF sat-h#1 "$RSESS" && instate sat-h#1; } \
  && ok "ⓗ 같은 이름 다른 폴더·id 세션 → rc3 · 건드림 0(세션 보존·기록 유지)" || bad "ⓗ rc=$rc: $o"

# ── ⓘ pi 검사 = 작업 폴더 «경계 일치» (r1 에 r10 포함 0) ───
mkopen i1 sat-i#1
printf '111\n' >"$T/pi-pids"; printf '111|%s\n' "$RH/Project/satellite-nano/i10" >"$T/pi-cwds"
o="$(bash "$TOOL" close sat-i#1 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && grep -q "pi_left=0" <<<"$o"; } && ok "ⓘ-1 이웃 폴더(i10)의 pi 는 i1 닫기에 안 섞인다" || bad "ⓘ-1 rc=$rc: $o"
mkopen i2 sat-i#2
printf '222\n' >"$T/pi-pids"; printf '222|%s\n' "$RH/Project/satellite-nano/i2/sub" >"$T/pi-cwds"
o="$(bash "$TOOL" close sat-i#2 2>&1)"; rc=$?
{ [ "$rc" = 6 ] && grep -q "pi_left=1" <<<"$o"; } && ok "ⓘ-2 작업 폴더 하위(i2/sub)의 pi 는 남은 것으로 센다" || bad "ⓘ-2 rc=$rc: $o"
: >"$T/pi-pids"; : >"$T/pi-cwds"; bash "$TOOL" close sat-i#2 >/dev/null 2>&1

# ── ⓙ 동시 pull 2개 = 배달 1 ───────────────────────────
rm -rf "$STUB_SENT_DIR"; printf 'j-body\n' >"$T/jb"; seed 901 'seat-j#0' 'mini-j#0' "$T/jb"
export STUB_MBOX_SLEEP=1
( SAT_MBOX_SH="$T/stub-mbox.sh" bash "$TOOL" pull --seats 'seat-j#0' >"$T/j1.out" 2>&1 ) & p1=$!
( SAT_MBOX_SH="$T/stub-mbox.sh" bash "$TOOL" pull --seats 'seat-j#0' >"$T/j2.out" 2>&1 ) & p2=$!
wait $p1; wait $p2; unset STUB_MBOX_SLEEP
{ [ "$(sentn)" = 1 ] && [ "$(rpend 'seat-j#0')" = 0 ]; } && ok "ⓙ 동시 pull 2개 → 같은 쪽지 배달 1 · mini pending 0" || bad "ⓙ 배달 $(sentn)건: $(cat "$T/j1.out" "$T/j2.out")"

# ── ⓚ send-keys 실패 → 표식 0 → 재시도가 다시 보낸다 ─────
mkopen k1 sat-k#1; printf '세번째 작업\n' >"$T/t3.md"; : >"$FAKE_SEND_FAIL"
o="$(bash "$TOOL" task sat-k#1 "$T/t3.md" 2>&1)"; rc=$?
nm="$(find "$RH/Project/satellite-nano/k1" -name 'TASK-*.sent' | wc -l | tr -d ' ')"
rm -f "$FAKE_SEND_FAIL"
o2="$(bash "$TOOL" task sat-k#1 "$T/t3.md" 2>&1)"; rc2=$?
ns="$(grep -c 'k1/TASK-' "$SEND")"
o3="$(bash "$TOOL" task sat-k#1 "$T/t3.md" 2>&1)"; ns3="$(grep -c 'k1/TASK-' "$SEND")"
{ [ "$rc" = 4 ] && [ "$nm" = 0 ] && [ "$rc2" = 0 ] && [ "$ns" = 1 ] && grep -q SKIP <<<"$o3" && [ "$ns3" = 1 ]; } \
  && ok "ⓚ send-keys 실패 → rc4 · 표식 0 · 재시도는 다시 보냄(1회) · 그 뒤 SKIP" || bad "ⓚ rc=$rc/$rc2 표식=$nm 전송=$ns/$ns3: $o / $o2 / $o3"
bash "$TOOL" close sat-k#1 >/dev/null 2>&1

# ── ⓛ 끝 개행 보존 · ⓜ 300KB 격리 ──────────────────────
rm -rf "$STUB_SENT_DIR"; printf 'a b\n\n' >"$T/exp-l"; seed 902 'seat-l#0' 'mini-l#0' "$T/exp-l"
o="$(SAT_MBOX_SH="$T/stub-mbox.sh" bash "$TOOL" pull --seats 'seat-l#0' 2>&1)"; rc=$?
f="$(find "$STUB_SENT_DIR" -type f | head -1)"
{ [ "$rc" = 0 ] && [ -n "$f" ] && cmp -s "$f" "$T/exp-l" && [ "$(rpend 'seat-l#0')" = 0 ]; } \
  && ok "ⓛ 본문 끝 개행 2개까지 바이트 그대로 배달 · ack" || bad "ⓛ rc=$rc: $o"
rm -rf "$STUB_SENT_DIR"; head -c 300000 /dev/zero | tr '\0' 'x' >"$T/big"; seed 903 'seat-m#0' 'mini-m#0' "$T/big"
o="$(SAT_MBOX_SH="$T/stub-mbox.sh" bash "$TOOL" pull --seats 'seat-m#0' 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && grep -q "ERROR oversize seq=903" <<<"$o" && [ "$(sentn)" = 0 ] && [ "$(rpend 'seat-m#0')" = 0 ] && [ -s "$RMBOX/quarantine/seq-903.json" ]; } \
  && ok "ⓜ 300KB 쪽지 → ERROR 1줄 · 배달 0 · mini pending 0 · quarantine/ 보관(삭제 0)" || bad "ⓜ rc=$rc: $o"

# ── ⓝ 값 검사 — 규칙 밖이면 rc2 · 원격 호출 0 ───────────
b="$(sshn)"; r1="$(bash "$TOOL" open "$T/card.md" --run '../x' 2>&1; echo "rc=$?")"
r2="$(bash "$TOOL" open "$T/card.md" --run 'a$(touch /tmp/ft-sat-nano-r902-MARK)' 2>&1; echo "rc=$?")"
r3="$(bash "$TOOL" open "$T/card.md" --run r9 --name 'a b' 2>&1; echo "rc=$?")"
r4="$(bash "$TOOL" pull --seats 'a;b' 2>&1; echo "rc=$?")"
r5="$(bash "$TOOL" close 'x;y' 2>&1; echo "rc=$?")"
a="$(sshn)"
{ [ "$a" = "$b" ] && grep -q "rc=2" <<<"$r1" && grep -q "rc=2" <<<"$r2" && grep -q "rc=2" <<<"$r3" && grep -q "rc=2" <<<"$r4" && grep -q "rc=2" <<<"$r5" \
  && [ ! -e /tmp/ft-sat-nano-r902-MARK ] && [ ! -d "$RH/Project/x" ]; } \
  && ok "ⓝ ../x · \$() · 공백 · ; 값 전부 rc2 · 원격 호출 0 · 탈출/실행 흔적 0" || bad "ⓝ ssh $b→$a: $r1 | $r2 | $r3 | $r4 | $r5"

# ── ⓞ 7초/70초 — open 쪼개기 · 총 마감 · 연결 실패 1회 재시도 ─
s0=$SECONDS; export FAKE_TMUXC_SLEEP=8
o="$(bash "$TOOL" open "$T/card.md" --run o1 --name sat-o#1 2>&1)"; rc=$?; unset FAKE_TMUXC_SLEEP; el=$((SECONDS - s0))
{ [ "$rc" = 0 ] && grep -qxF sat-o#1 "$RSESS" && [ "$el" -lt 50 ]; } \
  && ok "ⓞ-1 느린 tmuxc(8초): 원격 호출 한 번이 7초를 넘지 않게 «백그라운드 시작 → 폴링» 으로 쪼개 열림(${el}초)" || bad "ⓞ-1 rc=$rc ${el}초: $o"
bash "$TOOL" close sat-o#1 >/dev/null 2>&1
s0=$SECONDS; export FAKE_TMUXC_SLEEP=25
o="$(SAT_TOTAL=12 bash "$TOOL" open "$T/card.md" --run o2 --name sat-o#2 2>&1)"; rc=$?; unset FAKE_TMUXC_SLEEP; el=$((SECONDS - s0))
{ [ "$rc" = 5 ] && grep -q "총 마감" <<<"$o" && [ "$el" -lt 25 ]; } \
  && ok "ⓞ-2 총 마감(SAT_TOTAL=12) 안에 못 열면 rc5 로 끊는다(${el}초 · 기록은 남겨 close 로 정리)" || bad "ⓞ-2 rc=$rc ${el}초: $o"
rm -f "$SAT_STATE_DIR/opened.tsv.tmp"; awk -F'\t' '$1!="sat-o#2"' "$SAT_STATE_DIR/opened.tsv" >"$SAT_STATE_DIR/opened.tmp"; mv "$SAT_STATE_DIR/opened.tmp" "$SAT_STATE_DIR/opened.tsv"
b="$(sshn)"; echo 1 >"$FAKE_SSH_FAILS"
o="$(bash "$TOOL" pull --seats 'seat-o#0' 2>&1)"; rc=$?; a="$(sshn)"
{ [ "$rc" = 0 ] && [ "$((a - b))" = 2 ] && grep -q "PULL ok" <<<"$o"; } && ok "ⓞ-3 첫 연결 실패(255) 1회 → 재시도로 성공(ssh 2회)" || bad "ⓞ-3 rc=$rc ssh $b→$a: $o"
b="$(sshn)"; echo 2 >"$FAKE_SSH_FAILS"
o="$(bash "$TOOL" pull --seats 'seat-o#0' 2>&1)"; rc=$?; a="$(sshn)"; : >"$FAKE_SSH_FAILS"
{ [ "$rc" = 5 ] && [ "$((a - b))" = 2 ]; } && ok "ⓞ-4 연결 실패 2번 = 재시도 1회까지만(ssh 2회) → rc5" || bad "ⓞ-4 rc=$rc ssh $b→$a: $o"

# ── ⓠ 죽은 pid 의 잠금은 회수 ──────────────────────────
sleep 0 & dp=$!; wait $dp 2>/dev/null; ln -s "$dp" "$SAT_STATE_DIR/pull.lock"
o="$(bash "$TOOL" pull --seats 'seat-q#0' 2>&1)"; rc=$?
{ [ "$rc" = 0 ] && grep -q "PULL ok" <<<"$o" && [ ! -e "$SAT_STATE_DIR/pull.lock" ] && [ ! -L "$SAT_STATE_DIR/pull.lock" ]; } \
  && ok "ⓠ 죽은 pid 가 쥔 pull 잠금 회수 · 끝나면 잠금 해제" || bad "ⓠ rc=$rc: $o"

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
export SAT_MINI_MBOX_PY="$KIT/ft-mbox.py"; unset REAL_MPY
sed 's/^_opened() .*/_opened() { return 0; }/' "$TOOL" >"$T/mut-opened.sh"
o="$(bash "$T/mut-opened.sh" close "$FOREIGN" 2>&1)"; rc=$?
{ [ "$rc" = 2 ] && grep -q "상태 기록이 깨졌다" <<<"$o" && grep -qxF "$FOREIGN" "$RSESS"; } \
  && ok "ⓕ-3 변이(opened 검사 끔)여도 2차 방어(fail-closed: 상태 없는 세션은 폴더를 모른다)로 남의 세션 보존" || bad "ⓕ-3 변이 rc=$rc: $o"
mkdir -p "$T/hangbin"; printf '#!/usr/bin/env bash\nsleep 10\n' >"$T/hangbin/ssh"; chmod 755 "$T/hangbin/ssh"
o="$(SAT_TMO=1 PATH="$T/hangbin:$PATH" bash "$TOOL" pull --seats 'seat-a#0' 2>&1)"; rc=$?
{ [ "$rc" = 5 ] && grep -q "mini 쪽지함 읽기 실패\|쪽지함 응답 해석 실패" <<<"$o"; } \
  && ok "ⓕ-4 7초 룰: 원격이 안 답하면 SAT_TMO 에서 끊고 rc5(매달리지 않는다)" || bad "ⓕ-4 7초 룰 rc=$rc: $o"

# ── ⓟ 변이 — 신원 대조 끔 · 조회 실패=gone · 잠금 끔 · 값 검사 끔 (전부 시험이 빨강이어야 한다) ──
export SAT_STATE_DIR="$T/state-mut"
mkopen p1 sat-p#1
awk -F'|' -v OFS='|' '$1=="sat-p#1"{$2="$98";$3="6666";$4="/some/other/dir"}{print}' "$RSESS.meta" >"$RSESS.t"; mv "$RSESS.t" "$RSESS.meta"
sed 's/^ident_same() .*/ident_same() { return 0; }/' "$TOOL" >"$T/mut-ident.sh"
o="$(bash "$T/mut-ident.sh" close sat-p#1 2>&1)"; rc=$?
{ [ "$rc" != 3 ] && ! grep -q "다른 세션" <<<"$o"; } && ok "ⓟ-1 변이(신원 대조 끔) → ⓗ 빨강(다른 세션을 못 걸러냄 rc=$rc) = 변이 감지" || bad "ⓟ-1 변이(신원 대조 끔)인데 ⓗ 가 안 빨갛다: $o"
mkopen p2 sat-p#2
sed 's/^absent_rc() .*/absent_rc() { return 0; }/' "$TOOL" >"$T/mut-absent.sh"
o="$(FAKE_HAS_RC=2 bash "$T/mut-absent.sh" close sat-p#2 2>&1)"; rc=$?
{ ! grep -q "조회" <<<"$o"; } && ok "ⓟ-2 변이(조회 실패=gone 복귀) → ⓖ-1 빨강(조회 실패 메시지 사라짐) = 변이 감지" || bad "ⓟ-2 변이(조회 실패=gone)인데 ⓖ 가 안 빨갛다: $o"
rm -rf "$STUB_SENT_DIR"; printf 'p-body\n' >"$T/pb"; seed 904 'seat-p#0' 'mini-p#0' "$T/pb"; export STUB_MBOX_SLEEP=1
sed 's/^pull_lock() .*/pull_lock() { return 0; }/' "$TOOL" >"$T/mut-lock.sh"
( SAT_MBOX_SH="$T/stub-mbox.sh" bash "$T/mut-lock.sh" pull --seats 'seat-p#0' >/dev/null 2>&1 ) & p1=$!
( SAT_MBOX_SH="$T/stub-mbox.sh" bash "$T/mut-lock.sh" pull --seats 'seat-p#0' >/dev/null 2>&1 ) & p2=$!
wait $p1; wait $p2; unset STUB_MBOX_SLEEP
[ "$(sentn)" -ge 2 ] && ok "ⓟ-3 변이(잠금 끔) → ⓙ 빨강(같은 쪽지 $(sentn)번 배달) = 변이 감지" || bad "ⓟ-3 변이(잠금 끔)인데 ⓙ 가 안 빨갛다(배달 $(sentn))"
sed -e 's/^valid_run() .*/valid_run() { return 0; }/' -e 's/^valid_name() .*/valid_name() { return 0; }/' "$TOOL" >"$T/mut-valid.sh"
rm -f /tmp/ft-sat-nano-r902-MARK2
o="$(bash "$T/mut-valid.sh" open "$T/card.md" --run 'a$(touch /tmp/ft-sat-nano-r902-MARK2)' --name sat-mut#1 2>&1)"; rc=$?
{ [ "$rc" != 2 ] && [ ! -e /tmp/ft-sat-nano-r902-MARK2 ]; } \
  && ok "ⓟ-4 변이(값 검사 끔) → ⓝ 빨강(rc=$rc · 원격 호출까지 감) · 그래도 2차 방어(printf %q)로 \$() 실행 0" || bad "ⓟ-4 변이(값 검사 끔) rc=$rc MARK=$(ls /tmp/ft-sat-nano-r902-MARK2 2>&1): $o"
rm -f /tmp/ft-sat-nano-r902-MARK2

# ── ① 정적 검사 ────────────────────────────────────────
bash -n "$TOOL" && ok "① bash -n ft-sat-nano.sh" || bad "① bash -n"
[ -x /bin/bash ] && { /bin/bash -n "$TOOL" && ok "① /bin/bash(3.2) -n" || bad "① /bin/bash -n"; }
cmp -s "$TOOL" "$KIT/ft-sat-nano.sh" && ok "① 키트 사본 cmp 0" || bad "① 키트 사본 불일치"
bash "$TOOL" bogus >/dev/null 2>&1; [ $? = 2 ] && ok "① usage rc=2" || bad "① usage rc"
grep -q "kill -9\|pkill\|kill-server" "$TOOL" && bad "① 강제 kill 문구가 도구에 있다" || ok "① 강제 kill 문구 0"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED"
exit $fail
