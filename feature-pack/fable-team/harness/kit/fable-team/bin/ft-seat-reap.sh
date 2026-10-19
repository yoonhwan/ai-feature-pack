#!/usr/bin/env bash
# ft-seat-reap.sh <좌석> [--dry-run] [--wt <워크트리>] [--orphans-only] — 좌석이 띄운 백그라운드 프로세스(감시·증거 루프)를 찾아 멈춘다 (r448 · 골 6)
#   닫기 3종(ft-seat-close · ft-nano-close · ft-seat-retire)이 세션 kill «앞»에 부른다 — 좌석이 사라진 뒤 ppid 1 로 남아 로그를 쌓는 루프(10-19 tester67 guard.sh 5개)를 닫는 사건.
#   후보(내 uid 만): ①tmux 세션 =<좌석> 의 pane pid «자손»(pane pid 자신은 kill-session 몫)
#     ②env FT_SEAT=<좌석>(ppid 무관 · tmuxc 가 new-session -e 로 심음 · macOS 는 /bin/sh·/bin/zsh·/bin/sleep 같은 플랫폼 바이너리의 env 를 숨긴다 — brew bash·python·node 는 보임)
#     ②b argv `ft-bg-loop.sh --seat <좌석>` 래퍼(env 를 못 읽는 머신에서도 잡힘 · 자식은 아래 «자손»)
#     ③env 에 FT_SEAT 안 보임 ∧ ppid 1(고아) ∧ cwd ⊂ 좌석 워크트리(--wt · 없으면 세션 session_path · `.git` 있는 폴더만 · 안쪽 다른 워크트리 제외) ∧ 명령에 sleep·while
#        — 다른 라이브 tmux 세션이 그 워크트리 안에 있으면 ③ 생략(출력 `cwd=shared`) · 다른 세션 pane 나무에 속한 것도 제외
#   제외: 남의 FT_SEAT · 보호 exe(ft-leak-reap.sh 의 PROTECT_EXE 를 그대로 읽음 — 못 읽으면 rc 20) · 이 명령 자신과 조상
#     · 서비스 나무(r505 — 모든 모드 · 서비스 정지는 scripts/server/stop.command 몫): ⓐTCP LISTEN 을 쥔 프로세스와 그 조상·자손(`lsof -iTCP -sTCP:LISTEN` · 실패 = rc 20)
#       ⓑ 서비스 명령 꼴 FT_REAP_SERVICE_RE(기본 아래 SERVICE_RE)와 그 자손 — 후보였을 것만 앞 줄 `reap-skip pid=<n> why=service-listen|service-cmd cmd=<앞 100자>`(stopped·left 에 안 셈)
#   --orphans-only = ppid 1 인 것만(ft-seat-retire — 은퇴한 좌석의 살아 있는 에이전트·pane 나무는 건드리지 않는다)
#   정지: TERM → 최대 3 s → (같은 시작 시각일 때만) KILL → 최대 1 s → 재조사(같은 규칙) · left = 재조사 후보 수
#   후보의 자식(env 를 못 읽는 sleep 등)도 같은 주인(via=자손 · stopped 수엔 안 셈)
#   출력: 앞 줄 `reap-kill pid=<n> via=<①|②|②b|③|자손> cmd=<앞 100자>` · 끝 줄 `reap <좌석> stopped=<n> left=<n> rc=<n>[ cwd=shared]`
#     --dry-run = `reap-cand …` 줄 + `reap <좌석> found=<n> dry-run rc=0`
#   rc 0 = left 0 · 1 = left>0 · 2 = usage · 20 = 조사 실패(ps·lsof·tmux 못 읽음 — 0 과 구분 · ft-leak-reap ① 계약 · 끝 줄 left=? ). 외부 호출 각 7 s 상한.
#   FT_REAP_NOSIGNAL=1 = 시험 전용(신호 0 — «못 멈춘 프로세스» 재현).
set -uo pipefail
USAGE="usage: $0 <좌석> [--dry-run] [--wt <워크트리>] [--orphans-only]"
SEAT="${1:-}"; case "$SEAT" in ""|--*) echo "$USAGE" >&2; exit 2;; esac
shift; DRY=0; WT=""; ORPH=0
while [ $# -gt 0 ]; do case "$1" in --dry-run) DRY=1; shift;; --orphans-only) ORPH=1; shift;; --wt) WT="${2:-}"; [ -n "$WT" ] || { echo "$USAGE" >&2; exit 2; }; shift 2;; *) echo "$USAGE" >&2; exit 2;; esac; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
exec python3 - "$SEAT" "$DRY" "$WT" "$ORPH" "$HERE/ft-leak-reap.sh" <<'PY'
import ast, os, re, signal, subprocess, sys, time
seat, dry, wt_arg, orph, leak = sys.argv[1], sys.argv[2] == "1", sys.argv[3], sys.argv[4] == "1", sys.argv[5]
LINUX = sys.platform.startswith("linux")
def die(msg):
    print(f"ft-seat-reap: ERROR {msg}", file=sys.stderr); print(f"reap {seat} stopped=0 left=? rc=20"); sys.exit(20)
def run(cmd, ok_err=()):
    try: r = subprocess.run(cmd, capture_output=True, text=True, timeout=7, env={**os.environ, "LC_ALL": "C"})
    except (OSError, subprocess.SubprocessError) as e: die(f"{cmd[0]} 실행 실패: {e}")
    if r.returncode != 0 and not any(s in r.stderr for s in ok_err): die(f"{cmd[0]} rc={r.returncode}: {r.stderr.strip()[:80]}")
    return r.stdout if r.returncode == 0 else ""
try: PROTECT = ast.literal_eval(re.search(r"^PROTECT_EXE = (\{.*\})$", open(leak, encoding="utf-8").read(), re.M).group(1))
except (OSError, AttributeError, ValueError, SyntaxError) as e: die(f"보호 목록을 못 읽음 {leak}: {e}")
SERVICE_RE = r"\b(uvicorn|gunicorn|hypercorn)\b|-m (worker|gateway)\b|\bnext (dev|start)\b|next-server|run\.command"
try: SVC = re.compile(os.environ.get("FT_REAP_SERVICE_RE") or SERVICE_RE)
except re.error as e: die(f"FT_REAP_SERVICE_RE 정규식 오류: {e}")
def ps_table():   # pid → (ppid, pgid, uid, lstart, cmd, ft_seat|None)
    t = {}
    for ln in run(["ps", "-axww", "-o", "pid=,ppid=,pgid=,uid=,lstart=,command="]).splitlines():
        f = ln.split(None, 9)
        if len(f) < 10 or not f[0].isdigit(): continue
        t[int(f[0])] = [int(f[1]), int(f[2]), int(f[3]), " ".join(f[4:9]), f[9], None]
    if not t: die("ps 표가 비어 있음")
    for pid, row in t.items():
        if LINUX:
            try: env = open(f"/proc/{pid}/environ", "rb").read().decode("utf-8", "replace").split("\0")
            except OSError: continue
            row[5] = next((e[8:] for e in env if e.startswith("FT_SEAT=")), None)
    if not LINUX:   # macOS: -E 는 command 뒤에 env 를 붙인다 — 앞의 command 를 떼고 env 부분에서만 찾는다(인자 속 글자 오인 0)
        for ln in run(["ps", "-axEww", "-o", "pid=,command="]).splitlines():
            f = ln.strip().split(None, 1)
            if len(f) < 2 or not f[0].isdigit() or int(f[0]) not in t: continue
            c = t[int(f[0])][4]; env = f[1][len(c):] if f[1].startswith(c) else ""
            m = re.findall(r"(?:^|\s)FT_SEAT=(\S+)", env)
            if m: t[int(f[0])][5] = m[-1]
    return t
def panes():   # [(세션, pane_pid, 현재 경로, 세션 경로)] — tmux 서버 없음 = 빈 목록
    out = run(["tmux", "list-panes", "-a", "-F", "#{session_name}\t#{pane_pid}\t#{pane_current_path}\t#{session_path}"], ok_err=("no server running", "error connecting", "No such file"))
    return [l.split("\t") for l in out.splitlines() if l.count("\t") == 3 and l.split("\t")[1].isdigit()]
def cwds():
    if LINUX:
        r = {}
        for d in os.listdir("/proc"):
            if d.isdigit():
                try: r[int(d)] = os.readlink(f"/proc/{d}/cwd")
                except OSError: pass
        return r
    try: o = subprocess.run(["lsof", "-a", "-d", "cwd", "-Fpn", "-u", str(os.getuid())], capture_output=True, text=True, timeout=7)
    except (OSError, subprocess.SubprocessError) as e: die(f"lsof 실행 실패: {e}")
    if not o.stdout.strip(): die(f"lsof cwd 표가 비어 있음 rc={o.returncode}: {o.stderr.strip()[:80]}")   # rc 1 = 일부 프로세스 못 읽음(표는 있음)
    r, pid = {}, None
    for ln in o.stdout.splitlines():
        if ln[:1] == "p": pid = int(ln[1:])
        elif ln[:1] == "n" and pid: r[pid] = ln[1:]
    return r
def desc(t, roots):
    kids = {}
    for p, row in t.items(): kids.setdefault(row[0], []).append(p)
    out, st = set(), list(roots)
    while st:
        for k in kids.get(st.pop(), []):
            if k not in out: out.add(k); st.append(k)
    return out
def services(t):   # pid → why — 서비스 나무(r505): ⓐLISTEN 을 쥔 프로세스 + 조상 + 자손 ⓑ서비스 명령 꼴 + 자손
    try: o = subprocess.run(["lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-Fp"], capture_output=True, text=True, timeout=7, env={**os.environ, "LC_ALL": "C"})
    except (OSError, subprocess.SubprocessError) as e: die(f"lsof LISTEN 실행 실패: {e}")
    lis = {int(l[1:]) for l in o.stdout.splitlines() if l[:1] == "p" and l[1:].isdigit()}
    if o.returncode != 0 and not lis and (o.returncode != 1 or o.stderr.strip()): die(f"lsof LISTEN rc={o.returncode}: {o.stderr.strip()[:80]}")   # rc 1 + stderr 0 = LISTEN 0
    up = set()
    for p in lis:
        while p in t and p > 1 and p not in up: up.add(p); p = t[p][0]
    why = {p: "service-listen" for p in up | desc(t, lis)}
    cmd = {p for p, r in t.items() if SVC.search(r[4])}
    for p in cmd | desc(t, cmd): why.setdefault(p, "service-cmd")
    return why
def inside(p, top): return p == top or p.startswith(top.rstrip("/") + "/")
def own_wt(p, top):   # cwd 와 top 사이에 다른 `.git` 이 있으면 안쪽 다른 워크트리 — 이 좌석 것 아님
    while inside(p, top) and p != top:
        if os.path.exists(os.path.join(p, ".git")): return False
        p = os.path.dirname(p)
    return p == top
def survey():
    t, pl, me, anc = ps_table(), panes(), os.getuid(), set()
    p = os.getpid()
    while p in t and p not in anc and p > 1: anc.add(p); p = t[p][0]
    mine = [int(x[1]) for x in pl if x[0] == seat]
    other = desc(t, [int(x[1]) for x in pl if x[0] != seat]) | {int(x[1]) for x in pl if x[0] != seat}
    wt = wt_arg or next((x[3] for x in pl if x[0] == seat), "")
    wt = os.path.realpath(wt) if wt and os.path.exists(os.path.join(wt, ".git")) and os.path.realpath(wt) not in ("/", os.path.realpath(os.path.expanduser("~"))) else ""
    shared = bool(wt) and any(x[0] != seat and (inside(os.path.realpath(x[2]), wt) or inside(os.path.realpath(x[3]), wt)) for x in pl)
    cw = cwds() if wt and not shared else {}
    bg = {p for p, r in t.items() if re.search(r"ft-bg-loop\.sh .*--seat " + re.escape(seat) + r"(\s|$)", r[4])}
    cand, tree, svc, skip = {}, desc(t, mine), services(t), {}
    for pid, (ppid, pgid, uid, lst, cmd, fs) in t.items():
        if uid != me or pid in anc or pid in mine or (orph and ppid != 1): continue
        if fs is not None and fs != seat and pid not in bg: continue   # 남의 좌석(래퍼 argv --seat 가 env 보다 우선 — 래퍼는 띄운 좌석의 env 를 물려받는다)
        exe = os.path.basename(cmd.split()[0]) if cmd.split() else ""
        if exe in PROTECT: continue
        via = ("①" if pid in tree else "②" if fs == seat else "②b" if pid in bg else
               "③" if fs is None and ppid == 1 and pid not in other and pid in cw and own_wt(os.path.realpath(cw[pid]), wt) and re.search(r"\b(sleep|while)\b", cmd) else "")
        if via and pid in svc: skip[pid] = (svc[pid], cmd)
        elif via: cand[pid] = (via, lst, cmd)
    for pid in desc(t, list(cand)) - set(cand) - anc:   # 후보의 자식(env 를 못 읽는 sleep 등)도 같은 주인
        r = t[pid]
        if r[2] == me and (r[5] is None or r[5] == seat) and os.path.basename((r[4].split() or [""])[0]) not in PROTECT:
            if pid in svc: skip[pid] = (svc[pid], r[4])
            else: cand[pid] = ("자손", r[3], r[4])
    return cand, t, shared, skip
cand, _, shared, skip = survey()
for p, (w, c) in sorted(skip.items()): print(f"reap-skip pid={p} why={w} cmd={c[:100]}")
tail = " cwd=shared" if shared else ""
if dry:
    for p, (v, _, c) in sorted(cand.items()): print(f"reap-cand pid={p} via={v} cmd={c[:100]}")
    print(f"reap {seat} found={len(cand)} dry-run rc=0{tail}"); sys.exit(0)
NOSIG = os.environ.get("FT_REAP_NOSIGNAL") == "1"
def sig(p, s):
    if NOSIG: return
    try: os.kill(p, s)
    except ProcessLookupError: pass
    except PermissionError: print(f"ft-seat-reap: WARN pid={p} 신호 권한 없음", file=sys.stderr)
def alive(ps): return [p for p in ps if subprocess.run(["kill", "-0", str(p)], capture_output=True).returncode == 0]
def stop(cand):
    for p, (v, _, c) in sorted(cand.items()): print(f"reap-kill pid={p} via={v} cmd={c[:100]}"); sig(p, signal.SIGTERM)
    end = time.time() + 3
    while alive(cand) and time.time() < end: time.sleep(0.1)
    left0 = alive(cand)
    if left0:
        t = ps_table()
        for p in left0:
            if p in t and t[p][3] == cand[p][1]: sig(p, signal.SIGKILL)   # 시작 시각이 같을 때만(pid 재사용 오살 0)
        end = time.time() + 1
        while alive(left0) and time.time() < end: time.sleep(0.1)
seen, again = set(), cand
for _ in range(2):   # 2회전 — 1회전 사이에 새로 드러난 것(부모를 잃은 자식 등)까지
    if not again: break
    seen |= {p for p, x in again.items() if x[0] != "자손"}; stop(again); again, _, _, _ = survey()
left = sum(1 for x in again.values() if x[0] != "자손"); rc = 1 if left else 0
for p, (v, _, c) in sorted(again.items()): print(f"reap-left pid={p} via={v} cmd={c[:100]}")
print(f"reap {seat} stopped={len(seen - set(again))} left={left} rc={rc}{tail}"); sys.exit(rc)   # stopped = 뿌리 수(자손 sleep 등은 reap-kill 줄에만)
PY
