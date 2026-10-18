#!/bin/bash
# tracked-bin-call-gate — PreToolUse:Bash (R201 범위 추가 · 카드 r201-root-bin-stale-copy-shim)
# 왜: 뒤처진 워크트리의 `harness/bin/<도구>`(git 추적 사본 · r385 전엔 BYZ 리포 안 옛 위치)를 직접 부르면 «그 워크트리 시점의 옛 코드» 가 돈다(옛 자원 한도 30 · 드리프트 검사 건너뜀).
#     loom#27 spawn 이 loom-main 의 52커밋 뒤진 사본으로 REJECT(planner#49 #92812). 사본은 추적 파일이라 연결 파일로 바꿀 수 없다 → 호출 순간에 막고 라이브 경로를 안내한다.
# 동작: 명령을 구분자(; && || | 개행 $( `)로 나눠 «실행되는 첫 낱말» 이 `*/harness/bin/<입구 도구>` 또는 `*/harness/kit/fable-team/bin/<입구 도구>`(+ BYZ freeze 옛 위치 두 곳) 이면 deny.
#       입구 도구 = spawn · close · role-spawn · successor-open · resource-gate · resource-reclaim.
#       읽기(cat·grep·sed -n·git show·bash -n)와 `$FT_BIN/…`·`.fable-team/bin/…` 호출·입구 도구 밖 이름·`FT_ALLOW_TRACKED_BIN=1`(시험 하네스) 은 통과.
# ★못 읽음★: 입력 JSON 을 못 읽거나 파싱 실패 = 통과 + stderr 경고(fail-open · 다른 홈 훅과 같은 꼴 · 파괴 아님). 외부 호출 0(git rev-parse 1회만).
# 환경: FT_ROOT(루트 고정) · FT_BIN(안내용 라이브 위치 보조). ★설치(~/.claude/hooks/ 복사 · settings.json PreToolUse Bash 등록)는 master — 이 파일 범위 밖★
set +e
INPUT=$(cat 2>/dev/null)
[ -n "$INPUT" ] || exit 0
export INPUT
command -v python3 >/dev/null 2>&1 || { echo "WARN tracked-bin-call-gate: python3 없음 — 통과" >&2; exit 0; }
ENTRY_TOOLS="ft-nano-spawn ft-nano-close ft-role-spawn ft-successor-open ft-resource-gate ft-resource-reclaim"
export ENTRY_TOOLS
python3 - <<'PYEOF'
import json, os, re, subprocess, sys

ENTRY = os.environ.get("ENTRY_TOOLS", "").split()


def warn(msg):
    print(f"WARN tracked-bin-call-gate: {msg} — 통과", file=sys.stderr)
    sys.exit(0)


def segments(cmd):
    """따옴표 밖의 구분자로 명령을 조각낸다(따옴표 안은 한 덩어리)."""
    out, cur, q, i = [], [], None, 0
    while i < len(cmd):
        c = cmd[i]
        if q:
            cur.append(c)
            if c == q and (q == "'" or cmd[i - 1] != "\\"):
                q = None
        elif c in "'\"":
            q = c; cur.append(c)
        elif c == "$" and cmd[i:i + 2] == "$(":
            out.append("".join(cur)); cur = []; i += 1
        elif c in ";&|\n()`":
            out.append("".join(cur)); cur = []
        else:
            cur.append(c)
        i += 1
    out.append("".join(cur))
    return [s.strip() for s in out if s.strip()]


WRAP = {"env", "nohup", "time", "exec", "command", "sudo", "nice", "timeout", "stdbuf"}
SHELLS = {"bash", "sh", "zsh", "dash"}


def first_exec(tokens):
    """(실행되는 첫 낱말, 시험 하네스 허용 여부). 환경 대입·래퍼·셸 플래그를 건너뛴다. bash -n / -c 는 None(읽기·문자열 실행은 대상 아님)."""
    allow = False
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t):
            if t.startswith("FT_ALLOW_TRACKED_BIN=1"):
                allow = True
            i += 1; continue
        base = t.rsplit("/", 1)[-1]
        if base in WRAP:
            i += 1
            while i < len(tokens) and (tokens[i].startswith("-") or re.match(r"^\d+[smhd]?$", tokens[i])):
                i += 1
            continue
        if base in SHELLS:
            i += 1
            while i < len(tokens) and tokens[i].startswith("-"):
                if re.match(r"^-[A-Za-z]*[nc][A-Za-z]*$", tokens[i]):
                    return None, allow
                i += 1
            continue
        return t, allow
    return None, allow


def tracked_hit(word):
    w = word.strip("'\"")
    # 팩 추적 사본(harness/bin · harness/kit/fable-team/bin · r385) + BYZ freeze 사본(r386 삭제 전까지 남는 옛 위치)
    m = re.search(r"(?:^|/)(?:harness/(?:bin|kit/fable-team/bin)|scripts/(?:fable-team-bin|harness-install/fable-team/bin))/([^/\s]+?)(?:\.sh)?$", w)
    if m and m.group(1) in ENTRY:
        return m.group(1) + ".sh"
    return None


def live_bin(cwd):
    root = os.environ.get("FT_ROOT")
    if not root:
        p = subprocess.run(["git", "-C", cwd or os.getcwd(), "rev-parse", "--path-format=absolute", "--git-common-dir"], capture_output=True, text=True, timeout=5)
        root = os.path.dirname(p.stdout.strip()) if p.returncode == 0 and p.stdout.strip() else ""
    try:
        with open(os.path.join(root, ".fable-team", "LIVE_BIN"), encoding="utf-8") as f:
            v = f.readline().strip()
            if v:
                return v
    except OSError:
        pass
    return os.environ.get("FT_BIN") or ""


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
    if not cmd:
        sys.exit(0)
    if os.environ.get("FT_ALLOW_TRACKED_BIN") == "1":
        sys.exit(0)

    hit = None
    for seg in segments(cmd):
        try:
            import shlex
            toks = shlex.split(seg, comments=False, posix=True)
        except ValueError:
            toks = seg.split()
        word, allow = first_exec(toks)
        if not word or allow:
            continue
        name = tracked_hit(word)
        if name:
            hit = name
            break
    if not hit:
        sys.exit(0)

    try:
        live = live_bin(d.get("cwd"))
    except (OSError, subprocess.SubprocessError):
        live = ""
    where = live if live else "<LIVE_BIN 미설치 — master 에 ft-root-bin-shim.sh 설치 요청>"
    reason = (
        f"REJECT 추적 사본 직접 호출 — $FT_BIN/{hit} 으로 다시 부르세요 (FT_BIN={where}). "
        f"harness/bin·harness/kit/fable-team/bin(및 BYZ freeze 옛 위치)의 사본은 그 워크트리 시점의 옛 코드라 옛 한도·옛 검사로 돕니다(R201). "
        f"읽기(cat·grep·git show·bash -n)는 막지 않습니다. 시험 하네스만 FT_ALLOW_TRACKED_BIN=1."
    )
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": reason}}, ensure_ascii=False))


try:
    main()
except Exception as e:  # SystemExit 는 Exception 이 아니라 그대로 지나간다 — 파이썬 쪽 예외 전체 = 통과 + 경고(fail-open)
    warn(f"예외 {type(e).__name__}: {e}")
PYEOF
