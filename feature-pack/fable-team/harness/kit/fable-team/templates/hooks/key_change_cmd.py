"""key_change_cmd — key_change_judge 의 명령 해석(R277): 따옴표·heredoc·주석 안 글자는 명령이 아니다(ft_secret_lex 토큰 분석 재사용) ·
bash -c·eval·치환 안은 재귀(상한 3) · gcloud 인자 → 키 변경·삭제 부류와 식별 이름. 문자열만 본다(실행 0)."""
from __future__ import annotations

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ft_secret_lex import scan, strip_heredocs  # noqa: E402  (동봉 모듈 — 없으면 ImportError → 호출자 rc2)

ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*\+?=")
SKIP = {"command", "builtin", "exec", "nohup", "time", "if", "then", "elif", "else", "while", "until", "do", "!", "{", "}"}
# 값을 따로 받는 래퍼 옵션 — 값이 실행 파일로 오인되지 않게 함께 벗긴다(env -u X gcloud … · DA H2). -S/--split-string 값은 명령 글이라 재판정한다.
WRAP_VALUE = {"env": {"-u", "--unset", "-C", "--chdir", "-S", "--split-string", "-P"}, "sudo": {"-u", "-g", "-h", "-p", "-C", "-r", "-t", "-U", "-D"},
              "xargs": {"-I", "-n", "-P", "-L", "-s", "-d", "-E", "-a"},
              "timeout": {"-s", "--signal", "-k", "--kill-after"}, "gtimeout": {"-s", "--signal", "-k", "--kill-after"},
              "nice": {"-n", "--adjustment"}, "stdbuf": {"-i", "-o", "-e", "--input", "--output", "--error"},
              "caffeinate": {"-t", "-w"}, "ionice": {"-c", "--class", "-n", "--classdata", "-p", "-P", "-u"}}
WRAP_POS = {"timeout": 1, "gtimeout": 1}  # 옵션 뒤 첫 위치 인자(시간)도 명령이 아니다 — `timeout 7 gcloud …` (7초 룰로 흔한 꼴)
VALUE_FLAGS = {"--project", "--account", "--impersonate-service-account", "--format", "--configuration", "--billing-project",
               "--region", "--location", "--filter", "--limit", "--data-file", "--labels", "--display-name", "--ttl", "--replication-policy", "--secret"}
ENV_CHANGE = ("--update-env-vars", "--set-env-vars", "--update-secrets", "--set-secrets")
ENV_REMOVE = ("--remove-env-vars", "--remove-secrets")


def positional(words: list[str]) -> tuple[list[str], list[str]]:
    """(위치 인자, 옵션 목록 — 값을 따로 받는 옵션은 `--f=값` 으로 합친다)."""
    pos, flags, i = [], [], 0
    while i < len(words):
        w = words[i]
        if w.startswith("-"):
            flags.append(w)
            if "=" not in w and w in VALUE_FLAGS | set(ENV_CHANGE + ENV_REMOVE) and i + 1 < len(words):
                flags[-1], i = w + "=" + words[i + 1], i + 1
        else:
            pos.append(w)
        i += 1
    return [p for p in pos if p not in ("alpha", "beta")], flags


def flag_values(flags: list[str], names) -> list[str]:
    return [f.split("=", 1)[1] for f in flags if "=" in f and f.split("=", 1)[0] in names]


def env_names(values: list[str]) -> list[str]:
    """`--update-env-vars A=1,B=2` · `^@^A=x,y@B=2` · `A=secret:latest` → 왼쪽 이름만(오른쪽 값은 버린다)."""
    out = []
    for v in values:
        d = re.match(r"\^(.+?)\^(.*)", v)
        out += [p.split("=", 1)[0].split(":", 1)[0] for p in (d.group(2).split(d.group(1)) if d else v.split(","))]
    return [n for n in out if n]


def gcloud_hits(args: list[str]) -> list[tuple[str, str, list[str]]]:
    """gcloud 인자 → [(부류 변경|삭제, 종류 secret|apikey|run, 식별 이름들)] — 키와 무관한 명령은 []."""
    pos, flags = positional(args[1:])
    if pos[:3] == ["secrets", "versions", "add"]:
        return [("변경", "secret", pos[3:4])]
    if pos[:2] == ["secrets", "versions"] and pos[2:3] in (["disable"], ["destroy"]):
        ref = pos[3] if len(pos) > 3 else ""  # VERSION 위치 인자 + --secret 이 정식 · `projects/…/secrets/NAME/versions/N` 전체 이름도 받는다
        named = re.search(r"/secrets/([^/]+)", ref)
        return [("삭제", "secret", flag_values(flags, ("--secret",)) or [named.group(1) if named else ref])]
    if pos[:2] == ["secrets", "delete"]:
        return [("삭제", "secret", pos[2:3])]
    if pos[:3] in (["services", "api-keys", "create"], ["services", "api-keys", "update"]):
        return [("변경", "apikey", flag_values(flags, ("--display-name",)) + pos[3:4])]
    if pos[:3] == ["services", "api-keys", "delete"]:
        return [("삭제", "apikey", pos[3:4])]
    if pos[:3] == ["run", "services", "update"]:
        change, remove = env_names(flag_values(flags, ENV_CHANGE)), env_names(flag_values(flags, ENV_REMOVE))
        return ([("변경", "run", change)] if change else []) + (
            [("삭제", "run", remove or ["*"])] if remove or "--clear-secrets" in flags else [])
    return []


def unwrap(args: list[str]) -> tuple[list[str], list[str]]:
    """앞의 대입(NAME=VAL)·제어어·래퍼(env·sudo·xargs·time …)와 그 옵션을 벗긴다 → (남은 인자, 래퍼가 들고 온 명령 글들)."""
    args, texts = list(args), []
    while args:
        a = args[0]
        if ASSIGN.match(a) or a in SKIP:
            args.pop(0)
        elif a in WRAP_VALUE:
            args.pop(0)
            while args and args[0].startswith("-") and not ASSIGN.match(args[0]):
                o = args.pop(0)
                if o in WRAP_VALUE[a] and args:
                    val = args.pop(0)
                    texts += [val] if o in ("-S", "--split-string") else []
            for _ in range(WRAP_POS.get(a, 0) if args else 0):
                args.pop(0)
        else:
            break
    return args, texts


def commands(text: str, depth: int = 0):
    """단순 명령마다 단어 목록 — 따옴표·heredoc·주석 안 글자는 명령이 아니다 · bash -c·eval·치환 안은 재귀(상한 3)."""
    for _, words, _sep in scan(strip_heredocs(text)):
        args, texts = unwrap(words)
        for t in texts if depth < 3 else []:
            yield from commands(t, depth + 1)
        if depth < 3:
            for w in words:
                for sub in w.subs:
                    yield from commands(sub, depth + 1)
        if not args:
            continue
        exe = os.path.basename(args[0])
        script = next((args[i + 2] for i, a in enumerate(args[1:]) if re.fullmatch(r"-[a-z]*c", a) and i + 2 < len(args)), None)
        if exe in ("bash", "sh", "zsh", "dash") and script is not None and depth < 3:
            yield from commands(script, depth + 1)
        elif exe == "eval" and depth < 3:
            yield from commands(" ".join(args[1:]), depth + 1)
        else:
            yield args


def scan_hits(cmd: str) -> bool:
    """키 변경 모양의 gcloud 명령이 «실행되는 자리»에 있는가 — 장부 없이 토큰 분석만(판정기가 죽었을 때의 후퇴 판정)."""
    return any(os.path.basename(a[0]) == "gcloud" and gcloud_hits(a) for a in commands(cmd))


if __name__ == "__main__":  # --scan: stdin 의 PreToolUse JSON → hit|none (rc0) · 내부 오류 rc2(호출자가 마지막 후퇴로 글자 검사)
    import json
    try:
        print("hit" if scan_hits(json.load(sys.stdin)["tool_input"]["command"]) else "none")
    except Exception:
        sys.exit(2)
