#!/usr/bin/env python3
"""ft-sat-nano 본체 — 위성(mini) 나노 도구 하나 (r902 r7 · DECISION-r902-design-final 고침 3 · 반송 r5 R1~R3).

골 축: 하네스 골 C «메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용» — 이 맥 대신 mini 에 작업 좌석을 열고 쓰고 닫는다.
명령: open <카드> [--run R] [--name N] · task <세션> <파일> [--retry] · pull --seats A,B [--every N] · fetch <세션>
      close <세션> [--adopt | --forget --why '<1~200자>'] · roster(명부 표 1장 · 읽기)
열 때의 문(r949 · ft_sat_gate): 상한 SAT_MAX 3 · mini free% 경고 SAT_FREE_MIN 25(값은 ssh rc0 ∧ 측정 rc0 ∧ 숫자 셋 다일 때만 · 아니면 「측정 불가」 1줄 · 어느 갈래도 열고 진행) · 이름 = ft-name-lint(기본 byz-satnano-nano-<slug>#0)
      입력 비밀 꼴 = rc2 · 명부 roster.json(OPENING→OPEN→CLOSED · 표식 by=ft-sat-nano) · 원장 ledger.tsv(종류 = open·close·reject 셋뿐 · 경고는 open 줄의 칸)
보장: 쪽지 = 최소 한 번(꼬리표 · 재발신 상한 · dead 격리) · 지시 입력·원격 열기 = 최대 한 번(결과 모름 = rc4 · 자동 해소 0)
      close = 신원이 확인된 줄만 닫는다 · 열기 불확실 줄은 도구가 지우지 않는다(--forget = 사람·master 명시 · 원격 0)
장부(r5): R1 열쇠 = run(기본 이름 byz-sat-nano-<run>#0) · open·close·--adopt·--forget 은 장부 잠금을 명령 내내 쥔다
      R2 삭제 길 = close(gone 확인)·--forget 둘 + R_PRE 만 돈 open 실패 · 줄 = 정확히 8칸(아니면 rc6)
      R3 확인된 줄의 원격 조회·kill·입력 = 기록 소켓(tmux -S)만
원격 쓰기 = mini ~/<SAT_ROOT_REMOTE>/<run>/ · 쪽지함(+quarantine/) 뿐 · 사용자 값은 위치 인자(shlex 인용)로만.
rc: 0 ok · 1 다른 pull·open/close 진행 중(원격 0) · 2 값·설정·기록 실패(원격 0) · 3 열기 실패·다른 세션 · 4 불확실/전달 실패(기록 유지)
    5 원격 실패·총 마감·남의 세션 · 6 조회/닫기 확인 실패·표식 없음(기록 유지) · 7 pull 미완(skip·실패·dead·ack 실패)
    8 문 닫힘(상한 — 원격 쓰기 0 · 명부 행 0)
"""
import base64
import hashlib
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ft_sat_gate as gate  # noqa: E402
import ft_sat_rt as rt  # noqa: E402
from ft_sat_rt import Fail  # noqa: E402

HARNESS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RROOT = os.environ.get("SAT_ROOT_REMOTE", "Project/satellite-nano")
MODEL = os.environ.get("SAT_MODEL", "opengateway/deepseek/deepseek-v4.1-flash-ultrafast")
MPY = os.environ.get("SAT_MINI_MBOX_PY", "$HOME/.claude/skills/fable-team/scripts/ft-mbox.py")
KILL_OK = "session=gone pi_left=0 err=0"

# ── 원격 고정 스크립트 — 첫 인자 = tmux 소켓(R3 · 빔 = 기본 서버 · 확인된 줄은 기록 소켓만) ──
# has-session 의 «없음» 은 정상 응답(rc1 ∧ can't find session / no server running)만 · 그 밖은 2(조회 실패)
# «없음» 을 지우는 증거로 쓰는 곳은 close 뿐이고, close 는 확인된 줄(소켓 기록)에서만 조회한다
TM = """SOCK="$1"; shift
tm() { if [ -n "$SOCK" ]; then tmux -S "$SOCK" "$@"; else tmux "$@"; fi; }
"""
SESS = TM + """sess() { e="$(tm has-session -t "=$1" 2>&1)"; r=$?; case "$r:$e" in 0:*) echo 0;; "1:can't find session"*|"1:no server running"*) echo 1;; *) echo 2;; esac; }
"""
IDENT_FMT = "'#{session_id} #{session_created} #{socket_path} #{pane_current_path}'"
R_PRE = SESS + """for t in tmuxc pi perl; do if command -v "$t" >/dev/null 2>&1; then echo "$t=ok"; else echo "$t=MISSING"; fi; done
echo "sess_rc=$(sess "$1")"
mf=$(mktemp)
perl -e 'alarm 3; exec @ARGV' memory_pressure >"$mf" 2>/dev/null; mrc=$?
echo "free_rc=$mrc"
echo "free_raw=$(sed -n 's/.*free percentage: *\\([0-9][0-9]*\\)%.*/\\1/p' "$mf")"
rm -f "$mf"
if [ -e "$HOME/$2" ]; then echo dir=EXISTS; else echo dir=absent; fi
"""
R_WRITE = 'd="$HOME/$1"; mkdir -p "$d" && cat >"$d/TASK.md"\n'
R_OPEN_BG = """d="$HOME/$1"; cd "$d" || exit 3
if [ -f "$d/.open.pid" ]; then echo running; cat "$d/.open.pid"; exit 0; fi
if ! mkdir "$d/.open.claim" 2>/dev/null; then
  if [ -d "$d/.open.claim" ]; then echo claimed; exit 0; fi
  echo claim_fail; exit 4
fi
nohup bash -c 'perl -e "alarm 60; exec @ARGV" tmuxc open "$1" --name "$2" --agent pi --role worker --model "$3" --effort medium; echo $? >"$1/.open.done"' _ "$d" "$2" "$3" >"$d/.open.log" 2>&1 </dev/null &
p=$!; printf '%s %s\\n' "$p" "$(echo $(ps -o lstart= -p "$p"))" >"$d/.open.pid.tmp" && mv "$d/.open.pid.tmp" "$d/.open.pid" || exit 1
echo running; cat "$d/.open.pid"
"""
R_POLL = SESS + """d="$HOME/$2"; a=0
if [ -f "$d/.open.pid" ]; then read -r p l <"$d/.open.pid"; [ -n "$l" ] && [ "$(echo $(ps -o lstart= -p "$p" 2>/dev/null))" = "$l" ] && a=1; fi
echo "alive=$a"; echo "done=$(cat "$d/.open.done" 2>/dev/null)"; echo "sess_rc=$(sess "$1")"
tail -3 "$d/.open.log" 2>/dev/null | sed 's/^/log: /'
"""
R_IDENT = TM + 'tm display -p -t "=$1:" ' + IDENT_FMT + "\n"
R_PIDS = TM + """pp="$(tm display -p -t "=$1:" '#{pane_pid}' 2>/dev/null)"
if [ -n "$pp" ]; then pgrep -P "$pp" 2>/dev/null | wc -l | tr -d ' '; else echo 0; fi
"""
R_SEND = TM + """d="$HOME/$1"; f="$d/$2"; tok="$5"
mkdir -p "$d/.sent" || exit 4
if [ -e "$d/.sent/$tok/sent" ]; then echo ALREADY; exit 0; fi
if ! mkdir "$d/.sent/$tok" 2>/dev/null; then echo CLAIMED; exit 0; fi
if [ "$4" = write ]; then cat >"$f" || exit 4; fi
[ -s "$f" ] || exit 4
msg="[발주 #1] $f 를 읽고 그대로 수행해라. 결과는 같은 폴더 out.md."
[ -n "$msg" ] || exit 4
tm send-keys -t "=$3:" -l "$msg" && sleep 1 && tm send-keys -t "=$3:" Enter || { : >"$d/.sent/$tok/FAIL"; exit 1; }
: >"$d/.sent/$tok/sent" || exit 1
echo SENDOK
"""
R_CAT = 'cat "$HOME/$1/$2"\n'
R_LOOKUP = SESS + """h="$(sess "$1")"; echo "has=$h"
if [ "$h" = 0 ]; then
  i="$(tm display -p -t "=$1:" """ + IDENT_FMT + """ 2>/dev/null)"; echo "drc=$?"
  echo "ident=$i"
  p="${i#* }"; p="${p#* }"; p="${p#* }"; d="$HOME/$2"
  case "$p" in "$d"|"$d"/*) echo dirmatch=1;; *) echo dirmatch=0;; esac
fi
"""
R_KILL = SESS + """if [ -n "$1" ]; then tm kill-session -t "$1" >/dev/null 2>&1; fi
n=0; h=0
while [ "$n" -lt 6 ]; do h="$(sess "$2")"; [ "$h" != 0 ] && break; sleep 0.5; n=$((n + 1)); done
case "$h" in 0) s=alive;; 1) s=gone;; *) s=unknown;; esac
d="$HOME/$3"; left=0; err=0
pids="$(pgrep -x pi 2>/dev/null)"; prc=$?
if [ "$prc" -ge 2 ]; then err=1; fi
for p in $pids; do
  o="$(lsof -a -p "$p" -d cwd -Fn 2>/dev/null)"; lrc=$?
  if [ "$lrc" != 0 ]; then err=1; continue; fi
  c="$(printf '%s\\n' "$o" | sed -n 's/^n//p')"
  case "$c" in "$d"|"$d"/*) left=$((left + 1));; esac
done
echo "session=$s pi_left=$left err=$err"
"""
R_PY = 'python3 -c "$1" "${@:2}"\n'
PY_HEAD = """import base64,importlib.util,json,os,sys
s=importlib.util.spec_from_file_location('m',os.path.expandvars(sys.argv[1]))
m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
"""
PY_READ = PY_HEAD + """seats=set(sys.argv[2].split(','));mx=int(sys.argv[3]);mr=int(sys.argv[4])
rows=m._locked(m.CANON,lambda:[r for r in m._load(m.CANON) if r.get('to') in seats])[:mr]
out=[]
for r in rows:
    b=str(r.get('body','')).encode('utf-8')
    e={'seq':r.get('seq'),'to':r.get('to',''),'from':r.get('from','')}
    if len(b)>mx: e['oversize']=len(b)
    else: e['b64']=base64.b64encode(b).decode()
    out.append(e)
print(json.dumps(out))
"""
PY_ACK = PY_HEAD + """mode=sys.argv[2];seqs=set(json.loads(sys.argv[3]))
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
"""


def say(msg):
    print(f"[sat] {msg}", flush=True)


def kv(out):
    d = {}
    for ln in out.decode("utf-8", "replace").splitlines():
        k, sep, v = ln.partition("=")
        if sep and k not in d:
            d[k] = v
    return d


def tail(out, err=""):
    s = (err or "").strip() or out.decode("utf-8", "replace").strip()
    return " | ".join(s.splitlines()[-2:])


def same(a, b):
    return a == b


def unsure(name, d, why):
    return (f"열기 불확실({why}) — 기록 유지 · 자동 삭제 0 · mini `tmux ls`·~/{d}/.open.log 확인 뒤 "
            f"close {name} --forget --why '<사유>'(세션 없음) 또는 close {name} --adopt(세션 있음·폴더 일치)")


def opts(argv, flags, valued):
    pos, o = [], {}
    it = iter(argv)
    for a in it:
        if a in flags:
            o[a] = True
        elif a in valued:
            o[a] = next(it, None)
            if o[a] is None:
                raise Fail(2, f"{a} 값이 없다")
        elif a.startswith("--"):
            raise Fail(2, f"모르는 옵션: {a}")
        else:
            pos.append(a)
    return pos, o


def send_task(dl, d, fname, name, mode, tok, sock, stdin=None):
    """SEND = 되풀이 금지 — claim 3상태 · 자동 재시도 0(idem=False) · 입력은 기록 소켓의 서버로만(R3)."""
    rc, out, err = rt.rcall(dl, R_SEND, sock, d, fname, name, mode, tok, stdin=stdin, idem=False)
    lines = out.decode("utf-8", "replace").splitlines()
    if "SENDOK" in lines:
        return "sent"
    if "ALREADY" in lines:
        return "already"
    if "CLAIMED" in lines:
        raise Fail(4, f"전달 불확실(CLAIMED: 이전 시도의 결과 모름) — 입력 0 · mini pane 확인 뒤 task {name} <파일> --retry")
    if rc == 4:
        raise Fail(4, "전달 실패(원격 폴더·빈 파일·빈 지시문) — sent 0 · 입력 0")
    raise Fail(4, f"전달 불확실(rc={rc}) — 자동 재시도 0 · mini pane 확인 뒤 --retry: {tail(out, err)}")


def cmd_open(argv):
    pos, o = opts(argv, (), ("--run", "--name"))
    card = pos[0] if pos else ""
    if len(pos) != 1 or not os.path.isfile(card):
        raise Fail(2, f"usage open <카드파일> [--run R] [--name N] — 카드 파일이 없다: {card or '<없음>'}")
    run = o.get("--run") or re.sub(r"^[^A-Za-z0-9]+", "", re.sub(r"[^A-Za-z0-9._-]", "-", os.path.splitext(os.path.basename(card))[0]))[:40]
    name = o.get("--name") or gate.auto_name(run)
    rt.need("run", run, "--run")
    rt.need("name", name, "--name")
    gate.lint_name(name)
    rt.need("root", RROOT, "SAT_ROOT_REMOTE")
    rt.need("model", MODEL, "SAT_MODEL")
    try:
        with open(card, "rb") as f:
            data = f.read()
    except OSError as e:
        raise Fail(2, f"카드 읽기 실패(원격 0): {card} ({e})")
    gate.no_secret(data, "카드(TASK)", gate.slug(run), name)
    cfg = rt.config()
    dl = rt.Deadline(cfg["total"], cfg["tmo"])
    rt.ensure_state()
    d = f"{RROOT}/{run}"
    with rt.ledger(dl):
        reserve(dl, name, run, d)
        return open_body(dl, name, run, d, data)


def reserve(dl, name, run, d):
    """R1 — 같은 이름·같은 run 줄 검사와 pending 추가(write-ahead)를 명령 내내 쥔 장부 잠금 안에서 · 실패 = rc2 · 원격 0."""
    if any(r[0] == name or rt.same_run(r, run) for r in rt.read_rows("opened.tsv")):
        raise Fail(2, f"이 도구의 기록에 같은 이름 또는 같은 run 이 남아 있다 — close 먼저 · 원격 0: {name} run={run}")
    gate.gate_cap(gate.slug(run), name)  # r949 — 상한 = 원격 전
    rt.in_time(dl, "pending 기록 전", "원격 0")
    rt.opened_add([name, run, d, time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "", "", "", ""])
    try:
        gate.roster_add(run, name)
    except Fail:
        rt.opened_del(run)  # 원격 0 — 두 기록을 함께 되돌린다
        raise


def open_body(dl, name, run, d, data):
    try:
        free, warn = pre(dl, name, run, d)
    except Fail:
        rt.in_time(dl, "pending 삭제 전", unsure(name, d, "사전점검 뒤 마감 · 원격 쓰기 0"))
        rt.opened_del(run)  # R2 — 원격 호출이 R_PRE(읽기 전용) 뿐 · 세션이 생길 길 0
        gate.roster_drop(run)
        raise
    gate.ledger_open(gate.slug(run), name, free, warn, d)  # r949 r4 — 열기 줄 1(경고는 그 줄의 칸)
    write_task(dl, name, d, data)  # R2 — R_WRITE 를 부르기 시작했으면 결과와 무관하게 실패 = rc4 · 줄 유지
    try:
        sock = open_bg_and_poll(dl, name, run, d)
    except Fail as e:
        if e.rc == 5:
            raise Fail(5, f"{e.msg} — 열기 진행 중일 수 있다 · {unsure(name, d, '마감')}")
        raise
    if os.environ.get("SAT_NOWAIT", "0") != "1":
        wait_pi(dl, name, sock)
    dl.check("지시 전달")
    send_task(dl, d, "TASK.md", name, "keep", "TASK.md", sock)
    dl.check("open 끝")
    say(f"4/4 지시 전달 — TASK.md · 회수 fetch {name} · 닫기 close {name}")
    return 0


def pre(dl, name, run, d):
    """사전점검 1회 ssh — 확인된 칸으로 진행하고, free% 판정은 gate.gate_free 한 곳이 한다(r949 r4).
    반환 = (free 칸, warn 칸) — 열기 줄에 쓰인다."""
    rc, out, err = rt.rcall(dl, R_PRE, "", name, d)
    text = out.decode("utf-8", "replace")
    k = kv(out)
    if rc != 0 and ("sess_rc=" not in text or "dir=" not in text):
        raise Fail(5, f"mini 접속 실패(rc={rc}): {tail(out, err)}")  # 볼 칸이 아예 없다 = 진짜 접속 실패
    for ln in text.splitlines():
        say(f"  {ln}")
    if b"MISSING" in out:
        raise Fail(2, "mini 에 필요한 도구가 없다(위 MISSING)")
    free, warn = gate.gate_free(k.get("free_raw", ""), k.get("free_rc", ""), rc, gate.slug(run), name)
    if k.get("sess_rc") == "0":
        raise Fail(2, f"같은 이름 세션이 이미 있다 — 남의 세션이라 건드리지 않는다: {name}")
    if k.get("sess_rc") != "1":
        raise Fail(5, f"mini 세션 조회 실패(sess_rc={k.get('sess_rc')}) — 열지 않는다")
    if k.get("dir") != "absent":
        raise Fail(2, f"작업 폴더가 이미 있다 — --run <다른이름> 으로 다시: {d}")
    return free, warn


def write_task(dl, name, d, data):
    try:
        rc, out, err = rt.rcall(dl, R_WRITE, d, stdin=data)
    except Fail as e:
        raise Fail(4, unsure(name, d, f"TASK.md 쓰기 중 {e.msg} · 원격 열기 전"))
    if rc != 0:
        raise Fail(4, unsure(name, d, f"TASK.md 쓰기 결과 모름 rc={rc} · 원격 열기 전: {tail(out, err)}"))
    say(f"1/4 작업 폴더·TASK.md — {d}/TASK.md")


def open_bg_and_poll(dl, name, run, d):
    rc, out, err = rt.rcall(dl, R_OPEN_BG, d, name, MODEL)
    first = (out.decode("utf-8", "replace").splitlines() or [""])[0]
    if rc == 4 and first == "claim_fail":
        raise Fail(4, unsure(name, d, "상태=claim_fail · 원격 claim 폴더 생성 실패"))
    if rc == 0 and first == "claimed":
        raise Fail(4, unsure(name, d, "상태=claimed · 이전 시도의 결과 모름"))
    if not (rc == 0 and first == "running"):
        raise Fail(4, unsure(name, d, f"원격 열기 응답 모름 rc={rc}: {tail(out, err)}"))
    while True:
        rc, out, err = rt.rcall(dl, R_POLL, "", name, d)
        if rc != 0:
            raise Fail(6, f"세션 확인 조회 실패(rc={rc}) — 기록 유지: {tail(out, err)}")
        k = kv(out)
        if k.get("sess_rc") == "0":
            break
        if k.get("sess_rc") != "1":
            raise Fail(6, f"세션 조회 실패(sess_rc={k.get('sess_rc')}) — 기록 유지 · 원격 추가 호출 0")
        if k.get("alive") != "1":
            logs = " ".join(ln for ln in out.decode("utf-8", "replace").splitlines() if ln.startswith("log:"))
            raise Fail(4, unsure(name, d, f"opener 끝났으나 세션 없음 done={k.get('done')} {logs}"))
        dl.check("open 세션 확인")
        time.sleep(max(0.0, min(2.0, dl.left())))
    rc, out, err = rt.rcall(dl, R_IDENT, "", name)
    p = out.decode("utf-8", "replace").strip().split(" ", 3)  # session_id created socket pane_path
    if rc != 0 or len(p) != 4 or not all(p) or not rt.valid("sock", p[2]):
        raise Fail(6, f"신원 조회 실패(세션은 있음 · 기록 pending · {unsure(name, d, 'IDENT')}): {tail(out, err)}")
    rt.in_time(dl, "신원 기록 전", unsure(name, d, "세션은 있음 · 신원 기록 전 마감"))
    rt.opened_set_ident(run, p[0], p[1], p[3], p[2])
    gate.roster_set(run, status="OPEN", sock=p[2])
    say(f"  OPEN ok name={name} id={p[0]}")
    say(f"2/4 세션 열기 — {name} (이 도구가 연 세션으로 기록 · 신원 {p[0]} {p[1]} · 소켓 {p[2]})")
    return p[2]


def wait_pi(dl, name, sock):
    for i in range(6):
        dl.check("pi 기동 확인")
        rc, out, _ = rt.rcall(dl, R_PIDS, sock, name)
        if rc == 0 and out.strip().isdigit() and int(out.strip()) >= 1:
            say("3/4 pi 기동 확인")
            return
        if i < 5:
            time.sleep(max(0.0, min(5.0, dl.left())))
    raise Fail(3, f"pi 프로세스가 안 떴다(HARD GATE: 자식 0건 — 입력 전송 금지 · close {name} 으로 정리)")


def cmd_task(argv):
    pos, o = opts(argv, ("--retry",), ())
    if len(pos) != 2 or not os.path.isfile(pos[1]):
        raise Fail(2, "usage task <세션> <파일> [--retry]")
    name, path = pos
    rt.need("name", name, "세션 이름")
    row = rt.opened_find(name)
    if not row:
        raise Fail(5, f"이 도구가 연 세션이 아니다 — 남의 세션에는 쓰지 않는다: {name}")
    if not rt.confirmed(row):
        raise Fail(4, f"열기 불확실 줄 — 입력 0 · {unsure(name, row[2], 'pending')}")
    cfg = rt.config()
    dl = rt.Deadline(cfg["total"], cfg["tmo"])
    with open(path, "rb") as f:
        data = f.read()
    gate.no_secret(data, "task 입력", gate.slug(row[1]), name)
    target = f"TASK-{hashlib.sha256(data).hexdigest()[:8]}.md"
    tok = target
    if "--retry" in o:
        k = 1 + sum(1 for r in rt.read_rows("retries.tsv") if r[:2] == [name, target])
        rt.append_line(rt.spath("retries.tsv"), f"{name}\t{target}\t{k}")  # 기록 먼저
        tok = f"{target}.r{k}"
    res = send_task(dl, row[2], target, name, "write", tok, row[7], stdin=data)
    if res == "already":
        say(f"SKIP 같은 작업이 이미 전달됐다(중복 0) — {row[2]}/{target}")
    else:
        say(f"TASK ok run={row[1]} file={row[2]}/{target} token={tok}")
    return 0


def mbox_sh():
    if os.environ.get("SAT_MBOX_SH"):
        return os.environ["SAT_MBOX_SH"]
    for c in (os.path.expanduser("~/.claude/skills/fable-team/scripts/ft-mbox.sh"),
              os.path.join(HARNESS, "kit/fable-team/bin/ft-mbox.sh"), os.path.join(HARNESS, "bin/ft-mbox.sh")):
        if os.path.isfile(c):
            return c
    raise Fail(2, "이 맥 ft-mbox.sh 를 못 찾았다(SAT_MBOX_SH 로 지정)")


def deliver(r, cfg, dl, mb):
    """쪽지 1건 — 최소 한 번: intent 기록 → send → 정형 QUEUED 일 때만 done · 재발신 상한 넘으면 dead."""
    seq = int(r["seq"])
    key = f"mini:{seq}"
    last = rt.delivered_last(key)
    n = 1
    if last and last[0] in ("done", "dead"):
        return last[0]
    if last:
        if rt.now() - last[1] < 2 * cfg["tmo"]:
            say(f"SKIP seq={seq} intent 창 안(다른 pull 이 보내는 중일 수 있다 · ack 0)")
            return "skip"
        if last[2] >= cfg["resend_max"]:
            rt.delivered_put(key, "dead", last[2])
            say(f"ERROR dead seq={seq} 발신 {last[2]}회 실패(상한 {cfg['resend_max']}) — 배달 0 · mini quarantine/ 으로 이동")
            return "dead"
        n = last[2] + 1
    rt.delivered_put(key, "intent", n)
    body = f"[sat mini:{seq} from={r.get('from', '')}]\n".encode() + base64.b64decode(r["b64"])
    rc, so, _ = rt.run_child(["bash", mb, "send", str(r.get("to", "")), str(r.get("from", "")), body], dl.child_timeout("pull 배달"))
    queued = rc == 0 and re.match(rb"QUEUED seq=[0-9]+ ", so.split(b"\n", 1)[0]) is not None
    if not queued:
        say(f"DELIVER_FAIL seq={seq} rc={rc} (done 0 · intent 유지 · ack 0)")
        return "fail"
    try:
        rt.delivered_put(key, "done", n)
    except Fail as e:
        say(f"RECORD_FAIL seq={seq} ({e.msg} — ack 안 함)")
        return "fail"
    return "done"


def pull_once(seats, cfg, mb, turn, every):
    dl = rt.Deadline(cfg["total"], cfg["tmo"])
    fd = rt.flock_try(rt.spath("pull.flock"))
    if fd is None:
        raise Fail(1, f"다른 pull 진행 중(5초 안에 잠금을 못 잡았다): {rt.spath('pull.flock')}")
    try:
        rc, out, err = rt.rcall(dl, R_PY, PY_READ, MPY, seats, os.environ.get("SAT_MAX_BODY", "262144"), os.environ.get("SAT_PULL_ROWS", "20"))
        if rc != 0:
            raise Fail(5, f"mini 쪽지함 읽기 실패(rc={rc}): {tail(out, err)}")
        try:
            rows = json.loads(out)
        except ValueError:
            raise Fail(5, "mini 쪽지함 응답 해석 실패")
        acks, quar, bad = [], [], 0
        for r in rows:
            dl.check("pull 배달")
            if "oversize" in r:
                say(f"ERROR oversize seq={r['seq']} bytes={r['oversize']} — 받지 않음 · mini quarantine/ 으로 이동(삭제 0)")
                quar.append(int(r["seq"]))
                continue
            res = deliver(r, cfg, dl, mb)
            if res == "done":
                acks.append(int(r["seq"]))
            else:
                bad += 1
                if res == "dead":
                    quar.append(int(r["seq"]))
        dl.check("pull 마지막 배달 뒤")
        for mode, seqs in (("ack", acks), ("quarantine", quar)):
            if seqs and rt.rcall(dl, R_PY, PY_ACK, MPY, mode, json.dumps(seqs))[0] != 0:
                say(f"{mode.upper()}_FAIL (다음 pull 에서 장부로 중복 없이 재시도)")
                bad += 1
        dl.check("pull 끝")
    finally:
        os.close(fd)
    say(f"PULL {'ok' if bad == 0 else 'partial'} seen={len(rows)} delivered={len(acks)} incomplete={bad} every={every} turn={turn}")
    return 7 if bad else 0


def cmd_pull(argv):
    pos, o = opts(argv, (), ("--seats", "--every"))
    seats = o.get("--seats") or os.environ.get("SAT_SEAT", "")
    every = o.get("--every") or "0"
    if pos or not seats:
        raise Fail(2, "수신 좌석이 없다 — pull --seats A,B (또는 SAT_SEAT)")
    rt.need("seats", seats, "수신 좌석")
    rt.need("mpy", MPY, "SAT_MINI_MBOX_PY")
    if not re.fullmatch(r"[0-9]{1,5}", every):
        raise Fail(2, f"--every 는 숫자(초)여야 한다: {every}")
    cfg = rt.config()
    mb = mbox_sh()
    rt.ensure_state()
    worst, mx = 0, rt.cfg_int("SAT_PULL_MAX", 30, 1, 999)
    for i in range(1, mx + 1):
        worst = max(worst, pull_once(seats, cfg, mb, i, every))
        if int(every, 10) == 0:
            break
        if i < mx:
            time.sleep(int(every, 10))
    return worst


def cmd_fetch(argv):
    pos, _ = opts(argv, (), ())
    name = pos[0] if len(pos) == 1 else ""
    rt.need("name", name, "세션 이름")
    row = rt.opened_find(name)
    if not row:
        raise Fail(5, f"이 도구가 연 세션이 아니다: {name}")
    cfg = rt.config()
    dl = rt.Deadline(cfg["total"], cfg["tmo"])
    outd = os.path.join(os.environ.get("SAT_OUT_DIR") or os.path.join(HARNESS, "evidence/r902"), row[1])
    os.makedirs(outd, exist_ok=True)
    n = 0
    for f in ("out.md", "TASK.md"):
        rc, out, err = rt.rcall(dl, R_CAT, row[2], f)
        if rc in (124, 255):
            raise Fail(5, f"원격 실패·시간 초과(rc={rc}): {tail(out, err)}")
        if rc == 0 and out:
            with open(os.path.join(outd, f), "wb") as fh:
                fh.write(out)
            n += 1
            say(f"FETCH {os.path.join(outd, f)}")
    if n == 0:
        raise Fail(5, f"회수할 결과가 없다(아직 안 썼거나 경로가 다르다): {row[2]}")
    say(f"FETCH ok run={row[1]} files={n}")
    return 0


def cmd_close(argv):
    pos, o = opts(argv, ("--adopt", "--forget"), ("--why",))
    name = pos[0] if len(pos) == 1 else ""
    rt.need("name", name, "세션 이름")
    cfg = rt.config()
    dl = rt.Deadline(cfg["total"], cfg["tmo"])
    rt.ensure_state()
    with rt.ledger(dl):  # R1 — close·--adopt·--forget 도 명령 내내 장부 잠금
        row = rt.opened_find(name)
        if not row:
            raise Fail(5, f"이 도구가 연 세션이 아니다 — 남의 세션은 닫지 않는다: {name}")
        if "--forget" in o:
            rc = forget(dl, row, o.get("--why"))
            gate.closed(row, "forget")
            return rc
        gate.roster_marked(name)  # r949 — 이 도구 표식이 있는 줄만 닫는다
        rc = close_row(dl, row, "--adopt" in o)
        gate.closed(row, "close")
        return rc


def close_row(dl, row, adopt):
    name, run = row[0], row[1]
    conf = rt.confirmed(row)
    if conf and adopt:
        raise Fail(2, f"확인된 세션이다 — --adopt 없이 close {name} 로 닫는다")
    if not conf and not adopt:
        raise Fail(4, f"{unsure(name, row[2], 'pending · 신원 미확인')} · 원격 kill 0")
    sock = row[7] if conf else ""  # R3 — 확인된 줄은 기록 소켓만 · --adopt(pending)는 기본 서버에서 찾고 소켓을 채운다
    rc, out, err = rt.rcall(dl, R_LOOKUP, sock, name, row[2])
    k = kv(out)
    has, ident = k.get("has"), k.get("ident", "").split(" ", 3)  # session_id created socket pane_path
    whole = rc == 0 and has == "0" and k.get("drc") == "0" and len(ident) == 4 and all(ident) and rt.valid("sock", ident[2])
    if adopt:
        if not (whole and k.get("dirmatch") == "1"):
            raise Fail(4, f"채울 세션이 없다/다르다/조회 실패(rc={rc} has={has} drc={k.get('drc')} dirmatch={k.get('dirmatch')}) — 삭제 0 · 건드림 0")
        rt.in_time(dl, "신원 기록 전", "--adopt 마감 — 기록 그대로(pending) · 원격 0")
        rt.opened_set_ident(run, ident[0], ident[1], ident[3], ident[2])
        kid, sock = ident[0], ident[2]
        say(f"ADOPT 신원 채움 {' '.join(ident)}")
    elif rc != 0 or has not in ("0", "1"):
        raise Fail(6, f"세션 조회 실패(rc={rc} has={has}) — 닫힘으로 보지 않는다(기록 유지): {tail(out, err)}")
    elif has == "1":
        kid = ""  # 기록 소켓의 정상 «없음» + 신원 찬 줄 = gone 후보 — R_KILL 확인(pi 0·err 0)을 거쳐야 지운다
    else:
        if not whole:
            raise Fail(6, "세션 신원 조회 실패 — 건드리지 않는다(기록 유지)")
        now_id = [ident[0], ident[1], ident[3]]
        if not same(" ".join(now_id), " ".join(row[4:7])):
            raise Fail(3, f"다른 세션이다 — 같은 이름이지만 신원이 다르다(기록 {' '.join(row[4:7])} / 지금 {' '.join(now_id)}) · 건드림 0: {name}")
        kid = ident[0]
    rc, out, err = rt.rcall(dl, R_KILL, sock, kid, name, row[2])
    for ln in out.decode("utf-8", "replace").splitlines():
        say(f"  {ln}")
    ok = rc == 0 and KILL_OK in out.decode("utf-8", "replace")
    if not ok:
        raise Fail(6, f"닫기 확인 실패 — 세션/프로세스가 남았거나 확인이 안 됐다(강제 kill 0 · 기록 유지): {name}")
    rt.in_time(dl, "삭제 전", "닫힘 확인했으나 마감 초과 — 기록 유지 · 다시 close 하면 gone 경로로 지운다")
    rt.opened_del(run)
    say(f"CLOSE ok {name} — 세션 없음 · 이 폴더에서 도는 pi 0")
    return 0


def forget(dl, row, why):
    """--forget = 기록만 지운다(원격 호출 0) · pending 줄에만 · 이유 필수 · forgotten.tsv 1줄."""
    w = (why or "").strip()
    if not w or len(why) > 200 or any(c in why for c in "\t\r\n"):
        raise Fail(2, "--forget 은 --why '<1~200자 한 줄>' 필수 — 기록 그대로 · 원격 0")
    if rt.confirmed(row):
        raise Fail(2, "확인된 세션은 close 로 닫는다(--forget 불가) — 기록 그대로")
    rt.in_time(dl, "forget 기록 전", "--forget 마감 — 기록 그대로 · 원격 0")
    rt.forgotten_add(row, w)
    rt.in_time(dl, "삭제 전(forget 기록 뒤)", "forget 기록은 남았으나 마감 초과 — 줄 유지 · 다시 --forget")
    rt.opened_del(row[1])
    say(f"FORGET ok {row[0]} — 기록만 지움 · 원격 세션은 손대지 않음 · forgotten.tsv 1줄")
    return 0


def main(argv):
    cmds = {"open": cmd_open, "task": cmd_task, "pull": cmd_pull, "fetch": cmd_fetch, "close": cmd_close, "roster": gate.cmd_roster}
    if not argv or argv[0] not in cmds:
        print("usage: ft-sat-nano.sh {open <카드> [--run R] [--name N] | task <세션> <파일> [--retry] | pull --seats A,B [--every N]"
              " | fetch <세션> | close <세션> [--adopt | --forget --why '<사유>'] | roster}", file=sys.stderr)
        return 2
    try:
        return cmds[argv[0]](argv[1:])
    except Fail as e:
        print(f"[sat] REJECT rc={e.rc} {e.msg}", file=sys.stderr, flush=True)
        return e.rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
