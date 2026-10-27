"""ft-board teams — 팀마다 한 줄 «진행 · 대기 · 쉼 · 확인 불가» (R132a · 제안서 §7-5 · r850). collect dict 한 장에서만 만든다 — 새 수집 0.

  <팀> | <팀 상태 글자> [· 일함 <WORKING 좌석들>] | 진행 <N>(<첫 카드>)
팀 상태 글자 = 블록의 team_state(ft_board_collect.attach_team_states = ft_team_state.team_states · 뉴스 지도·요약 첫 줄과 같은 결과 · r850 r4) 그대로 —
  시트가 좌석 칸(ft_board_seat «현역 근거»)으로 따로 판정하지 않는다 · team_state 없는 옛 스냅샷 = «확인 불가(팀 상태 없음)»:
  «진행 · 일하는 좌석 W/L» · «진행 · N분 전 턴» · «진행 · 진행 카드 0 · 일하는 좌석 W/L» · «대기 N분 · 기다리는 것 = <wait 그대로>» · «대기 · 열린 좌석 0 · 기다리는 것 = …» · «쉼 · 진행 카드 0» · «확인 불가(<사유> N석)»
  줄 끝 `· 확인 불가 <N>` = team_state 의 확인 불가 좌석 수(숨김 0)
«기다리는 것» 에 결론 문구(다음 발주 없음 등)를 만들어 쓰지 않는다 — 문구는 Mail.wait 가 내는 것 그대로.
한 팀 = 반드시 한 줄 — 오류 문장(traceback)·wait 문구의 줄바꿈·CR 은 « ⏎ » 로 접는다(DA⑥ r1 반례 ②: 여러 줄이면 접기가 «… 외 N줄» 로 깨졌다).
"""


def _one_line(text: str) -> str:
    """줄바꿈·CR 을 « ⏎ » 로 접어 한 줄로 — 팀 수 = 출력 줄 수 를 지킨다."""
    for nl in ("\r\n", "\r", "\n"):
        text = text.replace(nl, " ⏎ ")
    return text


def _progress(t: dict) -> str:
    prog = t["progress"]
    return f"진행 {len(prog)}" + (f"({next(iter(prog))})" if prog else "")


def team_line(t: dict) -> str:
    if t.get("error"):  # 명부 수집 실패 — 이 팀만 «확인 못 함»(팀 목록에서 빼지 않는다 · 판정 r554)
        return _one_line(f"{t['label']} | 확인 못 함: {t['error']}")
    s = t.get("team_state")
    if not isinstance(s, dict):
        return _one_line(f"{t['label']} | 확인 불가(팀 상태 없음) | {_progress(t)}")
    mid = s["label"] + (f" · 일함 {', '.join(s['working'])}" if s["working"] else "")
    return _one_line(f"{t['label']} | {mid} | {_progress(t)}" + (f" · 확인 불가 {s['unknown']}" if s["unknown"] else ""))


def team_lines(d: dict) -> list[str]:
    return [team_line(t) for t in d["teams"]]
