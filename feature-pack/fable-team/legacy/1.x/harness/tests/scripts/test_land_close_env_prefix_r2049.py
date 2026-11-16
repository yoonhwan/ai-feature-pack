"""r2049 — 자동 닫기(land_close)가 «FT_LAND_REF=origin/<ref> bash ft-nano-close.sh …» 명령도 해석해 그 env 를 붙여 집행한다.

① env 접두 줄 → run 1회 · 인자 = [bash, close, S, --landed-pr, 7, …] · env FT_LAND_REF=origin/ops/main-base (기준판 = 해석 실패 = Red)
② ① 의 결과 CLOSED rc0 → «auto-close CLOSED …» 1줄 · tried 비움 (기준판 = Red)
③ env 없는 `bash …` 줄 → 인자·env 기준판과 같음(FT_LAND_REF 새로 넣지 않음 · 부모 env 값은 그대로)
④ 꼴 밖 머리 4종 → 각각 «판정 불가 auto-close 줄 해석 실패» 1줄 · run 0
⑤ 회귀(r1759 · test_merge_land_close_*.sh) = 따로 돌린다 · 여기서는 bin·kit 같은 바이트
M1 env 값을 집행 env 에 넣지 않음 → ① FAIL · M2 env 이름·값 검사 지움(아무 env 나 받음) → ④ FAIL (변이마다 원본 대조 1회)

격리: run 대역(인자·env 기록) · 임시 명부(role=nano) · 착지기록 대조(ancestor) 대역 · 실 tmux·실 nano-close·네트워크 0 · sleep 0.
R2049_BIN = 시험할 bin 폴더(기본 = 추적본 kit · 기준판 대조 때 덮는다).
"""
from __future__ import annotations

import filecmp
import json
import os
import shutil
import sys
from pathlib import Path

import pytest

HARNESS = Path(__file__).resolve().parents[2]
BIN = Path(os.environ.get("R2049_BIN") or HARNESS / "kit/fable-team/bin")
SEAT = "byz-harness-nano-pk#0"
SET_SHA = "b" * 40
REC = "r1"
STAMP = "T0"
CLOSE = "/stub/ft-nano-close.sh"
TAIL = f"ft-nano-close.sh {SEAT} --landed-pr 7 --result x --recv 1"
WANT_ARGS = ["bash", CLOSE, SEAT, "--landed-pr", "7", "--result", "x", "--recv", "1"]
BAD_HEADS = [
    "FOO=1 bash ",
    "FT_LAND_REF=origin/a FT_LAND_REF=origin/b bash ",
    "FT_LAND_REF=main bash ",
    "FT_LAND_REF=origin/a..b bash ",
]


def _line(head: str) -> str:
    return (f"닫기 차례 {SEAT} 팀=harness 가지=nano/pk landed={'a' * 40} main=abc1234567 갈래=착지기록 "
            f"rec={REC} set={SET_SHA} — {head}{TAIL}")


def _import(bin_dir: Path):
    for k in [k for k in sys.modules if k.startswith("ft_")]:   # 사본 bin 의 짝 모듈까지 다시 읽는다
        sys.modules.pop(k, None)
    sys.path.insert(0, str(bin_dir))
    try:
        import ft_nano_record_auto as m  # noqa: PLC0415 — 사본 bin 을 그때그때 import(변이 시험)
    finally:
        sys.path.remove(str(bin_dir))
    return m


def _close(tmp: Path, monkeypatch, head: str, bin_dir: Path | None = None, rc: int = 0):
    root = tmp / "root"
    (root / ".fable-team").mkdir(parents=True, exist_ok=True)
    (root / ".fable-team" / "seats-harness.json").write_text(
        json.dumps({"_master": "byz-harness-master-pi#217", SEAT: {"role": "nano"}}), encoding="utf-8")
    m = _import(bin_dir or BIN)
    monkeypatch.setattr(m, "ancestor", lambda ctx, seat, rec: "")   # 착지기록 대조 대역(통과)
    monkeypatch.setattr(m, "alert", lambda *a, **k: None)
    calls: list[tuple[list[str], dict]] = []

    def run(argv, env, cap, cwd=None):
        calls.append((list(argv), dict(env)))
        return rc, f"CLOSED {SEAT}\n" if rc == 0 else "REJECT x\n"

    tried: dict = {}
    out = m.land_close(_line(head), tried, STAMP, CLOSE, run, str(root))
    return out, tried, calls


# ── 반례 ①~⑤ ───────────────────────────────────────────────────────────────
def test_1_env_prefix_runs_with_ref(tmp_path, monkeypatch):
    monkeypatch.delenv("FT_LAND_REF", raising=False)
    _, _, calls = _close(tmp_path, monkeypatch, "FT_LAND_REF=origin/ops/main-base bash ")
    assert len(calls) == 1, f"run 1회 여야 한다: {calls}"   # 기준판 = 해석 실패 = run 0 = Red
    argv, env = calls[0]
    assert argv == WANT_ARGS, argv
    assert env.get("FT_LAND_REF") == "origin/ops/main-base", env.get("FT_LAND_REF")
    assert env.get("FT_NANO_AUTO_CLOSE") == "1"


def test_2_env_prefix_closed_line(tmp_path, monkeypatch):
    out, tried, _ = _close(tmp_path, monkeypatch, "FT_LAND_REF=origin/ops/main-base bash ")
    assert out == [f"{STAMP} auto-close CLOSED {SEAT} 갈래=착지기록 rec={REC}"], out
    assert tried == {}, "성공은 tried 에서 지운다"


@pytest.mark.parametrize("parent", [None, "origin/parent"])
def test_3_no_env_unchanged(parent, tmp_path, monkeypatch):
    if parent is None:
        monkeypatch.delenv("FT_LAND_REF", raising=False)
    else:
        monkeypatch.setenv("FT_LAND_REF", parent)
    out, _, calls = _close(tmp_path, monkeypatch, "bash ")
    assert out == [f"{STAMP} auto-close CLOSED {SEAT} 갈래=착지기록 rec={REC}"], out
    assert [c[0] for c in calls] == [WANT_ARGS]
    assert calls[0][1] == {**os.environ, "FT_NANO_AUTO_CLOSE": "1"}, "env 없는 줄 = 부모 env + FT_NANO_AUTO_CLOSE 뿐"
    assert calls[0][1].get("FT_LAND_REF") == parent


@pytest.mark.parametrize("head", BAD_HEADS)
def test_4_other_heads_rejected(head, tmp_path, monkeypatch):
    out, tried, calls = _close(tmp_path, monkeypatch, head)
    assert calls == [], f"꼴 밖 머리 = 집행 0: {head!r}"
    assert len(out) == 1 and out[0].startswith(f"{STAMP} 판정 불가 auto-close 줄 해석 실패 — "), out
    assert tried == {}


def test_5_bin_kit_same_bytes():
    a, b = HARNESS / "bin/ft_nano_record_auto.py", HARNESS / "kit/fable-team/bin/ft_nano_record_auto.py"
    assert filecmp.cmp(a, b, shallow=False), "bin·kit 두 벌이 같은 바이트여야 한다"


# ── 변이 M1~M2 (사본에서만 · 변이마다 원본 대조 1회) ─────────────────────────
MUT = {
    "M1 env 값 안 넣음": ('**ref, "FT_NANO_AUTO_CLOSE"', '"FT_NANO_AUTO_CLOSE"', "FT_LAND_REF=origin/ops/main-base bash "),
    "M2 env 검사 지움": (r'FT_LAND_REF=(origin/(?!\S*\.\.)[A-Za-z0-9._/-]+)', r'\w+=(\S+)', "FOO=1 bash "),
}


def _ok(head: str, out, calls) -> bool:   # 계약대로인가 — 좋은 머리 = FT_LAND_REF 붙여 1회 · 나쁜 머리 = 집행 0
    if head in BAD_HEADS:
        return calls == [] and out[0].startswith(f"{STAMP} 판정 불가 auto-close 줄 해석 실패")
    return len(calls) == 1 and calls[0][1].get("FT_LAND_REF") == "origin/ops/main-base"


@pytest.mark.parametrize("mid", list(MUT))
def test_mutations(mid, tmp_path, monkeypatch):
    anchor, repl, head = MUT[mid]
    monkeypatch.delenv("FT_LAND_REF", raising=False)
    out, _, calls = _close(tmp_path / "orig", monkeypatch, head)   # 원본 대조 — 같은 사례는 통과
    assert _ok(head, out, calls), f"원본 대조 실패 {mid}: {out} {calls}"
    d = tmp_path / "mut"
    d.mkdir()
    for p in sorted(BIN.glob("*.py")):
        shutil.copy(p, d / p.name)
    src = (d / "ft_nano_record_auto.py").read_text(encoding="utf-8")
    assert src.count(anchor) == 1, f"변이 앵커 {src.count(anchor)}곳: {anchor}"
    (d / "ft_nano_record_auto.py").write_text(src.replace(anchor, repl, 1), encoding="utf-8")
    out, _, calls = _close(tmp_path / "mut", monkeypatch, head, bin_dir=d)
    assert not _ok(head, out, calls), f"{mid} 변이인데 통과 = 검출 실패 {out} {calls}"
