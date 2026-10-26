#!/usr/bin/env bash
# ft-bg-finite.sh — «곧 끝나는 일» 자기 등록 장부 (r939 H1 · DA⑥ r1 반송: «짐작» 대신 «등록»)
#   끝나는 작업을 띄우는 도구(ft-da-codex.sh · install.sh · ft-scratch-repo.sh)가 시작할 때 자기 프로세스를 등록하고 trap EXIT 에서 지운다.
#   ft-seat-reap.sh --handover 는 장부에서 «이 좌석 ∧ pid 살아 있음 ∧ lstart 같음 ∧ 상한 전» 줄의 pgid 전체를 넘긴다 — 명령줄 글자 판정 0.
#   장부 = <데이터 루트>/.fable-team/state/bg-finite.tsv (env FT_BG_FINITE_LEDGER 로 바꿀 수 있다)
#     한 줄 = 좌석 <TAB> pid <TAB> pgid <TAB> lstart(LC_ALL=C TZ=UTC 5토큰, 공백 1칸) <TAB> 상한_epoch <TAB> 상태(ok|handed|stale) <TAB> 명령 앞 80자
#   ★쓰기는 이 파일 하나★ — flock(별 sidecar lock) + 읽기-병합-원자 교체(tmp→rename) · reap·leak-reap 은 읽기만 한다(겹쳐 써도 덮어쓰기 0)
#   register <좌석|-> <상한초> <pid> [명령…]   등록(같은 pid+lstart 줄은 교체 · pid 없으면 rc 3) · 좌석 "-" = 좌석 모름(넘김 대상 아님)
#   unregister <pid>                            trap EXIT 용 — 그 pid 줄을 지운다(끝났으므로)
#   handover <후계> <pid>…                      넘김 — 그 pid 줄의 좌석 칸을 후계로(덮어쓰기 0 · 다른 줄 보존)
#   prune [<pid>…]                              끝난 줄 지움 = pid 죽음 또는 pid 재사용(lstart 다름) — 인자 없으면 전부(reap·leak-reap 이 부른다)
#   register 상한초는 4200(70분)으로 잘린다(더 크거나 정수 아님 = 4200 · stderr 1줄)
#   stale <pid>…                                상한 지난 줄을 상태=stale 로 표시(자동 사살·넘김 0 · leak-reap 보고와 함께)
#   rows                                        장부 그대로 출력(시험·디버그)
#   rc 0 = ok · 2 = usage · 3 = pid 없음(register) · 20 = 장부 읽기·쓰기 실패
set -uo pipefail
USAGE="usage: $0 register <좌석|-> <상한초> <pid> [명령…] | unregister <pid> | handover <후계> <pid>… | prune [<pid>…] | stale <pid>… | rows"
MODE="${1:-}"; [ -n "$MODE" ] || { echo "$USAGE" >&2; exit 2; }
shift
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
LDG="${FT_BG_FINITE_LEDGER:-}"
if [ -z "$LDG" ]; then
  DR="$(. "$HERE/ft-harness-root.sh" && ft_data_root "$HERE" 2>/dev/null)" || DR=""
  [ -n "$DR" ] || { echo "ft-bg-finite: ERROR 데이터 루트를 못 풂(FT_ROOT 없음 · LIVE_ROOT 없음) — 장부 자리 모름" >&2; exit 20; }
  LDG="$DR/.fable-team/state/bg-finite.tsv"
fi
exec python3 - "$MODE" "$LDG" "$@" <<'PY'
import fcntl, os, re, subprocess, sys, time
mode, ldg, args = sys.argv[1], sys.argv[2], sys.argv[3:]
SEPS = "\t"
CAP_SEC = 4200   # register 상한 70분
def die(msg):
    print(f"ft-bg-finite: ERROR {msg}", file=sys.stderr); sys.exit(20)
def lstart(pid):   # reap 과 같은 꼴(LC_ALL=C TZ=UTC · 5토큰 공백 1칸) — 좌석마다 TZ 가 달라도 같은 글자
    try:
        r = subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)], capture_output=True, text=True, timeout=7, env={**os.environ, "LC_ALL": "C", "TZ": "UTC"})
    except (OSError, subprocess.SubprocessError) as e: die(f"ps 실행 실패: {e}")
    return " ".join(r.stdout.split())
def alive(pid):
    try: os.kill(pid, 0); return True
    except ProcessLookupError: return False
    except PermissionError: return True
class Ledger:
    def __enter__(self):   # sidecar lock — 본 파일은 tmp→rename 으로 통째 교체되므로 inode 잠금은 못 쓴다
        d = os.path.dirname(ldg) or "."
        try: os.makedirs(d, exist_ok=True)
        except OSError as e: die(f"장부 폴더를 못 만듦 {d}: {e.strerror}")
        try: self.lk = open(ldg + ".lock", "a+")
        except OSError as e: die(f"장부 잠금 파일을 못 열음 {ldg}.lock: {e.strerror}")
        fcntl.flock(self.lk, fcntl.LOCK_EX)
        try: text = open(ldg, encoding="utf-8").read() if os.path.exists(ldg) else ""
        except OSError as e: die(f"장부를 못 읽음 {ldg}: {e.strerror}")
        self.rows, self.bad = [], len(text.splitlines())
        for ln in text.splitlines():
            f = ln.split(SEPS)
            if len(f) >= 6:
                try: self.rows.append([f[0], int(f[1]), int(f[2]), f[3], int(f[4]), f[5], f[6] if len(f) > 6 else ""]); continue
                except ValueError: pass
            if ln.strip(): print(f"ft-bg-finite: WARN 깨진 줄 버림: {ln[:120]}", file=sys.stderr)
        return self
    def save(self):
        tmp = f"{ldg}.tmp{os.getpid()}"
        try:
            open(tmp, "w", encoding="utf-8").write("".join(SEPS.join(str(x) for x in r) + "\n" for r in self.rows))
            os.replace(tmp, ldg)
        except OSError as e: die(f"장부를 못 씀 {ldg}: {e.strerror}")
    def __exit__(self, *a):
        try: fcntl.flock(self.lk, fcntl.LOCK_UN); self.lk.close()
        except OSError: pass
        return False
def pids(seq):
    out = []
    for a in seq:
        if not a.isdigit(): die(f"pid 가 숫자가 아님: «{a}»")
        out.append(int(a))
    return out
if mode == "rows":
    try: print(open(ldg, encoding="utf-8").read(), end="")
    except FileNotFoundError: pass
    except OSError as e: die(f"장부를 못 읽음 {ldg}: {e.strerror}")
    sys.exit(0)
if mode == "register":
    if len(args) < 3: print("usage: register <좌석|-> <상한초> <pid> [명령…]", file=sys.stderr); sys.exit(2)
    seat, secs, pid = args[0], args[1], args[2]
    if not pid.isdigit(): die(f"pid 가 숫자가 아님: «{pid}»")
    if not re.fullmatch(r"[0-9]{1,6}", secs) or int(secs) > CAP_SEC:   # r939 r3 — 0 이상 정수(0 = 즉시 만료 · ASCII 숫자 1~6자리만 · «-»·부호·공백·지수·긴 숫자열 0)가 아니거나 4200 초과 = 4200 (자기등록 루프도 최대 70분 뒤 «만료» → 다음 승계·닫기가 reap)
        print(f"ft-bg-finite: WARN 상한초 «{secs}» → {CAP_SEC} 로 자름(70분 상한)", file=sys.stderr); secs = str(CAP_SEC)
    pid = int(pid)
    if not alive(pid): print(f"ft-bg-finite: ERROR pid {pid} 없음 — 등록 0", file=sys.stderr); sys.exit(3)
    try: pgid = os.getpgid(pid)
    except OSError as e: die(f"pgid 를 못 읽음 {pid}: {e.strerror}")
    lst = lstart(pid)
    if not lst: die(f"lstart 를 못 읽음 {pid}")
    cmd = " ".join(args[3:])[:80]
    row = [seat or "-", pid, pgid, lst, int(time.time()) + int(secs), "ok", cmd]
    with Ledger() as L:
        L.rows = [r for r in L.rows if not (r[1] == pid and r[3] == lst)] + [row]   # 같은 작업 재등록 = 교체(다른 줄 보존)
        L.save(); n = len(L.rows)
    print(f"registered pid={pid} pgid={pgid} seat={row[0]} until={row[4]} rows={n}")
    sys.exit(0)
if mode == "unregister":
    ps = pids(args[:1]) if args else []
    if not ps: print("usage: unregister <pid>", file=sys.stderr); sys.exit(2)
    with Ledger() as L:
        keep = [r for r in L.rows if r[1] not in ps]
        gone = len(L.rows) - len(keep)
        if gone: L.rows = keep; L.save()
    print(f"unregistered pid={ps[0]} removed={gone}"); sys.exit(0)
if mode == "handover":
    if len(args) < 2: print("usage: handover <후계> <pid>…", file=sys.stderr); sys.exit(2)
    new, ps = args[0], set(pids(args[1:]))
    with Ledger() as L:
        n = 0
        for r in L.rows:
            if r[1] in ps: r[0], r[5], n = new, "handed", n + 1
        if n: L.save()
    print(f"handover to={new} rows={n}"); sys.exit(0)
if mode == "stale":
    ps = pids(args)
    if not ps: print("usage: stale <pid>…", file=sys.stderr); sys.exit(2)
    with Ledger() as L:
        n = 0
        for r in L.rows:
            if r[1] in set(ps) and r[5] != "stale": r[5], n = "stale", n + 1
        if n: L.save()
    print(f"stale marked={n}"); sys.exit(0)
if mode == "prune":
    want = set(pids(args)) if args else None
    def gone_row(r):   # r939 r3 — 죽었거나 pid 재사용(lstart 다름)인 줄만 «끝난 작업» · 살아 있고 lstart 같은 줄은 인자에 든 pid 여도 지키지 않는다(재사용 pid 의 새 줄 오삭제 0)
        return (want is None or r[1] in want) and (not alive(r[1]) or lstart(r[1]) != r[3])
    with Ledger() as L:
        keep = [r for r in L.rows if not gone_row(r)]
        gone = len(L.rows) - len(keep)
        if gone: L.rows = keep; L.save()
    print(f"prune removed={gone}"); sys.exit(0)
print(USAGE, file=sys.stderr); sys.exit(2)
PY
