#!/usr/bin/env bash
# ft-reboot-restore.sh — r641 재부팅 뒤 claude 좌석 복구 1줄: 좌석 목록 → 4석씩 병렬로 tmux 세션 + 헤드룸 래퍼 --resume → 확인표.
#   ft-reboot-restore.sh [--from latest|<스냅샷 경로>] [--since <시간>] [--dry-run]
#   목록: ①스냅샷(기본 ~/.tmuxc/snapshots/latest.json · agent=shell 행 제외) ②없음·깨짐·빈 것이면 ZC_LIVE_DIR(~/.claude/state/seat-live)
#         engine=claude · 파일 시각 --since(24)시간 안 · 같은 이름은 at 최신 1개 · 출처를 1줄 · 둘 다 없음 = ERROR rc 2.
#   좌석마다(FT_RR_PAR=4 병렬): ①같은 이름 tmux 세션 있음 = SKIP 살아 있음 ②claude 아님 = FAIL 엔진 밖 ③uuid·cwd·model·대화 파일 없음 = FAIL
#     ④이름에 -nano- + `ft-resume-attempt.sh rested <jsonl>` rc 0 = SKIP 끝난 나노
#     ⑤`tmux new-session -d -s <이름> -c <cwd> -e FT_SEAT=<이름> 'zsh -l'` → send-keys -l <줄> 과 Enter 별도 호출
#       줄 = FT_SEAT=<이름> <FT_RR_HR(~/.headroom/claude-hr.sh)> --dangerously-skip-permissions --model <m> --effort <e|high> --resume <uuid> --name <이름>
#     ⑥FT_RR_WAIT(60)초 안에 pane 자손 중 ANTHROPIC_BASE_URL 있는 프로세스(또는 claude) = OK · 8317 O/X · 못 보면 FAIL 기동 확인 없음.
#   출력 = 좌석별 «이름 · 결과 · pid · 8317 O/X · uuid» + FAIL 목록 + 맨 끝 요약 1줄 · 원장 <루트>/.fable-team/state/reboot-restore.log(좌석이 끝날 때마다 1줄).
#   rc 0 · 3(FAIL 또는 8317 X 하나라도) · 2(ERROR) — 살아 있는 세션은 보기만 한다(kill·send-keys 0) · 명부·쪽지 0 · claude 좌석만.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_ROOT:-}"   # r385 라이브 루트 = FT_ROOT → ft_data_root(cwd LIVE_ROOT · 옛 설치 꼴) → ERROR
[ -n "$ROOT" ] || { . "$HERE/ft-harness-root.sh" && ROOT="$(ft_data_root "$HERE")"; } || { echo "ERROR 루트를 못 풂 — FT_ROOT=<리포 루트> 로 다시"; exit 2; }
case "${1:-}" in -h|--help) sed -n '2,13p' "$0"; exit 0;; esac
FT_ROOT="$ROOT" exec python3 -I - "$ROOT" "$HERE" "$@" <<'PY'
import glob, json, os, re, shlex, subprocess, sys, threading, time
from concurrent.futures import ThreadPoolExecutor
root, here, args = sys.argv[1], sys.argv[2], sys.argv[3:]
env = os.environ; home = os.path.expanduser("~")
PAR = max(1, int(env.get("FT_RR_PAR") or 4)); WAIT = float(env.get("FT_RR_WAIT") or 60)
LIVE = env.get("ZC_LIVE_DIR") or f"{home}/.claude/state/seat-live"
HR = env.get("FT_RR_HR") or f"{home}/.headroom/claude-hr.sh"
LOG = f"{root}/.fable-team/state/reboot-restore.log"
opt = lambda k, d: args[args.index(k) + 1] if k in args and args.index(k) + 1 < len(args) else d
src, since, dry = opt("--from", "latest"), float(opt("--since", "24")), "--dry-run" in args
lock = threading.Lock()
def log(line):
    if dry: return
    with lock:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, "a", encoding="utf-8") as f: f.write(f"{time.strftime('%Y-%m-%dT%H:%M:%S')} {line}\n")
def run(*a):
    try: r = subprocess.run(a, capture_output=True, text=True, timeout=7); return r.returncode, r.stdout
    except (OSError, subprocess.SubprocessError): return 1, ""
def row(name, engine, cwd, model, effort, uuid, jsonl=""):
    jsonl = jsonl or f"{home}/.claude/projects/{re.sub('[^A-Za-z0-9]', '-', cwd)}/{uuid}.jsonl"
    return dict(name=name, engine=engine, cwd=cwd, model=model, effort=effort or "high", uuid=uuid, jsonl=jsonl)
def from_snapshot():
    p = f"{home}/.tmuxc/snapshots/latest.json" if src == "latest" else src
    try:
        ss = json.load(open(p, encoding="utf-8"))["sessions"]
        rows = [row(s.get("name") or "", s.get("agent") or "", s.get("cwd") or "", s.get("model") or "", s.get("effort") or "", s.get("session_id") or "")
                for s in ss if s.get("agent") != "shell"]
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as e: return None, f"{p} {type(e).__name__}"
    return (rows, p) if rows else (None, f"{p} 좌석 0")
def from_live():
    cut, best = time.time() - since * 3600, {}
    for f in glob.glob(f"{LIVE}/*.json"):
        try:
            if os.path.getmtime(f) < cut: continue
            d = json.load(open(f, encoding="utf-8"))
        except (OSError, ValueError): continue
        if not isinstance(d, dict) or d.get("engine") != "claude" or not d.get("name"): continue
        if d["name"] not in best or str(d.get("at") or "") > str(best[d["name"]].get("at") or ""): best[d["name"]] = d
    return [row(n, "claude", d.get("cwd") or "", d.get("model") or "", d.get("effort") or "", d.get("uuid") or "", d.get("jsonl") or "") for n, d in sorted(best.items())]
def alive(n): return run("tmux", "has-session", "-t", "=" + n)[0] == 0
def precheck(r):   # (결과, 사유) · None = 연다
    n = r["name"]
    if not n: return "FAIL", "이름 없음"
    if alive(n): return "SKIP", "살아 있음"
    if r["engine"] != "claude": return "FAIL", f"엔진 밖({r['engine'] or '-'})"
    if not (r["uuid"] and r["model"] and os.path.isdir(r["cwd"])): return "FAIL", "uuid·model·cwd 없음"
    if not os.path.isfile(r["jsonl"]): return "FAIL", "대화 파일 없음"
    if "-nano-" in n and run("bash", f"{here}/ft-resume-attempt.sh", "rested", r["jsonl"])[0] == 0: return "SKIP", "끝난 나노"
    return None
def line_for(r):
    q = shlex.quote
    return " ".join([f"FT_SEAT={q(r['name'])}", q(HR), "--dangerously-skip-permissions", "--model", q(r["model"]),
                     "--effort", q(r["effort"]), "--resume", q(r["uuid"]), "--name", q(r["name"])])
def descendants(pid):
    out, todo = [], [pid]
    while todo:
        kids = run("pgrep", "-P", todo.pop())[1].split(); out += kids; todo += kids
    return out
def probe(pid):   # (pid, 8317 O/X) · None = 아직
    for k in descendants(pid):
        m = re.search(r"\bANTHROPIC_BASE_URL=(\S+)", run("ps", "eww", "-o", "command=", "-p", k)[1])
        if m: return k, "O" if re.search(r":8317(/|$)", m.group(1)) else "X"
        if os.path.basename(run("ps", "-o", "comm=", "-p", k)[1].strip()) == "claude": return k, "X"   # exec 된 claude 인데 프록시 없음
    return None
def open_seat(r):
    n, t = r["name"], "=" + r["name"] + ":"
    if run("tmux", "new-session", "-d", "-s", n, "-c", r["cwd"], "-e", f"FT_SEAT={n}", "zsh -l")[0]: return "FAIL", "tmux 세션 열기 실패", "-", "-"
    if run("tmux", "send-keys", "-t", t, "-l", line_for(r))[0] or run("tmux", "send-keys", "-t", t, "Enter")[0]: return "FAIL", "send-keys 실패", "-", "-"
    pp, end = run("tmux", "display", "-p", "-t", t, "#{pane_pid}")[1].strip(), time.time() + WAIT
    while pp and time.time() < end:
        got = probe(pp)
        if got: return "OK", "", got[0], got[1]
        time.sleep(1)
    return "FAIL", "기동 확인 없음", "-", "-"
def one(r):
    pre = precheck(r)
    res = (pre[0], pre[1], "-", "-") if pre else (("PLAN", "열기", "-", "-") if dry else open_seat(r))
    log(f"{r['name']} {res[0]} {res[1] or '-'} pid={res[2]} 8317={res[3]} uuid={r['uuid'] or '-'}")
    return res
rows, why = from_snapshot(); origin = f"출처=snapshot {why}"
if rows is None:
    rows = from_live(); origin = f"출처=seat-live (스냅샷 {why}) {LIVE} since={since:g}h"
    if not rows:
        print(f"ERROR 좌석 목록 없음 — 스냅샷({why}) · seat-live({LIVE} · {since:g}시간 안 claude 0)"); sys.exit(2)
uniq = {}
for r in rows: uniq.setdefault(r["name"], r)
rows = list(uniq.values())
print(origin); log(f"start {origin} 좌석={len(rows)} par={PAR} wait={WAIT:g}")
with ThreadPoolExecutor(max_workers=1 if dry else PAR) as ex: res = list(ex.map(one, rows))
print("이름 · 결과 · pid · 8317 · uuid")
for r, (k, why, pid, px) in zip(rows, res):
    label = "계획 " + why if k == "PLAN" else (f"{k} {why}" if why else k)
    print(f"{r['name']} · {label} · {pid} · {px} · {r['uuid'] or '-'}")
fails = [(r["name"], w) for r, (k, w, _, _) in zip(rows, res) if k == "FAIL"]
if fails: print("FAIL 목록:"); [print(f"- {n} — {w}") for n, w in fails]
cnt = lambda k: sum(1 for x in res if x[0] == k)
x = sum(1 for x in res if x[3] == "X"); rc = 0 if dry or not (fails or x) else 3
tail = f"REBOOT-RESTORE {'dry-run ' if dry else ''}ok={cnt('OK')} plan={cnt('PLAN')} skip={cnt('SKIP')} fail={len(fails)} x8317={x} rc={rc} 원장={'- (dry-run 기록 0)' if dry else LOG}"
log(tail); print(tail); sys.exit(rc)
PY
