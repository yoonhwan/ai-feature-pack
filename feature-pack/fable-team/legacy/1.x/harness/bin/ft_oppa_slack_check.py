#!/usr/bin/env python3
"""ft_oppa_slack_check — approve-merge --oppa-slack 확인 (r1275 · 판정 2904). 쓰기 0.
CLI: ft_oppa_slack_check.py <질문 글 ts> <40hex>… → 각 sha `SLACK-OK <sha> parent=<ts> reply=<ts>`(rc0) | `REJECT 오빠 슬랙 승인 확인 실패: <사유>`(rc2)
질문 글(부모)에 sha 40자가 낱말로 있고, 오빠(OPPA_SLACK_UID) 답글이 부모 뒤 · 부모 수정 전 · «다음 질문 전»(질문 글과 같은 작성자의 다음 글 전)에 있어야 통과. 꼴이 맞지 않으면 «판정 불가» rc2.
질문 글이 결정 스레드 안 답글이어도 읽는다(단계 3): 조회 결과에서 ts 가 같은 글을 찾고, 없거나 답글 하나뿐이면 스레드 루트(thread_ts)로 한 번 더 받는다(조회 2회 상한).
env: FT_SLACK_REPLIES_CMD(시험용 · 이 명령의 stdout = conversations.replies JSON · 조회할 ts 는 env FT_SLACK_TS 로 준다) · FT_SCOPE_SLACK_TOKEN_FILE · FT_SCOPE_SLACK_CHANNEL
--reply-only <질문 ts>(r1591) = sha 칸이 없는 질문(설계 승인 등) 모드 — stdout 은 `REPLY-SEEN parent=<ts> reply=<ts>` 한 줄(rc0) · 답글 아직 없으면 rc3 · 판정 불가 rc2 · SLACK-OK 를 «한 줄도» 내지 않는다(승인 길에 못 쓴다)."""
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


class NoReply(Exception):  # r1591 · 답글 아직 없음 = 정상 열린 질문(LookupError·ValueError 를 쓰면 KeyError·판정 불가 분기까지 삼킨다)
    pass


def fetch(ts: str) -> list:
    cmd = os.environ.get("FT_SLACK_REPLIES_CMD")
    if cmd:
        r = subprocess.run(shlex.split(cmd), capture_output=True, text=True, timeout=7, env={**os.environ, "FT_SLACK_TS": ts})
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


def locate(ts: str) -> list:
    """질문 글 ts 가 든 스레드(루트부터)를 돌려준다 — 조회 2회 상한 · 못 찾으면 «판정 불가»."""
    target = ts
    for _ in range(2):
        msgs = fetch(target)
        if not isinstance(msgs, list) or not msgs or not all(isinstance(m, dict) for m in msgs):
            raise Unjudgeable("부모 글 꼴 아님")
        q = next((m for m in msgs if m.get("ts") == ts), None)
        root = (q or msgs[0]).get("thread_ts")
        if q is not None and (root in (None, ts) or msgs[0].get("ts") == root):
            if msgs[0].get("ts") != ts and root in (None, ts):
                raise Unjudgeable("부모 글 꼴 아님")
            return msgs
        if not isinstance(root, str) or root in (ts, target):
            break
        target = root  # 질문 글이 스레드 답글 → 루트로 한 번 더
    raise Unjudgeable("부모 글 꼴 아님(질문 글을 스레드에서 못 찾음)")



def judge(ts: str, shas: list) -> list:
    msgs = locate(ts)
    q = next(m for m in msgs if m.get("ts") == ts)
    if not isinstance(q.get("text"), str):
        raise Unjudgeable("부모 글 꼴 아님")
    parent, text = dec(ts), q["text"]
    edited = q.get("edited")
    if edited is not None and not (isinstance(edited, dict) and "ts" in edited):
        raise Unjudgeable("edited 꼴 아님")
    me = [q.get("user"), q.get("bot_id")]
    after = sorted(((dec(m.get("ts")), m.get("user"), m) for m in msgs if m is not q), key=lambda x: x[0])
    nxt = next((t for t, _, m in after if t > parent and any(a and a in (m.get("user"), m.get("bot_id")) for a in me)), None)   # 다음 질문 = 같은 작성자의 다음 글
    out = []
    for sha in shas:
        if not re.search(r"(?<![0-9a-fA-F])%s(?![0-9a-fA-F])" % sha, text, re.I) and sha:  # r1591 · 빈 sha = 답글 확인 모드(sha 낱말 검사 없음)
            raise ValueError("질문 글에 %s 없음" % sha)
        ok = [t for t, u, _ in after if u == OPPA_SLACK_UID and t > parent and (nxt is None or t < nxt) and (edited is None or dec(edited["ts"]) < t)]
        if not ok:
            raise NoReply("오빠 답글 아직 없음") if not sha else ValueError("오빠 답글 없음(부모 뒤 · 수정 전 · 다음 질문 전): %s" % sha)
        out.append("REPLY-SEEN parent=%s reply=%s" % (ts, min(ok)) if not sha else "SLACK-OK %s parent=%s reply=%s" % (sha, ts, min(ok)))
    return out


def main(argv: list) -> int:
    if argv[1:2] == ["--reply-only"]:  # r1591 · h·sha 칸이 없는 질문(설계 승인 등) — 빈 sha = 답글 확인 모드(REPLY-SEEN 만)
        if len(argv) != 3 or not re.fullmatch(r"[0-9]+\.[0-9]{6}", argv[2]):
            print("usage: ft_oppa_slack_check.py --reply-only <질문 글 ts>", file=sys.stderr)
            return 2
        argv = [argv[0], argv[2], ""]
    if len(argv) < 3 or not re.fullmatch(r"[0-9]+\.[0-9]{6}", argv[1]):
        print("usage: ft_oppa_slack_check.py [--reply-only] <질문 글 ts> [<40hex>…]", file=sys.stderr)
        return 2
    try:
        print("\n".join(judge(argv[1], argv[2:])))
        return 0
    except NoReply as e:  # r1591 · 답글 아직 없음 = 정상 열린 질문(판정 불가 아님 · ANSWERED 아님)
        print("REPLY-NONE parent=%s — %s" % (argv[1], e), file=sys.stderr)
        return 3
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
