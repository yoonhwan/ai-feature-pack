"""ft2 card_stage (r1859·r1884·rH) — 2.0 done 카드를 카드가 있는 BYZ 가지(keeper_land.REFS 순서 · ops/main-base → main)의 indices/진행·대기 → 완성 으로 옮긴다.
rH — 임시 worktree 를 쓰지 않는다: 임시 index(GIT_INDEX_FILE) 하나로 D/A 커밋을 만든다(작업 폴더·worktree 등록·checkout 0 · G2·G3).
부모는 시도 시작에 SHA 하나로 고정한다(⓪ rev-parse <ref>^{commit}) — 그 뒤 read-tree·show·write-tree·commit-tree·push 가 모두 그 SHA 를 쓴다(G3·G9).
done = projection.project(journal 정본) · done.at = recover_state 복구 자료(raw state.json 0) · 카드 = keeper_land 규칙 · 1.x 가드·core 손 0.
git 1회 = 7초(하드 룰 12 · 늘리지 않는다) · 시간 초과 글에 하위 명령 이름이 있다(G1). push = 7초 + 재시도 1 · 거절이면 fetch 1회 뒤 새 끝에서 1회 더(G4).
push 전 자기 검사 = 커밋 변화가 D <옛 경로> 1줄 + 완성/ 밑 .md A 1줄뿐인가(G8).
머리 `- 상태:` 줄 = 완성 + `## 상태` 절 끝 1줄 · 커밋 글 `[docs] <카드> 2.0 완성 폴더(ft2 done)` 그대로(G7).
rc 0 STAGED·NOOP · 1 REJECT done 없음(쓰기 0) · 3 판정 불가(push 시간초과 = 결과 불명 · 다시 돌리면 NOOP·STAGED 로 수렴).
r2037 — `--da <판정문#§N>`: done 없음이면 §N 절을 ft_close_marker(1.x 한 곳 · 사본 0)로 읽어 닫힘이면 같은 stage() · 원장에 work 있고 done=false 면 complete 1회.
"""
import argparse
import importlib.util
import os
import re
import subprocess
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location("ft2_card_stage_land", os.path.join(HERE, "keeper_land.py"))
land = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(land)
_VSPEC = importlib.util.spec_from_file_location("ft2_card_stage_verdict", os.path.join(HERE, "card_verdict.py"))
verdict = importlib.util.module_from_spec(_VSPEC)
_VSPEC.loader.exec_module(verdict)   # r2176 — 판정문 글을 얻는 한 곳
proj = land.cli._load("projection")   # keeper_land.done 과 같은 projection.project(공개 API) · core 손 0
PAIR = ("worktree",)   # G1 — 둘째 낱말까지 적는 명령(worktree add · worktree remove …)
class Unsure(Exception):
    pass
class Reject(Exception):
    pass
class Slow(Unsure):
    """git 1회 7초 초과 — 결과 불명(재시도 1회는 push 만 · G5)."""
    pass
def spawn(cwd, args, env=None):
    """git 1회(상한 7초 고정) · 시간 초과면 하위 명령 이름을 넣어 Slow(G1 · 예 `git read-tree 시간초과 7초`)."""
    try:
        p = subprocess.run(["git", "-C", cwd] + list(args), capture_output=True, text=True, timeout=7, env=env)
    except subprocess.TimeoutExpired:
        raise Slow("git %s 시간초과 7초" % (" ".join(args[:2]) if args[:1] and args[0] in PAIR else (args[0] if args else ""))) from None
    return p.returncode, p.stdout
def git(cwd, *args):
    return spawn(cwd, args)
def git_env(cwd, env, *args):   # G3 ① — 임시 index 로 부르는 git
    return spawn(cwd, args, env)
def run(cwd, *args):
    rc, out = git(cwd, *args)
    if rc:
        raise Unsure("git %s rc %s" % (args[0], rc))
    return out
def run_env(cwd, env, *args):
    rc, out = git_env(cwd, env, *args)
    if rc:
        raise Unsure("git %s rc %s" % (args[0], rc))
    return out
def done_at(root, team, work):
    p = proj.project(root, team)
    if p.get("result") != proj.OK:
        raise Unsure("projection %s" % p.get("result"))
    if not (p["works"].get(work) or {}).get("done"):
        return None
    node = proj.journal.Journal(proj.runtime_path(root, team), rec=proj.record)
    return proj.record.recover_state(node.state(), node.records())["done"][work]["at"]
def pins(byz):
    """G3 ⓪·G9 — 시도 시작에 land.REFS 두 가지를 각각 40자 SHA 로 고정한다(가지 이름은 fetch·rev-parse·push 에만)."""
    return {ref: run(byz, "rev-parse", ref + "^{commit}").strip() for ref in land.REFS}
def card(byz, root, team, work, sha):
    """(ref, 진행|대기 카드 경로) · 이미 완성 = None · 0·2+ = Unsure. 짝 표 우선 → <work>.md → <work>-*.md.
    r1884 — keeper_land.REFS 두 ref 를 다 읽은 뒤 고른다 · 두 가지 모두 진행 카드 = Unsure(쓰기 0).
    rH — 판독 기준은 가지 이름이 아니라 시도 시작에 고정한 SHA 다(G9 · 고른 가지의 SHA 가 G3 의 P)."""
    rows, lp = {ref: land.team_row(run(byz, "show", sha[ref] + ":design/TEAMS.md"), team) for ref in land.REFS}, land.Landing()
    lp.root, lp.cache, lp.log = root, {}, lambda *a: None
    mapped = lp.cardmap(team)
    mapped = mapped.get(work) or [] if isinstance(mapped, dict) else mapped
    match = land.MAPPED.match(mapped[0]) if isinstance(mapped, list) and len(mapped) == 1 else None
    if not any(rows.values()) or isinstance(mapped, str) or len(mapped) > 1 or (mapped and not match):
        raise Unsure("카드 판독 %s" % ("TEAMS 팀 행 없음" if not any(rows.values()) else mapped if isinstance(mapped, str) else "짝 표 %s" % mapped))
    doing, wait, complete = {}, {}, False
    for ref, row in ((r, w) for r, w in rows.items() if w):
        names = [n for f in ([match.group(1)] if match else land.folders(row[1]))
                 for n in land.staged(f, run(byz, "ls-tree", "-r", "--name-only", sha[ref], "--", f + "/indices"))]
        base = {os.path.basename(n) for n in names}
        exact = os.path.basename(mapped[0]) if mapped else work + ".md" if work + ".md" in base else None
        hits = [n for n in names if (os.path.basename(n) == exact if exact else os.path.basename(n).startswith(work + "-") and n.endswith(".md"))]
        doing[ref], complete = [n for n in hits if "/indices/진행/" in n], complete or any("/indices/완성/" in n for n in hits)
        wait[ref] = [n for n in hits if "/indices/대기/" in n]   # r1889 — 2.0 팀은 대기/ 에서 바로 끝난다
    if any(doing.values()) and any(wait.values()):
        raise Unsure("진행·대기 둘 다 카드")
    doing = doing if any(doing.values()) or complete else wait
    picks = [(ref, found[0]) for ref, found in doing.items() if found]
    if len(picks) > 1:
        raise Unsure("두 가지에 진행 카드")
    if not picks and complete:
        return None
    if not picks or len(doing[picks[0][0]]) != 1:
        raise Unsure("진행 카드 %d개" % sum(map(len, doing.values())))
    return picks[0]
def da_check(root, spec, stem, byz=None, sha=None, seen=None):
    """r2037 A1·A2·A4 — 판정문 §N 절 → ft_close_marker <stem> · 통과 None · 거절 = 사유 1줄 · 판정문·lib 읽기 실패 = Unsure.
    r2176 — 글 = card_verdict(작업 트리 파일 먼저 → 고정 SHA 가지 순서) · git 으로 통과하면 seen["src"] = "<가지> <sha 10자>"."""
    path, _, sec = spec.rpartition("#")
    why, src = verdict.verdict(path, lambda text: da_judge(root, text, sec, stem), byz or root, sha, land.REFS, run, Unsure)
    if seen is not None:
        seen["src"] = src
    return why
def da_judge(root, text, sec, stem):
    lib = os.path.join(root, ".fable-team", "bin", "ft-team-lib.sh")   # 설치된 1.x 런타임 lib(ft_close_marker 단일 출처 · r1784)
    # 절 = `## …§N` 머리부터 다음 `## ` 전까지(ft-index-close-landed 와 같은 꼴)
    body = "".join(s for s in re.split(r"(?m)^(?=## )", text) if (m := re.match(r"## .*?(§\d+)(?!\d)", s)) and m.group(1) == sec)
    try:
        p = body and subprocess.run(["bash", "-c", '. "$1" >/dev/null 2>&1 || exit 9; ft_close_marker "$2"', "x", lib, stem],
                                    input=body.encode(), capture_output=True, timeout=7)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise Unsure("판정문 읽기 %s" % type(exc).__name__) from None
    if p and p.returncode > 1:
        raise Unsure("ft_close_marker rc %s" % p.returncode)
    out = p.stdout.decode("utf-8", "replace").strip() if p else "판정문에 %s 절 없음" % (sec or "§N")
    return None if p and p.returncode == 0 and out[:4] in ("card", "pack") else out or "%s 에 %s 닫힘 표식 없음" % (sec, stem)
def restate(text, at, now, frm="진행", da=None):
    lines, top = text.rstrip("\n").split("\n"), "- 상태: 완성 · %s · %s" % (now, "DA " + da if da else "ft2 complete " + at)
    idx = next((i for i, line in enumerate(lines) if line.startswith("- 상태:")), None)
    pos = idx if idx is not None else 1
    lines[pos:pos + (idx is not None)] = [top]
    lines += [] if "## 상태" in lines else ["", "## 상태"]
    end = next((i for i in range(lines.index("## 상태") + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
    while lines[end - 1] == "":
        end -= 1
    tail = "- %s · 완성 · DA %s · ft2 card_stage %s→완성" % (now, da, frm) if da else "- %s · ft2 card_stage %s→완성(ft2 complete %s)" % (now, frm, at)
    return "\n".join(lines[:end] + [tail] + lines[end:]) + "\n"
def push(byz, sha, ref, timed=False):
    """G5 — 받은 커밋 SHA 를 그대로 올린다(HEAD·rebase 0) · 7초 + 재시도 1 · 두 번째 시간 초과 = 결과 불명."""
    try:
        rc = git(byz, "push", "-q", "origin", "%s:%s" % (sha, ref.split("/", 1)[1]))[0]
    except (Slow, subprocess.TimeoutExpired):
        if timed:
            raise Unsure("push 결과 불명") from None
        return push(byz, sha, ref, True)
    return rc
def check(byz, parent, sha, old, new):
    """G8 — push 전 자기 검사 · `diff-tree -r --no-renames --name-status -z P <커밋>` 이 정확히 D <옛 경로> · A <완성 경로> 2줄.
    -z 로 읽어 한글 경로의 quoting 을 풀고 실제 경로와 비교한다(줄 수만 세지 않는다)."""
    toks = run(byz, "diff-tree", "-r", "--no-renames", "--name-status", "-z", parent, sha).split("\0")
    rows = [(toks[i], toks[i + 1]) for i in range(0, len(toks) - 1, 2)]
    if sorted(rows) != sorted([("D", old), ("A", new)]) or not new.endswith(".md") or "/indices/완성/" not in new:
        raise Unsure("card_stage 커밋 범위 밖 %d줄" % len(rows))
def commit_tree(byz, parent, old, new, at, now, frm, da=None):
    """G3 ①~⑧ — 임시 index 1개로 옛 경로 D + 완성 경로 A 커밋 · 자기 검사(G8)까지 · 커밋 SHA."""
    with tempfile.TemporaryDirectory(prefix="ft2-card-stage-") as tmp:
        env = dict(os.environ, GIT_INDEX_FILE=os.path.join(tmp, "index"))
        body, text = os.path.join(tmp, "card.md"), run(byz, "show", "%s:%s" % (parent, old))
        with open(body, "w", encoding="utf-8") as fh:
            fh.write(restate(text, at, now, frm, da))
        run_env(byz, env, "read-tree", parent)
        blob = run_env(byz, env, "hash-object", "-w", body).strip()
        run_env(byz, env, "update-index", "--force-remove", "--", old)
        run_env(byz, env, "update-index", "--add", "--cacheinfo", "100644,%s,%s" % (blob, new))
        tree = run_env(byz, env, "write-tree").strip()
        sha = run(byz, "commit-tree", tree, "-p", parent, "-m", "[docs] %s 2.0 완성 폴더(%s)" % (os.path.basename(old)[:-3], "DA " + da if da else "ft2 done")).strip()
        check(byz, parent, sha, old, new)
    return sha
def stage(byz, root, team, work, at, now, da=None, gate=None):
    """G2·G3·G4 — fetch 1 · 부모 SHA 고정 · 임시 index 커밋 · push · 거절 1회면 fetch 뒤 새 끝에서 1회 더.
    돌려주는 값 = (카드 stem, "<frm>→완성", 커밋 SHA) · 이미 완성/ = None(NOOP)."""
    run(byz, "fetch", "-q", "origin", *(r.split("/", 1)[1] for r in land.REFS))
    refused = False
    while True:
        sha, picked = pins(byz), None
        picked = card(byz, root, team, work, sha)
        if picked is None:
            return None
        ref, old = picked
        frm = "대기" if "/indices/대기/" in old else "진행"
        new = old.replace("/indices/%s/" % frm, "/indices/완성/", 1)
        why = gate(os.path.basename(old)[:-3], sha) if gate else None   # r2037 — 판정문 대조는 쓰기 전(거절 = 쓰기 0)
        if why and da:
            raise Reject(why)
        stem = os.path.basename(old)[:-3]
        own = stem == work or stem.startswith(work + "-")   # r2152 G1·G2 — 짝 표 남의 카드는 «착지(<work>):» 줄만(keeper_land F3 와 같은 규칙)
        pat = r"(?m)^- 착지: [0-9a-f]{40}\b" if own else r"(?m)^- 착지\(%s\): [0-9a-f]{40}(?=\s|$)" % re.escape(work)
        landed = re.search(pat, run(byz, "show", "%s:%s" % (sha[ref], old)))
        if not landed and not (gate and why is None):   # r2147 C1 — 착지 줄 또는 통과한 DA 만 옮김(쓰기·push 0)
            raise Unsure("착지 줄 없음 %s" % os.path.basename(old)[:-3])
        commit = commit_tree(byz, sha[ref], old, new, at, now, frm, da)
        rc = push(byz, commit, ref)
        if rc == 0:
            return os.path.basename(new)[:-3], frm + "→완성", commit, why
        if refused:   # G4 — 두 번째 거절 = 지금처럼 판정 불가(원격 쓰기 여부 모름)
            raise Unsure("push 결과 불명 rc %s" % rc)
        refused = True
        run(byz, "fetch", "-q", "origin", ref.split("/", 1)[1])   # 새 끝에서 card() 부터 다시
def ledger_complete(root, team, work):
    """r2037 A5 — 원장에 work 가 있고 done=false 면 cli complete 1회(최신 attempt) → done 재확인 · work 없음 = None(complete 0)."""
    row = proj.project(root, team)["works"].get(work)
    if row is None or row.get("done"):
        return None
    att = (row.get("deliveries") or [None])[-1]
    if not att:
        raise Unsure("— 원장 complete attempt 없음")
    out, rc = land.cli.run(["complete", "--work", work, "--attempt", att, "--root", root, "--team", team])
    if rc or done_at(root, team, work) is None:
        raise Unsure("— 원장 complete %s" % ((out.get("reason") or out.get("result")) if rc else "done 확인 못 함"))
    return "원장 complete %s %s" % (work, att)
def main(argv=None):
    ap = argparse.ArgumentParser(description="ft2 2.0 done 카드 진행→완성 (r1859)")
    [ap.add_argument(flag, required=flag not in ("--byz", "--da")) for flag in ("--root", "--team", "--work", "--byz", "--da")]
    a, now = ap.parse_args(argv), os.environ.get("FT_NOW") or time.strftime("%Y-%m-%dT%H:%M:%S")
    root, byz = os.path.abspath(a.root), os.path.abspath(a.byz or a.root)
    try:
        at = done_at(root, a.team, a.work)
        seen = {}   # r2176 — git 으로 통과한 판정문 출처
        da, gate = a.da if at is None else None, (lambda stem, sha: da_check(root, a.da, stem, byz, sha, seen)) if a.da else None
        out = None if at is None and not da else stage(byz, root, a.team, a.work, at or "", now, da, gate)
        word, rc = ("REJECT done 없음 %s" % a.work, 1) if at is None and not da else ("NOOP %s 이미 완성" % a.work, 0) if out is None \
            else ("STAGED %s %s %s" % out[:3], 0)
        if out and a.da and not da:   # A3 — done 있음 = 지금 갈래 + 대조 1줄
            word += "\nDA 대조 %s" % ("일치 " + a.da if out[3] is None else "불일치 " + out[3])
        if out and a.da and seen.get("src"):   # r2176 V3·V7 — git 출처로 통과 = STAGED·대조 줄 바로 다음 1줄
            word += "\n판정문 출처 %s" % seen["src"]
        if out and da:   # A5 — 카드 이동은 이미 끝(되돌림 0) · 원장 실패는 다음 줄 판정 불가
            print(word)
            word = ledger_complete(root, a.team, a.work) or ""
    except Reject as exc:
        word, rc = "REJECT %s" % str(exc).replace("REJECT ", "", 1), 1
    except (Unsure, subprocess.TimeoutExpired) as exc:
        word, rc = "판정 불가 %s" % (exc if isinstance(exc, Unsure) else "git 시간초과"), 3
    if word:
        print(word)
    return rc
if __name__ == "__main__":
    raise SystemExit(main())
