"""r850 — 뉴스 팀 지도 팀 상태 3값(진행 · 대기 · 쉼) + «확인 불가» 는 좌석 cwd 로 jsonl 재탐색 뒤에만.
옛 판정 = «지금 이 순간 WORKING 좌석 수» 하나 → 60초 틱 사이에 턴이 끝난 팀·나노 결과를 기다리는 팀이 «쉬는 팀»(13:51 ops·knowledge) ·
승계로 이름표가 파일 머리 1MB 밖에 있는 좌석은 «확인 불가(jsonl 없음)»(feature).
시험 입력 = 임시 루트(명부 · 팀 진행 카드) · 가짜 tmux(list-panes) · 좌석 cwd 아래 jsonl 픽스처 · FT_NEWS_NOW 고정 — 실 tmux·실 좌석·모델·슬랙 0.
  ⓐ 진행 카드 1 · 좌석 2 IDLE(10분 전 턴) → «진행»(옛 판 «쉬는 팀»)   ⓑ 진행 카드 1 · 좌석 1 IDLE(45분 전) → «대기» + 기다리는 것 1줄
  ⓒ 진행 카드 0 → «쉼»(좌석 수 무관)   ⓓ 이름으로 못 찾음 → cwd 재탐색 · 다른 좌석 파일 안 집음 · 그래도 없음 = «확인 불가(jsonl 없음 N석)» · 상한 넘김 = «시간 초과»
  ⓔ 요약 첫 줄·지도·시트 뿌리 글 팀 표(ft_board_teams)가 같은 judge 글자   ⓕ 변이 3종(진행 카드 조건 · 30분 창 · cwd 재탐색 삭제 → FAIL)
  r2(DA⑥ r1 HOLD 4): ⓖ 카드 0 + 열린 턴 = «진행 · 진행 카드 0 · …» · 카드 0 + 30분 안 IDLE 만 = «쉼»   ⓗ 재탐색 꼬리 읽기가 마감을 넘기면 그 값 버림 → «시간 초과»
  ⓘ 좌석 = 명부 현역(은퇴 세대 접두사 수집 0) → 뉴스·지도·시트 같은 «대기 45분»   ⓙ 좌석 0 갈래에도 «기다리는 것 = …»   변이 4종
  r3(DA⑥ r2 HOLD 3 · 재설계): ⓡ1 판독 전체 바깥 마감 7초(벽시계 ≤ 7.5초)   ⓡ2 팀 단위 격리(원천 하나 오류 = 그 팀만)
  ⓡ3b r1 반례 3 회귀   변이(바깥 상한 · 팀 try)
  r4(DA⑥ r3 HOLD 5 · 축소 재설계): ⓢ1 TERM 무시 + 손자 → 벽시계 ≤ 7.5초 · 무리 kill   ⓢ2 느린·깨진 팀만 «시간 초과»·«원천 오류»
  ⓢ3 스냅샷 master 모양 오류 = 그 팀만 원천 오류   ⓢ4 명부에 없는 같은 계보 세션 무시   ⓢ5 _master 없는 명부 = 뉴스·지도·시트 같은 글자
  ⓢ6 명부 #1 죽음 · #2 만 살아 있음 = «확인 불가(명부 현역 세션 없음)»   변이 5종
  r5(DA⑥ r4 HOLD 2 · 원천 1회 · 하위 1개 흘려 받기 · 팀 단위 격리 · 빈 원천 오류 · 발행 등급): ⓣ1 파일 핸들 한도 32 · 20팀 ·
  판독 8초 → 예외 전파 0 · 벽시계 ≤ 7.5초 · 마감 전 팀 = 실제 값 · 못 끝낸 팀 = «확인 불가(시간 초과)» · 마감 뒤 손자 완료 표식 0
  ⓣ1b 하위 생성 실패(EMFILE 24) → 전 팀 «확인 불가(판정 시작 실패 24)» + ERROR 1   ⓣ2 빈 원천 5종 = «기다리는 값 모름(원천 모양 오류)» + ERROR 1
  ⓣ3 깨진 jsonl 한 줄 = 그 팀만   ⓣ5 흘려 받기 꼬리 줄 버림·stderr 상속   ⓣ6 마감 뒤 줄 버림   ⓣ7 발행 등급 PARTIAL·ALL-UNKNOWN
  변이(끝에 한 번 받기 · 빈 값 검사 삭제 · 마감 뒤 줄 사용)
  r6(DA⑥ r5 HOLD 4 · 마감 입구 1개 · tmux 도 무리째 · 바깥 try · 등급 줄): ⓤ1 핸들 고갈 → 예외 전파 0 · ⓤ2 느린 tmux ≤ 7.5초 · ⓤ3 반환 뒤 자손 0 · ⓤ4 시트 등급 줄
  r7(DA⑥ r6 HOLD 3 · 부모 = 얇은 감독자): ⓤ1 하위가 알린 무리까지 반환 전 ESRCH(TERM 무시 손자) ⓤ2 핸들 고갈 = «판정 시작 실패» ⓤ3 ALL-UNKNOWN 1줄
  ⓤ4 하위 첫 줄 없음 · 명부 0개 raise   ⓤ5 부모 Popen 1회 · roster_files·import ft_team_turns 0   변이 5
  시트 = ft_board_collect.attach_team_states → ft_board_teams.team_line(뉴스와 같은 team_states 결과 · 시트 따로 판정 0)
실행: (팩 폴더에서) pytest -q harness/tests/scripts/test_news_team_state_r850.py
"""
import json
import os
import re
import sys
import time
import types
from datetime import datetime
from pathlib import Path

import pytest

BIN = Path(__file__).resolve().parents[2] / "bin"
sys.path[:0] = [str(BIN)]

import ft_board_teams as bt  # noqa: E402
import ft_news_html as fh  # noqa: E402
import ft_news_html_render as fr  # noqa: E402
import ft_board_collect as bc  # noqa: E402
import ft_team_state as ts  # noqa: E402
import ft_team_turns as tt  # noqa: E402
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

NOW = "2026-10-24 14:00"
NOW_DT = datetime(2026, 10, 24, 14, 0)
WAIT = "추정: x-arch#1 에 마지막 발신 #7(13:10) · 기록상 이후 x-arch#1 회신 없음"
# 명부 현역(ft_board_roster.select) — master = 포인터 · 나노 = 계보 #0 단일 생존(r2: 뉴스도 시트와 같은 좌석 집합)
ROSTER = {t: {"_master": m, m: {"role": "master"}, **({n: {"role": "nano"}} if n else {})}
          for t, m, n in (("x", "byz-x-master#1", "byz-x-nano#0"), ("y", "byz-y-master#1", ""), ("z", "byz-z-master#1", "byz-z-nano#0"),
                          ("f", "byz-f-master#2", "byz-f-nano#0"))}


def _jsonl(path: Path, names: list[str], end: str | None, opened: bool = False) -> None:
    """머리 이름표 names[0] + (이름이 2개 이상이면 1.1MB 채움 = 나머지 이름표는 머리 1MB 밖) + 턴 1개(끝 시각 end) + 꼬리 이름표 names[1:].
    opened 면 끝 뒤 user 1줄 = 열린 턴."""
    rows = [{"type": "custom-title", "customTitle": n} for n in names[:1]]
    if len(names) > 1:
        rows.append({"type": "assistant", "message": {"content": [{"type": "text", "text": "채움" * 400_000}]}})
    rows += [{"type": "user", "message": {"content": "일"}}, {"type": "assistant", "message": {"content": []}}]
    if end:
        rows.append({"type": "system", "subtype": "turn_duration", "timestamp": end, "durationMs": 1000})
    rows += [{"type": "custom-title", "customTitle": n} for n in names[1:]]
    if opened:
        rows.append({"type": "user", "message": {"content": "다음"}})
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(r, ensure_ascii=False, separators=(",", ":")) + "\n" for r in rows), encoding="utf-8")


def _enc(cwd: str) -> str:
    return re.sub(r"[^A-Za-z0-9]", "-", cwd)


@pytest.fixture
def world(tmp_path, monkeypatch):
    """팀 x(진행 1 · 2석 10분 전) · y(진행 1 · 1석 45분 전) · z(진행 0 · 2석 5분 전) · f(진행 1 · 1석 = 이름표가 꼬리에만 · 1석 = jsonl 없음)."""
    root, projects = tmp_path / "root", tmp_path / "projects"
    fable = root / ".fable-team"
    cards = {"x": ["c-x"], "y": ["c-y"], "z": [], "f": ["c-f"]}
    for team, ids in cards.items():
        (root / "cards" / team / "대기").mkdir(parents=True)
        (root / "cards" / team / "진행").mkdir(parents=True)
        (root / "cards" / team / "대기" / "q.md").write_text("# 대기\n", encoding="utf-8")
        for i in ids:
            (root / "cards" / team / "진행" / f"{i}.md").write_text("# 진행\n", encoding="utf-8")
        fable.mkdir(parents=True, exist_ok=True)
        (fable / f"seats-{team}.json").write_text(json.dumps({"_cards": f"cards/{team}", **ROSTER[team]}), encoding="utf-8")
    seats = {"byz-x-master#1": ("2026-10-24T13:50:00", ["byz-x-master#1"]), "byz-x-nano#0": ("2026-10-24T13:51:00", ["byz-x-nano#0"]),
             "byz-y-master#1": ("2026-10-24T13:15:00", ["byz-y-master#1"]),
             "byz-z-master#1": ("2026-10-24T13:55:00", ["byz-z-master#1"]), "byz-z-nano#0": ("2026-10-24T13:55:00", ["byz-z-nano#0"]),
             "byz-f-master#2": ("2026-10-24T13:40:00", ["byz-f-master#1", "byz-f-master#2"])}  # 승계 — 머리 #1 · 꼬리 #2
    panes = []
    for s, (end, names) in seats.items():
        cwd = f"/wt/{s.split('#')[0]}"
        _jsonl(projects / _enc(cwd) / f"{s.replace('#', '_')}.jsonl", names, end)
        panes.append(f"{s}\t{cwd}")
    panes.append("byz-f-nano#0\t/wt/byz-f-nano")  # jsonl 없음(pi 좌석 꼴)
    tmux = tmp_path / "tmux"
    tmux.write_text("#!/bin/sh\ncat <<'EOF'\n" + "\n".join(panes) + "\nEOF\n", encoding="utf-8")
    tmux.chmod(0o755)
    snap = fable / "state" / "board" / "2026-10-24"
    snap.mkdir(parents=True)
    (snap / "135900-abc.json").write_text(json.dumps({"teams": [{"key": "y", "master": "byz-y-master#1",
                                                                  "seats": {"byz-y-master#1": {"wait": WAIT}}}]}, ensure_ascii=False), encoding="utf-8")
    (tmp_path / "resume").mkdir()
    for k, v in {"FT_TMUX": str(tmux), "FT_CLAUDE_PROJECTS": str(projects), "FT_NEWS_NOW": NOW, "FT_SEAT_RESUME_DIR": str(tmp_path / "resume")}.items():
        monkeypatch.setenv(k, v)
    monkeypatch.setattr(fh, "_sessions", lambda *_a: [*seats, "byz-f-nano#0"])
    return types.SimpleNamespace(root=root, projects=projects, tmux=str(tmux), seats=seats)


def _live(world) -> dict:
    return {t["team"]: t for t in fh.live_teams(world.root)}


def _payload(world, alive=None) -> dict:
    """team_states 가 하위에 넘기는 한 장(r7) — 경로 문자열만 · 탐색 0. child_teams·run_teams 를 직접 부르는 시험이 쓴다."""
    return {"root": str(world.root), "now": NOW_DT.isoformat(), "teams": [],
            "rosters": {t: str(p) for t, p in ts.roster_files(world.root).items()},
            "alive": None if alive is None else sorted(alive), "alive_auto": alive is None, "alive_why": "",
            "boards": None, "boards_mode": "snapshot", "tmux": world.tmux, "projects": str(world.projects)}


# ⓐ 빨강 먼저(옛 판 = x 가 facts «쉬는 팀») — 진행 카드 1 · 좌석 2 IDLE · 마지막 턴 9~10분 전 → «진행»
def test_a_idle_seats_with_progress_card_and_recent_turn_is_progress(world):
    x = _live(world)["x"]
    assert (x["state"], x["label"], x["working"]) == ("진행", "진행 · 9분 전 턴", 0)
    facts = fh.facts(list(_live(world).values()), "모름")
    assert "x" in facts["진행"] and "x" not in facts["쉼"]


# ⓑ 진행 카드 1 · 좌석 1 IDLE · 마지막 턴 45분 전 → «대기» + 기다리는 값 1줄(보드 스냅샷 master 칸 그대로 · 없으면 «기다리는 값 모름»)
def test_b_quiet_over_window_with_card_is_waiting_with_wait_line(world, tmp_path):
    y = _live(world)["y"]
    assert (y["state"], y["label"]) == ("대기", f"대기 45분 · 기다리는 것 = {WAIT}")
    assert ts.judge(1, [("IDLE", "", 45)], "")[1] == "대기 45분 · 기다리는 것 = 기다리는 값 모름"
    assert ts.judge(1, [], "")[1] == "대기 · 열린 좌석 0 · 기다리는 것 = 기다리는 값 모름"  # r2 ④ 좌석 0 갈래도 기다리는 값


# ⓒ 진행 카드 0 → «쉼»(좌석 수·최근 턴 무관) · 열린 턴이면 사실대로 «진행»
def test_c_no_progress_card_is_rest_regardless_of_seats(world):
    z = _live(world)["z"]
    assert (z["state"], z["label"], z["live"]) == ("쉼", "쉼 · 진행 카드 0", 2)
    assert ts.judge(0, [("?", "jsonl 없음", None)])[0] == "쉼"
    assert ts.judge(0, [("WORKING", "", None)])[0] == "진행"


# ⓓ 이름표가 머리 1MB 밖(승계) → cwd 폴더 재탐색으로 찾음 · 그래도 없는 좌석만 «확인 불가(jsonl 없음 1석)»
def test_d_rescan_by_cwd_then_unknown_only_when_still_missing(world):
    got = tt.seat_turns_now(["byz-f-master#2", "byz-f-nano#0"], world.tmux, world.projects, NOW_DT)
    assert got["byz-f-master#2"] == ("IDLE", "", 20)
    assert got["byz-f-nano#0"] == ("?", "jsonl 없음", None)
    f = _live(world)["f"]
    assert (f["state"], f["label"]) == ("진행", "진행 · 20분 전 턴")  # 찾은 좌석의 30분 안 턴이 있으면 확인 불가 좌석이 있어도 진행
    only_missing = ts.judge(1, [got["byz-f-nano#0"]])
    assert only_missing == ("확인 불가", "확인 불가(jsonl 없음 1석)")


def test_d_rescan_never_takes_other_seat_file_or_older_name(world, tmp_path):
    d = world.projects / _enc("/wt/byz-g-master")
    _jsonl(d / "other.jsonl", ["byz-g-x#9", "byz-g-master#4", "byz-g-nano#0"], "2026-10-24T13:59:00")  # 꼬리에 #4 가 있어도 마지막 이름 = 다른 좌석
    _jsonl(d / "old.jsonl", ["byz-g-master#3"], "2026-10-24T13:58:00")  # 옛 이름(머리만) · #4 없음
    (tmp_path / "tmux").write_text("#!/bin/sh\necho 'byz-g-master#4\t/wt/byz-g-master'\n", encoding="utf-8")
    got = tt.seat_turns_now(["byz-g-master#4"], str(tmp_path / "tmux"), world.projects, NOW_DT)
    assert got == {"byz-g-master#4": ("?", "jsonl 없음", None)}


def test_d_rescan_over_budget_is_time_out_unknown(world):
    got = tt.seat_turns_now(["byz-f-master#2"], world.tmux, world.projects, datetime(2026, 10, 24, 14, 0), budget_s=-1)
    assert got == {"byz-f-master#2": ("?", "시간 초과", None)}
    assert ts.judge(1, [got["byz-f-master#2"]])[1] == "확인 불가(시간 초과 1석)"


# ⓔ 요약 첫 줄 · 지도 · 시트 뿌리 글 팀 표 = 같은 judge 글자
def test_e_status_line_map_and_sheet_table_share_one_verdict(world, tmp_path, monkeypatch):
    live = list(_live(world).values())
    c = fr.bucket([], live)
    status = fr.status_line(c)
    assert status == "진행 팀 2개: f, x. 대기 팀 1개: y. 쉬는 팀 1개: z"
    cards = "".join(t["seats"] for t in c["working"]) + "".join(t["text"] for t in c["resting"] + c["unknown"])
    for t in live:
        assert t["label"] in cards, t["team"]
    sheet = _sheet(world)
    for t in live:
        assert _mid(sheet[t["team"]]) == t["label"], (sheet[t["team"]], t["label"])  # 시트 표 가운데 칸 = 뉴스 label 바이트 그대로


def _snap(world) -> Path:
    return world.root / ".fable-team" / "state" / "board" / "2026-10-24" / "135900-abc.json"


def _sheet(world, cells: dict | None = None) -> dict[str, str]:
    """시트 경로 그대로 — 블록(보드 스냅샷 꼴: master · seats 의 master 칸 wait) → ft_board_collect.attach_team_states → ft_board_teams.team_line.
    블록 = 뉴스가 읽는 보드 스냅샷 블록 그대로 · 스냅샷에 없는 팀 = 명부 _master 칸 wait «»(collect Mail.wait 가 «» 인 꼴) · cells = 팀 → 좌석 칸 덮어쓰기."""
    by = {b["key"]: b for b in json.loads(_snap(world).read_text(encoding="utf-8"))["teams"]}
    files = sorted((world.root / ".fable-team").glob("seats-*.json"))
    blocks = []
    for f in files:
        k, r = f.stem[len("seats-"):], json.loads(f.read_text(encoding="utf-8"))
        m = r.get("_master")
        b = by.get(k) or {"master": m, "seats": {m: {"wait": ""}} if isinstance(m, str) and m in r else {}}
        prog = {p.stem: {} for p in (world.root / "cards" / k / "진행").glob("*.md")}
        blocks.append({"key": k, "label": k, "master": b["master"], "seats": (cells or {}).get(k, b["seats"]), "cards_dir": r.get("_cards"), "progress": prog})
    bc.attach_team_states(world.root, set(fh._sessions()), NOW_DT, blocks, files)
    return {b["key"]: bt.team_line(b) for b in blocks}


def _mid(line: str) -> str:
    """시트 줄 가운데 칸에서 «· 일함 …» 꼬리를 뗀 팀 상태 글자."""
    return line.split(" | ")[1].split(" · 일함 ")[0]


# ⓕ 변이 3종 — 판정기 소스를 바꾼 사본이 ⓐ·ⓒ·ⓓ 를 FAIL 시킨다(변이가 안 걸리면 시험이 그 조건을 안 본다)
def _mutant(old: str, new: str, fname: str = "ft_team_state.py") -> types.ModuleType:
    src = (BIN / fname).read_text(encoding="utf-8")
    assert src.count(old) == 1, old
    mod = types.ModuleType(fname[:-3] + "_mutant")
    mod.__file__ = str(BIN / fname)
    exec(compile(src.replace(old, new), mod.__name__, "exec"), mod.__dict__)  # noqa: S102 — 시험 전용 변이 사본
    return mod


def test_f_mutations_are_caught():
    no_card = _mutant("    if cards == 0 or (cards is None and not unknown):", "    if cards is None and not unknown:")
    assert no_card.judge(0, [("IDLE", "", 5), ("IDLE", "", 5)])[0] != "쉼"  # ⓒ FAIL
    no_window = _mutant("recent = min((n for n in idle if n < WINDOW_MIN), default=None)", "recent = None")
    assert no_window.judge(1, [("IDLE", "", 10), ("IDLE", "", 9)])[0] != "진행"  # ⓐ FAIL
    assert ts.judge(0, [("IDLE", "", 5), ("IDLE", "", 5)])[0] == "쉼" and ts.judge(1, [("IDLE", "", 10), ("IDLE", "", 9)])[0] == "진행"


def test_f_mutation_no_rescan_is_caught(world):
    no_rescan = _mutant("    if missing:\n        more, late = rescan(", "    if False:\n        more, late = rescan(", "ft_team_turns.py")
    got = no_rescan.seat_turns_now(["byz-f-master#2"], world.tmux, world.projects, NOW_DT)
    assert got["byz-f-master#2"] != ("IDLE", "", 20)  # ⓓ FAIL
    assert os.environ["FT_TMUX"] == world.tmux


# ── r2(DA⑥ r1 HOLD 4) ────────────────────────────────────────────────────────────────────────────────────────────────

class _Mail:  # 시트 SeatCells 의 우편 원천 스텁 — 기다리는 것 «» · 완료 선언 0
    def wait(self, name, decl):
        return ""

    def declaration(self, name):
        return None


def _add_team(world, monkeypatch, team: str, cards: list[str], roster: dict, ends: dict[str, tuple[str, bool]]) -> None:
    """world 에 팀 1개를 더한다 — 명부 · 진행 카드 · 좌석마다 jsonl(끝 시각 · 열린 턴) · 가짜 tmux pane 줄 · tmux 세션 목록."""
    (world.root / "cards" / team / "진행").mkdir(parents=True)
    for c in cards:
        (world.root / "cards" / team / "진행" / f"{c}.md").write_text("# 진행\n", encoding="utf-8")
    (world.root / ".fable-team" / f"seats-{team}.json").write_text(json.dumps({"_cards": f"cards/{team}", **roster}), encoding="utf-8")
    lines = []
    for s, (end, opened) in ends.items():
        cwd = f"/wt/{s.replace('#', '-')}"
        _jsonl(world.projects / _enc(cwd) / f"{s.replace('#', '_')}.jsonl", [s], end, opened)
        lines.append(f"{s}\t{cwd}")
    tmux = Path(world.tmux)
    tmux.write_text(tmux.read_text(encoding="utf-8").replace("\nEOF\n", "\n" + "\n".join(lines) + "\nEOF\n"), encoding="utf-8")
    sessions = fh._sessions()
    monkeypatch.setattr(fh, "_sessions", lambda *_a: [*sessions, *ends])


def _map_text(live: list[dict]) -> str:
    c = fr.bucket([], live)
    return "".join(t["seats"] for t in c["working"]) + "".join(t["text"] for t in c["resting"] + c["unknown"])


# ⓖ 카드 0 + 열린 턴 1 → «진행 · 진행 카드 0 · …»(계약 개정) · 카드 0 + 30분 안 IDLE 만 → «쉼» · 뉴스·지도·시트 같은 글자
def test_g_no_card_with_open_turn_is_progress_marked_no_card(world, monkeypatch):
    _add_team(world, monkeypatch, "g", [], {"_master": "byz-g-master#1", "byz-g-master#1": {"role": "master"}},
              {"byz-g-master#1": ("2026-10-24T13:50:00", True)})
    live = _live(world)
    assert (live["g"]["state"], live["g"]["label"]) == ("진행", "진행 · 진행 카드 0 · 일하는 좌석 1/1")
    assert ts.judge(0, [("IDLE", "", 10)]) == ("쉼", "쉼 · 진행 카드 0")
    assert live["g"]["label"] in _map_text(list(live.values()))
    assert _sheet(world)["g"].split(" | ")[1] == live["g"]["label"] + " · 일함 byz-g-master#1"  # 시트 = 같은 글자 + 일함 좌석 꼬리


def _slow_clock(mod, monkeypatch, delay: float) -> types.SimpleNamespace:
    """가짜 시계 — 꼬리 읽기(_last_name) 1회가 delay 초 걸린 것처럼 시계를 민다(실제 대기 0 · 걸린 시간은 가짜 시계로 잰다)."""
    import time as real
    clock = types.SimpleNamespace(t=0.0)
    real_last = mod._last_name

    def slow(path):
        clock.t += delay
        return real_last(path)
    monkeypatch.setattr(mod, "time", types.SimpleNamespace(monotonic=lambda: clock.t, time=real.time))
    monkeypatch.setattr(mod, "_last_name", slow)
    return clock


# ⓗ 재탐색 꼬리 읽기 7.1초 → 그 값 버림 «확인 불가(시간 초과)» · 걸린 시간 ≤ 7.5초
def test_h_rescan_value_read_after_deadline_is_discarded(world, monkeypatch):
    clock = _slow_clock(tt, monkeypatch, 7.1)
    got = tt.seat_turns_now(["byz-f-master#2"], world.tmux, world.projects, NOW_DT)
    assert got == {"byz-f-master#2": ("?", "시간 초과", None)}
    assert clock.t <= 7.5


# ⓘ 명부에 #1·#2 두 행(은퇴 표시 없음) · 둘 다 살아 있음 → 계보 최고 번호 #2(45분 전)만 판정 → 뉴스·지도·시트 모두 «대기 45분»
def test_i_retired_generation_is_not_collected_news_map_sheet_same(world, monkeypatch):
    roster = {"_master": "byz-i-master#2", "byz-i-master#1": {"role": "master"}, "byz-i-master#2": {"role": "master"}}
    ends = {"byz-i-master#1": ("2026-10-24T13:50:00", False), "byz-i-master#2": ("2026-10-24T13:15:00", False)}
    _add_team(world, monkeypatch, "i", ["c-i"], roster, ends)
    live = _live(world)
    label = "대기 45분 · 기다리는 것 = 기다리는 값 모름"
    assert (live["i"]["state"], live["i"]["label"], live["i"]["live"]) == ("대기", label, 1)
    assert label in _map_text(list(live.values()))
    assert _mid(_sheet(world)["i"]) == label


# ⓙ 진행 카드 1 + 좌석 0(명부 _master 포인터만 · 현역 행 0) → «대기 · 열린 좌석 0 · 기다리는 것 = …» · 뉴스(스냅샷)·시트가 같은 master 칸 규칙
def test_j_no_live_seat_branch_keeps_wait_line(world, monkeypatch):
    assert ts.judge(1, [], "회신 대기") == ("대기", "대기 · 열린 좌석 0 · 기다리는 것 = 회신 대기")
    _add_team(world, monkeypatch, "j", ["c-j"], {"_master": "byz-j-master#1"}, {})
    teams = json.loads(_snap(world).read_text(encoding="utf-8"))["teams"] + [{"key": "j", "master": "byz-j-master#1", "seats": {"byz-j-master#1": {"wait": "회신 대기"}}}]
    _snap(world).write_text(json.dumps({"teams": teams}, ensure_ascii=False), encoding="utf-8")
    j = _live(world)["j"]
    assert (j["state"], j["label"]) == ("대기", "대기 · 열린 좌석 0 · 기다리는 것 = 회신 대기")  # r5 보강 ⓑ3: 세션 0 팀도 master 칸은 있다
    assert _mid(_sheet(world)["j"]) == j["label"]


# r2 변이 4종 — 열린 턴 조건 · 값 쓰기 직전 마감 · 좌석 0 갈래 기다리는 값 · (접두사 수집 → r4 ⓢ4 변이로)
def test_r2_mutations_are_caught(world, monkeypatch):
    no_open = _mutant("    if opened:\n", "    if False:\n")
    assert no_open.judge(0, [("WORKING", "", None)])[0] != "진행"  # ⓖ FAIL
    no_wait = _mutant('return "대기", f"대기 · 열린 좌석 0 · {waiting}"', 'return "대기", "대기 · 열린 좌석 0"')
    assert "회신 대기" not in no_wait.judge(1, [], "회신 대기")[1]  # ⓙ FAIL
    no_deadline = _mutant("            if time.monotonic() > deadline:  # 값을 쓰기 직전 마감", "            if False:  # 값을 쓰기 직전 마감", "ft_team_turns.py")
    _slow_clock(no_deadline, monkeypatch, 7.1)
    got = no_deadline.seat_turns_now(["byz-f-master#2"], world.tmux, world.projects, NOW_DT)
    assert got["byz-f-master#2"] != ("?", "시간 초과", None)  # ⓗ FAIL


# ── r3(DA⑥ r2 HOLD 3 · 하드 룰 14 재설계) ─────────────────────────────────────────────────────────────────────────────

def _slow_child(tmp_path, monkeypatch, name_s: float, turn_s: float, only: str = "", term_ignore: bool = False) -> None:
    """판독 하위 프로세스만 느리게 — sitecustomize(PYTHONPATH)가 하위 프로세스 안의 ft_team_turns 이름표 읽기·턴 판독에 sleep 을 건다(제품 코드 훅 0).
    only = 그 글자가 경로에 든 jsonl 의 턴 판독만 느리게 · term_ignore = 하위가 SIGTERM 무시(DA⑥ r3 반례 1)."""
    d = tmp_path / f"slowsite-{name_s}-{turn_s}-{only or 'all'}-{int(term_ignore)}"
    d.mkdir()
    (d / "sitecustomize.py").write_text(
        "import signal, sys, time\n"
        f"sys.path.insert(0, {str(BIN)!r})\n"
        + ("signal.signal(signal.SIGTERM, signal.SIG_IGN)\n" if term_ignore else "")
        + "import ft_team_turns as m\n"
        "_ln, _tf = m._last_name, m.turn_of_file\n"
        f"m._last_name = lambda p: (time.sleep({name_s}), _ln(p))[1]\n"
        f"m.turn_of_file = lambda p: (time.sleep({turn_s}) if {only!r} in str(p) else None, _tf(p))[1]\n", encoding="utf-8")
    monkeypatch.setenv("PYTHONPATH", str(d))


def _timed(fn, *a):
    start = time.monotonic()
    got = fn(*a)
    return got, time.monotonic() - start


# ⓡ1 DA r2 반례 1 — 이름표 8초 → 벽시계 ≤ 7.5초 · «확인 불가(시간 초과)» · 이름표 6초 + 턴 판독 2초 → 같음(진행 0)
def test_r1_outer_deadline_bounds_wall_clock(world, tmp_path, monkeypatch):
    _slow_child(tmp_path, monkeypatch, 8, 0)  # 이름표 읽기 8초 — 판정 전체 마감(6초 TERM)이 먼저 끊는다
    live, wall = _timed(_live, world)
    assert (live["f"]["state"], live["f"]["label"]) == ("확인 불가", "확인 불가(시간 초과)") and wall <= 7.5, (live["f"], wall)
    _slow_child(tmp_path, monkeypatch, 6, 2)  # 이름표 6초 + 턴 판독 2초 = 8초
    live, wall = _timed(_live, world)
    assert (live["f"]["state"], live["f"]["label"]) == ("확인 불가", "확인 불가(시간 초과)") and wall <= 7.5, (live["f"], wall)


# ⓡ2 DA r2 반례 2 — x 정상 + y 기다림 원천 `seats:["깨진 칸"]` + w 명부 _cards 모양 오류 → x 그대로 · y·w 그 팀만 원천 오류 · 예외 전파 0 · 팀마다 ERROR 1
def _broken_sources(world):
    _snap(world).write_text(json.dumps({"teams": [{"key": "y", "master": "byz-y-master#1", "seats": ["깨진 칸"]}]}, ensure_ascii=False), encoding="utf-8")
    (world.root / ".fable-team" / "seats-w.json").write_text(json.dumps({"_cards": 5}), encoding="utf-8")


def test_r2_one_broken_source_isolated_to_its_team(world, caplog):
    _broken_sources(world)
    with caplog.at_level("ERROR"):
        live = _live(world)
    assert (live["x"]["state"], live["x"]["label"]) == ("진행", "진행 · 9분 전 턴")
    for t in ("y", "w"):  # r4: 기다림 원천 모양 오류도 그 팀 판정 try 안 = «확인 불가(원천 오류 …)»
        assert live[t]["state"] == "확인 불가" and live[t]["label"].startswith("확인 불가(원천 오류 TypeError"), live[t]
    errors = [r.getMessage() for r in caplog.records if r.levelname == "ERROR"]
    assert sum(" y " in m for m in errors) == 1 and sum(" w " in m for m in errors) == 1, errors


# ⓡ3b r1 반례 3 회귀 — 명부 #2 · 살아 있는 #1(10분 전)·#2(45분 전) → «대기 45분»(뉴스·지도·시트 같은 글자)
def test_r3b_retired_lower_generation_alive_is_ignored(world, monkeypatch):
    roster = {"_master": "byz-k-master#2", "byz-k-master#2": {"role": "master"}}
    ends = {"byz-k-master#1": ("2026-10-24T13:50:00", False), "byz-k-master#2": ("2026-10-24T13:15:00", False)}
    _add_team(world, monkeypatch, "k", ["c-k"], roster, ends)
    live = _live(world)
    label = "대기 45분 · 기다리는 것 = 기다리는 값 모름"
    assert (live["k"]["state"], live["k"]["label"], live["k"]["live"]) == ("대기", label, 1)
    assert label in _map_text(list(live.values()))
    assert _mid(_sheet(world)["k"]) == label


# r5 변이 — 빈 값 검사 삭제 → ⓣ2 FAIL(조용한 «기다림 확인 불가(master 칸 없음)» 로 되돌아간다)
def test_t2_mutation_empty_source_check_removed_is_caught():
    no_shape = _mutant('    if not master or not seats:  # 빈 원천 — [] · 0 · "" · null · {} 는 «모름» 이 아니라 «모양 오류»\n',
                       '    if False:  # 변이: 빈 값 검사 삭제\n')
    assert no_shape.wait_of({"key": "y", "master": "byz-y-master#1", "seats": {}})[0] != ts.WAIT_SHAPE
    assert ts.wait_of({"key": "y", "master": "byz-y-master#1", "seats": {}})[0] == ts.WAIT_SHAPE


# ── r4(DA⑥ r3 HOLD 5 · 축소 재설계) ─────────────────────────────────────────────────────────────────────────────────

def _grandchild_tmux(tmp_path) -> tuple[str, Path]:
    """가짜 tmux — 손자(백그라운드 sleep 9 → 완료 표식) + 본체 sleep 12. 무리 kill 이면 표식 0."""
    mark, stub = tmp_path / "grandchild-done", tmp_path / "tmux-slow"
    stub.write_text(f"#!/bin/sh\n(sleep 9; touch '{mark}') &\nsleep 12\n", encoding="utf-8")
    stub.chmod(0o755)
    return str(stub), mark


# ⓢ1 DA r3 반례 1 — 하위가 TERM 무시 + 판독 12초(tmux 손자 9초) → 벽시계 ≤ 7.5초 · 그 팀 «시간 초과» · 손자 완료 표식 0
def test_s1_term_ignored_child_and_grandchild_killed_as_group(world, tmp_path, monkeypatch):
    stub, mark = _grandchild_tmux(tmp_path)
    _slow_child(tmp_path, monkeypatch, 0, 12, term_ignore=True)
    monkeypatch.setenv("FT_TMUX", stub)  # 하위의 list_panes(손자) 가 9초 · 본체는 12초
    live, wall = _timed(_live, world)
    assert live["f"]["state"] == "확인 불가" and "시간 초과" in live["f"]["label"] and wall <= 7.5, (live["f"], wall)
    time.sleep(max(0.0, 9.8 - wall))
    assert not mark.exists()  # 손자까지 무리 kill(r6: tmux 호출도 자기 무리)


# ⓢ2 반례 2 — a(x) 정상 · b(y) 판독 8초 → x «진행» · y 만 «시간 초과» / y jsonl 에 `[]` 1행 → r5: x «진행» · y 만 «확인 불가(원천 오류 AttributeError …)»
def test_s2_slow_or_broken_team_does_not_touch_other_team(world, tmp_path, monkeypatch, caplog):
    _slow_child(tmp_path, monkeypatch, 0, 8, only="byz-y-master")
    live, wall = _timed(_live, world)
    assert (live["x"]["state"], live["x"]["label"]) == ("진행", "진행 · 9분 전 턴")
    assert (live["y"]["state"], live["y"]["label"]) == ("확인 불가", "확인 불가(시간 초과)") and wall <= 7.5, wall
    monkeypatch.delenv("PYTHONPATH")
    jl = world.projects / _enc("/wt/byz-y-master") / "byz-y-master_1.jsonl"
    jl.write_text(jl.read_text(encoding="utf-8") + "[]\n", encoding="utf-8")
    with caplog.at_level("ERROR"):
        live = _live(world)
    assert (live["x"]["state"], live["x"]["label"]) == ("진행", "진행 · 9분 전 턴")
    assert live["y"]["state"] == "확인 불가" and live["y"]["label"].startswith("확인 불가(원천 오류 AttributeError"), live["y"]
    assert sum("팀 y " in r.getMessage() for r in caplog.records if r.levelname == "ERROR") == 1


# ⓢ3 반례 3 — y 스냅샷 `master:["broken"]` → x 그대로 · y «확인 불가(원천 오류 TypeError …)» · 예외 전파 0
def _broken_master(world):
    _snap(world).write_text(json.dumps({"teams": [{"key": "y", "master": ["broken"], "seats": {}}]}, ensure_ascii=False), encoding="utf-8")


def test_s3_snapshot_master_shape_error_isolated_to_its_team(world):
    _broken_master(world)
    live = _live(world)
    assert (live["x"]["state"], live["x"]["label"]) == ("진행", "진행 · 9분 전 턴")
    assert live["y"]["state"] == "확인 불가" and live["y"]["label"].startswith("확인 불가(원천 오류 TypeError"), live["y"]


# ⓢ4 반례 4 — 명부 byz-a-master#1 IDLE 45분 + 다른 프로젝트의 byz-a-master#9 WORKING(tmux 에만) → «대기 45분»(#9 무시)
def _foreign_session_team(world, monkeypatch):
    _add_team(world, monkeypatch, "a", ["c-a"], {"_master": "byz-a-master#1", "byz-a-master#1": {"role": "master"}},
              {"byz-a-master#1": ("2026-10-24T13:15:00", False), "byz-a-master#9": ("2026-10-24T13:50:00", True)})


def test_s4_session_not_in_roster_is_never_a_seat(world, monkeypatch):
    _foreign_session_team(world, monkeypatch)
    live = _live(world)
    label = "대기 45분 · 기다리는 것 = 기다리는 값 모름"
    assert (live["a"]["state"], live["a"]["label"], live["a"]["live"]) == ("대기", label, 1)
    assert _mid(_sheet(world)["a"]) == label


# ⓢ5 반례 5 — _master 없는 명부 1석 WORKING · 카드 1 → 뉴스·지도·시트 같은 글자(시트가 «현역 근거 없음» 으로 따로 판정 0)
def _no_pointer_team(world, monkeypatch):
    roster = {"byz-p-lead#1": {"role": "master"}}
    _add_team(world, monkeypatch, "p", ["c-p"], roster, {"byz-p-lead#1": ("2026-10-24T13:20:00", True)})
    import ft_board_seat as bs
    monkeypatch.setattr(bs, "turn_row", lambda n: {"state": "WORKING", "turn_end": None, "source": "jsonl"})
    full = {"_cards": "cards/p", **roster}
    return bs.SeatCells(full, {"byz-p-lead#1"}, _Mail(), NOW_DT).all()  # 시트 좌석 칸(collect 와 같은 원천)


def test_s5_roster_without_master_pointer_same_on_news_map_sheet(world, monkeypatch):
    cells = _no_pointer_team(world, monkeypatch)
    live = _live(world)
    assert (live["p"]["state"], live["p"]["label"]) == ("진행", "진행 · 일하는 좌석 1/1")
    assert live["p"]["label"] in _map_text(list(live.values()))
    assert _sheet(world, {"p": cells})["p"].split(" | ")[1] == live["p"]["label"] + " · 일함 byz-p-lead#1"


# ⓢ6 r2 반례 3 의 새 계약 — 명부 #1(죽음) · 살아 있는 #2(명부 밖) → «확인 불가(명부 현역 세션 없음)»(«대기»·«진행» 0) · 뉴스·시트 같은 글자
def test_s6_roster_seat_dead_successor_not_in_roster_is_unknown(world, monkeypatch):
    _add_team(world, monkeypatch, "s", ["c-s"], {"_master": "byz-s-master#1", "byz-s-master#1": {"role": "master"}},
              {"byz-s-master#2": ("2026-10-24T13:20:00", True)})
    s = _live(world)["s"]
    assert (s["state"], s["label"]) == ("확인 불가", "확인 불가(명부 현역 세션 없음 1석)")
    assert _mid(_sheet(world)["s"]) == s["label"]
    assert ts.seat_set({"byz-s-master#1": {"role": "master"}}, None) == ([], {"byz-s-master#1": ("?", "tmux 목록 없음", None)})


# r4 변이 4종 — killpg → 하위만(r7 ⓤ1 변이로 옮김 — 정리 자리가 ft_team_state 로 감) · tmux 세션 좌석 추가 되살림 ·
#   시트 따로 판정 되살림 · 팀 try ① 삭제(판정이 하위로 옴 — child_teams 를 그 자리에서 부른다)
def test_s_mutation_tmux_sessions_added_as_seats_is_caught(world, monkeypatch):
    _foreign_session_team(world, monkeypatch)
    revive = _mutant("    for n in rows:\n", "    for n in [*rows, *(s for s in alive or () if lineage(s) in {lineage(r) for r in rows})]:\n")
    with pytest.raises(KeyError):  # ⓢ4 FAIL — 명부 밖 세션을 좌석으로 넣으려다 터진다
        revive.seat_set({"byz-a-master#1": {"role": "master"}}, {"byz-a-master#9"})
    all_rows = _mutant("    chosen = sorted(top.values())\n", "    chosen = sorted(rows)\n")
    roster = {"byz-i-master#1": {"role": "master"}, "byz-i-master#2": {"role": "master"}}
    assert all_rows.seat_set(roster, {"byz-i-master#1", "byz-i-master#2"}) != (["byz-i-master#2"], {})  # ⓘ FAIL(계보 최고 번호 규칙)


def test_s_mutation_sheet_own_verdict_is_caught(world, monkeypatch):
    cells = _no_pointer_team(world, monkeypatch)
    own = _mutant('    s = t.get("team_state")\n',
                  "    from ft_team_state import judge, master_wait  # 변이: 시트가 좌석 칸으로 따로 판정(r3 꼴)\n"
                  "    rows = [(\"WORKING\", \"\", None) if c.get(\"working\") else (\"?\", c[\"text\"], None) if c.get(\"text\", \"\").startswith(\"확인 불가\")"
                  " else (\"IDLE\", \"\", c.get(\"idle_min\")) for c in t[\"seats\"].values()]\n"
                  "    s = {\"label\": judge(len(t[\"progress\"]) if t.get(\"cards_dir\") else None, rows, master_wait(t))[1],"
                  " \"working\": sorted(n for n, c in t[\"seats\"].items() if c.get(\"working\")), \"unknown\": sum(r[0] == \"?\" for r in rows)}\n",
                  "ft_board_teams.py")
    monkeypatch.setattr(bt, "team_line", own.team_line)
    assert _mid(_sheet(world, {"p": cells})["p"]) != _live(world)["p"]["label"]  # ⓢ5 FAIL


def test_s_mutation_team_try_removed_is_caught(world):
    _broken_master(world)
    no_try = _mutant("        except Exception as e:  # noqa: BLE001 — 팀 단위 격리 ① 명부·좌석 집합·기다림·카드\n", "        except ZeroDivisionError as e:  # 변이\n")
    payload = _payload(world, set(fh._sessions()))
    with pytest.raises(TypeError):
        list(no_try.child_teams(payload))  # ⓢ3 FAIL(예외가 전체로 번진다)
    real = {line["team"]: line for line in ts.child_teams(payload) if "team" in line}
    assert real["y"]["v"]["label"].startswith("확인 불가(원천 오류 TypeError") and real["x"]["v"]["state"] == "진행"


# ── r5(DA⑥ r4 HOLD 2 · 원천 1회 · 하위 1개 흐려 받기 · 팀 단위 격리 · 빈 원천 오류 · 발행 등급) ─────────────────

def _slow_judge(tmp_path, monkeypatch, slow_in: str, turn_s: float, grandchild: Path | None = None) -> None:
    """판정 하위만 느리게 — turn_of_file 이 slow_in 이 든 경로에서만 turn_s 초(그때 손자 하나를 낳는다 · 무리 kill 확인)."""
    d = tmp_path / f"slowjudge-{slow_in}-{turn_s}-{int(bool(grandchild))}"
    d.mkdir(exist_ok=True)
    spawn = f"    subprocess.Popen(['sh', '-c', \"sleep 7; touch '{grandchild}'\"])\n" if grandchild else ""
    (d / "sitecustomize.py").write_text(
        "import subprocess, sys, time\n"
        f"sys.path.insert(0, {str(BIN)!r})\n"
        "import ft_team_turns as m\n"
        "_tf = m.turn_of_file\n"
        "def _slow(p):\n"
        + spawn
        + f"    time.sleep({turn_s})\n"
        "    return _tf(p)\n"
        f"m.turn_of_file = lambda p: _slow(p) if {slow_in!r} in str(p) else _tf(p)\n", encoding="utf-8")
    monkeypatch.setenv("PYTHONPATH", str(d))


def _twenty_teams(world, monkeypatch) -> None:
    """팀 t00~t19(각 1석 · 진행 카드 1 · 10분 전 턴 = «진행») — 팀마다 하위를 띄우면 파일 핸들이 모자라던 양."""
    for i in range(20):
        t = f"t{i:02d}"
        _add_team(world, monkeypatch, t, [f"c-{t}"], {"_master": f"byz-{t}-master#1", f"byz-{t}-master#1": {"role": "master"}},
                  {f"byz-{t}-master#1": ("2026-10-24T13:50:00", False)})


# ⓣ1 DA r4 반례 1 — 파일 핸들 한도 32 · 20팀 · 판독 8초 → 예외 전파 0 · 벽시계 ≤ 7.5초 · 마감 전 끝난 팀 = 실제 값 ·
#     못 끝낸 팀 = «확인 불가(시간 초과)» · 마감 뒤 하위·손자 완료 표식 0(killpg)
def test_t1_many_teams_low_fd_limit_streaming_deadline(world, tmp_path, monkeypatch):
    import resource

    _twenty_teams(world, monkeypatch)
    mark = tmp_path / "judge-grandchild-done"
    _slow_judge(tmp_path, monkeypatch, "byz-t10-master", 8, mark)
    soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
    resource.setrlimit(resource.RLIMIT_NOFILE, (min(soft, 32), hard))
    try:
        live, wall = _timed(_live, world)
    finally:
        resource.setrlimit(resource.RLIMIT_NOFILE, (soft, hard))
    assert (live["t00"]["state"], live["t00"]["label"]) == ("진행", "진행 · 10분 전 턴"), live["t00"]
    assert wall <= 7.5, wall
    assert live["t10"]["label"] == "확인 불가(시간 초과)", live["t10"]
    time.sleep(max(0.0, 7.8 - wall))
    assert not mark.exists()  # 마감 뒤 하위·손자 완료 표식 0


# ⓣ1b 하위 생성 실패 주입(Popen OSError errno 24) → 모든 팀 «확인 불가(판정 시작 실패 24)» + ERROR 1 · 지도 발행 · 예외 0
def test_t1b_child_spawn_failure_is_all_unknown(world, monkeypatch, caplog):
    def boom(*a, **k):
        raise OSError(24, "Too many open files")

    monkeypatch.setattr(ts, "_spawn", boom)
    with caplog.at_level("ERROR"):
        got = ts.team_states(world.root, set(fh._sessions()), NOW_DT, ts.roster_files(world.root))
    assert {v["label"] for v in got.values()} == {"확인 불가(판정 시작 실패 24)"}
    assert sum("판정 하위 생성 실패" in r.getMessage() for r in caplog.records if r.levelname == "ERROR") == 1


# ⓣ2 DA r4 반례 2 — 스냅샷 seats = [] · 0 · "" · null · {} 각각 → 그 팀 «기다리는 값 모름(원천 모양 오류)» + ERROR 1 · 다른 팀 그대로
@pytest.mark.parametrize("shape", [[], 0, "", None, {}], ids=["list", "zero", "empty-str", "null", "dict"])
def test_t2_empty_source_is_shape_error_not_silent_unknown(world, shape, caplog):
    _snap(world).write_text(json.dumps({"teams": [{"key": "y", "master": "byz-y-master#1", "seats": shape}]}, ensure_ascii=False), encoding="utf-8")
    with caplog.at_level("ERROR"):
        live = _live(world)
    assert (live["y"]["state"], live["y"]["label"]) == ("대기", f"대기 45분 · 기다리는 것 = {ts.WAIT_SHAPE}"), live["y"]
    assert (live["x"]["state"], live["x"]["label"]) == ("진행", "진행 · 9분 전 턴")
    assert sum(" y " in r.getMessage() for r in caplog.records if r.levelname == "ERROR") == 1


# ⓣ3 깨진 jsonl `[]` 한 줄(b 팀 좌석) → a 팀 그대로 · b «확인 불가(원천 오류 …)» · ERROR 1
def test_t3_broken_jsonl_row_is_only_that_team(world, caplog):
    jl = world.projects / _enc("/wt/byz-y-master") / "byz-y-master_1.jsonl"
    jl.write_text(jl.read_text(encoding="utf-8") + "[]\n", encoding="utf-8")
    with caplog.at_level("ERROR"):
        live = _live(world)
    assert (live["x"]["state"], live["x"]["label"]) == ("진행", "진행 · 9분 전 턴")
    assert live["y"]["state"] == "확인 불가" and live["y"]["label"].startswith("확인 불가(원천 오류"), live["y"]
    assert sum("팀 y " in r.getMessage() for r in caplog.records if r.levelname == "ERROR") == 1


# ⓣ4 r3 반례 다섯 · r1·r2 회귀 = 앞 절 ⓐ~ⓙ ⓡ1~ⓡ3b ⓢ1~ⓢ6 (그대로 통과 · ⓢ2 둘째 갈래만 r5 계약 «원천 오류» 로 바뀌었다)


# ⓣ5 보강 ⓑ1(fable-5.1 검토 · arch 148) — 부모는 «\n 으로 끝난 줄» 만 쓰고 마감 순간 잘린 꼬리 줄은 버린다(그 팀 = 확인 불가(시간 초과) · 예외 0) ·
#     하위 stderr 는 PIPE 가 아니라 상속(읽지 않는 파이프가 하위를 막는 일 0)
def test_t5_stream_tail_line_dropped_and_stderr_inherited(monkeypatch):
    import io
    import subprocess as sp
    import types

    seen = {}

    class FakeProc:
        pid, returncode = 424242, 0
        stdout = io.StringIO('{"team": "x", "v": {"state": "진행"}}\n{"team": "y", "v": ')

        def wait(self, timeout=None):
            return 0

    def popen(args, **kw):
        seen.update(kw)
        return FakeProc()

    monkeypatch.setattr(ts, "subprocess", types.SimpleNamespace(Popen=popen, PIPE=sp.PIPE, DEVNULL=sp.DEVNULL, TimeoutExpired=sp.TimeoutExpired))
    got, fail = ts.run_teams({"root": "/x", "teams": ["x", "y"]}, ["x", "y"])
    assert "stderr" not in seen  # 넘기지 않는다 = 부모 stderr 상속(PIPE 아님)
    assert got == {"x": {"team": "x", "v": {"state": "진행"}}} and fail is None  # 꼬리 줄(y) = 버린다


# ⓣ6 보강 ⓑ2 — 마감(TERM_S) 시각 뒤에 읽힌 줄은 버린다(그 팀 = 확인 불가(시간 초과)) · killpg ESRCH(이미 끝남) 는 삼킨다
def _slow_stream(rows: list[tuple[str, float]]):
    class SlowStream:
        def __iter__(self):
            for line, at in rows:
                time.sleep(at)
                yield line
    return SlowStream()


def _fake_run(monkeypatch, mod, proc_cls) -> None:
    import subprocess as sp
    import types

    monkeypatch.setattr(mod, "TERM_S", 0.3)
    monkeypatch.setattr(mod, "KILL_S", 0.5)
    monkeypatch.setattr(mod, "subprocess", types.SimpleNamespace(Popen=lambda *a, **k: proc_cls(), PIPE=sp.PIPE, DEVNULL=sp.DEVNULL, TimeoutExpired=sp.TimeoutExpired))


def test_t6_line_read_after_deadline_is_discarded(monkeypatch):
    class FakeProc:
        pid, returncode = 424242, 0
        stdout = _slow_stream([('{"team": "x", "v": {"state": "진행"}}\n', 0.05), ('{"team": "y", "v": {"state": "쉼"}}\n', 0.4)])

        def wait(self, timeout=None):
            return 0

    _fake_run(monkeypatch, ts, FakeProc)
    got, _ = ts.run_teams({"root": "/x", "teams": ["x", "y"]}, ["x", "y"])
    assert "x" in got and "y" not in got, got  # 마감(0.3초) 뒤에 읽힌 y 줄은 버린다


def test_t6_mutation_line_after_deadline_used_is_caught(monkeypatch):
    late = _mutant("        return _parse([line for at, line in out if at <= dl]), fail",
                   "        return _parse([line for _at, line in out]), fail", "ft_team_state.py")

    class FakeProc:
        pid, returncode = 424243, 0
        stdout = _slow_stream([('{"team": "x", "v": {}}\n', 0.05), ('{"team": "y", "v": {}}\n', 0.4)])

        def wait(self, timeout=None):
            return 0

    _fake_run(monkeypatch, late, FakeProc)
    got, _ = late.run_teams({"root": "/x", "teams": ["x", "y"]}, ["x", "y"])
    assert "y" in got, got  # ⓣ6 FAIL(마감 뒤 줄을 쓴다)


# ⓣ7 발행 등급(선례 E1) — 확인 불가 팀 1개 이상 = 끝 줄 «PARTIAL N팀» · 전원 = «ALL-UNKNOWN» + ERROR 1 · 발행은 계속
def test_t7_publish_grade_partial_and_all_unknown(caplog):
    assert fh.state_grade([]) == "" and fh.state_grade([{"state": "진행"}, {"state": "대기"}]) == ""
    assert fh.state_grade([{"state": "진행"}, {"state": "확인 불가"}, {"state": "확인 불가"}]) == "PARTIAL 2팀"
    assert fh.state_grade([{"state": "확인 불가"}, {"state": "확인 불가"}]) == "ALL-UNKNOWN"
    assert ts.grade({"a": {"state": "확인 불가"}, "b": {"state": "쉼"}}) == "PARTIAL 1팀"  # 뉴스·시트 같은 함수(r6 고침 4)


# r5 변이 — 흐려 받기 → 끝에 한 번 받기 되돌림 → ⓣ1 FAIL(마감을 넘긴다) — run_teams 가 r7 부터 ft_team_state 에 산다
def test_t1_mutation_end_of_run_receive_is_caught(world, tmp_path, monkeypatch):
    end_once = _mutant("            pump_out.join(max(0.0, dl - time.monotonic()))  # 흘려 받기",
                       "            pump_out.join(None)  # 변이: 끝에 한 번 받기", "ft_team_state.py")
    _twenty_teams(world, monkeypatch)
    _slow_judge(tmp_path, monkeypatch, "byz-t10-master", 8)
    payload = _payload(world, set(fh._sessions()))
    _, wall = _timed(end_once.run_teams, payload, payload["teams"])
    assert wall > 7.5, wall  # ⓣ1 FAIL


# ── r7(DA⑥ r6 HOLD 3 · 부모 = 얇은 감독자 1개 · 판정 전체는 하위 · 반환 지점 1) ──────────────────


def _group_stub(tmp_path, name: str = "tmux-group"):
    """가짜 tmux — TERM 무시 + 손자(9초 뒤 표식) + «ls 4초 · list-panes 20초» · 자기 무리 리더(무리 번호를 파일에 남긴다)."""
    stub, pidf, mark = tmp_path / name, tmp_path / f"{name}.pid", tmp_path / f"{name}-grandchild-done"
    stub.write_text(f"#!/bin/sh\ntrap '' TERM\n(sleep 9; touch '{mark}') &\necho \"$$ $!\" > '{pidf}'\n"
                    f"case \"$1\" in\n  ls) sleep 4; echo byz-x-master#1 ;;\n  *) sleep 20 ;;\nesac\n", encoding="utf-8")
    stub.chmod(0o755)
    return str(stub), pidf, mark


def _gone(pgid: int) -> bool:
    """그 무리가 사라졌나 — os.killpg(pgid, 0) 이 ESRCH 면 True(EPERM = 아직 있다)."""
    try:
        os.killpg(pgid, 0)
    except ProcessLookupError:
        return True
    except PermissionError:
        return False
    return False


def _kill_quiet(pgid: int) -> None:
    """시험 뒷정리 — 무리째 KILL(이미 죽었거나 zombie 뿐이면 ESRCH·EPERM 을 삼킨다)."""
    try:
        os.killpg(pgid, 9)
    except (ProcessLookupError, PermissionError):
        return


# ⓤ1 DA r6 반례 1 — 하위의 tmux 무리가 TERM 무시 + 20초 손자 → 벽시계 ≤ 7.5초 · 반환 직후 그 무리 ESRCH(표식 0 · 1초 뒤에도 0)
def test_u1_reported_groups_dead_at_return(world, tmp_path, monkeypatch):
    stub, pidf, mark = _group_stub(tmp_path)
    monkeypatch.setenv("FT_TMUX", stub)  # ls 4초 + 손자가 파이프를 쥐고 20초 = 하위 판독이 마감을 넘긴다
    got, wall = _timed(ts.team_states, world.root, ts.AUTO, NOW_DT, ts.roster_files(world.root))
    assert wall <= 7.5, wall
    assert {v["state"] for v in got.values()} == {"확인 불가"}, got
    pgid = int(pidf.read_text(encoding="utf-8").split()[0])
    assert _gone(pgid), pgid  # 부모가 반환 «직전» 하위가 알린 무리까지 걷어냈다(자손 0)
    time.sleep(1.0)
    assert not mark.exists()  # 1초 뒤에도 표식 0 — 손자가 살아 있으면 9초에 찍었을 것이다


# 변이 — «killpg → 리더만» / «KILL 되풀이(생존 0 확인) 삭제» → 그 무리가 살아남는다(ⓤ1 FAIL)
def test_u1_mutations_are_caught(tmp_path):
    import subprocess

    stub, pidf, _mark = _group_stub(tmp_path, "tmux-mut")
    cases = (("        os.killpg(pgid, sig)\n", "        os.kill(pgid, sig)  # 변이: 무리가 아니라 리더만\n"),
             ("    end = time.monotonic() + wait_s\n    while time.monotonic() < end:\n",
              "    end = 0.0  # 변이: KILL 되풀이(생존 0 확인) 삭제\n    while time.monotonic() < end:\n"))
    for old, new in cases:
        mut = _mutant(old, new)
        proc = subprocess.Popen([stub, "ls"], start_new_session=True)  # noqa: S603 — 시험용 스텁
        try:
            time.sleep(0.4)
            pgid = int(pidf.read_text(encoding="utf-8").split()[0])
            mut._reap_group(proc, grace=0.0, wait_s=0.3)
            assert not _gone(pgid), (old, pgid)  # 변이면 무리가 살아 있다 = ⓤ1 FAIL
        finally:
            _kill_quiet(proc.pid)
            _kill_quiet(pgid)
        time.sleep(0.1)
    proc = subprocess.Popen([stub, "ls"], start_new_session=True)  # noqa: S603 — 기준: 제품 판은 무리를 걷어낸다
    try:
        time.sleep(0.4)
        pgid = int(pidf.read_text(encoding="utf-8").split()[0])
        ts._reap_group(proc, grace=0.0, wait_s=0.5)
        assert _gone(pgid) and _gone(proc.pid)
    finally:
        _kill_quiet(proc.pid)
        _kill_quiet(pgid)


# ⓤ2 DA r6 반례 2 — 파일 핸들 한도 32 · 남은 핸들 채움 → 부모 예외 전파 0 · 전 팀 «확인 불가(판정 시작 실패 24)» 또는 팀 줄의 «원천 오류» · ERROR ≥1
def _fill_handles() -> tuple[list, tuple]:
    """RLIMIT_NOFILE 32 로 내리고 남은 핸들을 채운다 — (연 파일들, 원래 한도)."""
    import resource

    soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
    fds: list = []
    resource.setrlimit(resource.RLIMIT_NOFILE, (min(soft, 32), hard))
    while len(fds) < 40:
        try:
            fds.append(open("/dev/null"))  # noqa: SIM115 — 일부러 채운다
        except OSError:
            break
    if fds:
        fds.pop().close()  # 한 칸은 남긴다(임시 파일이 설 자리)
    return fds, (soft, hard)


def _release_handles(fds: list, limits: tuple) -> None:
    import resource

    for f in fds:
        f.close()
    resource.setrlimit(resource.RLIMIT_NOFILE, limits)


def test_u2_parent_stage_failure_is_all_unknown(world, caplog):
    rosters = ts.roster_files(world.root)  # 핸들을 채우기 «전» 에 팀 이름을 안다(부모가 탐색하는 것이 아니다)
    fds, limits = _fill_handles()
    try:
        with caplog.at_level("ERROR"):
            got = ts.team_states(world.root, set(fh._sessions()), NOW_DT, rosters)
    finally:
        _release_handles(fds, limits)
    assert {v["state"] for v in got.values()} == {"확인 불가"}, got  # 예외 전파 0
    assert all("판정 시작 실패" in v["label"] or "원천 오류" in v["label"] for v in got.values()), got
    assert sum(r.levelname == "ERROR" for r in caplog.records) >= 1


# 변이 «입구 try 에 roster_files 되살림(부모 직접 탐색)» → EMFILE 이 그대로 전파(ⓤ2 FAIL)
def test_u2_mutation_parent_roster_scan_restored_is_caught(world, monkeypatch):
    back = _mutant("    fail, out = None, {}\n",
                   "    rosters = roster_files(root) if rosters is None else rosters  # 변이: 부모가 직접 명부 탐색\n    fail, out = None, {}\n")
    monkeypatch.setattr(back, "roster_files", lambda *_a, **_k: (_ for _ in ()).throw(OSError(24, "Too many open files")))
    with pytest.raises(OSError):  # 변이: 부모가 명부를 찾으면 그 실패(EMFILE)가 전체로 번진다
        back.team_states(world.root, set(fh._sessions()), NOW_DT)
    assert ts.team_states(world.root, ts.AUTO, NOW_DT)  # 제품 판은 탐색을 하위가 하고 «모름» 으로 발행한다


# ⓤ3 DA r6 반례 3 — 같은 고갈(모듈은 이미 읽힘) → 끝 줄 ALL-UNKNOWN 글자 1 + ERROR 1 · 변이 «조기 return 되살림» → FAIL
def test_u3_grade_line_once_on_start_failure(world, caplog):
    rosters = ts.roster_files(world.root)
    fds, limits = _fill_handles()
    try:
        with caplog.at_level("ERROR"):
            got = ts.team_states(world.root, set(fh._sessions()), NOW_DT, rosters)
    finally:
        _release_handles(fds, limits)
    assert ts.grade(got) == "ALL-UNKNOWN", got
    assert sum("ALL-UNKNOWN" in r.getMessage() for r in caplog.records if r.levelname == "ERROR") == 1


def test_u3_mutation_early_return_restored_is_caught(world, caplog):
    early = _mutant("    out = dict(sorted(out.items()))\n    grade_text = grade(out)\n",
                    "    if fail:  # 변이: 조기 return — grade() 를 안 지난다\n"
                    "        return {t: _verdict(\"확인 불가\", f\"확인 불가({fail})\") for t in teams}\n"
                    "    out = dict(sorted(out.items()))\n    grade_text = grade(out)\n")
    rosters = ts.roster_files(world.root)
    fds, limits = _fill_handles()
    try:
        with caplog.at_level("ERROR"):
            early.team_states(world.root, set(fh._sessions()), NOW_DT, rosters)
    finally:
        _release_handles(fds, limits)
    assert not any("ALL-UNKNOWN" in r.getMessage() for r in caplog.records)  # ⓤ3 FAIL


# ⓤ4 하위 첫 줄(팀 목록)을 못 받음(스텁 하위가 0줄) → rosters 인자 팀 전원 «확인 불가(판정 시작 실패 …)» + ALL-UNKNOWN · 명부 0개 = raise
def test_u4_child_without_first_line_is_start_failure(world, monkeypatch, caplog):
    import io

    class Empty:
        pid, returncode = 424244, 0
        stdout = io.StringIO("")

        def wait(self, timeout=None):
            return 0

    monkeypatch.setattr(ts, "_spawn", lambda _path: Empty())
    with caplog.at_level("ERROR"):
        got = ts.team_states(world.root, set(fh._sessions()), NOW_DT, ts.roster_files(world.root))
    assert {v["label"] for v in got.values()} == {"확인 불가(판정 시작 실패 0줄)"}, got
    assert ts.grade(got) == "ALL-UNKNOWN"
    assert sum("ALL-UNKNOWN" in r.getMessage() for r in caplog.records if r.levelname == "ERROR") == 1
    monkeypatch.undo()  # 실제 하위를 다시 띄운다(아래 명부 0개 갈래)
    noro = world.root.parent / "noroster"
    (noro / ".fable-team").mkdir(parents=True)
    with pytest.raises(RuntimeError):  # 명부 0개 = 발행 0(하위의 {"fatal": …} 줄을 부모가 raise) — 지금 계약 그대로
        ts.team_states(noro, ts.AUTO, NOW_DT)


# ⓤ5 부모 호출 금지 — team_states 실행 중 Popen 1회 · tmux·roster_files·import ft_team_turns 0 · 변이 «부모가 직접» → FAIL
def test_u5_parent_does_no_work(world, monkeypatch):
    import builtins

    calls = {"popen": 0, "import": 0, "roster": 0}
    real_popen, real_import, real_roster = ts.subprocess.Popen, builtins.__import__, ts.roster_files

    def popen(*a, **k):
        calls["popen"] += 1
        return real_popen(*a, **k)

    def imp(name, *a, **k):
        calls["import"] += "ft_team_turns" in name
        return real_import(name, *a, **k)

    def roster(*a, **k):
        calls["roster"] += 1
        return real_roster(*a, **k)

    monkeypatch.setattr(ts.subprocess, "Popen", popen)
    monkeypatch.setattr(builtins, "__import__", imp)
    monkeypatch.setattr(ts, "roster_files", roster)
    got = ts.team_states(world.root, ts.AUTO, NOW_DT)  # rosters 인자 없음 = 명부 탐색도 하위가
    assert calls == {"popen": 1, "import": 0, "roster": 0}, calls  # 부모가 여는 자원 = 하위 1개(임시 파일 1 · 무리 1)
    assert {v["state"] for v in got.values()} == {"확인 불가"} or got, got
    assert len(got) == 4, got  # 하위 첫 줄로 팀 집합을 받았다
    calls.update({"popen": 0, "import": 0, "roster": 0})
    hop = _mutant("    fail, out = None, {}\n", "    import ft_team_turns as _tt  # 변이: 부모가 직접 import\n    fail, out = None, {}\n")
    hop.team_states(world.root, ts.AUTO, NOW_DT)
    assert calls["import"] == 1  # 변이면 부모가 모듈을 읽는다 = ⓤ5 FAIL


# ── r6 회귀(behavior 그대로 · 판정 자리만 하위로 옴) ───────────────────────────────────────────────────

# r6 ⓤ2 — tmux ls·list-panes 각 4초 지연 → 벽시계 ≤ 7.5초(세션 목록도 판정 마감 안) /
#     ls 가 마감을 통째로 먹으면 전 팀 «확인 불가(tmux 목록 시간 초과)» + ERROR
def _slow_tmux(tmp_path, ls_s: float, panes_s: float, name: str = "tmux-slow") -> str:
    stub = tmp_path / name
    stub.write_text(f"#!/bin/sh\ncase \"$1\" in\n  ls) sleep {ls_s}; echo {name}-master#1 ;;\n"
                    f"  list-panes) sleep {panes_s}; printf '%s\\t%s\\n' {name}-master#1 /wt/{name}-master ;;\nesac\n", encoding="utf-8")
    stub.chmod(0o755)
    return str(stub)


def test_r6_u2_slow_tmux_stays_inside_deadline(world, tmp_path, monkeypatch):
    monkeypatch.setenv("FT_TMUX", _slow_tmux(tmp_path, 4, 4))  # ls 4초 + list-panes 4초 = 8초
    got, wall = _timed(ts.team_states, world.root, ts.AUTO, NOW_DT, ts.roster_files(world.root))
    assert wall <= 7.5, wall
    assert {v["state"] for v in got.values()} == {"확인 불가"}, got


def test_r6_u2_session_list_over_deadline_is_all_unknown(world, tmp_path, monkeypatch, caplog):
    monkeypatch.setenv("FT_TMUX", _slow_tmux(tmp_path, 8, 0, "tmux-hang"))
    with caplog.at_level("ERROR"):
        got, wall = _timed(ts.team_states, world.root, ts.AUTO, NOW_DT, ts.roster_files(world.root))
    assert wall <= 7.5, wall
    assert all("tmux 목록 시간 초과" in v["label"] for v in got.values()), got
    assert any("tmux 세션 목록 시간 초과" in r.getMessage() for r in caplog.records if r.levelname == "ERROR")


# r6 ⓤ3 — ls 스텁이 20초 자식을 낳고 자신은 8초 지연 → 반환 뒤 자손 0(무리째 정리 · 자손 살아 있으면 os.kill(pid,0) 이 통과한다)
def test_r6_u3_no_descendants_left_after_return(world, tmp_path, monkeypatch):
    stub, pidf = tmp_path / "tmux", tmp_path / "child.pid"
    stub.write_text(f"#!/bin/sh\nsleep 20 &\necho $! > '{pidf}'\nsleep 8\n", encoding="utf-8")
    stub.chmod(0o755)
    monkeypatch.setenv("FT_TMUX", str(stub))
    _, wall = _timed(ts.team_states, world.root, ts.AUTO, NOW_DT, ts.roster_files(world.root))
    assert wall <= 7.5, wall
    time.sleep(1.0)  # 반환 1초 뒤
    pid = int(pidf.read_text(encoding="utf-8").strip())
    with pytest.raises(ProcessLookupError):
        os.kill(pid, 0)


# r6 ⓤ4 — 시트 경로(`ft-board.py teams`)도 같은 등급 줄을 낸다: 현역 Claude 좌석 1 · 진행 카드 1 · 빈 jsonl → stderr 에 PARTIAL
def test_r6_u4_sheet_teams_path_emits_grade_line(tmp_path):
    import subprocess

    root = tmp_path / "broot"
    fable = root / ".fable-team"
    for d in (fable / "comm", fable / "state", root / "t" / "x" / "진행"):
        d.mkdir(parents=True, exist_ok=True)
    (root / "t" / "x" / "진행" / "c-x.md").write_text("# 인덱스: x 카드\n본문\n", encoding="utf-8")
    (fable / "state" / "verdicts.jsonl").write_text("", encoding="utf-8")
    (fable / "seats-x.json").write_text(json.dumps(
        {"_label": "x팀", "_master": "byz-x-master#1", "_cards": "t/x", "byz-x-master#1": {"role": "master"}}), encoding="utf-8")
    projects = tmp_path / "projects"
    projects.mkdir()
    tmux = tmp_path / "tmux.sh"
    tmux.write_text("#!/bin/sh\necho byz-x-master#1\necho 'byz-x-master#1\t/wt/byz-x-master'\n", encoding="utf-8")
    tmux.chmod(0o755)
    git = ["git", "-C", str(root)]
    subprocess.run([*git, "init", "-q"], check=True)
    env = {**os.environ, "FT_ROOT": str(root), "FT_BOARD_NOW": NOW, "FT_BOARD_TMUX": f"bash {tmux}",
           "FT_CLAUDE_PROJECTS": str(projects), "FT_SEAT_RESUME_DIR": str(tmp_path / "resume"), "FT_GH_OFFLINE": "1"}
    r = subprocess.run([sys.executable, str(BIN / "ft-board.py"), "teams"], capture_output=True, text=True, env=env, timeout=120)
    assert r.returncode == 0, r.stderr
    assert "확인 불가(jsonl 없음 1석)" in r.stdout, r.stdout
    assert "PARTIAL" in r.stderr or "ALL-UNKNOWN" in r.stderr, r.stderr  # r6 고침 4 — 판정 함수가 등급 줄을 낸다


# 변이 — 바깥 try 삭제 → ⓤ2 FAIL / 등급 줄 삭제 → ⓤ3 FAIL · (r6 의 «입구 마감 없애기» 변이는 ⓤ2 변이로 대체 — 세션 목록이 부모에서 하위로 갔다)
def test_r6_u_mutation_outer_try_removed_is_caught(world, monkeypatch):
    no_try = _mutant("    except Exception as e:  # noqa: BLE001 — 정의상 예외 0: 새도 같은 끝 줄로(«판정 시작 실패»)\n",
                     "    except ZeroDivisionError as e:  # 변이\n")
    monkeypatch.setattr(no_try, "_spawn", lambda _p: (_ for _ in ()).throw(KeyError("준비 실패")))  # OSError 가 아니면 run_teams 가 안 삼킨다
    with pytest.raises(KeyError):  # 변이: 바깥 try 가 없으면 전체로 번진다(ⓤ2 FAIL)
        no_try.team_states(world.root, ts.AUTO, NOW_DT, ts.roster_files(world.root))


def test_r6_u_mutation_grade_line_removed_is_caught(world, caplog):
    _snap(world).write_text(json.dumps({"teams": [{"key": "y", "master": ["broken"], "seats": {}}]}, ensure_ascii=False), encoding="utf-8")  # y = 확인 불가
    with caplog.at_level("WARNING"):
        ts.team_states(world.root, set(fh._sessions()), NOW_DT)
    assert any("PARTIAL" in r.getMessage() for r in caplog.records), [r.getMessage() for r in caplog.records]
    caplog.clear()
    no_grade = _mutant("    elif grade_text:\n        LOG.warning(\"팀 상태 %s — 확인 불가 팀이 있다(발행은 계속)\", grade_text)\n",
                       "    elif False:  # 변이: 등급 줄 없음\n        LOG.warning(\"x\")\n")
    with caplog.at_level("WARNING"):
        no_grade.team_states(world.root, set(fh._sessions()), NOW_DT)
    assert not any("PARTIAL" in r.getMessage() for r in caplog.records)  # ⓤ4 FAIL
