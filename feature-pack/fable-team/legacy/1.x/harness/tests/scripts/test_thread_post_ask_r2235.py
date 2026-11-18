"""r2235 — desk 의 오빠 질문 단일 입구 `byz_thread_post.py ask`: D2 재판정 값 검사 «전» 거절 · 게시 1 · 감시 등록 1.

정본 = design/harness/indices/대기/r2235-desk-relay-d2-rejudge.md §반례 집합 ①~⑤ · §변이 M1~M4(⑥ = 기존 시험 결과 수 대조 · 시험 밖).
가짜 Slack(`_proposal_fakes.slack` · --slack-base 로컬) · 임시 FT_ROOT · 임시 장부(FT_DESK_REPLY_LEDGER) · FT_NOW · 실 Slack · 실 mbox · 실 장부 0 · sleep 0.

실행: PYTHONPATH=kit/slack-mirror:tests/scripts python3 -m pytest tests/scripts/test_thread_post_ask_r2235.py -q
"""
import importlib.util
import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

import pytest
from _proposal_fakes import slack  # noqa: F401 — 가짜 Slack fixture(키트 경로를 sys.path 에)
from _thread_fakes import body_after_status_head, status_head_file  # noqa: F401 — status_head_file = autouse(r1089)

import byz_thread_post as tp
import thread_post_update as tpu

KIT = Path(tp.__file__).resolve().parent
BIN = KIT.parent / "fable-team" / "bin"
WAKE = BIN / "ft_desk_reply_wake.py"
DESK_CH = "C9DESK"
NOW = 1794301443
GOOD_WHY = "GPU 2대 켜기 = 새 비용 · 승인 골 밖"
GOOD = ["--d2", "2", "--why", GOOD_WHY, "--default", "안 함 · 꺼진 채"]


@pytest.fixture
def env(slack, tmp_path, monkeypatch):  # noqa: F811
    root = tmp_path / "root"
    (root / ".fable-team" / "state").mkdir(parents=True)
    (tmp_path / "tok.env").write_text("YOONHWAN_BOT_TOKEN=xoxp-secret-1\n", encoding="utf-8")
    (tmp_path / "q.txt").write_text("[질문] GPU 2대를 지금 켤까요?", encoding="utf-8")
    today = datetime.now(tpu.KST).date().isoformat()
    (tmp_path / "threads.json").write_text(json.dumps({"desk": {"channel": DESK_CH, "root_ts": "1792422462.316339", "date": today}}), encoding="utf-8")
    for k, v in {"FT_ROOT": root, "FT_DESK_REPLY_LEDGER": root / ".fable-team/state/desk-reply-wait.jsonl", "FT_DESK_REPLY_WAKE": WAKE,
                 "FT_NOW": NOW, "FT_SLACK_THREADS": tmp_path / "threads.json", "FT_SLACK_STATE_DIR": tmp_path / "st"}.items():
        monkeypatch.setenv(k, str(v))
    return tmp_path


def ask(env, slack, *argv, to=("--to", "desk")):  # noqa: F811
    return tp.main(["ask", "--token-file", str(env / "tok.env"), "--slack-base", slack.base, *to,
                    "--key", "gpu-two", "--text-file", str(env / "q.txt"), *argv])


def rows() -> list[dict]:
    p = Path(os.environ["FT_DESK_REPLY_LEDGER"])
    return [json.loads(x) for x in p.read_text(encoding="utf-8").splitlines() if x.strip()] if p.exists() else []


# ① D2 인자 0 = rc3 · 게시 0 · 장부 0 (기준판 = «ask» 갈래 없음)
def test_1_no_d2_args_rejects_before_post(env, slack, capsys):  # noqa: F811
    assert ask(env, slack) == 3
    assert "D2 재판정 값 없음" in capsys.readouterr().err
    assert slack.msgs == [] and rows() == []


@pytest.mark.parametrize("drop", ["--d2", "--why", "--default"])
def test_1_each_missing_value_rejects(env, slack, drop):  # noqa: F811
    i = GOOD.index(drop)
    assert ask(env, slack, *(GOOD[:i] + GOOD[i + 2:])) == 3
    assert slack.msgs == [] and rows() == []


# ② 팀 판정 낱말을 빼면 이유가 안 남음 = rc3
@pytest.mark.parametrize("why", ["자율 범위 밖", "자율 범위 밖이라 묻습니다", "범위 밖 · 오빠 판단 필요"])
def test_2_team_verdict_is_not_a_reason(env, slack, capsys, why):  # noqa: F811
    assert ask(env, slack, "--d2", "2", "--why", why, "--default", "안 함") == 3
    assert "팀 판정은 근거가 아님" in capsys.readouterr().err
    assert slack.msgs == [] and rows() == []


# ③ 값
@pytest.mark.parametrize("argv,rc", [
    (["--d2", "4", "--why", GOOD_WHY, "--default", "안 함"], 3),
    (["--d2", "1", "--why", GOOD_WHY, "--default", "A 로 진행"], 3),
    (["--d2", "3", "--why", GOOD_WHY, "--default", "A 로 진행"], 0),
    (["--d2", "off", "--why", "자율 OFF 라 D0 대로 오빠께 묻기", "--default", "A 로 진행"], 0),
])
def test_3_values(env, slack, argv, rc):  # noqa: F811
    assert ask(env, slack, *argv) == rc
    assert len(slack.msgs) == (1 if rc == 0 else 0) and len(rows()) == (1 if rc == 0 else 0)


# ④ 게시 · 등록
def test_4_posts_once_with_two_tail_lines_and_registers(env, slack, capsys):  # noqa: F811
    assert ask(env, slack, *GOOD) == 0
    assert len(slack.msgs) == 1 and slack.msgs[0]["channel"] == DESK_CH and slack.msgs[0]["thread_ts"] == ""
    tail = body_after_status_head(slack.msgs[0]["text"]).splitlines()[-2:]
    assert tail == [f"왜 사람: {GOOD_WHY}", "답 전 기본값: 안 함 · 꺼진 채"]
    (r,) = rows()
    assert (r["q_ts"], r["kind"], r["key"], r["d2"], r["why"], r["state"]) == (slack.msgs[0]["ts"], "question", "gpu-two", "2", GOOD_WHY, "open")


def test_4_thread_root_reply_path(env, slack):  # noqa: F811
    assert ask(env, slack, *GOOD, to=("--ts", "1792422462.316339", "--channel", "C1")) == 0
    assert (slack.msgs[0]["channel"], slack.msgs[0]["thread_ts"]) == ("C1", "1792422462.316339") and len(rows()) == 1


def test_4_slack_failure_is_rc1_and_no_registration(env, slack):  # noqa: F811
    slack.drop_next_post = True
    assert ask(env, slack, *GOOD) == 1
    assert rows() == []


@pytest.mark.parametrize("var,val", [("FT_DESK_REPLY_WAKE", "{env}/없는/ft_desk_reply_wake.py"), ("FT_DESK_REPLY_LEDGER", "{env}/없는폴더/w.jsonl")])
def test_4_watch_tool_or_ledger_missing_is_rc2_before_post(env, slack, monkeypatch, capsys, var, val):  # noqa: F811
    monkeypatch.setenv(var, val.format(env=env))
    assert ask(env, slack, *GOOD) == 2
    assert "판정 불가 — 감시 도구 · 장부 없음" in capsys.readouterr().err
    assert slack.msgs == []


def test_4_tool_found_through_live_bin(env, slack, monkeypatch):  # noqa: F811
    monkeypatch.delenv("FT_DESK_REPLY_WAKE")
    (Path(os.environ["FT_ROOT"]) / ".fable-team/LIVE_BIN").write_text(f"{BIN}\n", encoding="utf-8")
    assert ask(env, slack, *GOOD) == 0 and len(rows()) == 1


def test_4_registration_failure_names_posted_ts(env, slack, monkeypatch, capsys):  # noqa: F811
    bad = env / "bad_wake.py"
    bad.write_text("import sys\nsys.exit(3)\n", encoding="utf-8")
    monkeypatch.setenv("FT_DESK_REPLY_WAKE", str(bad))
    assert ask(env, slack, *GOOD) == 1
    assert f"게시 ts={slack.msgs[0]['ts']} · 등록 손으로" in capsys.readouterr().err


# ⑤ 장부 — 뒤 인자 0 = 옛 줄 그대로 · 새 칸이 있어도 scan · close 결과 같음
def wake(root: Path, led: Path, *argv: str, now: int = NOW) -> subprocess.CompletedProcess:
    e = {**os.environ, "FT_ROOT": str(root), "FT_DESK_REPLY_LEDGER": str(led), "FT_NOW": str(now), "HIL_DIR": str(root / "hil"),
         "FT_MBOX_SH": str(root / "mbox.sh"), "FT_SLACK_CHECK": str(BIN / "ft_oppa_slack_check.py"),
         "FT_SLACK_REPLIES_CMD": f"cat {root / 'replies.json'}", "FT_SEATS_PLANNER": str(root / ".fable-team/seats-planner.json")}
    return subprocess.run([sys.executable, str(WAKE), *argv], capture_output=True, text=True, timeout=25, env=e, cwd=root)


def test_5_register_question_without_tail_is_unchanged(env):
    root, led = Path(os.environ["FT_ROOT"]), Path(os.environ["FT_DESK_REPLY_LEDGER"])
    assert wake(root, led, "--register-question", "1794300200.123456", "r1590").returncode == 0
    assert rows() == [{"q_ts": "1794300200.123456", "kind": "question", "key": "r1590", "at": NOW, "deadline": NOW + 86400, "state": "open"}]


def scan_world(base: Path, with_cells: bool) -> tuple[Path, Path]:
    root = base / ("new" if with_cells else "old")
    (root / ".fable-team/state").mkdir(parents=True)
    (root / "hil").mkdir()
    (root / ".fable-team/seats-planner.json").write_text('{"_master":"m#1","_desk":"d#1"}', encoding="utf-8")
    (root / "mbox.sh").write_text(f'#!/usr/bin/env bash\nprintf "%s\\t%s\\n" "$2" "$4" >> "{root}/sent.tsv"\necho QUEUED\n', encoding="utf-8")
    msgs = [{"ts": "1794300200.000001", "user": "U0C9GRFHJ", "text": "질문"}, {"ts": "1794300260.654321", "user": "U0AC2JF0M7D", "text": "좋아"}]
    (root / "replies.json").write_text(json.dumps({"ok": True, "messages": msgs}), encoding="utf-8")
    led = root / ".fable-team/state/desk-reply-wait.jsonl"
    old = [{"q_ts": f"179430020{i}.000001", "kind": "question", "key": f"r159{i}", "at": NOW, "deadline": NOW + 86400, "state": "open"} for i in range(3)]
    new = {"q_ts": "1794300300.000001", "kind": "question", "key": "gpu-two", "at": NOW, "deadline": NOW + 86400, "state": "open"}
    new.update({"d2": "2", "why": GOOD_WHY} if with_cells else {})
    led.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in old + [new]), encoding="utf-8")
    return root, led


def test_5_scan_and_close_ignore_new_cells(tmp_path):
    out = {}
    for cells in (False, True):
        root, led = scan_world(tmp_path, cells)
        s = wake(root, led)
        c = wake(root, led, "--close", "gpu-two")
        later = wake(root, led, now=NOW + 86401)
        got = [{k: v for k, v in json.loads(x).items() if k not in ("d2", "why")} for x in led.read_text(encoding="utf-8").splitlines()]
        sent = (root / "sent.tsv").read_text(encoding="utf-8") if (root / "sent.tsv").exists() else ""
        out[cells] = (s.returncode, s.stdout, c.returncode, c.stdout, later.returncode, later.stdout, sent, got)
    assert out[False] == out[True]
    assert out[True][6].count("m#1") >= 1  # 답글 1건이 실제로 master 로 갔다(빈 비교 아님)


# 변이 M1~M4 — 사본 모듈을 바꿔 끼우고 같은 사례를 원본으로 1회 더(반대 결과 대조)
MUTANTS = {
    "M1": [('REQUIRED = ("key", "d2", "why", "default")', 'REQUIRED = ("key", "why", "default")'),
           ("if a.d2 not in D2_VALUES:", "if a.d2 not in D2_VALUES + (None,):")],
    "M2": [("    return strip_team_words(SPACE.sub(\"\", why))", "    return \"\" if why.strip() in TEAM_WORDS else SPACE.sub(\"\", why)")],
    "M3": [('if a.d2 in ("1", "2") and "안 함" not in a.default:', "if False:")],
    "M4": [("    reason = refusal(a)\n    if reason:\n        print(f\"REJECT {reason} · 게시 0\", file=sys.stderr)\n        return 3\n", ""),
           ("    print(f\"POSTED {ts}\")\n", "    print(f\"POSTED {ts}\")\n    if refusal(a):\n        return 3\n")],
}
CASES = {"M1": ["--why", GOOD_WHY, "--default", "안 함"], "M2": ["--d2", "2", "--why", "자율 범위 밖이라 묻습니다", "--default", "안 함"],
         "M3": ["--d2", "1", "--why", GOOD_WHY, "--default", "A 로 진행"], "M4": []}


def mutant(tmp_path: Path, name: str):
    src = (KIT / "thread_post_ask.py").read_text(encoding="utf-8")
    for old, new in MUTANTS[name]:
        assert old in src, f"{name} 변이 자리 없음: {old!r}"
        src = src.replace(old, new, 1)
    p = tmp_path / f"thread_post_ask_{name}.py"
    p.write_text(src, encoding="utf-8")
    spec = importlib.util.spec_from_file_location(p.stem, p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.mark.parametrize("name", sorted(MUTANTS))
def test_mutants_flip_the_case(env, slack, monkeypatch, tmp_path, name):  # noqa: F811
    assert ask(env, slack, *CASES[name]) == 3 and slack.msgs == []  # 원본 = 게시 0
    monkeypatch.setattr(tp, "tpa", mutant(tmp_path, name))
    ask(env, slack, *CASES[name])
    assert len(slack.msgs) == 1, f"{name} 를 넣어도 게시 0 — 시험이 약하다"
