"""ft_team_move_apply — 팀 폴더 이동의 쓰는 쪽 (--apply · --revert · R382).

apply(팀마다): 선검사(깨끗한 트리·점유 0·목적지 없음) → 스냅샷 → `git mv` + 텍스트 재작성 + 한 커밋 → (선택) ft-head-sync → 저장 참조(명부·nano-card-base·worktree-info·baton·추가 파일).
  «받은 워크트리»(design/teams/<팀>/ 가 이미 있는 곳)만 저장 참조를 새 경로로 쓰고, 못 받은 곳은 옛 경로를 두고 `_move_pending` 표식(쌍둥이 후보가 읽는다).
revert: 스냅샷의 저장 참조 파일을 역순으로 바이트 복원(sha256 대조) → 그 뒤 `git revert` 로 이동 커밋을 되돌린다.
스냅샷 증거(DA⑥ Q1): 단계마다 `items` = 저장 참조 7종(KINDS) 각각 {kind·state(changed/tracked/unchanged)·before_sha·after_sha·revert_match·files}.
  changed = 저장 파일 백업(명부·nano-card-base·worktree-info·baton·홈 BOOT/GUIDE) · tracked = git 이동 커밋이 싣는 파일(카드 본문·README 지도·TEAMS.md·.gitignore → commit sha 와 같이) · unchanged = 이번 이동이 안 건드림(빠진 종류 0).
  revert 가 파일마다 «복원 뒤 sha == before_sha» 를 revert_match(bool)로 snapshot.json 에 다시 쓴다.
"""
from __future__ import annotations

import datetime
import hashlib
import json
import math
import os
import shutil
import subprocess
import time
from collections.abc import Callable
from pathlib import Path

from ft_team_move import Ctx, MoveError, hits, occupancy, occupancy_snapshot, old_form, pat, received, refs, run, sha256


# 7초 룰(전역 하드 룰 12) — --sync-worktrees 는 «크기를 아는 배치»: 시도 상한 = min(고정비 + 7초 × ceil(워크트리 수/기준량), 70초), 배치 전체 공통 마감 70초(팀 루프가 잔여를 차감).
# 고정비 3.5 s(CLI 기동 잠정값) · 기준량 = 워크트리 10개당 7 s(잠정 — 실측 뒤 조정).
SYNC_FIXED_S, SYNC_UNIT_S, SYNC_UNIT_WT, SYNC_DEADLINE_S = 3.5, 7.0, 10, 70.0


class Unjudged(MoveError):
    """점유 입력(tmux·lsof)을 못 얻었다 — 점유 판정 불가. 팀마다 반복하지 않고 배치를 한 번 알리고 멈춘다(rc 1)."""


class Exhausted(MoveError):
    """배치 공유 마감(70초)이 소진돼 이 팀의 점유 판정을 할 시간이 없다 — 이동 전 PARTIAL(rc 3)이지 판정 불가(BLOCK)가 아니다."""


class Partial(Exception):
    """이동 커밋은 끝났으나 ft-head-sync 가 마감 안에 못 끝났다 — 저장 참조 쓰기 전에 멈춘다(rc 3)."""


def sync_cap(ctx: Ctx) -> float:
    return min(SYNC_FIXED_S + SYNC_UNIT_S * math.ceil(max(len(ctx.worktrees()), 1) / SYNC_UNIT_WT), SYNC_DEADLINE_S)


def git(ctx: Ctx, *a: str, ok: tuple[int, ...] = (0,)) -> str:
    try:
        done = run("git", *a, cwd=ctx.root)
    except subprocess.TimeoutExpired:
        raise MoveError(f"ERROR git {a[0]} 7초 초과(7초 룰)") from None
    if done.returncode not in ok:
        raise MoveError(f"ERROR git {a[0]} 실패(rc={done.returncode}): {(done.stderr or done.stdout).strip()[:240]}")
    return done.stdout


def rewrite(text: str, team: str) -> str:
    return pat(team).sub(f"design/teams/{team}/", text)


KINDS = ("roster", "nano_card_base", "worktree_info", "baton", "card_body", "readme_map", "home_boot_guide")


def digest(vals: list[tuple[str, str]]) -> str | None:
    if not vals:
        return None
    return vals[0][1] if len(vals) == 1 else hashlib.sha256("\n".join(f"{p}:{v}" for p, v in sorted(vals)).encode()).hexdigest()


def build_items(step: dict) -> list[dict]:
    items = []
    for kind in KINDS:
        files = [f for f in step["files"] if f.get("kind") == kind]   # .get — version 1 스냅샷(kind 칸 없음)도 revert 가능
        tracked = [t for t in step.get("tracked", []) if t.get("kind") == kind]
        ent = files + tracked
        match = all(e.get("revert_match") is True for e in ent) if ent and all(e.get("revert_match") is not None for e in ent) else (None if ent else True)
        items.append({"kind": kind, "state": "tracked" if tracked else "changed" if files else "unchanged",
                      "before_sha": digest([(e["path"], e["before_sha"]) for e in ent]), "after_sha": digest([(e["path"], e.get("after_sha") or "") for e in ent]),
                      "revert_match": match,
                      "files": [{k: v for k, v in e.items() if k != "backup"} for e in ent]})
    return items


def new_step(team: str, before: list[str]) -> dict:
    return {"team": team, "commit": None, "files": [], "tracked": [], "before": before}


class Snap:
    def __init__(self, ctx: Ctx, tag: str):
        self.dir = ctx.state / f"{datetime.datetime.now():%Y%m%d-%H%M%S-%f}-{tag}"
        (self.dir / "files").mkdir(parents=True)
        self.data: dict = {"version": 2, "pending_teams": [], "root": str(ctx.root), "project": str(ctx.project), "steps": []}

    def backup(self, step: dict, path: Path, kind: str) -> None:
        n = sum(len(s["files"]) for s in self.data["steps"])
        dest = self.dir / "files" / str(n)
        shutil.copy2(path, dest)
        step["files"].append({"kind": kind, "path": str(path), "before_sha": sha256(path), "after_sha": None, "revert_match": None, "backup": str(dest)})

    def save(self) -> Path:
        for st in self.data["steps"]:
            st["items"] = build_items(st)
        out = self.dir / "snapshot.json"
        out.write_text(json.dumps(self.data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return out


def write_text(snap: Snap, step: dict, path: Path, new: str, kind: str) -> None:
    snap.backup(step, path, kind)
    path.write_text(new, encoding="utf-8")
    step["files"][-1]["after_sha"] = sha256(path)


def walk(obj, fn):
    if isinstance(obj, str):
        return fn(obj)
    if isinstance(obj, dict):
        return {k: walk(v, fn) for k, v in obj.items()}
    if isinstance(obj, list):
        return [walk(v, fn) for v in obj]
    return obj


def dump_like(raw: str, data: dict) -> str:
    lines = [ln for ln in raw.split("\n") if ln.strip()]
    if len(lines) <= 1:
        return json.dumps(data, ensure_ascii=False) + ("\n" if raw.endswith("\n") else "")
    ind = next((ln[: len(ln) - len(ln.lstrip())] for ln in lines[1:] if ln.startswith((" ", "\t"))), "  ")
    return json.dumps(data, ensure_ascii=False, indent=ind if ind != "  " else 2) + "\n"


def roster_step(ctx: Ctx, team: str, snap: Snap, step: dict) -> str:
    p = ctx.roster(team)
    if not p.is_file():
        return "roster 없음(건너뜀)"
    raw = p.read_text(encoding="utf-8")
    data = json.loads(raw)
    wt = lambda name: ctx.project / ".worktrees" / name if name else ctx.root  # noqa: E731
    done = pend = 0
    for k, v in data.items():
        base = wt(data.get("_cards_wt")) if k.startswith("_") and k in ("_cards", "_tree") else (wt(v.get("worktree")) if isinstance(v, dict) else ctx.root)
        new = walk(v, lambda s, t=team: rewrite(s, t))
        if new == v:
            continue
        if received(base, team):
            if isinstance(new, dict):
                new.pop("_move_pending", None)
            data[k] = new
            done += 1
        elif isinstance(v, dict):
            v["_move_pending"] = f"design/teams/{team}/"
            pend += 1
    out = dump_like(raw, data)
    json.loads(out)
    if out != raw:
        write_text(snap, step, p, out, "roster")
    return f"roster {p.name} 재작성 {done} · 미전환 표식 {pend}"


def card_base_step(ctx: Ctx, team: str, snap: Snap, step: dict) -> str:
    cb = ctx.project / ".fable-team" / "state" / "nano-card-base"
    done = pend = 0
    for p in sorted(cb.glob("*.json")) if cb.is_dir() else []:
        if not hits(p, team):
            continue
        row = json.loads(p.read_text(encoding="utf-8"))
        if received(Path(row.get("worktree") or ctx.root), team):
            row["card_path"] = rewrite(str(row.get("card_path", "")), team)
            row.pop("_move_pending", None)
            done += 1
        else:
            row["_move_pending"] = f"design/teams/{team}/"
            pend += 1
        write_text(snap, step, p, json.dumps(row, ensure_ascii=False, indent=2) + "\n", "nano_card_base")
    return f"nano-card-base 재작성 {done} · 미전환 표식 {pend}"


def text_stores_step(ctx: Ctx, team: str, snap: Snap, step: dict) -> str:
    wi = pend = 0
    for w in ctx.worktrees():
        p = w / ".worktree-info.json"
        if not hits(p, team):
            continue
        if received(w, team):
            write_text(snap, step, p, rewrite(p.read_text(encoding="utf-8"), team), "worktree_info")
            wi += 1
        else:
            pend += 1
    others = [(ctx.project / ".baton" / "branches.json", "baton"), *((p, "home_boot_guide") for p in ctx.extras())]
    ot = 0
    for p, kind in others:
        if hits(p, team):
            write_text(snap, step, p, rewrite(p.read_text(encoding="utf-8"), team), kind)
            ot += 1
    return f"worktree-info 재작성 {wi}(미전환 {pend} 은 옛 경로 유지) · baton·추가 파일 {ot}"


def preflight(ctx: Ctx, team: str, occ_snap: dict) -> None:
    src, dst = ctx.root / "design" / team, ctx.root / "design" / "teams" / team
    if not old_form(ctx.rows[team]):
        raise MoveError(f"REJECT {team} 이미 옮겼거나 이 도구 대상이 아니다: {ctx.rows[team]}")
    if not src.is_dir() or dst.exists():
        raise MoveError(f"REJECT {team} 원본 없음 또는 목적지 이미 있음: {src} → {dst}")
    if git(ctx, "diff", "--cached", "--name-only").strip():
        raise MoveError("REJECT 스테이징에 남의 변경이 있다 — 비운 뒤 다시")
    scope = [f"design/{team}", "design/TEAMS.md", ".gitignore"]
    if git(ctx, "status", "--porcelain", "--", *scope).strip():
        raise MoveError(f"REJECT 이동 대상({' '.join(scope)})에 미커밋 변경 또는 추적 안 된 파일이 있다")
    if occ_snap.get("deadline_exhausted"):
        raise Exhausted(team)
    if occ_snap["blocks"]:
        raise Unjudged("\n".join(occ_snap["blocks"]))
    occ = occupancy(ctx, team, occ_snap)
    if occ:
        raise MoveError("REJECT 점유 중 — 비운 뒤 다시:\n" + "\n".join(occ))


def resync_team(ctx: Ctx, team: str, snap: Snap) -> None:
    """이미 옮긴 팀의 저장 참조 재작성 — 그 사이 ft-head-sync 로 이동 커밋을 받은 워크트리의 `_move_pending` 행·카드 기준선을 새 경로로(멱등)."""
    step = new_step(team, [])
    snap.data["steps"].append(step)
    print(f"RESYNC {team} 이미 옮긴 팀 — 저장 참조만 다시 맞춘다(git 변경 0)")
    for fn in (roster_step, card_base_step, text_stores_step):
        print("STORE " + fn(ctx, team, snap, step))


def rollback(ctx: Ctx, team: str) -> None:
    """커밋 전 실패 — 선검사가 «이 범위 깨끗·스테이징 비어 있음» 을 보장했으니 이 팀 범위만 되돌린다(남의 변경 0)."""
    run("git", "reset", "-q", "--", f"design/{team}", f"design/teams/{team}", "design/TEAMS.md", ".gitignore", cwd=ctx.root)
    run("git", "checkout", "--", f"design/{team}", "design/TEAMS.md", ".gitignore", cwd=ctx.root)
    run("git", "clean", "-fdq", "--", f"design/teams/{team}", cwd=ctx.root)
    print(f"ROLLBACK {team} 커밋 전 실패 — 이 팀 범위를 원래대로 되돌렸다")


def rewrite_tracked(step: dict, kind: str, path: Path, old_path: Path, team: str) -> None:
    before = sha256(path)
    path.write_text(rewrite(path.read_text(encoding="utf-8"), team), encoding="utf-8")
    step["tracked"].append({"kind": kind, "path": str(path), "old_path": str(old_path), "before_sha": before, "after_sha": sha256(path), "commit": None, "revert_match": None})


def sync_worktrees(ctx: Ctx, deadline: float) -> bool:
    hs = Path(os.environ.get("FT_HEAD_SYNC") or Path(__file__).resolve().parent / "ft-head-sync.sh")
    left = deadline - time.monotonic()
    if left <= 0:
        print(f"ERROR ft-head-sync 공통 마감 {SYNC_DEADLINE_S:g}초 소진 — 부르지 않고 멈춘다")
        return False
    cap = min(sync_cap(ctx), left)
    try:
        done = run("bash", str(hs), "--apply", cwd=ctx.root, timeout=cap)
    except subprocess.TimeoutExpired:
        print(f"ERROR ft-head-sync {cap:g}초 초과(공통 마감 {SYNC_DEADLINE_S:g}초 중 잔여 {left:g}초)")
        return False
    print(f"SYNC rc={done.returncode} {(done.stdout.strip().splitlines() or [''])[-1][:160]}")
    return done.returncode == 0


def apply_team(ctx: Ctx, team: str, snap: Snap, deadline: float | None, take_occ: Callable[[], dict]) -> None:
    if not ctx.rows[team].startswith("design/"):
        print(f"SKIP {team} 폴더 칸이 design/ 밖 꼴: {ctx.rows[team]}")
        return
    if not old_form(ctx.rows[team]):
        if not received(ctx.root, team):
            raise MoveError(f"REJECT {team} 폴더 칸이 새 꼴인데 이 워크트리에 design/teams/{team}/ 가 없다: {ctx.rows[team]}")
        return resync_team(ctx, team, snap)
    preflight(ctx, team, take_occ())   # 이동 «직전» 점유 입력(앞 팀 이동 사이에 새로 연 프로세스를 잡는다)
    step = new_step(team, [f"{k} {v}" for k, v in refs(ctx, team)])
    snap.data["steps"].append(step)
    (ctx.root / "design" / "teams").mkdir(exist_ok=True)
    git(ctx, "mv", f"design/{team}", f"design/teams/{team}")
    moved = ctx.root / "design" / "teams" / team
    for p in sorted(moved.rglob("*")):
        if p.is_file() and not p.is_symlink() and hits(p, team):
            kind = "readme_map" if p.name.startswith("README") else "card_body"
            rewrite_tracked(step, kind, p, ctx.root / "design" / team / p.relative_to(moved), team)
    for extra in (ctx.root / "design" / "TEAMS.md", ctx.root / ".gitignore"):
        if hits(extra, team):
            rewrite_tracked(step, "readme_map", extra, extra, team)
    try:
        git(ctx, "add", "--", f"design/teams/{team}", "design/TEAMS.md", *([".gitignore"] if (ctx.root / ".gitignore").exists() else []))
        git(ctx, "commit", "-q", "-m", f"[structure] 팀 폴더 이동 {team}: design/{team}/ → design/teams/{team}/ (R382 ft-team-move)")
        step["commit"] = git(ctx, "rev-parse", "HEAD").strip()
        for t in step["tracked"]:
            t["commit"] = step["commit"]
    except MoveError:
        snap.data["steps"].remove(step)
        rollback(ctx, team)
        raise
    print(f"MOVED {team} design/{team}/ → design/teams/{team}/ commit={step['commit'][:12]}")
    if deadline is not None:
        if not sync_worktrees(ctx, deadline):
            snap.data["pending_teams"].append(team)
            raise Partial(team)
    else:
        print("HINT 다른 워크트리는 ft-head-sync.sh --apply 로 이 커밋을 받는다 — 받기 전 좌석은 _move_pending 표식 · 받은 뒤 같은 팀을 --apply 다시(저장 참조 재작성)")
    for fn in (roster_step, card_base_step, text_stores_step):
        print("STORE " + fn(ctx, team, snap, step))
    left = {k: v for k, v in refs(ctx, team)[2:] if k[0] in "3456"}
    print(f"AFTER 옛 경로 잔여 {left}")


def revert(ctx: Ctx, path: Path) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("root") != str(ctx.root):
        raise MoveError(f"REJECT 스냅샷의 리포 루트({data.get('root')})가 지금({ctx.root})과 다르다")
    first: dict[str, str] = {}
    for st in data["steps"]:
        for f in st["files"]:
            first.setdefault(f["path"], f["before_sha"])
    for st in reversed(data["steps"]):
        for f in reversed(st["files"]):
            shutil.copy2(f["backup"], f["path"])
            f["revert_match"] = sha256(Path(f["path"])) == f["before_sha"]
    err = None
    for st in reversed(data["steps"]):
        if st.get("commit"):
            done = run("git", "revert", "--no-edit", st["commit"], cwd=ctx.root)
            if done.returncode != 0:
                run("git", "revert", "--abort", cwd=ctx.root)
                err = f"ERROR git revert 실패({st['team']} {st['commit'][:12]}) — 그 뒤 커밋과 충돌: {done.stderr.strip()[:200]}"
                break
            print(f"REVERTED {st['team']} commit={st['commit'][:12]}")
            for t in st.get("tracked", []):
                old = Path(t["old_path"])
                t["revert_match"] = old.is_file() and sha256(old) == t["before_sha"]
    for st in data["steps"]:
        st["items"] = build_items(st)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")   # 대조 결과를 스냅샷에 남긴 «뒤» 실패를 올린다
    if err:
        raise MoveError(err)
    for p, sha in first.items():
        if sha256(Path(p)) != sha:
            raise MoveError(f"ERROR 복원 뒤 sha256 불일치: {p}")
    bad = [t["old_path"] for st in data["steps"] for t in st.get("tracked", []) if t["revert_match"] is not True]
    if bad:
        raise MoveError(f"ERROR git revert 뒤 sha256 불일치: {bad[0]}")
    print(f"REVERT-END 저장 참조 파일 {len(first)}개 sha256 일치 · 이동 커밋 파일 {sum(len(st.get('tracked', [])) for st in data['steps'])}개 일치")


def main(argv: list[str], ctx: Ctx) -> int:
    if argv[0] == "--revert":
        revert(ctx, Path(argv[1]))
        return 0
    deadline = time.monotonic() + SYNC_DEADLINE_S if "--sync-worktrees" in argv else None
    teams = list(ctx.rows) if argv[1] == "--all" else [argv[1]]
    if argv[1] != "--all" and argv[1] not in ctx.rows:
        raise MoveError(f"ERROR {argv[1]} 은 팀 명단(TEAMS.md)에 없다")
    snap, rc = Snap(ctx, "all" if argv[1] == "--all" else argv[1]), 0
    batch_end = deadline if deadline is not None else time.monotonic() + SYNC_DEADLINE_S   # 배치 총 마감(70초) — 점유 스냅샷·동기화가 같은 마감을 쓴다
    first = [occupancy_snapshot(batch_end)]   # 팀 루프 «전» 입력 검사 겸 첫 이동 팀의 스냅샷
    if first[0]["blocks"]:
        print("\n".join(first[0]["blocks"]))
        print("REJECT 점유 판정 불가 — 이동 0 · 팀별 판정 생략")
        return 1
    take_occ = lambda: first.pop() if first else occupancy_snapshot(batch_end)  # noqa: E731
    for team in teams:
        try:
            if old_form(ctx.rows[team]) and time.monotonic() >= batch_end:
                raise Exhausted(team)
            apply_team(ctx, team, snap, deadline, take_occ)
        except Exhausted:   # 공유 마감 소진(팀 시작 전이든 점유 재스냅샷 도중이든) = 그 팀부터 이동 전 중단 · 남은 팀은 pending_teams 에 기록
            rest = teams[teams.index(team):]
            snap.data["pending_teams"].extend(rest)
            print(f"PARTIAL {team} 배치 총 마감 {SYNC_DEADLINE_S:g}초 소진 — 이 팀부터 이동 전(처리 안 한 팀 {len(rest)}: {' '.join(rest)}) — 다음 --apply 가 이어간다(옮긴 팀은 RESYNC)")
            rc = 3
            break
        except Unjudged as e:
            print(f"{e}\nREJECT {team} 점유 판정 불가 — 남은 팀 판정 중단(처리 안 한 팀: {' '.join(teams[teams.index(team):])})")
            rc = 1
            break
        except Partial:
            rest = teams[teams.index(team) + 1:]
            print(f"PARTIAL {team} 이동 커밋은 끝 · 저장 참조는 쓰기 전에 멈춤(처리 안 한 팀 {len(rest)}: {' '.join(rest) or '-'}) — 다음 --apply {team} = RESYNC")
            rc = 3
            break
        except MoveError as e:
            print(str(e))
            rc = 1
            if argv[1] != "--all":
                break
        ctx.rows = dict(line.split("\t") for line in run("bash", "-c", '. "$1"; _ft_team_rows', "_", str(Path(__file__).resolve().parent / "ft-team-lib.sh"), env={"FT_REPO_ROOT": str(ctx.root)}).stdout.splitlines() if line)
    out = snap.save()
    print(f"SNAPSHOT {out}")
    return rc
