"""뉴스 HTML 모드(r478) ⓐ~ⓗ — 가짜 opencode(FT_OPENCODE · 인자 기록) + 가짜 Slack(--slack-base) · 실 opencode·실 Slack 0 · GIT_* env 0.
실행: python3 -m pytest tests/scripts/test_ft_news_html.py -q
"""
import importlib.util
import json
import os
import re
import subprocess
import sys
import threading
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import pytest

ROOT = Path(__file__).resolve().parents[3]
BIN = ROOT / "harness" / "bin"
KIT = ROOT / "harness" / "kit" / "slack-mirror"
sys.path[:0] = [str(BIN), str(KIT)]
os.environ["FT_HERMES_SCRIPTS"] = str(KIT)  # 설치본(~/.hermes/scripts) 아닌 키트판 magazine_slack(upload_file comment 인자)

import ft_news_html as fh  # noqa: E402
import ft_news_html_lint as lint  # noqa: E402
import ft_news_html_render as fr  # noqa: E402
import ft_news_publish as np  # noqa: E402
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

NOW = datetime(2026, 10, 19, 9, 15)
GOALS = [{"n": i, "goal": f"골 글 {i}", "team": f"t{i} (byz-t{i}-master)", "state": "지금"} for i in range(1, 7)]
CONTENT = {"summary": ["통역 고침 시험 중", "하네스 설치 끝"],
           "important": [{"title": "환각 고치기", "detail": "말끝 잡음", "who": "v65", "hot": True}, {"title": "합치기", "detail": "차례", "who": "room"}],
           "goals": [{"done": "끝난 것", "now": "하는 것", "left": "남은 것", "hot": i == 0} for i in range(6)],
           "team_notes": [{"team": "kk", "text": "닫힘"}, {"team": "chatbot", "text": "이름 바꾸기"}, {"team": "ops", "text": "메뉴 만드는 중"}],
           "resting": [{"team": "chatbot", "text": "LLM 이 잘못 넣은 쉬는 팀"}],  # r478c 반려 재현 — LLM 의 일함/쉼 판정은 버린다
           "refs": ["#113248", "a608fea5a0"]}
LIVE = [{"team": "kk", "live": 0, "working": 0, "unknown": 0}, {"team": "ops", "live": 2, "working": 1, "unknown": 1},
        {"team": "chatbot", "live": 6, "working": 2, "unknown": 0}]
DATA = {"goals": GOALS, "live": LIVE}
FAKE_OC = """#!/usr/bin/env python3
import json, os, stat, sys, time
log = os.environ["FAKE_OC_LOG"]
open(log, "a").write(json.dumps(sys.argv[1:]) + "\\n")
open(log + ".stdin", "a").write(str(stat.S_ISCHR(os.fstat(0).st_mode)) + "\\n")  # /dev/null = 문자 장치
if "--standalone" not in sys.argv: sys.exit(1)
if os.environ.get("FAKE_OC_FAIL_FIRST"):
    try:
        os.close(os.open(log + ".failed", os.O_CREAT | os.O_EXCL))  # 병렬 호출 중 «처음 하나» 만 실패(출력 0)
        sys.exit(1)
    except FileExistsError:
        pass
slow = os.environ.get("FAKE_OC_SLOW_MATCH")  # 있으면 이 글자가 든 갈래만 지연(부하 모사)
if not slow or slow in sys.argv[-1].split("출력 스키마:")[-1].splitlines()[0]:
    time.sleep(float(os.environ.get("FAKE_OC_SLEEP", "0")))
print(json.dumps({"type": "step_start"}))
print(json.dumps({"type": "text", "part": {"text": open(os.environ["FAKE_OC_REPLY"]).read()}}))
sys.exit(int(os.environ.get("FAKE_OC_RC", "0")))
"""


@pytest.fixture
def oc(tmp_path, monkeypatch):
    """가짜 opencode — 답 글 파일·인자 기록 파일."""
    exe, reply, log = tmp_path / "opencode", tmp_path / "reply.txt", tmp_path / "oc.log"
    exe.write_text(FAKE_OC, encoding="utf-8")
    exe.chmod(0o755)
    reply.write_text("```json\n" + json.dumps(CONTENT, ensure_ascii=False) + "\n```", encoding="utf-8")
    # r563: 모델 호출 기본 = HTTP 직접 — 이 시험은 가짜 opencode(CLI) 경로를 본다(되돌림 손잡이와 같은 env)
    for k, v in {"FT_OPENCODE": str(exe), "FAKE_OC_REPLY": str(reply), "FAKE_OC_LOG": str(log), "FT_NEWS_VIA": "opencode",
                 "FT_NEWS_STARTUP_LOG": str(tmp_path / "startup.tsv")}.items():
        monkeypatch.setenv(k, v)
    for k in ("FT_NEWS_EFFORT", "FT_NEWS_MODEL", "FT_NEWS_DEPTH", "FT_NEWS_HEAD", "FT_NEWS_FIXED_S"):
        monkeypatch.delenv(k, raising=False)
    return reply, log


def calls(log: Path) -> list[list[str]]:
    return [json.loads(ln) for ln in log.read_text(encoding="utf-8").splitlines()] if log.exists() else []


# ── ⓐ build: 입력 묶음 ─────────────────────────────────────────────

def _git(repo: Path, *a: str) -> str:
    return subprocess.run(["git", "-C", str(repo), *a], check=True, capture_output=True, text=True).stdout.strip()


def test_a_build_bundles_ledger_teams_urgent_commits_and_scrubs_secrets(tmp_path, monkeypatch):
    root, repo = tmp_path / "root", tmp_path / "repo"
    (repo / "design" / "planner").mkdir(parents=True)
    _git(repo.parent, "init", "-q", str(repo))
    _git(repo, "config", "user.email", "t@t")
    _git(repo, "config", "user.name", "t")
    rel = "design/planner/PLAN-oppa-ledger.md"
    (repo / rel).write_text("**지금 전체 상태**: 정지 레디\n## 2. 오빠 할 일\n- 승인 1줄 xoxb-1234567-secretvalue\n## 5. 완료 보관\n- 옛 줄\n", encoding="utf-8")
    _git(repo, "add", ".")
    _git(repo, "commit", "-qm", "[docs] 원장")
    snap = root / ".fable-team" / "state" / "board" / "2026-10-19"
    snap.mkdir(parents=True)
    (snap / "091000-ab12.json").write_text(json.dumps({"teams": [{"label": "v65", "seats": {"byz-v65-master-claude#1": {"working": True}}, "stalled": [], "progress": {}, "queue": []}]}), encoding="utf-8")
    box = root / ".fable-team" / "comm"
    box.mkdir(parents=True)
    rows = [{"ts": "2026-10-19T09:00:00", "body": "[긴급] 뉴스 멈춤\n본문"}, {"ts": "2026-10-17T09:00:00", "body": "[긴급] 옛 일"}, {"ts": "2026-10-19T09:01:00", "body": "[발주] 보통"}]
    (box / "mailbox.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")
    monkeypatch.setattr(fh, "goals", lambda: GOALS)
    monkeypatch.setattr(fh, "live_teams", lambda r: LIVE)  # 실측 함수는 test_r478c_live_teams_… 가 따로
    monkeypatch.setenv("FT_NEWS_MAIN_REF", "HEAD")
    data = fh.build(root, repo, rel, "", _git(repo, "rev-parse", "HEAD"), NOW)
    assert [g["n"] for g in data["goals"]] == [1, 2, 3, 4, 5, 6]
    titles = [p["title"] for p in data["ledger"]]
    assert "지금" in titles and any("오빠 할 일" in t for t in titles) and not any("완료 보관" in t for t in titles)
    assert data["urgent"] == ["[긴급] 뉴스 멈춤"]  # 24시간 밖·[긴급] 아닌 쪽지 빠짐
    assert data["teams"][1].startswith("• v65 — 일함 1")
    assert data["commits"][0].endswith("[docs] 원장")
    assert "xoxb-" not in json.dumps(data, ensure_ascii=False) and "[가림]" in json.dumps(data, ensure_ascii=False)


def test_a_teams_without_snapshot_is_marked_source_missing(tmp_path):
    assert fh.teams(tmp_path).startswith("원천 없음")


# ── ⓑ run: opencode 인자 · 틀 주입 ──────────────────────────────────

def _style(html: str) -> str:
    return re.search(r"<style>.*?</style>", html, re.S)[0]


def test_b_run_calls_opencode_standalone_json_with_variant_and_fills_template(tmp_path, oc, monkeypatch):
    _, log = oc
    monkeypatch.setenv("FT_NEWS_EFFORT", "max")
    html_p, sum_p = fh.run_files(DATA, tmp_path / "out", NOW)
    args = calls(log)[0]
    assert args[:6] == ["run", "--standalone", "--model", "opencode/deepseek-v4.1-flash-free#max", "--format", "json"]
    assert html_p.name == "NEWS-20261019-0915.html" and sum_p.name == "NEWS-20261019-0915.summary.txt"
    page = html_p.read_text(encoding="utf-8")
    tpl = next(d for d in fr.TEMPLATES if d.is_dir()) / "news-team-map.html"
    assert _style(page) == _style(tpl.read_text(encoding="utf-8"))
    assert "{{" not in page and page.count('<section class="goal">') == 6 and "골 1 · t1" in page
    assert 'class="step s-hot"' in page and "var(--hot-bg)" in page  # 급한 불 골
    # r588: 요약 첫 줄 = 코드가 만든 팀 상태 줄(모델 줄은 그 뒤) — DATA 의 LIVE 그대로
    assert sum_p.read_text(encoding="utf-8").splitlines() == ["일하는 팀 2개: chatbot, ops. 쉬는 팀 1개: kk", *CONTENT["summary"]]
    assert lint.problems(page, sum_p.read_text(encoding="utf-8")) == []


def test_b_base_variant_has_no_suffix_and_depth_goes_into_prompt(tmp_path, oc, monkeypatch):
    _, log = oc
    monkeypatch.setenv("FT_NEWS_EFFORT", "base")
    monkeypatch.setenv("FT_NEWS_DEPTH", "깊이: 팀마다 두 번 따져 본다")
    fh.run_files(DATA, tmp_path, NOW)
    args = calls(log)[0]
    assert args[3] == "opencode/deepseek-v4.1-flash-free" and "깊이: 팀마다 두 번 따져 본다" in args[-1]


# ── ⓒ 실패 = rc1 · 발행 0 · 재시도는 첫 출력 전만 ─────────────────────

@pytest.mark.parametrize("reply", ["그냥 글", json.dumps({"summary": ["a"]}), json.dumps({**CONTENT, "goals": CONTENT["goals"][:5]})])
def test_c_bad_reply_fails_without_files(tmp_path, oc, reply):
    oc[0].write_text(reply, encoding="utf-8")
    with pytest.raises(fr.NewsHtmlError):
        fh.run_files(DATA, tmp_path / "out", NOW)
    assert not (tmp_path / "out").exists()


def test_c_cli_run_failure_is_rc1(tmp_path, oc):
    oc[0].write_text("아님", encoding="utf-8")
    (tmp_path / "in.json").write_text(json.dumps(DATA), encoding="utf-8")
    assert fh.main(["run", "--input", str(tmp_path / "in.json"), "--out", str(tmp_path / "o")]) == 1


def test_c_retry_once_only_before_first_output(tmp_path, oc, monkeypatch):
    _, log = oc
    monkeypatch.setenv("FAKE_OC_FAIL_FIRST", "1")
    fh.run_files(DATA, tmp_path, NOW)
    assert len(calls(log)) == 5  # 갈래 4 + 출력 0 으로 실패한 갈래 재시도 1
    log.unlink()
    monkeypatch.delenv("FAKE_OC_FAIL_FIRST")
    monkeypatch.setenv("FAKE_OC_RC", "1")  # 출력 뒤 실패 = 재시도 0
    with pytest.raises(fr.NewsHtmlError):
        fh.run_files(DATA, tmp_path, NOW)
    assert len(calls(log)) == 4


# ── r478b·r478e: 갈래 4개 병렬 · 갈래별 입력만 · 상한 = 크기 비례 · stdin 차단 ──

def _prompts(log: Path) -> dict[str, str]:
    return {next(p for p in fr.PARTS if f'"{fr.PARTS[p][0][0]}":' in c[-1].split("출력 스키마:")[1].splitlines()[0]): c[-1] for c in calls(log)}


def test_split_parts_get_only_their_inputs_and_stdin_is_devnull(tmp_path, oc):
    _, log = oc
    data = {"now": "x", "goals": GOALS, "ledger": [{"title": "원장절", "text": "원장글"}], "urgent": ["긴급머리"], "teams": ["팀줄"], "live": LIVE, "commits": ["abc 커밋글"]}
    fh.run_files(data, tmp_path, NOW)
    prompts = _prompts(log)
    assert set(prompts) == {"summary", "important", "goals", "teams"}
    assert "팀줄" in prompts["teams"] and "원장글" not in prompts["teams"]
    assert "원장글" in prompts["goals"] and "팀줄" not in prompts["goals"] and "커밋글" not in prompts["goals"]
    assert all(x in prompts["summary"] for x in ("원장글", "긴급머리", "커밋글")) and "팀줄" not in prompts["summary"]
    assert all(x in prompts["important"] for x in ("원장글", "긴급머리")) and "커밋글" not in prompts["important"]
    assert '"important":' not in prompts["summary"].split("출력 스키마:")[1].splitlines()[0]  # 요약 갈래는 중요한 일을 안 만든다
    assert Path(str(log) + ".stdin").read_text().split() == ["True"] * 4


def test_cap_is_size_scaled_and_never_above_70():
    small = fr.build_prompt({"teams": ["팀"]}, "teams")
    assert fr.cap_s(small, "teams") == 3.5 + 7 * 4  # 예상 출력 1200자 / 300 = 4
    assert fr.cap_s(small, "goals") == 3.5 + 7 * 6
    assert fr.cap_s("가" * 200000, "summary") == 70  # 큰 입력 = 70초 천장


def test_r478e_one_slow_part_over_cap_fails_whole_map_publish_zero(tmp_path, oc, monkeypatch):
    _, log = oc
    monkeypatch.setattr(fr, "DEADLINE_S", 3)  # 모든 갈래 상한 = min(크기 비례, 3초)
    monkeypatch.setenv("FAKE_OC_SLEEP", "6")
    monkeypatch.setenv("FAKE_OC_SLOW_MATCH", '"important":')  # 부하 모사 — 중요한 일 갈래만 느리다
    with pytest.raises(fr.NewsHtmlError, match="important 상한"):
        fh.run_files(DATA, tmp_path / "o", NOW)
    assert not (tmp_path / "o").exists()  # 나머지 3갈래는 끝났지만 지도·발행 0
    assert sum('"important":' in c[-1].split("출력 스키마:")[1].splitlines()[0] for c in calls(log)) == 1  # 총 마감 3초 = 재시도 시간 없음


def test_r478e_timeout_is_first_output_failure_retried_once_within_deadline(tmp_path, oc, monkeypatch):
    _, log = oc
    monkeypatch.setattr(fr, "cap_s", lambda prompt, part, fixed: 2)  # 시도당 2초 · 총 마감 70초
    monkeypatch.setenv("FAKE_OC_SLEEP", "4")
    monkeypatch.setenv("FAKE_OC_SLOW_MATCH", '"important":')
    with pytest.raises(fr.NewsHtmlError, match="important 상한 2s 초과"):
        fh.run_files(DATA, tmp_path / "o", NOW)
    assert sum('"important":' in c[-1].split("출력 스키마:")[1].splitlines()[0] for c in calls(log)) == 2  # 초과 = 첫 출력 전 실패 → 재시도 1


# ── r478c: 일하는/쉬는 팀 = 라이브 좌석 실측(코드) · 일하는 팀이 위 ─────────

def test_r478c_working_team_from_live_seats_is_above_resting_and_never_in_resting(tmp_path, oc):
    html_p, _ = fh.run_files(DATA, tmp_path, NOW)
    lines = html_p.read_text(encoding="utf-8").splitlines()
    at = lambda s: next(i for i, ln in enumerate(lines) if s in ln)  # noqa: E731
    work_h, goal_h, rest_h = at("<h2>일하는 팀</h2>"), at("<h2>골 6개</h2>"), at("<h2>쉬는 팀</h2>")
    chatbot, ops, kk = at('<p class="say">chatbot</p>'), at('<p class="say">ops</p>'), at("<strong>kk</strong>")
    # r478d: 일하는 팀 = 골 카드 위 그림 카드(좌석 많은 순 chatbot 2 > ops 1) · 쉬는 팀은 맨 아래 목록
    assert work_h < chatbot < ops < goal_h < rest_h < kk
    assert "LLM 이 잘못 넣은" not in "\n".join(lines)  # LLM 의 일함/쉼 판정은 쓰지 않는다
    assert "일하는 좌석 2/6" in lines[chatbot - 1] and "이름 바꾸기" in lines[chatbot + 2] and "확인 불가 1" in lines[ops - 1]
    assert "라이브 좌석 0 · 일하는 좌석 0" in lines[kk]
    assert "\n".join(lines).count('<section class="goal work">') == 2 and '<section class="goal work">' in lines[chatbot - 4]


# ── r478d: 요약·중요한 일 = 코드 판정 따르기 · 자율 실측 ───────────────────

FALSE_LINE = "모든 팀은 작업을 멈추고 대기 중이며 사장님의 재개 지시와 합치기 승인 한 줄을 기다립니다"


def test_r478d_lint_rejects_all_stopped_and_approval_wait_against_code_facts(tmp_path, oc):
    html_p, sum_p = fh.run_files(DATA, tmp_path, NOW)
    page, summary = html_p.read_text(encoding="utf-8"), sum_p.read_text(encoding="utf-8")
    assert "자율 모름" in page and lint.problems(page, summary) == []
    bad = lint.problems(page, "가\n" + FALSE_LINE)
    assert any("일하는 팀 2개인데" in p for p in bad) and any("자율 모름 인데" in p for p in bad)
    assert any("일하는 팀 2개인데" in p for p in lint.problems(page, "가\n전 팀이 대기 중입니다"))
    assert lint.problems(page, "가\n전팀 지침과 폴더 기준 재기동은 다음 차례 대기") == []  # 골 제목 «전팀 지침…» 은 오탐 0
    off = page.replace("자율 모름", "자율 OFF")
    assert not any("자율" in p for p in lint.problems(off, "가\n합치기 승인을 기다립니다"))  # OFF 면 승인 대기 문장은 사실
    assert any("자율 ON 인데" in p for p in lint.problems(page.replace("자율 모름", "자율 ON"), "가\n합치기 승인을 기다립니다"))
    resting_only = re.sub(r'  <section class="goal work">.*?</section>\n?', "", page, flags=re.S)
    assert not any("일하는 팀" in p for p in lint.problems(resting_only, "가\n모든 팀이 쉬는 중"))  # 일하는 팀 0 이면 사실


def test_r478d_prompt_carries_code_facts_and_autonomy_in_footer(tmp_path, oc, monkeypatch):
    _, log = oc
    data = {**DATA, "facts": fh.facts(LIVE, "ON")}
    assert data["facts"] == {"일하는 팀": ["chatbot", "ops"], "확인 불가": [], "쉬는 팀": ["kk"], "자율": "ON"}
    html_p, _ = fh.run_files(data, tmp_path, NOW)
    top = next(c[-1] for c in calls(log) if '"summary":' in c[-1].split("출력 스키마:")[1].splitlines()[0])
    assert '"일하는 팀": [' in top and '"chatbot"' in top and '"자율": "ON"' in top and "facts 가 이긴다" in top
    assert "자율 ON" in html_p.read_text(encoding="utf-8")
    monkeypatch.setattr(fh, "HERE", tmp_path)  # ft-autonomy.sh 없음 = 모름
    assert fh.autonomy(tmp_path) == "모름"


def test_r478c_no_live_input_fails_without_publish(tmp_path, oc):
    with pytest.raises(fr.NewsHtmlError, match="live"):
        fh.run_files({"goals": GOALS}, tmp_path / "o", NOW)
    assert not (tmp_path / "o").exists()


def test_r478c_live_teams_counts_tmux_seats_by_jsonl_turn(tmp_path, monkeypatch):
    fable = tmp_path / ".fable-team"
    fable.mkdir()
    for name in ("seats-chatbot.json", "seats-kk.json", "seats.json"):
        (fable / name).write_text("{}", encoding="utf-8")
    sessions = ["byz-chatbot-master-claude#7", "byz-chatbot-nano-c-k1#0", "byz-chatbot-nano-c-k6#0", "byz-concierge-master-claude#6",
                "byz-v65-master-claude#212", "ft-v65-temp-m5#0", "byz-planner-desk-claude#24"]
    turns = {"byz-chatbot-nano-c-k1#0": "WORKING", "byz-chatbot-nano-c-k6#0": "WORKING", "ft-v65-temp-m5#0": "?"}
    monkeypatch.setattr(fh, "_sessions", lambda: sessions)
    monkeypatch.setattr(fh, "_turns", lambda ss: {s: (turns.get(s, "IDLE"), "jsonl 없음" if turns.get(s) == "?" else "") for s in ss})
    got = {t["team"]: t for t in fh.live_teams(tmp_path)}
    assert set(got) == {"chatbot", "kk", "v65"}  # 명부 있는 팀만 · seats.json = v65
    assert (got["chatbot"]["live"], got["chatbot"]["working"]) == (3, 2)  # 옛 이름 concierge 좌석은 chatbot 에 안 섞인다
    assert (got["v65"]["live"], got["v65"]["working"], got["v65"]["unknown"]) == (2, 0, 1)
    assert (got["kk"]["live"], got["kk"]["working"]) == (0, 0)
    with pytest.raises(RuntimeError, match="명부 0개"):
        fh.live_teams(tmp_path / "없음")


# ── r490: «확인 불가»(판정 못 함) ≠ «쉬는 팀» · r504: 판정 = ft_seat_turn.turns 한 번(좌석별 하위 프로세스·재시도·풀 0 — test_seat_turn_batch) ─────────

R490_TURNS = {"byz-a-1": ("WORKING", ""), "byz-a-2": ("WORKING", ""), "byz-a-3": ("?", "읽기 실패")}


@pytest.fixture
def seat_root(tmp_path, monkeypatch):
    """임시 루트(명부 a·b·v65) + 가짜 tmux ls(a 3 · b 2 · v65 1) + 가짜 판정(_turns · R490_TURNS 밖 = IDLE)."""
    fable = tmp_path / ".fable-team"
    fable.mkdir()
    for name in ("seats-a.json", "seats-b.json", "seats.json"):
        (fable / name).write_text("{}", encoding="utf-8")
    monkeypatch.setattr(fh, "_sessions", lambda: ["byz-a-1", "byz-a-2", "byz-a-3", "byz-b-1", "byz-b-2", "byz-v65-1"])
    monkeypatch.setattr(fh, "_turns", lambda ss: {s: R490_TURNS.get(s, ("IDLE", "")) for s in ss})
    return tmp_path


def test_r490_a_failed_seat_is_unknown_not_resting(seat_root):
    got = {t["team"]: t for t in fh.live_teams(seat_root)}
    assert (got["a"]["live"], got["a"]["working"], got["a"]["unknown"], got["a"]["unknown_reason"]) == (3, 2, 1, "읽기 실패 1석")
    assert (got["b"]["working"], got["b"]["unknown"], got["v65"]["unknown"]) == (0, 0, 0)
    assert fh.facts(list(got.values()), "모름") == {"일하는 팀": ["a"], "확인 불가": [], "쉬는 팀": ["b", "v65"], "자율": "모름"}


def test_r490_b_all_unknown_team_goes_to_unknown_block_with_reason_never_resting(seat_root, oc, monkeypatch, tmp_path):
    monkeypatch.setitem(R490_TURNS, "byz-a-1", ("?", "jsonl 없음"))
    monkeypatch.setitem(R490_TURNS, "byz-a-2", ("?", "jsonl 없음"))
    live = fh.live_teams(seat_root)
    a = next(t for t in live if t["team"] == "a")
    assert (a["working"], a["unknown"], a["unknown_reason"]) == (0, 3, "jsonl 없음 2석 · 읽기 실패 1석")
    assert fh.facts(live, "모름")["확인 불가"] == ["a"] and "a" not in fh.facts(live, "모름")["쉬는 팀"]
    page = fh.run_files({**DATA, "live": live}, tmp_path / "out", NOW)[0].read_text(encoding="utf-8")
    unk = page.split("<h2>확인 불가</h2>")[1].split("<h2>")[0]
    rest = page.split("<h2>쉬는 팀</h2>")[1]
    assert "<strong>a</strong>" in unk and "jsonl 없음 2석 · 읽기 실패 1석" in unk and "<strong>a</strong>" not in rest
    assert page.index("<h2>일하는 팀</h2>") < page.index("<h2>확인 불가</h2>") < page.index("<h2>골 6개</h2>")
    assert "c-unk" in page and "{{" not in page


@pytest.fixture
def unknown_page(tmp_path, oc):
    live = [{"team": "a", "live": 3, "working": 0, "unknown": 2, "unknown_reason": "turn 시간 초과 2석"},
            {"team": "b", "live": 2, "working": 0, "unknown": 0, "unknown_reason": ""}]
    html_p, _ = fh.run_files({**DATA, "live": live}, tmp_path / "u", NOW)
    return html_p.read_text(encoding="utf-8")


def test_r490_c_lint_rejects_resting_claim_on_unknown_team(unknown_page):
    bad = lint.problems(unknown_page, "가\na 팀은 쉬는 중")
    assert [p for p in bad if "확인 불가 팀" in p] == ["확인 불가 팀 a 에 쉼 단정 «a 팀은 쉬는 중»"]
    assert lint.problems(unknown_page, "가\na 팀 상태 확인 불가") == []
    assert lint.problems(unknown_page, "가\nb 팀은 쉬는 중") == []  # 쉬는 팀(확인 불가 0)은 사실
    assert lint.problems(unknown_page, "가\nab 팀은 쉬는 중") == []  # 이름 경계 — a 가 다른 이름 안에 든 것은 아님


# ── r498: 쉼 글자 «뒤» 같은 절의 부정 꼬리 = 단정 아님 · 긍정 단정은 그대로 REJECT ─────────
R498_OK = ["lecture·planner·room은 상태를 확인할 수 없어서 쉰다거나 멈췄다고 단정하지 않습니다",  # ⓐ 라이브 1.1.53 로그 원문
           "lecture 는 쉬지 않았을 수 있습니다", "lecture 가 멈춘 것은 아닙니다"]  # ⓑ
R498_BAD = ["lecture 는 쉬는 중입니다", "lecture 는 확인이 안 돼 멈춘 상태입니다",  # ⓒ 부정이 쉼 글자 «앞» 다른 말에 붙음
            "lecture 는 대기 중이며 확인되지 않습니다",
            "lecture 는 쉬고 있고, 원인은 단정하지 않습니다"]  # ⓓ 다른 절 부정


@pytest.fixture
def lecture_page(unknown_page):
    return unknown_page.replace('<div class="team unk"><strong>a</strong>', '<div class="team unk"><strong>lecture</strong>')


@pytest.mark.parametrize("line", R498_OK)
def test_r498_ab_negated_tail_after_rest_word_is_not_assertion(lecture_page, line):
    assert lint.problems(lecture_page, "가\n" + line) == []


@pytest.mark.parametrize("line", R498_BAD)
def test_r498_cd_positive_rest_assertion_still_rejected(lecture_page, line):
    bad = [p for p in lint.problems(lecture_page, "가\n" + line) if "확인 불가 팀" in p]
    assert bad == [f"확인 불가 팀 lecture 에 쉼 단정 «{line}»"]


def test_c_total_deadline_kills_and_fails(tmp_path, oc, monkeypatch):
    monkeypatch.setattr(fr, "DEADLINE_S", 2)
    monkeypatch.setenv("FAKE_OC_SLEEP", "5")
    with pytest.raises(fr.NewsHtmlError, match="총 마감"):
        fh.run_files(DATA, tmp_path, NOW)
    assert not list(tmp_path.glob("*.html"))


# ── ⓓ 린트 ────────────────────────────────────────────────────────

@pytest.fixture
def page(tmp_path, oc):
    html_p, sum_p = fh.run_files(DATA, tmp_path / "p", NOW)
    return html_p.read_text(encoding="utf-8"), sum_p.read_text(encoding="utf-8")


def test_d_lint_rules(page):
    html, summary = page
    assert lint.problems(html, summary) == []
    li = re.search(r"      <li.*?</li>", html)[0]
    many = html.replace(li, li * 8)
    assert any("중요한 일 9개" in p for p in lint.problems(many, summary))
    one_goal = re.search(r'  <section class="goal">.*?  </section>\n', html, re.S)[0]
    assert any("골 5행" in p for p in lint.problems(html.replace(one_goal, "", 1), summary))
    assert any("각주 밖 번호" in p for p in lint.problems(html.replace("끝난 것", "끝난 것 #1943", 1), summary))
    assert lint.problems(html.replace("근거:", "근거: 판정 2354 · 1a2b3c4d5e ·", 1), summary) == []  # 각주 안 번호는 허용
    assert any("요약 4줄" in p for p in lint.problems(html, summary + "넷째 줄\n"))
    assert any("요약 1줄" in p for p in lint.problems(html, "가" * 250))  # 750B > 600B
    assert any("시크릿" in p for p in lint.problems(html.replace("끝난 것", "xoxb-1234567-zzzz", 1), summary))
    assert any("절 6" in p for p in lint.problems(html.replace("<h2>쉬는 팀</h2>", ""), summary))
    assert any("절 6" in p for p in lint.problems(html.replace("<h2>확인 불가</h2>", ""), summary))


def test_d_lint_cli_rc3_and_publish_zero(tmp_path, page, monkeypatch):
    html, summary = page
    (tmp_path / "x.html").write_text(html.replace("끝난 것", "끝난 것 #1943", 1), encoding="utf-8")
    (tmp_path / "x.txt").write_text(summary, encoding="utf-8")
    assert lint.main([str(tmp_path / "x.html"), str(tmp_path / "x.txt")]) == 3
    monkeypatch.setattr(np, "publish_html", lambda *a: pytest.fail("린트 위반인데 게시"))
    assert fh.publish_files(tmp_path / "x.html", tmp_path / "x.txt", NOW) == (3, None)


# ── ⓔ 게시: 한 줄 + 요약 2줄 + HTML 첨부(채널 최상위 1글) · 미첨부 재시도 · 변화 0 반복 ──

class FakeSlack:
    """chat.postMessage · files.getUploadURLExternal → 업로드 URL(바이트) → files.completeUploadExternal · conversations.history 대역."""

    def __init__(self) -> None:
        self.msgs: list[dict] = []
        self.uploads: list[bytes] = []
        self.fail_upload = False
        outer = self

        class H(BaseHTTPRequestHandler):
            def log_message(self, *a: object) -> None:
                pass

            def _reply(self, out: dict, code: int = 200) -> None:
                raw = json.dumps(out).encode()
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

            def _add(self, text: str, thread_ts: str = "", files: list | None = None) -> str:
                ts = f"{1_900_000_000 + len(outer.msgs)}.000000"
                outer.msgs.append({"ts": ts, "text": text, "bot_id": "B1", "thread_ts": thread_ts, **({"files": files} if files else {})})
                return ts

            def do_POST(self) -> None:
                raw = self.rfile.read(int(self.headers["Content-Length"]))
                if self.path.startswith("/upload/"):
                    if outer.fail_upload:
                        return self._reply({}, 500)
                    outer.uploads.append(raw)
                    return self._reply({})
                body = json.loads(raw)
                self._reply({"ok": True, "ts": self._add(body["text"], body.get("thread_ts", ""))})

            def do_GET(self) -> None:
                u = urlparse(self.path)
                q = {k: v[0] for k, v in parse_qs(u.query).items()}
                if u.path.endswith("files.getUploadURLExternal"):
                    return self._reply({"ok": True, "upload_url": f"{outer.base}/upload/F{len(outer.uploads)}", "file_id": f"F{len(outer.uploads)}"})
                if u.path.endswith("files.completeUploadExternal"):
                    self._add(q.get("initial_comment", ""), q.get("thread_ts", ""), json.loads(q["files"]))
                    return self._reply({"ok": True, "files": json.loads(q["files"])})
                if u.path.endswith("conversations.history"):
                    return self._reply({"ok": True, "messages": [m for m in reversed(outer.msgs) if m["thread_ts"] in ("", m["ts"])]})
                self._reply({"ok": False, "error": "unknown"})

        self.srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.srv.server_port}"


@pytest.fixture
def slack(tmp_path, monkeypatch):
    spec = importlib.util.spec_from_file_location("magazine_slack", KIT / "magazine_slack.py")
    kit_mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(kit_mod)
    monkeypatch.setitem(sys.modules, "magazine_slack", kit_mod)  # 앞 시험이 올린 설치본 캐시 대신 키트판(upload_file comment 인자)
    s = FakeSlack()
    (tmp_path / "tok").write_text("YOONHWAN_BOT_TOKEN=xoxb-fake\n", encoding="utf-8")
    (tmp_path / "threads.json").write_text("{}", encoding="utf-8")
    (tmp_path / ".fable-team").mkdir(exist_ok=True)
    (tmp_path / "news").mkdir()
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    monkeypatch.setenv("FT_NEWS_DIR", str(tmp_path / "news"))
    monkeypatch.setenv("FT_THREAD_POST", str(KIT / "byz_thread_post.py"))
    monkeypatch.setenv("FT_NEWS_POST_ARGS", f"--slack-base {s.base} --token-file {tmp_path / 'tok'} --channel C1 --ledger {tmp_path / 'threads.json'}")
    monkeypatch.setenv("FT_NEWS_WORKSPACE_URL", "https://x.slack.com")
    yield s
    s.srv.shutdown()


def test_e_publish_one_root_post_with_html_and_rerun_adopts(tmp_path, oc, slack):
    html_p, sum_p = fh.run_files(DATA, tmp_path / "out", NOW)
    rc, got = fh.publish_files(html_p, sum_p, NOW)
    assert rc == 0 and len(slack.msgs) == 1 and slack.uploads == [html_p.read_bytes()]
    m = slack.msgs[0]
    assert m["thread_ts"] == "" and m["files"][0]["title"] == html_p.name
    assert m["text"].splitlines() == ["[뉴스 09:15] 팀 지도 — 일하는 팀 2개: chatbot, ops. 쉬는 팀 1개: kk", "통역 고침 시험 중", "하네스 설치 끝"]
    assert got["ts"] == m["ts"] and got["permalink"].startswith("https://x.slack.com/archives/C1/p")
    assert fh.publish_files(html_p, sum_p, NOW)[0] == 0 and len(slack.msgs) == 1 and len(slack.uploads) == 1  # 같은 글 채택 · 다시 안 올림


def test_e_attach_failure_posts_text_rc3_then_next_tick_attaches(tmp_path, oc, slack, capsys):
    html_p, sum_p = fh.run_files(DATA, tmp_path / "out", NOW)
    slack.fail_upload = True
    rc, got = fh.publish_files(html_p, sum_p, NOW)
    assert rc == 3 and got["ts"] and slack.msgs[0]["text"].endswith("(지도 HTML 미첨부 — 다음 틱 재시도)") and "files" not in slack.msgs[0]
    assert "미첨부" in capsys.readouterr().out
    pend = tmp_path / ".fable-team" / "state" / "news-publish" / "pending-attach.json"
    assert pend.is_file()
    np.retry_attach(NOW)  # 아직 실패 — 기록 유지
    assert pend.is_file()
    slack.fail_upload = False
    np.retry_attach(NOW)
    assert not pend.exists() and slack.msgs[-1]["thread_ts"] == got["ts"] and slack.msgs[-1]["files"]


def _tick_env(tmp_path, monkeypatch, made: list):
    monkeypatch.setattr(fh, "build", lambda *a: DATA)
    real = fh.run_files
    monkeypatch.setattr(fh, "run_files", lambda d, out, now: made.append(now) or real(d, out, now))
    return tmp_path / "state"


def test_e_tick_map_then_repeat_line_every_30_min(tmp_path, oc, slack, monkeypatch):
    made: list = []
    state = _tick_env(tmp_path, monkeypatch, made)
    monkeypatch.setattr(fh, "_human_key", lambda *a: "k" * 40)  # r907 r5: 키 모름(git 리포 아님) = 항상 «바뀜» — 이 시험은 «같은 판» 전제라 키를 고정
    args = (tmp_path, state, tmp_path, "x.md", tmp_path / "news")
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-19 09:15")
    assert fh.tick(*args, "a", "b")[0] == 0 and (state / "last.sha").read_text().strip() == "b" and len(made) == 1
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-19 09:40")
    assert fh.tick(*args, "b", "b") == (0, "원장 커밋 0") and len(slack.msgs) == 1  # 30분 안 = 0
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-19 09:46")
    assert fh.tick(*args, "b", "b")[0] == 0 and len(made) == 1
    assert slack.msgs[-1]["text"] == "[뉴스 09:46] 변화 없음 · 지도 " + json.loads((state / "html.json").read_text())["link"]
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-20 08:01")  # 하루 첫 발행 = 변화 없어도 지도 1회
    assert fh.tick(*args, "b", "b")[0] == 0 and len(made) == 2


def test_r503_sync_error_no_map_one_unjudgeable_line(tmp_path, oc, slack, monkeypatch):
    """r907 r2(오빠 13:5x «이런 상태면 발행하지 마라») — 받기 실패(warn) 틱 = 게시 0 · rc1 · ERROR 1줄(구간 첫 틱) ·
    같은 구간 다음 틱(FT_LEDGER_SYNC_REPEAT=1) 도 게시 0(오래 가면 check_stale 정지 경보 1통)."""
    made: list = []
    state = _tick_env(tmp_path, monkeypatch, made)
    args = (tmp_path, state, tmp_path, "x.md", tmp_path / "news")
    monkeypatch.setenv("FT_NEWS_HEAD", "")
    monkeypatch.setenv("FT_NEWS_FETCH_LAST", str(tmp_path / "fetch-last"))
    monkeypatch.setenv("FT_LEDGER_SYNC_ERROR", "원장 사본 갱신 안 됨 — ERROR x")
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-19 09:15")
    assert fh.tick(*args, "a", "b") == (1, "원장 ref fetch 실패")  # r907 r2 — 판정 불가 = 게시 0 · rc1
    assert made == [] and slack.msgs == [] and (tmp_path / "fetch-last").read_text(encoding="utf-8").strip() == "fail"
    n = len(slack.msgs)
    monkeypatch.setenv("FT_LEDGER_SYNC_REPEAT", "1")
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-19 09:46")
    assert fh.tick(*args, "b", "b") == (1, "원장 ref fetch 실패 계속") and len(slack.msgs) == n and made == []


def test_e_tick_failure_publishes_nothing_keeps_base_and_backs_off(tmp_path, oc, slack, monkeypatch):
    made: list = []
    state = _tick_env(tmp_path, monkeypatch, made)
    oc[0].write_text("JSON 아님", encoding="utf-8")
    args = (tmp_path, state, tmp_path, "x.md", tmp_path / "news")
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-19 09:15")
    assert fh.tick(*args, "a", "b") == (1, "지도 만들기 실패")
    assert slack.msgs == [] and not (state / "last.sha").exists()
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-19 09:17")
    assert fh.tick(*args, "a", "b")[1] == "지도 만들기 실패(재시도 대기)" and len(made) == 1


# ── ⓕ 모드 없음 = 옛 판 경로(tick 호출 0) ───────────────────────────

def test_f_ledger_calls_tick_only_in_html_mode():
    src = (BIN / "ft_news_ledger.py").read_text(encoding="utf-8")
    assert 'if os.environ.get("FT_NEWS_MODE") == "html":' in src and src.count("return tick(") == 1
    assert (BIN / "ft_news_ledger.py").read_bytes() == (ROOT / "harness" / "kit" / "fable-team" / "bin" / "ft_news_ledger.py").read_bytes()


# ── ⓖ effort 표 ──────────────────────────────────────────────────

def test_g_effort_table_rows_per_variant(tmp_path, oc):
    (tmp_path / "in.json").write_text(json.dumps(DATA, ensure_ascii=False), encoding="utf-8")
    table = tmp_path / "EFFORT-news-html-20261019.md"
    done = subprocess.run(["bash", str(BIN / "ft-news-effort-test.sh"), "--variants", "base,max,depth:두 번 따져 본다", "--input", str(tmp_path / "in.json"), "--table", str(table)],
                          capture_output=True, text=True, env={**os.environ, "FT_NEWS_NOW": "2026-10-19 09:15"}, check=False)
    assert done.returncode == 0, done.stderr
    rows = [ln for ln in table.read_text(encoding="utf-8").splitlines() if ln.startswith("| ") and not ln.startswith("| 변형")]
    assert [r.split(" | ")[0] for r in rows] == ["| base", "| max", "| depth:두 번 따져 본다"]
    assert all(" | 0 | OK | 2 | " in r for r in rows)
    models = [c[3] for c in calls(oc[1])]
    base = "opencode/deepseek-v4.1-flash-free"
    assert models == [base] * 4 + [base + "#max"] * 4 + [base] * 4  # 변형마다 갈래 4
    assert all("두 번 따져 본다" in c[-1] for c in calls(oc[1])[8:]) and "기본값 결정(사람 1줄)" in table.read_text(encoding="utf-8")
    assert subprocess.run(["bash", str(BIN / "ft-news-effort-test.sh")], capture_output=True, check=False).returncode == 2


# ── ⓗ 고정 문구 · 상한 · 짝 ──────────────────────────────────────

def test_h_head_phrase_one_place_and_deadline_70(monkeypatch):
    assert np.html_post_text("가\n나\n다\n라", NOW).splitlines() == ["[뉴스 09:15] 팀 지도 — 가", "나", "다"]
    monkeypatch.setenv("FT_NEWS_HEAD", "팀 현황")
    assert np.html_post_text("가", NOW) == "[뉴스 09:15] 팀 현황 — 가"
    assert fr.DEADLINE_S == 70
    for f in ("ft_news_html.py", "ft_news_html_render.py", "ft_news_html_lint.py", "ft-news-effort-test.sh"):
        src = (BIN / f).read_text(encoding="utf-8")
        assert not re.search(r"\b(600|300)\s*(s|초|\))|timeout\s*=?\s*(600|300)", src), f
        assert src.encode() == (ROOT / "harness" / "kit" / "fable-team" / "bin" / f).read_bytes(), f
