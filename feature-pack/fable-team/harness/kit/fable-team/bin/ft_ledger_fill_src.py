"""ft_ledger_fill_src — 원장 자동 채움(r851)의 입력 원천: 팀 카드 · [완료]·[착지] 쪽지 · main 착지 커밋 · 질문 장부 · 승인 h 대기 · AUTONOMY-QUEUE.

모든 읽기 실패는 FillError(조용한 0 금지) — 부르는 쪽(ft_ledger_fill_tables)은 그 표만 갱신 0 으로 둔다.
landed_commits 는 뉴스(ft_news_html.commits)와 같은 함수 — 기준선 뒤 착지 «전부»(15개 상한 0 · r851 ⓓ).
"""
from __future__ import annotations

import json
import os
import re
import subprocess
from datetime import datetime, timedelta
from pathlib import Path

LOCAL_S = 7.0  # 로컬 git·도구 1회 상한(7초 룰)
CAP_S = 70.0  # 크기 비례 상한 천장(하드 룰 12)
LOG_BASE = 100  # 완성 카드 git log 기준량 = 창 안 커밋 100개당 7초(r870 1-b)
MAILBOX_TAIL = 262144
DONE_MARK = ("[완료", "[착지")
_TEAM = re.compile(r"[a-z0-9][a-z0-9_-]*")
_FORM = re.compile(r"^(\$FT_HARNESS_ROOT/|\$\{FT_HARNESS_ROOT\}/)?design/(teams/)?[a-z0-9][a-z0-9_-]*/$")


class FillError(RuntimeError):
    pass


def _blank(raw) -> bool:
    return isinstance(raw, str) and not raw.strip()


def strict_rows(name: str, rows, form, skip=_blank) -> list:
    """r851 r4 — 원천 읽기 공통 1곳: (위치, 원문)마다 skip(빈 줄·그 원천에 정의된 주석 꼴)이 아니면 form(원문)이 항목(None 아님)이어야 한다.
    한 줄이라도 어긋나면 그 원천 전체 = FillError(첫 어긋난 줄 위치·앞 60자) — 걸러내기(불일치 행 버리고 나머지 사용) 0(#0 RULE)."""
    out = []
    for at, raw in rows:
        if skip(raw):
            continue
        item = form(raw)
        if item is None:
            raise FillError(f"{name} 꼴 틀림 — 줄 {at}: {str(raw)[:60]!r} (원천 전체 갱신 0 · 걸러내기 0)")
        out.append(item)
    return out


def _md_skip(raw: str) -> bool:
    return not raw.strip() or raw.lstrip().startswith(("#", ">"))  # 마크다운 원천의 주석 꼴 = 빈 줄 · 머리(#) · 인용(>)


def table_rows(name: str, text: str, form, prose: bool = False) -> tuple[list[str], list]:
    """마크다운 원천의 표 1개 → (머리 칸, 행 항목) — 표 = 연속한 `|` 줄 블록 1개(머리 · 구분 · 행) · 행마다 form 이 항목이어야 함.
    prose=False = 표 밖 줄도 주석 꼴(빈 줄·#·>)만 · prose=True = 표 앞 글줄 허용, 표 바로 뒤는 빈 줄·끝, 그 뒤 `|` 줄 0(표 2개·깨진 행 = 오류)."""
    lines = text.splitlines()
    a = next((i for i, ln in enumerate(lines) if ln.lstrip().startswith("|")), None)
    if a is None:
        raise FillError(f"{name} 에 표가 없다(원천 손상)")
    b = next((i for i in range(a, len(lines)) if not lines[i].lstrip().startswith("|")), len(lines))
    after = list(enumerate(lines[b:], b + 1))
    if prose:
        strict_rows(name, after[:1], lambda s: None)
        strict_rows(name, after, lambda s: None if s.lstrip().startswith("|") else s, skip=lambda s: False)
    else:
        strict_rows(name, [*enumerate(lines[:a], 1), *after], lambda s: None, skip=_md_skip)
    rows = [_cells(ln) for ln in lines[a:b]]
    if len(rows) < 2 or not all(re.fullmatch(r":?-+:?", c) for c in rows[1]):
        raise FillError(f"{name} 표 머리 아래 구분 줄 없음 — 줄 {a + 2}")
    return rows[0], strict_rows(name, enumerate(lines[a + 2:b], a + 3), form)


def _cells(ln: str) -> list[str]:
    return [c.strip() for c in ln.strip().strip("|").split("|")]


GIT = ("git", "-c", "core.quotepath=off")  # r851 r3 ② — 경로 출력 = 날 UTF-8(사용자 git 설정과 무관 · 한글 카드 경로 비교)


def git(repo: Path, *a: str, timeout: float = LOCAL_S) -> str:
    try:
        done = subprocess.run([*GIT, "-C", str(repo), *a], capture_output=True, text=True, encoding="utf-8", timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise FillError(f"git {a[0]} 실행 실패: {e}") from e
    if done.returncode != 0:
        raise FillError(f"git {a[0]} 실패: {done.stderr.strip()[:200]}")
    return done.stdout


_BRANCH = re.compile(r"ledger/[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)*")


def branch() -> str:
    """원장 사본 브랜치(r851 r2 · planner 결정 ② — 데몬은 이 브랜치에만 커밋 · main 착지는 planner 면제 경로 주기 1회).
    r851 r3 ① — `ledger/` 로 시작하는 이름만(main·HEAD·그 밖 = FillError · env 로 우회 0 · `..`·`.lock` 끝 거절)."""
    name = os.environ.get("FT_LEDGER_FILL_BRANCH") or "ledger/auto"
    if not _BRANCH.fullmatch(name) or ".." in name or name.endswith((".lock", ".")):
        raise FillError(f"원장 사본 브랜치는 ledger/ 로 시작하는 이름만 — 거절: {name!r}(push 0)")
    return name


def sized(n: int, base: int) -> float:
    """크기 아는 로컬 배치 상한 = min(7초 × ceil(n/base), 70초) — 최소 7초(하드 룰 12 · r870 1-b)."""
    return min(LOCAL_S * max(1, -(-n // base)), CAP_S)


def _has(repo: Path, ref: str) -> bool:
    try:
        return subprocess.run([*GIT, "-C", str(repo), "rev-parse", "--verify", "-q", f"{ref}^{{commit}}"], capture_output=True, timeout=LOCAL_S, check=False).returncode == 0
    except (OSError, subprocess.TimeoutExpired) as e:  # r870 — 시간 초과가 뉴스 틱을 죽이지 않게(FillError = 원장 채움만 0)
        raise FillError(f"git rev-parse 실행 실패: {e}") from e


def ancestor(repo: Path, a: str, b: str) -> bool:
    try:
        r = subprocess.run([*GIT, "-C", str(repo), "merge-base", "--is-ancestor", a, b], capture_output=True, text=True, timeout=LOCAL_S, check=False)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise FillError(f"git merge-base 실행 실패: {e}") from e
    if r.returncode not in (0, 1):
        raise FillError(f"git merge-base 실패: {r.stderr.strip()[:200]}")
    return r.returncode == 0


def read_ref(repo: Path, main_ref: str = "origin/main") -> str:
    """뉴스·매거진이 읽는 원장 판 ref 1곳 — 사본 브랜치(origin/<branch>)가 있고 main 을 품으면(앞섬) 그 브랜치 · 없거나 main 보다 뒤처짐 = main_ref."""
    br = f"refs/remotes/origin/{branch()}"
    return br if _has(repo, br) and ancestor(repo, main_ref, br) else main_ref


def landed_commits(repo: Path, base: str, ref: str, no_base_cap: str = "15") -> list[str]:
    """기준선(base) 뒤 ref 까지 «전부» — 상한 0. 기준선이 없을 때(첫 판)만 최근 no_base_cap 개."""
    if base:
        return git(repo, "log", "--format=%h %s", f"{base}..{ref}").splitlines()
    return git(repo, "log", "--format=%h %s", "-n", no_base_cap, ref).splitlines()


def teams(repo: Path, ref: str) -> dict[str, str]:
    """{팀: 폴더 칸} — `<ref>:design/TEAMS.md` 의 «현역» 행만(휴면 팀은 표에 안 싣는다)."""
    name = f"팀 명단({ref}:design/TEAMS.md)"
    form = lambda ln: c if len(c := _cells(ln)) == 4 and _TEAM.fullmatch(c[0]) and _FORM.match(re.sub(r"[\s`]", "", c[1])) and c[3] in ("현역", "휴면") else None  # noqa: E731
    head, rows = table_rows(name, git(repo, "show", f"{ref}:design/TEAMS.md"), form, prose=True)
    if head[:2] != ["팀", "폴더"] or head[3:4] != ["상태"]:
        raise FillError(f"{name} 표 머리 꼴 틀림: {head}")
    out = {c[0]: re.sub(r"[\s`]", "", c[1]) for c in rows if c[3] == "현역"}  # 휴면 = 꼴 맞는 행(표에 안 싣는다)
    if not out:
        raise FillError(f"팀 명단 0줄({ref}:design/TEAMS.md)")
    return out


def _title(first: str, name: str) -> str:
    """카드 첫 줄 «# 인덱스: <이름> — <제목> — …» → 제목 조각(없으면 이름)."""
    parts = [p.strip() for p in first.lstrip("# ").split(" — ")]
    return parts[1] if len(parts) > 1 and parts[1] else name


def _first_lines(repo: Path, specs: list[str]) -> list[str]:
    """`<ref>:<경로>` 들의 첫 줄 — cat-file --batch 1회(카드 수십 장을 git 1번으로)."""
    if not specs:
        return []
    try:
        done = subprocess.run([*GIT, "-C", str(repo), "cat-file", "--batch"], input=("\n".join(specs) + "\n").encode("utf-8"), capture_output=True, timeout=LOCAL_S, check=False)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise FillError(f"git cat-file 실행 실패: {e}") from e
    data, at, out = done.stdout, 0, []
    for spec in specs:
        nl = data.index(b"\n", at)
        head = data[at:nl].decode("utf-8", "replace").split()
        if done.returncode != 0 or len(head) != 3:
            raise FillError(f"git cat-file 못 읽음: {spec}")
        size = int(head[2])
        out.append(data[nl + 1:nl + 1 + size].decode("utf-8", "replace").split("\n", 1)[0])
        at = nl + 1 + size + 1
    return out


def _disk_cards(folder: Path) -> list[tuple[str, str]]:
    if not folder.is_dir():
        return []
    return [(p.stem, _title((p.read_text(encoding="utf-8").splitlines() or [""])[0], p.stem)) for p in sorted(folder.glob("*.md")) if p.name != "README.md"]


def _disk_team(rel: str, team: str, since: datetime) -> dict:
    hroot = os.environ.get("FT_HARNESS_ROOT", "")
    if not hroot:
        raise FillError(f"{team} 폴더 {rel} — FT_HARNESS_ROOT 미설정")
    base = Path(hroot) / rel.split("/", 1)[1] / "indices"
    done = [(n, t) for n, t in _disk_cards(base / "완성") if datetime.fromtimestamp((base / "완성" / f"{n}.md").stat().st_mtime) >= since]
    return {"진행": _disk_cards(base / "진행"), "대기": len(_disk_cards(base / "대기")), "착지": done}


def team_cards(repo: Path, ref: str, now: datetime, hours: int = 24) -> dict[str, dict]:
    """팀마다 {진행: [(이름, 제목)], 대기: N, 착지: [(이름, 제목)]} — 착지 = 최근 hours 시간 안 완성 폴더에 «추가»된 카드.
    git 4회(ls-tree · rev-list · log · cat-file). 폴더 칸이 $FT_HARNESS_ROOT 꼴이면 디스크에서 읽는다(env 없음 = FillError · 표 전체 갱신 0)."""
    rows, since = teams(repo, ref), now - timedelta(hours=hours)
    on_ref = {t: rel for t, rel in rows.items() if not rel.startswith("$")}
    paths = git(repo, "ls-tree", "-r", "--name-only", ref, "--", *(f"{rel}indices/" for rel in on_ref.values())).splitlines() if on_ref else []
    window = f"--since={since:%Y-%m-%d %H:%M}"
    cap = sized(int(git(repo, "rev-list", "--count", window, ref) or 0), LOG_BASE) if on_ref else LOCAL_S  # r870 1-b — 창 안 커밋 수 비례(부하 때 고정 7초에 걸리던 몫)
    recent = {p for p in git(repo, "log", ref, window, "--diff-filter=A", "--name-only", "--format=", "--",
                             *(f"{rel}indices/완성/" for rel in on_ref.values()), timeout=cap).splitlines()} if on_ref else set()
    pick: dict[tuple[str, str], list[str]] = {}
    for team, rel in on_ref.items():
        for state in ("진행", "대기", "완성"):
            pre = f"{rel}indices/{state}/"
            pick[(team, state)] = sorted(p for p in paths if p.startswith(pre) and "/" not in p[len(pre):] and p.endswith(".md") and not p.endswith("/README.md"))
    want = [p for (t, s), ps in pick.items() for p in ps if s == "진행" or (s == "완성" and p in recent)]
    titles = dict(zip(want, _first_lines(repo, [f"{ref}:{p}" for p in want])))
    card = lambda p: (Path(p).stem, _title(titles[p], Path(p).stem))  # noqa: E731
    out = {t: {"진행": [card(p) for p in pick[(t, "진행")]], "대기": len(pick[(t, "대기")]),
               "착지": [card(p) for p in pick[(t, "완성")] if p in recent]} for t in on_ref}
    out.update({t: _disk_team(rel, t, since) for t, rel in rows.items() if rel.startswith("$")})
    return out


def mbox_done(box: Path, now: datetime, hours: int = 24) -> dict[str, int]:
    """쪽지함 꼬리에서 hours 시간 안 [완료]·[착지] 쪽지 수 — 팀 = 보낸 좌석 `byz-<팀>-…`. 쪽지함 없음 = FillError."""
    if not box.is_file():
        raise FillError(f"쪽지함 없음: {box}")
    with box.open("rb") as f:
        start, cut = max(0, f.seek(0, 2) - MAILBOX_TAIL), False
        if start:
            f.seek(start - 1)
            cut = f.read(1) != b"\n"  # r851 r5 — 꼬리 앞 1바이트가 개행 = 첫 줄은 완전한 줄(버림 0) · 그 밖 = 첫 줄만 잘린 조각
        f.seek(start)
        tail = list(enumerate(f.read().decode("utf-8", "replace").splitlines(), 1))
    out: dict[str, int] = {}
    for row, at in strict_rows(f"쪽지함 꼬리({box})", tail[1:] if cut else tail, _note):  # 잘린 조각 1줄만 정의된 예외
        head = (str(row.get("body") or "").splitlines() or [""])[0]
        m = re.match(r"byz-([a-z0-9]+)-", str(row.get("from", "")))
        if m and any(k in head for k in DONE_MARK) and timedelta(0) <= now - at <= timedelta(hours=hours):
            out[m[1]] = out.get(m[1], 0) + 1
    return out


def _note(ln: str):
    try:
        row = json.loads(ln)
        return row, datetime.fromisoformat(str(row["ts"])[:19])
    except (ValueError, TypeError, KeyError, IndexError):
        return None


def _question(v):
    ok = isinstance(v, dict) and isinstance(v.get("state"), str)
    return v if ok and (v["state"] != "open" or all(isinstance(v.get(k), str) for k in ("what", "seat"))) else None


def open_questions(paths: list[Path]) -> list[dict]:
    """질문 장부(byz_slack_questions.<채널>.json) «open» 칸 중 state=open — 파일 없음 = 0건 · 깨짐·모양 틀림 = FillError.
    r851 r3 ⑥ — 모양 = 최상위 객체 · «open» 객체(없음·null = 0건) · 항목마다 객체(그 밖 = 그 표만 갱신 0)."""
    out: list[dict] = []
    for p in paths:
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
        except FileNotFoundError:
            continue
        except (OSError, ValueError) as e:
            raise FillError(f"질문 장부 못 읽음: {p} ({type(e).__name__})") from e
        opened = data.get("open") if isinstance(data, dict) else None
        if not isinstance(data, dict) or not isinstance(opened if opened is not None else {}, dict):
            raise FillError(f"질문 장부 모양 틀림: {p} (최상위·«open»·항목은 객체여야 함)")
        items = strict_rows(f"질문 장부 {p}", [(f"open.{k}", (k, v)) for k, v in sorted((opened or {}).items())],
                            lambda kv: kv if _question(kv[1]) else None, skip=lambda kv: False)  # 항목 = 객체 · state 글자 · 열린 것은 what·seat 글자
        out += [{"seq": k, **v} for k, v in items if v["state"] == "open"]
    return out


_HIL = re.compile(r"(h\d+) (-?\d+)")


def hil_pending(hil_sh: Path) -> list[tuple[str, int]]:
    """`ft-hil.sh --pending --each` → [(hN, 분)] — 실패·시간 초과 = FillError."""
    try:
        p = subprocess.run(["bash", str(hil_sh), "--pending", "--each"], capture_output=True, text=True, timeout=LOCAL_S, check=False)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise FillError(f"ft-hil.sh --pending 실행 실패: {e}") from e
    if p.returncode != 0:
        raise FillError(f"ft-hil.sh --pending rc={p.returncode} {p.stderr.strip()[:120]}")
    return strict_rows("ft-hil.sh --pending 출력", enumerate(p.stdout.splitlines(), 1),
                       lambda s: (m := _HIL.fullmatch(s.strip())) and (m[1], int(m[2])))  # rc0 이어도 꼴 검사(rc0 ≠ 정상 · r4 ③)


def queue_open(text: str | None) -> list[dict]:
    """AUTONOMY-QUEUE 표의 열린 행(상태·처리됨 칸이 비었거나 «대기» · ft_decision_count.autonomy_open 과 같은 규칙) — 파일 없음(None) = 0행."""
    if text is None:
        return []
    width = len(_cells(next((ln for ln in text.splitlines() if ln.lstrip().startswith("|")), "")))
    head, body = table_rows("AUTONOMY-QUEUE", text, lambda ln: c if len(c := _cells(ln)) == width else None)  # 행 = 머리와 같은 칸 수
    col = next((c for c in ("상태", "처리됨") if c in head), None)
    if col is None:
        return [dict(zip(head, r)) for r in body]
    i = head.index(col)
    return [dict(zip(head, r)) for r in body if not r[i] or r[i].split("·")[0].split("—")[0].strip() == "대기"]
