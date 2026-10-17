"""ft_secret_shapes — 출력 속 비밀 «모양»을 *** 로 가린다 (R135b · 판정 1585 · 제안서 §3-②).
mask(text) → (가린 텍스트, [(종류, 줄 번호)]) — 값은 어디에도 다시 쓰지 않는다(종류는 고정 글자 · 줄 번호는 정수).
--hook: PostToolUse JSON(stdin) 의 tool_response 속 문자열만 가려 hookSpecificOutput.updatedToolOutput(원래 형태 그대로)을 낸다 · 바뀐 게 없으면 출력 0.
자리표시자(***·<…>·$VAR·${VAR}·xxx)는 비밀이 아니다. 줄 단위 선형 정규식 — 역추적 폭주 0."""
from __future__ import annotations

import json
import os
import re
import sys
import time

from ft_secret_targets import NAME

PH = r"(?![*<$])(?!x{3,}\b)"  # 값 첫머리가 자리표시자면 맞지 않는다
TOKEN_PREFIX = r"(?:ghp_|gho_|github_pat_|sk-|xox[bp]-|AIza|ya29\.)"
NOT_IN_CHUNK = r"(?<![A-Za-z0-9_-])"  # 매칭은 «덩어리 첫 글자»에서만 시작 — 덩어리 안 모든 위치에서 다시 시작하면 제곱 시간
RULES = (  # (종류, 정규식 — 가릴 값은 그룹 val, 앞은 그룹 pre)
    ("url-cred", re.compile(r"(?P<pre>(?<![A-Za-z0-9+.-])[A-Za-z][A-Za-z0-9+.-]*://[^\s:/@*<>$]+:)" + PH + r"(?P<val>[^\s@/]{3,})(?=@)")),
    ("pgpassword", re.compile(r"(?P<pre>\bPGPASSWORD=)" + PH + r"(?P<val>[^\s'\"]+)")),
    ("token-prefix", re.compile(r"(?P<pre>)\b" + PH + r"(?P<val>" + TOKEN_PREFIX + r"[A-Za-z0-9_.\-]{16,})")),
    ("slack-webhook", re.compile(r"(?P<pre>(?i:https://hooks\.slack\.com/services/))" + PH + r"(?P<val>[A-Za-z0-9_%-]+/[A-Za-z0-9_%-]+/[A-Za-z0-9_%-]+)")),  # 앞이 고정 글자 — 선형 · R307 범위 2
    ("jwt", re.compile(r"(?P<pre>)" + NOT_IN_CHUNK + r"(?P<val>eyJ[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,})")),
)
# named-secret: «이름+구분자»만 소비하고 값은 앞보기로 본다 — 앞 이름이 비밀 이름이 아니면 아무것도 안 먹고 다음 후보로 넘어가 뒤의 진짜 이름을 놓치지 않는다(DA⑥ r3 H4)
NAMED = re.compile(r"(?<![A-Za-z_])(?P<name>[A-Za-z_]+)\s*[=:]\s*[\"']?(?=" + PH + r"(?![/.~])(?P<val>[A-Za-z0-9_\-./+]{20,}))")  # 경로 값(…_FILE=/run/…)은 비밀이 아니다
_PLACEHOLDER_ONLY = re.compile(r"x{3,}", re.I)
_PREFIX = re.compile(TOKEN_PREFIX)


def _is_placeholder(val: str) -> bool:
    return bool(_PLACEHOLDER_ONLY.fullmatch(_PREFIX.sub("", val, count=1)))


def _named(line: str) -> tuple[str, bool]:
    out: list[str] = []
    cur = 0
    for m in NAMED.finditer(line):
        if m.start() < cur or not NAME.search(m.group("name")) or _is_placeholder(m.group("val")):
            continue
        out.append(line[cur:m.end()] + "***")
        cur = m.end() + len(m.group("val"))
    return "".join(out) + line[cur:], bool(out)


def _line(line: str, no: int, hits: list[tuple[str, int]]) -> str:
    for kind, rx in RULES:
        found = False

        def sub(m: re.Match[str]) -> str:
            nonlocal found
            if _is_placeholder(m.group("val")):
                return m.group(0)
            found = True
            return m.group("pre") + "***"

        line = rx.sub(sub, line)
        if found:
            hits.append((kind, no))
    line, found = _named(line)
    if found:
        hits.append(("named-secret", no))
    return line


def mask(text: str) -> tuple[str, list[tuple[str, int]]]:
    hits: list[tuple[str, int]] = []
    if not text:
        return text, hits
    out = [_line(ln, n, hits) for n, ln in enumerate(text.split("\n"), 1)]
    return "\n".join(out), hits


def _walk(v: object, hits: list[tuple[str, int]]) -> object:  # 문자열 칸만 가린다 — 키·숫자·불리언·구조는 그대로(형태가 틀리면 Claude Code 가 교체를 무시한다)
    if isinstance(v, str):
        out, h = mask(v)
        hits += h
        return out
    if isinstance(v, dict):
        return {k: _walk(x, hits) for k, x in v.items()}
    if isinstance(v, list):
        return [_walk(x, hits) for x in v]
    return v


def hook(raw: str) -> str:  # PostToolUse stdin JSON → 출력할 JSON 글자("" = 바뀐 것 없음)
    if os.environ.get("FT_SECRET_GUARD_TEST_OFF"):
        return ""
    data = json.loads(raw)
    hits: list[tuple[str, int]] = []
    new = _walk(data.get("tool_response"), hits)
    if not hits:
        return ""
    try:  # 원장 실패가 가림을 막지 않는다 — 값 0(시각·세션 id·도구·종류만)
        log = os.environ.get("FT_SECRET_LEAK_LOG") or os.path.expanduser("~/.claude/state/secret-leak.log")
        os.makedirs(os.path.dirname(log), exist_ok=True)
        kinds = ",".join(sorted({k for k, _ in hits}))
        with open(log, "a") as f:
            f.write(f"{time.strftime('%F %T')} session={data.get('session_id', '?')} tool={data.get('tool_name', '?')} kinds={kinds} n={len(hits)}\n")
    except OSError:
        pass
    return json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "updatedToolOutput": new}}, ensure_ascii=False)


if __name__ == "__main__" and sys.argv[1:] == ["--hook"]:
    out = hook(sys.stdin.read())
    if out:
        print(out)
