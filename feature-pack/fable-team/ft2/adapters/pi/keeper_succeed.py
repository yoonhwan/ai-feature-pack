"""ft 2.0 keeper 승계 갈래 — 대화창 한도(증류 미완 표식)에 닿은 나노의 일을 후계 나노로 잇는다 (r2276 · 사전 DA#28 APPROVE-DESIGN).

들어오는 자리 = 바퀴마다 팀 투영 owners 순회(stall.check 의 dispatch attempt 길과 따로 · claim 으로 받은 work 도 닿음) · S1 보다 먼저.
표식 있는 owner work = 그 바퀴 깨움·S3 0(keeper.succeeding). 구 worktree = FT2_HOLDER == holder 인 intent 중 가장 늦은 1개 → 없으면 pane 경로.
C1 표식(<루트>/.fable-team/state/pi-distill-pending/<좌석 베이스> · 본문 seat=<holder>) 나이 ≥ FT2_SUCCEED_WAIT(300초) ∧ pane Working 0.
C2 구 worktree clean ∧ HEAD 로컬 보존(r2280 · push·fetch 0) = 가지 끝 · 없으면 refs/ft2/keep/<work>/<attempt>-<HEAD sha12> 만들기만(덮기 0 · 앞선 HEAD = 새 이름 1개) · git 실패 = 판정 불가 · dirty = 승계 0 + [크리티컬] · kill 0.
C3~C5 = keeper_stall.handoff(S3 와 같은 단계 · 사본 0) · plan 의 core _hold 판독(rotation) = 효과 미확정이면 kill 0 + [크리티컬].
C6 인계 3줄 = 새 holder 우편함(첫 본문의 recv 길) · C7 키 = 팀|work|g세대(S4 reassigned 와 따로) · 같은 work 하루 3회 상한.
C8 core·launch.py·distill-gate 글자 0 · 표식 쓰기 0 · git·tmux·표식·장부 못 읽음 = 판정 불가 1줄 · 쓰기 0.
"""
import glob, importlib.util, os, re  # noqa: E401

HERE = os.path.dirname(os.path.abspath(__file__))
FT2 = os.path.dirname(os.path.dirname(HERE))
SLOT, CAP = "succeeded", 3
BLOCK = "[크리티컬] ft2 keeper 승계 막힘 · %s — %s %s"
HAND = "[인계] ft2 keeper 승계 — 일 %s · 구 좌석 %s\n구 HEAD %s · 보존 %s\n카드 %s · 상태 끝 줄: %s"


def _load(path, alias):
    spec = importlib.util.spec_from_file_location("ft2_succeed_" + alias, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


pane_target = _load(os.path.join(HERE, "keeper_close.py"), "close").pane_target
planner = _load(os.path.join(HERE, "launch_plan.py"), "plan")
projection = _load(os.path.join(FT2, "core", "projection.py"), "projection")


def keep_name(work, attempt, sha):
    """C1ⓑ keep ref 이름 = <attempt>-<HEAD sha12>(r2280 · DA#29 조건 1 — 앞선 HEAD 는 새 이름 · 충돌 갈래 0)."""
    return "refs/ft2/keep/%s/%s-%s" % (work, attempt, sha[:12])


class Succeed:
    def __init__(self, keeper):
        self.k = keeper
        self.wait_s = int(keeper.env.get("FT2_SUCCEED_WAIT") or 300)
        keeper.succeeding = set()

    def sweep(self, team, proj, rows):
        """C1 들어오는 자리 — owners 순회 · 표식 있는 work = 이 바퀴 S1~S3 0 · 표식 나이가 차면 승계 1회."""
        k = self.k
        k.succeeding = {x for x in k.succeeding if x[0] != team}
        for work, row in sorted((proj.get("works") or {}).items()):
            holder = ((row or {}).get("owner") or {}).get("holder")
            if not holder or row.get("done"):
                continue
            age = self.marker(holder)
            if age is None:
                continue
            k.succeeding.add((team, work))
            if isinstance(age, str):
                k.log("판정 불가", team, "%s %s 표식 %s — 승계 0" % (work, holder, age))
            elif age >= self.wait_s:
                k.timed("stall", self.one, team, work, holder, int(row.get("gen") or 0), rows)   # 표식 없는 바퀴 = ROUND 줄 그대로

    def marker(self, holder):
        """증류 미완 표식 나이(초) · 없음·남의 좌석(본문 seat= 다름) = None · 못 읽음 = 사유 문자열."""
        path = os.path.join(self.k.root, ".fable-team", "state", "pi-distill-pending", re.sub(r"#\d+$", "", holder))
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                words = fh.read().split()
            at = os.stat(path).st_mtime
        except FileNotFoundError:
            return None
        except OSError as exc:
            return "읽기 %s" % type(exc).__name__
        return self.k.now() - at if "seat=" + holder in words else None

    def one(self, team, work, holder, gen, rows):
        """C7 → 구 worktree → C1 Working → C2 dirty → plan(C3 효과 미확정) → C2 push → handoff(C3~C6)."""
        k = self.k
        key, day = "%s|%s|g%d" % (team, work, gen), k.stamp()[:10]
        book = k.state.setdefault(SLOT, {})
        if key in book:
            return
        if sum(1 for x, v in book.items() if x.startswith("%s|%s|" % (team, work)) and str((v or {}).get("at", ""))[:10] == day) >= CAP:
            return self.block(team, work, "cap", "같은 일 하루 승계 %d회 — 자동 승계 0" % CAP)
        tree, intent = self.tree(team, holder)
        if not tree:
            return k.log("판정 불가", team, "%s %s 구 worktree 못 정함(%s) — 승계 0" % (work, holder, intent))
        ok = k.stall.guard(team, work, holder, rows)
        if not ok:
            return None if ok is None else k.log("WORKING", team, "%s %s 표식 있음 · Working — 다음 바퀴" % (work, holder))
        rc, dirty, _ = k.git(tree, "status", "--porcelain")
        if rc != 0:
            return k.log("판정 불가", team, "%s git status rc %s — 승계 0" % (work, rc))
        if dirty.strip():
            return self.block(team, work, "dirty", "dirty · 구 worktree %s" % tree)
        p = k.stall.plan(team, work, holder, tree, intent, rows)
        if p is None or (isinstance(p, str) and p.startswith("state 판독 불가")):
            return k.log("판정 불가", team, "%s %s — 승계 0" % (work, p)) if p else None
        if isinstance(p, str):
            return self.block(team, work, "pre", "효과 미확정 (%s)" % p if "결과 미확정" in p else p)
        last = [r.get("attempt") for r in rows if r.get("kind") == "dispatch" and r.get("work") == work]
        attempt = last[-1] if last else "g%d" % gen
        why, name = self.keep(work, tree, attempt)
        if why:
            return k.log("판정 불가", team, "%s %s — 승계 0" % (work, why))
        return k.stall.handoff(team, work, attempt, holder, tree, intent, rows, (SLOT, key), "SUCCEEDED",
                               p, lambda q: self.relay(team, work, holder, q, name))

    def tree(self, team, holder):
        """구 worktree — ⓐ FT2_HOLDER == holder 인 intent 중 가장 늦은 1개(at · DA 메모 ⓐ) ⓑ pane 경로 · 없음 = (None, 사유)."""
        k, got = self.k, []
        for path in glob.glob(os.path.join(projection.runtime_path(k.root, team), "launch", "*.intent")):
            it = k.read_json(path)
            if isinstance(it, dict) and it.get("FT2_HOLDER") == holder and it.get("worktree"):
                got.append((str(it.get("at", "")), path, it))
        if got:
            it = max(got, key=lambda x: x[:2])[2]
            return it["worktree"], it
        rc, out, _ = k.call([k.tmux, "display-message", "-p", "-t", pane_target(holder), "#{pane_current_path}"])
        cwd = out.strip() if rc == 0 else ""
        if cwd and os.path.isdir(cwd):
            return cwd, {"state": "opened", "worktree": cwd}
        return None, "intent 0 · pane 경로 rc %s" % rc

    def keep(self, work, tree, attempt):
        """C2(r2280) — 로컬 보존 · push·fetch·가지 옮기기 0 → ("", 보존 이름) | («판정 불가 …», "").
        ⓐ HEAD = 로컬 가지 끝(symbolic-ref · 분리면 for-each-ref --points-at) ⓑ 없으면 keep_name 만들기만(빈 옛 값 = 덮기 0)."""
        k = self.k  # C1
        rc, out, err = k.git(tree, "symbolic-ref", "-q", "HEAD")
        if rc == 0 and out.strip().startswith("refs/heads/"):
            return "", out.strip()[len("refs/heads/"):]
        if rc not in (0, 1):
            return "판정 불가 · symbolic-ref rc %s %s" % (rc, (err or "").strip()[:80]), ""
        rc, out, err = k.git(tree, "for-each-ref", "--points-at", "HEAD", "--format=%(refname:short)", "refs/heads/")
        if rc != 0:
            return "판정 불가 · for-each-ref rc %s %s" % (rc, (err or "").strip()[:80]), ""
        if out.split():
            return "", out.split()[0]
        rc, out, err = k.git(tree, "rev-parse", "--verify", "-q", "HEAD")
        head = out.strip()
        if rc != 0 or not head:
            return "판정 불가 · rev-parse HEAD rc %s %s" % (rc, (err or "").strip()[:80]), ""
        name = keep_name(work, attempt, head)
        rc = k.git(tree, "update-ref", name, head, "")[0]
        if rc == 0:
            return "", name
        rc, out, err = k.git(tree, "rev-parse", "--verify", "-q", name)
        if rc == 0 and out.strip() == head:
            return "", name   # 같은 이름 = 같은 sha = 보존 됨 · 다시 쓰기 0
        return "판정 불가 · keep ref 못 만듦 %s rc %s %s" % (name, rc, (err or "").strip()[:80]), ""

    def relay(self, team, work, holder, p, name):
        """C6 인계 3줄 → 새 holder 우편함(deliver 뒤 · launch 앞 · 첫 본문 recv 가 읽음) · 못 보냄 = 로그 1줄 · 열기는 계속."""
        k = self.k
        card, last = self.card(team, work)
        rc = k.send(p["next"], HAND % (work, holder, p["base"], name, card, last))[0]
        if rc != 0:
            k.log("판정 불가", team, "%s 인계 쪽지 %s rc %s — 열기는 계속" % (work, p["next"], rc))

    def card(self, team, work):
        """카드 자리(짝 표 → 루트 표 대기/ → 진행/) + «## 상태» 마지막 «- » 줄 · git show 실패 = «상태 줄 못 읽음»."""
        row, hit = planner.card_row(self.k.root, team), planner.mapped_card(self.k.root, team, work)
        if not (hit or row):
            return "카드 루트 표 행 없음", "-"
        repo, ref, path = hit or (row[0], row[1], "%s/대기/%s.md" % (row[2], work))
        for cand in (path, path.replace("/대기/", "/진행/")):
            rc, text, _ = self.k.git(repo, "show", "%s:%s" % (ref, cand))
            if rc == 0:
                body = (text.split("## 상태", 1)[1:] or [""])[0].split("\n## ")[0]
                lines = [x for x in body.splitlines() if x.startswith("- ")]
                return "%s %s:%s" % (repo, ref, cand), lines[-1] if lines else "상태 줄 없음"
        return "%s %s:%s" % (repo, ref, path), "상태 줄 못 읽음"

    def block(self, team, work, step, text):
        """승계 막힘 — 로그 1줄 + 팀 [크리티컬] 1통(그날 지문) · kill·배정 0."""
        k = self.k
        k.log("HELD-SUCCEED", team, "%s %s" % (work, text))
        k.notify(team, "succeed|%s|%s|%s|%s" % (team, work, step, k.stamp()[:10]), BLOCK % (text, team, work))
