"""ft_news_draft — «이슈 정리 리포트 + 뉴스 초안» 두 장 만들기 (R118a · 오빠 판정 1428·1430). 쓰는 쪽은 ft-news-draft.sh.

입력 = 상태판 수집 dict(ft_board_collect.collect) + 판정 원장의 «오빠 원문 「…」» 줄 + 카드 본문 + 쪽지 로그.
고리 규칙 r2(DA② B2): 그 번호를 «명시로» 적은 카드가 있나 → 그 번호를 적은 쪽지가 있나 → ★둘 다 없으면 «확인 안 됨»★
(전달 누락으로 찍지 않는다) · 연결 카드 일부만 완성이면 «일부 완료» — 요청 전체를 «완료» 로 올리지 않는다.
"""
import logging
import re
import sys
from datetime import datetime
from itertools import groupby
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ft_news_render import TEAM_ITEMS, easy_names, issue_text, render_draft, render_issues, scrub, state_rank, team_name, title_id  # noqa: E402

LOG = logging.getLogger("ft_news_draft")
REQUEST_LINE = re.compile(r"^-\s+\*{0,2}(\d+)\*{0,2}\s.*오빠.*?「(.+?)」")
STATUS_LINE = re.compile(r"^-\s*상태:\s*(대기|진행|완성)", re.M)
TOP_N, QUOTE_CAP = 10, 300


def parse_requests(lines: list[str]) -> list[dict]:
    """판정 원장 줄 중 «오빠 … 「원문」» 만 — 번호당 첫 줄."""
    seen: dict[int, dict] = {}
    for ln in lines:
        if (m := REQUEST_LINE.match(ln.strip())) and int(m[1]) not in seen:
            seen[int(m[1])] = {"n": int(m[1]), "quote": m[2][:QUOTE_CAP]}
    return list(seen.values())


def link_state(n: int, cards: list[dict], mails: list[str]) -> str:
    pat = re.compile(rf"판정[^\n]{{0,40}}?(?<!\d){n}(?!\d)")
    linked = [c for c in cards if pat.search(c["text"])]
    if not linked:
        return "전달됨(카드 없음)" if any(pat.search(m) for m in mails) else "확인 안 됨"
    done = sum(c["state"] == "완성" for c in linked)
    if done == len(linked):
        return "완료"
    if done:
        return f"일부 완료(완성 {done} / 연결 {len(linked)})"
    return "대기" if all(c["state"] == "대기" for c in linked) else "진행"


def rank(issues: list[dict]) -> list[dict]:
    """복잡도 높은 순 → 같으면 첫 커밋이 오래된 것(age 큰 것) 먼저 → 점수·age 가 «둘 다» 같은 묶음 안에서만 팀을 돌아가며."""
    out: list[dict] = []
    ordered = sorted(issues, key=lambda i: (-i["score"], -i["age"], i["title"]))
    for _, grp in groupby(ordered, key=lambda i: (i["score"], i["age"])):
        queues: dict[str, list[dict]] = {}
        for i in grp:
            queues.setdefault(i.get("team", ""), []).append(i)
        while any(queues.values()):
            out += [q.pop(0) for q in queues.values() if q]
    return out


def _card_title(text: str) -> str:
    m = re.match(r"#\s+(?:인덱스:\s*)?(.*)", text.strip().splitlines()[0] if text.strip() else "")
    return scrub(m[1].split(" — ")[0]) if m else "(제목 없음)"


def _bump(found: dict, key, team: str, title: str, score: int, reason: str, age: int = 0) -> None:
    it = found.setdefault(key, {"team": team, "title": title, "score": 0, "reasons": [], "age": age})
    it["score"] += score
    it["reasons"].append(reason)


def find_issues(collect: dict, texts: dict, added: dict | None = None, now_ts: float = 0) -> list[dict]:
    """복잡도 후보 — 진행 카드인데 세션 없음 · 폴더와 상태 줄 불일치 · 오래 멈춘 세션. age = 카드 파일을 처음 커밋한 뒤 지난 초."""
    found: dict = {}
    age_of = lambda key, idx: int(now_ts - added[(key, idx)]) if added and (key, idx) in added else 0  # noqa: E731
    for t in collect["teams"]:
        name = team_name(t)
        for idx, p in t["progress"].items():
            if not p["seats"]:
                _bump(found, (t["key"], idx), name, scrub(p["title"]), 2, "진행 카드인데 맡은 세션이 없음", age_of(t["key"], idx))
        for idx, state in t["states"].items():
            text = texts.get((t["key"], idx), "")
            if (m := STATUS_LINE.search(text)) and m[1] != state:
                _bump(found, (t["key"], idx), name, _card_title(text), 2, "폴더와 상태 줄이 다름", age_of(t["key"], idx))
        for row in t["stalled"]:
            mins = int(re.match(r"\d+", row[0]).group()) if re.match(r"\d+", row[0]) else 0
            _bump(found, (t["key"], "stalled", row[1]), name, f"{name} 세션이 멈춰 있어요", 3 if mins >= 60 else 1,
                  f"세션이 {mins}분 멈춤", mins * 60)
    return list(found.values())


def request_issues(requests: list[dict], teams_of: dict) -> list[dict]:
    out = []
    for r in requests:
        if r["state"] == "확인 안 됨":
            out.append({"team": "기획", "title": scrub(r["quote"]), "score": 1 + (len(teams_of[r["n"]]) > 1),
                        "reasons": ["요청이 어디에 연결됐는지 확인 안 됨"], "age": -r["n"]})
    return out


def _title_items(collect: dict) -> list[dict]:
    """팀 목록에 쓰이는 카드 제목 — 원문 그대로 내보내지 않고 같은 묶음·예산 규칙으로 쉬운 이름을 받는다."""
    titles = []
    for t in collect["teams"]:
        titles += [p["title"] for p in list(t["progress"].values())[:TEAM_ITEMS]] + [q["title"] for q in t["queue"][:TEAM_ITEMS]]
        titles += [t["done_today"]["last"]] if t["done_today"]["n"] else []
    return [{"id": title_id(x), "text": easy_names(scrub(x)), "mode": "job"} for x in dict.fromkeys(titles)]


def _easy_items(requests: list[dict], top: list[dict]) -> list[dict]:
    """요청 = 일 이름(job) · 이슈 = 상태 문장(status). 팀 약어는 쉬운 이름으로 바꿔서 보낸다."""
    jobs = [{"id": "r%d" % r["n"], "text": easy_names(r["quote"]), "mode": "job"} for r in requests]
    return jobs + [{"id": "p%d" % k, "text": easy_names(issue_text(i)), "mode": "status"} for k, i in enumerate(top)]


def merge_same(requests: list[dict]) -> list[dict]:
    """같은 원문은 1줄 — 번호는 처음 것, 상태는 가장 앞선 단계."""
    best: dict[str, dict] = {}
    for r in requests:
        key = " ".join(r["quote"].split())
        if key not in best:
            best[key] = dict(r)
        elif state_rank(r["state"]) > state_rank(best[key]["state"]):
            best[key]["state"] = r["state"]
    return list(best.values())


def _write(path: Path, text: str) -> None:
    tmp = path.with_suffix(".tmp")
    tmp.write_text(text, encoding="utf-8")
    tmp.replace(path)


def generate(out_dir, *, collect_fn, ledger_fn, texts_fn, mails_fn, easy_fn, send, dry_run: bool, now: datetime, added_fn=None) -> int:
    out_dir = Path(out_dir)
    try:
        collect, texts, added = collect_fn(), texts_fn(), (added_fn or dict)()
        mails, ledger = mails_fn(), ledger_fn()
    except Exception as e:  # 수집 실패 = 초안 0 + 실패 1통 (반쪽 초안 0)
        LOG.error("뉴스 초안 수집 실패: %s", e)
        if not dry_run:
            send(f"[뉴스 초안] 수집 실패: {type(e).__name__}: {e} — 초안 0")
        return 1
    cards = [{"team": k[0], "idx": k[1], "text": v, "state": next((t["states"].get(k[1]) for t in collect["teams"] if t["key"] == k[0]), "대기")}
             for k, v in texts.items()]
    requests = parse_requests(ledger)
    for r in requests:
        r["state"] = link_state(r["n"], cards, mails)
    requests = merge_same(requests)
    teams_of = {r["n"]: {c["team"] for c in cards if re.search(rf"판정[^\n]{{0,40}}?(?<!\d){r['n']}(?!\d)", c["text"])} for r in requests}
    issues = rank(find_issues(collect, texts, added, now.timestamp()) + request_issues(requests, teams_of))
    easy = easy_fn(_easy_items(requests, issues[:TOP_N]) + _title_items(collect))
    out_dir.mkdir(parents=True, exist_ok=True)
    stamp = now.strftime("%Y%m%d-%H%M")
    draft, sheet = out_dir / f"DRAFT-{stamp}.md", out_dir / f"ISSUES-{stamp}.md"
    _write(draft, render_draft(now, requests, collect, issues, easy))
    _write(sheet, render_issues(now, issues, TOP_N, easy))
    _write(out_dir / "last-draft-at.txt", now.isoformat(timespec="seconds") + "\n")
    failed = sum(1 for r in easy.values() if r.failure)
    if not dry_run:
        send(f"[뉴스 초안] DRAFT {draft} · ISSUES {sheet} · 요청 {len(requests)} · 팀 {len(collect['teams'])} · 문장 실패 {failed}")
    return 0
