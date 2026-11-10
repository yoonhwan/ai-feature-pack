"""r1148 ft_decision_kind — mbox_guard 승격분(첫 줄 끝 «(원래 [정리])» · r1098)은 머리가 [HIL] 이어도 통보 · 진짜 질문은 그대로.
반례 R1~R5(카드 동결). 임시 FT_ROOT·가짜 인박스만(실 우편함 0) — 임시 루트는 test_decision_count.make_env 그대로."""
import filecmp
import sys

import pytest
from test_decision_count import BIN, ROOT, make_env, put, row, run

sys.path.insert(0, str(BIN))
from ft_decision_kind import kind  # noqa: E402

G = "byz-graphics-master-claude#3"
R1 = "[HIL] 틱 정리 — 열린 오빠 질문 0 (원래 [정리])"
R2 = "[HIL] 정리 — 오빠 아이폰 요청 desk 에 올림 (원래 [정리])"
R3 = "[HIL] 결정 1개 — ①예 ②아니오"
R4 = "[긴급] 예/아니오?"
R5 = "[HIL] 결정 — 지난 쪽지 «(원래 [정리])» 꼬리 처리 ①유지 ②삭제"


@pytest.fixture
def env(tmp_path):
    return make_env(tmp_path)


@pytest.mark.parametrize("first", [R1, R2, R1 + "  "])
def test_a_promoted_heartbeat_is_notice(first):
    assert kind(first, 40) == "통보"


@pytest.mark.parametrize("first", [R3, R4, R5])
def test_b_real_question_stays_question(first):
    assert kind(first, 40) == "질문표식"


def test_a_decision_count_team_wait_zero_for_promoted(env):
    put(env, [row(1, "④", G, ago=40, body=R1), row(2, "④", G, ago=40, body=R2)])
    out = run(env).stdout
    assert out.startswith("결정 인터뷰 0건") and "팀 대기 0건" in out, out


def test_b_decision_count_direct_hil_still_waits(env):
    put(env, [row(1, "④", G, ago=40, body=R1), row(3, "④", G, ago=40, body=R3)])
    assert "팀 대기 1건(가장 오래 byz-graphics-master-claude#3 40분)" in run(env).stdout


def test_c_bin_and_kit_same():
    assert filecmp.cmp(BIN / "ft_decision_kind.py", ROOT / "harness/kit/fable-team/bin/ft_decision_kind.py", shallow=False)
