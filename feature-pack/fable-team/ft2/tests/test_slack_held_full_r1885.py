"""r1885 ft2 Slack 보류(full) 글 노출 + 재기동 재제출 예산·새 글 먼저 — 반례 ①~⑤(④′ 포함) · 변이 M1(예산 상한 빼기 → ①④) ·
M2(서명 기억 빼기 → ②). 임시 root · 실 Intake(용량 낮춰 full 만들기 → 8 로 재기동) · 가짜 notify · 가짜 mbox(<root>/.fable-team/comm/mbox.sh).
실 우편함·실 Slack·실 명부·설치 0 · sleep 0 · 기준판(recover 가 미완 전부 재제출 · 노출 0) = ①④⑤ Red."""
import importlib.util, json, os  # noqa: E401
import pytest

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESK, MASTER, T, C, U = "byz-planner-desk-pi#9", "byz-harness-master-pi#9", "TFAKE", "CFAKE", "U"
MBOX = '#!/bin/sh\nprintf "%s\\t%s\\n" "$2" "$(printf "%s" "$4" | head -1)" >> "$0.log"\n'
spec = importlib.util.spec_from_file_location("r1885_receive", os.path.join(FT2, "adapters", "slack", "receive.py"))
spec.loader.exec_module(receive := importlib.util.module_from_spec(spec))


@pytest.fixture
def root(tmp_path, monkeypatch):
    fable = tmp_path / ".fable-team"
    (fable / "comm").mkdir(parents=True)
    (fable / "seats-planner.json").write_text(json.dumps({"_desk": DESK}), encoding="utf-8")
    (fable / "seats-harness.json").write_text(json.dumps({"_master": MASTER}), encoding="utf-8")
    (fable / "comm" / "mbox.sh").write_text(MBOX, encoding="utf-8")
    monkeypatch.delenv("FT2_FULL_ALERT_WAKE", raising=False)
    return tmp_path


def held(root):   # [보류] 쪽지 줄(desk·master 각 1 = 1통)
    path = root / ".fable-team" / "comm" / "mbox.sh.log"
    return [ln for ln in (path.read_text(encoding="utf-8").splitlines() if path.exists() else []) if "보류" in ln]


def rx(root, capacity):
    client = receive.intake.Intake(str(root), "planner", capacity=capacity)
    return receive.SlackReceive(str(root), ack=lambda e: None, client=client, team="planner", allowed_users=(U,),
                                allowed_channels=(C,), notify=lambda row: None)


def world(root, used, full=3, received=False):
    """남은 일 used · full 글 full 개(ts 179456100i) · received 1 = 더 옛 글 1(재기동 전 죽음) → (재기동 수신기, 처음 attempts)."""
    first = rx(root, used)
    for i in range(used):
        assert first.client.submit("busy%d" % i, "body", "W%d" % i).result == receive.RESULT_OK
    for i in range(full):
        msg = {"team": T, "channel": C, "user": U, "ts": "179456100%d.000001" % i, "text": "글 %d" % i}
        assert first.handle(msg)["state"] == receive.FULL
    if received:
        first._append({"state": receive.RECEIVED, "command": "slack:%s:%s:1794560999.000001" % (T, C), "user": U,
                       "key": [T, C, "1794560999.000001"], "text": "옛 글", "attempts": 1})
    return rx(root, 8), {c: e["attempts"] for c, e in first.latest().items()}


def grown(again, before, state=receive.FULL):   # attempts 가 는 글 → ts 꼬리
    return sorted(c.rsplit(":", 1)[1] for c, e in again.latest().items() if e["attempts"] > before.get(c, 0))


def test_c1_one_room_newest_only_and_held_shown(root):
    again, before = world(root, 7)
    again.recover()
    assert grown(again, before) == ["1794561002.000001"]                          # 예산 1 = 가장 새 글
    assert again.latest()["slack:%s:%s:1794561002.000001" % (T, C)]["state"] == receive.DISPATCHED
    assert sorted(ln.split("\t")[0] for ln in held(root)) == sorted([DESK, MASTER])   # [보류] 1통
    assert "full 2건" in held(root)[0]


def test_c2_second_restart_same_signature_no_alert(root):
    again, before = world(root, 7)
    again.recover()
    snap = {c: e["attempts"] for c, e in again.latest().items()}
    rx(root, 8).recover()                                                         # 같은 상태 재기동 두 번째
    assert len(held(root)) == 2                                                   # 알림 0
    assert grown(rx(root, 8), snap) == []                                         # 그때 예산 0 = 재제출 0


def test_c3_no_full_no_alert(root):
    again, _ = world(root, 3, full=0)
    assert again.recover() == [] and held(root) == []


def test_c4_no_room_zero_resubmit_alert_once(root):
    again, before = world(root, 8)
    lines = len(again.entries())
    again.recover()
    assert grown(again, before) == [] and len(again.entries()) == lines              # attempts 증가 0 · 기록 줄 0
    assert len(held(root)) == 2 and "full 3건" in held(root)[0]


def test_c4b_all_room_all_resubmitted(root):
    again, before = world(root, 0)
    again.recover()
    assert len(grown(again, before)) == 3 and held(root) == []


def test_c5_received_first_then_no_room(root):
    again, before = world(root, 7, full=2, received=True)
    again.recover()
    assert grown(again, before) == ["1794560999.000001"]                          # received 먼저 → 남은 일 8 → 예산 0
    assert len(held(root)) == 2 and "full 2건" in held(root)[0]
