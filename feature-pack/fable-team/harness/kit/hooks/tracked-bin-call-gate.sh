#!/bin/bash
# tracked-bin-call-gate — PreToolUse:Bash (R201 범위 추가 · 카드 r201-root-bin-stale-copy-shim)
# 왜: 뒤처진 워크트리의 `harness/bin/<도구>`(git 추적 사본 · r385 전엔 BYZ 리포 안 옛 위치)를 직접 부르면 «그 워크트리 시점의 옛 코드» 가 돈다(옛 자원 한도 30 · 드리프트 검사 건너뜀).
#     loom#27 spawn 이 loom-main 의 52커밋 뒤진 사본으로 REJECT(planner#49 #92812). 사본은 추적 파일이라 연결 파일로 바꿀 수 없다 → 호출 순간에 막고 라이브 경로를 안내한다.
# 동작: 명령을 구분자(; && || | 개행 $( `)로 나눠 «실행되는 첫 낱말» 이 `*/harness/bin/<입구 도구>` 또는 `*/harness/kit/fable-team/bin/<입구 도구>`(+ BYZ freeze 옛 위치 두 곳) 이면 deny.
#       입구 도구 = spawn · close · role-spawn · successor-open · resource-gate · resource-reclaim.
#       ★r1145·r1146★ 그 밖 ft-* 도 «그 파일이 든 체크아웃의 가지가 main 이고 HEAD 가 origin/main 을 품지 않으면»(뒤처진 main 체크아웃) deny — lecture#30 이 273커밋 뒤 팩 체크아웃의 ft-merge-land 로 옛 안내를 9개 팀에 퍼뜨림. 가지 ≠ main(나노·팀 — squash 착지라 origin/main 을 못 품음)·분리 HEAD(격리 사본)는 통과(r1145 오탐 2).
#       같은 명령 앞 조각의 `NAME=값`(대입만 있는 조각 · export 허용)을 모아 뒤 조각의 `$NAME`·`${NAME}` 를 풀고, `cd <폴더>` 조각을 따라 상대 경로를 푼다.
#       읽기(cat·grep·sed -n·git show·bash -n)와 `$FT_BIN/…`·`.fable-team/bin/…` 호출·최신 체크아웃의 입구 밖 도구·`FT_ALLOW_TRACKED_BIN=1`(시험 하네스) 은 통과.
# ★못 읽음★: 입력 JSON 을 못 읽거나 파싱 실패 = 통과 + stderr 경고(fail-open · 다른 홈 훅과 같은 꼴 · 파괴 아님). git 판정 불가 = 통과 + 경고 1줄.
#       외부 호출: git rev-parse 1회(deny 때만) + 입구 밖 ft-* 경로일 때만 git symbolic-ref 1회 + (가지 main 일 때만) git merge-base 1회(각 timeout 5).
# 환경: FT_ROOT(루트 고정) · FT_BIN(안내용 라이브 위치 보조). ★설치(~/.claude/hooks/ 복사 · settings.json PreToolUse Bash 등록)는 master — 이 파일 범위 밖★
# ★r546★ 명령 조각내기는 공용 모듈 merge_cmd.segments 하나 — 같은 폴더의 merge_cmd.py 가 없으면 rc2(막음). 사본 0.
set +e
INPUT=$(cat 2>/dev/null)
[ -n "$INPUT" ] || exit 0
export INPUT
command -v python3 >/dev/null 2>&1 || { echo "WARN tracked-bin-call-gate: python3 없음 — 통과" >&2; exit 0; }
TBC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; export TBC_DIR
[ -f "$TBC_DIR/merge_cmd.py" ] || { echo "REJECT tracked-bin-call-gate: merge_cmd 없음 — 같은 폴더 공용 모듈(r546)이 필요하다: $TBC_DIR/merge_cmd.py" >&2; exit 2; }
ENTRY_TOOLS="ft-nano-spawn ft-nano-close ft-role-spawn ft-successor-open ft-resource-gate ft-resource-reclaim"
export ENTRY_TOOLS
python3 - <<'PYEOF'
import json, os, re, subprocess, sys

sys.path.insert(0, os.environ["TBC_DIR"])
from merge_cmd import segments  # r546: 사본 삭제 전 tracked-bin-call-gate 안에 있던 그 함수(글자 그대로 옮겼다)

ENTRY = os.environ.get("ENTRY_TOOLS", "").split()


def warn(msg):
    print(f"WARN tracked-bin-call-gate: {msg} — 통과", file=sys.stderr)
    sys.exit(0)


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
    """(표시 이름, 입구 도구 여부). 추적 사본 자리의 입구 도구 = (이름, True) · 그 밖 ft-* = (이름, False) · 해당 없음 = (None, False)."""
    w = word.strip("'\"")
    # 팩 추적 사본(harness/bin · harness/kit/fable-team/bin · r385) + BYZ freeze 사본(r386 삭제 전까지 남는 옛 위치)
    m = re.search(r"(?:^|/)(?:harness/(?:bin|kit/fable-team/bin)|scripts/(?:fable-team-bin|harness-install/fable-team/bin))/([^/\s]+?)(?:\.sh)?$", w)
    if m and m.group(1) in ENTRY:
        return m.group(1) + ".sh", True
    if m and m.group(1).startswith("ft-"):
        return w.rsplit("/", 1)[-1], False
    return None, False


def expand(tok, env):
    """같은 명령 안에서 모은 셸 변수만 푼다(r1145). 모르는 변수($FT_BIN 등)는 그대로 둔다."""
    return re.sub(r"\$\{([A-Za-z_]\w*)\}|\$([A-Za-z_]\w*)", lambda m: env.get(m.group(1) or m.group(2), m.group(0)), tok)


def note_assign(toks, env):
    """조각 전체가 대입(NAME=값 … · export 허용)이면 셸 변수로 모으고 True. 값에 $·` 가 남으면 모르는 값이라 버린다."""
    t = toks[1:] if toks[:1] == ["export"] else toks
    if not t or not all(re.match(r"^[A-Za-z_]\w*=", x) for x in t):
        return False
    for x in t:
        n, v = x.split("=", 1)
        v = os.path.expanduser(v)
        if "$" in v or "`" in v:
            env.pop(n, None)
        else:
            env[n] = v
    return True


def stale(word, cwd):
    """체크아웃이 «가지 main 인데 HEAD ⊉ origin/main» 이면 True(r1146). 가지 ≠ main·분리 HEAD·폴더 없음 = False · git 판정 불가 = False + 경고 1줄."""
    d = os.path.dirname(os.path.join(cwd, os.path.expanduser(word.strip("'\""))))
    if not os.path.isdir(d):
        return False
    try:
        b = subprocess.run(["git", "-C", d, "symbolic-ref", "-q", "--short", "HEAD"], capture_output=True, text=True, timeout=5)
        if b.returncode not in (0, 1):
            print(f"WARN tracked-bin-call-gate: 판정 불가 git rc={b.returncode} ({d}) — 통과", file=sys.stderr)
            return False
        if b.stdout.strip() != "main":
            return False
        p = subprocess.run(["git", "-C", d, "merge-base", "--is-ancestor", "origin/main", "HEAD"], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError) as e:
        print(f"WARN tracked-bin-call-gate: 판정 불가 git {type(e).__name__} ({d}) — 통과", file=sys.stderr)
        return False
    if p.returncode not in (0, 1):
        print(f"WARN tracked-bin-call-gate: 판정 불가 git rc={p.returncode} ({d}) — 통과", file=sys.stderr)
    return p.returncode == 1


def find_hit(cmd, cwd):
    """(표시 이름, 뒤처진 경로 또는 None). 입구 도구 = 늘 hit · 그 밖 ft-* = 뒤처진 체크아웃일 때만 hit."""
    import shlex
    env = {}
    for seg in segments(cmd):
        try:
            toks = shlex.split(seg, comments=False, posix=True)
        except ValueError:
            toks = seg.split()
        toks = [expand(t, env) for t in toks]
        if note_assign(toks, env):
            continue
        if toks[:1] == ["cd"] and len(toks) == 2:
            cwd = os.path.join(cwd, os.path.expanduser(toks[1]))
            continue
        word, allow = first_exec(toks)
        if not word or allow:
            continue
        name, entry = tracked_hit(word)
        if entry:
            return name, None
        if name and stale(word, cwd):
            return name, os.path.normpath(os.path.join(cwd, os.path.expanduser(word.strip("'\""))))
    return None, None


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

    hit, stale_path = find_hit(cmd, d.get("cwd") or os.getcwd())
    if not hit:
        sys.exit(0)

    try:
        live = live_bin(d.get("cwd"))
    except (OSError, subprocess.SubprocessError):
        live = ""
    where = live if live else "<LIVE_BIN 미설치 — master 에 ft-root-bin-shim.sh 설치 요청>"
    head = (f"REJECT 뒤처진 체크아웃의 도구 직접 호출({stale_path} · 가지 main 인데 HEAD 가 origin/main 을 품지 않음 · r1146)" if stale_path
            else "REJECT 추적 사본 직접 호출")
    reason = (
        f"{head} — $FT_BIN/{hit} 으로 다시 부르세요 (FT_BIN={where}). "
        f"harness/bin·harness/kit/fable-team/bin(및 BYZ freeze 옛 위치)의 사본은 그 워크트리 시점의 옛 코드라 옛 한도·옛 검사로 돕니다(R201). "
        f"읽기(cat·grep·git show·bash -n)는 막지 않습니다. 시험 하네스만 FT_ALLOW_TRACKED_BIN=1."
    )
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": reason}}, ensure_ascii=False))


try:
    main()
except Exception as e:  # SystemExit 는 Exception 이 아니라 그대로 지나간다 — 파이썬 쪽 예외 전체 = 통과 + 경고(fail-open)
    warn(f"예외 {type(e).__name__}: {e}")
PYEOF
