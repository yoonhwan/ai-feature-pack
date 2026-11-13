"""r1827 좌석 교대(retire) 때 Slack thread 담당을 후계로 넘긴다 — 반례 ①~④(①′ ③′ ④′ ④″) · 임시 root · 대역 장부 줄.
B1 `ThreadBinding.handover_seat` · B2 `cli.py slack handover-seat` · B3 ft-seat-retire.sh 가 RETIRED 뒤 B2 1회(FT2_CLI 주입).
실 runtime·Slack·launchd·명부 쓰기 0 · sleep 0.
"""
import importlib.util, json, os, re, subprocess, sys  # noqa: E401

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SLACK, CLI = os.path.join(FT2, "adapters", "slack"), os.path.join(FT2, "core", "cli.py")
RETIRE = os.path.join(os.path.dirname(FT2), "legacy", "1.x", "harness", "bin", "ft-seat-retire.sh")
OLD, NEW, OTHER, W, C = "byz-planner-master-pi#284", "byz-planner-master-pi#285", "byz-planner-desk-pi#3", "TF", "CF"


def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_r1827_" + name, os.path.join(SLACK, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


binding, publish = _load("binding"), _load("publish")


def _key(ts):
    return binding.thread_key(W, C, ts)


def _ledger(root, team, opens, other=0, closed=0):
    """열린 seat=OLD `opens` 개 · 열린 다른 좌석 `other` 개 · 닫힘(seat=OLD 대역 줄 + 실제 close) `closed` 쌍."""
    book = binding.ThreadBinding(str(root), team)
    for n in range(opens):
        book.bind(_key("1.%d" % n), OLD)
    for n in range(other):
        book.bind(_key("2.%d" % n), OTHER)
    for n in range(closed):
        book.bind(_key("3.%d" % n), OLD)
        book.close(_key("3.%d" % n))
        book._append({"state": binding.CLOSED, "key": list(_key("4.%d" % n)), "seat": OLD, "gen": 1, "open": False,
                      "owner": binding.owner_label(OLD, 1)})
    return book


def test_1_handover_seat_moves_only_open_old_and_is_idempotent(tmp_path):
    """① 열린 OLD 2 → NEW gen2 · 다른 좌석·닫힘 그대로 · ①′ 다시 = 0건 · 새 줄 0."""
    book = _ledger(tmp_path, "planner", opens=2, other=1, closed=1)
    assert book.handover_seat(OLD, NEW) == 2
    for n in range(2):
        now = book.get(_key("1.%d" % n))
        assert (now.seat, now.gen, now.open) == (NEW, 2, True)
    assert (book.get(_key("2.0")).seat, book.get(_key("2.0")).gen) == (OTHER, 1)
    assert (book.get(_key("3.0")).open, book.get(_key("3.0")).seat) == (False, None)
    assert (book.get(_key("4.0")).open, book.get(_key("4.0")).seat, book.get(_key("4.0")).gen) == (False, OLD, 1)
    before = len(book.entries())
    assert book.handover_seat(OLD, NEW) == 0
    assert len(book.entries()) == before


def test_2_publish_refusal_after_handover_seat(tmp_path):
    """② 이전 뒤 NEW(gen2) 답 = 통과 · OLD 옛 gen 답 = stale_owner."""
    book = _ledger(tmp_path, "planner", opens=2)
    book.handover_seat(OLD, NEW)
    pub = publish.SlackPublish(str(tmp_path), post=lambda *a, **k: None, team="planner", bindings=book)
    key = _key("1.0")
    assert pub._refusal(key, "receipt:x", NEW, book.get(key).gen) is None
    assert pub._refusal(key, "receipt:x", OLD, 1)["k"] == "stale_owner"


def _cli(root):
    return subprocess.run([sys.executable, CLI, "slack", "handover-seat", "--root", str(root), "--from", OLD, "--to", NEW],
                          capture_output=True, text=True, timeout=30)


def test_3_cli_handover_seat_teams_and_failures(tmp_path):
    """③ 2팀(planner 2 · harness 1) → moved=3 · 장부 없는 root → moved=0 rc0 · ③′ 깨진 줄 → 판정 불가 rc≠0 · 남은 팀은 진행."""
    _ledger(tmp_path / "a", "planner", opens=2, other=1)
    _ledger(tmp_path / "a", "harness", opens=1, closed=1)
    ran = _cli(tmp_path / "a")
    assert (ran.returncode, ran.stdout.strip()) == (0, "SLACK-BINDING moved=3 teams=[harness:1 planner:2]")
    (tmp_path / "b").mkdir()
    ran = _cli(tmp_path / "b")
    assert (ran.returncode, ran.stdout.strip()) == (0, "SLACK-BINDING moved=0 teams=[]")
    _ledger(tmp_path / "c", "planner", opens=2)
    harness = _ledger(tmp_path / "c", "harness", opens=1)
    with open(harness.path, "a", encoding="utf-8") as handle:
        handle.write("{깨진 줄\n")
    ran = _cli(tmp_path / "c")
    lines = ran.stdout.strip().splitlines()
    assert ran.returncode != 0
    assert [ln for ln in lines if ln.startswith("SLACK-BINDING 판정 불가 harness ")] and len(lines) == 2
    assert "SLACK-BINDING moved=2 teams=[planner:2]" in lines
    assert binding.ThreadBinding(str(tmp_path / "c"), "planner").get(_key("1.0")).seat == NEW


def _retire(tmp_path, args, cli):
    """명부 대역 + reap·quiesce·tmux·우편함 대역 · 임시 cwd(git 밖) = root."""
    stub = tmp_path / "stub.sh"
    stub.write_text("#!/bin/sh\necho \"reap $1 stopped=0 left=0 rc=0\"\n")
    tmux = tmp_path / "tmux"
    tmux.write_text("#!/bin/sh\nexit 1\n")
    os.chmod(tmux, 0o755)
    env = dict(os.environ, FT_SEAT_REAP_BIN=str(stub), FT_SEAT_QUIESCE_BIN=str(stub), FT_TMUX=str(tmux),
               FT_MBOX_PY=str(tmp_path / "none.py"), ZC_RESUME_DIR=str(tmp_path / "resume"), FT2_CLI=str(cli),
               FT_SUCCESSOR_DIR=str(tmp_path / "succ"), FT_ALLOW_TRACKED_BIN="1")
    return subprocess.run(["bash", RETIRE] + args, cwd=str(tmp_path), env=env, capture_output=True, text=True, timeout=60)


def _seats(tmp_path, row):
    seats = tmp_path / ".fable-team" / "seats-planner.json"
    seats.parent.mkdir(parents=True, exist_ok=True)
    seats.write_text(json.dumps({"_master": OLD, OLD: row}))
    return str(seats)


def test_4_retire_calls_handover_seat_after_retired(tmp_path):
    """④ RETIRED 뒤 SLACK-BINDING 1줄 · rc 0 · 장부 실제 이전."""
    seats = _seats(tmp_path, {"role": "master", "agent": "claude", "model": "m1", "tick": None})
    _ledger(tmp_path, "planner", opens=2)
    ran = _retire(tmp_path, [OLD, NEW, "--seats", seats], CLI)
    lines = ran.stdout.splitlines()
    assert ran.returncode == 0, ran.stdout + ran.stderr
    assert lines[0].startswith("RETIRED %s -> %s" % (OLD, NEW))
    hit = [n for n, ln in enumerate(lines) if ln.startswith("SLACK-BINDING")]
    assert len(hit) == 1 and lines[hit[0]] == "SLACK-BINDING moved=2 teams=[planner:2]"
    assert re.match(r"^(RESUME|NORECORD) ", lines[hit[0] - 1])
    assert binding.ThreadBinding(str(tmp_path), "planner").get(_key("1.1")).owner == NEW + "#2"


def test_4b_retire_rc_ignores_b2_failure_and_record_only_skips(tmp_path):
    """④′ B2 대역 rc≠0 → retire rc 0 · 판정 불가 1줄 · ④″ --record-only → B2 호출 0."""
    calls = tmp_path / "calls"
    bad = tmp_path / "bad_cli.py"
    bad.write_text("import sys\nopen(%r, 'a').write('x\\n')\nprint('SLACK-BINDING 판정 불가 planner 대역')\nsys.exit(1)\n"
                   % str(calls))
    seats = _seats(tmp_path, {"role": "master", "agent": "claude", "model": "m1", "tick": None})
    ran = _retire(tmp_path, [OLD, NEW, "--seats", seats], bad)
    assert ran.returncode == 0, ran.stdout + ran.stderr
    assert len([ln for ln in ran.stdout.splitlines() if ln.startswith("SLACK-BINDING 판정 불가")]) == 1
    calls.unlink()
    ran = _retire(tmp_path, [OLD, "--record-only", "--seats", seats], bad)
    assert not calls.exists() and "SLACK-BINDING" not in ran.stdout
