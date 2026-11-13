"""r1850 Slack 글 보낸이 표시 — 좌석 이름 → «보낸이 <팀-역할>» 1줄(사람이 Slack 검색창에 치는 낱말).
문법 = ft-name-lint.sh(역할 예약어 · AGENTS · 길이 60) · 못 넘으면 None(표시 0 · 게시는 그대로). 번호·에이전트·slug 는 넣지 않는다."""
import re

ROLES = frozenset("master arch da tester checker analyst pm nano repro tool desk qa".split())
AGENTS = frozenset("claude codex opencode cmd pi".split())  # ft-name-lint.sh AGENTS 와 같음
_NAME = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+){2,}#[0-9]+")


def sender_tag(seat, seq=None):
    """`byz-planner-desk-pi#147` → `보낸이 planner-desk` · nano = `<팀>-nano` · qa 범위 1토큰은 역할에 붙임 · r1856 seq = 끝 숫자 1개."""
    tag = _tag(seat)
    return "%s %s" % (tag, seq) if tag and seq else tag


def _tag(seat):
    if not isinstance(seat, str) or len(seat) > 60 or not _NAME.fullmatch(seat):
        return None
    _project, team, role, *tail = seat.rsplit("#", 1)[0].split("-")
    if role == "nano":  # slug 꼬리 없음 = lint 실패 = None(DA HOLD R1)
        return "보낸이 %s-nano" % team if tail else None
    scope = tail[:-1] if role == "qa" else []
    if role not in ROLES or len(tail) != len(scope) + 1 or len(scope) > 1 or tail[-1] not in AGENTS:
        return None
    return "보낸이 %s" % "-".join([team, role] + scope)
