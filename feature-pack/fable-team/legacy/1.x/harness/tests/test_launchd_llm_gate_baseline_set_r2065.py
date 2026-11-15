"""r2065 — launchd LLM 판정기 기준선 = 같은 (경로 · 줄 sha) 의 결합 sha «집합»(카드 반례 ①~⑤ · ⑥ = 기존 시험 재실행).
① X 먼저 · Y 뒤 · 파일 X → ALLOW(기준판 = 결합 불일치 = Red) · ② Y 판 ALLOW · 순서 바꿔 X·Y 둘 다 ALLOW
③ Z 판 → 결합 불일치 rc1 · (경로 · 줄) 줄 0 → 검사 불가 동적 실행 · ④ 맞는 결합 줄 근거 빈칸 → 결합 불일치 / 근거 있는 맞는 줄 1 + 빈 줄 여럿 → ALLOW
⑤ keeper.py 한 줄에 결합 3줄(2.0.51 · 2.0.54 · 2.0.61 꼴) · check --root-dir 가운데 판 · 마지막 판 → 둘 다 ALLOW(기준판 = 가운데 REJECT = Red)
틀 = test_launchd_llm_gate_r1838.py 의 임시 뿌리 · plist · roots.tsv · base.tsv(그 helper 를 그대로 import) · 판정기 대역 = env R1838_GATE(변이판)
실 launchd·실 기준선 읽기·쓰기 0 · 네트워크 0 · sleep 0."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_launchd_llm_gate_r1838 as r1838  # noqa: E402
from test_launchd_llm_gate_r1838 import ORIG, CHANGED, case, check, gate, put  # noqa: E402

w = r1838.w  # 임시 뿌리 fixture 그대로

THIRD = 'root={ext}\nrunner="$root"/zz\nrunner=${{runner}}top\n"$runner" exec sample\n'
MISMATCH, UNKNOWN = "검사 불가 동적 실행(기준선 결합 불일치)", "검사 불가 동적 실행"


def row(w, *args):
    """지금 파일의 동적 지점 1줄 (경로, 줄 sha16, 결합 sha) — list-dyncalls 그대로."""
    rc, out = gate(w, "list-dyncalls", *(args or ("--roots", w / "roots.tsv")))
    rows = [ln.split("\t")[:3] for ln in out.splitlines() if ln.strip()]
    assert rc == 0 and len(rows) == 1 and rows[0][2] != "-", out
    return tuple(rows[0])


def base(w, *lines):
    """(row, 근거) 를 적힌 순서대로 4칸 기준선에 쓴다."""
    (w / "base.tsv").write_text("".join(f"{k}\t{h}\t{b}\t{why}\n" for (k, h, b), why in lines))


def variant(w, text):
    return case(w, entry_sh=text.format(ext=w / "ext"))


@pytest.fixture
def xyz(w):
    """X · Y · Z 판의 동적 지점 줄(같은 경로 · 같은 줄 sha · 다른 결합)."""
    out = {}
    for name, text in (("X", ORIG), ("Y", CHANGED), ("Z", THIRD)):
        p = variant(w, text)
        out[name] = row(w)
    assert len({r[:2] for r in out.values()}) == 1 and len({r[2] for r in out.values()}) == 3, out
    return p, out


def test_1_first_binding_still_allowed(w, xyz):
    p, r = xyz
    base(w, (r["X"], "h-2065-x"), (r["Y"], "h-2065-y"))
    variant(w, ORIG)
    assert check(w, p) == (0, "ALLOW com.byz.ft-fx")


@pytest.mark.parametrize("order", ["XY", "YX"])
@pytest.mark.parametrize("now", [ORIG, CHANGED], ids=["X", "Y"])
def test_2_order_independent(w, xyz, order, now):
    p, r = xyz
    base(w, *((r[k], f"h-2065-{k}") for k in order))
    variant(w, now)
    assert check(w, p) == (0, "ALLOW com.byz.ft-fx")


def test_3_unknown_binding_and_missing_line_reject(w, xyz):
    p, r = xyz
    base(w, (r["X"], "h-2065-x"), (r["Y"], "h-2065-y"))
    variant(w, THIRD)
    rc, out = check(w, p)
    assert rc == 1 and out.startswith("REJECT launchd-llm com.byz.ft-fx ") and MISMATCH in out and out.endswith("bin/entry.sh:4"), out
    (w / "base.tsv").write_text("# 주석만\n")
    rc, out = check(w, p)
    assert rc == 1 and out == f"REJECT launchd-llm com.byz.ft-fx {UNKNOWN} bin/entry.sh:4", out


def test_4_binding_line_without_evidence_is_absent(w, xyz):
    p, r = xyz
    base(w, (r["X"], " "), (r["Y"], "h-2065-y"))
    variant(w, ORIG)
    rc, out = check(w, p)
    assert rc == 1 and out == f"REJECT launchd-llm com.byz.ft-fx {MISMATCH} bin/entry.sh:4", out
    base(w, (r["X"], ""), (r["X"], "h-2065-x"), (r["X"], " "), (r["Y"], ""))
    assert check(w, p) == (0, "ALLOW com.byz.ft-fx")


KEEPER = 'import subprocess, sys\nVERSION = "{v}"\nsubprocess.run(sys.argv[1:])\n'


def test_5_real_baseline_shape_middle_and_last(w):
    dirs = {v: put(w / "ft2" / v / "adapters/pi/keeper.py", KEEPER.format(v=v)).parents[2] for v in ("2.0.51", "2.0.54", "2.0.61")}
    rows = {v: row(w, "--root-dir", d) for v, d in dirs.items()}
    assert len({r[:2] for r in rows.values()}) == 1 and rows["2.0.51"][0] == "ft2-current/adapters/pi/keeper.py", rows
    base(w, *((rows[v], f"h-ft2-{v}-da") for v in dirs))
    for v in ("2.0.54", "2.0.61"):
        assert gate(w, "check", "--root-dir", dirs[v], "--baseline", w / "base.tsv") == (0, "ALLOW ft2-current"), v
