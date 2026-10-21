"""r639 우편함 거의 참 감시 — 송신 상한 초과·실패에도 서명을 남겨 같은 알림 반복 0 · 죽은 좌석은 하네스 master 에 1통.

픽스처 = 임시 루트(.fable-team/ 명부 2개 + 가짜 mbox(지연·실패 흉내) + 가짜 tmux 세션 목록) · 실 우편함·tmux 0.
ⓐ send 가 큐에 넣고 8초 걸림 → 틱 3회 1통 + 서명 + «송신 상한 초과 · 다음 재시도 30분 뒤» ⓑ send 즉시 rc≠0 → 서명 + retry_at ·
30분 안 재시도 0 · 30분 뒤 1회 ⓒ 죽은 좌석 → 그 팀 master 0 · 하네스 master 1통 · 같은 서명 다시 0 ⓓ 살아 있는 좌석 = 그 팀 master
ⓔ 서명 파일 깨짐 = ERROR + 새로 시작 (ⓕ = 기존 test_r630_queue_full_watch.py 그대로)
"""
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
QW = HERE.parents[1] / "kit" / "fable-team" / "bin" / "ft_queue_watch.py"
V65M, NANO, DEAD = "byz-v65-master-claude#5", "byz-v65-nano-x#0", "byz-v65-arch-canon-claude#11"
HARNESS_M, HNANO = "byz-harness-master-claude#90", "byz-harness-nano-y#0"
NOW = 1_800_000_000.0
DEAD_BODY = f"[우편함 거의 참 · 죽은 좌석] {DEAD} 미읽음 8/10 — 명부 행 정리 대상"


@pytest.fixture
def root(tmp_path: Path) -> Path:
    ft = tmp_path / ".fable-team"
    (ft / "comm").mkdir(parents=True)
    fake = HERE / "_fake_mbox.sh"
    # 큐에 먼저 넣고(실제 송신은 들어감) FAKE_SLEEP 초 걸림 — exec 라 상한 초과 kill 이 sleep 까지 끝낸다
    (ft / "comm" / "mbox.sh").write_text(f'bash "{fake}" "$@" || exit $?\n[ -n "${{FAKE_SLEEP:-}}" ] && exec sleep "$FAKE_SLEEP"\nexit 0\n')
    (ft / "seats.json").write_text(json.dumps({"_master": V65M, V65M: {"role": "master"}, NANO: {"role": "nano"},
                                               DEAD: {"role": "arch-canon"}}), encoding="utf-8")
    (ft / "seats-harness.json").write_text(json.dumps({"_master": HARNESS_M, HARNESS_M: {"role": "master"},
                                                       HNANO: {"role": "nano"}}), encoding="utf-8")
    sessions(tmp_path, [V65M, NANO, DEAD, HARNESS_M, HNANO])
    return tmp_path


def sessions(root: Path, names: list[str] | None) -> None:
    """가짜 tmux(PATH 앞 · 틱 FT_TICK_PATH_FIRST 와 같은 꼴) — list-panes 에 names 출력 · None = 목록 못 읽음(rc 1)."""
    out = "\n".join(names or [])
    body = f"cat <<'EOF'\n{out}\nEOF\n" if names is not None else "echo 'no server running' >&2; exit 1\n"
    (root / "bin").mkdir(exist_ok=True)
    (root / "bin" / "tmux").write_text("#!/bin/bash\n" + body)
    (root / "bin" / "tmux").chmod(0o755)


def fill(root: Path, to: str, n: int, first: int = 1) -> None:
    q = root / ".fable-team" / "comm" / "mailbox.jsonl"
    keep = [r for r in rows(root) if r["to"] != to]
    keep += [{"seq": first + i, "to": to, "from": "x", "body": "b"} for i in range(n)]
    q.write_text("".join(json.dumps(r) + "\n" for r in keep), encoding="utf-8")


def rows(root: Path) -> list[dict]:
    q = root / ".fable-team" / "comm" / "mailbox.jsonl"
    return [json.loads(ln) for ln in q.read_text(encoding="utf-8").splitlines() if ln.strip()] if q.exists() else []


def alerts(root: Path, to: str) -> list[str]:
    return [r["body"] for r in rows(root) if r["to"] == to and "[우편함 거의 참" in r["body"]]


def state(root: Path) -> dict:
    return json.loads((root / ".fable-team" / "state" / "queue-watch.json").read_text(encoding="utf-8"))


def scan(root: Path, now: float = NOW, **env: str) -> subprocess.CompletedProcess:
    ft = root / ".fable-team"
    e = {**os.environ, "FAKE_MBOX": str(ft / "comm" / "mbox.sh"), "PATH": f"{root / 'bin'}:{os.environ['PATH']}",
         "FT_NOW": str(now), "FT_QUEUE_WATCH_TIMEOUT": "1", **env}
    return subprocess.run([sys.executable, str(QW), "scan", "--mbox", str(ft / "comm" / "mbox.sh"), "--rosters", str(ft),
                           "--state", str(ft / "state" / "queue-watch.json")], capture_output=True, text=True, timeout=60, env=e)


def test_a_send_over_limit_but_queued_alerts_once_and_keeps_signature(root: Path):
    fill(root, NANO, 8)
    outs = [scan(root, NOW + i * 100, FAKE_SLEEP="8") for i in range(3)]
    assert all(r.returncode == 0 for r in outs), outs[-1].stderr
    assert len(alerts(root, V65M)) == 1, alerts(root, V65M)  # 지금 판 = 3통
    assert "송신 상한 초과 · 다음 재시도 30분 뒤" in outs[0].stdout, outs[0].stdout
    assert state(root)[NANO]["sig"] == [8, 1] and state(root)[NANO]["retry_at"] == NOW + 1800


def test_b_send_fails_retries_once_after_30_minutes(root: Path):
    fill(root, NANO, 8)
    r = scan(root, NOW, FAKE_FAIL_TO=V65M)
    assert "ERROR" in r.stdout and state(root)[NANO] == {"sig": [8, 1], "sent": False, "retry_at": NOW + 1800}
    scan(root, NOW + 1799)  # 30분 안 — 송신이 살아나도 재시도 0
    assert alerts(root, V65M) == []
    scan(root, NOW + 1800)  # 30분 뒤 1회
    assert len(alerts(root, V65M)) == 1 and state(root)[NANO]["sent"] is True
    scan(root, NOW + 9000)
    assert len(alerts(root, V65M)) == 1


def test_b2_retry_also_fails_gives_up_until_signature_changes(root: Path):
    fill(root, NANO, 8)
    scan(root, NOW, FAKE_FAIL_TO=V65M)
    r = scan(root, NOW + 1800, FAKE_FAIL_TO=V65M)
    assert "ERROR" in r.stdout and state(root)[NANO]["retry_at"] is None
    scan(root, NOW + 9000)
    assert alerts(root, V65M) == []  # 재시도는 1회만
    fill(root, NANO, 9)
    scan(root, NOW + 9100)
    assert len(alerts(root, V65M)) == 1  # 서명이 바뀌면 다시 알림


def test_c_dead_seat_alerts_harness_master_once_not_its_team(root: Path):
    sessions(root, [V65M, NANO, HARNESS_M])
    fill(root, DEAD, 8)
    for i in range(3):
        assert scan(root, NOW + i * 100).returncode == 0
    assert alerts(root, V65M) == []
    assert alerts(root, HARNESS_M) == [DEAD_BODY]


def test_d_live_seat_alerts_its_team_master(root: Path):
    fill(root, DEAD, 8)  # 세션 있음 = 살아 있음
    scan(root)
    assert len(alerts(root, V65M)) == 1 and alerts(root, HARNESS_M) == []


def test_d2_unreadable_tmux_list_treats_seats_as_alive(root: Path):
    sessions(root, None)
    fill(root, DEAD, 8)
    scan(root)
    assert len(alerts(root, V65M)) == 1 and alerts(root, HARNESS_M) == []


def test_e_broken_state_file_errors_and_starts_fresh(root: Path):
    st = root / ".fable-team" / "state" / "queue-watch.json"
    st.parent.mkdir(parents=True)
    st.write_text("{깨짐", encoding="utf-8")
    fill(root, NANO, 8)
    r = scan(root)
    assert r.returncode == 0 and "ERROR 서명 파일 깨짐" in r.stdout
    assert len(alerts(root, V65M)) == 1 and state(root)[NANO]["sig"] == [8, 1]


def test_e2_old_list_signature_from_live_state_is_kept(root: Path):
    st = root / ".fable-team" / "state" / "queue-watch.json"
    st.parent.mkdir(parents=True)
    st.write_text(json.dumps({NANO: [8, 1]}), encoding="utf-8")  # 1.1.172 판 서명 꼴
    fill(root, NANO, 8)
    scan(root)
    assert alerts(root, V65M) == []  # 이미 알린 서명 — 판 교체로 다시 보내지 않음
