"""r2296 keeper 끝 판독 — «완성» 단계 · 착지 줄 0 · 마지막 «- 완료: » 줄 ALREADY = 끝(superseded) · 그 밖 완성·착지 줄 0 = UNKNOWN 1줄(같은 사유 1회).
반례 ①~④ · ①ⓑ ①ⓒ ①ⓓ · 변이 M1~M4(사본) · 기준판 ①② Red(FT2_R2296_BASE = 기준 keeper_endings.py 경로일 때만).
대역 = 임시 git 리포(design/TEAMS.md · 팀 indices · 카드) + 대역 keeper(git · cache · state · unknown_line 기록) · 실 keeper·gh 0 · sleep 0."""
import importlib.util, os, shutil, subprocess  # noqa: E401
from pathlib import Path
import pytest
FT2 = Path(__file__).resolve().parents[1]
TEAM, FOLDER = "harness", "design/harness"
ALREADY = "- 완료: byz-harness-nano-r9001#0 · 한 일: ALREADY — 대체 r1752 · 코드·가지·PR 0"
PLAIN = "- 완료: byz-harness-nano-r9001#1 · 한 일: [fix] 고침 · 산출: nano/r9001"
MOVED = "- 2026-11-19T18:15:40 · 대기→완성(분류표 묶음)"
ID = ["-c", "user.email=t@t", "-c", "user.name=t", "-c", "commit.gpgsign=false"]
def _git(cwd, *a):
    p = subprocess.run(["git", *ID, *a], cwd=cwd, capture_output=True, text=True, timeout=7)
    return p.returncode, p.stdout, p.stderr
class K:
    """대역 keeper — _card_end 가 부르는 손만(git · cache · state · unknown_line · resolve_card)."""
    def __init__(s, root):
        s.root, s.cache, s.state, s.lines = str(root), {}, {"held": {}}, []
    def git(s, cwd, *a):
        return _git(cwd, *a)
    def unknown_line(s, team, work, kind, text):
        s.lines.append((team, work, kind, text))
    def resolve_card(s, team, work):
        return [], None
def load(ft2=FT2):
    spec = importlib.util.spec_from_file_location("r2296_endings_%d" % id(ft2), str(Path(ft2) / "adapters" / "pi" / "keeper_endings.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod
def repo(tmp, cards):
    """cards = {stage: {work: body}} → origin/ops/main-base·origin/main 둘 다 같은 트리."""
    root = tmp / "byz"
    (root / "design").mkdir(parents=True)
    (root / "design" / "TEAMS.md").write_text("| team | folder |\n|---|---|\n| %s | %s |\n" % (TEAM, FOLDER), encoding="utf-8")
    for stage, works in cards.items():
        for work, body in works.items():
            (root / FOLDER / "indices" / stage).mkdir(parents=True, exist_ok=True)
            (root / FOLDER / "indices" / stage / (work + ".md")).write_text(body, encoding="utf-8")
    _git(root, "init", "-q"), _git(root, "add", "-A"), _git(root, "commit", "-qm", "c")
    [_git(root, "update-ref", "refs/remotes/origin/" + ref, "HEAD") for ref in ("ops/main-base", "main")]
    return K(root)
def body(*rows):
    return "# 인덱스: r9001\n- 대상: x\n\n## 상태\n" + "".join(r + "\n" for r in rows)
def c1(E, tmp):    # ① 완성 · 착지 줄 0 · 마지막 완료 ALREADY · 상태 끝 «대기→완성» → superseded · UNKNOWN 0
    k = repo(tmp, {"완성": {"r9001": body(ALREADY, MOVED)}})
    assert E._card_end(k, TEAM, "r9001") == ("superseded", "카드 완성 · ALREADY") and k.lines == []
def c1b(E, tmp):   # ①ⓑ 완성 · 착지 줄 있음 · ALREADY → 기준판과 같음(_head None · UNKNOWN 0)
    k = repo(tmp, {"완성": {"r9001": body(ALREADY, "- 착지: " + "a" * 40, MOVED)}})
    assert E._card_end(k, TEAM, "r9001") is None and k.lines == []
def c1c(E, tmp):   # ①ⓒ 앞 완료 ALREADY · 마지막 보통 완료 · 착지 줄 0 → None · UNKNOWN 1줄
    k = repo(tmp, {"완성": {"r9001": body(ALREADY, PLAIN, MOVED)}})
    assert E._card_end(k, TEAM, "r9001") is None and len(k.lines) == 1, k.lines
def c1d(E, tmp):   # ①ⓓ 완성 · ALREADY · 상태 끝 «중단:» → _head 먼저 = suspended
    k = repo(tmp, {"완성": {"r9001": body(ALREADY, "- 2026-11-19 — 중단: 오빠 보류")}})
    assert E._card_end(k, TEAM, "r9001")[0] == "suspended" and k.lines == []
def c2(E, tmp):    # ② 완성 · 착지 줄 0 · ALREADY 0 → None · UNKNOWN 1줄 · 다시 부름 0줄
    k = repo(tmp, {"완성": {"r9001": body(PLAIN, MOVED)}})
    first = E._card_end(k, TEAM, "r9001")
    assert first is None and k.lines == [(TEAM, "-", "held", "r9001 완성 · 착지 줄 0 · 끝 판독 불가")], k.lines
    assert E._card_end(k, TEAM, "r9001") is None and len(k.lines) == 1, k.lines
def c3(E, tmp):    # ③ 진행 · 착지 줄 0 · ALREADY → None · UNKNOWN 0
    k = repo(tmp, {"진행": {"r9001": body(ALREADY, MOVED)}})
    assert E._card_end(k, TEAM, "r9001") is None and k.lines == []
def c3b(E, tmp):   # ③ⓑ 후보 2장(진행 + 완성) → False 그대로
    k = repo(tmp, {"진행": {"r9001": body(ALREADY)}, "완성": {"r9001": body(ALREADY)}})
    assert E._card_end(k, TEAM, "r9001") is False and k.lines == []
def c4(E, tmp):    # ④ 완성후 · ALREADY → 카드 완성후/
    k = repo(tmp, {"완성후": {"r9001": body(ALREADY, MOVED)}})
    assert E._card_end(k, TEAM, "r9001") == ("superseded", "카드 완성후/") and k.lines == []
CASES = [c1, c1b, c1c, c1d, c2, c3, c3b, c4]
@pytest.mark.parametrize("case", CASES, ids=[c.__name__ for c in CASES])
def test_case(case, tmp_path):
    case(load(), tmp_path)
@pytest.mark.skipif(not os.environ.get("FT2_R2296_BASE"), reason="기준판 경로 없음")
@pytest.mark.parametrize("case", [c1, c2], ids=["c1", "c2"])
def test_base_red(case, tmp_path):
    with pytest.raises(AssertionError):
        case(load(clone(tmp_path, None, Path(os.environ["FT2_R2296_BASE"]).read_text(encoding="utf-8"))), tmp_path / "w")
def clone(tmp, old, new):
    """core + adapters/pi 사본 · keeper_endings.py 의 old → new(old None = 파일 통째)."""
    dst = tmp / "ft2"
    for sub in ("core", "adapters/pi"):
        shutil.copytree(FT2 / sub, dst / sub, ignore=shutil.ignore_patterns("__pycache__"))
    path = dst / "adapters" / "pi" / "keeper_endings.py"
    text = path.read_text(encoding="utf-8")
    if old is not None and text.count(old) != 1:   # 변이 자리 없음 = 시험 오류(AssertionError 로 변이 잡힘을 흉내 내지 않음)
        raise ValueError("변이 자리 %d개: %s" % (text.count(old), old))
    path.write_text(new if old is None else text.replace(old, new), encoding="utf-8")
    return dst
MUTANTS = [   # (이름, old, new, 깨져야 할 사례)
    ("M1", ' or re.search(r"^- 착지: ", body, re.M)', "", c1b),
    ("M2", 'stage != "완성"', "stage not in DONE + (\"완성\", \"진행\", \"대기\")", c3),
    ("M3", '"end-done-noland:" + work', '"end-done-noland:" + work + k.__class__.__name__ + str(len(k.lines))', c2),
    ("M4", '"ALREADY" in done[-1]', 'any("ALREADY" in d for d in done)', c1c),
]
@pytest.mark.parametrize("name,old,new,case", MUTANTS, ids=[m[0] for m in MUTANTS])
def test_mutant(name, old, new, case, tmp_path):
    case(load(), tmp_path / "orig")   # 원본 = 통과(반대 결과 대조)
    with pytest.raises(AssertionError):
        case(load(clone(tmp_path, old, new)), tmp_path / "mut")
