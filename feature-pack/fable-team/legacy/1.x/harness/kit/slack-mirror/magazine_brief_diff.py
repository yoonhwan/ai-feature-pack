"""magazine_brief_diff — «지난 판 뒤로 바뀐 것» 칸: 지난 발행 원장 커밋 ↔ 이번 커밋의 §1·§2-1·§5 행 비교 (R259 · 판정 1988 · 지침 §1-3).

지난 커밋을 모르면 비교하지 않고 «지난 판 커밋 모름» 한 줄만 낸다(지어내기 0). 같은 일의 기준 = 근거 괄호를 뗀 «시키신 일»·«발주» 칸 글.
"""
import logging
from collections.abc import Callable

from magazine_brief_rows import is_done, split_evidence, table_rows
from magazine_doc_md import Doc, DocError, parse_doc

LOG = logging.getLogger("magazine_doc")
UNKNOWN = "지난 판 커밋 모름 — 이 칸은 지난 판이 남은 다음 판부터 채워져요"
ORDER = ("끝", "새", "바뀜")
Change = tuple[str, str, str]  # (끝|새|바뀜, 일, 바뀐 뒤 상태 — 바뀜만)


def previous_sha(state: dict[str, object], path: str, current: str) -> str | None:
    """상태 파일(키 = 원본 sha:경로)에서 이번이 아닌 «가장 최근에 올라간» 같은 경로의 판. 없으면 None."""
    for key, rec in reversed(list(state.items())):
        sha, _, src = key.partition(":")
        if src == path and sha != current and isinstance(rec, dict) and rec.get("uploaded"):
            return sha
    return None


def load_previous(state: dict[str, object], repo: str, path: str, current: str, read: Callable[[str, str, str], tuple[str, str]]) -> tuple[Doc | None, str]:
    """(지난 판 원장, 안내 줄). 읽기에 실패하면 (None, 사유 포함 «모름» 줄) + WARNING."""
    sha = previous_sha(state, path, current)
    if sha is None:
        return None, UNKNOWN
    try:
        return parse_doc(read(repo, sha, path)[1]), ""
    except (RuntimeError, DocError, OSError) as e:  # MirrorError·DocError 모두 RuntimeError
        LOG.warning("지난 판 원장을 못 읽음(%s): %s: %s", sha[:10], type(e).__name__, e)
        return None, f"{UNKNOWN.split(' — ')[0]} — 지난 판 원장을 못 읽었어요"


def _states(doc: Doc) -> dict[str, tuple[str, bool]]:
    out: dict[str, tuple[str, bool]] = {}
    for cell in doc.cells:
        archive = "완료 보관" in cell.title
        if not (archive or cell.title.startswith(("오빠가 시킨 일", "2-1."))):
            continue
        for row in table_rows(cell.body):
            task = " ".join(split_evidence(row.get("시키신 일") or row.get("발주") or "")[0].split())
            if task:
                state = "완료" if archive else row.get("지금 상태", "")
                out[task] = (state, is_done(state))
    return out


def changes(prev: Doc, cur: Doc) -> list[Change]:
    """끝(지금은 완료 · 지난 판엔 없거나 열림) · 새(지난 판에 없던 열린 일) · 바뀜(열린 채 상태 글이 달라짐) — 이 순서."""
    before, now = _states(prev), _states(cur)
    out: list[Change] = []
    for task, (state, done) in now.items():
        old = before.get(task)
        if done and not (old and old[1]):
            out.append(("끝", task, ""))
        elif not done and old is None:
            out.append(("새", task, ""))
        elif not done and old and state != old[0]:
            out.append(("바뀜", task, state))
    return sorted(out, key=lambda c: ORDER.index(c[0]))
