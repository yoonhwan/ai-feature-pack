"""proposal_text — 제안서 슬랙 글의 첫 줄·본문 (byz_proposal_publish 에서 분리 · 200줄 한도).

첫 줄 = 머리표 `[작업상황]` + `*제안서 <팀>/<slug>[ rN]*` (찾을 때는 양쪽 머리표를 떼고 비교 — mirror_share.first_line_is).
슬랙은 읽기 전용이다 — 결론·결정할 것 값에 답장 요구 문구가 있으면 결정적 문구로 바꾸고 `(요약 문구 교정)` 을 붙인다.
결정할 것 줄 바로 아래에 결정 자리(현역 planner 세션 이름) 1줄을 싣는다.
"""
import os
import re

from mirror_lib import esc
from mirror_share import CORRECTED, decision_line, fix_line, tag
from magazine_slack import eli5_warning_line

FALLBACK = "제안서 본문 참고"


def first_line(key: str, rev: str, record: str = "") -> str:
    if record:  # 승인 끝난 제안서 «기록» — 결정 요청이 아님이 첫 줄에서 보인다
        return tag("작업상황", f"*제안서 {key} · 기록 판정 {record}*")
    return tag("작업상황", f"*제안서 {key}*" if rev == "r0" else f"*제안서 {key} {rev}*")


def _value(p: dict[str, str], k: str) -> str:
    v, fixed = fix_line(p[k], FALLBACK)
    return esc(v) + (f" {CORRECTED}" if fixed else "")


def issue_url(issue: str) -> str | None:
    """`--issue #M`(또는 M) → 제안 Issue URL(R77 r1 · 판정 826). 「없음」 등 번호가 아니면 None."""
    m = re.fullmatch(r"#?(\d+)", issue.strip())
    return f"https://github.com/{os.environ.get('GH_REPO', 'SecondWindStudio/byz-agents')}/issues/{m.group(1)}" if m else None


def text_of(p: dict[str, str], rev: str, warn: str | None = None, block: str | None = None, seats: str | None = None, issue: str | None = None) -> str:
    rec = p["record"]
    decide = [f"결정할 것: 없음 — 판정 {rec} 으로 승인됨"] if rec else [f"결정할 것: {_value(p, '오빠가 결정할 것')}", decision_line(seats=seats)]
    lines = [first_line(p["key"], rev, rec), *([f"Issue: {issue}"] if issue else []), f"결론: {_value(p, '결론')}", *decide, f"되돌림: {esc(p['되돌림'])}"]
    return "\n".join(lines + ([esc(eli5_warning_line(warn))] if warn else []) + ([block] if block else []))
