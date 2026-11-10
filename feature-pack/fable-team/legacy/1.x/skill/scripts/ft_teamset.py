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


# ★나노 이름 규칙 정본(r655)★ — v65 도 다른 팀과 같은 꼴 `byz-<팀>-nano-` 다(오빠 «왜 나노워커가 ft-v65 인거야? byz-v65 여야지»).
#   옛 접두는 «인식만» 한다 — 전환기에 이미 열려 있는 좌석을 같은 팀 나노로 세기 위해서지 새로 만들지 않는다.
LEGACY_PREFIXES = {"v65": ("ft-v65-temp-",)}
LEGACY_TEAM_PREFIXES = {"v65": ("ft-v65-",)}   # 「팀 좌석 전부」(나노+역할) 옛 이름 — 예전엔 ft-v65-master-… 처럼 팀 접두가 ft- 였다
KNOWN_HINT = " | ".join(["byz-<팀>-nano-"] + list(LEGACY_PREFIXES.get("v65", ())))   # 오류 문구용 견본 — 목록 자체는 LEGACY_PREFIXES 한 곳


def prefix_of(team):
    """그 팀 나노의 «새» 이름 접두 — 모든 팀이 byz-<팀>-nano- 한 꼴."""
    return f"byz-{team}-nano-"


def prefixes_of(team):
    """그 팀 나노로 «세야 하는» 접두 전부 — 새 접두 먼저, 옛 접두 뒤(전환기)."""
    return (prefix_of(team),) + LEGACY_PREFIXES.get(team, ())


def team_prefixes_of(team):
    """그 팀 좌석 «전부»(나노·역할 무관)의 접두 — 셸이 팀 좌석을 고를 때 쓰는 목록(두 벌 규칙 0)."""
    return (f"byz-{team}-",) + LEGACY_TEAM_PREFIXES.get(team, ())


def team_of(prefix, strict=True):
    for t, legacies in LEGACY_PREFIXES.items():
        if prefix in legacies:
            return t
    m = re.fullmatch(r"byz-([a-z0-9]+)-nano-", prefix)
    if m:
        return m.group(1)
    return die(f"나노 접두 {prefix!r} 에서 팀을 못 읽는다 ({KNOWN_HINT})") if strict else None


def seat_info(seat):
    """좌석 이름 → (팀, 접두, 옛이름인가, 키) · 나노 이름이 아니면 None. 이름 만드는 곳과 세는 곳이 같은 규칙을 쓰게 하는 판정기(한 곳)."""
    if not re.fullmatch(r".+#\d+", seat):
        return None
    for t, legacies in LEGACY_PREFIXES.items():
        for p in legacies:
            if seat.startswith(p):
                return t, p, True, seat[len(p):].rsplit("#", 1)[0]
    m = re.fullmatch(r"byz-([a-z0-9]+)-nano-(.+)#\d+", seat)
    if m:
        return m.group(1), prefix_of(m.group(1)), False, m.group(2)
    return None


def sessions():
    try:
        r = subprocess.run(["tmux", "list-sessions", "-F", "#{session_name}"], capture_output=True, text=True, timeout=7)
    except (OSError, subprocess.TimeoutExpired) as e:
        die(f"tmux 세션 목록 실패({e}) — 셀 수 없다")
    if r.returncode:
        if re.search(r"no server running", r.stderr):   # r655(DA⑥ r1 H4⑦): «서버 없음» 만 빈 목록 — 그 밖은 ERROR(빈 목록이면 wt-v65 가 0을 내 press ① 검사가 통째로 사라진다)
            return []
        die(f"tmux list-sessions 실패: {r.stderr.strip()[:80]}")
    return r.stdout.split()


def cap_of(spec, team):
    return spec["teams"].get(team, spec["default"])


def cmd_cap(a):
    spec, team = load(a.md, a.root), team_of(a.prefix, strict=False)
    if team is None:  # 표 대상 아닌 접두(시험·외부 env) — 막지 않되 눈에 보이게
        print(f"SKIP 접두 {a.prefix!r} 는 팀셋 표 대상 아님({KNOWN_HINT}) — 상한 검사 0")
        sys.exit(0)
    # r655(DA⑥ r1 H1): 상한은 «그 팀의 접두 전부»(옛 이름 + 새 이름)를 센다 — 접두 하나만 세면 옛 1 + 새 N 이 상한을 통과한다.
    pf = prefixes_of(team)
    live, cap = sum(1 for s in sessions() if any(s.startswith(p) for p in pf)), cap_of(spec, team)
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
        return f"arch 없음 — 명부 _arch 칸이 비었다 {arch_open_hint(d, team)}"
    return "" if a in live else f"arch 없음 — 명부 _arch {a} 라이브 아님 {arch_open_hint(d, team)}"


def standby_close(root, d, team, live):
    """r1119 — 오빠 판정으로 arch 를 닫은 «대기 팀»이면 (좌석, 판정), 아니면 None. 읽기 전용 · 새 표식 0(ft-seat-close --verdict 기록만 읽는다).
    ⓐ `_arch` == "" ⓑ `_closed_from` 에 «이 명부:_arch» 를 가진 행 중 `_closed.at` 가 가장 늦은 행에 verdict ⓒ `byz-<팀>-arch-` 행 중 라이브 0."""
    if d.get("_arch") != "":
        return None
    me = os.path.realpath(roster_path(root, team))

    def ours(ent):
        f, _, k = str(ent).rpartition(":")
        return k == "_arch" and bool(f) and os.path.realpath(os.path.join(root, f)) == me   # 절대경로면 join 이 그대로 둔다

    closed = [(str((v.get("_closed") or {}).get("at", "")), k, v) for k, v in d.items()
              if isinstance(v, dict) and isinstance(v.get("_closed"), dict) and any(ours(e) for e in v.get("_closed_from") or [])]
    if not closed:
        return None
    _, seat, row = max(closed, key=lambda c: c[0])
    verdict = str(row["_closed"].get("verdict") or "")
    if not verdict or any(k.startswith(f"byz-{team}-arch-") and k in live for k in d):
        return None
    return seat, verdict


def arch_open_hint(d, team):
    """R437 — arch 없음 사유 뒤 «있는 길» 1줄: 명부 `_arch` 에 이름이 있으면 그 좌석의 자기 교대(successor-open · arch-live 통과 · 구 좌석 생존 불요), 비었으면 ft-role-spawn --team."""
    a = d.get("_arch")
    m = re.fullmatch(r"(.+)-([a-z]+)#(\d+)", a) if isinstance(a, str) else None
    if not m:
        return f"→ 열기: ft-role-spawn.sh arch --team {team}"
    row = d.get(a) if isinstance(d.get(a), dict) else {}
    model, ctx = row.get("model") or "claude-opus-5-5[1m]", " --ctx 1m" if m.group(2) == "claude" else ""
    return (f"→ 열기: ft-successor-open.sh '{a}' <{team} 워크트리> --name '{m.group(1)}-{m.group(2)}#{int(m.group(3)) + 1}' "
            f"--agent {m.group(2)} --model '{model}'{ctx} --effort high --body-file <골 3줄+인계>")


def watch_gap(team, m):
    """r408 — planner `_master` 는 doorbell 을 안 받는다(판정 876) → 세션 안 감시(ft-inbox-watch.sh)가 실재해야 쪽지를 받는다.
    판정기는 ft-mbox.sh watch-alive 하나(FT_TEAMSET_WATCH 로 시험 대체). 없으면 사유 문자열, 있으면·대상 아님 ''."""
    if team != "planner":
        return ""
    mb = os.environ.get("FT_TEAMSET_WATCH") or str(Path(__file__).with_name("ft-mbox.sh"))
    try:
        r = subprocess.run(["bash", mb, "watch-alive", m], capture_output=True, text=True, timeout=7)
    except (OSError, subprocess.TimeoutExpired) as e:
        return f"planner watch 판정 실패({e})"
    if r.returncode == 0:
        return ""
    if r.returncode == 3 and r.stdout.startswith("NO watch"):  # shim 오류도 rc3 이라 출력 머리까지 본다
        return f"planner watch 없음(ft-inbox-watch.sh {m})"
    return f"planner watch 판정 실패 rc={r.returncode} {r.stdout.strip()[:60]}"


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
        live = sessions() if {"_master", "_desk"} & set(keys) else []
        gap = arch_gap(load(a.md, a.root), d, t, live) if {"_master", "_desk"} & set(keys) else ""
        sb = standby_close(a.root, d, t, live) if gap else None
        if sb:   # r1119: 판정으로 arch 를 닫은 대기 팀 — 팀장 교대 통과
            print(f"OK {t} {keys[0]} · 대기(arch 닫힘 판정 {sb[1]} {sb[0]})")
            sys.exit(0)
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
    pre = (f"byz-{team}-",) + tuple(p for p in LEGACY_PREFIXES.get(team, ()))
    mine = [s for s in live if s.startswith(pre)]
    nano = [s for s in mine if any(s.startswith(p) for p in prefixes_of(team))]
    cap, err, warn, info = cap_of(spec, team), [], [], []
    if not mine:
        return "OK", f"휴면(라이브 좌석 0 · 나노 0/{cap})"
    if not any(s.startswith(f"byz-{team}-master-") for s in mine):
        err.append("master 없음")
    gap = arch_gap(spec, d, team, live)
    sb = standby_close(root, d, team, live) if gap else None
    if sb:   # r1119: 판정으로 arch 를 닫은 대기 팀 — ERR 아님
        info.append(f"대기(arch 닫힘 판정 {sb[1]})")
    elif gap:
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
        wg = watch_gap(team, m)
        if wg:
            err.append(wg)
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


def cmd_wt_v65(a):
    """v65 나노로 «세야 하는» 현역 좌석의 워크트리 이름(`v65-<키>`) — 새 이름·옛 이름 둘 다, stop-ready 제외. press 게이트가 이 한 곳을 부른다."""
    p = Path(a.seats or "")
    try:
        d = json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        die(f"명부 읽기 실패 {p}: {e}")
    live = set(sessions())
    out = set()
    for k, v in d.items():
        if not isinstance(v, dict) or v.get("role") == "stop-ready" or k not in live:
            continue
        t = re.fullmatch(r"ft-v65-(mr|le)-track#\d+$", k)
        if t:
            out.add("v65-" + t.group(1))
            continue
        info = seat_info(k)
        if info and info[0] == "v65":
            out.add("v65-" + info[3])
    print(" ".join(sorted(out)))


def cmd_name_rule(argv):
    """이름 규칙 조회만 하는 하위명령(`prefix`·`prefixes`·`seat-info`·`wt-v65`·`team-of`) — 셸이 목록을 «복사»하지 않고 여기서 읽는다(두 벌 규칙 0)."""
    ap = argparse.ArgumentParser(prog="ft_teamset.py")
    ap.add_argument("cmd", choices=["prefix", "prefixes", "seat-info", "team-prefixes", "wt-v65", "team-of"])
    ap.add_argument("--team")
    ap.add_argument("--seats")
    ap.add_argument("--prefix")
    ap.add_argument("seat", nargs="?")
    a = ap.parse_args(argv)
    if a.cmd == "team-of":  # r1144: 나노 접두 → 팀(옛 접두 포함) · 규칙 밖 = ERROR rc1
        if not a.prefix:
            die("--prefix 필수")
        print(team_of(a.prefix))
        sys.exit(0)
    if a.cmd == "wt-v65":
        if not a.seats:
            die("--seats 필수")
        return cmd_wt_v65(a)
    if a.cmd in ("prefix", "prefixes", "team-prefixes"):
        if not a.team:
            die("--team 필수")
        if a.cmd == "prefix":
            print(prefix_of(a.team))
        elif a.cmd == "team-prefixes":
            print(" ".join(team_prefixes_of(a.team)))
        else:
            print(" ".join(prefixes_of(a.team)))
        sys.exit(0)
    if not a.seat:
        die("좌석 이름 필요")
    info = seat_info(a.seat)
    if not info:
        die(f"나노 좌석 이름이 아니다 — {a.seat} (규칙 byz-<팀>-nano-<키>#N · 옛 이름 {LEGACY_PREFIXES['v65'][0]}<키>#N)")
    print(f"team={info[0]} prefix={info[1]} legacy={int(info[2])} key={info[3]} prefixes={','.join(prefixes_of(info[0]))}")


def main():
    if sys.argv[1:2] and sys.argv[1] in ("prefix", "prefixes", "seat-info", "team-prefixes", "wt-v65", "team-of"):
        return cmd_name_rule(sys.argv[1:])
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
