#!/usr/bin/env python3
"""autonomy_scope_classify.py — 오빠 부재 중 사전 승인(R298)의 «세트 종류» 분류기 (설계 DESIGN-r298-away-preapproval-merge §3·§7 · 판정 2055).

  autonomy_scope_classify.py classify <40hex> --repo <dir> [--remote origin] [--target main] --scope S<n>
        [--table <분류표.tsv>] [--ddl-records <기록표.tsv>] [--learned <키,…>]
      `CLASS docs|ff|revert|code[ kind=<키,…> learned]` rc0 | `FORBID kind=<키> <사유>` rc3 | `ERROR <사유>` rc1 (못 판단 = 닫힌 쪽 · 호출자 REJECT)
  autonomy_scope_classify.py check-revert --repo <dir> [--remote origin] [--target main] --scope S<n>
      `OK` rc0 | `REVERTED <착지 sha> by <sha>` rc4 | `ERROR <사유>` rc1
diff = merge-base(<remote>/<target>, sha)..sha · 로컬 git 만(호출마다 7초 상한) · 원장 = <state>/autonomy-scope/S<n>.ledger.tsv (6번째 칸 = 착지 sha).
r466: 분류표(기본 BYZ 내장 · 팩 표 파일) · 카드 폴더 이동(R100 · 파일 이름 같음 · 양쪽 docs) = docs · 적용 기록 있는 새 *.sql(그 밖 docs 만) = docs ·
      FORBID 마다 종류 키 · --learned 의 키(오빠 승인 1회로 저장된 종류 · secret 제외)는 docs 로 통과시키고 `kind=… learned` 를 붙인다."""
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import autonomy_scope_rules as rules  # noqa: E402
import autonomy_scope_secret as secret_lines  # noqa: E402

SHA_RE = re.compile(r"^[0-9a-f]{40}$")
SCOPE_RE = re.compile(r"^S[0-9]+$")
GIT_TIMEOUT_S = 7
LEDGER_LANDED_COL = 5   # 0 기준 — 승인 시각·sha·PR·종류·판정문·착지 sha·되돌림 명령


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


def show_at(repo, sha):   # sha 트리의 파일 본문(없으면 "")
    return lambda path: run(repo, ["show", "%s:%s" % (sha, path)]).stdout


def classify(repo, remote, target, scope, sha, table=None, records=None, learned=()):
    ref = "refs/remotes/%s/%s" % (remote, target)
    git(repo, "rev-parse", "--verify", "-q", ref + "^{commit}")
    git(repo, "rev-parse", "--verify", "-q", sha + "^{commit}")
    if is_exact_revert(repo, sha, landed_shas(repo, scope)):   # revert 판정은 docs 보다 먼저 — 승인 때 불가 범위를 이미 통과한 착지의 정확한 역 diff
        return 0, "CLASS revert"
    base = git(repo, "merge-base", ref, sha).strip()
    rows = parse_raw(git(repo, "diff", "--raw", "-z", "-M", base, sha))
    if not rows:
        raise Err("빈 diff(승인할 변경 없음)")
    blocks = secret_lines.parse_added(git, repo, base, sha)   # diff 상태 기계(파일마다 git 호출 0) · added = ddl 기록 대조용 전문
    added = "\n".join(t for _p, items, _n in blocks for _no, t in items)
    ddl_ok = lambda p: rules.ddl_recorded(records or [], p, added, show_at(repo, sha))  # noqa: E731
    full = secret_lines.read_new(repo, sha, [p for p, _i, _n in blocks if p and rules.ENV_TEMPLATE.search(p)])   # .env 견본 = 바뀐 뒤 전문(따옴표 값 «안» 줄 판별 · 칸 3)
    env_ok = lambda p: rules.env_added_values_ok(full.get(p), [(n, t) for q, items, _n in blocks if q == p for n, t in items])  # noqa: E731
    table = table or rules.BYZ_TABLE   # D+A 짝 맞추기(카드 이동)를 먼저 · 판정은 행마다
    judged = [rules.judge_row(table, r, ddl_ok, env_ok) for r in rules.pair_card_moves(table, rows)]
    secret = secret_lines.reason(blocks, lambda p: rules.path_class(table, p), repo, sha)   # code 전문 · 문서는 실행 줄만(r559)
    if secret:
        judged.append(("forbid", "secret", secret))
    used = rules.apply_learned(judged, learned)
    hit = next(((k, w) for c, k, w in judged if c == "forbid"), None)
    if hit:
        return 3, "FORBID kind=%s %s" % hit
    if any(k == "ddl-recorded" for _, k, _ in judged) and any(c != "docs" for c, _, _ in judged):
        return 3, "FORBID kind=ddl DDL 기록 PR 에 문서 밖 변경"
    tail = " kind=%s learned" % ",".join(used) if used else ""
    if any(c != "docs" for c, _, _ in judged):
        return 0, "CLASS code" + tail
    is_ff = run(repo, ["merge-base", "--is-ancestor", ref, sha]).returncode == 0
    return 0, ("CLASS ff" if is_ff else "CLASS docs") + tail


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
        raise Err("usage: classify <40hex>|check-revert --repo <dir> [--remote r] [--target t] --scope S<n> [--table f] [--ddl-records f] [--learned k,…]")
    cmd, rest = argv[0], list(argv[1:])
    sha = rest.pop(0) if cmd == "classify" and rest and not rest[0].startswith("--") else None
    opts = {"--repo": None, "--remote": "origin", "--target": "main", "--scope": None, "--table": None, "--ddl-records": None, "--learned": ""}
    while rest:
        key = rest.pop(0)
        if key not in opts or not rest:
            raise Err("인자 오류: " + key)
        opts[key] = rest.pop(0)
    if not opts["--repo"] or not SCOPE_RE.match(opts["--scope"] or ""):
        raise Err("--repo 와 --scope S<n> 필수")
    if cmd == "classify" and not SHA_RE.match(sha or ""):
        raise Err("<40hex> 필수")
    learned = tuple(k for k in (opts["--learned"] or "").split(",") if k)
    if not all(rules.KIND_RE.match(k) for k in learned):
        raise Err("--learned 키 꼴 틀림")
    return cmd, sha, opts, learned


def main(argv):
    try:
        cmd, sha, o, learned = parse_args(argv)
        repo, remote, target, scope = o["--repo"], o["--remote"], o["--target"], o["--scope"]
        if cmd == "classify":
            table, records = rules.load_table(o["--table"]), rules.load_ddl_records(o["--ddl-records"])
            rc, line = classify(repo, remote, target, scope, sha, table, records, learned)
        else:
            rc, line = check_revert(repo, remote, target, scope)
    except (Err, rules.TableErr, secret_lines.ImportErr, OSError) as e:
        rc, line = 1, "ERROR %s" % e
    except Exception as e:   # 판정기 내부 오류도 닫힌 쪽(#0 RULE) — 이유는 형 이름뿐
        rc, line = 1, "ERROR 내부 오류 %s" % type(e).__name__
    print(line)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
