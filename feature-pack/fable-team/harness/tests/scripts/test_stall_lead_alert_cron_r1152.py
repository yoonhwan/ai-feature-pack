"""r1152 — 팀장 심박 [멈춤](f) 쪽지가 «정리 1통» 에 더해 체크 크론 다시 걸기 단계를 같은 쪽지에 싣는다.

심박이 끊기는 가장 흔한 원인 = 세션 종속 크론 소실(BOOT 16). b 경보(선언 뒤 정지) 문구는 그대로.
R1152_BIN = 시험할 bin 폴더(기본 kit · 변이 사본을 넣어 R1 FAIL 을 본다). 자기 재호출 0.
"""
import filecmp
import os
import subprocess
from pathlib import Path

import pytest

from _stall_world import World, counts
from real_state_guard import guard_begin_module  # noqa: F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

HARNESS = Path(__file__).resolve().parents[2]
BIN = Path(os.environ.get("R1152_BIN") or HARNESS / "kit/fable-team/bin")


@pytest.fixture
def w(tmp_path: Path) -> World:
    return World(tmp_path)


def scan(w: World) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["bash", str(BIN / "ft-stall-scan.sh")], env=w.env, capture_output=True, text=True, timeout=60)


def bodies(w: World, to: str) -> list[str]:
    return [r.split("|")[4] for r in w.mbox_log() if r.startswith(f"send|{to}|")]


def lead_b_candidate(w: World) -> None:
    w.state("t1-master#1", "IDLE", 5)
    w.jsonl("t1-master#1", "확인했습니다. 지금 착수하겠습니다")


def f_body(w: World) -> str:
    r = scan(w)
    assert r.returncode == 0, r.stderr
    assert counts(r.stdout)["f"] == "1", r.stdout
    s = bodies(w, "t1-master#1")
    assert len(s) == 1, w.mbox_log()
    return s[0]


# ── R1 — 심박 끊김(f) 쪽지 1통 = 정리 1통 + CronCreate + cron=<id> ───────────────
def test_r1_stale_heartbeat_notice_has_cron_rearm(w: World) -> None:  # ⓐ
    lead_b_candidate(w)
    w.heartbeat("t1-master#1", 16)
    body = f_body(w)
    assert body.startswith("[멈춤] t1-master#1 팀장 심박 16분"), body
    for word in ("정리 1통", "CronCreate", "cron=<id>"):
        assert word in body, (word, body)


def test_r1_no_heartbeat_notice_has_cron_rearm(w: World) -> None:  # ⓐ 심박을 한 번도 안 보냄(cfo#120 꼴)
    lead_b_candidate(w)
    w.mail("planner#1", 3, 20, frm="t1-master#1", body="[정지 레디] 끝")
    body = f_body(w)
    assert "심박 없음" in body and "CronCreate" in body and "cron=<id>" in body, body


# ── R1b — 같은 쪽지에 CronList + 주기 어긋남(10분이 아니면) 단계 ──────────────────
def test_r1b_notice_checks_cron_list_and_period(w: World) -> None:
    lead_b_candidate(w)
    w.heartbeat("t1-master#1", 30)
    body = f_body(w)
    assert "CronList" in body and "10분이 아니면" in body and "10분 틱" in body, body
    assert body.index("CronList") < body.index("CronCreate"), body


# ── R2 — b 경보(팀장 아닌 좌석 선언 뒤 정지) 문구 그대로 · 크론 글자 0 ─────────────
def test_r2_b_notice_unchanged_no_cron_words(w: World) -> None:  # ⓑ
    w.heartbeat("t1-master#1", 1)
    w.state("t1-nano#0", "IDLE", 4)
    w.jsonl("t1-nano#0", "지금 착수하겠습니다")
    r = scan(w)
    assert r.returncode == 0, r.stderr
    assert counts(r.stdout)["b"] == "1" and counts(r.stdout)["f"] == "0", r.stdout
    s = bodies(w, "t1-nano#0")
    assert s == ["[stall b] 선언 뒤 정지 4분 — 지금 도구를 불러라 (ft-stall-scan)"], w.mbox_log()


# ── ③ bin·kit 같은 내용 ────────────────────────────────────────────────────
def test_bin_and_kit_same_content() -> None:  # ⓒ
    a, b = HARNESS / "bin/ft_stall_scan.py", HARNESS / "kit/fable-team/bin/ft_stall_scan.py"
    assert filecmp.cmp(a, b, shallow=False), (a, b)
