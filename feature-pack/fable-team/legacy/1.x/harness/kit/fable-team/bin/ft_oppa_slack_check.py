#!/usr/bin/env python3
"""ft_oppa_slack_check — approve-merge --oppa-slack 확인 (r1275 · 판정 2904). 쓰기 0.
CLI: ft_oppa_slack_check.py <질문 글 ts> <40hex>… → 각 sha `SLACK-OK <sha> parent=<ts> reply=<ts>`(rc0) | `REJECT 오빠 슬랙 승인 확인 실패: <사유>`(rc2)
질문 글(부모)에 sha 40자가 낱말로 있고, 오빠(OPPA_SLACK_UID) 답글이 부모 뒤 · 부모 수정 전 · «다음 질문 전»(질문 글과 같은 작성자의 다음 글 전)에 있어야 통과. 꼴이 맞지 않으면 «판정 불가» rc2.
질문 글이 결정 스레드 안 답글이어도 읽는다(단계 3): 조회 결과에서 ts 가 같은 글을 찾고, 없거나 답글 하나뿐이면 스레드 루트(thread_ts)로 한 번 더 받는다(조회 2회 상한).
r1606: 창 안 오빠 답글의 «내용» 도 본다 — 답글을 토막(공백·쉼표)으로 나눠 토막 전부가 승인 낱말일 때만 승인, 거절 토막이 하나라도 있으면 REJECT, 모르는 토막이 있으면 REJECT «판정 불가: 답글 내용». «오빠가 답했다» ≠ «오빠가 승인했다».
env: FT_SLACK_REPLIES_CMD(시험용 · 이 명령의 stdout = conversations.replies JSON · 조회할 ts 는 env FT_SLACK_TS 로 준다) · FT_SCOPE_SLACK_TOKEN_FILE · FT_SCOPE_SLACK_CHANNEL · r1857: 첫 인자 `<채널>:<ts>` 면 그 채널(env 보다 앞섬 · 가짜 조회엔 FT_SLACK_CHANNEL 로 준다)
--reply-only <질문 ts>(r1591) = sha 칸이 없는 질문(설계 승인 등) 모드 — stdout 은 `REPLY-SEEN parent=<ts> reply=<ts>` 한 줄(rc0) · 답글 아직 없으면 rc3 · 판정 불가 rc2 · SLACK-OK 를 «한 줄도» 내지 않는다(승인 길에 못 쓴다).
r1764: `--reply-only <부모 ts> --after <글 ts>` = 그 시각 «뒤» 첫 오빠 글만 본다(스레드 새 글 감시 · 글이 더 없으면 rc3) — 승인 길·--after 없는 길은 그대로.
r1776: `--reply-only <질문 ts> [--after <ts>] [--stop-at <ts>[,<ts>…]]`(순서 무관) = 같은 스레드에 있는 stop ts 중 질문 뒤 가장 이른 것 앞에서 창을 끊는다(스레드에 없는 ts 무시) · 승인 길(sha)에 --stop-at = rc2 usage."""
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
CHANNEL = None  # r1857 · 첫 인자 `<채널>:<ts>` 의 채널 — env FT_SCOPE_SLACK_CHANNEL·byz-desk 보다 앞선다
CHAN_TS = re.compile(r"(?:(C[A-Z0-9]{8,12}):)?([0-9]+\.[0-9]{6})")
# r1606 · 답글 «내용» 판정 — 답글을 토막으로 나눈 뒤 토막 전부가 승인 낱말일 때만 승인(«승인 안 함»·«네? 왜요» 는 승인 0). 오빠 확인 대상 — 바꾸려면 PR.
APPROVE_WORDS = frozenset(("네", "예", "승인", "확정", "네 확정", "네, 확정", "진행", "ok", "ㅇㅋ", "go"))
REJECT_WORDS = frozenset(("아니오", "아니요", "아니", "거절", "반려", "보류", "중지", "멈춰", "no", "stop"))
# r1950 · 또는 첫 조각 첫 토막 ∈ {네,예,승인} ∧ 덧말 ≤3토막 ∧ 덧말이 거절·부정 어간으로 시작 0 ∧ «?» 0 → 승인(«네 넓혀요») · 판단 못 하면 승인 0. 오빠 확인 대상 — 바꾸려면 PR.
FIRST_OK = frozenset(("네", "예", "승인"))
TAIL_NO = ("아니", "안", "않", "말", "마", "못", "하지", "보류", "취소", "중지", "멈", "그만", "거절", "반려", "철회", "금지", "잠깐", "나중", "no", "stop", "cancel", "hold")


HEX40 = re.compile(r"(?<![0-9a-fA-F])[0-9a-fA-F]{40}(?![0-9a-fA-F])")


def first_chunk_words(m: dict) -> list:
    """r1696 ⓑ — 답 본문을 줄바꿈과 «/» 로 조각낸 뒤 «첫 비어 있지 않은 조각» 의 토막. «예\n\n헤드는 …» = [예] (설명 줄이 붙어도 승인)."""
    t = m.get("text") if isinstance(m.get("text"), str) else ""
    for chunk in re.split(r"[\r\n]+|\s+/\s+", t):   # r1696 DA R1: 조각 경계 = 줄바꿈·«공백 있는 / » — 붙은 «/»(«네/아니오»)는 경계가 아니다
        ws = [w for w in (x.strip().rstrip(" \t.!~") for x in re.split(r"[\s,]+", chunk.strip().lower())) if w]
        if ws:
            return ws
    return []


def first_word_tail_ok(fc: list) -> bool:
    tail = fc[1:]
    return bool(fc) and fc[0] in FIRST_OK and len(tail) <= 3 and not any("?" in w or "？" in w for w in fc) and not any(s.startswith(TAIL_NO) for w in tail for s in re.split(r"\W+", w))


def reply_words(m: dict) -> list:
    """답글 토막 — 앞뒤 공백 제거 · 영문 소문자 · 끝 문장부호(. ! ~) 제거 뒤 공백·쉼표로 나눈다(«예. 승인» = [예, 승인]). 본문 없으면 빈 목록."""
    t = m.get("text")
    return [w for w in (x.strip().rstrip(" \t.!~") for x in re.split(r"[\s,]+", (t if isinstance(t, str) else "").strip().lower())) if w]


_HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(p) for p in (Path(os.environ.get("FT_HERMES_SCRIPTS") or "~/.hermes/scripts").expanduser(), _HERE.parent / "harness-install" / "slack-mirror") if p.is_dir()]


class Unjudgeable(Exception):
    pass


class NoReply(Exception):  # r1591 · 답글 아직 없음 = 정상 열린 질문(LookupError·ValueError 를 쓰면 KeyError·판정 불가 분기까지 삼킨다)
    pass


def fetch(ts: str) -> list:
    cmd, chan = os.environ.get("FT_SLACK_REPLIES_CMD"), CHANNEL or os.environ.get("FT_SCOPE_SLACK_CHANNEL") or DESK_CHANNEL
    if cmd:
        r = subprocess.run(shlex.split(cmd), capture_output=True, text=True, timeout=7, env={**os.environ, "FT_SLACK_TS": ts, "FT_SLACK_CHANNEL": chan})
        if r.returncode != 0:
            raise Unjudgeable("조회 rc=%d" % r.returncode)
        body = json.loads(r.stdout)
        if body.get("ok") is not True:
            raise Unjudgeable("ok:false")
        return body["messages"]
    from mirror_lib import paged, read_token  # 7초 + 재시도 1(하드 룰 12) · 쪽 끝까지
    tok = read_token(Path(os.environ.get("FT_SCOPE_SLACK_TOKEN_FILE") or "~/.hermes/secrets/yoonhwan_bot.env").expanduser())
    return paged("https://slack.com/api", tok, "conversations.replies", {"channel": chan, "ts": ts, "limit": 100})


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



def judge(ts: str, shas: list, after: str | None = None, stop: list | None = None) -> list:  # r1764 · after = 이 ts «뒤» 만(스레드 새 글 감시) · r1776 stop = 다음 질문 ts
    msgs = locate(ts)
    q = next(m for m in msgs if m.get("ts") == ts)
    if not isinstance(q.get("text"), str):
        raise Unjudgeable("부모 글 꼴 아님")
    parent, text = dec(ts), q["text"]
    floor = dec(after) if after else None  # r1764
    edited = q.get("edited")
    if edited is not None and not (isinstance(edited, dict) and "ts" in edited):
        raise Unjudgeable("edited 꼴 아님")
    me = [q.get("user"), q.get("bot_id")]
    after_msgs = sorted(((dec(m.get("ts")), m.get("user"), m) for m in msgs if m is not q), key=lambda x: x[0])
    stops, seen = [dec(s) for s in stop or []], {t for t, _, _ in after_msgs}  # r1776
    # r1696 ⓐ — 창 끝 = parent 뒤 «같은 작성자의 다음 글»(지금 그대로) · 단 그 글이 «이 sha 를 담고» 있으면(재게시·sha 적은 독촉) 끊지 않고 잇는다.
    #   40hex 없는 같은 작성자 글은 지금처럼 끊는다(«4. 다음 질문» = 창 끝) · sha 마다 다르게 판정하므로 «다른 sha 를 물은 글» 도 그 sha 의 창을 끊는다.
    mine = sorted([(parent, text)] + [(t, m.get("text") if isinstance(m.get("text"), str) else "") for t, _, m in after_msgs
                                       if t > parent and any(a and a in (m.get("user"), m.get("bot_id")) for a in me)], key=lambda x: x[0])
    def has_sha(txt: str, sha: str) -> bool:
        if not sha:
            return bool(HEX40.search(txt))   # --reply-only(r1591) = sha 칸 없음 → 40hex 담은 글(재게시)은 창을 끊지 않는다(카드 ⓗ)
        return bool(re.search(r"(?<![0-9a-fA-F])%s(?![0-9a-fA-F])" % sha, txt, re.I))
    out = []
    for sha in shas:
        if not re.search(r"(?<![0-9a-fA-F])%s(?![0-9a-fA-F])" % sha, text, re.I) and sha:  # r1591 · 빈 sha = 답글 확인 모드(sha 낱말 검사 없음)
            raise ValueError("질문 글에 %s 없음" % sha)
        # r1709: 승인 판정이 없는 질문 감시(sha 빈 값 = --reply-only)는 창을 끊지 않는다 — 같은 스레드 desk 정정·보충 글이 창을 끊어 그 뒤 오빠 답을 영영 못 보던 것(승인 0줄이라 새는 승인도 0)
        brk = [] if not sha else [x for x, txt in mine if x > parent and not has_sha(txt, sha)]   # 이 sha 의 창을 끊는 글 = sha 를 안 담은 같은 작성자 글
        if not sha and stops:  # r1776 · 다음 질문(장부에 있는 ts · 이 스레드 안) 앞에서만 끊는다 · 작성자로 끊지 않음(r1709 정정 글 허용 그대로)
            brk = sorted(x for x in stops if x > parent and x in seen)
        nxt = brk[0] if brk else None
        ok = [(t, m) for t, u, m in after_msgs if u == OPPA_SLACK_UID and t > parent and (nxt is None or t < nxt) and (edited is None or dec(edited["ts"]) < t)
              and (floor is None or t > floor)]
        if not ok:
            raise NoReply("오빠 답글 아직 없음") if not sha else ValueError("오빠 답글 없음(부모 뒤 · 수정 전 · 다음 질문 전): %s" % sha)
        if not sha:  # r1591 · --reply-only 는 «도착» 만 본다(r1606 내용 판정은 승인 길에만 · 범위 밖)
            out.append("REPLY-SEEN parent=%s reply=%s" % (ts, ok[0][0]))
            continue
        said = [(t, reply_words(m), first_chunk_words(m)) for t, m in ok]
        no = [t for t, ws, _ in said if REJECT_WORDS.intersection(ws)]  # r1606 · 거절은 «본문 전체» 토막 검사 그대로(«예\n근데 보류» = 거절)
        if no:
            raise ValueError("오빠 거절 답글 reply=%s" % no[0])
        yes = [t for t, _, fc in said if fc and all(w in APPROVE_WORDS for w in fc)] or [t for t, _, fc in said if first_word_tail_ok(fc)]  # r1696 ⓑ · r1950 · «첫 조각» 의 토막이 전부 승인 낱말이면 승인
        if not yes:  # r1606 · 오타·모르는 토막 = 승인 0 (BYZ #8243 «tmddls»)
            raise Unjudgeable("답글 내용 승인 낱말 아님")
        out.append("SLACK-OK %s parent=%s reply=%s" % (sha, ts, yes[0]))
    return out


def main(argv: list) -> int:
    args, opt = argv[1:], {}
    for flag in ("--after", "--stop-at"):  # r1764·r1776 · --reply-only 전용(승인 길에 새 인자를 끼우지 않는다) · 순서 무관
        if flag in args:
            i = args.index(flag)
            v = args[i + 1] if i + 1 < len(args) else ""
            if args[0] != "--reply-only" or not re.fullmatch(r"[0-9]+\.[0-9]{6}" + (r"(,[0-9]+\.[0-9]{6})*" if flag == "--stop-at" else ""), v):
                print("usage: ft_oppa_slack_check.py --reply-only <부모 글 ts> [--after <이 ts 뒤>] [--stop-at <ts>[,<ts>…]]", file=sys.stderr)
                return 2
            args, opt[flag] = args[:i] + args[i + 2:], v
    after, stop = opt.get("--after"), opt["--stop-at"].split(",") if "--stop-at" in opt else None
    if args[:1] == ["--reply-only"]:  # r1591 · h·sha 칸이 없는 질문(설계 승인 등) — 빈 sha = 답글 확인 모드(REPLY-SEEN 만)
        if len(args) != 2 or not CHAN_TS.fullmatch(args[1]):
            print("usage: ft_oppa_slack_check.py --reply-only <질문 글 ts>", file=sys.stderr)
            return 2
        args = [args[1], ""]
    if len(args) < 2 or not CHAN_TS.fullmatch(args[0]):
        print("usage: ft_oppa_slack_check.py [--reply-only] [<채널>:]<질문 글 ts> [<40hex>…]", file=sys.stderr)
        return 2
    global CHANNEL
    CHANNEL, parent = CHAN_TS.fullmatch(args[0]).groups()  # r1857  # r1764 보정 · NoReply 문구는 부모 ts(예전 argv[1] 재할당 빠짐으로 «parent=--reply-only» 가 새었나)
    try:
        print("\n".join(judge(parent, args[1:], after, stop)))
        return 0
    except NoReply as e:  # r1591 · 답글 아직 없음 = 정상 열린 질문(판정 불가 아님 · ANSWERED 아님)
        print("REPLY-NONE parent=%s — %s" % (parent, e), file=sys.stderr)
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
