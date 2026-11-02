# pyright: basic
"""ft_trigger_items.py — r1285 기억·트리거 원장: 항목 파일(design/triggers/T####-*.md)·인덱스 읽기 + 상태 파일 도구.
항목 = BYZ 리포 ref(루트 표 state/directive-roots.tsv 의 «*» 줄) 의 design/triggers/T####-<이름>.md · 머리 줄(첫 «## » 앞) `- 칸: 값` · 닫힘 = 머리 «상태: 닫힘» 또는 «## 닫힘» 절의 `- 닫힘:` 줄 하나라도.
외부 명령(git)이 실패하면 이 모듈의 git() 한 곳이 Undecided(«판정 불가») 로 끝낸다(하드 룰 20) · 조용한 빈 값 0(#0 RULE)."""
import calendar
import fcntl
import json
import os
import re
import subprocess
import time
from contextlib import contextmanager
from pathlib import Path

DIR = "design/triggers"
FIELDS = ("번호", "상태", "담당", "조건 출처", "조건 서비스", "조건 글자", "조건 심각도", "할 일")
SEVERITY = ("ERROR", "WARNING", "ANY")
HEAD = re.compile(r"^- ([^:]+):\s*(.*)$")
TS = re.compile(r"(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(\.\d+)?(Z|[+-]\d\d:\d\d)?$")


class Undecided(Exception):
    pass


def now() -> float:
    """시계 = 시험용 시계 파일(스텁이 올림) > FT_NOW(고정) > 실제 시각."""
    f, v = os.environ.get("FT_TRIGGER_CLOCK_FILE"), os.environ.get("FT_NOW")
    return float(Path(f).read_text(encoding="utf-8").strip()) if f else float(v) if v else time.time()


def parse_ts(s: str) -> float:
    m = TS.match(s or "")
    if not m:
        raise Undecided(f"시각 꼴 아님({str(s)[:30]})")
    t = calendar.timegm(time.strptime(m.group(1), "%Y-%m-%dT%H:%M:%S")) + float(m.group(2) or 0)
    if m.group(3) and m.group(3) != "Z":
        t -= (1 if m.group(3)[0] == "+" else -1) * (int(m.group(3)[1:3]) * 3600 + int(m.group(3)[4:6]) * 60)
    return t


def fmt_ts(e: float) -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(e))


def git(repo: str, *args: str, sec: float = 7) -> str:
    """호출마다 7초 + 재시도 1(시간 초과만) · rc≠0 = Undecided 한 줄."""
    for _ in range(2):
        try:
            p = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True, timeout=sec)
        except subprocess.TimeoutExpired:
            continue
        if p.returncode == 0:
            return p.stdout
        raise Undecided(f"git {args[0]} rc={p.returncode} {p.stderr.strip()[:80]}")
    raise Undecided(f"git 상한 넘김({args[0]})")


def repo_ref(R: Path) -> tuple[str, str]:
    f, row = R / ".fable-team/state/directive-roots.tsv", ["*", ".", "origin/main"]
    if f.is_file():
        rows = [ln.split("\t") for ln in f.read_text(encoding="utf-8").splitlines() if ln.strip() and not ln.startswith("#")]
        row = next((x for x in rows if len(x) >= 3 and x[0] == "*"), row)
    return (row[1] if os.path.isabs(row[1]) else str((R / row[1]).resolve())), row[2]


def parse(num: str, path: str, text: str) -> tuple[dict | None, str]:
    head, line, sect = {}, False, None
    for ln in text.splitlines():
        if ln.startswith("## "):
            sect = ln[3:].strip()
        elif sect is None and (m := HEAD.match(ln)):
            head.setdefault(m.group(1).strip(), m.group(2).strip())
        elif sect == "닫힘" and ln.startswith("- 닫힘:"):
            line = True
    bad = next((f for f in FIELDS if not head.get(f)), None) or (
        "번호" if head["번호"] != num else "상태" if head["상태"] not in ("열림", "닫힘") else "조건 심각도" if head["조건 심각도"] not in SEVERITY else "조건 출처" if head["조건 출처"] != "prod-dev-log" else None)
    if bad:
        return None, f"꼴 틀림 {num} {bad}"
    return dict(head, num=num, path=path, closed=head["상태"] == "닫힘" or line, mismatch=(head["상태"] == "닫힘") != line), ""


def index_rows(text: str) -> dict[str, str]:
    rows = {}
    for ln in text.splitlines():
        c = [x.strip() for x in ln.strip().strip("|").split("|")]
        if ln.lstrip().startswith("|") and len(c) > 2 and re.fullmatch(r"T\d{4}", c[0]):
            rows[c[0]] = c[2]
    return rows


def load(repo: str, ref: str) -> tuple[list[dict], list[str]]:
    """(꼴 맞는 항목들, 알림 줄들: 꼴 틀림 · 상태 어긋남 · 인덱스 어긋남)."""
    names = git(repo, "ls-tree", "--name-only", ref, DIR + "/").split()
    idx = index_rows(git(repo, "show", f"{ref}:{DIR}/INDEX.md")) if f"{DIR}/INDEX.md" in names else {}
    items, notes = [], []
    for path in sorted(names):
        m = re.match(r"(T\d{4})-.+\.md$", path.rsplit("/", 1)[-1])
        if not m:
            continue
        it, why = parse(m.group(1), path, git(repo, "show", f"{ref}:{path}"))
        if not it:
            notes.append(why)
            continue
        items.append(it)
        if it["mismatch"]:
            notes.append(f"상태 어긋남 {it['num']}")
        if it["num"] not in idx or idx[it["num"]] != it["상태"]:
            notes.append(f"인덱스 어긋남 {it['num']}" + ("" if it["num"] not in idx else " 상태"))
    return items, notes


def first_commit_ts(repo: str, ref: str, path: str) -> float:
    out = git(repo, "log", "--diff-filter=A", "--format=%cI", "--reverse", ref, "--", path).split()
    if not out:
        raise Undecided(f"항목 파일 첫 커밋 못 찾음({path})")
    return parse_ts(out[0])


def sdir(R: Path) -> Path:
    return R / ".fable-team/state/trigger-watch"


def rjson(p: Path, default):
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except OSError:
        return default
    except ValueError as e:
        raise Undecided(f"상태 파일 깨짐 {p.name}: {e}")


def wjson(p: Path, obj) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(p.suffix + ".tmp")
    tmp.write_text(json.dumps(obj, ensure_ascii=False), encoding="utf-8")
    tmp.replace(p)


@contextmanager
def single_run(sd: Path):
    """공용 잠금(ft_stall_state.single_run 꼴) — 잡혀 있으면 False."""
    sd.mkdir(parents=True, exist_ok=True)
    with open(sd / "lock", "w") as fh:
        try:
            fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            yield False
            return
        yield True
