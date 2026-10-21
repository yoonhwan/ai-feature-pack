#!/usr/bin/env bash
# a-fs-atomicity.sh — 실측 A: 파일시스템 원자성 · fsync · 동시 recv 이중소비 · SIGKILL 중 JSONL 보존
#
# 범위: 이 맥 로컬만. 원격 0 · 설치 0 · ssh 0 · 제품 우편함/제품 Redis 쓰기 0.
# 임시 폴더 = mktemp -d 만 쓰고 끝나면 그 폴더만 지운다(--keep 이면 남기고 경로를 찍는다).
#
# 출력: stdout 에 `KEY=VALUE` 요약 줄(사람이 읽고 measured-a-fs.md 표로 옮긴다).
#   A1.* 파일 os.replace 원자성      A2.* link()/rename 발행 + 디렉터리 swap
#   B.*  디렉터리 fsync 가부·비용     C.*  동시 recv 이중소비율
#   D.*  SIGKILL 중 JSONL 보존
#
# 사용: bash docs/multihost/measure/a-fs-atomicity.sh [--iters N] [--rounds N] [--keep]
set -uo pipefail

ITERS=1000
ROUNDS=100
KEEP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --iters) ITERS="$2"; shift 2 ;;
    --rounds) ROUNDS="$2"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
MBOX_PY="${FT_MBOX_PY:-$ROOT/feature-pack/fable-team/skill/scripts/ft-mbox.py}"
[ -f "$MBOX_PY" ] || { echo "FATAL: ft-mbox.py 없음: $MBOX_PY" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/a-fs-XXXXXX")
cleanup() { [ "$KEEP" = 1 ] && echo "WORK_DIR=$WORK" || rm -rf "$WORK"; }
trap cleanup EXIT

echo "ENV_OS=$(sw_vers -productVersion 2>/dev/null || echo unknown)"
echo "ENV_UNAME=$(uname -sm)"
echo "ENV_PY=$(python3 -V 2>&1)"
echo "ENV_FS=$(df -T "$WORK" 2>/dev/null | awk 'NR==2{print $1" "$2}' || echo unknown)"
echo "ENV_ITERS=$ITERS"
echo "ENV_ROUNDS=$ROUNDS"
echo "ENV_MBOX_PY=$MBOX_PY"
export WORK ITERS ROUNDS MBOX_PY

# ── 관찰자 프로세스 (별도 pid) — 중간 상태를 «읽는» 쪽 ────────────────────────
cat >"$WORK/observer.py" <<'PY'
import json, os, sys
mode, target, stop, out = sys.argv[1:5]
anom = {"missing": 0, "empty": 0, "torn": 0, "partial": 0}
samples = 0
while not os.path.exists(stop):
    try:
        if mode == "file":
            try:
                with open(target, "rb") as f:
                    b = f.read()
            except FileNotFoundError:
                anom["missing"] += 1
                continue
            samples += 1
            if len(b) == 0:
                anom["empty"] += 1
            elif not (b.startswith(b"R") and b.endswith(b"\nEND\n") and len(b) >= 4100):
                anom["torn"] += 1
        else:  # dir
            try:
                names = [n for n in os.listdir(target) if n.startswith("f")]
            except FileNotFoundError:
                anom["missing"] += 1
                continue
            samples += 1
            if len(names) != 5:
                anom["partial"] += 1
    except OSError:
        anom["torn"] += 1
json.dump({"samples": samples, **anom}, open(out, "w"))
PY

# ── A1 · A2 : 원자성 ────────────────────────────────────────────────────
cat >"$WORK/atomic.py" <<'PY'
import errno, json, os, subprocess, sys, time

WORK, ITERS = os.environ["WORK"], int(os.environ["ITERS"])
d = os.path.join(WORK, "atomic"); os.makedirs(d, exist_ok=True)
OBS = os.path.join(WORK, "observer.py")
body = b"x" * 4096

def start_obs(mode, target):
    stop = target + ".stop"; out = target + ".obs.json"
    for p in (stop, out):
        try: os.unlink(p)
        except FileNotFoundError: pass
    p = subprocess.Popen([sys.executable, OBS, mode, target, stop, out])
    return p, stop, out

def stop_obs(o):
    p, stop, out = o
    open(stop, "w").close()
    p.wait()
    return json.load(open(out))

# ── A1: 파일 os.replace (tmp 쓰고 replace) ──
tgt = os.path.join(d, "a1.txt")
def payload(i): return b"R%06d\n" % i + body + b"\nEND\n"
open(tgt, "wb").write(payload(0))
o = start_obs("file", tgt)
t0 = time.perf_counter(); exc = 0
for i in range(ITERS):
    tmp = os.path.join(d, ".a1.tmp")
    with open(tmp, "wb") as f:
        f.write(payload(i)); f.flush(); os.fsync(f.fileno())
    try: os.replace(tmp, tgt)
    except OSError: exc += 1
a1dur = (time.perf_counter() - t0) / ITERS * 1e6
a1 = stop_obs(o)
print(f"A1.iters={ITERS}\nA1.exceptions={exc}\nA1.samples={a1['samples']}")
print(f"A1.missing={a1['missing']}\nA1.empty={a1['empty']}\nA1.torn={a1['torn']}\nA1.us_per_write={a1dur:.1f}")

# ── A2a: link() 는 «있는 이름»을 덮지 못한다 (EEXIST) ──
tgt2 = os.path.join(d, "a2a.txt"); open(tgt2, "wb").write(payload(0))
eexist = ok = other = 0
for i in range(200):
    tmp = os.path.join(d, ".a2a.tmp")
    with open(tmp, "wb") as f: f.write(payload(i))
    try:
        os.link(tmp, tgt2); ok += 1
    except OSError as e:
        if e.errno == errno.EEXIST: eexist += 1
        else: other += 1
    os.unlink(tmp)
print(f"A2a.tries=200\nA2a.eexist={eexist}\nA2a.ok={ok}\nA2a.other_err={other}")

# ── A2b: link(tmp → 새 이름) + rename(새 이름 → tgt) 발행, 관찰자 ──
tgt3 = os.path.join(d, "a2b.txt")
open(tgt3, "wb").write(payload(0))
o = start_obs("file", tgt3)
exc = 0
for i in range(ITERS):
    tmp = os.path.join(d, ".a2b.tmp"); new = os.path.join(d, f".a2b.new.{i % 2}")
    with open(tmp, "wb") as f:
        f.write(payload(i)); f.flush(); os.fsync(f.fileno())
    try:
        try: os.unlink(new)
        except FileNotFoundError: pass
        os.link(tmp, new)
        os.replace(new, tgt3)
        os.unlink(tmp)
    except OSError: exc += 1
a2b = stop_obs(o)
print(f"A2b.iters={ITERS}\nA2b.exceptions={exc}\nA2b.samples={a2b['samples']}")
print(f"A2b.missing={a2b['missing']}\nA2b.empty={a2b['empty']}\nA2b.torn={a2b['torn']}")

# ── A3: 디렉터리 swap — replace(tmpdir, existing_dir) 가 되나 / 안 되면 그 대안의 창 ──
def mkdir_n(p, n=5):
    os.makedirs(p)
    for k in range(n):
        open(os.path.join(p, f"f{k}"), "wb").write(b"y" * 512)
dtgt = os.path.join(d, "dsec"); mkdir_n(dtgt)
enotempty = ok = other = 0
for i in range(200):
    src = os.path.join(d, f"dsrc{i}")
    mkdir_n(src)
    try:
        os.replace(src, dtgt); ok += 1   # 성공하면 dtgt 내용이 «새것»으로 바뀐다
        continue
    except OSError as e:
        if e.errno in (errno.ENOTEMPTY, errno.EEXIST): enotempty += 1
        else: other += 1
    for k in range(5):
        try: os.unlink(os.path.join(src, f"f{k}"))
        except FileNotFoundError: pass
    try: os.rmdir(src)
    except OSError: pass
print(f"A3a.tries=200\nA3a.replace_ok_on_existing_dir={ok}\nA3a.enotempty={enotempty}\nA3a.other_err={other}")

# ── A3b: 그래서 실제 swap = rename(현재 → 휴지통) + rename(새 → 현재) → 창이 벌어진다 ──
o = start_obs("dir", dtgt)
for i in range(ITERS):
    new = os.path.join(d, f"dnew{i}")
    mkdir_n(new)
    trash = os.path.join(d, f"dtrash{i}")
    os.rename(dtgt, trash)      # ← 이 사이 target 이 «없다» (비어있지 않은 디렉터리 교체 불가 → 창)
    os.rename(new, dtgt)
    for k in range(5):
        try: os.unlink(os.path.join(trash, f"f{k}"))
        except FileNotFoundError: pass
    try: os.rmdir(trash)
    except OSError: pass
a3b = stop_obs(o)
print(f"A3b.iters={ITERS}\nA3b.samples={a3b['samples']}")
print(f"A3b.missing={a3b['missing']}\nA3b.partial={a3b['partial']}")
PY
python3 "$WORK/atomic.py"

# ── B: 디렉터리 fsync 가부·비용 ─────────────────────────────────────────
cat >"$WORK/dirfsync.py" <<'PY'
import errno, os, statistics, time
WORK = os.environ["WORK"]
d = os.path.join(WORK, "fsync"); os.makedirs(d, exist_ok=True)
N = 300

def try_dir_fsync():
    fd = os.open(d, os.O_RDONLY)
    try:
        os.fsync(fd); return "ok", None
    except OSError as e:
        return "err", (e.errno, os.strerror(e.errno), errno.errorcode.get(e.errno, "?"))
    finally:
        os.close(fd)

verdict, detail = try_dir_fsync()
print(f"B1.dir_open_fsync={verdict}")
print(f"B1.detail={detail}")

# 디렉터리 fd 에 F_FULLFSYNC (macOS 전용 강한 동기화)
fd = os.open(d, os.O_RDONLY)
try:
    import fcntl
    fcntl.fcntl(fd, getattr(fcntl, "F_FULLFSYNC", 51)); print("B2.dir_fullfsync=ok")
except OSError as e:
    print(f"B2.dir_fullfsync=err:{e.errno}:{errno.errorcode.get(e.errno,'?')}")
finally:
    os.close(fd)

def timeit(fn, n=N):
    xs = []
    for _ in range(n):
        t = time.perf_counter(); fn(); xs.append((time.perf_counter() - t) * 1e6)
    xs.sort()
    return statistics.median(xs), xs[int(len(xs) * 0.95)], sum(xs) / len(xs)

def mk(i):
    p = os.path.join(d, f"b{i}.txt")
    with open(p, "wb") as f:
        f.write(b"z" * 256); f.flush(); os.fsync(f.fileno())
    return p

c = [0]
def file_only():
    c[0] += 1; mk(c[0])
def file_plus_dir():
    c[0] += 1; mk(c[0]); try_dir_fsync()
def dir_only():
    try_dir_fsync()
def file_plus_full():
    c[0] += 1; p = mk(c[0])
    fd = os.open(p, os.O_RDONLY)
    try:
        import fcntl; fcntl.fcntl(fd, getattr(fcntl, "F_FULLFSYNC", 51))
    finally: os.close(fd)

for name, fn in (("B3.file_fsync_only", file_only),
                 ("B4.file_fsync_plus_dir_fsync", file_plus_dir),
                 ("B4b.dir_fsync_only", dir_only),
                 ("B5.file_fullfsync_only", file_plus_full)):
    med, p95, mean = timeit(fn)
    print(f"{name}.median_us={med:.1f}\n{name}.p95_us={p95:.1f}\n{name}.mean_us={mean:.1f}")
PY
python3 "$WORK/dirfsync.py"

# ── C: 동시 recv 이중소비 ───────────────────────────────────────────────
cat >"$WORK/concurrent_recv.py" <<'PY'
import json, os, shutil, subprocess, sys, time
WORK, ROUNDS, MBOX_PY = os.environ["WORK"], int(os.environ["ROUNDS"]), os.environ["MBOX_PY"]
base = os.path.join(WORK, "recv"); os.makedirs(base, exist_ok=True)
ME = "nano-probe"
double = single = zero = 0
details = []
for r in range(ROUNDS):
    inbox = os.path.join(base, "inbox"); shutil.rmtree(inbox, ignore_errors=True); os.makedirs(inbox)
    seq = 1000 + r
    row = {"seq": seq, "to": ME, "from": "probe", "body": f"round {r}", "ts": time.time()}
    with open(os.path.join(inbox, "mailbox.jsonl"), "w", encoding="utf-8") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")
    gate = os.path.join(base, "gate"); 
    try: os.unlink(gate)
    except FileNotFoundError: pass
    env = dict(os.environ, FT_MBOX_DIR=inbox); env.pop("FT_MBOX_LEGACY", None)
    cmd = ["sh", "-c", f'while [ ! -f "{gate}" ]; do :; done; exec "{sys.executable}" "{MBOX_PY}" recv "{ME}" --all']
    ps = [subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env,
                           cwd=WORK) for _ in range(2)]
    time.sleep(0.05)
    open(gate, "w").close()
    outs = [p.communicate(timeout=60)[0] for p in ps]
    got = []
    for o in outs:
        seqs = [ln.split("#")[1].split()[0] for ln in o.splitlines()
                if ln.startswith("READ [") and "#" in ln]
        got.append(set(seqs))
    dup = got[0] & got[1]
    if dup: double += 1; kind = "double"
    elif len(got[0]) + len(got[1]) == 1: single += 1; kind = "single"
    elif len(got[0]) + len(got[1]) == 0: zero += 1; kind = "lost"
    else: single += 1; kind = "single"
    landed = [k for k, v in (("A", got[0]), ("B", got[1])) if str(seq) in v]
    details.append(f"{r}\t{kind}\tlanded={','.join(landed) or '-'}\tleft={os.path.getsize(os.path.join(inbox,'mailbox.jsonl'))}")
    if dup: details.append(f"{r}\tA_out={outs[0].strip()[:120]!r}\n{r}\tB_out={outs[1].strip()[:120]!r}")
print(f"C1.rounds={ROUNDS}")
print(f"C1.double_consume={double}")
print(f"C1.single_consume={single}")
print(f"C1.lost={zero}")
print(f"C1.double_rate={double / ROUNDS * 100:.1f}%")
open(os.path.join(base, "details.tsv"), "w").write("\n".join(details) + "\n")
open(os.path.join(WORK, "concurrent_details.txt"), "w").write("\n".join(details) + "\n")
PY
python3 "$WORK/concurrent_recv.py"
[ -f "$WORK/concurrent_details.txt" ] && echo "C1.details=$WORK/concurrent_details.txt"

# ── D: SIGKILL 중 JSONL 재작성 보존 ────────────────────────────────────
cat >"$WORK/kill_rewrite.py" <<'PY'
import json, os, random, signal, subprocess, sys, time

WORK, ROUNDS = os.environ["WORK"], int(os.environ["ROUNDS"])
base = os.path.join(WORK, "kill"); os.makedirs(base, exist_ok=True)
ROWS = 500
random.seed(20261021)

def mkrows(tag):
    return [{"seq": i + 1, "to": "seat", "from": "probe", "body": f"{tag}-{i}"} for i in range(ROWS)]

def write_jsonl(p, rows, atomic_tmp=None, phase_file=None):
    """비원자 = 현행 ft-mbox.py _save 와 같은 꼴(open 'w' + 줄마다 write).
    원자 = 같은 내용을 tmp 에 다 쓰고 fsync 한 뒤 os.replace."""
    if atomic_tmp is None:
        with open(p, "w", encoding="utf-8") as f:
            for r in rows:
                f.write(json.dumps(r, ensure_ascii=False) + "\n"); f.flush()
        return
    with open(atomic_tmp, "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n"); f.flush()
        os.fsync(f.fileno())
    if phase_file: open(phase_file, "w").write("pre-replace")
    os.replace(atomic_tmp, p)
    if phase_file: open(phase_file, "w").write("post-replace")

def verify(p, old_rows, new_rows):
    try:
        raw = open(p, encoding="utf-8").read()
    except FileNotFoundError:
        return {"state": "missing", "valid": 0, "old": 0, "new": 0}
    valid = 0; bad = 0
    for ln in raw.splitlines():
        if not ln.strip(): continue
        try: json.loads(ln); valid += 1
        except Exception: bad += 1
    olds = {(r["seq"], r["body"]) for r in old_rows}
    news = {(r["seq"], r["body"]) for r in new_rows}
    have = set()
    for ln in raw.splitlines():
        if not ln.strip(): continue
        try:
            r = json.loads(ln); have.add((r["seq"], r["body"]))
        except Exception: pass
    if have == olds: state = "old_intact"
    elif have == news: state = "new_intact"
    else: state = "mixed_or_torn"
    return {"state": state, "valid": valid, "bad": bad, "old": len(have & olds), "new": len(have & news)}

def child(kind, path, tmp, phase, rows_json):
    rows = json.loads(rows_json)
    write_jsonl(path, rows, atomic_tmp=(tmp if kind == "atomic" else None), phase_file=phase)

CHILD = os.path.join(WORK, "kill_child.py")
open(CHILD, "w").write(
"""import json, os, sys
kind, path, tmp, phase, rows_json = sys.argv[1:6]
rows = json.loads(rows_json)
def mark(s): open(phase, 'w').write(s)
if kind == 'atomic':
    mark('armed')
    with open(tmp, 'w', encoding='utf-8') as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + '\\n'); f.flush()
        os.fsync(f.fileno())
    mark('pre-replace')
    os.replace(tmp, path)
    mark('post-replace')
else:
    mark('armed')
    with open(path, 'w', encoding='utf-8') as f:
        mark('truncated')
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + '\\n'); f.flush()
    mark('done')
""")


PHASES = ["armed", "truncated", "pre-replace", "post-replace", "done"]

def wait_phase(ph, want, timeout=5.0):
    """phase 파일이 want «이상»에 닿을 때까지 좌시 — 킬 간격을 «재작성 창»으로 좁힌다.
    ★존재만 보고 돌아오면 «armed»에서 바로 킬»해 창을 못 맞춘다(실측)★ — 내용으로 판정한다."""
    idx = PHASES.index(want)
    t0 = time.perf_counter()
    while time.perf_counter() - t0 < timeout:
        if os.path.exists(ph):
            cur = open(ph).read().strip()
            if cur in PHASES and PHASES.index(cur) >= idx:
                return cur
        time.sleep(0.00005)
    return "timeout"


# 캘리브레이션 — 킬 없이 돌려 «armed 이후 창»의 길이를 잰다
cal = {}
for kind in ("non-atomic", "atomic"):
    p = os.path.join(base, f"cal-{kind}.jsonl"); tmp = p + ".tmp"; ph = p + ".phase"
    rows = mkrows("cal")
    write_jsonl(p, mkrows("old"))
    if os.path.exists(ph): os.unlink(ph)
    proc = subprocess.Popen([sys.executable, CHILD, kind, p, tmp, ph, json.dumps(rows)],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    wait_phase(ph, "armed")
    t0 = time.perf_counter()
    proc.wait()
    cal[kind] = (time.perf_counter() - t0) * 1e6
print(f"D0.window_nonatomic_us={cal['non-atomic']:.0f}")
print(f"D0.window_atomic_us={cal['atomic']:.0f}")

# 밴드 = (종류, 킬 기준 단계|None, 시간배율) — 창이 짧아 «단계에 붙여 죽이기»를 별도 밴드로 둔다
BANDS = (("non-atomic", None, 0.6), ("non-atomic", "truncated", None),
         ("atomic", None, 1.0), ("atomic", "pre-replace", None))
for kind, band, scale in BANDS:
    states = {}
    phases = {}
    lost_rows = []
    p = os.path.join(base, f"{kind}{('-' + band) if band else ''}.jsonl"); tmp = p + ".tmp"; ph = p + ".phase"
    old = mkrows("old")
    for r in range(ROUNDS):
        write_jsonl(p, old)
        if os.path.exists(tmp): os.unlink(tmp)
        if os.path.exists(ph): os.unlink(ph)
        new = mkrows(f"new{r}")
        proc = subprocess.Popen([sys.executable, CHILD, kind, p, tmp, ph, json.dumps(new)],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        wait_phase(ph, "armed")                     # ← 여기서부터가 «재작성 창»
        if band:                                    # 지정 뱅크 = 그 단계에 «붙여서» 죽인다
            wait_phase(ph, band)
            time.sleep(random.uniform(0, 0.0004))
        else:
            time.sleep(random.uniform(0, cal[kind] * scale / 1e6))
        try: proc.send_signal(signal.SIGKILL)
        except ProcessLookupError: pass
        proc.wait()
        phase = open(ph).read().strip() if os.path.exists(ph) else "no-marker"
        phases[phase] = phases.get(phase, 0) + 1
        v = verify(p, old, new)
        states[v["state"]] = states.get(v["state"], 0) + 1
        if v["state"] not in ("old_intact", "new_intact"):
            lost_rows.append(v["valid"])
    tag = kind if not band else f"{kind}@{band}"
    print(f"D.{tag}.band={'phase:' + band if band else 'uniform x' + str(scale)}")
    print(f"D.{tag}.rounds={ROUNDS}")
    for ph_, n in sorted(phases.items()): print(f"D.{tag}.phase[{ph_}]={n}")
    for st, n in sorted(states.items()): print(f"D.{tag}.state[{st}]={n}")
    if lost_rows:
        lost_rows.sort()
        print(f"D.{tag}.torn_valid_rows_median={lost_rows[len(lost_rows)//2]}")
        print(f"D.{tag}.torn_valid_rows_min={lost_rows[0]}")
        print(f"D.{tag}.torn_valid_rows_max={lost_rows[-1]}")
    print(f"D.{tag}.rows_total={ROWS}")
PY
python3 "$WORK/kill_rewrite.py"

echo "DONE=1"
