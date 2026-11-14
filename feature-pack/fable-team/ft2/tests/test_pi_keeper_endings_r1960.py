"""r1960 keeper — 일이 끝난 나노 자리는 어떤 결과로 끝났든 닫는다 (고정 카드 8b756f2f4d 반례 ①~⑦e · 변이 M1~M9 · DA #301612).
대역 = r1812 World(임시 BYZ·팩 리포·가짜 tmux·쪽지·실제 core) + 가짜 gh(FT2_GH) + tmux 생애 값 · r1813·r1921 World(⑤ noecho) · 실 세션 0 · sleep 0.
"""
import importlib.util, json, shutil  # noqa: E401
from pathlib import Path
import pytest

FT2 = Path(__file__).resolve().parents[1]
_S = importlib.util.spec_from_file_location("r1960_kw", str(FT2 / "tests" / "keeper_world_r1812.py"))
kw = importlib.util.module_from_spec(_S)
_S.loader.exec_module(kw)
B, R = (kw._mod(FT2 / "tests" / n, "r1960_" + n[:-3]) for n in ("test_pi_keeper_stall_r1813.py", "test_pi_keeper_stall_error_r1921.py"))
TEAM, _git, _lines, _put = kw.TEAM, kw._git, kw._lines, kw._put
ID = ["-c", "user.email=t@t", "-c", "user.name=t", "-c", "commit.gpgsign=false"]
LIFE = '''if a[0] == "display-message" and "#{session_id}" in a[-1]:
    t = a[a.index("-t") + 1][1:-1]; sys.stdout.write(d.get("life", {}).get(t, "") + "\\n"); sys.exit(0 if t in d["alive"] else 1)
if a[0] == "kill-session"'''
GH = '#!/bin/sh\nprintf "%s\\n" "$*" >> "$FAKE_GH.log"\ncat "$FAKE_GH.out"\nexit "$(cat "$FAKE_GH.rc" 2>/dev/null || echo 0)"\n'
def world(case, tmp, mp, ft2=FT2):
    tmp.mkdir(parents=True, exist_ok=True)
    if case in (c5, c5e):
        return (R.B if case is c5e else B).World(tmp, mp, ft2)
    w = kw.World(tmp, mp, ft2)
    _put(tmp / "bin" / "tmux", kw.TMUX.replace("__PY__", __import__("sys").executable).replace('if a[0] == "kill-session"', LIFE, 1))
    _put(tmp / "bin" / "gh", GH), (tmp / "bin" / "gh").chmod(0o755), _put(str(tmp / "gh") + ".out", "[]")
    w.env.update(FT2_GH=str(tmp / "bin" / "gh"), FAKE_GH=str(tmp / "gh"))
    return w
def tmuxset(w, **kv):
    d = json.loads(w.tm.read_text(encoding="utf-8"))
    [d.setdefault(key, {}).update(val) if isinstance(val, dict) else d[key].extend(val) for key, val in kv.items()]
    _put(w.tm, d)
def pr(w, work, mode="merge", n=1, rc=0):
    """팩 worktree(가지 nano/<work> · base = 팩 main 끝) · merge = HEAD 를 main 에 · squash = main 이 다른 커밋 · ff = 다른 work 커밋 F 로 ff · PR n개."""
    base, pack, path = w.pack_sha(), w.tmp / "pack", w.tmp / "wt" / work
    _git(pack, "fetch", "-q", "origin"), _git(pack, "worktree", "add", "-q", "-b", "nano/" + work, str(path), base)
    (w.pack_sha(), _git(path, "fetch", "-q", "origin"), _git(path, "merge", "-q", "--ff-only", "origin/main")) if mode == "ff" else _git(path, *ID, "commit", "-q", "--allow-empty", "-m", "n-" + work)
    oid = (_git(path, "push", "-q", "origin", "HEAD:main"), _git(w.tmp / "seed-pack", "pull", "-q", "--ff-only", "origin", "main"), _git(path, "rev-parse", "HEAD"))[2] if mode == "merge" else w.pack_sha()
    _put(str(w.tmp / "gh") + ".out", json.dumps([{"number": 7, "mergeCommit": {"oid": oid}, "baseRefName": "main"}] * n)), _put(str(w.tmp / "gh") + ".rc", str(rc))
    _put(w.runtime() / "launch" / ("%s@a1.intent" % work), {"FT2_HOLDER": "byz-harness-nano-%s-t#0" % work, "state": "opened", "worktree": str(path), "at": "2026-01-01T00:00:00", "base_sha": base})
    return oid
def card(w, work, text, stage="진행", name=None):
    [w.commit("byz", {"design/harness/indices/%s/%s" % (stage, name or work + "-x.md"): "# 인덱스: %s\n- 상태: 대기\n\n## 상태\n%s\n" % (work, text)}, ref) for ref in ("main", "ops/main-base")]
def run(w, k=None):
    return w.round(k), w.tmux("kill-session")
def has(lines, head, word=""):
    return any(x.startswith(head) and word in x for x in lines)
def c1(w):   # ① 착지 줄 없음 · nano/<work> PR 1 merged · mergeCommit base 조상 → COMPLETED(PR) → CLOSED-SESSION · 줄 보완 1통 · gh repo 결속
    w.enable(), w.card("r9601"), w.work("r9601", intent=False, alive=True), pr(w, "r9601")
    lines, kills = run(w)
    assert has(lines, "COMPLETED harness r9601", "PR #7 병합") and has(lines, "CLOSED-SESSION harness r9601") and len(kills) == 1 and sum("[줄 보완]" in x for x in _lines(str(w.mbox) + ".log")) == 1, lines
    assert "-R %s --head nano/r9601 --state merged" % (w.tmp / "pack.git") in _lines(str(w.tmp / "gh") + ".log")[0]
def c1b(w):  # ①b (DA ⓐ) 다른 work 커밋 F 로 ff · PR 0 → HELD «착지 줄 없음» 그대로
    w.card("r9611"), w.work("r9611", intent=False, alive=True), pr(w, "r9611", "ff", n=0)
    lines, kills = run(w)
    assert has(lines, "HELD harness r9611", "착지 줄 없음") and w.kinds("complete") == 0 and kills == [], lines
def c1c(w):  # ①c PR 2개 → None · ①d gh 실패 → None
    for work, kw_ in (("r9621", {"n": 2}), ("r9631", {"rc": 1})):
        w.card(work), w.work(work, intent=False, alive=True), pr(w, work, **kw_)
        assert has(run(w)[0], "HELD harness " + work, "착지 줄 없음") and w.kinds("complete") == 0
def c1e(w):  # ①e squash 병합 PR(mergeCommit 조상 · HEAD 아님) → landed(sha = mergeCommit)
    w.card("r9641"), w.work("r9641", intent=False), (oid := pr(w, "r9641", "squash"))
    assert has(run(w)[0], "COMPLETED harness r9641", oid) and w.kinds("complete") == 1
def c2(w):   # ② (DA ⓑ) journal 에 그 work refuse(done=false) → ending None · CLOSED 0 · complete 0
    w.enable(), w.card("r9602"), w.work("r9602", alive=True)
    w.CLI.run(["refuse", "--work", "r9602", "--place", "keeper", "--gen", "1", "--cause", "c", "--artifact", "a", "--event", "e", "--root", str(w.root), "--team", TEAM])
    lines, kills = run(w)
    assert not has(lines, "CLOSED") and kills == [] and w.kinds("complete") == 0, lines
def c3(w):   # ③ 카드가 아카이브 폴더 단일 → CLOSED-ENDING superseded · complete 호출 0 · 다음 배정 0
    w.enable(), w.card("r9603", stage="아카이브/2026-11"), w.work("r9603", alive=True)
    lines, kills = run(w)
    assert has(lines, "CLOSED-ENDING harness r9603", "superseded") and len(kills) == 1 and w.kinds("complete") == 0, lines
def c3b(w):  # ③b «## 상태» 마지막 항목(맨 줄) «중단: …» → suspended
    w.enable(), card(w, "r9613", "- 2026-11-14 — 진행\n중단: 오빠 보류 · 재개 = 새 세션"), w.work("r9613", alive=True)
    assert has(run(w)[0], "CLOSED-ENDING harness r9613", "suspended") and w.kinds("complete") == 0
def c3c(w):  # ③c 문중 «대체:» · 다른 절 «거절:» → None · ③d 카드 후보 2개(진행 + 아카이브) → None
    card(w, "r9623", "- 2026-11-14 — 진행 · 대체: 다른 카드\n\n## 메모\n거절: 시험 입력 글자"), w.work("r9623", alive=True)
    card(w, "r9633", "- 진행"), card(w, "r9633", "- 끝", stage="아카이브/2026-11"), w.work("r9633", alive=True)
    lines, kills = run(w)
    assert not has(lines, "CLOSED") and kills == [] and has(lines, "HELD harness r9623", "착지 줄 없음"), lines
def again(w, work, done=True):   # 같은 holder 로 a2 재배정(r1951 꼴 · keeper_next fill 과 같은 동사) · a2 intent 없음
    for argv in (["submit", "--command", "keeper-next-" + work, "--body", "카드"], ["assign", "--holder", "byz-harness-nano-%s-t#0" % work, "--evidence", "v1,v2"], ["deliver", "--mode", "intent"]) + ((["complete", "--attempt", "a2"],) if done else ()):
        assert w.CLI.run(argv + ["--work", work, "--root", str(w.root), "--team", TEAM])[0]["result"] == "접수 성공"
def c4(w):   # ④ r1951 — dispatch a1·a2 같은 holder · intent @a1 만 opened · done → @a1 로 닫음 · ④c 다른 holder 의 opened intent → 안 씀
    w.enable()
    for work, seat in (("r9604", None), ("r9624", "byz-harness-nano-other-t#0")):
        w.card(work, w.pack_sha()), w.work(work, alive=True, seat=seat), again(w, work)
    lines, kills = run(w)
    assert has(lines, "CLOSED-SESSION harness r9604") and kills == [["kill-session", "-t", "=byz-harness-nano-r9604-t#0"]], lines
    assert has(lines, "HELD harness r9624", "intent 없음(attempt a2)")
def c4d(w):  # ④d (DA R1 #301944) a2 재배정 · a2 intent 없음 · 대체 a1 intent base_sha = 카드 옛 착지 sha → 옛 착지 HELD · complete·kill 0
    w.enable(), w.card("r9634", sha := w.pack_sha()), w.work("r9634", alive=True)
    _put(f := w.runtime() / "launch" / "r9634@a1.intent", dict(json.loads(f.read_text(encoding="utf-8")), base_sha=sha)), w.round(), again(w, "r9634", done=False)
    lines, kills = run(w)
    assert has(lines, "HELD harness r9634", "옛 착지 줄") and kills == [] and w.kinds("complete") == 0, lines
def c4b(w):  # ④b intent 0 → HELD «intent 없음» 1줄(침묵 0) · 두 번째 바퀴 0
    w.card("r9614", w.pack_sha()), w.work("r9614", done=True, intent=False, alive=True)
    assert sum("intent 없음(attempt a1)" in x for x in run(w)[0]) == 1
    assert not [x for x in w.round() if "intent 없음" in x] and w.tmux("kill-session") == []
def c5(w):   # ⑤ unsure · after_s 지남 → 재깨움 1회 · 또 미확인 → [크리티컬] 1통 · 같은 날 0 · kill·재배정 0
    w.seat(), _put(w.tm, dict(json.loads(w.tm.read_text(encoding="utf-8")), noecho=True)), w.round(), w.round(11 * B.M)
    assert len(w.tmux("send-keys")) == 6 and w.notes() == []
    w.round(12 * B.M), w.round(13 * B.M)
    assert len(w.notes()) == 1 and "[크리티컬]" in w.notes()[0] and "깨움 도달 미확인" in w.notes()[0] and len(w.tmux("send-keys")) == 6 and w.tmux("kill-session") == [] and w.kinds("dispatch") == 1
def c5e(w):  # ⑤ 오류 턴 길에서도 같은 1회 · 또 미확인 → [크리티컬] 1통
    R._seat(w, "503 Service Unavailable", 121), _put(w.tm, dict(json.loads(w.tm.read_text(encoding="utf-8")), noecho=True)), w.round()
    w.round(11 * R.M), w.round(12 * R.M), w.round(13 * R.M)
    assert len(w.tmux("send-keys")) == 6 and len(w.notes()) == 1 and "[크리티컬]" in w.notes()[0] and w.tmux("kill-session") == []
def c6(w):   # ⑥ 회귀 가드 — 끝 결과 있음 + Working → HELD · attached 1 → HELD · 역할 master → 0
    w.enable()
    for work, kw_ in (("r9606", {"pane": "⠋ Working...\n"}), ("r9616", {}), ("r9626", {"holder": "byz-harness-master-pi#999"})):
        w.card(work, stage="아카이브/2026-11"), w.work(work, alive=True, **kw_)
    tmuxset(w, att={"byz-harness-nano-r9616-t#0": 1})
    lines, kills = run(w)
    assert all(has(lines, "HELD harness " + work, word) for work, word in (("r9606", "Working"), ("r9616", "사람 화면"), ("r9626", "보호 역할"))), lines
    assert kills == [] and not has(lines, "CLOSED")
def orphan(w, work, seat, life="$5\t100"):
    """고아 1석 — work(dispatch holder #0 · 세션 0) · 카드 아카이브 · seat 의 launch intent(영수 $5/100) · seat 생존(생애 = life)."""
    w.card(work, stage="아카이브/2026-11"), w.work(work)
    tree = str(w.tmp / "wt" / work)
    _put(w.runtime() / "launch" / ("%s@a9.intent" % work), {"FT2_HOLDER": seat, "state": "opened", "worktree": tree, "at": "2026-01-01T00:00:00", "tmux_sid": "$5", "tmux_created": "100"})
    tmuxset(w, alive=[seat], pane={seat: "❯ "}, life={seat: "%s\t%s" % (life, tree)})
def c7(w):   # ⑦ 영수 생애 일치 · 카드 아카이브 · 유휴·턴 끝 → CLOSED-ORPHAN
    orphan(w, "r9607", "byz-harness-nano-r9607#1")
    lines, kills = run(w)
    assert has(lines, "CLOSED-ORPHAN harness r9607 byz-harness-nano-r9607#1") and kills == [["kill-session", "-t", "=byz-harness-nano-r9607#1"]], lines
def c7b(w):  # ⑦b 같은 이름 새 생애(영수 다름) → HELD-ORPHAN + 알림 1 · kill 0 · ⑦c 이름 꼴 밖 → 0
    orphan(w, "r9617", "byz-harness-nano-r9617#1", life="$9\t200"), tmuxset(w, alive=["byz-harness-master-x#1", "foo"])
    lines, kills = run(w)
    assert has(lines, "HELD-ORPHAN harness byz-harness-nano-r9617#1", "생애 다름") and kills == [] and sum("[고아]" in x for x in _lines(str(w.mbox) + ".log")) == 1 and not [x for x in lines if "master-x" in x or " foo" in x]
def c7d(w):  # ⑦d 세션 목록 읽기 직전 dispatch+launch → 고아 아님(스냅샷 뒤 journal 새로 읽기)
    w.card("r9627", stage="아카이브/2026-11"), w.work("r9657")   # r9657 = 팀 켜기(ft20-switch)
    k, real, S = w.keeper(), None, "byz-harness-nano-r9627#0"
    def snap():   # 목록 읽기 직전 = submit→assign→deliver + launch(intent 영수 · 세션 생존)
        tree = (w.work("r9627", holder=S), str(w.tmp / "wt" / "r9627"))[1]
        _put(w.runtime() / "launch" / "r9627@a1.intent", {"FT2_HOLDER": S, "state": "opened", "worktree": tree, "at": "2026-01-01T00:00:00", "tmux_sid": "$5", "tmux_created": "100"})
        tmuxset(w, alive=[S], life={S: "$5\t100\t" + tree})
        k.alive_sessions = real
        return real()
    real, k.alive_sessions = k.alive_sessions, snap
    lines, kills = run(w, k)
    assert kills == [] and not has(lines, "CLOSED-ORPHAN"), lines
    assert [a for a in w.tmux("display-message") if "#{session_id}" in a[-1]] == []   # 호출 증거: 고아 후보 판정(생애 조회) 0 · ⑦e 재확인이 가리는 것 아님
def c7e(w):  # ⑦e 가드 읽는 사이 holder 바뀜(그 seat 에 새 dispatch) → 닫기 0
    orphan(w, "r9637", "byz-harness-nano-r9637#1")
    k, real = w.keeper(), None
    real, k.idle = k.idle, lambda team, work, holder: (holder.endswith("r9637#1") and w.work("r9647", holder=holder), real(team, work, holder))[1]
    lines, kills = run(w, k)
    assert kills == [] and not has(lines, "CLOSED-ORPHAN"), lines
CASES = {"①": c1, "①b": c1b, "①c·①d": c1c, "①e": c1e, "②": c2, "③": c3, "③b": c3b, "③c·③d": c3c, "④·④c": c4, "④b": c4b, "④d": c4d, "⑤": c5, "⑤e": c5e,
         "⑥": c6, "⑦": c7, "⑦b·⑦c": c7b, "⑦d": c7d, "⑦e": c7e}
KE, KC, KP = "adapters/pi/keeper_endings.py", "adapters/pi/keeper_close.py", "adapters/pi/keeper.py"
SNAP = 'H, alive = _mod("holders", os.path.join(HERE, "ft2_holders.py")), k.alive_sessions()\n    held_by = {t: {h for _, h in got.values()} for t in teams if (got := latest(k, t)) is not None}'
MUTANTS = {"M1": (KE, 'prs = _prs(k, REPO.search(url).group(1) if REPO.search(url) else url, "nano/" + work)', 'prs = [{"number": 0, "mergeCommit": {"oid": k.git(tree, "rev-parse", "HEAD")[1].strip()}, "baseRefName": "main"}]', c1b),
           "M2": (KE, '    land = _mod("land", os.path.join(HERE, "keeper_land.py"))\n    for ref in land.REFS:', '    if any(r.get("kind") == "refuse" and r.get("work") == work for r in _proj().journal.Journal(_proj().runtime_path(k.root, team), rec=_proj().record).records()):\n        return "refused", "journal refuse"\n    land = _mod("land", os.path.join(HERE, "keeper_land.py"))\n    for ref in land.REFS:', c2),
           "M3": (KE, 'r.get("FT2_HOLDER") == holder', 'r.get("FT2_HOLDER") is False', c4),
           "M4": (KC, 'return endings.held(self, team, "intent|', 'return None and endings.held(self, team, "intent|', c4b),
           "M5": (KE, "st.wake(team, work, holder, key, idle, fmt, slot)", "None", c5),
           "M6": (KC, "if not self.idle(team, work, holder):", "if not (ending or self.idle(team, work, holder)):", c6),
           "M7": (KE, SNAP, "\n    ".join(SNAP.split("\n    ")[::-1]), c7d),
           "M8": (KE, "H.auto_opened(k.call, k.tmux, seat, it) if work", '(True, "") if work', c7b),
           "M9": (KP, "elif self.sock and endings.ending(self, team, work):", "elif self.sock and endings.ending(self, team, work) and (self.complete(team, work, attempt, ('0' * 40, 'm9', '')) or True):", c3)}
@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](world(CASES[name], tmp_path / "w", monkeypatch))
@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    rel, old, new, case = MUTANTS[name]
    shutil.copytree(FT2, copy := tmp_path / "m" / "ft2", ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (copy / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (copy / rel).write_text(text.replace(old, new), encoding="utf-8")
    with pytest.raises(AssertionError):
        case(world(case, tmp_path / "w1", monkeypatch, copy))
    case(world(case, tmp_path / "w2", monkeypatch))   # 원본으로 같은 사례 1회 더 = PASS
