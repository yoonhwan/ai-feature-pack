#!/usr/bin/env bash
# ft-seat-quiesce.sh <좌석> --mode close|done|handover [--to <후계>] [--reason <머리>] [--dry-run]   (r1113 · 판정 2769·2770)
#   좌석 pane_pid 밑 프로세스 나무(ppid 체인 · pane pid 자신 = 에이전트 본체는 늘 제외 · 본체 종료는 kill-session 몫)를 세고 내린다.
#   close    = 나무 전부(node·zsh·LSP·dev 서버·크롬·pi·uvx serena · RSS 무관) · 오빠 «세션 닫을 때 무조건 강제» · ft-nano-close 가 kill-session 앞에 부른다
#   done     = «무거운 자식» 만 — 이름 집합(HEAVY_*) ∪ RSS ≥ FT_QUIESCE_RSS_MB(200) · 에이전트·셸(AGENT_EXE)·git·gh(KEEP_EXE)는 절대 대상 아님
#              + state/handover/<좌석>.tsv(옛 좌석이 넘긴 표 · lstart 같은 pid 만) · press 진행 중 = 건너뜀 1줄(term=0)
#   handover = kill 0 · 나무 표를 state/handover/<후계>.tsv 에 적는다(오빠 «증류할때는 인계가능») · 후계의 done 이 그 표를 내린다
#   --orphans (좌석 대신) = ppid 1 ∧ 내 uid ∧ 이름 집합(LSP·probe lsp·uvx serena·next dev — 크롬·RSS 규칙 0) ∧ launchd 목록 밖 · --survey = 조회 표(S 좌석 줄 · P 프로세스 줄 · 신호 0)
#   보호(모든 모드): --remote-debugging-port=9333 크롬과 그 자손 · launchctl list 의 pid(kill 0 · `quiesce-keep … why=launchd`) · 이 명령 자신·조상·자손
#   정지: TERM → 최대 FT_QUIESCE_WAIT_SEC(7)초 폴링 → 남은 것 KILL(lstart 같을 때만) → 최대 2초 → 다시 셈
#   출력 끝 2줄: `QUIESCED <좌석> mode=<m> before=<MB> after=<MB> term=<n> kill=<n> left=<n>` · `남은 자식|남은 대상 <n>[ <pid> <이름>…]`
#   rc 0 = left 0 · 1 = left>0 (닫기 도구가 CLOSE-FAIL) · 2 = usage · 20 = 판정 불가(ps·tmux·launchctl 실패 → 1줄 · 신호 0 · 하드 룰 20)
#   장부 <state>/quiesce.log · state = FT_QUIESCE_STATE_DIR 또는 <데이터 루트>/.fable-team/state · 외부 호출 각 7초 상한
#   시험: FT_PS·FT_TMUX·FT_LAUNCHCTL = 스텁 스크립트 · FT_QUIESCE_RSS_TSV(pid<TAB>MB) · FT_QUIESCE_NOSIGNAL=<pid,…>(신호 0 = 못 내린 프로세스 재현) · FT_PERMIT_DIR
set -uo pipefail
USAGE="usage: $0 <좌석> --mode close|done|handover [--to <후계>] [--reason <머리>] [--dry-run] | $0 --orphans [--dry-run] | $0 --survey"
SEAT=""; MODE=""; TO=""; REASON=""; DRY=0
case "${1:-}" in --orphans) MODE=orphans; shift;; --survey) MODE=survey; shift;; ""|--*) echo "$USAGE" >&2; exit 2;; *) SEAT="$1"; shift;; esac
while [ $# -gt 0 ]; do case "$1" in
  --mode) MODE="${2:-}"; shift 2;; --to) TO="${2:-}"; shift 2;;
  --reason) REASON="${2:-}"; shift 2;; --dry-run) DRY=1; shift;; *) echo "$USAGE" >&2; exit 2;; esac; done
case "$MODE" in close|done) [ -n "$SEAT" ];; handover) [ -n "$SEAT" ] && [ -n "$TO" ];; orphans|survey) [ -z "$SEAT" ];; *) false;; esac || { echo "$USAGE" >&2; exit 2; }
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SD="${FT_QUIESCE_STATE_DIR:-}"; PD="${FT_PERMIT_DIR:-}"
if [ -z "$SD" ] || [ -z "$PD" ]; then DR="$(. "$HERE/ft-harness-root.sh" && ft_data_root "$HERE" 2>/dev/null)" || DR=""; SD="${SD:-${DR:+$DR/.fable-team/state}}"; PD="${PD:-${DR:+$DR/.fable-team/state/permits}}"; fi
exec python3 - "$SEAT" "$MODE" "$TO" "$REASON" "$DRY" "$SD" "$PD" <<'PY'
import calendar, json, os, re, signal, subprocess, sys, time
seat, mode, to, reason, dry, sdir, pdir = sys.argv[1:8]; dry = dry == "1"
ME = os.getuid()
AGENT_EXE = {"claude", "codex", "pi", "opencode", "cursor-agent", "gemini", "tmux", "zsh", "bash", "sh", "fish", "login"}
SHELL_EXE = {"zsh", "bash", "sh", "fish"}
AGENT_CMD = re.compile(r"@anthropic-ai/claude-code|@openai/codex|cursor-agent|--dangerously-skip-permissions|(^|[/ ])(claude|codex|gemini|opencode|pi)( |$)")   # 런타임(node·bun) 꼴 에이전트 본체
KEEP_EXE = {"git", "gh"}   # done·고아 대상 아님 — 도는 중에 죽이면 .git/index.lock 이 남는다(10-29 실측 ops master 밑 git 258MB · close 는 그대로 전부)
RUNTIME_EXE = {"node", "bun", "deno", "python", "python3", "uv"}   # 이름 = 스크립트(첫 비옵션 인자) 이름
HEAVY_NAME = {"basedpyright", "basedpyright-langserver", "pyright", "pyright-langserver", "tsserver", "typingsInstaller",
              "typescript-language-server", "lsp-daemon", "next-server", "vite", "webpack", "serena", "serena-mcp-server"}
ORPHAN_CMD = re.compile(r"\bnext dev\b|\buvx\b.*\bserena\b|\bprobe lsp\b")   # 고아 = 이름 집합만(크롬·RSS 규칙 0 — ppid 1 크롬은 사람 앱 · 가상머신 647MB 실측 10-29)
HEAVY_CMD = re.compile(r"Google Chrome|" + ORPHAN_CMD.pattern)
KEEP_CDP = re.compile(r"--remote-debugging-port=" + re.escape(os.environ.get("FT_QUIESCE_KEEP_CDP_PORT", "9333")) + r"\b")
PRESS_RE = re.compile(os.environ.get("FT_PRESS_RUNNER_RE") or r"tests/e2e/\S*press\S*\.py|realtime_multi_e2e\.py")
RSS_MB = float(os.environ.get("FT_QUIESCE_RSS_MB") or 200); WAIT = float(os.environ.get("FT_QUIESCE_WAIT_SEC") or 7)
NOSIG = {int(x) for x in (os.environ.get("FT_QUIESCE_NOSIGNAL") or "").split(",") if x.strip().isdigit()}
def tool(env, name): return ["bash", os.environ[env]] if os.environ.get(env) else [name]
class Unknown(Exception): pass
def run(cmd, ok_err=(), rc1_empty=False):   # rc1_empty = rc 1 + stderr 0 은 «없음»(ps -p 에 죽은 pid 만)
    try: r = subprocess.run(cmd, capture_output=True, text=True, timeout=7, env={**os.environ, "LC_ALL": "C", "TZ": "UTC"})
    except (OSError, subprocess.SubprocessError) as e: raise Unknown(f"{cmd[-1] if cmd[0] == 'bash' else cmd[0]} 실행 실패: {e}")
    if r.returncode != 0 and not any(s in r.stderr for s in ok_err) and not (rc1_empty and r.returncode == 1 and not r.stderr.strip()): raise Unknown(f"{' '.join(cmd[:2])} rc={r.returncode}: {r.stderr.strip()[:80]}")
    return r.stdout if r.returncode == 0 else ""
def name_of(cmd):
    tok = cmd.split()
    if not tok: return ""
    exe = os.path.basename(tok[0]).lstrip("-")
    if exe in RUNTIME_EXE: exe = next((re.sub(r"\.(c|m)?js$", "", os.path.basename(a)) for a in tok[1:] if not a.startswith("-") and not a.isdigit()), exe)
    return exe
def ps_table():   # pid → dict(ppid uid rss(MB) cpu lstart epoch cmd name)
    rss = {}
    if os.environ.get("FT_QUIESCE_RSS_TSV"):
        for ln in open(os.environ["FT_QUIESCE_RSS_TSV"], encoding="utf-8"):
            f = ln.split("\t")
            if len(f) >= 2 and f[0].strip().isdigit(): rss[int(f[0])] = float(f[1])
    t = {}
    for ln in run(tool("FT_PS", "ps") + ["-axww", "-o", "pid=,ppid=,pgid=,uid=,rss=,%cpu=,lstart=,command="]).splitlines():
        f = ln.split(None, 11)
        if len(f) < 12 or not f[0].isdigit(): continue
        ls = " ".join(f[6:11])
        try: ep = calendar.timegm(time.strptime(ls, "%a %b %d %H:%M:%S %Y"))
        except ValueError: ep = None
        pid = int(f[0]); t[pid] = dict(ppid=int(f[1]), pgid=int(f[2]), uid=int(f[3]), rss=rss.get(pid, int(f[4]) / 1024), cpu=f[5], lstart=ls, epoch=ep, cmd=f[11], name=name_of(f[11]))
    if not t: raise Unknown("ps 표가 비어 있음")
    return t
def panes():   # [(세션, pane_pid, window_activity)] — tmux 서버 없음 = 빈 목록
    out = run(tool("FT_TMUX", "tmux") + ["list-panes", "-a", "-F", "#{session_name}\t#{pane_pid}\t#{window_activity}"], ok_err=("no server running", "error connecting", "No such file"))
    return [(f[0], int(f[1]), int(f[2]) if f[2].isdigit() else 0) for f in (l.split("\t") for l in out.splitlines()) if len(f) == 3 and f[1].isdigit()]
_ld = []
def launchd():
    if not _ld: _ld.append({int(f[0]) for f in (l.split() for l in run(tool("FT_LAUNCHCTL", "launchctl") + ["list"]).splitlines()[1:]) if f and f[0].isdigit()})
    return _ld[0]
def kids_of(t):
    k = {}
    for p, r in t.items(): k.setdefault(r["ppid"], []).append(p)
    return k
def desc(t, roots, kids=None):
    kids, out, st = kids or kids_of(t), set(), list(roots)
    while st:
        for c in kids.get(st.pop(), []):
            if c not in out: out.add(c); st.append(c)
    return out
def protected(t, kids):   # 이 명령 자신·조상·자손 + 9333 크롬 나무
    me, anc = os.getpid(), set()
    p = me
    while p in t and p > 1 and p not in anc: anc.add(p); p = t[p]["ppid"]
    cdp = {p for p, r in t.items() if KEEP_CDP.search(r["cmd"])}
    return anc | desc(t, [me], kids) | cdp | desc(t, cdp, kids)
def agent(r): return r["name"] in AGENT_EXE or bool(AGENT_CMD.search(r["cmd"][:300]))   # DA① 1 — node …/claude-code/cli.js 같은 런타임 꼴 본체도 보호
def heavy(r): return not agent(r) and r["name"] not in KEEP_EXE and (r["name"] in HEAVY_NAME or bool(HEAVY_CMD.search(r["cmd"])) or r["rss"] >= RSS_MB)
def orphan(p, r): return r["ppid"] == 1 and r["uid"] == ME and not agent(r) and r["name"] not in KEEP_EXE and (r["name"] in HEAVY_NAME or bool(ORPHAN_CMD.search(r["cmd"])))
def busy(t, pids): return sorted(p for p in pids if t[p]["name"] in SHELL_EXE and " -c " in f" {t[p]['cmd']} ")   # 작업 중 신호 = 도구 셸(sh -c …) 실행 중
def press():   # r690 꼴 — 내 uid 의 python 이 press 러너를 실행 중 ∨ 장치 허가 device.json held=true
    for p, r in T.items():
        tok = r["cmd"].split()
        if r["uid"] == ME and tok and re.match(r"(?i)python[0-9.]*$", os.path.basename(tok[0])) and any(PRESS_RE.search(a) for a in tok[1:3]): return f"runner:{p}"
    dev = os.path.join(pdir, "device.json") if pdir else ""
    if dev and os.path.exists(dev):
        try: return "device-held" if json.load(open(dev, encoding="utf-8")).get("held") is True else ""
        except (OSError, ValueError, AttributeError): return "device-unreadable"
    return ""
def log(line):
    if not sdir: return
    try:
        os.makedirs(sdir, exist_ok=True)
        with open(os.path.join(sdir, "quiesce.log"), "a", encoding="utf-8") as f: f.write(time.strftime("%Y-%m-%dT%H:%M:%S ") + line + "\n")
    except OSError as e: print(f"ft-seat-quiesce: WARN 장부 못 씀: {e}", file=sys.stderr)
def hpath(name): return os.path.join(sdir, "handover", f"{name}.tsv") if sdir else ""
def inherited(name):   # DA① 5 — 옛 좌석이 넘긴 표(pid·lstart·이름·MB·옛 좌석) 중 lstart 같은 살아 있는 pid → {pid: 행}
    p = hpath(name)
    if not p or not os.path.exists(p): return {}
    rows = [l.rstrip("\n").split("\t") for l in open(p, encoding="utf-8") if l.count("\t") >= 4]
    return {int(r[0]): r for r in rows if r[0].isdigit() and int(r[0]) in T and T[int(r[0])]["lstart"] == r[1]}
def write_table(name, rows):   # rows = [행] · 빈 목록 = 표 지움
    p = hpath(name)
    if not p: raise Unknown("state 폴더를 못 풂(FT_QUIESCE_STATE_DIR · 데이터 루트)")
    if not rows:
        if os.path.exists(p): os.remove(p)
        return p
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p + f".tmp{os.getpid()}", "w", encoding="utf-8") as f: f.write("".join("\t".join(r) + "\n" for r in rows))
    os.replace(p + f".tmp{os.getpid()}", p); return p
def alive(pids):   # 살아 있음 = ps 에 있고 상태가 Z(좀비 = 이미 죽어 부모가 거두기만 남음)가 아님 · NOSIG = 시험 전용 «못 내림»
    pids = list(pids)
    if not pids: return []
    st = {int(f[0]): f[1] for f in (l.split() for l in run(tool("FT_PS", "ps") + ["-o", "pid=,stat=", "-p", ",".join(map(str, pids))], rc1_empty=True).splitlines()) if len(f) == 2 and f[0].isdigit()}
    return [p for p in pids if p in NOSIG or (p in st and not st[p].startswith("Z"))]
def sig(p, s):
    if p in NOSIG: return
    try: os.kill(p, s)
    except ProcessLookupError: pass
    except PermissionError: print(f"ft-seat-quiesce: WARN pid={p} 신호 권한 없음", file=sys.stderr)
def same(now, cand, p): return p in NOSIG or (p in now and now[p]["lstart"] == cand[p]["lstart"])   # pid 재사용 = 다른 프로세스 → 신호 0
def stop(cand):   # TERM(직전 lstart 대조 · DA① 2) → 폴링 → KILL(lstart 대조) → 폴링 · (kill 수, 남은 pid)
    now = ps_table()
    for p in sorted(cand):
        if same(now, cand, p): sig(p, signal.SIGTERM)
    end = time.time() + WAIT
    while alive(cand) and time.time() < end: time.sleep(0.1)
    left = [p for p in alive(cand) if same(ps_table(), cand, p)] if alive(cand) else []
    now = ps_table() if left else {}
    for p in left:
        if same(now, cand, p): sig(p, signal.SIGKILL)
    end = time.time() + 2
    while alive(left) and time.time() < end: time.sleep(0.1)
    return len(left), [p for p in alive(left) if p in NOSIG or same(ps_table(), cand, p)]
def mb(rows): return int(round(sum(r["rss"] for r in rows)))
def survey(pl):
    kids, now = kids_of(T), time.time(); prot = protected(T, kids); own = {}
    for s, pp, act in pl:
        o = own.setdefault(s, {"idle": None, "pids": set()}); o["pids"] |= desc(T, [pp], kids) - prot
        if act: o["idle"] = min(o["idle"] if o["idle"] is not None else 10**9, int((now - act) // 60))   # 창 여러 개 = 가장 최근 출력
    orph = {p for p, r in T.items() if orphan(p, r) and p not in prot}
    lp = launchd() if orph else set(); orph -= lp
    for s, o in sorted(own.items()):
        rs = sorted((T[p] | {"pid": p} for p in o["pids"]), key=lambda r: -r["rss"])
        age = max((int((now - r["epoch"]) // 60) for r in rs if r["epoch"]), default=0)
        top = ",".join(f"{r['name']}:{int(r['rss'])}" for r in [r for r in rs if heavy(r)][:3]) or "-"
        print(f"S\t{s}\t{o['idle'] if o['idle'] is not None else '?'}\t{mb(rs)}\t{mb([r for r in rs if heavy(r)])}\t{len(rs)}\t{age}\t{top}\t{len(busy(T, o['pids']))}")
        for r in rs: print(f"P\t{s}\t{r['pid']}\t{r['name']}\t{int(r['rss'])}\t{r['cpu']}\t{int((now - r['epoch']) // 60) if r['epoch'] else '?'}\t{int(heavy(r))}\t{r['cmd'][:80]}")
    for p in sorted(orph): r = T[p]; print(f"P\t-\t{p}\t{r['name']}\t{int(r['rss'])}\t{r['cpu']}\t{int((now - r['epoch']) // 60) if r['epoch'] else '?'}\t1\t{r['cmd'][:80]}")
    return 0
def targets(t, roots, inh):   # 모드별 후보(보호 전) — 좌석 나무 ∪ 넘겨받은 표
    tree = desc(t, roots) - set(roots)
    if mode == "orphans": return {p for p, r in t.items() if orphan(p, r)}
    if mode == "close": return tree | set(inh)
    return {p for p in tree | set(inh) if heavy(t[p])}
def guard(t, cand, scope):   # 보호 빼기 — 자기·9333 + launchd 등록 pid «와 그 하위 나무 전체»(DA① 4 · 등록 pid 는 좌석 나무·후보 안에서만 찾는다) · (남은 후보, 보호 줄)
    cand = {p for p in cand - protected(t, kids_of(t)) if t[p]["uid"] == ME}
    lp = launchd() & (cand | scope) if cand else set()
    keep = lp | desc(t, lp)
    return cand - keep, [f"quiesce-keep pid={p} why=launchd name={t[p]['name']} subtree={len(desc(t, [p]) & cand)}" for p in sorted(lp & (cand | keep))]
def main():
    global T
    T = ps_table(); pl = panes(); t0 = time.time()
    if mode == "survey": return survey(pl)
    label = seat or "orphans"; roots = [pp for s, pp, _ in pl if s == seat]
    inh = inherited(seat) if seat else {}
    if mode == "handover":   # 나무 ∪ 내가 넘겨받은 표 → 후계 표 · 내 표는 지움(책임 이동 · DA① 5)
        tree = desc(T, roots) - set(roots) - protected(T, kids_of(T))
        rows = [[str(p), T[p]["lstart"], T[p]["name"], str(int(T[p]["rss"])), seat] for p in sorted(tree)] + [r for p, r in sorted(inh.items()) if p not in tree]
        if not rows and not inh: print(f"HANDOVER {seat} -> {to} rows=0 mb=0 (넘길 자식 0 · 표 0)"); return 0
        hp = hpath(to)
        if not dry:
            prev = {r[0]: r for r in (inherited(to) or {}).values()}   # 후계가 이미 받은 줄 보존
            write_table(to, list({**prev, **{r[0]: r for r in rows}}.values())); write_table(seat, [])
        print(f"HANDOVER {seat} -> {to} rows={len(rows)} inherited={len(inh)} mb={sum(int(r[3]) for r in rows)} file={hp}"); log(f"HANDOVER {seat} -> {to} rows={len(rows)}"); return 0
    if mode == "done" and (pr := press()):
        print(f"QUIESCE-SKIP {seat} mode=done why=press-active by={pr} term=0"); log(f"SKIP {seat} press {pr}"); return 0
    cand, keeps = guard(T, targets(T, roots, inh), desc(T, roots) - set(roots))
    for k in keeps: print(k)
    before = mb([T[p] for p in (desc(T, roots) - set(roots)) | cand])
    cand = {p: T[p] for p in sorted(cand)}
    for p, r in cand.items(): print(f"quiesce-{'cand' if dry else 'stop'} pid={p} name={r['name']} rss={int(r['rss'])}MB")
    nk, left, extra = 0, [], {}
    if cand and not dry:
        nk, left = stop(cand)
        T2 = ps_table(); pg = {r["pgid"] for r in cand.values()}   # DA① 3 — 종료 뒤 재조회: 나무에 새로 생긴 것 ∪ 후보 프로세스 묶음에서 시작 뒤 새로 생긴 고아
        fresh = {p for p, r in T2.items() if r["ppid"] == 1 and r["uid"] == ME and r["pgid"] in pg and r["epoch"] and r["epoch"] >= int(t0) and (mode == "close" or heavy(r))}
        extra, keeps2 = guard(T2, (targets(T2, roots, {}) | fresh) - set(cand), desc(T2, roots) - set(roots))
        for k in keeps2: print(k)
        extra = {p: T2[p] for p in sorted(extra)}
        for p, r in extra.items(): print(f"quiesce-stop-new pid={p} name={r['name']} rss={int(r['rss'])}MB")
        if extra: k2, l2 = stop(extra); nk += k2; left += l2
    allc = {**cand, **extra}
    after = before - (0 if dry else mb([r for p, r in cand.items() if p not in left]))
    if inh and not dry: write_table(seat, [r for p, r in inh.items() if p in alive([p])])   # 넘겨받은 표 = 살아 있는 줄만 남김
    word = "남은 자식" if mode == "close" else "남은 대상"
    summ = f"QUIESCED {label} mode={mode} before={before} after={after} term={0 if dry else len(allc)} kill={nk} left={len(left)} new={len(extra)}" + (" dry-run" if dry else "") + (f" reason={reason}" if reason else "")
    print(summ); print(f"{word} {len(left)}" + "".join(f" {p} {allc[p]['name']}" for p in left)); log(summ)
    return 1 if left else 0
try: sys.exit(main())
except Unknown as e:
    print(f"QUIESCE-UNKNOWN {seat or mode} 판정 불가 — {e} (신호 0)"); log(f"UNKNOWN {seat or mode} {e}"); sys.exit(20)
PY
