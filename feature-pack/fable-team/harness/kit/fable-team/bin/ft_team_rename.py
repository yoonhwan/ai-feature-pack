#!/usr/bin/env python3
"""ft_team_rename — 팀 «이름» 바꾸기 design/teams/<옛>/ → design/teams/<새>/ (r468 · ft-team-rename.sh 가 부른다).

이동 도구(ft_team_move·ft_team_move_apply)의 Ctx·점유·스냅샷·revert·명부 기준 워크트리 판정을 그대로 쓴다(복제 0).
--plan   표만(쓰기 0) · 끝줄 PLAN-END blockers=<n>
--apply  선검사 → 스냅샷(.fable-team/state/team-rename/<ts>-<옛>-<새>/) → git mv + TEAMS/TEAMSET 행 + 본문 치환(패턴 2) + TEAMS 각주 → 한 커밋
         → 명부 seats-<옛>.json → seats-<새>.json(+.bak-rename-<ts> · 행 이름 불변 · _renamed_from) → nano-card-base·worktree-info·baton·추가 파일 → env bin-<옛>/ → bin-<새>/ → AFTER
         명단에 <새> 만 있고 명부에 _renamed_from=<옛> 이면 = RESYNC(받은 워크트리의 _move_pending 만 다시 · git 변경 0)
--verify <새>  읽기 전용 · ERR(명단·폴더·명부 index·옛 자리 잔존·팀 집합) + 잔여 «<옛>» 글자 WARN · 끝줄 VERIFY ERR=<n> WARN=<m>
--revert <스냅샷.json>  만든 파일 지움 → 저장 파일 바이트 복원 + git revert(이동 도구 revert)
watch <mbox.sh> <명부>...  틱 전용 — _renamed_from 이 7일 안인 명부의 옛 계보 우편 peek → `PENDING<TAB>_master<TAB>옛 좌석<TAB>건수` 줄
치환 패턴: 팀 폴더 본문·TEAMS 행 = `design/teams/<옛>/` · `byz-<옛>-` 둘뿐 · 명부 경로 칸 = 폴더 경로만(좌석 이름 0) · env·명부 _doc = 아래 STORE 패턴.
env: 이동 도구와 같음(FT_REPO_ROOT · FT_PROJECT_ROOT · FT_TEAM_MOVE_EXTRA · FT_TEAM_MOVE_LSOF) + FT_TEAM_RENAME_STATE · FT_RENAME_WATCH_DAYS(7)
"""
from __future__ import annotations

import datetime
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))   # python3 -I 는 스크립트 폴더를 path 에 넣지 않는다 — 형제 이동 모듈 import 전에
from ft_team_move import Ctx, MoveError, check_stores, make_ctx, occupancy, occupancy_snapshot, received, run, sha256, store_base, tracked  # noqa: E402
from ft_team_move_apply import Snap, dump_like, git, new_step, walk, write_text  # noqa: E402
from ft_team_move_apply import revert as move_revert  # noqa: E402

NAME = re.compile(r"[a-z0-9][a-z0-9_-]*")
B = r"(?<![A-Za-z0-9_])"


class RCtx(Ctx):
    @property
    def state(self) -> Path:
        return Path(os.environ.get("FT_TEAM_RENAME_STATE") or self.project / ".fable-team" / "state" / "team-rename")


def path_subs(o: str, n: str) -> list:
    e = re.escape(o)
    return [(re.compile(rf"{B}design/teams/{e}/"), f"design/teams/{n}/"), (re.compile(rf"{B}design/{e}/"), f"design/teams/{n}/")]


def body_subs(o: str, n: str) -> list:
    return path_subs(o, n)[:1] + [(re.compile(rf"(?<![A-Za-z0-9_-])byz-{re.escape(o)}-"), f"byz-{n}-")]


def store_subs(o: str, n: str, names: dict[str, str]) -> list:
    e = re.escape(o)
    return body_subs(o, n) + path_subs(o, n)[1:] + [
        (re.compile(rf"{B}seats-{e}\.json"), f"seats-{n}.json"), (re.compile(rf"{B}bin-{e}/"), f"bin-{n}/"),
        (re.compile(rf"@zc_{e}_active"), f"@zc_{n}_active"), (re.compile(rf"(FT_NANO_WT_PREFIX=['\"]?){e}-"), rf"\g<1>{n}-"),
        (re.compile(rf"{B}ft-tick-{e}(?![A-Za-z0-9_])"), f"ft-tick-{n}"), (re.compile(rf"(?<![A-Za-z0-9_./-]){e} 팀"), f"{n} 팀"),
    ] + [(re.compile(rf"(?<![A-Za-z0-9_.-]){re.escape(a)}(?![A-Za-z0-9_])"), b) for a, b in names.items()]


def sub_all(text: str, subs: list) -> tuple[str, int]:
    total = 0
    for rx, rep in subs:
        text, k = rx.subn(rep, text)
        total += k
    return text, total


def word(o: str) -> re.Pattern:
    return re.compile(rf"(?i)(?<![a-z0-9]){re.escape(o)}(?![a-z0-9])")


def rename_base(name: str, o: str, n: str) -> str:
    return word(o).sub(n, name)


def read(p: Path) -> str | None:
    try:
        return p.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None


def first_cell(line: str) -> str:
    return line.split("|")[1].strip() if line.startswith("|") and line.count("|") > 2 else ""


def rename_rows(text: str, o: str, n: str, extra: list) -> tuple[str, int]:
    out, k = [], 0
    for ln in text.split("\n"):
        if first_cell(ln) == o:
            cells = ln.split("|")
            cells[1] = cells[1].replace(o, n)
            ln = sub_all("|".join(cells), extra)[0]
            k += 1
        out.append(ln)
    return "\n".join(out), k


def env_dir(ctx: Ctx, team: str) -> Path:
    return ctx.project / ".fable-team" / f"bin-{team}"


def env_files(ctx: Ctx, o: str) -> list[Path]:
    d = env_dir(ctx, o)
    return sorted(p for p in d.rglob("*") if p.is_file()) if d.is_dir() else []


def blockers(ctx: Ctx, o: str, n: str, snap: dict) -> list[str]:
    if not NAME.fullmatch(n) or o == n or "v65" in (o, n):
        return [f"BLOCK 새 이름이 팀 이름 꼴이 아니거나 같거나 v65(seats.json 고정): {o} → {n}"]
    if o not in ctx.rows:
        return [f"BLOCK {o} 은 팀 명단(TEAMS.md)에 없다(옛 이름 없음)"]
    bad = [f"BLOCK {n} 은 이미 팀 명단(TEAMS.md)에 있다"] if n in ctx.rows else []
    rel = ctx.rows[o]
    if rel != f"design/teams/{o}/":
        bad.append(f"BLOCK {o} 폴더 칸이 design/teams/{o}/ 꼴이 아니다({rel}) — 옛 꼴은 먼저 ft-team-move.sh --apply {o} · 하네스 팩 꼴은 대상 밖")
    if tracked(ctx, o):
        bad.append(f"BLOCK {o} 쌍둥이(옛 꼴 design/{o}/ 추적 파일 {len(tracked(ctx, o))}개) — 먼저 ft-team-move.sh --apply {o}(rename 안에서 이동 0)")
    src, dst = ctx.root / "design" / "teams" / o, ctx.root / "design" / "teams" / n
    bad += [] if src.is_dir() else [f"BLOCK 원본 폴더 없음: {src}"]
    bad += [f"BLOCK 목적지 이미 있음: {p}" for p in (dst, ctx.roster(n), env_dir(ctx, n)) if p.exists()]
    if git(ctx, "diff", "--cached", "--name-only").strip():
        bad.append("BLOCK 스테이징에 남의 변경이 있다 — 비운 뒤 다시")
    scope = [f"design/teams/{o}", "design/TEAMS.md", "design/TEAMSET.md"]
    if git(ctx, "status", "--porcelain", "--", *scope).strip():
        bad.append(f"BLOCK 작업 트리 더러움({' '.join(scope)}) — 커밋한 뒤 다시")
    bad += snap["blocks"] + (["BLOCK 배치 마감 소진 — 점유 판정 불가"] if snap.get("deadline_exhausted") else [])
    return bad + occupancy(ctx, f"teams/{o}", snap)   # occupancy 는 design/<인자> 를 본다 — teams/<옛> = 지금 폴더


def roster_pass(ctx: Ctx, data: dict, o: str, n: str, names: dict[str, str]) -> tuple[int, int]:
    """경로 칸만 치환 — 행의 «받음» 기준 워크트리(store_base)에 design/teams/<새>/ 가 있으면 새 경로 · 없으면 _move_pending(이동 도구와 같은 규칙)."""
    done = pend = 0
    for k, v in list(data.items()):
        if k in ("_name", "_label"):
            new = word(o).sub(lambda m: n.upper() if m.group().isupper() else n, v) if isinstance(v, str) else v
        elif k == "_doc":
            new = sub_all(v, store_subs(o, n, names))[0] if isinstance(v, str) else v
        else:
            new = walk(v, lambda s: sub_all(s, path_subs(o, n))[0])
            if new != v and not received(store_base(ctx, data, v), n):
                if isinstance(v, dict):
                    v["_move_pending"] = f"design/teams/{n}/"
                    pend += 1
                continue
            if isinstance(new, dict):
                new.pop("_move_pending", None)
        done += new != v
        data[k] = new
    return done, pend


def plan(ctx: Ctx, o: str, n: str) -> int:
    snap = occupancy_snapshot()
    bad = blockers(ctx, o, n, snap)
    if o not in ctx.rows:
        print("\n".join(bad) + "\nPLAN-END blockers=1")
        return 1
    files = [p for p in (ctx.root / "design" / "teams" / o).rglob("*") if p.is_file() and not p.is_symlink()]
    k = [sum(len(rx.findall(read(p) or "")) for p in files) for rx, _ in body_subs(o, n)]
    md = {f: read(ctx.root / "design" / f) or "" for f in ("TEAMS.md", "TEAMSET.md")}
    print(f"PLAN-RENAME {o} → {n} design/teams/{o}/ → design/teams/{n}/")
    for f, t in md.items():
        print(f"  ROW {f} {' / '.join(ln for ln in t.split(chr(10)) if first_cell(ln) == o) or '행 없음'}")
    print(f"  REF1 팀 폴더 파일 {len(files)}개 · 본문 치환 예상 design/teams/{o}/ {k[0]}곳 · byz-{o}- {k[1]}곳")
    ros = ctx.roster(o)
    data = json.loads(read(ros) or "{}") if ros.is_file() else {}
    cells = [c for c in ("_name", "_label", "_tree", "_doc") if c in data]
    print(f"  REF3 명부 {ros.name} → {ctx.roster(n).name} 칸 {len(cells)}({'·'.join(cells)}) · 행 {sum(1 for x in data if not x.startswith('_'))}" if data else f"  REF3 명부 {ros.name} 없음(건너뜀)")
    cb = ctx.project / ".fable-team" / "state" / "nano-card-base"
    rx = path_subs(o, n)[0][0]
    print(f"  REF4 nano-card-base 파일 {sum(1 for p in cb.glob('*.json') if rx.search(read(p) or '')) if cb.is_dir() else 0}개")
    wts = ctx.worktrees()
    print(f"  REF5 worktree-info 파일 {sum(1 for w in wts if rx.search(read(w / '.worktree-info.json') or ''))}개")
    print(f"  REF6 baton branches.json 참조 {len(rx.findall(read(ctx.project / '.baton' / 'branches.json') or ''))}곳")
    print(f"  REF7 추가 파일 {sum(1 for p in ctx.extras() if rx.search(read(p) or ''))}개")
    ef = env_files(ctx, o)
    print(f"  ENV {env_dir(ctx, o).name}/ → bin-{n}/ 파일 {len(ef)}개 · 이름 바뀜 {sum(1 for p in ef if rename_base(p.name, o, n) != p.name)}" if ef else f"  ENV bin-{o}/ 없음(건너뜀)")
    print(f"  WT 받음 {sum(1 for w in wts if received(w, n))} · 미전환(_move_pending 후보) {sum(1 for w in wts if not received(w, n))}")
    for ln in bad:
        print(f"  {ln}")
    print(f"PLAN-END blockers={len(bad)}")
    return 0


def track(step: dict, kind: str, path: Path, old: Path, text: str) -> None:
    before = sha256(path)
    path.write_text(text, encoding="utf-8")
    step["tracked"].append({"kind": kind, "path": str(path), "old_path": str(old), "before_sha": before, "after_sha": sha256(path), "commit": None, "revert_match": None})


def commit(ctx: Ctx, o: str, n: str, step: dict) -> None:
    today = datetime.date.today().isoformat()
    git(ctx, "mv", f"design/teams/{o}", f"design/teams/{n}")
    moved = ctx.root / "design" / "teams" / n
    for p in sorted(moved.rglob("*")):
        t = read(p) if p.is_file() and not p.is_symlink() else None
        new, k = sub_all(t, body_subs(o, n)) if t is not None else ("", 0)
        if k:
            track(step, "readme_map" if p.name.startswith("README") else "card_body", p, ctx.root / "design" / "teams" / o / p.relative_to(moved), new)
    for f in ("TEAMS.md", "TEAMSET.md"):
        p = ctx.root / "design" / f
        new, k = rename_rows(read(p) or "", o, n, body_subs(o, n))
        if f == "TEAMS.md":
            new = new.rstrip("\n") + f"\n\n- 옛 이름 {o} → {n}(개명 {today} · r468 ft-team-rename · 좌석 계보 byz-{o}-* 는 은퇴)\n"
        if k:
            track(step, "readme_map", p, p, new)
    git(ctx, "add", "--", f"design/teams/{n}", "design/TEAMS.md", "design/TEAMSET.md")
    git(ctx, "commit", "-q", "-m", f"[structure] 팀 이름 바꾸기 {o} → {n}: design/teams/{o}/ → design/teams/{n}/ · TEAMS/TEAMSET 행 (r468 ft-team-rename)")
    step["commit"] = git(ctx, "rev-parse", "HEAD").strip()
    for t in step["tracked"]:
        t["commit"] = step["commit"]


def rollback(ctx: Ctx, o: str, n: str) -> None:
    run("git", "reset", "-q", "--", f"design/teams/{o}", f"design/teams/{n}", "design/TEAMS.md", "design/TEAMSET.md", cwd=ctx.root)
    run("git", "checkout", "--", f"design/teams/{o}", "design/TEAMS.md", "design/TEAMSET.md", cwd=ctx.root)
    run("git", "clean", "-fdq", "--", f"design/teams/{n}", cwd=ctx.root)
    print(f"ROLLBACK {o} 커밋 전 실패 — 이 범위를 원래대로 되돌렸다")


def create(snap: Snap, step: dict, old: Path, new: Path, text: str | None, kind: str) -> None:
    """옛 파일 → 새 이름 파일(text 가 None 이면 바이트 그대로) · 옛 파일은 스냅샷 백업 뒤 지운다."""
    new.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(old, new)
    if text is not None:
        new.write_text(text, encoding="utf-8")
    snap.backup(step, old, kind)
    step["files"][-1].update(after_sha=sha256(new), renamed_to=str(new))
    snap.data["created"].append(str(new))
    old.unlink()


def stores(ctx: Ctx, o: str, n: str, snap: Snap, step: dict, resync: bool) -> None:
    ts = f"{datetime.datetime.now():%Y%m%d-%H%M%S}"
    names = {p.name: rename_base(p.name, o, n) for p in env_files(ctx, o) if rename_base(p.name, o, n) != p.name}
    src = ctx.roster(n if resync else o)
    if src.is_file():
        raw = src.read_text(encoding="utf-8")
        data = json.loads(raw)
        done, pend = roster_pass(ctx, data, o, n, names)
        if not resync:
            data.update(_renamed_from=o, _renamed_at=datetime.date.today().isoformat())
            bak = src.with_name(f"{src.name}.bak-rename-{ts}")
            shutil.copy2(src, bak)
            snap.data["created"].append(str(bak))
            create(snap, step, src, ctx.roster(n), dump_like(raw, data), "roster")
        elif dump_like(raw, data) != raw:
            write_text(snap, step, src, dump_like(raw, data), "roster")
        print(f"STORE roster {src.name} → {ctx.roster(n).name} 칸 재작성 {done} · 미전환 표식 {pend}")
    rx, cb, k = path_subs(o, n)[0][0], ctx.project / ".fable-team" / "state" / "nano-card-base", [0, 0, 0, 0]
    for p in sorted(cb.glob("*.json")) if cb.is_dir() else []:
        row = json.loads(read(p) or "{}")
        if not rx.search(str(row.get("card_path", ""))):
            continue
        if received(Path(row.get("worktree") or ctx.project), n):
            row["card_path"] = rx.sub(f"design/teams/{n}/", row["card_path"])
            row.pop("_move_pending", None)
            k[0] += 1
        else:
            row["_move_pending"] = f"design/teams/{n}/"
        write_text(snap, step, p, json.dumps(row, ensure_ascii=False, indent=2) + "\n", "nano_card_base")
    others = [(w / ".worktree-info.json", "worktree_info", w) for w in ctx.worktrees()]
    others += [(ctx.project / ".baton" / "branches.json", "baton", None)] + [(p, "home_boot_guide", None) for p in ctx.extras()]
    for p, kind, wt in others:
        t = read(p) if p.is_file() else None
        if t and rx.search(t) and (wt is None or received(wt, n)):
            write_text(snap, step, p, rx.sub(f"design/teams/{n}/", t), kind)
            k[1 if kind == "worktree_info" else 2] += 1
    print(f"STORE nano-card-base 재작성 {k[0]} · worktree-info {k[1]} · baton·추가 파일 {k[2]}")
    if resync:
        return
    for p in env_files(ctx, o):
        rel = p.relative_to(env_dir(ctx, o))
        t = read(p)
        new = sub_all(t, store_subs(o, n, names))[0] if t is not None else None
        create(snap, step, p, env_dir(ctx, n) / rel.parent / names.get(p.name, p.name), new, "env")
        k[3] += 1
    for d in sorted((x for x in env_dir(ctx, o).rglob("*") if x.is_dir()), key=lambda x: -len(x.parts)) if env_dir(ctx, o).is_dir() else []:
        d.rmdir()
    if env_dir(ctx, o).is_dir():
        env_dir(ctx, o).rmdir()
        snap.data["created_dirs"].append(str(env_dir(ctx, n)))
    print(f"STORE env bin-{o}/ → bin-{n}/ 파일 {k[3]} · 이름 바뀜 {len(names)}")


def apply(ctx: Ctx, o: str, n: str) -> int:
    ros_new = ctx.roster(n)
    resync = o not in ctx.rows and n in ctx.rows and ros_new.is_file() and json.loads(ros_new.read_text(encoding="utf-8")).get("_renamed_from") == o
    if not resync:
        bad = blockers(ctx, o, n, occupancy_snapshot())
        if bad:
            raise MoveError("REJECT 쓰기 0 — 선검사:\n" + "\n".join(bad))
    snap = Snap(ctx, f"{o}-{n}")
    snap.data.update(created=[], created_dirs=[], rename={"old": o, "new": n})
    step = new_step(n, [])
    snap.data["steps"].append(step)
    if resync:
        print(f"RESYNC {o} → {n} 이미 바꾼 팀 — 받은 워크트리의 저장 참조만 다시(git 변경 0)")
    else:
        try:
            commit(ctx, o, n, step)
        except MoveError:
            snap.data["steps"].remove(step)
            rollback(ctx, o, n)
            raise
        print(f"RENAMED {o} → {n} commit={step['commit'][:12]}")
    stores(ctx, o, n, snap, step, resync)
    left = [str(p) for p in (ctx.root / "design" / "teams" / o, ctx.roster(o), env_dir(ctx, o)) if p.exists()]
    print(f"AFTER 옛 자리 잔여 {len(left)} {' '.join(left)}".rstrip())
    print(f"SNAPSHOT {snap.save()}")
    return 0


def revert(ctx: Ctx, path: Path) -> int:
    data = json.loads(path.read_text(encoding="utf-8"))
    for c in reversed(data.get("created", [])):
        Path(c).unlink(missing_ok=True)
    for d in map(Path, data.get("created_dirs", [])):
        if d.is_dir():
            for x in sorted(d.rglob("*"), key=lambda x: -len(x.parts)):
                x.rmdir()
            d.rmdir()
    for st in data["steps"]:
        for f in st["files"]:
            Path(f["path"]).parent.mkdir(parents=True, exist_ok=True)
    move_revert(ctx, path)
    return 0


def residue(ctx: Ctx, n: str, o: str) -> list[str]:
    w, out = word(o), []
    note = f"옛 이름 {o} → {n}"
    seat = re.compile(rf"^byz-{re.escape(o)}-[a-z0-9-]+#\d+$")
    scan = [p for p in (ctx.root / "design" / "teams" / n).rglob("*") if p.is_file()] + [ctx.root / "design" / f for f in ("TEAMS.md", "TEAMSET.md")]
    scan += sorted(env_dir(ctx, n).rglob("*")) if env_dir(ctx, n).is_dir() else []
    for p in scan:
        for i, ln in enumerate((read(p) or "").split("\n"), 1):
            if w.search(ln) and note not in ln:
                out.append(f"{p.relative_to(ctx.root) if p.is_relative_to(ctx.root) else p}:{i}")
    ros = ctx.roster(n)
    data = json.loads(read(ros) or "{}") if ros.is_file() else {}
    for k, v in data.items():
        if k.startswith("_") and k not in ("_renamed_from", "_replaces") and isinstance(v, str) and w.search(v) and not seat.match(v):
            out.append(f"{ros.name}:{k}")
    rx = path_subs(o, n)[0][0]
    others = run("git", "grep", "-l", "-E", rx.pattern.replace("(?<![A-Za-z0-9_])", ""), "--", "design", cwd=ctx.root).stdout.split()
    if others:
        out.append(f"다른 문서 {len(others)}파일이 design/teams/{o}/ 경로 글자를 가짐(이력 · 치환 0) — 예 {others[0]}")
    return out


def verify(ctx: Ctx, n: str) -> int:
    err, ros = 0, ctx.roster(n)
    o = json.loads(read(ros) or "{}").get("_renamed_from") if ros.is_file() else None
    env = {"FT_REPO_ROOT": str(ctx.root)}
    if n not in ctx.rows:
        print(f"ERR {n} 은 팀 명단(TEAMS.md)에 없다")
        err += 1
    else:
        d = run("bash", "-c", '. "$1"; ft_team_root "$2"', "_", str(Path(__file__).resolve().parent / "ft-team-lib.sh"), n, env=env)
        if d.returncode != 0 or not Path(d.stdout.strip()).is_dir():
            print(f"ERR {n} 팀 폴더를 못 푼다/없다: {d.stderr.strip() or d.stdout.strip()}")
            err += 1
        m = run("bash", str(Path(__file__).resolve().parent / "ft-team-map-lint.sh"), n, env=env)
        if m.returncode != 0:
            print(f"ERR {n} map-lint: {(m.stdout.strip().splitlines() or [''])[-1]}")
            err += 1
        err += check_stores(ctx, n)
    up = run("bash", str(Path(__file__).resolve().parent / "ft-team-upgrade.sh"), "--check-teams", env=env)
    if up.returncode != 0:
        print(f"ERR 팀 집합: {up.stdout.strip()}")
        err += 1
    warn = 0
    if not o:
        print(f"WARN {n} 명부에 _renamed_from 없음 — 잔여 옛 이름 검사 생략")
        warn += 1
    else:
        for p, what in ((ctx.root / "design" / "teams" / o, "옛 폴더"), (ctx.roster(o), "옛 명부"), (env_dir(ctx, o), "옛 env 폴더")):
            if p.exists():
                print(f"ERR {what} 잔존: {p}")
                err += 1
        if o in ctx.rows:
            print(f"ERR {o} 이 아직 팀 명단에 있다")
            err += 1
        for ln in residue(ctx, n, o):
            print(f"WARN 잔여 «{o}»: {ln}")
            warn += 1
    print(f"VERIFY ERR={err} WARN={warn}")
    return 1 if err else 0


def watch(mbox: str, rosters: list[str]) -> int:
    days = float(os.environ.get("FT_RENAME_WATCH_DAYS", "7"))
    seen: set[str] = set()
    for r in rosters:
        if os.path.realpath(r) in seen or not os.path.isfile(r):
            continue
        seen.add(os.path.realpath(r))
        try:
            d = json.loads(Path(r).read_text(encoding="utf-8"))
            o, at = d.get("_renamed_from"), d.get("_renamed_at")
            if not o or not at or (datetime.date.today() - datetime.date.fromisoformat(at)).days >= days:
                continue
        except (OSError, ValueError) as e:
            print(f"ERROR {r} 명부를 못 읽음: {e}")
            continue
        tops: dict[str, tuple[int, str]] = {}
        for k in d:
            m = re.fullmatch(rf"(byz-{re.escape(o)}-[a-z0-9-]+)#(\d+)", k)
            if m and int(m.group(2)) >= tops.get(m.group(1), (-1, ""))[0]:
                tops[m.group(1)] = (int(m.group(2)), k)
        for _, seat in sorted(tops.values(), key=lambda x: x[1]):
            try:
                pk = run("bash", mbox, "peek", seat)
            except subprocess.TimeoutExpired:
                print(f"ERROR {seat} peek 7초 초과")
                continue
            got = re.search(r"pending=(\d+)", pk.stdout)
            if not got:
                print(f"ERROR {seat} peek 출력에 pending 없음 rc={pk.returncode}")
            elif int(got.group(1)) > 0:
                print(f"PENDING\t{d.get('_master') or '-'}\t{seat}\t{got.group(1)}\t{o}\t{Path(r).stem.removeprefix('seats-')}")
    return 0


def main(argv: list[str]) -> int:
    usage = "usage: ft-team-rename.sh (--plan|--apply) <옛> <새> | --verify <새> | --revert <스냅샷.json> | watch <mbox.sh> <명부>..."
    try:
        if argv[:1] == ["watch"] and len(argv) >= 2:
            return watch(argv[1], argv[2:])
        if argv[:1] in (["--plan"], ["--apply"]) and len(argv) == 3:
            base = make_ctx()
            return (plan if argv[0] == "--plan" else apply)(RCtx(base.root, base.project, base.rows), argv[1], argv[2])
        if argv[:1] in (["--verify"], ["--revert"]) and len(argv) == 2:
            base = make_ctx()
            ctx = RCtx(base.root, base.project, base.rows)
            return verify(ctx, argv[1]) if argv[0] == "--verify" else revert(ctx, Path(argv[1]))
        print(usage, file=sys.stderr)
        return 2
    except MoveError as e:
        print(str(e) if str(e).startswith(("ERROR", "REJECT")) else f"ERROR {e}")
        return 1
    except subprocess.TimeoutExpired as e:
        print(f"ERROR 외부 호출 {e.timeout:g}초 초과(7초 룰): {' '.join(map(str, e.cmd))[:160]}")
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
