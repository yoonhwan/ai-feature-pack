"""ft-tick-line.sh 의 본체 — 사용법·출력 규약은 ft-tick-line.sh 머리말이 정본. env 는 그 셸이 채워 넘긴다(HERE·SEAT·TEAM·FT_ROOT·LINT_OUT …)."""
import datetime as dt
import glob
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, os.environ["HERE"])
import ft_board_env as env  # noqa: E402
from ft_board_mail import PREFIX, Mail  # noqa: E402
from ft_board_seat import SeatCells  # noqa: E402
import ft_tick_line_io as tio  # noqa: E402

MAX_SEATS, MAX_LINES, MAX_CHARS, SHOWN, KEEP_FILES = 8, 5, 500, 3, 20
PARKED = {"closed", "stopped", "stop-ready"}
ATTN = re.compile(r"^\[(결정|HIL|긴급|합치기|정지 레디|완료)")
seat, root, now = os.environ["SEAT"], Path(os.environ["FT_ROOT"]), env.now()
iso = now.isoformat(timespec="seconds")
seat_unknown, other_unknown, details = [], [], []


def note_unknown(reason: str) -> None:
    other_unknown.append(reason); details.append(f"UNKNOWN {reason}")


def write_full() -> Path:
    out = Path(os.environ["FT_TICK_OUT_DIR"]); out.mkdir(parents=True, exist_ok=True)
    key_ = re.sub(r"[^A-Za-z0-9#_.-]", "_", seat)
    path = out / f"{key_}-{now.strftime('%Y%m%dT%H%M%S')}.txt"
    tmp = path.with_suffix(".tmp"); tmp.write_text("\n".join(details) + "\n", encoding="utf-8"); os.replace(tmp, path)
    for old in sorted(out.glob(f"{key_}-*.txt"))[:-KEEP_FILES]:
        old.unlink()
    return path


def finish(head: str) -> None:
    """상한(≤5줄·≤500자)을 첫 줄+행+경로 줄 «합쳐서» 집행 — 넘치면 행부터 접고 전체는 파일."""
    shown = details[:SHOWN] if len(details) > MAX_LINES - 1 else details[:]
    path = write_full() if len(shown) < len(details) else None

    def out_lines():
        return [head] + shown + ([f"… 전체 {len(details)}행 → {path}"] if path else [])
    while shown and len("\n".join(out_lines())) > MAX_CHARS:
        shown.pop()
        path = path or write_full()
    print("\n".join(out_lines()))


def roster_of(name: str):
    files = [os.environ["TEAM"]] if os.environ.get("TEAM") else sorted(glob.glob(os.environ["FT_SEATS_GLOB"]))
    for p in files:
        try:
            d = json.loads(Path(p).read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if isinstance(d, dict) and isinstance(d.get(name), dict) and not d[name].get("_replaced_by"):
            return p, d
    return None, None


path, seats = roster_of(seat)
if seats is None:
    finish(f"TICK {seat} @{iso} UNKNOWN(명부에 없음: {seat})")
    sys.exit(0)
stem = Path(path).stem
key = "v65" if stem == "seats" else stem.removeprefix("seats-")

try:
    r = subprocess.run(shlex.split(os.environ.get("FT_TMUX_LS_CMD", "tmux ls -F #{session_name}")), capture_output=True, text=True, timeout=30)
    if r.returncode != 0 and not ("no server running" in r.stderr or "no sessions" in r.stderr):
        raise RuntimeError(f"rc={r.returncode}")
    alive = {s.strip() for s in r.stdout.splitlines() if s.strip()}
except (RuntimeError, OSError, subprocess.TimeoutExpired) as e:
    finish(f"TICK {seat} @{iso} UNKNOWN(tmux ls 실패: {e})")
    sys.exit(0)

# ① 내 팀 활성 좌석 라이브 측정 (나 제외 · ≤8) — 정지 분은 틱 시점 now−턴 끝
live = sorted(n for n, v in seats.items() if not n.startswith("_") and isinstance(v, dict) and n != seat and n in alive
              and not v.get("_replaced_by") and v.get("role") not in PARKED)
if len(live) > MAX_SEATS:
    note_unknown(f"좌석 상한 {MAX_SEATS} 초과 {len(live) - MAX_SEATS}석 미측정")
    live = live[:MAX_SEATS]
io_stats = tio.Stats()
tio.install(Path(os.environ["FT_TICK_OUT_DIR"]), io_stats)
cells = SeatCells({n: seats[n] for n in live}, alive, Mail(root), now)
for n, c in cells.all().items():
    if c["text"].startswith(("확인 불가", "대기(분")):
        seat_unknown.append(n); details.append(f"UNKNOWN {n} {c['text']}")
stall = done_work = done_unproc = 0
io_stats.save()
for r_ in cells.rows():
    if re.fullmatch(r"\d+분", r_[0]):
        stall += 1; details.append(f"정지 {r_[0]} {r_[1]} (턴 끝 {r_[2]})")
    elif r_[0] == "완료 뒤 작업":
        done_work += 1; details.append(f"완료 뒤 작업 {r_[1]} {r_[2]}")
    else:
        done_unproc += 1; details.append(f"완료 선언 미처리 {r_[1]} ← {r_[2]} {r_[3]}")

# ② 큐 — 내 앞 쪽지 머리별 건수 + 주의 seq
queue, heads, attn = 0, {}, []
mb = root / ".fable-team" / "comm" / "mailbox.jsonl"
try:
    for n, line in enumerate(mb.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            rec = json.loads(line)
        except ValueError:
            raise RuntimeError(f"{n}행 해석 실패")
        if rec.get("to") != seat:
            continue
        queue += 1
        body = PREFIX.sub("", str(rec.get("body", "")), count=1)
        head = (re.match(r"\[[^\]\n]*\]", body) or [None])[0] or "(머리 없음)"
        heads[head] = heads.get(head, 0) + 1
        if ATTN.match(head):
            attn.append(f"#{rec.get('seq')}{head}")
except (OSError, RuntimeError) as e:
    queue = None
    note_unknown(f"큐 읽기 실패: {e}")
if heads:
    details.append("큐 머리 " + " · ".join(f"{h} {c}" for h, c in sorted(heads.items(), key=lambda x: -x[1])))
if attn:
    details.append("큐 주의 " + " ".join(attn[:6]) + (f" … 외 {len(attn) - 6}" if len(attn) > 6 else ""))

# ③ 명부 불일치 — ft-seats-lint.sh 출력(첫 줄 + 행)
lint = os.environ.get("LINT_OUT", "").splitlines()
m = re.match(r"불일치 (\d+) \(UNKNOWN (\d+)\)", lint[0]) if lint else None
if m:
    mism = int(m.group(1))
    if int(m.group(2)):
        note_unknown(f"명부 UNKNOWN {m.group(2)}")
    details += [x.strip() for x in lint[1:] if x.strip()]
else:
    mism = None
    note_unknown("ft-seats-lint 출력 해석 실패")

# ④ 스냅샷 — 개입 대상이 아닌 값(관찰 중 · 타 팀 정지)에만 쓴다
snap, observing, other = None, None, None
days = sorted(glob.glob(str(root / ".fable-team" / "state" / "board" / "????-??-??")), reverse=True)
for d in days:
    fs = sorted(Path(d).glob("*.json"), key=lambda p: (p.name[:6], p.stat().st_mtime_ns))
    if fs:
        snap = fs[-1]; break
snap_iso = age = None
if snap is None:
    note_unknown("스냅샷 없음")
else:
    try:
        data = json.loads(snap.read_text(encoding="utf-8"))
        st = dt.datetime.strptime(f"{snap.parent.name} {snap.name[:6]}", "%Y-%m-%d %H%M%S")
        age = int((now - st).total_seconds()); snap_iso = st.isoformat(timespec="seconds")
        observing = sum(1 for i in data["issues"] if i.get("state") == "open" and "status:observing" in i.get("labels", []))
        other = sum(len(t["stalled"]) for t in data["teams"] if t.get("key") != key)
        if age < 0:
            note_unknown("스냅샷 시각이 미래")
    except (OSError, ValueError, KeyError, TypeError):
        note_unknown("스냅샷 해석 실패")

src = f"turn-live({len(live)})+" + (f"snapshot@{snap_iso}" if snap_iso else "snapshot=없음")
head = f"TICK {seat} @{iso} age={age if age is not None else '?'}s src={src}"
q = "?" if queue is None else queue
tail = f"큐 {q} 불일치 {'?' if mism is None else mism} 관찰중 {'?' if observing is None else observing} 타팀정지 {'?' if other is None else other}"
if seat_unknown or other_unknown:
    head += " UNKNOWN " + "+".join(x for x in (f"{len(seat_unknown)}석" if seat_unknown else "", f"{len(other_unknown)}건" if other_unknown else "") if x) + f" 정지 {stall} 완료뒤작업 {done_work} 미처리 {done_unproc} {tail}"
elif stall or done_work or done_unproc or queue or mism:
    head += f" 정지 {stall} 완료뒤작업 {done_work} 미처리 {done_unproc} {tail}"
else:
    head += f" 0/0/0 {tail} — 할 일 없음"
finish(head)
print(io_stats.line(), file=sys.stderr)  # 시험·DA 가 재는 자리: 읽은 jsonl 수·바이트·ms·경로 해석 수
