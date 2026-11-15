"""r1953 goal-close 명부 읽기 상한 분리 (반례 ①~⑤ · 변이 M1~M3). 실 harness 명부는 366,989 바이트 — 판 폴더 파일 상한(64KB)을 명부에 걸면 그 팀은 늘 판정 불가다.
명부 = 전용 상한 4MB · 판 폴더 파일 = 64KB 그대로 · render --phrase 의 {da} = 인자 --da → 없으면 명부 _da. 임시 root·임시 설치 루트만 — 실 명부·바깥 호출·sleep 0."""
import importlib.util, json  # noqa: E401
from pathlib import Path
import pytest
_spec = importlib.util.spec_from_file_location("t_r1940_for_r1953", str(Path(__file__).with_name("test_goal_close_r1940.py")))
t = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(t)
KB, KEY = 1024, "first_body_tail"
def big(tmp, mp, ft2, size=70 * KB, phrases=t.GOOD, **cells):   # 팀 A 명부를 size 바이트 넘게 키운다(다른 칸 그대로 + cells) · CURRENT = gc-1.0 → (도구, 설치 루트, root, 명부 경로, CLI 인자)
    gc, gcroot, root = t.mk(tmp, mp, ft2, phrases, "gc-1.0")
    a = root / ".fable-team" / "seats-A.json"
    doc = dict(json.loads(a.read_text(encoding="utf-8")), **cells, **{"n#2": {"role": "nano", "note": "x" * size}})
    a.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (gcroot / "versions" / "gc-1.0" / "MODULE.json").write_text("{}", encoding="utf-8")
    assert a.stat().st_size > size
    return gc, gcroot, root, a, ["--root", str(root), "--team", "A"]
def run(gc, cap, argv):   # CLI 1회 → (rc, 출력)
    return (cap.readouterr(), gc.main(argv), cap.readouterr().out)[1:]
def c1(tmp, mp, ft2, cap):   # ① 70KB 명부(_goal_close 없음) + CURRENT → 그 판 · phrase 문장
    gc, gcroot, root, _, _ = big(tmp, mp, ft2)
    assert gc.selected(str(gcroot), str(root), "A") == "gc-1.0"
    assert gc.phrase(str(root), "A", "nano", KEY, {"da": t.DA}) == "새 문장 · 팀 DA %s 에 판정 요청 · gc=gc-1.0 · " % t.DA
def c2(tmp, mp, ft2, cap):   # ② 70KB 명부 pin → 그 1칸만(다른 줄 바이트 같음) · rollback → 앞 값(칸 없음 = 처음 바이트)
    gc, gcroot, root, a, at = big(tmp, mp, ft2)
    before = a.read_bytes()
    assert run(gc, cap, ["pin", *at, "--version", "gc-1.0"])[0] == 0 and json.loads(a.read_text(encoding="utf-8"))["_goal_close"] == "gc-1.0"
    assert [x for x in a.read_bytes().splitlines(True) if b"_goal_close" not in x] == before.splitlines(True)
    assert run(gc, cap, ["rollback", *at])[0] == 0 and a.read_bytes() == before
def c3(tmp, mp, ft2, cap):   # ③ 4MB+1 명부 → 판정 불가 «명부 4MB 초과» · phrase None · 쓰기 0
    gc, gcroot, root, a, at = big(tmp, mp, ft2, 4 * KB * KB + 1)
    before = a.stat().st_mtime_ns
    assert gc.selected(str(gcroot), str(root), "A") is None and gc.phrase(str(root), "A", "nano", KEY, {"da": t.DA}) is None
    for argv in (["render", *at, "--phrase", KEY], ["pin", *at, "--version", "gc-1.0"]):
        rc, out = run(gc, cap, argv)
        assert rc == 1 and "명부 4MB 초과" in out and a.stat().st_mtime_ns == before, (argv, rc, out)
def c4(tmp, mp, ft2, cap):   # ④ 판 폴더 phrases.tsv 65KB → 여전히 «64KB 초과»(판 상한 회귀) · 명부는 70KB 라도 그 탓이 아니다
    gc, gcroot, root, _, at = big(tmp, mp, ft2, phrases=t.GOOD + "pad\t" + "x" * (65 * KB) + "\n")
    assert gc.selected(str(gcroot), str(root), "A") == "gc-1.0" and gc.phrase(str(root), "A", "nano", KEY, {"da": t.DA}) is None
    rc, out = run(gc, cap, ["render", *at, "--phrase", KEY])
    assert rc == 1 and "64KB 초과" in out and "phrases.tsv" in out and "명부" not in out, (rc, out)
def c5(tmp, mp, ft2, cap):   # ⑤ render --phrase: {da} = 명부 _da · 인자 --da 가 있으면 인자 우선 · 명부에 _da 없으면 지금처럼 «빈칸 못 채움»
    gc, gcroot, root, a, at = big(tmp, mp, ft2, _da="byz-x-da-codex#7")
    rc, out = run(gc, cap, ["render", *at, "--phrase", KEY])
    assert rc == 0 and out.startswith("gc=gc-1.0 sha=") and "팀 DA byz-x-da-codex#7 에 판정 요청" in out, (rc, out)
    rc, out = run(gc, cap, ["render", *at, "--phrase", KEY, "--da", "byz-y-da-codex#3"])
    assert rc == 0 and "팀 DA byz-y-da-codex#3 에 판정 요청" in out and "codex#7" not in out, (rc, out)
    a.write_text(json.dumps({k: v for k, v in json.loads(a.read_text(encoding="utf-8")).items() if k != "_da"}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    rc, out = run(gc, cap, ["render", *at, "--phrase", KEY])
    assert rc == 1 and "빈칸 못 채움" in out, (rc, out)
CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5}
MUTANTS = {"M1": ("①②", "_read(_roster(root, team), ROSTER_LIMIT)", "_read(_roster(root, team))"),   # 명부도 판 폴더 상한 64KB
           "M2": ("④", "def _read(path, limit=LIMIT):", "def _read(path, limit=ROSTER_LIMIT):"),   # 판 폴더 파일도 명부 상한 4MB
           "M3": ("⑤", 'da=args.get("da") or _doc(root, team).get("_da")', 'da=args.get("da")')}   # 명부 _da 채움 삭제
@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch, capsys):
    CASES[name](tmp_path, monkeypatch, t.FT2, capsys)
@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch, capsys):   # 변이 = 도구 사본에서만 → 그 사례 FAIL · 원본으로 같은 사례 1회 더 → PASS
    cases, old, new = MUTANTS[name]
    tree, text = tmp_path / "m" / "ft2", (t.FT2 / "tools" / "goal_close.py").read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / "tools").mkdir(parents=True)
    (tree / "tools" / "goal_close.py").write_text(text.replace(old, new), encoding="utf-8")
    for i, case in enumerate(c for c in CASES if c in cases):
        with pytest.raises(AssertionError):
            CASES[case](tmp_path / ("w%d" % i), monkeypatch, tree, capsys)
        CASES[case](tmp_path / ("o%d" % i), monkeypatch, t.FT2, capsys)
