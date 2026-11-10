"""ft_secret_sinks — ft_secret_judge 의 «복사·입력 재지정이 비밀을 화면으로 보내는 모양» (R219 교정 2): sinks(명령 단어들, 표준입력 비밀 경로들) → 고정 이유 | None.
문자열만 본다(실행 0). 이유는 고정 글자뿐 — 명령 속 값·이름을 다시 쓰지 않는다."""
from __future__ import annotations

import re

from ft_secret_lex import W
from ft_secret_targets import AWKS, DUMPERS, FILE_LEAK, READERS, secret_path

SAFE_STDIN = {"wc", "read", "test", "[", "[[", ":", "md5", "md5sum", "shasum", "sha1sum", "sha256sum"}  # 내용을 안 내는 명령
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
PRECISE = READERS | DUMPERS | AWKS | {"cut", "sed"}  # target() 이 옵션까지 보고 이미 판정한다(grep -c · cut -d= -f1 · sed -n 등)
SCREEN = re.compile(r"/dev/(?:stdout|stderr|tty)|/dev/fd/[12]|/proc/self/fd/[12]|-")


def sinks(a: list[W], stdin: list[str]) -> str | None:  # stdin = `< 비밀경로` 로 들어온 경로들
    if not a:
        return None
    h, r = a[0], a[1:]
    if stdin and h not in SAFE_STDIN | PRECISE:  # 안전 목록 밖은 전부 거절(tee < .env)
        return h + FILE_LEAK
    if h in ("cp", "install") and r and SCREEN.fullmatch(r[-1]) and any(secret_path(x) for x in r[:-1]):
        return h + FILE_LEAK
    if h == "dd":
        src = [x[3:] for x in r if x.startswith("if=")]
        out = [x[3:] for x in r if x.startswith("of=")]
        if any(secret_path(x) for x in src) and (not out or SCREEN.fullmatch(out[0])):
            return "dd" + FILE_LEAK
    return None


def nested(a: list[W]) -> str:  # bash -c '본문' · eval 본문 — 작은따옴표 안 $ 표식(\x01)을 되돌려 judge 가 다시 읽게 한다
    if a[:1] == ["eval"]:
        return " ".join(a[1:]).replace("\x01", "$")
    if a and a[0] in SHELLS:
        for i, x in enumerate(a[1:-1], 1):
            if re.fullmatch(r"-[a-zA-Z]*c", x):
                return a[i + 1].replace("\x01", "$")
    return ""
