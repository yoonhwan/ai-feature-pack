#!/usr/bin/env python3
"""press_evidence_land.py — r1230 착지 쪽(판정 2946) · 판정 함수는 press_evidence_verify.py 하나(BYZ scripts/ci 와 바이트 같음)를 import.
  land : ft-merge-land 가 부른다 — 대상 = 착지 리포의 remote URL(날 값·확장 값)이 SecondWindStudio/byz-agents(CROSS 무관 · D2) 일 때만
         · 배포 경로 변경 0 = 대상 밖 · PR 전체 변경이 main 위 착지 하나의 정확 역 diff = 면제 + 빚 ref push(D6·D7)
         · 그 밖 = 배포 경로 트리가 같은 «통과» 묶음 필수 · 미상환 빚이면 빚 착지를 조상으로 가진 세트여야 + 상환 ref push
  pack : 묶음 커밋(부모 = 세트) → push refs/press/<세트>-<run_id> · 같은 칸 검사를 먼저(틀린 묶음은 만들지 않는다)
  debt : 미상환 빚 목록
  stdout(land 통과) = 사람 1줄 + 기록 토큰 1줄(press=out|ok:<세트10>:<run>|revert:<sha10>) · 대상 밖 리포 = 출력 0 · 거절 = 1줄 rc1.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from press_evidence_verify import (Reject, check_content, cover, debt_line, fetch_refs, git, net, ok_line,  # noqa: E402
                                   pick, run, same, specs_of, unpaid)

BYZ_SLUG = "secondwindstudio/byz-agents"


def byz_repo(repo, remote):
    urls = []
    for a in (("config", "--get-all", "remote.%s.url" % remote), ("config", "--get-all", "remote.%s.pushurl" % remote),
              ("remote", "get-url", "--all", remote), ("remote", "get-url", "--push", "--all", remote)):
        urls += run(repo, *a)[1].split()
    found = (re.search(r"github\.com[:/]+([^/]+/[^/]+?)(?:\.git)?/?$", u) for u in urls)
    return any(m and m.group(1).lower() == BYZ_SLUG for m in found)


def pid(repo, a, b):
    return run(repo, "patch-id", "--stable", inp=git(repo, "diff", "--no-renames", a, b))[1].split()[:1]


def exact_revert(repo, main, head, hint):   # 후보 = 제목·본문 힌트 sha + main 첫 부모 200 · 바뀐 파일 묶음이 같을 때만 patch-id 대조(제목은 참고)
    base = git(repo, "merge-base", main, head).strip()
    want, files = pid(repo, base, head), set(git(repo, "diff", "--no-renames", "--name-only", base, head).split())
    log = git(repo, "log", "--first-parent", "--no-merges", "-n", "200", "--no-renames", "--format=@%H", "--name-only", main)
    cand = {}
    for h in re.findall(r"\b[0-9a-f]{7,40}\b", hint or ""):
        rc, out = run(repo, "rev-parse", "--verify", "-q", h + "^{commit}")
        if rc == 0 and run(repo, "merge-base", "--is-ancestor", out.strip(), main)[0] == 0:
            cand[out.strip()] = set(run(repo, "diff", "--no-renames", "--name-only", out.strip() + "^", out.strip())[1].split())
    for chunk in log.split("@")[1:]:
        h, *names = chunk.split()
        cand.setdefault(h, set(names))
    for h, names in cand.items():
        if want and names == files and run(repo, "rev-parse", "-q", "--verify", h + "^")[0] == 0 and pid(repo, h, h + "^") == want:
            return h
    return None


def owner(root, title):   # 빚 담당 = PR 제목 «[팀]» 명부 _master · 없으면 planner 명부 _master · 둘 다 없으면 planner
    m = re.match(r"\s*\[([a-z0-9-]+)\]", title or "")
    for team in ([m.group(1)] if m else []) + ["planner"]:
        try:
            with open(os.path.join(root or ".", ".fable-team", "seats-%s.json" % team), encoding="utf-8") as f:
                v = json.load(f).get("_master")
        except (OSError, ValueError, AttributeError):
            v = None
        if isinstance(v, str) and v:
            return v
    return "planner"


def commit_tree(repo, tree, msg, parent=None):
    env = dict(os.environ)
    for k, v in (("NAME", "ft-press-evidence"), ("EMAIL", "ft-press-evidence@local")):
        env.setdefault("GIT_AUTHOR_" + k, v)
        env.setdefault("GIT_COMMITTER_" + k, v)
    p = subprocess.run(["git", "-C", repo, "commit-tree", tree, "-m", msg] + (["-p", parent] if parent else []),
                       capture_output=True, text=True, env=env)
    if p.returncode:
        raise Reject("판정 불가: commit-tree rc=%d" % p.returncode)
    return p.stdout.strip()


def land(a):
    if not byz_repo(a.repo, a.remote):
        return 0
    specs = specs_of(a.repo, a.head, a.main)
    if same(a.repo, a.main, a.head, specs):
        print("press 증거 대상 밖(배포 경로 변경 0)\npress=out")
        return 0
    fetch_refs(a.repo, a.remote)
    rv = exact_revert(a.repo, a.main, a.head, "%s %s" % (a.title, a.body))
    if rv:
        who = owner(a.root, a.title)
        msg = "press-debt landed=%s pr=%s reverted=%s owner=%s ts=%s" % (a.landing, a.pr, rv, who, time.strftime("%Y-%m-%dT%H:%M:%S"))
        net(a.repo, "push", a.remote, "%s:refs/press-debt/%s" % (commit_tree(a.repo, git(a.repo, "mktree", inp="").strip(), msg), a.landing))
        print("press 증거 면제 — 정확 역변경(되돌린 %s) · 빚 refs/press-debt/%s · 담당 %s · 복구 뒤 press 1회\npress=revert:%s"
              % (rv[:10], a.landing[:10], who, rv[:10]))
        return 0
    good, why = pick(a.repo, a.head, specs)
    if not good:
        raise Reject("press 증거 없음/틀림: %s — 판정 2946" % why)
    debts = unpaid(a.repo, a.main)
    b = cover(a.repo, good, debts)
    if b is None:
        raise Reject(debt_line(a.repo, debts[0]) + " — 판정 2946")
    for d in debts:   # 상환 = 갚은 묶음 커밋을 가리키는 원격 ref(D7 · 머신 무관)
        net(a.repo, "push", a.remote, "%s:refs/press-debt-paid/%s" % (b["commit"], d))
    print(ok_line(b) + (" · 빚 상환 %d" % len(debts) if debts else "") + "\npress=ok:%s:%s" % (b["set"][:10], b["run"]))
    return 0


def pack(a):
    if not re.match(r"^[A-Za-z0-9._-]{1,80}$", a.run) or ".." in a.run or a.run.endswith(".lock"):
        raise Reject("run_id 꼴 아님(영숫자·._- 80자 · ..·.lock 0): %s" % a.run)
    e = git(a.repo, "rev-parse", "--verify", a.set + "^{commit}").strip()
    src = {"poller_dom.jsonl": a.poller, "table.md": a.table, "turbopack.txt": a.turbopack}
    try:
        txt = {}
        for k, v in src.items():
            with open(v, encoding="utf-8", errors="replace") as f:
                txt[k] = f.read()
    except OSError as x:
        raise Reject("증거 파일 못 읽음: %s" % x)
    check_content(a.run, txt["poller_dom.jsonl"], txt["table.md"], txt["turbopack.txt"])
    meta = "set=%s\nrun_id=%s\nseat=%s\nts=%s\n" % (e, a.run, a.seat, time.strftime("%Y-%m-%dT%H:%M:%S"))
    blob = {k: git(a.repo, "hash-object", "-w", os.path.abspath(v)).strip() for k, v in src.items()}
    blob["meta.txt"] = git(a.repo, "hash-object", "-w", "--stdin", inp=meta).strip()
    tree = git(a.repo, "mktree", inp="".join("100644 blob %s\t%s\n" % (blob[f], f) for f in sorted(blob))).strip()
    c, ref = commit_tree(a.repo, tree, "press evidence set=%s run=%s" % (e, a.run), e), "refs/press/%s-%s" % (e, a.run)
    net(a.repo, "push", a.remote, "%s:%s" % (c, ref))
    git(a.repo, "update-ref", ref, c)
    print("PACKED ref=%s commit=%s" % (ref, c))
    return 0


def debt(a):
    fetch_refs(a.repo, a.remote)
    ds = unpaid(a.repo, git(a.repo, "rev-parse", "--verify", a.main + "^{commit}").strip())
    print("\n".join(debt_line(a.repo, d) for d in ds) or "press 빚 0")
    return 0


def main(argv):
    ap = argparse.ArgumentParser(prog="press_evidence_land.py")
    ap.add_argument("mode", choices=("land", "pack", "debt"))
    dflt = {"repo": ".", "remote": "origin", "main": "origin/main", "seat": "unknown", "title": "", "body": "", "root": ""}
    for k in ("repo", "remote", "main", "head", "landing", "pr", "title", "body", "root", "set", "run", "poller", "table", "turbopack", "seat"):
        ap.add_argument("--" + k, default=dflt.get(k))
    a = ap.parse_args(argv)
    need = {"land": ("head", "landing", "pr"), "pack": ("set", "run", "poller", "table", "turbopack")}
    if any(getattr(a, k) is None for k in need.get(a.mode, ())):
        ap.print_usage(sys.stderr)
        return 2
    try:
        return {"land": land, "pack": pack, "debt": debt}[a.mode](a)
    except Reject as r:
        print(str(r))
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
