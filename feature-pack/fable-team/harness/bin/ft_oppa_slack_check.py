#!/usr/bin/env python3
"""ft_oppa_slack_check — approve-merge --oppa-slack 확인 (r1275 · 판정 2904). 쓰기 0.
CLI: ft_oppa_slack_check.py <질문 글 ts> <40hex>… → 각 sha `SLACK-OK <sha> parent=<ts> reply=<ts>`(rc0) | `REJECT 오빠 슬랙 승인 확인 실패: <사유>`(rc2)
질문 글(부모)에 sha 40자가 낱말로 있고, 오빠(OPPA_SLACK_UID) 답글이 부모 뒤 · 부모 수정 전에 있어야 통과. 꼴이 맞지 않으면 «판정 불가» rc2.
env: FT_SLACK_REPLIES_CMD(시험용 · 이 명령의 stdout = conversations.replies JSON) · FT_SCOPE_SLACK_TOKEN_FILE · FT_SCOPE_SLACK_CHANNEL"""
import json
import os
import re
import shlex
import subprocess
import sys
from decimal import Decimal, InvalidOperation
from pathlib import Path

OPPA_SLACK_UID = "U0AC2JF0M7D"  # 코드 상수 — 바꾸려면 착지·승인 거친 PR (seats-planner.json 은 좌석이 쓸 수 있어 출처로 안 쓴다)
DESK_CHANNEL = "C0C9GRFHJE5"
_HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(p) for p in (Path(os.environ.get("FT_HERMES_SCRIPTS") or "~/.hermes/scripts").expanduser(), _HERE.parent / "harness-install" / "slack-mirror") if p.is_dir()]


class Unjudgeable(Exception):
    pass


def fetch(ts: str) -> list:
    cmd = os.environ.get("FT_SLACK_REPLIES_CMD")
    if cmd:
        r = subprocess.run(shlex.split(cmd), capture_output=True, text=True, timeout=7)
        if r.returncode != 0:
            raise Unjudgeable("조회 rc=%d" % r.returncode)
        body = json.loads(r.stdout)
        if body.get("ok") is not True:
            raise Unjudgeable("ok:false")
        return body["messages"]
    from mirror_lib import paged, read_token  # 7초 + 재시도 1(하드 룰 12) · 쪽 끝까지
    tok = read_token(Path(os.environ.get("FT_SCOPE_SLACK_TOKEN_FILE") or "~/.hermes/secrets/yoonhwan_bot.env").expanduser())
    return paged("https://slack.com/api", tok, "conversations.replies", {"channel": os.environ.get("FT_SCOPE_SLACK_CHANNEL") or DESK_CHANNEL, "ts": ts, "limit": 100})


def dec(v) -> Decimal:
    if not isinstance(v, str) or not re.fullmatch(r"[0-9]+\.[0-9]+", v):
        raise Unjudgeable("ts 꼴 아님")
    return Decimal(v)


def judge(ts: str, shas: list) -> list:
    msgs = fetch(ts)
    if not isinstance(msgs, list) or not msgs or not all(isinstance(m, dict) for m in msgs) or msgs[0].get("ts") != ts or not isinstance(msgs[0].get("text"), str):
        raise Unjudgeable("부모 글 꼴 아님")
    parent, text = dec(ts), msgs[0]["text"]
    edited = msgs[0].get("edited")
    if edited is not None and not (isinstance(edited, dict) and "ts" in edited):
        raise Unjudgeable("edited 꼴 아님")
    replies = [(dec(m.get("ts")), m.get("user")) for m in msgs[1:]]
    out = []
    for sha in shas:
        if not re.search(r"(?<![0-9a-fA-F])%s(?![0-9a-fA-F])" % sha, text, re.I):
            raise ValueError("질문 글에 %s 없음" % sha)
        ok = [t for t, u in replies if u == OPPA_SLACK_UID and t > parent and (edited is None or dec(edited["ts"]) < t)]
        if not ok:
            raise ValueError("오빠 답글 없음(부모 뒤 · 수정 전): %s" % sha)
        out.append("SLACK-OK %s parent=%s reply=%s" % (sha, ts, min(ok)))
    return out


def main(argv: list) -> int:
    if len(argv) < 3 or not re.fullmatch(r"[0-9]+\.[0-9]{6}", argv[1]):
        print("usage: ft_oppa_slack_check.py <질문 글 ts> <40hex>…", file=sys.stderr)
        return 2
    try:
        print("\n".join(judge(argv[1], argv[2:])))
        return 0
    except json.JSONDecodeError:
        why = "판정 불가: 응답이 JSON 아님"
    except ValueError as e:
        why = str(e)
    except (Unjudgeable, KeyError, TypeError, InvalidOperation, subprocess.SubprocessError, OSError, ImportError) as e:
        why = "판정 불가: %s" % (e or type(e).__name__)
    except Exception as e:  # MirrorError(조회 실패) 포함 — 확인 불가 = 거절
        why = "판정 불가: %s" % (str(e)[:120] or type(e).__name__)
    print("REJECT 오빠 슬랙 승인 확인 실패: " + why)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
