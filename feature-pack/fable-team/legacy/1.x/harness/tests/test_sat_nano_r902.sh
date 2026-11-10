#!/usr/bin/env bash
# ft-sat-nano 시험 (r902 r7 + DECISION 고침 3) — ssh·tmux·tmuxc·pgrep·lsof·ps·mkdir·mv «대역» 만. 실 mini 0 · 제품 쪽지함 쓰기 0 · 실 tmux 세션 0.
#   유지 칸: ⓐ ⓑ ⓒ ⓓ ⓖ ⓗ ⓘ ⓙ ⓜ ⓝ ⓞ ⓠ ⓡ ⓢ-1 ⓤ · 바뀌는 칸: ⓐ 표식 · ⓚ · ⓢ-2 · ⓛ · ⓣ · ⓥ
#   새 칸: Ⓐ Ⓑ Ⓒ Ⓓ Ⓔ Ⓕ Ⓖ Ⓗ①② Ⓘ①② Ⓙ Ⓚ Ⓛ-0~4 Ⓜ Ⓝ Ⓞ Ⓟ Ⓠ + 고침 3(claim_fail 줄 유지 · --why 필수 · has-session rc1 두 꼴)
#   반송 r5: tmux 대역 = 서버 2개(소켓 A·B) · 새 칸 ⓡ1~ⓡ6 · 새 변이 6
#   r5 확정: Ⓙ = 첫 R_POLL 표식(.polled) 뒤 세션 생성 · pid 재사용 = cwd 판정(시각 경쟁 0) · 원격 대역 지연 ≤ 3.5초 · 새 칸 ⓢ1·ⓢ2·Ⓙ'(확정) · 새 변이 2
#   astra r1: 대역 tmuxc = 기다림 끝에 .polled 없으면 세션 생성 0(rc3) · 새 칸 Ⓙ''(첫 R_POLL 5초 지연 → rc4 · 세션 0)
#   변이: 칸 함수를 «변이 사본»으로 다시 돌려 빨강이어야 통과(mut — 바꿀 글자가 정확히 1곳이어야 사본이 만들어진다).
#   실행: env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE bash tests/test_sat_nano_r902.sh   (bash 3.2 · /bin/bash 로도 돈다)
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
HARNESS="$(cd "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$HARNESS/bin"; TOOL="$BIN/ft-sat-nano.sh"; KIT="$HARNESS/kit/fable-team/bin"
T="$(mktemp -d)"; RH="$T/rhome"; FB="$T/fakebin"; SB="$T/sshbin"; RSESS="$T/remote-sessions"; SEND="$T/sendlog"
ROOTR="Project/satellite-nano"; RMBOX="$T/rmbox"; MACBOX="$T/macbox"; STUB="$T/stub-mbox.sh"
mkdir -p "$FB" "$SB" "$MACBOX" "$RMBOX" "$RH"
for f in "$RSESS" "$RSESS.meta" "$RSESS.calls" "$SEND" "$T/pi-pids" "$T/pi-cwds" "$T/sshlog" "$T/calls"; do : >"$f"; done
trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=1; }
call() { O="$("$@" 2>&1)"; RC=$?; }
instate() { cut -f1 "$SAT_STATE_DIR/opened.tsv" 2>/dev/null | grep -qxF -- "$1"; }
conf() { awk -F'\t' -v n="$1" '$1==n && NF==8 && $5!="" && $6!="" && $7!="" && $8!=""' "$SAT_STATE_DIR/opened.tsv" 2>/dev/null | grep -q .; }
hassess() { grep -qxF -- "$1" "$RSESS"; }
waitsess() { local _; for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do hassess "$1" && return 0; sleep 1; done; return 1; }
dropsess() { grep -vxF -- "$1" "$RSESS" >"$RSESS.t"; mv "$RSESS.t" "$RSESS"; awk -F'|' -v n="$1" '$1!=n' "$RSESS.meta" >"$RSESS.t"; mv "$RSESS.t" "$RSESS.meta"; }
sshn() { wc -l <"$T/sshlog" | tr -d ' '; }
callsn() { wc -l <"$T/calls" | tr -d ' '; }
opensn() { grep -cxF -- "$1" "$RSESS.calls"; }
sentn() { find "$STUB_SENT_DIR" -type f 2>/dev/null | wc -l | tr -d ' '; }
macn() { python3 -c 'import json,os,sys
p=os.path.join(os.environ["FT_MBOX_DIR"],"mailbox.jsonl")
print(sum(1 for l in open(p) if l.strip() and json.loads(l).get("to")==sys.argv[1]) if os.path.exists(p) else 0)' "$1" 2>/dev/null; }
rpend() { python3 -c 'import json,sys
print(sum(1 for l in open(sys.argv[1]) if l.strip() and json.loads(l).get("to")==sys.argv[2]))' "$RMBOX/mailbox.jsonl" "$1"; }
seed() { # seed <seq> <to> <from> <본문파일> — 대역 mini 쪽지함에 행 1개(격리 폴더)
  python3 - "$RMBOX/mailbox.jsonl" "$1" "$2" "$3" "$4" <<'PY'
import json,sys
p,seq,to,frm,bf=sys.argv[1:6]
body=open(bf,encoding='utf-8',newline='').read()
with open(p,'a',encoding='utf-8') as f: f.write(json.dumps({'seq':int(seq),'to':to,'from':frm,'body':body},ensure_ascii=False)+"\n")
PY
}
lastst() { awk -F'\t' -v k="mini:$1" '$1==k{s=$2}END{print s}' "$SAT_STATE_DIR/delivered.tsv" 2>/dev/null; }
mut() { # mut <id> <nano|rt|sh> <옛 글자> <새 글자> [옛 새 ...] → 변이 사본 입구 경로(바꿀 글자가 정확히 1곳 아니면 실패)
  local d="$T/mut-$1" f="$2"; shift 2
  mkdir -p "$d/bin"; cp "$BIN/ft-sat-nano.sh" "$BIN/ft_sat_nano.py" "$BIN/ft_sat_rt.py" "$BIN/ft_sat_gate.py" "$BIN/ft-name-lint.sh" "$BIN/ft_secret_shapes.py" "$BIN/ft_secret_targets.py" "$BIN/ft_secret_lex.py" "$BIN/autonomy_scope_secret.py" "$d/bin/"
  case "$f" in nano) f="$d/bin/ft_sat_nano.py";; rt) f="$d/bin/ft_sat_rt.py";; esac
  python3 - "$f" "$@" <<'PY' >&2 || return 1
import sys
p=sys.argv[1]; s=open(p,encoding='utf-8').read(); a=sys.argv[2:]
for old,new in zip(a[0::2],a[1::2]):
    if s.count(old)!=1: sys.exit("mutation anchor count=%d: %s" % (s.count(old), old))
    s=s.replace(old,new)
open(p,'w',encoding='utf-8').write(s)
PY
  printf '%s' "$d/bin/ft-sat-nano.sh"
}
mcheck() { # mcheck <변이 이름> <칸 함수> <변이 사본> [인자...] — 칸이 빨강(실패)이어야 변이 감지
  local nm="$1" fn="$2" m="$3"; shift 3
  [ -n "$m" ] || { bad "변이 $nm 사본이 안 만들어졌다"; return; }
  if "$fn" "$m" "$@" >/dev/null 2>&1; then bad "변이 $nm → $fn 이 안 빨갛다(시험이 헛돈다)"; else ok "변이 $nm → $fn 빨강 = 감지"; fi
}

# ── 대역 (실 프로세스·실 tmux 0) — ssh 는 이 맥 PATH 에, 나머지는 «원격» PATH 에만 ──
cat >"$SB/ssh" <<'EOF'
#!/usr/bin/env bash
{ printf '%s' "$*" | tr '\n' ' '; echo; } >>"$FAKE_SSHLOG"   # 한 호출 = 한 줄(원격 스크립트의 개행을 접는다)
while [ $# -gt 0 ]; do case "$1" in -o|-l|-p|-i) shift 2;; -*) shift;; *) break;; esac; done
shift 2>/dev/null || exit 255
cmd="$*"; pf='export PATH=/opt/homebrew/bin:$HOME/.local/bin:$PATH; '
hit() { [ -z "${FAKE_SSH_PAT:-}" ] && return 0; case "$cmd" in *"$FAKE_SSH_PAT"*) return 0;; esac; return 1; }
take() { [ -s "${1:-/nonexistent}" ] && hit || return 1; local n; n="$(cat "$1")"; [ "$n" -gt 0 ] || return 1; echo $((n - 1)) >"$1"; }
if take "${FAKE_SSH_FAILS:-}"; then echo "ssh: connect to host mini port 22: Operation timed out" >&2; exit 255; fi
export HOME="$FAKE_RHOME" PATH="$FAKE_BIN:$PATH" FT_MBOX_DIR="$FAKE_RMBOX"
if take "${FAKE_SSH_LOST:-}"; then bash -c "${cmd#"$pf"}" >/dev/null 2>&1; exit 255; fi   # 원격은 돌았고 출력만 잃음(0바이트)
if take "${FAKE_SSH_AFTER:-}"; then bash -c "${cmd#"$pf"}"; exit 255; fi                 # 출력까지 낸 뒤 255
case "$cmd" in *'echo "alive=$a"'*)   # R_POLL — 끝난 «뒤» 작업 폴더에 .polled 표식(대역 세션 생성의 동기화) · FAKE_RPOLL_SLEEP = 첫 R_POLL 만 늦춤
  last="${cmd##* }"; last="${last#\'}"; last="${last%\'}"; [ -n "${FAKE_RPOLL_SLEEP:-}" ] && [ ! -e "$FAKE_RHOME/$last/.polled" ] && sleep "$FAKE_RPOLL_SLEEP"
  bash -c "${cmd#"$pf"}"; rc=$?; last="${cmd##* }"; last="${last#\'}"; last="${last%\'}"; : >"$FAKE_RHOME/$last/.polled" 2>/dev/null; exit "$rc" ;;
esac
exec bash -c "${cmd#"$pf"}"
EOF
cat >"$FB/tmuxc" <<'EOF'
#!/usr/bin/env bash
[ "$1" = open ] || { echo "tmuxc: unsupported $*" >&2; exit 2; }
dir="$2"; shift 2; name=""
while [ $# -gt 0 ]; do case "$1" in --name) name="$2"; shift 2;; --agent|--role|--model|--effort) shift 2;; *) shift;; esac; done
printf '%s\n' "$name" >>"$FAKE_SESS.calls"
[ -d "$dir" ] || exit 3
if [ -n "${FAKE_TMUXC_WAITPOLL:-}" ]; then   # 표식 동기화(r5 확정): 첫 R_POLL 이 끝난 «뒤» 에만 세션을 만든다(파일 대기 · 상한 3초)
  while [ ! -e "$dir/.polled" ] && [ "$SECONDS" -lt 4 ]; do sleep 0.01; done   # r949: 벽시계 3~4초(부하 34 에서 sleep 0.01 ×300 = 5.8초 → Ⓙ'' 의 5초 지연을 넘었다)
  [ -e "$dir/.polled" ] || { echo "tmuxc: .polled 표식 없음(대역) — 세션 생성 0" >&2; exit 3; }   # astra r1: 표식 없음 = 생성 0
fi
[ -n "${FAKE_TMUXC_ARM_HAS:-}" ] && { printf '%s\n' "$FAKE_TMUXC_ARM_HAS" >"$FAKE_SESS.hasrc"; exit 0; }
[ -n "${FAKE_TMUXC_SLEEP:-}" ] && sleep "$FAKE_TMUXC_SLEEP"
[ -n "${FAKE_TMUXC_NOSESS:-}" ] && { echo "tmuxc: pi 기동 실패(대역)"; exit 3; }
n=$(( $(cat "$FAKE_SESS.cnt" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$FAKE_SESS.cnt"
printf '%s\n' "$name" >>"$FAKE_SESS"
printf '%s|$%s|%s|%s\n' "$name" "$n" "$((1000 + n))" "$dir" >>"$FAKE_SESS.meta"
echo "OPEN ok name=$name pane_pid=4242"
EOF
cat >"$FB/tmux" <<'EOF'
#!/usr/bin/env bash
# tmux 서버 2개 대역(r5 R3): 소켓 A = $FAKE_SESS · 소켓 B = $FAKE_SESS.B(파일 없음 = 서버 꺼짐) · 기본 소켓 = FAKE_DEFAULT_SOCK(없으면 A)
sock="${FAKE_DEFAULT_SOCK:-$FAKE_SOCK_A}"
if [ "$1" = -S ]; then sock="$2"; shift 2; fi
case "$sock" in "$FAKE_SOCK_A") S="$FAKE_SESS";; "$FAKE_SOCK_B") S="$FAKE_SESS.B";; *) S="";; esac
if [ -z "$S" ] || [ ! -e "$S" ]; then echo "no server running on $sock" >&2; exit 1; fi
sub="$1"; shift; tgt=""; fmt=""; args="$*"
while [ $# -gt 0 ]; do case "$1" in -t) tgt="$2"; shift 2;; '#'*) fmt="$1"; shift;; *) shift;; esac; done
case "$tgt" in '$'*) tgt="$(awk -F'|' -v i="$tgt" '$2==i{print $1}' "$S.meta")";; esac
tgt="${tgt#=}"; tgt="${tgt%:}"
case "$sub" in
  has-session)
    if [ -s "$FAKE_SESS.hasrc" ]; then c="$(cat "$FAKE_SESS.hasrc")"
      case "$c" in 1e) echo "error connecting to /private/tmp/tmux-501/default (Permission denied)" >&2; exit 1;; *) echo "server exited unexpectedly" >&2; exit "$c";; esac
    fi
    [ -n "${FAKE_HAS_RC:-}" ] && { echo "lost server" >&2; exit "$FAKE_HAS_RC"; }
    [ -n "${FAKE_HAS_ERR:-}" ] && { echo "$FAKE_HAS_ERR" >&2; exit 1; }
    grep -qxF -- "$tgt" "$S" && exit 0
    if [ -n "${FAKE_NO_SERVER:-}" ]; then echo "no server running on $sock" >&2; else echo "can't find session: $tgt" >&2; fi
    exit 1 ;;
  display)     grep -qxF -- "$tgt" "$S" || exit 1
               case "$fmt" in *session_id*) awk -F'|' -v n="$tgt" -v s="$sock" '$1==n{print $2" "$3" "s" "$4}' "$S.meta" ;; *) echo 4242 ;; esac ;;
  send-keys)   [ -e "${FAKE_SEND_FAIL:-/nonexistent}" ] && exit 1
               n=0; while [ -e "${FAKE_SEND_BARRIER:-/nonexistent}" ] && [ "$n" -lt 35 ]; do sleep 0.1; n=$((n + 1)); done
               echo "$tgt|$args" >>"$FAKE_SEND" ;;
  kill-session) [ -n "$tgt" ] && grep -qxF -- "$tgt" "$S" || exit 1
               grep -vxF -- "$tgt" "$S" >"$S.t"; mv "$S.t" "$S"
               awk -F'|' -v n="$tgt" '$1!=n' "$S.meta" >"$S.t"; mv "$S.t" "$S.meta" ;;
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
cat >"$FB/ps" <<'EOF'
#!/usr/bin/env bash
# pid 재사용 대역(r5 확정): FAKE_TMUXC_ARM_PS 면 OPEN_BG 밖(.open.claim 없는 cwd = R_POLL)의 lstart 는 늘 다른 값 — 시각 경쟁 0
case " $* " in *" lstart= "*) [ -n "${FAKE_TMUXC_ARM_PS:-}" ] && [ ! -d "$PWD/.open.claim" ] && { echo "Thu Jan  1 00:00:00 1970"; exit 0; };; esac
exec /bin/ps "$@"
EOF
cat >"$FB/mkdir" <<'EOF'
#!/usr/bin/env bash
last="${!#}"
case "$last" in
  */.open.claim) [ -n "${FAKE_MKDIR_FAIL_CLAIM:-}" ] && exit 1
                 if [ -n "${FAKE_MKDIR_DIE_CLAIM:-}" ]; then /bin/mkdir "$@" || exit 1; kill -9 "$PPID"; exit 1; fi ;;
  */.sent) [ -n "${FAKE_MKDIR_FAIL_SENT:-}" ] && exit 1 ;;
esac
exec /bin/mkdir "$@"
EOF
cat >"$FB/mv" <<'EOF'
#!/usr/bin/env bash
case "${!#}" in */.open.pid) [ -n "${FAKE_MV_FAIL_PID:-}" ] && exit 1;; esac
exec /bin/mv "$@"
EOF
printf '#!/bin/sh\nexit 0\n' >"$FB/pi"
printf '#!/bin/sh\n[ -n "${FAKE_FREE_RC:-}" ] && exit "$FAKE_FREE_RC"\necho "System-wide memory free percentage: ${FAKE_FREE:-50}%%"\n' >"$FB/memory_pressure"   # r949 free% 대역
cat >"$STUB" <<'EOF'
#!/usr/bin/env bash
[ "$1" = send ] || exit 2
printf '%s\n' "$4" | head -1 >>"$STUB_CALLS"
sleep "${STUB_MBOX_SLEEP:-0}"
case "${STUB_MBOX_MODE:-ok}" in
  ratelimit) echo "RATE_LIMIT to=$2 (대역)"; exit 3 ;;
  lc) echo "queued ok"; exit 0 ;;
  abc) echo "QUEUED seq=abc to=$2 pending=1"; exit 0 ;;
  second) printf 'note: hint\nQUEUED seq=5 to=%s pending=1\n' "$2"; exit 0 ;;
esac
mkdir -p "$STUB_SENT_DIR"; f="$(mktemp "$STUB_SENT_DIR/m.XXXXXX")"; printf '%s' "$4" >"$f"
echo "QUEUED seq=1 to=$2 pending=1"
EOF
mkdir -p "$T/fsyncinj"; cat >"$T/fsyncinj/sitecustomize.py" <<'EOF'
import os
if os.environ.get("SAT_TEST_FSYNC_FAIL"):
    def _fsync(fd):
        raise OSError(5, "fsync 실패(시험 주입)")
    os.fsync = _fsync
if os.environ.get("SAT_TEST_FSYNC_SLEEP"):
    import time
    _real_fsync = os.fsync
    def _slow_fsync(fd):
        time.sleep(float(os.environ["SAT_TEST_FSYNC_SLEEP"]))
        _real_fsync(fd)
    os.fsync = _slow_fsync
EOF
chmod 755 "$FB"/* "$SB"/* "$STUB"
export FAKE_RHOME="$RH" FAKE_BIN="$FB" FAKE_SESS="$RSESS" FAKE_SEND="$SEND" FAKE_RMBOX="$RMBOX" FAKE_PI_PIDS="$T/pi-pids" FAKE_PI_CWDS="$T/pi-cwds"
export FAKE_SSHLOG="$T/sshlog" STUB_SENT_DIR="$T/stub-sent" STUB_CALLS="$T/calls"
export FAKE_SOCK_A="$T/tmux-501/sockA" FAKE_SOCK_B="$T/tmux-501/sockB"
export SAT_MINI_MBOX_PY="$KIT/ft-mbox.py" SAT_MBOX_SH="$KIT/ft-mbox.sh" SAT_OUT_DIR="$T/out" FT_MBOX_DIR="$MACBOX" PATH="$SB:$PATH"
export SAT_STATE_DIR="$T/state" SAT_MAX=99   # r949: 이 시험은 세션을 많이 남긴다 — 상한은 test_sat_nano_r949.sh 가 본다
printf '요약하라. 끝에 SAT-DONE host=x 한 줄.\n' >"$T/card.md"
FOREIGN='other-tool-nano-x#0'; printf '%s\n' "$FOREIGN" >>"$RSESS"; printf '%s|$77|7777|/elsewhere\n' "$FOREIGN" >>"$RSESS.meta"
mkopen() { call bash "$1" open "$T/card.md" --run "$2" --name "$3"; [ "$RC" = 0 ] || { echo "준비 open $2 rc=$RC: $O" >&2; return 1; }; }
pending() { # pending <tool> <run> <name> — open 이 마감(rc5)으로 끝나 기록 pending 으로 남은 줄을 만든다
  FAKE_TMUXC_SLEEP=6 SAT_TOTAL=3 bash "$1" open "$T/card.md" --run "$2" --name "$3" >/dev/null 2>&1
  instate "$3" && ! conf "$3"; }

# ══ 유지 칸 ══
# ⓐ open — 사전점검 · 세션 1 · TASK.md · 기록 신원 · 표식(.sent/TASK.md/sent · .open.claim · .open.pid · claim/t 없음)
call bash "$TOOL" open "$T/card.md" --run r1; D="$RH/$ROOTR/r1"; SEAT='byz-satnano-nano-r1#0'
{ [ "$RC" = 0 ] && grep -q "OPEN ok" <<<"$O" && grep -q "3/4 pi 기동 확인" <<<"$O" && [ -s "$D/TASK.md" ] && hassess "$SEAT" && conf "$SEAT" \
  && [ -f "$D/.sent/TASK.md/sent" ] && [ -d "$D/.open.claim" ] && [ -s "$D/.open.pid" ] && [ ! -e "$D/.open.claim/t" ] && grep -q "^$SEAT|.*TASK.md" "$SEND"; } \
  && ok "ⓐ open: 세션 1 · TASK.md · 기록 신원 3칸 · 표식 .sent/TASK.md/sent + .open.claim·.open.pid (claim/t 없음)" || bad "ⓐ open rc=$RC: $O"
b="$(sshn)"; call bash "$TOOL" open "$T/card.md" --run r1 --name 'byz-satnano-nano-a2#1'; r2="$RC"; o2="$O"; s2="$(( $(sshn) - b ))"
call bash "$TOOL" open "$T/card.md" --run r2 --name "$FOREIGN"; r3="$RC"; o3="$O"
mkdir -p "$RH/$ROOTR/r2x"; call bash "$TOOL" open "$T/card.md" --run r2x --name 'byz-satnano-nano-a2#2'; r4="$RC"; o4="$O"
{ [ "$r2$r3$r4" = 222 ] && [ "$s2" = 0 ] && grep -q "같은 run" <<<"$o2" && grep -q "남의 세션이라 건드리지 않는다" <<<"$o3" && grep -q "폴더가 이미 있다" <<<"$o4" \
  && ! instate 'byz-satnano-nano-a2#1' && ! instate "$FOREIGN" && ! instate 'byz-satnano-nano-a2#2' && [ ! -d "$RH/$ROOTR/r2" ]; } \
  && ok "ⓐ-2 장부에 같은 run = REJECT(원격 0) · 남의 이름 세션 = REJECT · mini 폴더 있음 = REJECT · R_PRE 만 돈 거절은 기록도 0" || bad "ⓐ-2 rc=$r2/$r3/$r4 ssh=$s2: $o2 / $o3 / $o4"

# ⓑ task — 전달 · 같은 내용 2번 = SKIP · 남의 세션 0
printf '두번째 작업\n' >"$T/t2.md"
call bash "$TOOL" task "$SEAT" "$T/t2.md"; rb1=$RC; n1="$(find "$D" -maxdepth 1 -name 'TASK-*.md' | wc -l | tr -d ' ')"
call bash "$TOOL" task "$SEAT" "$T/t2.md"; rb2=$RC; o2="$O"
{ [ "$rb1" = 0 ] && [ "$rb2" = 0 ] && [ "$n1" = 1 ] && grep -q SKIP <<<"$o2"; } && ok "ⓑ task: 1개 전달 · 2번째 SKIP(ALREADY · 입력 0)" || bad "ⓑ rc=$rb1/$rb2: $o2"
call bash "$TOOL" task "$FOREIGN" "$T/t2.md"
{ [ "$RC" = 5 ] && grep -q "남의 세션" <<<"$O"; } && ok "ⓑ-2 task 남의 세션 = REJECT" || bad "ⓑ-2 rc=$RC: $O"

# ⓒ pull — 실 mbox(격리 폴더) 배달 · ack · 2번째 0
FT_MBOX_DIR="$RMBOX" bash "$KIT/ft-mbox.sh" send 'seat-a#0' 'mini-nano#0' "SAT-MBOX-REPLY host=mini" >/dev/null 2>&1
call bash "$TOOL" pull --seats 'seat-a#0'; rc1=$RC; o1="$O"
call bash "$TOOL" pull --seats 'seat-a#0'
{ [ "$rc1" = 0 ] && grep -q "delivered=1" <<<"$o1" && [ "$(macn 'seat-a#0')" = 1 ] && grep -q "delivered=0" <<<"$O" && [ "$(rpend 'seat-a#0')" = 0 ]; } \
  && ok "ⓒ pull: 배달 1 · mini ack · 2번째 pull 0" || bad "ⓒ rc=$rc1: $o1 | $O"
call bash "$TOOL" pull; { [ "$RC" = 2 ] && grep -q "수신 좌석이 없다" <<<"$O"; } && ok "ⓒ-2 --seats 없음 rc2" || bad "ⓒ-2 rc=$RC: $O"

# ⓓ fetch · close — 이 도구가 연 세션만
printf '요약 3줄\nSAT-DONE host=mini\n' >"$D/out.md"
call bash "$TOOL" fetch "$SEAT"; { [ "$RC" = 0 ] && grep -q "SAT-DONE" "$T/out/r1/out.md"; } && ok "ⓓ fetch: out.md 회수" || bad "ⓓ fetch rc=$RC: $O"
call bash "$TOOL" close "$FOREIGN"; { [ "$RC" = 5 ] && hassess "$FOREIGN"; } && ok "ⓓ-2 close 남의 세션 = REJECT" || bad "ⓓ-2 rc=$RC: $O"
printf '999\n' >"$T/pi-pids"; printf '999|%s\n' "$D" >"$T/pi-cwds"
call bash "$TOOL" close "$SEAT"; { [ "$RC" = 6 ] && grep -q "pi_left=1" <<<"$O" && instate "$SEAT"; } && ok "ⓓ-3 pi 남음 → rc6 · 기록 유지" || bad "ⓓ-3 rc=$RC: $O"
: >"$T/pi-pids"; : >"$T/pi-cwds"
call bash "$TOOL" close "$SEAT"; { [ "$RC" = 0 ] && grep -q "session=gone pi_left=0" <<<"$O" && ! hassess "$SEAT" && ! instate "$SEAT" && hassess "$FOREIGN"; } \
  && ok "ⓓ-4 close: 이 도구가 연 세션만 · 기록 삭제 · 남의 세션 보존" || bad "ⓓ-4 rc=$RC: $O"

# ⓖ close 조회 실패 = rc6 (tmux rc2 · pgrep rc2 · lsof rc1)
mkopen "$TOOL" g1 'byz-satnano-nano-g#1'
call env FAKE_HAS_RC=2 bash "$TOOL" close 'byz-satnano-nano-g#1'
{ [ "$RC" = 6 ] && grep -q "조회" <<<"$O" && instate 'byz-satnano-nano-g#1' && hassess 'byz-satnano-nano-g#1'; } && ok "ⓖ-1 tmux 조회 rc2 → rc6 · 기록·세션 유지" || bad "ⓖ-1 rc=$RC: $O"
printf '4001\n' >"$T/pi-pids"; call env FAKE_PGREP_X_RC=2 bash "$TOOL" close 'byz-satnano-nano-g#1'
{ [ "$RC" = 6 ] && instate 'byz-satnano-nano-g#1'; } && ok "ⓖ-2 pgrep rc2 → rc6" || bad "ⓖ-2 rc=$RC: $O"
mkopen "$TOOL" g2 'byz-satnano-nano-g#2'; printf '%s\n' "$$" >"$T/pi-pids"; call env FAKE_LSOF_RC=1 bash "$TOOL" close 'byz-satnano-nano-g#2'
{ [ "$RC" = 6 ] && instate 'byz-satnano-nano-g#2'; } && ok "ⓖ-3 lsof rc1 → rc6" || bad "ⓖ-3 rc=$RC: $O"
: >"$T/pi-pids"; bash "$TOOL" close 'byz-satnano-nano-g#2' >/dev/null 2>&1

# ⓗ 같은 이름 다른 세션 — 건드림 0
cell_h() { mkopen "$1" "h$2" "byz-satnano-nano-h#$2" || return 1
  awk -F'|' -v OFS='|' -v n="byz-satnano-nano-h#$2" '$1==n{$2="$99";$3="5555";$4="/some/other/dir"}{print}' "$RSESS.meta" >"$RSESS.t"; mv "$RSESS.t" "$RSESS.meta"
  call bash "$1" close "byz-satnano-nano-h#$2"; [ "$RC" = 3 ] && grep -q "다른 세션" <<<"$O" && hassess "byz-satnano-nano-h#$2" && instate "byz-satnano-nano-h#$2"; }
cell_h "$TOOL" 1 && ok "ⓗ 같은 이름 다른 id·폴더 → rc3 · 건드림 0" || bad "ⓗ rc=$RC: $O"

# ⓘ pi 경계 (i1 vs i10 · 하위 폴더)
mkopen "$TOOL" i1 'byz-satnano-nano-i#1'; printf '111\n' >"$T/pi-pids"; printf '111|%s\n' "$RH/$ROOTR/i10" >"$T/pi-cwds"
call bash "$TOOL" close 'byz-satnano-nano-i#1'; { [ "$RC" = 0 ] && grep -q "pi_left=0" <<<"$O"; } && ok "ⓘ-1 이웃 폴더 i10 의 pi 는 안 섞인다" || bad "ⓘ-1 rc=$RC: $O"
mkopen "$TOOL" i2 'byz-satnano-nano-i#2'; printf '222\n' >"$T/pi-pids"; printf '222|%s\n' "$RH/$ROOTR/i2/sub" >"$T/pi-cwds"
call bash "$TOOL" close 'byz-satnano-nano-i#2'; { [ "$RC" = 6 ] && grep -q "pi_left=1" <<<"$O"; } && ok "ⓘ-2 하위 폴더 pi 는 남은 것" || bad "ⓘ-2 rc=$RC: $O"
: >"$T/pi-pids"; : >"$T/pi-cwds"; bash "$TOOL" close 'byz-satnano-nano-i#2' >/dev/null 2>&1

# ⓙ 동시 pull 2개 = 발신 1
cell_j() { local t="$1" s="$2" p1 p2; : >"$T/calls"; printf 'j-body\n' >"$T/jb"; seed "$s" "seat-j$s#0" 'mini-j#0' "$T/jb"
  ( STUB_MBOX_SLEEP=1 SAT_STATE_DIR="$T/st-j$s" SAT_MBOX_SH="$STUB" bash "$t" pull --seats "seat-j$s#0" >/dev/null 2>&1 ) & p1=$!
  ( STUB_MBOX_SLEEP=1 SAT_STATE_DIR="$T/st-j$s" SAT_MBOX_SH="$STUB" bash "$t" pull --seats "seat-j$s#0" >/dev/null 2>&1 ) & p2=$!
  wait $p1; wait $p2; [ "$(callsn)" = 1 ] && [ "$(rpend "seat-j$s#0")" = 0 ]; }
cell_j "$TOOL" 901 && ok "ⓙ 동시 pull 2개 → 발신 1 · mini pending 0" || bad "ⓙ 발신 $(callsn)"

# ⓜ 300KB 격리 · ⓝ 값 검사 · ⓤ 설정 상한
head -c 300000 /dev/zero | tr '\0' 'x' >"$T/big"; seed 903 'seat-m#0' 'mini-m#0' "$T/big"; : >"$T/calls"
call env SAT_MBOX_SH="$STUB" bash "$TOOL" pull --seats 'seat-m#0'
{ [ "$RC" = 0 ] && grep -q "ERROR oversize seq=903" <<<"$O" && [ "$(callsn)" = 0 ] && [ "$(rpend 'seat-m#0')" = 0 ] && [ -s "$RMBOX/quarantine/seq-903.json" ]; } \
  && ok "ⓜ 300KB → ERROR · 발신 0 · quarantine/ 보관" || bad "ⓜ rc=$RC: $O"
cell_n() { local t="$1" b r=""; b="$(sshn)"; rm -f "$T/MARK"
  bash "$t" open "$T/card.md" --run '../x' >/dev/null 2>&1; r="$r $?"
  bash "$t" open "$T/card.md" --run "a\$(touch $T/MARK)" --name 'byz-satnano-nano-n#1' >/dev/null 2>&1; r="$r $?"
  bash "$t" open "$T/card.md" --run r9 --name 'a;b' >/dev/null 2>&1; r="$r $?"
  bash "$t" pull --seats 'a;b' >/dev/null 2>&1; r="$r $?"
  bash "$t" close 'x;y' >/dev/null 2>&1; r="$r $?"
  [ "$(sshn)" = "$b" ] && [ "$r" = " 2 2 2 2 2" ] && [ ! -e "$T/MARK" ] && [ ! -d "$RH/Project/x" ]; }
cell_n "$TOOL" && ok "ⓝ ../x · \$() · ; 값 전부 rc2 · 원격 호출 0 · 실행 흔적 0" || bad "ⓝ"
b="$(sshn)"; c=""; for kvp in SAT_TMO=9 SAT_TOTAL=90 SAT_TMO=abc SAT_TOTAL=0 SAT_TMO=0; do c="$c $(env "$kvp" bash "$TOOL" pull --seats 'seat-u#0' >/dev/null 2>&1; echo $?)"; done
{ [ "$(sshn)" = "$b" ] && [ "$c" = " 2 2 2 2 2" ]; } && ok "ⓤ SAT_TMO=9·SAT_TOTAL=90·abc·0 → rc2 · 원격 0" || bad "ⓤ rc:$c"

# ⓞ 7초/70초 — open 쪼개기 · 읽기 재시도 1
s0=$SECONDS; call env FAKE_TMUXC_SLEEP=8 bash "$TOOL" open "$T/card.md" --run o1 --name 'byz-satnano-nano-o#1'; el=$((SECONDS - s0))
{ [ "$RC" = 0 ] && hassess 'byz-satnano-nano-o#1' && [ "$el" -lt 50 ]; } && ok "ⓞ-1 느린 tmuxc(8초) → 백그라운드+폴링으로 열림(${el}초)" || bad "ⓞ-1 rc=$RC ${el}초: $O"
bash "$TOOL" close 'byz-satnano-nano-o#1' >/dev/null 2>&1
b="$(sshn)"; echo 1 >"$T/ssh-fails"; call env FAKE_SSH_FAILS="$T/ssh-fails" bash "$TOOL" pull --seats 'seat-o#0'
{ [ "$RC" = 0 ] && [ "$(( $(sshn) - b ))" = 2 ]; } && ok "ⓞ-3 연결 실패 1회 → 읽기 재시도로 성공(ssh 2)" || bad "ⓞ-3 rc=$RC: $O"
b="$(sshn)"; echo 2 >"$T/ssh-fails"; call env FAKE_SSH_FAILS="$T/ssh-fails" bash "$TOOL" pull --seats 'seat-o#0'
{ [ "$RC" = 5 ] && [ "$(( $(sshn) - b ))" = 2 ]; } && ok "ⓞ-4 연결 실패 2회 → 재시도 1회까지(ssh 2) rc5" || bad "ⓞ-4 rc=$RC: $O"
mkdir -p "$T/hangbin"; printf '#!/usr/bin/env bash\nsleep 10\n' >"$T/hangbin/ssh"; chmod 755 "$T/hangbin/ssh"
s0=$SECONDS; call env SAT_TMO=1 PATH="$T/hangbin:$PATH" bash "$TOOL" pull --seats 'seat-o#0'; el=$((SECONDS - s0))
{ [ "$RC" = 5 ] && [ "$el" -le 4 ]; } && ok "ⓞ-5 원격 무응답 → SAT_TMO 에서 끊고 rc5(${el}초)" || bad "ⓞ-5 rc=$RC ${el}초: $O"

# ⓠ lsof rc1 + 사라진 pid → rc6
mkopen "$TOOL" q1 'byz-satnano-nano-q#1'; sleep 0 & dp=$!; wait $dp 2>/dev/null; printf '%s\n' "$dp" >"$T/pi-pids"
call env FAKE_LSOF_RC=1 bash "$TOOL" close 'byz-satnano-nano-q#1'; { [ "$RC" = 6 ] && instate 'byz-satnano-nano-q#1'; } && ok "ⓠ lsof rc1 + 사라진 pid → rc6" || bad "ⓠ rc=$RC: $O"
: >"$T/pi-pids"; bash "$TOOL" close 'byz-satnano-nano-q#1' >/dev/null 2>&1

# ⓡ 커널 잠금 — 보유자 SIGKILL 뒤 즉시 · 5초 못 잡으면 rc1
printf 'r-body\n' >"$T/rb"; seed 905 'seat-r#0' 'mini-r#0' "$T/rb"; : >"$T/calls"
( exec env STUB_MBOX_SLEEP=3 SAT_MBOX_SH="$STUB" bash "$TOOL" pull --seats 'seat-r#0' >/dev/null 2>&1 ) & rk=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ "$(callsn)" -ge 1 ] && break; sleep 0.3; done; kill -9 "$rk" 2>/dev/null; wait "$rk" 2>/dev/null
s0=$SECONDS; call env SAT_MBOX_SH="$STUB" bash "$TOOL" pull --seats 'seat-r#0'; el=$((SECONDS - s0))
{ [ "$RC" != 1 ] && grep -q "PULL" <<<"$O" && [ "$el" -le 3 ]; } && ok "ⓡ-1 잠금 보유자 SIGKILL → 다음 pull 즉시 잠금(${el}초 · rc=$RC)" || bad "ⓡ-1 rc=$RC ${el}초: $O"
( exec 9>>"$SAT_STATE_DIR/pull.flock"; python3 -c 'import fcntl,time;fcntl.flock(9,fcntl.LOCK_EX);time.sleep(8)' ) & hp=$!; sleep 1
s0=$SECONDS; call bash "$TOOL" pull --seats 'seat-r#9'; el=$((SECONDS - s0)); wait $hp 2>/dev/null
{ [ "$RC" = 1 ] && grep -q "다른 pull 진행 중" <<<"$O" && [ "$el" -le 8 ]; } && ok "ⓡ-3 5초 못 잡으면 rc1(${el}초)" || bad "ⓡ-3 rc=$RC: $O"

# ⓢ-1 SENDOK 뒤 255 = 재시도 0 · ⓢ-2(바뀜) SEND 출력 0B 255 = 재시도 0 · rc4
mkopen "$TOOL" s1 'byz-satnano-nano-s#1'; printf '넷\n' >"$T/t4.md"; printf '다섯\n' >"$T/t5.md"
b="$(sshn)"; echo 1 >"$T/ssh-after"; call env FAKE_SSH_AFTER="$T/ssh-after" bash "$TOOL" task 'byz-satnano-nano-s#1' "$T/t4.md"; ns="$(grep -c 's1/TASK-' "$SEND")"
{ [ "$RC" = 0 ] && [ "$(( $(sshn) - b ))" = 1 ] && [ "$ns" = 1 ]; } && ok "ⓢ-1 SENDOK 뒤 rc255 → 재시도 0 · 입력 1" || bad "ⓢ-1 rc=$RC: $O"
b="$(sshn)"; echo 1 >"$T/ssh-lost"; call env FAKE_SSH_LOST="$T/ssh-lost" bash "$TOOL" task 'byz-satnano-nano-s#1' "$T/t5.md"
{ [ "$RC" = 4 ] && [ "$(( $(sshn) - b ))" = 1 ] && grep -q "불확실" <<<"$O"; } && ok "ⓢ-2 SEND 출력 0B rc255 → 재시도 0(ssh 1) · rc4 불확실" || bad "ⓢ-2 rc=$RC ssh: $O"
bash "$TOOL" close 'byz-satnano-nano-s#1' >/dev/null 2>&1

# ⓚ(바뀜) send-keys 실패 → rc4 · 같은 명령 = CLAIMED rc4 입력 0 · --retry = 입력 1
mkopen "$TOOL" k1 'byz-satnano-nano-k#1'; printf '셋\n' >"$T/t3.md"; : >"$T/sendfail"
call env FAKE_SEND_FAIL="$T/sendfail" bash "$TOOL" task 'byz-satnano-nano-k#1' "$T/t3.md"; k1="$RC"; rm -f "$T/sendfail"
call bash "$TOOL" task 'byz-satnano-nano-k#1' "$T/t3.md"; k2="$RC"; o2="$O"; n2="$(grep -c 'k1/TASK-' "$SEND")"
call bash "$TOOL" task 'byz-satnano-nano-k#1' "$T/t3.md" --retry; n3="$(grep -c 'k1/TASK-' "$SEND")"
{ [ "$k1" = 4 ] && [ "$k2" = 4 ] && grep -q CLAIMED <<<"$o2" && [ "$n2" = 0 ] && [ "$RC" = 0 ] && [ "$n3" = 1 ]; } \
  && ok "ⓚ send-keys 실패 rc4 → 재호출 CLAIMED rc4 입력 0 → --retry 입력 1" || bad "ⓚ rc=$k1/$k2/$RC 입력=$n2/$n3: $o2 | $O"
bash "$TOOL" close 'byz-satnano-nano-k#1' >/dev/null 2>&1

# ⓛ(바뀜) 꼬리표 줄 제거 뒤 바이트 동일(끝 개행 2개)
rm -rf "$STUB_SENT_DIR"; printf 'a b\n\n' >"$T/exp-l"; seed 902 'seat-l#0' 'mini-l#0' "$T/exp-l"
call env SAT_MBOX_SH="$STUB" bash "$TOOL" pull --seats 'seat-l#0'; f="$(find "$STUB_SENT_DIR" -type f | head -1)"
python3 -c 'import sys;b=open(sys.argv[1],"rb").read();h,_,r=b.partition(b"\n");open(sys.argv[2],"wb").write(r);sys.exit(0 if h==b"[sat mini:902 from=mini-l#0]" else 1)' "$f" "$T/got-l" 2>/dev/null; th=$?
{ [ "$RC" = 0 ] && [ "$th" = 0 ] && cmp -s "$T/got-l" "$T/exp-l" && [ "$(rpend 'seat-l#0')" = 0 ]; } && ok "ⓛ 꼬리표 [sat mini:902 from=…] + 원문 바이트 동일" || bad "ⓛ rc=$RC th=$th: $O"

# ⓣ(바뀜) 총 2초·배달 3초 → 배달 0 · intent 유지 · rc5 → 다음 pull 은 창 안 skip → SAT_FAKE_NOW 로 창 경과 → 재발신 1
rm -rf "$STUB_SENT_DIR"; : >"$T/calls"; printf 't1\n' >"$T/tb1"; seed 907 'seat-t#0' 'mini-t#0' "$T/tb1"
s0=$SECONDS; call env STUB_MBOX_SLEEP=3 SAT_TOTAL=2 SAT_MBOX_SH="$STUB" bash "$TOOL" pull --seats 'seat-t#0'; el=$((SECONDS - s0)); t1="$RC"; o1="$O"
call env SAT_MBOX_SH="$STUB" bash "$TOOL" pull --seats 'seat-t#0'; t2="$RC"; c2="$(callsn)"
call env SAT_FAKE_NOW=$(( $(date +%s) + 100 )) SAT_MBOX_SH="$STUB" bash "$TOOL" pull --seats 'seat-t#0'
{ [ "$t1" = 5 ] && grep -q "총 마감" <<<"$o1" && [ "$el" -le 4 ] && [ "$c2" = 1 ] && [ "$t2" = 7 ] && [ "$RC" = 0 ] && [ "$(callsn)" = 2 ] && [ "$(sentn)" = 1 ] && [ "$(lastst 907)" = "done" ]; } \
  && ok "ⓣ 총 2초·배달 3초 → rc5 배달 0 · 다음 pull 창 안 skip(rc7) · 창 경과 → 재발신 1 · done" || bad "ⓣ $t1 $o1 | t2=$t2 c2=$c2 calls=$(callsn) sent=$(sentn): $O"

# ══ 새 칸 ══
# Ⓐ 고아 배달 상한 — 보유자 SIGKILL → 즉시 pull 발신 0 · 창 뒤 발신 1(꼬리표 동일) · 재발신 상한 넘으면 dead·격리
cell_A() { local t="$1" s="$2" st="$T/st-A$2" hk FN c1 r1; : >"$T/calls"; printf 'A-body\n' >"$T/Ab"; seed "$s" "seat-A$s#0" 'mini-A#0' "$T/Ab"
  ( exec env STUB_MBOX_SLEEP=3 SAT_STATE_DIR="$st" SAT_MBOX_SH="$STUB" bash "$t" pull --seats "seat-A$s#0" >/dev/null 2>&1 ) & hk=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ "$(callsn)" -ge 1 ] && break; sleep 0.3; done; kill -9 "$hk" 2>/dev/null; wait "$hk" 2>/dev/null
  call env SAT_STATE_DIR="$st" SAT_MBOX_SH="$STUB" bash "$t" pull --seats "seat-A$s#0"; c1="$(callsn)"; r1="$RC"
  FN=$(( $(date +%s) + 100 )); call env SAT_FAKE_NOW="$FN" SAT_STATE_DIR="$st" SAT_MBOX_SH="$STUB" bash "$t" pull --seats "seat-A$s#0"
  [ "$c1" = 1 ] && [ "$r1" = 7 ] && [ "$RC" = 0 ] && [ "$(callsn)" = 2 ] && [ "$(sed -n 1p "$T/calls")" = "$(sed -n 2p "$T/calls")" ] || return 1
  : >"$T/calls"; seed "$((s + 1))" "seat-A$s#1" 'mini-A#0' "$T/Ab"
  for k in 0 100 200; do env SAT_FAKE_NOW=$((FN + 300 + k)) SAT_RESEND_MAX=2 STUB_MBOX_MODE=ratelimit SAT_STATE_DIR="$st" SAT_MBOX_SH="$STUB" bash "$t" pull --seats "seat-A$s#1" >"$T/A.out" 2>&1; done
  [ "$(callsn)" = 2 ] && grep -q "ERROR dead seq=$((s + 1))" "$T/A.out" && [ -s "$RMBOX/quarantine/seq-$((s + 1)).json" ] && [ "$(rpend "seat-A$s#1")" = 0 ]; }
cell_A "$TOOL" 910 && ok "Ⓐ 고아 배달: 즉시 pull 발신 0(rc7) · 창 뒤 1(꼬리표 동일) · 상한 2 넘으면 dead·격리·발신 0" || bad "Ⓐ calls=$(callsn): $O"

# Ⓑ 마지막 단계 뒤 마감 (함수 직접 · 대역 시계) — 배달 1.9초 + 읽기 0.2초 / 총 2초 → rc5 · ack 0 · 다음 pull 중복 0 · ack 실패 rc7
cell_B() { local bd; bd="$(dirname "$1")"; [ "$(python3 - "$bd" "$T/st-B-$2" <<'PY' | tail -1
import base64, json, os, sys
bd, st = sys.argv[1], sys.argv[2]
os.environ["SAT_STATE_DIR"] = st
os.makedirs(st, exist_ok=True)
sys.path.insert(0, bd)
import ft_sat_nano as m
rt = m.rt
class C:
    t = 0.0
    def __call__(self):
        return self.t
clk = C()
real = rt.Deadline
rt.Deadline = lambda total, tmo: real(total, tmo, clock=clk)
rows = [{"seq": 950, "to": "s#0", "from": "f#0", "b64": base64.b64encode(b"x\n").decode()}]
log, ack_rc, sends = [], [0], []
def fake_rcall(dl, script, *a, **k):
    if a and a[0] == m.PY_READ:
        clk.t += 0.2
        return 0, json.dumps(rows).encode(), ""
    log.append(a[2])
    return ack_rc[0], b"1\n", ""
def slow_send(argv, timeout, stdin=None):
    sends.append(argv)
    clk.t += 1.9
    return 0, b"QUEUED seq=7 to=s#0 pending=1 file=x\n", ""
rt.rcall, rt.run_child = fake_rcall, slow_send
cfg = {"tmo": 7, "total": 2, "resend_max": 3}
r = []
try:
    m.pull_once("s#0", cfg, "/stub", 1, "0")
    r.append("rc0")
except rt.Fail as e:
    r.append("rc%d" % e.rc)
r += ["ack" if "ack" in log else "noack", str(rt.delivered_last("mini:950")[0])]
log.clear()
n0 = len(sends)
cfg2 = dict(cfg, total=70)
r += ["rc%d" % m.pull_once("s#0", cfg2, "/stub", 2, "0"), "ack" if "ack" in log else "noack", "resend%d" % (len(sends) - n0)]
rows[0] = {"seq": 951, "to": "s#0", "from": "f#0", "b64": base64.b64encode(b"y\n").decode()}
ack_rc[0] = 1
r.append("rc%d" % m.pull_once("s#0", cfg2, "/stub", 3, "0"))
print(" ".join(r))
PY
)" = "rc5 noack done rc0 ack resend0 rc7" ]; }
cell_B "$BIN/ft-sat-nano.sh" 0 && ok "Ⓑ 마지막 배달이 마감을 넘으면 rc5(ack 0) · 다음 pull 재발신 0·ack 1 · ack 실패 rc7" || bad "Ⓑ"

# Ⓒ claim 장벽 — claim 뒤·sent 전 재호출 = CLAIMED rc4 입력 0 · sent 뒤 ALREADY · --retry 입력 1
cell_C() { local t="$1" s="$2" bp n1 n2 rb; mkopen "$t" "c$s" "byz-satnano-nano-c#$s" || return 1; printf 'C-%s\n' "$s" >"$T/tc$s.md"; : >"$T/barrier$s"
  ( FAKE_SEND_BARRIER="$T/barrier$s" bash "$t" task "byz-satnano-nano-c#$s" "$T/tc$s.md" >/dev/null 2>&1 ) & bp=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do compgen -G "$RH/$ROOTR/c$s/.sent/TASK-*" >/dev/null && break; sleep 0.3; done
  call bash "$t" task "byz-satnano-nano-c#$s" "$T/tc$s.md"; rb="$RC"; rbo="$O"; n1="$(grep -c "c$s/TASK-" "$SEND")"
  rm -f "$T/barrier$s"; wait $bp
  call bash "$t" task "byz-satnano-nano-c#$s" "$T/tc$s.md"; n2="$(grep -c "c$s/TASK-" "$SEND")"; grep -q SKIP <<<"$O" || return 1
  call bash "$t" task "byz-satnano-nano-c#$s" "$T/tc$s.md" --retry
  bash "$t" close "byz-satnano-nano-c#$s" >/dev/null 2>&1
  [ "$rb" = 4 ] && grep -q CLAIMED <<<"$rbo" && [ "$n1" = 0 ] && [ "$n2" = 1 ] && [ "$RC" = 0 ] && [ "$(grep -c "c$s/TASK-" "$SEND")" = 2 ]; }
cell_C "$TOOL" 1 && ok "Ⓒ claim 장벽: 진행 중 재호출 CLAIMED rc4 입력 0 · 끝난 뒤 ALREADY · --retry 입력 1" || bad "Ⓒ: $O"

# Ⓓ 설정 10진 — 08·07 rc0 · 0x7·7.0·-1 rc2
cell_D() { local r=""; for kvp in SAT_TOTAL=08 SAT_TMO=07; do r="$r $(env "$kvp" bash "$1" pull --seats 'seat-d#0' >/dev/null 2>&1; echo $?)"; done
  for kvp in SAT_TMO=0x7 SAT_TMO=7.0 SAT_TMO=-1; do r="$r $(env "$kvp" bash "$1" pull --seats 'seat-d#0' >/dev/null 2>&1; echo $?)"; done; [ "$r" = " 0 0 2 2 2" ]; }
cell_D "$TOOL" && ok "Ⓓ SAT_TOTAL=08·SAT_TMO=07 rc0 · 0x7·7.0·-1 rc2" || bad "Ⓓ"

# Ⓕ 장부 쓰기 실패 = rc2 · ssh 0 (chmod 400 · fsync 예외)
cell_F() { local st="$T/st-F$2" b r1 r2; mkdir -p "$st"; : >"$st/opened.tsv"; chmod 400 "$st/opened.tsv"; b="$(sshn)"
  SAT_STATE_DIR="$st" bash "$1" open "$T/card.md" --run "f$2" --name "byz-satnano-nano-f#$2" >/dev/null 2>&1; r1=$?; chmod 600 "$st/opened.tsv"
  SAT_TEST_FSYNC_FAIL=1 PYTHONPATH="$T/fsyncinj" SAT_STATE_DIR="$st" bash "$1" open "$T/card.md" --run "f$2b" --name "byz-satnano-nano-f#${2}9" >/dev/null 2>&1; r2=$?
  [ "$r1" = 2 ] && [ "$r2" = 2 ] && [ "$(sshn)" = "$b" ]; }
cell_F "$TOOL" 1 && ok "Ⓕ 장부 chmod 400 · fsync 예외 → rc2 · 원격 호출 0" || bad "Ⓕ"

# Ⓖ SEND 부모 폴더 실패 = rc4 · ALREADY 아님 · 입력 0
mkopen "$TOOL" gg 'byz-satnano-nano-gg#1'; printf 'G\n' >"$T/tg.md"
call env FAKE_MKDIR_FAIL_SENT=1 bash "$TOOL" task 'byz-satnano-nano-gg#1' "$T/tg.md"
{ [ "$RC" = 4 ] && ! grep -q SKIP <<<"$O" && [ "$(grep -c 'gg/TASK-' "$SEND")" = 0 ]; } && ok "Ⓖ .sent 부모 생성 실패 → rc4 · 입력 0" || bad "Ⓖ rc=$RC: $O"
bash "$TOOL" close 'byz-satnano-nano-gg#1' >/dev/null 2>&1

# Ⓗ ① RATE_LIMIT rc≠0 · ② rc0 비정형(queued ok · seq=abc · 둘째 줄 QUEUED) → done 0 · intent 유지 → 창 뒤 정상 재발신 → done
cell_H() { local t="$1" s="$2" st="$T/st-H$2" FN k=0 m; : >"$T/calls"; printf 'H\n' >"$T/Hb"; seed "$s" "seat-H$s#0" 'mini-H#0' "$T/Hb"; FN=$(date +%s)
  for m in ratelimit lc abc second; do
    env SAT_FAKE_NOW=$((FN + k)) SAT_RESEND_MAX=9 STUB_MBOX_MODE="$m" SAT_STATE_DIR="$st" SAT_MBOX_SH="$STUB" bash "$t" pull --seats "seat-H$s#0" >/dev/null 2>&1 || true
    [ "$(SAT_STATE_DIR="$st" lastst "$s")" = intent ] && [ "$(rpend "seat-H$s#0")" = 1 ] || return 1; k=$((k + 100)); done
  env SAT_FAKE_NOW=$((FN + k)) SAT_RESEND_MAX=9 SAT_STATE_DIR="$st" SAT_MBOX_SH="$STUB" bash "$t" pull --seats "seat-H$s#0" >/dev/null 2>&1
  [ "$(callsn)" = 5 ] && [ "$(SAT_STATE_DIR="$st" lastst "$s")" = "done" ] && [ "$(rpend "seat-H$s#0")" = 0 ]; }
cell_H "$TOOL" 920 && ok "Ⓗ RATE_LIMIT·queued ok·seq=abc·둘째 줄 QUEUED → done 0·intent 유지 → 창 뒤 재발신 1 → done" || bad "Ⓗ calls=$(callsn)"

# Ⓘ ① Deadline.child_timeout 직접 · ② 단계 전 검사 직후 남은 시간 0 → rcall 자식 실행 0 rc5
cell_I() { [ "$(python3 - "$(dirname "$1")" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import ft_sat_rt as rt
class C:
    t = 0.0
    def __call__(self):
        return self.t
r = []
c = C()
d = rt.Deadline(2, 7, clock=c)
c.t = 1.0
r.append("t%.1f" % d.child_timeout())
c.t = 2.0
try:
    d.child_timeout()
    r.append("noraise")
except rt.Fail as e:
    r.append("rc%d" % e.rc)
pops = []
class P:
    pid, returncode = 1, 0
    def __init__(self, *a, **k):
        pops.append(a)
    def communicate(self, *a, **k):
        return b"", b""
rt.subprocess.Popen = P
c2 = C()
d2 = rt.Deadline(2, 7, clock=c2)
d2.check("x")
c2.t = 2.0
try:
    rt.rcall(d2, "echo hi")
    r.append("noraise")
except rt.Fail as e:
    r.append("rc%d" % e.rc)
r.append("popen%d" % len(pops))
print(" ".join(r))
PY
)" = "t1.0 rc5 rc5 popen0" ]; }
cell_I "$TOOL" && ok "Ⓘ ① 남은 시간 0 이하 = 예외 rc5 · ② 경계에서 자식 실행 0" || bad "Ⓘ"

# Ⓙ pid 재사용(lstart 다름) → 표시만 · open rc4 기록 유지 · close rc4
call env FAKE_TMUXC_ARM_PS=1 FAKE_TMUXC_WAITPOLL=1 bash "$TOOL" open "$T/card.md" --run jj --name 'byz-satnano-nano-jj#1'; j1="$RC"; jo="$O"
waitsess 'byz-satnano-nano-jj#1'; call bash "$TOOL" close 'byz-satnano-nano-jj#1'
{ [ "$j1" = 4 ] && grep -q "열기 불확실" <<<"$jo" && [ "$RC" = 4 ] && instate 'byz-satnano-nano-jj#1' && hassess 'byz-satnano-nano-jj#1'; } && ok "Ⓙ pid 재사용 → alive 0 = 표시만 · open rc4 · close rc4 · 세션·기록 유지" || bad "Ⓙ $j1 | $RC $O"
bash "$TOOL" close 'byz-satnano-nano-jj#1' --adopt >/dev/null 2>&1

# Ⓚ 확인된 줄 gone + pi 잔존 / lsof 실패 → rc6 · 고침 3: rc1 다른 글 → rc6 · can't find(신원 참) → gone
cell_K() { local t="$1" s="$2"; mkopen "$t" "kk$s" "byz-satnano-nano-kk#$s" || return 1; dropsess "byz-satnano-nano-kk#$s"
  printf '61\n' >"$T/pi-pids"; printf '61|%s\n' "$RH/$ROOTR/kk$s" >"$T/pi-cwds"; call bash "$t" close "byz-satnano-nano-kk#$s"; local a="$RC"
  : >"$T/pi-cwds"; call env FAKE_LSOF_RC=1 bash "$t" close "byz-satnano-nano-kk#$s"; local b="$RC"; : >"$T/pi-pids"
  instate "byz-satnano-nano-kk#$s" && [ "$a" = 6 ] && [ "$b" = 6 ]; }
cell_K "$TOOL" 1 && ok "Ⓚ 확인된 줄 gone + pi 잔존 → rc6 · gone + lsof 실패 → rc6 · 기록 유지" || bad "Ⓚ: $O"
cell_K3() { local t="$1" s="$2"; mkopen "$t" "x$s" "byz-satnano-nano-x#$s" || return 1
  call env FAKE_HAS_ERR="error connecting to /tmp/x (Permission denied)" bash "$t" close "byz-satnano-nano-x#$s"; local a="$RC"
  instate "byz-satnano-nano-x#$s" && hassess "byz-satnano-nano-x#$s" && [ "$a" = 6 ] || return 1
  dropsess "byz-satnano-nano-x#$s"; call env FAKE_NO_SERVER=1 bash "$t" close "byz-satnano-nano-x#$s"; [ "$RC" = 0 ] && ! instate "byz-satnano-nano-x#$s"; }
cell_K3 "$TOOL" 1 && ok "고침3 close: has-session rc1 + 다른 글 → rc6(세션·기록 유지) · 정상 «없음»(no server) + 신원 참 → gone rc0" || bad "고침3 close: $O"

# Ⓛ-0 OPEN_BG 재시도 — ⓐ 출력만 잃음 → running · opener 1 · ⓑ pid 기록 실패 + 출력 잃음 → claimed rc4 · opener 1
cell_L0() { local t="$1" s="$2"; echo 1 >"$T/lost$s"
  call env FAKE_SSH_LOST="$T/lost$s" FAKE_SSH_PAT=.open.claim bash "$t" open "$T/card.md" --run "l0a$s" --name "byz-satnano-nano-l0a#$s"
  [ "$RC" = 0 ] && [ "$(opensn "byz-satnano-nano-l0a#$s")" = 1 ] || return 1; bash "$t" close "byz-satnano-nano-l0a#$s" >/dev/null 2>&1; echo 1 >"$T/lost$s"
  call env FAKE_SSH_LOST="$T/lost$s" FAKE_SSH_PAT=.open.claim FAKE_MV_FAIL_PID=1 bash "$t" open "$T/card.md" --run "l0b$s" --name "byz-satnano-nano-l0b#$s"
  waitsess "byz-satnano-nano-l0b#$s"; sleep 1; local r="$RC" o="$O"; bash "$t" close "byz-satnano-nano-l0b#$s" --adopt >/dev/null 2>&1
  [ "$r" = 4 ] && grep -q "상태=claimed" <<<"$o" && [ "$(opensn "byz-satnano-nano-l0b#$s")" = 1 ]; }
cell_L0 "$TOOL" 1 && ok "Ⓛ-0 OPEN_BG 출력 0B rc255 → 재시도 = 상태 응답(running · opener 1) · pid 전 끊김 → claimed rc4 · opener 1" || bad "Ⓛ-0: $O"
# Ⓛ-1 claim 직후 종료(+출력 잃음) → 재호출 claimed · open rc4 · opener 0 · close rc4 원격 0 · --forget 뒤에만 삭제
cell_L1() { local t="$1" s="$2" b r o; echo 1 >"$T/lost1$s"; b="$(sshn)"
  call env FAKE_SSH_LOST="$T/lost1$s" FAKE_SSH_PAT=.open.claim FAKE_MKDIR_DIE_CLAIM=1 bash "$t" open "$T/card.md" --run "l1$s" --name "byz-satnano-nano-l1#$s"; r="$RC"; o="$O"
  [ "$r" = 4 ] && grep -q "상태=claimed" <<<"$o" && [ "$(( $(sshn) - b ))" = 4 ] && [ "$(opensn "byz-satnano-nano-l1#$s")" = 0 ] && instate "byz-satnano-nano-l1#$s" || return 1
  b="$(sshn)"; call bash "$t" close "byz-satnano-nano-l1#$s"; [ "$RC" = 4 ] && instate "byz-satnano-nano-l1#$s" || return 1
  call bash "$t" close "byz-satnano-nano-l1#$s" --forget --why "claim 뒤 종료 · mini tmux ls 확인 0건"; [ "$RC" = 0 ] && ! instate "byz-satnano-nano-l1#$s" && [ "$(sshn)" = "$b" ]; }
cell_L1 "$TOOL" 1 && ok "Ⓛ-1 claim 직후 종료 → claimed rc4 · opener 0 · close rc4 · --forget 뒤에만 삭제 · ssh 0" || bad "Ⓛ-1: $O"
# Ⓛ-2 claim 생성 실패 → claim_fail · 고침 1: rc4 · 줄 유지 · close rc4 · --forget 뒤에만 삭제
cell_L2() { local t="$1" s="$2" r o; call env FAKE_MKDIR_FAIL_CLAIM=1 bash "$t" open "$T/card.md" --run "l2$s" --name "byz-satnano-nano-l2#$s"; r="$RC"; o="$O"
  [ "$r" = 4 ] && grep -q "claim_fail" <<<"$o" && instate "byz-satnano-nano-l2#$s" && [ "$(opensn "byz-satnano-nano-l2#$s")" = 0 ] || return 1
  call bash "$t" close "byz-satnano-nano-l2#$s"; [ "$RC" = 4 ] && instate "byz-satnano-nano-l2#$s" || return 1
  call bash "$t" close "byz-satnano-nano-l2#$s" --forget --why "claim_fail · 원격 폴더 권한"; [ "$RC" = 0 ] && ! instate "byz-satnano-nano-l2#$s"; }
cell_L2 "$TOOL" 1 && ok "Ⓛ-2 claim_fail → rc4 · 줄 유지(고침 1) · close rc4 · --forget 뒤에만 삭제" || bad "Ⓛ-2: $O"
# Ⓛ-3 nohup 뒤·pid 전 종료 → rc4 · 줄 유지 · 세션이 뒤에 생겨도 close rc4 · --forget 은 기록만(원격 0)
call env FAKE_MV_FAIL_PID=1 bash "$TOOL" open "$T/card.md" --run l3 --name 'byz-satnano-nano-l3#1'; l3="$RC"; l3o="$O"; waitsess 'byz-satnano-nano-l3#1'
call bash "$TOOL" close 'byz-satnano-nano-l3#1'; l3b="$RC"; b="$(sshn)"
call bash "$TOOL" close 'byz-satnano-nano-l3#1' --forget --why "pid 기록 실패 · 오빠 h 로 mini kill-session 예정"
{ [ "$l3" = 4 ] && grep -q "열기 불확실" <<<"$l3o" && [ "$l3b" = 4 ] && [ "$RC" = 0 ] && ! instate 'byz-satnano-nano-l3#1' && hassess 'byz-satnano-nano-l3#1' && [ "$(sshn)" = "$b" ]; } \
  && ok "Ⓛ-3 pid 전 종료 → rc4 · 뒤늦은 세션에도 close rc4 · --forget = 기록만(세션 그대로 · ssh 0)" || bad "Ⓛ-3 $l3 | $l3b | $RC $O"
dropsess 'byz-satnano-nano-l3#1'
# Ⓛ-4 opener 끝(done)·세션 없음 → rc4 · 줄 유지(폴링 rowdel 0) · --forget
cell_L4() { local t="$1" s="$2"; call env FAKE_TMUXC_NOSESS=1 bash "$t" open "$T/card.md" --run "l4$s" --name "byz-satnano-nano-l4#$s"
  [ "$RC" = 4 ] && grep -q "세션 없음 done=3" <<<"$O" && instate "byz-satnano-nano-l4#$s" || return 1
  call bash "$t" close "byz-satnano-nano-l4#$s" --forget --why "opener 실패 done=3"; [ "$RC" = 0 ] && ! instate "byz-satnano-nano-l4#$s"; }
cell_L4 "$TOOL" 1 && ok "Ⓛ-4 opener 끝·세션 없음 → rc4 · 줄 유지 · --forget 뒤 삭제" || bad "Ⓛ-4: $O"

# Ⓜ ① 정상 = 지시문 입력 1(대입된 \$msg) · ② 빈 \$msg 주입 → exit 4 · sent 0 · 입력 0 · ③ 빈 파일 → rc4
cell_M() { local t="$1" s="$2"; mkopen "$t" "m$s" "byz-satnano-nano-m#$s" || return 1; printf 'M\n' >"$T/tm$s.md"
  call bash "$t" task "byz-satnano-nano-m#$s" "$T/tm$s.md"; local r="$RC"; bash "$t" close "byz-satnano-nano-m#$s" >/dev/null 2>&1
  [ "$r" = 0 ] && grep -q "byz-satnano-nano-m#$s|.*\[발주 #1\] .*m$s/TASK-" "$SEND"; }
cell_M "$TOOL" 1 && ok "Ⓜ-1 정상 task → 지시문([발주 #1] <파일>) 입력 1" || bad "Ⓜ-1: $O"
MM="$(mut minject nano 'msg="[발주 #1] $f 를 읽고 그대로 수행해라. 결과는 같은 폴더 out.md."' 'msg=""')"
mkopen "$TOOL" m2 'byz-satnano-nano-m#2'; printf 'M2\n' >"$T/tm2.md"; call bash "$MM" task 'byz-satnano-nano-m#2' "$T/tm2.md"
{ [ "$RC" = 4 ] && [ "$(grep -c 'm2/TASK-' "$SEND")" = 0 ] && [ -z "$(find "$RH/$ROOTR/m2/.sent" -name sent -path '*TASK-*')" ]; } && ok "Ⓜ-2 비어 있지 않은 파일 + 빈 \$msg 주입 → rc4 · sent 0 · 입력 0" || bad "Ⓜ-2 rc=$RC: $O"
: >"$T/empty.md"; call bash "$TOOL" task 'byz-satnano-nano-m#2' "$T/empty.md"
{ [ "$RC" = 4 ] && [ "$(grep -c 'm2/TASK-' "$SEND")" = 0 ]; } && ok "Ⓜ-3 빈 파일 task → rc4 · 입력 0" || bad "Ⓜ-3 rc=$RC: $O"
bash "$TOOL" close 'byz-satnano-nano-m#2' >/dev/null 2>&1

# Ⓝ 불확실 줄 — 벽시계 전진 · LIMIT 변경 · 뒤늦은 세션 → close 전부 rc4 · 삭제 0 · 원격 0
cell_N() { local t="$1" s="$2" b r=""; pending "$t" "n$s" "byz-satnano-nano-nn#$s" || return 1; b="$(sshn)"
  r="$r $(SAT_FAKE_NOW=9999999999 bash "$t" close "byz-satnano-nano-nn#$s" >/dev/null 2>&1; echo $?)"
  r="$r $(SAT_OPEN_LIMIT=10 bash "$t" close "byz-satnano-nano-nn#$s" >/dev/null 2>&1; echo $?)"
  waitsess "byz-satnano-nano-nn#$s"; r="$r $(bash "$t" close "byz-satnano-nano-nn#$s" >/dev/null 2>&1; echo $?)"
  local okk=1; [ "$r" = " 4 4 4" ] && instate "byz-satnano-nano-nn#$s" && hassess "byz-satnano-nano-nn#$s" && [ "$(sshn)" = "$b" ] && okk=0
  bash "$t" close "byz-satnano-nano-nn#$s" --adopt >/dev/null 2>&1 || bash "$TOOL" close "byz-satnano-nano-nn#$s" --adopt >/dev/null 2>&1; return $okk; }
cell_N "$TOOL" 1 && ok "Ⓝ 벽시계 전진·LIMIT 변경·뒤늦은 세션 → close rc4 · 삭제 0 · 원격 0" || bad "Ⓝ"

# Ⓞ POLL 조회 실패 → open rc6 · 기록 유지 · IDENT·SEND 0 (has-session rc2 · rc1 + 다른 글 = 고침 3)
cell_O() { local t="$1" s="$2" c b; for c in 2 1e; do b="$(sshn)"
    call env FAKE_TMUXC_ARM_HAS="$c" bash "$t" open "$T/card.md" --run "o$s$c" --name "byz-satnano-nano-oo#$s${c%e}"; rm -f "$RSESS.hasrc"
    [ "$RC" = 6 ] && instate "byz-satnano-nano-oo#$s${c%e}" && ! tail -n +"$((b + 1))" "$T/sshlog" | grep -q 'session_id\|send-keys' || return 1
    bash "$t" close "byz-satnano-nano-oo#$s${c%e}" --forget --why "시험 정리" >/dev/null 2>&1; done; }
cell_O "$TOOL" 1 && ok "Ⓞ POLL sess_rc=2 · rc1+다른 글 → open rc6 · 기록 유지 · 신원 조회·입력 0" || bad "Ⓞ: $O"

# Ⓟ --forget — pending 만 · 이유 필수(고침 2) · 확인된 줄 rc2 · 없는 이름 rc5 · ssh 0 · forgotten.tsv 1줄(11칸)
cell_P() { local t="$1" s="$2" b a1 a2 a3 a4 a5; pending "$t" "p$s" "byz-satnano-nano-pp#$s" || return 1; mkopen "$t" "pc$s" "byz-satnano-nano-pc#$s" || return 1; b="$(sshn)"
  bash "$t" close "byz-satnano-nano-pp#$s" --forget >/dev/null 2>&1; a1=$?
  bash "$t" close "byz-satnano-nano-pp#$s" --forget --why "   " >/dev/null 2>&1; a2=$?
  bash "$t" close "byz-satnano-nano-pc#$s" --forget --why "확인된 줄" >/dev/null 2>&1; a3=$?
  bash "$t" close "byz-satnano-nano-none#$s" --forget --why "없음" >/dev/null 2>&1; a4=$?
  instate "byz-satnano-nano-pp#$s" && instate "byz-satnano-nano-pc#$s" || return 1
  FT_SEAT="tester#1" bash "$t" close "byz-satnano-nano-pp#$s" --forget --why "열기 마감 · 세션 없음 확인" >/dev/null 2>&1; a5=$?; local a6; a6="$(sshn)"
  waitsess "byz-satnano-nano-pp#$s"; dropsess "byz-satnano-nano-pp#$s"; bash "$TOOL" close "byz-satnano-nano-pc#$s" >/dev/null 2>&1
  PD="$a1$a2$a3$a4$a5 ssh ${b}→${a6}"; [ "$a1$a2$a3$a4$a5" = "22250" ] && [ "$a6" = "$b" ] && ! instate "byz-satnano-nano-pp#$s" \
    && awk -F'\t' -v n="byz-satnano-nano-pp#$s" 'NF==12 && $2=="tester#1" && $4==n && $12=="열기 마감 · 세션 없음 확인"' "$SAT_STATE_DIR/forgotten.tsv" | grep -q .; }
cell_P "$TOOL" 1 && ok "Ⓟ --forget: 이유 없음·공백 rc2 · 확인된 줄 rc2 · 없는 이름 rc5 · pending 만 rc0 · ssh 0 · forgotten 1줄(12칸)" || bad "Ⓟ ${PD:-}"

# Ⓠ/Ⓔ/ⓥ --adopt — open 마감 rc5 → close rc4 → 세션 생성 뒤에도 rc4 → --adopt(폴더 일치) 신원 채움·닫힘 · 폴더 다름/세션 없음/조회 실패 rc4 삭제 0
cell_Q() { local t="$1" s="$2" r1 r2 r3 r4 r5; QD="pending"; pending "$t" "qa$s" "byz-satnano-nano-qq#$s" || return 1
  bash "$t" close "byz-satnano-nano-qq#$s" >/dev/null 2>&1; r1=$?; waitsess "byz-satnano-nano-qq#$s"; bash "$t" close "byz-satnano-nano-qq#$s" >/dev/null 2>&1; r2=$?
  awk -F'|' -v OFS='|' -v n="byz-satnano-nano-qq#$s" '$1==n{$4="/some/other/dir"}{print}' "$RSESS.meta" >"$RSESS.t"; cp "$RSESS.meta" "$T/meta.bak"; mv "$RSESS.t" "$RSESS.meta"
  bash "$t" close "byz-satnano-nano-qq#$s" --adopt >/dev/null 2>&1; r3=$?; mv "$T/meta.bak" "$RSESS.meta"
  FAKE_HAS_RC=2 bash "$t" close "byz-satnano-nano-qq#$s" --adopt >/dev/null 2>&1; r4=$?
  QD="$r1$r2$r3$r4"; instate "byz-satnano-nano-qq#$s" && hassess "byz-satnano-nano-qq#$s" && ! conf "byz-satnano-nano-qq#$s" || return 1
  call bash "$t" close "byz-satnano-nano-qq#$s" --adopt; r5="$RC"
  [ "$r1$r2$r3$r4$r5" = "44440" ] && ! instate "byz-satnano-nano-qq#$s" && ! hassess "byz-satnano-nano-qq#$s" && grep -q "ADOPT 신원 채움" <<<"$O"; }
cell_Q "$TOOL" 1 && ok "Ⓠ·Ⓔ·ⓥ open 마감 → close rc4(전·후) · --adopt 폴더 다름/조회 실패 rc4 삭제 0 · 폴더 일치 → 신원 채움·닫힘 rc0" || bad "Ⓠ ${QD:-}: $O"
cell_Q2() { local t="$1" s="$2"; call env FAKE_TMUXC_NOSESS=1 bash "$t" open "$T/card.md" --run "q2$s" --name "byz-satnano-nano-q2#$s"
  call bash "$t" close "byz-satnano-nano-q2#$s" --adopt; [ "$RC" = 4 ] && instate "byz-satnano-nano-q2#$s" || return 1
  bash "$t" close "byz-satnano-nano-q2#$s" --forget --why "세션 없음" >/dev/null 2>&1; }
cell_Q2 "$TOOL" 1 && ok "Ⓠ-2 세션 없음에 --adopt → rc4 삭제 0 → --forget rc0" || bad "Ⓠ-2: $O"

# ══ r5 새 칸 (R1 열쇠 = run · R2 삭제 길 둘 · R3 소켓 고정 · 마감) ══
# ⓡ1 동시 open 같은 이름(순서 고정 · 함수 직접) — A 가 장부 잠금을 쥔 R_PRE 중에 B1 open·B2 --forget → rc1(또는 B1 rc2) · 원격 0
#     A 끝난 뒤 B3 open 같은 이름 → rc2 · 원격 0 · A 줄 1개 확인됨 · A close rc0
cell_r1() { local bd; bd="$(dirname "$1")"; R1D="$(python3 - "$bd" "$T/st-r1-$2" "$T/card.md" 2>/dev/null <<'PY' | tail -1
import os, sys
bd, st, card = sys.argv[1:4]
os.environ["SAT_STATE_DIR"] = st
sys.path.insert(0, bd)
import ft_sat_nano as m
rt = m.rt
rt.LOCK_WAIT = 0.3
sess, calls, r = {}, [0], []
def b_side():
    n0 = calls[0]
    r.append("B1=%d" % m.main(["open", card, "--run", "r1b", "--name", "byz-satnano-nano-r1#1"]))
    r.append("B2=%d" % m.main(["close", "byz-satnano-nano-r1#1", "--forget", "--why", "동시 forget"]))
    r.append("Bcalls=%d" % (calls[0] - n0))
hook = [b_side]
ID = "$1 100 /tmp/s.sock /home/x"
def fake(dl, script, *a, **k):
    calls[0] += 1
    if script == m.R_PRE:
        if hook:
            hook.pop()()
        return 0, b"tmuxc=ok\npi=ok\nperl=ok\nsess_rc=%d\nfree=50\ndir=absent\n" % (0 if a[1] in sess else 1), ""
    if script == m.R_OPEN_BG:
        sess[a[1]] = 1
        return 0, b"running\n1 x\n", ""
    if script == m.R_LOOKUP:
        return 0, ("has=0\ndrc=0\nident=%s\ndirmatch=1\n" % ID).encode(), ""
    return 0, {m.R_WRITE: b"", m.R_POLL: b"alive=1\ndone=\nsess_rc=0\n", m.R_IDENT: (ID + "\n").encode(),
               m.R_PIDS: b"1\n", m.R_SEND: b"SENDOK\n", m.R_KILL: m.KILL_OK.encode() + b"\n"}[script], ""
rt.rcall = fake
a = m.main(["open", card, "--run", "r1a", "--name", "byz-satnano-nano-r1#1"])
n0 = calls[0]
b3 = m.main(["open", card, "--run", "r1c", "--name", "byz-satnano-nano-r1#1"])
b3c = calls[0] - n0
rows = [x for x in rt.read_rows("opened.tsv") if x[0] == "byz-satnano-nano-r1#1"]
conf = int(len(rows) == 1 and rt.confirmed(rows[0]))
c = m.main(["close", "byz-satnano-nano-r1#1"])
print("A=%d %s B3=%d B3calls=%d conf=%d close=%d left=%d" % (a, " ".join(r), b3, b3c, conf, c, len(rt.read_rows("opened.tsv"))))
PY
)"; case "$R1D" in "A=0 B1=1 B2=1 Bcalls=0 B3=2 B3calls=0 conf=1 close=0 left=0"|"A=0 B1=2 B2=1 Bcalls=0 B3=2 B3calls=0 conf=1 close=0 left=0") return 0;; esac; return 1; }
cell_r1 "$TOOL" 0 && ok "ⓡ1 동시 open 같은 이름: A 잠금 중 B1 open·B2 --forget rc1 원격 0 · 뒤 B3 rc2 원격 0 · A 줄 유지·확인 · A close rc0" || bad "ⓡ1 ${R1D:-}"

# ⓡ2 R_WRITE 실행 뒤 응답 유실 ×2 → open rc4 · 줄 유지 · close rc4 · --forget 뒤에만 삭제
cell_r2() { local t="$1" s="$2"; echo 2 >"$T/r2lost$s"
  call env FAKE_SSH_LOST="$T/r2lost$s" FAKE_SSH_PAT='mkdir -p "$d" && cat' bash "$t" open "$T/card.md" --run "r2w$s" --name "byz-satnano-nano-r2#$s"
  [ "$RC" = 4 ] && [ -s "$RH/$ROOTR/r2w$s/TASK.md" ] && instate "byz-satnano-nano-r2#$s" && ! conf "byz-satnano-nano-r2#$s" && [ "$(opensn "byz-satnano-nano-r2#$s")" = 0 ] || return 1
  call bash "$t" close "byz-satnano-nano-r2#$s"; [ "$RC" = 4 ] && instate "byz-satnano-nano-r2#$s" || return 1
  call bash "$t" close "byz-satnano-nano-r2#$s" --forget --why "R_WRITE 응답 유실 · 세션 없음"; [ "$RC" = 0 ] && ! instate "byz-satnano-nano-r2#$s"; }
cell_r2 "$TOOL" 1 && ok "ⓡ2 R_WRITE 뒤 응답 유실 ×2 → open rc4 · 줄 유지 · close rc4 · --forget 뒤에만 삭제" || bad "ⓡ2: $O"

# ⓡ3 4칸·9칸 줄 → task·close·fetch·--forget 전부 rc6 · ssh 0 · 입력 0 · 줄 그대로
cell_r3() { local t="$1" st="$T/st-r3$2" b ns n r=""; mkdir -p "$st"
  printf 'byz-satnano-nano-r3a#1\tr3a\t%s/r3a\tts\n' "$ROOTR" >"$st/opened.tsv"
  printf 'byz-satnano-nano-r3b#1\tr3b\t%s/r3b\tts\t$1\t100\t/x\t/s\textra\n' "$ROOTR" >>"$st/opened.tsv"
  printf 'x\n' >"$T/r3t.md"; b="$(sshn)"; ns="$(wc -l <"$SEND" | tr -d ' ')"
  for n in 'byz-satnano-nano-r3a#1' 'byz-satnano-nano-r3b#1'; do
    r="$r $(SAT_STATE_DIR="$st" bash "$t" task "$n" "$T/r3t.md" >/dev/null 2>&1; echo $?)"
    r="$r $(SAT_STATE_DIR="$st" bash "$t" close "$n" >/dev/null 2>&1; echo $?)"
    r="$r $(SAT_STATE_DIR="$st" bash "$t" fetch "$n" >/dev/null 2>&1; echo $?)"
    r="$r $(SAT_STATE_DIR="$st" bash "$t" close "$n" --forget --why x >/dev/null 2>&1; echo $?)"
  done
  R3D="$r"; [ "$r" = " 6 6 6 6 6 6 6 6" ] && [ "$(sshn)" = "$b" ] && [ "$(wc -l <"$SEND" | tr -d ' ')" = "$ns" ] && [ "$(wc -l <"$st/opened.tsv" | tr -d ' ')" = 2 ]; }
cell_r3 "$TOOL" 1 && ok "ⓡ3 4칸·9칸 줄 → task·close·fetch·--forget rc6 · ssh 0 · 입력 0 · 줄 그대로" || bad "ⓡ3 rc:${R3D:-}"

# ⓡ4 tmux 서버 2개 — 소켓 A 에서 열고 기본 소켓을 B(꺼짐)로 바꾼 뒤 close → -S A 로 닫거나 rc6 · B 의 «no server» 로 삭제 0
cell_r4() { local t="$1" s="$2" r; rm -f "$RSESS.B"; mkopen "$t" "r4$s" "byz-satnano-nano-r4#$s" || return 1
  call env FAKE_DEFAULT_SOCK="$FAKE_SOCK_B" bash "$t" close "byz-satnano-nano-r4#$s"; r="$RC"
  if [ "$r" = 0 ] && ! hassess "byz-satnano-nano-r4#$s" && ! instate "byz-satnano-nano-r4#$s"; then return 0; fi
  if [ "$r" = 6 ] && instate "byz-satnano-nano-r4#$s" && hassess "byz-satnano-nano-r4#$s"; then bash "$t" close "byz-satnano-nano-r4#$s" >/dev/null 2>&1; return 0; fi
  instate "byz-satnano-nano-r4#$s" || dropsess "byz-satnano-nano-r4#$s"; return 1; }
cell_r4 "$TOOL" 1 && ok "ⓡ4 서버 2개: 기본 소켓 B(꺼짐)여도 close 는 기록 소켓 A 로 닫음 · B 의 «no server» 로 삭제 0" || bad "ⓡ4: $O"

# ⓡ5 SAT_TOTAL=3 · close 중 장부 잠금 4초 점유 → rc4 · 줄 유지 → 그 뒤 close rc0
#     + 함수 직접(대역 시계): 닫힘 확인(R_KILL) 뒤 마감 넘음 → 삭제 전 검사 rc4 · 줄 유지 → 다시 close = gone 경로 rc0
cell_r5() { local t="$1" s="$2" hp r1 el s0 bd; mkopen "$t" "r5$s" "byz-satnano-nano-r5#$s" || return 1; rm -f "$T/r5mark$s"
  ( exec 9>>"$SAT_STATE_DIR/opened.flock"; python3 -c 'import fcntl,sys,time;fcntl.flock(9,fcntl.LOCK_EX);open(sys.argv[1],"w").close();time.sleep(4)' "$T/r5mark$s" ) & hp=$!
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -e "$T/r5mark$s" ] && break; sleep 0.1; done
  s0=$SECONDS; call env SAT_TOTAL=3 bash "$t" close "byz-satnano-nano-r5#$s"; r1="$RC"; el=$((SECONDS - s0)); wait "$hp" 2>/dev/null
  [ "$r1" = 4 ] && [ "$el" -le 4 ] && instate "byz-satnano-nano-r5#$s" && hassess "byz-satnano-nano-r5#$s" || return 1
  call bash "$t" close "byz-satnano-nano-r5#$s"; [ "$RC" = 0 ] && ! instate "byz-satnano-nano-r5#$s" && ! hassess "byz-satnano-nano-r5#$s" || return 1
  bd="$(dirname "$t")"; [ "$(python3 - "$bd" "$T/st-r5b-$s" 2>/dev/null <<'PY' | tail -1
import os, sys
bd, st = sys.argv[1:3]
os.environ["SAT_STATE_DIR"] = st
os.makedirs(st, exist_ok=True)
sys.path.insert(0, bd)
import ft_sat_nano as m
rt = m.rt
with open(os.path.join(st, "opened.tsv"), "w") as f:
    f.write("byz-satnano-nano-r5b#1\tr5b\tProject/satellite-nano/r5b\tts\t$9\t100\t/home/x\t/tmp/s.sock\n")
with open(os.path.join(st, "roster.json"), "w") as f:  # r949 — 닫기는 명부 표식 줄만
    f.write('{"rows":[{"slug":"r5b","name":"byz-satnano-nano-r5b#1","run":"r5b","status":"OPEN","sock":"/tmp/s.sock","by":"ft-sat-nano"}]}')
class C:
    t = 0.0
    def __call__(self):
        return self.t
clk = C()
real = rt.Deadline
rt.Deadline = lambda total, tmo: real(total, tmo, clock=clk)
st8 = {"has": "0", "slow": True}
def fake(dl, script, *a, **k):
    if script == m.R_LOOKUP:
        return 0, ("has=%s\ndrc=0\nident=$9 100 /tmp/s.sock /home/x\n" % st8["has"]).encode(), ""
    if script == m.R_KILL:
        if st8["slow"]:
            clk.t += 100.0
        return 0, m.KILL_OK.encode() + b"\n", ""
    raise SystemExit("unexpected script")
rt.rcall = fake
r = ["rc%d" % m.main(["close", "byz-satnano-nano-r5b#1"]), "kept" if rt.opened_find("byz-satnano-nano-r5b#1") else "gone"]
st8.update(has="1", slow=False)
r += ["rc%d" % m.main(["close", "byz-satnano-nano-r5b#1"]), "kept" if rt.opened_find("byz-satnano-nano-r5b#1") else "gone"]
print(" ".join(r))
PY
)" = "rc4 kept rc0 gone" ]; }
cell_r5 "$TOOL" 1 && ok "ⓡ5 SAT_TOTAL=3 · 장부 잠금 4초 점유 → close rc4 줄 유지 → 다음 close rc0 · 닫힘 확인 뒤 마감 → 삭제 전 rc4 → 다시 close gone rc0" || bad "ⓡ5: $O"

# ⓡ6 opened.flock 쓰기 불가 → open·close rc2 · ssh 0 · traceback 0
cell_r6() { local t="$1" st="$T/st-r6$2" b r1 r2 o; mkdir -p "$st"; : >"$st/opened.flock"; chmod 400 "$st/opened.flock"; b="$(sshn)"
  o="$(SAT_STATE_DIR="$st" bash "$t" open "$T/card.md" --run "r6$2" --name "byz-satnano-nano-r6#$2" 2>&1)"; r1=$?
  o="$o$(SAT_STATE_DIR="$st" bash "$t" close "byz-satnano-nano-r6#$2" 2>&1)"; r2=$?; chmod 600 "$st/opened.flock"
  R6D="$r1$r2"; [ "$r1$r2" = 22 ] && [ "$(sshn)" = "$b" ] && ! grep -q Traceback <<<"$o"; }
cell_r6 "$TOOL" 1 && ok "ⓡ6 opened.flock 쓰기 불가 → open·close rc2 · ssh 0 · traceback 0" || bad "ⓡ6 rc=${R6D:-}"

# ══ r5 확정 칸 (DECISION-r902-impl-r5-final) ══
# ⓢ1(확정) 신원 3칸 참 + 소켓 빔 → close·--forget·task·--adopt·fetch 전부 rc6 · ssh 0 · 입력 0 · 줄 그대로
cell_s1() { local t="$1" st="$T/st-s1$2" b ns r=""; mkdir -p "$st"
  printf 'byz-satnano-nano-s1#1\ts1\t%s/s1\tts\t$5\t100\t%s/s1\t\n' "$ROOTR" "$RH/$ROOTR" >"$st/opened.tsv"; cp "$st/opened.tsv" "$st/before"
  printf 'x\n' >"$T/s1t.md"; b="$(sshn)"; ns="$(wc -l <"$SEND" | tr -d ' ')"
  r="$r $(SAT_STATE_DIR="$st" bash "$t" close 'byz-satnano-nano-s1#1' >/dev/null 2>&1; echo $?)"
  r="$r $(SAT_STATE_DIR="$st" bash "$t" close 'byz-satnano-nano-s1#1' --forget --why x >/dev/null 2>&1; echo $?)"
  r="$r $(SAT_STATE_DIR="$st" bash "$t" task 'byz-satnano-nano-s1#1' "$T/s1t.md" >/dev/null 2>&1; echo $?)"
  r="$r $(SAT_STATE_DIR="$st" bash "$t" close 'byz-satnano-nano-s1#1' --adopt >/dev/null 2>&1; echo $?)"
  r="$r $(SAT_STATE_DIR="$st" bash "$t" fetch 'byz-satnano-nano-s1#1' >/dev/null 2>&1; echo $?)"
  S1D="$r"; [ "$r" = " 6 6 6 6 6" ] && [ "$(sshn)" = "$b" ] && [ "$(wc -l <"$SEND" | tr -d ' ')" = "$ns" ] && cmp -s "$st/before" "$st/opened.tsv"; }
cell_s1 "$TOOL" 1 && ok "ⓢ1(확정) 신원 3칸 참 + 소켓 빔 → close·--forget·task·--adopt·fetch rc6 · ssh 0 · 입력 0 · 줄 그대로" || bad "ⓢ1(확정) rc:${S1D:-}"

# ⓢ2(확정) SAT_TOTAL=3 · forgotten.tsv fsync 대역 4초 → --forget rc4 · 줄 유지 · 다시 --forget rc0
cell_s2() { local t="$1" s="$2" r okk=1; pending "$t" "s2$s" "byz-satnano-nano-s2#$s" || return 1
  call env SAT_TOTAL=3 SAT_TEST_FSYNC_SLEEP=4 PYTHONPATH="$T/fsyncinj" bash "$t" close "byz-satnano-nano-s2#$s" --forget --why "마감 시험"; r="$RC"; S2D="$r $O"
  [ "$r" = 4 ] && instate "byz-satnano-nano-s2#$s" && grep -q "forget 기록은 남았으나" <<<"$O" && okk=0
  call bash "$TOOL" close "byz-satnano-nano-s2#$s" --forget --why "다시"; { [ "$RC" = 0 ] && ! instate "byz-satnano-nano-s2#$s"; } || okk=1
  waitsess "byz-satnano-nano-s2#$s"; dropsess "byz-satnano-nano-s2#$s"; return $okk; }
cell_s2 "$TOOL" 1 && ok "ⓢ2(확정) SAT_TOTAL=3 · forgotten fsync 4초 → --forget rc4 · 줄 유지 → 다시 --forget rc0" || bad "ⓢ2(확정) ${S2D:-}"

# Ⓙ'(확정) DA 재현 입력 FAKE_TMUXC_ARM_PS=1 FAKE_TMUXC_SLEEP=5 → open rc4 · 5회 같은 결과
cell_Jp() { local t="$1" s="$2" i r=""
  for i in 1 2 3 4 5; do r="$r $(FAKE_TMUXC_ARM_PS=1 FAKE_TMUXC_SLEEP=5 bash "$t" open "$T/card.md" --run "jp$s$i" --name "byz-satnano-nano-jp#$s$i" >/dev/null 2>&1; echo $?)"; done
  JPD="$r"; for i in 1 2 3 4 5; do waitsess "byz-satnano-nano-jp#$s$i"
    bash "$TOOL" close "byz-satnano-nano-jp#$s$i" --adopt >/dev/null 2>&1 || { bash "$TOOL" close "byz-satnano-nano-jp#$s$i" --forget --why "시험 정리" >/dev/null 2>&1; dropsess "byz-satnano-nano-jp#$s$i"; }; done
  [ "$r" = " 4 4 4 4 4" ]; }
cell_Jp "$TOOL" 1 && ok "Ⓙ'(확정) ARM_PS=1 SLEEP=5 → open rc4 ×5 같은 결과" || bad "Ⓙ'(확정) rc:${JPD:-}"

# Ⓙ''(astra r1) ARM_PS=1 WAITPOLL=1 + 첫 R_POLL 5초 지연 → 표식 없음 = 세션 생성 0 · open rc4 ×5 같은 결과
cell_Jpp() { local t="$1" s="$2" i r="" okk=0
  for i in 1 2 3 4 5; do r="$r $(FAKE_TMUXC_ARM_PS=1 FAKE_TMUXC_WAITPOLL=1 FAKE_RPOLL_SLEEP=5 bash "$t" open "$T/card.md" --run "jq$s$i" --name "byz-satnano-nano-jq#$s$i" >/dev/null 2>&1; echo $?)"; done
  JQD="$r"; for i in 1 2 3 4 5; do hassess "byz-satnano-nano-jq#$s$i" && { okk=1; JQD="$JQD 세션있음:$i"; dropsess "byz-satnano-nano-jq#$s$i"; }
    bash "$TOOL" close "byz-satnano-nano-jq#$s$i" --forget --why "시험 정리" >/dev/null 2>&1; done
  [ "$r" = " 4 4 4 4 4" ] && [ "$okk" = 0 ]; }
cell_Jpp "$TOOL" 1 && ok "Ⓙ''(astra r1) WAITPOLL=1 + 첫 R_POLL 5초 지연 → 표식 없음 = 세션 0 · open rc4 ×5" || bad "Ⓙ''(astra r1) rc:${JQD:-}"

# ══ 변이 (전부 빨강이어야 통과) ══
mcheck "신원 대조 끔" cell_h "$(mut ident nano 'return a == b' 'return True')" 2
mcheck "값 검사 끔" cell_n "$(mut valid rt 'return re.fullmatch(RE[kind], v or "") is not None and (kind == "seats" or ".." not in v)' 'return True')"
mcheck "intent 끔" cell_A "$(mut intent nano 'rt.delivered_put(key, "intent", n)' 'pass')" 940
mcheck "재발신 상한 끔" cell_A "$(mut cap nano 'if last[2] >= cfg["resend_max"]:' 'if False:')" 950
mcheck "루프 뒤 검사 끔" cell_B "$(mut loopchk nano 'dl.check("pull 마지막 배달 뒤")' 'pass')" 1
mcheck "SEND claim 끔" cell_C "$(mut sendclaim nano 'if ! mkdir "$d/.sent/$tok" 2>/dev/null; then echo CLAIMED; exit 0; fi' 'mkdir -p "$d/.sent/$tok"')" 2
mcheck "CLAIMED→ALREADY" cell_C "$(mut claimed nano 'then echo CLAIMED; exit 0; fi' 'then echo ALREADY; exit 0; fi')" 3
mcheck "int(x,0)" cell_D "$(mut int0 rt 'v = int(raw, 10)' 'v = int(raw, 0)')"
mcheck "장부 예외 삼킴" cell_F "$(mut swallow rt 'raise Fail(2, f"기록 실패({path}: {e}) — 원격 호출 0")' 'pass')" 2
mcheck "QUEUED 부분 문자열" cell_H "$(mut queued nano 'queued = rc == 0 and re.match(rb"QUEUED seq=[0-9]+ ", so.split(b"\n", 1)[0]) is not None' 'queued = b"QUEUED" in so')" 960
mcheck "timeout 바닥 0.1" cell_I "$(mut floor rt 'if left <= 0:' 'if left < -1e9:' 'return min(self.tmo, left)' 'return max(0.1, min(self.tmo, left))')"
mcheck "gone 확인 생략" cell_K "$(mut gone nano 'ok = rc == 0 and KILL_OK in out.decode("utf-8", "replace")' 'ok = True')" 2
mcheck "rc1 = 없음" cell_K3 "$(mut rc1 nano "\"1:can't find session\"*|\"1:no server running\"*)" '1:*)')" 2
mcheck "rc1 = 없음(open 폴링)" cell_O "$(mut rc1b nano "\"1:can't find session\"*|\"1:no server running\"*)" '1:*)')" 2
mcheck "OPEN_BG claim 끔" cell_L0 "$(mut obclaim nano 'if ! mkdir "$d/.open.claim" 2>/dev/null; then' 'if false; then')" 2
mcheck "claimed→started" cell_L1 "$(mut claimedrun nano 'then echo claimed; exit 0; fi' 'then echo running; exit 0; fi')" 2
mcheck "claim_fail→started" cell_L2 "$(mut cfrun nano 'echo claim_fail; exit 4' 'echo running; exit 0')" 2
mcheck "claim_fail 줄 삭제 복귀" cell_L2 "$(mut cfdel nano 'raise Fail(4, unsure(name, d, "상태=claim_fail' 'rt.opened_del(run); raise Fail(4, unsure(name, d, "상태=claim_fail')" 3
mcheck "폴링 rowdel 복귀" cell_L4 "$(mut pollrow nano 'raise Fail(4, unsure(name, d, f"opener 끝났으나' 'rt.opened_del(run); raise Fail(4, unsure(name, d, f"opener 끝났으나')" 2
mcheck "\$msg 대입 삭제" cell_M "$(mut msgdel nano 'msg="[발주 #1] $f 를 읽고 그대로 수행해라. 결과는 같은 폴더 out.md."
' '')" 3
mcheck "불확실 줄 close 가 지움" cell_N "$(mut closedel nano 'raise Fail(4, f"{unsure(name, row[2],' 'rt.opened_del(row[1]); raise Fail(4, f"{unsure(name, row[2],')" 2
mcheck "--why 검사 끔" cell_P "$(mut why nano 'if not w or len(why) > 200 or any(c in why for c in "\t\r\n"):' 'if False:')" 2
mcheck "--forget 확인된 줄도 지움" cell_P "$(mut forgetconf nano '    if rt.confirmed(row):
        raise Fail(2, "확인된 세션은' '    if False:
        raise Fail(2, "확인된 세션은')" 3
mcheck "--adopt dirmatch 없이" cell_Q "$(mut adopt nano ' and k.get("dirmatch") == "1"):' '):')" 2
# r5 변이 6
mcheck "잠금 구간 = 추가만(r5 ⓡ1)" cell_r1 "$(mut lockadd nano '        reserve(dl, name, run, d)
        return open_body(' '        reserve(dl, name, run, d)
    return open_body(')" 2
mcheck "삭제 열쇠 = 이름(r5 ⓡ1 · 이름 검사 끔과 짝)" cell_r1 "$(mut namekey nano 'r[0] == name or rt.same_run(r, run)' 'rt.same_run(r, run)' 'rt.opened_del(run)  # R2' '[rt.opened_del(r[1]) for r in rt.read_rows("opened.tsv") if r[0] == name]  # R2')" 3
mcheck "R_WRITE 뒤 자동 삭제(r5 ⓡ2)" cell_r2 "$(mut wdel nano '        free, warn = pre(dl, name, run, d)
' '        free, warn = pre(dl, name, run, d)
        write_task(dl, name, d, data)
' '    write_task(dl, name, d, data)  # R2' '    pass  # R2')" 2
mcheck "칸 수 검사 끔(r5 ⓡ3)" cell_r3 "$(mut ncol rt 'if len(hit) != 1 or len(hit[0]) != NCOL or' 'if len(hit) != 1 or')" 2
mcheck "-S 빼기(r5 ⓡ4)" cell_r4 "$(mut nosock nano 'tmux -S "$SOCK" "$@"' 'tmux "$@"')" 2
mcheck "confirmed = 신원 3칸만(확정 ⓢ1)" cell_s1 "$(mut conf3 rt 'all(row[4:NCOL])' 'all(row[4:7])')" 2
mcheck "삭제 전 dl.check 끔(--forget · 확정 ⓢ2)" cell_s2 "$(mut fgchk nano '    rt.in_time(dl, "삭제 전(forget 기록 뒤)", "forget 기록은 남았으나 마감 초과 — 줄 유지 · 다시 --forget")' '    pass')" 2
mcheck "삭제 전 dl.check 끔(r5 ⓡ5)" cell_r5 "$(mut delchk nano '    rt.in_time(dl, "삭제 전", "닫힘 확인했으나 마감 초과 — 기록 유지 · 다시 close 하면 gone 경로로 지운다")' '    pass')" 2

# ══ 정적 ══
python3 -m py_compile "$BIN/ft_sat_nano.py" "$BIN/ft_sat_rt.py" && ok "정적 py_compile" || bad "정적 py_compile"
if command -v ruff >/dev/null 2>&1; then ruff check -q "$BIN/ft_sat_nano.py" "$BIN/ft_sat_rt.py" && ok "정적 ruff" || bad "정적 ruff"; else bad "정적 ruff 없음"; fi
if command -v shellcheck >/dev/null 2>&1; then shellcheck -S warning "$TOOL" "${BASH_SOURCE[0]}" && ok "정적 shellcheck(입구+시험)" || bad "정적 shellcheck"; else bad "정적 shellcheck 없음"; fi
for f in ft-sat-nano.sh ft_sat_nano.py ft_sat_rt.py; do cmp -s "$BIN/$f" "$KIT/$f" && ok "정적 kit cmp0 $f" || bad "정적 kit 사본 불일치 $f"; done
grep -nE 'settled|OPEN_LIMIT|date \+%s' "$BIN/ft-sat-nano.sh" "$BIN/ft_sat_nano.py" "$BIN/ft_sat_rt.py" >/dev/null && bad "정적 settled|OPEN_LIMIT|date +%s 남음" || ok "정적 grep settled|OPEN_LIMIT|date +%s 0건"
grep -nE 'kill -9|pkill|kill-server' "$BIN/ft_sat_nano.py" "$BIN/ft_sat_rt.py" >/dev/null && bad "정적 강제 kill 문구" || ok "정적 강제 kill 문구 0"
bash "$TOOL" bogus >/dev/null 2>&1; [ $? = 2 ] && ok "정적 usage rc2" || bad "정적 usage rc"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED"
exit $fail
