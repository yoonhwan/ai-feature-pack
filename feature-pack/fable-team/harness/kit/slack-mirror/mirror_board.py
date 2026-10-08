"""mirror_board — 질문 보드 글(UTF-8 바이트 상한 · 가장 오래된 5건 + `… 외 n건`)과 닫는 사건(planner 인박스 `미닫힘=`).

정본 설계: design/harness/DESIGN-r49-question-board-20261008.md §2-r2 — A-r2(바이트 예산 = 실제 게시 문자열 전체) · B-r2(show 파싱 · fail-closed).
닫힘 판단은 `ft-inbox.sh show` 출력만 쓴다(정본 술어 obligation_closed 재구현 0). 큐 파일은 «있는가» 만 읽는다.
실패는 «닫기 0 + stderr ERROR + 보드 첫 줄 경고» — 보드 갱신·다른 카드 발행은 계속한다(조용한 대체 0).
"""
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

import mirror_lib as lib
import mirror_questions as mq
import mirror_share as ms

CAP = 3500  # 슬랙 실제 거부선 ~4000 바이트(실측 3909 성공 · 4073 거부) 아래 여유 12%
MAX_LINES = 5
ELLIPSIS = "…"
SHOW_LINE = re.compile(r"^\[[^\]]+\] \S+ seq=[0-9,]+ 미닫힘=(\d+(?:,\d+)*)? from=")
TIMEOUT = 30
_INGEST_FAILED: set[int] = set()  # 이 프로세스에서 적재가 실패한 seq — 다시 부르지 않는다(경고 `인박스 밖 n건` 은 매 패스 보드에 남는다 · 재기동 뒤 1회 재시도)


def _bytes(s: str) -> int:
    return len(s.encode("utf-8"))


def _fold(n: int) -> str:
    return f"{ELLIPSIS} 외 {n}건"


def fit_board(first: str, sections: list[tuple[str | None, list[str]]], cap: int = CAP) -> str:
    """첫 줄 + 목록(제목 줄·가장 오래된 순 최대 5줄·접기 표식)을 «최종 게시 문자열» 바이트 cap 안에 맞춘다. 어떤 입력에도 ≤ cap, 아니면 raise."""
    if _bytes(first) > cap - _bytes(ELLIPSIS):
        return first.encode("utf-8")[: cap - _bytes(ELLIPSIS)].decode("utf-8", "ignore") + ELLIPSIS
    text = first
    for title, lines in sections:
        base = text + (f"\n{title}" if title else "")
        if not lines or _bytes(f"{base}\n{_fold(len(lines))}") > cap:
            continue  # 제목 줄과 접기 표식도 못 싣는다 — 건수는 제목·첫 줄이 이미 말한다
        kept, shown = base, 0
        for ln in lines[:MAX_LINES]:
            rest = len(lines) - shown - 1
            cand = f"{kept}\n{ln}"
            if _bytes(cand + (f"\n{_fold(rest)}" if rest else "")) > cap:
                break
            kept, shown = cand, shown + 1
        text = kept + (f"\n{_fold(len(lines) - shown)}" if shown < len(lines) else "")
    if _bytes(text) > cap:
        raise lib.MirrorError(f"보드 글이 {cap} 바이트를 넘음: {_bytes(text)}")
    return text


def render_board(open_: dict[str, dict], now: float | None = None, place: str = "확인 불가", notes: list[str] | tuple[str, ...] = ()) -> str:
    now = now or time.time()

    def line(e: dict) -> str:
        mins = max(0, int((now - int(e.get("asked_at", now))) // 60))
        return f"{lib.esc(e.get('key', '?'))} {lib.esc(ms.share_guard(str(e.get('what', ''))) or ms.OMITTED)[:40]} ({mins}분)"

    def ordered(state: str) -> list[dict]:
        pairs = [(int(k), e) for k, e in open_.items() if e.get("state") == state]
        return [e for _, e in sorted(pairs, key=lambda p: (int(p[1].get("asked_at", now)), p[0]))]

    waiting, given = ordered("open"), ordered("delivered")
    first = f"{mq.BOARD_HEAD} {len(waiting)}건 — 결정 자리: {lib.esc(place)}" + "".join(f" — {lib.esc(n)}" for n in notes)
    return fit_board(first, [(None, [line(e) for e in waiting]), (f"planner 전달됨 {len(given)}건", [line(e) for e in given])])


def _run(argv: list[str], root: Path) -> subprocess.CompletedProcess:
    return subprocess.run(argv, capture_output=True, text=True, timeout=TIMEOUT, env={**os.environ, "FT_ROOT": str(root)})


def _queue_seqs(path: Path) -> set[int]:
    return {int(json.loads(x)["seq"]) for x in path.read_text(encoding="utf-8").splitlines() if x.strip()} if path.exists() else set()


def parse_show(out: str) -> set[int]:
    """show(비compact) 정상 출력 = 정확히 `EMPTY` 한 줄 또는 줄마다 SHOW_LINE. 안 닫힌 seq = `미닫힘=` 합집합(`seq=` 는 그룹 전체라 쓰지 않는다). 어긋나면 ValueError."""
    text = out.strip()
    if not text:
        raise ValueError("출력 비어 있음")
    if text == "EMPTY":
        return set()
    unclosed: set[int] = set()
    for ln in text.splitlines():
        m = SHOW_LINE.match(ln)
        if not m:
            raise ValueError(f"해석 불가 줄: {ln[:60]!r}")
        unclosed |= {int(x) for x in (m.group(1) or "").split(",") if x}
    return unclosed


def _fail(reason: str, detail: str = "") -> str:
    print(f"ERROR: 인박스 정리 확인 불가: {reason} {detail}".rstrip(), file=sys.stderr)
    return f"정리 확인 불가({reason})"


def _ingest_missing(inbox_bin: str, root: Path, seqs: list[int]) -> None:
    bad = []
    for s in (x for x in seqs if x not in _INGEST_FAILED):
        try:
            if _run([inbox_bin, "ingest", str(s)], root).returncode:
                bad.append(s)
        except (OSError, subprocess.SubprocessError):
            bad.append(s)
    if bad:
        _INGEST_FAILED.update(bad)
        print(f"ERROR: 인박스 적재 실패 seq={bad} (이 프로세스에서는 다시 시도하지 않음)", file=sys.stderr)


def close_from_inbox(qpath: Path, inbox_bin: str, planner_name: str | None, root: Path, why: str = "") -> str | None:
    """열린 질문 중 planner 인박스 큐에 «있고» `show` 의 미닫힘 집합에 «없는» 것을 닫는다. 반환 = 보드 첫 줄 경고(없으면 None)."""
    open_ = sorted(int(k) for k in mq.load(qpath)["open"])
    if not open_:
        return None
    if planner_name is None:
        return _fail(f"planner 현역 세션: {why}")
    inbox = Path(root) / ".fable-team" / "state" / "inbox"
    mine = inbox / f"{planner_name.split('#')[0]}.jsonl"  # 계보 = 이름의 #앞 (ft_inbox_core.lineage 와 같은 이름 규칙)
    try:
        anywhere = set().union(*(_queue_seqs(p) for p in inbox.glob("*.jsonl"))) if inbox.is_dir() else set()
        _ingest_missing(inbox_bin, root, [s for s in open_ if s not in anywhere])
        have = _queue_seqs(mine)
    except (ValueError, KeyError, TypeError, OSError) as e:
        return _fail("큐 파일 오류", type(e).__name__)
    notes = [f"인박스 밖 {n}건"] if (n := len([s for s in open_ if s not in have])) else []
    try:
        r = _run([inbox_bin, "show", planner_name], root)
        if r.returncode:
            return " — ".join([*notes, _fail(f"show rc={r.returncode}", r.stderr.strip()[:80])])
        unclosed = parse_show(r.stdout)
    except ValueError as e:
        return " — ".join([*notes, _fail("show 출력 해석 실패", str(e))])
    except (OSError, subprocess.SubprocessError) as e:
        return " — ".join([*notes, _fail("show 실행 실패", type(e).__name__)])
    for s in open_:
        if s in have and s not in unclosed:
            mq.close(qpath, s)
    return " — ".join(notes) or None


def add_args(p) -> None:
    p.add_argument("--inbox-bin", default="", help="planner 인박스 ft-inbox.sh 절대 경로 — 없으면 시작 시 exit 1(조용한 기본값 0)")


def check_args(a) -> None:
    if not a.inbox_bin or not Path(a.inbox_bin).is_file():
        raise lib.MirrorError(f"--inbox-bin 필요(ft-inbox.sh 절대 경로): {a.inbox_bin!r}")


def sweep(a, qpath: Path, seats: str, root: Path) -> None:
    """패스당 1회 — 닫는 사건을 처리하고 경고를 저장소 meta 에 둔다(보드는 갱신 때마다 그 경고를 읽는다)."""
    if not qpath.exists():
        return
    name, why = ms.live_planner(seats)
    note = close_from_inbox(qpath, a.inbox_bin, name, root, why)
    mq.set_notes(qpath, [note] if note else [])
