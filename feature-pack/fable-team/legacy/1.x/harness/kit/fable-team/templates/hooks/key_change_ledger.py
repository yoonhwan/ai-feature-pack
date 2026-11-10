"""key_change_ledger — key_change_judge 의 장부·사용처 표 읽기와 판정(R277 r2).

★작업 트리를 읽지 않는다★ — `git -C <루트> show ${BYZ_KEYS_REF:-origin/main}:<경로>` 로 «커밋된» 장부·표만 읽는다
(루트 작업 트리는 멈춰 있거나 편집 중일 수 있다 · 작업 트리만 바꾼 표로 훅을 속일 수 없다). 못 읽으면 Unreadable(호출자가 막는다).
"""
from __future__ import annotations

import datetime
import hashlib
import os
import re
import subprocess

ROOT = os.environ.get("BYZ_KEYS_ROOT", "/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents")
LEDGER_REL, USAGE_REL = "design/ops/keys/LEDGER-keys.md", "design/ops/keys/usage"
BEGIN_K, END_K, BEGIN_U, END_U, CONFIRM = "<!-- keys:begin -->", "<!-- keys:end -->", "<!-- usage:begin -->", "<!-- usage:end -->", "- 전환 확인:"
SM_NAME = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_-]{5,}")
CELL = re.compile(r"용도=[a-z0-9-]+ · API=[^\s·]+ · 표=usage/([A-Z0-9_]+)\.md@(\d{4}-\d{2}-\d{2})#([0-9a-f]{12})")
MADE = re.compile(r"- 생성: (\d{4}-\d{2}-\d{2}) \d{2}:\d{2}( |$)")
MAX_AGE_DAYS, CONFIRM_HOURS = 7, 24


class Unreadable(Exception):
    pass


def now() -> datetime.datetime:
    raw = os.environ.get("KEYGATE_NOW")
    return datetime.datetime.strptime(raw, "%Y-%m-%d %H:%M") if raw else datetime.datetime.now()


def git(*args: str) -> subprocess.CompletedProcess:
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    try:
        return subprocess.run(["git", "-C", ROOT, *args], capture_output=True, text=True, timeout=5, env=env)
    except (OSError, subprocess.SubprocessError, UnicodeDecodeError):
        raise Unreadable("git") from None


def ref() -> str:
    return os.environ.get("BYZ_KEYS_REF", "origin/main")


def read(rel: str) -> str | None:
    """커밋된 파일 본문 · 그 ref 에 파일이 없으면 None · ref 자체가 없거나 git 이 안 되면 Unreadable."""
    p = git("show", f"{ref()}:{rel}")
    if p.returncode == 0:
        return p.stdout
    if git("cat-file", "-e", f"{ref()}^{{commit}}").returncode != 0:
        raise Unreadable("ref")
    return None


def ledger_rows() -> list[list[str]]:
    text = read(LEDGER_REL)
    if text is None:
        raise Unreadable("장부")
    rows, inside = [], False
    for ln in text.split("\n"):
        inside = True if ln.strip() == BEGIN_K else False if ln.strip() == END_K else inside
        if inside and ln.startswith("|"):
            cells = [c.strip() for c in ln.strip().strip("|").split("|")]
            if len(cells) == 12 and cells[0] not in ("ENV(표준)", "---"):
                rows.append(cells)
    return rows


def region(text: str) -> list[str] | None:
    lines = text.split("\n")
    if BEGIN_U not in lines or END_U not in lines:
        return None
    return lines[lines.index(BEGIN_U) + 1:lines.index(END_U)]


def table_sha(text: str) -> str | None:
    inner = region(text)
    if inner is None:
        return None
    return hashlib.sha256(("\n".join(ln for ln in inner if not ln.startswith(CONFIRM)) + "\n").encode("utf-8")).hexdigest()[:12]


def verify(row: list[str], delete: bool) -> str:
    """'' = 통과 · 아니면 사유 1줄(ENV·경로만 — 값 0)."""
    env, m = row[0].split(",")[0].strip(), CELL.fullmatch(row[9])
    if not m:
        return f"{env} 사용처 칸이 미조사"
    text = read(f"{USAGE_REL}/{m.group(1)}.md")
    if text is None:
        return f"{env} 사용처 표 파일 없음({m.group(1)}.md · {ref()} 기준)"
    if table_sha(text) != m.group(3):
        return f"{env} 사용처 표 sha 가 장부 칸과 어긋남(표 본문이 바뀜 · keys-usage.sh 로 다시)"
    made = next((MADE.match(ln) for ln in region(text) or [] if MADE.match(ln)), None)
    if not made or made.group(1) != m.group(2):
        return f"{env} 사용처 표 생성일이 장부 칸 날짜와 다르거나 읽을 수 없음"
    age = (now().date() - datetime.date.fromisoformat(made.group(1))).days
    if not 0 <= age <= MAX_AGE_DAYS:
        return f"{env} 사용처 표가 {age}일 전 것(7일 이내만)"
    if not delete:
        return ""
    line = next((ln for ln in text.split("\n") if ln.startswith(CONFIRM)), "")
    ts = re.match(r"- 전환 확인: (\d{4}-\d{2}-\d{2} \d{2}:\d{2}) · ", line)
    delta = (now() - datetime.datetime.strptime(ts.group(1), "%Y-%m-%d %H:%M")) if ts else None
    if delta is None or not datetime.timedelta(0) <= delta <= datetime.timedelta(hours=CONFIRM_HOURS):
        return f"{env} 옛 키 삭제·비활성 전 «전환 확인» 줄(24시간 이내)이 없음"
    return ""


def by_env(rows, name):
    return [r for r in rows if name in [e.strip() for e in r[0].split(",")] or r[1] == name]


def by_secret(rows, name):
    return [r for r in rows if name in SM_NAME.findall(r[5]) + SM_NAME.findall(r[6])]


def by_identity(rows, idents):
    """api-key 표시 이름·키 id → 그 이름을 적어 둔 사용처 표의 장부 행."""
    listing = git("ls-tree", "-r", "--name-only", ref(), USAGE_REL)
    if listing.returncode != 0:
        raise Unreadable("표 목록")
    for path in sorted(listing.stdout.split()):
        text = read(path) or ""
        got = {ln.split(":", 1)[1].strip() for ln in text.split("\n") if ln.startswith(("- 표시 이름:", "- 키 id:"))}
        if got & set(idents):
            return by_env(rows, os.path.basename(path)[:-3])
    return []
