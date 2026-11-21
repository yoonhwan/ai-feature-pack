"""ft_board_news_wait — 오빠 대기 실측을 한 곳에서 세고, 그 실측으로 본문 줄을 만든다 (r2389 K1 · K2 · K3 값 · K5 ⓕ · K6).

ⓐ 지금 판정 h(ft-verdict open ∧ oppa_todo) — 판정 원장에 시작 시각이 없어 «오빠 승인 대기 N건» 한 줄로만 센다(r2102 꼴).
ⓑ 오빠 질문 장부 state/desk-reply-wait.jsonl — 열쇠((kind, q_ts))별 «마지막 줄» 이 closed 가 아닌 것(재등록·reask_at 줄 포함).
ⓒ 팀장 [HIL] 쪽지 — 팀 명부 _master → planner _master·_desk 로 간 최근 24시간 «팀마다 마지막 1통» 의 첫 줄이 «[HIL]» ·
   ⓑ 에 같은 PR 번호·key 가 있으면 뺀다(같은 일 두 줄 0 · PR 번호 = 글 속 4~5자리 숫자 낱말).
못 읽음 = 그 출처 «판정 불가» 1줄(하드 룰 20). 다만 파일이 아직 없음(장부·planner 명부·우편 기록)은 «아직 0» 이다(새 루트·시험).
여기에는 절대 시각(epoch)만 둔다 — «HH:MM(N시간)» 글은 발행하는 쪽이 지금 시각으로 만든다(collect dict 원칙).
K2 · K3 줄은 열쇠 밖이다 — 값이 늙어 시각만 바뀌면 재발행 0(열쇠는 todo_lines(now=None) 꼴).
"""
import json
import os
import re
import subprocess
from datetime import datetime
from pathlib import Path

from ft_board_mail import body_of, lineage

HOUR, DAY, NEXT_MAX, STALE_H = 3600, 86400, 50, 2
PR = re.compile(r"(?<![0-9])[0-9]{4,5}(?![0-9])")
LEDGER = ".fable-team/state/desk-reply-wait.jsonl"
HIL, NO_WAIT = "[HIL]", "원장·오빠 대기 실측 둘 다 없음"


def hhmm(at) -> str:
    return datetime.fromtimestamp(int(at)).strftime("%H:%M") if at else "시각 판정 불가"


def ago(at, now) -> str:
    """«HH:MM(N시간)» — 언제부터 기다렸나 · 시각 모름 = «시각 판정 불가»."""
    return f"{hhmm(at)}({max(0, int((now.timestamp() - int(at)) // HOUR))}시간)" if at else "시각 판정 불가"


def pr_nums(text) -> set:
    """글 속 4~5자리 숫자 낱말 = PR 번호 후보(ⓑⓒ 중복 대조)."""
    return set(PR.findall(str(text or "")))


def ledger_rows(p) -> tuple:
    """(장부 줄들 | None, 판정 불가 사유) — 파일 없음 = 빈 목록(아직 등록 0) · 한 줄이라도 깨짐 = None."""
    p = Path(p)
    if not p.is_file():
        return [], ""
    try:
        return [json.loads(x) for x in p.read_text(encoding="utf-8").splitlines() if x.strip()], ""
    except (OSError, ValueError):
        return None, "오빠 질문 장부 판정 불가"


def open_rows(rows) -> list:
    """열린 줄 — 열쇠별 마지막 줄이 closed 가 아닌 것(K1 ⓑ) → [{key, kind, q_ts, at}] 오래된 순."""
    last = {}
    for r in rows or []:
        if isinstance(r, dict) and isinstance(r.get("q_ts"), str):
            last[(r.get("kind") or "h", r["q_ts"])] = r
    out = [{"key": str(r.get("key") or r.get("h") or k[1]), "kind": k[0], "q_ts": k[1], "at": int(r.get("at") or 0)}
           for k, r in last.items() if r.get("state") != "closed"]
    return sorted(out, key=lambda x: (x["at"], x["key"]))


def seats(base) -> dict:
    """{팀 이름: 명부 dict} — .fable-team/seats*.json 만 본다(TEAMS.md 안 봄) · 깨진 파일 = 건너뛴다(collect 가 그 팀을 error 로 드러낸다)."""
    out = {}
    for p in sorted((Path(base) / ".fable-team").glob("seats*.json")):
        try:
            doc = json.loads(p.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if isinstance(doc, dict) and isinstance(doc.get("_master"), str) and doc["_master"]:
            out[str(doc.get("_label") or p.stem)] = doc
    return out


def _field(body: str, name: str) -> str:
    """쪽지 본문에서 «<name>:» 뒤 글 1개 — 없으면 빈 글."""
    for line in body.splitlines():
        i = line.strip().find(name)
        if i >= 0:
            return line.strip()[i + len(name):].strip(" —·")
    return ""


def _ts(ts) -> float:
    try:
        return datetime.fromisoformat(str(ts)).timestamp()
    except (TypeError, ValueError):
        return 0.0


def hil_notes(base, recs, now: float, targets: set) -> list:
    """ⓒ — 팀 _master 가 planner 쪽으로 보낸 24시간 안 마지막 1통의 첫 줄이 «[HIL]» 이면 {team, next, goal, at, pr, seq}."""
    out = []
    for label, doc in seats(base).items():
        mine = [r for r in recs or [] if lineage(r["from"]) == lineage(doc["_master"]) and lineage(r["to"]) in targets
                and 0 <= now - _ts(r["ts"]) <= DAY]  # 발행 시각 뒤 쪽지는 그 알림에 없던 일(과거 판 재현이 흔들리지 않게)
        if not mine:
            continue
        last = max(mine, key=lambda r: r["seq"])
        body = body_of(last)
        nxt = _field(body, "다음 수:") if body.strip().startswith(HIL) else ""
        if nxt:
            out.append({"team": label, "next": nxt, "goal": _field(body, "골좌표:"), "at": int(_ts(last["ts"])), "pr": sorted(pr_nums(nxt)), "seq": last["seq"]})
    return out


def waits(base, teams, mail, now: float) -> dict:
    """collect 가 부르는 한 곳 — {"a": [h번호], "b": [...], "c": [...], "bad": [사유]}. 못 읽은 출처만 bad 에 남는다."""
    bad: list = []
    rows, why = ledger_rows(Path(base) / LEDGER)
    if rows is None:
        bad.append(why)
    b = open_rows(rows)
    lab = seats(base)
    planner = lab.get("planner") or {}
    tgt = {lineage(x) for x in (planner.get("_master"), planner.get("_desk")) if isinstance(x, str) and x}
    err, c = str(getattr(mail, "err", "") or ""), []
    if not tgt:
        pass  # planner 명부 없음 = 아직 없는 루트(판정 불가 아님)
    elif err.endswith("해석 실패"):
        bad.append("팀장 [HIL] 쪽지 판정 불가")
    else:
        c = hil_notes(base, getattr(mail, "recs", None), now, tgt)
    keys = {x["key"] for x in b}
    bpr = set().union(*[pr_nums(k) for k in keys]) if keys else set()
    c = [x for x in c if not (set(x["pr"]) & bpr) and x["next"] not in keys and not (pr_nums(x["next"]) & bpr)]
    return {"a": sorted({int(n) for t in teams or [] if "error" not in t for n in (t.get("oppa_todo") or [])}), "b": b, "c": c, "bad": bad}


def pick(goal: str, col: str, cs) -> str:
    """K3 값 — 원장 «기다림» 칸 글 우선 · 없으면 ⓒ 골좌표 글에 골 이름이 든 것(오래된 순 2 + «외 N») · 없으면 빈 글."""
    if col and col not in ("—", "-"):
        return col
    hit = sorted((x for x in cs or [] if goal and goal in str(x.get("goal") or "")), key=lambda x: x["at"])
    if not hit:
        return ""
    return "; ".join(f"{x['team']} · {x['next']} · {hhmm(x['at'])}" for x in hit[:2]) + (f" (외 {len(hit) - 2})" if len(hit) > 2 else "")


def blamed(goal: str, cur: dict) -> list:
    """K6 — 수집 실패 팀(err)의 카드 골좌표(직전 snap 을 이어 쓴 값)에 그 골 이름이 든 팀들."""
    return sorted(t for t in cur.get("err") or []
                  if goal and any(goal in g for g in ((cur.get("card_goals") or {}).get(t) or {}).values()))


def stale_head(at, now) -> str:
    """K4 머리 줄 — 원장이 STALE_H 시간 넘게 낡았으면 1줄 · 그 안 = 빈 글 · 시각 모름 = «원장 시각 판정 불가»."""
    if at is None:
        return "원장 시각 판정 불가 — 골 상태 글 시각 모름"
    gap = (now - at).total_seconds()
    return f"원장 낡음 {int(gap // HOUR)}시간({at:%H:%M} 판) — 골 상태 글은 그때 값" if gap > STALE_H * HOUR else ""


def mbox(base, to: str, body: str) -> int:
    """쪽지 1통 — 25초 상한(로컬 하네스 · 하드 룰 12) · FT_MBOX_SH 로 시험 대체 · 0 = 접수."""
    sh = os.environ.get("FT_MBOX_SH") or str(Path(base) / ".fable-team/comm/mbox.sh")
    try:
        return subprocess.run(["bash", sh, "send", to, "ft-board-news", body], capture_output=True, text=True, timeout=25).returncode
    except (OSError, subprocess.SubprocessError):
        return 1


def stale_notice(base, sha: str, hours: int, now, send=None) -> str:
    """K4 planner 1통 — 같은 원장 sha 로 처음 넘을 때만(표식 state/board/news-stale-<sha10> · 같은 sha 두 번 0).
    «» = 보냈거나 보낼 것 없음 · 그 밖 = 판정 불가 사유 1줄(발행은 그대로 둔다)."""
    if not sha or "없음" in sha or "불명" in sha:
        return ""
    mark = Path(base) / ".fable-team/state/board" / f"news-stale-{sha[:10]}"
    if mark.exists():
        return ""
    to = (seats(base).get("planner") or {}).get("_master")
    if not isinstance(to, str) or not to:
        return "planner _master 없음 — 원장 낡음 쪽지 0"
    body = f"[정리 요청] 골 진행 원장 낡음 {hours}시간 — 원장 sha {sha} · 발행 시각 {now:%Y-%m-%d %H:%M}"
    if (send or (lambda t, b: mbox(base, t, b)))(to, body):
        return "쪽지 발신 실패 — 원장 낡음 쪽지 0"
    mark.parent.mkdir(parents=True, exist_ok=True)
    mark.write_text(f"{now:%Y-%m-%d %H:%M} {sha}\n", encoding="utf-8")
    return ""


def todo_lines(cur: dict, now=None, uid: str = "") -> list:
    """K2 «막힌 것, 오빠 할 일» — 오빠 대기마다 1줄 «<무엇> — <누가 기다림> · <HH:MM(N시간)>» · 오빠 태그 = 첫 줄 1개.
    now = None 이면 열쇠 꼴(«HH:MM(N시간)» 만 뺀다 · 시각만 바뀌어 재발행 0) · «없음» = 셋 다 0 ∧ 판정 불가 0."""
    w = cur.get("waits") or {}
    t = lambda x: f" · {ago(x.get('at'), now)}" if now else ""  # noqa: E731
    out = [f"{x['key']} 질문 — desk 기다림{t(x)}" for x in w.get("b") or []]
    out += [f"{x['next']} — {x['team']} 기다림{t(x)} (질문 장부 등록 0)" for x in w.get("c") or []]
    out = out or ([f"오빠 승인 대기 {cur['h']}건"] if cur["h"] else [])  # ⓐ = 판정 h 한 줄(기준판 꼴 · 시각 없음)
    if out and uid:
        out[0] = f"<@{uid}> {out[0]}"
    return (out + list(w.get("bad") or [])) or ["없음"]  # 사유는 이미 «… 판정 불가» 꼴(그대로 1줄)


def done(r: list) -> bool:
    """닫힌 골 = n·m 숫자이고 n == m(ft_board_news_body.closed 와 같은 술어 · 이 파일은 body 를 import 하지 않는다)."""
    return r[2].isdigit() and r[3].isdigit() and int(r[3]) > 0 and int(r[2]) == int(r[3])


def goal_waits(cur: dict) -> list:
    """K3 — 열린 골 순서대로 «지금 n/m단계 · 기다림: <누구> · <무엇> · <HH:MM>» 1줄(없으면 «»).
    원장에 «기다림» 칸이 있는 표 = 칸이 빈 골도 «둘 다 없음» · 칸이 없는 표 = 대기 있는 골만 줄이 생긴다(기준판 본문 보존)."""
    w, out = cur.get("waits") or {}, []
    rows = [r for r in cur["goals"] or [] if not done(r)]
    has_col = any(len(r) > 6 for r in rows)
    for r in rows:
        val = pick(r[1], r[6] if len(r) > 6 else "", w.get("c") or [])
        bad = blamed(r[1], cur)
        if not val and not has_col and not bad:  # K6 — 수집 실패 팀의 골이면 대기 0 이어도 줄 1개
            out.append("")
            continue
        step = f"지금 {r[2]}/{r[3]}단계" if r[2].isdigit() and r[3].isdigit() else "단계 수 원장에 없음"
        out.append(f"{step} · 기다림: {val or NO_WAIT}" + (f" · 수집 실패: {', '.join(bad)}" if bad else ""))
    return out


def trim(mid: list, k: int) -> list:
    """K2 줄 수 줄이기 — 오래된 순 k줄은 그대로 두고 나머지는 «그 밖의 오빠 대기 N건» 1줄로(줄은 자르지 않는다)."""
    return mid[:k] + ([f"그 밖의 오빠 대기 {len(mid) - k}건"] if k < len(mid) else [])


def clip_next(out: str) -> str:
    """K5 ⓕ — «다음» 칸 골별 줄을 NEXT_MAX 자로 줄인다(골 이름 · 줄은 남긴다 · «그 밖의 골 N개» 접기 0)."""
    lines, on = out.splitlines(), False
    for i, ln in enumerate(lines):
        on = True if ln == "다음" else (False if ln == "막힌 것, 오빠 할 일" else on)
        if on and ": " in ln and len(ln.split(": ", 1)[1]) > NEXT_MAX:
            name, text = ln.split(": ", 1)
            lines[i] = f"{name}: {text[:NEXT_MAX]}"
    return "\n".join(lines) + "\n"
