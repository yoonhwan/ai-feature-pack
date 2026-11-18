"""ft2 card_archive (r2177) — 2.0 팀의 «버림 · 쓸모 없음» 판정 카드를 indices/대기·진행 → indices/아카이브/<YYYY-MM>/ 로 옮긴다.
1.x ft-index-move 아카이브 갈래와 같은 판정 규칙(R2 착지 표식 = 거절 · 버림 줄 이름 정확 일치 · R4 정본 줄 · R6 --to)을 쓴다.
카드 고르기 · 부모 SHA 고정 · git 1회 7초 · push 재시도 = card_stage 를 불러 쓴다(card · pins · run · push · spawn) · 판정문 글 = r2176 card_verdict.
쓰기 = 임시 index 1개로 D <옛 경로> + A <아카이브/YYYY-MM/같은 이름> 커밋(작업 폴더 · worktree 0) · 원장 · 짝 표 · 좌석 손 0.
rc 0 ARCHIVED · NOOP · 1 REJECT(쓰기 0) · 2 usage · 3 판정 불가.
"""
import argparse
import importlib.util
import os
import re
import subprocess
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location("ft2_card_archive_stage", os.path.join(HERE, "card_stage.py"))
cs = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(cs)
land, verdict, proj, Unsure, Reject = cs.land, cs.verdict, cs.proj, cs.Unsure, cs.Reject
MONTH = re.compile(r"\d{4}-\d{2}/[^/]+\.md")   # 아카이브/ 밑 꼬리 = <YYYY-MM>/<파일>
CANON = re.compile(r"(?m)^- 정본 영향 없음:")
TO_EXAMPLE = "design/teams/<팀>/indices/대기/<카드>.md"   # r2185 꼴 예시(대기 · 진행 · 완성 가운데 실제 폴더 · 팀 폴더는 부르는 사람이)


def judge(root, text, sec, stem):
    """R2 — 절 전체로 ft_close_marker · stdout 있음 = 착지(거절) · 비고 rc1 = 버림 줄 검사 · 그 밖 = Unsure · 통과 None."""
    lib = os.path.join(root, ".fable-team", "bin", "ft-team-lib.sh")   # card_stage.da_judge 와 같은 lib · 같은 절 자르기
    body = "".join(s for s in re.split(r"(?m)^(?=## )", text) if (m := re.match(r"## .*?(§\d+)(?!\d)", s)) and m.group(1) == sec)
    if not body:
        return "판정문에 %s 절 없음" % (sec or "§N")
    try:
        p = subprocess.run(["bash", "-c", '. "$1" >/dev/null 2>&1 || exit 9; ft_close_marker "$2"', "x", lib, stem],
                           input=body.encode(), capture_output=True, timeout=7)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise Unsure("판정문 읽기 %s" % type(exc).__name__) from None
    if p.stdout.strip():
        return "착지한 카드 — card_stage --da 로 완성 (%s %s)" % (sec, stem)
    if p.returncode != 1:
        raise Unsure("ft_close_marker rc %s" % p.returncode)
    keys = tuple("%s — %s — %s" % (w, stem, v) for w in ("닫힘", "CLOSE") for v in ("버림", "쓸모 없음"))
    if any(line.strip().startswith(keys) for line in body.splitlines()):
        return None
    return ("{0} 에 «닫힘 — {1} — 버림»·«닫힘 — {1} — 쓸모 없음» 으로 시작하는 줄 없음"
            " · 통과 줄 예시 «닫힘 — {1} — 버림» · 닫힘 또는 CLOSE 가운데 한 낱말만 쓴다").format(sec, stem)


def ledger(root, team, work, to):
    """R5 — 원장 done = 거절 · 받은 일(deliveries 1+) = --to 필수 · 못 읽음 = Unsure."""
    try:
        p = proj.project(root, team)
    except (OSError, ValueError) as exc:
        raise Unsure("원장 못 읽음 %s" % type(exc).__name__) from None
    if p.get("result") != proj.OK:
        raise Unsure("원장 %s" % p.get("result"))
    row = p["works"].get(work) or {}
    if row.get("done"):
        raise Reject("원장 done — card_stage 로 완성 %s" % work)
    if row.get("deliveries") and not to:
        raise Reject("열린 일 — --to <받는 카드> %s" % work)


def gone(byz, root, team, work, sha):
    """R7 — 대기·진행에 카드 0 일 때 · 가지 순서로 indices/아카이브/<YYYY-MM>/ 밑 같은 이름(card() 규칙) · 처음 가지 1개 = stem · 2+ = Unsure · 0 = None."""
    lp = land.Landing()
    lp.root, lp.cache, lp.log = root, {}, lambda *a: None
    mapped = lp.cardmap(team)
    mapped = (mapped.get(work) or []) if isinstance(mapped, dict) else []
    m = land.MAPPED.match(mapped[0]) if len(mapped) == 1 else None
    for ref in land.REFS:
        row = land.team_row(cs.run(byz, "show", sha[ref] + ":design/TEAMS.md"), team)
        hits = []
        for head in ([m.group(1)] if m else land.folders(row[1]) if row else []):
            head += "/indices/아카이브/"
            hits += [n for n in cs.run(byz, "ls-tree", "-r", "--name-only", sha[ref], "--", head[:-1]).splitlines()
                     if n.startswith(head) and MONTH.fullmatch(n[len(head):])]
        names = [os.path.basename(n) for n in hits]
        names = [b for b in names if b == (m.group(2) if m else work + ".md")] or \
            ([] if m else [b for b in names if b.startswith(work + "-") and b.endswith(".md")])
        if len(names) > 1:
            raise Unsure("아카이브 카드 %d개" % len(names))
        if names:
            return names[0][:-3]
    return None


def pick(byz, root, team, work, sha):
    """R3 R7 — (ref, 대기|진행 카드) · 이미 아카이브 = stem 문자열 · 완성에만 = 거절 · 그 밖 = card() 의 Unsure 그대로."""
    try:
        got = cs.card(byz, root, team, work, sha)
    except Unsure as exc:
        if str(exc) != "진행 카드 0개":
            raise
        got = gone(byz, root, team, work, sha)
        if got is None:
            raise
    if got is None:
        raise Reject("완성 카드 — 아카이브 출발은 대기|진행 %s" % work)
    return got


def target(byz, sha, ref, to, old):
    """R6 — --to 는 고른 가지 고정 SHA 의 design/…/indices/(대기|진행|완성)/*.md 실재 · 자기 자신 = 거절."""
    if to is None:
        return
    if to == old or not land.MAPPED.match(to) or not cs.run(byz, "ls-tree", sha[ref], "--", to).strip():
        raise Reject("--to %s — 고른 가지의 indices 대기|진행|완성 카드가 아님(자기 자신 · 없음 · indices 밖)"
                     " · --to 는 카드 이름이 아니라 경로 · 예 %s" % (to, TO_EXAMPLE))


def restate(text, now, da, frm, seat, to):
    """R9 — 머리 «- 상태:» 줄 = 아카이브 · «## 상태» 절 끝 1줄(+ --to 면 1.x r1747 «대체됨:» 줄)."""
    lines = text.rstrip("\n").split("\n")
    idx = next((i for i, line in enumerate(lines) if line.startswith("- 상태:")), None)
    pos = idx if idx is not None else 1
    lines[pos:pos + (idx is not None)] = ["- 상태: 아카이브 · %s · DA %s" % (now, da)]
    lines += [] if "## 상태" in lines else ["", "## 상태"]
    end = next((i for i in range(lines.index("## 상태") + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
    while lines[end - 1] == "":
        end -= 1
    add = ["- %s · 아카이브 · DA %s · ft2 card_archive %s→아카이브 · 좌석 %s" % (now, da, frm, seat)]
    add += ["대체됨: %s · 사유: %s" % (to, da)] if to else []
    return "\n".join(lines[:end] + add + lines[end:]) + "\n"


def commit_tree(byz, parent, old, new, body, msg):
    """R8 — 임시 index 1개로 D old + A new 커밋 · push 전 자기 검사(변화 2줄 · 새 경로 = 아카이브/<YYYY-MM>/ 바로 밑 .md)."""
    with tempfile.TemporaryDirectory(prefix="ft2-card-archive-") as tmp:
        env, path = dict(os.environ, GIT_INDEX_FILE=os.path.join(tmp, "index")), os.path.join(tmp, "card.md")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(body)
        cs.run_env(byz, env, "read-tree", parent)
        blob = cs.run_env(byz, env, "hash-object", "-w", path).strip()
        cs.run_env(byz, env, "update-index", "--force-remove", "--", old)
        cs.run_env(byz, env, "update-index", "--add", "--cacheinfo", "100644,%s,%s" % (blob, new))
        sha = cs.run(byz, "commit-tree", cs.run_env(byz, env, "write-tree").strip(), "-p", parent, "-m", msg).strip()
    toks = cs.run(byz, "diff-tree", "-r", "--no-renames", "--name-status", "-z", parent, sha).split("\0")
    rows = [(toks[i], toks[i + 1]) for i in range(0, len(toks) - 1, 2)]
    head, _, tail = new.partition("/indices/아카이브/")
    if sorted(rows) != sorted([("D", old), ("A", new)]) or not tail or not MONTH.fullmatch(tail) or old.partition("/indices/")[0] != head:
        raise Unsure("card_archive 커밋 범위 밖 %d줄" % len(rows))
    return sha


def archive(byz, root, a, now, seen):
    """R8 — fetch 1 · 부모 SHA 고정 · 판정 · 커밋 · push · 거절 1회면 fetch 뒤 새 끝에서 1회 더 · 결과 (stem, frm, sha) | stem(NOOP)."""
    cs.run(byz, "fetch", "-q", "origin", *(r.split("/", 1)[1] for r in land.REFS))
    path, _, sec = a.da.rpartition("#")
    refused = False
    while True:
        sha = cs.pins(byz)
        got = pick(byz, root, a.team, a.work, sha)
        if isinstance(got, str):
            return got
        ref, old = got
        stem, frm = os.path.basename(old)[:-3], "대기" if "/indices/대기/" in old else "진행"
        why, seen["src"] = verdict.verdict(path, lambda text: judge(root, text, sec, stem), byz, sha, land.REFS, cs.run, Unsure)
        if why:
            raise Reject(why)
        text = cs.run(byz, "show", "%s:%s" % (sha[ref], old))
        if not CANON.search(text):
            raise Reject("카드에 «- 정본 영향 없음:» 줄 없음 %s" % stem)
        target(byz, sha, ref, a.to, old)
        new = old.replace("/indices/%s/" % frm, "/indices/아카이브/%s/" % now[:7], 1)
        body = restate(text, now, a.da, frm, a.seat, a.to)
        commit = commit_tree(byz, sha[ref], old, new, body, "[docs] %s 2.0 아카이브(DA %s)" % (stem, a.da))
        rc = cs.push(byz, commit, ref)
        if rc == 0:
            return stem, frm, commit
        if refused:
            raise Unsure("push 결과 불명 rc %s" % rc)
        refused = True
        cs.run(byz, "fetch", "-q", "origin", ref.split("/", 1)[1])


def main(argv=None):
    ap = argparse.ArgumentParser(description="ft2 2.0 버림 카드 대기·진행→아카이브 (r2177)")
    for flag in ("--root", "--team", "--work", "--da", "--seat", "--to", "--byz"):
        ap.add_argument(flag, required=flag not in ("--to", "--byz"),
                        help="받는 카드의 경로(카드 이름 아님) · 예 %s" % TO_EXAMPLE if flag == "--to" else None)
    a, now = ap.parse_args(argv), os.environ.get("FT_NOW") or time.strftime("%Y-%m-%dT%H:%M:%S")
    root, byz, seen = os.path.abspath(a.root), os.path.abspath(a.byz or a.root), {}
    try:
        ledger(root, a.team, a.work, a.to)
        out = archive(byz, root, a, now, seen)
        word, rc = ("NOOP %s 이미 아카이브" % out, 0) if isinstance(out, str) else ("ARCHIVED %s %s→아카이브 %s" % out, 0)
        word += "\n판정문 출처 %s" % seen["src"] if not isinstance(out, str) and seen.get("src") else ""
    except Reject as exc:
        word, rc = "REJECT %s" % exc, 1
    except (Unsure, subprocess.TimeoutExpired) as exc:
        word, rc = "판정 불가 %s" % (exc if isinstance(exc, Unsure) else "git 시간초과"), 3
    print(word)
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
