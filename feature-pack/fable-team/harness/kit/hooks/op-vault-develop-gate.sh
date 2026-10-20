#!/bin/bash
# op-vault-develop-gate — PreToolUse:Bash (r451 · 오빠 10-19 «op 볼트는 무조건 develop» · 전역 하드 룰 15)
# 왜: 기본 OP_SERVICE_ACCOUNT_TOKEN 은 kskill(슬랙 자동화 전용) 볼트만 보인다 — 좌석이 그냥 `op item create` 를 치면
#     «보이는 유일한 볼트» kskill 에 들어간다(컨시어지 시연 계정 8개 사건). BYZ 계정·키는 develop 볼트 + develop 전용 토큰.
# 동작(BYZ 리포 안만): 명령을 구분자(; && || | 개행 $( `)로 나눠 «실행되는 첫 낱말» 이 op 이고
#   하위 명령이 `item create|edit|get|list|delete` · `document …` 이면 ①`--vault develop`/`--vault=develop`
#   · `read` 이면 op:// 참조의 볼트가 develop ②명령 글자에 `OP_SERVICE_ACCOUNT_TOKEN="$OP_SERVICE_ACCOUNT_TOKEN_DEVELOP"` 대입
#   — 둘 중 하나라도 없으면 exit 2 + stderr 안내 1줄. `op vault list`·`whoami`·`signin`·`--version`·`account`·`item move` 등은 통과.
# 범위: FT_ROOT(있으면) 또는 cwd 가 BYZ 리포일 때만 = origin URL 이 …/byz-agents(.git) 또는 최상위에 `.claude/skills/byz-keys/`
#   (공용 루트 체크아웃은 옛 main 일 수 있어 파일 표식만으론 못 가린다 · 팩 리포도 .fable-team 이 있어 그것도 못 쓴다 · BYZ 밖 = hermes 슬랙 자동화 = 통과).
# ★못 읽음★: 입력 JSON 을 못 읽음 = 통과 + stderr 경고(fail-open · 다른 홈 훅과 같은 꼴 · 거절만 하는 훅). 외부 호출 0(op 위반 후보일 때만 로컬 git 2회).
# ★토큰 값은 읽지도 찍지도 않는다★(명령 «글자» 만 본다 · 환경변수 OP_* 접근 0).
# ★설치(~/.claude/hooks/ 복사 · settings.json PreToolUse Bash 등록)는 master — 이 파일 범위 밖★
# ★r546★ 명령 조각내기는 공용 모듈 merge_cmd.segments 하나 — 같은 폴더의 merge_cmd.py 가 없으면 rc2(막음). 사본 0.
set +e
INPUT=$(cat 2>/dev/null)
[ -n "$INPUT" ] || exit 0
export INPUT
command -v python3 >/dev/null 2>&1 || { echo "WARN op-vault-develop-gate: python3 없음 — 통과" >&2; exit 0; }
OVG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; export OVG_DIR
[ -f "$OVG_DIR/merge_cmd.py" ] || { echo "REJECT op-vault-develop-gate: merge_cmd 없음 — 같은 폴더 공용 모듈(r546)이 필요하다: $OVG_DIR/merge_cmd.py" >&2; exit 2; }
python3 - <<'PYEOF'
import json, os, re, shlex, subprocess, sys

sys.path.insert(0, os.environ["OVG_DIR"])
from merge_cmd import segments  # r546: 사본 삭제 전 op-vault 안에 있던 그 함수(글자 그대로 옮겼다)

MSG = ('REJECT op 볼트 = develop 만 — kskill 은 슬랙 자동화 전용(오빠 10-19) · '
       '꼴: OP_SERVICE_ACCOUNT_TOKEN="$OP_SERVICE_ACCOUNT_TOKEN_DEVELOP" op … --vault develop')
TOKEN_RE = re.compile(r"""OP_SERVICE_ACCOUNT_TOKEN=["']?\$\{?OP_SERVICE_ACCOUNT_TOKEN_DEVELOP\b""")
SUBS = {"item", "read", "document", "vault", "whoami", "signin", "signout", "account", "user", "group",
        "run", "inject", "connect", "events-api", "service-account", "plugin", "completion", "update"}
ITEM_GATED = {"create", "edit", "get", "list", "delete"}
WRAP = {"env", "nohup", "time", "exec", "command", "sudo", "nice", "timeout", "stdbuf"}
SHELLS = {"bash", "sh", "zsh", "dash"}


def warn(msg):
    print(f"WARN op-vault-develop-gate: {msg} — 통과", file=sys.stderr)
    sys.exit(0)


def exec_tokens(tokens):
    """실행되는 첫 낱말부터의 토큰. 환경 대입·래퍼를 건너뛴다. 셸 -c 는 ("-c", 문자열)."""
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t):
            i += 1; continue
        base = t.rsplit("/", 1)[-1]
        if base in WRAP:
            i += 1
            while i < len(tokens) and (tokens[i].startswith("-") or re.match(r"^\d+[smhd]?$", tokens[i])):
                i += 1
            continue
        if base in SHELLS:
            j = i + 1
            while j < len(tokens) and tokens[j].startswith("-"):
                if re.match(r"^-[A-Za-z]*c[A-Za-z]*$", tokens[j]) and j + 1 < len(tokens):
                    return ("-c", tokens[j + 1])
                j += 1
            return tokens[i:]
        return tokens[i:]
    return []


def vault_of(args):
    for k, a in enumerate(args):
        if a == "--vault" and k + 1 < len(args):
            return args[k + 1]
        if a.startswith("--vault="):
            return a.split("=", 1)[1]
    return None


def op_violation(toks):
    """op 볼트 명령이면 빠진 것 목록(볼트 꼴 검사만 · 토큰은 호출부), 아니면 None."""
    if not toks or toks[0].rsplit("/", 1)[-1] != "op":
        return None
    args = toks[1:]
    sub_i = next((k for k, a in enumerate(args) if a in SUBS), None)
    if sub_i is None:
        return None  # op --version · op --help 등
    sub, rest = args[sub_i], args[sub_i + 1:]
    if sub == "item":
        verb = next((a for a in rest if not a.startswith("-")), "")
        if verb not in ITEM_GATED:
            return None
    elif sub == "read":
        refs = [a for a in rest if a.startswith("op://")]
        ok = bool(refs) and all(r[len("op://"):].split("/", 1)[0] == "develop" for r in refs)
        return [] if ok else ["op://develop/…"]
    elif sub != "document":
        return None
    return [] if vault_of(rest) == "develop" else ["--vault develop"]


def in_byz(cwd):
    """FT_ROOT(있으면) 또는 cwd 가 BYZ 리포인가 — origin URL …/byz-agents 또는 최상위에 .claude/skills/byz-keys/."""
    d = os.environ.get("FT_ROOT") or cwd or os.getcwd()
    git = lambda *a: subprocess.run(["git", "-C", d, *a], capture_output=True, text=True, timeout=5).stdout.strip()
    if re.search(r"[/:]byz-agents(?:\.git)?/?$", git("config", "--get", "remote.origin.url"), re.I):
        return True
    top = git("rev-parse", "--show-toplevel")
    return bool(top) and os.path.isdir(os.path.join(top, ".claude", "skills", "byz-keys"))


def scan(cmd, depth=0):
    """명령 안 op 볼트 명령의 빠진 것들(첫 위반) · 없으면 None."""
    for seg in segments(cmd):
        try:
            toks = shlex.split(seg, comments=False, posix=True)
        except ValueError:
            toks = seg.split()
        et = exec_tokens(toks)
        if isinstance(et, tuple):
            if depth < 3:
                r = scan(et[1], depth + 1)
                if r is not None:
                    return r
            continue
        miss = op_violation(et)
        if miss is not None:
            if not TOKEN_RE.search(cmd):
                miss = miss + ["develop 토큰(OP_SERVICE_ACCOUNT_TOKEN_DEVELOP)"]
            if miss:
                return miss
    return None


def main():
    try:
        d = json.loads(os.environ["INPUT"])
    except ValueError:
        warn("입력 JSON 을 읽지 못함")
    if not isinstance(d, dict):
        warn("입력 JSON 이 객체(dict)가 아님")
    if d.get("tool_name", "Bash") != "Bash":
        sys.exit(0)
    cmd = (d.get("tool_input") or {}).get("command") or ""
    if not cmd or not re.search(r"(?:^|[^A-Za-z0-9_.-])op(?:\s|$)", cmd):
        sys.exit(0)
    miss = scan(cmd)
    if not miss:
        sys.exit(0)
    try:
        if not in_byz(d.get("cwd")):
            sys.exit(0)
    except (OSError, subprocess.SubprocessError):
        warn("BYZ 리포 판별 실패")
    print(f"{MSG} (빠진 것: {' · '.join(miss)})", file=sys.stderr)
    sys.exit(2)


try:
    main()
except Exception as e:  # SystemExit 는 Exception 이 아니라 그대로 지나간다 — 파이썬 쪽 예외 전체 = 통과 + 경고(fail-open)
    warn(f"예외 {type(e).__name__}: {e}")
PYEOF
