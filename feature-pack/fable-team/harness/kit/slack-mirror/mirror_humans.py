"""mirror_humans — inbound 의 허용 사용자(`--human` | `--humans` | `--humans-from-seats`)와 수신 좌석 고정(`--to`) (R205).

세 옵션은 정확히 하나만 쓴다(argparse 가 rc 2). 명부 읽기 실패·빈 목록은 전부 raise — 조용한 기본값 0.
"""
import argparse
import json
import sys
from pathlib import Path

import mirror_inbound as ib
import mirror_lib as lib

USERS_KEY = "_slack_users"
_IGNORED: set[str] = set()


def allowed(m: dict[str, object], ids: frozenset[str], channel: str, *, log: bool = True) -> bool:
    """허용 사용자의 사람 글이면 True. 허용 밖 사용자의 글은 좌석 도달 0 — `log` 면 글당 로그 1줄(본문 0 · 같은 ts 는 한 번만).
    단일 `--human` 모드는 log=False — 옛 is_human 과 stdout/stderr 까지 동일(R205 H2)."""
    if ib.is_human(m, ids):
        return True
    if log and ib.is_user_post(m) and str(m["ts"]) not in _IGNORED:
        _IGNORED.add(str(m["ts"]))
        print(f"ignored: 허용 밖 사용자 user={m.get('user')} ts={m['ts']} channel={channel}", file=sys.stderr)
    return False


def add_args(p: argparse.ArgumentParser) -> None:
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--human", help="답을 받을 Slack 사용자 ID 1개(고정) 예: U0AC2JF0M7D")
    g.add_argument("--humans", help="허용 Slack 사용자 ID 목록(쉼표) 예: U1,U2")
    g.add_argument("--humans-from-seats", action="store_true", help=f"--seats-file 명부의 `{USERS_KEY}` 키({{uid: 호칭}})를 허용 사용자로 읽는다(패스마다 다시)")
    p.add_argument("--to", default="", help="수신 좌석 이름 고정 — 주면 현역 planner 조회 0")


def humans(a: argparse.Namespace) -> frozenset[str]:
    if a.human:
        return frozenset({a.human})
    if a.humans is not None:
        ids = frozenset(u.strip() for u in a.humans.split(",") if u.strip())
    else:
        try:
            data = json.loads(Path(a.seats_file).read_text(encoding="utf-8"))
        except (OSError, ValueError) as e:
            raise lib.MirrorError(f"명부 읽기 실패: {a.seats_file} ({type(e).__name__})") from e
        users = data.get(USERS_KEY) if isinstance(data, dict) else None
        if not isinstance(users, dict):
            raise lib.MirrorError(f"명부에 `{USERS_KEY}`({{uid: 호칭}}) 없음: {a.seats_file}")
        ids = frozenset(str(u) for u in users)
    if not ids:
        raise lib.MirrorError("허용 사용자 0명 — 사람 글을 받을 수 없다")
    return ids
