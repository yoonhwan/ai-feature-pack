"""ft-board 시트 — collect dict + 카드 정해진 줄 + 사건 원장(sheet-events) 창 → 모델 한 장 → 트리 렌더 (PLAN-status-sheet r4 · S1).

허용 입력은 닫혀 있다(§2-1): 구조 필드(원장 행 고정 필드) · 원문 인용 2자리 · 이야기(LLM 모델 json — 입력일 뿐 상태 글자를 만들지 못한다).
원장 행이 없는 칸 = 글자 대신 `소유자 미확인(<누가> · <어느 도구>)`. rev 둘: 구조 rev(이야기·보정 메모 제외) · 발행 rev(렌더 md 전체 정규화).
env: FT_SHEET_STORY(이야기 json 경로 · 기본 <루트>/.fable-team/state/sheet-story.json) · FT_SHEET_NOTES(보정 메모 · 기본 <루트>/.fable-team/state/sheet-notes.md)
"""
import hashlib
import json
import os
import re
from datetime import datetime, timedelta
from pathlib import Path

import ft_board_env as env
import ft_board_sheet_cards as cards
import ft_board_sheet_notes as notes
import ft_sheet_events
from ft_board_decide import decide_lines
from ft_board_sheet_tree import render

WINDOW_H = 24
STORY_NONE = "오늘 이야기: 아직 없음(아침판 입력 전)"


def _ask(d: dict, now: datetime) -> dict:
    words, n, parts = cards.table("sheet_words.json")["ask"], 0, []
    lines = decide_lines(d, now)
    for ln in lines:
        m = re.match(r"- (.+?) (\d+)(?: .*)?$", ln)
        if m:
            n += int(m[2])
            parts += [f"{words.get(m[1], cards.plain(m[1]))} {m[2]}"] if int(m[2]) else []
        elif ln.startswith("- "):
            parts.append(re.sub(r"^- (.+?) 확인 불가.*$", lambda x: words.get(x[1], cards.plain(x[1])) + " 확인 불가", ln))
    text = " · ".join(parts) or "오늘 질문 없음"
    return {"n": n, "text": cards.plain(text) if parts else text, "raw": lines}


def _story(root: Path) -> str:
    p = Path(os.environ.get("FT_SHEET_STORY") or root / ".fable-team" / "state" / "sheet-story.json")
    if not p.is_file():
        return STORY_NONE
    data = json.loads(p.read_text(encoding="utf-8"))
    failure = str(data.get("failure") or "").strip()  # 매거진이 낸 실패 사유 — summary 가 비었을 때만 «보이게» (R109 ⓓ · 풀이만 실패한 날은 이야기 정상)
    text = str(data.get("summary", "")).strip()
    if not text and failure:
        return f"오늘 이야기 생성 실패: {failure.splitlines()[0]}"
    bad = any(w in text for w in cards.table("sheet_words.json")["blocked"]) or re.search(r"\d|#", text)
    return "오늘 이야기 생성 실패: 상태어·숫자 포함(상태는 위 트리만 말한다)" if bad or not text else text


def _cells(d: dict, root: Path, events: list[dict], now: datetime) -> list[dict]:
    """③ 팀 상황(팀별) · ⑤ 제안서 — 원장 행이 없으면 소유자 미확인."""
    words, out = cards.table("sheet_words.json")["events"], []
    base = lambda s: re.sub(r"#\d+$", "", s)  # noqa: E731
    owner = {base(n): t["key"] for t in d["teams"] for n in json.loads((root / ".fable-team" / ("seats.json" if t["key"] == "v65" else f"seats-{t['key']}.json")).read_text(encoding="utf-8")) if not n.startswith("_")}
    for t in d["teams"]:
        if t.get("error"):  # 명부 수집 실패 — 숫자·상태 글자 대신 «확인 못 함» 한 칸(조용한 누락 0 · 판정 r554)
            out.append({"cell": "③", "team": t["label"], "text": f"확인 못 함: {t['error']}", "unconfirmed": True})
            continue
        if t["key"] == "planner" or not t.get("master"):
            continue
        evs = [e for e in events if e["ev"] in ("stop-ready", "done") and (e.get("team") or owner.get(base(str(e.get("seat"))))) == t["key"]]
        text = (f"{words[evs[-1]['ev']]} {evs[-1]['ts'][11:16]}" if evs else f"소유자 미확인({t['label']} master · [정지 레디]/[완료] 0)")
        out.append({"cell": "③", "team": t["label"], "text": text, "unconfirmed": not evs})
    labels = [e for e in events if e["ev"] == "label"]
    cache = root / ".fable-team" / "state" / "board" / "gh-cache.json"
    at = datetime.fromtimestamp(cache.stat().st_mtime).strftime("%H:%M") if cache.is_file() else "없음"
    props = [i for i in d["issues"] if "proposal" in i["labels"]]
    text = f"제안 {len(props)}건 · 라벨 사건 {len(labels)}건" if labels else f"소유자 미확인(issues · 라벨 사건 0 · 캐시 {at})"
    return out + [{"cell": "⑤", "team": "issues", "text": text, "unconfirmed": not labels}]


def build(d: dict, root: Path, now: datetime) -> dict:
    files = sorted((root / ".fable-team").glob("seats*.json"))
    allc = [c for f in files for c in cards.team_cards(root, f)]
    seats = {(t["key"], s): [x["name"] for x in blk["seats"]] for t in d["teams"] for s, blk in (t.get("progress") or {}).items()}
    running = [{**c, "say": cards.plain(c["say"]), "seats": seats.get((c["team"], c["slug"]), [])} for c in allc if c["folder"] == "진행"]
    prog = sorted((c for c in running if c["seats"]), key=lambda c: (not c["where"].startswith("✅"), c["slug"]))  # 🔄 = 진행 카드 ∧ 좌석 실재(§2-3)
    waiting = [c for c in allc if c["folder"] == "대기"] + [c for c in running if not c["seats"]]  # 좌석 없는 진행 카드는 «지금 도는 일»이 아니다 → 완성 전
    before: dict = {}
    unmapped = 0
    for c in sorted((w for w in waiting if not w["after"]), key=lambda w: (not w["star"], bool(w["prereq"]), w["slug"])):
        area = cards.area_of(c["team"])
        unmapped += area is None
        before.setdefault(area or "", []).append({**c, "say": cards.plain(c["say"])})
    events = notes.tail_rows(ft_sheet_events.state_dir(root) / "sheet-events.jsonl", (now - timedelta(hours=WINDOW_H)).isoformat(timespec="seconds"))
    cells = _cells(d, root, events, now)
    lint = notes.lint_notes(root, Path(os.environ.get("FT_SHEET_NOTES") or root / ".fable-team" / "state" / "sheet-notes.md"))
    return {"date": d["date"], "errors": [{"team": t["label"], "why": t["error"]} for t in d["teams"] if t.get("error")],
            "pending": ft_sheet_events.pending_counts(root), "ask": _ask(d, now), "progress": prog, "before": before,
            "after": [{**c, "say": cards.plain(c["say"])} for c in waiting if c["after"]], "waiting": waiting, "unmapped": unmapped,
            "cells": cells, "unconfirmed": sum(c["unconfirmed"] for c in cells),
            "notes": {"ok": [x[1] for x in lint if x[0]], "rejected": sum(1 for x in lint if not x[0])}, "story": _story(root)}


def _norm(md: str) -> str:
    return re.sub(r"멈춤 \d+분", "멈춤 N분", re.sub(r"\d{2}:\d{2}", "", md))


def revs(m: dict) -> dict:
    core = {k: v for k, v in m.items() if k not in ("story", "notes")}
    sha = lambda s: hashlib.sha256(s.encode("utf-8")).hexdigest()[:16]  # noqa: E731
    blob = re.sub(r" \(캐시[^)]*\)", "", json.dumps(core, ensure_ascii=False, sort_keys=True))  # 구조 rev 는 시계 무관 — 캐시 «미확인» note 는 now−mtime 으로 생기는 글자
    return {"structure": sha(_norm(blob)), "publish": sha(_norm(render(m, "md")))}


def render_cli(args: list[str], collect_fn) -> str:
    m = build(collect_fn(), env.ft_root(), env.now())
    if "--rev" in args:
        return json.dumps(revs(m), ensure_ascii=False)
    return render(m, "text" if "--text" in args else "html" if "--html" in args else "slack" if "--slack" in args else "md").rstrip("\n")
