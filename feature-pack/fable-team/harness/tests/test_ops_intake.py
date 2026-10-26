#!/usr/bin/env python3
"""test_ops_intake — r955 접수 도구 시험 ⓐ~ⓗ (단일 파일 · 표준 라이브러리만).

실 슬랙·실 gh·실 ssh·실 mini 호출 0: 가짜 슬랙 API(로컬 HTTP) · 가짜 gh(고정 JSON) · 가짜 ssh(로컬 실행) · 임시 HOME.
  python3 tests/test_ops_intake.py                전체 (rc0 = ALL PASS)
  python3 tests/test_ops_intake.py --only d       한 축만
  python3 tests/test_ops_intake.py --mutate guard-ts  변이 시험 ⓗ (고친 사본으로 돌려 «그 축이 빨개지는지»)
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

KIT = Path(__file__).resolve().parent.parent / "kit/ops-intake"
SLACK_LIB = KIT.parent / "slack-mirror"
BIN = Path(__file__).resolve().parent.parent / "bin"
FT_MBOX_SH = Path(os.path.expanduser("~/.claude/skills/fable-team/scripts/ft-mbox.sh"))
FT_MBOX_PY = Path(os.path.expanduser("~/.claude/skills/fable-team/scripts/ft-mbox.py"))
PY = sys.executable
SEATS = ("byz-opsintake-tool-cmd#0", "byz-opsintake-master-claude#0", "byz-opsintake-other-claude#9", "byz-issues-master-claude#32")


class Slack:
    """가짜 슬랙 — chat.postMessage 만 받아 기록한다(실 호출 0)."""

    def __init__(self) -> None:
        self.calls: list[dict] = []
        outer = self

        class H(BaseHTTPRequestHandler):
            def do_POST(self) -> None:  # noqa: N802
                n = int(self.headers.get("Content-Length") or 0)
                body = json.loads(self.rfile.read(n).decode() or "{}")
                body["method"] = self.path.strip("/")
                outer.calls.append(body)
                out = json.dumps({"ok": True, "ts": f"1700.000{len(outer.calls)}"}).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(out)))
                self.end_headers()
                self.wfile.write(out)

            def log_message(self, *a) -> None:
                return

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), H)
        self.port = self.httpd.server_address[1]
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def base(self) -> str:
        return f"http://127.0.0.1:{self.port}/"

    def stop(self) -> None:
        self.httpd.shutdown()


class Env:
    """임시 HOME + 이 맥/미니 쪽지함 + 가짜 gh·ssh·push — 한 축의 세계."""

    def __init__(self) -> None:
        self.t = Path(tempfile.mkdtemp(prefix="opsintake-"))
        mac, mini = self.t / "mac", self.t / "mini"
        self.home, self.mini = mac, mini
        for h in (mac, mini):
            (h / ".fable-team" / "comm").mkdir(parents=True)
            (h / ".fable-team" / "ops-intake" / "inbox").mkdir(parents=True)
            (h / ".fable-team" / "ops-intake" / "status").mkdir(parents=True)
        (mac / ".hermes").mkdir(parents=True)
        (mac / ".hermes/.env").write_text("SLACK_BOT_TOKEN=xoxb-test-not-real\n")
        (mini / ".claude/skills/fable-team/scripts").mkdir(parents=True)
        shutil.copy(FT_MBOX_PY, mini / ".claude/skills/fable-team/scripts/ft-mbox.py")
        self.slack = Slack()
        self.gh = self.t / "gh.sh"
        self.gh.write_text('#!/usr/bin/env bash\ncat "$GH_VIEW"\n')
        self.ssh = self.t / "ssh.sh"
        self.ssh.write_text('#!/usr/bin/env bash\nHOME="$MINI_HOME" exec bash -c "${@: -1}"\n')
        self.push = self.t / "push.sh"
        self.push.write_text(f'#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "$PUSH_LOG"\n')
        for p in (self.gh, self.ssh, self.push):
            p.chmod(0o755)
        self.view = self.t / "view.json"
        self.view.write_text("{}")
        self.pushlog = self.t / "push.log"
        seats = self.t / "seats.json"
        seats.write_text(json.dumps({s: {"role": "nano", "agent": "pi", "tick": "ft-master-tick"} for s in SEATS}))
        self.env = {
            "FT_SEATS_JSON": str(seats),
            "FT_MBOX_RATE_N": "500",
            "FT_MBOX_RATE_WINDOW": "60",
            "FT_MBOX_RING": "200",
            "FT_MBOX_RESEND_COOLDOWN": "0",
            "FT_MBOX_SH": str(FT_MBOX_SH),
            "PATH": f"{os.environ['PATH']}",
            "HOME": str(mac),
            "TMPDIR": str(self.t),
            "no_proxy": "127.0.0.1,localhost",
            "NO_PROXY": "127.0.0.1,localhost",
            "OPS_INTAKE_ROOT": str(mac / ".fable-team/ops-intake"),
            "OPS_MBOX_SH": str(FT_MBOX_SH),
            "OPS_MBOX_PY": str(FT_MBOX_PY),
            "OPS_MBOOT_X": "",
            "OPS_SLACK_LIB": str(SLACK_LIB),
            "OPS_INTALE_X": "",
            "OPS_HERMES_ENV": str(mac / ".hermes/.env"),
            "OPS_SLACK_BASE": self.slack.base(),
            "OPS_INTAKE_CHANNEL": "C0TESTCHAN1",
            "OPS_GH": str(self.gh),
            "GH_VIEW": str(self.view),
            "OPS_PUSH": str(self.push),
            "PUSH_LOG": str(self.pushlog),
            "OPS_MINI_WRITE": str(self.t / "miniwrite.sh"),
            "OPS_INTAKE_SECRET_DIR": str(BIN),
            "FT_BIN": str(BIN),
            "SAT_MINI_PY": str(mini / ".claude/skills/fable-team/scripts/ft-mbox.py"),
            "MINI_HOME": str(mini),
            "SAT_SSH": str(self.ssh),
            "SAT_STATE": str(mac / ".fable-team/sat/delivered.json"),
            "FT_MBOX_DIR": str(mac / ".fable-team/comm"),
            "FT_NOW": "1793000000",
        }
        self.env.pop("OPS_MBOOT_X")
        self.env.pop("OPS_INTALE_X")
        mw = self.t / "miniwrite.sh"
        mw.write_text('#!/usr/bin/env bash\nmkdir -p "$MINI_HOME/$(dirname "$1")"; cat > "$MINI_HOME/$1"\n')
        mw.chmod(0o755)

    def run(self, script: str, *args: str, stdin: str = "", extra: dict | None = None) -> subprocess.CompletedProcess:
        env = dict(self.env, **(extra or {}))
        return subprocess.run([PY, str(KIT / script), *args], input=stdin, capture_output=True, text=True, env=env, cwd=str(self.t))

    def notes(self, home: Path | None = None) -> list[dict]:
        path = (home or self.home) / ".fable-team/comm/mailbox.jsonl"
        if not path.is_file():
            return []
        return [json.loads(ln) for ln in path.read_text().splitlines() if ln.strip()]

    def cards(self) -> list[Path]:
        return sorted((self.home / ".fable-team/ops-intake/inbox").glob("OPS-*.md"))

    def cleanup(self) -> None:
        self.slack.stop()
        shutil.rmtree(self.t, ignore_errors=True)


CARD = {
    "slack_channel": "C0TESTCHAN1", "thread_ts": "1793000000.000100", "user_id": "U0TESTUSER1",
    "kind": "bug", "product": "howtotalk", "urgency": "보통",
    "title": "로그인 버튼을 두 번 눌러야 들어가져요", "symptom": "아이폰 사파리에서 첫 탭이 먹히지 않습니다.",
    "repro": "1. 사파리 열기\n2. 로그인 탭", "expect": "한 번에 들어가짐", "attachments": [],
}


def card_text(ops_id="OPS-20261026-001", masked=0, extra="") -> str:
    return (f"ops_id: {ops_id}\nslack_channel: C0TESTCHAN1\nthread_ts: 1793000000.000100\nuser_id: U0TESTUSER1\n"
            f"kind: bug\nproduct: howtotalk\nurgency: 보통\nsecrets_masked: {masked}\n---\n## 제목\n로그인 두 번\n"
            f"## 증상·요청\n첫 탭이 안 먹어요{extra}\n## 재현\n- 없음\n## 기대 동작\n한 번에\n## 첨부\n- 없음\n")


class Base(unittest.TestCase):
    def setUp(self) -> None:
        self.e = Env()

    def tearDown(self) -> None:
        self.e.cleanup()


class TestWrite(Base):
    """ⓐ 스키마 · ⓑ 마스킹 · ⓒ 한도"""

    def test_a_valid_creates_card_and_note(self) -> None:
        r = self.e.run("ops_intake_write.py", stdin=json.dumps(CARD))
        self.assertEqual(r.returncode, 0, r.stderr)
        cards = self.e.cards()
        self.assertEqual(len(cards), 1)
        text = cards[0].read_text()
        self.assertIn("secrets_masked: 0", text)
        notes = self.e.notes()
        self.assertEqual(len(notes), 1)
        self.assertTrue(notes[0]["body"].startswith("[OPS-NEW] OPS-"))

    def test_a_bad_schema_writes_nothing(self) -> None:
        bad = dict(CARD, kind="praise")
        r = self.e.run("ops_intake_write.py", stdin=json.dumps(bad))
        self.assertEqual(r.returncode, 2)
        self.assertEqual(self.e.cards(), [])
        self.assertEqual(self.e.notes(), [])

    def test_b_secrets_and_pii_masked(self) -> None:
        body = dict(CARD, title="연결이 안 돼요", symptom=(
            "postgres://admin:pass1234@db.example.com:5432/x · 토큰 sk-abcdefghijklmnopqrstuvwxyz012345 · "
            "문의 010-1234-5678 · 메일 hong@example.com"))
        r = self.e.run("ops_intake_write.py", stdin=json.dumps(body))
        self.assertEqual(r.returncode, 0, r.stderr)
        text = self.e.cards()[0].read_text()
        for leaked in ("pass1234", "sk-abcdefghijklmnopqrstuvwxyz012345", "010-1234-5678", "hong@example.com"):
            self.assertNotIn(leaked, text, leaked)
        self.assertRegex(text, r"secrets_masked: [1-9]")
        self.assertRegex(text, r"\[마스킹 [1-9]\d*건: ")
        sys.path.insert(0, str(BIN))
        from ft_secret_shapes import mask
        self.assertEqual(mask(text)[1], [], "가린 카드에 비밀 값이 남았다")

    def test_c_user_limit_blocks_sixth(self) -> None:
        for i in range(5):
            r = self.e.run("ops_intake_write.py", stdin=json.dumps(CARD), extra={"FT_NOW": str(1793000000 + i * 30)})
            self.assertEqual(r.returncode, 0, r.stderr)
        r = self.e.run("ops_intake_write.py", stdin=json.dumps(CARD), extra={"FT_NOW": str(1793000000 + 200)})
        self.assertEqual(r.returncode, 3)
        self.assertIn("잠시 뒤", r.stderr)
        self.assertEqual(len(self.e.cards()), 5)

    def test_c_channel_limit_blocks_31st(self) -> None:
        for i in range(30):
            doc = dict(CARD, user_id=f"U0TEST{i:04d}X")
            r = self.e.run("ops_intake_write.py", stdin=json.dumps(doc), extra={"FT_NOW": str(1793000000 + i)})
            self.assertEqual(r.returncode, 0, r.stderr)
        doc = dict(CARD, user_id="U0TESTLATE1")
        r = self.e.run("ops_intake_write.py", stdin=json.dumps(doc), extra={"FT_NOW": "1793000100"})
        self.assertEqual(r.returncode, 3)
        self.assertEqual(len(self.e.cards()), 30)


class TestIntake(Base):
    """ⓑ2 이 맥 재검사 · ⓑ3 mini 마스킹 수 / 칸 없음"""

    def put_card(self, text: str, name="OPS-20261026-002.md") -> Path:
        p = self.e.home / ".fable-team/ops-intake/inbox" / name
        p.write_text(text)
        return p

    def test_b2_rescan_quarantines_masked_copy(self) -> None:
        dirty = card_text(extra="\nredis://:hunter2@cache.local:6379 · sk-abcdefghijklmnopqrstuvwxyz012345")
        card = self.put_card(dirty)
        r = self.e.run("ops_intake_sync.py", "intake")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual([n for n in self.e.notes() if "[ISSUE-REQ]" in n["body"]], [], "비밀을 본 카드는 이슈 요청 0")
        self.assertFalse(card.exists(), "이 맥에 원본이 남았다")
        q = self.e.home / ".fable-team/ops-intake/quarantine"
        blob = "\n".join(p.read_text() for p in q.glob("*.md"))
        for leaked in ("hunter2", "sk-abcdefghijklmnopqrstuvwxyz012345"):
            self.assertNotIn(leaked, blob)
        self.assertIn("[제거]", blob)
        ledger = (q / "MASKED-LOG.md").read_text()
        self.assertNotIn("hunter2", ledger)
        self.assertRegex(ledger, r"마스킹 [1-9]\d*건")
        tmpdir = self.e.home / ".fable-team/ops-intake/state/tmp"
        self.assertEqual(list(tmpdir.glob("*")) if tmpdir.is_dir() else [], [], "임시 원본 파일이 남았다")
        mini_card = self.e.mini / ".fable-team/ops-intake/inbox" / card.name
        self.assertTrue(mini_card.is_file(), "mini 쪽 카드를 마스킹 사본으로 덮지 않았다")
        self.assertNotIn("hunter2", mini_card.read_text())

    def test_b3_declared_masked_blocks(self) -> None:
        card = self.put_card(card_text(masked=1))
        r = self.e.run("ops_intake_sync.py", "intake")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual([n for n in self.e.notes() if "[ISSUE-REQ]" in n["body"]], [])
        replies = [n for n in self.e.notes() if "[OPS-REPLY]" in n["body"]]
        self.assertEqual(len(replies), 1)
        self.assertIn("키 제거", replies[0]["body"])
        self.assertFalse(card.exists())

    def test_b3_missing_field_blocks(self) -> None:
        self.put_card(card_text().replace("secrets_masked: 0\n", ""))
        r = self.e.run("ops_intake_sync.py", "intake")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual([n for n in self.e.notes() if "[ISSUE-REQ]" in n["body"]], [])
        replies = [n for n in self.e.notes() if "[OPS-REPLY]" in n["body"]]
        self.assertEqual(len(replies), 1)
        self.assertIn("판정 불가", replies[0]["body"])

    def test_clean_card_sends_issue_req(self) -> None:
        self.e.view.write_text("[]")
        self.put_card(card_text())
        r = self.e.run("ops_intake_sync.py", "intake")
        self.assertEqual(r.returncode, 0, r.stderr)
        reqs = [n for n in self.e.notes() if "[ISSUE-REQ]" in n["body"]]
        self.assertEqual(len(reqs), 1)
        self.assertIn("source:user-report", reqs[0]["body"])


class TestPoster(Base):
    """ⓓ 게시기 — thread_ts · 중복 · 문장 검사"""

    def note(self, body: str) -> None:
        r = subprocess.run(["bash", str(FT_MBOX_SH), "send", "byz-opsintake-tool-cmd#0", "byz-opsintake-master-claude#0", body],
                           capture_output=True, text=True, env=dict(self.e.env, FT_MBOX_DIR=str(self.e.home / ".fable-team/comm"),
                                                                    HOME=str(self.e.home)))
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_d_posts_once_in_thread(self) -> None:
        self.note("[OPS-REPLY] OPS-20261026-001\nthread_ts: 1793000000.000100\n접수했어요. 이슈 #9001 로 등록됐습니다.")
        r = self.e.run("ops_intake_poster.py")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len(self.e.slack.calls), 1)
        call = self.e.slack.calls[0]
        self.assertEqual(call["thread_ts"], "1793000000.000100")
        self.assertEqual(call["channel"], "C0TESTCHAN1")
        self.assertEqual(self.e.notes(), [], "게시 뒤 쪽지가 남았다(ack 0)")

    def test_d_missing_thread_ts_posts_nothing(self) -> None:
        self.note("[OPS-REPLY] OPS-20261026-001\n접수했어요.")
        r = self.e.run("ops_intake_poster.py")
        self.assertEqual(r.returncode, 2)
        self.assertEqual(self.e.slack.calls, [])

    def test_d_same_seq_twice_posts_once(self) -> None:
        body = "[OPS-REPLY] OPS-20261026-001\nthread_ts: 1793000000.000100\n확인 중입니다."
        self.note(body)
        self.note(body)
        self.e.run("ops_intake_poster.py")
        self.assertEqual(len(self.e.slack.calls), 1)

    def test_d_internal_words_and_secrets_blocked(self) -> None:
        for bad in ("자세한 건 /Users/someone/x.md 참고", "커밋 9f3ab21c 를 확인", "좌석 byz-planner-master-claude#3 가 봤어요"):
            self.e.slack.calls.clear()
            com = self.e.home / ".fable-team/comm/mailbox.jsonl"
            com.unlink(missing_ok=True)
            self.note(f"[OPS-REPLY] OPS-20261026-001\nthread_ts: 1793000000.000100\n{bad}")
            r = self.e.run("ops_intake_poster.py")
            self.assertEqual(r.returncode, 4, bad)
            self.assertEqual(self.e.slack.calls, [], bad)


class TestSync(Base):
    """ⓔ 이슈 상태 → 스레드 1줄"""

    def status(self, **kw) -> None:
        base = {"ops_id": "OPS-20261026-001", "issue": 9001, "thread_ts": "1793000000.000100", "slack_channel": "C0TESTCHAN1",
                "state": "open", "status_label": "status:in-progress", "seen_comments": []}
        base.update(kw)
        (self.e.home / ".fable-team/ops-intake/status" / f"{base['ops_id']}.json").write_text(json.dumps(base))

    def test_e_only_three_kinds_of_change(self) -> None:
        self.status()
        self.e.view.write_text(json.dumps({
            "state": "OPEN",
            "labels": [{"name": "status:blocked"}, {"name": "team:planner"}],
            "comments": [
                {"id": "c1", "body": "내부 메모 — 판정 1125 · sha 9f3ab21c"},
                {"id": "c2", "body": "[사용자 공지]\n확인 중입니다. 이번 주 안에 고칠게요."},
            ],
        }))
        r = self.e.run("ops_intake_sync.py", "status")
        self.assertEqual(r.returncode, 0, r.stderr)
        pushed = [ln for ln in self.e.pushlog.read_text().splitlines() if "[OPS-REPLY]" in ln]
        self.assertEqual(len(pushed), 2, pushed)  # 라벨 변화 1 + 공지 1 · 내부 코멘트 0
        self.assertTrue(all("[OPS-REPLY]" in p for p in pushed))
        log = self.e.pushlog.read_text()
        self.assertFalse("판정 1125" in log or "9f3ab21c" in log)
        st = json.loads((self.e.home / ".fable-team/ops-intake/status/OPS-20261026-001.json").read_text())
        self.assertEqual(st["status_label"], "status:blocked")
        self.assertIn("synced_at", st)

    def test_e_pack_20_per_pass(self) -> None:
        for i in range(25):
            self.status(ops_id=f"OPS-20261026-{i + 1:03d}", issue=9002 + i)
        self.e.view.write_text(json.dumps({"state": "OPEN", "labels": [], "comments": []}))
        r = self.e.run("ops_intake_sync.py", "status")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("pass=20 rest=5", r.stdout)


class TestPull(Base):
    """ⓕ pull 데몬 — 좌석 목록 · 큐 상한 · 카드 결과 폴더"""

    def mini_note(self, to: str, body: str) -> None:
        r = subprocess.run(["bash", str(FT_MBOX_SH), "send", to, "byz-opsintake-tool-cmd#0", body],
                           capture_output=True, text=True,
                           env=dict(self.e.env, HOME=str(self.e.mini), FT_MBOX_DIR=str(self.e.mini / ".fable-team/comm")))
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_f_only_listed_seats(self) -> None:
        self.mini_note("byz-opsintake-master-claude#0", "[OPS-NEW] A")
        self.mini_note("byz-opsintake-other-claude#9", "다른 좌석 쪽지")
        seats = self.e.t / "seats.txt"
        seats.write_text("# pull 대상\nbyz-opsintake-master-claude#0\n")
        r = self.e.run("sat-mbox.py", "pull", "--seats-file", str(seats))
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        got = [n["body"] for n in self.e.notes()]
        self.assertEqual(got, ["[OPS-NEW] A"])
        self.assertEqual(len(self.e.notes(self.e.mini)), 1, "목록 밖 좌석 쪽지가 사라졌다")

    def test_f_queue_cap_defers(self) -> None:
        for i in range(3):
            self.mini_note("byz-opsintake-master-claude#0", f"[OPS-NEW] {i}")
        q = self.e.home / ".fable-team/comm/mailbox.jsonl"
        q.write_text("".join(json.dumps({"seq": 100 + i, "to": "x", "from": "y", "body": "z"}) + "\n" for i in range(10)))
        r = self.e.run("sat-mbox.py", "pull", "--seats", "byz-opsintake-master-claude#0")
        self.assertEqual(r.returncode, 5)
        self.assertIn("큐 10", r.stdout)
        self.assertEqual(len(self.e.notes(self.e.mini)), 3, "보류인데 미니 쪽지가 지워졌다")

    def test_f_scp_card_only_result_dir(self) -> None:
        p = self.e.mini / ".fable-team/ops-intake/inbox/OPS-20261026-009.md"
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(card_text("OPS-20261026-009"))
        out = self.e.t / "pulled"
        r = self.e.run("sat-mbox.py", "scp-card", str(p), str(out))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual([x.name for x in out.iterdir()], ["OPS-20261026-009.md"])
        self.assertEqual(sorted(x.name for x in self.e.t.iterdir() if x.is_dir() and x.name not in ("mac", "mini", "pulled")), [])


class TestShell(Base):
    """ⓖ /bin/bash 3.2 + 시스템 python3"""

    def test_g_shell_and_python(self) -> None:
        b = subprocess.run(["/bin/bash", "--version"], capture_output=True, text=True).stdout.splitlines()[0]
        self.assertIn("version 3.2", b, b)
        v = subprocess.run([PY, "-V"], capture_output=True, text=True).stdout + subprocess.run([PY, "-V"], capture_output=True, text=True).stderr
        self.assertRegex(v, r"Python 3\.\d+")
        cmd = "set -euo pipefail; printf '%s' \"$CARD\" | python3 " + str(KIT) + "/ops_intake_write.py"
        r = subprocess.run(["/bin/bash", "-c", cmd], input="", capture_output=True, text=True,
                           env=dict(self.e.env, CARD=json.dumps(CARD)))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len(self.e.cards()), 1)


MUTATIONS = {
    # 이름: (파일, 원문, 바꿀 글, 이 변이가 깨야 하는 축)
    "mask-off": ("ops_intake_common.py", "        masked, n = rx.subn(ph, masked)", "        masked, n = masked, 0", "b-secrets"),
    "rescan-off": ("ops_intake_sync.py", "    if declared > 0 or kinds:", "    if declared > 0:", "b2-rescan"),
    "declared-off": ("ops_intake_sync.py", '        declared = int(MASKED_RX.search(text).group(1))', "        declared = 0", "b3-declared"),
    "guard-ts": ("ops_intake_poster.py", '    if not m_t:', '    if not m_t and False:', "d-thread-ts"),
    "ledger-off": ("ops_intake_poster.py", "            if key in done:", "            if False:", "d-dup"),
    "notice-off": ("ops_intake_sync.py", '        if str(cm.get("id")) in seen or not body.lstrip().startswith(NOTICE):', '        if True:', "e-notice"),
}


def run_cases(only: str = "") -> int:
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromModule(sys.modules[__name__])
    if only:
        keep = unittest.TestSuite()
        for group in suite:
            for case in group:
                if only in case.id().lower():
                    keep.addTest(case)
        suite = keep
    res = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if res.wasSuccessful() else 1


def mutate(name: str) -> int:
    """고친 사본 키트를 만들어 «그 축만» 돌린다 — 변이가 빨개지면 검사가 살아 있다는 뜻."""
    global KIT
    script, old, new, axis = MUTATIONS[name]
    work = Path(tempfile.mkdtemp(prefix="opsmut-"))
    kit = work / "kit"
    shutil.copytree(KIT, kit)
    src = (kit / script).read_text()
    if old not in src:
        print(f"MUTATE {name}: 원문을 못 찾음 — 검사가 낡았다", file=sys.stderr)
        return 1
    (kit / script).write_text(src.replace(old, new, 1))
    real, KIT = KIT, kit
    try:
        rc = run_cases(axis.split("-")[0])
    finally:
        KIT = real
        shutil.rmtree(work, ignore_errors=True)
    if rc == 0:
        print(f"MUTATE {name}: 살아남음(변이를 못 잡았다) → FAIL")
        return 1
    print(f"MUTATE {name}: 잡았다(축 {axis}) → PASS")
    return 0


if __name__ == "__main__":
    args = sys.argv[1:]
    if args[:1] == ["--mutate"]:
        sys.exit(mutate(args[1]))
    if args[:1] == ["--only"]:
        sys.exit(run_cases(args[1].lower()))
    sys.exit(run_cases())
