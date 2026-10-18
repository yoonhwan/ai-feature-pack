#!/bin/bash
# merge-head-gate — PreToolUse:Bash (R230 · 판정 1860·1862·1875 · 자율 ON/OFF 무관)
# 왜: v65 같은 큰 병합 뒤 옛 main 위의 세트를 그대로 병합하면 main 이 더한 줄이 되돌려진다(뒤로 회귀 · 10-03 S10 사고 꼴).
# 동작(BYZ 리포 안만): ★main 병합 = ft-merge-land.sh 뿐★(오빠 판정 1875)
#   · `gh pr merge`·`ft-gh-as-tank.sh pr merge`·`gh api …/pulls/N/merge` = 항상 deny(사유: ft-merge-land.sh 로)
#   · main 향 `git push` = ft-merge-gate.sh 통과해야 함(보내는 쪽 sha 의 «현재 main 포함 + main 이 더한 줄 보존») · force·+refspec·삭제·--all·--mirror·와일드카드 = deny · --dry-run·main 아닌 대상 = 통과
#   · 병합·main push 로 «인식된» 명령에서 sha 를 못 뽑음 · 게이트 도구 못 찾음 = deny(병합은 되돌리기 어렵다). 인식 전 단계의 파싱 오류만 통과(+로그).
# 파싱 모듈 = 같은 폴더의 merge_cmd.py (autonomy-merge-guard 와 같은 규칙). ★설치는 이 범위 밖 — 설치 카드★
set +e
INPUT=$(cat 2>/dev/null); [ -n "$INPUT" ] || exit 0
export INPUT MHG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 - <<'PYEOF'
import json, os, re, subprocess, sys, time
sys.path.insert(0, os.environ["MHG_DIR"])
import merge_cmd as mc

LOG = os.environ.get("FT_MERGE_GATE_HOOK_LOG") or os.path.expanduser("~/.claude/logs/merge-head-gate.log")
LAND = "main 병합은 `ft-merge-land.sh <PR번호> --approve-sha <PR head sha>` 로만(gh pr merge·병합 버튼 금지 · 판정 1875) — 검사한 트리 == main 에 놓이는 트리를 git 서버가 보장한다."

def note(msg):
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%dT%H:%M:%S") + f" merge-head-gate: {msg}\n")
    except OSError:
        pass

def byz_root(cwd):
    root = os.environ.get("FT_ROOT")
    if not root:
        p = subprocess.run(["git", "-C", cwd, "rev-parse", "--path-format=absolute", "--git-common-dir"], capture_output=True, text=True, timeout=5)
        root = os.path.dirname(p.stdout.strip()) if p.returncode == 0 and p.stdout.strip() else ""
    return root if root and os.path.isdir(os.path.join(root, ".fable-team")) else ""

def gate_sh(root):
    c = [os.environ.get("FT_MERGE_GATE_SH") or "", os.path.join(root, ".fable-team/bin/ft-merge-gate.sh"), os.path.join(root, "scripts/fable-team-bin/ft-merge-gate.sh")]
    return next((x for x in c if x and os.path.isfile(x)), None)

class Hook:
    def __init__(self, root, cwd):
        self.root, self.cwd, self.why = root, cwd, ""

    def git(self, *a):
        p = subprocess.run(["git", "-C", self.cwd, *a], capture_output=True, text=True, timeout=5)
        return p.stdout.strip() if p.returncode == 0 else ""

    def check_push(self, src, dst, forced):
        if forced or not src:
            self.why = "main 향 force·+refspec·삭제 push 금지 — " + LAND; return True
        sha = self.git("rev-parse", "--verify", "-q", src + "^{commit}")
        if not re.fullmatch(r"[0-9a-f]{40}", sha):
            self.why = "main push 의 보내는 쪽(%s)에서 sha 를 못 뽑음 — 병합은 deny. " % src + LAND; return True
        sh = gate_sh(self.root)
        if not sh:
            self.why = "ft-merge-gate.sh 를 못 찾아 main push 를 막았다(되돌리기 어려움) — 도구 경로를 고친 뒤 다시"; return True
        try:
            p = subprocess.run(["bash", sh, sha, "--repo", self.cwd], capture_output=True, text=True, timeout=60)
        except subprocess.SubprocessError:
            self.why = "ft-merge-gate.sh 실행 실패(시간 초과) — main push deny"; return True
        if p.returncode != 0:
            self.why = (p.stdout.strip() or p.stderr.strip() or "게이트 거절")[:600] + " · " + LAND; return True
        note("ALLOW push sha=%s repo=%s %s" % (sha, os.path.basename(self.root), p.stdout.strip()[:200]))
        return False

    def denied(self, cmd, depth=0):
        for words in mc.simple_commands(cmd):
            prog, args = mc.resolve(words)
            if prog == "cd" and args:
                self.cwd = os.path.normpath(os.path.join(self.cwd, args[0]))
            elif prog == "-c" and depth < 3 and args and self.denied(args[0], depth + 1):
                return True
            elif prog in ("gh", "ft-gh-as-tank.sh"):
                if "--help" in args or "-h" in args:  # 도움말은 병합이 아니다
                    continue
                if any(args[i:i + 2] == ["pr", "merge"] for i in range(len(args))) or ("api" in args and any(re.search(r"/pulls/[0-9]+/merge$", a) for a in args)):
                    self.why = LAND; return True
            elif prog == "git":
                a, i = list(args), 0
                while i < len(a) and a[i].startswith("-"):
                    if a[i] == "-C" and i + 1 < len(a):
                        self.cwd = os.path.normpath(os.path.join(self.cwd, a[i + 1]))
                    i += 2 if a[i] in ("-C", "-c") else 1
                if a[i:i + 1] == ["push"]:
                    specs, bad = mc.main_pushes(a[i + 1:], self.git("symbolic-ref", "--short", "HEAD"))
                    if bad:
                        self.why = bad + " 는 main 병합 경로에서 금지 — " + LAND; return True
                    if any(self.check_push(*s) for s in specs):
                        return True
        return False

try:
    d = json.loads(os.environ["INPUT"])
    cmd = (d.get("tool_input") or {}).get("command") or ""
    if d.get("tool_name") != "Bash" or not re.search(r"merge|push", cmd):
        sys.exit(0)
    cwd = d.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    root = byz_root(cwd)
    if not root:
        sys.exit(0)
    hook = Hook(root, cwd)
    hit = hook.denied(cmd)
except (ValueError, OSError, AttributeError, subprocess.SubprocessError) as e:
    note(f"{type(e).__name__} {e} — 인식 전 단계 파싱 오류: 허용(+로그)")
    sys.exit(0)
if hit:
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": hook.why}}, ensure_ascii=False))
PYEOF
exit 0
