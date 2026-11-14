"""r1947 goal-close W1 배선 — launch.py 가 phrase() 1회 → first_body(tail) (r1940 반례 ①②⑦ · 변이 M1).
열기는 test_pi_launch 의 가짜 git·tmux·pi + `--dry-run` 그대로(첫 본문 = tmux argv 끝) · 설치 루트 = 임시 FT2_GC_ROOT · sleep 0.
⑦ = 기존 test_pi_launch·r1930·r1900 시험을 같은 묶음으로 돌린다. 변이는 ft2 사본에서만 · 원본으로 1회 더.
"""
import importlib.util, json, shutil  # noqa: E401
from pathlib import Path
import pytest
FT2 = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location("pl_r1947", str(FT2 / "tests" / "test_pi_launch.py"))
pl = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pl)
DA, PHRASES = "byz-harness-da-codex#10", (FT2.parent / "goal-close" / "phrases.tsv").read_text(encoding="utf-8")
BAN, END = ("병합", "착지", "설치", "가지 삭제"), "이 좌석에 적용 0"
def body(tmp, phrases=PHRASES, roster=None, launcher=pl.LAUNCH):   # 임시 root·설치 루트 → dry-run 첫 본문
    root, fake = pl._paths(tmp)
    (root / ".fable-team" / "seats-harness.json").write_text(json.dumps(roster or {"_da": DA}), encoding="utf-8")
    gc = Path(tmp) / "gc"
    if phrases is not None:
        (gc / "versions" / "gc-1.0").mkdir(parents=True)
        (gc / "versions" / "gc-1.0" / "phrases.tsv").write_text(phrases, encoding="utf-8")
        (gc / "CURRENT").write_text("gc-1.0\n", encoding="utf-8")
    pl._runtime(root)
    out, rc = pl._launch(root, fake, launcher, extra=["--dry-run"], env_extra={"FT2_GC_ROOT": str(gc)})
    assert rc == 0 and out["dry_run"] is True, out
    return out["argv"]["tmux"][-1]
@pytest.mark.parametrize("phrases,need", [(PHRASES, "팀 DA %s 에 판정 요청" % DA), (PHRASES.replace("산출 =", "새 문장 · 산출 ="), "부터 · 새 문장 · 산출 =")], ids=["CURRENT", "새 문장"])
def test_c1_current(tmp_path, phrases, need):   # ① CURRENT 판 문구 + gc=<판> 이 끝 상수 앞 · 끝 = 코드 상수
    text = body(tmp_path, phrases)
    assert need in text and "모듈 못 읽음" not in text and text.endswith(END), text
    assert "mbox · gc=gc-1.0 · main·ops/main-base push" in text and text.index("gc=gc-1.0") < text.index(BAN[0]), text
CASES = {"모듈 없음": dict(phrases=None), "키 없음": dict(phrases="other_key\t글 ·\n"),
         "빈칸 못 채움": dict(roster={"_master": "m#1"}), "고정 판 미설치": dict(roster={"_da": DA, "_goal_close": "gc-9.9"}),
         "64KB 초과": dict(phrases=PHRASES + "#" * (64 * 1024))}
def c2(tmp, kw, launcher=pl.LAUNCH):   # ② 못 읽음 → 내장 문구 + «모듈 못 읽음» · claim → start 구 · 금지 낱말 4개 · 끝 상수
    text = body(tmp, launcher=launcher, **kw)
    assert "모듈 못 읽음" in text and "gc=" not in text and "ft2_claim → ft2_start 부터" in text, text
    assert all(word in text for word in BAN) and text.endswith(END), text
@pytest.mark.parametrize("name", sorted(CASES))
def test_c2_fallback(tmp_path, name):
    c2(tmp_path, CASES[name])
def test_m1(tmp_path):   # M1 ②의 내장 문구 가지 삭제(사본) → ② FAIL · 원본 1회 더 → PASS
    copy = tmp_path / "ft2"
    shutil.copytree(FT2, copy, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    src = copy / "adapters" / "pi" / "launch_plan.py"
    text, old = src.read_text(encoding="utf-8"), ' if tail else "ft2_claim → ft2_start 부터 · 모듈 못 읽음 · " + ('
    assert text.count(old) == 1
    src.write_text(text.replace(old, " or (", 1), encoding="utf-8")
    with pytest.raises(AssertionError):
        c2(tmp_path / "m", CASES["모듈 없음"], launcher=copy / "adapters" / "pi" / "launch.py")
    c2(tmp_path / "o", CASES["모듈 없음"])
