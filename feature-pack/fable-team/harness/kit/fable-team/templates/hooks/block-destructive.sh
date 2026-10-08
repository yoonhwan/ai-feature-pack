#!/bin/bash
# PreToolUse hook — 파괴적/비가역 Bash 명령 차단 (HIL 강제)
# 신설 2026-06-09: FB_MR#8 세션을 HIL 없이 kill한 사고 재발방지.
# 데이터/인프라/세션 등 복구 불가 삭제를 시스템 레벨에서 차단한다.
# exit 2 = PreToolUse deny (stderr 메시지가 Claude에 피드백됨).

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | python3 -c "import json,sys
try:
    print(json.load(sys.stdin).get('tool_input',{}).get('command',''))
except Exception:
    print('')" 2>/dev/null)

# 파괴/비가역 패턴 (대소문자 무시)
# 2026-07-11 예외: tmux kill-session은 하드블록에서 제외(사용자 명시 표준승인 —
# "tmux,tmuxc는 컨트롤해도됨", cmux 메모리 고갈 방지 위한 상시 세션 정리 목적).
# kill-server(전체 서버 종료, 모든 세션 동시 파괴)는 그대로 차단 유지. R44: push 는 원격 ref 를 덮거나 지우는 꼴(+ref · :ref · --delete/-d · --mirror)도 force 와 같이 차단.
PATTERN='tmux kill-server|rm -[rf][rf]|rm -[rf] +-[rf]|gcloud [a-z0-9 _-]*(delete|destroy)|DROP +(TABLE|DATABASE|SCHEMA)|TRUNCATE +TABLE|dropdb|terraform +destroy|kubectl +delete|git +push[^&|;]*(--force|-f\b|--mirror|--delete|[[:space:]]-d\b|[[:space:]]\+[^[:space:]]|[[:space:]]:[^[:space:]])|git +worktree +remove|git +branch +-D|supabase [a-z0-9 _-]*delete|kill -9|pkill'

# ── 판정 466: «글자로만 들어 있는» 파괴 명령은 통과, «실행되는» 파괴 명령만 차단 ──
# 명령을 구간(; && || | & 개행)으로 나눠 글 싱크(echo·printf·정본 mbox 송신·git commit·grep·대입·cat/tee heredoc
# 본문)의 인자 글자만 PATTERN 에서 뺀다. 나머지 구간은 원문 그대로(따옴표 안 포함) PATTERN — bash -c·psql -c 도 그대로 차단.
# 예외 자격 없음(실행 소비자·치환·파일 쓰기 뒤 소비·파이프 소비·파싱 실패) = 명령 전체에 PATTERN (이전 동작, fail-closed).
judge() {
python3 - "$@" <<'PYEOF'
import json, os, re, shlex, subprocess, sys

class Inelig(Exception): pass          # 예외 자격 없음 → 명령 전체에 PATTERN

REDIR = {"<", ">", ">>", "<<", "<<<", ">|", "&>", "&>>", ">&", "<&", "<>", "<<-"}
FILE_OUT = {">", ">>", ">|", "&>", "&>>", ">&", "<>"}
CONSUMERS = {"bash", "sh", "zsh", "dash", "ksh", "fish", "eval", "source", ".", "exec", "xargs", "env", "sudo", "nohup",
             "time", "timeout", "nice", "watch", "coproc", "command", "builtin", "function", "{", "}", "!", "ssh"}
INTERP = re.compile(r"(python|perl|ruby)[0-9.]*|node")
FILTERS = {"head", "tail", "wc", "sort", "uniq", "cut"}
ASSIGN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(\[[^\]]*\])?\+?=")
HD_OPEN = re.compile(r"<<(-?)\s*([^\s;&|()<>]+)")

MOVE = re.compile(r"(^|[\s;&|(])(cd|pushd|popd)(?=[\s;&|)]|$)")   # 이동 단어 뒤 구분자(; & | ))도 경계 — DA r2 Q2
def mbox_ok(path, cwd, moved):
    # 정본 mbox = JSON cwd 의 git 루트 + /.fable-team/comm/mbox.sh (realpath 일치만 · 절대경로는 글자 그대로 `..` 0)
    # 상대경로 정본 = JSON cwd 기준 realpath 일치 · 명령에 cd/pushd/popd 가 있으면 실행 위치가 달라 인정 0(R64)
    if re.search(r"[*?\[\]{}$~`]", path) or (path.startswith("/") and ".." in path.split("/")): return False
    if not path.startswith("/") and (moved or not cwd): return False
    r = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
                       cwd=cwd or ".", capture_output=True, text=True, timeout=5)
    if r.returncode: return False
    g = r.stdout.strip()
    want = os.path.realpath(os.path.join(os.path.dirname(g) if os.path.basename(g) == ".git" else g, ".fable-team/comm/mbox.sh"))
    return os.path.isfile(want) and os.path.realpath(os.path.join(cwd or ".", path)) == want
def strip_heredoc(cmd):
    # → (본문 뺀 명령 · 따옴표 밖 개행은 `;`, 본문, 개수). 따옴표 밖 `<<` 만 센다 · 2개 이상·미종결·여는 줄 따옴표 불일치 = Inelig
    lines, out, body, n, q, esc, li = cmd.split("\n"), [], [], 0, None, False, 0
    while li < len(lines):
        line = lines[li]; li += 1
        i, delim, dash = 0, None, ""
        while i < len(line):
            ch = line[i]
            if esc: esc = False
            elif ch == "\\" and q != "'": esc = True
            elif q: q = None if ch == q else q
            elif ch in "'\"": q = ch
            elif ch == "#" and (i == 0 or line[i - 1] in " \t;&|"): break
            elif line.startswith("<<<", i): i += 3; continue
            elif line.startswith("<<", i):
                m = HD_OPEN.match(line, i)
                if not m or n: raise Inelig
                n, dash, delim = 1, m.group(1), re.sub(r"['\"\\]", "", m.group(2))
                i = m.end(); continue
            i += 1
        out.append(line + ("\n" if q else ";"))
        if delim is None: continue
        if q: raise Inelig
        while True:
            if li >= len(lines): raise Inelig
            b = lines[li]; li += 1
            if (b.lstrip("\t") if dash else b) == delim: break
            body.append(b)
    return "".join(out)[:-1], "\n".join(body), n
def split(text):
    lex = shlex.shlex(text, posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    lex.commenters = ""                                      # 주석 처리 없음 — 보이는 글자는 전부 본다
    segs, cur = [], []
    for tok in lex:
        if re.fullmatch(r"[;&|()]+", tok):
            if "(" in tok or ")" in tok or (not cur and "|" in tok): raise Inelig
            if cur: segs.append((cur, tok))
            cur = []
        else: cur.append(tok)
    return segs + ([(cur, "")] if cur else [])
def text_sink(w, hd):
    c = w[0]
    return (c in ("echo", "grep", "egrep", "fgrep") or (c == "printf" and "-v" not in w[1:])
            or (c == "git" and w[1:2] == ["commit"]) or (c in ("cat", "tee") and hd))
def classify(toks, sep, cwd, moved):
    words, redirs, i = [], [], 0
    while i < len(toks):
        t = toks[i]
        if t in REDIR: redirs.append((t, toks[i + 1] if i + 1 < len(toks) else "")); i += 2
        elif re.fullmatch(r"[<>&|]+", t): raise Inelig
        else: words.append(t); i += 1
    g = dict(toks=toks, words=words, redirs=redirs, sep=sep, mbox=False, cmd="", kind="other",
             hd=any(o in ("<<", "<<-") for o, _ in redirs))
    ci = next((k for k, w in enumerate(words) if not ASSIGN.match(w)), None)
    if ci is None:
        g["kind"] = "assign" if words else "other"; return g
    g["cmd"] = words[ci]
    if "$" in g["cmd"]: raise Inelig                          # 명령 단어가 변수
    if ci == 0:
        g["mbox"] = g["cmd"] == "bash" and len(words) > 2 and words[2] in ("send", "relay", "ring") and mbox_ok(words[1], cwd, moved)
        if g["mbox"] or text_sink(words, g["hd"]): g["kind"] = "sink"
    return g
def fileout(g):
    return g["cmd"] == "tee" or any(o in FILE_OUT and t != "/dev/null" and not (o == ">&" and re.fullmatch(r"\d+|-", t))
                                    for o, t in g["redirs"])
def judge(cmd, cwd):
    if re.search(r"\$\(|`|[<>]\(|\$'|\\\n|\$\{!", cmd): raise Inelig
    text, body, n = strip_heredoc(cmd)
    moved = bool(MOVE.search(re.sub(r"[\\'\"]", "", cmd)))   # 이동 판별은 따옴표·역슬래시를 지운 글자로(c''d·c\d) — DA r1 Q2
    segs = [classify(t, s, cwd, moved) for t, s in split(text)]
    if sum(o in ("<<", "<<-") for g in segs for o, _ in g["redirs"]) != n: raise Inelig
    for g in segs:
        skip = g["mbox"]
        for t in g["toks"]:
            if skip and t == "bash": skip = False; continue
            b = os.path.basename(t)
            if b in CONSUMERS or INTERP.fullmatch(b): raise Inelig
    others = [g for g in segs if g["kind"] == "other"]
    if others and any(fileout(g) for g in segs if g["kind"] == "sink"): raise Inelig
    for i, g in enumerate(segs):
        j = i
        while g["kind"] == "sink" and "|" in segs[j]["sep"].replace("||", "") and j + 1 < len(segs):
            j += 1
            if segs[j]["cmd"] not in FILTERS or any(a.startswith("--compress-program") for a in segs[j]["words"]): raise Inelig
    body_in = n and not any(g["hd"] and g["kind"] == "sink" and g["cmd"] in ("cat", "tee") for g in segs)
    lines = [" ".join(g["toks"]) for g in others] + ([body] if body_in else [])
    if any(g["kind"] == "assign" for g in segs) and any("$" in l for l in lines): raise Inelig
    return "\n".join(lines)

cmd = sys.argv[1]
try:
    cwd = json.loads(sys.argv[2]).get("cwd")
    print(judge(cmd, cwd if isinstance(cwd, str) else None))
except Exception:
    print(cmd)
PYEOF
}
EFFECTIVE=$(judge "$CMD" "$INPUT" 2>/dev/null) || EFFECTIVE=$CMD

if printf '%s' "$EFFECTIVE" | grep -qiE "$PATTERN"; then
  printf '🚫 파괴적/비가역 명령 차단 — HIL(사람 승인) 필수\n' >&2
  printf '명령: %s\n' "$CMD" >&2
  printf '데이터/인프라/세션을 복구 불가하게 삭제할 수 있습니다. yoonhwan 오빠의 명시 승인을 받은 뒤에만 진행하세요. (정당한 경우 사용자가 직접 ! 로 실행하거나 승인)\n' >&2
  exit 2
fi

# INJECT-BEGIN
# ── R63b 측정 조작 차단 (오빠 절대지침 2026-10-09 · BOOT 20 · 전역 하드 룰 11) ───
# 명령줄에서 직접 치는 임의 Redis 쓰기(redis-cli + 상태 생성 동사)와 말풍선 재생 URL(/dev/bubble-replay)을 실행 전에 막는다.
# ★EFFECTIVE 를 본다★ — STAGE 처럼 $CMD 를 보면 쪽지 본문·grep 패턴 글자로 막힌다(판정 466 이 고친 오탐 15건/일).
# 검색(git grep·rg·ag)·게시(gh pr/issue) 구간과 페이지 파일 경로는 검사 사본 CHK 에서 뺀다 — arch 재현 오탐 7건(r1). EFFECTIVE 자체는 불변.
# Redis 는 «명령 자리의 동사»만: redis-cli 뒤 옵션(값 0~1개)만 오고 첫 토큰이 동사 + 인자 1개 이상 (`GET set`·`CONFIG SET` 은 안 맞는다).
INJECT_VERBS='SET|SETEX|SETNX|MSET|HSET|HMSET|HSETNX|XADD|PUBLISH|LPUSH|RPUSH|SADD|ZADD|APPEND|INCR|INCRBY'
INJECT_SKIP='(^|[[:space:];&|(])(git[[:space:]]+grep|rg|ag|gh[[:space:]]+(pr|issue)[[:space:]]+(create|comment|edit|view))([[:space:]][^;&|]*|$)'
INJECT_REDIS="redis-cli([[:space:]]+--?[A-Za-z][A-Za-z-]*(=[^[:space:]]*)?([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+['\"]?($INJECT_VERBS)['\"]?[[:space:]]+[^[:space:]]"
INJECT_PATTERN="$INJECT_REDIS|/dev/bubble-replay"
# 실행 치환($( )·백틱·<( )·>( ))이 하나라도 있으면 검색·게시 예외 0 — 셸이 «실행»하는 구간이라 글자가 아니다(DA r1 Q2).
case "$EFFECTIVE" in
  *'$('*|*'`'*|*'<('*|*'>('*) INJECT_SED='s#app/dev/bubble-replay##g' ;;
  *) INJECT_SED="s#$INJECT_SKIP#\\1#g; s#app/dev/bubble-replay##g" ;;
esac
# 따옴표·역슬래시 제거 — 셸 단어 이어붙임(redis-''cli·S""ET)을 한 단어로 본다(DA r2 Q2). 검색·게시 제거(sed)가 먼저라 따옴표 안 검색 패턴은 이미 빠진 뒤.
CHK=$(printf '%s' "$EFFECTIVE" | LC_ALL=C sed -E "$INJECT_SED" | LC_ALL=C tr -d "\\\\'\"") || CHK=$EFFECTIVE
if printf '%s' "$CHK" | grep -qiE "$INJECT_PATTERN"; then
  printf '🚫 측정 조작 차단 — 임의 Redis 쓰기·말풍선 DOM 주입(오빠 절대지침 · BOOT 20 · 전역 하드 룰 11)\n' >&2
  printf '명령: %s\n' "$CMD" >&2
  printf '측정은 trusted 클릭 + 기존 e2e 러너(tests/e2e/realtime_multi_e2e.py)만. 정당한 운영 쓰기는 파일에 쓰고 사람이 ! 로 실행하세요.\n' >&2
  exit 2
fi
# INJECT-END

# ── 스테이징 오염 차단 (신설 2026-09-16, CFO 트랙 규율 F17) ──────────────────
# 같은 워크트리를 여러 세션이 동시에 쓰면 `git add .`/`-A` 가 "남이 만든 파일"까지
# 자기 커밋에 싣는다. 2026-09-15 하루에 세 번 났고, 한 번은 코드 3파일이 다른 세션의
# 문서 커밋에 섞여 구조/문서 혼합(Tidy First 위반)까지 갔다.
# ★파괴적이지 않지만 되돌리기 어렵다★ — 공유 브랜치라 히스토리 재정리가 위험하다.
# ★이 훅이 막지 못하는 것★: `git add <디렉토리>/` 형태. 그것도 같은 사고를 내지만
# 의도적인 경우가 많아 차단하지 않는다 — 그건 사람이 판단한다.
# ★알려진 오탐(허용)★: 명령문 안에 문자열로 들어 있기만 해도 차단된다(문서·echo·주석 포함).
#   위 파괴 패턴도 같은 성질이고(`rm -rf` 를 문장에 쓰면 차단), 이 훅의 관행이다.
#   ★정교하게 파싱하지 않는 이유★: 판정기를 촘촘하게 만들수록 예외 목록이 자라고,
#   예외가 자라면 그 판정기는 결국 아무것도 안 막는다(2026-09-15 CFO 트랙에서 배운 것).
#   막히면 우회하지 말고 파일에 써서 실행하거나 사람이 직접 실행한다.
#   ★글 싱크 닫힌 목록으로 바꾼 이유(판정 466)★: 쪽지 본문·echo·heredoc 으로 쓰는 시험 파일·grep 패턴의 «글자»가 하루 15건 넘게
#   오탐이었고 실제 파괴는 0 이었다. 예외 목록이 아니라 «6종 싱크 + 나머지 전부 이전 규칙»이라 목록 자체를 늘리는 것도 판정 사항이다.
# ★경계를 요구한다★ — 뒤에 공백이나 줄끝이 와야 「전체 스테이징」이다.
#   2026-09-16 실측 오탐: 경계가 없으면 숨김 폴더로 시작하는 경로(.claude/… .github/… 등)의
#   맨 앞 점이 「전체」로 오인돼 정당한 경로 지정까지 막았다. 구현 좌석이 그 자리에서 걸렸다.
STAGE_PATTERN='git +add +(\.([[:space:]]|$)|-A([[:space:]]|$)|--all([[:space:]]|$))'
if printf '%s' "$CMD" | grep -qE "$STAGE_PATTERN"; then
  printf '🚫 git add . / -A 차단 — 스테이징 오염 방지 (CFO 규율 F17)\n' >&2
  printf '명령: %s\n' "$CMD" >&2
  printf '같은 워크트리를 다른 세션이 동시에 쓰고 있으면 남의 파일까지 커밋에 실립니다.\n' >&2
  printf '대신: (1) git status 로 스테이징에 내가 안 만진 파일이 있는지 보고 (2) git add <내 파일 경로들> 로 경로를 지정하세요.\n' >&2
  printf '그래도 섞이면 "섞였다"고 보고하고, 히스토리 재정리는 하지 마세요(공유 브랜치).\n' >&2
  exit 2
fi
exit 0
