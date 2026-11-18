"""thread_post_ask — byz_thread_post `ask`(r2235): desk 의 오빠 질문 단일 입구. D2 재판정 값을 게시 «전» 에 검사 → 게시 1회 → 감시 등록 1회.

`ask (--to <등록부 이름> | --ts <뿌리> --channel <ID>) --key <사유키> --d2 <1|2|3|off> --why "<왜 사람>" --default "<답 전 기본값>" --text-file <본문>`
  O1 --key · --d2 · --why · --default 중 하나라도 없음 = rc3 «D2 재판정 값 없음» · 게시 0 · 등록 0
  O2 --why 에서 팀 판정 낱말을 모두 빼고 공백을 걷은 글이 10자 미만 = rc3 «팀 판정은 근거가 아님»
  O3 --d2 = 1 · 2 · 3 · off 만 · 1 · 2 면 --default 에 «안 함» 필수 = 아니면 rc3
  O4 게시 전 감시 도구(FT_DESK_REPLY_WAKE › <루트>/.fable-team/LIVE_BIN 1줄 폴더 › <루트>/.fable-team/bin)와
     장부 폴더(FT_DESK_REPLY_LEDGER 또는 <루트>/.fable-team/state/desk-reply-wait.jsonl)·잠금 파일이 실재 = 아니면 rc2 게시 0
     통과 = 본문 끝 «왜 사람 · 답 전 기본값» 2줄 → post_guard 길(post · reply 와 같은 채널 고르기)로 게시
     → `ft_desk_reply_wake.py --register-question <ts> <키> --d2 <값> --why <글>`. 게시 실패 = rc1 등록 0 · 등록 실패 = rc1 + «게시 ts=<ts> · 등록 손으로».
  자율 상태(--d2 off)와 분류의 옳고 그름은 판정하지 않는다(카드 한계 2 · 3). 루트 = env FT_ROOT 또는 post_guard.DEFAULT_ROOT.
"""
import argparse
import os
import re
import subprocess
import sys
from collections.abc import Callable
from pathlib import Path

from magazine_slack import Target
from mirror_lib import MirrorError, esc
from post_guard import DEFAULT_ROOT, ROOT_ENV, check, guarded_post as post
from thread_post_update import TS, oppa_tag, topic_channel

REQUIRED = ("key", "d2", "why", "default")
D2_VALUES = ("1", "2", "3", "off")
TEAM_WORDS = ("자율 범위 밖", "범위 밖", "오빠 판단 필요", "오빠 결정 필요", "팀 판정")
KEY = re.compile(r"[a-z0-9][a-z0-9._-]{0,63}$")  # ft_desk_reply_wake.KEY 와 같은 꼴 — 게시 뒤 등록 거절을 게시 전에 막는다
SPACE = re.compile(r"\s+")
WHY_MIN, REG_TO = 10, 25  # 왜 사람 최소 글자 · 등록 25초(로컬 하네스 상한)
WAKE = "ft_desk_reply_wake.py"


def strip_team_words(text: str) -> str:
    for w in TEAM_WORDS:
        text = text.replace(SPACE.sub("", w), "")
    return text


def reason_left(why: str) -> str:
    """팀 판정 낱말을 모두 빼고 공백을 걷은 글 — 공백을 먼저 걷어 «자율범위 밖» 같은 띄어쓰기 우회도 뺀다."""
    return strip_team_words(SPACE.sub("", why))


def refusal(a: argparse.Namespace) -> str:
    """O1~O3 — 거절 사유 1줄 · 통과 = 빈 글."""
    missing = [f"--{n}" for n in REQUIRED if not (getattr(a, n) or "").strip()]
    if missing:
        return f"D2 재판정 값 없음 — {' '.join(missing)} · 선택지마다 D2 3문을 다시 묻고 «예» 인 선택지만 ask"
    if a.d2 not in D2_VALUES:
        return f"--d2 는 1 · 2 · 3 · off 만: {a.d2}"
    if len(reason_left(a.why)) < WHY_MIN:
        return f"팀 판정은 근거가 아님 — 선택지마다 D2 3문 · --why 는 팀 낱말을 빼고 {WHY_MIN}자 이상"
    if a.d2 in ("1", "2") and "안 함" not in a.default:
        return f"D2 {a.d2}번 기본값 = 안 함 · 지금 상태 유지 — --default 에 «안 함» 없음"
    if not KEY.match(a.key):
        return f"--key 는 사유키 꼴(소문자 · 숫자 · ._- · 64자): {a.key}"
    return ""


def watch_target() -> tuple[Path, Path, Path] | str:
    """O4 — (루트, 감시 도구, 장부) 또는 못 찾은 사유 1줄. 게시 «전» 에만 부른다."""
    root = Path(os.environ.get(ROOT_ENV) or DEFAULT_ROOT)
    env = os.environ.get("FT_DESK_REPLY_WAKE", "").strip()
    live = root / ".fable-team" / "LIVE_BIN"
    folder = live.read_text(encoding="utf-8").strip().split("\n", 1)[0].strip() if live.is_file() else ""
    tools = [Path(env)] if env else ([Path(folder) / WAKE] if folder else []) + [root / ".fable-team" / "bin" / WAKE]
    tool = next((t for t in tools if t.is_file()), None)
    led = Path(os.environ.get("FT_DESK_REPLY_LEDGER") or root / ".fable-team/state/desk-reply-wait.jsonl")
    if tool is None or not (root / ".fable-team").is_dir():
        return f"도구 {' · '.join(map(str, tools))} · 루트 {root}"
    if not led.parent.is_dir():
        return f"장부 폴더 {led.parent}"
    try:
        open(led.parent / (led.name + ".lock"), "a").close()  # 도구가 쓰는 잠금 파일 — 열 수 있어야 등록이 된다
    except OSError as e:
        return f"장부 잠금 {led}.lock ({type(e).__name__})"
    return root, tool, led


def register(root: Path, tool: Path, led: Path, ts: str, a: argparse.Namespace) -> tuple[int, str]:
    cmd = [sys.executable, str(tool), "--register-question", ts, a.key, "--d2", str(a.d2), "--why", str(a.why).strip()]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=REG_TO, cwd=root,
                           env={**os.environ, ROOT_ENV: str(root), "FT_DESK_REPLY_LEDGER": str(led)})
    except (subprocess.TimeoutExpired, OSError) as e:
        return 1, type(e).__name__
    return r.returncode, (r.stdout if r.returncode == 0 else r.stderr).strip()


def cmd_ask(a: argparse.Namespace, target: Callable[[argparse.Namespace], Target]) -> int:
    reason = refusal(a)
    if reason:
        print(f"REJECT {reason} · 게시 0", file=sys.stderr)
        return 3
    found = watch_target()
    if isinstance(found, str):
        print(f"판정 불가 — 감시 도구 · 장부 없음({found}) · 게시 0", file=sys.stderr)
        return 2
    if a.ts is not None and not TS.fullmatch(a.ts):
        raise MirrorError(f"--ts 는 슬랙 ts 꼴(예 1700000000.000100): {a.ts}")
    body = Path(a.text_file).read_text(encoding="utf-8").strip()
    if not body:
        raise MirrorError(f"본문이 비었다: {a.text_file}")
    full = f"{body}\n왜 사람: {str(a.why).strip()}\n답 전 기본값: {str(a.default).strip()}"
    ch = str(a.channel) if a.ts is not None else topic_channel(a)
    text = esc(full)
    check(text, ch, human=True)  # 사람 채널 — 글 «전» 거절(게시 0)
    text = oppa_tag(text, full, True)  # 오빠께 묻는 글 — 태그 1개(r2190 · 검사 «뒤»)
    t = target(a)
    ts = post(t.base, t.token, ch, text, a.ts, human=True, head=full if a.ts is None else None)  # 실패 = raise → rc1 · 등록 0
    print(f"POSTED {ts}")
    rc, out = register(*found, ts, a)
    if rc:
        print(f"ERROR 감시 등록 실패(rc{rc}) {out} — 게시 ts={ts} · 등록 손으로", file=sys.stderr)
        return 1
    print(out)
    return 0
