"""magazine_collect_detail — 풀 디테일 칸 `detail` 의 git 소스 (설계 DESIGN-magazine-full-detail §2·§3 · D1 D2 D4 D7 + 부록).

여러 ref 의 git 기록만 읽는다(작업 트리 0). ref 가 없거나 git 이 실패하면 전부 MagazineError (반쪽 결과 0).
같은 경로·절이 여러 ref 에 있으면 목록 앞 ref 의 것을 쓴다.
"""
import re
import subprocess
from datetime import datetime
from pathlib import Path
from collections.abc import Mapping
from typing import Any, NamedTuple, TypeVar

import magazine_card_shape as shape
from magazine_collect_git import DOC_PREFIXES, _git
from magazine_window import MagazineError

DEFAULT_REFS = ("origin/main", "origin/ops/main-base", "origin/feat/v6-realtime-live")  # r1009 — 사본에는 원격 추적 ref 만 있다(로컬 «ops/main-base» 는 낡거나 없다)
EMPTY_TREE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
CARD_GLOB = "design/*/indices/완성/*"
VERDICT_GLOB = "design/*/OPS-VERDICTS-*.md"
NANO_LEDGER_GLOB = "design/*/NANO-LEDGER-*.md"
HUNK_RE = re.compile(r"^@@ -\S+ \+(\d+)(?:,(\d+))? @@")
VERDICT_HEAD_RE = re.compile(r"^(§\d+)\s*(.*)$")
TITLE_RE = re.compile(r"^#\s+(?:인덱스:\s*)?(.+)$")
DA_RE = re.compile(r"진행→완성\s*·\s*DA\s+(\S+)")
EVIDENCE_MARKS = ("세트:", "완료 독립 검증")
TEAM_RE = re.compile(r"^design/(?:teams/)?([^/]+)/indices/")  # magazine_collect_open.CARD_RE 와 같은 해석(R382 팀 폴더)
CLOSE_HEAD = "- 닫힘 판정문:"  # 완성 카드 머리의 닫는 증거 줄 — «끝낸 일» 1줄의 첫 후보
FETCH_TIMEOUT = 7  # 하드 룰 12 — 사본에 원격 가지를 받는 상한(초) · 재시도 1
_Row = TypeVar("_Row", bound=Mapping[str, object])


class Sec(NamedTuple):
    head: str
    body: str
    first: int  # 머리 줄 번호(1부터)
    last: int


def git(repo: Path, *args: str) -> str:
    return _git(repo, "-c", "core.quotePath=false", *args)


def team_of(path: str) -> str:
    """카드 경로 → 팀 칸. `design/(teams/)?<팀>/indices/…` 의 <팀> · 못 풀면 옛 꼴(둘째 조각) 그대로."""
    found = TEAM_RE.match(path)
    return found.group(1) if found else path.split("/")[1]


def fetch_refs(repo: Path, refs: list[str]) -> None:
    """`origin/<가지>` ref 를 사본에 받아 둔다 — 7초 상한 · 재시도 1(출력 없는 실패만) · 실패 = MagazineError(반쪽 결과 0).

    원장 사본은 ft-ledger-repo-sync 가 origin/main 만 전진시킨다 — ops/main-base 같은 다른 원격 가지는 여기서 받지 않으면 낡거나 없다.
    """
    for name in refs:
        if not name.startswith("origin/"):
            continue  # 로컬 가지 이름 = 부르는 쪽이 만든 시험용 ref(원격에 없다)
        branch = name[len("origin/") :]
        err = ""
        for _ in (1, 2):
            try:
                done = subprocess.run(
                    ["git", "-C", str(repo), "fetch", "--quiet", "origin", f"+refs/heads/{branch}:refs/remotes/origin/{branch}"],
                    capture_output=True, text=True, timeout=FETCH_TIMEOUT,
                )
            except subprocess.TimeoutExpired:
                err = f"{FETCH_TIMEOUT}초 상한 초과"
                continue
            except OSError as e:
                raise MagazineError(f"git fetch 실행 실패: {type(e).__name__}") from e
            if done.returncode == 0:
                err = ""
                break
            lines = (done.stderr.strip() or done.stdout.strip()).splitlines()
            err = lines[-1] if lines else f"rc={done.returncode} 출력 없음"
            if lines:
                break  # 출력이 있는 실패 = 확정 실패(재시도 0)
        if err:
            raise MagazineError(f"ref {name} fetch 실패: {err}")


def done_line(text: str) -> str | None:
    """완성 카드의 «끝낸 일» 1줄 — 머리 `- 닫힘 판정문:` → «## 상태» 의 «진행→완성» 줄. 둘 다 없으면 None.

    머리의 다른 줄(«- 상태: 대기» 등)은 싣지 않는다 — 완성으로 옮긴 카드가 «대기» 로 보이던 자리(r1009).
    """
    lines = text.split("\n")
    head_end = next((i for i, ln in enumerate(lines) if ln.startswith("## ")), len(lines))
    close = next((ln.strip() for ln in lines[:head_end] if ln.strip().startswith(CLOSE_HEAD)), None)
    if close:
        return close
    state = next((s.body for s in sections(text) if s.head.startswith("상태")), "")
    return next((ln.strip() for ln in state.split("\n") if "진행→완성" in ln), None)


def blob(repo: Path, path: str, *shas: str) -> str:
    """앞 sha 부터 `path` 를 읽는다 — 모두 없으면 마지막 오류를 raise."""
    err: MagazineError | None = None
    for sha in shas:
        try:
            return git(repo, "show", f"{sha}:{path}")
        except MagazineError as e:
            err = e
    raise err or MagazineError(f"읽을 sha 가 없어요: {path}")


def sections(text: str) -> list[Sec]:
    lines = text.split("\n")
    marks = [i for i, ln in enumerate(lines) if ln.startswith("## ")]
    ends = [*marks[1:], len(lines)]
    return [Sec(lines[i][3:].strip(), "\n".join(lines[i + 1 : j]).strip("\n"), i + 1, j) for i, j in zip(marks, ends)]


def name_status(out: str) -> list[tuple[str, str]]:
    """`--name-status --format=%x01%H` 출력 → [(커밋 sha, 새 경로)]."""
    return [(c.split("\n")[0], row.split("\t")[-1]) for c in out.split("\x01")[1:] for row in c.split("\n")[1:] if row.strip()]


def resolve_refs(repo: Path, refs: list[str], start: datetime, end: datetime) -> list[dict[str, object]]:
    out: list[dict[str, object]] = []
    for name in refs:
        end_sha = git(repo, "rev-list", "-1", "--first-parent", f"--before={end.isoformat()}", name).strip()
        if not end_sha:
            raise MagazineError(f"ref {name}: 창 끝 이전 커밋이 없어요")
        start_sha = git(repo, "rev-list", "-1", "--first-parent", f"--before={start.isoformat()}", name).strip() or None
        out.append({"name": name, "start_sha": start_sha, "end_sha": end_sha})
    return out


def _card(repo: Path, info: dict[str, object], path: str, moved: str, report: bool = False) -> dict[str, object]:
    text = blob(repo, path, str(info["end_sha"]), moved)
    secs = sections(text)
    head = next((m.group(1).strip() for ln in text.split("\n")[:3] if (m := TITLE_RE.match(ln))), None)
    missing = shape.missing_parts(head, [s.head for s in secs])
    if missing and not report:
        raise shape.error_for(missing[0], path)
    if missing:
        shape.report_line(path, missing)
        return {"path": path, "team": team_of(path), "missing": missing, "moved_sha": moved, "ref": info["name"]}

    def pick(name: str) -> str:
        return next(s.body.strip() for s in secs if s.head.startswith(name))

    state = pick("상태")
    lines = [ln.strip() for ln in state.split("\n")]
    da = DA_RE.search(state)
    return {
        "team": team_of(path), "path": path, "title": head, "why": pick("배경"), "coord": pick("골좌표"),
        "evidence": [ln for ln in lines if any(k in ln for k in EVIDENCE_MARKS)],
        "done": done_line(text),
        "da": da.group(1) if da else None, "moved_sha": moved, "ref": info["name"],
    }


def _units(repo: Path, infos: list[dict[str, object]], span: list[str], report: bool) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    """(정상 units, 형식 미달 malformed) — malformed 는 report 모드에서만 생긴다. 같은 경로는 앞 ref 의 판정이 이긴다."""
    seen: dict[str, dict[str, object]] = {}
    for info in infos:
        out = git(repo, "log", str(info["end_sha"]), *span, "-M", "--diff-filter=AR", "--name-status", "--format=%x01%H", "--", CARD_GLOB)
        for sha, path in name_status(out):
            if path.endswith(".md") and path not in seen:
                seen[path] = _card(repo, info, path, sha, report)
    rows = list(seen.values())
    return [r for r in rows if "missing" not in r], [r for r in rows if "missing" in r]


def _ranges(diff: str) -> list[tuple[int, int]]:
    """-U0 diff 의 «추가된 줄» 새 파일 기준 구간 [(첫 줄, 끝 줄)]."""
    out: list[tuple[int, int]] = []
    for ln in diff.split("\n"):
        m = HUNK_RE.match(ln)
        if not m:
            continue
        first, n = int(m.group(1)), int(m.group(2) if m.group(2) is not None else 1)
        if n:  # n=0 은 순수 삭제 — 추가된 줄 없음
            out.append((first, first + n - 1))
    return out


def _verdict_sections(repo: Path, info: dict[str, object]) -> list[dict[str, object]]:
    base, end_sha = str(info["start_sha"] or EMPTY_TREE), str(info["end_sha"])
    files = [p for p in git(repo, "diff", "--name-only", "--diff-filter=ACMR", base, end_sha, "--", VERDICT_GLOB).split("\n") if p]
    out: list[dict[str, object]] = []
    for path in files:
        ranges = _ranges(git(repo, "diff", "-U0", base, end_sha, "--", path))
        for s in sections(blob(repo, path, end_sha)):
            m = VERDICT_HEAD_RE.match(s.head)
            if m and any(a <= s.last and b >= s.first for a, b in ranges):
                out.append({"path": path, "section": m.group(1), "title": m.group(2), "body": s.body})
    return out


def _merge_bodies(repo: Path, shas: list[str]) -> dict[str, str]:
    """`merges` 칸 sha(origin/main first-parent 창 안)의 커밋 본문 전문 — 다른 ref 의 커밋은 싣지 않는다(설계 D4)."""
    if not shas:
        return {}
    out = git(repo, "log", "--no-walk=unsorted", "--format=%x01%H%x00%B", *shas)
    return {sha: body.strip() for sha, body in (c.split("\x00", 1) for c in out.split("\x01")[1:])}


def _seats_closed(repo: Path, info: dict[str, object]) -> list[dict[str, str]]:
    base = str(info["start_sha"] or EMPTY_TREE)
    out: list[dict[str, str]] = []
    path = ""
    for ln in git(repo, "diff", "-U0", base, str(info["end_sha"]), "--", NANO_LEDGER_GLOB).split("\n"):
        if ln.startswith("+++"):
            path = ln[6:] if ln.startswith("+++ b/") else ""
        elif ln.startswith("+") and path and "닫힘" in ln:
            out.append({"path": path, "line": ln[1:].strip()})
    return out


def _appendix(repo: Path, info: dict[str, object], span: list[str]) -> list[dict[str, str]]:
    out = git(repo, "log", str(info["end_sha"]), *span, "--diff-filter=A", "--name-status", "--format=%x01%H", "--")
    docs = [(sha, p) for sha, p in name_status(out) if p.rsplit("/", 1)[-1].startswith(DOC_PREFIXES)]
    return [{"path": p, "text": blob(repo, p, str(info["end_sha"]), sha)} for sha, p in docs]


def first_wins(rows: list[_Row], key: tuple[str, ...]) -> list[_Row]:
    seen: dict[tuple[object, ...], _Row] = {}
    for r in rows:
        seen.setdefault(tuple(r[k] for k in key), r)
    return list(seen.values())


def collect_detail(repo: Path, refs: list[str], start: datetime, end: datetime, merge_shas: list[str]) -> dict[str, Any]:
    repo = Path(repo)
    report = shape.report_mode()
    fetch_refs(repo, refs)
    infos = resolve_refs(repo, refs, start, end)
    span = [f"--since={start.isoformat()}", f"--until={end.isoformat()}"]
    units, malformed = _units(repo, infos, span, report)
    return {
        "refs": infos,
        "units": units,
        "malformed": malformed,
        "verdict_sections": first_wins([s for i in infos for s in _verdict_sections(repo, i)], ("path", "section")),
        "merge_bodies": _merge_bodies(repo, merge_shas),
        "seats_closed": first_wins([s for i in infos for s in _seats_closed(repo, i)], ("path", "line")),
        "appendix": first_wins([a for i in infos for a in _appendix(repo, i, span)], ("path",)),
    }
