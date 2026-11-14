"""r1949 — 쉼 머리 규칙 한 함수(rest_head): 머리 «[정리]»·«[다음 없음]»·«막힘 = 사람 답(» 어느 꼴이든
첫 줄 쉼 표식이면 r1729 쉼 면제와 r1647 닫기 대기가 같은 규칙으로 판정한다 · 승격 꼴([HIL] + «(원래 [정리])») 보존.
R1949_BIN = 시험할 bin 폴더(기본 kit) — 변이 사본(M1~M4)을 넣어 반대 결과를 대조한다.
"""
import os
import subprocess
from pathlib import Path

import pytest

from _stall_world import World, counts
from real_state_guard import guard_begin_module  # noqa: F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

BIN = Path(os.environ.get("R1949_BIN") or Path(__file__).resolve().parents[2] / "kit/fable-team/bin")
CFO = "[다음 없음] 막힘 = 사람 답(1794632106.348429) — 결정 기다림\n한 일 0\n[정리] 변화 0"
HEAD_REST = "[정리] [다음 없음] 한 일 3줄"
PROMOTED = "[HIL] 막힘 보고 · [다음 없음] (원래 [정리])"


@pytest.fixture
def w(tmp_path: Path) -> World:
    return World(tmp_path)


def candidate(w: World) -> None:
    """팀장을 b 후보(경보 후보)로 세우고 다른 좌석은 WORKING — u 칸이 이 카드 판정을 가리지 않게."""
    for seat in ("planner#1", "t1-nano#0"):
        w.state(seat, "WORKING", 0.1)
    w.state("t1-master#1", "IDLE", 5)
    w.jsonl("t1-master#1", "확인했습니다. 지금 착수하겠습니다")


def scan(w: World) -> dict[str, str]:
    r = subprocess.run(["bash", str(BIN / "ft-stall-scan.sh")], env=w.env, capture_output=True, text=True, timeout=70)
    assert r.returncode == 0, r.stderr
    return counts(r.stdout) | {"out": r.stdout}


def sends(w: World) -> list[str]:
    return [x for x in w.mbox_log() if x.startswith("send|t1-master#1|")]


# ── ①②⑦ 쉼 머리 어느 꼴이든 · 사건 0 · 33분 = [멈춤] 0통 ──────────────────────
@pytest.mark.parametrize("body", [CFO, HEAD_REST, PROMOTED], ids=["① [다음 없음] 머리", "② [정리] [다음 없음] 회귀", "⑦ 승격 꼴 회귀"])
def test_rest_head_any_form_is_exempt(w: World, body: str) -> None:
    candidate(w)
    w.heartbeat("t1-master#1", 33, body=body)
    c = scan(w)
    assert c["f"] == "0" and c["u"] == "0", c
    assert not sends(w), w.mbox_log()


def test_r3_event_after_rest_head_alerts(w: World) -> None:  # ③ 그 뒤 사건 1통 · 21분 = A2 그대로
    candidate(w)
    w.heartbeat("t1-master#1", 40, body="[다음 없음] 막힘 = 사람 답(1794632106.348429)")
    w.mail("t1-nano#0", 950, 21, frm="t1-master#1", body="발주 — 이어서 하세요")
    assert scan(w)["f"] == "1"
    assert len(sends(w)) == 1


def test_r4_mark_on_second_line_only_is_not_rest(w: World) -> None:  # ④ 둘째 줄 표식 = 쉼 0
    candidate(w)
    w.heartbeat("t1-master#1", 33, body="[정리] 한 일 3줄\n[다음 없음]")
    assert scan(w)["f"] == "1"
    assert len(sends(w)) == 1


def test_r5_rest_head_to_non_lead_role_is_not_heartbeat(w: World) -> None:  # ⑤ 받는이 = nano → 심박 아님
    candidate(w)
    w.heartbeat("t1-master#1", 33, to="t1-nano#0", body=CFO)
    assert scan(w)["f"] == "1"
    assert len(sends(w)) == 1


def test_r6_closed_wait_uses_rest_head(w: World) -> None:  # ⑥ 마지막 발신 «[정리] [다음 없음]» + 받을 일 0 → 닫기 대기
    """심박([정리]) 25분 = 경보 후보 · 쉼 머리 쪽지는 nano 앞(심박 아님 = r1729 면제 0) → r1647 닫기 대기만 남는다."""
    candidate(w)
    w.heartbeat("t1-master#1", 25)
    w.mail("t1-nano#0", 950, 21, frm="t1-master#1", body=HEAD_REST)
    (w.root / "design/t1/indices/진행").mkdir(parents=True, exist_ok=True)  # open-work rc0(받을 일 0)
    c = scan(w)
    assert c["f"] == "0", c
    assert "보류 f t1 — [다음 없음] · 받을 일 0" in c["out"], c["out"]
    assert not sends(w), w.mbox_log()


def test_bin_and_kit_same_bytes() -> None:
    harness = Path(__file__).resolve().parents[2]
    for name in ("ft_stall_detect.py", "ft_stall_scan.py"):
        assert (harness / "bin" / name).read_bytes() == (harness / "kit/fable-team/bin" / name).read_bytes(), name
