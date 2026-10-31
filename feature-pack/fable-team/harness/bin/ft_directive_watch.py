#!/usr/bin/env python3
# pyright: basic
"""ft_directive_watch.py status|tick [--now <ISO|epoch>] — 오빠 지시마다 «담당 카드가 있고 움직이는가» (r1212 · Issue #5342 · 사전 DA ③ APPROVE).
후보 = 판정 원장을 번호로 접어 done(무효 포함)·닫음 표(state/directive-closed.tsv: n·사유·좌석·시각) 제외 · 남은 new 중 제목에 «오빠» 와 slack ts.
담당 = 카드의 «- 지시: 판정 N[, 판정 M]» 줄만 · 카드는 카드 루트 표(state/directive-roots.tsv: 팀·리포·ref·카드 폴더)의 ref 에서 읽는다(워크트리 무관).
움직임 = max(카드 파일 마지막 커밋 · 나노 가지 nano/<stem 앞 40자> 의 base 밖 커밋) · 쪽지·경보·상태 보고는 움직임 아님 · git 은 전부 --until=<평가 시각>.
판정: 담당 0 + 판정 뒤 60분 넘음 = 담당 없음 · 대기·진행 담당의 마지막 움직임이 6시간 넘음 = 멈춤 · 담당 전부 완성·아카이브 = 닫힘.
머리 «담당 없는 오빠 지시 N · 멈춘 오빠 지시 M · 판본 <stamp>» → stamps.tsv 1줄 · rc 0 = 둘 다 0 · 1 = 하나라도 · 3 = «지시 감시 판정 불가 · <사유>» 1줄.
--now 가 지금보다 앞 = 가상 시각: 운영 증분 캐시·stamps·경보 표식 읽기·쓰기 0. tick = status + planner·담당 팀 master 에 [긴급] (QUEUED 뒤 표식 · 같은 목록 60분 0통).
env FT_ROOT · FT_DIRECTIVE_NOW · FT_MBOX_SH · FT_DIRECTIVE_FROM · FT_DIRECTIVE_NANO_REPOS(:) · FT_DIRECTIVE_GIT_SEC(7) · _TICK_SEC(20) · _FIRST_SEC(60)."""
import hashlib
import json
import os
import re
import subprocess
import sys
import time
from fnmatch import fnmatch
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ft_penalty import root  # noqa: E402

SLACK_TS = re.compile(r"(?<!\d)1\d{9}(?:\.\d{1,6})?(?!\d)")
OPEN, CLOSED = ("대기", "진행"), ("완성", "아카이브")
OWNER_S, STALL_S, MUTE_S = 60 * 60, 6 * 3600, 3600
DEFAULT_ROOTS = [["*", ".", "origin/main", "design/teams/*/indices"], ["harness", ".", "origin/ops/main-base", "design/harness/indices"]]


class Undecided(Exception):
    pass


class Git:
    """리포 호출마다 7초 + 재시도 1 · 전체 예산(틱 20초 · 첫 실행·가상 시각 60초) — 넘으면 Undecided(조용한 빈 값 0)."""

    def __init__(self, budget: float) -> None:
        self.end, self.per = time.monotonic() + budget, float(os.environ.get("FT_DIRECTIVE_GIT_SEC") or 7)

    def __call__(self, repo: str, *args: str, long: bool = False, ok: tuple = (0,)) -> str:
        for _ in range(2):
            left = self.end - time.monotonic()
            if left <= 0:
                break
            try:
                p = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True, timeout=left if long else min(self.per, left))
            except subprocess.TimeoutExpired:
                continue
            if p.returncode in ok:
                return p.stdout
            raise Undecided(f"git {args[0]} rc={p.returncode} {repo} {p.stderr.strip()[:80]}")
        raise Undecided(f"git 상한 넘김({args[0]} {repo})")


def tsv(path: Path) -> list[list[str]]:
    if not path.is_file():
        return []
    return [ln.split("\t") for ln in path.read_text(encoding="utf-8").splitlines() if ln.strip() and not ln.startswith("#")]


def epoch(ts: str) -> float | None:
    try:
        return time.mktime(time.strptime(ts[:19], "%Y-%m-%dT%H:%M:%S"))
    except (TypeError, ValueError):
        return None


def hhmm(t: float) -> str:
    return time.strftime("%m-%d %H:%M:%S", time.localtime(t))


def until(now: float) -> str:
    return "--until=" + time.strftime("%Y-%m-%d %H:%M:%S +0000", time.gmtime(now))


def candidates(st: Path, now: float) -> tuple[list[tuple[str, float, dict]], dict]:
    f = st / "verdicts.jsonl"
    try:
        rows = [json.loads(ln) for ln in f.read_text(encoding="utf-8").splitlines() if ln.strip()]
    except (OSError, ValueError) as e:
        raise Undecided(f"판정 원장 못 읽음 {f} {e.__class__.__name__}")
    closed, done, new = {r[0] for r in tsv(st / "directive-closed.tsv")}, set(), {}
    for r in rows:
        t, n = epoch(r.get("ts", "")), str(r.get("n"))
        if t is None or t > now:  # 평가 시각 뒤 행은 없던 것
            continue
        if r.get("ev") == "done":
            done.add(n)
        elif r.get("ev") == "new" and n not in new:
            new[n] = (t, r)
    title = lambda r: r.get("title") or ""  # noqa: E731
    out = [(n, t, r) for n, (t, r) in new.items() if n not in done | closed and "오빠" in title(r) and SLACK_TS.search(title(r))]
    return out, rows[-1] if rows else {}


class Watch:
    def __init__(self, R: Path, now: float, virtual: bool) -> None:
        self.R, self.now, self.virtual = R, now, virtual
        self.st, self.wd = R / ".fable-team/state", R / ".fable-team/state/directive-watch"
        self.roots = [r[:4] for r in (tsv(self.st / "directive-roots.tsv") or DEFAULT_ROOTS) if len(r) >= 4]
        first = virtual or any(not self.cache(r).is_file() for r in self.roots)
        self.git = Git(float(os.environ.get("FT_DIRECTIVE_FIRST_SEC" if first else "FT_DIRECTIVE_TICK_SEC") or (60 if first else 20)))
        self.nano_refs: dict[str, set[str]] = {}

    def repo(self, r: list[str]) -> str:
        return r[1] if os.path.isabs(r[1]) else str((self.R / r[1]).resolve())

    def cache(self, r: list[str]) -> Path:
        return self.wd / ("commits-" + hashlib.sha1("\t".join(r[1:4]).encode()).hexdigest()[:12] + ".tsv")

    def card_times(self, r: list[str], tip: str) -> dict[str, float]:
        """카드 stem → 마지막 커밋 시각(폴더를 옮겨도 stem 으로 잇는다) · 운영 = 캐시의 «마지막 sha..tip» 만 · 가상 시각 = 캐시 무시·쓰기 0."""
        times: dict[str, float] = {}
        last, c = None, self.cache(r)
        if not self.virtual and c.is_file():
            rows = tsv(c)
            last = next((x[1] for x in rows if x[0] == "@sha"), None)
            times = {x[0]: float(x[1]) for x in rows if x[0] != "@sha"}
        span = f"{last}..{tip}" if last else tip
        out = self.git(self.repo(r), "log", until(self.now), "--format=@%ct", "--name-only", span, "--", r[3].split("*")[0].rstrip("/"), long=last is None)
        ct = 0.0
        for ln in out.splitlines():
            if ln.startswith("@"):
                ct = float(ln[1:])
            elif ln.endswith(".md") and fnmatch(ln, r[3] + "/*"):
                stem = ln.rsplit("/", 1)[-1][:-3]
                times[stem] = max(times.get(stem, 0.0), ct)
        if not self.virtual:
            self.wd.mkdir(parents=True, exist_ok=True)
            tmp = c.with_suffix(".tmp")
            tmp.write_text(f"@sha\t{tip}\n" + "".join(f"{k}\t{v:.0f}\n" for k, v in sorted(times.items())), encoding="utf-8")
            tmp.replace(c)
        return times

    def links(self) -> tuple[dict[str, list[dict]], list[str]]:
        """판정 번호 → 담당 카드(대기·진행·완성·아카이브 폴더 · 평가 시각에 커밋이 있던 카드만) · 근거·배경 인용은 세지 않는다."""
        found: dict[str, list[dict]] = {}
        tips = []
        for r in self.roots:
            repo = self.repo(r)
            tip = self.git(repo, "rev-list", "-1", until(self.now), r[2]).strip()  # 평가 시각 이하 ref 커밋 — 카드 본문·폴더도 여기서(미래 이동 0)
            tips.append(tip)
            if not tip:
                continue
            times = self.card_times(r, tip)
            depth, star = len(r[3].split("/")), r[3].split("/").index("*") if "*" in r[3] else -1
            hits = self.git(repo, "grep", "-I", "-e", "^- 지시:", tip, "--", r[3].split("*")[0].rstrip("/"), ok=(0, 1))
            for ln in hits.splitlines():
                path, _, text = ln[len(tip) + 1:].partition(":")
                parts = path.split("/")
                if not (path.endswith(".md") and fnmatch(path, r[3] + "/*") and len(parts) == depth + 2 and parts[depth] in OPEN + CLOSED):
                    continue
                stem = parts[-1][:-3]
                if stem not in times:
                    continue
                card = dict(team=parts[star] if r[0] == "*" else r[0], stem=stem, state=parts[depth], moved=times[stem], repo=repo, ref=r[2])
                for n in dict.fromkeys(re.findall(r"판정\s*(\d+)", text.split(":", 1)[1] if ":" in text else "")):
                    found.setdefault(n, []).append(card)
        return found, tips

    def nano_moved(self, card: dict) -> float:
        """나노 가지 nano/<stem 앞 40자> 의 base 밖 커밋 중 평가 시각 이하 마지막 · 카드 리포 base = 카드 ref · 다른 리포 = origin/main."""
        env = os.environ.get("FT_DIRECTIVE_NANO_REPOS")
        pack = Path.home() / "Project/ai-feature-pack"
        repos = [str(Path(x).resolve()) for x in env.split(":") if x] if env else list(dict.fromkeys([self.repo(r) for r in self.roots] + ([str(pack)] if (pack / ".git").exists() else [])))
        best = card["moved"]
        for repo in filter(None, repos):
            if repo not in self.nano_refs:
                self.nano_refs[repo] = set(self.git(repo, "for-each-ref", "--format=%(refname)", "refs/heads/nano", "refs/remotes/origin/nano").split())
            for ref in (f"refs/heads/nano/{card['stem'][:40]}", f"refs/remotes/origin/nano/{card['stem'][:40]}"):
                if ref in self.nano_refs[repo]:
                    base = card["ref"] if repo == card["repo"] else "origin/main"
                    out = self.git(repo, "log", "-1", "--format=%ct", until(self.now), ref, "--not", base).strip()
                    best = max(best, float(out or 0))
        return best

    def evaluate(self) -> tuple[list[tuple], str, str]:
        cands, last = candidates(self.st, self.now)
        found, tips = self.links()
        rows = []
        for n, t, r in cands:
            mine = found.get(n, [])
            if not mine:
                if self.now - t > OWNER_S:
                    rows.append(("담당 없음", n, t, r, None))
                continue
            opn = [c for c in mine if c["state"] in OPEN]
            if opn and self.now - max(c["moved"] for c in opn) > STALL_S:
                for c in opn:
                    c["moved"] = self.nano_moved(c)
                c = max(opn, key=lambda x: x["moved"])
                if self.now - c["moved"] > STALL_S:
                    rows.append(("멈춤", n, t, r, c))
        raw = json.dumps(last, ensure_ascii=False) + "".join(
            (self.st / f).read_text(encoding="utf-8") if (self.st / f).is_file() else "" for f in ("directive-closed.tsv", "directive-roots.tsv")) + "".join(tips)
        stamp = f"{int(self.now)}-{hashlib.sha1(raw.encode()).hexdigest()[:8]}"
        return rows, stamp, str(last.get("ts", "?"))[5:16].replace("T", " ")


def render(rows: list[tuple], stamp: str, last_ts: str) -> list[str]:
    n_own, n_stall = sum(1 for x in rows if x[0] == "담당 없음"), sum(1 for x in rows if x[0] == "멈춤")
    out = [f"담당 없는 오빠 지시 {n_own} · 멈춘 오빠 지시 {n_stall} · 판본 {stamp} · 원장 끝 {last_ts}"]
    for kind, n, t, r, c in rows:
        title = (r.get("title") or "")[:60]
        out.append(f"담당 없음 판정 {n} · {hhmm(t)} · {','.join(r.get('teams') or []) or '-'} · {title}" if c is None
                   else f"멈춤 판정 {n} · {c['stem']} · 마지막 움직임 {hhmm(c['moved'])} · {title}")
    return out


def team_master(R: Path, team: str) -> str | None:
    f = R / ".fable-team" / ("seats.json" if team == "v65" else f"seats-{team}.json")
    try:
        m = json.loads(f.read_text(encoding="utf-8")).get("_master")
    except (OSError, ValueError):
        return None
    return m if isinstance(m, str) and m else None


def tick(R: Path, now: float, rows: list[tuple] | None, why: str, lines: list[str]) -> list[str]:
    """rc0 = 표식 지움 · rc1 = 받는이마다 목록 해시 표식(QUEUED 뒤에만) · rc3 = planner 판정 불가 1통(따로 표식 · 60분 억제)."""
    wd = R / ".fable-team/state/directive-watch"
    mf = wd / "alarm.json"
    if rows == []:
        mf.unlink(missing_ok=True)
        return ["tick 경보 0 · 표식 지움"]
    marks = json.loads(mf.read_text(encoding="utf-8")) if mf.is_file() else {}
    planner, log = team_master(R, "planner"), []
    mbox, me = os.environ.get("FT_MBOX_SH") or str(R / ".fable-team/comm/mbox.sh"), os.environ.get("FT_DIRECTIVE_FROM", "ft-directive-watch")
    if rows is None:
        groups = {planner: ("_undecided", [f"[긴급] 지시 감시 판정 불가 — {why} (ft-directive-watch · 숫자로 읽지 말 것)"])}
    else:
        groups = {}
        for row, ln in zip(rows, lines[1:]):
            for to in dict.fromkeys([planner] + [team_master(R, t) for t in ([row[4]["team"]] if row[4] else row[3].get("teams") or [])]):
                groups.setdefault(to, (to, []))[1].append(ln)
    for to, (key, body) in groups.items():
        if not to:
            log.append("tick 받는이 없음(명부 _master 못 읽음) · 0통")
            continue
        h = hashlib.sha1("\n".join(body).encode()).hexdigest()[:12]
        m = marks.get(key) or {}
        if m.get("h") == h and now - float(m.get("t", 0)) < MUTE_S:
            continue
        text = body[0] if rows is None else "\n".join([f"[긴급] 지시 멈춤 — {lines[0].split(' · 판본')[0]} · 담당 카드 움직이거나 닫음 표에 1줄 (ft-directive-watch)", *body[:3], *([f"외 {len(body) - 3}건"] if len(body) > 3 else [])])
        p = subprocess.run(["bash", mbox, "send", to, me, text], capture_output=True, text=True, timeout=7)
        if "QUEUED" in p.stdout + p.stderr:
            marks[key] = {"h": h, "t": now}
            log.append(f"tick 1통 → {to}")
        else:
            log.append(f"tick 발신 실패 → {to} rc={p.returncode} · 다음 틱 다시")
    wd.mkdir(parents=True, exist_ok=True)
    mf.write_text(json.dumps(marks, ensure_ascii=False), encoding="utf-8")
    return log


def main(argv: list[str]) -> int:
    if not argv or argv[0] not in ("status", "tick"):
        print("사용: ft-directive-watch.sh status|tick [--now <YYYY-MM-DDTHH:MM:SS|epoch>]")
        return 2
    real, v = time.time(), argv[argv.index("--now") + 1] if "--now" in argv[:-1] else os.environ.get("FT_DIRECTIVE_NOW")
    now = real if not v else float(v) if re.fullmatch(r"\d+(\.\d+)?", v) else epoch(v)
    if now is None:
        print(f"지시 감시 판정 불가 · --now 꼴 아님({v})")
        return 3
    virtual, R = now < real, root()  # 유예 0 — 지금보다 앞이면 운영 파일 읽기·쓰기 0
    if argv[0] == "tick" and virtual:
        print("지시 감시 판정 불가 · tick 은 가상 시각을 받지 않는다")
        return 3
    try:
        rows, stamp, last_ts = Watch(R, now, virtual).evaluate()
    except (Undecided, OSError) as e:
        why = str(e) if isinstance(e, Undecided) else f"{e.__class__.__name__} {e}"
        print(f"지시 감시 판정 불가 · {why}")
        if argv[0] == "tick":
            print("\n".join(tick(R, now, None, why, [])))
        return 3
    lines = render(rows, stamp, last_ts)
    print("\n".join(lines))
    if not virtual:
        wd = R / ".fable-team/state/directive-watch"
        wd.mkdir(parents=True, exist_ok=True)
        n_own, n_stall = (sum(1 for x in rows if x[0] == k) for k in ("담당 없음", "멈춤"))
        with open(wd / "stamps.tsv", "a", encoding="utf-8") as fh:
            fh.write(f"{stamp}\t{n_own}\t{n_stall}\n")
    if argv[0] == "tick":
        print("\n".join(tick(R, now, rows, "", lines)))
    return 1 if rows else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
