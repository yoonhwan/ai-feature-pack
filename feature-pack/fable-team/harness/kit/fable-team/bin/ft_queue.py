#!/usr/bin/env python3
"""ft_queue.py — ft-queue.sh 본체(r529): 오빠 큐 줄 하나씩 shown · due · take · add (remind = ft_queue_remind.py)

  python3 ft_queue.py <큐.md> <상태 폴더> <명령> [인자…] — 쓰기 줄의 락은 ft-queue.sh 가 잡는다. 칸 = 머리 이름 · 파서 = ft_queue_state.py.
"""
import os
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import NoReturn
sys.path.insert(0, str(Path(__file__).resolve().parent))
import ft_queue_state as qs  # noqa: E402

qpath, state, cmd, *argv = sys.argv[1:]

NEW = ("번호", "팀", "보여준 시각")
FMT = "%Y-%m-%d %H:%M"
TITLE = "# AUTONOMY-QUEUE — 자율 대리 결정 모드가 대리하지 않은 질문 (오빠 큐)\n\n"
BASE = ("자율", "시각", "종류", "질문", "추천안", "사유", "상태")


def out(msg, rc) -> NoReturn:
    print(msg, file=sys.stderr if msg.startswith("ERROR") else sys.stdout)
    sys.exit(rc)


def opts(a):
    pos, kv, i = [], {}, 0
    while i < len(a):
        if a[i].startswith("--"):
            if i + 1 >= len(a):
                out(f"REJECT 값 없는 인자: {a[i]}", 4)
            kv[a[i][2:]] = a[i + 1]
            i += 2
        else:
            pos.append(a[i])
            i += 1
    return pos, kv


def when(s, what):
    try:
        return datetime.strptime(s, FMT)
    except ValueError:
        out(f"REJECT {what} 꼴 틀림(YYYY-MM-DD HH:MM): {s}", 4)


NOW = when(os.environ["FT_NOW"], "FT_NOW") if os.environ.get("FT_NOW") else datetime.now().replace(second=0, microsecond=0)
san = lambda s: s.replace("\n", " ").replace("|", "/")  # noqa: E731
split = lambda ln: [c.strip() for c in ln.strip().strip("|").split("|")]  # noqa: E731
join = lambda cells: "| " + " | ".join(cells) + " |\n"  # noqa: E731


def rows():
    try:
        recs, err = qs.parse(qpath, qs.load_vocab())
    except qs.ReadError as e:
        out(f"ERROR {e}", 2)
    if err:
        out(f"ERROR 큐 머리 {err[0]}줄: {err[1]}", 2)
    return recs


def lines():
    try:
        return Path(qpath).read_text(encoding="utf-8").splitlines(keepends=True)
    except OSError as e:
        out(f"ERROR 큐 읽기 실패: {qpath}: {e}", 2)


def save(ls):
    tmp = f"{qpath}.tmp.{os.getpid()}"
    try:
        Path(tmp).write_text("".join(ls), encoding="utf-8")
        os.replace(tmp, qpath)
    except OSError as e:
        out(f"ERROR 큐 쓰기 실패: {qpath}: {e}", 5)


def one(n):
    hit = [r for r in rows() if r["cells"].get("번호") == n]
    if len(hit) != 1:
        out(f"ERROR 번호 {n} 줄이 {len(hit)}개 — 정확히 1개여야 한다: {qpath}", 1)
    return hit[0]


def edit(rec, change):
    ls = lines()
    head = split(next(ln for ln in ls if ln.lstrip().startswith("|")))
    cells = split(ls[rec["line"] - 1])
    for name, fn in change.items():
        if name not in head or head.index(name) >= len(cells):
            out(f"ERROR 머리·줄에 «{name}» 칸 없음: {qpath}:{rec['line']}", 2)
        cells[head.index(name)] = san(fn(cells[head.index(name)]))
    ls[rec["line"] - 1] = join(cells)
    save(ls)


def scol(rec):
    col = next((c for c in qs.STATE_COLS if c in rec["cells"]), None)   # 상태 칸보다 짧은 줄 = None
    if col is None and rec["cells"].get("번호", "-") not in ("-", ""):
        out(f"ERROR {rec['cells']['번호']} 줄에 상태 칸 없음: {qpath}:{rec['line']}", 2)
    return col


def due(team=None, minutes=60):
    hits, old = [], 0
    for r in rows():
        c = r["cells"]
        n, t = c.get("번호", "-") or "-", c.get("팀", "-") or "-"
        if n == "-":
            old += r["state"] == "대기" or not c.get(scol(r), "")
            continue
        if team and not (t == team or (team == "planner" and t == "-")):
            continue
        sh = c.get("보여준 시각", "-") or "-"
        age = int((NOW - when(sh, f"{n} 보여준 시각")).total_seconds() // 60) if sh != "-" else None
        if r["state"] == "대기" and r["stop"] != "일시정지" and (age is None or age >= minutes):
            tag = "재질문"
        elif r["state"] == "보류" and r["recheck"] and when(r["recheck"], "재확인") <= NOW:
            tag = "재확인"
        else:
            continue
        hits.append(dict(n=n, team=t, kind=c.get("종류", "-"), shown=sh, age=age, tag=tag, q=c.get("질문", "")[:60], recheck=r["recheck"]))
    return hits, old


def add(kv):
    if not Path(qpath).exists():
        Path(qpath).parent.mkdir(parents=True, exist_ok=True)
        save([TITLE, join(BASE + NEW), "|" + "---|" * len(BASE + NEW) + "\n"])
    ls = lines()
    hi = next((i for i, ln in enumerate(ls) if ln.lstrip().startswith("|")), None)
    if hi is None or hi + 1 >= len(ls):
        out(f"ERROR 큐에 머리·구분 행이 없다: {qpath}", 2)
    head = split(ls[hi])
    if "번호" not in head:
        if head[-1] not in qs.STATE_COLS or any(x in head for x in NEW):
            out(f"ERROR 옛 머리 끝 칸이 상태가 아님 — 칸 셋을 붙일 수 없다: {head}", 2)
        head += NEW
        ls[hi], ls[hi + 1] = join(head), "|" + "---|" * len(head) + "\n"
    nums = [int(x[1:]) for x in (split(ln)[head.index("번호")] for ln in ls[hi + 2:] if ln.lstrip().startswith("|") and len(split(ln)) > head.index("번호")) if re.fullmatch(r"q\d+", x)]
    n = f"q{max(nums, default=0) + 1}"
    val = {"자율": kv["ev"], "시각": NOW.strftime(FMT), "종류": kv["kind"], "질문": kv["q"], "추천안": kv["choice"], "사유": kv["why"],
           "상태": "대기", "처리됨": "대기", "번호": n, "팀": kv.get("team") or "-", "보여준 시각": "-"}
    if ls and not ls[-1].endswith("\n"):
        ls[-1] += "\n"
    ls.append(join([san(val.get(h, "-")) for h in head]))
    save(ls)
    print(f"ADD {n}")


pos, kv = opts(argv)
if cmd in ("shown", "take") and len(pos) != 1:
    out(f"REJECT {cmd} 에는 줄 번호(q<N>) 하나", 4)
if cmd == "shown":
    at = kv.get("at") or NOW.strftime(FMT)
    when(at, "--at")
    edit(one(pos[0]), {"보여준 시각": lambda _: at})
    print(f"SHOWN {pos[0]} at={at}")
elif cmd == "due":
    hits, old = due(kv.get("team"), int(kv.get("min", "60")))
    for h in hits:
        print(f"DUE {h['n']} team={h['team']} kind={h['kind']} shown={h['shown'].replace(' ', 'T')} age={'-' if h['age'] is None else h['age']} tag={h['tag']} q={h['q']}")
    print(f"QUEUE-DUE n={len(hits)} old={old}")
elif cmd == "take":
    for k in ("value", "by", "verdict"):
        if not kv.get(k):
            out(f"REJECT take 에는 --{k} 필요", 4)
    if not kv["verdict"].isdigit():
        out(f"REJECT 판정 번호가 숫자 아님: {kv['verdict']}", 4)
    r = one(pos[0])
    if r["state"] not in ("대기", "보류"):
        out(f"REJECT {pos[0]} 은 이미 «{r['cells'][scol(r)]}» — 대기·보류 줄만 꺼낸다", 1)
    edit(r, {scol(r): lambda _: f"진행 — {kv['by']}", "사유": lambda s: f"{s} · 오빠 값: {kv['value']} (판정 {kv['verdict']})"})
    c = r["cells"]
    print(f"RESUME {pos[0]} team={c.get('팀', '-')} kind={c.get('종류', '-')} → {kv['by']} 가 «{c.get('질문', '')[:40]}» 를 오빠 값으로 이어 한다 · 끝나면 상태 칸 «완료 — 판정 {kv['verdict']}»")
elif cmd == "remind":
    for k in ("rosters", "mbox"):
        if not kv.get(k):
            out(f"REJECT remind 에는 --{k} 필요", 4)
    import ft_queue_remind
    ft_queue_remind.run(kv, due(None, int(kv.get("min", "60")))[0], NOW, state, out)
else:
    for k in ("ev", "kind", "q", "choice", "why"):
        if k not in kv:
            out(f"REJECT add 에는 --{k} 필요", 4)
    add(kv)
