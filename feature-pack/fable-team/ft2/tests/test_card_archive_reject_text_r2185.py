"""r2185 card_archive 거절 글 시험 (카드 반례 ②~⑦ · ① = test_card_archive_r2177.py 재실행 · 변이 M1~M3 은 사본에서).
대역 = test_card_archive_r2177.py 의 임시 bare 원격 + 임시 루트(그 모듈의 world · run · rejected · archived 를 그대로 쓴다) · 실 리포·실 push·외부 호출 0 · sleep 0.
기준판 = 팩 main d883d11572 → ② ③ ④ ⑤ ⑥ Red(통과 줄 예시 · «경로» 0) · ⑦ 은 기준판에서도 PASS(동작 불변).
"""
import importlib.util
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location("ca2177_world_r2185", str(Path(__file__).with_name("test_card_archive_r2177.py")))
t77 = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(t77)
base, kw, CARD, TO = t77.base, t77.kw, t77.CARD, t77.TO
EXAMPLE = "통과 줄 예시 «닫힘 — r9-x — 버림»"
TO_EXAMPLE = "design/teams/<팀>/indices/대기/<카드>.md"


def verdict_rejected(w, capsys, mp):
    before = base.heads(w)
    rc, out, _ = t77.run(w, capsys, mp)
    t77.rejected(w, rc, out, before, "r9-x")
    assert EXAMPLE in out and "한 낱말만" in out, out
    assert "(닫힘|CLOSE)" not in out and "닫힘|CLOSE" not in out, out
    return out


def test_2_literal_bar_line_rejected_with_example(tmp_path, monkeypatch, capsys):   # ②
    w = t77.world(tmp_path, monkeypatch, lines=("닫힘|CLOSE — r9-x — 버림",))
    verdict_rejected(w, capsys, monkeypatch)


def test_3_no_drop_line_same_text(tmp_path, monkeypatch, capsys):                   # ③ = ② 와 같은 글
    w = t77.world(tmp_path, monkeypatch, lines=("- 보류",))
    out3 = verdict_rejected(w, capsys, monkeypatch)
    w2 = t77.world(tmp_path / "b", monkeypatch, lines=("닫힘|CLOSE — r9-x — 버림",))
    assert verdict_rejected(w2, capsys, monkeypatch) == out3


def test_2c_example_copied_into_verdict_archived(tmp_path, monkeypatch, capsys):    # 확인칸 ⓒ 예시를 그대로 옮기면 통과
    w = t77.world(tmp_path, monkeypatch, lines=("닫힘|CLOSE — r9-x — 버림",))
    out = verdict_rejected(w, capsys, monkeypatch)
    line = out.split("통과 줄 예시 «", 1)[1].split("»", 1)[0]
    w.da.write_text(t77.verdict(line), encoding="utf-8")
    rc, out, _ = t77.run(w, capsys, monkeypatch)
    t77.archived(w, out, rc)


@pytest.mark.parametrize("to", ["r8-y", CARD % "대기", t77.IDX + "/대기/r7-z.md"])   # ④ 이름만 · ⑤ 자기 자신 · 없음
def test_4_5_to_rejected_with_path_example(tmp_path, monkeypatch, capsys, to):
    w = t77.world(tmp_path, monkeypatch, ledger=False)
    w.commit("byz", {TO: "# r8\n"}, t77.OPS)
    before = base.heads(w)
    rc, out, _ = t77.run(w, capsys, monkeypatch, "--to", to)
    t77.rejected(w, rc, out, before, "--to %s " % to)
    assert "카드 이름이 아니라 경로" in out and TO_EXAMPLE in out, out


def test_6_help_to_line_says_path(monkeypatch, capsys):
    monkeypatch.setenv("COLUMNS", "400")
    mod = kw._mod(Path(__file__).resolve().parents[1] / "adapters" / "pi" / "card_archive.py", "ca2185_help")
    with pytest.raises(SystemExit) as exc:
        mod.main(["--help"])
    out = capsys.readouterr().out
    line = next(x for x in out.splitlines() if x.strip().startswith("--to"))
    assert exc.value.code == 0 and "받는 카드의 경로" in line and TO_EXAMPLE in line, out


@pytest.mark.parametrize("word", ["닫힘", "CLOSE"])
@pytest.mark.parametrize("end", ["버림", "쓸모 없음"])
def test_7_pass_forms_unchanged(tmp_path, monkeypatch, capsys, word, end):            # ⑦ 통과 4꼴
    w = t77.world(tmp_path, monkeypatch, lines=("%s — r9-x — %s" % (word, end),))
    rc, out, _ = t77.run(w, capsys, monkeypatch)
    t77.archived(w, out, rc)
    assert len(out.splitlines()) == 1, out                                         # 기준판 = ARCHIVED 1줄


def test_7_to_path_and_other_rejects_unchanged(tmp_path, monkeypatch, capsys):        # ⑦ --to 경로 통과 · 다른 거절 글 그대로
    w = t77.world(tmp_path, monkeypatch, ledger=False)
    w.commit("byz", {TO: "# r8\n"}, t77.OPS)
    before = base.heads(w)
    rc, out, _ = t77.run(w, capsys, monkeypatch)
    assert (rc, out) == (1, "REJECT 열린 일 — --to <받는 카드> r9") and base.heads(w) == before
    rc, out, _ = t77.run(w, capsys, monkeypatch, "--to", TO)
    t77.archived(w, out, rc)
    w2 = t77.world(tmp_path / "b", monkeypatch, lines=(t77.LAND, t77.DROP))
    before = base.heads(w2)
    rc, out, _ = t77.run(w2, capsys, monkeypatch)
    assert (rc, out) == (1, "REJECT 착지한 카드 — card_stage --da 로 완성 (§2 r9-x)") and base.heads(w2) == before
