"""아침 매거진 ① detail 수집 시험 — 설계 §9-1 (임시 git 리포 2 ref · 가짜 gh · 네트워크 0).

리포: main(c0 창 앞 → c1 창 안 → c2 창 뒤) · ops(c0 에서 갈라져 창 안 커밋 1).
"""
import copy
import json
import os
import stat
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _magazine_fakes import DETAIL_FIXTURE, KIT  # noqa: E402,F401
import magazine_card_shape as shape  # noqa: E402
import magazine_collect  # noqa: E402
import magazine_collect_detail as mcd  # noqa: E402
import magazine_collect_gh as mgh  # noqa: E402
import magazine_collect_open as mco  # noqa: E402
from magazine_window import MagazineError  # noqa: E402

KST = ZoneInfo("Asia/Seoul")
START = datetime(2026, 10, 7, 8, tzinfo=KST)
END = datetime(2026, 10, 8, 8, tzinfo=KST)
H = "design/harness"


def card(title: str, status: str) -> str:
    return (f"# 인덱스: {title}\n\n## 골 원문 (항상 이 3줄)\n골 하나\n\n## 골좌표\n하네스 GOAL 표 / 닫는 증거: 「증거」.\n\n"
            f"## 배경 (한 단락)\n{title} 배경 첫 줄\n둘째 줄\n\n## 구현 범위\n1. x\n\n## 상태\n{status}\n")


CLOSED = ("- 2026-10-06 — 대기/ 생성\n- 세트: " + "d" * 40 + " · 시험: pytest rc=0 · 이슈: 0\n- 2026-10-07 — 완료 독립 검증 · 통과\n"
          f"- 2026-10-07 12:00 — 진행→완성 · DA {H}/OPS-VERDICTS-T.md#§2")
LEDGER = ("| # | 접수 | 요청자 | 증상 1줄 | Issue | 오빠 값 | 반영 sha |\n|---|---|---|---|---|---|---|\n"
          "| R1 | 10-04 | a | 닫힌 증상 | #1 | 닫힘 10-05 (PR 1) | abc |\n| R2 | 10-05 | b | 열린 증상 | | 접수 · 대기 | |\n"
          "| R3 | 10-06 | c | 끝 빈칸 증상 | | 닫힘 10-07 (PR 2) | def | |\n")  # R3: 손으로 쓴 표라 끝에 빈 칸이 더 붙은 행(실측 R25)


def sh(repo: Path, date: str, *a: str) -> str:
    env = {**os.environ, "GIT_AUTHOR_DATE": date, "GIT_COMMITTER_DATE": date}
    r = subprocess.run(["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t", *a], capture_output=True, text=True, env=env)
    assert r.returncode == 0, r.stderr
    return r.stdout.strip()


def put(repo: Path, path: str, text: str, mode: str = "w") -> None:
    p = repo / path
    p.parent.mkdir(parents=True, exist_ok=True)
    with p.open(mode, encoding="utf-8") as f:
        f.write(text)


def commit(repo: Path, date: str, msg: str) -> str:
    sh(repo, date, "add", "-A")
    sh(repo, date, "commit", "-q", "-m", msg)
    return sh(repo, date, "rev-parse", "HEAD")


@pytest.fixture
def repo(tmp_path: Path) -> dict:
    r = tmp_path / "r"
    r.mkdir()
    sh(r, "2026-10-06T12:00:00+09:00", "init", "-q", "-b", "main")
    put(r, f"{H}/indices/진행/card1.md", card("원본 카드1", "- 진행 중"))
    put(r, f"{H}/indices/진행/card2.md", card("카드2", "- a\n- b\n- c\n- d\n- e"))
    put(r, f"{H}/indices/대기/card3.md", card("카드3", "- 대기"))
    put(r, f"{H}/indices/완성/old0.md", card("옛 카드", CLOSED))
    put(r, f"{H}/OPS-VERDICTS-T.md", "# 판정\n\n## §1 옛 절 — 닫힘\n옛 본문\n")
    put(r, f"{H}/REQUEST-LEDGER.md", LEDGER)
    put(r, f"{H}/NANO-LEDGER-h.md", "- 옛 좌석 닫힘(ft-nano-close)\n")
    put(r, f"{H}/DA-old.md", "옛 DA\nHOLD\n")
    c0 = commit(r, "2026-10-06T12:00:00+09:00", "c0")
    sh(r, "2026-10-06T12:00:00+09:00", "branch", "ops")
    d1 = "2026-10-07T12:00:00+09:00"
    sh(r, d1, "mv", f"{H}/indices/진행/card1.md", f"{H}/indices/완성/card1.md")
    put(r, f"{H}/indices/완성/card1.md", card("원본 카드1", CLOSED))
    put(r, f"{H}/OPS-VERDICTS-T.md", "## §2 새 절 — 닫힘\n새 본문 1\n새 본문 2\n", "a")
    put(r, f"{H}/DA-new.md", "새 DA\n**HOLD**\n")
    put(r, f"{H}/DA-ok.md", "승인 DA\nAPPROVE\n")
    put(r, f"{H}/BRIEFING-x.md", "브리핑 전문\n")
    put(r, f"{H}/NANO-LEDGER-h.md", "- 새 좌석 닫힘(ft-nano-close)\n- 열린 줄\n", "a")
    c1 = commit(r, d1, "[docs] 창 안 머지\n\nWhy: 이유\nVerify: 확인")
    sh(r, "2026-10-08T12:00:00+09:00", "mv", f"{H}/indices/진행/card2.md", f"{H}/indices/완성/card2.md")
    c2 = commit(r, "2026-10-08T12:00:00+09:00", "c2 창 뒤")
    d2 = "2026-10-07T13:00:00+09:00"
    sh(r, d2, "checkout", "-q", "ops")
    sh(r, d2, "mv", f"{H}/indices/진행/card1.md", f"{H}/indices/완성/card1.md")
    put(r, f"{H}/indices/완성/card1.md", card("ops본 카드1", CLOSED))
    sh(r, d2, "mv", f"{H}/indices/대기/card3.md", f"{H}/indices/완성/card3.md")
    put(r, f"{H}/OPS-VERDICTS-T.md", "## §3 ops 절 — 닫힘\nops 본문\n", "a")
    o1 = commit(r, d2, "ops 커밋")
    sh(r, d2, "checkout", "-q", "main")
    (r.parent / "root" / "state" / "gce").mkdir(parents=True)
    (r.parent / "root" / "state" / "gce" / "BREACH.md").write_text("# 위반 전문\n", encoding="utf-8")
    return {"path": r, "c0": c0, "c1": c1, "c2": c2, "o1": o1, "root": r.parent / "root"}


def detail(repo: dict, refs: list[str], merges: list[str] | None = None) -> dict:
    return mcd.collect_detail(repo["path"], refs, START, END, merges or [])


def test_units_only_cards_moved_into_done_inside_window_first_ref_wins(repo):
    d = detail(repo, ["main", "ops"])
    assert {u["path"] for u in d["units"]} == {f"{H}/indices/완성/card1.md", f"{H}/indices/완성/card3.md"}
    u = next(u for u in d["units"] if u["path"].endswith("card1.md"))
    assert (u["ref"], u["title"], u["team"], u["moved_sha"]) == ("main", "원본 카드1", "harness", repo["c1"])
    assert u["why"] == "원본 카드1 배경 첫 줄\n둘째 줄" and u["coord"].startswith("하네스 GOAL 표")
    assert len(u["evidence"]) == 2 and u["evidence"][0].startswith("- 세트: ") and "완료 독립 검증" in u["evidence"][1]
    assert u["da"] == f"{H}/OPS-VERDICTS-T.md#§2"
    assert next(u for u in detail(repo, ["ops", "main"])["units"] if u["path"].endswith("card1.md"))["title"] == "ops본 카드1"


def test_refs_record_window_boundary_shas(repo):
    refs = detail(repo, ["main", "ops"])["refs"]
    assert refs == [{"name": "main", "start_sha": repo["c0"], "end_sha": repo["c1"]}, {"name": "ops", "start_sha": repo["c0"], "end_sha": repo["o1"]}]


def test_verdict_sections_return_only_added_sections_with_full_body(repo):
    secs = detail(repo, ["main", "ops"])["verdict_sections"]
    assert [(s["section"], s["title"]) for s in secs] == [("§2", "새 절 — 닫힘"), ("§3", "ops 절 — 닫힘")]
    assert secs[0]["body"] == "새 본문 1\n새 본문 2" and secs[0]["path"] == f"{H}/OPS-VERDICTS-T.md"


def test_merge_bodies_seats_closed_and_appendix(repo):
    d = detail(repo, ["main", "ops"], [repo["c1"]])  # merges 칸 = main 의 창 안 sha 뿐 — ops 의 창 안 커밋(o1) 본문은 안 들어간다
    assert set(d["merge_bodies"]) == {repo["c1"]} and "Verify: 확인" in d["merge_bodies"][repo["c1"]]
    assert detail(repo, ["main", "ops"])["merge_bodies"] == {}
    assert [s["line"] for s in d["seats_closed"]] == ["- 새 좌석 닫힘(ft-nano-close)"]
    assert d["appendix"] == [{"path": f"{H}/BRIEFING-x.md", "text": "브리핑 전문\n"}]


def test_open_rows_cards_requests_holds_breaches(repo):
    infos = detail(repo, ["main", "ops"])["refs"]
    o = mco.collect_open(repo["path"], infos, repo["root"], START, END)
    assert [(c["state"], c["title"], c["tail"]) for c in o["cards"]] == [("진행", "카드2", ["- c", "- d", "- e"])]  # card3 는 ops 에서 닫힘
    assert o["requests"] == [{"id": "R2", "text": "열린 증상 → 접수 · 대기"}]
    assert o["holds"] == [{"path": f"{H}/DA-new.md", "verdict": "HOLD"}]  # DA-old(창 앞)·DA-ok(APPROVE) 제외
    assert o["breaches"] == [{"path": "state/gce/BREACH.md", "text": "# 위반 전문\n"}]


def test_missing_ref_and_malformed_inputs_raise(repo):
    with pytest.raises(MagazineError):
        detail(repo, ["main", "없는/ref"])
    put(repo["path"], f"{H}/REQUEST-LEDGER.md", LEDGER + "| R3 | 깨진 행 |\n")
    sh(repo["path"], "2026-10-07T14:00:00+09:00", "add", "-A")
    sh(repo["path"], "2026-10-07T14:00:00+09:00", "commit", "-q", "-m", "bad ledger")
    infos = mcd.resolve_refs(repo["path"], ["main"], START, END)
    with pytest.raises(MagazineError, match="열 수"):
        mco.collect_open(repo["path"], infos, repo["root"], START, END)


def test_card_without_required_section_raises(repo):
    put(repo["path"], f"{H}/indices/완성/bad.md", "# 인덱스: 배경 없음\n\n## 골좌표\nx\n\n## 상태\n- y\n")
    commit(repo["path"], "2026-10-07T15:00:00+09:00", "bad card")
    with pytest.raises(MagazineError, match="배경"):
        detail(repo, ["main"])


OLD_FORM = "# 인덱스: 옛 형식\n\n## 배경\n옛 배경\n"  # 상태·골좌표 절이 없는 옛 카드 (제목·배경만)


def add_done_cards(repo: dict, *, old: int, good: int) -> None:
    for i in range(old):
        put(repo["path"], f"{H}/indices/완성/old-form{i}.md", OLD_FORM)
    for i in range(good):
        put(repo["path"], f"{H}/indices/완성/good{i}.md", card(f"정상{i}", CLOSED))
    commit(repo["path"], "2026-10-07T15:00:00+09:00", "cards")


def test_m1_without_opt_in_old_form_card_still_raises(repo, monkeypatch):  # M1
    monkeypatch.delenv(shape.MODE_ENV, raising=False)
    add_done_cards(repo, old=1, good=0)
    with pytest.raises(MagazineError, match="상태"):
        detail(repo, ["main"])


def test_m2_report_mode_moves_old_form_cards_to_malformed_and_logs_error(repo, monkeypatch, capsys):  # M2
    monkeypatch.setenv(shape.MODE_ENV, "report")
    add_done_cards(repo, old=1, good=2)
    d = detail(repo, ["main"])
    assert len(d["units"]) == 3 and not any("old-form" in u["path"] for u in d["units"])  # card1 + good0 + good1
    sha = sh(repo["path"], "2026-10-07T16:00:00+09:00", "log", "-1", "--format=%H", "--", f"{H}/indices/완성/old-form0.md")
    assert d["malformed"] == [{"path": f"{H}/indices/완성/old-form0.md", "team": "harness", "missing": ["상태", "골좌표"], "moved_sha": sha, "ref": "main"}]
    err = capsys.readouterr().err.splitlines()
    assert err == [f"ERROR magazine: 형식 미달 카드 {H}/indices/완성/old-form0.md (빠진 절: 상태, 골좌표)"]


def test_m3_report_mode_with_only_good_cards_matches_default_output(repo, monkeypatch, capsys):  # M3
    add_done_cards(repo, old=0, good=2)
    monkeypatch.delenv(shape.MODE_ENV, raising=False)
    base = detail(repo, ["main"])
    monkeypatch.setenv(shape.MODE_ENV, "report")
    got = detail(repo, ["main"])
    assert got["malformed"] == [] and base["malformed"] == [] and got == base
    assert capsys.readouterr().err == ""


def test_m4_unknown_mode_value_raises_even_without_old_cards(repo, monkeypatch):  # M4
    monkeypatch.setenv(shape.MODE_ENV, "reprot")
    with pytest.raises(MagazineError, match="알 수 없는 값"):
        detail(repo, ["main"])


def test_m5_blob_read_failure_raises_even_in_report_mode(repo, monkeypatch):  # M5
    monkeypatch.setenv(shape.MODE_ENV, "report")

    def boom(*_a, **_k):
        raise MagazineError("git show 실패")

    monkeypatch.setattr(mcd, "blob", boom)
    with pytest.raises(MagazineError, match="git show 실패"):
        detail(repo, ["main"])


def fake_gh(tmp_path: Path, monkeypatch, body: str) -> None:
    gh = tmp_path / "bin" / "gh"
    gh.parent.mkdir()
    gh.write_text(f"#!/bin/sh\n{body}\n", encoding="utf-8")
    gh.chmod(gh.stat().st_mode | stat.S_IEXEC)
    monkeypatch.setenv("PATH", f"{gh.parent}{os.pathsep}{os.environ['PATH']}")


def test_last_comments_takes_last_body_or_null_and_failures_raise(tmp_path, monkeypatch):
    fake_gh(tmp_path, monkeypatch, """case "$*" in
  *" 880 "*) printf '%s' '{"comments":[{"body":"첫"},{"body":"마지막 전문\\n둘째 줄"}]}' ;;
  *" 881 "*) printf '%s' '{"comments":[]}' ;;
  *) echo boom >&2; exit 1 ;;
esac""")
    assert mgh.last_comments("o/r", [880, 881]) == {"880": "마지막 전문\n둘째 줄", "881": None}
    with pytest.raises(MagazineError, match="rc=1"):
        mgh.last_comments("o/r", [999])


def test_collect_assembles_detail_with_the_fixture_shape(repo, tmp_path, monkeypatch):
    fake_gh(tmp_path, monkeypatch, """echo '{"comments":[{"body":"닫는 증거"}]}'""")
    mbox = tmp_path / "mbox.jsonl"
    head = {"ts": "2026-10-06T10:00:00", "from": "byz-cfo-master-claude#3", "to": "x#1", "body": "창 앞을 덮는 첫 줄"}  # collect_decisions 도 창 앞 덮음을 검사한다
    mbox.write_text("\n".join(json.dumps(r, ensure_ascii=False) for r in (head, {"ts": "2026-10-07T09:00:00", "from": "byz-planner-m#7", "to": "x#1", "body": "[a->b] 판정 354 본문"})), encoding="utf-8")
    m = {"git": {"main": {}, "merges": [{"sha": repo["c1"]}], "docs": []}, "gh": {"issues_opened": [], "issues_closed": [{"number": 880}]}, "mbox": {"verdicts": [], "mbox": {}, "seats": {}}}
    monkeypatch.setattr(magazine_collect, "collect_git", lambda *a: m["git"])
    monkeypatch.setattr(magazine_collect, "collect_gh", lambda *a: m["gh"])
    monkeypatch.setattr(magazine_collect, "collect_mbox", lambda *a: m["mbox"])
    monkeypatch.setenv("MAGAZINE_REFS", "main,ops")
    model = magazine_collect.collect("2026-10-08", repo=repo["path"], gh_repo="o/r", mailbox=mbox, byz_root=repo["root"])
    got, fx = model["detail"], copy.deepcopy(DETAIL_FIXTURE)
    assert list(got) == list(fx)
    for key in ("refs", "units", "verdict_sections", "decisions", "seats_closed", "appendix"):
        assert set(got[key][0]) == set(fx[key][0]), key
    assert set(got["open"]) == set(fx["open"]) and all(set(got["open"][k][0]) == set(fx["open"][k][0]) for k in fx["open"] if fx["open"][k])  # 빈 칸(malformed_requests)은 키만 대조
    assert list(got["merge_bodies"]) == [repo["c1"]]
    assert got["issue_evidence"] == {"880": "닫는 증거"} and got["decisions"][0]["n"] == 354
