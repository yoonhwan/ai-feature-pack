"""r870 원장 채움 push·로컬 git 시간 초과 ⓐ~ⓓ·ⓗ·1-b — r851 픽스처(임시 bare origin + 사본 · 실 원격 0) + git 래퍼(PATH 앞 · 하위 명령마다 잠 · 호출 기록).
래퍼 잠은 축척: push 상한 REMOTE_S 를 2초로 낮추고 «push 9초·12초 + 훅 2초» 를 «1.5초·3초 + 훅 1초» 로 둔다(같은 비율 · 시험 시간만 줄임).
실행: python3 -m pytest tests/scripts/test_ledger_fill_r870.py -q   (ⓕ 변이 = evidence/r870/mutation.sh)
"""
import logging
import shutil
from datetime import timedelta

import pytest

from test_ledger_fill_r851 import BR, NOW, REL, fill, guard_begin_module, n_commits, sha_of, world  # noqa: F401  r851 픽스처 그대로
import ft_ledger_fill as lf
import ft_ledger_fill_src as src

WRAP = r"""#!/usr/bin/env bash
a=("$@"); i=0
while [ $i -lt ${#a[@]} ]; do case "${a[$i]}" in -C|-c) i=$((i+2));; *) break;; esac; done
sub="${a[$i]}"
echo "$sub $*" >> "$R870_CALLS"
case "$sub" in
  push) sleep "${R870_PUSH:-0}"; case " $* " in *" --no-verify "*) ;; *) sleep "${R870_HOOK:-0}";; esac;;
  read-tree) sleep "${R870_READ_TREE:-0}";;
  rev-parse) case " $* " in *" -q "*) sleep "${R870_HAS:-0}";; esac;;
  log) sleep "${R870_LOG:-0}";;
esac
exec "$R870_GIT" "$@"
"""


@pytest.fixture
def wrap(world, monkeypatch):  # noqa: F811 — r851 픽스처를 받는 자리
    d, calls = world["tmp"] / "wrapbin", world["tmp"] / "calls.log"
    d.mkdir()
    (d / "git").write_text(WRAP, encoding="utf-8")
    (d / "git").chmod(0o755)
    monkeypatch.setenv("R870_GIT", shutil.which("git"))
    monkeypatch.setenv("R870_CALLS", str(calls))
    monkeypatch.setenv("PATH", f"{d}:{__import__('os').environ['PATH']}")
    monkeypatch.setattr(lf, "REMOTE_S", 2.0)
    monkeypatch.setenv("FT_LEDGER_FILL", "1")  # conftest 기본 끔(실 원장 보호) — 여기는 임시 원장
    monkeypatch.delenv("FT_LEDGER_FILL_PUSH", raising=False)
    calls.write_text("", encoding="utf-8")
    pushes = lambda: [ln for ln in calls.read_text(encoding="utf-8").splitlines() if ln.startswith("push ")]  # noqa: E731
    return {**world, "pushes": pushes, "set": lambda **kv: [monkeypatch.setenv(f"R870_{k.upper()}", str(v)) for k, v in kv.items()]}


def test_a_branch_holds_main_same_render_no_change_push_zero(wrap, capsys):
    rc, sha = fill(wrap)
    assert rc == 0 and sha and len(wrap["pushes"]()) == 1
    n1 = n_commits(wrap)
    rc, sha = fill(wrap)  # r3: 사본 ⊇ main → bases() 가 사본 머리를 base 로 · 렌더 = 그 머리 → tb.same «변화 없음» 이 push 0 을 맡음
    out = capsys.readouterr().out
    assert (rc, sha) == (0, sha_of(wrap, BR)) and len(wrap["pushes"]()) == 1 and n_commits(wrap) == n1  # r4 — 반환 = 읽은 판(사본 머리)
    assert "FILL 변화 없음" in out and "push 생략(같음)" not in out


def test_a3_raced_same_render_no_change_returns_winner_to_news(wrap, monkeypatch):
    import ft_news_html as fh
    from test_ledger_fill_r851 import _clone, run
    rc, b = fill(wrap)  # 공통 부모 A · ledger/auto = B
    other = _clone(wrap, "planner-empty")
    run(other, "commit", "-q", "--allow-empty", "-m", "main 전진")
    run(other, "push", "-q", "origin", "main")
    m = sha_of(wrap, "main")
    lf.fetch(wrap["repo"])  # 뉴스 틱은 do_fetch=False — 앞 단계 받기가 이미 끝난 꼴
    real_push, won = lf._push, []

    def raced_push(repo, sha, br):  # 다른 작성자 C(부모 [M, B] · 같은 렌더)가 이번 push 직전에 먼저 올림(대역 · DA⑥ r3 반례)
        if not won:
            won.append(run(wrap["origin"], "commit-tree", f"{b}^{{tree}}", "-p", m, "-p", b, "-m", "다른 작성자 같은 렌더").strip())
            run(wrap["origin"], "update-ref", f"refs/heads/{BR}", won[0])
        return real_push(repo, sha, br)

    monkeypatch.setattr(lf, "_push", raced_push)
    got = fh.ledger_fill(wrap["root"], wrap["repo"], REL, m)  # 이번 push ff 거절 → 다시 받기 → C 위 «변화 없음»
    assert won and got == won[0] == sha_of(wrap, BR) and got != m  # 옛 판 = '' → 뉴스 cur=M(옛 원장)
    assert len([p for p in wrap["pushes"]() if p.endswith(f":refs/heads/{BR}")]) == 2  # B + 거절된 1


def test_a2_same_tree_but_branch_misses_main_still_merges_and_pushes(wrap, monkeypatch, capsys):
    from test_ledger_fill_r851 import _clone, run
    real_read_ref = src.read_ref
    monkeypatch.setattr(src, "read_ref", lambda repo, ref="origin/main": f"refs/remotes/origin/{BR}")  # fetch 경쟁 대역(DA⑥ r2 — 검사 사이 사본이 C(⊇M) 로 전진) · r3 = 그래도 병합 push
    rc, b = fill(wrap)  # 공통 부모 A · ledger/auto = B(채움 커밋)
    other = _clone(wrap, "planner-empty")
    run(other, "commit", "-q", "--allow-empty", "-m", "main 전진")  # main = M(빈 커밋 · 트리 = A)
    run(other, "push", "-q", "origin", "main")
    m = sha_of(wrap, "main")
    rc, sha = fill(wrap)  # 렌더 = B 트리 · 옛 판 = «push 생략(같음)» → 뉴스는 M(옛 원장) · 채움은 성공 기록(DA⑥ r1 반례)
    parents = run(wrap["repo"], "rev-list", "--parents", "-n", "1", sha).split()[1:] if sha else []
    ledger_pushes = [p for p in wrap["pushes"]() if p.endswith(f":refs/heads/{BR}")]  # 시험이 친 main push 는 빼고 셈
    assert rc == 0 and parents == [m, b] and len(ledger_pushes) == 2 and sha_of(wrap, BR) == sha
    assert "push 생략(같음)" not in capsys.readouterr().out
    assert real_read_ref(wrap["repo"]) == f"refs/remotes/origin/{BR}"  # 뉴스·매거진이 새 판(사본 브랜치)을 고름


def test_b_push_cap_no_hook_retry_once_on_silent_timeout(wrap, caplog):
    wrap["set"](push=1.5, hook=1.0)  # 옛 판: 1.5 + 훅 1.0 > 상한 2.0 = 시간 초과 · 새 판: 훅 건너뜀 = 상한 안
    rc, sha = fill(wrap)
    assert rc == 0 and sha_of(wrap, BR) == sha and len(wrap["pushes"]()) == 1
    wrap["set"](push=3)  # 출력 0 시간 초과 = 재시도 1 · 그 뒤 실패 = FillError(무한 재시도 0)
    (wrap["q"]).write_text('{"open": {"9": {"seat": "byz-cfo-x#1", "what": "새 질문", "state": "open"}}}', encoding="utf-8")
    with pytest.raises(src.FillError, match="git push .*timed out"):
        fill(wrap, NOW + timedelta(minutes=1))
    assert len(wrap["pushes"]()) == 1 + 2


def test_b_push_failure_with_output_no_retry(wrap):
    from test_ledger_fill_r851 import run
    run(wrap["repo"], "remote", "set-url", "--push", "origin", str(wrap["tmp"] / "없는곳.git"))
    with pytest.raises(src.FillError, match="git push 실패"):
        fill(wrap)
    assert len(wrap["pushes"]()) == 1  # 출력(오류 글) 있는 실패 = 확정 실패 · 재시도 0(하드 룰 12)


def test_c_push_failure_error_once_then_warning_and_same_commit_next_tick(wrap, caplog):
    import ft_news_html as fh
    caplog.set_level(logging.INFO)
    wrap["set"](push=3)
    cur = sha_of(wrap, "main")
    assert fh.ledger_fill(wrap["root"], wrap["repo"], REL, cur) == cur  # 실패 = 지금 판으로 계속(뉴스 틱 안 죽음)
    first = lf._load(lf.state_dir(wrap["root"]) / "push-fail.json", {})
    assert first.get("sha") and first.get("n") == 1
    assert fh.ledger_fill(wrap["root"], wrap["repo"], REL, cur) == cur
    recs = [r for r in caplog.records if "원장 채움 실패" in r.getMessage()]
    assert [r.levelname for r in recs] == ["ERROR", "WARNING"] and "git push" in recs[0].getMessage() and "timed out" in recs[0].getMessage()
    assert "같은 원인 연속 2회" in recs[1].getMessage()
    wrap["set"](push=0)
    sha = fh.ledger_fill(wrap["root"], wrap["repo"], REL, cur)
    assert sha == first["sha"] == sha_of(wrap, BR)  # 다음 틱 = 같은 커밋을 다시 올림
    assert not (lf.state_dir(wrap["root"]) / "push-fail.json").exists()


def test_d_push_skips_hook_only_for_ledger_refspec(wrap):
    fill(wrap)
    (line,) = wrap["pushes"]()
    assert " --no-verify " in f" {line} " and line.endswith(f":refs/heads/{BR}") and line.count("refs/heads/") == 1


def test_h_read_tree_timeout_is_fill_error_news_tick_survives(wrap, caplog):
    import ft_news_html as fh
    wrap["set"](read_tree=9)  # 로컬 상한 7초 넘김
    cur = sha_of(wrap, "main")
    assert fh.ledger_fill(wrap["root"], wrap["repo"], REL, cur) == cur  # 옛 판 = TimeoutExpired 가 그대로 올라가 뉴스 틱 Traceback rc1
    msgs = [r.getMessage() for r in caplog.records if r.levelname == "ERROR"]
    assert any("원장 채움 실패" in m and "git read-tree 시간 초과" in m for m in msgs)


def test_h2_ref_probe_timeout_is_fill_error(wrap):
    wrap["set"](has=9)  # bases() 의 사본 브랜치 유무(rev-parse -q) 7초 넘김 — 옛 판 = TimeoutExpired(뉴스 틱 Traceback)
    with pytest.raises(src.FillError, match="rev-parse"):
        fill(wrap)


def test_1b_card_log_cap_scales_with_commits_in_window(wrap, monkeypatch):
    assert src.sized(0, 100) == 7.0 and src.sized(261, 100) == 21.0 and src.sized(10 ** 6, 100) == 70.0  # 하드 룰 12 · 70초 천장
    monkeypatch.setattr(src, "LOG_BASE", 1)  # 창 안 커밋 2개 = 상한 14초
    wrap["set"](log=8)  # 고정 7초 = 시간 초과(표 갱신 0) · 크기 비례 = 통과
    cards = src.team_cards(wrap["repo"], "origin/main", NOW)
    assert [n for n, _t in cards["cfo"]["착지"]] == ["cfo-done"]
