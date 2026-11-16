"""r2139 — [정리] 머리 글의 둘째 줄부터 «[다음 없음]» 만 있는 단독 줄도 쉼 표식(rest_head 참).

R1 단독 줄 인정(첫 줄 머리 [정리] ∧ 앞뒤 공백 뺀 값 = «[다음 없음]» 인 줄) · R2 문장 속·다른 머리 = 인정 0.
R2139_BIN = 시험할 bin 폴더(기본 kit) — 변이 사본(M1·M2)을 넣어 반대 결과를 대조한다.
"""
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

from _stall_world import World, counts
from real_state_guard import guard_begin_module  # noqa: F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

BIN = Path(os.environ.get("R2139_BIN") or Path(__file__).resolve().parents[2] / "kit/fable-team/bin")
TIDY = "[정리] 카드 대기 0 · 진행 0 · 다음 수: 없음\n골좌표: 7 — 하네스 운영 정리\n#322040 뒤 받은 일 0 · 닫기 대기\n"
CASE1 = TIDY + "[다음 없음]"  # #322126 본문 꼴


def rest_head(body: str) -> bool:
    code = "import json,sys; import ft_stall_detect as d; print(json.dumps(d.rest_head(json.loads(sys.argv[1]))))"
    r = subprocess.run([sys.executable, "-c", code, json.dumps(body)], cwd=BIN, env=os.environ | {"PYTHONPATH": str(BIN)}, capture_output=True, text=True, timeout=30)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


# ── ①② R1 단독 줄 = 쉼 ─────────────────────────────────────────────────────
@pytest.mark.parametrize("body", [CASE1, TIDY + "  [다음 없음]  "], ids=["① 끝 줄 단독", "② 앞뒤 공백"])
def test_r1_own_line_mark_is_rest(body: str) -> None:
    assert rest_head(body) is True


# ── ④⑤ R2 문장 속 · 다른 머리 = 쉼 0 ────────────────────────────────────────
@pytest.mark.parametrize("body", [TIDY + "[다음 없음] 아님 — 카드 1 남음", TIDY + "설명: [다음 없음] 표식은 끝에", "[완료] desk 틱 카드 1 닫음\n[다음 없음]"], ids=["④ 부정 문장", "④ 설명 문장", "⑤ [완료] 머리"])
def test_r2_mark_in_sentence_or_other_head_is_not_rest(body: str) -> None:
    assert rest_head(body) is False


# ── ③ closed_wait: 마지막 발신 = ① 본문(nano 앞) + 받을 일 0 → 닫기 대기 ──────────
def test_r3_closed_wait_with_own_line_mark(tmp_path: Path) -> None:
    w = World(tmp_path)
    for seat in ("planner#1", "t1-nano#0"):
        w.state(seat, "WORKING", 0.1)
    w.state("t1-master#1", "IDLE", 5)
    w.jsonl("t1-master#1", "확인했습니다. 지금 착수하겠습니다")
    w.heartbeat("t1-master#1", 25)
    w.mail("t1-nano#0", 950, 21, frm="t1-master#1", body=CASE1)
    (w.root / "design/t1/indices/진행").mkdir(parents=True, exist_ok=True)  # open-work rc0(받을 일 0)
    r = subprocess.run(["bash", str(BIN / "ft-stall-scan.sh")], env=w.env, capture_output=True, text=True, timeout=70)
    assert r.returncode == 0, r.stderr
    assert counts(r.stdout)["f"] == "0", r.stdout
    assert r.stdout.count("보류 f t1 — [다음 없음] · 받을 일 0") == 1, r.stdout
    assert not [x for x in w.mbox_log() if x.startswith("send|t1-master#1|")], w.mbox_log()
