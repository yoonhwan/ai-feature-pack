#!/usr/bin/env python3
"""press_evidence_verify.py — r1230 press 증거 묶음 판정 (판정 2946 · 오빠 «테스트 bts poller 없이는 배포없다»).
  팩 harness/bin 과 BYZ scripts/ci 가 «바이트 같은» 한 파일(시험이 cmp 로 대조) · 읽기 전용 판정만 — 묶음 만들기·착지 쪽 push 는 팩 press_evidence_land.py.
  deploy : 배포 직전 검사(cd-dev·cd-prod) — 배포 커밋 C 의 배포 경로 트리 == 어떤 «통과» 묶음 세트 E 의 배포 경로 트리(문서 면제 0 · D8)
           · 미상환 빚(refs/press-debt/<착지> 중 C 의 조상 ∧ refs/press-debt-paid 없음)이면 그 빚 착지를 조상으로 가진 세트의 묶음이어야
  묶음 = 커밋 1개(부모 = 세트 E · 트리 = meta.txt·poller_dom.jsonl·table.md·turbopack.txt) · ref = refs/press/<E>-<run_id>(원격 · 머신 무관)
  음성 경로(r1274) = 그 트리의 docs/rules/press_voice_paths.md «## 목록» 절 글롭(없음·빈 목록·꼴 틀림 = 판정 불가 = 거절 · D1) · env FT_PRESS_SCOPE=deploy = 옛 cd-dev.yml paths-filter 합집합
  외부 호출 = fetch 7 s + 재시도 1(실패 = 판정 불가 1줄) · push = min(고정비 9 + 7, 70) s + 재시도 1 + 끊긴 뒤 ls-remote 확인(r1254). rc 0 통과 · 1 거절 · 2 사용법.
"""
import argparse
import json
import os
import re
import subprocess
import sys

WORKFLOW = ".github/workflows/cd-dev.yml"
VOICE_LIST = "docs/rules/press_voice_paths.md"   # r1274 BYZ 정본 음성 경로 목록(바꾸는 법 = 문서 PR)
VOICE_GLOB = re.compile(r"^- `([^\s`]+)`$")
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


def once(repo, secs, *a):   # git 네트워크 1회 → (성공 여부, 마지막 오류 줄)
    try:
        p = subprocess.run(["git", "-c", "gc.auto=0", "-C", repo, *a], capture_output=True, text=True, timeout=secs)
    except subprocess.TimeoutExpired:
        return False, "%g s 초과" % secs
    return p.returncode == 0, (p.stderr.strip().splitlines() or [""])[-1][:160]


def net(repo, *a):   # 7 s + 재시도 1 — 실패 = 판정 불가(하드 룰 20)
    err = ""
    for _ in (1, 2):
        ok, err = once(repo, 7, *a)
        if ok:
            return
    raise Reject("판정 불가: git %s 실패(7 s + 재시도 1) %s" % (a[0], err))


def push_sec(parts=1):   # push = 쪼갤 수 없는 배치(하드 룰 12): min(고정비 + 7 × 조각 수, 70) · 고정비 = 원격 ref 광고 실측 8.56 s 올림 9 · FT_PRESS_PUSH_SEC 는 시험만
    fixed = float(os.environ.get("FT_PRESS_PUSH_FIXED", "9"))
    return float(os.environ.get("FT_PRESS_PUSH_SEC") or min(fixed + 7 * parts, 70))


def remote_sha(repo, remote, ref):   # 원격 ref 가 지금 가리키는 sha · 없음·확인 실패 = None
    try:
        p = subprocess.run(["git", "-c", "gc.auto=0", "-C", repo, "ls-remote", remote, ref], capture_output=True, text=True, timeout=7)
    except subprocess.TimeoutExpired:
        return None
    rows = [r.split() for r in p.stdout.splitlines()] if p.returncode == 0 else []
    return next((r[0] for r in rows if r[1:] == [ref]), None)


def push(repo, remote, sha, ref, parts=1):   # 끊긴 뒤의 정본 = «원격에 그 ref 가 그 sha 로 있나» (서버는 받았는데 손님만 끊긴 꼴) · 다른 sha 는 덮어쓰지 않는다
    secs, err = push_sec(parts), ""
    for _ in (1, 2):
        ok, err = once(repo, secs, "push", remote, "%s:%s" % (sha, ref))
        if ok:
            return
        now = remote_sha(repo, remote, ref)
        if now == sha:
            print("INFO push 끊김 · 원격에 있음 · 성공으로 셈 %s" % ref, file=sys.stderr)
            return
        if now:
            raise Reject("판정 불가: 원격 %s 가 다른 sha(%s) — 사람 판정" % (ref, now[:10]))
    raise Reject("판정 불가: git push 실패(%g s + 재시도 1 · 원격 확인 0) %s" % (secs, err))


def fetch_refs(repo, remote):   # --prune: 원격에 없는 묶음·빚 ref 는 로컬에서도 지운다(로컬만 만든 묶음 = 통과 0)
    net(repo, "fetch", "--quiet", "--prune", remote, *["+%s/*:%s/*" % (n, n) for n in NS])


def patterns(repo, rev):   # r1274: rev 트리의 BYZ 정본 음성 경로 목록 «## 목록» 절 · «- `<글롭>`» 줄만(빈 줄·한 줄 <!-- --> 만 건너뜀 · 다른 줄 = 판정 불가) · FT_PRESS_SCOPE=deploy = 옛 cd-dev.yml 범위
    if os.environ.get("FT_PRESS_SCOPE") == "deploy":
        return deploy_patterns(repo, rev)
    rc, txt = run(repo, "show", "%s:%s" % (rev, VOICE_LIST))
    out, ins = set(), False
    for n, line in enumerate(txt.splitlines() if rc == 0 else [], 1):
        s = line.rstrip()
        ins = (s == "## 목록") if s.startswith("## ") else ins
        m = VOICE_GLOB.match(s)
        if ins and s and not s.startswith("## ") and not (s.startswith("<!--") and s.endswith("-->")):
            if not m:
                raise Reject("판정 불가: 음성 경로 목록 꼴 틀림(%s:%d)" % (rev[:10], n))
            out.add(m.group(1))
    return out


def deploy_patterns(repo, rev):   # 옛 범위: cd-dev.yml «filters: |» 블록의 «- '<글롭>'» 합집합
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


def specs_of(repo, *revs, canon=None):   # 첫 rev(검사 트리)의 표가 비면 판정 불가 · 나머지 rev 표는 합집합으로 더한다
    if not patterns(repo, revs[0]):
        # r1697: 목록이 «원래 없는» 대상 가지(목록 신설 전에 갈라진 ops/main-base 등)는 정본 main 목록으로 판정한다.
        #   ① 대상 가지(revs[1])에 목록이 있으면 = 목록을 지운 PR → 지금처럼 판정 불가(D1)
        #   ② 대상에도 없고 canon(≠대상)에 목록이 있으면 = canon 목록을 쓴다(합집합 = canon ∪ 나머지) + 출처 1줄
        #   ③ 그 밖 = 지금처럼 판정 불가
        tgt = revs[1] if len(revs) > 1 else None
        if os.environ.get("FT_PRESS_SCOPE") != "deploy" and not (tgt and patterns(repo, tgt)) and canon and canon != tgt and patterns(repo, canon):   # r1697 보정 2: deploy 길은 그대로(정본 main 갈래 안 씀)
            print("음성 경로 목록 출처 = 정본 main %s" % canon[:10], file=sys.stderr)   # r1697 보정 1: stdout 첫 줄 = 판정 줄(부르는 쪽이 첫 줄만 echo)
            return [":(glob)" + p for p in sorted(set().union(*(patterns(repo, r) for r in revs), patterns(repo, canon)))]
        raise Reject("판정 불가: 음성 경로 목록 없음(%s:%s)" % (revs[0][:10], VOICE_LIST) if os.environ.get("FT_PRESS_SCOPE") != "deploy"
                     else "판정 불가: 배포 경로 표 없음(%s:%s paths-filter)" % (revs[0][:10], WORKFLOW))
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


def check_poller(run_id, lines):   # 줄 반복자(평문 = splitlines · r1268 조각 = 풀며 나오는 줄) · 줄마다 JSON 객체 + 필수 칸 · run_id 칸이 있는 줄은 전부 묶음 run_id · 1줄 이상(D5)
    tagged, i = 0, 0
    for row in (r for r in lines if r.strip()):
        i += 1
        try:
            d = json.loads(row)
        except ValueError:
            raise Reject("poller %d줄 JSON 아님" % i)
        if not isinstance(d, dict) or any(d.get(k) in (None, "") for k in POLLER_KEYS):
            raise Reject("poller %d줄 필수 칸(%s) 빔" % (i, "·".join(POLLER_KEYS)))
        if "run_id" in d and d["run_id"] != run_id:
            raise Reject("poller %d줄 run_id %s ≠ 묶음 %s" % (i, d["run_id"], run_id))
        tagged += "run_id" in d
    if not i:
        raise Reject("poller_dom.jsonl 줄 0")
    if not tagged:
        raise Reject("poller run_id 줄 0(묶음 run_id 결속 없음)")


def check_table(run_id, text, tp):   # ft-press-gate ⑧ 과 같은 규칙(표머리·네 축·사실·시간 · 빈 값·-·TODO·? 거절) + 표 머리 run_id + r1263 turbopack 행(숫자 = 원문 판정 tp)
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
    tps = [r for r in text.splitlines() if [x.strip() for x in r.split("|")][1:2] == ["turbopack"]]   # r1263 규칙 #8 «turbopack 칸 없으면 REJECT»
    if len(tps) != 1:
        raise Reject("4자 표 turbopack 칸 없음" if not tps else "4자 표 turbopack 칸 %d개(1개여야)" % len(tps))
    m = re.search(r"build\s*(\d+)\D+?runtime\s*(\d+)\D+?config\s*(\d+)", tps[0])
    got = tuple(int(x) for x in m.groups()) if m else None
    if got != tuple(tp):
        raise Reject("4자 표 turbopack 숫자 ≠ 원문(표 %s · 원문 %d/%d/%d)" % ("/".join(map(str, got)) if got else "못 읽음", *tp))


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


def check_content(run_id, poller, table, tp):   # poller = 줄 반복자(list·generator)
    check_poller(run_id, poller)
    counts = check_turbopack(tp)   # r1263: 원문 판정을 먼저 → 표 turbopack 행과 대조
    check_table(run_id, table, counts)
    return counts


def poller_rows(repo, commit, ref, meta, txt, rcs):   # r1268: 평문 poller = 지금 그대로 · 없으면 gzip 조각을 풀어 이은 줄(조각도 없으면 «poller_dom.jsonl 없음»)
    if not rcs[FILES[1]]:
        return txt[FILES[1]].splitlines()
    if not [n for n in run(repo, "ls-tree", "--name-only", commit)[1].split() if n.startswith(FILES[1] + ".gz.")]:
        raise Reject("%s 없음(%s)" % (FILES[1], ref))
    try:
        import press_evidence_parts as pp
    except ImportError:
        raise Reject("poller 조각 읽기 도구(press_evidence_parts.py) 없음 — 판정 불가")
    return pp.rows(repo, commit, meta, Reject)


def bundle(repo, ref, commit):   # 묶음 1개 결속(meta 세트 = 부모 = ref 이름 · run_id = ref 꼬리) + 칸 검사 → dict · 틀리면 Reject
    par, txt, rcs = git(repo, "rev-list", "--parents", "-n1", commit).split()[1:], {}, {}
    for f in FILES:
        rcs[f], txt[f] = run(repo, "show", "%s:%s" % (commit, f))
        if rcs[f] and f != FILES[1]:   # poller_dom.jsonl 만 없어도 된다 — r1268 조각 묶음
            raise Reject("%s 없음(%s)" % (f, ref))
    meta = dict(row.split("=", 1) for row in txt["meta.txt"].splitlines() if "=" in row)
    s, rid = meta.get("set", ""), meta.get("run_id", "")
    if len(par) != 1 or s != par[0] or ref != "refs/press/%s-%s" % (s, rid):
        raise Reject("meta 세트·run_id ≠ 묶음 부모·ref 이름(%s)" % ref)
    tp = check_content(rid, poller_rows(repo, commit, ref, meta, txt, rcs), txt["table.md"], txt["turbopack.txt"])
    return {"ref": ref, "commit": commit, "set": s, "run": rid, "tp": tp}


def newest_first(b):   # r1263 정렬 열쇠 — run_id 의 YYYYMMDD-HHMMSS 늦은 것 먼저 · 못 읽는 run = 맨 뒤 · 같으면 ref 이름순
    m = re.search(r"(\d{8})-(\d{6})", b["run"])
    return (m is None, -int(m.group(1) + m.group(2)) if m else 0, b["ref"])


def pick(repo, target, specs):   # 음성 경로 트리가 target 과 같은 세트의 «통과» 묶음들 + 첫 거절 사유 · r1274 비교 목록 = specs ∪ 묶음 세트 E 의 목록(자기 경로 지우기 0)
    good, why, n = [], "", 0
    for ref, c in sorted(refs(repo, "refs/press").items()):
        n += 1
        e = git(repo, "rev-parse", c + "^").strip()
        try:
            both = sorted({*specs, *(":(glob)" + p for p in patterns(repo, e))})
        except Reject as r:
            why = why or str(r)
            continue
        if not same(repo, e, target, both):
            continue
        try:
            good.append(bundle(repo, ref, c))
        except Reject as r:
            why = why or str(r)
    good.sort(key=newest_first)
    return good, why or "묶음 없음(음성 경로 트리가 같은 세트의 refs/press/* 0 · 검사 %d개)" % n


def unpaid(repo, upto):   # 빚 착지가 upto 의 조상(main 위)인데 상환 ref 없음 — 착지 못 한 빚 ref 는 조상 아님 = 무시
    paid = {r.rsplit("/", 1)[1] for r in refs(repo, "refs/press-debt-paid")}
    debts = (r.rsplit("/", 1)[1] for r in refs(repo, "refs/press-debt"))
    return [d for d in debts if SHA.match(d) and d not in paid and anc(repo, d, upto)]


def debt_line(repo, d):
    kv = dict(re.findall(r"(\w+)=(\S+)", git(repo, "log", "-1", "--format=%B", "refs/press-debt/" + d)))
    return "press 빚 PR #%s(착지 %s) — 담당 %s · 복구 뒤 press 1회" % (kv.get("pr", "?"), d[:10], kv.get("owner", "planner"))


def cover(repo, good, debts):   # 빚 착지 전부를 조상으로 가진 세트의 묶음(D7) · 빚 0 이면 첫 묶음(r1263 pick 이 늦은 run 순으로 줌)
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
