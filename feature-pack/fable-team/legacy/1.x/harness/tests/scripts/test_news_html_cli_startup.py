"""r510 — 뉴스 갈래 상한의 CLI 기동 고정비 = 실측 p90 ⓐ~ⓔ + 발행 지연 알림 ⓕ (가짜 opencode·가짜 Slack · 외부 호출 0 · GIT_* env 0).
실행: python3 -m pytest tests/scripts/test_news_html_cli_startup.py -q
"""
import json
import re
import sys
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_ft_news_html import DATA, NOW, calls, oc, slack  # noqa: E402,F401 — 픽스처 재사용(oc·slack)

import ft_news_html as fh  # noqa: E402
import ft_news_html_render as fr  # noqa: E402

SUMMARY = '"summary":'


def _rows(_oc) -> Path:
    return Path(fh.os.environ["FT_NEWS_STARTUP_LOG"])  # oc 픽스처가 tmp 로 돌려 둔 기동 기록


def _seed(path: Path, vals: list) -> None:
    path.write_text("".join(f"2026-10-20 03:00:{i:02d}\tsummary\t{v}\n" for i, v in enumerate(vals)), encoding="utf-8")


def _summary_calls(log: Path) -> int:
    return sum(SUMMARY in c[-1].split("출력 스키마:")[1].splitlines()[0] for c in calls(log))


# ── ⓐ 기록 없음(·3개 미만) = 잠정 3.5 ──────────────────────────────────

def test_a_no_records_keeps_provisional_3_5(oc):  # noqa: F811 — 가져온 픽스처
    small = fr.build_prompt({"teams": ["팀"]}, "teams")
    assert fr.fixed_s() == 3.5 and fr.cap_s(small, "teams", fr.fixed_s()) == 3.5 + 7 * 4
    _seed(_rows(oc), [30, 40])
    assert fr.fixed_s() == 3.5  # 표본 2개 = 아직 잠정


# ── ⓑ 기록 10개 → 고정비 = p90 · 옛 3.5 로는 넘던 갈래가 성공 ─────────────

def test_b_p90_of_records_raises_cap_and_slow_part_succeeds(tmp_path, oc, monkeypatch):  # noqa: F811 — 가져온 픽스처
    _, log = oc
    _seed(_rows(oc), [0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, ">5.0"])  # 시간 초과 기록 = 그 상한값(하한)
    assert fr.fixed_s() == 4.5  # nearest-rank p90 = 정렬 9번째
    monkeypatch.setattr(fr, "UNIT_S", 0.1)  # 시험 시간 줄임: summary 상한 = 고정비 + 0.1 × 3
    monkeypatch.setenv("FAKE_OC_SLEEP", "4.2")  # 부하 모사 — 요약 갈래만 기동 4.2초
    monkeypatch.setenv("FAKE_OC_SLOW_MATCH", SUMMARY)
    monkeypatch.setenv("FT_NEWS_FIXED_S", "3.5")  # 되돌림 스위치 = 옛 값 → 상한 3.8 < 4.2 = 두 시도 다 초과
    with pytest.raises(fr.NewsHtmlError, match="summary 상한 4s 초과"):
        fh.run_files(DATA, tmp_path / "old", NOW)
    assert _summary_calls(log) == 2
    monkeypatch.delenv("FT_NEWS_FIXED_S")
    log.unlink()
    _seed(_rows(oc), [0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, ">5.0"])
    html_p, _ = fh.run_files(DATA, tmp_path / "new", NOW)  # 상한 4.5 + 0.3 = 4.8 > 4.2
    assert html_p.is_file() and _summary_calls(log) == 1


# ── ⓒ p90 이 천장 이상 → 상한 70 + WARN ───────────────────────────────

def test_c_p90_at_or_over_ceiling_caps_70_and_warns(tmp_path, oc, capsys):  # noqa: F811 — 가져온 픽스처
    _seed(_rows(oc), [">70.0"] * 9 + [12])
    assert fr.fixed_s() == 70 and fr.cap_s(fr.build_prompt({}, "teams"), "teams", fr.fixed_s()) == 70
    fh.run_files(DATA, tmp_path, NOW)
    cap = capsys.readouterr()
    assert "WARN 기동 고정비 p90 70.0s ≥ 천장 70s" in cap.err and "fixed=70.0s" in cap.out


# ── ⓓ 시도마다 1줄 · 최근 20 · 시간 초과 = «>상한» · 쓰기 실패 = WARN ────────

def test_d_each_attempt_one_row_keep_20(tmp_path, oc, capsys):  # noqa: F811 — 가져온 픽스처
    rows = _rows(oc)
    _seed(rows, [9] * 19)
    fh.run_files(DATA, tmp_path, NOW)
    got = rows.read_text(encoding="utf-8").splitlines()
    assert len(got) == 20 and sum(r.endswith("\t9") for r in got) == 16
    new = got[-4:]
    assert sorted(r.split("\t")[1] for r in new) == sorted(fr.PARTS)
    assert all(re.fullmatch(r"\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\t\w+\t\d+\.\d", r) for r in new)
    assert re.search(r"ft-news-html: 만듦 \S+ secs=.* fixed=9\.0s model=", capsys.readouterr().out)


def test_d_timeout_records_cap_as_lower_bound(tmp_path, oc, monkeypatch):  # noqa: F811 — 가져온 픽스처
    monkeypatch.setattr(fr, "UNIT_S", 0.1)
    monkeypatch.setenv("FT_NEWS_FIXED_S", "1.5")  # summary 상한 1.8
    monkeypatch.setenv("FAKE_OC_SLEEP", "3")
    monkeypatch.setenv("FAKE_OC_SLOW_MATCH", SUMMARY)
    with pytest.raises(fr.NewsHtmlError, match="summary 상한"):
        fh.run_files(DATA, tmp_path / "o", NOW)
    got = _rows(oc).read_text(encoding="utf-8").splitlines()
    assert [r.split("\t")[2] for r in got if "\tsummary\t" in r] == [">1.8", ">1.8"]  # 1차·재시도 = 하한값 2줄


def test_d_record_write_failure_warns_and_publish_continues(tmp_path, oc, monkeypatch, capsys):  # noqa: F811 — 가져온 픽스처
    (tmp_path / "blocker").write_text("", encoding="utf-8")
    monkeypatch.setenv("FT_NEWS_STARTUP_LOG", str(tmp_path / "blocker" / "startup.tsv"))  # 부모가 파일 = 못 씀
    html_p, _ = fh.run_files(DATA, tmp_path / "o", NOW)
    assert html_p.is_file() and "WARN 기동 기록 못 씀 — 발행은 계속" in capsys.readouterr().err


# ── ⓔ 재시도 포함 총 마감 넘는 실행 0 (높은 고정비여도) ──────────────────

def test_e_total_deadline_holds_even_with_high_fixed(tmp_path, oc, monkeypatch):  # noqa: F811 — 가져온 픽스처
    _, log = oc
    _seed(_rows(oc), [60] * 10)
    monkeypatch.setattr(fr, "DEADLINE_S", 3)
    monkeypatch.setenv("FAKE_OC_SLEEP", "6")
    monkeypatch.setenv("FAKE_OC_SLOW_MATCH", SUMMARY)
    t0 = time.monotonic()
    with pytest.raises(fr.NewsHtmlError, match="summary 상한 3s 초과"):
        fh.run_files(DATA, tmp_path / "o", NOW)
    assert time.monotonic() - t0 < 3 + 1.5 and _summary_calls(log) == 1  # 재시도 시간 없음 = 1회


# ── ⓕ 지도 실패 연속 3틱 → 고정 문구 지연 글 1 · 4틱째 0 · 성공 → 복구 줄 ──────

def test_f_delay_notice_once_per_stall_then_recovery_line(tmp_path, oc, slack, monkeypatch):  # noqa: F811 — 가져온 픽스처
    reply, _ = oc
    good = reply.read_text(encoding="utf-8")
    monkeypatch.setattr(fh, "build", lambda *a: DATA)
    state, news = tmp_path / "state", tmp_path / "news"
    args = (tmp_path, state, tmp_path, "x.md", news)
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-19 09:00")
    assert fh.tick(*args, "a", "b")[0] == 0 and len(slack.msgs) == 1
    link = json.loads((state / "html.json").read_text())["link"]
    reply.write_text("JSON 아님", encoding="utf-8")
    for n, at in enumerate(("09:12", "09:24", "09:36", "09:48"), 1):  # r907 r2: 게시 최소 간격 10분 — 틱 간격을 그보다 벌린다
        monkeypatch.setenv("FT_NEWS_NOW", f"2026-10-19 {at}")
        assert fh.tick(*args, "b", "c") == (1, "지도 만들기 실패")
        assert len(slack.msgs) == (1 if n < 3 else 2), n  # 3틱째 1번 · 4틱째 추가 0
    text = slack.msgs[1]["text"]
    assert text.startswith("뉴스 지연 — 사유: 지도 만들기 실패 — 발행 0: ")  # 고정 문구 · 판단·요약 0
    assert re.search(rf"· 마지막 판 09:00\({re.escape(link)}\) · 부하 \d+\.\d\d$", text)
    assert len(text.split("사유: ")[1].split(" · 마지막 판")[0]) <= 120
    reply.write_text(good, encoding="utf-8")
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-19 10:00")
    assert fh.tick(*args, "b", "c")[0] == 0
    assert [m["text"] for m in slack.msgs[2:]][-1] == "뉴스 복구 10:00 · 지연 60분"  # r907 r2: 틱 간격 12분(게시 간격 10분) and len(slack.msgs) == 4  # 지도 1 + 복구 1
    assert not (state / "news-delay.json").exists()


def test_f_short_stall_below_threshold_is_silent(tmp_path, oc, slack, monkeypatch):  # noqa: F811 — 가져온 픽스처
    reply, _ = oc
    good = reply.read_text(encoding="utf-8")
    monkeypatch.setattr(fh, "build", lambda *a: DATA)
    state = tmp_path / "state"
    args = (tmp_path, state, tmp_path, "x.md", tmp_path / "news")
    reply.write_text("JSON 아님", encoding="utf-8")
    for at in ("09:00", "09:06"):
        monkeypatch.setenv("FT_NEWS_NOW", f"2026-10-19 {at}")
        assert fh.tick(*args, "a", "b")[0] == 1
    reply.write_text(good, encoding="utf-8")
    monkeypatch.setenv("FT_NEWS_NOW", "2026-10-19 09:12")
    assert fh.tick(*args, "a", "b")[0] == 0 and len(slack.msgs) == 1  # 지연 글·복구 줄 0 · 지도만
    assert not (state / "news-delay.json").exists()
