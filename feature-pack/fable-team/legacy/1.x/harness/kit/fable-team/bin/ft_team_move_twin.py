"""ft_team_move_twin — 쌍둥이 공존 가지의 옛→새 병합 이동 (r447 · ft_team_move·ft_team_move_apply 가 부른다).

명단(TEAMS.md)은 이미 새 꼴(design/teams/<팀>/)인데 옛 폴더 design/<팀>/ 에 추적 파일이 남은 가지(이동 커밋을 받고도 옛 폴더에서 계속 일함).
파일마다: 새 경로에 없음 = `git mv`(MOVED) · 있고 내용 다름 = 옛 쪽 내용 승 `git mv -f`(OVERWROTE) · 본문 치환 뒤 같음 = 옛 삭제 `git rm`(DROPPED-SAME).
그 뒤 새 폴더 본문의 옛 경로 글자를 치환하고 한 커밋 → 저장 참조(명부·nano-card-base·worktree-info·baton) 재작성. 옛 내용은 항상 새 경로로 살아남는다(삭제는 같은 내용 중복만).
"""
from __future__ import annotations

import os
from pathlib import Path

from ft_team_move import Ctx, MoveError, hits, occupancy, run
from ft_team_move_apply import Exhausted, Snap, Unjudged, card_base_step, git, new_step, rewrite, rewrite_tracked, roster_step, text_stores_step


def old_files(ctx: Ctx, team: str) -> list[str]:
    out = run("git", "ls-files", "-z", "--", f"design/{team}/", cwd=ctx.root).stdout
    return [p for p in out.split("\0") if p]


def same(a: Path, b: Path, team: str) -> bool:
    if a.is_symlink() or b.is_symlink():
        return a.is_symlink() and b.is_symlink() and os.readlink(a) == os.readlink(b)
    if not b.is_file():
        return False
    try:
        return rewrite(a.read_text(encoding="utf-8"), team) == rewrite(b.read_text(encoding="utf-8"), team)
    except UnicodeDecodeError:
        return a.read_bytes() == b.read_bytes()


def classify(ctx: Ctx, team: str) -> list[tuple[str, str, str]]:
    """(종류, 옛 상대경로, 새 상대경로) — 종류 = move · overwrite · drop."""
    rows = []
    for rel in old_files(ctx, team):
        new_rel = f"design/teams/{team}/{rel[len(f'design/{team}/'):]}"
        dst = ctx.root / new_rel
        kind = "move" if not (dst.exists() or dst.is_symlink()) else "drop" if same(ctx.root / rel, dst, team) else "overwrite"
        rows.append((kind, rel, new_rel))
    return rows


def plan_line(ctx: Ctx, team: str) -> str | None:
    rows = classify(ctx, team)
    if not rows:
        return None
    n = {k: sum(1 for r in rows if r[0] == k) for k in ("move", "overwrite", "drop")}
    return f"PLAN-TWIN {team} 쌍둥이 공존 design/{team}/ {len(rows)}파일 → 유일본 {n['move']} · 다른 내용(옛 쪽 승) {n['overwrite']} · 같은 내용(옛 삭제) {n['drop']}"


def preflight(ctx: Ctx, team: str, occ_snap: dict) -> None:
    if git(ctx, "diff", "--cached", "--name-only").strip():
        raise MoveError("REJECT 스테이징에 남의 변경이 있다 — 비운 뒤 다시")
    if git(ctx, "status", "--porcelain", "--", f"design/{team}", f"design/teams/{team}").strip():
        raise MoveError(f"REJECT {team} 쌍둥이 폴더에 미커밋 변경 또는 추적 안 된 파일이 있다 — [wip] 먼저 커밋한 뒤 다시")
    if occ_snap.get("deadline_exhausted"):
        raise Exhausted(team)
    if occ_snap["blocks"]:
        raise Unjudged("\n".join(occ_snap["blocks"]))
    occ = occupancy(ctx, team, occ_snap)
    if occ:
        raise MoveError("REJECT 점유 중 — 비운 뒤 다시:\n" + "\n".join(occ))


def rollback(ctx: Ctx, team: str) -> None:
    """커밋 전 실패 — 선검사가 «두 폴더 깨끗·스테이징 비어 있음» 을 보장했으니 두 폴더만 HEAD 로 되돌린다."""
    scope = [f"design/{team}", f"design/teams/{team}"]
    run("git", "reset", "-q", "--", *scope, cwd=ctx.root)
    run("git", "checkout", "--", *scope, cwd=ctx.root)
    run("git", "clean", "-fdq", "--", *scope, cwd=ctx.root)
    print(f"ROLLBACK {team} 커밋 전 실패 — 두 폴더를 원래대로 되돌렸다")


def prune_empty(top: Path) -> None:
    for d, _, _ in sorted(os.walk(top), key=lambda w: -len(w[0])):
        try:
            os.rmdir(d)   # 빈 폴더만 지운다(파일이 남은 폴더는 OSError)
        except OSError:
            pass


def merge(ctx: Ctx, team: str, snap: Snap, occ_snap: dict) -> None:
    preflight(ctx, team, occ_snap)
    rows = classify(ctx, team)
    step = new_step(team, [plan_line(ctx, team) or ""])
    snap.data["steps"].append(step)
    origin: dict[Path, Path] = {}
    n = {"move": 0, "overwrite": 0, "drop": 0}
    try:
        for kind, rel, new_rel in rows:
            if kind == "drop":
                git(ctx, "rm", "-q", "--", rel)
            else:
                (ctx.root / new_rel).parent.mkdir(parents=True, exist_ok=True)
                git(ctx, "mv", *(["-f"] if kind == "overwrite" else []), "--", rel, new_rel)
                origin[ctx.root / new_rel] = ctx.root / rel
            n[kind] += 1
        new_dir = ctx.root / "design" / "teams" / team
        for p in sorted(new_dir.rglob("*")):
            if p.is_file() and not p.is_symlink() and hits(p, team):
                rewrite_tracked(step, "readme_map" if p.name.startswith("README") else "card_body", p, origin.get(p, p), team)
        git(ctx, "add", "--", f"design/teams/{team}")
        git(ctx, "commit", "-q", "-m", f"[structure] 팀 폴더 쌍둥이 병합 {team}: design/{team}/ → design/teams/{team}/ (r447 ft-team-move · 옛 내용 우선)")
        step["commit"] = git(ctx, "rev-parse", "HEAD").strip()
        for t in step["tracked"]:
            t["commit"] = step["commit"]
    except MoveError:
        snap.data["steps"].remove(step)
        rollback(ctx, team)
        raise
    prune_empty(ctx.root / "design" / team)
    print(f"TWIN-MERGED {team} MOVED {n['move']} OVERWROTE {n['overwrite']} DROPPED-SAME {n['drop']} commit={step['commit'][:12]}")
    for fn in (roster_step, card_base_step, text_stores_step):
        print("STORE " + fn(ctx, team, snap, step))
