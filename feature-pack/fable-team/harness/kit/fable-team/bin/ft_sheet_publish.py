"""ft_sheet_publish — 시트 슬랙 발행의 결정적 조각 (PLAN-status-sheet r4 §4·§4-1 · S2). 슬랙·LLM 호출은 여기 없다.

  plan   --ledger L --day D --rev R [--cap N]   발행 원장에서 오늘 상태를 셸 변수(OK_REV·OK_HM·OK_URL·TODAY_OK·FAILS)로 낸다
  append --ledger L --rev R --ok 0|1 --now ISO [--root-ts --pdf-ts --pdf-url --md-ts]   발행 사건 1행(업로드 성공 rev 만 ok=true)
  root   --rev R --ledger L --day D [--cap N] < 트리 텍스트   뿌리 글 = 트리(≤3500B 접기) + 끝줄 («미갱신»·«미발행(상한)» 은 끝줄에 드러낸다)
  fold   < html                                  PDF 쪽수 초과용 — «자세히» 접힘 절을 뺀 html (전체 md 는 같은 답글에 첨부)
  pdf    <html> <pdf>                            로컬 PDF 변환(magazine_pdf · 쪽수를 stdout) — FT_SHEET_PDF_BIN 으로 시험 대체
원장 = .fable-team/state/sheet-publish.jsonl `{ts, rev, root_ts, pdf_ts, pdf_url, md_ts, ok}`. 실패는 전부 raise → rc≠0 (#0 RULE · 폴백 0).
"""
import argparse
import json
import os
import re
import shlex
import sys
from pathlib import Path

from ft_board_root import CAP, _b

DAY_CAP = 24
PAGE_CAP = 6


def rows(ledger: Path, day: str) -> list[dict]:
    if not ledger.is_file():
        return []
    out = [json.loads(ln) for ln in ledger.read_text(encoding="utf-8").splitlines() if ln.strip()]
    return [r for r in out if str(r.get("ts", "")).startswith(day)]


def admit(ledger: Path) -> None:
    """원장 admission — 쓸 수 없으면 raise(자동 mkdir 0 · #0 RULE). 슬랙 호출 «전» 에 부른다."""
    if not ledger.parent.is_dir() or not os.access(ledger.parent, os.W_OK):
        raise OSError(f"발행 원장 폴더 없음/쓰기 불가: {ledger.parent}")
    if ledger.exists() and not os.access(ledger, os.W_OK):
        raise OSError(f"발행 원장 쓰기 불가: {ledger}")


def state(ledger: Path, day: str) -> dict:
    rs = rows(ledger, day)
    oks = [r for r in rs if r.get("ok")]
    tail = 0
    for r in reversed(rs):
        if r.get("ok"):
            break
        tail += 1
    last = oks[-1] if oks else {}
    return {"OK_REV": last.get("rev", ""), "OK_HM": str(last.get("ts", ""))[11:16], "OK_URL": last.get("pdf_url") or "", "TODAY_OK": len(oks), "FAILS": tail}


def footer(st: dict, rev: str, cap: int) -> str:
    if not st["OK_REV"]:
        return f"📄 PDF 아직 없음 · 지금 rev {rev} 미갱신(재시도 중)"
    base = f"📄 최신 PDF rev {st['OK_REV']} {st['OK_HM']} {st['OK_URL']}"
    if st["OK_REV"] == rev:
        return base
    return base + (f" · rev {rev} 미발행(상한)" if st["TODAY_OK"] >= cap else f" · 지금 rev {rev} 미갱신(재시도 중)")


def root(tree: str, foot: str, fails: int) -> str:
    lines = tree.rstrip("\n").split("\n")
    if fails >= 3:  # 3회 실패부터 ⓪ 칸(❓ 줄 바로 뒤)에 드러낸다
        at = next((i for i, x in enumerate(lines) if x.startswith("❓")), 0) + 1
        lines.insert(at, f"⚠ PDF 발행 실패 {fails}회 — 다음 틱에 다시 시도해요")
    build = lambda ls, n: "\n".join([*ls, *([f"… 외 {n}줄"] if n else []), foot])  # noqa: E731
    for k in range(len(lines), 0, -1):
        text = build(lines[:k], len(lines) - k)
        if _b(text) <= CAP:
            return text
    raise ValueError("끝줄만으로 상한 초과 — 끝줄 형식 점검")


def fold(html: str) -> str:
    return re.sub(r"<details>.*?</details>\s*", "", html, flags=re.S)


def convert(html: Path, pdf: Path) -> int:
    mirror = os.environ.get("FT_SHEET_MIRROR_DIR")
    if not mirror:
        raise RuntimeError("FT_SHEET_MIRROR_DIR 없음 — magazine_pdf 폴더를 모른다(현재 폴더 탐색 0 · ft-sheet-publish.sh 가 export 한다)")
    sys.path.insert(0, mirror)
    from magazine_pdf import html_to_pdf
    return html_to_pdf(html, pdf, "시트")


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("cmd", choices=("plan", "append", "root", "fold", "pdf"))
    p.add_argument("args", nargs="*")
    for n in ("ledger", "day", "rev", "now", "root-ts", "pdf-ts", "pdf-url", "md-ts"):
        p.add_argument(f"--{n}")
    p.add_argument("--ok", type=int, default=0)
    p.add_argument("--cap", type=int, default=DAY_CAP)
    a = p.parse_args(argv)
    if a.cmd == "plan":
        admit(Path(a.ledger))
        print("\n".join(f"{k}={shlex.quote(str(v))}" for k, v in state(Path(a.ledger), a.day).items()))
    elif a.cmd == "append":
        row = {"ts": a.now, "rev": a.rev, "root_ts": a.root_ts, "pdf_ts": a.pdf_ts, "pdf_url": a.pdf_url, "md_ts": a.md_ts, "ok": bool(a.ok)}
        with open(a.ledger, "a", encoding="utf-8") as f:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
    elif a.cmd == "root":
        st = state(Path(a.ledger), a.day)
        sys.stdout.buffer.write(root(sys.stdin.read(), footer(st, a.rev, a.cap), st["FAILS"]).encode("utf-8"))
    elif a.cmd == "fold":
        sys.stdout.write(fold(sys.stdin.read()))
    else:
        print(convert(Path(a.args[0]), Path(a.args[1])))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as e:  # noqa: BLE001 — 실패는 숨기지 않고 rc≠0 (#0 RULE)
        print(f"ft_sheet_publish: {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(1)
