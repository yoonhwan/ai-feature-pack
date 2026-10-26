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
#   --defer-press (r690 · ft-seat-retire — 승계는 일을 잇는 것 · press 관측기를 끊지 않는다): press 진행 중이면 후보를 신호 0 으로 «미룸»
#     press 진행 = 내 uid 의 살아 있는 python*(대소문자 무시 — macOS 프레임워크 빌드는 «Python») 프로세스의 «실행 스크립트»(옵션 뒤 첫 비옵션 토큰 · -c/-m/- = 없음)가
#       FT_PRESS_RUNNER_RE(기본 아래 PRESS_RE)에 맞음 ∨ 장치 허가 device.json held=true · FT_PRESS_PS_SNAPSHOT=<파일>(`pid uid command` 줄) = 시험 전용 ps 표
#       (FT_PERMIT_DIR · 없으면 <데이터 루트>/.fable-team/state/permits · 못 읽는 device.json = 진행으로 봄 + WARN) — 앞 줄 `reap-press-active by=<runner:pid|device-held|device-unreadable>`
#     후보마다 `reap-defer pid=<n> why=press-active cmd=…` · 미룸 파일 FT_REAP_DEFER_DIR(없으면 <데이터 루트>/.fable-team/state/reap-deferred)/<좌석>.jsonl
#       (pid·lstart·cmd·via 한 줄씩 · 못 풀면 rc 20) · 끝 줄 `reap <좌석> stopped=0 left=0 deferred=<n> rc=0` (뿌리 수 · 미룸 아니면 deferred=0)
#   미룸 소화(닫는 사건 · 모든 모드 · dry-run 제외): press 진행 아님이면 미룸 파일 전부를 먼저 읽어 «lstart 같은» 내 pid 만 TERM→KILL(via=⑤미룸)
#     · 다르면(pid 재사용) 신호 0 · 파일마다 ps 표를 새로 읽고 일반 조사와 같은 제외(이 명령 자신·조상 · 보호 exe · 서비스 나무) → `reap-skip … why=self|protect-exe|service-*`
#     · 파일마다 `reap-deferred-done file=<f> stopped=<n> kept=<n>` · kept 0 = 파일 삭제(못 멈춘 행만 남김) · left 에 안 셈
#     · 깨진 줄 = 버리지 않는다: `<f>.broken-<시각>-<pid>` 로 원문 보존 + `reap-deferred-broken file=… lines=<n>`(stdout) + ERROR(stderr) · 읽기 오류 = rc 20
#     · 미룸 폴더를 못 풀면 소화 생략 + stderr WARN 1줄 · lstart 는 LC_ALL=C TZ=UTC 로 잰다(좌석마다 TZ 가 달라도 같은 글자)
#   --handover <후계> (r939 · ft-seat-retire — 승계는 닫기가 아니다): «곧 끝나는 일»(외부 DA·설치·격리 사본)은 죽이지 않고 후계에게 넘긴다.
#     ★H1 넘김 = «스스로 등록한 작업» 만★ — 장부 = <데이터 루트>/.fable-team/state/bg-finite.tsv(env FT_BG_FINITE_LEDGER) · 쓰기는 ft-bg-finite.sh 하나.
#       등록한 도구(ft-da-codex.sh·install.sh·ft-scratch-repo.sh)가 시작 때 자기 pid·pgid·lstart·상한을 적고 trap EXIT 에서 지운다.
#       넘김 판정 = 「이 좌석 ∧ pid 살아 있음 ∧ lstart 같음 ∧ 상한 전」→ 그 줄의 pgid 전체 + 자손. ★명령줄 글자·env 판정은 없다★(짐작 0 · DA⑥ r1 반례).
#       상한 지난 줄 = 자동 사살·넘김 0(보고만 — ft-leak-reap 가 stale 표시·보고한다) · lstart 다른 pid(재사용) = 넘김 0.
#     H3 순서 = 넘김 분리가 press 미룸보다 «먼저»(미룸 먼저면 press 끝 뒤 digest 가 DA 를 reap = 원래 결함 재발) · 넘김 줄 `reap-handover pid=<n> cmd=<앞 80자> to=<후계>`
#       · 끝 줄 `reap <좌석> stopped=<n> handed=<n> left=<n> rc=<n>`(handed 칸은 --handover 일 때만 — 닫기 출력 회귀 0) · 넘긴 것은 신호 0 이라 left 에 안 센다
#     H2 넘김 = 장부 좌석 칸 갱신(잠금+읽기-병합-원자 교체 · 다른 줄 보존) → 후계의 다음 retire·닫기·leak-reap 이 같은 장부로 그 작업을 본다.
#       resume 파일(ZC_RESUME_DIR)/<좌석>.json "handed" 칸은 «보기용 사본»(판정 근거 아님).
#     ├ 닫기·일반 reap 은 반대로 «등록한 작업도 이 좌석의 일» 로 후보에 넣어 정리하고, 끝나면 죽은 줄을 prune 한다(장부 줄이 영원히 남지 않는다).
set -uo pipefail
USAGE="usage: $0 <좌석> [--dry-run] [--wt <워크트리>] [--orphans-only] [--defer-press] [--handover <후계>]"
SEAT="${1:-}"; case "$SEAT" in ""|--*) echo "$USAGE" >&2; exit 2;; esac
shift; DRY=0; WT=""; ORPH=0; DEFER=0; HAND=""
while [ $# -gt 0 ]; do case "$1" in --dry-run) DRY=1; shift;; --orphans-only) ORPH=1; shift;; --defer-press) DEFER=1; shift;; --handover) HAND="${2:-}"; [ -n "$HAND" ] || { echo "$USAGE" >&2; exit 2; }; shift 2;; --wt) WT="${2:-}"; [ -n "$WT" ] || { echo "$USAGE" >&2; exit 2; }; shift 2;; *) echo "$USAGE" >&2; exit 2;; esac; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
DDIR="${FT_REAP_DEFER_DIR:-}"; PDIR="${FT_PERMIT_DIR:-}"; LDG="${FT_BG_FINITE_LEDGER:-}"   # 못 풀면 빈 값 — 미룸이 실제로 필요할 때만 python 이 rc 20
if [ -z "$DDIR" ] || [ -z "$PDIR" ] || [ -z "$LDG" ]; then DR="$(. "$HERE/ft-harness-root.sh" && ft_data_root "$HERE" 2>/dev/null)" || DR=""; DDIR="${DDIR:-${DR:+$DR/.fable-team/state/reap-deferred}}"; PDIR="${PDIR:-${DR:+$DR/.fable-team/state/permits}}"; LDG="${LDG:-${DR:+$DR/.fable-team/state/bg-finite.tsv}}"; fi
exec python3 - "$SEAT" "$DRY" "$WT" "$ORPH" "$HERE/ft-leak-reap.sh" "$DEFER" "$DDIR" "$PDIR" "$HAND" "$LDG" <<'PY'
import ast, json, os, re, signal, subprocess, sys, time
seat, dry, wt_arg, orph, leak = sys.argv[1], sys.argv[2] == "1", sys.argv[3], sys.argv[4] == "1", sys.argv[5]
defer, ddir, pdir, HAND = sys.argv[6] == "1", sys.argv[7], sys.argv[8], sys.argv[9]
LEDGER_ARG = sys.argv[10]
LINUX = sys.platform.startswith("linux")
def die(msg):
    print(f"ft-seat-reap: ERROR {msg}", file=sys.stderr); print(f"reap {seat} stopped=0 left=? rc=20"); sys.exit(20)
def run(cmd, ok_err=()):
    try: r = subprocess.run(cmd, capture_output=True, text=True, timeout=7, env={**os.environ, "LC_ALL": "C", "TZ": "UTC"})
    except (OSError, subprocess.SubprocessError) as e: die(f"{cmd[0]} 실행 실패: {e}")
    if r.returncode != 0 and not any(s in r.stderr for s in ok_err): die(f"{cmd[0]} rc={r.returncode}: {r.stderr.strip()[:80]}")
    return r.stdout if r.returncode == 0 else ""
try: PROTECT = ast.literal_eval(re.search(r"^PROTECT_EXE = (\{.*\})$", open(leak, encoding="utf-8").read(), re.M).group(1))
except (OSError, AttributeError, ValueError, SyntaxError) as e: die(f"보호 목록을 못 읽음 {leak}: {e}")
SERVICE_RE = r"\b(uvicorn|gunicorn|hypercorn)\b|-m (worker|gateway)\b|\bnext (dev|start)\b|next-server|run\.command"
try: SVC = re.compile(os.environ.get("FT_REAP_SERVICE_RE") or SERVICE_RE)
except re.error as e: die(f"FT_REAP_SERVICE_RE 정규식 오류: {e}")
PRESS_RE = r"tests/e2e/\S*press\S*\.py|realtime_multi_e2e\.py"
try: PRESS = re.compile(os.environ.get("FT_PRESS_RUNNER_RE") or PRESS_RE)
except re.error as e: die(f"FT_PRESS_RUNNER_RE 정규식 오류: {e}")
FINITE_EXE = {"ft-da-codex.sh", "install.sh", "ft-scratch-repo.sh"}   # r939 H1 — 이 세 도구가 «자기 등록» 한다(장부 = state/bg-finite.tsv · 쓰기는 ft-bg-finite.sh 하나)
LDG = os.environ.get("FT_BG_FINITE_LEDGER") or LEDGER_ARG   # 빈 값 = bash 가 데이터 루트로 품아 넘긴다(argv 10)
BGF = os.path.join(os.path.dirname(os.path.abspath(leak)), "ft-bg-finite.sh")
def ps_table():   # pid → (ppid, pgid, uid, lstart, cmd, ft_seat|None)
    t = {}
    for ln in run(["ps", "-axww", "-o", "pid=,ppid=,pgid=,uid=,lstart=,command="]).splitlines():
        f = ln.split(None, 9)
        if len(f) < 10 or not f[0].isdigit(): continue
        t[int(f[0])] = [int(f[1]), int(f[2]), int(f[3]), " ".join(f[4:9]), f[9], None, None]
    if not t: die("ps 표가 비어 있음")
    for pid, row in t.items():
        if LINUX:
            try: env = open(f"/proc/{pid}/environ", "rb").read().decode("utf-8", "replace").split("\0")
            except OSError: continue
            row[5] = next((e[8:] for e in env if e.startswith("FT_SEAT=")), None)
            row[6] = next((e[13:] for e in env if e.startswith("FT_BG_FINITE=")), None)
    if not LINUX:   # macOS: -E 는 command 뒤에 env 를 붙인다 — 앞의 command 를 떼고 env 부분에서만 찾는다(인자 속 글자 오인 0)
        for ln in run(["ps", "-axEww", "-o", "pid=,command="]).splitlines():
            f = ln.strip().split(None, 1)
            if len(f) < 2 or not f[0].isdigit() or int(f[0]) not in t: continue
            c = t[int(f[0])][4]; env = f[1][len(c):] if f[1].startswith(c) else ""
            m = re.findall(r"(?:^|\s)FT_SEAT=(\S+)", env)
            if m: t[int(f[0])][5] = m[-1]
            q = re.findall(r"(?:^|\s)FT_BG_FINITE=(\S+)", env)   # 옛 판 호환용(이제 판정에 안 쓴다)
            if q: t[int(f[0])][6] = q[-1]
    return t
def bgf(*a):   # 장부 쓰기는 ft-bg-finite.sh 하나(읽기만 여기서 한다) — 실패는 WARN 1줄(조용한 실패 0)
    env = {**os.environ}
    if LDG: env["FT_BG_FINITE_LEDGER"] = LDG
    try: r = subprocess.run(["bash", BGF, *a], capture_output=True, text=True, timeout=7, env=env)
    except (OSError, subprocess.SubprocessError) as e:
        print(f"ft-seat-reap: WARN 장부 {a[0]} 실행 실패: {e}", file=sys.stderr); return ""
    if r.returncode != 0: print(f"ft-seat-reap: WARN 장부 {a[0]} rc={r.returncode}: {r.stderr.strip()[:160]}", file=sys.stderr)
    return r.stdout if r.returncode == 0 else ""
def ledger_rows():   # 장부 읽기 — 좌석<TAB>pid<TAB>pgid<TAB>lstart<TAB>상한<TAB>상태<TAB>명령
    if not LDG or not os.path.exists(LDG): return []
    try: lines = open(LDG, encoding="utf-8").read().splitlines()
    except OSError as e: print(f"ft-seat-reap: WARN 장부를 못 읽음 {LDG}: {e}", file=sys.stderr); return []
    out = []
    for ln in lines:
        f = ln.split("\t")
        try: out.append({"seat": f[0], "pid": int(f[1]), "pgid": int(f[2]), "lstart": f[3], "until": int(f[4]), "state": f[5], "cmd": f[6] if len(f) > 6 else ""})
        except (IndexError, ValueError): continue
    return out
def registered(t, me, now, want=None):   # r939 H1 — «pid 살아 있음 ∧ lstart 같음 ∧ 상한 전» 줄의 pgid 전체 + 자손 → {pid: (좌석, cmd)}
    out = {}
    for r in ledger_rows():
        if want is not None and r["seat"] != want: continue   # want=None = 전 좌석(남의 등록 작업 판별용)
        if r["until"] <= now: continue   # 상한 지난 줄(보고는 ft-leak-reap 몫 — 자동 사살·넘김 0)
        if r["pid"] not in t or t[r["pid"]][3] != r["lstart"]: continue   # 죽었거나 pid 재사용
        out[r["pid"]] = (r["seat"], r["cmd"])
        for p, row in t.items():   # 같은 pgid = 그 작업의 일꾼(자식·손자)
            if row[1] == r["pgid"] and row[2] == me: out.setdefault(p, (r["seat"], r["cmd"]))
    kids, stack = {}, [(p, v[0], v[1]) for p, v in list(out.items())]   # 자손도 같은 좌석·같은 작업으로(반쪽만 죽이면 DA·설치가 깨진다)
    for p, row in t.items(): kids.setdefault(row[0], []).append(p)
    while stack:
        p, s, c = stack.pop()
        for k in kids.get(p, []):
            if k in t and t[k][2] == me and k not in out:
                out[k] = (s, c); stack.append((k, s, c))
    return out
def ledger_roots(now):   # 넘김 보고·장부 갱신은 «등록한 뿌리» 만 — 넘김 수를 자식 수로 부풀리지 않는다
    return [r for r in ledger_rows() if r["seat"] == seat and r["until"] > now]
def record_handover(rows):   # r939 H2 — resume 파일 "handed" 칸은 «보기용 사본»(판정 근거 아님 · 판정은 장부)
    ent = [{"pid": p, "cmd": c[:200], "started": (tbl[p][3] if p in tbl else ""), "at": time.strftime("%Y-%m-%dT%H:%M:%S")}
           for p, c in sorted(rows.items())]
    if not ent: return
    rd = os.environ.get("ZC_RESUME_DIR") or os.path.expanduser("~/.claude/state/seat-resume")
    try: os.makedirs(rd, exist_ok=True)
    except OSError as e: die(f"넘김 목록 폴더를 못 만듦 {rd}: {e.strerror}")
    rp, rec, side = os.path.join(rd, f"{seat}.json"), None, False
    if os.path.exists(rp):
        try: rec = json.load(open(rp, encoding="utf-8"))
        except (OSError, ValueError) as e: print(f"ft-seat-reap: WARN 재개 기록을 못 읽음 {rp} — 곁파일에 적는다: {e}", file=sys.stderr)
        if not isinstance(rec, dict): rec = None   # 깨진 기록은 덮지 않는다(닫기 근거) — 곁파일
    if rec is None: rp, rec, side = os.path.join(rd, f"{seat}.handed.json"), {"name": seat}, True
    prev = [e for e in rec.get("handed") if isinstance(e, dict)] if isinstance(rec.get("handed"), list) else []
    new = {(e["pid"], e["started"]) for e in ent}
    rec["handed"] = ([e for e in prev if (e.get("pid"), e.get("started")) not in new] + ent)[-50:]
    try:
        open(rp + f".tmp{os.getpid()}", "w", encoding="utf-8").write(json.dumps(rec, ensure_ascii=False, indent=2) + "\n")
        os.replace(rp + f".tmp{os.getpid()}", rp)
    except OSError as e: die(f"넘김 목록을 못 씀 {rp}: {e.strerror}")
    print(f"reap-handover-record {rp} handed={len(rec['handed'])}" + (" (resume 기록 없음 — 곁파일 · 후계는 이 파일을 본다)" if side else ""))
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
def ancestors(t):   # 이 명령 자신과 조상
    anc, p = set(), os.getpid()
    while p in t and p not in anc and p > 1: anc.add(p); p = t[p][0]
    return anc
def survey():
    t, pl, me = ps_table(), panes(), os.getuid()
    anc = ancestors(t)
    mine = [int(x[1]) for x in pl if x[0] == seat]
    other = desc(t, [int(x[1]) for x in pl if x[0] != seat]) | {int(x[1]) for x in pl if x[0] != seat}
    wt = wt_arg or next((x[3] for x in pl if x[0] == seat), "")
    wt = os.path.realpath(wt) if wt and os.path.exists(os.path.join(wt, ".git")) and os.path.realpath(wt) not in ("/", os.path.realpath(os.path.expanduser("~"))) else ""
    shared = bool(wt) and any(x[0] != seat and (inside(os.path.realpath(x[2]), wt) or inside(os.path.realpath(x[3]), wt)) for x in pl)
    cw = cwds() if wt and not shared else {}
    bg = {p for p, r in t.items() if re.search(r"ft-bg-loop\.sh .*--seat " + re.escape(seat) + r"(\s|$)", r[4])}
    cand, tree, svc, skip = {}, desc(t, mine), services(t), {}
    for pid, (ppid, pgid, uid, lst, cmd, fs, fb) in t.items():
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
def script_arg(tok):   # python 옵션 뒤 첫 비옵션 토큰 = 실행 스크립트 · -c/-m/- = 스크립트 없음 · -W/-X 는 값 1개를 먹는다
    i = 1
    while i < len(tok):
        a = tok[i]
        if a in ("-c", "-m", "-"): return ""
        if a == "--": return tok[i + 1] if i + 1 < len(tok) else ""
        if not a.startswith("-"): return a
        i += 2 if a in ("-W", "-X") else 1
    return ""
def press_rows():   # [(pid, uid, command)] — FT_PRESS_PS_SNAPSHOT = 시험 전용(남의 uid 러너 재현)
    snap = os.environ.get("FT_PRESS_PS_SNAPSHOT")
    if not snap: return [(p, r[2], r[4]) for p, r in sorted(ps_table().items())]
    try: lines = open(snap, encoding="utf-8").read().splitlines()
    except OSError as e: die(f"FT_PRESS_PS_SNAPSHOT 못 읽음 {snap}: {e}")
    return [(int(f[0]), int(f[1]), f[2]) for f in (l.split(None, 2) for l in lines) if len(f) == 3 and f[0].isdigit() and f[1].isdigit()]
_press = []
def press():   # r690 — "" = 진행 아님 · 아니면 by=<…> (한 번만 잼)
    if not _press:
        me, by = os.getuid(), ""
        for p, uid, cmd in press_rows():   # 실행 파일이 python* 이고 «실행 스크립트»가 러너 경로일 때만(셸 명령줄·인자로만 든 경로 오탐 0)
            tok = cmd.split()
            if tok and re.match(r"(?i)python[0-9.]*$", os.path.basename(tok[0])) and PRESS.search(script_arg(tok)) and uid == me: by = f"runner:{p}"; break
        dev = os.path.join(pdir, "device.json") if pdir else ""
        if not by and dev and os.path.exists(dev):
            try: by = "device-held" if json.load(open(dev, encoding="utf-8")).get("held") is True else ""
            except (OSError, ValueError, AttributeError) as e: by = "device-unreadable"; print(f"ft-seat-reap: WARN {dev} 못 읽음 — press 진행으로 봄: {e}", file=sys.stderr)
        _press.append(by)
    return _press[0]
def read_deferred(f):   # → (행들, 깨진 줄들) · None = 이미 없음(동시에 돈 다른 정리가 먼저 소화) · 읽기 오류 = rc 20
    try: lines = open(f, encoding="utf-8").read().splitlines()
    except FileNotFoundError: return None
    except (OSError, UnicodeDecodeError) as e: die(f"미룸 파일 못 읽음 {f}: {e}")
    rows, bad = [], []
    for ln in (l for l in lines if l.strip()):
        try: r = json.loads(ln)
        except ValueError: r = None
        if isinstance(r, dict) and isinstance(r.get("pid"), int) and isinstance(r.get("lstart"), str): rows.append(r)
        else: bad.append(ln)
    return rows, bad
def digest():   # 미룸 소화(닫는 사건) — lstart 같은 내 pid 만 · 일반 조사와 같은 제외 · 못 멈춘 행만 남김
    if not ddir: print("ft-seat-reap: WARN 미룸 폴더를 못 풂(FT_REAP_DEFER_DIR 없음 · 데이터 루트 못 풂) — 미룸 소화 생략", file=sys.stderr); return
    files = sorted(f for f in os.listdir(ddir) if f.endswith(".jsonl")) if os.path.isdir(ddir) else []
    if not files or press(): return
    me = os.getuid()
    for fn in files:
        f = os.path.join(ddir, fn); got = read_deferred(f)
        if got is None: continue
        rows, bad = got
        if bad:   # 조용히 버리지 않는다(#0 RULE) — 원문 보존 + 눈에 보이는 줄
            bf = f"{f}.broken-{time.strftime('%Y%m%d%H%M%S')}-{os.getpid()}"
            open(bf, "w", encoding="utf-8").write("".join(l + "\n" for l in bad))
            print(f"reap-deferred-broken file={bf} lines={len(bad)}"); print(f"ft-seat-reap: ERROR 미룸 파일 깨진 줄 {len(bad)} — {bf} 로 원문 보존(사람 판단)", file=sys.stderr)
        t = ps_table(); anc, svc, live = ancestors(t), services(t), {}   # 파일마다 새 표 — TERM 직전 lstart 재확인
        for r in rows:
            p = r["pid"]
            if p not in t or t[p][2] != me or t[p][3] != r["lstart"]: continue   # 죽었거나 pid 재사용 — 신호 0
            exe = os.path.basename(t[p][4].split()[0]) if t[p][4].split() else ""
            why = "self" if p in anc else "protect-exe" if exe in PROTECT else svc.get(p, "")
            if why: print(f"reap-skip pid={p} why={why} cmd={t[p][4][:100]}"); continue
            live[p] = ("⑤미룸", r["lstart"], t[p][4])
        if live: stop(live)
        kept = alive(live)
        if kept: open(f, "w", encoding="utf-8").write("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows if r.get("pid") in kept))
        else: os.remove(f)
        print(f"reap-deferred-done file={f} stopped={len(live) - len(kept)} kept={len(kept)}")
if not dry: digest()
cand, tbl, shared, skip = survey()
for p, (w, c) in sorted(skip.items()): print(f"reap-skip pid={p} why={w} cmd={c[:100]}")
tail = " cwd=shared" if shared else ""
dtail = " deferred=0" if defer else ""
if dry:
    for p, (v, _, c) in sorted(cand.items()): print(f"reap-cand pid={p} via={v} cmd={c[:100]}")
    print(f"reap {seat} found={len(cand)} dry-run rc=0{tail}"); sys.exit(0)
now = time.time()
allreg = registered(tbl, os.getuid(), now)                                  # r939 H1 — 전 좌석 등록 장부(짐작 0)
reg = {p: v for p, v in allreg.items() if v[0] == seat}                      # 이 좌석의 작업
other = {p for p, v in allreg.items() if v[0] != seat}                       # 넘겨받은(남의 좌석) 작업 — env FT_SEAT 가 옛 이름이어도 건드리지 않는다
cand = {p: v for p, v in cand.items() if p not in other}
for p, (v, lst, c) in sorted(cand.items()):   # 등록 안 한 «끝나는 일» 도구 → 넘기지 않는다는 것을 보이게(영구 참김)·알림 1줄 — 조용한 손실 0
    if p not in allreg and any(os.path.basename(a) in FINITE_EXE for a in c.split()) and v != "자손":
        print(f"reap-unregistered pid={p} cmd={c[:80]} (등록 장부에 줄 없음 — 넘김 대상 아님")
hn = 0
if HAND:   # H3 — 넘김 분리를 press 미룸보다 «먼저»(미룸이 먼저면 press 끝 뒤 digest 가 DA 를 reap = 원래 결함)
    roots = [r for r in ledger_roots(now) if r["pid"] in reg]   # 죽었거나 pid 재사용·lstart 불일치 = 넘김 0
    for r in roots:
        print(f"reap-handover pid={r['pid']} cmd={r['cmd'][:80]} to={HAND}"); hn += 1
    if hn:
        bgf("handover", HAND, *[str(r["pid"]) for r in roots])   # H2 장부 좌석 칸 → 후계(다른 줄 보존)
        record_handover({r["pid"]: r["cmd"] for r in roots})     # 보기용 사본(판정 근거 아님)
    cand = {p: v for p, v in cand.items() if p not in reg}
else:   # 닫기·일반 reap — 이 좌석의 등록 작업은 «이 좌석의 일» 이므로 후보에 넣고, 남의(넘겨받은) 등록 작업은 건드리지 않는다
    for p, v in reg.items():
        if p in tbl and p not in cand: cand[p] = ("등록", tbl[p][3], tbl[p][4])
if defer and cand and press():
    if not ddir: die("미룸 파일 경로를 못 풂 — FT_REAP_DEFER_DIR 없음 · 데이터 루트 못 풂(미룸을 적을 곳이 없으면 닫는 사건도 없다)")
    os.makedirs(ddir, exist_ok=True)
    print(f"reap-press-active by={press()}")
    with open(os.path.join(ddir, f"{seat}.jsonl"), "a", encoding="utf-8") as fh:
        for p, (v, lst, c) in sorted(cand.items()):
            print(f"reap-defer pid={p} why=press-active cmd={c[:100]}")
            fh.write(json.dumps({"pid": p, "lstart": lst, "cmd": c[:200], "via": v}, ensure_ascii=False) + "\n")
    print(f"reap {seat} stopped=0 left=0 deferred={sum(1 for x in cand.values() if x[0] != '자손')} rc=0{tail}"); sys.exit(0)
ht = f" handed={hn}" if HAND else ""
seen, again = set(), cand
for _ in range(2):   # 2회전 — 1회전 사이에 새로 드러난 것(부모를 잃은 자식 등)까지
    if not again: break
    seen |= {p for p, x in again.items() if x[0] != "자손"}; stop(again); again, _, _, _ = survey()
    if HAND: again = {p: v for p, v in again.items() if p not in reg}   # 넘긴 것은 살아 있는 것이 정상 — 후보로 다시 세지 않는다
left = sum(1 for x in again.values() if x[0] != "자손"); rc = 1 if left else 0
for p, (v, _, c) in sorted(again.items()): print(f"reap-left pid={p} via={v} cmd={c[:100]}")
bgf("prune")   # 끝난(죽은) 작업 줄 정리 — 넘긴 작업의 줄은 살아 있으니 그대로(후계·다음 retire 가 본다)
print(f"reap {seat} stopped={len(seen - set(again))}{ht} left={left}{dtail} rc={rc}{tail}"); sys.exit(rc)   # stopped = 뿌리 수(자손 sleep 등은 reap-kill 줄에만)
PY
