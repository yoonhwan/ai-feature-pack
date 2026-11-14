"""ft 2.0 keeper 다음 카드 (r1871 · keeper_close.close 가 닫기 영수 자리에서 부른다 · 코어 손 0).
고르기(읽기만) = 팀 카드 루트(directive-roots.tsv) 대기/ 카드 중 원장 seat·막힌 사유·ft2 owner 없음 → 긴급 → 우선 높음 → since 순 1장.
잇기 = submit → 최초이자 유일한 영수 1회(next·새 holder·evidence) → launch → record · 복구 = 저장 next·holder 로만 launch·record 를
«각각» 맞춘다(새 고르기 0 · handled 는 그 뒤) · 고를 카드 0 일 때만 팀장 [다음 없음] 1통(하루·팀 1키).
r1929 launch = 기다리지 않는다(keeper_launch · 띄우고 다음 바퀴에 의도를 읽어 잇기)."""
import importlib.util, os, re, sys  # noqa: E401

HERE = os.path.dirname(os.path.abspath(__file__))
FT2, GIT_S = os.path.dirname(os.path.dirname(HERE)), 25
OK, BLOCK, NONE = "접수 성공", ("정지", "석", "선행", "DA", "사람"), "[다음 없음]"
URGENT, HIGH = re.compile(r"- 긴급:\s*예\s*$"), re.compile(r"- 우선(?:순위)?:\s*높음")
def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_keeper_next_" + name, os.path.join(FT2, "core", name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
cli, dispatch = _load("cli"), _load("dispatch")
_kl = importlib.util.spec_from_file_location("ft2_keeper_next_launch", os.path.join(HERE, "keeper_launch.py"))
kl = importlib.util.module_from_spec(_kl)
_kl.loader.exec_module(kl)
def ft2_state(k, team):
    try:
        return dispatch.Dispatch(k.root, team).ex._state_records()[0]
    except ValueError:
        return None
def ledger(k, stem):
    return k.read_json(os.path.join(k.root, ".fable-team", "state", "card-assign", stem + ".json"))
def gates(k, team):
    """참 = 다음 카드 칸이 열림 · 거짓 = 0(켜기 전·팀 정지·spawn·계정 정지·나노 상한 · 판정 불가 포함)."""
    st = os.path.join(k.root, ".fable-team", "state")
    if not os.path.exists(os.path.join(k.root, ".fable-team", "teams", team, "CLOSE-NEXT.enabled")) or os.path.lexists(os.path.join(st, "%s-tick" % team, "PAUSED")):
        return False
    for name, tool, args, on in (("SPAWN_HOLD", "spawn-hold", [str(k.read_json(os.path.join(st, "SPAWN_HOLD")).get("verdict"))], 0), ("ACCT_PAUSE", "acct-pause", ["--agent", "pi"], 3)):
        rc = k.call(["bash", os.path.join(os.path.dirname(k.close_bin or ""), "ft-%s.sh" % tool), "status", "--check"] + args)[0] if os.path.lexists(os.path.join(st, name)) else 3 - on
        if rc != 3 - on:   # 끔 = hold rc3 · acct rc0 — 유효·판정 불가 = 0
            return k.log("NEXT-HOLD", team, "%s %s rc %s — 다음 카드 0" % (name, "유효" if rc == on else "판정 불가", rc))
    home = os.path.join(k.env.get("HOME") or os.path.expanduser("~"), ".claude", "fable-team", "thresholds.env")   # r1860 순서 = env > 루트 > ~/.claude > 샘플
    files = [p for p in (os.path.join(k.root, ".fable-team", "thresholds.env"), home, os.path.join(HERE, "thresholds.env.sample")) if os.path.isfile(p)]
    cap = (k.env.get("FT2_TEAM_NANO_MAX") or next((x.split("=", 1)[1].strip() for p in files for x in open(p, encoding="utf-8") if x.startswith("FT2_TEAM_NANO_MAX=")), "")).strip()
    if not (cap.isascii() and cap.isdigit()):   # R3 — 못 정함 = 새 실행 0(임의 기본값 0)
        return k.log("판정 불가", team, "나노 상한 FT2_TEAM_NANO_MAX 못 정함(%r · env·thresholds.env) — 다음 카드 0" % cap[:20])
    rc, out, _ = k.call([k.tmux, "list-sessions", "-F", "#{session_name}"])
    live = sum(x.startswith("byz-%s-nano-" % team) for x in set(out.split()) | k.cache.get("launching", set())) if rc == 0 else None   # r1929 여는 중 = 1칸
    k.fa.observe(k.root, "나노 정원", team, live, int(cap), "다음 카드")   # r1886 ⓑ 열림·NEXT-HOLD 둘 다
    return True if live is not None and live < int(cap) else k.log("NEXT-HOLD", team, "나노 %s / 상한 %s — 다음 카드 0" % (live, cap))
def cards(k, team):
    """({stem: [긴급, 높음, 대상 줄들]}, 루트 행) · 판독 실패 = 사유 문자열 (git 2회 · 작업 트리 0)."""
    try:
        with open(os.path.join(k.root, ".fable-team", "state", "directive-roots.tsv"), encoding="utf-8") as fh:
            rows = [x.rstrip("\n").split("\t") for x in fh if not x.startswith("#") and len(x.split("\t")) >= 4]
    except (OSError, UnicodeError):
        rows = []
    r = next((x for x in rows if x[0] == team), None) or next((x for x in rows if x[0] == "*"), None)
    if not r:
        return "카드 루트 표 행 없음"
    r = [r[0], os.path.join(k.root, r[1]), r[2], r[3].replace("*", team)]
    rc, names, err = k.git(r[1], "ls-tree", "--name-only", r[2], "--", r[3] + "/대기/")
    rc2, heads, _ = k.git(r[1], "grep", "-I", "-E", r"^- (긴급|우선|대상)", r[2], "--", r[3] + "/대기/")
    if rc != 0 or rc2 not in (0, 1):
        return "카드 루트 git rc %s/%s %s" % (rc, rc2, err[:60])
    found = {os.path.basename(p)[:-3]: [False, False, []] for p in names.splitlines() if p.endswith(".md")}
    for path, _, line in (x[len(r[2]) + 1:].partition(":") for x in heads.splitlines()):
        row = found.get(os.path.basename(path)[:-3])
        if row is not None:
            row[0], row[1] = row[0] or bool(URGENT.match(line)), row[1] or bool(HIGH.match(line))
            row[2] += [line] if line.startswith("- 대상") else []
    return found, r
def target(k, r, lines):
    """(리포, base) — 팩·feature-pack/ = 팩 origin/main · 없음 = 루트 리포·표 ref · 팩·BYZ 둘 다 = None."""
    pack, byz = any("팩" in x or "feature-pack/" in x for x in lines), any("BYZ" in x for x in lines)
    return None if pack and byz else (k.pack, "origin/main") if pack else (r[1], r[2])
def choose(k, team, skip=frozenset()):
    """(stem, 리포, base) · skip = fill 보류 stem(r1913 «보류») · 고를 카드 0 = None(그때만 [다음 없음] 1통) · 판독 실패 = None(쪽지 0)."""
    got, state = cards(k, team), ft2_state(k, team)
    if isinstance(got, str) or state is None:
        return k.log("판정 불가", team, "다음 카드 고르기 %s — 다음 카드 0" % (got if isinstance(got, str) else "ft2 state"))
    cmap, pair = k.cardmap(team), {}   # r1887 짝 표 {work: [경로]} → {카드 stem: 짝 work 집합} · 판독 실패 = 짝 0(stem 만)
    for work, paths in (cmap.items() if isinstance(cmap, dict) else ()):
        for p in paths:
            pair.setdefault(os.path.basename(p)[:-3], set()).add(work)
    (found, r), done, why, ready = got, state.get("done") or {}, {}, []
    owners = {s for s in found if ({s} | pair.get(s, set())) & set(state.get("owners") or {})}   # stem·짝 work 중 owner 있음
    for stem, (urgent, high, lines) in sorted(found.items()):
        led = ledger(k, stem)
        block = "배정됨" if led.get("state") == "seat" or stem in owners else led.get("reason") if led.get("reason") in BLOCK else ""
        block = block or ("보류" if stem in skip else "끝남" if stem in done or pair.get(stem, set()) & set(done) else "")   # r1887 stem·짝 work done
        place = None if block else target(k, r, lines)
        if not block and place is None:
            block = k.log("판정 불가", team, "%s 대상 팩·BYZ 둘 다 — 건너뜀" % stem) or "대상"
        ready.append(((not urgent, not high, led.get("since") or 0), stem) + place) if not block else why.update({block: why.get(block, 0) + 1})
    if ready:
        return min(ready)[1:]
    k.notify(team, "%s|next-none|%s" % (k.stamp()[:10], team), "%s %s · 배정 없는 카드 0 · 막힌 사유별 %s" % (NONE, team, " ".join("%s %d" % kv for kv in sorted(why.items())) or "0"))
def close(k, team, work, attempt, holder, gen):
    """닫기 영수 1회(지금 자리) + 다음 카드. 반환 = 영수 결과."""
    seen = ((ft2_state(k, team) or {}).get("close_receipts") or {}).get("keeper:%s@%s" % (work, attempt))
    if seen is None:
        pick = choose(k, team) if gates(k, team) else None
        if pick:
            out, rc = cli.run(["submit", "--command", "keeper-next-" + pick[0], "--body", "카드 " + pick[0], "--work", pick[0], "--root", k.root, "--team", team])
            k.fa.remaining(k.root, team, out.get("result"), "카드 " + pick[0])   # r1886 ⓐ keeper submit
            pick = pick if rc == 0 or "재부여 0" in str(out.get("reason")) else k.log("판정 불가", team, "%s submit %s" % (pick[0], out.get("result")))
        stem, nh = (pick[0], "byz-%s-nano-%s#0" % (team, pick[0][:40])) if pick else (None, None)
    else:
        stem, nh = seen.get("next"), seen.get("holder")
    if not stem:
        return k.receipt(team, work, attempt, holder, gen)
    out = k.receipt(team, work, attempt, holder, gen, next_work=stem, next_holder=nh, evidence=dispatch.Dispatch.REQUIRED_EVIDENCE, mark=False)
    if out.result == OK and out.next == stem or "재접수" in out.reason:
        reconcile(k, team, work, attempt, stem, nh, pick if seen is None else None)
    elif out.result == "접수 거부" and seen is None:   # 거부 = 쓰기 0 → 지금처럼 () 영수 1회
        return k.receipt(team, work, attempt, holder, gen)
    return out
def intake_open(k, team):
    """r1939 거짓 = 접수 남은 일 ≥ 상한(fill 0 · FILL-WAIT 는 값이 바뀔 때만 1줄) · project 판독 실패 = 참(submit 이 판정)."""
    out, _ = cli.run(["project", "--root", k.root, "--team", team])
    n, seen = out.get("remaining") if out.get("result") == OK else None, k.state.setdefault("fill_wait", {})
    if type(n) is not int:
        return True
    if n < k.fa.INTAKE_CAP:   # 정상값 = 기억 해제(8→7→8 = 다시 1줄)
        seen.pop(team, None)
        return True
    if seen.get(team) != n:
        seen[team] = n
        k.log("FILL-WAIT", team, "남은 일 %d/%d — fill 0 · 다음 바퀴" % (n, k.fa.INTAKE_CAP))
    return False
def fill(k, team):
    """r1913 빈 나노 칸 1장 = gates→choose→submit→assign→deliver→reconcile · 실패 = 1줄 + fill_hold(원장 쓰기 0 · 그 stem 재시도 0) · 풀림 = 원장 updated > 보류 시각."""
    held, opened = k.state.setdefault("fill_hold", {}), k.state.setdefault("fill_open", {})
    mine = [x for x in opened if x.split("|")[0] == team]
    for x in mine:   # r1929 띄운 열기 잇기 · 그 바퀴 새 fill 0
        stem = x.split("|", 1)[1]
        reconcile(k, team, "fill:" + stem, opened[x], stem, "byz-%s-nano-%s#0" % (team, stem[:40]), None)
        opened.pop(x) if "%s|fill:%s@%s" % (team, stem, opened[x]) in k.state["handled"] else None
    if mine:
        return None
    [held.pop(x) for x in list(held) if x.split("|")[0] == team and (ledger(k, x.split("|", 1)[1]).get("updated") or 0) > float(str(held[x]).split("|")[0])]   # 풀림 · r1939 값 = 시각 또는 «시각|사유»
    pick = intake_open(k, team) and choose(k, team, {x.split("|", 1)[1] for x in held if x.split("|")[0] == team}) if gates(k, team) else None
    if not pick:
        return None
    stem, attempt, nh = pick[0], None, "byz-%s-nano-%s#0" % (team, pick[0][:40])
    for verb, args, ok in (("submit", ["--command", "keeper-next-" + stem, "--body", "카드 " + stem], "재부여 0"),
            ("assign", ["--holder", nh, "--evidence", ",".join(dispatch.Dispatch.REQUIRED_EVIDENCE)], "\0"),
            ("deliver", ["--mode", "intent"], "전달 의도 없음")):
        out, rc = cli.run([verb, "--work", stem, "--root", k.root, "--team", team] + args + (["--attempt", attempt] if verb == "deliver" and attempt else []))
        if verb == "submit":
            k.fa.remaining(k.root, team, out.get("result"), "카드 " + stem)   # r1886 ⓐ fill submit 도 같은 줄
            if out.get("result") == "용량 부족":   # r1939 project·submit 경합 = 보류·쪽지 0 · 다음 바퀴 다시
                return k.log("FILL-WAIT", team, "%s submit 용량 부족 — 보류 0 · 다음 바퀴" % stem)
        attempt = out.get("attempt") if verb == "assign" else attempt
        if rc != 0 and ok not in str(out.get("reason")):
            k.log("HELD-NEXT", team, "fill %s %s rc %s %s %s" % (stem, verb, rc, out.get("result"), str(out.get("reason"))[:60]))
            held["%s|%s" % (team, stem)] = k.now()   # 보류 시각 = 풀림 기준(keeper state · 바퀴마다 저장)
            held.update({x: "%s|%s" % (held[x], out.get("result")) for x in held if x == "%s|%s" % (team, stem)})   # r1939 새 꼴 «시각|사유»
            return k.notify(team, "%s|fill-hold|%s|%s" % (k.stamp()[:10], team, stem), "[다음 막힘] ft2 keeper fill %s %s %s — 같은 카드 자동 재시도 0 · 원장을 손보면 다시 시도" % (stem, verb, out.get("result"))) and None
    reconcile(k, team, "fill:" + stem, attempt, stem, nh, pick)
    opened.update({} if "%s|fill:%s@%s" % (team, stem, attempt) in k.state["handled"] else {"%s|%s" % (team, stem): attempt})
def reconcile(k, team, work, attempt, stem, nh, pick):
    """launch(세션 없음) · record(원장 ≠ seat) 를 따로 맞춘다 · 실패 = 단계 + «복구 필요» 1줄(재시도 0) · 그 뒤 handled."""
    seen, led = k.probe(nh), ledger(k, stem)
    if seen not in ("absent", "alive"):
        return k.log("판정 불가", team, "%s -> %s %s %s — 다음 바퀴" % (work, stem, nh, seen))
    need = (seen == "absent", (led.get("state"), led.get("seat")) != ("seat", nh))
    def done(kind, text):   # handled = 두 단계를 맞춘 뒤 또는 «복구 필요» 뒤에만
        return k.state["handled"].update({"%s|%s@%s" % (team, work, attempt): k.stamp()}) or k.log(kind, team, "%s -> %s %s%s" % (work, stem, nh, text))
    if need[0]:
        if pick is None and not gates(k, team):   # R2 — 복구 launch 직전 현재 가드 · 막힘 = handled 0(허용 뒤 같은 사건 재개)
            return None
        place = pick[1:] if pick else (lambda g: None if isinstance(g, str) or stem not in g[0] else target(k, g[1], g[0][stem][2]))(cards(k, team))
        argv = [sys.executable, k.env.get("FT2_KEEPER_LAUNCH") or os.path.join(HERE, "launch.py"), "--root", k.root, "--team", team, "--work", stem, "--repo", place[0], "--base", place[1], "--role", "session"] if place else None
        why = kl.launching(k, team, stem, (((ft2_state(k, team) or {}).get("deliveries") or {}).get(stem) or [None])[-1], nh, argv)
        if why:   # r1929 True = 이번 바퀴 끝(handled 0) · 문자열 = «복구 필요»
            return None if why is True else done("HELD-NEXT", " launch %s · 복구 필요" % why)
    if need[1]:
        rc, text, err = k.call(["bash", k.env.get("FT2_CARD_ASSIGN_BIN") or os.path.join(os.path.dirname(k.close_bin or ""), "ft-card-assign-watch.sh"), "record", stem, "seat", nh], GIT_S)
        if rc != 0:
            return done("HELD-NEXT", " record rc %s %s · 복구 필요" % (rc, (text or err).strip()[:80]))
    done("NEXT", "")
