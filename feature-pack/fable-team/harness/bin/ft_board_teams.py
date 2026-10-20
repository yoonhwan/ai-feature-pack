"""ft-board teams — 팀마다 한 줄 «일함 / 정지 N분» (R132a · 제안서 §7-5). collect dict 한 장에서만 만든다 — 새 수집 0.

  <팀> | 일함 <WORKING 좌석들> | 진행 <N>(<첫 카드>)
  <팀> | 정지 <N>분 · 기다리는 것 = <그 팀 master 칸의 Mail.wait 문구 그대로> | 진행 <N>(<첫 카드>)      (현역 좌석이 전부 IDLE)
  줄 끝 `· 확인 불가 <N>` = 칸이 «확인 불가(…)» 인 현역 좌석 수(현역 근거 없음 포함 · 숨김 0)
N = 현역 IDLE 좌석(분 계산 가능한 것) 중 가장 최근 턴 끝 뒤 경과. 분을 계산할 좌석이 없으면 «정지 분 확인 불가».
«기다리는 것» 에 결론 문구(다음 발주 없음 등)를 만들어 쓰지 않는다 — 문구는 Mail.wait 가 내는 것 그대로.
"""


def _progress(t: dict) -> str:
    prog = t["progress"]
    return f"진행 {len(prog)}" + (f"({next(iter(prog))})" if prog else "")


def _wait(t: dict) -> str:
    cell = t["seats"].get(t["master"]) if t["master"] else None
    return cell["wait"] if cell else "기다림 확인 불가(master 칸 없음)"


def team_line(t: dict) -> str:
    if t.get("error"):  # 명부 수집 실패 — 이 팀만 «확인 못 함»(팀 목록에서 빼지 않는다 · 판정 r554)
        return f"{t['label']} | 확인 못 함: {t['error']}"
    cells = t["seats"]
    working = sorted(n for n, c in cells.items() if c.get("working"))
    idle = [c["idle_min"] for c in cells.values() if c.get("idle_min") is not None]
    if working:
        mid = f"일함 {', '.join(working)}"
    else:
        mid = f"정지 {min(idle)}분" if idle else "정지 분 확인 불가"
        mid += f" · 기다리는 것 = {_wait(t)}"
    unknown = sum(1 for c in cells.values() if c["text"].startswith("확인 불가"))
    return f"{t['label']} | {mid} | {_progress(t)}" + (f" · 확인 불가 {unknown}" if unknown else "")


def team_lines(d: dict) -> list[str]:
    return [team_line(t) for t in d["teams"]]
