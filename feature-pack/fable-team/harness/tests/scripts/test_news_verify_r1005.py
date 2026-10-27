"""r1005 발행 검증기 ft-news-verify ⓐ~ⓘ — r853 시험 틀(25칸) + DA⑥ r2 [수용] 반례 6칸 · 임시 리포·명부·쪽지함 스텁 · FT_NOW 고정 · 실 발행·실 슬랙 0.

실행: python3 -m pytest tests/scripts/test_news_verify_r1005.py -q
선행 착지(r847·r851·r1004) 뒤 판 — ⓘ 칸은 r1004 `root_readback_guard.check` 재호출(None = 정상 · 사유 글자 = 거짓).
"""
import contextlib
import io
import json
import logging
import os
import subprocess
import sys
import types
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
BIN = ROOT / "harness" / "bin"
KIT = ROOT / "harness" / "kit" / "slack-mirror"
sys.path[:0] = [str(BIN)]

import _news_verify as nv  # noqa: E402
import _news_verify_cells as cells  # noqa: E402
import _news_verify_pub_cells as pub  # noqa: E402
import ft_ledger_fill_tables as tb  # noqa: E402
import ft_news_html as nh  # noqa: E402
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd

NOW = "2026-10-27 03:40"
PUB_AT = "2026-10-27 03:00"
GIT_ENV = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}
TEAMS = """| 팀 | 폴더 | 오케 좌석 계열 | 상태 |
|---|---|---|---|
| harness | `$FT_HARNESS_ROOT/design/harness/` | byz-harness-master-claude | 현역 |
| planner | `design/teams/planner/` | byz-planner-master-claude | 현역 |
| cfo | `design/teams/cfo/` | byz-cfo-master-claude | 현역 |
"""
CLOSED_ROW = "| 2 | 닫힌 일 | 코드 | 닫힘 — 오빠 확인 끝 | — |"
LEDGER = "\n".join([
    "# 오빠 원장 (정본)", "",
    "## 1. 오빠가 시킨 일 — 지금 상태", "",
    "### 10-27 시키신 일", "| 순번 | 시키신 일 | 종류 | 지금 상태 | 발주 쪽지 |", "|---|---|---|---|---|",
    "| 1 | 열린 일 | 발주 | 진행 — 앞 단계 | — |", CLOSED_ROW, "",
    "## 2. 오빠 할 일", "1. 손으로 쓴 옛 줄", "",
    "## 5. 완료 보관", "| 순번 | 시키신 일 | 종류 | 닫는 증거 | 내린 날 |", "|---|---|---|---|---|",
    "| 10-15-1 | 옛 줄 | 코드 | 끝 | 10-15 |", ""])


def git(cwd: Path, *a: str) -> str:
    return subprocess.run(["git", "-C", str(cwd), *a], check=True, capture_output=True, text=True, env={**os.environ, **GIT_ENV}).stdout


def write(p: Path, text: str) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8")


class World:
    """검증 1회에 필요한 전부 — 발행본(body)·지도 상태(last.sha)·로그·명부·쪽지함 스텁."""

    def __init__(self, tmp: Path):
        self.tmp, self.root = tmp, tmp / "root"
        self.repo = self._repo(tmp)
        self.state = self.root / ".fable-team/state/news-ledger"
        self.st = self.root / ".fable-team/state/news-verify"
        self.body, self.log, self.sent = tmp / "NEWS.summary.txt", tmp / "news.log", tmp / "sent.log"
        self.base = git(self.repo, "rev-parse", "HEAD~1").strip()
        self.head = git(self.repo, "rev-parse", "HEAD").strip()
        self.short = git(self.repo, "rev-parse", "--short", "HEAD").strip()
        write(self.state / "last.sha", self.base + "\n")
        write(self.log, "INFO 뉴스 시작\n")
        write(self.sent, "")
        write(self.root / ".fable-team/seats-planner.json", json.dumps({"_master": "byz-planner-master-claude#1"}))
        write(self.root / ".fable-team/seats-harness.json", json.dumps({"byz-harness-nano-a#0": {"role": "nano"}}))
        write(self.root / ".fable-team/comm/mbox.sh", '#!/usr/bin/env bash\n'
              '{ printf \'%s\' "SEND $1 $2 "; printf \'%s\' "$4" | tr \'\\n\' \' \'; printf \'\\n\'; } >> "$FT_TEST_SENT"\n')
        write(self.root / ".fable-team/state/magazine-doc.json", json.dumps({"k": {"uploaded": True, "at": PUB_AT}}))
        self.body_text = "\n".join([
            f"# 팀 지도 {self.head[:10]} · 팀 3개", "",
            "## 오빠 할 일", "1. 질문 — 크레딧 한도 올릴까요 (묻는 팀 cfo)", "2. 실행 줄 — 기다린 지 5분 · ! bash /tmp/h1", "",
            "## 한 일", f"{self.short} [feature] 팀 착지", "",
            "## 팀 지도", "harness · planner · cfo — 지금 일하는 좌석 1", "",
            "지난밤 한 일은 위와 같고 오빠 할 일은 두 건입니다.", ""])
        write(self.body, self.body_text)

    @staticmethod
    def _repo(tmp: Path) -> Path:
        origin, repo = tmp / "origin.git", tmp / "repo"
        subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(origin)], check=True)
        subprocess.run(["git", "clone", "-q", str(origin), str(repo)], check=True, capture_output=True)
        git(repo, "checkout", "-q", "-b", "main")
        write(repo / "design/TEAMS.md", TEAMS)
        write(repo / "design/teams/planner/PLAN-oppa-ledger.md", LEDGER)
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "base")
        write(repo / "design/teams/cfo/indices/완성/cfo-done.md", "# 인덱스: cfo-done — 잔액 정리\n")
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "팀 착지")
        git(repo, "push", "-q", "origin", "main")
        git(repo, "fetch", "-q", "origin")
        return repo

    def run(self, *extra: str) -> tuple[int, str]:
        argv = ["--kind", "news", "--body", str(self.body), "--root", str(self.root), "--repo", str(self.repo),
                "--state", str(self.state), "--log", str(self.log), *extra]
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = nv.main(argv)
        return rc, buf.getvalue()

    def sends(self) -> list[str]:
        return [ln for ln in self.sent.read_text(encoding="utf-8").splitlines() if ln.strip()]

    def restore(self) -> None:
        write(self.body, self.body_text)


@pytest.fixture
def world(tmp_path, monkeypatch, caplog):
    w = World(tmp_path)
    caplog.set_level(logging.INFO, logger="ft_news_verify")
    monkeypatch.setenv("FT_ROOT", str(w.root))
    monkeypatch.setenv("FT_NOW", NOW)
    monkeypatch.setenv("FT_TEST_SENT", str(w.sent))
    monkeypatch.setenv("FT_NEWS_VERIFY_STATE", str(w.st))
    monkeypatch.setenv("FT_MAGAZINE_STATE", str(w.root / ".fable-team/state/magazine-doc.json"))
    monkeypatch.setenv("FT_NEWS_FETCH_LAST", str(w.root / ".fable-team/state/news-ledger/fetch-last"))
    monkeypatch.setattr(cells, "sources", lambda ctx: {"qs": [{"what": "크레딧", "seat": "byz-cfo-master#1"}], "hil": [("h1", 5)],
                                                        "queue": [], "cards": {}, "notes": {}})
    monkeypatch.setattr(nh, "live_teams", lambda root: [{"team": "harness", "live": 1, "working": 1, "unknown": 0}])
    w.guard = stub_guard(monkeypatch)  # r1004 가드 대역(빈 사유 = 정상) — check(text) = None
    w.guard_ok = w.guard.check
    return w


def stub_guard(monkeypatch, reason=None):
    """r1004 가드 대역 — check(text) 호출 수를 세고 사유(None = 정상)를 돌려준다(가드 «재호출» 검사)."""
    mod = types.ModuleType("root_readback_guard")
    mod.calls = []

    def check(text):
        mod.calls.append(text)
        return reason

    mod.check = check
    monkeypatch.setitem(sys.modules, "root_readback_guard", mod)
    return mod


def test_a_all_nine_true_publish_is_9_of_9_rc0(world, caplog):
    """ⓐ 9칸 모두 참 → «검증 9/9» rc0 · 로그 1줄 · 발행본 꼬리 «검증 9/9» · 연속 셈 1."""
    rc, out = world.run("--tail")
    assert rc == 0, out
    assert "검증 9/9" in out
    assert world.body.read_text(encoding="utf-8").rstrip().endswith("검증 9/9")
    assert sum("검증 9/9 kind=news" in r.getMessage() for r in caplog.records) == 1
    assert json.loads((world.st / "streak.json").read_text(encoding="utf-8"))["news"] == 1
    assert world.sends() == []


def _break_todo(w):
    write(w.body, w.body_text.replace("질문 — ", "질문 "))


def _break_commits(w):
    write(w.body, w.body_text.replace("[feature]", "[wip]"))


def _break_teams(w):
    write(w.body, w.body_text.replace("팀 3개", "팀 5개"))


def _break_sha(w):
    orphan = subprocess.run(["git", "-C", str(w.repo), "commit-tree", git(w.repo, "rev-parse", "HEAD^{tree}").strip(), "-m", "옛 갈래"],
                            capture_output=True, text=True, check=True, env={**os.environ, **GIT_ENV}).stdout.strip()
    write(w.body, w.body_text.replace(w.head[:10], orphan[:10]))


def _fix_sha(w):
    w.restore()


def _break_closed(w):
    row = next(ln for ln in LEDGER.splitlines() if ln == CLOSED_ROW)
    write(w.st / "closed-seen.json", json.dumps({tb.key(row): "2026-10-27 02:00"}, ensure_ascii=False))


def _fix_closed(w):
    (w.st / "closed-seen.json").unlink()


def _break_fetchlog(w):
    """ⓖ 거짓 = 표식 켜짐(fetch-last=fail) + 로그 실패 줄 — 표식이 꺼진 과거 줄만으로는 거짓이 아니다(r1005 반송 r2)."""
    write(w.log, "INFO 뉴스 시작\nERROR 원장 ref fetch 실패 — 판정 불가 · 게시 0\n")
    write(w.root / ".fable-team/state/news-ledger/fetch-last", "fail\n")


def _fix_fetchlog(w):
    write(w.log, "INFO 뉴스 시작\n")
    write(w.root / ".fable-team/state/news-ledger/fetch-last", "ok\n")


def _break_liveseats(w):
    nh.live_teams = lambda root: [{"team": "ops", "live": 1, "working": 1, "unknown": 0}]


def _fix_liveseats(w):
    nh.live_teams = lambda root: [{"team": "harness", "live": 1, "working": 1, "unknown": 0}]


def _break_quote(w):
    w.guard.check = lambda text: (w.guard.calls.append(text), "첫 줄이 결론 문장이 아님, 표 줄 3개")[1]  # r1004 check = 사유 글자


CASES = [
    ("ⓐ 오빠 할 일 건수", _break_todo, lambda w: w.restore()),
    ("ⓑ 한 일", _break_commits, lambda w: w.restore()),
    ("ⓒ 팀 수", _break_teams, lambda w: w.restore()),
    ("ⓓ 발행 sha", _break_sha, _fix_sha),
    ("ⓕ 완료 줄", _break_closed, _fix_closed),
    ("ⓖ fetch 실패", _break_fetchlog, _fix_fetchlog),
    ("ⓗ 팀 지도", _break_liveseats, _fix_liveseats),
    ("ⓘ 뿌리 글", _break_quote, lambda w: setattr(w.guard, "check", w.guard_ok)),
]


@pytest.mark.parametrize("name,break_it,fix_it", CASES, ids=[c[0] for c in CASES])
def test_b_break_one_cell_8_of_9_rc1_one_urgent_same_event_silent(world, name, break_it, fix_it):
    """ⓑ 칸마다 거짓 1개 → «검증 8/9 · 실패 <칸>» rc1 · [긴급] 1통 · 같은 칸 또 거짓 = 0통 · 참 뒤 다시 거짓 = 새 1통."""
    assert world.run()[0] == 0
    break_it(world)
    rc, out = world.run()
    assert rc == 1 and "검증 8/9" in out and name in out
    assert len(world.sends()) == 1 and "[긴급" in world.sends()[0]
    assert world.run()[0] == 1 and len(world.sends()) == 1
    fix_it(world)
    assert world.run()[0] == 0
    break_it(world)
    assert world.run()[0] == 1 and len(world.sends()) == 2


def test_b_same_warning_twice_in_a_day_is_the_ninth_cell(world):
    """ⓑ(ⓔ 칸) 같은 경고 문장이 하루 발행본 2판에 → «검증 8/9 · 실패 ⓔ 같은 경고»."""
    write(world.body, world.body_text + "판정 불가 — 원장 ref 받기 실패\n")
    assert world.run()[0] == 0  # 첫 판 = 1회
    rc, out = world.run()  # 같은 날 두 번째 판 = 2회
    assert rc == 1 and "검증 8/9" in out and "ⓔ 같은 경고" in out


def test_c_unknown_counts_as_failure_silent_pass_zero(world):
    """ⓒ 값 못 읽음(장부 없음) = «모름» = 실패로 셈 — 9/9 아님 · [긴급] 1통."""
    old = cells.sources
    cells.sources = lambda ctx: {"qs": RuntimeError("질문 장부 없음"), "hil": [], "queue": [], "cards": {}, "notes": {}}
    try:
        rc, out = world.run()
    finally:
        cells.sources = old
    assert rc == 1 and "검증 8/9" in out and "ⓐ 오빠 할 일 건수" in out
    assert len(world.sends()) == 1


def test_d_streak_24_sends_endline_once(world):
    """ⓓ 연속 셈: 9/9 마다 +1 · 24 도달 = planner 1통 «끝선 도달»(두 번째 0)."""
    write(world.st / "streak.json", json.dumps({"news": 23}))
    assert world.run()[0] == 0
    assert json.loads((world.st / "streak.json").read_text(encoding="utf-8"))["news"] == 24
    assert len(world.sends()) == 1 and "끝선 도달" in world.sends()[0]
    assert world.run()[0] == 0 and len(world.sends()) == 1


def test_e_verifier_own_failure_does_not_block_publish(world, caplog):
    """ⓔ 검증기 자체 실패(예외) = 로그 ERROR + [긴급] 1통 · 발행기(ft_news_html.verify_run)는 예외 0."""
    def boom(ctx):
        raise RuntimeError("칸이 터짐")
    old = nv.CELLS
    nv.CELLS = tuple((name, boom if name.startswith("ⓒ") else fn) for name, fn in old)
    try:
        rc, out = world.run()
    finally:
        nv.CELLS = old
    assert rc == 1 and "ⓒ 팀 수" in out and "예외 RuntimeError" in out
    assert len(world.sends()) == 1
    assert nh.verify_run(world.tmp / "없는.html", world.tmp / "없는.txt") is None  # 발행 유지(예외 전파 0)


def test_i_guard_recalled_normal_none_pass_and_reason_fail(world):
    """ⓘ = r1004 가드 «재호출» — None(정상) → 참 · 사유 글자 → 거짓(사유가 사유 줄에)."""
    assert world.run()[0] == 0
    assert len(world.guard.calls) >= 1 and "오빠 할 일" in world.guard.calls[-1]  # 발행본 글 그대로 넘긴다
    world.guard.check = lambda text: (world.guard.calls.append(text), "«…» 4개")[1]
    rc, out = world.run()
    assert rc == 1 and "검증 8/9" in out and "ⓘ 뿌리 글" in out and "«…» 4개" in out


def test_i_guard_missing_is_unavailable_not_silent_pass(world, monkeypatch):
    """ⓘ R1 — 가드 모듈이 없으면 «검증 불가» · 9/9 아님 · ERROR 1줄 · 쪽지는 0통.
    (r1004 착지 뒤로는 kit/slack-mirror 에 실 모듈이 있어 import 가 되므로 «모듈 없음» 을 _guard 로 흉내낸다.)"""
    def no_guard():
        raise ImportError("No module named 'root_readback_guard'")
    monkeypatch.setattr(pub, "_guard", no_guard)
    rc, out = world.run()
    assert rc == 1 and "검증 8/9" in out and "[검증 불가]" in out and "root_readback_guard" in out
    assert world.sends() == []  # 검증 불가는 쪽지 사건이 아니다(ERROR 로만)


def test_i_calls_guard_not_its_own_verdict():
    """ⓘ 변이 감지용 — cell_i 는 check() 를 부른다(자체 판정 0)."""
    saved = sys.modules.get("root_readback_guard")
    mod = types.ModuleType("root_readback_guard")
    mod.check = lambda text: "첫 줄이 결론 문장 아님"
    sys.modules["root_readback_guard"] = mod
    try:
        ctx = cells.Ctx(kind="news", texts=["| a | b |\n«가» «나» «다»"], root=Path("/tmp"), repo=Path("/tmp"),
                        rel="x", state=None, verify_state=None, log=None)
        verdict, why = pub.cell_i(ctx)
    finally:
        sys.modules.pop("root_readback_guard", None)
        if saved is not None:
            sys.modules["root_readback_guard"] = saved
    assert verdict == cells.FAIL and "첫 줄이 결론 문장 아님" in why


# ── V2 같은 사건 1통: 사건 키 = «실패 칸 하나» ────────────────────────────
def test_v2_one_message_per_cell_open_close_reopen(world):
    """{ⓐ}→{ⓐ,ⓒ}→{ⓐ}→정상→{ⓐ}: 새 사건만 1통(누적 3통 · 미복구 재알림 0 · 재발은 새 사건)."""
    _break_todo(world)
    assert world.run()[0] == 1 and len(world.sends()) == 1          # {ⓐ}
    write(world.body, world.body_text.replace("질문 — ", "질문 ").replace("팀 3개", "팀 5개"))
    assert world.run()[0] == 1 and len(world.sends()) == 2          # {ⓐ,ⓒ} — ⓒ 만 새 1통
    write(world.body, world.body_text.replace("질문 — ", "질문 "))
    assert world.run()[0] == 1 and len(world.sends()) == 2          # {ⓐ} — 열린 칸이라 0통
    world.restore()
    assert world.run()[0] == 0 and len(world.sends()) == 2          # 정상 = 0통(열린 키 닫힘)
    _break_todo(world)
    assert world.run()[0] == 1 and len(world.sends()) == 3          # 재발 = 새 사건 1통


def test_v2_open_cell_not_realarmed_when_set_grows_and_shrinks(world):
    """{ⓐ}→{ⓐ,ⓑ}→{ⓐ} — 미복구 ⓐ 를 다시 알리지 않는다(쪽지 누적 2통, 3통 아님)."""
    _break_todo(world)
    assert world.run()[0] == 1 and len(world.sends()) == 1
    _break_teams(world)
    assert world.run()[0] == 1 and len(world.sends()) == 2
    write(world.body, world.body_text.replace("팀 3개", "팀 5개"))  # ⓐ 는 계속 실패 · ⓑ 는 정상
    assert world.run()[0] == 1 and len(world.sends()) == 2


# ── V3 모듈은 있는데 함수가 없음 = «검증 불가»(모름·쪽지 아님) ───────────────
def test_v3_guard_module_without_check_is_unavailable(world, monkeypatch):
    mod = types.ModuleType("root_readback_guard")  # check 없음
    monkeypatch.setitem(sys.modules, "root_readback_guard", mod)
    rc, out = world.run()
    assert rc == 1 and "검증 8/9" in out and "[검증 불가]" in out and "check 함수 없음" in out
    assert world.sends() == []


def test_v3_ledger_module_without_teams_is_unavailable(world, monkeypatch):
    real = cells.need

    def need(module, name):
        if (module, name) == ("ft_ledger_fill_src", "teams"):
            raise cells.Missing("ft_ledger_fill_src.teams 함수 없음")
        return real(module, name)
    monkeypatch.setattr(cells, "need", need)
    rc, out = world.run()
    assert rc == 1 and "검증 8/9" in out and "[검증 불가]" in out and "teams 함수 없음" in out
    assert world.sends() == []


# ── V4 검증기 자체 예외 = 발행 유지 · ERROR 1줄 · 쪽지 1(R2) ────────────────
def test_v4_broken_streak_state_is_one_error_and_one_message(world, caplog):
    write(world.st / "streak.json", "[]")
    rc, out = world.run()
    assert rc == 1
    assert any(r.levelname == "ERROR" and "검증기 자체 실패" in r.getMessage() for r in caplog.records)
    assert len(world.sends()) == 1 and "자체 실패" in world.sends()[0]
    assert world.run()[0] == 1 and len(world.sends()) == 1  # 같은 사유 연속 = 0통


def test_v4_news_caller_oserror_keeps_publish_and_sends_one(world, monkeypatch):
    def boom(*a, **k):
        raise OSError("exec 실패")
    monkeypatch.setenv("FT_NEWS_VERIFY", "1")
    monkeypatch.setattr(nh, "subprocess", types.SimpleNamespace(run=boom, CompletedProcess=subprocess.CompletedProcess, TimeoutExpired=subprocess.TimeoutExpired))
    assert nh.verify_run(world.tmp / "a.html", world.tmp / "a.txt") is None  # 예외 전파 0(발행 유지)
    assert len(world.sends()) == 1 and "자체 실패" in world.sends()[0]
    assert nh.verify_run(world.tmp / "a.html", world.tmp / "a.txt") is None
    assert len(world.sends()) == 1  # 같은 사유 연속 = 0통


# ── V5·V6 매거진 호출부: 실제 출력 폴더에서 찾기 · HOME 없어도 rc0 ───────────
def magazine_run(w, out_dir: Path, html: str | None, extra_args=(), extra_env=None):
    doc, vlog, vbin = w.tmp / "doc.py", w.tmp / "verify.calls", w.tmp / "ft-news-verify"
    line = f"PUBLISH warn=0 elapsed=0.0s html={out_dir / html}" if html else "ARGS --publish"
    doc.write_text(  # 발행기 대역 — 상태 가드가 parse_args 를 부른다(r707) · 본문 출력은 __main__ 일 때만
        "import types\n\n\ndef parse_args(argv=None):\n"
        f"    return types.SimpleNamespace(publish=True, dry_run=False, date=None, state={str(w.tmp / 'magazine-doc.json')!r})\n\n\n"
        f"if __name__ == '__main__':\n    print({line!r})\n", encoding="utf-8")
    vbin.write_text(f'#!/usr/bin/env bash\necho "$@" >> "{vlog}"\n', encoding="utf-8")
    env = {"PATH": os.environ["PATH"], "FT_ROOT": str(w.root), "FT_LEDGER_REPO": str(w.repo),
           "FT_LEDGER_PATH": "design/teams/planner/PLAN-oppa-ledger.md", "FT_LEDGER_SYNCED": "1", "FT_LEDGER_FRESH_GATE": "0",
           "FT_MAGAZINE_DOC": str(doc), "FT_NEWS_VERIFY_BIN": str(vbin), **(extra_env or {})}  # HOME 없음(V6)
    r = subprocess.run(["bash", str(KIT / "magazine_from_news.sh"), *extra_args], env=env, capture_output=True, text=True, timeout=30)
    return r, (vlog.read_text(encoding="utf-8") if vlog.exists() else "")


def test_v5_magazine_verifies_in_out_dir_and_tails_the_file(world):
    out = world.tmp / "별도폴더"
    write(out / "MAGAZINE-DOC-2026-10-27-abc.html", "<h1>매거진</h1>\n")
    r, calls = magazine_run(world, out, "MAGAZINE-DOC-2026-10-27-abc.html", ("--publish", "--out-dir", str(out)))
    assert r.returncode == 0, r.stderr
    assert "--kind magazine" in calls and "MAGAZINE-DOC-2026-10-27-abc.html" in calls and "--tail" in calls
    assert "HOME" not in r.stderr and "unbound" not in r.stderr  # V6


def test_v5_magazine_out_dir_equals_form_and_missing_file_is_error(world):
    out = world.tmp / "eq폴더"
    write(out / "MAGAZINE-DOC-2026-10-27-abc.html", "<h1>매거진</h1>\n")
    r, calls = magazine_run(world, out, "MAGAZINE-DOC-2026-10-27-abc.html", ("--publish", f"--out-dir={out}"))
    assert r.returncode == 0 and "--kind magazine" in calls
    (out / "MAGAZINE-DOC-2026-10-27-abc.html").unlink()
    (world.tmp / "verify.calls").unlink()
    r, calls = magazine_run(world, out, "MAGAZINE-DOC-2026-10-27-abc.html", ("--publish", "--out-dir", str(out)))
    assert r.returncode == 7 and "검증할 발행본 못 찾음" in r.stderr and calls == ""


def test_v6_magazine_without_home_and_without_html_line_is_rc0_warn(world):
    r, calls = magazine_run(world, world.tmp, None, ("--publish",))  # 대역: html= 줄 없음 · HOME 없음
    assert r.returncode == 0 and "WARN" in r.stderr and "unbound" not in r.stderr and calls == ""


# ── r1005 · DA⑥ r2 [수용] 반례 6칸 ─────────────────────────────────────────
def test_r2_1_unavailable_is_not_recovery_same_cell_one_message(world, monkeypatch):
    """반례 1 — ⓘ 실패 → 검증 불가(check 없음) → 같은 실패 복원 = 쪽지 누적 1→1→1통(«복구» 로 읽지 않는다)."""
    _break_quote(world)
    assert world.run()[0] == 1 and len(world.sends()) == 1                 # ⓘ 거짓 = 1통
    mod = types.ModuleType("root_readback_guard")                          # 모듈만 있고 check 없음 = 검증 불가
    monkeypatch.setitem(sys.modules, "root_readback_guard", mod)
    rc, out = world.run()
    assert rc == 1 and "[검증 불가]" in out and len(world.sends()) == 1     # 검증 불가 = 쪽지 0 · 사건 안 닫힘
    monkeypatch.setitem(sys.modules, "root_readback_guard", world.guard)    # 같은 실패 복원
    assert world.run()[0] == 1 and len(world.sends()) == 1                 # 2통이 아니라 1통


def test_r2_2_unreadable_body_is_one_error_and_one_message(world, caplog):
    """반례 2 — 발행본 읽기 권한 000: 예외 전파 0(rc1) · ERROR 1줄 · planner 쪽지 1통."""
    world.body.chmod(0o000)
    try:
        rc, out = world.run()
    finally:
        world.body.chmod(0o644)
    assert rc == 1
    assert any(r.levelname == "ERROR" and "발행본 못 읽음" in r.getMessage() for r in caplog.records)
    assert len(world.sends()) == 1 and "자체 실패" in world.sends()[0]


def test_r2_3_broken_self_error_state_still_one_message(world):
    """반례 3 — streak.json=[] · self-error.json=[]: 오류 처리기 안에서 안 죽고 ERROR + 쪽지 1통."""
    write(world.st / "streak.json", "[]")
    write(world.st / "self-error.json", "[]")
    assert world.run()[0] == 1
    assert len(world.sends()) == 1 and "자체 실패" in world.sends()[0]
    assert world.run()[0] == 1 and len(world.sends()) == 1  # 같은 사유 연속 = 0통


def test_r2_4_same_self_error_after_recovery_is_a_new_message(world):
    """반례 4 — 자체 오류 → 정상 9/9 복구 → 같은 자체 오류 재발 = 새 1통(누적 1→1→2)."""
    write(world.st / "streak.json", "[]")
    assert world.run()[0] == 1 and len(world.sends()) == 1
    write(world.st / "streak.json", "{}")
    assert world.run()[0] == 0 and len(world.sends()) == 1   # 정상 완주 = 자체 오류 사건 닫힘
    write(world.st / "streak.json", "[]")
    assert world.run()[0] == 1 and len(world.sends()) == 2   # 재발 = 새 1통


def test_r2_5_tail_write_failure_is_not_9_of_9(world, caplog):
    """반례 5 — 발행본 0444 에 --tail: 꼬리를 못 썼으면 9/9 아님(rc≠0 · ERROR · 쪽지 1)."""
    world.body.chmod(0o444)
    try:
        rc, out = world.run("--tail")
    finally:
        world.body.chmod(0o644)
    assert rc == 1 and "꼬리 못 씀" in out
    assert any(r.levelname == "ERROR" and "꼬리 못 씀" in r.getMessage() for r in caplog.records)
    assert len(world.sends()) == 1
    assert "검증 9/9" not in world.body.read_text(encoding="utf-8")


# ── r1005 반송 r2 · ⓖ = 최신 상태가 이긴다(표식 꺼짐이면 과거 로그 줄 셈 0) ──────────────
def test_r2_g_marker_off_ignores_past_log_lines(world, monkeypatch):
    """반송 r2 — 과거 «원장 ref fetch 실패» 줄 + 그 뒤 성공 + 표식 False → ⓖ 참 · 9/9 rc0 · 쪽지 0."""
    write(world.log, "INFO 뉴스 시작\nERROR 원장 ref fetch 실패 — 판정 불가 · 게시 0\nINFO 원장 ref fetch 성공\n")
    real_need = pub.need
    monkeypatch.setattr(pub, "need", lambda m, n: (lambda: False) if (m, n) == ("ft_news_ledger", "fail_announced") else real_need(m, n))
    rc, out = world.run()
    assert rc == 0 and "검증 9/9" in out and world.sends() == []
    assert "과거 로그 1줄 셈 0" not in out  # 실패 칸이 아니라 사유 줄을 안 찍는다(참이면 사유 출력 0)


def test_r2_g_marker_on_is_a_failure_one_message(world, monkeypatch):
    """반송 r2 — 표식이 켜져 있으면 지금대로 ⓖ 거짓 · 쪽지 1통(«표식 무시» 변이 감시)."""
    write(world.log, "INFO 뉴스 시작\n")
    real_need = pub.need
    monkeypatch.setattr(pub, "need", lambda m, n: (lambda: True) if (m, n) == ("ft_news_ledger", "fail_announced") else real_need(m, n))
    rc, out = world.run()
    assert rc == 1 and "검증 8/9" in out and "ⓖ fetch 실패" in out and len(world.sends()) == 1


def test_r2_6_magazine_tilde_out_dir_is_expanded(world, tmp_path_factory):
    """반례 6 — `--out-dir '~/tilde-out'`: «~» 를 펼쳐 그 폴더에서 검증한다(문자 그대로 찾아 rc7 0)."""
    home = tmp_path_factory.mktemp("home")
    write(home / "tilde-out/MAGAZINE-DOC-2026-10-27-abc.html", "<h1>매거진</h1>\n")
    r, calls = magazine_run(world, Path("~/tilde-out"), "MAGAZINE-DOC-2026-10-27-abc.html",
                            ("--publish", "--out-dir", "~/tilde-out"), {"HOME": str(home)})
    assert r.returncode == 0, r.stderr
    assert "--kind magazine" in calls and str(home / "tilde-out") in calls


# ── r1005 반송 r1 · 상태 파일 손상(깨진 JSON) = 자체 오류 길 · 9/9 금지 · 덮어쓰기 0 ──────────
def test_r1_1_broken_streak_json_is_error_one_message_and_not_9_of_9(world, caplog):
    """반송 r1 ① — streak.json='{' : ERROR 1줄 · planner 쪽지 1통 · «검증 9/9» 아님 · 손상 파일 그대로."""
    write(world.st / "streak.json", "{")
    rc, out = world.run()
    assert rc == 1 and "검증 불가 — 상태 파일 손상" in out and "검증 9/9" not in out
    assert any(r.levelname == "ERROR" and "자체 실패" in r.getMessage() for r in caplog.records)
    assert len(world.sends()) == 1 and "자체 실패" in world.sends()[0]
    assert (world.st / "streak.json").read_text(encoding="utf-8") == "{"  # 초기값으로 덮어쓰기 0


def test_r1_2_broken_alarm_json_same_failure_keeps_one_message(world):
    """반송 r1 ① — alarm.json='{' 뒤 같은 실패를 다시 돌려도 쪽지 누적 1통 그대로(사건 키 = 상태 손상)."""
    write(world.st / "alarm.json", "{")
    _break_todo(world)
    assert world.run()[0] == 1 and len(world.sends()) == 1
    assert world.run()[0] == 1 and len(world.sends()) == 1   # 두 번째 회차 = 같은 사건 0통
    assert (world.st / "alarm.json").read_text(encoding="utf-8") == "{"  # 사건 기록으로 덮어쓰기 0


def test_r1_3_missing_state_files_are_still_a_first_run(world):
    """반송 r1 — «파일 없음» 은 지금대로 정상 초기값(첫 실행) — 9/9 rc0 · 쪽지 0."""
    assert not (world.st / "streak.json").exists()
    rc, out = world.run()
    assert rc == 0 and "검증 9/9" in out and world.sends() == []


def test_r2_6_magazine_tilde_without_home_is_rc7(world):
    """반례 6(환경) — HOME 없이 «~» 출력 폴더 = 펼침 불가 · ERROR 1줄 + rc7(조용한 건너뜀 0)."""
    r, calls = magazine_run(world, Path("~/tilde-out"), "MAGAZINE-DOC-2026-10-27-abc.html",
                            ("--publish", "--out-dir", "~/tilde-out"))
    assert r.returncode == 7 and "HOME 없음" in r.stderr and calls == ""
