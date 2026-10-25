#!/usr/bin/env bash
# ft-sat-nano.sh — 위성(mini) 나노 도구 하나 (r902 · arch 140 발주 2026-10-25 · 반송 r2 = DA⑥ r1 HOLD 5묶음 반영)
#   골 축: 하네스 골 C «메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용» — 이 맥 대신 mini 에 작업 좌석을 열고 쓰고 닫는다.
#   원형 흡수: docs/multihost/satellite/sat-mbox.py(push/pull/dedupe/ack) + h-mini-satellite-nano-test.sh(열기·작업·회수·닫기) — ba9de431
#   명령: open <카드파일> [--run R] [--name N] · task <세션> <파일> · pull --seats A,B [--every N] · fetch <세션> · close <세션>
#   ★값 검사: --run·세션 이름·좌석·SAT_ROOT_REMOTE·SAT_MODEL·SAT_MINI_MBOX_PY 는 정규식 통과값만 쓴다(아니면 rc2 · 원격 호출 0).
#     원격 명령은 이 파일에 박힌 «고정 스크립트» + printf %q 로 한 번 더 인용한 인자뿐 — 사용자 값이 원격 셸 문자열이 되는 길 0.★
#   ★닫기 = 신원 대조: open 때 #{session_id} #{session_created} #{pane_current_path} 를 opened.tsv 에 기록 · close 는 같은 셋일 때만 정리.
#     다르면 rc3(건드림 0) · tmux·pgrep·lsof 조회가 실패하면 «닫힘» 이 아니라 rc6(기록 유지) · pi 검사는 작업 폴더 «경계 일치».★
#   ★쪽지 가져오기: pull 은 로컬 잠금(ln -s · 죽은 pid 회수 · 5초 상한) 안에서 읽기→배달→기록→ack · 본문은 base64 로 바이트 보존(끝 개행 포함) ·
#     SAT_MAX_BODY(256KB) 넘는 쪽지는 받지 않고 ERROR 1줄 + mini «quarantine/» 폴더로 이동(삭제 0 · 영구 pending 0).★
#   ★작업 전달 완료 = send-keys 가 둘 다 rc0 일 때만 «<파일>.sent» 표식(파일 존재 ≠ 전달) · 표식이 없으면 재시도가 다시 보낸다.★
#   ★원격 쓰기 = mini 의 ~/Project/satellite-nano/<run>/ 와 mini 쪽지함(+quarantine/)뿐. BYZ 소스·서버·Redis·settings·authorized_keys 접촉 0.★
#   ★7초/70초: 원격 호출 한 번 = 연결 6초 + 명령 SAT_TMO(7초) · 첫 출력 전 연결 실패(ssh rc255)만 1회 재시도 · 명령 하나의 총 마감 SAT_TOTAL(70초 · open 포함).
#     open 은 «원격 백그라운드 시작 → 짧은 확인 폴링» 으로 쪼갠다(45초 예외 없음). pull --every 는 회차마다 마감을 새로 센다.★
#   env: MINI(mini) · SAT_TMO(7) · SAT_TOTAL(70) · SAT_ROOT_REMOTE(Project/satellite-nano) · SAT_MODEL
#        SAT_STATE_DIR(~/.fable-team/sat) · SAT_MINI_MBOX_PY · SAT_MBOX_SH · SAT_OUT_DIR(harness/evidence/r902)
#        SAT_NOWAIT(1=pi 기동 대기 생략·시험용) · SAT_SEAT(pull 기본 수신자) · SAT_PULL_MAX(30) · SAT_MAX_BODY(262144) · SAT_PULL_ROWS(20)
#   rc: 0 ok · 2 usage/전제실패/값 검사 · 3 세션 열기 실패·신원 불일치 · 4 전달 실패 · 5 원격 실패·시간 초과 · 6 닫기 확인 실패
set -uo pipefail
MINI="${MINI:-mini}"; TMO="${SAT_TMO:-7}"; TOTAL="${SAT_TOTAL:-70}"
RROOT="${SAT_ROOT_REMOTE:-Project/satellite-nano}"
MODEL="${SAT_MODEL:-opengateway/deepseek/deepseek-v4.1-flash-ultrafast}"
STATE="${SAT_STATE_DIR:-$HOME/.fable-team/sat}"
OPENED="$STATE/opened.tsv"    # name<TAB>run<TAB>dir<TAB>ts<TAB>session_id<TAB>created<TAB>pane_path
DELIVERED="$STATE/delivered"  # mini:<seq> 한 줄씩(같은 쪽지 2번 배달 0)
LOCK="$STATE/pull.lock"
HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTD="${SAT_OUT_DIR:-$HARNESS/evidence/r902}"
MPY="${SAT_MINI_MBOX_PY:-\$HOME/.claude/skills/fable-team/scripts/ft-mbox.py}"
MAXB="${SAT_MAX_BODY:-262144}"; ROWS="${SAT_PULL_ROWS:-20}"
SO=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=10 -o ServerAliveCountMax=3)
T0=$SECONDS; HELD=0
TMPD="$(mktemp -d)" || { echo "[sat] REJECT rc=2 임시 폴더 생성 실패" >&2; exit 2; }
ROUTF="$TMPD/rout"; RERRF="$TMPD/rerr"; ROUT=""; RERR=""
trap 'if [ "$HELD" = 1 ]; then rm -f "$LOCK"; fi; rm -rf "$TMPD"' EXIT
say() { printf '[sat] %s\n' "$*"; }
die() { printf '[sat] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }

# ── 값 검사 (한 줄 함수 — 시험의 변이가 이 줄을 바꾼다) ─────
RE_NAME='^[A-Za-z0-9][A-Za-z0-9._#-]{0,63}$'; RE_RUN='^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'
RE_ROOT='^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$'; RE_MODEL='^[A-Za-z0-9][A-Za-z0-9._/:@-]{0,127}$'
RE_SEATS='^[A-Za-z0-9._#-]+(,[A-Za-z0-9._#-]+)*$'; RE_MPY='^[A-Za-z0-9_$/{}.-]+$'
valid_name() { [[ "$1" =~ $RE_NAME && "$1" != *..* ]]; }
valid_run() { [[ "$1" =~ $RE_RUN && "$1" != *..* ]]; }
valid_root() { [[ "$1" =~ $RE_ROOT && "$1" != *..* ]]; }
valid_model() { [[ "$1" =~ $RE_MODEL && "$1" != *..* ]]; }
valid_seats() { [[ "$1" =~ $RE_SEATS ]]; }
valid_mpy() { [[ "$1" =~ $RE_MPY && "$1" != *..* ]]; }
ident_same() { [ "$1" = "$2" ]; }      # close 신원 대조 — 현재 «id created path» == open 때 기록
absent_rc() { [ "$1" = 1 ]; }          # tmux has-session rc1 = 세션 없음 · 그 밖의 rc = 조회 실패
pull_lock() { lock_acquire; }

# ── 원격 고정 스크립트 (사용자 값은 위치 인자로만 들어간다) ──
IFS= read -r -d '' R_PRE <<'EOF' || true
n="$1"; d="$HOME/$2"
for t in tmuxc pi; do if command -v "$t" >/dev/null 2>&1; then echo "$t=ok"; else echo "$t=MISSING"; fi; done
tmux has-session -t "=$n" 2>/dev/null; echo "sess_rc=$?"
if [ -e "$d" ]; then echo dir=EXISTS; else echo dir=absent; fi
EOF
IFS= read -r -d '' R_WRITE <<'EOF' || true
d="$HOME/$1"; mkdir -p "$d" && cat >"$d/TASK.md"
EOF
IFS= read -r -d '' R_OPEN_BG <<'EOF' || true
d="$HOME/$1"; cd "$d" || exit 3
nohup tmuxc open "$d" --name "$2" --agent pi --role worker --model "$3" --effort medium >"$d/.open.log" 2>&1 </dev/null &
echo $! >"$d/.open.pid"
echo started
EOF
IFS= read -r -d '' R_POLL <<'EOF' || true
d="$HOME/$2"; pid="$(cat "$d/.open.pid" 2>/dev/null)"
if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then echo alive=1; else echo alive=0; fi
tmux has-session -t "=$1" 2>/dev/null; echo "sess_rc=$?"
tail -3 "$d/.open.log" 2>/dev/null | sed 's/^/log: /'
EOF
IFS= read -r -d '' R_IDENT <<'EOF' || true
tmux display -p -t "=$1:" '#{session_id} #{session_created} #{pane_current_path}'
EOF
IFS= read -r -d '' R_PIDS <<'EOF' || true
pp="$(tmux display -p -t "=$1:" '#{pane_pid}' 2>/dev/null)"
if [ -n "$pp" ]; then pgrep -P "$pp" 2>/dev/null | wc -l | tr -d ' '; else echo 0; fi
EOF
IFS= read -r -d '' R_SEND <<'EOF' || true
d="$HOME/$1"; f="$d/$2"; m="$f.sent"
if [ "$4" = write ]; then
  if [ -f "$m" ]; then echo ALREADY; exit 0; fi
  cat >"$f" || exit 4
fi
msg="[발주 #1] $f 를 읽고 그대로 수행해라. 결과는 같은 폴더 out.md."
tmux send-keys -t "=$3:" -l "$msg" || exit 1
sleep 1
tmux send-keys -t "=$3:" Enter || exit 1
: >"$m" || exit 1
echo SENDOK
EOF
IFS= read -r -d '' R_CAT <<'EOF' || true
cat "$HOME/$1/$2"
EOF
IFS= read -r -d '' R_LOOKUP <<'EOF' || true
tmux has-session -t "=$1" 2>/dev/null; h=$?; echo "has=$h"
if [ "$h" = 0 ]; then
  i="$(tmux display -p -t "=$1:" '#{session_id} #{session_created} #{pane_current_path}' 2>/dev/null)"; echo "drc=$?"
  echo "ident=$i"
fi
EOF
IFS= read -r -d '' R_KILL <<'EOF' || true
if [ -n "$1" ]; then tmux kill-session -t "$1" >/dev/null 2>&1; fi
n=0; h=0
while [ "$n" -lt 6 ]; do
  tmux has-session -t "=$2" 2>/dev/null; h=$?
  [ "$h" != 0 ] && break
  sleep 0.5; n=$((n + 1))
done
case "$h" in 0) s=alive;; 1) s=gone;; *) s=unknown;; esac
d="$HOME/$3"; left=0; err=0
pids="$(pgrep -x pi 2>/dev/null)"; prc=$?
if [ "$prc" -ge 2 ]; then err=1; fi
for p in $pids; do
  o="$(lsof -a -p "$p" -d cwd -Fn 2>/dev/null)"; lrc=$?
  if [ "$lrc" != 0 ]; then
    if kill -0 "$p" 2>/dev/null; then err=1; fi
    continue
  fi
  c="$(printf '%s\n' "$o" | sed -n 's/^n//p')"
  case "$c" in "$d"|"$d"/*) left=$((left + 1));; esac
done
echo "session=$s pi_left=$left err=$err"
EOF
R_PY='python3 -c "$1" "${@:2}"'
IFS= read -r -d '' PY_HEAD <<'EOF' || true
import base64,importlib.util,json,os,sys
s=importlib.util.spec_from_file_location('m',os.path.expandvars(sys.argv[1]))
m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
EOF
IFS= read -r -d '' PY_READ_BODY <<'EOF' || true
seats=set(sys.argv[2].split(','));mx=int(sys.argv[3]);mr=int(sys.argv[4])
rows=m._locked(m.CANON,lambda:[r for r in m._load(m.CANON) if r.get('to') in seats])[:mr]
out=[]
for r in rows:
    b=str(r.get('body','')).encode('utf-8')
    e={'seq':r.get('seq'),'to':r.get('to',''),'from':r.get('from','')}
    if len(b)>mx: e['oversize']=len(b)
    else: e['b64']=base64.b64encode(b).decode()
    out.append(e)
print(json.dumps(out))
EOF
IFS= read -r -d '' PY_ACK_BODY <<'EOF' || true
mode=sys.argv[2];seqs=set(json.loads(sys.argv[3]))
def op():
    rows=m._load(m.CANON);hit=[r for r in rows if r.get('seq') in seqs]
    if mode=='quarantine' and hit:
        qd=os.path.join(m.CANON,'quarantine');os.makedirs(qd,exist_ok=True)
        for r in hit:
            with open(os.path.join(qd,'seq-%s.json'%r.get('seq')),'w',encoding='utf-8') as f: json.dump(r,f,ensure_ascii=False)
    keep=[r for r in rows if r.get('seq') not in seqs]
    if len(keep)!=len(rows): m._save(m.CANON,keep)
    print(len(rows)-len(keep))
m._locked(m.CANON,op)
EOF
PY_READ="$PY_HEAD$PY_READ_BODY"; PY_ACK="$PY_HEAD$PY_ACK_BODY"
PLAN_PY='import base64,json,os,sys
for r in json.load(open(sys.argv[1])):
    seq=str(int(r.get("seq")))
    if "oversize" in r: kind="oversize:%s"%r["oversize"]
    else:
        open(os.path.join(sys.argv[2],seq+".body"),"wb").write(base64.b64decode(r["b64"])); kind="ok"
    print("\t".join([seq,str(r.get("to","")),str(r.get("from","")),kind]))'

# ── 원격 호출 — 한 번 TMO · 연결 실패(rc255)만 1회 재시도 · 총 TOTAL 마감 ──
rsc() { # rsc <원격 스크립트> [값...] — 값은 전부 printf %q · stdin = $RIN(없으면 /dev/null) · 결과 ROUT·RERR(+파일 ROUTF)
  local script="$1"; shift
  local cmd a rc left t
  cmd="export PATH=/opt/homebrew/bin:\$HOME/.local/bin:\$PATH; bash -c $(printf %q "$script") _"
  for a in "$@"; do cmd="$cmd $(printf %q "$a")"; done
  for _ in 1 2; do
    left=$((TOTAL - (SECONDS - T0)))
    if [ "$left" -le 0 ]; then ROUT=""; RERR="총 마감 ${TOTAL}초 초과"; return 124; fi
    t="$TMO"; [ "$left" -lt "$t" ] && t="$left"
    timeout "$t" ssh "${SO[@]}" "$MINI" "$cmd" <"${RIN:-/dev/null}" >"$ROUTF" 2>"$RERRF"; rc=$?
    ROUT="$(cat "$ROUTF")"; RERR="$(cat "$RERRF")"
    [ "$rc" = 255 ] || return "$rc"
  done
  return "$rc"
}
tail2() { printf '%s' "$1" | tail -2; }
kv() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }  # kv <본문> <키>
_opened() { cut -f1 "$OPENED" 2>/dev/null | grep -qxF -- "$1"; }
_seen() { grep -qxF -- "$1" "$DELIVERED" 2>/dev/null; }
field() { awk -F'\t' -v n="$1" -v c="$2" '$1==n{print $c}' "$OPENED" 2>/dev/null; }
rowdel() { awk -F'\t' -v n="$1" '$1!=n' "$OPENED" >"$OPENED.tmp" && mv "$OPENED.tmp" "$OPENED"; }
rowset() { awk -F'\t' -v OFS='\t' -v n="$1" -v a="$2" -v b="$3" -v c="$4" '$1==n{$5=a;$6=b;$7=c}{print}' "$OPENED" >"$OPENED.tmp" && mv "$OPENED.tmp" "$OPENED"; }
mbox_sh() {
  [ -n "${SAT_MBOX_SH:-}" ] && { printf '%s' "$SAT_MBOX_SH"; return 0; }
  local c
  for c in "$HOME/.claude/skills/fable-team/scripts/ft-mbox.sh" "$HARNESS/kit/fable-team/bin/ft-mbox.sh" "$HARNESS/bin/ft-mbox.sh"; do
    [ -f "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}
lock_acquire() { # 로컬 잠금 = 심볼릭 링크(생성이 원자적 · 대상 = 쥔 pid) · 죽은 pid 는 회수 · 5초 상한
  local n=0 p q
  while ! ln -s "$$" "$LOCK" 2>/dev/null; do
    p="$(readlink "$LOCK" 2>/dev/null)"
    if [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null; then
      q="$(readlink "$LOCK" 2>/dev/null)"; [ "$q" = "$p" ] && rm -f "$LOCK"
      continue
    fi
    n=$((n + 1)); [ "$n" -le 50 ] || return 1
    sleep 0.1
  done
  HELD=1
}
lock_release() { if [ "$HELD" = 1 ]; then rm -f "$LOCK"; HELD=0; fi; }

cmd_open() {
  local card="${1:-}"; [ $# -gt 0 ] && shift; local run="" name="byz-sat-nano-pi#0"
  while [ $# -gt 0 ]; do case "$1" in --run) run="${2:?}"; shift 2;; --name) name="${2:?}"; shift 2;; *) die 2 "usage open <카드파일> [--run R] [--name N]";; esac; done
  [ -n "$card" ] && [ -f "$card" ] || die 2 "카드 파일이 없다: ${card:-<없음>}"
  [ -n "$run" ] || run="$(printf '%s' "$(basename "$card")" | sed 's/\.[^.]*$//' | tr -c 'A-Za-z0-9._-' '-' | sed 's/^[^A-Za-z0-9]*//' | cut -c1-40)"
  valid_run "$run" || die 2 "작업 이름(--run)이 규칙 밖이다(영숫자로 시작 · 영숫자 . _ - · 64자 이하 · .. 없음): $run"
  valid_name "$name" || die 2 "세션 이름(--name)이 규칙 밖이다: $name"
  valid_root "$RROOT" || die 2 "SAT_ROOT_REMOTE 가 규칙 밖이다: $RROOT"
  valid_model "$MODEL" || die 2 "SAT_MODEL 이 규칙 밖이다: $MODEL"
  mkdir -p "$STATE" || die 2 "상태 폴더 생성 실패: $STATE"
  _opened "$name" && die 2 "이 도구의 기록에 같은 이름이 남아 있다 — close $name 먼저: $name"
  local dir="$RROOT/$run" sr
  rsc "$R_PRE" "$name" "$dir" || die 5 "mini 접속 실패: $(tail2 "${RERR:-$ROUT}")"
  printf '%s\n' "$ROUT" | sed 's/^/[sat]   /'
  case "$ROUT" in *MISSING*) die 2 "mini 에 필요한 도구가 없다(위 MISSING)";; esac
  sr="$(kv "$ROUT" sess_rc)"
  if [ "$sr" = 0 ]; then die 2 "같은 이름 세션이 이미 있다 — 남의 세션이라 건드리지 않는다: $name"
  elif ! absent_rc "$sr"; then die 5 "mini 세션 조회 실패(sess_rc=${sr:-?}) — 열지 않는다"; fi
  case "$ROUT" in *dir=EXISTS*) die 2 "작업 폴더가 이미 있다 — --run <다른이름> 으로 다시: $dir";; esac
  RIN="$card" rsc "$R_WRITE" "$dir" || die 4 "TASK.md 쓰기 실패: $(tail2 "${RERR:-$ROUT}")"
  say "1/4 작업 폴더·TASK.md — $dir/TASK.md"
  printf '%s\t%s\t%s\t%s\t\t\t\n' "$name" "$run" "$dir" "$(date -u +%FT%TZ)" >>"$OPENED"   # 신원은 세션이 보인 뒤 채운다
  rsc "$R_OPEN_BG" "$dir" "$name" "$MODEL" || { rowdel "$name"; die 3 "원격 세션 열기 시작 실패: $(tail2 "${RERR:-$ROUT}")"; }
  local al
  while :; do
    rsc "$R_POLL" "$name" "$dir" || die 5 "세션 확인 실패(기록은 남김 — close $name 으로 정리): $(tail2 "${RERR:-$ROUT}")"
    sr="$(kv "$ROUT" sess_rc)"; al="$(kv "$ROUT" alive)"
    [ "$sr" = 0 ] && break
    if [ "$al" = 0 ]; then rowdel "$name"; die 3 "tmuxc open 이 세션 없이 끝났다: $(printf '%s' "$ROUT" | grep '^log:' | tail -3 | tr '\n' ' ')"; fi
    [ $((TOTAL - (SECONDS - T0))) -ge 10 ] || die 5 "총 마감 ${TOTAL}초 안에 세션이 안 보인다(기록은 남김 — close $name 으로 정리)"
    sleep 2
  done
  rsc "$R_IDENT" "$name" || die 3 "세션 신원 조회 실패(세션은 열려 있다 — close 불가 상태 · 수동 확인): $(tail2 "${RERR:-$ROUT}")"
  local sid cr pth; read -r sid cr pth <<<"$ROUT"
  [ -n "$sid" ] && [ -n "$cr" ] && [ -n "$pth" ] || die 3 "세션 신원 해석 실패(세션은 열려 있다 — 수동 확인): $ROUT"
  rowset "$name" "$sid" "$cr" "$pth" || die 2 "신원 기록 실패: $OPENED"
  printf '%s\n' "OPEN ok name=$name id=$sid" | sed 's/^/[sat]   /'
  say "2/4 세션 열기 — $name (이 도구가 연 세션으로 기록 · 신원 $sid $cr)"
  if [ "${SAT_NOWAIT:-0}" != "1" ]; then
    local i n=0
    for i in 1 2 3 4 5 6; do
      rsc "$R_PIDS" "$name" && n="$ROUT" || n=0
      [ "${n:-0}" -ge 1 ] 2>/dev/null && break
      [ $((TOTAL - (SECONDS - T0))) -ge 10 ] || break
      sleep 5
    done
    [ "${n:-0}" -ge 1 ] 2>/dev/null || die 3 "pi 프로세스가 안 떴다(HARD GATE: 자식 0건 — 입력 전송 금지 · close $name 으로 정리)"
    say "3/4 pi 기동 확인"
  fi
  rsc "$R_SEND" "$dir" TASK.md "$name" keep || die 4 "지시 전달 실패(표식 0): $(tail2 "${RERR:-$ROUT}")"
  say "4/4 지시 전달 — TASK.md · 회수 fetch $name · 닫기 close $name"
}

cmd_task() {
  local name="${1:-}" file="${2:-}"
  [ -n "$name" ] && [ -f "${file:-}" ] || die 2 "usage task <세션> <파일>"
  valid_name "$name" || die 2 "세션 이름이 규칙 밖이다: $name"
  _opened "$name" || die 5 "이 도구가 연 세션이 아니다 — 남의 세션에는 쓰지 않는다: $name"
  local dir sum target rc; dir="$(field "$name" 3)"; [ -n "$dir" ] || die 2 "상태 기록이 깨졌다: $name"
  sum="$(shasum -a 256 "$file" | cut -c1-8)"; target="TASK-$sum.md"
  RIN="$file" rsc "$R_SEND" "$dir" "$target" "$name" write; rc=$?
  case "$ROUT" in *ALREADY*) say "SKIP 같은 작업이 이미 전달됐다(중복 0) — $dir/$target"; exit 0;; esac
  [ "$rc" = 0 ] || die 4 "작업 전달 실패(rc=$rc · 표식 0 — 같은 명령을 다시 하면 재전송): $(tail2 "${RERR:-$ROUT}")"
  say "TASK ok run=$(field "$name" 2) file=$dir/$target"
}

pull_once() { # $1=좌석들 $2=회차 $3=every
  pull_lock || die 5 "pull 잠금을 5초 안에 못 잡았다(다른 pull 진행 중): $LOCK"
  local seats="$1" PDIR="$TMPD/pull" seq to frm kind key body out ok="" qs="" nplan nok ackjson
  rm -rf "$PDIR"; mkdir -p "$PDIR"
  rsc "$R_PY" "$PY_READ" "$MPY" "$seats" "$MAXB" "$ROWS" || die 5 "mini 쪽지함 읽기 실패: $(tail2 "${RERR:-$ROUT}")"
  python3 -c "$PLAN_PY" "$ROUTF" "$PDIR" >"$TMPD/plan" 2>/dev/null || die 5 "mini 쪽지함 응답 해석 실패"
  while IFS=$'\t' read -r seq to frm kind; do
    [ -n "${seq:-}" ] || continue
    key="mini:$seq"
    case "$kind" in
      oversize:*) say "ERROR oversize seq=$seq bytes=${kind#oversize:} > ${MAXB} — 받지 않음 · mini quarantine/ 으로 이동(삭제 0)"; qs="$qs $seq"; continue;;
    esac
    _seen "$key" && { ok="$ok $seq"; continue; }
    body="$(cat "$PDIR/$seq.body"; printf x)"; body="${body%x}"   # 끝 개행 보존
    out="$(bash "$mb" send "$to" "$frm" "$body" 2>&1 </dev/null)"
    case "$out" in
      *QUEUED*)
        if printf '%s\n' "$key" >>"$DELIVERED" 2>/dev/null; then ok="$ok $seq"
        else say "RECORD_FAIL seq=$seq (배달 기록 실패 — ack 안 함 · 다음 pull 재시도)"; fi ;;
      *) say "DELIVER_FAIL seq=$seq (ack 안 함 — 다음 pull 에서 재시도)" ;;
    esac
  done <"$TMPD/plan"
  ackjson="[$(printf '%s' "$ok" | tr ' ' '\n' | grep -v '^$' | paste -sd, -)]"
  if [ "$ackjson" != "[]" ]; then
    rsc "$R_PY" "$PY_ACK" "$MPY" ack "$ackjson" >/dev/null || say "ACK_FAIL (다음 pull 에서 중복 없이 재시도)"
  fi
  if [ -n "$qs" ]; then
    rsc "$R_PY" "$PY_ACK" "$MPY" quarantine "[$(printf '%s' "$qs" | tr ' ' '\n' | grep -v '^$' | paste -sd, -)]" >/dev/null \
      || say "QUARANTINE_FAIL (큰 쪽지가 mini 큐에 남았다 — 다음 pull 에서 재시도)"
  fi
  nplan="$(grep -c . "$TMPD/plan")"; nok="$(printf '%s' "$ok" | wc -w | tr -d ' ')"
  lock_release
  say "PULL ok seen=$nplan delivered=$nok every=$3 turn=$2"
}

cmd_pull() {
  local seats="${SAT_SEAT:-}" every=0
  while [ $# -gt 0 ]; do case "$1" in --seats) seats="${2:?}"; shift 2;; --every) every="${2:?}"; shift 2;; *) die 2 "usage pull --seats A,B [--every N]";; esac; done
  [ -n "$seats" ] || die 2 "수신 좌석이 없다 — pull --seats A,B (또는 SAT_SEAT)"
  valid_seats "$seats" || die 2 "수신 좌석 값이 규칙 밖이다: $seats"
  valid_mpy "$MPY" || die 2 "SAT_MINI_MBOX_PY 가 규칙 밖이다: $MPY"
  [[ "$every" =~ ^[0-9]{1,5}$ ]] || die 2 "--every 는 숫자(초)여야 한다: $every"
  mb="$(mbox_sh)" || die 2 "이 맥 ft-mbox.sh 를 못 찾았다(SAT_MBOX_SH 로 지정)"
  mkdir -p "$STATE" || die 2 "상태 폴더 생성 실패: $STATE"
  local i=0 max="${SAT_PULL_MAX:-30}"
  while :; do
    i=$((i + 1)); T0=$SECONDS
    pull_once "$seats" "$i" "$every"
    [ "$every" -gt 0 ] || break
    [ "$i" -lt "$max" ] || break
    sleep "$every"
  done
}

cmd_fetch() {
  local name="${1:-}"; [ -n "$name" ] || die 2 "usage fetch <세션>"
  valid_name "$name" || die 2 "세션 이름이 규칙 밖이다: $name"
  _opened "$name" || die 5 "이 도구가 연 세션이 아니다: $name"
  local run dir f dest n=0 rc; run="$(field "$name" 2)"; dir="$(field "$name" 3)"
  [ -n "$run" ] && [ -n "$dir" ] || die 2 "상태 기록이 깨졌다: $name"
  mkdir -p "$OUTD/$run" || die 2 "회수 폴더 생성 실패: $OUTD/$run"
  for f in out.md TASK.md; do
    dest="$OUTD/$run/$f"
    rsc "$R_CAT" "$dir" "$f"; rc=$?
    case "$rc" in 124|255) die 5 "원격 실패·시간 초과(rc=$rc): $(tail2 "$RERR")";; esac
    if [ "$rc" = 0 ] && [ -s "$ROUTF" ] && cp "$ROUTF" "$dest"; then
      n=$((n + 1)); say "FETCH $dest"
    else
      rm -f "$dest"
    fi
  done
  [ "$n" -gt 0 ] || die 5 "회수할 결과가 없다(아직 안 썼거나 경로가 다르다): $dir"
  say "FETCH ok run=$run files=$n"
}

cmd_close() {
  local name="${1:-}"; [ -n "$name" ] || die 2 "usage close <세션>"
  valid_name "$name" || die 2 "세션 이름이 규칙 밖이다: $name"
  _opened "$name" || die 5 "이 도구가 연 세션이 아니다 — 남의 세션은 닫지 않는다: $name"
  local dir sid cr pth has want got kid; dir="$(field "$name" 3)"; [ -n "$dir" ] || die 2 "상태 기록이 깨졌다: $name"
  sid="$(field "$name" 5)"; cr="$(field "$name" 6)"; pth="$(field "$name" 7)"
  rsc "$R_LOOKUP" "$name" || die 6 "세션 조회 실패 — 닫힘으로 보지 않는다(기록 유지): $(tail2 "${RERR:-$ROUT}")"
  has="$(kv "$ROUT" has)"; kid=""
  if [ "$has" = 0 ]; then
    [ "$(kv "$ROUT" drc)" = 0 ] || die 6 "세션 신원 조회 실패 — 건드리지 않는다(기록 유지)"
    [ -n "$sid" ] && [ -n "$cr" ] && [ -n "$pth" ] || die 3 "신원 기록이 없다 — 이 도구가 연 세션인지 확인할 수 없다 · 건드림 0: $name"
    want="$sid $cr $pth"; got="$(kv "$ROUT" ident)"
    ident_same "$got" "$want" || die 3 "다른 세션이다 — 같은 이름이지만 신원이 다르다(기록 $want / 지금 $got) · 건드림 0: $name"
    kid="$sid"
  elif ! absent_rc "$has"; then
    die 6 "세션 조회 결과를 알 수 없다(has=${has:-?}) — 닫힘으로 보지 않는다(기록 유지): $name"
  fi
  rsc "$R_KILL" "$kid" "$name" "$dir" || die 6 "닫기 명령 실패(기록 유지): $(tail2 "${RERR:-$ROUT}")"
  printf '%s\n' "$ROUT" | sed 's/^/[sat]   /'
  grep -q "session=gone pi_left=0 err=0" <<<"$ROUT" || die 6 "닫기 확인 실패 — 세션/프로세스가 남았거나 확인이 안 됐다(강제 kill 은 하지 않는다 · 기록 유지): $name"
  rowdel "$name"
  say "CLOSE ok $name — 세션 없음 · 이 폴더에서 도는 pi 0"
}

case "${1:-}" in
  open)  shift; cmd_open "$@" ;;
  task)  shift; cmd_task "$@" ;;
  pull)  shift; cmd_pull "$@" ;;
  fetch) shift; cmd_fetch "$@" ;;
  close) shift; cmd_close "$@" ;;
  *) echo "usage: ft-sat-nano.sh {open <카드파일> [--run R] [--name N]|task <세션> <파일>|pull --seats A,B [--every N]|fetch <세션>|close <세션>}" >&2; exit 2 ;;
esac
