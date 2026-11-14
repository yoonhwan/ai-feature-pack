"""r1940 goal-close 판 도구 (반례 ③~⑥ + 도구 쪽 render·phrase · 변이 M2~M4). 배선 반례 ①②⑦·M1 = r1947. 임시 root·임시 설치 루트(FT2_GC_ROOT)만 — 실 설치·실 명부·바깥 호출·sleep 0. 변이는 도구 사본에서만 · 원본으로 1회 더."""
import hashlib, importlib.util, json, shutil  # noqa: E401
from pathlib import Path
import pytest

FT2 = Path(__file__).resolve().parents[1]
SRC, DA, GOOD = FT2.parent / "goal-close", "byz-x-da-codex#1", "first_body_tail\t새 문장 · 팀 DA {da} 에 판정 요청 ·\n"

def mk(tmp, mp, ft2=FT2, phrases=None, current=None, pins=None):   # 임시 설치 루트 + 팀 A·B 명부(다른 칸 5개) → (도구, 설치 루트, root)
    gcroot, root = tmp / "gc", tmp / "root"
    (root / ".fable-team").mkdir(parents=True)
    for team in "AB":
        cells = dict({"_goal_close": pins[team]} if team in (pins or {}) else {}, _master="m#1", _da=DA, _arch="a#1", _desk="d#1", **{"n#1": {"role": "nano"}})
        (root / ".fable-team" / ("seats-%s.json" % team)).write_text(json.dumps(cells, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (gcroot / "versions" / "gc-1.0").mkdir(parents=True) if phrases is not None else gcroot.mkdir()
    if phrases is not None:
        (gcroot / "versions" / "gc-1.0" / "phrases.tsv").write_text(phrases, encoding="utf-8")
    if current:
        (gcroot / "CURRENT").write_text(current + "\n", encoding="utf-8")
    mp.setenv("FT2_GC_ROOT", str(gcroot))
    spec = importlib.util.spec_from_file_location("gc_r1940", str(ft2 / "tools" / "goal_close.py"))
    gc = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gc)
    return gc, gcroot, root
def pkg(tmp, version, edits=()):   # 팩의 실제 모듈 폴더 사본 → 고침 → 판 이름 · sha256 을 «바르게» 다시 계산
    d = tmp / ("pkg%d-%s" % (len(list(tmp.iterdir())), version))
    shutil.copytree(SRC, d)
    for edit in edits:
        edit(d)
    files = {p.relative_to(d).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(d.rglob("*")) if p.is_file() and p.name != "MODULE.json"}
    (d / "MODULE.json").write_text(json.dumps(dict(json.loads((d / "MODULE.json").read_text(encoding="utf-8")), version=version, files=files), ensure_ascii=False), encoding="utf-8")
    return str(d)
def snap(gcroot, root):   # 선택자 2종(CURRENT · 명부) 바이트 + 판 폴더 목록
    return {p.name: p.read_bytes() for p in [gcroot / "CURRENT", *sorted((root / ".fable-team").glob("seats-*.json"))]}, sorted(p.name for p in (gcroot / "versions").glob("*"))
def two(tmp, mp, ft2):   # 팩 원본이 검사 통과 + gc-1.0·gc-1.1 설치 + CURRENT=gc-1.0 + A 를 gc-1.1 에 고정 → (도구, 설치 루트, root, pin 앞 모습, 인자)
    gc, gcroot, root = mk(tmp, mp, ft2)
    assert gc.check(str(SRC)) == "gc-1.0" and [gc.main(["install", "--pkg", pkg(tmp, v)]) for v in ("gc-1.0", "gc-1.1")] == [0, 0]
    assert gc.main(["promote", "--root", str(root), "--version", "gc-1.0"]) == 0
    before, at = snap(gcroot, root), ["--root", str(root), "--team", "A"]
    assert gc.main(["pin", *at, "--version", "gc-1.1"]) == 0
    return gc, gcroot, root, before, at
def cut(d):   # ⓐ 필수 기준 첫 행의 구를 본문에서만 뺀다(기준 = 도구 옆 contracts — 후보 밖)
    target, need = next(x.rstrip("\n").split("\t") for x in open(FT2 / "contracts" / "goal-close" / "INVARIANTS.tsv", encoding="utf-8") if x.startswith(("phrase:", "file:")))
    path = d / (target[5:] if target.startswith("file:") else "phrases.tsv")
    assert need in path.read_text(encoding="utf-8")
    path.write_text(path.read_text(encoding="utf-8").replace(need, ""), encoding="utf-8")
def thin(d):   # ⓑ 패키지 안에 줄인 목록
    (d / "INVARIANTS.tsv").write_text("", encoding="utf-8")
def c3(tmp, mp, ft2, cap, edits):   # ③ 세 판 모두 거부 · 판 폴더·CURRENT·명부 그대로
    gc, gcroot, root, _, _ = two(tmp, mp, ft2)
    before = snap(gcroot, root)
    assert gc.main(["install", "--pkg", pkg(tmp, "gc-1.2", edits)]) != 0 and snap(gcroot, root) == before
def c4(tmp, mp, ft2, cap, _):   # ④⑥ pin = 그 팀 1칸만 → rollback --team = 앞 값(없음 → 칸 지움) · CURRENT·다른 팀 바이트 그대로
    gc, gcroot, root, (seats, _), at = two(tmp, mp, ft2)
    after, a = snap(gcroot, root)[0], "seats-A.json"
    assert [x for x in after[a].splitlines(True) if b"_goal_close" not in x] == seats[a].splitlines(True) and {**after, a: b""} == {**seats, a: b""}
    assert [gc.selected(str(gcroot), str(root), t) for t in "AB"] == ["gc-1.1", "gc-1.0"]
    assert gc.main(["rollback", *at]) == 0 and snap(gcroot, root)[0] == seats and [gc.selected(str(gcroot), str(root), t) for t in "AB"] == ["gc-1.0", "gc-1.0"]
    log = [json.loads(x) for x in (gcroot / "install-log.jsonl").read_text(encoding="utf-8").splitlines()][-2:]
    assert [(x["op"], x["team"], x["prev"]) for x in log] == [("pin", "A", None), ("rollback", "A", "gc-1.1")], log
    assert gc.phrase(str(root), "B", "nano", "first_body_tail", {"da": DA}).endswith("막힘 = 팀 master 에 mbox · gc=gc-1.0 · ") and gc.main(["pin", *at, "--version", "gc-1.1"]) == 0
    cap.readouterr()   # 도구 쪽 render: 첫 줄 gc=<판> sha=<8자> · 팀 고정 판의 역할 «핵심»만
    head, core = (gc.main(["render", *at, "--role", "nano"]), cap.readouterr().out)[1].split("\n", 1)
    assert head.startswith("gc=gc-1.1 sha=") and len(head.split("sha=")[1]) == 8 and "가지 삭제 0" in core and "## 상세" not in core, (head, core)
def c5(tmp, mp, ft2, cap, _):   # ⑤ 전체 rollback = CURRENT 만 · 고정한 팀 그대로 · «고정값 남은 팀» 1줄
    gc, gcroot, root, _, _ = two(tmp, mp, ft2)
    assert gc.main(["promote", "--root", str(root), "--version", "gc-1.1"]) == 0
    cap.readouterr()
    assert gc.main(["rollback", "--root", str(root)]) == 0
    out = cap.readouterr().out
    assert (gcroot / "CURRENT").read_text(encoding="utf-8").strip() == "gc-1.0" and gc.selected(str(gcroot), str(root), "A") == "gc-1.1"
    assert "고정값 남은 팀" in out and "A=gc-1.1" in out.split("고정값 남은 팀")[1], out

CASES = {"③ⓐ": (c3, (cut,)), "③ⓑ": (c3, (thin,)), "③ⓒ": (c3, (cut, thin)), "④⑥": (c4, ()), "⑤": (c5, ())}
MUTANTS = {"M2": ("③ⓑ③ⓒ", [(' or any(os.path.basename(rel) == os.path.basename(INVARIANTS) for rel in found)', ""),   # 필수 기준을 후보 안 파일에서 읽음
                              ("_read(INVARIANTS).splitlines()", '_read(os.path.join(pkg, "INVARIANTS.tsv") if os.path.exists(os.path.join(pkg, "INVARIANTS.tsv")) else INVARIANTS).splitlines()')]),
           "M3": ("④⑥", [("    if back is not None:\n        _pick(gc, root, team, back)\n", '    open(os.path.join(gc, "CURRENT"), "w").write("gc-1.1\\n")\n')]),   # rollback --team 이 CURRENT 도 씀
           "M4": ("④⑥⑤", [("version or _pin(root, team) or _current(gc)", "version or _current(gc)")])}   # 팀 고정 읽기 삭제

@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch, capsys):
    CASES[name][0](tmp_path, monkeypatch, FT2, capsys, CASES[name][1])
@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch, capsys):   # 변이 = 도구 사본에서만 → 그 사례 FAIL · 원본으로 같은 사례 1회 더 → PASS
    tree, text = tmp_path / "m" / "ft2", (FT2 / "tools" / "goal_close.py").read_text(encoding="utf-8")
    for old, new in MUTANTS[name][1]:
        assert text.count(old) == 1, (name, old)
        text = text.replace(old, new)
    shutil.copytree(FT2 / "contracts" / "goal-close", tree / "contracts" / "goal-close"), (tree / "tools").mkdir()
    (tree / "tools" / "goal_close.py").write_text(text, encoding="utf-8")
    for i, case in enumerate(c for c in CASES if c in MUTANTS[name][0]):
        with pytest.raises(AssertionError):
            CASES[case][0](tmp_path / ("w%d" % i), monkeypatch, tree, capsys, CASES[case][1])
        CASES[case][0](tmp_path / ("o%d" % i), monkeypatch, FT2, capsys, CASES[case][1])
@pytest.mark.parametrize("phrases,current,pins", [(None, None, None), ("other\tx\n", "gc-1.0", None), ("first_body_tail\t팀 DA {da} {zzz}\n", "gc-1.0", None),
                         (GOOD, "gc-1.0", {"A": "gc-9.9"})], ids=["모듈없음", "키없음", "빈칸", "고정판미설치"])
def test_phrase_unknown_is_none(tmp_path, monkeypatch, phrases, current, pins):   # 도구 쪽: 못 읽으면 None(다른 판으로 안 넘어감) · CLI 는 rc1 «판정 불가»
    gc, _, root = mk(tmp_path, monkeypatch, FT2, phrases, current, pins)
    assert gc.phrase(str(root), "A", "nano", "first_body_tail", {"da": DA}) is None
    assert gc.main(["render", "--root", str(root), "--team", "A", "--role", "nano", "--phrase", "first_body_tail"]) == 1
