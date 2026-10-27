"""ft-news-verify 알림 장부 — 쪽지 1통 규칙(사건 키 = 실패 칸 하나) · 자체 오류 1통 · 연속 셈(r853 · r1005).

_news_verify.py 가 200줄 상한(CLAUDE.md Code Metrics)을 넘어 분리했다 — 검증·칸 판정은 _news_verify.py 몫이고,
여기는 «무엇을 몇 통 알리나» 만 본다. 발행은 어떤 경우에도 막지 않는다(rc·로그만).
"""
import json
import logging
import os
import subprocess
from datetime import datetime
from pathlib import Path

import _news_verify_lib as lib

LOG = logging.getLogger("ft_news_verify")
TARGET_STREAK = 24
WHO = "ft-news-verify"


class StateCorrupt(Exception):
    """상태 파일이 JSON 으로 안 읽힌다 — «없음»(첫 실행) 과 다르다. 그 회차는 검증 불가이고, 그 파일은 덮어쓰지 않는다."""


def load_state(f: Path, default):
    """상태 파일 — «파일 없음» 만 기본값(첫 실행). 못 읽음·깨진 JSON(STATE) = StateCorrupt(조용한 초기화 0 · r1005 반송 r1)."""
    if not f.is_file():
        return default
    try:
        return json.loads(f.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise StateCorrupt(f"{f.name} — {type(e).__name__}") from e


def check_state(st: Path) -> None:
    """검증 전에 상태 두 파일(streak·alarm)이 읽히는지 본다 — 손상이면 9/9 를 말하지 않고 자체 오류 길로 간다."""
    for name in ("streak.json", "alarm.json"):
        load_state(st / name, {})


def _save(f: Path, data) -> None:
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")


def tell(root: Path, body: str) -> int:
    """planner [긴급] 1통 — 좌석 이름은 명부에서, 쪽지는 mbox.sh 로(다른 알림과 같은 길)."""
    try:
        planner = json.loads((root / ".fable-team/seats-planner.json").read_text(encoding="utf-8"))["_master"]
        p = subprocess.run(["bash", os.environ.get("FT_MBOX") or str(root / ".fable-team/comm/mbox.sh"), "send", planner, WHO, body],
                           capture_output=True, text=True, timeout=7, check=False)
    except (OSError, ValueError, KeyError, subprocess.TimeoutExpired) as e:
        LOG.error("검증 쪽지 못 보냄: %s", e)
        return 1
    if p.returncode != 0:
        LOG.error("검증 쪽지 못 보냄 rc=%s: %s", p.returncode, p.stderr.strip()[:120])
    return p.returncode


def bookkeep(root: Path, st: Path, kind: str, passed: int, out, now: datetime) -> None:
    """연속 24 · 실패 [긴급] 1통 — 사건 키 = «실패 칸 하나»(V2): 그 칸이 정상으로 돌아오면 키를 닫고,
    다시 실패하면 새 사건 1통 · 다른 칸이 늘거나 줄어도 이미 알린 칸은 다시 알리지 않는다.
    r1005 반례 1: «검증 불가» 는 복구가 아니다 — 그 칸의 열린 사건은 닫지도 새로 열지도 않는다."""
    streak = load_state(st / "streak.json", {})
    n = int(streak.get(kind, 0)) + 1 if passed == 9 else 0
    _save(st / "streak.json", {**streak, kind: n})
    open_cells = set(load_state(st / "alarm.json", {}).get("open") or [])  # 지금 열려 있는 사건(칸 이름 하나 단위)
    failing = {name for name, v, _w in out if v in (lib.FAIL, lib.UNKNOWN)}  # 검증 불가는 사건이 아니다(R1 = ERROR 로만)
    unknown = {name for name, v, _w in out if v == lib.UNAVAILABLE}  # 검증 불가 칸 — 사건은 안 닫는다
    fresh = failing - open_cells  # 이번에 새로 열린 칸 = 쪽지 몫
    still = {c for c in open_cells if c in failing or c in unknown}  # 열린 사건 중 아직 참이 아닌 칸
    if os.environ.get("FT_NEWS_VERIFY_NOTIFY", "1") == "0":
        return
    if passed == 9:
        _save(st / "alarm.json", {"open": []})
        if n == TARGET_STREAK and streak.get(f"{kind}-reached") != TARGET_STREAK:
            body = f"[긴급] {kind} 정상화 끝선 도달 — 검증 9/9 연속 {n}회 · {now:%Y-%m-%d %H:%M} (ft-news-verify)"
            if tell(root, body) == 0:
                _save(st / "streak.json", {**streak, kind: n, f"{kind}-reached": TARGET_STREAK})
        return
    if not fresh:  # 새 사건 0(이미 알린 칸이 계속 실패 · 복구된 칸은 닫힘) = 쪽지 0 · 열린 목록만 갱신
        _save(st / "alarm.json", {"open": sorted(still)})
        return
    lines = [f"{name} — {why}" for name, v, why in out if name in fresh]
    body = (f"[긴급] {kind} 검증 {passed}/9 · 새 사건 {len(fresh)}칸 — {', '.join(sorted(fresh))}\n"
            + "\n".join(lines[:4]) + f"\n같은 칸 1통 · 발행은 그대로(검증만 실패) · {now:%Y-%m-%d %H:%M}")
    if tell(root, body) == 0:
        _save(st / "alarm.json", {"open": sorted(still | fresh)})


def self_error(root: Path, st: Path, kind: str, why: str) -> None:
    """R2 — 검증기 자체 실패 = 발행 유지 · ERROR 1줄 · 쪽지 1(같은 사유 연속 = 0통 · 정상 복구 뒤 재발 = 새 1통).
    상태 파일 꼴이 깨져도 여기서는 죽지 않는다(r1005 반례 3) — 꼴 검사는 발행 경로(bookkeep) 몫이다."""
    LOG.error("검증기 자체 실패 — 발행은 그대로: %s", why)
    key = f"self-error|{why[:60]}"
    seen = lib.load(st / "self-error.json", {}).get("key")  # 꼴 깨짐 = «모름»(기본값) — 여기서 죽으면 쪽지를 못 낸다
    if os.environ.get("FT_NEWS_VERIFY_NOTIFY", "1") == "0" or seen == key:
        return
    if tell(root, f"[긴급] {kind} 검증기 자체 실패 — {why[:160]} (발행은 그대로 · R2)") == 0:
        _save(st / "self-error.json", {"key": key})
