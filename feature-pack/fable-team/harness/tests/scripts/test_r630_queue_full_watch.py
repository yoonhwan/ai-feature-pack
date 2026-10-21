"""r630 우편함 거의 참 경보 — 틱 큐 감시(모든 명부) · mbox 버림 원장 · 슬랙 수신 데몬 «가득 참» master 쪽지.

픽스처 = 임시 루트(.fable-team/ 명부 2개 + 가짜 mbox) · 실 우편함·실 슬랙·tmux 0.
ⓐ desk(planner 명부에만 있음) 미읽음 8 → planner `_master` 에 1통 ⓑ 같은 서명 재틱 0 · 건수 늘거나 가장 오래된 seq 바뀌면 1통
ⓒ 7건 이하 0 ⓓ 11건째 send → mailbox.drops.log 1줄 + 기존 stderr DROPPED ⓔ 슬랙 «가득 참» 미룸 → 그 좌석 팀 master 1통(항목당 1번)
ⓕ 명부 깨짐 → ERROR 1줄 · 다른 명부 감시는 계속 · 틱 rc 0
"""
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
from _slack_fakes import FakeSlack

HERE = Path(__file__).resolve().parent
HARNESS = HERE.parents[1]
TICK = HARNESS / "kit" / "fable-team" / "bin" / "ft-tick.sh"
QW = HARNESS / "kit" / "fable-team" / "bin" / "ft_queue_watch.py"
MBOX_PY = HARNESS / "comm" / "mbox.py"
INBOUND = HARNESS / "kit" / "slack-mirror" / "byz_slack_mbox_inbound.py"
DESK, PLANNER, V65M, NANO = "byz-planner-desk#34", "byz-planner-master-claude#9", "byz-v65-master-claude#5", "byz-v65-nano-x#0"
HUMAN = "U0AC2JF0M7D"


@pytest.fixture
def root(tmp_path: Path) -> Path:
    ft = tmp_path / ".fable-team"
    (ft / "comm").mkdir(parents=True)
    shutil.copy(HERE / "_fake_mbox.sh", ft / "comm" / "mbox.sh")
    (ft / "seats.json").write_text(json.dumps({"_master": V65M, V65M: {"role": "master"}, NANO: {"role": "nano"}}), encoding="utf-8")
    (ft / "seats-planner.json").write_text(json.dumps({"_master": PLANNER, PLANNER: {"role": "master"}, DESK: {"role": "desk"}}), encoding="utf-8")
    return tmp_path


def fill(root: Path, to: str, n: int, first: int = 1) -> None:
    q = root / ".fable-team" / "comm" / "mailbox.jsonl"
    keep = [r for r in rows(root) if r["to"] != to]
    keep += [{"seq": first + i, "to": to, "from": "x", "body": "b"} for i in range(n)]
    q.write_text("".join(json.dumps(r) + "\n" for r in keep), encoding="utf-8")


def rows(root: Path) -> list[dict]:
    q = root / ".fable-team" / "comm" / "mailbox.jsonl"
    return [json.loads(ln) for ln in q.read_text(encoding="utf-8").splitlines() if ln.strip()] if q.exists() else []


def alerts(root: Path, to: str) -> list[str]:
    return [r["body"] for r in rows(root) if r["to"] == to and "[우편함 거의 참]" in r["body"]]


def tick(root: Path) -> subprocess.CompletedProcess:
    """ft-tick.sh 의 queue_full_watch 함수만 떼어 돌린다(다른 감시·tmux 0)."""
    fn = re.search(r"^queue_full_watch\(\) \{.*?^\}", TICK.read_text(encoding="utf-8"), re.S | re.M)
    src = fn.group(0) if fn else "queue_full_watch() { echo 'NO queue_full_watch' >&2; return 0; }"
    ft = root / ".fable-team"
    script = (f'set -uo pipefail\nlog() {{ echo "$(date "+%F %T") $*"; }}\nDRY=0; HERE="{QW.parent}"; MBOX="{ft}/comm/mbox.sh"; '
              f'SEATS="{ft}/seats.json"\n{src}\nqueue_full_watch; echo "TICK_GOES_ON"')
    env = {**os.environ, "FAKE_MBOX": str(ft / "comm" / "mbox.sh")}
    return subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=30, env=env)


def test_a_desk_only_in_planner_roster_alerts_planner_master(root: Path):
    fill(root, DESK, 8)
    r = tick(root)
    assert r.returncode == 0, r.stderr
    assert alerts(root, PLANNER) == [f"[우편함 거의 참] {DESK} 미읽음 8/10 — 그 좌석이 recv 해야 함 · 넘치면 오래된 것부터 사라짐"]
    assert alerts(root, V65M) == []


def test_b_same_signature_no_resend_then_growth_or_new_oldest_resends(root: Path):
    fill(root, DESK, 8)
    tick(root)
    tick(root)
    assert len(alerts(root, PLANNER)) == 1  # 같은 좌석·같은 건수·같은 가장 오래된 seq
    fill(root, DESK, 9)
    tick(root)
    assert len(alerts(root, PLANNER)) == 2 and "미읽음 9/10" in alerts(root, PLANNER)[-1]  # 건수 늘어남
    fill(root, DESK, 9, first=50)
    tick(root)
    assert len(alerts(root, PLANNER)) == 3  # 가장 오래된 seq 바뀜(같은 건수)


def test_c_seven_or_less_is_silent(root: Path):
    fill(root, DESK, 7)
    fill(root, NANO, 3)
    r = tick(root)
    assert r.returncode == 0 and alerts(root, PLANNER) == [] and alerts(root, V65M) == []


def test_c2_nano_in_main_roster_alerts_its_team_master(root: Path):
    fill(root, NANO, 8)
    tick(root)
    assert len(alerts(root, V65M)) == 1 and alerts(root, PLANNER) == []


def test_f_broken_roster_errors_and_watch_of_others_goes_on(root: Path):
    (root / ".fable-team" / "seats.json").write_text("{깨짐", encoding="utf-8")
    fill(root, DESK, 8)
    r = tick(root)
    assert r.returncode == 0 and "TICK_GOES_ON" in r.stdout
    assert re.search(r"queue_full_watch: ERROR .*seats\.json", r.stderr), r.stderr
    assert len(alerts(root, PLANNER)) == 1  # 깨진 명부만 건너뜀 — 다른 명부 좌석은 계속 본다


def test_a2_tick_pass_calls_queue_full_watch_and_dry_run_sends_nothing(root: Path):
    body = re.search(r"^pass\(\) \{.*?^\}", TICK.read_text(encoding="utf-8"), re.S | re.M)
    assert body and re.search(r"^\s+queue_full_watch$", body.group(0), re.M)  # 매 루프 pass() 가 부른다
    fn = re.search(r"^queue_full_watch\(\) \{.*?^\}", TICK.read_text(encoding="utf-8"), re.S | re.M)
    assert fn
    fill(root, DESK, 8)
    r = subprocess.run(["bash", "-c", f"DRY=1\n{fn.group(0)}\nqueue_full_watch"], capture_output=True, text=True, timeout=30)
    assert r.stdout.strip() == "DRY kind=queue-full" and alerts(root, PLANNER) == []


def test_d_ring_drop_writes_drops_ledger_line(tmp_path: Path):
    env = {**os.environ, "FT_MBOX_DIR": str(tmp_path), "FT_MBOX_RELAY_DIR": str(tmp_path / "relay"), "FT_MBOX_RING": "10"}
    for i in range(11):
        r = subprocess.run([sys.executable, str(MBOX_PY), "send", "dst#1", f"src{i}#1", f"쪽지 {i}", "--force"],
                           env=env, capture_output=True, text=True, timeout=30)
        assert r.returncode == 0, r.stderr
    assert "DROPPED 1 oldest to=dst#1" in r.stderr  # 기존 stderr 줄 그대로
    oldest = min(json.loads(ln)["seq"] for ln in (tmp_path / "mailbox.log.jsonl").read_text(encoding="utf-8").splitlines() if ln.strip())
    lines = (tmp_path / "mailbox.drops.log").read_text(encoding="utf-8").splitlines()
    assert len(lines) == 1 and re.fullmatch(rf"\d{{4}}-\d\d-\d\dT\d\d:\d\d:\d\d to=dst#1 dropped=1 oldest_seq={oldest}", lines[0]), lines
    assert "쪽지" not in lines[0]  # 본문 0


@pytest.fixture
def slack():
    s = FakeSlack()
    yield s
    s.srv.shutdown()


def inbound(root: Path, slack: FakeSlack) -> subprocess.CompletedProcess:
    ft = root / ".fable-team"
    (root / "tok.env").write_text("YOONHWAN_BOT_TOKEN=xoxp-test\n", encoding="utf-8")
    env = {**os.environ, "FAKE_MBOX": str(ft / "comm" / "mbox.sh"), "MIRROR_TMUX": "true", "FT_QUEUE_WATCH_BIN": str(QW)}
    return subprocess.run(
        [sys.executable, str(INBOUND), "--channel", "C1", "--human", HUMAN, "--mbox", str(ft / "comm" / "mbox.sh"),
         "--seats-file", str(ft / "seats.json"), "--state-dir", str(root / "st"), "--token-file", str(root / "tok.env"),
         "--api-base", slack.base, "--inbox-bin", str(HERE / "_fake_inbox.sh"), "--once"], capture_output=True, text=True, timeout=60, env=env)


def test_e_slack_full_deferral_to_desk_mails_planner_master_once_per_item(root: Path, slack: FakeSlack):
    sys.path.insert(0, str(HARNESS / "kit" / "slack-mirror"))
    import mirror_questions as mq

    assert inbound(root, slack).returncode == 0  # baseline
    thread = "9999999990.000001"
    slack.msgs.append({"ts": thread, "text": "#820 시작 — x", "thread_ts": "", "bot_id": "B1"})
    mq.add(root / "st" / "byz_slack_questions.C1.json", 100, {"key": "#820", "seat": DESK, "what": "질문", "options": [], "thread_ts": thread})
    slack.human("네", thread)
    fill(root, DESK, 10)
    for _ in range(2):  # 두 패스 — 슬랙 알림도 master 쪽지도 항목당 1번
        r = inbound(root, slack)
        assert r.returncode == 0, r.stderr
    assert sum("가득" in m["text"] for m in slack.msgs) == 1  # 기존 슬랙 알림 그대로
    assert [x for x in rows(root) if x["to"] == DESK and x["from"] == "slack-oppa"] == []  # 미룸 동작 그대로
    assert alerts(root, PLANNER) == [f"[우편함 거의 참] {DESK} 미읽음 10/10 — 그 좌석이 recv 해야 함 · 넘치면 오래된 것부터 사라짐"]


def test_e2_full_seat_is_its_own_and_planner_master_warns_without_mail(root: Path, slack: FakeSlack):
    assert inbound(root, slack).returncode == 0
    slack.human("새 요청이에요")  # 루트 글 → planner _master
    fill(root, PLANNER, 10)
    r = inbound(root, slack)
    assert r.returncode == 0, r.stderr
    assert sum("가득" in m["text"] for m in slack.msgs) == 1
    assert alerts(root, PLANNER) == [] and re.search(r"WARN .*" + re.escape(PLANNER), r.stderr), r.stderr  # 조용히 0 아님
