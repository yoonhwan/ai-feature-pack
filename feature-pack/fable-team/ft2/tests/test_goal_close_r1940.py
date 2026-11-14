"""r1940 goal-close 모듈 첫 판 + 나노 첫 본문 배선 (반례 ①~⑥ · ⑦ = 기존 묶음). 임시 root·임시 설치 루트(FT2_GC_ROOT)만 — 실 설치·실 명부·바깥 호출·sleep 0."""
import hashlib, importlib.util, json, shutil  # noqa: E401
from pathlib import Path
import pytest

FT2 = Path(__file__).resolve().parents[1]
BAN = "main·ops/main-base push·병합·착지·설치·심링크·가지 삭제 0(= master·h 몫) · AGENTS.md «Landing the Plane» 은 이 좌석에 적용 0"
DA, GOOD = "byz-x-da-codex#1", "first_body_tail\t새 문장 · 팀 DA {da} 에 판정 요청 ·\n"

def load(rel):
    spec = importlib.util.spec_from_file_location("r1940_" + Path(rel).stem, str(FT2 / rel))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

def mk(tmp, mp, phrases=None, current=None, pins=None):   # 임시 설치 루트 + 팀 A·B 명부(다른 칸 5개) → (도구, 설치 루트, root)
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
    return load("tools/goal_close.py"), gcroot, root

def pkg(tmp, version, edits=()):   # 팩의 실제 모듈 폴더 사본 → 고침 → 판 이름 · sha256 을 «바르게» 다시 계산
    d = tmp / ("pkg%d-%s" % (len(list(tmp.iterdir())), version))
    shutil.copytree(FT2.parent / "goal-close", d)
    for edit in edits:
        edit(d)
    files = {p.relative_to(d).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(d.rglob("*")) if p.is_file() and p.name != "MODULE.json"}
    (d / "MODULE.json").write_text(json.dumps(dict(json.loads((d / "MODULE.json").read_text(encoding="utf-8")), version=version, files=files), ensure_ascii=False), encoding="utf-8")
    return str(d)

def body(root, tail):
    env = {"FT2_TEAM": "A", "FT2_WORK": "r9", "FT2_ATTEMPT": "a1", "FT2_HOLDER": "n#1", "FT2_ROOT": str(root)}
    return load("adapters/pi/launch_plan.py").first_body(env, ("/r", "origin/main", "design/A/indices"), tail)[1]

def snap(gcroot, root):   # 선택자 2종(CURRENT · 명부) 바이트 + 판 폴더 목록
    return {p.name: p.read_bytes() for p in [gcroot / "CURRENT", *sorted((root / ".fable-team").glob("seats-*.json"))]}, sorted(p.name for p in (gcroot / "versions").glob("*"))

def two(tmp, mp):   # 팩 원본이 검사를 통과 + gc-1.0·gc-1.1 설치 + CURRENT=gc-1.0 + A 를 gc-1.1 에 고정 → (도구, 설치 루트, root, pin 앞 모습, 인자)
    gc, gcroot, root = mk(tmp, mp)
    assert gc.check(str(FT2.parent / "goal-close")) == "gc-1.0" and [gc.main(["install", "--pkg", pkg(tmp, v)]) for v in ("gc-1.0", "gc-1.1")] == [0, 0]
    assert gc.main(["promote", "--root", str(root), "--version", "gc-1.0"]) == 0
    before, at = snap(gcroot, root), ["--root", str(root), "--team", "A"]
    assert gc.main(["pin", *at, "--version", "gc-1.1"]) == 0
    return gc, gcroot, root, before, at

@pytest.mark.parametrize("phrases,current,pins", [(None, None, None), ("other\tx\n", "gc-1.0", None), ("first_body_tail\t팀 DA {da} {zzz}\n", "gc-1.0", None),
                         (GOOD, "gc-1.0", {"A": "gc-9.9"})], ids=["모듈없음", "키없음", "빈칸", "고정판미설치"])
def test_fallback_keeps_safety(tmp_path, monkeypatch, phrases, current, pins):   # ② 못 읽으면 내장 문구 + «모듈 못 읽음» · 금지 목록 그대로
    gc, _, root = mk(tmp_path, monkeypatch, phrases, current, pins)
    assert gc.phrase(str(root), "A", "nano", "first_body_tail", {"da": DA}) is None
    text = body(root, None)
    assert "모듈 못 읽음" in text and "ft2_claim → ft2_start" in text and text.endswith(BAN), text

def test_current_phrase_in_body(tmp_path, monkeypatch):   # ① CURRENT 판 문구 + gc=<판> 이 금지 목록 앞
    gc, _, root = mk(tmp_path, monkeypatch, GOOD, "gc-1.0")
    text = body(root, gc.phrase(str(root), "A", "nano", "first_body_tail", {"da": DA}))
    assert "새 문장 · 팀 DA %s 에 판정 요청" % DA in text and "모듈 못 읽음" not in text and text.endswith(BAN), text
    assert text.index("새 문장") < text.index("gc=gc-1.0") < text.index(BAN), text

def cut(d):   # ⓐ 필수 기준 첫 행의 구를 본문에서만 뺀다(기준 = 도구 옆 contracts — 후보 밖)
    target, need = next(x.rstrip("\n").split("\t") for x in open(FT2 / "contracts" / "goal-close" / "INVARIANTS.tsv", encoding="utf-8") if x.startswith(("phrase:", "file:")))
    path = d / (target[5:] if target.startswith("file:") else "phrases.tsv")
    assert need in path.read_text(encoding="utf-8")
    path.write_text(path.read_text(encoding="utf-8").replace(need, ""), encoding="utf-8")

def thin(d):   # ⓑ 패키지 안에 줄인 목록
    (d / "INVARIANTS.tsv").write_text("", encoding="utf-8")

@pytest.mark.parametrize("edits", [(cut,), (thin,), (cut, thin)], ids=["ⓐ", "ⓑ", "ⓒ"])
def test_install_rejects(tmp_path, monkeypatch, edits):   # ③ 세 판 모두 거부 · 판 폴더·CURRENT·명부 그대로
    gc, gcroot, root, _, _ = two(tmp_path, monkeypatch)
    before = snap(gcroot, root)
    assert gc.main(["install", "--pkg", pkg(tmp_path, "gc-1.2", edits)]) != 0 and snap(gcroot, root) == before

def test_pin_one_cell_then_team_rollback(tmp_path, monkeypatch):   # ④⑥ pin = 그 팀 1칸만 → rollback --team = 앞 값(없음 → 칸 지움)
    gc, gcroot, root, (seats, _), at = two(tmp_path, monkeypatch)
    after, a = snap(gcroot, root)[0], "seats-A.json"
    assert [x for x in after[a].splitlines(True) if b"_goal_close" not in x] == seats[a].splitlines(True) and {**after, a: b""} == {**seats, a: b""}
    assert [gc.selected(str(gcroot), str(root), t) for t in "AB"] == ["gc-1.1", "gc-1.0"]
    assert gc.main(["rollback", *at]) == 0 and snap(gcroot, root)[0] == seats and [gc.selected(str(gcroot), str(root), t) for t in "AB"] == ["gc-1.0", "gc-1.0"]
    log = [json.loads(x) for x in (gcroot / "install-log.jsonl").read_text(encoding="utf-8").splitlines()][-2:]
    assert [(x["op"], x["team"], x["prev"]) for x in log] == [("pin", "A", None), ("rollback", "A", "gc-1.1")], log

def test_global_rollback_keeps_pins(tmp_path, monkeypatch, capsys):   # ⑤ 전체 rollback = CURRENT 만 · 고정한 팀 그대로 · 1줄
    gc, gcroot, root, _, _ = two(tmp_path, monkeypatch)
    assert gc.main(["promote", "--root", str(root), "--version", "gc-1.1"]) == 0
    capsys.readouterr()
    assert gc.main(["rollback", "--root", str(root)]) == 0
    out = capsys.readouterr().out
    assert (gcroot / "CURRENT").read_text(encoding="utf-8").strip() == "gc-1.0" and gc.selected(str(gcroot), str(root), "A") == "gc-1.1"
    assert "고정값 남은 팀" in out and "A=gc-1.1" in out.split("고정값 남은 팀")[1], out
