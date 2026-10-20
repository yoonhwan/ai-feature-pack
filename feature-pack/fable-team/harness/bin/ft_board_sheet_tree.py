"""시트 화면 — 오빠 확정 트리(PLAN §2-3)를 «한 함수»가 text·md·html·slack 으로 그린다 (세 화면이 다른 문장을 갖지 않는다).

화면 = 맨 위 한 화면(확인 중 · ❓ · 🔄 · ⏳ 완성 전 영역 4 · ⏳ 완성 후) → 이야기 절 → 흐름 1장 → «자세히»(번호·경로·sha 는 여기만).
줄 글자는 모델(원장 행 + 치환표)에서만 나온다 — 쪽지 본문·카드 자유 줄을 읽는 코드는 없다.
"""
import html

from ft_board_sheet_cards import table

SHOWN = 5   # 🔄 줄 상한
PER_AREA = 3
SLACK_MAX = 3500


def tree_lines(m: dict) -> list[str]:
    p = m["pending"]
    out = [f"확인 중 {p['prepared']}" + (f"(오래됨 {p['old']})" if p["old"] else "") + f" · 소유자 미확인 {m['unconfirmed']}칸",
           f"❓ 오빠가 정할 것 ({m['ask']['n']}건) — {m['ask']['text']}", "🔄 지금 진행 중 (끝나면 멈춤)"]
    out += [f"⚠ 확인 못 함 {e['team']}: {e['why']}" for e in m.get("errors") or []]  # 한 팀을 못 읽어도 나머지는 발행된다(판정 r554)
    prog = m["progress"]
    keep = SHOWN if len(prog) <= SHOWN else SHOWN - 1  # 넘치면 «외 N건» 줄도 5줄 안에 든다
    out += [f"  · {x['say']} — {x['where']}" for x in prog[:keep]] or ["  · (지금 진행 중인 일 없음)"]
    if len(prog) > keep:
        out.append(f"  · 외 {len(prog) - keep}건")
    out.append("⏳ 완성 전")
    for area in table("sheet_areas.json")["areas"]:
        items = m["before"].get(area, [])
        lines = [x["say"] + (" ★" if x["star"] else "") for x in items[:PER_AREA]] or ["(없음)"]
        if len(items) > PER_AREA:
            lines.append(f"외 {len(items) - PER_AREA}건")
        out += [f"  {area} · {ln}" if i == 0 else f"    · {ln}" for i, ln in enumerate(lines)]
    aft = m["after"]
    out.append(f"⏳ 완성 후 ({len(aft)}건)" + (" — " + " · ".join(x["say"] for x in aft[:3]) if aft else ""))
    return out


def detail_lines(m: dict) -> list[str]:
    out = ["### 줄별 상세"]
    for x in m["progress"]:
        out.append(f"- 진행 · {x['slug']} — {x['path']} · 좌석 {' '.join(x['seats']) or '좌석 없음'} · 단계 {x['where']}")
    for x in m["waiting"]:
        out.append(f"- {'좌석 없는 진행' if x['folder'] == '진행' else '대기'} · {x['slug']} — {x['path']}" + (f" · 선행 「{x['prereq']}」 [{x['path']}:선행]" if x["prereq"] else ""))
    out += ["### 칸별 소유자 미확인 · 확인된 칸"] + [f"- {c['cell']} {c['team']}: {c['text']}" for c in m["cells"]]
    out += [f"- ask 근거: {ln}" for ln in m["ask"]["raw"]]
    if m["unmapped"]:
        out.append(f"- 영역 미정 {m['unmapped']}건 (sheet_areas.json 에 팀 없음 — planner 커밋으로만 추가)")
    out += [f"### 보정 메모(미적용 {len(m['notes']['ok'])})"] + [f"- {n}" for n in m["notes"]["ok"]]
    if m["notes"]["rejected"]:
        out.append(f"- 거절 {m['notes']['rejected']}건 (ft-board.py sheet-notes 로 사유 확인)")
    out += ["### 출처표 (소유자)", "| 칸 | 소유자 | 사건 |", "|---|---|---|"] + [f"| {a} | {b} | {c} |" for a, b, c in table("sheet_words.json")["sources"]]
    return out


def _flow(m: dict) -> list[str]:
    boxes = table("sheet_words.json")["flow"]
    return ["| 흐름 | " + " | → | ".join(boxes) + " |", "|" + "---|" * (2 * len(boxes))]


def render(m: dict, fmt: str) -> str:
    tree = tree_lines(m)
    if fmt == "text":
        return "\n".join(tree)
    if fmt == "slack":
        out = "\n".join(tree)
        if len(out.encode("utf-8")) > SLACK_MAX:
            raise RuntimeError(f"슬랙 뿌리 글 {SLACK_MAX}B 초과 — 접기 규칙 필요(S2)")
        return out
    story = m["story"]
    if fmt == "md":
        return "\n".join([ln + "  " for ln in tree] + ["", "## 오늘 이야기", story, "", "## 흐름"] + _flow(m)
                         + ["", "## 자세히"] + detail_lines(m)) + "\n"
    esc = html.escape
    flow = "".join(f"<td>{esc(b)}</td>" + ("<td>→</td>" if i < len(table('sheet_words.json')['flow']) - 1 else "") for i, b in enumerate(table("sheet_words.json")["flow"]))
    return ("<!doctype html><meta charset=utf-8><title>현황판</title>\n<pre class=\"tree\">\n" + "\n".join(esc(ln) for ln in tree)
            + f"\n</pre>\n<h2>오늘 이야기</h2>\n<p>{esc(story)}</p>\n<h2>흐름</h2>\n<table class=\"flow\"><tr>{flow}</tr></table>\n"
            + "<details><summary>자세히</summary><pre>\n" + "\n".join(esc(ln) for ln in detail_lines(m)) + "\n</pre></details>\n")
