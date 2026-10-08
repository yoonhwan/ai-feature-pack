"""magazine_emit — 블록 목록 → md · html (같은 목록에서 둘 다 뽑는다 · md 파서 0).

블록: ("h1"|"h2"|"h3"|"p", 글) · ("ul", [(글, 링크|None)]) · ("table", [머리], [[칸]]).
md 는 데이터를 그대로 싣고, html 은 전부 html.escape 로 중화한다(미검증 mbox 본문 — <@U..>·<script> 무력화).
"""
import html
from typing import Any

Block = tuple[Any, ...]
Model = dict[str, Any]  # 구조 모델(설계 §8) — 칸 검증은 render 가 한다
_HEAD = {"h1": 1, "h2": 2, "h3": 3}
CSS = (
    "body{font-family:'Apple SD Gothic Neo',sans-serif;font-size:11pt;line-height:1.55;margin:0 8mm}"
    "h1{font-size:19pt;border-bottom:2px solid #333;padding-bottom:4px}h2{font-size:14pt;margin-top:20px}"
    "h3{font-size:12pt;color:#444}table{border-collapse:collapse;width:100%}"
    "td,th{border:1px solid #bbb;padding:3px 6px;font-size:10pt;text-align:left;vertical-align:top}"
)


def _md_table(head: list[str], rows: list[list[str]]) -> str:
    def line(cells: list[str]) -> str:
        return "| " + " | ".join(str(c).replace("|", "\\|") for c in cells) + " |"
    return "\n".join([line(head), "|" + "---|" * len(head)] + [line(r) for r in rows])


def _md_block(b: Block) -> str:
    kind = b[0]
    if kind in _HEAD:
        return f"{'#' * _HEAD[kind]} {b[1]}"
    if kind == "p":
        return str(b[1])
    if kind == "ul":
        return "\n".join(f"- [{t}]({u})" if u else f"- {t}" for t, u in b[1])
    if kind == "table":
        return _md_table(b[1], b[2])
    raise ValueError(f"알 수 없는 블록: {kind}")


def to_md(blocks: list[Block]) -> str:
    return "\n\n".join(_md_block(b) for b in blocks) + "\n"


def _h(text: object) -> str:
    return html.escape(str(text), quote=True)


def _li(text: str, url: str | None) -> str:
    if url and url.startswith(("https://", "http://")):
        return f'<li><a href="{_h(url)}">{_h(text)}</a></li>'
    return f"<li>{_h(text)}</li>"


def _html_table(head: list[str], rows: list[list[str]]) -> str:
    th = "".join(f"<th>{_h(c)}</th>" for c in head)
    body = "".join("<tr>" + "".join(f"<td>{_h(c)}</td>" for c in r) + "</tr>" for r in rows)
    return f"<table><tr>{th}</tr>{body}</table>"


def _html_block(b: Block) -> str:
    kind = b[0]
    if kind in _HEAD:
        return f"<h{_HEAD[kind]}>{_h(b[1])}</h{_HEAD[kind]}>"
    if kind == "p":
        return f"<p>{_h(b[1])}</p>"
    if kind == "ul":
        return "<ul>" + "".join(_li(t, u) for t, u in b[1]) + "</ul>"
    if kind == "table":
        return _html_table(b[1], b[2])
    raise ValueError(f"알 수 없는 블록: {kind}")


def to_html(blocks: list[Block], title: str) -> str:
    head = f'<!doctype html><html lang="ko"><head><meta charset="utf-8"><title>{_h(title)}</title><style>{CSS}</style></head>'
    return head + "<body>\n" + "\n".join(_html_block(b) for b in blocks) + "\n</body></html>\n"
