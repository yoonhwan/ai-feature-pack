"""ft2 card_stage (r1859) — 2.0 done 카드를 BYZ ops/main-base 의 indices/진행 → 완성 으로 옮긴다(임시 detached worktree 안에서만 쓴다).
done = projection.project(journal 정본) · done.at = recover_state 복구 자료(raw state.json 0) · 카드 = keeper_land 규칙 · 1.x 가드·core 손 0.
push = 7초 + 재시도 1 · 거절이면 rebase 1회 · 머리 `- 상태:` 줄 = 완성 + `## 상태` 절 끝 1줄 · 끝에 임시 worktree 정리.
rc 0 STAGED·NOOP · 1 REJECT done 없음(쓰기 0) · 3 판정 불가(push 시간초과 = 결과 불명 · 다시 돌리면 NOOP·STAGED 로 수렴).
"""
import argparse
import importlib.util
import os
import pathlib
import subprocess
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REF, BRANCH = "origin/ops/main-base", "ops/main-base"
_SPEC = importlib.util.spec_from_file_location("ft2_card_stage_land", os.path.join(HERE, "keeper_land.py"))
land = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(land)
proj = land.cli._load("projection")   # keeper_land.done 과 같은 projection.project(공개 API) · core 손 0
class Unsure(Exception):
    pass
def git(cwd, *args):
    p = subprocess.run(["git", "-C", cwd] + list(args), capture_output=True, text=True, timeout=7)
    return p.returncode, p.stdout
def run(cwd, *args):
    rc, out = git(cwd, *args)
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
def card(byz, root, team, work):
    """진행 카드 1개 경로 · 이미 완성 = None · 0·2+ = Unsure. 짝 표 우선 → <work>.md → <work>-*.md."""
    row, lp = land.team_row(run(byz, "show", REF + ":design/TEAMS.md"), team), land.Landing()
    lp.root, lp.cache, lp.log = root, {}, lambda *a: None
    mapped = lp.cardmap(team)
    mapped = mapped.get(work) or [] if isinstance(mapped, dict) else mapped
    match = land.MAPPED.match(mapped[0]) if row and isinstance(mapped, list) and len(mapped) == 1 else None
    if row is None or isinstance(mapped, str) or len(mapped) > 1 or (mapped and not match):
        raise Unsure("카드 판독 %s" % ("TEAMS 팀 행 없음" if row is None else mapped if isinstance(mapped, str) else "짝 표 %s" % mapped))
    names = [n for f in ([match.group(1)] if match else land.folders(row[1]))
             for n in land.staged(f, run(byz, "ls-tree", "-r", "--name-only", REF, "--", f + "/indices"))]
    base = {os.path.basename(n) for n in names}
    exact = os.path.basename(mapped[0]) if mapped else work + ".md" if work + ".md" in base else None
    hits = [n for n in names if (os.path.basename(n) == exact if exact else os.path.basename(n).startswith(work + "-") and n.endswith(".md"))]
    doing = [n for n in hits if "/indices/진행/" in n]
    if not doing and any("/indices/완성/" in n for n in hits):
        return None
    if len(doing) != 1:
        raise Unsure("진행 카드 %d개" % len(doing))
    return doing[0]
def restate(text, at, now):
    lines, top = text.rstrip("\n").split("\n"), "- 상태: 완성 · %s · ft2 complete %s" % (now, at)
    idx = next((i for i, line in enumerate(lines) if line.startswith("- 상태:")), None)
    pos = idx if idx is not None else 1
    lines[pos:pos + (idx is not None)] = [top]
    lines += [] if "## 상태" in lines else ["", "## 상태"]
    end = next((i for i in range(lines.index("## 상태") + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
    while lines[end - 1] == "":
        end -= 1
    return "\n".join(lines[:end] + ["- %s · ft2 card_stage 진행→완성(ft2 complete %s)" % (now, at)] + lines[end:]) + "\n"
def push(wt, rebased=False, timed=False):
    """7초 + 재시도 1 · 거절이면 rebase 1회. 보낸 뒤 실패는 전부 «결과 불명»(원격 쓰기 여부 모름 · R1 · «원격 쓰기 0» 주장 0)."""
    try:
        rc = git(wt, "push", "-q", "origin", "HEAD:" + BRANCH)[0]
    except subprocess.TimeoutExpired:
        if timed:
            raise Unsure("push 결과 불명") from None
        return push(wt, rebased, True)
    if rc == 0:
        return run(wt, "rev-parse", "HEAD").strip()
    try:
        if rebased:
            raise Unsure("rc %s" % rc)
        run(wt, "fetch", "-q", "origin", BRANCH), run(wt, "rebase", "-q", REF)
    except (Unsure, subprocess.TimeoutExpired) as exc:
        raise Unsure("push 결과 불명 %s" % (exc if isinstance(exc, Unsure) else "git 시간초과")) from None
    return push(wt, True, timed)
def stage(byz, path, at, now):
    with tempfile.TemporaryDirectory(prefix="ft2-card-stage-") as tmp:
        wt, dst = os.path.join(tmp, "wt"), path.replace("/indices/진행/", "/indices/완성/", 1)
        run(byz, "worktree", "add", "-q", "--detach", wt, REF)
        try:
            os.makedirs(os.path.dirname(os.path.join(wt, dst)), exist_ok=True)
            run(wt, "mv", path, dst)
            doc = pathlib.Path(wt, dst)
            doc.write_text(restate(doc.read_text(encoding="utf-8"), at, now), encoding="utf-8")
            run(wt, "commit", "-q", "-am", "[docs] %s 2.0 완성 폴더(ft2 done)" % doc.stem)
            out = doc.stem, push(wt)
        except Unsure as exc:
            out = exc
        try:
            gone = git(byz, "worktree", "remove", "--force", wt)[0]
        except subprocess.TimeoutExpired:
            gone = 124
    if gone:   # R1 — 정리 rc 를 버리지 않는다 · 앞 결과를 같이 낸다(재실행 = NOOP 수렴)
        raise Unsure("worktree 정리 실패 rc %s %s 등록 잔존 · %s" % (gone, wt, out if isinstance(out, Unsure) else "STAGED %s %s" % out))
    if isinstance(out, Unsure):
        raise out
    return out
def main(argv=None):
    ap = argparse.ArgumentParser(description="ft2 2.0 done 카드 진행→완성 (r1859)")
    [ap.add_argument(flag, required=flag != "--byz") for flag in ("--root", "--team", "--work", "--byz")]
    a, now = ap.parse_args(argv), os.environ.get("FT_NOW") or time.strftime("%Y-%m-%dT%H:%M:%S")
    root, byz = os.path.abspath(a.root), os.path.abspath(a.byz or a.root)
    try:
        at = done_at(root, a.team, a.work)
        path = at and run(byz, "fetch", "-q", "origin", BRANCH) is not None and card(byz, root, a.team, a.work)
        word, rc = ("REJECT done 없음 %s" % a.work, 1) if at is None else ("NOOP %s 이미 완성" % a.work, 0) if path is None \
            else ("STAGED %s 진행→완성 %s" % stage(byz, path, at, now), 0)
    except (Unsure, subprocess.TimeoutExpired) as exc:
        word, rc = "판정 불가 %s" % (exc if isinstance(exc, Unsure) else "git 시간초과"), 3
    print(word)
    return rc
if __name__ == "__main__":
    raise SystemExit(main())
