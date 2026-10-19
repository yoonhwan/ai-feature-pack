#!/usr/bin/env bash
# ft-opencode-reap.sh <좌석> [--wt <워크트리>] [--record [--since <epoch>]] [--apply]  |  --pid-file <F> [--apply] — opencode 는 쓰면 매번 완전히 닫는다 (r286 · 판정 2035 · 하드 룰 14)
#   대상(내 uid 만 · 이 명령 자신과 조상 제외 · 다른 tmux 세션 pane 나무 제외):
#     ①tmux 세션 =<좌석> pane 나무(pane pid 포함) 안의 opencode   ③ppid 1(부모 잃음) ∧ opencode ∧ cwd ⊂ --wt(안쪽 다른 워크트리 제외)
#     기록=pid 파일(<상태>/<좌석>.pids · 탭 3칸 pid·lstart·via) 의 pid 중 시작 시각(lstart)이 같은 것만(pid 재사용 오살 0)
#     new=--record 때만: ppid 1 ∧ opencode ∧ --since 이후 시작(스폰이 띄운 serve) — 닫을 때 «다른 opencode» 가 살아 있으면 공유로 보고 건너뛴다(oc-skip)
#     위 대상의 자손 전부(serve 가 띄운 MCP·LSP 등)
#   --record = 대상을 pid 파일에 합쳐 쓴다(kill 0 · 스폰 직후·닫기 앞) · 인자 없음 = 조사만(oc-cand 줄) · --apply = TERM → 3 s → (같은 lstart 만) KILL → 1 s → 재조사 2회전
#   출력 끝 줄: `REAPED <좌석> n=<멈춘 수> left=<남은 수> rc=<n>` · rc 0 = left 0 · 1 = left>0 · 2 = usage · 20 = 조사 실패(ps·lsof·tmux 못 읽음 · left=?)
#   상태 폴더 = FT_OC_STATE_DIR(기본 ~/.claude/state/opencode) · 가짜 tmux = FT_TMUX_BIN(시험) · 외부 호출 각 7 s 상한 · 남의 opencode(다른 부모·다른 cwd) 0.
set -uo pipefail
USAGE="usage: $0 <좌석> [--wt <워크트리>] [--record [--since <epoch>]] [--apply] | --pid-file <F> [--apply]"
SEAT=""; PF=""; WT=""; MODE=survey; SINCE=""
case "${1:-}" in ""|--wt|--record|--since|--apply) echo "$USAGE" >&2; exit 2;; --pid-file) PF="${2:-}"; [ -n "$PF" ] || { echo "$USAGE" >&2; exit 2; }; shift 2;; *) SEAT="$1"; shift;; esac
while [ $# -gt 0 ]; do case "$1" in
  --wt) WT="${2:-}"; [ -n "$WT" ] || { echo "$USAGE" >&2; exit 2; }; shift 2;; --since) SINCE="${2:-}"; [[ "$SINCE" =~ ^[0-9]+$ ]] || { echo "$USAGE" >&2; exit 2; }; shift 2;;
  --record) MODE=record; shift;; --apply) MODE=apply; shift;; *) echo "$USAGE" >&2; exit 2;; esac; done
[ -z "$PF" ] || [ "$MODE" != record ] || { echo "$USAGE (--pid-file 는 --record 불가)" >&2; exit 2; }
STATE="${FT_OC_STATE_DIR:-$HOME/.claude/state/opencode}"
[ -n "$PF" ] || PF="$STATE/$(printf '%s' "$SEAT" | tr -c 'A-Za-z0-9._#-' '_').pids"
exec python3 - "$SEAT" "$PF" "$WT" "$MODE" "$SINCE" "${FT_TMUX_BIN:-tmux}" <<'PY'
import os, signal, subprocess, sys, time
seat, pf, wt_arg, mode, since, tmux = sys.argv[1:7]
LINUX, ME, LBL = sys.platform.startswith("linux"), os.getuid(), seat or os.path.basename(pf)
OC = {"opencode", ".opencode", "opencode-ai"}; SH = {"bash", "sh", "zsh", "node", "bun", "env"}
def die(msg): print(f"ft-opencode-reap: ERROR {msg}", file=sys.stderr); print(f"REAPED {LBL} n=0 left=? rc=20"); sys.exit(20)
def run(cmd, ok_err=()):
    try: r = subprocess.run(cmd, capture_output=True, text=True, timeout=7, env={**os.environ, "LC_ALL": "C"})
    except (OSError, subprocess.SubprocessError) as e: die(f"{cmd[0]} 실행 실패: {e}")
    if r.returncode != 0 and not any(s in r.stderr + r.stdout for s in ok_err): die(f"{cmd[0]} rc={r.returncode}: {r.stderr.strip()[:80]}")
    return r.stdout if r.returncode == 0 else ""
def is_oc(cmd):   # argv[0] 이 opencode · 또는 셸·node 가 opencode 스크립트를 돌림(시험 스텁 꼴)
    w = cmd.split()[:2]; b = os.path.basename(w[0]) if w else ""
    return b in OC or (b in SH and len(w) > 1 and os.path.basename(w[1]) in OC)
def ps():   # pid → [ppid, uid, lstart, cmd]
    t = {int(f[0]): [int(f[1]), int(f[2]), " ".join(f[3:8]), f[8]] for f in (l.split(None, 8) for l in run(["ps", "-axww", "-o", "pid=,ppid=,uid=,lstart=,command="]).splitlines()) if len(f) >= 9 and f[0].isdigit()}
    return t or die("ps 표가 비어 있음")
def started(lst):
    try: return time.mktime(time.strptime(lst, "%a %b %d %H:%M:%S %Y"))
    except ValueError: return 0
def panes():   # [(세션, pane_pid)] — 서버 없음 = 빈 목록
    out = run([tmux, "list-panes", "-a", "-F", "#{session_name}\t#{pane_pid}"], ok_err=("no server running", "error connecting", "No such file"))
    return [(a, int(b)) for a, b in (l.split("\t", 1) for l in out.splitlines() if "\t" in l) if b.isdigit()]
def cwd_of(pids):
    if not pids: return {}
    if LINUX: return {p: os.readlink(f"/proc/{p}/cwd") for p in pids if os.path.exists(f"/proc/{p}/cwd")}
    try: o = subprocess.run(["lsof", "-a", "-d", "cwd", "-Fpn", "-p", ",".join(map(str, pids))], capture_output=True, text=True, timeout=7)
    except (OSError, subprocess.SubprocessError) as e: die(f"lsof 실행 실패: {e}")
    r, p = {}, None
    for ln in o.stdout.splitlines():
        if ln[:1] == "p": p = int(ln[1:])
        elif ln[:1] == "n" and p: r[p] = ln[1:]
    return r
def desc(t, roots):
    kids, out, st = {}, set(), list(roots)
    for p, row in t.items(): kids.setdefault(row[0], []).append(p)
    while st:
        for k in kids.get(st.pop(), []):
            if k not in out: out.add(k); st.append(k)
    return out
def inside(p, top): return p == top or p.startswith(top.rstrip("/") + "/")
def own_wt(p, top):   # cwd 와 top 사이에 다른 `.git` 이 있으면 안쪽 다른 워크트리 — 이 좌석 것 아님
    while inside(p, top) and p != top:
        if os.path.exists(os.path.join(p, ".git")): return False
        p = os.path.dirname(p)
    return p == top
REC, HDR = {}, ""
try:
    for ln in open(pf, encoding="utf-8"):
        f = ln.rstrip("\n").split("\t")
        if ln.startswith("# since "): HDR = ln.split()[2]
        elif len(f) == 3 and f[0].isdigit(): REC[int(f[0])] = (f[1], f[2])
except FileNotFoundError: pass
except OSError as e: die(f"pid 파일을 못 읽음 {pf}: {e}")
SINCE = int(since or HDR or 0)
def survey():
    t, anc, p = ps(), set(), os.getpid()
    while p in t and p not in anc and p > 1: anc.add(p); p = t[p][0]
    pl = panes() if seat else []
    mine, oth = [q for s, q in pl if s == seat], [q for s, q in pl if s != seat]
    tree, other = desc(t, mine) | set(mine), desc(t, oth) | set(oth)
    wt = os.path.realpath(wt_arg) if wt_arg and os.path.exists(os.path.join(wt_arg, ".git")) else ""
    cw = cwd_of([q for q, r in t.items() if r[0] == 1 and r[1] == ME and is_oc(r[3]) and q not in other]) if wt else {}
    cand = {}
    for q, (pp, uid, lst, cmd) in t.items():
        if uid != ME or q in anc: continue
        if q in REC and REC[q][0] == lst: cand[q] = (REC[q][1], lst, cmd); continue
        if not seat or not is_oc(cmd) or q in other: continue
        via = ("①" if q in tree else "③" if q in cw and own_wt(os.path.realpath(cw[q]), wt) else
               "new" if mode == "record" and SINCE and pp == 1 and started(lst) >= SINCE else "")
        if via: cand[q] = (via, lst, cmd)
    sub = desc(t, list(cand))   # 공유 판정은 자손을 붙이기 «전» — 건너뛴 serve 의 자손(MCP 등)도 같이 남긴다
    rest = [q for q, r in t.items() if r[1] == ME and is_oc(r[3]) and q not in cand and q not in sub and q not in anc]
    for q in [q for q, c in cand.items() if c[0] == "new" and rest and mode == "apply"]:
        print(f"oc-skip pid={q} reason=다른 opencode 살아 있음(공유 serve 가능 · {len(rest)}개) cmd={cand.pop(q)[2][:80]}")
    for q in desc(t, list(cand)) - set(cand) - anc:
        if t[q][1] == ME and q not in other: cand[q] = ("자손", t[q][2], t[q][3])
    return cand
cand = survey()
if mode == "survey":
    for q, (v, _, c) in sorted(cand.items()): print(f"oc-cand pid={q} via={v} cmd={c[:100]}")
    print(f"REAPED {LBL} n=0 left={sum(1 for x in cand.values() if x[0] != '자손')} dry-run rc=0"); sys.exit(0)
if mode == "record":
    os.makedirs(os.path.dirname(pf), exist_ok=True); tmp = f"{pf}.tmp-{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f: f.write(f"# since {SINCE}\n" + "".join(f"{q}\t{lst}\t{v}\n" for q, (v, lst, _) in sorted(cand.items())))
    os.replace(tmp, pf); print(f"oc-record {LBL} n={sum(1 for x in cand.values() if x[0] != '자손')} file={pf}"); sys.exit(0)
NOSIG = os.environ.get("FT_REAP_NOSIGNAL") == "1"   # 시험 전용 — 신호 0(«못 멈춘 프로세스» 재현)
def sig(q, s):
    try: NOSIG or os.kill(q, s)
    except ProcessLookupError: pass
    except PermissionError: print(f"ft-opencode-reap: WARN pid={q} 신호 권한 없음", file=sys.stderr)
def alive(qs): return [q for q in qs if subprocess.run(["kill", "-0", str(q)], capture_output=True).returncode == 0]
def wait(qs, sec):
    end = time.time() + sec
    while alive(qs) and time.time() < end: time.sleep(0.1)
def stop(c):
    for q, (v, _, cmd) in sorted(c.items()): print(f"oc-kill pid={q} via={v} cmd={cmd[:100]}"); sig(q, signal.SIGTERM)
    wait(c, 3); left0, t = alive(c), ps()
    for q in left0:
        if q in t and t[q][2] == c[q][1]: sig(q, signal.SIGKILL)   # 시작 시각이 같을 때만(pid 재사용 오살 0)
    wait(left0, 1)
def roots(c): return {q for q, x in c.items() if x[0] != "자손"}   # 수 = 뿌리(opencode)만 — 자손(sleep·MCP)은 뿌리가 살아 있는 동안만 의미가 있다
seen, again = set(), cand
for _ in range(2):   # 2회전 — 1회전 사이에 부모를 잃고 드러난 것까지
    if not again: break
    seen |= roots(again); stop(again); again = survey()
for q, (v, _, c) in sorted(again.items()): print(f"oc-left pid={q} via={v} cmd={c[:100]}")
left = len(roots(again)); rc = 1 if left else 0
if not left and seat and os.path.exists(pf): os.remove(pf)
print(f"REAPED {LBL} n={len(seen - roots(again))} left={left} rc={rc}"); sys.exit(rc)
PY
