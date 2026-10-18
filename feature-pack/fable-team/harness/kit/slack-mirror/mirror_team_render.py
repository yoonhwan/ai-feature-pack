"""mirror_team_render — 팀 뿌리 글·planner 한눈에 글을 «이벤트 원장에서 통째로» 다시 그린다 (판정 623 · 카드 설계 3 · r2-B).

원장 bucket = {"events": {이벤트 id: {issue, key, kind, at, title, pr, sha, link}}}. 이 모듈은 읽기만 하고 Slack 을 모른다.
«지금 하는 일» 문장은 609 `magazine_indexless.strip_tokens` 로 번호를 «걷어» 쓴다 — 번호는 «이슈 목록» 에만 남고, 걷고 남은 글이 6자 미만일 때만 그 문장을 건너뛴다.
"""
import sys

import mirror_lib as lib
import mirror_share as ms
from magazine_indexless import strip_tokens
from mirror_team import MAIN_TEAMS_LABEL, PLANNER, TEAMS, hhmm

LIST_CAP = 40
ROOT_MAX_BYTES = 3500  # 뿌리 글 전체 «UTF-8 바이트» 상한 — 실측: 성공한 글 최대 3967B · 실패한 글 최소 6097B (글자 수로 재면 한글 3448자=6315B 가 막힌다)
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


def _fold(n: int) -> str:
    return f"… 외 {n}건 — 스레드 참고"


def _size(s: str) -> int:
    return len(s.encode("utf-8"))


def _list_block(bucket: dict, others: list[str]) -> list[str]:
    """목록 블록 자리 = ROOT_MAX_BYTES − 목록 밖 본문. 머리+줄+접힘 → 머리+접힘 → 접힘만 → 0줄 순으로 맞춘다."""
    recs = list(issues(bucket).items())
    if not recs:
        return []
    room = ROOT_MAX_BYTES - _size("\n".join(others))
    head = _size("이슈 목록") + 1
    lines = [issue_line(n, r) for n, r in recs[:LIST_CAP]]
    for k in range(len(lines), -1, -1):
        fold = [_fold(len(recs) - k)] if k < len(recs) else []
        cost = head + sum(_size(x) + 1 for x in lines[:k]) + sum(_size(x) + 1 for x in fold)
        if cost <= room:
            return ["이슈 목록", *lines[:k], *fold]
    fold = _fold(len(recs))
    return [fold] if _size(fold) + 1 <= room else []


def _fit(head: str, sections: list[list[str]], tail: str) -> list[str]:
    """목록 밖 본문(꼬리 앞까지)을 ROOT_MAX_BYTES 안에 맞춘다 — 앞 구역(현재 요약)부터 «… 외 N줄» 로 접고, 그래도 넘으면 글 끝을 바이트 경계에서 자른다."""
    secs = [list(s) for s in sections]

    def lines() -> list[str]:
        return [head, *(x for s in secs for x in s), tail]

    def fits() -> bool:
        return _size("\n".join(lines())) <= ROOT_MAX_BYTES

    for i, full in enumerate(sections):
        if fits():
            break
        for k in range(len(full), -1, -1):
            secs[i] = full[:k] + ([f"… 외 {len(full) - k}줄"] if k < len(full) else [])
            if fits():
                break
    if fits():
        return lines()[:-1]
    cut = "…(뿌리 글 예산 초과 — 접힘)"
    body = "\n".join(lines()[:-1]).encode("utf-8")[: ROOT_MAX_BYTES - _size(f"\n{cut}\n{tail}")]
    print(f"ERROR: 뿌리 글 목록 밖 본문이 {ROOT_MAX_BYTES}바이트 초과 — 끝을 잘라 올림 ({head[:40]})", file=sys.stderr)
    return [body.decode("utf-8", "ignore"), cut]


def _assemble(head: str, sections: list[list[str]], tail: str, bucket: dict) -> str:
    before = _fit(head, sections, tail)
    return "\n".join([*before, *_list_block(bucket, [*before, tail]), tail])


def render_team(team: str, day: str, bucket: dict, post_key: str) -> str:
    head = ms.tag("작업상황", f"{lib.esc(team)} · {day} — 지금 하는 일")
    now = [lib.esc(w) for w in now_lines(bucket)] or ["아직 올라온 글이 없어요"]
    wait = [f"결정 기다림: {lib.esc(w['title'])}" + (f" {lib.esc(w['link'])}" if w.get("link") else "") for w in waiting(bucket)]
    return _assemble(head, [now, wait], f"(mirror · {post_key} 시작)", bucket)


def render_planner(day: str, buckets: dict[str, dict], post_key: str) -> str:
    rows = []
    for t in (*TEAMS, "기타"):
        b = buckets.get(t, {})
        first = (now_lines(b) or ["오늘 글 없음"])[0]
        opened, shut = counts(b)
        rows.append(f"• {t} — {lib.esc(first)} (열린 {opened} · 닫힌 {shut})")
    own = buckets.get(PLANNER, {})
    return _assemble(ms.tag("작업상황", f"{MAIN_TEAMS_LABEL} · {day}"), [rows], f"(mirror · {post_key} 시작)", own)
