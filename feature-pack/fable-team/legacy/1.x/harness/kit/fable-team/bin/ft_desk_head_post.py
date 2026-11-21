"""ft_desk_head_post.py [--root R] [--now ISO]  (r2390 K4 · K5 · ft-board-publish.sh --news 가 판마다 1회 부름)

TEAM-STATUS.md 1행(칸 8개)을 읽어 Slack 메인에 머리 1통을 올린다 — 골 알림 본문 발행과 같은 판에서 따로 1통(본문 손 0).
  열쇠 = 칸 8개 값(«?» 포함 · planner [정리] 칸의 «(N분 전)» 는 뺀다 · «HH:MM» 까지만)
  직전 머리 발행(state/board/head-last.json)과 열쇠가 다르면 1통
  같아도 0 아닌 칸(오빠 답 기다림 · 스크립트 · 막힌 팀 · 원장 낡음 · 오빠 지시 멈춤 · 담당 없음)이 있고 직전 발행 3시간 넘으면 1통(«그대로 N시간» 꼬리)
  그 밖 = 침묵(«변화 없음 — 발행 0» rc0) · «?» = 못 잰 칸이라 재발행 사유가 아니다(그 사실은 2행이 진다)
  K5 오빠 태그 = 오빠 답 기다림 ≥ 1 또는 스크립트 ≥ 1 일 때만 1개(r2102 꼴 · --keep-mention)
  1행 파일 10분 넘게 낡음 = 발행 0 + stderr «판정 불가 머리 줄 낡음» rc0 · 발행 실패 = head-last 쓰기 0 + desk [긴급] 1통(30분 창)
"""
from __future__ import annotations  # mini python 3.9.6

import json
import os
import re
import subprocess
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path

STATUS_REL = Path(".fable-team") / "state" / "planner-tick" / "TEAM-STATUS.md"
LAST_REL = Path(".fable-team") / "state" / "board" / "head-last.json"
FAIL_REL = Path(".fable-team") / "state" / "board" / "head-fail-last.json"
CARDS = 8
NAMES = ("자율", "오빠 답 기다림", "스크립트", "막힌 팀", "planner [정리]", "원장 낡음", "오빠 지시 멈춤", "담당 없음")
STALE_SEC = 600  # 1행 10분 낡음 = 발행 0
STANDING_SEC = 10800  # 3시간 그대로
FAIL_WINDOW_SEC = 1800  # desk [긴급] 같은 단계 30분 창
MIN = re.compile(r"\(([0-9]+)분 전\)")
COUNT = re.compile(r"^([0-9]+)")
TAG = "오빠 태그"


def hhmm(t: float) -> str:
    return time.strftime("%H:%M", time.localtime(t))


def cells(first: str) -> list:
    """1행 → 칸 8개 값 · 꼴 다르면 빈 목록(판정 불가)."""
    got = [c.strip() for c in first.strip().split(" · ")]
    return got if len(got) == CARDS else []


def numeric(cell: str) -> int:
    """칸 앞 숫자 — «?»·꼴 다름 = 0(재발행 사유 아님 · 못 잰 칸은 2행이 진다)."""
    m = COUNT.match(cell.strip())
    return int(m.group(1)) if m else 0


def wait_cards(got: list) -> dict:
    """{칸 이름: 값} — 이름은 K1 순서 고정 · 각 칸이 그 이름으로 시작하지 않으면 빈 dict(꼴 다름)."""
    out = {}
    for name, cell in zip(NAMES, got):
        if not cell.startswith(name + " "):
            return {}
        out[name] = cell[len(name) + 1:].strip()
    return out if len(out) == CARDS else {}


def key_of(got: list) -> list:
    """열쇠 = 칸 8개 값 — planner [정리] 칸의 «(N분 전)» 만 뺀다(시각 «N분 전» 은 열쇠 밖)."""
    return [MIN.sub("", c).strip() for c in got]


def standing(got: list) -> bool:
    """0 아닌 칸이 있나 — 자율 · planner [정리] 는 세지 않는다(K4 꼴 그대로)."""
    w = wait_cards(got)
    return any(numeric(v) > 0 for n, v in w.items() if n not in ("자율", "planner [정리]"))


def tag_on(got: list) -> bool:
    """K5 — 오빠 답 기다림 ≥ 1 또는 스크립트 ≥ 1 일 때만 태그."""
    w = wait_cards(got)
    return any(numeric(v) >= 1 for n, v in w.items() if n in ("오빠 답 기다림", "스크립트"))


def fail_mark(path: Path, now: float, mark: bool) -> bool:
    """30분 창 — True = 보낸다 · 표식은 send 성공 뒤에만(mark=True)."""
    try:
        d = json.loads(path.read_text(encoding="utf-8"))
        last = float(d["at"])
    except (OSError, ValueError, KeyError, TypeError):
        last = 0.0
    if not mark:
        return now - last >= FAIL_WINDOW_SEC
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"at": now}), encoding="utf-8")
    return True


def fail_notice(root: Path, now: float, why: str) -> None:
    """발행 실패 = 지금 news_fail 길 — planner _desk 에 [긴급] 1통 · 좌석 없음·전송 실패 = stderr 1줄."""
    mark = Path(os.environ.get("FT_DESK_HEAD_FAIL") or (root / FAIL_REL))
    if not fail_mark(mark, now, False):
        return
    mbox = os.environ.get("FT_MBOX") or str(root / ".fable-team" / "comm" / "mbox.sh")
    try:
        desk = json.loads((root / ".fable-team" / "seats-planner.json").read_text(encoding="utf-8")).get("_desk") or ""
    except (OSError, ValueError):
        desk = ""
    try:
        r = subprocess.run(["bash", mbox, "send", desk, "ft-desk-head", f"[긴급] 머리 줄 발행 실패 — {why}"],
                           capture_output=True, text=True, timeout=25)
        ok = bool(desk) and r.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        ok = False
    if ok:
        fail_mark(mark, now, True)
    else:
        print(f"ft_desk_head_post: 판정 불가 — desk 알림 실패({why})", file=sys.stderr)


def post(root: Path, text: str, uid: str, keep: bool) -> int:
    """byz_thread_post.py post 1회 — 골 알림과 같은 도구·같은 채널(FT_BOARD_POST_ARGS)."""
    tp = os.environ.get("FT_THREAD_POST") or str(Path.home() / ".hermes" / "scripts" / "byz_thread_post.py")
    args = (os.environ.get("FT_BOARD_POST_ARGS") or "").split()
    fd, tmp = tempfile.mkstemp(prefix=".head-post.", dir=str(root / ".fable-team" / "state"))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        cmd = ["python3", tp, "post", *args, "--no-status-head"]
        cmd += ["--keep-mention", uid] if keep and uid else []
        r = subprocess.run(cmd + ["--text-file", tmp], capture_output=True, text=True, timeout=25)
        return r.returncode if r.returncode != 0 else 0
    except (OSError, subprocess.TimeoutExpired):
        return 124
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass


def main(argv: list) -> int:
    root = Path(os.environ.get("FT_ROOT") or os.getcwd())
    now = time.time()
    for a, b in zip(argv[::2], argv[1::2]):
        if a == "--root":
            root = Path(b)
        elif a == "--now":
            try:
                now = datetime.fromisoformat(b).timestamp()
            except ValueError:
                print(f"판정 불가 — --now 꼴 {b}", file=sys.stderr)
                return 2
        else:
            print("usage: ft_desk_head_post.py [--root R] [--now ISO]", file=sys.stderr)
            return 2
    f = Path(os.environ.get("FT_TEAM_STATUS_FILE") or (root / STATUS_REL))
    try:
        lines = f.read_text(encoding="utf-8").splitlines()
        mtime = f.stat().st_mtime
    except (OSError, UnicodeDecodeError):
        print("판정 불가 머리 줄 없음 — 발행 0", file=sys.stderr)
        return 0
    if now - mtime > STALE_SEC:
        print("판정 불가 머리 줄 낡음 — 발행 0", file=sys.stderr)
        return 0
    got = cells(lines[0] if lines else "")
    if not got:
        print("판정 불가 머리 줄 꼴 다름 — 발행 0", file=sys.stderr)
        return 0
    last_p = Path(os.environ.get("FT_DESK_HEAD_LAST") or (root / LAST_REL))
    try:
        last = json.loads(last_p.read_text(encoding="utf-8"))
        same = last.get("key") == key_of(got)
        prev_at = float(last["at"])
    except (OSError, ValueError, KeyError, TypeError):
        same, prev_at = False, 0.0
    tail, uid = "", os.environ.get("FT_OPPA_SLACK_UID") or ""
    if same:
        if not (standing(got) and now - prev_at > STANDING_SEC):
            print("ft_desk_head_post: 변화 없음 — 발행 0")
            return 0
        tail = f" · 그대로 {max(0, int((now - prev_at) // 3600))}시간"
    keep = tag_on(got)
    head = lines[0].rstrip() + tail + (f" <@{uid}>" if keep and uid else "")
    text = "\n".join([head] + lines[1:2]) + "\n"
    rc = post(root, text, uid, keep)
    if rc != 0:
        print(f"ft_desk_head_post: 발행 실패 rc={rc} — head-last 그대로", file=sys.stderr)
        fail_notice(root, now, f"post rc={rc}")
        return 0
    try:
        last_p.parent.mkdir(parents=True, exist_ok=True)
        tmp = last_p.with_suffix(".tmp")
        tmp.write_text(json.dumps({"at": now, "key": key_of(got)}, ensure_ascii=False), encoding="utf-8")
        os.replace(tmp, last_p)
    except OSError as e:
        print(f"판정 불가 — head-last 기록 실패 {e}", file=sys.stderr)
        return 1
    print(f"ft_desk_head_post: 머리 1통 발행({hhmm(now)})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
