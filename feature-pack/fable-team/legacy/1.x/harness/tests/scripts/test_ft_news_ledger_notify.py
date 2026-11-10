"""R139 원장 갱신 알림 — «원장 본문에 번호 없는 오빠 결정»만 · 한 틱 1통(묶음) · 첫 실행 기준선 (planner#40 요청).

시각 칸은 쓰지 않는다(판정표 시계가 실제와 어긋남). 격리 임시 git 저장소 + mbox 호출 기록 스텁 — 실제 송신 0.
실행: env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR python3 -m pytest tests/scripts/test_ft_news_ledger_notify.py -q
"""
import logging
import re

import test_ft_news_ledger as base  # noqa: I001 — 먼저 불러야 scripts/fable-team-bin 이 sys.path 에 오른다
from test_ft_news_ledger import REAL, ROW_NEW, ROW_OLD, commit, news_files

import ft_news_ledger as nl  # noqa: E402
import ft_news_ledger_notify as nn  # noqa: E402

env = base.env  # 원장 뉴스 시험의 격리 픽스처를 그대로 쓴다

LEDGER_WITH_1500 = REAL + "\n- 판정 1500 반영 — 오빠 결정을 적었다\n"


def verdict_rows(root, rows: list[tuple[int, str]]) -> None:
    d = root / ".worktrees" / "wt" / "design" / "planner"
    d.mkdir(parents=True, exist_ok=True)
    (d.parent / "TEAMS.md").write_text("| 팀 | 폴더 | 팀장 | 상태 |\n|---|---|---|---|\n| planner | `design/planner/` | planner#9 | 현역 |\n", encoding="utf-8")  # R383
    body ="".join(f"| {n} | 23:5x | {text} |\n" for n, text in rows)
    (d / "VERDICTS-planner-37-20261013.md").write_text("| 판정 | 시각 | 내용 |\n|---|---|---|\n" + body, encoding="utf-8")
    (root / ".fable-team" / "seats-planner.json").write_text('{"_master": "planner#9", "_cards_wt": "wt"}', encoding="utf-8")


def sent_file(root):
    return root / ".fable-team" / "state" / "news-ledger" / "notified.txt"


def seed_sent(root, nums: str = "0") -> None:
    sent_file(root).parent.mkdir(parents=True, exist_ok=True)
    sent_file(root).write_text(nums + "\n", encoding="utf-8")


def mbox_lines(tmp) -> list[str]:
    f = tmp / "mbox.log"
    return f.read_text(encoding="utf-8").splitlines() if f.exists() else []


def set_mbox(root, rc: int) -> None:
    (root / ".fable-team" / "comm" / "mbox.sh").write_text(f'#!/usr/bin/env bash\necho "$@" >> "$FT_MBOX_LOG"\nexit {rc}\n', encoding="utf-8")


def test_number_in_ledger_text_sends_nothing_even_if_verdict_time_is_after_commit(env):  # ①
    repo, root, tmp = env
    commit(repo, LEDGER_WITH_1500)
    seed_sent(root)
    verdict_rows(root, [(1500, "(오빠) 새 지시")])
    nl.main(["run"])
    assert mbox_lines(tmp) == []


def test_rows_not_starting_with_oppa_send_nothing_even_if_number_missing(env):  # ②
    repo, root, tmp = env
    commit(repo, REAL)
    seed_sent(root)
    verdict_rows(root, [(1493, "문서 push 승인"), (1497, "실행 결과 (오빠 확인)")])
    nl.main(["run"])
    assert mbox_lines(tmp) == []


def test_three_missing_oppa_verdicts_make_one_bundled_message_within_300_chars(env):  # ③
    repo, root, tmp = env
    commit(repo, REAL)
    seed_sent(root)
    verdict_rows(root, [(1525, "(오빠) 가"), (1576, "(오빠) 나"), (1591, "(오빠) 다")])
    nl.main(["run"])
    lines = mbox_lines(tmp)
    msg = lines[0].split("ft-news-ledger ", 1)[1]
    assert len(lines) == 1 and all(str(n) in msg for n in (1525, 1576, 1591)) and len(msg) <= 300


def test_overflowing_bundle_is_cut_with_remaining_count(env):  # ③ 넘침
    repo, root, tmp = env
    commit(repo, REAL)
    seed_sent(root)
    verdict_rows(root, [(2000 + i, "(오빠) 결정") for i in range(80)])
    nl.main(["run"])
    lines = mbox_lines(tmp)
    msg = lines[0].split("ft-news-ledger ", 1)[1]
    assert len(lines) == 1 and len(msg) <= 300 and re.search(r" 외 \d+건", msg)


def test_same_tick_rerun_sends_nothing_more(env):  # ④
    repo, root, tmp = env
    commit(repo, REAL)
    seed_sent(root)
    verdict_rows(root, [(1525, "(오빠) 가")])
    nl.main(["run"])
    nl.main(["run"])
    assert len(mbox_lines(tmp)) == 1 and "1525" in sent_file(root).read_text(encoding="utf-8").split()


def test_first_run_without_notified_file_records_baseline_and_sends_nothing(env):  # ⑤
    repo, root, tmp = env
    commit(repo, REAL)
    verdict_rows(root, [(1525, "(오빠) 가"), (1493, "문서 push 승인")])
    nl.main(["run"])
    assert mbox_lines(tmp) == [] and set(sent_file(root).read_text(encoding="utf-8").split()) == {"1525", "1493"}


def test_mbox_failure_logs_error_keeps_numbers_unsent_and_news_still_publishes(env, caplog):  # ⑥
    repo, root, tmp = env
    commit(repo, REAL)
    nl.main(["run"])  # 뉴스 기준선
    seed_sent(root)
    verdict_rows(root, [(1525, "(오빠) 가")])
    set_mbox(root, 1)
    commit(repo, REAL.replace(ROW_OLD, ROW_NEW))
    with caplog.at_level(logging.ERROR, logger="ft_news_ledger"):
        assert nl.main(["run"]) == 0
    assert "1525" not in sent_file(root).read_text(encoding="utf-8").split() and len(news_files(root)) == 1
    assert any("알림" in r.getMessage() for r in caplog.records)
    set_mbox(root, 0)
    nl.main(["run"])
    assert len(mbox_lines(tmp)) == 2 and "1525" in sent_file(root).read_text(encoding="utf-8").split()


def test_pending_oppa_uses_digit_boundaries():
    assert nn.pending_oppa([("15", "(오빠) 가")], "판정 150 과 2150", set()) == [("15", "(오빠) 가")]
    assert nn.pending_oppa([("15", "(오빠) 가")], "판정 15 반영", set()) == []
