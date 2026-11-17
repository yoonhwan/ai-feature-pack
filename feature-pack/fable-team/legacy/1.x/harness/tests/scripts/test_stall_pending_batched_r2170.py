"""r2170 — pending_mail 은 wake_at 이 아직 오지 않은 큐 행(«묶인 행»)을 미읽음으로 세지 않는다.

B1 묶인 행 = wake_at 이 정수 ∧ 지금 < wake_at ≤ 지금 + 3600 · B2 그 밖(칸 없음·글자·소수·null·지난 시각·+3600 초과)은 센다
B3 묶인 행만 가진 좌석 = 결과 없음(d 0) · 섞이면 안 묶인 행만으로 (seq · 나이) · B4 반환 꼴·칸 없는 큐 = 기준판과 같음.
R2170_BIN = 시험할 bin 폴더(기본 kit) — 기준판·변이 사본(M1~M4)을 넣어 반대 결과를 대조한다.
"""
import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

import pytest

from _stall_world import NOW, World, counts
from real_state_guard import guard_begin_module  # noqa: F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

BIN = Path(os.environ.get("R2170_BIN") or Path(__file__).resolve().parents[2] / "kit/fable-team/bin").resolve()
X = "t1-nano#0"
_ABSENT = object()


def row(seq: int, minutes_ago: float, wake_at: object = _ABSENT, to: str = X) -> str:
    r: dict[str, object] = {"seq": seq, "ts": datetime.fromtimestamp(NOW - minutes_ago * 60).strftime("%Y-%m-%dT%H:%M:%S"), "to": to, "from": "x", "body": "[틱]"}
    if wake_at is not _ABSENT:
        r["wake_at"] = wake_at
    return json.dumps(r, ensure_ascii=False)


def pending(tmp: Path, rows: list[str]) -> dict[str, list[float]]:
    comm = tmp / "comm"
    comm.mkdir(exist_ok=True)
    _ = (comm / "mailbox.jsonl").write_text("".join(r + "\n" for r in rows), encoding="utf-8")
    code = "import json,sys; import ft_stall_detect as d; print(json.dumps(d.pending_mail(__import__('pathlib').Path(sys.argv[1]), float(sys.argv[2]))))"
    r = subprocess.run([sys.executable, "-c", code, str(comm), str(NOW)], cwd=BIN, env=os.environ | {"PYTHONPATH": str(BIN)}, capture_output=True, text=True, timeout=30)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


# ── ① 묶인 행만 → 좌석 없음 (기준판 Red = 있음) ──────────────────────────────
def test_1_batched_only_seat_absent(tmp_path: Path) -> None:
    assert X not in pending(tmp_path, [row(10, 5, NOW + 600)])


# ── ② 칸 없는 행 + 묶인 오래된 행 → 안 묶인 행만으로 (12 · 4분) ──────────────
def test_2_mixed_uses_unbatched_row_only(tmp_path: Path) -> None:
    out = pending(tmp_path, [row(10, 9, NOW + 600), row(12, 4)])
    assert out[X][0] == 12 and abs(out[X][1] - 4.0) < 0.05, out


# ── ③ 경계: 엄격한 하한 · 포함 상한 ─────────────────────────────────────────
@pytest.mark.parametrize(("delta", "counted"), [(-1, True), (0, True), (1, False), (3600, False), (3601, True)],
                         ids=["now-1", "now", "now+1", "now+3600", "now+3601"])
def test_3_bounds(tmp_path: Path, delta: int, counted: bool) -> None:
    assert (X in pending(tmp_path, [row(10, 5, NOW + delta)])) is counted


# ── ④ 정수 아닌 값은 센다 ───────────────────────────────────────────────────
@pytest.mark.parametrize("wake_at", ["x", NOW + 600.5, None], ids=["글자", "소수", "null"])
def test_4_non_integer_counted(tmp_path: Path, wake_at: object) -> None:
    assert pending(tmp_path, [row(10, 5, wake_at)])[X][0] == 10


# ── ⑤ Scan.find 대역: 팀장 아닌 유휴 5분 좌석 ───────────────────────────────
def _scan(w: World) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["bash", str(BIN / "ft-stall-scan.sh")], env=w.env, capture_output=True, text=True, timeout=60)


@pytest.mark.parametrize(("wake_at", "d"), [(NOW + 600, "0"), (_ABSENT, "1")], ids=["묶인 행만", "칸 없는 행"])
def test_5_scan_find_d(tmp_path: Path, wake_at: object, d: str) -> None:
    w = World(tmp_path)
    w.raw_mail(row(10, 5, wake_at))
    w.state(X, "IDLE", 5)
    r = _scan(w)
    assert r.returncode == 0, r.stderr
    assert counts(r.stdout)["d"] == d, r.stdout
    assert len([x for x in w.mbox_log() if x.startswith(f"ring|{X}")]) == int(d), w.mbox_log()
