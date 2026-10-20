"""byz_slack_mbox_inbound 옵션 2(허용 사용자 N명 · 수신 좌석 고정) + install-inbound.sh 2번째 인스턴스 «설치만» (R205 · 설계 §8 ②).

가짜 Slack·가짜 mbox·임시 HOME·launchctl 대역 — 진짜 슬랙 게시·launchctl load·진짜 명부 쓰기 0.
실행: python3 -m pytest tests/scripts/test_inbound_humans_and_install.py -q
"""
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

import pytest
from _slack_fakes import FakeSlack

HERE = Path(__file__).resolve().parent
KIT = HERE.parents[1] / "kit" / "slack-mirror"  # r516: parents[1] = 팩 harness/ (r386 이전 글자 치환이 harness/ 를 한 번 더 붙였다)
SCRIPT = KIT / "byz_slack_mbox_inbound.py"
INSTALLER = KIT / "install-inbound.sh"
OPPA, SANGAE, STRANGER = "U0AC2JF0M7D", "U0SANGAE001", "U0STRANGER9"
DESK = "byz-planner-desk-claude#0"
WORKER = "fixture-worker#1"
BASE_SHA = "6d7b2ee804"  # R205 착수 전 HEAD — 옛 키트(옵션 없는 1번째 인스턴스 기준선)
sys.path.insert(0, str(KIT))
import mirror_questions as mq  # noqa: E402


@pytest.fixture
def slack():
    s = FakeSlack()
    yield s
    s.srv.shutdown()


@pytest.fixture
def env(tmp_path: Path) -> Path:
    (tmp_path / "comm").mkdir()
    shutil.copy(HERE / "_fake_mbox.sh", tmp_path / "comm" / "mbox.sh")
    (tmp_path / "tok.env").write_text("YOONHWAN_BOT_TOKEN=xoxp-test\n", encoding="utf-8")
    (tmp_path / "seats-planner.json").write_text(json.dumps({"_slack_users": {OPPA: "오빠", SANGAE: "sangae 언니"}, "_desk": DESK}), encoding="utf-8")
    return tmp_path


def run(env: Path, slack: FakeSlack, *who: str, **extra: str):
    e = {**os.environ, "FAKE_MBOX": str(env / "comm" / "mbox.sh"), "MIRROR_TMUX": f"sh {env}/tmux-spy.sh", **extra}
    (env / "tmux-spy.sh").write_text(f"echo \"$@\" >> {env}/tmux.calls\nexit 0\n", encoding="utf-8")
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--channel", "C1", *who, "--mbox", str(env / "comm" / "mbox.sh"),
         "--seats-file", str(env / "seats-planner.json"), "--state-dir", str(env / "st"), "--token-file", str(env / "tok.env"),
         "--api-base", slack.base, "--inbox-bin", str(HERE / "_fake_inbox.sh"), "--once"], capture_output=True, text=True, timeout=60, env=e)


def queue(env: Path) -> list[dict]:
    p = env / "comm" / "mailbox.jsonl"
    return [json.loads(ln) for ln in p.read_text(encoding="utf-8").splitlines()] if p.exists() else []


def ready(env: Path, slack: FakeSlack, *who: str) -> None:
    assert run(env, slack, *who).returncode == 0  # baseline 만 만든다
    time.sleep(0.01)


def test_humans_from_seats_delivers_each_registered_user_to_the_fixed_seat_and_drops_others(env: Path, slack: FakeSlack):
    ready(env, slack, "--humans-from-seats", "--to-key", "_desk")
    slack.human("오빠 글", user=OPPA)
    slack.human("언니 글", user=SANGAE)
    slack.human("남의 글", user=STRANGER)
    r = run(env, slack, "--humans-from-seats", "--to-key", "_desk")
    assert r.returncode == 0, r.stderr
    rows = queue(env)
    assert [x["to"] for x in rows] == [DESK, DESK] and "오빠 글" in rows[0]["body"] and "언니 글" in rows[1]["body"]
    assert all("남의 글" not in x["body"] for x in rows)  # 허용 밖 사용자 = 좌석 도달 0
    assert r.stderr.count("ignored") == 1 and STRANGER in r.stderr and "남의 글" not in r.stderr  # 로그 1줄 · 본문 0
    assert run(env, slack, "--humans-from-seats", "--to-key", "_desk").returncode == 0 and len(queue(env)) == 2  # 재실행 중복 0


def asked(env: Path) -> set[str]:
    """tmux 대역이 받은 has-session 대상 — 명부 키로 정한 좌석만 물어야 한다."""
    p = env / "tmux.calls"
    return {ln.split()[-1] for ln in p.read_text(encoding="utf-8").splitlines()} if p.exists() else set()


def test_fixed_key_reads_the_roster_key_and_asks_only_that_seat(env: Path, slack: FakeSlack):
    ready(env, slack, "--humans-from-seats", "--to-key", "_desk")
    slack.human("글", user=OPPA)
    assert run(env, slack, "--humans-from-seats", "--to-key", "_desk").returncode == 0
    assert asked(env) == {f"={DESK}"}  # 명부 `_desk` 의 좌석만 has-session 확인 · `_master` 조회 0
    assert [x["to"] for x in queue(env)] == [DESK]


def test_humans_list_option(env: Path, slack: FakeSlack):
    ready(env, slack, "--humans", f"{OPPA},{SANGAE}", "--to-key", "_desk")
    slack.human("가", user=SANGAE)
    slack.human("나", user=STRANGER)
    assert run(env, slack, "--humans", f"{OPPA},{SANGAE}", "--to-key", "_desk").returncode == 0
    assert [x["to"] for x in queue(env)] == [DESK] and "가" in queue(env)[0]["body"]


@pytest.mark.parametrize("who", [[], ["--human", OPPA, "--humans", OPPA], ["--human", OPPA, "--humans-from-seats"], ["--humans", OPPA, "--humans-from-seats"]])
def test_human_options_are_mutually_exclusive_and_one_is_required(env: Path, slack: FakeSlack, who: list[str]):
    r = run(env, slack, *who)
    assert r.returncode == 2 and queue(env) == []


@pytest.mark.parametrize("seats", ["없음", "{broken", '{"_master": "x"}', '{"_slack_users": {}}'])
def test_seat_registry_failure_or_empty_users_raises(env: Path, slack: FakeSlack, seats: str):
    p = env / "seats-planner.json"
    p.unlink() if seats == "없음" else p.write_text(seats, encoding="utf-8")
    r = run(env, slack, "--humans-from-seats", "--to-key", "_desk")
    assert r.returncode == 1 and "ERROR" in r.stderr and queue(env) == []


def test_single_human_option_keeps_the_first_instance_behavior(env: Path, slack: FakeSlack):
    (env / "seats-planner.json").write_text(json.dumps({"_master": "byz-planner-master-claude#9"}), encoding="utf-8")
    ready(env, slack, "--human", OPPA)
    slack.human("새 요청", user=OPPA)
    slack.human("남의 글", user=SANGAE)
    assert run(env, slack, "--human", OPPA).returncode == 0
    assert [x["to"] for x in queue(env)] == ["byz-planner-master-claude#9"]  # 옵션 없음 = 현역 planner(명부 `_master` + tmux) 조회
    assert (env / "tmux.calls").exists()


def bot_root(slack: FakeSlack, text: str) -> str:
    ts = f"{time.time() + len(slack.msgs) * 0.001:.6f}"
    slack.msgs.append({"ts": ts, "text": text, "thread_ts": "", "bot_id": "B1"})
    return ts


FIXED = ("--humans-from-seats", "--to-key", "_desk")


def test_fixed_to_open_question_thread_reaches_only_the_desk_and_leaves_the_question_open(env: Path, slack: FakeSlack):
    ready(env, slack, *FIXED)
    t = bot_root(slack, "#820 시작 — x")
    (env / "st").mkdir(exist_ok=True)
    qpath = env / "st" / "byz_slack_questions.C1.json"
    mq.add(qpath, 100, {"key": "#820", "seat": WORKER, "what": "질문", "options": [], "thread_ts": t})
    slack.human("그렇게 해 주세요", t, user=SANGAE)
    assert run(env, slack, *FIXED).returncode == 0
    assert [x["to"] for x in queue(env)] == [DESK] and "그렇게 해 주세요" in queue(env)[0]["body"]  # 질문 좌석 도달 0 · desk 1통
    assert asked(env) == {f"={DESK}"}  # desk 만 조회 · planner 조회 0
    assert mq.load(qpath)["open"]["100"]["state"] != "delivered"  # desk 도달만으로 질문 상태를 전진시키지 않는다


def test_fixed_to_confirm_answer_does_not_close_the_question(env: Path, slack: FakeSlack):
    ready(env, slack, *FIXED)
    t = bot_root(slack, "#820 시작 — x")
    (env / "st").mkdir(exist_ok=True)
    qpath = env / "st" / "byz_slack_questions.C1.json"
    mq.add(qpath, 100, {"key": "#820", "seat": WORKER, "what": "질문", "options": [], "thread_ts": t})
    mq.set_delivered(qpath, 100, "1.0", 1)
    slack.human("확인", t, user=OPPA)
    assert run(env, slack, *FIXED).returncode == 0
    assert [x["to"] for x in queue(env)] == [DESK] and "100" in mq.load(qpath)["open"]


def test_fixed_to_inferred_seat_thread_reaches_only_the_desk(env: Path, slack: FakeSlack):
    ready(env, slack, *FIXED)
    t = bot_root(slack, f"[작업상황] x\n본문\n({WORKER} · #820)")  # 열린 질문 없음 — 봇 글 꼬리 줄이 좌석을 추정시킨다
    slack.human("답", t, user=OPPA)
    assert run(env, slack, *FIXED).returncode == 0
    assert [x["to"] for x in queue(env)] == [DESK] and asked(env) == {f"={DESK}"}


def test_without_fixed_to_the_question_seat_still_gets_its_answer(env: Path, slack: FakeSlack):
    (env / "seats-planner.json").write_text(json.dumps({"_master": "byz-planner-master-claude#9"}), encoding="utf-8")
    ready(env, slack, "--human", OPPA)
    t = bot_root(slack, "#820 시작 — x")
    (env / "st").mkdir(exist_ok=True)
    mq.add(env / "st" / "byz_slack_questions.C1.json", 100, {"key": "#820", "seat": WORKER, "what": "질문", "options": [], "thread_ts": t})
    slack.human("네", t, user=OPPA)
    assert run(env, slack, "--human", OPPA).returncode == 0
    assert sorted(x["to"] for x in queue(env)) == sorted([WORKER, "byz-planner-master-claude#9"])  # 기존 모드 불변


def _legacy_kit(tmp: Path) -> Path:
    if subprocess.run(["git", "-C", str(HERE), "cat-file", "-e", f"{BASE_SHA}^{{commit}}"], capture_output=True).returncode != 0:
        pytest.skip(f"기준 커밋 {BASE_SHA} 이 이 클론에 없다(얕은 클론) — 아래 stderr 단언 시험이 같은 계약을 지킨다")
    dst = tmp / "legacy"
    dst.mkdir()
    tar = subprocess.run(["git", "-C", str(HERE.parents[1]), "archive", BASE_SHA, "harness/kit/slack-mirror"], capture_output=True, check=True).stdout
    subprocess.run(["tar", "-x", "-C", str(dst)], input=tar, check=True)
    return dst / "harness" / "kit" / "slack-mirror" / "byz_slack_mbox_inbound.py"


def _args(env: Path, slack: FakeSlack, state: str) -> list[str]:
    return ["--channel", "C1", "--human", OPPA, "--mbox", str(env / "comm" / "mbox.sh"), "--seats-file", str(env / "seats-planner.json"),
            "--state-dir", str(env / state), "--token-file", str(env / "tok.env"), "--api-base", slack.base, "--inbox-bin", str(HERE / "_fake_inbox.sh"), "--once"]


def test_single_human_mode_is_byte_identical_to_the_pre_r205_kit_for_stranger_posts(env: Path, slack: FakeSlack, tmp_path: Path):
    legacy = _legacy_kit(tmp_path)
    (env / "seats-planner.json").write_text(json.dumps({"_master": "byz-planner-master-claude#9"}), encoding="utf-8")
    e = {**os.environ, "FAKE_MBOX": str(env / "comm" / "mbox.sh"), "MIRROR_TMUX": "true"}
    for script, state in ((legacy, "st-old"), (SCRIPT, "st-new")):
        assert subprocess.run([sys.executable, str(script), *_args(env, slack, state)], capture_output=True, text=True, timeout=60, env=e).returncode == 0
    slack.human("오빠", user=OPPA)
    slack.human("남의 글", user=STRANGER)
    out = []
    for script, state in ((legacy, "st-old"), (SCRIPT, "st-new")):
        r = subprocess.run([sys.executable, str(script), *_args(env, slack, state)], capture_output=True, text=True, timeout=60, env=e)
        out.append((r.returncode, r.stdout, r.stderr))
    assert out[0] == out[1] and "ignored" not in out[1][2]
    assert [x["to"] for x in queue(env)] == ["byz-planner-master-claude#9"] * 2  # 옛·새 각 1통(허용 밖 글 도달 0)


def test_single_human_mode_logs_nothing_for_stranger_posts_but_multi_user_mode_logs_once(env: Path, slack: FakeSlack):
    (env / "seats-planner.json").write_text(json.dumps({"_master": "byz-planner-master-claude#9", "_slack_users": {OPPA: "오빠"}}), encoding="utf-8")
    ready(env, slack, "--human", OPPA)
    slack.human("남의 글", user=STRANGER)
    assert "ignored" not in run(env, slack, "--human", OPPA).stderr
    ready(env, slack, "--humans-from-seats", "--to-key", "_desk")
    assert run(env, slack, "--humans-from-seats", "--to-key", "_desk").stderr.count("ignored") == 1


# --- 설치기 -----------------------------------------------------------------------------------
@pytest.fixture
def home(tmp_path: Path) -> tuple[Path, dict[str, str]]:
    h = tmp_path / "home"
    (h / ".hermes" / "secrets").mkdir(parents=True)
    tok = h / ".hermes" / "secrets" / "yoonhwan_bot.env"
    tok.write_text("YOONHWAN_BOT_TOKEN=x\n")
    tok.chmod(0o600)
    shim = tmp_path / "shim"
    shim.mkdir()
    (shim / "launchctl").write_text(f"#!/bin/sh\necho \"$@\" >> {tmp_path}/launchctl.calls\n", encoding="utf-8")
    (shim / "launchctl").chmod(0o755)
    root = tmp_path / "root"
    (root / ".fable-team" / "comm").mkdir(parents=True)
    (root / ".fable-team" / "comm" / "mbox.sh").write_text("#!/bin/sh\n")
    (root / ".fable-team" / "seats-harness.json").write_text("{}")
    e = {**os.environ, "HOME": str(h), "BYZ_ROOT": str(root), "FT_INBOX_BIN": str(HERE / "_fake_inbox.sh"), "MIRROR_PY": sys.executable,
         "PATH": f"{shim}:{os.environ['PATH']}"}
    return tmp_path, e


def install(e: dict[str, str], *args: str):
    return subprocess.run(["bash", str(INSTALLER), *args], capture_output=True, text=True, timeout=60, env=e)


TALK = ["--label", "com.hermes.byz-slack-talk-inbound", "--channel", "C0TALK12345", "--to-key", "_desk", "--humans-from-seats"]


def test_second_instance_writes_the_plist_file_only_and_never_calls_launchctl(home):
    tmp, e = home
    r = install(e, *TALK)
    assert r.returncode == 0, r.stderr
    assert r.stdout.startswith("INSTALLED-NOT-LOADED com.hermes.byz-slack-talk-inbound")
    plist = Path(e["HOME"]) / "Library/LaunchAgents/com.hermes.byz-slack-talk-inbound.plist"
    text = plist.read_text(encoding="utf-8")
    assert "<string>--humans-from-seats</string>" in text and "<string>--to-key</string><string>_desk</string>" in text and "<string>C0TALK12345</string>" in text
    assert "<string>--to</string>" not in text and DESK not in text  # 좌석 이름 고정 0 — 명부 키만
    assert "__" not in text and "--human</string>" not in text
    assert not (tmp / "launchctl.calls").exists()  # load 0 — launchctl 호출 자체가 없다
    assert not (Path(e["HOME"]) / "Library/LaunchAgents/com.hermes.byz-slack-mbox-inbound.plist").exists()  # 1번째 인스턴스 plist 는 건드리지 않는다


def test_first_instance_install_still_loads(home):
    tmp, e = home
    r = install(e)
    assert r.returncode == 0 and r.stdout.startswith("installed com.hermes.byz-slack-mbox-inbound")
    calls = (tmp / "launchctl.calls").read_text()
    assert "bootstrap" in calls and "kickstart" in calls


@pytest.mark.parametrize("bad", [
    ["--label", "com.hermes.byz-slack-mbox-inbound", "--channel", "C0TALK12345", "--to-key", "_desk", "--humans-from-seats"],  # 1번째 라벨 덮어쓰기 금지
    ["--label", "evil", "--channel", "C0TALK12345", "--to-key", "_desk", "--humans-from-seats"],
    ["--label", "com.hermes.x", "--channel", "general", "--to-key", "_desk", "--humans-from-seats"],
    ["--label", "com.hermes.x", "--channel", "C0TALK12345", "--to-key", "Bad Name", "--humans-from-seats"],
    ["--label", "com.hermes.x", "--channel", "C0TALK12345", "--to-key", DESK, "--humans-from-seats"],  # 좌석 이름은 키가 아니다
    ["--label", "com.hermes.x", "--channel", "C0TALK12345", "--to-key", "_", "--humans-from-seats"],
    ["--label", "com.hermes.x", "--channel", "C0TALK12345", "--to-key", "desk", "--humans-from-seats"],  # `_` 로 시작해야 한다
    ["--label", "com.hermes.x", "--channel", "C0TALK12345", "--to-key", "_desk"],  # --humans-from-seats 없음
    ["--label", "com.hermes.x", "--channel", "C0TALK12345", "--humans-from-seats"],  # --to-key 없음
    ["--label", "com.hermes.x", "--channel", "C0TALK12345", "--to", DESK, "--humans-from-seats"],  # 옛 --to 는 거절
    ["--to-key", "_desk"],  # --label 없이 2번째 전용 옵션
])
def test_installer_rejects_bad_args_with_zero_side_effects(home, bad: list[str]):
    tmp, e = home
    assert install(e, *bad).returncode == 2
    assert not (tmp / "launchctl.calls").exists() and not (Path(e["HOME"]) / "Library").exists()


def test_ack_flag_goes_into_the_talk_plist_only_when_asked_and_mirror_ack_is_always_installed(home):
    tmp, e = home
    plist = Path(e["HOME"]) / "Library/LaunchAgents/com.hermes.byz-slack-talk-inbound.plist"
    assert install(e, *TALK).returncode == 0
    assert "--ack" not in plist.read_text(encoding="utf-8") and "__" not in plist.read_text(encoding="utf-8")
    assert (Path(e["HOME"]) / ".hermes/scripts/mirror_ack_alarm.py").is_file()
    assert (Path(e["HOME"]) / ".hermes/scripts/mirror_ack.py").is_file()  # 데몬이 import 하므로 --ack 와 무관하게 설치
    r = install(e, *TALK, "--ack")
    assert r.returncode == 0, r.stderr
    text = plist.read_text(encoding="utf-8")
    assert "<string>--ack</string>" in text and "__" not in text
    assert not (tmp / "launchctl.calls").exists()


def test_ack_flag_without_label_is_rejected_with_zero_side_effects(home):
    tmp, e = home
    assert install(e, "--ack").returncode == 2
    assert not (tmp / "launchctl.calls").exists() and not (Path(e["HOME"]) / "Library").exists()

# --- R238: 승계 뒤 손 대응 0 — 수신 좌석은 전달마다 명부 키에서 읽는다 ---------------------------------------
DESK1 = "byz-planner-desk-claude#1"
KEY = ("--humans-from-seats", "--to-key", "_desk")
STATE = "byz_slack_mbox_inbound.C1.json"


def set_desk(env: Path, desk: str | None) -> None:
    data = {"_slack_users": {OPPA: "오빠"}, **({"_desk": desk} if desk else {})}
    (env / "seats-planner.json").write_text(json.dumps(data), encoding="utf-8")


def guard(env: Path, bad: str, rc: int = 3, flip_to: str = "") -> None:
    """가짜 가드 — `bad` 로 가는 전송은 큐 적재 0 으로 거절(rc)한다. flip_to 가 있으면 그 순간 명부 `_desk` 를 바꾼다(승계가 막 끝난 경합)."""
    real = env / "comm" / "mbox-real.sh"
    shutil.copy(HERE / "_fake_mbox.sh", real)
    flip = f"python3 -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d[\"_desk\"]=sys.argv[2];json.dump(d,open(p,\"w\"))' {env}/seats-planner.json {flip_to}" if flip_to else ":"
    (env / "comm" / "mbox.sh").write_text(
        f'#!/usr/bin/env bash\nif [ "$2" = "{bad}" ]; then\n  echo x >> "{env}/guard.calls"\n  {flip}\n'
        f'  echo "REJECT 은퇴한 좌석 {bad} — 후계 이름으로 다시 보내라" >&2\n  exit {rc}\nfi\nexec bash "{real}" "$@"\n', encoding="utf-8")


def notices(slack: FakeSlack, needle: str) -> int:
    return sum(needle in m["text"] for m in slack.msgs)


def entry(env: Path) -> dict:
    (e,) = json.loads((env / "st" / STATE).read_text(encoding="utf-8"))["ledger"].values()
    return e


def test_succession_between_posts_needs_no_hand_work(env: Path, slack: FakeSlack):
    ready(env, slack, *KEY)
    slack.human("첫 글", user=OPPA)
    assert run(env, slack, *KEY).returncode == 0
    set_desk(env, DESK1)  # desk#0 → #1 승계 — 명부 `_desk` 만 바뀐다(plist·재기동 0)
    guard(env, DESK)  # 옛 이름으로 가면 거절 — 가면 안 된다
    slack.human("새 글", user=OPPA)
    r = run(env, slack, *KEY)
    assert r.returncode == 0 and "REJECT" not in r.stderr and not (env / "guard.calls").exists()
    assert [x["to"] for x in queue(env)] == [DESK, DESK1] and notices(slack, "멈췄어요") == 0


def test_reject_mid_pass_rereads_the_roster_once_and_resends_without_counting_an_attempt(env: Path, slack: FakeSlack):
    ready(env, slack, *KEY)
    guard(env, DESK, flip_to=DESK1)  # 읽은 직후 승계가 끝나 가드가 옛 이름을 거절한다
    slack.human("글", user=OPPA)
    r = run(env, slack, *KEY)
    assert r.returncode == 0, r.stderr
    assert [x["to"] for x in queue(env)] == [DESK1] and (env / "guard.calls").read_text().count("x") == 1
    e = entry(env)
    assert e["attempt"]["@planner"] == [DESK1] and e["done"]["@planner"] == DESK1  # 거절은 시도가 아니다


def test_reject_with_an_unchanged_roster_holds_notifies_once_and_never_reaches_stuck(env: Path, slack: FakeSlack):
    ready(env, slack, *KEY)
    guard(env, DESK)
    slack.human("글", user=OPPA)
    for _ in range(3):
        assert run(env, slack, *KEY).returncode == 0
    assert queue(env) == [] and entry(env)["attempt"].get("@planner", []) == []
    assert notices(slack, "가드가 거절했는데") == 1 and notices(slack, "멈췄어요") == 0
    set_desk(env, DESK1)  # 명부가 현역을 가리키면 다음 패스에 정확히 1회
    assert run(env, slack, *KEY).returncode == 0 and [x["to"] for x in queue(env)] == [DESK1]


def test_a_failure_that_is_not_a_reject_still_counts_and_stops_after_two(env: Path, slack: FakeSlack):
    ready(env, slack, *KEY)
    guard(env, DESK, rc=1)
    slack.human("글", user=OPPA)
    for _ in range(2):
        r = run(env, slack, *KEY)
        assert r.returncode == 1 and "mbox 전달 실패 rc=1" in r.stderr
    assert run(env, slack, *KEY).returncode == 0 and notices(slack, "멈췄어요") == 1 and queue(env) == []


def test_missing_or_dead_desk_holds_without_sending_and_delivers_once_when_back(env: Path, slack: FakeSlack):
    ready(env, slack, *KEY)
    slack.human("글", user=OPPA)
    set_desk(env, None)
    assert run(env, slack, *KEY).returncode == 0 and queue(env) == [] and notices(slack, "확인 불가(_desk 없음)") == 1
    set_desk(env, DESK)
    assert run(env, slack, *KEY, MIRROR_TMUX="false").returncode == 0 and queue(env) == [] and notices(slack, "확인 불가(세션 없음)") == 1
    assert run(env, slack, *KEY).returncode == 0 and [x["to"] for x in queue(env)] == [DESK]


@pytest.mark.parametrize("trace", ["done", "marker"])
def test_old_ledger_with_the_retired_name_is_not_resent_after_the_fixed_name_is_gone(env: Path, slack: FakeSlack, trace: str):
    ready(env, slack, *KEY)
    ts = f"{time.time():.6f}"
    e = {"recips": ["@planner"], "text": "오빠 새 글 (Slack) — 원문:\n글", "q": None, "thread": "",
         "done": {"@planner": DESK} if trace == "done" else {}, "attempt": {"@planner": [DESK]}}
    (env / "st" / STATE).write_text(json.dumps({"baseline": "1.0", "ledger": {ts: e}}), encoding="utf-8")
    row = {"seq": 1, "to": DESK, "from": "slack-oppa", "body": f"x\n(slack:{ts}:@planner)"}
    (env / "comm" / "mailbox.jsonl").write_text(json.dumps(row) + "\n", encoding="utf-8")
    set_desk(env, DESK1)
    assert run(env, slack, *KEY).returncode == 0
    assert [x["to"] for x in queue(env)] == [DESK] and entry(env)["finished"] is True  # 재발송 0


@pytest.mark.parametrize("opt", [["--to", DESK], ["--to-key", DESK], ["--to-key", "desk"], ["--to-key", "_"], ["--to-key", "_Desk"]])
def test_old_to_option_and_malformed_keys_are_refused(env: Path, slack: FakeSlack, opt: list[str]):
    r = run(env, slack, "--humans-from-seats", *opt)
    assert r.returncode == 2 and queue(env) == []


@pytest.mark.parametrize("renamed_first", [False, True])  # True = 첫 거절 뒤 이름이 바뀌어 같은 패스 재전송도 거절되는 경우
def test_reject_is_persisted_as_no_attempt_before_the_roster_is_reread(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, renamed_first: bool):
    """DA⑥ H1: rc 3 뒤 명부 재조회 도중 재시작돼도(×2) 디스크 원장에 시도가 남지 않아 다음 패스가 stuck 에 닿지 않는다."""
    import argparse

    import mirror_inbound as ib
    import mirror_share as ms

    path = tmp_path / "ledger.json"
    path.write_text(json.dumps({"attempt": {}, "text": "x"}), encoding="utf-8")

    def reject(*_a: object) -> int:
        raise ib.MboxError("known queue rejection", 3)

    calls: list[int] = []

    def restart(*_a: object) -> tuple[str | None, str]:
        calls.append(1)
        if renamed_first and len(calls) % 2 == 1:
            return DESK1, ""
        raise KeyboardInterrupt("restart during roster reread")

    monkeypatch.setattr(ib, "send", reject)
    monkeypatch.setattr(ib, "resolve", restart)
    a = argparse.Namespace(to_key="_desk", mbox="stub")
    for _ in range(2):
        e = json.loads(path.read_text(encoding="utf-8"))
        n, _names = ib.sent_names(e, ms.PLANNER_ROLE)
        with pytest.raises(KeyboardInterrupt):
            ib.attempt_send(e, ms.PLANNER_ROLE, DESK, n, "tok", a, tmp_path, "stub", lambda: path.write_text(json.dumps(e), encoding="utf-8"))
        assert json.loads(path.read_text(encoding="utf-8"))["attempt"].get(ms.PLANNER_ROLE, []) == []  # 확정 미적재 = 영속 시도 0
