"""r2159 ft2 keeper 다음 카드 — 진행/ 카드 마지막 «- 재개: <시각> · PR #<N> · head <sha> · 가지 <headRefName>» 줄 + PR OPEN · head·가지 같음 ·
시각이 최신 intent 뒤 = 그 headRefOid 40자를 base 로 launch 1회 · 옛 seat(세션 없음) = 새 나노 이름 seat (반례 ①~⑧ · ⑩ ⑪ · 변이 M1~M4).
대역 = r2113 세계(r2111 · r1871 world · 임시 root·git·가짜 tmux·launch·record) + 가짜 gh(FT2_GH · PR 목록 json · 호출 기록) + 팩 goal-close 폴더 사본.
실 PR·실 tmux·실 원장·설치 0 · sleep 0. 기준판 = ① ② ⑩ Red(진행/ 카드 재개 0 · 재개 구 0).
"""
import hashlib, importlib.util, json, re, shutil, subprocess, sys  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_next_r2159_r2111", str(HERE / "test_keeper_next_delivered_reopen_r2111.py"))
r11 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(r11)
base, kw, hand, alive = r11.base, r11.kw, r11.hand, r11.alive
S, KN, BR, SHA = "r9901-pr", "adapters/pi/keeper_next.py", "nano/r9901-pr", "abc1234" + "0" * 33
LINE = "- 재개: 2026-11-17T10:30:00 · PR #7051 · head abc1234 · 가지 " + BR
GC = kw.FT2.parent / "goal-close"
GH = '''import json, os, sys
me = os.path.abspath(__file__)
open(me + ".log", "a").write(json.dumps(sys.argv[1:]) + "\\n")
d = json.load(open(me + ".json"))
print(json.dumps(d["prs"]))
sys.exit(d["rc"])
'''


def load(path, alias):
    spec = importlib.util.spec_from_file_location(alias, str(path))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def prog(w, *heads):
    w.commit("byz", {"design/harness/indices/진행/%s.md" % S: "# 인덱스: %s\n%s- 상태: 진행\n" % (S, "".join(h + "\n" for h in heads))}, "main")


def gh(w, rc=0, **pr):
    path = w.tmp / "bin" / "gh"
    kw._put(path, "#!%s\n%s" % (sys.executable, GH)), path.chmod(0o755)
    kw._put(Path(str(path) + ".json"), {"rc": rc, "prs": [dict({"number": 7051, "state": "OPEN", "headRefOid": SHA, "headRefName": BR}, **pr)]})
    w.env["FT2_GH"] = str(path)


def calls(w):
    return kw._lines(str(w.tmp / "bin" / "gh") + ".log")


def skip(lines, why):
    return [x for x in lines if x.startswith(("NEXT-SKIP harness %s" % S, "판정 불가 harness %s" % S)) and why in x]


def argv(w):
    return [json.loads(x) for x in base.log(w, "launch.py")]


def blocked(w, why):   # 열기 0 · 사유 1줄 · 둘째 바퀴 같은 줄 0
    lines = w.round()
    assert base.launched(w) == [] and len(skip(lines, why)) == 1, lines
    more = r11.again(w)
    assert base.launched(w) == [] and skip(more[len(lines):], why) == [], more


def c1(w, mp):   # ① 진행/ + 재개 줄 + PR OPEN · head·가지 같음 → launch 1 · --base = 40자 · --repo = 카드 루트 리포
    prog(w, LINE), gh(w)
    w.round()
    got = argv(w)
    assert base.launched(w) == [S] and got[0][got[0].index("--base") + 1] == SHA, got
    assert Path(got[0][got[0].index("--repo") + 1]).resolve() == Path(w.root).resolve() and len(calls(w)) >= 1, got


def c2(w, mp):   # ② 원장 seat = 옛 나노 이름 · 세션 없음 → 열기 1 · 원장 seat = 새 나노 이름
    prog(w, LINE), gh(w)
    kw._put(w.state / "card-assign" / (S + ".json"), {"state": "seat", "seat": "byz-harness-nano-old-%s#0" % S, "since": 1.0, "updated": 1.0})
    w.round()
    assert base.launched(w) == [S] and base.ledger(w, S) == {"state": "seat", "seat": base.nh(S)}, base.ledger(w, S)


def c3(w, mp, state="CLOSED"):   # ③ PR CLOSED · MERGED → 열기 0 · 1줄
    prog(w, LINE), gh(w, state=state)
    blocked(w, state)


def c4(w, mp):   # ④ headRefOid 다른 sha(head 바뀜) → 열기 0 · 1줄
    prog(w, LINE), gh(w, headRefOid="def5678" + "0" * 33)
    blocked(w, "head 바뀜")


def c4b(w, mp):   # ④ 둘째 칸 — headRefName 다름 → 열기 0 · 1줄
    prog(w, LINE), gh(w, headRefName="nano/other")
    blocked(w, "가지 다름")


def c5(w, mp):   # ⑤ gh rc≠0 → 열기 0 · «판정 불가» 1줄
    prog(w, LINE), gh(w, rc=1)
    blocked(w, "판정 불가 gh")


def c5b(w, mp):   # ⑤ 둘째 칸 — gh 실행 실패(시간 초과와 같은 rc None) → 같음
    prog(w, LINE), gh(w)
    w.env["FT2_GH"] = str(w.tmp / "bin" / "gh-none")
    blocked(w, "판정 불가 gh")


def c6(w, mp):   # ⑥ 같은 stem 나노 세션 살아 있음 → «이름겹침» · 열기 0
    prog(w, LINE), gh(w)
    alive(w, base.nh(S))
    lines = w.round()
    assert base.launched(w) == [] and len(skip(lines, "이름겹침")) == 1, lines


def c7(w, mp):   # ⑦ 그 work 의 기존 worktree 에 untracked 1개 → 열기 0 · 1줄
    prog(w, LINE), gh(w)
    tree = w.root / ".fable-team" / "teams" / "harness" / "worktrees" / (S + "@a1")
    tree.mkdir(parents=True)
    subprocess.run(["git", "init", "-q", str(tree)], check=True)
    kw._put(tree / "loose.txt", "x")
    blocked(w, "worktree")


def c8(w, mp):   # ⑧ 진행/ 카드 재개 줄 없음 → 읽기 0 · gh 호출 0 · 줄 0
    prog(w, "- 대상: BYZ x.py"), gh(w)
    lines = w.round()
    assert base.launched(w) == [] and calls(w) == [] and [x for x in lines if S in x] == [], lines


def c10(w, mp, folder=GC, ft2=kw.FT2):   # ⑩ 팩 goal-close: check = gc-1.3 · install·promote 뒤 실제 first_body 에 재개 구 · 예시 줄 = keeper 판독 함수가 받음
    mp.setenv("FT2_GC_ROOT", str(w.tmp / "gcroot"))
    gc = load(ft2 / "tools" / "goal_close.py", "gc_r2159")
    assert gc.check(str(folder)) == "gc-1.3"
    assert gc.main(["install", "--pkg", str(folder)]) == 0 and gc.main(["promote", "--root", str(w.root), "--version", "gc-1.3"]) == 0
    tail = gc.phrase(str(w.root), "harness", "nano", "first_body_tail", {"da": "byz-harness-da#1"})
    lp = load(ft2 / "adapters" / "pi" / "launch_plan.py", "lp_r2159")
    env = {"FT2_TEAM": "harness", "FT2_WORK": S, "FT2_ATTEMPT": "a1", "FT2_HOLDER": base.nh(S), "FT2_ROOT": str(w.root)}
    body = lp.first_body(env, (str(w.root), "origin/main", "design/harness/indices"), tail)[1]
    for need in ("gc=gc-1.3", "재개", "git push origin HEAD:<가지>", "새 가지·새 PR 0", "진행/<work>.md", "ft2_claim → ft2_start", "HOLD 줄이 3 이면 DA 요청 0"):
        assert need in body, (need, body)
    example = re.search(r"«(- 재개: [^»]+)»", body)
    assert example and load(ft2 / KN, "kn_r2159").resume_line(example.group(1)) == ("2026-11-17T10:30:00", "7051", "abc1234", "nano/<work>"), body


def c11(w, mp):   # ⑪ 재개 시각(10:30) ≤ 그 work 최신 intent at(11:00) → 열기 0 · 1줄
    prog(w, LINE), gh(w)
    hand(w, S, "2026-11-17T11:00:00")
    blocked(w, "재개시각")


CASES = {"①": c1, "②": c2, "③": c3, "③'": lambda w, mp: c3(w, mp, "MERGED"), "④": c4, "④b": c4b, "⑤": c5, "⑤b": c5b,
         "⑥": c6, "⑦": c7, "⑧": c8, "⑩": c10, "⑪": c11}
MUTANTS = {"M1": ("    r.append(progress(k, team, r, found, prog))", "    r.append({})", ("①", "②")),
           "M2": (" and oid.startswith(got[2])", "", ("④",)),
           "M3": ("+ res[stem][:2]", "+ (res[stem][0], \"origin/main\")", ("①",))}


def run(name, tmp, mp, ft2=kw.FT2):
    w = base.world(tmp, mp, {}, ft2=ft2)
    CASES[name](w, mp)


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    run(name, tmp_path, monkeypatch)


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    old, new, cases = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(kw.FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KN).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KN).write_text(text.replace(old, new), encoding="utf-8")
    for case in cases:
        bad, good = tmp_path / ("bad" + case), tmp_path / ("good" + case)
        bad.mkdir(), good.mkdir()
        with pytest.raises(AssertionError):
            run(case, bad, monkeypatch, tree)
        run(case, good, monkeypatch)   # 원본으로 같은 사례 1회 더 = PASS


def test_mutant_m4(tmp_path, monkeypatch):   # M4 phrases.tsv 재개 구 지움(MODULE sha 다시 맞춤) → ⑩ FAIL · 원본 폴더 = PASS
    folder = tmp_path / "gc-m4"
    shutil.copytree(GC, folder)
    text = (folder / "phrases.tsv").read_text(encoding="utf-8")
    assert text.count(" 재개 = ") == 1
    (folder / "phrases.tsv").write_text(re.sub(r" 재개 = [^\n]*", "", text, count=1), encoding="utf-8")
    meta = json.loads((folder / "MODULE.json").read_text(encoding="utf-8"))
    meta["files"]["phrases.tsv"] = hashlib.sha256((folder / "phrases.tsv").read_bytes()).hexdigest()
    (folder / "MODULE.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    bad, good = tmp_path / "bad", tmp_path / "good"
    bad.mkdir(), good.mkdir()
    with pytest.raises(AssertionError):
        c10(base.world(bad, monkeypatch, {}), monkeypatch, folder)
    c10(base.world(good, monkeypatch, {}), monkeypatch)
