#!/usr/bin/env python3
"""press_evidence_verify.py — r1230 press 증거 묶음 판정 (판정 2946 · 오빠 «테스트 bts poller 없이는 배포없다»).
  팩 harness/bin 과 BYZ scripts/ci 가 «바이트 같은» 한 파일(시험이 cmp 로 대조) · 읽기 전용 판정만 — 묶음 만들기·착지 쪽 push 는 팩 press_evidence_land.py.
  deploy : 배포 직전 검사(cd-dev·cd-prod) — 배포 커밋 C 의 배포 경로 트리 == 어떤 «통과» 묶음 세트 E 의 배포 경로 트리(문서 면제 0 · D8)
           · 미상환 빚(refs/press-debt/<착지> 중 C 의 조상 ∧ refs/press-debt-paid 없음)이면 그 빚 착지를 조상으로 가진 세트의 묶음이어야
  묶음 = 커밋 1개(부모 = 세트 E · 트리 = meta.txt·poller_dom.jsonl·table.md·turbopack.txt) · ref = refs/press/<E>-<run_id>(원격 · 머신 무관)
  음성 경로(r1274) = 그 트리의 docs/rules/press_voice_paths.md «## 목록» 절 글롭(없음·빈 목록·꼴 틀림 = 판정 불가 = 거절 · D1) · env FT_PRESS_SCOPE=deploy = 옛 cd-dev.yml paths-filter 합집합
  외부 호출 = fetch 7 s + 재시도 1(실패 = 판정 불가 1줄) · push = min(고정비 9 + 7, 70) s + 재시도 1 + 끊긴 뒤 ls-remote 확인(r1254). rc 0 통과 · 1 거절 · 2 사용법.
  queue : r2387 — 음성 경로 PR 이 줄 서면 «지금 press 해도 착지까지 안 깨질 PR» 1개(NEXT)를 고른다 · 판정 = pick(=same·patterns) 그대로 · 읽기 전용(refs·작업 트리 쓰기 0) · rc 0 정상 · 3 판정 불가.
    승인 표식 = <state>/autonomy-merge-approved/<head sha> 파일(이름 = 승인한 head · 시각 = mtime · DA#54 H3) · 열린 PR 조회 = gh pr list 1회(번호·head 만 = 7 s + 재시도 1 · 두 번 다 실패 = «판정 불가 PR 목록» 1줄 rc 3) · 바뀐 파일 = 로컬 git diff · ref fetch·prune 0(읽기 전용).
"""
import argparse
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys
import time

WORKFLOW = ".github/workflows/cd-dev.yml"
VOICE_LIST = "docs/rules/press_voice_paths.md"   # r1274 BYZ 정본 음성 경로 목록(바꾸는 법 = 문서 PR)
VOICE_GLOB = re.compile(r"^- `([^\s`]+)`$")
POLLER_KEYS = ("axis", "epoch_ms")   # 실 poller_dom.jsonl 공통 칸(arch#190 질문 #211296)
AXES = ("아키텍처 문서", "코드", "로그", "화면")
FILES = ("meta.txt", "poller_dom.jsonl", "table.md", "turbopack.txt")
NS = ("refs/press", "refs/press-debt", "refs/press-debt-paid")
SHA = re.compile(r"^[0-9a-f]{40}$")
GH_JSON = "number,headRefOid"   # r2387 queue 의 gh pr list 칸 = 번호·head 만(실 BYZ 183 PR 에서 files·reviews 를 더하면 7 s timeout · DA#54 H2 실측 1.16 s) · 바뀐 파일 = 로컬 git diff · 승인 표식 = 상태 폴더 파일
APPROVE_DIR = "autonomy-merge-approved"   # 승인 표식 = <state>/autonomy-merge-approved/<head sha> (파일 이름 = 승인한 head · 시각 = mtime · DA#54 H3 · ft-autonomy.sh approve-merge)


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


_PAT = {}   # r2387: (repo, rev, scope) → 목록 — queue 가 PR 수만큼 같은 rev 를 다시 읽지 않게(값 그대로 · 판정 불변)


def patterns(repo, rev):   # r1274: rev 트리의 BYZ 정본 음성 경로 목록 «## 목록» 절 · «- `<글롭>`» 줄만(빈 줄·한 줄 <!-- --> 만 건너뜀 · 다른 줄 = 판정 불가) · FT_PRESS_SCOPE=deploy = 옛 cd-dev.yml 범위
    key = (repo, rev, os.environ.get("FT_PRESS_SCOPE") or "")
    if key in _PAT:
        return set(_PAT[key])
    if os.environ.get("FT_PRESS_SCOPE") == "deploy":
        _PAT[key] = frozenset(deploy_patterns(repo, rev))
        return set(_PAT[key])
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
    _PAT[key] = frozenset(out)
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


def newest_refs(rows):   # r2381: ref 이름 꼬리(run_id)에만 r1263 열쇠를 건다(세트 40자는 열쇠에서 뺀다 · git 0) · 못 읽는 run = 맨 뒤 · 같으면 ref 이름순
    def key(row):
        tail = row[0].rsplit("/", 1)[-1]
        run = tail.split("-", 1)[1] if re.match(r"[0-9a-f]{40}-", tail) else tail
        return newest_first({"run": run, "ref": row[0]})
    return sorted(rows, key=key)


def pick(repo, target, specs, upto=None):   # 음성 경로 트리가 target 과 같은 세트의 «통과» 묶음들 + 첫 거절 사유 + 읽은 빚 · r1274 비교 목록 = specs ∪ 묶음 세트 E 의 목록(자기 경로 지우기 0)
    # r2381: 최신 run 순으로 하나씩 판정 → 첫 통과 묶음이 나오면 unpaid 1회로 빚을 읽고, 그 묶음이 빚을 다 덮으면 거기서 멈춘다 · 못 덮으면 다음 통과 묶음을 이어 본다(통과 0 = unpaid 0회)
    upto = target if upto is None else upto
    good, bad, debts, n = [], {}, None, 0
    seen, diffs = {}, {}   # seen = 세트 sha → 비교 목록 또는 Reject · diffs = 세트 sha → diff 판정(K3: 부모당 1회)
    for ref, c in newest_refs(refs(repo, "refs/press").items()):
        n += 1
        e = git(repo, "rev-parse", c + "^").strip()   # 깨진 묶음 = 지금처럼 판정 불가(본 묶음일 때만)
        if e not in seen:
            try:
                both = sorted({*specs, *(":(glob)" + p for p in patterns(repo, e))})
            except Reject as r:
                seen[e] = r
            else:
                seen[e] = both
        both = seen[e]
        if isinstance(both, Reject):
            bad[ref] = str(both)
            continue
        if e not in diffs:
            if not same(repo, e, target, both):
                diffs[e] = False
            else:
                diffs[e] = True
        if not diffs[e]:
            continue
        try:
            b = bundle(repo, ref, c)
        except Reject as r:
            bad[ref] = str(r)
            continue
        good.append(b)
        if debts is None:
            debts = unpaid(repo, upto)
        if all(anc(repo, d, b["set"]) for d in debts):
            break
    return good, (bad[min(bad)] if bad else "") or "묶음 없음(음성 경로 트리가 같은 세트의 refs/press/* 0 · 검사 %d개)" % n, debts or []


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


def globrx(g):   # r2387: r1274 글롭(«**»·«*»·«?») → 이름 하나 정규식(«[» 는 글자 그대로)
    out, i = [], 0
    while i < len(g):
        if g.startswith("**", i):
            out.append(".*")
            i += 2
        elif g[i] == "*":
            out.append("[^/]*")
            i += 1
        elif g[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(g[i]))
            i += 1
    return re.compile("^" + "".join(out) + "$")


def touches(specs, files):   # PR 이 음성 경로를 바꿨나 — 글롭 합집합(specs) × 로컬로 센 바뀐 파일(gh 상한 없음 = 잘림 걱정 0 · 목록 0 = 안 바꿈)
    rxs = [globrx(re.sub(r"^:\(glob\)", "", s)) for s in specs]
    return any(rx.match(f) for rx in rxs for f in files)


def gh_prs(gh, limit, slug, secs=7):   # r2387: 열린 PR 1회 조회 — 7 s + 재시도 1 · 두 번 다 실패 = 판정 불가(하드 룰 20)
    cmd = [gh, "pr", "list", "--state", "open", "--limit", str(limit), "--json", GH_JSON] + (["-R", slug] if slug else [])
    err = ""
    for _ in (1, 2):
        try:
            p = subprocess.run(cmd, capture_output=True, text=True, timeout=secs, encoding="utf-8", errors="replace")
        except subprocess.TimeoutExpired:
            err = "%g s 초과" % secs
            continue
        except OSError as x:
            raise Reject("gh 실행 실패(%s)" % str(x)[:60])
        if p.returncode == 0:
            try:
                rows = json.loads(p.stdout or "[]")
            except ValueError:
                rows, err = None, "JSON 아님"
            if isinstance(rows, list):
                return rows
        else:
            err = (p.stderr.strip().splitlines() or [""])[-1][:120]
    raise Reject("gh pr list 실패(%s)" % err)


def epoch(ts):   # ISO «2026-11-21T01:02:03Z» → 초 · 못 읽으면 None(«<분>분째» 셈용)
    try:
        return datetime.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc).timestamp()
    except (TypeError, ValueError):
        return None


def changed(repo, main, head):   # PR 이 바뀐 파일 — 로컬 git diff 1회(«main...head» = git 이 merge-base 를 안에서 푼다 · gh files 칸 안 씀 = 100개 상한 없음)
    rc, out = run(repo, "diff", "--name-only", "--no-renames", "%s...%s" % (main, head))
    if rc:
        raise Reject("판정 불가: git diff rc=%d" % rc)
    return [f for f in out.splitlines() if f]


def state_dir(root):   # 승인 표식 폴더의 부모 = ft-autonomy.sh state-dir(정본 1곳) → 실패 = <root>/.fable-team/state
    here = os.path.dirname(os.path.abspath(__file__))
    env = dict(os.environ)
    if root:
        env["FT_ROOT"] = root
    try:
        p = subprocess.run(["bash", os.path.join(here, "ft-autonomy.sh"), "state-dir"], capture_output=True, text=True,
                           encoding="utf-8", errors="replace", timeout=7, env=env)
        if p.returncode == 0 and p.stdout.strip():
            return p.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        pass
    return os.path.join(root, ".fable-team", "state") if root else ""


def approved_at(head, st):   # 승인 표식 시각 = <state>/autonomy-merge-approved/<head sha> 의 mtime · 없으면 ""(승인 전)
    if not st:
        return ""
    try:
        return datetime.datetime.fromtimestamp(os.path.getmtime(os.path.join(st, APPROVE_DIR, head)), datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    except OSError:
        return ""


def merge_tree(repo, base, head):   # 지금 main + PR head 의 병합 트리 1회(객체 쓰기뿐) — 겹침 = 그 줄만 판정 불가
    rc, out = run(repo, "merge-tree", "--write-tree", base, head)
    t = (out.splitlines() or [""])[0].strip()
    if rc or not SHA.match(t):
        raise Reject("겹침(merge-tree rc=%d)" % rc)
    return t


MAINSPEC = [None]   # r2387: queue 가 도는 동안 «지금 main 목록» 은 하나 — PR 수만큼 다시 읽지 않는다
_SET = {}   # r2387: 세트 sha → {"voice": {비교목록: 해시}, "names": 세트가 부모에 더한 파일, "tree": 세트 트리, "parent": 세트 부모} · 프로세스 안 읽기 전용 캐시


def set_meta(repo, e, key, fn):   # 세트 1개의 계산값 1회 캐시(같은 세트를 PR 수만큼 다시 세지 않는다)
    m = _SET.setdefault(e, {})
    if key not in m:
        m[key] = fn()
    return m[key]


def voice_hash(repo, rev, specs):   # 글롭 범위 트리 «내용» 해시 — ls-tree -r 1회 + 글롭 거르기(:(glob) 는 ls-tree 가 안 받는다) · 두 rev 값이 같으면 same()(= diff --quiet) 0 과 같은 뜻
    pre = sorted({re.sub(r"^:\(glob\)", "", x).split("*")[0].split("?")[0].rsplit("/", 1)[0] for x in specs} - {""})   # 글롭 앞 고정 경로만 넘긴다(트리 전체를 안 읽는다)
    rc, out = run(repo, "ls-tree", "-r", "-z", rev, "--", *pre) if pre else (0, "")
    if rc:
        raise Reject("판정 불가: git ls-tree rc=%d" % rc)
    rxs = [globrx(re.sub(r"^:\(glob\)", "", x)) for x in specs]
    rows = []
    for row in out.split("\0"):
        if row:
            meta, _, path = row.partition("\t")
            if any(rx.match(path) for rx in rxs):
                rows.append(meta + "\t" + path)
    rows.sort()
    return hashlib.sha1("\n".join(rows).encode("utf-8", "replace")).hexdigest()


def press_sets(repo):   # refs/press 를 최신 run 순으로 — (ref, 묶음 커밋, 세트) · 깨진 묶음은 Reject 를 그 자리에 담는다(pick 과 같은 자리)
    out = []
    for ref, c in newest_refs(refs(repo, "refs/press").items()):
        out.append((ref, c, set_meta(repo, c, "set", lambda c=c: _set_of(repo, c))))
    return out


def _set_of(repo, c):
    try:
        return git(repo, "rev-parse", c + "^").strip()
    except Reject as x:
        return x


def pick_fast(repo, target, specs, upto):   # r2387 N1: pick 과 «같은 규칙»(최신 run 순 · 음성 경로 트리 같음 · bundle 통과 · 빚 덮음)을 세트 캐시로 센다 — PR 수 × ref 수 git 호출을 없앤다
    pre = specs_of(repo, MAINSPEC[0])   # 거르기 = 지금 main 목록(모든 PR 이 같은 키 = 세트당 1회) · 확정은 아래 same() 그대로
    tgt = voice_hash(repo, target, pre)
    good, why, debts, n = [], "", None, 0
    for ref, c, e in press_sets(repo):
        n += 1
        if isinstance(e, Reject):
            raise e   # 깨진 묶음 = 그 줄 판정 불가(⑮ · pick 과 같은 자리에서 끊는다)
        if set_meta(repo, e, "voice", lambda e=e: voice_hash(repo, e, pre)) != tgt:
            continue   # 후보 거르기(세트마다 1회 계산 · PR 수만큼 다시 안 센다)
        both = sorted({*specs, *(":(glob)" + p for p in patterns(repo, e))})   # 확정 = pick 과 같은 비교 목록·같은 함수
        if not same(repo, e, target, both):
            continue
        try:
            b = bundle(repo, ref, c)
        except Reject as x:
            why = why or str(x)
            continue
        good.append(b)
        if debts is None:
            debts = unpaid(repo, upto)
        if all(anc(repo, d, b["set"]) for d in debts):
            break
    return good, (why or "묶음 없음(음성 경로 트리가 같은 세트의 refs/press/* 0 · 검사 %d개)" % n), debts or []


def own_set(repo, head, files):   # r2387: 이 PR 의 묶음이 있나 — 묶음에는 PR 번호가 없어 «세트 = 그 세트 부모 + 이 PR 의 병합» 인가로 센다(세트는 PR head 를 조상으로 안 갖는다 · 최신 run 순 첫 hit)
    want = frozenset(files)
    for _ref, c, e in press_sets(repo):
        if isinstance(e, Reject):
            raise e
        nm = set_meta(repo, e, "names", lambda e=e: _names(repo, e))
        if not nm or not nm <= want:
            continue   # 세트가 부모에 더한 파일이 그 PR 이 바꾼 파일의 부분집합 — 아니면 그 PR 의 묶음이 아니다(merge-tree 0회)
        t = (run(repo, "merge-tree", "--write-tree", set_meta(repo, e, "parent", lambda e=e: git(repo, "rev-parse", e + "^").strip()), head)[1].splitlines() or [""])[0].strip()
        if SHA.match(t) and t == set_meta(repo, e, "tree", lambda e=e: git(repo, "rev-parse", e + "^{tree}").strip()):
            return e
    return ""


def _names(repo, e):
    rc, out = run(repo, "diff", "--name-only", "--no-renames", git(repo, "rev-parse", e + "^").strip(), e)
    return frozenset(out.split()) if rc == 0 else frozenset()


def last_voice_landing(repo, main, specs):   # 음성 경로를 마지막으로 바꾼 main 착지 sha 1개(STALE 의 «다르게 만든 착지»)
    out = git(repo, "log", "--first-parent", "--format=%H", "-n", "1", main, "--", *specs).strip().splitlines()
    return out[0] if out else ""


def queue_row(repo, main, pr, st):   # r2387 K1·K2: PR 1개 → None(음성 경로 0 · 줄에 안 섬) 또는 (승인시각, 갈래, 덧말) · 판정은 pick 그대로(새 규칙 0)
    head = (pr.get("headRefOid") or "").strip()
    if not SHA.match(head) or run(repo, "rev-parse", "--verify", head + "^{commit}")[0]:
        raise Reject("head 객체 없음(%s)" % (head[:10] or "?"))
    files = changed(repo, main, head)   # 바뀐 파일(로컬 git diff 1회)
    specs = specs_of(repo, MAINSPEC[0])   # 지금 main 목록 1회(캐시) — 대부분의 PR 은 이것만으로 걸러진다
    if not touches(specs, files) and VOICE_LIST not in files:
        return None   # 음성 경로 0 · 목록 자체를 안 바꿈 = 줄에 안 섬(PR 쪽 목록 show 0회)
    specs = specs_of(repo, main, head)   # 목록 = 지금 main ∪ PR 쪽(r1274 같음 · PR 이 글롭을 넓힌 경우)
    if not touches(specs, files):
        return None
    at = approved_at(head, st)   # 표식 파일 이름이 head sha = 승인 뒤 새 커밋을 올리면 그 새 head 는 «승인 전»
    if not at:
        return "", "승인 전", ""
    good, _why, _debts = pick_fast(repo, merge_tree(repo, main, head), specs, main)
    if good:
        return at, "VALID", ""
    if own_set(repo, head, files):
        return at, "STALE", " · 다르게 만든 착지 %s · press 다시" % (last_voice_landing(repo, main, specs)[:10] or "?")
    return at, "NONE", " · press 필요"


def queue(a):   # r2387 K1~K4: PR 마다 1줄 + 끝 «NEXT …» 1줄 — 쓰기·push 0(읽기 전용)
    main = git(a.repo, "rev-parse", "--verify", a.main + "^{commit}").strip()
    if a.landed:   # K3: 착지가 음성 경로를 안 바꿨으면 gh 0 · 출력 0
        base = git(a.repo, "rev-parse", "--verify", a.landed[0] + "^{commit}").strip()
        q = git(a.repo, "rev-parse", "--verify", a.landed[1] + "^{commit}").strip()
        rc, out = run(a.repo, "diff", "--name-only", "--no-renames", base, q, "--", *specs_of(a.repo, q, base))
        if rc or not out.strip():
            return 0
    MAINSPEC[0] = main
    st = state_dir(a.root)   # r2387 H1: fetch 0 — 원격 최신 묶음은 부르는 쪽 몫(로컬 ref 만 읽는다 = queue 가 ref 를 안 지운다)
    prs, now, rows = gh_prs(a.gh, a.limit, a.slug), time.time(), []
    for pr in prs:
        n = int(pr.get("number") or 0)
        try:
            r = queue_row(a.repo, main, pr, st)
        except Reject as x:
            r = ("", "판정 불가", " · " + str(x))
        if r is None:
            continue
        rows.append((r[0] or "9999", n, r[1], "PR #%d %s%s" % (n, r[1], r[2])))
    rows.sort(key=lambda r: (r[0], r[1]))   # 승인 표식 시각 오름차순 · 같으면 PR 번호
    for r in rows:
        print(r[3])
    valid = [r for r in rows if r[2] == "VALID"]
    if valid:   # 줄 어디든 VALID 면 NEXT 는 «대기»(DA#53 H1) — VALID 둘 이상이면 승인 순 첫 것
        print("NEXT 대기(VALID PR %d 착지 뒤 · %d분째)" % (valid[0][1], max(0, int((now - (epoch(valid[0][0]) or now)) // 60))))
    else:
        nxt = next((r for r in rows if r[2] in ("STALE", "NONE")), None)   # 판정 불가 줄은 건너뛴다
        print("NEXT %d" % nxt[1] if nxt else "NEXT 없음")
    return 0


def deploy(a):
    c = git(a.repo, "rev-parse", "--verify", a.commit + "^{commit}").strip()
    specs = specs_of(a.repo, c)
    fetch_refs(a.repo, a.remote)
    good, why, debts = pick(a.repo, c, specs)   # r2381: 빚 조회는 통과 묶음이 처음 나올 때 1회(pick 안)
    if not good:
        raise Reject("press 증거 없음/틀림: %s — 배포 %s · 판정 2946" % (why, c[:10]))
    b = cover(a.repo, good, debts)
    if b is None:
        raise Reject(debt_line(a.repo, debts[0]) + " — 배포 %s · 판정 2946" % c[:10])
    print(ok_line(b) + " · 배포 %s" % c[:10])
    return 0


def main(argv):
    ap = argparse.ArgumentParser(prog="press_evidence_verify.py", description="배포 직전 press 증거 검사(r1230) · queue(r2387)")
    ap.add_argument("mode", choices=("deploy", "queue"))
    ap.add_argument("--commit")
    ap.add_argument("--repo", default=".")
    ap.add_argument("--remote", default="origin")
    ap.add_argument("--main", default="origin/main")
    ap.add_argument("--gh", default=os.environ.get("FT_GH") or "gh")
    ap.add_argument("--slug", default="")
    ap.add_argument("--root", default=os.environ.get("FT_ROOT") or "")
    ap.add_argument("--limit", type=int, default=200)
    ap.add_argument("--landed", nargs=2, metavar=("BASE", "COMMIT"))
    a = ap.parse_args(argv)
    if a.mode == "queue":
        try:
            return queue(a)
        except Reject as r:
            print("판정 불가 PR 목록 — %s" % r)
            return 3
    if not a.commit:
        ap.error("deploy 에는 --commit 이 필요하다")
    try:
        return deploy(a)
    except Reject as r:
        print(str(r))
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
