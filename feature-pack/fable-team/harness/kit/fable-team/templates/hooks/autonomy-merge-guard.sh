#!/bin/bash
# fable-team autonomy-merge-guard — PreToolUse:Bash (r-autonomy-hooks 훅③ · 판정 1355 · EVAL-night-autonomy-20261013 결함 2)
# 왜: 10-13 밤 planner 가 main 병합·배포를 판별기 없이 손판단(1333·1337) → 판정 1675: 자율 중에도 main 병합 = 오빠 값(push-merge 대리 폐지).
# 동작(ON·BYZ 리포 안만): 오빠 승인 `<상태>/autonomy-merge-approved/<40hex>`(ft-autonomy.sh approve-merge 가 씀)가 있고 그 내용 1줄이 `<상태>/autonomy.log` 에 글자 그대로 있는 sha 만 통과.
#   ★r462★ 글자 일치가 아니면 그 승인 sha 들 중 «같은 변경 집합»(ft_approval_equiv.py EQUIV = 승인 위 main 병합·rebase 만 · 자기 변경 diff·병합 트리 동일)이 있을 때 통과 + 로그 `EQUIV <승인> -> <head>`.
#   옛 `autonomy-merge-ok/`(push-merge PROXY 시절 파일)는 읽지 않는다 — 파일은 보존, 승인 근거 아님(DA② H1).
#   · `gh pr merge`/`ft-gh-as-tank.sh pr merge` → `--match-head-commit <sha>` 필수(헤드 결속은 gh 가 강제). `gh api …/pulls/N/merge` 는 `sha=<sha>`.
#   · main 대상 `git push`(main·HEAD:main·x:main·refs/heads/main · `--repo` 포함 · 맨 push+현재 브랜치 main) → 보내는 쪽 ref(없으면 HEAD)의 rev-parse sha. 삭제(:main·--delete/-d)·--all·--mirror·와일드카드는 항상 deny. --dry-run allow.
#   `env -S '<명령>'` 는 `bash -c` 처럼 안쪽을 재검사. OFF·위변조·따옴표/heredoc/mbox 본문 글자만 = allow.
# ★못 읽음(R176 · 판정 1675 ①)★: ft-autonomy.sh 못 찾음·rc≠0 = 병합·main push 는 deny + 이유 + 로그(FT_AUTONOMY_HOOK_LOG). 파싱 불가(JSON·예외)는 그대로 허용+로그. 외부 호출 0.
#   ★r560★ ①판정기 자리 = <루트>/.fable-team/LIVE_BIN 1줄 + ft_approval_equiv.py (첫 줄이 bash 대리 파일(shim)이면 안 쓴다 — shim 폴더를 도구 자리로 잡으면 python3 -I 가 SyntaxError 로 «판정기 출력 없음» 만 남겼다) ②후보 순서 = `git rev-list <S> ^origin/main` 에 든 승인 먼저(병합 경로) → 그다음 최신순(rebase 경로) ③autonomy.log 는 «한 번» 읽어 집합(후보마다 다시 읽지 않음) ④판정기 stderr·rc·시간 초과·마감 소진을 거절 이유에 남긴다(마감 21초·후보당 7초는 그대로 — 판정 666).
# 도구·상태 해석 = 오빠 `!` 와 같은 곳: FT_AUTONOMY_SH → harness-env.sh 의 FT_BIN → 루트 2경로 · 상태는 FT_ROOT 가 env 에 있을 때만 그것, 아니면 도구 자기 루트.
# ★설치는 이 파일 범위 밖 — 설치 카드★
# ★r546★ env -S 분해는 공용 모듈 merge_cmd.env_split 하나 — 같은 폴더의 merge_cmd.py 가 없으면 rc2(막음). 사본 0.
set +e
INPUT=$(cat 2>/dev/null); [ -n "$INPUT" ] || exit 0
export INPUT AMG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$AMG_DIR/merge_cmd.py" ] || { echo "REJECT autonomy-merge-guard: merge_cmd 없음 — 같은 폴더 공용 모듈(r546)이 필요하다: $AMG_DIR/merge_cmd.py" >&2; exit 2; }
python3 - <<'PYEOF'
import json, os, re, shlex, subprocess, sys, time

sys.path.insert(0, os.environ["AMG_DIR"])
from merge_cmd import env_split  # r546: 사본 삭제 전 이 훅 안에 있던 그 함수(글자 그대로 옮겼다)

LOG = os.environ.get("FT_AUTONOMY_HOOK_LOG") or os.path.expanduser("~/.claude/logs/autonomy-hooks.log")
WRAP = {"sudo", "env", "command", "exec", "nohup", "time", "timeout", "nice"}
SHELLS = {"bash", "sh", "zsh", "dash"}
VALOPTS = {"-u", "-C", "-S", "-P", "-k", "-s", "-n"}  # 값을 하나 더 먹는 래퍼 옵션(env -u NAME · timeout -k N · nice -n N)
SHA = re.compile(r"^[0-9a-f]{40}$")
REASON = ("자율 ON 중 병합·main push 는 오빠가 `! bash /tmp/h<N>`(ft-autonomy.sh approve-merge <sha>)로 승인한 sha 만 — pr merge 는 --match-head-commit <sha> 로, "
          "main push 는 승인된 sha 를 보낼 때만(판정 1675). 승인 전이면 오빠 큐.")
EQUIV_HINT = " 승인 sha 위에 main 병합만 더한 head(같은 변경 집합)는 재승인 없이 통과한다(EQUIV · r462) — head 객체·origin/main 이 로컬에 있어야 대조된다."

UNREADABLE = "자율 상태(ft-autonomy.sh mode)를 못 읽어 병합을 막았다 — 도구 경로·상태 폴더를 고친 뒤 다시 친다(R176). "

def note(msg):
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%dT%H:%M:%S") + f" autonomy-merge-guard: {msg}\n")
    except OSError:
        pass

def byz_root(cwd):
    root = os.environ.get("FT_ROOT")
    if not root:
        p = subprocess.run(["git", "-C", cwd or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd(), "rev-parse", "--path-format=absolute", "--git-common-dir"],
                           capture_output=True, text=True, timeout=5)
        root = os.path.dirname(p.stdout.strip()) if p.returncode == 0 and p.stdout.strip() else ""
    return root if root and os.path.isdir(os.path.join(root, ".fable-team")) else ""

# --- R176 resolve begin (두 훅 같은 문장 — tests/harness/test_autonomy_hooks_layout.sh 가 바이트 대조) ---
def autonomy_sh(root):
    """ft-autonomy.sh 해석(R176): FT_AUTONOMY_SH → <루트>/.fable-team/bin-harness/harness-env.sh 의 `export FT_BIN=<경로>` 한 줄(source 0) → 루트 shim → $FT_HARNESS_ROOT/bin(r385). 없으면 None."""
    cands = [os.environ.get("FT_AUTONOMY_SH") or ""]
    try:
        with open(os.path.join(root, ".fable-team/bin-harness/harness-env.sh"), encoding="utf-8") as f:
            for line in f:
                m = re.match(r"""^\s*export\s+FT_BIN=(["']?)([^\s"'$`]+)\1\s*(#.*)?$""", line)
                if m:
                    cands.append(os.path.join(m.group(2), "ft-autonomy.sh"))
                    break
    except OSError:
        pass
    hr = os.environ.get("FT_HARNESS_ROOT") or ""
    cands += [os.path.join(root, ".fable-team/bin/ft-autonomy.sh"), hr and os.path.join(hr, "bin/ft-autonomy.sh")]
    return next((c for c in cands if c and os.path.isfile(c)), None)

def autonomy_state(sh):
    """도구가 읽는 상태 폴더 — ft-autonomy.sh:15-16 과 같은 규칙: FT_AUTONOMY_STATE_DIR → FT_ROOT/.fable-team/state → 도구 자기 루트(`<도구 폴더>/../..`)."""
    if os.environ.get("FT_AUTONOMY_STATE_DIR"):
        return os.environ["FT_AUTONOMY_STATE_DIR"]
    base = os.environ.get("FT_ROOT") or os.path.abspath(os.path.join(os.path.dirname(sh), "../.."))
    return os.path.join(base, ".fable-team/state")
# --- R176 resolve end ---

def mode_of(root):
    """(도구 경로, on|off|tamper) — 못 읽으면 모드 ""(R176 · 판정 1675 ①: 못 읽음 = 병합 deny)."""
    sh = autonomy_sh(root)
    try:
        p = subprocess.run(["bash", sh, "mode"], capture_output=True, text=True, timeout=5) if sh else None
    except (OSError, subprocess.SubprocessError):
        p = None
    mode = p.stdout.strip() if p is not None and p.returncode == 0 else ""
    return sh, mode if mode in ("on", "off", "tamper") else ""

def strip_heredocs(cmd):
    out, delim = [], None
    for line in cmd.split("\n"):
        if delim is not None:
            delim = None if line.strip() == delim else delim
            continue
        out.append(line)
        m = re.search(r"(?<!<)<<(?!<)-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1", line)
        delim = m.group(2) if m else None
    return "\n".join(out)

def simple_commands(cmd):
    """명령 문자열 → [단어들] — 따옴표 안·heredoc 본문은 글자일 뿐 명령이 아니다. 리다이렉트 토큰은 버린다."""
    lex = shlex.shlex(strip_heredocs(cmd), posix=True, punctuation_chars=";&|()<>\n")
    lex.whitespace, lex.whitespace_split, lex.commenters = " \t\r", True, ""
    segs, words, skip = [], [], False
    for t in lex:
        if skip:
            skip = False
        elif t and set(t) <= set(";&|()\n"):
            segs.append(words); words = []
        elif t and set(t) <= set("<>&|"):
            skip = True
        else:
            words.append(t)
    return segs + [words]

def resolve(words):
    """환경 대입·래퍼·셸 인터프리터를 벗겨 (프로그램 basename, 인자들) — `bash -c 'x'` 는 ('-c', [x])."""
    w = list(words)
    while w:
        b = os.path.basename(w[0])
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w[0]):
            w.pop(0)
        elif b in WRAP:
            w.pop(0)
            while w and (w[0].startswith("-") or re.match(r"^([A-Za-z_][A-Za-z0-9_]*=|[0-9.]+$)", w[0])):
                split = env_split(b, w)
                if split is not None: w = split; break  # 첫 낱말이 실행 프로그램 — 맨 위 루프가 다시 벗긴다(bash -c 일 때만 셸 코드 재검사)
                del w[:2 if w[0] in VALOPTS else 1]
        elif b in SHELLS:
            w.pop(0)
            while w and w[0].startswith("-") and not re.fullmatch(r"-[a-zA-Z]*c[a-zA-Z]*", w[0]):
                w.pop(0)
            if w and w[0].startswith("-"):
                return "-c", w[1:2]
        else:
            return b, w[1:]
    return "", []

def head_arg(args, flag):
    for i, a in enumerate(args):
        if a == flag and i + 1 < len(args):
            return args[i + 1]
        if a.startswith(flag + "="):
            return a[len(flag) + 1:]
    return ""

def live_judge(root, sh):  # r560: 판정기 자리 — LIVE_BIN 우선 · 첫 줄 bash 대리 파일(shim)은 건너뛴다 · 없으면 "" (통과 0)
    """<루트>/.fable-team/LIVE_BIN 1줄 = 라이브 bin 폴더. 두 번째 후보 = 도구 폴더(FT_AUTONOMY_SH 의 형제 · 설치 꼴·시험 꼴)."""
    cands = []
    try:
        with open(os.path.join(root, ".fable-team/LIVE_BIN"), encoding="utf-8") as f:
            for line in f:
                if line.strip():
                    cands.append(os.path.join(line.strip(), "ft_approval_equiv.py"))
                    break
    except OSError:
        pass
    if sh:
        cands.append(os.path.join(os.path.dirname(sh), "ft_approval_equiv.py"))
    for c in cands:
        try:
            with open(c, encoding="utf-8", errors="replace") as f:
                head = f.readline()
        except OSError:
            continue
        if not (head.startswith("#!") and "bash" in head):  # 루트 shim(.py = bash 대리 파일)이면 python3 -I 가 못 읽는다
            return c
    return ""

class Guard:
    def __init__(self, state, cwd, sh=None, root=""):  # state 없음(못 읽음) = 승인 근거 0 → 병합·main push 전부 deny
        self.approved, self.logpath, self.cwd = (os.path.join(state, "autonomy-merge-approved"), os.path.join(state, "autonomy.log"), cwd) if state else (None, None, cwd)
        self.judge = live_judge(root, sh) if root else ""
        self.logged = None   # r560: autonomy.log 줄 집합 — 첫 exact() 때 한 번만 읽는다
        self.why = "" if self.judge else "라이브 판정기 없음: %s" % (os.path.join(root, ".fable-team/LIVE_BIN") if root else "<루트 미상>")

    def cands(self, sha):  # r560: 후보 = exact 승인들 · ⓐ S 줄기 안의 승인(rev-list <S> ^origin/main) 먼저 ⓑ 그다음 mtime 최신순
        """★DA⑥ r1★ 이미 origin/main 의 조상인 승인(=착지한 세트)은 새 head 의 근거에서 뺀다 — 착지 뒤 다른 트리를 같은 승인으로 통과시키던 구멍."""
        try:
            names = [a for a in os.listdir(self.approved) if SHA.match(a)]
        except OSError:
            return []
        names = sorted((a for a in names if self.exact(a)), key=lambda a: os.path.getmtime(os.path.join(self.approved, a)), reverse=True)
        trunk = dict.fromkeys(self.git("rev-list", sha, "^origin/main").split())
        landed = set(self.git("rev-list", "origin/main").split())
        if any(a in landed for a in names):
            self.why = "착지한 승인은 근거 아님(이미 origin/main 의 조상)"
        names = [a for a in names if a not in landed]
        return [a for a in trunk if a in names] + [a for a in names if a not in trunk]

    def ok(self, sha):
        """정확 일치(exact) → 아니면 EQUIV(r462): 오빠 승인 sha 중 «같은 변경 집합»(ft_approval_equiv.py rc0 = 승인 위 main 병합·rebase 만)이 있으면 통과.
        판정기 = ft-merge-land(R247)·scope-approve(r411)와 같은 것 하나 — 못 판단(rc3·시간 초과 7초)·판정기 없음 = 통과 0."""
        if self.exact(sha):
            return True
        if not SHA.match(sha) or not self.approved or not self.judge:
            return False
        try:   # ★DA⑥ r1 H2★ EQUIV 경로(판정기 찾기·실행·해독·파싱)의 예외는 deny — 훅 바깥 fail-open 으로 새면 안 된다
            return self.equiv(sha)
        except Exception as e:
            self.why = "판정기 예외: %s" % type(e).__name__
            note(f"EQUIV 경로 예외 {type(e).__name__} {e} — deny(fail-open 금지 · DA⑥ r1)")
            return False

    def equiv(self, sha):   # 후보를 하나씩 판정기에 넣는다 — 출력은 bytes 로 받아 errors="replace" 로 해독(C 로케일에서 UnicodeDecodeError 로 새던 자리)
        cands = self.cands(sha)
        deadline = time.time() + 21  # 7초 × 3 — 훅 하나가 세션을 오래 붙잡지 않게(판정 666)
        tried, why = 0, []
        for a in cands:
            if time.time() > deadline:
                why.append("후보 %d 중 %d 대조 · 마감 21초" % (len(cands), tried))
                break
            tried += 1
            try:
                p = subprocess.run(["python3", "-I", self.judge, self.cwd, a, sha, "origin", "main"], capture_output=True, timeout=7)
            except subprocess.TimeoutExpired:
                why.append("판정기 7초 초과")
                continue
            p.stdout = p.stdout.decode("utf-8", "replace")   # ★DA⑥ r1 H2★ 해독 실패 = 예외 0(errors="replace")
            p.stderr = p.stderr.decode("utf-8", "replace")
            if p.returncode == 0 and p.stdout.startswith("EQUIV "):
                note(f"EQUIV {a} -> {sha} ({p.stdout.strip()[:200]})")
                return True
            first = (p.stdout.strip().splitlines() or [""])[0][:200]
            err = (p.stderr.strip().splitlines() or [""])[0][:120]   # r560: stderr·rc 를 버리지 않는다(옛 판 = «출력 없음» 만)
            why.append("rc=%d %s%s" % (p.returncode, first or "출력 없음", (" stderr=" + err) if err else ""))
        if why:   # r560: «왜 못 닿았나» 를 남긴다 — 서로 다른 이유 2개 + 대조한 후보 수(옛 판 = 첫 줄 하나만)
            u = list(dict.fromkeys(why))
            self.why = (" | ".join(u[:2]) + ((" | 후보 %d 중 %d 대조" % (len(cands), tried)) if len(u) > 1 else ""))[:400]
        return False

    def exact(self, sha):
        """승인 파일 1줄(`approve-merge <sha> …`)이 autonomy.log 의 한 줄과 글자 그대로 같을 때만 — 파일만 있으면(직접 쓰기) 아니다. 로그는 한 번만 읽는다(r560)."""
        if not SHA.match(sha) or not self.approved:
            return False
        if self.logged is None:
            try:
                with open(self.logpath, encoding="utf-8") as f:
                    self.logged = set(f.read().splitlines())
            except OSError:
                self.logged = set()
        try:
            with open(os.path.join(self.approved, sha), encoding="utf-8") as f:
                lines = f.read().splitlines()
        except OSError:
            return False
        return len(lines) == 1 and lines[0].startswith("approve-merge %s " % sha) and lines[0] in self.logged

    def git(self, *a):
        p = subprocess.run(["git", "-C", self.cwd, *a], capture_output=True, text=True, timeout=5)
        return p.stdout.strip() if p.returncode == 0 else ""

    def anc(self, a, b):   # r560 DA⑥ ⓝ: main push 는 «최신 main 을 품은 head» 만 — 옛 main 위 head 를 직접 밀면 main 이 지운 것을 되돌린다(초록 지우기)
        return subprocess.run(["git", "-C", self.cwd, "merge-base", "--is-ancestor", a, b], capture_output=True, timeout=5).returncode == 0

    def push_denied(self, args):
        flags = [a for a in args if a.startswith("-")]
        if "--dry-run" in flags or "-n" in flags:
            return False
        pos, skip = [], False
        has_repo = any(a == "--repo" or a.startswith("--repo=") for a in args)  # --repo 가 원격을 정하면 positional 전부가 refspec
        for a in args:
            if skip:
                skip = False
            elif a in ("-o", "--push-option", "--repo", "--receive-pack", "--exec"):
                skip = True
            elif not a.startswith("-"):
                pos.append(a)
        if "--all" in flags or "--mirror" in flags:
            return True
        specs = pos if has_repo else pos[1:]
        if "--delete" in flags or "-d" in flags:  # 삭제 = 보내는 쪽이 빈 refspec(`:main`)과 같다
            specs = [r if ":" in r else ":" + r for r in specs]
        specs = specs or (["HEAD:main"] if self.git("symbolic-ref", "--short", "HEAD") == "main" else [])
        for r in specs:
            r = r.lstrip("+")
            src, dst = r.split(":", 1) if ":" in r else (r, r)
            if "*" not in r and dst.replace("refs/heads/", "", 1) != "main":
                continue
            sha = "" if ("*" in r or not src) else self.git("rev-parse", "--verify", "-q", src + "^{commit}")
            if not sha or not self.ok(sha):
                return True
            if self.git("rev-parse", "--verify", "-q", "origin/main^{commit}") and not self.anc("origin/main", sha):
                self.why = self.why or "main 이 head 의 조상이 아님 — main push 는 최신 main 을 품은 head 만(옛 main 위 head 직접 push 는 지운 것을 되살린다)"
                return True
        return False

    def denied(self, cmd, depth=0):
        for words in simple_commands(cmd):
            prog, args = resolve(words)
            if prog == "cd" and args:
                self.cwd = os.path.normpath(os.path.join(self.cwd, args[0]))
            elif prog == "-c" and depth < 3 and args and self.denied(args[0], depth + 1):
                return True
            elif prog in ("gh", "ft-gh-as-tank.sh"):
                if any(args[i:i + 2] == ["pr", "merge"] for i in range(len(args))):
                    if not self.ok(head_arg(args, "--match-head-commit")):
                        return True
                elif "api" in args and any(re.search(r"/pulls/[0-9]+/merge$", a) for a in args):
                    if not self.ok(next((a[4:] for a in args if a.startswith("sha=")), "")):
                        return True
            elif prog == "git":
                a, i = list(args), 0
                while i < len(a) and a[i].startswith("-"):
                    if a[i] == "-C" and i + 1 < len(a):
                        self.cwd = os.path.normpath(os.path.join(self.cwd, a[i + 1]))
                    i += 2 if a[i] in ("-C", "-c") else 1
                if a[i:i + 1] == ["push"] and self.push_denied(a[i + 1:]):
                    return True
        return False

try:
    d = json.loads(os.environ["INPUT"])
    cmd = (d.get("tool_input") or {}).get("command") or ""
    if d.get("tool_name") != "Bash" or not re.search(r"merge|push", cmd):  # 거의 모든 Bash 호출 앞에 서는 훅 — 관련 글자 없으면 즉시 통과
        sys.exit(0)
    cwd = d.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    root = byz_root(cwd)
    if not root:
        sys.exit(0)
    sh, mode = mode_of(root)
    if not mode:
        note(f"ft-autonomy.sh mode 를 못 읽음(도구={sh}) — 병합·main push 는 deny(R176 · 판정 1675 ①)")
    elif mode != "on":
        sys.exit(0)
    guard = Guard(autonomy_state(sh) if mode else "", cwd, sh, root)
    hit = guard.denied(cmd)
except (ValueError, OSError, AttributeError, subprocess.SubprocessError) as e:
    note(f"{type(e).__name__} {e} — 허용(fail-open)")
    sys.exit(0)
if hit:
    reason = (REASON if mode else UNREADABLE + REASON) + (f" 재승인 필요 — 승인 sha 와 같은 변경 집합 아님: {guard.why}" if guard.why else EQUIV_HINT)
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": reason}}, ensure_ascii=False))
PYEOF
exit $?  # r546: 종전 `exit 0` 은 모듈 없음·모듈 오류까지 삼켰다 — 이제 rc2(막음)가 전달된다
