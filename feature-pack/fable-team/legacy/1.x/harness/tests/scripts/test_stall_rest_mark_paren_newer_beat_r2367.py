"""r2367 — 쉼 표식(«[다음 없음]»)은 첫 줄 «괄호 밖» 에서 시작한 것만 세고, 쉼 면제 갈래는
마지막 심박이 쉼 심박일 때만 탄다 · 더 새 보통 심박이 있으면 유휴 면제·나이 판정을 그대로 쓴다.

계약: K1 첫 줄 표식 = 괄호 밖만(ASCII «( )» 깊이 0 · 짝 없는 «)» 는 무시 = 깊이 하한 0 · 닫히지 않은 «(» 뒤는 괄호 속)
      K2 쉼 갈래 = 쉼 심박 ts ≥ 마지막 심박 ts 일 때만 · 더 새 보통 심박이 있으면 다음 갈래 그대로
      K3 다른 길(20분 임계 · 쉼 상한 240분 · A1 · A2 · L3 유휴 면제 · 승격 꼴 · 머리 꼴) 그대로
반례 ①~⑪ · 변이 M1~M6 은 R2367_BIN 사본으로 대조한다(기본 = kit).
실사건 = 2026-11-21 ft-stall-scan → feature master-pi#86 [멈춤] 3통(140 · 163 · 173분).
"""
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

from _stall_world import NOW, World
from real_state_guard import guard_begin_module  # noqa: F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

BIN = Path(os.environ.get("R2367_BIN") or Path(__file__).resolve().parents[2] / "kit/fable-team/bin")
LEAD = "t1-master#1"
REST = "[정리] 한 일 3줄 · [다음 없음]"
# ① 실사건 #358014 첫 줄 글자 그대로 — 괄호 속 «arch#18 [다음 없음]» 인용 하나뿐(끝은 승격 표식)
QUOTED = (
    "[HIL] 카드 대기 4(선행) · 진행 2(9756 오빠 답 · w5 는 9756 뒤) · 유휴 좌석 1(arch#18 [다음 없음])"
    " · 다음 수: 9756 오빠 approve-merge 답 → planner 착지 → arch#18 정본 반영 → w5 새 holder (원래 [정리])"
)
# ④ I1 — 괄호 속 인용 «뒤» 에 진짜 표식이 또 있다 = 참
QUOTED_THEN_MARK = "[정리] 카드 대기 4 · 유휴 좌석 1(arch#18 [다음 없음]) · [다음 없음]"
# ⑤ I2 — 앞에 짝 없는 «)» 가 있어도 깊이는 0 아래로 안 내려간다 = 참
STRAY_CLOSE = "[정리] 1) 한 일 2) 정리 · [다음 없음]"
# ③ 닫히지 않은 «(» 뒤 = 괄호 속 = 거짓
UNCLOSED = "[정리] 한 일 (메모 [다음 없음]"
# ② 지금과 같은 참이어야 하는 머리 꼴 6가지
HEADS = [
    REST,
    "[HIL] 막힘 보고 · [다음 없음] (원래 [정리])",
    "[다음 없음] 막힘 = 사람 답(1794632106.348429)",
    "[정리] 한 일 3줄 · 막힘 = 사람 답(1794445218.408129)",
    "[정리] 한 일(3줄) · [다음 없음]",
    "[정리] [다음 없음] 한 일 3줄",
]
# ⑦ 실사건 시각표 — 기준 «지금»(NOW) = 02:07:47 · 값 = 그 시각부터 몇 분 뒤(음수 = 기준보다 뒤 = 미래)
T_EVENT = 5.383  # 02:13:10 desk 사건
T_HB = (40.217, 75.217, 112.2, 145.717)  # 02:48 · 03:23 · 03:59:59 · 04:33:30 보통 심박
NOW_ALERTS = (145.333, 168.5, 179.267)  # 04:33:07 · 04:56:17 · 05:07:03


def _run(code: str, *args: str) -> str:
    r = subprocess.run(
        [sys.executable, "-c", code, *args],
        cwd=BIN,
        env=os.environ | {"PYTHONPATH": str(BIN)},
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert r.returncode == 0, r.stderr
    return r.stdout


def rest_head(body: str) -> bool:
    code = "import json,sys; import ft_stall_detect as d; print(json.dumps(d.rest_head(json.loads(sys.argv[1]))))"
    return json.loads(_run(code, json.dumps(body)))


def lead_alert(root: Path, now: float) -> tuple[bool, float | None, bool]:
    code = (
        "import json,sys; from pathlib import Path; import ft_stall_detect as d;"
        " r=Path(sys.argv[1]); print(json.dumps(d.lead_alert(r, r/'.fable-team/comm', sys.argv[3], float(sys.argv[2]))))"
    )
    alert, age, undec = json.loads(_run(code, str(root), repr(now), LEAD))
    return alert, age, undec


def after(w: World, minutes: float, to: str, seq: int, frm: str, body: str) -> None:
    """기준 «지금»(NOW) 보다 minutes 분 «뒤» 에 온 쪽지 — minutes 음수 = 기준 이전."""
    w.mail(to, seq, -minutes, frm=frm, body=body)


# ── ① 괄호 속 인용은 쉼 표식이 아니다(기준판 = 참 → Red) ─────────────────────────
def test_1_quoted_mark_in_parens_is_not_rest() -> None:
    assert rest_head(QUOTED) is False


# ── ② 머리 꼴 6가지 = 지금과 같은 참 ────────────────────────────────────────────
@pytest.mark.parametrize("body", HEADS, ids=[f"②-{i}" for i in range(6)])
def test_2_head_forms_stay_true(body: str) -> None:
    assert rest_head(body) is True


# ── ③ 닫히지 않은 «(» 뒤 = 괄호 속 ─────────────────────────────────────────────
def test_3_unclosed_paren_is_not_rest() -> None:
    assert rest_head(UNCLOSED) is False


# ── ④ I1 괄호 속 인용 뒤 괄호 밖 표식 = 참 ──────────────────────────────────────
def test_4_mark_after_quoted_mark_is_rest() -> None:
    assert rest_head(QUOTED_THEN_MARK) is True


# ── ⑤ I2 짝 없는 «)» 는 깊이 하한 0(무시) ───────────────────────────────────────
def test_5_stray_close_paren_keeps_depth_floor() -> None:
    assert rest_head(STRAY_CLOSE) is True


# ── ⑥ 쉼 심박 뒤 더 새 보통 심박 · 일 쪽지 0 = 유휴 면제(기준판 = 나이 140분 경보 → Red) ──
def test_6_newer_beat_beats_rest_branch(tmp_path: Path) -> None:
    w = World(tmp_path)
    w.heartbeat(LEAD, 146, body=REST)  # 쉼 심박(02:07)
    w.mail(LEAD, 951, 140, frm="planner-desk#229", body="[완료] 판정 4431 · 좌석 닫기")  # 02:13 사건
    w.heartbeat(LEAD, 34.1)  # 03:59 보통 심박 — 쉼보다 새롭다
    alert, age, undec = lead_alert(w.root, NOW)
    assert (alert, undec) == (False, False)
    assert age == pytest.approx(34.1, abs=0.05)


# ── ⑦ 실사건 재현: 그 시각까지 자른 기록 · 세 시각 모두 경보 0(기준판 = 경보 → Red) ──────
@pytest.mark.parametrize("now_after", NOW_ALERTS, ids=["⑦-04:33:07", "⑦-04:56:17", "⑦-05:07:03"])
def test_7_real_incident_three_times(tmp_path: Path, now_after: float) -> None:
    w = World(tmp_path)
    w.heartbeat(LEAD, 0, body=QUOTED)  # 02:07:47 #358014
    after(w, T_EVENT, LEAD, 951, "planner-desk#229", "[완료] 판정 4431 · 좌석 닫기")  # 02:13:10 #358051
    for i, t in enumerate(T_HB):
        if t <= now_after:
            after(w, t, LEAD, 960 + i, LEAD, "[정리] 한 일 3줄")
    alert, age, undec = lead_alert(w.root, NOW + now_after * 60)
    assert (alert, undec) == (False, False), (alert, age, undec)
    beat = max(t for t in T_HB if t <= now_after)
    assert age == pytest.approx(now_after - beat, abs=0.05)


# ── ⑧ 쉼 심박이 마지막 심박 · 그 뒤 사건 0 = 경보 0 · 나이 90(A1 그대로) ──────────────
def test_8_rest_is_last_beat_no_event(tmp_path: Path) -> None:
    w = World(tmp_path)
    w.heartbeat(LEAD, 90, body=REST)
    alert, age, undec = lead_alert(w.root, NOW)
    assert (alert, undec) == (False, False)
    assert age == pytest.approx(90, abs=0.05)


# ── ⑨ 쉼 심박이 마지막 심박 · 그 뒤 사건 1 = 경보 · 나이 30(A2 그대로) ───────────────
def test_9_rest_is_last_beat_with_event(tmp_path: Path) -> None:
    w = World(tmp_path)
    w.heartbeat(LEAD, 90, body=REST)
    w.mail(LEAD, 951, 30, frm="planner-desk#229", body="[완료] 판정 4431 · 좌석 닫기")
    alert, age, undec = lead_alert(w.root, NOW)
    assert (alert, undec) == (True, False)
    assert age == pytest.approx(30, abs=0.05)


# ── ⑩ 보통 심박만 · 그 뒤 일 쪽지 1 = 경보 · 나이 = 첫 일 쪽지부터(L3 그대로) ──────────
def test_10_idle_exempt_counts_from_first_work_mail(tmp_path: Path) -> None:
    w = World(tmp_path)
    w.heartbeat(LEAD, 50)
    w.mail(LEAD, 951, 25, frm="planner-desk#229", body="[완료] 판정 4431 · 좌석 틱")
    alert, age, undec = lead_alert(w.root, NOW)
    assert (alert, undec) == (True, False)
    assert age == pytest.approx(25, abs=0.05)


# ── ⑪ 둘째 줄 단독 표식은 그대로 쉼(r2139 그대로) ──────────────────────────────────
def test_11_own_line_mark_on_second_line_stays_rest() -> None:
    assert rest_head("[정리] 한 일 3줄\n[다음 없음]") is True
