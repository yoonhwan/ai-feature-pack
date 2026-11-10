#!/usr/bin/env bash
# ft-bg-watch-check.sh — 좌석 밖 상주 감시 비모델 점검 (r1572 · 카드 r1572-detached-watch-ttl · 수용 ⓑ·ⓒ)
#   대상 = ppid 1 ∧ 내 uid ∧ 명령줄이 «셸·python 감시 꼴»(watch|loop|while|monitor|tail -f|nohup|daemon)
#   알림 = 장부(bg-watch.tsv) 밖이거나 그 인스턴스에 적힌 끝 시각이 지난 것 → 소유자(장부 좌석 · 없거나 닫혔으면 desk)에 1통
#   중복 억제 키 = uid:pid:lstart:명령줄해시 — 같은 인스턴스 1통 · 같은 PID 라도 lstart 이 다르면 새 인스턴스(따로 1통)
#          · 옛 장부 행을 새 인스턴스의 면제로 쓰지 않는다(키에 lstart 이 든다) · 같은 키로 두 번 안 보낸다(장부 옆 .seen 1줄)
#   시작 시각을 못 읽으면 «판정 불가» 1줄 — 알림 완료로도 면제 확정으로도 적지 않는다(다음 점검이 다시 본다)
#   중복 억제는 «사유별» — 장부밖 알림을 이미 보낸 인스턴스를 adopt 해도 기한지남 알림은 따로 1통 간다(사유마다 1통 · 같은 사유 두 번 0)
#   오탐 0(ⓒ) = launchd 소유 · tmux 서버 · 사람 앱(.app/) · 현역 MCP(0·1번 fd 가 PIPE) · hermes browser_harness.daemon(다른 하네스 소유 · 실행 자리만) · 장부 안(up·adopt) ∧ 끝 시각 전 → 알림 0
#   kill 0(ⓑ) — 종료는 소유자 또는 h. 읽기·쪽지·장부 읽기만 한다(프로세스 변경 0 · 새 launchd 0)
#   출력 = `SKIP <pid> <사유>` · `NA <pid> 판정 불가 — 시작 시각을 못 읽음` · `NOTIFY <pid> <키> <사유=장부밖|기한지남> -> <받는좌석>` · 마지막 줄 `check sent=<n> skip=<m> na=<k>` rc0
#   env(시험·이식): FT_BGW_LEDGER · FT_BGW_SEEN · FT_BGW_PS_CMD · FT_BGW_LAUNCHCTL_CMD · FT_BGW_LSOF_CMD · FT_BGW_MBOX · FT_BGW_TMUX_CMD · FT_BGW_NOW_CMD · FT_BGW_UID · FT_BGW_DESK · FT_MBOX_DIR
#   사용: bash ft-bg-watch-check.sh   (기존 감시 주기에 1줄로 붙인다 · 주기 실행 자체는 부르는 쪽 몫)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/ft-harness-root.sh"
COMM="$(ft_comm_dir "$HERE" 2>/dev/null)" || COMM=""
MBOX="${FT_BGW_MBOX:-}"; [ -n "$MBOX" ] || [ -z "$COMM" ] || MBOX="$COMM/mbox.sh"
LDG="${FT_BGW_LEDGER:-}"
if [ -z "$LDG" ]; then DR="$(ft_data_root "$HERE" 2>/dev/null)" || DR=""; LDG="${DR:-.}/.fable-team/state/bg-watch.tsv"; fi
FT_BGW_MBOX_X="$MBOX" FT_BGW_LEDGER_X="$LDG" FT_BGW_SEATS_X="${FT_BGW_SEATS_X:-${COMM:+$(dirname "$COMM")}}" exec python3 - <<'PY'
import glob, hashlib, json, os, re, subprocess, sys, time

def run(tpl, **kw):
    try: return subprocess.run(tpl.format(**kw), shell=True, capture_output=True, text=True, timeout=7).stdout
    except Exception: return ""

def now():
    v = run(os.environ.get("FT_BGW_NOW_CMD") or "date +%s").strip()
    return int(v) if v.isdigit() else int(time.time())

def alive(seat):
    tpl = os.environ.get("FT_BGW_TMUX_CMD") or "tmux has-session -t {seat}"
    try: return subprocess.run(tpl.format(seat=seat), shell=True, capture_output=True, timeout=7).returncode == 0
    except Exception: return False

def roster():                     # 명부(seats*.json) 전부 — 현역 판정은 «명부 글자» 로만 한다
    js = {}
    for p in sorted(glob.glob(os.path.join(os.environ.get("FT_BGW_SEATS_X") or "", "seats*.json"))):
        try: js[p] = json.load(open(p, encoding="utf-8"))
        except Exception: pass
    return js

def desk(js):                     # 받는 자리 = seats-planner.json 의 _desk 하나(DA R3 · R5) — 정렬 첫 _desk·이름 글자·_master 로 대체 0
    if os.environ.get("FT_BGW_DESK"): return os.environ["FT_BGW_DESK"]
    for p, j in js.items():
        if os.path.basename(p) == "seats-planner.json": return j.get("_desk") or ""
    return ""

def closed(js, seat):             # 닫힘 = 명부가 은퇴(_replaced_by)로 적었거나, 명부에 없고 세션도 없다
    if not seat: return True
    for j in js.values():
        row = j.get(seat)
        if isinstance(row, dict): return bool(row.get("_replaced_by"))
    return not alive(seat)

def send(to, body):               # 쪽지 1통 — 실패면 알림 완료로 적지 않는다
    m = os.environ.get("FT_BGW_MBOX_X") or ""
    if not m or not os.path.isfile(m): return False
    try:
        r = subprocess.run(["bash", m, "send", to, "ft-bg-watch-check", body], capture_output=True, text=True, timeout=7,
                           env={**os.environ, "FT_MBOX_DIR": os.path.dirname(m)})
        return r.returncode == 0
    except Exception: return False

UID = os.environ.get("FT_BGW_UID") or str(os.getuid())
LDG = os.environ["FT_BGW_LEDGER_X"]; SEEN = os.environ.get("FT_BGW_SEEN") or LDG + ".seen"
reg, ended = {}, set()          # 키 = uid:pid:lstart:명령줄해시 — lstart 이 다르면 다른 인스턴스
try: LEDGER = open(LDG, encoding="utf-8").read().splitlines()
except OSError: LEDGER = []
for ln in LEDGER:
    f = ln.split("\t")
    if len(f) < 11: continue
    k = "%s:%s:%s:%s" % (f[2], f[3], f[4], f[5])
    if f[0] in ("up", "adopt"):      # adopt = «이미 도는» 프로세스를 장부에 올린 줄(ft-bg-watch.sh --adopt) — up 과 같게 «장부 안»
        try: reg[k] = (f[1], int(f[6]))
        except ValueError: reg[k] = (f[1], -1)
    elif f[0] in ("done", "fail"): ended.add(k)
try: seen = {l.strip() for l in open(SEEN, encoding="utf-8") if l.strip()}
except OSError: seen = set()
LAUNCHD = {l.split()[0] for l in run(os.environ.get("FT_BGW_LAUNCHCTL_CMD") or "launchctl list").splitlines() if l.split() and l.split()[0].isdigit()}
SHELLRE = re.compile(r"(^|/)(bash|sh|zsh|dash|python[0-9.]*|Python[0-9.]*)$")  # Python.framework 실행 경로(/…/MacOS/Python) 포함
WATCHRE = re.compile(r"watch|loop|while|monitor|tail -f|nohup|daemon", re.I)
MCPRE = re.compile(r"mcp|serena|probe|lsp|language-server", re.I)   # 파이프만으로 MCP 라 단정하지 않는다(DA R4)
HERMES_PY = re.compile(r"(^|/)browser_harness/daemon\.py$")   # hermes 소유 데몬 — «실행 자리»만 본다(다른 스크립트의 인자로는 면제 0 · DA R2)
def hermes_daemon(t):
    if len(t) < 2 or not SHELLRE.search(t[0]): return False
    if t[1] == "-m" and len(t) > 2 and t[2] == "browser_harness.daemon": return True
    return bool(HERMES_PY.search(t[1]))
def skip_reason(cmd):             # 명령줄만으로 «감시 꼴» 이 아닌 것을 먼저 거른다(오탐 0 · ⓒ)
    t = cmd.split()
    if hermes_daemon(t): return "hermes 데몬"
    if t and t[0].rsplit("/", 1)[-1] == "tmux": return "tmux 서버"
    if t and SHELLRE.search(t[0]) and WATCHRE.search(cmd): return ""     # 인터프리터 + 감시 꼴 = 대상
    if t and (".app/" in t[0] or t[0].startswith("/Applications/")): return "사람 앱"   # Python.app 처럼 인터프리터 꼴은 위에서 먼저 걸러진다
    return "감시 꼴 아님"
JS = roster()                     # 명부는 1회만 읽는다
S = {"sent": 0, "skip": 0, "na": 0}
def note(kind, msg):
    print(kind, msg)
    if kind == "NOTIFY": S["sent"] += 1
    else: S[kind.lower()] += 1
PS = "env LC_ALL=C TZ=UTC " + (os.environ.get("FT_BGW_PS_CMD") or "ps -axo uid=,pid=,ppid=,lstart=,command=")   # lstart 은 ft-bg-finite 과 같은 LC_ALL=C TZ=UTC 5토큰 — 로캘이 다르면 토큰 수가 달라져 명령줄이 잘린다
for ln in run(PS).splitlines():
    f = ln.split()
    if len(f) >= 5 and f[3] == "-": u, pid, ppid, lst, cmd = f[0], f[1], f[2], "-", " ".join(f[4:])
    elif len(f) >= 8: u, pid, ppid, lst, cmd = f[0], f[1], f[2], " ".join(f[3:8]), " ".join(f[8:])
    else: continue
    if u != UID or ppid != "1": continue
    why = skip_reason(cmd)
    if why: note("SKIP", "%s %s" % (pid, why)); continue
    if pid in LAUNCHD: note("SKIP", "%s launchd 소유" % pid); continue
    if lst == "-": note("NA", "%s 판정 불가 — 시작 시각을 못 읽음" % pid); continue
    k = "%s:%s:%s:%s" % (u, pid, lst, hashlib.sha1(cmd.encode()).hexdigest()[:12])
    if MCPRE.search(cmd) and "tPIPE" in run(os.environ.get("FT_BGW_LSOF_CMD") or "lsof -a -p {pid} -d 0,1 -Fft", pid=pid): note("SKIP", "%s 현역 MCP(파이프 연결)" % pid); continue
    if k in ended: note("SKIP", "%s 장부 끝남" % pid); continue
    seat, reason = "", "장부밖"
    if k in reg:
        seat, end_at = reg[k]
        if now() < end_at: note("SKIP", "%s 장부 안·기한 전" % pid); continue
        reason = "기한지남"
    sk = k if reason == "장부밖" else k + "|" + reason   # 중복 억제 키는 «사유별» — 장부밖 알림과 기한지남 알림은 서로를 막지 않는다(각 1통)
    if sk in seen: note("SKIP", "%s 이미 1통" % pid); continue
    if closed(JS, seat):
        to = desk(JS)
        if not to or not alive(to): note("NA", "%s 판정 불가 — seats-planner.json _desk 없음 또는 세션 없음(알림 0)" % pid); continue
    else: to = seat
    body = ("좌석 밖 상주 감시가 장부 밖이거나 끝 시각이 지났다(점검 r1572 · 자동 종료 0)\n- pid %s · 시작 %s · 사유 %s\n- 명령: %s\n"
            "- 끝내는 사람 = 소유자 또는 h · 등록 = ft-bg-watch.sh --seat <좌석> --until <끝 조건> --end-at <끝 시각> --every <초>\n- 장부 = %s"
            % (pid, lst, reason, cmd[:100], LDG))
    if not send(to, body): note("SKIP", "%s 쪽지 실패" % pid); continue
    d = os.path.dirname(SEEN)
    if d: os.makedirs(d, exist_ok=True)
    with open(SEEN, "a", encoding="utf-8") as fh: fh.write(sk + "\n")
    seen.add(sk); note("NOTIFY", "%s %s %s -> %s" % (pid, k, reason, to))
print("check sent=%d skip=%d na=%d" % (S["sent"], S["skip"], S["na"]))
sys.exit(0)
PY
