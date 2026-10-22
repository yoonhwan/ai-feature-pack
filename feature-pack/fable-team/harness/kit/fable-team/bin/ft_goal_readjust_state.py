"""ft_goal_readjust_state — 골 재조정 «회차 파일 읽기» (r714a · 골 표 render 가 부른다 · import 0 = 순환 방지).

회차 파일 = `<루트>/.fable-team/state/goal-readjust/rounds/<run>-<nn>.json` — 한 번 쓴 파일은 고치지 않는다(덮어쓰기 0 · 계약은 ft_goal_readjust.py).
«마지막 성공»·«최근 시도» 는 포인터 파일 없이 목록에서 **파생**한다 — `last_ok` = 이름순 가장 최근 status=OK 파일 · `last_attempt` = 가장 최근 파일
(실패 시도는 OK 파일을 건드리지 않으므로 «직전 성공 보존» 질문이 사라진다 · 설계 r3 §1).
read(root=None)              → `{last_ok, last_attempt}` (없으면 둘 다 None) · 루트 = env FT_ROOT › LIVE_ROOT(1행 절대경로 폴더)
                               · `_send` = 그 시도의 영수증(`.sent.json`/`.send-failed.json`)에서 읽은 송신 상태(영수증 없음 + claimed = `unknown` — 렌더가 «송신 실패/모름» 을 보인다)
row_cell(state, n, goal_hash, canon_sha10) → «재조정» 칸 글자(≤24자) — 회차 파일 행의 `goal_hash`(골 전문 sha10)가 지금 렌더 행과 같을 때만 라벨을 쓴다
                               (다르면 `모름(판 다름)` · 정본 sha 만 다르고 전문이 같으면 라벨 뒤 `·정본 바뀜` · 설계 r3 §4 «대응 대조»)
header(state, now=None)      → 머리 글자 `재조정: ok=<run> <HH:MM> · 최근=<run>-<nn> OK|ERROR <사유 24자>` · 기록 없음 `재조정 기록 없음`
                               · 마지막 성공이 FT_GOAL_READJUST_MAX_H(26)시간 전 `재조정 없음 N시간 · ok=… · 최근=…` — 마지막 성공과 최근 시도를 항상 둘 다 보인다
                               · 송신 실패/모름이면 끝에 `·송신 실패`/`·송신 모름`(조용한 OK 0)
"""
from __future__ import annotations

import json
import os
from datetime import datetime
from pathlib import Path

DIR = "goal-readjust"
CELL = 24
MAX_H = 26
SKIP = (".sent.json", ".send-failed.json")  # 영수증 파일은 회차 파일이 아니다


class StatePathError(RuntimeError):
    """데이터 루트가 «무효»(LIVE_ROOT 값이 폴더가 아님) — 조용히 FT_ROOT 로 대체하지 않는다(DA H13)."""


def _root_check(root: Path | str | None = None) -> tuple[Path | None, str]:
    """(데이터 루트, 사유) — FT_ROOT › (그 안) `.fable-team/LIVE_ROOT` 1행 절대경로 폴더.
    ★LIVE_ROOT 파일이 «있는데» 값이 비었거나·상대경로거나·폴더가 아니면 «무효»★(FT_ROOT 로 조용히 대체 0 · DA H13)
    — 못 풀면 None(렌더는 기록 없음으로 발행 · 렌더를 죽이지 않는다). 파일 자체가 없으면 FT_ROOT(옛 설치본)."""
    base = Path(root) if root else (Path(os.environ["FT_ROOT"]) if os.environ.get("FT_ROOT") else None)
    if base is None:
        return None, "FT_ROOT 없음"
    try:
        lines = (base / ".fable-team" / "LIVE_ROOT").read_text(encoding="utf-8").splitlines()
    except OSError:
        return base, ""
    value = lines[0].strip() if lines else ""
    if not value:
        return None, "LIVE_ROOT 값 비었음"
    path = Path(value)
    if not path.is_absolute():
        return None, f"LIVE_ROOT 무효(상대경로 {value})"
    return (path, "") if path.is_dir() else (None, f"LIVE_ROOT 무효({path})")


def _root(root: Path | str | None = None) -> Path | None:
    return _root_check(root)[0]


def state_dir(root: Path | str | None = None, strict: bool = False) -> Path | None:
    """상태 폴더 — strict 면 무효 루트 = StatePathError(회차 수집기 몫) · 아니면 None(렌더는 «모름» 글자)."""
    base, why = _root_check(root)
    if base is None:
        if strict:
            raise StatePathError(why)
        return None
    return base / ".fable-team" / "state" / DIR


def rounds_dir(root: Path | str | None = None) -> Path | None:
    d = state_dir(root)
    return None if d is None else d / "rounds"


def round_files(root: Path | str | None = None) -> list[Path]:
    """회차 파일 전부(이름순) — 영수증(`.sent.json`·`.send-failed.json`)은 뺀다."""
    d = rounds_dir(root)
    if d is None or not d.is_dir():
        return []
    return sorted(p for p in d.glob("*.json") if not p.name.endswith(SKIP))


def _load(path: Path) -> dict | None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def read(root: Path | str | None = None) -> dict:
    """`{last_ok, last_attempt}` — 목록에서 파생(포인터 파일 0) · 깨진 파일은 건너뛴다."""
    files = [(p, _load(p)) for p in round_files(root)]
    good = [(p, d) for p, d in files if d is not None]
    ok = next(((p, d) for p, d in reversed(good) if d.get("status") == "OK"), None)
    last = good[-1] if good else None
    return {"last_ok": _tag(ok), "last_attempt": _tag(last)}


def _tag(hit: tuple[Path, dict] | None) -> dict | None:
    if hit is None:
        return None
    path, data = hit
    return {**data, "_file": path.name, "_send": _send_state(path, data)}


def _send_state(path: Path, data: dict) -> str:
    """송신 상태 = 영수증이 정본 — `.sent.json`/`.send-failed.json` 이 회차 파일의 `claimed` 를 덮는다(DA H8)."""
    stem = path.name.removesuffix(".json")
    if (path.parent / f"{stem}.sent.json").is_file():
        return "sent"
    if (path.parent / f"{stem}.send-failed.json").is_file():
        return "failed"
    state = (data.get("send") or {}).get("state")
    return "unknown" if state == "claimed" else str(state or "none")


def _max_h() -> float:
    try:
        return float(os.environ.get("FT_GOAL_READJUST_MAX_H") or MAX_H)
    except ValueError:
        return MAX_H


def _now(now: datetime | None) -> datetime:
    if now is not None:
        return now
    value = os.environ.get("FT_NOW")
    return datetime.strptime(value, "%Y-%m-%d %H:%M") if value else datetime.now()


def _hours(finished: str | None, now: datetime) -> float | None:
    try:
        return (now - datetime.strptime(str(finished), "%Y-%m-%d %H:%M:%S")).total_seconds() / 3600
    except (TypeError, ValueError):
        return None


def _hhmm(finished: str | None) -> str:
    return str(finished or "")[11:16] or "??:??"


def _reason(text: str | None) -> str:
    flat = " ".join(str(text or "").split()).replace("(", "/").replace(")", "/")
    return flat[:24]


def _recent(att: dict | None) -> str:
    if att is None:
        return "없음"
    name = str(att.get("_file", "")).removesuffix(".json")
    tag = f"{name} {att.get('status', '?')}"
    if att.get("error"):
        tag = f"{tag} {_reason(att.get('error'))}"
    send = str(att.get("_send") or "")
    return f"{tag} 송신 실패" if send == "failed" else f"{tag} 송신 모름" if send == "unknown" else tag.rstrip()


def header(state: dict, now: datetime | None = None) -> str:
    """머리 글자 — 마지막 성공(ok=…)과 최근 시도(최근=…)를 항상 둘 다 · 26시간 넘으면 «재조정 없음 N시간 · ok=… · 최근=…»."""
    state = state or {}
    ok, att = state.get("last_ok"), state.get("last_attempt")
    if ok is None and att is None:
        return "재조정 기록 없음"
    recent = _recent(att)
    if ok is None:
        return f"재조정: ok=없음 · 최근={recent}"
    mine = f"ok={ok.get('run')} {_hhmm(ok.get('finished'))}"
    hours = _hours(ok.get("finished"), _now(now))
    if hours is not None and hours > _max_h():
        return f"재조정 없음 {int(hours)}시간 · {mine} · 최근={recent}"
    return f"재조정: {mine} · 최근={recent}"


def row_cell(state: dict, n: int, goal_hash: str, canon_sha10: str | None = None) -> str:
    """«재조정» 칸 — 행 식별(번호 + 골 전문 해시)이 같을 때만 라벨 · 다르면 `모름(판 다름)`."""
    ok = (state or {}).get("last_ok")
    if ok is None:
        return "모름(기록 없음)"
    rows = ok.get("rows") or []
    row = next((r for r in rows if isinstance(r, dict) and r.get("n") == n), None)
    if row is None or not goal_hash or row.get("goal_hash") != goal_hash:
        return "모름(판 다름)"
    label = str(row.get("label") or "")
    text = label
    if label != "기준":  # 첫 회차 = 기준 하나(군더더기 0) — 정본 바뀜은 기준 행에도 붙는다(DA H4)
        if int(row.get("cards_added") or 0) >= 1:
            text += f"·카드{int(row['cards_added'])}"
        # ★«대응 유지 모름» 접두로 판별★ — 손상·빈 표식 글자에는 «r702» 가 없어도 같은 «모름» 이다(DA H7)
        if any(str(u).startswith("대응 유지 모름") for u in row.get("unknown") or []):
            text += "·대응 모름"
    if canon_sha10 and str(ok.get("inputs", {}).get("canon_sha10") or "") not in ("", canon_sha10):
        text += "·정본 바뀜"
    return text if len(text) <= CELL else text[: CELL - 1] + "…"
