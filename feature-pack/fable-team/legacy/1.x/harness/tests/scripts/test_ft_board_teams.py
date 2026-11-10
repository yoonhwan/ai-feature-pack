"""R132a — `ft-board.py teams` 팀 한 줄 시험 (일함 1팀 · 전원 정지 1팀 + 확인 불가 1). 임시 FT_ROOT·스텁 env — 실제 tmux·gh·jsonl 조회 0.
r850 r4: 팀 줄 가운데 칸 = ft_team_state.team_states(뉴스와 같은 판정 · 좌석 = 명부 현역 행 · 턴 = jsonl) — 픽스처가 좌석마다 jsonl + 가짜 list-panes 도 만든다."""

import datetime as dt
import json
import os
import re
import subprocess
import sys
from pathlib import Path

import pytest

BIN = Path(__file__).resolve().parents[3] / "harness" / "bin"
NOW = dt.datetime(2026, 10, 13, 10, 0, 0)
ago = lambda m: (NOW - dt.timedelta(minutes=m)).isoformat()  # noqa: E731


def _turn(root: Path, seat: str, state: str, minutes: int | None = None, **extra) -> None:
    out = {"state": state, "turn_end": None if minutes is None else ago(minutes), "duration_ms": 1000, "reported": "no", "source": "jsonl", **extra}
    (root / "turn" / f"{seat}.out").write_text(json.dumps(out), encoding="utf-8")
    if out["source"] != "jsonl":  # codex 좌석 = claude jsonl 없음(뉴스·시트 판정 = «jsonl 없음» · r850 r4 범위 밖 그대로)
        return
    rows = [{"type": "custom-title", "customTitle": seat}, {"type": "user", "message": {"content": "일"}}, {"type": "assistant", "message": {"content": []}}]
    if minutes is not None:
        rows.append({"type": "system", "subtype": "turn_duration", "timestamp": ago(minutes), "durationMs": 1000})
    if state == "WORKING":
        rows.append({"type": "user", "message": {"content": "다음"}})
    d = root.parent / "projects" / re.sub(r"[^A-Za-z0-9]", "-", f"/wt/{seat}")
    d.mkdir(parents=True, exist_ok=True)
    (d / "s.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False, separators=(",", ":")) + "\n" for r in rows), encoding="utf-8")


@pytest.fixture
def board(tmp_path: Path):
    root = tmp_path / "root"
    fb = root / ".fable-team"
    for d in (fb / "comm", fb / "state", root / "turn", root / "t" / "진행"):
        d.mkdir(parents=True)
    git = ["git", "-C", str(root)]
    subprocess.run([*git, "init", "-q"], check=True)
    subprocess.run([*git, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "base"], check=True)
    (fb / "state" / "verdicts.jsonl").write_text("", encoding="utf-8")
    (tmp_path / "gh.json").write_text("[]", encoding="utf-8")
    (tmp_path / "inbox.sh").write_text("#!/bin/sh\necho EMPTY\n", encoding="utf-8")
    (tmp_path / "seat.sh").write_text(f'#!/bin/sh\ncat "{root}/turn/$2.out"\n', encoding="utf-8")
    (root / "t" / "진행" / "c-prog.md").write_text("# 인덱스: 진행카드\n본문\n", encoding="utf-8")
    env = {**os.environ, "FT_ROOT": str(root), "FT_BOARD_NOW": NOW.isoformat(), "FT_BOARD_GH_TTL": "0", "FT_BOARD_GH_REFRESH": "1",
           "FT_VERDICT_BIN": str(BIN / "ft-verdict.sh"), "FT_BOARD_TMUX": f"bash {tmp_path / 'tmux.sh'}", "FT_BOARD_GH": f"cat {tmp_path / 'gh.json'}",
           "FT_BOARD_INBOX": f"bash {tmp_path / 'inbox.sh'}", "FT_BOARD_SEAT_STATUS": str(tmp_path / "seat.sh"),
           "FT_SEAT_RESUME_DIR": str(tmp_path / "resume"), "FT_TMUX": str(tmp_path / "panes.sh"), "FT_CLAUDE_PROJECTS": str(tmp_path / "projects")}
    (tmp_path / "panes.sh").write_text(f'#!/bin/sh\nwhile read -r s; do [ -n "$s" ] && printf "%s\\t/wt/%s\\n" "$s" "$s"; done < "{tmp_path}/alive.txt"\n',
                                       encoding="utf-8")
    (tmp_path / "panes.sh").chmod(0o755)
    env.pop("GIT_DIR", None)

    def run(*args: str) -> subprocess.CompletedProcess:
        return subprocess.run([sys.executable, str(BIN / "ft-board.py"), *args], capture_output=True, text=True, env=env)

    def seats(name: str, data: dict, alive: list[str]) -> None:
        (fb / f"seats-{name}.json").write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        with (tmp_path / "alive.txt").open("a", encoding="utf-8") as f:
            f.write("\n".join(alive) + "\n")
        (tmp_path / "tmux.sh").write_text(f'#!/bin/sh\ncat "{tmp_path}/alive.txt"\n', encoding="utf-8")

    def mail(rows: list[dict]) -> None:
        (fb / "comm" / "mailbox.log.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")

    return type("B", (), {"run": staticmethod(run), "seats": staticmethod(seats), "mail": staticmethod(mail), "root": root})


def test_teams_one_line_per_team_working_vs_stopped_with_unknown(board) -> None:
    board.seats("a", {"_label": "일함팀", "_master": "a-m#1", "a-m#1": {"role": "master"}, "a-n1#0": {"role": "nano"}, "a-n2#0": {"role": "nano"}},
                ["a-m#1", "a-n1#0", "a-n2#0"])
    board.seats("b", {"_label": "정지팀", "_master": "b-m#1", "_cards": "t", "b-m#1": {"role": "master"},
                      "b-n#0": {"role": "nano", "index": "t/진행/c-prog.md"}, "b-da#0": {"role": "da"}}, ["b-m#1", "b-n#0", "b-da#0"])
    _turn(board.root, "a-m#1", "IDLE", 8)
    _turn(board.root, "a-n1#0", "WORKING", 20)
    _turn(board.root, "a-n2#0", "IDLE", 2)
    _turn(board.root, "b-m#1", "IDLE", 10)
    _turn(board.root, "b-n#0", "IDLE", 7)
    _turn(board.root, "b-da#0", "IDLE", 1)
    board.mail([{"seq": 1, "ts": ago(30), "to": "b-arch#1", "from": "b-m#1", "body": "[b-m#1->b-arch#1] 질문"}])
    r = board.run("teams")
    assert r.returncode == 0, r.stderr
    assert r.stdout.splitlines() == [  # r850: 가운데 칸 = ft_team_state.judge 글자(진행 카드 1 + 30분 안 턴 = 진행)
        "일함팀 · 진행 · 일하는 좌석 1/3 · 일함 a-n1#0 · 진행 0",
        "정지팀 · 진행 · 1분 전 턴 · 진행 1(c-prog)",  # r4: 좌석 = 명부 현역 행(da 행도 좌석 · 시트 «현역 근거» 따로 판정 0)
    ]


def test_teams_team_option_limits_to_one_roster(board) -> None:
    board.seats("a", {"_label": "일함팀", "_master": "a-m#1", "a-m#1": {"role": "master"}}, ["a-m#1"])
    board.seats("z", {"_label": "딴팀", "_master": "z-m#1", "z-m#1": {"role": "master"}}, ["z-m#1"])
    _turn(board.root, "a-m#1", "WORKING", 1)
    _turn(board.root, "z-m#1", "WORKING", 1)
    r = board.run("teams", "--team", str(board.root / ".fable-team" / "seats-a.json"))
    assert r.stdout.splitlines() == ["일함팀 · 진행 · 일하는 좌석 1/1 · 일함 a-m#1 · 진행 0"]


def test_teams_no_waiting_conclusion_when_no_unreplied_mail(board) -> None:
    """기록상 미회신 0 이면 Mail.wait 가 내는 문구 그대로 — «다음 발주 없음» 같은 결론 문구를 만들어 쓰지 않는다.
    r850: «기다리는 것» 은 대기(진행 카드 ≥1 · 좌석이 30분 넘게 조용)일 때 싣는다."""
    board.seats("b", {"_label": "정지팀", "_master": "b-m#1", "_cards": "t", "b-m#1": {"role": "master"}}, ["b-m#1"])
    _turn(board.root, "b-m#1", "IDLE", 45)
    board.mail([{"seq": 1, "ts": ago(30), "to": "b-m#1", "from": "x#1", "body": "[x#1->b-m#1] 발주"}])
    line = board.run("teams").stdout.strip()
    assert line == "정지팀 · 대기 45분 · 기다리는 것 = 추정: 기록(09:30 이후)상 발신 없음 · 진행 1(c-prog)"
    assert "다음 발주 없음" not in line


def test_teams_codex_aborted_seat_counts_as_stopped(board) -> None:
    """codex 좌석(source=codex · aborted)도 분 계산에 들어간다 — pane 판정이 아니라 턴 기록."""
    board.seats("d", {"_label": "코덱스팀", "_master": "d-m#1", "_da": "d-da#1", "d-m#1": {"role": "master"}, "d-da#1": {"role": "da", "agent": "codex"}},
                ["d-m#1", "d-da#1"])
    _turn(board.root, "d-m#1", "IDLE", 30)
    _turn(board.root, "d-da#1", "IDLE", 4, source="codex", aborted=True)
    r = board.run("teams")
    assert r.stdout.startswith("코덱스팀 · 확인 불가(jsonl 없음 1석) · "), r.stdout  # r850 r4: 팀 줄 = 뉴스와 같은 판정(codex 좌석 = jsonl 없음 · 범위 밖)


def test_stalled_lists_unknown_seat_regardless_of_min(board) -> None:
    """규칙 3 «확인 불가» 좌석은 master 감시(`ft-board.py stalled`)에서 빠지지 않는다 — 분 열이 숫자가 아니라 --min 과 무관하게 나온다."""
    board.seats("b", {"_label": "정지팀", "_master": "b-m#1", "b-m#1": {"role": "master"}, "b-da#0": {"role": "da"}}, ["b-m#1", "b-da#0"])
    _turn(board.root, "b-m#1", "IDLE", 1)
    _turn(board.root, "b-da#0", "IDLE", 1)
    want = ["확인 불가|b-da#0|-|현역 근거 없음(포인터·은퇴 표시 0)"]
    assert board.run("stalled", "--min", "3").stdout.splitlines() == want
    assert board.run("stalled", "--min", "99").stdout.splitlines() == want


def test_stalled_lists_pointer_seat_whose_turn_is_unknown(board) -> None:
    """DA⑥ I1 — 포인터 현역 codex 좌석의 턴 조회가 UNKNOWN(rollout 0)이면 stalled 에 사유와 함께 나온다(--min 무관) · teams 줄 개수와 일치."""
    board.seats("b", {"_label": "정지팀", "_master": "b-m#1", "_da": "b-da#1", "b-m#1": {"role": "master"}, "b-da#1": {"role": "da", "agent": "codex"}},
                ["b-m#1", "b-da#1"])
    _turn(board.root, "b-m#1", "IDLE", 1)
    _turn(board.root, "b-da#1", "UNKNOWN", None, source="codex", reason="rollout 0")
    want = ["확인 불가|b-da#1|-|rollout 0"]
    assert board.run("stalled", "--min", "3").stdout.splitlines() == want
    assert board.run("stalled", "--min", "99").stdout.splitlines() == want
    assert board.run("teams").stdout.strip().endswith("· 확인 불가 1")


# ── r554 — 한 팀 수집 실패는 «그 팀 칸»에 보이게 싣고 나머지 팀은 그대로 (ⓐ~ⓔ) ──
def _cards(root: Path, team: str, folder: str = "진행", name: str = "c1") -> None:
    d = root / "t" / team / folder
    d.mkdir(parents=True, exist_ok=True)
    (d / f"{name}.md").write_text(f"# 인덱스: {team}카드\n본문\n", encoding="utf-8")


def _team(d: dict, key: str) -> dict:
    return next(t for t in d["teams"] if t["key"] == key)


def test_collect_missing_cards_folder_marks_only_that_team(board) -> None:
    """ⓐ 카드 폴더 없음 — 그 팀 = error 한 칸(숫자 칸 자체가 없다: 0 으로 채우지 않는다) · 다른 팀 값은 그대로."""
    _cards(board.root, "ok")
    board.seats("ok", {"_label": "정상팀", "_master": "ok-m#1", "_cards": "t/ok", "ok-m#1": {"role": "master"}}, ["ok-m#1"])
    board.seats("bad", {"_label": "사라진팀", "_master": "bad-m#1", "_cards": "t/nope", "bad-m#1": {"role": "master"}}, ["bad-m#1"])
    r = board.run("collect")
    assert r.returncode == 0, r.stderr
    d = json.loads(r.stdout)
    assert _team(d, "ok")["counts"]["진행"] == 1
    bad = _team(d, "bad")
    assert (bad["key"], bad["label"]) == ("bad", "사라진팀")
    assert bad["error"] == f"카드 폴더 없음 — {board.root / 't' / 'nope'}"
    for k in ("counts", "queue", "states", "progress", "axes", "done_today"):
        assert k not in bad


def test_collect_missing_tree_file_marks_only_that_team(board) -> None:
    """ⓑ `_tree` 만 없음 — 같은 꼴(그 팀 error · 다른 팀 정상)."""
    _cards(board.root, "ok")
    board.seats("ok", {"_label": "정상팀", "_master": "ok-m#1", "_cards": "t/ok", "ok-m#1": {"role": "master"}}, ["ok-m#1"])
    _cards(board.root, "bad")
    board.seats("bad", {"_label": "트리팀", "_master": "bad-m#1", "_cards": "t/bad", "_tree": "t/bad/NEWS-TREE.md",
                        "bad-m#1": {"role": "master"}}, ["bad-m#1"])
    r = board.run("collect")
    assert r.returncode == 0, r.stderr
    d = json.loads(r.stdout)
    assert _team(d, "bad")["error"] == f"_tree 파일 없음 — {board.root / 't' / 'bad' / 'NEWS-TREE.md'}"
    assert _team(d, "ok")["counts"]["진행"] == 1


def test_collect_broken_roster_json_marks_that_team_with_exception_name(board) -> None:
    """ⓒ 명부 JSON 깨짐 — 그 팀 error(파일 이름 + 예외 이름) · 나머지 정상 (한 장 깨졌다고 전 팀 0 이 아니다)."""
    _cards(board.root, "ok")
    board.seats("ok", {"_label": "정상팀", "_master": "ok-m#1", "_cards": "t/ok", "ok-m#1": {"role": "master"}}, ["ok-m#1"])
    (board.root / ".fable-team" / "seats-broken.json").write_text("{ 깨짐", encoding="utf-8")
    r = board.run("collect")
    assert r.returncode == 0, r.stderr
    d = json.loads(r.stdout)
    err = _team(d, "broken")["error"]
    assert err.startswith("seats-broken.json JSONDecodeError: "), err
    assert _team(d, "ok")["counts"]["진행"] == 1


def test_render_error_team_shows_unconfirmed_line_and_other_rows_unchanged(board) -> None:
    """ⓓ 그리는 쪽 — error 팀 = «확인 못 함: <원인>» 한 줄 · 다른 팀 줄은 error 팀이 늘기 전과 같은 글자."""
    _cards(board.root, "ok")
    board.seats("ok", {"_label": "정상팀", "_master": "ok-m#1", "_cards": "t/ok", "ok-m#1": {"role": "master"}}, ["ok-m#1"])
    only = board.run("render", "--term")
    assert only.returncode == 0, only.stderr
    board.seats("bad", {"_label": "사라진팀", "_master": "bad-m#1", "_cards": "t/nope", "bad-m#1": {"role": "master"}}, ["bad-m#1"])
    both = board.run("render", "--term")
    assert both.returncode == 0, both.stderr
    ok_row = next(ln for ln in only.stdout.splitlines() if "정상팀" in ln)
    assert ok_row in both.stdout.splitlines()
    assert f"- 사라진팀 | 확인 못 함: 카드 폴더 없음 — {board.root / 't' / 'nope'}" in both.stdout.splitlines()
    assert "확인 못 함" in board.run("render", "--slack").stdout


def test_collect_error_team_prints_error_line_on_stderr(board) -> None:
    """ⓔ stderr `ERROR <명부 이름>: <원인>` — 실패가 화면(로그)에 남는다(조용한 폴백 0)."""
    _cards(board.root, "ok")
    board.seats("ok", {"_label": "정상팀", "_master": "ok-m#1", "_cards": "t/ok", "ok-m#1": {"role": "master"}}, ["ok-m#1"])
    board.seats("bad", {"_label": "사라진팀", "_master": "bad-m#1", "_cards": "t/nope", "bad-m#1": {"role": "master"}}, ["bad-m#1"])
    r = board.run("collect")
    assert r.returncode == 0, r.stderr
    assert f"ERROR seats-bad.json: 카드 폴더 없음 — {board.root / 't' / 'nope'}" in r.stderr


# ── r1024 — 팀 줄이 슬랙 뿌리 글 되읽기 가드(r1004)에 «표 줄» 로 세이지 않는다(칸 구분 « · ») ──
def _mods():
    """ft_board_teams(갈래 5) + root_readback_guard.check(판정기 그대로) — 시험 판정기는 가드의 실제 함수."""
    import importlib.util
    kit = BIN.parent / "kit" / "slack-mirror"
    sys.path.insert(0, str(kit))
    spec = importlib.util.spec_from_file_location("ft_board_teams_r1024", BIN / "ft_board_teams.py")
    tb = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(tb)
    import root_readback_guard as guard
    return tb, guard


def _branches() -> list[dict]:
    """반례 집합 5갈래 — 확인 못 함(수집 오류) · 확인 불가(팀 상태 없음) · 일함 · 일함 없음 · 끝 «확인 불가 N»."""
    return [
        {"label": "오류팀", "error": "카드 폴더 없음 — /t/nope"},
        {"label": "옛팀", "progress": {"카드X": 1}},
        {"label": "일함팀", "progress": {}, "team_state": {"label": "진행 · 일하는 좌석 1/2", "working": ["a-n#0"], "unknown": 0}},
        {"label": "정지팀", "progress": {"카드A": 1}, "team_state": {"label": "대기 5분 · 기다리는 것 = 회신 대기", "working": [], "unknown": 0}},
        {"label": "빈팀", "progress": {}, "team_state": {"label": "쉼 · 열린 좌석 0", "working": [], "unknown": 3}},
    ]


def test_team_lines_have_no_table_rows_for_root_guard() -> None:
    """C1 — 갈래 5 전부: 줄당 파이프 ≤1 · 뿌리 글(첫 줄 → 👥 → 팀 줄 → 트리 → 끝줄) check() == None."""
    tb, guard = _mods()
    lines = tb.team_lines({"teams": _branches()})
    assert len(lines) == 5, lines
    assert [ln.count("|") for ln in lines] == [0] * 5, lines
    assert lines[0].startswith("오류팀 · 확인 못 함: "), lines[0]
    assert lines[1] == "옛팀 · 확인 불가(팀 상태 없음) · 진행 1(카드X)", lines[1]
    assert lines[2] == "일함팀 · 진행 · 일하는 좌석 1/2 · 일함 a-n#0 · 진행 0", lines[2]
    assert lines[4].endswith("· 확인 불가 3"), lines[4]
    root = "\n".join(["확인 중 0 · 소유자 미확인 0", "👥 팀별 지금", *lines, "  · 카드A — 착수", "❓ 오빠가 정할 것 (0건)"])
    assert guard.check(root) is None, guard.check(root)


def test_teams_stdout_passes_root_guard(board) -> None:
    """C1 실 발행 경로 — ft-board.py teams 출력으로 만든 뿌리 글이 가드를 통과한다(«표 줄 14개» 회귀 재현 금지)."""
    _, guard = _mods()
    board.seats("a", {"_label": "일함팀", "_master": "a-m#1", "a-m#1": {"role": "master"}, "a-n#0": {"role": "nano"}}, ["a-m#1", "a-n#0"])
    board.seats("bad", {"_label": "사라진팀", "_master": "bad-m#1", "_cards": "t/nope", "bad-m#1": {"role": "master"}}, ["bad-m#1"])
    _turn(board.root, "a-n#0", "WORKING", 3)
    r = board.run("teams")
    assert r.returncode == 0, r.stderr
    lines = r.stdout.splitlines()
    assert lines and all(ln.count("|") == 0 for ln in lines), lines
    root = "\n".join(["확인 중 0 · 소유자 미확인 0", "👥 팀별 지금", *lines, "  · 카드A — 착수", "❓ 오빠가 정할 것 (0건)"])
    assert guard.check(root) is None, guard.check(root)
