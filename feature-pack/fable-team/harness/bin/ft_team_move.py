#!/usr/bin/env python3
"""ft_team_move — 팀 폴더 design/<팀>/ → design/teams/<팀>/ 이동 도구의 읽기 쪽 (R382 · ft-team-move.sh 가 부른다).

--plan 은 쓰기 0(표만) · --verify 는 읽기 전용 · 쓰는 일(--apply·--revert)은 ft_team_move_apply.py.
팀 폴더 해석은 ft-team-lib.sh(TEAMS.md 폴더 칸 3꼴 · 단일 출처)를 «부른다» — 여기서 명단을 다시 파싱하지 않는다.
저장 참조 7종: ①팀 폴더 파일 ②TEAMS.md 폴더 칸 ③명부(.fable-team/seats-<팀>.json · v65=seats.json) ④nano-card-base ⑤worktree-info ⑥baton branches.json ⑦텍스트 참조(카드 본문·README 지도·.gitignore·추가 파일).
env: FT_REPO_ROOT(이동을 커밋할 워크트리) · FT_PROJECT_ROOT(.fable-team·.worktrees·.baton 이 있는 프로젝트 루트 · 기본 git 공용 루트) · FT_TEAM_MOVE_EXTRA(콜론 구분 추가 텍스트 파일) · FT_TEAM_MOVE_LSOF(기본 lsof) · FT_TEAM_MOVE_STATE
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

HERE = Path(__file__).resolve().parent
LIB = HERE / "ft-team-lib.sh"


class MoveError(RuntimeError):
    pass


def run(*cmd: str, cwd: Path | None = None, timeout: float = 7, env: dict | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(list(cmd), cwd=cwd, capture_output=True, text=True, timeout=timeout, env={**os.environ, **(env or {})})


def sha256(p: Path) -> str:
    import hashlib
    return hashlib.sha256(p.read_bytes()).hexdigest()


@dataclass
class Ctx:
    root: Path      # 이동을 커밋하는 워크트리(design/ 가 있는 곳)
    project: Path   # .fable-team · .worktrees · .baton 이 있는 프로젝트 루트
    rows: dict      # 팀 → TEAMS.md 폴더 칸 원문

    @property
    def state(self) -> Path:
        return Path(os.environ.get("FT_TEAM_MOVE_STATE") or self.project / ".fable-team" / "state" / "team-move")

    def worktrees(self) -> list[Path]:
        wd = self.project / ".worktrees"
        return sorted(p for p in wd.iterdir() if p.is_dir()) if wd.is_dir() else []

    def roster(self, team: str) -> Path:
        return self.project / ".fable-team" / ("seats.json" if team == "v65" else f"seats-{team}.json")

    def extras(self) -> list[Path]:
        return [Path(x) for x in os.environ.get("FT_TEAM_MOVE_EXTRA", "").split(":") if x]


def make_ctx() -> Ctx:
    git = lambda *a, cwd=None: run("git", *a, cwd=cwd).stdout.strip()  # noqa: E731
    root = Path(os.environ.get("FT_REPO_ROOT") or git("rev-parse", "--show-toplevel"))
    if not (root / "design").is_dir():
        raise MoveError(f"ERROR 리포 루트(design/)를 못 찾았다: {root}")
    common = git("rev-parse", "--path-format=absolute", "--git-common-dir", cwd=root)
    project = Path(os.environ.get("FT_PROJECT_ROOT") or (Path(common).parent if common else root))
    done = run("bash", "-c", '. "$1"; _ft_team_rows', "_", str(LIB), env={"FT_REPO_ROOT": str(root)})
    if done.returncode != 0:
        raise MoveError(done.stderr.strip() or "ERROR 팀 명단을 못 읽었다")
    rows = dict(line.split("\t") for line in done.stdout.splitlines() if line)
    return Ctx(root, project, rows)


def pick(ctx: Ctx, arg: str) -> list[str]:
    if arg == "--all":
        return list(ctx.rows)
    if arg not in ctx.rows:
        raise MoveError(f"ERROR {arg} 은 팀 명단(TEAMS.md)에 없다")
    return [arg]


def old_form(rel: str) -> bool:
    return rel.startswith("design/") and not rel.startswith("design/teams/")


def pat(team: str) -> re.Pattern:
    return re.compile(rf"(?<![A-Za-z0-9_])design/{re.escape(team)}/")


def hits(path: Path, team: str) -> int:
    try:
        return len(pat(team).findall(path.read_text(encoding="utf-8")))
    except (OSError, UnicodeDecodeError):
        return 0


def tracked(ctx: Ctx, team: str) -> list[Path]:
    out = run("git", "ls-files", "-z", "--", f"design/{team}", cwd=ctx.root).stdout
    return [ctx.root / p for p in out.split("\0") if p]


def received(wt: Path, team: str) -> bool:
    return (wt / "design" / "teams" / team).is_dir()


def refs(ctx: Ctx, team: str) -> list[tuple[str, str]]:
    ros, cb = ctx.roster(team), ctx.project / ".fable-team" / "state" / "nano-card-base"
    cards = [p for p in sorted(cb.glob("*.json")) if hits(p, team)] if cb.is_dir() else []
    infos = [w / ".worktree-info.json" for w in ctx.worktrees() if hits(w / ".worktree-info.json", team)]
    text = [p for p in tracked(ctx, team) if hits(p, team)]
    gi = ctx.root / ".gitignore"
    return [
        ("1 팀 폴더", f"파일 {len(tracked(ctx, team))}개 design/{team}/"),
        ("2 TEAMS.md", ctx.rows[team]),
        ("3 명부", f"{ros.name} 참조 {hits(ros, team)}곳" if ros.is_file() else f"{ros.name} 없음(건너뜀)"),
        ("4 nano-card-base", f"파일 {len(cards)}개"),
        ("5 worktree-info", f"파일 {len(infos)}개"),
        ("6 baton", f"branches.json 참조 {hits(ctx.project / '.baton' / 'branches.json', team)}곳"),
        ("7 텍스트", f"카드·README 등 {len(text)}파일 · .gitignore {hits(gi, team)}곳 · 추가 {sum(1 for p in ctx.extras() if hits(p, team))}파일"),
    ]


def occupancy(ctx: Ctx, team: str) -> list[str]:
    dirs = [ctx.root / "design" / team] + [w / "design" / team for w in ctx.worktrees()]
    out: list[str] = []
    tm = run("tmux", "list-panes", "-a", "-F", "#{session_name}\t#{pane_current_path}")
    if tm.returncode == 0:
        for line in tm.stdout.splitlines():
            sess, _, cwd = line.partition("\t")
            if any(cwd == str(d) or cwd.startswith(f"{d}/") for d in dirs):
                out.append(f"CWD {sess} {cwd}")
    elif "no server running" not in (tm.stderr + tm.stdout):
        out.append(f"BLOCK tmux 목록을 못 읽었다(rc={tm.returncode}) — 점유 판정 불가")
    lsof = os.environ.get("FT_TEAM_MOVE_LSOF", "lsof")
    for d in dirs:
        if not d.is_dir():
            continue
        try:
            ls = run(lsof, "+D", str(d), timeout=7)
        except subprocess.TimeoutExpired:
            out.append(f"BLOCK lsof +D {d} 7초 초과 — 점유 판정 불가")
            continue
        out += [f"LSOF {ln.split()[0]} pid={ln.split()[1]} {d}" for ln in ls.stdout.splitlines()[1:] if len(ln.split()) > 1]
    return out


def cmd_plan(ctx: Ctx, arg: str) -> int:
    blockers = 0
    for team in pick(ctx, arg):
        rel = ctx.rows[team]
        if not old_form(rel):
            print(f"SKIP {team} 이미 옮겼거나 이 도구 대상이 아니다: {rel}")
            continue
        src, dst = ctx.root / "design" / team, ctx.root / "design" / "teams" / team
        print(f"PLAN {team} design/{team}/ → design/teams/{team}/")
        for k, v in refs(ctx, team):
            print(f"  REF{k} {v}")
        bad = [] if src.is_dir() else [f"BLOCK 원본 폴더 없음: {src}"]
        bad += [f"BLOCK 목적지 이미 있음: {dst}"] if dst.exists() else []
        occ = occupancy(ctx, team)
        for ln in bad + occ:
            print(f"  {ln}")
        blockers += len(bad) + len(occ)
        for w in ctx.worktrees():
            print(f"  WT {w.name} {'받음' if received(w, team) else '미전환(_move_pending 후보)'}")
    print(f"PLAN-END blockers={blockers}")
    return 0


def cmd_verify(ctx: Ctx, arg: str) -> int:
    err = warn = 0
    env = {"FT_REPO_ROOT": str(ctx.root)}
    for team in pick(ctx, arg):
        rel = ctx.rows[team]
        if old_form(rel):
            print(f"SKIP {team} 아직 옛 꼴: {rel}")
            continue
        d = run("bash", "-c", '. "$1"; ft_team_root "$2"', "_", str(LIB), team, env=env)
        folder = Path(d.stdout.strip())
        if d.returncode != 0 or not folder.is_dir():
            print(f"ERR {team} 팀 폴더를 못 푼다/없다: {d.stderr.strip() or folder}")
            err += 1
            continue
        m = run("bash", str(HERE / "ft-team-map-lint.sh"), team, env=env)
        last = (m.stdout.strip().splitlines() or [""])[-1]
        if m.returncode != 0:
            print(f"ERR {team} map-lint: {last}")
            err += 1
        err += check_stores(ctx, team)
        left = [p for p in folder.rglob("*") if p.is_file() and hits(p, team)]
        for p in left:
            shown = p.relative_to(ctx.root) if p.is_relative_to(ctx.root) else p   # 꼴3 팀 폴더는 리포 밖
            print(f"WARN {team} 잔여 옛 경로 design/{team}/ : {shown}")
            warn += 1
    up = run("bash", str(HERE / "ft-team-upgrade.sh"), "--check-teams", env=env)
    if up.returncode != 0:
        print(f"ERR 팀 집합: {up.stdout.strip()}")
        err += 1
    print(f"VERIFY ERR={err} WARN={warn}")
    return 1 if err else 0


def check_stores(ctx: Ctx, team: str) -> int:
    err = 0
    ros = ctx.roster(team)
    if ros.is_file():
        try:
            data = json.loads(ros.read_text(encoding="utf-8"))
        except ValueError as e:
            print(f"ERR {team} 명부 JSON 깨짐 {ros}: {e}")
            return 1
        for seat, row in data.items():
            if seat.startswith("_") or not isinstance(row, dict) or not str(row.get("index", "")).startswith("design/"):
                continue
            base = ctx.project / ".worktrees" / row["worktree"] if row.get("worktree") else ctx.root
            if not (base / row["index"]).exists() and not (row.get("_move_pending") and (base / row["index"]).exists()):
                print(f"ERR {team} 명부 {seat} index 실재 안 함: {row['index']} (기준 {base.name})")
                err += 1
    cb = ctx.project / ".fable-team" / "state" / "nano-card-base"
    for p in sorted(cb.glob("*.json")) if cb.is_dir() else []:
        try:
            row = json.loads(p.read_text(encoding="utf-8"))
        except ValueError:
            continue
        cp = str(row.get("card_path", ""))
        if (cp.startswith(f"design/teams/{team}/") or cp.startswith(f"design/{team}/")) and not (Path(row.get("worktree", ctx.root)) / cp).exists():
            print(f"ERR {team} nano-card-base {p.name} card_path 실재 안 함: {cp}")
            err += 1
    return err


def main(argv: list[str]) -> int:
    if len(argv) < 2 or argv[0] not in ("--plan", "--verify", "--apply", "--revert"):
        print("usage: ft-team-move.sh (--plan|--apply|--verify) (<팀>|--all) [--sync-worktrees] | --revert <스냅샷.json>", file=sys.stderr)
        return 2
    try:
        if argv[0] in ("--apply", "--revert"):
            import ft_team_move_apply as ap
            return ap.main(argv, make_ctx())
        ctx = make_ctx()
        return (cmd_plan if argv[0] == "--plan" else cmd_verify)(ctx, argv[1])
    except MoveError as e:
        print(str(e) if str(e).startswith(("ERROR", "REJECT")) else f"ERROR {e}")
        return 1
    except subprocess.TimeoutExpired as e:
        print(f"ERROR 외부 호출 {e.timeout:g}초 초과(7초 룰): {' '.join(map(str, e.cmd))[:160]}")
        return 1


if __name__ == "__main__":
    sys.path.insert(0, str(HERE))
    sys.exit(main(sys.argv[1:]))
