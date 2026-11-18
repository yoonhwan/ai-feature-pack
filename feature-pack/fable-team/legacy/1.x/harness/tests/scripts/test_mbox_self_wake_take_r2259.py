"""r2259 — 좌석이 자기에게 보낸 «[깨움]»(to == me 글자 그대로) = recv · peek · send doorbell 이 셈한다(O1 · O2 · O3).

다른 자기 발신 행([착지] · [카드 이동] · [회신] …)과 옛 세션 → 후계 행 판정은 그대로다(r1116 · r1153 · r2146).
임시 우편함(FT_MBOX_DIR) + 임시 명부 + 합성 쪽지 행 + 가짜 tmux/ps 만 쓴다 · 실 우편함 · 실 명부 · 네트워크 0 · sleep 0.
R2259_COMM = 다른 comm 폴더(변이 사본)를 볼 때만 준다 · 없으면 이 팩의 comm.
"""
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

COMM = Path(os.environ.get("R2259_COMM") or Path(__file__).resolve().parents[3] / "harness" / "comm")
MBOX = COMM / "mbox.py"
ME, OLD, PEER = "byz-t-arch-pi#20", "byz-t-arch-pi#19", "byz-t-master-claude#1"
WAKE = "[깨움] r3b 대기 끝 — 판독 이어감"
NOW = 1700002800


def _run(box: Path, *args: str):
    env = {**os.environ, "FT_MBOX_DIR": str(box), "FT_MBOX_RELAY_DIR": str(box / "relay"),
           "FT_SEATS_JSON": str(box / "seats.json"),
           "FT_MBOX_NOW": str(NOW)}
    return subprocess.run([sys.executable, str(MBOX), *args], env=env, capture_output=True, text=True, timeout=30)


def _roster(box: Path):   # 계보 pi#19 → pi#20(me) · 명부 없는 사례 = seats-t.json 0(역할 키만 · r2146 ⑤)
    (box / "seats-t.json").write_text(json.dumps({
        OLD: {"role": "arch", "_replaced_by": ME},
        ME: {"role": "arch", "_replaces": [OLD]},
    }), encoding="utf-8")


def _queue(box: Path, rows):   # 합성 쪽지 행 [(seq, to, from, body[, wake_at])]
    with open(box / "mailbox.jsonl", "w", encoding="utf-8") as f:
        for seq, to, frm, body, *wake in rows:
            r = {"seq": seq, "ts": "2026-11-18T00:00:00", "to": to, "from": frm, "body": body}
            if wake:
                r["wake_at"] = wake[0]
            f.write(json.dumps(r, ensure_ascii=False) + "\n")


def _left(box: Path):
    return sorted(json.loads(x)["seq"] for x in (box / "mailbox.jsonl").read_text(encoding="utf-8").splitlines() if x.strip())


def _peek(box: Path, me=ME):
    p = _run(box, "peek", me)
    assert p.returncode == 0, p.stdout + p.stderr
    return p.stdout.strip()


def _read(box: Path, me=ME):
    p = _run(box, "recv", me)
    assert p.returncode == 0, p.stdout + p.stderr
    return p.stdout


def test_r1_self_wake_taken(tmp_path: Path):   # ① O1 — 기준판 = pending 0 · READ none
    _roster(tmp_path)
    _queue(tmp_path, [(1, ME, ME, WAKE)])
    assert _peek(tmp_path).startswith(f"pending=1 latest_seq=1 from={ME} ")
    assert "READ none" not in _read(tmp_path)
    assert _left(tmp_path) == []


def test_r1_send_doorbell_not_none(tmp_path: Path):   # ① send 줄 — doorbell 판정이 peek pending 을 본다(DA 메모)
    box, fake = tmp_path / "box", tmp_path / "fakebin"
    comm = box / ".fable-team" / "comm"
    comm.mkdir(parents=True)
    (box / ".fable-team" / "state").mkdir()
    (box / "tmp").mkdir()
    for f in [*COMM.glob("mbox*.sh"), *COMM.glob("mbox*.py"), COMM / "ft-agent-alive.sh"]:
        shutil.copy(f, comm)
    (comm / "mailbox.jsonl").write_text("", encoding="utf-8")
    (tmp_path / "seats.json").write_text(json.dumps({"gn#1": {"agent": "claude", "team": "h1", "tick": None}}), encoding="utf-8")
    fake.mkdir()
    (fake / "tmux").write_text("""#!/bin/bash
case "${1:-}" in
  list-panes) shift; if [ "${1:-}" = "-a" ]; then printf 'gn#1|%%1\\n'; else printf '900001\\n'; fi; exit 0;;
  has-session|list-clients|send-keys) exit 0;;
  display-message) printf 'node\\n'; exit 0;;
esac
exit 1
""", encoding="utf-8")
    (fake / "ps").write_text("#!/bin/sh\nprintf '%s\\n' '900001     1 S    /bin/zsh' "
                             "'900002 900001 S    /usr/bin/claude --dangerously-skip-permissions'\n", encoding="utf-8")
    for f in fake.iterdir():
        f.chmod(0o755)
    env = {**os.environ, "PATH": f"{fake}:{os.environ['PATH']}", "FT_PS_CMD": str(fake / "ps"),
           "FT_AGENT_ALIVE_TIMEOUT": "2", "FT_BIN": str(tmp_path / "nobin"), "FT_MBOX_RECV_LIMIT": "50",
           "FT_MBOX_RATE_N": "1000", "FT_MBOX_RESEND_COOLDOWN": "0", "FT_MBOX_DIR": str(comm),
           "FT_MBOX_STATE_DIR": str(box / ".fable-team" / "state"), "TMPDIR": str(box / "tmp"),
           "HOME": str(tmp_path / "nohome"), "FT_SEATS_JSON": str(tmp_path / "seats.json"), "FT_MBOX_NOW": str(NOW)}
    p = subprocess.run(["bash", str(comm / "mbox.sh"), "send", "gn#1", "gn#1", WAKE],
                       env=env, capture_output=True, text=True, timeout=30)
    assert p.returncode == 0, p.stdout + p.stderr
    db = [w for w in p.stdout.split() if w.startswith("doorbell=")]
    assert db and db[-1] != "doorbell=none", p.stdout


def test_r2_self_wake_batched(tmp_path: Path):   # ② O2 _batched — 기준판 = 칸 없음
    _roster(tmp_path)
    _queue(tmp_path, [(1, ME, ME, WAKE, NOW + 600)])
    hhmm = time.strftime("%H:%M", time.localtime(NOW + 600))
    assert _peek(tmp_path).endswith(f" batched=1 wake={hhmm}")


def test_r3_tool_self_alerts_not_counted(tmp_path: Path):   # ③ O3 — [착지] · [카드 이동] 그대로
    _roster(tmp_path)
    _queue(tmp_path, [(1, ME, ME, "[착지] pr=1 sha=abc"), (2, ME, ME, "[카드 이동] r9 대기→진행")])
    assert _peek(tmp_path).startswith("pending=0 ")
    assert "READ none" in _read(tmp_path)
    assert _left(tmp_path) == [1, 2]


def test_r4_old_to_successor_wake(tmp_path: Path):   # ④ O3 — 명부 없음(역할 키만) · 옛 O → 후계 N
    _queue(tmp_path, [(1, ME, OLD, "[깨움] x")])
    assert _peek(tmp_path, OLD).startswith("pending=0 ")
    assert "READ none" in _read(tmp_path, OLD)
    assert _left(tmp_path) == [1]
    assert "READ none" not in _read(tmp_path, ME)
    assert _left(tmp_path) == []


def test_r5_reply_to_self_no_echo(tmp_path: Path):   # ⑤ 반향 고리 0 — 받은 뒤 자기 회신
    _roster(tmp_path)
    _queue(tmp_path, [(1, ME, ME, WAKE)])
    _read(tmp_path)
    _queue(tmp_path, [(2, ME, ME, "[회신] 깨움 받음")])
    assert _peek(tmp_path).startswith("pending=0 ")


def test_r6_head_position(tmp_path: Path):   # ⑥ 앞 공백 · 줄바꿈 = ① · 본문 가운데 = 셈 0
    _roster(tmp_path)
    _queue(tmp_path, [(1, ME, ME, "  \n[깨움] 앞 공백"), (2, ME, ME, "x [깨움] 가운데")])
    assert _peek(tmp_path).startswith("pending=1 latest_seq=1 ")
    _read(tmp_path)
    assert _left(tmp_path) == [2]
