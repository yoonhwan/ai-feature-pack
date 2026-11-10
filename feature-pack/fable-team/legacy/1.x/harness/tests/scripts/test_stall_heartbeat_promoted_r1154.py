"""r1154 — mbox_guard 승격분(머리 [HIL] · 첫 줄 끝 «(원래 [정리])» · r1098)도 팀장 심박으로 센다.

판정 정규식은 ft_decision_kind.PROMOTED(r1148) 한 벌을 같이 쓴다. 직접 보낸 [HIL] 질문·표식이 첫 줄 끝이 아닌 쪽지는 심박 아님.
R1154_BIN = 시험할 bin 폴더(기본 kit · 변이 사본을 넣어 R1 FAIL 을 본다). 자기 재호출 0.
"""
import os
import subprocess
import sys
from pathlib import Path

import pytest

from _stall_world import NOW, World, counts
from real_state_guard import guard_begin_module  # noqa: F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

BIN = Path(os.environ.get("R1154_BIN") or Path(__file__).resolve().parents[2] / "kit/fable-team/bin")
sys.path.insert(0, str(BIN))
from ft_stall_detect import lead_alert  # noqa: E402

PROMOTED_TICK = "[HIL] 틱 05:23 — ①새 쪽지 0 ②로컬 서비스 0 ③오빠 결정(A/B) 대기 (원래 [정리])"


@pytest.fixture
def w(tmp_path: Path) -> World:
    return World(tmp_path)


def scan(w: World) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["bash", str(BIN / "ft-stall-scan.sh")], env=w.env, capture_output=True, text=True, timeout=60)


def sends(w: World, to: str) -> list[str]:
    return [r for r in w.mbox_log() if r.startswith(f"send|{to}|")]


def lead_b_candidate(w: World) -> None:
    w.state("t1-master#1", "IDLE", 5)
    w.jsonl("t1-master#1", "확인했습니다. 지금 착수하겠습니다")


def lead_f(w: World, body: str) -> str:
    lead_b_candidate(w)
    w.heartbeat("t1-master#1", 5, body=body)
    r = scan(w)
    assert r.returncode == 0, r.stderr
    return counts(r.stdout)["f"]


# ── R1 — 승격분 «[HIL] 틱 … (원래 [정리])» 5분 전 = 경보 0 ─────────────────────
def test_r1_promoted_heartbeat_is_fresh(w: World) -> None:  # ⓐ 판정 함수 값
    w.heartbeat("t1-master#1", 5, body=PROMOTED_TICK + "\n둘째 줄")
    alert, age, undec = lead_alert(w.root, w.root / ".fable-team/comm", "t1-master#1", NOW)
    assert (alert, undec) == (False, False) and age is not None and round(age) == 5


def test_r1_scan_promoted_heartbeat_no_stall(w: World) -> None:  # ⓐ scan f 수
    assert lead_f(w, PROMOTED_TICK) == "0"
    assert not sends(w, "t1-master#1")


# ── R2 — 머리 [정리] 5분 전 = 경보 0(지금 그대로) ─────────────────────────────
def test_r2_plain_heartbeat_still_fresh(w: World) -> None:
    assert lead_f(w, "[정리] 한 일 3줄") == "0"


# ── R3 — 표식 없는 [HIL] 결정 질문 = 심박 아님 = 경보 1 ────────────────────────
def test_r3_direct_hil_question_is_not_heartbeat(w: World) -> None:
    assert lead_f(w, "[HIL] 결정 1개 — ①A안 ②B안") == "1"
    assert len(sends(w, "t1-master#1")) == 1


# ── R4 — 표식이 첫 줄 끝이 아님(본문 중간·둘째 줄) = 심박 아님 ───────────────────
@pytest.mark.parametrize("body", [
    "[HIL] (원래 [정리]) 결정 ①A ②B",
    "[HIL] 결정 1개 — ①A ②B\n지난 틱 (원래 [정리])",
])
def test_r4_marker_not_at_first_line_end(w: World, body: str) -> None:
    assert lead_f(w, body) == "1"
