"""ft_api_outage_util.py — ft_api_outage.py 의 형제 모듈: 오류 문구 분류·해제 근거 파싱 + 수신자 공용 notify 잠금 (R146).

잠금 = 수신자별 공용 notify 상태의 «읽기 → 발신 → 성공 기록» 을 한 프로세스만 하게 하는 fcntl.flock 1개(macOS 에 flock 명령 없음).
대기 상한은 7초 룰 — 넘으면 yield False(건너뛰기 아님: 호출 쪽이 ERROR 1줄 + 발신 0 + 다음 틱 재시도).
"""
import fcntl
import glob
import json
import re
import subprocess
import sys
import time
from collections.abc import Iterator
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path

CAUSES = (("rate_limit", "rate_limit|limit reached|temporarily limiting requests|are cooling down"), ("oauth_not_allowed", "OAuth authentication is currently not allowed"),
          ("subscription_disabled", "disabled Claude subscription access"))
Rec = dict[str, object]
RETRY = r"retry[\s_-]*after\s*(\d+)\s*(min\w*|m\b|s\w*)?"


TAIL = 1 << 20


def epoch(rec: Rec) -> int:
    return int(datetime.fromisoformat(str(rec["timestamp"]).replace("Z", "+00:00")).timestamp())


def records(path: str) -> list[Rec]:
    """좌석 jsonl 꼬리 1MB → 시각 있는 레코드(r497 에서 ft_api_outage.py 로부터 옮김 · 200줄 한도)."""
    with open(path, "rb") as fh:
        size = fh.seek(0, 2)
        _ = fh.seek(max(0, size - TAIL))
        raw = fh.read().split(b"\n")
    out: list[Rec] = []
    for line in raw[1:] if size > TAIL else raw:
        try:
            rec = json.loads(line)
            _ = epoch(rec)
        except (ValueError, KeyError, TypeError):
            continue
        out.append(rec)
    return out


def is_error(rec: Rec) -> bool:
    return rec.get("type") == "assistant" and rec.get("isApiErrorMessage") is True


def is_normal(rec: Rec) -> bool:
    msg = rec.get("message")
    return rec.get("type") == "assistant" and not is_error(rec) and not (isinstance(msg, dict) and msg.get("model") == "<synthetic>")  # pyright: ignore[reportUnknownMemberType]


def hhmm(epoch: int) -> str:
    return time.strftime("%H:%M", time.localtime(epoch))


def text_of(rec: Rec) -> str:
    msg = rec.get("message")
    parts = msg.get("content") if isinstance(msg, dict) else None  # pyright: ignore[reportUnknownMemberType]
    body = " ".join(str(p.get("text", "")) for p in parts if isinstance(p, dict)) if isinstance(parts, list) else ""  # pyright: ignore[reportUnknownVariableType,reportUnknownMemberType,reportUnknownArgumentType]
    return f"{body} {rec.get('error', '')}"


def cause_of(rec: Rec) -> str:
    return next((n for n, pat in CAUSES if re.search(pat, text_of(rec))), "기타")


def reset_of(rec: Rec, ts: int) -> str:
    """문구의 해제 근거 → «HH:MM (문구: resets 3am, retry after 120s)» · 근거 없으면 빈 문자열."""
    text, basis, eta = text_of(rec), [], ""
    if m := re.search(r"resets?\s*(?:at\s*)?(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)", text, re.I):
        eta = m.group(1).strip()
        basis.append(f"resets {eta}")
    if m := re.search(RETRY, text, re.I):
        mins = (m.group(2) or "s").lower().startswith("m")
        basis.append(f"retry after {m.group(1)}{'min' if mins else 's'}")
        eta = eta or hhmm(ts + int(m.group(1)) * (60 if mins else 1))
    return f"{eta} (문구: {', '.join(basis)})" if basis else ""


def eta_of(rec: Rec, ts: int) -> int:
    """`retry after N` 근거가 있으면 해제 예상 epoch · 없으면 0(r497 — «3분 안 해제면 기다림» 판정용)."""
    if m := re.search(RETRY, text_of(rec), re.I):
        return ts + int(m.group(1)) * (60 if (m.group(2) or "s").lower().startswith("m") else 1)
    return 0


def base_model(model: str) -> str:
    """`claude-fable-5-1[1m]` → `claude-fable-5-1` (창 꼬리 `[…]` 떼고 비교 · r497)."""
    return re.sub(r"\[[^\]]*\]$", "", model.strip())


def model_of(rec: Rec) -> str:
    """오류 문구 `for model <id>` → 바탕 id · 정상 레코드는 message.model · 모르면 ''(r497 모델별 복구)."""
    if m := re.search(r"for model ([A-Za-z0-9._\[\]-]+)", text_of(rec)):
        return base_model(m.group(1))
    msg = rec.get("message")
    got = msg.get("model") if isinstance(msg, dict) else None  # pyright: ignore[reportUnknownMemberType,reportUnknownVariableType]
    return base_model(got) if isinstance(got, str) and got != "<synthetic>" else ""


def fallback_table(path: Path) -> dict[str, str]:
    """r497 model-fallback.tsv 2열 `<바탕 id>\\t<다음 모델 전체 id>` — 바탕 id 는 `[1m]` 떼고 비교."""
    rows = [ln.split("\t") for ln in path.read_text(encoding="utf-8").splitlines() if ln.strip() and not ln.startswith("#")]
    return {base_model(r[0]): r[1].strip() for r in rows if len(r) >= 2}


def goal_source(ft: Path, base: str) -> tuple[list[str], str] | None:
    """r497 계보 최신 도달 파일(state/successor/<베이스>#*.json · reached_at) 의 seq → 발주 본문 첫 3줄(골 원문) + 인계서 줄 · 없으면 None."""
    reach: list[tuple[str, float, str]] = []
    for p in (ft / "state" / "successor").glob(glob.escape(base) + "#*.json"):
        try:
            j = json.loads(p.read_text(encoding="utf-8"))
            reach.append((str(j.get("reached_at", "")), p.stat().st_mtime, str(j.get("seq", ""))))
        except (ValueError, OSError, AttributeError):
            continue
    if not reach or not (seq := max(reach)[2]).isdigit():
        return None
    body = ft / "comm" / "bodies" / f"{seq}.txt"
    lines = body.read_text(encoding="utf-8").splitlines() if body.is_file() else []
    if len([ln for ln in lines[:3] if ln.strip()]) < 3:
        return None
    return lines[:3], next((ln.strip() for ln in lines[3:] if "인계서" in ln), "")


def read_table(path: Path) -> dict[str, object] | None:
    """r497 명부 1개 — 못 읽으면 WARN 1줄 + None(조용한 생략 0)."""
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, OSError) as exc:
        print(f"WARN model_swap: 명부 못 읽음 {path.name} ({exc})", file=sys.stderr)
        return None


def find_jsonls(seats: list[str], tmux: str, projects: Path, days: int = 2) -> dict[str, str]:
    """r497 좌석들 → 최신 jsonl 을 «한 번에». ft-seat-status.sh jsonl 은 좌석마다 폴더 jsonl 전부(5989개)의 머리 1MB 를 읽어
    부하 30 에서 1회 10초(실측) — 여기선 폴더 = tmux pane cwd 인코딩(같은 규칙) · 후보 = 최근 days 일 수정 파일만 · 파일 머리 1번 읽어 전 좌석 대조."""
    r = subprocess.run([tmux, "list-panes", "-a", "-F", "#{session_name}\t#{pane_current_path}"], capture_output=True, text=True, timeout=7)
    groups: dict[Path, list[str]] = {}
    for s, cwd in (ln.split("\t", 1) for ln in (r.stdout if r.returncode == 0 else "").splitlines() if "\t" in ln):
        if s in seats and not any(s in g for g in groups.values()):
            groups.setdefault(projects / re.sub(r"[^A-Za-z0-9]", "-", cwd), []).append(s)
    out: dict[str, str] = {}
    for d, group in groups.items():
        try:
            files = sorted(((p.stat().st_mtime, p) for p in d.glob("*.jsonl")), reverse=True)
        except OSError:
            continue
        for _, p in (f for f in files if time.time() - f[0] < days * 86400):
            if not (left := [s for s in group if s not in out]):
                break
            try:
                with p.open("rb") as fh:
                    head = fh.read(1 << 20)
            except OSError:  # 읽는 사이 지워진 파일
                continue
            out.update({s: str(p) for s in left if f'"agentName":"{s}"'.encode() in head or f'"customTitle":"{s}"'.encode() in head})
    return out


def jsonl_cwd(path: str) -> str:
    """r497 좌석 jsonl 의 마지막 `cwd`(후계 워크트리) · 없으면 ''."""
    return next((str(r["cwd"]) for r in reversed(records(path)) if isinstance(r.get("cwd"), str)), "") if path else ""


def next_name(names: set[str], base: str) -> str:
    """r497 후계 이름 = 베이스#(명부 키·tmux 세션 중 최대 번호 + 1)."""
    nums = [int(m.group(1)) for n in names if (m := re.fullmatch(re.escape(base) + r"#(\d+)", n))]
    return f"{base}#{max(nums, default=0) + 1}"


@contextmanager
def locked(path: Path, timeout: float = 7.0) -> Iterator[bool]:
    """path 에 배타 잠금 — 얻으면 True · timeout 초 안에 못 얻으면 False(잠금 없음)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as fh:
        end, got = time.monotonic() + timeout, False
        while not got:
            try:
                fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)  # GUARD:flock
                got = True
            except BlockingIOError:
                if time.monotonic() >= end:
                    break
                time.sleep(0.05)
        try:
            yield got
        finally:
            if got:
                fcntl.flock(fh, fcntl.LOCK_UN)
