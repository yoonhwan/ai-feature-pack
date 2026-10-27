"""ft_team_move_cleanup — 팀 폴더 이동 뒷정리 (r899 · ft_team_move.py 가 부른다).

--classify <팀>|--all            읽기 전용 · CLS 줄 + 끝줄 CLASSIFY <분류>=<n> …
--cleanup-plan <팀>|--all --out <폴더>   계획만 만든다(plan.json · plan.tsv · plan.sh) — 명부·좌석 기록 쓰기 0
--cleanup-run <plan.json> --plan-sha <sha256>   plan.sh 가 부른다(master/오빠 실행) · 고정된 계획만
    r899 r2 «읽은 한 판 = 쓰는 한 판»: 계획 파일 1회 읽기(해시·파싱 같은 바이트) · 파일마다 잠금(<파일>.lock.d)을
    «전부» 먼저 집고(못 집으면 쓰기 0) → 파일마다 «한 판».
    r899 r4 파일 하나의 한 판 순서(행 단위 교체 0 · 이 순서 그대로):
        B1 읽기 → tmux 조회(실패 = 그 파일 SKIP rc1 · tmp 전) → 값 계산(순수) → tmp 쓰기·fsync·모드 복사
        → B2 재읽기(다르면 tmp 삭제 · SKIP rc1) → os.replace «바로 다음 줄».
    r899 r5 보관 기록은 «교체 전»(write-ahead): tmp 쓰기 전에 파일의 보관 항목을 status="pending" 으로 fsync 해 둔다
    (이 기록이 실패하면 그 파일 교체 0 · SKIP rc1) · 교체 뒤 "done" 표시는 «있으면 좋은 것»(실패 = WARN rc1).
--cleanup-restore <archive.json>  되살리기 — r899 r6 «파일 통째 · 바이트 비교 · 보관본 검증» 하나(행 단위 로직 0 · JSON 파싱·재생성 0)
    파일마다: 보관본(replace=orig/ · move=ncb/ — 항목당 «한 경로» · 메타 kept 가 그 경로) 읽기(없음 = ERROR · sha ≠ b1_sha = ERROR «손상» · 둘 다 rc1) → 현재 바이트로 판정:
    replace — sha(현재)==new_sha → CAS 교체(쓰는 바이트 = 보관본 바이트 그대로) · ==b1_sha → «교체 안 됨» SKIP · 그 밖 → «또 바뀜» SKIP rc1.
    move(보관으로 옮긴 기록 파일) — 현재 없음 → 보관본 바이트를 «없을 때만» 만든다(tmp + os.link — 덮어쓰기 0) · ==보관본 → SKIP · 그 밖 → «또 바뀜» SKIP rc1.
보관 = .fable-team/state/team-move/cleanup/<ts>/ (archive.json + ncb/ 보관으로 뺀 기록 파일 · orig/ 고치기 전 바이트 — 항목마다 보관본은 «한 벌»(ncb 또는 orig) ·
run 이 pending 기록 «전» 에 저장·sha 검증 · move 는 보관본 검증 뒤 원래 자리를 unlink) · 지우기 0.
"""
from __future__ import annotations

import hashlib
import json
import os
import shlex
import shutil
import time
from pathlib import Path

import ft_team_move as tm
import ft_team_move_classify as cl
from ft_team_move_apply import dump_like

FIELD = {"roster": "index", "ncb": "card_path"}
ACT = ("ARCHIVE", "LIVE-FIX", "KEEP-FIX")   # 계획이 실행하는 분류 — 나머지는 표(plan.tsv)로만
row_sha = cl.row_sha                        # 행 전체 지문 — 정의는 한 곳(classify)에만
LOCK_WAIT = 5.0                             # 잠금 대기 상한(초) — 넘으면 REJECT(조용한 통과 0)
CHANGED = "바뀜 — 다시 실행"                 # B2 가 B1 과 다름 = 그 파일 교체 0


def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def acquire(p: Path, wait: float = LOCK_WAIT) -> Path:
    """파일 잠금 — `<파일>.lock.d`(pid 포함) · r899 r3 rename 잠금.
    pid 를 먼저 쓴 임시 폴더(`<잠금>.tmp.<pid>`)를 만든 뒤 rename 으로 잠금 이름에 올린다 — 빈 잠금 폴더가
    관측되는 창 0(빈 폴더면 rename 이 그 폴더를 덮어써 잠금을 훔치기 때문). 회수 실패를 포함해 «반복 어느
    지점에서든» 마감(5초)을 지나면 REJECT — 회수만 반복하며 상한을 우회하지 못한다."""
    d, t0 = p.with_name(p.name + ".lock.d"), time.time()
    while True:
        if time.time() - t0 > wait:
            raise tm.MoveError(f"REJECT 잠금을 못 잡았다(>{wait:g}s): {d} — 다른 도구가 이 파일을 쓰는 중")
        tmp = d.with_name(f"{d.name}.tmp.{os.getpid()}")
        shutil.rmtree(tmp, ignore_errors=True)
        try:
            tmp.mkdir()
            try:
                (tmp / "pid").write_text(str(os.getpid()), encoding="utf-8")
            except OSError as e:
                shutil.rmtree(tmp, ignore_errors=True)   # pid 쓰기 실패 = 잠금 폴더 잔류 0
                raise tm.MoveError(f"REJECT 잠금 pid 를 못 썼다: {tmp} ({e})")
            os.rename(tmp, d)
            return d
        except FileExistsError:
            shutil.rmtree(tmp, ignore_errors=True)
        except OSError:
            shutil.rmtree(tmp, ignore_errors=True)       # 이미 누가 잠금을 들고 있다(비어 있지 않은 폴더)
        pid = (d / "pid").read_text().strip() if (d / "pid").is_file() else ""
        if not (pid.isdigit() and _pid_alive(int(pid))):
            shutil.rmtree(d, ignore_errors=True)         # 죽은 잠금 회수 — 실패해도 위 마감 검사가 잡는다
        time.sleep(0.02)


def release(d: Path) -> None:
    if (d / "pid").is_file() and (d / "pid").read_text().strip() == str(os.getpid()):
        shutil.rmtree(d, ignore_errors=True)


def cas_replace(p: Path, data: str | bytes, sha1: str) -> str:
    """tmp 에 다 쓰고 교체 직전 비교(CAS) — 돌려주는 값 = "" (교체함) 또는 CHANGED(교체 0 · 다시 실행).
    B1 = 판정에 쓴 바이트의 sha(호출자가 넘긴다) · B2 = 교체 직전 «다시 읽은» 바이트. 모드 복사는 B2 «앞» —
    B2 와 os.replace 사이에는 호출이 0 이다. 어떤 예외에서도 tmp 는 남기지 않는다(finally)."""
    tmp = p.with_name(p.name + ".r899tmp")
    try:
        with open(tmp, "wb") as fh:
            fh.write(data if isinstance(data, bytes) else data.encode("utf-8"))
            fh.flush()
            os.fsync(fh.fileno())
        shutil.copymode(p, tmp)
        if hashlib.sha256(p.read_bytes()).hexdigest() != sha1:   # B2
            return CHANGED
        os.replace(tmp, p)   # B2 바로 다음 줄
        return ""
    finally:
        tmp.unlink(missing_ok=True)


def cas_remove(p: Path, sha1: str) -> str:
    """보관본(ncb/)이 이미 저장·검증된 파일을 원래 자리에서 치운다 — tmp 없음. B2 비교 바로 다음 줄이 unlink."""
    if hashlib.sha256(p.read_bytes()).hexdigest() != sha1:   # B2
        return CHANGED
    os.unlink(p)
    return ""


def team_repo(ctx, team: str) -> Path | None:
    d = tm.run("bash", "-c", '. "$1"; ft_team_root "$2"', "_", str(tm.LIB), team, env={"FT_REPO_ROOT": str(ctx.root)})
    s = d.stdout.strip()
    return Path(s.rsplit("/design/", 1)[0]) if d.returncode == 0 and "/design/" in s else None


def collect(ctx, arg: str, snaps: dict | None = None) -> list[dict]:
    live = cl.live_sessions(tm.run, tm.MoveError)
    allow, cache, out = cl.allow_list(ctx.root), {}, []
    for team in tm.pick(ctx, arg):
        if tm.old_form(ctx.rows[team]) and not ctx.rows[team].startswith(("$", "/")):
            continue
        out += cl.seats(ctx, team, live, team_repo(ctx, team), tm.store_base, snaps)
        for path, no in tm.code_refs(ctx, team):
            cls, why = cl.code_class(ctx.root, path, no, allow, cache, team)
            out.append({"store": "code", "team": team, "file": path, "seat": f"{path}:{no}", "ref": f"design/{team}/", "cls": cls, "why": why})
    return out


def counts(items: list[dict]) -> str:
    keys = ("LIVE-OK", "LIVE-FIX", "LIVE-HAND", "ARCHIVE", "KEEP-FIX", "KEEP-LINEAGE", "CODE-RUN", "CODE-NOTE", "CODE-RECORD", "CODE-FIXTURE", "CODE-FIXTURE-UNLISTED")
    return " ".join(f"{k}={sum(1 for i in items if i['cls'] == k)}" for k in keys)


def cmd_classify(ctx, arg: str) -> int:
    items = collect(ctx, arg)
    for i in items:
        print(f"CLS {i['cls']} {i['team']} {i['store']} {i['seat']} {i['ref']} — {i['why']}")
    print(f"CLASSIFY {counts(items)}")
    return 0


def cmd_plan(ctx, arg: str, out: Path) -> int:
    items = collect(ctx, arg)   # 반례 3: 분류와 행 지문이 «한 판» 에서 나온다(명부를 다시 읽지 않는다)
    out.mkdir(parents=True, exist_ok=True)
    plan = {"r": "r899", "created": time.strftime("%Y%m%dT%H%M%S"), "project": str(ctx.project), "root": str(ctx.root),
            "act": [i for i in items if i["cls"] in ACT], "report": [i for i in items if i["cls"] not in ACT]}
    pj = out / "plan.json"
    pj.write_text(json.dumps(plan, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    (out / "plan.tsv").write_text("".join(f"{i['cls']}\t{i['team']}\t{i['store']}\t{i['seat']}\t{i['ref']}\t{i['why']}\n" for i in items), encoding="utf-8")
    sha = hashlib.sha256(pj.read_bytes()).hexdigest()
    bin_sh = tm.HERE / "ft-team-move.sh"
    (out / "plan.sh").write_text(
        "#!/bin/bash\n"
        f"# r899 팀 이동 뒷정리 계획 {plan['created']} · {counts(items)}\n"
        "# 실행 = master/오빠 · 보관(지우기 0) · 실행 시점에 tmux 세션 재확인(살아 있으면 건너뜀) · 행이 바뀌었으면 건너뜀\n"
        f"# 표 = {out / 'plan.tsv'} · 되살리기 = bash {shlex.quote(str(bin_sh))} --cleanup-restore <출력의 archive=…>\n"
        "set -euo pipefail\n"
        f"exec bash {shlex.quote(str(bin_sh))} --cleanup-run {shlex.quote(str(pj))} --plan-sha {sha}\n", encoding="utf-8")
    print(f"PLAN-OUT {out / 'plan.sh'} 실행 대상 {len(plan['act'])} · 보고만 {len(plan['report'])} · {counts(items)}")
    return 0


def dump_arch(arch_path: Path, rec: dict) -> None:
    """보관 기록(archive.json)을 쓴다(tmp·fsync·교체) — 파일 교체 «전» 에 pending 으로 먼저 부른다(r5)."""
    tmp = arch_path.with_name(arch_path.name + ".r899tmp")
    try:
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write(json.dumps(rec, ensure_ascii=False, indent=1) + "\n")
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, arch_path)
    finally:
        tmp.unlink(missing_ok=True)


def save_kept(kept: Path, blob: bytes, sha1: str) -> None:
    """보관본 = 원본 바이트 그대로 — 쓰고 fsync 하고 «다시 읽어» sha 가 b1_sha 와 같은지 본다(다르면 OSError)."""
    kept.parent.mkdir(exist_ok=True)
    with open(kept, "wb") as fh:
        fh.write(blob)
        fh.flush()
        os.fsync(fh.fileno())
    if hashlib.sha256(kept.read_bytes()).hexdigest() != sha1:
        raise OSError("보관본 sha 가 b1_sha 와 다름")


def add_pending(arch: Path, rec: dict, f: str, meta: dict, rows: list[dict], rew: list[dict], order: list | None) -> None:
    """파일 교체 «전» 보관 기록 — 새 기록을 먼저 파일에 쓰고(fsync) 성공했을 때만 메모리 rec 에 반영한다.
    쓰기가 실패하면 OSError 가 그대로 올라가고 rec 은 그대로(교체 0)."""
    trial = {**rec, "roster": rec["roster"] + [r for r in rows if meta["store"] == "roster"],
             "ncb": rec["ncb"] + [r for r in rows if meta["store"] != "roster"], "rewrite": rec["rewrite"] + rew,
             "order": {**rec["order"], **({f: order} if order is not None else {})}, "files": {**rec["files"], f: meta}}
    dump_arch(arch / "archive.json", trial)
    rec.update(trial)


def counts_done(rec: dict) -> tuple[int, int]:
    """교체된 파일의 행만 센다(pending 인데 교체 안 된 파일은 셈 밖) — (보관 수, 다시 쓴 수)."""
    d = {f for f, m in rec["files"].items() if m["status"] == "done"}
    return (sum(1 for r in rec["roster"] + rec["ncb"] if r["file"] in d), sum(1 for r in rec["rewrite"] if r["file"] in d))


def compute(raw: str, keep: list[dict], roster: bool, arch: Path, p: Path) -> tuple[str, list[dict], list[dict]]:
    """순수 함수 — I/O 0. 새 파일 글자 · 보관 행 · 다시 쓴 칸 기록을 돌려준다(바꾸기 «전» 값 포함)."""
    data = json.loads(raw)
    rows, rew = [], []
    for i in keep:
        row = data.get(i["seat"]) if roster else data
        if i["cls"] == "ARCHIVE":
            rows.append({**i, "row": row, "kept": str(arch / "ncb" / p.name) if not roster else ""})
            if roster:
                data.pop(i["seat"], None)
        else:
            old = row[FIELD[i["store"]]]
            row[FIELD[i["store"]]] = i["why"]
            rew.append({**i, "old": old, "new": i["why"]})
    txt = dump_like(raw, data)
    json.loads(txt)
    return txt, rows, rew


def run_file(p: Path, items: list[dict], arch: Path, rec: dict) -> tuple[int, bool]:
    """파일 하나 = 한 판(행 단위 교체 0). 순서 = B1 → tmux → 계산 → tmp → B2 → 교체(바로 다음 줄) → 보관 기록.
    돌려주는 값 = (SKIP 수, 실패 있음 → rc1). 교체된 파일의 행만 rec 에 넣는다."""
    f = str(p)
    if not p.is_file():
        for i in items:
            print(f"SKIP {i['seat']} 행이 없거나 바뀜")
        return len(items), False
    blob = p.read_bytes()   # B1
    sha1 = hashlib.sha256(blob).hexdigest()
    raw = blob.decode("utf-8")
    base = json.loads(raw)
    roster = items[0]["store"] == "roster"
    todo, skipped = [], 0
    for i in items:
        row = base.get(i["seat"]) if roster else base
        if not isinstance(row, dict) or row_sha(row) != i["row_sha"]:
            print(f"SKIP {i['seat']} 행이 없거나 바뀜")
            skipped += 1
        else:
            todo.append(i)
    if not todo:
        return skipped, False
    try:
        live = cl.live_sessions(tm.run, tm.MoveError)   # 못 읽으면 이 파일만 SKIP · tmp 만들기 전
    except tm.MoveError as e:
        for i in todo:
            print(f"SKIP {i['seat']} tmux 목록 실패 — 다시 실행 ({e})")
        return skipped + len(todo), True
    alive = {i["seat"] for i in todo if i["cls"] == "ARCHIVE" and i["seat"] in live}
    for s in sorted(alive):
        print(f"SKIP {s} 살아 있음")
    keep = [i for i in todo if i["seat"] not in alive]
    skipped += len(alive)
    if not keep:
        return skipped, False
    txt, rows, rew = compute(raw, keep, roster, arch, p)   # 순수 — I/O 0
    move = not roster and keep[0]["cls"] == "ARCHIVE"   # ncb 보관 = 파일 이동
    meta = {"file": f, "store": items[0]["store"], "kind": "move" if move else "replace",
            "kept": str(arch / "ncb" / p.name) if move else str(arch / "orig" / f"{sha1[:12]}-{p.name}"), "mode": 0o644, "b1_sha": sha1, "status": "pending",
            "new_sha": "" if move else hashlib.sha256(txt.encode("utf-8")).hexdigest()}
    try:   # r6 보관본(원본 바이트 그대로) — pending 기록 «전» 에 저장하고 sha 를 확인한다(실패 = 그 파일 교체 0)
        meta["mode"] = p.stat().st_mode & 0o7777
        save_kept(Path(meta["kept"]), blob, sha1)
    except OSError as e:
        why = f"보관본 저장 실패 — 교체 0 ({e})"
    else:
        try:   # r5 write-ahead — 기록이 안 써지면 이 파일 교체 0(기록 없는 교체가 생길 수 없다)
            add_pending(arch, rec, f, meta, rows, rew, list(base) if roster else None)
            why = None
        except OSError as e:
            why = f"보관 기록 실패 — 교체 0 ({e})"
    if why is None:
        try:
            why = cas_remove(p, sha1) if move else cas_replace(p, txt, sha1)
        except OSError as e:
            why = f"교체 실패 — {e}"
    if why:   # 교체 0 — pending 기록이 남아도 restore 가 현재 바이트로 SKIP 한다
        for i in keep:
            print(f"SKIP {i['seat']} {why}")
        return skipped + len(keep), True
    meta["status"] = "done"   # 교체 뒤 표시 — 디스크 쓰기는 «있으면 좋은 것»
    try:
        dump_arch(arch / "archive.json", rec)
    except OSError as e:
        print(f"WARN {p.name} done 표시 실패 — pending 으로 남음(되살림은 현재 바이트로 판정) ({e})")
        return skipped, True
    return skipped, False


def arch_dir(ctx) -> Path:
    """보관 폴더 — 초 단위 이름이 겹치면 -1, -2 … 를 붙인다(같은 초 두 실행이 죽지 않게 · 지우기 0)."""
    base = ctx.state / "cleanup" / time.strftime("%Y%m%dT%H%M%S")
    n = 0
    while True:
        d = base if n == 0 else base.with_name(f"{base.name}-{n}")
        try:
            (d / "ncb").mkdir(parents=True, exist_ok=False)
            return d
        except FileExistsError:
            n += 1


def cmd_run(ctx, plan_path: Path, sha: str) -> int:
    pb = plan_path.read_bytes()   # 반례 2: 계획 파일 «한 판» 만 읽는다(해시·파싱 같은 바이트)
    if hashlib.sha256(pb).hexdigest() != sha:
        raise tm.MoveError("REJECT 계획 파일이 만든 뒤 바뀌었다(sha 불일치) — --cleanup-plan 다시")
    plan = json.loads(pb.decode("utf-8"))
    arch = arch_dir(ctx)
    rec: dict = {"plan": str(plan_path), "roster": [], "ncb": [], "rewrite": [], "order": {}, "files": {}}
    dump_arch(arch / "archive.json", rec)
    skipped, casfail = 0, False
    files = sorted({i["file"] for i in plan["act"]})
    locks: list[Path] = []
    try:
        for f in files:   # 잠금을 «전부» 먼저 집고 바로 해제 목록에 넣는다 — 하나라도 못 집으면 쓰기 0
            lock = acquire(Path(f))
            locks.append(lock)
        for f in files:
            s, c = run_file(Path(f), [i for i in plan["act"] if i["file"] == f], arch, rec)
            skipped += s
            casfail = casfail or c
    finally:
        for d in reversed(locks):
            release(d)
    n_arch, n_rew = counts_done(rec)
    print(f"CLEANUP-RUN ARCHIVED={n_arch} REWROTE={n_rew} SKIPPED={skipped} archive={arch / 'archive.json'}")
    return 1 if casfail else 0


def put_new(p: Path, orig: bytes, mode: int) -> tuple[bool, bool]:
    """보관본 바이트를 «없을 때만» 만든다 — tmp 에 다 쓰고 os.link(덮어쓰기 0 · 경쟁 새 파일이면 FileExistsError)."""
    tmp = p.with_name(p.name + ".r899tmp")
    try:
        with open(tmp, "wb") as fh:
            fh.write(orig)
            fh.flush()
            os.fsync(fh.fileno())
        os.chmod(tmp, mode)
        os.link(tmp, p)
    except FileExistsError:
        print(f"SKIP {p.name} {CHANGED}")
        return False, True
    except OSError as e:
        print(f"SKIP {p.name} 되살림 실패 — {e}")
        return False, True
    finally:
        tmp.unlink(missing_ok=True)
    return True, False


def restore_one(f: str, m: dict) -> tuple[bool, bool]:
    """파일 하나 = 파일 통째 · 현재 «바이트» 판정 · 보관본 sha 검증 — JSON 을 파싱·재생성하지 않는다(r6).
    돌려주는 값 = (되살림 여부, rc1 여부). 하나라도 ERROR·«또 바뀜» 이면 rc1 — 조용한 rc0 없음."""
    p = Path(f)
    try:
        orig = Path(m["kept"]).read_bytes()
    except (KeyError, OSError):
        print(f"ERROR {p.name} 보관본 없음 — 되살림 0")
        return False, True
    if hashlib.sha256(orig).hexdigest() != m["b1_sha"]:
        print(f"ERROR {p.name} 보관본 손상(sha 불일치) — 되살림 0")
        return False, True
    try:
        cur = p.read_bytes()
    except FileNotFoundError:
        cur = None
    if m["kind"] == "move":   # 보관으로 옮긴 기록 파일 — 없어야 하는 자리
        if cur is None:
            return put_new(p, orig, m["mode"])
        if cur == orig:
            print(f"SKIP {p.name} 이미 원본")
            return False, False
        print(f"SKIP {p.name} 또 바뀜(원본도 없음도 아님) — 되살림 0")
        return False, True
    cs = hashlib.sha256(cur).hexdigest() if cur is not None else ""
    if cs == m["new_sha"]:   # 교체 직후 바이트 그대로 — CAS 로 원본 바이트를 되돌린다
        try:
            why = cas_replace(p, orig, cs)
        except OSError as e:
            why = f"교체 실패 — {e}"
        if why:
            print(f"SKIP {p.name} {why}")
            return False, True
        return True, False
    if cs == m["b1_sha"]:
        print(f"SKIP {p.name} 교체 안 됨(pending)")
        return False, False
    print(f"SKIP {p.name} 또 바뀜(교체 직후도 교체 전도 아님) — 되살림 0")
    return False, True


def cmd_restore(ctx, arch_path: Path) -> int:
    """되살리기 — 잠금 전부 먼저 → 파일마다 restore_one(통째 · 바이트 · 보관본 검증). B2 가 다르면 그 파일 교체 0
    「바뀜 — 다시 실행」(rc1 · 다른 파일은 계속). 셈 = 그 파일에 속한 보관·다시 쓴 행 수."""
    rec = json.loads(arch_path.read_bytes().decode("utf-8"))
    files = rec.get("files") or {}
    if not files:
        print("ERROR archive 에 files 칸이 없다(옛 형식) — 되살림 0")
        return 1
    rows = rec["roster"] + rec["ncb"] + rec["rewrite"]
    back = skip = 0
    casfail = False
    locks: list[Path] = []
    try:
        for f in sorted(files):
            locks.append(acquire(Path(f)))
        for f in sorted(files):
            n = sum(1 for r in rows if r["file"] == f)
            done, fail = restore_one(f, files[f])
            back, skip, casfail = back + (n if done else 0), skip + (0 if done else n), casfail or fail
    finally:
        for d in reversed(locks):
            release(d)
    print(f"CLEANUP-RESTORE RESTORED={back} SKIPPED={skip}")
    return 1 if casfail else 0
