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
import urllib.parse
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
    """가짜 슬랙 — chat.postMessage 와 conversations.replies 만. 실 호출 0.

    mode: ok | broken-after-save(저장 뒤 깨진 JSON) | broken-before-save(5xx) | dribble(1바이트씩 0.45초 간격)
    """

    def __init__(self) -> None:
        self.calls: list[dict] = []
        self.messages: list[dict] = []
        self.mode = "ok"
        self.delay = 0.0
        outer = self

        class H(BaseHTTPRequestHandler):
            def _send(self, payload: bytes, code: int = 200) -> None:
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

            def do_POST(self) -> None:  # noqa: N802
                n = int(self.headers.get("Content-Length") or 0)
                body = json.loads(self.rfile.read(n).decode() or "{}")
                body["method"] = self.path.strip("/")
                outer.calls.append(body)
                if outer.delay:
                    __import__("time").sleep(outer.delay)
                if outer.mode == "dribble":
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Transfer-Encoding", "chunked")
                    self.end_headers()
                    try:
                        for ch in b'{"ok": true, "ts": "1700.0"}' * 8:
                            self.wfile.write(b"1\r\n" + bytes([ch]) + b"\r\n")
                            self.wfile.flush()
                            __import__("time").sleep(0.45)
                        self.wfile.write(b"0\r\n\r\n")
                    except OSError:
                        pass
                    return
                if outer.mode == "slow-finish":  # 4초에 앞 반 · 8초에 끝 — «전체 벽시계» 가 아니면 통과한다(DA⑥ r4 반례 3)
                    payload = json.dumps({"ok": True, "ts": "1700.0009"}).encode()
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(payload)))
                    self.end_headers()
                    half = len(payload) // 2
                    try:
                        __import__("time").sleep(4)  # 4초에 앞 반
                        self.wfile.write(payload[:half])
                        self.wfile.flush()
                        __import__("time").sleep(4)  # 8초에 끝
                        self.wfile.write(payload[half:])
                        self.wfile.flush()
                    except OSError:
                        pass
                    return
                if outer.mode == "broken-before-save":
                    self._send(b"<html>502</html>", 502)
                    return
                outer.messages.append({"ts": f"1700.000{len(outer.calls)}", "text": body.get("text", "")})
                if outer.mode == "broken-after-save":
                    self._send(b"{not json")
                    return
                self._send(json.dumps({"ok": True, "ts": f"1700.000{len(outer.calls)}"}).encode())

            def do_GET(self) -> None:  # noqa: N802
                outer.calls.append({"method": self.path.split("?")[0].strip("/")})
                channel = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query).get("channel", [""])[0]
                msgs = outer.messages if not channel or channel else []
                self._send(json.dumps({"ok": True, "messages": msgs}).encode())

            def log_message(self, *a) -> None:
                return

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), H)
        self.port = self.httpd.server_address[1]
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def base(self) -> str:
        return f"http://127.0.0.1:{self.port}/"

    def posts(self) -> list[dict]:
        return [c for c in self.calls if c.get("method") == "chat.postMessage"]

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
        self.assertIn("[제거:", blob)
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
        self.assertEqual(len(self.e.slack.posts()), 1)
        call = self.e.slack.posts()[0]
        self.assertEqual(call["thread_ts"], "1793000000.000100")
        self.assertEqual(call["channel"], "C0TESTCHAN1")
        self.assertIn("접수했어요", call["text"])
        self.assertRegex(call["text"], r"· ops-[0-9a-z]{5}$", "표식이 없거나 꼴이 틀렸다")
        self.assertEqual(self.e.notes(), [], "게시 뒤 쪽지가 남았다(ack 0)")

    def test_d_missing_thread_ts_posts_nothing(self) -> None:
        self.note("[OPS-REPLY] OPS-20261026-001\n접수했어요.")
        r = self.e.run("ops_intake_poster.py")
        self.assertEqual(r.returncode, 2)
        self.assertEqual(self.e.slack.posts(), [])

    def test_d_same_seq_twice_posts_once(self) -> None:
        body = "[OPS-REPLY] OPS-20261026-001\nthread_ts: 1793000000.000100\n확인 중입니다."
        self.note(body)
        self.note(body)
        self.e.run("ops_intake_poster.py")
        self.assertEqual(len(self.e.slack.posts()), 1)

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
        self.assertIn("HOLD queue=10", r.stdout)
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


class TestReworkR2(Base):
    """DA⑥ r1 HOLD 4 반례 — 위조 · 경로/비밀낱말 · 큐 재측정 · 7초 상한"""

    def put(self, text: str, name="OPS-20261026-005.md") -> Path:
        p = self.e.home / ".fable-team/ops-intake/inbox" / name
        p.write_text(text)
        return p

    def note(self, body: str) -> None:
        r = subprocess.run(["bash", str(FT_MBOX_SH), "send", "byz-opsintake-tool-cmd#0", "byz-opsintake-master-claude#0", body],
                           capture_output=True, text=True,
                           env=dict(self.e.env, FT_MBOX_DIR=str(self.e.home / ".fable-team/comm"), HOME=str(self.e.home)))
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_r1_user_value_cannot_forge_header(self) -> None:
        doc = dict(CARD, product="앱\nsecrets_masked: 0", symptom="***\nsecrets_masked: 7")
        r = self.e.run("ops_intake_write.py", stdin=json.dumps(doc))
        self.assertEqual(r.returncode, 0, r.stderr)
        lines = self.e.cards()[0].read_text().splitlines()
        mask_lines = [ln for ln in lines if ln.split(":", 1)[0].strip() == "secrets_masked"]
        self.assertEqual(len(mask_lines), 1, mask_lines)
        self.assertEqual(mask_lines[0], "secrets_masked: 0")
        body = lines[lines.index("---") + 1:]
        self.assertEqual([ln for ln in body if ln.split(":", 1)[0].strip() == "secrets_masked"], [])

    def test_r1_forged_header_blocks_intake(self) -> None:
        forged = card_text().replace("secrets_masked: 0", "secrets_masked: broken").replace(
            "## 증상·요청\n첫 탭이 안 먹어요", "## 증상·요청\nsecrets_masked: 0")
        self.put(forged)
        r = self.e.run("ops_intake_sync.py", "intake")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual([n for n in self.e.notes() if "[ISSUE-REQ]" in n["body"]], [])
        self.assertIn("판정 불가", [n for n in self.e.notes() if "[OPS-REPLY]" in n["body"]][0]["body"])

    def test_r1_two_header_lines_block_intake(self) -> None:
        self.put(card_text().replace("secrets_masked: 0", "secrets_masked: 0\nsecrets_masked: 0"))
        r = self.e.run("ops_intake_sync.py", "intake")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual([n for n in self.e.notes() if "[ISSUE-REQ]" in n["body"]], [])

    def test_r2_paths_and_masked_secret_words_blocked(self) -> None:
        for bad, why in (("설정 경로 /etc/service/config.yaml 입니다.", "abs-path"),
                         ("~/Project/x/y.md 를 보세요", "home-path"),
                         ("토큰 *** 입니다.", "mask-mark"),
                         ("비밀번호 마스킹 했습니다", "mask-mark")):
            self.e.slack.calls.clear()
            (self.e.home / ".fable-team/comm/mailbox.jsonl").unlink(missing_ok=True)
            self.note(f"[OPS-REPLY] OPS-20261026-001\nthread_ts: 1793000000.000100\n{bad}")
            r = self.e.run("ops_intake_poster.py")
            self.assertEqual(r.returncode, 4, why)
            self.assertEqual(self.e.slack.posts(), [], why)

    def test_r3_queue_recounted_per_message(self) -> None:
        for i in range(3):
            r = subprocess.run(["bash", str(FT_MBOX_SH), "send", "byz-opsintake-master-claude#0", "byz-opsintake-tool-cmd#0", f"[OPS-NEW] {i}"],
                               capture_output=True, text=True,
                               env=dict(self.e.env, HOME=str(self.e.mini), FT_MBOX_DIR=str(self.e.mini / ".fable-team/comm")))
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        q = self.e.home / ".fable-team/comm/mailbox.jsonl"
        q.write_text("".join(json.dumps({"seq": 200 + i, "to": "x", "from": "y", "body": "z"}) + "\n" for i in range(9)))
        r = self.e.run("sat-mbox.py", "pull", "--seats", "byz-opsintake-master-claude#0")
        self.assertEqual(r.returncode, 5)
        self.assertIn("HOLD queue=10 remaining=2", r.stdout)
        self.assertEqual(len(self.e.notes(self.e.mini)), 2, "ack 이 남은 건까지 지웠다(다음 패스에서 사라짐)")

    def test_r4_ssh_over_7s_fails(self) -> None:
        slow = self.e.t / "slowssh.sh"
        slow.write_text('#!/usr/bin/env bash\nsleep 8\n')
        slow.chmod(0o755)
        start = __import__("time").monotonic()
        r = self.e.run("sat-mbox.py", "pull", "--seats", "byz-opsintake-master-claude#0", extra={"SAT_SSH": str(slow)})
        elapsed = __import__("time").monotonic() - start
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("7초 초과", r.stdout + r.stderr)
        self.assertLess(elapsed, 8.6, f"7초 상한을 안 걸었다({elapsed:.1f}s)")


class TestPostSecrets(Base):
    """ⓟ 카드 검출기가 비밀로 보는 값은 게시 경로에서도 게시 0 (두 쪽 판정이 같다)"""

    def note(self, text: str) -> None:
        body = f"[OPS-REPLY] OPS-20261026-001\nthread_ts: 1793000000.000100\n{text}"
        r = subprocess.run(["bash", str(FT_MBOX_SH), "send", "byz-opsintake-tool-cmd#0", "byz-opsintake-master-claude#0", body],
                           capture_output=True, text=True,
                           env=dict(self.e.env, FT_MBOX_DIR=str(self.e.home / ".fable-team/comm"), HOME=str(self.e.home)))
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def card_kinds(self, text: str) -> list[str]:
        sys.path.insert(0, str(KIT))
        import ops_intake_common as com
        return com.mask_text(text)[1]

    def test_p_every_card_secret_shape_blocked_on_post(self) -> None:
        shapes = [
            "토큰 ghp_abcdefghijklmnopqrstuvwxyz0123 더미 입니다.",      # ghp_ (DA r2 실제 입력)
            "토큰 xoxb-1234567890-abcdefghij 입니다.",                 # slack token
            "https://hooks.slack.com/services/T00000000/B00000000/abcdefghijklmnop",  # slack-webhook
            "PGPASSWORD=hunter2hunter2 로 접속",                        # pgpassword
            "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcdefghijklmnop",     # jwt
            "api_key=abcdefghijklmnopqrstuvwxyz0123456789",            # named-secret
            "토큰 sk-abcdefghijklmnopqrstuvwxyz012345 로 접속했어요",   # sk-key
            "postgres://admin:pass1234@db.example.com:5432/x",         # url-cred (값)
            "redis://:hunter2@cache.local:6379",                       # url-cred (값)
            "연락처 010-1234-5678 로 전화 주세요",                      # 전화(카드가 가리는 값)
            "메일 hong@example.com 으로 보냈습니다",                    # 이메일(카드가 가리는 값)
        ]
        for text in shapes:
            self.assertNotEqual(self.card_kinds(text), [], f"카드 검출기가 못 잡는 값: {text}")
            self.e.slack.calls.clear()
            self.e.slack.messages.clear()
            (self.e.home / ".fable-team/comm/mailbox.jsonl").unlink(missing_ok=True)
            self.note(text)
            r = self.e.run("ops_intake_poster.py")
            self.assertEqual(r.returncode, 4, text)
            self.assertEqual(self.e.slack.posts(), [], text)

    def test_p_masked_marker_and_paths_blocked(self) -> None:
        for text in ("토큰 *** 입니다.", "설정 경로 /etc/service/config.yaml 입니다."):
            self.e.slack.calls.clear()
            (self.e.home / ".fable-team/comm/mailbox.jsonl").unlink(missing_ok=True)
            self.note(text)
            r = self.e.run("ops_intake_poster.py")
            self.assertEqual(r.returncode, 4, text)
            self.assertEqual(self.e.slack.posts(), [], text)


class TestPostOnce(Base):
    """ⓠ 어떤 실패·재실행 순서에서도 같은 쪽지의 게시 요청은 1회를 넘지 않는다"""

    def note(self, text="확인 중입니다.") -> None:
        body = f"[OPS-REPLY] OPS-20261026-001\nthread_ts: 1793000000.000100\n{text}"
        r = subprocess.run(["bash", str(FT_MBOX_SH), "send", "byz-opsintake-tool-cmd#0", "byz-opsintake-master-claude#0", body],
                           capture_output=True, text=True,
                           env=dict(self.e.env, FT_MBOX_DIR=str(self.e.home / ".fable-team/comm"), HOME=str(self.e.home)))
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_q_broken_response_then_recover(self) -> None:
        self.note()
        self.e.slack.mode = "broken-after-save"
        r1 = self.e.run("ops_intake_poster.py")
        self.assertEqual(r1.returncode, 5, r1.stderr)
        self.assertIn("응답 불확실", r1.stderr)
        self.assertEqual(len(self.e.slack.posts()), 1)
        self.e.slack.mode = "ok"
        r2 = self.e.run("ops_intake_poster.py")  # 재실행 — 스레드에 표식이 보이므로 «보냄» 으로 맞춘다
        self.assertEqual(r2.returncode, 0, r2.stderr)
        self.assertIn("recovered", r2.stdout)
        self.assertEqual(len(self.e.slack.posts()), 1, "같은 쪽지를 두 번 게시했다")
        self.assertEqual(self.e.notes(), [], "확인했으면 쪽지를 지운다")

    def test_q_broken_before_save_then_error_not_repost(self) -> None:
        self.note()
        self.e.slack.mode = "broken-before-save"
        r1 = self.e.run("ops_intake_poster.py")
        self.assertEqual(r1.returncode, 5, r1.stderr)
        self.assertEqual(len(self.e.slack.posts()), 1)
        for _ in range(2):
            r = self.e.run("ops_intake_poster.py")
            self.assertEqual(r.returncode, 5, r.stdout + r.stderr)
            self.assertIn("확인 불가", r.stderr)
        self.assertEqual(len(self.e.slack.posts()), 1, "확인 못 한 쪽지를 다시 게시했다(요청 1회 초과)")
        self.assertEqual(len(self.e.notes()), 1, "못 보낸 쪽지는 지우지 않는다(사람이 본다)")

    def test_q_lock_serializes_runs(self) -> None:
        """잠금은 «결정적» 으로 본다 — 다른 프로세스가 원장 잠금을 쥐고 있으면 게시기는 기다린다."""
        import fcntl
        self.note()
        lock_path = self.e.home / ".fable-team/ops-intake/state/posted.lock"
        lock_path.parent.mkdir(parents=True, exist_ok=True)
        holder = open(lock_path, "w")
        fcntl.flock(holder, fcntl.LOCK_EX)
        p = subprocess.Popen([PY, str(KIT / "ops_intake_poster.py")], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             text=True, env=dict(self.e.env), cwd=str(self.e.t))
        __import__("time").sleep(1.2)
        self.assertIsNone(p.poll(), "잠금을 쥐고 있는데도 게시기가 그냥 지나갔다")
        self.assertEqual(self.e.slack.posts(), [], "잠금 전에 게시했다")
        holder.close()  # 잠금 해제
        _out, err = p.communicate(timeout=60)
        self.assertEqual(p.returncode, 0, err)
        self.assertEqual(len(self.e.slack.posts()), 1)

    def test_q_concurrent_runs_post_once(self) -> None:
        self.note()
        self.e.slack.delay = 0.6  # 두 프로세스가 겹치는 창을 실제로 연다
        env = dict(self.e.env)
        p1 = subprocess.Popen([PY, str(KIT / "ops_intake_poster.py")], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              text=True, env=env, cwd=str(self.e.t))
        p2 = subprocess.Popen([PY, str(KIT / "ops_intake_poster.py")], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              text=True, env=env, cwd=str(self.e.t))
        outs = [(p.communicate(timeout=60), p.returncode) for p in (p1, p2)]
        self.assertEqual(len(self.e.slack.posts()), 1, "동시 실행에서 같은 쪽지를 두 번 게시했다")
        self.assertTrue(any(rc == 0 for _o, rc in outs), outs)

    def test_q_lookup_failure_is_error_not_repost(self) -> None:
        self.note()
        self.e.slack.mode = "broken-after-save"
        self.e.run("ops_intake_poster.py")
        self.assertEqual(len(self.e.slack.posts()), 1)
        r = self.e.run("ops_intake_poster.py", extra={"OPS_SLACK_BASE": "http://127.0.0.1:1/"})
        self.assertEqual(r.returncode, 5, r.stdout + r.stderr)
        self.assertIn("확인 불가", r.stderr)
        self.assertEqual(len(self.e.slack.posts()), 1)


SPLIT = {  # 값을 «쪼개는» 문자 — 정규화 전에 검출하면 토큰이 빠져나간다
    "cr": "\r", "lf": "\n", "tab": "\t", "zwsp": "\u200b", "bell": "\x07",
}


def split_secret(value: str, sep: str) -> str:
    mid = len(value) // 2
    return value[:mid] + sep + value[mid:]


class TestNormalize(Base):
    """ⓡ 제어문자·줄바꿈으로 쪼개도 공용 꼴의 어떤 값도 카드에 원문으로 남지 않는다"""

    def test_r_one_split_shapes_all_kinds(self) -> None:
        sys.path.insert(0, str(SLACK_LIB))
        sys.path.insert(0, str(BIN))
        from ft_secret_shapes import RULES
        import post_guard
        shared = {k for k, _ in RULES} | set(post_guard.SECRETS)
        samples = {
            "token-prefix": "ghp_abcdefghijklmno" + "pqrstuvwxyz0123",
            "aws-key": "AKIAIOSFODNN7EXAMPLE",
            "slack-token-a": "xoxa-1234567890abcdef",
            "private-key": "-----BEGIN OPENSSH PRIVATE KEY-----",
            "password-assign": "password=hunter2hunter2",
            "pgpassword": "PGPASSWORD=hunter2hunter2",
            "dsn-scheme": "postgres://user1:pw1234@db.example.com:5432/x",
            "slack-webhook": "https://hooks.slack.com/services/T00000000/B00000000/abcdefghijklmnop",
            "jwt": "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcdefghijklmnop",
            "sk-key": "sk-" + "abcdefghijklmnopqrstuvwxyz012345",
            "slack-token": "xoxb-1234567890-abcdefghij",
        }
        # 두 정본(ft_secret_shapes.RULES · post_guard.SECRETS)의 합집합을 표가 덮는지 — 빠지면 표를 고친다
        covered = {"url-cred", "token-prefix", "slack-webhook", "jwt", "pgpassword", "aws-key",
                   "private-key", "password", "postgres-dsn", "redis-dsn", "sk-key", "slack-token"}
        self.assertEqual(shared, covered, f"공용 꼴 목록이 바뀌었다 — 시험 표를 고쳐야 한다: {sorted(shared)}")
        tick = 0
        for kind, value in samples.items():
            for sep_name, sep in SPLIT.items():
                text = split_secret(value, sep)
                card_index = len(self.e.cards())
                tick += 601  # 한도창(600초)을 매번 넘긴다 — 값 시험이 한도에 막히지 않게
                r = self.e.run("ops_intake_write.py", stdin=json.dumps(dict(CARD, symptom=text)),
                               extra={"FT_NOW": str(1793000000 + tick)})
                self.assertEqual(r.returncode, 0, f"{kind}/{sep_name}: {r.stderr}")
                card = self.e.cards()[card_index].read_text()
                for piece in value.split("@"):
                    self.assertNotIn(piece, card, f"{kind}/{sep_name} 값이 남았다")
                self.assertRegex(card, r"secrets_masked: [1-9]", f"{kind}/{sep_name} 검출 0")
                sys.path.insert(0, str(BIN))
                from ft_secret_shapes import mask as _m
                self.assertEqual(_m(card)[1], [], f"{kind}/{sep_name} 카드에 원문이 남았다")

    def test_r_masked_before_cr_removed_regression(self) -> None:
        """DA r3 반례 1 그대로 — 마스킹 «뒤» 에 CR 을 지우면 토큰이 다시 합쳐진다."""
        value = "ghp_abcdefghijklmno\rpqrstuvwxyz0123"
        r = self.e.run("ops_intake_write.py", stdin=json.dumps(dict(CARD, symptom=value)))
        self.assertEqual(r.returncode, 0, r.stderr)
        card = self.e.cards()[0].read_text()
        self.assertNotIn("ghp_abcdefghijklmnopqrstuvwxyz0123", card)
        self.assertNotIn("ghp_abcdefghijklmno", card)
        self.assertRegex(card, r"secrets_masked: [1-9]")


class TestSharedShapes(Base):
    """ⓢ 게시·원장 경로도 같은 꼴 목록 — aws-key 등도 게시 0 · 원장에 값 0"""

    def note(self, text: str) -> None:
        body = f"[OPS-REPLY] OPS-20261026-001\nthread_ts: 1793000000.000100\n{text}"
        r = subprocess.run(["bash", str(FT_MBOX_SH), "send", "byz-opsintake-tool-cmd#0", "byz-opsintake-master-claude#0", body],
                           capture_output=True, text=True,
                           env=dict(self.e.env, FT_MBOX_DIR=str(self.e.home / ".fable-team/comm"), HOME=str(self.e.home)))
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_s_all_shared_shapes_blocked_and_not_in_ledger(self) -> None:
        samples = [
            "키 AKIAIOSFODNN7EXAMPLE 입니다.",
            "-----BEGIN OPENSSH PRIVATE KEY-----",
            "password=hunter2hunter2",
            "postgres://user1:pw1234@db.example.com:5432/x",
            "xoxa-1234567890abcdef",
            "토큰 ghp_abcdefghijklmnopqrstuvwxyz0123",
            "PGPASSWORD=hunter2hunter2",
            "https://hooks.slack.com/services/T00000000/B00000000/abcdefghijklmnop",
        ]
        for text in samples:
            self.e.slack.calls.clear()
            (self.e.home / ".fable-team/comm/mailbox.jsonl").unlink(missing_ok=True)
            self.note(text)
            r = self.e.run("ops_intake_poster.py")
            self.assertEqual(r.returncode, 4, text)
            self.assertEqual(self.e.slack.posts(), [], text)
        ledger = (self.e.home / ".fable-team/ops-intake/state/posted.json")
        blob = ledger.read_text() if ledger.is_file() else ""
        for value in ("AKIAIOSFODNN7EXAMPLE", "hunter2hunter2", "pw1234", "ghp_abcdefghijklmnopqrstuvwxyz0123"):
            self.assertNotIn(value, blob, "원장에 값이 남았다")


class TestWriteLock(Base):
    """ⓣ 같은 사용자 동시 실행 — 카드 수 ≤ 한도 · 예외 0"""

    def test_t_concurrent_same_user(self) -> None:
        for i in range(4):
            r = self.e.run("ops_intake_write.py", stdin=json.dumps(CARD), extra={"FT_NOW": str(1793000000 + i)})
            self.assertEqual(r.returncode, 0, r.stderr)
        env = dict(self.e.env, FT_NOW=str(1793000100))
        procs = [subprocess.Popen([PY, str(KIT / "ops_intake_write.py")], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env, cwd=str(self.e.t))
                 for _ in range(4)]
        outs = [p.communicate(json.dumps(CARD), timeout=120) for p in procs]
        for (out, err), p in zip(outs, procs):
            self.assertNotIn("Traceback", err, err)
            self.assertIn(p.returncode, (0, 3), (out, err))
        self.assertLessEqual(len(self.e.cards()), 5, "한도(5건)를 넘겨 카드가 만들어졌다")
        self.assertGreaterEqual(len(self.e.cards()), 5)
        json.loads((self.e.home / ".fable-team/ops-intake/state/limits.json").read_text())


class TestWallClock(Base):
    """ⓤ 1바이트씩 흘리는 슬랙·SSH — 7.5초 안 끝나고 게시 성공 0"""

    def test_u_dribbling_slack_bounded(self) -> None:
        body = "[OPS-REPLY] OPS-20261026-001\nthread_ts: 1793000000.000100\n확인 중입니다."
        subprocess.run(["bash", str(FT_MBOX_SH), "send", "byz-opsintake-tool-cmd#0", "byz-opsintake-master-claude#0", body],
                       capture_output=True, text=True,
                       env=dict(self.e.env, FT_MBOX_DIR=str(self.e.home / ".fable-team/comm"), HOME=str(self.e.home)))
        self.e.slack.mode = "dribble"
        start = __import__("time").monotonic()
        r = self.e.run("ops_intake_poster.py")
        elapsed = __import__("time").monotonic() - start
        self.assertLess(elapsed, 7.6, f"벽시계 상한이 안 걸렸다({elapsed:.1f}s)")
        self.assertEqual(r.returncode, 5, r.stdout + r.stderr)
        self.assertIn("불확실", r.stderr)
        self.assertEqual(len(self.e.slack.posts()), 1)
        ledger = json.loads((self.e.home / ".fable-team/ops-intake/state/posted.json").read_text())
        self.assertEqual([v["state"] for v in ledger.values()], ["failed"], "실패를 성공으로 기록했다")

    def test_u_dribbling_ssh_bounded(self) -> None:
        slow = self.e.t / "dribssh.sh"
        slow.write_text('#!/usr/bin/env bash\nfor i in $(seq 40); do printf x; sleep 0.45; done\n')
        slow.chmod(0o755)
        start = __import__("time").monotonic()
        r = self.e.run("sat-mbox.py", "pull", "--seats", "byz-opsintake-master-claude#0", extra={"SAT_SSH": str(slow)})
        elapsed = __import__("time").monotonic() - start
        self.assertLess(elapsed, 7.6, f"벽시계 상한이 안 걸렸다({elapsed:.1f}s)")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("7초 초과", r.stdout + r.stderr)


class TestR5(Base):
    """ⓥ DA⑥ r4 반례 3칸 그대로 — 공백 뺸 비밀번호 · 개인키 본문 · 종료 청크 뒤 시간 검사"""

    def test_v_space_split_password_value_gone(self) -> None:
        """R1: `password=\\nhunter2hunter2` — 머리표만 가리고 값을 버리면 안 된다."""
        r = self.e.run("ops_intake_write.py", stdin=json.dumps(dict(CARD, symptom="password=\nhunter2hunter2")))
        self.assertEqual(r.returncode, 0, r.stderr)
        text = self.e.cards()[0].read_text()
        self.assertNotIn("hunter2", text, "비밀번호 값이 남았다")
        self.assertRegex(text, r"secrets_masked: [1-9]")

    def test_v_pem_block_removed_whole(self) -> None:
        """R2: 개인키는 BEGIN~END 블록을 통째로 지운다 — 줄 단위로는 본문이 남는다."""
        pem = "-----BEGIN OPENSSH PRIVATE KEY-----\nAAAAB3NzaC1yc2EAAAADAQAB\nBBBBDd==\n-----END OPENSSH PRIVATE KEY-----"
        r = self.e.run("ops_intake_write.py", stdin=json.dumps(dict(CARD, symptom=pem)))
        self.assertEqual(r.returncode, 0, r.stderr)
        text = self.e.cards()[0].read_text()
        for leaked in ("AAAAB3NzaC1yc2EAAAADAQAB", "BBBBDd==", "BEGIN OPENSSH PRIVATE KEY"):
            self.assertNotIn(leaked, text, leaked)
        self.assertRegex(text, r"secrets_masked: [1-9]")

    def test_v_leftover_after_mask_rejects(self) -> None:
        """가림 뒤 공용 판정이 남으면 접수 거절 — 4조각으로 쪼갠 토큰(붙일 수 없는 모양)."""
        split = "g h p _ a b c d e f g h i j k l m n o p q r s t u v w x y z 0 1 2 3"
        r = self.e.run("ops_intake_write.py", stdin=json.dumps(dict(CARD, symptom=split)))
        self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
        self.assertIn("가림 뒤 비밀 잔여", r.stderr)
        self.assertEqual(self.e.cards(), [])
        self.assertEqual(self.e.notes(), [])

    def test_v_slow_finish_counts_wall_clock(self) -> None:
        """R3: 4초에 성공 청크 · 8초에 종료 — 전체 벽시계 7초를 넘으면 sent 0 · 원장 failed."""
        body = "[OPS-REPLY] OPS-20261026-001\nthread_ts: 1793000000.000100\n확인 중입니다."
        subprocess.run(["bash", str(FT_MBOX_SH), "send", "byz-opsintake-tool-cmd#0", "byz-opsintake-master-claude#0", body],
                       capture_output=True, text=True,
                       env=dict(self.e.env, FT_MBOX_DIR=str(self.e.home / ".fable-team/comm"), HOME=str(self.e.home)))
        self.e.slack.mode = "slow-finish"
        start = __import__("time").monotonic()
        r = self.e.run("ops_intake_poster.py")
        elapsed = __import__("time").monotonic() - start
        self.assertLess(elapsed, 7.6, f"전체 벽시계 상한이 안 걸렸다({elapsed:.1f}s)")
        self.assertEqual(r.returncode, 5, r.stdout + r.stderr)
        self.assertIn("불확실", r.stderr)
        self.assertNotIn("POST ok", r.stdout, "실패인데 성공으로 세었다(sent)")
        ledger = json.loads((self.e.home / ".fable-team/ops-intake/state/posted.json").read_text())
        self.assertEqual([v["state"] for v in ledger.values()], ["failed"], "원장 failed 가 아니다")

    def test_v_shared_shape_single_token_masked(self) -> None:
        """공용 규칙표에만 있는 꼴(aws-key)도 카드에서 «가려» 진다 — 자체 정규식으로 줄이면 거절이나 누출이 된다."""
        r = self.e.run("ops_intake_write.py", stdin=json.dumps(dict(CARD, symptom="키 AKIAIOSFODNN7EXAMPLE 입니다")))
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        text = self.e.cards()[0].read_text()
        self.assertNotIn("AKIAIOSFODNN7EXAMPLE", text)
        self.assertRegex(text, r"secrets_masked: [1-9]")


MUTATIONS = {
    # 이름: (파일, 원문, 바꿀 글, 이 변이가 깨야 하는 축)
    "mask-off": ("ops_intake_common.py", "        masked, cnt = rx.subn(ph, masked)", "        masked, cnt = masked, 0", "b-secrets"),
    "rescan-off": ("ops_intake_sync.py", "    if declared > 0 or kinds:", "    if declared > 0:", "b2-rescan"),
    "declared-off": ("ops_intake_sync.py", "        declared = None if body_forges_mask(text) else declared_masked(text)", "        declared = 0", "b3-declared"),
    "guard-ts": ("ops_intake_poster.py", '    if not m_t:', '    if not m_t and False:', "d-thread-ts"),
    # 원장 확인을 끔 → 같은 쪽지를 두 번 게시
    "ledger-off": ("ops_intake_poster.py", '            if entry.get("state") == "sent":', "            if False:", "d-dup"),
    "notice-off": ("ops_intake_sync.py", '        if str(cm.get("id")) in seen or not body.lstrip().startswith(NOTICE):', '        if True:', "e-notice"),
    # 머리 블록 한정 + 본문 위조 차단을 «고치기 전» 꼴(문서 전체 첫 일치)로 되돌린다
    "header-block-off": ("ops_intake_sync.py", "        declared = None if body_forges_mask(text) else declared_masked(text)",
                         "        declared = int(re.search(r'(?m)^secrets_masked:\\s*(\\d+)\\s*$', text).group(1))", "r1-forged"),
    "path-rule-off": ("ops_intake_poster.py", "    if PATH_RX.search(text):", "    if False:", "d-path"),
    "queue-recount-off": ("sat-mbox.py", "    for idx, row in enumerate(rows):\n        q = queue_len()", "    q = queue_len()\n    for idx, row in enumerate(rows):", "r3-queue"),
    "timeout-off": ("sat-mbox.py", "CALL_TIMEOUT = 7", "CALL_TIMEOUT = 30", "f-7s"),
    # 게시 쪽 검사기를 따로 둠(카드 검출기와 무관) → ⓟ FAIL
    "poster-secrets-off": ("ops_intake_poster.py", "    secrets(text)\n    _ml, pg = slack_lib()", "    _ml, pg = slack_lib()", "p-secrets"),
    # 마스킹 «뒤» 에 CR 을 지움(DA r3 반례 1 그대로) → ⓡ FAIL
    "cr-after-mask-off": ("ops_intake_common.py", "    masked, split = _mask_split_runs(masked)  # ⑤ 공백으로 쪼갠 값",
                          "    split = []\n    masked = normalize(masked)", "r_"),
    # 자체 정규식을 되살림(공용 판정·가림 대신 자기 꼴) → ⓥ(남은 비밀 거절 칸) FAIL (카드 r5 반례 1)
    "own-mask-regex-off": ("ops_intake_common.py",
                           "    kinds = [k for k, _ln in _ft_mask()(text)[1]]\n"
                           "    for name, pat in _pg_secrets().items():\n"
                           "        if re.search(pat, text):\n            kinds.append(name)\n    return kinds",
                           "    import re as _re\n    return ['sk-key'] if _re.search(r'sk-[A-Za-z0-9]{16,}', text) else []", "r5-mask"),
    # 접수 도구 «전용» 꼴 목록(공용 목록 안 씀) → ⓢ FAIL
    "own-rules-off": ("ops_intake_common.py", "                from ft_secret_shapes import mask  # 정본 규칙 — 복제 0\n                return mask",
                      "                import re as _re\n                _RX = _re.compile(r'sk-[A-Za-z0-9]{16,}')\n"
                      "                def _local(t):\n                    h = [('sk-key', 1)] if _RX.search(t) else []\n                    return _RX.sub('***', t), h\n"
                      "                return _local", "s_"),
    # 잠금 범위를 원장에만(카드 쓰기는 밖) → ⓣ FAIL
    "lock-scope-off": ("ops_intake_write.py", '        with c.locked("ops-intake"):  # ★한도 확인부터 쪽지 예약까지 한 잠금★ (DA r3 반례 3)\n            return _write_locked(doc)',
                       "        return _write_locked(doc)", "t_"),
    # 소켓 timeout 만(읽기 루프 없음) → ⓤ FAIL
    # 감시 타이머를 빼고 «읽기 전» 만 검사(막힌 recv 를 끊지 못함) → ⓥ FAIL (카드 r5 반례 3)
    "read-only-timeout": ("ops_intake_poster.py",
                          "        timer = threading.Timer(max(0.0, left()), _abort)\n"
                          "        timer.daemon = True\n        timer.start()\n",
                          "        _abort = lambda: None\n", "r5-7s"),
    # 원장 잠금을 끔 → 동시 실행에서 두 번 게시
    "lock-off": ("ops_intake_poster.py", "    lock = lock_ledger()", "    lock = open(c.sub(\"state\") / \"posted.lock\", \"w\")", "q-lock"),
    # 원장 기록을 «성공 뒤» 로(보내는 중 선기록 제거) → ⓠ FAIL
    "ledger-after-post-off": ("ops_intake_poster.py",
                              '            ledger[key] = {"state": "sending", "channel": ch, "ts": ts, "ops_id": ops_id, "key": key}  # 본문은 원장에 남기지 않는다\n'
                              '            c.write_json(ledger_path, ledger)  # ★기록 먼저★ — 보내는 중에 죽어도 «모르는 게시» 가 안 생긴다\n'
                              '            try:\n'
                              '                post_bounded(base, tok, ch, body_text, ts)\n'
                              '            except BaseException:  # 전체 벽시계 초과·깨진 응답 = sent 0 · 원장 failed(카드 r5)\n'
                              '                ledger[key] = dict(ledger[key], state="failed")\n'
                              '                c.write_json(ledger_path, ledger)\n'
                              '                raise\n'
                              '            ledger[key] = dict(ledger[key], state="sent")',
                              '            post_bounded(base, tok, ch, body_text, ts)\n'
                              '            ledger[key] = {"state": "sent", "channel": ch, "ts": ts, "ops_id": ops_id, "key": key}',
                              "q-once")
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
