#!/usr/bin/env python3
"""press_evidence_verify.py — r1230 press 증거 묶음 판정 (판정 2946 · 오빠 «테스트 bts poller 없이는 배포없다»).
  팩 harness/bin 과 BYZ scripts/ci 가 «바이트 같은» 한 파일(시험이 cmp 로 대조) · 읽기 전용 판정만 — 묶음 만들기·착지 쪽 push 는 팩 press_evidence_land.py.
  deploy : 배포 직전 검사(cd-dev·cd-prod) — 배포 커밋 C 의 배포 경로 트리 == 어떤 «통과» 묶음 세트 E 의 배포 경로 트리(문서 면제 0 · D8)
           · 미상환 빚(refs/press-debt/<착지> 중 C 의 조상 ∧ refs/press-debt-paid 없음)이면 그 빚 착지를 조상으로 가진 세트의 묶음이어야
  묶음 = 커밋 1개(부모 = 세트 E · 트리 = meta.txt·poller_dom.jsonl·table.md·turbopack.txt) · ref = refs/press/<E>-<run_id>(원격 · 머신 무관)
  배포 경로 = 그 트리의 .github/workflows/cd-dev.yml paths-filter 합집합(못 읽으면 판정 불가 = 거절 · D1)
  외부 호출 = fetch 7 s + 재시도 1(실패 = 판정 불가 1줄). rc 0 통과 · 1 거절 · 2 사용법.
"""
import argparse
import json
import re
import subprocess
import sys

WORKFLOW = ".github/workflows/cd-dev.yml"
POLLER_KEYS = ("axis", "epoch_ms")   # 실 poller_dom.jsonl 공통 칸(arch#190 질문 #211296)
AXES = ("아키텍처 문서", "코드", "로그", "화면")
FILES = ("meta.txt", "poller_dom.jsonl", "table.md", "turbopack.txt")
NS = ("refs/press", "refs/press-debt", "refs/press-debt-paid")
SHA = re.compile(r"^[0-9a-f]{40}$")


class Reject(Exception):
    pass


def run(repo, *a, inp=None):
    p = subprocess.run(["git", "-C", repo, *a], input=inp, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return p.returncode, p.stdout


def git(repo, *a, inp=None):
    rc, out = run(repo, *a, inp=inp)
    if rc:
        raise Reject("판정 불가: git %s rc=%d" % (" ".join(a[:2]), rc))
    return out


def net(repo, *a):   # 7 s + 재시도 1 — 실패 = 판정 불가(하드 룰 20)
    err = ""
    for _ in (1, 2):
        try:
            p = subprocess.run(["git", "-c", "gc.auto=0", "-C", repo, *a], capture_output=True, text=True, timeout=7)
            if p.returncode == 0:
                return
            err = (p.stderr.strip().splitlines() or [""])[-1][:160]
        except subprocess.TimeoutExpired:
            err = "7 s 초과"
    raise Reject("판정 불가: git %s 실패(7 s + 재시도 1) %s" % (a[0], err))


def fetch_refs(repo, remote):   # --prune: 원격에 없는 묶음·빚 ref 는 로컬에서도 지운다(로컬만 만든 묶음 = 통과 0)
    net(repo, "fetch", "--quiet", "--prune", remote, *["+%s/*:%s/*" % (n, n) for n in NS])


def patterns(repo, rev):   # cd-dev.yml «filters: |» 블록의 «- '<글롭>'» 합집합
    rc, txt = run(repo, "show", "%s:%s" % (rev, WORKFLOW))
    out, ind = set(), None
    for line in txt.splitlines() if rc == 0 else []:
        s, lead = line.strip(), len(line) - len(line.lstrip())
        if re.match(r"filters:\s*\|", s):
            ind = lead
        elif ind is not None and s and not s.startswith("#"):
            m = re.match(r"-\s*['\"]?([^'\"#\s]+)", s) if lead > ind else None
            ind = ind if lead > ind else None
            out.update([m.group(1)] if m else [])
    return out


def specs_of(repo, *revs):   # 첫 rev(검사 트리)의 표가 비면 판정 불가 · 나머지 rev 표는 합집합으로 더한다
    if not patterns(repo, revs[0]):
        raise Reject("판정 불가: 배포 경로 표 없음(%s:%s paths-filter)" % (revs[0][:10], WORKFLOW))
    return [":(glob)" + p for p in sorted(set().union(*(patterns(repo, r) for r in revs)))]


def same(repo, a, b, specs):   # 배포 경로 트리가 같은가(D3)
    rc, _ = run(repo, "diff", "--quiet", a, b, "--", *specs)
    if rc > 1:
        raise Reject("판정 불가: git diff rc=%d" % rc)
    return rc == 0


def anc(repo, a, b):
    return run(repo, "merge-base", "--is-ancestor", a, b)[0] == 0


def refs(repo, ns):
    out = git(repo, "for-each-ref", "--format=%(refname) %(objectname)", ns + "/")
    return dict(row.split() for row in out.splitlines() if row.strip())


def check_poller(run_id, text):   # 줄마다 JSON 객체 + 필수 칸 · run_id 칸이 있는 줄은 전부 묶음 run_id · 1줄 이상(D5)
    rows, tagged = [r for r in text.splitlines() if r.strip()], 0
    if not rows:
        raise Reject("poller_dom.jsonl 줄 0")
    for i, row in enumerate(rows, 1):
        try:
            d = json.loads(row)
        except ValueError:
            raise Reject("poller %d줄 JSON 아님" % i)
        if not isinstance(d, dict) or any(d.get(k) in (None, "") for k in POLLER_KEYS):
            raise Reject("poller %d줄 필수 칸(%s) 빔" % (i, "·".join(POLLER_KEYS)))
        if "run_id" in d and d["run_id"] != run_id:
            raise Reject("poller %d줄 run_id %s ≠ 묶음 %s" % (i, d["run_id"], run_id))
        tagged += "run_id" in d
    if not tagged:
        raise Reject("poller run_id 줄 0(묶음 run_id 결속 없음)")


def check_table(run_id, text):   # ft-press-gate ⑧ 과 같은 규칙(표머리·네 축·사실·시간 · 빈 값·-·TODO·? 거절) + 표 머리 run_id
    m = re.search(r"^\s*[-*]?\s*run_id\s*[:=]\s*`?([^`\s]+)`?\s*$", text, re.M)
    if not m or m.group(1) != run_id:
        raise Reject("4자 표 머리 run_id %s ≠ 묶음 %s" % (m.group(1) if m else "없음", run_id))
    hdr, seen, bad = False, set(), set()
    for row in text.splitlines():
        c = [x.strip() for x in row.split("|")]
        hdr = hdr or c[1:4] == ["축", "사실", "시간"]
        if len(c) > 1 and c[1] in AXES:
            seen.add(c[1])
            bad.update([c[1]] if len(c) < 4 or any(v in ("", "-", "TODO", "?") for v in c[2:4]) else [])
    miss = ([] if hdr else ["표머리"]) + [a for a in AXES if a not in seen or a in bad]
    if miss:
        raise Reject("4자 표 칸 빔: " + " / ".join(miss))


def check_turbopack(text):   # get_errors 원문(SSE «data:» 줄 또는 JSON) → (build, runtime, config) 건수 · 원문 없음 = 거절(D9)
    for s in [r.strip()[5:] if r.strip().startswith("data:") else r for r in text.splitlines()] + [text]:
        try:
            inner = json.loads(json.loads(s)["result"]["content"][0]["text"])
        except (ValueError, KeyError, IndexError, TypeError):
            continue
        if isinstance(inner, dict) and "error" in inner:
            raise Reject("turbopack 원문 오류: %s" % str(inner["error"])[:80])
        cfg, ses = (inner.get("configErrors"), inner.get("sessionErrors")) if isinstance(inner, dict) else (None, None)
        if isinstance(cfg, list) and isinstance(ses, list):
            ses = [x for x in ses if isinstance(x, dict)]
            return sum(1 for x in ses if x.get("buildError")), sum(len(x.get("runtimeErrors") or []) for x in ses), len(cfg)
    raise Reject("turbopack 원문 없음(get_errors 응답의 configErrors·sessionErrors 칸 0)")


def check_content(run_id, poller, table, tp):
    check_poller(run_id, poller)
    check_table(run_id, table)
    return check_turbopack(tp)


def bundle(repo, ref, commit):   # 묶음 1개 결속(meta 세트 = 부모 = ref 이름 · run_id = ref 꼬리) + 칸 검사 → dict · 틀리면 Reject
    par, txt = git(repo, "rev-list", "--parents", "-n1", commit).split()[1:], {}
    for f in FILES:
        rc, txt[f] = run(repo, "show", "%s:%s" % (commit, f))
        if rc:
            raise Reject("%s 없음(%s)" % (f, ref))
    meta = dict(row.split("=", 1) for row in txt["meta.txt"].splitlines() if "=" in row)
    s, rid = meta.get("set", ""), meta.get("run_id", "")
    if len(par) != 1 or s != par[0] or ref != "refs/press/%s-%s" % (s, rid):
        raise Reject("meta 세트·run_id ≠ 묶음 부모·ref 이름(%s)" % ref)
    tp = check_content(rid, txt["poller_dom.jsonl"], txt["table.md"], txt["turbopack.txt"])
    return {"ref": ref, "commit": commit, "set": s, "run": rid, "tp": tp}


def pick(repo, target, specs):   # 배포 경로 트리가 target 과 같은 세트의 «통과» 묶음들 + 첫 거절 사유
    good, why, n = [], "", 0
    for ref, c in sorted(refs(repo, "refs/press").items()):
        n += 1
        if not same(repo, git(repo, "rev-parse", c + "^").strip(), target, specs):
            continue
        try:
            good.append(bundle(repo, ref, c))
        except Reject as r:
            why = why or str(r)
    return good, why or "묶음 없음(배포 경로 트리가 같은 세트의 refs/press/* 0 · 검사 %d개)" % n


def unpaid(repo, upto):   # 빚 착지가 upto 의 조상(main 위)인데 상환 ref 없음 — 착지 못 한 빚 ref 는 조상 아님 = 무시
    paid = {r.rsplit("/", 1)[1] for r in refs(repo, "refs/press-debt-paid")}
    debts = (r.rsplit("/", 1)[1] for r in refs(repo, "refs/press-debt"))
    return [d for d in debts if SHA.match(d) and d not in paid and anc(repo, d, upto)]


def debt_line(repo, d):
    kv = dict(re.findall(r"(\w+)=(\S+)", git(repo, "log", "-1", "--format=%B", "refs/press-debt/" + d)))
    return "press 빚 PR #%s(착지 %s) — 담당 %s · 복구 뒤 press 1회" % (kv.get("pr", "?"), d[:10], kv.get("owner", "planner"))


def cover(repo, good, debts):   # 빚 착지 전부를 조상으로 가진 세트의 묶음(D7) · 빚 0 이면 첫 묶음
    return next((b for b in good if all(anc(repo, d, b["set"]) for d in debts)), None)


def ok_line(b):
    return "press 증거 OK 세트 %s run %s · ref %s · turbopack build %d runtime %d config %d" % ((b["set"][:10], b["run"], b["ref"]) + b["tp"])


def deploy(a):
    c = git(a.repo, "rev-parse", "--verify", a.commit + "^{commit}").strip()
    specs = specs_of(a.repo, c)
    fetch_refs(a.repo, a.remote)
    good, why = pick(a.repo, c, specs)
    if not good:
        raise Reject("press 증거 없음/틀림: %s — 배포 %s · 판정 2946" % (why, c[:10]))
    debts = unpaid(a.repo, c)
    b = cover(a.repo, good, debts)
    if b is None:
        raise Reject(debt_line(a.repo, debts[0]) + " — 배포 %s · 판정 2946" % c[:10])
    print(ok_line(b) + " · 배포 %s" % c[:10])
    return 0


def main(argv):
    ap = argparse.ArgumentParser(prog="press_evidence_verify.py", description="배포 직전 press 증거 검사(r1230)")
    ap.add_argument("mode", choices=("deploy",))
    ap.add_argument("--commit", required=True)
    ap.add_argument("--repo", default=".")
    ap.add_argument("--remote", default="origin")
    a = ap.parse_args(argv)
    try:
        return deploy(a)
    except Reject as r:
        print(str(r))
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
