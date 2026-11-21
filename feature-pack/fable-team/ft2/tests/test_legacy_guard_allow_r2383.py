"""r2383 ft2 legacy_guard ALLOW 시험 — 반례 ①~⑩ · ⑳ · ㉒ · ㉕ · 변이 M1~M3 · M9 · M10.

①⑧ = 진짜 ft2 트리(git archive HEAD · 라이브) · ②~⑦ = 임시 ft2 꼴 폴더 · ⑨⑩ = 손 기준값과 바이트 대조
⑳ = r1545 시험 test_legacy_guard 의 a~e·m1·m2 를 그대로 부른다. 실 원격 0 · sleep 0 · 변이는 사본에서만.
⑧ 의 «guard 를 부르는 ft2 시험 21파일» 자체 실행은 회귀 명령 몫이다(이 시험 = 그 파일들이 기대하는 guard rc 0 조건 · 카드 반례표 ⑧).
"""
import hashlib
import importlib.util
import re
import subprocess
import sys
import tempfile
from pathlib import Path

FT2 = Path(__file__).resolve().parents[1]
GUARD = FT2 / "tools" / "legacy_guard.py"
OLD = "legacy" + "/1" + ".x"
BIN = "harness" + "/bin"
KIT = "harness" + "/kit"
FABLE = "." + "fable-team" + "/bin"
LIVE = "LIVE" + "_BIN"
PATS = (OLD, BIN, KIT, LIVE, FABLE)
LAND = "adapters/pi/keeper_land.py"
NEXT = "adapters/pi/keeper_next.py"
FIX_OLD = "원장이 카드 줄과 다르면: bash .fable-team" + "/bin/ft-card-assign-watch.sh record <카드> clear <사유>"
NAMES_OLD = ["/".join([OLD, "harness", "bin", "ft-successor-open.sh"]),
             "/".join([OLD, "skill", "scripts", "ft-successor-open.sh"])]


def run(script, root):
    proc = subprocess.run([sys.executable, str(script), str(root)],
                          capture_output=True, text=True, timeout=70)
    return proc.returncode, [line for line in proc.stdout.splitlines() if line.strip()]


def put(root, rel, lines):
    path = Path(root) / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(line + "\n" for line in lines), encoding="utf-8")


def base(root, land=1, nxt=1):
    """ALLOW 표 두 줄을 그대로 채운 기준 트리 — ② = rc 0."""
    put(root, LAND, ["x = read(" + LIVE + ")"] * land)
    put(root, NEXT, ["FIX = '" + FABLE + "/ft-card.sh'"] * nxt)
    return root


def real_tree(tmp):
    """진짜 main ft2 트리 — git archive HEAD 한 벌을 풀어서 준다(①·⑧)."""
    root = Path(tempfile.mkdtemp(dir=str(tmp), prefix="real_"))
    arc = subprocess.run(["git", "-C", str(FT2), "archive", "HEAD", "."], capture_output=True, timeout=70)
    assert arc.returncode == 0, arc.stderr
    subprocess.run(["tar", "-x", "-C", str(root)], input=arc.stdout, check=True, timeout=70)
    return root


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, str(path))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def c1(tmp):   # ① 진짜 main ft2 트리 → rc 0 · 0줄(기준판 = rc 1 · 13줄)
    return run(GUARD, real_tree(tmp))


def c2(tmp):   # ② ALLOW 파일의 그 패턴 1줄 → 안 찍음 · rc 0
    return run(GUARD, base(Path(tmp) / "b"))


def c3(tmp):   # ③ ALLOW 에 없는 파일 → 지금 꼴 1줄 · rc 1
    root = base(Path(tmp) / "c")
    put(root, "core/x.py", ["y = " + LIVE])
    return run(GUARD, root)


def c4(tmp):   # ④ 이름만 같은 다른 폴더 → 위반 1줄(relpath 정확 일치)
    root = base(Path(tmp) / "d")
    put(root, "tests/keeper_land.py", ["y = " + LIVE])
    return run(GUARD, root)


def c5(tmp):   # ⑤ 상한 1 을 2줄로 넘김 → 2줄 + ALLOW-OVER · rc 1
    return run(GUARD, base(Path(tmp) / "e", land=2))


def c6(tmp):   # ⑥ 다리를 걷어 0줄 → ALLOW-STALE · rc 1
    return run(GUARD, base(Path(tmp) / "f", land=0))


def c7(tmp):   # ⑦ ALLOW 파일의 다른 패턴 → 지금 꼴 1줄 · rc 1
    root = base(Path(tmp) / "g")
    put(root, LAND, ["x = read(" + LIVE + ")", "y = '" + KIT + "/x.sh'"])
    return run(GUARD, root)


def c8(tmp):   # ⑧ 라이브 ft2 → rc 0 · 0줄(guard 를 부르는 ft2 시험이 기대하는 조건)
    return run(GUARD, FT2)


def c9(tmp):   # ⑨ 글자 고친 5파일 — 조립한 문자열 == 옛 글자 바이트 같음 · 패턴 글자 0
    src = (FT2 / "tests" / "test_keeper_next_none_names_r2182.py").read_text(encoding="utf-8")
    assert eval(re.search(r"^FIX = .*$", src, re.M).group(0)[len("FIX = "):]) == FIX_OLD
    src = (FT2 / "tests" / "test_new_card_hold.py").read_text(encoding="utf-8")
    assert eval(re.search(r"^    names = .*$", src, re.M).group(0).strip()[len("names = "):]) == NAMES_OLD
    for rel in ("tests/keeper_world_r1812.py", "tests/test_keeper_git_no_lazy_fetch.py",
                "tests/test_keeper_land_anc_memo_r2307.py", "tests/test_keeper_next_none_names_r2182.py",
                "tests/test_new_card_hold.py"):
        text = (FT2 / rel).read_text(encoding="utf-8")
        assert not [p for p in PATS if p in text], rel
    assert (FT2 / LAND).read_text(encoding="utf-8").count(LIVE) == 1   # 다리 줄 = :60 한 줄(ALLOW 상한 1)
    assert '"LIVE" + "_BIN"' in (FT2 / "tests" / "test_keeper_land_anc_memo_r2307.py").read_text(encoding="utf-8")
    return (0, [])


def c10(tmp):   # ⑩ keeper 두 출력이 기준값과 바이트 같음(같은 입력)
    root = Path(tmp) / "k"
    body = "v1"
    (root / ".fable-team" / "bin").mkdir(parents=True)
    (root / "live").mkdir()
    (root / ".fable-team" / "bin" / "ft-land-kind-lib.sh").write_text("# shim\n", encoding="utf-8")
    (root / ".fable-team" / LIVE).write_text(str(root / "live") + "\n", encoding="utf-8")
    (root / "live" / "ft-land-kind-lib.sh").write_text(body, encoding="utf-8")
    assert load(FT2 / LAND, "r2383_land").lib_mark(str(root)) == hashlib.sha1(body.encode()).hexdigest()
    assert load(FT2 / NEXT, "r2383_next").FIX == " · " + FIX_OLD   # keeper_next 쪽은 앞 « · » 가 붙은 꼴
    return (0, [])


def c22(tmp):   # ㉒ ALLOW 줄 둘 다 0줄(패턴을 지움 · 파일은 있음) → ALLOW-STALE 2줄 · rc 1 (DA#56 H1)
    return run(GUARD, base(Path(tmp) / "h", land=0, nxt=0))


def c25(tmp):   # ㉕ 진짜 ft2 사본에서 ALLOW 파일 두 개를 통째로 뺌 → 파일마다 ALLOW-STALE · rc 1 (DA#56 H1)
    root = real_tree(tmp)
    for rel in (LAND, NEXT):
        (root / rel).unlink()
    return run(GUARD, root)


def c20(tmp):   # ⑳ guard ≤ 120줄 · import os·sys 만 · r1545 시험 a~e·m1·m2 PASS
    old = load(FT2 / "tests" / "test_legacy_guard.py", "r2383_old")
    old.test_a_skeleton_and_readme()
    old.test_b_self_scan_clean()
    for name in ("og_c", "og_d", "og_m"):
        (Path(tmp) / name).mkdir(parents=True, exist_ok=True)
    old.test_c_each_case_fails_with_one_line(Path(tmp) / "og_c")
    old.test_d_md_allowed_comments_not(Path(tmp) / "og_d")
    old.test_e_guard_is_small_and_stdlib_only()
    old.test_m1_m2_mutants_miss_their_own_case(Path(tmp) / "og_m")
    return (0, [])


CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑦": c7, "⑧": c8, "⑨": c9, "⑩": c10,
         "⑳": c20, "㉒": c22, "㉕": c25}
EXPECT = {
    "①": (0, []),
    "②": (0, []),
    "③": (1, ["core/x.py:1: " + LIVE]),
    "④": (1, ["tests/keeper_land.py:1: " + LIVE]),
    "⑤": (1, [LAND + ":1: " + LIVE, LAND + ":2: " + LIVE, "ALLOW-OVER " + LAND + " " + LIVE + " 2/1"]),
    "⑥": (1, ["ALLOW-STALE " + LAND + " " + LIVE]),
    "⑦": (1, [LAND + ":2: " + KIT]),
    "⑧": (0, []),
    "⑨": (0, []),
    "⑩": (0, []),
    "⑳": (0, []),
    "㉒": (1, ["ALLOW-STALE " + LAND + " " + LIVE, "ALLOW-STALE " + NEXT + " " + FABLE]),
    "㉕": (1, ["ALLOW-STALE " + LAND + " " + LIVE, "ALLOW-STALE " + NEXT + " " + FABLE]),
}
# 변이 (사본에서만 · 변이마다 원본으로 같은 사례 1회 더)
MUTANTS = {
    "M1": ("상한 무시", [("        if cap is not None and counted[(rel, pattern)] <= cap:", "        if cap is not None:")], "⑤"),
    "M2": ("STALE 검사 지움", [
        ("        elif got == 0 and (alive or ftree or os.path.isfile(os.path.join(root, rel))):",
         "        elif got == 0 and False:")], "⑥"),
    "M3": ("relpath 대신 basename", [
        ("caps = {(rel, pattern): cap for rel, pattern, cap, _card, _why in ALLOW}",
         "caps = {(os.path.basename(rel), pattern): cap for rel, pattern, cap, _card, _why in ALLOW}"),
        ("counted[(rel, pattern)] = counted.get((rel, pattern), 0) + 1",
         "counted[(os.path.basename(rel), pattern)] = counted.get((os.path.basename(rel), pattern), 0) + 1"),
        ("        cap = caps.get((rel, pattern))", "        cap = caps.get((os.path.basename(rel), pattern))"),
        ("        if cap is not None and counted[(rel, pattern)] <= cap:",
         "        if cap is not None and counted[(os.path.basename(rel), pattern)] <= cap:")], "④"),
    "M9": ("STALE = 살아있는 줄이 있을 때만", [
        ("        elif got == 0 and (alive or ftree or os.path.isfile(os.path.join(root, rel))):",
         "        elif got == 0 and ftree:")], "㉒"),
    "M10": ("ALLOW 파일 있나(ft2 트리) 검사 지움", [
        ("        elif got == 0 and (alive or ftree or os.path.isfile(os.path.join(root, rel))):",
         "        elif got == 0 and (alive or os.path.isfile(os.path.join(root, rel))):")], "㉕"),
}


def test_cases(tmp_path):
    for name, case in CASES.items():
        assert case(tmp_path) == EXPECT[name], name


def test_mutants(tmp_path):
    global GUARD
    source = GUARD.read_text(encoding="utf-8")
    for name, (why, subs, case) in MUTANTS.items():
        text = source
        for old, new in subs:
            assert text.count(old) == 1, (name, old)
            text = text.replace(old, new)
        path = tmp_path / ("mutant_" + name + ".py")
        path.write_text(text, encoding="utf-8")
        mut_dir, live_dir = tmp_path / ("w_" + name), tmp_path / ("o_" + name)
        mut_dir.mkdir()
        live_dir.mkdir()
        keep = GUARD
        GUARD = path
        try:
            assert CASES[case](mut_dir) != EXPECT[case], (name, why)
        finally:
            GUARD = keep
        assert CASES[case](live_dir) == EXPECT[case], (name, why)
