"""r2065 E8 명부 찾기 한 함수 — 코어와 어댑터가 같은 규칙을 쓰게 정의는 코어에 둔다(ft2-launch-failed-end L11).

core 는 실행 환경(어댑터)을 모른다 — 방향은 어댑터 → 코어 한 길만 있다. 그래서 명부 경로를 만드는 자리는
여기 하나이고, `adapters/pi/launch_roster.py` 는 이 함수를 경로로 묶어 같은 이름으로 다시 내보낸다(정의 1곳).
"""

import os


def roster_path(root, team):
    """r2065 E8 명부 찾기 한 함수 — `<root>/.fable-team/seats-<팀>.json` 이 있으면 그 파일 · 없고 팀이 v65 면 `seats.json` · 그 밖 = None(명부 없음).

    인자 = (루트 경로, 팀 이름) · 반환 = 절대 경로 또는 None · 못 읽는 명부는 부르는 쪽이 다음 칸으로 간다(여기서 읽지 않는다).
    부르는 곳 = Execution._master(현역 master 판독 · L11) · keeper_report.notify(팀 명부·harness 명부) · launch_roster.enroll(L10).
    """
    names = ["seats-%s.json" % team] + (["seats.json"] if team == "v65" else [])   # v65 팀 명부 = seats.json(seats-v65.json 은 없다 · 실측 2026-11-16)
    for name in names:
        path = os.path.join(root, ".fable-team", name)
        if os.path.exists(path):
            return path
    return None
