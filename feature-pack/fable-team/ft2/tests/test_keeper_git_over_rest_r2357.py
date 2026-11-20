"""r2357 ft2 keeper — git 7초 넘은 work 는 5바퀴 쉰다(카드 반례 ①~⑩ · 변이 M1~M8 · 계약 K1~K4).

대역 = `test_keeper_round_60s.Rig` 그대로 — 임시 루트(tmp_path) · 주입 시계 · 가짜 subprocess.run · sleep 0 · 실 runtime·실 git·실 tmux 0.
바퀴 사이는 **새 Keeper**(state.json 만 이어진다 = 실제 `keeper --once` 꼴 · `Rig.boot`).
Rig 주입값(DA#46 M-b): 바퀴 한 장 = ROUND_S 60초(업무 구획 WORK_S 45초 · report 55 · 마무리 60) ·
git 넘김 주입 = 8초 1회 — 로컬 git 상한 GIT_S 7초에서 끊겨 시계는 7초만 흐른다(GIT_COST) ·
바퀴 사이 간격 = 125초(카드 «약 120초» + 7초 넘김 몫 — 그래서 쉼 600초가 바퀴2~5 를 덮고 바퀴6 에 풀린다) · REST_S = 600초 ·
② 의 바퀴 머리 = 18초(실사건 «ROUND items 1/97» 꼴 — fetch·나노 모으기가 예산을 먼저 먹는다 · `boot(head=…)`).

② 의 세계·기준판(실측 · DA#47 HOLD 1/2 반영): 팀 a work 5장 전부 git 8초 · 뒤 팀 b · 바퀴 머리 18초.
- 굶음 = 5장 × 7초 = 35초 + 머리 18초 = 53초 > 업무 예산 45초 → 바퀴마다 w4 의 landing 이 예산에서 끊긴다(R2 · 그 바퀴는 b2f·뒤 팀까지 못 간다).
- 고친 판 = 바퀴2 부터 매 바퀴 a b2f 1회 · b land 1회(쉼이 붙은 뒤로 5장이 예산을 안 먹는다) — 6바퀴 실측 = 0·1·1·1·1·1.
- 기준판 = 홀수 바퀴(3·5번째)에 a b2f 0 · b land 0 — 같은 work 5장이 매 바퀴 35초를 다시 써서 그 바퀴가 w4 에서 끊긴다. 6바퀴 실측 = 0·1·0·1·0·1.
- 카드 «기준판 = 6바퀴 동안 a b2f 0» 은 그래서 «6바퀴 중 3바퀴 0(홀수 바퀴)» 으로 적었다 — 이 대역에서 6바퀴 전부 0 인 세계는 고친 판도 0 이라(같은 pass 를 다시 도는 구조) ② 가 아무것도 못 가른다.
- DA#47 이 짚은 «4장이면 28초 ≥ 22.5 → b2f 앞 TEAM-CAP» 은 실측과 다르다. TEAM-CAP 문턱은 그 팀이 그 바퀴에 쓴 초만 센다(바퀴 머리 초는 team_at 앞이라 안 들어간다)
  → 3장 = 문턱 14초 · 4장 = 21초 < 22.5 = TEAM-CAP 0줄 · 5장 = 28초 ≥ 22.5 = TEAM-CAP 1줄(머리 0초일 때). 그 5장·머리 0초 세계도 재 봤지만 기준판이 b2f 에 닿는다(6바퀴 0·1·0·0·1·0) — 굶음을 가르는 값이 약하다.
  그래서 ② 는 «머리 18초 + 5장» 으로 두었고, 굶음은 TEAM-CAP 이 아니라 R2 예산 끊김으로 온다(같은 실사건 «바퀴 예산이 그 팀 b1 에서 끝난다»).
"""
import datetime
import json
import shutil

import pytest

from test_keeper_round_60s import FT2, KP, Rig, field, line

GIT8, GIT_COST, WHEEL, REST_S, HEAD = 8.0, 7.0, 125, 600, 18.0   # 주입 초 · 실제로 흐르는 초 · 바퀴 간격 · 쉼 창 · ② 바퀴 머리 초


def stamp(seconds):
    return datetime.datetime.fromtimestamp(seconds).strftime("%Y-%m-%dT%H:%M:%S")


def git(w, seconds=GIT8):
    """로컬 git 판독 1회 — 소요 seconds · 상한 7초라 넘으면 그 자리에서 끊긴다(Ungraded 또는 Cut)."""
    plan = w.plan
    w.plan = lambda argv, timeout: (seconds, 0, "")
    try:
        w.k.call(["git", "-C", str(w.root), "merge-base", "a", "b"])
    finally:
        w.plan = plan


def hands(w, slow=(), waits=None):
    """landing — slow 안의 (팀, work) 만 git 8초 · waits = 파이썬 안 시간(팀 몫 시계에 그대로 들어간다) · 그 밖은 바로 착지."""
    waits = waits or {}

    def landing(team, work):
        w.done.append(["land", team, work])
        w.t += waits.get((team, work), 0.0)
        if (team, work) in slow:
            git(w)
        return ("ab" * 20, "main", "")
    w.k.landing = landing


def boot(w, n, slow=(), attempts=None, waits=None, done=None, returns=None, head=0.0):
    """n번째 바퀴 1장 — 주입 시계 = (n-1) × WHEEL · 새 Keeper(state.json 다시 읽음) · 대역 손 다시 건다."""
    w.t = (n - 1) * WHEEL
    w.boot()
    hands(w, slow, waits)
    if head:   # 바퀴 머리(fetch·나노 모으기)가 업무 예산을 먼저 먹는다 — 실사건 «items 1/97» 꼴
        w.mod.Keeper.__init__.__globals__["kf"].collect = lambda k: w.wait(head)
    if attempts:   # 그 work 만 새 dispatch attempt(키가 달라진다)
        base = w.rows
        w.k.rows_of = lambda team: [dict(r, attempt=attempts.get((team, r["work"]), r["attempt"])) for r in base(team)]
    if returns:   # 그 work 가 반환으로 latest 에서 빠짐(dispatch 줄 0)
        base = w.rows
        w.k.rows_of = lambda team: [{"kind": "returned", "work": returns[1], "attempt": "a1", "holder": "h#0"}] if team == returns[0] else base(team)
    if done:   # 그 work 의 투영 done = true
        base = w.k.project
        w.k.project = lambda root, team: dict(base(root, team), works=dict(base(root, team)["works"], **({done[1]: {"done": True}} if team == done[0] else {})))
    start = len(w.done)
    w.round()
    return w.done[start:]


def lands(got, team=None):
    return [d for d in got if d[0] == "land" and (team is None or d[1] == team)]


def ratio(w):
    got, allm = field(w.k, "items").split("/")
    return int(allm) > 0 and got == allm


# ── 반례 ①~⑩ ─────────────────────────────────────────────────────────────────
def c1(w):   # ① 팀 a · w1 git 8초 → «git 7초 넘음» + «GIT-OVER» 1줄 · state 키 1(값 = git 끝난 시각 + 600)
    w.teams, w.works = ["a"], {"a": ["w1"]}
    boot(w, 1, {("a", "w1")})
    assert line(w.k, "판정 불가") == ["판정 불가 a w1 git 7초 넘음"], w.k.lines
    assert line(w.k, "GIT-OVER") == ["GIT-OVER a w1 %s 까지 쉼" % stamp(GIT_COST + REST_S)], w.k.lines
    assert w.state()["git_over"] == {"a|w1@a1": GIT_COST + REST_S}, w.state()


def c2(w):   # ② 실사건 꼴: 팀 a work 5장이 매 바퀴 git 7초 + 바퀴 머리 18초 · 뒤 팀 b → 바퀴2 부터 매 바퀴 a b2f 1회 · b land 1회(기준판 = 홀수 바퀴 굶음)
    works = ["w1", "w2", "w3", "w4", "w5"]
    w.teams, w.works = ["a", "b"], {"a": works, "b": ["w1"]}
    slow = {("a", work) for work in works}
    got = boot(w, 1, slow, head=HEAD)   # 바퀴1 = 5장이 45초 예산을 다 먹어 w4 에서 끊긴다 → b2f·뒤 팀 0(실사건 그대로)
    armed = len(line(w.k, "GIT-OVER"))
    assert [d[2] for d in lands(got, "a")] == ["w1", "w2", "w3", "w4"], got
    assert ["fill", "a"] not in got and ["land", "b", "w1"] not in got, got
    for n in (2, 3, 4, 5, 6):   # 바퀴2 부터 매 바퀴 빈 칸 채우기와 뒤 팀이 돈다(쉼 = 5장이 예산을 안 먹는다)
        got = boot(w, n, slow, head=HEAD)
        assert ["fill", "a"] in got, (n, got)   # 기준판은 여기서 선다 = 홀수 바퀴에 b2f·뒤 팀이 굶는다
        assert ["land", "b", "w1"] in got, (n, got)
    assert armed == 3, w.k.lines   # 바퀴1 이 쉬게 한 3장(w4 는 예산에서 끊겨 못 쉬었다)


def c3(w):   # ③ 바퀴 사이 state.json 만 이어도(새 Keeper = 실제 --once 꼴) ① 과 같은 결과
    w.teams, w.works = ["a"], {"a": ["w1"]}
    boot(w, 1, {("a", "w1")})
    saved = json.loads((w.root / ".fable-team" / "state" / "ft2-keeper" / "state.json").read_text(encoding="utf-8"))
    assert saved.get("git_over") == {"a|w1@a1": GIT_COST + REST_S}, saved
    got = boot(w, 2, {("a", "w1")})
    assert lands(got, "a") == [] and ["settle", "a", "w1"] in got, got   # stall 자리만 돈다


def c4(w):   # ④ 바퀴2~5(시각 < 풀림) landing 0 · stall 자리 1회 · 분모 그대로 · 바퀴6(≥ 풀림) landing 1회 · 바퀴 끝 키 0
    w.teams, w.works = ["a"], {"a": ["w1"]}
    boot(w, 1, {("a", "w1")})
    for n in (2, 3, 4, 5):
        got = boot(w, n, {("a", "w1")})
        assert lands(got, "a") == [] and ["settle", "a", "w1"] in got, (n, got)
        assert ratio(w), w.k.lines
    got = boot(w, 6, set())   # 625초 ≥ 607초 = 풀림 · 이 바퀴 판독은 빠르다
    assert ["land", "a", "w1"] in got, got
    assert "git_over" not in w.state(), w.state()


def c5(w):   # ⑤ 쉼 중 새 dispatch(a2) = 키가 달라 곧바로 판독 · 옛 키 a1 은 풀리는 시각 뒤 바퀴 끝에 지움
    w.teams, w.works = ["a"], {"a": ["w1"]}
    boot(w, 1, {("a", "w1")})
    boot(w, 2, {("a", "w1")})
    got = boot(w, 3, {("a", "w1")}, attempts={("a", "w1"): "a2"})
    assert ["land", "a", "w1"] in got, got
    assert sorted(w.state()["git_over"]) == ["a|w1@a1", "a|w1@a2"], w.state()
    for n in (4, 5):
        boot(w, n, {("a", "w1")}, attempts={("a", "w1"): "a2"})
    boot(w, 6, set(), attempts={("a", "w1"): "a2"})   # 625초 ≥ 옛 키 607초 = 바퀴 끝에 지운다
    assert sorted(w.state().get("git_over") or {}) == ["a|w1@a2"], w.state()


def c6(w):   # ⑥ 풀린 뒤 판독이 빠르면 GIT-OVER 줄 0 · 그 뒤로 매 바퀴 판독(지금과 같음)
    w.teams, w.works = ["a"], {"a": ["w1"]}
    boot(w, 1, {("a", "w1")})
    for n in (2, 3, 4, 5):
        assert lands(boot(w, n, set()), "a") == [], n
    for n in (6, 7):
        got = boot(w, n, set())
        assert ["land", "a", "w1"] in got and line(w.k, "GIT-OVER") == [], (n, got, w.k.lines)


def c7(w):   # ⑦ 쉼 중인 w1 옆 w2(빠름) · 뒤 팀 b → w2·b 는 지금과 같이 돈다(쉼은 그 work 만)
    w.teams, w.works = ["a", "b"], {"a": ["w1", "w2"], "b": ["w1"]}
    boot(w, 1, {("a", "w1")})
    got = boot(w, 2, {("a", "w1")})
    assert lands(got, "a") == [["land", "a", "w2"]], got
    assert ["complete", "a", "w2"] in got, got
    assert ["land", "b", "w1"] in got and ["close", "b", "w1"] in got, got


def c8(w):   # ⑧ 쉼 중 w1 이 투영 done=true → 그 바퀴 close 1회(풀리는 시각 기다림 0 · landing 0)
    w.teams, w.works = ["a"], {"a": ["w1"]}
    boot(w, 1, {("a", "w1")})
    got = boot(w, 2, {("a", "w1")}, done=("a", "w1"))
    assert ["close", "a", "w1"] in got, got
    assert lands(got, "a") == [], got


def c9(w):   # ⑨ 팀 a 가 TEAM-CAP 으로 w1 앞에서 3바퀴 멈춤(그 바퀴들에 w1 방문 0) → 쉼은 시각대로 끝남 · 첫 방문에 landing 1회
    w.teams, w.works = ["a", "b"], {"a": ["w1"], "b": ["w1"]}
    boot(w, 1, {("a", "w1")})
    w.works = {"a": ["w0", "w1"], "b": ["w1"]}   # 앞 work 가 팀 몫 절반(22.5초)을 넘겨 w1 앞에서 멈춘다
    for n in (2, 3, 4):
        got = boot(w, n, {("a", "w1")}, waits={("a", "w0"): 25.0})
        assert ["land", "a", "w1"] not in got, (n, got)   # w1 앞에서 멈춘 바퀴 = w1 방문 0
    w.works = {"a": ["w1"], "b": ["w1"]}
    got = boot(w, 6, {("a", "w1")})   # 625초 ≥ 607초 = 방문 수와 무관하게 끝나 있다
    assert ["land", "a", "w1"] in got, got


def c10(w):   # ⑩ 쉼 중 w1 이 반환으로 latest 에서 빠짐 → 풀리는 시각 뒤 바퀴 끝 키 0
    w.teams, w.works = ["a"], {"a": ["w1"]}
    boot(w, 1, {("a", "w1")})
    assert "a|w1@a1" in w.state()["git_over"], w.state()
    for n in (2, 3, 4):
        assert lands(boot(w, n, {("a", "w1")}, returns=("a", "w1")), "a") == [], n
    boot(w, 6, set(), returns=("a", "w1"))   # 625초 ≥ 607초 → 바퀴 끝에 지운다(방문 0 이어도)
    assert "git_over" not in w.state(), w.state()


CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑦": c7, "⑧": c8, "⑨": c9, "⑩": c10}
MUTANTS = {
    "M1": ([("                self.git_rest_set(team, work, attempt)   # r2357 K1", "                pass   # M1 기억 0")], "②"),
    "M2": ([("        over, key, now = self.state.setdefault(\"git_over\", {})", "        over, key, now = self.__dict__.setdefault(\"git_over\", {})"),
            ("        until = (self.state.get(\"git_over\") or {}).get(self.git_key(team, work, attempt))", "        until = (self.__dict__.get(\"git_over\") or {}).get(self.git_key(team, work, attempt))")], "③"),   # 기억을 self 에만
    "M3": ([("return until - self.now() if until and self.now() < until else None", "return until - self.now() if until else None")], "④"),   # 시각 비교 지움 = 영구 쉼
    "M4": ([("        return \"%s|%s@%s\" % (team, work, attempt)", "        return \"%s|%s\" % (team, work)")], "⑤"),   # 키에서 attempt 뺌
    "M5": ([("        over[key] = now + REST_S", "        over[key] = now + REST_S\n        self.state.setdefault(\"git_over_team\", {})[team] = over[key]"),
            ("        for work, (attempt, dispatched) in sorted(latest.items()):",
             "        if (self.state.get(\"git_over_team\") or {}).get(team, 0) > self.now():\n            return   # M5 팀 전체 쉼\n        for work, (attempt, dispatched) in sorted(latest.items()):")], "⑦"),   # 쉼을 팀 전체로
    "M6": ([("        if self.git_rest(team, work, attempt) is not None:   # r2357 K2 — 쉼 중 = landing·complete·ending 0 · stall 자리만(줄 0)\n            return self.stall_pos(team, work, attempt, dispatched, row, rows, \"판정 불가 · git 쉼\")\n", ""),
            ("        if row.get(\"done\"):   # 착지면 complete 만 = close 자리",
             "        if self.git_rest(team, work, attempt) is not None:   # M6 루프 머리\n            return self.stall_pos(team, work, attempt, dispatched, row, rows, \"판정 불가 · git 쉼\")\n        if row.get(\"done\"):   # 착지면 complete 만 = close 자리")], "⑧"),   # 쉼 확인을 done 갈래 앞으로
    "M7": ([("        over[key] = now + REST_S", "        over[key] = 5   # M7 횟수"),
            ("        until = (self.state.get(\"git_over\") or {}).get(self.git_key(team, work, attempt))\n        return until - self.now() if until and self.now() < until else None",
             "        over = self.state.get(\"git_over\") or {}\n        key = self.git_key(team, work, attempt)\n        if not over.get(key):\n            return None\n        over[key] -= 1\n        return 1.0")], "⑨"),   # 풀리는 시각 대신 방문마다 횟수 − 1
    "M8": ([("            self.git_rest_sweep()   # r2357 K3", "            pass   # M8 정리 0")], "⑩"),
}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path):
    assert CASES[name](Rig(tmp_path)) is None


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path):
    pairs, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KP).read_text(encoding="utf-8")
    for old, new in pairs:
        assert text.count(old) == 1, (name, old)
        text = text.replace(old, new)
    (tree / KP).write_text(text, encoding="utf-8")
    for sub in ("m1", "o1"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):   # 사본(변이) = 그 사례가 잡는다
        CASES[case](Rig(tmp_path / "m1", tree))
    assert CASES[case](Rig(tmp_path / "o1")) is None   # 원본으로 같은 사례 1회 = PASS(대조)
