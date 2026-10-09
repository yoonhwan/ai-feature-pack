"""mirror_team_render — 팀 뿌리 글·planner 한눈에 글을 «이벤트 원장에서 통째로» 다시 그린다 (판정 623 · 카드 설계 3 · r2-B).

원장 bucket = {"events": {이벤트 id: {issue, key, kind, at, title, pr, sha, link}}}. 이 모듈은 읽기만 하고 Slack 을 모른다.
«지금 하는 일» 문장은 609 `magazine_indexless.strip_tokens` 로 번호를 «걷어» 쓴다 — 번호는 «이슈 목록» 에만 남고, 걷고 남은 글이 6자 미만일 때만 그 문장을 건너뛴다.
"""
import mirror_lib as lib
import mirror_share as ms
from magazine_indexless import strip_tokens
from mirror_team import MAIN_TEAMS_LABEL, PLANNER, TEAMS, hhmm

LIST_CAP = 40
NOW_MAX = 2
MIN_NOW = 6  # 번호를 걷고 남은 글이 이보다 짧으면 «지금 하는 일» 로 쓰지 않는다


def _events(bucket: dict) -> list[dict]:
    return sorted(dict(bucket.get("events", {})).values(), key=lambda e: float(e["at"]))


def issues(bucket: dict) -> dict[int, dict]:
    out: dict[int, dict] = {}
    for ev in _events(bucket):
        n = ev.get("issue")
        if n is None:
            continue
        rec = out.setdefault(int(n), {"title": ev["title"], "opened": float(ev["at"]), "progress": 0, "closed": None})
        if ev["kind"] == "opened":
            rec["title"] = ev["title"]
        elif ev["kind"] in ("closed", "merged"):
            rec["closed"] = ev
        else:
            rec["progress"] += 1
    return out


def issue_title(bucket: dict, n: int) -> str | None:
    rec = issues(bucket).get(n)
    return str(rec["title"]) if rec else None


def now_lines(bucket: dict) -> list[str]:
    """그 팀 최근 글의 요약 1~2개 — 답장 요구 문구는 걷고(문장째 건너뜀), 번호 토큰은 strip_tokens 로 걷은 글을 쓴다."""
    out: list[str] = []
    for ev in reversed(_events(bucket)):
        what = ms.share_guard(str(ev.get("what") or ev["title"]))
        clean = strip_tokens(what)[0] if what else ""
        if len(clean) >= MIN_NOW and clean not in out:
            out.append(clean)
        if len(out) == NOW_MAX:
            break
    return out


def _closed_part(ev: dict) -> str:
    bits = ["닫힘"]
    if ev.get("pr"):
        bits.append(f"PR #{ev['pr']}")
    if ev["kind"] == "merged":
        bits.append(str(ev["sha"])[:7] if ev.get("sha") else "sha 확인 불가")
    return " ".join(bits) + f" {hhmm(float(ev['at']))}"


def issue_line(n: int, rec: dict) -> str:
    title = ms.share_guard(str(rec["title"])) or ms.OMITTED
    tail = _closed_part(rec["closed"]) if rec["closed"] else "진행 중"
    return f"#{n} {lib.esc(title)} — 열림 {hhmm(rec['opened'])} · 진행 {rec['progress']} · {tail}"


def waiting(bucket: dict) -> list[dict]:
    """결정 기다림 — 같은 키로 hil 뒤에 다른 글(보고·닫힘)이 오면 풀린 것으로 본다."""
    evs, out = _events(bucket), []
    for i, ev in enumerate(evs):
        if ev["kind"] == "hil" and not any(x["key"] == ev["key"] and x["kind"] != "hil" for x in evs[i + 1:]):
            out.append(ev)
    return out


def counts(bucket: dict) -> tuple[int, int]:
    recs = issues(bucket).values()
    shut = sum(1 for r in recs if r["closed"])
    return len(recs) - shut, shut


def _list_block(bucket: dict) -> list[str]:
    recs = list(issues(bucket).items())
    lines = [issue_line(n, r) for n, r in recs[:LIST_CAP]]
    return ["이슈 목록"] + lines + ([f"… 외 {len(recs) - LIST_CAP}건 — 스레드 참고"] if len(recs) > LIST_CAP else []) if recs else []


def render_team(team: str, day: str, bucket: dict, post_key: str) -> str:
    head = ms.tag("작업상황", f"{lib.esc(team)} · {day} — 지금 하는 일")
    now = [lib.esc(w) for w in now_lines(bucket)] or ["아직 올라온 글이 없어요"]
    wait = [f"결정 기다림: {lib.esc(w['title'])}" + (f" {lib.esc(w['link'])}" if w.get("link") else "") for w in waiting(bucket)]
    return "\n".join([head, *now, *wait, *_list_block(bucket), f"(mirror · {post_key} 시작)"])


def render_planner(day: str, buckets: dict[str, dict], post_key: str) -> str:
    rows = []
    for t in (*TEAMS, "기타"):
        b = buckets.get(t, {})
        first = (now_lines(b) or ["오늘 글 없음"])[0]
        opened, shut = counts(b)
        rows.append(f"• {t} — {lib.esc(first)} (열린 {opened} · 닫힌 {shut})")
    own = buckets.get(PLANNER, {})
    return "\n".join([ms.tag("작업상황", f"{MAIN_TEAMS_LABEL} · {day}"), *rows, *_list_block(own), f"(mirror · {post_key} 시작)"])
