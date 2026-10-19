#!/usr/bin/env python3
"""autonomy_scope_classify.py — 오빠 부재 중 사전 승인(R298)의 «세트 종류» 분류기 (설계 DESIGN-r298-away-preapproval-merge §3·§7 · 판정 2055).

  autonomy_scope_classify.py classify <40hex> --repo <dir> [--remote origin] [--target main] --scope S<n>
      `CLASS docs|ff|revert|code` rc0 | `FORBID <사유>` rc3 | `ERROR <사유>` rc1 (못 판단 = 닫힌 쪽 · 호출자 REJECT)
  autonomy_scope_classify.py check-revert --repo <dir> [--remote origin] [--target main] --scope S<n>
      `OK` rc0 | `REVERTED <착지 sha> by <sha>` rc4 | `ERROR <사유>` rc1
diff = merge-base(<remote>/<target>, sha)..sha · 로컬 git 만(호출마다 7초 상한) · 원장 = <state>/autonomy-scope/S<n>.ledger.tsv (6번째 칸 = 착지 sha)."""
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
SCOPE_RE = re.compile(r"^S[0-9]+$")
GIT_TIMEOUT_S = 7
LEDGER_LANDED_COL = 5   # 0 기준 — 승인 시각·sha·PR·종류·판정문·착지 sha·되돌림 명령

# (이름, 정규식) — 옛·새 경로 어느 쪽이든 맞으면 종류와 무관하게 FORBID
PATH_RULES = [(n, re.compile(rx, re.I)) for n, rx in [
    ("DDL", r"(^|/)migrations/|\.sql$|^alembic/"),
    ("배포·인프라", r"^\.github/workflows/|^infra/|^terraform/|cloudbuild|(^|/)Dockerfile|^deploy/|^scripts/deploy"),
    ("키", r"^secrets/|(^|/)[^/]*\.env[^/]*$|\.cred$|credential"),
    ("과금", r"billing|credit|payment|pricing|toss|subscription|^docs/architect/COST_BASE_TABLE\.md$"),
    ("의존", r"(^|/)(package\.json|pyproject\.toml|requirements[^/]*\.txt)$|(^|/)[^/]*[-.]lock[^/]*$"),
    ("전역 규칙", r"(^|/)CLAUDE\.md$|(^|/)\.claude/|COMM-GUIDE|(^|/)harness/kit/|(^|/)scripts/harness-install/"),
]]
DOC_RE = re.compile(r"^(design|docs)/.*\.md$")   # 확장자만으로 문서 판정 0 — design/ 아래 .py·.sh 는 code, 루트 .md 는 docs 아님
SECRET_SHAPE = re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----|\bAKIA[0-9A-Z]{16}\b|\bgh[pousr]_[A-Za-z0-9]{30,}|\bsk-[A-Za-z0-9_-]{20,}|\bxox[abprs]-[A-Za-z0-9-]{10,}")


class Err(Exception):
    pass


def run(repo, args, stdin=None):
    try:
        return subprocess.run(["git", "-C", repo] + args, input=stdin, capture_output=True, text=True,
                              errors="replace", timeout=GIT_TIMEOUT_S)
    except subprocess.TimeoutExpired:
        raise Err("git %s %d초 초과" % (args[0], GIT_TIMEOUT_S))


def git(repo, *args):
    p = run(repo, list(args))
    if p.returncode != 0:
        raise Err("git %s 실패 rc=%d" % (args[0], p.returncode))
    return p.stdout


def parse_raw(out):   # `git diff --raw -z -M` → [(옛 모드, 새 모드, 상태, [경로…])]
    toks, i, rows = out.split("\0"), 0, []
    while i < len(toks) and toks[i].startswith(":"):
        om, nm, _, _, st = toks[i][1:].split(" ")
        n = 2 if st[0] in "RC" else 1
        rows.append((om, nm, st, toks[i + 1:i + 1 + n]))
        i += 1 + n
    if any(toks[i:]):
        raise Err("diff --raw 해석 실패")
    return rows


def path_reason(path):
    for name, rx in PATH_RULES:
        if rx.search(path):
            return "%s 경로: %s" % (name, path)
    return None


def row_reason(row):
    om, nm, st, paths = row
    if st[0] not in "AM":
        return "상태 %s: %s" % (st, " → ".join(paths))   # 삭제·이름 바꾸기·복사·타입 변경
    if (st[0] == "M" and om != nm) or (st[0] == "A" and nm != "100644"):
        return "모드 %s→%s: %s" % (om, nm, paths[0])
    return next(filter(None, map(path_reason, paths)), None)


def added_text(repo, base, sha):
    out = git(repo, "diff", "--no-color", "--no-renames", "-U0", base, sha)
    return "\n".join(ln[1:] for ln in out.split("\n") if ln.startswith("+") and not re.match(r"^\+\+\+ (b/|/dev/null)", ln))


def secret_reason(text):
    if SECRET_SHAPE.search(text):
        return "추가 줄에 비밀 꼴"
    try:
        import ft_secret_judge
    except SystemExit:
        raise Err("ft_secret_judge 를 불러오지 못함")
    found = ft_secret_judge.plan(text)
    return "추가 줄: " + found[0][1] if found else None


def patch_id(repo, a, b):
    diff = git(repo, "diff", "--no-color", "--no-renames", "-U0", a, b)
    if not diff.strip():
        return ""
    p = run(repo, ["patch-id", "--stable"], stdin=diff)
    if p.returncode != 0 or not p.stdout.split():
        raise Err("patch-id 실패")
    return p.stdout.split()[0]


def state_dir(repo):
    if os.environ.get("FT_AUTONOMY_STATE_DIR"):
        return os.environ["FT_AUTONOMY_STATE_DIR"]
    common = git(repo, "rev-parse", "--path-format=absolute", "--git-common-dir").strip()
    return os.path.join(os.environ.get("FT_ROOT") or os.path.dirname(common), ".fable-team", "state")


def landed_shas(repo, scope):
    path = os.path.join(state_dir(repo), "autonomy-scope", scope + ".ledger.tsv")
    if not os.path.isfile(path):
        return []
    with open(path, encoding="utf-8") as f:
        cols = [line.rstrip("\n").split("\t") for line in f]
    return [c[LEDGER_LANDED_COL] for c in cols if len(c) > LEDGER_LANDED_COL and SHA_RE.match(c[LEDGER_LANDED_COL])]


def is_exact_revert(repo, sha, landed):   # 부모 1개 ∧ 그 diff 의 patch-id == 원장 착지 L 의 역 diff(L → L^) patch-id
    parents = git(repo, "rev-list", "--parents", "-n1", sha).split()[1:]
    if len(parents) != 1 or not landed:
        return False
    want = patch_id(repo, parents[0], sha)
    return bool(want) and any(patch_id(repo, sha_l, sha_l + "^") == want for sha_l in landed)


def classify(repo, remote, target, scope, sha):
    ref = "refs/remotes/%s/%s" % (remote, target)
    git(repo, "rev-parse", "--verify", "-q", ref + "^{commit}")
    git(repo, "rev-parse", "--verify", "-q", sha + "^{commit}")
    if is_exact_revert(repo, sha, landed_shas(repo, scope)):   # revert 판정은 docs 보다 먼저 — 승인 때 불가 범위를 이미 통과한 착지의 정확한 역 diff
        return 0, "CLASS revert"
    base = git(repo, "merge-base", ref, sha).strip()
    rows = parse_raw(git(repo, "diff", "--raw", "-z", "-M", base, sha))
    if not rows:
        raise Err("빈 diff(승인할 변경 없음)")
    why = next(filter(None, map(row_reason, rows)), None) or secret_reason(added_text(repo, base, sha))
    if why:
        return 3, "FORBID " + why
    if not all(DOC_RE.match(r[3][0]) for r in rows):
        return 0, "CLASS code"
    is_ff = run(repo, ["merge-base", "--is-ancestor", ref, sha]).returncode == 0
    return 0, "CLASS ff" if is_ff else "CLASS docs"


def find_reverter(repo, ref, landed):   # 착지 뒤 ref 에 «This reverts commit <L>» 이 든 커밋 → 그 sha
    log = git(repo, "log", "--format=%H%x1f%B%x1e", "%s..%s" % (landed, ref))
    for rec in log.split("\x1e"):
        h, _, body = rec.strip().partition("\x1f")
        if h and "This reverts commit " + landed in body:
            return h
    return ""


def check_revert(repo, remote, target, scope):
    ref = "refs/remotes/%s/%s" % (remote, target)
    git(repo, "rev-parse", "--verify", "-q", ref + "^{commit}")
    for landed in landed_shas(repo, scope):
        git(repo, "rev-parse", "--verify", "-q", landed + "^{commit}")
        by = find_reverter(repo, ref, landed)
        if by:
            return 4, "REVERTED %s by %s" % (landed, by)
    return 0, "OK"


def parse_args(argv):
    if not argv or argv[0] not in ("classify", "check-revert"):
        raise Err("usage: classify <40hex>|check-revert --repo <dir> [--remote r] [--target t] --scope S<n>")
    cmd, rest = argv[0], list(argv[1:])
    sha = rest.pop(0) if cmd == "classify" and rest and not rest[0].startswith("--") else None
    opts = {"--repo": None, "--remote": "origin", "--target": "main", "--scope": None}
    while rest:
        key = rest.pop(0)
        if key not in opts or not rest:
            raise Err("인자 오류: " + key)
        opts[key] = rest.pop(0)
    if not opts["--repo"] or not SCOPE_RE.match(opts["--scope"] or ""):
        raise Err("--repo 와 --scope S<n> 필수")
    if cmd == "classify" and not SHA_RE.match(sha or ""):
        raise Err("<40hex> 필수")
    return cmd, sha, opts["--repo"], opts["--remote"], opts["--target"], opts["--scope"]


def main(argv):
    try:
        cmd, sha, repo, remote, target, scope = parse_args(argv)
        rc, line = classify(repo, remote, target, scope, sha) if cmd == "classify" else check_revert(repo, remote, target, scope)
    except Err as e:
        rc, line = 1, "ERROR %s" % e
    except Exception as e:   # 판정기 내부 오류도 닫힌 쪽(#0 RULE) — 이유는 형 이름뿐
        rc, line = 1, "ERROR 내부 오류 %s" % type(e).__name__
    print(line)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
