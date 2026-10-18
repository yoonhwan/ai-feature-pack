#!/usr/bin/env python3
"""ft_teamset.py — design/TEAMSET.md 표를 읽는 팀셋 도구 (r-teamset-standard · 판정 2170). 읽기 전용(큐 = ft_spawn_queue.py).
  check      --root R --md M [--team T | --all]   팀당 1줄 `<팀> OK|WARN|ERR …` · ERR 있으면 rc1
  cap        --root R --md M --prefix P            나노 상한 대조 · rc0 `CAP …` / rc4 `AT-CAP …` / rc1 `ERROR …`
  arch-live  --root R --md M (--team T | --seat S)  «arch 상시» 팀의 `_arch` 라이브 판정(R342 · 판정기 하나) · rc0 `OK|SKIP …` / rc3 `NO …` / rc1 `ERROR …`
못 읽음 = `ERROR …` rc1
"""
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, NoReturn


def die(msg: str) -> NoReturn:
    print(f"ERROR {msg}")
    sys.exit(1)


def table_rows(text: str, heading: str):
    m = re.search(rf"^##\s*{heading}.*?$(.*?)(?=^##\s|\Z)", text, re.S | re.M)
    if not m:
        die(f"TEAMSET 에 «{heading}» 절이 없다")
    rows = [[c.strip() for c in ln.strip().strip("|").split("|")] for ln in m.group(1).splitlines() if ln.lstrip().startswith("|")]
    return [r for r in rows[2:] if r], m.group(1)  # 머리줄·구분줄 뒤


def tick(s):
    return re.findall(r"`([^`]+)`", s)


GITREF = "gitref:"  # `--md gitref:<ref>:<경로>` = `git -C <root> show <ref>:<경로>` (R351 — 정본은 main tracked 한 곳 · 호출 워크트리 파일 의존 0)


def git_out(root, *args):
    try:
        r = subprocess.run(["git", "-C", root, *args], capture_output=True, text=True, timeout=7)
    except (OSError, subprocess.TimeoutExpired) as e:
        die(f"TEAMSET git {args[0]} 실패({e})")
    if r.returncode:
        die(f"TEAMSET 읽기 실패 git {' '.join(args)} ({root}): {r.stderr.strip()[:120]}")
    return r.stdout


def load(md, root):
    """표를 읽어 spec 을 돌려준다. gitref 는 ref 를 ★한 번★ commit sha 로 확정한 뒤 그 sha 로 show — 판정에 쓴 표와 머리줄 sha 가 같은 판(DA⑥ H1).
    spec["head"] = `md=<ref>@<sha10>`(fetch 는 안 한다 · 오래됨은 sha 로 드러낸다) · 파일 주입은 ''."""
    head = ""
    if md.startswith(GITREF):
        ref = md[len(GITREF):]
        rev, _, path = ref.partition(":")
        sha = git_out(root, "rev-parse", rev + "^{commit}").strip()
        text, head = git_out(root, "show", f"{sha}:{path}"), f"md={ref}@{sha[:10]}"
    else:
        try:
            text = Path(md).read_text(encoding="utf-8")
        except OSError as e:
            die(f"TEAMSET 읽기 실패 {md}: {e}")
    roles, body1 = table_rows(text, "표 1")
    teams, _ = table_rows(text, "표 2")
    mb = re.search(r"나노 상한 기본:\s*(\d+)", body1)
    if not roles or not teams or not mb:
        die("TEAMSET 표 1(역할)·표 2(팀)·「나노 상한 기본: N」 중 비었다")
    spec: dict[str, Any] = {"head": head, "default": int(mb.group(1)), "role_model": {}, "keys": set(), "teams": {}, "arch": set()}
    for r in roles:
        if len(r) < 5:
            die(f"표 1 열 수 부족: {r}")
        spec["role_model"][r[0]] = (tick(r[2]) or [""])[0]
        spec["keys"].update(k for k in tick(r[4]) if k.startswith("_"))
    spec["keys"].update(k for k in tick(body1) if k.startswith("_"))
    for r in teams:
        if len(r) < 4 or not r[1].isdigit():
            die(f"표 2 행 형식(팀 | 나노 상한 숫자 | tester | arch): {r}")
        spec["teams"][r[0]] = int(r[1])
        if r[3].startswith("상시"):
            spec["arch"].add(r[0])
    return spec


def prefix_of(team):
    return "ft-v65-temp-" if team == "v65" else f"byz-{team}-nano-"


def team_of(prefix, strict=True):
    m = re.fullmatch(r"byz-([a-z0-9]+)-nano-", prefix)
    if prefix == "ft-v65-temp-" or m:
        return "v65" if prefix == "ft-v65-temp-" else m.group(1)
    return die(f"나노 접두 {prefix!r} 에서 팀을 못 읽는다 (byz-<팀>-nano- | ft-v65-temp-)") if strict else None


def sessions():
    try:
        r = subprocess.run(["tmux", "list-sessions", "-F", "#{session_name}"], capture_output=True, text=True, timeout=7)
    except (OSError, subprocess.TimeoutExpired) as e:
        die(f"tmux 세션 목록 실패({e}) — 셀 수 없다")
    if r.returncode:
        if re.search(r"no server|error connecting", r.stderr):
            return []
        die(f"tmux list-sessions 실패: {r.stderr.strip()[:80]}")
    return r.stdout.split()


def cap_of(spec, team):
    return spec["teams"].get(team, spec["default"])


def cmd_cap(a):
    spec, team = load(a.md, a.root), team_of(a.prefix, strict=False)
    if team is None:  # 표 대상 아닌 접두(시험·외부 env) — 막지 않되 눈에 보이게
        print(f"SKIP 접두 {a.prefix!r} 는 팀셋 표 대상 아님(byz-<팀>-nano- | ft-v65-temp-) — 상한 검사 0")
        sys.exit(0)
    live, cap = sum(1 for s in sessions() if s.startswith(a.prefix)), cap_of(spec, team)
    print(f"{'AT-CAP' if live >= cap else 'CAP'} {team} live={live} cap={cap}")
    sys.exit(4 if live >= cap else 0)


def roster_path(root, team):
    name = "seats.json" if team == "v65" else f"seats-{team}.json"
    return Path(root) / ".fable-team" / name


def teams_of(root):
    names = sorted(f.stem.removeprefix("seats-") for f in (Path(root) / ".fable-team").glob("seats-*.json"))
    return ["v65"] + names if (Path(root) / ".fable-team" / "seats.json").exists() else names


def gens_of(names):
    gens = {}
    for s in names:
        b, _, n = s.rpartition("#")
        if b and n.isdigit():
            gens.setdefault(b, []).append((int(n), s))
    return {b: sorted(g) for b, g in gens.items() if len(g) > 1}


def working(seat):
    st = os.environ.get("FT_SEAT_STATUS") or str(Path(__file__).with_name("ft-seat-status.sh"))
    r = subprocess.run(["bash", st, "turn", seat], capture_output=True, text=True, timeout=20)
    return r.stdout.split()[:1] == ["WORKING"]


def arch_gap(spec, d, team, live):
    """R342 teamset_arch_live — «arch 상시» 팀이 `_arch` 라이브(tmux)가 아니면 사유 문자열, 아니면 ''. 재개 기록은 라이브가 아니다."""
    if team not in spec["arch"]:
        return ""
    a = d.get("_arch")
    if not isinstance(a, str) or not a:
        return "arch 없음 — 명부 _arch 칸이 비었다"
    return "" if a in live else f"arch 없음 — 명부 _arch {a} 라이브 아님"


def read_roster(root, team):
    p = roster_path(root, team)
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        die(f"명부 읽기 실패 {p.name}: {e}")


def cmd_arch_live(a):
    if a.team:
        if not roster_path(a.root, a.team).exists():
            print(f"SKIP {a.team} 명부 없음 — 검사 대상 아님")
            sys.exit(0)
        gap = arch_gap(load(a.md, a.root), read_roster(a.root, a.team), a.team, sessions())
        print(f"NO {a.team} {gap}" if gap else f"OK {a.team}")
        sys.exit(3 if gap else 0)
    for t in teams_of(a.root):  # --seat: 교대 대상이 `_master`·`_desk` 로 적힌 팀만 — `_arch` 자신의 교대는 통과(교착 0)
        d = read_roster(a.root, t)
        keys = [k for k in ("_master", "_desk", "_arch") if d.get(k) == a.seat]  # 소유 역할 키만 — _hil_route·_parent 류 참조 키는 소속이 아니다(DA⑥ r1 H1)
        gap = arch_gap(load(a.md, a.root), d, t, sessions()) if {"_master", "_desk"} & set(keys) else ""
        if gap:
            print(f"NO {t} {gap}")
            sys.exit(3)
        if keys:
            print(f"OK {t} {keys[0]}")
            sys.exit(0)
    print(f"SKIP {a.seat} 명부에 없음 — 검사 대상 아님")


def check_team(spec, root, team, live):
    p = roster_path(root, team)
    try:
        d = json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        die(f"명부 읽기 실패 {p.name}: {e}")
    pre = ("byz-v65-", "ft-v65-temp-") if team == "v65" else (f"byz-{team}-",)
    mine = [s for s in live if s.startswith(pre)]
    nano = [s for s in mine if s.startswith(prefix_of(team))]
    cap, err, warn, info = cap_of(spec, team), [], [], []
    if not mine:
        return "OK", f"휴면(라이브 좌석 0 · 나노 0/{cap})"
    if not any(s.startswith(f"byz-{team}-master-") for s in mine):
        err.append("master 없음")
    gap = arch_gap(spec, d, team, live)
    if gap:
        err.append(gap)
    m = d.get("_master")
    master_ok = False
    if not isinstance(m, str) or not m:
        err.append("명부 _master 없음")
    elif not re.fullmatch(rf"byz-{team}-master-[a-z0-9]+#\d+", m):
        err.append(f"명부 _master {m} 형식·소속 위반(byz-{team}-master-<에이전트>#N)")
    elif m not in live:
        err.append(f"명부 _master {m} 라이브 아님")
    else:
        master_ok = True
    if len(nano) > cap:
        warn.append("나노 상한 초과")
    for b, g in gens_of(mine).items():
        if len(g) >= 3:
            warn.append(f"{b} {len(g)}세대 동시 라이브(keep-last-2 밖 {len(g) - 2})")
        elif len(g) == 2 and sum(working(s) for _, s in g) == 2:
            warn.append(f"{b} 현역 2세대 동시 WORKING")
    odd = sorted(k for k in d if k.startswith("_") and k not in spec["keys"])
    if odd:
        warn.append("표에 없는 키 " + ",".join(odd))
    mis = sum(1 for k, v in d.items() if isinstance(v, dict) and k in live and spec["role_model"].get(v.get("role", ""))
              and spec["role_model"][v["role"]] not in str(v.get("model", "")))
    if mis:
        info.append(f"모델≠표 {mis}")
    import ft_spawn_queue as sq
    stk = len(sq.stuck_cards(root, prefix_of(team)))
    if stk:
        warn.append(f"큐 확인 필요 {stk}(카드 없음·명부 행 없음)")
    note = sq.notify_master(root, prefix_of(team), cap - len(nano), m) if master_ok else ""
    if note:
        info.append(note)
    status = "ERR" if err else "WARN" if warn else "OK"
    return status, " · ".join(err + warn + [f"나노 {len(nano)}/{cap}"] + info)


def cmd_check(a):
    spec, live = load(a.md, a.root), sessions()
    teams = teams_of(a.root) if a.all else [a.team]
    if not a.all and not roster_path(a.root, a.team).exists():
        die(f"명부 없음: {a.team} ({roster_path(a.root, a.team).name})")
    if spec["head"]:
        print(spec["head"])
    rc = 0
    for t in teams:
        st, msg = check_team(spec, a.root, t, live)
        print(f"{t} {st} {msg}")
        rc = 1 if st == "ERR" else rc
    sys.exit(rc)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["check", "cap", "arch-live"])
    ap.add_argument("--root", required=True)
    ap.add_argument("--md")
    ap.add_argument("--team")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--prefix")
    ap.add_argument("--seat")
    a = ap.parse_args()
    if a.cmd in ("check", "cap", "arch-live") and not a.md:
        die("--md 필수")
    if a.cmd == "check" and not (a.all or a.team):
        die("<팀> 또는 --all 필요")
    if a.cmd == "cap" and not a.prefix:
        die("--prefix 필수")
    if a.cmd == "arch-live" and not (a.team or a.seat):
        die("--team 또는 --seat 필요")
    {"check": cmd_check, "cap": cmd_cap, "arch-live": cmd_arch_live}[a.cmd](a)


if __name__ == "__main__":
    main()
