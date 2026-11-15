"""ft 2.0 keeper 다음 카드 (r1871 · keeper_close.close 가 닫기 영수 자리에서 부른다 · 코어 손 0).
고르기(읽기만) = 팀 카드 루트(directive-roots.tsv) 대기/ 카드 중 원장 seat·막힌 사유·ft2 owner 없음 → 긴급 → 우선 높음 → since 순 1장.
잇기 = submit → 최초이자 유일한 영수 1회(next·새 holder·evidence) → launch → record · 복구 = 저장 next·holder 로만 launch·record 를
«각각» 맞춘다(새 고르기 0 · handled 는 그 뒤) · 고를 카드 0 일 때만 팀장 [다음 없음] 1통(하루·팀 1키).
r1929 launch = 기다리지 않는다(keeper_launch · 띄우고 다음 바퀴에 의도를 읽어 잇기)."""
import hashlib, importlib.util, os, re, sys  # noqa: E401

HERE = os.path.dirname(os.path.abspath(__file__))
FT2, GIT_S, PENALTY_S = os.path.dirname(os.path.dirname(HERE)), 25, 7   # r2073 판정기 호출 7초(하드 룰 12)
OK, BLOCK, NONE = "접수 성공", ("정지", "석", "선행", "DA", "사람"), "[다음 없음]"
URGENT, HIGH = re.compile(r"- 긴급:\s*예\s*$"), re.compile(r"- 우선(?:순위)?:\s*높음")
REF = re.compile(r"(?<![A-Za-z0-9_])r(\d+)(?![0-9])")   # r2027 카드 참조 r<번호>
MONTH = re.compile(r"/아카이브/\d{4}-\d{2}")   # DA R1 월별 아카이브(루트 뒤 꼬리)
MARK = ("사람", "정지", "DA", "lint", "면제대기", "선행")   # r2058 L9 — 카드 «- 배정: 대기(<사유> · …)» 의 막는 사유(새 표식 · «석» 은 여기 없다)
def prereq(lines, where):
    """r2027 카드 본문 선행 막힘 = "" · "선행" · "선행불명"(판정 불가) · where = {번호: 카드가 있는 폴더 집합}.
    반환 = (판정, 까닭) — 까닭은 선행불명일 때만 찬다(`번호 참조 없음` · `루트에 없는 번호 r<a> r<b> …` · 없는 번호 전부·번호 순 · I2·I3).
    r2058 L9 — «- 배정: 대기(<사유> · 시각)» 의 사유가 사람·정지·DA·lint·면제대기·선행 이면 그 사유 그대로 막는다(«대기(석» 은 새 표식이 아니다)."""
    mark = next((x[len("- 배정: 대기("):].split(" · ")[0].strip().rstrip(")").strip() for x in lines if x.startswith("- 배정: 대기(")), "")
    if mark in MARK:
        return mark, ""   # ① 카드 배정 줄(원장·owner 를 본 뒤의 자리)
    val = next((x.split(":", 1)[1].strip() for x in lines if x.startswith("- 선행:")), "")
    if not val or val.startswith(("없음", "충족", "0", "—", "-")):
        return "", ""   # ② r1941 없음·충족·0·— = 막지 않음(주인이 고친 줄)
    nums = REF.findall(val)
    seen = [where.get(n, set()) for n in nums]
    if not seen:
        return "선행불명", "번호 참조 없음"   # ④ r 참조 없는 글
    if any(s & {"대기", "진행"} for s in seen):
        return "선행", ""   # ③ 안 끝난 참조
    if all(s & {"완성", "완성후", "아카이브"} for s in seen):
        return "", ""   # 끝난 참조
    miss = sorted({n for n in nums if not where.get(n)}, key=int)   # I2 없는 번호는 전부(첫 번호만 적지 않는다 · 번호 순)
    return "선행불명", "루트에 없는 번호 " + " ".join("r" + n for n in miss or sorted(set(nums), key=int))   # 루트에 없는 참조 = 판정 불가
def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_keeper_next_" + name, os.path.join(FT2, "core", name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
cli, dispatch = _load("cli"), _load("dispatch")
_kl = importlib.util.spec_from_file_location("ft2_keeper_next_launch", os.path.join(HERE, "keeper_launch.py"))
kl = importlib.util.module_from_spec(_kl)
_kl.loader.exec_module(kl)
_lp = importlib.util.spec_from_file_location("ft2_keeper_next_plan", os.path.join(HERE, "launch_plan.py"))
lp = importlib.util.module_from_spec(_lp)   # r2030 짝 표 대기 카드(mapped_cards) = 발주문·sparse 와 같은 함수
_lp.loader.exec_module(lp)
def ft2_state(k, team):
    try:
        return dispatch.Dispatch(k.root, team).ex._state_records()[0]
    except ValueError:
        return None
def once(k, key, read):
    """r1969 바퀴 캐시 — 같은 바깥 읽기 = 바퀴당 1회(팀 사이 공유) · keeper._round 가 열고 닫음(바퀴 밖 = 캐시 0) · kill·launch 뒤 ls 버림(keeper.call)."""
    got, fn = k.cache.get("@round"), read if callable(read) else lambda: k.call(read)
    return fn() if got is None else got[key] if key in got else got.setdefault(key, fn())
def nano_name(k, team, stem):
    """r2016 나노 좌석 이름 = stem 앞 40자 · 끝 «-» 지움(1.x ft-nano-spawn.sh _slug 와 같은 규칙) · 빈 값 = None + 경고 1줄(지어내기 0)."""
    cut = stem[:40].rstrip("-")
    return "byz-%s-nano-%s#0" % (team, cut) if cut else k.log("경고", team, "%s 나노 이름 빈 값 — 그 카드 0" % stem)
def ledger(k, stem):
    return k.read_json(os.path.join(k.root, ".fable-team", "state", "card-assign", stem + ".json"))
def skip_landed(k, team, stem):
    """r2058 L5 — 착지 판독(바퀴 캐시 · 카드당 1회) 참 = fill·닫기 뒤 pick 둘 다 고르지 않는다 · `NEXT-SKIP` 1줄(값이 바뀔 때만)."""
    landed = once(k, ("landed", team, stem), lambda: k.landing(team, stem))
    yes = bool(landed[0]) and not landed[2]
    book, key = k.state.setdefault("next_skip", {}), "%s|%s" % (team, stem)
    if book.get(key) != yes:
        book[key] = yes
        if yes:
            k.log("NEXT-SKIP", team, "%s 이미 착지 — 카드 정리 필요" % stem)
    return yes
def gates(k, team):
    """참 = 다음 카드 칸이 열림 · 거짓 = 0(켜기 전·팀 정지·spawn·계정 정지·나노 상한 · 판정 불가 포함)."""
    st = os.path.join(k.root, ".fable-team", "state")
    if not os.path.exists(os.path.join(k.root, ".fable-team", "teams", team, "CLOSE-NEXT.enabled")) or os.path.lexists(os.path.join(st, "%s-tick" % team, "PAUSED")):
        return False
    for name, tool, args, on in (("SPAWN_HOLD", "spawn-hold", [str(k.read_json(os.path.join(st, "SPAWN_HOLD")).get("verdict"))], 0), ("ACCT_PAUSE", "acct-pause", ["--agent", "pi"], 3)):
        rc = once(k, tool, ["bash", os.path.join(os.path.dirname(k.close_bin or ""), "ft-%s.sh" % tool), "status", "--check"] + args)[0] if os.path.lexists(os.path.join(st, name)) else 3 - on
        if rc != 3 - on:   # 끔 = hold rc3 · acct rc0 — 유효·판정 불가 = 0
            return k.log("NEXT-HOLD", team, "%s %s rc %s — 다음 카드 0" % (name, "유효" if rc == on else "판정 불가", rc))
    home = os.path.join(k.env.get("HOME") or os.path.expanduser("~"), ".claude", "fable-team", "thresholds.env")   # r1860 순서 = env > 루트 > ~/.claude > 샘플
    files = [p for p in (os.path.join(k.root, ".fable-team", "thresholds.env"), home, os.path.join(HERE, "thresholds.env.sample")) if os.path.isfile(p)]
    cap = (k.env.get("FT2_TEAM_NANO_MAX") or next((x.split("=", 1)[1].strip() for p in files for x in open(p, encoding="utf-8") if x.startswith("FT2_TEAM_NANO_MAX=")), "")).strip()
    if not (cap.isascii() and cap.isdigit()):   # R3 — 못 정함 = 새 실행 0(임의 기본값 0)
        return k.log("판정 불가", team, "나노 상한 FT2_TEAM_NANO_MAX 못 정함(%r · env·thresholds.env) — 다음 카드 0" % cap[:20])
    rc, out, _ = once(k, "ls", [k.tmux, "list-sessions", "-F", "#{session_name}"])   # r1969 바퀴당 1회 · 여는 중 합집합은 부를 때마다
    live = sum(x.startswith("byz-%s-nano-" % team) for x in set(out.split()) | k.cache.get("launching", set())) if rc == 0 else None   # r1929 여는 중 = 1칸
    k.fa.observe(k.root, "나노 정원", team, live, int(cap), "다음 카드")   # r1886 ⓑ 열림·NEXT-HOLD 둘 다
    return True if live is not None and live < int(cap) else k.log("NEXT-HOLD", team, "나노 %s / 상한 %s — 다음 카드 0" % (live, cap))
def penalty_seen(k, team, val):
    """r2073 P6·P7 — 값이 바뀔 때만 1줄 · 기억은 keeper 상태 파일(state["penalty_seen"][팀]) · val = "" 열림 · "hold" 재개 전 · "rc <값>" 판정 불가."""
    book = k.state.setdefault("penalty_seen", {})
    if book.get(team, "") == val:   # 같은 값 = 줄 0(재기동해도 상태 파일에 남아 있다)
        return not val
    if val:
        book[team] = val
        k.log("NEXT-HOLD" if val == "hold" else "판정 불가", team,
              "PENALTY_STOP 재개 전 — 다음 카드 0" if val == "hold" else "PENALTY_STOP 판독 %s — 다음 카드 0" % val)
        return False
    book.pop(team, None)   # 기억에 있던 팀이 풀렸다 = 이때만 1줄
    k.log("NEXT-OPEN", team, "PENALTY_STOP 풀림")
    return True
def penalty_open(k, team):
    """r2073 P1·P2 — 참 = 새 카드를 넣어도 됨. state/PENALTY_STOP 없음 = 참(판정기 호출 0) · 있음 = ft-penalty.sh check <팀>
    rc 0 = 참 · rc 3 = 거짓 · 그 밖(rc 1·2 · 도구 없음 · 시간 초과) = 거짓 + 판정 불가. 판정기는 1.x ft_penalty.py 한 곳이 한다(JSON 직접 풀기 0)."""
    if not os.path.exists(os.path.join(k.root, ".fable-team", "state", "PENALTY_STOP")):
        return penalty_seen(k, team, "")
    judge = k.env.get("FT2_PENALTY_BIN") or os.path.join(os.path.dirname(k.close_bin or ""), "ft-penalty.sh")
    rc = once(k, ("penalty", team), lambda: penalty_rc(k, judge, team))   # 팀당 바퀴 1회
    return penalty_seen(k, team, "" if rc == 0 else "hold" if rc == 3 else "rc %s" % rc)
def penalty_rc(k, judge, team):
    """판정기 1회 = rc(k.call 은 실패·시간 초과를 None 으로 준다) · 판정기는 FT_ROOT 로 루트를 받는다."""
    outer, k.env = k.env, dict(k.env, FT_ROOT=k.root)
    try:
        return k.call(["bash", judge, "check", team], PENALTY_S)[0]
    finally:
        k.env = outer
def new_card_hold(k, team):
    """r2101 H1~H5 — 새 카드 보류 설정 1개(state/NEW_CARD_HOLD.json) · 참 = 카드 고르기 두 곳(fill pick·닫기 뒤 pick)만 막힌다.
    판독 = 바퀴당 1회(once · 팀 사이 공유) · 없음 = 거짓(열림) · 있음 = 참 + 팀마다 `NEW-CARD-HOLD <reason> · until <until>` 1줄(값이 바뀔 때만) ·
    깨짐(빈 파일·JSON 아님·reason 없음) = 참 + `판정 불가` 1줄. gates()·ALL_STOP·팀 PAUSED·팀장 개설은 안 본다(H7·H8)."""
    got = once(k, "new-card-hold", lambda: hold_read(k, os.path.join(k.root, ".fable-team", "state", "NEW_CARD_HOLD.json")))
    book = k.state.setdefault("new_card_hold_seen", {})
    val = "" if got is None else "깨짐" if isinstance(got, str) else "|".join(got)
    if book.get(team, "") == val:   # 같은 값 = 줄 0(재기동해도 상태 파일에 남아 있다)
        return bool(val)
    if not val:   # 기억에 있던 팀이 풀렸다 = 이때만 1줄
        book.pop(team, None)
        k.log("NEW-CARD-OPEN", team)
        return False
    book[team] = val
    if isinstance(got, str):
        k.log("판정 불가", team, "NEW_CARD_HOLD 판독 불가(빈 파일·JSON 아님·reason 없음) — 새 카드 0")
    else:
        k.log("NEW-CARD-HOLD", team, "%s · until %s" % got)
    return True
def hold_read(k, path):
    """H1·H2 판독 1회 — 없음 = None · 있음 = (reason, until) · 깨짐 = "깨짐"(추측 채움 0)."""
    if not os.path.lexists(path):
        return None
    data, reason = k.read_json(path), ""
    if isinstance(data.get("reason"), str):
        reason = data["reason"].strip()
    if not reason:   # 빈 파일·JSON 아님(read_json = {})·reason 없음
        return "깨짐"
    return reason, str(data.get("until") or "").strip() or "-"
def cards(k, team):
    """({stem: [긴급, 높음, 대상 줄들, 선행 막힘]}, 루트 행) · 판독 실패 = 사유 문자열 (git 2회 · 작업 트리 0)."""
    try:
        with open(os.path.join(k.root, ".fable-team", "state", "directive-roots.tsv"), encoding="utf-8") as fh:
            rows = [x.rstrip("\n").split("\t") for x in fh if not x.startswith("#") and len(x.split("\t")) >= 4]
    except (OSError, UnicodeError):
        rows = []
    r = next((x for x in rows if x[0] == team), None) or next((x for x in rows if x[0] == "*"), None)
    if not r:
        return "카드 루트 표 행 없음"
    raw, r = r[3], [r[0], os.path.join(k.root, r[1]), r[2], r[3].replace("*", team)]   # r1969 raw git = (리포·ref·표 행 루트) 바퀴당 1회 · 팀 걸러내기는 따로
    rc, names, err, rc2, heads = once(k, ("cards", r[1], r[2], raw), lambda: k.git(r[1], "ls-tree", "-r", "--name-only", r[2], "--", raw.split("*")[0] if "*" in raw else raw + "/")   # r2027 루트 전체 = 선행 참조 폴더
                                      + k.git(r[1], "grep", "-I", "-E", r"^- (긴급|우선|대상|선행|배정)", r[2], "--", ":(glob)%s/대기/*" % raw)[:2])
    if rc != 0 or rc2 not in (0, 1):
        return "카드 루트 git rc %s/%s %s" % (rc, rc2, err[:60])
    mine = r[3] + "/대기"
    found = {os.path.basename(p)[:-3]: [False, False, [], []] for p in names.splitlines() if p.endswith(".md") and os.path.dirname(p) == mine}
    where = {}
    for p in (x for x in names.splitlines() if x.endswith(".md") and (os.path.dirname(os.path.dirname(x)) == r[3] or x.startswith(r[3] + "/") and MONTH.fullmatch(os.path.dirname(x)[len(r[3]):]))):
        m = re.match(r"r(\d+)(?![0-9])", os.path.basename(p))   # DA R1 · 아카이브/<YYYY-MM>/ = 아카이브
        where.setdefault(m.group(1), set()).add("아카이브" if os.path.dirname(os.path.dirname(p)) != r[3] else os.path.basename(os.path.dirname(p))) if m else None
    for path, _, line in (x[len(r[2]) + 1:].partition(":") for x in heads.splitlines()):
        row = found.get(os.path.basename(path)[:-3]) if os.path.dirname(path) == mine else None
        if row is not None:
            row[0], row[1] = row[0] or bool(URGENT.match(line)), row[1] or bool(HIGH.match(line))
            row[2] += [line] if line.startswith("- 대상") else []
            row[3] += [line] if line.startswith(("- 선행", "- 배정")) else []
    mapped(k, team, found, where)   # r2030 짝 표 대기 카드(팀 폴더 밖 포함)
    for row in found.values():
        val = next((x.split(":", 1)[1].strip() for x in row[3] if x.startswith("- 선행:")), "")   # I1 기억에 넣을 선행 값 그대로
        verdict, why = prereq(row[3], where)
        row[3], row[4:] = verdict, [{"val": val, "why": why}]   # row[4] = I1·I6 기억 값
    return found, r
def mapped(k, team, found, where):
    """r2030 짝 표 대기 카드 → found 후보(같은 stem 1개) · 그 카드 indices 의 완성·완성후·아카이브(월별 포함) 참조 → where(DA R2).
    짝 work ≠ 카드 stem(별칭) = 후보 0 + 1줄(DA R1 · 별칭 기동 지원 0) · 판독 실패 = 지금 길 + 1줄."""
    mc = lp.mapped_cards(k.root, team)
    if isinstance(mc, str):
        return once(k, ("map-log", team), lambda: k.log("경고", team, "%s — 팀 폴더 대기 카드만" % mc))
    for work, (repo, ref, path) in sorted(mc.items()):
        stem, idx = os.path.basename(path)[:-3], lp.WAIT.match(path).group(1)
        if work != stem:
            once(k, ("map-alias", team, work), lambda: k.log("경고", team, "짝 표 별칭 — keeper 후보 0 %s" % work))
            continue
        if stem in found:
            continue
        rc3, text, _ = once(k, ("mapped", repo, ref, path), lambda: k.git(repo, "show", "%s:%s" % (ref, path)))
        rc4, names, _ = once(k, ("mapped-tree", repo, ref, idx), lambda: k.git(repo, "ls-tree", "-r", "--name-only", ref, "--", idx + "/"))
        if rc3 != 0 or rc4 != 0:
            once(k, ("map-show", team, path), lambda: k.log("판정 불가", team, "짝 표 카드 %s:%s git rc %s/%s — 건너뜀" % (ref, path, rc3, rc4)))
            continue
        heads = [x for x in text.splitlines() if re.match(r"- (긴급|우선|대상|선행|배정)", x)]
        found[stem] = [any(URGENT.match(x) for x in heads), any(HIGH.match(x) for x in heads), [x for x in heads if x.startswith("- 대상")], [x for x in heads if x.startswith(("- 선행", "- 배정"))]]
        for p in (x for x in names.splitlines() if x.endswith(".md")):
            m, stage = re.match(r"r(\d+)(?![0-9])", os.path.basename(p)), "아카이브" if MONTH.fullmatch(os.path.dirname(p)[len(idx):]) else os.path.basename(os.path.dirname(p)) if os.path.dirname(os.path.dirname(p)) == idx else ""
            where.setdefault(m.group(1), set()).add(stage) if m and stage in ("완성", "완성후", "아카이브") else None
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
    for stem, (urgent, high, lines, pre, seen) in sorted(found.items()):
        led = ledger(k, stem)
        block = "배정됨" if led.get("state") == "seat" or stem in owners else led.get("reason") if led.get("reason") in BLOCK else pre   # r2027 ⑤ 원장·카드 둘 중 하나
        if pre == "선행불명":   # I1·I2 — 값·까닭이 바뀔 때만 1줄(기억 = keeper 상태 파일 · 재기동해도 다시 찍지 않는다 · DA 310229)
            book, key = k.state.setdefault("prereq_seen", {}), "%s|%s" % (team, stem)
            if book.get(key) != seen:
                book[key] = seen
                k.log("판정 불가", team, "%s 선행 줄 판독 불가(%s) — 건너뜀 · 고칠 꼴 «- 선행: 없음» 또는 «- 선행: r<번호>»" % (stem, seen["why"]))
        block = block or ("보류" if stem in skip else "끝남" if stem in done or pair.get(stem, set()) & set(done) else "")   # r1887 stem·짝 work done
        block = block or ("착지" if skip_landed(k, team, stem) else "")   # r2058 L5 착지 카드 = 다시 넣지도 닫기 뒤 다음으로도 고르지 않는다
        place = None if block else target(k, r, lines)
        if not block and place is None:
            block = k.log("판정 불가", team, "%s 대상 팩·BYZ 둘 다 — 건너뜀" % stem) or "대상"
        block = block or ("팩낡음" if place[0] in k.stale else "")   # r1963 낡은 팩 base 로 나노 열기 0(이 바퀴 보류 · BYZ 대상 카드는 그대로)
        ready.append(((not urgent, not high, led.get("since") or 0), stem) + place) if not block else why.update({block: why.get(block, 0) + 1})
    if why.get("팩낡음"):
        k.log("판정 불가", team, "다음 카드 보류 %d장 · 팩 fetch 실패" % why["팩낡음"])
    prereq_tell(k, team, {s: row[4] for s, row in found.items() if row[3] == "선행불명"})   # I4~I8 · 고를 카드가 있든 없든 간다
    if ready or why.get("팩낡음"):   # 보류뿐이면 [다음 없음] 쪽지 0
        return min(ready)[1:] if ready else None
    k.notify(team, "%s|next-none|%s" % (k.stamp()[:10], team), "%s %s · 배정 없는 카드 0 · 막힌 사유별 %s" % (NONE, team, " ".join("%s %d" % kv for kv in sorted(why.items())) or "0"))
def prereq_mute(k, team):
    """P1 묵음 — 전팀 정지(k.halt) · 팀 PAUSED(state/<팀>-tick/PAUSED) · 새 카드 보류(NEW_CARD_HOLD.json · 깨짐 포함) 중 하나라도 참.
    판정 자리 = prereq_tell 안 1곳(부르는 쪽 앞 조건이 나중에 바뀌어도 새지 않게 하는 방어 · 설계 P1)."""
    st = os.path.join(k.root, ".fable-team", "state")
    return bool(k.halt) or os.path.lexists(os.path.join(st, "%s-tick" % team, "PAUSED")) or new_card_hold(k, team)

def prereq_path(k, team):
    """P4 목록 파일 자리 = <root>/.fable-team/state/ft2-keeper/prereq-<팀>.txt(팀마다 1개 · 일반 파일)."""
    return os.path.join(k.dir, "prereq-%s.txt" % team)

def prereq_list(k, team, unread, changed):
    """P4 — prereq_tell 이 불린 바퀴에 (지문이 바뀌었거나 목록 파일이 없으면) 원자 쓰기(tmp → replace) · 빈 묶음이면 지운다 · 파일 있고 지문 그대로 = 손 0.
    첫 줄 = `# 관측 <시각> · <n>장`(마지막으로 고른 바퀴의 값) · 그 아래 줄마다 `<카드>\\t<선행 값>\\t<까닭>` 이름순 · 3장 이하도 쓴다.
    파일 없이 지문만 있는 상태 = 옛 판이 만든 상태(판 올림 승계 · DA 312085 반례) — 그 바퀴에 한 번 만든다(지문이 같아도)."""
    path = prereq_path(k, team)
    if not unread:   # 빈 묶음 = 지운다
        if os.path.lexists(path):
            os.unlink(path)
        return
    if not changed and os.path.lexists(path):   # 지문 그대로 · 파일 있음 = 쓰지도 지우지도 않는다(P0 · ㊵바·㊵사)
        return
    os.makedirs(k.dir, exist_ok=True)
    body = "# 관측 %s · %d장\n" % (k.stamp(), len(unread)) + "".join("%s\t%s\t%s\n" % (s, v["val"], v["why"]) for s, v in sorted(unread.items()))
    with open(path + ".tmp", "w", encoding="utf-8") as fh:
        fh.write(body)
    os.replace(path + ".tmp", path)

def prereq_body(k, team, unread):
    """P3 본문 = 3장까지는 지금 글 그대로 · 3장을 넘으면 «전체 목록 <경로>» 칸 하나를 붙인다(I5 가 바뀌는 곳 · P8)."""
    head = "[다음 막힘] %s 선행 줄을 못 읽는 카드 %d장: %s" % (team, len(unread), " · ".join(sorted(unread)[:3]))
    tail = " · 전체 목록 %s" % prereq_path(k, team) if len(unread) > 3 else ""
    return head + tail + " · 고칠 꼴 «- 선행: 없음» 또는 «- 선행: r<번호>»"

def prereq_tell(k, team, unread):
    """I4~I8 + P1~P6 — 선행불명 기억 치우기 + 묶음 지문·전이 번호 + 팀장 [다음 막힘] 1통(마지막으로 전한 묶음과 다를 때만).
    unread = {카드: {"val": 선행 값, "why": 까닭}} · 기억 셋은 모두 keeper 상태 파일 키다(재기동해도 이어진다 · I9) ·
    P0 = 이 함수가 불린 바퀴에만 손 · P1 묵음 = 전팀 정지·팀 PAUSED·새 카드 보류 중이면 쪽지 0(now·목록 파일은 고친다) ·
    P4 목록 파일 = 지문이 바뀐 바퀴에만 · P5 팀장 없음 = 쪽지 대신 PREREQ-WAIT 1줄 · P6 순서 = 빔 → P1 → P5 → I8."""
    book = k.state.setdefault("prereq_seen", {})
    for key in [x for x in book if x.split("|")[0] == team and x.split("|")[1] not in unread]:   # I4 선행불명이 아니게 되거나 대기에서 사라짐
        book.pop(key)
    fp = hashlib.sha1("\n".join("%s\t%s\t%s" % (s, v["val"], v["why"]) for s, v in sorted(unread.items())).encode("utf-8")).hexdigest()[:12] if unread else ""   # I6 묶음 지문
    now, told, prev = k.state.setdefault("prereq_now", {}), k.state.setdefault("prereq_told", {}), k.state.setdefault("prereq_now", {}).get(team) or {}
    n = prev.get("n") if prev.get("fp", "") == fp else (prev.get("n") or 0) + 1   # I7 전이 번호 = 묶음이 바뀔 때마다 +1
    now[team] = {"fp": fp, "n": n}
    wait = k.state.setdefault("prereq_wait", {})   # P5 기억 = 마지막으로 보류한 묶음 지문(새 키 1개 · 옛 판은 읽지 않는다)
    prereq_list(k, team, unread, prev.get("fp", "") != fp)   # P4 — 바뀐 바퀴에만 쓰기·지우기(보류 바퀴 = 마지막 관측값 그대로)
    if not fp:   # I7 지금 묶음이 비면 told·보류 기억을 비우고 목록 파일을 지운다
        told.pop(team, None)
        wait.pop(team, None)
        return
    if prereq_mute(k, team):   # P1 — 묵음 = 쪽지 0(told 그대로 · now·목록 파일은 위에서 고친다)
        return
    to, stand = k.recipients(team)   # P5 팀장 판독 = keeper 쪽지 받는 곳 차례 그대로(그 팀 _master → _desk → harness _master)
    if not to or stand:   # P5 팀장 없음 = 쪽지 대신 PREREQ-WAIT 1줄(묶음에 쌓지 않는다)
        if wait.get(team) != fp:   # 묶음 지문이 바뀔 때만 1줄(보류 중 되풀이 0)
            wait[team] = fp
            k.log("PREREQ-WAIT", team, "팀장 없음 — 선행 줄 쪽지 보류 %d장 · 목록 %s" % (len(unread), prereq_path(k, team)))
        return
    wait.pop(team, None)   # 팀장이 선 바퀴 = 보류 기억 지움(그 묶음은 I8 로 나간다)
    if told.get(team) == fp:   # I8 마지막으로 전한 묶음 그대로 = 보내지 않는다
        return
    ok = k.notify(team, "prereq|%s|%s|%s" % (team, fp, n), prereq_body(k, team, unread))
    if ok:   # I8 성공(rc 0·도착 확인)일 때만 told 를 바꾼다 · 실패·넘김(defer)은 그대로
        told[team] = fp


def close(k, team, work, attempt, holder, gen):
    """닫기 영수 1회(지금 자리) + 다음 카드. 반환 = 영수 결과. r2101 H3 = 새 카드 보류면 이 고르기만 멈춘다(영수·이어 잇기 그대로)."""
    seen = ((ft2_state(k, team) or {}).get("close_receipts") or {}).get("keeper:%s@%s" % (work, attempt))
    pick = None
    if seen is None and not new_card_hold(k, team):
        pick = choose(k, team) if gates(k, team) and penalty_open(k, team) else None
        pick = pick if pick and nano_name(k, team, pick[0]) else None   # r2016 빈 이름 = submit 전 그 카드 0
        if pick:
            out, rc = cli.run(["submit", "--command", "keeper-next-" + pick[0], "--body", "카드 " + pick[0], "--work", pick[0], "--root", k.root, "--team", team])
            k.fa.remaining(k.root, team, out.get("result"), "카드 " + pick[0])   # r1886 ⓐ keeper submit
            pick = pick if rc == 0 or "재부여 0" in str(out.get("reason")) else k.log("판정 불가", team, "%s submit %s" % (pick[0], out.get("result")))
        stem, nh = (pick[0], nano_name(k, team, pick[0])) if pick else (None, None)
    elif seen is not None:
        stem, nh = seen.get("next"), seen.get("holder")
    else:   # 새 카드 보류(H3) = 다음 카드 없음 · 영수는 그대로 쓴다
        stem, nh = None, None
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
    n, seen = out.get("capacity", out.get("remaining")) if out.get("result") == OK else None, k.state.setdefault("fill_wait", {})   # r2055 용량 셈(쉼 제외 · work 단위)
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
        reconcile(k, team, "fill:" + stem, opened[x], stem, nano_name(k, team, stem), None)
        opened.pop(x) if "%s|fill:%s@%s" % (team, stem, opened[x]) in k.state["handled"] else None
    if mine:
        return None
    [held.pop(x) for x in list(held) if x.split("|")[0] == team and (ledger(k, x.split("|", 1)[1]).get("updated") or 0) > float(str(held[x]).split("|")[0])]   # 풀림 · r1939 값 = 시각 또는 «시각|사유»
    if new_card_hold(k, team):   # r2101 H3 — 보류 = 새 카드 고르기만 멈춘다(위 이어 열기·settle·닫기는 그대로)
        return None
    pick = intake_open(k, team) and choose(k, team, {x.split("|", 1)[1] for x in held if x.split("|")[0] == team}) if gates(k, team) and penalty_open(k, team) else None
    if not pick:
        return None
    stem, attempt, nh = pick[0], None, nano_name(k, team, pick[0])
    if not nh:   # r2016 빈 이름 = 채우기 0(경고 1줄은 nano_name)
        return None
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
        if place and place[0] in k.stale:   # r1963 복구 launch 도 낡은 팩 base 로는 안 연다(handled 0 · 다음 바퀴)
            return k.log("판정 불가", team, "%s -> %s 다음 카드 보류 · 팩 fetch 실패" % (work, stem))
        argv = [sys.executable, k.env.get("FT2_KEEPER_LAUNCH") or os.path.join(HERE, "launch.py"), "--root", k.root, "--team", team, "--work", stem, "--repo", place[0], "--base", place[1], "--role", "session"] if place else None
        att = (((ft2_state(k, team) or {}).get("deliveries") or {}).get(stem) or [None])[-1]
        spot = os.path.join(kl.projection.runtime_path(k.root, team), "launch", "%s@%s" % (stem, att))
        if place and "repo:" + place[0] in k.cache.setdefault("launching", set()) and not any(os.path.exists(spot + x) for x in (".intent", ".owner")):   # r1967 ① 같은 리포 새 열기 = 바퀴당 1개 · 나머지 다음 바퀴(여는 중 = 1칸)
            return kl.busy(k, team, nh, "LAUNCH-WAIT", "같은 리포 열기 1개 · 다음 바퀴") and None
        why = kl.launching(k, team, stem, att, nh, argv)
        k.cache.setdefault("launching", set()).add("repo:" + place[0]) if why is True and place else None   # 여는 중 셈과 같은 수명(바퀴마다 새로 · 나노 칸 셈 밖 글자)
        if why:   # r1929 True = 이번 바퀴 끝(handled 0) · 문자열 = «복구 필요»
            return None if why is True else done("HELD-NEXT", " launch %s · 복구 필요" % why)
    if need[1]:
        rc, text, err = k.call(["bash", k.env.get("FT2_CARD_ASSIGN_BIN") or os.path.join(os.path.dirname(k.close_bin or ""), "ft-card-assign-watch.sh"), "record", stem, "seat", nh], GIT_S)
        if rc != 0:
            return done("HELD-NEXT", " record rc %s %s · 복구 필요" % (rc, (text or err).strip()[:80]))
    done("NEXT", "")
