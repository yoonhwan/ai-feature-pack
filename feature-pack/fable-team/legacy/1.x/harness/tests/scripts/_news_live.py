"""r850 — 옛 꼴 live 픽스처(team·live·working·unknown)에 팀 상태(state·label)를 붙인다 — 값은 ft_team_state.judge 그대로(카드 폴더 없는 팀 · 분 없음).
지도·요약 첫 줄(bucket·status_line)은 state·label 없는 live 를 거절한다(조용한 추정 0) — 옛 픽스처를 쓰는 시험은 이 함수를 거친다."""
from ft_team_state import judge


def with_state(rows: list[dict]) -> list[dict]:
    out = []
    for t in rows:
        seats = ([("WORKING", "", None)] * t["working"] + [("?", "jsonl 없음", None)] * t["unknown"]
                 + [("IDLE", "", None)] * (t["live"] - t["working"] - t["unknown"]))
        state, label = judge(None, seats)
        out.append({**t, "state": state, "label": label})
    return out
