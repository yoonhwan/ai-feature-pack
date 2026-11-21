"""ft_board_news_wait 사본 스텁 — r2390 시험·r2255 시험용 (r2389 미착지 · 카드 r2390 한계 1).

r2389 ft_board_news_wait 의 계약만 옮긴 사본이다(같은 이름·같은 인자·같은 dict).
  waits(base, teams, mail, now) → {"a": [판정 h], "b": [답 안 온 장부 줄], "c": [장부 미등록 팀장 [HIL]], "bad": [사유]}
  H1(DA#54) = 답 안 온 줄만 — 장부 실물의 «답 온» 표시 = state closed(closed 기둥이 붙는다) · notified_at 세부 판정은 r2389 착지 판이 정한다
  todo_lines(base, now) → «오빠 할 일» 줄들(장부 갈래만) — r2390 반례 ③ 의 대조군
r2389 가 착지하면 이 파일은 쓰이지 않는다(FT_BOARD_NEWS_WAIT_BIN 을 실제 bin 으로 두면 그 모듈이 먼저 잡힌다).
"""
import json
from pathlib import Path

LEDGER = ".fable-team/state/desk-reply-wait.jsonl"
BAD = "오빠 질문 장부 판정 불가"


def answered(r):
    """답이 온 줄인가 — H1(r2389 DA#54): state closed(closed 기둥) = 답 온 줄. 나머지는 아직 기다리는 줄."""
    return r.get("state") == "closed"


def waits(base, teams, mail, now):
    p = Path(base) / LEDGER
    if not p.is_file():  # 아직 없는 루트 = 등록 0(r2389 계약)
        return {"a": [], "b": [], "c": [], "bad": []}
    try:
        rows = [json.loads(x) for x in p.read_text(encoding="utf-8").splitlines() if x.strip()]
    except (OSError, ValueError):
        return {"a": [], "b": [], "c": [], "bad": [BAD]}
    last = {}
    for r in rows:
        if isinstance(r, dict) and isinstance(r.get("q_ts"), str):
            last[(r.get("kind") or "h", r["q_ts"])] = r
    out = []
    for k, r in last.items():
        if r.get("state") == "closed":
            continue
        if answered(r):
            continue  # 답이 온 줄(H1)
        out.append({"key": str(r.get("key") or k[1]), "kind": k[0], "q_ts": k[1], "at": int(r.get("at") or 0)})
    return {"a": [], "b": sorted(out, key=lambda x: (x["at"], x["key"])), "c": [], "bad": []}


def todo_lines(base, now=None, uid=""):
    """«오빠 할 일» 줄들 — 장부 갈래 1줄씩(r2390 ③ 대조군)."""
    return [f"{x['key']} 질문 — desk 기다림" for x in waits(base, [], None, now or 0)["b"]]
