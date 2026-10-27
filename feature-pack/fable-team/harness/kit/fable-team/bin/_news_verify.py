#!/usr/bin/env python3
"""ft-news-verify — 뉴스·매거진 발행 직후 계획 §2 9칸(ⓐ~ⓘ)을 다시 재는 검증기 (r853 · N4).

발행은 그대로 둔다: 어떤 실패든 rc≠0 + 로그 1줄일 뿐 게시·삭제를 하지 않는다(계획 §2 ⓔ).
- 칸 = 7초 상한(하드 룰 12) · 값 못 읽음 = «모름» = 실패로 셈(조용한 9/9 0) · 선행 카드 함수 없음 = «검증 불가»(역시 9/9 아님 · ERROR)
- 9/9 연속 수 상태 파일 · 24 도달 = planner 1통(«뉴스 정상화 끝선 도달»)
- 실패 = planner [긴급] 1통(같은 사건 1통 — 실패 칸 조합이 그대로면 0통, 참으로 돌아간 뒤 다시 거짓 = 새 1통)
  검증 불가(선행 함수 없음)는 «복구» 가 아니다 — 그 칸의 열린 사건은 닫지도 새로 열지도 않는다(r1005 R2 반례 1)
- 발행본 꼬리 «검증 N/9» = --tail 일 때 그 파일 끝에 덧붙인다(게시 뒤라 슬랙 본문에는 안 들어간다)
  꼬리를 못 쓰면 9/9 가 아니다(r1005 R2 반례 5 — ERROR 1줄 + rc≠0)

env: FT_ROOT · FT_LEDGER_REPO · FT_LEDGER_PATH · FT_NEWS_VERIFY_STATE · FT_NEWS_VERIFY_NOTIFY=0 · FT_NOW(고정 시각)
"""
import argparse
import json
import logging
import os
import sys
import threading
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE)]
LOG = logging.getLogger("ft_news_verify")
CELL_S = 7.0

import _news_verify_book as book  # noqa: E402
import _news_verify_cells as cells  # noqa: E402
import _news_verify_lib as lib  # noqa: E402
import _news_verify_pub_cells as pub  # noqa: E402

CELLS = cells.CELLS + pub.CELLS  # 9칸 = 원장 쪽 ⓐ~ⓕ + 발행 쪽 ⓖ~ⓘ
bookkeep, self_error = book.bookkeep, book.self_error  # r1005 — 알림 장부는 _news_verify_book.py(파일 200줄 상한)


def _now() -> datetime:
    v = os.environ.get("FT_NOW")
    return datetime.strptime(v, "%Y-%m-%d %H:%M") if v else datetime.now().replace(second=0, microsecond=0)


def _load(f: Path, default):
    """상태 파일 — 없음·못 읽음·깨진 JSON = 기본값. 꼴이 다른 JSON(리스트/문자열)은 여기서 감싸지 않는다 —
    V4(R2): 꼴 깨짐도 «검증기 자체 실패» 한 곳(main 의 try)에서 ERROR 1줄 + 쪽지 1 로 받는다(조용한 무시 0)."""
    try:
        return json.loads(f.read_text(encoding="utf-8")) if f.is_file() else default
    except (OSError, ValueError):
        return default


def _save(f: Path, data) -> None:
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")


def run_cell(name: str, fn, ctx) -> tuple[str, str]:
    """칸 하나 — 7초 상한 · 넘김/예외 = «모름»(그 칸만 실패 · 다음 칸은 계속)."""
    box: dict = {}

    def worker() -> None:
        try:
            box["v"] = fn(ctx)
        except Exception as e:  # noqa: BLE001 — 칸 예외가 검증 전체를 죽이지 않는다
            box["e"] = e

    t = threading.Thread(target=worker, name=f"cell-{name}", daemon=True)
    t.start()
    t.join(CELL_S)
    if t.is_alive():
        LOG.error("%s 칸 %d초 초과 — 모름", name, CELL_S)
        return lib.UNKNOWN, f"{CELL_S:.0f}초 초과"
    if "e" in box:
        LOG.error("%s 칸 예외 — 모름: %s: %s", name, type(box["e"]).__name__, box["e"])
        return lib.UNKNOWN, f"예외 {type(box['e']).__name__}: {box['e']}"
    return box.get("v", (lib.UNKNOWN, "값 없음"))


def verify(ctx) -> tuple[int, list[tuple[str, str, str]]]:
    """9칸 전부 — (참 개수, [(칸 이름, 판정, 사유)])."""
    out = []
    for name, fn in CELLS:
        verdict, why = run_cell(name, fn, ctx)
        if verdict == lib.UNAVAILABLE:  # R1 — 선행 카드 함수 없음 = 9/9 아님 · ERROR(조용한 통과 0) · 쪽지는 안 보낸다
            LOG.error("%s 칸 검증 불가 — %s", name, why)
        out.append((name, verdict, str(why)[:200]))
    return sum(1 for _n, v, _w in out if v == lib.PASS), out


def tail_line(body: Path, line: str) -> str:
    """발행본 꼬리 «검증 N/9» — 같은 검증 줄이 이미 있으면 갈아 끼운다(두 번 붙지 않게).
    못 썼으면 사유를 돌려준다(빈 글자 = 씀) — 부르는 쪽이 rc≠0 으로 만든다(r1005 R2 반례 5)."""
    try:
        text = body.read_text(encoding="utf-8")
        kept = [ln for ln in text.splitlines() if not ln.startswith("검증 ")]
        body.write_text("\n".join(kept).rstrip("\n") + "\n" + line + "\n", encoding="utf-8")
    except OSError as e:
        return f"{body}: {type(e).__name__}: {e}"
    return ""


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--kind", choices=("news", "magazine"), default="news")
    p.add_argument("--body", action="append", default=[], help="발행본 글·HTML 경로(여러 번 줄 수 있다)")
    p.add_argument("--root", default=os.environ.get("FT_ROOT") or ".")
    p.add_argument("--repo", default=os.environ.get("FT_LEDGER_REPO") or "")
    p.add_argument("--rel", default=os.environ.get("FT_LEDGER_PATH") or "design/teams/planner/PLAN-oppa-ledger.md")
    p.add_argument("--ref", default=os.environ.get("FT_NEWS_MAIN_REF") or "origin/main")
    p.add_argument("--state", default="", help="뉴스 지도 상태 폴더(기본 <루트>/.fable-team/state/news-ledger)")
    p.add_argument("--log", default=os.environ.get("FT_NEWS_LOG") or "/tmp/byz-ft-news-planner.log")
    p.add_argument("--tail", action="store_true", help="발행본 끝에 «검증 N/9» 를 쓴다")
    a = p.parse_args(argv)
    root = Path(a.root).expanduser()
    body = [Path(x).expanduser() for x in a.body]
    now = _now()
    os.environ.setdefault("FT_ROOT", str(root))  # 칸들이 부르는 도구(r847 표식·원장 채움)가 같은 루트를 보게
    st = Path(os.environ.get("FT_NEWS_VERIFY_STATE") or root / ".fable-team/state/news-verify")
    try:  # R2(r1005 반례 2) — 발행본 읽기 권한 오류도 «발행 유지 · ERROR 1줄 · 쪽지 1»(예외 전파 0)
        texts = [lib.read_body(f) for f in body if f.is_file()]
    except OSError as e:
        self_error(root, st, a.kind, f"발행본 못 읽음 — {type(e).__name__}: {e}")
        return 1
    if not texts:
        print(f"ft-news-verify: 발행본 글 못 읽음 — {' '.join(str(x) for x in body) or '(‑‑body 없음)'} (검증 0/9)", file=sys.stderr)
        return 2
    ctx = lib.Ctx(kind=a.kind, texts=texts, root=root, repo=Path(a.repo or root / ".worktrees/news-ledger-main"),
                    rel=a.rel, ref=a.ref, state=Path(a.state) if a.state else root / ".fable-team/state/news-ledger",
                    verify_state=st, log=Path(a.log) if a.log else None, now=now)
    try:  # V4 — 검증기 안 예외는 전부 여기 한 곳에서(상태 파일 꼴 깨짐 포함) = 발행 유지 · ERROR 1줄 · 쪽지 1(R2)
        passed, out = verify(ctx)
        line = f"검증 {passed}/9"
        bad = [w for w in ([tail_line(f, line) for f in body if f.is_file()] if a.tail else []) if w]
        LOG.info("%s kind=%s streak=%s 연속 · 실패 %s", line, a.kind, _load(st / "streak.json", {}).get(a.kind, 0),
                 ", ".join(name for name, v, _w in out if v != lib.PASS) or "0")
        print(f"NEWS-VERIFY {now:%Y-%m-%d %H:%M} kind={a.kind} {line}"
              + (" (꼬리 못 씀 — 9/9 아님)" if bad else "")
              + "".join(f"\n  {name} — {'[검증 불가] ' if v == lib.UNAVAILABLE else ''}{why}" for name, v, why in out if v != lib.PASS))
        if bad:  # r1005 반례 5 — 발행본에 «검증 N/9» 를 못 남겼으면 9/9 가 아니다(ERROR · rc≠0 · 연속 셈 0)
            self_error(root, st, a.kind, f"발행본 꼬리 못 씀 — {'; '.join(bad)[:160]}")
            return 1
        bookkeep(root, st, a.kind, passed, out, now)
        _save(st / "self-error.json", {})  # r1005 반례 4 — 정상 완주 = 앞 자체 오류 사건 닫힘(같은 사유 재발 = 새 1통)
    except Exception as e:  # noqa: BLE001 — 어떤 예외도 발행 쪽으로 전파하지 않는다(R2)
        self_error(root, st, a.kind, f"{type(e).__name__}: {e}")
        return 1
    return 0 if passed == 9 else 1


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    raise SystemExit(main(sys.argv[1:]))
