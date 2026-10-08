"""magazine_render — 구조 모델(설계 §8) → md · html. 같은 블록 목록에서 둘 다 뽑아 순서가 같다.

틀(§2): 결론 → 오빠 할 일 → 바뀐 것 → 근거 → 각주표. 본문 #N 은 전부 각주표에 — 없으면 RenderError.
자유 문장(제목·mbox 줄)의 #N 은 «N번» 으로 풀어 쓴다 — 번호 표기는 구조 칸(머지 PR·이슈)에서만 나온다.
"""
import re

from magazine_emit import Block, Model, to_html, to_md

REQUIRED = ("date", "start", "end", "main", "merges", "issues_opened", "issues_closed", "verdicts", "mbox", "docs", "seats")
REF = re.compile(r"(?<![\w#])#([1-9]\d*)(?!\d)")
_PR_TAIL = re.compile(r"\s*\(#\d+\)\s*$")
_STATE_KO = {"OPEN": "열림", "CLOSED": "닫힘"}
HIL_MAX, VERDICT_MAX, SEAT_MAX = 8, 10, 5
Notes = dict[int, tuple[str, str, str]]


class RenderError(RuntimeError):
    pass


def scrub(text: object) -> str:
    return REF.sub(lambda m: f"{m.group(1)}번", " ".join(str(text).split()))


def _title(raw: object) -> str:
    return scrub(_PR_TAIL.sub("", str(raw)))


def _hm(iso: str) -> str:
    return str(iso)[:16].replace("T", " ")


def _notes(model: Model) -> Notes:
    notes: Notes = {}
    for m in model["merges"]:
        if m.get("pr"):
            notes.setdefault(int(m["pr"]), ("PR", _title(m["title"]), "병합됨"))
    for i in model["issues_opened"] + model["issues_closed"]:
        notes.setdefault(int(i["number"]), ("Issue", scrub(i["title"]), _STATE_KO.get(str(i.get("state")).upper(), str(i.get("state")))))
    return notes


def check_footnotes(body_md: str, notes: Notes) -> None:
    missing = sorted({int(n) for n in REF.findall(body_md)} - set(notes))
    if missing:
        raise RenderError("각주표에 없는 번호: " + ", ".join(f"#{n}" for n in missing))


def _hil_blocks(model: Model) -> list[Block]:
    hil = model["mbox"].get("hil", [])
    if not hil:
        return [("h2", "오빠 할 일"), ("p", "없어요")]
    items = [(scrub(x), None) for x in hil[:HIL_MAX]]
    note: list[Block] = [("p", f"최대 {HIL_MAX}건까지만 보여요")] if len(hil) >= HIL_MAX else []  # 수집기가 8건에서 자르므로 «8건» 이면 더 있을 수 있다
    return [("h2", "오빠 할 일"), ("ul", items)] + note


def _main_blocks(model: Model) -> list[Block]:
    groups: dict[str, list[tuple[str, None]]] = {}
    for m in model["merges"]:
        pr = f" (#{int(m['pr'])})" if m.get("pr") else ""
        groups.setdefault(scrub(m.get("tag") or "기타"), []).append((f"{_title(m['title'])}{pr}", None))
    out: list[Block] = [("h3", "main 에 들어간 것")]
    for tag, items in groups.items():
        out += [("p", f"{tag} {len(items)}건"), ("ul", items)]
    return out if groups else out + [("p", "없어요")]


def _issue_blocks(model: Model) -> list[Block]:
    opened, closed = model["issues_opened"], model["issues_closed"]
    out: list[Block] = [("h3", "이슈"), ("p", f"새로 연 {len(opened)}건 · 닫은 {len(closed)}건")]
    for label, issues in (("새로 연 이슈", opened), ("닫은 이슈", closed)):
        if issues:
            out += [("p", label), ("ul", [(f"#{int(i['number'])} {scrub(i['title'])}", None) for i in issues])]
    return out


def _verdict_blocks(model: Model) -> list[Block]:
    verdicts, bad = model["verdicts"], model["mbox"].get("bad_lines", 0)
    if not verdicts:
        return [("h3", "판정"), ("p", f"유효 줄에서 판정 0건 · 깨진 줄 {bad}건" if bad else "없어요")]
    nums = [int(v["n"]) for v in verdicts]
    items = [(f"판정 {int(v['n'])}: {scrub(v['line'])}", None) for v in verdicts[:VERDICT_MAX]]
    more = len(verdicts) - VERDICT_MAX
    return [("h3", "판정"), ("p", f"{min(nums)}~{max(nums)}번 · {len(nums)}건"), ("ul", items)] + ([("p", f"…외 {more}건")] if more > 0 else [])


def _team_of(seat: str) -> str:
    parts = str(seat).split("-")
    return parts[1] if len(parts) > 2 and parts[0] == "byz" else "기타"


def _seat_blocks(model: Model) -> list[Block]:
    """좌석은 팀별 건수 표 + 승계 쌍 상한(SEAT_MAX) — 신규 77·승계 47 같은 날에도 한 장에 들어가게."""
    succ, new = model["seats"].get("succession", []), model["seats"].get("new", [])
    if not succ and not new:
        return [("h3", "좌석"), ("p", "없어요"), ("p", "닫힘은 명부 기준 — 이 장에 없음")]
    teams: dict[str, list[int]] = {}
    for _old, name in succ:
        teams.setdefault(_team_of(name), [0, 0])[0] += 1
    for name in new:
        teams.setdefault(_team_of(name), [0, 0])[1] += 1
    rows = [[scrub(t), str(c[0]), str(c[1])] for t, c in sorted(teams.items(), key=lambda kv: -sum(kv[1]))]
    out: list[Block] = [("h3", "좌석"), ("p", f"승계 {len(succ)}건 · 신규 {len(new)}석"), ("table", ["팀", "승계", "신규"], rows)]
    if succ:
        out.append(("ul", [(f"{scrub(o)} → {scrub(n)} (승계)", None) for o, n in succ[:SEAT_MAX]]))
    if len(succ) > SEAT_MAX:
        out.append(("p", f"승계 최근 {SEAT_MAX}건만 보여요 · 나머지 {len(succ) - SEAT_MAX}건 생략"))
    return out + [("p", "닫힘은 명부 기준 — 이 장에 없음")]


def _team_blocks(model: Model) -> list[Block]:
    teams = model["mbox"].get("by_team", {})
    if not teams:
        return [("h3", "팀별 쪽지"), ("p", "없어요")]
    ranked = sorted(teams.items(), key=lambda kv: -kv[1]["count"])
    rows = [[scrub(t), str(v["count"]), " / ".join(scrub(r) for r in v.get("recent", [])[:3])] for t, v in ranked]
    return [("h3", "팀별 쪽지"), ("table", ["팀", "건수", "최근 요지"], rows)]


def _doc_blocks(model: Model) -> list[Block]:
    docs = model["docs"]
    return [("h3", "브리핑·마감 문서"), ("ul", [(scrub(d["path"]), d.get("url")) for d in docs]) if docs else ("p", "없어요")]


def _evidence_blocks(model: Model, generated_at: str) -> list[Block]:
    mb, seats, main = model["mbox"], model["seats"], model["main"]
    items = [
        f"창: {_hm(model['start'])} ~ {_hm(model['end'])} (KST)",
        f"main sha 범위: {str(main.get('from_sha') or '-')[:10]} → {str(main.get('to_sha') or '-')[:10]}",
        f"자료별 건수: main {len(model['merges'])} · 이슈 열림 {len(model['issues_opened'])}/닫힘 {len(model['issues_closed'])}"
        f" · 판정 {len(model['verdicts'])} · 쪽지 {mb.get('total', 0)} · 문서 {len(model['docs'])}"
        f" · 승계 {len(seats.get('succession', []))}/신규 {len(seats.get('new', []))}",
        f"깨진 줄 {mb.get('bad_lines', 0)}",
        f"생성: {generated_at}",
    ]
    if model.get("skipped_days"):
        items.append("건너뛴 날: " + ", ".join(model["skipped_days"]) + " (수동 --date 로 발행 가능)")
    return [("h2", "근거"), ("ul", [(s, None) for s in items])]


def _footnote_blocks(notes: Notes) -> list[Block]:
    rows = [[f"#{n}", k, t, s] for n, (k, t, s) in sorted(notes.items())]
    return [("h2", "각주표"), ("table", ["번호", "종류", "제목", "상태"], rows) if rows else ("p", "없어요")]


def render(model: Model, lines: list[str], generated_at: str) -> tuple[str, str]:
    for key in REQUIRED:
        if key not in model:
            raise RenderError(f"구조 모델에 '{key}' 칸 없음")
    if not lines:
        raise RenderError("요약 줄 없음")
    notes = _notes(model)
    heading = f"아침 매거진 — {model['date']} (전날 08:00 ~ 오늘 08:00)"
    body: list[Block] = [("h1", heading), ("h2", "결론"), ("p", scrub(lines[0]))] + _hil_blocks(model) + [("h2", "바뀐 것")]
    for part in (_main_blocks, _issue_blocks, _verdict_blocks, _seat_blocks, _team_blocks, _doc_blocks):
        body += part(model)
    body += _evidence_blocks(model, generated_at)
    check_footnotes(to_md(body), notes)
    blocks = body + _footnote_blocks(notes)
    return to_md(blocks), to_html(blocks, heading)
