"""ft 2.0 keeper 끝 판정 (r1960 · DA APPROVE-DESIGN #301612) — ① pr_landed: 착지 줄 없음 → 가지 nano/<work> merged PR 정확히 1개 ∧ mergeCommit
허용 base 조상 ∧ pre_attempt(HEAD 조상 단독·추측 0) ② ending: 우선 ref 단일 카드 완성후·아카이브 · «## 상태» 마지막 유효 항목 머리(refuse 0)
③ intent 대체 ④ unsure 재깨움 1회 → [크리티컬] 1통/일 ⑤ orphans: 스냅샷 «뒤» journal 새로 읽기 · launch intent 근거 ∧ 끝 ∧ 가드 → kill 1.
"""
import glob, importlib.util, json, os, re  # noqa: E401
HERE = os.path.dirname(os.path.abspath(__file__))
GH_S, BASES, DONE, HEADS = 7, ("main", "ops/main-base"), ("완성후", "아카이브"), (("중단:", "suspended"), ("대체:", "superseded"), ("거절:", "superseded"))
ORPHAN, REPO, SHA = re.compile(r"byz-([a-z0-9]+)-nano-(.+)#\d+"), re.compile(r"github\.com[:/]([^/]+/[^/]+?)(?:\.git)?/?$"), re.compile(r"[0-9a-f]{40}")
_MOD = {}
def _mod(name, path):
    if name not in _MOD:   # keeper_land 는 늦게 읽는다(keeper_land 가 이 파일을 읽으므로 순환 0)
        _MOD[name] = importlib.util.module_from_spec(spec := importlib.util.spec_from_file_location("ft2_keeper_endings_" + name, path))
        spec.loader.exec_module(_MOD[name])
    return _MOD[name]
def _proj():
    return _mod("projection", os.path.join(os.path.dirname(os.path.dirname(HERE)), "core", "projection.py"))
def held(k, team, key, text):
    """같은 사유 1회 HELD 1줄(held 키) · 반환 None."""
    if k.state["held"].get(key) != text:
        k.state["held"][key] = text
        k.log("HELD", team, text)
def _rows(k, team):   # journal 새로 읽기 · 못 읽음 = None(판독 실패 = 대체·고아 닫기 0)
    try:
        return _proj().journal.Journal(_proj().runtime_path(k.root, team), rec=_proj().record).records()
    except (OSError, ValueError):
        return None
def latest(k, team):   # {work: (attempt, holder)} 최신 dispatch · 못 읽음 = None
    rows = _rows(k, team)
    return None if rows is None else {r["work"]: (r.get("attempt"), r.get("holder")) for r in rows if r.get("kind") == "dispatch" and r.get("work")}
def intents(k, team, pattern="*"):
    for path in sorted(glob.glob(os.path.join(glob.escape(os.path.join(_proj().runtime_path(k.root, team), "launch")), pattern + "@*.intent"))):
        work, _, attempt = os.path.basename(path)[:-len(".intent")].rpartition("@")
        yield work, attempt, k.read_json(path)
def intent(k, team, work, attempt, holder):
    """③ 그 attempt intent · 없으면 같은 work·holder·opened ∧ journal 에서 그 holder 에 dispatch 된 attempt 의 최신 1개(close·pre_attempt 공용 · DA R1 #301944)."""
    got = k.read_json(os.path.join(_proj().runtime_path(k.root, team), "launch", "%s@%s.intent" % (work, attempt)))
    if got.get("state") == "opened" and got.get("FT2_HOLDER"):
        return got
    sent = {r.get("attempt") for r in _rows(k, team) or () if r.get("kind") == "dispatch" and r.get("work") == work and r.get("holder") == holder}
    rows = [r for _, a, r in intents(k, team, glob.escape(work)) if a in sent and r.get("state") == "opened" and r.get("FT2_HOLDER") == holder]
    return max(rows, key=lambda r: str(r.get("at") or ""), default={})
def _prs(k, repo, branch):
    rc, out, _ = k.call([k.env.get("FT2_GH") or "gh", "pr", "list", "-R", repo, "--head", branch, "--state", "merged",
                         "--json", "number,mergeCommit,baseRefName"], GH_S, retry=1)
    try:
        return json.loads(out) if rc == 0 else None
    except ValueError:
        return None
def _common(k, repo):   # git common-dir(clone·linked worktree 는 remote-tracking ref 공유) · 못 읽음 = 경로 그대로
    return os.path.realpath(k.git(repo, "rev-parse", "--path-format=absolute", "--git-common-dir")[1].strip() or repo)
def pr_landed(k, team, work):
    """① (mergeCommit, 근거 ref, "") · 근거 못 채움 = (None, None, "착지 줄 없음") · 옛 착지 = (None, None, 사유)."""
    none = (None, None, "착지 줄 없음")
    attempt, holder = (latest(k, team) or {}).get(work, (None, None))
    it = intent(k, team, work, attempt, holder) if attempt else {}
    tree = it.get("worktree") or ""
    if not os.path.isdir(tree) or k.git(tree, "rev-parse", "--abbrev-ref", "HEAD")[1].strip() != "nano/" + work:
        return none
    if bad := [r for r in sorted(getattr(k, "stale", ())) if _common(k, r) == _common(k, tree)]:   # DA R2 #302302 — 낡은 리포 ref = 조상 검사 0
        return None, None, "판정 불가 · %s fetch 실패" % bad[0]
    url = k.git(tree, "config", "--get", "remote.origin.url")[1].strip()
    prs = _prs(k, REPO.search(url).group(1) if REPO.search(url) else url, "nano/" + work)
    pr = prs[0] if isinstance(prs, list) and len(prs) == 1 and isinstance(prs[0], dict) else {}
    sha, base = str((pr.get("mergeCommit") or {}).get("oid") or ""), pr.get("baseRefName")
    if not SHA.fullmatch(sha) or base not in BASES or k.git(tree, "merge-base", "--is-ancestor", sha, "origin/" + base)[0] != 0:
        return none
    if old := k.pre_attempt(team, work, tree, sha, it):
        return None, None, old
    k.notify(team, "%s|noline|%s|%s" % (k.stamp()[:10], team, work), "[줄 보완] ft2 keeper %s 카드 착지 줄 없음 · PR #%s 병합 %s — 카드에 «- 착지: %s» 보완(keeper 카드 쓰기 0)" % (work, pr.get("number"), sha[:10], sha))
    return sha, "origin/%s · 착지 줄 없음 · PR #%s 병합" % (base, pr.get("number")), ""
def _cards(k, team, ref):
    """우선 ref 의 팀 폴더 indices 아래 .md 전부(단계 5 · 아카이브 하위 폴더 포함) · 판독 실패 = None · 바퀴 안 캐시."""
    if ("endings", team, ref) not in k.cache:
        land, names = _mod("land", os.path.join(HERE, "keeper_land.py")), []
        rc, md, _ = k.git(k.root, "show", ref + ":design/TEAMS.md")
        row = land.team_row(md, team) if rc == 0 else None
        for folder in land.folders(row[1]) if row else ():
            rc, out, _ = k.git(k.root, "ls-tree", "-r", "--name-only", ref, "--", folder + "/indices")
            names = names + [(folder, p) for p in out.splitlines()] if rc == 0 and names is not None else None
        k.cache[("endings", team, ref)] = names if row else None
    return k.cache[("endings", team, ref)]
def _head(body):
    """«## 상태» 절 마지막 유효 항목(맨 줄 «중단:» 포함)의 머리 → (결과, 근거) | None."""
    part = re.split(r"^## 상태[ \t]*$", body, maxsplit=1, flags=re.M)
    rows = [x.strip() for x in re.split(r"^## ", part[1], maxsplit=1, flags=re.M)[0].splitlines() if x.strip()] if len(part) == 2 else []
    last = re.sub(r"^\d{4}-\d{2}-\d{2}[^—]*—\s*", "", re.sub(r"^-\s*", "", rows[-1])) if rows else ""
    return next(((kind, "상태 " + last[:60]) for head, kind in HEADS if last.startswith(head)), None)
def ending(k, team, work):
    """② landed 아닌 끝 → (suspended|superseded, 근거) | None · 우선 ref 에 후보 2개↑·판독 실패 = None(추측 0)."""
    land = _mod("land", os.path.join(HERE, "keeper_land.py"))
    for ref in land.REFS:
        if (names := _cards(k, team, ref)) is None:
            return None
        hits = [(f, p) for f, p in names if p.endswith(".md") and p[len(f) + 9:].split("/")[0] in land.STAGES + DONE
                and (os.path.basename(p) == work + ".md" or os.path.basename(p).startswith(work + "-"))]
        hits = [h for h in hits if os.path.basename(h[1]) == work + ".md"] or hits
        if len(hits) > 1:
            return None
        if hits:
            stage = hits[0][1][len(hits[0][0]) + 9:].split("/")[0]
            if stage in DONE:
                return "superseded", "카드 %s/" % stage
            rc, body, _ = k.git(k.root, "show", "%s:%s" % (ref, hits[0][1]))
            return _head(body) if rc == 0 else None
    return None
def unsure(st, team, work, holder, key, idle, fmt=None, slot=""):
    """④ 미확인 깨움 — after_s 뒤 재깨움 1회(정상·오류 턴 길 같은 rewoke 키) · 또 미확인 = harness master [크리티컬] 1통/일 · 재배정·kill 0."""
    k, retry = st.k, st.k.state.setdefault("rewoke", {})
    if key not in retry and k.now() - k.state["unsure"][key] >= st.after_s:
        retry[key] = k.stamp()
        return st.wake(team, work, holder, key, idle, fmt, slot)
    if key not in retry:
        return k.log("판정 불가", team, "%s %s 깨움 도달 미확인(%s) — 재깨움 %d초 뒤 1회 · 재배정 0" % (work, holder, k.state["unsure"][key], st.after_s))
    k.notify("harness", "%s|unsure|%s" % (k.stamp()[:10], key), "[크리티컬] ft2 keeper 깨움 도달 미확인 %s %s %s — 재깨움 1회 뒤에도 미확인 · 재배정·kill 0(사람·팀장 판단)" % (team, work, holder))
def orphans(k, teams):
    """⑤ 고아 — 이름 꼴 byz-<팀>-nano-<stem>#N ∧ 그 팀 최신 dispatch holder 밖 · 자동 개설 = ft2_holders.auto_opened(launch 영수 생애 결속) 공용."""
    H, alive = _mod("holders", os.path.join(HERE, "ft2_holders.py")), k.alive_sessions()
    held_by = {t: {h for _, h in got.values()} for t in teams if (got := latest(k, t)) is not None}
    for seat in sorted(alive or ()):
        team = m.group(1) if (m := ORPHAN.fullmatch(seat)) else None
        if team not in held_by or seat in held_by[team]:
            continue
        mine = [x for x in intents(k, team) if x[2].get("FT2_HOLDER") == seat]
        work, _, it = max(mine, key=lambda x: str(x[2].get("at") or "")) if len({x[0] for x in mine}) == 1 else (None, None, {})
        ok, why = H.auto_opened(k.call, k.tmux, seat, it) if work else (False, "자동 개설 근거 없음·모호(launch intent work %d개)" % len({x[0] for x in mine}))
        if not ok:
            if k.state["held"].get("orphan|" + seat) != k.stamp()[:10]:
                k.state["held"]["orphan|" + seat] = k.stamp()[:10]
                k.log("HELD-ORPHAN", team, "%s %s · 닫기 0" % (seat, why))
                k.notify(team, "%s|orphan|%s" % (k.stamp()[:10], seat), "[고아] ft2 keeper %s %s — 닫기 0(사람 확인)" % (seat, why))
            continue
        sha, _, why = k.landing(team, work)
        end = ("landed", sha) if sha and not why else ending(k, team, work)
        if not end or not k.idle(team, work, seat) or not k.turn_ended(team, work, seat, it) or k.held_attached(team, work, seat):
            continue
        if seat in {h for _, h in (latest(k, team) or {0: (0, seat)}).values()}:   # ⑦e 읽는 사이 holder 바뀜·판독 실패 = 닫기 0
            continue
        k.call([k.tmux, "kill-session", "-t", "=" + seat])
        gone = k.probe(seat)
        k.log("CLOSED-ORPHAN" if gone == "absent" else "HELD", team, "%s %s %s %s%s" % (work, seat, end[0], end[1], "" if gone == "absent" else " 부재 확인 없음(%s)" % gone))
