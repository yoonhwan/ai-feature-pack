#!/usr/bin/env python3
"""autonomy_scope_post — approve-scope 가 grant 를 쓰기 «전» #byz-desk 에 1줄 게시 (R298 r3 · 판정 2078 ⓐ).

같은 uid 의 직접 쓰기는 막지 못하므로 «들킨다» — 알림 없는 grant 는 만들지 않는다(실패 = rc 1 · 호출자는 grant 쓰기 0).
성공 stdout = `SLACK-TS <ts>` 1줄 · 실패 stderr = `ERR …` · 토큰 값은 어디에도 출력하지 않는다. 7초 상한은 mirror_lib 의 호출 상한(하드 룰 12).
env: FT_SCOPE_SLACK_TOKEN_FILE(기본 ~/.hermes/secrets/yoonhwan_bot.env) · FT_SCOPE_SLACK_CHANNEL(기본 #byz-desk) · FT_HERMES_SCRIPTS(기본 ~/.hermes/scripts)
"""
import argparse
import os
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_HERMES = Path(os.environ.get("FT_HERMES_SCRIPTS") or "~/.hermes/scripts").expanduser()  # 설치본
_KIT = _HERE.parent / "harness-install" / "slack-mirror"  # 리포 안 키트(설치본이 없는 시험·개발 판)
sys.path[:0] = [str(p) for p in (_HERMES, _KIT) if p.is_dir()]

API = "https://slack.com/api"
DESK_CHANNEL = "C0C9GRFHJE5"  # #byz-desk (com.hermes.byz-slack-talk-inbound.plist 의 --channel)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--text", required=True)
    a = p.parse_args()
    try:
        from mirror_lib import MirrorError, post, read_token
    except ImportError as e:
        print(f"ERR mirror_lib 를 못 찾음: {e}", file=sys.stderr)
        return 1
    try:
        token = read_token(Path(os.environ.get("FT_SCOPE_SLACK_TOKEN_FILE") or "~/.hermes/secrets/yoonhwan_bot.env").expanduser())
        ts = post(API, token, os.environ.get("FT_SCOPE_SLACK_CHANNEL") or DESK_CHANNEL, a.text)
    except MirrorError as e:
        print(f"ERR {e}", file=sys.stderr)
        return 1
    print(f"SLACK-TS {ts}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
