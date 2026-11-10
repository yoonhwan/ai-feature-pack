"""R217 뉴스 발행 → planner 요약 1통 (판정 1825). 원장 뉴스 시험의 격리 픽스처(임시 git 저장소·발행 대역·mbox 대역)를 그대로 쓴다 — 실 Slack·실 mbox 0.

발행 대역(STUB)은 실 발행 도구처럼 성공 줄(ts·channel·permalink)을 stdout 으로 낸다 — 요약 재료는 이번 호출의 stdout 뿐(파일 인계 0). 실행:
env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY python3 -m pytest tests/scripts/test_news_planner_digest.py -q
"""
import json
import logging

import test_ft_news_ledger as base  # noqa: I001 — 먼저 불러야 scripts/fable-team-bin 이 sys.path 에 오른다
from test_ft_news_ledger import REAL, ROW_OLD, commit, news_files

import ft_news_digest as nd  # noqa: E402
import ft_news_post as npost  # noqa: E402
import ft_news_ledger as nl  # noqa: E402

env = base.env
DAY = "2026-10-15"
STUB = """#!/usr/bin/env bash
echo "$1" >> "$FT_STUB_LOG"
[ "${FT_STUB_RC:-0}" = 0 ] || exit "$FT_STUB_RC"
n=$(wc -l < "$FT_STUB_LOG" | tr -d " ")
[ -n "$FT_STUB_QUOTE" ] && { echo "ft-news-publish: 발행 완료 ts=1.1 channel=C9 permalink=https://quoted"; echo "ft-news-publish: 같은 내용 — 발행 0"; exit 0; }
[ -n "$FT_STUB_GARBAGE" ] && { echo "뭔가 이상한 출력"; exit 0; }
[ -n "$FT_STUB_NOPOST" ] && { echo "ft-news-publish: 같은 내용 — 발행 0"; exit 0; }
echo "ft-news-publish: 발행 완료 ts=1900000001.00010$n channel=C1 permalink=${FT_STUB_LINK:-https://w.slack.com/archives/C1/p$n}"
"""
ROW_DONE = "|  | 가입 메일 템플릿 13종 | 코드 | 완료 — 재확인 |  |"
REC = {"ts": "1900000001.000101", "channel": "C1", "permalink": "https://w.slack.com/archives/C1/p1"}
SEATS = '{"_master": "planner#9", "_hil_route": "byz-planner-master-claude#50"}'


def setup(env, monkeypatch, seats: str = SEATS):
    repo, root, tmp = env
    (root / ".fable-team" / "seats-planner.json").write_text(seats, encoding="utf-8")
    (tmp / "pub.sh").write_text(STUB, encoding="utf-8")
    monkeypatch.setenv("FT_NEWS_NOW", f"{DAY} 15:00")
    for k in ("FT_STUB_NOPOST", "FT_STUB_GARBAGE", "FT_STUB_LINK", "FT_STUB_QUOTE"):
        monkeypatch.delenv(k, raising=False)
    monkeypatch.delenv("FT_DECISION_COUNT", raising=False)
    commit(repo, REAL)
    nl.main(["run"])  # 기준선
    return repo, root, tmp


def sends(tmp) -> list[str]:
    f = tmp / "mbox.log"
    return [ln for ln in f.read_text(encoding="utf-8").splitlines() if ln.startswith("send ") and "ft-news-digest" in ln] if f.exists() else []  # 본문이 여러 줄이라 «send » 로 시작하는 줄 = 호출 1회 · 요약 쪽지만 센다(정지 경보 등 다른 발신자 제외)


def fake_mbox(root, tmp, rc: int = 0) -> None:
    """본문(여러 줄)을 통째로 한 파일에 쌓는 대역 — 호출 1회 = 파일 하나."""
    (root / ".fable-team" / "comm" / "mbox.sh").write_text(
        f'#!/usr/bin/env bash\necho "$@" >> "$FT_MBOX_LOG"\nprintf "%s" "$4" > "{tmp}/body-$(ls {tmp}/body-*.txt 2>/dev/null | wc -l | tr -d " ").txt"\nexit {rc}\n', encoding="utf-8")


def bodies(tmp) -> list[str]:
    return [t for p in sorted(tmp.glob("body-*.txt")) if (t := p.read_text(encoding="utf-8")).startswith("[뉴스 요약")]


def publish_change(repo, text=None) -> None:
    commit(repo, text or REAL.replace(ROW_OLD, ROW_DONE))
    assert nl.main(["run"]) == 0


def test_a_ledger_commit_publishes_once_and_sends_one_six_line_note_with_link(env, monkeypatch):  # ⓐ
    repo, root, tmp = setup(env, monkeypatch)
    fake_mbox(root, tmp)
    publish_change(repo)
    [body] = bodies(tmp)
    lines = body.splitlines()
    assert len(sends(tmp)) == 1 and "byz-planner-master-claude#50 ft-news-digest" in sends(tmp)[0]
    assert len(lines) == 6 and len(body.encode()) <= 700
    assert lines[0] == "[뉴스 요약 15:00] https://w.slack.com/archives/C1/p1"
    assert lines[2].startswith("한 일:") and "완료 — 재확인" in lines[2]


def test_b_same_content_rerun_publishes_and_sends_nothing(env, monkeypatch):  # ⓑ
    repo, root, tmp = setup(env, monkeypatch)
    fake_mbox(root, tmp)
    publish_change(repo)
    n_news, n_sends = len(news_files(root)), len(sends(tmp))
    assert nl.main(["run"]) == 0
    assert (len(news_files(root)), len(sends(tmp))) == (n_news, n_sends)


def test_c_publish_failure_sends_nothing_and_writes_no_last_post(env, monkeypatch):  # ⓒ
    repo, root, tmp = setup(env, monkeypatch)
    fake_mbox(root, tmp)
    monkeypatch.setenv("FT_STUB_RC", "1")
    commit(repo, REAL.replace(ROW_OLD, ROW_DONE))
    assert nl.main(["run"]) == 1
    assert sends(tmp) == []


def test_d_two_parts_make_one_note_marked_with_part_count(env, monkeypatch):  # ⓓ
    repo, root, tmp = setup(env, monkeypatch)
    fake_mbox(root, tmp)
    big = REAL.replace(ROW_OLD, ROW_DONE) + "".join(f"- 판정 {3000 + i} 반영 — {'가' * 90}\n" for i in range(40))
    publish_change(repo, big)
    assert len(news_files(root)) >= 2 and len(sends(tmp)) == 1
    head = bodies(tmp)[0].splitlines()[0]
    assert f"(판 {len(news_files(root))}개)" in head and f"/p{len(news_files(root))} " in head  # 마지막 판의 링크 1개


def test_e_draft_mode_sends_nothing(env, monkeypatch):  # ⓔ
    repo, root, tmp = setup(env, monkeypatch)
    fake_mbox(root, tmp)
    monkeypatch.setenv("FT_NEWS_MODE", "draft")
    publish_change(repo)
    assert sends(tmp) == []


def test_f_status_only_publish_sends_one_note_with_no_ledger_change(env, monkeypatch):  # ⓕ
    repo, root, tmp = setup(env, monkeypatch)
    fake_mbox(root, tmp)
    monkeypatch.setenv("FT_NEWS_STATUS_INTERVAL", "1800")
    snap = root / ".fable-team" / "state" / "board" / DAY
    snap.mkdir(parents=True)
    team = {"label": "하네스", "seats": {"s1": {"working": False}}, "stalled": [], "progress": {}, "queue": []}
    (snap / "145500-abc.json").write_text(json.dumps({"teams": [team]}), encoding="utf-8")
    assert nl.main(["run"]) == 0
    [body] = bodies(tmp)
    lines = body.splitlines()
    assert len(sends(tmp)) == 1 and lines[2] == "한 일: 원장 변화 0" and lines[5] == "팀 상태: 쉬는 팀 1 · 정지 팀 없음"


def test_g_decision_line_missing_tool_vs_present_tool(env, monkeypatch):  # ⓖ
    repo, root, tmp = setup(env, monkeypatch)
    fake_mbox(root, tmp)
    publish_change(repo)
    assert bodies(tmp)[0].splitlines()[1] == "(건수 도구 미설치 — R214)"
    tool = tmp / "count.sh"
    tool.write_text("#!/usr/bin/env bash\necho '결정 대기 3건 · 스크립트 1건'\n", encoding="utf-8")
    assert nd.decision_line(root) == "(건수 도구 미설치 — R214)"
    monkeypatch.setenv("FT_DECISION_COUNT", str(tool))
    assert nd.decision_line(root) == "결정 대기 3건 · 스크립트 1건"
    tool.write_text("#!/usr/bin/env bash\nexit 4\n", encoding="utf-8")
    assert nd.decision_line(root) == "(건수 실패 rc=4)"


def test_h_mbox_failure_keeps_publish_rc_zero_and_logs_one_error(env, monkeypatch, caplog):  # ⓗ
    repo, root, tmp = setup(env, monkeypatch)
    fake_mbox(root, tmp, rc=1)
    commit(repo, REAL.replace(ROW_OLD, ROW_DONE))
    with caplog.at_level(logging.ERROR, logger="ft_news_ledger"):
        assert nl.main(["run"]) == 0
    errs = [r for r in caplog.records if "요약 쪽지 실패" in r.getMessage()]
    assert len(errs) == 1 and len(news_files(root)) == 1


def test_i_same_ts_twice_sends_once(env, monkeypatch):  # ⓘ
    repo, root, tmp = setup(env, monkeypatch)
    fake_mbox(root, tmp)
    publish_change(repo)
    state = root / ".fable-team" / "state" / "news-ledger"
    assert nd.send(root, state, nl.news_now(), [], [], None, 1, REC) is False
    assert len(sends(tmp)) == 1


def test_j_oversized_material_is_cut_and_keeps_six_lines(env, monkeypatch):  # ⓙ
    repo, root, tmp = setup(env, monkeypatch)
    fake_mbox(root, tmp)
    long = "가" * 400
    diff = [("바뀜", f"{long} {i}: 진행 → 완료 {long}") for i in range(5)]
    blocks = [("*팀 작업* — x", [f"• 팀{i} — 진행 {long}" for i in range(5)]), ("*오빠 할 일*", [f"• {long}", f"• {long}"])]
    assert nd.send(root, root / ".fable-team" / "state" / "news-ledger", nl.news_now(), diff, blocks, None, 1, {"ts": "9.9", "channel": "C1", "permalink": None}) is True
    body = bodies(tmp)[-1]
    assert len(body.splitlines()) == 6 and len(body.encode()) <= nd.MAX_BYTES and body.splitlines()[0].endswith("ts=9.9 ch=C1")


def test_k_kit_copies_match_tracked_sources():  # ⓚ
    from pathlib import Path
    root = Path(__file__).resolve().parents[3]
    for name in ("ft_news_digest.py", "ft_news_ledger.py", "ft_news_publish.py", "ft_news_post.py"):
        a, b = root / "harness" / "bin" / name, root / "harness" / "kit" / "fable-team" / "bin" / name
        assert a.read_bytes() == b.read_bytes(), name


def test_l_mutation_without_sent_ts_check_sends_twice(env, monkeypatch):  # ⓛ 변이: sent.ts 비교를 지우면 ⓘ 가 깨진다
    repo, root, tmp = setup(env, monkeypatch)
    fake_mbox(root, tmp)
    publish_change(repo)
    monkeypatch.setattr(nd, "_already_sent", lambda f, ts: False)
    state = root / ".fable-team" / "state" / "news-ledger"
    assert nd.send(root, state, nl.news_now(), [], [], None, 1, REC) is True
    assert len(sends(tmp)) == 2


def test_m_stale_receipt_file_of_today_does_not_make_a_note_when_this_call_posted_nothing(env, monkeypatch):  # H1: 낡은 날짜 파일 + 이번 발행 0
    repo, root, tmp = setup(env, monkeypatch)
    fake_mbox(root, tmp)
    old = root / ".fable-team" / "state" / "news-publish" / DAY
    old.mkdir(parents=True)
    (old / "last-post.json").write_text(json.dumps({"ts": "old.1", "channel": "C1", "permalink": "https://old"}), encoding="utf-8")
    monkeypatch.setenv("FT_STUB_NOPOST", "1")
    publish_change(repo)
    assert sends(tmp) == [] and "https://old" not in "".join(bodies(tmp))


def test_n_unreadable_publish_stdout_logs_error_sends_nothing_and_keeps_rc_zero(env, monkeypatch, caplog):  # H1: 해석 실패
    repo, root, tmp = setup(env, monkeypatch)
    fake_mbox(root, tmp)
    monkeypatch.setenv("FT_STUB_GARBAGE", "1")
    commit(repo, REAL.replace(ROW_OLD, ROW_DONE))
    with caplog.at_level(logging.ERROR, logger="ft_news_ledger"):
        assert nl.main(["run"]) == 0
    assert sends(tmp) == [] and len([r for r in caplog.records if "요약 재료 없음 — 발행은 성공" in r.getMessage()]) == 1
    assert baseline_moved(root)


def test_o_long_link_is_replaced_by_ts_and_channel_head_within_120_chars_and_all_six_lines_700b(env, monkeypatch):  # H3
    repo, root, tmp = setup(env, monkeypatch)
    fake_mbox(root, tmp)
    monkeypatch.setenv("FT_STUB_LINK", "https://w.slack.com/archives/C1/p" + "9" * 150)
    publish_change(repo)
    [body] = bodies(tmp)
    lines = body.splitlines()
    assert len(lines) == 6 and all(len(ln) <= nd.MAX_LINE for ln in lines) and len(body.encode()) <= nd.MAX_BYTES
    assert lines[0] == "[뉴스 요약 15:00] ts=1900000001.000101 ch=C1"


def baseline_moved(root) -> bool:
    return base.baseline(root) != ""


OK_LINE = "ft-news-publish: 발행 완료 ts=1900000001.000101 channel=C1 permalink=https://w.slack.com/archives/C1/p1"
SAME = "ft-news-publish: 같은 내용 — 발행 0"


def test_p_quoted_success_line_before_a_final_same_content_line_is_not_a_post(env, monkeypatch):  # DA r2 (a)
    assert npost._receipt(f"{OK_LINE}\n{SAME}\n") == {}
    repo, root, tmp = setup(env, monkeypatch)
    fake_mbox(root, tmp)
    monkeypatch.setenv("FT_STUB_QUOTE", "1")
    publish_change(repo)
    assert sends(tmp) == []


def test_q_same_content_line_then_real_success_line_is_the_success_receipt():  # DA r2 (b)
    assert npost._receipt(f"{SAME}\n{OK_LINE}\n") == {"ts": "1900000001.000101", "channel": "C1", "permalink": "https://w.slack.com/archives/C1/p1"}
    assert npost._receipt(OK_LINE.replace("https://w.slack.com/archives/C1/p1", "-")) ["permalink"] is None


def test_r_two_success_lines_or_bad_format_or_embedded_line_is_unreadable():  # DA r2 (c) + ④ 형식 검증
    assert npost._receipt(f"{OK_LINE}\n{OK_LINE.replace('101', '102')}\n") is None
    assert npost._receipt(OK_LINE.replace("ts=1900000001.000101", "ts=abc")) is None
    assert npost._receipt(OK_LINE.replace("channel=C1", "channel=c1")) is None
    assert npost._receipt(f"> {OK_LINE}\n") is None and npost._receipt(f"{OK_LINE} 끝\n") is None
    assert npost._receipt("") is None
