"""ft 2.0 keeper 멈춤 갈래 — 진척 0 좌석을 깨우고, 그래도 멈추면 같은 일을 새 attempt 로 재배정한다 (r1813 · 카드 r3 S1~S5 · DA#10 r3 APPROVE).

keeper.py 바퀴(team_round)가 «끝나지 않은 일» 마다 Stall.check 1회를 부른다(keeper.py 270줄 상한 → 이 파일로 나눔).
core 손 0 — 공개 동사(cli assign·deliver)와 읽기 함수(_state_records·_eligible·_hold·Lifecycle.scan)만 · reassess·complete 0.
launch.py 손 0 — 옛 worktree 에서 repo·base·role 을 복원해 부르기만 한다. 1.x ft-idle-wake·stall-scan 손 0.
S1 멈춤 = 마지막 진척(진척 줄 · 세션 mtime(깨움 전만) · worktree HEAD · 최신 deliver) 15분 ∧ IDLE ∧ 외부 대기 시한 밖 ∧ LOGGEDOUT 아님.
S2 깨움 = Escape 1 → 문구(-l) → Enter → 도달 확인 3회 · attempt 당 1회. S3 = 깨움 뒤 10분 → 사전 판독 → kill → assign(rotation) →
deliver → launch(단계 실패 = 멈춤 + 팀 master [크리티컬]). S4 = 같은 work 두 번째 S3 자동 0 · 쪽지 하루 1.
S5 = intent 없는 좌석(master·arch·DA·desk·1.x) 0. 하나라도 못 읽음 = 판정 불가 1줄 · 행동 0. 문턱 = 환경 변수로만 바꾼다.
"""
import glob, importlib.util, json, os, re, sys, time  # noqa: E401

HERE = os.path.dirname(os.path.abspath(__file__))
FT2 = os.path.dirname(os.path.dirname(HERE))
LAUNCH, LAUNCH_S = os.path.join(HERE, "launch.py"), 25     # launch = 로컬 하네스 25초(하드 룰 12)
STEPS, STAMP = ("start", "effect", "result", "complete"), "%Y-%m-%dT%H:%M:%S"
WAKE = "[깨움] ft2 keeper — 일 %s 진척 0 %d분 · 이어서 진행하거나 result 로 막힘을 기록하라"
BUSY = re.compile("Working|[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]")
NEXT, SHA = re.compile(r"^(.*#)(\d+)$"), re.compile(r"^[0-9a-f]{40}$")
TRUST = "Trust project folder"
ERR_WAKE = "[깨움] ft2 keeper — 일 %s 오류 턴 뒤 %d초 · 이어서 진행하거나 result 로 막힘을 기록하라"


def _load(rel, alias):
    spec = importlib.util.spec_from_file_location("ft2_stall_" + alias, os.path.join(FT2, rel))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


cli, dispatch, lifecycle, projection = (_load(os.path.join("core", n + ".py"), n) for n in ("cli", "dispatch", "lifecycle", "projection"))
models = _load(os.path.join("tools", "models.py"), "models")
pane_target = _load(os.path.join("adapters", "pi", "keeper_close.py"), "close").pane_target   # r1822 G1 1곳
E = _load(os.path.join("adapters", "pi", "keeper_stall_error.py"), "error")   # r1921 세션 끝 줄 판독·오류 종류
error_turn = E.error_turn
endings = _load(os.path.join("adapters", "pi", "keeper_endings.py"), "endings")   # r1960 미확인 깨움 → 재깨움 1회


def turn(path):
    """pi 세션 jsonl 끝 256KB → IDLE | LOGGEDOUT | ERROR | WORKING | UNKNOWN. 끝난 턴(stop·end_turn·max_tokens)만 IDLE(1.x pi 턴 판정과 같은 증거)."""
    rows = [r["message"] for r in E.records(path) or ()]
    last = next((m for m in reversed(rows) if m.get("role") == "assistant"), None)
    if last is None:
        return "UNKNOWN"
    if E.is_error(last):
        return "LOGGEDOUT" if any(a in E.why(last) for a in E.AUTH) else "ERROR"
    return "IDLE" if rows[-1] is last and last.get("stopReason") in ("stop", "end_turn", "max_tokens") else "WORKING"


class Stall:
    def __init__(self, keeper):
        self.k, env = keeper, keeper.env
        self.stall_s, self.after_s = int(env.get("FT2_KEEPER_STALL_S") or 900), int(env.get("FT2_KEEPER_WAKE_S") or 600)
        self.sessions = env.get("FT2_PI_SESSIONS") or os.path.expanduser("~/.pi/agent/sessions")
        self.ps, self.err_s = env.get("FT2_KEEPER_PS") or "ps", int(env.get("FT2_KEEPER_ERROR_WAKE_S") or 120)
    def check(self, team, work, attempt, rows):
        """S1 → S2 또는 S3. 대상 = 최신 dispatch(attempt) 전달됨 ∧ 그 attempt intent 의 FT2_HOLDER 세션 생존."""
        k = self.k
        intent = k.read_json(os.path.join(projection.runtime_path(k.root, team), "launch", "%s@%s.intent" % (work, attempt)))
        holder, tree = intent.get("FT2_HOLDER"), intent.get("worktree")
        if not holder:
            return                                    # S5 — intent 없는 좌석 = 깨움·재배정 0
        if not any(r.get("kind") == "deliver" and r.get("work") == work and r.get("attempt") == attempt for r in rows):
            return
        mine = [r for r in rows if r.get("work") == work]   # r1840 K1 — 최신 dispatch 뒤 마지막 단계 = result(착지 대기) = 멈춤 아님
        cut = max([i for i, r in enumerate(mine) if r.get("kind") == "dispatch"] or [0])   # result.attempt(holder#g) ≠ dispatch attempt
        if [r.get("kind") for r in mine[cut:] if r.get("kind") in STEPS][-1:] == ["result"]:
            return
        seen = k.probe(holder)
        if seen != "alive":
            return None if seen == "absent" else k.log("판정 불가", team, "%s %s %s — 행동 0" % (work, holder, seen))
        if self.first(team, work, attempt, holder, tree, intent, rows):
            return                                    # r1895 — 첫 본문 도달 0 = 깨움 없이 S3 1회(facts 전)
        facts, key = self.facts(work, attempt, rows, tree), "%s|%s@%s" % (team, work, attempt)
        if isinstance(facts, str):
            return k.log("판정 불가", team, "%s %s %s — 행동 0" % (work, holder, facts))
        hit = self.error(team, work, holder, key, facts["session"], rows)   # r1921 — 오류 턴 갈래(ready 앞 · S1 시계와 다른 키)
        if hit == "again" and "%s|stall-error|%s|%s" % (k.stamp()[:10], team, work) not in k.state["sent"]:
            k.log("HELD-STALL", team, "%s %s 오류 턴 반복 — 재배정 0" % (work, holder))
            k.notify(team, "%s|stall-error|%s|%s" % (k.stamp()[:10], team, work), "[크리티컬] ft2 keeper 오류 턴 반복 %s %s %s" % (team, work, holder))
        if hit:
            return
        woke = k.state.setdefault("woke", {}).get(key)
        idle = k.now() - max([facts["journal"], facts["head"]] + ([facts["mtime"]] if woke is None else [woke]))
        if idle < (self.stall_s if woke is None else self.after_s) or not self.ready(team, work, holder, facts["session"], rows):
            return
        if woke is None and key in k.state.setdefault("unsure", {}):   # 보정1 R1 — 미확인 깨움 = S3 진입 0 · r1960 after_s 뒤 재깨움 1회
            return endings.unsure(self, team, work, holder, key, idle)
        if woke is None:
            return self.wake(team, work, holder, key, idle)
        return self.reassign(team, work, attempt, holder, tree, intent, rows)
    def error(self, team, work, holder, key, session, rows):
        """r1921 — UNAVAILABLE 오류 ≥ err_s ∧ Working 0 → S2 깨움 1회(err_woke) · 그 뒤 또 오류 = "again" · 그 밖 오류·정상 = None(기존 경로)."""
        k = self.k
        try:
            kind, at = error_turn(session) or (None, None)
        except OSError:
            return None                               # ready() 가 판정 불가 1줄
        if kind != "UNAVAILABLE":
            return None
        if at is None:
            return k.log("판정 불가", team, "%s %s 오류 턴 timestamp 판독 불가 — 행동 0" % (work, holder)) or True
        woke = k.state.setdefault("err_woke", {}).get(key)   # 보정1 R2 — 미확인 = 정상·오류 공통 unsure 하나
        if woke is None and key in k.state.setdefault("unsure", {}):   # r1960 오류 턴 길도 같은 재깨움 1회(rewoke 키)
            return (self.guard(team, work, holder, rows) and endings.unsure(self, team, work, holder, key, int(k.now() - at), ERR_WAKE, "err_")) or True
        if woke is not None:
            return "again" if at > woke else True
        if k.now() - at < self.err_s:
            return True
        if self.guard(team, work, holder, rows):   # 보정1 R1 — pane Working·external_wait 공통 가드
            self.wake(team, work, holder, key, int(k.now() - at), ERR_WAKE, "err_")
        return True
    def first(self, team, work, attempt, holder, tree, intent, rows):
        """r1895 도달 확인 1회(body 키) — 새 intent(body_mark) at+60초 표식 user 줄 0 · 옛 intent 세션 0 ∧ stall_s ∧ Working 0 → S3 · 판독 불가 = 0."""
        k, key, body = self.k, "%s|%s@%s" % (team, work, attempt), self.k.state.setdefault("body", {})
        mark = intent.get("body_mark")
        session = self.session(tree) if tree and key not in body else None
        try:
            age = k.now() - time.mktime(time.strptime(intent["at"], STAMP))
            seen = [json.loads(x) for x in open(session, encoding="utf-8", errors="replace")] if session and mark and age >= 60 else []
        except (KeyError, TypeError, ValueError, OSError):
            return False
        if key in body or intent.get("state") != "opened" or age < (60 if mark else self.stall_s) or (session and not mark):
            return False
        rc, pane, _ = (0, "", "") if mark else k.call([k.tmux, "capture-pane", "-p", "-t", pane_target(holder)])
        if rc != 0 or BUSY.search(pane[-2000:]):
            return False
        if body.setdefault(key, k.stamp()) and any(isinstance(r, dict) and (r.get("message") or {}).get("role") == "user" and mark + " " in json.dumps(r["message"], ensure_ascii=False) for r in seen):
            return False
        k.log("HELD", team, "%s %s 본문 도달 0(%s) — 깨움 0 · 재배정 1회" % (work, holder, "표식 줄 0" if session else "세션 파일 0"))
        return self.reassign(team, work, attempt, holder, tree, intent, rows) or True
    def facts(self, work, attempt, rows, tree):
        """마지막 진척 재료 4개(wall 시각 · 논리 tick 과 섞지 않는다) — 못 읽음 = 사유 문자열."""
        mine = [r for r in rows if r.get("work") == work]
        steps = [r for r in mine if r.get("kind") in STEPS or (r.get("kind") == "progress" and r.get("tick_kind") == "progress")]
        base = [r for r in mine if r.get("kind") == "deliver" and r.get("attempt") == attempt][-1:]
        try:
            journal = max(time.mktime(time.strptime(r["at"], STAMP)) for r in steps + base)
        except (KeyError, TypeError, ValueError):
            return "journal at 판독 불가"
        if not tree:
            return "intent worktree 칸 없음"
        session = self.session(tree)
        if not session:
            return "pi 세션 파일 없음(%s)" % tree
        rc, out, err = self.k.git(tree, "log", "-1", "--format=%ct", "HEAD")
        if rc != 0 or not out.strip().isdigit():
            return "worktree HEAD 시각 rc %s %s" % (rc, err)
        try:
            return {"journal": journal, "head": int(out.strip()), "mtime": os.path.getmtime(session), "session": session}
        except OSError as exc:
            return "pi 세션 파일 mtime %s" % exc
    def session(self, tree):
        """pi 세션 파일 = <sessions>/--<pane cwd 의 / 를 - 로>--/*.jsonl 중 가장 최근(ft-seat-retire r960 과 같은 결속)."""
        names = {"--%s--" % p.strip("/").replace("/", "-") for p in (os.path.abspath(tree), os.path.realpath(tree))}
        files = [f for n in sorted(names) for f in glob.glob(os.path.join(glob.escape(self.sessions), glob.escape(n), "*.jsonl"))]
        return max(files, key=os.path.getmtime) if files else None
    def ready(self, team, work, holder, session, rows):
        """턴 IDLE(jsonl) ∧ pane Working 0 ∧ external_wait 시한 밖 ∧ LOGGEDOUT 아님 — 고스트 `❯` 글자는 근거가 아니다(하드 룰 10)."""
        k = self.k
        try:
            state = turn(session)
        except OSError as exc:
            return k.log("판정 불가", team, "%s %s 세션 파일 %s — 행동 0" % (work, holder, exc))
        if state == "LOGGEDOUT":
            return k.log("LOGGEDOUT", team, "%s %s — 깨움·재배정 0(재개 = 재시작)" % (work, holder))
        return state == "IDLE" and self.guard(team, work, holder, rows)
    def guard(self, team, work, holder, rows):
        """공통 가드(정상·오류 갈래) — pane Working 0 ∧ external_wait 시한 밖 · 판독 불가 = 판정 불가 1줄 · 행동 0."""
        k = self.k
        rc, pane, _ = k.call([k.tmux, "capture-pane", "-p", "-t", pane_target(holder)])
        if rc != 0:
            return k.log("판정 불가", team, "%s %s capture rc %s — 행동 0" % (work, holder, rc))
        if BUSY.search(pane[-2000:]):
            return False
        lanes = {r.get("lane") for r in rows if r.get("kind") == "progress" and r.get("work") == work and r.get("lane")}
        if not lanes:
            return True
        scan = lifecycle.Lifecycle(k.root, team).scan()
        if scan.lanes is None:
            return k.log("판정 불가", team, "%s lifecycle scan %s — 행동 0" % (work, scan.result))
        return not any((scan.lanes.get(lane) or {}).get("reason") == "EXTERNAL_WAIT_WITHIN_DEADLINE" for lane in lanes)
    def wake(self, team, work, holder, key, idle, fmt=None, slot=""):
        """S2 — Escape 1 → 문구 -l → Enter(따로) → 도달 확인 3회 · 보낸 뒤에는 같은 attempt 깨움 0.
        woke(재배정 시계의 기준) = 도달 확인 뒤에만 · 확인 3회 실패 = unsure(보정1 R1 · 재배정 0 · 판정 불가 보고만)."""
        k, t, text = self.k, ["-t", pane_target(holder)], fmt % (work, idle) if fmt else WAKE % (work, idle // 60)   # r1921 오류 턴 = slot err_
        rc, pane, _ = k.call([k.tmux, "capture-pane", "-p"] + t)   # r1895 — trust 창의 Escape = 거절 → 키 0
        if rc == 0 and TRUST in pane:
            return self.stop(team, work, key.rsplit("@", 1)[1], "trust", "%s %s trust 창 — 키 0" % (work, holder))
        for argv in (["send-keys"] + t + ["Escape"], ["send-keys"] + t + ["-l", text], ["send-keys"] + t + ["Enter"]):
            rc = k.call([k.tmux] + argv)[0]
            if rc != 0:
                return k.log("판정 불가", team, "%s %s 깨움 %s rc %s — 다음 단계 0" % (work, holder, argv[-1][:8], rc))
        for _ in range(3):
            rc, pane, _ = k.call([k.tmux, "capture-pane", "-p"] + t)
            if rc == 0 and ("[깨움] ft2 keeper" in pane or BUSY.search(pane[-2000:])):
                k.state.setdefault(slot + "woke", {})[key] = k.now()
                return k.log("WOKE", team, "%s %s%s" % (work, holder, " 오류 턴" if slot else ""))
        k.state.setdefault("unsure", {})[key] = k.now()   # 보정1 R2 — 성공 시계만 slot 분리
        return k.log("판정 불가", team, "%s %s 깨움 도달 확인 3회 실패" % (work, holder))
    def stop(self, team, work, attempt, step, text):
        self.k.log("HELD-STALL", team, text)
        self.k.notify(team, "stall|%s|%s@%s|%s" % (team, work, attempt, step), "[크리티컬] ft2 keeper " + text)
    def reassign(self, team, work, attempt, holder, tree, intent, rows):
        """S3 — 사전 판독(쓰기 0) → Working 재확인 → kill 1 → assign(rotation) → deliver → launch(복원 인자) · S4 반복 막기."""
        k, wk = self.k, "%s|%s" % (team, work)
        if wk in k.state.setdefault("reassigned", {}):
            k.notify(team, "%s|stall-repeat|%s" % (k.stamp()[:10], wk), "[크리티컬] 같은 일 두 번 멈춤 %s %s %s — 자동 재배정 0" % (team, work, holder))
            return
        p = self.plan(team, work, holder, tree, intent, rows)
        if p is None:
            return                                    # r1840 K3 — 역할만 못 정함 = plan 이 판정 불가 1줄 · 크리티컬 0
        if isinstance(p, str):
            return self.stop(team, work, attempt, "pre", "%s %s 재배정 0 — %s" % (work, holder, p))
        rc, pane, _ = k.call([k.tmux, "capture-pane", "-p", "-t", pane_target(holder)])
        if rc != 0 or BUSY.search(pane[-2000:]):
            return k.log("HELD", team, "%s %s 재배정 직전 Working·capture rc %s — 다음 바퀴" % (work, holder, rc))
        if k.held_attached(team, work, holder):
            return
        k.call([k.tmux, "kill-session", "-t", "=" + holder])
        if k.probe(holder) != "absent":
            return self.stop(team, work, attempt, "kill", "%s %s kill 뒤 부재 확인 없음 — 재배정 0" % (work, holder))
        g = ["--root", k.root, "--team", team]
        out, rc = cli.run(["assign", "--work", work, "--holder", p["next"], "--evidence", ",".join(dispatch.Dispatch.REQUIRED_EVIDENCE),
                           "--rotation", "true"] + (["--pre", ",".join(p["pre"])] if p["pre"] else []) + g)
        if rc != 0:
            return self.stop(team, work, attempt, "assign", "%s 옛 좌석 닫힘 · 새 배정 0 · 옛 worktree %s · assign %s %s" % (work, tree, out.get("result"), out.get("reason", "")[:80]))
        launch = [sys.executable, LAUNCH, "--root", k.root, "--team", team, "--work", work, "--repo", p["repo"], "--base", p["base"], "--role", p["role"]]
        k.state["reassigned"][wk] = {"at": k.stamp(), "from": holder, "to": p["next"], "launch": launch[1:]}
        out, rc = cli.run(["deliver", "--work", work] + g)
        if rc != 0:
            return self.stop(team, work, attempt, "deliver", "%s 새 배정 %s · deliver %s — launch 0" % (work, p["next"], out.get("result")))
        rc, text, err = k.call(launch, LAUNCH_S)
        if rc != 0:
            return self.stop(team, work, attempt, "launch", "%s 새 배정 %s 전달됨 · launch rc %s %s" % (work, p["next"], rc, (text or err).strip()[:120]))
        return k.log("REASSIGNED", team, "%s %s -> %s repo=%s base=%s role=%s" % (work, holder, p["next"], p["repo"], p["base"][:12], p["role"]))
    def plan(self, team, work, holder, tree, intent, rows):
        """S3-a 사전 판독(쓰기 0 · kill 전) — ⓐ pre·evidence·resources=()·rotation ⓑ 실제 core 읽기 함수 ⓒ repo·base·role 복원."""
        k, last = self.k, [r for r in rows if r.get("kind") == "dispatch" and r.get("work") == work][-1]
        pre, d = tuple(last.get("pre") or ()), dispatch.Dispatch(k.root, team)
        try:
            state, records = d.ex._state_records()
        except ValueError as exc:
            return "state 판독 불가 %s" % exc
        why = d._eligible(state, work, pre, d.REQUIRED_EVIDENCE, ())
        if why:
            return "배정 조건 %s" % why
        gen = (state.get("generations") or {}).get(work, 0)
        if d.ex._hold(state, records, work, gen + 1, rotation=True) is not None:
            return "결과 미확정 — 사람 확인"
        missing, repo, sha, m = [], "", "", NEXT.match(holder)
        if not m:
            missing.append("holder")
        if intent.get("state") != "opened" or not tree or not os.path.isdir(tree):
            missing.append("intent")
        else:
            rc, out, _ = k.git(tree, "rev-parse", "--path-format=absolute", "--git-common-dir")
            repo = os.path.dirname(out.strip().rstrip("/")) if rc == 0 and os.path.basename(out.strip().rstrip("/")) == ".git" else ""
            rc, sha, _ = k.git(tree, "rev-parse", "HEAD")
            sha = sha.strip() if rc == 0 else ""
            rc, dirty, _ = k.git(tree, "status", "--porcelain")
            missing += [n for n, bad in (("repo", not repo), ("base", not SHA.match(sha)), ("clean", rc != 0 or dirty.strip())) if bad]
        try:   # r1840 K3 — ⓐ intent role 칸(표에 있을 때만) ⓑ argv 판독 ⓒ 둘 다 못 정함 = 판정 불가
            role = intent.get("role") if intent.get("role") in models.role_defaults() else None
        except (OSError, ValueError):
            role = None
        role, why = (role, "") if role else self.argv_role(holder)
        if not role and not missing:
            got = "%s 표에 없음" % intent["role"] if "role" in intent else "칸 없음"
            return k.log("판정 불가", team, "%s %s 역할 못 정함(intent role %s · argv %s) — 재배정 0" % (work, holder, got, why))
        if not role:
            missing.append("role")
        if missing:
            return "못 정한 칸 " + ",".join(missing)
        return {"pre": pre, "next": m.group(1) + str(int(m.group(2)) + 1), "repo": repo, "base": sha, "role": role}
    def role(self, holder):
        """옛 holder pi 프로세스 argv 의 --model·--thinking 과 (모델·effort) 가 같은 role-defaults 행 «정확히 1개» — 아니면 None."""
        return self.argv_role(holder)[0]
    def argv_role(self, holder):
        """role() 과 같은 판독 — (역할, "") · 못 정함 = (None, 사유) (r1840 K3 판정 불가 문구용)."""
        k = self.k
        rc, pid, _ = k.call([k.tmux, "display-message", "-p", "-t", pane_target(holder), "#{pane_pid}"])
        if rc != 0 or not pid.strip().isdigit():
            return None, "pane_pid rc %s" % rc
        rc, args, _ = k.call([self.ps, "-o", "args=", "-p", pid.strip()])
        words = args.split() if rc == 0 else []
        got = {w: words[i + 1] for i, w in enumerate(words[:-1]) if w in ("--model", "--thinking")}
        if len(got) != 2:
            return None, "--model·--thinking 칸 %d개(ps rc %s)" % (len(got), rc)
        try:
            hits = [n for n, v in models.role_defaults().items() if v == (models.base_model(got["--model"]), got["--thinking"])]
        except (OSError, ValueError) as exc:
            return None, "role-defaults %s" % exc
        return (hits[0], "") if len(hits) == 1 else (None, "표 일치 %d행" % len(hits))
