#!/usr/bin/env python3
"""ft_team_move — 팀 폴더 design/<팀>/ → design/teams/<팀>/ 이동 도구의 읽기 쪽 (R382 · ft-team-move.sh 가 부른다).

--plan 은 쓰기 0(표만) · --verify 는 읽기 전용 · 쓰는 일(--apply·--revert)은 ft_team_move_apply.py.
팀 폴더 해석은 ft-team-lib.sh(TEAMS.md 폴더 칸 3꼴 · 단일 출처)를 «부른다» — 여기서 명단을 다시 파싱하지 않는다.
저장 참조 7종: ①팀 폴더 파일 ②TEAMS.md 폴더 칸 ③명부(.fable-team/seats-<팀>.json · v65=seats.json) ④nano-card-base ⑤worktree-info ⑥baton branches.json ⑦텍스트 참조(카드 본문·README 지도·.gitignore·추가 파일).
env: FT_REPO_ROOT(이동을 커밋할 워크트리) · FT_PROJECT_ROOT(.fable-team·.worktrees·.baton 이 있는 프로젝트 루트 · 기본 git 공용 루트) · FT_TEAM_MOVE_EXTRA(콜론 구분 추가 텍스트 파일) · FT_TEAM_MOVE_LSOF(기본 lsof) · FT_TEAM_MOVE_STATE
r587: 코드·시험 안에 박헌 옛 경로(design/<팀>/)도 읽는다 — --verify 는 ERR, --plan 은 BEFORE code-ref 줄 · 기록(archive·evidence·closeout·.claude/archives)은 셈 밖 · 자동 재작성 0.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from bisect import bisect_left, bisect_right
from dataclasses import dataclass
from pathlib import Path

HERE = Path(__file__).resolve().parent
LIB = HERE / "ft-team-lib.sh"
CODE_GLOBS = ("*.py", "*.sh", "*.ts", "*.tsx", "*.js", "*.json", "*.toml", "*.yaml")   # r587: 옛 경로를 훑는 «코드·시험» 꼴
RECORD_DIRS = ("archive", "evidence", "closeout")   # r587: 이동 뒤 기록 폴더 = 옛 경로가 남아도 셈 밖


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


def is_record(rel: str, team: str) -> bool:
    """기록 안 파일인가 — design/teams/<팀>/{archive,evidence,closeout}/** · design/teams/<팀>/CLOSEOUT* · .claude/archives/** (r587 · 옛 경로가 남아 있어도 셈 밖)."""
    parts = rel.split("/")
    if len(parts) > 2 and parts[0] == ".claude" and parts[1] == "archives":
        return True
    if len(parts) < 4 or parts[:3] != ["design", "teams", team]:
        return False
    return parts[3] in RECORD_DIRS or parts[3].startswith("CLOSEOUT")


def code_refs(ctx: Ctx, team: str) -> list[tuple[str, int]]:
    """코드·시험 안에 박힌 옛 경로 `design/<팀>/` — (경로, 줄) 정렬 목록 (r587 · 읽기만 · 자동 재작성 0).
    git grep 1회(7초 룰) · CODE_GLOBS 만 · 기록(archive·evidence·closeout·.claude/archives)은 셈 밖."""
    g = run("git", "grep", "-n", "-F", "-e", f"design/{team}/", "--", *CODE_GLOBS, cwd=ctx.root)
    if g.returncode not in (0, 1):   # 1 = 히트 0 · 그 밖 = 검색 실패(조용한 통과 0)
        raise MoveError(f"ERROR {team} 코드·시험 옛 경로 검색 실패(rc={g.returncode}): {g.stderr.strip()[:160]}")
    out: list[tuple[str, int]] = []
    for line in g.stdout.splitlines():
        path, _, rest = line.partition(":")
        no, _, _ = rest.partition(":")
        if no.isdigit() and not is_record(path, team):
            out.append((path, int(no)))
    return sorted(set(out))


def tracked(ctx: Ctx, team: str) -> list[Path]:
    out = run("git", "ls-files", "-z", "--", f"design/{team}", cwd=ctx.root).stdout
    return [ctx.root / p for p in out.split("\0") if p]


def received(wt: Path, team: str) -> bool:
    return (wt / "design" / "teams" / team).is_dir()


def store_base(ctx: Ctx, data: dict, row: object) -> Path:
    """명부 행의 «받음» 기준 워크트리 = 행 worktree 칸 → 명부 머리 _cards_wt → 프로젝트 루트.
    ctx.root(이동 커밋 워크트리)는 쓰지 않는다 — 거기엔 design/teams/<팀>/ 가 «항상» 있어 받음 판정이 무의미하다(R391)."""
    name = (row.get("worktree") if isinstance(row, dict) else None) or data.get("_cards_wt")
    return ctx.project / ".worktrees" / name if name else ctx.project


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


def open_files(lsof_out: str) -> list[tuple[str, str, str]]:
    """`lsof -Fpcn` 출력 → (명령, pid, 열린 경로) — p/c 는 프로세스 줄, n 은 그 프로세스의 열린 파일마다 한 줄."""
    pid = cmd = ""
    files = []
    for ln in lsof_out.splitlines():
        key, val = ln[:1], ln[1:]
        if key == "p":
            pid = val
        elif key == "c":
            cmd = (val.split() or [val])[0]
        elif key == "n" and val.startswith("/"):
            files.append((cmd, pid, val))
    return files


def occupancy_snapshot(deadline: float | None = None) -> dict:
    """점유 판정 입력 — tmux pane cwd 1회 + lsof 열린 파일 전체 1회(팀·워크트리 수와 무관 · 호출당 7초 · deadline = 배치 총 마감(monotonic)이 있으면 잔여만큼만)."""
    snap: dict = {"panes": [], "files": [], "names": [], "blocks": [], "deadline_exhausted": False}
    cap = lambda: 7.0 if deadline is None else min(7.0, deadline - time.monotonic())  # noqa: E731
    # 시간 초과 구분 — 호출당 7초가 한도였으면 BLOCK(점유 판정 불가) · 배치 마감 잔여(< 7초)가 한도였으면 마감 소진(호출자가 이동 전 PARTIAL)
    t = cap()
    try:
        if t <= 0:
            snap["deadline_exhausted"] = True
            return snap
        tm = run("tmux", "list-panes", "-a", "-F", "#{session_name}\t#{pane_current_path}", timeout=t)
        if tm.returncode == 0:
            snap["panes"] = [tuple(line.partition("\t")[::2]) for line in tm.stdout.splitlines()]
        elif "no server running" not in (tm.stderr + tm.stdout):
            snap["blocks"].append(f"BLOCK tmux 목록을 못 읽었다(rc={tm.returncode}) — 점유 판정 불가")
    except subprocess.TimeoutExpired:
        if t < 7.0:
            snap["deadline_exhausted"] = True
            return snap
        snap["blocks"].append("BLOCK tmux 목록 7초 초과 — 점유 판정 불가")
    t = cap()
    try:
        if t <= 0:
            snap["deadline_exhausted"] = True
            return snap
        ls = run(os.environ.get("FT_TEAM_MOVE_LSOF", "lsof"), "-nP", "-Fpcn", timeout=t)
    except subprocess.TimeoutExpired:
        if t < 7.0:
            snap["deadline_exhausted"] = True
            return snap
        snap["blocks"].append("BLOCK lsof 7초 초과 — 점유 판정 불가")
    except OSError as e:
        snap["blocks"].append(f"BLOCK lsof 를 실행하지 못했다({e}) — 점유 판정 불가")
    else:
        snap["files"] = sorted(open_files(ls.stdout), key=lambda f: f[2])
        snap["names"] = [f[2] for f in snap["files"]]
        if not snap["files"]:   # 종료 코드와 무관 — 실행 중인 프로세스는 항상 열린 파일이 있다 · 레코드 0 = 관찰 실패
            snap["blocks"].append(f"BLOCK lsof 열린 파일 레코드 0(rc={ls.returncode}) — 점유 판정 불가")
    return snap


def occupancy(ctx: Ctx, team: str, snap: dict | None = None) -> list[str]:
    snap = snap or occupancy_snapshot()
    dirs = [ctx.root / "design" / team] + [w / "design" / team for w in ctx.worktrees()]
    out = [f"CWD {sess} {cwd}" for sess, cwd in snap["panes"] if any(cwd == str(d) or cwd.startswith(f"{d}/") for d in dirs)]
    out += snap["blocks"]
    labels: dict[str, Path] = {}
    for d in filter(Path.is_dir, dirs):
        labels[str(d)] = d
        labels.setdefault(os.path.realpath(d), d)
    names, files = snap["names"], snap["files"]
    for path, d in labels.items():   # 정렬된 경로에서 «그 폴더 자신 + 그 폴더 아래» 구간만 이분탐색 — 경로 문자열 사전 필터 0
        hit = files[bisect_left(names, path):bisect_right(names, path)] + files[bisect_left(names, path + "/"):bisect_left(names, path + "0")]
        out += [f"LSOF {cmd} pid={pid} {d}" for cmd, pid, _ in hit]
    return out


def cmd_plan(ctx: Ctx, arg: str) -> int:
    blockers = 0
    snap = occupancy_snapshot()
    if snap["blocks"]:   # 점유 입력을 못 얻으면 팀 루프 «전» 한 번만 알리고 끝낸다(13팀 반복 0 · «통과» 로 안 보임)
        print("\n".join(snap["blocks"]))
        print("PLAN-END 점유 판정 불가 — 팀별 판정 생략")
        return 1
    for team in pick(ctx, arg):
        rel = ctx.rows[team]
        if not old_form(rel):
            import ft_team_move_twin as tw   # r447: 쌍둥이 공존이면 병합 이동 계획 1줄 + 점유
            line = tw.plan_line(ctx, team) if rel.startswith("design/teams/") else None
            print(line or f"SKIP {team} 이미 옮겼거나 이 도구 대상이 아니다: {rel}")
            occ = occupancy(ctx, team, snap) if line else []
            for ln in occ:
                print(f"  {ln}")
            blockers += len(occ)
            continue
        src, dst = ctx.root / "design" / team, ctx.root / "design" / "teams" / team
        print(f"PLAN {team} design/{team}/ → design/teams/{team}/")
        for k, v in refs(ctx, team):
            print(f"  REF{k} {v}")
        crefs = code_refs(ctx, team)   # r587: 이동 전에 고칠 코드·시험 목록도 blockers 로 센다
        print(f"  BEFORE {team} code-ref {len(crefs)}")
        blockers += len(crefs)
        bad = [] if src.is_dir() else [f"BLOCK 원본 폴더 없음: {src}"]
        bad += [f"BLOCK 목적지 이미 있음: {dst}"] if dst.exists() else []
        occ = occupancy(ctx, team, snap)
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
        crefs = code_refs(ctx, team)   # r587: 코드·시험 안 옛 경로 = ERR(기록은 셈 밖)
        for path, no in crefs:
            print(f"ERR {team} 코드 옛 경로 design/{team}/ : {path}:{no}")
        err += len(crefs)
        left = [p for p in folder.rglob("*") if p.is_file() and hits(p, team)
                and not (p.is_relative_to(ctx.root) and is_record(str(p.relative_to(ctx.root)), team))]
        for p in left:
            shown = p.relative_to(ctx.root) if p.is_relative_to(ctx.root) else p   # 꼴3 팀 폴더는 리포 밖
            print(f"WARN {team} 잔여 옛 경로 design/{team}/ : {shown}")
            warn += 1
        twin = tracked(ctx, team)   # r447: 쌍둥이 공존(옛 폴더 추적 파일 잔존) — 병합 이동 안내
        if twin:
            print(f"WARN {team} 쌍둥이 옛 폴더 design/{team}/ 추적 파일 {len(twin)}개 — ft-team-move.sh --apply {team}")
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
            base = store_base(ctx, data, row)
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
        if (cp.startswith(f"design/teams/{team}/") or cp.startswith(f"design/{team}/")) and not (Path(row.get("worktree") or ctx.project) / cp).exists():
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
